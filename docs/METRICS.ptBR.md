# Página de métricas

[English](METRICS.md)

Uma página pequena, feita em casa, mostra as métricas das duas máquinas quase ao vivo. Fica em
https://metrics.piabrota.art, na piabrota2. O módulo é `metrics.nix`. Tudo vem desligado; cada host
liga o que é seu. O formato do arquivo de dados está em [metrics/SCHEMA.md](../metrics/SCHEMA.md).

## O que mostra e o que não mostra

A página é um `metrics/index.html` estático (menos de 20 KB, sem pedido externo, JavaScript puro).
A cada 5 s ela lê `/data/piabrota.json` e `/data/piabrota2.json` e guarda as últimas 60 amostras só
na memória da aba.

Mostra, por host:

- CPU, memória usada (MemTotal menos MemAvailable) e disco de `/`.
- Os 10 processos que mais usam memória (RSS) e os 10 que mais usam CPU.
- As unidades do systemd sob `system.slice` que têm `MemoryMax` numérico (hermes-agent 8G,
  hermes-backend 2G, openrig 2G, pgx 256M...), no máximo 12, em ordem de memória sobre o máximo.
  O `memory.peak` aparece quando o kernel tem.
- O total de processos (conta as threads do kernel).

Como ler os números:

- A CPU de um processo é a média do último intervalo (cerca de 10 s), em percentual de UMA vCPU.
  Por isso pode passar de 100.
- O nome do processo é só o `comm` (até 15 caracteres, ASCII imprimível; o resto vira `?`).
- Na primeira rodada depois do boot a página diz `warming` e a CPU é 0.

Não mostra: histórico além das amostras da aba (as amostras vêm por arquivo novo, a cada 10 s, então
são uns 10 minutos), outros discos além de `/`, rede, disco ou IO por processo, alertas, linhas de
comando.

## Os dois hosts e quem roda o quê

| Host | Coletor | Página (nginx) | Pull | Publica |
|---|---|---|---|---|
| piabrota2 (KVM 4) | sim | sim | sim | não |
| piabrota (KVM 1) | sim | não | não | sim |

- O coletor é o `metrics/collect.sh` (POSIX sh e awk). O timer `metrics-collect.timer` o roda a cada
  10 s (unidade oneshot `metrics-collect.service`).
- Ele escreve `/run/metrics-web/<nome>.json` de forma atômica. A amostra anterior fica em
  `/run/metrics-state/<nome>.state` (não é servida).
- Os nomes são `piabrota` e `piabrota2` (opção `piabrota.metrics.name`). Nunca o hostname: o da
  piabrota2 ainda é `nixos`.
- Lê só `/proc`, `/sys/fs/cgroup`, `/etc/passwd` e `df`. Nunca uma linha de comando.
- O arquivo JSON tem menos de 8 KB (schema v1).

## O caminho dos dados da KVM 1

A piabrota tem o coletor e UMA location a mais no vhost `www.piabrota.art`:
`= /_metrics/piabrota.json`, com `allow 187.41.117.18; deny all;`. Esse é o IPv4 público da
piabrota2 (opção `piabrota.metrics.publish.allowFrom`).

Na piabrota2, o timer `metrics-pull.timer` (a cada 10 s) roda `metrics-pull.service`. Ele faz
`curl -4 -sf --max-time 5 --max-filesize 65536` de
`https://www.piabrota.art/_metrics/piabrota.json`. Confere que começa com `{` e diz
`"host":"piabrota"`. Depois escreve `/run/metrics-web/piabrota.json` de forma atômica.

Se a busca falha, o arquivo antigo fica (a unidade sai com 0). A página então fica velha e depois
offline.

A lista de IPs não é segredo e basta, porque o arquivo não tem linha de comando, segredo nem dado de
usuário além de nomes de processo, nomes de usuário e números de memória e CPU. O limite: quem
consegue enviar a partir do endereço da piabrota2 (um processo na piabrota2, ou uma posição de rede
que falsifica endereço) consegue ler o arquivo. Só IPv4. Se o endereço da piabrota2 mudar, troque
`allowFrom` em `hosts/piabrota/default.nix`.

## DNS e login

- O DNS de `metrics.piabrota.art` já aponta para a piabrota2: nada a fazer.
- O nginx da piabrota2 atende o domínio com `forceSSL` e ACME.
- O login é HTTP basic auth contra o MESMO arquivo do painel do Hermes
  (`piabrota.hermesWeb.htpasswdFile`, `/var/lib/hermes-web-secrets/htpasswd`). Então vale o login do
  hermes.piabrota.art. Não há segredo novo.
