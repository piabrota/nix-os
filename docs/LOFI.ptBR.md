# lofi: um bot de música 24/7 para o Discord da Marola

[English](LOFI.md)

O `lofi` é um bot pequeno de Discord. Ele fica num canal de voz de um servidor e toca os arquivos
de música de um diretório, embaralhados, sem fim. Ele é a unit `lofi` (`lofi.nix`), construída a
partir do crate Rust em `lofi/`. O bot entra no canal quando inicia e entra de novo quando o
Discord o derruba. O status dele mostra a faixa ("Ouvindo …"), e o comando `/np` responde com a
faixa e o crédito dela. O bot não lê mensagens e não tem outro comando.

## Por que um bot nosso

| Opção | Por que não, ou por que sim |
|---|---|
| Um bot de música público (convidar e usar) | A maioria toca YouTube ou Spotify, e os termos desses serviços não permitem isso; o Rythm e o Groovy foram fechados por isso em 2021. O modo 24/7 deles costuma ser pago, e quem escolhe a música são eles |
| Lavalink com um bot em Java | Uma JVM numa máquina de 1 vCPU e 4 GB (`AGENTS.md`, "Resource budget", regra 4) |
| Um bot em Python (discord.py) com ffmpeg | Um runtime Python e o ffmpeg para um trabalho só |
| **Este bot** | Um binário Rust de 10,8 MiB, mais a libopus (0,5 MiB); cerca de 20 MiB de RAM enquanto toca, com teto de 128 MiB; música escolhida por nós e que podemos tocar |

