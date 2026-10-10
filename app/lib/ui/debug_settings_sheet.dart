import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../managers/risk_manager.dart';
import '../services/carla_demo_service.dart';
import '../services/weather_service.dart';

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
  bool _isRefreshingWeather = false;

  @override
  void initState() {
    super.initState();
    final riskManager = context.read<RiskManager>();
    _speed = riskManager.overrideSpeed;
    _isRaining = riskManager.overrideIsRaining;
    _isNight = riskManager.overrideIsNight;
    _isErratic = riskManager.overrideIsErratic;
    _speedLimit = riskManager.overrideSpeedLimit;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && riskManager.liveWeather == null) {
        riskManager.refreshLiveWeather();
      }
    });
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
            // ── OpenWeather API Live Status Section ──
            _buildOpenWeatherSection(),
            const Divider(color: Colors.white24, height: 28),

            // ── CARLA Demo Mode Section ──
            _buildCarlaSection(),
            const Divider(color: Colors.white24, height: 28),

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

  Widget _buildOpenWeatherSection() {
    return Consumer2<RiskManager, WeatherService>(
      builder: (context, riskManager, weatherService, _) {
        final weather = riskManager.liveWeather ?? weatherService.currentWeather;
        final pos = riskManager.latestPosition;
        final lat = weather?.sourceLatitude ?? pos?.latitude;
        final lon = weather?.sourceLongitude ?? pos?.longitude;
        final hasLocation = lat != null && lon != null;
        final locationStr = hasLocation
            ? '${lat.toStringAsFixed(4)}° N, ${lon.toStringAsFixed(4)}° E'
            : 'Acquiring device GPS location...';
        final isAvailable = weather?.isAvailable == true;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.wb_sunny_outlined, color: Colors.amberAccent, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'OpenWeather API Live',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                _isRefreshingWeather
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                      )
                    : TextButton.icon(
                        icon: const Icon(Icons.refresh, size: 16, color: Colors.blueAccent),
                        label: const Text('Refresh', style: TextStyle(color: Colors.blueAccent, fontSize: 13)),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () async {
                          setState(() => _isRefreshingWeather = true);
                          try {
                            await riskManager.refreshLiveWeather();
                          } finally {
                            if (mounted) setState(() => _isRefreshingWeather = false);
                          }
                        },
                      ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isAvailable
                    ? Colors.blueAccent.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isAvailable
                      ? Colors.blueAccent.withValues(alpha: 0.3)
                      : Colors.white12,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Location Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.place, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              weather?.locationName != null && weather!.locationName!.isNotEmpty
                                  ? 'Location: ${weather.locationName}'
                                  : 'Device Location',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              locationStr,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isAvailable
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isAvailable ? Colors.greenAccent : Colors.orangeAccent,
                          ),
                        ),
                        child: Text(
                          isAvailable
                              ? 'HTTP 200 OK'
                              : (weatherService.lastError != null ? 'Error' : 'Pending'),
                          style: TextStyle(
                            color: isAvailable ? Colors.greenAccent : Colors.orangeAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 18),

                  if (isAvailable && weather != null) ...[
                    // Weather Metrics Grid
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _weatherMetric(
                          icon: Icons.thermostat,
                          label: 'Temp',
                          value: weather.temperature != null
                              ? '${weather.temperature!.toStringAsFixed(1)} °C'
                              : '--',
                        ),
                        _weatherMetric(
                          icon: Icons.cloud_outlined,
                          label: 'Condition',
                          value: weather.description,
                        ),
                        _weatherMetric(
                          icon: Icons.category_outlined,
                          label: 'Category',
                          value: weather.category.name.toUpperCase(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _weatherMetric(
                          icon: Icons.visibility_outlined,
                          label: 'Visibility',
                          value: weather.visibilityMeters != null
                              ? '${(weather.visibilityMeters! / 1000).toStringAsFixed(1)} km'
                              : '--',
                        ),
                        _weatherMetric(
                          icon: Icons.water_drop_outlined,
                          label: 'Humidity',
                          value: weather.humidity != null ? '${weather.humidity}%' : '--',
                        ),
                        _weatherMetric(
                          icon: Icons.air,
                          label: 'Wind',
                          value: weather.windSpeedMps != null
                              ? '${weather.windSpeedMps!.toStringAsFixed(1)} m/s'
                              : '--',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Last updated: ${weather.lastUpdated.hour.toString().padLeft(2, '0')}:${weather.lastUpdated.minute.toString().padLeft(2, '0')}:${weather.lastUpdated.second.toString().padLeft(2, '0')} · API active',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ] else ...[
                    Text(
                      weatherService.lastError ??
                          'No weather data fetched yet. Tap Refresh to query OpenWeather API.',
                      style: TextStyle(
                        color: weatherService.lastError != null ? Colors.redAccent : Colors.white60,
                        fontSize: 12,
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

  Widget _weatherMetric({required IconData icon, required String label, required String value}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.blueAccent, size: 14),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
