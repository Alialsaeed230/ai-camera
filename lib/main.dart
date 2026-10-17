import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

List<CameraDescription> _cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error initializing cameras: $e');
  }
  runApp(const IOS27CameraApp());
}

class IOS27CameraApp extends StatelessWidget {
  const IOS27CameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iOS 27 AI Camera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const CameraScreen(),
    );
  }
}

enum CameraMode { cinematic, video, photo, aiScan, portrait }

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin {
  CameraController? _controller;
  int _selectedCameraIndex = 0;

  // Camera Settings State
  CameraMode _selectedMode = CameraMode.aiScan;
  FlashMode _flashMode = FlashMode.auto;
  bool _showGrid = true;
  bool _showLevel = true;
  double _currentZoom = 1.0;
  double _maxZoom = 5.0;
  double _minZoom = 1.0;
  double _exposureOffset = 0.0;
  double _minExposure = -2.0;
  double _maxExposure = 2.0;
  bool _showExposureSlider = false;

  // Filter State
  int _selectedFilterIndex = 0;
  final List<Map<String, dynamic>> _filters = [
    {'name': 'Original', 'matrix': null},
    {
      'name': 'Vivid',
      'matrix': <double>[
        1.2, 0, 0, 0, 0,
        0, 1.2, 0, 0, 0,
        0, 0, 1.2, 0, 0,
        0, 0, 0, 1, 0,
      ],
    },
    {
      'name': 'Warm',
      'matrix': <double>[
        1.2, 0, 0, 0, 10,
        0, 1.0, 0, 0, 0,
        0, 0, 0.8, 0, -10,
        0, 0, 0, 1, 0,
      ],
    },
    {
      'name': 'Dramatic',
      'matrix': <double>[
        1.4, 0, 0, 0, -20,
        0, 1.4, 0, 0, -20,
        0, 0, 1.4, 0, -20,
        0, 0, 0, 1, 0,
      ],
    },
    {
      'name': 'Mono',
      'matrix': <double>[
        0.33, 0.59, 0.11, 0, 0,
        0.33, 0.59, 0.11, 0, 0,
        0.33, 0.59, 0.11, 0, 0,
        0, 0, 0, 1, 0,
      ],
    },
  ];

  // Gyroscope / Horizon Level
  double _deviceRoll = 0.0; // in degrees
  StreamSubscription<AccelerometerEvent>? _accelSubscription;

  // AI Framing Engine State
  double _aiRecommendedZoom = 2.5;
  String _aiGuidanceMessage = "Analyzing framing...";
  bool _isAIFramedPerfectly = false;
  late AnimationController _aiScanAnimationController;

  @override
  void initState() {
    super.initState();
    _initCamera(_selectedCameraIndex);
    _initSensors();

    _aiScanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  void _initSensors() {
    _accelSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      // Calculate roll angle relative to horizon
      double roll = math.atan2(event.x, event.y) * (180 / math.pi);
      if (mounted) {
        setState(() {
          _deviceRoll = roll;
          _updateAIGuidance();
        });
      }
    });
  }

  Future<void> _initCamera(int cameraIndex) async {
    if (_cameras.isEmpty) return;
    
    final controller = CameraController(
      _cameras[cameraIndex],
      ResolutionPreset.max,
      enableAudio: false,
    );

    _controller = controller;

    try {
      await controller.initialize();
      _maxZoom = await controller.getMaxZoomLevel();
      _minZoom = await controller.getMinZoomLevel();
      _minExposure = await controller.getMinExposureOffset();
      _maxExposure = await controller.getMaxExposureOffset();
    } catch (e) {
      debugPrint('Camera init error: $e');
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _updateAIGuidance() {
    double tiltError = _deviceRoll.abs();
    if (tiltError > 3.0) {
      _isAIFramedPerfectly = false;
      if (_deviceRoll > 0) {
        _aiGuidanceMessage = "Tilt left ${tiltError.toStringAsFixed(1)}° to align horizon";
      } else {
        _aiGuidanceMessage = "Tilt right ${tiltError.toStringAsFixed(1)}° to align horizon";
      }
    } else if (_currentZoom < _aiRecommendedZoom - 0.5) {
      _isAIFramedPerfectly = false;
      _aiGuidanceMessage = "Zoom in to ${_aiRecommendedZoom}x for optimal subject framing";
    } else {
      _isAIFramedPerfectly = true;
      _aiGuidanceMessage = "Perfect Framing! Tap to Shoot ✨";
    }
  }

  Future<void> _setZoom(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    double clampedZoom = zoom.clamp(_minZoom, _maxZoom);
    await _controller!.setZoomLevel(clampedZoom);
    setState(() {
      _currentZoom = clampedZoom;
    });
  }

  Future<void> _setExposure(double exposure) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    await _controller!.setExposureOffset(exposure);
    setState(() {
      _exposureOffset = exposure;
    });
  }

  void _toggleCamera() {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    _initCamera(_selectedCameraIndex);
  }

  void _toggleFlash() {
    if (_controller == null) return;
    setState(() {
      switch (_flashMode) {
        case FlashMode.off:
          _flashMode = FlashMode.auto;
          break;
        case FlashMode.auto:
          _flashMode = FlashMode.always;
          break;
        case FlashMode.always:
          _flashMode = FlashMode.torch;
          break;
        case FlashMode.torch:
          _flashMode = FlashMode.off;
          break;
      }
      _controller!.setFlashMode(_flashMode);
    });
  }

  void _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    HapticFeedback.mediumImpact();
    try {
      final XFile photo = await _controller!.takePicture();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo saved: ${photo.path}'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error taking picture: $e');
    }
  }

  @override
  void dispose() {
    _accelSubscription?.cancel();
    _controller?.dispose();
    _aiScanAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final matrix = _filters[_selectedFilterIndex]['matrix'] as List<double>?;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 1. Live Camera Viewfinder with Filters
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24.0),
                child: matrix != null
                    ? ColorFiltered(
                        colorFilter: ColorFilter.matrix(matrix),
                        child: CameraPreview(_controller!),
                      )
                    : CameraPreview(_controller!),
              ),
            ),

            // 2. Custom Painter Overlays (Grid & Level Gauge)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: ViewfinderOverlayPainter(
                    showGrid: _showGrid,
                    showLevel: _showLevel,
                    rollDegrees: _deviceRoll,
                  ),
                ),
              ),
            ),

            // 3. AI Scan Overlay & AR Framing Box
            if (_selectedMode == CameraMode.aiScan)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _aiScanAnimationController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: AIScanPainter(
                          progress: _aiScanAnimationController.value,
                          isPerfect: _isAIFramedPerfectly,
                        ),
                      );
                    },
                  ),
                ),
              ),

            // 4. Top Guidance Banner (AI Scan Feedback)
            if (_selectedMode == CameraMode.aiScan)
              Positioned(
                top: 70,
                left: 20,
                right: 20,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _isAIFramedPerfectly
                              ? Colors.green.withOpacity(0.3)
                              : Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isAIFramedPerfectly
                                ? Colors.greenAccent
                                : Colors.white24,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isAIFramedPerfectly ? Icons.check_circle : Icons.auto_awesome,
                              color: _isAIFramedPerfectly ? Colors.greenAccent : Colors.amberAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _aiGuidanceMessage,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 5. Top Control Bar (iOS Frosted Glass Style)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.black26,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(_getFlashIcon()),
                          color: Colors.white,
                          onPressed: _toggleFlash,
                        ),
                        IconButton(
                          icon: Icon(_showGrid ? Icons.grid_on : Icons.grid_off),
                          color: _showGrid ? Colors.amberAccent : Colors.white54,
                          onPressed: () => setState(() => _showGrid = !_showGrid),
                        ),
                        IconButton(
                          icon: Icon(_showLevel ? Icons.screen_rotation : Icons.screen_rotation_alt),
                          color: _showLevel ? Colors.amberAccent : Colors.white54,
                          onPressed: () => setState(() => _showLevel = !_showLevel),
                        ),
                        IconButton(
                          icon: const Icon(Icons.exposure),
                          color: _showExposureSlider ? Colors.amberAccent : Colors.white,
                          onPressed: () => setState(() => _showExposureSlider = !_showExposureSlider),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 6. Exposure Adjustment Slider
            if (_showExposureSlider)
              Positioned(
                right: 20,
                top: 120,
                bottom: 240,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: _exposureOffset,
                    min: _minExposure,
                    max: _maxExposure,
                    activeColor: Colors.amberAccent,
                    inactiveColor: Colors.white24,
                    onChanged: (val) => _setExposure(val),
                  ),
                ),
              ),

            // 7. Bottom Controls & Lens Switcher
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black.withOpacity(0.85),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Zoom Pill Selectors
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildZoomPill(1.0, "1x"),
                            _buildZoomPill(2.0, "2x"),
                            _buildZoomPill(3.0, "3x"),
                            if (_selectedMode == CameraMode.aiScan)
                              GestureDetector(
                                onTap: () => _setZoom(_aiRecommendedZoom),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.amberAccent),
                                  ),
                                  child: Text(
                                    "✨ ${_aiRecommendedZoom}x",
                                    style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Filter Carousel Selector
                    SizedBox(
                      height: 30,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _filters.length,
                        itemBuilder: (context, index) {
                          final isSelected = index == _selectedFilterIndex;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedFilterIndex = index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              child: Text(
                                _filters[index]['name'],
                                style: TextStyle(
                                  color: isSelected ? Colors.amberAccent : Colors.white54,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Camera Mode Switcher Carousel
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: CameraMode.values.map((mode) {
                        final isSelected = mode == _selectedMode;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedMode = mode),
                          child: Text(
                            mode.name.toUpperCase(),
                            style: TextStyle(
                              color: isSelected ? Colors.amberAccent : Colors.white54,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    // Main Shutter Button & Flanking Controls
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24.0, left: 24, right: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Gallery Preview Button
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Icon(Icons.photo_library, color: Colors.white),
                          ),

                          // iOS 27 Shutter Button
                          GestureDetector(
                            onTap: _takePicture,
                            child: Container(
                              width: 76,
                              height: 76,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 4),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _selectedMode == CameraMode.video
                                      ? Colors.red
                                      : Colors.white,
                                ),
                              ),
                            ),
                          ),

                          // Camera Flip Switcher
                          IconButton(
                            icon: const Icon(Icons.flip_camera_ios, size: 28),
                            color: Colors.white,
                            onPressed: _toggleCamera,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomPill(double zoomValue, String label) {
    final isSelected = (_currentZoom - zoomValue).abs() < 0.2;
    return GestureDetector(
      onTap: () => _setZoom(zoomValue),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.amberAccent : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.highlight;
    }
  }
}

// Custom Painter for Viewfinder Grid & Horizon Gauge
class ViewfinderOverlayPainter extends CustomPainter {
  final bool showGrid;
  final bool showLevel;
  final double rollDegrees;

  ViewfinderOverlayPainter({
    required this.showGrid,
    required this.showLevel,
    required this.rollDegrees,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintGrid = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..strokeWidth = 1.0;

    // Draw Rule of Thirds Grid
    if (showGrid) {
      double thirdWidth = size.width / 3;
      double thirdHeight = size.height / 3;

      canvas.drawLine(Offset(thirdWidth, 0), Offset(thirdWidth, size.height), paintGrid);
      canvas.drawLine(Offset(thirdWidth * 2, 0), Offset(thirdWidth * 2, size.height), paintGrid);
      canvas.drawLine(Offset(0, thirdHeight), Offset(size.width, thirdHeight), paintGrid);
      canvas.drawLine(Offset(0, thirdHeight * 2), Offset(size.width, thirdHeight * 2), paintGrid);
    }

    // Draw Horizon Level Indicator
    if (showLevel) {
      bool isLevel = rollDegrees.abs() < 1.0;
      final levelPaint = Paint()
        ..color = isLevel ? Colors.amberAccent : Colors.white.withOpacity(0.7)
        ..strokeWidth = 2.0;

      double cx = size.width / 2;
      double cy = size.height / 2;
      double lineLength = 60;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(-rollDegrees * (math.pi / 180));

      canvas.drawLine(Offset(-lineLength, 0), Offset(-15, 0), levelPaint);
      canvas.drawLine(Offset(15, 0), Offset(lineLength, 0), levelPaint);
      canvas.drawCircle(Offset.zero, 3, levelPaint);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant ViewfinderOverlayPainter oldDelegate) {
    return oldDelegate.showGrid != showGrid ||
        oldDelegate.showLevel != showLevel ||
        oldDelegate.rollDegrees != rollDegrees;
  }
}

// Custom Painter for AI Framing AR Overlay
class AIScanPainter extends CustomPainter {
  final double progress;
  final bool isPerfect;

  AIScanPainter({required this.progress, required this.isPerfect});

  @override
  void paint(Canvas canvas, Size size) {
    final paintBorder = Paint()
      ..color = isPerfect ? Colors.greenAccent : Colors.amberAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    double scanBoxSize = size.width * 0.65;
    double left = (size.width - scanBoxSize) / 2;
    double top = (size.height - scanBoxSize) / 2 - 40;
    Rect rect = Rect.fromLTWH(left, top, scanBoxSize, scanBoxSize);

    // Draw Corner Reticles
    double cornerLength = 20.0;
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(cornerLength, 0), paintBorder);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, cornerLength), paintBorder);

    canvas.drawLine(rect.topRight, rect.topRight + Offset(-cornerLength, 0), paintBorder);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(0, cornerLength), paintBorder);

    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(cornerLength, 0), paintBorder);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(0, -cornerLength), paintBorder);

    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(-cornerLength, 0), paintBorder);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(0, -cornerLength), paintBorder);

    // Dynamic AR Scanning Line
    double scanY = top + (scanBoxSize * progress);
    final scanLinePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          (isPerfect ? Colors.greenAccent : Colors.amberAccent).withOpacity(0.6),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(left, scanY, scanBoxSize, 2));

    canvas.drawRect(Rect.fromLTWH(left, scanY - 1, scanBoxSize, 3), scanLinePaint);
  }

  @override
  bool shouldRepaint(covariant AIScanPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isPerfect != isPerfect;
  }
}