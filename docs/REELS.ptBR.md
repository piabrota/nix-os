# A Fábrica de Reels

Os arquivos são `openrig/specs/rigs/reels-fabric/`, `openrig/specs/agents/reels-*/`, `reels/` (o kit
`reel`), as opções `piabrota.openrig.reels.enable` e `piabrota.openrig.reels.blender.enable` em
`openrig.nix` e esta página. As páginas `Reels` do wiki resumem tudo. Os fatos aqui foram medidos na
`piabrota2` em 2026-11-05 (o kit) e em 2026-11-08 (o Blender) ou lidos no código. O que não está
provado fica em "O que não está provado".

## O que é

A Fábrica de Reels é uma rig do [OpenRig](OPENRIG.md) que faz um vídeo vertical, de 15 s ou 30 s,
1080x1920, para os Reels do Instagram. Cinco seats trabalham como uma equipe de cinema, num só pod,
o `crew` (veja "A equipe"). O diretor criativo escreve o roteiro. O produtor-editor o aprova e monta
o reel. O artista 3D faz os planos 3D, o diretor musical faz o som e o QA confere o arquivo. Os seats
usam um só kit, o `reel`, feito de shell POSIX, `jq`, `ffmpeg` e `resvg`. Os planos 3D precisam do
Blender, que é uma segunda opção e está desligada (veja "Cenas 3D com o Blender").

A rig é só uma definição. As opções estão desligadas, ninguém inicia a rig, e o dono decide quando
testar.

## As restrições do dono

A ordem do dono (2026-11-05): "Create a comprehensive Reels Fabric to generate high quality videos,
in Instagram format, 30 seconds, defined as a rig. It must not use generative video or media APIs:
Claude only. Reels configs are 15 s or 30 s. The screenplay must be a first-class citizen."

- **Só Claude.** O único modelo é o Claude (Sonnet, pela assinatura, como nas outras rigs). Nenhum
  serviço faz imagem, vídeo, voz ou música. Sem vídeo de banco e sem download. Código que um seat roda
  na máquina faz cada pixel e cada som.
- **15 s ou 30 s, 1080x1920, 30 fps.** O `reels/profile.json` não tem outro formato.
- **O roteiro vem primeiro.** Um arquivo, `screenplay.json`, é a fonte do reel. Todo outro arquivo
  vem dele e cita os ids dos beats. Nada depois do roteiro roda se ele não estiver aprovado.

## O roteiro

`screenplay.json`, schema `reels.screenplay/1`. O topo tem `slug`, `title`, `format` (15 ou 30),
`logline`, `audience`, `language`, `loop` (true ou false), `claims`, `look` (`style`: `piabrota`,
`paper` ou `mono`) e `music` (`preset`, `bpm`). `beats` é a lista de beats. Um beat tem:

|Campo|Significado|
|---|---|
|`id`|`b01`, `b02`, em ordem|
|`t_in`, `t_out`|Segundos. Os beats se tocam, o primeiro começa em 0 e o último termina em `format`.|
|`role`|`hook`, `setup`, `turn`, `proof`, `payoff`, `cta` ou `loop`|
|`visual`|`describe` (em palavras), `scene` e `params`. As cenas são `title_card`, `big_number`, `bullet_reveal`, `quote`, `split_compare`, `timeline`, `diagram_reveal`, `kinetic_text` e `outro_loop`.|
|`text`|As linhas na tela. `*palavra*` marca o destaque.|
|`sound`|`music` (`on`, `low`, `off`), `sfx` (`{name, at}`: `whoosh`, `tick`, `hit`, `riser`, `pop`) e `silence`|
|`transition`, `transition_s`|Como o beat entra, por exemplo `cut`, `fade` ou `slideleft`|
|`claims`, `note`|Os ids das afirmações que o beat faz, e uma nota|

Toda afirmação (`claims`) tem `id`, `text`, `source` e `status` (`own`, `sourced` ou `needs-check`; o
lint recusa `needs-check`). Não existe campo `vo`: a locução está desligada na v1 e o lint rejeita o
campo enquanto `voice` for false no perfil.

Um exemplo real. É o topo de `reels/examples/30/screenplay.json` e o primeiro beat. As outras
afirmações e os outros sete beats foram cortados.

```json
{
  "schema": "reels.screenplay/1",
  "slug": "marola-praia-30",
  "title": "A praia boa hoje? Ou sem dados.",
  "format": 30,
  "language": "pt-BR",
  "loop": true,
  "claims": [
    { "id": "c5", "text": "A marola diz que praia está boa para nadar hoje e a melhor hora de amanhã", "source": "marola.dev, página inicial (resumo do dono, 2026-11-03)", "status": "sourced" }
  ],
  "look": { "style": "piabrota" },
  "music": { "preset": "pulse", "bpm": 96 },
  "beats": [
    {
      "id": "b01", "t_in": 0, "t_out": 2.8, "role": "hook",
      "visual": { "describe": "Dark sheet. The question lands word by word in big type, one word in red.", "scene": "kinetic_text", "params": {} },
      "text": ["Essa praia está boa", "pra *nadar* hoje?"],
      "sound": { "music": "on", "sfx": [{ "name": "hit", "at": 0.0 }] },
      "transition": "cut",
      "claims": ["c5"]
    }
  ]
}
```

As palavras na tela ficam no `language`. Os arquivos e as mensagens dos seats ficam em inglês.

## O portão

O `reel lint` confere o schema e as regras. Um erro bloqueia a aprovação. Um aviso não bloqueia. As
regras principais:

