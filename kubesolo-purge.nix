# KubeSolo ran here from 2026-10-30 to 2026-11-02 and is gone from the configuration. Removing its
# module stops the unit, but NixOS deletes nothing outside the store, and KubeSolo's
# KillMode=process leaves the pods running. This unit clears what is left, once: the steps of
# the old docs/KUBESOLO.md, "Cleaning what is left" (in git history). It runs only while
# /var/lib/kubesolo exists, never fails, and is not a oneshot, so the switch does not wait for it
# (stopping the pods can take a while) and it cannot make deploy-rs roll a deploy back.
# Delete this file in a later PR, once `ls /var/lib/kubesolo` on the box says it is gone.
{ config, lib, pkgs, ... }:
{
  systemd.services.kubesolo-purge = {
    description = "Delete what KubeSolo left on the box";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/var/lib/kubesolo";
    path = with pkgs; [ coreutils util-linux iproute2 iptables nftables kmod procps config.systemd.package ];
    # `piabrota kubesolo-purge` (scala/scripts/Maintenance.scala) runs every step and always exits 0.
    script = lib.getExe ((pkgs.callPackage ./scala { }).command { name = "kubesolo-purge"; });
  };
}
