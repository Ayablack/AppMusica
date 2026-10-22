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

Aparelhos: **S25** SM-S931B, Android 16, One UI 8.5 · **A53** SM-A536E, Android 16, One UI 8.0. Rede Wi-Fi doméstica. Medição de 2026-10-22, conduzida por adb sem fio (APK `c05b808`), otimização de bateria no padrão (ativa).

| Anfitrião | Convidado | Conectou | Tempo até conectar | Par ICE | Sentido | RTT mediano | 1 MiB | Integridade |
|---|---|---|---|---|---|---|---|---|
| S25 | A53 | sim | 515 ms (S25) / 461 ms (A53) | prflx/prflx | S25 → A53 | 16 ms | 183 ms (5,5 MB/s) | SHA-256 confere |
| S25 | A53 | sim | (mesma conexão) | prflx/prflx | A53 → S25 | 14 ms | 204 ms (4,9 MB/s) | SHA-256 confere |

`prflx/prflx`: cada lado descobriu o outro pela checagem de conectividade (os candidatos `host` do WebRTC no Android usam nomes mDNS `.local`). A conexão é direta na rede local, sem servidor no meio.

### Revisão do M2 (2026-10-22)

**Causa dos erros iniciais (reproduzidos no PC):**

| Erro | Causa | Correção |
|---|---|---|
| `ArgumentError: No host specified in URI` | Botão "Entrar" com o campo de IP vazio | IP, porta e código validados antes de conectar; erro `invalid_address` com mensagem clara |
| `SocketException: Failed host lookup` | IP digitado com vírgula (teclado numérico Samsung) ou malformado | Mesmo tratamento: `invalid_address`; teclado com ponto decimal |
| `SocketException` (conexão recusada) | IP certo, mas porta sem sala aberta (sala encerrada ou porta errada) | Erro `refused` com mensagem; anfitrião mostra o nome da interface de cada IP, Wi-Fi primeiro |

As mensagens mostradas ao usuário e o log não incluem IPs. Erros não tratados passam a aparecer no log com tipo, mensagem saneada e até 3 linhas do código do app.

**Monitor de tela desligada revisado:** um ping a cada 2 s por convidado, prazo de 3 s, em sequência. Registra cada ping (sucesso ou falha, RTT), o estado real da tela (`PowerManager.isInteractive`) e se o serviço em primeiro plano estava ativo. Resumo: enviados, respostas, falhas, RTT mediano e máximo, maior intervalo sem resposta, maior atraso entre envios, tempo com a tela apagada confirmada e respostas e falhas nesse período. Exporta CSV.

**Teste de tela apagada (real, 2026-10-22).** Monitor nos dois aparelhos ao mesmo tempo; 20 s com as telas acesas, tela de um aparelho apagada por 2 min (`KEYCODE_SLEEP`, o mesmo efeito do botão lateral), depois acesa. O estado da tela vem do próprio aparelho (`PowerManager.isInteractive`) e foi conferido também por `dumpsys power` (`Dozing`).

| Tela apagada | Medido por | Pings | Falhas | Tela apagada confirmada | RTT mediano antes / apagada / depois | RTT máx. com a tela apagada | Maior intervalo sem resposta | Maior atraso entre envios | Serviço ativo o tempo todo |
|---|---|---|---|---|---|---|---|---|---|
| S25 (anfitrião) | S25 (o próprio) | 107 | 0 | sim, 138 s (69 respostas, 0 falhas) | geral 27 ms, máx. 59 ms | 59 ms | 2,0 s | 2,0 s | sim |
| S25 (anfitrião) | A53 | 85 | 0 | — (tela do A53 acesa) | 64 / 68 / 56 ms | 171 ms | 2,0 s | 2,0 s | sim |
| A53 (convidado) | S25 | 80 | 0 | — (tela do S25 acesa) | 28 / 33 / 25 ms | 405 ms | 2,0 s | 2,0 s | sim |
| A53 (convidado) | A53 (o próprio) | 1389 em 46 min | 0 | sim, 2716 s (~45 min: os 2 min do teste e mais ~43 min depois, na tela de bloqueio) | 55 ms acesa / 64 ms apagada | 783 ms (4 de 1357 acima de 300 ms; p99 218 ms) | 2,0 s | 2,0 s | sim |

**Teste longo (não planejado).** O monitor do A53 continuou rodando depois do teste, até o aparelho ser desbloqueado: **46 min, 1389 pings, 0 falhas**, com a tela apagada confirmada por ~45 min. No mesmo período, o app do S25 (anfitrião) ficou ~33 min em segundo plano (`paused`, de 19:31 a 52:27 no relógio do S25) e respondeu todos os pings. O estado da tela do S25 nesse trecho não foi medido (o monitor dele estava desligado). Evidência: `2026-10-22-monitor-a53-proprio-apagado-45min.txt`.

