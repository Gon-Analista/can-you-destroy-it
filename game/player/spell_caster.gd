class_name SpellCaster
extends Node
## Lanza los hechizos de las dos manos (GDD 5.2 y 10.1). Cada mano lleva un elemento (Q / E lo
## cambian) y su propio enfriamiento: clic izquierdo lanza la izquierda, clic derecho la
## derecha. Pulsar los dos a la vez junta las manos y funde los dos elementos en un hechizo
## combinado si la pareja tiene receta (Chispa + Chispa = Bola de Fuego, Chispa + Escarcha =
## Choque Térmico), que se carga mientras se mantiene y sale al soltar. Desde el nivel 2 la
## carga va por etapas, un círculo mágico por etapa con su golpe (ChargeStages, ChargeFeedback).
##
## Con el báculo (StaffCombos) la gema lleva un tercer elemento (R o la rueda lo cambian): si
## las dos manos y la gema forman una receta triple, al juntar las manos sale la triple.
##
## Para no perder la combinación, un clic con las dos manos listas espera `combine_window_sec`
## por si llega el otro; si se suelta antes, sale en el acto. Enfriamiento con "buffer" (si
## pulsas un poco antes de tiempo, sale en cuanto se pueda), golpe resonante y pools. Cómo llega
## cada hechizo al cristal está en SpellDelivery.

const ELEMENT: ElementDef = preload("res://data/elements/spark.tres")
const RECIPE: SpellRecipe = preload("res://data/spells/recipe_fireball.tres")
## Elementos que puede llevar una mano, en el orden en que se recorren con Q / E.
const ELEMENTS: Array[ElementDef] = [
	ELEMENT,
	preload("res://data/elements/frost.tres"),
	preload("res://data/elements/bolt.tres"),
	preload("res://data/elements/earth.tres"),
	preload("res://data/elements/arcane.tres"),
	preload("res://data/elements/wind.tres"),
]
## Todas las combinaciones (una por pareja de elementos) y las reacciones (no se lanzan; se
## descubren en el cristal). El Libro de Combinaciones las enseña en este orden.
const RECIPES: Array[SpellRecipe] = [
	RECIPE,
	preload("res://data/spells/recipe_thermal_shock.tres"),
	preload("res://data/spells/recipe_ice_lance.tres"),
	preload("res://data/spells/recipe_thunder.tres"),
	preload("res://data/spells/recipe_meteor.tres"),
	preload("res://data/spells/recipe_stalactites.tres"),
	preload("res://data/spells/recipe_plasma.tres"),
	preload("res://data/spells/recipe_charged_lance.tres"),
	preload("res://data/spells/recipe_earthquake.tres"),
	preload("res://data/spells/recipe_magnetism.tres"),
	preload("res://data/spells/recipe_echo_fire.tres"),
	preload("res://data/spells/recipe_echo_ice.tres"),
	preload("res://data/spells/recipe_echo_thunder.tres"),
	preload("res://data/spells/recipe_gravity.tres"),
	preload("res://data/spells/recipe_resonance.tres"),
	preload("res://data/spells/recipe_tornado.tres"),
	preload("res://data/spells/recipe_firestorm.tres"),
	preload("res://data/spells/recipe_blizzard.tres"),
	preload("res://data/spells/recipe_tempest.tres"),
	preload("res://data/spells/recipe_sandstorm.tres"),
	preload("res://data/spells/recipe_echo_wind.tres"),
	preload("res://data/spells/recipe_steam.tres"),
	preload("res://data/spells/recipe_temper.tres"),
]
const SWITCH_SFX: AudioStream = preload("res://audio/sfx/sfx_spell_combine_01.ogg")
const STAFF_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_staff_cycle_01.ogg"),
	preload("res://audio/sfx/sfx_staff_cycle_02.ogg"),
]
const TRIPLE_SFX: AudioStream = preload("res://audio/sfx/sfx_triple_combine_01.ogg")
const CAST_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_spark_cast_01.ogg"),
	preload("res://audio/sfx/sfx_spark_cast_02.ogg"),
	preload("res://audio/sfx/sfx_spark_cast_03.ogg"),
]
const READY_SFX: AudioStream = preload("res://audio/sfx/sfx_spark_ready_01.ogg")
const FIZZLE_SFX: AudioStream = preload("res://audio/sfx/sfx_spark_fizzle_01.ogg")
## El golpe grave al soltar un combinado (el estruendo del meteorito, más agudo y bajo).
const RELEASE_SFX: AudioStream = preload("res://audio/sfx/sfx_meteor_boom_01.ogg")
## Entregas que salen disparadas de las manos hacia delante: al soltarlas, empujan al mago.
const FORWARD_DELIVERIES: Array[SpellRecipe.Delivery] = [
	SpellRecipe.Delivery.FRONT,
	SpellRecipe.Delivery.LANCE,
	SpellRecipe.Delivery.BEAM,
	SpellRecipe.Delivery.GROUND,
	SpellRecipe.Delivery.NOVA,
	SpellRecipe.Delivery.RESONANCE,
]
## Ecos fantasma del Arcano en vuelo a la vez (disparos sueltos y Ecos de X).
const ECHO_PROJECTILE_POOL: int = 10
const ARCANE_COLOR := Color(1.4, 0.7, 1.9)
const ARCANE_HOT := Color(2.2, 1.8, 2.4)
const RAY_LENGTH: float = 250.0
const ACTIONS: Array[StringName] = [&"cast_left", &"cast_right"]
## Lado que usan las señales y las manos para el hechizo combinado.
const BOTH_HANDS: int = 2
## La rueda del ratón (o un panel táctil, que manda muchos pasos seguidos) cambia la gema como
## mucho una vez cada tanto (ms).
const WHEEL_STEP_MS: int = 140

