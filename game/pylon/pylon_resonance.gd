class_name PylonResonance
extends Node3D
## La rama del Pilón (GDD 7) y sus hitos (GDD 4.2):
## - Resonancia del Pilón (mejora): cada pocos segundos el Pilón carga (la corona brilla y
##   zumba) y dispara un rayo al Cristal Madre que golpea como un hechizo de Rayo: arranca
##   cristal, suelta fragmentos y salta a otros puntos. Más fuerte cuanto más lleno el Pilón.
## - Hitos: al pasar cada marca tallada, una columna de luz sube al cielo con un coro y
##   campanas (el valle cambia a la vez, ver ValleyMilestones).

const PILLAR_SHADER: Shader = preload("res://pylon/pylon_pillar.gdshader")
const GLOW_SHADER: Shader = preload("res://fx/hd/hd_glow.gdshader")
const BOLT_ELEMENT: ElementDef = preload("res://data/elements/bolt.tres")
const CHARGE_SFX: AudioStream = preload("res://audio/sfx/sfx_pylon_charge_01.ogg")
const BOLT_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_pylon_bolt_01.ogg"),
	preload("res://audio/sfx/sfx_pylon_bolt_02.ogg"),
]
const ASCEND_SFX: AudioStream = preload("res://audio/sfx/sfx_pylon_ascend_01.ogg")
## Colores del maná del Pilón (rayo, columna).
const C_BOLT := Color(1.3, 0.75, 2.0)
const C_BOLT_HOT := Color(1.6, 1.6, 2.0)
const PILLAR_HEIGHT: float = 160.0
## Primer rayo tras comprar la mejora (o al empezar con ella): no hay que esperar el intervalo.
const FIRST_DELAY_SEC: float = 3.0

var pylon: ManaPylon

var _timer: float = 0.0
var _charge_t: float = -1.0
## Destello de la corona al disparar (1 -> 0).
var _flash_t: float = 0.0
var _pillar: MeshInstance3D
var _pillar_mat: ShaderMaterial
var _pillar_t: float = 0.0
var _crown_glow: MeshInstance3D
var _crown_mat: ShaderMaterial
var _embers: GPUParticles3D
var _charge_player: AudioStreamPlayer3D
var _bolt_player: AudioStreamPlayer3D
var _ascend_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	BOLT_ELEMENT.ensure_levels()
	_timer = _interval() - FIRST_DELAY_SEC
	_build_fx()
	_build_audio()
	Events.pylon_milestone.connect(_celebrate)
	Events.upgrade_bought.connect(
		func(id: StringName, _level: int) -> void:
			if id == &"pylon_resonance":
				_timer = maxf(_timer, _interval() - FIRST_DELAY_SEC)
	)


## Segundos entre rayos (0 = la mejora no está comprada).
func _interval() -> float:
	return GameState.stat(&"pylon_bolt_sec", 0.0)


## Fuerza del Pilón para su rayo: su nivel visible (0..1).
static func strength() -> float:
	return ManaPylon.display_fill(GameState.progression.pylon_ratio())


## Daño del rayo del Pilón ahora mismo (crece con lo lleno que está).
static func bolt_damage() -> int:
	var b: BalanceConfig = GameState.BALANCE
	return roundi(lerpf(float(b.pylon_bolt_damage_min), float(b.pylon_bolt_damage_max), strength()))


