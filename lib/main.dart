import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'lab/connection_lab_page.dart';
import 'lab/lab_errors.dart';
import 'lab/player_lab_page.dart';
import 'player/just_audio_local_player.dart';
import 'player/local_player.dart';

/// Player do app (um só); variável global, criada no primeiro uso. Pertence ao app, não às
/// telas: sair de uma tela não para a música.
final LocalPlayer appPlayer = JustAudioLocalPlayer();

void main() {
  LabErrors.install();
  // Windows usa libmpv; Android continua no ExoPlayer do just_audio.
  JustAudioMediaKit.ensureInitialized(windows: true, android: false);
  runApp(const AppMusica());
}

class AppMusica extends StatelessWidget {
  const AppMusica({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppMusica',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const TelaInicial(),
    );
  }
}

/// Tela provisória da Fase 0. Ainda não há player nem Jam.
class TelaInicial extends StatelessWidget {
  const TelaInicial({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AppMusica')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Fase 0: validação técnica', style: textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Protótipo experimental. Nenhuma função de música disponível ainda.',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ConnectionLabPage(),
                  ),
                ),
                child: const Text('Laboratório: conexão'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlayerLabPage(player: appPlayer),
                  ),
                ),
                child: const Text('Laboratório: player'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
