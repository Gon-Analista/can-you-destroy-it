extends Node3D
## Escena del prototipo "El golpe": el valle, el Cristal Madre, el mago y el HUD.
## Captura el ratón al hacer clic y lo suelta con Esc.

## Música del valle por capas (tools/music_synth.py): 1 Aprendiz ... 5 Archimago.
const MUSIC_LAYERS: Array[AudioStream] = [
	preload("res://audio/music/music_valley_1_aprendiz.ogg"),
	preload("res://audio/music/music_valley_2_iniciado.ogg"),
	preload("res://audio/music/music_valley_3_hechicero.ogg"),
	preload("res://audio/music/music_valley_4_magus.ogg"),
	preload("res://audio/music/music_valley_5_archimago.ogg"),
]

var _day_night: DayNight
var _hut: ApprenticeHut
var _flock: FamiliarFlock

@onready var _world: SubViewport = $WorldView/WorldViewport
@onready var _sun: DirectionalLight3D = $WorldView/WorldViewport/Sun
@onready var _player: Player = $WorldView/WorldViewport/Player
@onready var _hud: Hud = $HUDLayer/Hud
@onready var _magic: MagicLayer = $MagicView


func _ready() -> void:
	# Todo en su sitio según WorldLayout (y a ras del suelo ondulado).
	_magic.bind(_player.get_camera())
	_place(_world.get_node(^"ManaPylon") as Node3D, WorldLayout.PYLON)
	_place(_world.get_node(^"Sanctum") as Node3D, WorldLayout.SANCTUM)
	(_world.get_node(^"Sanctum") as Node3D).rotation.y = deg_to_rad(WorldLayout.SANCTUM_YAW_DEG)
	# Los familiares y su jaula (aparecen con la primera mejora de Familiar).
	_flock = FamiliarFlock.new()
	_flock.name = "FamiliarFlock"
	_world.add_child(_flock)
	# Se empieza dentro de la casucha, mirando a la puerta: el cristal no se ve hasta abrirla.
	_hut = ApprenticeHut.new()
	_hut.name = "ApprenticeHut"
	_world.add_child(_hut)
	_place(_hut, WorldLayout.HUT)
	_player.global_position = _hut.start_position()
	_player.rotation.y = 0.0
	if not _hut.is_open:
		AudioDirector.muffle_music(true, 0.01)
		_hud.set_intro.call_deferred(true)
		_hut.door_opened.connect(func() -> void: _hud.set_intro(false))
	# El día y la noche mueven el sol, el cielo y el sonido ambiente.
	_day_night = DayNight.new()
	_day_night.name = "DayNight"
	_world.add_child(_day_night)
	var env: Environment = (_world.get_node(^"WorldEnvironment") as WorldEnvironment).environment
	_day_night.setup(_sun, env)
	# El valle cambia con los hitos del Pilón (faroles, estandartes; las auroras van en el cielo).
	var milestones := ValleyMilestones.new()
	milestones.name = "ValleyMilestones"
	_world.add_child(milestones)
	_hud.bind(_player.get_camera(), _player.get_caster())
	# Hasta que exista el sistema de rangos, se empieza en Aprendiz (1 capa).
	AudioDirector.play_music(MUSIC_LAYERS, _arg_int("--music-layers=", 1))
	GameState.emit_all()
	# La música crece con el mago: una capa más cada 3 niveles comprados (Aprendiz -> Archimago).
	AudioDirector.set_music_layers(_rank_layers(), 0.1)
	Events.upgrade_bought.connect(
		func(_id: StringName, _l: int) -> void: AudioDirector.set_music_layers(_rank_layers())
	)
	if OS.is_debug_build():
		_setup_autoplay()
	# La música del título suena ya durante la pantalla de carga.
	if _shows_title():
		AudioDirector.play_theme(GameMenu.TITLE_MUSIC)
	_warm_up()


