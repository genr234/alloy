"""Hold the PS button on a controller to switch to game mode.

Runs inside the desktop session. Watches every gamepad (USB or Bluetooth,
including ones connected later) and runs `alloy-mode game` once the PS / Home
button has been held for ALLOY_PS_HOLD_SECONDS. A short press does nothing,
so Steam and games still get normal PS button presses.
"""

import os
import select
import subprocess
import sys
import time

import evdev
from evdev import ecodes

RESCAN_SECONDS = 3.0


class HoldDetector:
    """Fires once per press, when a button has been held long enough."""

    def __init__(self, hold_seconds):
        self.hold_seconds = hold_seconds
        self.pressed_at = None
        self.fired = False

    def press(self, now):
        self.pressed_at = now
        self.fired = False

    def release(self):
        self.pressed_at = None
        self.fired = False

    def due_in(self, now):
        """Seconds until this press fires, or None if nothing is pending."""
        if self.pressed_at is None or self.fired:
            return None
        return max(0.0, self.pressed_at + self.hold_seconds - now)

    def poll(self, now):
        """True exactly once per press, after it was held long enough."""
        due = self.due_in(now)
        if due is not None and due <= 0:
            self.fired = True
            return True
        return False


def is_gamepad(device):
    keys = device.capabilities().get(ecodes.EV_KEY, [])
    return ecodes.BTN_MODE in keys and ecodes.BTN_SOUTH in keys


def log(message):
    print(f"alloy-ps-button: {message}", file=sys.stderr, flush=True)


def main():
    hold = float(os.environ.get("ALLOY_PS_HOLD_SECONDS", "1.0"))
    pads = {}  # fd -> (device, HoldDetector)
    skipped = set()  # paths we can't use, so we don't retry them every scan
    next_scan = 0.0

    while True:
        now = time.monotonic()

        if now >= next_scan:
            known = {dev.path for dev, _ in pads.values()}
            for path in evdev.list_devices():
                if path in known or path in skipped:
                    continue
                try:
                    device = evdev.InputDevice(path)
                except OSError:
                    skipped.add(path)
                    continue
                if is_gamepad(device):
                    pads[device.fd] = (device, HoldDetector(hold))
                    log(f"watching {device.name} ({path})")
                else:
                    device.close()
                    skipped.add(path)
            # Event node numbers get reused after unplugging.
            skipped &= set(evdev.list_devices())
            next_scan = now + RESCAN_SECONDS

        timeout = next_scan - now
        for _, detector in pads.values():
            due = detector.due_in(now)
            if due is not None:
                timeout = min(timeout, due)

        ready, _, _ = select.select(list(pads), [], [], max(timeout, 0))

        for fd in ready:
            device, detector = pads[fd]
            try:
                for event in device.read():
                    if (event.type == ecodes.EV_KEY
                            and event.code == ecodes.BTN_MODE):
                        if event.value == 1:
                            detector.press(time.monotonic())
                        elif event.value == 0:
                            detector.release()
            except OSError:
                log(f"{device.name} went away")
                del pads[fd]
                device.close()

        now = time.monotonic()
        for device, detector in pads.values():
            if detector.poll(now):
                log(f"PS button held on {device.name}, switching to game")
                subprocess.run(["alloy-mode", "game"], check=False)


if __name__ == "__main__":
    main()
