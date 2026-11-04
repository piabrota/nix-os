# Hermes

[English](Hermes-EN)

O [Hermes Agent](https://github.com/NousResearch/hermes-agent), o agente da Nous Research, roda
na `kvm4` (a VPS KVM 4) como piabrota-hermes: ele responde no Telegram e no Discord, roda as
próprias tarefas agendadas e, quando o dono pede, abre pull requests. Esta página é um mapa de
como ele roda e de como ele é configurado, no estado de
[#72](https://github.com/piabrota/nix-os/pull/72) e
[#74](https://github.com/piabrota/nix-os/pull/74). O guia completo é
[`docs/HERMES.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/HERMES.ptBR.md); a
configuração em si é [`hermes.nix`](https://github.com/piabrota/nix-os/blob/main/hermes.nix).

## A configuração, em YAML

[www.piabrota.art/hermes](https://www.piabrota.art/hermes) mostra a configuração inteira em YAML
simples: as configurações que o `hermes.nix` escreve no `config.yaml` e o jeito como a unidade
roda. O build do site lê esses dados do sistema avaliado, então a página muda a cada merge que
muda o `hermes.nix`. Este wiki não copia esse YAML: leia lá.

## Como ele roda

| | |
|---|---|
| Unidade | `hermes-agent`, um serviço systemd do módulo NixOS do flake do Hermes (o input `hermes-agent`, fixado no `flake.lock`). Modo nativo, sem contêiner. |
| Versão | A release v0.22.7 (commit `b200f5b`, de 2026-11-03), fixada no `flake.lock`. |
| Host | `kvm4`, a VPS KVM 4 (`hosts/kvm4/default.nix`). |
| Pacote | `full`, o padrão do flake do Hermes, mais os extras `anthropic`, `messaging`, `mcp` e `ddgs`. |
| Limites | `MemoryMax=8G` (metade da RAM) e `CPUWeight=50`: com os quatro núcleos ocupados, o sshd e as outras unidades têm o dobro da parcela de CPU do Hermes. |
| Painel | `hermes.piabrota.art`, atrás do nginx, com TLS e basic auth. Unidade `hermes-backend`, `MemoryMax=2G` (`hermes-web.nix`). |
| Estado | `/var/lib/hermes`. O diretório de trabalho é `/var/lib/hermes/workspace`. |
| Segredos | Um arquivo na máquina, `/var/lib/hermes-secrets/hermes.env`, só do root. A ativação copia esse arquivo para o `.env` do Hermes. Nunca no repositório, no store ou na página `/hermes`. |
| GitHub | Um App próprio, piabrota-hermes[bot] (`hermes-github.nix`): só branches `hermes/*` e pull requests, nunca um merge. |
| CLI | `hermes`, rodado pelo `h0ffmann` com `sudo -u hermes hermes ...`. Ele não está no grupo `hermes`: a aba Chat do painel exige o grupo privado. |
| Fuso horário | `America/Sao_Paulo`. |

## Os modelos

Os dois modelos rodam na assinatura do Claude do dono, nunca com uma chave de API, e não há
provedor de reserva: se a Anthropic falha, o turno falha.

| Modelo | Faz |
|---|---|
| `claude-sonnet-5-5` | O modelo principal: ele planeja, escreve, revisa e decide. Ele também faz a compressão, a aprovação de comando perigoso e a revisão depois do turno. Ele mesmo roda um grep, uma listagem ou uma busca isolada. |
| `claude-haiku-5-5` | Subagentes só para leitura em leque (três tarefas ou mais, ou mais de uns 20 arquivos) e três tarefas laterais: os títulos das sessões, a escolha de skill e o juiz do `/goal`. |

Subagentes: no máximo 2 ao mesmo tempo, 50 iterações cada, um nível de profundidade.

## Limites de execução

| Configuração | Valor |
|---|---|
| `agent.max_turns` | 60 chamadas ao modelo numa execução, com parada forçada em laço de ferramenta |
| `goals.max_turns` | 6 turnos para um `/goal` (o padrão é 20); `/goal resume` dá mais 6 |
| `cron.max_parallel_jobs` | 1 |
| `agent.agent_cache.max_size`, `code_execution.max_session_kernels` | 16, 1 |
| `gateway.max_inbound_media_bytes` | 20 MiB, e o mesmo teto para os anexos do Discord |
| `sessions` | apagadas depois de 45 dias; depois, o `state.db` passa por vacuum |
| `updates.check`, `model_catalog.enabled`, `telemetry.shared_metrics.enabled`, `security.allow_lazy_installs` | desligados: o Nix cuida das atualizações e das dependências, e nada vai para a Nous |

## Um deploy e um reinício

1. Um merge na `main` roda o `deploy.yml`. O runner builda o sistema, e o deploy-rs troca a VPS
   para ele ([Operação](Operacao)).
2. A ativação escreve de novo o `config.yaml`, o `.env`, o `SOUL.md`, o `AGENTS.md` e os links
   dos plugins do Hermes.
3. Quando uma dessas entradas muda, o systemd recarrega o `hermes-agent` (`reloadTriggers`). O
   reload manda `SIGUSR1`: o gateway não aceita trabalho novo, deixa terminar os turnos, as
   tarefas agendadas e os subagentes em andamento, e sai com o código 75. O `Restart=always` sobe
   o gateway de novo com a configuração nova. Um turno espera no máximo 600 s
   (`agent.restart_after_turn_timeout`). Uma mensagem nova espera o gateway voltar.
4. Um pacote novo do Hermes muda o `ExecStart` da unidade, e isso reinicia a unidade na hora.
5. Depois, o deploy apaga todas as gerações do sistema menos as cinco últimas. Ele não coleta
   lixo: o Nix coleta quando o disco livre fica abaixo de 2 GiB (até sobrarem 8 GiB), e o
   `nix.gc` apaga, toda semana, os caminhos com mais de 14 dias. O store é deduplicado uma vez
   por semana, não a cada deploy.

Para ver se um deploy pegou, compare `systemctl show hermes-agent -p ActiveEnterTimestamp` com a
hora do deploy. Por causa da espera, a diferença pode chegar a 10 minutos.

## Quem ele é e o que ele pode usar

- `hermes/SOUL.md`: a identidade e as regras dele (do dogma da piabrota). `hermes/AGENTS.md`: um
  resumo dos projetos, das fontes e das tarefas do dono. A ativação instala os dois a cada deploy.
- Skills: cinco do catálogo opcional do projeto, a evidence-ledger-research e 29 skills do dono
  ([`docs/HERMES-SKILLS.md`](https://github.com/piabrota/nix-os/blob/main/docs/HERMES-SKILLS.md)).
- Servidores MCP: DeepWiki e Context7, remotos, sem chave.
- Proteção: o plugin custom-dangerous-patterns bloqueia os comandos de
  [`hermes/dangerous-patterns.yaml`](https://github.com/piabrota/nix-os/blob/main/hermes/dangerous-patterns.yaml)
  (escritas no GitHub fora dos branches dele, segredos, `sudo`, instalações). A lista fica no
  store, então o Hermes não consegue mudar a lista.

## Para mudar

Mude o `hermes.nix` ou o `hermes/` num pull request; o merge faz o deploy. No NixOS, o
`hermes setup` e o `hermes config set` se recusam a mudar o que o módulo controla. Para olhar a
unidade na máquina:

```console
systemctl status hermes-agent
journalctl -u hermes-agent -n 100
hermes status
```
