extends SceneTree

# Test headless de scripts/peuplement.gd (RefCounted static, chantier
# "peuplement + rendu MultiMesh", etape 2 M1a).
#
# Utilise scripts/verif.gd -- assert() natif INTERDIT (voir verif.gd:3-9 :
# un assert echoue en --headless --script fait PENDRE le processus).
#
# Godot 4 headless : godot --headless --script scripts/test_banc_peuplement.gd
#
# Cinq cas :
# 1. creer_pool(10, mesh, scenario) retourne un Dictionary complet, RIDs
#    valides, slots_libres = [0..9].
# 2. spawn(pool, catalogue, "mobile_test", pos, monde) sur un pool vide
#    fabrique un individu, l'inscrit au pool ET dans le monde
#    (monde.par_id le retrouve).
# 3. spawn au-dela de la capacite retourne "" et laisse le pool intact.
# 4. retirer(pool, id, monde) libere le slot, retire du pool, retire du monde.
# 5. ecrire_transform(pool, id) apres deplacement de individu.position
#    n'erre pas et laisse le pool coherent (le rendu headless est un dummy,
#    on verifie l'absence d'erreur d'API plutot que la valeur affichee).

const Verif = preload("res://scripts/verif.gd")
const Peuplement = preload("res://scripts/peuplement.gd")
const Monde = preload("res://scripts/monde.gd")
const MeshCatalogue = preload("res://scripts/mesh_catalogue.gd")

var _v := Verif.new()

func _init() -> void:
	_lancer.call_deferred()

func _lancer() -> void:
	await _executer()
	if _v.echecs() == 0:
		print("OK: scripts/peuplement.gd -- 5 cas passes (creer_pool, spawn, saturation, retirer, ecrire_transform)")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s) -- voir push_error ci-dessus" % _v.echecs())
		quit(1)

