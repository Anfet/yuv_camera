# CAM 2 — камерный API и проверки источников

**Status:** BLOCKED
**Tier:** T2
**Owner:** —
**Depends on:** CAM 1 — принятый каркас.
**Probe:** windows+web

## Goal

Скопировать камерную инфраструктуру и подтвердить работу источников в новом пакете до удаления чего-либо из YUV.

## Architect Decision

1. Источник — `yuv_ffi/example/lib/camera/`; назначение — `lib/src/` с `impl/`, по карте 2.1. `heavy_blur.dart` не входит в пакет, переносится в CAM 3. Экспортировать только пять согласованных типов: YuvCameraFrame, YuvCameraFrameSource, YuvCameraView, YuvCameraViewController, YuvTransformView. Внутренние импортер, ориентация, цикл чтения и старт потока не экспортируются.
2. Это копирование с правкой импортов, а не переработка алгоритмов. Сохранить strides, lifecycle, ошибки, троттлинг и capture; публичный YUV импортировать только через `package:yuv_ffi/yuv_ffi.dart`. Исправить library в FlutterErrorDetails и iOS dartdoc по Q3: один iPhone/iOS 18.7/front/portrait+landscape; ориентационный код не менять.
3. Восемь файлов `example/test/camera/` (26 тестов) и `support/fake_camera.dart` скопировать в те же относительные каталоги нового example. Для проверки внутренних деталей тесты могут импортировать `package:yuv_camera/src/...`; пользователи получают только публичный entrypoint. Никакого сокращения assertions/helper-cleanup.
4. Скопировать `camera_capture_native_test.dart`, `camera_source_web_smoke_test.dart` и их фактические helpers/driver. Минимальный example компилирует публичный entrypoint и зависит от camera_desktop на desktop. ML Kit не нужен для этих двух целей.
5. Подготовить `_common.ps1`, `drive.ps1`/`drive.sh` и `windows.ps1`, `android.ps1`, `web.ps1`/`web.sh` с явными камерными targets. Не копировать операционные probes/reference или New-CiNativeBuild корня YUV; Flutter-сборка приложения собирает зависимость YUV. Windows-команда выполняет release-сборку и native capture; web — Chrome/JavaScript с fake-media флагами и camera source smoke. Обёртка drive требует exit 0 и `All tests passed`, завершает свои процессы.
6. CAM 2 уже проверяет источники; CAM 3 дополняет пример и общий гейт, а не откладывает все проверки API до конца переноса. При сбое импортов исправить пути; при изменении поведения остановиться с фактами, не менять backend YUV.

## Scope

`lib/`, `example/test/camera/`, fake helper, два integration targets/driver, зависимости минимального example, `tool/ci/` перечисленных платформ. YUV остаётся источником без правок.

## Constraints

Без собственного native-плагина, ML Kit в lib, обратной зависимости YUV → камера, обновления сторонних зависимостей и улучшения алгоритмов. Web-доказательство — только Chrome/JavaScript, без обещания Firefox/Safari/--wasm.

## Definition of Done

1. API содержит пять типов и не использует внутренности YUV — check: чтение exports/imports против карты 1 и 2.1; `flutter analyze` в корне/example — by: Executor.
2. Все 26 камерных тестов сохранены — check: из example `flutter test test/camera`, итог 26 passed, сопоставление восьми файлов/assertions с картой 2.2 — by: Executor.
3. Native capture проходит в Windows, Web smoke в Chrome/JS — check: из корня `pwsh -File tool/ci/windows.ps1` и `pwsh -File tool/ci/web.ps1`, exit 0 и PASS выбранной цели; лог содержит режим/target — by: Executor.
4. Probe windows+web имеет вердикты PASS без регрессии сценариев; исходные файлы YUV сохранены — check: отчёт пробы и diff собственного scope — by: Executor.

## Validation

Команды DoD; `dart format --line-length 150` изменённых Dart, analyze, `git diff --check`. Существующие проверки не переписывать ради passing count. Android-команда готовится здесь; запуск на Tablet входит в G1 CAM 3. Report содержит Validated at, 26/26 и два probe-вердикта; чужие изменения исключены.

## Executor Report

Заполняет Executor.
