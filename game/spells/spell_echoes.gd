class_name SpellEchoes
extends Node
## Ecos del Arcano (GDD 5.1 y 5.2: "amplifica y duplica"; "Arcano + X = Eco de X").
## - Disparo suelto de Arcano: `SpellTier.echoes` copias fantasma vuelven a golpear el mismo
##   punto, una cada `ElementDef.echo_delay` s, saliendo de un círculo de runas junto a la mano.
## - Eco de X (`SpellRecipe.echo_of`): tras el X de verdad salen `echo_count` copias fantasma,
##   cada una por un círculo arcano que se abre junto a las manos (o en el cielo, si X cae del
##   cielo) y hacia donde mires en ese momento. En el cristal hacen lo mismo que X.
## Cada eco es la versión fantasma del hechizo (`SpellGhost`) y suena un tono más alto.

## Cada eco suena un tono más alto (pentatónica de La: 0, 2, 4, 7, 9 semitonos).
const PITCH: PackedFloat32Array = [1.0, 1.1225, 1.2599, 1.4983, 1.6818]
## Dónde se abren los círculos de los Ecos de X alrededor de las manos (derecha, arriba) a
## `DEPTH` m de la cámara.
const SPOTS: PackedVector2Array = [
	Vector2(0.62, 0.22), Vector2(-0.62, 0.22), Vector2(0.0, 0.48), Vector2(0.9, -0.05)
]
const DEPTH: float = 1.8
const HOT := Color(2.2, 1.8, 2.4)

var _caster: SpellCaster
var _circles: MagicCircles
## Funciones del lanzador que usan los ecos: apuntar, origen en la mano, entregar una receta,
## entregar desde el cielo y probabilidad de resonante (ver `setup`).
var _aim: Callable
var _hand_origin: Callable
var _deliver_recipe: Callable
var _deliver_sky: Callable
var _resonant_chance: Callable
var _pool: Array[SparkProjectile] = []
## Campanadas de los ecos (por elemento o por receta).
var _sounds: Dictionary[Resource, AudioStreamRandomizer] = {}
var _rng := RandomNumberGenerator.new()
var _ghost := SpellGhost.new()


## `calls`: [apuntar, origen en la mano, entregar, entregar desde el cielo, resonante] del
## lanzador (son suyas; los ecos sólo las reutilizan).
func setup(
	caster: SpellCaster, circles: MagicCircles, pool: Array[SparkProjectile], calls: Array[Callable]
) -> void:
	_caster = caster
	_circles = circles
	_pool = pool
	_aim = calls[0]
	_hand_origin = calls[1]
	_deliver_recipe = calls[2]
	_deliver_sky = calls[3]
	_resonant_chance = calls[4]
	_rng.randomize()
	for el: ElementDef in SpellCaster.ELEMENTS:
		if not el.echo_sfx.is_empty():
			_sounds[el] = _randomizer(el.echo_sfx)
	for r: SpellRecipe in SpellCaster.RECIPES:
		if not r.echo_sfx.is_empty():
			_sounds[r] = _randomizer(r.echo_sfx)


## Arcano suelto: `count` ecos del golpe `hit` (daño sin resonancia `base_damage`) desde la
## mano `side` hacia el mismo punto y el mismo `collider`.
func echo_single(side: int, hit: SpellHit, base_damage: int, collider: Object, count: int) -> void:
	var el: ElementDef = hit.element_def
	for k: int in count:
		var echo: SpellHit = ghost(hit, base_damage, el.echo_damage)
		var spot := Vector2(0.1 if side == 0 else -0.1, 0.1 + 0.09 * k)
		get_tree().create_timer(el.echo_delay * float(k + 1)).timeout.connect(
			func() -> void:
				var cam: Camera3D = _caster.camera
				var hand: Vector3 = _hand_origin.call(side)
				var origin: Vector3 = hand + cam.global_basis * Vector3(spot.x, spot.y, 0.0)
				_launch(echo, origin, collider)
				_circles.muzzle(origin, echo.position, 1, el.circle_color, HOT)
				_play(el, k, -6.0)
		)


## Eco de X: `recipe.echo_count` ecos de `base` tras el golpe `hit` (daño sin resonancia
## `damage`, carga `charge`).
func echo_recipe(
	recipe: SpellRecipe, base: SpellRecipe, hit: SpellHit, damage: int, charge: float
) -> void:
	for k: int in recipe.echo_count:
		# El golpe es el de X (hit.recipe = base) con el aspecto fantasma del Eco de X.
		var echo: SpellHit = ghost(hit, damage, recipe.echo_damage)
		echo.tier = _ghost.tier(recipe.tier)
		echo.recipe = base
		get_tree().create_timer(recipe.echo_delay * float(k + 1)).timeout.connect(
			_deliver.bind(recipe, base, echo, charge, k)
		)


