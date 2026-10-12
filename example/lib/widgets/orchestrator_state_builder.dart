import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:yuv_camera/yuv_camera.dart';

/// Rebuilds [builder] whenever [orchestrator] reports a change.
///
/// The orchestrator notifies synchronously: from inside the build of the preview that opens the camera and from inside
/// the unmount of the preview that releases it. A plain `ListenableBuilder` would call `setState` at that moment and
/// fail, so a notification that arrives while a frame is being built waits for the end of that frame.
class OrchestratorStateBuilder extends StatefulWidget {
  const OrchestratorStateBuilder({super.key, required this.orchestrator, required this.builder});

  final YuvCameraOrchestrator orchestrator;

  /// Builds the content from the current state and error of the orchestrator.
  final Widget Function(BuildContext context, YuvCameraOrchestrator orchestrator) builder;

  @override
  State<OrchestratorStateBuilder> createState() => _OrchestratorStateBuilderState();
}

class _OrchestratorStateBuilderState extends State<OrchestratorStateBuilder> {
  @override
  Widget build(BuildContext context) => widget.builder(context, widget.orchestrator);

  @override
  void initState() {
    super.initState();
    widget.orchestrator.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant OrchestratorStateBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orchestrator == widget.orchestrator) return;
    oldWidget.orchestrator.removeListener(_onChanged);
    widget.orchestrator.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.orchestrator.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }
}
