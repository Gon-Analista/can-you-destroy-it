class_name StationLabels
extends Control
## Nombres de las estaciones del valle (Pilón, Trituradora, Santuario, Mesa de Runas, Espejo,
## Jaula): al acercarse se lee qué es cada cosa sin tener que tocarla. Debajo del nombre, una
## línea con para qué sirve mientras el jugador no la ha usado nunca (`Progression.times`), sólo
## en la que queda más cerca de la mira; luego sólo el nombre. Si se pisan, las lejanas suben.
## Aparecen entre `FAR_M` y `NEAR_M` metros y se apagan al llegar, cuando manda el aviso de la
## tecla junto a la mira. Main le pasa el mundo con `bind_world`.

## Distancias (m): a partir de FAR_M empiezan a verse, del todo a FULL_M; por debajo de NEAR_M se
## apagan (el aviso de la mira ya dice qué hacer).
const FAR_M: float = 30.0
const FULL_M: float = 22.0
const NEAR_M: float = 6.0
const GONE_M: float = 4.2
const C_NAME := Color("#ffd27a")
const C_DESC := Color("#f2f6ff")
const C_SHADOW := Color("#14183a")
## Ancho de las etiquetas (px a 640x360) y margen con los bordes de la pantalla.
const LABEL_W: float = 260.0
const SIDE: float = 6.0
## Para qué sirve cada estación (en el orden de `bind_world`).
# i18n
const HELP: PackedStringArray = [
	"SE LLENA CON EL MANÁ QUE TRITURAS",
	"ECHA LOS CRISTALES Y TIRA DE LA PALANCA",
	"EL GRIMORIO: MEJORAS A CAMBIO DE MANÁ",
	"INSCRIBE RUNAS EN TUS HECHIZOS",
	"TU RANGO Y TUS HAZAÑAS",
]
## La jaula es la única estación cuyo nombre no salía ya en otro sitio.
# i18n
const NEST_NAME: String = "JAULA DE FAMILIARES"

## Oculto todo (dentro de la casucha, como la guía).
var suppressed: bool = false
var camera: Camera3D

var _stations: Array[Station] = []


class Station:
	extends RefCounted
	var node: Node3D
	var at: Callable
	var title: String
	var desc: String
	var learn: StringName
	var name_label: Label
	var desc_label: Label
	var screen := Vector2.ZERO
	var dist: float = 0.0
	var alpha: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Events.locale_changed.connect(_relocalize)


## Busca las estaciones en el mundo y las registra (las que no estén, se saltan).
func bind_world(world: Node) -> void:
	var pylon := world.get_node_or_null(^"ManaPylon") as ManaPylon
	if pylon:
		var top := func() -> Vector3: return pylon.mouth_position() + Vector3.UP * 1.4
		add(pylon, top, "PILÓN DE MANÁ", HELP[0], &"lever")
	var crusher := world.get_node_or_null(^"ManaPylon/Crusher") as CrystalCrusher
	if crusher:
		add(crusher, crusher.marker_position, "TRITURADORA", HELP[1], &"lever")
	var sanctum := world.get_node_or_null(^"Sanctum") as Sanctum
	if sanctum:
		add(sanctum, sanctum.marker_position, "SANTUARIO", HELP[2], &"grimoire")
	var table := world.get_node_or_null(^"Sanctum/RuneTable") as RuneTable
	if table:
		add(table, table.marker_position, "MESA DE RUNAS", HELP[3], &"rune_table")
	var mirror := world.get_node_or_null(^"Sanctum/ArchmageMirror") as ArchmageMirror
	if mirror:
		add(mirror, mirror.marker_position, "ESPEJO DEL ARCHIMAGO", HELP[4], &"mirror")
	var nest := world.get_node_or_null(^"FamiliarFlock/FamiliarNest") as Node3D
	if nest:
		var over := func() -> Vector3: return nest.global_position + Vector3.UP * 3.2
		add(nest, over, NEST_NAME, "", &"")


