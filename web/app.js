import { makeConnection, openLive, listRecordings, loadRecording } from './media.js';

const $ = (selector, root = document) => root.querySelector(selector);
const main = $('#main');
const playerDialog = $('#player-dialog');
const player = $('#player');
const connectionDialog = $('#connection-dialog');
const form = $('#connection-form');
const pages = { overview: 'Обзор', screens: 'Экраны', archive: 'Архив', activity: 'Активность' };
const paths = {
  grid: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
  screen: '<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8m-4-4v4"/>',
  archive: '<rect x="3" y="4" width="18" height="4" rx="1"/><path d="M5 8v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8m-9 4h4"/>',
  activity: '<path d="M3 13h4l3-8 4 14 3-6h4"/>',
  settings: '<circle cx="12" cy="12" r="5"/><path d="M12 2v4m0 12v4M2 12h4m12 0h4M5 5l3 3m8 8 3 3M5 19l3-3m8-8 3-3"/>',
  plug: '<path d="M10 4v5m4-5v5m-6 0h8v3a4 4 0 0 1-8 0zm4 7v4"/>',
  server: '<rect x="4" y="4" width="16" height="7" rx="2"/><rect x="4" y="13" width="16" height="7" rx="2"/><path d="M8 7.5h1m-1 9h1m4-9h3m-3 9h3"/>',
  play: '<path d="m9 5 11 7-11 7z"/>',
};
const icon = (key) => `<svg class="icon" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${paths[key]}</svg>`;
document.querySelectorAll('[data-icon]').forEach((node) => { node.outerHTML = icon(node.dataset.icon); });

