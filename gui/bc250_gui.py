#!/usr/bin/env python3
"""Local graphical guide for BC-250 CU Unlock Suite.

The GUI intentionally does not perform privileged GPU writes itself. It serves a
localhost-only web UI and launches the existing CLI commands in a visible
terminal. This keeps one safety/validation implementation: the CLI.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
from pathlib import Path
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
GUI_DIR = Path(__file__).resolve().parent
VERSION_FILE = ROOT / "VERSION"
UPSTREAM_MANAGER = ROOT / "upstream" / "bc250-cu-live-manager" / "bc250-cu-live-manager.sh"
UPSTREAM_VERIFY = ROOT / "upstream" / "bc250-40cu-unlock" / "scripts" / "bc250-compute-verify.sh"
SERVICE = "bc250-cu-live-manager.service"
CPU_REARM_SERVICE = "bc250-cpu-rearm.service"
SERVICE_CONF = Path("/etc/bc250-cu-live-manager.conf")

# When boot persistence is enabled, probing commands intentionally refuse to run.
# Mirror that safety rule in the GUI so beginners are not led into expected errors.
PERSISTENCE_LOCKED_ACTIONS = {
    "setup", "wizard", "doctor", "baseline", "scan", "visual", "apply",
    "soak30", "recover", "stock", "persist_install",
}

# Fixed action whitelist. The browser never supplies shell commands.
ACTIONS: dict[str, dict[str, Any]] = {
    "setup": {"cmd": "bash ./setup.sh", "group": "start", "risk": "system"},
    "wizard": {"cmd": "sudo bash ./bc250-unlock wizard", "group": "start", "risk": "write"},
    "doctor": {"cmd": "sudo bash ./bc250-unlock doctor", "group": "workflow", "risk": "normal"},
    "baseline": {"cmd": "sudo bash ./bc250-unlock baseline", "group": "workflow", "risk": "write"},
    "scan": {"cmd": "sudo bash ./bc250-unlock scan", "group": "workflow", "risk": "write"},
    "visual": {"cmd": "sudo bash ./bc250-unlock visual", "group": "workflow", "risk": "write"},
    "results": {"cmd": "sudo bash ./bc250-unlock results", "group": "workflow", "risk": "normal"},
    "apply": {"cmd": "sudo bash ./bc250-unlock apply", "group": "workflow", "risk": "write"},
    "status": {"cmd": "sudo bash ./bc250-unlock status", "group": "tools", "risk": "normal"},
    "soak30": {"cmd": "sudo bash ./bc250-unlock soak 30", "group": "tools", "risk": "write"},
    "report": {"cmd": "sudo bash ./bc250-unlock report", "group": "tools", "risk": "normal"},
    "recover": {"cmd": "sudo bash ./bc250-unlock recover", "group": "recovery", "risk": "write"},
    "stock": {"cmd": "sudo bash ./bc250-unlock stock", "group": "recovery", "risk": "write"},
    "persist_status": {"cmd": "sudo bash ./bc250-unlock persist status", "group": "persist", "risk": "normal"},
    "persist_install": {"cmd": "sudo bash ./bc250-unlock persist install", "group": "persist", "risk": "persist"},
    "persist_remove": {"cmd": "sudo bash ./bc250-unlock persist remove", "group": "persist", "risk": "persist"},
    "persist_reapply": {"cmd": "sudo bash ./bc250-unlock persist reapply", "group": "persist", "risk": "write"},
    "steamos_verify": {"cmd": "sudo bash ./bc250-unlock steamos verify", "group": "steamos", "risk": "normal"},
    "steamos_repair": {"cmd": "sudo bash ./bc250-unlock steamos repair", "group": "steamos", "risk": "system"},
    "cpu_status": {"cmd": "sudo bash ./bc250-unlock cpu status", "group": "cpu", "risk": "normal"},
    "cpu_unlock": {"cmd": "sudo bash ./bc250-unlock cpu unlock", "group": "cpu", "risk": "cpu"},
    "cpu_quick": {"cmd": "sudo bash ./bc250-unlock cpu quick", "group": "cpu", "risk": "cpu"},
    "cpu_deep": {"cmd": "sudo bash ./bc250-unlock cpu deep", "group": "cpu", "risk": "cpu"},
    "cpu_rearm_status": {"cmd": "sudo bash ./bc250-unlock cpu rearm status", "group": "cpu", "risk": "normal"},
    "cpu_rearm_enable": {"cmd": "sudo bash ./bc250-unlock cpu rearm enable", "group": "cpu", "risk": "cpu_rearm"},
    "cpu_rearm_disable": {"cmd": "sudo bash ./bc250-unlock cpu rearm disable", "group": "cpu", "risk": "cpu_rearm"},
}


def read_version() -> str:
    try:
        return VERSION_FILE.read_text(encoding="utf-8").strip()
    except OSError:
        return "dev"


def run_capture(args: list[str], timeout: float = 4.0) -> tuple[int, str]:
    try:
        cp = subprocess.run(
            args,
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
            check=False,
        )
        return cp.returncode, cp.stdout.strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 127, str(exc)


def platform_label() -> str:
    rc, out = run_capture(["bash", str(ROOT / "bc250-unlock"), "platform"])
    return out.splitlines()[-1] if rc == 0 and out else "Unknown Linux platform"


def detect_terminal() -> tuple[str | None, list[str] | None]:
    """Return (name, argv prefix). Script path is appended by launch_terminal."""
    # Avoid false positives (for example xterm installed on a headless SSH host).
    if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        return None, None
    custom = os.environ.get("TERMINAL", "").strip()
    if custom:
        parts = shlex.split(custom)
        if parts and shutil.which(parts[0]):
            return parts[0], parts

    # Order favors the desktop environments most likely on CachyOS/SteamOS.
    candidates: list[tuple[str, list[str]]] = [
        ("konsole", ["konsole", "-e"]),
        ("kgx", ["kgx", "--"]),
        ("gnome-terminal", ["gnome-terminal", "--"]),
        ("xfce4-terminal", ["xfce4-terminal", "--command"]),
        ("kitty", ["kitty"]),
        ("alacritty", ["alacritty", "-e"]),
        ("foot", ["foot"]),
        ("terminator", ["terminator", "-x"]),
        ("xterm", ["xterm", "-e"]),
    ]
    for name, prefix in candidates:
        if shutil.which(name):
            return name, prefix
    return None, None


def runtime_dir() -> Path:
    xdg = os.environ.get("XDG_RUNTIME_DIR")
    if xdg:
        path = Path(xdg) / "bc250-cu-unlock-suite-gui"
    elif Path(f"/run/user/{os.getuid()}").is_dir():
        path = Path(f"/run/user/{os.getuid()}") / "bc250-cu-unlock-suite-gui"
    else:
        path = Path(tempfile.gettempdir()) / f"bc250-cu-unlock-suite-gui-{os.getuid()}"
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        path.chmod(0o700)
    except OSError:
        pass
    return path


def launch_terminal(action_id: str) -> dict[str, Any]:
    action = ACTIONS.get(action_id)
    if not action:
        raise KeyError(action_id)
    term_name, prefix = detect_terminal()
    if not prefix:
        return {"ok": False, "error": "no_terminal", "command": action["cmd"]}

    job_id = secrets.token_hex(8)
    rt = runtime_dir()
    status_file = rt / f"job-{job_id}.json"
    runner = rt / f"job-{job_id}.sh"
    command = str(action["cmd"])
    root_q = shlex.quote(str(ROOT))
    status_q = shlex.quote(str(status_file))

    runner.write_text(
        "#!/usr/bin/env bash\n"
        "set +e\n"
        f"cd -- {root_q} || exit 125\n"
        "clear 2>/dev/null || true\n"
        "printf '\\n============================================================\\n'\n"
        "printf ' BC-250 CU Unlock Suite — CLI terminal\\n'\n"
        "printf '============================================================\\n\\n'\n"
        f"printf 'Command: %s\\n\\n' {shlex.quote(command)}\n"
        f"{command}\n"
        "rc=$?\n"
        f"printf '{{\"done\":true,\"rc\":%s,\"finished\":%s}}\\n' \"$rc\" \"$(date +%s)\" > {status_q}\n"
        "printf '\\n------------------------------------------------------------\\n'\n"
        "if [ \"$rc\" -eq 0 ]; then printf 'Finished successfully / Finalizado correctamente (exit 0).\\n'; "
        "else printf 'Command finished with exit code %s / Terminó con código %s. Review / Revisa la salida.\\n' \"$rc\" \"$rc\"; fi\n"
        "printf 'Press Enter / Pulsa Enter para cerrar... '\n"
        "IFS= read -r _ || true\n"
        "exit \"$rc\"\n",
        encoding="utf-8",
    )
    runner.chmod(0o700)

    try:
        if term_name == "xfce4-terminal":
            argv = prefix + [f"bash {shlex.quote(str(runner))}"]
        else:
            argv = prefix + ["bash", str(runner)]
        subprocess.Popen(argv, cwd=ROOT, start_new_session=True)
    except OSError as exc:
        return {"ok": False, "error": "launch_failed", "detail": str(exc), "command": command}

    return {
        "ok": True,
        "job": job_id,
        "terminal": term_name,
        "command": command,
        "risk": action["risk"],
    }


def job_status(job_id: str) -> dict[str, Any]:
    if not job_id or any(ch not in "0123456789abcdef" for ch in job_id.lower()):
        return {"done": False, "error": "invalid_job"}
    path = runtime_dir() / f"job-{job_id}.json"
    if not path.exists():
        return {"done": False}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {"done": False}
    except (OSError, json.JSONDecodeError):
        return {"done": False}


def sudo_cached_live_cus() -> int | None:
    if not shutil.which("sudo"):
        return None
    rc, _ = run_capture(["sudo", "-n", "true"], timeout=1.5)
    if rc != 0:
        return None
    rc, out = run_capture(
        ["sudo", "-n", "bash", str(ROOT / "scripts" / "bc250-status.sh")],
        timeout=5.0,
    )
    if rc != 0:
        return None
    import re

    matches = re.findall(r"CUs active[^:]*:[^0-9]*(\d+)/40", out)
    if not matches:
        matches = re.findall(r"Current routed CUs\s*:\s*(\d+)/40", out)
    return int(matches[-1]) if matches else None


def persistent_profile_cus() -> int | None:
    """Return the saved boot-profile CU count without privileged UMR access."""
    try:
        lines = SERVICE_CONF.read_text(encoding="utf-8").splitlines()
    except OSError:
        return None

    for line in lines:
        if not line.startswith("BC250_WGP_MASKS="):
            continue
        raw = line.split("=", 1)[1].strip()
        parts = [part.strip() for part in raw.split(",") if part.strip()]
        if len(parts) != 4:
            return None
        try:
            masks = [int(part, 0) & 0x1f for part in parts]
        except ValueError:
            return None
        return sum(bin(mask).count("1") * 2 for mask in masks)
    return None


def service_active() -> bool | None:
    if not shutil.which("systemctl"):
        return None
    rc, _ = run_capture(["systemctl", "is-active", "--quiet", SERVICE], timeout=2.0)
    return rc == 0


def service_enabled() -> bool | None:
    if not shutil.which("systemctl"):
        return None
    rc, _ = run_capture(["systemctl", "is-enabled", "--quiet", SERVICE], timeout=2.0)
    if rc == 0:
        return True
    # is-enabled returns nonzero for disabled/not-found. Distinguish not-found only loosely.
    return False


def cpu_rearm_enabled() -> bool | None:
    if not shutil.which("systemctl"):
        return None
    rc, _ = run_capture(["systemctl", "is-enabled", "--quiet", CPU_REARM_SERVICE], timeout=2.0)
    return rc == 0


def cpu_present_threads() -> int | None:
    try:
        text = Path("/sys/devices/system/cpu/present").read_text(encoding="ascii").strip()
    except OSError:
        return None
    total = 0
    try:
        for part in text.split(","):
            if "-" in part:
                lo, hi = part.split("-", 1)
                total += int(hi) - int(lo) + 1
            elif part:
                total += 1
    except ValueError:
        return None
    return total


def action_block_reason(action_id: str) -> str | None:
    """Return a stable reason when the GUI must not launch an action."""
    if action_id in PERSISTENCE_LOCKED_ACTIONS and service_enabled() is True:
        return "persistence_active"
    return None


def info_payload() -> dict[str, Any]:
    term_name, _ = detect_terminal()
    persisted = service_enabled()
    active = service_active()
    live_cus = sudo_cached_live_cus()
    if live_cus is None and persisted is True and active is True:
        live_cus = persistent_profile_cus()
    return {
        "version": read_version(),
        "platform": platform_label(),
        "setupReady": UPSTREAM_MANAGER.is_file() and os.access(UPSTREAM_MANAGER, os.X_OK) and UPSTREAM_VERIFY.is_file() and os.access(UPSTREAM_VERIFY, os.X_OK),
        "terminal": term_name,
        "liveCUs": live_cus,
        "serviceEnabled": persisted,
        "cpuThreads": cpu_present_threads(),
        "cpuRearmEnabled": cpu_rearm_enabled(),
        "mode": "persistent" if persisted is True else "diagnostic",
        "root": str(ROOT),
    }


class GuiHandler(BaseHTTPRequestHandler):
    server_version = "BC250Gui/0.5.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        if getattr(self.server, "verbose", False):
            super().log_message(fmt, *args)

    def _token_ok(self) -> bool:
        parsed = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        supplied = self.headers.get("X-BC250-Token") or (query.get("token") or [""])[0]
        return secrets.compare_digest(supplied, getattr(self.server, "token"))

    def _send_json(self, data: Any, status: int = 200) -> None:
        raw = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(raw)

    def _send_static(self, relative: str) -> None:
        files = {
            "/": GUI_DIR / "index.html",
            "/index.html": GUI_DIR / "index.html",
            "/style.css": GUI_DIR / "style.css",
            "/app.js": GUI_DIR / "app.js",
        }
        path = files.get(relative)
        if not path or not path.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        raw = path.read_bytes()
        if relative in ("/", "/index.html"):
            raw = raw.replace(b"__BC250_TOKEN__", getattr(self.server, "token").encode("ascii"))
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", f"{content_type}; charset=utf-8" if content_type.startswith("text/") else content_type)
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.path.startswith("/api/"):
            if not self._token_ok():
                self._send_json({"error": "forbidden"}, HTTPStatus.FORBIDDEN)
                return
            if parsed.path == "/api/info":
                self._send_json(info_payload())
                return
            if parsed.path == "/api/actions":
                safe = {k: {"command": v["cmd"], "group": v["group"], "risk": v["risk"]} for k, v in ACTIONS.items()}
                self._send_json(safe)
                return
            if parsed.path == "/api/job":
                q = urllib.parse.parse_qs(parsed.query)
                self._send_json(job_status((q.get("id") or [""])[0]))
                return
            self._send_json({"error": "not_found"}, HTTPStatus.NOT_FOUND)
            return
        self._send_static(parsed.path)

    def do_POST(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlsplit(self.path)
        if not self._token_ok():
            self._send_json({"error": "forbidden"}, HTTPStatus.FORBIDDEN)
            return
        if parsed.path == "/api/launch":
            try:
                size = min(int(self.headers.get("Content-Length", "0")), 4096)
                payload = json.loads(self.rfile.read(size) or b"{}")
                action = str(payload.get("action", ""))
                if action not in ACTIONS:
                    self._send_json({"error": "unknown_action"}, HTTPStatus.BAD_REQUEST)
                    return
                blocked = action_block_reason(action)
                if blocked:
                    self._send_json(
                        {
                            "error": blocked,
                            "detail": "Boot persistence is enabled; diagnostic/routing tests are locked until persistence is removed.",
                            "command": ACTIONS[action]["cmd"],
                        },
                        HTTPStatus.CONFLICT,
                    )
                    return
                self._send_json(launch_terminal(action))
            except (ValueError, json.JSONDecodeError) as exc:
                self._send_json({"error": "bad_request", "detail": str(exc)}, HTTPStatus.BAD_REQUEST)
            return
        if parsed.path == "/api/stop":
            self._send_json({"ok": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        self._send_json({"error": "not_found"}, HTTPStatus.NOT_FOUND)


def self_test() -> int:
    required = [GUI_DIR / "index.html", GUI_DIR / "style.css", GUI_DIR / "app.js", ROOT / "bc250-unlock"]
    missing = [str(p) for p in required if not p.is_file()]
    bad = [k for k, v in ACTIONS.items() if not v.get("cmd") or v.get("risk") not in {"normal", "write", "persist", "system", "cpu", "cpu_rearm"}]
    bad_locked = sorted(PERSISTENCE_LOCKED_ACTIONS.difference(ACTIONS))
    if missing or bad or bad_locked:
        print(json.dumps({"ok": False, "missing": missing, "badActions": bad, "badPersistenceLocks": bad_locked}, indent=2))
        return 1
    print(json.dumps({"ok": True, "version": read_version(), "actions": len(ACTIONS), "persistenceLockedActions": len(PERSISTENCE_LOCKED_ACTIONS), "terminal": detect_terminal()[0]}, indent=2))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="BC-250 CU Unlock Suite local graphical guide")
    parser.add_argument("--no-browser", action="store_true", help="print URL without opening the default browser")
    parser.add_argument("--port", type=int, default=0, help="localhost port (default: random free port)")
    parser.add_argument("--verbose", action="store_true", help="log HTTP requests")
    parser.add_argument("--self-test", action="store_true", help="validate GUI files/action registry and exit")
    args = parser.parse_args()

    if args.self_test:
        return self_test()
    if os.geteuid() == 0:
        print("[bc250-gui] ERROR: start the graphical mode WITHOUT sudo.", file=sys.stderr)
        print("[bc250-gui] Use: ./bc250-unlock gui", file=sys.stderr)
        print("[bc250-gui] Privileged actions open a terminal and ask for sudo there.", file=sys.stderr)
        return 2
    if not shutil.which("python3"):
        print("[bc250-gui] ERROR: python3 is required.", file=sys.stderr)
        return 2

    token = secrets.token_urlsafe(24)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), GuiHandler)
    server.token = token  # type: ignore[attr-defined]
    server.verbose = args.verbose  # type: ignore[attr-defined]
    host, port = server.server_address[:2]
    url = f"http://{host}:{port}/?token={urllib.parse.quote(token)}"

    print(f"[bc250-gui] BC-250 CU Unlock Suite {read_version()}")
    print("[bc250-gui] Local-only interface. No network listener beyond 127.0.0.1.")
    print(f"[bc250-gui] {url}")
    print("[bc250-gui] Keep this terminal open while using the graphical guide. Ctrl+C stops it.")
    if not args.no_browser:
        threading.Timer(0.35, lambda: webbrowser.open(url, new=1)).start()

    try:
        server.serve_forever(poll_interval=0.3)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    print("[bc250-gui] stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
