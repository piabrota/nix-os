# KubeSolo na piabrota

[English](KUBESOLO.md) (o espelho em inglês desta página)

Como experimentar o [KubeSolo](https://github.com/portainer/kubesolo) nesta VPS e como voltar
atrás. O módulo é o `kubesolo.nix`, atrás de `piabrota.kubesolo.enable`, que vem **desligado**:
desligado, o sistema construído é idêntico ao de antes (mesmo caminho no store). O desenho segue
o de [`MICROK8S.ptBR.md`](MICROK8S.ptBR.md): o nó vive neste repositório, as cargas vivem em
`k8s/` e entram por um túnel SSH, nunca por um deploy do sistema.

Escrito em 2026-10-30. ⚠ marca o que não foi verificado numa máquina rodando o KubeSolo.

## O que é

| Ponto | Valor | Fonte |
|---|---|---|
| Projeto | `portainer/kubesolo`, da Portainer, licença MIT | [repositório](https://github.com/portainer/kubesolo) |
| Versão empacotada | v1.2.3, de 2026-10-27 | [release](https://github.com/portainer/kubesolo/releases/tag/v1.2.3) |
| Forma | Um binário só. A variante musl de amd64 é estática (`file`: *statically linked*), 197 423 240 bytes, num `.tar.gz` de 86 MB | baixado e inspecionado aqui |
| O que vem dentro | apiserver, controller-manager e kubelet num processo só; containerd e crun; CoreDNS; Kine sobre SQLite no lugar do etcd; sem scheduler (um webhook, `NodeSetter`, preenche `spec.nodeName`) | README do projeto |
| Rede | Bridge `cni0`, pods em `10.42.0.0/16`, serviços em `10.43.0.0/16`, CoreDNS em `10.43.0.10`; kube-proxy em iptables (ou nftables, se `ip_tables` não carregar) | `types/const.go`, `install.sh` |
| Portas | 6443 (API), 10250 (kubelet), 10443 (webhook); 6060 (pprof) e 9105 (métricas) só se ligados; o Kine usa um socket unix | `uninstall.sh`, `types/const.go`, exemplo de config |
| Estado | `/var/lib/kubesolo`: PKI, banco SQLite, containerd, kubelet. Também escreve `/etc/cni/net.d/10-bridge.conflist` | exemplo de config, `uninstall.sh` |
| Imagens puxadas na partida (variante online) | `coredns/coredns:1.14.4`, `portainer/pause:latest`; `rancher/local-path-provisioner:v0.0.36` se o storage local estiver ligado | strings do binário, `types/const.go` |
| Memória | "menos de 200 MB", número do fornecedor ⚠ não medido aqui | README do projeto |
| Conformidade | Não passa na conformidade CNCF, diz o próprio projeto | [`KUBERNETES.ptBR.md`](KUBERNETES.ptBR.md) |

**O nixpkgs não tem KubeSolo** (nem `nixos-26.05`, nem `master`, em 2026-10-30). O
`kubesolo/package.nix` empacota o binário da release: `fetchurl` com versão e hash fixos (o hash é
o `sha256` que o GitHub publica para o asset, conferido aqui com `shasum`) e um `install`. Compilar
do fonte não dá: o `make build` do projeto baixa containerd, crun e os plugins CNI durante o build.
Como é estático, não precisa de `patchelf` nem de glibc. Para atualizar, troque `version` e `hash`
juntos.

## O custo

| | Valor |
|---|---|
| Closure, flag desligada | **0**: `system.build.toplevel` é o mesmo caminho de antes (`w0mb8vfj…`), avaliado aqui |
| Closure, flag ligada | **≈ +191 MiB**: o binário (188,3 MiB) mais `nftables` e suas libs que o sistema ainda não tem (jansson, gmp, libedit: no máximo 2,4 MiB, pelo `nix path-info` no cache.nixos.org). `iptables`, `kmod`, `util-linux` e `iproute2` já estão no sistema ⚠ `dix` não rodou: o sistema é x86_64 e a máquina daqui não constrói x86_64 |
| Download | O binário não está no cache.nixos.org: o runner baixa o `.tar.gz` (86 MB) do GitHub, e o deploy-rs copia os 188 MiB do runner para a VPS uma vez por versão. Nada é compilado em lugar nenhum |
| Disco, em uso | `/var/lib/kubesolo` com o containerd, as imagens e o banco ⚠ tamanho não medido |
| RAM | KubeSolo, containerd e shims ficam na unit `kubesolo`, limitada a `MemoryMax=1G`. Os pods ficam em `kubepods.slice`, que o kubelet limita à memória do nó menos `systemReserved` (1536 Mi aqui): os pods juntos não passam de uns 2,2 GiB ⚠ |
| CPU | `CPUQuota=60%` e `CPUWeight=50` na unit. O sshd e o nginx disputam a mesma vCPU com peso normal. Sem `systemReserved.cpu`: o KubeSolo arredonda para CPUs inteiras e, com uma vCPU, sai na partida (`--system-reserved cpu=300m reserves 1 of this host's 1 CPUs, leaving none for workloads`; isso parou o primeiro deploy, em 2026-10-30, e o deploy-rs voltou atrás) |

## O que o módulo faz quando ligado

- Roda a unit `kubesolo` com `--config` apontando para um YAML no store, gerado de
  `piabrota.kubesolo.settings`. O módulo põe padrões (todos com `mkDefault`): IPv6 desligado
  (encaminhar IPv6 no host faria a VPS ignorar router advertisements), load balancer desligado
  (ele daria o IP público a todo Service `LoadBalancer`, passando pelo firewall), storage local,
  d2k, métricas, pprof e a API de configuração desligados, `127.0.0.1` e `localhost` no
  certificado da API, e o `systemReserved` acima.
- Carrega `br_netfilter` e `overlay`, e liga `net.ipv4.ip_forward` e
  `net.bridge.bridge-nf-call-iptables`.
- Confia em `cni0` no firewall do NixOS, para os pods falarem com a API e o CoreDNS. **Não abre
  nenhuma porta**: 6443, 10250 e 10443 ficam fechadas para fora.
- Põe `iptables`, `nftables`, `kmod`, `util-linux` e `iproute2` no `PATH` da unit.
- Recusa avaliar se docker, podman ou containerd estiverem ligados (o KubeSolo traz o próprio
  containerd).

Sem sandbox do systemd (`ProtectSystem`, `PrivateTmp`, `NoNewPrivileges`, `SystemCallFilter`):
containerd e kubelet rodam dentro da unit, todo pod herda os namespaces e filtros seccomp dela, e o
kubelet precisa de montagens que se propagam para o host. O endurecimento possível é o firewall
fechado, os limites de recurso e as opções que desligam o que escuta. `KillMode=process` e
`Delegate=yes` vêm da unit do upstream: sem eles, um restart duplica todos os pods (issue #197 do
projeto); a consequência é que parar a unit **não** para os pods (veja o rollback).

`checks.kubesolo-example` constrói o sistema com a flag ligada, então o CI pega um módulo quebrado
antes de alguém ligá-lo.

## Ligar

1. **Tire um snapshot na Hostinger antes** (passo (d) do rollback).
2. Abra um PR de uma linha no `configuration.nix`, ao lado do `piabrota.site.enable`:

   ```nix
   piabrota.kubesolo.enable = true;
   ```

3. O merge faz o deploy. Na VPS, acompanhe a partida (puxa CoreDNS e pause na primeira vez):

   ```console
   ssh h0ffmann@piabrota.art
   systemctl status kubesolo
   journalctl -u kubesolo -f
   free -m
   ```

## Chegar na API

A API fica fechada para a internet. Do seu computador, com `kubectl` instalado lá (não na VPS):

```console
# o kubeconfig de admin, só root lê
ssh h0ffmann@piabrota.art sudo cat /var/lib/kubesolo/pki/admin/admin.kubeconfig > ~/.kube/piabrota.yaml
chmod 600 ~/.kube/piabrota.yaml

# o túnel, num terminal à parte
ssh -N -L 6443:127.0.0.1:6443 h0ffmann@piabrota.art

# aponte o kubeconfig para o túnel
kubectl --kubeconfig ~/.kube/piabrota.yaml config set-cluster \
  "$(kubectl --kubeconfig ~/.kube/piabrota.yaml config view -o jsonpath='{.clusters[0].name}')" \
  --server=https://127.0.0.1:6443
export KUBECONFIG=~/.kube/piabrota.yaml
kubectl get nodes
```

⚠ Se a API não escutar em 127.0.0.1 (só no IP do nó), use `-L 6443:<ip-da-vps>:6443` no túnel; o
certificado cobre o IP do nó e, pela config deste módulo, `127.0.0.1`.

## Uma primeira carga

```console
kubectl create deployment hello --image=nginxdemos/hello:plain-text
kubectl set resources deployment hello --requests=cpu=10m,memory=16Mi --limits=cpu=200m,memory=64Mi
kubectl expose deployment hello --port=80          # ClusterIP, nunca NodePort
kubectl port-forward svc/hello 8080:80             # pelo túnel da API
curl localhost:8080
kubectl delete deployment,svc hello
```

**Nada de `NodePort` nem `LoadBalancer`.** O DNAT do kube-proxy acontece antes da cadeia `INPUT`
do firewall do NixOS ⚠ (é como o iptables funciona; não testado aqui), então uma NodePort fica
aberta para a internet. Para publicar algo, o caminho é o mesmo dos apps Loco: o nginx da VPS como
proxy, num PR deste repositório, para um Service exposto só no loopback (⚠ isso pede um
`hostPort` em 127.0.0.1 ou um `kubectl port-forward` como unit; ainda não desenhado).

## rax no KubeSolo

[piabrota/rax](https://github.com/piabrota/rax) (MPL-2.0) é o porte em Rust do
[AX](https://github.com/google/ax), o orquestrador declarativo de tarefas agênticas sobre o
[Agent Substrate](https://github.com/agent-substrate/substrate). Ele mantém a API `ax.io/v1alpha1`
do AX (serviço gRPC e `/healthz` na mesma porta, 8080).

### O que o rax completo pede do cluster

Segundo o próprio `docs/minikube-footprint.md` e `docs/local-kubernetes.md` do rax (2026-10-29, ⚠
estimativas que o rax ainda não rodou de ponta a ponta):

- **Agent Substrate**: uns 15 deployments em `ate-system` (API, IdP, controller, router com Envoy,
  atelet em DaemonSet, RustFS para snapshots, PostgreSQL), workers gVisor que rodam como root com
  `SYS_ADMIN` e `NET_ADMIN`, e um controller de certificados de pod.
- **Feature gates** `ClusterTrustBundle`, `ClusterTrustBundleProjection` e
  `PodCertificateRequest`, mais a API `certificates.k8s.io/v1beta1`. O manifesto do `ax-server`
  monta volumes `podCertificate` e `clusterTrustBundle`. **O KubeSolo não tem configuração para
  feature gates** (nenhuma chave em `config.yaml` nem flag para isso) ⚠.
- **PostgreSQL** para o AX (ou `--store memory://`, que perde tudo no restart). Aqui é o
  [PGX](PGX.ptBR.md), no host, e não um servidor PostgreSQL num pod.
- **Tamanho**: 26 pods, ≈1,5 CPU e ≈2 GiB pedidos, 2 a 3 GiB em repouso, ≈6 GB de imagens no nó;
  mínimo estimado de 3 CPUs e 6 GB.

**Isso não cabe no KVM 1** (1 vCPU, 4 GB, ao lado do KubeSolo, do nginx e do sshd), e o KubeSolo
nem liga os feature gates. O que cabe é o **`rax-server` sozinho**: a API do AX com o store no
PGX do host, sem Substrate. Ele sobe sem Substrate ("running without substrate reconciliation", no
`main.rs`) ⚠ não testado num cluster; aceita, lista e apaga Tasks, Workspaces e Models, mas não
executa nenhuma tarefa. Serve para testar a API, o CLI `rax` e o caminho até o cluster.

### Os manifestos: `k8s/rax/`

`k8s/rax/` é o `ax-server.yaml` de `test/e2e/manifests` do AX, cortado para um nó pequeno
(`kubectl kustomize k8s/rax` renderiza; conferido aqui):

- `namespace.yaml`: o namespace `ax-system` e uma `ResourceQuota` (no máximo 512 Mi e 1 CPU de
  limites, 4 pods, nenhuma NodePort nem LoadBalancer).
- `rax-server.yaml`: ServiceAccount, uma `Role` que lê secrets **só em `ax-system`** (o AX usa
  `ClusterRole`), o Deployment (`--addr=:8080`, a URL do store vinda do Secret `ax-store`, `Recreate`, usuário 65534,
  sistema de arquivos só de leitura, sem capabilities, seccomp `RuntimeDefault`, pede 50m/64Mi,
  limita a 500m/256Mi) e um Service `ClusterIP` na 8080.
- `kustomization.yaml`: a imagem é `rax-server:dev`, importada à mão; troque por um registro em
  `images:` quando houver um.

O `deploy.yml` ignora `k8s/**`: um merge que só mexe em `k8s/` não troca o sistema. Este PR não
traz workflow que aplique os manifestos. Quando houver, segue o `MICROK8S.ptBR.md`: um `k8s.yml`
num ambiente `k8s` separado do `prod`, que abre o túnel SSH e roda `kubectl apply -k k8s/rax`.

### A imagem

A VPS não compila nada, então a imagem chega pronta. O rax não publica imagem nem empacota o
`rax-server` em Nix hoje. Dois caminhos:

1. **Construir fora e importar** (sem registro). Numa máquina x86_64 com Docker, no checkout do
   rax:

   ```console
   docker build -f Dockerfile.server -t rax-server:dev .
   docker save rax-server:dev | ssh h0ffmann@piabrota.art \
     'sudo nix shell nixpkgs#containerd -c ctr --address "$(sudo find /var/lib/kubesolo -name containerd.sock | head -1)" -n k8s.io images import -'
   ```

   ⚠ O caminho do socket do containerd do KubeSolo não foi visto numa máquina rodando
   (`types/const.go` sugere `/var/lib/kubesolo/containerd/containerd.sock`). O `nix shell`
   baixa o `ctr` do cache, não compila, e não fica no sistema.
2. **Publicar num registro**: um workflow no repositório do rax que construa a imagem (pelo
   Dockerfile, ou em Nix com `dockerTools.buildLayeredImage` sobre um `rustPlatform.buildRustPackage`,
   que o rax ainda não tem) e a mande para `ghcr.io/piabrota/rax-server`. Aí `k8s/rax/kustomization.yaml`
   ganha `newName` e `digest`. ⚠ Não existe ainda.

A imagem do `Dockerfile.server` tem 34 MB para baixar e 135 MB no nó (medidos pelo rax); sobre
musl ou distroless seriam uns 80 MB a menos.

### Rodar, chegar, tirar

Primeiro o store: um banco no PGX, e a URL dele num Secret (nunca no repositório). Na VPS:

```console
pgx create ax
pgx url ax                     # postgres://postgres:<senha>@127.0.0.1:5432/ax
ip -4 -br addr show cni0       # o host como os pods o veem, 10.42.0.1 ⚠ confira: ainda não visto
```

Depois, pelo túnel, com essa URL e o endereço do `cni0` no lugar de `127.0.0.1`:

```console
kubectl create namespace ax-system
kubectl -n ax-system create secret generic ax-store \
  --from-literal=url='postgres://postgres:<senha>@10.42.0.1:5432/ax?sslmode=disable'
kubectl apply -k k8s/rax
kubectl -n ax-system rollout status deploy/ax-server
kubectl -n ax-system port-forward svc/ax-server 8080:8080   # pelo túnel da API
curl localhost:8080/healthz                                  # ok
rax --server localhost:8080 get tasks
```

Sem `--server`, o `rax` faz o próprio `port-forward` para `svc/ax-server` no contexto atual, como
o `ax`. Pelo nginx num caminho (`/rax`) não: a API é gRPC sem autenticação, e não deve ficar na
internet.

**Tire o rax antes de desligar o KubeSolo:**

```console
kubectl delete -k k8s/rax --wait
kubectl get ns ax-system      # NotFound
```

## Rollback

### (a) O caminho normal: um PR que desliga

Reverta o PR que ligou (ou mude a linha para `false`) e faça o merge. O deploy para e remove a unit
`kubesolo` e o binário sai do sistema (o caminho fica no store até a coleta de lixo: 14 dias e 5
gerações, `deploy.nix`).

O que o deploy-rs cobre: se o SSH não responder em 60 s depois da troca, ele volta a geração
anterior sozinho (magic rollback), e uma ativação que falha também volta (`autoRollback`). O que
**não** cobre: a unit é `Type=simple`, então a troca dá certo mesmo que o KubeSolo caia em loop
depois; falta de memória que aparece minutos depois, quando os pods sobem; imagens baixadas; e
todo o estado fora do store (passo (c)). E como o KubeSolo usa `KillMode=process`, desligar a
unit **deixa os containers rodando** até o passo (c) ou um reboot.

### (b) Emergência na VPS

Se a VPS ficar lenta demais para um PR esperar:

```console
ssh h0ffmann@piabrota.art
sudo systemctl stop kubesolo kubepods.slice   # para o KubeSolo e todos os pods ⚠
sudo nixos-rebuild switch --rollback          # volta à geração anterior
```

Sem SSH: o console serial no hPanel (VPS → Console), reinicie e escolha a geração anterior no menu
do GRUB (o `configuration.nix` mostra o menu por 1 s; o GRUB guarda 5 gerações). Já dentro, rode
`sudo nixos-rebuild switch --rollback` para que ela fique como padrão. Depois, **reverta no `main`
também** (passo (a)), ou o próximo deploy traz o KubeSolo de volta.

### (c) Limpar o que fica

Nada disto está no store, e nenhum rollback do NixOS apaga. Depois que a flag estiver desligada:

```console
# 1. parar pods que sobraram (KillMode=process os deixa vivos)
sudo systemctl stop kubepods.slice            # ⚠ ou reinicie a VPS
# 2. desmontar o que o containerd montou e apagar o estado
findmnt -rn -o TARGET | grep '^/var/lib/kubesolo' | sort -r | xargs -r -n1 sudo umount -l
sudo rm -rf /var/lib/kubesolo /etc/cni/net.d/10-bridge.conflist
# 3. rede: a bridge e as regras do kube-proxy e do CNI
sudo ip link delete cni0 2>/dev/null
sudo ip link show | grep -o 'veth[^@:]*' | xargs -r -n1 sudo ip link delete
sudo iptables-save | grep -v -E 'KUBE-|CNI-' | sudo iptables-restore
sudo nft list tables | grep -i kube           # se o kube-proxy usou nftables: sudo nft delete table ip kube-proxy
sudo systemctl restart firewall               # recria as regras do NixOS
```

O caminho mais simples e seguro é **reiniciar a VPS** depois do deploy que desliga: as regras de
iptables, a `cni0`, os `veth`, as montagens, o `ip_forward` e os módulos não sobrevivem ao boot,
e o KubeSolo não sobe mais. Só sobram `/var/lib/kubesolo` e `/etc/cni/net.d/10-bridge.conflist`
para apagar. O kubeconfig no seu computador (`~/.kube/piabrota.yaml`) também pode ir.

### (d) Snapshot da Hostinger antes de ligar

No hPanel: **VPS → Snapshots e backups → Criar snapshot**, antes do merge que liga. É a volta
completa se tudo o mais falhar: restaurar devolve o disco inteiro àquele momento (e perde o que
mudou depois). ⚠ Pelo que a Hostinger documenta, cada VPS guarda um snapshot só, e um novo
substitui o anterior; confira no painel antes de contar com ele.

## Fontes e o que não foi verificado

- KubeSolo: [README](https://github.com/portainer/kubesolo),
  [`examples/kubesolo-config.yaml`](https://github.com/portainer/kubesolo/blob/develop/examples/kubesolo-config.yaml),
  [`docs/configuration/config-file.md`](https://github.com/portainer/kubesolo/blob/develop/docs/configuration/config-file.md),
  `install.sh` (a unit systemd, `KillMode=process`, `Delegate=yes`, os pré-requisitos de
  iptables), `uninstall.sh` (portas, montagens, limpeza), `types/const.go` (CIDRs, imagens),
  `pkg/kubernetes/kubelet/config.go` (driver de cgroup `systemd`, `systemReserved`); a
  [release v1.2.3](https://github.com/portainer/kubesolo/releases/tag/v1.2.3) e o binário,
  inspecionado com `file` e `strings`.
- nixpkgs: `pkgs/by-name/ku/` em `nixos-26.05` e `master`, sem `kubesolo`.
- rax: [README](https://github.com/piabrota/rax), `docs/minikube-footprint.md`,
  `docs/local-kubernetes.md`, `Dockerfile.server`, `crates/rax-server/src/main.rs`; AX:
  [`test/e2e/manifests/ax-server.yaml`](https://github.com/google/ax/blob/main/test/e2e/manifests/ax-server.yaml).
- Verificado aqui: o hash do binário, que ele é estático, que a flag desligada não muda o
  sistema, `nix flake check --no-build --all-systems`, nixpkgs-fmt, statix, deadnix, e que
  `k8s/rax` renderiza com `kubectl kustomize`. O CI constrói `checks.kubesolo-example` em x86_64.
- **Não verificado** (⚠): o KubeSolo rodando no NixOS ou nesta VPS; sua memória real; o tamanho de
  `/var/lib/kubesolo`; se a API escuta em 127.0.0.1; se os pods chegam à API com só `cni0`
  confiável; se `systemctl stop kubepods.slice` para todos os pods; o socket do containerd para o
  `ctr import`; o `rax-server` subindo sem Substrate num cluster; a política de snapshots da
  Hostinger.