## Modo demo para grabar capturas sin ratón (sólo debug):
## godot --path game -- --autoplay [--tier=N] [--yaw=grados] [--pitch=grados] [--combo]
## --delay=s espera antes de empezar. --no-cast no lanza; --mana=N, --bag=N y --warp=x,z
## preparan la partida; --grimoire abre el Grimorio (y --buy inscribe y lo cierra).
## Con --combo junta las manos, carga la Bola de Fuego `--hold=s` segundos y la suelta.
## En modo demo no se carga ni se guarda la partida (ver SaveSystem).
func _setup_autoplay() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--autoplay"):
		return
	# La demo no hace el tutorial (salvo --tutorial).
	if not args.has("--tutorial"):
		_hud.tutorial.skip()
	# La demo empieza ya fuera, delante de la casucha y con la puerta abierta (salvo --hut).
	if not args.has("--hut"):
		_hut.set_open()
		_player.global_position = WorldLayout.HUT + Vector3(0.0, 0.2, -5.0)
	var tier: int = -1
	for a: String in args:
		if a.begins_with("--tier="):
			tier = int(a.get_slice("=", 1)) - 1
		elif a.begins_with("--yaw="):
			_player.rotation.y = deg_to_rad(float(a.get_slice("=", 1)))
		elif a.begins_with("--pitch="):
			(_player.get_node(^"Head") as Node3D).rotation.x = deg_to_rad(
				float(a.get_slice("=", 1))
			)
	if tier > 0:
		_player.get_caster().set_tier(tier)
	_hud.force_captured_look = true
	# Estado de partida para probar el bucle: --mana=N, --bag=N (astillas), --warp=x,z.
	for a: String in args:
		if a.begins_with("--mana="):
			GameState.deliver(int(a.get_slice("=", 1)))
		elif a.begins_with("--bag="):
			for i: int in int(a.get_slice("=", 1)):
				GameState.progression.collect_shard(&"splinter")
			GameState.emit_all()
		elif a.begins_with("--hands="):
			# --hands=0,4: elemento de cada mano (índices de SpellCaster.ELEMENTS: 0 Chispa,
			# 1 Escarcha, 2 Rayo, 3 Tierra, 4 Arcano); despierta la Escarcha y los de las manos.
			GameState.progression.upgrade_levels[&"awaken_frost"] = 1
			var hs: PackedStringArray = a.get_slice("=", 1).split(",")
			var caster: SpellCaster = _player.get_caster()
			for s: int in 2:
				caster.hand_element[s] = int(hs[s])
				var el: ElementDef = SpellCaster.ELEMENTS[int(hs[s])]
				if el.unlock_upgrade != &"":
					GameState.progression.upgrade_levels[el.unlock_upgrade] = 1
			caster.set_tier(caster.tier_index)
		elif a.begins_with("--litter="):
			# --litter=N: N fragmentos sueltos por el suelo alrededor del mago (para la Gravedad).
			_demo_litter.call_deferred(int(a.get_slice("=", 1)))
		elif a.begins_with("--layer="):
			# --layer=N: empieza en esa capa del cristal (1 = Manto Geódico...).
			var crystal: MotherCrystal = _world.get_node(^"MotherCrystal")
			CrystalDemo.tunnel_to_layer(crystal, int(a.get_slice("=", 1)))
		elif a.begins_with("--dig="):
			# --dig=N: N golpes de 30 de daño donde apunta la cámara (cráter sin efectos).
			_demo_dig.call_deferred(int(a.get_slice("=", 1)))
		elif a == "--geode":
			# --geode: túnel hasta la geoda más cercana y el jugador mirándola desde la boca.
			var mc: MotherCrystal = _world.get_node(^"MotherCrystal")
			var spots: Array[Vector3] = CrystalDemo.tunnel_to_geode(mc, _player.global_position)
			var mouth: Vector3 = spots[0]
			_player.global_position = Vector3(mouth.x, maxf(mouth.y - 1.2, 0.2), mouth.z)
			var to_geode: Vector3 = spots[1] - (_player.global_position + Vector3.UP * 1.6)
			_player.rotation.y = atan2(-to_geode.x, -to_geode.z)
			(_player.get_node(^"Head") as Node3D).rotation.x = atan2(
				to_geode.y, Vector2(to_geode.x, to_geode.z).length()
			)
		elif a.begins_with("--vein="):
			# --vein=N: túnel hasta la Vena Resonante N (0 Chispa, 1 Escarcha, 2 Rayo, 3 Tierra,
			# 4 Arcano), el jugador en la boca mirando al fondo y las manos con ese elemento.
			_demo_vein(int(a.get_slice("=", 1)))
		elif a.begins_with("--open-door="):
			# --open-door=s (con --hut): abre la puerta a los s segundos.
			get_tree().create_timer(float(a.get_slice("=", 1))).timeout.connect(_hut.open_door)
		elif a.begins_with("--up="):
			# --up=id:nivel,id:nivel: mejoras ya compradas (p. ej. double_jump:1,levitation:3).
			for pair: String in a.get_slice("=", 1).split(","):
				GameState.progression.upgrade_levels[StringName(pair.get_slice(":", 0))] = int(
					pair.get_slice(":", 1)
				)
			Events.upgrade_bought.emit(&"", 0)
		elif a.begins_with("--fly="):
			# --fly=s: a los s segundos salta, hace el doble salto y mantiene Espacio para levitar.
			var t0: float = float(a.get_slice("=", 1))
			var tree: SceneTree = get_tree()
			tree.create_timer(t0).timeout.connect(func() -> void: Input.action_press(&"jump"))
			tree.create_timer(t0 + 0.15).timeout.connect(
				func() -> void: Input.action_release(&"jump")
			)
			tree.create_timer(t0 + 0.55).timeout.connect(
				func() -> void: Input.action_press(&"jump")
			)
			tree.create_timer(t0 + 5.5).timeout.connect(
				func() -> void: Input.action_release(&"jump")
			)
		elif a.begins_with("--spell-level="):
			# --spell-level=N: todos los hechizos a nivel N (1..10), con sus efectos.
			_player.get_caster().set_debug_level(int(a.get_slice("=", 1)))
		elif a.begins_with("--discover="):
			# --discover=fireball,meteor: combinaciones ya descubiertas (Libro de Combinaciones).
			for id: String in a.get_slice("=", 1).split(","):
				GameState.progression.discover_recipe(StringName(id))
		elif a == "--book":
			get_tree().create_timer(0.8).timeout.connect(
				func() -> void: (_hud.get_node(^"SpellBook") as SpellBook).open()
			)
		elif a.begins_with("--scatter="):
			# --scatter=N: N fragmentos sueltos por el suelo delante del cristal (familiares).
			_demo_scatter.call_deferred(int(a.get_slice("=", 1)))
		elif a.begins_with("--summon="):
			# --summon=s: a los s segundos se compra un Familiar más (jaula, sonido y aviso).
			get_tree().create_timer(float(a.get_slice("=", 1))).timeout.connect(
				func() -> void:
					var lv: int = GameState.progression.get_level(&"familiar") + 1
					GameState.progression.upgrade_levels[&"familiar"] = lv
					Events.upgrade_bought.emit(&"familiar", lv)
			)
		elif a.begins_with("--pylon="):
			# --pylon=0.6: el Pilón ya lleno a ese punto (hitos del valle incluidos, sin fiesta).
			_demo_pylon(float(a.get_slice("=", 1)))
		elif a.begins_with("--pylon-bolt="):
			# --pylon-bolt=s: a los s segundos el Pilón dispara su rayo (y luego cada 3 s).
			var pylon: ManaPylon = _world.get_node(^"ManaPylon")
			var t0: float = float(a.get_slice("=", 1))
			for k: int in 4:
				get_tree().create_timer(t0 + 3.0 * k).timeout.connect(pylon.resonance().fire)
		elif a.begins_with("--milestone="):
			# --milestone=s: a los s segundos se entrega justo lo que falta para la siguiente marca.
			get_tree().create_timer(float(a.get_slice("=", 1))).timeout.connect(_demo_next_mark)
		elif a.begins_with("--time="):
			_day_night.time_of_day = float(a.get_slice("=", 1))
		elif a.begins_with("--warp="):
			var xz: PackedStringArray = a.get_slice("=", 1).split(",")
			_player.global_position = Vector3(float(xz[0]), 0.2, float(xz[1]))
	if args.has("--grimoire"):
		get_tree().create_timer(0.6).timeout.connect(
			func() -> void: Events.grimoire_requested.emit(true)
		)
		# --page=N abre esa constelación, --select=N elige estrella, --buy inscribe y cierra.
		var book: Grimoire = _hud.get_node(^"Grimoire")
		for a: String in args:
			if a.begins_with("--page="):
				var pg: int = int(a.get_slice("=", 1))
				get_tree().create_timer(0.9).timeout.connect(book.open_page.bind(pg))
			if a.begins_with("--select="):
				var idx: int = int(a.get_slice("=", 1))
				get_tree().create_timer(0.9).timeout.connect(book.select.bind(idx))
		if args.has("--buy"):
			get_tree().create_timer(1.6).timeout.connect(book.try_buy)
			get_tree().create_timer(3.4).timeout.connect(book.close)
	for a: String in args:
		if a.begins_with("--feed="):
			# --feed=s: mantiene F junto a la trituradora s segundos y luego tira de la palanca.
			CrystalCrusher.demo_input = true
			var secs: float = float(a.get_slice("=", 1))
			get_tree().create_timer(3.0).timeout.connect(
				func() -> void: Input.action_press(&"interact")
			)
			get_tree().create_timer(3.0 + secs).timeout.connect(
				func() -> void: Input.action_release(&"interact")
			)
			get_tree().create_timer(4.6 + secs).timeout.connect(
				func() -> void:
					Input.action_press(&"interact")
					await get_tree().process_frame
					await get_tree().process_frame
					Input.action_release(&"interact")
			)
	if args.has("--no-cast"):
		return
	var timer := Timer.new()
	timer.wait_time = 0.05
	# --delay=s: unos segundos quieto antes de empezar (para ver las manos en reposo).
	var delay: float = 0.0
	for a: String in args:
		if a.begins_with("--delay="):
			delay = float(a.get_slice("=", 1))
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(timer.start)
	else:
		timer.autostart = true
	var side: Array[int] = [0]
	if args.has("--combo"):
		var hold: float = 0.9
		for a: String in args:
			if a.begins_with("--hold="):
				hold = float(a.get_slice("=", 1))
		var held: Array[float] = [0.0]
		timer.timeout.connect(
			func() -> void:
				var caster: SpellCaster = _player.get_caster()
				if caster.is_combining():
					held[0] += timer.wait_time
					if held[0] >= hold:
						caster.try_release_combine()
				elif caster.try_begin_combine():
					held[0] = 0.0
		)
	else:
		timer.timeout.connect(
			func() -> void:
				_player.get_caster().try_cast(side[0])
				side[0] = 1 - side[0]
		)
	add_child(timer)
	if args.has("--collect"):
		# Tras unos golpes: camina hacia el cristal y mantiene F para recoger.
		var t1: SceneTreeTimer = get_tree().create_timer(3.0)
		t1.timeout.connect(
			func() -> void:
				timer.stop()
				Input.action_press(&"move_forward")
		)
		var t2: SceneTreeTimer = get_tree().create_timer(5.2)
		t2.timeout.connect(
			func() -> void:
				Input.action_release(&"move_forward")
				Input.action_press(&"interact")
		)
	if args.has("--report"):
		get_tree().create_timer(4.0, true, false, true).timeout.connect(_print_report)


