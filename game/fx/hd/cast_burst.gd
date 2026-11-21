class_name CastBurst
extends Node3D
## El golpe de poder al soltar un combinado (capa de magia HD): fogonazo entre las palmas, ondas
## de choque que salen en cono hacia donde apuntas (una detrás de otra, cada vez más grandes),
## chispas disparadas hacia delante y un pulso de luz. Lo acompañan el retroceso del mago, de la
## cámara y de las manos (ver `SpellCaster._release_kick`). Escala con `strength` (0 un toque,
## 1 carga completa, ~2 a nivel alto cargado a tope). Se crea una vez; nada se instancia al usarlo.

## Ondas del cono: distancia a las manos (m) y tamaño (m) de cada una con fuerza 1.
const RING_DIST: PackedFloat32Array = [0.5, 1.6, 3.2]
const RING_SIZE: PackedFloat32Array = [1.1, 2.4, 4.0]
## Lo que tarda en abrirse cada onda y el retraso entre una y la siguiente (s).
const RING_SEC: float = 0.32
const RING_STAGGER: float = 0.045
const FLASH_SEC: float = 0.16
const LIFE_SEC: float = 0.7

var _flash: MeshInstance3D
var _flash_mat: ShaderMaterial
var _rings: Array[MeshInstance3D] = []
var _ring_mats: Array[ShaderMaterial] = []
var _sparks: GPUParticles3D
var _light: OmniLight3D
var _t: float = -1.0
var _strength: float = 1.0
var _origin := Vector3.ZERO
var _dir := Vector3.FORWARD


func _ready() -> void:
	top_level = true
	_flash = HdFx.quad(HdFx.GLOW_SHADER, 1.0, 9)
	_flash.name = "Flash"
	_flash_mat = _flash.material_override
	_flash_mat.set_shader_parameter("rays", 1.3)
	_flash_mat.set_shader_parameter("ray_count", 7.0)
	_flash_mat.set_shader_parameter("falloff", 2.6)
	# Tiñe más que suma: pegado a la cámara, sumado, sería un fogonazo blanco a pantalla entera.
	_flash_mat.set_shader_parameter("cover", 0.3)
	add_child(_flash)
	for i: int in RING_DIST.size():
		var ring: MeshInstance3D = HdFx.quad(HdFx.RING_SHADER, 1.0, 8)
		ring.name = "Shock%d" % i
		var m: ShaderMaterial = ring.material_override
		m.set_shader_parameter("intensity", 1.6 - 0.3 * float(i))
		m.set_shader_parameter("cover", 0.55)
		add_child(ring)
		_rings.append(ring)
		_ring_mats.append(m)
	_sparks = HdFx.sparks(
		70, 22.0, 0.035, PackedColorArray([Color(2, 1.8, 1.2), Color(1, 0.5, 0.2)])
	)
	_sparks.name = "Sparks"
	_sparks.lifetime = 0.45
	_sparks.trail_lifetime = 0.09
	var spm: ParticleProcessMaterial = _sparks.process_material
	spm.spread = 22.0
	spm.gravity = Vector3(0, -4.0, 0)
	spm.emission_sphere_radius = 0.12
	add_child(_sparks)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.shadow_enabled = false
	_light.omni_range = 6.0
	add_child(_light)
	_hide()


## Suelta el golpe en `origin` (entre las manos) hacia `dir`, con los colores del hechizo.
func play(origin: Vector3, dir: Vector3, color: Color, hot: Color, strength: float) -> void:
	_origin = origin
	_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	_strength = clampf(strength, 0.15, 2.5)
	global_position = origin
	var glow := Color(color.r, color.g, color.b)
	_flash.global_position = origin + _dir * 0.15
	_flash_mat.set_shader_parameter("color", Color(hot.r, hot.g, hot.b))
	_flash_mat.set_shader_parameter("seed", randf() * 10.0)
	for i: int in _rings.size():
		_ring_mats[i].set_shader_parameter("color", glow if i > 0 else Color(hot.r, hot.g, hot.b))
		_ring_mats[i].set_shader_parameter("seed", randf() * 10.0)
		_rings[i].global_position = origin + _dir * RING_DIST[i] * lerpf(0.8, 1.3, _strength / 2.0)
	var cols := PackedColorArray([Color(hot.r, hot.g, hot.b) * 1.6, glow * 1.2])
	var spm: ParticleProcessMaterial = _sparks.process_material
	spm.color_ramp = HdFx.color_ramp(cols)
	spm.direction = _dir
	spm.initial_velocity_min = 8.0 + 6.0 * _strength
	spm.initial_velocity_max = 14.0 + 14.0 * _strength
	_sparks.global_position = origin + _dir * 0.3
	_sparks.amount_ratio = clampf(0.25 + 0.4 * _strength, 0.25, 1.0)
	_sparks.restart()
	_light.light_color = glow
	_light.global_position = origin + _dir * 0.8
	visible = true
	_t = 0.0
	_animate()
	set_process(true)


func _process(delta: float) -> void:
	if _t < 0.0:
		set_process(false)
		return
	_t += delta
	_animate()
	if _t >= LIFE_SEC:
		_hide()


func _animate() -> void:
	var s: float = _strength
	var fk: float = clampf(_t / FLASH_SEC, 0.0, 1.0)
	_flash.visible = fk < 1.0
	_flash.scale = Vector3.ONE * lerpf(0.3, 0.6, sqrt(fk)) * (0.4 + 0.2 * s)
	_flash_mat.set_shader_parameter(
		"intensity", (1.0 - fk) * (1.0 - fk) * (0.2 + 0.15 * s) * HdFx.flash_scale
	)
	for i: int in _rings.size():
		var k: float = clampf((_t - RING_STAGGER * float(i)) / RING_SEC, 0.0, 1.0)
		# Con poca carga sólo sale la primera onda; a tope, las tres.
		var on: bool = float(i) < 1.0 + s * 1.5
		_rings[i].visible = on and k > 0.0 and k < 1.0
		_rings[i].scale = Vector3.ONE * RING_SIZE[i] * lerpf(0.7, 1.25, s / 2.0)
		_ring_mats[i].set_shader_parameter("progress", k)
	_light.light_energy = 6.0 * s * (1.0 - fk) * HdFx.flash_scale
	_light.visible = fk < 1.0


func _hide() -> void:
	_t = -1.0
	visible = false
	_flash.visible = false
	for r: MeshInstance3D in _rings:
		r.visible = false
	_light.visible = false
	set_process(false)
