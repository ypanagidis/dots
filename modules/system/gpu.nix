{ config, pkgs, ... }:

{
  # NVIDIA and graphics settings remain system-level because they affect the
  # kernel, display stack, CUDA-capable applications, and 32-bit game support.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    modesetting.enable = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.production;
    open = true;
    powerManagement = {
      enable = true;
      finegrained = false;
    };
  };

  # OBS is configured with CUDA support, so keep it near the GPU stack rather
  # than hiding it among general user applications.
  programs.obs-studio = {
    enable = true;
    package = pkgs.obs-studio.override {
      cudaSupport = true;
    };
    plugins = with pkgs.obs-studio-plugins; [ obs-vkcapture ];
  };
}
