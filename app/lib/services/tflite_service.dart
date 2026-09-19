import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/widgets.dart';

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
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  bool _isProcessing = false;
  final int _inputSize = 320;

  bool get isProcessing => _isProcessing;

  Future<void> init() async {
    final receivePort = ReceivePort();
    final token = RootIsolateToken.instance!;
    
    _isolate = await Isolate.spawn(_isolateEntryPoint, _IsolateInitData(receivePort.sendPort, token));
    
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
    interpreter.resizeInputTensor(0, [1, 320, 320, 3]);
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

            for (int dstY = 0; dstY < msg.inputSize; dstY++) {
              for (int dstX = 0; dstX < msg.inputSize; dstX++) {
                int srcX = (dstY * msg.width / msg.inputSize).floor();
                int srcY = msg.height - 1 - (dstX * msg.height / msg.inputSize).floor();

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

        Map<int, List<int>> knownShapes = {
          0: [1, 12804, 4], 1: [1, 100], 2: [1], 3: [1, 12804, 91],
          4: [1, 100, 4], 5: [1, 100], 6: [1, 100], 7: [1, 100, 91],
        };
        
        Map<int, Object> outputs = {};
        for (int i = 0; i < 8; i++) {
          outputs[i] = _createNestedList(knownShapes[i]!, 0);
        }

        // ONE single run! Do not call invoke() AND runForMultipleInputs!
        interpreter.runForMultipleInputs([inputBuffer], outputs);

        int boxesIdx = 4;
        int scoresIdx = 6;
        int classesIdx = 5;

        var parsedScores = outputs[scoresIdx] as List<dynamic>;
        var parsedBoxes = outputs[boxesIdx] as List<dynamic>;
        var parsedClasses = outputs[classesIdx] as List<dynamic>;
        
        int detectionCount = parsedScores[0].length;
        List<DetectedObject> results = [];

        for (int i = 0; i < detectionCount; i++) {
          double score = parsedScores[0][i];
          if (score >= 0.40) { // Keep 40% for demo
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
              
              results.add(DetectedObject(
                label: className, // It will literally print 'laptop' or 'car' or 'keyboard'
                confidence: score,
                boundingBox: Rect.fromLTRB(xmin, ymin, xmax, ymax),
                trackingId: i,
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
