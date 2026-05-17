{ pkgs, ... }:

{
  # Keep this file as the host entrypoint. Package lists live in focused modules
  # so it is obvious whether something is system infrastructure or userland.
  imports = [
    ./hardware-configuration.nix
    ./system/mt7927-bluetooth.nix

    # System building blocks.
    ./modules/system/base-packages.nix
    ./modules/system/desktop-kde.nix
    ./modules/system/virtualisation.nix
    ./modules/system/gpu.nix

    # Compatibility/runtime glue for external binaries.
    ./modules/compat/electron-runtime.nix

    # Focused system modules that also declare their own helper packages.
    ./modules/minecraft.nix
    ./modules/steam.nix
    ./modules/crapple-display.nix
    ./modules/kdeconnect.nix
    ./modules/logitech.nix
    ./modules/sunshine.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  # Boot stays host-level because it directly describes this machine.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 20;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_6_18;

  boot.kernelModules = [
    "k10temp"
    "asus_ec_sensors"
  ];

  boot.kernelParams = [
    "mem_sleep_default=s2idle"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "pci=realloc=on,pcie_bus_perf,hpbussize=32"
  ];

  networking.hostName = "nix-pc";
  networking.networkmanager.enable = true;
  networking.firewall.trustedInterfaces = [ "virbr0" ];
  networking.firewall.allowedTCPPorts = [
    # Local dev / agent web UIs.
    4096
    4000
    3000
  ];

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

  services.nordvpn = {
    # Keep the daemon available so the CLI can connect on demand. Autoconnect is
    # managed by NordVPN's own settings, not by disabling the NixOS service.
    enable = true;
    users = [ "yiannis" ];
  };

  # Hardware toggles stay host-level because they describe devices attached to
  # this desktop, while their helper packages live in the relevant modules.
  hardware.apple-studio-display.enable = true;

  services.hardware.openrgb.enable = true;
  services.hardware.bolt.enable = true;
  programs.coolercontrol.enable = true;

  systemd.services.thunderbolt-rebind = {
    description = "Rebind Thunderbolt controller after resume";
    after = [ "post-resume.target" ];
    wantedBy = [ "post-resume.target" ];
    path = [ pkgs.pciutils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'dev=$(lspci -D | grep \"ASM4242 PCIe Switch Upstream\" | cut -d\" \" -f1); echo 1 > /sys/bus/pci/devices/$dev/remove; sleep 2; echo 1 > /sys/bus/pci/rescan'";
    };
  };

  environment.sessionVariables = {
    _JAVA_AWT_WM_NONREPARENTING = "1";
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
  };

  powerManagement.powerDownCommands = ''
    for dev in /sys/bus/pci/devices/*/power/wakeup; do
      echo disabled > "$dev" 2>/dev/null || true
    done
  '';

  system.stateVersion = "25.11";
}
