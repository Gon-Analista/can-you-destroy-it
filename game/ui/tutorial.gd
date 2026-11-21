class_name Tutorial
extends Control
## Tutorial del principio, muy rápido y con humor (pedido del equipo):
## 0. Al salir de la casucha: acércate al cristal por el camino (que se vea lo enorme que es).
## 1. Un clic: tu magia es una chispita que ni araña el cristal ("clink"). Vale cualquier mano.
## 2. El otro clic: la otra mano, igual de lamentable.
## 3. Los dos clics a la vez: juntas los hechizos. Sigue siendo malo, pero hace 1 de daño y
##    cae un pedacito. (Si juntas las manos antes, los pasos 1 y 2 se dan por sabidos.)
## 4. Recógelo. 5. Llévalo a la trituradora. 6. Junta 5 de maná. 7. Compra en el Santuario la
##    primera mejora (la magia hace 2 de daño).
## El panel dice QUÉ hacer; el CÓMO de cada tecla lo enseña el aviso junto a la mira cuando toca
## (y deja de hacerlo cuando ya se sabe), y la guía de objetivos (`ObjectiveGuide`) dice ADÓNDE
## ir. Así ninguna instrucción se repite. Cada paso avanza con lo que pasa de verdad en el juego
## (señales de Events). Empieza al abrir la puerta de la casucha y se guarda
## (`Progression.tutorial_step`).

enum Step { DOOR, APPROACH, CAST_LEFT, CAST_RIGHT, COMBINE, PICKUP, CRUSH, EARN, BUY, DONE }

const OK_SFX: AudioStream = preload("res://audio/sfx/sfx_spark_ready_01.ogg")
const C_TEXT := Color("#f2f6ff")
const C_SUB := Color("#a5dae5")
const C_GOLD := Color("#ffd27a")
const C_PINK := Color("#ff7ad9")
const C_BG := Color("#14183a")
const C_PANEL := Color("#2a1d4a")
const C_CYAN := Color("#a5dae5")
## Icono de cada paso (pixel art, '#' color, '+' brillo, 2 px por punto).
const SHARD_ICON: PackedStringArray = [
	"...#....", "..#+#...", "..#+#...", ".#+##...", ".#+###..", ".####...", "..##....", "........"
]
const MANA_ICON: PackedStringArray = [
	"...#....", "..###...", "..###...", ".##+##..", ".#+####.", ".#+####.", "..####..", "........"
]
const BOOK_ICON: PackedStringArray = [
	"........", "##.##...", "#+#+#...", "#+#+#...", "#+#+#...", "#+#+#...", "#####...", "........"
]
## Se da por llegado al cristal a esta distancia de su eje (m), por el camino desde la casucha.
const APPROACH_RADIUS: float = WorldLayout.CRYSTAL_FOOTPRINT + 14.0
## Panel centrado arriba; el ancho se ajusta al texto (`_box`).
const BOX_Y := 46.0
const BOX_H := 38.0
const TEXT_X := 36.0
## Fase de la guía de objetivos para cada paso (en el orden de `Step`).
const GUIDE_PHASES: Array[int] = [
	Guidance.Phase.DOOR,
	Guidance.Phase.CAST,
	Guidance.Phase.CAST,
	Guidance.Phase.CAST,
	Guidance.Phase.CAST,
	Guidance.Phase.PICKUP,
	Guidance.Phase.CRUSH,
	Guidance.Phase.EARN,
	Guidance.Phase.BUY,
	Guidance.Phase.DONE,
]
## Primera mejora (la que hace que tu magia haga daño de verdad).
const FIRST_UPGRADE: StringName = &"spark_power"

var step: int = Step.DONE

