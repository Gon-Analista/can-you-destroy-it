class_name HdImpact
extends Node3D
## Impacto de un hechizo en la capa de magia HD (pool, nada se instancia en caliente):
## destello con rayos, cuerpo del hechizo que se hincha y se deshace, onda de choque, chispas con
## estela, motas y humo. Colores de la estela del hechizo; tamaño según el radio de grieta del
## nivel (un golpe resonante o una Bola de Fuego, mucho más). Cada elemento estalla a su manera
## (`ImpactStyle`): forma del cuerpo, chispas, humo o polvo, ondas y destello.

## Capa grave de cada estilo, en el orden de `ImpactStyle` (`tools/sfx_impacts.py`).
const BODY_SFX: Array[String] = ["fire", "arcane", "ice", "bolt", "rock", "wind"]

const STAR_SHADER: Shader = preload("res://fx/hd/hd_hitspark.gdshader")

## Vida máxima de un impacto (s): lo que tarda en apagarse lo más lento (nieve, motas arcanas).
const LIFETIME: float = 2.2

@export var pool_size: int = 8

var _slots: Array[Node3D] = []
var _fire: Array[ShaderMaterial] = []
var _fire_mi: Array[MeshInstance3D] = []
var _flash: Array[ShaderMaterial] = []
var _flash_mi: Array[MeshInstance3D] = []
var _ring: Array[ShaderMaterial] = []
var _ring_mi: Array[MeshInstance3D] = []
## Segunda onda (eco del Arcano, doble ráfaga del Viento).
var _ring2: Array[ShaderMaterial] = []
var _ring2_mi: Array[MeshInstance3D] = []
## Chispa de golpe: estrella de puntas con contorno oscuro (`hd_hitspark.gdshader`).
var _star: Array[ShaderMaterial] = []
var _star_mi: Array[MeshInstance3D] = []
var _sparks: Array[GPUParticles3D] = []
var _embers: Array[GPUParticles3D] = []
var _smoke: Array[GPUParticles3D] = []
var _age: PackedFloat32Array = []
var _size: PackedFloat32Array = []
var _peak: PackedFloat32Array = []
## Tamaño extra de la bola de fuego (los combinados estallan más grandes).
var _fire_k: PackedFloat32Array = []
## Perfil de `ImpactStyle` de cada impacto en curso.
var _prof: Array[ImpactStyle.Profile] = []
var _next: int = 0
var _default_ramp: Gradient
## Cuerpo del golpe (sólo los de una mano: los combinados ya tienen su estruendo).
var _body_player: AudioStreamPlayer3D
var _body_sounds: Array[AudioStreamRandomizer] = []


func _ready() -> void:
	_default_ramp = Gradient.new()
	_default_ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 1.0])
	_default_ramp.colors = PackedColorArray(
		[Color(2.0, 2.0, 2.0), Color("#c9f6ff"), Color("#458fb8"), Color(0.16, 0.29, 0.53, 0.0)]
	)
	for i: int in pool_size:
		var slot := Node3D.new()
		slot.name = "Impact%d" % i
		slot.top_level = true
		add_child(slot)
		var flash: MeshInstance3D = HdFx.quad(HdFx.GLOW_SHADER, 1.0, 3)
		slot.add_child(flash)
		var fire: MeshInstance3D = HdFx.quad(HdFx.FIRE_SHADER, 1.0, 5)
		slot.add_child(fire)
		var ring: MeshInstance3D = _make_ring()
		slot.add_child(ring)
		var ring2: MeshInstance3D = _make_ring()
		slot.add_child(ring2)
		var star: MeshInstance3D = HdFx.quad(STAR_SHADER, 1.0, 9)
		star.visible = false
		slot.add_child(star)
		var sparks: GPUParticles3D = HdFx.sparks(
			60, 9.0, 0.05, PackedColorArray([Color(2, 1.8, 1.2), Color(1, 0.5, 0.2)])
		)
		slot.add_child(sparks)
		var embers: GPUParticles3D = HdFx.embers(
			40, 0.14, PackedColorArray([Color(2, 1.6, 1.0), Color(1, 0.4, 0.15)])
		)
		embers.one_shot = true
		embers.explosiveness = 0.9
		embers.emitting = false
		embers.lifetime = 1.2
		var epm: ParticleProcessMaterial = embers.process_material
		epm.initial_velocity_min = 1.0
		epm.initial_velocity_max = 4.0
		epm.emission_sphere_radius = 0.6
		slot.add_child(embers)
		var smoke: GPUParticles3D = HdFx.smoke(14, 2.2, Color(0.44, 0.39, 0.4))
		smoke.lifetime = 1.6
		(smoke.process_material as ParticleProcessMaterial).spread = 75.0
		slot.add_child(smoke)
		_slots.append(slot)
		_fire.append(fire.material_override as ShaderMaterial)
		_fire_mi.append(fire)
		_flash.append(flash.material_override as ShaderMaterial)
		_flash_mi.append(flash)
		_ring.append(ring.material_override as ShaderMaterial)
		_ring_mi.append(ring)
		_ring2.append(ring2.material_override as ShaderMaterial)
		_ring2_mi.append(ring2)
		_star.append(star.material_override as ShaderMaterial)
		_star_mi.append(star)
		_prof.append(ImpactStyle.profile(ImpactStyle.FIRE))
		_sparks.append(sparks)
		_embers.append(embers)
		_smoke.append(smoke)
		_age.append(-1.0)
		_size.append(1.0)
		_peak.append(1.0)
		_fire_k.append(1.0)
		slot.visible = false
	_build_body_sfx()
	set_process(false)


