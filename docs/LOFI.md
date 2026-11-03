# lofi: a 24/7 music bot for the Marola Discord

[Português](LOFI.ptBR.md)

`lofi` is a small Discord bot that sits in one voice channel of one server and plays the music
files of one directory, shuffled, without end. It is the unit `lofi` (`lofi.nix`), built from the
Rust crate in `lofi/`. It joins when it starts, joins again when Discord drops it, shows the track
in its status ("Listening to …") and answers `/np` with the track and its credit. It reads no
messages and has no other command.

## Why a bot of our own

| Option | Why not, or why |
|---|---|
| A public music bot (invite and go) | Most play YouTube or Spotify, which their terms do not allow; Rythm and Groovy were shut down for that in 2021. Their 24/7 mode is often paid, and the music is theirs to choose |
| Lavalink with a Java bot | A JVM on a box with 1 vCPU and 4 GB (`AGENTS.md`, "Resource budget", rule 4) |
| A Python bot (discord.py) with ffmpeg | A Python runtime and ffmpeg for one job |
| **This bot** | One Rust binary, 10.8 MiB, plus libopus (0.5 MiB); about 20 MiB of RAM while it plays, capped at 128 MiB; music we chose and may play |

It uses [serenity](https://github.com/serenity-rs/serenity) 0.12 and
[songbird](https://github.com/serenity-rs/songbird) 0.6.1. Songbird 0.6 is the first release with
DAVE, Discord's end-to-end encryption, which "is since 2026 mandatory for all voice connections"
(its changelog). An older voice library cannot connect.

## Cost

| | |
|---|---|
| Closure | +11.3 MiB: `lofi` (10.8 MiB, stripped, `opt-level = "s"`, full LTO) and `libopus` (0.5 MiB). glibc and libgcc are already in the system. ⚠ `dix` on the whole system did not run here (the sandbox could not fetch the `hermes-agent` input); CI builds it |
| Memory | `MemoryMax=128M`; ⚠ the 20 MiB figure is an estimate, read it with `systemctl status lofi` |
| CPU | One Opus encode at 48 kHz stereo; `CPUWeight=50`, so sshd, nginx and the apps go first |
| Bandwidth | About 64 to 128 kbit/s out while it plays, so under 45 GB a month of the 4 TB |

## The music: what is legal to play

The bot plays only the files you copy to `/var/lib/lofi/music`. The music is never committed to
this repository. Rules:

1. **CC0 first.** [HoliznaCC0](https://freemusicarchive.org/music/holiznacc0) has dedicated his
   archive to the public domain under CC0, lofi included (for example
   [Winter Lofi](https://freemusicarchive.org/music/holiznacc0/winter-lofi) and
   [Spring at last (LOFI TAPE)](https://freemusicarchive.org/music/holiznacc0/spring-at-last-lofi-tape)).
   CC0 asks for no credit; give it anyway in `credits.tsv`.
2. **CC BY is fine with credit.** On the [Free Music Archive](https://freemusicarchive.org), filter
   by licence. A CC BY track needs its credit: artist, title, licence and link, in `credits.tsv`
   (below). `/np` shows it. Read the licence of each track on its own page, not the album's.
3. **No NC or ND without thought.** CC BY-NC is fine while the server earns nothing; a server
   with paid tiers or sponsors is not "non-commercial".
4. **Not Pixabay music.** Its licence forbids distributing a track "on a Standalone basis", in
   the same form as on the site, which is what a stream is
   ([Pixabay Content License](https://pixabay.com/service/license/)).
5. **Never YouTube, Spotify, or "lofi radio" rips.** Those tracks are under copyright and the
   services' terms forbid it.

### `credits.tsv`

A file in the music directory: the file name, one tab, the credit. Lines that start with `#` are
comments.

```
# file	credit
winter-lofi-01.mp3	HoliznaCC0 - Winter Lofi 1 (CC0 1.0) https://freemusicarchive.org/music/holiznacc0/winter-lofi
```

A track without a row is shown by its file name, so name files `Artist - Title.mp3`. The bot
reads MP3, FLAC, Ogg Vorbis, Opus and WAV. It reads the directory again at the end of each round,
so a new file plays from the next round, with no restart.

## One-time setup

1. **Make the bot.** In the [Discord Developer Portal](https://discord.com/developers/applications),
   make an application, then under "Bot" reset and copy the token. No privileged intent is needed.
2. **Invite it.** Under "OAuth2", URL generator: scopes `bot` and `applications.commands`;
   permissions `Connect` and `Speak` (in the voice channel). Open the URL and pick the Marola server.
3. **Get the IDs.** In Discord, Settings, Advanced, turn on Developer Mode. Right-click the server,
   "Copy Server ID"; right-click the voice channel, "Copy Channel ID".
4. **Write the env file on the box**, root only. With it, the path unit `lofi.path` starts the bot:

   ```console
   sudo install -m 600 /dev/null /var/lib/lofi-secrets/lofi.env
   sudo tee /var/lib/lofi-secrets/lofi.env >/dev/null <<'EOF'
   DISCORD_TOKEN=<the bot token>
   LOFI_GUILD_ID=<the server ID>
   LOFI_CHANNEL_ID=<the voice channel ID>
   EOF
   ```

   The IDs are not secret. To keep them in git instead, set `piabrota.lofi.guildId` and
   `piabrota.lofi.channelId` in `configuration.nix`; the token stays in the file.
5. **Copy the music**, from your computer: `scp *.mp3 credits.tsv piabrota.art:/var/lib/lofi/music/`.
   The directory belongs to the `lofi` group, and `h0ffmann` is in it.

## Check it

```console
systemctl status lofi
journalctl -u lofi -f        # "joined the voice channel", then "playing" for each track
```

| Exit, or log line | Meaning |
|---|---|
| exit 2, `LOFI_GUILD_ID is not set` | The env file lacks a setting. The unit does not restart on 2: fix the file, then `sudo systemctl restart lofi` |
| exit 2, `401: Unauthorized` | Wrong token: reset it in the portal and write it again |
| `cannot join the voice channel` | The bot lacks `Connect` in that channel, or the ID is wrong. It tries again, up to every 5 minutes |
| `no music to play` | The directory has no file it reads. It looks again every 60 s |

## Change or turn it off

- Volume: `piabrota.lofi.volume` (0 to 1, default 0.5) in `configuration.nix`.
- Off: `piabrota.lofi.enable = false;` in a PR. The music and the env file stay on the box.
- The crate's tests run in its Nix build (`nix build .#lofi`); `cargo clippy -- -D warnings` and
  `cargo fmt --check` in `lofi/` before a PR.
