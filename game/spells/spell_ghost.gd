class_name SpellGhost
extends RefCounted
## Versión "fantasma" de un hechizo para los ecos del Arcano: el mismo aspecto (llama, Bola de
## Fuego, lanza...) teñido de violeta arcano, algo más pálido y más pequeño. Se calcula una vez
## por aspecto y se guarda en esta caché (la tiene SpellEchoes): los ecos no crean recursos al
## lanzarse (y se libera con ella). Las runas (RuneCaster) usan la misma caché con su propio color
## (`color`, `mix`): las chispas de más del Multidisparo, doradas; los rebotes, magenta.

## Violeta arcano hacia el que tiran los colores (se conserva el brillo HDR de cada uno).
const GHOST := Color(0.78, 0.52, 1.0)
## Cuánto tiran hacia el violeta (0 = igual, 1 = todo violeta).
const MIX: float = 0.6

## Color hacia el que tiran los colores y cuánto (el violeta arcano, salvo en las runas).
var color: Color = GHOST
var mix: float = MIX
var _tiers: Dictionary[SpellTier, SpellTier] = {}
var _visuals: Dictionary[SpellVisualDef, SpellVisualDef] = {}


func _init(p_color: Color = GHOST, p_mix: float = MIX) -> void:
	color = p_color
	mix = p_mix


## El nivel `tier` en versión fantasma (aspecto, estela, colores del impacto).
func tier(source: SpellTier) -> SpellTier:
	if source == null:
		return null
	if _tiers.has(source):
		return _tiers[source]
	var t: SpellTier = source.duplicate()
	t.visual = visual(source.visual)
	t.color_core = tint(source.color_core)
	t.color_glow = tint(source.color_glow)
	t.impact_tint = tint(source.impact_tint) if source.impact_tint.a > 0.0 else color
	t.orb_scale = source.orb_scale * 0.85
	# Golpe de eco: estallido y grieta algo menores que los del hechizo de verdad.
	t.crack_radius = source.crack_radius * 0.7
	t.light_energy = source.light_energy * 0.6
	t.trail_width = source.trail_width * 0.8
	t.trail_smoke = 0.0
	# Sin rugido propio: cada eco suena con su campanada (ver SpellCaster).
	t.flight_sfx = null
	t.echoes = 0
	if source.trail_ramp:
		t.trail_ramp = _tint_gradient(source.trail_ramp)
	_tiers[source] = t
	return t


## El aspecto `def` en versión fantasma.
func visual(source: SpellVisualDef) -> SpellVisualDef:
	if source == null:
		return null
	if _visuals.has(source):
		return _visuals[source]
	var v: SpellVisualDef = source.duplicate()
	if source.core_ramp:
		v.core_ramp = _tint_gradient(source.core_ramp)
	if source.sparkle_colors:
		v.sparkle_colors = _tint_gradient(source.sparkle_colors)
	var ribbons := PackedColorArray()
	for col: Color in source.ribbon_colors:
		ribbons.append(tint(col))
	v.ribbon_colors = ribbons
	v.flare_color = tint(source.flare_color)
	v.light_color = tint(source.light_color)
	v.body_intensity = source.body_intensity * 0.65
	v.glow_intensity = source.glow_intensity * 0.9
	v.core_spin = source.core_spin * 1.5
	# Sin onda de choque al llegar: con varios ecos seguidos sería un muro de anillos.
	v.release_flash = minf(source.release_flash, 0.4)
	v.seed = source.seed + 1000
	_visuals[source] = v
	return v


## Un color tirando hacia `color` (el violeta arcano) sin perder su brillo (HDR incluido).
func tint(col: Color) -> Color:
	var peak: float = maxf(col.r, maxf(col.g, col.b))
	var ghost := Color(color.r * peak, color.g * peak, color.b * peak, col.a)
	return col.lerp(ghost, mix)


func _tint_gradient(src: Gradient) -> Gradient:
	var g: Gradient = src.duplicate()
	var cols := PackedColorArray()
	for col: Color in src.colors:
		cols.append(tint(col))
	g.colors = cols
	return g
