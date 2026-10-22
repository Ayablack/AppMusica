/// Um ping do monitor contínuo. [rttMs] nulo = sem resposta no prazo.
class PingSample {
  PingSample({
    required this.at,
    required this.rttMs,
    required this.screenOn,
    required this.serviceRunning,
  });

  /// Instante do envio, no relógio do aparelho que monitora.
  final Duration at;
  final int? rttMs;

  /// Estado da tela deste aparelho; nulo onde não dá para ler (Windows).
  final bool? screenOn;
  final bool? serviceRunning;

  bool get ok => rttMs != null;
}

/// Estatísticas do teste de tela desligada (descartável, só Fase 0).
class PingMonitorStats {
  PingMonitorStats({required this.start});

  final Duration start;
  final samples = <PingSample>[];

  Duration _lastOk = Duration.zero;
  Duration _maxGap = Duration.zero;
  Duration _maxSend = Duration.zero;
  Duration _screenOff = Duration.zero;

  void record(PingSample s) {
    final prev = samples.isEmpty ? start : samples.last.at;
    if (samples.isEmpty) _lastOk = start;
    final sendGap = s.at - prev;
    if (sendGap > _maxSend) _maxSend = sendGap;
    if (s.screenOn == false) _screenOff += sendGap;
    if (s.ok) {
      final gap = s.at - _lastOk;
      if (gap > _maxGap) _maxGap = gap;
      _lastOk = s.at;
    }
    samples.add(s);
  }

  int get sent => samples.length;
  int get ok => samples.where((s) => s.ok).length;
  int get failed => sent - ok;

  List<int> get _rtts => [for (final s in samples) ?s.rttMs]..sort();
  int? get rttMedianMs => _rtts.isEmpty ? null : _rtts[_rtts.length ~/ 2];
  int? get rttMaxMs => _rtts.isEmpty ? null : _rtts.last;

  Duration get maxGapWithoutAnswer {
    if (samples.isEmpty) return Duration.zero;
    final tail = samples.last.at - _lastOk;
    return tail > _maxGap ? tail : _maxGap;
  }

  Duration get maxSendInterval => _maxSend;
  Duration get screenOffTime => _screenOff;
  bool get screenOffConfirmed => samples.any((s) => s.screenOn == false);
  bool get screenReadable => samples.any((s) => s.screenOn != null);
  int get okWhileScreenOff =>
      samples.where((s) => s.screenOn == false && s.ok).length;
  int get failedWhileScreenOff =>
      samples.where((s) => s.screenOn == false && !s.ok).length;
  bool get serviceAlwaysRunning =>
      samples.every((s) => s.serviceRunning != false);

  static String _sec(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';

  String summary() {
    final screen = !screenReadable
        ? 'estado da tela: não disponível neste aparelho'
        : screenOffConfirmed
        ? 'tela APAGADA confirmada por ${_sec(screenOffTime)}: '
              '$okWhileScreenOff respostas, $failedWhileScreenOff falhas'
        : 'tela não foi apagada durante o monitor';
    final service = samples.any((s) => s.serviceRunning != null)
        ? 'serviço em primeiro plano: '
              '${serviceAlwaysRunning ? 'ativo o tempo todo' : 'PAROU em algum momento'}'
        : 'serviço em primeiro plano: não se aplica';
    return [
      'pings: $sent enviados, $ok respostas, $failed falhas',
      'RTT: mediano ${rttMedianMs ?? '-'} ms, máximo ${rttMaxMs ?? '-'} ms',
      'maior intervalo sem resposta: ${_sec(maxGapWithoutAnswer)}',
      'maior atraso entre envios: ${_sec(maxSendInterval)}',
      screen,
      service,
    ].join('\n');
  }

  String csv() {
    String flag(bool? v) => v == null ? '' : (v ? '1' : '0');
    return [
      't_s,ok,rtt_ms,tela_ligada,servico_ativo',
      for (final s in samples)
        '${(s.at.inMilliseconds / 1000).toStringAsFixed(1)},'
            '${s.ok ? 1 : 0},${s.rttMs ?? ''},'
            '${flag(s.screenOn)},${flag(s.serviceRunning)}',
    ].join('\n');
  }
}
