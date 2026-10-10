import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import 'package:app/managers/risk_manager.dart';
import 'package:app/services/carla_demo_service.dart';
import 'package:app/services/gps_service.dart';
import 'package:app/services/weather_service.dart';
import 'package:app/services/time_context_service.dart';
import 'package:app/models/context_vector.dart';
import 'package:app/models/app_state.dart';
import 'package:app/ui/debug_settings_sheet.dart';
import 'package:app/ui/home_screen.dart';

class MockWeatherService extends WeatherService {
  MockWeatherService(this._mockCondition);
  final WeatherCondition? _mockCondition;

  @override
  WeatherCondition? get currentWeather => _mockCondition;

  @override
  Future<WeatherCondition> getWeather(double latitude, double longitude, {bool forceRefresh = false}) {
    if (_mockCondition != null) {
      return Future.value(_mockCondition);
    }
    return super.getWeather(latitude, longitude, forceRefresh: forceRefresh);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/sensors/method'),
      (MethodCall methodCall) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('contextdrive/voice_alerts'),
      (MethodCall methodCall) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (MethodCall methodCall) async => <int, int>{
        0: 1,
        1: 1,
        3: 1,
        14: 1,
      },
    );
  });

  group('OpenWeather Debug Sheet Verification', () {
    testWidgets('displays all relevant OpenWeather and location details', (WidgetTester tester) async {
      final sampleWeather = WeatherCondition(
        temperature: 28.4,
        category: WeatherCategory.clear,
        visibilityMeters: 10000,
        description: 'scattered clouds',
        isAvailable: true,
        lastUpdated: DateTime(2026, 10, 11, 2, 15),
        sourceLatitude: 9.9312,
        sourceLongitude: 76.2673,
        locationName: 'Kochi',
        humidity: 82,
        windSpeedMps: 3.6,
      );

      final gpsService = GpsService();
      final weatherService = MockWeatherService(sampleWeather);
      final timeService = TimeContextService();
      final carlaService = CarlaDemoService();
      final riskManager = RiskManager(gpsService, weatherService, timeService, carlaService);

      riskManager.setPositionForTesting(Position(
        latitude: 9.9312,
        longitude: 76.2673,
        timestamp: DateTime(2026, 10, 11, 2, 15),
        accuracy: 5.0,
        altitude: 10.0,
        altitudeAccuracy: 1.0,
        heading: 0.0,
        headingAccuracy: 1.0,
        speed: 0.0,
        speedAccuracy: 0.5,
      ));
      riskManager.setWeatherForTesting(sampleWeather);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<WeatherService>.value(value: weatherService),
            ChangeNotifierProvider<RiskManager>.value(value: riskManager),
            ChangeNotifierProvider<CarlaDemoService>.value(value: carlaService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DebugSettingsSheet(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('OpenWeather API Live'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.textContaining('Location: Kochi'), findsOneWidget);
      expect(find.textContaining('9.9312'), findsOneWidget);
      expect(find.textContaining('76.2673'), findsOneWidget);
      expect(find.text('HTTP 200 OK'), findsOneWidget);
      expect(find.text('28.4 °C'), findsOneWidget);
      expect(find.text('scattered clouds'), findsOneWidget);
      expect(find.text('CLEAR'), findsOneWidget);
      expect(find.text('10.0 km'), findsOneWidget);
      expect(find.text('82%'), findsOneWidget);
      expect(find.text('3.6 m/s'), findsOneWidget);
    });

    testWidgets('shows Pending status when weather is not yet fetched', (WidgetTester tester) async {
      final gpsService = GpsService();
      final weatherService = MockWeatherService(null);
      final timeService = TimeContextService();
      final carlaService = CarlaDemoService();
      final riskManager = RiskManager(gpsService, weatherService, timeService, carlaService);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<WeatherService>.value(value: weatherService),
            ChangeNotifierProvider<RiskManager>.value(value: riskManager),
            ChangeNotifierProvider<CarlaDemoService>.value(value: carlaService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DebugSettingsSheet(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('OpenWeather API Live'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('No weather data fetched yet. Tap Refresh to query OpenWeather API.'), findsOneWidget);
    });
  });

  group('HomeScreen Layout & Overflow Prevention Verification', () {
    testWidgets('HomeScreen renders weather and night pills without duplicate night', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final sampleWeather = WeatherCondition(
        temperature: 26.0,
        category: WeatherCategory.clear,
        visibilityMeters: 10000,
        description: 'overcast clouds',
        isAvailable: true,
        lastUpdated: DateTime(2026, 10, 11, 2, 30),
        sourceLatitude: 9.9312,
        sourceLongitude: 76.2673,
        locationName: 'Kochi',
        humidity: 89,
        windSpeedMps: 2.1,
      );

      final gpsService = GpsService();
      final weatherService = MockWeatherService(sampleWeather);
      final timeService = TimeContextService();
      final carlaService = CarlaDemoService();
      final riskManager = RiskManager(gpsService, weatherService, timeService, carlaService);
      final appState = AppStateModel()..setState(AppState.ready);

      riskManager.setWeatherForTesting(sampleWeather);
      riskManager.overrideIsNight = true;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<GpsService>.value(value: gpsService),
            Provider<WeatherService>.value(value: weatherService),
            Provider<TimeContextService>.value(value: timeService),
            ChangeNotifierProvider<CarlaDemoService>.value(value: carlaService),
            ChangeNotifierProvider<RiskManager>.value(value: riskManager),
            ChangeNotifierProvider<AppStateModel>.value(value: appState),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Weather shows Cloudy (derived from OpenWeather 'overcast clouds')
      expect(find.text('Cloudy'), findsOneWidget);
      // Time shows Day (cleanly separated from weather)
      expect(find.text('Day'), findsOneWidget);
      // No duplicate pills exist
      expect(find.text('Night'), findsNothing);
      // Telemetry metrics are rendered inside with no overflow
      expect(find.text('0 veh'), findsOneWidget);
      expect(find.text('Closing: NO'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
