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
signal spell_combine_started(recipe: SpellRecipe)
signal recipe_discovered(recipe: SpellRecipe)
signal spell_impacted(hit: SpellHit)
signal spell_fizzled(position: Vector3)
signal streak_changed(streak: int)
signal streak_milestone(streak: int)
signal streak_broken(final_streak: int)

# --- Fragmentos ---
signal shard_collected(type: ShardType, count_of_type: int, position: Vector3)
signal shard_targeted(type: ShardType)
signal bag_changed(count: int, capacity: int)
signal bag_full

# --- Pilón y Santuario ---
## Un fragmento sale de la bolsa hacia el Pilón (aún no ha llegado).
signal shard_sent_to_pylon(type: ShardType)
## Abrir el Grimorio: `at_sanctum` = true si se puede comprar (junto al atril).
signal grimoire_requested(at_sanctum: bool)
signal grimoire_opened
signal grimoire_closed
## Mensaje para el HUD ("¡BOLSA LLENA!", "¡MEJORA DISPONIBLE!"...).
signal hint(text: String, color: Color)
