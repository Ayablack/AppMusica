import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../signal_message.dart';
import '../signaling_channel.dart';

/// Servidor de sinalização embutido no anfitrião (Android ou Windows).
///
/// Descartável: no Bloco B o Firebase ocupa este lugar atrás de
/// [SignalingChannel]. O servidor só repassa mensagens de sinalização;
/// não serve arquivos nem diretórios.
class LanSignalingServer {
  LanSignalingServer._(
    this._http,
    this.roomCode,
    this.maxParticipants,
    this.helloTimeout,
    this._clock,
  );

  static const defaultPort = 47820;
  static const maxMessageChars = 64 * 1024;
  static const _alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  static const _maxBadCodes = 5;
  static const _blockWindow = Duration(minutes: 1);

  final HttpServer _http;
  final String roomCode;
  final int maxParticipants;
  final Duration helloTimeout;
  final DateTime Function() _clock;

  final _guests = <String, WebSocket>{};
  final _badCodes = <String, List<DateTime>>{};
  final _blockedUntil = <String, DateTime>{};
  final _random = Random.secure();
  late final _host = _HostChannel(this);

  int get port => _http.port;
  SignalingChannel get hostChannel => _host;

  static String generateRoomCode() {
    final r = Random.secure();
    return String.fromCharCodes(
      List.generate(
        8,
        (_) => _alphabet.codeUnitAt(r.nextInt(_alphabet.length)),
      ),
    );
  }

