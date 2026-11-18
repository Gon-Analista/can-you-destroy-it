class_name TearCounter
extends Control
## Contador de Lágrimas del Núcleo en el HUD, a la izquierda del maná (lo coloca HudLoop con
## `right_x`). Aparece al llegar al Corazón Cristalino o con la primera Lágrima. La gota late
## como las del mundo; al recoger una, una gota vuela desde donde estaba hasta el contador
## dejando estela, y al llegar el número salta, destella y suelta un anillo de píxeles.
## Dibujado a píxel entero con las fuentes pixel del HUD.

const C_SHADOW := Color("#14183a")
const C_TEAR := Color("#8a4fe0")
const C_PINK := Color("#ff7ad9")
const C_TEXT := Color("#f2e6ff")
## Lágrima de 7x10 (distinta de la gota rosa del maná): 'o' borde violeta claro, '#' cuerpo casi
## negro y '+' el corazón rosa que late.
const ICON: PackedStringArray = [
	"...o...",
	"...o...",
	"..o#o..",
	"..o#o..",
	".o###o.",
	"o##+##o",
	"o#+++#o",
	"o##+##o",
	".o###o.",
	"..ooo.."
]
const C_BODY := Color("#2a1240")
const C_RIM := Color("#c79bff")
const FLY_SEC: float = 0.55
const BEAT_SEC: float = 1.15
const TRAIL: int = 10
## Tamaño de píxel de la gota (como la del maná).
const PX: int = 2

## Borde derecho del contador (px del HUD): justo a la izquierda de la gota del maná.
var right_x: float = 420.0
var y: float = 336.0

var _label: Label
var _shown: int = 0
var _punch: float = 0.0
var _ring: float = 0.0
var _t: float = 0.0
## Gotas volando al contador: desde, tiempo (-1 libre).
var _fly_from: PackedVector2Array = PackedVector2Array()
var _fly_t: PackedFloat32Array = PackedFloat32Array()
var _camera: Camera3D
var _icon_x: float = 400.0
var _label_value: int = -1
## Píxeles de ICON por tipo (borde, cuerpo, corazón), calculados una vez: dibujar no crea textos.
var _px_rim: PackedVector2Array = PackedVector2Array()
var _px_body: PackedVector2Array = PackedVector2Array()
var _px_heart: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_override(&"font", UiFonts.TITLE)
	_label.add_theme_font_size_override(&"font_size", UiFonts.HEAD)
	_label.add_theme_color_override(&"font_color", C_TEXT)
	UiFonts.outline(_label, C_SHADOW)
	_label.size = Vector2(60, UiFonts.HEAD_LINE)
	add_child(_label)
	for yy: int in ICON.size():
		for x: int in ICON[yy].length():
			match ICON[yy][x]:
				"o":
					_px_rim.append(Vector2(x, yy))
				"#":
					_px_body.append(Vector2(x, yy))
				"+":
					_px_heart.append(Vector2(x, yy))
	for i: int in 4:
		_fly_from.append(Vector2.ZERO)
		_fly_t.append(-1.0)
	_shown = GameState.progression.tears
	Events.tear_collected.connect(_on_collected)
	# Las primeras caen en mitad de las llamas de los combinados: se avisa para que no se pierdan.
	Events.tear_dropped.connect(
		func(_at: Vector3) -> void:
			if GameState.progression.tears_total < 2:
				Events.hint.emit(tr("¡EL CORAZÓN HA LLORADO UNA LÁGRIMA!"), C_PINK)
	)
	Events.tears_changed.connect(_on_changed)
	# El Núcleo queda expuesto: la última estrella del Grimorio se ve (la Gran Convergencia).
	Events.grimoire_final_revealed.connect(
		func() -> void: Events.hint.emit(tr("¡EL GRIMORIO REVELA SU ÚLTIMA PÁGINA!"), C_PINK)
	)


func bind(camera: Camera3D) -> void:
	_camera = camera


## Se ve desde que se llega al Corazón (o se tiene alguna Lágrima).
func is_shown() -> bool:
	var prog: Progression = GameState.progression
	return prog.tears_total > 0 or prog.deepest_layer >= TearDrops.HEART_LAYER


func _on_collected(at: Vector3) -> void:
	var from := Vector2(320, 180)
	if _camera and not _camera.is_position_behind(at):
		# El HUD va a 640x360: la cámara del mundo también (SubViewport del mundo).
		var vp: Vector2 = _camera.get_viewport().get_visible_rect().size
		from = _camera.unproject_position(at) * Vector2(640.0, 360.0) / vp
	for i: int in _fly_t.size():
		if _fly_t[i] < 0.0:
			_fly_from[i] = from.clamp(Vector2(8, 8), Vector2(632, 352))
			_fly_t[i] = 0.0
			break
	var total: int = GameState.progression.tears_total
	if total <= 3:
		Events.hint.emit(tr("¡LÁGRIMA DEL NÚCLEO!"), C_PINK)
		if total == 1:
			Events.hint.emit(tr("PAGA LOS NODOS FINALES DEL GRIMORIO"), Color("#c79bff"))