func _executer() -> void:
	# Racine + attente d'un tick pour que get_world_3d().scenario soit valide.
	var racine := Node3D.new()
	get_root().add_child(racine)
	await process_frame

	# Preparer un mesh reel via le catalogue (patron banc).
	var catalogue_mesh: Dictionary = MeshCatalogue.charger()
	_v.v(not catalogue_mesh.is_empty(), "catalogue mesh vide")
	var fiche: Dictionary = catalogue_mesh.get("boite_simple", {})
	var mesh: Mesh = MeshCatalogue.fabriquer_mesh(fiche)
	_v.v(mesh != null, "mesh 'boite_simple' non resolu")
	var scenario: RID = racine.get_world_3d().scenario
	_v.v(scenario.is_valid(), "scenario invalide sur get_world_3d()")

	# Charger le catalogue types (patron banc).
	var catalogue: Dictionary = _charger_types()
	_v.v(catalogue.has("mobile_test"), "catalogue types sans entree 'mobile_test'")

	# ---- CAS 1 : creer_pool ----
	var pool: Dictionary = Peuplement.creer_pool(10, mesh, scenario)
	_v.v(not pool.is_empty(), "cas 1 : pool vide apres creer_pool")
	_v.v(int(pool.get("taille_max", -1)) == 10, "cas 1 : taille_max != 10")
	_v.v((pool.slots_libres as Array).size() == 10, "cas 1 : slots_libres != 10")
	_v.v((pool.individus as Array).is_empty(), "cas 1 : individus non vide a la creation")
	_v.v(pool.get("mm", null) is MultiMesh, "cas 1 : pool.mm absent ou pas un MultiMesh")
	if pool.get("mm", null) is MultiMesh:
		var mm_p: MultiMesh = pool.mm
		_v.v(mm_p.instance_count == 10, "cas 1 : mm.instance_count != 10")
		_v.v(mm_p.visible_instance_count == 10, "cas 1 : mm.visible_instance_count != 10")
	var rid_pool: RID = pool.get("rid", RID())
	_v.v(rid_pool.is_valid(), "cas 1 : pool.rid invalide -- une instance RS unique attendue")

	# ---- CAS 2 : spawn dans un pool vide + inscription au monde ----
	var monde = Monde.new()
	var id_1: String = Peuplement.spawn(pool, catalogue, "mobile_test", Vector3(3.0, 12.4, -5.0), monde)
	_v.v(id_1 != "", "cas 2 : spawn a rendu \"\"")
	_v.v((pool.individus as Array).size() == 1, "cas 2 : individus.size() != 1 apres spawn")
	_v.v((pool.slots_libres as Array).size() == 9, "cas 2 : slots_libres.size() != 9 apres spawn")
	_v.v((pool.id_to_index as Dictionary).has(id_1), "cas 2 : id_to_index sans l'id fraiche")
	var entree_monde = monde.par_id(id_1)
	_v.v(entree_monde != null, "cas 2 : monde.par_id(id) rend null")
	if entree_monde != null:
		_v.v(entree_monde.chose.position == Vector3(3.0, 12.4, -5.0), "cas 2 : position dans le monde differente de position spawn")

	# ---- CAS 3 : spawn au-dela de la capacite ----
	# Le pool a taille_max=10 et 1 slot occupe : on en spawn 9 pour saturer.
	for i in range(9):
		var id: String = Peuplement.spawn(pool, catalogue, "mobile_test", Vector3(float(i), 12.4, 0.0), monde)
		_v.v(id != "", "cas 3 (pre-saturation) : spawn %d/9 a echoue" % (i + 1))
	_v.v((pool.slots_libres as Array).is_empty(), "cas 3 : slots_libres non vide apres saturation")
	# Sature : le 11e spawn doit retourner "" sans modifier le pool.
	var individus_avant: int = (pool.individus as Array).size()
	var counter_avant: int = int(pool._counter)
	var id_sature: String = Peuplement.spawn(pool, catalogue, "mobile_test", Vector3.ZERO, monde)
	_v.v(id_sature == "", "cas 3 : spawn en pool sature n'a pas rendu \"\"")
	_v.v((pool.individus as Array).size() == individus_avant, "cas 3 : individus modifie apres refus")
	# _counter ne doit pas avancer sur un refus (le spawn n'a jamais tente
	# d'attribuer d'id). C'est un contrat implicite -- _counter n'incremente
	# qu'apres avoir passe le check de saturation.
	_v.v(int(pool._counter) == counter_avant, "cas 3 : _counter avance apres un refus de saturation")

	# ---- CAS 4 : retirer ----
	Peuplement.retirer(pool, id_1, monde)
	_v.v((pool.individus as Array).size() == individus_avant - 1, "cas 4 : individus non decremente apres retirer")
	_v.v((pool.slots_libres as Array).size() == 1, "cas 4 : slots_libres != 1 apres retirer (attendu 1 libere)")
	_v.v(not (pool.id_to_index as Dictionary).has(id_1), "cas 4 : id encore dans id_to_index apres retirer")
	_v.v(not (monde.choses as Dictionary).has(id_1), "cas 4 : id encore dans monde.choses apres retirer")
	# Retirer un id absent doit etre silencieux, ne pas crasher.
	Peuplement.retirer(pool, "id_qui_n_existe_pas", monde)
	_v.v((pool.individus as Array).size() == individus_avant - 1, "cas 4 : individus modifie par retirer d'un id absent")

	# ---- CAS 5 : ecrire_transform ----
	# Prendre le premier individu du pool, deplacer sa position en donnee, et
	# appeler ecrire_transform. Le rendu headless est dummy, on ne peut pas
	# verifier l'affichage ; on verifie que l'API ne rend pas d'erreur et que
	# le pool reste coherent (l'individu est toujours indexe, son slot inchange).
	var premier: Dictionary = (pool.individus as Array)[0]
	var id_premier: String = String(premier.id)
	var slot_premier: int = int((premier.proprietes as Dictionary).get("_slot", -1))
	_v.v(slot_premier >= 0, "cas 5 : _slot absent sur individu du pool")
	premier.position = Vector3(42.0, 12.4, -13.0)
	Peuplement.ecrire_transform(pool, id_premier)
	# Rien ne doit avoir change dans les structures du pool.
	_v.v((pool.id_to_index as Dictionary).has(id_premier), "cas 5 : id retire du pool apres ecrire_transform")
	_v.v(int((premier.proprietes as Dictionary).get("_slot", -1)) == slot_premier, "cas 5 : _slot modifie apres ecrire_transform")
	# ecrire_transform sur id absent : silencieux.
	Peuplement.ecrire_transform(pool, "id_qui_n_existe_pas")
	_v.v((pool.individus as Array).size() == individus_avant - 1, "cas 5 : individus modifie par ecrire_transform d'un id absent")

	# ---- Nettoyage ----
	Peuplement.detruire_pool(pool)
	_v.v((pool.individus as Array).is_empty(), "nettoyage : individus non vide apres detruire_pool")
	_v.v((pool.slots_libres as Array).is_empty(), "nettoyage : slots_libres non vide apres detruire_pool")

func _charger_types() -> Dictionary:
	var texte := FileAccess.get_file_as_string("res://data/types.json")
	var donnees = JSON.parse_string(texte)
	if donnees is Dictionary:
		return donnees
	return {}
