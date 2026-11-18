class_name SpellCaster
extends Node
## Lanza los hechizos de las dos manos (GDD 5.2 y 10.1). Cada mano lleva un elemento (Q / E lo
## cambian) y su propio enfriamiento: clic izquierdo lanza la izquierda, clic derecho la
## derecha. Pulsar los dos a la vez junta las manos y funde los dos elementos en un hechizo
## combinado si la pareja tiene receta (Chispa + Chispa = Bola de Fuego, Chispa + Escarcha =
## Choque Térmico), que se carga mientras se mantiene y sale al soltar. Desde el nivel 2 la
## carga va por etapas, un círculo mágico por etapa con su golpe (ChargeStages, ChargeFeedback).
##
## Para no perder la combinación, un clic con las dos manos listas espera `combine_window_sec`
## por si llega el otro; si se suelta antes, sale en el acto. Enfriamiento con "buffer" (si
## pulsas un poco antes de tiempo, sale en cuanto se pueda), golpe resonante y pools.

const ELEMENT: ElementDef = preload("res://data/elements/spark.tres")
const RECIPE: SpellRecipe = preload("res://data/spells/recipe_fireball.tres")
## Elementos que puede llevar una mano, en el orden en que se recorren con Q / E.
const ELEMENTS: Array[ElementDef] = [
	ELEMENT,
	preload("res://data/elements/frost.tres"),
	preload("res://data/elements/bolt.tres"),
	preload("res://data/elements/earth.tres"),
	preload("res://data/elements/arcane.tres"),
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
	preload("res://data/spells/recipe_steam.tres"),
	preload("res://data/spells/recipe_temper.tres"),
]
const SWITCH_SFX: AudioStream = preload("res://audio/sfx/sfx_spell_combine_01.ogg")
const CAST_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_spark_cast_01.ogg"),
	preload("res://audio/sfx/sfx_spark_cast_02.ogg"),
	preload("res://audio/sfx/sfx_spark_cast_03.ogg"),
]
const READY_SFX: AudioStream = preload("res://audio/sfx/sfx_spark_ready_01.ogg")
const FIZZLE_SFX: AudioStream = preload("res://audio/sfx/sfx_spark_fizzle_01.ogg")
const PROJECTILE_POOL: int = 24
const COMBO_PROJECTILE_POOL: int = 6
## Ecos fantasma del Arcano en vuelo a la vez (disparos sueltos y Ecos de X).
const ECHO_PROJECTILE_POOL: int = 10
const ARCANE_COLOR := Color(1.4, 0.7, 1.9)
const ARCANE_HOT := Color(2.2, 1.8, 2.4)
const PLASMA_SFX: AudioStream = preload("res://audio/sfx/amb_plasma_loop.ogg")
## Cada cuánto golpea el Haz de Plasma (s).
const BEAM_TICK: float = 0.09
const RAY_LENGTH: float = 250.0
const ACTIONS: Array[StringName] = [&"cast_left", &"cast_right"]
## Lado que usan las señales y las manos para el hechizo combinado.
const BOTH_HANDS: int = 2

@export var camera: Camera3D
@export var hands: WizardHands

## Nivel de la Chispa (lo da la Potencia; en debug, las teclas 1-5 lo fuerzan en todos).
var tier_index: int = 0
## Elemento de cada mano (índice en ELEMENTS). [izquierda, derecha]
var hand_element: Array[int] = [0, 0]
## Demo/depuración: fuerza el nivel de los combinados (1..10); -1 = el comprado.
var debug_recipe_level: int = -1
## Depuración (modo dios): las manos recargan al instante.
var debug_no_cooldown: bool = false
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
var _projectiles: Array[SparkProjectile] = []
var _combo_projectiles: Array[SparkProjectile] = []
var _cast_random: AudioStreamRandomizer
var _combo_cast_random: AudioStreamRandomizer
var _charge_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
## Haz de Plasma en curso: segundos que le quedan, golpe de plantilla y reloj de golpes.
var _beam_left: float = 0.0
var _beam_hit: SpellHit
var _beam_tick: float = 0.0
## Círculos mágicos de los niveles 6 a 10.
var _circles: MagicCircles
## Ecos del Arcano (disparos sueltos y Ecos de X) y pozo de Gravedad.
var _echoes: SpellEchoes
var _gravity: GravityWell
## Resonancia Arcana: segundos en los que todo golpe es resonante y hasta poder repetirla.
var _resonance_left: float = 0.0
var _resonance_lock: float = 0.0
## Lado por el que entra el próximo hechizo del cielo (se alterna en cada lanzamiento).
var _sky_side: float = 1.0


