import 'package:safe_drive_monitor/config/app_config.dart';

class Settings {
  final int retentionDays;
  final double minDrivingSpeed;
  final double speedLimit;
  final double suddenAccThreshold;
  final double suddenBrakeThreshold;
  final double sharpTurnThreshold;

  Settings({
    required this.retentionDays,
    required this.minDrivingSpeed,
    required this.speedLimit,
    required this.suddenAccThreshold,
    required this.suddenBrakeThreshold,
    required this.sharpTurnThreshold,
  });

  factory Settings.defaultSettings() => Settings(
    retentionDays: AppConfig.retentionDays,
    minDrivingSpeed: AppConfig.minRecordingSpeed,
    speedLimit: AppConfig.speedThreshold,
    suddenAccThreshold: AppConfig.suddenAccelerationThreshold,
    suddenBrakeThreshold: AppConfig.suddenBrakingThreshold,
    sharpTurnThreshold: AppConfig.sharpTurnThreshold,
  );

  Map<String, dynamic> toJson() => {
    'retentionDays': retentionDays,
    'minDrivingSpeed': minDrivingSpeed,
    'speedLimit': speedLimit,
    'suddenAccThreshold': suddenAccThreshold,
    'suddenBrakeThreshold': suddenBrakeThreshold,
    'sharpTurnThreshold': sharpTurnThreshold,
  };

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
    retentionDays: json['retentionDays'] as int,
    minDrivingSpeed: json['minDrivingSpeed'] as double,
    speedLimit: json['speedLimit'] as double,
    suddenAccThreshold: json['suddenAccThreshold'] as double,
    suddenBrakeThreshold: json['suddenBrakeThreshold'] as double,
    sharpTurnThreshold: json['sharpTurnThreshold'] as double,
  );
} 