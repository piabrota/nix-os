# KubeSolo ran here from 2026-10-30 to 2026-11-02 and is gone from the configuration. Removing its
# module stops the unit, but NixOS deletes nothing outside the store, and KubeSolo's
# KillMode=process leaves the pods running. This unit clears what is left, once: the steps of
# the old docs/KUBESOLO.md, "Cleaning what is left" (in git history). It runs only while
# /var/lib/kubesolo exists, never fails, and is not a oneshot, so the switch does not wait for it
# (stopping the pods can take a while) and it cannot make deploy-rs roll a deploy back.
# Delete this file in a later PR, once `ls /var/lib/kubesolo` on the box says it is gone.
{ config, pkgs, ... }:
{
  systemd.services.kubesolo-purge = {
    description = "Delete what KubeSolo left on the box";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/var/lib/kubesolo";
    path = with pkgs; [ coreutils findutils gnugrep util-linux iproute2 iptables nftables kmod procps config.systemd.package ];
    script = ''
      set +e
      # 1. The pods, then the containerd shims that outlived the unit.
      systemctl stop kubepods.slice
      pkill -f containerd-shim-runc-v2
      # 2. What containerd and the kubelet mounted, deepest first, then the state. Lazy unmounts
      #    detach at once, and --one-file-system keeps rm out of anything still mounted.
      findmnt -rn -o TARGET | grep -E '^(/var/lib/kubesolo|/run/containerd|/run/netns/cni-)' | sort -r \
        | xargs -r -n1 umount -l
      rm -rf --one-file-system /var/lib/kubesolo /var/lib/kubesolo-secrets /run/kubesolo-admin \
        /etc/cni/net.d/10-bridge.conflist
      rmdir /etc/cni/net.d /etc/cni 2>/dev/null
      # 3. The pod network: the bridge, the veths, kube-proxy's and the CNI's rules, forwarding.
      ip link delete cni0 2>/dev/null
      ip -o link show | grep -o 'veth[^@:]*' | xargs -r -n1 ip link delete
      for t in iptables ip6tables; do
        if "$t-save" | grep -q -E 'KUBE-|CNI-'; then
          "$t-save" | grep -v -E 'KUBE-|CNI-' | "$t-restore"
        fi
      done
      nft list tables 2>/dev/null | grep -i kube | while read -r _ family name; do nft delete table "$family" "$name"; done
      sysctl -q -w net.ipv4.ip_forward=0
      modprobe -r br_netfilter 2>/dev/null
      echo "KubeSolo's state, mounts and network are gone"
      exit 0
    '';
  };
}
