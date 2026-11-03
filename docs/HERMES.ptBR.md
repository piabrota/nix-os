# Hermes Agent na piabrota

[English](HERMES.md)

O [Hermes Agent](https://github.com/NousResearch/hermes-agent) é o agente da Nous Research: um
programa em Python que conversa por plataformas de chat (Telegram, Discord, Slack e outras), usa
ferramentas e roda tarefas agendadas. Esta máquina o roda como a unit `hermes-agent` (`hermes.nix`):
o gateway de mensagens dele, que responde nas plataformas cujos tokens tem.

O projeto publica um flake com um pacote e um módulo NixOS (`nixosModules.default`). O `flake.nix`
daqui o traz como o input `hermes-agent`, e o `hermes.nix` só escolhe as opções. Para o projeto, Nix
e NixOS são plataforma de nível 2: o flake e o módulo são mantidos "no melhor esforço", e um commit
na `main` deles pode quebrá-los. Por isso o `flake.lock` fixa um commit, e a atualização semanal do
flake (`flake-update.yml`) só o move num PR que o CI constrói antes do merge.

## O que o `hermes.nix` escolhe

| | |
|---|---|
| Modo | Nativo: um serviço systemd no host, com o sandbox do módulo (`ProtectSystem=strict`, `NoNewPrivileges`, `PrivateTmp`). Não o modo container, que pediria Docker ou Podman. |
| Pacote | `minimal`, mais os extras `anthropic` (o SDK da Anthropic) e `messaging` (Telegram, Discord, Slack). O padrão do flake, `full`, traz uns 700 MB a mais (voz, Bedrock, Modal e afins). |
| Modelo | `claude-sonnet-5-5` pelo provedor `anthropic`, com a assinatura do dono: `CLAUDE_CODE_OAUTH_TOKEN` (de `claude setup-token`), como o piabrota/agents faz. Sem chave de API. |
| Segredos | `/var/lib/hermes-secrets/hermes.env`, escrito à mão na máquina, só root lê. Nunca no repositório nem na store. |
| Limites | `MemoryMax=1G` (um quarto da RAM) e `CPUWeight=50`: sshd, nginx e os apps ganham a CPU primeiro. |
| Estado | `/var/lib/hermes` (`HERMES_HOME` é `/var/lib/hermes/.hermes`): a configuração, a memória, as sessões e o `.env`. |
| CLI | `hermes` no PATH (`addToSystemPackages`), sobre o mesmo estado do serviço; o `h0ffmann` está no grupo `hermes`. |

A configuração fica no Nix: no NixOS, `hermes setup`, `hermes config set` e
`hermes gateway install` recusam mudar o que o módulo gerencia. Mude o `hermes.nix` num PR.

## Quem ele é

O `hermes/SOUL.md` é a identidade dele: piabrota-hermes, nesta VPS, no Claude Sonnet. O arquivo diz o
que ele tem e o que não tem, e traz regras tiradas do dogma do piabrota (`piabrota/mu`, `DOGMA.md`):
ele nunca lê nem repete um segredo, nunca dá push nem faz merge, só aceita alertas de fontes
oficiais e cita o que afirma. O arquivo também explica que a linha "Claude Code" no começo do prompt
é o jeito de a assinatura se autenticar. O `hermes/AGENTS.md`, no diretório de trabalho dele, é o
resumo: o dono, os repositórios do piabrota e do marola, as fontes oficiais para os watchers, os jobs
que o dono pode pedir e esta VPS. A ativação instala os dois a cada deploy: mude-os aqui, num PR. O
fuso horário é `America/Sao_Paulo`, e o usuário `hermes` lê o journal (`systemd-journal`) para a
checagem diária da máquina.

## Complementos

Todos ficam declarados no `hermes.nix`, então chegam com um deploy e andam junto com o input do flake.

| Complemento | Tipo | Para quê |
|---|---|---|
| `mcp`, `ddgs` | extras | O cliente MCP (sem ele os servidores abaixo não fazem nada) e a busca do DuckDuckGo, sem chave |
| DeepWiki, Context7 | servidores MCP remotos, sem chave | Perguntas sobre repositórios públicos (piabrota, marola-dev, nixpkgs) e documentação atual de bibliotecas. Nada roda na máquina por causa deles. |
| `watchers`, `rss-feeds` | skills opcionais | Consultam RSS, APIs JSON e o GitHub sem repetir aviso, no cron do Hermes: boletins de balneabilidade, alertas da Defesa Civil e do INMET, notícias do mar |
| `duckduckgo-search`, `research-paper-writing` | skills opcionais | Busca na web; artigos científicos, junto com as skills `arxiv` e `grounded-citations`, que já vêm no pacote |
| `ast-grep` | skill opcional, mais o `pkgs.ast-grep` | Busca estrutural em código |
| `gh` | pacote | Para a skill `github`, que já vem no pacote. Ponha um token fine-grained só com acesso de leitura no arquivo de ambiente como `GITHUB_TOKEN`: ela lê, e não consegue dar push nem fazer merge. |

As skills opcionais formam um diretório só de leitura em `skills.external_dirs`, tirado do
`optional-skills/` do projeto no commit fixado. As skills que vêm no pacote (`arxiv`, `github`,
`obsidian`, `weekly-review-planning` e as outras) já estão lá. Ficaram de fora, porque pedem Node,
Go ou Homebrew na máquina: `pr-lens`, `qmd`, `llm-wiki`, `blogwatcher`, `archify`. Ficaram de fora
pelo tamanho da máquina: voz, as skills de `mlops`, um navegador local e o `computer-use`.

## Configurar uma vez na máquina

Sem o arquivo de segredos, a ativação só avisa (`cannot read environmentFile`) e o gateway sobe sem
plataforma nenhuma, rodando só as tarefas agendadas. Um deploy nunca falha por isso.

1. Gere o token da assinatura no seu computador: `claude setup-token`.
2. Crie um bot na plataforma que você quer. No Telegram: fale com o
   [@BotFather](https://t.me/BotFather), `/newbot`, e guarde o token. Seu ID numérico vem do
   [@userinfobot](https://t.me/userinfobot).
3. Na máquina, escreva o arquivo (cole as linhas e termine com Ctrl-D):

   ```console
   ssh h0ffmann@piabrota.art
   sudo install -m 600 /dev/stdin /var/lib/hermes-secrets/hermes.env
   CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
   TELEGRAM_BOT_TOKEN=123456:ABC...
   TELEGRAM_ALLOWED_USERS=<seu ID numérico>
   GITHUB_TOKEN=github_pat_...   # opcional: só leitura, para a skill github
   ```

   No lugar do Telegram: `DISCORD_BOT_TOKEN` e `DISCORD_ALLOWED_USERS`, ou `SLACK_BOT_TOKEN`,
   `SLACK_APP_TOKEN` e `SLACK_ALLOWED_USERS` (os nomes vêm do `.env.example` do projeto). Sem uma
   lista de usuários permitidos, o gateway recusa todo mundo (`GATEWAY_ALLOW_ALL_USERS` é `false`
   por padrão).
4. Quem copia esse arquivo para o `.env` do Hermes é a ativação do sistema, não o serviço. Rode a
   ativação de novo e reinicie:

   ```console
   sudo /run/current-system/bin/switch-to-configuration switch
   sudo systemctl restart hermes-agent
   ```

   O mesmo vale toda vez que você mudar o arquivo. O próximo deploy também copia.

## Conferir

```console
systemctl status hermes-agent
journalctl -u hermes-agent -n 100
hermes status
hermes doctor
```

O log diz quais plataformas conectaram; "No messaging platforms enabled" quer dizer que o `.env`
não tem token de plataforma.

## Atualizar e desligar

- **Atualizar:** o PR semanal do `flake-update.yml` move o input `hermes-agent` junto com o resto,
  com a diferença do closure (`dix`). O CI constrói; o merge faz o deploy.
- **Desligar:** tire o `./hermes.nix` dos `imports` do `configuration.nix` num PR. O deploy para e
  remove a unit; `/var/lib/hermes` e `/var/lib/hermes-secrets` ficam na máquina até alguém apagar.

## Fontes e o que não foi conferido

- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent): `flake.nix`,
  `nix/nixosModules.nix`, `nix/moduleCommon.nix` (opções, a ativação que junta os
  `environmentFiles` no `.env`), `nix/packages.nix` (`minimal`, `full`, `messaging`),
  `hermes_cli/auth.py` (o `CLAUDE_CODE_OAUTH_TOKEN` no provedor `anthropic`), `.env.example`, e
  [a página de Nix](https://hermes-agent.nousresearch.com/docs/getting-started/nix-setup), lidos em
  2026-11-02.
- Não conferido: o sistema não foi construído nem rodado na máquina ainda (o CI constrói o PR); o
  uso de RAM e o tamanho do closure na VPS não foram medidos.
