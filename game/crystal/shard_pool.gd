class_name ShardPool
extends Node3D
## Pool de fragmentos físicos en cinco tamaños (Astilla, Fragmento, Fragmento grande, Bloque
## de cristal y Pedrusco de maná; ver data/shards/) y los Fragmentos Resonantes de las venas, que
## brillan con el color de su vena. Un golpe suelta fragmentos por valor de su daño (`pieces_for`):
## el maná que da el cristal es la esencia que pierde, y el Pilón va con él.
## Nada se instancia durante el juego: se reciclan (el más antiguo primero) y tras unos segundos
## quietos se congelan para no gastar física.
## Recoger: el fragmento se vuelve intangible y vuela hacia la mano encogiéndose.
## Gravedad (Arcano + Tierra): los fragmentos sueltos giran en espiral hasta un pozo y, al
## llegar, avisan con `swallowed` (quien abrió el pozo decide si van a la bolsa o a la tolva).
## Vórtice (nodo hito): igual, pero hacia `vortex_target` (el mago, que se mueve) y avisan con
## `vortexed`. Lo que gira (pozo o vórtice) no está suelto: no lo cogen los familiares.

## Un fragmento ha llegado al centro del pozo de gravedad (sigue visible, quieto en el centro).
signal swallowed(index: int)
## Un fragmento ha terminado la espiral del Vórtice junto al mago.
signal vortexed(index: int)

const SHARD_MATERIAL_SHADER: Shader = preload("res://crystal/shard.gdshader")
const SPLINTER: ShardType = preload("res://data/shards/splinter.tres")
const SHARD: ShardType = preload("res://data/shards/shard.tres")
const CHUNK: ShardType = preload("res://data/shards/chunk.tres")
const BLOCK: ShardType = preload("res://data/shards/block.tres")
const BOULDER: ShardType = preload("res://data/shards/boulder.tres")
## Fragmento Resonante (GDD 6.1): sale de golpear una vena con su elemento débil. No entra en
## TYPES (que va por daño); ALL_TYPES los tiene todos, de menos a más valor.
const RESONANT: ShardType = preload("res://data/shards/resonant.tres")
const TYPES: Array[ShardType] = [SPLINTER, SHARD, CHUNK, BLOCK, BOULDER]
const ALL_TYPES: Array[ShardType] = [SPLINTER, SHARD, CHUNK, BLOCK, RESONANT, BOULDER]
const GLOW_SHADER: Shader = preload("res://fx/hd/hd_glow.gdshader")
## Piezas grandes por golpe como mucho (si no caben, un tamaño más; del mayor, hasta el doble) y
## trocitos para el resto.
const MAX_PIECES: int = 10
const MAX_EXTRA: int = 3
const CLINK_STREAMS: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_shard_clink_01.ogg"),
	preload("res://audio/sfx/sfx_shard_clink_02.ogg"),
	preload("res://audio/sfx/sfx_shard_clink_03.ogg"),
	preload("res://audio/sfx/sfx_shard_clink_04.ogg"),
]
const PICKUP_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_shard_pickup_01.ogg"),
	preload("res://audio/sfx/sfx_shard_pickup_02.ogg"),
]
const SHARD_LAYER: int = 1 << 3
const MESH_VARIANTS: int = 4
const COLLECT_SEC: float = 0.22
## Vórtice: altura del centro sobre los pies del mago, radio en que acaba la espiral (a su
## alrededor, a la vista) y halo de los fragmentos que gira.
const VORTEX_LIFT: float = 0.35
const VORTEX_END_RADIUS: float = 3.2
const VORTEX_GLOW := Color(0.55, 0.9, 1.0, 1.0)

@export var pool_size: int = 128
@export var freeze_after_sec: float = 5.0
@export var clink_players: int = 8
## Separación mínima entre dos tintineos (evita un muro de sonido).
@export var clink_min_gap_sec: float = 0.035

## Hacia dónde gira el Vórtice (el mago; ver ManaVortex).
var vortex_target: Node3D

