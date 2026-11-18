class_name SpellDelivery
extends Node
## Cómo llega cada hechizo al cristal (ver SpellRecipe.Delivery), separado de SpellCaster: los
## pools de proyectiles, el proyectil desde las manos, lo que cae del cielo (Meteoro, Trueno,
## Glaciar), la lluvia, el haz de Plasma, la onda del Terremoto, el pozo de Gravedad y las triples
## del báculo (la Tormenta Elemental y la Supernova). El lanzador decide qué y cuánto; esto, por
## dónde y cómo.

const FIZZLE_SFX: AudioStream = preload("res://audio/sfx/sfx_spark_fizzle_01.ogg")
const PLASMA_SFX: AudioStream = preload("res://audio/sfx/amb_plasma_loop.ogg")
const PROJECTILE_POOL: int = 24
const COMBO_PROJECTILE_POOL: int = 6
## Cada cuánto golpea el Haz de Plasma (s).
const BEAM_TICK: float = 0.09
## Lado que usan las señales y las manos para el hechizo combinado.
const BOTH_HANDS: int = 2

var camera: Camera3D
## Proyectiles de los disparos sueltos (y de la lluvia y el granizo) y de los combinados.
var projectiles: Array[SparkProjectile] = []
var combo_projectiles: Array[SparkProjectile] = []
## Lado por el que entra el próximo hechizo del cielo (se alterna en cada lanzamiento).
var sky_side: float = 1.0
var _circles: MagicCircles
var _aim: Callable
var _hand_origin: Callable
var _gravity: GravityWell
var _storm: ElementalStorm
var _nova: Supernova
var _beam_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
## Haz de Plasma en curso: segundos que le quedan, golpe de plantilla y reloj de golpes.
var _beam_left: float = 0.0
var _beam_hit: SpellHit
var _beam_tick: float = 0.0


## `aim` y `hand_origin` son del lanzador: apuntar por el centro de la pantalla y el punto de la
## pantalla de cada mano (o de las dos juntas).
func setup(cam: Camera3D, circles: MagicCircles, aim: Callable, hand_origin: Callable) -> void:
	camera = cam
	_circles = circles
	_aim = aim
	_hand_origin = hand_origin
	_rng.randomize()
	for i: int in PROJECTILE_POOL:
		projectiles.append(make_projectile("Spark%d" % i))
	for i: int in COMBO_PROJECTILE_POOL:
		combo_projectiles.append(make_projectile("Combo%d" % i))
	_gravity = GravityWell.new()
	_gravity.name = "GravityWell"
	add_child(_gravity)
	_storm = ElementalStorm.new()
	_storm.name = "ElementalStorm"
	add_child(_storm)
	_storm.setup(self, _circles)
	_nova = Supernova.new()
	_nova.name = "Supernova"
	add_child(_nova)
	_beam_player = AudioStreamPlayer.new()
	_beam_player.name = "BeamLoop"
	_beam_player.bus = &"SFX"
	_beam_player.stream = PLASMA_SFX
	add_child(_beam_player)
	set_process(false)


func make_projectile(node_name: String) -> SparkProjectile:
	var p := SparkProjectile.new()
	p.name = node_name
	p.top_level = true
	p.arrived.connect(_on_projectile_arrived)
	add_child(p)
	return p


static func free_projectile(pool: Array[SparkProjectile]) -> SparkProjectile:
	for p: SparkProjectile in pool:
		if not p.active:
			return p
	return null


## La Tormenta Elemental activa (o null), para la mira y los tests.
func storm() -> ElementalStorm:
	return _storm


func crystal() -> MotherCrystal:
	return get_tree().get_first_node_in_group(&"mother_crystal") as MotherCrystal


## Apunta por el centro de la pantalla y lanza el proyectil desde la mano `side`.
func launch(projectile: SparkProjectile, hit: SpellHit, side: int) -> void:
	var result: Dictionary = _aim.call()
	var target: Vector3 = result["position"]
	hit.normal = result["normal"]
	hit.position = target
	var origin: Vector3 = _hand_origin.call(side)
	hit.direction = (target - origin).normalized()
	projectile.launch(origin, target, hit, result["collider"])