func _on_changed(tears: int) -> void:
	# Al gastar baja en el acto; al recoger espera a que llegue la gota que vuela.
	if tears < _shown or not _flying():
		_shown = tears
		_punch = 0.6


func _flying() -> bool:
	for t: float in _fly_t:
		if t >= 0.0:
			return true
	return false


func _process(delta: float) -> void:
	_t += delta
	visible = is_shown()
	if not visible:
		return
	_punch = maxf(0.0, _punch - delta * 3.0)
	_ring = maxf(0.0, _ring - delta * 2.2)
	for i: int in _fly_t.size():
		if _fly_t[i] < 0.0:
			continue
		_fly_t[i] += delta
		if _fly_t[i] >= FLY_SEC:
			_fly_t[i] = -1.0
			_shown = mini(_shown + 1, GameState.progression.tears)
			_punch = 1.0
			_ring = 1.0
	if not _flying():
		_shown = GameState.progression.tears
	if _label_value != _shown:
		_label_value = _shown
		_label.text = str(_shown)
	var w: float = _text_w()
	_label.position = Vector2(right_x - 60.0, y - roundi(_punch * 3.0))
	_label.add_theme_color_override(&"font_color", C_TEXT.lerp(C_PINK, _punch))
	_icon_x = right_x - w - 4.0 - 7.0 * PX
	queue_redraw()


func _text_w() -> float:
	return UiFonts.TITLE.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFonts.HEAD).x


func _beat() -> float:
	var bt: float = fmod(_t, BEAT_SEC)
	return maxf(exp(-bt * 11.0), exp(-maxf(bt - 0.19, 0.0) * 11.0) * 0.7 * float(bt > 0.19))


func _draw() -> void:
	var at := Vector2(_icon_x, y - 4.0 - roundi(_punch * 3.0))
	var beat: float = _beat()
	var rim: Color = C_RIM.lerp(Color.WHITE, _punch * 0.7)
	var heart: Color = C_PINK.lerp(Color.WHITE, beat * 0.6)
	if beat > 0.5 or _punch > 0.2:
		# Halo de un píxel alrededor en cada latido.
		_draw_icon(at + Vector2(-1, 0), Color(C_PINK, 0.35), PX)
		_draw_icon(at + Vector2(1, 0), Color(C_PINK, 0.35), PX)
	_draw_icon(at + Vector2(1, 1), C_SHADOW, PX)
	_draw_icon(at, rim, PX, heart, C_BODY.lerp(C_TEAR, beat * 0.4))
	if _ring > 0.0:
		var c: Vector2 = at + Vector2(3.5, 5.0) * PX
		var r: float = (1.0 - _ring) * 22.0 + 4.0
		for k: int in 12:
			var a: float = TAU * float(k) / 12.0 + _t
			var p: Vector2 = (c + Vector2(cos(a), sin(a)) * r).round()
			draw_rect(Rect2(p, Vector2(2, 2)), Color(C_PINK if k % 2 == 0 else C_TEXT, _ring))
	for i: int in _fly_t.size():
		if _fly_t[i] >= 0.0:
			_draw_flight(i, at)


## Gota que vuela en arco hasta el contador, con estela de píxeles que se apagan.
func _draw_flight(i: int, to: Vector2) -> void:
	var k: float = clampf(_fly_t[i] / FLY_SEC, 0.0, 1.0)
	for s: int in TRAIL:
		var kk: float = maxf(0.0, k - float(s) * 0.03)
		var p: Vector2 = _flight_pos(_fly_from[i], to, kk)
		var a: float = (1.0 - float(s) / float(TRAIL)) * 0.8
		draw_rect(Rect2(p.round(), Vector2(2, 2)), Color(C_PINK if s % 2 == 0 else C_TEAR, a))
	var head: Vector2 = _flight_pos(_fly_from[i], to, k)
	_draw_icon(
		head.round() - Vector2(3, 5) * PX, C_RIM.lerp(Color.WHITE, 1.0 - k), PX, C_PINK, C_BODY
	)


static func _flight_pos(from: Vector2, to: Vector2, k: float) -> Vector2:
	var e: float = k * k * (3.0 - 2.0 * k)
	var p: Vector2 = from.lerp(to + Vector2(3, 5) * PX, e)
	p.y -= sin(k * PI) * 40.0
	return p


## Sin `heart` (alfa 0), de un solo color (sombra y halo).
func _draw_icon(
	at: Vector2, rim: Color, px: int, heart := Color(0, 0, 0, 0), body := Color(0, 0, 0, 0)
) -> void:
	var flat: bool = heart.a <= 0.0
	var sz := Vector2(px, px)
	for p: Vector2 in _px_rim:
		draw_rect(Rect2(at + p * px, sz), rim)
	for p: Vector2 in _px_body:
		draw_rect(Rect2(at + p * px, sz), rim if flat else body)
	for p: Vector2 in _px_heart:
		draw_rect(Rect2(at + p * px, sz), rim if flat else heart)
