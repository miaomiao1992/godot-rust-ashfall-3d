"""Original, seamless direction-space skies inspired by the Skybox Sampler approach.

Requires NumPy. Generates the project's own artwork; no sampler images are copied.
Run with python3.11 tools/generate_skies.py (2048 x 1024 RGB panoramas).
"""
from pathlib import Path
import struct
import zlib
import numpy as np

ROOT = Path(__file__).resolve().parent.parent


def noise(p):
    p = p.astype(np.float32, copy=False)
    cell = np.floor(p)
    f = p - cell
    f = f * f * (3.0 - 2.0 * f)
    result = np.zeros(p.shape[:-1], dtype=np.float32)
    for x in range(2):
        for y in range(2):
            for z in range(2):
                phase = (cell[..., 0]+x)*127.1 + (cell[..., 1]+y)*311.7 + (cell[..., 2]+z)*74.7
                h = np.sin(phase) * 43758.5453
                h = h - np.floor(h)
                weight = (f[..., 0] if x else 1-f[..., 0]) * (f[..., 1] if y else 1-f[..., 1]) * (f[..., 2] if z else 1-f[..., 2])
                result += h * weight
    return result


def fbm(p, octaves=5):
    total = np.zeros(p.shape[:-1], dtype=np.float32)
    amplitude = 0.55
    for _ in range(octaves):
        total += noise(p) * amplitude
        p = p * 2.03 + np.array((7.31, -2.8, 1.19), dtype=np.float32)
        amplitude *= 0.48
    return total


def smooth(low, high, x):
    t = np.clip((x-low)/(high-low), 0, 1)
    return t*t*(3-2*t)


def save_png(path, rgb):
    h, w, _ = rgb.shape
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind+data) & 0xffffffff)
    rows = b''.join(b'\0' + row.tobytes() for row in rgb)
    data = b'\x89PNG\r\n\x1a\n'
    data += chunk(b'IHDR', struct.pack('!2I5B', w, h, 8, 2, 0, 0, 0))
    data += chunk(b'IDAT', zlib.compress(rows, 8)) + chunk(b'IEND', b'')
    path.write_bytes(data)


def shade(d, storm):
    altitude = np.clip(d[..., 1], 0, 1)
    sun = np.array((-0.57, 0.19, -0.8), dtype=np.float32)
    sun /= np.linalg.norm(sun)
    toward_sun = np.clip(np.sum(d*sun, axis=-1), -1, 1)
    zenith = np.array((0.12, 0.20, 0.29) if not storm else (0.065, 0.105, 0.17))
    horizon = np.array((0.67, 0.49, 0.32) if not storm else (0.37, 0.46, 0.50))
    gradient = np.power(altitude, 0.42)[..., None]
    color = horizon*(1-gradient) + zenith*gradient
    glow = np.exp((toward_sun-1)*10.0) * np.exp(-altitude*1.4)
    color += glow[..., None] * ((0.22, 0.10, 0.025) if not storm else (0.075, 0.08, 0.065))
    warp = fbm(d*2.2 + (11, 8, -4), 3)
    p = d * (5.0, 7.5, 5.0) + warp[..., None]*1.7 + (1, 3, 2)
    cloud_noise = fbm(p, 6)
    cover = smooth(0.33 if storm else 0.40, 0.59 if storm else 0.66, cloud_noise)
    cover *= smooth(0.015, 0.13, altitude)
    light = smooth(0.20, 0.64, fbm(p + sun*0.55, 4))
    shadow = np.array((0.19, 0.21, 0.25) if not storm else (0.105, 0.14, 0.19))
    lit = np.array((0.76, 0.62, 0.48) if not storm else (0.43, 0.49, 0.53))
    cloud_color = shadow*(1-light[..., None]) + lit*light[..., None]
    silver = np.exp((toward_sun-1)*22) * (1-cover) * cover
    cloud_color += silver[..., None] * (0.50, 0.30, 0.12)
    color = color*(1-cover[..., None]) + cloud_color*cover[..., None]
    wisps = smooth(0.57, 0.75, fbm(d*(17, 3, 17)+(33, 5, 18), 3))
    wisps *= smooth(0.12, 0.45, altitude)*0.19
    color = color*(1-wisps[..., None]) + np.array((0.61, 0.63, 0.65))*wisps[..., None]
    disc = np.exp((toward_sun-1)*5200)*(1-cover)**2
    color += disc[..., None]*((1.3, 0.84, 0.43) if not storm else (0.5, 0.48, 0.39))
    ground = np.array((0.12, 0.105, 0.10) if not storm else (0.085, 0.12, 0.14))
    below = smooth(0, 0.14, -d[..., 1])[..., None]
    color = color*(1-below)+ground*below
    rgb = (np.clip(color, 0, 1)*255+0.5).astype(np.uint8)
    return rgb


def sky(storm):
    w, h = 2048, 1024
    longitude = np.linspace(-np.pi, np.pi, w, dtype=np.float32)
    latitude = np.linspace(np.pi/2, -np.pi/2, h, dtype=np.float32)
    tiles = []
    for start in range(0, h, 64):
        lon, lat = np.meshgrid(longitude, latitude[start:start+64])
        d = np.stack((np.cos(lat)*np.sin(lon), np.sin(lat), np.cos(lat)*np.cos(lon)), axis=-1)
        tiles.append(shade(d, storm))
    rgb = np.concatenate(tiles)
    rgb[:, -1] = rgb[:, 0]
    rgb[0] = rgb[0, 0]
    rgb[-1] = rgb[-1, 0]
    return rgb


if __name__ == '__main__':
    output = ROOT/'assets'/'skies'
    output.mkdir(exist_ok=True)
    for name, storm in [('highway_dusk', False), ('harbor_overcast', True)]:
        path = output/(name+'.png')
        rgb = sky(storm)
        assert np.array_equal(rgb[:, 0], rgb[:, -1])
        save_png(path, rgb)
        print(f'Generated {path.name}: 2048x1024, seamless, {path.stat().st_size/1048576:.2f} MiB')
