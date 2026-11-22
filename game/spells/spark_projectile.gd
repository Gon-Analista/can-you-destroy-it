class_name SparkProjectile
extends Node3D
## Un hechizo en vuelo: el mismo `SpellOrb` que se veía en la mano (llama, Bola de Fuego...),
## siempre de cara a la cámara, con una estela de fuego de píxeles sólidos (`SpellTrail`), brasas
## que se quedan flotando y una luz que tiñe el valle a su paso. Todo lo decide el `SpellTier`
## del golpe: a más nivel, más grande, más rápido, menos torpe y de otro color.
## Vuela hacia un punto fijo con un arco y un bamboleo (más torpe cuanto más débil) y estalla al
## llegar. Se reutiliza desde un pool: nada se instancia en caliente salvo el orbe al cambiar de
## aspecto (al subir de nivel). La Bola de Fuego y el Meteoro llevan piezas propias
## (`FireballFlight`, `MeteorRock`) que `prepare_combo()` crea en la pantalla de carga.

signal arrived(projectile: SparkProjectile)

## Distancia a la cámara a la que flotan los hechizos entre las manos.
const HANDS_DEPTH: float = 0.85
## Distancia recorrida a partir de la cual suelta brasas (m).
const EMBERS_FROM: float = 5.0
## Distancia recorrida a partir de la cual la Bola de Fuego suelta su cola de bocanadas (m).
const TAIL_FROM: float = 6.0
## Hacia arriba en pantalla (en el shader del fuego la `y` crece hacia abajo).
const UP_2D := Vector2(0.0, -1.0)

## Carga del orbe en vuelo (la que tenía en la mano al soltarlo).
var orb_charge: float = 1.0
var active: bool = false
var hit: SpellHit
var target_collider: Object

var _orb: SpellOrb
var _light_peak: float = 1.0
var _orb_def: SpellVisualDef
var _orb_scale: float = 1.0
var _trail: SpellTrail
var _embers: GPUParticles3D
var _ember_mat: ParticleProcessMaterial
var _sparks: GPUParticles3D
var _smoke: GPUParticles3D
var _roar: AudioStreamPlayer3D
var _prev_screen := Vector2.ZERO
var _flow := Vector2(0.0, -1.0)
var _light: OmniLight3D
var _from: Vector3
var _to: Vector3
var _duration: float = 1.0
var _t: float = 0.0
var _wobble: float = 0.0
var _wobble_phase: float = 0.0
var _arc: float = 0.6
var _linger: float = 0.0
## Crecimiento al salir de la mano (mejora de Tamaño): de 1 a `hit.size` en el primer tramo.
var _grow: float = 1.0
var _trail_width: float = 1.0
var _light_range: float = 3.0
## Meteoro (`SpellVisualDef.meteor`): roca, humo e impacto propios; cae acelerando.
var _meteor: MeteorRock
var _falls: bool = false
## Bola de Fuego (`SpellVisualDef.fireball_flight`): esfera de fuego en vez del orbe.
var _fireball: FireballFlight
## Terremoto (`SpellVisualDef.boulder`): peñasco que rueda por el suelo en vez del orbe.
var _boulder: BoulderRoll
var _rolls: bool = false
## Escala de lo que se ve en vuelo por lo cargado que salió (`SpellHit.fx_scale`): un combinado
## cargado a tope destroza mucho más y tiene que verse igual de grande.
var _vis: float = 1.0
var _ball_on: bool = false
## Ancho de bola con el que se dimensionaron las brasas (-1: nunca): sólo se rehacen si cambia.
var _embers_for: float = -1.0


func _ready() -> void:
	_trail = SpellTrail.new()
	_trail.name = "Trail"
	_trail.hd = true
	add_child(_trail)
	_build_embers()
	_light = OmniLight3D.new()
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	add_child(_light)
	_deactivate()


