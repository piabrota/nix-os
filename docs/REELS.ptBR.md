# A Fábrica de Reels

Os arquivos são `openrig/specs/rigs/reels-fabric/`, `openrig/specs/agents/reels-*/`, `reels/` (o kit
`reel`), a opção `piabrota.openrig.reels.enable` em `openrig.nix` e esta página. As páginas `Reels`
do wiki resumem tudo. Os fatos aqui foram medidos na `piabrota2` em 2026-11-05 ou lidos no código. O
que não está provado fica em "O que não está provado".

## O que é

A Fábrica de Reels é uma rig do [OpenRig](OPENRIG.md) que faz um vídeo vertical, de 15 s ou 30 s,
1080x1920, para os Reels do Instagram. Cinco seats trabalham em dois pods. O pod `story` escreve e
aprova um roteiro. O pod `studio` dirige, monta e confere o vídeo a partir desse roteiro. Os seats
usam um só kit, o `reel`, feito de shell POSIX, `jq`, `ffmpeg` e `resvg`.

A rig é só uma definição. A opção está desligada, ninguém inicia a rig, e o dono decide quando
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
reel: screenplay.json of demo changed after its approval, or the approval is not in the form of reel approve (now 6ec284fe): the writer fixes it, then lint and approve again
```

Isso rodou em 2026-11-05: um título alterado fez `render` e `publish` pararem com essa linha. Um
roteiro de 31 s, um gancho que termina em 4 s e uma linha de 46 caracteres falharam no `reel lint`,
cada um com uma linha `ERROR` para a regra quebrada.

Só o writer edita o `screenplay.json`. O script editor aprova depois de uma revisão. O dono também
pode aprovar. O Hermes nunca aprova.

## Os seats

|Pod|Seat|Lê|Escreve|
|---|---|---|---|
|`story`|`story-writer@reels-fabric`|O brief do dono, os exemplos do kit|`brief.md`, `screenplay.json`|
|`story`|`story-script-editor@reels-fabric`|`brief.md`, `screenplay.json`, `reel lint`, `reel screenplay-view`, `reel timing-report`|`review/screenplay.review.md`, e `screenplay.approved` pelo `reel approve`|
|`studio`|`studio-director@reels-fabric`|O roteiro aprovado|`direction/shotlist.json`, `direction/svg/`, `direction/storyboard/<beat>.png`|
|`studio`|`studio-maker@reels-fabric`|O roteiro e a shotlist|`build/`, `out/<slug>/reel.mp4` (pelo `reel render`), `review/build.md`|
|`studio`|`studio-qa@reels-fabric`|`reel.mp4`, `qa.json`, os quadros, o roteiro|`out/<slug>/qa.json` e `qa/` (pelo `reel qa`), `review/qa.md`, a outbox (pelo `reel publish`)|

Os cinco seats rodam `omp` em `anthropic/claude-sonnet-5-5`, sem pedidos de aprovação
(`permission_policy: builtin:yolo`, como nas outras rigs). Um membro pode rodar `runtime: claude-code`
com uma linha (veja [`RUNTIMES.ptBR.md`](RUNTIMES.ptBR.md)). As arestas são `delegates_to` e formam
uma cadeia: writer, script editor, director, maker, QA. Cada seat manda ao próximo o slug e um
caminho, nunca o conteúdo. Um veredito (approve, revise, pass, fail) vem com evidência e o número da
rodada. Depois de 3 rodadas o ciclo para e o dono decide.

O que um seat não faz:

- O writer é o único seat que edita o roteiro. Uma mudança volta para ele.
- O script editor escreve só o arquivo de revisão. Nunca edita o roteiro, nem um erro de digitação.
- O director escreve só `direction/`. Uma mudança que o roteiro precisa volta para o writer.
- O maker não pode criar um template de cena: o kit está no Nix store, só leitura. Ele reporta a
  lacuna com o id do beat. Não renderiza um clipe à mão com o `ffmpeg`.
- O QA só lê. Ele não consegue ouvir: escreve a sonoridade como número e o som como "sem dados".
- Nenhum seat inicia ou para um seat, e nenhum seat tem rede.

## As fases

A unit `openrig` tem `MemoryMax=2G` e `MemoryHigh=1536M`. Um seat omp usa cerca de 340 MiB e o
daemon parado cerca de 220 MiB (`hermes/skills/hermes-omp/references/openrig-seats.md`, medido em
2026-11-04). Um render soma um `ffmpeg` de até 540 MiB (veja "Números medidos"). Então a regra é
**dois seats ao mesmo tempo, no máximo**, e um comando `reel` por vez. A rig tem cinco seats, por isso
o operador os inicia em três fases. Os comandos são os do `rig.yaml`:

```console
rig import /etc/openrig/specs/rigs/reels-fabric/rig.yaml --materialize-only   # registra cinco seats, não inicia nenhum

# fase 1, story
rig launch reels-fabric story.writer
rig launch reels-fabric story.script-editor
rig send story-writer@reels-fabric "<slug>, <15|30>, <o brief do dono>" --verify
# pronto quando o `reel approve` escreveu screenplay.approved (no máximo 3 rodadas)
rig seat stop story-writer@reels-fabric --reason "phase 1 done"
rig seat stop story-script-editor@reels-fabric --reason "phase 1 done"

# fase 2, studio
rig launch reels-fabric studio.director
rig launch reels-fabric studio.maker
rig send studio-director@reels-fabric "<slug>, <caminho do projeto>, direct it" --verify
# pronto quando a shotlist e o storyboard existem e out/<slug>/reel.mp4 existe; então pare o director

