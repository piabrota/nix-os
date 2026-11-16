# nix-os

[English](Home-EN)

A configuração NixOS de duas VPSs da Hostinger. Cada mudança é um pull request. Um merge na `main`
builda os dois sistemas e faz o deploy deles.

- A `piabrota` (KVM 1: 1 vCPU, 4 GB de RAM) serve o site público.
- A `piabrota2` (KVM 4: 4 vCPU, 16 GB de RAM) roda o Hermes Agent, o painel dele, o OpenRig, o PGX e
  os outros serviços web.

O OpenRig é o motor da fábrica de software aberta da piabrota. A [Fábrica](Fabrica) diz o que ele
faz hoje e o que vai fazer.

Este wiki é um mapa. As regras e os procedimentos ficam no repositório. Cada página aqui aponta para
eles.

## Páginas

- [Arquitetura](Arquitetura): as peças e como uma mudança chega à VPS.
- [Operação](Operacao): o dia a dia (buildar, conferir, voltar atrás, ligar o site, adicionar um app).
- [Hermes](Hermes): como o Hermes Agent roda aqui (a unidade, os modelos, os limites, o reinício num deploy) e onde fica a configuração dele.
- [Fábrica](Fabrica): a fábrica de software aberta, com o OpenRig como motor (as etapas, quem faz cada uma, o estado de hoje e as regras que ficam).
- [Runtimes](Runtimes): os runtimes do OpenRig (Claude Code, Codex, Pi, omp, terminal, stub e os harnesses da comunidade): prós, contras e quais a máquina roda.
- [A tese](Thesis): o rig que escreve um projeto de graduação da UFRJ em português, seção por seção, com quatro portões e um PDF (nenhum seat o rodou ainda).
- [Reels](Reels): a Fábrica de Reels, a rig do OpenRig que faz vídeos de 15 s e 30 s para o Instagram, com o roteiro como fonte e só Claude (sem API de mídia).
- [Maquetes](Maquetes): três direções para a home de piabrota.art, geradas em Nix.

## Endereços

O [README](https://github.com/piabrota/nix-os#every-piabrotaart-address) tem a lista completa.

- Na `piabrota` (KVM 1): [www.piabrota.art](https://www.piabrota.art/), o site, e
  [skills.piabrota.art](https://skills.piabrota.art/), o site das skills. `piabrota.art` leva ao
  `www`.
- Na `piabrota2` (KVM 4), com login: [hermes.piabrota.art](https://hermes.piabrota.art/), o painel
  do Hermes, e [rig.piabrota.art](https://rig.piabrota.art/), a interface do OpenRig.
- Na `piabrota2`, abertos: [metrics.piabrota.art](https://metrics.piabrota.art/), as métricas das
  duas máquinas, e os sites dos projetos (room, grid, proof, pirsig, wave, closed, hffmnn, marola).

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
