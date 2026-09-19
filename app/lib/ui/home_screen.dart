import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../services/tflite_service.dart';
import '../models/detected_object.dart';
import '../models/context_vector.dart';
import '../managers/risk_manager.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CameraController? _cameraController;
  bool _isProcessing = false;
  File? _staticImage;
  
  // Use a ValueNotifier to only rebuild the bounding boxes, not the whole camera preview
  final ValueNotifier<List<DetectedObject>> _detectionsNotifier = ValueNotifier([]);

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeML();
  }

  Future<void> _initializeML() async {
    final tflite = context.read<TfliteService>();
    await tflite.init();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final backCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      _cameraController!.startImageStream((CameraImage image) {
        if (_isProcessing) return;
        _isProcessing = true;
        _processFrame(image);
      });

      setState(() {});
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    try {
      final tflite = context.read<TfliteService>();
      final results = await tflite.processFrame(image);
      
      if (mounted) {
        _detectionsNotifier.value = results; // Updates only the overlay
        context.read<RiskManager>().updateDetections(results);
      }
    } finally {
      _isProcessing = false;
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _detectionsNotifier.dispose();
    super.dispose();
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
        _detectionsNotifier.value = []; // Clear old detections
      });

      // Run inference on the static image
      final tflite = context.read<TfliteService>();
      final results = await tflite.processStaticImage(pickedFile.path);
      
      if (mounted) {
        _detectionsNotifier.value = results;
        context.read<RiskManager>().updateDetections(results);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
                  _detectionsNotifier.value = [];
                });
                _initializeCamera();
              },
            )
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _staticImage != null 
              ? Image.file(_staticImage!, fit: BoxFit.cover)
              : CameraPreview(_cameraController!),
          _buildBoundingBoxes(),
          _buildRiskOverlay(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickStaticImage,
        child: const Icon(Icons.image),
      ),
    );
  }

  Widget _buildBoundingBoxes() {
    return ValueListenableBuilder<List<DetectedObject>>(
      valueListenable: _detectionsNotifier,
      builder: (context, detections, child) {
        return CustomPaint(
          painter: BoundingBoxPainter(detections),
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

  BoundingBoxPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.redAccent;

    for (var det in detections) {
      final rect = Rect.fromLTRB(
        det.boundingBox.left * size.width,
        det.boundingBox.top * size.height,
        det.boundingBox.right * size.width,
        det.boundingBox.bottom * size.height,
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