O bot usa o [serenity](https://github.com/serenity-rs/serenity) 0.12 e o
[songbird](https://github.com/serenity-rs/songbird) 0.6.1. O songbird 0.6 é a primeira versão com
DAVE, a criptografia de ponta a ponta do Discord, que "is since 2026 mandatory for all voice
connections" (o changelog dele). Uma biblioteca de voz mais antiga não conecta.

## Custo

| | |
|---|---|
| Closure | +11,3 MiB: o `lofi` (10,8 MiB, sem símbolos, `opt-level = "s"`, LTO completo) e a `libopus` (0,5 MiB). A glibc e a libgcc já estão no sistema. ⚠ O `dix` do sistema inteiro não rodou aqui (o sandbox não conseguiu baixar o input `hermes-agent`); o CI constrói o sistema |
| Memória | `MemoryMax=128M`; ⚠ os 20 MiB são uma estimativa, confira com `systemctl status lofi` |
| CPU | Um encode Opus a 48 kHz estéreo; `CPUWeight=50`, então o sshd, o nginx e os apps vêm antes |
| Banda | Cerca de 64 a 128 kbit/s de saída enquanto toca, ou seja, menos de 45 GB por mês dos 4 TB |

## A música: o que é legal tocar

O bot toca só os arquivos que você copia para `/var/lib/lofi/music`. A música nunca entra neste
repositório. As regras:

1. **CC0 primeiro.** O [HoliznaCC0](https://freemusicarchive.org/music/holiznacc0) dedicou o
   acervo dele ao domínio público com CC0, lofi incluído (por exemplo
   [Winter Lofi](https://freemusicarchive.org/music/holiznacc0/winter-lofi) e
   [Spring at last (LOFI TAPE)](https://freemusicarchive.org/music/holiznacc0/spring-at-last-lofi-tape)).
   A CC0 não pede crédito; dê o crédito mesmo assim no `credits.tsv`.
2. **CC BY serve, com crédito.** No [Free Music Archive](https://freemusicarchive.org), filtre pela
   licença. Uma faixa CC BY precisa do crédito: artista, título, licença e link, no `credits.tsv`
   (abaixo). O `/np` mostra o crédito. Leia a licença de cada faixa na página dela, não na do álbum.
3. **NC ou ND só com cuidado.** A CC BY-NC serve enquanto o servidor não ganha nada; um servidor
   com planos pagos ou patrocínio não é "não comercial".
4. **Música do Pixabay, não.** A licença dele proíbe distribuir uma faixa "on a Standalone basis",
   na mesma forma do site, e é isso que um stream faz
   ([Pixabay Content License](https://pixabay.com/service/license/)).
5. **Nunca faixas tiradas do YouTube, do Spotify ou de "rádios lofi".** Essas faixas têm direitos
   autorais, e os termos dos serviços proíbem isso.

### `credits.tsv`

Um arquivo no diretório de música: o nome do arquivo, um tab, o crédito. As linhas que começam
com `#` são comentários.

```
# file	credit
winter-lofi-01.mp3	HoliznaCC0 - Winter Lofi 1 (CC0 1.0) https://freemusicarchive.org/music/holiznacc0/winter-lofi
```

Uma faixa sem linha aparece pelo nome do arquivo, então nomeie os arquivos `Artista - Título.mp3`.
O bot lê MP3, FLAC, Ogg Vorbis, Opus e WAV. Ele lê o diretório de novo no fim de cada rodada, então
um arquivo novo toca a partir da rodada seguinte, sem reiniciar.

## Configuração, uma vez só

1. **Crie o bot.** No [Discord Developer Portal](https://discord.com/developers/applications), crie
   uma aplicação. Em "Bot", gere o token e copie. O bot não precisa de intent privilegiado.
2. **Convide o bot.** Em "OAuth2", gerador de URL: escopos `bot` e `applications.commands`;
   permissões `Connect` e `Speak` (no canal de voz). Abra a URL e escolha o servidor da Marola.
3. **Pegue os IDs.** No Discord, em Configurações, Avançado, ligue o Modo Desenvolvedor. Clique com
   o botão direito no servidor, "Copiar ID do servidor"; no canal de voz, "Copiar ID do canal".
4. **Escreva o arquivo de ambiente na máquina**, só para o root. Com ele, a path unit `lofi.path`
   inicia o bot:

   ```console
   sudo install -m 600 /dev/null /var/lib/lofi-secrets/lofi.env
   sudo tee /var/lib/lofi-secrets/lofi.env >/dev/null <<'EOF'
   DISCORD_TOKEN=<o token do bot>
   LOFI_GUILD_ID=<o ID do servidor>
   LOFI_CHANNEL_ID=<o ID do canal de voz>
   EOF
   ```

   Os IDs não são segredo. Para guardar os IDs no git, defina `piabrota.lofi.guildId` e
   `piabrota.lofi.channelId` no `configuration.nix`; o token continua no arquivo.
5. **Copie a música**, do seu computador: `scp *.mp3 credits.tsv piabrota.art:/var/lib/lofi/music/`.
   O diretório é do grupo `lofi`, e o `h0ffmann` está nesse grupo.

## Conferir

```console
systemctl status lofi
journalctl -u lofi -f        # "joined the voice channel", depois "playing" a cada faixa
```

| Saída, ou linha do log | Significado |
|---|---|
| saída 2, `LOFI_GUILD_ID is not set` | Falta uma configuração no arquivo de ambiente. A unit não reinicia com 2: corrija o arquivo e rode `sudo systemctl restart lofi` |
| saída 2, `401: Unauthorized` | Token errado: gere outro no portal e escreva de novo |
| `cannot join the voice channel` | O bot não tem `Connect` nesse canal, ou o ID está errado. Ele tenta de novo, no máximo a cada 5 minutos |
| `no music to play` | O diretório não tem arquivo que o bot lê. Ele procura de novo a cada 60 s |

## Mudar ou desligar

- Volume: `piabrota.lofi.volume` (de 0 a 1, padrão 0,5) no `configuration.nix`.
- Desligar: `piabrota.lofi.enable = false;` num PR. A música e o arquivo de ambiente ficam na máquina.
- Os testes do crate rodam no build Nix dele (`nix build .#lofi`); rode `cargo clippy -- -D warnings`
  e `cargo fmt --check` em `lofi/` antes de um PR.
