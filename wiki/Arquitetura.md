# Arquitetura

[English](Architecture)

## As peças

| Arquivo | O que faz |
|---|---|
| `flake.nix` | O sistema `nixosConfigurations.piabrota` (nixos-26.05), o nó do deploy-rs e os `checks` do CI. |
| `configuration.nix` | A base da Hostinger: GRUB em `/dev/sda`, cloud-init, o agente QEMU, SSH. Importa os módulos abaixo. |
| `piabrota.nix` | O usuário `h0ffmann` (só chave SSH) e os pacotes base. |
| `tools.nix` | Ferramentas de linha de comando leves e os limites de disco e memória. |
| `deploy.nix` | O usuário `deploy` que o CI usa, a coleta de lixo e o limite de gerações de boot. |
| `loco.nix` | Apps [Loco](https://loco.rs) como serviços systemd isolados, com SQLite, nginx e HTTPS. |
| `site.nix` | O site estático de `site/` (Gleam e Lustre, pré-renderizado no build; a VPS recebe só o HTML e o CSS) em www.piabrota.art, por HTTP e HTTPS; `piabrota.art` redireciona para o `www`. |
| `kubesolo.nix` | O [KubeSolo](https://github.com/portainer/kubesolo), um Kubernetes de um nó só, atrás de uma flag desligada; as cargas ficam em `k8s/` e nunca entram por um deploy. Veja [`docs/KUBESOLO.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/KUBESOLO.ptBR.md). |
| `pgx.nix` | O [PGX](https://pgx.dev), um banco compatível com Postgres em um processo, no lugar de um servidor PostgreSQL ou do Docker: o store do rax no KubeSolo. Só para dado que dá para refazer; o dado dos apps fica no SQLite. Veja [`docs/PGX.ptBR.md`](https://github.com/piabrota/nix-os/blob/main/docs/PGX.ptBR.md). |

## Do pull request à VPS

```
PR ──► ci.yml: nix flake check (builda o sistema), nixpkgs-fmt, statix, deadnix, shellcheck
merge na main ──► deploy.yml: o runner builda, o deploy-rs copia via SSH e ativa
                    └─► se o SSH não responder em 60 s, a VPS volta sozinha (magic rollback)
              └─► freeze.yml: a lista de pacotes da VPS no resumo da execução
              └─► cves.yml: relatório do vulnix sobre o sistema buildado (e toda segunda)
              └─► wiki.yml: copia wiki/ para este wiki (se wiki/ mudou)
```

A VPS não compila nada: ela baixa do `cache.nixos.org` o que o cache tem. Cada deploy é uma
geração nova, e o GRUB guarda as cinco últimas.

## As figuras

![Como o nix-os funciona: um pull request roda o ci.yml a cada push; o merge na main roda o deploy.yml, que builda o sistema no runner do GitHub; o deploy-rs copia o closure para a VPS via SSH e troca o sistema, e a VPS baixa os caminhos da store do cache.nixos.org; se o SSH ficar mudo por 60 s, o magic rollback volta o sistema antigo; depois da troca, o freeze.yml lista os pacotes da VPS, e o cves.yml roda o vulnix no mesmo push.](img/pt/how-nix-os-works.png)

<details open>
<summary>Como ler esta figura</summary>

**Em uma frase.** Ninguém faz deploy à mão: o merge de um pull request é o deploy, e uma troca que corta o SSH se desfaz sozinha.

**Como ler.** De cima para baixo, uma faixa por lugar onde o trabalho roda. As setas dizem o que passa ou o que vem depois; a borda vermelha marca onde você entra.

**Fora da figura.** Os secrets e o environment `prod`, o `wiki.yml`, os pushes só de Markdown que pulam o build, e o deploy à mão (`just deploy`).

**Fonte.** [`docs/archify/pt/how-nix-os-works.json`](https://github.com/piabrota/nix-os/blob/main/docs/archify/pt/how-nix-os-works.json), a fonte da figura; `.github/workflows/`, `flake.nix` (`deploy.nodes.piabrota`, `magicRollback`), [`docs/DEPLOY.md`](https://github.com/piabrota/nix-os/blob/main/docs/DEPLOY.md).

</details>

![piabrota.art: um navegador resolve os dois registros A da Porkbun, que apontam para a VPS; o nginx responde ao piabrota.art com um 301 para https://www e serve o www.piabrota.art por HTTP e HTTPS, com /nixos num 302 para o repositório e um certificado do Let's Encrypt por nome; a página foi buildada antes do deploy, o site/ em Gleam pré-renderizado pelo Nix na /nix/store como três páginas e style.css, que é o root do nginx.](img/pt/piabrota-art.png)

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
