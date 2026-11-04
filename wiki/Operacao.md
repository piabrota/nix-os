# Operação

[English](Operations)

Comandos da raiz do repositório, numa máquina com Nix (não precisa ser NixOS). Para ver todas as
receitas: `just`.

| Para | Rode |
|---|---|
| Buildar o sistema sem fazer deploy | `just build` |
| Rodar o que o CI roda | `just check` |
| Ver quanto uma mudança acrescenta ao sistema | `nix run nixpkgs#dix -- diff <sistema-antigo> <sistema-novo>` |
| Ver CPU, RAM, disco e a geração de uma VPS | `just remote-specs` |
| Listar os pacotes de uma VPS com o tamanho de cada um | `just remote-freeze` |
| Relatório de CVEs do sistema | `just cves` |

## As duas máquinas

A `piabrota` (KVM 1) serve a web pública. A `piabrota2` (KVM 4) roda o Hermes, o painel dele e o PGX.
As receitas `just remote-*` leem `DEPLOY_HOST` e, sem ele, usam `piabrota.art`, a máquina
`piabrota`. Para a `piabrota2`, ponha o endereço dela em `DEPLOY_HOST`:

```console
DEPLOY_HOST=<endereço da piabrota2> just remote-specs         # CPU, RAM, disco e geração
DEPLOY_HOST=<endereço da piabrota2> just remote-health        # memória, MemoryPeak contra MemoryMax, disco e CPU, com as unidades do Hermes
DEPLOY_HOST=<endereço da piabrota2> just remote-hermes-check  # os add-ons do Hermes do último deploy estão ativos
```

O `remote-health` roda o script da skill `kvm4-health`, o mesmo relatório que o Hermes lê com o
comando `kvm4-health` na máquina.

## Fazer uma mudança

Abra um branch, faça a mudança e abra um PR. O CI builda o sistema; o merge faz o deploy. Diga no
PR o que mudou no sistema (o resumo do `dix`). Ninguém faz deploy direto da própria máquina,
a não ser no primeiro deploy ([`docs/DEPLOY.md`](https://github.com/piabrota/nix-os/blob/main/docs/DEPLOY.md)).

## Voltar atrás

- Numa VPS: `sudo nixos-rebuild switch --rollback`, ou escolha uma geração mais antiga no menu do
  GRUB pelo console serial.
- Depois, reverta o commit na `main`. Se não reverter, o próximo deploy traz a mudança de volta.

## O site em www.piabrota.art

O site está ligado. Os dois nomes, `piabrota.art` e `www`, precisam apontar para a VPS `piabrota`
(KVM 1); o `hermes.piabrota.art` aponta para a `piabrota2`. Os passos do DNS estão em
[`docs/SITE.md`](https://github.com/piabrota/nix-os/blob/main/docs/SITE.md).

## Adicionar um app

Empacote o app no flake dele, crie o registro DNS, ponha os segredos na VPS e declare o app aqui:
[`docs/LOCO.md`](https://github.com/piabrota/nix-os/blob/main/docs/LOCO.md).