## Impacto de un golpe del jugador: la firma de su elemento (`ImpactStyle.of`) a la vista y al oído.
func play_hit(hit: SpellHit, tier: SpellTier, scale_k: float) -> void:
	var style: int = ImpactStyle.of(hit)
	play(hit.position, hit.normal, tier, hit.resonant, hit.recipe != null, scale_k, style)
	if hit.recipe or hit.minor:
		return
	# Del susurro del nivel 1 al golpe que retumba: más fuerte y más grave cuanto mayor el nivel.
	var power: float = clampf((tier.crack_radius * scale_k - 0.9) / 1.6, 0.0, 1.0)
	_body_player.stream = _body_sounds[style]
	_body_player.global_position = hit.position
	_body_player.volume_db = lerpf(-14.0, -4.0, power) + (2.0 if hit.resonant else 0.0)
	_body_player.pitch_scale = lerpf(1.08, 0.9, power)
	_body_player.play()


func _build_body_sfx() -> void:
	_body_player = AudioStreamPlayer3D.new()
	_body_player.name = "Body"
	_body_player.bus = &"SFX"
	_body_player.unit_size = 40.0
	_body_player.max_polyphony = 3
	_body_player.top_level = true
	add_child(_body_player)
	for id: String in BODY_SFX:
		var r := AudioStreamRandomizer.new()
		for v: int in 3:
			r.add_stream(
				-1, load("res://audio/sfx/sfx_hit_%s_%02d.ogg" % [id, v + 1]) as AudioStream
			)
		r.random_pitch = 1.08
		_body_sounds.append(r)


