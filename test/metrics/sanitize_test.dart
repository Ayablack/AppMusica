import 'package:appmusica/metrics/sanitize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remove IPv4', () {
    expect(
      sanitizeForLog('falhou address = 192.168.0.10, port = 47820'),
      'falhou address = <ip>, port = 47820',
    );
  });

  test('remove IPv6', () {
    expect(sanitizeForLog('de fe80::1c2b:3aff:fe4d:5e6f%wlan0'), 'de <ip>');
  });

  test('remove caminhos do Windows, Android e Unix', () {
    expect(
      sanitizeForLog(r'abrindo C:\Users\felip\Music\a.mp3 ok'),
      'abrindo <caminho> ok',
    );
    expect(
      sanitizeForLog('lendo /storage/emulated/0/Music/a b.mp3'),
      'lendo <caminho>',
    );
    expect(sanitizeForLog('em /data/user/0/app/cache/x'), 'em <caminho>');
    expect(sanitizeForLog('file:///C:/Projetos/x.dart:3:1'), '<caminho>');
  });

  test('mantém frames package: do stack trace', () {
    expect(
      sanitizeForLog(
        '#0 _ConnectionLabPageState._join (package:appmusica/lab/connection_lab_page.dart:91:7)',
      ),
      '#0 _ConnectionLabPageState._join (package:appmusica/lab/connection_lab_page.dart:91:7)',
    );
  });

  test('remove e-mail', () {
    expect(sanitizeForLog('conta x@y.com'), 'conta <email>');
  });

  test('describeError dá tipo, mensagem saneada e 3 frames do app', () {
    final st = StackTrace.fromString('''
#0      _HttpClient._openUrl (dart:_http/http_impl.dart:2991:9)
#1      LanSignalingClient.connect (package:appmusica/jam/signaling/lan/lan_signaling_client.dart:40:5)
#2      _ConnectionLabPageState._join (package:appmusica/lab/connection_lab_page.dart:91:7)
#3      _ConnectionLabPageState.build (package:appmusica/lab/connection_lab_page.dart:200:7)
#4      _ConnectionLabPageState.build2 (package:appmusica/lab/connection_lab_page.dart:201:7)
''');

    final text = describeError(
      ArgumentError('No host specified in URI http://10.0.0.5:47820/'),
      st,
    );

    expect(text, startsWith('ArgumentError: '));
    expect(text, isNot(contains('10.0.0.5')));
    expect(text, contains('lan_signaling_client.dart:40'));
    expect(text, contains('connection_lab_page.dart:91'));
    expect(text, contains('connection_lab_page.dart:200'));
    expect(text, isNot(contains('connection_lab_page.dart:201')));
    expect(text, isNot(contains('http_impl.dart')));
  });
}