## Cada combinación llega al cristal a su manera (ver SpellRecipe.Delivery).
func deliver(recipe: SpellRecipe, hit: SpellHit, charge: float) -> void:
	match recipe.delivery:
		SpellRecipe.Delivery.SKY:
			deliver_sky(recipe, hit, charge)
		SpellRecipe.Delivery.RAIN:
			_deliver_rain(recipe, hit)
		SpellRecipe.Delivery.BEAM:
			_beam_hit = hit
			_beam_left = recipe.beam_sec
			_beam_tick = 0.0
			_beam_player.pitch_scale = 1.0
			_beam_player.volume_db = -4.0
			_beam_player.play()
			set_process(true)
		SpellRecipe.Delivery.MAGNET:
			var player: Node = get_tree().get_first_node_in_group(&"player")
			var n: int = int(player.call(&"magnet_pull", 45.0)) if player else 0
			var c: MotherCrystal = crystal()
			if c:
				c.magnet_pulse(camera.global_position - Vector3(0, 1.4, 0), n)
		SpellRecipe.Delivery.GROUND:
			_deliver_ground(hit, charge)
		SpellRecipe.Delivery.GRAVITY:
			# El pozo se abre delante del mago, algo por encima de la mirada.
			var flat: Vector3 = -camera.global_basis.z
			flat.y = 0.0
			flat = flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD
			var center: Vector3 = camera.global_position + flat * 6.0 + Vector3.UP * 0.6
			_gravity.open(center, (camera.global_position - center).normalized(), recipe, _circles)
			_trauma(0.3)
		SpellRecipe.Delivery.STORM:
			var aim: Dictionary = _aim.call()
			var target: Vector3 = aim["position"]
			var cloud: Vector3 = sky_origin(recipe, target, aim["normal"])
			_storm.start(recipe, hit, cloud, target, aim["normal"], _hand_origin.call(BOTH_HANDS))
			_trauma(0.45)
		_:
			var projectile: SparkProjectile = free_projectile(combo_projectiles)
			if projectile:
				# Misma carga que el orbe entre las manos (ver WizardHands): sale sin cambiar
				# de tamaño.
				projectile.orb_charge = lerpf(0.15, 1.0, charge)
				launch(projectile, hit, BOTH_HANDS)


## Meteoro, Trueno, Glaciar: cae desde lo alto sobre el punto que miras (en diagonal, para que
## se vea). `aim` (opcional): otro blanco, como el de un eco.
func deliver_sky(
	recipe: SpellRecipe, hit: SpellHit, charge: float, aim: Dictionary = {}
) -> Vector3:
	if aim.is_empty():
		aim = _aim.call()
	var target: Vector3 = aim["position"]
	var origin: Vector3 = sky_origin(recipe, target, aim["normal"])
	hit.position = target
	hit.normal = aim["normal"]
	hit.direction = (target - origin).normalized()
	var projectile: SparkProjectile = free_projectile(combo_projectiles)
	if projectile:
		projectile.orb_charge = lerpf(0.4, 1.0, charge)
		projectile.launch(origin, target, hit, aim["collider"])
	var c: MotherCrystal = crystal()
	if c and recipe.fall_sec < 0.3:
		# El Trueno: el rayo baja ya, del cielo al blanco (violeta si es un eco).
		var col: Color = recipe.circle_hot if hit.tier == recipe.tier else hit.tier.color_glow * 1.8
		c.sky_bolt(origin, target, col)
	return origin


## De dónde cae un hechizo del cielo sobre `target`: alto, sobre el blanco y a un lado, para que
## se vea caer en diagonal (ver SkyPath); sus círculos se abren por ese camino.
func sky_origin(recipe: SpellRecipe, target: Vector3, normal: Vector3) -> Vector3:
	return SkyPath.origin(
		camera.get_world_3d().direct_space_state,
		camera.global_position,
		target,
		normal,
		recipe.sky_height,
		sky_side
	)


## Lluvia (de Estalactitas, de Estrellas): cae escalonada del cielo sobre una zona alrededor
## del blanco.
func _deliver_rain(recipe: SpellRecipe, hit: SpellHit) -> void:
	var aim: Dictionary = _aim.call()
	var center: Vector3 = aim["position"]
	var n: int = maxi(recipe.rain_count, 1)
	var each: int = maxi(1, roundi(float(hit.damage) / float(n)))
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var element: StringName = recipe.strike_element if recipe.strike_element != &"" else &"frost"
	for i: int in n:
		var a: float = _rng.randf() * TAU
		var rr: float = sqrt(_rng.randf()) * recipe.rain_radius * hit.size
		var ground: Vector3 = center + Vector3(cos(a), 0.0, sin(a)) * rr
		var sky: Vector3 = ground + Vector3.UP * recipe.sky_height
		var q := PhysicsRayQueryParameters3D.create(sky, ground - Vector3.UP * 30.0, 1 | (1 << 1))
		var r: Dictionary = space.intersect_ray(q)
		if r.is_empty():
			continue
		var sub := SpellHit.new()
		sub.tier = recipe.tier
		sub.recipe = recipe
		sub.element = element
		sub.damage = each
		sub.minor = i > 0
		sub.size = hit.size
		sub.resonant = hit.resonant and i == 0
		sub.position = r["position"]
		sub.normal = r["normal"]
		sub.direction = Vector3.DOWN
		var delay: float = 0.08 * i + _rng.randf() * 0.05
		get_tree().create_timer(delay).timeout.connect(
			func() -> void:
				var p: SparkProjectile = free_projectile(projectiles)
				if p:
					p.launch(sky, sub.position, sub, r["collider"])
		)