func launch(from: Vector3, to: Vector3, p_hit: SpellHit, collider: Object) -> void:
	var tier: SpellTier = p_hit.tier
	hit = p_hit
	target_collider = collider
	_from = from
	_to = to
	_duration = maxf(0.08, from.distance_to(to) / (tier.speed * maxf(p_hit.speed_mult, 0.1)))
	_vis = charged_scale(p_hit.fx_scale)
	var r0: SpellRecipe = p_hit.recipe
	if r0 and r0.delivery == SpellRecipe.Delivery.SKY and r0.fall_sec < 0.3:
		# El Trueno: su fuerza la lleva el rayo (CrystalCombos.sky_bolt); una bola blanca enorme
		# cayendo sólo tapaba la columna.
		_vis = 1.0
	_t = 0.0
	_wobble = tier.wobble
	_wobble_phase = randf() * TAU
	_arc = 0.6 * (1.0 - tier.wobble * 0.5)
	_linger = -1.0
	global_position = from
	_set_orb(tier.visual)
	_orb_scale = tier.orb_scale * (1.35 if p_hit.resonant else 1.0) * _vis
	_falls = tier.visual != null and tier.visual.meteor
	_rolls = tier.visual != null and tier.visual.boulder
	if _falls:
		# Cae del cielo acelerando, sin arco ni bamboleo, en lo que diga la receta.
		var r: SpellRecipe = p_hit.recipe
		_duration = maxf(_duration, r.fall_sec if r else 1.0)
		_arc = 0.0
		_wobble = 0.0
		prepare_combo()
		_meteor.launch(from, to, p_hit.size * _vis * tier.visual.meteor_scale, p_hit.warmup)
	elif _meteor:
		_meteor.stop()
	if _rolls:
		# Rueda por el suelo: sin arco ni bamboleo (los botes los pone el peñasco).
		_arc = 0.0
		_wobble = 0.0
		_prepare_boulder()
		_boulder.launch(from, to, p_hit.size * _vis, tier.visual.boulder_heat, p_hit.warmup)
		if _orb:
			_orb.visible = false
	elif _boulder:
		_boulder.stop()
	if _ball_on:
		_fireball.launch(_ball_size(), clampf(float(p_hit.level - 1) / 9.0, 0.0, 1.0))
	elif _orb and not _rolls:
		_orb.visible = true
		_orb.appear()
		_orb.charge = orb_charge
		_orb.set_flow(UP_2D, 1.0)
		# El fuego del meteoro envuelve la roca (centrado); el resto deja sitio a sus lenguas.
		_orb.set_center_shift(0.0 if _falls else 1.0)
		_face_camera()
	_grow = 1.0
	_trail_width = tier.trail_width * (1.35 if p_hit.resonant else 1.0) * _vis
	_trail.width = _trail_width
	_trail.length_sec = tier.trail_length
	_trail.near_depth = HANDS_DEPTH
	_trail.max_scale = _orb_scale
	if tier.trail_ramp:
		_trail.set_ramp(tier.trail_ramp)
	_trail.start(from)
	_light.light_color = tier.color_glow
	_light_peak = tier.light_energy * 0.6
	_light.light_energy = 0.0
	_light_range = 3.0 + tier.orb_scale * 0.4
	_light.omni_range = _light_range
	_light.visible = true
	# Las de la Bola de Fuego, doradas y sin pasarse de brillo: florecían hasta lavar la bola.
	var hot: float = 1.1 if _ball_on else 2.0
	var ember_cols := PackedColorArray([tier.color_core * hot, tier.color_glow * 1.1])
	_ember_mat.color_ramp = HdFx.color_ramp(ember_cols)
	(_sparks.process_material as ParticleProcessMaterial).color_ramp = HdFx.color_ramp(ember_cols)
	# Con el nivel, más brasas y chispas (la Bola de Fuego de nivel 10 va soltando una lluvia).
	var lv: float = lerpf(0.55, 1.0, float(p_hit.level - 1) / 9.0) if _ball_on else 1.0
	_embers.amount_ratio = clampf(tier.orb_scale / 10.0, 0.3, 1.0) * lv
	_sparks.amount_ratio = clampf(tier.orb_scale / 10.0, 0.3, 1.0) * lv
	_size_embers(_ball_size() * _orb_scale * FireballFlight.BODY_SCALE if _ball_on else 0.0)
	_smoke.amount_ratio = clampf(tier.trail_smoke, 0.01, 1.0)
	_prev_screen = Vector2.ZERO
	# La Bola de Fuego sale de las manos hacia la mira (hacia arriba): sus lenguas, hacia abajo.
	_flow = Vector2.DOWN if _ball_on else UP_2D
	if _ball_on:
		_fireball.set_flow(_flow, 1.1)
	if tier.flight_sfx:
		_roar.stream = tier.flight_sfx
		_roar.pitch_scale = 0.8
		_roar.volume_db = -4.0
		_roar.play()
	active = true
	visible = true
	set_process(true)


