# Home Assistant: unprivileged NixOS LXC (CT 106) on the home Proxmox (proxmox.mine).
#
# Bridged onto the home LAN (vmbr0) with a DHCP lease (MAC bc:24:11:76:5b:f2)
# so discovery (mDNS, SSDP) sees the same network as the devices. The UI is
# plain HTTP on :8123, LAN only. Management is SSH as root with the desktop
# key; `pct enter 106` on proxmox.mine is the fallback.
#
# Integrations whose Python deps aren't in the closure fail to set up from the
# UI; add them to extraComponents and redeploy.
#
# Build the bootstrap image:  nix build .#nixosConfigurations.home-assistant.config.system.build.tarball
# Deploy changes:             nixos-rebuild switch --flake .#home-assistant --target-host root@192.168.1.33
{
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [ "${modulesPath}/virtualisation/proxmox-lxc.nix" ];

  networking.hostName = "home-assistant";
  proxmoxLXC.manageHostName = true;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPmAQyfvYbmlKrZ6b121CTn/ESV28EWxI1mVtYBY3Dtn"
  ];

  services.home-assistant = {
    enable = true;
    extraComponents = [
      # Onboarding: forecast, radio, TTS, and discovery-driven integrations.
      "default_config"
      "met"
      "radio_browser"
      "google_translate"
      "isal"
      "esphome"
      "unifi"
      "cast"
      "tplink"
      "matter"
    ];
    config = {
      default_config = { };
      homeassistant = {
        name = "Home";
        unit_system = "metric";
        time_zone = "Europe/Athens";
      };
      # Keep UI-made automations, scripts, and scenes editable.
      "automation ui" = "!include automations.yaml";
      "script ui" = "!include scripts.yaml";
      "scene ui" = "!include scenes.yaml";
    };
  };

  # Matter controller for the `matter` integration (ws://localhost:5580/ws).
  # Wi-Fi Matter devices are reached over link-local IPv6 on the LAN.
  services.matter-server = {
    enable = true;
    # A malformed DCL root cert makes the strict `cryptography` parser throw,
    # which kills startup before the websocket listens. Skip such certs.
    package = pkgs.python-matter-server.overridePythonAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace matter_server/server/helpers/paa_certificates.py \
          --replace-fail '        cert = x509.load_pem_x509_certificate(pem_certificate.encode())' \
        '        try:
                    cert = x509.load_pem_x509_certificate(pem_certificate.encode())
                except ValueError as err:
                    LOGGER.warning("Skipping unparsable PAA root cert %s: %s", subject, err)
                    return False'
      '';
    });
  };

  # Discovery replies (TP-Link broadcast, mDNS, SSDP) don't match conntrack,
  # so a stateful firewall drops them. The home LAN is the trust boundary.
  networking.firewall.enable = false;

  systemd.tmpfiles.rules = [
    "f /var/lib/hass/automations.yaml 0644 hass hass - []"
    "f /var/lib/hass/scripts.yaml 0644 hass hass"
    "f /var/lib/hass/scenes.yaml 0644 hass hass - []"
  ];

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

  time.timeZone = "Europe/Athens";
  system.stateVersion = "26.05";
}
