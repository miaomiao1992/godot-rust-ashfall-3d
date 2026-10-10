#!/usr/bin/env python3
"""Adapt rustc's GNU linker flags for Zig 0.13's Windows COFF backend."""
import os
import sys

args = []
skip = {"-l:libpthread.a", "-lgcc", "-lmsvcrt", "-Wl,--disable-auto-image-base", "-Wl,--dynamicbase", "-Wl,-Bdynamic"}
for arg in sys.argv[1:]:
    if arg in skip or (arg.startswith("-Wl,") and arg.endswith("/list.def")):
        continue
    if "libcompiler_builtins-" in arg and arg.endswith(".rlib"):
        continue
    args.append("-lc++" if arg == "-lgcc_eh" else arg)
os.execvp("zig", ["zig", "cc", "-target", "x86_64-windows-gnu", *args])
