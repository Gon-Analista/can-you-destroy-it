class_name CrystalGeodes
extends Node
## Las geodas del Manto Geódico (GDD 6): una excavación que llega a una bolsa la abre (se ve la
## amatista dentro) y un golpe cerca la revienta en una lluvia de fragmentos grandes. El estado
## de cada una (1 abierta, 2 rota) se guarda en `Progression.geodes`.

const OPEN_SFX: AudioStream = preload("res://audio/sfx/sfx_streak_chime_01.ogg")
## La geoda suena como el resquebrajo, más aguda.
const BREAK_SFX: AudioStream = preload("res://audio/sfx/sfx_crystal_surge_01.ogg")
const COLOR := Color("#e9a5ff")

var _crystal: MotherCrystal
var _arcs: CrystalArcs
var _shards: ShardPool
var _hd_fx: HdImpact
var _nodes: Dictionary[int, Geode] = {}


func setup(crystal: MotherCrystal, arcs: CrystalArcs, shards: ShardPool, hd_fx: HdImpact) -> void:
	_crystal = crystal
	_arcs = arcs
	_shards = shards
	_hd_fx = hd_fx
	# Las que ya estaban abiertas al cargar la partida.
	for i: int in crystal.volume.geodes.size():
		if GameState.progression.geodes.get(i, 0) == 1:
			_reveal(i, false)


## Una excavación en `p` (local) de radio `radius`: abre las bolsas a las que llega.
func check_pockets(p: Vector3, radius: float) -> void:
	var geodes: Array = _crystal.volume.geodes
	for i: int in geodes.size():
		if GameState.progression.geodes.has(i):
			continue
		var g: Dictionary = geodes[i]
		var center: Vector3 = g["center"]
		var g_radius: float = g["radius"]
		if center.distance_to(p) < g_radius + radius * 0.6:
			GameState.progression.geodes[i] = 1
			_reveal(i, true)


## Un golpe cerca de una geoda abierta la revienta.
func check_hit(hit: SpellHit) -> void:
	var reach: float = 2.0 + hit.tier.crack_radius * 0.5 * hit.size
	for i: int in _nodes:
		var g: Geode = _nodes[i]
		if g.active and g.global_position.distance_to(hit.position) <= reach + g.scale.x * 0.4:
			_break(i, hit)
			return


func _reveal(i: int, announce: bool) -> void:
	var g: Dictionary = _crystal.volume.geodes[i]
	var r: float = g["radius"]
	var center: Vector3 = g["center"]
	var node := Geode.new()
	node.name = "Geode%d" % i
	_crystal.add_child(node)
	node.place(_crystal.to_global(center - Vector3(0.0, r * 0.7, 0.0)), Vector3.UP)
	node.scale = Vector3.ONE * r * 1.4
	_nodes[i] = node
	if not announce:
		return
	_crystal.play_accent(OPEN_SFX, 1.25, -4.0)
	_crystal.flash(0.3)
	Events.hint.emit(tr("¡UNA GEODA! REVIÉNTALA"), COLOR)


func _break(i: int, hit: SpellHit) -> void:
	var g: Geode = _nodes[i]
	var at: Vector3 = g.global_position
	var n: Vector3 = g.global_basis.y.normalized()
	g.break_open()
	_nodes.erase(i)
	g.queue_free.call_deferred()
	GameState.progression.geodes[i] = 2
	var layer: CrystalLayerDef = GameState.LAYERS[1]
	# Siempre fragmentos grandes (TYPES ya llega a los Pedruscos: no se usa "el mayor").
	_shards.spawn(at + n * 0.5, n, ShardPool.CHUNK, layer.geode_shards, 1.5, 1)
	_hd_fx.play(at, n, hit.tier, true, true)
	_arcs.strike(at, n, 1.6, Color(1.6, 0.5, 2.0))
	_crystal.play_accent(BREAK_SFX, 1.5, -2.0)
	_crystal.flash(0.5)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig:
		(cam as CameraRig).add_trauma(0.3)
	HitStop.trigger(get_tree(), 0.07)
	Events.hint.emit(tr("¡GEODA! +%d FRAGMENTOS GRANDES") % layer.geode_shards, COLOR)
	Events.geode_broken.emit(at)
