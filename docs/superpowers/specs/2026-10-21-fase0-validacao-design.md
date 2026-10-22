# Fase 0 — Validação técnica do AppMusica

Data: 2026-10-21
Status: rascunho para aprovação

## 1. Intenção

O AppMusica é um player de música local (Android e Windows, Flutter), sem propaganda e sem assinatura, com Android Auto e uma "Jam" entre amigos. A arquitetura candidata da Jam é a **abordagem B**: o arquivo vai para os convidados por WebRTC DataChannel, cada aparelho toca localmente e um protocolo de estados mantém todos sincronizados; o Firebase Realtime Database cuida só de salas e sinalização.

A Fase 0 existe para descobrir, **antes** de construir as Fases 1 e 2, se algum risco técnico obriga a mudar essa arquitetura. O produto da Fase 0 é **evidência e uma decisão**, não um app.

## 2. Objetivos, não-objetivos e anti-objetivos

**Objetivos**
- Protótipo mínimo que compila e roda em Android e Windows.
- Provar o player local nas duas plataformas atrás de uma interface comum.
- Provar transferência binária confiável por DataChannel entre Android e Windows.
- Medir sincronização real (software e áudio audível) em cenários de ciclo de vida.
- Provar conectividade: mesma rede, redes diferentes, e TURN quando necessário.
- Definir e testar regras de segurança do Firebase e limites da sala.
- Entregar tabela de resultados, lista de problemas e decisão fundamentada.

**Não-objetivos**
- Interface final, biblioteca completa, playlists, favoritos, sugestões de faixas.
- Fluxo completo da Jam (UX de convite, fila colaborativa, troca de anfitrião).
- Publicação em loja.

**Anti-objetivos (falha mesmo que "funcione")**
- A Jam conseguir interromper ou travar uma reprodução local independente.
- Qualquer segredo (chave TURN, chave de API privilegiada) embutido no app.
- Tratar metas de sincronização (20–80 ms) como garantia em vez de medir.
- Carregar o arquivo inteiro em memória para enviar ou receber.
- Tratar sala privada ou cache temporário como autorização para compartilhar música protegida por direito autoral.

## 3. Restrições

- Flutter 3.47.2 / Dart 3.13.2, Android SDK 37, Visual Studio 2026 (verificado na máquina em 2026-10-21).
- Alvos: Android (celular físico) e Windows 11 x64.
- `audio_service` **não** é tratado como suporte equivalente no Windows.
- Infra de produção preferida: STUN/TURN do Cloudflare (Realtime TURN), com credenciais temporárias emitidas por backend (Cloudflare Worker).
- Limite da sala: **5 participantes no total** (anfitrião + 4).
- Aparelhos de teste: Samsung Galaxy S25 e Samsung Galaxy A53 (versões do Android a confirmar) e o PC Windows de desenvolvimento. Android Auto em carro: **pendente**; até confirmar, P3 usa o Desktop Head Unit (DHU).
- Com 2 celulares + 1 PC, o teste multi-convidado fica limitado a **anfitrião + 2 convidados** (ver T7). O cenário de 4 convidados simultâneos fica como limitação conhecida, com estimativa extrapolada dos dados de T7.
- Contas Firebase e Cloudflare são criadas pelo dono do projeto, seguindo passo a passo fornecido na etapa correspondente.
- Nenhuma chave secreta, token ou credencial entra no repositório.

## 4. Estrutura do protótipo

Um único app Flutter (`appmusica`) com módulos isolados. O módulo `jam` depende do `player`; o `player` nunca depende do `jam`.

```
lib/
  player/        interface LocalPlayer + implementações por plataforma
  jam/
    signaling/   salas e troca de SDP/ICE via Firebase RTDB
    transport/   PeerLink: conexão WebRTC + canais "ctrl" e "data"
    transfer/    protocolo de transferência de arquivos
    sync/        relógio sincronizado + protocolo de estados
  lab/           telas de teste e coleta de métricas (só Fase 0)
backend/
  turn-worker/   Cloudflare Worker que emite credenciais TURN
firebase/
  database.rules.json
tools/
  gerar_audio_teste/   gera faixa de cliques para medição acústica
  analisar_gravacao/   mede defasagem entre cliques numa gravação
```

