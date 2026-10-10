# CAM 3 — пример камеры, перенос покрытия и гейт G1

**Status:** BLOCKED
**Tier:** T2
**Owner:** —
**Depends on:** CAM 2 — принятые API и источники.
**Probe:** windows+web

## Goal

Перенести демонстрацию, ML Kit и все камерные проверки; дать проверяемое разрешение на последующее удаление камеры из YUV.

## Architect Decision

1. Скопировать экраны camera/device-check, heavy_blur, ext.dart, face_rect_paint, диагностические entrypoints и остальные тесты по карте 2.1–2.5. ML Kit, camera_desktop и демонстрационное размытие — только example. Пакет camera_desktop регистрируется Flutter по зависимости приложения; собственной регистрации в lib нет.
2. Добавить минимальный экран результата capture через YuvFrameView с распознаванием лица для C4. Перенести C1–C4; C5 редактора остаётся в YUV и реализуется в YUV 1. Device-check сохраняет 7 шагов и DEVICE-1, не смешивается с операционными пробами.
3. В example остаётся раскладка тестов «путь в путь»: 26 камерных + 5 device-check + 3 toInputImage = 34 теста. Ни один исходный assertion не удаляется. Скопировать ios_bgra_camera_frame_test и desktop_camera_preview_smoke_test; example_camera_flow_test переименовать в camera_flow_test после отделения C5. iOS BGRA и физический flow не включать молча в автоматический glob: они остаются ручными целями этапа 2.
4. Настройки permissions, signing-neutral runners и assets переносить только по карте 2.5. Сохранить iOS deployment 15.5 и пин симулятора 18.x; снижение требований не входит в перенос. Linux — GStreamer; desktop dependencies должны появиться в registrants через инструменты.
5. Дополнить платформенные scripts macos.sh/ios.sh/linux.sh и scope_guard.sh только камерными сценариями. `vm.ps1` запускает тесты example без собственного CMake-проекта. `example.ps1` делает analyze и build web. Своя таблица scope: lib → vm/windows/web; example/test → vm; integration_test или общий CI-helper/pubspec → all; платформенные configs/scripts/workflows → соответствующая платформа; example/lib → vm/example/windows/android/web; документы → none. Ключ all — все существующие scripts vm/windows/android/web/example/macos/ios/linux; ключ smoke из YUV не переносить без соответствующего script. Windows-local ключи исполняются в этом этапе; remote platforms — гейт этапа 2. Чужие root YUV-матрицы, wasm build и benchmarks не копировать. Автозапуск CI не вводить.
6. G1: analyze обоих уровней, 34/34, native capture в Windows и Android Tablet (x86_64/API 35), web source в Chrome/JS. Вердикты CAM 2 можно переиспользовать только если покрываемые пути с Validated at не менялись; иначе соответствующий script повторить. Недоступный Android — BLOCKED с названием ресурса, удаление YUV не разрешается.
7. Ручные физические камеры, Pixel 3/device-check, iPhone и Mac camera — гейт этапа 2 по карте 4, не условие G1. Не выдавать эмулятор/fake-platform за подтверждение физической камеры.

## Scope

`example/`, package docs о запуске примера, камерные `tool/ci/`. Источники YUV не удаляются.

## Constraints

Нет новых публичных API, оптимизаций, схем отчёта или зависимостей ML Kit в пакете. Сохраняются пределы платформ/браузеров. Не менять secrets/signing и не запускать физический iPhone без команды Engineer.

## Definition of Done

1. Сохранены C1–C4, D1–D5 и device-check по карте 3 — check: чтение новых экранов/targets против таблиц карты — by: Executor.
2. Все 34 теста проходят — check: из example `flutter test`, ровно 34 passed; из корня/example `flutter analyze` — by: Executor.
3. G1 завершён — check: `pwsh -File tool/ci/windows.ps1`, `pwsh -File tool/ci/android.ps1`, `pwsh -File tool/ci/web.ps1`; exit 0, PASS capture на двух native-платформах и PASS Web smoke, Windows release build — by: Executor.
4. Настройки раннеров/регистрация и собственный scope соответствуют карте — check: чтение platform configs и сгенерированных registrants после pub get/build; из корня `bash tool/ci/scope_guard.sh <base>`, `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/example.ps1`; остальные Windows-local ключи покрыты G1 — by: Executor.
5. Условие удаления из YUV явно доказано — check: Executor Report с G1 PASS, 34/34, targets, режимами, Validated at и указанием оставленных ручных проверок — by: Executor.
6. Утверждения не потеряны при разделении — check: diff против карты 2–4 и отчёта G1, без повторного запуска проверок Executor — by: Reviewer.

## Validation

Полный flutter test разрешён этой карточкой только в новом example. Камерный код: Probe windows+web, PASS обязателен. Перед запуском Android прочитать MACHINES.md; не совмещать Android AVD и Linux VM. Тесты устройств/remote platforms отнесены к этапу 2 явно; обязательные команды G1 не заменяются review по чтению. Формат touched Dart и git diff --check. REVIEW возможен только с G1 PASS; YUV 1 ждёт приёмки этой карточки.

## Executor Report

Заполняет Executor.
