import 'package:flutter/foundation.dart';

enum AppState {
  starting,
  requestingPermissions,
  initializingModel,
  initializingCamera,
  ready,
  cameraUnavailable,
  locationUnavailable,
  modelFailed,
  error
}

class AppStateModel extends ChangeNotifier {
  AppState _currentState = AppState.starting;
  String _errorMessage = "";

  AppState get currentState => _currentState;
  String get errorMessage => _errorMessage;

  void setState(AppState state, {String error = ""}) {
    if (_currentState != state || _errorMessage != error) {
      _currentState = state;
      _errorMessage = error;
      notifyListeners();
    }
  }
}