### 4.1 Player (`LocalPlayer`)

Interface comum:
- `setQueue(List<Track>)`, `play()`, `pause()`, `seek(Duration)`, `next()`, `previous()`, `setSpeed(double)`
- streams: `position`, `state` (tocando/pausado/carregando/parado), `currentTrack`
- `Track`: caminho do arquivo, título, artista, duração, `sha256` (opcional, calculado sob demanda)

Implementações:
- **Android:** `just_audio` + `audio_service` (serviço em primeiro plano tipo `mediaPlayback`, notificação, tela bloqueada, `MediaBrowserService` para Android Auto com uma árvore mínima: "Fila").
- **Windows:** `just_audio` com backend para Windows + pacote de controles de mídia do sistema (SMTC). Ponto de escolha do construtor, com critério: o backend precisa passar nos testes de seek preciso, `setSpeed` sem mudar o tom e `position` com resolução ≤ 50 ms. Candidatos a testar primeiro: `just_audio_media_kit` (player) e `smtc_windows` (controles). Se falharem, registrar como problema e testar alternativa.

### 4.2 Conexão (`PeerLink`)

- `flutter_webrtc`, topologia estrela (anfitrião ↔ cada convidado).
- Dois DataChannels confiáveis e ordenados: `ctrl` (JSON, sync e controle da transferência) e `data` (binário, blocos de arquivo). Separados para que mensagens de sync não fiquem atrás de blocos de arquivo.
- Registrar via `getStats()` o tipo do par de candidatos selecionado (`host`, `srflx`, `relay`) em cada teste.

### 4.3 Sinalização e salas (Firebase RTDB)

- Autenticação anônima do Firebase.
- Estrutura:
  ```
  rooms/{code}/
    hostUid, createdAt, expiresAt
    slots/{s1..s4}: uid do convidado
    signal/{toUid}/{fromUid}/{pushId}: {type: offer|answer|candidate, payload}
    presence/{uid}: true (com onDisconnect remove)
  ```
- Mensagens de sincronização e transferência **não** passam pelo Firebase.

### 4.4 TURN (Cloudflare)

- Worker `POST /turn-credentials`: verifica o ID token do Firebase do chamador (JWT, chaves públicas do Google), chama a API do Cloudflare para gerar ICE servers com TTL curto (ex.: 2 h) e devolve `iceServers`. A chave da API do Cloudflare fica só como segredo do Worker.
- O app sempre inclui STUN; TURN entra nas `iceServers` vindas do Worker.
- Para forçar teste de relay: `iceTransportPolicy: relay`.

## 5. Protocolo de transferência

**Metadados** (canal `ctrl`, do remetente):
`OFFER {transferId, sha256, size, chunkSize, totalChunks, name, mime}`

**Receptor responde:**
- `HAVE {transferId}` se já possui arquivo com o mesmo SHA-256 (biblioteca ou cache) → nada é enviado.
- `ACCEPT {transferId, missing: [faixas de índices]}` → na primeira vez, tudo; após reconexão, só o que falta.

**Blocos** (canal `data`, binário): cabeçalho de 8 bytes `[transferId u32][chunkIndex u32]` + payload.
- Tamanho de bloco: **16 KiB** como padrão (seguro entre implementações); testar também 64 KiB e registrar a diferença.

**Backpressure em duas camadas:**
1. **Buffer do canal:** remetente pausa quando `bufferedAmount` > 1 MiB e retoma em `onBufferedAmountLow` (limiar 256 KiB). Se o `flutter_webrtc` não expuser isso de forma confiável em alguma plataforma, registrar como problema e depender só da camada 2.
2. **Janela por créditos:** receptor concede créditos (`CREDIT {transferId, n}`) após gravar blocos em disco; remetente nunca tem mais que a janela (ex.: 64 blocos) sem crédito. Isso limita memória dos dois lados, independente do plugin.

