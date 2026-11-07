# piabrota-dot

O piabrota-dot é um bot, sem modelo, que olha uma vez por dia se saiu uma versão nova do Hermes Agent
ou do OpenRig e abre um pull request no piabrota/nix-os. Ele é um GitHub App próprio
(`piabrota-dot[bot]`). Tudo vem do `piabrota-dot.nix`; o código está em `piabrota-dot/`.

## O que é e o que nunca faz

- Roda como script (`piabrota-dot/run.sh`: git, gh, jq e nix). Não chama modelo e não usa rede além do
  GitHub e dos downloads do `nix`.
- Abre, ou atualiza, **um** pull request por componente, na branch fixa `piabrota-dot/hermes` ou
  `piabrota-dot/openrig`. Só muda os arquivos do pin: `flake.nix`, `flake.lock` e `hermes.nix` (Hermes);
  `openrig/package.nix` (OpenRig). Se o diff tocar outro arquivo, ele não abre o pull request e abre uma
  issue.
- Se uma versão nova não avalia (`nix eval`), ele abre **uma** issue para ela e nenhum pull request.
- Só mexe nos pull requests e nas issues que ele mesmo abriu.
- **Nunca** muda o ruleset, nunca empurra para o `main`, nunca usa `workflows` nem `administration`. O
  token dele alcança só o `piabrota/nix-os`.
- O merge vem **desligado**. Veja "A chave do merge".
- Não faz o build e não sobe nada: isso é do `deploy.yml`, no merge.

## Um dia às 14:00

1. O timer `piabrota-dot.timer` dispara às 14:00 de `America/Sao_Paulo`.
2. A unidade `piabrota-dot-token` (root) gera um token novo de uma hora, só para o `piabrota/nix-os`.
3. A unidade `piabrota-dot` (usuário `piabrota-dot`) atualiza o clone em `/var/lib/piabrota-dot/nix-os`.
4. Para `hermes` e depois `openrig`, roda `scripts/<componente>-bump.sh --check` do clone. Saída 0: está em
   dia. Saída 10: há versão nova. Outra saída: falha.
5. Com versão nova: roda o script de bump, confere a lista de arquivos, avalia o `piabrota` e o
   `piabrota2` (só avaliação, sem build), faz o commit, empurra a branch e abre ou atualiza o pull
   request, com o rótulo `piabrota-dot`.
6. Escreve `/var/lib/piabrota-dot/last-run.txt`. A primeira linha é `piabrota-dot: nothing new` quando
   nada mudou.
7. Às 14:15 um job do cron do Hermes (sem agente) entrega esse arquivo no Discord, uma vez, quando ele
   mudou. Um dia sem novidade não manda mensagem.

Uma segunda rodada no mesmo dia, sem novidade, não muda nada e não imprime nada. A unidade tem
`MemoryMax=3G`: cada avaliação chega a cerca de 0,95 GB de memória residente (medido nesta caixa),
uma depois da outra.

## Por que dois estágios

O Hermes é um agente e **nunca** faz merge. O piabrota-dot pode fazer merge (se o dono ligar). Se o
token do bot ficasse ao alcance do Hermes, o Hermes passaria a poder fazer merge. Por isso:

- A chave do App fica em `/var/lib/piabrota-secrets/piabrota-dot.env`, só do root.
- A unidade `piabrota-dot-token` (root) lê a chave e escreve o token em `/run/piabrota-dot/token`
  (modo 0400, dono `piabrota-dot`). A pasta é `root:piabrota-dot` 0750.
- O usuário `piabrota-dot` não tem shell, não tem `sudo` e não está no grupo `hermes`. O usuário `hermes`
  não está no grupo `piabrota-dot`. Ele não lê o token nem a chave.
- O job do cron do Hermes, que roda como `hermes`, só **lê** o `last-run.txt`, que é público e não tem
  segredo. A pasta de estado tem modo 0751 (e não 0750): o Hermes entra nela e lê esse arquivo pelo nome,
  mas não lista a pasta. O resto fica em subpastas 0700.

## Criar o GitHub App

Uma vez, no navegador:

1. GitHub, **Settings**, **Developer settings**, **GitHub Apps**, **New GitHub App**. (Para a
   organização: github.com/organizations/piabrota/settings/apps.)
2. Nome `piabrota-dot`. Homepage: `https://piabrota.art`. **Webhook** desligado.
3. Em **Repository permissions**: **Contents** read and write, **Pull requests** read and write,
   **Issues** read and write, **Metadata** read. Nada mais (sem Workflows, sem Administration).
4. **Where can this GitHub App be installed**: só nesta conta.
5. **Create GitHub App**. Anote o **App ID**.
6. Na página do App, **Generate a private key**. Um `.pem` é baixado.
7. **Install App**: instale só no `piabrota/nix-os` (**Only select repositories**).

## Pôr a chave na caixa

O formato é o do `hermes-github.nix`: as linhas `GH_APP_ID` e `GH_APP_PRIVATE_KEY_B64`. Os nomes são os
mesmos para você repetir um passo que já conhece.