func _ready() -> void:
	_rng.randomize()
	for el: ElementDef in ELEMENTS:
		el.ensure_levels()
	_circles = MagicCircles.new()
	_circles.name = "MagicCircles"
	add_child(_circles)
	for i: int in PROJECTILE_POOL:
		_projectiles.append(_make_projectile("Spark%d" % i))
	for i: int in COMBO_PROJECTILE_POOL:
		_combo_projectiles.append(_make_projectile("Combo%d" % i))
	var echo_pool: Array[SparkProjectile] = []
	for i: int in ECHO_PROJECTILE_POOL:
		echo_pool.append(_make_projectile("Echo%d" % i))
		echo_pool[i].prepare_combo(false)  # Los ecos del Eco de Fuego son bolas de fuego.
	_echoes = SpellEchoes.new()
	_echoes.name = "Echoes"
	add_child(_echoes)
	_echoes.setup(
		self, _circles, echo_pool, [_aim, _hand_origin, _deliver, _deliver_sky, _resonant_chance]
	)
	_gravity = GravityWell.new()
	_gravity.name = "GravityWell"
	add_child(_gravity)
	_cast_random = _randomizer(CAST_SFX, 1.15)
	_combo_cast_random = _randomizer(RECIPE.cast_sfx, 1.08)
	for el: ElementDef in ELEMENTS:
		_cast_sounds[el] = (
			_randomizer(el.cast_sfx, 1.12) if not el.cast_sfx.is_empty() else _cast_random
		)
	for r: SpellRecipe in RECIPES:
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
	var el: ElementDef = element_of(side)
	var idx: int = tier_index if el == ELEMENT else roundi(GameState.stat(el.power_stat, 0.0))
	if _debug_tier >= 0:
		idx = _debug_tier
	return el.tiers[clampi(idx, 0, el.tiers.size() - 1)]


## Demo y menú de depuración: todos los hechizos a nivel `level` (1..10) sin comprar nada;
## 0 vuelve a los niveles comprados. Con `celebrate`, las manos lo celebran.
func set_debug_level(level: int, celebrate: bool = false) -> void:
	_debug_tier = level - 1
	debug_recipe_level = level
	_refresh_hands(celebrate)


## Nivel (1..10) del hechizo de una mano.
func level_of(side: int) -> int:
	return element_of(side).tiers.find(tier_for(side)) + 1


## Nivel (1..10) de un combinado: 1 + niveles comprados de su Potencia.
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


## Receta para la pareja de elementos de las manos (el orden no importa), o null.
func recipe_for_hands() -> SpellRecipe:
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


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed(&"cycle_element_left"):
		cycle_element(0)
		return
	if event.is_action_pressed(&"cycle_element_right"):
		cycle_element(1)
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
	else:
		_request_single(side)