@export var camera: Camera3D:
	set(value):
		camera = value
		if _delivery:
			_delivery.camera = value
		if _stage_fx:
			_stage_fx.camera = value
		if _auto:
			_auto.camera = value
@export var hands: WizardHands

## Nivel de la Chispa (lo da la Potencia; en debug, las teclas 1-5 lo fuerzan en todos).
var tier_index: int = 0
## Elemento de cada mano (índice en ELEMENTS). [izquierda, derecha]
var hand_element: Array[int] = [0, 0]
## Demo/depuración: fuerza el nivel de los combinados (1..11); -1 = el comprado.
var debug_recipe_level: int = -1
## Depuración (modo dios): las manos recargan al instante.
var debug_no_cooldown: bool = false
## El báculo: elemento de su gema y las recetas triples.
var staff := StaffCombos.new()
var _debug_tier: int = -1
var _active_recipe: SpellRecipe = RECIPE
var _cast_sounds: Dictionary[ElementDef, AudioStreamRandomizer] = {}
var _combo_sounds: Dictionary[SpellRecipe, AudioStreamRandomizer] = {}
var _cooldown: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
## Duración del último enfriamiento de cada mano (para la carga de 0 a 1).
var _cooldown_total: PackedFloat32Array = PackedFloat32Array([1.0, 1.0])
var _was_ready: Array[bool] = [true, true]
var _buffered: Array[bool] = [false, false]
var _buffer_time: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
## Clic que espera por si llega el de la otra mano.
var _pending_side: int = -1
var _pending_time: float = 0.0
var _combining: bool = false
var _combine_time: float = 0.0
var _combine_full_announced: bool = false
## Etapas de la carga actual y su golpe; si la empezó el jugador con los botones (no la demo).
var _stages := ChargeStages.new()
var _stage_fx: ChargeFeedback
var _combine_by_input: bool = false
var _cast_random: AudioStreamRandomizer
var _combo_cast_random: AudioStreamRandomizer
var _charge_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
## Círculos mágicos de los niveles 6 a 10.
var _circles: MagicCircles
## Ecos del Arcano (disparos sueltos y Ecos de X) y cómo llega cada hechizo al cristal.
var _echoes: SpellEchoes
var _delivery: SpellDelivery
## Resonancia Arcana: segundos en los que todo golpe es resonante y hasta poder repetirla.
var _resonance_left: float = 0.0
var _resonance_lock: float = 0.0
var _wheel_at: int = -WHEEL_STEP_MS
## Lanzamiento continuo (nodo hito): mantener un botón lanza esa mano en ráfaga.
var _auto: AutoCast
## El golpe de poder en las manos al soltar un combinado.
var _burst: CastBurst


func _ready() -> void:
	_rng.randomize()
	for el: ElementDef in ELEMENTS:
		el.ensure_levels()
	_circles = MagicCircles.new()
	_circles.name = "MagicCircles"
	add_child(_circles)
	_delivery = SpellDelivery.new()
	_delivery.name = "Delivery"
	add_child(_delivery)
	_delivery.setup(camera, _circles, _aim, _hand_origin)
	var echo_pool: Array[SparkProjectile] = []
	for i: int in ECHO_PROJECTILE_POOL:
		echo_pool.append(_delivery.make_projectile("Echo%d" % i))
		echo_pool[i].prepare_combo(false)  # Los ecos del Eco de Fuego son bolas de fuego.
	_echoes = SpellEchoes.new()
	_echoes.name = "Echoes"
	add_child(_echoes)
	_echoes.setup(
		self,
		_circles,
		echo_pool,
		[_aim, _hand_origin, _delivery.deliver, _delivery.deliver_sky, _resonant_chance]
	)
	_delivery.runes.bind(self, _echoes)
	_cast_random = _randomizer(CAST_SFX, 1.15)
	_combo_cast_random = _randomizer(RECIPE.cast_sfx, 1.08)
	for el: ElementDef in ELEMENTS:
		_cast_sounds[el] = (
			_randomizer(el.cast_sfx, 1.12) if not el.cast_sfx.is_empty() else _cast_random
		)
	for r: SpellRecipe in RECIPES + StaffCombos.TRIPLES:
		if not r.is_reaction:
			_combo_sounds[r] = _randomizer(r.cast_sfx, 1.08)
	_charge_player = AudioStreamPlayer.new()
	_charge_player.name = "ComboChargeLoop"
	_charge_player.bus = &"SFX"
	_charge_player.stream = RECIPE.charge_loop_sfx  # bucle activado en la importación
	add_child(_charge_player)
	_stage_fx = ChargeFeedback.new()
	_stage_fx.name = "ChargeFeedback"
	_stage_fx.camera = camera
	_stage_fx.hands = hands
	add_child(_stage_fx)
	_auto = AutoCast.new()
	_auto.name = "AutoCast"
	_auto.caster = self
	_auto.camera = camera
	_auto.hands = hands
	add_child(_auto)
	_burst = CastBurst.new()
	_burst.name = "CastBurst"
	add_child(_burst)
	# Menú, Grimorio o libro a media carga la deshacen (el botón se suelta fuera del juego).
	Events.menu_opened.connect(_cancel_combine)
	Events.grimoire_opened.connect(_cancel_combine)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _combine_by_input:
		_cancel_combine()


