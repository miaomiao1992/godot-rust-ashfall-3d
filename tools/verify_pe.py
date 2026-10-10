"""Inspect real PE import/export tables without relying on filename extensions."""
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parent.parent


class PE:
    def __init__(self, path):
        self.data = path.read_bytes()
        offset = self.u32(0x3C)
        assert self.data[offset:offset + 4] == b"PE\0\0", "Not a PE executable"
        assert self.u16(offset + 4) == 0x8664, "Not Windows x64"
        count = self.u16(offset + 6)
        optional_size = self.u16(offset + 20)
        self.optional = offset + 24
        assert self.u16(self.optional) == 0x20B, "Not PE32+"
        self.sections = []
        for i in range(count):
            section = self.optional + optional_size + i * 40
            self.sections.append((self.u32(section + 12), self.u32(section + 8), self.u32(section + 20), self.u32(section + 16)))

    def u16(self, offset):
        return struct.unpack_from("<H", self.data, offset)[0]

    def u32(self, offset):
        return struct.unpack_from("<I", self.data, offset)[0]

    def file_offset(self, rva):
        for virtual, virtual_size, raw, raw_size in self.sections:
            if virtual <= rva < virtual + max(virtual_size, raw_size):
                return raw + rva - virtual
        raise ValueError(f"RVA outside sections: {rva:#x}")

    def string(self, rva):
        offset = self.file_offset(rva)
        return self.data[offset:self.data.index(0, offset)].decode("ascii")

    def imports(self):
        rva = self.u32(self.optional + 120)
        if not rva:
            return []
        cursor = self.file_offset(rva)
        result = []
        while any(self.data[cursor:cursor + 20]):
            result.append(self.string(self.u32(cursor + 12)))
            cursor += 20
        return result

    def exports(self):
        rva = self.u32(self.optional + 112)
        if not rva:
            return []
        table = self.file_offset(rva)
        names = self.file_offset(self.u32(table + 32))
        return [self.string(self.u32(names + i * 4)) for i in range(self.u32(table + 24))]


if __name__ == "__main__":
    folder = ROOT / "dist" / "ASHFALL-Windows64"
    for name in ["ASHFALL.exe", "ashfall_core.dll"]:
        pe = PE(folder / name)
        print(f"PE VERIFIED: {name} / Windows x64")
        imports = pe.imports()
        print("DLL dependencies:", ", ".join(imports))
        assert not any("libgcc" in dll.lower() or "libstdc++" in dll.lower() or "libwinpthread" in dll.lower() for dll in imports), "Unbundled MinGW dependency"
        if name.endswith(".dll"):
            assert "gdext_rust_init" in pe.exports(), "Missing Godot extension entry point"
            print("EXPORT VERIFIED: gdext_rust_init")
    print("PE VALIDATION COMPLETE")
