class_name RuneScreen
extends Control
## La Mesa de Runas (GDD 4.3 y 5.3): se abre con F junto a la mesa del Santuario. Una losa de
## piedra con las ranuras arriba y las cinco runas debajo, cada una con su glifo, su nivel, qué
## hace ahora y qué hará al subirla. Con maná se aprenden y se suben de nivel; inscribirlas es
## elegir: sólo hay tantas activas como ranuras (una al 10 % del Pilón; más se compran desde el
## 25 %). Al aprender una runa con una ranura libre se inscribe sola. El glifo vuela a su ranura,
## destella y suena; borrar la vacía. Ratón: elegir, MEJORAR, INSCRIBIR / BORRAR, clic en una
## ranura (borra o compra). Teclado: arriba / abajo, Enter inscribe o borra; F, Esc o Tab cierran.

const OPEN_SFX: AudioStream = preload("res://audio/sfx/sfx_rune_table_open_01.ogg")
const CLOSE_SFX: AudioStream = preload("res://audio/sfx/sfx_rune_table_close_01.ogg")
const BUY_SFX: AudioStream = preload("res://audio/sfx/sfx_rune_buy_01.ogg")
const INSCRIBE_SFX: AudioStream = preload("res://audio/sfx/sfx_rune_inscribe_01.ogg")
const ERASE_SFX: AudioStream = preload("res://audio/sfx/sfx_rune_erase_01.ogg")
const DENY_SFX: AudioStream = preload("res://audio/sfx/sfx_spark_fizzle_01.ogg")
const TICK_SFX: AudioStream = preload("res://audio/sfx/sfx_ui_tick_01.ogg")
const C_SHADOW := Color("#14102a")
const C_STONE := Color("#241d3d")
const C_STONE_LIGHT := Color("#3b3160")
const C_EDGE := Color("#5a4f8a")
const C_ROW_SEL := Color("#352b62")
const C_GOLD := Color("#d8a23a")
const C_GOLD_LIGHT := Color("#ffd27a")
const C_TEXT := Color("#f2f6ff")
const C_SOFT := Color("#a5b4e6")
const C_DIM := Color("#6f6890")
const C_RED := Color("#ff7a7a")
const C_PINK := Color("#ff7ad9")
const PANEL := Rect2(56, 12, 528, 336)
const SLOT_Y: float = 62.0
const SLOT_GAP: float = 54.0
const SLOT_R: float = 15.0
const ROW_Y: float = 100.0
const ROW_H: float = 40.0
const ROW_X: float = 68.0
const ROW_W: float = 504.0
const BTN_X: float = 466.0
const BTN := Vector2(100, 14)
## Lo que tarda el glifo en volar a su ranura (s).
const FLY_SEC: float = 0.28
const SPARKS: int = 28

var is_open: bool = false
var selected: int = 0

