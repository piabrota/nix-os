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
| Modelo | `claude-sonnet-5-5` pelo provedor `anthropic`, com o `claude-haiku-4-5` para subagentes e três tarefas laterais baratas (veja "Ajustes de execução"), com a assinatura do dono: `CLAUDE_CODE_OAUTH_TOKEN` (de `claude setup-token`), como o piabrota/agents faz. Sem chave de API. |
| Segredos | `/var/lib/hermes-secrets/hermes.env`, escrito à mão na máquina, só root lê. Nunca no repositório nem na store. |
| Limites | `MemoryMax=1G` (um quarto da RAM) e `CPUWeight=50`: sshd, nginx e os apps ganham a CPU primeiro. |
| Estado | `/var/lib/hermes` (`HERMES_HOME` é `/var/lib/hermes/.hermes`): a configuração, a memória, as sessões e o `.env`. |
| CLI | `hermes` no PATH (`addToSystemPackages`), sobre o mesmo estado do serviço; o `h0ffmann` está no grupo `hermes`. |

A configuração fica no Nix: no NixOS, `hermes setup`, `hermes config set` e
`hermes gateway install` recusam mudar o que o módulo gerencia. Mude o `hermes.nix` num PR.

## Interfaces

Como as pessoas e as tarefas chegam ao Hermes, e onde cada parte é definida. A regra vale para
todas: a escolha fica no `hermes.nix`, e o token ou a lista de usuários permitidos fica no arquivo
de segredos na máquina (nunca aqui, e nunca um valor num PR).

| Interface | Como roda aqui | No `hermes.nix` | Na máquina (`hermes.env`) |
|---|---|---|---|
| Telegram | Modo polling, sem porta aberta. Responde só aos usuários permitidos. Reações (👀, ✅) trocam as mensagens de "ainda trabalhando". | `settings.telegram.reactions`; `HERMES_TELEGRAM_DISABLE_FALLBACK_IPS` (sem consultas DNS-over-HTTPS do Telegram por terceiros); mídia lida na RAM limitada a 20 MiB (`gateway.max_inbound_media_bytes`) | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` |
| Discord | Um bot no servidor do dono, que responde só ao usuário permitido. Sem voz: o pacote `full` não está instalado, então o aviso de Opus no log é esperado. | `DISCORD_MAX_ATTACHMENT_BYTES` em 20 MiB, o mesmo limite do Telegram | `DISCORD_BOT_TOKEN`, `DISCORD_ALLOWED_USERS` |
| Slack | Está no extra `messaging`; aqui só ficam os nomes das variáveis (veja "Configurar uma vez na máquina"). | nada | `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, `SLACK_ALLOWED_USERS` |
| Cron | O agendador do próprio Hermes, dentro do gateway: uma tarefa por vez, resultado no canal principal (`/sethome`, veja "Discord"), sem cabeçalho e rodapé. Datas em `America/Sao_Paulo`. | `settings.cron.max_parallel_jobs = 1`, `settings.cron.wrap_response = false`, `settings.timezone` | nada |
| CLI | `hermes` no PATH, sobre o estado do próprio serviço, para quem está no grupo `hermes` (`h0ffmann`). | `addToSystemPackages`, `users.users.h0ffmann.extraGroups` | nada |
| Servidores MCP | DeepWiki e Context7, remotos, sem chave; nada roda na máquina por eles. | `mcpServers`; `settings.mcp.auto_reload_on_config_change = false` | nada |

Sem a lista de usuários permitidos de uma plataforma, o gateway recusa todos nela. Sem o arquivo
de segredos, ele sobe sem plataforma e roda só as tarefas agendadas.

## Ajustes de execução

O que o `hermes.nix` define além do modelo e dos complementos, para 1 vCPU, 1 GB e a cota de uma
assinatura. A pesquisa de cada chave no commit fixado está em
[`AWESOME-HERMES.ptBR.md`](AWESOME-HERMES.ptBR.md).

