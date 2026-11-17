class_name ApprenticeHut
extends Node3D
## La casucha del aprendiz: donde empieza el juego. Por dentro, acogedora y llena de trastos
## mágicos (cama, mesa con el libro abierto y una vela, estante de pociones, caldero que borbotea,
## chimenea, cristalitos colgando). Sin ventanas hacia el cristal: no se ve hasta que abres la
## puerta (F junto a ella). Entonces cruje, entra el viento y aparece el Cristal Madre, enorme.
## La puerta (lado -z local) mira al cristal. Se construye por código, con cajas (se ven por
## dentro y por fuera) y el shader toon del valle.

signal door_opened

const TOON_SHADER: Shader = preload("res://world/hut_toon.gdshader")
const DOOR_SFX: AudioStream = preload("res://audio/sfx/sfx_door_open_01.ogg")
const WIND_SFX: AudioStream = preload("res://audio/sfx/sfx_wind_gust_01.ogg")
const REVEAL_SFX: AudioStream = preload("res://audio/sfx/sfx_reveal_01.ogg")
const AMBIENCE: AudioStream = preload("res://audio/sfx/amb_hut_loop.ogg")
const C_PLASTER := Color("#efe2cf")
const C_PLASTER_SHADE := Color("#d9c6b4")
const C_WOOD := Color("#8a5a3b")
const C_WOOD_DARK := Color("#5e3a26")
const C_WOOD_LIGHT := Color("#a8754c")
const C_ROOF := Color("#5b3f9e")
const C_ROOF_DARK := Color("#43307a")
const C_STONE := Color("#b9b3c4")
const C_STONE_DARK := Color("#8c86a0")
const C_GOLD := Color("#d8a23a")
const C_PAGE := Color("#f1e8d8")
const C_VIOLET := Color("#654fae")
const C_RUG := Color("#a8384a")
const C_RUG_EDGE := Color("#e0b04a")
const C_CYAN := Color("#a5dae5")
const C_PINK := Color("#ff7ad9")
const C_GREEN := Color("#7be36b")
## Medidas por dentro (m).
const W: float = 4.6
const D: float = 4.2
const H: float = 2.7
const DOOR_W: float = 1.2
const DOOR_H: float = 2.15
## Distancia a la puerta desde la que se puede abrir.
const REACH: float = 2.2

var is_open: bool = false

var _toon: ShaderMaterial
var _door: Node3D
var _door_body: StaticBody3D
var _fire_light: OmniLight3D
var _candle_light: OmniLight3D
var _flames: Array[MeshInstance3D] = []
var _hanging: Array[Node3D] = []
var _ambience: AudioStreamPlayer3D
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"apprentice_hut")
	_rng.seed = 404
	_toon = ShaderMaterial.new()
	_toon.shader = TOON_SHADER
	_toon.set_shader_parameter("rim", 0.15)
	# Dos bandas: con tres, la luz del fuego pintaba anillos en las paredes.
	_toon.set_shader_parameter("bands", 2.0)
	_build_shell()
	_build_door()
	_build_furniture()
	_build_lights()
	_ambience = AudioStreamPlayer3D.new()
	_ambience.name = "Ambience"
	_ambience.bus = &"Ambience"
	_ambience.stream = AMBIENCE  # bucle activado en la importación
	_ambience.unit_size = 3.0
	_ambience.volume_db = -4.0
	_ambience.position = Vector3(0.0, 1.0, D * 0.4)
	_ambience.autoplay = true
	add_child(_ambience)
	if GameState.progression.hut_door_open:
		_set_open_now()


## Centro de la puerta (global): donde se mira para abrirla.
func door_position() -> Vector3:
	return to_global(Vector3(0.0, 1.1, -D * 0.5 - 0.1))


## Sitio para empezar dentro, de cara a la puerta.
func start_position() -> Vector3:
	return to_global(Vector3(0.0, 0.2, D * 0.5 - 1.3))