- Os beats são contíguos e terminam em 15 ou 30 s. Um beat tem no mínimo 0,8 s.
- O primeiro beat é o gancho (`hook`). Termina até 3 s e deve ter texto.
- A velocidade de leitura é de no máximo 15 caracteres por segundo, com no máximo 5 linhas e 28
  caracteres por linha.
- O papel `cta` ou `loop` só vale no último beat. Se `loop` for true, o último beat usa `outro_loop`.
- Toda afirmação tem fonte ou `own`. Um beat só cita afirmações que existem.
- O look nomeia um estilo. Um `TODO` em qualquer lugar é erro.
- O reel tem algum som: música ou pelo menos um efeito, e no máximo 6 efeitos num beat
  (`sfx_per_beat`). O QA prende a sonoridade a uma meta, então um arquivo mudo nunca passaria.
- Nenhum caractere de controle e nenhum texto com mais de 1000 caracteres. Um símbolo ou um emoji que
  as duas fontes podem não desenhar é um aviso.

O `reel approve <slug> [--by <nome>]` roda o lint. Se passar, escreve `screenplay.approved` no
projeto: primeiro a linha `<sha256>  screenplay.json`, e a hora e o nome na linha 2. Cada etapa lê o
roteiro e a aprovação de novo e roda o lint de novo: uma aprovação escrita à mão não pula as regras.
Ela também confere que o slug no arquivo é o da pasta, e recusa um link no lugar de qualquer um dos
dois arquivos.

Depois disso `reel shotlist`, `still`, `scene`, `music`, `mix`, `render`, `qa`, `contact-sheet` e
`publish` conferem o hash primeiro. Eles param com uma linha clara se o arquivo não existe ou se o
roteiro mudou:

```console
$ reel render demo
reel: screenplay.json of demo changed after its approval, or the approval is not in the form of reel approve (now 6ec284fe): the creative director fixes it, then lint and approve again
```

Isso rodou em 2026-11-05: um título alterado fez `render` e `publish` pararem com essa linha. Um
roteiro de 31 s, um gancho que termina em 4 s e uma linha de 46 caracteres falharam no `reel lint`,
cada um com uma linha `ERROR` para a regra quebrada.

Só o diretor criativo edita o `screenplay.json`. O produtor-editor aprova depois de uma revisão. O
dono também pode aprovar. O Hermes nunca aprova.

## A equipe

Os seats seguem os créditos de uma equipe de cinema. O dono deu a lista em 2026-11-08: produtor e
editor, diretor criativo, artista 3D, diretor musical e produtor executivo. A ideia vem de uma demo
pública do autor do OpenRig: um videoclipe feito por uma rig de agentes, em que um seat é o produtor,
o editor e o diretor musical, e o humano é o "produtor executivo", que só dá gosto e julgamento. O
dono deu a descrição; ninguém aqui assistiu à demo. Os nomes dos seats são nossos.

**Produtor executivo: o dono (um humano).** Ele não é um seat. Ele decide o brief, o início de cada
fase e o que acontece com o reel publicado.

|Id do seat|Papel|O que faz|
|---|---|---|
|`creative-director`|Diretor criativo|Recebe o brief do dono. Escreve o `screenplay.json` (gancho, beats, legendas, estilo). Depois da aprovação, faz a shotlist e o storyboard (`reel shotlist`, `reel still`). É dono do visual e das palavras.|
|`producer-editor`|Produtor e editor|Revisa o roteiro com o lint e o tempo (`reel lint`, `reel timing-report`, `reel screenplay-view`) e aprova o hash (`reel approve`). Depois monta as cenas e o corte (`reel scene`, `reel render`) e publica depois do QA (`reel publish`). É dono do cronograma e do arquivo final.|
|`artist-3d`|Artista 3D|Faz os planos 3D que a shotlist marca como `3d`: escreve uma cena em Python do Blender para cada um, renderiza sem janela para uma sequência de PNG com o `reel blender` (Cycles, CPU) e entrega a sequência ao produtor-editor. O seat está sempre no spec da rig, e só serve quando a opção do Blender está ligada.|
|`music-director`|Diretor musical|Faz a música procedural e a mixagem na linha do tempo (`reel music`, `reel mix`) e confere a sonoridade que o perfil pede.|
|`qa`|Revisor|Confere o arquivo contra o roteiro (`reel qa`, `reel contact-sheet`). Um seat que fez o trabalho nunca o confere, então o QA é um seat à parte.|

Se a memória deixar, a rig pode juntar o `producer-editor` e o `music-director` num só seat (a demo
pública faz assim): um spec de agente novo com os dois papéis e um só membro no `rig.yaml`. Isso
poupa um seat, cerca de 340 MiB. Isto não está feito aqui, e nada prova que funciona.

O que cada seat lê e escreve:

|Seat|Lê|Escreve|
|---|---|---|
|`crew-creative-director@reels-fabric`|O brief do dono, os exemplos do kit, o roteiro aprovado|`brief.md`, `screenplay.json`, `direction/shotlist.json`, `direction/svg/`, `direction/storyboard/<beat>.png`|
|`crew-producer-editor@reels-fabric`|`brief.md`, `screenplay.json`, a shotlist, `reel lint`, `reel screenplay-view`, `reel timing-report`|`review/screenplay.review.md`, `screenplay.approved` pelo `reel approve`, `build/` e `out/<slug>/reel.mp4` pelo `reel render`, `review/build.md`, a outbox pelo `reel publish`|
|`crew-artist-3d@reels-fabric`|O roteiro aprovado, a shotlist, o estilo|`blender/<beat>.py`, `frames/<beat>/` pelo `reel blender`, `review/3d.md`|
|`crew-music-director@reels-fabric`|O roteiro e as indicações de `sound` dele|`build/audio/` pelo `reel music` e pelo `reel mix`, `review/sound.md`|
|`crew-qa@reels-fabric`|`reel.mp4`, `qa.json`, os quadros, o roteiro|`out/<slug>/qa.json` e `qa/` pelo `reel qa`, `review/qa.md`|