func current_tier() -> SpellTier:
	return tier_for(0)


func current_recipe() -> SpellRecipe:
	return _active_recipe


func element_of(side: int) -> ElementDef:
	return ELEMENTS[hand_element[side]]


## Nivel del hechizo de una mano: según la mejora de Potencia de su elemento.
func tier_for(side: int) -> SpellTier:
	return _element_tier(element_of(side))


func _element_tier(el: ElementDef) -> SpellTier:
	var idx: int = tier_index if el == ELEMENT else roundi(GameState.stat(el.power_stat, 0.0))
	if _debug_tier >= 0:
		idx = _debug_tier
	return el.tiers[clampi(idx, 0, el.tiers.size() - 1)]


## Demo y menú de depuración: todos los hechizos a nivel `level` (1..11) sin comprar nada;
## 0 vuelve a los niveles comprados. Con `celebrate`, las manos lo celebran.
func set_debug_level(level: int, celebrate: bool = false) -> void:
	_debug_tier = level - 1
	debug_recipe_level = level
	_refresh_hands(celebrate)


## Nivel (1..11) del hechizo de una mano.
func level_of(side: int) -> int:
	return element_of(side).tiers.find(tier_for(side)) + 1


## Nivel (1..11) de un combinado: 1 + niveles comprados de su Potencia.
func recipe_level(recipe: SpellRecipe) -> int:
	if debug_recipe_level > 0:
		return debug_recipe_level
	if recipe == null or recipe.power_upgrade == &"":
		return 1
	return 1 + GameState.progression.get_level(recipe.power_upgrade)


## Nivel de un combinado para sus etapas y sus círculos: el de su Potencia si la tiene; si no,
## la media de los niveles de las dos manos.
func charge_level(recipe: SpellRecipe) -> int:
	if debug_recipe_level > 0 or (recipe and recipe.power_upgrade != &""):
		return recipe_level(recipe)
	return int(float(level_of(0) + level_of(1)) * 0.5)


## Etapas de la carga en curso (0 = continua) y cuántas se han completado.
func charge_stages() -> ChargeStages:
	return _stages


## Punto al que se apunta (rayo por el centro de la pantalla), y su colisionador (o un bicho).
func _aim() -> Dictionary:
	var from_cam: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(
		from_cam, from_cam + forward * RAY_LENGTH, 1 | (1 << 1) | Critter.LAYER
	)
	var result: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return {"position": from_cam + forward * 40.0, "normal": -forward, "collider": null}
	return result


## Origen de un hechizo: la palma de la mano `side` (o las dos juntas), donde va su llama.
func _hand_origin(side: int) -> Vector3:
	if hands:
		var depth: float = WizardHands.orb_depth(camera)
		return camera.project_position(hands.palm_screen_position(side), depth)
	return camera.global_position + camera.global_basis * Vector3(0, -0.17, -0.6)


## Receta para los elementos de las manos (el orden no importa), o null. Con el báculo, si las
## manos y la gema forman una triple, la triple.
func recipe_for_hands() -> SpellRecipe:
	var gem: ElementDef = staff.element(ELEMENTS)
	if gem:
		var triple: SpellRecipe = StaffCombos.triple_for(element_of(0).id, element_of(1).id, gem.id)
		# Con la tormenta aún rugiendo, las manos siguen con su pareja (no se pierde el clic).
		var raging: bool = (
			triple
			and triple.delivery == SpellRecipe.Delivery.STORM
			and _delivery.storm().lock_left() > 0.0
		)
		if triple and not raging:
			return triple
	for r: SpellRecipe in RECIPES:
		if r.matches(element_of(0).id, element_of(1).id):
			return r
	return null


func is_unlocked(el: ElementDef) -> bool:
	return el.unlock_upgrade == &"" or GameState.progression.get_level(el.unlock_upgrade) > 0


## Q / E: la mano pasa al siguiente elemento que conozcas. Si sólo conoces uno, avisa.
func cycle_element(side: int) -> void:
	if _combining:
		return
	var n: int = ELEMENTS.size()
	for step: int in range(1, n + 1):
		var idx: int = (hand_element[side] + step) % n
		if idx == hand_element[side]:
			break
		if is_unlocked(ELEMENTS[idx]):
			hand_element[side] = idx
			_refresh_hands(false, side)
			if hands:
				hands.play_switch(side)
			AudioDirector.play_sfx(SWITCH_SFX, -8.0, 1.2 if idx > 0 else 1.0)
			var which: String = tr("MANO IZQUIERDA") if side == 0 else tr("MANO DERECHA")
			Events.hint.emit(
				"%s: %s" % [which, tr(ELEMENTS[idx].display_name).to_upper()], ELEMENTS[idx].color
			)
			return
	Events.hint.emit(
		tr("AÚN NO CONOCES OTRO ELEMENTO: DESPIÉRTALO EN EL GRIMORIO"), Color("#a5dae5")
	)