# fase 3, qa
rig launch reels-fabric studio.qa          # o maker ainda está de pé: dois seats
rig send studio-qa@reels-fabric "<slug>, <caminho do out>, check it" --verify
# pronto quando o `reel publish` rodou; então pare os dois
```

O `rig launch` inicia um seat que nunca rodou. O `rig seat launch <seat> --fresh --reason "<motivo>"`
inicia uma conversa em branco num seat que já rodou. Um seat sem ninguém para quem mandar termina com
uma resposta final, e o operador inicia o próximo seat. Uma falha do QA vai para um seat que já está
parado: inicie-o no lugar do director ou do maker, para que rodem dois seats. Rode o `kvm4-health`
antes de cada fase e o `rig snapshot reels-fabric` antes de parar. Uma rig guarda o spec com que foi
feita: depois de mudar o spec, rode `rig archive reels-fabric` e importe de novo. Não rode junto com
outra rig.

O dono decide o brief, o início da fase 2 e o que fazer com o reel publicado. O dono pode ler o
`reel screenplay-view <slug>` antes da fase 2. Nada aqui publica no Instagram.

## As pastas do projeto

`REELS_HOME` é `/var/lib/openrig/work/reels-fabric`. A opção cria estas pastas (`StateDirectory` da
unit, modo 0700, dono `openrig`): uma para cada seat (`writer`, `script-editor`, `director`, `maker`,
`qa`), `projects` e `out`.

```text
$REELS_HOME/
  projects/<slug>/
    brief.md                      writer
    screenplay.json               writer, a fonte única
    screenplay.approved           reel approve: SHA-256 do screenplay.json
    review/                       screenplay.review.md, build.md, qa.md
    direction/                    shotlist.json, storyboard/<beat>.png, svg/
    build/                        o reel escreve: scenes/, audio/, layers/, cache/
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
|`reel shotlist <slug> [--force]`|A `direction/shotlist.json` padrão, um plano para cada beat, para o director refinar|
|`reel still <slug> <beat> [--at <s>] [-o <arquivo>]`|Um quadro de um beat. O arquivo padrão é `direction/storyboard/<beat>.png`.|
|`reel scene <slug> <beat>`|O clipe de um beat, em `build/scenes/`|
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
ambiente vazio):

```console
$ reel new demo 30 --example
$ reel lint demo
lint: 0 error(s), 0 warning(s)
lint: PASS
$ reel approve demo --by script-editor
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
estilos, os exemplos e as fontes) e `REELS_FONTS`. A rig define as duas primeiras no `env:`.
`REELS_HOME`, `REELS_SHARE`, `REELS_FONTS` e `TMPDIR` só podem ter letras, dígitos e `/ . _ -`: os
caminhos chegam a filtros do `ffmpeg` e a arquivos de legenda. Cada `ffmpeg` para após 300 s e cada
`resvg` após 60 s (`limits` no perfil), com uma linha clara, para que um processo travado não prenda
um seat.

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
dele se um seat crescer. Por isso o maker e o QA rodam um comando `reel` por vez, e nada mais roda
durante um render.

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
deploy reinicia o `openrig` e encerra os seats (veja [`OPENRIG.md`](OPENRIG.md)).

Para buildar o kit sem a opção:

```console
nix build --impure --expr '(builtins.getFlake "path:'$PWD'").nixosConfigurations.piabrota2.pkgs.callPackage ./reels {}'
```

## Um primeiro teste

1. Ligue a opção e faça o deploy. Rode `rig status` e `kvm4-health`.
2. Como dono, rode o import de "As fases", uma vez.
3. Rode a fase 1 com um brief curto: um fato, uma fonte, 15 s. Leia `reel screenplay-view <slug>`.
4. Rode a fase 2 e a fase 3 como escrito.
5. Abra `reel.mp4` e `qa/contact-sheet.png`. Ouça o som. Diga o que está errado.

Para testar o kit sem uma rig, rode `reel new demo 15 --example` e a sessão acima com `REELS_HOME` e
`REELS_OUTBOX` apontando para pastas de rascunho.

## Riscos

- **Memória.** Um render passa de 450 MiB por um tempo curto. Com dois seats e o daemon, sobra pouco
  espaço abaixo do `MemoryHigh`. O kernel desacelera a unit, não a mata, mas um render com um terceiro
  processo pode chegar ao `MemoryMax`. O `OOMPolicy=continue` leva um processo.
- **CPU.** Um render de 30 s levou de 105 a 120 s, com `nice -n 10` e uma thread de vídeo na
  codificação final. Ele desacelera um pouco as outras units. Não roda em horário agendado.
- **Um seat não é um verificador.** O lint mede o que consegue. Uma afirmação é "sourced" porque uma
  pessoa escreveu uma fonte no brief; o script editor não consegue abrir um link. As fontes precisam de
  um humano.
- **Rodam sem pedidos de aprovação.** Como nas outras rigs: as regras de bloqueio do `hermes/omp.yml`
  são a guarda.
- **Uma palavra do roteiro pode não caber.** Palavras longas ou outros idiomas podem ficar mais largas
  que o quadro. O QA confere a área segura por medida e um seat olha o quadro.

## O que não está provado

- Uma execução real da rig: nenhum seat fez uma tarefa desta rig. A guidance dos seats, as mensagens
  entre eles e as três fases vêm dos specs, não de uma execução.
- Que o OpenRig aceita o spec (`rig spec validate` não rodou aqui: não há `rig` nesta worktree).
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
- [OpenRig](https://github.com/mvschwarz/openrig), de mvschwarz (Apache-2.0), e o próprio kit,
  MPL-2.0, como o resto deste repositório.
