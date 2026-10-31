extends GutTest
## Phase 0: the extension loads, finds the JSBSim shared library and flies a model.

const ROOT := "res://thirdparty/jsbsim"


func test_class_registered() -> void:
	assert_true(ClassDB.class_exists("JSBSimProbe"))


func test_jsbsim_version() -> void:
	assert_string_starts_with(JSBSimProbe.get_jsbsim_version(), "1.3.3")


func test_fly_pc7() -> void:
	var r: Dictionary = JSBSimProbe.fly_test(ROOT, "pc7", 10.0)
	assert_true(r.ok, str(r.get("error", "")))
	assert_almost_eq(float(r.sim_time), 10.0, 0.01)
	assert_eq(int(r.steps), 1200, "default dt is 1/120 s")
	# Still flying near the start point: 5000 ft, Esenboğa.
	assert_almost_eq(float(r["position/geod-alt-ft"]), 5000.0, 1500.0)
	assert_almost_eq(float(r["position/lat-geod-deg"]), 39.95, 0.05)
	assert_gt(float(r["velocities/vc-kts"]), 50.0)


func test_missing_aircraft_does_not_crash() -> void:
	var r: Dictionary = JSBSimProbe.fly_test(ROOT, "no_such_aircraft", 1.0)
	assert_false(r.ok)
	assert_ne(str(r.get("error", "")), "")


func test_missing_root_does_not_crash() -> void:
	var r: Dictionary = JSBSimProbe.fly_test("res://no_such_dir", "pc7", 1.0)
	assert_false(r.ok)


## Same flight in the official JSBSim Python package (tools/oracle_fly.py). Both use JSBSim 1.3.3 but different
## builds (compiler, flags), so values are compared with a tolerance (1e-9 relative); in practice they agree to ~1e-14.
func test_matches_python_oracle() -> void:
	var python := ProjectSettings.globalize_path("res://tools/.venv/Scripts/python.exe")
	if OS.get_name() != "Windows":
		python = ProjectSettings.globalize_path("res://tools/.venv/bin/python")
	if not FileAccess.file_exists(python):
		pending("tools/.venv not set up")
		return
	var seconds := 60.0
	var output: Array = []
	var code := OS.execute(python, [ProjectSettings.globalize_path("res://tools/oracle_fly.py"),
			ProjectSettings.globalize_path(ROOT), "pc7", str(seconds)], output, true)
	assert_eq(code, 0, "oracle failed: %s" % [output])
	if code != 0:
		return
	var lines := str(output[0]).strip_edges().split("\n")
	var oracle: Dictionary = JSON.parse_string(lines[lines.size() - 1])
	var ours: Dictionary = JSBSimProbe.fly_test(ROOT, "pc7", seconds)
	assert_true(ours.ok, str(ours.get("error", "")))
	assert_eq(int(ours.steps), int(oracle.steps))
	for key: String in ["position/lat-geod-deg", "position/long-gc-deg", "position/geod-alt-ft", "position/h-sl-ft",
			"velocities/vc-kts", "attitude/psi-deg", "attitude/theta-deg", "attitude/phi-deg"]:
		gut.p("%s: ours %.9f, oracle %.9f, diff %s" % [key, ours[key], oracle[key], float(ours[key]) - float(oracle[key])])
		assert_almost_eq(float(ours[key]), float(oracle[key]), 1e-9 * maxf(1.0, absf(oracle[key])), key)