func player_can_open() -> bool:
	if is_open:
		return false
	var player: Node3D = get_tree().get_first_node_in_group(&"player") as Node3D
	return player != null and player.global_position.distance_to(door_position()) < REACH + 1.1


## Texto del aviso del HUD junto a la puerta ("" si no toca).
func prompt() -> String:
	return tr("[F] ABRIR LA PUERTA") if player_can_open() else ""


func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed(&"interact")
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and player_can_open()
	):
		get_viewport().set_input_as_handled()
		open_door()


## Abre la puerta: pestillo, crujido, ráfaga de viento y la revelación del cristal.
func open_door() -> void:
	if is_open:
		return
	is_open = true
	GameState.progression.hut_door_open = true
	AudioDirector.play_sfx(DOOR_SFX, -2.0)
	AudioDirector.muffle_music(false, 4.0)
	var tw := create_tween()
	tw.tween_interval(0.28)
	tw.tween_callback(
		func() -> void:
			_door_body.collision_layer = 0
			AudioDirector.play_sfx(WIND_SFX, -8.0)
	)
	(
		tw
		. tween_property(_door, "rotation:y", deg_to_rad(108.0), 1.5)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tw
		. parallel()
		. tween_callback(func() -> void: AudioDirector.play_sfx(REVEAL_SFX, -3.0))
		. set_delay(0.25)
	)
	tw.tween_callback(
		func() -> void:
			Events.hint.emit(tr("EL CRISTAL MADRE"), Color("#a5f0ff"))
			door_opened.emit()
	)
	var ambience_tw := create_tween()
	ambience_tw.tween_property(_ambience, "volume_db", -14.0, 3.0)


## Puerta ya abierta, sin ceremonia (partida guardada o demo).
func set_open() -> void:
	_set_open_now()
	GameState.progression.hut_door_open = true
	AudioDirector.muffle_music(false, 0.01)


func _set_open_now() -> void:
	is_open = true
	_door.rotation.y = deg_to_rad(108.0)
	_door_body.collision_layer = 0


func _process(delta: float) -> void:
	_t += delta
	# Llama y velas: parpadeo a saltos (12 fps, como el resto del pixel art).
	var step: float = floor(_t * 12.0) / 12.0
	var flick: float = sin(step * 13.0) * 0.5 + sin(step * 7.3) * 0.5
	_fire_light.light_energy = 1.6 + flick * 0.25
	_candle_light.light_energy = 0.45 + sin(step * 17.0) * 0.06
	for i: int in _flames.size():
		var f: MeshInstance3D = _flames[i]
		f.scale = Vector3(1.0, 1.0 + sin(step * 11.0 + i * 1.7) * 0.18, 1.0)
	for i: int in _hanging.size():
		_hanging[i].rotation.y = step * (0.4 + i * 0.07)
		_hanging[i].position.y = 2.25 - 0.18 * float(i % 3) + sin(step * 1.3 + i) * 0.03


