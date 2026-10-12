import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

enum _Step {
  capture('Capture'),
  choose('Choose shape'),
  place('Place'),
  result('Result');

  const _Step(this.label);

  final String label;
}

enum _ShapeOption {
  rectangle('Rectangle', 'Free width and height', YuvCropShape.rectangle),
  square('Square', 'Equal sides', YuvCropShape.rectangle),
  oval('Oval', 'Vertical, face-shaped', YuvCropShape.ellipse),
  circle('Circle', 'Equal axes', YuvCropShape.ellipse);

  const _ShapeOption(this.title, this.description, this.shape);

  final String title;
  final String description;
  final YuvCropShape shape;
}

enum _SizeMode { percent, pixels }

const Map<String, Color> _fills = {'Black': Color(0xFF000000), 'Gray': Color(0xFF808080), 'Magenta': Color(0xFFFF00FF)};

/// Captures a frame from [orchestrator]'s camera in four steps and cuts a shape out of it.
class ShapeCropScreen extends StatefulWidget {
  const ShapeCropScreen({super.key, required this.orchestrator});

  final YuvCameraOrchestrator orchestrator;

  @override
  State<ShapeCropScreen> createState() => ShapeCropScreenState();
}

class ShapeCropScreenState extends State<ShapeCropScreen> {
  @visibleForTesting
  YuvImage? get captured => _captured;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Expanded(
              child: switch ((_step, _captured, _shaped)) {
                (_Step.capture, _, _) => _buildCapture(),
                (_Step.choose, final image?, _) => _buildChoose(image),
                (_Step.place, final image?, _) => _buildPlace(image),
                (_Step.result, _, final shaped?) => _buildResult(shaped),
                _ => const SizedBox.shrink(),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            children: [
              IconButton(onPressed: _closeScreen, icon: const Icon(Icons.close), tooltip: 'Close'),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shape crop', style: theme.textTheme.titleMedium),
                  Text('Step ${_step.index + 1} of ${_Step.values.length} · ${_step.label}', style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              spacing: 4,
              children: [
                for (final step in _Step.values)
                  Expanded(
                    child: ColoredBox(
                      color: step.index <= _step.index ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                      child: const SizedBox(height: 4),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapture() {
    return Stack(
      fit: StackFit.expand,
      children: [
        YuvCameraLeaseBuilder(
          orchestrator: widget.orchestrator,
          builder: (context, controller) => YuvCameraView(cameraController: controller, viewController: _viewController),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Center(
            child: ListenableBuilder(
              listenable: widget.orchestrator,
              builder: (context, child) => IconButton.filled(
                onPressed: widget.orchestrator.state == YuvCameraState.open && !_capturing ? _capture : null,
                tooltip: 'Capture frame',
                iconSize: 36,
                padding: const EdgeInsets.all(20),
                icon: const Icon(Icons.camera_alt),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChoose(YuvImage image) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 160,
          child: FittedBox(child: YuvImageWidget(image: image)),
        ),
        const SizedBox(height: 8),
        Text('${image.width}×${image.height} · ${image.format.name}', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ListenableBuilder(
          listenable: widget.orchestrator,
          builder: (context, child) =>
              Text('Camera: ${widget.orchestrator.state.name}', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in _ShapeOption.values)
              SizedBox(
                width: 240,
                child: Card.outlined(
                  color: option == _option ? theme.colorScheme.primaryContainer : null,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => setState(() => _option = option),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(option.title, style: theme.textTheme.titleSmall),
                          Text(option.description, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _place, child: Text('Next: place the ${_option.title.toLowerCase()}')),
      ],
    );
  }

  Widget _buildPlace(YuvImage image) {
    final theme = Theme.of(context);
    final frame = _frame(image);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: image.width / image.height,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pixelsPerPoint = image.width / constraints.maxWidth;
                    final viewFrame = Rect.fromLTRB(
                      frame.left / pixelsPerPoint,
                      frame.top / pixelsPerPoint,
                      frame.right / pixelsPerPoint,
                      frame.bottom / pixelsPerPoint,
                    );
                    return GestureDetector(
                      onPanUpdate: (details) => setState(() {
                        _center = _frameAt(image, _center + details.delta * pixelsPerPoint).center;
                      }),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          FittedBox(
                            fit: BoxFit.fill,
                            child: YuvImageWidget(image: image),
                          ),
                          CustomPaint(
                            painter: _FramePainter(frame: viewFrame, ellipse: _option.shape == YuvCropShape.ellipse),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Text(
            _summary(image, frame),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
          SegmentedButton<_SizeMode>(
            segments: const [
              ButtonSegment(value: _SizeMode.percent, label: Text('Percent')),
              ButtonSegment(value: _SizeMode.pixels, label: Text('Pixels')),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) => setState(() => _mode = selection.first),
          ),
          Row(
            children: [
              Text('Size ${(_scale * 100).round()}%'),
              Expanded(
                child: Slider(
                  min: 0.5,
                  max: 1.4,
                  value: _scale,
                  onChanged: (value) => setState(() {
                    _scale = value;
                    _center = _frame(image).center;
                  }),
                ),
              ),
            ],
          ),
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => setState(() => _step = _Step.choose), child: const Text('Back')),
              ),
              Expanded(
                child: FilledButton(onPressed: _crop, child: const Text('Crop')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResult(YuvShapedImage shaped) {
    final theme = Theme.of(context);
    final image = shaped.image;
    final region = shaped.region;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Expanded(
              child: _ResultPanel(
                title: 'YUV · FILL',
                aspectRatio: image.width / image.height,
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: YuvImageWidget(image: image),
                ),
              ),
            ),
            Expanded(
              child: _ResultPanel(
                title: 'BGRA · ALPHA',
                aspectRatio: image.width / image.height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const CustomPaint(painter: _CheckerPainter()),
                    if (_bgra case final bgra?) RawImage(image: bgra, fit: BoxFit.fill),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SegmentedButton<Color>(
          segments: [for (final MapEntry(:key, :value) in _fills.entries) ButtonSegment(value: value, label: Text(key))],
          selected: {_fill},
          onSelectionChanged: (selection) => _applyFill(selection.first),
        ),
        const SizedBox(height: 16),
        _InfoRow(label: 'Shape', value: _option.title),
        _InfoRow(label: 'Cut box', value: '${region.width.round()} × ${region.height.round()} at (${region.left.round()}, ${region.top.round()})'),
        _InfoRow(label: 'Inside the shape', value: '${shaped.insideCount} px'),
        _InfoRow(label: 'Outside, filled', value: '${image.width * image.height - shaped.insideCount} px'),
        _InfoRow(label: 'Format', value: image.format.name),
        const SizedBox(height: 8),
        Text('Transparency comes from the shape, not from a key color: YUV gets the fill, BGRA gets alpha 0.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: OutlinedButton(onPressed: () => setState(() => _step = _Step.place), child: const Text('Adjust')),
            ),
            Expanded(
              child: FilledButton(onPressed: _closeScreen, child: const Text('Done')),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _viewController.dispose();
    _bgra?.dispose();
    super.dispose();
  }

  void _closeScreen() => Navigator.of(context).popUntil((route) => route.isFirst);

  Future<void> _capture() async {
    setState(() => _capturing = true);
    final YuvImage? image;
    try {
      image = await _viewController.capture();
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
    if (!mounted) return;
    if (image == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing was captured.')));
      return;
    }
    final frame = image;
    setState(() {
      _captured = frame;
      _center = frame.size.center(Offset.zero);
      _step = _Step.choose;
    });
  }

  void _place() => setState(() {
    _scale = 1;
    _center = _captured?.size.center(Offset.zero) ?? Offset.zero;
    _step = _Step.place;
  });

  void _crop() {
    final image = _captured;
    if (image == null) return;
    final frame = _frame(image);
    final size = image.size;
    _target = switch (_mode) {
      _SizeMode.percent => YuvCropTarget.fraction(
        left: frame.left / size.width,
        top: frame.top / size.height,
        right: frame.right / size.width,
        bottom: frame.bottom / size.height,
      ),
      _SizeMode.pixels => YuvCropTarget.pixels(frame.size, alignment: Alignment.topLeft, offset: frame.topLeft),
    };
    _showShaped();
  }

  void _applyFill(Color fill) {
    _fill = fill;
    _showShaped();
  }

  void _showShaped() {
    final image = _captured;
    final target = _target;
    if (image == null || target == null) return;
    final shaped = image.croppedToShape(target, shape: _option.shape, fill: _fill);
    final previous = _bgra;
    setState(() {
      _shaped = shaped;
      _bgra = null;
      _step = _Step.result;
    });
    // The released panel may still be drawn in the current frame; the image goes after it.
    WidgetsBinding.instance.addPostFrameCallback((_) => previous?.dispose());
    ui.decodeImageFromPixels(shaped.toBgraBytes(), shaped.image.width, shaped.image.height, ui.PixelFormat.bgra8888, (decoded) {
      if (!mounted || !identical(_shaped, shaped)) {
        decoded.dispose();
        return;
      }
      setState(() => _bgra = decoded);
    });
  }

  /// The frame in pixels of [image], the base size of the chosen shape times the slider, centered at [center] and kept inside the image.
  Rect _frameAt(YuvImage image, Offset center) {
    final size = image.size;
    final base = switch (_option) {
      _ShapeOption.rectangle => YuvCropTarget.pixels(Size(0.6 * size.width * _scale, 0.4 * size.height * _scale)),
      _ShapeOption.square || _ShapeOption.circle => YuvCropTarget.square(0.5 * _scale),
      _ShapeOption.oval => YuvCropTarget.pixels(Size(0.42 * size.width * _scale, 0.567 * size.width * _scale)),
    };
    final fitted = base.place(size).size;
    final left = (center.dx - fitted.width / 2).clamp(0.0, size.width - fitted.width).roundToDouble();
    final top = (center.dy - fitted.height / 2).clamp(0.0, size.height - fitted.height).roundToDouble();
    return Rect.fromLTWH(left, top, fitted.width, fitted.height);
  }

  Rect _frame(YuvImage image) => _frameAt(image, _center);

  String _summary(YuvImage image, Rect frame) {
    if (_mode == _SizeMode.pixels) return '${frame.width.round()} × ${frame.height.round()} px at (${frame.left.round()}, ${frame.top.round()})';
    String percent(double value) => '${(value * 100).toStringAsFixed(1)}%';
    return 'L ${percent(frame.left / image.width)}  T ${percent(frame.top / image.height)}  '
        'R ${percent(frame.right / image.width)}  B ${percent(frame.bottom / image.height)}';
  }

  final YuvCameraViewController _viewController = YuvCameraViewController();
  YuvImage? _captured;
  YuvShapedImage? _shaped;
  YuvCropTarget? _target;
  ui.Image? _bgra;
  _Step _step = _Step.capture;
  _ShapeOption _option = _ShapeOption.oval;
  _SizeMode _mode = _SizeMode.percent;
  Color _fill = _fills.values.first;
  Offset _center = Offset.zero;
  double _scale = 1;
  bool _capturing = false;
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.title, required this.aspectRatio, required this.child});

  final String title;
  final double aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelSmall),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: AspectRatio(aspectRatio: aspectRatio, child: child),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label, style: theme.textTheme.bodySmall)),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter({required this.frame, required this.ellipse});

  final Rect frame;
  final bool ellipse;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = Path();
    if (ellipse) {
      shape.addOval(frame);
    } else {
      shape.addRect(frame);
    }
    final outside = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), shape);
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white;
    canvas.drawPath(shape, line..strokeWidth = 2);
    if (ellipse) canvas.drawRect(frame, line..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _FramePainter oldDelegate) => oldDelegate.frame != frame || oldDelegate.ellipse != ellipse;
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const tile = 8.0;
    final light = Paint()..color = const Color(0xFFEEEEEE);
    final dark = Paint()..color = const Color(0xFFBDBDBD);
    for (var row = 0; row * tile < size.height; row++) {
      for (var column = 0; column * tile < size.width; column++) {
        canvas.drawRect(Rect.fromLTWH(column * tile, row * tile, tile, tile), (row + column).isEven ? light : dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter oldDelegate) => false;
}
