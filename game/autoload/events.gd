extends Node
## Bus de señales globales. Sólo declara señales: nada de lógica aquí.

@warning_ignore("unused_signal")
signal crystal_hit(damage: int, position: Vector3)
@warning_ignore("unused_signal")
signal essence_changed(essence: int, total: int)
@warning_ignore("unused_signal")
signal shard_delivered(value: int)
@warning_ignore("unused_signal")
signal mana_changed(mana: int)
@warning_ignore("unused_signal")
signal pylon_changed(progress: int, ratio: float)
@warning_ignore("unused_signal")
signal upgrade_bought(upgrade_id: StringName, level: int)
@warning_ignore("unused_signal")
signal crystal_destroyed
## Se ha abierto una capa nueva del cristal (Corteza -> Manto Geódico -> ...).
@warning_ignore("unused_signal")
signal crystal_layer_changed(layer: CrystalLayerDef, index: int)
@warning_ignore("unused_signal")
signal geode_broken(position: Vector3)
## Un golpe dio en una Vena Resonante con su elemento débil (`element`: el de la vena).
@warning_ignore("unused_signal")
signal vein_hit(hit: SpellHit, element: StringName)
## El Pilón pasa una de sus marcas talladas (índice en ManaPylon.MARKS). Sólo una vez cada una.
@warning_ignore("unused_signal")
signal pylon_milestone(index: int, mark: float)
## La Resonancia del Pilón lanza un rayo al cristal (`at`: dónde da).
@warning_ignore("unused_signal")
signal pylon_bolt(at: Vector3)
## El mago sube de rango (`WizardRanks.RANKS`). Una vez por rango; al cargar no se emite.
@warning_ignore("unused_signal")
signal rank_changed(rank: int, previous: int)

# --- Lágrimas del Núcleo (GDD 6.1) y el final ---
## Brota una Lágrima del Núcleo del Corazón Cristalino (aún hay que recogerla).
@warning_ignore("unused_signal")
signal tear_dropped(position: Vector3)
## El jugador recoge una Lágrima: ya está en el contador.
@warning_ignore("unused_signal")
signal tear_collected(position: Vector3)
## Cambian las Lágrimas para gastar (al recoger o al inscribir con ellas).
@warning_ignore("unused_signal")
signal tears_changed(tears: int)
## El cristal llega al 99 %: el Núcleo queda expuesto y el Grimorio enseña la Gran Convergencia.
## Una sola vez por partida (al cruzar el umbral).
@warning_ignore("unused_signal")
signal grimoire_final_revealed
## Se inscribe la Gran Convergencia (nodo `grand_convergence`): ya se puede lanzar el hechizo
## final. Equivale a `GameState.has_upgrade(&"grand_convergence")` pasando a true.
@warning_ignore("unused_signal")
signal grand_convergence_unlocked
## El cristal ya se ha resquebrajado y desprendido: el Núcleo flota a la vista (ver CoreReveal).
@warning_ignore("unused_signal")
signal core_revealed
## Las manos empiezan a cargar la Gran Convergencia (`charging` true) o dejan de hacerlo.
@warning_ignore("unused_signal")
signal convergence_charging(charging: bool)
## La Gran Convergencia rompe el Núcleo: fin de la partida (GDD 9). Una sola vez.
@warning_ignore("unused_signal")
signal game_completed

# --- Sensación del golpe (prototipo de la chispa) ---
@warning_ignore("unused_signal")
signal spell_cast(tier: SpellTier, hand_side: int)
@warning_ignore("unused_signal")
signal spell_ready
@warning_ignore("unused_signal")
signal spell_combine_started(recipe: SpellRecipe)
## Carga por etapas de un combinado (ver ChargeStages): `stage` 0 al empezar (con `total`
## etapas), 1..total al completar cada una y -1 al terminar (lanzada o cancelada).
@warning_ignore("unused_signal")
signal spell_charge_stage(stage: int, total: int)
@warning_ignore("unused_signal")
signal recipe_discovered(recipe: SpellRecipe)
@warning_ignore("unused_signal")
signal spell_impacted(hit: SpellHit)
@warning_ignore("unused_signal")
signal spell_fizzled(position: Vector3)
## Daño por quemadura (el fuego que queda ardiendo en el cristal).
@warning_ignore("unused_signal")
signal crystal_burned(damage: int, position: Vector3)
@warning_ignore("unused_signal")
signal streak_changed(streak: int)
@warning_ignore("unused_signal")
signal streak_milestone(streak: int)
@warning_ignore("unused_signal")
signal streak_broken(final_streak: int)

# --- Fragmentos ---
@warning_ignore("unused_signal")
signal shard_collected(type: ShardType, count_of_type: int, position: Vector3)
@warning_ignore("unused_signal")
signal shard_targeted(type: ShardType)
@warning_ignore("unused_signal")
signal bag_changed(count: int, capacity: int)
@warning_ignore("unused_signal")
signal bag_full

# --- Pilón y Santuario ---
## Un fragmento sale de la bolsa hacia el Pilón (aún no ha llegado).
@warning_ignore("unused_signal")
signal shard_sent_to_pylon(type: ShardType)
## Abrir el Grimorio: `at_sanctum` = true si se puede comprar (junto al atril).
@warning_ignore("unused_signal")
signal grimoire_requested(at_sanctum: bool)
## Abrir las estadísticas del Espejo del Archimago (F junto al espejo).
@warning_ignore("unused_signal")
signal mirror_requested
## Abrir el Grimorio por una página (id del elemento de `Grimoire.PAGES`): la Vitrina del Báculo.
@warning_ignore("unused_signal")
signal grimoire_page_requested(page_id: StringName)
## Abrir la Mesa de Runas (F junto a la mesa, ya abierta al 10 % del Pilón).
@warning_ignore("unused_signal")
signal rune_table_requested
## Se inscribió o se borró una runa, o se compró un nivel o una ranura (manos, mesa, HUD).
@warning_ignore("unused_signal")
signal runes_changed
@warning_ignore("unused_signal")
signal menu_opened
@warning_ignore("unused_signal")
signal menu_closed
## El jugador cambió de idioma en Opciones: los textos fijos se rehacen.
@warning_ignore("unused_signal")
signal locale_changed
@warning_ignore("unused_signal")
signal grimoire_opened
@warning_ignore("unused_signal")
signal grimoire_closed
## Mensaje para el HUD ("¡BOLSA LLENA!", "¡MEJORA DISPONIBLE!"...).
@warning_ignore("unused_signal")
signal hint(text: String, color: Color)

# --- Bichos del valle ---
## Un bicho reventó (`critter_id`: id de su CritterDef).
@warning_ignore("unused_signal")
signal critter_popped(at: Vector3, critter_id: StringName)
