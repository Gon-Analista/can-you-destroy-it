class_name CrystalCombos
extends Node
## Lo que hacen en el Cristal Madre las combinaciones y las reacciones: lanzas que perforan,
## rayos que saltan a otros puntos, el Trueno que baja del cielo, el pulso del Magnetismo y las
## reacciones Explosión de Vapor (fuego sobre hielo) y Temple (hielo sobre fuego), que se
## descubren al provocarlas.

const STEAM_RECIPE: SpellRecipe = preload("res://data/spells/recipe_steam.tres")
const TEMPER_RECIPE: SpellRecipe = preload("res://data/spells/recipe_temper.tres")
const STEAM_SFX: AudioStream = preload("res://audio/sfx/sfx_steam_burst_01.ogg")

var _crystal: MotherCrystal
var _arcs: CrystalArcs
var _shards: ShardPool
var _hd_fx: HdImpact
var _fx: ImpactFx
var _steam: GPUParticles3D
var _rng := RandomNumberGenerator.new()


func setup(
	crystal: MotherCrystal, arcs: CrystalArcs, shards: ShardPool, hd_fx: HdImpact, fx: ImpactFx
) -> void:
	_crystal = crystal
	_arcs = arcs
	_shards = shards
	_hd_fx = hd_fx
	_fx = fx
	_rng.randomize()
	_steam = HdFx.smoke(60, 2.4, Color(0.95, 0.97, 1.0))
	_steam.name = "Steam"
	_steam.one_shot = true
	_steam.explosiveness = 0.85
	_steam.emitting = false
	_steam.lifetime = 2.2
	add_child(_steam)


## Explosión de Vapor: fuego sobre cristal congelado. +50 % de daño, nube de vapor y el doble
## de fragmentos (la zona helada la gasta MotherCrystal).
func steam(hit: SpellHit, at: Vector3) -> void:
	hit.damage = roundi(float(hit.damage) * 1.5)
	var n: Vector3 = hit.normal if hit.normal.length_squared() > 0.01 else Vector3.UP
	_shards.spawn(at, n, ShardPool.TYPES[1], 4, 1.4, _crystal.hit_layer())
	_hd_fx.play(at, n, hit.tier, true, true, 1.6)
	_puff(at + n * 0.6)
	AudioDirector.play_sfx(STEAM_SFX, -2.0, 0.9)
	_crystal.flash(0.45)
	GameState.register_recipe_cast(STEAM_RECIPE)


## Temple: escarcha sobre cristal al rojo (quemadura reciente). Se parte en fragmentos grandes
## con una grieta enorme; la quemadura se apaga.
func check_temper(hit: SpellHit) -> void:
	if hit.element != &"frost":
		return
	var b: Vector4 = _crystal.hot_burn_near(hit.position, 0.8, true)
	if b.w < 0.0:
		return
	var at := Vector3(b.x, b.y, b.z)
	hit.damage = roundi(float(hit.damage) * 1.8)
	var n: Vector3 = hit.normal if hit.normal.length_squared() > 0.01 else Vector3.UP
	# Siempre fragmentos grandes (TYPES ya llega a los Pedruscos: "el mayor" daría 1.500 de maná).
	_shards.spawn(at, n, ShardPool.CHUNK, 3, 1.5, _crystal.hit_layer())
	_crystal.add_crack(at, b.w * 2.4 + 1.5)
	_hd_fx.play(at, n, hit.tier, true, true, 1.5)
	_puff(at + n * 0.5)
	AudioDirector.play_sfx(STEAM_SFX, -4.0, 1.3)
	_crystal.flash(0.5)
	GameState.register_recipe_cast(TEMPER_RECIPE)


## Lanzas: perforan un túnel recto y hondo por la dirección de vuelo. La Lanza de Hielo deja
## las paredes congeladas; la Cargada, chispas que saltan por el túnel.
func pierce(hit: SpellHit) -> void:
	var recipe: SpellRecipe = hit.recipe
	var dir: Vector3 = hit.direction.normalized()
	if dir.length_squared() < 0.5:
		dir = -hit.normal
	var steps: int = maxi(2, ceili(recipe.pierce_depth * hit.size / 0.9))
	var each: float = float(hit.damage) * 0.9 / float(steps)
	var prev: Vector3 = hit.position
	for k: int in steps:
		var p: Vector3 = hit.position + dir * (0.6 + 0.9 * float(k + 1))
		if _crystal.dig(p, -dir, each, true, hit.size) < 0.0:
			break
		if recipe.chain_count > 0 and k % 3 == 0:
			_arcs.strike(p, -dir, 0.7, recipe.circle_hot * 1.5)
			_arcs.bolt_between(prev, p, 0.1, recipe.circle_color * 1.6, 0.35)
		if recipe.freeze_trail and k % 3 == 1:
			_crystal.add_weak_zone(p, 1.6 * hit.size, 2.0, 6.0)
		prev = p
	_shards.spawn(hit.position, hit.normal, ShardPool.TYPES[1], 2, 1.3, _crystal.hit_layer())