func _process(delta: float) -> void:
	var every: float = _interval()
	if every > 0.0 and _charge_t < 0.0:
		_timer += delta
		if _timer >= every:
			_timer = 0.0
			_charge_t = 0.0
			_charge_player.play()
	if _charge_t >= 0.0:
		var total: float = GameState.BALANCE.pylon_bolt_charge_sec
		_charge_t += delta
		var k: float = clampf(_charge_t / total, 0.0, 1.0)
		_crown_glow.visible = true
		_crown_mat.set_shader_parameter("intensity", k * k * 2.5)
		_crown_glow.scale = Vector3.ONE * (0.5 + k * 0.9 + sin(_charge_t * 40.0) * 0.05 * k)
		pylon.pulse(k * 0.6)
		if _charge_t >= total:
			_charge_t = -1.0
			fire()
	elif _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta * 3.0)
		_crown_mat.set_shader_parameter("intensity", _flash_t * 3.0)
		_crown_glow.scale = Vector3.ONE * (1.4 + (1.0 - _flash_t) * 1.2)
		_crown_glow.visible = _flash_t > 0.0
	if _pillar_t > 0.0:
		_pillar_t = maxf(0.0, _pillar_t - delta / 4.5)
		var rise: float = clampf((1.0 - _pillar_t) / 0.08, 0.0, 1.0)
		_pillar_mat.set_shader_parameter("reach", rise)
		_pillar_mat.set_shader_parameter("intensity", minf(1.0, _pillar_t * 1.6) * 0.75)
		_pillar.visible = _pillar_t > 0.0


## Dispara un rayo del Pilón al Cristal Madre (también para tests y demo). Devuelve dónde da, o
## null si no hay cristal a la vista.
func fire() -> Variant:
	var crystal: MotherCrystal = get_tree().get_first_node_in_group(&"mother_crystal")
	if crystal == null:
		return null
	var from: Vector3 = pylon.crown_position()
	var target: Dictionary = _pick_target(crystal, from)
	if target.is_empty():
		return null
	var at: Vector3 = target["position"]
	var n: Vector3 = target["normal"]
	var k: float = strength()
	var hit := SpellHit.new()
	hit.element_def = BOLT_ELEMENT
	hit.element = BOLT_ELEMENT.id
	var tiers: Array[SpellTier] = BOLT_ELEMENT.tiers
	hit.tier = tiers[clampi(roundi(k * float(tiers.size() - 1)), 0, tiers.size() - 1)]
	hit.damage = bolt_damage()
	hit.size = 1.0 + k * 0.5
	hit.position = at
	hit.normal = n
	hit.direction = (at - from).normalized()
	crystal.receive_hit(hit)
	# Las hebras se dibujan después del golpe: los rayos del cristal (pool de 40) no las pisan.
	# Tres: la principal gruesa, un núcleo blanco y una que se abre.
	crystal.draw_bolt(from, at, 0.8 + k * 0.6, C_BOLT, 0.55)
	crystal.draw_bolt(from, at, 0.25, C_BOLT_HOT, 0.4)
	crystal.draw_bolt(from + Vector3(0.0, 0.6, 0.0), at + n * 1.5, 0.22, C_BOLT * 0.8, 0.35)
	_flash_t = 1.0
	_bolt_player.global_position = at
	_bolt_player.play()
	pylon.pulse(1.5)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig and cam.global_position.distance_to(at) < 60.0:
		(cam as CameraRig).add_trauma(0.25)
	Events.pylon_bolt.emit(at)
	return at


## Punto de la cara del cristal que mira al Pilón (a una altura y un ángulo al azar).
func _pick_target(crystal: MotherCrystal, from: Vector3) -> Dictionary:
	var c: Vector3 = crystal.global_position
	var base: float = atan2(from.z - c.z, from.x - c.x)
	for attempt: int in 6:
		var a: float = base + _rng.randf_range(-0.45, 0.45)
		var y: float = _rng.randf_range(3.0, 26.0)
		var probe := Vector3(c.x + cos(a) * 70.0, y, c.z + sin(a) * 70.0)
		var surf: Dictionary = crystal.surface_toward(probe)
		if not surf.is_empty():
			return surf
	return {}


