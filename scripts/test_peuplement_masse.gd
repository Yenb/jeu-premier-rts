extends SceneTree

# Test headless de scripts/peuplement.gd -- regime masse (chantier
# "regime de masse en colonnes, paquet dynamique fabrique a la demande",
# 2026-09-08). Verrouille le contrat des deux nouvelles fonctions statiques :
#
# - spawn_masse : cree UNE ligne de colonnes sans aucun Dict individu. Le buffer
#   MultiMesh recoit les 12 floats du slot. individus/id_to_index restent VIDES.
# - activer : fabrique le Dictionary individu (paquets_partages=true), l'attache
#   au pool avec _slot correct, inscrit au monde. Le paquet dynamique arrive
#   COMPLET (reserves.faim.reserve=100.0 par defaut).
#
# Utilise scripts/verif.gd -- assert() natif INTERDIT.
# Lancement : godot --headless --script scripts/test_peuplement_masse.gd
#
# Six cas :
# 1. spawn_masse dans un pool vide : rend un slot >= 0, cols recoivent la
#    ligne (position/velocite/desiree/direction/au_sol/cap_horloge/vitesse/slot),
#    individus/id_to_index restent VIDES, buffer contient les 12 floats.
# 2. spawn_masse repete : count = cols.position.size() croit, slots_libres
#    diminue en LIFO.
# 3. spawn_masse sur un pool sature : rend -1 sans modifier les colonnes.
# 4. activer(pool, "mobile_test", index) : rend un id non vide, cree UN
#    Dictionary individu, le paquet dynamique porte reserves.faim.reserve=100.0,
#    _slot correspond a cols.slot[index], la position lue est cols.position[index].
# 5. activer inscrit au monde : monde.par_id(id) retourne l'individu.
# 6. activer hors bornes rend "" sans crasher.

const Verif = preload("res://scripts/verif.gd")
const Peuplement = preload("res://scripts/peuplement.gd")
const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const MeshCatalogue = preload("res://scripts/mesh_catalogue.gd")

var _v := Verif.new()

func _init() -> void:
	_lancer.call_deferred()

func _lancer() -> void:
	await _executer()
	if _v.echecs() == 0:
		print("OK: peuplement.gd -- 6 cas passes (spawn_masse pool vide/repete/sature, activer paquet dynamique/monde/hors bornes)")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)

