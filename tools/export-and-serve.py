import subprocess
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def find_project_root(start):
    current = start.resolve()
    for candidate in [current, *current.parents]:
        if (candidate / "project.godot").is_file() or (candidate / ".git").is_dir():
            return candidate
    return start.resolve()


class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


project_root = find_project_root(Path.cwd())
build_dir = project_root / "releases/web"

# Run build
subprocess.run(
    ["godot", "--export-release", "Web", str(build_dir / "index.html")], check=True
)

handler = partial(Handler, directory=build_dir)
print("Serving on http://127.0.0.1:8002")
ThreadingHTTPServer(("127.0.0.1", 8002), handler).serve_forever()
