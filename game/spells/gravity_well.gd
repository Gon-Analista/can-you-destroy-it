class_name GravityWell
extends Node3D
## Gravedad (Arcano + Tierra, GDD 5.2: "atrae todos los fragmentos de la sala"). Se abre un pozo
## delante del mago: un agujero violeta que gira dentro de tres círculos arcanos (uno en el
## suelo), con un remolino de motas que caen hacia él. Todos los fragmentos sueltos del valle
## giran en espiral hasta el centro (`ShardPool.gravity_pull`) y, al llegar, van a la bolsa si
## caben; si no, a la tolva de la trituradora. Al cerrarse, implosión con destello.
## Todo se crea una vez (capa de magia HD); el pozo se reutiliza.

## Tamaño del agujero (escala del orbe) y de los círculos (m).
const ORB_SCALE: float = 5.5
const CIRCLE_SIZE: float = 2.0
const GROUND_CIRCLE_SIZE: float = 2.4

var active: bool = false
## Fragmentos que se ha tragado el último pozo.
var swallowed_count: int = 0

var _orb: SpellOrb
var _swirl: GPUParticles3D
var _burst: GPUParticles3D
var _light: OmniLight3D
var _circles: MagicCircles
var _shards: ShardPool
var _recipe: SpellRecipe
var _t: float = 0.0
var _sec: float = 2.5
var _caught: int = 0
## Latido al tragarse un fragmento (1 -> 0).
var _pulse: float = 0.0


func _ready() -> void:
	top_level = true
	var cols := PackedColorArray([Color(2.2, 1.6, 2.6), Color(1.6, 0.5, 1.9), Color(0.6, 0.2, 1.2)])
	_swirl = HdFx.embers(160, 0.1, cols)
	_swirl.name = "Swirl"
	_swirl.lifetime = 1.1
	_swirl.emitting = false
	var pm: ParticleProcessMaterial = _swirl.process_material
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = 7.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.5
	pm.radial_accel_min = -16.0
	pm.radial_accel_max = -10.0
	pm.tangential_accel_min = 8.0
	pm.tangential_accel_max = 14.0
	pm.damping_min = 0.0
	pm.damping_max = 0.5
	pm.turbulence_enabled = false
	add_child(_swirl)
	_burst = HdFx.sparks(90, 12.0, 0.05, cols)
	_burst.name = "Burst"
	add_child(_burst)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = Color(0.75, 0.45, 1.0)
	_light.omni_range = 8.0
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	visible = false
	set_process(false)


## Abre el pozo en `center` con el aspecto de `recipe` (círculos de `circles`, de cara a `facing`,
## la dirección hacia la cámara). Devuelve cuántos fragmentos atrapa.
func open(center: Vector3, facing: Vector3, recipe: SpellRecipe, circles: MagicCircles) -> int:
	_recipe = recipe
	_circles = circles
	_sec = maxf(recipe.gravity_sec, 0.6)
	_t = 0.0
	_caught = 0
	swallowed_count = 0
	global_position = center
	visible = true
	active = true
	if _orb == null:
		_orb = SpellOrb.new()
		_orb.name = "Hole"
		_orb.def = recipe.visual
		add_child(_orb)
	_orb.appear()
	_orb.charge = 0.2
	_swirl.restart()
	_swirl.emitting = true
	_light.visible = true
	var hot: Color = recipe.circle_hot
	var col: Color = recipe.circle_color
	var life: float = _sec + 0.35
	_circles.stamp(center - facing * 0.4, -facing, CIRCLE_SIZE, col, hot, life, 2.2)
	_circles.stamp(center - facing * 0.2, -facing, CIRCLE_SIZE * 0.62, hot, col, life, -3.6)
	var ground := Vector3(center.x, center.y - 1.9, center.z)
	_circles.stamp(ground, Vector3.DOWN, GROUND_CIRCLE_SIZE, col, hot, life, 1.2)
	_shards = get_tree().get_first_node_in_group(&"shard_pool") as ShardPool
	if _shards:
		if not _shards.swallowed.is_connected(_on_swallowed):
			_shards.swallowed.connect(_on_swallowed)
		_caught = _shards.gravity_pull(center, _sec)
	if _caught == 0:
		Events.hint.emit(tr("NO HAY FRAGMENTOS SUELTOS EN EL VALLE"), Color("#c79bff"))
	else:
		Events.hint.emit(tr("GRAVEDAD: %d FRAGMENTOS") % _caught, Color("#c79bff"))
	set_process(true)
	return _caught


func _process(delta: float) -> void:
	_t += delta
	var k: float = clampf(_t / _sec, 0.0, 1.0)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if _orb and cam:
		# El agujero crece con lo que se traga y late cada vez más deprisa antes de cerrarse.
		_pulse = maxf(0.0, _pulse - delta * 6.0)
		var pulse: float = 1.0 + sin(_t * (6.0 + 18.0 * k)) * 0.05 * k + _pulse * 0.12
		var s: float = ORB_SCALE * lerpf(0.55, 1.0, minf(1.0, _t / 0.35)) * pulse
		_orb.global_basis = cam.global_basis.scaled(Vector3.ONE * s)
		_orb.charge = lerpf(0.2, 0.95, k)
	if active:
		_light.light_energy = (1.0 + 1.5 * k + _pulse) * (1.0 + sin(_t * 20.0) * 0.15)
	else:
		_light.light_energy = maxf(0.0, _light.light_energy - delta * 8.0)
	if cam is CameraRig:
		(cam as CameraRig).add_trauma(delta * 0.25 * k)
	if _t >= _sec and active:
		_collapse()
	if not active and (_orb == null or not _orb.is_releasing()) and _t > _sec + 1.2:
		visible = false
		_light.visible = false
		set_process(false)


## El pozo se cierra: implosión con destello, chispas y sacudida.
func _collapse() -> void:
	active = false
	_swirl.emitting = false
	if _orb:
		_orb.charge = 1.0
		_orb.release()
	_burst.restart()
	_light.light_energy = 4.0
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig:
		(cam as CameraRig).add_trauma(0.45)
	if swallowed_count > 0:
		Events.hint.emit(tr("+%d FRAGMENTOS DEL POZO") % swallowed_count, Color("#ffd27a"))


## Un fragmento llegó al centro: a la bolsa o a la tolva (lo decide el mago).
func _on_swallowed(index: int) -> void:
	if not active and _t > _sec + 0.5:
		return
	swallowed_count += 1
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player and player.has_method(&"gravity_collect"):
		player.call(&"gravity_collect", index)
	# El agujero late al tragar.
	_pulse = 1.0
