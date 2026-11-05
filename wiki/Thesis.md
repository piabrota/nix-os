# A tese

[English](Thesis-EN)

O rig `wave-forecaster-thesis` do [OpenRig](https://github.com/mvschwarz/openrig) escreve um projeto de
graduação da Escola Politécnica da UFRJ, em português, e entrega um PDF. Seis seats do Claude Code
(editor, librarian, três writers e reviewer) escrevem seções independentes. O comando `thesis`, sem
modelo e sem rede, reserva as seções, roda quatro portões e monta o PDF. O guia completo, com as
notas de deploy, é o
[`docs/THESIS.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/THESIS.ptBR.md).

**Não é um ghost-writer.** O dono dá os fatos, os dados, as decisões e as fontes. O rig escreve, confere
e diagrama. O dono lê, assina e deposita. A ficha catalográfica vem do gerador do SiBI.

![O rig da tese: o dono dá o pedido ao editor, que escreve o thesis.json; a librarian guarda as fontes e o refs.bib; três writers pegam uma seção cada com thesis fetch e entregam com thesis submit; a ferramenta thesis, com pandoc, o filtro Lua, o modelo e o pdfLaTeX, roda os portões; o reviewer registra o parecer com o hash; o assemble monta o PDF e roda pdf-qa e ufrj-check; o publish põe o PDF na caixa de saída, de onde o Hermes e o dono o leem; os seis seats rodam no Claude Code, no unit openrig de 2G.](img/pt/thesis-rig.png)

Página interativa: <https://www.piabrota.art/figures/pt-BR/thesis-rig/>

<details open>
<summary>Como ler esta figura</summary>

**Em uma frase.** Seis seats do Claude Code escrevem seções independentes, uma ferramenta sem modelo as confere e as monta, e um PDF sai numa caixa de saída que o dono lê.

**Como ler.** De cima para baixo e da esquerda para a direita, uma faixa por papel; a faixa do alto marca as cinco fases. A borda vermelha marca onde uma pessoa entra. Cada seta traz o comando ou o arquivo que passa de uma peça a outra.

**Fora da figura.** Os três writers aparecem como uma caixa só; os quatro portões, os arquivos do projeto e o prompt de consentimento do Claude Code.

**Fonte.** [`docs/archify/pt/thesis-rig.json`](https://github.com/piabrota/nix-os/blob/main/docs/archify/pt/thesis-rig.json), a fonte da figura; `openrig/specs/rigs/wave-forecaster-thesis/rig.yaml`, [`docs/THESIS.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/THESIS.ptBR.md). ⚠ Nenhum seat rodou esta rig: as setas são o desenho, não uma execução.

</details>

## As cinco fases

Dois seats por vez, nunca junto com outro rig. O unit `openrig` tem 2G, e a memória de um seat do
Claude Code não foi medida.

|Fase|Seats|O que acontece|
|---|---|---|
|0, pedido|nenhum|O dono decide título, autor, orientador, curso, seções, resultados e fontes.|
|1, plano|editor, librarian|`thesis new`, `thesis.json`, fontes verificadas em `REFERENCES.md`.|
|2, escrita|writer-a, writer-b, depois writer-c|`thesis fetch`, escrever, `thesis submit`.|
|3, revisão|reviewer|Os portões e o parecer, com o hash. No máximo 3 rodadas por seção.|
|4, montagem|editor, reviewer|`thesis assemble`, `pdf-qa`, `ufrj-check`, `thesis publish`. O dono lê o PDF.|

## Os quatro portões

Legibilidade em pt-BR, slop, regras da UFRJ e citações. São regras locais de superfície, sem detector
externo e sem promessa de nota. Cada portão diz o que **não** prova, e o `ufrj-check` marca o que
fica por conta do dono (a ficha, a originalidade, a ortografia).

## Como começar

1. Fazer o merge do PR do rig. Com a opção desligada, o rig é só uma definição.
2. Num PR pequeno, ligar `piabrota.openrig.thesis.enable = true;` em `hosts/piabrota2/default.nix`.
3. Depois do deploy: `rig import /etc/openrig/specs/rigs/wave-forecaster-thesis/rig.yaml --materialize-only`.
4. Iniciar um seat, mostrar o prompt de consentimento do Claude Code ao dono, medir a memória e só então
   rodar por fases.

Os passos completos, com os comandos e o que pode dar errado, estão em
[`docs/THESIS.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/THESIS.ptBR.md), "Notas de deploy".
Nenhum seat rodou esta rig ainda.
