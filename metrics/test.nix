# checks.metrics: three VMs. `hub` has the collector, the page and the pull (piabrota2's roles),
# `edge` has the collector and the published location on the site's vhost (piabrota's roles),
# `client` is an address that is not in the allow list. TLS and ACME are off in the VM (there is
# no ACME server), so every request is plain HTTP, and the names are the node names, not
# metrics.piabrota.art and www.piabrota.art. Everything else is the real module: the units, their
# sandbox, nginx, the basic-auth file. Needs KVM to run in reasonable time.
{ pkgs, ... }:
{
  name = "metrics";

  nodes =
    let
      common = {
        imports = [ ../loco.nix ../metrics.nix ];
        networking.firewall.allowedTCPPorts = [ 80 ];
        environment.systemPackages = [ pkgs.jq pkgs.curl ];
      };
    in
    {
      hub = { lib, ... }: {
        imports = [ common ];
        piabrota.metrics = {
          name = "piabrota2";
          label = "piabrota2 (KVM 4)";
          collector = {
            enable = true;
            interval = 2;
          };
          web = {
            enable = true;
            domain = "hub";
            htpasswdFile = "/etc/metrics-test-htpasswd";
          };
          pull = {
            enable = true;
            url = "http://edge/_metrics/piabrota.json";
          };
        };
        services.nginx.virtualHosts.hub = {
          forceSSL = lib.mkForce false;
          enableACME = lib.mkForce false;
        };
        environment.systemPackages = [ pkgs.openssl ];
      };

      edge = { lib, nodes, ... }: {
        imports = [ common ../site.nix ];
        piabrota.metrics = {
          name = "piabrota";
          label = "piabrota (KVM 1)";
          collector = {
            enable = true;
            interval = 2;
          };
          publish = {
            enable = true;
            allowFrom = [ nodes.hub.networking.primaryIPAddress ];
          };
        };
        # The site, with a stand-in page in place of the Gleam build, on the name `edge`.
        piabrota.site = {
          enable = true;
          domain = "edge";
          redirectFrom = [ ];
          skills = null;
          figures = null;
          hermes = null;
          root = pkgs.runCommand "site-stand-in" { } ''
            mkdir $out
            echo the-site-home > $out/index.html
          '';
        };
        services.nginx.virtualHosts.edge = {
          addSSL = lib.mkForce false;
          enableACME = lib.mkForce false;
        };
      };

      client = {
        environment.systemPackages = [ pkgs.curl pkgs.jq ];
      };
    };

  testScript = ''
    import json

    start_all()
    hub.wait_for_unit("nginx.service")
    edge.wait_for_unit("nginx.service")

    def code(node, cmd):
        return node.succeed(f"curl -s -o /dev/null -w '%{{http_code}}' {cmd}").strip()

    with subtest("The collector writes a valid, fresh file on both hosts"):
        for node, name in ((hub, "piabrota2"), (edge, "piabrota")):
            node.wait_until_succeeds(f"jq -e '.host == \"{name}\" and .v == 1' /run/metrics-web/{name}.json")
            node.succeed(f"jq -e '(now - .ts) < 20 and .vcpus >= 1 and .mem.total > 0 and .procs_total > 10 and (.top_mem | length) == 10' /run/metrics-web/{name}.json")
            node.succeed(f"jq -e '[.top_mem[].user] | index(\"root\")' /run/metrics-web/{name}.json")
            assert node.succeed(f"stat -c %a /run/metrics-web/{name}.json").strip() == "644"
            node.succeed("systemctl is-active metrics-collect.timer")
            node.fail("systemctl is-failed metrics-collect.service")

    with subtest("The collector's sandbox"):
        assert hub.succeed("systemctl show metrics-collect.service -p PrivateNetwork --value").strip() == "yes"
        hub.succeed("systemctl show metrics-collect.service -p MemoryMax --value | grep -qx 67108864")
        print(hub.succeed("systemd-analyze security metrics-collect.service --no-pager | tail -n 1"))
        print(hub.succeed("systemd-analyze security metrics-pull.service --no-pager | tail -n 1"))

    with subtest("The page needs the basic-auth login"):
        hub.succeed("echo \"metrics:$(openssl passwd -apr1 s3cret)\" > /etc/metrics-test-htpasswd && chmod 644 /etc/metrics-test-htpasswd")
        assert code(client, "http://hub/") == "401"
        assert code(client, "http://hub/data/piabrota2.json") == "401"
        assert code(client, "-u metrics:wrong http://hub/") == "401"
        assert code(client, "-u metrics:s3cret http://hub/") == "200"
        # No grep -q: it closes the pipe early and curl fails with exit code 23.
        client.succeed("curl -s -u metrics:s3cret http://hub/ | grep -c 'piabrota metrics'")
        client.succeed("curl -s -u metrics:s3cret http://hub/data/piabrota2.json | jq -e '.host == \"piabrota2\"'")
        client.succeed("curl -sI -u metrics:s3cret http://hub/data/piabrota2.json | grep -i '^cache-control: no-store'")
        client.succeed("curl -sI -u metrics:s3cret http://hub/data/piabrota2.json | grep -i '^x-frame-options: DENY'")

    with subtest("The state is not in the served folder"):
        hub.succeed("test -s /run/metrics-state/piabrota2.state")
        hub.fail("ls -A /run/metrics-web | grep -q state")
        assert code(client, "-u metrics:s3cret http://hub/data/piabrota2.state") == "404"

    with subtest("The hub pulls the edge's file"):
        hub.wait_until_succeeds("jq -e '.host == \"piabrota\"' /run/metrics-web/piabrota.json", timeout=60)
        client.succeed("curl -s -u metrics:s3cret http://hub/data/piabrota.json | jq -e '.label == \"piabrota (KVM 1)\"'")
        hub.fail("systemctl is-failed metrics-pull.service")

    with subtest("The edge serves its file to the hub's address only"):
        assert code(client, "http://edge/_metrics/piabrota.json") == "403"
        assert code(hub, "http://edge/_metrics/piabrota.json") == "200"
        assert code(edge, "http://edge/_metrics/piabrota.json") == "403"
        assert code(client, "http://edge/_metrics/piabrota2.json") == "404"

    with subtest("The site's other paths are the same"):
        assert client.succeed("curl -s http://edge/").strip() == "the-site-home"
        assert code(client, "http://edge/nixos") == "302"
        assert code(client, "http://edge/nothing-here") == "404"

    with subtest("A stopped edge collector leaves the pulled file as it was"):
        edge.succeed("systemctl stop metrics-collect.timer")
        # is-active fails while a oneshot is "activating", so ask for the state itself.
        edge.wait_until_succeeds("systemctl show metrics-collect.service -p ActiveState --value | grep -qx inactive")
        hub.succeed("systemctl is-active metrics-pull.timer")
        # The hub's copy may lag the edge's file by a pull or two (a VM is slow): wait until it
        # has caught up with the last file the edge wrote, then watch it stay.
        last = json.loads(edge.succeed("cat /run/metrics-web/piabrota.json"))["ts"]
        hub.wait_until_succeeds(f"jq -e '.ts == {last}' /run/metrics-web/piabrota.json", timeout=120)
        before = last
        mine_before = json.loads(hub.succeed("cat /run/metrics-web/piabrota2.json"))["ts"]
        hub.sleep(10)
        after = json.loads(hub.succeed("cat /run/metrics-web/piabrota.json"))["ts"]
        mine_after = json.loads(hub.succeed("cat /run/metrics-web/piabrota2.json"))["ts"]
        assert before == after, (before, after)
        assert mine_after > mine_before, (mine_before, mine_after)
        assert client.succeed("curl -s -u metrics:s3cret http://hub/data/piabrota.json | jq .ts").strip() == str(after)

    with subtest("A failed pull keeps the old file and the unit does not fail"):
        edge.succeed("systemctl stop nginx.service")
        hub.sleep(6)
        hub.succeed("jq -e '.host == \"piabrota\"' /run/metrics-web/piabrota.json")
        hub.fail("systemctl is-failed metrics-pull.service")
  '';
}
