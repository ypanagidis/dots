{
  lib,
  niri,
  rustPlatform,
}:

niri.overrideAttrs (oldAttrs: {
  # Niri 26.04 predates Smithay PR #2080. Keep the compositor release fixed
  # while moving only Smithay to the reviewed upstream GPU leak fixes.
  # pkgs.niri already contains a realised cargoDeps attribute. Re-vendor its
  # original lockfile and patch only the pinned Smithay source inside it. This
  # avoids pulling unrelated post-26.04 Smithay dependencies into Niri.
  cargoDeps = rustPlatform.fetchCargoVendor {
    pname = "niri";
    version = "26.04-smithay-vram-fixed";
    inherit (oldAttrs) src;
    postBuild = ''
      patch -d "$out/git/ff5fa7df392cecfba049ffed55cdaa4e98a8e7ef" \
        -p1 < ${./smithay-vram-fixes.patch}
    '';
    hash = "sha256-9+BM0sEquTI/CzAO7ytl1iUFKJSn4U/X9g1v5MYNw1Y=";
  };

  env = (oldAttrs.env or { }) // {
    NIRI_BUILD_COMMIT = "Nixpkgs+Smithay-VRAM-fixes";
  };
})
