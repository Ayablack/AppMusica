import 'package:appmusica/lab/ping_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

PingSample s(
  int sec, {
  int? rtt,
  bool? screenOn = true,
  bool? service = true,
}) => PingSample(
  at: Duration(seconds: sec),
  rttMs: rtt,
  screenOn: screenOn,
  serviceRunning: service,
);

void main() {
  test('conta sucessos e falhas, RTT mediano e máximo', () {
    final m = PingMonitorStats(start: Duration.zero)
      ..record(s(2, rtt: 10))
      ..record(s(4, rtt: 30))
      ..record(s(6))
      ..record(s(8, rtt: 20));

    expect(m.sent, 4);
    expect(m.ok, 3);
    expect(m.failed, 1);
    expect(m.rttMedianMs, 20);
    expect(m.rttMaxMs, 30);
  });

  test(
    'maior intervalo sem resposta conta desde o início e entre sucessos',
    () {
      final m = PingMonitorStats(start: Duration.zero)
        ..record(s(2, rtt: 5))
        ..record(s(4))
        ..record(s(6))
        ..record(s(8))
        ..record(s(10, rtt: 5));

      expect(m.maxGapWithoutAnswer, const Duration(seconds: 8));
    },
  );

  test('falhas no fim contam até o último ping', () {
    final m = PingMonitorStats(start: Duration.zero)
      ..record(s(2, rtt: 5))
      ..record(s(4))
      ..record(s(12));

    expect(m.maxGapWithoutAnswer, const Duration(seconds: 10));
  });

  test('tela apagada: tempo, sucessos e falhas com a tela apagada', () {
    final m = PingMonitorStats(start: Duration.zero)
      ..record(s(2, rtt: 5))
      ..record(s(4, rtt: 6, screenOn: false))
      ..record(s(6, screenOn: false))
      ..record(s(8, rtt: 7, screenOn: false))
      ..record(s(10, rtt: 5));

    expect(m.screenOffConfirmed, isTrue);
    expect(m.screenOffTime, const Duration(seconds: 6));
    expect(m.okWhileScreenOff, 2);
    expect(m.failedWhileScreenOff, 1);
  });

  test('sem leitura de tela (Windows) não confirma tela apagada', () {
    final m = PingMonitorStats(start: Duration.zero)
      ..record(s(2, rtt: 5, screenOn: null));

    expect(m.screenOffConfirmed, isFalse);
    expect(m.summary(), contains('estado da tela: não disponível'));
  });

  test(
    'serviço em primeiro plano parado em algum momento aparece no resumo',
    () {
      final m = PingMonitorStats(start: Duration.zero)
        ..record(s(2, rtt: 5))
        ..record(s(4, rtt: 5, service: false));

      expect(m.serviceAlwaysRunning, isFalse);
      expect(m.summary(), contains('serviço em primeiro plano: PAROU'));
    },
  );

  test('maior atraso entre pings enviados revela timer atrasado', () {
    final m = PingMonitorStats(start: Duration.zero)
      ..record(s(2, rtt: 5))
      ..record(s(4, rtt: 5))
      ..record(s(19, rtt: 5));

    expect(m.maxSendInterval, const Duration(seconds: 15));
  });

  test('csv tem cabeçalho e uma linha por ping, sem IP', () {
    final m = PingMonitorStats(start: Duration.zero)
      ..record(s(2, rtt: 5))
      ..record(s(4, screenOn: false));

    final lines = m.csv().trim().split('\n');
    expect(lines.first, 't_s,ok,rtt_ms,tela_ligada,servico_ativo');
    expect(lines, hasLength(3));
    expect(lines[2], '4.0,0,,0,1');
  });
}
