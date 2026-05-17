{
  pkgs,
  inputs,
  ...
}:

let
  pkgsUnstable = import inputs.nixpkgs-unstable {
    inherit (pkgs) system;
    config = pkgs.config;
  };
  pkgsMaster = import inputs.nixpkgs-master {
    inherit (pkgs) system;
    config = pkgs.config;
  };
in

{
  # Home Manager entrypoint. Keep long package lists in imported modules so this
  # file only explains the shape of the user environment.
  _module.args.pkgsUnstable = pkgsUnstable;
  _module.args.pkgsMaster = pkgsMaster;

  imports = [
    ./modules/dev/base.nix
    ./modules/apps/gui.nix
    ./modules/media
    ./modules/gaming
    ./modules/ides
    ./modules/clis
    ./modules/terminals.nix
    ./modules/des
    ./modules/browsers
  ];

  home.stateVersion = "25.11";
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