## `style`: firma del elemento (`ImpactStyle`); -1 = la de la forma del hechizo del nivel.
func play(
	pos: Vector3,
	normal: Vector3,
	tier: SpellTier,
	resonant: bool,
	big: bool = false,
	scale_k: float = 1.0,
	style: int = -1
) -> void:
	var i: int = _next
	_next = (_next + 1) % pool_size
	var slot: Node3D = _slots[i]
	var cam: Camera3D = get_viewport().get_camera_3d()
	var toward: Vector3 = (cam.global_position - pos).normalized() if cam else normal
	slot.global_position = pos + normal * 0.3 + toward * 0.6
	slot.visible = true
	if style < 0:
		style = ImpactStyle.of_tier(tier)
	var pf: ImpactStyle.Profile = ImpactStyle.profile(style)
	_prof[i] = pf
	var size: float = (
		tier.crack_radius * 2.6 * (1.6 if resonant else 1.0) * (1.4 if big else 1.0) * scale_k
	)
	_size[i] = size
	# El destello suma luz: sobre el cristal claro, poco o lo lava todo a blanco. El que se tiene
	# que ver es el cuerpo (opaco, con color).
	_peak[i] = (
		(0.45 + (0.45 if resonant else 0.0) - (0.15 if big else 0.0)) * pf.flash * HdFx.flash_scale
	)
	_fire_k[i] = (1.35 if big else 1.0) * pf.fire_k
	var ramp: Gradient = tier.trail_ramp if tier.trail_ramp else _default_ramp
	var glow: Color = Color("#ffd27a") if resonant else tier.color_glow
	_fire[i].set_shader_parameter("ramp", HdFx.smooth_ramp(ramp))
	_fire[i].set_shader_parameter("seed", randf() * 10.0)
	_fire[i].set_shader_parameter("style", style)
	_fire[i].set_shader_parameter("turbulence", pf.turb)
	_fire[i].set_shader_parameter("intensity", 1.0)
	_flash[i].set_shader_parameter("color", glow)
	_flash[i].set_shader_parameter("rays", pf.rays)
	_flash[i].set_shader_parameter("ray_count", pf.ray_count)
	# Tiñe más que suma: sobre el cristal claro, sumar luz lo lavaba todo a blanco.
	_flash[i].set_shader_parameter("cover", 0.8)
	_flash[i].set_shader_parameter("seed", randf() * 10.0)
	_set_star(_star[i], pf, glow, tier.color_core)
	for rm: ShaderMaterial in [_ring[i], _ring2[i]]:
		rm.set_shader_parameter("color", glow)
		rm.set_shader_parameter("seed", randf() * 10.0)
	var cols := PackedColorArray([tier.color_core * 2.2, glow * 1.5])
	var power: float = clampf(size / 3.0, 0.4, 3.0)
	_play_sparks(i, pf, cols, power, size)
	_play_embers(i, pf, cols, power)
	_play_smoke(i, pf, power, size)
	_age[i] = 0.0
	_animate(i)
	set_process(true)


func _play_sparks(
	i: int, pf: ImpactStyle.Profile, cols: PackedColorArray, power: float, size: float
) -> void:
	var p: GPUParticles3D = _sparks[i]
	var pm: ParticleProcessMaterial = p.process_material
	pm.color_ramp = HdFx.color_ramp(cols)
	p.amount_ratio = clampf(power * 0.5, 0.25, 1.0)
	var speed: float = (6.0 + power * 5.0) * pf.spark_speed
	pm.initial_velocity_max = speed
	pm.initial_velocity_min = speed * 0.4
	pm.damping_min = speed * 0.25
	pm.damping_max = speed * 0.7
	pm.gravity = Vector3(0.0, pf.spark_grav, 0.0)
	# Arcano: salen y el remolino se las traga; Viento: giran en torbellino.
	pm.radial_accel_min = pf.spark_pull * power
	pm.radial_accel_max = pf.spark_pull * power
	pm.tangential_accel_min = pf.spark_swirl * power * 0.6
	pm.tangential_accel_max = pf.spark_swirl * power
	pm.emission_sphere_radius = size * 0.15
	p.lifetime = pf.spark_life
	p.restart()


func _play_embers(i: int, pf: ImpactStyle.Profile, cols: PackedColorArray, power: float) -> void:
	var p: GPUParticles3D = _embers[i]
	var amount: float = pf.ember
	if amount <= 0.0:
		p.emitting = false
		return
	var pm: ParticleProcessMaterial = p.process_material
	pm.color_ramp = HdFx.color_ramp(cols)
	pm.gravity = Vector3(0.0, pf.ember_grav, 0.0)
	pm.tangential_accel_min = pf.ember_swirl * 0.5
	pm.tangential_accel_max = pf.ember_swirl
	p.lifetime = pf.ember_life
	p.amount_ratio = clampf(power * 0.4 * amount, 0.2, 1.0)
	p.restart()


func _play_smoke(i: int, pf: ImpactStyle.Profile, power: float, size: float) -> void:
	var p: GPUParticles3D = _smoke[i]
	var amount: float = pf.smoke
	if amount <= 0.0:
		p.emitting = false
		return
	p.amount_ratio = clampf(power * 0.35 * amount, 0.15, 1.0)
	var puff: float = size * 0.7 * pf.smoke_size
	HdFx.set_smoke_size(p, puff)
	# El humo se abre y sube deprisa (a la escala del golpe): quieto, se apilaba en un disco
	# oscuro sobre el impacto. El polvo de la roca y la escarcha del hielo se arrastran y caen.
	var pm: ParticleProcessMaterial = p.process_material
	var rise: float = pf.smoke_rise
	var col: Color = pf.smoke_col
	pm.color_ramp = HdFx.color_ramp(PackedColorArray([Color(col, 0.0), Color(col, 0.32), col]))
	pm.emission_sphere_radius = puff * 0.25
	pm.spread = 75.0 if rise > 0.0 else 100.0
	pm.initial_velocity_min = puff * 0.5
	pm.initial_velocity_max = puff * 1.3
	pm.gravity = Vector3(0.0, puff * 0.35 * rise, 0.0)
	p.restart()


