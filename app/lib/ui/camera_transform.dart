import 'package:flutter/material.dart';

class CameraTransform {
  /// Converts normalized ML bounding box [0..1] to screen coordinates [0..screenWidth]
  /// taking into account the crop and scale of the CameraPreview.
  static Rect transformBoundingBox(
    Rect normalizedBox,
    Size screenSize,
    Size previewSize,
    bool isAndroidLandscape,
  ) {
    // If the image was squeezed into the ML model ignoring aspect ratio (which tflite_service does currently),
    // the normalized coordinates are direct percentages of the raw sensor.
    // If the UI is using StackFit.expand with BoxFit.cover, we need to map the normalized coordinates 
    // to the covering rect.
    
    // For MVP Phase 4, we assume the preview covers the screen using BoxFit.cover logic.
    double screenAspect = screenSize.width / screenSize.height;
    double previewAspect = previewSize.width / previewSize.height;

    // The camera package returns previewSize based on the raw sensor (usually landscape).
    // If the UI is in portrait mode (!isAndroidLandscape), we must invert the preview aspect ratio
    // to match how the CameraPreview widget renders it.
    if (!isAndroidLandscape) {
      previewAspect = 1.0 / previewAspect;
    }

    double scaleX = 1.0;
    double scaleY = 1.0;
    double dx = 0.0;
    double dy = 0.0;

    if (screenAspect > previewAspect) {
      // Screen is wider than preview aspect ratio
      scaleX = screenSize.width;
      scaleY = screenSize.width / previewAspect;
      dy = (screenSize.height - scaleY) / 2;
    } else {
      // Screen is taller than preview aspect ratio
      scaleY = screenSize.height;
      scaleX = screenSize.height * previewAspect;
      dx = (screenSize.width - scaleX) / 2;
    }

    return Rect.fromLTRB(
      dx + normalizedBox.left * scaleX,
      dy + normalizedBox.top * scaleY,
      dx + normalizedBox.right * scaleX,
      dy + normalizedBox.bottom * scaleY,
    );
  }
}
