# Arquitetura

[English](Architecture)

## As peças

| Arquivo | O que faz |
|---|---|
| `flake.nix` | Um sistema por máquina, `nixosConfigurations.piabrota` e `.piabrota2` (nixos-26.05, de `hosts/<nome>/`), um nó do deploy-rs para cada uma e os `checks` do CI. |
| `configuration.nix` | O que as duas máquinas dividem: a base da Hostinger (GRUB em `/dev/sda`, cloud-init, o agente QEMU, SSH). Importa os módulos abaixo. |
| `piabrota.nix` | O usuário `h0ffmann` (só chave SSH) e os pacotes base. |
| `tools.nix` | Ferramentas de linha de comando leves e os limites de disco e memória. |
| `deploy.nix` | O usuário `deploy` que o CI usa, a coleta de lixo e o limite de gerações de boot. |
| `loco.nix` | Apps [Loco](https://loco.rs) como serviços systemd isolados, com SQLite, nginx e HTTPS. |
| `site.nix` | O site estático de `site/` (Gleam e Lustre, pré-renderizado no build; a VPS recebe só o HTML e o CSS) em www.piabrota.art, por HTTP e HTTPS; `piabrota.art` redireciona para o `www`. |
| `pgx.nix` | O [PGX](https://pgx.dev), um banco compatível com Postgres em um processo, no lugar de um servidor PostgreSQL ou do Docker, para a próxima carga que precisar de Postgres (hoje nada o usa). Só para dado que dá para refazer; o dado dos apps fica no SQLite. Veja [`docs/PGX.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/PGX.ptBR.md). |
| `hermes.nix` | O [Hermes Agent](https://github.com/NousResearch/hermes-agent), o agente da Nous Research, pelo módulo NixOS do flake dele: um serviço isolado que responde em plataformas de chat, com o Claude pela assinatura do dono; os segredos ficam na máquina. Veja [Hermes](Hermes). |
| `openrig.nix` | O [OpenRig](https://github.com/mvschwarz/openrig), um painel de controle para um time de agentes de código, na KVM 4, com a interface em rig.piabrota.art atrás de basic auth. É o motor da [fábrica de software](Fabrica): um seat builder e um seat reviewer, ambos no `omp`, que o Hermes opera. Veja [`docs/OPENRIG.md`](https://github.com/piabrota/nix-os/blob/main/docs/OPENRIG.md) (em inglês). |
| `kubesolo-purge.nix` | Um oneshot que limpa uma instalação antiga da máquina, uma vez. Uma pessoa o apaga depois. |

## Do pull request à VPS

```
PR ──► ci.yml: nixpkgs-fmt, statix, deadnix, shellcheck, justfiles (nix flake check à mão)
merge na main ──► deploy.yml: o runner builda, o deploy-rs copia via SSH e ativa
                    └─► se o SSH não responder em 60 s, a VPS volta sozinha (magic rollback)
              └─► freeze.yml: a lista de pacotes da VPS no resumo da execução
              └─► cves.yml: relatório do vulnix sobre o sistema buildado (e toda segunda)
              └─► wiki.yml: copia wiki/ para este wiki (se wiki/ mudou)
```

A VPS não compila nada: ela baixa do `cache.nixos.org` o que o cache tem. Cada deploy é uma
geração nova, e o GRUB guarda as cinco últimas.

## As figuras

![Duas máquinas: o navegador de um visitante consulta o DNS da Porkbun, cujos registros A mandam o www.piabrota.art para a VPS 1 (KVM 1), que serve o site, /hermes, /figures e o app Loco /notes, e o hermes.piabrota.art e o rig.piabrota.art para a VPS 2 (KVM 4); lá, o painel com basic auth divide o estado com o gateway hermes-agent, que comanda a unidade openrig com os dois seats omp; a interface do OpenRig, também com basic auth, faz proxy para o openrig; o gateway faz polling nas conversas do dono no Telegram e no Discord.](img/pt/two-hosts.png)

Página interativa: <https://www.piabrota.art/figures/pt-BR/two-hosts/>

<details open>
<summary>Como ler esta figura</summary>

**Em uma frase.** A KVM 1 serve a web pública e nada mais; tudo do Hermes e do OpenRig fica na KVM 4.

**Como ler.** De cima para baixo, uma faixa por lugar: visitante, DNS, cada VPS, dono. O DNS transforma cada nome numa máquina. Na KVM 4, leia a linha da esquerda para a direita: o painel divide o estado com o gateway, o gateway comanda o openrig, e a interface do OpenRig faz proxy para ele. O gateway vai até as conversas; elas não o chamam. A borda vermelha marca o que fica fora das duas máquinas.

**Fora da figura.** O deploy e os pull requests (as figuras "Como o nix-os funciona" e "A fábrica de software" mostram os dois), o PGX na KVM 4, os certificados ACME, os segredos em cada máquina e os clones em que os seats trabalham.

**Fonte.** [`docs/archify/pt/two-hosts.json`](https://github.com/piabrota/nix-os/blob/main/docs/archify/pt/two-hosts.json), a fonte da figura; `hosts/piabrota/default.nix`, `hosts/piabrota2/default.nix`, `hermes-web.nix`, `openrig.nix`, [`docs/OPENRIG.md`](https://github.com/piabrota/nix-os/blob/main/docs/OPENRIG.md), [`docs/MIGRATION-KVM4.md`](https://github.com/piabrota/nix-os/blob/main/docs/MIGRATION-KVM4.md).

</details>

![A fábrica de software: o dono manda uma tarefa ao Hermes, na VPS 2; o Hermes a manda ao seat builder do rig piabrota-dev do OpenRig, que passa o diff ao seat reviewer, e o parecer volta ao Hermes; o Hermes faz o commit, o push de um branch hermes/* e abre um pull request no GitHub; uma pessoa faz o merge, sempre; o deploy.yml então implanta as duas VPSs com o deploy-rs e o magic rollback.](img/pt/software-factory.png)

Página interativa: <https://www.piabrota.art/figures/pt-BR/software-factory/>

<details open>
<summary>Como ler esta figura</summary>

**Em uma frase.** O rig vai fazer a construção e a revisão, o Hermes encaminha e confere, e só uma pessoa faz o merge.

**Como ler.** De cima para baixo, uma faixa por etapa: pessoas, Hermes, o rig, GitHub, deploy. As setas dizem o que vem depois; a borda vermelha marca onde uma pessoa entra.

**Fora da figura.** As skills `/triage` e `/mip`, que vêm antes da tarefa, os vigias depois do deploy (`kvm4-health`), a lista de bloqueio e o token dos seats.

**Fonte.** [`docs/archify/pt/software-factory.json`](https://github.com/piabrota/nix-os/blob/main/docs/archify/pt/software-factory.json), a fonte da figura; `openrig/specs/rigs/piabrota-dev/rig.yaml`, [`docs/OPENRIG.md`](https://github.com/piabrota/nix-os/blob/main/docs/OPENRIG.md), `.github/workflows/deploy.yml`, as skills `hermes-rig` e `hermes-omp`. ⚠ Nenhuma tarefa passou pelo rig ainda: os seats, a seta do parecer e o pull request a partir do diff de um seat são o plano, não uma execução.

</details>

![Como o nix-os funciona: um pull request roda o ci.yml a cada push; o merge na main roda o deploy.yml, que builda o sistema no runner do GitHub; o deploy-rs copia o closure para a VPS via SSH e troca o sistema, e a VPS baixa os caminhos da store do cache.nixos.org; se o SSH ficar mudo por 60 s, o magic rollback volta o sistema antigo; depois da troca, o freeze.yml lista os pacotes da VPS, e o cves.yml roda o vulnix no mesmo push.](img/pt/how-nix-os-works.png)

Página interativa: <https://www.piabrota.art/figures/pt-BR/how-nix-os-works/>

<details open>
<summary>Como ler esta figura</summary>

**Em uma frase.** Ninguém faz deploy à mão: o merge de um pull request é o deploy, e uma troca que corta o SSH se desfaz sozinha.

**Como ler.** De cima para baixo, uma faixa por lugar onde o trabalho roda. As setas dizem o que passa ou o que vem depois; a borda vermelha marca onde você entra.

**Fora da figura.** Os secrets e o environment `prod`, o `wiki.yml`, os pushes só de Markdown que pulam o build, e o deploy à mão (`just deploy`).

**Fonte.** [`docs/archify/pt/how-nix-os-works.json`](https://github.com/piabrota/nix-os/blob/main/docs/archify/pt/how-nix-os-works.json), a fonte da figura; `.github/workflows/`, `flake.nix` (`deploy.nodes.piabrota`, `magicRollback`), [`docs/DEPLOY.md`](https://github.com/piabrota/nix-os/blob/main/docs/DEPLOY.md).

</details>

![piabrota.art: um navegador resolve os dois registros A da Porkbun, que apontam para a VPS; o nginx responde ao piabrota.art com um 301 para https://www e serve o www.piabrota.art por HTTP e HTTPS, com /nixos num 302 para o repositório e um certificado do Let's Encrypt por nome; a página foi buildada antes do deploy, o site/ em Gleam pré-renderizado pelo Nix na /nix/store como três páginas e style.css, que é o root do nginx.](img/pt/piabrota-art.png)

Página interativa: <https://www.piabrota.art/figures/pt-BR/piabrota-art/>

<details open>
<summary>Como ler esta figura</summary>

**Em uma frase.** A VPS serve alguns arquivos pequenos da store; o Gleam, o node e o build nunca chegam nela.

**Como ler.** De cima para baixo: o visitante, o DNS, o nginx na VPS e o que foi buildado antes do deploy. As setas dizem para onde vai um pedido, ou o que entra em quê.

**Fora da figura.** O desafio HTTP-01 do ACME, a opção `httpsOnly` e os apps Loco que dividiriam o nginx.

**Fonte.** [`docs/archify/pt/piabrota-art.json`](https://github.com/piabrota/nix-os/blob/main/docs/archify/pt/piabrota-art.json), a fonte da figura; `site.nix`, `site/default.nix`, [`docs/SITE.md`](https://github.com/piabrota/nix-os/blob/main/docs/SITE.md).

</details>

## O que não pode quebrar

O agente QEMU, o cloud-init, o SSH com a chave do `h0ffmann`, o GRUB em `/dev/sda`, o usuário
`deploy` e o magic rollback. Sem eles, a Hostinger não consegue provisionar a máquina ou o CI
não consegue fazer o deploy. A lista completa está em [`AGENTS.md`](https://github.com/piabrota/nix-os/blob/main/AGENTS.md), seção "Do not
break the machine".
