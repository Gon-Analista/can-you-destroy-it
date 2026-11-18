class_name HudLoop
extends Control
## HUD del bucle de juego (GDD 10.2): barra del Pilón arriba con sus marcas, maná y bolsa abajo a
## la derecha, avisos en el centro, el aviso de la tecla junto a la mira (entero sólo mientras no
## se sabe, ver `Guidance.prompt_mode`) y la guía de objetivos (`ObjectiveGuide`), que dice
## adónde ir. Todo reacciona: los números ruedan, la barra destella con cada entrega, la bolsa
## llena late en oro.
## Dibujado a píxel entero con las fuentes pixel del HUD.

const BAG_FULL_SFX: AudioStream = preload("res://audio/sfx/sfx_bag_full_01.ogg")
const AVAILABLE_SFX: AudioStream = preload("res://audio/sfx/sfx_guide_new_01.ogg")
const DEF: GuidanceDef = preload("res://data/ui/guidance.tres")
const C_TEXT := Color("#f2f6ff")
const C_SHADOW := Color("#14183a")
const C_CYAN := Color("#a5dae5")
const C_GOLD := Color("#ffd27a")
const C_GOLD_DARK := Color("#d8a23a")
const C_PINK := Color("#ff7ad9")
const C_VIOLET := Color("#c79bff")
const C_DEEP := Color("#654fae")
const C_FRAME := Color("#2a43a7")
const BAR := Rect2i(8, 17, 152, 8)
const SMALL: int = UiFonts.SMALL
const LINE: int = UiFonts.LINE
## Altura de la línea del maná (y de su gota).
const MANA_Y: int = 336
const MANA_ICON: PackedStringArray = [
	"...#....", "..###...", "..###...", ".##+##..", ".#+####.", ".#+####.", "..####..", "........"
]
const SHARD_ICON: PackedStringArray = [
	"...#....", "..#+#...", "..#+#...", ".#+##...", ".#+###..", ".####...", "..##....", "........"
]
const HINT_SEC: float = 2.4

## Dentro de la casucha, antes de abrir la puerta: el Pilón aún no se conoce.
var intro: bool = false:
	set(v):
		intro = v
		if _pylon_title:
			_pylon_title.visible = not v
			_pylon_pct.visible = not v
		if _guide:
			_guide.suppressed = v
		queue_redraw()
var _camera: Camera3D
var _pylon_title: Label
var _pylon_pct: Label
var _mana: Label
var _mana_gain: Label
var _bag: Label
var _hint: Label
var _prompt: Label
## La tecla pequeña que queda cuando la acción ya se sabe.
var _key: KeyHint
var _guide: ObjectiveGuide
## Elemento de cada mano (sólo cuando conoces más de uno).
var _hand_tags: Array[Label] = []
var _shown_fill: float = 0.0
var _bar_flash: float = 0.0
var _shown_mana: float = 0.0
var _mana_punch: float = 0.0
var _gain: int = 0
var _gain_t: float = 0.0
var _bag_punch: float = 0.0
var _bag_full_t: float = 0.0
var _hint_t: float = 0.0
var _hint_queue: Array[Array] = []
var _bag_full_cooldown: float = 0.0
var _had_available: bool = false
var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pylon_title = _label("PILÓN DE MANÁ", SMALL, C_CYAN, Rect2(8, 3, 152, LINE), 0)
	_pylon_pct = _label("", SMALL, C_TEXT, Rect2(8, 29, 152, LINE), 0)
	_mana = _label("", UiFonts.HEAD, C_TEXT, Rect2(452, MANA_Y, 176, UiFonts.HEAD_LINE), 2, true)
	_mana_gain = _label("", SMALL, C_PINK, Rect2(452, 302, 176, LINE), 2)
	_bag = _label("", SMALL, C_TEXT, Rect2(428, 314, 200, LINE), 2)
	_hint = _label("", UiFonts.HEAD, C_GOLD, Rect2(20, 236, 600, UiFonts.HEAD_LINE), 1, true)
	_hint.pivot_offset = Vector2(300, 7)
	_hint.visible = false
	_prompt = _label("", SMALL, C_GOLD, Rect2(70, 214, 500, LINE), 1)
	_key = KeyHint.new()
	_key.name = "KeyHint"
	_key.position = Vector2(313, 200)
	add_child(_key)
	_guide = ObjectiveGuide.new()
	_guide.name = "Guide"
	_guide.suppressed = intro
	add_child(_guide)
	move_child(_guide, 0)
	_hand_tags.append(_label("", SMALL, C_TEXT, Rect2(8, 298, 160, LINE), 0))
	_hand_tags.append(_label("", SMALL, C_TEXT, Rect2(472, 298, 160, LINE), 2))
	Events.shard_delivered.connect(_on_delivered)
	Events.bag_changed.connect(func(_c: int, _cap: int) -> void: _bag_punch = 1.0)
	Events.bag_full.connect(_on_bag_full)
	Events.hint.connect(_push_hint)
	Events.locale_changed.connect(func() -> void: _pylon_title.text = tr("PILÓN DE MANÁ"))
	# El bucle lo enseña el Tutorial (ui/tutorial.gd); estos avisos quedan para partidas que lo
	# saltaron (demo) y aún no han entregado nada.
	if GameState.progression.pylon_progress == 0 and GameState.progression.tutorial_step >= 8:
		Events.spell_impacted.connect(_on_first_impact, CONNECT_ONE_SHOT)
		Events.shard_collected.connect(_on_first_collect, CONNECT_ONE_SHOT)
	_shown_mana = GameState.progression.mana
	_shown_fill = ManaPylon.display_fill(GameState.progression.pylon_ratio())
	_had_available = _guide.has_new_upgrade()


