import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart'; // for compute

import '../models/detected_object.dart';

class TfliteService {
  Interpreter? _interpreter;
  List<String>? _labels;
  bool _isProcessing = false;

  final int _inputSize = 320;
  final double _confidenceThreshold = 0.55;

  Future<void> init() async {
    try {
      final options = InterpreterOptions()..threads = 4;
      
      _interpreter = await Interpreter.fromAsset('assets/detect.tflite', options: options);
      
      // Explicitly resize the input tensor to 320x320 and allocate
      _interpreter!.resizeInputTensor(0, [1, _inputSize, _inputSize, 3]);
      _interpreter!.allocateTensors();
      
      final labelData = await rootBundle.loadString('assets/labelmap.txt');
      _labels = labelData.split('\n');
      print('TFLite Initialized successfully.');
      
      // Print IO info for debugging
      print('Input Tensors: ${_interpreter?.getInputTensors()}');
      print('Output Tensors: ${_interpreter?.getOutputTensors()}');
      
    } catch (e) {
      print('Error initializing TFLite: $e');
    }
  }

  Future<List<DetectedObject>> processFrame(CameraImage image) async {
    if (_interpreter == null || _isProcessing) return [];
    _isProcessing = true;

    try {
      // Move image conversion and tensor creation to background isolate
      final isolateData = _IsolateData(
        image.width,
        image.height,
        _inputSize,
        image.format.group == ImageFormatGroup.yuv420,
        image.planes.map((p) => p.bytes).toList(),
        image.planes.map((p) => p.bytesPerRow).toList(),
        image.planes.map((p) => p.bytesPerPixel ?? 1).toList(),
        false,
      );

      print('DEBUG: Starting isolate...');
      var inputBuffer = await compute(_processImageInIsolate, isolateData) as Uint8List;
      print('DEBUG: Isolate finished!');

      return _runInferenceAndParse(inputBuffer);
    } catch (e) {
      if (!_hasPrintedTypeError) {
        print('Error during processing: $e');
        _hasPrintedTypeError = true;
      }
      _isProcessing = false;
      return [];
    }
  }

  Future<List<DetectedObject>> processStaticImage(String imagePath) async {
    if (_interpreter == null || _isProcessing) return [];
    _isProcessing = true;

    try {
      final imgBytes = await File(imagePath).readAsBytes();
      final decodedImage = img.decodeImage(imgBytes);
      if (decodedImage == null) {
        _isProcessing = false;
        return [];
      }

      final resizedImage = img.copyResize(decodedImage, width: _inputSize, height: _inputSize);

      var inputBuffer = Uint8List(1 * _inputSize * _inputSize * 3);
      int p = 0;
      for (int y = 0; y < _inputSize; y++) {
        for (int x = 0; x < _inputSize; x++) {
          var pixel = resizedImage.getPixel(x, y);
          inputBuffer[p++] = pixel.r.toInt();
          inputBuffer[p++] = pixel.g.toInt();
          inputBuffer[p++] = pixel.b.toInt();
        }
      }

      return _runInferenceAndParse(inputBuffer);
    } catch (e) {
      print('Error processing static image: $e');
      _isProcessing = false;
      return [];
    }
  }

