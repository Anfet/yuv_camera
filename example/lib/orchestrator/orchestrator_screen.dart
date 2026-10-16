import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yuv_camera/yuv_camera.dart';

/// Opens, closes and reopens the camera of [orchestrator] and shows what the orchestrator reports.
class OrchestratorScreen extends StatefulWidget {
  const OrchestratorScreen({super.key, required this.orchestrator});

  final YuvCameraOrchestrator orchestrator;

  @override
  State<OrchestratorScreen> createState() => _OrchestratorScreenState();
}

class _OrchestratorScreenState extends State<OrchestratorScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Open & close'),
            Text('YuvCameraOrchestrator', style: theme.textTheme.labelMedium),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.orchestrator,
        builder: (context, child) => SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildCameraSelector(theme),
                  const SizedBox(height: 12),
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: ClipRRect(borderRadius: BorderRadius.circular(12), child: _buildPreview()),
                  ),
                  const SizedBox(height: 12),
                  _buildStatus(theme),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(onPressed: _open, child: const Text('Open')),
                      OutlinedButton(onPressed: _close, child: const Text('Close')),
                      OutlinedButton(onPressed: _reopen, child: const Text('Reopen')),
                      OutlinedButton(onPressed: _cycling ? null : _cycle, child: const Text('Open/close ×10')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Events', style: theme.textTheme.titleSmall),
                      OutlinedButton.icon(
                        key: const ValueKey('open_close_copy_events_button'),
                        onPressed: _events.isEmpty ? null : _copyEvents,
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy'),
                      ),
                    ],
                  ),
                  for (final line in _events) Text(line, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_shown) {
      return YuvCameraLeaseBuilder(
        orchestrator: widget.orchestrator,
        builder: (context, controller) => YuvCameraView(cameraController: controller),
      );
    }
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Text('Camera: ${widget.orchestrator.state.name}', style: const TextStyle(color: Colors.white70)),
      ),
    );
  }

  Widget _buildStatus(ThemeData theme) {
    final state = widget.orchestrator.state;
    return Row(
      spacing: 8,
      children: [
        Icon(Icons.circle, size: 12, color: _stateColor(state)),
        Text(state.name, style: theme.textTheme.titleSmall),
        const Spacer(),
        Text('opens $_opens · closes $_closes · errors $_errors', style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
      ],
    );
  }

  Widget _buildCameraSelector(ThemeData theme) {
    final state = widget.orchestrator.state;
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Camera', border: OutlineInputBorder()),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<CameraDescription>(
          key: const ValueKey('open_close_camera_selector'),
          isExpanded: true,
          value: _selectedCamera,
          hint: Text(
            !_cameraLoadComplete
                ? 'Loading cameras…'
                : _cameraError != null
                ? 'Unable to load cameras'
                : 'No cameras found',
          ),
          items: [
            for (final camera in _cameras)
              DropdownMenuItem(
                key: ValueKey('open_close_camera_${camera.name}'),
                value: camera,
                child: Text('${camera.name} · ${camera.lensDirection.name}'),
              ),
          ],
          onChanged: state == YuvCameraState.closed && !_cycling && _cameraError == null ? _selectCamera : null,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _lastState = widget.orchestrator.state;
    _selectedCamera = widget.orchestrator.selectedCamera;
    widget.orchestrator.addListener(_onOrchestratorChanged);
    _loadCameras().ignore();
  }

  @override
  void dispose() {
    widget.orchestrator.removeListener(_onOrchestratorChanged);
    super.dispose();
  }

  void _open() {
    setState(() {
      _log('request: open');
      _shown = true;
    });
  }

  Future<void> _copyEvents() async {
    final events = _events.join('\n');
    if (events.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: events));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to copy events')));
      return;
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Events copied')));
  }

  void _selectCamera(CameraDescription? camera) {
    if (camera == null) return;
    widget.orchestrator.selectCamera(camera);
    setState(() => _selectedCamera = camera);
  }

  Future<void> _loadCameras() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      final currentCamera = _selectedCamera;
      final selectedCamera = cameras.isEmpty
          ? null
          : cameras.firstWhere(
              (camera) => currentCamera != null && _sameCamera(camera, currentCamera),
              orElse: () => cameras.firstWhere((camera) => camera.lensDirection == widget.orchestrator.lensDirection, orElse: () => cameras.first),
            );
      setState(() {
        _cameras
          ..clear()
          ..addAll(cameras);
        _selectedCamera = selectedCamera;
        _cameraLoadComplete = true;
      });
      if (widget.orchestrator.state == YuvCameraState.closed && selectedCamera != null) {
        widget.orchestrator.selectCamera(selectedCamera);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraError = error;
        _cameraLoadComplete = true;
      });
    }
  }

  void _close() {
    setState(() {
      _log('request: close');
      _shown = false;
    });
  }

  void _reopen() {
    setState(() {
      _log('request: reopen');
      _shown = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
  }

  Future<void> _cycle() async {
    setState(() {
      _log('request: open/close ×10');
      _cycling = true;
      _shown = false;
    });
    // Let the preview leave the tree first: a lease it still holds would keep the camera open between the cycles.
    await WidgetsBinding.instance.endOfFrame;
    var failed = 0;
    for (var i = 0; i < 10 && mounted; i++) {
      try {
        final lease = await widget.orchestrator.acquire();
        lease.release();
      } catch (error) {
        failed++;
        if (mounted) setState(() => _log('cycle ${i + 1} failed: $error'));
      }
    }
    if (!mounted) return;
    setState(() {
      _log('10 cycles done · $failed errors');
      _cycling = false;
    });
  }

  void _onOrchestratorChanged() {
    final orchestrator = widget.orchestrator;
    final state = orchestrator.state;
    final error = orchestrator.error;
    // Only the fields change here: the orchestrator notifies in the middle of a build, and the state builder around
    // the body rebuilds after the frame.
    if (state != _lastState) {
      _log('state: ${state.name}');
      if (state == YuvCameraState.open) _opens++;
      if (state == YuvCameraState.closed && _lastState == YuvCameraState.closing) _closes++;
      _lastState = state;
    }
    if (error != null && !identical(error, _lastError)) {
      _errors++;
      _log('error: $error');
    }
    _lastError = error;
  }

  void _log(String event) {
    final seconds = _clock.elapsedMilliseconds / 1000;
    _events.add('+${seconds.toStringAsFixed(2)} s $event');
    if (_events.length > 8) _events.removeAt(0);
  }

  bool _sameCamera(CameraDescription left, CameraDescription right) =>
      left.name == right.name && left.lensDirection == right.lensDirection && left.sensorOrientation == right.sensorOrientation;

  Color _stateColor(YuvCameraState state) => switch (state) {
    YuvCameraState.closed => Colors.grey,
    YuvCameraState.opening => Colors.amber,
    YuvCameraState.open => Colors.green,
    YuvCameraState.closing => Colors.orange,
  };

  final Stopwatch _clock = Stopwatch()..start();
  final List<String> _events = [];
  final List<CameraDescription> _cameras = [];
  CameraDescription? _selectedCamera;
  Object? _cameraError;
  bool _cameraLoadComplete = false;
  late YuvCameraState _lastState;
  Object? _lastError;
  bool _shown = false;
  bool _cycling = false;
  int _opens = 0;
  int _closes = 0;
  int _errors = 0;
}
