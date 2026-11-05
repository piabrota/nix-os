# nix-os

[English](Home-EN)

A configuração NixOS de duas VPSs em produção, guests KVM da Hostinger. A `piabrota` (plano KVM 1:
1 vCPU, 4 GB de RAM, 50 GB de disco) serve a web pública. A `piabrota2` (plano KVM 4) roda o Hermes
Agent, o painel dele, o OpenRig e o PGX. Medido na `piabrota2` em 2026-11-04: 4 vCPU, 15,6 GiB de RAM, 196,8 GiB
de disco (6 % em uso) e 7,8 GiB de swap; em repouso, o `hermes-agent` usa uns 0,4 GiB, o
`hermes-backend` uns 0,55 GiB e o `pgx` uns 0,1 GiB. Tudo passa pelo GitHub: um pull request roda
as verificações do CI, e o merge na `main` builda e faz o deploy de cada sistema.

O OpenRig é o motor da fábrica de software aberta que fica por trás da piabrota. A [Fábrica](Fabrica)
diz o que ele faz hoje e o que ainda vai fazer: os seats dele ainda não rodaram nenhuma tarefa.

Este wiki é um mapa. As regras e os passos a passo ficam no repositório, e cada página aqui aponta
para eles.

## Páginas

- [Arquitetura](Arquitetura): as peças e como uma mudança chega à VPS.
- [Operação](Operacao): o dia a dia (buildar, conferir, voltar atrás, ligar o site, adicionar um app).
- [Hermes](Hermes): como o Hermes Agent roda aqui (a unidade, os modelos, os limites, o reinício num deploy) e onde fica a configuração dele.
- [Fábrica](Fabrica): a fábrica de software aberta, com o OpenRig como motor (as etapas, quem faz cada uma, o estado de hoje e as regras que ficam).
- [Runtimes](Runtimes): os runtimes do OpenRig (Claude Code, Codex, Pi, omp, terminal, stub e os harnesses da comunidade): prós, contras e quais a máquina roda.
- [A tese](Thesis): o rig que escreve um projeto de graduação da UFRJ em português, seção por seção, com quatro portões e um PDF (nenhum seat o rodou ainda).
- [Maquetes](Maquetes): três direções para a home de piabrota.art, geradas em Nix.

## Endereços

Todos os endereços piabrota.art que este repositório serve. A tabela completa, com o status de cada
um, está na [seção "Every piabrota.art address" do README](https://github.com/piabrota/nix-os#every-piabrotaart-address).

- Na `piabrota` (KVM 1), abertos: [www.piabrota.art](https://www.piabrota.art/) (o site; também
  `/index/`, `/paths/`, `/hosts/`, `/hermes/` e `/skills/`) e `/nixos` (leva ao repositório).
  `piabrota.art` redireciona para o `www`.
- Na `piabrota`, com uma senha: [www.piabrota.art/notes](https://www.piabrota.art/notes), o app Loco `notes`.
- Na `piabrota2` (KVM 4), com login (basic auth): [hermes.piabrota.art](https://hermes.piabrota.art/), o
  painel do Hermes, e [rig.piabrota.art](https://rig.piabrota.art/), a interface do OpenRig.
- `paperclip.piabrota.art`: desligado desde 2026-11-04, não responde.

## No repositório

| Para | Leia |
|---|---|
| As regras para quem muda o repositório (pessoas e agentes) | [`AGENTS.md`](https://github.com/piabrota/nix-os/blob/main/AGENTS.md) |
| Como o deploy funciona e a configuração inicial | [`docs/DEPLOY.md`](https://github.com/piabrota/nix-os/blob/main/docs/DEPLOY.md) |
| O site estático em www.piabrota.art e o DNS na Porkbun | [`docs/SITE.md`](https://github.com/piabrota/nix-os/blob/main/docs/SITE.md) |
| Adicionar um app Loco | [`docs/LOCO.md`](https://github.com/piabrota/nix-os/blob/main/docs/LOCO.md) |
| Rodar a sua própria VPS a partir de um fork | [`docs/FORK.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/FORK.ptBR.md) |
| Hermes Agent nesta máquina | [`docs/HERMES.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/HERMES.ptBR.md), e a configuração dele em YAML em [www.piabrota.art/hermes](https://www.piabrota.art/hermes) |
| As figuras como páginas interativas | [www.piabrota.art/figures](https://www.piabrota.art/figures/) |

As páginas vêm da pasta [`wiki/`](https://github.com/piabrota/nix-os/tree/main/wiki) do repositório
e são copiadas para cá a cada merge. Não edite o wiki direto: a próxima cópia apaga a edição.