## Rayos que saltan del impacto a otros puntos cercanos de la superficie: cada uno arranca un
## poco de cristal y suelta un fragmento.
func chain(hit: SpellHit, count: int) -> void:
	var space: PhysicsDirectSpaceState3D = _crystal.get_world_3d().direct_space_state
	var n: Vector3 = hit.normal if hit.normal.length_squared() > 0.01 else Vector3.UP
	var side: Vector3 = n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized()
	var up: Vector3 = side.cross(n).normalized()
	var col: Color = hit.recipe.circle_hot * 1.6 if hit.recipe else Color(1.8, 1.7, 0.9)
	var reach: float = 3.0 + float(count) * 0.8
	for k: int in count:
		var a: float = _rng.randf() * TAU
		var off: Vector3 = (side * cos(a) + up * sin(a)) * _rng.randf_range(reach * 0.5, reach)
		var from: Vector3 = hit.position + off + n * 2.5
		var q := PhysicsRayQueryParameters3D.create(from, from - n * 6.0, 1 << 1)
		var r: Dictionary = space.intersect_ray(q)
		if r.is_empty():
			continue
		var p: Vector3 = r["position"]
		_arcs.bolt_between(hit.position + n * 0.2, p, 0.12, col, 0.4)
		var worth: float = maxf(1.0, float(hit.damage) * 0.2)
		if _crystal.dig(p, r["normal"], worth, hit.recipe != null) > 0.0:
			_shards.spawn_worth(p, r["normal"], worth, 1.0, _crystal.hit_layer())
		_fx.play(p, r["normal"], hit.tier, false, 0.7)


## Juicio del Trueno: el rayo baja del cielo al blanco (varias hebras), con destello.
func sky_bolt(from: Vector3, to: Vector3, col: Color) -> void:
	# Tres descargas seguidas (como un rayo de verdad): se lee la columna y no sólo el destello.
	for k: int in 3:
		var delay: float = [0.0, 0.08, 0.2][k]
		get_tree().create_timer(delay).timeout.connect(
			func() -> void:
				_arcs.bolt_between(from, to, 0.7 - k * 0.15, col * 1.6, 0.35)
				_arcs.bolt_between(from + Vector3(1.5, 0, -1.0), to, 0.3, col * 1.2, 0.25)
				_crystal.flash(0.3 - k * 0.08)
		)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig:
		(cam as CameraRig).add_trauma(0.55)


## Resonancia Arcana: el cristal entero vibra. Una onda de golpes resonantes se abre por la
## superficie desde el impacto en tres anillos (cuanto más lejos, más tarde), cada uno con su
## destello, su rayo desde el centro y un fragmento; tormenta de rayos violeta por el cristal.
func resonance_pulse(hit: SpellHit) -> void:
	var col: Color = hit.recipe.circle_hot * 1.4 if hit.recipe else Color(1.8, 1.2, 2.2)
	_arcs.storm(
		_crystal.global_position, _crystal.volume.top * 0.7, WorldLayout.CRYSTAL_FOOTPRINT, col
	)
	_crystal.flash(0.4)
	var space: PhysicsDirectSpaceState3D = _crystal.get_world_3d().direct_space_state
	var n0: Vector3 = hit.normal if hit.normal.length_squared() > 0.01 else Vector3.BACK
	var side: Vector3 = n0.cross(Vector3.UP if absf(n0.y) < 0.95 else Vector3.RIGHT).normalized()
	var up: Vector3 = side.cross(n0).normalized()
	var phase: float = _rng.randf() * TAU
	var count: int = 12
	for k: int in count:
		var ring: int = k % 3
		var a: float = phase + TAU * float(k) / float(count) + float(ring) * 0.4
		var radius: float = 4.0 + 4.5 * float(ring)
		var from: Vector3 = hit.position + (side * cos(a) + up * sin(a)) * radius + n0 * 6.0
		var q := PhysicsRayQueryParameters3D.create(from, from - n0 * 16.0, 1 << 1)
		var r: Dictionary = space.intersect_ray(q)
		if r.is_empty():
			continue
		var p: Vector3 = r["position"]
		var n: Vector3 = r["normal"]
		var center: Vector3 = hit.position + n0 * 0.3
		get_tree().create_timer(0.1 + radius * 0.035).timeout.connect(
			func() -> void:
				_arcs.bolt_between(center, p, 0.22, col, 0.45)
				# Sólo suelta fragmentos donde el cristal cede (el Núcleo no da nada gratis).
				var worth: float = maxf(1.0, float(hit.damage) * 0.1)
				if _crystal.dig(p, n, worth, true) > 0.0:
					_shards.spawn_worth(p, n, worth, 1.2, _crystal.hit_layer())
				_hd_fx.play(p, n, hit.tier, true, false, 0.7)
		)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig:
		(cam as CameraRig).add_trauma(0.4)


## Magnetismo: rayos desde el mago a su alrededor; aviso si no había nada que atraer.
func magnet_pulse(at: Vector3, pulled: int) -> void:
	for k: int in mini(pulled + 4, 12):
		var a: float = TAU * float(k) / 12.0
		var to: Vector3 = at + Vector3(cos(a), 0.2, sin(a)) * _rng.randf_range(4.0, 9.0)
		_arcs.bolt_between(at + Vector3.UP * 0.8, to, 0.08, Color(0.8, 0.9, 2.0), 0.5)
	if pulled == 0:
		Events.hint.emit(tr("NO HAY FRAGMENTOS CERCA"), Color("#a5c8ff"))


func _puff(at: Vector3) -> void:
	_steam.global_position = at
	_steam.restart()
