# A certificate order that fails (the name does not point here yet) leaves NixOS's self-signed
# stand-in in place, and the module orders again only on the next daily timer: on 2026-11-09 proof
# and skills showed a browser warning for a day after their DNS was fixed. So a failed order is
# started again 20 minutes later, at most 9 times in 6 hours: 3 failed validations an hour for a
# name, under Let's Encrypt's limit of 5. After that the daily timer takes over again.
# scripts/cert_check.py and certs.yml watch the result from outside (docs/SITE.md, "Certificates").
#
# Not the module's own Restart=on-failure (every 15 minutes, no limit): a unit that waits in auto-restart counts as failed in every
# switch-to-configuration (it resets "failed", not "auto-restart"), so a deploy in the 6-hour window
# rolled back the whole host (kvm4, 2026-11-13). OnFailure leaves the unit failed, which the switch
# resets, and a transient timer starts it again. With no certificate it adds nothing.
{ config, lib, pkgs, ... }:
let
  certs = builtins.attrNames config.security.acme.certs;
  systemd = config.systemd.package;
  # `piabrota acme-retry NAME` (scala/scripts/Maintenance.scala): past StartLimitBurst the start is
  # refused, so it leaves the name to its daily timer.
  retry = lib.getExe ((pkgs.callPackage ./scala { }).command {
    name = "acme-retry";
    runtimeInputs = [ systemd ];
    exclusivePath = true;
  });
in
{
  systemd.services = lib.mkMerge [
    (lib.listToAttrs (map
      (name: lib.nameValuePair "acme-order-renew-${name}" {
        onFailure = [ "acme-retry@${name}.service" ];
        serviceConfig.Restart = lib.mkForce "no";
        # A deploy that changes the unit must not run an order inside the switch: a failed order
        # there rolls the host back too. acme-<name>.service still starts one when the config moves.
        restartIfChanged = false;
        unitConfig = {
          StartLimitIntervalSec = "6h";
          StartLimitBurst = 9;
        };
      })
      certs))
    (lib.mkIf (certs != [ ]) {
      "acme-retry@" = {
        description = "Order the ACME certificate %i again in 20 minutes";
        # "-": this unit must never end failed either, for the same reason.
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "-${retry} %i";
        };
      };
    })
  ];
}
