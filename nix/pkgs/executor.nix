# Shared by the desktop CLI and the executor LXC on mendbox.
#
# Executor's Bun executable must remain unpatched: its program is appended
# to the binary. nix-ld supplies the libraries expected by upstream.
{ lib, stdenvNoCC, fetchurl }:

stdenvNoCC.mkDerivation {
  pname = "executor";
  version = "1.6.10";
  src = fetchurl {
    url = "https://registry.npmjs.org/executor/-/executor-1.6.10-linux-x64.tgz";
    hash = "sha256-hdRGpka6/MUlpyEnoJhwoI96Y4P9f8Gge1+yHw/JYzU=";
  };
  sourceRoot = "package";
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/lib/executor"
    cp -R bin/. "$out/lib/executor/"
    ln -s ../lib/executor/executor "$out/bin/executor"
    runHook postInstall
  '';
  meta = {
    description = "Local integration gateway for AI agents";
    homepage = "https://executor.sh";
    license = lib.licenses.mit;
    mainProgram = "executor";
    platforms = [ "x86_64-linux" ];
  };
}
