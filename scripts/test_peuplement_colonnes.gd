extends SceneTree

# Test headless :
# godot --headless --script scripts/test_peuplement_colonnes.gd
#
# Verrouille l'ALIGNEMENT des colonnes paralleles de scripts/peuplement.gd
# apres retrait. Le banc courant ne retire personne pendant le run, donc ce
# chemin n'est exerce par aucun autre test ; s'il est faux, la valeur de
# colonne lue apres un retrait ne correspond plus a l'individu -- panne
# silencieuse. peuplement fait un swap-remove sur individus ET sur CHAQUE
# colonne, ce test le prouve.
#
# Trois cas :
#  1. Trois spawns avec des valeurs de colonne distinctes rangent chacun a
#     l'index rendu par id_to_index.
#  2. Retirer celui du MILIEU (swap-remove : le dernier prend sa place) :
#     pour chaque individu restant, colonne[id_to_index[id]] == valeur au
#     spawn.
#  3. La taille des colonnes suit celle de individus a chaque etape.

const Verif = preload("res://scripts/verif.gd")
const Peuplement = preload("res://scripts/peuplement.gd")
const MeshCatalogue = preload("res://scripts/mesh_catalogue.gd")

var _v := Verif.new()


func _init() -> void:
	_lancer.call_deferred()


func _lancer() -> void:
	await _executer()
	if _v.echecs() == 0:
		print("OK: peuplement.colonnes -- append au spawn, swap-remove au retrait, alignement tenu")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)


func _executer() -> void:
	var racine := Node3D.new()
	get_root().add_child(racine)
	await process_frame

	var catalogue_mesh: Dictionary = MeshCatalogue.charger()
	var mesh: Mesh = MeshCatalogue.fabriquer_mesh(catalogue_mesh.get("boite_simple", {}))
	var scenario: RID = racine.get_world_3d().scenario
	var catalogue: Dictionary = _charger_types()

	# Deux colonnes : "couleur" (Vector3) et "poids" (float). Peuplement ne
	# lit jamais leur contenu ; le test ecrit et relit.
	var pool: Dictionary = Peuplement.creer_pool(5, mesh, scenario, {
		"couleur": Vector3.ZERO,
		"poids": 0.0,
	})
	_v.v(not pool.is_empty(), "pool vide apres creer_pool")
	_v.v(pool.colonnes.has("couleur"), "colonne 'couleur' absente")
	_v.v(pool.colonnes.has("poids"), "colonne 'poids' absente")
	_v.v((pool.colonnes.couleur as PackedVector3Array).size() == 0, "couleur non vide au depart")

	# --- CAS 1 : 3 spawns, valeurs distinctes ecrites via l'index rendu ---
	var couleurs_spawn := [
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
	]
	var poids_spawn := [11.0, 22.0, 33.0]
	var ids: Array = []
	for k in range(3):
		var id: String = Peuplement.spawn(pool, catalogue, "mobile_test", Vector3.ZERO)
		_v.v(id != "", "spawn %d a rendu \"\"" % k)
		if id == "":
			return
		ids.append(id)
		var idx: int = int(pool.id_to_index[id])
		_v.v(idx == k, "index rendu != ordre de spawn (%d, attendu %d)" % [idx, k])
		var cc: PackedVector3Array = pool.colonnes.couleur
		cc[idx] = couleurs_spawn[k]
		pool.colonnes.couleur = cc
		var pp: PackedFloat32Array = pool.colonnes.poids
		pp[idx] = poids_spawn[k]
		pool.colonnes.poids = pp

	_v.v((pool.individus as Array).size() == 3, "individus.size() != 3")
	_v.v((pool.colonnes.couleur as PackedVector3Array).size() == 3, "colonne couleur non alignee (size)")
	_v.v((pool.colonnes.poids as PackedFloat32Array).size() == 3, "colonne poids non alignee (size)")

	# --- CAS 2 : retirer celui du MILIEU (swap-remove) ---
	Peuplement.retirer(pool, ids[1])
	_v.v((pool.individus as Array).size() == 2, "individus.size() != 2 apres retirer")
	_v.v((pool.colonnes.couleur as PackedVector3Array).size() == 2, "couleur.size() != 2 apres retirer")
	_v.v((pool.colonnes.poids as PackedFloat32Array).size() == 2, "poids.size() != 2 apres retirer")

	# Pour chaque ID restant : la valeur relue via id_to_index doit etre celle
	# du spawn. C'est LE test critique : si le swap-remove sur colonne diverge
	# du swap-remove sur individus, l'egalite tombe.
	for k in [0, 2]:
		var id: String = ids[k]
		_v.v(pool.id_to_index.has(id), "id %s absent apres retirer du milieu" % id)
		if not pool.id_to_index.has(id):
			continue
		var idx: int = int(pool.id_to_index[id])
		var couleur_lue: Vector3 = (pool.colonnes.couleur as PackedVector3Array)[idx]
		var poids_lu: float = (pool.colonnes.poids as PackedFloat32Array)[idx]
		_v.v(couleur_lue == couleurs_spawn[k],
			"id %s : couleur %s != spawn %s (colonne desalignee)" % [id, str(couleur_lue), str(couleurs_spawn[k])])
		_v.v(poids_lu == poids_spawn[k],
			"id %s : poids %s != spawn %s (colonne desalignee)" % [id, str(poids_lu), str(poids_spawn[k])])

	# --- CAS 3 : retirer un id absent ne casse rien ---
	Peuplement.retirer(pool, "id_qui_n_existe_pas")
	_v.v((pool.colonnes.couleur as PackedVector3Array).size() == 2, "couleur mutee par retirer d'un id absent")
	_v.v((pool.colonnes.poids as PackedFloat32Array).size() == 2, "poids mutee par retirer d'un id absent")

	Peuplement.detruire_pool(pool)
	_v.v((pool.colonnes as Dictionary).is_empty(), "colonnes non vides apres detruire_pool")


func _charger_types() -> Dictionary:
	var texte := FileAccess.get_file_as_string("res://data/types.json")
	var donnees = JSON.parse_string(texte)
	if donnees is Dictionary:
		return donnees
	return {}
