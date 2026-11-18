extends Node
## Bus de señales globales. Sólo declara señales: nada de lógica aquí.

signal crystal_hit(damage: int, position: Vector3)
signal essence_changed(essence: int, total: int)
signal shard_delivered(value: int)
signal mana_changed(mana: int)
signal pylon_changed(progress: int, ratio: float)
signal upgrade_bought(upgrade_id: StringName, level: int)
signal crystal_destroyed
## Se ha abierto una capa nueva del cristal (Corteza -> Manto Geódico -> ...).
signal crystal_layer_changed(layer: CrystalLayerDef, index: int)
signal geode_broken(position: Vector3)
## Un golpe dio en una Vena Resonante con su elemento débil (`element`: el de la vena).
signal vein_hit(hit: SpellHit, element: StringName)
## El Pilón pasa una de sus marcas talladas (índice en ManaPylon.MARKS). Sólo una vez cada una.
signal pylon_milestone(index: int, mark: float)
## La Resonancia del Pilón lanza un rayo al cristal (`at`: dónde da).
signal pylon_bolt(at: Vector3)

# --- Lágrimas del Núcleo (GDD 6.1) y el final ---
## Brota una Lágrima del Núcleo del Corazón Cristalino (aún hay que recogerla).
signal tear_dropped(position: Vector3)
## El jugador recoge una Lágrima: ya está en el contador.
signal tear_collected(position: Vector3)
## Cambian las Lágrimas para gastar (al recoger o al inscribir con ellas).
signal tears_changed(tears: int)
## El cristal llega al 99 %: el Núcleo queda expuesto y el Grimorio enseña la Gran Convergencia.
## Una sola vez por partida (al cruzar el umbral).
signal grimoire_final_revealed
## Se inscribe la Gran Convergencia (nodo `grand_convergence`): ya se puede lanzar el hechizo
## final. Equivale a `GameState.has_upgrade(&"grand_convergence")` pasando a true.
signal grand_convergence_unlocked

# --- Sensación del golpe (prototipo de la chispa) ---
signal spell_cast(tier: SpellTier, hand_side: int)
signal spell_ready
signal spell_combine_started(recipe: SpellRecipe)
## Carga por etapas de un combinado (ver ChargeStages): `stage` 0 al empezar (con `total`
## etapas), 1..total al completar cada una y -1 al terminar (lanzada o cancelada).
signal spell_charge_stage(stage: int, total: int)
signal recipe_discovered(recipe: SpellRecipe)
signal spell_impacted(hit: SpellHit)
signal spell_fizzled(position: Vector3)
## Daño por quemadura (el fuego que queda ardiendo en el cristal).
signal crystal_burned(damage: int, position: Vector3)
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
signal menu_opened
signal menu_closed
## El jugador cambió de idioma en Opciones: los textos fijos se rehacen.
signal locale_changed
signal grimoire_opened
signal grimoire_closed
## Mensaje para el HUD ("¡BOLSA LLENA!", "¡MEJORA DISPONIBLE!"...).
signal hint(text: String, color: Color)

# --- Bichos del valle ---
## Un bicho reventó (`critter_id`: id de su CritterDef).
signal critter_popped(at: Vector3, critter_id: StringName)