var _shards: Array[RigidBody3D] = []
var _meshes: Array[MeshInstance3D] = []
var _cols: Array[CollisionShape3D] = []
var _types: Array[ShardType] = []
var _spawn_time: PackedFloat64Array = []
var _flash: PackedFloat32Array = []
## > 0 mientras el fragmento vuela hacia la mano.
var _collect_t: PackedFloat32Array = []
var _collect_from: Array[Vector3] = []
var _type_meshes: Array[Array] = []
var _type_shapes: Array[Array] = []
var _next: int = 0
var _clinks: Array[AudioStreamPlayer3D] = []
var _clink_next: int = 0
var _last_clink: float = -1.0
var _clink_random: AudioStreamRandomizer
var _pickup_player: AudioStreamPlayer
var _highlighted: int = -1
var _collect_target: Node3D
var _time: float = 0.0
var _material: ShaderMaterial
## Un material por capa del cristal: cada fragmento lleva el color de la capa de la que sale.
var _layer_materials: Array[ShaderMaterial] = []
## Pozo de gravedad: segundos en el pozo (-1 = fuera), duración de su espiral, posición de
## partida en polares respecto al centro (radio, ángulo, altura) y vueltas que da.
var _orbit_t: PackedFloat32Array = []
var _orbit_dur: PackedFloat32Array = []
var _orbit_from: Array[Vector3] = []
var _orbit_turns: PackedFloat32Array = []
var _well := Vector3.ZERO
## 0: gira hacia el pozo de gravedad; 1: hacia el Vórtice.
var _orbit_kind := PackedByteArray()
## Halo HD de cada fragmento (sólo se ve en los resonantes) y sus materiales por color.
var _halos: Array[MeshInstance3D] = []
var _halo_mats: Dictionary[Color, ShaderMaterial] = {}


## Los fragmentos llevan el color de la capa de la que salen.
func set_palette_color(key: String, c: Color) -> void:
	if _material:
		_material.set_shader_parameter(key, c)


## Prepara un material por capa con su paleta (lo llama MotherCrystal).
func set_layer_palettes(layers: Array[CrystalLayerDef]) -> void:
	_layer_materials.clear()
	for layer: CrystalLayerDef in layers:
		var m: ShaderMaterial = _material.duplicate()
		for key: String in ["col_highlight", "col_light", "col_mid", "col_dark", "col_core"]:
			m.set_shader_parameter(key, layer.get(key))
		_layer_materials.append(m)


func _ready() -> void:
	add_to_group(&"shard_pool")
	var material := ShaderMaterial.new()
	_material = material
	material.shader = SHARD_MATERIAL_SHADER
	for t: int in ALL_TYPES.size():
		var meshes: Array[ArrayMesh] = []
		var shapes: Array[ConvexPolygonShape3D] = []
		for v: int in MESH_VARIANTS:
			var m: ArrayMesh = CrystalClusterBuilder.build_shard_mesh(ALL_TYPES[t], 40 + t * 10 + v)
			meshes.append(m)
			shapes.append(m.create_convex_shape(true, true) as ConvexPolygonShape3D)
		_type_meshes.append(meshes)
		_type_shapes.append(shapes)
	for i: int in pool_size:
		var body := RigidBody3D.new()
		body.name = "Shard%d" % i
		body.add_to_group(&"shards")
		body.set_meta(&"shard_index", i)
		body.collision_layer = SHARD_LAYER
		body.collision_mask = 1 | (1 << 1) | SHARD_LAYER
		body.contact_monitor = true
		body.max_contacts_reported = 1
		body.mass = 0.2
		var phys := PhysicsMaterial.new()
		phys.bounce = 0.35
		phys.friction = 0.6
		body.physics_material_override = phys
		var col := CollisionShape3D.new()
		body.add_child(col)
		var mi := MeshInstance3D.new()
		mi.material_override = material
		mi.set_instance_shader_parameter("glint_seed", randf())
		body.add_child(mi)
		var halo: MeshInstance3D = HdFx.quad(GLOW_SHADER, 1.4, 3)
		halo.visible = false
		mi.add_child(halo)
		_halos.append(halo)
		body.body_entered.connect(_on_shard_contact.bind(i))
		_deactivate(body)
		add_child(body)
		_shards.append(body)
		_meshes.append(mi)
		_cols.append(col)
		_types.append(TYPES[1])
		_spawn_time.append(-1.0)
		_flash.append(0.0)
		_collect_t.append(0.0)
		_collect_from.append(Vector3.ZERO)
		_orbit_t.append(-1.0)
		_orbit_dur.append(1.0)
		_orbit_from.append(Vector3.ZERO)
		_orbit_turns.append(1.0)
		_orbit_kind.append(0)
	_setup_audio()


