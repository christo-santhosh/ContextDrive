import 'package:flutter/material.dart';
import '../models/drive.dart';
import '../config/app_config.dart';

class DriveDetailPage extends StatelessWidget {
  final Drive drive;

  const DriveDetailPage({Key? key, required this.drive}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final duration = Duration(seconds: drive.durationSeconds);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text('Drive Details', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoCard(
            title: 'Time',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start: ${drive.startTime.toString().split('.')[0]}',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                if (drive.endTime != null)
                  Text(
                    'End: ${drive.endTime.toString().split('.')[0]}',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                Text(
                  'Duration: ${duration.inHours}h ${duration.inMinutes % 60}m ${duration.inSeconds % 60}s',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            title: 'Speed',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Average: ${drive.averageSpeed.toStringAsFixed(1)} km/h',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                Text(
                  'Time Over Speed Limit: ${drive.overSpeedDurationSeconds}s',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            title: 'Events',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sudden Accelerations:',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...drive.suddenAccelerations.entries.map((e) => Text(
                  '${e.value} events at ${DateTime.fromMillisecondsSinceEpoch(e.key * AppConfig.suddenEventGroupInterval * 1000).toString().split('.')[0]}',
                  style: TextStyle(color: Colors.grey[400]),
                )),
                const SizedBox(height: 8),
                Text(
                  'Sudden Brakings:',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...drive.suddenBrakings.entries.map((e) => Text(
                  '${e.value} events at ${DateTime.fromMillisecondsSinceEpoch(e.key * AppConfig.suddenEventGroupInterval * 1000).toString().split('.')[0]}',
                  style: TextStyle(color: Colors.grey[400]),
                )),
                const SizedBox(height: 8),
                Text(
                  'Sharp Turns:',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...drive.sharpTurns.entries.map((e) => Text(
                  '${e.value} events at ${DateTime.fromMillisecondsSinceEpoch(e.key * AppConfig.suddenEventGroupInterval * 1000).toString().split('.')[0]}',
                  style: TextStyle(color: Colors.grey[400]),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required String title, required Widget content}) {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            content,
          ],
        ),
      ),
    );
  }
} 