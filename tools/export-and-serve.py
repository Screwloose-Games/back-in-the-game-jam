import errno
import glob
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = int(os.environ.get("PORT", 8002))
WINDOWS = os.name == "nt"

# Godot is not on PATH on every machine here, so look for it in the usual places.
if WINDOWS:
    GODOT_SEARCH_GLOBS = [
        "D:/Godot_v*_win64.exe",
        "C:/Program Files/Godot/Godot_v*_win64.exe",
        str(Path.home() / "AppData/Local/Programs/Godot/Godot_v*_win64.exe"),
    ]
elif sys.platform == "darwin":
    # Homebrew's cask installs the bundle into /Applications; its `godot` shim, if
    # any, is already covered by the PATH lookup below.
    GODOT_SEARCH_GLOBS = [
        "/Applications/Godot.app/Contents/MacOS/Godot",
        "/Applications/Godot_v*.app/Contents/MacOS/Godot",
        str(Path.home() / "Applications/Godot.app/Contents/MacOS/Godot"),
        str(Path.home() / "Applications/Godot_v*.app/Contents/MacOS/Godot"),
    ]
else:
    GODOT_SEARCH_GLOBS = [
        str(Path.home() / ".local/bin/[Gg]odot*"),
        str(Path.home() / "Applications/Godot_v*_linux.x86_64"),
        "/usr/local/bin/[Gg]odot*",
        "/opt/[Gg]odot*/[Gg]odot*",
        "/opt/Godot_v*_linux.x86_64",
    ]


def find_project_root(start):
    current = start.resolve()
    for candidate in [current, *current.parents]:
        if (candidate / "project.godot").is_file() or (candidate / ".git").is_dir():
            return candidate
    return start.resolve()


def find_godot():
    override = os.environ.get("GODOT_BIN") or os.environ.get("GODOT")
    if override:
        # A macOS bundle is a directory; the binary is buried inside it.
        if override.rstrip("/").endswith(".app") and Path(override).is_dir():
            override = str(Path(override) / "Contents/MacOS/Godot")
        if not Path(override).is_file():
            sys.exit(f"GODOT_BIN points at a missing file: {override}")
        return override

    for name in ("godot", "godot4", "Godot", "Godot_v4"):
        found = shutil.which(name)
        # A .cmd/.bat shim mangles the arguments we pass through it, so keep looking
        # for the real executable instead.
        if found and not (WINDOWS and found.lower().endswith((".cmd", ".bat"))):
            return found

    candidates = []
    for pattern in GODOT_SEARCH_GLOBS:
        candidates += [
            p
            for p in glob.glob(pattern)
            if "console" not in p and Path(p).is_file() and os.access(p, os.X_OK)
        ]
    if candidates:
        # Newest wins. The version is in the file name on Windows and Linux but only
        # in the directory on macOS, where every candidate is named "Godot".
        return max(candidates, key=lambda p: (Path(p).name, p))

    sys.exit("Could not find the Godot binary. Set GODOT_BIN to its full path.")


def is_port_busy_error(error):
    # Windows reports a taken port as WSAEADDRINUSE, or as WSAEACCES when the holder
    # claimed it exclusively; Python maps the latter to plain EACCES.
    return error.errno == errno.EADDRINUSE or getattr(error, "winerror", None) in (
        10048,
        10013,
    )


def port_in_use(port):
    # Windows lets us bind 127.0.0.1:PORT under a server holding 0.0.0.0:PORT, which
    # then keeps answering, so only a connection detects the clash.
    with socket.socket() as probe:
        probe.settimeout(0.5)
        return probe.connect_ex(("127.0.0.1", port)) == 0


