import errno
import os
import re
import signal
import socket
import subprocess
import sys
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from godot_bin import WINDOWS, find_godot, find_project_root

PORT = int(os.environ.get("PORT", 8002))


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
    # Windows records .js as text/plain in HKCR, and Python's mimetypes honours the
    # registry, so the default map serves the engine's scripts as plain text. Chrome
    # refuses an AudioWorklet module with a non-JavaScript MIME type, and Godot then
    # has no audio driver at all - the build runs completely silent, which makes it
    # useless for testing anything to do with sound.
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".wasm": "application/wasm",
    }

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
