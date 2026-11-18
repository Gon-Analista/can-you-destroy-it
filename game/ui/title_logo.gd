class_name TitleLogo
extends Control
## Logo de la pantalla de título: "CAN YOU" / "DESTROY IT" letra a letra (ondulan a saltos, como
## pixel art, con un brillo que las recorre) y un "?" gigante de cristal que flota con destellos.
## El "?" se puede golpear con el ratón: se agrieta con un tintineo, tiembla, suelta esquirlas y
## protesta; al quinto golpe estalla, se vuelve "!" un momento y se vuelve a formar.
## Debajo, eslóganes graciosos que se escriben solos y van cambiando.

## El logotipo va con Pixelify Sans; la frase de debajo, con la fuente del resto de la interfaz.
const FONT_LOGO: FontFile = UiFonts.LOGO
## Tamaños del logotipo: múltiplos de los 11 px de Pixelify Sans, para que cada píxel de la letra
## ocupe 2, 3 o 7 píxeles enteros (a 16 y 32 salían píxeles desiguales y la C parecía una O).
const SIZE_SMALL: int = 22
const SIZE_BIG: int = 33
const SIZE_Q: int = 77
const HIT_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_crystal_hit_04.ogg"),
	preload("res://audio/sfx/sfx_crystal_hit_05.ogg"),
	preload("res://audio/sfx/sfx_crystal_hit_06.ogg"),
	preload("res://audio/sfx/sfx_crystal_hit_10.ogg"),
]
const SHATTER_SFX: AudioStream = preload("res://audio/sfx/sfx_crystal_surge_01.ogg")
const C_BG := Color("#14183a")
const C_SHADOW := Color("#24184f")
const C_GOLD := Color("#ffd27a")
const C_GOLD_DARK := Color("#d8a23a")
const C_SHINE := Color("#fff4d6")
const C_CYAN := Color("#a5dae5")
const C_ICE := Color("#c9f6ff")
const C_ICE_DARK := Color("#458fb8")
const C_PINK := Color("#ff7ad9")
# i18n
const TAGLINES: PackedStringArray = [
	"UN APRENDIZ. UNA CHISPITA. UN CRISTAL DEL TAMAÑO DE UNA MONTAÑA.",
	"SPOILER: PROBABLEMENTE.",
	"TU MAESTRO DICE QUE NO. TU MAESTRO NO ESTÁ AQUÍ.",
	"NINGÚN CRISTAL FUE MALTRATADO. BUENO, UNO.",
	"RECOMENDADO POR 9 DE CADA 10 MAGOS SIN CEJAS.",
	"AHORA CON UN 100 % MÁS DE CHISPA.",
	"LA PREGUNTA ES RETÓRICA. CREEMOS.",
]
# i18n
const OUCH: PackedStringArray = [
	"¡EH!", "¡OYE, QUE DUELE!", "VALE, VALE...", "¿EN SERIO? ¿AL LOGO?", "¡ESTÁ BIEN! ¡SÍ PUEDES!"
]
const HITS_TO_SHATTER: int = 5

