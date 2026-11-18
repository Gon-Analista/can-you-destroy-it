class_name ElementalStorm
extends Node3D
## Tormenta Elemental (GDD 5.2: Chispa + Escarcha + Rayo, "tormenta permanente sobre el
## cristal"). Al soltarla, el orbe sube de las manos al cielo sobre el blanco y allí se abre una
## nube que gira, con un círculo mágico debajo, lluvia y relámpagos por dentro. Durante
## `storm_sec` descarga por turnos los elementos de su receta:
##   Rayo     -> un rayo del cielo al cristal (salta como el Trueno) y destello en la nube
##   Escarcha -> una ráfaga de granizo que congela la zona (x2 para lo demás)
##   Chispa   -> una bola de fuego que cae y deja el cristal ardiendo
## El daño de la triple se reparte entre todas las descargas. Mientras ruge, el mago sigue
## lanzando con las manos; sólo puede haber una (`buff_lockout_sec`).
## Todo se crea una vez (bocanadas, luz, lluvia, sonido) y se reutiliza.

const CLOUD_SHADER: Shader = preload("res://fx/hd/hd_storm_cloud.gdshader")
const LOOP_SFX: AudioStream = preload("res://audio/sfx/amb_storm_cloud_loop.ogg")
const HAIL_SFX: AudioStream = preload("res://audio/sfx/sfx_hail_01.ogg")
const FIRE_SFX: AudioStream = preload("res://audio/sfx/sfx_meteor_whistle_01.ogg")
const BOLT: ElementDef = preload("res://data/elements/bolt.tres")
const FROST: ElementDef = preload("res://data/elements/frost.tres")
const SPARK: ElementDef = preload("res://data/elements/spark.tres")
const PUFFS: int = 22
## Segundos que tarda en formarse la nube y en deshacerse.
const FORM_SEC: float = 0.9
const FADE_SEC: float = 1.4
## Bolas de granizo de cada ráfaga.
const HAIL_PER_VOLLEY: int = 3
const MASK_CRYSTAL: int = 1 << 1

var _delivery: SpellDelivery
var _circles: MagicCircles
var _puffs: Array[MeshInstance3D] = []
var _puff_base: PackedVector4Array = PackedVector4Array()
var _puff_flash: PackedFloat32Array = PackedFloat32Array()
var _light: OmniLight3D
var _rain: GPUParticles3D
var _sound: AudioStreamPlayer3D
var _accent: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _recipe: SpellRecipe
var _hit: SpellHit
var _target: Vector3
var _normal: Vector3
var _tangent: Vector3
var _bitangent: Vector3
## Segundos desde que se lanzó (incluye la subida del orbe y la formación).
var _t: float = -1.0
var _strike_t: float = 0.0
var _strike_k: int = 0
var _strikes_total: int = 1
var _each: int = 1
var _lock_until: float = 0.0
var _clock: float = 0.0
var _radius: float = 7.0
var _ember: float = 0.0
var _warming: float = 0.0


func setup(delivery: SpellDelivery, circles: MagicCircles) -> void:
	_delivery = delivery
	_circles = circles
	top_level = true
	_rng.randomize()
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADER
	mat.render_priority = 1
	for i: int in PUFFS:
		var mi := MeshInstance3D.new()
		mi.name = "Puff%d" % i
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		mi.mesh = q
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = MagicLayer.MAGIC_LAYER
		mi.extra_cull_margin = 16.0
		mi.set_instance_shader_parameter(&"seed", float(i) * 3.7)
		add_child(mi)
		_puffs.append(mi)
	_puff_base.resize(PUFFS)
	_puff_flash.resize(PUFFS)
	_light = OmniLight3D.new()
	_light.name = "StormLight"
	_light.light_color = Color(0.75, 0.75, 1.0)
	_light.omni_range = 45.0
	_light.omni_attenuation = 1.2
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	add_child(_light)
	_rain = _make_rain()
	add_child(_rain)
	_sound = AudioStreamPlayer3D.new()
	_sound.name = "StormLoop"
	_sound.bus = &"SFX"
	_sound.stream = LOOP_SFX
	_sound.unit_size = 30.0
	_sound.max_db = 3.0
	add_child(_sound)
	_accent = AudioStreamPlayer3D.new()
	_accent.name = "StormAccent"
	_accent.bus = &"SFX"
	_accent.unit_size = 30.0
	add_child(_accent)
	visible = false
	set_process(false)