## Hito del Pilón: columna de luz, coro y campanas, chispas que suben y un destello del Pilón.
func _celebrate(index: int, mark: float) -> void:
	_pillar_t = 1.0
	_pillar.visible = true
	_pillar_mat.set_shader_parameter("reach", 0.0)
	_embers.restart()
	_ascend_player.play()
	pylon.pulse(3.0)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig and cam.global_position.distance_to(global_position) < 50.0:
		(cam as CameraRig).add_trauma(0.3)
	Events.hint.emit(tr("¡EL PILÓN LLEGA AL %d %%!") % roundi(mark * 100.0), Color("#ffd27a"))
	if index == ManaPylon.MARKS.size() - 1:
		Events.hint.emit(tr("¡EL PILÓN ESTÁ LLENO!"), Color("#c9f6ff"))


func _build_fx() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.2
	cyl.bottom_radius = 1.4
	cyl.height = PILLAR_HEIGHT
	cyl.radial_segments = 16
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_pillar = MeshInstance3D.new()
	_pillar.name = "Pillar"
	_pillar.mesh = cyl
	_pillar_mat = ShaderMaterial.new()
	_pillar_mat.shader = PILLAR_SHADER
	_pillar_mat.render_priority = 3
	_pillar_mat.set_shader_parameter("height", PILLAR_HEIGHT)
	_pillar.material_override = _pillar_mat
	_pillar.layers = MagicLayer.MAGIC_LAYER
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pillar.position.y = PILLAR_HEIGHT * 0.5 + ManaPylon.GLASS_BASE + ManaPylon.GLASS_HEIGHT
	_pillar.visible = false
	add_child(_pillar)
	_crown_glow = HdFx.quad(GLOW_SHADER, 5.0, 4)
	_crown_glow.name = "CrownGlow"
	_crown_mat = _crown_glow.material_override
	_crown_mat.set_shader_parameter("color", Color(0.85, 0.6, 1.0))
	_crown_mat.set_shader_parameter("rays", 1.0)
	_crown_mat.set_shader_parameter("ray_count", 8.0)
	_crown_glow.position.y = ManaPylon.GLASS_BASE + ManaPylon.GLASS_HEIGHT + 1.55
	_crown_glow.visible = false
	add_child(_crown_glow)
	_embers = HdFx.embers(
		90,
		0.35,
		PackedColorArray([Color(2.0, 1.8, 2.0), Color(1.4, 0.8, 2.2), Color(0.5, 1.4, 2.0)])
	)
	_embers.name = "MilestoneEmbers"
	_embers.one_shot = true
	_embers.explosiveness = 0.6
	_embers.lifetime = 3.0
	_embers.emitting = false
	var pm: ParticleProcessMaterial = _embers.process_material
	pm.emission_sphere_radius = 1.6
	pm.direction = Vector3.UP
	pm.spread = 20.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 16.0
	pm.gravity = Vector3(0.0, 1.5, 0.0)
	_embers.position.y = ManaPylon.GLASS_BASE + ManaPylon.GLASS_HEIGHT + 1.0
	add_child(_embers)


func _build_audio() -> void:
	_charge_player = AudioStreamPlayer3D.new()
	_charge_player.bus = &"SFX"
	_charge_player.stream = CHARGE_SFX
	_charge_player.unit_size = 16.0
	_charge_player.position.y = ManaPylon.GLASS_BASE + ManaPylon.GLASS_HEIGHT + 1.5
	add_child(_charge_player)
	var bolts := AudioStreamRandomizer.new()
	for s: AudioStream in BOLT_SFX:
		bolts.add_stream(-1, s)
	bolts.random_pitch = 1.08
	_bolt_player = AudioStreamPlayer3D.new()
	_bolt_player.bus = &"SFX"
	_bolt_player.stream = bolts
	_bolt_player.unit_size = 45.0
	_bolt_player.max_polyphony = 2
	_bolt_player.top_level = true
	add_child(_bolt_player)
	_ascend_player = AudioStreamPlayer.new()
	_ascend_player.bus = &"SFX"
	_ascend_player.stream = ASCEND_SFX
	_ascend_player.volume_db = -3.0
	add_child(_ascend_player)