var _t: float = 0.0
var _open_t: float = 0.0
var _closing: bool = false
var _hover: int = -1
var _hover_btn: int = -1
var _title: Label
var _mana: Label
var _slot_caps: Array[Label] = []
var _names: Array[Label] = []
var _descs: Array[Label] = []
var _effects: Array[Label] = []
var _buy_labels: Array[Label] = []
var _ink_labels: Array[Label] = []
var _note: Label
var _message: Label
var _footer: Label
var _pulse: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0])
var _slot_flash: PackedFloat32Array = PackedFloat32Array([0, 0, 0])
var _fly_def: RuneDef
var _fly_from := Vector2.ZERO
var _fly_to := Vector2.ZERO
var _fly_t: float = 1.0
var _spark_pos: PackedVector2Array = PackedVector2Array()
var _spark_vel: PackedVector2Array = PackedVector2Array()
var _spark_life: PackedFloat32Array = PackedFloat32Array()
var _spark_col: PackedColorArray = PackedColorArray()
var _next_spark: int = 0
var _message_t: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var px: float = PANEL.position.x
	var w: float = PANEL.size.x
	_title = _label(UiFonts.TITLE, UiFonts.HEAD, C_GOLD_LIGHT, Rect2(px, 20, w, 14), 1)
	_mana = _label(UiFonts.BOLD, UiFonts.SMALL, C_PINK, Rect2(px + w - 132, 21, 112, 12), 2)
	for i: int in RuneBook.MAX_SLOTS:
		var cx: float = _slot_center(i).x
		_slot_caps.append(
			_label(UiFonts.BODY, UiFonts.SMALL, C_SOFT, Rect2(cx - 40, SLOT_Y + 18, 80, 12), 1)
		)
	for i: int in RuneBook.RUNES.size():
		var y: float = ROW_Y + i * ROW_H
		_names.append(_label(UiFonts.BOLD, UiFonts.SMALL, C_TEXT, Rect2(112, y + 1, 240, 12), 0))
		_descs.append(_label(UiFonts.BODY, UiFonts.SMALL, C_SOFT, Rect2(112, y + 13, 350, 12), 0))
		_effects.append(_label(UiFonts.BODY, UiFonts.SMALL, C_TEXT, Rect2(112, y + 25, 350, 12), 0))
		_buy_labels.append(_label(UiFonts.BOLD, UiFonts.SMALL, C_TEXT, _btn_rect(i, 0), 1))
		_ink_labels.append(_label(UiFonts.BOLD, UiFonts.SMALL, C_TEXT, _btn_rect(i, 1), 1))
	for l: Label in _descs + _effects:
		l.clip_text = true
	_note = _label(UiFonts.BODY, UiFonts.SMALL, C_SOFT, Rect2(px + 12, 302, w - 24, 12), 1)
	_message = _label(UiFonts.BOLD, UiFonts.SMALL, C_GOLD_LIGHT, Rect2(px + 12, 315, w - 24, 12), 1)
	_footer = _label(UiFonts.BODY, UiFonts.SMALL, C_DIM, Rect2(px + 12, 330, w - 24, 12), 1)
	for i: int in SPARKS:
		_spark_pos.append(Vector2.ZERO)
		_spark_vel.append(Vector2.ZERO)
		_spark_life.append(0.0)
		_spark_col.append(Color.WHITE)
	Events.rune_table_requested.connect(open)
	Events.locale_changed.connect(
		func() -> void:
			if is_open:
				_refresh()
	)
	Events.mana_changed.connect(
		func(_m: int) -> void:
			if is_open:
				_refresh()
	)
	set_process(false)


