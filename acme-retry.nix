# A certificate order that fails (the name does not point here yet) leaves NixOS's self-signed
# stand-in in place, and the module orders again only on the next daily timer: on 2026-11-09 proof
# and skills showed a browser warning for a day after their DNS was fixed. The module sets
# RestartSec but no Restart. Retry every 20 minutes, at most 9 times in 6 hours: 3 failed
# validations an hour for a name, under Let's Encrypt's limit of 5. After that the daily timer
# takes over again. scripts/cert_check.py and certs.yml watch the result from outside
# (docs/SITE.md, "Certificates"). With no certificate it adds nothing.
{ config, lib, ... }:
{
  systemd.services = lib.mapAttrs'
    (name: _: lib.nameValuePair "acme-order-renew-${name}" {
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = lib.mkForce "20min";
      };
      unitConfig = {
        StartLimitIntervalSec = "6h";
        StartLimitBurst = 9;
      };
    })
    config.security.acme.certs;
}
