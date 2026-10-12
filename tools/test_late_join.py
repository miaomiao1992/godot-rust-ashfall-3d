"""Verify persistent mid-match team selection using real host/client processes."""
import subprocess
import threading
import time
import sys


def launch(role):
    lines = []
    display = ["--rendering-method", "gl_compatibility"] if "--render" in sys.argv and role == "client" else ["--headless"]
    process = subprocess.Popen(
        ["godot", *display, "-s", "tests/late_join_flow.gd", "--", f"--late-{role}"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )

    def collect():
        for line in process.stdout:
            lines.append(line.rstrip())

    worker = threading.Thread(target=collect, daemon=True)
    worker.start()
    return role, process, lines, worker


host = launch("host")
deadline = time.monotonic() + 30
while "LATE_JOIN_HOST_READY" not in host[2] and time.monotonic() < deadline:
    time.sleep(0.1)
jobs = [host, launch("client")]
failed = False
for role, process, lines, worker in jobs:
    try:
        code = process.wait(timeout=60)
    except subprocess.TimeoutExpired:
        process.kill()
        code = 1
    worker.join(timeout=2)
    print(f"LATE_JOIN_PROCESS {role} exit={code}")
    print("\n".join(lines))
    if code or "LATE_JOIN RESULT: 0 failures" not in lines or any("ERROR:" in s for s in lines):
        failed = True
raise SystemExit(1 if failed else 0)
