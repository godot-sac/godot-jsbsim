extends CanvasLayer
## Flight data (top left), key help (bottom left) and an optional JSBSim property panel (F3, right).

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
const HELP := ("W/S pitch   A/D roll   Q/E rudder   R/F throttle   C camera   P pause   N step   [ ] time   "
		+ "Backspace reset   F3 properties   Esc quit")

@export var aircraft: JSBSimAircraft

var _data: Label
var _panel: Label
var _help: Label


func _ready() -> void:
	_data = _label(Vector2(16, 12), 20)
	_help = _label(Vector2(16, 0), 14)
	_help.text = HELP
	_help.anchor_top = 1.0
	_help.anchor_bottom = 1.0
	_help.offset_top = -30
	_panel = _label(Vector2(0, 12), 14)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -430
	_panel.visible = false


func toggle_properties() -> void:
	_panel.visible = not _panel.visible


func _process(_delta: float) -> void:
	if aircraft == null or not aircraft.is_started():
		_data.text = "JSBSim model not loaded (see the output)"
		return
	if aircraft.is_failed():
		_data.text = "SIMULATION STOPPED (crash)\nBackspace: reset"
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
		"THR   %5.0f %%" % (aircraft.throttle * 100.0),
		"STICK ail %+.2f  elev %+.2f  rud %+.2f" % [aircraft.aileron, aircraft.elevator, aircraft.rudder],
		"TIME  %6.1f s" % fdm.get_sim_time(),
	])
	_data.text = "\n".join(lines)
	if _panel.visible:
		var rows := PackedStringArray()
		for name: String in PANEL_PROPERTIES:
			if fdm.has_property(name):
				rows.append("%-34s %12.4f" % [name, fdm.get_property(name)])
		_panel.text = "\n".join(rows)


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