**Disco, não memória:**
- Remetente lê o arquivo por `RandomAccessFile` no offset do bloco.
- Receptor grava em `cache/jam/{sha256}.part` no offset certo e mantém um bitmap de blocos recebidos persistido em `{sha256}.state` (a cada N blocos).

**Integridade:** ao completar, receptor calcula SHA-256 em streaming do `.part`. Igual → renomeia para `{sha256}` e envia `DONE`. Diferente → apaga, envia `FAIL {reason: hash}` e o remetente refaz uma vez; segunda falha encerra com erro.

**Falha e reconexão:** se o `PeerLink` cair, a transferência fica suspensa (não apagada). Na reconexão, o remetente reenvia `OFFER`; o receptor responde `ACCEPT` com os índices que faltam lidos do `.state`. Timeout de 10 min sem reconectar apaga o `.part`.

**Identidade de arquivo:** SHA-256 identifica arquivos **idênticos byte a byte**. A mesma música em outra codificação, bitrate ou com tags diferentes tem outro hash e será transferida normalmente.

## 6. Protocolo de sincronização

### 6.1 Relógio

- Cada aparelho usa um relógio monotônico local (`Stopwatch` iniciado no boot do app), nunca o relógio de parede.
- Convidado envia `PING {t0}`; anfitrião responde `PONG {t0, t1, t2}` (recebeu em t1, enviou em t2); convidado anota t3.
  - `rtt = (t3 - t0) - (t2 - t1)`
  - `offset = ((t1 - t0) + (t2 - t3)) / 2`
- Rajada de 8 pings ao conectar; usa a amostra de menor `rtt`. Repete uma rajada a cada 30 s e após reconexão. Registra `offset` ao longo do tempo para medir deriva entre relógios.

### 6.2 Estados numerados

O anfitrião é a única fonte de verdade. Toda mudança vira um estado:

```
STATE {
  roomEpoch,     // muda se o anfitrião reinicia a sala
  seq,           // inteiro crescente
  trackSha256,
  status,        // playing | paused
  positionMs,    // posição da faixa em atHostMs
  atHostMs       // instante (relógio do anfitrião) em que a posição vale
}
```

Regras do convidado:
- Descarta estado com `(roomEpoch, seq)` menor ou igual ao último aplicado.
- Posição esperada agora: `positionMs + (agoraNoHost - atHostMs)` se `playing`; `positionMs` se `paused`.
- Se não tem o arquivo de `trackSha256`, fica em "carregando", pede a transferência e aplica o estado mais recente assim que o arquivo chegar.

Comandos:
- **play / troca de faixa / seek tocando:** execução programada. `atHostMs = agora + lead`. `lead = maior(rtt)/2 entre convidados + tempoDePreparoDoPlayer + margem`. O `tempoDePreparoDoPlayer` é **medido na Fase 0** (tempo entre `seek`+`play` e o player reportar tocando) por plataforma; a margem começa em 50 ms e é ajustada pelos resultados. O convidado faz `seek` para a posição alvo, aguarda até `atHostMs` convertido para o relógio local e chama `play`.
- **pause:** imediato. O anfitrião pausa e envia `paused` com a posição exata; convidados pausam e fazem `seek` para ela.
- **seek pausado, voltar, avançar:** novo estado; mesmas regras acima.
- **Heartbeat:** a cada 2 s o anfitrião reenvia o estado atual (com `atHostMs` atualizado) para corrigir desvio e recuperar convidados que perderam mensagens.

Correção de desvio (parâmetros **experimentais**, ajustados com os dados da Fase 0):
- |desvio| < limiar A (início: 40 ms): não faz nada.
- entre A e B (início: 250 ms): ajusta velocidade em até ±2 % até zerar, se a plataforma mantiver o tom; senão, registrar e usar só seek.
- acima de B: `seek` direto para a posição esperada.

