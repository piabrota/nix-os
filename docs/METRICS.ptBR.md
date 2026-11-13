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
- O total de processos (conta as threads do kernel), threads, tarefas rodando e bloqueadas, forks
  e trocas de contexto por segundo, arquivos abertos e os serviços que rodam agora (cada serviço com um cgroup sob
  `system.slice`).
- O detalhe da memória: cache de páginas, buffers, shmem e páginas sujas (dirty).
- Rede de entrada e de saída por segundo (todas as interfaces menos `lo`), sockets TCP (em uso,
  TIME-WAIT) e sockets UDP.
- Leitura e escrita de disco por segundo, somadas sobre os discos inteiros (`sda`, `vda`,
  `nvme0n1`; sem partições).
- Pressão (PSI) de CPU, memória e IO: a parte dos últimos 10 s em que tarefas esperaram
  (`some` / `full`).
- No topo: os sites que respondem (verde) e os que não respondem (vermelho), os commits, os
  deploys, os apps instalados e a versão do NixOS ("O topo", abaixo).
- O que esta geração roda: as contagens de "O inventário", abaixo.

Como ler os números:

- A CPU de um processo é a média do último intervalo (cerca de 10 s), em percentual de UMA vCPU.
  Por isso pode passar de 100.
- O nome do processo é só o `comm` (até 15 caracteres, ASCII imprimível; o resto vira `?`).
- Na primeira rodada depois do boot a página diz `warming` e a CPU é 0.

Não mostra: histórico além das amostras da aba (as amostras vêm por arquivo novo, a cada 10 s, então
são uns 10 minutos), uso de outros sistemas de arquivos além de `/`, rede ou IO por processo ou por interface, alertas, linhas de
comando.

## O topo: sites, commits, deploys, apps, NixOS

O topo de cada cartão tem cinco números e uma linha de sites:

| Rótulo | O que é | De onde vem |
|---|---|---|
| Domains up | sites que responderam, dos sites do host; verde quando todos respondem, vermelho quando um não responde | `metrics/probe.sh`, a cada 60 s |
| Commits | commits na `main` de `piabrota/nix-os` | a API do GitHub, no máximo uma vez a cada 10 minutos |
| Deploys | a geração de `/nix/var/nix/profiles/system`: uma para cada deploy que mudou o sistema | o coletor, a partir do link `system-<n>-link` |
| Apps installed | os pacotes de `environment.systemPackages` (a contagem `packages` do inventário) | o Nix, no build |
| NixOS | a versão, por exemplo 26.05; a versão completa fica na dica | `/run/current-system/nixos-version` |

Abaixo deles, cada site do host é uma etiqueta: verde quando responde, vermelha com o código HTTP
(ou "no answer") quando não responde. Um site está de pé quando dá qualquer resposta abaixo de HTTP
500: um 301 ou um 401 (um login) é uma resposta. A sonda não segue redirecionamento. Quando os dados
da sonda estão mais de 5 minutos atrás dos do host, as etiquetas ficam cinza e a contagem fica sem cor.

Os sites são os mesmos nomes que o inventário conta como `sites`: todo host virtual do nginx, menos
o `_` e os nomes que só redirecionam. O Nix grava a lista (`https://` quando o host tem TLS). A sonda
(`metrics-probe.timer`, oneshot `metrics-probe.service`) pergunta a cada nome com um `curl` de no
máximo 6 s, um depois do outro, e grava `/run/metrics-state/<name>.probe` (não servido). O coletor
copia isso para `domains` e `repo` (metrics/SCHEMA.md). A sonda lê a contagem de commits do
cabeçalho `Link` de `GET /repos/piabrota/nix-os/commits?per_page=1`: o número da última página é a
contagem. Sem token o GitHub aceita 60 pedidos por hora de um endereço; a sonda usa 6. Quando o
GitHub não responde, fica a última contagem.

## O inventário

Cada cartão tem um bloco "What this generation runs". O Nix conta isso uma vez, quando constrói o
sistema, a partir da configuração que o host roda; nada é contado na máquina. Um deploy muda os
números.

