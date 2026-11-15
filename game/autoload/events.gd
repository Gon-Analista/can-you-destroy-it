extends Node
## Bus de señales globales. Sólo declara señales: nada de lógica aquí.

signal crystal_hit(damage: int, position: Vector3)
signal essence_changed(essence: int, total: int)
signal shard_delivered(value: int)
signal mana_changed(mana: int)
signal pylon_changed(progress: int, ratio: float)
signal upgrade_bought(upgrade_id: StringName, level: int)
signal crystal_destroyed
