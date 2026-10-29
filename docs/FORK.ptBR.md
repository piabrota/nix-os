# Use o nix-os na sua VPS

[English](FORK.md)

O nix-os roda uma VPS da Hostinger com NixOS e faz o deploy a partir do GitHub. Você pode fazer
um fork e rodar a sua VPS do mesmo jeito. Esta página lista cada mudança e cada passo manual. Os
passos que só você pode fazer (na Hostinger, no GitHub ou na sua máquina) estão marcados como
**manual**.

A configuração, o sistema e o nó de deploy se chamam `piabrota`. Esse nome é só um rótulo, e
você pode mantê-lo. Para trocar o nome, troque-o em `flake.nix`, `.github/workflows/deploy.yml`
e `justfile` no mesmo commit.

## 1. Faça o fork e crie a VPS

1. **Manual, GitHub.** Faça o fork de `piabrota/nix-os`. No fork, abra a aba **Actions** e
   ative os workflows. O GitHub desativa os workflows num fork novo.
2. **Manual, Hostinger.** Crie uma VPS KVM e instale o template NixOS pelo hPanel
   (**VPS > OS & Panel > Operating System**). O `configuration.nix` foi escrito para esse
   template: GRUB em BIOS no `/dev/sda`, cloud-init e o QEMU guest agent. ⚠ O caminho do menu é
   o do hPanel em 2026-10-29. A Hostinger pode mudar esse caminho. A piabrota roda no plano
   **KVM 1** (1 núcleo de vCPU, 4 GB de RAM, 50 GB de disco, 4 TB de banda por mês); a
   configuração foi feita para ele.
3. **Manual, Hostinger.** Tire um snapshot da VPS nova (**Snapshots & Backups**). Com o snapshot,
   você pode voltar a um sistema limpo.

## 2. Adapte o repositório

Edite estes arquivos no seu fork:

| Arquivo | Mudança |
|---|---|
| `piabrota.nix` | Troque o usuário `h0ffmann` pelo seu usuário. Ponha a sua chave pública SSH em `openssh.authorizedKeys.keys`. Troque também o usuário em `nix.settings.trusted-users`. |
| `.github/workflows/deploy.yml` | Em `ssh_user`, na linha `options: [deploy, h0ffmann]`, troque `h0ffmann` pelo seu usuário. |
| `justfile` | Em `remote-specs` e `remote-freeze`, troque `h0ffmann` pelo seu usuário. |
| `flake.nix` | Em `deploy.nodes.piabrota.hostname`, ponha o seu domínio ou IP. O CI usa o secret `DEPLOY_HOST`, então esse valor só vale como padrão para o `just deploy`. |
| `.github/FUNDING.yml` | Apague o arquivo ou ponha a sua conta. |
| `README.md`, `docs/drawings/` | O desenho e o texto descrevem este repositório. Mude ou mantenha, com os créditos. |

Não remova as configurações que o `AGENTS.md` lista em "Do not break the machine". A Hostinger
provisiona a VPS por meio delas.

## 3. A chave de deploy e os secrets

1. **Manual, sua máquina.** Crie a chave que o GitHub Actions usa para entrar na VPS:

   ```sh
   ssh-keygen -t ed25519 -N '' -C github-actions-deploy -f nix-os-deploy
   ```

2. Troque a linha da chave em `keys/deploy.pub` pelo conteúdo de `nix-os-deploy.pub` e faça o
   commit. Esse arquivo é a metade pública da chave e fica no repositório.
3. **Manual, GitHub.** No fork, abra **Settings > Environments**, crie o environment `prod` e
   adicione três secrets:

   | Secret | Valor |
   |---|---|
   | `DEPLOY_SSH_KEY` | o conteúdo de `nix-os-deploy` (a chave privada) |
   | `DEPLOY_HOST` | o IPv4 da VPS (hPanel, **VPS > Overview**) |
   | `DEPLOY_KNOWN_HOSTS` | uma linha, `<ip> ssh-ed25519 AAAA…`: o IP, um espaço e a saída de `cat /etc/ssh/ssh_host_ed25519_key.pub` na VPS |

   Em **Deployment branches**, deixe só `main`. Depois apague `nix-os-deploy` da sua máquina.
4. **Manual, Hostinger.** Se o firewall da VPS estiver ligado (**VPS > Security > Firewall**),
   libere a porta TCP 22 para qualquer endereço. Os runners do GitHub conectam de muitos
   endereços.

## 4. O primeiro deploy

O usuário `deploy`, que o CI usa, não existe numa VPS nova. Crie esse usuário uma vez, por um
destes caminhos:

- **Manual, na VPS**, como root ou como o usuário do template:

  ```sh
  sudo nixos-rebuild test --flake 'github:<você>/nix-os#piabrota'
  # confira da sua máquina: ssh -i nix-os-deploy deploy@<ip> true
  sudo nixos-rebuild switch --flake 'github:<você>/nix-os#piabrota'
  ```

  O `test` não cria entrada de boot. Se algo falhar, um reboot volta ao sistema antigo. Este é o
  único build que roda na VPS.

- **Manual, sua máquina, com Nix:** `DEPLOY_HOST=<ip> just deploy <seu-usuário>`.

## 5. Daqui em diante

Cada merge em `main` constrói o sistema no GitHub e faz o deploy (`docs/DEPLOY.md`). Se um
switch quebrar o SSH, a VPS volta sozinha para a geração anterior. Mude o sistema num pull
request: o CI constrói o sistema antes do merge.

## Licença e créditos

O nix-os é MPL-2.0 (`LICENSE`). No seu fork, mantenha o arquivo de licença e os créditos do
`README.md` e de `docs/drawings/README.md`.
