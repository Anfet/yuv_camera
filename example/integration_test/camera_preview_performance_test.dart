import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/common.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final originalReporter = reportTestException;
  reportTestException = (details, description) {
    originalReporter(details, description);
    // FlutterErrorDetails.toString() is empty in Release; retain actionable failures.
    binding.results[description] = Failure(description, '${details.exceptionAsString()}\n${details.stack}');
  };

  testWidgets('Release preview baseline: visible, offstage, recovery', (tester) async {
    expect(kIsWeb && kReleaseMode, isTrue, reason: 'This workload requires Web Release');
    await YuvFfi.initialize();
    final cameras = await availableCameras();
    expect(cameras, isNotEmpty, reason: 'Chrome fake-media must expose a camera');
    final camera = cameras.firstWhere((item) => item.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false);
    await controller.initialize();
    final offstage = ValueNotifier(false);
    var sourceFrames = 0;
    var drawnFrames = 0;
    var width = 0;
    var height = 0;
    var format = '';
    final errors = <Object>[];
    final source = YuvCameraFrameSource(
      controller,
      onFrame: (frame) {
        // Metadata only: this shared listener never materializes frame.image.
        sourceFrames++;
        width = frame.width;
        height = frame.height;
        format = frame.format.name;
      },
      onError: errors.add,
    );
    final rows = <Map<String, Object>>[];
    try {
      await source.start();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<bool>(
            valueListenable: offstage,
            builder: (context, hidden, child) => Offstage(offstage: hidden, child: child),
            child: YuvCameraView(
              cameraController: controller,
              onFramePresented: (_) => drawnFrames++,
              onStreamStopped: () => errors.add(StateError('Preview source stopped')),
            ),
          ),
        ),
      );
      for (var repetition = 1; repetition <= 3; repetition++) {
        for (final hidden in [false, true]) {
          offstage.value = hidden;
          await tester.pump();
          await tester.pump(const Duration(seconds: 5));
          expect(errors, isEmpty);
          final startSource = sourceFrames;
          final startDrawn = drawnFrames;
          final windowWidth = width;
          final windowHeight = height;
          final clock = Stopwatch()..start();
          await tester.pump(const Duration(seconds: 20));
          clock.stop();
          final sourceCount = sourceFrames - startSource;
          final drawnCount = drawnFrames - startDrawn;
          expect(errors, isEmpty);
          expect(sourceCount, greaterThan(0), reason: 'Incomplete source window');
          expect(width, greaterThan(0));
          expect(height, greaterThan(0));
          expect([width, height], [windowWidth, windowHeight], reason: 'Resolution changed during measurement');
          if (!hidden) expect(drawnCount, greaterThan(0), reason: 'Visible preview was never drawn');
          rows.add({
            'scenario': hidden ? 'offstage' : 'visible',
            'repetition': repetition,
            'width_px': width,
            'height_px': height,
            'format': format,
            'window_ms': clock.elapsedMicroseconds / 1000,
            'source_frames': sourceCount,
            'drawn_frames': drawnCount,
            'source_fps': sourceCount * 1000000 / clock.elapsedMicroseconds,
            'drawn_fps': drawnCount * 1000000 / clock.elapsedMicroseconds,
          });
          if (hidden) {
            offstage.value = false;
            await tester.pump();
            final beforeRecovery = drawnFrames;
            await tester.pump(const Duration(seconds: 5));
            expect(drawnFrames, greaterThan(beforeRecovery), reason: 'No rendered recovery after offstage');
            expect(errors, isEmpty);
            rows.last['recovery_drawn_frames_5s'] = drawnFrames - beforeRecovery;
          }
        }
      }
      binding.reportData = {
        'previewPerformance': {
          'schema': 1,
          'mode': 'release',
          'resolution_preset': 'medium',
          'requested_fps': 'browser default',
          'onFrame': null,
          'warmup_seconds': 5,
          'measurement_seconds': 20,
          'rows': rows,
          'metrics': {
            'source_frames': 'count; shared-source metadata-only listener; measurement window only',
            'drawn_frames': 'count; YuvCameraView.onFramePresented; measurement window only',
            'window_ms': 'milliseconds; monotonic Stopwatch around real-time 20s pump',
            'source_fps': 'source_frames / actual elapsed seconds; delivered source rate, not device sensor rate',
            'drawn_fps': 'drawn_frames / actual elapsed seconds',
            'imported_count': 'UNAVAILABLE: actual production loader has no injected observer',
            'import_time_p50_p95': 'UNAVAILABLE: actual production loader has no timing observer',
            'heap_bytes': 'UNAVAILABLE: no portable heap profiler connected to this release workload',
            'gc_count_and_allocations': 'UNAVAILABLE: no GC/allocation profiler trace; no inference from frame counts',
          },
        },
      };
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
      await controller.dispose();
      offstage.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
