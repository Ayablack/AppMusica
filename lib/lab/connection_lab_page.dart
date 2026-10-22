import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../jam/signaling/lan/lan_signaling_client.dart';
import '../jam/signaling/lan/lan_signaling_server.dart';
import '../jam/signaling/signaling_channel.dart';
import '../jam/transport/peer_link.dart';
import '../jam/transport/peer_link_factory.dart';
import '../jam/transport/webrtc_peer_link.dart';
import 'keep_alive.dart';

/// Task 0B — prova mínima de conexão real entre aparelhos (descartável).
///
/// O log da tela nunca mostra IPs nem caminhos; pode ser copiado e colado.
class ConnectionLabPage extends StatefulWidget {
  const ConnectionLabPage({super.key});

  @override
  State<ConnectionLabPage> createState() => _ConnectionLabPageState();
}

class _ConnectionLabPageState extends State<ConnectionLabPage> {
  final _hostField = TextEditingController();
  final _portField = TextEditingController(
    text: '${LanSignalingServer.defaultPort}',
  );
  final _codeField = TextEditingController();
  final _clock = Stopwatch()..start();
  final _log = <String>[];
  final _links = <PeerLink>[];
  final _probes = <String, _Probe>{};

  LanSignalingServer? _server;
  SignalingChannel? _signal;
  PeerLinkFactory? _factory;
  List<String> _addresses = const [];
  Timer? _monitor;
  bool _busy = false;

  bool get _active => _factory != null;

  void _add(String line) {
    final t = _clock.elapsed;
    final stamp =
        '${t.inMinutes.toString().padLeft(2, '0')}:'
        '${(t.inSeconds % 60).toString().padLeft(2, '0')}.'
        '${(t.inMilliseconds % 1000).toString().padLeft(3, '0')}';
    setState(() => _log.insert(0, '$stamp  $line'));
  }