var _title: Label
var _sub: Label
var _t: float = 0.0
var _done_t: float = -1.0
var _pop: float = 0.0
var _wait_reaction: bool = false
## Mano con la que se lanzó el primer clic (el segundo paso pide la otra).
var _first_side: int = 0
var _box := Rect2(170, BOX_Y, 300, BOX_H)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group(&"tutorial")
	_title = _label(UiFonts.TITLE, UiFonts.HEAD, C_GOLD)
	_sub = _label(UiFonts.BODY, UiFonts.SMALL, C_SUB)
	step = _initial_step()
	Events.spell_cast.connect(_on_cast)
	Events.spell_fizzled.connect(_on_fizzled)
	Events.spell_impacted.connect(_on_impacted)
	Events.shard_collected.connect(
		func(_t2: ShardType, _c: int, _a: Vector3) -> void: _reach(Step.PICKUP)
	)
	Events.shard_sent_to_pylon.connect(func(_t2: ShardType) -> void: _reach(Step.PICKUP))
	Events.mana_changed.connect(_on_mana)
	Events.upgrade_bought.connect(
		func(id: StringName, _l: int) -> void:
			if id == FIRST_UPGRADE:
				_reach(Step.BUY)
	)
	Events.locale_changed.connect(_refresh)
	resized.connect(_layout)
	_watch_door.call_deferred()
	_refresh()


## La casucha la crea Main después del HUD: se busca un fotograma más tarde.
func _watch_door() -> void:
	if step != Step.DOOR:
		return
	var hut: ApprenticeHut = get_tree().get_first_node_in_group(&"apprentice_hut") as ApprenticeHut
	if hut == null or hut.is_open:
		_set_step(Step.APPROACH)
	else:
		hut.door_opened.connect(func() -> void: _set_step(Step.APPROACH))


func is_active() -> bool:
	return step != Step.DONE


## La fase que le importa a la guía de objetivos (`Guidance.Phase`).
func guide_phase() -> int:
	return GUIDE_PHASES[clampi(step, 0, GUIDE_PHASES.size() - 1)]


## Modo demo y pruebas: sin tutorial.
func skip() -> void:
	step = Step.DONE
	GameState.progression.tutorial_step = Step.DONE
	_done_t = -1.0
	_refresh()


## Modo demo (capturas): salta al paso `s` (con `--tutorial --tutorial-step=N`).
func jump_to(s: int) -> void:
	_set_step(clampi(s, Step.APPROACH, Step.DONE))


## Partidas que ya han empezado no ven el tutorial.
func _initial_step() -> int:
	var prog: Progression = GameState.progression
	if prog.tutorial_step >= Step.DONE:
		return Step.DONE
	if prog.pylon_progress > 0 or GameState.total_upgrade_levels() > 0:
		return Step.DONE
	return maxi(prog.tutorial_step, Step.DOOR)


