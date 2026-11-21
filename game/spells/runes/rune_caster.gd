class_name RuneCaster
extends Node
## Lo que hacen las runas inscritas en la Mesa de Runas (GDD 5.3, reglas en RuneBook) en los
## hechizos que salen de las manos: los sueltos y, más flojo (`RuneDef.combo_scale`), los combinados
## que vuelan desde las palmas (Bola de Fuego, Choque Térmico, lanzas). Las triples del báculo, lo
## que cae del cielo, el haz, la onda y los familiares no las llevan.
## - Multidisparo: chispas de más en abanico, más pequeñas y doradas (revientan bichos igual).
## - Rebote: al llegar al cristal, el golpe salta a otro punto de la superficie (o a un bicho
##   cercano) y vuelve a golpear, más pequeño y magenta, tantas veces como su nivel.
## - Perforación: el golpe sigue por dentro del cristal y excava un túnel detrás del primero.
## - Eco: a veces sale gratis una copia fantasma del hechizo (los ecos del Arcano, SpellEchoes).
## - Cosecha: menos daño (`harvested`) y más maná por fragmento (GameState.shard_value).
## Lo que se ve y se oye de cada una está en RuneFx. Proyectiles en pools propios.

const MULTISHOT_POOL: int = 10
const BOUNCE_POOL: int = 8
## Grados entre las chispas del abanico.
const FAN_DEG: float = 3.6
## Hasta dónde salta un rebote (m) y radio en el que prefiere a un bicho.
const BOUNCE_REACH := Vector2(3.0, 6.5)
const BOUNCE_CRITTER_RADIUS: float = 6.5
## Lo que tarda en salir el eco (s).
const ECHO_DELAY: float = 0.3
## Paso del túnel de la Perforación (m).
const PIERCE_STEP: float = 0.9
## Las chispas de las runas nunca bajan de este tamaño (por debajo de 0,6 un golpe es "flojo" y
## suelta una astilla).
const MIN_SIZE: float = 0.65
const RAY_LENGTH: float = 250.0
## Tinte de lo que sale de cada runa (las chispas de más y los rebotes) y cuánto.
const TINT_MIX: float = 0.5

var fx: RuneFx
var _caster: SpellCaster
var _delivery: SpellDelivery
var _echoes: SpellEchoes
var _hand_origin: Callable
var _multi_pool: Array[SparkProjectile] = []
var _bounce_pool: Array[SparkProjectile] = []
var _tints: Dictionary[RuneDef.Kind, SpellGhost] = {}
var _fan_flip: int = 1
var _rng := RandomNumberGenerator.new()


## Lo crea SpellDelivery (sus pools llegan al cristal por el mismo camino que el resto).
func setup(delivery: SpellDelivery, hand_origin: Callable) -> void:
	_delivery = delivery
	_hand_origin = hand_origin
	_rng.randomize()
	for i: int in MULTISHOT_POOL:
		_multi_pool.append(delivery.make_projectile("RuneMulti%d" % i))
	for i: int in BOUNCE_POOL:
		_bounce_pool.append(delivery.make_projectile("RuneBounce%d" % i))
	for def: RuneDef in RuneBook.RUNES:
		_tints[def.kind] = SpellGhost.new(def.color, TINT_MIX)
	fx = RuneFx.new()
	fx.name = "RuneFx"
	add_child(fx)
	Events.spell_impacted.connect(_on_impacted)


## El lanzador: sus llamas (para lo que sale de los combinados) y sus ecos (runa de Eco).
func bind(caster: SpellCaster, echoes: SpellEchoes) -> void:
	_caster = caster
	_echoes = echoes


## Cosecha: el daño de un hechizo del mago con la runa inscrita (sin ella, igual).
func harvested(damage: int) -> int:
	var mult: float = RuneBook.harvest_damage(GameState.progression)
	if damage <= 0 or mult >= 1.0:
		return damage
	return maxi(1, roundi(float(damage) * mult))


