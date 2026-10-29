# Operação

[English](Operations)

Comandos da raiz do repositório, numa máquina com Nix (não precisa ser NixOS). Para ver todas as
receitas: `just`.

| Para | Rode |
|---|---|
| Buildar o sistema sem fazer deploy | `just build` |
| Rodar o que o CI roda | `just check` |
| Ver quanto uma mudança acrescenta ao sistema | `nix run nixpkgs#dix -- <sistema-antigo> <sistema-novo>` |
| Ver CPU, RAM, disco e a geração da VPS | `just remote-specs` |
| Listar os pacotes da VPS com o tamanho de cada um | `just remote-freeze` |
| Relatório de CVEs do sistema | `just cves` |

## Fazer uma mudança

Abra um branch, faça a mudança e abra um PR. O CI builda o sistema; o merge faz o deploy. Diga no
PR o que mudou no sistema (o resumo do `dix`). Ninguém faz deploy direto da própria máquina,
a não ser no primeiro deploy ([`docs/DEPLOY.md`](https://github.com/piabrota/nix-os/blob/main/docs/DEPLOY.md)).

## Voltar atrás

- Na VPS: `sudo nixos-rebuild switch --rollback`, ou escolha uma geração mais antiga no menu do
  GRUB pelo console serial.
- Depois, reverta o commit na `main`. Se não reverter, o próximo deploy traz a mudança de volta.

## O site em www.piabrota.art

O site está ligado. Os dois nomes, `piabrota.art` e `www`, precisam apontar para a VPS. Os passos do DNS estão em
[`docs/SITE.md`](https://github.com/piabrota/nix-os/blob/main/docs/SITE.md).

## Adicionar um app

Empacote o app no flake dele, crie o registro DNS, ponha os segredos na VPS e declare o app aqui:
[`docs/LOCO.md`](https://github.com/piabrota/nix-os/blob/main/docs/LOCO.md).
