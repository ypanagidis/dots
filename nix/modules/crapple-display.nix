{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.apple-studio-display;

  # Define the package locally within the module
  asdbctl = pkgs.rustPlatform.buildRustPackage rec {
    pname = "asdbctl";
    version = "master";

    src = pkgs.fetchFromGitHub {
      owner = "juliuszint";
      repo = "asdbctl";
      rev = "42bb4fc6256903c6fac37af2c864b95592197d62";
      hash = "sha256-UHOX4VRcqxxYRIrJiFrf2a89BYhmZ2oGy78vk06y/8w=";
    };

    cargoHash = "sha256-OPmnGh6xN6XeREeIgyYB2aeHUpdQ5hFS5MivcTeY29E=";

    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.udev ];
  };
in
{
  options.hardware.apple-studio-display = {
    enable = lib.mkEnableOption "Apple Studio Display brightness control and permissions";
  };

  config = lib.mkIf cfg.enable {
    # 1. Install the tool system-wide
    environment.systemPackages = [ asdbctl ];

    # 2. Apply the necessary Udev rule automatically
    services.udev.extraRules = ''
      # Rule for the raw USB device (sometimes needed)
      SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", ATTR{idProduct}=="9b33", MODE="0666"

      # Rule for the HID device (Required for asdbctl)
      # We use ATTRS (plural) because the Vendor ID is on the parent USB device, not the hidraw node itself.
      KERNEL=="hidraw*", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="9b33", MODE="0666"
    '';
  };
}
