# PGX: Postgres sem um servidor PostgreSQL

[English](PGX.md)

O [PGX](https://pgx.dev) ([pgrundev/pgx](https://github.com/pgrundev/pgx)) é um banco compatível
com Postgres escrito em Rust: um processo que fala o protocolo e o SQL do PostgreSQL 18. Esta
máquina o roda como a unit `pgx` (`pgx.nix`) para o que precisa de Postgres aqui, hoje o store do
rax no KubeSolo, no lugar de um servidor PostgreSQL ou de um container Docker.

## O que ele é, e o que não é

| | |
|---|---|
| Versão | v0.1.2 (2026-10-27), primeira versão em 2026-10-21 |
| Licença | AGPL-3.0. Roda aqui sem modificação; uma mudança no PGX servida a outros teria de ser publicada |
| Compatibilidade | PostgreSQL 18.6: 219 dos 231 arquivos da suíte de regressão do próprio PostgreSQL idênticos byte a byte, os outros 12 diferem só no texto do `EXPLAIN` (números do projeto). Os testes do store do rax passam nele (abaixo) |
| O que não tem | Extensões em C (PostGIS, TimescaleDB), PL/Python, PL/Perl; o `pg_dump` não vem na release |
| O próprio aviso | "For disposable databases, not production data": o projeto diz que a v0.1 "não é um primário de produção, um sistema de registro, nem um banco com HA ou PITR" |

O perfil padrão do PGX desliga o `fsync`. Este módulo inicializa com `--durability full` (os
padrões do PostgreSQL: `fsync`, `synchronous_commit` e `full_page_writes` ligados), o que o teste
confere. Mesmo assim: **dado que você quer guardar vai para o SQLite**, como fazem os apps Loco
([`LOCO.md`](LOCO.md)). Aqui o PGX guarda stores que dá para refazer, como as tasks do rax.

## Custo

| | |
|---|---|
| Closure | **≈ +99 MiB**: a release (o motor, 56 MiB, o CLI e o `share/`: fusos, scripts do contrib e o cluster base de 39 MiB). As bibliotecas dele, glibc e libstdc++, já estão no sistema. ⚠ `dix` não rodou: o sistema é x86_64 e a máquina daqui constrói aarch64 (medido na release aarch64, 99,3 MiB) |
| Download | A release não está no cache.nixos.org: o runner baixa (32 MB) do GitHub e o deploy-rs copia para a VPS uma vez por versão. Nada é compilado |
| RAM | 45 MiB parado, 68 MiB depois dos testes do store do rax (medido num container, 2026-10-30). `MemoryMax=256M`; o vigia de memória do PGX lê esse limite e recusa consultas (SQLSTATE 53200) antes de o kernel matá-lo |
| Disco, em uso | `/var/lib/pgx`: o cluster base (39 MiB) mais os bancos e o WAL deles ⚠ o WAL pode crescer até `max_wal_size` (1 GB, padrão do PostgreSQL) com muita escrita |
| CPU | Parado quando não há o que fazer; sem limite na unit |

## O que o `pgx.nix` faz

- Empacota a release (`pgx/package.nix`): o `autoPatchelfHook` aponta os dois binários para a
  glibc e a libstdc++ do store. O nixpkgs não tem pgx.
- Roda `pgx serve` como o usuário `pgx`, com o estado em `/var/lib/pgx` (modo 0700) e o socket em
  `/run/pgx` (modo 0750, só o grupo `pgx`). Na primeira partida copia o cluster base
  (`pgx init --port 5432 --durability full`) e gera a senha do superusuário, que fica em
  `/var/lib/pgx/config.json`.
- Escuta em todos os endereços, porta 5432: os pods chegam ao host pelo `cni0`, que só aparece
  depois que o KubeSolo sobe. **O firewall não abre porta nenhuma**, e o `pg_hba.conf`, reescrito
  a cada partida, admite o socket (só o grupo `pgx`) e, por TCP com a senha (`scram-sha-256`), o
  loopback e, com o KubeSolo ligado, os pods (`10.42.0.0/16`).
- A mesma sandbox dos apps Loco: sem capabilities, sistema só de leitura, `/tmp` e dispositivos
  privados, chamadas de sistema `@system-service`.
- Põe no path um comando `pgx` que roda o CLI como o usuário `pgx`.

O `checks.pgx` (`pgx/test.nix`) sobe uma VM com o módulo, cria um banco, conecta por TCP com a
senha e sem ela, reinicia a unit, acha a linha de novo e lê o limite de memória no log. A CI roda
com `nix flake check`.

## Usando

Na VPS:

```console
pgx ls                    # os bancos
pgx create ax             # um banco
pgx url ax                # a URL dele, com a senha: postgres://postgres:…@127.0.0.1:5432/ax
pgx drop ax               # apaga
```

Qualquer cliente ou driver PostgreSQL funciona com essa URL. De um pod, troque `127.0.0.1` pelo
endereço do `cni0` no host (10.42.0.1 ⚠ confira com `ip -4 -br addr show cni0`). O rax no
KubeSolo pega a URL de um Secret: [`KUBESOLO.ptBR.md`](KUBESOLO.ptBR.md), "Rodar, chegar, tirar".

**Testado com o rax**: `cargo test -p rax-store` do piabrota/rax com `RAX_TEST_POSTGRES_URL`
apontando para o PGX 0.1.2, 11 de 11 (a suíte de conformidade, criação concorrente do schema,
advisory locks, renovação e tomada de lease, `ON CONFLICT`, `FOR UPDATE`).

## Backups

Nenhum. A release não traz `pg_dump`, e o dado aqui é para ser refeito. Se isso mudar, copie com
`pg_dump` de outra máquina por um túnel SSH até a porta 5432, ou leve o dado para o SQLite.

## Atualizando

Troque `version` e os dois hashes em `pgx/package.nix` (os arquivos `.sha256` da release trazem
em hex; `nix hash convert --to sri sha256:<hex>`). O diretório de dados está no formato do
PostgreSQL 18 e fica; leia as notas da release para o resto.

## Desligando

Ponha `piabrota.pgx.enable = false` no `configuration.nix` e faça o merge: a unit e a release
saem do sistema. O `/var/lib/pgx` fica no disco; apague à mão (`sudo rm -r /var/lib/pgx`) quando
não servir mais. O pod do rax então não alcança o store até ganhar outro.

## Fontes

O README do projeto, `docs/pgx/layout.md`, `crates/bin/pgx/src/conf.rs` (o perfil e o
`pg_hba.conf` que ele escreve) e `crates/bin/pgx/src/cli.rs` (os comandos e as variáveis
`PGX_*`), na v0.1.2. Medições: este repositório, 2026-10-30.
