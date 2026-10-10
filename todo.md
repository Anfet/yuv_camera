# yuv_camera 0.0.1 — подготовка выпуска

## Цель и текущее состояние

Создать самостоятельный Flutter-пакет камеры поверх `yuv_ffi: ^0.5.2`. Пять публичных типов: YuvCameraFrame, YuvCameraFrameSource, YuvCameraView, YuvCameraViewController, YuvTransformView. ML Kit и camera_desktop — зависимости примера, не lib. Собственный native-плагин не нужен; геометрия, презентер, шейдер и native/WASM операции остаются в YUV.

Checkout — `D:\.projects\yuv_ffi_camera`, рабочая ветка `dev`, remote — `https://github.com/Anfet/yuv_camera`, лицензия MIT. Исходно здесь README и LICENSE; Architect добавил план/карточки, реализация ещё не начата. Локальные правила и каркас создаёт CAM 1. Источник карты — [camera-extraction.md](../yuv_ffi/doc/camera-extraction.md); общий план пары — [todo YUV](../yuv_ffi/todo.md). PREP 1 там в REVIEW, его принимает независимый Reviewer.

## Этапы

| Этап | Работа | Условие завершения |
| --- | --- | --- |
| 0. Подготовка | Приёмка PREP 1 в YUV, решения Engineer, декомпозиция | Карта принята; карточки готовы. |
| 1. Разделение | CAM 1 → CAM 2 → CAM 3 → YUV 1 → YUV 2 → CAM 4 | G1 PASS, обе стороны приняты, разделённая пара проверена локально. |
| 2. Кандидаты | Заморозка обоих SHA; платформы/устройства/CI, состав публикации | Точные кандидаты проходят обязательные проверки. |
| 3. Выпуск | Сначала yuv_ffi 0.5.2, затем yuv_camera 0.0.1 | Engineer выпустил оба; независимый потребитель опубликованной пары проверен. |

## Локальный дашборд yuv_camera — этап 1

**Общая очередь обоих репозиториев и текущий шаг:** [дашборд YUV](../yuv_ffi/todo.md#общий-дашборд-обоих-репозиториев). Сейчас PREP 1 там ожидает ревью; следующая работа здесь — CAM 1 после его принятия. Ни одна из карточек ниже ещё не исполнялась: BLOCKED означает ожидание зависимости.

| ID | Status | Tier | Owner | Depends on | Summary / next step |
| --- | --- | --- | --- | --- | --- |
| [CAM 1](tasks/0.0.1/CAM-1.md) | BLOCKED | T2 | — | yuv_ffi: PREP 1 | Каркас и metadata; ждёт приёмки карты. |
| [CAM 2](tasks/0.0.1/CAM-2.md) | BLOCKED | T2 | — | CAM 1 | Копия API, 26 тестов, Windows/Web sources. |
| [CAM 3](tasks/0.0.1/CAM-3.md) | BLOCKED | T2 | — | CAM 2 | Пример/ML Kit, ещё 8 тестов, G1 (34/34 + Windows/Android/Web). |
| [CAM 4](tasks/0.0.1/CAM-4.md) | BLOCKED | T2 | — | CAM 3; yuv_ffi: YUV 2 | Workflows с точным SHA YUV, docs и локальная пара. |

Карточки YUV 1/2 находятся в исходном репозитории и видны в общем дашборде. Зависимость закрывается после приёмки, подтверждённой карточкой либо COMPLETION/git history. Собственный Base и Validated at для каждого checkout; при проверке пары Report называет оба результата. Карточки подготовлены для исполнения после приёмки PREP 1 и команды Engineer. При смене статуса карточка и этот локальный дашборд коммитятся вместе; CAM-строка общего обзора в YUV синхронизируется отдельным коммитом того же завершения работы.

## Решения Engineer (10.10.2026)

- Q1: существующий remote Anfet/yuv_camera и MIT; имя/публикация `yuv_camera 0.0.1` на pub.dev. Description — `Flutter camera package built on yuv_ffi for capturing and displaying YUV camera frames.` URL repository/homepage — remote, issues — `/issues`. CI до публикации YUV получает его точный SHA вторым checkout; overrides ignored. Фактические runners/права проверяются CAM 4; отсутствие workflows в исходном каркасе не считается отсутствием доступа.
- Q2: отдельную YUV-пробу физического шейдера не вводить; device-check пары — этап 2.
- Q3: APPLE 1 актуален: один iPhone, iOS 18.7, front, portrait/landscape; исправить устаревший dartdoc без изменения алгоритма.
- Q4: использовать этот checkout `yuv_ffi_camera` на dev, свои правила/план/память. Пакет называется `yuv_camera`.

## Правила цикла

Общие правила — `D:\.projects\AGENTS.md`, `ENGINEERING_PROTOCOL.md` и файл роли. Работа последовательно в основной копии dev, без worktree/пуловых веток и делегирования. Не менять чужие файлы; коммитить собственные paths. Architect не принимает PREP 1 и не исполняет перенос. После DONE карточка удаляется, одна строка в COMPLETION; dashboard и header всегда согласованы.

Сначала копирование и G1, затем удаление в YUV. Зависимость pubspec — ^0.5.2, временные path overrides не отслеживаются и не публикуются. Внутренние документы русские; README/dartdoc/description/CHANGELOG/comments/errors/commits английские. Версии camera и остальных сторонних пакетов не обновлять в ходе переноса.

CI без автозапуска dev: только теги ci/<platform>/<label>, ci/all/<label> или dispatch. Внешние прогоны — этап 2; scripts локальных проверок создаются в CAM 2/3. Drive только через drive.ps1/drive.sh, требуется exit 0 и All tests passed. Устройства/пути SDK — актуальный MACHINES.md.

## Гейт этапа 2 (ещё не выполнен)

Карточки этапа 2 Architect расписывает после приёмки этапа 1 на фактических scripts, runners и кандидатах; сейчас это требования гейта, не исполнимые задачи.

- Native capture на Windows, Android, macOS, iOS и Linux; Web camera source — Chrome/JavaScript, не расширять на Safari/Firefox/--wasm без доказательства.
- iOS BGRA import; desktop preview/capture и camera_flow C1–C4 в окружениях карты, без выдачи fake-platform за физическую камеру.
- Device-check пары на Pixel 3 и согласованном iPhone/Mac: schema DEVICE-1, семь шагов, отображение/ориентация/capture. Запуск физического iPhone только по отдельной команде Engineer.
- CI получает кандидата YUV по точному SHA; публикационный dry-run на чистом кандидате; проверка metadata/лицензии/состава обоих пакетов. Release SHA/теги/публикация — Engineer.
