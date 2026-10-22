import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'peer_link.dart';
import 'peer_link_factory.dart';

/// [RtcSession] sobre `flutter_webrtc`. Quem inicia cria os canais
/// `ctrl` e `data`; o outro lado os recebe em `onDataChannel`.
class WebRtcSession implements RtcSession {
  WebRtcSession._(this._pc, this._link);

  /// Na Fase 0 (mesma rede), `iceServers` fica vazio: só candidatos `host`.
  static Future<WebRtcSession> create(
    String remoteId, {
    required bool initiator,
    List<Map<String, Object?>> iceServers = const [],
  }) async {
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    final link = WebRtcPeerLink._(remoteId, pc);
    final session = WebRtcSession._(pc, link);
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      session._candidates.add({
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    pc.onConnectionState = link._onPcState;
    if (initiator) {
      link._attach(
        await pc.createDataChannel(
          'ctrl',
          RTCDataChannelInit()..ordered = true,
        ),
      );
      link._attach(
        await pc.createDataChannel(
          'data',
          RTCDataChannelInit()..ordered = true,
        ),
      );
    } else {
      pc.onDataChannel = link._attach;
    }
    return session;
  }

  final RTCPeerConnection _pc;
  final WebRtcPeerLink _link;

  /// Não é broadcast: guarda candidatos até a fábrica começar a escutar.
  final _candidates = StreamController<Map<String, Object?>>();

  @override
  PeerLink get link => _link;

  @override
  Stream<Map<String, Object?>> get localCandidates => _candidates.stream;

  @override
  Future<Map<String, Object?>> createOffer() async {
    final offer = await _pc.createOffer();
    await _pc.setLocalDescription(offer);
    return {'type': offer.type, 'sdp': offer.sdp};
  }

  @override
  Future<Map<String, Object?>> acceptOffer(Map<String, Object?> offer) async {
    await _pc.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String?, offer['type'] as String?),
    );
    final answer = await _pc.createAnswer();
    await _pc.setLocalDescription(answer);
    return {'type': answer.type, 'sdp': answer.sdp};
  }

  @override
  Future<void> acceptAnswer(Map<String, Object?> answer) =>
      _pc.setRemoteDescription(
        RTCSessionDescription(
          answer['sdp'] as String?,
          answer['type'] as String?,
        ),
      );

  @override
  Future<void> addCandidate(Map<String, Object?> c) => _pc.addCandidate(
    RTCIceCandidate(
      c['candidate'] as String?,
      c['sdpMid'] as String?,
      c['sdpMLineIndex'] as int?,
    ),
  );

  @override
  Future<void> dispose() async {
    await _candidates.close();
    await _link.close();
  }
}

class WebRtcPeerLink implements PeerLink {
  WebRtcPeerLink._(this.remoteId, this._pc);

  @override
  final String remoteId;
  final RTCPeerConnection _pc;
  RTCDataChannel? _ctrlChannel;
  RTCDataChannel? _dataChannel;
  RTCPeerConnectionState? _pcState;

  final _ctrl = StreamController<Map<String, Object?>>.broadcast();
  final _data = StreamController<Uint8List>.broadcast();
  final _states = StreamController<PeerLinkState>.broadcast();
  final _low = StreamController<void>.broadcast();
  PeerLinkState _state = PeerLinkState.connecting;

  @override
  PeerLinkState get state => _state;
  @override
  Stream<PeerLinkState> get stateStream => _states.stream;
  @override
  Stream<Map<String, Object?>> get ctrlMessages => _ctrl.stream;
  @override
  Stream<Uint8List> get dataMessages => _data.stream;
  @override
  Stream<void> get dataBufferedLow => _low.stream;
  @override
  int get dataBufferedAmount => _dataChannel?.bufferedAmount ?? 0;

  void _attach(RTCDataChannel channel) {
    if (channel.label == 'ctrl') {
      _ctrlChannel = channel;
      channel.onMessage = (m) {
        if (m.isBinary) return;
        try {
          _ctrl.add(Map<String, Object?>.from(jsonDecode(m.text) as Map));
        } on FormatException {
          // Mensagem de controle malformada é descartada.
        }
      };
    } else if (channel.label == 'data') {
      _dataChannel = channel;
      channel.bufferedAmountLowThreshold = PeerLink.bufferedLowThreshold;
      channel.onBufferedAmountLow = (_) => _low.add(null);
      channel.onMessage = (m) {
        if (m.isBinary) _data.add(m.binary);
      };
    }
    channel.onDataChannelState = (_) => _recompute();
    _recompute();
  }

  void _onPcState(RTCPeerConnectionState s) {
    _pcState = s;
    _recompute();
  }

  void _recompute() {
    final open =
        _ctrlChannel?.state == RTCDataChannelState.RTCDataChannelOpen &&
        _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen;
    final next = switch (_pcState) {
      RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
        PeerLinkState.closed,
      RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
      RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
        PeerLinkState.disconnected,
      _ when open => PeerLinkState.connected,
      // Já conectou alguma vez: canal fechado é queda, não negociação.
      _ =>
        _state == PeerLinkState.connecting
            ? PeerLinkState.connecting
            : PeerLinkState.disconnected,
    };
    if (next == _state || _state == PeerLinkState.closed) return;
    _state = next;
    _states.add(next);
  }

  @override
  Future<void> sendCtrl(Map<String, Object?> message) async {
    if (_state != PeerLinkState.connected) return;
    await _ctrlChannel!.send(RTCDataChannelMessage(jsonEncode(message)));
  }

  @override
  Future<void> sendData(Uint8List bytes) async {
    if (_state != PeerLinkState.connected) return;
    await _dataChannel!.send(RTCDataChannelMessage.fromBinary(bytes));
  }

  @override
  Future<String?> selectedCandidatePairType() async {
    final reports = await _pc.getStats();
    final byId = {for (final r in reports) r.id: r};
    String? pairId;
    for (final r in reports) {
      if (r.type == 'transport') {
        pairId = r.values['selectedCandidatePairId'] as String?;
      }
    }
    pairId ??= reports
        .where(
          (r) =>
              r.type == 'candidate-pair' &&
              r.values['state'] == 'succeeded' &&
              r.values['nominated'] == true,
        )
        .firstOrNull
        ?.id;
    final pair = byId[pairId];
    if (pair == null) return null;
    final local = byId[pair.values['localCandidateId']];
    final remote = byId[pair.values['remoteCandidateId']];
    return '${local?.values['candidateType']}/${remote?.values['candidateType']}';
  }

  @override
  Future<void> close() async {
    if (_state == PeerLinkState.closed) return;
    _state = PeerLinkState.closed;
    _states.add(PeerLinkState.closed);
    await _ctrlChannel?.close();
    await _dataChannel?.close();
    await _pc.close();
  }
}
