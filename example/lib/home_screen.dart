import 'package:flutter/material.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_camera_example/device_check/device_check_screen.dart';
import 'package:yuv_camera_example/faces/face_screen.dart';
import 'package:yuv_camera_example/orchestrator/orchestrator_screen.dart';
import 'package:yuv_camera_example/shape_crop/shape_crop_screen.dart';

/// The list of example scenarios; every one of them takes its camera from [orchestrator].
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.orchestrator});

  final YuvCameraOrchestrator orchestrator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('yuv_camera 0.0.1 · example', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
                      const SizedBox(height: 4),
                      Text('YUV Camera', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      const Text(
                        'Pick a scenario. Every screen takes the camera from one YuvCameraOrchestrator, does one thing, and gives it back when you leave.',
                      ),
                      const SizedBox(height: 16),
                      _ScenarioCard(
                        number: '01',
                        title: 'Shape crop',
                        description: 'Capture a frame, pick a shape, place it, and see exactly which pixels were cut out.',
                        builder: (_) => ShapeCropScreen(orchestrator: orchestrator),
                      ),
                      _ScenarioCard(
                        number: '02',
                        title: 'Open & close',
                        description: 'Open, close and reopen the camera fast through the orchestrator. Nothing should fail.',
                        builder: (_) => OrchestratorScreen(orchestrator: orchestrator),
                      ),
                      _ScenarioCard(
                        number: '03',
                        title: 'Face detection',
                        description: 'Live ML Kit face box over the preview, with a plain Face detected or No face label.',
                        builder: (_) => FaceScreen(orchestrator: orchestrator),
                      ),
                      _ScenarioCard(
                        number: '04',
                        title: 'Device check',
                        description: 'The guided check of preview, capture and frame rate on this device.',
                        builder: (_) => DeviceCheckScreen(orchestrator: orchestrator),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ListenableBuilder(
                    listenable: orchestrator,
                    builder: (context, child) => Text('Camera: ${orchestrator.state.name}', style: theme.textTheme.labelLarge),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({required this.number, required this.title, required this.description, required this.builder});

  final String number;
  final String title;
  final String description;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: builder)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            spacing: 16,
            children: [
              Text(
                number,
                style: theme.textTheme.titleLarge?.copyWith(fontFamily: 'monospace', color: theme.colorScheme.primary),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    Text(description, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