**Metas, não garantias:** desvio de software ≤ 80 ms e desvio audível ≤ 80 ms (sem Bluetooth) são metas experimentais. O resultado medido é o que vale para a decisão.

### 6.3 Medições

**Desvio do player (software):** a cada 250 ms, o convidado registra `posiçãoReportadaPeloPlayer - posiçãoEsperada`. O anfitrião registra a mesma diferença em relação ao próprio estado. Saída: JSONL com timestamp, evento (play, seek, etc.) e desvio.

**Latência audível (acústica):**
1. `tools/gerar_audio_teste` gera uma faixa com cliques curtos a cada 1 s e um padrão de identificação no início.
2. Os dois aparelhos tocam a faixa sincronizados; um terceiro dispositivo (ou o microfone do PC) grava os dois ao mesmo tempo, posicionado à mesma distância dos dois alto-falantes.
3. `tools/analisar_gravacao` detecta os pares de cliques na gravação e reporta a defasagem (média, p95, máximo).
- Mede-se uma vez com fones/alto-falante embutido e, separadamente, com Bluetooth, para quantificar o atraso de saída que o software não enxerga.

## 7. Isolamento Jam × player local

- `JamController` só chama métodos públicos do `LocalPlayer`. Exceções da Jam são capturadas na borda do módulo.
- Se a Jam cair, o anfitrião continua tocando normalmente; o convidado termina a faixa atual com o arquivo local e depois para.
- Teste obrigatório: matar a conexão (desligar Wi-Fi, encerrar sala, derrubar processo do outro lado) durante reprodução e confirmar que a reprodução local não parou nem travou.

## 8. Segurança e limites

**Regras do Firebase RTDB** (`firebase/database.rules.json`):
- Nada é legível ou gravável sem autenticação.
- `/rooms` não pode ser listado; só se lê `rooms/{code}` conhecendo o código.
- Criar sala: só se não existir; `hostUid == auth.uid`; `expiresAt <= now + 12h`.
- Qualquer leitura/escrita em sala exige `expiresAt > now`.
- `slots/{s1..s4}`: chave deve casar com `^s[1-4]$`; grava só se vazio e com o próprio `uid`; o convidado pode apagar o próprio slot; o anfitrião pode apagar qualquer slot. Isso limita a 5 participantes no total.
- `signal/{toUid}/{fromUid}`: só `fromUid` grava, só `toUid` lê; remetente precisa ser anfitrião ou ocupar um slot.
- As regras são testadas com o Firebase Local Emulator Suite (testes automatizados de permitido/negado).

**Código da sala:** 8 caracteres de um alfabeto de 31 símbolos sem ambíguos (sem 0/O, 1/I/L), gerado com `Random.secure()` (≈ 8,5 × 10¹¹ combinações). Expira em 12 h.

**Limpeza:** o RTDB não apaga sozinho. Na Fase 0, o anfitrião apaga a sala ao encerrar e as regras bloqueiam salas vencidas; uma limpeza agendada fica registrada como pendência para a Fase 2.

**Cache temporário:** `cache/jam/` apagado ao sair da Jam e na inicialização do app (órfãos); teto de 1 GB, removendo os mais antigos.

**Direito autoral:** o protocolo de transferência é um mecanismo técnico. Sala privada e cache temporário **não** autorizam compartilhar música protegida. A política do produto (o que o app permite compartilhar e o que avisa ao usuário) é decisão separada, antes de qualquer distribuição pública.

## 9. Plano de testes

### 9.1 Player local
| # | Plataforma | Teste | Evidência |
|---|---|---|---|
| P1 | Android | Toca em segundo plano por 15 min com tela bloqueada | log de posição + captura da notificação |
| P2 | Android | Controles da tela bloqueada e fone Bluetooth | vídeo curto ou capturas |
| P3 | Android | Android Auto via Desktop Head Unit (DHU): lista "Fila", play/pause/próxima | capturas do DHU |
| P4 | Windows | Toca, seek preciso, fila (próxima/anterior) | log de posição antes/depois do seek |
| P5 | Windows | Controles de mídia do sistema (teclas de mídia, painel do Windows) | capturas |
| P6 | Ambos | `setSpeed(1.02)` mantém o tom | gravação ou anotação |
| P7 | Ambos | Tempo de preparo (`seek`+`play` até tocando), 20 repetições | tabela p50/p95 |

