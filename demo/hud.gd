extends CanvasLayer
## Flight data (top left), key help (bottom left), an optional JSBSim property panel (F3, right) and a joypad panel
## (F4, right: connected devices with their raw axes and buttons, to map a flight stick).

const FT := 0.3048
const PANEL_PROPERTIES := [
	"velocities/vc-kts", "velocities/vtrue-kts", "velocities/mach", "velocities/h-dot-fps",
	"aero/alpha-deg", "aero/beta-deg", "aero/qbar-psf", "accelerations/n-pilot-z-norm",
	"attitude/psi-deg", "attitude/theta-deg", "attitude/phi-deg",
	"position/lat-geod-deg", "position/long-gc-deg", "position/geod-alt-ft", "position/h-agl-ft",
	"fcs/aileron-cmd-norm", "fcs/elevator-cmd-norm", "fcs/rudder-cmd-norm", "fcs/throttle-cmd-norm",
	"fcs/pitch-trim-cmd-norm", "fcs/elevator-pos-rad", "propulsion/engine/propeller-rpm",
	"propulsion/engine/thrust-lbs", "forces/fbz-aero-lbs", "simulation/sim-time-sec",
]
const HELP := ("W/S pitch   A/D roll   Q/E rudder   R/F throttle   B brakes   C camera   P pause   N step   "
		+ "[ ] time   Backspace reset   F3 properties   Esc quit\n"
		+ "T autopilot   Y route   , . heading   - = altitude   9 0 speed   Home/End trim   F4 joypads")

@export var aircraft: JSBSimAircraft

var _data: Label
var _panel: Label
var _help: Label
var _joypads: Label


func _ready() -> void:
	_data = _label(Vector2(16, 12), 20)
	_help = _label(Vector2(16, 0), 14)
	_help.text = HELP
	_help.anchor_top = 1.0
	_help.anchor_bottom = 1.0
	_help.offset_top = -50
	_panel = _label(Vector2(0, 12), 14)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -430
	_panel.visible = false
	_joypads = _label(Vector2(0, 12), 14)
	_joypads.anchor_left = 1.0
	_joypads.anchor_right = 1.0
	_joypads.offset_left = -520
	_joypads.visible = false


## Data source lines that must stay visible (terrain imagery and elevation licences), bottom right.
func set_attribution(lines: PackedStringArray) -> void:
	var label := _label(Vector2.ZERO, 12)
	label.text = "\n".join(lines)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 12)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.offset_bottom = -34


func toggle_properties() -> void:
	_panel.visible = not _panel.visible
	_joypads.visible = false


func toggle_joypads() -> void:
	_joypads.visible = not _joypads.visible
	_panel.visible = false


func _process(_delta: float) -> void:
	if _joypads.visible:
		_joypads.text = _joypad_report()
	if aircraft == null or not aircraft.is_started():
		_data.text = "JSBSim model not loaded (see the output)"
		return
	if aircraft.is_failed() or aircraft.is_crashed():
		_data.text = "CRASHED\nBackspace: reset"
		return
	var fdm := aircraft.get_fdm()
	var altitude := fdm.get_property("position/geod-alt-ft") * FT
	var lines := PackedStringArray([
		"%s   %s" % [fdm.get_model_name(), "PAUSED" if aircraft.paused else "x%s" % aircraft.time_scale],
		"IAS   %6.1f kt" % fdm.get_property("velocities/vc-kts"),
		"ALT   %6.0f m  (%5.0f ft)" % [altitude, altitude / FT],
		"AGL   %6.0f m" % (fdm.get_property("position/h-agl-ft") * FT),
		"VS    %+6.1f m/s" % (fdm.get_property("velocities/h-dot-fps") * FT),
		"HDG   %6.1f°" % fposmod(fdm.get_property("attitude/psi-deg"), 360.0),
		"PITCH %+6.1f°  ROLL %+6.1f°" % [fdm.get_property("attitude/theta-deg"), fdm.get_property("attitude/phi-deg")],
		"AOA   %+6.1f°" % fdm.get_property("aero/alpha-deg"),
		"G     %+6.2f" % -fdm.get_property("accelerations/n-pilot-z-norm"),
		"THR   %5.0f %%%s" % [aircraft.throttle * 100.0, "   BRAKES" if aircraft.brake > 0.0 else ""],
		"GEAR  %s" % ("on ground" if aircraft.is_on_ground() else "airborne"),
		"STICK ail %+.2f  elev %+.2f  rud %+.2f" % [aircraft.aileron, aircraft.elevator, aircraft.rudder],
		"TIME  %6.1f s" % fdm.get_sim_time(),
	])
	var ap := aircraft.get_autopilot()
	if ap and ap.enabled:
		var modes := "HDG %03.0f" % ap.target_heading if ap.heading_hold and not ap.follow_route else "WINGS LEVEL"
		if ap.follow_route and ap.get_active_waypoint() >= 0:
			modes = "ROUTE wp %d/%d  %.1f km  xtk %+.0f m  trk %03.0f" % [ap.get_active_waypoint() + 1,
					ap.get_waypoint_count(), ap.get_distance_to_waypoint() / 1000.0, ap.get_cross_track_error(),
					ap.get_desired_track()]
		lines.append("AP    %s   ALT %s   SPD %s" % [modes,
				"%.0f m" % ap.target_altitude if ap.altitude_hold else "VS %+.1f" % ap.target_vertical_speed,
				"%.0f kt" % ap.target_speed if ap.speed_hold else "manual"])
	else:
		lines.append("AP    off")
	_data.text = "\n".join(lines)
	if _panel.visible:
		var rows := PackedStringArray()
		for name: String in PANEL_PROPERTIES:
			if fdm.has_property(name):
				rows.append("%-34s %12.4f" % [name, fdm.get_property(name)])
		_panel.text = "\n".join(rows)


## Every connected joypad: name, GUID, raw axes and pressed buttons (Godot's indices, as InputMap uses them).
func _joypad_report() -> String:
	var rows := PackedStringArray(["JOYPADS (axis and button numbers for docs/input.md)"])
	var devices := Input.get_connected_joypads()
	if devices.is_empty():
		rows.append("none connected")
	for device in devices:
		rows.append("#%d %s" % [device, Input.get_joy_name(device)])
		rows.append("   guid %s" % Input.get_joy_guid(device))
		var axes := PackedStringArray()
		for axis in JOY_AXIS_MAX:
			axes.append("%d:%+.2f" % [axis, Input.get_joy_axis(device, axis)])
		rows.append("   axes " + " ".join(axes))
		var buttons := PackedStringArray()
		for button in 128:
			if Input.is_joy_button_pressed(device, button):
				buttons.append(str(button))
		rows.append("   buttons " + (" ".join(buttons) if not buttons.is_empty() else "-"))
	return "\n".join(rows)


func _label(at: Vector2, size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "monospace"])
	label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label