func _executer() -> void:
	Objet.vider_cache_paquets_partages()
	var racine := Node3D.new()
	get_root().add_child(racine)
	await process_frame

	var catalogue_mesh: Dictionary = MeshCatalogue.charger()
	var mesh: Mesh = MeshCatalogue.fabriquer_mesh(catalogue_mesh.get("boite_simple", {}))
	_v.v(mesh != null, "prealable : mesh 'boite_simple' non resolu")
	var scenario: RID = racine.get_world_3d().scenario
	_v.v(scenario.is_valid(), "prealable : scenario invalide")
	var catalogue: Dictionary = _charger_types()
	_v.v(catalogue.has("mobile_test"), "prealable : catalogue sans 'mobile_test'")

	# Colonnes que le banc de peuplement declare (voir jeu/bancs/banc_peuplement.gd:
	# _monter_pool). spawn_masse ecrit chacune de ces colonnes a chaque appel.
	var colonnes := {
		"position": Vector3.ZERO,
		"velocite": Vector3.ZERO,
		"desiree": Vector3.ZERO,
		"direction": Vector3.ZERO,
		"au_sol": false,
		"cap_horloge": 0.0,
		"vitesse": 1.0,
		"slot": 0,
	}

	# ---- CAS 1 : spawn_masse dans un pool vide ----
	var pool: Dictionary = Peuplement.creer_pool(10, mesh, scenario, colonnes)
	_v.v(not pool.is_empty(), "cas 1 : creer_pool a rendu {}")
	var slot_1: int = Peuplement.spawn_masse(pool, Vector3(3.0, 12.4, -5.0), 2.5, Vector3(1.0, 0.0, 0.0), 5.0)
	_v.v(slot_1 >= 0, "cas 1 : spawn_masse a rendu -1 sur un pool vide")
	_v.v((pool.individus as Array).is_empty(), "cas 1 : individus non vide apres spawn_masse (regime masse doit laisser Dictionary intact)")
	_v.v((pool.id_to_index as Dictionary).is_empty(), "cas 1 : id_to_index non vide apres spawn_masse")
	_v.v((pool.slots_libres as Array).size() == 9, "cas 1 : slots_libres != 9 apres 1 spawn_masse (10-1=9)")
	var cols: Dictionary = pool.colonnes
	_v.v((cols.position as PackedVector3Array).size() == 1, "cas 1 : cols.position != 1 apres 1 spawn_masse")
	_v.v((cols.position as PackedVector3Array)[0] == Vector3(3.0, 12.4, -5.0), "cas 1 : cols.position[0] != position spawn")
	_v.v(is_equal_approx((cols.vitesse as PackedFloat32Array)[0], 2.5), "cas 1 : cols.vitesse[0] != vitesse parametre")
	_v.v((cols.direction as PackedVector3Array)[0] == Vector3(1.0, 0.0, 0.0), "cas 1 : cols.direction[0] != direction_errance parametre")
	_v.v(is_equal_approx((cols.cap_horloge as PackedFloat32Array)[0], 5.0), "cas 1 : cols.cap_horloge[0] != cap_horloge parametre")
	_v.v((cols.velocite as PackedVector3Array)[0] == Vector3.ZERO, "cas 1 : cols.velocite[0] != Vector3.ZERO au spawn")
	# desiree = direction * vitesse : cablage attendu du peuplement mobile.
	_v.v((cols.desiree as PackedVector3Array)[0] == Vector3(2.5, 0.0, 0.0), "cas 1 : cols.desiree[0] != direction * vitesse")
	_v.v((cols.au_sol as PackedByteArray)[0] == 0, "cas 1 : cols.au_sol[0] != false au spawn")
	_v.v(int((cols.slot as PackedInt32Array)[0]) == slot_1, "cas 1 : cols.slot[0] != slot alloue")
	# BUFFER : identite + position ecrits.
	var buffer: PackedFloat32Array = pool.buffer
	var base: int = slot_1 * 12
	_v.v(is_equal_approx(buffer[base + 0], 1.0) and is_equal_approx(buffer[base + 5], 1.0) and is_equal_approx(buffer[base + 10], 1.0),
		"cas 1 : base identite non posee dans le buffer apres spawn_masse")
	_v.v(is_equal_approx(buffer[base + 3], 3.0), "cas 1 : buffer origin.x != position.x")
	_v.v(is_equal_approx(buffer[base + 7], 12.4), "cas 1 : buffer origin.y != position.y")
	_v.v(is_equal_approx(buffer[base + 11], -5.0), "cas 1 : buffer origin.z != position.z")

	# ---- CAS 2 : spawn_masse repete ----
	for k in range(4):
		var slot_k: int = Peuplement.spawn_masse(pool, Vector3(float(k), 12.0, 0.0), 1.0)
		_v.v(slot_k >= 0, "cas 2 : spawn_masse %d/4 a rendu -1" % (k + 1))
	_v.v((cols.position as PackedVector3Array).size() == 5, "cas 2 : cols.position != 5 apres 5 spawn_masse")
	_v.v((pool.slots_libres as Array).size() == 5, "cas 2 : slots_libres != 5 apres 5 spawn_masse")
	_v.v((pool.individus as Array).is_empty(), "cas 2 : individus non vide apres 5 spawn_masse")

	# ---- CAS 3 : spawn_masse sur pool sature ----
	for k in range(5):
		var s: int = Peuplement.spawn_masse(pool, Vector3(float(k), 20.0, 0.0), 1.0)
		_v.v(s >= 0, "cas 3 (pre-saturation) : spawn_masse a echoue avant saturation")
	_v.v((pool.slots_libres as Array).is_empty(), "cas 3 : slots_libres non vide apres 10 spawn_masse")
	var cols_avant_sature: int = (cols.position as PackedVector3Array).size()
	var slot_sature: int = Peuplement.spawn_masse(pool, Vector3.ZERO, 1.0)
	_v.v(slot_sature == -1, "cas 3 : spawn_masse en pool sature n'a pas rendu -1")
	_v.v((cols.position as PackedVector3Array).size() == cols_avant_sature, "cas 3 : cols.position modifie apres refus de saturation")

	# ---- CAS 4 : activer paquet dynamique complet ----
	Peuplement.detruire_pool(pool)
	pool = Peuplement.creer_pool(10, mesh, scenario, colonnes)
	# REBIND OBLIGATOIRE : detruire_pool clear le Dictionary colonnes du pool
	# precedent ; la variable `cols` locale pointait encore dessus. Le nouveau
	# creer_pool a mis un Dictionary neuf sous pool.colonnes -- il faut le
	# reprendre.
	cols = pool.colonnes
	var monde = Monde.new()
	var slot_a: int = Peuplement.spawn_masse(pool, Vector3(7.0, 12.5, -1.0), 2.0)
	var slot_b: int = Peuplement.spawn_masse(pool, Vector3(8.0, 12.5, -2.0), 2.0)
	_v.v(slot_a >= 0 and slot_b >= 0, "cas 4 : spawn_masse initial a echoue")
	var id_activated: String = Peuplement.activer(pool, catalogue, "mobile_test", 1, monde)
	_v.v(id_activated != "", "cas 4 : activer a rendu \"\"")
	_v.v((pool.individus as Array).size() == 1, "cas 4 : individus.size() != 1 apres UNE activation")
	_v.v((pool.id_to_index as Dictionary).has(id_activated), "cas 4 : id_to_index sans l'id active")
	var individu: Dictionary = (pool.individus as Array)[0]
	var p: Dictionary = individu.proprietes
	# Paquet dynamique fabrique correctement : sous-Dict reserves porte 5 canaux
	# (herite de dynamique), faim.reserve=100.0 par defaut.
	_v.v(p.has("reserves"), "cas 4 : reserves absente du paquet dynamique active")
	_v.v(p.reserves.has("faim") and p.reserves.has("energie") and p.reserves.has("soif"),
		"cas 4 : reserves fabriquee sans les 5 canaux de dynamique")
	_v.v(is_equal_approx(float(p.reserves.faim.reserve), 100.0), "cas 4 : reserves.faim.reserve != 100.0 (defaut de dynamique perdu)")
	_v.v(int(p.get("_slot", -1)) == int((cols.slot as PackedInt32Array)[1]), "cas 4 : _slot != cols.slot[index]")
	_v.v(individu.position == (cols.position as PackedVector3Array)[1], "cas 4 : individu.position != cols.position[index]")

	# ---- CAS 5 : activer inscrit au monde ----
	var entree = monde.par_id(id_activated)
	_v.v(entree != null, "cas 5 : monde.par_id(id) rend null apres activer")
	if entree != null:
		_v.v(entree.chose.position == Vector3(8.0, 12.5, -2.0), "cas 5 : position dans le monde != position spawn_masse")

	# ---- CAS 6 : activer hors bornes ----
	var id_hors: String = Peuplement.activer(pool, catalogue, "mobile_test", 999, null)
	_v.v(id_hors == "", "cas 6 : activer(index=999) hors bornes n'a pas rendu \"\"")
	var id_neg: String = Peuplement.activer(pool, catalogue, "mobile_test", -1, null)
	_v.v(id_neg == "", "cas 6 : activer(index=-1) n'a pas rendu \"\"")
	_v.v((pool.individus as Array).size() == 1, "cas 6 : individus modifie apres refus hors bornes")

	Peuplement.detruire_pool(pool)

func _charger_types() -> Dictionary:
	var texte := FileAccess.get_file_as_string("res://data/types.json")
	var donnees = JSON.parse_string(texte)
	if donnees is Dictionary:
		return donnees
	return {}