```console
base64 < piabrota-dot.*.private-key.pem | tr -d '\n'     # no seu computador: copie a saída
ssh h0ffmann@hermes.piabrota.art
sudo install -d -m 700 /var/lib/piabrota-secrets
sudo install -m 600 /dev/stdin /var/lib/piabrota-secrets/piabrota-dot.env    # cole e termine com Ctrl-D
GH_APP_ID=<o App ID>
GH_APP_PRIVATE_KEY_B64=<a linha em base64>
```

Os comandos não imprimem a chave. Apague o `.pem` do seu computador quando funcionar: dá para gerar
outro quando quiser.

## Testar à mão

```console
sudo systemctl start piabrota-dot-token
journalctl -u piabrota-dot-token -n 5     # "piabrota/nix-os: token for one hour"
sudo -u piabrota-dot piabrota-dot --dry-run
```

O `--dry-run` roda todos os passos (clone, bump, `nix eval`) e **imprime** cada escrita no GitHub, sem
fazê-la. Ele também não escreve o `last-run.txt`. Rodado à mão ele não usa a sandbox da unidade e escreve
no terminal, não no journal. Para uma rodada de verdade, igual à das 14:00:

```console
sudo systemctl start piabrota-dot
journalctl -u piabrota-dot -n 40
cat /var/lib/piabrota-dot/last-run.txt
```

Uma rodada de verdade abre pull requests de verdade.

## A entrega às 14:15

Só depois do merge, uma vez, como `hermes` (o dono cria o job; o código não cria):

```console
sudo -u hermes hermes cron create "15 14 * * *" --name piabrota-dot-report \
  --no-agent --script piabrota-dot-report.sh --deliver discord:<ID do canal>
sudo -u hermes hermes cron list
sudo -u hermes hermes cron run <id>      # uma rodada: não imprime nada se nada mudou
```

Use o mesmo destino do job `skills-export` (veja `hermes cron list`). O fuso `America/Sao_Paulo` vem do
`settings.timezone` do Hermes. O script (`hermes/scripts/piabrota-dot-report.sh`, instalado por
`hermesHomeFiles`) guarda o que já entregou em `$HERMES_HOME/piabrota-dot-delivered`. A linha `time:`
não conta na comparação. Uma falha (`piabrota-dot failed: ...`) é entregue uma vez.

## A chave do merge

`piabrota.dot.merge.hermes` e `piabrota.dot.merge.openrig`. As duas são `false`. **Ligar uma delas é uma
decisão do dono.**

- Um merge no `main` é um deploy.
- Merge do **OpenRig**: o daemon roda migrações novas do banco no primeiro start. Elas só andam para
  frente. Antes, faça `rig snapshot` e uma cópia do banco do daemon. O merge reinicia a unidade
  `openrig` e encerra todos os seats vivos.
- Merge do **Hermes**: reinicia `hermes-agent` e `hermes-backend` e encerra as rodadas do próprio agente.

Com a chave ligada, o bot faz o merge do **seu próprio** pull request daquele componente só se **tudo**
valer: o autor é `piabrota-dot[bot]`; não é rascunho; o head é o commit que o bot empurrou; o diff toca só
os arquivos do pin; todo check run e todo status do head terminou e está verde (lista vazia **não** é
verde; um check pendente espera o dia seguinte). O merge é `squash`, pela API, **uma** vez. Se o ruleset
recusar, o bot não tenta de novo, não procura outro caminho e escreve `merge refused by the ruleset` no
`last-run.txt`.

**O ruleset é a barreira de verdade.** Quem o define é o dono, no GitHub. Este código não o contorna e não
deve contorná-lo. O App não tem permissão para mudar o ruleset. Sem as checagens obrigatórias no ruleset,
o único freio do merge é o portão do próprio bot.

## Parar

- Apague a chave: `sudo rm /var/lib/piabrota-secrets/piabrota-dot.env`. As duas unidades passam a não
  fazer nada, sem falhar. O último token vale no máximo mais uma hora.
- Ou ponha `piabrota.dot.enable = false` em `hosts/piabrota2/default.nix` e faça o deploy.
- Remova o job do cron: `sudo -u hermes hermes cron remove <id>`.
- Para parar só o merge: `merge.hermes = false` e `merge.openrig = false`.

## O que ele confere e o que não confere

Confere: que o script de bump muda só os arquivos do pin; que o `piabrota` e o `piabrota2` avaliam
(`nix eval ...toplevel.drvPath`); que os checks do GitHub estão verdes (só para o merge).

Não confere: o build (o `deploy.yml` faz, no merge); um start de verdade do Hermes ou do OpenRig; as
migrações do OpenRig; o comportamento do ruleset.

## Arquivos

| Arquivo | O que é |
|---|---|
| `piabrota-dot.nix` | As opções `piabrota.dot.*`, o usuário, as duas unidades e os dois timers. |
| `piabrota-dot/run.sh` | O passo diário. |
| `piabrota-dot/mint-token.sh` | Gera o token de uma hora (root). |
| `piabrota-dot/git-credential.sh` | Entrega o token ao git sem pô-lo em URL. |
| `piabrota-dot/test/run.sh` | Testes offline: `sh piabrota-dot/test/run.sh`. |
| `hermes/scripts/piabrota-dot-report.sh` | A entrega das 14:15. |
