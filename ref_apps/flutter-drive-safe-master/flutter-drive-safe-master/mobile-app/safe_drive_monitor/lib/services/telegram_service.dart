import 'package:televerse/televerse.dart';
import '../config/app_config.dart';

class TelegramService {
  // Singleton pattern
  static final TelegramService _instance = TelegramService._internal();
  factory TelegramService() => _instance;
  
  late final Bot _bot;
  
  // Static timestamps for rate limiting
  static DateTime? _lastSpeedAlert;
  static final Map<String, DateTime> _lastEventByType = {};
  
  // Rate limiting constants (in seconds)
  static const int _speedAlertInterval = 1800;  // 30 minutes
  static const int _suddenEventAlertInterval = 600;  // 10 minutes

  TelegramService._internal() {
    if (AppConfig.telegramBotToken.isNotEmpty) {
      _bot = Bot(AppConfig.telegramBotToken);
    }
  }

  bool _canSendSpeedAlert() {
    if (_lastSpeedAlert == null) return true;
    return DateTime.now().difference(_lastSpeedAlert!).inSeconds >= _speedAlertInterval;
  }

  bool _canSendSuddenEventAlert(String eventType) {
    final lastEvent = _lastEventByType[eventType];
    if (lastEvent == null) return true;
    return DateTime.now().difference(lastEvent).inSeconds >= _suddenEventAlertInterval;
  }

  Future<bool> sendSpeedAlert(double speed) async {
    if (!AppConfig.isTelegramConfigured || !_canSendSpeedAlert()) {
      return false;
    }
    _lastSpeedAlert = DateTime.now();
    try {
      await _bot.api.sendMessage(
        ChatID(int.parse(AppConfig.telegramChatId)),
        '''
🚨 Speed Alert!

Current speed: ${speed.toStringAsFixed(0)} km/h
Speed limit: ${AppConfig.speedThreshold.toStringAsFixed(0)} km/h
''',
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> sendSuddenEventAlert(String eventType, double value) async {
    if (!AppConfig.isTelegramConfigured || !_canSendSuddenEventAlert(eventType)) {
      return false;
    }
    _lastEventByType[eventType] = DateTime.now();
    try {
      String emoji;
      String message;
      switch (eventType) {
        case 'acceleration':
          emoji = '🚗';
          message = 'Sudden acceleration detected';
          break;
        case 'braking':
          emoji = '🛑';
          message = 'Sudden braking detected';
          break;
        case 'turn':
          emoji = '↪️';
          message = 'Sharp turn detected';
          break;
        default:
          return false;
      }

      await _bot.api.sendMessage(
        ChatID(int.parse(AppConfig.telegramChatId)),
        '''
$emoji $message!

Force: ${(value.abs() / 9.81).toStringAsFixed(2)}g
''',
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> sendTestMessage() async {
    if (!AppConfig.isTelegramConfigured) {
      return false;
    }

    try {
      await _bot.api.sendMessage(
        ChatID(int.parse(AppConfig.telegramChatId)),
        '''
✅ Test Message

Safe Drive Monitor is successfully connected!
Your notifications are working correctly.

Time: ${DateTime.now().toString().split('.')[0]}''',
      );
      return true;
    } catch (e) {
      print('Error sending test message: $e');
      return false;
    }
  }

  static String getBotUrl() {
    return 'https://t.me/${AppConfig.telegramBotName}';
  }

} 