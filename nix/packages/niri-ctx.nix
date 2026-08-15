{
  lib,
  rustPlatform,
  src,
  bashFallback,
}:

rustPlatform.buildRustPackage {
  pname = "niri-ctx";
  version = "0.1.0";

  src = lib.cleanSource src;

  patches = [ ./niri-ctx-current-exe.patch ];

  cargoLock.lockFile = src + "/Cargo.lock";

  postInstall = ''
    install -Dm755 ${bashFallback} \
      $out/libexec/niri-ctx/bash-fallback
  '';

  meta = {
    description = "Yiannis' Niri workspace and session dispatcher";
    license = lib.licenses.gpl3Plus;
    mainProgram = "niri-ctx";
    platforms = lib.platforms.linux;
  };
}
