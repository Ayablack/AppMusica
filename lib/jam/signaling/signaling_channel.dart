import 'dart:async';

import 'signal_message.dart';

/// Canal de sinalização entre um aparelho e os outros participantes da sala.
///
/// Fase 0: servidor LAN embutido no anfitrião. Bloco B: Firebase.
/// O transporte (PeerLink) e a transferência só conhecem esta interface.
abstract class SignalingChannel {
  String get selfId;
  String get hostId;
  bool get isHost => selfId == hostId;
  Stream<SignalMessage> get messages;

  /// O campo `from` é preenchido pelo canal; quem envia não escolhe.
  Future<void> send(SignalMessage message);
  Future<void> close();
}

class SignalingRejected implements Exception {
  SignalingRejected(this.reason);

  /// `bad_code`, `full`, `blocked` ou `protocol`.
  final String reason;

  String get message => switch (reason) {
    'bad_code' => 'Código da sala incorreto.',
    'full' => 'A sala está cheia (máximo de 5 participantes).',
    'blocked' =>
      'Muitas tentativas com código errado. Aguarde 1 minuto e tente de novo.',
    _ => 'O anfitrião recusou a conexão por erro de protocolo.',
  };

  @override
  String toString() => 'SignalingRejected($reason)';
}

/// Falha ao alcançar o canal de sinalização. [message] é para o usuário e
/// nunca contém IPs ou caminhos.
class SignalingConnectionFailed implements Exception {
  SignalingConnectionFailed(this.code, this.message);

  /// `invalid_address`, `invalid_port`, `invalid_code`, `refused`,
  /// `timeout`, `unreachable`, `network_blocked`, `not_appmusica`, `unknown`.
  final String code;
  final String message;

  @override
  String toString() => 'SignalingConnectionFailed($code): $message';
}

/// Falha ao abrir a sala no anfitrião.
class SignalingServerFailed implements Exception {
  SignalingServerFailed(this.code, this.message);

  /// `port_in_use` ou `bind_failed`.
  final String code;
  final String message;

  @override
  String toString() => 'SignalingServerFailed($code): $message';
}

/// Broadcast que guarda as mensagens até o primeiro ouvinte, para que nada
/// chegue antes de quem conectou ter tempo de escutar.
class BufferedBroadcast<T> {
  BufferedBroadcast() {
    controller = StreamController<T>.broadcast(onListen: _flush);
  }

  late final StreamController<T> controller;
  final _pending = <T>[];

  void add(T value) {
    if (controller.hasListener) {
      controller.add(value);
    } else {
      _pending.add(value);
    }
  }

  void _flush() {
    for (final v in _pending) {
      controller.add(v);
    }
    _pending.clear();
  }

  Future<void> close() => controller.close();
}

/// Sinalização em memória para testes: todos os canais do mesmo hub se
/// enxergam, e o primeiro a entrar é o anfitrião.
class LoopbackSignalingHub {
  final _channels = <String, _LoopbackChannel>{};
  String? _hostId;

  SignalingChannel join(String peerId) {
    _hostId ??= peerId;
    final channel = _LoopbackChannel(this, peerId);
    _channels[peerId] = channel;
    if (peerId != _hostId) {
      _channels[_hostId]!.inbox.add(
        SignalMessage(type: SignalType.peerJoined, from: peerId),
      );
    }
    return channel;
  }

  void _route(SignalMessage m) {
    final targets = m.to == null
        ? _channels.values.where((c) => c.selfId != m.from)
        : [?_channels[m.to]];
    for (final c in targets) {
      c.inbox.add(m);
    }
  }

  void _leave(String peerId) {
    _channels.remove(peerId);
    if (peerId != _hostId && _channels.containsKey(_hostId)) {
      _channels[_hostId]!.inbox.add(
        SignalMessage(type: SignalType.peerLeft, from: peerId),
      );
    }
  }
}

class _LoopbackChannel extends SignalingChannel {
  _LoopbackChannel(this.hub, this.selfId);

  final LoopbackSignalingHub hub;
  final inbox = BufferedBroadcast<SignalMessage>();

  @override
  final String selfId;

  @override
  String get hostId => hub._hostId!;

  @override
  Stream<SignalMessage> get messages => inbox.controller.stream;

  @override
  Future<void> send(SignalMessage m) async => hub._route(
    SignalMessage(type: m.type, from: selfId, to: m.to, payload: m.payload),
  );

  @override
  Future<void> close() async {
    hub._leave(selfId);
    await inbox.close();
  }
}
