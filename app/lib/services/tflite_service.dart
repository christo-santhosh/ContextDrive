import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'dart:isolate';

import '../models/detected_object.dart';

// --- Isolate Data Structures ---

class _IsolateInitData {
  final SendPort sendPort;
  final RootIsolateToken token;
  _IsolateInitData(this.sendPort, this.token);
}

class _IsolateRequest {
  final SendPort replyPort;
  final int width;
  final int height;
  final int inputSize;
  final bool isYuv;
  final List<Uint8List> planeBytes;
  final List<int> bytesPerRow;
  final List<int> bytesPerPixel;
  final String? imagePath;

  _IsolateRequest({
    required this.replyPort,
    required this.width,
    required this.height,
    required this.inputSize,
    required this.isYuv,
    required this.planeBytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    this.imagePath,
  });
}

// --- The Service ---

class TfliteService {
  SendPort? _isolateSendPort;
  bool _isProcessing = false;
  final int _inputSize = 320;

  bool get isProcessing => _isProcessing;

  Future<void> init() async {
    final receivePort = ReceivePort();
    final token = RootIsolateToken.instance!;
    
    await Isolate.spawn(_isolateEntryPoint, _IsolateInitData(receivePort.sendPort, token));
    
    _isolateSendPort = await receivePort.first as SendPort;
    print('TFLite Isolate spawned and ready.');
  }

  Future<List<DetectedObject>> processFrame(CameraImage image) async {
    if (_isolateSendPort == null || _isProcessing) return [];
    _isProcessing = true;

    try {
      final responsePort = ReceivePort();
      final request = _IsolateRequest(
        replyPort: responsePort.sendPort,
        width: image.width,
        height: image.height,
        inputSize: _inputSize,
        isYuv: image.format.group == ImageFormatGroup.yuv420,
        planeBytes: image.planes.map((p) => p.bytes).toList(),
        bytesPerRow: image.planes.map((p) => p.bytesPerRow).toList(),
        bytesPerPixel: image.planes.map((p) => p.bytesPerPixel ?? 1).toList(),
      );

      _isolateSendPort!.send(request);
      final results = await responsePort.first as List<DetectedObject>;
      
      _isProcessing = false;
      return results;
    } catch (e) {
      print('Error in processFrame: $e');
      _isProcessing = false;
      return [];
    }
  }

  Future<List<DetectedObject>> processStaticImage(String imagePath) async {
    if (_isolateSendPort == null || _isProcessing) return [];
    _isProcessing = true;

    try {
      final responsePort = ReceivePort();
      final request = _IsolateRequest(
        replyPort: responsePort.sendPort,
        width: 0, height: 0, inputSize: _inputSize, isYuv: false,
        planeBytes: [], bytesPerRow: [], bytesPerPixel: [],
        imagePath: imagePath,
      );

      _isolateSendPort!.send(request);
      final results = await responsePort.first as List<DetectedObject>;
      
      _isProcessing = false;
      return results;
    } catch (e) {
      print('Error processing static image: $e');
      _isProcessing = false;
      return [];
    }
  }
}

// --- Background Isolate Logic ---