func _process(delta: float) -> void:
	var any: bool = false
	for i: int in pool_size:
		if _age[i] < 0.0:
			continue
		_age[i] += delta
		_animate(i)
		if _age[i] > LIFETIME:
			_age[i] = -1.0
			_slots[i].visible = false
		else:
			any = true
	if not any:
		set_process(false)


func _animate(i: int) -> void:
	var pf: ImpactStyle.Profile = _prof[i]
	var t: float = _age[i]
	var k: float = clampf(t / pf.dur, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, pf.snap)
	var s: float = _size[i]
	_fire_mi[i].visible = k < 1.0
	_fire_mi[i].scale = Vector3.ONE * s * _fire_k[i] * lerpf(0.45, 1.25, e)
	_fire[i].set_shader_parameter("burst", k)
	_fire[i].set_shader_parameter("fade", 1.0 - k * k)
	_fire[i].set_shader_parameter("charge", 1.0)
	var fk: float = clampf(t / pf.flash_t, 0.0, 1.0)
	var flicker: float = 1.0
	if pf.strobe:
		# El rayo no se apaga suave: parpadea dos veces, como un relámpago.
		flicker = 1.0 if t < 0.04 or (t > 0.07 and t < 0.11) or (t > 0.15 and t < 0.18) else 0.12
	_flash_mi[i].visible = fk < 1.0
	_flash_mi[i].scale = Vector3.ONE * s * lerpf(0.7, 1.3, fk)
	_flash[i].set_shader_parameter("intensity", _peak[i] * (1.0 - fk) * (1.0 - fk) * flicker)
	var rs: float = pf.ring_speed
	var ring_t: float = 0.55 / rs
	_set_ring(_ring_mi[i], _ring[i], t / ring_t, s * 2.4 * pf.ring)
	var d2: float = pf.ring2
	if d2 >= 0.0:
		_set_ring(_ring2_mi[i], _ring2[i], (t - d2) / ring_t, s * 3.1 * pf.ring)
	else:
		_ring2_mi[i].visible = false
	var sk: float = t / pf.star_t
	_star_mi[i].visible = sk < 1.0
	if sk < 1.0:
		_star[i].set_shader_parameter("progress", sk)
		_star_mi[i].scale = Vector3.ONE * s * 1.5 * pf.star_size


func _set_star(m: ShaderMaterial, pf: ImpactStyle.Profile, glow: Color, core: Color) -> void:
	m.set_shader_parameter("color", glow * 1.4)
	m.set_shader_parameter("hot", core * 1.8)
	# Contorno del mismo tono muy oscuro: recorta la estrella sobre el cristal claro.
	m.set_shader_parameter("ink", Color(glow.r * 0.12, glow.g * 0.1, glow.b * 0.18))
	m.set_shader_parameter("points", pf.star_pts)
	m.set_shader_parameter("sharp", pf.star_sharp)
	m.set_shader_parameter("twist", pf.star_twist)
	m.set_shader_parameter("jag", pf.star_jag)
	m.set_shader_parameter("seed", randf() * TAU)


func _set_ring(mi: MeshInstance3D, m: ShaderMaterial, k: float, size: float) -> void:
	mi.visible = k >= 0.0 and k < 1.0
	if not mi.visible:
		return
	m.set_shader_parameter("progress", k)
	mi.scale = Vector3.ONE * size


## La onda tiñe en vez de sumar: al nacer es casi un disco del tamaño del golpe y, sumada con
## intensidad 2 (HDR), florecía en un fogonazo blanco que tapaba toda la pantalla.
func _make_ring() -> MeshInstance3D:
	var ring: MeshInstance3D = HdFx.quad(HdFx.RING_SHADER, 1.0, 8)
	var rm: ShaderMaterial = ring.material_override
	rm.set_shader_parameter("intensity", 0.9)
	rm.set_shader_parameter("cover", 0.35)
	ring.visible = false
	return ring
