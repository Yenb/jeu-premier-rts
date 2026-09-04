extends RefCounted

# A ajouter a CARTE.md dans le prochain chantier d'inventaire -- mecanisme
# non encore documente dans la carte.
#
# PEUPLEMENT : orchestrateur generique d'une population homogene d'individus.
# Alloue un pool de N slots portes par UN MultiMesh unique + UNE instance
# RenderingServer directe qui pointe vers ce MultiMesh (patron
# rendu_terrain_multimesh.gd:853-870 § S6, chemin "instances RS directes").
# Consequence : UN seul draw call pour toute la population, quelle que soit
# N. Le consommateur (banc, systeme de jeu) tient le pool en donnee
# (Dictionary), lit et ecrit ses champs, decide du comportement de chaque
# individu.
#
# CE MODULE NE CONNAIT AUCUN NOM DE CONTENU. Il ne parle d'aucune categorie
# du monde. Aucun type_id, aucun mesh_ref n'est cite en dur ici. Ce sont
# toujours des Strings opaques recues en parametre, resolues via un catalogue
# passe par le consommateur. Test permanent : si une String qui nomme une
# chose du jeu apparait ici, une categorie s'est glissee.
#
# CE MODULE N'EMBARQUE AUCUN COMPORTEMENT. Errance, chasse, ordre, cadence
# de tick, choix de politique -- rien de tout cela n'est ici. Le consommateur
# itere pool.individus, pose velocite_desiree_horizontale, appelle
# Tick.tick_entite lui-meme, puis appelle Peuplement.ecrire_transform pour
# refleter la nouvelle position sur le rendu. Peuplement est un orchestrateur
# de population, pas un moteur d'IA.
#
# CE MODULE N'A AUCUN ETAT. Fonctions static, pas de var membre, aucun cache
# entre appels. Toute donnee de vie du pool est dans le Dictionary retourne
# par creer_pool -- le consommateur en est le seul depositaire.
#
# Aucun nom de classe global declare (doctrine CLAUDE.md) : preload("res://scripts/peuplement.gd").
#
# ---- STRUCTURE DU POOL (Dictionary retourne par creer_pool) ----
# {
#   individus       : Array de Dictionary (chacun est un objet Objet.fabriquer),
#   id_to_index     : Dictionary id:String -> int (index dans individus),
#   slots_libres    : Array[int] (LIFO des slots dispo dans le MultiMesh),
#   mm              : MultiMesh (reference forte, N slots -- issue #80479 :
#                     sans ref forte GDScript, GC -> RID invalide, instance
#                     disparait silencieusement),
#   rid             : RID (UNE seule instance RS, base = mm.get_rid()),
#   scenario        : RID (World3D scenario -- garde pour trace),
#   taille_max      : int,
#   _counter        : int (compteur d'id, seul champ prefixe _ dans le pool),
# }
#
# ---- API PUBLIQUE ----
# static creer_pool(taille_max, mesh, scenario) -> Dictionary
#   Alloue le MultiMesh (N slots, mm.mesh = mesh, TRANSFORM_3D), puis UNE
#   instance RS pointant vers lui. scenario pose (obligatoire, issue
#   godotengine/godot#77113). custom_aabb TRES LARGE (Godot ne cull pas par
#   instance de MultiMesh, godot-proposals#10669 : le culling se decide sur
#   l'AABB du MultiMesh entier, jamais par slot). Tous les slots demarrent
#   avec une transform d'echelle NULLE (invisibles). slots_libres initialise
#   [0..N-1] LIFO. Rend le Dictionary complet, ou {} sur echec (taille_max
#   <= 0, mesh null, scenario invalide).
#
# static spawn(pool, catalogue, type_id, position, monde) -> String
#   Alloue un slot libre, appelle Objet.fabriquer pour construire l'individu,
#   l'inscrit dans pool.individus / pool.id_to_index, pose la transform du
#   slot dans le MultiMesh a la position demandee, inscrit dans le monde si
#   non null. Ecrit individu.proprietes._slot = slot (champ technique prefixe
#   _). Rend "" et remet le slot dans slots_libres si Objet.fabriquer refuse
#   (composition invalide, materiau absent). Rend "" sans allouer si
#   pool.slots_libres est vide (pool sature) -- _counter n'incremente pas.
#
# static retirer(pool, id, monde) -> void
#   Remet le slot du MultiMesh a la transform "invisible" (echelle nulle),
#   libere le slot dans slots_libres, retire l'individu du pool par
#   swap-remove (O(1)), retire du monde si non null. Silencieux sur id
#   absent. Le parametre monde est facultatif par symetrie avec spawn --
#   l'ajout est justifie par le choix Yael d'utiliser monde.retirer (ecart
#   framework documente en tete de monde.gd, CARTE.md §4781 amende par le
#   meme chantier).
#
# static ecrire_transform(pool, id) -> void
#   Depuis individu.position courante, pose mm.set_instance_transform sur le
#   slot de l'individu. Silencieux sur id absent.
#
# static ecrire_transform_index(pool, index) -> void
#   Meme geste que ecrire_transform, mais recoit l'INDEX de l'individu dans
#   pool.individus au lieu de son id String -- saute le lookup id_to_index.
#   Utile a un consommateur qui itere deja pool.individus par index (banc de
#   population homogene ou la boucle _physics_process n'a pas besoin du hash).
#   Silencieux sur index hors bornes.
#
# static detruire_pool(pool) -> void
#   Free la RID (sinon fuite : le SceneTree ne nettoie pas les instances RS
#   directes), vide toutes les structures. mm et sa ref forte tombent
#   naturellement quand le Dictionary est libere.
#
# ---- POURQUOI MULTIMESH + N SLOTS PLUTOT QUE N INSTANCES RS + MESH ----
# Un livrable intermediaire avait choisi N instances RS + base=Mesh partage
# (perte du batching : N draw calls a 10 000 individus, incompatible avec
# l'objectif M1). Retour au patron MultiMesh unique : UN draw call, quelle
# que soit N. Prix : les slots libres restent "presents mais invisibles" dans
# le buffer MultiMesh (pas de compaction) -- la transform d'echelle nulle sur
# un slot libre reste rendue par le GPU mais ne produit aucun pixel visible,
# cout marginal versus le gain d'un draw call unique. Voir
# rendu_terrain_multimesh.gd:853-870 pour le patron RS direct.
#
# ---- INVALIDATION DU MONDE ----
# Le monde.gd de ce depot porte un retirer(id) en ECART FRAMEWORK (voir
# monde.gd:224 § "ECART AVEC LE DEPOT FRAMEWORK"). Le depot Orion n'a pas ce
# geste, et CARTE.md §4781 le classait "ECARTE, a ne pas reproposer" ; l'ecart
# est desormais assume (validation Yael, chantier "peuplement + rendu"),
# CARTE.md est amendee en consequence dans le meme commit. Peuplement.retirer
# l'utilise donc sans reserve.
#
# ---- ECART AVEC LE DEPOT FRAMEWORK ----
# Ce fichier est NEUF dans cette copie de scripts/ ; le depot orion ne le
# porte pas encore. Divergence assumee par Yael faute d'un mecanisme partage
# cote framework (voir CLAUDE.md § Frontiere).