## Registra una estación. `at` devuelve el punto del mundo sobre el que va el nombre; `learn` es
## la acción de `Progression.times` que, hecha una vez, quita la línea de ayuda (vacía: sin ella).
func add(node: Node3D, at: Callable, title: String, desc: String, learn: StringName) -> void:
	var s := Station.new()
	s.node = node
	s.at = at
	s.title = title
	s.desc = desc
	s.learn = learn
	s.name_label = _label(UiFonts.BOLD, C_NAME)
	s.desc_label = _label(UiFonts.BODY, C_DESC)
	_stations.append(s)
	_relocalize_one(s)


func _process(_delta: float) -> void:
	# 1) Dónde cae cada una y cuánto se ve; la línea de ayuda, sólo la más cercana a la mira.
	var shown: Array[Station] = []
	var focus: Station = null
	var center_x: float = size.x * 0.5
	for s: Station in _stations:
		_measure(s)
		if s.alpha <= 0.01:
			s.name_label.visible = false
			s.desc_label.visible = false
			continue
		shown.append(s)
		if focus == null or absf(s.screen.x - center_x) < absf(focus.screen.x - center_x):
			focus = s
	# 2) De la más cercana a la más lejana; si una pisa a otra ya puesta, sube hasta quedar libre.
	shown.sort_custom(func(a: Station, b: Station) -> bool: return a.dist < b.dist)
	var placed: Array[Rect2] = []
	for s: Station in shown:
		_place(s, s == focus and _needs_help(s), placed)


## Proyecta la estación y calcula su alfa (0: no se ve).
func _measure(s: Station) -> void:
	s.alpha = 0.0
	if suppressed or camera == null or not is_instance_valid(s.node):
		return
	if not s.node.is_visible_in_tree():
		return
	var world: Vector3 = s.at.call()
	s.dist = camera.global_position.distance_to(world)
	if s.dist >= FAR_M or s.dist <= GONE_M or camera.is_position_behind(world):
		return
	s.screen = camera.unproject_position(world)
	var sz: Vector2 = size
	if s.screen.x < 0.0 or s.screen.x > sz.x or s.screen.y < 0.0 or s.screen.y > sz.y:
		return
	s.alpha = (1.0 - smoothstep(FULL_M, FAR_M, s.dist)) * smoothstep(GONE_M, NEAR_M, s.dist)


func _needs_help(s: Station) -> bool:
	return s.desc != "" and GameState.progression.times(s.learn) == 0


func _place(s: Station, help: bool, placed: Array[Rect2]) -> void:
	var line: float = float(UiFonts.LINE)
	var w: float = _text_w(UiFonts.BOLD, s.name_label.text)
	if help:
		w = maxf(w, _text_w(UiFonts.BODY, s.desc_label.text))
	var h: float = line * (2.0 if help else 1.0)
	var box := Rect2(s.screen.x - w * 0.5 - 2.0, s.screen.y - line, w + 4.0, h)
	box.position.x = clampf(box.position.x, SIDE, size.x - SIDE - box.size.x)
	for _try: int in 6:
		var hit: bool = false
		for r: Rect2 in placed:
			if r.intersects(box):
				box.position.y = r.position.y - box.size.y - 1.0
				hit = true
		if not hit:
			break
	placed.append(box)
	var x: float = box.get_center().x - LABEL_W * 0.5
	s.name_label.position = Vector2(x, box.position.y).round()
	s.name_label.modulate.a = s.alpha
	s.name_label.visible = true
	s.desc_label.visible = help
	if help:
		s.desc_label.position = Vector2(x, box.position.y + line).round()
		s.desc_label.modulate.a = s.alpha * 0.9


static func _text_w(font: Font, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFonts.SMALL).x


func _label(font: Font, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", UiFonts.SMALL)
	l.add_theme_color_override(&"font_color", col)
	UiFonts.outline(l, C_SHADOW)
	l.size = Vector2(LABEL_W, UiFonts.LINE)
	l.visible = false
	add_child(l)
	return l


func _relocalize() -> void:
	for s: Station in _stations:
		_relocalize_one(s)


func _relocalize_one(s: Station) -> void:
	s.name_label.text = tr(s.title)
	s.desc_label.text = tr(s.desc) if s.desc != "" else ""
