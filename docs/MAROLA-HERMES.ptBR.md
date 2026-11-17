# marola-hermes

[English](MAROLA-HERMES.md)

O marola-hermes é o bot de conversa da [marola](https://marola.dev), rodado pelo Hermes no piabrota2
(`marola-hermes.nix`). Não é um serviço novo: é o perfil `marola-hermes` do Hermes, servido pelo
mesmo gateway do perfil principal (`gateway.multiplex_profiles`). Um perfil com credencial de bot
própria ganha o próprio adaptador e responde como esse bot; os segredos vêm só do `.env` dele, nunca
do perfil principal (`gateway/AGENTS.md` do upstream na v0.23.1).

Está desligado (`piabrota.marolaHermes.enable = false` em `hosts/piabrota2`).

## O que ele pode fazer

| | |
|---|---|
| Plataforma | Telegram (polling, sem porta aberta) ou Discord, conforme o token no arquivo de segredos. |
| Modelo | `claude-sonnet-5-5`, na assinatura do dono (o `CLAUDE_CODE_OAUTH_TOKEN` do `hermes.env`, copiado para o `.env` do perfil). |
| Ferramentas | `web`, `skills`, `todo` (`platform_toolsets`). Sem terminal, sem arquivos, sem navegador, sem mensagem para outros chats. |
| GitHub | Nenhum. O que o Hermes escreve nos repositórios da marola continua com o marola-pr-bot (`marola-bot.nix`). |
| Quem | Só os IDs em `TELEGRAM_ALLOWED_USERS` ou `DISCORD_ALLOWED_USERS`. Sem lista, o gateway recusa todo mundo. |

## Como ligar

1. Crie o bot. No Telegram: [@BotFather](https://t.me/BotFather), `/newbot`, nome `marola-hermes`,
   e guarde o token. No Discord: uma aplicação nova com bot no Developer Portal.
2. No servidor, grave o arquivo de segredos (termine com Ctrl-D):

   ```console
   ssh h0ffmann@hermes.piabrota.art
   sudo install -m 600 /dev/stdin /var/lib/marola-hermes-secrets/bot.env
   TELEGRAM_BOT_TOKEN=123456:ABC...
   TELEGRAM_ALLOWED_USERS=<IDs numéricos, separados por vírgula>
   ```

   Para o Discord: `DISCORD_BOT_TOKEN` e `DISCORD_ALLOWED_USERS`. Só as linhas `TELEGRAM_*` e
   `DISCORD_*` são copiadas.
3. Mude para `piabrota.marolaHermes.enable = true` em `hosts/piabrota2/default.nix` num pull
   request. O merge faz o deploy.
4. Reinicie o Hermes uma vez, para o gateway subir o bot novo: `just remote-restart hermes h0ffmann <endereço>`.

A unidade `marola-hermes-env` grava o `.env` do perfil; uma unidade de caminho roda de novo quando o
`bot.env` muda. Um token novo ainda pede o reinício do passo 4.

## Como conferir

```console
systemctl status marola-hermes-env
sudo journalctl -u hermes-agent | grep -i marola-hermes
```

Depois, escreva para o bot de uma conta permitida.

## Como desligar

`piabrota.marolaHermes.enable = false`, ou apague o `bot.env` e reinicie o Hermes.

## O que não foi conferido

- O build completo do sistema com o módulo ligado: `nix flake check` não rodou. O módulo foi avaliado
  sozinho contra o nixpkgs, com opções do Hermes simuladas (os arquivos do perfil, o `config.yaml` e a unidade).
- Se o `.env` de um perfil gravado depois que o gateway subiu é lido sem reiniciar.
