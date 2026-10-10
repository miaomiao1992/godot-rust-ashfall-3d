"""Package the verified Windows export, including licenses and a checksum."""
import hashlib
from pathlib import Path
import shutil
import zipfile
import sys

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
LAN = "--lan" in sys.argv
FOLDER = DIST / ("ASHFALL-LAN-Windows64" if LAN else "ASHFALL-Windows64")
EXECUTABLE = "ASHFALL-LAN" if LAN else "ASHFALL"
ARCHIVE = "ASHFALL-LAN-Windows64-v0.3.1" if LAN else "ASHFALL-Windows64-v0.2.1"

if __name__ == "__main__":
    for name in [EXECUTABLE + ".exe", EXECUTABLE + ".pck", "ashfall_core.dll"]:
        if not (FOLDER / name).is_file():
            raise SystemExit(f"Missing Windows runtime file: {name}")
    shutil.copy2(ROOT / "THIRD_PARTY_ASSETS.md", FOLDER / "THIRD_PARTY_ASSETS.md")
    shutil.copy2(ROOT / "docs" / ("lan-readme.txt" if LAN else "windows-readme.txt"), FOLDER / "README-游玩说明.txt")
    shutil.copy2(ROOT / "docs" / "Godot-MIT.txt", FOLDER / "LICENSE-Godot.txt")
    archive = DIST / (ARCHIVE + ".zip")
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as output:
        for path in sorted(FOLDER.rglob("*")):
            if path.is_file():
                output.write(path, path.relative_to(DIST))
    with zipfile.ZipFile(archive) as package:
        assert package.testzip() is None, "ZIP CRC check failed"
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (DIST / (ARCHIVE + ".sha256")).write_text(f"{digest}  {archive.name}\n")
    alias = "ASHFALL-LAN-Windows64" if LAN else "ASHFALL-Windows64"
    shutil.copy2(archive, DIST / (alias + ".zip"))
    (DIST / (alias + ".sha256")).write_text(f"{digest}  {alias}.zip\n")
    print(f"Windows package: {archive} ({archive.stat().st_size / 1048576:.1f} MiB)")
    print(f"SHA256: {digest}")