func _mesh(node_name: String, st: SurfaceTool, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = MeshKit.commit(st)
	mi.material_override = mat if mat else _toon
	add_child(mi)
	return mi


func _glow_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


## Suelo, paredes (la de delante con el hueco de la puerta), techo, tejado y chimenea; con
## colisión en paredes y suelo.
func _build_shell() -> void:
	var st: SurfaceTool = MeshKit.begin()
	var hw: float = W * 0.5
	var hd: float = D * 0.5
	var t: float = 0.2
	var body := StaticBody3D.new()
	body.name = "Walls"
	add_child(body)
	# Suelo de tablones.
	var planks: int = 9
	for i: int in planks:
		var x0: float = -hw - t + (W + 2 * t) * float(i) / planks
		var wdt: float = (W + 2 * t) / planks
		var col: Color = C_WOOD if i % 2 == 0 else C_WOOD_LIGHT
		MeshKit.add_box(
			st, Vector3(x0 + wdt * 0.5, 0.07, 0.0), Vector3(wdt - 0.02, 0.14, D + 2 * t), col
		)
	_box_shape(body, Vector3(0.0, 0.07, 0.0), Vector3(W + 2 * t, 0.14, D + 2 * t))
	# Paredes de yeso con zócalo de madera.
	var walls: Array[Array] = [
		[Vector3(0.0, H * 0.5, hd + t * 0.5), Vector3(W + 2 * t, H, t)],
		[Vector3(-hw - t * 0.5, H * 0.5, 0.0), Vector3(t, H, D)],
		[Vector3(hw + t * 0.5, H * 0.5, 0.0), Vector3(t, H, D)],
	]
	var side_w: float = hw + t - DOOR_W * 0.5
	walls.append(
		[Vector3(-(DOOR_W * 0.5 + side_w * 0.5), H * 0.5, -hd - t * 0.5), Vector3(side_w, H, t)]
	)
	walls.append(
		[Vector3(DOOR_W * 0.5 + side_w * 0.5, H * 0.5, -hd - t * 0.5), Vector3(side_w, H, t)]
	)
	walls.append([Vector3(0.0, (DOOR_H + H) * 0.5, -hd - t * 0.5), Vector3(DOOR_W, H - DOOR_H, t)])
	for w: Array in walls:
		var c: Vector3 = w[0]
		var s: Vector3 = w[1]
		MeshKit.add_box(st, c, s, C_PLASTER, C_PLASTER_SHADE)
		_box_shape(body, c, s)
	# Postes de las esquinas y vigas a media altura (entramado), por fuera y por dentro.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			MeshKit.add_box(
				st,
				Vector3(sx * (hw + t * 0.5), H * 0.5, sz * (hd + t * 0.5)),
				Vector3(0.32, H, 0.32),
				C_WOOD_DARK
			)
	MeshKit.add_box(st, Vector3(0.0, 0.22, hd - 0.02), Vector3(W, 0.3, 0.06), C_WOOD_DARK)
	MeshKit.add_box(st, Vector3(-hw + 0.02, 0.22, 0.0), Vector3(0.06, 0.3, D), C_WOOD_DARK)
	MeshKit.add_box(st, Vector3(hw - 0.02, 0.22, 0.0), Vector3(0.06, 0.3, D), C_WOOD_DARK)
	# Friso de madera en la mitad de abajo de las paredes, por dentro.
	var wain: float = 1.05
	MeshKit.add_box(st, Vector3(0.0, wain * 0.5 + 0.14, hd - 0.03), Vector3(W, wain, 0.06), C_WOOD)
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_box(
			st, Vector3(sx * (hw - 0.03), wain * 0.5 + 0.14, 0.0), Vector3(0.06, wain, D), C_WOOD
		)
		MeshKit.add_box(
			st,
			Vector3(sx * (DOOR_W * 0.5 + side_w * 0.5 - t * 0.5), wain * 0.5 + 0.14, -hd + 0.03),
			Vector3(side_w - t - 0.2, wain, 0.06),
			C_WOOD
		)
	MeshKit.add_box(st, Vector3(0.0, wain + 0.17, hd - 0.05), Vector3(W, 0.06, 0.1), C_WOOD_DARK)
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_box(
			st, Vector3(sx * (hw - 0.05), wain + 0.17, 0.0), Vector3(0.1, 0.06, D), C_WOOD_DARK
		)
	# Marco de la puerta.
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_box(
			st,
			Vector3(sx * (DOOR_W * 0.5 + 0.06), DOOR_H * 0.5, -hd - t * 0.5),
			Vector3(0.14, DOOR_H, t + 0.1),
			C_WOOD
		)
	MeshKit.add_box(
		st,
		Vector3(0.0, DOOR_H + 0.07, -hd - t * 0.5),
		Vector3(DOOR_W + 0.26, 0.14, t + 0.1),
		C_WOOD
	)
	# Techo con vigas.
	MeshKit.add_box(
		st, Vector3(0.0, H + 0.07, 0.0), Vector3(W + 2 * t, 0.14, D + 2 * t), C_WOOD_DARK
	)
	for i: int in 3:
		MeshKit.add_box(
			st, Vector3(0.0, H - 0.1, -hd + D * (i + 1) / 4.0), Vector3(W, 0.18, 0.2), C_WOOD
		)
	# Tejado a dos aguas, con alero, y chimenea de piedra.
	_mesh("Shell", st)
	_build_roof()
	_build_outside()
	var chimney: SurfaceTool = MeshKit.begin()
	MeshKit.add_box(
		chimney, Vector3(1.3, H + 1.3, hd - 0.4), Vector3(0.7, 2.6, 0.7), C_STONE, C_STONE_DARK
	)
	MeshKit.add_box(
		chimney, Vector3(1.3, H + 2.65, hd - 0.4), Vector3(0.85, 0.15, 0.85), C_STONE_DARK
	)
	# Chimenea por dentro: hogar de piedra en la pared del fondo.
	MeshKit.add_box(
		chimney, Vector3(1.3, 0.6, hd - 0.25), Vector3(1.3, 1.2, 0.4), C_STONE, C_STONE_DARK
	)
	MeshKit.add_box(chimney, Vector3(1.3, 1.25, hd - 0.3), Vector3(1.5, 0.12, 0.55), C_STONE_DARK)
	MeshKit.add_box(
		chimney, Vector3(1.3, 1.9, hd - 0.15), Vector3(0.8, 1.2, 0.3), C_STONE, C_STONE_DARK
	)
	_mesh("Chimney", chimney)
	# Hueco del fuego (oscuro) y llamas.
	var hole: SurfaceTool = MeshKit.begin()
	MeshKit.add_box(hole, Vector3(1.3, 0.5, hd - 0.44), Vector3(0.8, 0.6, 0.04), Color("#1f1420"))
	_mesh("Hearth", hole)
	for i: int in 3:
		var f: SurfaceTool = MeshKit.begin()
		var col: Color = [Color("#ffb347"), Color("#ff7a2e"), Color("#ffe08a")][i]
		MeshKit.add_prism(
			f, Vector3.ZERO, Vector3.UP, 0.09 - i * 0.015, 0.0, 0.32 - i * 0.06, 5, col, col, _rng
		)
		var fm: MeshInstance3D = _mesh("Flame%d" % i, f, _glow_material(col))
		fm.position = Vector3(1.15 + i * 0.14, 0.22, hd - 0.5)
		_flames.append(fm)


