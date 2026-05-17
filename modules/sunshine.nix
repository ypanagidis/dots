{
  config,
  pkgs,
  lib,
  ...
}:

{
  services.sunshine = {
    enable = true;
    package = pkgs.sunshine.override {
      cudaSupport = true;
    };
    # Keep Sunshine installed and configured, but do not launch it automatically
    # when the machine boots or the user session starts.
    autoStart = false;
    capSysAdmin = true;
    openFirewall = true;
    settings = {
      sunshine_name = "nix-pc";
    };
    applications = {
      apps = [
        {
          name = "Desktop";
          auto-detach = "true";
        }
      ];
    };
  };
}
