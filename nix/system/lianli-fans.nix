{ pkgs, ... }:

{
  # The Lian Li Uni SL-Infinity hub keeps its fan settings in volatile RAM:
  # after a real power-off it reverts to its default (full blast). Pin all
  # channels to a quiet baseline at boot, before coolercontrold starts —
  # CoolerControl's temp curves (configured in its GUI, state under
  # /etc/coolercontrol) then take over when present. This only guards the
  # blank-config / fresh-install case, like the one that followed the
  # 2026-08-15 reinstall.
  systemd.services.lianli-fan-baseline = {
    description = "Set Lian Li SL-Infinity fans to a quiet baseline";
    wantedBy = [ "multi-user.target" ];
    before = [ "coolercontrold.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      for ch in fan1 fan2 fan3 fan4; do
        ${pkgs.liquidctl}/bin/liquidctl --match "SL-Infinity" set "$ch" speed 30 || true
      done
    '';
  };
}
