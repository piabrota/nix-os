# The personal feed

`hermes/feeds/build_feed.py` builds one feed from the owner's sources. It scores each item on his interests.
It uses no agent and no model. It uses only the standard library of Python 3.11 or later (`tomllib`).

`hermes.nix` installs the script as `scripts/feed-build.py` and the sources as `feeds/feeds.toml`, in `HERMES_HOME`.
A `no_agent` cron job posts what the script prints. This repository does not create that job. Ask Hermes to create it.

## Run it

```console
just feeds-test    # unit tests, offline
just feeds-build   # all sources, prints the digest, writes nothing, needs the network
python3 hermes/feeds/build_feed.py --config hermes/feeds/feeds.toml --out /tmp/feed --no-state
```

- `--dry-run`: print the digest, write nothing. It does not read the state.
- `--no-state`: write the files, but do not read or write the state.
- `--opml-only`: write `sources.opml` and stop. It asks no network.
- `--source ID`: run only these source ids. `--max-seconds N`: stop the fetch after N seconds (default 150).
- Defaults: `--config` is `$HERMES_HOME/feeds/feeds.toml`, `--out` is `$HERMES_HOME/feeds/out/` and `--state` is `$HERMES_HOME/feeds/state.json` (`HERMES_HOME` is `~/.hermes` if unset).

Exit 0 when one source worked. Exit 1 when no source worked or a write failed.
When no source worked, the old `feed.atom` stays and `health.json` shows the errors.

## Output files

|File|What it holds|
|---|---|
|`feed.atom`|Atom 1.0. The best recent items, best score first. Subscribe to it.|
|`digest.md`|The same items as short Markdown, grouped.|
|`sources.opml`|The feed sources as OPML. GitHub searches and the chart are not in it. Import it into any reader.|
|`health.json`|For each source: `ok`, `error` or `skipped`, the error text, the item count, the newest item date.|
|stdout|The digest of the items that are new and have `score >= digest_min_score`. It is empty when nothing is new.|

`state.json` holds the ids of the items the script already printed. It drops an entry after 60 days.
The stdout digest ends with `Sources with errors: ...` when a source failed. It has no such line when it is empty.

## Read the score

An item scores `base + interest + recency + stars`.

- `base`: the `weight` of the source, 1 to 5.
- `interest`: for each interest, `1.2 * weight` when a term is in the title, or `0.4 * weight` when it is only in the summary. The sum stops at 8.
- `recency`: +2 for an item under 24 hours old. It falls in a straight line to 0 at the `max_age_days` of the source.
- `stars`: for a GitHub search only, `min(3, log10(stars + 1) / 1.5)`.

A term of `[negative]` in the title or summary drops the item.
`requires_match = true` keeps only items that match an interest.
A `pinned` source always keeps its newest items. An item without a date gets no recency bonus.
`feed.atom` keeps items with `score >= min_score`. The thresholds are in `[output]`.
A GitHub item has the date of its last push (`pushed_at`), or of its creation if there is no push. `feed.atom` gives each group `max_per_group` places first; the best of the rest fill the room. The digest shows at most `digest_per_group` items of a group.
A source key `exclude_terms = ["canary"]` drops an item with a term in its title, as a whole word. A source key `pinned_keep` replaces the `[output]` value for that source.

## The interests

|Origin|Topics|
|---|---|
|`chat`|Hermes Agent; Coding agents and Claude; Nix and NixOS; Agent skills, plugins and MCP; Building in public; Self-hosting and VPS; Chat bots; CI and code quality; Technical writing; Second brain|
|`profile`|Wave models; GPU and HPC; Rust; Gleam and BEAM; Scala and effects; Open-water swimming; Water quality; Floods and warnings; Postgres; ML engineering|

`chat` means the owner asked Hermes about the topic. `profile` means the topic is in the public profile in `hermes/AGENTS.md`.

## Sources that are not included

- Official bulletins (CEMADEN, Defesa Civil, INMET, FEPAM, IMA, IAT). The bathing water and flood watch job reads them every 3 hours.
- GitHub activity on `piabrota/*`, `marola-dev/*` and `h0ffmann/*`. The overnight GitHub digest covers it.
- A source that did not answer on 2026-11-04. `feeds.toml` omits it. Test a new URL before you add it.

## Add a source

1. Open the URL and check that it answers with a feed.
2. Add a `[[source]]` table to `hermes/feeds/feeds.toml`. Put it in the block of its group.
3. Set `id` (unique), `group` (an `id` of a `[[group]]`), `kind`, `weight` (1 to 5) and `limit`.
4. A `feed` source and an `apple_chart` source need `url`. A `github_search` source needs `query`. A query can use `{d7}`, `{d14}` and `{d30}`.
5. Optional keys: `max_age_days`, `pinned`, `pinned_keep`, `requires_match`, and `genres` for a chart.
6. Run `just feeds-test`. One test checks that `feeds.toml` is complete.

To add an interest, add an `[[interest]]` table with `name`, `origin` (`chat` or `profile`), `weight` and `terms`. Add its row to the table above.
A podcast feed can be 5 MB. The script reads only the first 1.5 MB, so a long feed is fine.