## Crea la Bola de Fuego y (con `meteor`) la roca del Meteoro si faltan; se llama al cargar,
## nunca al lanzar. Los ecos no necesitan la roca: ningún eco es un Meteoro.
func prepare_combo(meteor: bool = true) -> void:
	if meteor and _meteor == null:
		_meteor = MeteorRock.new()
		_meteor.name = "Meteor"
		add_child(_meteor)
	if _fireball == null:
		_fireball = FireballFlight.new()
		_fireball.name = "Fireball"
		add_child(_fireball)


func _process(delta: float) -> void:
	if _orb or _ball_on:
		_face_camera()
	if _linger >= 0.0:
		# Ya llegó: dejamos morir la estela, las brasas y el estallido antes de volver al pool.
		_linger -= delta
		if _linger < 0.0:
			_deactivate()
		return
	_t += delta / _duration
	var k: float = clampf(_t, 0.0, 1.0)
	# En la mano siempre del mismo tamaño; al salir crece hasta el de su mejora.
	_grow = lerpf(1.0, hit.size, smoothstep(0.0, 0.35, k))
	_trail.width = _trail_width * _grow
	_trail.max_scale = _orb_scale * _grow
	_light.omni_range = _light_range * _grow
	# El meteoro empieza despacio y acelera (la gravedad): llega con todo el peso.
	var kp: float = k * lerpf(0.3, 1.0, k) if _falls else k
	var pos: Vector3 = _from.lerp(_to, kp)
	# Arco suave hacia arriba y bamboleo que se apaga al llegar.
	pos.y += sin(k * PI) * _arc
	var fade_w: float = sin(k * PI)
	pos += (
		Vector3(sin(_t * 23.0 + _wobble_phase), cos(_t * 19.0 + _wobble_phase), 0.0)
		* _wobble
		* 0.35
		* fade_w
	)
	global_position = pos
	# Las brasas sólo cuando ya va lejos: pegadas a la cámara se verían como manchas enormes.
	_embers.emitting = k < 1.0 and _from.distance_to(pos) > EMBERS_FROM
	# La luz se enciende al alejarse: pegada al mago teñía el suelo a sus pies.
	_light.light_energy = _light_peak * smoothstep(2.0, 7.0, _from.distance_to(pos))
	_sparks.emitting = _embers.emitting
	_smoke.emitting = _embers.emitting and hit.tier.trail_smoke > 0.0
	if _ball_on:
		# La cola de bocanadas desde algo más cerca que las brasas; luz en el cristal al llegar.
		_fireball.set_tail(k < 1.0 and _from.distance_to(pos) > TAIL_FROM, _from)
		if not hit.warmup:
			_fireball.glow_crystal(_to)
	_update_flow(delta)
	if k >= 1.0:
		_light.visible = false
		_trail.stop()
		_embers.emitting = false
		_sparks.emitting = false
		_smoke.emitting = false
		_roar.stop()
		_linger = maxf(_smoke.lifetime, _trail.length_sec)
		if _ball_on:
			_fireball.release()
			_linger = maxf(_linger, FireballFlight.TAIL_SEC)
		elif _orb and not _rolls:
			_orb.release()
			_linger = maxf(_linger, _orb_def.release_time + _orb_def.sparkle_lifetime)
		if _falls:
			_meteor.impact(_to, hit.normal, hit.warmup)
			_linger = maxf(_linger, MeteorRock.IMPACT_SEC)
		if _rolls:
			_boulder.impact(_to, hit.normal)
			_linger = maxf(_linger, BoulderRoll.IMPACT_SEC)
		arrived.emit(self)