func _on_first_impact(_hit: SpellHit) -> void:
	if GameState.progression.times(&"pickup") < DEF.pickup_learn:
		_push_hint(tr("¡RECOGE LOS FRAGMENTOS CON [F]!"), C_CYAN)


func _on_first_collect(_type: ShardType, _count: int, _at: Vector3) -> void:
	_push_hint(tr("¡LLÉVALOS AL PILÓN DE MANÁ!"), C_PINK)


func bind(camera: Camera3D) -> void:
	_camera = camera
	_guide.bind(camera)


func _on_delivered(value: int) -> void:
	_bar_flash = 1.0
	_mana_punch = 1.0
	_gain = _gain + value if _gain_t > 0.0 else value
	_gain_t = 1.2


func _on_bag_full() -> void:
	_bag_full_t = 0.6
	if _bag_full_cooldown <= 0.0:
		_bag_full_cooldown = 1.6
		AudioDirector.play_sfx(BAG_FULL_SFX, -4.0)
		# Las primeras veces se dice con palabras; luego basta el sonido, la bolsa que late y la
		# guía, que ya apunta a la trituradora.
		if GameState.progression.learn(&"bag_full") <= DEF.bag_full_hints:
			_push_hint(tr("¡BOLSA LLENA! A LA TRITURADORA"), C_PINK)


func _push_hint(text: String, color: Color) -> void:
	# Si ya se está mostrando el mismo aviso, sólo se alarga.
	if _hint.visible and _hint.text == text:
		_hint_t = maxf(_hint_t, HINT_SEC * 0.6)
		return
	_hint_queue.append([text, color])
	if not _hint.visible:
		_next_hint()


func _next_hint() -> void:
	if _hint_queue.is_empty():
		_hint.visible = false
		return
	var h: Array = _hint_queue.pop_front()
	_hint.text = h[0]
	_hint.add_theme_color_override(&"font_color", h[1])
	_hint.visible = true
	_hint_t = HINT_SEC


func _process(delta: float) -> void:
	_t += delta
	var prog: Progression = GameState.progression
	# Pilón: la barra sube con la misma curva que el líquido del Pilón.
	var target_fill: float = ManaPylon.display_fill(prog.pylon_ratio())
	_shown_fill = lerpf(_shown_fill, target_fill, 1.0 - exp(-delta * 4.0))
	_bar_flash = maxf(0.0, _bar_flash - delta * 3.0)
	_pylon_pct.text = _percent(prog.pylon_ratio())
	# Maná que rueda y da un golpe al subir.
	_shown_mana = lerpf(_shown_mana, float(prog.mana), 1.0 - exp(-delta * 10.0))
	if absf(_shown_mana - prog.mana) < 0.5:
		_shown_mana = prog.mana
	_mana.text = Hud.format_int(roundi(_shown_mana))
	_mana_punch = maxf(0.0, _mana_punch - delta * 5.0)
	_mana.add_theme_color_override(&"font_color", C_TEXT.lerp(C_PINK, _mana_punch))
	_mana.position.y = MANA_Y - roundi(_mana_punch * 2.0)
	_gain_t = maxf(0.0, _gain_t - delta)
	_mana_gain.visible = _gain_t > 0.0
	_mana_gain.text = "+%s" % Hud.format_int(_gain)
	_mana_gain.position.y = 302 - roundi((1.2 - _gain_t) * 6.0)
	# Bolsa.
	var count: int = prog.bag_count()
	var cap: int = GameState.bag_capacity()
	_bag_punch = maxf(0.0, _bag_punch - delta * 5.0)
	_bag_full_t = maxf(0.0, _bag_full_t - delta)
	_bag_full_cooldown = maxf(0.0, _bag_full_cooldown - delta)
	var full: bool = count >= cap
	_bag.text = (tr("BOLSA  %d / %d") % [count, cap]) + (("  " + tr("¡LLENA!")) if full else "")
	var bag_col: Color = C_TEXT.lerp(C_CYAN, _bag_punch)
	if full:
		bag_col = C_GOLD if fmod(_t, 0.6) < 0.35 else C_PINK
	_bag.add_theme_color_override(&"font_color", bag_col)
	_bag.position.x = 428 + roundi(sin(_bag_full_t * 60.0) * 3.0 * (_bag_full_t / 0.6))
	# Avisos.
	if _hint.visible:
		_hint_t -= delta
		var age: float = HINT_SEC - _hint_t
		_hint.scale = Vector2.ONE * (1.0 + 0.4 * maxf(0.0, 1.0 - age / 0.15))
		_hint.modulate.a = clampf(_hint_t / 0.35, 0.0, 1.0)
		if _hint_t <= 0.0:
			_next_hint()
	_update_prompt()
	_update_hand_tags()
	# Mejora nueva (no vista en el Grimorio): campanita y aviso una vez cuando aparece. Durante
	# el tutorial ya lo dice el panel.
	var available: bool = _guide.has_new_upgrade()
	if available and not _had_available and prog.tutorial_step >= Tutorial.Step.DONE:
		AudioDirector.play_sfx(AVAILABLE_SFX, -2.0)
		_push_hint(tr("¡MEJORA DISPONIBLE EN EL SANTUARIO!"), C_GOLD)
	_had_available = available
	queue_redraw()


