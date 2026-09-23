import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';

import '../services/tflite_service.dart';
import '../models/context_vector.dart';
import '../models/detected_object.dart';
import '../models/app_state.dart';
import '../managers/risk_manager.dart';
import 'widgets/diagnostic_panel.dart';
import 'camera_transform.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isProcessing = false;
  File? _staticImage;
  Size? _staticImageSize;
  
  // Performance metrics
  int _fps = 0;
  int _lastInferenceTimeMs = 0;
  int _framesInLastSecond = 0;
  DateTime _lastFpsTime = DateTime.now();
  DateTime _lastFrameProcessedTime = DateTime.now();
  
  // Use a ValueNotifier to only rebuild the bounding boxes
  final ValueNotifier<List<DetectedObject>> _detectionsNotifier = ValueNotifier([]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAppFlow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _detectionsNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cameraController?.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      _resumeCamera();
    }
  }

  Future<void> _startAppFlow() async {
    final appState = context.read<AppStateModel>();
    appState.setState(AppState.starting);

    // 1. Request permissions
    bool hasPermission = await _requestPermissions(appState);
    if (!hasPermission) return;

    // Location permission is checked later, but we need to start RiskManager
    // with the knowledge of whether location is available. We will do this 
    // after we ask for location.

    // 2. Initialize Model
    appState.setState(AppState.initializingModel);
    if (!mounted) return;
    try {
      final tflite = context.read<TfliteService>();
      await tflite.init();
      if (!mounted) return;
    } catch (e) {
      appState.setState(AppState.modelFailed, error: e.toString());
      return;
    }

    // 3. Initialize Camera
    await _initCameraFlow(appState);
  }

  Future<bool> _requestPermissions(AppStateModel appState) async {
    appState.setState(AppState.requestingPermissions);
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      if (mounted) appState.setState(AppState.cameraUnavailable, error: "Camera permission denied.");
      return false;
    }

    final locationStatus = await Permission.location.request();
    bool locationAvailable = locationStatus.isGranted;
    
    if (!locationAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission denied. GPS speed unavailable. Using limited risk assessment.")),
        );
      }
      // Continue without location to allow camera-based detection
    }
    
    if (mounted) {
      context.read<RiskManager>().start(locationAvailable: locationAvailable);
    }
    
    return true;
  }

  Future<void> _initCameraFlow(AppStateModel appState) async {
    appState.setState(AppState.initializingCamera);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        appState.setState(AppState.cameraUnavailable, error: "No cameras found.");
        return;
      }

      final backCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      if (_cameraController != null) {
        await _cameraController!.dispose();
      }

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      _resumeCamera();
      appState.setState(AppState.ready);
    } catch (e) {
      appState.setState(AppState.error, error: "Camera init error: $e");
    }
  }

  void _resumeCamera() {
    if (_cameraController != null && !_cameraController!.value.isStreamingImages) {
      _cameraController!.startImageStream((CameraImage image) {
        if (_isProcessing || _staticImage != null) return;
        
        // Target ~10 FPS maximum to prevent device overheating
        if (DateTime.now().difference(_lastFrameProcessedTime).inMilliseconds < 100) return;
        
        _isProcessing = true;
        _processFrame(image);
      });
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    try {
      final startTime = DateTime.now();
      _lastFrameProcessedTime = startTime;
      final tflite = context.read<TfliteService>();
      
      final sensorOrientation = _cameraController?.description.sensorOrientation ?? 90;
      final deviceOrientation = MediaQuery.of(context).orientation == Orientation.portrait 
          ? DeviceOrientation.portraitUp 
          : DeviceOrientation.landscapeLeft;
          
      final results = await tflite.processFrame(image, sensorOrientation, deviceOrientation);
      final inferenceTime = DateTime.now().difference(startTime).inMilliseconds;
      
      if (!mounted) return;
      _updateFps(inferenceTime);

      _detectionsNotifier.value = results;
      context.read<RiskManager>().updateDetections(results);
    } finally {
      _isProcessing = false;
    }
  }

  void _updateFps(int inferenceTime) {
    _framesInLastSecond++;
    _lastInferenceTimeMs = inferenceTime;
    final now = DateTime.now();
    if (now.difference(_lastFpsTime).inSeconds >= 1) {
      setState(() {
        _fps = _framesInLastSecond;
      });
      _framesInLastSecond = 0;
      _lastFpsTime = now;
    }
  }

  Future<void> _pickStaticImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      if (_cameraController != null && _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      
      setState(() {
        _staticImage = File(pickedFile.path);
        _detectionsNotifier.value = [];
      });

      if (!mounted) return;
      final tflite = context.read<TfliteService>();
      final startTime = DateTime.now();
      
      final imgBytes = await pickedFile.readAsBytes();
      final decodedImage = await decodeImageFromList(imgBytes);
      _staticImageSize = Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());
      
      final results = await tflite.processStaticImage(pickedFile.path);
      
      setState(() {
        _lastInferenceTimeMs = DateTime.now().difference(startTime).inMilliseconds;
        _fps = 0;
      });

      if (!mounted) return;

      _detectionsNotifier.value = results;
      context.read<RiskManager>().updateDetections(results);
    }
  }

  Widget _buildStateUI(AppStateModel state) {
    switch (state.currentState) {
      case AppState.starting:
      case AppState.requestingPermissions:
        return const Center(child: Text("Requesting permissions..."));
      case AppState.initializingModel:
        return const Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Loading object detector...")
          ],
        ));
      case AppState.initializingCamera:
        return const Center(child: Text("Initializing camera..."));
      case AppState.cameraUnavailable:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(state.errorMessage),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => openAppSettings(),
                child: const Text("Open Settings"),
              ),
              TextButton(
                onPressed: () => _startAppFlow(),
                child: const Text("Retry"),
              )
            ],
          ),
        );
      case AppState.locationUnavailable:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              Text(state.errorMessage),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => openAppSettings(),
                child: const Text("Open Settings"),
              ),
              TextButton(
                onPressed: () => _startAppFlow(),
                child: const Text("Retry"),
              )
            ],
          ),
        );
      case AppState.modelFailed:
      case AppState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(state.errorMessage),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _startAppFlow(),
                child: const Text("Retry"),
              )
            ],
          ),
        );
      case AppState.ready:
        // Render the main preview
        Size previewSize = Size.zero;
        if (_staticImageSize != null) {
          previewSize = _staticImageSize!;
        } else if (_cameraController != null && _cameraController!.value.isInitialized) {
          previewSize = _cameraController!.value.previewSize ?? Size.zero;
          // Swap width/height if orientation is portrait (which is true for Android phones)
          if (MediaQuery.of(context).orientation == Orientation.portrait && previewSize.width > previewSize.height) {
            previewSize = Size(previewSize.height, previewSize.width);
          }
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            _staticImage != null 
                ? Image.file(_staticImage!, fit: BoxFit.cover)
                : CameraPreview(_cameraController!),
            _buildBoundingBoxes(context, previewSize),
            _buildRiskOverlay(),
            Positioned(
              top: 10,
              left: 10,
              child: DiagnosticPanel(
                fps: _fps,
                inferenceTimeMs: _lastInferenceTimeMs,
              ),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ContextDrive'),
        actions: [
          if (_staticImage != null)
            IconButton(
              icon: const Icon(Icons.camera_alt),
              onPressed: () {
                setState(() {
                  _staticImage = null;
                  _staticImageSize = null;
                  _detectionsNotifier.value = [];
                });
                _resumeCamera();
              },
            )
        ],
      ),
      body: Consumer<AppStateModel>(
        builder: (context, appState, _) {
          return _buildStateUI(appState);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickStaticImage,
        child: const Icon(Icons.image),
      ),
    );
  }

  Widget _buildBoundingBoxes(BuildContext context, Size previewSize) {
    return ValueListenableBuilder<List<DetectedObject>>(
      valueListenable: _detectionsNotifier,
      builder: (context, detections, child) {
        return CustomPaint(
          painter: BoundingBoxPainter(detections, previewSize),
        );
      },
    );
  }

  Widget _buildRiskOverlay() {
    return Positioned(
      bottom: 40,
      left: 20,
      right: 20,
      child: Consumer<RiskManager>(
        builder: (context, riskManager, child) {
          final assessment = riskManager.currentAssessment;
          
          Color riskColor;
          switch (assessment.level) {
            case RiskLevel.high:
              riskColor = Colors.red;
              break;
            case RiskLevel.moderate:
              riskColor = Colors.orange;
              break;
            case RiskLevel.low:
              riskColor = Colors.green;
              break;
            case RiskLevel.limited:
              riskColor = Colors.grey;
              break;
          }

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: riskColor, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RISK: ${assessment.level.name.toUpperCase()}', 
                  style: TextStyle(color: riskColor, fontSize: 24, fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 8),
                Text('⚠ ${assessment.recommendation}', style: const TextStyle(color: Colors.white, fontSize: 18)),
                const SizedBox(height: 8),
                Text('How: ${assessment.howExplanation}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 4),
                Text('Why: ${assessment.whyExplanation}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<DetectedObject> detections;
  final Size previewSize;

  BoundingBoxPainter(this.detections, this.previewSize);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.redAccent;

    // Use full screen size for static image for MVP if previewSize is empty
    Size effectivePreviewSize = previewSize == Size.zero ? size : previewSize;

    for (var det in detections) {
      final rect = CameraTransform.transformBoundingBox(
        det.boundingBox,
        size,
        effectivePreviewSize,
      );
      
      canvas.drawRect(rect, paint);
      
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${det.label} (${(det.confidence * 100).toStringAsFixed(0)}%)',
          style: const TextStyle(color: Colors.white, backgroundColor: Colors.redAccent, fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(rect.left, rect.top - 20));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
