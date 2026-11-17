class_name MagicLayer
extends TextureRect
## Capa de magia en alta definición ("HD-2D", decisión 2026-11-17): el valle y las manos se
## dibujan en pixel art a 640x360, pero los hechizos se dibujan aparte a la resolución de la
## pantalla, con resplandor (glow HDR), partículas suaves, estelas y destellos, como en los
## juegos modernos. Se componen con alfa premultiplicado encima del mundo.
##
## Cómo: una SubViewport que comparte el mundo 3D con la del valle y una cámara que copia cada
## fotograma a la del jugador; esa cámara sólo ve la capa visual `MAGIC_LAYER` y la del valle
## la excluye. Los hechizos no quedan tapados por el mundo (casi siempre están delante: vuelan
## hacia el cristal y estallan en su superficie).

## Capa visual (bit) de todo lo que es magia HD.
const MAGIC_LAYER: int = 1 << 10

var _viewport: SubViewport
var _camera: Camera3D
var _source: Camera3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Sin esto, el tamaño mínimo sería el de la textura (nativa) y no cabría en 640x360.
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := CanvasItemMaterial.new()
	# Alfa premultiplicado: lo opaco (cuerpo del fuego) tapa el fondo con su color y lo aditivo
	# (núcleos, resplandor) suma luz. Así el color no se lava sobre el cielo claro.
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	material = mat
	_viewport = SubViewport.new()
	_viewport.name = "MagicViewport"
	_viewport.transparent_bg = true
	_viewport.audio_listener_enable_3d = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.use_hdr_2d = false
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.name = "MagicCamera"
	_camera.cull_mask = MAGIC_LAYER
	_camera.environment = _make_environment()
	_viewport.add_child(_camera)
	_camera.current = true
	texture = _viewport.get_texture()
	get_window().size_changed.connect(_resize)
	_resize()


## La cámara del jugador (la del valle) a la que se pega la de la magia.
func bind(world_camera: Camera3D) -> void:
	_source = world_camera
	_source.cull_mask &= ~MAGIC_LAYER
	_viewport.world_3d = world_camera.get_world_3d()


## Copia la cámara del valle después de que se haya movido (sacudida incluida).
func _process(_delta: float) -> void:
	if _source == null:
		return
	_camera.global_transform = _source.global_transform
	_camera.fov = _source.fov
	_camera.near = _source.near
	_camera.far = _source.far
	_camera.h_offset = _source.h_offset
	_camera.v_offset = _source.v_offset


## Resolución nativa de la zona de juego (640x360 escalado por enteros).
func _resize() -> void:
	var win: Vector2i = get_window().size
	var k: int = maxi(1, mini(win.x / 640, win.y / 360))
	_viewport.size = Vector2i(640 * k, 360 * k)


func _make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# Sólo radios cortos y medios: un resplandor ancho lava toda la pantalla de blanco.
	var levels: PackedFloat32Array = [0.0, 1.0, 0.8, 0.45, 0.0, 0.0, 0.0]
	for i: int in 7:
		env.set_glow_level(i, levels[i])
	return env


## Pone en la capa de magia todos los nodos visuales de `node` (y él mismo).
static func tag(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = MAGIC_LAYER
	for c: Node in node.get_children():
		tag(c)
