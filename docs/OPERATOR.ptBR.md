# A conta operator

[English](OPERATOR.md)

`operator` deixa a sessão de um agente de código (o Claude Code no computador do dono) olhar um
host e fazer nele um conjunto pequeno e fixo de coisas, sem root. É o `observer` mais uma lista de
comandos permitidos no sudo. Todo host a recebe (`configuration.nix` importa `operator.nix`); a
lista de cada host tem só as units que ele tem.

| Conta | Lê | Muda |
|---|---|---|
| `observer` | o log e o estado de toda unit, `ps`, `free`, `df` | nada |
| `operator` | o mesmo, e arquivos em `HERMES_HOME`, menos segredos | só os comandos abaixo |
| `h0ffmann` | tudo | tudo (sudo sem senha) |

## O que ela pode rodar

Rode `op-help` na máquina para ver a lista daquele host.

| Comando | Em | Faz |
|---|---|---|
| `sudo systemctl restart <unit>.service` | `hermes-agent`, `hermes-backend`, `nginx`, `pgx`, `loco-<app>`, as que o host tiver | reinicia uma unit de longa duração |
| `sudo systemctl start <unit>.service` | `nix-gc`, `nix-optimise`, `hermes-github-token`, `loco-<app>-backup`, as que o host tiver | roda agora o job de um timer |
| `sudo -u hermes op-hermes <cmd>` | hosts com Hermes | `status`, `doctor`, `insights`, `logs`, `cron list`, `cron status`, `sessions list`, `sessions stats`, `cron run\|pause\|resume <job-id>` |
| `sudo -u hermes op-peek <caminho> [linhas]` | hosts com Hermes | `ls -la` de um diretório ou as últimas linhas (200 por padrão) de um arquivo em `HERMES_HOME` |

Qualquer outra coisa pelo sudo pede senha, e `operator` não tem senha. Ela não faz deploy, não
muda a configuração, não para units e não lê `/var/lib/*-secrets`.

`op-peek` resolve os links simbólicos antes, recusa caminhos fora de `HERMES_HOME` e recusa
`.env*`, `auth*` e qualquer nome com `secret`, `token`, `credential`, `password`, `.key` ou `.pem`.
`operator` não está no grupo `hermes` de propósito: o módulo NixOS do Hermes deixa o `.env`, que
guarda o token do Claude e os das plataformas de chat, legível por esse grupo.

## Configuração no computador do dono

O par de chaves é `~/.ssh/piabrota_operator`; a metade pública é `keys/operator.pub`. Ponha uma
entrada por host em `~/.ssh/config`, junto das do observer:

```sshconfig
Host piabrota-operator
  HostName <IPv4 do piabrota>
  User operator
  IdentityFile ~/.ssh/piabrota_operator
  IdentitiesOnly yes
  UserKnownHostsFile ~/.ssh/known_hosts.piabrota
  StrictHostKeyChecking yes
  ConnectTimeout 10

Host kvm4-operator
  HostName hermes.piabrota.art
  User operator
  IdentityFile ~/.ssh/piabrota_operator
  IdentitiesOnly yes
  ConnectTimeout 10
```

Depois, no Claude Code: `ssh piabrota-operator op-help`.

## Regras para um agente

A seção "Deploy" do AGENTS.md vale: um agente usa `operator` só para uma ação que o dono pediu,
roda essa ação e nada mais, e diz o que rodou. Uma correção na configuração continua indo num pull
request.

## Desligar

Esvazie `keys/operator.pub` (só comentários) e faça o merge: a conta fica, mas nenhuma chave a
abre. Para removê-la, tire `./operator.nix` de `configuration.nix`.
