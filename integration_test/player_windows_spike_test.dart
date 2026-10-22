// Task 0A — prova mínima do player no Windows (descartável, só roda localmente).
//
// flutter test integration_test/player_windows_spike_test.dart -d windows \
//   --dart-define=MEDIA_DIR=<pasta com os arquivos gerados por ffmpeg>
//
// Mede com o candidato just_audio + just_audio_media_kit (libmpv):
// posição reportada × relógio, erro de seek, taxa a 1,02× e tom a 1,02×.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' as mk;

const mediaDir = String.fromEnvironment('MEDIA_DIR');

const formats = {
  'wav': 'seno.wav',
  'mp3_cbr': 'seno_cbr.mp3',
  'mp3_vbr': 'seno_vbr.mp3',
  'flac': 'seno.flac',
  'm4a': 'seno.m4a',
};

final results = <String, Map<String, Object>>{};

/// Nenhum teste de integração pode travar a máquina: limite total por teste.
const testLimit = Timeout(Duration(minutes: 2));

Future<void> waitPlaying(AudioPlayer p) => p.playerStateStream
    .firstWhere((s) => s.playing && s.processingState == ProcessingState.ready)
    .timeout(const Duration(seconds: 10));

/// Avanço da posição reportada em [window] de relógio, dividido pelo relógio.
Future<({int driftMs, double rate})> measureAdvance(
  AudioPlayer p,
  Duration window,
) async {
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final sw = Stopwatch()..start();
  final pos0 = p.position;
  await Future<void>.delayed(window);
  final advanced = p.position - pos0;
  sw.stop();
  return (
    driftMs: (advanced - sw.elapsed).inMilliseconds,
    rate: advanced.inMicroseconds / sw.elapsed.inMicroseconds,
  );
}

int percentile(List<int> values, double q) {
  final s = [...values]..sort();
  return s[((s.length - 1) * q).round()];
}

