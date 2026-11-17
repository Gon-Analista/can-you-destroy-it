class_name ImpactFx
extends Node3D
## Pool de estallidos de impacto: destellos en estrella, esquirlas con gravedad, anillo que se
## expande y un flash de luz. Todo preasignado; play() sólo reposiciona y reinicia.

const RING_SHADER: Shader = preload("res://fx/ring.gdshader")
const BLAST_SHADER: Shader = preload("res://fx/impact_blast.gdshader")
## Duración del estallido (s).
const BLAST_SEC: float = 0.4
## Diámetro del estallido respecto al radio de grieta del golpe.
const BLAST_PER_CRACK: float = 2.6

@export var pool_size: int = 10

var _bursts: Array[Node3D] = []
var _sparkles: Array[GPUParticles3D] = []
var _chips: Array[GPUParticles3D] = []
var _rings: Array[MeshInstance3D] = []
var _ring_mats: Array[ShaderMaterial] = []
var _lights: Array[OmniLight3D] = []
var _blasts: Array[MeshInstance3D] = []
var _blast_mats: Array[ShaderMaterial] = []
var _default_ramp: GradientTexture1D
var _ramps: Dictionary[Gradient, GradientTexture1D] = {}
var _age: PackedFloat32Array = []
var _light_peak: PackedFloat32Array = []
var _next: int = 0


func _ready() -> void:
	var sparkle_mat := _particle_draw_material(PixelTextures.star())
	var chip_mat := _particle_draw_material(PixelTextures.chip())
	for i: int in pool_size:
		var burst := Node3D.new()
		burst.name = "Burst%d" % i
		add_child(burst)
		var sparkles := _make_particles(sparkle_mat, 0.7, _sparkle_process(), 0.8)
		burst.add_child(sparkles)
		var chips := _make_particles(chip_mat, 0.28, _chip_process(), 1.2)
		burst.add_child(chips)
		var ring := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1, 1)
		ring.mesh = quad
		var rm := ShaderMaterial.new()
		rm.shader = RING_SHADER
		rm.render_priority = 1
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.visible = false
		burst.add_child(ring)
		var blast := MeshInstance3D.new()
		var bquad := QuadMesh.new()
		bquad.size = Vector2.ONE
		blast.mesh = bquad
		var bm := ShaderMaterial.new()
		bm.shader = BLAST_SHADER
		bm.render_priority = 8
		blast.material_override = bm
		blast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blast.top_level = true
		blast.visible = false
		burst.add_child(blast)
		_blasts.append(blast)
		_blast_mats.append(bm)
		var light := OmniLight3D.new()
		light.light_color = Color("#bff3ff")
		light.omni_range = 9.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.visible = false
		burst.add_child(light)
		_bursts.append(burst)
		_sparkles.append(sparkles)
		_chips.append(chips)
		_rings.append(ring)
		_ring_mats.append(rm)
		_lights.append(light)
		_age.append(-1.0)
		_light_peak.append(0.0)
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.45, 0.7, 0.9])
	g.colors = PackedColorArray(
		[
			Color(1.8, 1.9, 2.0),
			Color("#c9f6ff"),
			Color("#a5dae5"),
			Color("#458fb8"),
			Color(0.16, 0.29, 0.53, 0.4),
		]
	)
	_default_ramp = _ramp_texture(g)
	set_process(false)


func _ramp_texture(g: Gradient) -> GradientTexture1D:
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.use_hdr = true
	tex.width = 64
	return tex