## Terremoto: la onda sale de tus pies, corre por el suelo y revienta la base del cristal en la
## dirección en la que miras.
func _deliver_ground(hit: SpellHit, charge: float) -> void:
	var feet: Vector3 = camera.global_position - Vector3(0, 1.45, 0)
	var flat: Vector3 = -camera.global_basis.z
	flat.y = 0.0
	flat = flat.normalized()
	var from: Vector3 = feet + flat * 1.0 + Vector3.UP * 0.4
	var q := PhysicsRayQueryParameters3D.create(from, from + flat * 120.0, 1 << 1)
	var r: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		AudioDirector.play_sfx(FIZZLE_SFX, -6.0)
		return
	hit.position = r["position"]
	hit.normal = r["normal"]
	hit.direction = flat
	var projectile: SparkProjectile = free_projectile(combo_projectiles)
	if projectile:
		projectile.orb_charge = lerpf(0.4, 1.0, charge)
		projectile.launch(from, hit.position, hit, r["collider"])
	_trauma(0.5)


## Haz de Plasma: golpea cada BEAM_TICK donde apunte la mirilla mientras dure.
func _process(delta: float) -> void:
	if _beam_left <= 0.0:
		set_process(false)
		return
	_beam_left -= delta
	_beam_tick -= delta
	var origin: Vector3 = _hand_origin.call(BOTH_HANDS)
	var aim: Dictionary = _aim.call()
	var c: MotherCrystal = crystal()
	if c:
		c.draw_beam(origin, aim["position"], _beam_hit.recipe.circle_color)
	if _beam_tick <= 0.0:
		_beam_tick = BEAM_TICK
		var collider: Object = aim["collider"]
		if collider is Node and (collider as Node).has_meta(&"mother_crystal"):
			var sub := SpellHit.new()
			sub.tier = _beam_hit.tier
			sub.recipe = _beam_hit.recipe
			sub.element = &"spark"
			sub.minor = true
			sub.size = _beam_hit.size
			sub.damage = maxi(
				1,
				roundi(float(_beam_hit.damage) * BEAM_TICK / maxf(_beam_hit.recipe.beam_sec, 0.1))
			)
			sub.position = aim["position"]
			sub.normal = aim["normal"]
			sub.direction = (sub.position - origin).normalized()
			((collider as Node).get_meta(&"mother_crystal") as MotherCrystal).receive_hit(sub)
	_trauma(delta * 0.6)
	if _beam_left <= 0.0:
		_beam_player.stop()


func _trauma(amount: float) -> void:
	if camera is CameraRig:
		(camera as CameraRig).add_trauma(amount)


func _on_projectile_arrived(projectile: SparkProjectile) -> void:
	if projectile.hit.warmup:
		return
	var collider: Object = projectile.target_collider
	if collider is Node and (collider as Node).has_meta(&"mother_crystal"):
		var c: MotherCrystal = (collider as Node).get_meta(&"mother_crystal")
		var r: SpellRecipe = projectile.hit.recipe
		if r and r.delivery == SpellRecipe.Delivery.NOVA and not projectile.hit.minor:
			# La estrella no estalla al llegar: se contrae y luego revienta (ver Supernova).
			_nova.ignite(projectile.hit, c, camera)
			return
		c.receive_hit(projectile.hit)
		if r and r.delivery == SpellRecipe.Delivery.RESONANCE:
			c.resonance_pulse(projectile.hit)
	else:
		AudioDirector.play_sfx(FIZZLE_SFX, -6.0)
		Events.spell_fizzled.emit(projectile.hit.position)


## Pantalla de carga: lanza un proyectil de cada aspecto distinto (niveles de cada elemento y
## combinaciones) hacia `target` sin efecto de juego, para compilar shaders y partículas.
func warm_up(target: Vector3, elements: Array[ElementDef], recipes: Array[SpellRecipe]) -> void:
	var from: Vector3 = camera.global_position + camera.global_basis * Vector3(0.0, -0.3, -1.5)
	var seen: Array[SpellVisualDef] = []
	var k: int = 0
	for el: ElementDef in elements:
		for tier: SpellTier in el.tiers:
			if seen.has(tier.visual) or k >= projectiles.size():
				continue
			seen.append(tier.visual)
			k += int(_warm(projectiles[k], from, target, tier, null))
	var j: int = 0
	for r: SpellRecipe in recipes:
		if r.is_reaction or r.tier == null:
			continue
		if j < combo_projectiles.size():
			j += int(_warm(combo_projectiles[j], from, target, r.tier, r))
		elif k < projectiles.size():
			k += int(_warm(projectiles[k], from, target, r.tier, r))
	_circles.charging(1.0, 2, from, target, Color.ORANGE, Color.WHITE)
	_circles.release()
	_storm.warm_up(target)
	_nova.warm_up(target, camera)


func _warm(
	p: SparkProjectile, from: Vector3, target: Vector3, tier: SpellTier, recipe: SpellRecipe
) -> bool:
	var hit := SpellHit.new()
	hit.tier = tier
	hit.recipe = recipe
	hit.warmup = true
	hit.position = target
	hit.normal = Vector3.BACK
	p.launch(from, target, hit, null)
	return true
