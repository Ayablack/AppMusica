import 'dart:io';

import 'package:flutter/services.dart';

/// Lê se a tela do aparelho está acesa (Android: `PowerManager.isInteractive`).
class ScreenState {
  static const _channel = MethodChannel('appmusica/screen');

  /// Nulo onde não dá para ler (Windows) ou se o canal falhar.
  static Future<bool?> isOn() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<bool>('isInteractive');
    } on Object {
      return null;
    }
  }
}