Os cinco seats rodam `omp` em `anthropic/claude-sonnet-5-5`, sem pedidos de aprovação
(`permission_policy: builtin:yolo`, como nas outras rigs). Um membro pode rodar `runtime: claude-code`
com uma linha (veja [`RUNTIMES.ptBR.md`](RUNTIMES.ptBR.md)). As arestas são `delegates_to` e formam
uma cadeia sem ciclo: `creative-director` para `producer-editor`, `creative-director` para
`artist-3d`, `producer-editor` para `music-director`, `producer-editor` para `qa`. Um retorno é um
`rig send`, não uma aresta. Cada seat manda ao próximo o slug e um caminho, nunca o conteúdo. Um
veredito (approve, revise, pass, fail) vem com evidência e o número da rodada. Depois de 3 rodadas o
ciclo para e o dono decide.

O que um seat não faz:

- O diretor criativo é o único seat que edita o roteiro. Uma mudança volta para ele, e o
  produtor-editor aprova de novo.
- O produtor-editor escreve só os arquivos de revisão e o build. Nunca edita o roteiro, nem um erro de
  digitação. Ele não pode criar um template de cena: o kit está no Nix store, só leitura. Ele reporta a
  lacuna com o id do beat. Não renderiza um clipe à mão com o `ffmpeg`.
- O artista 3D escreve só `blender/`, `frames/` e o arquivo de revisão dele. Ele não define o motor:
  quem define é o `reel blender`.
- O diretor musical escreve só `build/audio/` e o arquivo de revisão dele.
- O QA só lê. Ele não consegue ouvir: escreve a sonoridade como número e o som como "sem dados". Ele
  não publica.
- Nenhum seat inicia ou para um seat, e nenhum seat tem rede.

## As fases

A unit `openrig` tem `MemoryMax=2G` e `MemoryHigh=1536M`. Um seat omp usa cerca de 340 MiB e o
daemon parado cerca de 220 MiB (`hermes/skills/hermes-omp/references/openrig-seats.md`, medido em
2026-11-04). Um render soma um `ffmpeg` de até 540 MiB (veja "Números medidos"), e um render do
Blender soma 536 MiB. Então a regra é **dois seats ao mesmo tempo, no máximo**, e um comando `reel`
por vez. A rig tem cinco seats, por isso o operador os inicia em cinco fases. Os comandos são os do
`rig.yaml`:

```console
rig import /etc/openrig/specs/rigs/reels-fabric/rig.yaml --materialize-only   # registra cinco seats, não inicia nenhum

# fase 1, história e visual
rig launch reels-fabric crew.creative-director
rig launch reels-fabric crew.producer-editor
rig send crew-creative-director@reels-fabric "<slug>, <15|30>, <o brief do dono>" --verify
# pronto quando o `reel approve` escreveu screenplay.approved (no máximo 3 rodadas); os dois seats ficam de pé

# fase 2, imagem: os mesmos dois seats
# o diretor criativo faz a shotlist e o storyboard; o produtor-editor monta os clipes das cenas
# pronto quando a shotlist e o storyboard existem e todo beat plano tem o clipe dele; então:
rig seat stop crew-creative-director@reels-fabric --reason "phase 2 done"

# fase 3, planos 3D (pule se a shotlist não tem plano 3d, ou se a opção do Blender está desligada)
rig launch reels-fabric crew.artist-3d
rig send crew-artist-3d@reels-fabric "<slug>, <caminho do projeto>, the 3d shots" --verify
# pronto quando cada plano 3d tem a sequência de PNG dele; então:
rig seat stop crew-artist-3d@reels-fabric --reason "phase 3 done"

# fase 4, som
rig launch reels-fabric crew.music-director
rig send crew-music-director@reels-fabric "<slug>, <caminho do projeto>, make the sound" --verify
# pronto quando a mixagem existe e o `reel render` do produtor-editor fez o corte com o áudio; então:
rig seat stop crew-music-director@reels-fabric --reason "phase 4 done"

# fase 5, conferir e publicar
rig launch reels-fabric crew.qa          # o produtor-editor ainda está de pé: dois seats
rig send crew-qa@reels-fabric "<slug>, <caminho do out>, check it" --verify
# pronto quando o `reel publish` rodou; então pare os dois
```

O produtor-editor não deve rodar `reel render` nem `reel scene` enquanto um render do `reel blender`
roda: a unit tem 2 GiB. Na fase 2 o produtor-editor faz o clipe de cada beat plano com `reel scene`;
o clipe de um beat 3d espera os quadros dele. O `reel render` faz o som sozinho, então o corte com o
áudio e os clipes dos beats 3d vêm na fase 4, depois da mixagem.

