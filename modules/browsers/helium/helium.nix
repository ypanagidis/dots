{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  patchelf,
  bintools,
  appimageTools,

  # Linked dynamic libraries (matching google-chrome dependencies)
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  fontconfig,
  freetype,
  gcc-unwrapped,
  gdk-pixbuf,
  glib,
  gtk3,
  gtk4,
  libdrm,
  libglvnd,
  libkrb5,
  libX11,
  libxcb,
  libXcomposite,
  libXcursor,
  libXdamage,
  libXext,
  libXfixes,
  libXi,
  libxkbcommon,
  libXrandr,
  libXrender,
  libXScrnSaver,
  libxshmfence,
  libXtst,
  libgbm,
  nspr,
  nss,
  pango,
  pipewire,
  vulkan-loader,
  wayland,

  # Command line programs
  coreutils,

  # Will crash without
  systemd,

  # Loaded at runtime
  libexif,
  pciutils,

  # Additional dependencies
  curl,
  liberation_ttf,
  util-linux,
  wget,
  xdg-utils,
  flac,
  harfbuzz,
  icu,
  libopus,
  libpng,
  snappy,
  speechd-minimal,
  bzip2,
  libcap,

  # Audio
  libpulseaudio,

  # Icons/themes
  adwaita-icon-theme,
  gsettings-desktop-schemas,

  # VA-API for video acceleration
  libva,

  # Vulkan
  addDriverRunpath,

  # QT support
  qt6,
}:

let
  pname = "helium";
  version = "0.12.3.1";

  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
    hash = "sha256-VnOhzhAulvFNBB/0AD1d+K/TzfFL9Zwtk/vcm5vWl+I=";
  };

  # Extract AppImage contents using appimageTools
  appimageContents = appimageTools.extractType2 { inherit pname version src; };

  opusWithCustomModes = libopus.override { withCustomModes = true; };

  deps = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    bzip2
    cairo
    coreutils
    cups
    curl
    dbus
    expat
    flac
    fontconfig
    freetype
    gcc-unwrapped.lib
    gdk-pixbuf
    glib
    harfbuzz
    icu
    libcap
    libdrm
    liberation_ttf
    libexif
    libglvnd
    libkrb5
    libpng
    libX11
    libxcb
    libXcomposite
    libXcursor
    libXdamage
    libXext
    libXfixes
    libXi
    libxkbcommon
    libXrandr
    libXrender
    libXScrnSaver
    libxshmfence
    libXtst
    libgbm
    nspr
    nss
    opusWithCustomModes
    pango
    pciutils
    pipewire
    snappy
    speechd-minimal
    systemd
    util-linux
    vulkan-loader
    wayland
    wget
    libpulseaudio
    libva
    gtk3
    gtk4
    qt6.qtbase
    qt6.qtwayland
  ];

  rpath = lib.makeLibraryPath deps + ":" + lib.makeSearchPathOutput "lib" "lib64" deps;
  binpath = lib.makeBinPath deps;

  # Chromium flags for Wayland/PipeWire support
  chromiumFlags = lib.concatStringsSep " " [
    "--disable-features=WaylandWpColorManagerV1"
    "--enable-features=WebRTCPipeWireCapturer"
  ];

in
stdenvNoCC.mkDerivation {
  inherit pname version;

  # No src needed - we use pre-extracted appimageContents
  dontUnpack = true;

  nativeBuildInputs = [
    makeWrapper
    patchelf
  ];

  buildInputs = [
    adwaita-icon-theme
    glib
    gtk3
    gtk4
    gsettings-desktop-schemas
  ];

  installPhase = ''
    runHook preInstall

    # Copy extracted AppImage contents
    mkdir -p $out/share/helium
    cp -r ${appimageContents}/opt/helium/* $out/share/helium/
    # Make files writable so we can patch them
    chmod -R u+w $out/share/helium

    # Copy desktop file and icons
    mkdir -p $out/share/applications
    mkdir -p $out/share/icons/hicolor/256x256/apps

    cp ${appimageContents}/helium.desktop $out/share/applications/
    chmod u+w $out/share/applications/helium.desktop
    cp $out/share/helium/product_logo_256.png $out/share/icons/hicolor/256x256/apps/helium.png

    # Copy locales if they exist in usr/share
    if [ -d ${appimageContents}/usr/share ]; then
      cp -r ${appimageContents}/usr/share/* $out/share/ 2>/dev/null || true
    fi

    # Replace bundled vulkan-loader with system one
    rm -f $out/share/helium/libvulkan.so.1
    ln -s "${lib.getLib vulkan-loader}/lib/libvulkan.so.1" "$out/share/helium/libvulkan.so.1"

    # Patch ELF binaries with correct rpath and interpreter
    # Note: binary names changed from chrome/chrome_crashpad_handler to helium/helium_crashpad_handler in 0.8.3.x
    for elf in $out/share/helium/{helium,helium_crashpad_handler,chromedriver,chrome,chrome_crashpad_handler}; do
      if [ -f "$elf" ]; then
        patchelf --set-rpath "${rpath}" "$elf"
        patchelf --set-interpreter "${bintools.dynamicLinker}" "$elf"
      fi
    done

    # Patch the GL/EGL libraries too
    for solib in $out/share/helium/lib*.so*; do
      if [ -f "$solib" ] && [ ! -L "$solib" ]; then
        patchelf --set-rpath "${rpath}" "$solib" 2>/dev/null || true
      fi
    done

    # Update desktop file
    substituteInPlace $out/share/applications/helium.desktop \
      --replace-fail 'Exec=helium' "Exec=$out/bin/helium" \
      --replace-fail 'Icon=helium' "Icon=$out/share/icons/hicolor/256x256/apps/helium.png"

    # Create wrapper script
    # Note: main binary changed from 'chrome' to 'helium' in 0.8.3.x
    mkdir -p $out/bin
    mainBinary="$out/share/helium/helium"
    if [ ! -f "$mainBinary" ]; then
      mainBinary="$out/share/helium/chrome"
    fi
    makeWrapper "$mainBinary" "$out/bin/helium" \
      --prefix QT_PLUGIN_PATH : "${qt6.qtbase}/lib/qt-6/plugins" \
      --prefix QT_PLUGIN_PATH : "${qt6.qtwayland}/lib/qt-6/plugins" \
      --prefix NIXPKGS_QT6_QML_IMPORT_PATH : "${qt6.qtwayland}/lib/qt-6/qml" \
      --prefix LD_LIBRARY_PATH : "${rpath}" \
      --prefix PATH : "${binpath}" \
      --suffix PATH : "${lib.makeBinPath [ xdg-utils ]}" \
      --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH:${addDriverRunpath.driverLink}/share" \
      --set CHROME_WRAPPER "helium" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --add-flags "${chromiumFlags}"

    runHook postInstall
  '';

  meta = {
    description = "Private, fast, and honest web browser based on Chromium";
    homepage = "https://github.com/imputnet/helium";
    changelog = "https://github.com/imputnet/helium-linux/releases/tag/${version}";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.gpl3;
    mainProgram = "helium";
  };
}