## R / rueda: la gema del báculo pasa al siguiente elemento despierto (`dir` -1: al anterior).
func _cycle_staff(dir: int) -> void:
	if _combining or not StaffCombos.owned():
		return
	var idx: int = staff.cycle(ELEMENTS, dir)
	if idx < 0:
		Events.hint.emit(tr("LA GEMA NO CONOCE OTRO ELEMENTO"), Color("#ffc46b"))
		return
	var el: ElementDef = ELEMENTS[idx]
	if hands and hands.staff:
		hands.staff.set_element(el, true)
	AudioDirector.play_sfx(STAFF_SFX[idx % STAFF_SFX.size()], -6.0, 0.9 + 0.06 * idx)
	var triple: SpellRecipe = recipe_for_hands()
	var msg: String = "%s: %s" % [tr("BÁCULO"), tr(el.display_name).to_upper()]
	if triple and triple.is_triple():
		msg += "  ·  " + tr("¡LAS MANOS Y LA GEMA RESUENAN!")
	Events.hint.emit(msg, el.color)


## Carga de una mano: 0 = recién lanzada, 1 = lista. Sin `side`, la media de las dos
## (o la carga del hechizo combinado mientras se junta).
func charge_ratio(side: int = -1) -> float:
	if side < 0:
		if _combining:
			return combine_charge()
		return (charge_ratio(0) + charge_ratio(1)) * 0.5
	return 1.0 - clampf(_cooldown[side] / maxf(_cooldown_total[side], 0.001), 0.0, 1.0)


func combine_charge() -> float:
	# Con muchas etapas la carga se alarga un poco (y se descuenta de la recarga; ChargeStages).
	return _stages.charge_at(_combine_time)


func is_combining() -> bool:
	return _combining


## `celebrate`: al subir de nivel comprando, las manos lo celebran (destello y chispas).
func set_tier(index: int, celebrate: bool = false) -> void:
	tier_index = clampi(index, 0, ELEMENT.tiers.size() - 1)
	_refresh_hands(celebrate)


## Pone en cada mano la llama de su elemento y nivel (con `celebrate`, la transformación).
## `only_side` >= 0 cambia sólo esa mano.
func _refresh_hands(celebrate: bool, only_side: int = -1) -> void:
	if hands == null:
		return
	for side: int in 2:
		if only_side >= 0 and side != only_side:
			continue
		hands.set_flame_visual(tier_for(side).visual, celebrate, side)
	if hands.staff and only_side < 0:
		var first: bool = staff.ensure_element(ELEMENTS)
		hands.staff.set_element(staff.element(ELEMENTS), celebrate)
		if first and celebrate:
			Events.hint.emit(
				tr("¡BÁCULO! R O LA RUEDA: ELEMENTO DE LA GEMA · JUNTA LAS MANOS PARA UNA TRIPLE"),
				Color("#ffc46b")
			)


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed(&"cycle_element_left"):
		cycle_element(0)
		return
	if event.is_action_pressed(&"cycle_element_right"):
		cycle_element(1)
		return
	if _staff_input(event):
		return
	for side: int in 2:
		if event.is_action_pressed(ACTIONS[side]):
			_on_press(side)
			return
		if event.is_action_released(ACTIONS[side]):
			_on_release(side)
			return
	if (
		OS.is_debug_build()
		and event is InputEventKey
		and event.is_pressed()
		and not event.is_echo()
	):
		var key: Key = (event as InputEventKey).physical_keycode
		if key >= KEY_1 and key <= KEY_5:
			set_tier(key - KEY_1, true)


## R o la rueda del ratón: cambia el elemento de la gema del báculo. Devuelve si era eso.
func _staff_input(event: InputEvent) -> bool:
	if not StaffCombos.ENABLED:
		return false
	if event.is_action_pressed(&"cycle_staff"):
		_cycle_staff(1)
		return true
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var wheel: MouseButton = (event as InputEventMouseButton).button_index
		if wheel == MOUSE_BUTTON_WHEEL_UP or wheel == MOUSE_BUTTON_WHEEL_DOWN:
			var now: int = Time.get_ticks_msec()
			if now - _wheel_at >= WHEEL_STEP_MS:
				_wheel_at = now
				_cycle_staff(1 if wheel == MOUSE_BUTTON_WHEEL_UP else -1)
			return true
	return false


## Lanza con una mano, sin esperar a la combinación (lo usa el modo demo).
func try_cast(side: int) -> void:
	_request_single(side)


## Junta las manos como si se pulsaran los dos botones (modo demo). Devuelve si empezó.
func try_begin_combine() -> bool:
	if _combining or not (_hand_ready(0) and _hand_ready(1)) or recipe_for_hands() == null:
		return false
	_begin_combine(false)
	return _combining


## Suelta el hechizo combinado (modo demo).
func try_release_combine() -> void:
	if _combining:
		_launch_combine()


