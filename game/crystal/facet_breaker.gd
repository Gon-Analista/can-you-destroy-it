class_name FacetBreaker
extends Node
## Rompefacetas (nodo hito de la Resonancia, GDD 7: "críticos que rompen facetas enteras"). Con
## `facet_break` inscrito, un golpe resonante del mago parte una faceta entera: el cráter se queda
## con el daño de base y lo que pone la resonancia (x3), más `facet_mult` veces la base, sale de
## golpe en una losa poligonal a lo largo de la superficie (`CrystalVolume.carve_facet`): con
## `facet_mult` 1,5, la losa es 3,5 veces el cráter. La losa se ve: resbala cuesta abajo, se
## despega, cae dando vueltas y revienta contra el suelo en una lluvia de fragmentos (su
## esencia, como todo golpe: el maná es lo que pierde el cristal). Crujido grave, rayos por el
## contorno de la grieta, destello de todo el cristal, sacudida fuerte y un hit-stop mayor que el
## resonante.
##
## Reglas: el Núcleo no cede (máscara de capas) y la cuenta nunca baja del 99 %
## (`GameState.core_floor`: la losa no pide más de lo que queda por encima). El Corazón sólo
## cede ante combinados: allí sólo los combinados resonantes parten faceta, y más pequeña
## (`facet_heart_scale`). Los ecos (golpes menores), los familiares y el rayo del Pilón no.
## Lo crea MotherCrystal: `prepare` antes de excavar (rebaja el golpe a su base) y `try_break`
## después (la losa).

const UPGRADE: StringName = &"facet_break"
const STAT: StringName = &"facet_mult"
const SHARD_SHADER: Shader = preload("res://crystal/shard.gdshader")
const BREAK_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_facet_break_01.ogg"),
	preload("res://audio/sfx/sfx_facet_break_02.ogg"),
]
const CRASH_SFX: AudioStream = preload("res://audio/sfx/sfx_facet_crash_01.ogg")
const HEART_LAYER: int = 3
## Losas que pueden ir cayendo a la vez (se reutilizan).
const SLABS: int = 3
## Parte de los fragmentos que salta de la grieta al romperse (el resto, al reventar la losa).
const CRACK_SHARE: float = 0.3
## Segundos que la losa resbala pegada a la cara antes de despegarse, y su aceleración (m/s2).
const SLIDE_SEC: float = 0.45
const SLIDE_ACCEL: float = 9.0
const GRAVITY: float = 18.0
const MAX_FALL_SEC: float = 4.0
const C_HINT := Color("#ffd27a")
const ARC_GOLD := Color(2.2, 1.6, 0.6)

## Facetas rotas (pruebas y depuración) y esencia de la última.
var broken: int = 0
var last_essence: float = 0.0

## Esencia que pide la losa del golpe en curso (lo apunta `prepare`).
var _slab_damage: float = 0.0
var _crystal: MotherCrystal
var _arcs: CrystalArcs
var _shards: ShardPool
var _hd_fx: HdImpact
var _rng := RandomNumberGenerator.new()
var _slabs: Array[MeshInstance3D] = []
var _slab_t: PackedFloat32Array = PackedFloat32Array()
var _slab_vel: Array[Vector3] = []
var _slab_spin: Array[Vector3] = []
var _slab_slide: Array[Vector3] = []
var _slab_worth: PackedFloat32Array = PackedFloat32Array()
var _slab_layer: PackedInt32Array = PackedInt32Array()
var _materials: Array[ShaderMaterial] = []
var _break_player: AudioStreamPlayer3D
var _crash_player: AudioStreamPlayer3D
var _dust: GPUParticles3D


func _init() -> void:
	name = "FacetBreaker"


func setup(crystal: MotherCrystal, arcs: CrystalArcs, shards: ShardPool, hd_fx: HdImpact) -> void:
	_crystal = crystal
	_arcs = arcs
	_shards = shards
	_hd_fx = hd_fx
	_rng.randomize()
	for layer: CrystalLayerDef in GameState.LAYERS:
		var m := ShaderMaterial.new()
		m.shader = SHARD_SHADER
		for key: String in ["col_highlight", "col_light", "col_mid", "col_dark", "col_core"]:
			m.set_shader_parameter(key, layer.get(key))
		_materials.append(m)
	for i: int in SLABS:
		var mi := MeshInstance3D.new()
		mi.name = "Slab%d" % i
		mi.top_level = true
		mi.visible = false
		mi.extra_cull_margin = 8.0
		add_child(mi)
		_slabs.append(mi)
		_slab_t.append(-1.0)
		_slab_vel.append(Vector3.ZERO)
		_slab_spin.append(Vector3.ZERO)
		_slab_slide.append(Vector3.DOWN)
		_slab_worth.append(0.0)
		_slab_layer.append(0)
	_break_player = _player_3d("Break", 40.0, 4.0)
	_crash_player = _player_3d("Crash", 30.0, 2.0)
	_dust = HdFx.smoke(40, 4.5, Color(0.85, 0.92, 1.0))
	_dust.name = "Dust"
	add_child(_dust)
	set_process(false)


