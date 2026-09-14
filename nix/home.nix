{
  pkgs,
  inputs,
  lib,
  ...
}:

{
  # Home Manager entrypoint. Keep long package lists in imported modules so this
  # file only explains the shape of the user environment.
  imports = [
    ./modules/dots.nix
    ./modules/dev/base.nix
    ./modules/dev/ai
    ./modules/apps/gui.nix
    ./modules/media
    ./modules/gaming
    ./modules/ides
    ./modules/clis
    ./modules/terminals.nix
    ./modules/des
    ./modules/browsers
  ];

  # Fresh install (Aug 2026, tracking unstable between 26.05 and 26.11).
  home.stateVersion = "26.05";
  home.sessionPath = [ "$HOME/.local/bin" ];

  # SSH is account identity, not an app package, so it stays at the home root.
  programs.ssh = {
    enable = true;
    extraConfig = ''
      Include ~/.config/sealant/ssh_config
    '';
    enableDefaultConfig = false;
    matchBlocks = {
      "*" = {
        addKeysToAgent = "yes";
        hashKnownHosts = true;
      };
      github = {
        hostname = "github.com";
        user = "git";
        identitiesOnly = true;
        identityFile = "~/.ssh/id_ed25519";
      };
      "sbx-*" = {
        hostname = "localhost";
        port = 2222;
        identitiesOnly = true;
        identityFile = "~/.ssh/id_ed25519_github";
      };
      personal_macbook = {
        hostname = "Yianniss-MacBook-Pro.local";
        user = "yiannis";
        identitiesOnly = true;
        identityFile = "~/.ssh/id_ed25519";
      };
    };
  };

  # ~/.ssh/config must be a real file owned by the user, not a symlink into the
  # Nix store. Tools that run inside a bubblewrap user namespace (FHS-wrapped
  # binaries such as `gt`, sandboxes) see store files as owned by `nobody`, and
  # OpenSSH then refuses the config with "Bad owner or permissions". Home
  # Manager links the generated file first; this step replaces the link with a
  # private copy. `force` lets the next generation overwrite that copy again.
  home.file.".ssh/config".force = true;
  home.activation.materializeSshConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ -L "$HOME/.ssh/config" ]; then
      target="$(readlink -f "$HOME/.ssh/config")"
      run rm -f "$HOME/.ssh/config"
      run cp "$target" "$HOME/.ssh/config"
      run chmod 600 "$HOME/.ssh/config"
    fi
  '';
}