| Chave | Rótulo | O que conta |
|---|---|---|
| `apps` | Loco apps | `piabrota.loco.apps` |
| `sites` | Sites | hosts virtuais do nginx, sem o `_` padrão e sem os nomes que só redirecionam |
| `rigs` | Rigs | as specs de rig em `/etc/openrig/specs/rigs`, quando o OpenRig está ligado |
| `agents` | Rig agents | as specs de agente em `/etc/openrig/specs/agents`, sem as pastas `*shared` |
| `skills` | Skills | os arquivos `SKILL.md` das pastas de skills do Hermes (`skills.external_dirs`) e dos plugins |
| `skills_bundled` | Bundled skills | os arquivos `SKILL.md` que vêm dentro do Hermes (`piabrota.metrics.inventory.bundledSkillDirs`) |
| `plugins` | Plugins | `settings.plugins.enabled` do Hermes |
| `mcp` | MCP servers | `mcpServers` do Hermes |
| `packages` | Packages | `environment.systemPackages` |
| `timers` | Timers | os timers do systemd que estão ligados |

Um módulo que o host não importa conta 0: a piabrota não tem Hermes nem OpenRig. São contagens
declaradas. O Hermes também pode criar skills próprias em tempo de execução, em `/var/lib/hermes`; o
coletor não lê essa pasta (o usuário dele não está no grupo `hermes`, de propósito), então essas
skills ficam fora da conta. O `metrics.nix` grava as contagens num arquivo no store e o coletor as
copia para `inventory` (metrics/SCHEMA.md).

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
- Lê só `/proc`, `/sys/fs/cgroup`, `/etc/passwd`, `df`, o arquivo do inventário no store, o
  arquivo da sonda, o link do perfil do sistema e `/run/current-system/nixos-version`. Nunca
  uma linha de comando.
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

## DNS e acesso

- O DNS de `metrics.piabrota.art` já aponta para a piabrota2: nada a fazer.
- O nginx da piabrota2 atende o domínio com `forceSSL` e ACME.
- A página é pública. Quem visita não precisa de login.
- Quem visita pode ler a página e os arquivos de `/data/`. Estes campos são públicos:
  - o nome e o rótulo do host, a hora da amostra, o uptime, o número de vCPUs e a carga;
  - o uso de CPU (total e de cada vCPU), a memória e o swap (total, usado, disponível) e o uso do
    disco de `/`;
  - o número de processos e de serviços rodando;
  - o inventário: quantos Loco apps, sites, rigs, agentes de rig, skills, plugins, servidores MCP,
    pacotes e timers a configuração declara;
  - dos 10 processos que mais usam memória e dos 10 que mais usam CPU: pid, nome do processo
    (`comm`), nome do usuário, RSS e percentual de CPU;
  - de até 12 unidades do systemd: nome da unidade, memória agora, `MemoryMax` e pico de memória.
- Os dados não têm segredo nem linha de comando. Eles mostram quais serviços rodam e o quanto o
  host está ocupado. Isso não dá acesso a nada, mas um atacante pode ler.
- `/data/` vem de `/run/metrics-web/` com `Cache-Control: no-store`.
- Limites por endereço: 10 pedidos por segundo (rajada de 30) e 20 pedidos abertos. Acima de um
  limite, o nginx responde 429.
- Para pôr o login de volta, defina `piabrota.metrics.web.htpasswdFile` com um caminho no arquivo do
  host, por exemplo `"/var/lib/hermes-web-secrets/htpasswd"` (o arquivo do painel do Hermes). Aí
  todo pedido, `/robots.txt` inclusive, exige login, e arquivo ausente dá 500. O padrão é `null`:
  sem login.

## robots.txt e bloqueio de robôs

- O `/robots.txt` sai de uma única lista de agentes de IA e de raspagem, `blockedAgents` em
  `metrics.nix`. Para cada agente ele diz `Disallow: /`. O último grupo, `User-agent: *`, também diz
  `Disallow: /`. O nginx o envia como `text/plain` com `Cache-Control` de um dia. O arquivo fica na
  loja do Nix.