  static Future<LanSignalingServer> start({
    int port = defaultPort,
    int maxParticipants = 5,
    Duration helloTimeout = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) async {
    final HttpServer http;
    try {
      http = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } on SocketException catch (e) {
      throw _describeBindError(e, port);
    }
    final server = LanSignalingServer._(
      http,
      generateRoomCode(),
      maxParticipants,
      helloTimeout,
      clock ?? DateTime.now,
    );
    http.listen(server._onRequest);
    return server;
  }

  // EADDRINUSE: Linux/Android, macOS, Windows. O Windows às vezes informa -1.
  static const _inUse = {98, 48, 10048, -1};

  static SignalingServerFailed _describeBindError(SocketException e, int port) {
    final code = e.osError?.errorCode;
    if (_inUse.contains(code)) {
      return SignalingServerFailed(
        'port_in_use',
        'A porta $port já está em uso. Feche outra sala aberta neste aparelho '
            'ou espere alguns segundos e tente de novo.',
      );
    }
    return SignalingServerFailed(
      'bind_failed',
      'Não foi possível abrir a sala (código do sistema $code).',
    );
  }

  /// IPv4 locais com o nome da interface, Wi-Fi primeiro, para mostrar na
  /// tela do anfitrião. Nunca vão para logs.
  static Future<List<({String interface, String address})>>
  localAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    bool wifi(String n) =>
        n.startsWith('wlan') || n.toLowerCase().contains('wi-fi');
    final list = [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLoopback) (interface: i.name, address: a.address),
    ];
    list.sort(
      (a, b) =>
          (wifi(a.interface) ? 0 : 1).compareTo(wifi(b.interface) ? 0 : 1),
    );
    return list;
  }

  Future<void> _onRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final address = request.connectionInfo?.remoteAddress.address ?? '?';
    final ws = await WebSocketTransformer.upgrade(request);
    _handshake(ws, address);
  }

  void _handshake(WebSocket ws, String address) {
    String? peerId;
    final timer = Timer(helloTimeout, () {
      if (peerId == null) ws.close(WebSocketStatus.policyViolation, 'hello');
    });

    ws.listen(
      (data) {
        final message = _decode(ws, data);
        if (message == null) return;
        if (peerId == null) {
          timer.cancel();
          peerId = _admit(ws, address, message);
        } else {
          _fromGuest(peerId!, message);
        }
      },
      onDone: () {
        timer.cancel();
        if (peerId != null && _guests.remove(peerId) != null) {
          _host.inbox.add(
            SignalMessage(type: SignalType.peerLeft, from: peerId!),
          );
        }
      },
      cancelOnError: true,
    );
  }

  SignalMessage? _decode(WebSocket ws, Object? data) {
    if (data is! String || data.length > maxMessageChars) {
      ws.close(WebSocketStatus.messageTooBig, 'size');
      return null;
    }
    try {
      return SignalMessage.fromJson(
        Map<String, Object?>.from(jsonDecode(data) as Map),
      );
    } on Object {
      ws.close(WebSocketStatus.protocolError, 'format');
      return null;
    }
  }

  /// Valida o hello e devolve o id do convidado, ou null se recusado.
  String? _admit(WebSocket ws, String address, SignalMessage hello) {
    String? reason;
    final now = _clock();
    final blocked = _blockedUntil[address];
    if (blocked != null && now.isBefore(blocked)) {
      reason = 'blocked';
    } else if (hello.type != SignalType.hello) {
      reason = 'protocol';
    } else if (hello.payload['roomCode'] != roomCode) {
      reason = 'bad_code';
      _registerBadCode(address, now);
    } else if (_guests.length + 1 >= maxParticipants) {
      reason = 'full';
    }
    if (reason != null) {
      _sendTo(
        ws,
        SignalMessage(
          type: SignalType.reject,
          from: _host.selfId,
          payload: {'reason': reason},
        ),
      );
      ws.close(WebSocketStatus.policyViolation, reason);
      return null;
    }

    final id = _newPeerId();
    _guests[id] = ws;
    _sendTo(
      ws,
      SignalMessage(
        type: SignalType.welcome,
        from: _host.selfId,
        to: id,
        payload: {'peerId': id, 'hostPeerId': _host.selfId},
      ),
    );
    _host.inbox.add(SignalMessage(type: SignalType.peerJoined, from: id));
    return id;
  }

  void _registerBadCode(String address, DateTime now) {
    final attempts = (_badCodes[address] ?? [])
      ..removeWhere((t) => now.difference(t) > _blockWindow)
      ..add(now);
    _badCodes[address] = attempts;
    if (attempts.length >= _maxBadCodes) {
      _blockedUntil[address] = now.add(_blockWindow);
      _badCodes.remove(address);
    }
  }

  String _newPeerId() {
    String id;
    do {
      id = 'g${_random.nextInt(1 << 30).toRadixString(36)}';
    } while (_guests.containsKey(id));
    return id;
  }

  /// Convidados só falam com o anfitrião; o remetente vem do servidor.
  void _fromGuest(String peerId, SignalMessage m) {
    _host.inbox.add(
      SignalMessage(
        type: m.type,
        from: peerId,
        to: _host.selfId,
        payload: m.payload,
      ),
    );
  }

  void _fromHost(SignalMessage m) {
    final stamped = SignalMessage(
      type: m.type,
      from: _host.selfId,
      to: m.to,
      payload: m.payload,
    );
    final targets = m.to == null ? _guests.values : [?_guests[m.to]];
    for (final ws in targets) {
      _sendTo(ws, stamped);
    }
  }

  void _sendTo(WebSocket ws, SignalMessage m) => ws.add(jsonEncode(m.toJson()));

  Future<void> stop() async {
    for (final ws in _guests.values.toList()) {
      await ws.close(WebSocketStatus.goingAway);
    }
    _guests.clear();
    await _http.close(force: true);
    await _host.inbox.close();
  }
}

class _HostChannel extends SignalingChannel {
  _HostChannel(this.server);

  final LanSignalingServer server;
  final inbox = BufferedBroadcast<SignalMessage>();

  @override
  String get selfId => 'host';

  @override
  String get hostId => selfId;

  @override
  Stream<SignalMessage> get messages => inbox.controller.stream;

  @override
  Future<void> send(SignalMessage message) async => server._fromHost(message);

  @override
  Future<void> close() => server.stop();
}
