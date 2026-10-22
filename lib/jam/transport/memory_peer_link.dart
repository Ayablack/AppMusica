import 'dart:async';
import 'dart:typed_data';

import 'peer_link.dart';

/// Par de [PeerLink] em memória, com falhas injetáveis, para testes.
/// Resultados obtidos com ele são sempre "simulados".
class MemoryPeerLink implements PeerLink {
  MemoryPeerLink._(this._selfId, this.remoteId, this._dropAfter, this._corrupt);

  static (MemoryPeerLink, MemoryPeerLink) pair({
    String idA = 'a',
    String idB = 'b',
    int? dropAfterDataMessages,
    Set<int> corruptDataMessages = const {},
  }) {
    final a = MemoryPeerLink._(
      idA,
      idB,
      dropAfterDataMessages,
      corruptDataMessages,
    );
    final b = MemoryPeerLink._(idB, idA, null, const {});
    a._other = b;
    b._other = a;
    return (a, b);
  }

  final String _selfId;
  @override
  final String remoteId;
  final int? _dropAfter;
  final Set<int> _corrupt;
  late MemoryPeerLink _other;

  final _ctrl = StreamController<Map<String, Object?>>.broadcast();
  final _data = StreamController<Uint8List>.broadcast();
  final _states = StreamController<PeerLinkState>.broadcast();
  final _low = StreamController<void>.broadcast();
  PeerLinkState _state = PeerLinkState.connected;
  int _dataSent = 0;
  int _buffered = 0;

  @override
  PeerLinkState get state => _state;
  @override
  Stream<PeerLinkState> get stateStream => _states.stream;
  @override
  Stream<Map<String, Object?>> get ctrlMessages => _ctrl.stream;
  @override
  Stream<Uint8List> get dataMessages => _data.stream;
  @override
  int get dataBufferedAmount => _buffered;
  @override
  Stream<void> get dataBufferedLow => _low.stream;

  bool get _up => _state == PeerLinkState.connected;

  @override
  Future<void> sendCtrl(Map<String, Object?> message) async {
    if (!_up) return;
    // Cópia profunda via ida e volta lógica: quem recebe não compartilha o mapa.
    _other._deliverCtrl(Map<String, Object?>.from(message));
  }

  @override
  Future<void> sendData(Uint8List bytes) async {
    if (!_up) return;
    final index = _dataSent++;
    var copy = Uint8List.fromList(bytes);
    if (_corrupt.contains(index) && copy.isNotEmpty) {
      copy[copy.length - 1] ^= 0xFF;
    }
    _other._deliverData(copy);
    if (_dropAfter != null && _dataSent >= _dropAfter) simulateDisconnect();
  }

  void _deliverCtrl(Map<String, Object?> m) {
    if (_up) scheduleMicrotask(() => _ctrl.add(m));
  }

  void _deliverData(Uint8List d) {
    if (_up) scheduleMicrotask(() => _data.add(d));
  }

  /// Simula o buffer do canal cheio ou esvaziando.
  void setBufferedAmount(int bytes) {
    final wasHigh = _buffered > PeerLink.bufferedLowThreshold;
    _buffered = bytes;
    if (wasHigh && bytes <= PeerLink.bufferedLowThreshold) _low.add(null);
  }

  void _setState(PeerLinkState s) {
    if (_state == s || _state == PeerLinkState.closed) return;
    _state = s;
    _states.add(s);
  }

  void simulateDisconnect() {
    _setState(PeerLinkState.disconnected);
    _other._setState(PeerLinkState.disconnected);
  }

  void simulateReconnect() {
    _setState(PeerLinkState.connected);
    _other._setState(PeerLinkState.connected);
  }

  @override
  Future<String?> selectedCandidatePairType() async => _up ? 'memory' : null;

  @override
  Future<void> close() async {
    _setState(PeerLinkState.closed);
    _other._setState(PeerLinkState.closed);
  }

  @override
  String toString() => 'MemoryPeerLink($_selfId→$remoteId)';
}
