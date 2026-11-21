class_name LoadingCover
extends Control
## Pantalla de carga: tapa la entrada al juego mientras se carga la escena en otro hilo, se talla
## el cristal (`CrystalPrebuild`) y se precalientan los efectos (`Main._warm_up`). Vive en su
## propia CanvasLayer bajo la raíz para sobrevivir al cambio de escena (`SceneFlow`). Título,
## estrella que late, cielo de estrellas, barra de progreso con la etapa y un consejo que cambia;
## al terminar se desvanece y se borra sola.

const C_BG := Color("#14183a")
const C_PANEL := Color("#24184f")
const C_GOLD := Color("#ffd27a")
const C_GOLD_DARK := Color("#d8a23a")
const C_PINK := Color("#ff7ad9")
const C_CYAN := Color("#a5dae5")
const C_STAR := Color("#c9f6ff")
const BAR := Rect2i(200, 214, 240, 8)
const TIP_SEC: float = 4.5
## Etapas que se enseñan bajo el título (las pasan `SceneFlow` y `Main._warm_up`; aquí para que
## se extraigan y traduzcan).
# i18n
const STAGES: PackedStringArray = [
	"PREPARANDO LA MAGIA",
	"CARGANDO EL VALLE",
	"TALLANDO EL CRISTAL",
	"DESPERTANDO EL VALLE",
	"ENCENDIENDO EL PILÓN",
	"ABRIENDO EL SANTUARIO",
	"VOLVIENDO AL TÍTULO",
	"¡LISTO!",
]
## Consejos de la parte de abajo (uno al azar y luego en orden).
# i18n
const TIPS: PackedStringArray = [
	"JUNTA LAS DOS MANOS PARA COMBINAR SUS ELEMENTOS",
	"LOS FRAGMENTOS VAN A LA TOLVA: TRITURADOS DAN MANÁ",
	"EL GRIMORIO DEL SANTUARIO GUARDA TODAS LAS MEJORAS",
	"CADA VENA DEL CRISTAL TIENE UN ELEMENTO DÉBIL",
	"LOS GOLPES SEGUIDOS SUMAN RACHA Y A VECES RESUENAN",
	"CUANDO EL PILÓN SE LLENE, EL VALLE ESTARÁ SALVADO",
	"LOS BICHOS DEL VALLE NO MUERDEN... PERO REVIENTAN",
	"LA MESA DE RUNAS DESPIERTA CON EL PILÓN AL 10 %",
	"EL ESPEJO DEL SANTUARIO GUARDA TUS CIFRAS DE MAGO",
	"ESC ABRE EL MENÚ: OPCIONES, FOV Y CONTROLES",
]

## La que está en pantalla (la reutiliza `Main._warm_up` al llegar de `SceneFlow`).
static var current: LoadingCover

var _t: float = 0.0
var _fade: float = -1.0
var _fade_in: float = 1.0
var _target: float = 0.0
var _shown: float = 0.0
var _stage: String = ""
var _tip_index: int = 0
var _tip_t: float = 0.0
var _stars: Array[Vector3i] = []
var _title: Label
var _sub: Label
var _tip: Label
var _pct: Label


## Abre la pantalla de carga encima de todo (o devuelve la que ya hay). `fade_in` la funde desde
## transparente (al salir del título); sin él tapa de golpe (al arrancar desde el editor).
static func open(tree: SceneTree, fade_in: bool = false) -> LoadingCover:
	if current != null and is_instance_valid(current) and current._fade < 0.0:
		return current
	var layer := CanvasLayer.new()
	layer.name = "LoadingLayer"
	layer.layer = 120
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var cover := LoadingCover.new()
	cover.name = "LoadingCover"
	cover._fade_in = 0.0 if fade_in else 1.0
	layer.add_child(cover)
	# Diferido: si se llama desde el `_ready` de la escena que se está montando, la raíz está
	# ocupada y no admite hijos todavía.
	tree.root.add_child.call_deferred(layer)
	current = cover
	return cover


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 70:
		_stars.append(Vector3i(rng.randi_range(0, 639), rng.randi_range(0, 359), rng.randi() % 100))
	_tip_index = randi() % TIPS.size()
	_title = _label("CAN YOU DESTROY IT?", UiFonts.LOGO, 33, C_GOLD, Rect2(0, 132, 640, 40))
	_sub = _label("", UiFonts.BOLD, UiFonts.SMALL, C_CYAN, Rect2(0, 190, 640, UiFonts.LINE))
	_pct = _label("", UiFonts.BOLD, UiFonts.SMALL, C_GOLD, Rect2(0, 228, 640, UiFonts.LINE))
	_tip = _label("", UiFonts.BOLD, UiFonts.SMALL, C_STAR, Rect2(16, 318, 608, UiFonts.LINE))
	_set_stage("PREPARANDO LA MAGIA" if _stage == "" else _stage)
	_show_tip()
	modulate.a = _fade_in


