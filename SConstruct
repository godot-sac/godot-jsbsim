#!/usr/bin/env python
# Builds the godot-jsbsim GDExtension: godot-cpp + src/, linked dynamically against the JSBSim shared library.
# Build JSBSim first: tools/.venv/Scripts/python.exe tools/build_jsbsim.py
# Usage (from the repo root): tools/.venv/Scripts/scons [target=template_debug|template_release] [-j16]
import os

# JSBSim reports errors with C++ exceptions, so this extension is built with exception handling (godot-cpp turns
# it off by default). JSBSim's API passes std::string and other STL objects across the DLL boundary, so on Windows
# both libraries must use the same shared C runtime (/MD), not godot-cpp's default static one (/MT).
ARGUMENTS.setdefault("disable_exceptions", "no")
ARGUMENTS.setdefault("use_static_cpp", "no")

env = SConscript("thirdparty/godot-cpp/SConstruct", {"api_version": "4.3"})

platform = env["platform"]
jsbsim_lib_dir = "build/jsbsim/{}/lib".format(platform)
if not os.path.isdir(jsbsim_lib_dir):
    print("JSBSim is not built for {0}: run tools/build_jsbsim.py first ({1} is missing).".format(platform, jsbsim_lib_dir))
    Exit(1)

env.Append(CPPPATH=["src/", "thirdparty/jsbsim/src/"], LIBPATH=[jsbsim_lib_dir], LIBS=["JSBSim"])
if platform == "windows":
    # The JSBSim headers use M_PI and friends; on Windows JSBSim's CMake defines this for its own users.
    env.Append(CPPDEFINES=["_USE_MATH_DEFINES"])
    if not env.get("use_mingw"):
        env.Append(CXXFLAGS=["/utf-8"])
elif platform == "linux":
    # Find libJSBSim.so.1 next to our library at run time.
    env.Append(LINKFLAGS=["-Wl,-rpath,'$$ORIGIN'"])
elif platform == "macos":
    env.Append(LINKFLAGS=["-Wl,-rpath,@loader_path"])

# Keep Godot from importing the object files in build/.
os.makedirs("build", exist_ok=True)
open(os.path.join("build", ".gdignore"), "a").close()

sources = Glob("src/*.cpp") + Glob("src/*/*.cpp")
library = env.SharedLibrary(
    "addons/jsbsim/bin/{}/libgodot_jsbsim{}{}".format(platform, env["suffix"], env["SHLIBSUFFIX"]),
    source=sources,
)
Default(library)
