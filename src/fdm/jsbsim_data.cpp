#include "jsbsim_data.h"

#include <map>
#include <mutex>
#include <string>

#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

using namespace godot;

namespace {

// Paths of all files under `dir`, relative to it, sorted (so the fingerprint does not depend on listing order).
bool list_files(const String &dir, const String &prefix, PackedStringArray &r_files) {
	Ref<DirAccess> access = DirAccess::open(dir.path_join(prefix));
	if (access.is_null()) {
		return false;
	}
	access->list_dir_begin();
	for (String name = access->get_next(); !name.is_empty(); name = access->get_next()) {
		const String relative = prefix.is_empty() ? name : prefix.path_join(name);
		if (access->current_is_dir()) {
			if (!list_files(dir, relative, r_files)) {
				return false;
			}
		} else {
			r_files.push_back(relative);
		}
	}
	access->list_dir_end();
	return true;
}

} // namespace

namespace jsbsim_data {

String resolve(const String &root_dir, String &r_error) {
	const String path = ProjectSettings::get_singleton()->globalize_path(root_dir);
	if (DirAccess::dir_exists_absolute(path)) {
		return path;
	}
	if (root_dir.begins_with("res://") && DirAccess::dir_exists_absolute(root_dir)) {
		// Inside the .pck of an exported game: extracted (and its files hashed) once per run, not per aircraft.
		static std::mutex mutex;
		static std::map<std::string, std::string> extracted;
		const std::string key = root_dir.utf8().get_data();
		std::lock_guard<std::mutex> lock(mutex);
		const auto found = extracted.find(key);
		if (found != extracted.end()) {
			return String::utf8(found->second.c_str());
		}
		const String target = extract(root_dir, r_error);
		if (!target.is_empty()) {
			extracted[key] = target.utf8().get_data();
		}
		return target;
	}
	r_error = "JSBSim data folder not found: " + root_dir;
	return String();
}

String extract(const String &res_dir, String &r_error) {
	PackedStringArray files;
	if (!list_files(res_dir, String(), files) || files.is_empty()) {
		r_error = "Cannot list JSBSim data folder: " + res_dir;
		return String();
	}
	files.sort();

	String fingerprint;
	for (const String &file : files) {
		fingerprint += file + String(":") + FileAccess::get_md5(res_dir.path_join(file)) + String("\n");
	}
	const String name = res_dir.trim_suffix("/").get_file();
	const String target = "user://jsbsim/" + name + "-" + fingerprint.md5_text().substr(0, 12);
	const String marker = target.path_join(".complete");
	const String target_path = ProjectSettings::get_singleton()->globalize_path(target);
	if (FileAccess::file_exists(marker)) {
		return target_path;
	}

	for (const String &file : files) {
		const String destination = target.path_join(file);
		if (DirAccess::make_dir_recursive_absolute(destination.get_base_dir()) != OK) {
			r_error = "Cannot create " + destination.get_base_dir();
			return String();
		}
		Ref<FileAccess> out = FileAccess::open(destination, FileAccess::WRITE);
		if (out.is_null()) {
			r_error = "Cannot write " + destination;
			return String();
		}
		out->store_buffer(FileAccess::get_file_as_bytes(res_dir.path_join(file)));
	}
	// Written last: an interrupted extraction is redone on the next start.
	Ref<FileAccess> done = FileAccess::open(marker, FileAccess::WRITE);
	if (done.is_null()) {
		r_error = "Cannot write " + marker;
		return String();
	}
	done->store_string(fingerprint);
	return target_path;
}

} // namespace jsbsim_data
