import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'dart:isolate';

import '../models/detected_object.dart';

// --- Isolate Data Structures ---

class _IsolateInitData {
  final SendPort sendPort;
  final RootIsolateToken token;
  final Uint8List modelBytes;
  final List<String> labels;
  _IsolateInitData(this.sendPort, this.token, this.modelBytes, this.labels);
}

class _IsolateInitResponse {
  final SendPort? sendPort;
  final String? error;
  _IsolateInitResponse({this.sendPort, this.error});
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
  final int sensorOrientation;
  final int deviceOrientation; // 0 = portrait, 1 = landscapeLeft, 2 = landscapeRight, 3 = portraitDown
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
    required this.sensorOrientation,
    required this.deviceOrientation,
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
    
    // Load assets on the main thread to avoid ServicesBinding isolate errors
    final modelData = await rootBundle.load('assets/detect.tflite');
    final modelBytes = modelData.buffer.asUint8List();
    
    final labelData = await rootBundle.loadString('assets/labelmap.txt');
    final labels = labelData.split('\n');
    
    await Isolate.spawn(_isolateEntryPoint, _IsolateInitData(receivePort.sendPort, token, modelBytes, labels));
    
    try {
      final response = await receivePort.first.timeout(const Duration(seconds: 10)) as _IsolateInitResponse;
      if (response.error != null) {
        throw Exception(response.error);
      }
      _isolateSendPort = response.sendPort;
      debugPrint('TFLite Isolate spawned and ready.');
    } catch (e) {
      throw Exception('TFLite initialization failed or timed out: $e');
    } finally {
      receivePort.close();
    }
  }

  void dispose() {
    _isolateSendPort?.send('terminate'); // Signal isolate to terminate
  }

  Future<List<DetectedObject>> processFrame(CameraImage image, int sensorOrientation, DeviceOrientation deviceOrientation) async {
    if (_isolateSendPort == null || _isProcessing) return [];
    _isProcessing = true;

    final responsePort = ReceivePort();
    try {
      final request = _IsolateRequest(
        replyPort: responsePort.sendPort,
        width: image.width,
        height: image.height,
        inputSize: _inputSize,
        isYuv: image.format.group == ImageFormatGroup.yuv420,
        planeBytes: image.planes.map((p) => p.bytes).toList(),
        bytesPerRow: image.planes.map((p) => p.bytesPerRow).toList(),
        bytesPerPixel: image.planes.map((p) => p.bytesPerPixel ?? 1).toList(),
        sensorOrientation: sensorOrientation,
        deviceOrientation: deviceOrientation.index,
      );

      _isolateSendPort!.send(request);
      final results = await responsePort.first as List<DetectedObject>;
      
      return results;
    } catch (e) {
      debugPrint('Error in processFrame: $e');
      return [];
    } finally {
      responsePort.close();
      _isProcessing = false;
    }
  }

  Future<List<DetectedObject>> processStaticImage(String imagePath) async {
    if (_isolateSendPort == null || _isProcessing) return [];
    _isProcessing = true;

    final responsePort = ReceivePort();
    try {
      final request = _IsolateRequest(
        replyPort: responsePort.sendPort,
        width: 0, height: 0, inputSize: _inputSize, isYuv: false,
        planeBytes: [], bytesPerRow: [], bytesPerPixel: [],
        sensorOrientation: 0, deviceOrientation: 0,
        imagePath: imagePath,
      );

      _isolateSendPort!.send(request);
      final results = await responsePort.first as List<DetectedObject>;
      
      return results;
    } catch (e) {
      debugPrint('Error processing static image: $e');
      return [];
    } finally {
      responsePort.close();
      _isProcessing = false;
    }
  }
}

// --- Background Isolate Logic ---

void _isolateEntryPoint(_IsolateInitData initData) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(initData.token);
  
  Interpreter? interpreter;
  List<String>? labels;
  
  int boxesIdx = -1;
  int classesIdx = -1;
  int scoresIdx = -1;

  final port = ReceivePort();

  try {
    final options = InterpreterOptions()..threads = 4;
    interpreter = Interpreter.fromBuffer(initData.modelBytes, options: options);
    interpreter.allocateTensors();
    
    labels = initData.labels;
    
    // Explicitly verified indices for this specific SSD model
    boxesIdx = 4;
    classesIdx = 5;
    scoresIdx = 6;

    initData.sendPort.send(_IsolateInitResponse(sendPort: port.sendPort));
  } catch (e) {
    initData.sendPort.send(_IsolateInitResponse(error: e.toString()));
    return;
  }

  await for (final msg in port) {
    if (msg == 'terminate') {
      // Termination signal
      interpreter.close();
      port.close();
      break;
    }
    
    if (msg is _IsolateRequest) {
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

            bool rotate90 = false;
            // 0 = portraitUp, 3 = portraitDown
            if (msg.deviceOrientation == 0 || msg.deviceOrientation == 3) {
              rotate90 = msg.sensorOrientation == 90 || msg.sensorOrientation == 270;
            }

            for (int dstY = 0; dstY < msg.inputSize; dstY++) {
              for (int dstX = 0; dstX < msg.inputSize; dstX++) {
                int srcX, srcY;
                
                if (rotate90) {
                  srcX = (dstY * msg.width / msg.inputSize).floor();
                  srcY = msg.height - 1 - (dstX * msg.height / msg.inputSize).floor();
                } else {
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

        // Pre-allocate map based on known indices
        int outputTensorCount = interpreter.getOutputTensors().length;
        Map<int, Object> outputs = {};
        for (int i = 0; i < outputTensorCount; i++) {
          outputs[i] = _createNestedList(interpreter.getOutputTensor(i).shape, 0);
        }

        interpreter.getInputTensor(0).setTo(inputBuffer.buffer.asUint8List());
        interpreter.runForMultipleInputs([inputBuffer], outputs);

        var parsedScores = outputs[scoresIdx] as List<dynamic>;
        var parsedBoxes = outputs[boxesIdx] as List<dynamic>;
        var parsedClasses = outputs[classesIdx] as List<dynamic>;
        
        int detectionCount = parsedScores[0].length;
        List<DetectedObject> results = [];

        for (int i = 0; i < detectionCount; i++) {
          double score = parsedScores[0][i];
          if (score >= 0.25) {
            int classId = (parsedClasses[0][i] as double).toInt();
            
            // Standard COCO 1-indexed IDs for road vehicles:
            // Person: 1
            // Car: 3, Motorcycle: 4, Bus: 6, Truck: 8
            
            RoadObjectType type = RoadObjectType.ignored;
            if (classId == 1) {
              type = RoadObjectType.vulnerableRoadUser;
            } else if (classId == 3 || classId == 4 || classId == 6 || classId == 8) {
              type = RoadObjectType.roadVehicle;
            }

            if (type != RoadObjectType.ignored) {
              String className = "Vehicle";
              if (classId >= 0 && classId < labels.length) {
                className = labels[classId];
              }
              
              var box = parsedBoxes[0][i];
              if (box is! List || box.length < 4) continue;
              
              double ymin = box[0];
              double xmin = box[1];
              double ymax = box[2];
              double xmax = box[3];
              
              results.add(DetectedObject(
                label: className,
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
