# checks.pgx: a VM with pgx.nix on, as the VPS would run it (the same unit and sandbox). It
# creates a database with the admin's `pgx`, connects over TCP with the generated password,
# restarts the unit and finds the row again. A build of the system cannot show that a unit
# starts; this does.
{
  name = "pgx";

  nodes.machine = { pkgs, ... }: {
    imports = [ ../kubesolo.nix ../pgx.nix ];
    piabrota.pgx.enable = true;
    environment.systemPackages = [ pkgs.postgresql_18 ];
    virtualisation.memorySize = 1024;
  };

  testScript = ''
    machine.wait_for_unit("pgx.service")
    machine.wait_for_open_port(5432)

    machine.succeed("pgx create ax")
    url = machine.succeed("pgx url ax").strip().splitlines()[-1]
    assert url.startswith("postgres://postgres:"), url

    def sql(q):
        return machine.succeed(f"psql '{url}' -Atc \"{q}\"").strip()

    assert sql("SHOW fsync") == "on"
    sql("CREATE TABLE t (x int); INSERT INTO t VALUES (42)")

    # Without the password, TCP is refused (-w: fail instead of asking for it).
    machine.fail("psql -w 'postgres://postgres@127.0.0.1:5432/ax' -c 'SELECT 1'")

    machine.systemctl("restart pgx.service")
    machine.wait_for_unit("pgx.service")
    machine.wait_for_open_port(5432)
    assert sql("SELECT x FROM t") == "42"

    # The engine's memory watchdog sees the unit's MemoryMax.
    machine.succeed("journalctl -u pgx.service | grep 'memory watchdog: armed: limit=256 MB'")
  '';
}