func _on_press(side: int) -> void:
	_auto.press(side)
	if _combining:
		# "Clic para cargar" (Opciones): el siguiente clic suelta el combinado.
		if not Settings.hold_to_charge:
			_launch_combine()
		return
	var other: int = 1 - side
	if _pending_side == other:
		# Segundo clic a tiempo: combinación (sin receta, las dos manos lanzan a la vez).
		_pending_side = -1
		if recipe_for_hands():
			_begin_combine()
		else:
			_cast_single(other)
			_cast_single(side)
	elif _hand_ready(side) and _hand_ready(other) and recipe_for_hands() != null:
		# Las dos manos listas: puede que el otro clic esté a punto de llegar.
		_pending_side = side
		_pending_time = GameState.BALANCE.combine_window_sec
	elif not _auto.joins(side):
		# (Con la otra mano en ráfaga, las dos se juntan en cuanto estén listas: ver AutoCast.)
		_request_single(side)


func _on_release(side: int) -> void:
	_auto.release(side)
	if _combining:
		if Settings.hold_to_charge:
			_launch_combine()
	elif _pending_side == side:
		# Clic corto: no hay combinación, sale ya.
		_pending_side = -1
		_cast_single(side)


func _hand_ready(side: int) -> bool:
	return _cooldown[side] <= 0.0


func _request_single(side: int) -> void:
	if _combining:
		return
	if _hand_ready(side):
		_cast_single(side)
	elif _cooldown[side] <= GameState.BALANCE.cast_buffer_sec:
		_buffered[side] = true
		_buffer_time[side] = GameState.BALANCE.cast_buffer_sec


func _process(delta: float) -> void:
	var auto: int = _auto.tick(delta, _combining)
	if (auto & AutoCast.JOIN) != 0:
		# Las dos manos se van a juntar: nada guardado de la ráfaga sale suelto antes.
		_buffered.fill(false)
	for side: int in 2:
		if _cooldown[side] > 0.0:
			_cooldown[side] -= delta
		if _buffer_time[side] > 0.0:
			_buffer_time[side] -= delta
			if _buffered[side] and _hand_ready(side):
				_cast_single(side)
		else:
			_buffered[side] = false
	if _pending_side >= 0:
		_pending_time -= delta
		if _pending_time <= 0.0:
			var side: int = _pending_side
			_pending_side = -1
			_cast_single(side)
	if (auto & AutoCast.JOIN) != 0 and _hand_ready(0) and _hand_ready(1) and recipe_for_hands():
		_pending_side = -1
		_begin_combine()
		if not _combining:
			_auto.clear()  # no se pudo (la Resonancia aún vibra): no se reintenta cada fotograma
	for side: int in 2:
		# Sólo con la mano lista (sin buffer): al soltar no queda ningún disparo guardado.
		if (auto & (1 << side)) != 0 and _pending_side < 0 and _hand_ready(side):
			_request_single(side)
	if _combining:
		_update_combine(delta)
	_resonance_lock = maxf(0.0, _resonance_lock - delta)
	if _resonance_left > 0.0:
		_resonance_left -= delta
		if _resonance_left <= 0.0:
			Events.hint.emit(tr("LA RESONANCIA SE APAGA"), Color("#a58bd0"))
	for side: int in 2:
		var ready_now: bool = _hand_ready(side)
		if ready_now and not _was_ready[side] and not _combining:
			_on_hand_ready()
		_was_ready[side] = ready_now
	if hands:
		hands.charges[0] = charge_ratio(0)
		hands.charges[1] = charge_ratio(1)
		hands.combine_charge = combine_charge()


func _on_hand_ready() -> void:
	Events.spell_ready.emit()
	if hands:
		hands.play_ready()
	if _cooldown_for(tier_for(0)) >= 0.6:
		AudioDirector.play_sfx(READY_SFX, -8.0)


## Recarga con la Canalización aplicada.
func _cooldown_for(tier: SpellTier) -> float:
	return tier.cooldown_sec * GameState.stat(&"cooldown_mult", 1.0)


## Probabilidad de golpe resonante con la Resonancia aplicada (más `bonus`, el del Arcano).
## Durante la Resonancia Arcana, todo golpe es resonante.
func _resonant_chance(bonus: float = 0.0) -> float:
	if _resonance_left > 0.0:
		return 1.0
	return (
		GameState.stat(&"resonant_percent", GameState.BALANCE.resonant_chance * 100.0) / 100.0
		+ bonus
	)