## Segundos hasta que se pueda lanzar otra tormenta (0 = ya se puede).
func lock_left() -> float:
	return maxf(0.0, _lock_until - _clock)


## Si la nube está descargando ahora mismo.
func is_raging() -> bool:
	return _t >= 0.0 and _recipe != null and _t < _form_end() + _recipe.storm_sec


## Descargas que ya han caído en la tormenta en curso (o en la última).
func strikes_done() -> int:
	return _strike_k


## Abre la tormenta: `hit` lleva el daño total de la triple; `cloud` es el punto del cielo
## sobre el blanco (`target`, con su `normal`) y `from`, de dónde sale el orbe (las manos).
func start(
	recipe: SpellRecipe, hit: SpellHit, cloud: Vector3, target: Vector3, normal: Vector3,
	from: Vector3
) -> void:
	_recipe = recipe
	_hit = hit
	_target = target
	_normal = normal if normal.length_squared() > 0.01 else Vector3.BACK
	_tangent = _normal.cross(Vector3.UP if absf(_normal.y) < 0.95 else Vector3.RIGHT).normalized()
	_bitangent = _tangent.cross(_normal).normalized()
	_radius = recipe.storm_radius * hit.size
	global_position = cloud
	_t = 0.0
	_strike_t = 0.0
	_strike_k = 0
	_strikes_total = maxi(1, floori(recipe.storm_sec / maxf(recipe.storm_interval, 0.05)))
	_each = maxi(1, roundi(float(hit.damage) / float(_strikes_total)))
	_lock_until = _clock + recipe.buff_lockout_sec
	_ember = 0.0
	for i: int in PUFFS:
		var a: float = TAU * float(i) / float(PUFFS) + _rng.randf_range(-0.2, 0.2)
		var ring: float = sqrt(_rng.randf()) * _radius * 1.25
		_puff_base[i] = Vector4(a, ring, _rng.randf_range(-1.6, 1.6), _rng.randf_range(7.0, 11.0))
		_puff_flash[i] = 0.0
	visible = true
	# El orbe sube de las manos a la nube (sólo se ve: el daño lo hacen las descargas).
	var p: SparkProjectile = SpellDelivery.free_projectile(_delivery.combo_projectiles)
	if p:
		var orb := SpellHit.new()
		orb.tier = recipe.tier
		orb.recipe = recipe
		orb.warmup = true
		orb.position = cloud
		orb.normal = Vector3.DOWN
		p.orb_charge = 0.8
		p.launch(from, cloud, orb, null)
	# Círculo mágico enorme bajo la nube, mirando abajo, que gira mientras dure.
	_circles.stamp(
		cloud - Vector3.UP * 2.5,
		Vector3.DOWN,
		_radius * 2.2,
		recipe.circle_color,
		recipe.circle_hot,
		recipe.storm_sec + FORM_SEC,
		0.7,
		0.5
	)
	_sound.volume_db = -30.0
	_sound.play()
	_rain.global_position = cloud - Vector3.UP * 1.5
	(_rain.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(
		_radius, 0.5, _radius
	)
	_rain.emitting = false
	set_process(true)


## Pantalla de carga: la nube un momento delante del blanco (compila su shader).
func warm_up(at: Vector3) -> void:
	global_position = at + Vector3.UP * 6.0
	for i: int in PUFFS:
		_puff_base[i] = Vector4(TAU * float(i) / float(PUFFS), 3.0, 0.0, 6.0)
	visible = true
	_warming = 0.3
	_t = -1.0
	set_process(true)


func _form_end() -> float:
	return FORM_SEC


func _process(delta: float) -> void:
	_clock += delta
	if _warming > 0.0:
		_warming -= delta
		_animate_puffs(delta, 1.0)
		if _warming <= 0.0:
			visible = false
			if _t < 0.0:
				set_process(false)
		return
	if _t < 0.0 or _recipe == null:
		set_process(false)
		return
	_t += delta
	var life: float = _recipe.storm_sec
	var grow: float = smoothstep(0.0, FORM_SEC, _t)
	var fade: float = 1.0 - smoothstep(FORM_SEC + life, FORM_SEC + life + FADE_SEC, _t)
	_animate_puffs(delta, grow * fade)
	_sound.volume_db = lerpf(-30.0, 0.0, minf(grow, fade))
	_rain.emitting = grow > 0.6 and fade > 0.3
	_light.light_energy = maxf(0.0, _light.light_energy - delta * 14.0)
	_ember = maxf(0.0, _ember - delta * 1.8)
	if _t >= FORM_SEC and _t < FORM_SEC + life:
		_strike_t -= delta
		while _strike_t <= 0.0 and _strike_k < _strikes_total:
			_strike_t += _recipe.storm_interval
			_strike(_strike_k)
			_strike_k += 1
	if _t >= FORM_SEC + life + FADE_SEC:
		_t = -1.0
		visible = false
		_sound.stop()
		_rain.emitting = false
		set_process(false)


## Las bocanadas giran despacio alrededor del centro y se revuelven; el relámpago las ilumina.
func _animate_puffs(delta: float, k: float) -> void:
	var spin: float = _clock * 0.18
	for i: int in PUFFS:
		var b: Vector4 = _puff_base[i]
		var a: float = b.x + spin * (1.0 if i % 2 == 0 else 0.8)
		var off := Vector3(cos(a) * b.y, b.z + sin(_clock * 0.7 + float(i)) * 0.4, sin(a) * b.y)
		var puff: MeshInstance3D = _puffs[i]
		puff.position = off * lerpf(0.4, 1.0, k)
		var s: float = b.w * lerpf(0.2, 1.0, k)
		puff.scale = Vector3(s, s, s)
		_puff_flash[i] = maxf(0.0, _puff_flash[i] - delta * 6.0)
		puff.set_instance_shader_parameter(&"flash", _puff_flash[i])
		puff.set_instance_shader_parameter(&"ember", _ember)
		puff.set_instance_shader_parameter(&"fade", clampf(k * 1.4, 0.0, 1.0))


## Una descarga: el elemento que toca por turno (en el orden de la receta).
func _strike(k: int) -> void:
	var crystal: MotherCrystal = _delivery.crystal()
	if crystal == null:
		return
	var els: Array[StringName] = _recipe.elements
	var el: StringName = els[k % els.size()]
	var from: Vector3 = _cloud_point()
	match el:
		&"bolt":
			var aim: Dictionary = _surface_point(from)
			var sub: SpellHit = _sub_hit(BOLT, _each, aim, from, false)
			crystal.sky_bolt(from, sub.position, _recipe.circle_hot)
			crystal.receive_hit(sub)
			_flash_cloud(from, 1.0)
			_delivery_trauma(0.12)
		&"frost":
			var each: int = maxi(1, roundi(float(_each) / float(HAIL_PER_VOLLEY)))
			for h: int in HAIL_PER_VOLLEY:
				var hf: Vector3 = _cloud_point()
				var aim: Dictionary = _surface_point(hf)
				_fall(_sub_hit(FROST, each, aim, hf, h > 0), hf, aim)
			_play(HAIL_SFX, -4.0, _rng.randf_range(0.9, 1.15))
			_flash_cloud(from, 0.35)
		_:
			var aim: Dictionary = _surface_point(from)
			var sub: SpellHit = _sub_hit(SPARK, _each, aim, from, false)
			_fall(sub, from, aim)
			_ember = 1.0
			_play(FIRE_SFX, -10.0, _rng.randf_range(1.2, 1.5))


func _sub_hit(
	el: ElementDef, damage: int, aim: Dictionary, from: Vector3, minor: bool
) -> SpellHit:
	var sub := SpellHit.new()
	var lvl: int = clampi(roundi(GameState.stat(el.power_stat, 0.0)), 0, el.tiers.size() - 1)
	if el == SPARK:
		lvl = clampi(roundi(GameState.stat(&"spark_tier", 0.0)), 0, el.tiers.size() - 1)
	sub.tier = el.tiers[lvl]
	sub.recipe = _recipe
	sub.element = el.id
	sub.element_def = el
	sub.damage = damage
	sub.minor = minor
	sub.size = _hit.size
	sub.resonant = _hit.resonant and _strike_k == 0
	sub.position = aim["position"]
	sub.normal = aim["normal"]
	sub.direction = (sub.position - from).normalized()
	return sub


## Lo que cae de la nube (granizo, bolas de fuego) como proyectil hasta el cristal.
func _fall(sub: SpellHit, from: Vector3, aim: Dictionary) -> void:
	var p: SparkProjectile = SpellDelivery.free_projectile(_delivery.projectiles)
	if p:
		p.launch(from, sub.position, sub, aim["collider"])


## Un punto de la panza de la nube.
func _cloud_point() -> Vector3:
	var a: float = _rng.randf() * TAU
	var r: float = sqrt(_rng.randf()) * _radius
	return global_position + Vector3(cos(a) * r, -2.0, sin(a) * r)


## Un punto del cristal cerca del blanco (dentro del radio de la tormenta), visto desde `from`.
func _surface_point(from: Vector3) -> Dictionary:
	var a: float = _rng.randf() * TAU
	var r: float = sqrt(_rng.randf()) * _radius
	var want: Vector3 = _target + (_tangent * cos(a) + _bitangent * sin(a)) * r
	var dir: Vector3 = (want - from).normalized()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, want + dir * 25.0, MASK_CRYSTAL)
	var res: Dictionary = space.intersect_ray(q)
	if res.is_empty():
		q = PhysicsRayQueryParameters3D.create(from, _target + dir * 10.0, MASK_CRYSTAL)
		res = space.intersect_ray(q)
	if res.is_empty():
		return {"position": _target, "normal": _normal, "collider": null}
	return res


