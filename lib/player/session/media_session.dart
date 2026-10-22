import 'dart:io';

import 'package:audio_service/audio_service.dart';

import '../local_player.dart';
import 'app_audio_handler.dart';

/// Integração do player com os controles de mídia do sistema.
abstract class MediaSession {
  Future<void> attach(LocalPlayer player);
}

/// Android: notificação, tela bloqueada, botões do fone e Android Auto.
class AudioServiceSession implements MediaSession {
  @override
  Future<void> attach(LocalPlayer player) => AudioService.init(
    builder: () => AppAudioHandler(player),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'io.github.ayablack.appmusica.playback',
      androidNotificationChannelName: 'Reprodução',
      androidNotificationOngoing: true,
    ),
  );
}

/// Plataformas ainda sem controles do sistema (Windows até a prova de
/// conceito do SMTC no M3.3).
class NoMediaSession implements MediaSession {
  @override
  Future<void> attach(LocalPlayer player) async {}
}

MediaSession createMediaSession() =>
    Platform.isAndroid ? AudioServiceSession() : NoMediaSession();