## La copia fantasma de `hit` (mismo blanco, elemento y receta, aspecto fantasma) con
## `damage` (sin resonancia) x `fraction` de daño y su propia tirada de resonante. Sin pausa ni
## destello global: el golpe fuerte es el primero; los ecos llevan el ritmo. También la usa la
## runa de Eco (RuneCaster).
func ghost(hit: SpellHit, damage: int, fraction: float) -> SpellHit:
	var echo := SpellHit.new()
	echo.tier = _ghost.tier(hit.tier)
	echo.recipe = hit.recipe
	echo.element = hit.element
	echo.element_def = hit.element_def
	echo.size = hit.size
	echo.level = hit.level
	echo.echo = true
	echo.minor = true
	var bonus: float = hit.element_def.resonant_bonus if hit.element_def else 0.0
	echo.resonant = _rng.randf() < VariantCast.to_float(_resonant_chance.call(bonus))
	echo.damage = _echo_damage(damage, fraction, echo.resonant)
	echo.position = hit.position
	echo.normal = hit.normal
	return echo


## Lanza la copia `echo` (de `ghost`) desde `origin` hacia su punto y `collider`.
func launch_ghost(echo: SpellHit, origin: Vector3, collider: Object, orb_charge: float) -> void:
	_launch(echo, origin, collider, orb_charge)


func _deliver(
	recipe: SpellRecipe, base: SpellRecipe, echo: SpellHit, charge: float, k: int
) -> void:
	var cam: Camera3D = _caster.camera
	if base.delivery == SpellRecipe.Delivery.SKY:
		var origin: Vector3 = _deliver_sky.call(base, echo, charge, _scattered_aim(k))
		var down: Vector3 = (echo.position - origin).normalized()
		_circles.stamp(
			origin + down * 3.0, down, 4.5, recipe.circle_color, recipe.circle_hot, 0.7, 4.0
		)
	elif base.delivery == SpellRecipe.Delivery.FRONT or base.delivery == SpellRecipe.Delivery.LANCE:
		var spot: Vector2 = SPOTS[k % SPOTS.size()]
		var origin: Vector3 = (
			cam.global_position + cam.global_basis * Vector3(spot.x, spot.y, -DEPTH)
		)
		var aim: Dictionary = _aim.call()
		echo.position = aim["position"]
		echo.normal = aim["normal"]
		_circles.stamp(
			origin,
			(echo.position - origin).normalized(),
			0.32,
			recipe.circle_color,
			recipe.circle_hot,
			0.6,
			7.0
		)
		var collider: Object = aim["collider"]
		_launch(echo, origin, collider, lerpf(0.3, 0.6, charge))
	else:
		_deliver_recipe.call(base, echo, charge)
	_play(recipe, k, 0.0)
	Events.spell_cast.emit(echo.tier, SpellCaster.BOTH_HANDS)


## Lanza un eco fantasma desde `origin` hacia su punto (ya en `hit.position`).
func _launch(hit: SpellHit, origin: Vector3, collider: Object, orb_charge: float = 1.0) -> void:
	var p: SparkProjectile = null
	for candidate: SparkProjectile in _pool:
		if not candidate.active:
			p = candidate
			break
	if p == null:
		return
	hit.direction = (hit.position - origin).normalized()
	p.orb_charge = orb_charge
	p.launch(origin, hit.position, hit, collider)


func _play(owner_res: Resource, k: int, volume_db: float) -> void:
	if _sounds.has(owner_res):
		AudioDirector.play_sfx(_sounds[owner_res], volume_db - 1.5 * k, PITCH[k % PITCH.size()])


## Blanco de un eco del cielo: donde miras, desplazado por la superficie para que no caigan
## todos en el mismo punto.
func _scattered_aim(k: int) -> Dictionary:
	var aim: Dictionary = _aim.call()
	var n: Vector3 = aim["normal"]
	if aim["collider"] == null or n.length_squared() < 0.01:
		return aim
	var side: Vector3 = n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized()
	var up: Vector3 = side.cross(n).normalized()
	var a: float = float(k) * 2.4 + _rng.randf() * 0.6
	var off: Vector3 = (side * cos(a) + up * sin(a)) * _rng.randf_range(2.5, 4.5)
	var aim_at: Vector3 = aim["position"]
	var from: Vector3 = aim_at + off + n * 4.0
	var q := PhysicsRayQueryParameters3D.create(from, from - n * 10.0, 1 << 1)
	var r: Dictionary = _caster.camera.get_world_3d().direct_space_state.intersect_ray(q)
	return aim if r.is_empty() else r


## La receta que repite un Eco de X (`echo_of`), o null si no es un eco.
static func base_of(recipe: SpellRecipe) -> SpellRecipe:
	if recipe.echo_of == &"":
		return null
	for r: SpellRecipe in SpellCaster.RECIPES:
		if r.id == recipe.echo_of:
			return r
	return null


static func _echo_damage(damage: int, fraction: float, resonant: bool) -> int:
	return (
		maxi(1, roundi(float(damage) * fraction))
		* (GameState.BALANCE.resonant_damage_mult if resonant else 1)
	)


func _randomizer(streams: Array[AudioStream]) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	for s: AudioStream in streams:
		r.add_stream(-1, s)
	r.random_pitch = 1.03
	r.random_volume_offset_db = 1.5
	return r