func _on_release(side: int) -> void:
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
	if _combining:
		_update_combine(delta)
	if _beam_left > 0.0:
		_update_beam(delta)
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
	var projectile: SparkProjectile = _free_projectile(_projectiles)
	if projectile == null:
		return
	var hit := SpellHit.new()
	hit.tier = tier
	hit.resonant = _rng.randf() < _resonant_chance(el.resonant_bonus)
	hit.size = GameState.stat(el.size_stat, 1.0) if el.size_stat != &"" else 1.0
	var base_damage: int = _sized_damage(tier.damage, hit.size)
	hit.damage = base_damage * (GameState.BALANCE.resonant_damage_mult if hit.resonant else 1)
	hit.element = el.id
	hit.element_def = el
	_launch(projectile, hit, side)
	if tier.echoes > 0:
		_echoes.echo_single(side, hit, base_damage, projectile.target_collider, tier.echoes)
	if _resonance_left > 0.0:
		# Resonancia Arcana: cada disparo sale vibrando por un círculo arcano.
		_circles.muzzle(_hand_origin(side), hit.position, 1, ARCANE_COLOR, ARCANE_HOT)
	# El Rayo es casi instantáneo: se ve el rayo de la mano al blanco.
	if el.chain_count > 0:
		var crystal: MotherCrystal = _crystal()
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
	_combining = true
	_combine_by_input = by_input
	_combine_time = 0.0
	_combine_full_announced = false
	var bal: BalanceConfig = GameState.BALANCE
	_stages.reset(
		ChargeStages.count_for_level(charge_level(_active_recipe), bal.charge_stages_by_level),
		_active_recipe.charge_sec,
		bal.charge_stage_min_sec
	)
	_stage_fx.begin(_stages.count)
	if hands:
		hands.begin_combine(_active_recipe.visual)
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
		# Hechizos del cielo: los círculos se abren siempre, encima del blanco y mirando hacia
		# abajo (uno más por nivel desde el 6). Con la carga, el cielo retumba.
		var aim: Dictionary = _aim()
		_circles.charging_sky(
			k,
			r.sky_circles + maxi(0, lvl - ElementDef.ASCENDED_LEVEL + 1),
			aim["position"],
			aim["normal"],
			_sky_origin(r, aim["position"], aim["normal"]),
			r.circle_color,
			r.circle_hot,
			_stages.count
		)
		if camera is CameraRig:
			(camera as CameraRig).add_trauma(delta * 0.25 * k)
	elif _stages.is_staged() or lvl >= ElementDef.ASCENDED_LEVEL or _is_arcane_recipe(r):
		# Círculos mágicos que se abren hacia donde apuntas mientras cargas: uno por etapa (y
		# siempre en los arcanos: los Ecos, uno por eco).
		var arcane_n: int = maxi(r.echo_count, 2) if _is_arcane_recipe(r) else 0
		_circles.charging(
			k,
			maxi(maxi(_stages.count, lvl - ElementDef.ASCENDED_LEVEL + 1), arcane_n),
			_hand_origin(BOTH_HANDS),
			_aim()["position"],
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
		hands.release_combine()
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
	var damage: int = recipe.damage_for(tier_for(0).damage, tier_for(1).damage, power)
	var power_stat: StringName = (
		recipe.power_stat if recipe.power_stat != &"" else effect.power_stat
	)
	if power_stat != &"":
		damage = roundi(float(damage) * GameState.stat(power_stat, 1.0))
	var size_stat: StringName = recipe.size_stat if recipe.size_stat != &"" else effect.size_stat
	hit.size = GameState.stat(size_stat, 1.0) if size_stat != &"" else 1.0
	damage = _sized_damage(damage, hit.size)
	if tier_for(0).damage <= 0 and tier_for(1).damage <= 0:
		# Dos chispitas de aprendiz: la combinación sigue siendo lamentable (se encoge en el aire,
		# 1 de daño y un pedacito), pero ya araña el cristal.
		hit.size = 0.45
		hit.resonant = false
		damage = 1
	hit.damage = damage * (GameState.BALANCE.resonant_damage_mult if hit.resonant else 1)
	_deliver(effect, hit, power)
	if base:
		_echoes.echo_recipe(recipe, base, hit, damage, power)
		AudioDirector.play_sfx(_combo_sounds[base], lerpf(-7.0, -3.0, power))
	if recipe.delivery == SpellRecipe.Delivery.RESONANCE:
		_start_resonance(recipe)
	_circles.release()
	_sky_side = -_sky_side
	AudioDirector.play_sfx(_combo_sounds[recipe], lerpf(-4.0, 0.0, power))
	GameState.progression.spells_cast += 1
	Events.spell_cast.emit(tier, BOTH_HANDS)
	GameState.register_recipe_cast(recipe)


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
	AudioDirector.play_sfx(FIZZLE_SFX, -10.0, 0.75)


## Cada combinación llega al cristal a su manera (ver SpellRecipe.Delivery).
func _deliver(recipe: SpellRecipe, hit: SpellHit, charge: float) -> void:
	match recipe.delivery:
		SpellRecipe.Delivery.SKY:
			_deliver_sky(recipe, hit, charge)
		SpellRecipe.Delivery.RAIN:
			_deliver_rain(recipe, hit)
		SpellRecipe.Delivery.BEAM:
			_beam_hit = hit
			_beam_left = recipe.beam_sec
			_beam_tick = 0.0
			_charge_player.stream = PLASMA_SFX
			_charge_player.pitch_scale = 1.0
			_charge_player.volume_db = -4.0
			_charge_player.play()
		SpellRecipe.Delivery.MAGNET:
			var player: Node = get_tree().get_first_node_in_group(&"player")
			var n: int = int(player.call(&"magnet_pull", 45.0)) if player else 0
			var crystal: MotherCrystal = _crystal()
			if crystal:
				crystal.magnet_pulse(camera.global_position - Vector3(0, 1.4, 0), n)
		SpellRecipe.Delivery.GROUND:
			_deliver_ground(hit, charge)
		SpellRecipe.Delivery.GRAVITY:
			# El pozo se abre delante del mago, algo por encima de la mirada.
			var flat: Vector3 = -camera.global_basis.z
			flat.y = 0.0
			flat = flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD
			var center: Vector3 = camera.global_position + flat * 6.0 + Vector3.UP * 0.6
			_gravity.open(center, (camera.global_position - center).normalized(), recipe, _circles)
			if camera is CameraRig:
				(camera as CameraRig).add_trauma(0.3)
		_:
			var projectile: SparkProjectile = _free_projectile(_combo_projectiles)
			if projectile:
				# Misma carga que el orbe entre las manos (WizardHands): sale del mismo tamaño.
				projectile.orb_charge = lerpf(0.15, 1.0, charge)
				_launch(projectile, hit, BOTH_HANDS)


func _crystal() -> MotherCrystal:
	return get_tree().get_first_node_in_group(&"mother_crystal") as MotherCrystal


## Meteoro, Trueno: cae desde lo alto sobre el punto que miras (en diagonal, para que se vea).
## `aim` (opcional): otro blanco, como el de un eco.
func _deliver_sky(
	recipe: SpellRecipe, hit: SpellHit, charge: float, aim: Dictionary = {}
) -> Vector3:
	if aim.is_empty():
		aim = _aim()
	var target: Vector3 = aim["position"]
	var origin: Vector3 = _sky_origin(recipe, target, aim["normal"])
	hit.position = target
	hit.normal = aim["normal"]
	hit.direction = (target - origin).normalized()
	var projectile: SparkProjectile = _free_projectile(_combo_projectiles)
	if projectile:
		projectile.orb_charge = lerpf(0.4, 1.0, charge)
		projectile.launch(origin, target, hit, aim["collider"])
	var crystal: MotherCrystal = _crystal()
	if crystal and recipe.fall_sec < 0.3:
		# El Trueno: el rayo baja ya, del cielo al blanco (violeta si es un eco).
		var col: Color = recipe.circle_hot if hit.tier == recipe.tier else hit.tier.color_glow * 1.8
		crystal.sky_bolt(origin, target, col)
	return origin


## De dónde cae un hechizo del cielo sobre `target`: alto, sobre el blanco y a un lado, para que
## se vea caer en diagonal (ver SkyPath); sus círculos se abren por ese camino.
func _sky_origin(recipe: SpellRecipe, target: Vector3, normal: Vector3) -> Vector3:
	return SkyPath.origin(
		camera.get_world_3d().direct_space_state,
		camera.global_position,
		target,
		normal,
		recipe.sky_height,
		_sky_side
	)


## Lluvia de Estalactitas: caen escalonadas del cielo sobre una zona alrededor del blanco.
func _deliver_rain(recipe: SpellRecipe, hit: SpellHit) -> void:
	var aim: Dictionary = _aim()
	var center: Vector3 = aim["position"]
	var n: int = maxi(recipe.rain_count, 1)
	var each: int = maxi(1, roundi(float(hit.damage) / float(n)))
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
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
		sub.element = &"frost"
		sub.damage = each
		sub.minor = i > 0
		sub.size = hit.size
		sub.position = r["position"]
		sub.normal = r["normal"]
		sub.direction = Vector3.DOWN
		var delay: float = 0.08 * i + _rng.randf() * 0.05
		get_tree().create_timer(delay).timeout.connect(
			func() -> void:
				var p: SparkProjectile = _free_projectile(_projectiles)
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
	var projectile: SparkProjectile = _free_projectile(_combo_projectiles)
	if projectile:
		projectile.orb_charge = lerpf(0.4, 1.0, charge)
		projectile.launch(from, hit.position, hit, r["collider"])
	if camera is CameraRig:
		(camera as CameraRig).add_trauma(0.5)


## Resonancia Arcana: unos segundos en los que todo golpe es resonante.
func _start_resonance(recipe: SpellRecipe) -> void:
	_resonance_left = recipe.buff_sec
	_resonance_lock = recipe.buff_lockout_sec
	Events.hint.emit(tr("RESONANCIA ARCANA: ¡CADA GOLPE ES RESONANTE!"), Color("#e7c6ff"))


## Combinaciones del Arcano (llevan círculos al cargar siempre, no sólo desde el nivel 6).
static func _is_arcane_recipe(r: SpellRecipe) -> bool:
	return r.elements.has(&"arcane")


## Haz de Plasma: golpea cada BEAM_TICK donde apunte la mirilla mientras dure.
func _update_beam(delta: float) -> void:
	_beam_left -= delta
	_beam_tick -= delta
	var origin: Vector3 = _hand_origin(BOTH_HANDS)
	var aim: Dictionary = _aim()
	var crystal: MotherCrystal = _crystal()
	if crystal:
		crystal.draw_beam(origin, aim["position"], _beam_hit.recipe.circle_color)
	if _beam_tick <= 0.0:
		_beam_tick = BEAM_TICK
		var collider: Object = null if CritterHerd.beam(_beam_hit, aim) else aim["collider"]
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
	if camera is CameraRig:
		(camera as CameraRig).add_trauma(delta * 0.6)
	if _beam_left <= 0.0:
		_charge_player.stop()


## Más grande, más cristal: la mitad del aumento de tamaño se suma al daño.
static func _sized_damage(damage: int, size: float) -> int:
	return maxi(damage, roundi(float(damage) * (1.0 + (size - 1.0) * 0.5)))


func _start_cooldown(side: int, seconds: float) -> void:
	if debug_no_cooldown:
		seconds = 0.0
	_cooldown[side] = seconds
	_cooldown_total[side] = maxf(seconds, 0.001)
	_was_ready[side] = false


## Apunta por el centro de la pantalla y lanza el proyectil desde la mano `side`.
func _launch(projectile: SparkProjectile, hit: SpellHit, side: int) -> void:
	var result: Dictionary = _aim()
	var target: Vector3 = result["position"]
	hit.normal = result["normal"]
	var collider: Object = result["collider"]
	hit.position = target
	var origin: Vector3 = _hand_origin(side)
	hit.direction = (target - origin).normalized()
	projectile.launch(origin, target, hit, collider)


func _make_projectile(node_name: String) -> SparkProjectile:
	var p := SparkProjectile.new()
	p.name = node_name
	p.top_level = true
	p.arrived.connect(_on_projectile_arrived)
	add_child(p)
	return p


func _randomizer(streams: Array[AudioStream], pitch: float) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	for s: AudioStream in streams:
		r.add_stream(-1, s)
	r.random_pitch = pitch
	r.random_volume_offset_db = 2.0
	return r


func _free_projectile(pool: Array[SparkProjectile]) -> SparkProjectile:
	for p: SparkProjectile in pool:
		if not p.active:
			return p
	return null


## Pantalla de carga: lanza un proyectil de cada aspecto distinto (niveles de cada elemento y
## combinaciones) hacia `target` sin efecto de juego, para compilar shaders y partículas.
func warm_up(target: Vector3) -> void:
	var from: Vector3 = camera.global_position + camera.global_basis * Vector3(0.0, -0.3, -1.5)
	var seen: Array[SpellVisualDef] = []
	var k: int = 0
	for p: SparkProjectile in _combo_projectiles:
		p.prepare_combo()
	for el: ElementDef in ELEMENTS:
		for tier: SpellTier in el.tiers:
			if seen.has(tier.visual) or k >= _projectiles.size():
				continue
			seen.append(tier.visual)
			var hit := SpellHit.new()
			hit.tier = tier
			hit.warmup = true
			hit.position = target
			hit.normal = Vector3.BACK
			_projectiles[k].launch(from, target, hit, null)
			k += 1
	var j: int = 0
	for r: SpellRecipe in RECIPES:
		if r.is_reaction or r.tier == null:
			continue
		var combo := SpellHit.new()
		combo.tier = r.tier
		combo.recipe = r
		combo.warmup = true
		combo.position = target
		combo.normal = Vector3.BACK
		if j < _combo_projectiles.size():
			_combo_projectiles[j].launch(from, target, combo, null)
			j += 1
		elif k < _projectiles.size():
			_projectiles[k].launch(from, target, combo, null)
			k += 1
	_circles.charging(1.0, 2, from, target, Color.ORANGE, Color.WHITE)
	_circles.release()


func _on_projectile_arrived(projectile: SparkProjectile) -> void:
	if projectile.hit.warmup or CritterHerd.intercept(projectile.hit, projectile.target_collider):
		return
	var collider: Object = projectile.target_collider
	if collider is Node and (collider as Node).has_meta(&"mother_crystal"):
		var crystal: MotherCrystal = (collider as Node).get_meta(&"mother_crystal")
		crystal.receive_hit(projectile.hit)
		var r: SpellRecipe = projectile.hit.recipe
		if r and r.delivery == SpellRecipe.Delivery.RESONANCE:
			crystal.resonance_pulse(projectile.hit)
	else:
		AudioDirector.play_sfx(FIZZLE_SFX, -6.0)
		Events.spell_fizzled.emit(projectile.hit.position)