func _label(font: Font, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", col)
	l.add_theme_color_override(&"font_shadow_color", C_BG)
	l.add_theme_constant_override(&"shadow_offset_x", 1)
	l.add_theme_constant_override(&"shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _set_step(s: int) -> void:
	step = s
	GameState.progression.tutorial_step = s
	_pop = 1.0
	_t = 0.0
	_refresh()


## Si el paso actual es `s`, se cumple: sonido, "pop" y al siguiente.
func _reach(s: int) -> void:
	if step != s:
		return
	AudioDirector.play_sfx(OK_SFX, -10.0, 1.3)
	if s == Step.BUY:
		_set_step(Step.DONE)
		_done_t = 3.5
		Events.hint.emit(tr("¡AHORA SÍ ERES UN MAGO! (CASI)"), C_GOLD)
		return
	_set_step(s + 1)
	if step == Step.EARN:
		_on_mana(GameState.progression.mana)


## El primer clic vale con cualquier mano; el segundo, con la otra.
func _on_cast(_tier: SpellTier, side: int) -> void:
	if step == Step.APPROACH:
		# Quien lanza antes de llegar ya ha encontrado el cristal: se sigue con los clics.
		_set_step(Step.CAST_LEFT)
	if side == SpellCaster.BOTH_HANDS:
		return
	if step == Step.CAST_LEFT:
		_first_side = side
		_wait_reaction = true
		_reach(Step.CAST_LEFT)
	elif step == Step.CAST_RIGHT and side != _first_side:
		_wait_reaction = true
		_reach(Step.CAST_RIGHT)


func _on_fizzled(_at: Vector3) -> void:
	if not _wait_reaction:
		return
	_wait_reaction = false
	if step == Step.CAST_RIGHT:
		Events.hint.emit(tr("...NI UN RASGUÑO."), C_SUB)
	elif step == Step.COMBINE:
		Events.hint.emit(tr("...TAMPOCO. QUÉ VERGÜENZA."), C_PINK)


func _on_impacted(hit: SpellHit) -> void:
	if hit.recipe == null or step < Step.CAST_LEFT or step > Step.COMBINE:
		return
	Events.hint.emit(tr("¡1 DE DAÑO! ¡CAYÓ UN PEDACITO!"), C_GOLD)
	# Quien junta las manos antes de tiempo ya sabe usar las dos: no se le repite.
	if step != Step.COMBINE:
		_wait_reaction = false
		_set_step(Step.COMBINE)
	_reach(Step.COMBINE)


func _on_mana(mana: int) -> void:
	if step == Step.CRUSH and mana > 0:
		_reach(Step.CRUSH)
	if step == Step.EARN:
		_refresh()
		if mana >= _first_cost():
			_reach(Step.EARN)


func _first_cost() -> int:
	for n: UpgradeNode in GameState.UPGRADES:
		if n.id == FIRST_UPGRADE:
			return n.cost_for_level(0)
	return 5


func _refresh() -> void:
	var titles: Dictionary[int, String] = {
		Step.APPROACH: tr("ACÉRCATE AL CRISTAL"),
		Step.CAST_LEFT: tr("CLIC IZQUIERDO: LANZA TU MAGIA"),
		Step.CAST_RIGHT:
		(
			tr("CLIC DERECHO: TU OTRA MANO")
			if _first_side == 0
			else tr("CLIC IZQUIERDO: TU OTRA MANO")
		),
		Step.COMBINE: tr("LOS DOS CLICS A LA VEZ: JUNTA TUS HECHIZOS"),
		Step.PICKUP: tr("RECOGE EL PEDACITO"),
		Step.CRUSH: tr("LLÉVALO A LA TRITURADORA"),
		Step.EARN:
		(
			tr("JUNTA %d DE MANÁ  (%d / %d)")
			% [_first_cost(), mini(GameState.progression.mana, _first_cost()), _first_cost()]
		),
		Step.BUY: tr("VE AL SANTUARIO"),
	}
	var subs: Dictionary[int, String] = {
		Step.APPROACH: tr("Sigue el camino. De cerca es aún más grande."),
		Step.CAST_LEFT: tr("Tu mano izquierda guarda una chispa. Más o menos."),
		Step.CAST_RIGHT: tr("A lo mejor ésta tiene más ganas."),
		Step.COMBINE: tr("Mantén para cargar y suelta. Juntas son menos tímidas."),
		Step.PICKUP: tr("Todo cristal cuenta. Hasta ése."),
		Step.CRUSH: tr("Sigue el rombo: está junto al Pilón."),
		Step.EARN: tr("Junta hechizos, recoge y tritura."),
		Step.BUY: tr("Inscribe «Potencia»: tu magia hará 2 de daño."),
	}
	_title.text = titles.get(step, "")
	_sub.text = subs.get(step, "")
	var shown: bool = step != Step.DOOR and step != Step.DONE
	_title.visible = shown
	_sub.visible = shown
	_layout()
	queue_redraw()


## El panel crece con el texto (cada idioma mide distinto) y se queda centrado.
func _layout() -> void:
	var w_title: float = (
		UiFonts.TITLE.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFonts.HEAD).x
	)
	var w_sub: float = (
		UiFonts.BODY.get_string_size(_sub.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFonts.SMALL).x
	)
	var w: float = clampf(maxf(w_title, w_sub) + TEXT_X + 12.0, 200.0, 620.0)
	var view_w: float = size.x if size.x > 0.0 else 640.0
	_box = Rect2(roundf((view_w - w) * 0.5), BOX_Y, w, BOX_H)
	_title.position = _box.position + Vector2(TEXT_X, 4)
	_title.size = Vector2(w - TEXT_X - 6.0, UiFonts.HEAD_LINE)
	_sub.position = _box.position + Vector2(TEXT_X, 21)
	_sub.size = Vector2(w - TEXT_X - 6.0, UiFonts.LINE)


func _process(delta: float) -> void:
	_t += delta
	_pop = maxf(0.0, _pop - delta * 3.0)
	if _done_t > 0.0:
		_done_t -= delta
	visible = step != Step.DOOR and (step != Step.DONE or _done_t > 0.0)
	if step == Step.APPROACH:
		var player: Node3D = get_tree().get_first_node_in_group(&"player") as Node3D
		if (
			player
			and (
				Vector2(player.global_position.x, player.global_position.z).length()
				< APPROACH_RADIUS
			)
		):
			_reach(Step.APPROACH)
	queue_redraw()


func _draw() -> void:
	if step == Step.DONE or step == Step.DOOR:
		return
	var r: Rect2 = _box.grow(_pop * 4.0)
	draw_rect(r.grow(2), C_BG)
	draw_rect(r, Color(C_PANEL, 0.92))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), C_GOLD)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 2), Vector2(r.size.x, 2)), C_GOLD)
	var icon_at: Vector2 = r.position + Vector2(9, 6)
	var blink: bool = int(_t * 3.0) % 2 == 0
	# Sólo QUÉ hacer: las teclas las enseña el aviso de la mira cuando hace falta.
	match step:
		Step.CAST_LEFT:
			_mouse(icon_at, blink, false)
		Step.CAST_RIGHT:
			_mouse(icon_at, blink and _first_side == 1, blink and _first_side == 0)
		Step.COMBINE:
			_mouse(icon_at, blink, blink)
		Step.APPROACH, Step.PICKUP, Step.CRUSH:
			_icon(SHARD_ICON, icon_at + Vector2(1, 4 - (1 if blink else 0)), C_CYAN)
		Step.EARN:
			_icon(MANA_ICON, icon_at + Vector2(1, 4 - (1 if blink else 0)), C_PINK)
		_:
			_icon(BOOK_ICON, icon_at + Vector2(1, 4 - (1 if blink else 0)), C_GOLD)