func _update_hand_tags() -> void:
	var player: Player = get_tree().get_first_node_in_group(&"player") as Player
	if player == null:
		return
	var caster: SpellCaster = player.get_caster()
	var known: int = 0
	for el: ElementDef in SpellCaster.ELEMENTS:
		if caster.is_unlocked(el):
			known += 1
	for side: int in 2:
		var l: Label = _hand_tags[side]
		l.visible = known > 1
		if not l.visible:
			continue
		var el: ElementDef = caster.element_of(side)
		var name: String = tr(el.display_name).to_upper()
		l.text = ("[Q] " + name) if side == 0 else (name + " [E]")
		l.add_theme_color_override(&"font_color", el.color)


## Aviso de la tecla junto a la mira: trituradora, puerta de la casucha, atril del Santuario o
## Espejo del Archimago.
## Entero mientras no se sabe; luego sólo la tecla pequeña y, al final, nada.
func _update_prompt() -> void:
	_prompt.visible = false
	_key.shown = false
	if _camera == null:
		return
	var pylon: ManaPylon = get_tree().get_first_node_in_group(&"mana_pylon") as ManaPylon
	var crusher: CrystalCrusher = pylon.crusher() if pylon else null
	if crusher and crusher.player_in_range():
		_show_prompt(crusher.prompt(), crusher.prompt_icon())
	var hut: ApprenticeHut = get_tree().get_first_node_in_group(&"apprentice_hut") as ApprenticeHut
	if hut and hut.player_can_open():
		_show_prompt(hut.prompt(), false)
	var sanctum: Sanctum = get_tree().get_first_node_in_group(&"sanctum") as Sanctum
	if sanctum and sanctum.player_in_range():
		var mode: int = Guidance.prompt_mode(
			GameState.progression.times(&"grimoire"), DEF.grimoire_learn, DEF.grimoire_forget
		)
		var full: bool = mode == Guidance.Prompt.FULL
		_show_prompt(tr("[F] ABRIR EL GRIMORIO") if full else "", mode == Guidance.Prompt.ICON)
	var mirror: ArchmageMirror = (
		get_tree().get_first_node_in_group(&"archmage_mirror") as ArchmageMirror
	)
	if mirror and mirror.player_in_range():
		_show_prompt(mirror.prompt(), mirror.prompt_icon())


func _show_prompt(text: String, icon: bool) -> void:
	if text != "":
		_prompt.visible = true
		_prompt.text = text
		_key.shown = false
	elif icon and not _prompt.visible:
		_key.shown = true


func _draw() -> void:
	if not intro:
		_draw_pylon_bar()
	_draw_levitation()
	_draw_icon(MANA_ICON, Vector2(452 + 176 - _mana_text_width() - 22, MANA_Y), 2, C_PINK)
	_draw_bag()


