import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../signal_message.dart';
import '../signaling_channel.dart';

/// Cliente do [LanSignalingServer] usado pelos convidados.
class LanSignalingClient {
  static Future<SignalingChannel> connect({
    required String host,
    required int port,
    required String roomCode,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final ws = await WebSocket.connect('ws://$host:$port/').timeout(timeout);
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
    } on Object {
      await ws.close();
      rethrow;
    }
    return channel;
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
