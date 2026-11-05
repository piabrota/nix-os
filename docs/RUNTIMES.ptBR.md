# Runtimes do OpenRig: o que um seat pode rodar

[English](RUNTIMES.md)

Runtime é o programa que um seat roda. O campo `runtime:` do membro, na spec de uma rig, o nomeia.
O OpenRig traz seis embutidos (como lidos na v0.7.7): `claude-code`, `codex`, `pi`, `omp`, `terminal` e `stub`. Ele
também carrega harnesses da comunidade, que a spec nomeia como `runtime: <nome>`. Esta página os
compara e diz quais esta máquina roda. O resto da instalação do OpenRig está em
[`OPENRIG.md`](OPENRIG.md).

**Como ler.** Cada afirmação sobre um runtime vem dos documentos do OpenRig na tag
[v0.7.7](https://github.com/mvschwarz/openrig/tree/v0.7.7), nomeados no texto, ou deste
repositório. "Só docs" quer dizer que li e não rodei aqui. `⚠` marca um fato que não consegui
conferir. Nada aqui diz que um seat fez uma tarefa: nenhum fez.

Créditos. O [OpenRig](https://github.com/mvschwarz/openrig) é de mvschwarz (Apache-2.0).
O [Pi](https://pi.dev) ([badlogic/pi-mono](https://github.com/badlogic/pi-mono)) é de Mario Zechner.
O [oh-my-pi](https://github.com/can1357/oh-my-pi) (`omp`, de can1357) é um fork do Pi. O Claude Code
é da Anthropic, e o Codex é da OpenAI.

## Num relance

|Runtime|O que é|Rota do modelo|Arquivo de guidance|Nesta máquina|
|---|---|---|---|---|
|`claude-code`|O Claude Code da Anthropic num painel tmux|Login do Claude, `CLAUDE_CODE_OAUTH_TOKEN` ou `ANTHROPIC_API_KEY`|`CLAUDE.md`|A rig de port, depois deste PR e com `waveForecaster.enable` ligado. Precisa do `unfree.nix`|
|`codex`|O CLI Codex da OpenAI num painel tmux|Um login da OpenAI (`codex login`) ou uma chave|`AGENTS.md`|Não instalado|
|`pi`|O harness Pi, pelo runner RPC do OpenRig|Uma chave de OpenRouter, Z.ai, Kimi ou MiniMax, pelo prefixo do modelo|`AGENTS.md`|Não instalado. Nenhuma spec o usa|
|`omp`|O oh-my-pi, por um runner do mesmo tipo|Uma chave do provedor, pelo modelo `provedor/id`|`AGENTS.md`|Funciona. `piabrota-dev` e a rig de integração|
|`terminal`|Um shell comum, sem agente|Nenhuma|Nenhum|Funciona|
|`stub`|Um harness de teste com roteiro|Nenhuma|Não consta nos docs que li|Disponível. Nenhuma spec o usa|
|Harness da comunidade|Uma ferramenta de fora, um arquivo de preset|A que a ferramenta usar|Nenhum. Não é colocado|Nenhum instalado|

Como a política de permissão da rig chega a cada um (`permission_policy:` da rig ou do membro).
Fontes: [`rig-spec.md`](https://github.com/mvschwarz/openrig/blob/v0.7.7/docs/reference/rig-spec.md),
[`adapters-and-runtimes.md`](https://github.com/mvschwarz/openrig/blob/v0.7.7/docs/as-built/architecture/adapters-and-runtimes.md).
Só docs.

|Runtime|Piso (sem política, ou `builtin:locked`, `standard`, `open`)|`builtin:auto`|`builtin:yolo`|
|---|---|---|---|
|`claude-code`|`--permission-mode acceptEdits` e, para um seat sem política, uma lista curta de allow e ask em `--settings`|`--permission-mode auto`|`--dangerously-skip-permissions`|
|`codex`|`-s workspace-write`, ou `-p <perfil>`|O piso|`-s danger-full-access -a never`|
|`pi`|Não tem política de permissão. Confiança de recursos: `--no-approve`|O piso|`--approve`|
|`omp`|`--approval-mode always-ask`|⚠ O piso (os docs não dizem para o omp)|`--approval-mode yolo`|
|`terminal`|Nenhuma|Nenhuma|Nenhuma|
|`stub`|Levada ao runner como `--posture`, nada é imposto|Igual|Igual|
|Comunidade|Nenhuma: as aprovações ficam no painel da própria ferramenta|Igual|Igual|

Uma rig sem política recebe o piso, e uma política vence o `OPENRIG_YOLO=1` da unit. Por isso as
rigs desta máquina definem `permission_policy: builtin:yolo` (decisão do dono, PR 124).

## `claude-code`

**O que é.** O Claude Code, iniciado no painel do seat como
`claude <postura> --session-id <id> --name <nome> [--model <m>] [--effort <e>]`. Um resume usa
`--resume <token>`. Um fork exige o Claude Code 2.0.73 ou mais novo.

**Recursos.**
- A guidance vai num bloco gerenciado do `CLAUDE.md` na pasta do seat (ou no `CLAUDE.local.md`, com o
  `managed_blocks` da rig). Skills, subagentes, plugins e entradas MCP vão para `.claude/` e
  `.mcp.json`.
- A atividade vem dos hooks do próprio Claude e do arquivo de sessão dele, não só da tela.
- O membro pode definir `effort`, `advisor` (um segundo modelo) e `claude_token` (um arquivo de token
  do seat).
- Antes do primeiro turno o OpenRig marca a pasta como confiável e o onboarding como feito no
  arquivo de estado do Claude. Ele não escreve regras de permissão.
- Um seat pode ser retomado, bifurcado e passado adiante, com uma conferência de que a conversa
  retomou de verdade.

**Prós.** O runtime mais bem suportado do OpenRig. Usa a assinatura do Claude. Os modos de permissão
são nativos, e as configurações gerenciadas podem pôr regras que nada num repositório sobrescreve.

**Contras.**
- O Claude Code é unfree. Esta máquina o permite pelo nome (`unfree.nix`).
- É grande: a closure cresce cerca de 280 MiB, e o binário do fornecedor não está no `cache.nixos.org`.
- A primeira execução em modo bypass mostra um aviso que uma pessoa precisa aceitar uma vez.
- O Claude Code põe `ANTHROPIC_API_KEY` acima de `CLAUDE_CODE_OAUTH_TOKEN` (veja "Credenciais").
- O uso de memória dele não foi medido aqui.

**Spec.**

```yaml
- id: porter
  agent_ref: "local:../../agents/wf-porter"
  profile: default
  runtime: claude-code
  model: claude-sonnet-5-5   # um id completo de modelo do Claude, como no rig-spec.md
  cwd: /var/lib/openrig/work/wave-forecaster-dev/porter
```

**Credenciais.** O Claude guarda o login no config dir dele (`~/.claude`, ou o `CLAUDE_CONFIG_DIR` do
seat). Um token de assinatura vai em `CLAUDE_CODE_OAUTH_TOKEN`. O OpenRig lista os nomes que o Claude
Code põe acima desse token: uma chave de provedor de nuvem, `ANTHROPIC_AUTH_TOKEN` e
`ANTHROPIC_API_KEY`
([`claude-credential-precedence.ts`](https://github.com/mvschwarz/openrig/blob/v0.7.7/packages/daemon/src/domain/claude-credential-precedence.ts)).
Um nome só chega a um seat se o daemon o tem e o operador o nomeia em
`recovery.provider_auth_env_allowlist` ([`startup.ts`](https://github.com/mvschwarz/openrig/blob/v0.7.7/packages/daemon/src/startup.ts)).

**Estado.** `~/.claude` e `~/.claude.json` (aqui `HOME` é `/var/lib/openrig`) e
`<cwd>/.claude/settings.local.json`, onde o OpenRig põe seus hooks e o coletor da status line.

**Nesta máquina.** A rig de port `wave-forecaster-dev` (porter e auditor) o roda depois deste PR, e
só quando `piabrota.openrig.waveForecaster.enable` está ligado, o que não está. Os detalhes estão em
"Claude Code nesta máquina", abaixo. **Não rodou:** nenhum seat Claude de verdade.

## `codex`

**O que é.** O CLI Codex da OpenAI no painel do seat: `codex <postura> -C <cwd>`, com `-m <modelo>` e
`-c model_reasoning_effort=...` quando a spec os define. Só docs.

**Recursos.**
- A guidance vai no `AGENTS.md`, as skills em `.agents/skills/`, os plugins em `.codex/plugins/`.
- Resume e fork são nativos. Um lançamento nunca deixa o Codex se atualizar sozinho.
- No piso, o OpenRig pergunta a um `codex app-server` descartável se o acesso à rede no sandbox é
  permitido, e o liga quando é.
- A atividade vem dos hooks do Codex. Esse degrau está em teste na 0.7.7: precisa de 50 leituras
  concordantes antes de ser confiável ([`agent-state-taxonomy.md`](https://github.com/mvschwarz/openrig/blob/v0.7.7/docs/reference/agent-state-taxonomy.md)).

**Prós.** Um sandbox nativo (`workspace-write`) no piso. Uma segunda família de modelos ao lado do
Claude.

**Contras.** Precisa de um login ou chave da OpenAI e de um binário `codex`: nenhum dos dois está
nesta máquina. A postura de permissão dele não tem meio-termo: `builtin:auto` dá o piso.

**Spec.**

```yaml
- id: reviewer
  agent_ref: "local:agents/reviewer"
  profile: default
  runtime: codex
  model: gpt-5.5   # o id que o rig-spec.md usa num exemplo
```

**Credenciais.** `codex login`, ou `OPENAI_API_KEY` (um nome que a allowlist aceita). O login fica no
`CODEX_HOME` (padrão `~/.codex`).

**Estado.** `~/.codex`, ou o `CODEX_HOME` do próprio seat.

**Nesta máquina.** Não instalado. Não existe rota da assinatura do Claude para o Codex: o seat
precisaria de um login próprio da OpenAI, que o dono não deu.

## `pi`

**O que é.** O agente de código Pi, "a minimal, extensible agent harness" (pi.dev), iniciado como
`pi --mode rpc` dentro do runner do OpenRig. O runner lê o fluxo de eventos do Pi e informa ao daemon
cada limite de turno. Só docs.

**Recursos.**
- A atividade vem dos relatos do runner: trabalhando, ocioso, precisa de resposta. Um painel quieto
  nunca vale como ocioso sozinho.
- O esforço do seat vai ao Pi como `--thinking <nível>`.
- Modelos próprios: `models.json` na pasta agent do seat.
- Resume e fork funcionam. O token de resume é o arquivo de sessão do Pi.

**Prós.** Pequeno. Muitos provedores. Atividade precisa, vinda do runner.

**Contras.**
- Sem subagentes e sem modo de plano por padrão (pi.dev).
- Sem política de permissão: só confiança de recursos (`--approve` ou `--no-approve`).
- Um diálogo de extensão (`select`, `confirm`, `input`, `editor`) é cancelado, porque o painel não
  pode responder, e o seat passa a precisar de atenção.
- Aceita no máximo uma chave de provedor: `OPENROUTER_API_KEY`, `ZAI_API_KEY`, `KIMI_API_KEY` ou
  `MINIMAX_API_KEY`, escolhida pelo prefixo do modelo. Não há rota para um token de assinatura do
  Claude.

**Spec.**

```yaml
- id: helper
  agent_ref: "local:agents/helper"
  profile: default
  runtime: pi
  model: openrouter/<id-do-modelo>   # ou zai/<id>, kimi-coding/<id>, minimax/<id>
```

**Estado.** `$OPENRIG_HOME/state/pi/<sessão>/agent`, com `sessions/` ao lado. O OpenRig não copia
nada de `~/.pi/agent`.

**Nesta máquina.** Não instalado, e a unit não tem nenhuma das quatro chaves. Nenhuma spec o usa.

## `omp`

**O que é.** O [oh-my-pi](https://github.com/can1357/oh-my-pi), um fork do Pi. O OpenRig o roda por
um runner do mesmo tipo, como runtime separado (ele não usa o `--name` nem o `--approve` do Pi). O
README dele diz "60+ providers, 31 built-in tools, 14 LSP operations, 28 DAP operations"; não medi
isso.

**Recursos.**
- Os mesmos relatos do runner que no Pi.
- Um seat tem o próprio `HOME`: `$OPENRIG_HOME/state/omp/<seat>/agent`, com `sessions/`.
- O OpenRig não copia credenciais do omp. Provisione o seat, ou nomeie a variável de chave do
  provedor em `recovery.provider_auth_env_allowlist`.
- Um erro de modelo com status 408, 429, 500, 502, 503, 504 ou 529 volta a ocioso no fim do turno,
  então uma nova tentativa comum funciona.

**Prós.** Funciona aqui com o token da assinatura, pelo wrapper `omp/wrapper.nix`. Tem regras
próprias (`hermes/omp.yml`) que um repositório clonado não afrouxa. Uma execução usa cerca de
340 MiB (número em `hermes/omp.yml`).

**Contras.**
- Um seat só recebe uma chave se o modelo dele está escrito `provedor/id`. Um nome curto como `opus`
  não passa nenhuma.
- Um seat novo, sem turno concluído, não tem arquivo de sessão, então um restore o deixa esperando:
  inicie com `rig seat launch <seat> --fresh --reason "<por quê>"`.
- Depois de um restore completo, `rig seat clear-attention` não limpa um seat omp
  ([openrig#41](https://github.com/mvschwarz/openrig/issues/41)).
- Um seat omp desta máquina não projeta plugin nem recurso de runtime (`openrig/specs/agents/shared/agent.yaml`).

**Spec.**

```yaml
- id: builder
  agent_ref: "local:../../agents/builder"
  profile: default
  runtime: omp
  model: anthropic/claude-sonnet-5-5   # `anthropic/<id>`: a forma para a qual o runner passa a chave
  cwd: /var/lib/openrig/work
```

**Credenciais aqui.** A unit dá a todo seat a `ANTHROPIC_API_KEY`, que guarda o token da assinatura. O
wrapper a move para `ANTHROPIC_OAUTH_TOKEN` ([`OPENRIG.md`](OPENRIG.md), "The token of the seats").

**Nesta máquina.** Funciona. `piabrota-dev` e `wave-forecaster-dev-integrate` o usam. A rig de port
o usava até este PR.

## `terminal`

**O que é.** Um shell para um servidor, um tail de log ou um vigia de build. Não é um agente: todo
passo do adapter é um no-op, e o seat fica pronto na hora.

**Recursos.** `rig send` digita o texto exato, sem as linhas From e To. Um restore relança o seat do
zero e roda as ações de startup de novo.

**Prós.** Sem modelo, sem token, sem memória além do processo.

**Contras.** Sem guidance, sem skills, sem identidade. Um wake da fila não chega nele
(`failed:terminal-seat`).

**Spec.** Os três campos vão juntos, ou a spec é inválida.

```yaml
- id: logs
  agent_ref: "builtin:terminal"
  profile: none
  runtime: terminal
```

**Nesta máquina.** Funciona. Foi testado num daemon descartável.

## `stub`

**O que é.** Um harness de teste determinístico. Um runner Node no painel segue
`<cwd>/.openrig/stub/script.json` e não chama modelo. Passa pelo caminho normal de lançamento,
skills, startup e prontidão.

**Prós.** Testa o encanamento da rig sem gastar tokens.

**Contras.** Não tem canal de entrada, então nenhum teste prova que uma mensagem foi consumida. Não
faz fork. Ignora o comportamento nativo de permissão
([`test-layers.md`](https://github.com/mvschwarz/openrig/blob/v0.7.7/docs/as-built/test-layers.md),
"What a stub can and cannot prove").

**Spec.**

```yaml
- id: probe
  agent_ref: "local:agents/probe"
  profile: default
  runtime: stub
```

**Estado.** `<cwd>/.openrig/stub/`.

**Nesta máquina.** Disponível na 0.7.7. Nenhuma spec o usa, e não o rodei.

## Harnesses da comunidade

**O que é.** Uma ferramenta que um mantenedor de fora mantém, instalada como
`$OPENRIG_HOME/community-harnesses/<nome>.yaml`. O nome do preset é o runtime. O OpenRig digita o
`command` do preset no painel e não testa a ferramenta. Exemplos na 0.7.7: Hermes, OpenClaw, Cursor
e a TUI do próprio Pi
([`community-harness-presets.md`](https://github.com/mvschwarz/openrig/blob/v0.7.7/docs/reference/community-harness-presets.md)).

**Recursos.** Lançamento, entrega (`rig send` cola o texto e aperta Enter), transporte e, quando o
preset declara, identidade e resume. A atividade vem só da tela, ou dos relatos de um preset runner.

**Contras.** Nenhuma guidance, skill ou arquivo de startup é colocado. O modelo vem da configuração
da própria ferramenta, a menos que o preset defina `passes_model`. Sem aprovações, sem cancelar. Uma
tela que parece ociosa vale como `unknown`.

**Spec.** Um membro nomeia o preset como runtime. Os outros campos do membro são como em qualquer
seat de agente; não achei um exemplo de membro completo no documento dos presets, então dou só a
linha que muda.

```yaml
  runtime: example-harness   # o nome do preset; os nomes embutidos são reservados
```

**Nesta máquina.** Nenhum instalado. O `hermes-rig` manda não adicionar um (um seat Hermes é um
segundo runtime Python nos 2 GiB da unit).

## Qual escolher

|Você quer|Use|
|---|---|
|A assinatura do Claude e o máximo que o OpenRig consegue ver e controlar|`claude-code`. É unfree e grande, então aqui é opt-in|
|A assinatura do Claude sem pacote unfree, regras próprias e um runner|`omp` (o que esta máquina faz em `piabrota-dev` e na rig de integração)|
|Modelos da OpenAI e o sandbox nativo do Codex|`codex`, depois que existirem um login da OpenAI e um binário|
|Um harness pequeno e uma chave de OpenRouter, Z.ai, Kimi ou MiniMax|`pi`|
|Um servidor, um tail de log ou um vigia de build|`terminal`|
|Uma checagem do encanamento da rig sem tokens|`stub`|
|Uma ferramenta que o OpenRig não traz|Um harness da comunidade, sabendo que ele é lido pela tela e não recebe guidance|

Nesta máquina a escolha também é uma escolha de memória: o daemon e todos os seats dividem o
`MemoryMax=2G` da unit, dois seats por vez.

## Claude Code nesta máquina

Este PR dá à rig de port `runtime: claude-code` (porter e auditor, `model: claude-sonnet-5-5`).
`piabrota-dev` e `wave-forecaster-dev-integrate` continuam no omp. Tudo fica atrás de
`piabrota.openrig.waveForecaster.enable`, que continua desligado.

**O que a opção acrescenta para o Claude.**
- O `unfree.nix` permite `claude-code` pelo nome e mais nada. `allowUnfree` continua desligado. Um
  nome só entra ali com o sim do dono.
- Um comando `claude` no perfil do seat e no path da unit (`openrig.nix`, `seatClaude`): um wrapper
  do `pkgs.claude-code` com `choom`, como o do omp.
- `/etc/claude-code/managed-settings.json`, com `allowManagedPermissionRulesOnly` e regras deny.

**O problema da credencial, e a solução.** A unit dá a todo seat a `ANTHROPIC_API_KEY` (o token da
assinatura) para os seats omp. O Claude Code põe esse nome acima de `CLAUDE_CODE_OAUTH_TOKEN` e
mandaria o token como se fosse uma chave de API. A resposta do próprio OpenRig, o `claude_token` na
spec, lê o token com `/bin/cat` (`claude-seat-token.ts`), e o NixOS não tem `/bin/cat`. Então o
`seatClaude` move um token que começa com `sk-ant-oat` para `CLAUDE_CODE_OAUTH_TOKEN` e remove
`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` e os interruptores de nuvem, só para o processo do
Claude. Qualquer outro valor em `ANTHROPIC_API_KEY` é descartado, então o Claude nunca cobra uma
chave de API por engano. Os seats omp não mudam. Rodei a lógica do wrapper com valores de mentira e
o `claude --version` por ele.

**A proteção.** As regras deny são os `bash.patterns` do `hermes/omp.yml`, um a um, como regras
`Bash(...)`, e as `restrictedFolders` dele como regras `Read(...)`. Acrescentam `git -C * push`,
`claude *`, `rig seat set-permissions*`, `rig policy apply*` e o token do próprio seat. O Claude Code
confere as regras deny antes do modo de permissão, então elas valem sob
`--dangerously-skip-permissions`. Não são um sandbox: um programa que o seat inicia pode ler o que
uma regra nomeia. A camada dura é o sandbox da unit. A chave `allowManagedPermissionRulesOnly` está
no schema de configurações desta versão (li no binário), então regras de um repositório não afrouxam
as gerenciadas.

**Versão.** O flake fixa o nixos-26.05, cujo `claude-code` é o 2.1.223. O binário tem as strings
`claude-sonnet-5` e `claude-opus-5`, e não `claude-sonnet-5-5`. ⚠ Não testei se um seat aceita esse
modelo. As outras flags que o OpenRig usa (`--session-id`, `--name`, `--effort`,
`--permission-mode`, `--dangerously-skip-permissions`) estão no `--help` dele. Se o modelo falhar,
use `model: sonnet` ou atualize o nixpkgs.

**Custo.** A closure cresce cerca de 280 MiB em relação ao sistema em execução (o binário tem
290 MB; o resto é pequeno). O binário vem de `downloads.claude.ai` por um fetch de saída fixa, então
o runner do CI o constrói (nada está no `cache.nixos.org`), e o deploy o copia para a máquina.

**O que uma pessoa precisa fazer.**
1. Definir `piabrota.openrig.waveForecaster.enable = true` em `hosts/piabrota2/default.nix`, fazer o
   merge e deixar o deploy rodar.
2. Uma rig guarda a spec que a criou. As duas rigs wave foram criadas da spec antiga, então rode
   `rig archive wave-forecaster-dev` e depois
   `rig import /etc/openrig/specs/rigs/wave-forecaster-dev/rig.yaml --materialize-only`. Isso cria a
   rig e seus seats e não inicia nada. Depois `rig up`.
3. O Claude Code pede uma vez para aceitar o aviso do bypass-permissions. O OpenRig marca o seat como
   `attention_required` até que `rig seat continue`, ou a UI web, responda. Uma linha
   `non_interruptive: true` na spec aceitaria por flag. Este PR não acrescenta essa linha: a lista de
   negação do Hermes bloqueia a flag `--non-interruptive`, e a escolha é do dono.

## O que não está provado

- Um seat Claude de verdade: o início, o primeiro turno, o login com o token do wrapper, o diálogo
  do bypass, o id do modelo com o Claude Code 2.1.223 e o uso de memória.
- Que o OpenRig acha o processo de um seat iniciado pelo wrapper (`choom` e depois o wrapper Nix do
  `claude`). O OpenRig conhece o layout Nix do `claude-code`
  ([`native-process-lineage.ts`](https://github.com/mvschwarz/openrig/blob/v0.7.7/packages/daemon/src/domain/native-process-lineage.ts)),
  e essa cadeia não rodou sob uma rig.
- Regras Read com caminho absoluto: a forma documentada é `//caminho`, e o arquivo também traz a
  forma `/caminho`.
- As linhas de Codex, Pi, `stub` e comunidade: só docs.

## Fontes

- OpenRig v0.7.7: `docs/reference/rig-spec.md`, `docs/reference/community-harness-presets.md`,
  `docs/reference/harness-runner-contract.md`, `docs/reference/non-interruptive-mode.md`,
  `docs/reference/agent-state-taxonomy.md`, `docs/as-built/architecture/adapters-and-runtimes.md`,
  `docs/as-built/test-layers.md`, `packages/daemon/src/domain/claude-seat-token.ts`,
  `claude-credential-precedence.ts`, `claude-managed-launch.ts` e `startup.ts`.
- Este repositório: `openrig.nix`, `unfree.nix`, `omp/wrapper.nix`, `hermes/omp.yml`,
  `openrig/specs/`, [`OPENRIG.md`](OPENRIG.md),
  [`hermes/skills/hermes-rig/references/runtimes.md`](../hermes/skills/hermes-rig/references/runtimes.md).
