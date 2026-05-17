#!/usr/bin/env python3
import os
import select
import signal
import sys
import time

from evdev import AbsInfo, InputDevice, UInput, ecodes, list_devices


DEVICE_NAMES = [
    name.strip()
    for name in os.environ.get(
        "MX_PINCH_DEVICE_NAMES",
        "MX Master 3S,Logitech MX Master 3S,Logitech USB Receiver",
    ).split(",")
    if name.strip()
]
KEY_DEVICE_NAMES = [
    name.strip()
    for name in os.environ.get("MX_PINCH_KEY_DEVICE_NAMES", "LogiOps Virtual Input").split(",")
    if name.strip()
]
BUTTON_NAMES = [
    name.strip()
    for name in os.environ.get("MX_PINCH_BUTTONS", "KEY_F13").split(",")
    if name.strip()
]
SENSITIVITY = float(os.environ.get("MX_PINCH_SENSITIVITY", "6.0"))
DEBUG = os.environ.get("MX_PINCH_DEBUG", "0") == "1"

CENTER_X = 1000
CENTER_Y = 1000
START_DISTANCE = 300
MIN_DISTANCE = 80
MAX_DISTANCE = 900

running = True


def log(message):
    print(f"mx-master-pinch: {message}", flush=True)


def code_name(event_type, code):
    name = ecodes.bytype.get(event_type, {}).get(code, str(code))
    if isinstance(name, list):
        return name[0]
    return name


def parse_button_codes():
    codes = set()
    for name in BUTTON_NAMES:
        if name.isdigit():
            codes.add(int(name))
            continue

        value = getattr(ecodes, name, None)
        if value is None:
            log(f"unknown button code in MX_PINCH_BUTTONS: {name}")
            continue
        codes.add(value)
    return codes


BUTTON_CODES = parse_button_codes()


def device_caps(device):
    caps = device.capabilities(absinfo=False)
    rel_codes = set(caps.get(ecodes.EV_REL, []))
    key_codes = set(caps.get(ecodes.EV_KEY, []))
    return rel_codes, key_codes


def is_motion_device(device):
    rel_codes, _ = device_caps(device)
    is_named_mouse = any(name in device.name for name in DEVICE_NAMES)
    return is_named_mouse and ecodes.REL_Y in rel_codes


def is_button_device(device):
    _, key_codes = device_caps(device)
    is_named_key_device = any(name in device.name for name in KEY_DEVICE_NAMES)
    emits_pinch_button = bool(BUTTON_CODES.intersection(key_codes))
    return is_named_key_device and emits_pinch_button


def matching_device(device):
    return is_motion_device(device) or is_button_device(device)


def maybe_grab_button_device(device):
    if not is_button_device(device):
        return

    try:
        device.grab()
        device.mx_pinch_grabbed = True
        log(f"grabbed {device.path}: {device.name}")
    except OSError as error:
        log(f"could not grab {device.path}: {device.name}: {error}")


def close_device(device):
    if getattr(device, "mx_pinch_grabbed", False):
        try:
            device.ungrab()
        except OSError:
            pass
    device.close()


def open_devices():
    devices = []
    for path in sorted(list_devices()):
        try:
            device = InputDevice(path)
        except OSError:
            continue

        try:
            if matching_device(device):
                maybe_grab_button_device(device)
                devices.append(device)
                log(f"watching {device.path}: {device.name}")
            else:
                close_device(device)
        except OSError:
            close_device(device)

    return devices


def refresh_devices(devices):
    known_paths = {device.path for device in devices}
    refreshed = list(devices)

    for path in sorted(list_devices()):
        if path in known_paths:
            continue

        try:
            device = InputDevice(path)
        except OSError:
            continue

        try:
            if matching_device(device):
                maybe_grab_button_device(device)
                refreshed.append(device)
                log(f"watching {device.path}: {device.name}")
            else:
                close_device(device)
        except OSError:
            close_device(device)

    return refreshed