def listening_pids_windows(port):
    try:
        netstat = subprocess.run(
            ["netstat", "-ano", "-p", "tcp"], capture_output=True, text=True, check=True
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return []

    pids = set()
    for line in netstat.splitlines():
        fields = line.split()
        if len(fields) >= 5 and fields[1].endswith(f":{port}") and fields[-1].isdigit():
            pid = int(fields[-1])
            if pid:
                pids.add(pid)
    return sorted(pids)


def listening_pids_posix(port):
    # lsof exits 1 when nothing matches, so read stdout rather than trusting the code.
    try:
        lsof = subprocess.run(
            ["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-t"],
            capture_output=True,
            text=True,
        ).stdout
        pids = sorted({int(line) for line in lsof.split() if line.isdigit()})
        if pids:
            return pids
    except OSError:
        pass

    try:
        ss = subprocess.run(
            ["ss", "-H", "-ltnp", f"sport = :{port}"], capture_output=True, text=True
        ).stdout
    except OSError:
        return []
    return sorted({int(pid) for pid in re.findall(r"pid=(\d+)", ss)})


def listening_pids(port):
    return listening_pids_windows(port) if WINDOWS else listening_pids_posix(port)


def describe_pid(pid):
    if WINDOWS:
        command = [
            "powershell",
            "-NoProfile",
            "-Command",
            f"(Get-CimInstance Win32_Process -Filter 'ProcessId={pid}').CommandLine",
        ]
    else:
        # `-o args=` is spelled the same for BSD ps and procps.
        command = ["ps", "-p", str(pid), "-o", "args="]
    try:
        command_line = subprocess.run(
            command, capture_output=True, text=True
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        command_line = ""
    return command_line or "(command line unavailable)"


def process_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def kill_pid(pid):
    if WINDOWS:
        result = subprocess.run(
            ["taskkill", "/PID", str(pid), "/F"], capture_output=True, text=True
        )
        if result.returncode:
            print((result.stderr or result.stdout).strip())
        return result.returncode == 0

    # Ask nicely, then escalate to match what taskkill /F does.
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return True
    except PermissionError as error:
        print(f"Cannot kill PID {pid}: {error}")
        return False

    for _ in range(8):
        if not process_alive(pid):
            return True
        time.sleep(0.25)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        return True
    except PermissionError as error:
        print(f"Cannot kill PID {pid}: {error}")
        return False
    return True


def busy_port_advice(port):
    if WINDOWS:
        find = f"netstat -ano | findstr :{port}"
        other = "$env:PORT=8003; python tools/export-and-serve.py"
    else:
        find = f"lsof -iTCP:{port} -sTCP:LISTEN"
        other = "PORT=8003 python3 tools/export-and-serve.py"
    return f"  Find it with:  {find}\n  Or pick another port:  {other}"


def free_port_or_exit(port):
    if not port_in_use(port):
        return

    pids = listening_pids(port)
    if pids and sys.stdin.isatty() and sys.stdout.isatty():
        print(f"Port {port} is already serving something:")
        for pid in pids:
            print(f"  PID {pid}  {describe_pid(pid)}")
        try:
            answer = input("Kill it and continue? [y/N] ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            answer = ""
        if answer in ("y", "yes"):
            for pid in pids:
                kill_pid(pid)
            for _ in range(20):
                if not port_in_use(port):
                    print(f"Port {port} is free.")
                    return
                time.sleep(0.25)
            sys.exit(f"Port {port} is still busy after killing {pids}.")

    sys.exit(
        f"Port {port} is already serving something. Stop it before exporting.\n"
        + busy_port_advice(port)
    )


class Server(ThreadingHTTPServer):
    # SO_REUSEADDR is not the same switch on both platforms. On Windows it lets a
    # second server bind over a live one, so keep it off there. On POSIX it only
    # skips TIME_WAIT, so leaving it off would just make a quick restart fail.
    allow_reuse_address = not WINDOWS


class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


free_port_or_exit(PORT)

project_root = find_project_root(Path.cwd())
build_dir = project_root / "releases/web"
# Godot fails the export rather than creating a missing output directory.
build_dir.mkdir(parents=True, exist_ok=True)

godot = find_godot()
print(f"Exporting with {godot}")
subprocess.run(
    [
        godot,
        "--headless",
        "--path",
        str(project_root),
        "--export-release",
        "Web",
        str(build_dir / "index.html"),
    ],
    check=True,
)

handler = partial(Handler, directory=build_dir)
try:
    server = Server(("127.0.0.1", PORT), handler)
except OSError as error:
    # Something grabbed the port during the export; anything else is a real bug.
    if not is_port_busy_error(error):
        raise
    sys.exit(f"Port {PORT} was taken while the export ran. Stop that server and retry.")
print(f"Serving {build_dir} on http://127.0.0.1:{PORT}", flush=True)
server.serve_forever()
