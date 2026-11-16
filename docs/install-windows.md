# Установщики Экравио 0.1.0 для Windows x64

Лабораторные сборки этапа 0. Оба EXE без подписи издателя. Контрольные суммы лежат в `SHA256SUMS.txt` рядом с установщиками.

## Сервер

1. Запустите `Ekravio-Server-Setup-x64.exe` с правами администратора. В пакете есть MediaMTX 1.21.3 и WinSW 2.12.0. WinSW использует .NET Framework 4.6.1 или новее. [.NET Framework в Windows](https://learn.microsoft.com/en-us/dotnet/framework/install/on-windows-10).
2. В меню «Пуск» откройте **Ekravio Server - Configure and start**. Задайте два разных случайных пароля длиной от 16 символов. Для `publisher` используйте латинские буквы, цифры, дефис и подчёркивание. У `viewer` отдельный пароль.
3. После настройки служба `Ekravio.Media` запускается автоматически вместе с Windows. По умолчанию сервер слушает `127.0.0.1`. Откройте `http://127.0.0.1:8889/stage0/` для просмотра или `http://127.0.0.1:9996/list?path=stage0` для списка записей. Войдите как `viewer`.

Конфигурация, журнал и записи находятся в `%ProgramData%\Ekravio\Server`. Экранный поток записывается независимо от браузера, срок хранения в прототипе составляет один час. При обновлении служба останавливается на время замены файлов. После обновления откройте **Configure and start**. Штатное удаление останавливает и удаляет службу. Каталог данных сохраняется.

Для агента на другом ПК при первой настройке укажите адрес сервера и TLS-сертификат. Пример команды для Windows PowerShell от администратора с путём установки по умолчанию:

```powershell
& "$env:ProgramFiles\Ekravio\Server\Server-Manager.ps1" `
    -BindAddress 192.168.1.24 -ServerName ekravio.example.org `
    -Certificate 'C:\lab\server.crt' -CertificateKey 'C:\lab\server.key'
```

Агент и браузер должны доверять сертификату, выписанному на указанное имя. Разрешите в тестовой сети TCP 8889, TCP 9996 и UDP 8189. Установщик не меняет правила брандмауэра. Для этой настройки адрес WHIP — `https://ekravio.example.org:8889/stage0/whip`.

## Агент

1. Установите GStreamer 1.28.7 MSVC x64 с D3D11, x264, `h264parse` и `whipclientsink`. Для x264 выберите соответствующие GPL restricted plugins в установщике. [GStreamer 1.28.7](https://gstreamer.freedesktop.org/pkg/windows/1.28.7/).
2. Запустите `Ekravio-Agent-Setup-x64.exe` под пользователем, который будет выполнять захват. Приложения .NET собраны с включённой средой выполнения. Установка агента не требует администратора.
3. В меню «Пуск» откройте **Ekravio Agent - Local DXGI probe** для проверки захвата в памяти либо **Ekravio Agent - Start capture** для передачи потока. Укажите адрес WHIP и пароль `publisher`. Для сервера на том же ПК достаточно принять адрес по умолчанию. Подтвердите запуск `START` на тестовом рабочем столе. `Ctrl+C` завершает сеанс захвата.
4. **Ekravio Agent - Input activity probe** запускает отдельную 90-секундную пробу. Она печатает факт активности по текущему сеансу и его доступность.

Запуск агента ручной. Удаление доступно через «Установленные приложения». Отдельно установленный GStreamer удаляется собственным установщиком. Сквозной прогон реального экрана, RDP и AnyDesk остаётся в матрице испытаний.

## Пересборка

Сборка требует .NET SDK 11 и [Inno Setup 6.4.3](https://github.com/jrsoftware/issrc/releases/tag/is-6_4_3). Подготовьте [MediaMTX 1.21.3 для Windows amd64](https://github.com/bluenviron/mediamtx/releases/tag/v1.21.3), [WinSW.NET461.exe версии 2.12.0](https://github.com/winsw/winsw/releases/tag/v2.12.0) и `LICENSE.txt` WinSW из этого тега. Скрипт сверяет SHA-256 бинарников сервера перед сборкой.

```powershell
.\deploy\windows\installer\Build-Installers.ps1 `
    -InnoCompiler 'C:\lab\inno\ISCC.exe' `
    -MediaMtxDirectory 'C:\lab\mediamtx' `
    -WinSW 'C:\lab\WinSW.NET461.exe' `
    -WinSWLicense 'C:\lab\WinSW-LICENSE.txt'
```

Результат сохраняется в `dist\windows`.
