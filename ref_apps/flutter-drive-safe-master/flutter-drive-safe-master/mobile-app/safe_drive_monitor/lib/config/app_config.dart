import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import '../models/settings.dart';

class AppConfig {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Database configs
  static const String dbName = 'safe_drive_monitor.db';
  static const String recordsTable = 'driving_records';
  static const String drivesTable = 'drives';
  static const int batchSize = 10;
  static int retentionDays = 90;

  // Sampling rate configs
  static double minRecordingSpeed = 10.0;
  static const Map<int, Duration> speedSamplingRates = {
    10: Duration(seconds: 5),  // 10-30 km/h: every 5s
    30: Duration(seconds: 2),  // 30-60 km/h: every 2s
    60: Duration(seconds: 1),  // >60 km/h: every 1s
  };

  // Drive detection configs
  static double driveStartSpeed = 10.0; // km/h
  static const int driveStartDuration = 60; // seconds
  static const double driveEndSpeed = 10.0; // km/h
  static const int driveEndDuration = 1800; // seconds
  
  // Speed monitoring
  static double speedThreshold = 110.0; // km/h
  
  // Acceleration monitoring
  static double suddenAccelerationThreshold = 3.0; // m/s²
  static double suddenBrakingThreshold = -3.0; // m/s²
  static double sharpTurnThreshold = 3.0; // m/s²
  static const int suddenEventGroupInterval = 10; // seconds

  // UI configs
  static const int warningDisplaySeconds = 5;
  static double speedWarningThreshold = 110.0; // km/h

  // Telegram notification intervals (in seconds)
  static const int speedAlertInterval = 1800;  // 30 minutes
  static const int suddenEventAlertInterval = 300;  // 5 minutes

  // Telegram configs
  static const String telegramBotName = 'safe_drive_monitor_bot';
  static String get telegramBotToken => dotenv.env['TELEGRAM_BOT_TOKEN'] ?? '';
  static String get telegramChatId => _prefs?.getString('telegram_chat_id') ?? '';
  static bool get isTelegramConfigured => 
      telegramBotToken.isNotEmpty && telegramChatId.isNotEmpty;

  static Future<void> loadSettings() async {
    final settingsJson = _prefs?.getString('settings');
    if (settingsJson != null) {
      final settings = Settings.fromJson(jsonDecode(settingsJson));
      retentionDays = settings.retentionDays;
      minRecordingSpeed = settings.minDrivingSpeed;
      speedThreshold = settings.speedLimit;
      suddenAccelerationThreshold = settings.suddenAccThreshold;
      suddenBrakingThreshold = settings.suddenBrakeThreshold;
      sharpTurnThreshold = settings.sharpTurnThreshold;
    }
  }
}