var _small: Array[Label] = []
var _big: Array[Label] = []
var _q: Label
var _q_shadow: Label
var _tag: Label
var _q_rect: Rect2
var _t: float = 0.0
var _tag_index: int = 0
var _tag_t: float = 0.0
var _hits: int = 0
var _shake: float = 0.0
var _shattered_t: float = 0.0
var _cracks: Array[PackedVector2Array] = []
var _parts_pos: PackedVector2Array = PackedVector2Array()
var _parts_vel: PackedVector2Array = PackedVector2Array()
var _parts_life: PackedFloat32Array = PackedFloat32Array()
var _parts_col: PackedColorArray = PackedColorArray()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Medidas para centrar el bloque: "DESTROY IT" + "?" grande a su derecha.
	var big_text: String = "DESTROY IT"
	var big_w: float = (
		FONT_LOGO.get_string_size(big_text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE_BIG).x
	)
	var q_w: float = FONT_LOGO.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE_Q).x
	var x0: float = roundf((640.0 - big_w - q_w - 6.0) * 0.5)
	var x: float = x0
	for ch: String in big_text:
		var l: Label = _letter(ch, SIZE_BIG, C_GOLD)
		l.position = Vector2(x, 54)
		_big.append(l)
		x += FONT_LOGO.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE_BIG).x
	var small_text: String = "CAN YOU"
	var sx: float = x0 + 2.0
	for ch: String in small_text:
		var l: Label = _letter(ch, SIZE_SMALL, C_CYAN)
		l.position = Vector2(sx, 33)
		_small.append(l)
		sx += FONT_LOGO.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE_SMALL).x
	_q_shadow = _letter("?", SIZE_Q, C_ICE_DARK)
	_q = _letter("?", SIZE_Q, C_ICE)
	_q.position = Vector2(x + 6.0, 16)
	_q_shadow.position = _q.position + Vector2(3, 3)
	_q_rect = Rect2(_q.position + Vector2(4, 10), Vector2(q_w - 8, 70))
	_tag = Label.new()
	_tag.add_theme_font_override(&"font", UiFonts.BOLD)
	_tag.add_theme_font_size_override(&"font_size", UiFonts.SMALL)
	_tag.add_theme_color_override(&"font_color", C_CYAN)
	UiFonts.outline(_tag, C_BG)
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.position = Vector2(0, 112)
	_tag.size = Vector2(640, UiFonts.LINE)
	add_child(_tag)
	_tag_index = _rng.randi() % TAGLINES.size()
	_set_tag(tr(TAGLINES[_tag_index]))


func _letter(ch: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = ch
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_override(&"font", FONT_LOGO)
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", col)
	l.add_theme_color_override(&"font_shadow_color", C_BG if size_px < 64 else Color(0, 0, 0, 0))
	l.add_theme_constant_override(&"shadow_offset_x", 2)
	l.add_theme_constant_override(&"shadow_offset_y", 2)
	l.add_theme_color_override(&"font_outline_color", C_SHADOW)
	l.add_theme_constant_override(&"outline_size", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## Vuelve a escribir la frase con el idioma nuevo.
func relocalize() -> void:
	_set_tag(tr(TAGLINES[_tag_index]))
	_tag.add_theme_color_override(&"font_color", C_CYAN)


func _set_tag(text: String) -> void:
	_tag.text = text
	_tag.visible_ratio = 0.0
	_tag_t = 0.0


func _gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).pressed
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		and _q_rect.has_point((event as InputEventMouseButton).position)
	):
		_hit_question()
		accept_event()


## Golpear el "?": tintineo, temblor, grieta nueva, esquirlas y una protesta.
func _hit_question() -> void:
	if _shattered_t > 0.0:
		return
	_hits += 1
	_shake = 1.0
	AudioDirector.play_sfx(HIT_SFX[_rng.randi() % HIT_SFX.size()], -4.0, 1.0 + _hits * 0.06)
	_add_crack()
	_burst(_q_rect.get_center() + Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-12, 12)), 10)
	if _hits >= HITS_TO_SHATTER:
		# Estalla: lluvia de esquirlas, retumbe y un "!" triunfal un momento.
		_shattered_t = 2.6
		_burst(_q_rect.get_center(), 60)
		AudioDirector.play_sfx(SHATTER_SFX, -4.0, 1.3)
		_q.text = "!"
		_q_shadow.text = "!"
		_q.add_theme_color_override(&"font_color", C_GOLD)
		_q_shadow.add_theme_color_override(&"font_color", C_GOLD_DARK)
		_cracks.clear()
	_set_tag(tr(OUCH[mini(_hits, OUCH.size()) - 1]))
	_tag.add_theme_color_override(&"font_color", C_PINK)


func _add_crack() -> void:
	var c: Vector2 = (
		_q_rect.get_center() + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-16, 16))
	)
	var line := PackedVector2Array()
	var p: Vector2 = c
	var dir: float = _rng.randf() * TAU
	line.append(p)
	for k: int in 5:
		dir += _rng.randf_range(-0.8, 0.8)
		p += Vector2(cos(dir), sin(dir)) * _rng.randf_range(3.0, 6.0)
		line.append(p.round())
	_cracks.append(line)