const clock = new Intl.DateTimeFormat('ru-RU', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
const now = new Date();
const date = [now.getFullYear(), String(now.getMonth() + 1).padStart(2, '0'), String(now.getDate()).padStart(2, '0')].join('-');
const state = { page: 'overview', connection: null, date };
let closeLive;
let listRequest;
let movieRequest;
let objectUrl;
let visibilityTimer;

function heading(title, detail) {
  return `<div class="heading"><div><h1>${title}</h1><p>${detail}</p></div></div>`;
}

function emptyPanel(symbol, title, detail, action = '') {
  return `<section class="blank">${icon(symbol)}<h2>${title}</h2><p>${detail}</p>${action}</section>`;
}

function connectionPrompt() {
  return emptyPanel('server', 'Сервер не подключён', 'Укажите адрес MediaMTX и учётные данные просмотра.',
    `<button type="button" class="button primary" data-connect>${icon('plug')} Подключить сервер</button>`);
}

function streamPanel() {
  return `<section class="panel"><div class="panel-header"><div><h2>Поток MediaMTX</h2><p id="stream-path"></p></div><button type="button" class="button primary" data-screen>${icon('play')} Открыть эфир</button></div></section>`;
}

function archivePage() {
  return `<section class="panel"><div class="panel-header"><div><h2>Записи экрана</h2><p id="stream-path"></p></div><div class="filters"><label>Дата <input type="date" id="archive-date"></label></div></div><div id="recordings" aria-live="polite"></div></section>`;
}

function render() {
  listRequest?.abort();
  const page = state.page;
  const connection = state.connection;
  $('#breadcrumb').textContent = pages[page];
  document.title = `Экравио — ${pages[page]}`;
  document.querySelectorAll('[data-page]').forEach((node) => {
    if (node.dataset.page === page) node.setAttribute('aria-current', 'page');
    else node.removeAttribute('aria-current');
  });
  $('#mode-label').textContent = connection ? 'Сервер настроен' : 'Сервер не подключён';
  $('#connect-label').textContent = connection ? 'Настроить сервер' : 'Подключить сервер';
  $('#workspace-detail').textContent = connection ? new URL(connection.live).host : 'Адрес не указан';

  if (page === 'activity') {
    main.innerHTML = heading('Активность', 'Статистика ввода пользователя.') +
      emptyPanel('activity', 'Нет данных об активности', 'Данные активности пока доступны в локальном сеансе Windows.');
    return;
  }
  if (page === 'archive') {
    main.innerHTML = heading('Архив', 'Найдите запись выбранного потока по дате.') + (connection ? archivePage() : connectionPrompt());
  } else {
    main.innerHTML = heading(pages[page], 'Просмотр экрана с сервера MediaMTX.') + (connection ? streamPanel() : connectionPrompt());
  }
  if ($('#stream-path')) $('#stream-path').textContent = connection.path;
  if ($('#archive-date')) {
    $('#archive-date').value = state.date;
    void renderArchive();
  }
}

function errorMessage(error) {
  return error instanceof TypeError ? 'Архив недоступен из браузера. Проверьте HTTPS, CORS и адрес сервера.' : error.message;
}

async function renderArchive() {
  const box = $('#recordings');
  const connection = state.connection;
  if (!box || !connection) return;
  listRequest?.abort();
  const request = new AbortController();
  listRequest = request;
  box.innerHTML = '<p class="panel-message">Загрузка записей…</p>';
  let rows;
  try {
    rows = await listRecordings(connection, state.date, AbortSignal.any([request.signal, AbortSignal.timeout(15000)]));
  } catch (error) {
    if (request.signal.aborted) return;
    const message = document.createElement('p');
    message.className = 'panel-message';
    message.textContent = errorMessage(error);
    box.replaceChildren(message);
    return;
  }
  if (request.signal.aborted) return;
  if (!rows.length) {
    box.innerHTML = '<p class="panel-message">За выбранную дату записей нет.</p>';
    return;
  }
  box.innerHTML = '<div class="recordings-heading"><span>Начало записи</span><span>Длительность</span><span></span></div>';
  for (const recording of rows) {
    const row = document.createElement('div');
    row.className = 'recording-row';
    const seconds = Math.round(recording.duration);
    row.innerHTML = `<strong>${clock.format(new Date(recording.start))}</strong><span>${Math.floor(seconds / 60)} мин ${seconds % 60} сек</span><button class="button secondary">${icon('play')} Смотреть</button>`;
    $('button', row).addEventListener('click', () => void playRecording(connection, recording));
    box.append(row);
  }
}

function cleanPlayer() {
  clearTimeout(visibilityTimer);
  closeLive?.();
  closeLive = undefined;
  movieRequest?.abort();
  movieRequest = undefined;
  player.pause();
  player.srcObject = null;
  player.removeAttribute('src');
  player.load();
  if (objectUrl) URL.revokeObjectURL(objectUrl);
  objectUrl = undefined;
  $('#download').hidden = true;
  $('#download').removeAttribute('href');
}

function preparePlayer(connection, detail) {
  cleanPlayer();
  $('#player-title').textContent = connection.path;
  $('#player-detail').textContent = detail;
  $('#player-status').textContent = 'Подготовка видео…';
  playerDialog.showModal();
}

function playScreen() {
  if (!state.connection) return;
  preparePlayer(state.connection, 'Прямой эфир · WebRTC');
  closeLive = openLive(state.connection, player, (message) => {
    $('#player-status').textContent = message;
  });
}

async function playRecording(connection, recording) {
  preparePlayer(connection, `Архив · ${clock.format(new Date(recording.start))}`);
  const request = new AbortController();
  movieRequest = request;
  try {
    const blob = await loadRecording(connection, recording, AbortSignal.any([request.signal, AbortSignal.timeout(90000)]));
    if (request.signal.aborted) return;
    objectUrl = URL.createObjectURL(blob);
    player.src = objectUrl;
    $('#player-status').textContent = 'Видеозапись готова к просмотру';
    const download = $('#download');
    download.href = objectUrl;
    download.download = 'ekravio-recording.mp4';
    download.hidden = false;
    player.play().catch(() => {});
  } catch (error) {
    if (!request.signal.aborted) $('#player-status').textContent = errorMessage(error);
  }
}

function route() {
  const slug = location.hash.slice(1);
  state.page = Object.hasOwn(pages, slug) ? slug : 'overview';
  if (playerDialog.open) playerDialog.close();
  render();
}

document.addEventListener('click', (event) => {
  if (event.target.closest('[data-connect]')) {
    $('#connection-error').hidden = true;
    $('#reset-connection').hidden = !state.connection;
    connectionDialog.showModal();
  }
  const close = event.target.closest('[data-close]');
  if (close) document.getElementById(close.dataset.close).close();
  if (event.target.closest('[data-screen]')) playScreen();
});

main.addEventListener('change', (event) => {
  if (event.target.id === 'archive-date' && event.target.value) {
    state.date = event.target.value;
    void renderArchive();
  }
});

form.addEventListener('submit', (event) => {
  event.preventDefault();
  try {
    state.connection = makeConnection(new FormData(form));
    form.elements.password.value = '';
    connectionDialog.close();
    render();
  } catch (error) {
    const message = $('#connection-error');
    message.textContent = error instanceof TypeError ? 'Проверьте адреса MediaMTX.' : error.message;
    message.hidden = false;
  }
});

$('#reset-connection').addEventListener('click', () => {
  state.connection = null;
  form.reset();
  connectionDialog.close();
  render();
});

connectionDialog.addEventListener('close', () => { form.elements.password.value = ''; });
playerDialog.addEventListener('close', cleanPlayer);
player.addEventListener('error', () => { $('#player-status').textContent = 'Браузер не смог воспроизвести это видео.'; });
window.addEventListener('hashchange', route);
window.addEventListener('pagehide', cleanPlayer);
document.addEventListener('visibilitychange', () => {
  clearTimeout(visibilityTimer);
  if (document.hidden && closeLive) visibilityTimer = setTimeout(() => playerDialog.close(), 30000);
});
route();
