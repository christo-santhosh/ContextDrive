import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../managers/risk_manager.dart';

class DebugSettingsSheet extends StatefulWidget {
  const DebugSettingsSheet({super.key});

  @override
  State<DebugSettingsSheet> createState() => _DebugSettingsSheetState();
}

class _DebugSettingsSheetState extends State<DebugSettingsSheet> {
  double? _speed;
  bool? _isRaining;
  bool? _isNight;

  @override
  void initState() {
    super.initState();
    final riskManager = context.read<RiskManager>();
    _speed = riskManager.overrideSpeed;
    _isRaining = riskManager.overrideIsRaining;
    _isNight = riskManager.overrideIsNight;
  }

  void _applySettings() {
    final riskManager = context.read<RiskManager>();
    riskManager.overrideSpeed = _speed;
    riskManager.overrideIsRaining = _isRaining;
    riskManager.overrideIsNight = _isNight;
    Navigator.pop(context);
  }

  void _clearSettings() {
    setState(() {
      _speed = null;
      _isRaining = null;
      _isNight = null;
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Debug Settings',
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
          const SizedBox(height: 24),
          
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
            const Text('Speed is coming from real GPS', style: TextStyle(color: Colors.grey, fontSize: 12)),
          
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
              const Text('Live API', style: TextStyle(color: Colors.white)),
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
              const Text('Live API', style: TextStyle(color: Colors.white)),
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
    );
  }
}