O `rig launch` inicia um seat que nunca rodou. O `rig seat launch <seat> --fresh --reason "<motivo>"`
inicia uma conversa em branco num seat que já rodou. Um seat sem ninguém para quem mandar termina com
uma resposta final, e o operador inicia o próximo seat. Uma falha do QA volta para o produtor-editor,
que ainda está de pé e manda cada falha ao seat dela. Uma falha para um seat que já está parado (o
diretor criativo, o artista 3D ou o diretor musical): inicie-o no lugar de um seat que não é mais
preciso, para que rodem dois seats. Rode o `kvm4-health` antes de cada fase e o
`rig snapshot reels-fabric` antes de parar. Uma rig guarda o spec com que foi feita: depois de mudar
o spec, rode `rig archive reels-fabric` e importe de novo. Não rode junto com outra rig.

O dono, o produtor executivo, decide o brief, o início de cada fase e o que fazer com o reel
publicado. Ele pode ler o `reel screenplay-view <slug>` antes da fase 2. Nada aqui publica no
Instagram.

## As pastas do projeto

`REELS_HOME` é `/var/lib/openrig/work/reels-fabric`. A opção cria estas pastas (`StateDirectory` da
unit, modo 0700, dono `openrig`): uma para cada seat (`creative-director`, `producer-editor`,
`artist-3d`, `music-director`, `qa`), `projects` e `out`.

```text
$REELS_HOME/
  projects/<slug>/
    brief.md                      diretor criativo
    screenplay.json               diretor criativo, a fonte única
    screenplay.approved           reel approve: SHA-256 do screenplay.json
    review/                       screenplay.review.md, build.md (produtor-editor), sound.md, 3d.md, qa.md
    direction/                    shotlist.json, storyboard/<beat>.png, svg/ (diretor criativo)
    blender/<beat>.py             artist-3d: uma cena do Blender para cada plano 3d
    frames/<beat>/%04d.png        o reel blender escreve: a sequência de PNG de um plano 3d
    build/                        o reel escreve: scenes/, audio/, layers/, cache/, blender-home/
  out/<slug>/
    reel.mp4  render.json  qa.json
    qa/                           hook.png, <beat>.png, <beat>-start.png, contact-sheet.png
$REELS_OUTBOX/<slug>/             reel publish: reel.mp4, qa.json, screenplay.json, review/
```

`REELS_OUTBOX` é `/var/lib/rig-outbox/reels-fabric`. Um slug tem letras minúsculas, dígitos e `-`, no
máximo 41 caracteres. As pastas dos seats guardam as normas (`AGENTS.md`) de cada seat e mais nada.

## O kit

`reel help` lista os comandos. O primeiro grupo não precisa de aprovação:

|Comando|Faz|
|---|---|
|`reel new <slug> <15\|30> [--example]`|Cria a pasta do projeto e um esqueleto de roteiro, ou uma cópia do exemplo|
|`reel lint <slug\|arquivo.json>`|As regras do roteiro, e da shotlist se houver|
|`reel screenplay-view <slug\|arquivo>`|O roteiro como script de duas colunas: imagem, e texto com som|
|`reel timing-report <slug\|arquivo>`|A leitura de mesa: velocidade de leitura e tempo de espera de cada beat. Sai com 1 se um beat é rápido demais.|
|`reel approve <slug> [--by <nome>]`|Escreve `screenplay.approved` se o lint passar|

Estes se recusam a rodar sem uma aprovação válida:

|Comando|Faz|
|---|---|
|`reel shotlist <slug> [--force]`|A `direction/shotlist.json` padrão, um plano para cada beat, para o diretor criativo refinar|
|`reel still <slug> <beat> [--at <s>] [-o <arquivo>]`|Um quadro de um beat. O arquivo padrão é `direction/storyboard/<beat>.png`.|
|`reel blender <slug> <beat>`|Renderiza um plano do tipo `3d` a partir de `blender/<beat>.py` para `frames/<beat>/%04d.png` (Cycles, CPU). Precisa do binário `blender` no PATH. Veja "Cenas 3D com o Blender".|
|`reel scene <slug> <beat>`|O clipe de um beat, em `build/scenes/`. Um beat `3d` usa a sequência de PNG como imagem.|
|`reel music <slug>`|A cama de música procedural, `build/audio/music.wav`|
|`reel mix <slug>`|Música e efeitos, normalizados, `build/audio/mix.wav`|
|`reel render <slug>`|O som, os clipes e a montagem: `out/<slug>/reel.mp4` e `render.json`. Precisa da shotlist.|
|`reel qa <slug>`|Fatos, sonoridade, quadros e área segura: `out/<slug>/qa.json` e `qa/`. Sai com 1 se falhar.|
|`reel contact-sheet <slug>`|`out/<slug>/qa/contact-sheet.png`, todos os quadros dos beats numa imagem|
|`reel publish <slug> [--replace]`|Copia o vídeo para a outbox. Precisa de um `qa.json` aprovado, deste mesmo arquivo e deste mesmo roteiro. Nunca sobrescreve um slug sem `--replace` e nunca toca em outro slug.|

O `reel render` faz os clipes um a um e monta o vídeo em etapas de no máximo 4 entradas, para que
um `ffmpeg` fique pequeno. Um clipe é mantido quando nada de que ele depende mudou. O `reel qa`
confere: contêiner, codec (`h264`), tamanho, formato de pixel (`yuv420p`), taxa de quadros,
duração (a 0,05 s de 15 ou 30), áudio (`aac`, 48000 Hz, 2 canais, e um tamanho a 0,1 s do formato), `+faststart` (moov antes do
mdat), sonoridade, pico real, se o render veio do roteiro aprovado, a imagem do gancho em 0,5 s e, em
cada beat, se a imagem está dentro da área segura e tem contraste. Faz isso com medidas, sem modelo.
O QA lê o arquivo, nunca a shotlist.

