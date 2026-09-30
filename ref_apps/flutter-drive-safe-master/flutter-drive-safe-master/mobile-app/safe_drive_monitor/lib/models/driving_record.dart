class DrivingRecord {
  final int? id;
  final int? driveId;
  final DateTime timestamp;
  final double speed;
  final double latitude;
  final double longitude;
  final double accelerationX;
  final double accelerationY;
  final double accelerationZ;
  final double totalAcceleration;
  final bool isSuddenAcceleration;
  final bool isSuddenBraking;
  final bool isSharpTurn;

  DrivingRecord({
    this.id,
    this.driveId,
    required this.timestamp,
    required this.speed,
    required this.latitude,
    required this.longitude,
    required this.accelerationX,
    required this.accelerationY,
    required this.accelerationZ,
    required this.totalAcceleration,
    required this.isSuddenAcceleration,
    required this.isSuddenBraking,
    required this.isSharpTurn,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'drive_id': driveId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'speed': speed,
      'latitude': latitude,
      'longitude': longitude,
      'accelerationX': accelerationX,
      'accelerationY': accelerationY,
      'accelerationZ': accelerationZ,
      'totalAcceleration': totalAcceleration,
      'isSuddenAcceleration': isSuddenAcceleration ? 1 : 0,
      'isSuddenBraking': isSuddenBraking ? 1 : 0,
      'isSharpTurn': isSharpTurn ? 1 : 0,
    };
  }

  static DrivingRecord fromMap(Map<String, dynamic> map) {
    return DrivingRecord(
      id: map['id'],
      driveId: map['drive_id'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      speed: map['speed'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      accelerationX: map['accelerationX'],
      accelerationY: map['accelerationY'],
      accelerationZ: map['accelerationZ'],
      totalAcceleration: map['totalAcceleration'],
      isSuddenAcceleration: map['isSuddenAcceleration'] == 1,
      isSuddenBraking: map['isSuddenBraking'] == 1,
      isSharpTurn: map['isSharpTurn'] == 1,
    );
  }
} 