| Ajuste | Valor | Por quê |
|---|---|---|
| `fallback_providers` (principal e `delegation`) | vazio | Só modelos Claude. Se a Anthropic falhar, o turno falha; ele nunca vai para outro provedor. |
| `model.default` | `claude-sonnet-5-5` | O Sonnet é o modelo de alto nível: planeja, escreve, revisa e decide. |
| `delegation.model`, `auxiliary.title_generation`, `auxiliary.skills_hub`, `auxiliary.goal_judge` | `claude-haiku-4-5` | O Haiku é o modelo de baixo nível: subagentes para leituras em paralelo e três tarefas laterais baratas (títulos, escolha de skill, o juiz do `/goal`). O Hermes não tem roteador por chamada: o Sonnet decide delegar, e o `hermes/SOUL.md` diz quando. Um subagente começa com um contexto novo em outro modelo, e o Sonnet confere a resposta. Por isso o Sonnet roda sozinho um grep, uma lista ou uma busca, e só delega três ou mais tarefas de leitura, ou a leitura de mais de uns 20 arquivos. A compressão, a aprovação de comandos perigosos e a revisão pós-turno ficam no Sonnet. |
| `delegation` | até 2 filhos, 50 iterações cada, um nível | Pouca ramificação, para uma vCPU e a cota. |
| `agent.max_turns`, `tool_loop_guardrails.hard_stop_enabled` | 60, ligado | Um limite por execução e uma parada firme em laços de ferramentas. |
| `goals.max_turns` | 6 (padrão 20) | O `/goal` é o loop Ralph do Hermes: ele continua uma tarefa sozinho até o juiz dizer que acabou. Cada turno pode usar até 60 chamadas ao modelo, então 6 turnos mantêm um objetivo dentro da cota; o `/goal resume` dá mais 6. |
| `prompt_caching.cache_ttl` | `auto` | 1 h no chat (as pessoas pausam), 5 min no cron e nos subagentes. |
| `mcp.auto_reload_on_config_change` | desligado | Mudar a configuração não recarrega os servidores MCP (o que derrubaria o cache do prompt); só um deploy muda a configuração. |
| `agent.agent_cache.max_size` | 16 | Menos agentes em cache, para poupar RAM. |
| `code_execution.max_session_kernels` | 1 | Um kernel de código por vez. |
| `sessions` | apaga com mais de 45 dias e depois faz vacuum no `state.db` | Disco. |
| `security.allow_lazy_installs` | desligado | O Nix cuida das dependências: sem `pip install` em tempo de execução. |
| `model_catalog.enabled`, `updates.check`, `telemetry.shared_metrics.enabled` | desligados | Sem catálogo de modelos baixado da Nous, sem checagem de atualização (o Nix cuida delas) e nada enviado à Nous. |

O Hermes não reinicia sozinho quando um deploy muda os arquivos dele: a ativação reescreve
`config.yaml`, `.env`, `SOUL.md`, `AGENTS.md` e os links dos plugins, mas a unit não muda. Por
isso o `hermes.nix` os lista como `reloadTriggers` do `hermes-agent` (as configurações, o
ambiente, os servidores MCP, as skills opcionais, os plugins e os dois documentos). Quando você
adicionar um novo tipo de entrada ao módulo, adicione-o ali também. Sem isso, um deploy deixa o
processo antigo rodando com a configuração antiga.

O reload é um reinício gracioso. O `ExecReload` manda um `SIGUSR1`; o gateway não aceita trabalho
novo, deixa terminar os turnos, os jobs de cron e os subagentes em andamento (no máximo
`agent.restart_after_turn_timeout`, 600 s aqui) e sai com o código 75. O systemd
(`Restart=always`) então o inicia com a configuração nova. Antes disso, um deploy parava a unit
com `SIGTERM` e cortava o turno em andamento, inclusive quando o merge era um PR do próprio
Hermes. Um pacote novo do Hermes muda o `ExecStart` da unit, e isso ainda a reinicia na hora.
Enquanto ele drena, uma mensagem nova espera o gateway voltar.

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

