# nix-os

[English](Home-EN)

A configuração NixOS de duas VPSs em produção, guests KVM da Hostinger. A `piabrota` (plano KVM 1:
1 vCPU, 4 GB de RAM, 50 GB de disco) serve a web pública. A `piabrota2` (plano KVM 4) roda o Hermes
Agent, o painel dele e o PGX. Medido na `piabrota2` em 2026-11-04: 4 vCPU, 15,6 GiB de RAM, 196,8 GiB
de disco (6 % em uso) e 7,8 GiB de swap; em repouso, o `hermes-agent` usa uns 0,4 GiB, o
`hermes-backend` uns 0,55 GiB e o `pgx` uns 0,1 GiB. Tudo passa pelo GitHub: um pull request roda
as verificações do CI, e o merge na `main` builda e faz o deploy de cada sistema.

Este wiki é um mapa. As regras e os passos a passo ficam no repositório, e cada página aqui aponta
para eles.

## Páginas

- [Arquitetura](Arquitetura): as peças e como uma mudança chega à VPS.
- [Operação](Operacao): o dia a dia (buildar, conferir, voltar atrás, ligar o site, adicionar um app).
- [Hermes](Hermes): como o Hermes Agent roda aqui (a unidade, os modelos, os limites, o reinício num deploy) e onde fica a configuração dele.
- [Maquetes](Maquetes): três direções para a home de piabrota.art, geradas em Nix.

## No repositório

| Para | Leia |
|---|---|
| As regras para quem muda o repositório (pessoas e agentes) | [`AGENTS.md`](https://github.com/piabrota/nix-os/blob/main/AGENTS.md) |
| Como o deploy funciona e a configuração inicial | [`docs/DEPLOY.md`](https://github.com/piabrota/nix-os/blob/main/docs/DEPLOY.md) |
| O site estático em www.piabrota.art e o DNS na Porkbun | [`docs/SITE.md`](https://github.com/piabrota/nix-os/blob/main/docs/SITE.md) |
| Adicionar um app Loco | [`docs/LOCO.md`](https://github.com/piabrota/nix-os/blob/main/docs/LOCO.md) |
| Rodar a sua própria VPS a partir de um fork | [`docs/FORK.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/FORK.ptBR.md) |
| Kubernetes nesta máquina | [`docs/KUBERNETES.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/KUBERNETES.ptBR.md), [`docs/MICROK8S.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/MICROK8S.ptBR.md) |
| Hermes Agent nesta máquina | [`docs/HERMES.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/HERMES.ptBR.md), e a configuração dele em YAML em [www.piabrota.art/hermes](https://www.piabrota.art/hermes) |

As páginas vêm da pasta [`wiki/`](https://github.com/piabrota/nix-os/tree/main/wiki) do repositório
e são copiadas para cá a cada merge. Não edite o wiki direto: a próxima cópia apaga a edição.
