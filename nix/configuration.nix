{ lib, pkgs, ... }:

{
  # Keep this file as the host entrypoint. Package lists live in focused modules
  # so it is obvious whether something is system infrastructure or userland.
  imports = [
    ./hardware-configuration.nix
    ./system/mt7927-bluetooth.nix
    ./system/lianli-fans.nix

    # System building blocks.
    ./modules/system/base-packages.nix
    ./modules/system/desktop-kde.nix
    ./modules/system/desktop-niri.nix
    ./modules/system/1password.nix
    ./modules/system/virtualisation.nix
    ./modules/system/gpu.nix

    # Compatibility/runtime glue for external binaries.
    ./modules/compat/electron-runtime.nix

    # Focused system modules that also declare their own helper packages.
    ./modules/minecraft.nix
    ./modules/steam.nix
    ./modules/kdeconnect.nix
    ./modules/sunshine.nix
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Upstream caches for packages consumed from these flake inputs.
    extra-substituters = [
      "https://cache.numtide.com"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
  nixpkgs.config.allowUnfree = true;

  # Boot stays host-level because it directly describes this machine.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 20;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_6_18;

  boot.kernelModules = [
    "k10temp"
    "asus_ec_sensors"
    # Wispr Flow injects transcribed text through a virtual keyboard.
    "uinput"
  ];

  services.udev.packages = [ pkgs.wispr-flow ];

  boot.kernelParams = [
    # Prefer ACPI S3 suspend-to-RAM over the shallower s2idle mode.
    "mem_sleep_default=deep"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
  ];

  # Swap lives in compressed RAM like the old CachyOS setup; no swap partition.
  zramSwap.enable = true;

  networking.hostName = "nix-pc";
  networking.extraHosts = ''
    10.102.121.122 synchat.internal synchatapi.internal
  '';
  networking.networkmanager.enable = true;
  networking.firewall.allowedTCPPorts = [
    # Local dev / agent web UIs.
    4096
    4000
    3000
    # mend
    3105
  ];

  # Tailscale: private network to the Hetzner box (`main`) and the other devices.
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # Accept SSH over trusted interfaces. `tailscale0` is trusted below, while
  # port 22 stays closed on the public and LAN firewall. Password login remains
  # available until the client key has been copied over.
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "yiannis" ];
    };
  };

  # Tailscale has no official Linux GUI; Trayscale is the usual GTK tray app.
  environment.systemPackages = [ pkgs.trayscale ];
  networking.firewall.trustedInterfaces = [ "virbr0" "tailscale0" ];

  time.timeZone = "Europe/Athens";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users.yiannis = {
    isNormalUser = true;
    description = "Yiannis Panagidis";
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
      "libvirtd"
      "kvm"
      "nordvpn"
      # Fallback when logind does not grant the udev uaccess ACL.
      "input"
    ];
  };

  # Needed because the user's login shell is zsh.
  programs.zsh.enable = true;

  services.printing.enable = true;

  # Keep Syncthing declared as disabled so it cannot come back on boot through
  # an old config fragment. Obsidian Sync is the current notes sync path.
  services.syncthing.enable = false;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # Uses the nixpkgs services.nordvpn module (upstreamed since 25.11; the old
  # nordvpn-flake module is gone). CLI access is via the nordvpn group on the
  # user. Keep the daemon available so the CLI can connect on demand.
  services.nordvpn.enable = true;
  # Don't launch the Nord tray/notifier at login; the daemon stays up so
  # `nordvpn connect` still works on demand.
  systemd.user.services.norduserd.wantedBy = lib.mkForce [ ];

  services.hardware.openrgb.enable = true;
  programs.coolercontrol.enable = true;

  environment.sessionVariables = {
    _JAVA_AWT_WM_NONREPARENTING = "1";
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
  };

  # Fresh install (Aug 2026, tracking unstable between 26.05 and 26.11).
  system.stateVersion = "26.05";
}