## Ratón pixel art con el botón izquierdo / derecho encendido.
func _mouse(at: Vector2, left: bool, right: bool) -> void:
	draw_rect(Rect2(at, Vector2(18, 26)), C_BG)
	draw_rect(Rect2(at + Vector2(1, 1), Vector2(16, 24)), C_TEXT)
	draw_rect(Rect2(at + Vector2(1, 1), Vector2(7, 10)), C_GOLD if left else C_TEXT.darkened(0.1))
	draw_rect(Rect2(at + Vector2(10, 1), Vector2(7, 10)), C_GOLD if right else C_TEXT.darkened(0.1))
	draw_rect(Rect2(at + Vector2(8, 1), Vector2(2, 10)), C_BG)
	draw_rect(Rect2(at + Vector2(1, 11), Vector2(16, 1)), C_BG)


func _icon(rows: PackedStringArray, at: Vector2, col: Color) -> void:
	var hi: Color = col.lightened(0.5)
	for pass_i: int in 2:
		for y: int in rows.size():
			var row: String = rows[y]
			for x: int in row.length():
				var ch: String = row[x]
				if ch == ".":
					continue
				var r := Rect2(at + Vector2(x * 2, y * 2), Vector2(2, 2))
				if pass_i == 0:
					draw_rect(r.grow(1), C_BG)
				else:
					draw_rect(r, hi if ch == "+" else col)
