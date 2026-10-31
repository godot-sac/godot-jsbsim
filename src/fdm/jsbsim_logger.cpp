#include "jsbsim_logger.h"

#include <atomic>
#include <memory>
#include <string>

#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <input_output/FGLog.h>

using namespace godot;
using JSBSim::LogLevel;

namespace {

std::atomic<int> min_level{ static_cast<int>(LogLevel::WARN) };

// JSBSim calls SetLevel() to start a record, Message() one or more times, then Flush() to end it.
class GodotLogger : public JSBSim::FGLogger {
public:
	void SetLevel(LogLevel level) override {
		log_level = level;
		location.clear();
		buffer.clear();
	}

	void FileLocation(const std::string &filename, int line) override {
		location = " (" + filename + ":" + std::to_string(line) + ")";
	}

	void Message(const std::string &message) override { buffer += message; }

	void Flush() override {
		// JSBSim builds messages with leading and trailing newlines for the console; strip them.
		const size_t first = buffer.find_first_not_of(" \t\r\n");
		if (first != std::string::npos) {
			const size_t last = buffer.find_last_not_of(" \t\r\n");
			emit(buffer.substr(first, last - first + 1) + location);
		}
		buffer.clear();
		location.clear();
	}

private:
	void emit(const std::string &text) const {
		if (log_level != LogLevel::STDOUT && static_cast<int>(log_level) < min_level.load()) {
			return;
		}
		const String message = "JSBSim: " + String::utf8(text.c_str());
		switch (log_level) {
			case LogLevel::ERROR:
			case LogLevel::FATAL:
				UtilityFunctions::push_error(message);
				break;
			case LogLevel::WARN:
				UtilityFunctions::push_warning(message);
				break;
			default:
				UtilityFunctions::print(message);
				break;
		}
	}

	std::string location;
	std::string buffer;
};

} // namespace

namespace jsbsim_logger {

void set_min_level(int level) {
	min_level.store(level);
}

int get_min_level() {
	return min_level.load();
}

void install() {
	// thread_local: one flag per thread, like JSBSim's logger itself.
	thread_local bool installed = false;
	if (!installed) {
		JSBSim::SetLogger(std::make_shared<GodotLogger>());
		installed = true;
	}
}

} // namespace jsbsim_logger
