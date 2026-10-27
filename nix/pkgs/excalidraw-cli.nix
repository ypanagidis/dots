# Official Excalidraw CLI (`excalidraw`). The npm tarball ships a prebuilt
# bundle whose only runtime dependency is playwright-core, used for PNG
# rendering against an already-installed browser.
{ lib, stdenvNoCC, fetchurl, makeWrapper, nodejs, chromium }:

let
  playwrightCore = fetchurl {
    url = "https://registry.npmjs.org/playwright-core/-/playwright-core-1.63.0.tgz";
    hash = "sha512-rYCsBF/M5HjUch52bbtVONEFjv6Xu8sm8h72dNlR5bzIE1fvC/bxgspzkjSfU+MweEMmPM8KJebG6nnyxo5mCg==";
  };
in
stdenvNoCC.mkDerivation {
  pname = "excalidraw-cli";
  version = "0.2.0";
  src = fetchurl {
    url = "https://registry.npmjs.org/@excalidraw/cli/-/cli-0.2.0.tgz";
    hash = "sha512-Qk1pQt8FMcbW//6XbhOvPSJVngE5NwgmHIb8X++m7ONwfHc01ortmWemDrBAMyolS1amGESmGbNBOK3hVb9otA==";
  };
  sourceRoot = "package";
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    pkg="$out/lib/node_modules/@excalidraw/cli"
    mkdir -p "$pkg/node_modules/playwright-core" "$out/bin"
    cp -R . "$pkg/"
    tar xzf ${playwrightCore} --strip-components=1 -C "$pkg/node_modules/playwright-core"
    # `excalidraw update` cannot modify the read-only store; bump it here instead.
    makeWrapper ${lib.getExe nodejs} "$out/bin/excalidraw" \
      --add-flags "$pkg/dist/main.js" \
      --set EXCALIDRAW_NO_UPDATE_NOTIFIER 1 \
      --set-default EXCALIDRAW_BROWSER_PATH ${lib.getExe chromium}
    runHook postInstall
  '';
  meta = {
    description = "Official Excalidraw CLI for humans and agents";
    homepage = "https://github.com/excalidraw/cli";
    license = lib.licenses.mit;
    mainProgram = "excalidraw";
  };
}
