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
    # Newest non-beta release (615 new-feature branch, 2026-10-07). nixpkgs
    # still ships 615.71.09 as new_feature; switch back to
    # nvidiaPackages.latest once it catches up.
    package =
      (config.boot.kernelPackages.nvidiaPackages.mkDriver {
        version = "615.78.08";
        sha256_64bit = "sha256-Pj9t3cLudnoIGFMAr3vjyyhuznZpjS3eNSRZl4LQf/4=";
        openSha256 = "sha256-HBINiOjL0ZJLIAJeNIBYHBnwgUXtNwPPtnFpAI1YwF4=";
        settingsSha256 = "sha256-inDRpG02sdDgHmlqgu/DsgK8OFdOt1fZIYyXdhlGC/c=";
        persistencedSha256 = "sha256-RzeR6Ldct6MUxjnXRyThdh5Y3jjMehTVg85MtwuWNX4=";
      }).overrideAttrs
        (old: {
          # builder.sh sets interpreter and rpath in one patchelf call, which on
          # 615.78.08 emits a new RW LOAD that overlaps the next R LOAD. The
          # page holding .dynamic ends up read-only and ld.so segfaults writing
          # DT_DEBUG (nvidia-smi, nvidia-cuda-mps-control, nvidia-powerd).
          # Patching rpath and interpreter in separate passes gives a clean
          # layout. Drop once nixpkgs' builder stops producing it.
          postFixup = (old.postFixup or "") + ''
            for i in $bin/origBin/*; do
              dst=$bin/bin/$(basename "$i")
              install -m755 "$i" "$dst"
              patchelf --set-rpath "$out/lib:$libPath" "$dst"
              patchelf --interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$dst"
            done
          '';
        });
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
