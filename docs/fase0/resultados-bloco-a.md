# Fase 0 · Bloco A — Resultados

> Resultados **simulados** (transporte em memória, sem rede) e **reais** (WebRTC e áudio nativos) ficam em seções separadas. Só os reais contam para a decisão.

## Resultados reais

### M1 — Player no Windows (2026-10-22, PC de desenvolvimento)

Candidato `just_audio` + `just_audio_media_kit` (libmpv). Seno de 1 kHz, 60 s, gerado com ffmpeg. Teste: `integration_test/player_windows_spike_test.dart`.

| Formato | Posição × relógio (5 s) | Erro de seek p95 (posição reportada) | Taxa a 1,02× |
|---|---|---|---|
| WAV | −1 ms | 0 ms | 1,0198 |
| MP3 CBR | 0 ms | 0 ms | 1,0201 |
| MP3 VBR | −1 ms | 0 ms | 1,0198 |
| FLAC | −1 ms | 0 ms | 1,0200 |
| M4A | 0 ms | 0 ms | 1,0196 |

- Tom a 1,02×: **1000 Hz** (preservado). Controle sem correção de tom: 1020 Hz, o que confirma que a medição detecta mudança de tom.
- Ressalva: o erro de seek é a posição **informada pelo player**. A precisão audível do seek fica para o teste acústico (S8).

### M2 — WebRTC real no mesmo PC (2026-10-22)

Dois pares WebRTC nativos (`flutter_webrtc`) no mesmo processo Windows, sinalização pelo servidor LAN real em 127.0.0.1. Teste: `integration_test/webrtc_loopback_test.dart`. Prova a pilha completa, **não** substitui o teste entre aparelhos.

| Execução | Par ICE | Conexão estabelecida em | 1 MiB (16 KiB/bloco) | Integridade |
|---|---|---|---|---|
| 1 | host/prflx | ~0,4 s | 138 ms | SHA-256 confere |
| 2 | host/host | ~0,4 s | 165 ms | SHA-256 confere |
| 3 | host/prflx | ~0,4 s | 134 ms | SHA-256 confere |

`prflx` (peer-reflexive): o outro lado foi descoberto pela checagem de conectividade antes de o candidato chegar pela sinalização. A conexão continua direta na rede local.

### M2 — Entre aparelhos

Conexão S25 ↔ A53 na mesma rede Wi-Fi, **bem-sucedida nos dois sentidos** (relato do dono do projeto, 2026-10-22). Os números detalhados ainda não foram registrados aqui; o teste de tela desligada foi refeito com o monitor revisado (abaixo).

| Anfitrião | Convidado | Conectou? | Tempo | Par ICE | RTT mediano | 1 MiB | Integridade | Observações |
|---|---|---|---|---|---|---|---|---|
| S25 | A53 | | | | | | | |
| A53 | S25 | | | | | | | |
| S25 (tela desligada 2 min) | A53 | | | | | | | |

### Revisão do M2 (2026-10-22)

**Causa dos erros iniciais (reproduzidos no PC):**

| Erro | Causa | Correção |
|---|---|---|
| `ArgumentError: No host specified in URI` | Botão "Entrar" com o campo de IP vazio | IP, porta e código validados antes de conectar; erro `invalid_address` com mensagem clara |
| `SocketException: Failed host lookup` | IP digitado com vírgula (teclado numérico Samsung) ou malformado | Mesmo tratamento: `invalid_address`; teclado com ponto decimal |
| `SocketException` (conexão recusada) | IP certo, mas porta sem sala aberta (sala encerrada ou porta errada) | Erro `refused` com mensagem; anfitrião mostra o nome da interface de cada IP, Wi-Fi primeiro |

As mensagens mostradas ao usuário e o log não incluem IPs. Erros não tratados passam a aparecer no log com tipo, mensagem saneada e até 3 linhas do código do app.

**Monitor de tela desligada revisado:** um ping a cada 2 s por convidado, prazo de 3 s, em sequência. Registra cada ping (sucesso ou falha, RTT), o estado real da tela (`PowerManager.isInteractive`) e se o serviço em primeiro plano estava ativo. Resumo: enviados, respostas, falhas, RTT mediano e máximo, maior intervalo sem resposta, maior atraso entre envios, tempo com a tela apagada confirmada e respostas e falhas nesse período. Exporta CSV.

**Pendente (aparelhos):** repetir o teste de tela desligada com o monitor revisado, apagando a tela do S25 e depois a do A53.

| Aparelho com a tela apagada | Monitor rodando em | Tela apagada confirmada | Tempo apagada | Respostas / falhas com a tela apagada | RTT máximo | Maior intervalo sem resposta | Serviço ativo o tempo todo |
|---|---|---|---|---|---|---|---|
| S25 | S25 e A53 | | | | | | |
| A53 | S25 e A53 | | | | | | |

## Resultados simulados

| Suíte | O que cobre | Resultado |
|---|---|---|
| `test/jam/signaling/*` | Código da sala, limite de 5, prazo do hello, 64 KiB, bloqueio após 5 códigos errados, roteamento só convidado ↔ anfitrião, validação de IP/porta/código, erros `refused`, `timeout`, `port_in_use`, mensagens sem IP (servidor LAN real em 127.0.0.1, sem WebRTC) | 27/27 |
| `test/jam/transport/*` | `MemoryPeerLink` (queda, reconexão, corrupção, buffer) e negociação da `PeerLinkFactory` com sessão falsa | 11/11 |
| `test/player/*` | Fila de reprodução | 6/6 |
| `test/metrics/*` | Saneamento de IPv4, IPv6, caminhos, e-mails e stack traces | 6/6 |
| `test/lab/*` | Estatísticas do monitor (sucessos, falhas, RTT, intervalos, tela apagada, serviço, CSV) e abertura da tela do lab | 9/9 |

## Problemas encontrados

1. `smtc_windows` exige toolchain Rust (cargokit). Removido até a Task 4, onde se decide entre Rust e plugin C++.
2. `PeerLinkFactory` perdia o link criado antes de alguém escutar. Achado no teste WebRTC real e corrigido, com teste de regressão.
3. Ao cair um canal depois de conectado, o link voltava para "conectando" em vez de "desconectado". Corrigido.
4. A tela do laboratório tentava redesenhar depois de fechada. Corrigido.
5. O teste de integração WebRTC chegou a ficar 10 minutos travado (aguardava um link já perdido, sem prazo). Agora todo teste de integração tem limite de 2 minutos e as esperas internas têm prazo próprio.
6. Testes de integração no Windows rodados em sequência imediata às vezes falham por erro de arquivo temporário da ferramenta do Flutter, antes de o teste começar. Não é falha do app; esperar alguns segundos entre execuções resolve.
