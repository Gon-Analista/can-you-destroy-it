class_name Supernova
extends Node3D
## Supernova (triple: Chispa + Tierra + Arcano). La estrella llega al cristal y no estalla: se
## queda flotando sobre la superficie, se contrae tragándose la luz (motas que caen hacia ella,
## un círculo que gira cada vez más deprisa, la luz del valle que se apaga a su alrededor) y,
## a los `nova_sec` s, revienta: el golpe de verdad (área enorme y quemadura) con destello,
## onda de choque, sacudida y un estruendo grave.
## Pool de dos estrellas (nada se instancia en caliente).

const GATHER_SFX: AudioStream = preload("res://audio/sfx/sfx_nova_gather_01.ogg")
const VISUAL: SpellVisualDef = preload("res://data/spells/vfx_supernova.tres")
const POOL: int = 2
## Distancia a la superficie a la que flota la estrella (m) y su tamaño al contraerse.
const LIFT: float = 1.6
const STAR_SCALE: float = 7.0
## A partir de esta distancia (m) la estrella crece con ella: desde lejos también se ve.
const SEEN_FROM: float = 22.0

## Los círculos mágicos del lanzador (un sello gira bajo la estrella).
var circles: MagicCircles
var _stars: Array[SpellOrb] = []
var _swirls: Array[GPUParticles3D] = []
var _lights: Array[OmniLight3D] = []
var _sounds: Array[AudioStreamPlayer3D] = []
var _hits: Array[SpellHit] = []
var _crystals: Array[MotherCrystal] = []
var _age: PackedFloat32Array = PackedFloat32Array()
var _sec: PackedFloat32Array = PackedFloat32Array()
var _anchor: PackedVector3Array = PackedVector3Array()
var _base_scale: PackedFloat32Array = PackedFloat32Array()
var _camera: Camera3D


func _ready() -> void:
	top_level = true
	var cols := PackedColorArray([Color(2.6, 2.3, 1.6), Color(2.0, 0.9, 1.4), Color(0.9, 0.4, 1.4)])
	for i: int in POOL:
		var star := SpellOrb.new()
		star.name = "Star%d" % i
		star.def = VISUAL
		star.charge = 0.0
		star.top_level = true
		star.visible = false
		add_child(star)
		_stars.append(star)
		var swirl: GPUParticles3D = HdFx.embers(120, 0.18, cols)
		swirl.name = "Swirl%d" % i
		swirl.lifetime = 0.6
		var pm: ParticleProcessMaterial = swirl.process_material
		pm.emission_sphere_radius = 7.0
		pm.radial_velocity_min = -16.0
		pm.radial_velocity_max = -11.0
		pm.gravity = Vector3.ZERO
		swirl.emitting = false
		add_child(swirl)
		_swirls.append(swirl)
		var light := OmniLight3D.new()
		light.name = "Light%d" % i
		light.light_color = Color(1.0, 0.8, 0.6)
		light.omni_range = 26.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		add_child(light)
		_lights.append(light)
		var snd := AudioStreamPlayer3D.new()
		snd.name = "Gather%d" % i
		snd.bus = &"SFX"
		snd.stream = GATHER_SFX
		snd.unit_size = 25.0
		add_child(snd)
		_sounds.append(snd)
		_hits.append(null)
		_crystals.append(null)
	_age.resize(POOL)
	_sec.resize(POOL)
	_anchor.resize(POOL)
	_base_scale.resize(POOL)
	set_process(false)


## La estrella llegó a `crystal` con el golpe `hit`: se contrae y estalla tras `nova_sec`.
func ignite(hit: SpellHit, crystal: MotherCrystal, camera: Camera3D) -> void:
	_camera = camera
	var i: int = _free()
	if i < 0:
		crystal.receive_hit(hit)
		return
	_hits[i] = hit
	_crystals[i] = crystal
	_age[i] = 0.0
	_sec[i] = maxf(hit.recipe.nova_sec, 0.1)
	var n: Vector3 = hit.normal if hit.normal.length_squared() > 0.01 else Vector3.BACK
	var at: Vector3 = hit.position + n * LIFT
	var star: SpellOrb = _stars[i]
	_anchor[i] = at
	star.global_position = at
	var far: float = camera.global_position.distance_to(at) / SEEN_FROM if camera else 1.0
	_base_scale[i] = STAR_SCALE * hit.size * maxf(1.0, far)
	star.scale = Vector3.ONE * _base_scale[i] * 1.4
	star.appear()
	star.charge = 0.6
	_swirls[i].global_position = at
	_swirls[i].emitting = true
	_lights[i].global_position = at
	_sounds[i].global_position = at
	_sounds[i].play()
	if circles:
		circles.stamp(
			hit.position + n * 0.3,
			n,
			hit.recipe.area_radius * 1.4 * hit.size,
			hit.recipe.circle_color,
			hit.recipe.circle_hot,
			_sec[i] + 0.2,
			6.0,
			0.6
		)
	set_process(true)


## Pantalla de carga: una estrella que estalla delante de la cámara (compila sus efectos).
func warm_up(at: Vector3, _cam: Camera3D) -> void:
	var star: SpellOrb = _stars[0]
	star.global_position = at
	star.scale = Vector3.ONE * STAR_SCALE
	star.appear()
	star.flare(1.0)
	_swirls[0].global_position = at
	_swirls[0].restart()
	get_tree().create_timer(0.3).timeout.connect(
		func() -> void:
			star.release()
			_swirls[0].emitting = false
	)


func _process(delta: float) -> void:
	var busy: bool = false
	for i: int in POOL:
		if _hits[i] == null:
			continue
		busy = true
		_age[i] += delta
		var k: float = clampf(_age[i] / _sec[i], 0.0, 1.0)
		var star: SpellOrb = _stars[i]
		# Se contrae (más pequeña y más brillante) y tiembla cada vez más.
		star.charge = lerpf(0.6, 1.0, k)
		star.scale = Vector3.ONE * _base_scale[i] * lerpf(1.4, 0.5, k * k)
		var jitter: float = k * 0.25
		star.global_position = (
			_anchor[i]
			+ Vector3(
				randf_range(-jitter, jitter),
				randf_range(-jitter, jitter),
				randf_range(-jitter, jitter)
			)
		)
		_lights[i].light_energy = lerpf(0.5, 7.0, k * k)
		if _camera is CameraRig:
			(_camera as CameraRig).add_trauma(delta * 0.5 * k)
		if k >= 1.0:
			_detonate(i)
	if not busy:
		set_process(false)


func _detonate(i: int) -> void:
	var hit: SpellHit = _hits[i]
	var crystal: MotherCrystal = _crystals[i]
	_hits[i] = null
	_crystals[i] = null
	_stars[i].release()
	_swirls[i].emitting = false
	_lights[i].light_energy = 0.0
	if is_instance_valid(crystal):
		crystal.receive_hit(hit)
		crystal.flash(1.0)
	if _camera is CameraRig:
		(_camera as CameraRig).add_trauma(0.9)


func _free() -> int:
	for i: int in POOL:
		if _hits[i] == null:
			return i
	return -1
