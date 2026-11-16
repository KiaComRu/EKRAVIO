export function makeConnection(form) {
  const readOrigin = (name) => {
    const url = new URL(form.get(name).trim());
    const loopback = ['localhost', '127.0.0.1'].includes(url.hostname) && location.protocol === 'http:';
    if (url.protocol !== 'https:' && !(url.protocol === 'http:' && loopback)) {
      throw new Error('Для подключения нужен адрес HTTPS. HTTP доступен при локальном запуске панели.');
    }
    if (url.username || url.password || url.search || url.hash || url.pathname !== '/') {
      throw new Error('Укажите только адрес сервера и порт. Путь потока вводится отдельно.');
    }
    return url.origin;
  };
  const path = form.get('path').trim();
  if (!/^[\w-]+(?:\/[\w-]+)*$/.test(path) || path.length > 120) {
    throw new Error('Проверьте путь потока. Используйте латинские буквы, цифры, дефис, подчёркивание и косую черту.');
  }
  const user = form.get('user').trim();
  const password = form.get('password');
  if (!user || user.includes(':') || !password) throw new Error('Проверьте имя пользователя и пароль.');
  return { live: readOrigin('live'), playback: readOrigin('playback'), path, user, password };
}

function request(config, url, options = {}) {
  const bytes = new TextEncoder().encode(`${config.user}:${config.password}`);
  const encoded = btoa(Array.from(bytes, (byte) => String.fromCharCode(byte)).join(''));
  return fetch(url, {
    ...options, cache: 'no-store', redirect: 'error', credentials: 'omit',
    headers: { ...options.headers, Authorization: `Basic ${encoded}` },
  });
}

function check(response, missing) {
  if (response.ok) return response;
  if ([401, 403].includes(response.status)) throw new Error('Сервер отклонил доступ. Проверьте пароль и права просмотра.');
  if (response.status === 404) throw new Error(missing);
  throw new Error(`Медиасервер вернул ошибку ${response.status}.`);
}

function iceServers(value) {
  const links = value?.matchAll(/<((?:stun|stuns|turn|turns):[^>]+)>;\s*rel="ice-server"(?:;\s*username=("(?:\\.|[^"])*");\s*credential=("(?:\\.|[^"])*");\s*credential-type="password")?/gi) ?? [];
  return Array.from(links, ([, urls, username, credential]) => username
    ? { urls, username: JSON.parse(username), credential: JSON.parse(credential) }
    : { urls });
}

function gather(peer, signal) {
  if (peer.iceGatheringState === 'complete') return Promise.resolve();
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => finish(), 3500);
    const changed = () => { if (peer.iceGatheringState === 'complete') finish(); };
    const cancelled = () => finish(signal.reason);
    function finish(error) {
      clearTimeout(timer);
      peer.removeEventListener('icegatheringstatechange', changed);
      signal.removeEventListener('abort', cancelled);
      if (error) reject(error); else resolve();
    }
    peer.addEventListener('icegatheringstatechange', changed);
    signal.addEventListener('abort', cancelled, { once: true });
    if (signal.aborted) cancelled();
  });
}

export function openLive(config, video, onStatus) {
  const controller = new AbortController();
  const { signal } = controller;
  const endpoint = `${config.live}/${config.path}/whep`;
  let peer;
  let session;
  let seenFrames = false;
  const timer = setTimeout(() => fail(new Error('Истекло время ожидания видео. Проверьте поток и сетевой доступ к MediaMTX.')), 18000);
  const playing = () => {
    clearTimeout(timer);
    seenFrames = true;
    onStatus('Прямой эфир', true);
  };
  video.addEventListener('playing', playing, { once: true });

  function close() {
    if (signal.aborted) return;
    clearTimeout(timer);
    controller.abort();
    video.removeEventListener('playing', playing);
    peer?.close();
    video.srcObject = null;
    if (session) void request(config, session, { method: 'DELETE', signal: AbortSignal.timeout(3500) }).catch(() => {});
  }

  function fail(error) {
    if (signal.aborted) return;
    close();
    onStatus(error instanceof TypeError ? 'Сервер недоступен из браузера. Проверьте HTTPS, CORS и сетевой доступ.' : error.message, false);
  }

  async function start() {
    const options = check(await request(config, endpoint, { method: 'OPTIONS', signal }), 'Путь потока отсутствует на сервере.');
    peer = new RTCPeerConnection({ iceServers: iceServers(options.headers.get('Link')) });
    peer.addTransceiver('video', { direction: 'recvonly' });
    peer.ontrack = ({ streams, track }) => {
      if (signal.aborted) return;
      video.srcObject = streams[0] ?? new MediaStream([track]);
      video.play().catch(() => {});
      track.addEventListener('ended', () => fail(new Error('Трансляция завершилась.')), { once: true });
    };
    peer.onconnectionstatechange = () => {
      if (peer.connectionState === 'failed' || (seenFrames && peer.connectionState === 'disconnected')) {
        fail(new Error('Связь с видеопотоком прервалась. Откройте экран снова.'));
      }
    };
    await peer.setLocalDescription(await peer.createOffer());
    await gather(peer, signal);
    const answer = check(await request(config, endpoint, {
      method: 'POST', headers: { 'Content-Type': 'application/sdp' }, body: peer.localDescription.sdp, signal,
    }), 'Поток ещё не опубликован. Запустите захват на компьютере с агентом.');
    const address = answer.headers.get('Location');
    if (address) {
      const candidate = new URL(address, endpoint);
      if (candidate.origin === config.live && candidate.pathname.startsWith(`/${config.path}/whep/`)) session = candidate.href;
    }
    await peer.setRemoteDescription({ type: 'answer', sdp: await answer.text() });
  }
  start().catch(fail);
  return close;
}

export async function listRecordings(config, date, signal) {
  const start = new Date(`${date}T00:00:00`);
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  const query = new URLSearchParams({ path: config.path, start: start.toISOString(), end: end.toISOString() });
  const response = await request(config, `${config.playback}/list?${query}`, { signal });
  if (response.status === 404) return [];
  const rows = await check(response).json();
  if (!Array.isArray(rows)) throw new Error('Сервер вернул неизвестный формат архива.');
  return rows.filter((row) => Number.isFinite(Date.parse(row?.start)) && Number.isFinite(row?.duration) && row.duration > 0)
    .map(({ start, duration }) => ({ start, duration }));
}

export async function loadRecording(config, recording, signal) {
  const query = new URLSearchParams({ path: config.path, start: recording.start, duration: recording.duration, format: 'mp4' });
  const response = check(await request(config, `${config.playback}/get?${query}`, { signal }), 'Запись отсутствует в архиве.');
  const limit = 96 * 1024 * 1024;
  if (Number(response.headers.get('Content-Length')) > limit) throw new Error('Запись превышает лимит загрузки в панели (96 МБ).');
  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > limit) throw new Error('Запись превышает лимит загрузки в панели (96 МБ).');
      chunks.push(value);
    }
    return new Blob(chunks, { type: 'video/mp4' });
  } finally {
    await reader.cancel().catch(() => {});
  }
}
