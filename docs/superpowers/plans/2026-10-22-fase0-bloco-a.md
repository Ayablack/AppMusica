# Fase 0 · Bloco A — Player local e transferência na mesma rede: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provar, em aparelhos reais (S25, A53, PC Windows), o player local com integração de sistema (segundo plano, tela bloqueada, controles de mídia, Android Auto) e a transferência de arquivos por WebRTC DataChannel na mesma rede Wi-Fi, com métricas registradas em JSONL.

**Architecture:** O player é um módulo independente (`lib/player/`) com a interface `LocalPlayer`, um motor comum sobre `just_audio` e adaptadores de sessão de mídia por plataforma. A Jam é construída em camadas trocáveis: `SignalingChannel` (LAN agora, Firebase no Bloco B) → `PeerLink` (WebRTC agora, memória nos testes) → protocolo de transferência (puro Dart, definitivo). Qualquer aparelho pode ser anfitrião.

**Tech Stack:** Flutter 3.47.2 / Dart 3.13.2 · `just_audio` · `just_audio_media_kit` + `media_kit_libs_windows_audio` (Windows) · `audio_service` (Android) · `smtc_windows` (Windows) · `flutter_webrtc` · `crypto` · `file_picker` · `device_info_plus` · `path_provider`.

**Spec:** [docs/superpowers/specs/2026-10-21-fase0-validacao-design.md](../specs/2026-10-21-fase0-validacao-design.md)

## Global Constraints

- Nada de Firebase, Cloudflare, STUN ou TURN neste bloco. `iceServers` vazio (só candidatos `host`).
- Nenhuma chave, token ou credencial no repositório.
- O player nunca importa nada de `lib/jam/`. Erro na Jam nunca interrompe a reprodução local.
- Arquivo nunca é carregado inteiro em memória para enviar, receber ou calcular hash.
- Limite de **5 participantes no total** por sala (anfitrião + 4).
- Bloco de transferência padrão **16 KiB**; testar também **64 KiB**.
- Janela de créditos padrão **64 blocos**; backpressure do canal: pausa acima de **1 MiB** em `bufferedAmount`, retoma abaixo de **256 KiB**.
- Arquivo parcial sem reconexão é apagado após **10 min**. Cache da Jam com teto de **1 GB**, apagado ao sair da Jam e na inicialização.
- SHA-256 identifica arquivos idênticos byte a byte; mesma música com outra codificação é outro arquivo.
- Logs JSONL sem caminhos de arquivo, nomes de arquivo do usuário, IPs ou dados pessoais.
- Tudo na branch `fase0/bloco-a`; a `main` só recebe o bloco depois dos testes reais aprovados.
- Identificadores de código em inglês; textos de interface, mensagens de commit e documentação em português.

## Review Focus