func _label(font: Font, size_px: int, col: Color, r: Rect2, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", col)
	l.horizontal_alignment = align as HorizontalAlignment
	l.position = r.position
	l.size = r.size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFonts.outline(l, C_SHADOW)
	add_child(l)
	return l


func open() -> void:
	if is_open:
		return
	is_open = true
	_closing = false
	visible = true
	_open_t = 0.0
	_t = 0.0
	_message.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDirector.play_sfx(OPEN_SFX, -3.0)
	# Como el Grimorio: bloquea las manos y el movimiento.
	Events.grimoire_opened.emit()
	_refresh()
	set_process(true)


func close() -> void:
	if not is_open or _closing:
		return
	_closing = true
	AudioDirector.play_sfx(CLOSE_SFX, -5.0)


## Elige la runa `index` (0..4).
func select(index: int) -> void:
	var n: int = RuneBook.RUNES.size()
	var idx: int = posmod(index, n)
	if idx != selected:
		AudioDirector.play_sfx(TICK_SFX, -14.0, 1.0 + 0.05 * idx)
	selected = idx
	_refresh()


## Aprende o sube de nivel la runa `index` con maná. Al aprenderla, si hay ranura libre, se
## inscribe sola. Devuelve si se compró.
func buy(index: int) -> bool:
	var def: RuneDef = RuneBook.RUNES[index]
	var prog: Progression = GameState.progression
	var block: StringName = prog.purchase_block(def)
	if block != &"":
		_deny(_block_text(block, def.cost_for_level(prog.get_level(def.id))))
		return false
	var first: bool = prog.get_level(def.id) == 0
	if not GameState.buy_upgrade(def):
		return false
	_pulse[index] = 1.0
	_sparkle(_glyph_center(index), def.color, 10)
	AudioDirector.play_sfx(BUY_SFX, -3.0, 1.0 + 0.06 * prog.get_level(def.id))
	if first and RuneBook.inscribe_block(prog, def.id) == &"":
		_inscribe(index)
	else:
		var lv: int = prog.get_level(def.id)
		_say(tr("¡%s, NIVEL %d!") % [tr(def.display_name).to_upper(), lv], def.color)
		Events.runes_changed.emit()
	_refresh()
	return true


## Inscribe la runa `index` si no lo está, o la borra si lo está. Devuelve si cambió algo.
func toggle(index: int) -> bool:
	var def: RuneDef = RuneBook.RUNES[index]
	var prog: Progression = GameState.progression
	if RuneBook.is_inscribed(prog, def.id):
		var slot: int = RuneBook.slot_index(prog, def.id)
		RuneBook.erase(prog, def.id)
		_slot_flash[clampi(slot, 0, RuneBook.MAX_SLOTS - 1)] = 0.6
		AudioDirector.play_sfx(ERASE_SFX, -4.0)
		_say(tr("%s BORRADA DE SU RANURA") % tr(def.display_name).to_upper(), C_SOFT)
		Events.runes_changed.emit()
		_refresh()
		return true
	var block: StringName = RuneBook.inscribe_block(prog, def.id)
	if block != &"":
		_deny(_inscribe_text(block))
		return false
	_inscribe(index)
	_refresh()
	return true


## Compra la siguiente ranura (si se puede). Devuelve si se compró.
func buy_slot() -> bool:
	var prog: Progression = GameState.progression
	var node: UpgradeNode = RuneBook.SLOTS
	var block: StringName = prog.purchase_block(node)
	if block != &"":
		_deny(_block_text(block, node.cost_for_level(prog.get_level(node.id))))
		return false
	if not GameState.buy_upgrade(node):
		return false
	var idx: int = RuneBook.slot_count(prog) - 1
	_slot_flash[clampi(idx, 0, RuneBook.MAX_SLOTS - 1)] = 1.0
	_sparkle(_slot_center(idx), C_GOLD_LIGHT, 14)
	AudioDirector.play_sfx(BUY_SFX, -2.0, 0.9)
	_say(
		tr("¡RANURA NUEVA! YA PUEDES INSCRIBIR %d RUNAS") % RuneBook.slot_count(prog), C_GOLD_LIGHT
	)
	Events.runes_changed.emit()
	_refresh()
	return true


func _inscribe(index: int) -> void:
	var def: RuneDef = RuneBook.RUNES[index]
	var prog: Progression = GameState.progression
	if not RuneBook.inscribe(prog, def.id):
		return
	var slot: int = clampi(RuneBook.slot_index(prog, def.id), 0, RuneBook.MAX_SLOTS - 1)
	_fly_def = def
	_fly_from = _glyph_center(index)
	_fly_to = _slot_center(slot)
	_fly_t = 0.0
	AudioDirector.play_sfx(INSCRIBE_SFX, -2.0)
	_say(tr("¡%s INSCRITA!") % tr(def.display_name).to_upper(), def.color)
	Events.runes_changed.emit()


func _deny(text: String) -> void:
	AudioDirector.play_sfx(DENY_SFX, -6.0, 0.8)
	_say(text, C_RED)


func _say(text: String, col: Color) -> void:
	_message.text = text
	_message.add_theme_color_override(&"font_color", col)
	_message_t = 0.0


func _block_text(block: StringName, cost: int) -> String:
	match block:
		&"max":
			return tr("YA ESTÁ AL MÁXIMO")
		&"locked":
			return tr("AÚN NO: LA MESA PIDE MÁS PILÓN")
		&"mana":
			return tr("TE FALTA MANÁ (%s)") % Hud.format_int(cost)
	return tr("AHORA NO SE PUEDE")


func _inscribe_text(block: StringName) -> String:
	match block:
		&"unbought":
			return tr("PRIMERO APRENDE LA RUNA")
		&"full":
			return tr("NO HAY RANURA LIBRE: BORRA UNA RUNA ANTES")
		&"sealed":
			return tr("LA MESA SIGUE SELLADA")
	return tr("AHORA NO SE PUEDE")


## Qué hace la runa a nivel `level` (vacío a nivel 0); `short`, sin el daño.
static func effect_text(def: RuneDef, level: int, short: bool = false) -> String:
	if level <= 0:
		return ""
	var v: float = def.value_at(level)
	var n: int = roundi(v)
	var txt: String
	match def.kind:
		RuneDef.Kind.MULTISHOT:
			txt = _tr("+1 chispa") if n == 1 else _tr("+%d chispas") % n
		RuneDef.Kind.BOUNCE:
			txt = _tr("1 rebote") if n == 1 else _tr("%d rebotes") % n
		RuneDef.Kind.PIERCE:
			txt = _tr("túnel de %s m") % String.num(v, 1).replace(".", ",")
		RuneDef.Kind.ECHO:
			txt = _tr("%d %% de eco") % n
		_:
			txt = _tr("maná x%s") % String.num(v, 2).replace(".", ",")
			if not short:
				txt += (
					", " + _tr("daño x%s") % String.num(def.damage_at(level), 2).replace(".", ",")
				)
			return txt
	if not short:
		txt += " " + _tr("al %d %% de daño") % roundi(def.damage_at(level) * 100.0)
	return txt


static func _tr(key: String) -> String:
	return TranslationServer.translate(key)


## Rellena los textos (al abrir, comprar, inscribir o cambiar de idioma).
func _refresh() -> void:
	var prog: Progression = GameState.progression
	_title.text = tr("MESA DE RUNAS")
	_mana.text = Hud.format_int(prog.mana)
	var slots: int = RuneBook.slot_count(prog)
	for i: int in RuneBook.MAX_SLOTS:
		var cap: String = tr("RANURA %d") % (i + 1)
		if i >= slots:
			var need: StringName = prog.purchase_block(RuneBook.SLOTS)
			if i > slots:
				cap = tr("CERRADA")
			elif need == &"locked":
				cap = tr("PILÓN %d %%") % roundi(_slot_pylon() * 100.0)
			else:
				cap = Hud.format_int(
					RuneBook.SLOTS.cost_for_level(prog.get_level(RuneBook.SLOTS.id))
				)
		_slot_caps[i].text = cap
		_slot_caps[i].add_theme_color_override(&"font_color", C_SOFT if i < slots else C_DIM)
	for i: int in RuneBook.RUNES.size():
		var def: RuneDef = RuneBook.RUNES[i]
		var lv: int = prog.get_level(def.id)
		var max_lv: int = def.get_max_level()
		var ink: bool = RuneBook.is_inscribed(prog, def.id)
		var name_txt: String = tr(def.display_name).to_upper()
		if ink:
			name_txt += "  ·  " + tr("INSCRITA")
		_names[i].text = name_txt
		_names[i].add_theme_color_override(&"font_color", def.color if lv > 0 else C_TEXT)
		_descs[i].text = tr(def.description)
		var eff: String = tr("NIVEL %d: %s") % [maxi(lv, 1), effect_text(def, maxi(lv, 1))]
		if lv > 0 and lv < max_lv:
			eff += "  ·  " + tr("LUEGO: %s") % effect_text(def, lv + 1, true)
		_effects[i].text = eff
		_effects[i].add_theme_color_override(&"font_color", C_TEXT if lv > 0 else C_SOFT)
		var block: StringName = prog.purchase_block(def)
		if lv >= max_lv:
			_buy_labels[i].text = tr("MÁXIMO")
		else:
			var word: String = tr("APRENDER") if lv == 0 else tr("MEJORAR")
			_buy_labels[i].text = "%s %s" % [word, Hud.format_int(def.cost_for_level(lv))]
		_buy_labels[i].add_theme_color_override(
			&"font_color", C_GOLD_LIGHT if block == &"" else C_DIM
		)
		_ink_labels[i].text = tr("BORRAR") if ink else tr("INSCRIBIR")
		var can_ink: bool = ink or RuneBook.inscribe_block(prog, def.id) == &""
		_ink_labels[i].add_theme_color_override(&"font_color", C_TEXT if can_ink else C_DIM)
	var sel: RuneDef = RuneBook.RUNES[selected]
	_note.text = tr(sel.combo_note)
	_footer.text = tr(
		"CLIC: ELEGIR  ·  ARRIBA / ABAJO  ·  ENTER: INSCRIBIR O BORRAR  ·  F / ESC: CERRAR"
	)
	queue_redraw()


## Pilón al que se puede comprar la siguiente ranura (su requisito "pylon:").
static func _slot_pylon() -> float:
	for req: StringName in RuneBook.SLOTS.prerequisites:
		if String(req).begins_with("pylon:"):
			return float(String(req).get_slice(":", 1))
	return 0.0


static func _slot_center(i: int) -> Vector2:
	var n: float = float(RuneBook.MAX_SLOTS - 1)
	return Vector2(320.0 + (float(i) - n * 0.5) * SLOT_GAP, SLOT_Y)


static func _row_rect(i: int) -> Rect2:
	return Rect2(ROW_X, ROW_Y + i * ROW_H, ROW_W, ROW_H - 2)


static func _btn_rect(i: int, which: int) -> Rect2:
	var y: float = ROW_Y + i * ROW_H + 3 + which * 17
	return Rect2(Vector2(BTN_X, y), BTN)


static func _glyph_center(i: int) -> Vector2:
	return Vector2(ROW_X + 21, ROW_Y + i * ROW_H + 18)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if (
		event.is_action_pressed(&"interact")
		or event.is_action_pressed(&"ui_cancel")
		or event.is_action_pressed(&"open_grimoire")
	):
		close()
	elif event.is_action_pressed(&"ui_up"):
		select(selected - 1)
	elif event.is_action_pressed(&"ui_down"):
		select(selected + 1)
	elif event.is_action_pressed(&"ui_accept"):
		toggle(selected)
	elif not event.is_action_pressed(&"open_spellbook"):
		return
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_at((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_click(mb.position)
		accept_event()


func _hover_at(p: Vector2) -> void:
	var row: int = -1
	var btn: int = -1
	for i: int in RuneBook.RUNES.size():
		if _row_rect(i).has_point(p):
			row = i
			for b: int in 2:
				if _btn_rect(i, b).grow(1).has_point(p):
					btn = b
	if row != _hover or btn != _hover_btn:
		_hover = row
		_hover_btn = btn
		queue_redraw()


func _click(p: Vector2) -> void:
	for i: int in RuneBook.MAX_SLOTS:
		if p.distance_to(_slot_center(i)) <= SLOT_R + 2.0:
			_click_slot(i)
			return
	for i: int in RuneBook.RUNES.size():
		if not _row_rect(i).has_point(p):
			continue
		select(i)
		if _btn_rect(i, 0).grow(1).has_point(p):
			buy(i)
		elif _btn_rect(i, 1).grow(1).has_point(p):
			toggle(i)
		return


## Una ranura: con runa, la borra; la siguiente cerrada, la compra.
func _click_slot(i: int) -> void:
	var prog: Progression = GameState.progression
	var runes: Array[RuneDef] = RuneBook.inscribed(prog)
	if i < runes.size():
		toggle(RuneBook.RUNES.find(runes[i]))
	elif i == RuneBook.slot_count(prog):
		buy_slot()


func _process(delta: float) -> void:
	_t += delta
	_message_t += delta
	if _closing:
		_open_t -= delta
		if _open_t <= 0.0:
			is_open = false
			_closing = false
			visible = false
			set_process(false)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Events.grimoire_closed.emit()
			return
	else:
		_open_t = minf(0.3, _open_t + delta)
	for i: int in _pulse.size():
		_pulse[i] = maxf(0.0, _pulse[i] - delta * 2.0)
	for i: int in _slot_flash.size():
		_slot_flash[i] = maxf(0.0, _slot_flash[i] - delta * 2.0)
	if _fly_t < 1.0:
		_fly_t = minf(1.0, _fly_t + delta / FLY_SEC)
		if _fly_t >= 1.0 and _fly_def:
			var slot: int = RuneBook.slot_index(GameState.progression, _fly_def.id)
			_slot_flash[clampi(slot, 0, RuneBook.MAX_SLOTS - 1)] = 1.0
			_sparkle(_fly_to, _fly_def.color, 14)
	for i: int in SPARKS:
		if _spark_life[i] > 0.0:
			_spark_life[i] -= delta
			_spark_vel[i].y += 160.0 * delta
			_spark_pos[i] += _spark_vel[i] * delta
	if _message_t > 3.5 and _message.text != "":
		_message.text = ""
	var a: float = clampf(_open_t / 0.25, 0.0, 1.0)
	for c: Node in get_children():
		if c is Label:
			(c as Label).modulate.a = a
	position.y = roundf((1.0 - a) * (1.0 - a) * 24.0)
	queue_redraw()


func _sparkle(at: Vector2, col: Color, n: int) -> void:
	for k: int in n:
		var i: int = _next_spark
		_next_spark = (_next_spark + 1) % SPARKS
		var ang: float = randf() * TAU
		_spark_pos[i] = at
		_spark_vel[i] = Vector2(cos(ang), sin(ang) - 0.6) * randf_range(40.0, 110.0)
		_spark_life[i] = randf_range(0.3, 0.6)
		_spark_col[i] = col.lightened(randf() * 0.5)


func _draw() -> void:
	var a: float = clampf(_open_t / 0.25, 0.0, 1.0)
	draw_rect(Rect2(Vector2(-10, -40), Vector2(660, 440)), Color(C_SHADOW, 0.62 * a))
	_draw_panel()
	_draw_slots()
	for i: int in RuneBook.RUNES.size():
		_draw_row(i)
	RuneGlyphs.draw(self, GrimoireIcons.MANA_ICON, Vector2(PANEL.end.x - 18, 22), 1, C_PINK)
	if _fly_t < 1.0 and _fly_def:
		var k: float = smoothstep(0.0, 1.0, _fly_t)
		var p: Vector2 = _fly_from.lerp(_fly_to, k) + Vector2(0, -sin(k * PI) * 18.0)
		RuneGlyphs.draw(self, _fly_def.glyph, (p - Vector2(8, 8)).round(), 2, _fly_def.color)
	for i: int in SPARKS:
		if _spark_life[i] > 0.0:
			draw_rect(Rect2(_spark_pos[i].round(), Vector2.ONE * 2.0), _spark_col[i])


## Losa de piedra con borde tallado, esquinas de oro y una línea bajo las ranuras.
func _draw_panel() -> void:
	var r: Rect2 = PANEL
	draw_rect(r.grow(2), C_SHADOW)
	draw_rect(r, C_EDGE)
	draw_rect(r.grow(-2), C_STONE_LIGHT)
	draw_rect(r.grow(-4), C_STONE)
	# Estrías de la piedra.
	for k: int in 9:
		var y: float = r.position.y + 40 + k * 34
		draw_rect(Rect2(r.position.x + 6, y, r.size.x - 12, 1), Color(C_STONE_LIGHT, 0.35))
	for c: Vector2 in [
		r.position,
		Vector2(r.end.x - 10, r.position.y),
		r.end - Vector2(10, 10),
		Vector2(r.position.x, r.end.y - 10)
	]:
		draw_rect(Rect2(c, Vector2(10, 10)), C_GOLD)
		draw_rect(Rect2(c + Vector2(2, 2), Vector2(6, 6)), C_GOLD_LIGHT)
	draw_rect(Rect2(r.position.x + 20, SLOT_Y + 32, r.size.x - 40, 1), C_EDGE)


## Las ranuras: inscritas con su glifo y anillo de color; libres, un hueco oscuro; cerradas, con
## candado (la siguiente, con su precio o el Pilón que pide).
func _draw_slots() -> void:
	var prog: Progression = GameState.progression
	var slots: int = RuneBook.slot_count(prog)
	var runes: Array[RuneDef] = RuneBook.inscribed(prog)
	for i: int in RuneBook.MAX_SLOTS:
		var c: Vector2 = _slot_center(i)
		var flash: float = _slot_flash[i]
		var ring: Color = C_GOLD if i < slots else C_DIM
		var flying: bool = _fly_t < 1.0 and i < runes.size() and runes[i] == _fly_def
		if i < runes.size() and not flying:
			ring = runes[i].color
		draw_circle(c, SLOT_R + 2.0, C_SHADOW, true, -1.0, false)
		draw_circle(c, SLOT_R + 1.0, ring.lerp(Color.WHITE, flash), true, -1.0, false)
		draw_circle(c, SLOT_R - 1.0, C_SHADOW, true, -1.0, false)
		if i < runes.size() and not flying:
			var def: RuneDef = runes[i]
			var glow: float = 0.5 + 0.5 * sin(_t * 3.0 + i)
			draw_circle(c, SLOT_R - 3.0, Color(def.color.darkened(0.6), 0.6 + 0.3 * glow), true)
			var bob: float = roundf(sin(_t * 2.5 + i) * 1.0)
			RuneGlyphs.draw(
				self, def.glyph, c - Vector2(8, 8 + bob), 2, def.color.lerp(Color.WHITE, flash)
			)
		elif i >= slots:
			RuneGlyphs.draw(self, RuneGlyphs.LOCK, c - Vector2(4, 4), 1, C_DIM)
		else:
			# Libre: puntos que giran en el hueco.
			for k: int in 6:
				var ang: float = _t * 1.5 + TAU * k / 6.0
				draw_rect(
					Rect2((c + Vector2(cos(ang), sin(ang)) * 9.0).round(), Vector2.ONE), C_EDGE
				)


func _draw_row(i: int) -> void:
	var prog: Progression = GameState.progression
	var def: RuneDef = RuneBook.RUNES[i]
	var r: Rect2 = _row_rect(i)
	var lv: int = prog.get_level(def.id)
	var ink: bool = RuneBook.is_inscribed(prog, def.id)
	if i == selected:
		draw_rect(r, C_ROW_SEL)
		draw_rect(Rect2(r.position, Vector2(2, r.size.y)), def.color)
	elif i == _hover:
		draw_rect(r, Color(C_ROW_SEL, 0.5))
	# Marco del glifo; las inscritas brillan con su color.
	var frame := Rect2(r.position + Vector2(6, 3), Vector2(32, 32))
	draw_rect(frame.grow(1), C_SHADOW)
	draw_rect(frame, def.color.darkened(0.55) if ink else C_STONE_LIGHT)
	var pulse: float = _pulse[i]
	var col: Color = def.color if lv > 0 else C_DIM
	var g: Vector2 = frame.position + Vector2(4, 4) - Vector2(0, roundf(pulse * 3.0))
	RuneGlyphs.draw(self, def.glyph, g, 3, col.lerp(Color.WHITE, pulse))
	# Niveles: rombos tras el nombre.
	var x0: float = 112.0 + _names[i].get_minimum_size().x + 6.0
	for k: int in def.get_max_level():
		var p := Vector2(x0 + k * 7, r.position.y + 5)
		draw_rect(Rect2(p + Vector2(1, 0), Vector2(3, 5)), C_SHADOW)
		draw_rect(Rect2(p + Vector2(0, 1), Vector2(5, 3)), C_SHADOW)
		var on: Color = def.color if k < lv else C_STONE_LIGHT
		draw_rect(Rect2(p + Vector2(1, 1), Vector2(3, 3)), on)
	for b: int in 2:
		_draw_button(
			_btn_rect(i, b), i == _hover and b == _hover_btn, b == 0 and lv > 0 and pulse > 0.0
		)


func _draw_button(r: Rect2, hover: bool, lit: bool) -> void:
	draw_rect(r.grow(1), C_SHADOW)
	draw_rect(r, C_EDGE if hover else C_STONE_LIGHT)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), C_GOLD if hover or lit else C_EDGE)
