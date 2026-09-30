import 'package:flutter/services.dart';

class BackgroundService {
  static const platform = MethodChannel('com.example.safe_drive_monitor/background');
  
  static Future<void> startService() async {
    try {
      await platform.invokeMethod('startService');
    } on PlatformException catch (e) {
      print('Failed to start service: ${e.message}');
    }
  }

  static Future<void> stopService() async {
    try {
      await platform.invokeMethod('stopService');
    } on PlatformException catch (e) {
      print('Failed to stop service: ${e.message}');
    }
  }
} 