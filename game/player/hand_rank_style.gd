class_name HandRankStyle
extends Node
## Las manos cambian con el rango del mago (RankDef: gema del brazalete, ribete de la manga,
## runas del puño y tela), con un shader sobre los sprites de Sprite AI, sin arte nuevo. Al cargar
## se ponen sin más; en la ceremonia de subida (`celebrate`) una línea de luz sube por la manga.

const SHADER: Shader = preload("res://player/hands/hand_rank.gdshader")
## Lo que dura la luz de la subida (s).
const FLASH_SEC: float = 1.6

var _mat: ShaderMaterial
var _flash: float = 0.0


func _ready() -> void:
	add_to_group(&"hand_rank_style")
	set_process(false)


## Pone el material a los sprites de las manos con el aspecto del rango actual.
func bind(sprites: Array[Sprite2D]) -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	for s: Sprite2D in sprites:
		s.material = _mat
	apply(GameState.rank())


## Aspecto del rango `rank`, sin destello.
func apply(rank: int) -> void:
	if _mat == null:
		return
	var def: RankDef = WizardRanks.def_of(rank)
	_mat.set_shader_parameter("gem_color", def.hand_gem)
	_mat.set_shader_parameter("trim_color", def.hand_trim)
	_mat.set_shader_parameter("rune_color", def.hand_runes)
	_mat.set_shader_parameter("sleeve_color", def.hand_sleeve)
	_mat.set_shader_parameter("prismatic", 1.0 if def.hand_prismatic else 0.0)


## Subida de rango: el aspecto nuevo con la luz que recorre la manga (lo llama RankCeremony).
func celebrate(rank: int) -> void:
	apply(rank)
	_flash = 1.0
	set_process(true)


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta / FLASH_SEC)
	# La luz sube deprisa y se apaga suave.
	_mat.set_shader_parameter("flash", _flash)
	if _flash <= 0.0:
		set_process(false)
