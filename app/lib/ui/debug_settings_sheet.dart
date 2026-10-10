import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../managers/risk_manager.dart';
import '../services/carla_demo_service.dart';

class DebugSettingsSheet extends StatefulWidget {
  const DebugSettingsSheet({super.key});

  @override
  State<DebugSettingsSheet> createState() => _DebugSettingsSheetState();
}

class _DebugSettingsSheetState extends State<DebugSettingsSheet> {
  double? _speed;
  bool? _isRaining;
  bool? _isNight;
  bool? _isErratic;
  int? _speedLimit;

  @override
  void initState() {
    super.initState();
    final riskManager = context.read<RiskManager>();
    _speed = riskManager.overrideSpeed;
    _isRaining = riskManager.overrideIsRaining;
    _isNight = riskManager.overrideIsNight;
    _isErratic = riskManager.overrideIsErratic;
    _speedLimit = riskManager.overrideSpeedLimit;
  }

  void _applySettings() {
    final riskManager = context.read<RiskManager>();
    riskManager.overrideSpeed = _speed;
    riskManager.overrideIsRaining = _isRaining;
    riskManager.overrideIsNight = _isNight;
    riskManager.overrideIsErratic = _isErratic;
    riskManager.overrideSpeedLimit = _speedLimit;
    Navigator.pop(context);
  }

  void _clearSettings() {
    setState(() {
      _speed = null;
      _isRaining = null;
      _isNight = null;
      _isErratic = null;
      _speedLimit = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF161618),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── CARLA Demo Mode Section ──
            _buildCarlaSection(),
            const Divider(color: Colors.white24, height: 32),

            // ── Manual Override Section ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Manual Overrides',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: _clearSettings,
                  child: const Text('Clear All'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'These overrides work in both Real and CARLA mode.\n'
              'Use as a backup if the CARLA connection fails.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 16),
            
            // Speed Override
            const Text('Speed Override (km/h)', style: TextStyle(color: Colors.white70)),
            Slider(
              value: _speed ?? 0,
              min: 0,
              max: 150,
              divisions: 150,
              label: _speed?.toStringAsFixed(0) ?? 'Off',
              activeColor: _speed != null ? Colors.blue : Colors.grey,
              onChanged: (value) {
                setState(() {
                  _speed = value;
                });
              },
            ),
            if (_speed == null)
              const Text('Speed is coming from real GPS / CARLA', style: TextStyle(color: Colors.grey, fontSize: 12)),
            
            const SizedBox(height: 16),
            
            // Speed Limit Override
            const Text('Speed Limit Override (km/h)', style: TextStyle(color: Colors.white70)),
            Slider(
              value: (_speedLimit ?? 0).toDouble(),
              min: 0,
              max: 120,
              divisions: 24,
              label: _speedLimit?.toString() ?? 'Off',
              activeColor: _speedLimit != null ? Colors.orangeAccent : Colors.grey,
              onChanged: (value) {
                setState(() {
                  _speedLimit = value.toInt();
                  if (_speedLimit == 0) _speedLimit = null;
                });
              },
            ),
            if (_speedLimit == null)
              const Text('Speed limit from OSM / CARLA', style: TextStyle(color: Colors.grey, fontSize: 12)),

            const SizedBox(height: 16),
            
            // Weather Override
            const Text('Weather Override', style: TextStyle(color: Colors.white70)),
            Row(
              children: [
                Radio<bool?>(
                  value: null,
                  groupValue: _isRaining,
                  onChanged: (val) => setState(() => _isRaining = val),
                ),
                const Text('Live', style: TextStyle(color: Colors.white)),
                const SizedBox(width: 16),
                Radio<bool?>(
                  value: false,
                  groupValue: _isRaining,
                  onChanged: (val) => setState(() => _isRaining = val),
                ),
                const Text('Clear', style: TextStyle(color: Colors.white)),
                const SizedBox(width: 16),
                Radio<bool?>(
                  value: true,
                  groupValue: _isRaining,
                  onChanged: (val) => setState(() => _isRaining = val),
                ),
                const Text('Raining', style: TextStyle(color: Colors.white)),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Time Override
            const Text('Time Override', style: TextStyle(color: Colors.white70)),
            Row(
              children: [
                Radio<bool?>(
                  value: null,
                  groupValue: _isNight,
                  onChanged: (val) => setState(() => _isNight = val),
                ),
                const Text('Live', style: TextStyle(color: Colors.white)),
                const SizedBox(width: 16),
                Radio<bool?>(
                  value: false,
                  groupValue: _isNight,
                  onChanged: (val) => setState(() => _isNight = val),
                ),
                const Text('Day', style: TextStyle(color: Colors.white)),
                const SizedBox(width: 16),
                Radio<bool?>(
                  value: true,
                  groupValue: _isNight,
                  onChanged: (val) => setState(() => _isNight = val),
                ),
                const Text('Night', style: TextStyle(color: Colors.white)),
              ],
            ),

            const SizedBox(height: 16),

            // This is explicitly a simulator input, not physical IMU evidence.
            const Text('Hard-braking simulation (debug only)', style: TextStyle(color: Colors.white70)),
            Row(
              children: [
                Radio<bool?>(
                  value: null,
                  groupValue: _isErratic,
                  onChanged: (val) => setState(() => _isErratic = val),
                ),
                const Text('Live', style: TextStyle(color: Colors.white)),
                const SizedBox(width: 16),
                Radio<bool?>(
                  value: false,
                  groupValue: _isErratic,
                  onChanged: (val) => setState(() => _isErratic = val),
                ),
                const Text('Normal', style: TextStyle(color: Colors.white)),
                const SizedBox(width: 16),
                Radio<bool?>(
                  value: true,
                  groupValue: _isErratic,
                  onChanged: (val) => setState(() => _isErratic = val),
                ),
                const Text('Hard braking', style: TextStyle(color: Colors.redAccent)),
              ],
            ),
            
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _applySettings,
              child: const Text('Apply Changes', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarlaSection() {
    return Consumer<CarlaDemoService>(
      builder: (context, carlaService, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      carlaService.isRunning ? Icons.cast_connected : Icons.cast,
                      color: carlaService.isRunning ? Colors.greenAccent : Colors.white54,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'CARLA Demo Mode',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: carlaService.isRunning,
                  activeColor: Colors.greenAccent,
                  onChanged: (enabled) async {
                    if (enabled) {
                      await carlaService.start();
                    } else {
                      await carlaService.stop();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: carlaService.isRunning
                    ? Colors.greenAccent.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: carlaService.isRunning
                      ? Colors.greenAccent.withValues(alpha: 0.3)
                      : Colors.white12,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    carlaService.isRunning
                        ? '● Server Active'
                        : '○ Server Inactive',
                    style: TextStyle(
                      color: carlaService.isRunning ? Colors.greenAccent : Colors.white54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    carlaService.statusMessage,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  if (carlaService.isRunning) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Packets received: ${carlaService.packetsReceived}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'CARLA Python script should POST to:\n'
                      'http://<phone-ip>:8080/telemetry',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
