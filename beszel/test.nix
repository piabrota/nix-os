# checks.metrics: one VM with metrics.nix on, hub and agent both. nginx proxies the hub (TLS is off
# in the VM: there is no ACME). The agent dials the hub through nginx's name, as piabrota's agent
# does, so the WebSocket upgrade and the token path are exercised. Shaped after nixpkgs'
# nixos/tests/beszel.nix, with the agent in its WebSocket mode (HUB_URL) and a universal token.
{
  name = "metrics";

  nodes.machine = { lib, pkgs, ... }: {
    imports = [ ../loco.nix ../metrics.nix ];
    piabrota.metrics = {
      hub = {
        enable = true;
        domain = "metrics.test";
      };
      agent = {
        enable = true;
        hubUrl = "http://metrics.test";
      };
    };
    networking.hosts."127.0.0.1" = [ "metrics.test" ];
    services.nginx.virtualHosts."metrics.test" = {
      forceSSL = lib.mkForce false;
      enableACME = lib.mkForce false;
    };
    environment.systemPackages = [ pkgs.jq ];
    virtualisation.memorySize = 1024;
  };

  testScript = ''
    import json

    hub = "http://metrics.test"
    machine.wait_for_unit("beszel-hub.service")
    machine.wait_for_unit("nginx.service")
    machine.wait_until_succeeds(f"curl -fs {hub}/api/health")

    with subtest("Without the environment file the agent is skipped, not failed"):
        machine.fail("systemctl is-failed beszel-agent.service")
        machine.succeed("systemctl show beszel-agent.service -p ActiveState --value | grep -qx inactive")

    with subtest("The first user, once; a second try is refused"):
        creds = json.dumps({"email": "admin@example.com", "password": "password123"})
        machine.succeed(f"curl -f --json '{creds}' {hub}/api/beszel/create-user")
        machine.fail(f"curl -f --json '{creds}' {hub}/api/beszel/create-user")
        login = json.dumps({"identity": "admin@example.com", "password": "password123"})
        user = json.loads(machine.succeed(f"curl -f --json '{login}' {hub}/api/collections/users/auth-with-password"))
        auth = f"Authorization: {user['token']}"

    with subtest("Nobody can register a user through the API"):
        other = json.dumps({"email": "x@example.com", "password": "password123", "passwordConfirm": "password123"})
        machine.fail(f"curl -f --json '{other}' {hub}/api/collections/users/records")

    with subtest("nginx limits login attempts"):
        bad = json.dumps({"identity": "admin@example.com", "password": "wrong-password"})
        codes = [machine.succeed(f"curl -s -o /dev/null -w '%{{http_code}}' --json '{bad}' {hub}/api/collections/users/auth-with-password") for _ in range(20)]
        assert "429" in codes, codes

    with subtest("Write the agent's environment file and start the agent"):
        key = machine.succeed(f"curl -f -H '{auth}' {hub}/api/beszel/getkey | jq -r .key").strip()
        token = machine.succeed(f"curl -f -H '{auth}' {hub}/api/beszel/universal-token | jq -r .token").strip()
        # The hub accepts a universal token only after it is switched on (internal/hub/api.go).
        machine.succeed(f"curl -f -H '{auth}' '{hub}/api/beszel/universal-token?token={token}&enable=1'")
        machine.succeed(f"install -m 0600 /dev/null /var/lib/beszel-secrets/agent.env && printf 'KEY=%s\\nTOKEN=%s\\n' '{key}' '{token}' > /var/lib/beszel-secrets/agent.env")
        machine.succeed("systemctl start beszel-agent.service")
        machine.wait_for_unit("beszel-agent.service")

    with subtest("The agent reaches the hub over the WebSocket"):
        machine.wait_until_succeeds(f"curl -f -H '{auth}' {hub}/api/collections/systems/records | jq -e '.items[0].status == \"up\"'")

    with subtest("The agent binds no port"):
        machine.fail("ss -tlnp | grep 45876")

    with subtest("The agent sees systemd units through D-Bus under PrivateUsers"):
        machine.succeed("systemctl show beszel-agent.service -p PrivateUsers --value | grep -qx yes")
        machine.wait_until_succeeds(f"curl -f -H '{auth}' '{hub}/api/collections/systemd_services/records?perPage=200' | jq -e '[.items[].name] | index(\"beszel-hub\")'", timeout=700)
  '';
}
