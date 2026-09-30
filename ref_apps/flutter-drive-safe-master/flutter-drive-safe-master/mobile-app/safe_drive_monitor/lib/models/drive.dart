class Drive {
  final int? id;
  final DateTime startTime;
  final DateTime? endTime;
  final int durationSeconds;
  final double averageSpeed;
  final int overSpeedDurationSeconds;
  final Map<int, int> suddenAccelerations;
  final Map<int, int> suddenBrakings;
  final Map<int, int> sharpTurns;

  Drive({
    this.id,
    required this.startTime,
    this.endTime,
    required this.durationSeconds,
    required this.averageSpeed,
    required this.overSpeedDurationSeconds,
    required this.suddenAccelerations,
    required this.suddenBrakings,
    required this.sharpTurns,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime?.millisecondsSinceEpoch,
      'duration_seconds': durationSeconds,
      'average_speed': averageSpeed,
      'over_speed_duration': overSpeedDurationSeconds,
      'sudden_acc_groups': _encodeEventGroups(suddenAccelerations),
      'sudden_brake_groups': _encodeEventGroups(suddenBrakings),
      'sharp_turn_groups': _encodeEventGroups(sharpTurns),
    };
  }

  String _encodeEventGroups(Map<int, int> groups) {
    return groups.entries
        .map((e) => '${e.key}:${e.value}')
        .join(',');
  }

  static Map<int, int> _decodeEventGroups(String encoded) {
    if (encoded.isEmpty) return {};
    return Map.fromEntries(
      encoded.split(',').map((group) {
        final parts = group.split(':');
        return MapEntry(int.parse(parts[0]), int.parse(parts[1]));
      }),
    );
  }

  static Drive fromMap(Map<String, dynamic> map) {
    return Drive(
      id: map['id'],
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time']),
      endTime: map['end_time'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['end_time'])
          : null,
      durationSeconds: map['duration_seconds'],
      averageSpeed: map['average_speed'],
      overSpeedDurationSeconds: map['over_speed_duration'],
      suddenAccelerations: _decodeEventGroups(map['sudden_acc_groups'] ?? ''),
      suddenBrakings: _decodeEventGroups(map['sudden_brake_groups'] ?? ''),
      sharpTurns: _decodeEventGroups(map['sharp_turn_groups'] ?? ''),
    );
  }
} 