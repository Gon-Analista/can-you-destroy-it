extends Node
## Bus de señales globales. Sólo declara señales: nada de lógica aquí.

signal crystal_hit(damage: int, position: Vector3)
signal essence_changed(essence: int, total: int)
signal shard_delivered(value: int)
signal mana_changed(mana: int)
signal pylon_changed(progress: int, ratio: float)
signal upgrade_bought(upgrade_id: StringName, level: int)
signal crystal_destroyed

# --- Sensación del golpe (prototipo de la chispa) ---
signal spell_cast(tier: SpellTier, hand_side: int)
signal spell_ready
signal spell_impacted(hit: SpellHit)
signal spell_fizzled(position: Vector3)
signal streak_changed(streak: int)
signal streak_milestone(streak: int)
signal streak_broken(final_streak: int)

# --- Fragmentos ---
signal shard_collected(type: ShardType, count_of_type: int, position: Vector3)
signal shard_targeted(type: ShardType)