## Antes de excavar (con todos los multiplicadores ya puestos): si el golpe va a partir faceta,
## el cráter se queda con su daño de base y la losa se apunta lo que pone la resonancia más
## `facet_mult` veces la base (en el Corazón, por `facet_heart_scale`, y sólo con combinados).
func prepare(hit: SpellHit) -> void:
	_slab_damage = 0.0
	if not hit.resonant or not hit.by_player or hit.minor or hit.damage <= 1:
		return
	var mult: float = GameState.stat(STAT, 0.0)
	if mult <= 0.0:
		return
	var combo: bool = hit.recipe != null
	if _layer_of(hit) >= HEART_LAYER:
		if not combo:
			return
		mult *= GameState.BALANCE.facet_heart_scale
	var base: int = maxi(1, roundi(float(hit.damage) / GameState.BALANCE.resonant_damage_mult))
	_slab_damage = float(hit.damage - base) + float(base) * mult
	hit.damage = base


## Tras el golpe (si arrancó cristal): la losa que apuntó `prepare`. Devuelve su esencia (0 si
## no hubo).
func try_break(hit: SpellHit) -> float:
	var want: float = _slab_damage
	_slab_damage = 0.0
	if want < 1.0:
		return 0.0
	# Nunca por debajo del 99 %: la losa no pide más de lo que queda por encima del Núcleo.
	var room: float = float(GameState.progression.essence - GameState.core_floor)
	var target: float = minf(want, room)
	if target < 1.0:
		return 0.0
	return _break(hit, target, _allowed(hit.recipe != null))


## Capa en la que cae el golpe (como MotherCrystal._dig: un poco por dentro de la cara).
func _layer_of(hit: SpellHit) -> int:
	var n: Vector3 = (_crystal.global_basis.inverse() * hit.normal).normalized()
	return _crystal.volume.layer_at(_crystal.to_local(hit.position) - n * 0.35)


## Capas que cede la losa (como un golpe: el Corazón sólo con combinados; el Núcleo, nunca).
func _allowed(combo: bool) -> int:
	var mask: int = 0
	for i: int in GameState.LAYERS.size():
		var layer: CrystalLayerDef = GameState.LAYERS[i]
		if not layer.immune and not (layer.needs_combo and not combo):
			mask |= 1 << i
	return mask


func _break(hit: SpellHit, target: float, allowed: int) -> float:
	var bal: BalanceConfig = GameState.BALANCE
	var vol: CrystalVolume = _crystal.volume
	var p0: Vector3 = _crystal.to_local(hit.position)
	var n: Vector3 = (_crystal.global_basis.inverse() * hit.normal).normalized()
	if n.length_squared() < 0.5:
		n = vol.normal_at(p0)
	var frame: Basis = _frame(n)
	var sides: int = _rng.randi_range(5, 7)
	var turn: float = _rng.randf() * TAU
	var tilt := Vector2(_rng.randf_range(-0.04, 0.04), _rng.randf_range(-0.04, 0.04))
	# Ajuste en seco (como un golpe): el radio que arranca la esencia pedida.
	var density: float = vol.layer_density[clampi(hit.layer, 0, vol.layer_density.size() - 1)]
	var radius: float = clampf(
		pow(target / density / (PI * bal.facet_depth_ratio), 1.0 / 3.0), 1.2, bal.facet_max_radius
	)
	var poly: PackedVector2Array = _polygon(sides, turn, 1.0)
	for attempt: int in 6:
		var shape: PackedVector2Array = _scaled(poly, radius)
		var depth_m: float = radius * bal.facet_depth_ratio
		var dry: float = (
			vol.carve_facet(p0, frame, shape, depth_m, tilt, allowed, false, 2)["essence"]
		)
		if (dry >= target * 0.8 and dry <= target * 1.2) or attempt == 5:
			break
		var k: float = clampf(target / maxf(dry, target * 0.1), 0.3, 4.0)
		radius = clampf(radius * pow(k, 1.0 / 3.0), 1.0, bal.facet_max_radius)
	var final_shape: PackedVector2Array = _scaled(poly, radius)
	var thick: float = radius * bal.facet_depth_ratio
	var r: Dictionary = vol.carve_facet(p0, frame, final_shape, thick, tilt, allowed)
	var carved: float = r["essence"]
	var essence: float = minf(carved, target * 1.25)
	if essence < 1.0:
		return 0.0
	var removed: float = _crystal.apply_carve(r, p0, radius, essence)
	broken += 1
	last_essence = removed
	_react(hit, frame, final_shape, thick, removed)
	return removed