Uma sessão de exemplo, com o roteiro de exemplo (rodou em 2026-11-05, do pacote buildado, num
ambiente vazio). Uma palavra mudou depois da execução: o nome depois de `--by` era `script-editor`, o
seat que o produtor-editor substitui.

```console
$ reel new demo 30 --example
$ reel lint demo
lint: 0 error(s), 0 warning(s)
lint: PASS
$ reel approve demo --by producer-editor
approved: demo (sha256 d7fee787e42ed72cc2c694a8ca830ae3909675a1c6cb5c73681931e97a0273e3)
$ reel shotlist demo
$ reel render demo
render: .../out/demo/reel.mp4 (5520735 bytes, 120 s wall, 539.4 MiB peak in one ffmpeg)
$ reel qa demo
pass  size: 1080x1920
pass  loudness (LUFS): -14.30
qa: PASS (.../out/demo/qa.json, frames in .../out/demo/qa)
$ reel contact-sheet demo
$ reel publish demo
published: $REELS_OUTBOX/demo (5520735 bytes)
```

As variáveis que o kit lê: `REELS_HOME`, `REELS_OUTBOX`, `REELS_SHARE` (os dados dele: o perfil, os
estilos, os exemplos e as fontes), `REELS_FONTS` e, para o `reel blender`, `REELS_BLENDER` (o caminho
do binário `blender`; o wrapper do pacote o define a partir do PATH de quem chama, e fica vazio se não
houver). A rig define as duas primeiras no `env:`. `REELS_HOME`, `REELS_SHARE`, `REELS_FONTS` e
`TMPDIR` só podem ter letras, dígitos e `/ . _ -`: os caminhos chegam a filtros do `ffmpeg` e a
arquivos de legenda. Cada `ffmpeg` para após 300 s e cada `resvg` após 60 s, e uma execução do
`blender` após 3600 s (`limits` no perfil), com uma linha clara, para que um processo travado não
prenda um seat.

## O que faz e o que não faz

Faz texto sobre uma folha escura com um acento vermelho, no look do `site/DESIGN.md`: Fjalla One nos
títulos, Inter no texto. As nove cenas são layouts tipográficos com desenhos simples em SVG. O
movimento é uma entrada palavra por palavra, um zoom lento do fundo (`camera.zoom` na shotlist), 15
transições além de `cut` (`fade`, slides, wipes, círculos e outras) e um gradiente. O som é uma cama de
música procedural (`pulse`, `ambient`, `tension`, `upbeat`) e cinco efeitos, todos feitos de ondas
senoidais e ruído filtrado.

Não faz:

- vídeo filmado, foto de um lugar, de uma pessoa, de um animal ou de uma onda real. O kit não tem fonte
  para isso.
- voz. A locução está desligada na v1.
- música de verdade. A cama é um loop de tons sintéticos, e ninguém a ouviu: a máquina não tem ouvido.
  Ouça antes de publicar.
- um visual que ganha prêmio. O contact sheet do exemplo é limpo e legível, e é um conjunto de
  cartões com o terço de baixo do quadro vazio (é a área segura do Instagram). Um reel deste tipo é
  um explicativo ou um cartão de citação em movimento, não um filme.

O visual e o som são a pergunta em aberto desta rig. O passo depois de um primeiro teste é ler o que o
dono acha deles.

## Cenas 3D com o Blender

O dono decidiu em 2026-11-08 usar o Blender para o artista 3D. O `AGENTS.md` diz sem GUI e sem
bibliotecas de desktop; o dono abre uma exceção para isto, como fez para o Node 24 e para dois
arquivos de fonte. O Blender é software livre (GPL-2.0-or-later, `meta.unfree` é false no nixpkgs),
então `unfree.nix` e `allowUnfree` não mudam. Ele roda sem janela e sem display.

**A opção.** `piabrota.openrig.reels.blender.enable`, desligada por padrão. Ela adiciona o
`pkgs.blender` ao perfil do usuário `openrig` e ao `path` da unit, e mais nada. Com a opção desligada,
a rig de reels funciona como antes (sem planos 3D) e o fecho não cresce. A opção precisa de
`piabrota.openrig.reels.enable`: com o Blender ligado e a rig de reels desligada, o build para com uma
assertion. O pacote é o `pkgs.blender` do nixpkgs fixado, sem override.

**Um plano 3D.** O diretor criativo marca um plano em `direction/shotlist.json`:
`"kind": "3d", "frames": "frames/b03"`. O id do plano é o id do beat. `kind` é `flat` (o padrão) ou
`3d`. `frames` é obrigatório para `3d`, deve ser `frames/<beat>` e é recusado num plano `flat`. O
`reel lint` confere os dois e avisa quando o beat tem mais quadros que `blender.max_frames` em
`blender.fps` (o último quadro é mantido). O roteiro em si não muda: a cena, o texto e o som do beat
ficam como foram escritos.

**`reel blender <slug> <beat>`.** O artista 3D escreve `blender/<beat>.py`, uma cena em Python do
Blender (um exemplo é `reels/examples/blender/spin.py`: um cubo que gira, 24 quadros). O comando:

- se recusa a rodar sem o roteiro aprovado e sem um plano do tipo `3d`, como toda etapa.
- precisa do binário `blender` no PATH. Sem ele, para com uma linha clara e código de saída 1.
- roda `blender -b --factory-startup --threads 2 --python-exit-code 1`, com `HOME`,
  `XDG_CONFIG_HOME` e `XDG_CACHE_HOME` em `build/blender-home/` do projeto, nunca na home de verdade.
  Ele roda primeiro o arquivo da cena e depois um driver do kit, para que o driver tenha a última
  palavra.
