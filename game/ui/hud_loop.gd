class_name HudLoop
extends Control
## HUD del bucle de juego (GDD 10.2): barra del Pilón arriba con sus marcas, maná y bolsa abajo a
## la derecha, avisos en el centro y marcadores en pantalla hacia el Pilón (cuando llevas
## fragmentos) y hacia el Santuario (cuando hay una mejora que puedes pagar). Todo reacciona:
## los números ruedan, la barra destella con cada entrega, la bolsa llena late en oro.
## Dibujado a píxel entero con las fuentes pixel del HUD.

const BAG_FULL_SFX: AudioStream = preload("res://audio/sfx/sfx_bag_full_01.ogg")
const AVAILABLE_SFX: AudioStream = preload("res://audio/sfx/sfx_spark_ready_01.ogg")
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
## Ancho de las etiquetas de los marcadores (Trituradora, Mejora).
const TAG_W: float = 160.0
## Los marcadores no suben de aquí (arriba están la esencia y el Pilón).
const MARKER_TOP: float = 56.0
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
		queue_redraw()
var _camera: Camera3D
var _pylon_title: Label
var _pylon_pct: Label
var _mana: Label
var _mana_gain: Label
var _bag: Label
var _hint: Label
var _prompt: Label
var _pylon_tag: Label
## Elemento de cada mano (sólo cuando conoces más de uno).
var _hand_tags: Array[Label] = []
var _sanctum_tag: Label
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
var _pylon_marker: Vector3 = Vector3.INF
var _sanctum_marker: Vector3 = Vector3.INF
var _pylon_screen := Vector2.ZERO
var _sanctum_screen := Vector2.ZERO
var _pylon_edge: bool = false
var _sanctum_edge: bool = false


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
	_pylon_tag = _label("", SMALL, C_PINK, Rect2(0, 0, TAG_W, LINE), 1)
	_hand_tags.append(_label("", SMALL, C_TEXT, Rect2(8, 298, 160, LINE), 0))
	_hand_tags.append(_label("", SMALL, C_TEXT, Rect2(472, 298, 160, LINE), 2))
	_sanctum_tag = _label("", SMALL, C_GOLD, Rect2(0, 0, TAG_W, LINE), 1)
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
	_had_available = GameState.cheapest_affordable() != null


func _on_first_impact(_hit: SpellHit) -> void:
	_push_hint(tr("¡RECOGE LOS FRAGMENTOS CON [F]!"), C_CYAN)


func _on_first_collect(_type: ShardType, _count: int, _at: Vector3) -> void:
	_push_hint(tr("¡LLÉVALOS AL PILÓN DE MANÁ!"), C_PINK)


func bind(camera: Camera3D) -> void:
	_camera = camera


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
		_push_hint(tr("¡BOLSA LLENA! LLÉVALA AL PILÓN"), C_PINK)


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
	_update_markers(count, full)
	_update_hand_tags()
	# Mejora disponible: aviso y campanita una vez cuando aparece.
	var available: bool = GameState.cheapest_affordable() != null
	if available and not _had_available:
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


func _update_markers(count: int, full: bool) -> void:
	var pylon: ManaPylon = get_tree().get_first_node_in_group(&"mana_pylon") as ManaPylon
	var sanctum: Sanctum = get_tree().get_first_node_in_group(&"sanctum") as Sanctum
	_prompt.visible = false
	_pylon_marker = Vector3.INF
	_sanctum_marker = Vector3.INF
	if _camera == null:
		return
	var player: Node3D = get_tree().get_first_node_in_group(&"player") as Node3D
	var crusher: CrystalCrusher = pylon.crusher() if pylon else null
	var near_crusher: bool = crusher != null and crusher.player_in_range()
	if crusher and (count > 0 or crusher.hopper_count() > 0) and not near_crusher:
		_pylon_marker = crusher.marker_position()
		var d: float = (
			player.global_position.distance_to(crusher.global_position) if player else 0.0
		)
		_pylon_tag.text = (
			(tr("¡TRITURADORA!  %d M") if full else tr("TRITURADORA  %d M")) % roundi(d)
		)
		_pylon_tag.add_theme_color_override(&"font_color", C_GOLD if full else C_PINK)
	if near_crusher:
		_prompt.visible = true
		_prompt.text = crusher.prompt()
	if sanctum and GameState.cheapest_affordable() != null:
		_sanctum_marker = sanctum.marker_position() + Vector3.UP * 0.5
		_sanctum_tag.text = tr("¡MEJORA!")
	var hut: ApprenticeHut = get_tree().get_first_node_in_group(&"apprentice_hut") as ApprenticeHut
	if hut and hut.player_can_open():
		_prompt.visible = true
		_prompt.text = hut.prompt()
	if sanctum and sanctum.player_in_range():
		_prompt.visible = true
		_prompt.text = tr("[F] ABRIR EL GRIMORIO")
		_sanctum_marker = Vector3.INF
	_pylon_tag.visible = _pylon_marker != Vector3.INF
	_sanctum_tag.visible = _sanctum_marker != Vector3.INF
	if _pylon_tag.visible:
		var r: Array = _to_screen(_pylon_marker)
		_pylon_screen = r[0]
		_pylon_edge = r[1]
		_pylon_tag.position = _tag_position(_pylon_tag, _pylon_screen)
	if _sanctum_tag.visible:
		var r: Array = _to_screen(_sanctum_marker)
		_sanctum_screen = r[0]
		_sanctum_edge = r[1]
		_sanctum_tag.position = _tag_position(_sanctum_tag, _sanctum_screen)