## Tras lanzar `hit` desde `origin` (la mano `side`) hacia el blanco `aim` (con su colisionador):
## el golpe se lleva el Rebote y la Perforación y salen el abanico y el eco.
func on_launch(hit: SpellHit, side: int, origin: Vector3, aim: Dictionary) -> void:
	if not _eligible(hit):
		return
	var prog: Progression = GameState.progression
	var base: int = _base_damage(hit)
	var def: RuneDef = RuneBook.def_of_kind(RuneDef.Kind.BOUNCE)
	var lv: int = RuneBook.active_level(prog, def.kind)
	if lv > 0:
		hit.rune_bounces = roundi(def.value_at(lv))
		hit.rune_bounce_frac = def.damage_at(lv) * _scale(def, hit)
	def = RuneBook.def_of_kind(RuneDef.Kind.PIERCE)
	lv = RuneBook.active_level(prog, def.kind)
	if lv > 0:
		hit.rune_pierce = def.damage_at(lv) * _scale(def, hit)
		hit.rune_depth = def.value_at(lv)
	def = RuneBook.def_of_kind(RuneDef.Kind.MULTISHOT)
	lv = RuneBook.active_level(prog, def.kind)
	if lv > 0:
		var dmg: int = maxi(1, roundi(float(base) * def.damage_at(lv) * _scale(def, hit)))
		_fan(hit, origin, roundi(def.value_at(lv)), dmg, def)
	def = RuneBook.def_of_kind(RuneDef.Kind.ECHO)
	lv = RuneBook.active_level(prog, def.kind)
	if lv > 0 and _rng.randf() < def.value_at(lv) / 100.0 * _scale(def, hit):
		var echo: SpellHit = _echoes.ghost(hit, base, def.damage_at(lv))
		echo.rune_spawn = true
		get_tree().create_timer(ECHO_DELAY).timeout.connect(
			_fire_echo.bind(echo, side, aim["collider"], def)
		)


## Sólo los hechizos del mago que salen de las manos (y no lo que ya sale de una runa o un eco).
static func _eligible(hit: SpellHit) -> bool:
	if hit.warmup or hit.echo or hit.rune_spawn or not hit.by_player or hit.familiar:
		return false
	if hit.damage <= 0:
		return false
	if hit.recipe == null:
		return true
	if hit.recipe.is_triple():
		return false
	return (
		hit.recipe.delivery == SpellRecipe.Delivery.FRONT
		or hit.recipe.delivery == SpellRecipe.Delivery.LANCE
	)


static func _scale(def: RuneDef, hit: SpellHit) -> float:
	return 1.0 if hit.recipe == null else def.combo_scale


## Daño del golpe sin la resonancia (lo que sale de más tira su propia resonancia o ninguna).
static func _base_damage(hit: SpellHit) -> int:
	var mult: int = GameState.BALANCE.resonant_damage_mult if hit.resonant else 1
	@warning_ignore("integer_division")
	return maxi(1, hit.damage / mult)


## Un golpe de una runa a partir de `hit`: el mismo hechizo (o la llama de la mano izquierda, si
## era un combinado) en pequeño y teñido del color de la runa.
func _sub(hit: SpellHit, damage: int, def: RuneDef, shrink: float) -> SpellHit:
	var sub := SpellHit.new()
	var el: ElementDef = hit.element_def
	var tier: SpellTier = hit.tier
	if el == null:
		el = _caster.element_of(0) if _caster else SpellCaster.ELEMENT
		tier = _caster.tier_for(0) if _caster else el.tiers[0]
	sub.tier = _tints[def.kind].tier(tier)
	sub.element = el.id
	sub.element_def = el
	sub.size = maxf(MIN_SIZE, hit.size * shrink)
	sub.level = hit.level
	sub.minor = true
	sub.rune_spawn = true
	sub.damage = maxi(1, damage)
	return sub


