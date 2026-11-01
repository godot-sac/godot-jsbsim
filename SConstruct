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

# C++ unit tests (doctest), without Godot: `scons tests` builds and runs build/tests/unit_tests. A separate
# environment, because godot-cpp's flags (DLL settings) don't suit a test program. It links JSBSim like the extension.
test_env = Environment(ENV=os.environ)
jsbsim_bin_dir = Dir("addons/jsbsim/bin/{}".format(platform)).abspath
if platform == "windows" and not env.get("use_mingw"):
    # /wd4251: JSBSim's exported classes have STL members; harmless when both sides use the same compiler and CRT.
    test_env.Append(CXXFLAGS=["/std:c++17", "/EHsc", "/O2", "/W3", "/wd4251", "/utf-8", "/MD"])
    test_env.Append(CPPDEFINES=["_USE_MATH_DEFINES"])
    test_env.PrependENVPath("PATH", jsbsim_bin_dir)  # JSBSim.dll at run time
else:
    test_env.Append(CXXFLAGS=["-std=c++17", "-O2", "-Wall"], LINKFLAGS=["-Wl,-rpath," + jsbsim_bin_dir])
golden_dir = Dir("tests/golden").abspath.replace("\\", "/")
data_dir = Dir("addons/jsbsim/data").abspath.replace("\\", "/")
test_env.Append(
    CPPPATH=["src/", "thirdparty/doctest/", "thirdparty/jsbsim/src/"],
    CPPDEFINES=[("GOLDEN_DIR", '\\"{}\\"'.format(golden_dir)), ("DATA_DIR", '\\"{}\\"'.format(data_dir))],
    LIBPATH=[jsbsim_lib_dir],
    LIBS=["JSBSim"],
)
test_objects = [
    test_env.Object("build/tests/" + os.path.splitext(os.path.basename(str(f)))[0], f)
    # Only the Godot-free parts of src/.
    for f in Glob("tests/cpp/*.cpp") + ["src/geo/geo_math.cpp"]
]
test_program = test_env.Program("build/tests/unit_tests", test_objects)
test_env.Alias("tests", test_program, test_program[0].abspath)
AlwaysBuild("tests")
