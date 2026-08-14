{
  pkgs ? import <nixpkgs> { },
}:

pkgs.appimageTools.wrapType2 {
  pname = "cursor";
  version = "latest";

  src = pkgs.fetchurl {
    url = "https://api2.cursor.sh/updates/download/golden/linux-x64/cursor/2.3";
    sha256 = "sha256-o/NIEtSOlUl67g18mWDG4M0thPA4VIfiWudv0Xiov08=";
  };

  extraPkgs =
    pkgs: with pkgs; [
      # Node so we can pin a binary to use more ram in lsp
      nodejs

      # Required for keymapping (fixes the error you saw)
      xorg.libxkbfile

      # Common libraries that Electron apps and extensions need
      libsecret
      libnotify
      libappindicator-gtk3
      curl
      glib
      nss
      nspr
      at-spi2-atk
      cups
      dbus
      libdrm
      gtk3
      pango
      cairo
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      mesa
      alsa-lib
    ];
}