func _cast_single(side: int) -> void:
	var tier: SpellTier = tier_for(side)
	var el: ElementDef = element_of(side)
	_start_cooldown(side, _cooldown_for(tier))
	_buffered[side] = false
	_buffer_time[side] = 0.0
	var projectile: SparkProjectile = SpellDelivery.free_projectile(_delivery.projectiles)
	if projectile == null:
		return
	var hit := SpellHit.new()
	hit.tier = tier
	hit.resonant = _rng.randf() < _resonant_chance(el.resonant_bonus)
	hit.size = GameState.stat(el.size_stat, 1.0) if el.size_stat != &"" else 1.0
	var base_damage: int = _delivery.runes.harvested(_sized_damage(tier.damage, hit.size))
	hit.damage = base_damage * (GameState.BALANCE.resonant_damage_mult if hit.resonant else 1)
	hit.element = el.id
	hit.element_def = el
	_delivery.launch(projectile, hit, side)
	if tier.echoes > 0:
		_echoes.echo_single(side, hit, base_damage, projectile.target_collider, tier.echoes)
	if _resonance_left > 0.0:
		# Resonancia Arcana: cada disparo sale vibrando por un círculo arcano.
		_circles.muzzle(_hand_origin(side), hit.position, 1, ARCANE_COLOR, ARCANE_HOT)
	# El Rayo es casi instantáneo: se ve el rayo de la mano al blanco.
	if el.chain_count > 0:
		var crystal: MotherCrystal = _delivery.crystal()
		if crystal:
			crystal.draw_bolt(_hand_origin(side), hit.position, 0.06, tier.color_glow, 0.12)
	# Nivel 6+: círculos de runas que salen de la mano (uno más a nivel 8 y a nivel 10).
	var lvl_now: int = level_of(side)
	if lvl_now >= ElementDef.ASCENDED_LEVEL:
		var n: int = 1 + int(lvl_now >= 8) + int(lvl_now >= 10)
		_circles.muzzle(
			_hand_origin(side), hit.position, n, tier.color_glow * 1.6, tier.color_core * 1.8
		)
	if hands:
		hands.play_cast(side)
	# GDD 10: el crepitar suena más grave (y más fuerte) al subir de nivel.
	var lvl: int = el.tiers.find(tier)
	if tier.damage <= 0:
		# La chispita de aprendiz: un "pff" casi inaudible (GDD 3: el primer hechizo da vergüenza).
		AudioDirector.play_sfx(_cast_sounds[el], -17.0, el.cast_pitch * 1.35)
	else:
		AudioDirector.play_sfx(
			_cast_sounds[el], -2.0 + lvl * 0.8, el.cast_pitch * (1.0 - lvl * 0.07)
		)
	GameState.progression.spells_cast += 1  # pantalla final (los ecos no cuentan)
	Events.spell_cast.emit(tier, side)


## `by_input`: con los botones (no la demo); sólo esas se deshacen al perder el foco.
func _begin_combine(by_input: bool = true) -> void:
	_active_recipe = recipe_for_hands()
	if _active_recipe == null:
		return
	if _active_recipe.delivery == SpellRecipe.Delivery.RESONANCE and _resonance_lock > 0.0:
		# El cristal aún vibra con la última Resonancia: no se puede encadenar.
		Events.hint.emit(
			tr("EL CRISTAL AÚN VIBRA: ESPERA %d S") % ceili(_resonance_lock), Color("#c79bff")
		)
		AudioDirector.play_sfx(FIZZLE_SFX, -6.0, 1.2)
		return
	var storm_lock: float = _delivery.storm().lock_left()
	var gem: ElementDef = staff.element(ELEMENTS)
	if storm_lock > 0.0 and gem and not _active_recipe.is_triple():
		# Sólo una tormenta a la vez: mientras la nube descarga (o el cielo se calma), las manos
		# lanzan su pareja; se avisa de por qué no sale la Tormenta.
		var t: SpellRecipe = StaffCombos.triple_for(element_of(0).id, element_of(1).id, gem.id)
		if t and t.delivery == SpellRecipe.Delivery.STORM:
			Events.hint.emit(
				tr("EL CIELO AÚN RUGE: ESPERA %d S") % ceili(storm_lock), Color("#c9b8ff")
			)
	_combining = true
	_combine_by_input = by_input
	_combine_time = 0.0
	_combine_full_announced = false
	var bal: BalanceConfig = GameState.BALANCE
	_stages.reset(
		ChargeStages.count_for_level(charge_level(_active_recipe), bal.charge_stages_by_level),
		StaffCombos.charge_sec(_active_recipe),
		bal.charge_stage_min_sec
	)
	_stage_fx.begin(_stages.count)
	if hands:
		hands.begin_combine(_active_recipe.visual)
	if _active_recipe.is_triple():
		# Las manos y la gema: acorde de tres notas y la llama del báculo viaja al orbe.
		AudioDirector.play_sfx(TRIPLE_SFX, -2.0)
		if hands and hands.staff:
			hands.staff.begin_triple()
	AudioDirector.play_sfx(_active_recipe.combine_sfx, -3.0)
	_charge_player.stream = _active_recipe.charge_loop_sfx
	_charge_player.pitch_scale = 0.85
	_charge_player.volume_db = -18.0
	_charge_player.play()
	Events.spell_combine_started.emit(_active_recipe)


