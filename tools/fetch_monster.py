from fetch_windows_template import RemoteZip
import zipfile
import sys
from pathlib import Path

name = sys.argv[1] if len(sys.argv) > 1 else "Colors"
with zipfile.ZipFile(RemoteZip(f"https://opengameart.org/sites/default/files/{name}.zip")) as archive:
    for info in archive.infolist():
        print(info.filename, info.file_size)
        if len(sys.argv) > 2 and any(token.lower() in info.filename.lower() for token in sys.argv[2:]) and not info.is_dir() and not info.filename.startswith("__MACOSX"):
            destination = Path(__file__).resolve().parent / "sources" / "horror-monster"
            destination.mkdir(parents=True, exist_ok=True)
            (destination / Path(info.filename).name).write_bytes(archive.read(info.filename))
            print("EXTRACTED:", info.filename)
