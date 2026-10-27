# Executor integration gateway: unprivileged NixOS LXC (CT 170) on mendbox.
#
# Executor listens on loopback only; `tailscale serve` is the single way in,
# at https://executor.tailc79e49.ts.net. The tailnet policy admits only
# autogroup:member and tag:mend, and Executor's bearer token gates every
# request on top of that. Management is Tailscale SSH; `pct enter 170` on
# mendbox is the fallback when the tailnet is down.
#
# Build the bootstrap image:  nix build .#nixosConfigurations.executor.config.system.build.tarball
# Deploy changes:             nixos-rebuild switch --flake .#executor --target-host root@executor
{
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  executor = pkgs.callPackage ../../pkgs/executor.nix { };
  port = 4788;
  origin = "https://executor.tailc79e49.ts.net";
in
{
  imports = [ "${modulesPath}/virtualisation/proxmox-lxc.nix" ];

  networking.hostName = "executor";
  proxmoxLXC.manageHostName = true;

  # Executor's unpatched Bun binary and its native addons need a stock loader.
  programs.nix-ld.enable = true;

  services.openssh.enable = lib.mkForce false;
  services.resolved.settings.Resolve.LLMNR = "false";

  # Proxmox owns the address and resolvers, so MagicDNS stays off here.
  services.tailscale = {
    enable = true;
    authKeyFile = "/var/lib/tailscale/authkey";
    extraUpFlags = [
      "--hostname=executor"
      "--advertise-tags=tag:executor"
      "--ssh"
      "--accept-dns=false"
    ];
  };

  # Tailscale SSH and serve answer on the tailnet interface; nothing else is
  # reachable, and Executor itself is bound to loopback.
  networking.firewall = {
    enable = true;
    interfaces.tailscale0.allowedTCPPorts = [
      22
      443
    ];
  };

  users.users.executor = {
    isSystemUser = true;
    group = "executor";
    home = "/var/lib/executor";
  };
  users.groups.executor = { };

  environment.systemPackages = [ executor ];

  # The bearer token is generated on first start and kept in
  # /var/lib/executor/.executor/server-control/auth.json.
  systemd.services.executor = {
    description = "Executor integration gateway";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      HOME = "/var/lib/executor";
      DO_NOT_TRACK = "1";
      EXECUTOR_DISABLE_ANALYTICS = "1";
      EXECUTOR_DISABLE_UPDATE_CHECK = "1";
    };
    serviceConfig = {
      ExecStart = lib.escapeShellArgs [
        (lib.getExe executor)
        "daemon"
        "run"
        "--foreground"
        "--hostname"
        "127.0.0.1"
        "--port"
        (toString port)
        "--allowed-host"
        origin
      ];
      User = "executor";
      Group = "executor";
      StateDirectory = "executor";
      StateDirectoryMode = "0700";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 2;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };

  # Serve config persists in tailscaled's state; reapplying it is idempotent.
  systemd.services.tailscale-serve-executor = {
    description = "Expose Executor on the tailnet over HTTPS";
    wantedBy = [ "multi-user.target" ];
    after = [
      "tailscaled-autoconnect.service"
      "executor.service"
    ];
    wants = [ "tailscaled-autoconnect.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = "${lib.getExe pkgs.tailscale} serve --bg --https=443 http://127.0.0.1:${toString port}";
  };

  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  time.timeZone = "UTC";
  system.stateVersion = "26.05";
}