func _burst(at: Vector2, n: int) -> void:
	for k: int in n:
		var a: float = _rng.randf() * TAU
		_parts_pos.append(at)
		_parts_vel.append(Vector2(cos(a), sin(a)) * _rng.randf_range(30.0, 140.0) + Vector2(0, -50))
		_parts_life.append(_rng.randf_range(0.5, 1.1))
		_parts_col.append([C_ICE, C_CYAN, C_ICE_DARK, Color.WHITE][k % 4])


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var step: float = floor(_t * 8.0) / 8.0
	# Letras que ondulan a saltos y un brillo que las recorre cada pocos segundos.
	var shine: int = int(fmod(_t * 6.0, 26.0))
	for i: int in _big.size():
		var l: Label = _big[i]
		l.position.y = 54 + roundi(sin(step * 3.0 + i * 0.55) * 2.0)
		l.add_theme_color_override(
			&"font_color", C_SHINE if i == shine or i == shine - 1 else C_GOLD
		)
	for i: int in _small.size():
		_small[i].position.y = 36 + roundi(sin(step * 3.0 + i * 0.7 + 1.5) * 1.0)
	# El "?" flota, tiembla al golpearlo y respira su color de cristal.
	_shake = maxf(0.0, _shake - delta * 4.0)
	var bob: float = roundf(sin(step * 1.6) * 3.0)
	var sh: float = roundf(sin(_t * 70.0) * 3.0 * _shake)
	_q.position = Vector2(_q_rect.position.x - 4 + sh, 16 + bob)
	_q_shadow.position = _q.position + Vector2(3, 3)
	if _shattered_t > 0.0:
		_shattered_t -= delta
		if _shattered_t <= 0.0:
			_hits = 0
			_q.text = "?"
			_q_shadow.text = "?"
			_q.add_theme_color_override(&"font_color", C_ICE)
			_q_shadow.add_theme_color_override(&"font_color", C_ICE_DARK)
			_burst(_q_rect.get_center(), 24)
	else:
		_q.add_theme_color_override(
			&"font_color", C_ICE.lerp(Color.WHITE, 0.25 + 0.25 * sin(step * 2.0))
		)
	# Eslogan que se escribe solo; cambia cada pocos segundos.
	_tag_t += delta
	_tag.visible_ratio = clampf(_tag_t * 1.6, 0.0, 1.0)
	if _tag_t > 5.5:
		_tag_index = (_tag_index + 1) % TAGLINES.size()
		_set_tag(tr(TAGLINES[_tag_index]))
		_tag.add_theme_color_override(&"font_color", C_CYAN)
	_update_particles(delta)
	queue_redraw()


func _update_particles(delta: float) -> void:
	var i: int = 0
	while i < _parts_pos.size():
		_parts_life[i] -= delta
		if _parts_life[i] <= 0.0:
			_parts_pos.remove_at(i)
			_parts_vel.remove_at(i)
			_parts_life.remove_at(i)
			_parts_col.remove_at(i)
			continue
		_parts_vel[i] += Vector2(0, 220.0) * delta
		_parts_pos[i] += _parts_vel[i] * delta
		i += 1


func _draw() -> void:
	# Destellos en estrella alrededor del "?" (titilan a saltos).
	var step: int = int(_t * 6.0)
	for k: int in 6:
		var a: float = float(k) * 1.1 + 0.3
		var r: float = 34.0 + float((k * 7) % 11)
		var on: bool = (step + k * 3) % 5 < 2
		if on:
			var p: Vector2 = (_q_rect.get_center() + Vector2(cos(a), sin(a)) * r).round()
			var s: int = 1 + (k % 2)
			draw_rect(Rect2(p.x - s * 2, p.y, s * 4 + 1, 1), C_ICE)
			draw_rect(Rect2(p.x, p.y - s * 2, 1, s * 4 + 1), C_ICE)
	# Grietas del "?" (líneas de 1 píxel, oscuras con un filo claro).
	var off := Vector2(_q.position.x - (_q_rect.position.x - 4), _q.position.y - 16)
	for line: PackedVector2Array in _cracks:
		for k: int in line.size() - 1:
			draw_line(line[k] + off, line[k + 1] + off, C_ICE_DARK, 1.0)
			draw_line(
				line[k] + off + Vector2(1, 0), line[k + 1] + off + Vector2(1, 0), Color.WHITE, 1.0
			)
	for i: int in _parts_pos.size():
		draw_rect(Rect2(_parts_pos[i].round(), Vector2(2, 2)), _parts_col[i])
