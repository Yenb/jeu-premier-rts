extends RefCounted

# PEUPLEMENT_2 : JUMEAU indépendant de scripts/peuplement.gd, réécrit
# entièrement pour permettre une comparaison de coût "Processus" /
# "Processus physique" côte à côte à N identique. Cohabite avec l'original
# sans le préloader ni en réutiliser une seule ligne : le contrat public est
# le même, l'écriture est neuve.
#
# ROLE. Orchestrateur générique d'une population homogène : alloue UN
# MultiMesh de N slots et UNE instance RenderingServer directe qui pointe
# dessus. Un draw call unique quelle que soit N. Le consommateur (banc, jeu)
# détient le Dictionary retourné par creer_pool ; ce module n'a ni état, ni
# cache, ni catégorie du monde connue.
#
# CE MODULE NE CONNAIT AUCUN NOM DE CONTENU. type_id et mesh_ref circulent
# comme String opaques ; ils sont résolus côté consommateur avant appel.
#
# CE MODULE N'EMBARQUE AUCUN COMPORTEMENT. Errance, cadence, politique de
# tick : c'est le banc qui les décide.
#
# CE MODULE N'A AUCUN CACHE PAR INDIVIDU. individu.proprietes ne reçoit
# qu'un seul champ technique préfixé _ : "_slot" (index dans le MultiMesh).
# Aucun cache de sol, aucun cache de sommet, aucune clé _sol_* ou _cache_*.
#
# ---- STRUCTURE DU POOL (Dictionary retourné par creer_pool) ----
# {
#   individus       : Array de Dictionary (chacun est un objet Objet.fabriquer),
#   id_to_index     : Dictionary id:String -> int,
#   slots_libres    : Array[int] (LIFO des indices dispo),
#   mm              : MultiMesh (référence forte, N slots),
#   rid             : RID (UNE instance RS, base = mm.get_rid()),
#   scenario        : RID (World3D scenario, gardé pour trace),
#   taille_max      : int,
#   _counter        : int (compteur d'id monotone),
# }
#
# ---- API PUBLIQUE ----
# static creer_pool(taille_max, mesh, scenario) -> Dictionary
# static spawn(pool, catalogue, type_id, position, monde = null) -> String
# static retirer(pool, id, monde = null) -> void
# static ecrire_transform(pool, id) -> void
# static detruire_pool(pool) -> void
#
# ---- ECART FRAMEWORK ----
# Fichier neuf dans cette copie de scripts/, absent du dépôt orion. Jumeau
# temporaire ; sa présence est justifiée par une comparaison de performance
# décidée par Yael.

const Objet = preload("res://scripts/objet.gd")

# Un slot libre est rendu invisible par une matrice d'échelle nulle. La
# transform identité par défaut placerait un mesh à l'origine — empilement de
# cubes visibles à (0,0,0). Alternative à une compaction qui coûterait un
# memmove par retrait.
const SLOT_INVISIBLE := Transform3D(
	Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO),
	Vector3.ZERO)

# Godot ne cull pas par slot d'un MultiMesh (godot-proposals#10669) : le
# culler tranche pour le MultiMesh entier. Une AABB très large garantit qu'il
# reste visible tant qu'un individu est à l'écran.
const AABB_MONDE := AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))


static func creer_pool(taille_max: int, mesh: Mesh, scenario: RID) -> Dictionary:
	if taille_max <= 0:
		push_error("peuplement_2.gd : creer_pool(taille_max = %d) refuse -- taille non positive" % taille_max)
		return {}
	if mesh == null:
		push_error("peuplement_2.gd : creer_pool refuse -- mesh null")
		return {}
	if not scenario.is_valid():
		push_error("peuplement_2.gd : creer_pool refuse -- scenario RID invalide (issue godotengine/godot#77113)")
		return {}

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = taille_max
	mm.visible_instance_count = taille_max

	var libres: Array = []
	libres.resize(taille_max)
	var i: int = taille_max - 1
	var j: int = 0
	while i >= 0:
		mm.set_instance_transform(i, SLOT_INVISIBLE)
		libres[j] = i
		i -= 1
		j += 1

	var rid: RID = RenderingServer.instance_create()
	RenderingServer.instance_set_base(rid, mm.get_rid())
	RenderingServer.instance_set_scenario(rid, scenario)
	RenderingServer.instance_set_custom_aabb(rid, AABB_MONDE)

	return {
		"individus": [] as Array,
		"id_to_index": {} as Dictionary,
		"slots_libres": libres,
		"mm": mm,
		"rid": rid,
		"scenario": scenario,
		"taille_max": taille_max,
		"_counter": 0,
	}


static func spawn(pool: Dictionary, catalogue: Dictionary, type_id: String, position: Vector3, monde = null) -> String:
	if pool.is_empty():
		push_error("peuplement_2.gd : spawn refuse -- pool vide (non initialise)")
		return ""
	var libres: Array = pool.slots_libres
	if libres.is_empty():
		push_error("peuplement_2.gd : spawn refuse -- pool sature (%d slots)" % int(pool.taille_max))
		return ""

	var slot: int = int(libres.pop_back())
	var compteur: int = int(pool._counter) + 1
	pool["_counter"] = compteur
	var id: String = "%s_%d" % [type_id, compteur]

	var individu: Dictionary = Objet.fabriquer(id, type_id, position, catalogue, {}, [], {}, [])
	if individu.is_empty():
		push_error("peuplement_2.gd : Objet.fabriquer('%s', '%s') a echoue -- slot rendu" % [id, type_id])
		libres.push_back(slot)
		return ""

	(individu.proprietes as Dictionary)["_slot"] = slot
	var individus: Array = pool.individus
	individus.append(individu)
	(pool.id_to_index as Dictionary)[id] = individus.size() - 1

	if monde != null:
		monde.ajouter(individu, type_id, position)

	(pool.mm as MultiMesh).set_instance_transform(slot, Transform3D(Basis.IDENTITY, position))
	return id


static func retirer(pool: Dictionary, id: String, monde = null) -> void:
	if pool.is_empty():
		return
	var index_par_id: Dictionary = pool.id_to_index
	if not index_par_id.has(id):
		return

	var individus: Array = pool.individus
	var index: int = int(index_par_id[id])
	var individu: Dictionary = individus[index]

	var slot: int = int((individu.proprietes as Dictionary).get("_slot", -1))
	if slot >= 0:
		(pool.mm as MultiMesh).set_instance_transform(slot, SLOT_INVISIBLE)
		(pool.slots_libres as Array).push_back(slot)

	# Swap-remove O(1) : le dernier prend la place du retire, id_to_index
	# est mis a jour pour le seul deplace.
	var dernier: int = individus.size() - 1
	if index != dernier:
		var deplace: Dictionary = individus[dernier]
		individus[index] = deplace
		index_par_id[String(deplace.id)] = index
	individus.pop_back()
	index_par_id.erase(id)

	if monde != null and (monde.choses as Dictionary).has(id):
		monde.retirer(id)


static func ecrire_transform(pool: Dictionary, id: String) -> void:
	if pool.is_empty():
		return
	var index_par_id: Dictionary = pool.id_to_index
	if not index_par_id.has(id):
		return
	var individu: Dictionary = (pool.individus as Array)[int(index_par_id[id])]
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