## Escala de un hechizo en vuelo para el `fx_scale` de su golpe (1 sin cargar; un combinado de
## nivel 11 cargado a tope, ~1,9).
static func charged_scale(fx_scale: float) -> float:
	return lerpf(1.0, maxf(fx_scale, 1.0), 0.85)


func _prepare_boulder() -> void:
	if _boulder == null:
		_boulder = BoulderRoll.new()
		_boulder.name = "Boulder"
		add_child(_boulder)


## Cambia el aspecto del orbe sólo si es otro (al subir de nivel); si no, se reutiliza.
func _set_orb(def: SpellVisualDef) -> void:
	_ball_on = def != null and def.fireball_flight
	if _ball_on:
		prepare_combo(false)
		_fireball.setup(def)
		if _orb:
			_orb.visible = false
		return
	if _fireball:
		_fireball.stop()
	if def == _orb_def:
		return
	if _orb:
		_orb.queue_free()
		_orb = null
	_orb_def = def
	if def == null:
		return
	_orb = SpellOrb.new()
	_orb.name = "Orb"
	_orb.def = def
	_orb.release_flash_mul = 0.2
	_orb.rock_enabled = false
	add_child(_orb)


## Las llamas se arrastran hacia atrás de la trayectoria en pantalla (y algo hacia arriba).
## Si en pantalla apenas se mueve (se aleja de la cámara, como casi siempre), el fuego sube: una
## bola con lenguas hacia arriba, no una gota que gotea hacia el mago.
func _update_flow(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or (_orb == null and not _ball_on) or cam.is_position_behind(global_position):
		return
	var sp: Vector2 = cam.unproject_position(global_position)
	if _prev_screen != Vector2.ZERO and delta > 0.0:
		var v: Vector2 = sp - _prev_screen
		# Velocidad en pantallas (de alto) por segundo.
		var speed: float = v.length() / delta / maxf(get_viewport().get_visible_rect().size.y, 1.0)
		var w: float = smoothstep(0.12, 0.9, speed)
		if _ball_on:
			_update_ball_flow(cam.unproject_position(_from) - sp, w, delta)
		else:
			var back: Vector2 = (
				(-v.normalized() + Vector2(0.0, -0.35)).normalized() if w > 0.0 else UP_2D
			)
			var target: Vector2 = (back * w + UP_2D * (1.0 - w)).normalized()
			_flow = _flow.lerp(target, minf(delta * 10.0, 1.0)).normalized()
			_orb.set_flow(_flow, lerpf(0.7, 2.6, w))
	_prev_screen = sp


## Las lenguas de la Bola de Fuego apuntan en pantalla hacia de donde salió (`to_origin`, hacia
## la mano), como la cola de cometa: aunque se aleje casi de frente o el arco la haga bajar al
## final, nunca suben como una vela. Algo de subida del calor; más largas cuanto más deprisa
## cruza la pantalla.
func _update_ball_flow(to_origin: Vector2, w: float, delta: float) -> void:
	if to_origin.length_squared() > 4.0:
		var back: Vector2 = (to_origin.normalized() + Vector2(0.0, -0.15)).normalized()
		_flow = _flow.lerp(back, minf(delta * 8.0, 1.0)).normalized()
	_fireball.set_flow(_flow, lerpf(1.3, 2.8, w))


## El orbe se diseñó para verse de frente (sus órbitas giran en el plano de la cámara).
## Mantiene el tamaño en pantalla que tenía en la mano (a 0,85 m) hasta alcanzar su escala de
## vuelo; a partir de ahí se aleja con perspectiva. Así sale de la mano sin saltos.
func _face_camera() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:
		var dist: float = cam.global_position.distance_to(global_position)
		var s: float = clampf(dist / HANDS_DEPTH, 1.0, _orb_scale) * _grow
		if _ball_on:
			_fireball.set_view_scale(s, _orb_scale * _grow)
		else:
			_orb.global_basis = cam.global_basis.scaled(Vector3.ONE * s)


## Diámetro del cuerpo de la Bola de Fuego en la mano (m): el del orbe que había entre las
## manos con esa carga, para salir de ellas sin saltos.
func _ball_size() -> float:
	var d: SpellVisualDef = hit.tier.visual
	return d.core_radius * 2.0 * d.body_scale * lerpf(d.charge_min_scale, 1.0, orb_charge)


## Brasas y chispas a la escala del hechizo (`ball`: ancho de la Bola de Fuego en vuelo, m; 0 el
## resto): las de la bola, que vuela lejos y es enorme, tienen que verse y salir disparadas.
func _size_embers(ball: float) -> void:
	if absf(ball - _embers_for) < 0.001:
		return
	_embers_for = ball
	var big: bool = ball > 0.0
	(_embers.draw_pass_1 as QuadMesh).size = Vector2.ONE * (ball * 0.07 if big else 0.09)
	var ribbon: RibbonTrailMesh = _sparks.draw_pass_1
	ribbon.size = ball * 0.02 if big else 0.02
	ribbon.section_length = ball * 0.04 if big else 0.1
	_ember_mat.emission_sphere_radius = ball * 0.25 if big else 0.15
	_ember_mat.initial_velocity_max = 6.0 if big else 2.0
	var spm: ParticleProcessMaterial = _sparks.process_material
	spm.emission_sphere_radius = ball * 0.25 if big else 0.1
	spm.initial_velocity_max = 9.0 if big else 2.5


## Brasas suaves y chispas con estela que va soltando en vuelo (capa de magia HD).
func _build_embers() -> void:
	_embers = HdFx.embers(48, 0.09, PackedColorArray([Color(2, 1.7, 1.1), Color(1, 0.6, 0.2)]))
	_embers.name = "Embers"
	_embers.emitting = false
	_ember_mat = _embers.process_material
	_ember_mat.emission_sphere_radius = 0.15
	_ember_mat.initial_velocity_min = 0.5
	_ember_mat.initial_velocity_max = 2.0
	add_child(_embers)
	_sparks = HdFx.sparks(40, 2.5, 0.02, PackedColorArray([Color(2, 1.8, 1.2), Color(1, 0.5, 0.2)]))
	_sparks.name = "Sparks"
	_sparks.one_shot = false
	_sparks.explosiveness = 0.0
	_sparks.lifetime = 0.35
	_sparks.trail_lifetime = 0.07
	(_sparks.process_material as ParticleProcessMaterial).gravity = Vector3(0, -3.0, 0)
	add_child(_sparks)
	# Humo que deja la Bola de Fuego: le da cuerpo y peso a la trayectoria.
	_smoke = HdFx.smoke(40, 1.4, Color(0.28, 0.23, 0.23))
	_smoke.name = "Smoke"
	_smoke.one_shot = false
	_smoke.explosiveness = 0.0
	_smoke.lifetime = 1.1
	var spm: ParticleProcessMaterial = _smoke.process_material
	spm.initial_velocity_min = 0.2
	spm.initial_velocity_max = 0.8
	add_child(_smoke)
	_roar = AudioStreamPlayer3D.new()
	_roar.name = "Roar"
	_roar.bus = &"SFX"
	_roar.unit_size = 10.0
	_roar.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(_roar)


func _deactivate() -> void:
	active = false
	visible = false
	_embers.emitting = false
	_sparks.emitting = false
	_smoke.emitting = false
	_roar.stop()
	_trail.stop()
	if _meteor:
		_meteor.stop()
	if _boulder:
		_boulder.stop()
	if _fireball:
		_fireball.stop()
	_linger = -1.0
	set_process(false)
