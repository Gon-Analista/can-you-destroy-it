class_name RankBadge
extends Control
## El rango del mago en el HUD, discreto: su escudo pequeño (x1) y su nombre bajo la barra del
## Pilón. En la subida de rango (`celebrate`, desde RankCeremony) el escudo destella en blanco, da
## un salto y suelta unas chispitas; el resto del tiempo no se redibuja.

const C_SHADOW := Color("#14183a")
const FLASH_SEC: float = 1.4

var _rank: int = 0
var _name: Label
var _flash: float = 0.0


func _ready() -> void:
	add_to_group(&"rank_badge")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(160, 20)
	_name = Label.new()
	_name.add_theme_font_override(&"font", UiFonts.BOLD)
	_name.add_theme_font_size_override(&"font_size", UiFonts.SMALL)
	_name.position = Vector2(RankCrest.SIZE.x + 4, 4)
	_name.size = Vector2(130, UiFonts.LINE)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFonts.outline(_name, C_SHADOW)
	add_child(_name)
	Events.locale_changed.connect(_refresh)
	_rank = GameState.rank()
	_refresh()
	set_process(false)


## Subida de rango: el escudo nuevo destella y salta.
func celebrate(rank: int) -> void:
	_rank = rank
	_refresh()
	_flash = 1.0
	set_process(true)


func _refresh() -> void:
	var def: RankDef = WizardRanks.def_of(_rank)
	_name.text = tr(def.display_name).to_upper()
	_name.add_theme_color_override(&"font_color", def.color_light)
	queue_redraw()


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta / FLASH_SEC)
	var def: RankDef = WizardRanks.def_of(_rank)
	_name.add_theme_color_override(&"font_color", def.color_light.lerp(Color.WHITE, _flash))
	_name.position.y = 4 - roundi(sin(minf(_flash * 3.0, 1.0) * PI) * 2.0)
	queue_redraw()
	if _flash <= 0.0:
		set_process(false)


func _draw() -> void:
	var hop: float = roundf(sin(clampf((1.0 - _flash) * 3.0, 0.0, 1.0) * PI) * 2.0 * _flash)
	var tint: Color = Color.WHITE.lerp(Color(3.0, 3.0, 3.0), _flash * 0.6)
	RankCrest.draw(self, _rank, Vector2(0, -hop), 1, tint)
	if _flash <= 0.0:
		return
	# Chispitas que salen del escudo.
	var def: RankDef = WizardRanks.def_of(_rank)
	var c := Vector2(8, 9)
	var r: float = 4.0 + (1.0 - _flash) * 14.0
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0 + 0.4
		var p: Vector2 = (c + Vector2(cos(a), sin(a)) * r).round()
		draw_rect(Rect2(p, Vector2.ONE), Color(def.color_light, _flash))
