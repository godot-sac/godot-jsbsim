extends GutTest
## Data folder handling: res:// on disk in the editor, extraction to user:// for exported games.

const DATA := "res://addons/jsbsim/data"


func test_resolve_res_path_in_editor() -> void:
	var path := JSBSimFDM.resolve_data_dir(DATA)
	assert_eq(path, ProjectSettings.globalize_path(DATA))


func test_resolve_missing_dir() -> void:
	assert_eq(JSBSimFDM.resolve_data_dir("res://no_such_dir"), "")
	assert_push_error_count(1)


func test_extract_copies_all_files() -> void:
	var path := JSBSimFDM.extract_data_dir(DATA)
	assert_string_starts_with(path, ProjectSettings.globalize_path("user://jsbsim/data-"))
	for file: String in ["aircraft/J3Cub/J3Cub.xml", "aircraft/J3Cub/Engines/Continental A-65-8.xml", "aircraft/J3Cub/NOTICE.md"]:
		var source := DATA.path_join(file)
		var copy := path.path_join(file)
		assert_true(FileAccess.file_exists(copy), file)
		assert_eq(FileAccess.get_md5(copy), FileAccess.get_md5(source), file)
	assert_true(FileAccess.file_exists(path.path_join(".complete")))
	assert_eq(JSBSimFDM.extract_data_dir(DATA), path, "unchanged data is reused")


func test_extracted_data_flies_the_same() -> void:
	var extracted := JSBSimFDM.extract_data_dir(DATA)
	var results: Array[float] = []
	for dir: String in [DATA, extracted]:
		var fdm := JSBSimFDM.new()
		assert_true(fdm.load_model("J3Cub", dir), fdm.get_last_error())
		fdm.set_initial_position(39.95, 32.69, 1500.0)
		fdm.set_initial_airspeed(70.0)
		fdm.run_ic()
		fdm.start_engines()
		fdm.step(600)
		results.append(fdm.get_property("position/geod-alt-ft"))
	assert_eq(results[0], results[1])


## Exported games: the data exists only inside a .pck. A pack built with PCKPacker and mounted with
## load_resource_pack() puts the files under res:// without a folder on disk, as in an exported game.
func test_data_inside_pck_is_extracted() -> void:
	var pck := "user://test_jsbsim_data.pck"
	var packer := PCKPacker.new()
	assert_eq(packer.pck_start(pck), OK)
	var files := _files(DATA)
	for file in files:
		assert_eq(packer.add_file("res://packed_jsbsim".path_join(file), DATA.path_join(file)), OK, file)
	assert_eq(packer.flush(), OK)
	assert_true(ProjectSettings.load_resource_pack(pck))

	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://packed_jsbsim")), "not on disk")
	var fdm := JSBSimFDM.new()
	assert_true(fdm.load_model("J3Cub", "res://packed_jsbsim"), fdm.get_last_error())
	assert_string_starts_with(fdm.get_data_path(), ProjectSettings.globalize_path("user://jsbsim/packed_jsbsim-"))
	for file in files:
		assert_true(FileAccess.file_exists(fdm.get_data_path().path_join(file)), file)
	fdm.set_initial_position(39.95, 32.69, 1500.0)
	fdm.set_initial_airspeed(70.0)
	assert_true(fdm.run_ic())
	assert_eq(fdm.step(120), 120)


func _files(dir: String, prefix := "") -> Array[String]:
	var found: Array[String] = []
	var path := dir.path_join(prefix)
	for file in DirAccess.get_files_at(path):
		found.append(prefix.path_join(file) if prefix else file)
	for sub in DirAccess.get_directories_at(path):
		found.append_array(_files(dir, prefix.path_join(sub) if prefix else sub))
	return found
