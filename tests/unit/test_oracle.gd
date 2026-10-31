extends GutTest
## Runs the scenarios in tests/golden/ with JSBSimFDM and with the official JSBSim Python package
## (tools/oracle_fly.py) and compares the sampled trajectories. Both use JSBSim 1.3.3 but different builds (compiler,
## flags), so values are compared with a relative tolerance of 1e-9; on Windows they are bit-identical.

const GOLDEN := "res://tests/golden"
const TOLERANCE := 1e-9


func _python() -> String:
	var bin := "Scripts/python.exe" if OS.get_name() == "Windows" else "bin/python"
	return ProjectSettings.globalize_path("res://tools/.venv/" + bin)


func _scenarios() -> Array[String]:
	var files: Array[String] = []
	for file in DirAccess.get_files_at(GOLDEN):
		if file.ends_with("_scenario.json"):
			files.append(GOLDEN.path_join(file))
	return files


## Same steps and order as tools/oracle_fly.py.
func _run(scenario: Dictionary) -> Dictionary:
	var fdm := JSBSimFDM.new()
	if not fdm.load_model(scenario.aircraft, "res://" + scenario.data_dir):
		return {"ok": false, "error": fdm.get_last_error()}
	fdm.set_initial_position(scenario.latitude, scenario.longitude, scenario.height_m)
	fdm.set_initial_orientation(scenario.heading_deg, scenario.pitch_deg, scenario.roll_deg)
	fdm.set_initial_airspeed(scenario.vc_kts)
	fdm.run_ic()
	fdm.start_engines()
	var trim_ok := true
	if int(scenario.get("trim_mode", -1)) >= 0:
		trim_ok = fdm.trim(int(scenario.trim_mode))
	var inputs := {}
	for entry: Dictionary in scenario.get("inputs", []):
		inputs[int(entry.step)] = entry
	var samples: Array[Dictionary] = []
	var sample := func(at: int) -> void:
		var row := {"step": at}
		for name: String in scenario.properties:
			row[name] = fdm.get_property(name)
		samples.append(row)
	var step := 0
	sample.call(0)
	while step < int(scenario.steps):
		if inputs.has(step):
			var entry: Dictionary = inputs[step]
			for name: String in entry.get("set", {}):
				fdm.set_property(name, entry.set[name])
			for name: String in entry.get("add", {}):
				fdm.set_property(name, fdm.get_property(name) + float(entry.add[name]))
		if fdm.step() != 1:
			break
		step += 1
		if step % int(scenario.sample_every) == 0:
			sample.call(step)
	return {"ok": true, "steps": step, "trim_ok": trim_ok, "samples": samples}


func test_scenarios_exist() -> void:
	assert_gt(_scenarios().size(), 1)


func test_matches_python_oracle() -> void:
	if not FileAccess.file_exists(_python()):
		pending("tools/.venv not set up")
		return
	for path in _scenarios():
		var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var output: Array = []
		var code := OS.execute(_python(), [ProjectSettings.globalize_path("res://tools/oracle_fly.py"),
				ProjectSettings.globalize_path(path)], output)
		assert_eq(code, 0, "%s: oracle failed: %s" % [path, output])
		if code != 0:
			continue
		var lines := str(output[0]).strip_edges().split("\n")
		var oracle: Dictionary = JSON.parse_string(lines[lines.size() - 1])
		var ours := _run(scenario)
		assert_true(ours.ok, str(ours.get("error", "")))
		assert_eq(ours.steps, int(oracle.steps), path)
		assert_eq(ours.trim_ok, oracle.trim_ok, path + ": trim result")
		assert_eq(ours.samples.size(), oracle.samples.size(), path)
		var worst := 0.0
		var failures := 0
		for i in mini(ours.samples.size(), oracle.samples.size()):
			for name: String in scenario.properties:
				var a: float = ours.samples[i][name]
				var b: float = oracle.samples[i][name]
				var relative := absf(a - b) / maxf(1.0, absf(b))
				worst = maxf(worst, relative)
				if relative > TOLERANCE:
					failures += 1
					if failures <= 5:
						fail_test("%s step %d %s: ours %.12f, oracle %.12f" % [path, ours.samples[i].step, name, a, b])
		gut.p("%s: %d samples, worst relative difference %s" % [path.get_file(), ours.samples.size(), worst])
		assert_eq(failures, 0, path)
