# Métricas ao vivo com Beszel

[English](METRICS.md)

[Beszel](https://github.com/henrygd/beszel) (MIT) mostra, numa página web, as métricas das duas
máquinas ao vivo: CPU, memória, disco, rede e os serviços do systemd. Tem um hub (a página, com
login próprio) e um agente em cada máquina. O módulo é `metrics.nix`. Tudo vem desligado; cada
host liga o que é seu.

## Por que Beszel e não Grafana

O dono quer ver as métricas como no Grafana, só que mais leve. Grafana, com Prometheus e
exporters, é demais para duas máquinas. Beszel é um hub de 37 MB e um agente de 11 MB, sem banco
de dados à parte (o hub usa SQLite, via PocketBase). Nas medidas abaixo: **34 MiB** de RAM o hub,
**17 MiB** o agente.

## Quem roda o quê

| | piabrota2 (KVM 4) | piabrota (KVM 1) |
|---|---|---|
| Hub | sim, em `metrics.piabrota.art` (nginx, ACME, portas 80 e 443 que já estão abertas) | não |
| Agente | sim, fala com o hub em `http://127.0.0.1:8090` | sim, fala com `https://metrics.piabrota.art` |
| Porta nova | nenhuma | nenhuma |
| Mudança de nginx | o vhost do hub | nenhuma |

O agente **só disca para fora** (um WebSocket). Ele não abre porta nenhuma (`DISABLE_SSH=true`:
`agent/server.go`, `agent/connection_manager.go`). Por isso a piabrota não precisa de firewall novo.

Opções (`metrics.nix`): `piabrota.metrics.hub.{enable,domain}` e
`piabrota.metrics.agent.{enable,hubUrl,environmentFile}`. Hub e agente usam o mesmo pacote
(`piabrota.metrics.package`), então as duas versões são sempre iguais.

## Antes do merge: o DNS

No Porkbun, crie um registro **A**, `metrics`, com o endereço de `rig.piabrota.art` (o mesmo da
piabrota2). Faça isso **antes do merge**. Sem o registro, o pedido ACME falha no deploy e o
deploy-rs desfaz a troca. Os passos estão em [`SITE.md`](SITE.md), "DNS on Porkbun".

## A primeira configuração, em ordem

1. (Opcional, evita uma corrida.) Na piabrota2, antes do merge, crie
   `/var/lib/beszel-secrets/hub.env` (root, modo 0600, numa pasta que você cria com
   `sudo install -d -m 0750 /var/lib/beszel-secrets`) com `USER_EMAIL=` e `USER_PASSWORD=`.
   Na primeira partida com dados novos, o hub cria essa conta como admin
   (`internal/migrations/initial-settings.go`). Medido: funciona.
2. Faça o merge. O deploy liga o hub e os dois agentes. Os agentes ainda não têm `KEY` e `TOKEN`:
   a unidade é **pulada**, não falha (`ConditionPathExists`), então o deploy não volta atrás.
3. Abra `https://metrics.piabrota.art`. **Sem o passo 1, crie a conta de admin logo**: enquanto não
   existe usuário, o endereço `POST /api/beszel/create-user` aceita quem chegar primeiro
   (`internal/hub/api.go:171`). Depois do primeiro usuário ele recusa
   (`internal/users/users.go:108`) e ninguém mais se registra: o hub não liga `USER_CREATION`.
4. Na página, **Add System**, duas vezes: "piabrota2" e "piabrota". A página mostra a `KEY` (chave
   pública do hub) e o `TOKEN` de cada uma.
5. Em cada máquina, escreva `/var/lib/beszel-secrets/agent.env` à mão, **root, modo 0600**:

   ```console
   sudo install -m 0600 /dev/null /var/lib/beszel-secrets/agent.env
   sudoedit /var/lib/beszel-secrets/agent.env     # duas linhas: KEY=... e TOKEN=...
   sudo systemctl restart beszel-agent
   ```

   O systemd lê o arquivo como root, antes de largar os privilégios do `DynamicUser`. Por isso
   root 0600 basta, e o agente não precisa ler o arquivo. Nada disso vai para o repositório nem
   para a store.
6. Em segundos o sistema aparece como "up".

Sem o arquivo, a unidade fica inativa (`systemctl status beszel-agent` diz que a condição falhou).
Depois de criar o arquivo, a unidade só começa com `restart` (ou no próximo boot).

## O que mostra, o que não mostra

Mostra, por máquina: CPU, memória, swap, disco, rede, temperatura quando há, e a lista de serviços
do systemd com estado.

**Por serviço (verificado no código v0.21.1 e numa execução real):** o agente coleta o estado, a
**CPU** (`CPUUsageNSec`), a **memória atual** (`MemoryCurrent`) e o **pico** (`MemoryPeak`) de cada
`*.service` (`agent/systemd.go:252-286`). Então dá para ver a memória do `hermes-agent`. Mas:

- A lista é lida **a cada 10 minutos** (`agent/systemd.go:142-146`), não ao vivo. A memória por
  serviço é um retrato, com defasagem de até 10 minutos.
- O hub guarda **só o último retrato** de cada serviço (`INSERT ... ON CONFLICT DO UPDATE` em
  `internal/hub/systems/system.go:433`). **Não há gráfico de histórico por serviço.**
- O hub mostra a memória e o pico, mas **não a compara com o `MemoryMax`** de 8G. O limite só
  aparece nos detalhes do serviço. A comparação você faz de olho.
- Os logs de serviço estão desligados (`SKIP_SYSTEMD_LOGS`): o agente não lê o journal.
- Medido na piabrota2 (um agente de teste, sem ser uma unidade): 58 serviços, e `hermes-agent` com
  641 MB atuais e pico de 942 MB.

Para a memória do `hermes-agent` contra o `MemoryMax=8G` ao longo do tempo, o mais barato é o
`kvm4-health` (a cada 30 minutos, sem custo de modelo), que já lê `MemoryCurrent` e `MemoryPeak`.
A alternativa mais pesada seria o Netdata (fechamento de 1,1 GiB no nixpkgs), que guarda histórico
por cgroup. Não está nos planos.

O D-Bus: o módulo do nixpkgs permite ao usuário `beszel-agent` chamar `ListUnits`, e a unidade
tem `PrivateUsers=true`. Rodei o agente como usuário comum e ele listou os serviços. **O teste de VM
`checks.metrics` rodou a unidade de verdade sob `PrivateUsers` e ela viu o `beszel-hub` pelo D-Bus.**

## O nginx na frente do hub

Sem basic auth: o agente da piabrota disca pelo mesmo nome, e uma senha de nginx o barraria. O hub
tem o login dele (PocketBase) e o agente tem o token. Caminhos (lidos no código):

- `/api/beszel/agent-connect`: o WebSocket do agente (`internal/hub/api.go:195`,
  `agent/client.go:221`). Cabeçalhos `X-Token` e `X-Beszel`.
- `/api/realtime`: as atualizações ao vivo da página, em eventos SSE (`apis/realtime.go` do
  PocketBase, que já manda `X-Accel-Buffering: no`).
- Login: `/api/collections/<coleção>/auth-with-password`, `request-otp`, `auth-with-otp`
  (`apis/record_auth.go:31,39,42`).

O vhost faz proxy de tudo para `127.0.0.1:8090` com os cabeçalhos de upgrade do WebSocket,
`proxy_buffering off` e `proxy_read_timeout` de 1 hora. Os três caminhos de login têm um limite
de **10 tentativas por minuto por endereço** (`limit_req_zone`, rajada de 5, resposta 429).
Cabeçalhos de segurança como no `hermes-web.nix`.

## Variáveis do hub que confirmei

Lidas em `internal/hub` e `internal/migrations` (v0.21.1). Qualquer uma também aceita o prefixo
`BESZEL_HUB_`.

| Variável | Efeito | Usada aqui |
|---|---|---|
| `USER_EMAIL`, `USER_PASSWORD` | Cria o admin na primeira partida com dados novos (`initial-settings.go:28-30`) | opcional, por `hub.env` |
| `USER_CREATION` | Só com `true` deixa criar usuário por OAuth (`collections.go:32`). Sem ela, ninguém se registra | **não**, fica desligada |
| `DISABLE_PASSWORD_AUTH` | Desliga o login por senha (`collections.go:28`). Sem OAuth configurado, você se tranca para fora | não |
| `APP_URL` | O endereço público, usado nos links dos alertas (`hub.go:131`) | sim, `https://metrics.piabrota.art` |
| `CHECK_UPDATES` | Verifica versões no GitHub; só com `true` | não |

Do agente: `HUB_URL`, `KEY`, `TOKEN` (por arquivo), `DISABLE_SSH`, `SKIP_GPU`, `SKIP_SYSTEMD_LOGS`.

## Custo

Medido nesta máquina em 2026-11-05, com os binários reais da versão fixada, rodando como usuário
comum numa pasta de rascunho:

| | |
|---|---|
| RAM do hub, parado | **34 MiB** (VmRSS 34208 kB depois de 20 s; 35516 kB depois de 60 s) |
| RAM do agente, ligado ao hub | **16,5 MiB** (VmRSS 16832 kB, igual depois de 60 s) |
| Dados do hub | 0,9 MiB com um sistema, depois de 80 s (cresce com o histórico) |
| Limites | hub `MemoryMax=256M` e `CPUWeight=20`; agente `MemoryMax=64M` e `CPUWeight=20` |
| Fechamento | o pacote tem 91,1 MiB no fechamento, dos quais 52,3 MiB são dele; glibc, tzdata e o resto costumam estar no sistema (não medi no sistema inteiro). Contra o beszel 0.18.7 do nixpkgs deste lock: **+3,11 MiB** (`dix`) |
| Disco por host | os mesmos 52 MiB, uma vez, na store |
| CPU | quase nada parado; um agente por minuto manda um pacote |

A piabrota (4 GB) cresce só pelo agente e pelo pacote. O `dix` dos dois sistemas inteiros contra
a `main` **não rodou** aqui: o sistema da piabrota são 360 derivações a compilar nesta máquina
(`max-jobs = 1`). Rode `just build` e o `dix` no CI antes do merge.

## O pacote fixado

`beszel/package.nix` fixa a versão **0.21.1** (a última do upstream em 2026-11-05; o nixpkgs deste
lock tem a 0.18.7). É uma cópia da derivação do nixpkgs (MIT), com `version`, `hash`, `vendorHash`
e `npmDepsHash` no topo. Foi uma cópia, e não um `overrideAttrs`, porque o `webui` é uma segunda
derivação que lê `finalAttrs.src`, e os testes ignorados e as tags de build mudam entre versões:
a sobrescrita repetiria quase o arquivo todo.

⚠ Este pacote **não está no `cache.nixos.org`** (verificado com `nix path-info --store`). Ele
compila no runner do GitHub, no `deploy.yml`; a VPS nunca compila, só recebe o resultado pelo
deploy-rs. Nesta máquina a compilação levou **3 min 22 s** (com os testes do Go; as dependências
do npm e do Go, buscadas na rede, levam mais cerca de 4 min na primeira vez) e usou até cerca de
**1,1 GiB** de memória do sistema (diferença da memória usada, medida de fora, com ruído).

⚠ O módulo do nixpkgs deste lock chama `beszel-hub history-sync`, um comando que a 0.21 não tem
("unknown command"): o hub nunca subiria. `metrics.nix` troca o `ExecStartPre` por
`migrate up` e `migrate history-sync`, como o nixpkgs novo faz. Quando o lock avançar, confira.

## Atualizando o pin

Hub e agente andam **juntos**: um pacote, uma versão. Nunca mude um sem o outro.

```console
# 1. a fonte (hash)
nix flake prefetch github:henrygd/beszel/vX.Y.Z --json | jq -r .hash
# 2. o npm da interface (npmDepsHash)
nix run nixpkgs#prefetch-npm-deps -- <caminho da fonte>/internal/site/package-lock.json
# 3. os módulos do Go (vendorHash): ponha lib.fakeHash, compile, copie o "got:"
nix build .#beszel
```

Troque `version`, `hash`, `npmDepsHash` e `vendorHash` no topo de `beszel/package.nix`. Compare
`checkFlags` com o `package.nix` do nixpkgs da mesma versão. Confira:

```console
nix build .#beszel && ./result/bin/beszel-agent --version
```

O método foi provado na 0.21.0: os três hashes calculados são iguais aos do nixpkgs. Quando o
nixpkgs do lock alcançar a versão, apague `beszel/` e use `pkgs.beszel`. Não há tarefa diária de
atualização.

## Desligando

Tire `piabrota.metrics.*` dos arquivos de `hosts/`. A piabrota2 perde o vhost; os dados ficam em
`/var/lib/beszel-hub`. Para apagar: `sudo rm -r /var/lib/beszel-hub /var/lib/beszel-secrets`.

## Cópia dos dados

O hub guarda tudo em `/var/lib/beszel-hub` (SQLite). Para uma cópia consistente:
`sudo systemctl stop beszel-hub`, copie a pasta, `sudo systemctl start beszel-hub`. A conta de
superusuário do PocketBase (`/_/`) não serve ao dono: o Beszel a cria com senha aleatória. Os
dados são de métricas: perdê-los custa só o histórico.

## O que não provei

- Um agente de verdade na piabrota (KVM 1), o deploy, o ACME e o navegador.
- `checks.metrics` (`beszel/test.nix`) passou nesta máquina em 2026-11-05 (107 s): o agente é
  pulado sem o arquivo, o primeiro usuário nasce uma vez, ninguém mais se registra, o nginx limita
  logins (429), o agente chega ao hub pelo WebSocket através do nginx, não abre porta e vê as
  unidades do systemd. Rodou com HTTP simples e um nome falso, então TLS e ACME seguem sem prova.