- `/data/` vem de `/run/metrics-web/` com `Cache-Control: no-store`.
- Limite de 10 pedidos por segundo para cada endereço.

## Quando um host aparece offline

A página mostra o host offline quando o arquivo dele tem mais de 30 s ou a busca falha. Ela diz a
idade dos dados. Para investigar, rode:

```console
systemctl status metrics-collect.timer metrics-pull.timer
journalctl -u metrics-collect -u metrics-pull --since -10min
cat /run/metrics-web/piabrota.json | head -c 300      # compare "ts" com: date +%s
```

Na piabrota2 olhe os dois timers. Na piabrota só existe o `metrics-collect.timer`.

Para a ponte da KVM 1, rode na piabrota2:

```console
curl -sI https://www.piabrota.art/_metrics/piabrota.json
```

Deve dizer 200. De qualquer outro lugar deve dizer 403.

## Custo (medido)

Medido na piabrota2, com 127 processos:

- Uma rodada: 0,03 s de relógio, cerca de 0,02 s de CPU, 5 MB de RSS no pico.
- Nada fica residente entre as rodadas.
- A cada 10 s dá cerca de 0,2 % de uma vCPU (cerca de 3 minutos de CPU por dia: 8.640 rodadas).
- Na KVM 1 (1 vCPU) há menos processos, então o custo é menor.
- A unidade tem `MemoryMax=64M` e um usuário de sistema fixo, `metrics`.

## Endurecimento

As duas unidades rodam como `metrics` com:

- `ProtectSystem=strict`, com `ReadWritePaths` só das duas pastas em `/run`.
- `MemoryMax=64M`, `NoNewPrivileges`, conjunto de capabilities vazio e filtro de syscalls.
- `PrivateNetwork` no coletor.
- `LogLevelMax=warning`, para a rodada não escrever linhas no journal.

NÃO usamos `ProcSubset=pid`, `ProtectProc=invisible` e `PrivateUsers`, porque escondem o que o
coletor precisa ler (com `PrivateUsers` os nomes de usuário virariam números).

## Opções

Todas vêm desligadas. Todas ficam sob `piabrota.metrics`:

| Opção | Para que serve |
|---|---|
| `name`, `label` | nome do arquivo de dados e rótulo na página |
| `collector.enable` | liga o coletor e o timer |
| `collector.interval` | segundos entre rodadas (2 a 300, padrão 10) |
| `web.enable`, `web.domain`, `web.htpasswdFile` | a página no nginx, o domínio e o arquivo de login |
| `publish.enable`, `publish.allowFrom` | a location da KVM 1 e o IP que pode ler |
| `pull.enable`, `pull.url`, `pull.name` | o timer que busca o arquivo do outro host |

Hoje: a piabrota2 liga coletor, web e pull. A piabrota liga coletor e publish.

## Mudar a cadência

Mude `piabrota.metrics.collector.interval` (em segundos) no arquivo do host. O limite de offline da
página é 30 s, a constante `STALE_S` em `metrics/index.html`. Então deixe o intervalo em 10 ou
menos, ou mude essa constante também.

## Remover os dados do Beszel

O Beszel saiu. O novo deploy para e remove as unidades `beszel-hub` e `beszel-agent`. Os dados
antigos ficam no disco da piabrota2. O dono roda:

```console
sudo rm -rf /var/lib/beszel-hub /var/lib/beszel-secrets
```

Na piabrota, rode também `sudo rm -rf /var/lib/beszel-secrets`, se a pasta existir. Mais nada é
preciso. A conta do hub do Beszel e a `KEY` e o `TOKEN` dos agentes não valem mais.

## Testes e prévia

- `sh metrics/test/run.sh`: o coletor, com uma árvore falsa de `/proc` e cgroup. Imprime
  "N checks, M failed".
- `sh metrics/test/page.sh`: as regras estáticas da página e uma busca HTTP com python3.
- `checks.metrics`: três VMs (hub, edge, client), HTTP simples, precisa de KVM:
  `nix build .#checks.x86_64-linux.metrics`.
- Prévia da página com dados de teste (healthy, stale, missing, hostile):

  ```console
  sh metrics/test/preview.sh healthy 8080     # abra http://127.0.0.1:8080/
  just metrics-preview healthy
  ```

  Precisa de python3 e jq.