1. **Disco cheio ao receber** → a transferência termina com `FAIL {reason: "disk"}`, o `.part` e o `.state` são apagados, o app continua estável. Teste na Task 10.
2. **Arquivo de origem alterado ou apagado durante o envio** → o remetente detecta (tamanho ou data de modificação mudou) e envia `CANCEL {reason: "source_changed"}`. Teste na Task 10.
3. **App do receptor morto pelo sistema no meio da transferência** → ao abrir de novo e reconectar, retoma dos blocos salvos no `.state`, sem recomeçar do zero. Teste na Task 10 (novo `FileReceiver` sobre o mesmo diretório).
4. **Dois pedidos do mesmo arquivo ao mesmo tempo** (mesmo SHA-256, dois `OFFER`) → um único download; o segundo pedido espera e termina junto. Teste na Task 10.
5. **Nome de arquivo com caminho, caracteres especiais ou muito longo nos metadados** → o receptor usa só um nome saneado (sem `/`, `\`, `..`, até 120 caracteres) e nunca grava fora do cache. Teste na Task 9.

---

## Ajustes da revisão de 2026-10-22 (valem sobre o resto do plano)

**Ordem de execução revisada** (cada marco é apresentado ao dono do projeto antes de seguir):

| Marco | Tasks | Valida |
|---|---|---|
| M1 | Task 1 + **Task 0A** | Interface `LocalPlayer` e prova mínima do player no Windows |
| M2 | **Task 0B** + Tasks 7, 8 | Conexão WebRTC real entre dois aparelhos, com Android e Windows como anfitrião |
| M3 | Tasks 2–6 | Player completo nas duas plataformas, sessões de mídia, métricas |
| M4 | Tasks 9–10 | Protocolo de transferência e retomada |
| M5 | Tasks 11–13 | Laboratório, vários convidados, medições reais, resultados |

**Task 0A — Prova mínima do player no Windows.** Teste de integração (`integration_test/`, roda com `flutter test integration_test -d windows`, só local) sobre o candidato `just_audio` + `just_audio_media_kit`. Mede: reprodução de MP3 CBR, MP3 VBR, FLAC, M4A e WAV gerados com `ffmpeg`; posição reportada × tempo real; erro de seek em 10 posições; taxa de avanço da posição a 1,02×; preservação do tom a 1,02× (renderização para arquivo PCM e medição da frequência dominante de um seno de 1 kHz: tom preservado ≈ 1000 Hz, tom alterado ≈ 1020 Hz). Critérios: posição reportada dentro de ±150 ms do tempo real após 5 s; erro de seek p95 ≤ 100 ms (MP3 VBR registrado à parte); taxa a 1,02× entre 1,00 e 1,04; frequência a 1,02× entre 990 e 1010 Hz. Se algum critério falhar, registrar e testar a alternativa (`just_audio_windows`) antes de seguir.

**Task 0B — Prova mínima de conexão real.** Antes das Tasks 7 e 8 completas: tela mínima que abre um `RTCPeerConnection` com sinalização LAN e troca mensagens de texto e um bloco binário de 1 MiB pelo DataChannel. Executar: Windows anfitrião ↔ S25, S25 anfitrião ↔ Windows, S25 anfitrião ↔ A53, e S25 anfitrião com a tela desligada por 2 min.

**Anfitrião Android com a tela desligada.** O servidor LAN e as conexões WebRTC do anfitrião rodam dentro de um serviço em primeiro plano. Durante a reprodução, o serviço `mediaPlayback` do `audio_service` mantém o processo vivo. Sem música tocando (testes de transferência), o lab inicia um serviço em primeiro plano do tipo `dataSync` com notificação visível. As restrições de rede local e de segundo plano das versões do S25 e do A53 são verificadas no M2 e registradas.

**Rede local e segundo plano no Android (pesquisa de 2026-10-22, a confirmar no M2).**
- O S25 está recebendo a One UI 9 (Android 17). A versão do A53 ainda não foi confirmada; provavelmente Android 16.
- O Android 17 bloqueia acesso à rede local para apps com `targetSdk` **37 ou mais**, que precisam declarar e pedir `ACCESS_LOCAL_NETWORK` em tempo de execução. Apps com `targetSdk` abaixo de 37 recebem acesso implícito pela permissão `INTERNET`.
- O AppMusica usa o `targetSdk` padrão do Flutter 3.47.2, que é **36**. Na Fase 0, o acesso à LAN funciona sem pedir permissão. Ao subir para 37, será preciso declarar `ACCESS_LOCAL_NETWORK` e pedi-la antes de abrir o servidor ou conectar. Isso fica registrado como pendência da Fase 2.
- No Android 15 ou superior, serviços em primeiro plano do tipo `dataSync` têm limite de **6 h a cada 24 h**. Para o lab, isso basta. Na Jam real, o anfitrião normalmente está tocando música, então usa o serviço `mediaPlayback`, que não tem esse limite.
- Se o Doze corta a rede de um app com serviço em primeiro plano é verificado no teste "S25 anfitrião com tela desligada por 2 min" da Task 0B.

**Simulado × real.** Toda linha JSONL ganha o campo `"source": "simulated" | "device"`. Testes sobre `MemoryPeerLink` só produzem `simulated` e nunca entram nas tabelas de resultado reais; `resultados-bloco-a.md` separa as duas origens em seções diferentes.

**Retomada e integridade (reforço da Task 10).** O `.state` é gravado em arquivo temporário e renomeado (escrita atômica), nunca sobrescrito no lugar. Um arquivo só sai de `.part` para o nome final depois do SHA-256 conferir; `lookup` nunca devolve `.part`. Testes adicionais: `state corrompido ou truncado é descartado e a transferência recomeça`, `lookup não devolve arquivo parcial`, `processo encerrado entre gravar bloco e salvar state não marca bloco não gravado`.

**Segurança do servidor LAN (reforço da Task 7).** Conexão sem `hello` válido em 5 s é fechada; 5 códigos errados do mesmo endereço em 1 min bloqueiam esse endereço por 1 min; o servidor só repassa mensagens de sinalização, não serve arquivos nem diretórios; mensagens acima de 64 KiB são recusadas. Testes correspondentes na Task 7.

---

## Decisões e comparações

### Player: pacotes

| Opção | Android | Windows | Segundo plano / tela bloqueada | Controles de mídia | Android Auto |
|---|---|---|---|---|---|
| **`just_audio` + `audio_service` (Android)** ✅ | ExoPlayer/Media3 | — | Sim, serviço em primeiro plano | Notificação, tela bloqueada, fones | Sim (`MediaBrowserService`) |
| **`just_audio` + `just_audio_media_kit` + `smtc_windows` (Windows)** ✅ | — | libmpv | Não se aplica | SMTC (teclas de mídia, painel do Windows) via `smtc_windows` | — |
| `just_audio_windows` | — | Windows MediaPlayer | — | SMTC limitado | — |
| `audioplayers` | Sim | Sim | Precisa de pacote extra | Não integrado | Não |
| `media_kit` em tudo | libmpv | libmpv | Sem sessão de mídia no Android | Não no Android | Não |
| Media3 nativo (Kotlin) via canal | Melhor controle | — | Sim | Sim | Melhor suporte |

**Escolha:** um motor comum `just_audio` nas duas plataformas, com backend libmpv no Windows por ter seek preciso e velocidade sem mudar o tom (`scaletempo`). A integração com o sistema fica em adaptadores separados: `audio_service` no Android e `smtc_windows` no Windows. O `audio_service` **não** é usado no Windows.

**Saída de emergência:** se o Android Auto falhar no DHU com `audio_service`, o adaptador Android é trocado por Media3 nativo sem mudar a interface `LocalPlayer`. Se o `smtc_windows` não funcionar, o adaptador Windows vira um plugin C++ pequeno sobre `SystemMediaTransportControls`.

### Sinalização local

| Opção | Anfitrião Android? | Depende do PC? | Reaproveitado no Bloco B? |
|---|---|---|---|
| Servidor fixo no Windows | Não | **Sim** | Não |
| Copiar e colar SDP manualmente | Sim | Não | Não, e é lento para testar |
| **Servidor WebSocket embutido no anfitrião, qualquer plataforma** ✅ | **Sim** | **Não** | A interface sim; o servidor LAN é descartável ou vira um "modo offline" |

**Escolha:** o aparelho anfitrião (S25, A53 ou PC) abre um servidor WebSocket com `dart:io` na porta **47820** e mostra `IP:porta` + um código de sala de 8 caracteres. Os convidados digitam esses dados. Tudo acima disso fala com a interface `SignalingChannel`. No Bloco B, `FirebaseSignaling` implementa a mesma interface, e o `PeerLink` e o protocolo de transferência não mudam.

### Conexão sem Firebase nesta fase

1. O convidado abre um WebSocket para o anfitrião e envia `hello {roomCode}`; o anfitrião responde `welcome {peerId, hostPeerId}` ou recusa com `full`/`bad_code`.
2. O anfitrião cria um `RTCPeerConnection` por convidado, abre os canais `ctrl` e `data` e envia `offer`. O convidado responde `answer`. Os dois trocam `candidate` pela mesma via.
3. `iceServers: []`: só candidatos `host` da rede local. O tipo de par escolhido é lido em `getStats()` e registrado.

### Código definitivo × descartável

| Definitivo (Fases 1 e 2) | Descartável (só Fase 0) |
|---|---|
| `lib/player/**` | `lib/lab/**` (telas de teste) |
| `lib/jam/signaling/signaling_channel.dart`, `signal_message.dart` | `lib/jam/signaling/lan/**` (servidor/cliente LAN; pode virar modo offline depois) |
| `lib/jam/transport/**` | `lib/lab/test_files.dart` (gerador de arquivos de teste) |
| `lib/jam/transfer/**` | `docs/fase0/**` (roteiros e resultados) |
| `lib/metrics/**` (formato de log, saneamento) | |

---

## Estrutura de arquivos

```
lib/
  main.dart                          (modificar: inicialização e navegação para o lab)
  player/
    track.dart                       Track
    local_player.dart                interface LocalPlayer + PlayerStatus
    playback_queue.dart              lógica pura de fila
    just_audio_local_player.dart     motor comum sobre just_audio
    session/
      media_session.dart             interface MediaSession
      android_media_session.dart     audio_service (AudioHandler + árvore do Android Auto)
      windows_media_session.dart     smtc_windows
      media_session_factory.dart     escolhe a implementação por plataforma
  metrics/
    device_descriptor.dart           plataforma, modelo, versão do SO
    metric_event.dart                registro JSONL + validação de campos proibidos
    jsonl_logger.dart                gravação append-only por sessão
  jam/
    signaling/
      signal_message.dart
      signaling_channel.dart         interface + LoopbackSignalingHub (testes)
      lan/lan_signaling_server.dart
      lan/lan_signaling_client.dart
    transport/
      peer_link.dart                 interface PeerLink
      memory_peer_link.dart          par em memória com falhas injetáveis
      webrtc_peer_link.dart          flutter_webrtc
      peer_link_factory.dart         cria PeerLinks a partir de um SignalingChannel
    transfer/
      transfer_messages.dart         mensagens de controle + quadro binário + saneamento de nome
      chunk_bitmap.dart
      file_hasher.dart               SHA-256 em streaming
      jam_cache.dart                 cache, índice de hashes, teto, limpeza
      file_sender.dart
      file_receiver.dart
  lab/
    lab_home_page.dart
    player_lab_page.dart
    transfer_lab_page.dart
    test_files.dart
test/
  player/…  metrics/…  jam/signaling/…  jam/transport/…  jam/transfer/…
android/app/src/main/AndroidManifest.xml          (modificar)
android/app/src/main/res/xml/automotive_app_desc.xml
android/app/src/main/kotlin/io/github/ayablack/appmusica/MainActivity.kt  (modificar)
docs/fase0/roteiro-bloco-a.md
docs/fase0/resultados-bloco-a.md
```

---

### Task 1: Branch, dependências e interface `LocalPlayer`

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/player/track.dart`, `lib/player/local_player.dart`, `lib/player/playback_queue.dart`
- Test: `test/player/playback_queue_test.dart`

**Interfaces:**
- Produces:
  - `class Track { final String id; final String uri; final String title; final String? artist; final Duration? duration; String? sha256; }` — `uri` é `file://` ou `content://`; `id` é estável por sessão.
  - `enum PlayerStatus { idle, loading, ready, playing, paused, completed, error }`
  - `abstract class LocalPlayer { Future<void> setQueue(List<Track> tracks, {int startIndex = 0}); Future<void> play(); Future<void> pause(); Future<void> seek(Duration position); Future<void> next(); Future<void> previous(); Future<void> setSpeed(double speed); Stream<Duration> get positionStream; Stream<PlayerStatus> get statusStream; Stream<Track?> get currentTrackStream; Duration get position; PlayerStatus get status; Track? get currentTrack; List<Track> get queue; Future<void> dispose(); }`
  - `class PlaybackQueue { PlaybackQueue(List<Track> tracks, {int startIndex = 0}); Track? get current; int get index; bool moveNext(); bool movePrevious({required Duration position}); }` — `movePrevious` volta ao início da faixa atual se `position > 3 s`, senão vai para a anterior.

- [ ] **Step 1:** `git switch -c fase0/bloco-a` a partir da `main` (`48cf279`).
- [ ] **Step 2:** Adicionar dependências: `just_audio`, `just_audio_media_kit`, `media_kit_libs_windows_audio`, `audio_service`, `smtc_windows`, `flutter_webrtc`, `crypto`, `file_picker`, `device_info_plus`, `path_provider`, `uuid`. Rodar `flutter pub get`; esperado: sem conflitos.
- [ ] **Step 3: Testes que falham** em `playback_queue_test.dart`:
  - `moveNext avança e retorna false no fim` — fila de 3, `startIndex: 2` → `moveNext()` é `false`, `index == 2`.
  - `movePrevious volta ao início se passou de 3 s` — `movePrevious(position: Duration(seconds: 4))` → `false`, índice igual.
  - `movePrevious vai para a anterior até 3 s` — `index 1`, `position: 2 s` → `true`, `index == 0`.
  - `fila vazia tem current nulo`.
- [ ] **Step 4:** `flutter test test/player/playback_queue_test.dart` → FAIL (classe não existe).
- [ ] **Step 5:** Implementar `Track`, `PlayerStatus`, `LocalPlayer` (só a interface) e `PlaybackQueue`.
- [ ] **Step 6:** Rodar o teste → PASS. `flutter analyze` → sem problemas.
- [ ] **Step 7:** Commit `feat(player): interface LocalPlayer e fila de reprodução`.

### Task 2: Motor `JustAudioLocalPlayer`

**Files:**
- Create: `lib/player/just_audio_local_player.dart`
- Modify: `lib/main.dart` (chamar `JustAudioMediaKit.ensureInitialized(windows: true, android: false)` antes do `runApp`)
- Test: `test/player/just_audio_local_player_test.dart`

**Interfaces:**
- Consumes: `LocalPlayer`, `PlaybackQueue`, `Track` (Task 1).
- Produces: `class JustAudioLocalPlayer implements LocalPlayer { JustAudioLocalPlayer({AudioPlayer? audioPlayer}); }` — `audioPlayer` injetável para teste.

- [ ] **Step 1: Testes que falham** com um `AudioPlayer` falso (subclasse com `setAudioSource`, `play`, `pause`, `seek`, `setSpeed` registrando chamadas):
  - `setQueue carrega a faixa inicial` — chama `setAudioSource` com a `uri` da faixa `startIndex`.
  - `next carrega a próxima faixa e mantém o status tocando se estava tocando`.
  - `fim da faixa avança automaticamente` — emitir `ProcessingState.completed` no falso → `currentTrack` passa para a próxima; na última, status `completed`.
  - `setSpeed repassa o valor e limita a 0.5–2.0`.
  - `erro ao carregar arquivo vira status error e não lança exceção`.
- [ ] **Step 2:** `flutter test test/player/just_audio_local_player_test.dart` → FAIL.
- [ ] **Step 3:** Implementar mapeando `ProcessingState`/`playing` do `just_audio` para `PlayerStatus`; `positionStream` com intervalo de 50 ms.
- [ ] **Step 4:** Rodar o teste → PASS.
- [ ] **Step 5:** `flutter build windows --release` e `flutter build apk --debug` → sucesso (confirma que as libs nativas resolvem).
- [ ] **Step 6:** Commit `feat(player): motor JustAudioLocalPlayer (Android e Windows)`.

### Task 3: Sessão de mídia no Android (segundo plano, tela bloqueada, Android Auto)

**Files:**
- Create: `lib/player/session/media_session.dart`, `lib/player/session/android_media_session.dart`, `android/app/src/main/res/xml/automotive_app_desc.xml`
- Modify: `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/io/github/ayablack/appmusica/MainActivity.kt`
- Test: `test/player/android_media_session_test.dart`

**Interfaces:**
- Consumes: `LocalPlayer` (Task 1).
- Produces:
  - `abstract class MediaSession { Future<void> attach(LocalPlayer player); Future<void> detach(); }`
  - `class AndroidMediaSession implements MediaSession` — internamente um `AppMusicaAudioHandler extends BaseAudioHandler with QueueHandler` que repassa `play/pause/seek/skipToNext/skipToPrevious/playFromMediaId` ao `LocalPlayer` e publica `playbackState`, `mediaItem` e `queue`.
  - Árvore de navegação do Android Auto: raiz `"root"` com um filho navegável `"queue"` ("Fila"); os itens de `"queue"` são as faixas da fila, tocáveis por `mediaId == Track.id`.


- [ ] **Step 1: Testes que falham** com um `LocalPlayer` falso:
  - `handler.play repassa ao player`; idem `pause`, `seek(30 s)`, `skipToNext`, `skipToPrevious`.
  - `mudança de faixa no player atualiza mediaItem` (título, artista, duração).
  - `getChildren("root") retorna só "queue"`; `getChildren("queue") retorna as faixas da fila`.
  - `playFromMediaId toca a faixa certa`.
- [ ] **Step 2:** Rodar → FAIL.
- [ ] **Step 3:** Implementar. `MainActivity` passa a estender `AudioServiceActivity`. Manifest: permissões `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`, `INTERNET`; serviço `com.ryanheise.audioservice.AudioService` com `foregroundServiceType="mediaPlayback"`, `exported="true"` e `intent-filter` `android.media.browse.MediaBrowserService`; receptor `com.ryanheise.audioservice.MediaButtonReceiver`; `meta-data` `com.google.android.gms.car.application` → `@xml/automotive_app_desc` (`<uses name="media"/>`). Pedir `POST_NOTIFICATIONS` em tempo de execução no Android 13+.
- [ ] **Step 4:** Rodar → PASS. `flutter build apk --debug` → sucesso.
- [ ] **Step 5:** Commit `feat(player): sessão de mídia Android com Android Auto`.

### Task 4: Sessão de mídia no Windows (SMTC)

**Files:**
- Create: `lib/player/session/windows_media_session.dart`, `lib/player/session/media_session_factory.dart`
- Test: `test/player/windows_media_session_test.dart`

**Interfaces:**
- Consumes: `MediaSession`, `LocalPlayer`.
- Produces: `Future<MediaSession> createMediaSession()` em `media_session_factory.dart` (Android → `AndroidMediaSession`, Windows → `WindowsMediaSession`, outros → sessão que não faz nada).
- Produces: `class WindowsMediaSession implements MediaSession { WindowsMediaSession({SmtcGateway? gateway}); }` com `abstract class SmtcGateway { Stream<SmtcButton> get buttons; Future<void> updateMetadata({required String title, String? artist}); Future<void> updateStatus(PlayerStatus status); Future<void> updateTimeline({required Duration position, required Duration? duration}); Future<void> dispose(); }` — `SmtcGateway` é a única classe que importa `smtc_windows`; `enum SmtcButton { play, pause, next, previous }`.

- [ ] **Step 1: Testes que falham** com `SmtcGateway` falso: botão `play` → `player.play()`; `next` → `player.next()`; troca de faixa → `updateMetadata`; status do player → `updateStatus`; `timeline` atualizada no máximo 1 vez por segundo.
- [ ] **Step 2:** Rodar → FAIL.
- [ ] **Step 3:** Implementar `WindowsMediaSession` e a classe real `SmtcWindowsGateway`.
- [ ] **Step 4:** Rodar → PASS. `flutter build windows --release` → sucesso. Se o `smtc_windows` exigir toolchain Rust, adicionar `dtolnay/rust-toolchain@stable` ao job Windows do CI e registrar em `docs/fase0/resultados-bloco-a.md`.
- [ ] **Step 5:** Commit `feat(player): controles de mídia do Windows (SMTC)`.

### Task 5: Métricas JSONL

**Files:**
- Create: `lib/metrics/device_descriptor.dart`, `lib/metrics/metric_event.dart`, `lib/metrics/jsonl_logger.dart`
- Test: `test/metrics/metric_event_test.dart`, `test/metrics/jsonl_logger_test.dart`

**Interfaces:**
- Produces:
  - `class DeviceDescriptor { final String platform; final String model; final String osVersion; final String appVersion; final String gitSha; static Future<DeviceDescriptor> current(); Map<String, Object?> toJson(); }` — `gitSha` vem de `--dart-define=GIT_SHA=…` (padrão `"dev"`).
  - `class MetricEvent { MetricEvent({required String runId, required String testId, required String kind, required DeviceDescriptor device, Map<String, Object?> data = const {}}); Map<String, Object?> toJson(); }` — lança `ArgumentError` se `data` contiver chave proibida ou valor que pareça caminho/IP (regras abaixo).
  - `class JsonlLogger { JsonlLogger(Directory dir); Future<void> write(MetricEvent e); Future<File> currentFile(); }` — um arquivo por dia, `fase0-AAAA-MM-DD.jsonl`, uma linha por evento.

**Formato da linha (schema 1):**
```json
{"schema":1,"ts":"2026-10-22T14:03:11.204Z","runId":"7c1e…","testId":"T2","kind":"transfer_result",
 "device":{"platform":"android","model":"SM-S931B","osVersion":"16","appVersion":"0.0.1+1","gitSha":"48cf279"},
 "data":{"role":"receiver","peer":{"platform":"windows","model":"PC"},"candidatePair":"host/host",
  "file":{"sizeBytes":52428800,"sha256":"…"},"chunkSize":16384,"window":64,
  "durationMs":8123,"throughputMBps":6.15,"rss":{"startBytes":0,"peakBytes":0,"endBytes":0},
  "resumes":0,"bytesResent":0,"result":"ok","integrity":"match","errors":[]}}
```
- `kind`: `transfer_result`, `transfer_event` (queda, retomada, cancelamento), `player_result`, `player_event`.
- `result`: `ok` | `fail` | `cancelled`. `integrity`: `match` | `mismatch` | `not_checked`.
- `errors`: lista de `{"code": "...", "message": "..."}`, sem caminhos.
- Chaves proibidas em qualquer nível de `data`: `path`, `filePath`, `fileName`, `name`, `ip`, `address`, `email`, `user`. Valores proibidos: texto contendo `:\`, `/storage/`, `/data/`, `/Users/`, `C:/`, ou um IPv4/IPv6.
- O `sha256` em `file` é permitido: os arquivos de transferência são gerados pelo app (Task 12), não são do usuário.

- [ ] **Step 1: Testes que falham:**
  - `toJson tem schema 1, ts em UTC ISO-8601, runId, testId, kind e device`.
  - `chave proibida em data lança ArgumentError` — `{"file": {"path": "x"}}`.
  - `valor com caminho Windows lança` — `{"note": "C:\\Users\\x"}`; idem `"/storage/emulated/0/a.mp3"` e `"192.168.0.10"`.
  - `logger grava uma linha JSON válida por evento e anexa sem sobrescrever` (2 eventos → 2 linhas, cada uma decodifica).
- [ ] **Step 2:** Rodar → FAIL.
- [ ] **Step 3:** Implementar. `DeviceDescriptor.current()` usa `device_info_plus` (Android: `model`, `version.release`; Windows: `"PC"`, `displayVersion`).
- [ ] **Step 4:** Rodar → PASS.
- [ ] **Step 5:** Commit `feat(metrics): registro JSONL saneado`.

### Task 6: Tela de laboratório do player

**Files:**
- Create: `lib/lab/lab_home_page.dart`, `lib/lab/player_lab_page.dart`
- Modify: `lib/main.dart` (`TelaInicial` ganha botão "Laboratório")
- Test: `test/lab/player_lab_page_test.dart`

**Interfaces:**
- Consumes: `LocalPlayer`, `createMediaSession()`, `JsonlLogger`, `MetricEvent`.

- [ ] **Step 1: Teste de widget que falha:** com `LocalPlayer` falso, a tela mostra "Escolher músicas", e os botões tocar/pausar/próxima/anterior chamam o player; o campo de seek em segundos chama `seek`.
- [ ] **Step 2:** Rodar → FAIL.
- [ ] **Step 3:** Implementar. Escolha de arquivos com `file_picker` (múltiplos, `FileType.audio`). Botão **"Medir preparo (P7)"**: repete 20× `seek(0)` + `play()` e mede até `status == playing`; grava `player_result` com `{"testId":"P7","format":"mp3_cbr","samplesMs":[…],"p50Ms":…,"p95Ms":…}` (formato escolhido num seletor: `mp3_cbr`, `mp3_vbr`, `flac`, `m4a`). Botão **"Medir seek (P4)"**: 10 seeks para posições aleatórias e grava `|posiçãoReportada − alvo|` após 500 ms. Botão **"Velocidade 1,02×" (P6)**.
- [ ] **Step 4:** Rodar → PASS. `flutter analyze` → sem problemas.
- [ ] **Step 5:** Verificação manual rápida no Windows: `flutter run -d windows`, tocar um arquivo, pausar, avançar, usar as teclas de mídia.
- [ ] **Step 6:** Commit `feat(lab): tela de testes do player`.

### Task 7: Sinalização (interface, loopback e LAN)

**Files:**
- Create: `lib/jam/signaling/signal_message.dart`, `lib/jam/signaling/signaling_channel.dart`, `lib/jam/signaling/lan/lan_signaling_server.dart`, `lib/jam/signaling/lan/lan_signaling_client.dart`
- Test: `test/jam/signaling/signal_message_test.dart`, `test/jam/signaling/lan_signaling_test.dart`

**Interfaces:**
- Produces:
  - `enum SignalType { hello, welcome, reject, peerJoined, peerLeft, offer, answer, candidate, bye }`
  - `class SignalMessage { final SignalType type; final String from; final String? to; final Map<String, Object?> payload; Map<String, Object?> toJson(); factory SignalMessage.fromJson(Map<String, Object?> j); }`
  - `abstract class SignalingChannel { String get selfId; String get hostId; Stream<SignalMessage> get messages; Future<void> send(SignalMessage m); Future<void> close(); }`
  - `class LoopbackSignalingHub { SignalingChannel join(String peerId); }` — para testes.
  - `class LanSignalingServer { static Future<LanSignalingServer> start({int port = 47820, int maxParticipants = 5}); String get roomCode; int get port; SignalingChannel get hostChannel; Future<void> stop(); }` — o servidor também é o canal do anfitrião; repassa mensagens pelo campo `to`; código de sala de 8 caracteres do alfabeto `23456789ABCDEFGHJKMNPQRSTUVWXYZ` com `Random.secure()`.
  - `class LanSignalingClient { static Future<SignalingChannel> connect({required String host, required int port, required String roomCode}); }`

- [ ] **Step 1: Testes que falham:**
  - `SignalMessage ida e volta JSON preserva todos os campos`; tipo desconhecido → `FormatException`.
  - LAN em `127.0.0.1`: `convidado com código certo recebe welcome e o anfitrião recebe peerJoined`.
  - `código errado recebe reject bad_code e a conexão fecha`.
  - `sexto participante recebe reject full` (anfitrião + 4 convidados aceitos, o 5º convidado é recusado).
  - `mensagem com to chega só ao destinatário`.
  - `convidado que cai gera peerLeft no anfitrião`.
  - `roomCode tem 8 caracteres do alfabeto permitido` (1000 gerações).
- [ ] **Step 2:** Rodar → FAIL.
- [ ] **Step 3:** Implementar com `HttpServer.bind(InternetAddress.anyIPv4, port)` + `WebSocketTransformer`. Servidor anuncia os IPv4 locais via `NetworkInterface.list()` para a tela mostrar (só na tela, nunca no log).
- [ ] **Step 4:** Rodar → PASS.
- [ ] **Step 5:** Commit `feat(jam): sinalização com interface trocável e servidor LAN`.

### Task 8: `PeerLink` (memória e WebRTC)

**Files:**
- Create: `lib/jam/transport/peer_link.dart`, `lib/jam/transport/memory_peer_link.dart`, `lib/jam/transport/webrtc_peer_link.dart`, `lib/jam/transport/peer_link_factory.dart`
- Test: `test/jam/transport/memory_peer_link_test.dart`, `test/jam/transport/peer_link_factory_test.dart`

**Interfaces:**
- Consumes: `SignalingChannel`, `SignalMessage` (Task 7).
- Produces:
  - `enum PeerLinkState { connecting, connected, disconnected, closed }`
  - `abstract class PeerLink { String get remoteId; Stream<PeerLinkState> get stateStream; PeerLinkState get state; Stream<Map<String, Object?>> get ctrlMessages; Stream<Uint8List> get dataMessages; Future<void> sendCtrl(Map<String, Object?> m); Future<void> sendData(Uint8List bytes); int get dataBufferedAmount; Stream<void> get dataBufferedLow; Future<String?> selectedCandidatePairType(); Future<void> close(); }` — `selectedCandidatePairType` devolve `"host/host"`, `"srflx/host"`, `"relay/…"` etc.
  - `class MemoryPeerLink implements PeerLink { static (MemoryPeerLink, MemoryPeerLink) pair({int? dropAfterDataMessages, double corruptProbability = 0}); void simulateDisconnect(); void simulateReconnect(); }`
  - `class PeerLinkFactory { PeerLinkFactory(SignalingChannel signaling, {List<Map<String, Object?>> iceServers = const []}); Stream<PeerLink> get links; Future<void> connectTo(String remoteId); Future<void> dispose(); }` — anfitrião chama `connectTo` para cada `peerJoined`; convidado recebe o link via `links` ao chegar a `offer`.
  - `WebRtcPeerLink`: canais `ctrl` (`ordered: true`, JSON em texto) e `data` (`ordered: true`, binário); `bufferedAmountLowThreshold = 256 * 1024`.

- [ ] **Step 1: Testes que falham:**
  - `par em memória entrega ctrl e data na ordem`.
  - `simulateDisconnect muda os dois lados para disconnected e descarta envios`; `simulateReconnect volta para connected`.
  - `dropAfterDataMessages: 10 desconecta após o 10º bloco`.
  - `PeerLinkFactory sobre LoopbackSignalingHub com um PeerLink de teste injetado troca offer/answer/candidate na ordem` (a fábrica recebe um construtor de link injetável; o WebRTC real não roda no `flutter test`).
- [ ] **Step 2:** Rodar → FAIL.
- [ ] **Step 3:** Implementar `MemoryPeerLink`, `PeerLinkFactory` e `WebRtcPeerLink`.
- [ ] **Step 4:** Rodar → PASS. Builds Android e Windows → sucesso.
- [ ] **Step 5:** Commit `feat(jam): PeerLink com WebRTC DataChannel e implementação em memória`.

### Task 9: Mensagens e quadros da transferência

**Files:**
- Create: `lib/jam/transfer/transfer_messages.dart`, `lib/jam/transfer/chunk_bitmap.dart`, `lib/jam/transfer/file_hasher.dart`
- Test: `test/jam/transfer/transfer_messages_test.dart`, `test/jam/transfer/chunk_bitmap_test.dart`, `test/jam/transfer/file_hasher_test.dart`

**Interfaces:**
- Produces:
  - Mensagens de controle (`{"v":1,"t":<tipo>,…}`), todas com `transferId` (u32):
    - `Offer {transferId, sha256, size, chunkSize, totalChunks, name, mime}`
    - `Have {transferId}` · `Accept {transferId, missing: List<List<int>>}` (faixas `[início, fim]` inclusivas)
    - `Credit {transferId, n}` · `Done {transferId}` · `Fail {transferId, reason}` · `Cancel {transferId, reason}`
    - `reason` ∈ `hash`, `disk`, `source_changed`, `timeout`, `user`, `protocol`.
  - `sealed class TransferMessage { Map<String, Object?> toJson(); static TransferMessage fromJson(Map<String, Object?> j); }`
  - `Uint8List encodeChunkFrame(int transferId, int chunkIndex, Uint8List payload)` e `({int transferId, int chunkIndex, Uint8List payload}) decodeChunkFrame(Uint8List frame)` — cabeçalho de 8 bytes, big-endian.
  - `String sanitizeFileName(String raw)` — remove diretórios (`/`, `\`), `..`, caracteres de controle e `<>:"|?*`; corta em 120 caracteres; vazio vira `"arquivo"`.
  - `class ChunkBitmap { ChunkBitmap(int totalChunks); void mark(int i); bool has(int i); int get count; bool get isComplete; List<List<int>> missingRanges(); String toBase64(); factory ChunkBitmap.fromBase64(String s, int totalChunks); }`
  - `Future<String> sha256OfFile(File f)` — leitura em blocos de 1 MiB, hex minúsculo.

- [ ] **Step 1: Testes que falham:**
  - Ida e volta JSON de cada mensagem; `"v": 2` → `FormatException`; tipo desconhecido → `FormatException`.
  - `quadro com transferId 4294967295 e chunkIndex 0 ida e volta`; quadro com menos de 8 bytes → `FormatException`.
  - `sanitizeFileName("../../etc/passwd") == "passwd"`; `"C:\\Users\\x\\música.mp3"` → `"música.mp3"`; nome de 300 caracteres → 120; `""` → `"arquivo"` (Review Focus 5).
  - `bitmap: missingRanges de [0,1,5] em 8 blocos == [[2,4],[6,7]]`; ida e volta base64.
  - `sha256OfFile de "abc" == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"`; arquivo de 5 MiB igual ao hash calculado em memória no teste.
- [ ] **Step 2:** Rodar → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar → PASS.
- [ ] **Step 5:** Commit `feat(transfer): mensagens, quadros binários, bitmap e SHA-256`.

### Task 10: Cache, `FileSender` e `FileReceiver`

**Files:**
- Create: `lib/jam/transfer/jam_cache.dart`, `lib/jam/transfer/file_sender.dart`, `lib/jam/transfer/file_receiver.dart`
- Test: `test/jam/transfer/jam_cache_test.dart`, `test/jam/transfer/file_transfer_test.dart`

**Interfaces:**
- Consumes: `PeerLink`, `MemoryPeerLink` (Task 8); mensagens, quadros, `ChunkBitmap`, `sha256OfFile`, `sanitizeFileName` (Task 9).
- Produces:
  - `class JamCache { JamCache(Directory root, {int maxBytes = 1024 * 1024 * 1024}); Future<File?> lookup(String sha256); void registerLibraryFile(String sha256, File f); File partFile(String sha256); File stateFile(String sha256); Future<File> promote(String sha256); Future<void> enforceLimit(); Future<void> clearAll(); Future<void> purgeStalePartials({Duration maxAge = const Duration(minutes: 10)}); }`
  - `class TransferProgress { final int transferId; final int sentOrReceivedChunks; final int totalChunks; final int bytes; final Duration elapsed; }`
  - `class FileSender { FileSender(PeerLink link, {int chunkSize = 16384, int window = 64, int highWater = 1 << 20}); Future<SendResult> send(File file, {required String sha256, required String mime, required String displayName}); Future<void> cancel(int transferId); Stream<TransferProgress> get progress; }`
  - `class FileReceiver { FileReceiver(PeerLink link, JamCache cache, {Duration stallTimeout = const Duration(seconds: 30)}); Stream<ReceivedFile> get completed; Stream<TransferProgress> get progress; Stream<TransferFailure> get failures; Future<void> cancel(int transferId); }`
  - `class SendResult { final String outcome; /* ok | have | fail | cancelled */ final int bytesSent; final int bytesResent; final int resumes; final Duration elapsed; final String? reason; }`
  - `class ReceivedFile { final String sha256; final File file; final int resumes; }` · `class TransferFailure { final int transferId; final String reason; }`

**Comportamento que os testes fixam:**
- Remetente: `Offer` → espera `Have`/`Accept`; envia só blocos de `missing`; nunca tem mais que `window` blocos sem `Credit`; pausa enquanto `dataBufferedAmount > highWater` e retoma em `dataBufferedLow`. Lê cada bloco com `RandomAccessFile.setPosition` + `read`.
- Antes de cada lote de blocos, confere se tamanho e data de modificação da origem não mudaram; se mudaram → `Cancel {reason: source_changed}`.
- Receptor: grava no offset certo do `.part`; salva o `.state` (bitmap base64 + metadados) a cada 64 blocos e ao desconectar; concede `Credit` depois de gravar. Ao completar: SHA-256 em streaming; igual → `promote` + `Done`; diferente → apaga e envia `Fail {hash}`; o remetente reenvia do zero **uma** vez, a segunda falha encerra com `fail`.
- Erro de escrita (`FileSystemException`) → `Fail {disk}`, apaga `.part`/`.state`.
- Link `disconnected` → suspende, mantém `.part`. Reconexão → remetente reenvia `Offer`; receptor responde `Accept` com o que falta do `.state`.
- Sem bloco por `stallTimeout` com link conectado → receptor reenvia `Accept` com o que falta.
- `Cancel` de qualquer lado → os dois param; receptor apaga `.part` e `.state`.
- Dois `Offer` com o mesmo `sha256` → o segundo aguarda o primeiro e é resolvido com o mesmo arquivo, sem segundo download.

- [ ] **Step 1: Testes que falham** em `jam_cache_test.dart`:
  - `lookup encontra arquivo da biblioteca registrado e arquivo promovido do cache`.
  - `enforceLimit apaga os mais antigos até ficar abaixo de maxBytes` (teto de 10 KB no teste).
  - `purgeStalePartials apaga .part/.state com mais de 10 min e mantém os recentes`.
  - `clearAll esvazia o cache e não toca arquivos da biblioteca`.
- [ ] **Step 2: Testes que falham** em `file_transfer_test.dart` (sobre `MemoryPeerLink`, arquivos temporários de 3 MiB):
  - `transfere íntegro com bloco de 16 KiB` e `com bloco de 64 KiB` (SHA-256 confere).
  - `nunca há mais que window blocos sem crédito` (contador no link falso).
  - `respeita backpressure`: com `dataBufferedAmount` forçado acima de 1 MiB, nenhum envio até `dataBufferedLow`.
  - `retoma após queda no meio` (`dropAfterDataMessages: 50`, reconecta) → íntegro, `resumes == 1`, `bytesResent` < 10 % do tamanho.
  - `retoma com novo FileReceiver no mesmo cache` (Review Focus 3).
  - `bloco corrompido gera Fail hash e um único reenvio completo` (`corruptProbability` em um bloco).
  - `arquivo já presente responde Have e envia zero bytes`.
  - `Cancel do remetente e do receptor param os dois lados e apagam o parcial`.
  - `disco cheio gera Fail disk e apaga o parcial` (Review Focus 1, `JamCache` com arquivo falso que lança `FileSystemException`).
  - `origem alterada durante o envio gera Cancel source_changed` (Review Focus 2).
  - `dois Offer do mesmo sha256 geram um único download` (Review Focus 4).
  - `sem blocos por stallTimeout o receptor reenvia Accept` (`stallTimeout` de 200 ms no teste).
  - `pico de memória não cresce com o tamanho do arquivo`: transferir 3 MiB e 30 MiB e comparar `ProcessInfo.maxRss`; diferença < 20 MiB.
- [ ] **Step 3:** Rodar → FAIL.
- [ ] **Step 4:** Implementar `JamCache`, `FileSender` e `FileReceiver`.
- [ ] **Step 5:** Rodar → PASS. Rodar a suíte inteira (`flutter test`) → PASS.
- [ ] **Step 6:** Commit `feat(transfer): envio e recepção com créditos, retomada e verificação SHA-256`.

### Task 11: Tela de laboratório da transferência

**Files:**
- Create: `lib/lab/transfer_lab_page.dart`, `lib/lab/test_files.dart`
- Modify: `lib/lab/lab_home_page.dart`
- Test: `test/lab/test_files_test.dart`

**Interfaces:**
- Consumes: `LanSignalingServer`, `LanSignalingClient`, `PeerLinkFactory`, `FileSender`, `FileReceiver`, `JamCache`, `JsonlLogger`, `MetricEvent`, `DeviceDescriptor`.
- Produces: `Future<File> generateTestFile(Directory dir, {required int sizeBytes, required int seed})` — bytes pseudoaleatórios determinísticos (xorshift32 com `seed`), escrita em blocos de 1 MiB; mesmo `seed` e tamanho → mesmo SHA-256 em qualquer aparelho.

- [ ] **Step 1: Teste que falha:** `generateTestFile 10 MB com seed 1 gera sempre o mesmo SHA-256` (duas gerações, hashes iguais; `seed 2` → hash diferente; tamanho exato `10 * 1024 * 1024`).
- [ ] **Step 2:** Rodar → FAIL; implementar; rodar → PASS.
- [ ] **Step 3:** Implementar a tela:
  - **"Ser anfitrião"**: inicia `LanSignalingServer`, mostra IPs locais, porta e código; lista convidados conectados com o tipo de par de candidatos.
  - **"Entrar"**: campos IP, porta e código.
  - Anfitrião escolhe teste (`T1`…`T7`), tamanho (10 MB / 50 MB), bloco (16 / 64 KiB) e destino (um convidado ou **todos ao mesmo tempo**, para T7). O arquivo de teste é gerado no aparelho com `seed` fixo.
  - Durante o envio: MB/s ao vivo, blocos, memória (`ProcessInfo.currentRss`) amostrada a cada 500 ms (pico registrado).
  - Botões **"Derrubar conexão"** (fecha o link para T4) e **"Cancelar"**.
  - Cada lado grava `transfer_result` e cada queda, retomada ou cancelamento como `transfer_event`, com o mesmo `runId` (o `runId` vai na mensagem `Offer` como campo extra `runId`).
  - **"Exportar logs"**: `FilePicker.saveFile` com o JSONL do dia.
  - Limpa o cache da Jam ao sair da tela e na inicialização (`purgeStalePartials` + `clearAll`).
- [ ] **Step 4:** Android: confirmar `INTERNET` no manifesto principal (Task 3). No primeiro uso no S25 e no A53, verificar se o sistema pede permissão de **rede local**; se pedir, adicionar a permissão exigida e o pedido em tempo de execução, e registrar a versão do Android em que isso ocorreu.
- [ ] **Step 5:** Verificação local: duas instâncias no PC (`flutter run -d windows` duas vezes), anfitrião em `127.0.0.1`, enviar 10 MB → íntegro e linhas JSONL gravadas nos dois lados.
- [ ] **Step 6:** Commit `feat(lab): tela de testes de transferência na rede local`.

### Task 12: CI, documentação e roteiros de teste

**Files:**
- Modify: `.github/workflows/ci.yml` (passar `--dart-define=GIT_SHA=${{ github.sha }}` nos builds; Rust no job Windows só se a Task 4 exigiu), `README.md` (seção "Laboratório da Fase 0")
- Create: `docs/fase0/roteiro-bloco-a.md`, `docs/fase0/resultados-bloco-a.md`

- [ ] **Step 1:** Escrever `roteiro-bloco-a.md` com, para cada teste, pré-condições, passos e o que registrar:
  - **P1–P7** (player) e **T1–T7** (transferência), mais **T8: tela do S25 bloqueada durante envio de 50 MB** e **T9: Wi-Fi do convidado desligado por 30 s no meio de 50 MB** (comportamento quando a conexão cai).
  - Matriz real: S25 ↔ Windows (os dois sentidos), A53 ↔ Windows (os dois sentidos), S25 → A53 + PC ao mesmo tempo (T7), com 10 MB e 50 MB.
  - Cada combinação roda **3 vezes**; o resultado usa a mediana.
  - Seção **Android Auto com DHU** (abaixo).
- [ ] **Step 2:** Escrever `resultados-bloco-a.md` com as tabelas vazias (colunas: teste, remetente, receptor, tamanho, bloco, MB/s mediana, pico de memória, integridade, retomadas, observações) e a seção "Problemas encontrados".
- [ ] **Step 3:** Atualizar CI e README. Push da branch → CI verde nos 3 jobs.
- [ ] **Step 4:** Commit `docs(fase0): roteiro e modelo de resultados do Bloco A`.

**Conteúdo da seção DHU no roteiro:**
1. No PC: Android Studio → SDK Manager → SDK Tools → marcar **Android Auto Desktop Head Unit Emulator**. O executável fica em `<Android SDK>/extras/google/auto/desktop-head-unit.exe`.
2. No celular: Configurações → Android Auto → tocar 10 vezes em **Versão** para ativar o modo desenvolvedor → menu ⋮ → **Configurações do desenvolvedor** → ativar **Fontes desconhecidas** (sem isso, um APK instalado fora da Play Store não aparece no Android Auto) → menu ⋮ → **Iniciar servidor da unidade principal**.
3. Cabo USB com depuração USB ativa; no PC: `adb forward tcp:5277 tcp:5277` (o `adb` fica em `<Android SDK>/platform-tools/`).
4. Rodar `desktop-head-unit.exe`. O AppMusica deve aparecer na lista de apps de mídia.
5. Testes no DHU: abrir o app, navegar em "Fila", tocar uma faixa, play/pause/próxima/anterior, bloquear o celular e repetir.

**Só um carro real valida:** áudio pelo Bluetooth ou USB do carro, botões do volante, Android Auto sem fio, comportamento ao ligar/desligar o carro com música tocando, troca de chamada telefônica durante a música e diferenças de interface da central multimídia de cada fabricante.

### Task 13: Execução dos testes reais e decisão

**Files:**
- Modify: `docs/fase0/resultados-bloco-a.md`
- Create: `docs/fase0/evidencias/bloco-a/` (JSONL exportados, capturas)

- [ ] **Step 1:** Instalar o APK da branch no S25 e no A53 e o build Windows no PC.
- [ ] **Step 2:** Rodar P1–P7 seguindo o roteiro (P3 no DHU).
- [ ] **Step 3:** Rodar T1–T9 na matriz real, exportar os JSONL de cada aparelho para `docs/fase0/evidencias/bloco-a/`.
- [ ] **Step 4:** Antes de versionar os JSONL, rodar a varredura: nenhum caminho, IP ou e-mail (`grep -E ':\\\\|/storage/|/Users/|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|@'` sem resultados).
- [ ] **Step 5:** Preencher as tabelas, listar problemas e limitações, e escrever a conclusão do Bloco A: player e transferência aprovados, aprovados com ressalvas ou reprovados, com os números.
- [ ] **Step 6:** Commit `docs(fase0): resultados do Bloco A`. Abrir PR `fase0/bloco-a` → `main`. Merge só após sua aprovação.

---

## Critérios de aprovação do Bloco A

| Área | Aprovado se |
|---|---|
| Player Android | P1: 15 min em segundo plano com tela bloqueada sem corte; P2: controles da tela bloqueada e do fone funcionam; P3: app aparece no DHU, "Fila" navegável, play/pause/próxima funcionam |
| Player Windows | P4: erro de seek p95 ≤ 100 ms em MP3 CBR, FLAC e M4A (MP3 VBR é medido e registrado); P5: teclas de mídia e painel do Windows controlam o app |
| Ambos | P6: 1,02× sem mudança de tom audível; P7: tempo de preparo medido nos 4 formatos |
| Transferência | 10 e 50 MB íntegros (SHA-256) em todas as direções da matriz; retomada após queda sem recomeçar do zero; pico de memória não cresce com o tamanho do arquivo (diferença 10 MB × 50 MB < 20 MiB); T7 completa nos dois convidados |
| Isolamento | Nenhuma falha de transferência interrompeu música tocando no mesmo aparelho |
| Privacidade | Varredura dos JSONL sem caminhos, IPs ou e-mails |

---

## Riscos técnicos

| # | Risco | Impacto | Mitigação |
|---|---|---|---|
| 1 | Android 17 (SDK 37) pode exigir permissão de **acesso à rede local** para conexões na LAN | Anfitrião ou convidado Android não conecta | Task 11, Step 4: verificar no S25/A53, adicionar permissão e pedido em tempo de execução |
| 2 | **Firewall do Windows** bloqueia o servidor LAN ou o WebRTC na primeira execução | Celular não alcança o PC | Roteiro instrui a permitir em "Redes privadas"; registrar se ocorrer |
| 3 | `smtc_windows` depende de Rust/binários pré-compilados | Build Windows quebra no CI | Rust no CI se necessário; plano B: plugin C++ próprio sobre SMTC |
| 4 | `flutter_webrtc` com `bufferedAmount`/`onBufferedAmountLow` incompleto em alguma plataforma | Backpressure da camada 1 falha | Janela de créditos (camada 2) limita memória sozinha; registrar como problema |
| 5 | Samsung (One UI) mata apps em segundo plano | P1 ou T8 falham com tela bloqueada | Roteiro inclui tirar o app da otimização de bateria; registrar o comportamento padrão também |
| 6 | Android Auto ignora app instalado fora da loja | P3 falha | "Fontes desconhecidas" no modo desenvolvedor do Android Auto |
| 7 | `file_picker` no Android copia o arquivo escolhido para o cache | Arquivos grandes demoram e ocupam espaço | Aceitável no lab; na Fase 1 a biblioteca usa MediaStore |
| 8 | Wi-Fi com **isolamento de clientes** (redes de visitante, alguns roteadores) | Aparelhos não se enxergam | Roteiro pede rede doméstica comum; registrar se ocorrer |
| 9 | libmpv sem dispositivo de áudio no runner de CI | Testes de integração do player não rodam no CI | Testes do player no CI usam `AudioPlayer` falso; reprodução real só nos testes manuais |

## Tempo estimado

| Tasks | O quê | Estimativa |
|---|---|---|
| 1–6 | Player e métricas | 2–3 sessões de trabalho |
| 7–11 | Sinalização, PeerLink, transferência e lab | 3–4 sessões |
| 12 | CI e roteiros | 1 sessão curta |
| 13 | Testes reais com os 3 aparelhos | 2–3 horas suas, com o roteiro em mãos |
