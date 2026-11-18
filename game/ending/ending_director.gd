class_name EndingDirector
extends Node
## El final de la partida (GDD 9), de principio a fin. Lo crea Main.
## - Núcleo expuesto (CoreReveal): el valle se oscurece hacia el violeta (`DayNight.tension`) y
##   suena la capa tensa de la música.
## - La Gran Convergencia (GrandConvergence, bajo el SpellCaster): mientras se carga, las manos se
##   llenan de luz (resplandor en pantalla).
## - El impacto: el Núcleo estalla (CoreBlast) con hit-stop, destello blanco y violeta, sacudida y
##   onda de choque; lo que quedaba del cristal llueve en fragmentos brillantes. El Pilón llega al
##   100 % (los hitos del Pilón celebran: columna, coro, banderas), sube la columna de maná que
##   atraviesa las nubes, el cielo se llena de auroras y la aldea celebra (ValleyCelebration).
## - La pantalla final (EndingScreen) y la partida terminada guardada: al volver a cargar, el valle
##   sigue de fiesta y sin cristal.

const TENSION_MUSIC: AudioStream = preload("res://audio/music/mus_core_tension_loop.ogg")
const EXPLOSION_SFX: AudioStream = preload("res://audio/sfx/sfx_core_explosion_01.ogg")
const C_FLASH := Color(1.0, 0.93, 1.0)
const C_GLOW := Color(0.95, 0.8, 1.0)

var _main: Main
var _world: SubViewport
var _player: Player
var _hud: Hud
var _day_night: DayNight
var _crystal: MotherCrystal
var _reveal: CoreReveal
var _pylon: ManaPylon
var _convergence: GrandConvergence
var _celebration: ValleyCelebration
var _blast: CoreBlast
var _screen: EndingScreen
var _flash: ColorRect
var _glow: TextureRect
var _flash_k: float = 0.0
var _glow_k: float = 0.0
var _tension_tween: Tween
var _finale_tween: Tween
## Partida terminada cargada sin haber visto la pantalla final: sale al cerrar el título.
var _screen_pending: bool = false
## Segundos que la mirada se va sola (suave) hacia la columna de maná si no se ve (ver
## _look_at_column); el ratón sigue mandando encima.
var _look_t: float = 0.0


func setup(main: Main, world: SubViewport, player: Player, hud: Hud, day_night: DayNight) -> void:
	_main = main
	_world = world
	_player = player
	_hud = hud
	_day_night = day_night


func _ready() -> void:
	add_to_group(&"ending_director")
	_crystal = _world.get_node(^"MotherCrystal") as MotherCrystal
	_reveal = _crystal.get_node(^"CoreReveal") as CoreReveal
	_pylon = _world.get_node(^"ManaPylon") as ManaPylon
	var caster: SpellCaster = _player.get_caster()
	_convergence = GrandConvergence.new()
	_convergence.name = "GrandConvergence"
	_convergence.camera = caster.camera
	_convergence.hands = caster.hands
	_convergence.reveal = _reveal
	caster.add_child(_convergence)
	_convergence.struck.connect(_on_struck)
	_celebration = ValleyCelebration.new()
	_celebration.name = "ValleyCelebration"
	_world.add_child(_celebration)
	var env: Environment = (_world.get_node(^"WorldEnvironment") as WorldEnvironment).environment
	_celebration.setup(
		_pylon.crown_position() + Vector3.UP * 0.5, env.sky.sky_material as ShaderMaterial
	)
	_blast = CoreBlast.new()
	_blast.name = "CoreBlast"
	_world.add_child(_blast)
	_build_overlay()
	Events.grimoire_final_revealed.connect(func() -> void: _set_tension(1.0, 3.0))
	Events.menu_closed.connect(_on_menu_closed)
	var prog: Progression = GameState.progression
	if prog.game_complete:
		_restore_complete()
	elif GameState.core_exposed:
		_day_night.tension = 1.0
		if OS.get_cmdline_user_args().has("--autoplay"):
			AudioDirector.play_theme(TENSION_MUSIC, -7.0)


## La Gran Convergencia (para tests y depuración).
func convergence() -> GrandConvergence:
	return _convergence


func screen() -> EndingScreen:
	return _screen


## Depuración y demo: el cristal al 99 % (el Núcleo se expone con su momento) y el mago delante.
func debug_core() -> void:
	var prog: Progression = GameState.progression
	if prog.game_complete:
		return
	if not GameState.core_exposed:
		# Como al final de verdad: sólo queda una costra alrededor del Núcleo; luego el 99 %.
		_reveal.debug_trim(
			15.0,
			func() -> void:
				GameState.hit_crystal(prog.essence - GameState.core_floor, _reveal.core_position())
		)
	var core: Vector3 = _reveal.core_position()
	var stand := Vector3(core.x + 4.0, 0.0, core.z + 30.0)
	stand.y = Valley.ground_height(stand.x, stand.z) + 0.2
	_main.debug_teleport(stand, core)


