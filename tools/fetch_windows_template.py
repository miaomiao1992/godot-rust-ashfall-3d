"""Fetch only the official x64 Windows release template from the 1.2 GB ZIP.

HTTP range reads + zipfile CRC validation avoid downloading unrelated platforms.
"""

import io
from pathlib import Path
import urllib.request
import zipfile
import time

URL = "https://github.com/godotengine/godot-builds/releases/download/4.7-stable/Godot_v4.7-stable_export_templates.tpz"


class RemoteZip(io.RawIOBase):
    def __init__(self, url):
        request = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(request, timeout=120) as response:
            self.url = response.geturl()
            self.length = int(response.headers["Content-Length"])
        self.position = 0
        self.cache = {}

    def seekable(self):
        return True

    def seek(self, offset, whence=0):
        self.position = offset if whence == 0 else self.position + offset if whence == 1 else self.length + offset
        return self.position

    def tell(self):
        return self.position

    def read(self, size=-1):
        if size < 0:
            size = self.length - self.position
        end = min(self.position + size, self.length)
        if end <= self.position:
            return b""
        key = (self.position, end)
        if key not in self.cache:
            chunks = []
            cursor = self.position
            while cursor < end:
                chunk_end = min(cursor + 2 * 1024 * 1024, end)
                for attempt in range(5):
                    try:
                        req = urllib.request.Request(self.url, headers={"Range": f"bytes={cursor}-{chunk_end - 1}", "Accept-Encoding": "identity"})
                        with urllib.request.urlopen(req, timeout=180) as response:
                            if response.status != 206:
                                raise RuntimeError("Server does not honor byte ranges")
                            data = response.read()
                            if len(data) != chunk_end - cursor:
                                raise RuntimeError("Incomplete range response")
                            chunks.append(data)
                        break
                    except Exception:
                        if attempt == 4:
                            raise
                        time.sleep(2 + attempt)
                cursor = chunk_end
            self.cache[key] = b"".join(chunks)
        self.position = end
        return self.cache[key]


if __name__ == "__main__":
    destination = Path(__file__).resolve().parent / "templates"
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(RemoteZip(URL)) as archive:
        name = "templates/windows_release_x86_64.exe"
        data = archive.read(name)
        (destination / "windows_release_x86_64.exe").write_bytes(data)
        print(f"Official Windows x64 template: {len(data):,} bytes (ZIP CRC verified)")
