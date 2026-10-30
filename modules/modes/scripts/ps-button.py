"""Watch the controllers and switch modes from them.

One daemon, three jobs, picked by the session that starts it:

  desktop  alloy-ps-button
           Hold the PS button for ALLOY_PS_HOLD_SECONDS to switch to game
           mode. A short press does nothing, so Steam and games still get
           normal PS button presses.
  game     alloy-ps-button --target none --idle-minutes 30
           Go to rest mode after 30 minutes without controller input, but
           never while a game is running.
  rest     alloy-ps-button --hold 0 --wake-on-connect
           Any PS press, or a controller turning back on, wakes the console
           into game mode.

Watches every gamepad (USB or Bluetooth, including ones connected later).
"""

import argparse
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


class IdleTimer:
    """Fires when nothing happened for a while; any activity restarts it."""

    def __init__(self, idle_seconds, now):
        self.idle_seconds = idle_seconds
        self.last = now

    def touch(self, now):
        self.last = now

    def due_in(self, now):
        return max(0.0, self.last + self.idle_seconds - now)

    def poll(self, now):
        """True once per idle stretch; the next one starts counting at now."""
        if self.due_in(now) <= 0:
            self.last = now
            return True
        return False


def game_running(proc="/proc"):
    """True while Steam runs a game.

    Steam starts every game, non-Steam shortcuts included, through its
    `reaper SteamLaunch AppId=...` wrapper.
    """
    for pid in os.listdir(proc):
        if not pid.isdigit():
            continue
        try:
            with open(os.path.join(proc, pid, "cmdline"), "rb") as f:
                if b"SteamLaunch" in f.read():
                    return True
        except OSError:
            continue
    return False


def setting_on(name, default):
    """An on/off switch the Alloy Decky panel keeps in the state directory."""
    state = (os.environ.get("XDG_STATE_HOME")
             or os.path.expanduser("~/.local/state"))
    try:
        with open(os.path.join(state, "alloy", name)) as f:
            return f.read().strip() != "off"
    except OSError:
        return default


def is_gamepad(device):
    keys = device.capabilities().get(ecodes.EV_KEY, [])
    return ecodes.BTN_MODE in keys and ecodes.BTN_SOUTH in keys


def log(message):
    print(f"alloy-ps-button: {message}", file=sys.stderr, flush=True)


def switch(mode, why):
    log(f"{why}, switching to {mode}")
    subprocess.run(["alloy-mode", mode], check=False)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(prog="alloy-ps-button")
    parser.add_argument(
        "--hold", type=float,
        default=float(os.environ.get("ALLOY_PS_HOLD_SECONDS", "1.0")),
        help="seconds the PS button must be held (0: any press)")
    parser.add_argument(
        "--target", default="game",
        help="mode the PS button switches to, or 'none' to leave it alone")
    parser.add_argument(
        "--wake-on-connect", action="store_true",
        help="also switch when a controller connects (turned back on)")
    parser.add_argument(
        "--idle-minutes", type=float, default=0,
        help="go to rest mode after this long without controller input")
    return parser.parse_args(argv)


def main():
    args = parse_args()
    pads = {}  # fd -> (device, HoldDetector)
    skipped = set()  # paths we can't use, so we don't retry them every scan
    next_scan = 0.0
    first_scan = True
    idle = (IdleTimer(args.idle_minutes * 60, time.monotonic())
            if args.idle_minutes > 0 else None)

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
                    pads[device.fd] = (device, HoldDetector(args.hold))
                    log(f"watching {device.name} ({path})")
                    if args.wake_on_connect and not first_scan:
                        switch(args.target, f"{device.name} connected")
                else:
                    device.close()
                    skipped.add(path)
            # Event node numbers get reused after unplugging.
            skipped &= set(evdev.list_devices())
            next_scan = now + RESCAN_SECONDS
            first_scan = False

        timeout = next_scan - now
        for _, detector in pads.values():
            due = detector.due_in(now)
            if due is not None:
                timeout = min(timeout, due)
        if idle:
            timeout = min(timeout, idle.due_in(now))

        ready, _, _ = select.select(list(pads), [], [], max(timeout, 0))

        for fd in ready:
            device, detector = pads[fd]
            try:
                for event in device.read():
                    if idle:
                        idle.touch(time.monotonic())
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
            if detector.poll(now) and args.target != "none":
                switch(args.target, f"PS button on {device.name}")

        if idle and idle.poll(now) and setting_on("auto-rest", True):
            if game_running():
                # Cutscenes and paused games are not idle; start over.
                idle.touch(now)
            else:
                minutes = f"{args.idle_minutes:g}"
                switch("rest", f"no controller input for {minutes} minutes")


if __name__ == "__main__":
    main()