const Objet = preload("res://scripts/objet.gd")

# Transform "invisible" pour un slot libre : echelle NULLE + position (0,0,0).
# Transform3D() par defaut est IDENTITE : un slot libre y rendrait le mesh a
# l'origine, empilement de cubes visibles a (0,0,0). Une echelle nulle rend
# strictement invisible sans retirer le slot du buffer -- alternative propre a
# la compaction / swap qui couterait un memmove par retrait.
const TRANSFORM_SLOT_LIBRE := Transform3D(
	Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO),
	Vector3.ZERO)

# AABB monde large englobant toute la population attendue. Godot ne cull pas
# par instance de MultiMesh (godot-proposals#10669), le culler decide "visible
# ou pas" pour le MultiMesh entier. -1e6 a +1e6 est au-dela de toute carte
# concevable, donc le MultiMesh est TOUJOURS considere visible tant qu'un
# individu est dans le champ de la camera.
const AABB_TRES_LARGE := AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))

static func creer_pool(taille_max: int, mesh: Mesh, scenario: RID) -> Dictionary:
	if taille_max <= 0:
		push_error("peuplement.gd : creer_pool(taille_max = %d) -- taille non positive, pool inutilisable" % taille_max)
		return {}
	if mesh == null:
		push_error("peuplement.gd : creer_pool -- mesh null, aucun rendu possible")
		return {}
	if not scenario.is_valid():
		push_error("peuplement.gd : creer_pool -- scenario RID invalide, instance RS ne serait jamais rendue (issue godotengine/godot#77113)")
		return {}
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = taille_max
	mm.visible_instance_count = taille_max
	# Tous les slots demarrent invisibles ; spawn ecrira la vraie transform.
	# Pas de compaction : visible_instance_count reste a taille_max, les slots
	# libres portent TRANSFORM_SLOT_LIBRE (echelle nulle, invisibles).
	var slots_libres: Array = []
	for slot in range(taille_max):
		mm.set_instance_transform(slot, TRANSFORM_SLOT_LIBRE)
		slots_libres.append(slot)
	var rid: RID = RenderingServer.instance_create()
	RenderingServer.instance_set_base(rid, mm.get_rid())
	RenderingServer.instance_set_scenario(rid, scenario)
	RenderingServer.instance_set_custom_aabb(rid, AABB_TRES_LARGE)
	return {
		"individus": [] as Array,
		"id_to_index": {} as Dictionary,
		"slots_libres": slots_libres,
		"mm": mm,
		"rid": rid,
		"scenario": scenario,
		"taille_max": taille_max,
		"_counter": 0,
	}