func _update_combine(delta: float) -> void:
	_combine_time += delta
	var k: float = combine_charge()
	var r: SpellRecipe = _active_recipe
	var sky: bool = (
		r.delivery == SpellRecipe.Delivery.SKY or r.delivery == SpellRecipe.Delivery.RAIN
	)
	# Cada etapa completada encaja su círculo con su golpe (una sola vez cada una).
	var new_stage: int = _stages.advance(k)
	if new_stage > 0:
		_stage_fx.stage(new_stage, _stages.count, sky)
	# El rugido del fuego sube de tono y de volumen con la carga (a escalones si va por etapas).
	_stage_fx.update_loop(_charge_player, k, _stages, delta)
	# El mundo vibra un poco mientras se concentra el poder (pasa por Settings.screen_shake).
	if camera is CameraRig:
		(camera as CameraRig).add_trauma(delta * 0.35 * k)
	var lvl: int = charge_level(r)
	if sky:
		# Hechizos del cielo: los círculos se abren siempre, apilados en horizontal en la columna
		# por la que caerá a plomo (uno más por nivel desde el 6). Con la carga, el cielo retumba.
		var aim: Dictionary = _aim()
		var aim_at: Vector3 = aim["position"]
		var aim_normal: Vector3 = aim["normal"]
		var land: Dictionary = _delivery.sky_landing(r, aim_at, aim_normal)
		var land_at: Vector3 = land["position"]
		_circles.charging_sky(
			k,
			r.sky_circles + maxi(0, lvl - ElementDef.ASCENDED_LEVEL + 1),
			land_at,
			r.sky_height,
			r.circle_color,
			r.circle_hot,
			_stages.count
		)
		if camera is CameraRig:
			(camera as CameraRig).add_trauma(delta * 0.25 * k)
	elif (
		_stages.is_staged()
		or lvl >= ElementDef.ASCENDED_LEVEL
		or _is_arcane_recipe(r)
		or r.is_triple()
	):
		# Círculos mágicos que se abren hacia donde apuntas mientras cargas: uno por etapa (y
		# siempre en los arcanos, uno por eco, y en las triples, uno por elemento).
		var arcane_n: int = (
			3 if r.is_triple() else (maxi(r.echo_count, 2) if _is_arcane_recipe(r) else 0)
		)
		var hand: Vector3 = _hand_origin(BOTH_HANDS)
		var aim_at: Vector3 = _aim()["position"]
		_circles.charging(
			k,
			maxi(maxi(_stages.count, lvl - ElementDef.ASCENDED_LEVEL + 1), arcane_n),
			hand,
			aim_at,
			r.circle_color,
			r.circle_hot,
			_stages.count
		)
	if k >= 1.0 and not _combine_full_announced:
		_combine_full_announced = true
		Events.spell_ready.emit()
		if hands:
			hands.play_ready()


func _launch_combine() -> void:
	var recipe: SpellRecipe = _active_recipe
	var charge: float = combine_charge()
	# El daño va por la última etapa completada (sobre la curva de siempre; ver ChargeStages).
	var power: float = _stages.power_charge(charge)
	_combining = false
	_charge_player.stop()
	_stage_fx.end()
	var cd: float = maxf(
		recipe.cooldown_sec * GameState.stat(&"cooldown_mult", 1.0), _cooldown_for(tier_for(0))
	)
	# El tiempo de más de una carga larga por etapas sale de la recarga (mismo ciclo de siempre).
	cd = _stages.cooldown_after(cd, charge, GameState.BALANCE.charge_stage_cooldown_floor_sec)
	_start_cooldown(0, cd)
	_start_cooldown(1, cd)
	if hands:
		hands.release_combine(release_strength(power, 1.0))
		if hands.staff and recipe.is_triple():
			hands.staff.release_triple()
	var tier: SpellTier = recipe.tier
	# Eco de X: sale X (con el aspecto del eco) y en el cristal hace lo que hace X.
	var base: SpellRecipe = SpellEchoes.base_of(recipe)
	var effect: SpellRecipe = base if base else recipe
	var hit := SpellHit.new()
	hit.tier = tier
	hit.recipe = effect
	hit.level = recipe_level(recipe)
	hit.element = effect.elements[0] if not effect.elements.is_empty() else ELEMENT.id
	hit.resonant = (
		recipe.delivery == SpellRecipe.Delivery.RESONANCE or _rng.randf() < _resonant_chance()
	)
	var gem: ElementDef = staff.element(ELEMENTS)
	var gem_damage: int = _element_tier(gem).damage if gem and recipe.is_triple() else 0
	# Premio de la carga: cada etapa completada multiplica (los combinados de toque, casi nada).
	var full_bonus: float = ChargeStages.full_bonus(
		charge_level(recipe), GameState.BALANCE.full_charge_bonus_by_level, recipe.charge_payoff
	)
	var bonus: float = ChargeStages.bonus(power, full_bonus)
	# Lo que se ve crece con el premio (x6 de daño: el estallido, casi el doble de grande).
	hit.fx_scale = 1.0 + log(bonus) / log(2.0) * 0.3
	var damage: int = recipe.damage_for(
		tier_for(0).damage, tier_for(1).damage, power, gem_damage, bonus
	)
	var power_stat: StringName = (
		recipe.power_stat if recipe.power_stat != &"" else effect.power_stat
	)
	if power_stat != &"":
		damage = roundi(float(damage) * GameState.stat(power_stat, 1.0))
	var size_stat: StringName = recipe.size_stat if recipe.size_stat != &"" else effect.size_stat
	hit.size = GameState.stat(size_stat, 1.0) if size_stat != &"" else 1.0
	damage = _delivery.runes.harvested(_sized_damage(damage, hit.size))
	if tier_for(0).damage <= 0 and tier_for(1).damage <= 0:
		# Dos chispitas de aprendiz: la combinación sigue siendo lamentable (se encoge en el aire,
		# 1 de daño y un pedacito), pero ya araña el cristal.
		hit.size = 0.45
		hit.resonant = false
		damage = 1
	hit.damage = damage * (GameState.BALANCE.resonant_damage_mult if hit.resonant else 1)
	_delivery.deliver(effect, hit, power)
	_release_kick(effect, power, hit.fx_scale)
	if base:
		_echoes.echo_recipe(recipe, base, hit, damage, power)
		AudioDirector.play_sfx(_combo_sounds[base], lerpf(-7.0, -3.0, power))
	if recipe.delivery == SpellRecipe.Delivery.RESONANCE:
		_start_resonance(recipe)
	_circles.release()
	_delivery.sky_side = -_delivery.sky_side
	AudioDirector.play_sfx(_combo_sounds[recipe], lerpf(-4.0, 0.0, power))
	GameState.progression.spells_cast += 1
	Events.spell_cast.emit(tier, BOTH_HANDS)
	GameState.register_recipe_cast(recipe)


