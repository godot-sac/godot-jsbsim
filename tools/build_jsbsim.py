"""Build JSBSim (thirdparty/jsbsim) as a shared library with its own CMake build.

JSBSim is LGPL-2.1, so godot-jsbsim links it dynamically: this script builds the JSBSim shared library, copies it
next to the GDExtension in addons/jsbsim/bin/<platform>/ and puts the link-time files (Windows import library)
in build/jsbsim/<platform>/lib/. The SConstruct links against those.

Usage (from the repository root):
    tools/.venv/Scripts/python.exe tools/build_jsbsim.py [--jobs N] [--clean]

Windows uses the Visual Studio 2022 generator (no developer prompt needed), Linux and macOS the default generator.
"""

from __future__ import annotations

import argparse
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "thirdparty" / "jsbsim"


def godot_platform() -> str:
    system = platform.system()
    return {"Windows": "windows", "Linux": "linux", "Darwin": "macos"}[system]


def find_cmake() -> str:
    # Prefer the cmake from tools/.venv (pinned in requirements.txt), then PATH.
    scripts = Path(sys.executable).parent
    for name in ("cmake.exe", "cmake"):
        if (scripts / name).exists():
            return str(scripts / name)
    found = shutil.which("cmake")
    if not found:
        sys.exit("cmake not found: install tools/requirements.txt into tools/.venv")
    return found


def run(cmd: list[str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--clean", action="store_true", help="delete the CMake build directory first")
    parser.add_argument("--arch", default="", help="macOS: CMAKE_OSX_ARCHITECTURES, e.g. 'arm64;x86_64'")
    args = parser.parse_args()

    if not (SOURCE / "CMakeLists.txt").exists():
        sys.exit("thirdparty/jsbsim is empty: run `git submodule update --init --recursive`")

    plat = godot_platform()
    build_dir = ROOT / "build" / "jsbsim" / plat
    cmake_dir = build_dir / "cmake"
    if args.clean and cmake_dir.exists():
        shutil.rmtree(cmake_dir)

    cmake = find_cmake()
    configure = [
        cmake, "-S", str(SOURCE), "-B", str(cmake_dir),
        "-DBUILD_SHARED_LIBS=ON",
        "-DBUILD_PYTHON_MODULE=OFF",
        "-DBUILD_DOCS=OFF",
        "-DCMAKE_BUILD_TYPE=Release",
    ]
    if plat == "windows":
        # /utf-8: the JSBSim sources are UTF-8; without it MSVC warns (C4819) on non-English code pages.
        configure += ["-G", "Visual Studio 17 2022", "-A", "x64", "-DCMAKE_CXX_FLAGS_INIT=/utf-8"]
    if plat == "macos" and args.arch:
        configure.append(f"-DCMAKE_OSX_ARCHITECTURES={args.arch}")
    run(configure)
    run([cmake, "--build", str(cmake_dir), "--config", "Release", "--target", "libJSBSim", "--parallel", str(args.jobs)])

    out = cmake_dir / "src"
    if plat == "windows":
        out = out / "Release"
    bin_dir = ROOT / "addons" / "jsbsim" / "bin" / plat
    lib_dir = build_dir / "lib"
    bin_dir.mkdir(parents=True, exist_ok=True)
    lib_dir.mkdir(parents=True, exist_ok=True)

    if plat == "windows":
        shutil.copy2(out / "JSBSim.dll", bin_dir / "JSBSim.dll")
        shutil.copy2(out / "JSBSim.lib", lib_dir / "JSBSim.lib")
    elif plat == "linux":
        # Runtime file is the SONAME (libJSBSim.so.1); the linker needs the plain name.
        real = max(out.glob("libJSBSim.so.*.*"), key=lambda p: len(p.name))
        soname = "libJSBSim.so." + real.name.split(".so.")[1].split(".")[0]
        shutil.copy2(real, bin_dir / soname)
        shutil.copy2(real, lib_dir / "libJSBSim.so")
    else:
        real = next(p for p in out.glob("libJSBSim.*.dylib") if p.name.count(".") == 2)
        shutil.copy2(real, bin_dir / real.name)
        shutil.copy2(real, lib_dir / "libJSBSim.dylib")
    print(f"JSBSim shared library -> {bin_dir.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