static func spawn(pool: Dictionary, catalogue: Dictionary, type_id: String, position: Vector3, monde = null) -> String:
	if pool.is_empty():
		push_error("peuplement.gd : spawn -- pool vide (non initialise)")
		return ""
	if (pool.slots_libres as Array).is_empty():
		push_error("peuplement.gd : spawn -- pool sature (%d slots occupes), refuse" % int(pool.taille_max))
		return ""
	var slot: int = int((pool.slots_libres as Array).pop_back())
	pool["_counter"] = int(pool._counter) + 1
	var id: String = "%s_%d" % [type_id, int(pool._counter)]
	# Objet.fabriquer contrat : (id, type, position, table, materiaux, proprietes_immuables, reserve_combustible, catalogue_emergences).
	# Les quatre catalogues facultatifs restent au defaut vide -- un objet mobile
	# generique n'utilise ni composition, ni combustible, ni emergences.
	var individu: Dictionary = Objet.fabriquer(id, type_id, position, catalogue, {}, [], {}, [])
	if individu.is_empty():
		push_error("peuplement.gd : spawn -- Objet.fabriquer('%s', '%s') a echoue (voir push_error precedent)" % [id, type_id])
		(pool.slots_libres as Array).push_back(slot)
		return ""
	(individu.proprietes as Dictionary)["_slot"] = slot
	(pool.individus as Array).append(individu)
	(pool.id_to_index as Dictionary)[id] = (pool.individus as Array).size() - 1
	if monde != null:
		monde.ajouter(individu, type_id, position)
	(pool.mm as MultiMesh).set_instance_transform(slot, Transform3D(Basis.IDENTITY, position))
	return id

static func retirer(pool: Dictionary, id: String, monde = null) -> void:
	if pool.is_empty():
		return
	var id_to_index: Dictionary = pool.id_to_index
	if not id_to_index.has(id):
		return
	var index: int = int(id_to_index[id])
	var individus: Array = pool.individus
	var individu: Dictionary = individus[index]
	var slot: int = int((individu.proprietes as Dictionary).get("_slot", -1))
	if slot >= 0:
		(pool.mm as MultiMesh).set_instance_transform(slot, TRANSFORM_SLOT_LIBRE)
		(pool.slots_libres as Array).push_back(slot)
	# Swap-remove : deplace le dernier a la place du retire, evite le O(N) d'un
	# remove_at + rebuild complet de id_to_index.
	var dernier: int = individus.size() - 1
	if index != dernier:
		var swap: Dictionary = individus[dernier]
		individus[index] = swap
		id_to_index[String(swap.id)] = index
	individus.pop_back()
	id_to_index.erase(id)
	if monde != null and (monde.choses as Dictionary).has(id):
		monde.retirer(id)

static func ecrire_transform(pool: Dictionary, id: String) -> void:
	if pool.is_empty():
		return
	var id_to_index: Dictionary = pool.id_to_index
	if not id_to_index.has(id):
		return
	var individu: Dictionary = (pool.individus as Array)[int(id_to_index[id])]
	var slot: int = int((individu.proprietes as Dictionary).get("_slot", -1))
	if slot < 0:
		return
	(pool.mm as MultiMesh).set_instance_transform(slot, Transform3D(Basis.IDENTITY, individu.position))

static func ecrire_transform_index(pool: Dictionary, index: int) -> void:
	if pool.is_empty():
		return
	var individus: Array = pool.individus
	if index < 0 or index >= individus.size():
		return
	var individu: Dictionary = individus[index]
	var slot: int = int((individu.proprietes as Dictionary).get("_slot", -1))
	if slot < 0:
		return
	(pool.mm as MultiMesh).set_instance_transform(slot, Transform3D(Basis.IDENTITY, individu.position))

static func detruire_pool(pool: Dictionary) -> void:
	if pool.is_empty():
		return
	var rid: RID = pool.get("rid", RID())
	if rid.is_valid():
		RenderingServer.free_rid(rid)
	(pool.individus as Array).clear()
	(pool.id_to_index as Dictionary).clear()
	(pool.slots_libres as Array).clear()