## Tejado de sombrero de mago: ala ancha, cinta dorada, cono y una punta torcida con estrella.
func _build_roof() -> void:
	var st: SurfaceTool = MeshKit.begin()
	var y0: float = H + 0.14
	MeshKit.add_prism(
		st, Vector3(0, y0, 0), Vector3.UP, 3.95, 0.2, 0.0, 8, C_ROOF_DARK, C_ROOF, _rng
	)
	MeshKit.add_prism(
		st, Vector3(0, y0 + 0.2, 0), Vector3.UP, 3.05, 0.32, 0.0, 8, C_GOLD, Color("#f0c45a"), _rng
	)
	MeshKit.add_prism(
		st, Vector3(0, y0 + 0.5, 0), Vector3.UP, 2.95, 0.001, 3.3, 8, C_ROOF, C_ROOF, _rng
	)
	# La punta se dobla hacia un lado, como un sombrero viejo.
	MeshKit.add_prism(
		st,
		Vector3(0.15, y0 + 2.75, 0.05),
		Vector3(0.7, 1.0, 0.25),
		0.62,
		0.001,
		1.7,
		8,
		C_ROOF,
		C_ROOF,
		_rng
	)
	var tip: Vector3 = Vector3(0.15, y0 + 2.75, 0.05) + Vector3(0.7, 1.0, 0.25).normalized() * 1.7
	MeshKit.add_prism(
		st, tip - Vector3(0, 0.12, 0), Vector3.UP, 0.16, 0.0, 0.24, 5, C_GOLD, C_GOLD, _rng
	)
	MeshKit.add_prism(
		st, tip - Vector3(0, 0.12, 0), Vector3.DOWN, 0.16, 0.0, 0.24, 5, C_GOLD, C_GOLD, _rng
	)
	# Estrellas doradas sueltas sobre el cono.
	for k: int in 6:
		var a: float = TAU * k / 6.0 + 0.4
		var h: float = 0.5 + (k % 3) * 0.7
		var r: float = 2.95 * (1.0 - h / 3.3) + 0.02
		var p := Vector3(cos(a) * r, y0 + 0.5 + h, sin(a) * r)
		MeshKit.add_prism(
			st, p, Vector3(cos(a), 0.4, sin(a)), 0.11, 0.0, 0.03, 5, C_GOLD, C_GOLD, _rng
		)
	_mesh("Roof", st)


