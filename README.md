# AppMusica

> **Projeto experimental, em Fase 0 (validação técnica).**
> Ainda não existe aplicativo utilizável. Nada aqui deve ser tratado como funcionalidade pronta.

## O que é

AppMusica é um player de música para **Android** e **Windows**, feito em Flutter, que toca arquivos de música do próprio aparelho, sem propaganda e sem assinatura.

O objetivo de longo prazo inclui uma **Jam**: amigos entram numa sala por código e ouvem juntos, mesmo sem ter o arquivo da música.

## Status atual

| Fase | O que é | Situação |
|---|---|---|
| 0 | Validação técnica dos riscos de arquitetura | **Em andamento** |
| 1 | Player local (Android e Windows) | Não iniciada |
| 2 | Jam entre amigos | Não iniciada |

A Fase 0 testa, com protótipos e medições, se a arquitetura proposta funciona:

- reprodução local em segundo plano, tela bloqueada e Android Auto (Android);
- reprodução local e controles de mídia do sistema (Windows);
- transferência de arquivos entre aparelhos por WebRTC DataChannel;
- sincronização da reprodução entre aparelhos;
- conectividade na mesma rede e entre redes diferentes.

O resultado da Fase 0 pode confirmar a arquitetura ou exigir mudanças. Detalhes em [docs/superpowers/specs/2026-10-21-fase0-validacao-design.md](docs/superpowers/specs/2026-10-21-fase0-validacao-design.md).

## O que o projeto não faz

- Não baixa músicas do Spotify, YouTube ou de qualquer serviço.
- Não fornece músicas: toca apenas arquivos que o usuário já possui.

## Como rodar

Ainda não há código executável. Esta seção será preenchida quando o protótipo da Fase 0 existir.

Requisitos previstos:

- Flutter (canal stable)
- Android SDK, para builds Android
- Visual Studio com a carga de trabalho "Desenvolvimento para desktop com C++", para builds Windows

## Segurança

Nenhuma chave, token ou credencial é versionada neste repositório. Arquivos de configuração com segredos (Firebase, Cloudflare, assinatura do APK) ficam fora do Git; quando necessários, haverá modelos `*.example` com instruções.

Se você encontrar algum segredo publicado por engano, abra uma issue sem incluir o valor.

## Downloads

Ainda não há versões publicadas. Quando houver, os APKs estarão em **Releases**, com notas da versão e instruções de instalação. Versões experimentais serão marcadas como pré-release.
