# Runtimes

[English](Runtimes-EN)

Runtime é o programa que um seat do [OpenRig](https://github.com/mvschwarz/openrig) roda. Esta
página é um mapa dos seis que o OpenRig traz embutidos (como lidos na v0.7.7), dos harnesses da comunidade e de quais
a `piabrota2` roda. O guia completo, com uma linha de spec, as credenciais, o mapeamento de
permissão e o estado de cada um, é o
[`docs/RUNTIMES.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/RUNTIMES.ptBR.md). Ele
foi lido nos documentos do OpenRig na tag v0.7.7 e nem tudo rodou aqui: nenhum seat fez uma tarefa
ainda. Créditos: OpenRig, de mvschwarz (Apache-2.0), [Pi](https://pi.dev), de Mario Zechner
([badlogic/pi-mono](https://github.com/badlogic/pi-mono)), e
[oh-my-pi](https://github.com/can1357/oh-my-pi), de can1357.

## Os runtimes

|Runtime|O que é|Prós|Contras|Na `piabrota2`|
|---|---|---|---|---|
|`claude-code`|O Claude Code da Anthropic num painel tmux|O mais bem suportado pelo OpenRig. Usa a assinatura do Claude. As configurações gerenciadas põem regras que um repositório não sobrescreve|Unfree. Cerca de +280 MiB. Pede uma vez para aceitar o aviso do bypass. Põe `ANTHROPIC_API_KEY` acima do token OAuth|A rig de port `wave-forecaster-dev`, depois desta mudança e com `waveForecaster.enable` ligado (desligado). Precisa do `unfree.nix`|
|`codex`|O CLI Codex da OpenAI|Sandbox nativo. Outra família de modelos|Precisa de um login da OpenAI e de um binário|Não instalado|
|`pi`|O harness Pi, pelo runner do OpenRig|Pequeno. Muitos provedores. Atividade precisa|Sem subagentes nem modo de plano por padrão. Sem rota da assinatura do Claude. Sem política de permissão|Não instalado. Nenhuma spec|
|`omp`|O oh-my-pi, um fork do Pi, por um runner|Funciona aqui com o token da assinatura. Regras próprias que um repositório não afrouxa|Só recebe chave com modelo escrito `provedor/id`. O restore de um seat novo pede `--fresh`|Funciona: `piabrota-dev` e a rig de integração|
|`terminal`|Um shell comum|Sem modelo, sem token|Sem guidance, sem skills, sem wake da fila|Funciona|
|`stub`|Um harness de teste com roteiro|Testa o encanamento sem tokens|Não prova que uma mensagem foi consumida|Disponível. Nenhuma spec|
|Harness da comunidade|Uma ferramenta de fora, um arquivo de preset|Traz uma ferramenta que o OpenRig não traz|Lido só pela tela. Sem guidance. Sem aprovações|Nenhum instalado|

## Qual escolher

- A assinatura do Claude e o máximo que o OpenRig consegue ver e controlar: `claude-code`.
- A assinatura do Claude, sem pacote unfree: `omp`. É o que a máquina roda.
- Modelos da OpenAI: `codex`, depois que existirem um login da OpenAI e um binário.
- Um harness pequeno e uma chave de OpenRouter, Z.ai, Kimi ou MiniMax: `pi`.
- Um servidor, um tail de log ou um vigia de build: `terminal`.
- Um teste do encanamento sem tokens: `stub`.

Qualquer que seja a escolha, o daemon e todos os seats dividem o `MemoryMax=2G` da unit, dois seats
por vez.

## O que não está provado

Um seat Claude Code de verdade não rodou: nem o login, o primeiro turno, o diálogo do bypass, o
modelo `claude-sonnet-5-5` com o Claude Code 2.1.223 fixado, nem a memória. As linhas de Codex, Pi,
`stub` e harnesses da comunidade vêm só dos documentos. O guia lista cada lacuna.

## Veja também

- [Fábrica](Fabrica): as etapas da fábrica de software e o estado dela.
- [`docs/OPENRIG.md`](https://github.com/piabrota/nix-os/blob/main/docs/OPENRIG.md): a unit, as
  specs e as rigs, incluindo a `wave-forecaster-dev`.
