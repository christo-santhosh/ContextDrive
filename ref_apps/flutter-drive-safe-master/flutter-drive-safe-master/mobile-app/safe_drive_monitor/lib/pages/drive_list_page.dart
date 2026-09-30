import 'package:flutter/material.dart';
import '../models/drive.dart';
import '../services/database_service.dart';
import 'drive_detail_page.dart';

class DriveListPage extends StatefulWidget {
  const DriveListPage({Key? key}) : super(key: key);

  @override
  State<DriveListPage> createState() => _DriveListPageState();
}

class _DriveListPageState extends State<DriveListPage> {
  final DatabaseService _dbService = DatabaseService();
  List<Drive> _drives = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDrives();
  }

  Future<void> _loadDrives() async {
    final drives = await _dbService.getDrives();
    setState(() {
      _drives = drives;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text('Drive History', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _drives.isEmpty
              ? const Center(
                  child: Text(
                    'No drives recorded yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _drives.length,
                  itemBuilder: (context, index) {
                    final drive = _drives[index];
                    final duration = Duration(seconds: drive.durationSeconds);
                    return Card(
                      color: Colors.grey[900],
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DriveDetailPage(drive: drive),
                            ),
                          );
                        },
                        title: Text(
                          drive.startTime.toString().split('.')[0],
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          'Duration: ${duration.inMinutes}m ${duration.inSeconds % 60}s\n'
                          'Avg Speed: ${drive.averageSpeed.toStringAsFixed(1)} km/h',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                        trailing: Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.grey[600],
                          size: 16,
                        ),
                      ),
                    );
                  },
                ),
    );
  }
} 