## Multidisparo: `count` chispas en abanico (a los lados de la mira, alternando) desde la mano.
func _fan(hit: SpellHit, origin: Vector3, count: int, damage: int, def: RuneDef) -> void:
	var cam: Camera3D = _delivery.camera
	var from_cam: Vector3 = cam.global_position
	var aim_dir: Vector3 = (hit.position - from_cam).normalized()
	var right: Vector3 = cam.global_basis.x
	var up: Vector3 = cam.global_basis.y
	var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state
	_fan_flip = -_fan_flip
	for k: int in count:
		var p: SparkProjectile = SpellDelivery.free_projectile(_multi_pool)
		if p == null:
			break
		var step: int = ceili(float(k + 1) * 0.5) * (_fan_flip if k % 2 == 0 else -_fan_flip)
		var yaw: float = deg_to_rad(FAN_DEG * float(step) + _rng.randf_range(-0.6, 0.6))
		var pitch: float = deg_to_rad(_rng.randf_range(-0.8, 1.4))
		var dir: Vector3 = aim_dir.rotated(up, yaw).rotated(right, pitch).normalized()
		var q := PhysicsRayQueryParameters3D.create(
			from_cam, from_cam + dir * RAY_LENGTH, 1 | (1 << 1) | Critter.LAYER
		)
		var r: Dictionary = space.intersect_ray(q)
		var sub: SpellHit = _sub(hit, damage, def, 0.72)
		var collider: Object = null
		if r.is_empty():
			sub.position = from_cam + dir * 40.0
			sub.normal = -dir
		else:
			sub.position = r["position"]
			sub.normal = r["normal"]
			collider = r["collider"]
		var start: Vector3 = origin + right * (0.04 * float(step))
		sub.direction = (sub.position - start).normalized()
		p.launch(start, sub.position, sub, collider)
	fx.fan(origin, aim_dir, count, def)


## Eco: la copia fantasma sale de junto a la mano hacia el mismo blanco.
func _fire_echo(echo: SpellHit, side: int, collider: Object, def: RuneDef) -> void:
	var cam: Camera3D = _delivery.camera
	var lift := Vector3(0.12 if side == 0 else -0.12, 0.14, 0.0)
	var hand: Vector3 = _hand_origin.call(side)
	var origin: Vector3 = hand + cam.global_basis * lift
	_echoes.launch_ghost(echo, origin, collider, 0.55 if echo.recipe else 1.0)
	fx.echo(origin, echo.position, def)


func _on_impacted(hit: SpellHit) -> void:
	if hit.warmup:
		return
	if hit.rune_pierce > 0.0:
		_pierce(hit)
	if hit.rune_bounces > 0:
		_bounce(hit)
	if hit.by_player and not hit.familiar and RuneBook.harvest_damage(GameState.progression) < 1.0:
		fx.harvest(hit.position, hit.normal)


## Rebote: salta a un bicho cercano o a otro punto de la superficie y vuelve a golpear.
func _bounce(hit: SpellHit) -> void:
	var p: SparkProjectile = SpellDelivery.free_projectile(_bounce_pool)
	if p == null:
		return
	var def: RuneDef = RuneBook.def_of_kind(RuneDef.Kind.BOUNCE)
	var target: Dictionary = _bounce_target(hit)
	if target.is_empty():
		return
	var sub: SpellHit = _sub(hit, roundi(float(hit.damage) * hit.rune_bounce_frac), def, 0.82)
	sub.rune_bounces = hit.rune_bounces - 1
	sub.rune_bounce_frac = hit.rune_bounce_frac
	sub.position = target["position"]
	sub.normal = target["normal"]
	var from: Vector3 = hit.position + hit.normal * 0.35
	sub.direction = (sub.position - from).normalized()
	var collider: Object = target["collider"]
	p.launch(from, sub.position, sub, collider)
	var k: int = RuneBook.active_level(GameState.progression, def.kind) - sub.rune_bounces - 1
	fx.bounce(hit.position, hit.normal, sub.position, k, def)


