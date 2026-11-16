# Reels

[English](Reels-EN)

A Fábrica de Reels é uma rig do [OpenRig](https://github.com/mvschwarz/openrig) que faz um vídeo
vertical de 15 s ou 30 s (1080x1920) para o Instagram. O guia completo é o
[`docs/REELS.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/REELS.ptBR.md). Os fatos
dele foram medidos na `piabrota2` em 2026-11-05 (o kit) e em 2026-11-08 (o Blender) ou lidos no
código, e nenhuma execução real da rig aconteceu ainda.

## Em resumo

- **Só Claude.** Nenhuma API de imagem, vídeo, voz ou música. Cada pixel e cada som vêm de código
  que um seat roda na máquina (`ffmpeg`, `resvg`, Scala).
- **O roteiro vem primeiro.** Um arquivo, `screenplay.json`, é a fonte. O `reel lint` confere as
  regras e o `reel approve` grava o SHA-256 dele. Sem aprovação válida, nada depois do roteiro roda.
- **Uma equipe de cinema, cinco seats.** O pod `crew`: o diretor criativo (`creative-director`)
  escreve o roteiro, o produtor-editor (`producer-editor`) aprova e monta, o artista 3D (`artist-3d`)
  faz os planos 3D, o diretor musical (`music-director`) faz o som e o QA confere. O produtor
  executivo é o dono, um humano, e não é um seat. Todos rodam `omp`.
- **Cinco fases, dois seats por vez.** A unit `openrig` tem `MemoryMax=2G`: história e visual,
  imagem, planos 3D, som, e conferir e publicar, com os comandos `rig` do `rig.yaml`.
- **Medido:** o exemplo de 30 s renderiza em 105 a 120 s, com pico de 540 MiB num `ffmpeg`, e dá 5,3
  MiB. O de 15 s: 47 a 65 s, 508 MiB, 2,8 MiB.
- **Desligada.** A opção `piabrota.openrig.reels.enable` está desligada. Ligada, ela põe o kit, duas
  fontes (a exceção do dono para "sem fontes"), as pastas e a outbox
  `/var/lib/rig-outbox/reels-fabric`.
- **Blender, outra opção.** `piabrota.openrig.reels.blender.enable`, desligada: o Blender sem janela,
  a exceção do dono para "sem GUI" (2026-11-08). Precisa da opção acima. O `reel blender` renderiza
  só com o Cycles na CPU: o EEVEE não funciona nesta máquina. Um quadro de 1080x1920 levou 8,3 s e
  536 MiB. Os 55 minutos de um reel de 15 s são uma extrapolação, não uma medida.

## O que não está provado

Uma execução real dos seats, a aceitação do Instagram, e o som: ninguém o ouviu. Um render do Blender
dentro da unit `openrig` e com o Blender 5.1.1, a versão do nixpkgs fixado, também não rodou. Sem
vídeo filmado, sem foto, sem voz e sem música de verdade: o visual é tipografia sobre uma folha
escura, e os planos 3D são cenas simples. Vários números (a área segura, a velocidade de leitura, a
sonoridade) são palpites e estão listados em "Os números não verificados" do guia.
