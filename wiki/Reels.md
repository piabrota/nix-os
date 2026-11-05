# Reels

[English](Reels-EN)

A Fábrica de Reels é uma rig do [OpenRig](https://github.com/mvschwarz/openrig) que faz um vídeo
vertical de 15 s ou 30 s (1080x1920) para o Instagram. O guia completo é o
[`docs/REELS.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/REELS.ptBR.md). Os fatos
dele foram medidos na `piabrota2` em 2026-11-05 ou lidos no código, e nenhuma execução real da rig
aconteceu ainda.

## Em resumo

- **Só Claude.** Nenhuma API de imagem, vídeo, voz ou música. Cada pixel e cada som vêm de código
  que um seat roda na máquina (`ffmpeg`, `resvg`, `jq`, shell).
- **O roteiro vem primeiro.** Um arquivo, `screenplay.json`, é a fonte. O `reel lint` confere as
  regras e o `reel approve` grava o SHA-256 dele. Sem aprovação válida, nada depois do roteiro roda.
- **Cinco seats, dois pods.** `story` (o writer escreve, o script editor revisa e aprova) e `studio`
  (o director planeja, o maker monta, o QA confere). Todos rodam `omp`.
- **Três fases, dois seats por vez.** A unit `openrig` tem `MemoryMax=2G`: story, studio e QA, com
  os comandos `rig` do `rig.yaml`.
- **Medido:** o exemplo de 30 s renderiza em 105 a 120 s, com pico de 540 MiB num `ffmpeg`, e dá 5,3
  MiB. O de 15 s: 47 a 65 s, 508 MiB, 2,8 MiB.
- **Desligada.** A opção `piabrota.openrig.reels.enable` está desligada. Ligada, ela põe o kit, duas
  fontes (a exceção do dono para "sem fontes"), as pastas e a outbox
  `/var/lib/rig-outbox/reels-fabric`.

## O que não está provado

Uma execução real dos seats, a aceitação do Instagram, e o som: ninguém o ouviu. Sem vídeo filmado,
sem foto, sem voz e sem música de verdade: o visual é tipografia sobre uma folha escura. Vários
números (a área segura, a velocidade de leitura, a sonoridade) são palpites e estão listados em
"Os números não verificados" do guia.
