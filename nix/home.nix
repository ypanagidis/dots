{
  pkgs,
  inputs,
  ...
}:

{
  # Home Manager entrypoint. Keep long package lists in imported modules so this
  # file only explains the shape of the user environment.
  imports = [
    ./modules/dots.nix
    ./modules/dev/base.nix
    ./modules/dev/ai.nix
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
    };
  };
}
