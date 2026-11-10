# Maquetes da home de piabrota.art

[English](Mockups)

Três direções para a home de [piabrota.art](https://www.piabrota.art), cada uma em desktop (1280 px)
e celular (390 px). São SVGs gerados em Nix puro (`mockups/`), como o desenho 无 do README: nenhum
programa de desenho, nada para instalar. Os fatos vêm do perfil da org
([piabrota/.github](https://github.com/piabrota/.github), `profile/README.md`), copiados em
`mockups/data.nix`. O site builda as três em Gleam, a partir do mesmo
`mockups/data.nix`: a A em [www.piabrota.art](https://www.piabrota.art/), a B em
[/index/](https://www.piabrota.art/index/), a C em [/paths/](https://www.piabrota.art/paths/).

## A · fabric

O perfil da org como página: escura, o vermelho do logo, os projetos em cartões nas faixas da
figura "How it fits" (pensar e escrever, avisar e hospedar, jogar). Cada cartão diz onde o projeto
encontra a web, com um ponto verde (no ar), amarelo (chegando) ou cinza (sem site).

| Desktop | Celular |
|---|---|
| ![Maquete A, fabric, desktop](mockups/fabric-desktop.svg) | ![Maquete A, fabric, celular](mockups/fabric-mobile.svg) |

## B · index

Uma lista editorial: clara, a marca PIABROTA grande em vermelho, uma linha numerada por projeto,
com o endereço, o estado e a licença à direita (embaixo, no celular).

| Desktop | Celular |
|---|---|
| ![Maquete B, index, desktop](mockups/index-desktop.svg) | ![Maquete B, index, celular](mockups/index-mobile.svg) |

## C · paths

A página de hoje com um bloco a mais: o 无 e o nome ficam, e embaixo vem uma listagem, como um
terminal, do que responde em piabrota.art e de onde o resto mora. É a menor mudança.

| Desktop | Celular |
|---|---|
| ![Maquete C, paths, desktop](mockups/paths-desktop.svg) | ![Maquete C, paths, celular](mockups/paths-mobile.svg) |

## Contagem de commits

Cada projeto que mora em um repositório próprio da org mostra dois números: no cartão (A), na linha
(B e C) e na entrada do inventário. São os commits da branch padrão, humanos e de agentes. O campo
`commits` de cada projeto em `mockups/data.nix` guarda os números, e `commitsAsOf` guarda o dia em
que foram lidos. Um projeto sem `commits` (o hermes e os repositórios pessoais) não mostra nada. O
build não tem rede, então os números só mudam quando alguém os atualiza.

- Regra: um commit é de agente quando o login do autor no GitHub termina em `[bot]` ou é exatamente
  `claude`, a conta que o GitHub associa ao autor do Claude Code. Todo outro commit é humano.
- Limite: um commit que uma pessoa fez com a ajuda de um agente, em seu próprio nome, conta como
  humano. A regra do repositório é "nenhum rastro de agente em um commit", então não dá para
  distinguir os dois. O número de agentes é um piso.
- Atualizar: `just commit-counts` lê o GitHub (só leitura, precisa do `gh`) e imprime uma linha por
  projeto, como `nix-os: commits = { human = 104; agent = 63; };`. Cole cada linha sobre o
  `commits` do projeto, ajuste `commitsAsOf` para o dia, rode `just mockups` e abra um pull
  request. Um repositório que não responde imprime `no data`, e o comando sai com 1.

## Como mudar

Edite `mockups/data.nix` (os fatos) ou `mockups/<direção>.nix` (o layout) e rode `just mockups`. O
comando escreve os SVGs em `docs/mockups/` e a cópia do wiki em `wiki/mockups/`. O
`checks.mockups` do flake falha se os testes (`lib.runTests`) falharem ou se um SVG commitado não for
a saída dos `.nix`. Nada disto entra no sistema da VPS.