## Demo: `count` fragmentos repartidos por el suelo entre 6 y 30 m del mago (delante y a los
## lados), de los tres tamaños, que caen y se quedan quietos.
func _demo_litter(count: int) -> void:
	var pool: ShardPool = get_tree().get_first_node_in_group(&"shard_pool") as ShardPool
	if pool == null:
		return
	var base: Vector3 = _player.global_position
	var yaw: float = _player.rotation.y
	for i: int in count:
		var a: float = yaw + randf_range(-2.0, 2.0)
		var d: float = randf_range(6.0, 30.0)
		var at: Vector3 = base + Vector3(-sin(a), 0.0, -cos(a)) * d + Vector3.UP * 3.0
		pool.spawn(at, Vector3.UP, ShardPool.TYPES[i % ShardPool.TYPES.size()], 1, 0.3)


func _print_report() -> void:
	var shards: int = 0
	for body: Node in get_tree().get_nodes_in_group(&"shards"):
		if not (body as RigidBody3D).freeze:
			shards += 1
	print(
		(
			(
				"REPORT draw_calls=%d objects=%d primitives=%d physics_active=%d"
				+ " shards_moving=%d time_scale=%.2f"
			)
			% [
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
				shards,
				Engine.time_scale,
			]
		)
	)


func _process(_delta: float) -> void:
	# Red de seguridad: el tiempo nunca se queda ralentizado fuera de un hit-stop.
	if Engine.time_scale != 1.0 and not HitStop.is_active():
		Engine.time_scale = 1.0