  List<DetectedObject> _runInferenceAndParse(Uint8List inputBuffer) {
    var inputTensor = _interpreter!.getInputTensor(0);
    inputTensor.setTo(inputBuffer);
    
    _interpreter!.invoke();

    var tensors = _interpreter!.getOutputTensors();

    int boxesIdx = 4;
    int scoresIdx = 6;
    int classesIdx = 5;
    int numDetectionsIdx = 2;

    for (int i = 0; i < tensors.length; i++) {
      var t = tensors[i];
      if (t.name == 'detection_boxes') boxesIdx = i;
      if (t.name == 'detection_scores') scoresIdx = i;
      if (t.name == 'detection_classes') classesIdx = i;
      if (t.name == 'num_detections') numDetectionsIdx = i;
    }

    var boxesTensor = _interpreter!.getOutputTensor(boxesIdx);
    var scoresTensor = _interpreter!.getOutputTensor(scoresIdx);
    var classesTensor = _interpreter!.getOutputTensor(classesIdx);
    var numDetectionsTensor = _interpreter!.getOutputTensor(numDetectionsIdx);

    // Read flat Float32 data
    var boxesData = Float32List(1 * 100 * 4);
    var scoresData = Float32List(1 * 100);
    var classesData = Float32List(1 * 100);
    var numDetectionsData = Float32List(1);
    
    // We cannot use outputTensor.copyTo() easily if shapes mismatch, but we can access data directly?
    // tflite_flutter's Tensor class provides a data buffer!
    // But tflite_flutter 0.12.1 requires outputs to be objects or pre-allocated shapes.
    // Wait, let's use the standard `outputs` map for `invoke()`, which handles memory mapping perfectly.
    
    Map<int, List<int>> knownShapes = {
      0: [1, 12804, 4],
      1: [1, 100],
      2: [1],
      3: [1, 12804, 91],
      4: [1, 100, 4],
      5: [1, 100],
      6: [1, 100],
      7: [1, 100, 91],
    };
    
    Map<int, Object> outputs = {};
    for (int i = 0; i < tensors.length; i++) {
      var t = tensors[i];
      List<int> shape = knownShapes.containsKey(i) ? knownShapes[i]! : t.shape;
      outputs[i] = _createNestedList(shape, 0);
    }

    _interpreter!.runForMultipleInputs([inputBuffer], outputs);

    List<DetectedObject> results = [];
    
    var parsedScores = outputs[scoresIdx] as List<dynamic>;
    var parsedBoxes = outputs[boxesIdx] as List<dynamic>;
    var parsedClasses = outputs[classesIdx] as List<dynamic>;
    
    int detectionCount = parsedScores[0].length;

    if (!_hasPrintedShapes) {
      print("====== DEBUG TENSORS ======");
      for (int i = 0; i < tensors.length; i++) {
        print("Tensor $i: name=${tensors[i].name}, shape=${tensors[i].shape}");
      }
      print("boxesIdx=$boxesIdx, scoresIdx=$scoresIdx, classesIdx=$classesIdx, numDetectionsIdx=$numDetectionsIdx");
      
      var t1 = (outputs[1] as List<dynamic>)[0] as List<double>;
      var t5 = (outputs[5] as List<dynamic>)[0] as List<double>;
      var t6 = (outputs[6] as List<dynamic>)[0] as List<double>;
      print("Tensor 1 (Call:0) head: ${t1.sublist(0, 5)}");
      print("Tensor 5 (Call:2) head: ${t5.sublist(0, 5)}");
      print("Tensor 6 (Call:4) head: ${t6.sublist(0, 5)}");
      _hasPrintedShapes = true;
    }

    for (int i = 0; i < detectionCount; i++) {
      if (parsedScores[0][i] is! double || parsedClasses[0][i] is! double) {
        if (!_hasPrintedTypeError) {
          print("TYPE ERROR! Score is ${parsedScores[0][i].runtimeType}, Class is ${parsedClasses[0][i].runtimeType}");
          _hasPrintedTypeError = true;
        }
        break;
      }

      double score = parsedScores[0][i];
      if (score >= 0.40) { // Lowered to 40% to help detect cars inside laptop screens
        int classId = (parsedClasses[0][i] as double).toInt();
        
        String className = "Vehicle";
        if (classId == 0) {
          className = "Person";
        } else if (_labels != null && classId < _labels!.length) {
          className = _labels![classId];
        }

        // Only detect Vehicles (2=Car, 3=Motorcycle, 5=Bus, 7=Truck) and optionally Person (0)
        // Since user wants to 'detect vehicles', we will allow 2,3,5,7.
        if ([2, 3, 5, 7].contains(classId)) {
          var box = parsedBoxes[0][i];
          if (box is! List || box.length < 4) continue;
          
          double ymin = box[0];
          double xmin = box[1];
          double ymax = box[2];
          double xmax = box[3];
          
          results.add(DetectedObject(
            label: "Vehicle", // Enforce label
            confidence: score,
            boundingBox: Rect.fromLTRB(xmin, ymin, xmax, ymax),
            trackingId: i,
          ));
        }
      }
    }

    _isProcessing = false;
    return results;
  }

  bool _hasPrintedShapes = false;
  bool _hasPrintedTypeError = false;

  Object _createNestedList(List<int> shape, int depth) {
    if (shape.isEmpty) return [0.0];
    if (depth == shape.length - 1) {
      return List<double>.filled(shape[depth], 0.0);
    }
    return List<dynamic>.generate(shape[depth], (i) => _createNestedList(shape, depth + 1));
  }

}

class _IsolateData {
  final int width;
  final int height;
  final int inputSize;
  final bool isYuv;
  final List<Uint8List> planeBytes;
  final List<int> bytesPerRow;
  final List<int> bytesPerPixel;
  final bool isFloat;

  _IsolateData(this.width, this.height, this.inputSize, this.isYuv, this.planeBytes, this.bytesPerRow, this.bytesPerPixel, this.isFloat);
}

Object _processImageInIsolate(_IsolateData data) {
  var inputBuffer = Uint8List(1 * data.inputSize * data.inputSize * 3);
  int p = 0;

  if (data.isYuv) {
    final int uvRowStride = data.bytesPerRow[1];
    final int uvPixelStride = data.bytesPerPixel[1];
    final int yRowStride = data.bytesPerRow[0];

    // Subsample directly during YUV extraction to save 90% CPU
    for (int dstY = 0; dstY < data.inputSize; dstY++) {
      for (int dstX = 0; dstX < data.inputSize; dstX++) {
        // Rotate 90 degrees clockwise while sampling
        int srcX = (dstY * data.width / data.inputSize).floor();
        int srcY = data.height - 1 - (dstX * data.height / data.inputSize).floor();

        srcX = srcX.clamp(0, data.width - 1);
        srcY = srcY.clamp(0, data.height - 1);

        final int uvIndex = uvPixelStride * (srcX >> 1) + uvRowStride * (srcY >> 1);
        final int index = srcY * yRowStride + srcX;

        final yp = data.planeBytes[0][index];
        final up = data.planeBytes[1][uvIndex];
        final vp = data.planeBytes[2][uvIndex];

        int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91).round().clamp(0, 255);
        int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);

        inputBuffer[p++] = r;
        inputBuffer[p++] = g;
        inputBuffer[p++] = b;
      }
    }
  } else {
    // Fallback for non-YUV (unlikely on Android, but safe)
    img.Image imgImage = img.Image.fromBytes(
      width: data.width,
      height: data.height,
      bytes: data.planeBytes[0].buffer,
      rowStride: data.bytesPerRow[0],
      order: img.ChannelOrder.bgra,
    );
    
    img.Image resizedImage = img.copyResize(imgImage, width: data.inputSize, height: data.inputSize);
    for (int y = 0; y < data.inputSize; y++) {
      for (int x = 0; x < data.inputSize; x++) {
        int srcX = y;
        int srcY = (data.inputSize - 1) - x;
        var pixel = resizedImage.getPixel(srcX, srcY);
        
        inputBuffer[p++] = pixel.r.toInt();
        inputBuffer[p++] = pixel.g.toInt();
        inputBuffer[p++] = pixel.b.toInt();
      }
    }
  }

  return inputBuffer;
}
