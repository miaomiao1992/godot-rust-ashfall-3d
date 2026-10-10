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
    process = subprocess.Popen(["godot", *([] if RENDER else ["--headless"]), "--path", str(ROOT), "--", *args], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    lines = []
    def reader():
        for line in process.stdout:
            lines.append(line.rstrip())
    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    jobs.append((name, process, lines, thread))

if __name__ == "__main__":
    full = "--four" in sys.argv
    scenario = "--scenario" in sys.argv
    extra = ["--scenario"] if scenario else []
    if RENDER: extra.append("--lan-photo")
    launch("host", ["--lan-host", "--duration=33" if scenario else "--duration=24" if full else "--duration=12", *extra])
    time.sleep(2)
    launch("client-1", ["--lan-client", "--duration=30" if scenario else "--duration=20" if full else "--duration=9", *extra])
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
            code = process.wait(timeout=60)
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
