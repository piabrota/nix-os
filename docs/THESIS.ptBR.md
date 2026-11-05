# O rig da tese: wave-forecaster-thesis

[English](THESIS.md)

Seis seats do OpenRig, todos no Claude Code, escrevem um projeto de graduação da Escola Politécnica
da UFRJ em português, seção por seção, e entregam um PDF. Um conjunto de ferramentas sem modelo e sem
rede, o comando `thesis`, faz o trabalho mecânico: reserva a seção, monta o PDF, roda os portões e
registra o parecer. Esta página explica as peças, o contrato entre elas, o que cada portão mede e o
que não prova, e traz as notas de deploy. O resto da instalação do OpenRig está em
[`OPENRIG.md`](OPENRIG.md). Os arquivos são `thesis/`, `openrig/specs/rigs/wave-forecaster-thesis/`,
`openrig/specs/agents/thesis-*/` e a opção `piabrota.openrig.thesis.enable` de `openrig.nix`.

**Como ler.** Cada número vem de um arquivo deste repositório (`thesis/profile.json`, os scripts de
`thesis/lib/`, as specs) ou do relatório da execução que construiu as ferramentas (2026-11-05). `⚠`
marca o que não foi conferido. "Não medido" quer dizer que ninguém mediu. **Nenhum seat rodou esta
rig ainda.** O que foi provado é o `thesis` sobre uma tese de exemplo (veja "O que está provado e o
que não está").

## Para que serve, e para que não serve

**Serve** para escrever com método o texto de um projeto de graduação cujo conteúdo já existe: os
fatos, os dados, as decisões e as fontes são do dono. O rig organiza o texto em seções
independentes, escreve cada uma, confere a forma e as fontes e monta o PDF no modelo da Poli.

**Não é um ghost-writer.** O dono dá os fatos, os dados, as decisões e as fontes. O rig escreve,
confere e diagrama. O dono lê, assina e deposita. Concretamente:

- Um seat nunca inventa um número, um resultado, uma referência ou uma experiência do autor. Onde só o
  autor sabe, o texto leva a marca `**[AUTHOR: ...]**`, e `thesis submit` recusa a seção enquanto a
  marca existir.
- A ficha catalográfica vem do gerador do SiBI (<http://fichacatalografica.sibi.ufrj.br/>). O
  modelo deixa uma folha reservada, e uma pessoa põe a ficha nela.
- As assinaturas, a aprovação do orientador e o depósito são do dono.
- O rig não sobe nada a lugar nenhum. Ele só escreve na caixa de saída (`/var/lib/rig-outbox/wave-forecaster-thesis`).
- A tese de graduação é um trabalho original do aluno. Nenhum portão prova originalidade
  (a regra U39 de `thesis ufrj-check` é `CANNOT-CHECK`). Quem usa o rig responde pelo que assina.

## As peças e como se ligam

![O rig da tese: o dono dá o pedido ao editor, que escreve o thesis.json; a librarian guarda as fontes e o refs.bib; três writers pegam uma seção cada com thesis fetch e entregam com thesis submit; a ferramenta thesis, com pandoc, o filtro Lua, o modelo e o pdfLaTeX, roda os portões; o reviewer registra o parecer com o hash; o assemble monta o PDF e roda pdf-qa e ufrj-check; o publish põe o PDF na caixa de saída, de onde o Hermes e o dono o leem; os seis seats rodam no Claude Code, no unit openrig de 2G.](img/pt/thesis-rig.png)

Página interativa: <https://www.piabrota.art/figures/pt-BR/thesis-rig/>

<details open>
<summary>Como ler esta figura</summary>

**Em uma frase.** Seis seats do Claude Code escrevem seções independentes, uma ferramenta sem modelo as confere e as monta, e um PDF sai numa caixa de saída que o dono lê.

**Como ler.** De cima para baixo e da esquerda para a direita, uma faixa por papel; a faixa do alto marca as cinco fases. A borda vermelha marca onde uma pessoa entra. Cada seta traz o comando ou o arquivo que passa de uma peça a outra. A seta de baixo mostra o que o ambiente dá à ferramenta.

**Fora da figura.** Os três writers aparecem como uma caixa só. Os peers que trocam mensagens (`collaborates_with`), a lista dos quatro portões (veja a tabela abaixo), os arquivos do projeto e o prompt de consentimento do Claude Code.

**Fonte.** [`docs/archify/pt/thesis-rig.json`](archify/pt/thesis-rig.json), a fonte da figura; `openrig/specs/rigs/wave-forecaster-thesis/rig.yaml`, `thesis/thesis`, `openrig.nix`. ⚠ Nenhum seat rodou esta rig: as setas são o desenho, não uma execução.

</details>

### Os seis seats

Os nomes dos seats são `<pod>-<membro>@wave-forecaster-thesis`. Os três writers usam a mesma spec
(`thesis-writer`) e diferem só na pasta, e por isso no nome. Todos rodam
`runtime: claude-code` no modelo `claude-sonnet-5-5`, com `permission_policy: builtin:yolo`.

|Seat|Pode|Não pode|Comandos|Arquivos|
|---|---|---|---|---|
|`plan-editor` (editor)|Planejar a partir do pedido do dono. Editar `thesis.json`, `notes/` e `data/`. Montar e publicar.|Usar a web. Editar `sections/**` (regra de ferramenta `Edit(...)`). Escrever prosa, `status` ou claim. Iniciar um seat.|`thesis new`, `sections`, `status`, `assemble`, `pdf-qa`, `publish`|`thesis.json`, `notes/facts.md`, `notes/glossary.md`|
|`writing-librarian`|Usar a web (`WebFetch`, `WebSearch`: o único seat). Escrever `sources/`, `refs.bib`, `REFERENCES.md`.|Editar seção, `thesis.json` ou `review/`. Inventar referência. Marcar `verified` o que não buscou.|`rig send` (para responder)|`sources/<chave>.md`, `refs.bib`, `REFERENCES.md`|
|`writing-writer-a`, `-b`, `-c`|Reservar e escrever uma seção por vez.|Usar a web. Ler o texto de outra seção. Mexer em arquivo de outro seat, em `thesis.json`, em `status` ou claim à mão.|`thesis fetch`, `release`, `build-section`, `slop`, `readability`, `cite-check`, `cite-score`, `submit`|`sections/<id>.md`|
|`review-reviewer`|Rodar os portões, escrever em `review/`, registrar o parecer.|Usar a web. Editar `sections/**` (regra de ferramenta). Julgar a seção que escreveu (o `verdict` recusa).|`thesis readability`, `slop`, `cite-check`, `cite-score`, `review-report`, `verdict`, `ufrj-check`, `pdf-qa`|`review/<id>.review.md`, `review/final.md`|

A web fica negada (`deny: [WebFetch, WebSearch]`) em todos os membros, menos na librarian. Uma regra
`deny` com o nome da ferramenta a remove do seat, mesmo no modo bypass. O `allow` da librarian só
registra a intenção, porque no modo bypass o `allow` não restringe. ⚠ A aplicação nativa dessas
regras não foi provada. As regras de `/etc/claude-code/managed-settings.json` valem em todos os
seats e não são um sandbox. O sandbox duro é o do unit `openrig`.

### O comando `thesis`

POSIX sh, `jq`, `awk`, pandoc e pdfLaTeX. Sem Python, sem rede, sem modelo. Cada comando roda com um
`PATH` que tem só essas ferramentas.

|Grupo|Comandos|
|---|---|
|Editor|`thesis new <slug> [--template <nome>]`, `sections [<slug>]`, `status <slug>`|
|Writer|`fetch <slug> [<id>] [--as <seat>]`, `release`, `build-section`, `submit`|
|Reviewer|`lint`, `readability`, `slop`, `cite-check`, `cite-score`, `ufrj-check`, `review-report <slug> <id\|final>`, `verdict <slug> <id> accept\|revise --by <seat> [--note <arquivo>]`|
|Montagem|`assemble <slug>`, `pdf-qa <slug>`, `publish <slug> [--replace]`|

Um seat se identifica por `--as`, por `THESIS_SEAT` ou pela pasta do membro em que está. As pastas
vêm de `THESIS_HOME` (padrão `/var/lib/openrig/work/wave-forecaster-thesis`) e `THESIS_OUTBOX`
(padrão `/var/lib/rig-outbox/wave-forecaster-thesis`).

## A árvore do projeto e o contrato

`thesis new <slug>` cria `projects/<slug>/` em `THESIS_HOME`:

|Caminho|O que é|Quem escreve|
|---|---|---|
|`thesis.json`|Título, autor, orientador, curso, mês, ano, modelo, seções (`id`, `role`, `order`, `brief`, `sources`, `target_words`). O `status` aqui é só `todo` ou `omit`.|O editor|
|`sections/<id>.md`|Uma seção em Markdown do pandoc.|O writer que a reservou|
|`sources/<chave>.md`|A captura de uma fonte: `URL:`, `Retrieved:`, `DOI check:` e uma passagem citada (linha com `>`).|A librarian|
|`refs.bib`|As entradas BibTeX.|A librarian|
|`REFERENCES.md`|A tabela `Key / Status / Checked against / Note`.|A librarian|
|`notes/`|`facts.md`, `glossary.md`, `thesis.log` e as perguntas `<id>.questions.md`.|O editor (e o log, a ferramenta)|
|`state/<id>.json`|O estado de uma seção: `status`, `by`, `sha`, `round`, `accepted_sha`.|Só `thesis`|
|`claims/<id>.claim`|Quem reservou a seção e quando.|Só `thesis`|
|`review/`|`<id>.gates.md` (a máquina), `<id>.review.md` (o reviewer), `<id>.verdict.md`, `final.md`.|O reviewer e `thesis`|
|`build/`|`thesis.pdf`, `qa.json`, `main.log`, `assembled.json`, a árvore TeX.|Só `thesis`|
|`figures/`, `assets/`|Figuras do texto; o logo da UFRJ (`assets.ufrj_logo`).|O editor, o dono|

E em `THESIS_HOME/out/<slug>/thesis.pdf`, o PDF montado. `thesis new` não cria `data/`, e as normas
dos seats mandam o editor pôr os dados do dono nessa pasta: o editor a cria. ⚠

### Uma seção, do claim ao parecer

1. **`thesis fetch <slug> [--as <seat>]`** reserva a próxima seção livre, na ordem, e imprime a ordem
   de trabalho. O claim é um arquivo criado com `set -C` (noclobber): a criação é atômica, e dois
   writers nunca reservam a mesma seção. Um seat que já tem um claim retoma o seu antes de pegar um
   novo. Um claim com mais de 7200 s (`limits.claim_stale_s`) é velho, e o próximo `fetch` o toma
   sob um lock (`mkdir`). Sem seção livre, `fetch` sai com o código 3.
2. **O writer escreve** `sections/<id>.md` e roda `build-section`, `slop`, `readability`,
   `cite-check` e `cite-score` quantas vezes quiser.
3. **`thesis submit <slug> <id>`** só vale para o dono do claim. Ele roda `lint`, `build-section`,
   `cite-check`, `slop` e `readability`. Se um falha, a seção não é entregue e o comando lista os
   motivos. Se todos passam, o `state/<id>.json` guarda `status: drafted`, o autor e o `sha256` do
   texto, e o claim some.
4. **O reviewer** roda os portões (`review-report` junta o resultado em `review/<id>.gates.md`),
   lê a seção contra `sources/<chave>.md`, `notes/facts.md` e `data/`, e escreve
   `review/<id>.review.md` à mão.
5. **`thesis verdict <slug> <id> accept|revise --by <seat>`** só vale para uma seção `drafted` ou
   `linted`, de outro autor (quem escreveu não julga), cujo texto ainda tem o `sha256` do `submit`.
   - `accept` exige `review/<id>.review.md`, roda os portões sobre o texto atual e recusa se um
     falhou. Registra `accepted_sha`.
   - `revise` devolve o claim ao writer e conta uma rodada. Na 4ª rodada (`max_review_rounds` é 3)
     o comando recusa e manda perguntar ao dono.
6. **Uma edição depois do `accept` muda o `sha256`.** A seção passa a `changed` e precisa de novo
   `submit` e novo `verdict`.
7. **`thesis assemble <slug>`** exige o `thesis.json` válido e toda seção não omitida `accepted`
   com o hash de hoje. Depois roda `lint` sem marcadores, o `cite-check` da obra inteira, monta o
   PDF e roda o `pdf-qa`. Grava `build/assembled.json` com o hash de cada seção.
8. **`thesis publish <slug>`** exige `qa.json` com `pass`, o PDF mais novo que o `thesis.json`, os
   hashes de `assembled.json` iguais aos de hoje e uma pasta de destino que não exista (ou
   `--replace`). Copia `thesis.pdf`, `qa.json`, `REFERENCES.md` e `review/` para a caixa de saída.

**O que isso não garante.** O hash é uma convenção de arquivos, não uma assinatura. Todos os seats
rodam como o mesmo usuário `openrig`, e `state/<id>.json` é um arquivo comum. As normas proíbem
escrevê-lo à mão, e nenhuma permissão o impede (inferência a partir das ferramentas). O parecer vale
o que vale a leitura do reviewer, que é outro seat do mesmo modelo.

## O modelo

### O primeiro modelo: forecast-energy-demand

O modelo é o repositório [h0ffmann/forecast-energy-demand](https://github.com/h0ffmann/forecast-energy-demand),
do dono, no commit `a9a35ee4223037469c0ed35b22ecf510417de86e` (2026-04-17), preso por hash em
`thesis/default.nix`. O repositório não tem arquivo de licença. O dono o escreveu e mandou usá-lo.
Só os arquivos que o overlay usa entram no pacote: `docs/project/pt/project_main.tex` (só a linha
`\documentclass` é lida), `shared/thesis_pack.tex`, `shared/page.sty`, `shared/portland.sty` e o logo
da Poli em PDF. O pacote não copia nada para este repositório.

### O overlay

O overlay (`thesis/templates/forecast-energy-demand/overlay/`: `main.latex`, `preamble.tex`,
`preview.latex`) preenche as lacunas do modelo contra as regras da UFRJ e nunca edita um arquivo
fixado. Ele acrescenta (de `template.json`):

- a capa, a folha de rosto e a folha de aprovação, preenchidas de `thesis.json` (a `cover.tex` do
  modelo tem texto fixo);
- a folha da ficha catalográfica (reservada: a ficha vem do SiBI);
- as folhas de resumo e abstract, com referência e palavras-chave, e as de dedicatória e agradecimentos;
- os números romanos na parte pré-textual e um contador de folhas para a ficha;
- o corpo em Times (TeX Gyre Termes), espaço simples em citações longas, legendas e referências,
  legendas no padrão da ABNT;
- o capítulo de referências, os apêndices e as listas de figuras e tabelas.

Ele mantém as margens, o espaçamento de 1,5 e o estilo de página de `shared/page.sty` e
`thesis_pack.tex`. A execução que construiu as ferramentas mandou o título dos capítulos para
24 pt (era 24,88) para caber em "Times 24".

### Por que o `coppe.bst` não é usado

O `project_main.tex` do modelo pede `\bibliographystyle{coppe}`, mas o repositório não traz o
`coppe.bst`, e ele não está no TeX Live do nixpkgs (a execução conferiu os nomes de `texlive.pkgs`).
Então as referências saem do `pandoc --citeproc` com o CSL ABNT autor-data do repositório
citation-style-language/styles, no commit `b0114efe` (hash em `thesis/default.nix`, licença
CC BY-SA 3.0), com uma mudança: o sobrenome na citação no texto fica em maiúsculas
("(TOLMAN, 2009)"). O arquivo diz isso num comentário, como a licença pede.

Defeitos que os testes acharam nesse CSL:

- ele descarta o `booktitle` de um `@inproceedings` se não houver `eventtitle` (por isso o `cite-check`
  exige os dois);
- ele letra mal as entradas com o mesmo autor e ano (`a2022`, e também na data de acesso). O
  `cite-check` avisa.

⚠ A exatidão do CSL contra a NBR 6023:2025 e a NBR 10520:2023 **não foi verificada**.

### O pandoc, o filtro Lua e o TeX bruto

O pandoc lê o Markdown de cada seção e escreve LaTeX. Ele também preenche `main.latex` com os dados
de `thesis.json`, já escapados para LaTeX. O pandoc faz as referências com `--citeproc`. O filtro
`thesis/filters/thesis.lua` roda antes disso e faz três coisas:

1. as referências cruzadas (`@fig:nome`, `@tbl:nome`, `@eq:nome`, `@sec:nome`, `@cap:<id>`), no lugar do
   `pandoc-crossref`, cujo fecho tem 5,5 GiB;
2. o escopo dos rótulos: o id da seção entra no rótulo, e duas seções podem usar o mesmo nome;
3. a segurança: em matemática, só passam as macros da lista `math_macros` (206 na `profile.json`),
   e `^^`, `%` e `#` são recusados. Caminhos de imagem ficam em `figures/`.

O leitor roda com `markdown-raw_tex-raw_attribute-raw_html-yaml_metadata_block-latex_macros-auto_identifiers`.
**O TeX bruto está desligado de propósito:** um seat que escreve `\write18` ou `\input` não chega ao
TeX. A matemática é o único caminho em que o texto do autor chega ao TeX como foi escrito, e por
isso tem a lista de macros. O pdfLaTeX roda com `-no-shell-escape`, `-halt-on-error` e um limite de
120 s (`tex_timeout_s`); o pandoc tem 60 s (`pandoc_timeout_s`).

O pdfLaTeX, e não o XeTeX: o Tectonic, que o CI do modelo usa, busca o seu bundle na rede. Por isso
um emoji é recusado por `lint` e `build-section` (o pdfLaTeX não o desenha), em vez de quebrar a
montagem sem aviso.

### A interface do modelo e o segundo modelo

Os comandos leem só o `template.json` de `thesis/templates/<nome>/` (a chave `interface` é 1):
fonte e commit, o motor e as flags, o modo de bibliografia e o CSL, o arquivo principal, as pastas
fixadas, o overlay e as seções padrão (10 seções: resumo, abstract, agradecimentos, introdução,
fundamentação, relacionados, desenvolvimento, resultados, conclusões e apêndices; agradecimentos e
apêndices começam `omit`). `thesis new <slug> --template <nome>` escolhe o modelo.

Para somar o [CoppeTeX](https://github.com/COPPE-UFRJ/CoppeTeX) (`ufrj.cls[grad]` com `ufrj-poli`,
GPL-3, biblatex com estilos ABNT, PDF/A-2b), cria-se uma pasta nova com o seu `template.json`, o seu
overlay e os arquivos fixados. Nenhum comando muda. **Não foi feito:** os seus fixos, a troca do
modo de bibliografia para biblatex e o conjunto TeX ainda não existem. Por ser GPL-3, o pacote dele
não pode misturar-se ao MPL-2.0 sem checar a licença. ⚠

## Os quatro portões

Um portão é uma regra local e simples. Nenhum usa modelo ou rede. Os números estão em
`thesis/profile.json`, e **nenhum arquivo, além dele, guarda um limite**. A lista `unverified` do
mesmo arquivo diz que estes números são palpites do autor das ferramentas.

|Portão|Comando|O que mede|Números|O que **não** prova|
|---|---|---|---|---|
|1. pt-BR legível|`thesis readability`|Tamanho das frases e dos parágrafos, voz passiva, índice tipo Flesch para o português, anglicismos fora do glossário, termos mistos, figuras e tabelas citadas.|Média de frase até 28 palavras; frase longa tem mais de 40 e pode ser até 8 % das frases; parágrafo até 220 palavras; parágrafo de uma frase até 25 %; passiva até 30 %; Flesch-pt a partir de 25; 3 anglicismos distintos reprovam (69 listados); a taxa só vale com 5 frases ou mais.|Que o texto é claro, correto ou verdadeiro. A passiva com "-se" não é contada. As constantes do Flesch (Martins et al., 1996) vêm de memória, e o contador de sílabas é uma heurística.|
|2. slop|`thesis slop`|Padrões de superfície de texto de modelo: frases feitas (100 listadas), travessões, listas de três, mesma abertura em três frases, pouca variação de frase, fecho-resumo, 4-gramas repetidos, hedges (19), negritos no início, título repetido, conectivos (24).|Nota de 0 a 100, soma de 11 sinais com pesos; reprova com 35 ou mais; abaixo de 120 palavras não pontua.|Autoria. Ver abaixo.|
|3. UFRJ|`thesis ufrj-check`|Os padrões gráficos e de estrutura do projeto de graduação, no PDF e em `thesis.json`: PASS, FAIL ou CANNOT-CHECK, com a fonte da regra. Ver "As regras da UFRJ".|Margens mínimas 25, 25, 30, 30 mm; A4; corpo 12 pt; título até 24 pt; resumo e abstract até 250 palavras, com 3 a 6 palavras-chave.|A forma de cada referência, a cor das figuras, a originalidade, a ortografia e o Manual do SiBI.|
|4. citações|`thesis cite-check`, `cite-score`|Cada chave citada está em `refs.bib`, tem linha `verified` em `REFERENCES.md` e um `sources/<chave>.md` com `URL`, `Retrieved`, `DOI check` e uma passagem; campos obrigatórios por tipo; citação numérica; citação em linha com mais de 40 palavras.|Estados `verified`, `partial`, `unverified`. O `cite-score` é só informativo: alvo 0,60 (alto), 0,30 (médio), 0,08 (baixo).|Que a fonte diz o que a frase afirma. Isso o reviewer lê.|

### Slop, com franqueza

O portão 2 **não é um detector de IA**. Ele conta padrões de superfície com listas e pesos que o
autor das ferramentas escolheu. Não houve comparação com um detector externo, e ele não promete
nenhuma nota em nenhuma ferramenta de fora. Uma pessoa também escreve alguns desses padrões, e um
texto de modelo pode passar. Uma paráfrase da mesma frase mantém o padrão e o conteúdo vazio.

**A correção de verdade** é outra: reescrever a partir dos fatos (o número, a fonte, a decisão) e pôr
o que só o autor sabe, nas marcas `**[AUTHOR: ...]**`, sem inventar experiência. As normas dos
seats dizem isso, e a mensagem do próprio comando também. Não se deve jogar contra a nota.

### O parecer humano

`thesis review-report` roda `lint`, `readability`, `slop`, `cite-check` e `cite-score` sobre uma seção
e escreve `review/<id>.gates.md`. Ele deixa três perguntas sem resposta de máquina: a fonte diz o que a
frase diz? O texto é claro para um aluno do curso? Algum fato foi inventado? O reviewer responde em
`review/<id>.review.md`.

## As regras da UFRJ

|Fonte|Estado|O que traz|
|---|---|---|
|R: Resolução nº 05/2012 da Escola Politécnica, Anexo "Normas de Elaboração Gráfica do Projeto de Graduação"|**Em vigor**|Português; A4; espaço 1,5 ou 2; Times 12; título até Times 24; texto justificado; margens mínimas 25, 25, 30 e 30 mm; capa, folha de rosto, folha de aprovação, ficha catalográfica, resumo e abstract, sumário; números romanos antes do texto e arábicos depois; legenda de tabela em cima e de figura embaixo; um só sistema de referências; trabalho original.|
|N: Norma Gráfica 2026|**Proposta** para a Congregação, ainda não aprovada. A de 2012 vale até lá.|Capa com o logo da UFRJ à esquerda e o da Poli à direita, o nome da instituição em três linhas; folha de rosto e de aprovação sem logo; a frase de "natureza"; resumo e depois abstract, cada um na sua folha, até 250 palavras; ficha do gerador do SiBI; NBR 6023:2025 e NBR 10520:2023.|
|M: Manual do SiBI para trabalhos acadêmicos da UFRJ (9ª ed., 2025)|⚠ Lido só como trechos de busca, não por inteiro|Espaço 1,5 no texto; espaço simples em citações longas, notas, referências e legendas.|

O `thesis ufrj-check <slug>` imprime uma linha por regra, no formato
`PASS|FAIL|CANNOT-CHECK [fonte] Uxx regra: detalhe`, e uma linha final com as somas. Ele sai com erro
se há um `FAIL`. Na tese de exemplo deu **34 PASS, 0 FAIL e 7 CANNOT-CHECK**.

Os 7 `CANNOT-CHECK` são o que **fica por conta do dono**:

|Regra|O que ninguém confere por script|
|---|---|
|U13|se uma figura dentro de um capítulo é um logo|
|U20|a ficha catalográfica em si (do gerador do SiBI)|
|U27|a forma de cada referência e de cada citação contra a NBR 6023:2025 e a NBR 10520:2023|
|U36|a cor dentro das figuras (devem ler-se em preto e branco)|
|U39|a originalidade e o crédito a terceiros|
|U40|a ortografia atual|
|U41|o Manual do SiBI, lido só em trechos|

Além disso: as assinaturas, a aprovação do orientador e o depósito. **O modelo não traz o logo da
UFRJ.** O dono põe um arquivo (PDF, PNG ou JPEG) em `assets/` e aponta `assets.ufrj_logo` em
`thesis.json`. Sem ele, a regra U11 dá `FAIL`. O `thesis new` põe `Engenharia Eletrônica e de
Computação` como curso. A lista de cursos da `profile.json` tem 14.

## Citações do jeito do closed-source

O dono pediu citação profissional como a do repositório
[h0ffmann/closed-source](https://github.com/h0ffmann/closed-source) (*The god that failed*, texto em
CC BY 4.0, commit `6b3aae557f69ab89ec747364311978928dd0ca71`). As regras de lá, aplicadas aqui:

- **Nunca inventar uma referência.** A librarian busca cada fonte antes de a chave existir e registra
  a conferência em `REFERENCES.md`.
- **Estados.** `verified`: buscada, e os dados batem. `partial`: buscada, e um detalhe não foi
  confirmado (o detalhe sai do `refs.bib`, e a nota diz `unconfirmed: campo`). `unverified`: não
  buscada, e **não pode ser citada**.
- **`cite-check`** falha se uma chave citada não está em `refs.bib`, se não tem linha, se o estado não
  é `verified`, se falta o `sources/<chave>.md`, se um campo obrigatório do tipo falta (as listas por
  tipo vêm da memória do autor, não da norma), se há duas linhas ou duas entradas para a mesma chave,
  se uma entrada não é citada por nenhuma seção, ou se um campo `unconfirmed` ficou no `refs.bib`.
  A conferência de que a fonte sustenta a frase não é de máquina.
- **Marcas do texto.** `**[AUTHOR: ...]**` para o que só o autor sabe e `**[ANALYSIS]**` para
  interpretação, em parágrafo separado do fato. O `lint` recusa as duas marcas, no `submit` e na
  montagem: elas são do editor e do dono, e saem do texto antes da entrega.
- **`cite-score`.** É a ideia da skill `citation-score` do closed-source: a fração das frases com 3
  palavras ou mais que levam uma marca de citação. Ele conta marcas, não verdade. Nenhum alvo é uma meta
  para toda seção. Aqui ele só informa (`--strict` o torna um portão).

Créditos: o `AGENTS.md` de forecast-energy-demand esboça os agentes de tese (revisão de português,
consistência de números, agente de citações) e deu as ideias de frases longas, voz passiva e
afirmações sem `\cite{}`. As regras do Vale do closed-source, em inglês, deram a ideia dos sinais de
slop para o português, sem os arquivos. O CoppeTeX (GPL-3) é um segundo modelo possível. O CSL é do
projeto citation-style-language (CC BY-SA 3.0).

## Notas de deploy

Estas notas valem para quem faz o deploy: o dono, com o Hermes quando o dono pede.

1. **Fazer o merge do PR do rig.** Uma pessoa faz o merge. O `deploy.yml` roda no push para `main`.
   Com a opção desligada (o padrão), o rig fica só como definição: as specs entram em
   `/etc/openrig/specs`, e não entram `thesis`, `claude`, pastas, caixa de saída nem
   `managed-settings.json`. Não foi medido se o unit `openrig` reinicia nesse deploy. Antes do merge,
   confira que nenhum seat trabalha: `rig ps --nodes --active`.
2. **Ligar a opção, num PR pequeno.** Em `hosts/piabrota2/default.nix`, ao lado de
   `piabrota.openrig.waveForecaster.enable = false;`, ponha
   `piabrota.openrig.thesis.enable = true;`. A exceção unfree de `claude-code` já está em
   `unfree.nix`. As peças do Claude (o `claude` do `seatClaude` e `managed-settings.json`) ligam
   quando a rig do port **ou** a da tese está ligada. No PR, meça o crescimento com
   `just build piabrota2` antes e depois, e `nix run nixpkgs#dix -- diff <antigo> <novo>`.
   **O crescimento do sistema não foi medido.** O fecho do pacote `thesis` é de 727,3 MiB (pandoc 283,
   poppler-utils 143, conjunto TeX 483,2 com perl e ghostscript, partes comuns contadas uma vez), e o
   Claude Code traz cerca de +280 MiB (`docs/OPENRIG.md`). Os dois não se somam sem conferir, pois
   dividem caminhos. Com a opção, o `nix build --dry-run` listou 11 derivações a construir, contra 3
   sem ela; o tamanho do que se busca não foi medido.
3. **O que esse deploy reinicia.** Ele muda o unit `openrig` (`path`, `StateDirectory`,
   `ReadWritePaths`), então o systemd reinicia o unit e **encerra todos os seats vivos**
   (`KillMode=control-group`; veja "O que um deploy faz com os seats" em
   [`OPENRIG.md`](OPENRIG.md)). Ninguém reinicia um rig depois. Faça o deploy com a máquina quieta.
4. **Disco.** Veja `df -h /` e a linha de disco de `kvm4-health` antes e depois. O disco do plano é
   de 200 GB (`AGENTS.md`); o espaço usado pelo pacote além do fecho não foi medido. O GC roda toda
   semana e remove caminhos com mais de 14 dias.
5. **Conferir.** Depois do deploy:

   ```console
   systemctl status openrig
   rig status                                   # deve dizer "Daemon running"
   test -f /etc/claude-code/managed-settings.json && echo managed-ok
   ls -ld /var/lib/rig-outbox /var/lib/rig-outbox/wave-forecaster-thesis   # openrig:hermes, 0750
   sudo -u openrig bash -lc 'command -v thesis claude pandoc pdflatex pdftotext'
   sudo ls /var/lib/openrig/work/wave-forecaster-thesis   # editor writer-a writer-b writer-c librarian reviewer projects out
   ```

   O `sudo -u openrig bash -lc` é para o dono (o Hermes não usa `sudo`). O shell de login monta o
   `PATH` do perfil do usuário `openrig`, o mesmo que um painel de seat usa.
6. **Importar a rig.** Uma spec não é uma rig: a UI só lista a rig depois do import.

   ```console
   rig spec validate /etc/openrig/specs/rigs/wave-forecaster-thesis/rig.yaml
   rig import /etc/openrig/specs/rigs/wave-forecaster-thesis/rig.yaml --materialize-only
   rig ps --nodes --rig wave-forecaster-thesis
   ```

   O import registra os seis seats e não inicia nenhum. ⚠ O `rig spec validate` não foi rodado
   aqui para esta spec.
7. **Primeira partida de um seat e o prompt de consentimento.** Um seat que nunca rodou parte com
   `rig launch wave-forecaster-thesis plan.editor`. Um que já rodou, com
   `rig seat launch plan-editor@wave-forecaster-thesis --fresh --reason "<motivo>"`. O Claude Code pede
   uma vez para aceitar o aviso do modo bypass, e o OpenRig mostra o seat em `attention_required`.
   **Mostre o painel ao dono** (`rig capture plan-editor@wave-forecaster-thesis --lines 40`) **e deixe o
   dono responder** (`rig seat continue` ou a UI). O Hermes nunca responde a um prompt de consentimento.
   ⚠ Não foi provado se há também um diálogo de confiança na primeira execução.
8. **O login.** O unit dá a cada seat `ANTHROPIC_API_KEY` com o token da assinatura do dono, e o
   `seatClaude` o move para `CLAUDE_CODE_OAUTH_TOKEN`. Não há chave de API. Se `rig capture` mostrar um erro
   de login, avise o dono e não procure outro token.
9. **O spike de memória.** A memória de um seat do Claude Code **não foi medida**, e o unit tem
   `MemoryHigh=1536M` e `MemoryMax=2G`. Inicie um seat, deixe-o trabalhar, e leia
   `systemctl show openrig -p MemoryCurrent -p MemoryPeak`. Depois inicie dois e leia de novo.
   Registre os números num PR que mude [`OPENRIG.md`](OPENRIG.md). **Até lá, no máximo dois seats.** Os
   três writers juntos só depois de o dono medir e subir o limite.
10. **Rodar por fases, dois seats por vez.** Nunca junto com outro rig.

    |Fase|Seats|O que acontece|Termina quando|
    |---|---|---|---|
    |0, pedido|nenhum|O dono decide título, autor, orientador, curso, seções, resultados e fontes, e os dá ao operador, que os manda ao editor.|O editor tem tudo.|
    |1, plano|editor e librarian|O editor roda `thesis new`, preenche `thesis.json`, `notes/glossary.md` e `notes/facts.md`. A librarian verifica as fontes e escreve `refs.bib` e `REFERENCES.md`.|`thesis status <slug>` mostra toda seção `todo` com fontes verificadas. Pare os dois.|
    |2, escrita|writer-a e writer-b, depois writer-c|Cada um repete `thesis fetch`, escreve, `thesis submit`. Quem precisa de uma fonte pede à librarian, que entra no lugar de um writer.|Nenhuma seção está `todo`.|
    |3, revisão|reviewer, com o editor ou um writer|Os portões, a leitura contra as fontes, o parecer. Um `revise` volta a um writer, que entra no lugar de outro seat. No máximo 3 rodadas por seção.|Toda seção `accepted`.|
    |4, montagem|editor e reviewer|O editor roda `assemble` e `pdf-qa`. O reviewer roda os portões finais e escreve `review/final.md`. O editor roda `publish`.|O PDF está na caixa de saída. O dono lê e decide.|

11. **Como o Hermes lê a caixa de saída.** O Hermes está no grupo `hermes`, que lê
    `/var/lib/rig-outbox/wave-forecaster-thesis` (dono `openrig`, grupo `hermes`, 0750, ACL padrão
    para o grupo). A pasta `<slug>/` traz `thesis.pdf`, `qa.json`, `REFERENCES.md` e `review/`. O
    Hermes lê o `qa.json` e o `review/final.md`, e conta ao dono o que falta. Ele não lê
    `/var/lib/openrig` (a lista de bloqueio impede). O arquivo some depois de 14 dias.
12. **Backup.** O estado fica em `/var/lib/openrig/work/wave-forecaster-thesis` (`projects/` e
    `out/`). Nada nesta máquina o copia: não há backup configurado para essa pasta. O dono copia
    `projects/<slug>` e o PDF para fora da máquina ao fim de cada fase, por exemplo
    `sudo tar -C /var/lib/openrig/work/wave-forecaster-thesis -czf <destino>/<slug>.tar.gz projects/<slug>`.
13. **Mudar o rig.** Edite as specs ou o `thesis/` num PR. O merge atualiza `/etc/openrig/specs`, e um
    seat que roda mantém o texto antigo. Um rig guarda a spec de que nasceu: peça o ok do dono,
    rode `rig archive wave-forecaster-thesis` e importe de novo (passo 6). Uma mudança no `thesis/`
    chega ao seat pelo deploy e pelo relançamento do seat.
14. **Voltar atrás.** Ponha `piabrota.openrig.thesis.enable = false;` e faça o deploy. O unit
    reinicia, os seats acabam, e `thesis` sai do `PATH`. O estado em
    `/var/lib/openrig/work/wave-forecaster-thesis` fica. O que faz os PDFs da caixa de saída
    sumirem em 14 dias é a regra `d ... 14d` que a opção cria: sem a opção, a regra some, e
    os arquivos ficam até alguém os apagar (inferência, não testada). Copie os PDFs antes.

### O que pode dar errado

|Sintoma|Causa provável|Correção curta|
|---|---|---|
|`claude: command not found` num painel|A opção está desligada, o deploy não acabou, ou o seat partiu antes do deploy e mantém o `PATH` antigo.|Confira a opção e `readlink /run/current-system`; relance o seat com `rig seat launch <seat> --fresh --reason "<motivo>"`.|
|`thesis: command not found`|O mesmo.|O mesmo; confira com `sudo -u openrig bash -lc 'command -v thesis'`.|
|`assemble` para por tempo do TeX|O pdfLaTeX passou de 120 s (`tex_timeout_s`; o limite é um palpite). Na tese de exemplo, a montagem levou 2,5 a 3 s.|Leia `build/main.log`. Procure uma figura enorme ou um laço de referências. Mude o limite em `profile.json` num PR, ou com `THESIS_TEX_TIMEOUT`.|
|Um claim travado|Um writer parou no meio. O claim só fica velho depois de 7200 s.|O dono do claim roda `thesis release <slug> <id> --as <seat>`. Outro seat usa `--force`, ou espera o claim ficar velho e roda `thesis fetch`.|
|`assemble` recusa|Uma seção não está `accepted` (a edição depois do `accept` conta como `changed`), `thesis.json` está incompleto (`A PREENCHER`, logo da UFRJ), uma marca `**[AUTHOR ...]**` ficou, ou o `cite-check` da obra inteira falha (entrada citada por nenhuma seção, linha sem entrada).|`thesis status <slug>` lista o que bloqueia. Corrija, faça `submit` e `verdict` de novo, e rode `assemble`.|
|`verdict revise` recusa|A seção já teve 3 rodadas.|Pergunte ao dono.|
|`publish` recusa|Já existe a pasta no `outbox`, ou o `thesis.json` é mais novo que o PDF, ou uma seção mudou depois da montagem.|`thesis publish <slug> --replace`, ou monte de novo.|

## O que está provado e o que não está

**Provado** (execução de 2026-11-05, sem seat):

- O `thesis` real sobre uma tese de exemplo (15 páginas, 8 seções, PDF de cerca de 100 KB):
  `thesis/test/run.sh` deu **60 verificações, 0 falhas**. Elas cobrem nomes, `fetch` em paralelo,
  recusa de marcador, `accept`, edição e `assemble`, `cite-check` com fonte não verificada e
  verificada, `slop` com falha e com aprovação, TeX bruto escapado, a lista de macros de matemática,
  caracteres hostis, emoji recusado, arquivo de modelo ausente, TeX parado por tempo e `publish` sem
  `--replace`.
- `shellcheck` limpo, e `nixpkgs-fmt`, `statix` e `deadnix` sem aviso nos arquivos Nix.
- A avaliação de `piabrota` (igual à do `main`) e de `piabrota2`, com a opção desligada e ligada.
- Nos testes: a montagem leva 2,5 a 3 s, e o maior processo (pdfLaTeX) usa 135 MiB de pico.
- Os nomes e caminhos das specs batem com o `thesis`: nenhum desencontro.

**Não provado:**

- Uma execução real com seats do Claude Code: a partida, o login, o aviso do bypass, as mensagens
  entre seats, as regras `deny` de ferramenta.
- A memória do Claude Code.
- A exatidão do CSL contra a NBR 6023:2025 e a NBR 10520:2023.
- Todos os números da lista `unverified` de `profile.json`: limites de tempo, de claim e de rodadas;
  limites de legibilidade e a constante do Flesch; pesos do slop; alvos do `cite-score`; as listas de
  campos obrigatórios por tipo; a lista de anglicismos e termos mistos; a tolerância do
  espaçamento medida só no PDF de exemplo.
- O Manual do SiBI, lido só em trechos.
- O crescimento do sistema com `dix`, o tamanho do que se busca e o teste `passthru.tests.run` no Nix
  (só o `run.sh` contra o pacote construído).

## Limites e riscos

- **O unit de 2G.** O OpenRig, o tmux e todos os seats dividem `MemoryMax=2G` (`MemoryHigh=1536M`). Por
  isso são dois seats por vez, e as fases existem.
- **A memória de um seat do Claude Code** não foi medida (veja o spike, passo 9).
- **O tamanho do pacote:** 727,3 MiB de fecho, mais o Claude Code. A regra 1 de "Resource budget" do
  `AGENTS.md` pede uma razão para mais que alguns MiB, e o PR da opção deve trazer a medida do `dix`.
- **pdfLaTeX, não XeTeX.** O pdfLaTeX não usa as fontes do sistema, o emoji é recusado, e um
  caractere fora da lista `allowed_chars` é recusado com uma mensagem clara.
- **Defeitos do CSL** (acima): `booktitle` descartado sem `eventtitle`, letras `a2022` mal postas.
- **Heurísticas de pt-BR rodam sobre o abstract em inglês.** O `readability` não distingue o idioma.
  O abstract pode falhar ou passar por acaso. ⚠
- **O que o PDF de exemplo mostrou de ruim.** O título de capítulo vem com "Capítulo 1" e muito
  branco, "WAVEWATCH" aparece hifenizado no corpo (falta uma exceção de hifenização) e a matemática
  sai em Computer Modern ao lado do texto em Termes. A folha de rosto e a de aprovação já não hifenizam.
- **Quatro desencontros entre as specs e o `thesis`** (nada foi corrigido aqui; ⚠ cada um precisa de um PR):
  1. As normas mandam marcar a análise com `**[ANALYSIS]**`, e o `submit` recusa essa marca. Um
     writer que a siga não consegue entregar a seção.
  2. A `role.md` do reviewer roda `pdftoppm`, mas só o comando `thesis` está no `PATH` do seat
     (o poppler fica dentro do invólucro do `thesis`).
  3. A ordem de trabalho manda perguntar em `notes/<id>.questions.md` e seguir escrevendo, e a
     `role.md` do writer manda soltar a seção (`thesis release`) e avisar o editor.
  4. `thesis new` não cria `data/`, que as normas citam.
- **Os seats podem errar de um jeito que o portão não vê.** Os portões olham a forma. O parecer
  humano e a leitura do dono pegam o resto.
- **Os seis seats são todos o mesmo modelo.** O reviewer não é um segundo par de olhos independente.

## Créditos

- [h0ffmann/forecast-energy-demand](https://github.com/h0ffmann/forecast-energy-demand): o primeiro
  modelo e as ideias do seu `AGENTS.md`.
- [h0ffmann/closed-source](https://github.com/h0ffmann/closed-source) (CC BY 4.0): as invariantes de
  citação, `REFERENCES.md` e a ideia do `citation-score`.
- [COPPE-UFRJ/CoppeTeX](https://github.com/COPPE-UFRJ/CoppeTeX) (GPL-3): o segundo modelo possível e a
  proposta de norma gráfica de 2026.
- [citation-style-language/styles](https://github.com/citation-style-language/styles): o CSL ABNT.
- [OpenRig](https://github.com/mvschwarz/openrig), de mvschwarz (Apache-2.0).
- Claude Code, da Anthropic.