## Fuerza del golpe al soltar un combinado (0..~2.5): la carga, y a nivel alto lo que
## multiplica el premio de la carga (`fx_scale`).
static func release_strength(power: float, fx_scale: float) -> float:
	return clampf(power, 0.0, 1.0) * maxf(fx_scale, 1.0)


## El hechizo sale de las manos con un golpe de poder (`CastBurst`): fogonazo y ondas de choque
## hacia delante, la cámara cabecea y se abre, y lo que sale disparado hacia delante te empuja
## un poco hacia atrás (más cuanto más cargado). Lo que cae del cielo o se queda delante (pozo,
## imán, tormenta) sólo da el fogonazo, sin empujón.
func _release_kick(recipe: SpellRecipe, power: float, fx_scale: float) -> void:
	var s: float = release_strength(power, fx_scale)
	var origin: Vector3 = _hand_origin(BOTH_HANDS)
	var aim_at: Vector3 = _aim()["position"]
	var dir: Vector3 = (aim_at - origin).normalized()
	var forward: bool = recipe.delivery in FORWARD_DELIVERIES
	if not forward:
		# Hacia arriba (al cielo) o delante: el fogonazo sin cono largo.
		dir = (dir + Vector3.UP * 0.6).normalized()
	_burst.play(origin, dir, recipe.circle_color, recipe.circle_hot, s * (1.0 if forward else 0.6))
	AudioDirector.play_sfx(
		RELEASE_SFX, lerpf(-16.0, -4.0, clampf(s / 2.0, 0.0, 1.0)), 1.25 - 0.1 * s
	)
	if camera is CameraRig:
		(camera as CameraRig).recoil(s * (1.0 if forward else 0.45))
	if not forward or s < 0.2:
		return
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player and player.has_method(&"knockback"):
		var back: Vector3 = -dir
		back.y = 0.0
		back = back.normalized() if back.length_squared() > 0.001 else Vector3.ZERO
		# Un empujón corto; cargado a tope a nivel alto, un saltito hacia atrás.
		var hop: float = 1.6 * clampf(s - 1.0, 0.0, 1.0)
		player.call(&"knockback", back * (1.5 + 2.6 * s) + Vector3.UP * hop)


## Deshace la combinación sin lanzar (menú, Grimorio o foco perdido a media carga): sin
## enfriamiento; los círculos se apagan y las llamas vuelven a las manos.
func _cancel_combine() -> void:
	if not _combining:
		return
	_combining = false
	_combine_time = 0.0
	_charge_player.stop()
	_circles.cancel()
	_stage_fx.end()
	if hands:
		hands.cancel_combine()
		if hands.staff:
			hands.staff.cancel_triple()
	AudioDirector.play_sfx(FIZZLE_SFX, -10.0, 0.75)


## Resonancia Arcana: unos segundos en los que todo golpe es resonante.
func _start_resonance(recipe: SpellRecipe) -> void:
	_resonance_left = recipe.buff_sec
	_resonance_lock = recipe.buff_lockout_sec
	Events.hint.emit(tr("RESONANCIA ARCANA: ¡CADA GOLPE ES RESONANTE!"), Color("#e7c6ff"))


## Combinaciones del Arcano (llevan círculos al cargar siempre, no sólo desde el nivel 6).
static func _is_arcane_recipe(r: SpellRecipe) -> bool:
	return r.elements.has(&"arcane")


## Más grande, más cristal: la mitad del aumento de tamaño se suma al daño.
static func _sized_damage(damage: int, size: float) -> int:
	return maxi(damage, roundi(float(damage) * (1.0 + (size - 1.0) * 0.5)))


func _start_cooldown(side: int, seconds: float) -> void:
	if debug_no_cooldown:
		seconds = 0.0
	_cooldown[side] = seconds
	_cooldown_total[side] = maxf(seconds, 0.001)
	_was_ready[side] = false


func _randomizer(streams: Array[AudioStream], pitch: float) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	for s: AudioStream in streams:
		r.add_stream(-1, s)
	r.random_pitch = pitch
	r.random_volume_offset_db = 2.0
	return r


## Pantalla de carga: un proyectil de cada aspecto (ver SpellDelivery.warm_up).
func warm_up(target: Vector3) -> void:
	var all: Array[SpellRecipe] = RECIPES.duplicate()
	all.append_array(StaffCombos.triples())
	_delivery.warm_up(target, ELEMENTS, all)