## Clic para capturar el ratón. En `_input` (no en `_unhandled_input`): el clic lo consume
## la vista del valle al pasárselo a su SubViewport.
func _input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.is_pressed()
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		and not (_hud.get_node(^"Grimoire") as Grimoire).is_open
		and not _hud.menu.is_open()
	):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if (
		OS.is_debug_build()
		and event is InputEventKey
		and (event as InputEventKey).pressed
		and not (event as InputEventKey).echo
		and (event as InputEventKey).keycode == KEY_M
	):
		# Debug: M sube una capa de música (1 -> 5 -> 1) para oír cómo crece con el rango.
		AudioDirector.set_music_layers(AudioDirector.get_music_layers() % MUSIC_LAYERS.size() + 1)


## Pantalla de carga que evita los tirones: la primera vez que se dibuja un shader o un sistema
## de partículas, el motor lo compila y el juego se congela un instante (al primer golpe, la
## primera entrega...). Por detrás de la pantalla de carga, la cámara mira al cristal, al
## Pilón y al Santuario y dispara una vez cada efecto, sin tocar la partida.
func _warm_up() -> void:
	var cover := LoadingCover.new()
	cover.name = "LoadingCover"
	_hud.add_child(cover)
	var cam: Camera3D = _player.get_camera()
	var saved: Transform3D = cam.transform
	var crystal: MotherCrystal = _world.get_node(^"MotherCrystal")
	var pylon: ManaPylon = _world.get_node(^"ManaPylon")
	var sanctum: Sanctum = _world.get_node(^"Sanctum")
	var caster: SpellCaster = _player.get_caster()
	var hands: WizardHands = _player.get_node(^"Hands")
	await get_tree().process_frame
	# 1) El cristal: impactos, fuego, fragmentos y todos los hechizos en vuelo y en la mano.
	var front := Vector3(0.0, 4.0, WorldLayout.CRYSTAL_FOOTPRINT * 0.8)
	var surf: Dictionary = crystal.surface_toward(Vector3(0.0, 4.0, WorldLayout.PLAYER_START.z))
	if not surf.is_empty():
		front = surf["position"]
	_aim(cam, front)
	var defs: Array[SpellVisualDef] = [caster.current_recipe().visual]
	for t: SpellTier in SpellCaster.ELEMENT.tiers:
		if not defs.has(t.visual):
			defs.append(t.visual)
	hands.warm_up(defs)
	caster.warm_up(front)
	var tiers: Array[SpellTier] = SpellCaster.ELEMENT.tiers
	crystal.warm_up(front, Vector3.BACK, tiers[tiers.size() - 1], caster.current_recipe().tier)
	await _frames(24)
	_aim(cam, front)
	await _frames(12)
	# 2) El Pilón: fragmentos que vuelan a la boca y la salpicadura.
	_aim(cam, pylon.mouth_position())
	pylon.warm_up()
	await _frames(24)
	_flock.warm_up(pylon.mouth_position() + Vector3(1.5, 1.0, 0.0))
	await _frames(12)
	# 3) El Santuario: el destello de objeto nuevo.
	_aim(cam, sanctum.marker_position())
	sanctum.warm_up()
	await _frames(10)
	cam.transform = saved
	await _frames(2)
	if _shows_title():
		_hud.menu.show_title()
	GameMenu.skip_title_once = false
	cover.finish()


