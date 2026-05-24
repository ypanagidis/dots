# Browser Pinch Zoom

This setup keeps browser pinch zoom working through native touchpad gestures on Linux/KDE Wayland.

## Native Touchpad Path

Browsers need real Wayland pinch gesture events for smooth pinch zoom. The clean path is:

```text
touchpad -> libinput/KWin -> Wayland pinch gesture -> browser
```

This repo enables the browser-side Wayland pieces in `configuration.nix`:

```nix
MOZ_ENABLE_WAYLAND = "1";
NIXOS_OZONE_WL = "1";
```

Firefox also has the pinch preference enabled in `modules/browsers/default.nix`:

```nix
apz.gtk.touchpad_pinch.enabled = true;
```

An Apple Magic Trackpad should use this path directly.
