#pragma once

// Routes JSBSim's log output (FGLogger) to the Godot output: errors to push_error, warnings to push_warning, the
// rest to print. JSBSim keeps one logger per thread, so install() must run on every thread that uses JSBSim.
namespace jsbsim_logger {

// Minimum level that is printed, as JSBSim::LogLevel (0 BULK ... 5 FATAL). Messages JSBSim marks as STDOUT (for
// example trim reports at debug level 1) are always printed. Shared by all threads. Default: 3 (WARN).
void set_min_level(int level);
int get_min_level();

// Makes the Godot logger the JSBSim logger of the calling thread (once per thread).
void install();

} // namespace jsbsim_logger