- O nginx lê a mesma lista. Ele compara o cabeçalho `User-Agent`, sem diferenciar maiúsculas. Um
  agente da lista recebe 403 em todo caminho, menos em `/robots.txt`, para ainda poder ler o arquivo
  que manda ele embora. `User-Agent` vazio, navegador, `curl` e `python-requests` não são
  bloqueados.
- Toda resposta leva `X-Robots-Tag: noindex, nofollow, noarchive, noimageindex, noai, noimageai`.
- Para bloquear mais um agente, ponha o nome em `blockedAgents`. Uma só edição muda o arquivo e a
  regra do nginx.
- Os nomes vêm do [ai-robots-txt/ai.robots.txt](https://github.com/ai-robots-txt/ai.robots.txt)
  (`robots.json`; o commit está no comentário acima da lista). O nginx acha um nome em qualquer
  ponto do cabeçalho, então um nome que é palavra comum (`Code`, `Dot`, `Spider`) não entra na
  lista: ele bloquearia navegadores e outros clientes. O `facebookexternalhit` não entra na lista,
  para as prévias de link continuarem funcionando.

Esses passos só detêm robôs bem-comportados. Um raspador pode trocar o `User-Agent` e ignorar o
`robots.txt`. Eles não são controle de acesso. Não protegem a página de quem quer os dados. A
página é segura para expor porque não tem segredo.

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

As unidades (coletor, sonda, pull) rodam como `metrics` com:

- `ProtectSystem=strict`, com `ReadWritePaths` só das duas pastas em `/run`.
- `MemoryMax=64M`, `NoNewPrivileges`, conjunto de capabilities vazio e filtro de syscalls.
- A sonda é a unidade de um host que abre conexão (o pull é a outra, na piabrota2): o sandbox
  é o mesmo, com `AF_INET` e `AF_INET6`.
- `PrivateNetwork` no coletor. Por isso ele lê a rede do PID 1 (`/proc/1/net/dev` e `sockstat`),
  que qualquer usuário lê, e não o seu próprio `/proc/net` vazio.
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
| `probe.enable`, `probe.interval` | o timer que pergunta a cada site por uma resposta (10 a 3600 s, padrão 60); precisa do coletor |
| `probe.repo`, `probe.branch` | o repositório e o branch cujos commits são contados (padrão `piabrota/nix-os`, `main`); repo vazio: sem contagem |
| `web.enable`, `web.domain`, `web.htpasswdFile` | a página no nginx, o domínio e o arquivo de login opcional (`null`, o padrão, deixa a página pública) |
| `publish.enable`, `publish.allowFrom` | a location da KVM 1 e o IP que pode ler |
| `pull.enable`, `pull.url`, `pull.name` | o timer que busca o arquivo do outro host |
| `inventory.bundledSkillDirs` | pastas de skills que vêm dentro de um agente, contadas como `skills_bundled`; o `hermes.nix` acrescenta as do Hermes |

Hoje: a piabrota2 liga coletor, sonda, web e pull. A piabrota liga coletor, sonda e publish.

## Mudar a cadência

Mude `piabrota.metrics.collector.interval` (em segundos) no arquivo do host. O limite de offline da
página é 30 s, a constante `STALE_S` em `metrics/index.html`. Então deixe o intervalo em 10 ou
menos, ou mude essa constante também.

## Testes e prévia

- `python3 metrics/test/collect_test.py`: o coletor e a sonda, com uma árvore falsa de `/proc` e
  cgroup e um curl falso. Imprime "N checks, M failed".
- `checks.metrics-page` (`metrics/test/page.nix`): as regras estáticas da página, em Nix puro, e
  os dados de teste pelo jq. `python3 metrics/test/preview.py --check`: uma busca HTTP da página e
  dos dados. `just metrics-test` roda os três.
- `checks.metrics`: quatro VMs (hub, edge, locked, client), HTTP simples, precisa de KVM:
  `nix build .#checks.x86_64-linux.metrics`.
- Prévia da página com dados de teste (healthy, stale, missing, hostile):

  ```console
  python3 metrics/test/preview.py healthy 8080     # abra http://127.0.0.1:8080/
  just metrics-preview healthy
  ```

  Precisa de python3.
