# Hermes on KVM 1: what ../../hermes.nix leaves at upstream's defaults, cut for one vCPU and 4 GB.
# Without this file a host runs the full Hermes (hosts/kvm4).
{ lib, hermes-agent, ... }:
{
  services.hermes-agent = {
    # The smallest build. The extras the box uses (Anthropic, the chat platforms, MCP, ddgs) are
    # extraDependencyGroups in hermes.nix. `full` adds about 700 MB more (voice, Bedrock, Modal and
    # the like).
    package = hermes-agent.packages.x86_64-linux.minimal;
    # Two subagents at a time (upstream: 10).
    settings.delegation.max_concurrent_children = 2;
    # Memory, for 1 vCPU and 1 GB: fewer cached agents (upstream: 128), one cron job at a time
    # (upstream: no limit), one code kernel (upstream: 4), and media read into RAM capped at 20 MiB
    # (upstream: 128 MiB).
    settings.agent.agent_cache.max_size = 16;
    settings.cron.max_parallel_jobs = 1;
    settings.code_execution.max_session_kernels = 1;
    settings.gateway.max_inbound_media_bytes = 20 * 1024 * 1024;
    # Discord attachments are held in RAM while they download: the same 20 MiB cap as Telegram's
    # media, not Discord's 32 MiB.
    environment.DISCORD_MAX_ATTACHMENT_BYTES = toString (20 * 1024 * 1024);
  };

  # The box has one vCPU and 4 GB: Hermes gets at most a quarter of the memory and yields the CPU
  # to sshd, nginx and the apps. omp runs in this cgroup too; its wrapper (hermes.nix) makes the
  # OOM killer pick omp before the gateway.
  systemd.services.hermes-agent.serviceConfig = {
    MemoryMax = lib.mkDefault "1G";
    CPUWeight = lib.mkDefault 50;
  };
}