## Por fuera: contraventanas cerradas con jardinera (no hay ventanas de verdad), un farol junto a la
## puerta y un letrero con estrella.
func _build_outside() -> void:
	var st: SurfaceTool = MeshKit.begin()
	var hw: float = W * 0.5
	var hd: float = D * 0.5
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (hw + 0.24)
		MeshKit.add_box(st, Vector3(x, 1.55, 0.0), Vector3(0.06, 0.95, 1.05), C_WOOD_DARK)
		MeshKit.add_box(st, Vector3(x + sx * 0.02, 1.55, -0.26), Vector3(0.06, 0.85, 0.46), C_ROOF)
		MeshKit.add_box(st, Vector3(x + sx * 0.02, 1.55, 0.26), Vector3(0.06, 0.85, 0.46), C_ROOF)
		MeshKit.add_box(st, Vector3(x + sx * 0.05, 1.55, 0.0), Vector3(0.04, 0.12, 0.9), C_GOLD)
		MeshKit.add_box(st, Vector3(x + sx * 0.14, 0.98, 0.0), Vector3(0.24, 0.18, 1.0), C_WOOD)
		for k: int in 5:
			var c: Color = [C_PINK, Color("#ffd27a"), C_CYAN, C_PINK, Color("#ffd27a")][k]
			MeshKit.add_prism(
				st,
				Vector3(x + sx * 0.14, 1.07, -0.4 + k * 0.2),
				Vector3.UP,
				0.07,
				0.1,
				0.04,
				5,
				c,
				c.lightened(0.3),
				_rng
			)
	# Letrero colgado sobre la puerta.
	MeshKit.add_box(st, Vector3(0.0, DOOR_H + 0.45, -hd - 0.3), Vector3(0.9, 0.4, 0.06), C_WOOD)
	MeshKit.add_prism(
		st,
		Vector3(0.0, DOOR_H + 0.45, -hd - 0.34),
		Vector3.BACK,
		0.13,
		0.0,
		0.02,
		5,
		C_GOLD,
		C_GOLD,
		_rng
	)
	# Farol en un poste a la derecha de la puerta.
	var lp := Vector3(DOOR_W * 0.5 + 0.75, 0.0, -hd - 0.7)
	MeshKit.add_box(st, lp + Vector3(0, 0.9, 0), Vector3(0.1, 1.8, 0.1), C_WOOD_DARK)
	MeshKit.add_box(st, lp + Vector3(0, 1.82, 0), Vector3(0.3, 0.06, 0.3), Color("#4a4458"))
	MeshKit.add_box(st, lp + Vector3(0, 2.1, 0), Vector3(0.3, 0.06, 0.3), Color("#4a4458"))
	_mesh("Outside", st)
	var glass: SurfaceTool = MeshKit.begin()
	MeshKit.add_box(glass, lp + Vector3(0, 1.96, 0), Vector3(0.22, 0.22, 0.22), Color("#ffd48a"))
	_mesh("Lantern", glass, _glow_material(Color("#ffd48a")))
	var lantern := OmniLight3D.new()
	lantern.light_color = Color("#ffc878")
	lantern.light_energy = 0.8
	lantern.omni_range = 4.0
	lantern.position = lp + Vector3(0, 1.96, -0.2)
	add_child(lantern)