def create_virtual_touchpad():
    abs_range = AbsInfo(value=0, min=0, max=2000, fuzz=0, flat=0, resolution=20)
    caps = {
        ecodes.EV_KEY: [
            ecodes.BTN_TOUCH,
            ecodes.BTN_TOOL_DOUBLETAP,
        ],
        ecodes.EV_ABS: [
            (ecodes.ABS_X, abs_range),
            (ecodes.ABS_Y, abs_range),
            (ecodes.ABS_MT_SLOT, AbsInfo(value=0, min=0, max=1, fuzz=0, flat=0, resolution=0)),
            (
                ecodes.ABS_MT_TRACKING_ID,
                AbsInfo(value=0, min=0, max=65535, fuzz=0, flat=0, resolution=0),
            ),
            (ecodes.ABS_MT_POSITION_X, abs_range),
            (ecodes.ABS_MT_POSITION_Y, abs_range),
        ],
    }

    return UInput(
        caps,
        name="MX Master Virtual Pinch Touchpad",
        vendor=0x1209,
        product=0x0001,
        version=1,
        bustype=ecodes.BUS_USB,
        input_props=[ecodes.INPUT_PROP_POINTER],
    )


class PinchEmitter:
    def __init__(self, ui):
        self.ui = ui
        self.active = False
        self.distance = START_DISTANCE
        self.next_tracking_id = 10

    def _contact(self, slot, tracking_id, x, y):
        self.ui.write(ecodes.EV_ABS, ecodes.ABS_MT_SLOT, slot)
        self.ui.write(ecodes.EV_ABS, ecodes.ABS_MT_TRACKING_ID, tracking_id)
        self.ui.write(ecodes.EV_ABS, ecodes.ABS_MT_POSITION_X, x)
        self.ui.write(ecodes.EV_ABS, ecodes.ABS_MT_POSITION_Y, y)

    def _frame(self):
        half = int(self.distance / 2)
        self.ui.write(ecodes.EV_KEY, ecodes.BTN_TOUCH, 1)
        self.ui.write(ecodes.EV_KEY, ecodes.BTN_TOOL_DOUBLETAP, 1)
        self._contact(0, self.next_tracking_id, CENTER_X - half, CENTER_Y)
        self._contact(1, self.next_tracking_id + 1, CENTER_X + half, CENTER_Y)
        self.ui.syn()

    def begin(self):
        if self.active:
            return

        self.active = True
        self.distance = START_DISTANCE
        self.next_tracking_id += 2
        self._frame()
        log("pinch begin")

    def update_from_rel_y(self, rel_y):
        if not self.active or rel_y == 0:
            return

        self.distance = max(MIN_DISTANCE, min(MAX_DISTANCE, self.distance - rel_y * SENSITIVITY))
        self._frame()

    def end(self):
        if not self.active:
            return

        self.ui.write(ecodes.EV_ABS, ecodes.ABS_MT_SLOT, 0)
        self.ui.write(ecodes.EV_ABS, ecodes.ABS_MT_TRACKING_ID, -1)
        self.ui.write(ecodes.EV_ABS, ecodes.ABS_MT_SLOT, 1)
        self.ui.write(ecodes.EV_ABS, ecodes.ABS_MT_TRACKING_ID, -1)
        self.ui.write(ecodes.EV_KEY, ecodes.BTN_TOUCH, 0)
        self.ui.write(ecodes.EV_KEY, ecodes.BTN_TOOL_DOUBLETAP, 0)
        self.ui.syn()
        self.active = False
        log("pinch end")


def stop(_signum, _frame):
    global running
    running = False


def main():
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    if not BUTTON_CODES:
        log("no valid button codes configured")
        return 1

    log(f"matching device names: {', '.join(DEVICE_NAMES)}")
    log(f"matching key device names: {', '.join(KEY_DEVICE_NAMES)}")
    log(f"thumb button candidates: {', '.join(BUTTON_NAMES)}")

    ui = create_virtual_touchpad()
    emitter = PinchEmitter(ui)
    devices = open_devices()

    try:
        while running:
            if not devices:
                time.sleep(2)
                devices = open_devices()
                continue

            readable, _, _ = select.select(devices, [], [], 2)
            if not readable:
                devices = refresh_devices(devices)
                continue

            for device in readable:
                try:
                    events = device.read()
                except OSError:
                    log(f"lost {device.path}: {device.name}")
                    for stale in devices:
                        close_device(stale)
                    devices = open_devices()
                    break

                for event in events:
                    if event.type == ecodes.EV_KEY:
                        if DEBUG and event.code in BUTTON_CODES and event.value in (0, 1, 2):
                            log(f"key {code_name(event.type, event.code)} value={event.value} from {device.name}")

                        if event.code in BUTTON_CODES:
                            if event.value == 1:
                                emitter.begin()
                            elif event.value == 0:
                                emitter.end()

                    elif event.type == ecodes.EV_REL and event.code == ecodes.REL_Y:
                        emitter.update_from_rel_y(event.value)

    finally:
        emitter.end()
        for device in devices:
            close_device(device)
        ui.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
