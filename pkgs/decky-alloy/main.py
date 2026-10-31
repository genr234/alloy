"""Alloy's panel in Steam's Quick Access menu.

Rest mode and its two switches, PS5 boost, and Steam's download queue for
rest mode's shutdown. Runs as the console's user,
not root: the switches are files in Alloy's state directory, which the
session scripts read (modules/modes/scripts), and boost is a unit that user
may start and stop (modules/modes/default.nix).
"""

import asyncio
import json
import os

import decky

STATE = os.path.join(decky.DECKY_USER_HOME, ".local", "state", "alloy")
# Written by modules/modes/decky.nix from the alloy.modes options.
DEFAULTS = "/etc/alloy/modes.json"
BOOST_UNIT = "alloy-game-performance.service"
SETTINGS = ("auto-rest", "shutdown-when-done")
# Read by alloy-rest-session.sh: Steam downloads still to do.
DOWNLOADS = "steam-downloads"


def defaults():
    try:
        with open(DEFAULTS) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def setting_on(name, default):
    try:
        with open(os.path.join(STATE, name)) as f:
            return f.read().strip() != "off"
    except OSError:
        return default


async def run(*cmd):
    proc = await asyncio.create_subprocess_exec(
        *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    out, err = await proc.communicate()
    if proc.returncode:
        decky.logger.warning(f"{' '.join(cmd)}: {err.decode().strip()}")
    return proc.returncode, out.decode().strip()


class Plugin:
    async def get_status(self):
        d = defaults()
        boost = None
        if d.get("boost"):
            _, state = await run("systemctl", "is-active", BOOST_UNIT)
            boost = state == "active"
        return {
            "restEnabled": d.get("rest", False),
            "autoRestMinutes": d.get("autoRestMinutes", 0),
            "autoRest": setting_on("auto-rest", True),
            "shutdownWhenDone": setting_on(
                "shutdown-when-done", d.get("shutdownWhenDone", True)
            ),
            "boost": boost,
            "updatePending": (await run("alloy-update", "status"))[0] == 0,
        }

    async def set_setting(self, name, on):
        if name not in SETTINGS:
            raise ValueError(f"unknown setting {name}")
        os.makedirs(STATE, exist_ok=True)
        with open(os.path.join(STATE, name), "w") as f:
            f.write("on\n" if on else "off\n")

    async def report_downloads(self, pending):
        os.makedirs(STATE, exist_ok=True)
        path = os.path.join(STATE, DOWNLOADS)
        with open(path + ".tmp", "w") as f:
            f.write(f"{int(pending)}\n")
        os.replace(path + ".tmp", path)

    async def set_boost(self, on):
        code, _ = await run("systemctl", "start" if on else "stop", BOOST_UNIT)
        return code == 0

    async def finish_update(self):
        code, _ = await run("alloy-update", "finish", "game")
        return code == 0

    async def rest_now(self):
        code, _ = await run("alloy-mode", "rest")
        return code == 0

    async def _main(self):
        decky.logger.info("Alloy panel loaded")

    async def _unload(self):
        pass