func _setup_audio() -> void:
	_clink_random = AudioStreamRandomizer.new()
	for s: AudioStream in CLINK_STREAMS:
		_clink_random.add_stream(-1, s)
	_clink_random.random_pitch = 1.12
	_clink_random.random_volume_offset_db = 3.0
	for i: int in clink_players:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.stream = _clink_random
		p.unit_size = 8.0
		p.max_db = -2.0
		add_child(p)
		_clinks.append(p)
	var pickup := AudioStreamRandomizer.new()
	for s: AudioStream in PICKUP_SFX:
		pickup.add_stream(-1, s)
	pickup.random_pitch = 1.05
	_pickup_player = AudioStreamPlayer.new()
	_pickup_player.bus = &"SFX"
	_pickup_player.stream = pickup
	_pickup_player.max_polyphony = 4
	add_child(_pickup_player)


## Fragmentos que suelta un golpe que vale `worth` (su daño): el tipo es el mayor cuyo
## `min_damage` se alcanza (el doble de su valor, así salen de 2 a 9 piezas), la cuenta es
## worth / valor y lo que sobra sale en hasta MAX_EXTRA trocitos más pequeños. Devuelve pares
## (índice en TYPES, cuántos). Ver tools/balance_sim.py.
static func pieces_for(worth: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if worth < 1.0:
		return out
	var idx: int = 0
	for i: int in TYPES.size():
		if worth >= TYPES[i].min_damage:
			idx = i
	while idx < TYPES.size() - 1 and floori(worth / TYPES[idx].value) > MAX_PIECES:
		idx += 1
	var top: int = MAX_PIECES * (2 if idx == TYPES.size() - 1 else 1)
	var count: int = clampi(floori(worth / TYPES[idx].value), 1, top)
	out.append(Vector2i(idx, count))
	var rest: float = worth - float(count * TYPES[idx].value)
	var extra: int = 0
	for j: int in range(idx - 1, -1, -1):
		var n: int = 0
		while rest >= TYPES[j].value and extra < MAX_EXTRA:
			rest -= TYPES[j].value
			n += 1
			extra += 1
		if n > 0:
			out.append(Vector2i(j, n))
	return out


## Lanza los fragmentos de un golpe que vale `worth` (ver `pieces_for`).
func spawn_worth(origin: Vector3, normal: Vector3, worth: float, power: float, layer: int) -> void:
	for piece: Vector2i in pieces_for(worth):
		spawn(origin, normal, TYPES[piece.x], piece.y, power, layer)


## Tipo de fragmento para un golpe: el mayor cuyo daño mínimo se alcance; resonante sube uno.
static func type_for_hit(damage: int, resonant: bool) -> ShardType:
	var idx: int = 0
	for i: int in TYPES.size():
		if damage >= TYPES[i].min_damage:
			idx = i
	if resonant:
		idx = mini(idx + 1, TYPES.size() - 1)
	return TYPES[idx]


## Lanza `count` fragmentos de tipo `type` desde `origin`, saliendo según `normal`. Con `glow`
## (alfa > 0) brillan de ese color con un halo HD (Fragmentos Resonantes).
func spawn(
	origin: Vector3,
	normal: Vector3,
	type: ShardType,
	count: int,
	power: float,
	layer: int = -1,
	glow: Color = Color(0, 0, 0, 0)
) -> void:
	var t_index: int = ALL_TYPES.find(type)
	var mat: ShaderMaterial = _material
	if layer >= 0 and layer < _layer_materials.size():
		mat = _layer_materials[layer]
	for n: int in count:
		var i: int = _next
		_next = (_next + 1) % pool_size
		var body: RigidBody3D = _shards[i]
		_deactivate(body)
		_orbit_t[i] = -1.0
		_orbit_kind[i] = 0
		var variant: int = randi() % MESH_VARIANTS
		_types[i] = type
		_meshes[i].mesh = _type_meshes[t_index][variant]
		_meshes[i].material_override = mat
		_cols[i].shape = _type_shapes[t_index][variant]
		_meshes[i].scale = Vector3.ONE
		body.global_transform = Transform3D(
			Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU)),
			origin + normal * (0.2 + type.radius)
		)
		body.collision_layer = SHARD_LAYER
		body.freeze = false
		body.visible = true
		var spread := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)) * 0.6
		var dir: Vector3 = (normal + Vector3.UP * 0.6 + spread).normalized()
		body.linear_velocity = dir * randf_range(4.0, 8.0) * power * type.launch_speed
		body.angular_velocity = (
			Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 14.0
		)
		_spawn_time[i] = _time
		_flash[i] = 1.0
		_meshes[i].set_instance_shader_parameter("spawn_flash", 1.0)
		_meshes[i].set_instance_shader_parameter("vein_glow", glow)
		_halos[i].visible = glow.a > 0.0
		if glow.a > 0.0:
			_halos[i].material_override = _halo_material(glow)
	set_physics_process(true)