## Etiqueta centrada bajo el marcador, pero siempre entera dentro de la pantalla (en el borde,
## el texto se cortaba).
func _tag_position(tag: Label, at: Vector2) -> Vector2:
	var slack: float = (TAG_W - _text_w(tag)) * 0.5
	var x: float = clampf(at.x - TAG_W * 0.5, 4.0 - slack, size.x - 4.0 - TAG_W + slack)
	return Vector2(x, at.y + 8.0).round()


## Proyecta un punto del mundo a la pantalla. Si queda fuera (o detrás), lo pega al borde.
## Devuelve [posición, está_en_el_borde].
func _to_screen(world: Vector3) -> Array:
	var sz: Vector2 = size
	var margin: float = 18.0
	var behind: bool = _camera.is_position_behind(world)
	var p: Vector2 = _camera.unproject_position(world)
	var inside: bool = (
		not behind and p.x > margin and p.x < sz.x - margin and p.y > MARKER_TOP and p.y < sz.y - 40
	)
	if inside:
		return [p.round(), false]
	var center: Vector2 = sz * 0.5
	var dir: Vector2 = p - center
	if behind:
		dir = -dir
		if dir.length_squared() < 1.0:
			dir = Vector2.DOWN
	dir.y = clampf(dir.y, -1e9, 1e9)
	var half_x: float = sz.x * 0.5 - margin
	# Arriba, por debajo de la esencia (no se pisan); abajo, por encima de la bolsa y el maná.
	var half_y: float = center.y - MARKER_TOP if dir.y < 0.0 else sz.y * 0.5 - margin - 20.0
	var k: float = minf(half_x / maxf(absf(dir.x), 0.001), half_y / maxf(absf(dir.y), 0.001))
	return [(center + dir * k).round(), true]


func _draw() -> void:
	if not intro:
		_draw_pylon_bar()
	_draw_levitation()
	_draw_icon(MANA_ICON, Vector2(452 + 176 - _mana_text_width() - 22, MANA_Y), 2, C_PINK)
	_draw_bag()
	if _pylon_tag.visible:
		_draw_marker(_pylon_screen, _pylon_edge, C_GOLD if GameState.is_bag_full() else C_PINK)
	if _sanctum_tag.visible:
		_draw_marker(_sanctum_screen, _sanctum_edge, C_GOLD)


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


## Rombo con contorno; en el borde de la pantalla, además, una flecha hacia el objetivo.
func _draw_marker(p: Vector2, edge: bool, col: Color) -> void:
	var bob: float = 0.0 if edge else round(sin(floor(_t * 8.0) * 0.8) * 1.5)
	var c: Vector2 = p + Vector2(0, bob)
	for k: int in range(-4, 5):
		var w: int = 4 - absi(k)
		draw_rect(Rect2(c.x - w - 1, c.y + k, w * 2 + 3, 1), C_SHADOW)
	for k: int in range(-3, 4):
		var w: int = 3 - absi(k)
		draw_rect(Rect2(c.x - w, c.y + k, w * 2 + 1, 1), col)
	draw_rect(Rect2(c.x, c.y - 1, 1, 1), Color.WHITE)
	if edge:
		var dir: Vector2 = (p - size * 0.5).normalized()
		for k: int in 3:
			var q: Vector2 = (c + dir * (8 + k * 2)).round()
			draw_rect(Rect2(q, Vector2(2, 2)), col)


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