## Avance (0..1) y, si se da, la etapa ("TALLANDO EL CRISTAL"...). La barra nunca retrocede.
func set_progress(ratio: float, stage: String = "") -> void:
	_target = maxf(_target, clampf(ratio, 0.0, 1.0))
	if stage != "" and stage != _stage:
		_set_stage(stage)


## Llena la barra, empieza a desvanecerse y se borra sola al terminar.
func finish() -> void:
	set_progress(1.0, "¡LISTO!")
	_fade = 1.25
	if current == self:
		current = null


func _set_stage(stage: String) -> void:
	_stage = stage
	if _sub:
		_sub.text = tr(stage)


func _show_tip() -> void:
	_tip.text = tr("CONSEJO") + ": " + tr(TIPS[_tip_index])
	_tip_t = 0.0


func _process(delta: float) -> void:
	_t += delta
	_fade_in = minf(1.0, _fade_in + delta * 4.0)
	# La barra corre hacia el objetivo (deprisa si se queda atrás, para no esperar a la animación).
	_shown = move_toward(_shown, _target, delta * maxf(0.6, (_target - _shown) * 4.0))
	_pct.text = "%d %%" % roundi(_shown * 100.0)
	var dots: int = int(_t * 3.0) % 4
	_sub.text = tr(_stage) + ".".repeat(dots) if _fade < 0.0 else tr(_stage)
	_tip_t += delta
	if _tip_t >= TIP_SEC:
		_tip_index = (_tip_index + 1) % TIPS.size()
		_show_tip()
	_tip.modulate.a = clampf(minf(_tip_t * 3.0, (TIP_SEC - _tip_t) * 3.0), 0.0, 1.0)
	var a: float = _fade_in
	if _fade >= 0.0:
		# Primero se ve la barra llena un instante; luego se funde.
		_fade -= delta * 2.5
		a = minf(a, clampf(_fade, 0.0, 1.0))
		if _fade <= 0.0:
			if get_parent() is CanvasLayer:
				get_parent().queue_free()
			else:
				queue_free()
			return
	modulate.a = a
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	# Cielo de estrellas que titilan, a píxel entero.
	for s: Vector3i in _stars:
		var tw: float = 0.5 + 0.5 * sin(_t * (1.0 + s.z * 0.03) + s.z)
		if tw > 0.25:
			draw_rect(Rect2(s.x, s.y, 1, 1), Color(C_STAR, 0.15 + 0.5 * tw))
	# Estrella de cuatro puntas que late.
	var c := Vector2(320, 112)
	var r: int = 3 + int(2.0 + 2.0 * sin(_t * 5.0))
	var col: Color = C_PINK if fmod(_t, 0.6) < 0.3 else C_GOLD
	draw_rect(Rect2(c.x - r * 2, c.y, r * 4 + 1, 1), col)
	draw_rect(Rect2(c.x, c.y - r * 2, 1, r * 4 + 1), col)
	for k: int in range(-r, r + 1):
		var w: int = r - absi(k)
		draw_rect(Rect2(c.x - w, c.y + k, w * 2 + 1, 1), col)
	# Barra: marco dorado, fondo violeta, relleno rosa a dorado con un brillo que corre.
	var b := Rect2(BAR)
	draw_rect(b.grow(2), C_GOLD_DARK)
	draw_rect(b.grow(1), C_BG)
	draw_rect(b, C_PANEL)
	var fill: int = roundi(b.size.x * _shown)
	for x: int in fill:
		var k: float = float(x) / b.size.x
		draw_rect(Rect2(b.position.x + x, b.position.y, 1, b.size.y), C_PINK.lerp(C_GOLD, k))
	if fill > 0:
		draw_rect(Rect2(b.position.x, b.position.y, fill, 2), Color(1, 1, 1, 0.35))
		var shine: int = int(fmod(_t * 160.0, b.size.x + 40.0)) - 20
		for x: int in range(maxi(0, shine), mini(fill, shine + 6)):
			draw_rect(Rect2(b.position.x + x, b.position.y, 1, b.size.y), Color(1, 1, 1, 0.4))
	# Esquinas del marco, como los paneles del juego.
	for p: Vector2 in [
		b.position - Vector2(3, 3),
		Vector2(b.end.x + 1, b.position.y - 3),
		Vector2(b.position.x - 3, b.end.y + 1),
		b.end + Vector2(1, 1),
	]:
		draw_rect(Rect2(p, Vector2(2, 2)), C_GOLD)


func _label(text: String, font: Font, font_size: int, color: Color, r: Rect2) -> Label:
	var l := Label.new()
	l.text = tr(text)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.position = r.position
	l.size = r.size
	add_child(l)
	return l