### 9.2 Transferência
| # | Cenário | Medir |
|---|---|---|
| T1 | 10 MB, Android → Windows, mesma rede | MB/s, pico de memória (`ProcessInfo.maxRss`), SHA-256 confere |
| T2 | 50 MB, Android → Windows, mesma rede | idem |
| T3 | 10 e 50 MB, Windows → Android | idem |
| T4 | 50 MB com queda de rede no meio | retoma do ponto certo, integridade |
| T5 | 16 KiB × 64 KiB de bloco | diferença de velocidade e memória |
| T6 | Arquivo já presente no receptor | `HAVE`, zero bytes enviados |
| T7 | 50 MB do anfitrião (S25) para 2 convidados ao mesmo tempo (A53 + PC) | MB/s por convidado, upload total do anfitrião, memória |

### 9.3 Conectividade
| # | Cenário | Tipo de par esperado |
|---|---|---|
| C1 | Mesmo Wi-Fi | `host` |
| C2 | Celular em 4G, PC em Wi-Fi de casa | `srflx` ou `relay` |
| C3 | Forçado `iceTransportPolicy: relay` | `relay` |
| C4 | Worker recusa chamada sem token Firebase válido | erro 401 |

### 9.4 Sincronização e ciclo de vida
Executar cada cenário duas vezes: (a) arquivos idênticos já presentes nos dois lados; (b) arquivo recebido por DataChannel.

| # | Cenário | Medir |
|---|---|---|
| S1 | 10 min tocando contínuo | desvio de software (média, p95, máx) e deriva do relógio |
| S2 | Seek (10 repetições) | desvio após 1 s e após 5 s |
| S3 | Pause/play (10 repetições) | desvio na retomada |
| S4 | Troca de faixa (10 repetições) | desvio no início da faixa |
| S5 | Celular convidado bloqueado por 10 min | desvio, sem cortes |
| S6 | Convidado sai da rede por 30 s e volta | tempo até realinhar, desvio após |
| S7 | Anfitrião fecha o app | convidado termina a faixa e para; reprodução local nunca trava |
| S8 | Medição acústica (alto-falante e Bluetooth) | defasagem audível média, p95, máx |

## 10. Entregáveis

1. Protótipo compilando para Android (APK) e Windows (exe).
2. Pasta `docs/fase0/evidencias/` com logs JSONL, capturas e gravações.
3. `docs/fase0/resultados.md` com as tabelas da seção 9 preenchidas.
4. Lista de problemas encontrados e limitações que permanecem.
5. Decisão fundamentada: seguir com a abordagem B, ajustá-la ou mudar de arquitetura.

**Critérios de decisão (propostos):**
- Seguir com B se: transferência íntegra e retomável nas duas direções com memória estável; desvio de software p95 ≤ 150 ms após seek/troca; reprodução local nunca interrompida pela Jam; Android Auto e tela bloqueada funcionando.
- Reavaliar se: DataChannel instável no Windows, memória crescendo com o tamanho do arquivo, ou desvio p95 > 300 ms sem causa corrigível.

## 11. Decisões tomadas na revisão (escolhas do Claude, verificar)

