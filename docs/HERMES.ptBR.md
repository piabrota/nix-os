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

O que existe para o Hermes, e o que esta máquina usa: [`AWESOME-HERMES.ptBR.md`](AWESOME-HERMES.ptBR.md).

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
oficiais e cita o que afirma. Ele tem uma regra fixa do dono: toda mensagem com notícia boa (uma melhoria, um conserto que
deu certo, uma checagem que voltou ao normal) começa com **piou a melhoria**. O arquivo também explica que a linha "Claude Code" no começo do prompt
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

## Complementos da comunidade

Escolhidos da [awesome-hermes-agent](https://github.com/0xNyk/awesome-hermes-agent) em 2026-11-03.
Cada um foi lido antes de ser fixado (licença, último commit, cada ponto de entrada, e o que ele roda,
lê e envia), e está fixado por commit no `hermes.nix`:

| Complemento | Tipo | Para quê |
|---|---|---|
| [custom-dangerous-patterns](https://github.com/scross01/hermes-custom-dangerous-patterns-plugin) v0.5.2 (MIT) | plugin | Bloqueia comandos de terminal que batem com o `hermes/dangerous-patterns.yaml`: escrita no GitHub (`git push`, `gh pr merge`, `gh api -X POST` e os outros), leitura de segredos, `sudo` e rebuilds, e instalações ou `curl \| sh`. A lista fica na store, então o agente não consegue editá-la. |
| [evidence-ledger-research](https://github.com/markoblogo/abvx-agent-skills) (MIT) | skill | Disciplina de fonte, data, unidade e célula de tabela quando ele tira números de boletins, PDFs e artigos. |

Limites tirados dos playbooks da lista: `agent.max_turns = 60`; no máximo 2 subagentes ao mesmo
tempo, com 50 iterações cada e um nível só; `tool_loop_guardrails.hard_stop_enabled`; sem checagem de
atualização (quem atualiza é o Nix) e sem métricas compartilhadas.

Ficaram de fora, com o motivo: cronalytics (pede um diretório de plugin com escrita), rtk-hermes (a
ordem do hook dele com a lista de bloqueio não foi testada), agentburn (a skill roda `uvx`, um
download sem versão fixa), hermes-lcm e os provedores de memória (pesados demais para 1 GB, ou pedem
um servidor ou uma nuvem), e tudo que pede Node, API paga ou painel web, ou não tem licença. Nada na
lista cobre alertas brasileiros, balneabilidade ou ciência do mar: essas são skills próprias do
piabrota, ainda por escrever.

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

## Discord

O extra `messaging` do Hermes já tem o discord.py; o Discord só precisa de um bot e de duas linhas
no arquivo de segredos. Pelo guia do projeto (`website/docs/user-guide/messaging/discord.md` no
commit fixado):

1. No [Discord Developer Portal](https://discord.com/developers/applications): **New
   Application**, depois **Bot**. Em **Privileged Gateway Intents**, ligue **Message Content
   Intent** e **Server Members Intent** (sem a primeira, o Discord recusa a conexão). **Reset
   Token** e guarde o token.
2. Convide o bot para o seu servidor: **Installation** (ou OAuth2), escopos `bot` e
   `applications.commands`, permissões 309237763136 (ver, enviar, embeds, arquivos, histórico,
   threads, reações; sem voz).
3. Seu ID de usuário: no Discord, **Configurações → Avançado → Modo Desenvolvedor** ligado, depois
   clique com o botão direito no seu nome, **Copiar ID do usuário**.
4. Na máquina, acrescente ao `/var/lib/hermes-secrets/hermes.env` (`sudo nano`):

   ```text
   DISCORD_BOT_TOKEN=...
   DISCORD_ALLOWED_USERS=<seu ID de usuário>
   ```

   Depois rode `sudo /run/current-system/bin/switch-to-configuration switch && sudo systemctl
   restart hermes-agent`. O log diz quando o Discord conecta.

Num canal de servidor, ele só responde quando é @mencionado, numa thread própria; numa DM, sempre.
Ele nunca menciona `@everyone`, `@here` nem um cargo (é o padrão, e o `SOUL.md` diz isso). O
`hermes.nix` limita os anexos a 20 MiB, como no Telegram. Mande `/sethome` no canal onde os
resultados agendados devem chegar.

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
