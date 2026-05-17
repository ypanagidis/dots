# Browser Pinch Zoom

This setup tries to get macOS-style browser pinch zoom on Linux/KDE Wayland.

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

## MX Master Workaround

The MX Master thumb gesture button is not a real touchpad pinch. The workaround turns it into one:

```text
MX thumb button -> logid -> KEY_F13
mouse vertical movement -> mx-master-pinch -> virtual touchpad pinch
browser receives pinch zoom
```

Files:

- `modules/logitech.nix` installs and runs the services.
- `modules/logitech-mx-pinch.py` creates the virtual touchpad events.
- `modules/system/desktop-kde.nix` excludes `logid`'s virtual keyboard from `keyd`, so KDE does not treat `KEY_F13` as a normal shortcut.

## Services

`logid` exposes the hidden Logitech thumb button as `KEY_F13`.

`mx-master-pinch` grabs `logid`'s virtual keyboard, consumes `KEY_F13`, and watches mouse movement. While `KEY_F13` is held, vertical mouse movement changes the distance between two synthetic touch points on a virtual touchpad.

Check them with:

```sh
journalctl -u logid -u mx-master-pinch -f
```

Expected thumb button output:

```text
mx-master-pinch: key KEY_F13 value=1
mx-master-pinch: pinch begin
mx-master-pinch: key KEY_F13 value=0
mx-master-pinch: pinch end
```

## Limitations

This is experimental. Firefox Wayland works. Other Chromium-based browsers may vary.

If KDE shortcuts open while pressing the thumb button, `keyd` is probably still seeing `KEY_F13`.

If the thumb button stops working after config changes, restart both services:

```sh
sudo systemctl restart logid mx-master-pinch
```
