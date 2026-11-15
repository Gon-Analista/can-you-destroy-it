class_name Hud
extends Control
## HUD del prototipo. Todo reacciona: el contador de Esencia baja con un "golpe" de escala y
## color, la racha salta y cambia de color, los números flotan desde el impacto y los hitos
## de racha y los golpes resonantes se celebran con un aviso grande.

## Silkscreen para texto pequeño (diseñada para 8 px); Pixelify Sans para números grandes.
const FONT_SMALL: FontFile = preload("res://ui/fonts/silkscreen_regular.woff2")
const FONT_BOLD: FontFile = preload("res://ui/fonts/pixelify_sans_bold.woff2")
const C_TEXT := Color("#f2f6ff")
const C_SHADOW := Color("#14183a")
const C_CYAN := Color("#a5dae5")
const C_GOLD := Color("#ffd27a")
## Colores de la racha según crece: cian -> violeta -> rosa -> oro.
const STREAK_COLORS: Array[Color] = [
	Color("#c9f6ff"), Color("#c79bff"), Color("#ff7ad9"), Color("#ffd27a")
]
const FLOATERS: int = 24

## Muestra el HUD de juego aunque el ratón no esté capturado (modo demo).
var force_captured_look: bool = false

var _camera: Camera3D
var _caster: SpellCaster
var _essence_title: Label
var _essence: Label
var _streak: Label
var _banner: Label
var _pylon: Label
var _bag: Label
var _pickup_prompt: Label
var _bag_punch: float = 0.0
var _fps: Label
var _debug: Label
var _prompt: Label
var _crosshair: Crosshair
var _shown_essence: float = 0.0
var _target_essence: int = 0
var _essence_punch: float = 0.0
var _streak_punch: float = 0.0
var _streak_fade: float = 0.0
var _banner_time: float = 0.0
var _floaters: Array[Label] = []
var _floater_pos: Array[Vector3] = []
var _floater_age: PackedFloat32Array = []
var _floater_next: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	_essence_title = _label("ESENCIA DEL CRISTAL", 8, C_CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_essence_title, Control.PRESET_CENTER_TOP, Rect2(-80, 6, 160, 10))
	_essence = _label("1.000.000", 24, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	_place(_essence, Control.PRESET_CENTER_TOP, Rect2(-100, 15, 200, 26))
	_essence.pivot_offset = Vector2(100, 13)
	_pylon = _label("", 8, C_CYAN, HORIZONTAL_ALIGNMENT_LEFT)
	_place(_pylon, Control.PRESET_TOP_LEFT, Rect2(8, 6, 160, 10))
	_bag = _label("", 8, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_bag, Control.PRESET_BOTTOM_RIGHT, Rect2(-308, -18, 300, 10))
	_bag.pivot_offset = Vector2(300, 5)
	_pickup_prompt = _label("", 8, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_pickup_prompt, Control.PRESET_CENTER, Rect2(-120, 20, 240, 10))
	_pickup_prompt.visible = false
	_fps = _label("", 8, C_CYAN, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_fps, Control.PRESET_TOP_RIGHT, Rect2(-70, 6, 62, 10))
	_fps.visible = OS.is_debug_build()
	_debug = _label("", 8, Color(C_TEXT, 0.75), HORIZONTAL_ALIGNMENT_LEFT)
	_place(_debug, Control.PRESET_BOTTOM_LEFT, Rect2(8, -16, 240, 10))
	_debug.visible = OS.is_debug_build()
	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_crosshair)
	_streak = _label("", 16, STREAK_COLORS[0], HORIZONTAL_ALIGNMENT_LEFT, true)
	_place(_streak, Control.PRESET_CENTER, Rect2(14, 6, 90, 20))
	_streak.pivot_offset = Vector2(0, 10)
	_banner = _label("", 16, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER, true)
	_place(_banner, Control.PRESET_CENTER, Rect2(-150, -62, 300, 20))
	_banner.pivot_offset = Vector2(150, 10)
	_banner.visible = false
	_prompt = _label(
		"CLIC PARA EMPEZAR  ·  WASD MOVERSE  ·  CLIC LANZAR  ·  F RECOGER",
		8,
		C_TEXT,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_place(_prompt, Control.PRESET_CENTER, Rect2(-200, 30, 400, 10))
	for i: int in FLOATERS:
		var f: Label = _label("", 8, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
		f.size = Vector2(80, 12)
		f.visible = false
		_floaters.append(f)
		_floater_pos.append(Vector3.ZERO)
		_floater_age.append(-1.0)
	Events.essence_changed.connect(_on_essence_changed)
	Events.pylon_changed.connect(_on_pylon_changed)
	Events.spell_impacted.connect(_on_impact)
	Events.streak_changed.connect(_on_streak_changed)
	Events.streak_milestone.connect(_on_streak_milestone)
	Events.streak_broken.connect(_on_streak_broken)
	Events.shard_collected.connect(_on_shard_collected)
	Events.shard_targeted.connect(_on_shard_targeted)
	_target_essence = GameState.progression.essence
	_shown_essence = _target_essence
	_essence.text = _format_int(_target_essence)
	_on_pylon_changed(GameState.progression.pylon_progress, GameState.progression.pylon_ratio())
	_refresh_bag()


func bind(camera: Camera3D, caster: SpellCaster) -> void:
	_camera = camera
	_caster = caster


## Ancla `c` al punto `preset` y lo coloca con un rectángulo relativo a ese ancla.
static func _place(c: Control, preset: Control.LayoutPreset, r: Rect2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x
	c.offset_bottom = r.position.y + r.size.y


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT_SMALL
	t.default_font_size = 8
	return t


func _label(
	text: String, font_size: int, color: Color, align: HorizontalAlignment, bold: bool = false
) -> Label:
	var l := Label.new()
	l.text = tr(text)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override(&"font_size", font_size)
	if bold:
		l.add_theme_font_override(&"font", FONT_BOLD)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_shadow_color", C_SHADOW)
	l.add_theme_constant_override(&"shadow_offset_x", 1)
	l.add_theme_constant_override(&"shadow_offset_y", 1)
	l.add_theme_constant_override(&"shadow_outline_size", 0)
	add_child(l)
	return l


static func _format_int(v: int) -> String:
	var s: String = str(absi(v))
	var out: String = ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


func _on_essence_changed(essence: int, _total: int) -> void:
	_target_essence = essence
	_essence_punch = 1.0


func _on_shard_targeted(type: ShardType) -> void:
	_pickup_prompt.visible = type != null
	if type:
		_pickup_prompt.text = tr("[F] RECOGER %s") % tr(type.display_name).to_upper()


func _on_shard_collected(type: ShardType, _count: int, at: Vector3) -> void:
	_bag_punch = 1.0
	_refresh_bag()
	var i: int = _floater_next
	_floater_next = (_floater_next + 1) % FLOATERS
	var f: Label = _floaters[i]
	f.text = "+1 " + tr(type.display_name).to_upper()
	f.add_theme_color_override(&"font_color", C_CYAN)
	f.add_theme_font_size_override(&"font_size", 8)
	_floater_pos[i] = at + Vector3.UP * 0.3
	_floater_age[i] = 0.0
	f.visible = true


## "BOLSA  3 ASTILLAS · 1 FRAGMENTO", en el orden de tamaño.
func _refresh_bag() -> void:
	var parts: PackedStringArray = []
	for type: ShardType in ShardPool.TYPES:
		var n: int = GameState.progression.bag.get(type.id, 0)
		if n > 0:
			var name_key: String = type.display_name if n == 1 else type.display_name_plural
			parts.append("%d %s" % [n, tr(name_key).to_upper()])
	_bag.text = (tr("BOLSA  ") + "  ·  ".join(parts)) if not parts.is_empty() else ""


func _on_pylon_changed(_progress: int, ratio: float) -> void:
	_pylon.text = tr("PILÓN DE MANÁ  %d %%") % int(floor(ratio * 100.0))


func _on_impact(hit: SpellHit) -> void:
	var i: int = _floater_next
	_floater_next = (_floater_next + 1) % FLOATERS
	var f: Label = _floaters[i]
	f.text = ("-%d  " + tr("¡RESONANTE!")) % hit.damage if hit.resonant else "-%d" % hit.damage
	f.add_theme_color_override(&"font_color", C_GOLD if hit.resonant else C_TEXT)
	f.add_theme_font_size_override(&"font_size", 16 if hit.resonant else 8)
	_floater_pos[i] = hit.position + hit.normal * 0.6
	_floater_age[i] = 0.0
	f.visible = true
	if hit.resonant:
		_show_banner(tr("¡GOLPE RESONANTE!"), C_GOLD)


func _on_streak_changed(streak: int) -> void:
	if streak <= 1:
		# 0 llega justo después de romperse la racha: dejamos que el texto se desvanezca.
		if streak == 1:
			_streak.visible = false
		return
	_streak.visible = true
	_streak.text = "x%d" % streak
	var idx: int = clampi(int(log(float(streak)) / log(2.6)) - 1, 0, STREAK_COLORS.size() - 1)
	_streak.add_theme_color_override(&"font_color", STREAK_COLORS[idx])
	_streak_punch = 1.0
	_streak_fade = 1.0


func _on_streak_milestone(streak: int) -> void:
	_show_banner(tr("¡RACHA x%d!") % streak, STREAK_COLORS[clampi(streak / 20, 0, 3)])


func _on_streak_broken(_final: int) -> void:
	_streak_fade = 0.999


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override(&"font_color", color)
	_banner.visible = true
	_banner_time = 1.2


func _process(delta: float) -> void:
	var captured: bool = force_captured_look or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_prompt.visible = not captured
	_crosshair.visible = captured
	if _caster:
		_crosshair.charge = _caster.charge_ratio()
	# Esencia: el número baja rodando y el texto da un golpe de escala y color.
	if absf(_shown_essence - _target_essence) > 0.01:
		_shown_essence = lerpf(_shown_essence, float(_target_essence), 1.0 - exp(-delta * 14.0))
		if absf(_shown_essence - _target_essence) < 0.5:
			_shown_essence = _target_essence
		_essence.text = _format_int(int(round(_shown_essence)))
	_essence_punch = maxf(0.0, _essence_punch - delta * 6.0)
	_essence.scale = Vector2.ONE * (1.0 + _essence_punch * 0.18)
	_essence.add_theme_color_override(&"font_color", C_TEXT.lerp(C_CYAN, _essence_punch))
	_bag_punch = maxf(0.0, _bag_punch - delta * 6.0)
	_bag.scale = Vector2.ONE * (1.0 + _bag_punch * 0.25)
	_bag.add_theme_color_override(&"font_color", C_TEXT.lerp(C_CYAN, _bag_punch))
	# Racha.
	_streak_punch = maxf(0.0, _streak_punch - delta * 7.0)
	_streak.scale = Vector2.ONE * (1.0 + _streak_punch * 0.45)
	if _streak_fade < 1.0:
		_streak_fade = maxf(0.0, _streak_fade - delta * 2.5)
		_streak.modulate.a = _streak_fade
		if _streak_fade <= 0.0:
			_streak.visible = false
			_streak.modulate.a = 1.0
			_streak_fade = 1.0
	# Aviso grande.
	if _banner_time > 0.0:
		_banner_time -= delta
		var k: float = clampf(_banner_time / 1.2, 0.0, 1.0)
		_banner.scale = Vector2.ONE * (1.0 + pow(k, 6.0) * 0.6)
		_banner.modulate.a = clampf(_banner_time / 0.3, 0.0, 1.0)
		if _banner_time <= 0.0:
			_banner.visible = false
	_update_floaters(delta)
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	if _debug.visible and _caster:
		_debug.text = tr("DEBUG  1-5: NIVEL DE CHISPA (%d)") % (_caster.tier_index + 1)


func _update_floaters(delta: float) -> void:
	if _camera == null:
		return
	for i: int in FLOATERS:
		if _floater_age[i] < 0.0:
			continue
		_floater_age[i] += delta
		var t: float = _floater_age[i]
		var f: Label = _floaters[i]
		var world: Vector3 = _floater_pos[i] + Vector3.UP * (t * 1.6 - t * t * 0.6)
		if t > 0.9 or _camera.is_position_behind(world):
			_floater_age[i] = -1.0
			f.visible = false
			continue
		var screen: Vector2 = _camera.unproject_position(world)
		f.position = (screen - f.size * 0.5).round()
		f.modulate.a = clampf((0.9 - t) / 0.3, 0.0, 1.0)
