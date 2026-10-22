
import 'package:flutter/foundation.dart';

import '../metrics/sanitize.dart';

/// Erros não tratados do app, já saneados, para aparecerem no log do
/// laboratório com tipo, mensagem e onde aconteceram.
class LabErrors {
  static final lines = ValueNotifier<List<String>>(const []);

  static void install() {
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      _add(details.exception, details.stack);
      previousFlutter?.call(details);
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _add(error, stack);
      return previousPlatform?.call(error, stack) ?? true;
    };
  }

  static void _add(Object error, StackTrace? stack) {
    lines.value = [
      ...lines.value,
      'ERRO NÃO TRATADO ${describeError(error, stack)}',
    ];
  }
}
