# CAM 1 — каркас yuv_camera

**Status:** BLOCKED
**Tier:** T2
**Owner:** —
**Depends on:** yuv_ffi: PREP 1 — принятие карты Reviewer.
**Probe:** none — каркас и конфигурация, камерной реализации ещё нет.

## Goal

Подготовить существующий checkout к переносу камеры: самостоятельный Flutter-пакет `yuv_camera 0.0.1` и минимальный пример, разрешающие зависимости до публикации YUV 0.5.2.

## Architect Decision

1. Работать в `D:\.projects\yuv_ffi_camera`, ветка `dev`; имя пакета и remote — `yuv_camera`, не имя локального каталога. На старте записать базовый SHA этого репозитория в Executor Report. Карта: `D:\.projects\yuv_ffi\doc\camera-extraction.md`, разделы 1, 5–6.
2. Это Flutter-пакет поверх существующих плагинов, без собственного platform channel, FFI, native-кода и декларации `flutter.plugin`. Не генерировать native-плагин. Геометрия, презентер, шейдер и операции остаются в `yuv_ffi`.
3. Создать `pubspec.yaml`: версия `0.0.1`, Dart `^3.12.0`, Flutter `>=3.44.0`, зависимости по разделу 1 карты; `yuv_ffi: ^0.5.2`. Description: `Flutter camera package built on yuv_ffi for capturing and displaying YUV camera frames.` Repository/homepage — `https://github.com/Anfet/yuv_camera`, issue_tracker — URL `/issues`. MIT LICENSE сохранить. `publish_to` не ограничивать: целевой выпуск — pub.dev.
4. Создать `analysis_options.yaml`, `.gitignore`, `CHANGELOG.md`, пока пустой публичный entrypoint `lib/yuv_camera.dart`. Пять экспортов добавить только вместе с реализациями в CAM 2. Не создавать фиктивные классы.
5. Минимальный пример — `yuv_camera_example`; создать через Flutter app scaffolding в `example/`, не затерев существующие файлы. Платформы Windows/Android/iOS/macOS/Web; Linux создаётся при Linux-проверке. Камерные экраны и ML Kit пока не добавлять. Шаблонный counter/widget_test убрать при создании каркаса: будущие 34 теста — перенесённое покрытие, не сумма с демонстрационным counter-тестом.
6. Создать собственный `AGENTS.md` и память по общим правилам: работа в dev без worktree; свои проверки и Probe; no native C; CI только тег/dispatch; внешние тексты английские. Сохранить подготовленные Architect карточки и `todo.md`. `pubspec_overrides.yaml` корня и примера игнорируются; локально оба получают `yuv_ffi: path: ../yuv_ffi` с корректным путём относительно каждого файла. В публикуемых pubspec path на YUV не попадает; path `..` в примере допустим.
7. Если Flutter scaffolding конфликтует с существующим README/LICENSE, создать scaffold во временном каталоге и перенести только недостающие файлы. В отчёте указать выбранный вариант. Remote, права и секреты не менять.

## Scope

Каркас пакета, `example/`, локальные правила, `.gitignore`, начальные публикационные данные. `yuv_ffi` читается, не меняется.

## Constraints

Не переносить native backend, не обновлять версии сторонних зависимостей, не запускать CI и не публиковать. Не удалять исходную камеру из YUV. Заготовки платформ не означают подтверждённую поддержку.

## Definition of Done

1. Имя, версия, SDK, зависимости, URL и лицензия соответствуют решениям — check: чтение pubspec и LICENSE против карты, `flutter pub get --no-example` из корня и `flutter pub get` из example — by: Executor.
2. Каркас анализируется без ошибок — check: `flutter analyze` в корне и example — by: Executor.
3. Overrides не отслеживаются и не меняют публикационный контракт — check: `git check-ignore pubspec_overrides.yaml example/pubspec_overrides.yaml`, чтение обоих pubspec — by: Executor.
4. Локальные правила и dashboard задают порядок CAM 1 → CAM 2 → CAM 3 → YUV 1 → YUV 2 → CAM 4 — check: чтение AGENTS/todo против этого плана — by: Executor.
5. Исходная камера сохранена — check: diff собственного checkout; отсутствие изменений Executor в yuv_ffi — by: Executor.

## Validation

Команды выше; runtime-тестов для каркаса нет. `git diff --check` для собственных путей. Executor Report: Base, Validated at, команды/exit code и каждый DoD. Снять BLOCKED после принятия PREP 1; выполнение этапа запускает Engineer.

## Executor Report

Заполняет Executor.
