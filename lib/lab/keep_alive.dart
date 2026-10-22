import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Mantém o processo vivo com a tela desligada (Android: serviço em primeiro
/// plano `dataSync` com notificação). Nas outras plataformas não faz nada.
class JamKeepAlive {
  static bool get supported => Platform.isAndroid;

  /// Devolve uma linha legível para o log do laboratório.
  static Future<String> start(String text) async {
    if (!supported) return 'serviço em primeiro plano: não se aplica';
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'appmusica_jam',
        channelName: 'Jam (laboratório)',
        channelDescription: 'Mantém a conexão da Jam com a tela desligada',
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    if (await FlutterForegroundTask.isRunningService) {
      return 'serviço em primeiro plano: já ativo';
    }
    final result = await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: 'AppMusica: laboratório da Jam',
      notificationText: text,
    );
    return result is ServiceRequestSuccess
        ? 'serviço em primeiro plano: ativo'
        : 'serviço em primeiro plano: FALHOU (${result.runtimeType})';
  }

  static Future<void> stop() async {
    if (supported && await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<String> batteryStatus() async {
    if (!supported) return 'otimização de bateria: não se aplica';
    final ignoring = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    return 'otimização de bateria: ${ignoring ? 'desativada para o app' : 'ATIVA'}';
  }

  static Future<void> requestIgnoreBattery() async {
    if (supported) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }
}
