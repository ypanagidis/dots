{ pkgs, ... }:

let
  python = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.evdev ]);
  mxMasterPinch = pkgs.writeShellApplication {
    name = "mx-master-pinch";
    text = ''
      exec ${python}/bin/python ${./logitech-mx-pinch.py}
    '';
  };
  mxMaster3sLogidConfig = name: ''
    {
      name: "${name}";

      buttons: (
        {
          // MX Master thumb/gesture button. logid exposes this otherwise-hidden
          // HID++ control as KEY_F13 so mx-master-pinch can use it as a modifier.
          cid: 0xc3;
          action =
          {
            type: "Keypress";
            keys: ["KEY_F13"];
          };
        }
      );
    }
  '';
in
{
  hardware.uinput.enable = true;

  environment.systemPackages = with pkgs; [
    evtest
    libinput
    logiops
    mxMasterPinch
  ];

  environment.etc."logid.cfg".text = ''
    devices: (
      ${mxMaster3sLogidConfig "MX Master 3S"},
      ${mxMaster3sLogidConfig "Logitech MX Master 3S"}
    );
  '';

  systemd.services.logid = {
    description = "Logitech HID++ device configuration daemon";
    wantedBy = [ "graphical.target" ];
    before = [ "mx-master-pinch.service" ];

    serviceConfig = {
      ExecStart = "${pkgs.logiops}/bin/logid -c /etc/logid.cfg";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.services.mx-master-pinch = {
    description = "Map MX Master thumb movement to a virtual touchpad pinch";
    wantedBy = [ "graphical.target" ];
    after = [
      "graphical.target"
      "logid.service"
      "systemd-udev-settle.service"
    ];

    environment = {
      MX_PINCH_DEVICE_NAMES = "MX Master 3S,Logitech MX Master 3S,Logitech USB Receiver";
      MX_PINCH_KEY_DEVICE_NAMES = "LogiOps Virtual Input";
      MX_PINCH_BUTTONS = "KEY_F13";
      MX_PINCH_SENSITIVITY = "6.0";
      # Keep this on for the first pass so journalctl confirms KEY_F13 events.
      MX_PINCH_DEBUG = "1";
    };

    serviceConfig = {
      ExecStart = "${mxMasterPinch}/bin/mx-master-pinch";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