func play(pos: Vector3, normal: Vector3, tier: SpellTier, resonant: bool) -> void:
	var i: int = _next
	_next = (_next + 1) % pool_size
	var burst: Node3D = _bursts[i]
	var up: Vector3 = normal.normalized()
	var side: Vector3 = up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
	burst.global_transform = Transform3D(
		Basis(side, up, side.cross(up)).orthonormalized(), pos + up * 0.1
	)
	var power: float = 2.2 if resonant else 1.0
	var sparkles: GPUParticles3D = _sparkles[i]
	sparkles.amount = maxi(4, int(tier.impact_particles * power))
	var tinted: bool = tier.impact_tint.a > 0.0
	(sparkles.process_material as ParticleProcessMaterial).color = (
		Color("#ffe7a3") if resonant else (tier.impact_tint if tinted else Color("#d8fbff"))
	)
	sparkles.restart()
	var chips: GPUParticles3D = _chips[i]
	chips.amount = maxi(4, int(tier.impact_particles * 0.8 * power))
	chips.restart()
	var ring: MeshInstance3D = _rings[i]
	ring.scale = Vector3.ONE * (tier.crack_radius * 5.0 * (1.6 if resonant else 1.0))
	ring.visible = true
	_ring_mats[i].set_shader_parameter(
		"color",
		Color("#ffd27a") if resonant else (tier.impact_tint if tinted else Color("#c9f6ff"))
	)
	_ring_mats[i].set_shader_parameter("progress", 0.0)
	var light: OmniLight3D = _lights[i]
	light.light_color = (
		Color("#ffd27a") if resonant else (tier.impact_tint if tinted else Color("#bff3ff"))
	)
	light.visible = true
	_light_peak[i] = tier.light_energy * power
	light.light_energy = _light_peak[i]
	# Estallido de píxeles: con los colores de la estela del hechizo, un poco hacia la cámara.
	var blast: MeshInstance3D = _blasts[i]
	var cam: Camera3D = get_viewport().get_camera_3d()
	var toward: Vector3 = (cam.global_position - pos).normalized() if cam else up
	blast.global_position = pos + up * 0.15 + toward * 0.4
	blast.scale = Vector3.ONE * tier.crack_radius * BLAST_PER_CRACK * (1.5 if resonant else 1.0)
	var ramp: GradientTexture1D = _default_ramp
	if tier.trail_ramp:
		if not _ramps.has(tier.trail_ramp):
			_ramps[tier.trail_ramp] = _ramp_texture(tier.trail_ramp)
		ramp = _ramps[tier.trail_ramp]
	_blast_mats[i].set_shader_parameter("ramp", ramp)
	_blast_mats[i].set_shader_parameter("seed", randf() * 10.0)
	_blast_mats[i].set_shader_parameter("progress", 0.0)
	# El estallido pixel art queda sustituido por el impacto HD (HdImpact).
	blast.visible = false
	_age[i] = 0.0
	set_process(true)


func _process(delta: float) -> void:
	var any: bool = false
	for i: int in pool_size:
		if _age[i] < 0.0:
			continue
		_age[i] += delta
		var t: float = _age[i]
		_ring_mats[i].set_shader_parameter("progress", clampf(t / 0.35, 0.0, 1.0))
		_lights[i].light_energy = _light_peak[i] * maxf(0.0, 1.0 - t / 0.28)
		_blast_mats[i].set_shader_parameter("progress", clampf(t / BLAST_SEC, 0.0, 1.0))
		if t > 0.35:
			_rings[i].visible = false
		if t > BLAST_SEC:
			_blasts[i].visible = false
			_lights[i].visible = false
			_age[i] = -1.0
		else:
			any = true
	if not any:
		set_process(false)


func _make_particles(
	draw_mat: StandardMaterial3D, size: float, process: ParticleProcessMaterial, lifetime: float
) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.95
	p.lifetime = lifetime
	p.amount = 16
	p.local_coords = false
	p.process_material = process
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = draw_mat
	p.draw_pass_1 = quad
	return p


func _particle_draw_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.disable_fog = true
	m.render_priority = 2
	return m


func _sparkle_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 70.0
	m.initial_velocity_min = 5.0
	m.initial_velocity_max = 12.0
	m.gravity = Vector3(0, -6, 0)
	m.damping_min = 3.0
	m.damping_max = 5.0
	m.scale_min = 0.5
	m.scale_max = 1.3
	m.color = Color("#d8fbff")
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(0.55, 0.9, 1.0, 0.0))
	ramp.add_point(0.6, Color(0.8, 0.97, 1.0, 1.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_ramp = tex
	return m


func _chip_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 55.0
	m.initial_velocity_min = 3.0
	m.initial_velocity_max = 7.0
	m.gravity = Vector3(0, -14, 0)
	m.scale_min = 0.7
	m.scale_max = 1.4
	m.color = Color("#a5dae5")
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(0.27, 0.56, 0.72, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_ramp = tex
	return m