/// Frequência dominante pelo cruzamento de zero no canal 0 de um WAV.
double dominantFrequency(File wav) {
  final b = ByteData.sublistView(wav.readAsBytesSync());
  var offset = 12, format = 1, channels = 2, rate = 44100, bits = 16;
  int? dataStart, dataLen;
  while (offset + 8 <= b.lengthInBytes) {
    final id = String.fromCharCodes(
      Uint8List.sublistView(b, offset, offset + 4),
    );
    final size = b.getUint32(offset + 4, Endian.little);
    if (id == 'fmt ') {
      format = b.getUint16(offset + 8, Endian.little);
      channels = b.getUint16(offset + 10, Endian.little);
      rate = b.getUint32(offset + 12, Endian.little);
      bits = b.getUint16(offset + 22, Endian.little);
    } else if (id == 'data') {
      dataStart = offset + 8;
      // ao=pcm interrompido pode deixar o tamanho do bloco em 0 ou inválido.
      dataLen = (size == 0 || dataStart + size > b.lengthInBytes)
          ? b.lengthInBytes - dataStart
          : size;
      break;
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  if (dataStart == null) throw StateError('WAV sem bloco data');
  final frameBytes = channels * bits ~/ 8;
  final frames = dataLen! ~/ frameBytes;
  double sample(int i) {
    final o = dataStart! + i * frameBytes;
    if (format == 3) return b.getFloat32(o, Endian.little);
    return b.getInt16(o, Endian.little) / 32768.0;
  }

  final skip = rate ~/ 2; // ignora o primeiro meio segundo
  var crossings = 0;
  var prev = sample(skip);
  for (var i = skip + 1; i < frames; i++) {
    final s = sample(i);
    if ((prev < 0 && s >= 0) || (prev >= 0 && s < 0)) crossings++;
    prev = s;
  }
  return crossings / 2 / ((frames - skip) / rate);
}

/// Toca [source] com o mesmo backend do just_audio_media_kit (pitch: true)
/// e grava a saída em WAV, para medir o tom sem depender de microfone.
Future<double> renderedFrequency(
  String source,
  double rate, {
  bool pitch = true,
}) async {
  final out = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}appmusica_tom_${rate}_$pitch.wav',
  );
  if (out.existsSync()) out.deleteSync();
  final player = mk.Player(configuration: mk.PlayerConfiguration(pitch: pitch));
  final native = player.platform as mk.NativePlayer;
  await native.setProperty('ao-pcm-file', out.path);
  await native.setProperty('ao-pcm-waveheader', 'yes');
  await native.setProperty('ao', 'pcm');
  // Controle: sem correção, mudar a velocidade tem que mudar o tom.
  if (!pitch) await native.setProperty('audio-pitch-correction', 'no');
  await player
      .open(mk.Media(source), play: false)
      .timeout(const Duration(seconds: 10));
  await player.setRate(rate);
  await player.play();
  await Future<void>.delayed(const Duration(seconds: 4));
  await player.dispose();
  final f = dominantFrequency(out);
  out.deleteSync();
  return f;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    expect(mediaDir, isNotEmpty, reason: 'passe --dart-define=MEDIA_DIR=...');
    JustAudioMediaKit.ensureInitialized(windows: true, android: false);
    mk.MediaKit.ensureInitialized();
  });

  tearDownAll(() {
    // Uma linha por formato, para copiar para os resultados.
    for (final e in results.entries) {
      // ignore: avoid_print
      print('RESULTADO ${e.key} ${e.value}');
    }
  });

  for (final entry in formats.entries) {
    testWidgets('player Windows: ${entry.key}', (tester) async {
      final r = <String, Object>{};
      results[entry.key] = r;
      final p = AudioPlayer();
      addTearDown(p.dispose);

      final loaded = await p
          .setFilePath('$mediaDir/${entry.value}')
          .timeout(const Duration(seconds: 10));
      r['duracaoMs'] = loaded?.inMilliseconds ?? -1;

      // 1. Posição reportada × relógio a 1,0×.
      await p.play();
      await waitPlaying(p);
      final normal = await measureAdvance(p, const Duration(seconds: 5));
      r['desvioPosicaoMs'] = normal.driftMs;

      // 2. Erro de seek, pausado, em 10 posições.
      await p.pause();
      final errors = <int>[];
      for (var i = 0; i < 10; i++) {
        final target = Duration(milliseconds: 4000 + i * 4700);
        await p.seek(target).timeout(const Duration(seconds: 5));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        errors.add((p.position - target).inMilliseconds.abs());
      }
      r['seekP50Ms'] = percentile(errors, 0.5);
      r['seekP95Ms'] = percentile(errors, 0.95);
      r['seekMaxMs'] = errors.reduce(max);

      // 3. Taxa de avanço a 1,02×.
      await p.seek(const Duration(seconds: 5));
      await p.setSpeed(1.02);
      await p.play();
      await waitPlaying(p);
      final fast = await measureAdvance(p, const Duration(seconds: 5));
      r['taxa102'] = double.parse(fast.rate.toStringAsFixed(4));
      await p.stop();

      expect(
        normal.driftMs.abs(),
        lessThanOrEqualTo(150),
        reason: 'posição reportada se afastou do relógio',
      );
      if (entry.key != 'mp3_vbr') {
        expect(
          r['seekP95Ms'] as int,
          lessThanOrEqualTo(100),
          reason: 'erro de seek p95 acima de 100 ms',
        );
      }
      expect(fast.rate, inInclusiveRange(1.00, 1.04));
    }, timeout: testLimit);
  }

  testWidgets('player Windows: tom preservado a 1,02×', (tester) async {
    final source = '$mediaDir/${formats['wav']}';
    final f100 = await renderedFrequency(source, 1.0);
    final f102 = await renderedFrequency(source, 1.02);
    results['tom'] = {
      'freq100Hz': double.parse(f100.toStringAsFixed(1)),
      'freq102Hz': double.parse(f102.toStringAsFixed(1)),
    };
    expect(f100, inInclusiveRange(990, 1010));
    expect(
      f102,
      inInclusiveRange(990, 1010),
      reason: 'a 1,02× o tom mudou (tom alterado ficaria perto de 1020 Hz)',
    );
  }, timeout: testLimit);

  testWidgets(
    'controle: sem correção de tom a 1,02× a medição acusa ~1020 Hz',
    (tester) async {
      final source = '$mediaDir/${formats['wav']}';
      final f = await renderedFrequency(source, 1.02, pitch: false);
      results['tomControle'] = {
        'freq102SemCorrecaoHz': double.parse(f.toStringAsFixed(1)),
      };
      expect(
        f,
        inInclusiveRange(1010, 1030),
        reason:
            'a medição não detecta mudança de tom; resultado do tom não vale',
      );
    },
    timeout: testLimit,
  );
}
