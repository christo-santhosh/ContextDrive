import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/settings.dart';
import '../config/app_config.dart';
import '../main.dart';
import './telegram_setup_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Settings _settings;
  bool _isLoading = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('settings');
      
      if (mounted) {
        setState(() {
          _settings = settingsJson != null 
              ? Settings.fromJson(jsonDecode(settingsJson))
              : Settings.defaultSettings();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading settings: $e');
      if (mounted) {
        setState(() {
          _settings = Settings.defaultSettings();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings', jsonEncode(_settings.toJson()));
    await AppConfig.loadSettings();
    if (mounted) {
      Navigator.pop(context);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const MyHomePage(title: 'Safe Drive Monitor'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return WillPopScope(
      onWillPop: () async {
        if (_hasChanges) {
          await _saveSettings();
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.grey[900],
          title: const Text('Settings', style: TextStyle(color: Colors.white)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (_hasChanges) {
                _saveSettings();
              } else {
                Navigator.pop(context);
              }
            },
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSettingSection(
              title: 'Data Retention (Days)',
              value: _settings.retentionDays.toDouble(),
              min: 30,
              max: 365,
              divisions: 67,
              valueLabel: '${_settings.retentionDays} days',
              onChanged: (value) {
                setState(() {
                  _hasChanges = true;
                  _settings = Settings(
                    retentionDays: value.round(),
                    minDrivingSpeed: _settings.minDrivingSpeed,
                    speedLimit: _settings.speedLimit,
                    suddenAccThreshold: _settings.suddenAccThreshold,
                    suddenBrakeThreshold: _settings.suddenBrakeThreshold,
                    sharpTurnThreshold: _settings.sharpTurnThreshold,
                  );
                });
              },
            ),
            
            const SizedBox(height: 24),
            
            _buildSettingSection(
              title: 'Minimum Driving Speed',
              value: _settings.minDrivingSpeed,
              min: 5,
              max: 30,
              divisions: 25,
              valueLabel: '${_settings.minDrivingSpeed.round()} km/h',
              onChanged: (value) {
                setState(() {
                  _hasChanges = true;
                  _settings = Settings(
                    retentionDays: _settings.retentionDays,
                    minDrivingSpeed: value,
                    speedLimit: _settings.speedLimit,
                    suddenAccThreshold: _settings.suddenAccThreshold,
                    suddenBrakeThreshold: _settings.suddenBrakeThreshold,
                    sharpTurnThreshold: _settings.sharpTurnThreshold,
                  );
                });
              },
            ),

            const SizedBox(height: 24),

            _buildSettingSection(
              title: 'Speed Limit',
              value: _settings.speedLimit,
              min: 60,
              max: 130,
              divisions: 70,
              valueLabel: '${_settings.speedLimit.round()} km/h',
              onChanged: (value) {
                setState(() {
                  _hasChanges = true;
                  _settings = Settings(
                    retentionDays: _settings.retentionDays,
                    minDrivingSpeed: _settings.minDrivingSpeed,
                    speedLimit: value,
                    suddenAccThreshold: _settings.suddenAccThreshold,
                    suddenBrakeThreshold: _settings.suddenBrakeThreshold,
                    sharpTurnThreshold: _settings.sharpTurnThreshold,
                  );
                });
              },
            ),

            const SizedBox(height: 24),

            _buildSettingSection(
              title: 'Sudden Acceleration Threshold',
              value: _settings.suddenAccThreshold,
              min: 1.0,
              max: 5.0,
              divisions: 40,
              valueLabel: '${_settings.suddenAccThreshold.toStringAsFixed(1)} m/s²',
              onChanged: (value) {
                setState(() {
                  _hasChanges = true;
                  _settings = Settings(
                    retentionDays: _settings.retentionDays,
                    minDrivingSpeed: _settings.minDrivingSpeed,
                    speedLimit: _settings.speedLimit,
                    suddenAccThreshold: value,
                    suddenBrakeThreshold: _settings.suddenBrakeThreshold,
                    sharpTurnThreshold: _settings.sharpTurnThreshold,
                  );
                });
              },
            ),

            const SizedBox(height: 24),

            _buildSettingSection(
              title: 'Sudden Braking Threshold',
              value: _settings.suddenBrakeThreshold.abs(),
              min: 1.0,
              max: 5.0,
              divisions: 40,
              valueLabel: '${_settings.suddenBrakeThreshold.abs().toStringAsFixed(1)} m/s²',
              onChanged: (value) {
                setState(() {
                  _hasChanges = true;
                  _settings = Settings(
                    retentionDays: _settings.retentionDays,
                    minDrivingSpeed: _settings.minDrivingSpeed,
                    speedLimit: _settings.speedLimit,
                    suddenAccThreshold: _settings.suddenAccThreshold,
                    suddenBrakeThreshold: -value,
                    sharpTurnThreshold: _settings.sharpTurnThreshold,
                  );
                });
              },
            ),

            const SizedBox(height: 24),

            _buildSettingSection(
              title: 'Sharp Turn Threshold',
              value: _settings.sharpTurnThreshold,
              min: 1.0,
              max: 5.0,
              divisions: 40,
              valueLabel: '${_settings.sharpTurnThreshold.toStringAsFixed(1)} m/s²',
              onChanged: (value) {
                setState(() {
                  _hasChanges = true;
                  _settings = Settings(
                    retentionDays: _settings.retentionDays,
                    minDrivingSpeed: _settings.minDrivingSpeed,
                    speedLimit: _settings.speedLimit,
                    suddenAccThreshold: _settings.suddenAccThreshold,
                    suddenBrakeThreshold: _settings.suddenBrakeThreshold,
                    sharpTurnThreshold: value,
                  );
                });
              },
            ),

            const SizedBox(height: 24),
            
            if (AppConfig.telegramBotToken.isNotEmpty) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const TelegramSetupPage()),
                  );
                },
                child: const Text(
                  'Setup Telegram Notification',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingSection({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            Text(
              valueLabel,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 16,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.green,
            inactiveTrackColor: Colors.grey[800],
            thumbColor: Colors.white,
            overlayColor: Colors.green.withOpacity(0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
} 