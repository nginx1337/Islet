# Безопасность и приватность Islet

[English below](#english)

## Что Islet делает с вашими данными

- **Всё остаётся на Mac.** Нет аналитики, телеметрии и учётных записей. Единственный сетевой запрос — скачивание обложки Spotify в запасном режиме: только `https`, без cookies и кэша на диске (`URLSession` с эфемерной конфигурацией), не больше 8 МБ.
- **Что играет.** Название, исполнитель, обложка и позиция берутся из системного MediaRemote через встроенный [mediaremote-adapter](Vendor/mediaremote-adapter) и живут только в памяти. Истории прослушивания нет, обложки кэшируются в памяти (последние 20) и на диск не пишутся.
- **Звук для полосок.** Если вы разрешили «Запись системного звука», Islet подключает Core Audio process tap: закрытый (`isPrivate`), без приглушения звука. Из звука считается только громкость в четырёх полосах частот, звук не записывается, не сохраняется и никуда не передаётся. Захват работает, лишь пока остров виден и трек играет. Входы самого устройства вывода (микрофон USB-гарнитуры или аудиоинтерфейса) отключаются и не читаются, поэтому микрофон не открывается.
- **Управление плеерами.** В запасном режиме Islet отправляет AppleScript только «Музыке» и Spotify, только если они уже открыты (плееры не запускаются), с таймаутом 2 секунды.
- **Мышь и клавиатура.** Положение курсора отслеживается, только пока остров виден, и только чтобы раскрывать его при наведении; никуда не записывается. Нажатия клавиш читаются лишь в окне настроек, пока вы записываете сочетание. Щелчок колёсиком по острову ловит локальный монитор событий (видит только клики по окнам Islet). Пока остров спрятан, глобальный монитор ждёт только щелчка колёсиком и читает лишь номер кнопки и положение курсора; когда остров показан, его нет. Глобальное сочетание регистрируется через Carbon `RegisterEventHotKey`, без универсального доступа.
- **Живые активности** (вторая капсула рядом с островом). Всё локально, без сети и без новых разрешений. Таймер и секундомер — только время в памяти. «Зарядка» читает состояние батареи через публичный IOKit. «Наушники» слушает смену устройства вывода в Core Audio и показывает название Bluetooth-устройства (Bluetooth напрямую не используется, уровень заряда не читается). «Прогресс файлов» (по умолчанию выключено) подписывается через `Progress` на операции с файлами в «Загрузках», «Рабочем столе», «Документах» и на подключённых томах и читает только долю выполнения и тип операции, без имён и содержимого файлов. Каждый источник включается отдельно в настройках и не работает, пока выключен. Внешние программы не запускаются, закрытые API не используются.
- **Установка и обновление.** Обновления нет ни автоматического, ни по кнопке: приложение не ходит в сеть за новыми версиями. Новую версию вы скачиваете сами и ставите `scripts/install.sh`. Он ставит новую сборку вместо старой: проверяет подпись и идентификатор собранного приложения, закрывает запущенную копию, а старую версию в «Программах» переносит в Корзину (удаляет только то, что действительно Islet с тем же идентификатором, иначе останавливается). Запущенная новая копия просит закрыться другие копии Islet (обычное завершение, не принудительное).
- **Проверка исходников.** `scripts/audit.sh` (запускается и в CI) падает, если появляется новый сетевой API, запуск программы, загрузка кода во время работы, разрешение или стороннее обращение к сети вне перечня из этого файла: сеть только в загрузке обложки Spotify, запуск программ только у адаптера (`perl`), AppleScript только в запасном режиме, в `IsletCore` нет UI и сетевых фреймворков, нет сторонних пакетов. Кроме того: `Info.plist` не ослабляет App Transport Security, ни один скрипт не скачивает из сети, глобальные мониторы событий не читают клавиатуру, нет перехвата событий (event tap) и прямого доступа к устройствам ввода. CI дополнительно проверяет, что у релизной сборки включён hardened runtime и нет отладочных entitlements (`get-task-allow`, отключение проверки библиотек, JIT).
- **Настройки.** Числа из настроек (смещение, размеры, задержка скрытия) при запуске зажимаются в допустимые пределы: их можно поменять снаружи через `defaults write`, и значение вроде NaN или миллиона не должно уводить остров за экран или ломать таймеры.
- **Журнал.** В системный журнал (`app.islet`) попадают только состояния и ошибки, без названий треков.
- **Процессы.** Адаптер запускается как `/usr/bin/perl` со встроенным скриптом. При выходе Islet его останавливает; оставшиеся после сбоя процессы Islet находит по пути к своему скрипту и останавливает только их.

## Разрешения

| Разрешение | Зачем | Обязательно |
|---|---|---|
| Запись системного звука | Полоски показывают настоящий звук | Нет: без него полоски просто анимируются |
| Автоматизация → «Музыка», Spotify | Только запасной режим | Нет |
| Объекты входа | «Открывать при входе» | Нет |

Запись экрана, микрофон, универсальный доступ и полный доступ к диску **не нужны**.

## Сборка и подпись

- Hardened runtime. Entitlements: `com.apple.security.automation.apple-events` (запасной режим) и `com.apple.security.device.audio-input` (process tap).
- Песочницы нет: Islet запускает системный `perl` для адаптера и отправляет Apple Events.
- Сторонний код один: mediaremote-adapter (BSD-3-Clause), без изменений, в `Vendor/`. Фреймворк адаптера загружает `perl`, само приложение с ним не линкуется.
- Отладочный режим `--render-preview` есть только в отладочной сборке; CI проверяет, что в релизе нет ни его, ни локальных путей.
- Сборка из репозитория подписана ad-hoc. Для распространения нужна подпись Developer ID и нотаризация.

## Как сообщить об уязвимости

Не публикуйте подробности в открытых issues. Воспользуйтесь закрытым сообщением об уязвимости на GitHub (вкладка **Security → Report a vulnerability**). Опишите шаги воспроизведения и версию macOS.

---

## English

- **Everything stays on the Mac.** No analytics, telemetry or accounts. The only network request downloads Spotify artwork in fallback mode: `https` only, ephemeral session (no cookies, no disk cache), at most 8 MB.
- **What is playing** comes from MediaRemote through the bundled [mediaremote-adapter](Vendor/mediaremote-adapter) and is kept in memory only: no listening history, artwork cached in memory (last 20), never written to disk.
- **Sound for the bars.** With System Audio Recording allowed, Islet uses a private, unmuted Core Audio process tap and measures only loudness in four frequency bands. Nothing is recorded, stored or sent. It runs only while the island is visible and a track plays. The output device's own inputs (a USB headset or interface microphone) are switched off and never read.
- **Player control.** In fallback mode Islet sends AppleScript only to Music and Spotify, only while they are already open, with a 2-second timeout.
- **Mouse and keyboard.** The pointer position is used only while the island is visible, to expand it on hover, and is not stored. Keys are read only in Settings while you record a shortcut; a wheel click on the island is caught by a local event monitor (it sees only clicks on Islet's own windows); while the island is hidden, a global monitor waits for a wheel click only and reads just the button number and the pointer position, and it is removed once the island is shown; the global shortcut uses Carbon `RegisterEventHotKey`, no Accessibility access.
- **Live activities** (the second capsule beside the island). All local: no network, no new permissions. Timer and stopwatch are just times in memory. "Power" reads the battery state through public IOKit. "Headphones" listens for the output device changing in Core Audio and shows the name of a Bluetooth device (Bluetooth itself is not used, the battery level is not read). "File progress" (off by default) subscribes through `Progress` to file operations in Downloads, Desktop, Documents and mounted volumes and reads only the completed fraction and the kind of operation, never file names or contents. Each source has its own switch in Settings and does nothing while it is off. No external programs are run and no private APIs are used.
- **Install and update.** There is no update, neither automatic nor on a button: the app does not go online for new versions. You download a new version yourself and install it with `scripts/install.sh`, which puts a new build in place of the old one: it verifies the signature and bundle identifier of the build, quits the running copy and moves the old version in Applications to the Trash (it only touches something that really is Islet with the same identifier, otherwise it stops). A newly started copy asks other running Islets to quit (a normal quit, not a kill).
- **Source audit.** `scripts/audit.sh` (also run in CI) fails when a new network API, program launch, run-time code loading or permission appears outside what this file lists: network only for the Spotify artwork, program launch only for the adapter (`perl`), AppleScript only in fallback mode, no UI or network frameworks in `IsletCore`, no third-party packages. It also checks that `Info.plist` does not weaken App Transport Security, no script downloads anything, no global event monitor reads the keyboard, and nothing uses event taps or raw input devices. CI also checks that the release build has the hardened runtime and no debugging entitlements (`get-task-allow`, disabled library validation, JIT).
- **Settings.** Numbers read from the settings (offset, sizes, hide delay) are clamped to the allowed range at launch: they can be changed from outside with `defaults write`, and a NaN or a huge value must not move the island off screen or break its timers.
- **Log.** The system log (`app.islet`) gets states and errors only, never track titles.

Permissions: System Audio Recording (optional, for real bars), Automation for Music/Spotify (fallback only), Login Items (optional). No Screen Recording, Microphone, Accessibility or Full Disk Access.

Build: hardened runtime; entitlements `automation.apple-events` and `device.audio-input`; not sandboxed (runs the system `perl` for the adapter and sends Apple Events); one third-party component, mediaremote-adapter (BSD-3-Clause), unmodified; ad-hoc signature (sign with a Developer ID and notarize to distribute).

**Reporting a vulnerability:** please do not open a public issue. Use GitHub's private vulnerability reporting (**Security → Report a vulnerability**) with steps to reproduce and your macOS version.
