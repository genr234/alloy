"""alloy-download: downloads that keep going in rest mode.

Talks to the aria2 user service (alloy-downloads.service) over its RPC port.

  alloy-download URL...         queue downloads (-d DIR to pick the folder)
  alloy-download -i links.txt   queue every link in a file ("-" for stdin)
  alloy-download status         what's downloading, queued, done or failed
  alloy-download web            open the download page (AriaNg)
  alloy-download secret         the RPC secret, for a browser extension
  alloy-download pending        downloads and extractions still to do (rest
                                mode waits for this to reach 0)
  alloy-download extract [DIR]  extract finished archive sets in DIR now
  alloy-download hook GID N PATH
                                aria2's on-download-complete hook

When a download finishes, every complete archive set in its folder is
extracted next to it: name.part01.rar ... name.part20.rar, name.7z.001 ...,
or a single .rar, .7z or .zip. A set counts as complete once none of its
parts is still downloading, queued or half done. Extraction goes to
.<name>.extracting first and is moved into place when 7-Zip succeeds, so a
failure (a missing part, a wrong password) leaves no half-extracted folder.
"""

import argparse
import base64
import contextlib
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

RPC = os.environ.get("ALLOY_ARIA2_RPC", "http://127.0.0.1:6800/jsonrpc")
HOME = os.path.expanduser("~")
STATE = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local", "state")),
    "alloy",
)
SECRET = os.path.join(STATE, "aria2-secret")
# One file per running extraction (named after its pid), for `pending`.
EXTRACTING = os.path.join(STATE, "extracting")
SEVENZIP = os.environ.get("ALLOY_7Z", "7zz")
DELETE_ARCHIVES = os.environ.get("ALLOY_DOWNLOADS_DELETE_ARCHIVES") == "1"
COMMANDS = ("add", "status", "web", "secret", "pending", "extract", "hook")

# Multi-volume sets: (pattern, how to spot the first volume).
VOLUMES = [
    re.compile(r"^(?P<base>.+)\.part(?P<n>\d+)\.rar$", re.I),
    re.compile(r"^(?P<base>.+\.(?:7z|zip))\.(?P<n>\d{3})$", re.I),
]
SINGLE = re.compile(r"^(?P<base>.+)\.(?:rar|7z|zip)$", re.I)


def log(msg):
    print(f"alloy-download: {msg}", file=sys.stderr, flush=True)


# --- aria2 RPC -------------------------------------------------------------


def secret():
    with open(SECRET) as f:
        return f.read().strip()


