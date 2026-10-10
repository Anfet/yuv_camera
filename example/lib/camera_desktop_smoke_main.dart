// Diagnostic entry point for checking a desktop camera stream without the
// demo UI. Run it directly on a desktop with a camera:
//
// Run (from `example/`):
//   flutter run -t lib/camera_desktop_smoke_main.dart -d windows
//   flutter run -t lib/camera_desktop_smoke_main.dart -d macos
//   flutter run -t lib/camera_desktop_smoke_main.dart -d linux
//
// The camera package restricts `CameraController.startImageStream` to Android
// and iOS. Calling `CameraPlatform.instance.onStreamedFrameAvailable` directly
// lets this diagnostic exercise desktop frame delivery while retaining the
// controller's initialization, disposal, and lifecycle handling.
//
// Verdict: the final line is `SMOKE COMPLETE` only if all five frames were
// imported through `importCameraImage()`/`toBgraBytes()` without throwing and the
// stream was stopped cleanly afterwards; any other outcome (conversion
// failure, stream error, timeout, no camera) prints `SMOKE FAILED` with the
// reason and calls `exit(1)`, so a rerun gives an unambiguous result even
// when only the process exit code is checked.
import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/camera_image_import.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.initialize();
  runApp(const _SmokeApp());
}

class _SmokeApp extends StatelessWidget {
  const _SmokeApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('camera_desktop image-stream smoke')),
        body: const _SmokeBody(),
      ),
    );
  }
}

class _SmokeBody extends StatefulWidget {
  const _SmokeBody();

  @override
  State<_SmokeBody> createState() => _SmokeBodyState();
}

class _SmokeBodyState extends State<_SmokeBody> {
  final List<String> _log = <String>[];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    unawaited(_runSmoke());
  }

  void _append(String line) {
    // Printed as well as shown on screen: `flutter run`'s console is the
    // artifact a reviewer copies into a report; the on-screen list is for
    // watching it live.
    debugPrint('[camera_desktop_smoke] $line');
    if (mounted) {
      setState(() => _log.add(line));
    } else {
      _log.add(line);
    }
  }

  Future<void> _runSmoke() async {
    if (_running) {
      return;
    }
    _running = true;
    int? cameraId;
    StreamSubscription<CameraImageData>? subscription;
    // The final verdict requires five successful imports and a clean stream
    // stop; either condition failing makes the smoke fail.
    var framesImported = 0;
    const targetFrames = 5;
    var streamStoppedCleanly = false;
    String? failureReason;

    void fail(String reason) {
      failureReason ??= reason;
      _append('SMOKE FAILED: $reason');
    }

    try {
      final cameras = await availableCameras();
      _append('availableCameras: ${cameras.length}');
      for (final c in cameras) {
        _append('  ${c.name} lensDirection=${c.lensDirection} sensorOrientation=${c.sensorOrientation}');
      }
      if (cameras.isEmpty) {
        fail('No camera available.');
        return;
      }

      final description = cameras.first;
      cameraId = await CameraPlatform.instance.createCamera(description, ResolutionPreset.medium, enableAudio: false);
      _append('createCamera -> cameraId=$cameraId');

      final initialized = CameraPlatform.instance.onCameraInitialized(cameraId).first;
      await CameraPlatform.instance.initializeCamera(cameraId);
      final initEvent = await initialized;
      _append('initializeCamera -> previewSize=${initEvent.previewWidth}x${initEvent.previewHeight}');

      final framesDone = Completer<void>();

      // The bypass described in the file header: this is exactly what
      // `CameraController.startImageStream` calls internally, minus its
      // Android/iOS-only assert.
      subscription = CameraPlatform.instance
          .onStreamedFrameAvailable(cameraId)
          .listen(
            (CameraImageData data) {
              if (framesDone.isCompleted) {
                return;
              }
              final frameNumber = framesImported + 1;
              final image = CameraImage.fromPlatformInterface(data);
              final plane = image.planes.first;
              _append(
                'frame $frameNumber: ${image.width}x${image.height} '
                'format=${image.format.group} raw=${image.format.raw} '
                'planes=${image.planes.length} bytesPerRow=${plane.bytesPerRow} '
                'bytesPerPixel=${plane.bytesPerPixel} bufferLength=${plane.bytes.length}',
              );

              try {
                final yuv = importCameraImage(image);
                final bgra = yuv.toBgraBytes();
                _append(
                  'importCameraImage/toBgraBytes ok: format=${yuv.format} '
                  'firstPixel=${bgra.sublist(0, 4)}',
                );
                framesImported++;
              } catch (e) {
                fail('importCameraImage/toBgraBytes threw on frame $frameNumber: $e');
                if (!framesDone.isCompleted) {
                  framesDone.complete();
                }
                return;
              }

              if (framesImported >= targetFrames && !framesDone.isCompleted) {
                framesDone.complete();
              }
            },
            onError: (Object e) {
              fail('onStreamedFrameAvailable error: $e');
              if (!framesDone.isCompleted) {
                framesDone.complete();
              }
            },
          );

      await framesDone.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail('Timed out waiting for $targetFrames frames (got $framesImported).'),
      );

      if (framesImported < targetFrames) {
        // A conversion failure or stream error above already completed
        // `framesDone` and called `fail`; this only catches the case where
        // the completer resolved for some other reason without enough frames.
        fail('Only $framesImported/$targetFrames frames imported successfully.');
      } else {
        // Mirrors CameraController.stopImageStream's body (cancel the
        // subscription) without its Android/iOS-only assert.
        await subscription.cancel();
        subscription = null;
        streamStoppedCleanly = true;
        _append('stream stopped, subscription cancelled');
      }
    } catch (e, st) {
      fail('Unhandled exception: $e');
      debugPrint('$st');
    } finally {
      await subscription?.cancel();
      if (cameraId != null) {
        await CameraPlatform.instance.dispose(cameraId);
        _append('dispose($cameraId) done');
      }

      final success = failureReason == null && framesImported >= targetFrames && streamStoppedCleanly;
      if (success) {
        _append('SMOKE COMPLETE ($framesImported/$targetFrames frames, clean stop)');
      } else {
        _append(
          'SMOKE FAILED: '
          '${failureReason ?? "verdict conditions not met ($framesImported/$targetFrames frames, "
                  "streamStoppedCleanly=$streamStoppedCleanly)"}',
        );
        // A manual `flutter run` still shows the log above; `exit(1)` matters
        // for a CI/scripted invocation, where only the process's exit code is
        // checked and the on-screen list is never read. This tool only
        // targets desktop platforms (see file header), so no platform guard.
        exit(1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _log.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Text(_log[index], style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ),
    );
  }
}

// ignore_for_file: implementation_imports
