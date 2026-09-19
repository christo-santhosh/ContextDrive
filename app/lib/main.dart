import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ui/home_screen.dart';
import 'services/gps_service.dart';
import 'services/tflite_service.dart';
import 'services/weather_service.dart';
import 'services/time_context_service.dart';
import 'managers/risk_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ContextDriveApp());
}

class ContextDriveApp extends StatelessWidget {
  const ContextDriveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<GpsService>(create: (_) => GpsService()),
        Provider<WeatherService>(create: (_) => WeatherService()),
        Provider<TimeContextService>(create: (_) => TimeContextService()),
        Provider<TfliteService>(create: (_) => TfliteService()),
        ChangeNotifierProxyProvider3<GpsService, WeatherService, TimeContextService, RiskManager>(
          create: (ctx) => RiskManager(
            ctx.read<GpsService>(),
            ctx.read<WeatherService>(),
            ctx.read<TimeContextService>(),
          )..start(),
          update: (ctx, gps, weather, time, previous) => previous ?? RiskManager(gps, weather, time)..start(),
        ),
      ],
      child: MaterialApp(
        title: 'ContextDrive',
        theme: ThemeData.dark().copyWith(
          primaryColor: Colors.blueAccent,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
