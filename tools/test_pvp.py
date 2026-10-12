"""Run real PvP ENet processes, optionally with all ten slots or rendered UI."""
import sys
import time
import subprocess
from test_lan import launch, jobs

players = 10 if "--ten" in sys.argv else 2
extra = [f"--players={players}"]
if "--render" in sys.argv:
    extra.append("--pvp-photo")
host_lines = launch("pvp-host", ["--pvp-host", *extra])
deadline = time.monotonic() + 30
while not any("PVP_TEST LOBBY" in line for line in host_lines) and time.monotonic() < deadline:
    time.sleep(0.1)
for index in range(players - 1):
    launch(f"pvp-client-{index + 1}", ["--pvp-client", *extra])
    time.sleep(0.3)
failed = False
for name, process, lines, thread in jobs:
    try:
        code = process.wait(timeout=120)
    except subprocess.TimeoutExpired:
        process.kill()
        code = 1
    thread.join(timeout=2)
    print(f"=== {name}: exit {code} ===")
    print("\n".join(lines))
    if code or not any("PVP_TEST RESULT PASS" in line for line in lines) or any("SCRIPT ERROR" in line or "ERROR:" in line for line in lines):
        failed = True
raise SystemExit(1 if failed else 0)
