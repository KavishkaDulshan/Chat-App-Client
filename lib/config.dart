import 'package:flutter/foundation.dart'; // <--- USE THIS, NOT dart:io

class AppConfig {
  static const bool isProduction = true;
  static const String productionUrl =
      'http://blinkchat.uaenorth.cloudapp.azure.com';

  static String get baseUrl {
    if (isProduction) {
      return productionUrl;
    }

    // 1. CHECK WEB FIRST
    if (kIsWeb) {
      return 'http://localhost:3000'; // Chrome/Web always uses localhost
    }

    // 2. CHECK ANDROID (Using Foundation, not IO)
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }

    // 3. IOS / WINDOWS
    return 'http://localhost:3000';
  }
}
