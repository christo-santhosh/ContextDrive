import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:safe_drive_monitor/models/driving_record.dart';
import 'package:safe_drive_monitor/models/drive.dart';
import 'package:safe_drive_monitor/config/app_config.dart';

class DatabaseService {
  static Database? _database;
  final _recordBuffer = <DrivingRecord>[];
  DateTime _lastSampleTime = DateTime.now();
  int? _currentDriveId;
  DateTime? _driveStartTime;
  DateTime _lastSpeedCheck = DateTime.now();
  bool _isDriving = false;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), AppConfig.dbName);
    
    // Delete existing database for testing
    // await deleteDatabase(path);  // Remove this line in production!
    
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Create drives table first (referenced by records)
        await db.execute('''
          CREATE TABLE ${AppConfig.drivesTable}(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_time INTEGER NOT NULL,
            end_time INTEGER,
            duration_seconds INTEGER NOT NULL,
            average_speed REAL NOT NULL,
            over_speed_duration INTEGER NOT NULL,
            sudden_acc_groups TEXT NOT NULL,
            sudden_brake_groups TEXT NOT NULL,
            sharp_turn_groups TEXT NOT NULL
          )
        ''');

        // Create records table with foreign key
        await db.execute('''
          CREATE TABLE ${AppConfig.recordsTable}(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            drive_id INTEGER,
            timestamp INTEGER NOT NULL,
            speed REAL NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            accelerationX REAL NOT NULL,
            accelerationY REAL NOT NULL,
            accelerationZ REAL NOT NULL,
            totalAcceleration REAL NOT NULL,
            isSuddenAcceleration INTEGER NOT NULL,
            isSuddenBraking INTEGER NOT NULL,
            isSharpTurn INTEGER NOT NULL,
            FOREIGN KEY (drive_id) REFERENCES ${AppConfig.drivesTable}(id)
          )
        ''');

        // Create indexes
        await db.execute(
          'CREATE INDEX idx_timestamp ON ${AppConfig.recordsTable}(timestamp)'
        );
        await db.execute(
          'CREATE INDEX idx_drive_id ON ${AppConfig.recordsTable}(drive_id)'
        );
        await db.execute(
          'CREATE INDEX idx_speed ON ${AppConfig.recordsTable}(speed) WHERE speed > ${AppConfig.minRecordingSpeed}'
        );
      },
    );
  }

  bool shouldSample(double speedKmh) {
    if (speedKmh < AppConfig.minRecordingSpeed) {
      return false;
    }

    final now = DateTime.now();
    Duration requiredInterval = AppConfig.speedSamplingRates.entries
        .firstWhere(
          (entry) => speedKmh < entry.key,
          orElse: () => AppConfig.speedSamplingRates.entries.last,
        )
        .value;

    if (now.difference(_lastSampleTime) >= requiredInterval) {
      _lastSampleTime = now;
      _checkDriveStatus(speedKmh, now);
      return true;
    }
    return false;
  }

  void _checkDriveStatus(double speedKmh, DateTime now) async {
    if (!_isDriving && speedKmh >= AppConfig.driveStartSpeed) {
      if (_driveStartTime == null) {
        _driveStartTime = now;
        print('SDM_LOG: Potential drive start detected at ${now.toIso8601String()}');
      } else if (now.difference(_driveStartTime!).inSeconds >= AppConfig.driveStartDuration) {
        _isDriving = true;
        _currentDriveId = await _startNewDrive(_driveStartTime!);
        print('SDM_LOG: Drive started with ID: $_currentDriveId');
      }
    } else if (_isDriving && speedKmh < AppConfig.driveEndSpeed) {
      if (now.difference(_lastSpeedCheck).inSeconds >= AppConfig.driveEndDuration) {
        await _endCurrentDrive(now);
        print('SDM_LOG: Drive ended: ID $_currentDriveId at ${now.toIso8601String()}');
        _isDriving = false;
        _currentDriveId = null;
        _driveStartTime = null;
      }
    } else {
      _lastSpeedCheck = now;
    }
  }

  Future<int> _startNewDrive(DateTime startTime) async {
    final db = await database;
    return await db.insert(
      AppConfig.drivesTable,
      Drive(
        startTime: startTime,
        durationSeconds: 0,
        averageSpeed: 0,
        overSpeedDurationSeconds: 0,
        suddenAccelerations: {},
        suddenBrakings: {},
        sharpTurns: {},
      ).toMap(),
    );
  }

  Future<void> _endCurrentDrive(DateTime endTime) async {
    if (_currentDriveId == null) return;

    final db = await database;
    final records = await db.query(
      AppConfig.recordsTable,
      where: 'drive_id = ?',
      whereArgs: [_currentDriveId],
    );

    if (records.isEmpty) return;

    final speeds = records.map((r) => r['speed'] as double).toList();
    final avgSpeed = speeds.reduce((a, b) => a + b) / speeds.length;
    final overSpeedDuration = records
        .where((r) => (r['speed'] as double) > AppConfig.speedThreshold)
        .length;

    // Group sudden accelerations by 10-second intervals
    final suddenAccGroups = <int, int>{};
    for (var record in records.where((r) => r['isSuddenAcceleration'] == 1)) {
      final timestamp = record['timestamp'] as int;
      final interval = timestamp ~/ (AppConfig.suddenEventGroupInterval * 1000);
      
      if (record['isSuddenAcceleration'] == 1) {
        suddenAccGroups[interval] = (suddenAccGroups[interval] ?? 0) + 1;
      }
    }

    await db.update(
      AppConfig.drivesTable,
      {
        'end_time': endTime.millisecondsSinceEpoch,
        'duration_seconds': endTime.difference(
          DateTime.fromMillisecondsSinceEpoch(records.first['timestamp'] as int)
        ).inSeconds,
        'average_speed': avgSpeed,
        'over_speed_duration': overSpeedDuration,
        'sudden_acc_groups': suddenAccGroups.entries.map((e) => '${e.key}:${e.value}').join(','),
      },
      where: 'id = ?',
      whereArgs: [_currentDriveId],
    );
  }

  Future<void> insertRecord(DrivingRecord record) async {
    final recordWithDrive = DrivingRecord(
      driveId: _currentDriveId,
      timestamp: record.timestamp,
      speed: record.speed,
      latitude: record.latitude,
      longitude: record.longitude,
      accelerationX: record.accelerationX,
      accelerationY: record.accelerationY,
      accelerationZ: record.accelerationZ,
      totalAcceleration: record.totalAcceleration,
      isSuddenAcceleration: record.isSuddenAcceleration,
      isSuddenBraking: record.isSuddenBraking,
      isSharpTurn: record.isSharpTurn,
    );

    _recordBuffer.add(recordWithDrive);
    
    if (_recordBuffer.length >= AppConfig.batchSize) {
      final db = await database;
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (var record in _recordBuffer) {
          batch.insert(AppConfig.recordsTable, record.toMap());
        }
        await batch.commit();
      });
      _recordBuffer.clear();
      await _cleanOldRecords();
    }
  }

  Future<void> _cleanOldRecords() async {
    final db = await database;
    final cutoffDate = DateTime.now()
        .subtract(Duration(days: AppConfig.retentionDays));
    
    await db.delete(
      AppConfig.recordsTable,
      where: 'timestamp < ?',
      whereArgs: [cutoffDate.millisecondsSinceEpoch],
    );

    await db.delete(
      AppConfig.drivesTable,
      where: 'start_time < ?',
      whereArgs: [cutoffDate.millisecondsSinceEpoch],
    );
  }

  Future<void> debugDatabase() async {
    try {
      final db = await database;
      final recordCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM ${AppConfig.recordsTable}')
      );
      final driveCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM ${AppConfig.drivesTable}')
      );
      print('SDM_LOG: Total records: $recordCount, Total drives: $driveCount');

      if (driveCount != null && driveCount > 0) {
        final drives = await db.query(
          AppConfig.drivesTable,
          limit: 5,
          orderBy: 'start_time DESC'
        );
        print('SDM_LOG: Latest 5 drives:');
        drives.forEach((drive) => print('SDM_LOG: $drive'));
      }
    } catch (e) {
      print('SDM_LOG: Database error: $e');
    }
  }

  Future<List<Drive>> getDrives() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      AppConfig.drivesTable,
      orderBy: 'start_time DESC',
    );
    
    return List.generate(maps.length, (i) => Drive.fromMap(maps[i]));
  }
}
