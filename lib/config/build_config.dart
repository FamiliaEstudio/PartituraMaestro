enum AppFlavor { debug, release }

class BuildConfig {
  static const String _flavorValue = String.fromEnvironment(
    'APP_FLAVOR',
    defaultValue: 'debug',
  );

  static const bool crashlyticsEnabled = bool.fromEnvironment(
    'ENABLE_CRASHLYTICS',
    defaultValue: false,
  );

  static AppFlavor get flavor {
    switch (_flavorValue) {
      case 'release':
        return AppFlavor.release;
      case 'debug':
      default:
        return AppFlavor.debug;
    }
  }
}

AppFlavor get appFlavor => BuildConfig.flavor;
