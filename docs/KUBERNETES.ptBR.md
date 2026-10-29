# Kubernetes na piabrota

[English](KUBERNETES.md)

Uma pesquisa, de 2026-10-29, das distribuições pequenas de Kubernetes que poderiam rodar nesta
VPS ao lado do que ela já hospeda: nginx com ACME na frente de apps Loco (Rust e SQLite), cada
uma um serviço systemd isolado com `MemoryMax=256M` por padrão (`loco.nix`). É só pesquisa:
nada na configuração mudou por causa dela.

A máquina é o plano **KVM 1** da Hostinger: 1 vCPU, 4 GB de RAM (mais zram de 50%), 50 GB de
disco, NixOS 26.05, closure do sistema de 1,19 GiB.

## Recomendação

**Não rode Kubernetes nesta máquina para a carga atual.**

A única distribuição que o NixOS suporta bem é o k3s, e ele caberia na memória, mas por pouco:
a própria documentação mede um servidor de um nó em 1,2 a 1,45 GB sem nada implantado. É um
terço da RAM, e uma parte do único núcleo, gasta para orquestrar alguns serviços systemd que o
NixOS já orquestra, com rollback, pelo deploy-rs.

Se você quer containers, use `virtualisation.oci-containers` com podman: nenhum daemon parado,
cerca de 200 MiB de closure. Se você quer o próprio Kubernetes (para aprender, ou porque um
chart precisa dele), use `services.k3s` enxuto, como abaixo, ou mude para um plano KVM 2, onde
ele não disputa a máquina com as apps.

## As opções

"Closure a mais" é o que o pacote soma ao sistema implantado além do que já está nele, medido no
cache.nixos.org para o nixpkgs `08d3a97` (o rev do `flake.lock`). Quando o projeto não está no
nixpkgs, não há closure para medir.

| Opção | RAM parada | CPU parada | Closure a mais | No NixOS 26.05 | Manutenção | Cabe aqui |
|---|---|---|---|---|---|---|
| **k3s** (SUSE / Rancher, CNCF) | 1,2–1,45 GB | 5–25% de um núcleo | +472 MiB | `services.k3s` no nixpkgs, pacote 1.35.8+k3s1, testes NixOS, manifests e charts Helm declarativos | releases de patch todo mês | apertado |
| **k3s enxuto** | ~1,2 GB | igual | +472 MiB | o mesmo módulo, com flags `--disable` | igual | apertado |
| **KubeSolo** (Portainer) | <200 MB (do fabricante) | não publicado | fora do nixpkgs | sem pacote e sem módulo; você empacotaria o binário Go | v1.2.3 em 2026-10-27, releases a cada poucas semanas; projeto novo, de uma empresa | cabe, sem pacote |
| **k0s** (Mirantis, CNCF sandbox) | ≥1 GB (mínimo da doc) | 1 vCPU no mínimo | fora do nixpkgs | só o flake comunitário `johbo/k0s-nix`, marcado como experimental | ativo: v1.36.3, 1.37 em alpha | apertado, sem pacote |
| **MicroK8s** (Canonical) | 540 MB mín., 4 GB recomendados | não publicado | n/a | só snap, e o nixpkgs não tem `snapd` | ativo, feito para Ubuntu | não |
| *Nomad* (HashiCorp), comparação | não medido | não medido | sem cache | `services.nomad` existe, mas o pacote é BUSL-1.1, logo unfree; este repo mantém `allowUnfree` desligado | ativo; licença mudou em 2023 | excluído |
| *systemd + podman*, comparação | ≈0 (sem daemon) | ≈0 | +200 MiB | `virtualisation.podman`, `virtualisation.oci-containers` | Red Hat, releases regulares (5.8.9 aqui) | sim |
| *só systemd* (hoje) | 0 | 0 | 0 | o `loco.nix` já faz isso | você | sim |