## El relámpago ilumina las bocanadas cercanas y el valle (luz del mundo).
func _flash_cloud(at: Vector3, amount: float) -> void:
	for i: int in PUFFS:
		var d: float = _puffs[i].global_position.distance_to(at)
		_puff_flash[i] = maxf(_puff_flash[i], amount * clampf(1.4 - d / (_radius * 1.2), 0.2, 1.0))
	_light.global_position = at
	_light.light_energy = maxf(_light.light_energy, 6.0 * amount)


func _play(stream: AudioStream, db: float, pitch: float) -> void:
	_accent.stream = stream
	_accent.volume_db = db
	_accent.pitch_scale = pitch
	_accent.global_position = global_position
	_accent.play()


func _delivery_trauma(amount: float) -> void:
	if _delivery.camera is CameraRig:
		(_delivery.camera as CameraRig).add_trauma(amount)


## Lluvia fina bajo la nube (rayas que caen), en la capa de magia.
func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Rain"
	p.amount = 260
	p.lifetime = 0.9
	p.local_coords = false
	p.emitting = false
	p.layers = MagicLayer.MAGIC_LAYER
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -50, -30), Vector3(60, 60, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(8.0, 0.5, 8.0)
	pm.direction = Vector3.DOWN
	pm.spread = 4.0
	pm.initial_velocity_min = 26.0
	pm.initial_velocity_max = 34.0
	pm.gravity = Vector3(0, -12, 0)
	pm.particle_flag_align_y = true
	pm.color = Color(0.75, 0.8, 1.2, 1.0)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 1.3)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.7, 0.75, 1.0, 0.35)
	m.disable_fog = true
	m.render_priority = 2
	q.material = m
	p.draw_pass_1 = q
	return p
