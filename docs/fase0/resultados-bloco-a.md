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

_Pendente: S25 ↔ A53 (os dois sentidos), S25 anfitrião com tela desligada por 2 min._

| Anfitrião | Convidado | Conectou? | Tempo | Par ICE | RTT mediano | 1 MiB | Integridade | Observações |
|---|---|---|---|---|---|---|---|---|
| S25 | A53 | | | | | | | |
| A53 | S25 | | | | | | | |
| S25 (tela desligada 2 min) | A53 | | | | | | | |

## Resultados simulados

| Suíte | O que cobre | Resultado |
|---|---|---|
| `test/jam/signaling/*` | Código da sala, limite de 5, prazo do hello, 64 KiB, bloqueio após 5 códigos errados, roteamento só convidado ↔ anfitrião (servidor LAN real em 127.0.0.1, sem WebRTC) | 14/14 |
| `test/jam/transport/*` | `MemoryPeerLink` (queda, reconexão, corrupção, buffer) e negociação da `PeerLinkFactory` com sessão falsa | 11/11 |
| `test/player/*` | Fila de reprodução | 6/6 |

## Problemas encontrados

1. `smtc_windows` exige toolchain Rust (cargokit). Removido até a Task 4, onde se decide entre Rust e plugin C++.
2. `PeerLinkFactory` perdia o link criado antes de alguém escutar. Achado no teste WebRTC real e corrigido, com teste de regressão.
3. Ao cair um canal depois de conectado, o link voltava para "conectando" em vez de "desconectado". Corrigido.
4. A tela do laboratório tentava redesenhar depois de fechada. Corrigido.
5. Testes de integração no Windows rodados em sequência imediata às vezes falham por erro de arquivo temporário da ferramenta do Flutter, antes de o teste começar. Não é falha do app; esperar alguns segundos entre execuções resolve.
