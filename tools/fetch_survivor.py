"""Fetch the CC0 rigged soldier from Grab3D for offline game conversion."""
from pathlib import Path
import hashlib
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
URL = "https://grab3d.com/dl/soldier-rigged/soldier-rigged.glb"
SHA256 = "b1f32017868a6f951c21c45b84646696431e6b4c813d563af37944123f673a59"
DESTINATION = ROOT / "tools" / "sources" / "survivor-soldier.glb"

if __name__ == "__main__":
    request = urllib.request.Request(URL, headers={"User-Agent": "ASHFALL asset downloader"})
    with urllib.request.urlopen(request, timeout=90) as response:
        data = response.read()
    if data[:4] != b"glTF":
        raise ValueError("Expected a GLB model, received a different response")
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise ValueError("Source model changed; inspect its content and license before updating")
    DESTINATION.write_bytes(data)
    print(f"Downloaded {DESTINATION.name}: {len(data):,} bytes")
    print("Source:", URL)
    print("License: https://grab3d.com/license/ (CC0 1.0)")
    print("SHA256:", hashlib.sha256(data).hexdigest())
