{ pkgs, ... }:

{
  # Docker uses gVisor as an alternate runtime. Keep the package next to the
  # daemon config instead of in the generic system package list.
  virtualisation.docker = {
    enable = true;
    daemon.settings.runtimes.runsc = {
      path = "${pkgs.gvisor}/bin/runsc";
      runtimeArgs = [ "--platform=ptrace" ];
    };
  };

  # Libvirt/QEMU are system services. virt-manager is a GUI, but it is tightly
  # coupled to this stack, so keeping it here makes the dependency clear.
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
      runAsRoot = true;
    };
  };

  environment.systemPackages = with pkgs; [
    gvisor
    virt-manager
  ];
}