## Depuración y demo: inscribe la Gran Convergencia (si hace falta) y la lanza sola.
func debug_convergence() -> void:
	if GameState.progression.game_complete:
		return
	if not GameState.core_exposed:
		debug_core()
	if not GameState.has_upgrade(GameState.GRAND_CONVERGENCE):
		GameState.progression.upgrade_levels[GameState.GRAND_CONVERGENCE] = 1
		Events.upgrade_bought.emit(GameState.GRAND_CONVERGENCE, 1)
		Events.grand_convergence_unlocked.emit()
	_convergence.auto_cast()


## Demo (`--complete`): la partida ya terminada (como al volver a cargarla), sin la escena.
func demo_complete() -> void:
	if not GameState.progression.game_complete:
		_complete_state()
		GameState.progression.ending_seen = true
		_reveal.vanish()
		_restore_complete()


## Pantalla de carga: compila los efectos del estallido (sin verse).
func warm_up(at: Vector3) -> void:
	_blast.warm_up(at)


func _build_overlay() -> void:
	_glow = TextureRect.new()
	_glow.name = "ConvergenceGlow"
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(C_GLOW, 1.0), Color(C_GLOW, 0.35), Color(C_GLOW, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 1.0)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 160
	tex.height = 90
	_glow.texture = tex
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.modulate.a = 0.0
	_glow.visible = false
	_flash = ColorRect.new()
	_flash.name = "EndingFlash"
	_flash.color = C_FLASH
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.visible = false
	_screen = EndingScreen.new()
	_screen.name = "EndingScreen"
	_screen.continue_requested.connect(_on_continue)
	_screen.new_game_requested.connect(_on_new_game)
	# Por debajo del Grimorio y los menús (la pausa sigue encima de todo).
	var at: int = _hud.get_node(^"Grimoire").get_index()
	_hud.add_child(_glow)
	_hud.move_child(_glow, at)
	_hud.add_child(_flash)
	_hud.move_child(_flash, at + 1)
	_hud.add_child(_screen)
	_hud.move_child(_screen, _hud.menu.get_index())


func _process(delta: float) -> void:
	# Las manos se llenan de luz mientras se carga (más en cada etapa).
	var k: float = _convergence.charge_ratio()
	_glow_k = move_toward(_glow_k, k, delta * 3.0)
	_glow.visible = _glow_k > 0.005
	_glow.modulate.a = _glow_k * _glow_k * 0.4 * HdFx.flash_scale
	if _flash_k > 0.0:
		_flash_k = maxf(0.0, _flash_k - delta / 1.1)
		_flash.visible = _flash_k > 0.0
		_flash.color.a = pow(_flash_k, 2.2) * 0.6 * HdFx.flash_scale
	if _look_t > 0.0:
		_look_t -= delta
		_steer_view(delta)


## ¡El Núcleo estalla! El momento grande y, en cadena, la fiesta y la pantalla final.
func _on_struck(_at: Vector3) -> void:
	if GameState.progression.game_complete:
		return
	var core: Vector3 = _reveal.core_position()
	_reveal.vanish()
	_blast.play(core)
	HitStop.trigger(get_tree(), 0.32, 0.03)
	_flash_k = 1.0
	_flash.visible = true
	var cam: Camera3D = _player.get_camera()
	if cam is CameraRig:
		(cam as CameraRig).add_trauma(1.0)
		(cam as CameraRig).punch_fov(-14.0)
	AudioDirector.play_sfx(EXPLOSION_SFX, 2.0)
	AudioDirector.fade_theme(-60.0, 0.2)
	# Los bichos salen corriendo (luego bailan con la fiesta).
	var herd: CritterHerd = CritterHerd.instance()
	if herd:
		for c: Critter in herd.critters():
			if c.is_alive():
				c.startle(core)
	_complete_state()
	var tree: SceneTree = get_tree()
	tree.create_timer(1.2, false).timeout.connect(_pylon_full)
	tree.create_timer(1.6, false).timeout.connect(_celebration.raise_column)
	tree.create_timer(1.9, false).timeout.connect(_look_at_column)
	tree.create_timer(2.2, false).timeout.connect(
		func() -> void:
			_set_tension(0.0, 3.0)
			_set_finale(1.0, 5.0)
	)
	tree.create_timer(3.0, false).timeout.connect(
		func() -> void:
			_celebration.start()
			AudioDirector.stop_theme(4.0)
			AudioDirector.set_music_layers(5, 3.0)
	)
	tree.create_timer(GameState.BALANCE.ending_screen_delay_sec, false).timeout.connect(
		show_final_screen
	)


## Hacia dónde mirar para ver la columna de maná subir (su pie y el cielo).
func _column_view_point() -> Vector3:
	return _pylon.crown_position() + Vector3.UP * 38.0