- o driver define o motor como `CYCLES`, o dispositivo como `CPU`, as amostras (`blender.samples`, 16),
  o denoiser desligado, o tamanho (1080x1920, do perfil), a taxa de quadros (`blender.fps`, 24) e a
  saída. Um arquivo de cena que define outro motor é sobrescrito depois do carregamento. O kit nunca
  escolhe o EEVEE.
- lê antes o intervalo de quadros da cena, numa execução curta, e recusa uma cena com mais quadros que
  `blender.max_frames` (240) antes de gastar minutos. Ele avisa e sai com 1.
- renderiza em `frames/<beat>.part/` e move para `frames/<beat>/` (`0001.png`, `0002.png`, ...) só
  quando a contagem está certa, então uma execução com falha deixa os quadros antigos como estavam.

O `reel scene` e o `reel render` usam a sequência como imagem do beat, no lugar do fundo plano: os
quadros passam de `blender.fps` para 30 fps e são ajustados a 1080x1920, o último quadro é mantido se
o beat for mais longo, e as legendas e as camadas SVG ficam por cima como em qualquer beat. Um beat 3d
sem quadros não tem clipe (um still volta para o fundo plano, com um aviso). Um clipe só é mantido
enquanto os quadros dele são os mesmos arquivos.

**Os limites.**

- **O EEVEE não funciona aqui.** O `blender -b` com `BLENDER_EEVEE` morreu com erros de EGL e uma falha
  de segmentação: a máquina não tem GPU nem display. O Workbench não foi testado. Então o kit usa o
  Cycles na CPU e nada mais.
- **O denoiser está desligado.** Com ele ligado, um quadro de 1080x1920 chegou a 2174 MiB de pico, e a
  unit tem 2 GiB para todos os seats. Desligado, o pico é 536 MiB. Os quadros ficam com ruído a 16
  amostras: mantenha a cena simples, com materiais lisos e poucas luzes.
- **Memória.** O produtor-editor não deve rodar `reel render` nem `reel scene` enquanto um render do
  `reel blender` roda. No máximo dois seats rodam (o artista 3D e o produtor-editor), e um comando
  `reel` por vez.
- **Tempo.** Uma cena deve ficar simples, e o número de quadros tem orçamento: `blender.max_frames`
  (240, ou seja, 10 s a 24 fps) e `blender.fps` em `reels/profile.json`.

**Os números.** *Medidos* na `piabrota2` pelo agente do dono em 2026-11-08, com o Blender 5.2.2 (rev
do nixpkgs `02c087f3fe673c9e317f206a627cb6b910336dbe`): o fecho do sistema com o Blender tem 4940 MiB
no total, e cerca de 3,0 GiB (863 MiB para baixar) era novo na máquina. Um quadro de 1080x1920, 16
amostras, 2 threads, Cycles na CPU, uma cena simples: 7,4 s e 527 MiB de pico de memória. *Medidos*
aqui em 2026-11-08 com o mesmo Blender 5.2.2, a cena de exemplo, 2 threads: 16 amostras, denoiser
desligado, 8,3 s e 536 MiB por quadro; 32 amostras, denoiser desligado, 15,5 s e 536 MiB; 32 amostras,
denoiser ligado, 24,7 s e 2174 MiB. Um quadro PNG tem cerca de 1,2 MB, então 240 quadros ocupam cerca
de 290 MB. *Medido*, uma execução em seco do build com o Blender 5.1.1 (veja abaixo): 81 caminhos do
store, 693,5 MiB para baixar, 2,7 GiB descompactados. *Extrapolados*, não medidos: 450 quadros (15 s a
30 fps) ao mesmo custo levariam cerca de 55 minutos, e 240 quadros a 8,3 s cerca de 33 minutos. Por
isso uma cena fica simples e o kit tem um orçamento de quadros.

**A versão.** O input `nixpkgs` deste repositório (o que os hosts usam, rev `9bb52223`) tem o Blender
5.1.1. O Blender 5.2.2 está no nixpkgs que o input `hermes-agent` fixa (rev `02c087f3`), que é o que o
agente do dono mediu. Os números acima são do 5.2.2. As execuções reais do Blender desta página foram
com o 5.2.2 do store; o 5.1.1 não rodou. Rode o primeiro plano 3D na máquina e confira os números de
novo.

**Ligar e desligar.** Ligar: ponha `piabrota.openrig.reels.blender.enable = true;` ao lado de
`piabrota.openrig.reels.enable = true;` em `hosts/piabrota2/default.nix`, abra um pull request e faça o
merge. O deploy baixa cerca de 700 MiB e descompacta cerca de 2,7 GiB. Desligar: tire a linha. O
próximo deploy tira o Blender do perfil, e a coleta de lixo o remove depois. `frames/` e `blender/`
ficam nos projetos. Com a opção desligada, o `reel blender` para com "blender is not in the PATH", e o
seat artist-3d não tem o que fazer: pule a fase 3.

## Números medidos

Medidos nesta máquina (`piabrota2`) em 2026-11-05, com o pacote buildado, um ambiente vazio, os
roteiros de exemplo e o `time` do GNU. O render de 30 s levou 105 s, 105 s e 120 s em três execuções, e
o de 15 s levou 65 s, 47 s e 56 s: outra execução do `omp` usou a CPU por momentos (a carga média no
início de uma execução ficou entre 0,04 e 3,9). As execuções foram do usuário `hermes`, não dentro da
unit `openrig`. O pico de memória de um render de 30 s foi 549, 542 e 539 MiB (o kit mudou um pouco
entre as execuções). A tabela traz a última de cada uma.

