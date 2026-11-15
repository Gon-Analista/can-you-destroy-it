extends Node3D
## Escena del prototipo "El golpe": el valle, el Cristal Madre, el mago y el HUD.
## Captura el ratón al hacer clic y lo suelta con Esc.

const SUN_DIR := Vector3(0.55, -0.65, -0.52)
const AMBIENCE: AudioStream = preload("res://audio/sfx/amb_valley_loop.ogg")
## Música del valle por capas (tools/music_synth.py): 1 Aprendiz ... 5 Archimago.
const MUSIC_LAYERS: Array[AudioStream] = [
	preload("res://audio/music/music_valley_1_aprendiz.ogg"),
	preload("res://audio/music/music_valley_2_iniciado.ogg"),
	preload("res://audio/music/music_valley_3_hechicero.ogg"),
	preload("res://audio/music/music_valley_4_magus.ogg"),
	preload("res://audio/music/music_valley_5_archimago.ogg"),
]

@onready var _sun: DirectionalLight3D = $Sun
@onready var _player: Player = $Player
@onready var _hud: Hud = $HUDLayer/Hud


func _ready() -> void:
	_sun.look_at_from_position(Vector3.ZERO, SUN_DIR.normalized(), Vector3.UP)
	_hud.bind(_player.get_camera(), _player.get_caster())
	AudioDirector.play_ambience(AMBIENCE, -10.0)
	# Hasta que exista el sistema de rangos, se empieza en Aprendiz (1 capa).
	AudioDirector.play_music(MUSIC_LAYERS, _arg_int("--music-layers=", 1))
	GameState.emit_all()
	if OS.is_debug_build():
		_setup_autoplay()


## Modo demo para grabar capturas sin ratón (sólo debug):
## godot --path game -- --autoplay [--tier=N] [--yaw=grados] [--pitch=grados]
func _setup_autoplay() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--autoplay"):
		return
	var tier: int = 0
	for a: String in args:
		if a.begins_with("--tier="):
			tier = int(a.get_slice("=", 1)) - 1
		elif a.begins_with("--yaw="):
			_player.rotation.y = deg_to_rad(float(a.get_slice("=", 1)))
		elif a.begins_with("--pitch="):
			(_player.get_node(^"Head") as Node3D).rotation.x = deg_to_rad(
				float(a.get_slice("=", 1))
			)
	_player.get_caster().set_tier(tier)
	_hud.force_captured_look = true
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	var side: Array[int] = [0]
	timer.timeout.connect(
		func() -> void:
			_player.get_caster().try_cast(side[0])
			side[0] = 1 - side[0]
	)
	add_child(timer)
	if args.has("--collect"):
		# Tras unos golpes: camina hacia el cristal y mantiene F para recoger.
		var t1: SceneTreeTimer = get_tree().create_timer(3.0)
		t1.timeout.connect(
			func() -> void:
				timer.stop()
				Input.action_press(&"move_forward")
		)
		var t2: SceneTreeTimer = get_tree().create_timer(5.2)
		t2.timeout.connect(
			func() -> void:
				Input.action_release(&"move_forward")
				Input.action_press(&"interact")
		)
	if args.has("--report"):
		get_tree().create_timer(4.0, true, false, true).timeout.connect(_print_report)


func _print_report() -> void:
	var shards: int = 0
	for body: Node in get_tree().get_nodes_in_group(&"shards"):
		if not (body as RigidBody3D).freeze:
			shards += 1
	print(
		(
			(
				"REPORT draw_calls=%d objects=%d primitives=%d physics_active=%d"
				+ " shards_moving=%d time_scale=%.2f"
			)
			% [
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
				shards,
				Engine.time_scale,
			]
		)
	)


func _process(_delta: float) -> void:
	# Red de seguridad: el tiempo nunca se queda ralentizado fuera de un hit-stop.
	if Engine.time_scale != 1.0 and not HitStop.is_active():
		Engine.time_scale = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.is_pressed()
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif (
		OS.is_debug_build()
		and event is InputEventKey
		and (event as InputEventKey).pressed
		and not (event as InputEventKey).echo
		and (event as InputEventKey).keycode == KEY_M
	):
		# Debug: M sube una capa de música (1 -> 5 -> 1) para oír cómo crece con el rango.
		AudioDirector.set_music_layers(AudioDirector.get_music_layers() % MUSIC_LAYERS.size() + 1)
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _arg_int(prefix: String, fallback: int) -> int:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return int(a.trim_prefix(prefix))
	return fallback
