# CAM 4 — CI камеры, документация и локальная проверка пары

**Status:** BLOCKED
**Tier:** T2
**Owner:** —
**Depends on:** CAM 3; yuv_ffi: YUV 2 — принятые разделение и версия 0.5.2.
**Probe:** none — scripts, workflow и документы; при изменении lib добавить windows+web.

## Goal

Завершить этап 1: новый пакет документирован, CI умеет получать точную зависимость YUV, пример подтверждает совместимость разделённой пары.

## Architect Decision

1. Workflows одной платформы вызывают соответствующий script, только tag `ci/<platform>/<label>`, `ci/all/<label>` или dispatch. Сначала обнаружить доступные runners/доступ репозитория read-only; использовать реальные labels из YUV, не утверждать наличие прав/секретов по одному origin. Автозапуск на push dev не добавлять.
2. До выпуска YUV checkout зависимости выполняется по обязательному точному SHA из input/repository variable, без плавающего dev. CI генерирует ignored overrides для корня/example; runner получает публичный репозиторий Anfet/yuv_ffi вторым checkout. После публикации проверка опубликованной пары обходится без override. Не создавать secrets и не менять права; при подтверждённом отказе доступа — ENGINEER_REQUIRED с конкретной ошибкой, без гипотетической блокировки заранее.
3. README, example/README, dartdoc и CHANGELOG — английские. Описать API, desktop camera_desktop, permissions, onFrame для внешнего ML Kit, локальные overrides и пределы подтверждённого. Description и MIT согласованы Q1. Не обещать работу физической камеры по сборке.
4. Локальный потребитель этапа 1 — example нового пакета. Он зависит от yuv_camera через `..`, от yuv_ffi через ^0.5.2 с ignored override на текущий разделённый checkout. После YUV 2 заново проверить native capture и Web camera source: изменился реальный dependency checkout. Отдельный опубликованный потребитель остаётся этапу 3.
5. Добавить воспроизводимый script проверки пары, создающий/убирающий только собственные overrides (существующие пользовательские сохранять). Применить scripts scope_guard и отчёт без дублирования уже валидных проверок. CI-файлы создаются сейчас, внешний CI запускается на кандидатах этапа 2.

## Scope

Workflows, `tool/ci/`, README/example docs, CHANGELOG, завершение metadata. Не менять реализацию камеры или backend YUV.

## Definition of Done

1. Каждый workflow вызывает камерный script и использует точный SHA зависимости — check: чтение YAML/scripts против решений 1–2; тест script во время проверки пары — by: Executor.
2. Совместимость разделённой пары локально подтверждена — check: `flutter analyze` из корня/example; из example `flutter test` (34); из корня `pwsh -File tool/ci/windows.ps1` и `pwsh -File tool/ci/web.ps1`, PASS обоих источников; в отчёте обе версии и dependency path — by: Executor.
3. Данные публикации и описание соответствуют Q1, API/границы — карте — check: чтение pubspec/README/CHANGELOG и проверка tracked files на отсутствие overrides — by: Executor.
4. Незавершённые проверки устройств и CI записаны как гейт этапа 2 — check: todo содержит конкретные targets из карты 4, не объявляет кандидаты проверенными — by: Executor.

## Validation

`bash tool/ci/scope_guard.sh <base>`; keys, необходимые по собственным изменённым scripts, выполнить. `git diff --check`. Dry-run публикации на чистом кандидате — этап 2, не на незавершённом dirty tree. Report: Validated at, результаты, ссылка на G1 и выполненную проверку пары. Не повторять native/Web scripts без изменений покрываемых путей после последнего успешного запуска.

## Executor Report

Заполняет Executor.
