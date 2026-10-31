# shellcheck shell=bash disable=SC1090,SC1091
# The `k8s` shell (kubesolo.nix): an interactive bash for operating KubeSolo on this box, with
# kubectl's completion, short aliases and the box's own chores. `k8s-help` lists them. The wrapper
# sets KUBECONFIG (the admin copy in /run/kubesolo-admin) and NIXOS_REPO before this file runs.

[ -f /etc/bashrc ] && . /etc/bashrc
[ -f ~/.bashrc ] && . ~/.bashrc

# The namespace `k` and the aliases use; `kn ax-system` sets it, `kn` clears it. The kubeconfig is
# read-only, so this lives in the shell, not in the context.
KNS=${KNS:-}
k() { kubectl ${KNS:+--namespace "$KNS"} "$@"; }
kn() { KNS=${1:-}; }

source <(kubectl completion bash)
complete -o default -F __start_kubectl k

alias kg='k get'
alias kd='k describe'
alias kl='k logs'
alias klf='k logs -f --tail=100'
alias kx='k exec -it'
alias kpf='k port-forward'
alias ka='k apply'
alias kdel='k delete'
alias kgp='kubectl get pods -A -o wide'
alias kga='kubectl get all -A'
alias kev='kubectl get events -A --sort-by=.lastTimestamp'
alias ax='kubectl --namespace ax-system'

# The node: its units, memory and log.
kubesolo-status() {
  systemctl is-active kubesolo pgx pgx-kube-secrets | paste -sd ' ' | sed 's/^/kubesolo pgx pgx-kube-secrets: /'
  kubectl get nodes -o wide
  printf 'kubesolo unit: %s MiB\n' "$(( $(systemctl show kubesolo -p MemoryCurrent --value) / 1048576 ))"
  free -m | head -2
}
kubesolo-log() { journalctl -u kubesolo -f; }

# rax-server (k8s/rax, docs/KUBESOLO.md "rax on KubeSolo").
rax-apply() {
  kubectl apply -k "$NIXOS_REPO/k8s/ax-tasks" &&
    kubectl apply -k "$NIXOS_REPO/k8s/rax" &&
    kubectl -n ax-system rollout status deploy/ax-server
}
# The task pods (ax-tasks, --runner=pod) and the Secret they all get.
alias tasks='kubectl --namespace ax-tasks'
agents-secret-refresh() { sudo systemctl restart kubesolo-secret-agents; }
rax-logs() { kubectl -n ax-system logs deploy/ax-server -f --tail=50; }
rax-health() {
  kubectl -n ax-system port-forward svc/ax-server 18080:8080 >/dev/null &
  local pf=$!
  sleep 2
  curl -fsS localhost:18080/healthz; echo
  kill "$pf"
}
# Its store: the Secret pgx.nix writes, and a pod that connects with it.
ax-secret-refresh() { sudo systemctl restart pgx-kube-secrets; }
# shellcheck disable=SC2016 # $AX_STORE expands in the pod, not here
ax-pgcheck() {
  kubectl -n ax-system run pgcheck --rm -i --restart=Never --image=postgres:18-alpine \
    --overrides='{"spec":{"containers":[{"name":"pgcheck","image":"postgres:18-alpine","command":["sh","-c","psql \"$AX_STORE\" -Atc \"select current_database(), version()\""],"env":[{"name":"AX_STORE","valueFrom":{"secretKeyRef":{"name":"ax-store","key":"url"}}}]}]}}'
}

k8s-help() {
  cat <<'EOF'
k8s: kubectl for KubeSolo on this box (kubesolo.nix, docs/KUBESOLO.md)

  k ...               kubectl, in the namespace set by `kn` (completion works)
  kn <ns> / kn        set / clear that namespace (shown in the prompt)
  kg kd kl klf        get, describe, logs, logs -f --tail=100
  kx kpf ka kdel      exec -it, port-forward, apply, delete
  kgp kga kev         pods, everything, events (all namespaces)
  ax ...              kubectl in ax-system

  kubesolo-status     units, node, memory      kubesolo-log    the node's log, followed
  rax-apply           kubectl apply -k k8s/ax-tasks and k8s/rax, then wait for the rollout
  tasks ...           kubectl in ax-tasks, where task pods run
  agents-secret-refresh  write the Secret ax-tasks/agents again from its env file
  rax-logs            rax-server's log         rax-health      GET /healthz through a port-forward
  ax-secret-refresh   write the Secret ax-store again (pgx-kube-secrets)
  ax-pgcheck          a pod that connects to PGX with that Secret

  exit                leave the k8s shell
EOF
}

PS1='\[\e[36m\]k8s${KNS:+:$KNS}\[\e[0m\] '"$PS1"
echo "k8s shell: k8s-help lists the aliases and commands."