void _isolateEntryPoint(_IsolateInitData initData) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(initData.token);
  
  Interpreter? interpreter;
  List<String>? labels;

  try {
    final options = InterpreterOptions()..threads = 4;
    interpreter = await Interpreter.fromAsset('assets/detect.tflite', options: options);
    interpreter.allocateTensors();
    
    final labelData = await rootBundle.loadString('assets/labelmap.txt');
    labels = labelData.split('\n');
    print('TFLite initialized inside isolate.');
  } catch (e) {
    print('Failed to initialize TFLite in isolate: $e');
  }

  final port = ReceivePort();
  initData.sendPort.send(port.sendPort);

  await for (final msg in port) {
    if (msg is _IsolateRequest) {
      if (interpreter == null) {
        msg.replyPort.send(<DetectedObject>[]);
        continue;
      }

      try {
        Uint8List inputBuffer;
        
        if (msg.imagePath != null) {
          // Static Image Processing
          final imgBytes = await File(msg.imagePath!).readAsBytes();
          final decodedImage = img.decodeImage(imgBytes);
          if (decodedImage == null) {
            msg.replyPort.send(<DetectedObject>[]);
            continue;
          }
          final resizedImage = img.copyResize(decodedImage, width: msg.inputSize, height: msg.inputSize);
          inputBuffer = Uint8List(1 * msg.inputSize * msg.inputSize * 3);
          int p = 0;
          for (int y = 0; y < msg.inputSize; y++) {
            for (int x = 0; x < msg.inputSize; x++) {
              var pixel = resizedImage.getPixel(x, y);
              inputBuffer[p++] = pixel.r.toInt();
              inputBuffer[p++] = pixel.g.toInt();
              inputBuffer[p++] = pixel.b.toInt();
            }
          }
        } else {
          // Camera YUV Processing
          inputBuffer = Uint8List(1 * msg.inputSize * msg.inputSize * 3);
          int p = 0;
          
          if (msg.isYuv) {
            final int uvRowStride = msg.bytesPerRow[1];
            final int uvPixelStride = msg.bytesPerPixel[1];
            final int yRowStride = msg.bytesPerRow[0];

            bool isLandscape = msg.width > msg.height;

            for (int dstY = 0; dstY < msg.inputSize; dstY++) {
              for (int dstX = 0; dstX < msg.inputSize; dstX++) {
                int srcX, srcY;
                
                if (isLandscape) {
                  // Rotate 90 degrees for landscape sensors (typical Android back camera)
                  srcX = (dstY * msg.width / msg.inputSize).floor();
                  srcY = msg.height - 1 - (dstX * msg.height / msg.inputSize).floor();
                } else {
                  // Do not rotate for portrait sensors
                  srcX = (dstX * msg.width / msg.inputSize).floor();
                  srcY = (dstY * msg.height / msg.inputSize).floor();
                }

                srcX = srcX.clamp(0, msg.width - 1);
                srcY = srcY.clamp(0, msg.height - 1);

                final int uvIndex = uvPixelStride * (srcX >> 1) + uvRowStride * (srcY >> 1);
                final int index = srcY * yRowStride + srcX;

                final yp = msg.planeBytes[0][index];
                final up = msg.planeBytes[1][uvIndex];
                final vp = msg.planeBytes[2][uvIndex];

                int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
                int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91).round().clamp(0, 255);
                int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);

                inputBuffer[p++] = r;
                inputBuffer[p++] = g;
                inputBuffer[p++] = b;
              }
            }
          } else {
            // Unlikely BGRA format fallback
            img.Image imgImage = img.Image.fromBytes(
              width: msg.width, height: msg.height, bytes: msg.planeBytes[0].buffer, rowStride: msg.bytesPerRow[0], order: img.ChannelOrder.bgra,
            );
            img.Image resizedImage = img.copyResize(imgImage, width: msg.inputSize, height: msg.inputSize);
            for (int y = 0; y < msg.inputSize; y++) {
              for (int x = 0; x < msg.inputSize; x++) {
                var pixel = resizedImage.getPixel(y, (msg.inputSize - 1) - x);
                inputBuffer[p++] = pixel.r.toInt();
                inputBuffer[p++] = pixel.g.toInt();
                inputBuffer[p++] = pixel.b.toInt();
              }
            }
          }
        }

        // Get dynamic output tensor shapes
        int outputTensorCount = interpreter.getOutputTensors().length;
        Map<int, Object> outputs = {};
        
        int boxesIdx = -1;
        int classesIdx = -1;
        int scoresIdx = -1;
        int countIdx = -1;

        for (int i = 0; i < outputTensorCount; i++) {
          final tensor = interpreter.getOutputTensor(i);
          outputs[i] = _createNestedList(tensor.shape, 0);
          
          // Heuristic to find the correct tensors
          if (tensor.shape.length == 3 && tensor.shape[2] == 4) boxesIdx = i;
          else if (tensor.shape.length == 2 && tensor.shape[1] > 10) {
            // scores or classes, usually scores are float32
            if (scoresIdx == -1) scoresIdx = i;
            else classesIdx = i;
          }
          else if (tensor.shape.length == 1) countIdx = i;
        }

        // TfliteFlutter's runForMultipleInputs silently fails to copy flat Uint8Lists.
        // We must manually copy the bytes to the tensor first using setTo().
        interpreter.getInputTensor(0).setTo(inputBuffer.buffer.asUint8List());

        // Then we run inference and map outputs. (It will run inference once here).
        interpreter.runForMultipleInputs([inputBuffer], outputs);

        // Fallback to known indices if heuristic failed
        if (boxesIdx == -1) boxesIdx = 4;
        if (classesIdx == -1) classesIdx = 5;
        if (scoresIdx == -1) scoresIdx = 6;
        if (countIdx == -1) countIdx = 7;

        var parsedScores = outputs[scoresIdx] as List<dynamic>;
        var parsedBoxes = outputs[boxesIdx] as List<dynamic>;
        var parsedClasses = outputs[classesIdx] as List<dynamic>;
        
        int detectionCount = parsedScores[0].length;
        List<DetectedObject> results = [];

        for (int i = 0; i < detectionCount; i++) {
          double score = parsedScores[0][i];
          if (score >= 0.25) { // Lowered to 25% for MVP testing
            int classId = (parsedClasses[0][i] as double).toInt();
            
            // Allow Laptops (73), Keyboards (76), and Monitors (72) along with Vehicles (2,3,5,7) and People (0) for demo!
            if ([0, 2, 3, 5, 7, 72, 73, 76].contains(classId)) {
              String className = "Vehicle";
              if (labels != null && classId < labels.length) {
                className = labels[classId];
              }
              
              var box = parsedBoxes[0][i];
              if (box is! List || box.length < 4) continue;
              
              double ymin = box[0];
              double xmin = box[1];
              double ymax = box[2];
              double xmax = box[3];
              
              RoadObjectType type = RoadObjectType.ignored;
              if (classId == 0 || classId == 1) type = RoadObjectType.vulnerableRoadUser; // person, bicycle
              else if (classId == 2 || classId == 3 || classId == 5 || classId == 7) type = RoadObjectType.roadVehicle; // car, motorcycle, bus, truck
              
              results.add(DetectedObject(
                label: className, // It will literally print 'laptop' or 'car' or 'keyboard'
                confidence: score,
                boundingBox: Rect.fromLTRB(xmin, ymin, xmax, ymax),
                trackingId: i,
                type: type,
              ));
            }
          }
        }

        msg.replyPort.send(results);
      } catch (e) {
        print("Isolate processing error: $e");
        msg.replyPort.send(<DetectedObject>[]);
      }
    }
  }
}

Object _createNestedList(List<int> shape, int depth) {
  if (shape.isEmpty) return [0.0];
  if (depth == shape.length - 1) {
    return List<double>.filled(shape[depth], 0.0);
  }
  return List<dynamic>.generate(shape[depth], (i) => _createNestedList(shape, depth + 1));
}
