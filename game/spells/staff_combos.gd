class_name StaffCombos
extends RefCounted
## El báculo (GDD 5.2: "más adelante se desbloquea un tercer 'espacio' (el báculo) para
## combinaciones triples"; GDD 7, hito de la rama de Elementos). Lleva su propio elemento en la
## gema (R o la rueda lo cambian entre los despiertos). Al juntar las manos, si la mano
## izquierda, la derecha y el báculo forman una receta triple, sale la triple en vez de la
## pareja (con el daño de los tres, la Potencia del báculo y la carga acortada por el Foco).
##
## Aquí sólo el estado y las reglas (sin nodos): qué elemento lleva, si se tiene y qué triple
## forman tres elementos. Lo usan SpellCaster, el Libro de Combinaciones y los tests.

## Todas las combinaciones triples, en el orden del Libro de Combinaciones.
const TRIPLES: Array[SpellRecipe] = [
	preload("res://data/spells/recipe_elemental_storm.tres"),
	preload("res://data/spells/recipe_thunder_glacier.tres"),
	preload("res://data/spells/recipe_supernova.tres"),
	preload("res://data/spells/recipe_star_rain.tres"),
	preload("res://data/spells/recipe_magma_tide.tres"),
]
## Mejora que da el báculo y sus estadísticas (data/upgrades/staff*.tres).
const UNLOCK_UPGRADE: StringName = &"staff"
const FOCUS_STAT: StringName = &"staff_focus"
## Elemento con el que llega la gema la primera vez: el Rayo, que con Chispa y Escarcha en las
## manos ya hace la Tormenta Elemental.
const FIRST_ELEMENT: StringName = &"bolt"

## Elemento de la gema (índice en SpellCaster.ELEMENTS); -1 = aún no tiene.
var element_index: int = -1


## Si el mago ya tiene el báculo (la mejora "Báculo").
static func owned() -> bool:
	return GameState.progression.get_level(UNLOCK_UPGRADE) > 0


## Triple que forman tres elementos (en cualquier orden), o null.
static func triple_for(a: StringName, b: StringName, c: StringName) -> SpellRecipe:
	for r: SpellRecipe in TRIPLES:
		if r.matches_triple(a, b, c):
			return r
	return null


## Segundos de carga de una combinación: el Foco del báculo acorta la de las triples.
static func charge_sec(recipe: SpellRecipe) -> float:
	if recipe.is_triple():
		return recipe.charge_sec * GameState.stat(FOCUS_STAT, 1.0)
	return recipe.charge_sec


## La gema despierta con su primer elemento (si no tenía): el Rayo si se conoce; si no, el
## último elemento despierto. Devuelve si ha cambiado.
func ensure_element(elements: Array[ElementDef]) -> bool:
	if element_index >= 0 or not owned():
		return false
	var fallback: int = -1
	for i: int in elements.size():
		if _awake(elements[i]):
			fallback = i
			if elements[i].id == FIRST_ELEMENT:
				element_index = i
				return true
	element_index = fallback
	return element_index >= 0


## La gema pasa al siguiente (`dir` = 1) o al anterior (-1) elemento despierto. Devuelve el
## índice nuevo, o -1 si no hay otro al que cambiar.
func cycle(elements: Array[ElementDef], dir: int = 1) -> int:
	if not owned():
		return -1
	ensure_element(elements)
	var n: int = elements.size()
	for step: int in range(1, n):
		var idx: int = wrapi(element_index + step * dir, 0, n)
		if _awake(elements[idx]):
			element_index = idx
			return idx
	return -1


## El elemento de la gema, o null si no hay báculo.
func element(elements: Array[ElementDef]) -> ElementDef:
	if not owned() or element_index < 0 or element_index >= elements.size():
		return null
	return elements[element_index]


static func _awake(el: ElementDef) -> bool:
	return el.unlock_upgrade == &"" or GameState.progression.get_level(el.unlock_upgrade) > 0
