import 'dart:async';

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../player/local_player.dart';
import '../player/track.dart';
import 'lab_log.dart';

/// Escolhe arquivos de áudio do aparelho e monta as faixas.
Future<List<Track>> pickAudioTracks() async {
  // file_picker 13: seleção múltipla é o padrão e o retorno é a lista.
  final files = await FilePicker.pickFiles(type: FileType.audio);
  return [
    for (final (i, f) in files.indexed)
      if (f.path != null)
        Track(
          id: 'f${i}_${f.name}',
          uri: Uri.file(f.path!).toString(),
          title: f.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        ),
  ];
}

/// Arquivos copiados por `adb push` para a pasta privada do app
/// (Android: `Android/data/<app>/files/teste`), sem permissão de
/// armazenamento. Só para testes automatizados no aparelho.
Future<List<Track>> loadDeviceTestTracks() async {
  final base = Platform.isAndroid
      ? await getExternalStorageDirectory()
      : await getApplicationSupportDirectory();
  if (base == null) return const [];
  final dir = Directory('${base.path}${Platform.pathSeparator}teste');
  if (!dir.existsSync()) return const [];
  final files = dir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      Track(
        id: f.uri.pathSegments.last,
        uri: f.uri.toString(),
        title: f.uri.pathSegments.last.replaceFirst(RegExp(r'\.[^.]+$'), ''),
      ),
  ];
}

/// Laboratório do player local (descartável, Fase 0).
///
/// O player é do app, não da tela: sair da tela não para a música, como
/// num app de música de verdade.
class PlayerLabPage extends StatefulWidget {
  const PlayerLabPage({
    super.key,
    required this.player,
    this.pickTracks = pickAudioTracks,
    this.loadTestTracks = loadDeviceTestTracks,
  });

  final LocalPlayer player;
  final Future<List<Track>> Function() pickTracks;
  final Future<List<Track>> Function() loadTestTracks;

  @override
  State<PlayerLabPage> createState() => _PlayerLabPageState();
}

class _PlayerLabPageState extends State<PlayerLabPage> {
  final _log = LabLog();
  final _seekField = TextEditingController();
  late final List<StreamSubscription<Object?>> _subs;
  Duration _position = Duration.zero;
  bool _fast = false;

  LocalPlayer get _player => widget.player;

  @override
  void initState() {
    super.initState();
    _subs = [
      _player.statusStream.listen((s) => _add('status → ${s.name}')),
      _player.currentTrackStream.listen((t) => _add('faixa: ${t?.title}')),
      _player.positionStream.listen((p) => setState(() => _position = p)),
    ];
  }

  void _add(String line) => setState(() => _log.add(line));

  Future<void> _pick() => _load(widget.pickTracks);

  Future<void> _load(Future<List<Track>> Function() source) async {
    final tracks = await source();
    if (tracks.isEmpty) {
      _add('nenhum arquivo encontrado');
      return;
    }
    _add('fila com ${tracks.length} faixas');
    await _player.setQueue(tracks);
    setState(() {});
  }

  Future<void> _toggleSpeed() async {
    _fast = !_fast;
    await _player.setSpeed(_fast ? 1.02 : 1.0);
    _add('velocidade ${_fast ? '1,02' : '1,00'}×');
  }

  Future<void> _seek() async {
    final s = int.tryParse(_seekField.text.trim());
    if (s == null) return;
    await _player.seek(Duration(seconds: s));
  }

  /// P7: tempo entre pedir seek(0)+play e o player informar "tocando".
  Future<void> _measurePrep() async {
    final samples = <int>[];
    for (var i = 0; i < 10; i++) {
      await _player.pause();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final sw = Stopwatch()..start();
      await _player.seek(Duration.zero);
      await _player.play();
      try {
        if (_player.status != PlayerStatus.playing) {
          await _player.statusStream
              .firstWhere((s) => s == PlayerStatus.playing)
              .timeout(const Duration(seconds: 5));
        }
        samples.add(sw.elapsedMilliseconds);
      } on TimeoutException {
        _add('P7: não tocou em 5 s');
      }
    }
    await _player.pause();
    if (samples.isEmpty) return;
    samples.sort();
    _add(
      'P7 preparo (posição informada): p50 ${samples[samples.length ~/ 2]} ms, '
      'p95 ${samples[((samples.length - 1) * 0.95).round()]} ms, '
      'amostras ${samples.join(',')}',
    );
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final playing = _player.status == PlayerStatus.playing;
    return Scaffold(
      appBar: AppBar(title: const Text('Laboratório: player')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _pick,
                child: const Text('Escolher músicas'),
              ),
              OutlinedButton(
                onPressed: () => _load(widget.loadTestTracks),
                child: const Text('Carregar arquivos de teste'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _player.currentTrack?.title ?? 'nenhuma faixa',
            style: text.titleLarge,
          ),
          Text('status: ${_player.status.name}'),
          Text('posição: ${_fmt(_position)}'),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Anterior',
                icon: const Icon(Icons.skip_previous),
                onPressed: _player.previous,
              ),
              IconButton.filled(
                tooltip: playing ? 'Pausar' : 'Tocar',
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: playing ? _player.pause : _player.play,
              ),
              IconButton(
                tooltip: 'Próxima',
                icon: const Icon(Icons.skip_next),
                onPressed: _player.next,
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                onPressed: _toggleSpeed,
                child: Text(_fast ? 'Voltar a 1,00×' : 'Velocidade 1,02×'),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _seekField,
                  decoration: const InputDecoration(labelText: 'Seek (s)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              OutlinedButton(onPressed: _seek, child: const Text('Ir')),
              OutlinedButton(
                onPressed: _measurePrep,
                child: const Text('Medir preparo (P7)'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Fila', style: text.titleMedium),
          for (final t in _player.queue)
            Text(
              '${identical(t, _player.currentTrack) ? '▶ ' : '   '}${t.title}',
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Log', style: text.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: _log.lines.reversed.join('\n')),
                ),
                child: const Text('Copiar log'),
              ),
            ],
          ),
          for (final line in _log.lines)
            Text(line, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
