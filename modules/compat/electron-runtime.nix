{ pkgs, ... }:

{
  # Native Electron binaries from nixpkgs are useful for quick testing external
  # Electron app behavior against the same runtime compatibility layer below.
  environment.systemPackages = with pkgs; [
    electron
  ];

  programs.nix-ld = {
    enable = true;

    # Runtime libs for Electron binaries distributed outside nixpkgs, for
    # example `node_modules/.pnpm/electron/.../dist/electron`. ffmpeg here is a
    # library/runtime dependency, not the user-facing `ffmpeg-full` CLI.
    libraries = with pkgs; [
      stdenv.cc.cc
      zlib
      glib
      nss
      nspr
      dbus
      expat
      gtk3
      gdk-pixbuf
      cairo
      pango
      atk
      at-spi2-atk
      at-spi2-core
      libdrm
      libgbm
      mesa
      libglvnd
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      xorg.libXcursor
      xorg.libXi
      xorg.libXrender
      xorg.libXScrnSaver
      xorg.libxshmfence
      xorg.libXtst
      xorg.libxcb
      xorg.libxkbfile
      libxkbcommon
      wayland
      alsa-lib
      cups
      libsecret
      libnotify
      libappindicator-gtk3
      pipewire
      fontconfig
      freetype
      harfbuzz
      ffmpeg
    ];
  };
}