## Base de la faceta: y = normal hacia fuera, x y z en su plano (x lo más horizontal posible).
static func _frame(n: Vector3) -> Basis:
	var ref: Vector3 = Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
	var x: Vector3 = ref.cross(n).normalized()
	var z: Vector3 = x.cross(n).normalized()
	return Basis(x, n, z)


## Polígono convexo irregular de radio 1 (antihorario en x-z).
func _polygon(sides: int, turn: float, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k: int in sides:
		var a: float = turn + TAU * (float(k) + _rng.randf_range(-0.2, 0.2)) / float(sides)
		var r: float = scale * _rng.randf_range(0.78, 1.0)
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


static func _scaled(poly: PackedVector2Array, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in poly:
		out.append(p * s)
	return out


## La reacción: crujido, rayos por la grieta, destello, sacudida, hit-stop, fragmentos de la
## grieta y la losa que empieza a resbalar.
func _react(
	hit: SpellHit, frame: Basis, poly: PackedVector2Array, thick: float, worth: float
) -> void:
	var bal: BalanceConfig = GameState.BALANCE
	var at: Vector3 = hit.position
	var gb: Basis = _crystal.global_basis * frame
	var gn: Vector3 = gb.y.normalized()
	var layer: int = hit.layer
	var scale_m: float = gb.y.length()
	# Rayos dorados que recorren el contorno y grietas que se quedan en cada vértice.
	for k: int in poly.size():
		var a: Vector2 = poly[k]
		var b: Vector2 = poly[(k + 1) % poly.size()]
		var pa: Vector3 = at + gb * Vector3(a.x, 0.0, a.y)
		var pb: Vector3 = at + gb * Vector3(b.x, 0.0, b.y)
		_arcs.bolt_between(pa, pb, 0.18, ARC_GOLD, 0.35)
		_crystal.add_crack(pa, thick * scale_m * 0.6)
	_arcs.strike(at, gn, 2.2, ARC_GOLD)
	_hd_fx.play(at, gn, hit.tier, true, true, maxf(2.0, thick))
	_crystal.flash(0.9)
	# Los fragmentos que saltan de la grieta al partirse (una parte de la esencia).
	var crack_worth: float = worth * CRACK_SHARE
	for k: int in 2:
		var edge: Vector2 = poly[_rng.randi() % poly.size()] * 0.8
		_shards.spawn_worth(
			at + gb * Vector3(edge.x, 0.0, edge.y), gn, crack_worth * 0.5, 1.5, layer
		)
	_break_player.global_position = at
	_break_player.stream = BREAK_SFX[_rng.randi() % BREAK_SFX.size()]
	_break_player.pitch_scale = _rng.randf_range(0.94, 1.04)
	_break_player.play()
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig:
		(cam as CameraRig).add_trauma(0.7)
		(cam as CameraRig).punch_fov(-4.0)
	HitStop.trigger(get_tree(), bal.facet_hit_stop_sec)
	Events.hint.emit(tr("¡FACETA ROTA!  -%s") % Hud.format_int(roundi(worth)), C_HINT)
	_launch_slab(at, gb, poly, thick, worth - crack_worth, layer)


## La losa: el prisma del polígono (la cara de fuera arriba), con la paleta de su capa.
func _launch_slab(
	at: Vector3, gb: Basis, poly: PackedVector2Array, thick: float, worth: float, layer: int
) -> void:
	var i: int = _free_slab()
	var mi: MeshInstance3D = _slabs[i]
	var st: SurfaceTool = MeshKit.begin()
	var inside := Vector3(0.0, -thick * 0.5, 0.0)
	var c := Color.WHITE
	for k: int in poly.size():
		var a: Vector2 = poly[k]
		var b: Vector2 = poly[(k + 1) % poly.size()]
		var ta := Vector3(a.x, 0.0, a.y)
		var tb := Vector3(b.x, 0.0, b.y)
		var ba := Vector3(a.x * 0.92, -thick, a.y * 0.92)
		var bb := Vector3(b.x * 0.92, -thick, b.y * 0.92)
		MeshKit.add_tri(st, Vector3.ZERO, ta, tb, c, inside)
		MeshKit.add_tri(st, Vector3(0.0, -thick, 0.0), ba, bb, c, inside)
		MeshKit.add_quad(st, ta, tb, bb, ba, c, inside)
	mi.mesh = MeshKit.commit(st)
	mi.material_override = _materials[clampi(layer, 0, _materials.size() - 1)]
	mi.set_instance_shader_parameter("glint_seed", _rng.randf())
	mi.set_instance_shader_parameter("spawn_flash", 1.0)
	# La base lleva la escala del cristal: la losa mide lo mismo que el hueco que deja.
	mi.global_transform = Transform3D(gb, at + gb.y.normalized() * 0.15)
	mi.visible = true
	# Cuesta abajo por la cara (la gravedad en su plano) y un poco hacia fuera.
	var n: Vector3 = gb.y.normalized()
	var down: Vector3 = Vector3.DOWN - n * Vector3.DOWN.dot(n)
	_slab_slide[i] = down.normalized() if down.length_squared() > 0.01 else -gb.z.normalized()
	_slab_vel[i] = n * 1.2
	_slab_spin[i] = Vector3(
		_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.4), _rng.randf_range(-1.0, 1.0)
	)
	_slab_t[i] = 0.0
	_slab_worth[i] = worth
	_slab_layer[i] = layer
	set_process(true)


func _free_slab() -> int:
	var oldest: int = 0
	for i: int in SLABS:
		if _slab_t[i] < 0.0:
			return i
		if _slab_t[i] > _slab_t[oldest]:
			oldest = i
	_shatter(oldest)  # todas cayendo: la más vieja revienta ya
	return oldest


func _process(delta: float) -> void:
	var any: bool = false
	for i: int in SLABS:
		if _slab_t[i] < 0.0:
			continue
		any = true
		_slab_t[i] += delta
		var mi: MeshInstance3D = _slabs[i]
		if _slab_t[i] < SLIDE_SEC:
			# Resbala pegada a la cara, rascando, cada vez más deprisa.
			_slab_vel[i] += _slab_slide[i] * SLIDE_ACCEL * delta
		else:
			_slab_vel[i] += Vector3.DOWN * GRAVITY * delta
			var spin: Vector3 = _slab_spin[i] * delta * 2.2
			mi.global_basis = Basis.from_euler(spin) * mi.global_basis
		mi.global_position += _slab_vel[i] * delta
		var p: Vector3 = mi.global_position
		if p.y < Valley.ground_height(p.x, p.z) + 0.4 or _slab_t[i] > MAX_FALL_SEC:
			_shatter(i)
		elif _slab_t[i] > 0.12:
			mi.set_instance_shader_parameter("spawn_flash", 0.0)
	if not any:
		set_process(false)


## La losa revienta contra el suelo: polvo, estruendo, sacudida según lo cerca y la lluvia de
## fragmentos (el resto de su esencia).
func _shatter(i: int) -> void:
	var mi: MeshInstance3D = _slabs[i]
	var at: Vector3 = mi.global_position
	at.y = maxf(at.y, Valley.ground_height(at.x, at.z) + 0.3)
	_slab_t[i] = -1.0
	mi.visible = false
	var worth: float = _slab_worth[i]
	for k: int in 3:
		var off := Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))
		_shards.spawn_worth(at + off, Vector3.UP, worth / 3.0, 1.7, _slab_layer[i])
	_dust.global_position = at
	_dust.restart()
	_hd_fx.play(at, Vector3.UP, SpellCaster.ELEMENT.tiers[4], false, true, 3.0)
	_crash_player.global_position = at
	_crash_player.pitch_scale = _rng.randf_range(0.92, 1.05)
	_crash_player.play()
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig:
		var d: float = cam.global_position.distance_to(at)
		(cam as CameraRig).add_trauma(clampf(0.55 - d * 0.008, 0.12, 0.55))


func _player_3d(node_name: String, unit: float, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.bus = &"SFX"
	p.unit_size = unit
	p.max_db = db
	p.volume_db = 0.0
	p.max_distance = 400.0
	add_child(p)
	return p