def rpc(method, *params):
    body = json.dumps(
        {
            "jsonrpc": "2.0",
            "id": "alloy",
            "method": f"aria2.{method}",
            "params": [f"token:{secret()}", *params],
        }
    ).encode()
    req = urllib.request.Request(
        RPC, body, {"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            reply = json.load(r)
    except urllib.error.HTTPError as e:
        # aria2 answers errors with a 400 and a JSON body.
        reply = json.load(e)
    if "error" in reply:
        raise RuntimeError(reply["error"].get("message", "aria2 error"))
    return reply["result"]


KEYS = ["gid", "status", "totalLength", "completedLength",
        "downloadSpeed", "dir", "files", "errorMessage"]


def unfinished():
    """Downloads aria2 still has to do: active, queued or paused."""
    return rpc("tellActive", KEYS) + rpc("tellWaiting", 0, 10000, KEYS)


# --- archive sets ------------------------------------------------------------


def archive_set(name):
    """(base, member pattern, is first volume) for an archive file name."""
    for pattern in VOLUMES:
        m = pattern.match(name)
        if m:
            base = m.group("base")
            if pattern is VOLUMES[0]:
                members = re.escape(base) + r"\.part\d+\.rar"
            else:
                members = re.escape(base) + r"\.\d{3}"
            stem = re.sub(r"\.(7z|zip)$", "", base, flags=re.I)
            return stem, re.compile(members + "$", re.I), int(m["n"]) == 1
    m = SINGLE.match(name)
    if m:
        return m["base"], re.compile(re.escape(name) + "$"), True
    return None


def find_sets(directory):
    """{stem: (first volume, [members])} for the archives in directory."""
    sets = {}
    try:
        names = sorted(os.listdir(directory))
    except OSError:
        return sets
    for name in names:
        info = archive_set(name)
        if not info or not info[2]:
            continue
        stem, members, _ = info
        sets[stem] = (
            os.path.join(directory, name),
            [n for n in names if members.match(n)],
        )
    return sets


def busy_paths(downloads):
    """Paths aria2 is still writing, and whether some aren't known yet."""
    paths, unknown = set(), False
    for d in downloads:
        for f in d.get("files", []):
            if f.get("path"):
                paths.add(os.path.realpath(f["path"]))
            else:
                # Queued and not started: aria2 only learns the file name
                # from the server.
                unknown = True
    return paths, unknown


def ready(directory, stem, members, busy, unknown):
    """Whether a set can be extracted now; logs why not."""
    marker = os.path.join(directory, f".{stem}")
    if os.path.exists(marker + ".extracted"):
        return False
    try:
        with open(marker + ".failed") as f:
            if f.read().split("\n") == members:
                return False  # failed before with these very parts
    except OSError:
        pass
    for n in members:
        path = os.path.join(directory, n)
        if os.path.realpath(path) in busy or os.path.exists(path + ".aria2"):
            log(f"{stem}: waiting for {n}")
            return False
    if unknown:
        log(f"{stem}: waiting for queued downloads to start")
        return False
    return True


@contextlib.contextmanager
def extracting():
    os.makedirs(EXTRACTING, exist_ok=True)
    mark = os.path.join(EXTRACTING, str(os.getpid()))
    open(mark, "w").close()
    try:
        yield
    finally:
        with contextlib.suppress(OSError):
            os.remove(mark)


def extract(directory, stem, first, members):
    tmp = os.path.join(directory, f".{stem}.extracting")
    shutil.rmtree(tmp, ignore_errors=True)
    log(f"{stem}: extracting {os.path.basename(first)}")
    # -p with no password: an encrypted archive fails instead of asking.
    result = subprocess.run(
        [SEVENZIP, "x", "-y", "-p", "-bd", "-bb0", f"-o{tmp}", first],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    marker = os.path.join(directory, f".{stem}")
    if result.returncode != 0:
        shutil.rmtree(tmp, ignore_errors=True)
        log(f"{stem}: extraction failed: {result.stderr.strip()}")
        with open(marker + ".failed", "w") as f:
            f.write("\n".join(members))
        return False

    # An archive holding one folder becomes that folder; anything else
    # goes into a folder named after the archive.
    entries = os.listdir(tmp)
    if len(entries) == 1 and os.path.isdir(os.path.join(tmp, entries[0])):
        source, name = os.path.join(tmp, entries[0]), entries[0]
    else:
        source, name = tmp, stem
    target = os.path.join(directory, name)
    n = 1
    while os.path.exists(target):
        n += 1
        target = os.path.join(directory, f"{name} ({n})")
    os.rename(source, target)
    shutil.rmtree(tmp, ignore_errors=True)
    with contextlib.suppress(OSError):
        os.remove(marker + ".failed")
    open(marker + ".extracted", "w").close()
    log(f"{stem}: extracted to {target}")
    if DELETE_ARCHIVES:
        for m in members:
            os.remove(os.path.join(directory, m))
    return True


def extract_ready(directory, downloads):
    """Extract every complete set in directory, one at a time."""
    os.makedirs(directory, exist_ok=True)
    lock = open(os.path.join(directory, ".alloy-extract.lock"), "w")
    with lock, extracting():
        fcntl.flock(lock, fcntl.LOCK_EX)
        busy, unknown = busy_paths(downloads)
        ok = True
        for stem, (first, members) in find_sets(directory).items():
            if ready(directory, stem, members, busy, unknown):
                ok = extract(directory, stem, first, members) and ok
        return ok


# --- commands ----------------------------------------------------------------


def cmd_add(args):
    urls = list(args.urls)
    if args.input_file:
        f = sys.stdin if args.input_file == "-" else open(args.input_file)
        with f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    urls.append(line)
    if not urls:
        log("no links given")
        return 2
    options = {}
    if args.dir:
        options["dir"] = os.path.abspath(os.path.expanduser(args.dir))
    for url in urls:
        rpc("addUri", [url], options)
    log(f"queued {len(urls)} download(s); see them with 'alloy-download status'")
    return 0


def size(n):
    n = float(n)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if n < 1024:
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TiB"


def cmd_status(_args):
    downloads = unfinished() + rpc("tellStopped", 0, 10000, KEYS)
    if not downloads:
        print("No downloads.")
    for d in downloads:
        files = d.get("files") or [{}]
        name = os.path.basename(files[0].get("path", "")) or (
            (files[0].get("uris") or [{}])[0].get("uri", d["gid"])
        )
        total, done = int(d["totalLength"]), int(d["completedLength"])
        pct = f"{100 * done // total:3d}%" if total else "  ?%"
        line = f"{d['status']:<8} {pct} {size(total):>10}  {name}"
        if d["status"] == "active":
            line += f"  ({size(d['downloadSpeed'])}/s)"
        if d["status"] == "error":
            line += f"  [{d.get('errorMessage', '')}]"
        print(line)
    return 0


def live_extractions():
    count = 0
    try:
        pids = os.listdir(EXTRACTING)
    except OSError:
        return 0
    for pid in pids:
        if pid.isdigit() and os.path.exists(f"/proc/{pid}"):
            count += 1
        else:
            with contextlib.suppress(OSError):
                os.remove(os.path.join(EXTRACTING, pid))
    return count


def cmd_pending(_args):
    """Prints how much is left; 0 when aria2 isn't running at all."""
    count = live_extractions()
    try:
        stat = rpc("getGlobalStat")
        # Paused downloads (numWaiting includes them) would keep the
        # console up forever, as with Steam, so they don't count.
        paused = sum(1 for d in rpc("tellWaiting", 0, 10000, ["status"])
                     if d["status"] == "paused")
        count += int(stat["numActive"]) + int(stat["numWaiting"]) - paused
    except (OSError, RuntimeError, ValueError):
        pass
    print(count)
    return 0


def cmd_secret(_args):
    print(secret())
    return 0


def cmd_web(_args):
    page = os.environ.get("ALLOY_ARIANG")
    if not page:
        log("the download page (AriaNg) isn't installed")
        return 1
    token = base64.urlsafe_b64encode(secret().encode()).decode().rstrip("=")
    url = f"file://{page}#!/settings/rpc/set/http/127.0.0.1/6800/jsonrpc/{token}"
    return subprocess.call(["xdg-open", url])


def cmd_extract(args):
    directory = os.path.abspath(os.path.expanduser(args.dir))
    try:
        downloads = unfinished()
    except (OSError, RuntimeError):
        downloads = []
    return 0 if extract_ready(directory, downloads) else 1


def cmd_hook(args):
    # aria2 waits for nothing, but a hook that crashes would only be in the
    # journal: log and carry on.
    try:
        downloads = unfinished()
        extract_ready(os.path.dirname(os.path.abspath(args.path)), downloads)
    except Exception as e:  # noqa: BLE001
        log(f"extraction after {args.path} failed: {e}")
    return 0


def downloads_dir():
    """The download folder; relative to the home directory, as in aria2."""
    d = os.environ.get("ALLOY_DOWNLOADS_DIR", "Downloads")
    return os.path.join(os.path.expanduser("~"), os.path.expanduser(d))


def parse_args(argv):
    if not argv or (argv[0] not in COMMANDS and argv[0] not in ("-h", "--help")):
        argv = ["add", *argv]
    p = argparse.ArgumentParser(
        prog="alloy-download",
        description="Downloads that keep going in rest mode (aria2).",
    )
    sub = p.add_subparsers(dest="command", required=True)
    add = sub.add_parser("add", help="queue downloads")
    add.add_argument("urls", nargs="*")
    add.add_argument("-i", "--input-file", help="file with one link per line")
    add.add_argument("-d", "--dir", help="download folder")
    add.set_defaults(func=cmd_add)
    for name, func in [("status", cmd_status), ("web", cmd_web),
                       ("secret", cmd_secret), ("pending", cmd_pending)]:
        sub.add_parser(name).set_defaults(func=func)
    ex = sub.add_parser("extract", help="extract finished archive sets")
    ex.add_argument("dir", nargs="?", default=downloads_dir())
    ex.set_defaults(func=cmd_extract)
    hook = sub.add_parser("hook")
    hook.add_argument("gid")
    hook.add_argument("files")
    hook.add_argument("path")
    hook.set_defaults(func=cmd_hook)
    return p.parse_args(argv)


def main(argv):
    args = parse_args(argv)
    try:
        return args.func(args)
    except FileNotFoundError as e:
        if e.filename == SECRET:
            log("the download service hasn't started yet "
                "(systemctl --user status alloy-downloads)")
            return 1
        raise
    except (OSError, RuntimeError) as e:
        log(f"can't reach the download service: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