## Fragmentos de un tipo que hay ahora en el suelo (o volando), para los tests y la demo.
func count_of(type: ShardType) -> int:
	var n: int = 0
	for i: int in pool_size:
		if _shards[i].visible and _types[i] == type and _collect_t[i] <= 0.0:
			n += 1
	return n


## Halo de los fragmentos del Vórtice: más grande y con destellos (la espiral se ve de lejos).
func _vortex_halo() -> ShaderMaterial:
	if not _halo_mats.has(VORTEX_GLOW):
		var m: ShaderMaterial = _halo_material(VORTEX_GLOW)
		m.set_shader_parameter("intensity", 0.9)
		m.set_shader_parameter("falloff", 2.2)
		m.set_shader_parameter("rays", 0.7)
	return _halo_mats[VORTEX_GLOW]


func _halo_material(c: Color) -> ShaderMaterial:
	if not _halo_mats.has(c):
		var m: ShaderMaterial = _halos[0].material_override.duplicate()
		m.set_shader_parameter("color", Color(c.r, c.g, c.b))
		m.set_shader_parameter("intensity", 0.45)
		m.set_shader_parameter("falloff", 3.0)
		m.set_shader_parameter("rays", 0.3)
		m.set_shader_parameter("ray_count", 4.0)
		_halo_mats[c] = m
	return _halo_mats[c]


## Pantalla de carga: enseña un fragmento de cada tamaño quieto un momento (no se pueden
## recoger) para compilar su material antes de jugar.
func warm_up(at: Vector3) -> void:
	var used: Array[int] = []
	for t: int in ALL_TYPES.size():
		var i: int = pool_size - 1 - t
		var body: RigidBody3D = _shards[i]
		_meshes[i].mesh = _type_meshes[t][0]
		_meshes[i].scale = Vector3.ONE
		body.global_position = at + Vector3(float(t) - 1.0, 0.0, 0.0)
		body.visible = true
		_meshes[i].set_instance_shader_parameter("spawn_flash", 1.0)
		_meshes[i].set_instance_shader_parameter(
			"vein_glow", Color(1, 0.5, 0.2, 1) if ALL_TYPES[t] == RESONANT else Color(0, 0, 0, 0)
		)
		_halos[i].visible = ALL_TYPES[t] == RESONANT
		used.append(i)
	await get_tree().create_timer(0.4).timeout
	for i: int in used:
		if _spawn_time[i] < 0.0:
			_deactivate(_shards[i])


