# notes

A sample [Loco](https://loco.rs) app for piabrota.art: CRUD for notes on SQLite, under
<https://www.piabrota.art/notes>, behind one password. It is built by `default.nix` in this folder
and declared in `../../apps.nix`; `../../docs/LOCO.md` ("The notes demo") says how it was made, how
to set its password on the box, and how its database grows or moves.

| Path | Is |
|---|---|
| `src/controllers/notes.rs` | the pages and the password wall (`NOTES_PASSWORD`, `NOTES_SECRET`) |
| `assets/views/notes/` | the Tera views, in piabrota.art's stylesheet (`/style.css`) |
| `src/models/notes.rs`, `migration/` | the `notes` table and its SeaORM migration |
| `config/production.yaml` | read from the environment that `loco.nix` sets |

Run it locally (needs Rust 1.94 or newer):

```console
cargo loco start          # development, on http://localhost:5150/notes
NOTES_PASSWORD=dev cargo loco start
cargo test --lib          # the controller's unit tests
```

Of what `loco new` generates, only what the notes need is kept: no accounts, mailer, workers,
tasks, JSON API or i18n.
