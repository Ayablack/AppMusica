import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../signal_message.dart';
import '../signaling_channel.dart';

/// Cliente do [LanSignalingServer] usado pelos convidados.
class LanSignalingClient {
  static final _ipv4 = RegExp(
    r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$',
  );
  static final _roomCode = RegExp(r'^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{8}$');

  /// Falhas viram [SignalingConnectionFailed] (endereço, rede) ou
  /// [SignalingRejected] (o anfitrião respondeu e recusou).
  static Future<SignalingChannel> connect({
    required String host,
    required int port,
    required String roomCode,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!_ipv4.hasMatch(host) && host != 'localhost') {
      throw SignalingConnectionFailed(
        'invalid_address',
        'Endereço do anfitrião inválido. Digite o IP mostrado na tela do '
            'anfitrião: 4 números separados por pontos.',
      );
    }
    if (port < 1 || port > 65535) {
      throw SignalingConnectionFailed(
        'invalid_port',
        'Porta inválida. Use a porta mostrada na tela do anfitrião.',
      );
    }
    if (!_roomCode.hasMatch(roomCode)) {
      throw SignalingConnectionFailed(
        'invalid_code',
        'O código da sala tem 8 letras e números, como aparece no anfitrião.',
      );
    }

    final WebSocket ws;
    try {
      ws = await WebSocket.connect('ws://$host:$port/').timeout(timeout);
    } on Object catch (e) {
      throw _describe(e);
    }
    return _handshake(ws, roomCode, timeout);
  }

  static Future<SignalingChannel> _handshake(
    WebSocket ws,
    String roomCode,
    Duration timeout,
  ) async {
    final channel = _ClientChannel(ws);
    final welcome = Completer<void>();

    ws.listen(
      (data) {
        final SignalMessage m;
        try {
          m = SignalMessage.fromJson(
            Map<String, Object?>.from(jsonDecode(data as String) as Map),
          );
        } on Object {
          return;
        }
        if (!welcome.isCompleted) {
          if (m.type == SignalType.welcome) {
            channel._selfId = m.payload['peerId'] as String;
            channel._hostId = m.payload['hostPeerId'] as String;
            welcome.complete();
          } else {
            welcome.completeError(
              SignalingRejected(m.payload['reason'] as String? ?? 'protocol'),
            );
          }
          return;
        }
        channel.inbox.add(m);
      },
      onDone: () {
        if (!welcome.isCompleted) {
          welcome.completeError(SignalingRejected('protocol'));
        }
        channel.inbox.close();
      },
      cancelOnError: true,
    );

    ws.add(
      jsonEncode(
        SignalMessage(
          type: SignalType.hello,
          from: '',
          payload: {'roomCode': roomCode},
        ).toJson(),
      ),
    );

    try {
      await welcome.future.timeout(timeout);
    } on TimeoutException {
      await ws.close();
      throw _describe(TimeoutException(null));
    } on Object {
      await ws.close();
      rethrow;
    }
    return channel;
  }

  // Códigos de erro do sistema: Linux/Android, macOS e Windows (Winsock e Win32).
  static const _refused = {111, 61, 10061, 1225};
  static const _timedOut = {110, 60, 10060, 121};
  static const _unreachable = {101, 113, 51, 65, 10051, 10065, 1231, 1232};
  static const _blocked = {1, 13};

  static SignalingConnectionFailed _describe(Object e) {
    if (e is TimeoutException) {
      return SignalingConnectionFailed(
        'timeout',
        'O anfitrião não respondeu. Confira se os dois aparelhos estão na '
            'mesma rede Wi-Fi e se o IP digitado é o da rede Wi-Fi do anfitrião.',
      );
    }
    if (e is ArgumentError || e is FormatException) {
      return SignalingConnectionFailed(
        'invalid_address',
        'Endereço do anfitrião inválido.',
      );
    }
    if (e is WebSocketException) {
      return SignalingConnectionFailed(
        'not_appmusica',
        'Algo respondeu nesse endereço, mas não é uma sala do AppMusica. '
            'Confira o IP e a porta.',
      );
    }
    if (e is SocketException) {
      final code = e.osError?.errorCode;
      if (e.message.contains('host lookup')) {
        return SignalingConnectionFailed(
          'invalid_address',
          'Endereço do anfitrião não encontrado. Digite só números e pontos.',
        );
      }
      if (_refused.contains(code)) {
        return SignalingConnectionFailed(
          'refused',
          'O aparelho foi encontrado, mas não há sala aberta nessa porta. '
              'Confira a porta e se a sala do anfitrião ainda está aberta.',
        );
      }
      if (_timedOut.contains(code)) return _describe(TimeoutException(null));
      if (_unreachable.contains(code)) {
        return SignalingConnectionFailed(
          'unreachable',
          'A rede do anfitrião está inalcançável: os aparelhos parecem estar '
              'em redes diferentes.',
        );
      }
      if (_blocked.contains(code)) {
        return SignalingConnectionFailed(
          'network_blocked',
          'O sistema bloqueou o acesso à rede local para o app. Verifique a '
              'permissão de rede local/dispositivos próximos.',
        );
      }
      return SignalingConnectionFailed(
        'unknown',
        'Falha de rede inesperada (código do sistema $code).',
      );
    }
    return SignalingConnectionFailed(
      'unknown',
      'Falha inesperada ao conectar (${e.runtimeType}).',
    );
  }
}

class _ClientChannel extends SignalingChannel {
  _ClientChannel(this.ws);

  final WebSocket ws;
  final inbox = BufferedBroadcast<SignalMessage>();
  late String _selfId;
  late String _hostId;

  @override
  String get selfId => _selfId;

  @override
  String get hostId => _hostId;

  @override
  Stream<SignalMessage> get messages => inbox.controller.stream;

  @override
  Future<void> send(SignalMessage m) async => ws.add(
    jsonEncode(
      SignalMessage(
        type: m.type,
        from: selfId,
        to: m.to ?? hostId,
        payload: m.payload,
      ).toJson(),
    ),
  );

  @override
  Future<void> close() => ws.close(WebSocketStatus.normalClosure);
}