## Adónde rebota: a un bicho vivo cerca del impacto o a otro punto del cristal que ceda ante el
## golpe (en el Corazón, un rebote suelto no vale). {} si no hay.
func _bounce_target(hit: SpellHit) -> Dictionary:
	var herd: CritterHerd = CritterHerd.instance()
	if herd:
		for c: Critter in herd.critters():
			if c.is_alive() and c.center().distance_to(hit.position) < BOUNCE_CRITTER_RADIUS:
				var to: Vector3 = c.center()
				return {
					"position": to, "normal": (hit.position - to).normalized(), "collider": null
				}
	var crystal: MotherCrystal = _delivery.crystal()
	if crystal == null:
		return {}
	var n: Vector3 = hit.normal if hit.normal.length_squared() > 0.01 else Vector3.UP
	var side: Vector3 = n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized()
	var up: Vector3 = side.cross(n).normalized()
	var space: PhysicsDirectSpaceState3D = crystal.get_world_3d().direct_space_state
	for attempt: int in 4:
		var a: float = _rng.randf() * TAU
		var off: Vector3 = (
			(side * cos(a) + up * sin(a)) * _rng.randf_range(BOUNCE_REACH.x, BOUNCE_REACH.y)
		)
		var from: Vector3 = hit.position + off + n * 2.5
		var q := PhysicsRayQueryParameters3D.create(from, from - n * 6.0, 1 << 1)
		var r: Dictionary = space.intersect_ray(q)
		if r.is_empty():
			continue
		var at: Vector3 = r["position"]
		var normal: Vector3 = r["normal"]
		if _yields(crystal, at, normal):
			return r
	return {}


## True si la capa del cristal en `at` cede ante un golpe suelto (el Corazón sólo ante combinados;
## el Núcleo, ante nada).
static func _yields(crystal: MotherCrystal, at: Vector3, normal: Vector3) -> bool:
	var n: Vector3 = (crystal.global_basis.inverse() * normal).normalized()
	var layer: int = crystal.volume.layer_at(crystal.to_local(at) - n * 0.35)
	var def: CrystalLayerDef = GameState.LAYERS[clampi(layer, 0, GameState.LAYERS.size() - 1)]
	return not def.immune and not def.needs_combo


## Perforación: un túnel detrás del impacto, por la dirección de vuelo, que arranca esa parte del
## daño (lo que no cede corta el túnel) y suelta sus fragmentos por la boca.
func _pierce(hit: SpellHit) -> void:
	var crystal: MotherCrystal = _delivery.crystal()
	if crystal == null:
		return
	var def: RuneDef = RuneBook.def_of_kind(RuneDef.Kind.PIERCE)
	var dir: Vector3 = hit.direction.normalized()
	if dir.length_squared() < 0.5:
		dir = -hit.normal
	var steps: int = maxi(2, ceili(hit.rune_depth * hit.size / PIERCE_STEP))
	var each: float = float(hit.damage) * hit.rune_pierce / float(steps)
	var removed: float = 0.0
	var last: Vector3 = hit.position
	var done: int = 0
	# Lo que ya es aire (el cráter, un túnel de antes) se cruza sin contar: sigue hasta arrancar
	# lo suyo o hasta el doble de fondo.
	for k: int in steps * 2:
		var p: Vector3 = hit.position + dir * (0.7 + PIERCE_STEP * float(k + 1))
		var got: float = crystal.dig(p, -dir, each, hit.recipe != null, hit.size)
		if got < 0.0:
			break
		if got <= 0.0:
			continue
		removed += got
		last = p
		done += 1
		if done % 2 == 0:
			crystal.add_crack(p, 0.8 * hit.size)
		if done >= steps:
			break
	if removed <= 0.0:
		return
	# La boca del túnel queda resquebrajada (grieta persistente del cristal).
	crystal.add_crack(hit.position, 1.5 * hit.size)
	var pool: ShardPool = get_tree().get_first_node_in_group(&"shard_pool") as ShardPool
	if pool:
		pool.spawn_worth(hit.position, hit.normal, removed, 1.2, crystal.hit_layer())
	fx.pierce(hit.position, last, hit.normal, def)


## Pantalla de carga: una chispa de cada runa (sin efecto) y sus efectos, para compilarlos.
func warm_up(target: Vector3) -> void:
	fx.warm_up(target)