- **k3s.** O único Kubernetes com suporte de primeira classe no NixOS: um módulo mantido, um
  pacote que acompanha o upstream e manifests declarados em Nix. Nesta máquina, o piso de 1,2 GB
  mais as apps deixa pouca folga, e o único núcleo é dividido entre os pods, o nginx e a ativação
  do deploy. O Traefik e o ServiceLB que vêm com ele querem as portas 80 e 443, que são do nginx,
  então os dois precisam sair.
- **KubeSolo.** O mais leve no papel: um processo, SQLite via Kine, sem etcd e sem scheduler.
  Os 200 MB são da própria Portainer, e o projeto diz que não passa na conformidade da CNCF. Não
  está no nixpkgs: você escreveria a derivation e a unit systemd e as manteria em dia. Vale
  acompanhar, ainda não vale carregar.
- **k0s.** Bem mantido upstream e um binário único, mas no NixOS só existe num flake comunitário
  experimental, e o mínimo documentado para controller e worker é 1 vCPU e 1 GB, a mesma ordem
  do k3s sem o suporte do módulo.
- **MicroK8s.** Só sai como snap. O NixOS não tem snapd, então não há jeito suportado de
  instalar, e a Canonical recomenda 4 GB para cargas reais, que é a máquina inteira.

## Se você rodar o k3s mesmo assim

Um servidor de um nó enxuto: SQLite em vez de etcd (o padrão para um servidor), o nginx continua
na borda e os add-ons que não servem ficam desligados. Não foi construído nem testado; meça com
`dix`, como pede o `AGENTS.md`.

```nix
services.k3s = {
  enable = true;
  role = "server";
  extraFlags = [
    "--disable=traefik"          # o nginx já tem as portas 80 e 443
    "--disable=servicelb"
    "--disable=metrics-server"
    "--disable=local-storage"    # mantenha se um pod precisar de PVC
    "--disable-cloud-controller"
    "--disable-helm-controller"  # tire se usar services.k3s.autoDeployCharts
    "--kubelet-arg=system-reserved=memory=512Mi"
  ];
};
# O nginx então faz proxy para um NodePort, como faz hoje para as apps Loco.
# Conte com o closure indo de 1,19 GiB para cerca de 1,65 GiB, mais as imagens em /var/lib/rancher.
```

## Fontes e o que não foi verificado

- RAM e CPU do k3s: [k3s resource profiling](https://docs.k3s.io/reference/resource-profiling)
  (servidor sem carga: 1428 MB com SQLite e 1450 MB com etcd num Intel 8375C, 1215 MB num
  Pi 4B; 5% e 25% de um núcleo).
- k0s: [requisitos do k0s](https://docs.k0sproject.io/main/system-requirements/); no NixOS:
  [johbo/k0s-nix](https://github.com/johbo/k0s-nix); versões pelas
  [notas da v1.36.3](https://newreleases.io/project/github/k0sproject/k0s/release/v1.36.3%2Bk0s.0).
- KubeSolo: [portainer/kubesolo](https://github.com/portainer/kubesolo) e
  [a documentação](https://kubesolo.pages.dev/documentation); versões pelo
  [pkg.go.dev](https://pkg.go.dev/github.com/portainer/kubesolo?tab=versions).
- MicroK8s: 540 MB e 4 GB pela
  [LinuxConfig](https://linuxconfig.org/linux-system-requirements-for-kubernetes) e pelo
  [fórum do Kubernetes](https://discuss.kubernetes.io/t/get-started/18344); não confirmados na
  página da Canonical.
- Versões, licenças, módulos e closures: avaliados no canal nixos-26.05 em `08d3a97` e com
  `nix path-info` contra o cache.nixos.org. "Closure a mais" é o closure menos o de systemd,
  coreutils, bash, openssh, nginx, iptables, util-linux, glibc, sqlite, openssl, curl e git,
  então é próximo do número do `dix`, não igual.
- Não verificado: o uso de memória atual da máquina, a CPU parada do Nomad e do KubeSolo, e
  qualquer uma destas opções rodando nesta VPS.
