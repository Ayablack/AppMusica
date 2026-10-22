// M3.1 — player local real no Windows (JustAudioLocalPlayer + libmpv).
//
// flutter test integration_test/player_engine_test.dart -d windows \
//   --dart-define=MEDIA_DIR=<pasta com os arquivos gerados por ffmpeg>
//
// As medições de seek usam a posição INFORMADA pelo player: medem latência e
// coerência da API, não a precisão do áudio que sai do alto-falante.
import 'dart:math';

import 'package:appmusica/player/just_audio_local_player.dart';
import 'package:appmusica/player/local_player.dart';
import 'package:appmusica/player/track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

const mediaDir = String.fromEnvironment('MEDIA_DIR');
const testLimit = Timeout(Duration(minutes: 3));

const formats = {
  'wav': 'seno.wav',
  'mp3_cbr': 'seno_cbr.mp3',
  'mp3_vbr': 'seno_vbr.mp3',
  'flac': 'seno.flac',
  'm4a': 'seno.m4a',
};

Track track(String file) =>
    Track(id: file, uri: Uri.file('$mediaDir/$file').toString(), title: file);

Future<void> waitStatus(LocalPlayer p, PlayerStatus s) async {
  if (p.status == s) return;
  await p.statusStream
      .firstWhere((x) => x == s)
      .timeout(const Duration(seconds: 10));
}

int pct(List<int> v, double q) {
  final s = [...v]..sort();
  return s[((s.length - 1) * q).round()];
}

/// Uma rodada de 10 seeks. Devolve latência da API, tempo até acomodar e erro.
Future<Map<String, List<int>>> seekRound(
  LocalPlayer p, {
  required bool playing,
}) async {
  final api = <int>[], settle = <int>[], error = <int>[];
  for (var i = 0; i < 10; i++) {
    final target = Duration(milliseconds: 4000 + i * 4700);
    final sw = Stopwatch()..start();
    await p.seek(target).timeout(const Duration(seconds: 5));
    api.add(sw.elapsedMilliseconds);
    bool settled() {
      final d = (p.position - target).inMilliseconds;
      return playing ? (d >= -20 && d <= 250) : d.abs() <= 50;
    }

    while (!settled() && sw.elapsedMilliseconds < 2000) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    settle.add(sw.elapsedMilliseconds);
    if (!playing) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      error.add((p.position - target).inMilliseconds.abs());
    }
  }
  return {'api': api, 'settle': settle, 'error': error};
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final results = <String, Object>{};

  setUpAll(() {
    expect(mediaDir, isNotEmpty, reason: 'passe --dart-define=MEDIA_DIR=...');
    JustAudioMediaKit.ensureInitialized(windows: true, android: false);
  });

  tearDownAll(() {
    for (final e in results.entries) {
      // ignore: avoid_print
      print('RESULTADO ${e.key} ${e.value}');
    }
  });

  testWidgets('fila: avança sozinho e pula arquivo corrompido', (t) async {
    final p = JustAudioLocalPlayer();
    addTearDown(p.dispose);
    final seen = <String>[];
    final statuses = <PlayerStatus>[];
    final clock = Stopwatch()..start();
    void diag(String m) {
      // ignore: avoid_print
      print('DIAG ${clock.elapsedMilliseconds} ms $m');
    }

    p.currentTrackStream.listen((x) {
      seen.add(x!.id);
      diag('faixa ${x.id}');
    });
    p.statusStream.listen((s) {
      statuses.add(s);
      diag('status ${s.name}');
    });

    await p.setQueue([
      track('curta_a.mp3'),
      track('corrompido.mp3'),
      track('curta_b.mp3'),
    ]);
    await p.play();
    await waitStatus(p, PlayerStatus.playing);
    await p.statusStream
        .firstWhere((s) => s == PlayerStatus.completed)
        .timeout(const Duration(seconds: 20));

    results['fila'] = {
      'faixas': seen,
      'teveErro': statuses.contains(PlayerStatus.error),
    };
    expect(seen, ['curta_a.mp3', 'corrompido.mp3', 'curta_b.mp3']);
    expect(statuses, contains(PlayerStatus.error));
    expect(p.currentTrack!.id, 'curta_b.mp3');
  }, timeout: testLimit);

  for (final f in formats.entries) {
    testWidgets('seek e velocidade: ${f.key}', (t) async {
      final p = JustAudioLocalPlayer();
      addTearDown(p.dispose);
      await p.setQueue([track(f.value)]);
      await waitStatus(p, PlayerStatus.ready);

      final paused = await seekRound(p, playing: false);
      await p.play();
      await waitStatus(p, PlayerStatus.playing);
      final playing = await seekRound(p, playing: true);

      await p.seek(const Duration(seconds: 5));
      await p.setSpeed(1.02);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final sw = Stopwatch()..start();
      final p0 = p.position;
      await Future<void>.delayed(const Duration(seconds: 5));
      final rate = (p.position - p0).inMicroseconds / sw.elapsedMicroseconds;
      await p.pause();

      final api = [...paused['api']!, ...playing['api']!];
      final settle = [...paused['settle']!, ...playing['settle']!];
      final r = {
        'apiP50': pct(api, 0.5),
        'apiP95': pct(api, 0.95),
        'apiMax': api.reduce(max),
        'acomodarP95Pausado': pct(paused['settle']!, 0.95),
        'acomodarP95Tocando': pct(playing['settle']!, 0.95),
        'erroP95': pct(paused['error']!, 0.95),
        'taxa102': double.parse(rate.toStringAsFixed(4)),
      };
      results[f.key] = r;

      expect(
        r['apiP95'] as int,
        lessThanOrEqualTo(100),
        reason: 'latência da API',
      );
      expect(
        pct(settle, 0.95),
        lessThanOrEqualTo(250),
        reason: 'acomodar posição',
      );
      if (f.key != 'mp3_vbr') {
        expect(
          r['erroP95'] as int,
          lessThanOrEqualTo(50),
          reason: 'erro da posição',
        );
      }
      expect(rate, inInclusiveRange(1.00, 1.04));
    }, timeout: testLimit);
  }
}
