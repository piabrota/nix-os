# O feed pessoal

`hermes/feeds/build_feed.py` monta um feed só com as fontes do dono e dá uma nota a cada item, conforme os interesses dele.
Não usa agente nem modelo. Usa apenas a biblioteca padrão do Python.

O `hermes.nix` instala o script como `scripts/feed-build.py` e as fontes como `feeds/feeds.toml`, dentro de `HERMES_HOME`.
Um cron `no_agent` posta o que o script imprime. Este repositório não cria esse cron. Peça ao Hermes que o crie.

## Como rodar

```console
just feeds-test    # testes unitários, offline
just feeds-build   # todas as fontes, imprime o resumo, não grava nada, precisa de rede
python3 hermes/feeds/build_feed.py --config hermes/feeds/feeds.toml --out /tmp/feed --no-state
```

- `--dry-run`: imprime o resumo e não grava nada. Não lê o estado.
- `--no-state`: grava os arquivos, mas não lê nem grava o estado.
- `--opml-only`: grava só o `sources.opml`. Não usa a rede.
- `--source ID`: roda só estes ids de fonte. `--max-seconds N`: para a busca após N segundos (padrão 150).
- Padrões: `--config`, `--out` e `--state` ficam em `$HERMES_HOME/feeds/` (`HERMES_HOME` é `~/.hermes` se não estiver definido).

Sai com 0 quando uma fonte funcionou. Sai com 1 quando nenhuma funcionou ou uma gravação falhou.
Se nenhuma fonte funcionou, o `feed.atom` antigo fica e o `health.json` mostra os erros.

## Arquivos de saída

|Arquivo|O que tem|
|---|---|
|`feed.atom`|Atom 1.0. Os melhores itens recentes, do maior para o menor score. É o que se assina.|
|`digest.md`|Os mesmos itens em Markdown curto, agrupados.|
|`sources.opml`|As fontes de feed em OPML. As buscas no GitHub e o ranking não entram. Importe em qualquer leitor.|
|`health.json`|Por fonte: `ok`, `error` ou `skipped`, o texto do erro, o número de itens, a data do item mais novo.|
|stdout|O resumo dos itens novos com `score >= digest_min_score`. Fica vazio quando nada é novo.|

O `state.json` guarda os ids dos itens que o script já imprimiu. Uma entrada some após 60 dias.
O resumo no stdout termina com `Sources with errors: ...` quando uma fonte falhou. Se está vazio, não tem essa linha.

## Como ler a nota

A nota de um item é `base + interest + recency + stars`.

- `base`: o `weight` da fonte, de 1 a 5.
- `interest`: para cada interesse, `1,2 * weight` se um termo está no título, ou `0,4 * weight` se está só no resumo. A soma para em 8.
- `recency`: +2 para item com menos de 24 horas. Cai em linha reta até 0 no `max_age_days` da fonte.
- `stars`: só para busca no GitHub, `min(3, log10(stars + 1) / 1,5)`.

Um termo de `[negative]` no título ou no resumo descarta o item.
`requires_match = true` mantém só os itens que casam com algum interesse.
Uma fonte `pinned` sempre mantém seus itens mais novos. Item sem data não ganha bônus de recência.
O `feed.atom` mantém itens com `score >= min_score`. Os limites ficam em `[output]`.

## Os interesses

|Origem|Temas|
|---|---|
|`chat`|Hermes Agent; Coding agents and Claude; Nix and NixOS; Agent skills, plugins and MCP; Building in public; Self-hosting and VPS; Chat bots; CI and code quality; Technical writing; Second brain|
|`profile`|Wave models; GPU and HPC; Rust; Gleam and BEAM; Scala and effects; Open-water swimming; Water quality; Floods and warnings; Postgres; ML engineering|

`chat` quer dizer que o dono perguntou ao Hermes sobre o tema. `profile` quer dizer que o tema está no perfil público em `hermes/AGENTS.md`.

## Fontes que não entram

- Boletins oficiais (CEMADEN, Defesa Civil, INMET, FEPAM, IMA, IAT). O job de balneabilidade e enchentes lê esses boletins a cada 3 horas.
- Atividade no GitHub em `piabrota/*`, `marola-dev/*` e `h0ffmann/*`. O resumo noturno do GitHub já cobre.
- Fonte que não respondeu em 2026-11-04. O `feeds.toml` a omite. Teste uma URL nova antes de incluí-la.

## Como incluir uma fonte

1. Abra a URL e confira que ela responde com um feed.
2. Inclua uma tabela `[[source]]` em `hermes/feeds/feeds.toml`, no bloco do grupo dela.
3. Defina `id` (único), `group` (um `id` de `[[group]]`), `kind`, `weight` (1 a 5) e `limit`.
4. Fonte `feed` e fonte `apple_chart` precisam de `url`. Fonte `github_search` precisa de `query`. A busca aceita `{d7}`, `{d14}` e `{d30}`.
5. Chaves opcionais: `max_age_days`, `pinned`, `pinned_keep`, `requires_match` e `genres` (para o ranking).
6. Rode `just feeds-test`. Um teste confere se o `feeds.toml` está completo.

Para incluir um interesse, crie uma tabela `[[interest]]` com `name`, `origin` (`chat` ou `profile`), `weight` e `terms`. Inclua a linha dele na tabela acima.
Um feed de podcast pode ter 5 MB. O script lê só o primeiro 1,5 MB, então um feed longo não é problema.
