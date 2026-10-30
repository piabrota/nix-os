# nix-os

[English](Home-EN)

A configuração NixOS de uma VPS pequena e em produção: um guest KVM da Hostinger (plano KVM 1:
1 vCPU, 4 GB de RAM, 50 GB de disco). Tudo passa pelo GitHub: um pull request builda o sistema
inteiro no CI, e o merge na `main` faz o deploy.

Este wiki é um mapa. As regras e os passos a passo ficam no repositório, e cada página aqui aponta
para eles.

## Páginas

- [Arquitetura](Arquitetura): as peças e como uma mudança chega à VPS.
- [Operação](Operacao): o dia a dia (buildar, conferir, voltar atrás, ligar o site, adicionar um app).
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

As páginas vêm da pasta [`wiki/`](https://github.com/piabrota/nix-os/tree/main/wiki) do repositório
e são copiadas para cá a cada merge. Não edite o wiki direto: a próxima cópia apaga a edição.
