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
import '../metrics/sanitize.dart';
import 'keep_alive.dart';
import 'lab_errors.dart';
import 'ping_monitor.dart';
import 'screen_state.dart';

/// Task 0B — prova mínima de conexão real entre aparelhos (descartável).
///
/// Toda linha do log passa por [sanitizeForLog]: o log pode ser copiado e
/// colado sem expor IPs, caminhos ou e-mails.
class ConnectionLabPage extends StatefulWidget {
  const ConnectionLabPage({super.key});

  @override
  State<ConnectionLabPage> createState() => _ConnectionLabPageState();
}

class _ConnectionLabPageState extends State<ConnectionLabPage>
    with WidgetsBindingObserver {
  final _hostField = TextEditingController();
  final _portField = TextEditingController(
    text: '${LanSignalingServer.defaultPort}',
  );
  final _codeField = TextEditingController();
  final _clock = Stopwatch()..start();
  final _log = <String>[];
  final _probes = <String, _Probe>{};

  LanSignalingServer? _server;
  SignalingChannel? _signal;
  PeerLinkFactory? _factory;
  List<({String interface, String address})> _addresses = const [];
  bool _monitoring = false;
  bool _busy = false;
  int _errorsShown = 0;

  bool get _active => _factory != null;

  /// Eventos de rede chegam depois de a tela fechar; só redesenha se ela existe.
  @override
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(fn);
    } else {
      fn();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LabErrors.lines.addListener(_onUnhandledError);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _add('app: ${state.name}');

  void _onUnhandledError() {
    final all = LabErrors.lines.value;
    for (final line in all.skip(_errorsShown)) {
      _add(line);
    }
    _errorsShown = all.length;
  }

  void _add(String line) {
    final t = _clock.elapsed;
    final stamp =
        '${t.inMinutes.toString().padLeft(2, '0')}:'
        '${(t.inSeconds % 60).toString().padLeft(2, '0')}.'
        '${(t.inMilliseconds % 1000).toString().padLeft(3, '0')}';
    setState(() => _log.insert(0, '$stamp  ${sanitizeForLog(line)}'));
  }

  Future<void> _host() async {
    setState(() => _busy = true);
    try {
      final server = await LanSignalingServer.start();
      _server = server;
      _addresses = await LanSignalingServer.localAddresses();
      _add('anfitrião: sala aberta, código ${server.roomCode}');
      _add(
        'interfaces de rede: ${_addresses.map((a) => a.interface).join(', ')}',
      );
      _attach(server.hostChannel, autoConnect: true);
      await _startKeepAlive('Anfitrião da sala ${server.roomCode}');
    } on SignalingServerFailed catch (e) {
      _add('ERRO ao abrir sala [${e.code}]: ${e.message}');
    } on Object catch (e, st) {
      _add('ERRO ao abrir sala: ${describeError(e, st)}');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final signal = await LanSignalingClient.connect(
        host: _hostField.text.trim(),
        port: int.tryParse(_portField.text.trim()) ?? 0,
        roomCode: _codeField.text.trim().toUpperCase(),
      );
      _add('convidado: entrou na sala como ${signal.selfId}');
      _attach(signal, autoConnect: false);
      await _startKeepAlive('Convidado na Jam');
    } on SignalingConnectionFailed catch (e) {
      _add('NÃO CONECTOU [${e.code}]: ${e.message}');
    } on SignalingRejected catch (e) {
      _add('RECUSADO pelo anfitrião [${e.reason}]: ${e.message}');
    } on Object catch (e, st) {
      _add('ERRO ao entrar: ${describeError(e, st)}');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _startKeepAlive(String text) async {
    _add(await JamKeepAlive.start(text));
    _add(await JamKeepAlive.batteryStatus());
  }

  void _attach(SignalingChannel signal, {required bool autoConnect}) {
    _signal = signal;
    signal.messages.listen(
      (m) => _add('sinalização: ${m.type.name} de ${m.from}'),
      onDone: () => _add('sinalização encerrada'),
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
    final probe = _probes[link.remoteId] = _Probe(link, _add);
    _add('${link.remoteId}: negociando conexão');
    link.stateStream.listen((s) async {
      _add('${link.remoteId}: ${s.name}');
      if (s == PeerLinkState.connected) {
        final ms = (_clock.elapsed - started).inMilliseconds;
        try {
          probe.pairType = await link.selectedCandidatePairType();
        } on Object catch (e, st) {
          _add('${link.remoteId}: getStats falhou: ${describeError(e, st)}');
        }
        _add(
          '${link.remoteId}: CONECTADO em $ms ms, par ICE ${probe.pairType}',
        );
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
    setState(() => _monitoring = on);
    if (on) {
      _add('monitor ligado: um ping a cada 2 s por convidado, prazo de 3 s');
      for (final p in _probes.values) {
        p.monitor(() => _monitoring, () => setState(() {}));
      }
    } else {
      _add('monitor desligado');
      for (final p in _probes.values) {
        final stats = p.stats;
        if (stats != null) _add('${p.link.remoteId}: ${stats.summary()}');
      }
    }
  }

  void _copyMonitor() {
    final text = [
      for (final p in _probes.values)
        if (p.stats != null) ...[
          '== ${p.link.remoteId} (par ICE ${p.pairType}) ==',
          p.stats!.summary(),
          p.stats!.csv(),
        ],
    ].join('\n');
    Clipboard.setData(ClipboardData(text: sanitizeForLog(text)));
    _add('resultado do monitor copiado');
  }

  Future<void> _stop() async {
    _monitoring = false;
    await _factory?.dispose();
    if (_server == null) await _signal?.close();
    await _server?.stop();
    await JamKeepAlive.stop();
    _factory = null;
    _server = null;
    _signal = null;
    _probes.clear();
    _add('sessão encerrada');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LabErrors.lines.removeListener(_onUnhandledError);
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
              decoration: const InputDecoration(
                labelText: 'IP do anfitrião',
                hintText: 'o IP da linha Wi-Fi na tela do anfitrião',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
            for (final a in _addresses)
              SelectableText(
                '${a.address}   (${a.interface})',
                style: text.titleLarge,
              ),
            SelectableText(
              'Porta: ${_server!.port}\nCódigo: ${_server!.roomCode}',
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
                  selected: _monitoring,
                  onSelected: _toggleMonitor,
                ),
                OutlinedButton(
                  onPressed: _copyMonitor,
                  child: const Text('Copiar resultado do monitor'),
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

  static const _pingTimeout = Duration(seconds: 3);
  static const _monitorInterval = Duration(seconds: 2);

  final PeerLink link;
  final void Function(String) log;
  final _clock = Stopwatch()..start();
  final _pending = <int, Completer<void>>{};
  int _nextId = 0;
  String? pairType;
  String result = '';
  PingMonitorStats? stats;

  // Recepção de 1 MiB.
  BytesBuilder? _incoming;
  int _expected = 0;
  String? _expectedSha;
  final _incomingClock = Stopwatch();
  Completer<Map<String, Object?>>? _blobAck;

  String get summary => [
    'par ICE: ${pairType ?? '?'}',
    if (result.isNotEmpty) result,
    if (stats != null) stats!.summary(),
  ].join('\n');

  /// RTT em ms, ou nulo sem resposta no prazo.
  Future<int?> _ping() async {
    final id = _nextId++;
    final c = _pending[id] = Completer<void>();
    final t0 = _clock.elapsedMicroseconds;
    try {
      await link.sendCtrl({'t': 'ping', 'id': id});
      await c.future.timeout(_pingTimeout);
      return (_clock.elapsedMicroseconds - t0) ~/ 1000;
    } on TimeoutException {
      return null;
    } finally {
      _pending.remove(id);
    }
  }

  /// Pings em sequência (um termina antes do próximo), para que atraso de
  /// timer com a tela apagada apareça como intervalo maior entre envios.
  Future<void> monitor(bool Function() active, void Function() refresh) async {
    final s = stats = PingMonitorStats(start: _clock.elapsed);
    bool? lastScreen;
    while (active() && link.state != PeerLinkState.closed) {
      final at = _clock.elapsed;
      final screenOn = await ScreenState.isOn();
      final service = await JamKeepAlive.isRunning();
      if (screenOn != null && screenOn != lastScreen) {
        log('${link.remoteId}: tela ${screenOn ? 'ACESA' : 'APAGADA'}');
        lastScreen = screenOn;
      }
      final rtt = await _ping();
      s.record(
        PingSample(
          at: at,
          rttMs: rtt,
          screenOn: screenOn,
          serviceRunning: service,
        ),
      );
      if (rtt == null) log('${link.remoteId}: ping sem resposta');
      refresh();
      final wait = _monitorInterval - (_clock.elapsed - at);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
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

  void _onCtrl(Map<String, Object?> m) {
    switch (m['t']) {
      case 'ping':
        link.sendCtrl({'t': 'pong', 'id': m['id']});
      case 'pong':
        final c = _pending[m['id']];
        if (c != null && !c.isCompleted) c.complete();
      case 'blob':
        _incoming = BytesBuilder(copy: false);
        _expected = m['size'] as int;
        _expectedSha = m['sha'] as String;
        _incomingClock
          ..reset()
          ..start();
      case 'blob_ok':
        final ack = _blobAck;
        if (ack != null && !ack.isCompleted) ack.complete(m);
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
