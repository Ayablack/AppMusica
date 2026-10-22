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

Por enquanto existe só um esqueleto: o app abre uma tela informando que é a Fase 0. Não há player nem Jam.

Requisitos:

- Flutter 3.47.2 (canal stable), a mesma versão usada no CI
- Android SDK e JDK 17 ou superior, para builds Android
- Visual Studio com a carga de trabalho "Desenvolvimento para desktop com C++", para builds Windows

Comandos:

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter build apk --debug
```

## Integração contínua

Cada push e pull request roda o workflow [CI](.github/workflows/ci.yml): `flutter analyze`, `flutter test`, build do APK de debug e build do Windows. O APK e a pasta do Windows ficam disponíveis como **artefatos do workflow** por 14 dias. Eles não são releases: o APK é assinado com chave de debug e serve só para validação.

## Segurança

Nenhuma chave, token ou credencial é versionada neste repositório. Arquivos de configuração com segredos (Firebase, Cloudflare, assinatura do APK) ficam fora do Git; quando necessários, haverá modelos `*.example` com instruções.

Se você encontrar algum segredo publicado por engano, abra uma issue sem incluir o valor.

## Downloads

Ainda não há versões publicadas. Quando houver, os APKs estarão em **Releases**, com notas da versão e instruções de instalação. Versões experimentais serão marcadas como pré-release.
