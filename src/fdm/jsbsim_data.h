#pragma once

#include <godot_cpp/variant/string.hpp>

// JSBSim reads its XML files from disk with its own parser, so it needs a real folder. In the editor res:// is a
// folder on disk; in an exported game it is inside the .pck. This helper turns a JSBSim data folder (aircraft/,
// engine/, systems/) into an absolute OS path, extracting it from the .pck into user:// when needed.
namespace jsbsim_data {

// Absolute OS path for `root_dir` (res://, user:// or absolute). A res:// folder that is not on disk is extracted
// with extract(). Returns an empty string and sets `r_error` on failure.
godot::String resolve(const godot::String &root_dir, godot::String &r_error);

// Copies every file under `res_dir` to user://jsbsim/<name>-<fingerprint>/ and returns its absolute OS path. The
// fingerprint covers file paths and contents, so a game update with changed data extracts again; an unchanged
// extraction is reused. Returns an empty string and sets `r_error` on failure.
godot::String extract(const godot::String &res_dir, godot::String &r_error);

} // namespace jsbsim_data
