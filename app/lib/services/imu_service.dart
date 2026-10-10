/// Physical motion classification is intentionally unavailable in this MVP.
/// A phone accelerometer measures the phone's axes, not the vehicle's forward
/// axis. Without a repeatable mount-orientation calibration, a magnitude or a
/// single axis cannot honestly distinguish braking from acceleration.
class ImuService {
  bool get isDirectionalClassificationAvailable => false;

  void start() {
    // Reserved for a calibrated mount-orientation implementation.
  }

  void stop() {}
}
