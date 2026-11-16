# tyler-durden-bot

[English](TYLER-DURDEN.md)

O tyler-durden-bot resume cada pull request grande aberto no `h0ffmann/proof` em um comentário: um
TLDR, um ELI5, um resumo e um risco de muito baixo a crítico, com a sua confiança. Ele é a GitHub App
**tyler-durden-bot**, da conta h0ffmann. Não é um serviço novo: é uma rota de webhook do Hermes
(`hermes.nix`) no piabrota2, com um perfil próprio do Hermes, `tyler-durden`, cujo token do GitHub é
o da App. Assim o comentário aparece como `tyler-durden-bot[bot]`, nunca como piabrota-hermes.

O `tyler-durden-bot.nix` o declara, **desligado** (`piabrota.tylerDurden.enable = false` em
`hosts/piabrota2`). Desligado, o sistema é o mesmo que sem o módulo.

## Como um pull request vira um comentário

1. O GitHub manda o evento `pull_request`, assinado com o secret de webhook da App, para
   `https://tyler.piabrota.art/p/tyler-durden/webhooks/tyler-durden`. O nginx passa só esse caminho,
   só POST, para a porta de webhook do Hermes em 127.0.0.1 (8644); o resto é 404.
2. O Hermes confere a assinatura (`WEBHOOK_SECRET`), fica só com `action: opened` e roda o script da
   rota, `tyler-durden-bot.py`.
3. O script lê os arquivos do pull request com o token da App e conta as linhas alteradas como
   código, comentário ou markdown, no total e por linguagem (pela extensão). Abaixo de todos os
   thresholds da config ele imprime `[SILENT]`, e nenhum modelo roda.
4. Senão, o agente do perfil `tyler-durden` escreve o comentário com a skill `tyler-durden-bot`, sem
   terminal, arquivos ou web (`toolsets = [ "clarify" ]`), e o Hermes o publica com `gh pr comment`
   e o `GH_TOKEN` do perfil.

Um push, um reopen ou um draft que fica pronto não roda de novo.

## Onde fica cada coisa

| O quê | Onde |
|---|---|
| O script, a skill, a config (watchlist, `[trigger]`, `[sections]`, `[quality]`) e o manifesto da App | piabrota/agents, `tyler-durden-bot/` e `apps/tyler-durden-bot.json`, fixado por commit no `tyler-durden-bot.nix` (`agents`) |
| A rota, o `config.yaml` e o `SOUL.md` do perfil, o vhost, a unidade do token | `tyler-durden-bot.nix` |
| O ID e a chave da App | `/var/lib/tyler-durden-secrets/app.env` no servidor, só root |
| O secret do webhook | `WEBHOOK_SECRET` em `/var/lib/hermes-secrets/hermes.env` no servidor |
| O token (uma hora, só `h0ffmann/proof`, Pull requests write) | `/run/tyler-durden-bot/token` e o `.env` do perfil, escritos pela `tyler-durden-token` a cada 45 minutos |

Mudar um threshold, uma seção ou o orçamento é um pull request no piabrota/agents, e depois um aqui
que move o pin.

## Ligar

O dono, uma vez:

1. Criar a App na conta h0ffmann (Settings, Developer settings, GitHub Apps) a partir do
   `apps/tyler-durden-bot.json` do piabrota/agents: Pull requests read and write, Metadata read, o
   evento Pull request, a URL de webhook acima e um secret de webhook (`openssl rand -hex 32`).
   Instalar só no `h0ffmann/proof`.
2. Apontar o registro A de `tyler.piabrota.art` para o piabrota2 (docs/SITE.md, "DNS on Porkbun").
3. No servidor, como root:

   ```sh
   install -d -m 0700 /var/lib/tyler-durden-secrets
   printf 'GH_APP_ID=%s\nGH_APP_PRIVATE_KEY_B64=%s\n' <app-id> "$(base64 -w0 tyler-durden-bot.*.pem)" \
     > /var/lib/tyler-durden-secrets/app.env
   chmod 0600 /var/lib/tyler-durden-secrets/app.env
   echo 'WEBHOOK_SECRET=<o secret do webhook>' >> /var/lib/hermes-secrets/hermes.env
   ```

4. Um pull request aqui com `piabrota.tylerDurden.enable = true` em `hosts/piabrota2`. O merge faz o
   deploy.

## Conferir

- `systemctl status tyler-durden-token` diz "token for one hour"; `journalctl -u hermes-agent | grep webhook`
  mostra a rota e cada evento.
- Nas configurações da App, Advanced, Recent Deliveries: um 200 com `ignored` é um evento filtrado
  (não é opened, ou abaixo dos thresholds); um 202 iniciou o agente.
- Abrir um pull request de teste com mais de 1000 linhas no `h0ffmann/proof`.

## Pilhas de pull requests

Uma pilha são vários pull requests, cada um baseado na branch do que está embaixo, abertos ou
atualizados com push em poucos segundos. O bot trata assim:

- O script conta os arquivos de um pull request (`GET /pulls/N/files`). Essa lista é o diff do pull
  request contra a sua própria branch base. Um pull request da pilha é contado só pelas suas
  próprias mudanças.
- O filtro da rota olha `action: opened` e não olha a branch base. Todo pull request que abre em um
  repositório vigiado é considerado, em pilha ou não.

Duas opções evitam que uma pilha grande perca um pull request:

| Opção | Padrão | Por quê |
|---|---|---|
| `piabrota.tylerDurden.rateLimit` | 300 | O Hermes conta toda entrega da rota contra esse limite (30 por minuto, por padrão) antes de aplicar o filtro. Os eventos `synchronize`, `edited` e `labeled`, que o filtro ignora, também contam. Um restack de 40 branches manda 40 eventos `synchronize` de uma vez. Acima do limite o Hermes responde 429, e o GitHub não manda essa entrega de novo sozinho: o pull request fica sem comentário. |
| `piabrota.tylerDurden.scriptTimeoutSeconds` | 120 | O script lista os arquivos de 100 em 100, até 30 páginas, uma depois da outra. Um pull request muito grande pode precisar de mais que os 30 segundos que o Hermes dá por padrão. Num timeout o Hermes descarta o evento. |

Para ver uma entrega perdida: configurações da App no GitHub, Advanced, Recent Deliveries. Um 429 ou
um timeout aparece ali. Redeliver manda de novo com o mesmo id. O Hermes aceita, porque recusou a
primeira tentativa antes de guardar o id.

### Não coberto

- O prompt não diz a branch base nem o lugar do pull request na pilha. O script da rota monta o
  payload, e ele fica no piabrota/agents (PR 6). Isso pede uma mudança lá.
- Nada limita nem mede quantas execuções do agente rodam ao mesmo tempo.
- O GitHub corta uma entrega que demora mais de 10 segundos para responder. O trabalho pode
  continuar. Não verificado.
- Não testado: nada disso foi rodado em uma pilha de verdade.

## Desligar

`piabrota.tylerDurden.enable = false`, ou desinstalar a App do `h0ffmann/proof`.

## Não verificado

Escrito a partir da documentação e do código do Hermes v0.23.0, ainda não rodado no servidor:

- que o script da rota é encontrado no `scripts/` do perfil (ele está instalado nas duas homes);
- que o Hermes lê de novo o `.env` do perfil depois que a unidade do token o reescreve, a cada 45
  minutos; se não ler, o `GH_TOKEN` expira em uma hora e o `gh` cai no login guardado dele, que é o
  piabrota-hermes: confira o autor dos primeiros comentários;
- que o `WEBHOOK_SECRET` global do arquivo de ambiente chega a uma rota que não define secret.
