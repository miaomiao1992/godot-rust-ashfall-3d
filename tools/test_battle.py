"""Exercise optional bots, hot join and combat feature replication over ENet."""
import subprocess
import time
from test_lan import launch, jobs

host = launch("battle-host", ["--battle-host"])
deadline = time.monotonic() + 30
while not any("BATTLE_NET READY" in line for line in host) and time.monotonic() < deadline:
    time.sleep(0.1)
launch("battle-client", ["--battle-client"])
failed = False
for name, process, lines, thread in jobs:
    try:
        code = process.wait(timeout=100)
    except subprocess.TimeoutExpired:
        process.kill()
        code = 1
    thread.join(timeout=2)
    print(f"=== {name}: exit {code} ===")
    print("\n".join(lines))
    if code or not any("BATTLE_NET RESULT PASS" in line for line in lines) or any("SCRIPT ERROR" in line or "ERROR:" in line for line in lines):
        failed = True
raise SystemExit(1 if failed else 0)
