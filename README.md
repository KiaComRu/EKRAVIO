# EKRAVIO / Экравио

[English](#english) · [Русский](#русский)

## English

**EKRAVIO** is a self-hosted prototype for monitoring Windows workstations. It brings live screen viewing and a recording archive into one web dashboard. A separate Windows probe reports whether there was recent user input in the current session without storing individual keystrokes.

- **Windows agent:** captures the active local desktop via DXGI and sends H.264 video to MediaMTX over WHIP. Capture starts after the operator confirms and stops if the session or desktop becomes unavailable.
- **Media server:** MediaMTX serves live video over WebRTC and records it on the server even when nobody is watching.
- **Web dashboard:** connects to MediaMTX so an operator can watch a live stream and browse recorded clips.

**Status:** Stage 0 lab prototype. Live viewing and server-side recording have been verified with synthetic video. End-to-end validation with a real desktop and remote sessions is still pending. Use a dedicated test desktop with the participant’s knowledge and permission.

To get started, follow the [prototype setup and test guide](docs/prototype.md), the [Windows installer and build instructions](docs/install-windows.md), or the [web dashboard guide](docs/web.md). These guides are currently in Russian.

## Русский

**Экравио** — прототип для наблюдения за рабочими станциями Windows на собственном сервере. В одной веб-панели можно смотреть экран в реальном времени и открывать записи из архива. Отдельная программа для Windows определяет, был ли недавно ввод в текущем сеансе, без сохранения отдельных нажатий клавиш.

- **Агент Windows:** захватывает активный локальный рабочий стол через DXGI и передаёт видео H.264 в MediaMTX по WHIP. Захват начинается после подтверждения оператором и останавливается, если сеанс или рабочий стол становится недоступен.
- **Медиасервер:** MediaMTX отдаёт прямую трансляцию по WebRTC и сохраняет запись на сервере, даже когда её никто не смотрит.
- **Веб-панель:** подключается к MediaMTX для просмотра прямой трансляции и записей.

**Статус:** лабораторный прототип, этап 0. Прямую трансляцию и запись на сервере проверили на синтетическом видео. Сквозная проверка с реальным рабочим столом и испытания в удалённых сеансах ещё впереди. Для испытаний используйте выделенный рабочий стол с ведома и согласия участника.

- [Запуск прототипа и результаты испытаний](docs/prototype.md)
- [Установка и сборка для Windows](docs/install-windows.md)
- [Подключение веб-панели к MediaMTX](docs/web.md)
- [Техническое задание](docs/Ekravio_TZ_for_Codex.md), [план реализации](docs/implementation-plan.md) и [архитектурные решения](docs/adr/0001-stage-0.md)
- [Фирменные материалы](brand/BRAND.md)
