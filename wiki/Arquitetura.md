# Arquitetura

[English](Architecture)

## As peças

| Arquivo | O que faz |
|---|---|
| `flake.nix` | O sistema `nixosConfigurations.piabrota` (nixos-26.05), o nó do deploy-rs e os `checks` do CI. |
| `configuration.nix` | A base da Hostinger: GRUB em `/dev/sda`, cloud-init, o agente QEMU, SSH. Importa os módulos abaixo. |
| `piabrota.nix` | O usuário `h0ffmann` (só chave SSH) e os pacotes base. |
| `tools.nix` | Ferramentas de linha de comando leves e os limites de disco e memória. |
| `deploy.nix` | O usuário `deploy` que o CI usa, a coleta de lixo e o limite de gerações de boot. |
| `loco.nix` | Apps [Loco](https://loco.rs) como serviços systemd isolados, com SQLite, nginx e HTTPS. |
| `site.nix` | O site estático de `site/` (Gleam e Lustre, pré-renderizado no build; a VPS recebe só o HTML e o CSS) em www.piabrota.art, por HTTP e HTTPS; `piabrota.art` redireciona para o `www`. |

## Do pull request à VPS

```
PR ──► ci.yml: nix flake check (builda o sistema), nixpkgs-fmt, statix, deadnix, shellcheck
merge na main ──► deploy.yml: o runner builda, o deploy-rs copia via SSH e ativa
                    └─► se o SSH não responder em 60 s, a VPS volta sozinha (magic rollback)
              └─► freeze.yml: a lista de pacotes da VPS no resumo da execução
              └─► cves.yml: relatório do vulnix sobre o sistema buildado (e toda segunda)
              └─► wiki.yml: copia wiki/ para este wiki (se wiki/ mudou)
```

A VPS não compila nada: ela baixa do `cache.nixos.org` o que o cache tem. Cada deploy é uma
geração nova, e o GRUB guarda as cinco últimas.

## O que não pode quebrar

O agente QEMU, o cloud-init, o SSH com a chave do `h0ffmann`, o GRUB em `/dev/sda`, o usuário
`deploy` e o magic rollback. Sem eles, a Hostinger não consegue provisionar a máquina ou o CI
não consegue fazer o deploy. A lista completa está em [`AGENTS.md`](https://github.com/piabrota/nix-os/blob/main/AGENTS.md), seção "Do not
break the machine".
