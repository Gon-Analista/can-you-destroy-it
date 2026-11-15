extends Node3D
## Galería de VFX: carga el juego real (valle, cristal, manos, contorno) y coloca un `SpellOrb`
## entre las manos para compararlo con la referencia y grabar capturas sin ratón.
##
## godot --path game res://tests/vfx_gallery/vfx_gallery.tscn -- [opciones]
##   --def=res://data/spells/vfx_arcane_orb.tres   recurso SpellVisualDef a mostrar
##   --charge=0.6     carga fija (sin opción: ciclo cargar -> mantener -> soltar)
##   --yaw=grados --pitch=grados   orientación de la cámara
##   --hud            muestra el HUD (oculto por defecto para capturas limpias)
##   --report         imprime draw calls a los 3 s
## Teclas: Espacio suelta el hechizo, 1-5 fija la carga (0,2 a 1), 0 vuelve al ciclo.

const MAIN_SCENE: PackedScene = preload("res://main/main.tscn")
const DEFAULT_DEF: String = "res://data/spells/vfx_arcane_orb.tres"
const SPARK_SHADER: Shader = preload("res://spells/spark.gdshader")
## Posición del orbe en espacio de cámara: entre las palmas.
const ORB_POS := Vector3(0.0, -0.15, -0.5)
const CHARGE_TIME: float = 1.6
const HOLD_TIME: float = 1.4
const PAUSE_TIME: float = 0.4

var _orb: SpellOrb
var _fixed_charge: float = -1.0
var _cycle_t: float = 0.0
var _phase: int = 0


func _ready() -> void:
	var main: Node3D = MAIN_SCENE.instantiate()
	add_child(main)
	var player: Player = main.get_node(^"Player")
	var head: Node3D = player.get_node(^"Head")
	var camera: Camera3D = player.get_camera()
	var def_path: String = DEFAULT_DEF
	var show_hud: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--def="):
			def_path = a.get_slice("=", 1)
		elif a.begins_with("--charge="):
			_fixed_charge = clampf(float(a.get_slice("=", 1)), 0.0, 1.0)
		elif a.begins_with("--yaw="):
			player.rotation.y = deg_to_rad(float(a.get_slice("=", 1)))
		elif a.begins_with("--pitch="):
			head.rotation.x = deg_to_rad(float(a.get_slice("=", 1)))
		elif a == "--hud":
			show_hud = true
		elif a == "--report":
			get_tree().create_timer(3.0).timeout.connect(_print_report)
	(main.get_node(^"HUDLayer") as CanvasLayer).visible = show_hud
	_hide_palm_sparks(player.get_node(^"Head/Camera/Hands"))
	_orb = SpellOrb.new()
	_orb.name = "SpellOrb"
	_orb.def = load(def_path) as SpellVisualDef
	_orb.position = ORB_POS
	_orb.charge = _fixed_charge if _fixed_charge >= 0.0 else 0.0
	camera.add_child(_orb)


func _process(delta: float) -> void:
	if _fixed_charge >= 0.0:
		return
	_cycle_t += delta
	match _phase:
		0:
			_orb.charge = _cycle_t / CHARGE_TIME
			if _cycle_t >= CHARGE_TIME:
				_next_phase()
		1:
			if _cycle_t >= HOLD_TIME:
				_orb.release()
				_next_phase()
		2:
			if not _orb.is_releasing() and _cycle_t >= PAUSE_TIME:
				_orb.charge = 0.0
				_orb.appear()
				_next_phase()


func _next_phase() -> void:
	_phase = (_phase + 1) % 3
	_cycle_t = 0.0


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_SPACE:
		_orb.release()
	elif key.keycode >= KEY_1 and key.keycode <= KEY_5:
		_fixed_charge = float(key.keycode - KEY_0) / 5.0
		if not _orb.visible or _orb.is_releasing():
			_orb.appear()
		_orb.charge = _fixed_charge
	elif key.keycode == KEY_0:
		_fixed_charge = -1.0


## Oculta los orbes de chispa de las palmas (sólo en la galería) para ver el hechizo limpio.
func _hide_palm_sparks(node: Node) -> void:
	for child: Node in node.get_children():
		var mi := child as MeshInstance3D
		if mi != null:
			var mat := mi.material_override as ShaderMaterial
			if mat != null and mat.shader == SPARK_SHADER:
				mi.visible = false
		_hide_palm_sparks(child)


func _print_report() -> void:
	print(
		(
			"REPORT draw_calls=%d objects=%d primitives=%d fps=%d"
			% [
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.TIME_FPS),
			]
		)
	)
