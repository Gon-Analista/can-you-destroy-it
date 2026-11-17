class_name CrystalClusterBuilder
extends RefCounted
## Mallas de los fragmentos sueltos del cristal. (El Cristal Madre ya no es una malla fija: es un
## volumen excavable, ver CrystalVolume y tools/crystal_volume.py.)


## Malla de un fragmento suelto del tipo `type`: prisma irregular con punta.
## La astilla es una aguja fina; el fragmento grande, un trozo grueso de 6 caras.
static func build_shard_mesh(type: ShardType, seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st: SurfaceTool = MeshKit.begin()
	var r: float = type.radius * rng.randf_range(0.85, 1.15)
	var h: float = type.height * rng.randf_range(0.85, 1.2)
	var tip: float = type.tip * rng.randf_range(0.85, 1.2)
	var axis := Vector3(rng.randf_range(-0.2, 0.2), 1.0, rng.randf_range(-0.2, 0.2)).normalized()
	MeshKit.add_prism(
		st, -axis * h * 0.4, axis, r, h, tip, type.sides, Color.WHITE, Color.WHITE, rng, 0.2, 0.85
	)
	return MeshKit.commit(st)
