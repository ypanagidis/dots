{ pkgs, ... }:

{
  # Small system-level tools that are useful before Home Manager is available,
  # inside root shells, or from services/scripts running outside the user env.
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    unzip
    zip
    jq
    ripgrep
    fd
    htop
    nil
    man-pages
    man-pages-posix

    # Hardware and system inspection tools belong system-wide because they are
    # often used while debugging boot, drivers, USB, PCI, storage, and audio.
    usbutils
    pciutils
    alsa-utils
    pulseaudio
    lm_sensors
    smartmontools
    nvme-cli
    sysstat

    # Compatibility/runtime libraries that were previously global. Keep them in
    # one clearly named system list until we verify which ones are still needed.
    stdenv.cc.cc.lib
    fuse3
    icu
    zlib
    nss
    openssl
    expat
    libnotify

    # RDP tooling is low-level enough to keep available outside the HM profile.
    freerdp
    (pkgs.runCommand "xfreerdp3-compat" { } ''
      mkdir -p $out/bin
      ln -s ${pkgs.freerdp}/bin/xfreerdp $out/bin/xfreerdp3
    '')

    # Device control tools for this desktop's cooling/RGB hardware.
    liquidctl
    openrgb
  ];
}
