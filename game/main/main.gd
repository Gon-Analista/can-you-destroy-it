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
	_player.global_position = WorldLayout.PLAYER_START
	# El día y la noche mueven el sol, el cielo y el sonido ambiente.
	_day_night = DayNight.new()
	_day_night.name = "DayNight"
	_world.add_child(_day_night)
	var env: Environment = (_world.get_node(^"WorldEnvironment") as WorldEnvironment).environment
	_day_night.setup(_sun, env)
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
			# --hands=0,1: elemento de cada mano (0 Chispa, 1 Escarcha); despierta la Escarcha.
			GameState.progression.upgrade_levels[&"awaken_frost"] = 1
			var hs: PackedStringArray = a.get_slice("=", 1).split(",")
			var caster: SpellCaster = _player.get_caster()
			caster.hand_element[0] = int(hs[0])
			caster.hand_element[1] = int(hs[1])
			caster.set_tier(caster.tier_index)
		elif a.begins_with("--layer="):
			# --layer=N: empieza en esa capa del cristal (1 = Manto Geódico...).
			var crystal: MotherCrystal = _world.get_node(^"MotherCrystal")
			crystal.jump_to_layer(int(a.get_slice("=", 1)))
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
	var front := Vector3(0.0, 4.0, WorldLayout.CRYSTAL_FOOTPRINT * 0.55)
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
	# 3) El Santuario: el destello de objeto nuevo.
	_aim(cam, sanctum.marker_position())
	sanctum.warm_up()
	await _frames(10)
	cam.transform = saved
	await _frames(2)
	if get_tree().current_scene == self and not OS.get_cmdline_user_args().has("--autoplay"):
		_hud.menu.show_title()
	cover.finish()


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


func _arg_int(prefix: String, fallback: int) -> int:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return int(a.trim_prefix(prefix))
	return fallback