## Índice del fragmento al que apunta el collider, o -1.
func index_of(collider: Object) -> int:
	if collider is Node and (collider as Node).has_meta(&"shard_index"):
		var i: int = (collider as Node).get_meta(&"shard_index")
		if _collect_t[i] <= 0.0 and _orbit_t[i] < 0.0 and _shards[i].visible:
			return i
	return -1


## Fragmento recogible más cercano a `point` dentro de `radius`, o -1.
func nearest(point: Vector3, radius: float) -> int:
	var best: int = -1
	var best_d: float = radius * radius
	for i: int in pool_size:
		if not _shards[i].visible or _collect_t[i] > 0.0 or _orbit_t[i] >= 0.0:
			continue
		var d: float = _shards[i].global_position.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = i
	return best


## Para los familiares: el fragmento suelto más cercano a `point` dentro de `radius` que lleve
## al menos `settle_sec` en el mundo (ya ha caído) y no esté en `claimed`, o -1.
func loose_near(
	point: Vector3, radius: float, claimed: PackedInt32Array, settle_sec: float = 1.0
) -> int:
	var best: int = -1
	var best_d: float = radius * radius
	for i: int in pool_size:
		if not is_loose(i) or _time - _spawn_time[i] < settle_sec or claimed.has(i):
			continue
		var d: float = _shards[i].global_position.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = i
	return best


## True si el fragmento `index` está en el mundo y nadie lo está recogiendo.
func is_loose(index: int) -> bool:
	return (
		_shards[index].visible
		and _spawn_time[index] >= 0.0
		and _collect_t[index] <= 0.0
		and _orbit_t[index] < 0.0
	)


## Un familiar se lleva el fragmento: desaparece sin sonido (el familiar pone el suyo).
## Devuelve su tipo, o null si ya no estaba.
func take(index: int) -> ShardType:
	if not is_loose(index):
		return null
	if index == _highlighted:
		set_highlight(-1)
	var t: ShardType = _types[index]
	_deactivate(_shards[index])
	_spawn_time[index] = -1.0
	return t


func position_of(index: int) -> Vector3:
	return _shards[index].global_position


func type_of(index: int) -> ShardType:
	return _types[index]


func set_highlight(index: int) -> void:
	if index == _highlighted:
		return
	if _highlighted >= 0:
		_meshes[_highlighted].set_instance_shader_parameter("highlight", 0.0)
	_highlighted = index
	if index >= 0:
		_meshes[index].set_instance_shader_parameter("highlight", 1.0)


## Recoge el fragmento: vuela hacia `target` (la mano) y desaparece. Devuelve su tipo.
func collect(index: int, target: Node3D) -> ShardType:
	var body: RigidBody3D = _shards[index]
	if index == _highlighted:
		set_highlight(-1)
	_orbit_t[index] = -1.0
	if target == null:
		# Sin destino (envío directo): desaparece ya; otra cosa dibuja su vuelo.
		var t: ShardType = _types[index]
		_deactivate(body)
		_spawn_time[index] = -1.0
		_pickup_player.pitch_scale = t.pickup_pitch * 1.2
		_pickup_player.play()
		return t
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	body.collision_layer = 0
	_collect_from[index] = body.global_position
	_collect_t[index] = COLLECT_SEC
	_collect_target = target
	_meshes[index].set_instance_shader_parameter("spawn_flash", 1.0)
	var type: ShardType = _types[index]
	_pickup_player.pitch_scale = type.pickup_pitch
	_pickup_player.play()
	set_physics_process(true)
	return type