## El título sólo sale en el juego de verdad (no en el modo demo ni en los tests) y no al volver
## de "Nueva partida".
func _shows_title() -> bool:
	return (
		get_tree().current_scene == self
		and not OS.get_cmdline_user_args().has("--autoplay")
		and not GameMenu.skip_title_once
	)


func _aim(cam: Camera3D, target: Vector3) -> void:
	var from: Vector3 = cam.global_position
	if from.distance_to(target) > 0.1:
		cam.global_basis = Basis.looking_at(target - from, Vector3.UP)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _place(node: Node3D, at: Vector3) -> void:
	node.position = Vector3(at.x, Valley.ground_height(at.x, at.z) - 0.05, at.z)


func _rank_layers() -> int:
	return maxi(_arg_int("--music-layers=", 1), 1 + GameState.total_upgrade_levels() / 3)


func _demo_dig(hits: int) -> void:
	await get_tree().physics_frame
	var crystal: MotherCrystal = _world.get_node(^"MotherCrystal")
	var cam: Camera3D = _player.get_viewport().get_camera_3d()
	for i: int in hits:
		var space: PhysicsDirectSpaceState3D = crystal.get_world_3d().direct_space_state
		var from: Vector3 = cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * 200.0, 1 << 1)
		var r: Dictionary = space.intersect_ray(q)
		if r.is_empty():
			return
		var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.8
		crystal.call("_dig", r["position"] + jitter, r["normal"], 30.0, false)
		for k: int in 3:
			await get_tree().physics_frame