- **Qualidade do código:** `player/`, `jam/transport`, `jam/transfer` e `jam/sync` são escritos como base das Fases 1 e 2, com testes unitários (protocolos testados com transporte simulado). `lab/` e as telas de teste são descartáveis.
- **Direção anfitrião/convidado:** S1–S4 rodam nas duas direções (Android anfitrião e Windows anfitrião). S5–S7 rodam com **Android como anfitrião**, o caso mais arriscado (tela bloqueada e sistema matando o app atingem a fonte da verdade); S5 também com Android convidado.
- **Formatos de áudio testados:** MP3 CBR, MP3 VBR, FLAC e M4A/AAC. P4, P6, P7, S2 e S4 rodam com todos; o restante com MP3 CBR. O MP3 VBR pode ter seek impreciso; se tiver, isso entra como limitação com o número medido.
- **Peso da medição acústica:** S8 conta para a decisão. Defasagem audível p95 ≤ 150 ms (sem Bluetooth) entra nos critérios de "seguir". Entre 150 e 300 ms (software ou acústico): ajustar parâmetros e repetir uma vez antes de decidir. Bluetooth é medido e registrado, mas não reprova: o software não enxerga esse atraso e a resposta é o ajuste manual por convidado.

## 12. Repositório público e distribuição

**Decisões do dono do projeto:**
- Repositório **público** no GitHub desde o início, com código, README, instruções de configuração e documentos técnicos suficientes para outra pessoa entender e rodar o projeto.
- Nada de senhas, chaves privadas, `.env` com segredos, credenciais do Firebase ou tokens do Cloudflare no repositório.
- APK de cada versão estável publicado no **GitHub Releases**, gerado e anexado automaticamente pelo GitHub Actions depois de testes e builds passarem. Download direto, com instruções de instalação, notas da versão e aviso claro de que é um APK instalado fora da Play Store.
- Código e releases organizados por versão e tag: cada APK corresponde a uma tag.
- APKs experimentais nunca aparecem como estáveis. Builds da Fase 0 podem sair como artefatos de CI ou **pré-releases**.
- Automação de release estável só depois de existir uma versão realmente testada.

**Estrutura inicial:**
```
AppMusica/
├── android/
├── windows/
├── lib/
├── test/
├── docs/superpowers/specs/
├── .github/workflows/ci.yml
├── .gitignore
├── README.md
├── LICENSE
└── pubspec.yaml
```
`backend/turn-worker/`, `firebase/` e `tools/` entram quando suas etapas começarem.

**Segredos (escolhas do Claude, verificar):**
- `.gitignore` bloqueia desde o primeiro commit: `.env*` (exceto `.env.example`), `google-services.json`, `lib/firebase_options.dart`, `firebase.json` local de projeto real, `*.jks`, `*.keystore`, `key.properties`, `.dev.vars`, `.wrangler/`.
- Arquivos de exemplo versionados (`*.example`) mostram o formato sem valores reais.
- As chaves de cliente do Firebase não são segredo no sentido estrito (a proteção vem das regras do RTDB e, depois, do App Check), mas ficam fora do repositório por decisão do projeto; o CI recebe esses arquivos por **GitHub Secrets** quando precisar.
- Chave TURN do Cloudflare existe só como segredo do Worker (`wrangler secret put`), nunca em arquivo.
- No GitHub: ativar **secret scanning** e **push protection** antes do primeiro push com código.
- Assinatura do APK: a keystore de release nunca é versionada; vai para GitHub Secrets quando a automação de release for criada. Pré-releases da Fase 0 usam assinatura de debug e o aviso de que **não** atualizam para a versão estável (é preciso desinstalar).

**CI da Fase 0 (`ci.yml`, em todo push e pull request):**
1. `flutter analyze` e `flutter test` (Ubuntu).
2. `flutter build apk --debug` (Ubuntu), APK enviado como artefato do workflow.
3. `flutter build windows` (Windows), executável enviado como artefato.
4. Testes das regras do Firebase com o Local Emulator Suite, quando `firebase/` existir.
- O CI não precisa de credenciais reais nessa fase: usa arquivos de configuração de exemplo/emulador.

## 13. Decisões do construtor

- Escolha dos pacotes de player e SMTC no Windows, seguindo o critério da seção 4.1.
- Valores iniciais de janela, limiares e margens, desde que fiquem configuráveis e sejam registrados nos resultados.
- Formato exato das mensagens JSON, desde que respeite os campos acima.
- Ferramentas de geração e análise de áudio (Dart ou Python).