## Gravedad: todos los fragmentos sueltos (estén donde estén) giran en espiral hasta `center` en
## `sec` s como mucho (los lejanos tardan más). Devuelve cuántos atrapa.
func gravity_pull(center: Vector3, sec: float) -> int:
	_well = center
	var n: int = 0
	for i: int in pool_size:
		if (
			_spawn_time[i] < 0.0
			or not _shards[i].visible
			or _collect_t[i] > 0.0
			or _orbit_t[i] >= 0.0
		):
			continue
		var body: RigidBody3D = _shards[i]
		if i == _highlighted:
			set_highlight(-1)
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
		body.collision_layer = 0
		var rel: Vector3 = body.global_position - center
		var r0: float = Vector2(rel.x, rel.z).length()
		_orbit_from[i] = Vector3(r0, atan2(rel.z, rel.x), rel.y)
		_orbit_dur[i] = clampf(0.9 + r0 * 0.025, 0.9, sec) * randf_range(0.82, 1.0)
		_orbit_turns[i] = randf_range(1.1, 1.8)
		_orbit_t[i] = 0.0
		_orbit_kind[i] = 0
		_meshes[i].set_instance_shader_parameter("highlight", 1.0)
		n += 1
	if n > 0:
		set_physics_process(true)
	return n


## Vórtice: el fragmento suelto `index` sube y gira en espiral hasta el mago en unos `sec` s,
## brillando. Devuelve false si ya no estaba suelto.
func vortex_pull(index: int, sec: float) -> bool:
	if not is_loose(index) or vortex_target == null:
		return false
	if index == _highlighted:
		set_highlight(-1)
	var body: RigidBody3D = _shards[index]
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	body.collision_layer = 0
	var rel: Vector3 = (
		body.global_position - (vortex_target.global_position + Vector3.UP * VORTEX_LIFT)
	)
	var r0: float = Vector2(rel.x, rel.z).length()
	_orbit_from[index] = Vector3(r0, atan2(rel.z, rel.x), rel.y)
	_orbit_dur[index] = sec
	_orbit_turns[index] = randf_range(1.2, 2.0)
	_orbit_t[index] = 0.0
	_orbit_kind[index] = 1
	_meshes[index].set_instance_shader_parameter("highlight", 1.0)
	if _types[index] != RESONANT:
		_halos[index].material_override = _vortex_halo()
	_halos[index].visible = true
	set_physics_process(true)
	return true


## Fragmentos que siguen girando hacia el pozo (`kind` 0), hacia el Vórtice (1) o los dos (-1).
func orbiting_count(kind: int = -1) -> int:
	var n: int = 0
	for i: int in pool_size:
		if _orbit_t[i] >= 0.0 and (kind < 0 or _orbit_kind[i] == kind):
			n += 1
	return n


func _physics_process(delta: float) -> void:
	_time += delta
	var any_active: bool = false
	for i: int in pool_size:
		if _spawn_time[i] < 0.0:
			continue
		if _orbit_t[i] >= 0.0:
			any_active = true
			_update_orbit(i, delta)
			continue
		if _collect_t[i] > 0.0:
			any_active = true
			_update_collect(i, delta)
			continue
		if _flash[i] > 0.0:
			_flash[i] = maxf(0.0, _flash[i] - delta * 4.0)
			_meshes[i].set_instance_shader_parameter("spawn_flash", 1.0 if _flash[i] > 0.6 else 0.0)
		var body: RigidBody3D = _shards[i]
		if not body.freeze:
			any_active = true
			if (
				_time - _spawn_time[i] > freeze_after_sec
				and body.linear_velocity.length_squared() < 0.04
			):
				body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
				body.freeze = true
				body.contact_monitor = false
	if not any_active:
		set_physics_process(false)


func _update_collect(i: int, delta: float) -> void:
	_collect_t[i] = maxf(0.0, _collect_t[i] - delta)
	var k: float = 1.0 - _collect_t[i] / COLLECT_SEC
	var target: Vector3 = _collect_from[i]
	if is_instance_valid(_collect_target):
		target = _collect_target.global_position
	var pos: Vector3 = _collect_from[i].lerp(target, k * k)
	pos.y += sin(k * PI) * 0.6
	_shards[i].global_position = pos
	_meshes[i].scale = Vector3.ONE * maxf(0.05, 1.0 - k * 0.85)
	if _collect_t[i] <= 0.0:
		_deactivate(_shards[i])
		_spawn_time[i] = -1.0


