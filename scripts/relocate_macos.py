#!/usr/bin/env python3
"""Makes a staged macOS rizin bundle relocatable: every Mach-O file refers to the others by a path relative to itself
(@loader_path/...), never by the absolute folder it was built or installed into, and is ad-hoc signed again (changing a
load command invalidates the signature, and an arm64 binary will not run without one). The Developer ID signature is
put on at release time by the application's own signing step, after this.

usage: relocate_macos.py <stage root>
"""
import os
import subprocess
import sys


def run(*cmd: str) -> str:
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


def is_macho(path: str) -> bool:
    if os.path.islink(path) or not os.path.isfile(path):
        return False
    with open(path, "rb") as f:
        magic = f.read(4)
    return magic in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xfe\xed\xfa\xcf", b"\xbe\xba\xfe\xca")


def main() -> int:
    stage = os.path.realpath(sys.argv[1])
    files = [os.path.join(d, f) for d, _, fs in os.walk(stage) for f in fs if is_macho(os.path.join(d, f))]
    by_name = {}
    for f in files:
        by_name.setdefault(os.path.basename(f), f)

    for f in files:
        here = os.path.dirname(f)
        lines = run("otool", "-L", f).splitlines()[1:]
        deps = [ln.strip().split(" (")[0] for ln in lines]
        for dep in deps:
            real = os.path.realpath(dep) if dep.startswith("/") and os.path.exists(dep) else dep
            target = None
            if dep.startswith(stage) or real.startswith(stage):
                target = real if real.startswith(stage) else dep
            elif dep.startswith("@rpath/") or dep.startswith("@executable_path/"):
                target = by_name.get(os.path.basename(dep))
            elif not dep.startswith(("/usr/lib/", "/System/", "@loader_path/")):
                target = by_name.get(os.path.basename(dep))      # an absolute path from the build machine (/usr/local/lib/...)
            if target is None:
                continue
            new = "@loader_path/" + os.path.relpath(target, here)
            if new != dep:
                run("install_name_tool", "-change", dep, new, f)
        if f.endswith(".dylib"):
            run("install_name_tool", "-id", "@loader_path/" + os.path.basename(f), f)
        # a leftover absolute rpath from the build tree would still point outside the bundle
        for ln in run("otool", "-l", f).splitlines():
            ln = ln.strip()
            if ln.startswith("path ") and os.path.isabs(ln.split(" (")[0][5:]):
                rp = ln.split(" (")[0][5:]
                subprocess.run(["install_name_tool", "-delete_rpath", rp, f], capture_output=True)

    for f in files:
        run("codesign", "--force", "--sign", "-", f)

    # verify: nothing refers outside the bundle or the system
    bad = []
    for f in files:
        for ln in run("otool", "-L", f).splitlines()[1:]:
            dep = ln.strip().split(" (")[0]
            if dep.startswith(("/usr/lib/", "/System/", "@loader_path/")) or dep == os.path.basename(f):
                continue
            bad.append((os.path.relpath(f, stage), dep))
    if bad:
        for f, dep in bad:
            print(f"NOT RELOCATABLE: {f} -> {dep}", file=sys.stderr)
        return 1
    print(f"relocated and re-signed {len(files)} Mach-O files; none refers outside the bundle")
    return 0


if __name__ == "__main__":
    sys.exit(main())