func _box_shape(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = center
	body.add_child(col)


## La puerta: tablones con herrajes y una estrella pintada; gira sobre la bisagra izquierda
## (vista desde dentro) hacia fuera.
func _build_door() -> void:
	_door = Node3D.new()
	_door.name = "Door"
	_door.position = Vector3(-DOOR_W * 0.5, 0.14, -D * 0.5 - 0.1)
	add_child(_door)
	var st: SurfaceTool = MeshKit.begin()
	var boards: int = 4
	for i: int in boards:
		var bw: float = DOOR_W / boards
		var col: Color = C_WOOD_LIGHT if i % 2 == 0 else C_WOOD
		MeshKit.add_box(
			st,
			Vector3(bw * (i + 0.5), (DOOR_H - 0.16) * 0.5, 0.0),
			Vector3(bw - 0.015, DOOR_H - 0.16, 0.08),
			col
		)
	for y: float in [0.35, 1.6]:
		MeshKit.add_box(
			st, Vector3(DOOR_W * 0.5, y, 0.0), Vector3(DOOR_W - 0.06, 0.1, 0.11), Color("#4a4458")
		)
	MeshKit.add_box(st, Vector3(DOOR_W - 0.16, 1.0, 0.07), Vector3(0.06, 0.16, 0.06), C_GOLD)
	MeshKit.add_box(st, Vector3(DOOR_W - 0.16, 1.0, -0.07), Vector3(0.06, 0.16, 0.06), C_GOLD)
	# Estrella pintada por dentro y por fuera (dos triángulos cruzados aplanados).
	for z: float in [0.045, -0.045]:
		MeshKit.add_prism(
			st,
			Vector3(DOOR_W * 0.5, 1.2, z),
			Vector3(0, 0, signf(z)),
			0.16,
			0.0,
			0.005,
			5,
			C_GOLD,
			C_GOLD,
			_rng
		)
	var mi := MeshInstance3D.new()
	mi.name = "Boards"
	mi.mesh = MeshKit.commit(st)
	mi.material_override = _toon
	_door.add_child(mi)
	_door_body = StaticBody3D.new()
	_door_body.name = "Body"
	_door.add_child(_door_body)
	_box_shape(_door_body, Vector3(DOOR_W * 0.5, DOOR_H * 0.5, 0.0), Vector3(DOOR_W, DOOR_H, 0.1))


## Muebles y trastos de aprendiz.
func _build_furniture() -> void:
	var hw: float = W * 0.5
	var hd: float = D * 0.5
	var st: SurfaceTool = MeshKit.begin()
	# Alfombra con borde dorado.
	MeshKit.add_box(st, Vector3(0.0, 0.15, 0.1), Vector3(2.3, 0.02, 1.7), C_RUG_EDGE)
	MeshKit.add_box(st, Vector3(0.0, 0.16, 0.1), Vector3(2.0, 0.02, 1.4), C_RUG)
	# Cama en la esquina del fondo a la izquierda.
	var bed := Vector3(-hw + 0.6, 0.0, hd - 1.1)
	MeshKit.add_box(st, bed + Vector3(0, 0.3, 0), Vector3(1.0, 0.3, 1.9), C_WOOD)
	MeshKit.add_box(st, bed + Vector3(0, 0.52, 0.0), Vector3(0.92, 0.16, 1.8), C_PAGE)
	MeshKit.add_box(st, bed + Vector3(0, 0.58, -0.2), Vector3(0.96, 0.12, 1.3), C_VIOLET)
	MeshKit.add_box(st, bed + Vector3(0, 0.66, 0.68), Vector3(0.6, 0.12, 0.32), Color.WHITE)
	MeshKit.add_box(st, bed + Vector3(0, 0.7, 0.93), Vector3(1.0, 0.8, 0.08), C_WOOD_DARK)
	# Mesa con libro abierto, vela y pergaminos, a la derecha junto a la puerta.
	var table := Vector3(hw - 0.75, 0.0, -hd + 1.1)
	MeshKit.add_box(st, table + Vector3(0, 0.84, 0), Vector3(1.1, 0.08, 0.75), C_WOOD_LIGHT)
	for sx: float in [-0.45, 0.45]:
		for sz: float in [-0.28, 0.28]:
			MeshKit.add_box(
				st, table + Vector3(sx, 0.45, sz), Vector3(0.08, 0.8, 0.08), C_WOOD_DARK
			)
	MeshKit.add_box(st, table + Vector3(-0.15, 0.9, 0.0), Vector3(0.24, 0.03, 0.32), C_PAGE)
	MeshKit.add_box(st, table + Vector3(0.11, 0.9, 0.0), Vector3(0.24, 0.03, 0.32), C_PAGE)
	MeshKit.add_box(st, table + Vector3(-0.02, 0.885, 0.0), Vector3(0.52, 0.02, 0.36), C_VIOLET)
	MeshKit.add_prism(
		st, table + Vector3(0.36, 0.88, -0.2), Vector3.UP, 0.04, 0.18, 0.0, 6, C_PAGE, C_PAGE, _rng
	)
	MeshKit.add_box(
		st, table + Vector3(0.35, 0.91, 0.22), Vector3(0.3, 0.06, 0.06), Color("#e6d2a8")
	)
	# Taburete.
	MeshKit.add_box(st, table + Vector3(-0.2, 0.45, 0.65), Vector3(0.4, 0.06, 0.4), C_WOOD)
	MeshKit.add_box(st, table + Vector3(-0.2, 0.22, 0.65), Vector3(0.08, 0.42, 0.08), C_WOOD_DARK)
	# Estante con pociones y libros en la pared derecha.
	for y: float in [1.35, 1.85]:
		MeshKit.add_box(st, Vector3(hw - 0.17, y, 0.7), Vector3(0.3, 0.05, 1.3), C_WOOD_DARK)
	var potion_cols: Array[Color] = [C_PINK, C_CYAN, C_GREEN, Color("#ffd27a"), C_VIOLET, C_PINK]
	for i: int in 6:
		var y: float = 1.38 if i < 3 else 1.88
		var z: float = 0.3 + (i % 3) * 0.38
		var c: Color = potion_cols[i]
		MeshKit.add_prism(
			st, Vector3(hw - 0.17, y, z), Vector3.UP, 0.08, 0.16, 0.08, 6, c, c.darkened(0.3), _rng
		)
	for i: int in 5:
		var c: Color = [C_RUG, C_VIOLET, Color("#2f6b8a"), C_GOLD, C_RUG][i]
		MeshKit.add_box(
			st,
			Vector3(hw - 0.17, 1.98, -0.1 + i * 0.07),
			Vector3(0.24, 0.26 - (i % 2) * 0.04, 0.06),
			c
		)
	# Escoba apoyada junto a la puerta.
	MeshKit.add_prism(
		st,
		Vector3(-DOOR_W * 0.5 - 0.5, 0.15, -hd + 0.2),
		Vector3(0.15, 1.0, 0.1),
		0.03,
		1.35,
		0.0,
		5,
		C_WOOD,
		C_WOOD,
		_rng
	)
	MeshKit.add_prism(
		st,
		Vector3(-DOOR_W * 0.5 - 0.5, 0.15, -hd + 0.2),
		Vector3(0.05, 1.0, 0.03),
		0.13,
		0.38,
		0.0,
		6,
		C_GOLD,
		Color("#b8862a"),
		_rng
	)
	_mesh("Furniture", st)
	# Caldero a la izquierda, con poción verde que brilla.
	var cauldron: SurfaceTool = MeshKit.begin()
	var cp := Vector3(-hw + 0.8, 0.15, -0.2)
	var iron := Color("#3a3446")
	for k: int in 3:
		var a: float = TAU * k / 3.0
		MeshKit.add_box(
			cauldron,
			cp + Vector3(cos(a) * 0.28, 0.08, sin(a) * 0.28),
			Vector3(0.08, 0.16, 0.08),
			iron
		)
	MeshKit.add_prism(
		cauldron,
		cp + Vector3(0, 0.12, 0),
		Vector3.UP,
		0.42,
		0.42,
		0.0,
		8,
		iron,
		Color("#26222e"),
		_rng
	)
	MeshKit.add_prism(
		cauldron,
		cp + Vector3(0, 0.5, 0),
		Vector3.UP,
		0.47,
		0.08,
		0.0,
		8,
		Color("#4a4458"),
		Color("#4a4458"),
		_rng
	)
	_mesh("Cauldron", cauldron)
	var brew: SurfaceTool = MeshKit.begin()
	MeshKit.add_prism(
		brew,
		cp + Vector3(0, 0.55, 0),
		Vector3.UP,
		0.38,
		0.03,
		0.0,
		8,
		C_GREEN,
		C_GREEN.lightened(0.3),
		_rng
	)
	for k: int in 4:
		var b := Vector3(_rng.randf_range(-0.2, 0.2), 0.6, _rng.randf_range(-0.2, 0.2))
		MeshKit.add_prism(
			brew, cp + b, Vector3.UP, 0.04, 0.03, 0.03, 5, C_GREEN.lightened(0.4), Color.WHITE, _rng
		)
	_mesh("Brew", brew, _glow_material(C_GREEN))
	var green := OmniLight3D.new()
	green.light_color = C_GREEN
	green.light_energy = 0.25
	green.omni_range = 1.6
	green.position = cp + Vector3(0, 0.9, 0)
	add_child(green)
	# Cristalitos colgados del techo con un hilo.
	var cols: Array[Color] = [C_CYAN, C_PINK, Color("#c79bff"), C_CYAN, Color("#ffd27a")]
	for i: int in cols.size():
		var holder := Node3D.new()
		holder.name = "Hanging%d" % i
		# En los lados: nada delante de la puerta.
		var side: float = -1.0 if i % 2 == 0 else 1.0
		holder.position = Vector3(
			side * (1.25 + 0.3 * float(i / 2)), 2.2, 0.2 + 0.55 * float(i / 2)
		)
		add_child(holder)
		var h: SurfaceTool = MeshKit.begin()
		MeshKit.add_prism(
			h,
			Vector3(0, -0.08, 0),
			Vector3.UP,
			0.04,
			0.08,
			0.06,
			6,
			cols[i],
			cols[i].darkened(0.35),
			_rng
		)
		MeshKit.add_box(h, Vector3(0, 0.22, 0), Vector3(0.008, 0.44, 0.008), C_PAGE)
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.commit(h)
		mi.material_override = _toon
		holder.add_child(mi)
		_hanging.append(holder)


func _build_lights() -> void:
	var hd: float = D * 0.5
	_fire_light = OmniLight3D.new()
	_fire_light.name = "Fire"
	_fire_light.light_color = Color("#ffb36b")
	_fire_light.light_energy = 1.6
	_fire_light.omni_range = 7.5
	_fire_light.shadow_enabled = true
	_fire_light.position = Vector3(1.3, 0.9, hd - 0.9)
	add_child(_fire_light)
	_candle_light = OmniLight3D.new()
	_candle_light.name = "Candle"
	_candle_light.light_color = Color("#ffd48a")
	_candle_light.light_energy = 0.45
	_candle_light.omni_range = 2.4
	_candle_light.position = Vector3(W * 0.5 - 0.4, 1.25, -hd + 0.9)
	add_child(_candle_light)
	var flame: SurfaceTool = MeshKit.begin()
	MeshKit.add_prism(
		flame,
		Vector3.ZERO,
		Vector3.UP,
		0.025,
		0.0,
		0.07,
		5,
		Color("#ffe08a"),
		Color("#ffe08a"),
		_rng
	)
	var fm: MeshInstance3D = _mesh("CandleFlame", flame, _glow_material(Color("#ffe08a")))
	fm.position = Vector3(W * 0.5 - 0.75 + 0.36, 1.06, -hd + 1.1 - 0.2)
	_flames.append(fm)
