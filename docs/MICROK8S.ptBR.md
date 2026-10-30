# MicroK8s na piabrota

[English](MICROK8S.md)

Uma pesquisa de 2026-10-29 para o próximo PR: testar o MicroK8s nesta VPS com o gerenciamento do
Kubernetes separado do gerenciamento do sistema operacional. É só pesquisa: nada na configuração
mudou por causa dela. Complementa o [`KUBERNETES.ptBR.md`](KUBERNETES.ptBR.md), que comparou as
distribuições e classificou o MicroK8s como "não cabe".

## Resposta curta

- O MicroK8s só existe como snap, e o nixpkgs não tem snapd. O único caminho no NixOS é o flake
  comunitário [nix-community/nix-snapd](https://github.com/nix-community/nix-snapd)
  (`services.snap.enable`).
- Não achei nenhum relato do MicroK8s rodando no NixOS por esse caminho, e o README do nix-snapd
  não diz se snaps com confinamento `classic` (que o MicroK8s pede) funcionam. Trate como
  experimento: teste numa VM local antes da VPS.
- Para ser modular, divida em duas camadas: o **nó** (snapd, MicroK8s, kernel, firewall) fica
  neste repositório atrás de uma flag desligada por padrão; as **cargas** (manifests, charts) ficam
  em `k8s/` com um workflow próprio. Um deploy do sistema nunca mexe nos pods, e uma mudança nos
  pods nunca troca o sistema.
- Se o nix-snapd não rodar o MicroK8s, a mesma divisão funciona com o `services.k3s`, que é nativo
  do NixOS.

## Como o MicroK8s entraria no NixOS

| Ponto | O que acontece | Consequência aqui |
|---|---|---|
| Instalação | `snap install microk8s --classic`, pelo snapd do nix-snapd | Um input novo no flake (`nix-snapd`, com `nixpkgs.follows`) |
| Confinamento | A variante `strict` existe, mas bloqueia cargas que precisam de mount compartilhado com o host | Use `--classic`, que é justamente o que ninguém testou no nix-snapd |
| Atualização | O snapd atualiza o snap sozinho, fora do Nix | Um rollback do NixOS não volta o MicroK8s. Fixe o canal (`--channel=1.3x/stable`) e segure as atualizações (`snap refresh --hold microk8s`) |
| Estado | `/var/snap/microk8s`, `/var/lib/snapd`, `/snap` | Fora da store: a coleta de lixo do Nix não toca, e desligar a flag não apaga |
| Memória | 540 MB no mínimo, 4 GB recomendados (fontes abaixo) | Cabe no KVM 1 só com poucos addons, dividindo o único núcleo com o nginx e os apps |

## As duas camadas

### Camada 1: o nó (este repositório, `deploy.yml`)

Um módulo `k8s.nix` com `piabrota.k8s.enable`, desligado por padrão, como o `site.nix`. Ligado,
ele:

- importa `nix-snapd.nixosModules.default` e liga `services.snap.enable`;
- roda uma unidade oneshot `microk8s-install` que instala o snap no canal fixado, se ainda não
  estiver instalado, e segura as atualizações;
- carrega os módulos de kernel `br_netfilter` e `overlay` e liga `net.ipv4.ip_forward`;
- confia nas interfaces do CNI no firewall (`cali+`, `vxlan.calico`) e deixa a API (16443)
  fechada: o acesso é por túnel SSH;
- reserva memória para o sistema no kubelet (`--system-reserved=memory=512Mi`), para um pod não
  derrubar o `sshd`.

Um `checks.k8s-example` builda o sistema com a flag ligada, como o `checks.loco-example`, para o
CI pegar um módulo quebrado antes de alguém ligar a flag.

Por que não um segundo `nixosConfiguration` ou um perfil separado no deploy-rs: a VPS tem um só
perfil de sistema. Dois sistemas para a mesma máquina se sobrescrevem a cada deploy, e o que
fizesse o último deploy ganharia. A flag é o jeito de ligar e desligar o Kubernetes sem dividir o
sistema.

### Camada 2: as cargas (`k8s/`, um workflow próprio)

- Os manifests (ou um `kustomization.yaml`) ficam em `k8s/`, ou num repositório separado.
- Um `k8s.yml` roda no push para a `main` quando `k8s/**` muda: abre um túnel SSH até a porta
  16443 e roda `kubectl apply --server-side -k k8s/`. O kubeconfig fica num secret de um
  environment `k8s`, separado do `prod`.
- O `deploy.yml` ganha `k8s/**` no `paths-ignore`. Assim um deploy do sistema nunca reaplica os
  pods, e uma mudança nos pods nunca troca o sistema.
- Alternativa: o Flux, instalado uma vez, puxa `k8s/` sozinho e não precisa de acesso de entrada.
  Custa quatro controladores, algumas centenas de MiB a mais. Numa máquina de 4 GB, o workflow
  com `kubectl` é mais barato.

### Entrada de tráfego

O nginx continua dono das portas 80 e 443 (o site e os apps Loco). O addon `ingress` do MicroK8s
fica desligado; o nginx faz proxy para um NodePort, como já faz para os apps Loco.

## Plano de teste para o próximo PR

1. **Local.** Buildar a VM com a flag ligada (`nix run .#nixosConfigurations.piabrota.config.system.build.vm`,
   numa máquina x86_64 com KVM) e ver se `snap install microk8s --classic` funciona e se
   `microk8s status --wait-ready` termina. Um `nixosTest` no CI não serve aqui: a VM de teste não
   tem rede e não baixa o snap.
2. **Antes da VPS.** Tirar um snapshot na Hostinger. O magic rollback do deploy-rs só protege o
   SSH, não a memória.
3. **Na VPS.** Fazer o merge do PR com a flag ligada e medir: `free -m` em repouso, o tempo até o
   `status --wait-ready` e um pod de teste acessado pelo nginx via NodePort.
4. **Saída.** `sudo snap remove --purge microk8s`, depois um PR com a flag desligada, depois apagar
   `/var/lib/snapd` à mão.
5. **Se o nix-snapd falhar.** A mesma divisão em duas camadas com o `services.k3s`
   ([`KUBERNETES.ptBR.md`](KUBERNETES.ptBR.md) tem a configuração enxuta).

## Fontes e o que não foi conferido

- nix-snapd: [README](https://github.com/nix-community/nix-snapd) e a
  [página Snap do wiki do NixOS](https://wiki.nixos.org/wiki/Snap), que diz que o snap ainda não
  está no nixpkgs.
- MicroK8s só como snap: [Snap Store](https://snapcraft.io/microk8s) e
  [este comentário no Hacker News](https://news.ycombinator.com/item?id=27916515).
- Confinamento estrito: [documentação do MicroK8s](https://microk8s.io/docs/strict-confinement).
- Memória: as mesmas fontes do [`KUBERNETES.ptBR.md`](KUBERNETES.ptBR.md) (540 MB e 4 GB, não
  confirmados na página da Canonical).
- Não conferido: o MicroK8s rodando de fato pelo nix-snapd, o consumo de memória nesta VPS e se as
  unidades `snap.microk8s.*` aceitam limites de memória vindos do NixOS.
