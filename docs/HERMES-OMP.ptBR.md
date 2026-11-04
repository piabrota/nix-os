# omp, o trabalhador de código padrão: ver e ajustar

English: [HERMES-OMP.md](HERMES-OMP.md) (este arquivo vem primeiro; o inglês é o espelho).

## A regra

Toda tarefa que escreve ou revisa código, configuração ou scripts passa pelo omp (oh-my-pi). O
Hermes escreve um arquivo de tarefa e roda o omp. O Hermes lê o diff. Depois o Hermes faz o commit,
o push de um branch `hermes/*` e abre o pull request.

O Hermes não escreve código com as próprias ferramentas de arquivo. O omp nunca faz push e nunca
chama o `gh`.

O Hermes edita à mão só em dois casos: um arquivo Markdown sem código, e um deslize pequeno no diff
do omp. No segundo caso, o Hermes avisa no chat. O omp não roda para conversa, notas ou pesquisa.

O procedimento é a skill `hermes-omp`: [`hermes/skills/hermes-omp/SKILL.md`](../hermes/skills/hermes-omp/SKILL.md).
A configuração está em [HERMES.ptBR.md](HERMES.ptBR.md#omp-o-trabalhador-de-código). A skill também é
um comando: `/hermes-omp` no Telegram e `/skill` no Discord.

## O que você vê no chat

Antes da execução, o Hermes diz o repositório, o branch, o modo (escrita ou só revisão), o arquivo
de tarefa, os modelos e o nível de raciocínio.

Durante a execução, o Hermes diz o estado do processo e o tempo que falta. A saída do omp fica
vazia até o fim da execução.

Depois da execução, o Hermes diz estes fatos:

- os arquivos que o omp mudou;
- as verificações que o omp rodou e as que o Hermes rodou;
- o que ninguém verificou, e cada rótulo "unsure" que o omp escreveu;
- o tempo da execução;
- o link do pull request.

O omp guarda cada sessão em `~/.omp/agent/sessions/<encoded-cwd>/<timestamp>_<sessionId>.jsonl`, na
home do Hermes. O comando `omp --export <session>` escreve uma sessão em HTML (docs do omp,
`session.md` e `cli-reference.md`). Não testado nesta máquina.

## As camadas: o que você pode editar

As linhas vão da camada mais próxima da execução até a mais distante.

|Camada|Arquivo|O que controla|Quem muda|Quando vale|
|---|---|---|---|---|
|1. A tarefa|`/var/lib/hermes/workspace/omp-tasks/<nome>.md` (arquivo temporário)|O objetivo, os critérios de pronto, os comandos de verificação, os arquivos para começar|Você, quando pede ao Hermes no chat|Na próxima execução, sem deploy|
|2. Flags de uma execução|O comando `omp` na skill|`--thinking <nível>`, `--model <id-ou-papel>`, `--max-time`|Você, quando pede ao Hermes ("rode o omp com --thinking max")|Na próxima execução, sem deploy. Use só flags de modelo, raciocínio e tempo: nunca uma flag que afrouxe uma regra|
|3. As regras do repositório de destino|`AGENTS.md`, `.omp/AGENTS.md`, `.omp/RULES.md` no repositório que o omp muda|O contexto do projeto (`AGENTS.md`) e as exigências curtas e rígidas que ficam em todo pedido (`RULES.md`)|Um PR para esse repositório|Depois do merge lá|
|4. O procedimento|[`hermes/skills/hermes-omp/SKILL.md`](../hermes/skills/hermes-omp/SKILL.md)|Quando o Hermes usa o omp, o formato do arquivo de tarefa, a revisão do diff, o que o Hermes diz a você|Um PR para o nix-os|Depois do próximo deploy (veja abaixo)|
|5. O acréscimo ao prompt|[`hermes/omp-append-system.md`](../hermes/omp-append-system.md)|As regras que o wrapper acrescenta ao prompt de sistema do omp: diffs pequenos, uma verificação declarada, nada de "pronto" sem saída|Um PR para o nix-os|Depois do próximo deploy (veja abaixo)|
|6. O overlay de configuração|[`hermes/omp.yml`](../hermes/omp.yml)|Os modelos por papel, o nível de raciocínio, as ferramentas, a memória, as regras de bloqueio do bash, as pastas restritas|Um PR para o nix-os|Depois do deploy|
|7. O wrapper|[`omp/wrapper.nix`](../omp/wrapper.nix) (`ompWrapped` no [`hermes.nix`](../hermes.nix))|O ambiente, o token, o `choom`, o teto de tempo e as flags que toda execução recebe|Um PR para o nix-os|Depois do deploy|
|8. A versão|[`omp/package.nix`](../omp/package.nix) (tag `v18.16.0`)|A release do omp|Um PR para o nix-os|Depois do deploy|

O `deploy.yml` ignora um merge que muda só Markdown. Isso inclui os arquivos Markdown em `hermes/`:
`SOUL.md`, `AGENTS.md`, `omp-append-system.md` e a skill. Uma mudança assim chega à máquina no próximo
deploy, ou quando você roda o `deploy.yml` à mão no `main`. Um merge que muda um arquivo `.nix`, o
`hermes/omp.yml` ou outro arquivo que não é Markdown faz o deploy da máquina.

O wrapper roda o omp sob `timeout`. Nenhuma execução passa de 35 minutos, sejam quais forem as flags.
Um restart do gateway também interrompe a execução. Numa tarefa longa, o arquivo de tarefa nomeia um
arquivo de progresso (`omp-tasks/<nome>.progress`). O omp acrescenta uma linha a cada passo
concluído, e a execução seguinte continua depois do último. O `kvm4-health` mostra o `NRestarts` de
cada unidade: WARN acima de 3, CRIT acima de 50.

## Seats do OpenRig

O OpenRig pode rodar o omp como seat de um rig (`runtime: omp` num AgentSpec). O seat usa o mesmo
wrapper, construído com dois argumentos:

```nix
pkgs.callPackage ./omp/wrapper.nix {
  ceiling = null; # um seat vive enquanto o rig vive
  appendSystemPrompt = ./hermes/omp-seat-append-system.md;
}
```

O wrapper carrega o `hermes/omp.yml` sozinho, então o seat tem as mesmas regras de bloqueio de uma
execução do Hermes. O runner do OpenRig passa ao omp só a `ANTHROPIC_API_KEY`, e só para um modelo
`anthropic/<id>`. O wrapper move um token da assinatura (`sk-ant-oat...`) dessa variável para a
`ANTHROPIC_OAUTH_TOKEN`. As outras configurações da unit do openrig (`OPENRIG_NO_KERNEL=1`,
`OPENRIG_YOLO=1`, o socket do tmux, o `lsof`) e o motivo de cada uma estão em
[`references/openrig-seats.md`](../hermes/skills/hermes-omp/references/openrig-seats.md), na skill.

O `hermes/omp.yml` deixa o seat usar `rig send`, `rig queue` e `rig whoami`. Ele recusa `rig setup`,
`rig daemon`, `rig start`, `rig host`, `rig auth`, `rig provider switch`, `rig mcp`, `rig slack`,
`rig gateway` e `rig destroy`. A deny list do Hermes recusa os mesmos comandos de controle para o
Hermes, mas deixa o Hermes rodar `rig up`, `rig down` e `rig ps`.

## Qual configuração vence

Esta é a ordem no omp, da mais forte para a mais fraca (docs do omp, `config-usage.md`, "Layers", na
v18.16.0):

1. uma variável de ambiente que uma configuração declara;
2. as substituições em tempo de execução;
3. os overlays: primeiro `PI_CONFIG_FILES`, depois cada `--config <arquivo>`; o arquivo mais tardio vence;
4. o `.omp/config.yml` do projeto;
5. o `~/.omp/agent/config.yml` do usuário;
6. o padrão do omp.

Nesta máquina, o wrapper aponta `PI_CONFIG_FILES` para o `hermes/omp.yml`. Esse arquivo fica na store,
só para leitura. Por isso o `.omp/config.yml` de um repositório e o `~/.omp/agent/config.yml` do
Hermes não conseguem afrouxá-lo. Uma lista no overlay substitui a lista de uma camada mais baixa.

## Receitas: o que mudar para quê

- **Código melhor, mais raciocínio.** Mude `defaultThinkingLevel` no `hermes/omp.yml`. Os valores
  aceitos são `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max` e `auto`. Hoje é `high`. Para
  uma execução só, use `--thinking`. O custo é mais da sua cota do Claude.
- **Um modelo mais forte ou mais barato para um trabalho.** Mude `modelRoles.<papel>` no
  `hermes/omp.yml`. Os papéis `default`, `slow` e `plan` levam o trabalho principal. O papel `task` é
  o papel dos subagentes que editam código. Os papéis `smol`, `tiny`, `commit`, `memory`, `advisor` e
  `judge` são papéis laterais e baratos. Hoje os quatro primeiros usam o Sonnet e os outros usam o
  Haiku. Use só modelos `anthropic/...`: a sua assinatura é o único provedor.
- **Resultado melhor em um repositório.** Escreva `.omp/RULES.md` (regras curtas e rígidas) e
  `.omp/AGENTS.md` (contexto) nesse repositório.
- **Resultado melhor em uma tarefa.** Escreva um arquivo de tarefa melhor. Diga o critério de pronto
  e os comandos exatos de verificação.
- **Um hábito diferente em toda execução.** Edite o `hermes/omp-append-system.md`.
- **Quando o Hermes usa o omp, ou o que ele diz a você.** Edite a skill.
- **Execuções mais longas.** Mude `--max-time` no comando da skill (hoje 15 minutos). Mude também
  `tools.maxTimeout` no `hermes/omp.yml`.
- **Servidores de linguagem.** Ligue `lsp.enabled` no `hermes/omp.yml`. Hoje está desligado para
  poupar memória. Teste só com o pico de memória medido (`systemctl show hermes-agent -p MemoryPeak`).

## Teste uma mudança no seu computador primeiro

1. Instale o omp v18.16.0 pela página de releases do `can1357/oh-my-pi` (arquivo `omp-linux-x64`).
2. Num clone do nix-os, rode `omp --config hermes/omp.yml --config meu.yml`.
3. Ponha no `meu.yml` só as chaves que você testa. O arquivo mais tardio vence.

Teste só chaves de modelo e de raciocínio assim. Um segundo overlay pode afrouxar as regras de
bloqueio sem querer. Nunca copie de um experimento uma mudança em `bash.patterns` ou em
`restrictedFolders`. Não testado nesta máquina. O que você testa no seu computador não muda a
máquina. Só um merge muda.

## O que fica fixo

O omp não consegue fazer push, chamar o `gh`, instalar pacotes, nem usar `sudo`, `curl` ou `wget`.
O omp não consegue ler os segredos nem o estado do Hermes. Essas regras estão no `hermes/omp.yml`
(`bash.patterns` e `tools.restrictedFolders`). O arquivo fica na store, e nem o Hermes nem o omp
conseguem editá-lo.

Afrouxar uma regra é decisão sua, tomada num PR para o nix-os. Este documento não recomenda isso.

## Não verificado

- O comando `omp --export` na máquina.
- O experimento com `--config` no seu computador.
- O pico de memória de uma execução com nível de raciocínio mais alto.

## Fontes

O OpenRig na tag v0.7.7 (commit `f3d8bac`), em
[github.com/mvschwarz/openrig](https://github.com/mvschwarz/openrig) (Apache-2.0):
`packages/daemon/src/adapters/pi-runner-protocol.ts`, `pi-runner.ts`, `yolo-mode.ts`, `tmux.ts`
e `packages/daemon/src/domain/kernel-boot.ts`.

As docs do omp na tag v18.16.0, em [github.com/can1357/oh-my-pi](https://github.com/can1357/oh-my-pi)
(MIT): `docs/settings.md`, `docs/config-usage.md`, `docs/cli-reference.md`,
`docs/context-files.md`, `docs/skills.md` e `docs/session.md`.
