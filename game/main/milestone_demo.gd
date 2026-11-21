class_name MilestoneDemo
extends RefCounted
## Modo demo de los nodos hito (sólo para capturas; lo llama Main._setup_autoplay):
## --autofire[=s]: Lanzamiento continuo inscrito; a los s segundos (3,4 por defecto) mantiene el
##   botón izquierdo (con --no-cast para que la demo no clique además). --autofire-join=s: a los
##   s segundos pulsa también el derecho (las manos se juntan) y --autofire-release=s suelta todo.
## --vortex: Vórtice inscrito (con el envío directo) y, al acabar la carga, 40 fragmentos sueltos
##   alrededor del mago que el remolino aspira (--vortex=N: N fragmentos).
## --facet-crit: Rompefacetas inscrito y todo golpe del mago es resonante (cada uno parte faceta).
##   --facet-hit=D: además, a los 3,5 s un golpe resonante de daño D donde mira la cámara.


static func setup(main: Node, args: PackedStringArray, player: Player) -> void:
	var tree: SceneTree = main.get_tree()
	var prog: Progression = GameState.progression
	for a: String in args:
		if a.begins_with("--autofire") and not a.begins_with("--autofire-"):
			prog.upgrade_levels[&"channeling"] = maxi(prog.get_level(&"channeling"), 1)
			prog.upgrade_levels[&"autocast"] = 1
			var at: float = float(a.get_slice("=", 1)) if a.contains("=") else 3.4
			tree.create_timer(at).timeout.connect(_press.bind(player, 0, true))
		elif a.begins_with("--autofire-join="):
			var at: float = float(a.get_slice("=", 1))
			tree.create_timer(at).timeout.connect(_press.bind(player, 1, true))
		elif a.begins_with("--autofire-release="):
			var at: float = float(a.get_slice("=", 1))
			tree.create_timer(at).timeout.connect(_press.bind(player, 0, false))
			tree.create_timer(at).timeout.connect(_press.bind(player, 1, false))
		elif a.begins_with("--vortex"):
			prog.upgrade_levels[&"direct_send"] = 1
			prog.upgrade_levels[&"vortex"] = 1
			var n: int = int(a.get_slice("=", 1)) if a.contains("=") else 40
			tree.create_timer(3.3).timeout.connect(_litter.bind(player, n))
		elif a == "--facet-crit":
			prog.upgrade_levels[&"resonance"] = maxi(prog.get_level(&"resonance"), 1)
			prog.upgrade_levels[&"facet_break"] = 1
			# Resonancia Arcana sin fin: cada golpe del mago resuena.
			player.get_caster().set(&"_resonance_left", 3600.0)
		elif a.begins_with("--facet-hit="):
			prog.upgrade_levels[&"facet_break"] = 1
			var dmg: int = int(a.get_slice("=", 1))
			tree.create_timer(3.5).timeout.connect(_facet_hit.bind(player, dmg))
	Events.upgrade_bought.emit(&"", 0)


static func _press(player: Player, side: int, down: bool) -> void:
	var caster: SpellCaster = player.get_caster()
	if down:
		caster.call(&"_on_press", side)
	else:
		caster.call(&"_on_release", side)


## Fragmentos sueltos repartidos entre 8 y 34 m del mago (delante y a los lados).
static func _litter(player: Player, count: int) -> void:
	var pool: ShardPool = player.get_tree().get_first_node_in_group(&"shard_pool") as ShardPool
	if pool == null:
		return
	var base: Vector3 = player.global_position
	var yaw: float = player.rotation.y
	for i: int in count:
		var a: float = yaw + randf_range(-1.6, 1.6)
		var d: float = randf_range(8.0, 34.0)
		var at: Vector3 = base + Vector3(-sin(a), 0.0, -cos(a)) * d + Vector3.UP * 2.0
		pool.spawn(at, Vector3.UP, ShardPool.TYPES[i % 3], 1, 0.25)


## Un golpe resonante del mago donde mira la cámara (sin proyectil): para ver la faceta.
static func _facet_hit(player: Player, damage: int) -> void:
	var cam: Camera3D = player.get_camera()
	var from: Vector3 = cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * 250.0, 1 << 1)
	var r: Dictionary = cam.get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return
	var collider: Node = r["collider"]
	if not collider.has_meta(&"mother_crystal"):
		return
	var crystal: MotherCrystal = collider.get_meta(&"mother_crystal")
	var hit := SpellHit.new()
	hit.position = r["position"]
	hit.normal = r["normal"]
	hit.direction = -cam.global_basis.z
	hit.damage = damage
	hit.resonant = true
	hit.element = &"spark"
	hit.element_def = SpellCaster.ELEMENT
	hit.tier = SpellCaster.ELEMENT.tiers[4]
	crystal.receive_hit(hit)