|Número|30 s|15 s|
|---|---|---|
|`reel render`, tempo de relógio|120 s|56 s|
|`reel render`, memória de pico (o maior `ffmpeg`)|540 MiB|508 MiB|
|`reel render`, execuções do `ffmpeg`|19|13|
|`reel.mp4`, tamanho|5.520.735 bytes (5,3 MiB)|2.928.943 bytes (2,8 MiB)|
|`reel qa`, tempo de relógio, memória de pico|4,2 s, 110 MiB|3,7 s, 109 MiB|
|`reel contact-sheet`, tempo de relógio|2,5 s|2,2 s|
|Sonoridade, pico real|-14,30 LUFS, -0,82 dBTP|-14,18 LUFS, -1,42 dBTP|
|`new`, `lint`, `approve`, `shotlist`, `publish`|cada um abaixo de 0,1 s|cada um abaixo de 0,1 s|

O arquivo: H.264 High, `yuv420p`, 1080x1920, 30 fps, 900 quadros em 30,000 s, AAC 48000 Hz estéreo,
cerca de 1,5 Mbit/s, o `qa` passa. A soma: o daemon (cerca de 220 MiB) com dois seats (cerca de
340 MiB cada) e um render (540 MiB) dá cerca de 1,4 GiB, logo abaixo do `MemoryHigh=1536M` e acima
dele se um seat crescer. Por isso o produtor-editor e o QA rodam um comando `reel` por vez, e nada mais
roda durante um render.

O tamanho do kit: o `reel` sozinho tem 332 MiB com o fecho dele (`nix path-info -S`); 199 MiB disso,
em 64 caminhos do store, não estão no fecho do sistema em execução (comparado com
`/run/current-system` em 2026-11-05). A parte que é nossa tem 1,2 MB: os scripts, o perfil, os
estilos, os exemplos e dois arquivos de fonte.

## Para onde vai o vídeo

O `reel publish` copia `reel.mp4`, `qa.json`, `screenplay.json` e `review/` para
`/var/lib/rig-outbox/reels-fabric/<slug>/`. A pasta é do `openrig`, grupo `hermes`, modo 2750 (setgid,
então um arquivo novo fica no grupo `hermes`), com uma ACL padrão para o grupo. O `reel publish` também
dá leitura ao grupo no que copia, porque o `UMask` da unit é 077. O `systemd-tmpfiles` remove arquivos com mais de 14 dias. A
outbox fica fora de `/var/lib/openrig`, que a lista de bloqueio do Hermes protege. O Hermes lê os
arquivos ali e mostra ao dono o caminho do vídeo, a visão do roteiro, o veredito do QA e o contact
sheet (que fica em `out/<slug>/qa/` e não é copiado).

Como o arquivo chega ao dono está em aberto. Um vídeo de 5,3 MiB pode caber no limite de arquivo do
canal de chat, mas isso não foi conferido: confira o limite antes de enviar. O envio ao Instagram não é
feito aqui.

## Os números não verificados

As chaves de `unverified` em `reels/profile.json` são palpites, não fatos que alguém conferiu com o
Instagram ou com uma norma. O lint e o QA usam os valores como estão:

|Chave|Valor|Significado|
|---|---|---|
|`safe.top`, `safe.bottom`, `safe.side`|0,14, 0,35, 0,06|A fatia do quadro que fica livre de texto e desenho|
|`text.max_cps`|15|Caracteres por segundo|
|`text.max_lines`, `text.max_chars_per_line`|5, 28|O tamanho do texto de um beat|
|`audio.target_lufs`, `audio.lufs_tolerance`|-14, 2,0|A sonoridade que a mixagem mira, e o quanto o QA deixa passar|
|`audio.true_peak`, `audio.true_peak_slack`, `audio.premix_peak`|-1,0, 0,5, -2,0|Limites em dBTP|
|`video.crf`|20|A qualidade do vídeo final|
|`qa.min_text_range`, `qa.edge_min`, `qa.safe_slack_px`, `qa.probe_frac`, `qa.audio_tolerance_s`|60, 40, 8, 0,7, 0,1|Os limites e o ponto de prova das checagens do QA|
|`limits.ffmpeg_timeout_s`, `limits.resvg_timeout_s`, `sfx_per_beat`|300, 60, 6|Os limites de tempo do `ffmpeg` e do `resvg` em segundos, e os efeitos que um beat pode ter|

Também não verificado, porque não são fatos sobre o Instagram: se o envio aceita o arquivo, como o app
corta e cobre o quadro, e o quanto 14 LUFS soa alto perto de outros reels. O tempo do gancho (3 s), o
beat mais curto (0,8 s) e os formatos são escolhas deste desenho, não palpites de uma medida.

## Como ligar

Ponha `piabrota.openrig.reels.enable = true;` em `hosts/piabrota2/default.nix` e abra um pull request.
O merge faz o deploy. A opção adiciona:

- o kit `reel` no perfil do usuário `openrig` e no `path` da unit, com `ffmpeg-headless` e `jq`. O kit
  tem o próprio `ffmpeg-headless`, `resvg`, `jq`, `coreutils` e `time`.
- dois arquivos de fonte, Inter (879.708 bytes) e Fjalla One (209.052 bytes). É a exceção do dono para
  "sem fontes" no `AGENTS.md`: dois arquivos em `share/reels/fonts`, sem coleção, sem `fontconfig` do
  sistema, sem GUI.