## La columna sale del Pilón, que suele quedar a un lado o detrás del Núcleo: si no se ve, la
## mirada gira sola y despacio hacia ella un par de segundos (el gran momento no se pierde).
func _look_at_column() -> void:
	var cam: Camera3D = _player.get_camera()
	var to: Vector3 = (_column_view_point() - cam.global_position).normalized()
	if (-cam.global_basis.z).dot(to) < 0.85:
		_look_t = 2.2


func _steer_view(delta: float) -> void:
	var cam: Camera3D = _player.get_camera()
	var head: Node3D = cam.get_parent() as Node3D
	var to: Vector3 = _column_view_point() - cam.global_position
	var yaw: float = atan2(-to.x, -to.z)
	var pitch: float = atan2(to.y, Vector2(to.x, to.z).length())
	# Arranca y acaba suave; el ratón del jugador sigue sumando encima.
	var w: float = sin(clampf(_look_t / 2.2, 0.0, 1.0) * PI)
	var k: float = 1.0 - exp(-delta * 3.2 * w)
	_player.rotation.y = lerp_angle(_player.rotation.y, yaw, k)
	if head:
		head.rotation.x = lerpf(head.rotation.x, clampf(pitch, -1.2, 1.2), k)


## La pantalla final, sin las manos delante (vuelven al seguir en el valle).
func show_final_screen() -> void:
	var hands: WizardHands = _player.get_caster().hands
	hands.visible = false
	hands.orb_enabled = false
	_screen.open()


## La partida queda terminada: el cristal a cero, guardado.
func _complete_state() -> void:
	var prog: Progression = GameState.progression
	prog.essence = 0
	prog.game_complete = true
	Events.essence_changed.emit(0, prog.total_essence)
	Events.crystal_destroyed.emit()
	Events.game_completed.emit()
	_suppress_guide()
	SaveSystem.save_game()


## El Pilón se llena del todo: sus hitos hacen la fiesta (columna, coro, banderas y faroles).
func _pylon_full() -> void:
	var prog: Progression = GameState.progression
	prog.pylon_progress = prog.total_essence
	Events.pylon_changed.emit(prog.pylon_progress, 1.0)
	for node: Node in get_tree().get_nodes_in_group(&"valley_milestones"):
		(node as ValleyMilestones).refresh()
	Events.pylon_milestone.emit(ManaPylon.MARKS.size() - 1, 1.0)
	_pylon.pulse(4.0)
	SaveSystem.save_game()


## Partida cargada ya terminada: sin cristal, columna, auroras y fiesta.
func _restore_complete() -> void:
	var prog: Progression = GameState.progression
	prog.pylon_progress = prog.total_essence
	GameState.emit_all()
	_day_night.finale = 1.0
	_day_night.tension = 0.0
	_celebration.raise_column(true)
	_celebration.start(true)
	AudioDirector.set_music_layers(5, 0.1)
	_suppress_guide.call_deferred()
	if not prog.ending_seen:
		# Se salió durante la fiesta: la pantalla final, en cuanto se cierre el título (o enseguida
		# si no hay título).
		_screen_pending = true
		get_tree().create_timer(1.0, false).timeout.connect(_show_pending)


func _suppress_guide() -> void:
	for n: Node in _hud.find_children("*", "ObjectiveGuide", true, false):
		(n as ObjectiveGuide).suppressed = true


## Al cerrar el título o la pausa con el Núcleo expuesto vuelve la capa tensa (el título trae su
## propia música).
func _on_menu_closed() -> void:
	var prog: Progression = GameState.progression
	if _screen_pending:
		get_tree().create_timer(1.5, false).timeout.connect(_show_pending)
		return
	if GameState.core_exposed and not prog.game_complete and not _screen.is_open():
		if _reveal.state == CoreReveal.State.EXPOSED:
			AudioDirector.play_theme(TENSION_MUSIC, -7.0)


func _show_pending() -> void:
	if _screen_pending and not _hud.menu.is_open() and not _screen.is_open():
		_screen_pending = false
		show_final_screen()


func _on_continue() -> void:
	var hands: WizardHands = _player.get_caster().hands
	hands.visible = true
	hands.orb_enabled = true
	Events.hint.emit(tr("EL VALLE ES TUYO"), Color("#ffd27a"))


func _on_new_game() -> void:
	_hud.menu.new_game()


func _set_tension(v: float, sec: float) -> void:
	if _tension_tween:
		_tension_tween.kill()
	_tension_tween = create_tween()
	_tension_tween.tween_property(_day_night, "tension", v, sec)


func _set_finale(v: float, sec: float) -> void:
	if _finale_tween:
		_finale_tween.kill()
	_finale_tween = create_tween()
	_finale_tween.tween_property(_day_night, "finale", v, sec)
