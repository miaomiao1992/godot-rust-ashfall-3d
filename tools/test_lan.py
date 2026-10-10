"""Run actual ENet host/client processes and retain bounded logs for diagnostics."""
from pathlib import Path
import subprocess
import threading
import time
import sys

ROOT = Path(__file__).resolve().parent.parent
jobs = []
RENDER = "--render" in sys.argv

def launch(name, args):
    started = time.monotonic()
    process = subprocess.Popen(["godot", *(["--resolution", "640x400", "--max-fps", "60"] if RENDER else ["--headless"]), "--path", str(ROOT), "--", *args], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    lines = []
    def reader():
        for line in process.stdout:
            lines.append(f"[{time.monotonic() - started:.2f}s] {line.rstrip()}")
    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    jobs.append((name, process, lines, thread))
    return lines

if __name__ == "__main__":
    full = "--four" in sys.argv
    scenario = "--scenario" in sys.argv
    extra = ["--scenario"] if scenario else []
    if RENDER: extra.append("--lan-photo")
    host_lines = launch("host", ["--lan-host", "--duration=45" if scenario else "--duration=40" if full else "--duration=45" if RENDER else "--duration=16", *extra])
    deadline = time.monotonic() + 30
    while not any("LAN_TEST STATE" in line for line in host_lines) and time.monotonic() < deadline:
        time.sleep(0.1)
    launch("client-1", ["--lan-client", "--duration=30" if scenario else "--duration=20" if full else "--duration=30" if RENDER else "--duration=9", *extra])
    if full:
        time.sleep(4)
        launch("hot-client-2", ["--lan-client", "--duration=16"])
        time.sleep(2)
        launch("hot-client-3", ["--lan-client", "--duration=14"])
        time.sleep(2)
        launch("full-rejection", ["--lan-client", "--duration=5", "--expect-full"])
    failed = False
    for name, process, lines, thread in jobs:
        try:
            code = process.wait(timeout=120 if RENDER else 60)
        except subprocess.TimeoutExpired:
            process.kill()
            code = 1
            lines.append("TIMEOUT")
        thread.join(timeout=2)
        print(f"=== {name}: exit {code} ===")
        for line in lines:
            print(line)
        if code or not any("LAN_TEST RESULT PASS" in line for line in lines) or any("SCRIPT ERROR" in line or "ERROR:" in line for line in lines):
            failed = True
    raise SystemExit(1 if failed else 0)