- as pastas de "As pastas do projeto" no `StateDirectory` da unit.
- a outbox `/var/lib/rig-outbox/reels-fabric` (2750 `openrig` `hermes`, 14 dias, ACL padrão
  `group::r-X`), e o `ReadWritePaths` dela. O pai `/var/lib/rig-outbox` é dividido com a rig das ondas,
  e as duas opções podem estar ligadas.

Com a opção desligada, os specs ficam em `/etc/openrig/specs` só como definição e mais nada muda. O
deploy reinicia o `openrig` e encerra os seats (veja [`OPENRIG.md`](OPENRIG.md)). O Blender é uma
segunda opção, `piabrota.openrig.reels.blender.enable`, desligada: veja "Cenas 3D com o Blender". Com
ela desligada, o fecho dos dois hosts é o mesmo de antes de ela existir (o `nix build --dry-run` lista
as mesmas derivações).

Para buildar o kit sem a opção:

```console
nix build --impure --expr '(builtins.getFlake "path:'$PWD'").nixosConfigurations.piabrota2.pkgs.callPackage ./reels {}'
```

## Um primeiro teste

1. Ligue a opção e faça o deploy. Rode `rig status` e `kvm4-health`.
2. Como dono, rode o import de "As fases", uma vez.
3. Rode a fase 1 com um brief curto: um fato, uma fonte, 15 s. Leia `reel screenplay-view <slug>`.
4. Rode as fases 2, 4 e 5 como escrito. Rode a fase 3 só se a opção do Blender estiver ligada e a shotlist tiver um plano 3d.
5. Abra `reel.mp4` e `qa/contact-sheet.png`. Ouça o som. Diga o que está errado.

Para testar o kit sem uma rig, rode `reel new demo 15 --example` e a sessão acima com `REELS_HOME` e
`REELS_OUTBOX` apontando para pastas de rascunho.

## Riscos

- **Memória.** Um render passa de 450 MiB por um tempo curto. Com dois seats e o daemon, sobra pouco
  espaço abaixo do `MemoryHigh`. O kernel desacelera a unit, não a mata, mas um render com um terceiro
  processo pode chegar ao `MemoryMax`. O `OOMPolicy=continue` leva um processo. Um render do Blender
  soma 536 MiB (com o denoiser desligado): veja "Cenas 3D com o Blender".
- **CPU.** Um render de 30 s levou de 105 a 120 s, com `nice -n 10` e uma thread de vídeo na
  codificação final. Ele desacelera um pouco as outras units. Não roda em horário agendado.
- **Um seat não é um verificador.** O lint mede o que consegue. Uma afirmação é "sourced" porque uma
  pessoa escreveu uma fonte no brief; o produtor-editor não consegue abrir um link. As fontes precisam
  de um humano.
- **Rodam sem pedidos de aprovação.** Como nas outras rigs: as regras de bloqueio do `hermes/omp.yml`
  são a guarda.
- **Uma palavra do roteiro pode não caber.** Palavras longas ou outros idiomas podem ficar mais largas
  que o quadro. O QA confere a área segura por medida e um seat olha o quadro.

## O que não está provado

- Uma execução real da rig: nenhum seat fez uma tarefa desta rig. A guidance dos seats, as mensagens
  entre eles e as cinco fases vêm dos specs, não de uma execução.
- Que o OpenRig inicia a rig. O `rig spec validate` (a rig) e o `rig agent validate` (os seis specs de
  agente) passaram aqui em 2026-11-08, sem daemon. O `rig spec preflight` não resolveu os caminhos
  `agent_ref` aqui, e falha do mesmo jeito na `wave-forecaster-dev`, então não prova nada.
- Um render do `reel blender` com o Blender 5.1.1, a versão que o nixpkgs fixado tem, e um render
  dentro da unit `openrig` (as execuções de teste foram do usuário `hermes`, com o 5.2.2).
- A aceitação do arquivo pelo Instagram, e como o app o mostra.
- O visual aos olhos do dono, e o som por inteiro: ninguém o ouviu.
- A leitura da outbox pelo Hermes sob o sandbox do `hermes-agent`, como na rig das ondas.
- Os números de "Os números não verificados".

## Créditos

- [FFmpeg](https://ffmpeg.org) (`ffmpeg-headless` 8.1.3, com libx264 e libass; a licença no nixpkgs é
  LGPL-2.1-or-later ou GPL-2.0-or-later, e o build com libx264 é GPL).
- [resvg](https://github.com/linebender/resvg) 0.47.0 (MPL-2.0) desenha o SVG.
- [jq](https://github.com/jqlang/jq) 1.8.2 (MIT) faz a lógica do roteiro.
- [Inter](https://rsms.me/inter/) 4.1, de Rasmus Andersson (SIL OFL 1.1), do nixpkgs.
- [Fjalla One](https://fonts.google.com/specimen/Fjalla+One), de Sorkin Type (SIL OFL 1.1: o arquivo
  está na pasta `ofl/` do [google/fonts](https://github.com/google/fonts) e a tabela de nomes dele cita
  a licença), no commit que o `google-fonts` do nixpkgs fixa.
- [Blender](https://www.blender.org) (GPL-2.0-or-later), sem janela, atrás de uma opção própria, para
  as cenas 3D.
- [OpenRig](https://github.com/mvschwarz/openrig), de mvschwarz (Apache-2.0), e o próprio kit,
  MPL-2.0, como o resto deste repositório.
