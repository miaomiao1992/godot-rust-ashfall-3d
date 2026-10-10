"""Package the verified Windows export, including licenses and a checksum."""
import hashlib
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
FOLDER = DIST / "ASHFALL-Windows64"

if __name__ == "__main__":
    for name in ["ASHFALL.exe", "ASHFALL.pck", "ashfall_core.dll"]:
        if not (FOLDER / name).is_file():
            raise SystemExit(f"Missing Windows runtime file: {name}")
    shutil.copy2(ROOT / "THIRD_PARTY_ASSETS.md", FOLDER / "THIRD_PARTY_ASSETS.md")
    shutil.copy2(ROOT / "docs" / "windows-readme.txt", FOLDER / "README-游玩说明.txt")
    shutil.copy2(ROOT / "docs" / "Godot-MIT.txt", FOLDER / "LICENSE-Godot.txt")
    archive = DIST / "ASHFALL-Windows64-v0.2.1.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as output:
        for path in sorted(FOLDER.rglob("*")):
            if path.is_file():
                output.write(path, path.relative_to(DIST))
    with zipfile.ZipFile(archive) as package:
        assert package.testzip() is None, "ZIP CRC check failed"
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (DIST / "ASHFALL-Windows64-v0.2.1.sha256").write_text(f"{digest}  {archive.name}\n")
    shutil.copy2(archive, DIST / "ASHFALL-Windows64.zip")
    (DIST / "ASHFALL-Windows64.sha256").write_text(f"{digest}  ASHFALL-Windows64.zip\n")
    print(f"Windows package: {archive} ({archive.stat().st_size / 1048576:.1f} MiB)")
    print(f"SHA256: {digest}")
