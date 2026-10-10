# yuv_camera — принятые задачи

Одна строка на завершённую задачу пакета. Карточки и вердикты удалённых карточек доступны в истории group checkout `D:\.projects\yuv`.

## 10.10.2026

- **CAM 1** — DONE: каркас Flutter-пакета `yuv_camera 0.0.1` (pubspec с зависимостями раздела 1 карты, metadata pub.dev, MIT, пустой entrypoint, analysis_options, `.gitignore` с локальными overrides и lock примера) и минимальный пример `yuv_camera_example` для Windows/Android/iOS/macOS/Web. Base `e0be2afcc76fafabfa119e42df1b3ffd8e4970d0`; accepted SHA `32afdfe22e1d0492ded60165b22524b66806c269`. CI: не требуется; merge/push не требуются. Карточка/Review: история group `tasks/0.0.1/CAM-1.md`.
- **CAM 2** — DONE: камерный API в `lib/src/` (копия `yuv_ffi/example/lib/camera/` с правкой импортов, `FlutterErrorDetails.library`, iOS-dartdoc по Q3), публичный entrypoint с пятью типами, 26 камерных тестов и `fake_camera.dart` в `example/test/camera/`, integration-цели native capture и web source smoke, скрипты `tool/ci/` (`drive`, `windows`, `android`, `web`); пример использует публичный entrypoint. Base `56fd2094fcce7d4f0251f2760236c5f2277b3084`; accepted SHA `42bdf95f647a025e53c9dbf3a3b1bf5d294aff40`. Проверки: 26/26, Windows capture и Chrome/JS smoke — PASS; Android Tablet — в G1 CAM 3. CI: не требуется; merge/push не требуются. Карточка/Review: история group `tasks/0.0.1/CAM-2.md`.