**Conclusão parcial:** com a tela apagada por 2 min nos dois modelos, e por ~45 min no A53, a conexão continuou sem nenhuma falha de ping, o serviço em primeiro plano ficou ativo e o timer do app não atrasou (envios a cada 2,0 s). O RTT com a tela apagada teve picos (até 405 ms no A53), sem perda.

**Ressalvas:**
- A depuração sem fio (adb por Wi-Fi) estava ligada nos dois aparelhos neste teste. Resultado confirmado depois sem ela (seção abaixo).
- Otimização de bateria no padrão (ativa); não foi preciso desativá-la. O período longo (~45 min) foi medido só com o A53 apagado e com a depuração sem fio ligada.
- O RTT do monitor (~30–70 ms) é maior que o do teste isolado (14–16 ms) porque os dois monitores e as leituras de tela por adb rodavam juntos.

### Repetição sem depuração sem fio (2026-10-22, conduzida pelo dono do projeto)

Mesmos aparelhos e rede, **depuração sem fio desligada**, otimização de bateria no padrão (ativa), S25 anfitrião e A53 convidado. O teste com o A53 como anfitrião foi dispensado pelo dono do projeto.

**Conexão e 1 MiB**

| Sentido | Conectou em | Par ICE | RTT | 1 MiB | Integridade |
|---|---|---|---|---|---|
| S25 → A53 | 558 ms (S25) / 495 ms (A53) | prflx/prflx | 17 ms | 208 ms (4,8 MB/s) | SHA-256 confere |
| A53 → S25 | (mesma conexão) | prflx/prflx | 8 ms | 135 ms (7,4 MB/s) | SHA-256 confere |

**Monitor contínuo (um ping a cada 2 s, prazo de 3 s)**

| Teste | Medido por | Pings | Falhas | Tela apagada confirmada | RTT mediano | RTT máx. | Maior intervalo sem resposta | Maior atraso entre envios | Serviço ativo |
|---|---|---|---|---|---|---|---|---|---|
| Tela do S25 apagada ~2 min | S25 | 75 | 0 | 130 s (65 respostas, 0 falhas) | 28 ms | 71 ms | 2,0 s | 2,0 s | sempre |
| Tela do S25 apagada ~2 min | A53 | 74 | 0 | — | 19 ms | 107 ms | 2,0 s | 2,0 s | sempre |
| Tela do A53 apagada ~2 min | S25 | 72 | 0 | — | 111 ms | 348 ms | 2,0 s | 2,0 s | sempre |
| Tela do A53 apagada ~2 min | A53 | 72 | 0 | 134 s (67 respostas, 0 falhas) | 77 ms | 277 ms | 2,0 s | 2,0 s | sempre |
| **As duas telas apagadas ~31 min** | S25 | 944 | 0 | 1846 s (923 respostas, 0 falhas) | 25 ms | 715 ms | 2,0 s | 2,0 s | sempre |
| **As duas telas apagadas ~31 min** | A53 | 945 | 0 | 1843 s (921 respostas, 0 falhas) | 44 ms | 330 ms | 2,0 s | 2,0 s | sempre |

**Conclusão:** sem a depuração sem fio, o resultado se mantém. Com a tela apagada (2 min em cada aparelho e ~31 min nos dois ao mesmo tempo), **nenhum ping falhou** em 2.182 pings, o serviço em primeiro plano ficou ativo e o timer do app não atrasou. O RTT sobe com a tela apagada (picos de até 715 ms), sem perda de mensagens. A ressalva sobre a depuração sem fio está resolvida.

**Bug encontrado neste teste:** ao tocar em "Encerrar" no S25, `HttpException: HttpServer is not bound to a socket` (a tela lia a porta de um servidor já fechado). Corrigido com teste de regressão. O log também mostrou "serviço em primeiro plano: já ativo" ao abrir a sala: era um serviço que sobrou de uma sessão anterior; o lab agora o encerra ao abrir.

## Resultados simulados

| Suíte | O que cobre | Resultado |
|---|---|---|
| `test/jam/signaling/*` | Porta legível após encerrar, código da sala, limite de 5, prazo do hello, 64 KiB, bloqueio após 5 códigos errados, roteamento só convidado ↔ anfitrião, validação de IP/porta/código, erros `refused`, `timeout`, `port_in_use`, mensagens sem IP (servidor LAN real em 127.0.0.1, sem WebRTC) | 28/28 |
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
6. Ao encerrar a sala no S25: `HttpException: HttpServer is not bound to a socket`. Corrigido (porta guardada ao abrir), com teste de regressão.
7. Serviço em primeiro plano de sessão anterior continuava ativo ao abrir nova sala. O lab agora o encerra ao abrir.
8. Testes de integração no Windows rodados em sequência imediata às vezes falham por erro de arquivo temporário da ferramenta do Flutter, antes de o teste começar. Não é falha do app; esperar alguns segundos entre execuções resolve.