func _draw_pylon_bar() -> void:
	var r := Rect2(BAR)
	draw_rect(r.grow(2), C_SHADOW)
	draw_rect(r.grow(1), C_GOLD_DARK)
	draw_rect(r, C_DEEP.darkened(0.5))
	var w: float = floor(r.size.x * _shown_fill)
	if w >= 1.0:
		var fill_col: Color = C_VIOLET.lerp(Color.WHITE, _bar_flash * 0.7)
		draw_rect(Rect2(r.position, Vector2(w, r.size.y)), C_DEEP)
		draw_rect(Rect2(r.position, Vector2(w, r.size.y - 2)), fill_col)
		draw_rect(Rect2(r.position + Vector2(0, 1), Vector2(w, 1)), C_PINK)
		# Brillo que recorre el líquido a saltos.
		var sx: float = fmod(floor(_t * 12.0) * 6.0, maxf(w, 1.0))
		draw_rect(Rect2(r.position + Vector2(sx, 2), Vector2(3, 2)), Color(1.0, 1.0, 1.0, 0.8))
		draw_rect(Rect2(r.position + Vector2(w - 1, 0), Vector2(1, r.size.y)), Color("#c9f6ff"))
	for i: int in ManaPylon.MARKS.size():
		var x: float = r.position.x + floor(r.size.x * ManaPylon.display_fill(ManaPylon.MARKS[i]))
		var lit: bool = ManaPylon.mark_reached(GameState.progression.pylon_ratio(), i)
		draw_rect(Rect2(x, r.position.y - 2, 1, r.size.y + 4), C_GOLD if lit else C_GOLD_DARK)


## Carga de levitación: una barrita bajo la mirilla, sólo mientras se vuela o se recarga.
func _draw_levitation() -> void:
	var player: Player = get_tree().get_first_node_in_group(&"player") as Player
	if player == null or player.levitation_max <= 0.0:
		return
	var k: float = player.fuel_ratio()
	if not player.levitating and k >= 0.999:
		return
	var r := Rect2(300, 196, 40, 4)
	draw_rect(r.grow(1), C_SHADOW)
	draw_rect(r, Color(C_SHADOW, 0.6))
	var col: Color = C_CYAN.lerp(C_PINK, clampf(1.0 - k * 2.0, 0.0, 1.0))
	if k < 0.25 and player.levitating and int(Time.get_ticks_msec() / 120) % 2 == 0:
		col = Color.WHITE
	draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * k), r.size.y)), col)
	if player.refill_flash > 0.0:
		draw_rect(r.grow(2), Color(C_GOLD, player.refill_flash), false, 1.0)


func _draw_bag() -> void:
	var count: int = GameState.progression.bag_count()
	var cap: int = GameState.bag_capacity()
	var right: float = 628.0
	var y: float = 328.0
	if cap <= 20:
		# Una casilla por hueco: se ve de un vistazo cuánto cabe.
		var cell: float = 6.0 if cap <= 10 else 4.0
		for i: int in cap:
			var x: float = right - (cap - i) * (cell + 1.0)
			var on: bool = i < count
			draw_rect(Rect2(x, y, cell, 3), C_SHADOW)
			draw_rect(Rect2(x, y, cell - 1, 2), C_CYAN if on else C_DEEP)
	else:
		var w: float = 100.0
		draw_rect(Rect2(right - w - 1, y - 1, w + 2, 5), C_SHADOW)
		draw_rect(Rect2(right - w, y, w * float(count) / float(cap), 3), C_CYAN)
	_draw_icon(SHARD_ICON, Vector2(right - 200 - 2 + 200 - _text_w(_bag) - 12, 317), 1, C_CYAN)


func _draw_icon(rows: PackedStringArray, at: Vector2, px: int, col: Color) -> void:
	var hi: Color = col.lightened(0.5)
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			var ch: String = row[x]
			if ch == ".":
				continue
			draw_rect(Rect2(at + Vector2(x * px + 1, y * px + 1), Vector2(px, px)), C_SHADOW)
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			var ch: String = row[x]
			if ch == ".":
				continue
			draw_rect(
				Rect2(at + Vector2(x * px, y * px), Vector2(px, px)), hi if ch == "+" else col
			)


func _mana_text_width() -> float:
	return _text_w(_mana)


func _text_w(l: Label) -> float:
	var f: Font = l.get_theme_font(&"font")
	return (
		f
		. get_string_size(
			l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size(&"font_size")
		)
		. x
	)


## "0,0042 %" al principio, "12,5 %" más adelante: siempre se ve moverse.
static func _percent(ratio: float) -> String:
	var pct: float = ratio * 100.0
	var txt: String
	if pct <= 0.0:
		txt = "0"
	elif pct < 0.01:
		txt = "%.4f" % pct
	elif pct < 1.0:
		txt = "%.3f" % pct
	elif pct < 10.0:
		txt = "%.2f" % pct
	else:
		txt = "%.1f" % pct
	return txt.replace(".", ",") + " %"


func _label(
	text: String, font_size: int, color: Color, r: Rect2, align: int, bold: bool = false
) -> Label:
	var l := Label.new()
	l.text = tr(text)
	l.horizontal_alignment = align as HorizontalAlignment
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", UiFonts.TITLE if bold else UiFonts.BOLD)
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	UiFonts.outline(l, C_SHADOW)
	l.position = r.position
	l.size = r.size
	add_child(l)
	return l