  Future<void> _host() async {
    setState(() => _busy = true);
    try {
      final server = await LanSignalingServer.start();
      _server = server;
      _addresses = await LanSignalingServer.localAddresses();
      _add('anfitrião: sala aberta, código ${server.roomCode}');
      _attach(server.hostChannel, autoConnect: true);
      _add(await JamKeepAlive.start('Anfitrião da sala ${server.roomCode}'));
      _add(await JamKeepAlive.batteryStatus());
    } on Object catch (e) {
      _add('ERRO ao abrir sala: ${e.runtimeType}');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final signal = await LanSignalingClient.connect(
        host: _hostField.text.trim(),
        port: int.parse(_portField.text.trim()),
        roomCode: _codeField.text.trim().toUpperCase(),
      );
      _add('convidado: entrou na sala como ${signal.selfId}');
      _attach(signal, autoConnect: false);
      _add(await JamKeepAlive.start('Convidado na Jam'));
      _add(await JamKeepAlive.batteryStatus());
    } on SignalingRejected catch (e) {
      _add('RECUSADO pelo anfitrião: ${e.reason}');
    } on Object catch (e) {
      _add('ERRO ao entrar: ${e.runtimeType}');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _attach(SignalingChannel signal, {required bool autoConnect}) {
    _signal = signal;
    signal.messages.listen(
      (m) => _add('sinalização: ${m.type.name} de ${m.from}'),
    );
    final factory = PeerLinkFactory(
      signal,
      autoConnect: autoConnect,
      sessionBuilder: (remoteId, {required initiator}) =>
          WebRtcSession.create(remoteId, initiator: initiator),
    );
    _factory = factory;
    factory.links.listen(_onLink);
    setState(() {});
  }

  void _onLink(PeerLink link) {
    final started = _clock.elapsed;
    _links.add(link);
    final probe = _probes[link.remoteId] = _Probe(link, _add);
    _add('${link.remoteId}: negociando conexão');
    link.stateStream.listen((s) async {
      _add('${link.remoteId}: ${s.name}');
      if (s == PeerLinkState.connected) {
        final ms = (_clock.elapsed - started).inMilliseconds;
        final pair = await link.selectedCandidatePairType();
        probe.pairType = pair;
        _add('${link.remoteId}: CONECTADO em $ms ms, par ICE $pair');
      }
      setState(() {});
    });
  }

  Future<void> _testAll() async {
    for (final p in _probes.values) {
      if (p.link.state == PeerLinkState.connected) await p.run();
    }
    setState(() {});
  }

  void _toggleMonitor(bool on) {
    _monitor?.cancel();
    _monitor = null;
    if (on) {
      for (final p in _probes.values) {
        p.resetMonitor();
      }
      _monitor = Timer.periodic(const Duration(seconds: 2), (_) {
        for (final p in _probes.values) {
          p.heartbeat();
        }
        setState(() {});
      });
      _add('monitor ligado: ping a cada 2 s');
    } else {
      _add('monitor desligado');
    }
    setState(() {});
  }

  Future<void> _stop() async {
    _monitor?.cancel();
    _monitor = null;
    await _factory?.dispose();
    if (_server == null) await _signal?.close();
    await _server?.stop();
    await JamKeepAlive.stop();
    _factory = null;
    _server = null;
    _signal = null;
    _links.clear();
    _probes.clear();
    _add('sessão encerrada');
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Laboratório: conexão')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_active) ...[
            FilledButton(
              onPressed: _busy ? null : _host,
              child: const Text('Ser anfitrião'),
            ),
            const SizedBox(height: 24),
            Text('Entrar numa sala', style: text.titleMedium),
            TextField(
              controller: _hostField,
              decoration: const InputDecoration(labelText: 'IP do anfitrião'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _portField,
              decoration: const InputDecoration(labelText: 'Porta'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _codeField,
              decoration: const InputDecoration(labelText: 'Código da sala'),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _join,
              child: const Text('Entrar'),
            ),
          ],
          if (_server != null) ...[
            Text('Sala aberta', style: text.titleMedium),
            SelectableText(
              'IP: ${_addresses.join('  ou  ')}\n'
              'Porta: ${_server!.port}\n'
              'Código: ${_server!.roomCode}',
              style: text.titleLarge,
            ),
          ],
          if (_active) ...[
            const SizedBox(height: 12),
            for (final p in _probes.values)
              Card(
                child: ListTile(
                  title: Text('${p.link.remoteId}: ${p.link.state.name}'),
                  subtitle: Text(p.summary),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _testAll,
                  child: const Text('Testar (ping + 1 MiB)'),
                ),
                FilterChip(
                  label: const Text('Monitor contínuo'),
                  selected: _monitor != null,
                  onSelected: _toggleMonitor,
                ),
                if (JamKeepAlive.supported)
                  OutlinedButton(
                    onPressed: () async {
                      await JamKeepAlive.requestIgnoreBattery();
                      _add(await JamKeepAlive.batteryStatus());
                    },
                    child: const Text('Tirar da otimização de bateria'),
                  ),
                OutlinedButton(onPressed: _stop, child: const Text('Encerrar')),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Log', style: text.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: _log.reversed.join('\n')),
                ),
                child: const Text('Copiar log'),
              ),
            ],
          ),
          for (final line in _log)
            Text(line, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

/// Testes de laboratório sobre um link: ping (RTT), 1 MiB e monitor.
/// Os dois lados respondem às mensagens do outro.
class _Probe {
  _Probe(this.link, this.log) {
    link.ctrlMessages.listen(_onCtrl);
    link.dataMessages.listen(_onData);
  }

  final PeerLink link;
  final void Function(String) log;
  final _clock = Stopwatch()..start();
  final _pending = <int, Completer<int>>{};
  int _nextId = 0;
  String? pairType;
  String result = '';

  // Recepção de 1 MiB.
  BytesBuilder? _incoming;
  int _expected = 0;
  String? _expectedSha;
  final _incomingClock = Stopwatch();
  Completer<Map<String, Object?>>? _blobAck;

  // Monitor.
  int _sent = 0, _answered = 0;
  Duration _lastPong = Duration.zero, _maxGap = Duration.zero;

  String get summary =>
      'par ICE: ${pairType ?? '?'}\n$result'
      '${_sent > 0 ? '\nmonitor: $_answered/$_sent respostas, maior intervalo sem resposta ${(_maxGap.inMilliseconds / 1000).toStringAsFixed(1)} s' : ''}';

  Future<int?> _ping() async {
    final id = _nextId++;
    final c = _pending[id] = Completer<int>();
    final t0 = _clock.elapsedMicroseconds;
    await link.sendCtrl({'t': 'ping', 'id': id});
    try {
      await c.future.timeout(const Duration(seconds: 3));
      return (_clock.elapsedMicroseconds - t0) ~/ 1000;
    } on TimeoutException {
      return null;
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> run() async {
    final rtts = <int>[];
    for (var i = 0; i < 5; i++) {
      final r = await _ping();
      if (r != null) rtts.add(r);
    }
    rtts.sort();
    final rtt = rtts.isEmpty ? 'sem resposta' : '${rtts[rtts.length ~/ 2]} ms';

    final rng = Random(42);
    final blob = Uint8List.fromList(
      List.generate(1 << 20, (_) => rng.nextInt(256)),
    );
    final sha = sha256.convert(blob).toString();
    _blobAck = Completer();
    final sw = Stopwatch()..start();
    await link.sendCtrl({'t': 'blob', 'size': blob.length, 'sha': sha});
    for (var o = 0; o < blob.length; o += 16384) {
      while (link.dataBufferedAmount > 1 << 20) {
        await link.dataBufferedLow.first.timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
      }
      await link.sendData(Uint8List.sublistView(blob, o, o + 16384));
    }
    String blobResult;
    try {
      final ack = await _blobAck!.future.timeout(const Duration(seconds: 30));
      sw.stop();
      final mbps = blob.length / 1048576 / (sw.elapsedMilliseconds / 1000);
      blobResult = ack['match'] == true
          ? 'íntegro em ${sw.elapsedMilliseconds} ms (${mbps.toStringAsFixed(1)} MB/s)'
          : 'SHA-256 NÃO confere';
    } on TimeoutException {
      blobResult = 'sem confirmação em 30 s';
    }
    result = 'RTT mediano: $rtt (${rtts.length}/5)\n1 MiB: $blobResult';
    log('${link.remoteId}: teste → RTT $rtt; 1 MiB $blobResult');
  }

  void resetMonitor() {
    _sent = 0;
    _answered = 0;
    _maxGap = Duration.zero;
    _lastPong = _clock.elapsed;
  }

  void heartbeat() {
    _sent++;
    final id = _nextId++;
    final c = _pending[id] = Completer<int>();
    link.sendCtrl({'t': 'ping', 'id': id});
    c.future
        .then((_) {
          _answered++;
          final now = _clock.elapsed;
          final gap = now - _lastPong;
          if (gap > _maxGap) _maxGap = gap;
          _lastPong = now;
        })
        .timeout(const Duration(seconds: 10), onTimeout: () {})
        .whenComplete(() => _pending.remove(id));
  }

  void _onCtrl(Map<String, Object?> m) {
    switch (m['t']) {
      case 'ping':
        link.sendCtrl({'t': 'pong', 'id': m['id']});
      case 'pong':
        _pending[m['id']]?.complete(0);
      case 'blob':
        _incoming = BytesBuilder(copy: false);
        _expected = m['size'] as int;
        _expectedSha = m['sha'] as String;
        _incomingClock
          ..reset()
          ..start();
      case 'blob_ok':
        _blobAck?.complete(m);
    }
  }

  void _onData(Uint8List d) {
    final b = _incoming;
    if (b == null) return;
    b.add(d);
    if (b.length < _expected) return;
    final match = sha256.convert(b.takeBytes()).toString() == _expectedSha;
    _incoming = null;
    log(
      '${link.remoteId}: recebi 1 MiB em ${_incomingClock.elapsedMilliseconds} ms, SHA-256 ${match ? 'confere' : 'NÃO confere'}',
    );
    link.sendCtrl({'t': 'blob_ok', 'match': match});
  }
}