As skills do próprio dono ([h0ffmann/skills](https://github.com/h0ffmann/skills)) formam um
segundo diretório só de leitura em `skills.external_dirs`, fixado por commit. Cada uma vira um
comando no chat: veja [`HERMES-SKILLS.md`](HERMES-SKILLS.md) (em inglês) para a lista, o que ficou
de fora e por quê, e por que não é um submódulo do git.

## Complementos da comunidade

Escolhidos da [awesome-hermes-agent](https://github.com/0xNyk/awesome-hermes-agent) e do catálogo de
plugins da Nous (`plugin-catalog/` no commit fixado do hermes-agent) em 2026-11-03. Cada um foi lido antes de ser fixado (licença, último commit, cada ponto de entrada, e o que ele roda,
lê e envia), e está fixado por commit no `hermes.nix`:

| Complemento | Tipo | Para quê |
|---|---|---|
| [custom-dangerous-patterns](https://github.com/scross01/hermes-custom-dangerous-patterns-plugin) v0.5.2 (MIT) | plugin | Bloqueia comandos de terminal que batem com o `hermes/dangerous-patterns.yaml`: escrita no GitHub (`git push`, `gh pr merge`, `gh api -X POST` e os outros), leitura de segredos, `sudo` e rebuilds, e instalações ou `curl \| sh`. A lista fica na store, então o agente não consegue editá-la. |
| [evidence-ledger-research](https://github.com/markoblogo/abvx-agent-skills) (MIT) | skill | Disciplina de fonte, data, unidade e célula de tabela quando ele tira números de boletins, PDFs e artigos. |
| [tripwire](https://github.com/percyhendrux123-prog/hermes-tripwire) v0.1.1 (MIT) | plugin | Grava uma linha JSON para cada ação recusada (uma ferramenta bloqueada pela lista de bloqueio ou por outro hook, ou uma aprovação negada, cancelada ou expirada) em `/var/lib/hermes/.hermes/tripwire/events.jsonl`. Ele não guarda argumentos, resultados nem texto de mensagem, e não acessa a rede. Um arquivo `~/.hermes/tripwire/TEST_BLOCK` com `default <ferramenta>` bloqueia essa ferramenta, para testar um alerta; apague o arquivo para parar. |
| [inbox](https://github.com/NousResearch/hermes-labs-plugins/tree/main/inbox) (MIT, Nous Research Labs) | plugin | `hermes inbox` (e `--json`): uma lista só de leitura dos jobs do cron que falharam ou estão pausados, dos subagentes parados, dos processos órfãos, do trabalho em andamento e das próximas execuções do cron. Só um comando de CLI: nenhuma ferramenta e nenhum hook no chat. |
| [telegram-business](https://github.com/NousResearch/hermes-labs-plugins/tree/main/telegram-business) (MIT, Nous Research Labs) | plugin | Escreve rascunhos de resposta aos clientes de uma conta Telegram Business e só envia quando o dono toca em Send; `/biz` no Telegram. Não faz nada até uma conta Business (Telegram Premium) conectar o bot. Os rascunhos vão para o Sonnet. |
| [workflow-record](https://github.com/NousResearch/hermes-labs-plugins/tree/main/workflow-record) (MIT, Nous Research Labs) | plugin | `hermes record` grava um fluxo no navegador por CDP, e a skill dele deixa o `/learn` transformar a gravação em skill. Aqui não faz nada: a máquina não roda navegador. |
| [github-copilot](https://github.com/NousResearch/hermes-labs-plugins/tree/main/github-copilot) (MIT, Nous Research Labs) | plugin | O GitHub Copilot como provedor de modelo. Aqui não faz nada: o modelo e os fallbacks só citam a Anthropic, e ele só chama o GitHub num perfil que escolheu o Copilot. |
| [error-ledger, aux-ledger, approval-ledger, stop-ledger](https://github.com/olric3015/hermes-plugins) (MIT) | plugins | Registros locais, lidos no chat: `/errors` (chamadas à Anthropic que falharam, por causa), `/aux` (tokens das tarefas laterais do Haiku), `/approval-log` (quantas vezes cada regra da lista de bloqueio perguntou, e as respostas), `/stop-log` (turnos parados com `/stop` ou `/new`). Só metadados, nenhum texto de prompt, sem rede; cada arquivo é aparado depois de 2 MB. |
| [progress-squash](https://github.com/pierrenode/hermes-progress-squash) (MIT) | plugin | Reduz a uma linha os redesenhos de uma barra de progresso na saída do terminal antes de o modelo lê-la. Sem rede, sem arquivos. |
| [public-holidays](https://github.com/Akloenx123/hermes-public-holidays) (MIT) | plugin | Feriados e contas de dias úteis (inclusive do Brasil e dos estados), calculados em código, para os resumos do cron e os prazos. GET em `date.nager.at` com um código de país e um ano, sem chave. |
| [gh-ref, wiki-ref](https://github.com/EloquentBrush0x/hermes-context-refs) (MIT) | plugins | `@gh:dono/repo#N` anexa uma issue ou um pull request público (GET anônimo em `api.github.com`); `@wiki:<título>` anexa uma seção da Wikipédia. Sem token, sem arquivos. |
| [hermes-cron](https://github.com/itpartypattaya/hermes-cron) v1.5.2 (MIT) | skill | Regras para os jobs do cron: pausar, desativar ou remover; e `no_agent`, a checagem prévia `wakeAgent` e `[SILENT]`, para que um tick sem novidade não chame o modelo. O script de diagnóstico dela, só de leitura, pede `python3`, que não está no `PATH` do Hermes aqui; as regras funcionam sem ele. |

Limites tirados dos playbooks da lista: `agent.max_turns = 60`; no máximo 2 subagentes ao mesmo
tempo, com 50 iterações cada e um nível só; `tool_loop_guardrails.hard_stop_enabled`; sem checagem de
atualização (quem atualiza é o Nix) e sem métricas compartilhadas.

Ficaram de fora, com o motivo: cronalytics (pede um diretório de plugin com escrita), rtk-hermes (a
ordem do hook dele com a lista de bloqueio não foi testada), agentburn (a skill roda `uvx`, um
download sem versão fixa), hermes-lcm e os provedores de memória (pesados demais para 1 GB, ou pedem
um servidor ou uma nuvem), e tudo que pede Node, API paga ou painel web, ou não tem licença. Nada na
lista cobre alertas brasileiros, balneabilidade ou ciência do mar: essas são skills próprias do
piabrota, ainda por escrever.

## Os plugins do dono

`pirsig-notes` e `pirsig-videos`, em `hermes/plugins/`, mandam smart notes e leituras de vídeo para
o piabrota/pirsig como pull requests em branches `hermes/*`. Eles precisam do yt-dlp
(`yt-dlp-light`) e do GitHub App abaixo. Veja [HERMES-PLUGINS.md](HERMES-PLUGINS.md) (em inglês).

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

## Escrita no GitHub

Quando o dono pede, o Hermes clona um repositório, trabalha num branch `hermes/*`, dá push nele e
abre um pull request, como **piabrota-hermes[bot]**, o GitHub App dele. Ele nunca faz merge: quem
faz é o dono. O `hermes-github.nix` guarda a chave do App só para o root e entrega ao Hermes tokens
de uma hora.

1. **Crie o App** (uma vez): github.com/organizations/piabrota/settings/apps → **New GitHub App**.
   Nome `piabrota-hermes`, qualquer homepage (piabrota.art), **Webhook** desligado. Permissões de
   repositório: **Contents** leitura e escrita, **Pull requests** leitura e escrita, **Issues**
   leitura e escrita, Metadata leitura; mais nada (sem Workflows, sem Administration). Onde pode ser
   instalado: **Any account**, para entrar também no marola-dev e no h0ffmann.
2. **Gere uma chave privada** na página do App (baixa um `.pem`), e anote o **App ID**.
3. **Instale** (página do App → **Install App**) no piabrota, no marola-dev e no h0ffmann, em todos
   os repositórios ou só nos que o Hermes pode mexer.
4. **Proteja os branches padrão**: em cada organização, Settings → Rules → Rulesets → **New branch
   ruleset**, alvo o branch padrão, **Restrict deletions**, **Block force pushes**, **Require a
   pull request before merging**, sem exceção para o App. Assim o GitHub recusa um push na `main`
   mesmo se a lista de bloqueio deixar passar algum.
5. **Ponha a chave na máquina** (no seu computador, depois na VPS):

   ```console
   base64 < piabrota-hermes.*.private-key.pem | tr -d '\n'   # no seu computador: copie a saída
   sudo install -m 600 /dev/stdin /var/lib/hermes-secrets/github-app.env   # na VPS, e cole:
   GH_APP_ID=<o App ID>
   GH_APP_PRIVATE_KEY_B64=<a linha em base64>
   ```

   Termine com Ctrl-D, depois rode `sudo systemctl start hermes-github-token` e
   `journalctl -u hermes-github-token` (uma linha por conta: "token for one hour"). Apague o `.pem`
   do seu computador quando funcionar; dá para gerar outro quando quiser.

Depois peça no Telegram ou no Discord: "abre um PR em piabrota/nix-os que …". O Hermes responde com
o link. Se você tinha posto um `GITHUB_TOKEN` só de leitura, tire-o do `hermes.env`: o App substitui
esse token.

## Conferir

```console
systemctl status hermes-agent
journalctl -u hermes-agent -n 100
hermes status
hermes doctor
```

O log diz quais plataformas conectaram; "No messaging platforms enabled" quer dizer que o `.env`
não tem token de plataforma. Dois avisos são esperados: o "Opus codec not found" do adaptador do
Discord (a voz ficou de fora) e o do plugin da lista de bloqueio, que diz não poder gravar o hash
de integridade ao lado de um arquivo da store (a lista é somente leitura de propósito). Para ver
se um deploy valeu, compare `systemctl show hermes-agent -p ActiveEnterTimestamp` com a hora do
deploy: a unit reinicia quando suas entradas mudam, depois que o trabalho em andamento termina
(veja "Ajustes de execução"), então a hora pode vir até 10 minutos depois do deploy.

## A página /hermes

A página [www.piabrota.art/hermes](https://www.piabrota.art/hermes) mostra esta configuração em
YAML simples, não em Nix. Ela mostra as opções que o `hermes.nix` grava no `config.yaml` e como a
unit roda: o pacote, os extras, os limites, os plugins, os arquivos e o commit fixado do upstream. O
build do site lê esses dados do sistema avaliado (`site/hermes.nix`). Por isso a página muda a cada
merge que muda o `hermes.nix`. A página mostra a configuração que o último deploy da `main` aplica.
Ela não confere a unit ao vivo: para isso, veja "Conferir".

Nenhum segredo chega à página. O site nunca lê os arquivos de ambiente e não cita o nome deles. Uma
chave que cita token, chave, segredo, senha ou usuários permitidos sai antes do build, e o build
para se o nome de um segredo passar. Os caminhos da store mantêm o nome e perdem o hash.

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
- Visto rodando na máquina em 2026-11-03: a unit ativa, `MemoryMax` de 1 GiB, `CPUWeight` 50 e
  cerca de 350 MiB em uso numa leitura, com o Telegram conectado em modo polling. Uma leitura não
  é um pico: o uso sob carga e o tamanho do closure na VPS não foram medidos.
