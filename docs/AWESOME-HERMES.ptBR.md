# Awesome Hermes, para o piabrota

[English](AWESOME-HERMES.md)

Uma lista curada do que existe para o [Hermes Agent](https://github.com/NousResearch/hermes-agent) e
do que esta máquina faz com isso. Não é uma cópia das listas maiores: cada item foi julgado contra
uma máquina pequena, em produção, e contra os objetivos do dono, e diz por que entrou, por que vale
testar ou por que ficou de fora. Como o Hermes roda aqui está no [`HERMES.ptBR.md`](HERMES.ptBR.md).

**A régua.** Uma Hostinger KVM 1 (1 vCPU, 4 GB de RAM, o Hermes limitado a 1 GB), NixOS com tudo
declarado no `hermes.nix`, o Claude Sonnet pela assinatura do dono e nenhum outro provedor, o
Telegram e o Discord como chats, um token do GitHub só de leitura. Fica de fora: o que pede Node, Go,
Docker ou navegador na máquina, uma API paga ou um painel web, o que manda dados para fora, e o que
não tem licença OSI. Os objetivos que ela serve: o [marola](https://marola.dev) (balneabilidade e
segurança na praia no Brasil), o [piabrota/alerts](https://github.com/piabrota/alerts) (alertas de
órgãos oficiais), a pesquisa do mar e de modelos de onda, os repositórios FOSS do piabrota, e gastar
pouco da assinatura.

**Legenda.** ✅ em uso aqui · 🧪 vale um teste · ⛔ fora, com o motivo.

**Como foi conferido.** Lido em 2026-11-02 e 2026-11-03 contra o Hermes no commit que o
`flake.lock` fixa (`d9f15af`, v0.22.x): cada configuração abaixo existe no
`hermes_cli/config_defaults.py` desse commit. O código de terceiros foi lido, nunca rodado. Estrelas
e datas são daquele dia; elas mudam.

## Conteúdo

- [Oficial](#oficial)
- [Embutido, em uso aqui](#embutido-em-uso-aqui)
- [Configurações](#configurações)
- [Complementos da comunidade](#complementos-da-comunidade)
- [Guias e posts](#guias-e-posts)
- [Outras listas](#outras-listas)
- [Lacunas: o que o piabrota tem que escrever](#lacunas-o-que-o-piabrota-tem-que-escrever)

## Oficial

- ✅ [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent): o agente, o flake e
  o módulo NixOS (`nixosModules.default`), que aqui é o input `hermes-agent`. Lá, o Nix é
  plataforma Tier 2: melhor esforço.
- ✅ [Nix & NixOS setup](https://hermes-agent.nousresearch.com/docs/getting-started/nix-setup): as
  opções do módulo; foi assim que o `hermes.nix` foi escrito.
- ✅ Os guias que vêm no repositório (`website/docs/guides/`): `automate-with-cron.md`,
  `cron-script-only.md`, `tips.md`; e `user-guide/features/heartbeat.md`. Mais atuais que qualquer
  post de blog.
- [Releases](https://github.com/NousResearch/hermes-agent/releases): o registro das mudanças (da
  v0.22.1 à v0.22.6, de 2026-10-14 a 2026-11-02). O blog da Nous Research não teve post sobre o
  Hermes em 2026.

## Embutido, em uso aqui

- ✅ **Gateway no Telegram** (por polling) **e no Discord**, com um usuário permitido em cada.
- ✅ **Agendador de cron**, com os resultados no canal principal do Telegram.
- ✅ **Memória embutida** (`MEMORY.md`, `USER.md`), sem provedor externo.
- ✅ **Skills que vêm no pacote**: `github`, `arxiv`, `grounded-citations`, `obsidian`,
  `weekly-review-planning`, `document-to-action-items`, `codebase-inspection` e as outras.
- ✅ **Skills opcionais** (o `optional-skills/` do commit fixado, copiado para a store): `watchers`,
  `rss-feeds`, `research-paper-writing`, `ast-grep`. A busca do DuckDuckGo é um provedor de web desde a v0.23.0.
- ✅ **Servidores MCP** do catálogo aprovado (`optional-mcps/`), remotos, sem chave:
  [DeepWiki](https://mcp.deepwiki.com) e [Context7](https://context7.com).
- ✅ **Identidade e resumo**: `hermes/SOUL.md` (regras do dogma do piabrota) e `hermes/AGENTS.md`.
- 🧪 **A2A** (`plugins/platforms/a2a`, protocolo v1.0, só biblioteca padrão): o Hermes como par de
  um agente de código. Sem token, ele escuta só em 127.0.0.1; chegue por um túnel SSH, nunca por uma
  porta aberta. Falta decidir onde roda o agente de código.
- 🧪 **`/usage`** lê as janelas de 5 horas e da semana da assinatura, e o `hermes insights --days 7`
  mostra o uso ao longo do tempo: o painel de custo, sem um de terceiros.
- ⛔ **Mixture of agents**: pede outros provedores. **Kanban** e **perfis**: uma pessoa, um perfil.
  **Checkpoints**: para programar na máquina, o que esta máquina não faz. **Monitoramento OTLP**:
  pede um coletor. **Voz, geração de imagem e de vídeo**: pesados, e APIs pagas.

## Configurações

Cada uma está no `hermes.nix`, com o motivo do lado.

| Configuração | Aqui | Padrão | Por quê |
|---|---|---|---|
| `model.provider`, `model.default` | `anthropic`, `claude-sonnet-5-5` | | Sonnet pela assinatura |
| `fallback_providers`, `delegation.fallback_providers` | `[ ]` | | Só Claude: nenhum outro provedor, nunca |
| `delegation.model`, `auxiliary.title_generation.model`, `auxiliary.skills_hub.model`, `auxiliary.goal_judge.model` | `claude-haiku-5-5` | | Haiku para subagentes e três tarefas laterais baratas; Sonnet para o resto |
| `delegation.max_concurrent_children`, `max_iterations`, `max_spawn_depth` | 2, 50, 1 | 10, 250, 1 | Poucos subagentes, para uma vCPU e a cota |
| `agent.max_turns` | 60 | sem limite | Uma execução não fica em loop para sempre |
| `goals.max_turns` | 6 | 20 | Um `/goal` (o loop Ralph) para depois de 6 turnos, até o `/goal resume` |
| `tool_loop_guardrails.hard_stop_enabled` | true | false | Para um loop de ferramenta também no chat |
| `prompt_caching.cache_ttl` | `auto` | `5m` | Cache de 1 h para o chat e de 5 min para o cron: o Hermes mede cerca de 42 % menos custo de escrita de cache quando uma conversa volta depois de uma pausa |
| `mcp.auto_reload_on_config_change` | false | true | Recarregar derruba o cache do prompt; aqui só um deploy muda a configuração |
| `agent.agent_cache.max_size` | 16 | 128 | Cada agente em cache guarda uma conversa na RAM |
| `cron.max_parallel_jobs` | 1 | sem limite | Dois resumos ao mesmo tempo podem bater no teto de 1 GB |
| `code_execution.max_session_kernels` | 1 | 4 | RAM |
| `gateway.max_inbound_media_bytes` | 20 MiB | 128 MiB | A mídia é lida inteira para a RAM |
| `sessions.auto_prune`, `retention_days` | true, 45 | false, 90 | As sessões do gateway nunca reiniciam; o `state.db` só cresceria |
| `security.allow_lazy_installs` | false | true | Nada de pip install em execução: quem cuida das dependências é o Nix |
| `model_catalog.enabled` | false | true | Nada de buscar o catálogo na Nous a cada 20 minutos |
| `HERMES_TELEGRAM_DISABLE_FALLBACK_IPS` | true | vazio | Nada de consultar o Telegram por DNS-over-HTTPS no Google e na Cloudflare |
| `telegram.reactions` | true | false | 👀 e ✅ no lugar de mensagens de "ainda trabalhando", sem tokens |
| `cron.wrap_response` | false | true | Resultados do cron sem cabeçalho e rodapé |
| `updates.check`, `telemetry.shared_metrics.enabled` | false, false | true, false | Quem atualiza é o Nix; nada vai para a Nous |
| `timezone` | `America/Sao_Paulo` | hora do servidor | Os jobs na hora do dono |

🧪 Para testar antes de adotar:

- **`platform_toolsets.telegram`**: o pacote padrão oferece navegador, imagem, TTS e visão, que a
  máquina não usa, e os schemas deles custam tokens a cada chamada. Corte para o que é usado;
  confira os nomes com `hermes tools` antes.
- **Opções do cron por job** (`automate-with-cron.md`): `enabled_toolsets` por job, esforço de
  raciocínio baixo para os jobs baratos, `--continuity` para um watcher não repetir o que já disse,
  e um script que imprime `{"wakeAgent": false}` (ou `no_agent`), para um tick sem novidade não
  chamar o modelo.
- **`memory.nudge_interval`, `skills.creation_nudge_interval`** de 10 para 20 ou 30: a revisão
  depois de um turno repassa a conversa, na cota.
- **`compression.proactive_prune_tokens`** perto de 48 000: corta saída antiga de ferramenta sem
  chamar o modelo, mas quebra o cache uma vez a cada corte; meça antes.
- **`compression.idle_compact_after_seconds`** perto de 3 600, e
  **`gateway.message_timestamps.enabled`** para os resumos.
- **`memory.write_approval`, `skills.write_approval`**: põem em espera o que o Hermes escreve na
  memória e nas skills, para `/memory pending` e `/skills pending`. Uma decisão de confiança do dono.
- ⛔ **`compression.micro_compact`**: quebra o cache do prompt a cada turno. ⛔
  **`curator.consolidate`**: chama o modelo; a poda determinística padrão basta.

## Complementos da comunidade

Da [awesome-hermes-agent](https://github.com/0xNyk/awesome-hermes-agent), de uma busca no GitHub e
do catálogo de plugins da própria Nous: `plugin-catalog/` no commit fixado do hermes-agent, 912
entradas, cada uma com merge de um mantenedor, fixada num commit completo e examinada na admissão
(o `README.md` dele traz as regras). Ao fixar um plugin de lá, prefira o commit do catálogo.

- ✅ [percyhendrux123-prog/hermes-tripwire](https://github.com/percyhendrux123-prog/hermes-tripwire)
  (MIT, v0.1.1, no catálogo): uma linha JSON para cada ação recusada, inclusive os bloqueios da
  lista. Sem rede, sem guardar argumentos nem texto.
- ✅ [NousResearch/hermes-labs-plugins](https://github.com/NousResearch/hermes-labs-plugins) (MIT,
  no catálogo), os quatro, cada um no commit do catálogo, por escolha do dono: `inbox` (`hermes
  inbox`, uma lista só de leitura dos jobs do cron que falharam e dos subagentes parados),
  `telegram-business` (rascunhos de resposta para uma conta Telegram Business; inerte sem ela),
  `workflow-record` (grava um fluxo no navegador; inerte, sem navegador aqui) e `github-copilot` (um
  provedor de modelo; inerte, só Anthropic).
- ✅ [itpartypattaya/hermes-cron](https://github.com/itpartypattaya/hermes-cron) (MIT, v1.5.2, no
  catálogo): uma skill para jobs baratos do cron (`no_agent`, `wakeAgent`, `[SILENT]`). O script de
  diagnóstico dela pede `python3`, que o `PATH` do Hermes não tem aqui.
- ✅ Do catálogo, cada um no commit do catálogo (MIT, só Python, sem chamada ao modelo): os registros
  [error-ledger, aux-ledger, approval-ledger e stop-ledger](https://github.com/olric3015/hermes-plugins)
  (`/errors`, `/aux`, `/approval-log`, `/stop-log`, só metadados),
  [progress-squash](https://github.com/pierrenode/hermes-progress-squash) (uma linha por barra de
  progresso), [public-holidays](https://github.com/Akloenx123/hermes-public-holidays) (feriados do
  Brasil e contas de dias úteis, do `date.nager.at`) e as referências de contexto
  [gh-ref e wiki-ref](https://github.com/EloquentBrush0x/hermes-context-refs).
- 🧪 Para depois, do catálogo: [hermes-session-reset-policy](https://github.com/fastfinge/hermes-session-reset-policy)
  (uma sessão nova do gateway depois de um tempo parado ou a cada dia, para o contexto ficar curto;
  uma escolha sobre a memória da conversa), [reaction-feedback](https://github.com/AhmetArif0/hermes-reaction-feedback)
  (o Hermes vê seus 👍 e 👎 no Telegram; só Telegram), telegram_dashboard_probe (a mensagem de status
  fixada acima), osv-ref (registros `@cve:`, se o Hermes passar a triar CVEs do `cves.yml`) e
  openalex (artigos e citações; pede uma chave grátis do OpenAlex no arquivo de ambiente).
- 🧪 [mister-ideas/usage-guard](https://github.com/mister-ideas/usage-guard) (MIT, no catálogo):
  recusa uma chamada ao modelo quando uma janela da assinatura está cheia, para não gastar excedente.
  Esperar: no commit fixado, o `agent/account_usage.py` multiplica por 100 um `utilization` da
  Anthropic de 1 ou menos, então o guard bloquearia logo depois de cada reset (o README dele aponta a
  correção upstream).
- 🧪 [otsoa-dubief/airlock](https://github.com/otsoa-dubief/airlock) (Apache-2.0, no catálogo):
  depois que uma sessão lê conteúdo não confiável, envios, pushes e escritas de memória, skill e
  cron passam por aprovação. Ele bloqueia escritas do cron sem ninguém por perto, então comece no
  modo de observação.
- ⛔ Do catálogo: context-audit (sem arquivo de licença), turn-usage (o rodapé dele volta ao modelo
  a cada turno), llmslim (numpy e scikit-learn do PyPI), tameru (sobrescreve métodos privados do
  Hermes), discord-tps, session-mirror e hermes-discord-rpc (presença do bot ou o app de desktop),
  redaction-pack (fornecedores que esta máquina não usa).

- ✅ [scross01/hermes-custom-dangerous-patterns-plugin](https://github.com/scross01/hermes-custom-dangerous-patterns-plugin)
  (MIT, v0.5.2): um hook `pre_tool_call` que bloqueia comandos de terminal por regex. Aqui ele
  aplica o `hermes/dangerous-patterns.yaml`: nada de escrita no GitHub, de segredos, de `sudo` ou
  de instalações. Sem rede, sem subprocess.
- ✅ [markoblogo/abvx-agent-skills](https://github.com/markoblogo/abvx-agent-skills), a skill
  `evidence-ledger-research` (MIT, só markdown): disciplina de fonte, data, unidade e célula de
  tabela para números tirados de boletins, PDFs e artigos.
- 🧪 [bablobanov/hermes-agent-telegram-dashboard](https://github.com/bablobanov/hermes-agent-telegram-dashboard)
  (MIT, 7 ★): uma mensagem de status fixada no Telegram, editada no lugar, sem chamar o modelo;
  está no catálogo de plugins do commit fixado. Uma visão barata da saúde da VPS. Ler o código
  antes de fixar.
- 🧪 [8bit64k/cronalytics](https://github.com/8bit64k/cronalytics) (MIT, 115 ★): custo, falhas e
  desvio por job do cron, sem rede. Pede um diretório de plugin com escrita e um ajuste de caminho.
- 🧪 [ogallotti/rtk-hermes](https://github.com/ogallotti/rtk-hermes) (MIT, 302 ★, o exemplo do
  próprio módulo): comprime a saída do terminal antes de ela chegar ao modelo, com o `pkgs.rtk`.
  Testar antes a ordem do hook dele com a lista de bloqueio.
- 🧪 [Socialpranker/agentburn](https://github.com/Socialpranker/agentburn) (MIT, 113 ★): qual janela
  de 5 horas gastou a cota. Rodar num notebook, com logs copiados; a skill chama `uvx`, um download
  sem versão fixa.
- 🧪 [kenpritchard/hermes-delegation-gate](https://github.com/kenpritchard/hermes-delegation-gate)
  (MIT, 99 linhas): pede `/approve` antes de abrir subagentes. Com ele, os jobs do cron falham
  fechados.
- ✅ Onda 1 da [#88](https://github.com/piabrota/nix-os/issues/88), no piabrota2, cada um no commit do
  catálogo (MIT): [hermes-plugin-guard](https://github.com/mauricemohr88-debug/hermes-plugin-guard)
  (`hermes plugin-guard scan`, o portão estático do próximo plugin; só o `src/`),
  [memory-rewind](https://github.com/AhmetArif0/hermes-memory-rewind) (um histórico git da memória,
  do `SOUL.md` e das skills, com restauração) e [hermes-guide](https://github.com/iap/hermes-guide)
  (`/hermes-doctor`, checagens só de leitura; um `git ls-remote` por execução).
- 🧪 [bubblewrap](https://github.com/NousResearch/hermes-official-plugins/tree/main/bubblewrap)
  (oficial): um sandbox `bwrap` por comando. Ainda não: ele esconde o `~/.config/gh`, onde fica o
  token do gh, e o limite de 256 MB de espaço de endereçamento derruba o omp. Precisa de um ensaio
  no piabrota2.
- 🧪 Só no CI: [hermes-labs-ai/lintlang](https://github.com/hermes-labs-ai/lintlang)
  (Apache-2.0) faz lint do `SOUL.md`, do `AGENTS.md` e das skills.
- ⛔ Pesados demais para 1 GB, ou pedem servidor ou nuvem: [hermes-lcm](https://github.com/stephenschoettler/hermes-lcm)
  (troca o motor de contexto e faz chamadas extras de resumo), e os provedores de memória
  (hindsight, mem0, honcho, supermemory, Mnemosyne).
- ⛔ Inseguros ou que mudam a si mesmos: tree-ring-memory (baixa o próprio binário e se atualiza),
  curator-evolver (reescreve skills sozinho), oh-my-hermes (entra em toda chamada, e o fluxo dele
  faz commit), hermes-backup-recovery (empacota o home inteiro, com os segredos: faça backup pelo
  NixOS).
- ⛔ Outra plataforma ou pegam credencial: cronwatch (Feishu, lê o `.env`), cron-status-alert
  (Discord), telegram-checklist (uma sessão de usuário do Telethon; a versão da Bot API pede uma
  conta business).
- ⛔ Node ou painel web: [garrytan/gbrain](https://github.com/garrytan/gbrain), hermes-hud,
  hermes-ai-usage, agent-analytics. APIs pagas: web-search-plus, Consensus, Extracto (manda URLs
  para o r.jina.ai). Sem licença: [NousResearch/hermes-agent-self-evolution](https://github.com/NousResearch/hermes-agent-self-evolution),
  hermes-weather-plugin.
- ⛔ Já coberto: [Iampattanayak/hermes-nixos](https://github.com/Iampattanayak/hermes-nixos) (o
  módulo oficial faz isso), asimons81/hermes-a2a-bridge (arquivado; o A2A já vem embutido).

## Guias e posts

- Holme Bengt, ["Why your Hermes feels slow and costs too much"](https://buttondown.com/HolmeBengt),
  2026-08-02: os jobs do cron carregam todas as ferramentas por padrão, então dê a cada um as suas;
  um limite menor de memória. Os números de custo são de uma pessoa só.
- O megathread do r/hermesagent (junho de 2026): o custo fixo do prompt, e quanto cortar ferramentas
  economiza. Não conferido aqui.
- runtimewire.com sobre a v0.20.0 (voz e A2A): contexto.

## Outras listas

- [0xNyk/awesome-hermes-agent](https://github.com/0xNyk/awesome-hermes-agent) (cerca de 5,9 mil ★):
  o diretório grande de onde esta lista partiu. A seção "Check the trust boundary" vale a leitura.
- [0xarkstar/awesome-hermes-agent](https://github.com/0xarkstar/awesome-hermes-agent),
  [frankxai/awesome-hermes-agents](https://github.com/frankxai/awesome-hermes-agents) e
  [frankxai/awesome-hermes-agent-skills](https://github.com/frankxai/awesome-hermes-agent-skills)
  (um filtro de segurança para skills), e listas em chinês:
  [jefferyjob/awesome-hermes-agent-zh](https://github.com/jefferyjob/awesome-hermes-agent-zh).

## Lacunas: o que o piabrota tem que escrever

Nada do que foi achado cobre o Brasil ou o mar. Estas são skills próprias do piabrota, por
escrever, em cima do `watchers` e do `evidence-ledger-research`, com os endpoints tirados de código
que já os consulta:

- **Balneabilidade** da FEPAM (RS), do IMA (SC), do IAT (PR), do INEA (RJ) e do INEMA (BA), para o
  marola: veja o [astrbot_dw_ext_br_south_waterq](https://github.com/h0ffmann/astrbot_dw_ext_br_south_waterq).
- **Alertas oficiais** do CEMADEN, da Defesa Civil e do INMET, em CAP 1.2, para o piabrota/alerts.
- **Pesquisa do mar**: releases do WAVEWATCH III e as categorias do arXiv sobre modelos de onda.
- **O gramatico como skill**: português do Brasil que se lê uma vez só, em toda resposta em pt-BR.