## Demo: `n` fragmentos que caen por el suelo del claro, delante del cristal.
func _demo_scatter(n: int) -> void:
	await get_tree().physics_frame
	var pool: ShardPool = get_tree().get_first_node_in_group(&"shard_pool")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i: int in n:
		var p := Vector3(rng.randf_range(-32.0, -16.0), 0.0, rng.randf_range(44.0, 58.0))
		p.y = Valley.ground_height(p.x, p.z) + 0.6
		pool.spawn(p, Vector3.UP, ShardPool.TYPES[i % 2], 1, 0.25)


func _demo_vein(sector: int) -> void:
	var mc: MotherCrystal = _world.get_node(^"MotherCrystal")
	var spots: Array[Vector3] = CrystalDemo.tunnel_to_vein(mc, sector)
	var stand: Vector3 = spots[0]
	_player.global_position = Vector3(
		stand.x, Valley.ground_height(stand.x, stand.z) + 0.2, stand.z
	)
	var to_end: Vector3 = spots[2] - (_player.global_position + Vector3.UP * 1.6)
	_player.rotation.y = atan2(-to_end.x, -to_end.z)
	(_player.get_node(^"Head") as Node3D).rotation.x = atan2(
		to_end.y, Vector2(to_end.x, to_end.z).length()
	)
	if OS.get_cmdline_user_args().has("--vein-close"):
		# --vein-close: dentro del túnel, a unos metros del fondo (cuando ya tiene colisión).
		var inside: Vector3 = spots[2] + (spots[1] - spots[2]).normalized() * 7.0
		get_tree().create_timer(1.0).timeout.connect(
			func() -> void: _player.global_position = inside - Vector3.UP * 1.3
		)
	var caster: SpellCaster = _player.get_caster()
	if sector < SpellCaster.ELEMENTS.size():
		for id: StringName in [&"awaken_frost", &"awaken_bolt", &"awaken_earth"]:
			GameState.progression.upgrade_levels[id] = 1
		caster.hand_element[0] = sector
		caster.hand_element[1] = sector
		caster.set_tier(caster.tier_index)


## Demo: pone el Pilón a `ratio` sin celebrar los hitos (el valle ya cambiado).
func _demo_pylon(ratio: float) -> void:
	var prog: Progression = GameState.progression
	prog.pylon_progress = roundi(clampf(ratio, 0.0, 1.0) * float(prog.total_essence))
	GameState.emit_all()
	for node: Node in get_tree().get_nodes_in_group(&"valley_milestones"):
		(node as ValleyMilestones).refresh()


func _demo_next_mark() -> void:
	var prog: Progression = GameState.progression
	for m: float in ManaPylon.MARKS:
		var need: int = ceili(m * float(prog.total_essence)) - prog.pylon_progress
		if need > 0:
			GameState.deliver(need)
			return


func _arg_int(prefix: String, fallback: int) -> int:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return int(a.trim_prefix(prefix))
	return fallback