## Espiral hacia el pozo: el radio se cierra, el giro se acelera (como un remolino) y el
## fragmento sube en arco, gira sobre sí mismo y encoge al llegar.
func _update_orbit(i: int, delta: float) -> void:
	_orbit_t[i] += delta
	var k: float = clampf(_orbit_t[i] / _orbit_dur[i], 0.0, 1.0)
	var e: float = k * k * (3.0 - 2.0 * k)
	var from: Vector3 = _orbit_from[i]
	var vortex: bool = _orbit_kind[i] == 1
	var center: Vector3 = _well
	var r: float = from.x * pow(1.0 - e, 1.3)
	var a: float = from.y + _orbit_turns[i] * TAU * k * k
	var h: float = from.z * (1.0 - e) + sin(k * PI) * minf(3.0, 0.6 + from.x * 0.08)
	if vortex:
		# Hacia el mago (que se mueve): acaba girando a su alrededor, a la vista, y sube en arco
		# más alto cuanto más lejos estaba (la "lluvia de cristal" en espiral del GDD).
		if is_instance_valid(vortex_target):
			center = vortex_target.global_position + Vector3.UP * VORTEX_LIFT
		r = VORTEX_END_RADIUS + (from.x - VORTEX_END_RADIUS) * pow(1.0 - e, 1.4)
		a = from.y + _orbit_turns[i] * TAU * pow(k, 1.6)
		h = from.z * (1.0 - e) + sin(k * PI) * minf(4.0, 0.6 + from.x * 0.1)
	var body: RigidBody3D = _shards[i]
	var spin := Basis(Vector3(0.3, 1.0, 0.2).normalized(), delta * (4.0 + 12.0 * k))
	body.global_transform = Transform3D(
		spin * body.global_basis, center + Vector3(cos(a) * r, h, sin(a) * r)
	)
	# Encogen al llegar (los del Vórtice más: acaban girando a los pies, sin tapar la vista).
	_meshes[i].scale = Vector3.ONE * lerpf(1.0, 0.3 if vortex else 0.55, k * k)
	if k < 1.0:
		return
	_orbit_t[i] = -1.0
	_meshes[i].set_instance_shader_parameter("highlight", 0.0)
	if vortex:
		_halos[i].visible = _types[i] == RESONANT
		vortexed.emit(i)
	else:
		swallowed.emit(i)
	if _collect_t[i] <= 0.0 and _spawn_time[i] >= 0.0 and _shards[i].visible:
		# Nadie lo ha recogido: cae del pozo como un fragmento más.
		_meshes[i].scale = Vector3.ONE
		body.collision_layer = SHARD_LAYER
		body.freeze = false
		body.linear_velocity = Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1))
		_spawn_time[i] = _time


func _deactivate(body: RigidBody3D) -> void:
	var idx: int = body.get_meta(&"shard_index", -1)
	if idx >= 0 and idx < _halos.size():
		_halos[idx].visible = false
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = true
	body.visible = false
	body.collision_layer = 0
	body.contact_monitor = true
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO


func _on_shard_contact(_other: Node, index: int) -> void:
	var body: RigidBody3D = _shards[index]
	var speed: float = body.linear_velocity.length()
	if speed < 0.8 or _time - _last_clink < clink_min_gap_sec:
		return
	_last_clink = _time
	var p: AudioStreamPlayer3D = _clinks[_clink_next]
	_clink_next = (_clink_next + 1) % _clinks.size()
	p.global_position = body.global_position
	p.pitch_scale = _types[index].pickup_pitch
	p.volume_db = linear_to_db(clampf(speed / 6.0, 0.15, 1.0))
	p.play()
