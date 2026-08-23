# RENDU VISUEL-SEUL du terrain lointain via TUILES de MultiMeshInstance3D.
#
# ROLE : remplacer un GridMap dynamique pour la zone visuelle lointaine.
# Un GridMap paye 4-6 ms par retarget en reconstruction d'octants.
# Un MultiMesh unique paye ZERO reconstruction mais Godot 4 ne cull pas
# par instance (proposal godotengine/godot-proposals#10669) : toutes
# les instances sont vertex-shadees a chaque frame -> catastrophe
# (mesure : fps 8 a 300k instances).
#
# SOLUTION EPROUVEE (plugin Spatial Gardener, doc Godot) : decouper
# l'espace en TUILES carrees, un MultiMeshInstance3D par tuile par
# item de biblio, custom_aabb serre a la boite de la tuile. Godot cull
# chaque tuile independamment via son AABB.
#
# UN MULTIMESH PAR ITEM PAR TUILE : preserve les particularites
# (bloc_vert sculpte, rampes orientees) sans mesher unifie.
#
# INSTANCE_COUNT DIMENSIONNE AU COMPTE REEL, EN DEUX PASSES. Cas
# different de `visuel_herbe.gd` : la population de la tuile est FIGEE
# a sa creation, aucune naissance/mort intra-tuile. On peut donc
# allouer pile poil chaque MMI. Zero slot cache -> zero vertex
# processing gaspille. La tuile est monolithique : creee/detruite d'un
# bloc, pas de free-list intra-tuile.
#
# ORIENTATION : `carte.orientation_de(cellule)` code un index
# orthogonal 0..23. Table statique de 24 Basis, calculee UNE fois via
# un GridMap ephemere -- pas de GridMap orphelin retenu en memoire.
#
# ENTREE : une `carte`, une `mesh_library`, un observateur, un rayon
# cellules, un rayon interne (masque proche pour eviter recouvrement
# avec le GridMap physique), une taille de tuile.
# SORTIE : sous-arbre de MultiMeshInstance3D groupes par tuile.

extends Node3D

const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")

@export var carte: Resource
@export var mesh_library: MeshLibrary
@export var rayon_cellules: int = 120
@export var rayon_interne_cellules: int = 15
@export var taille_tuile_cellules: int = 10
@export var pas_de_rafraichissement: int = 4
@export var groupe_observateur: StringName = &"observateur"

var _tuiles: Dictionary = {}
var _centre_pose_tuile: Vector2i = Vector2i.ZERO
var _amorce := false
var _rayon_tuiles: int = 0
var _rayon_interne_tuiles: int = 0
var _pas_tuiles: int = 1
var _item_defaut_repli: int = -1

static var _bases_orientation: Array = []

func _ready() -> void:
	if carte == null:
		push_error("terrain_visible_multimesh sans carte")
		return
	if mesh_library == null:
		push_error("terrain_visible_multimesh sans mesh_library")
		return
	# OVERRIDE INSTRUMENTATION : env var pour balayer taille_tuile sans
	# editer le .tscn (hook interdit). Retire apres diagnostic.
	# Consequence si var absente : rien, comportement inchange.
	# Rollback : suppression de ce bloc.
	var env_tuile := OS.get_environment("TAILLE_TUILE")
	if env_tuile != "":
		taille_tuile_cellules = int(env_tuile)
		print("[TERRAIN_MM] override taille_tuile_cellules = ", taille_tuile_cellules)
	_amorcer_bases_orientation()
	# Repli pour ITEM_DEFAUT hoiste hors de la boucle interne.
	var ids := mesh_library.get_item_list()
	if not ids.is_empty():
		_item_defaut_repli = ids[0]
	_rayon_tuiles = int(ceil(float(rayon_cellules) / float(taille_tuile_cellules)))
	# CEIL, pas floor : mieux vaut une tuile de trou en trop qu'un
	# recouvrement invisible avec le GridMap physique proche.
	_rayon_interne_tuiles = int(ceil(float(rayon_interne_cellules) / float(taille_tuile_cellules)))
	_pas_tuiles = maxi(1, int(ceil(float(pas_de_rafraichissement) / float(taille_tuile_cellules))))
	_rafraichir_vers(_centre_tuile_observateur())

# UNE seule fois par processus. GridMap.new() cree un noeud hors-arbre
# juste pour lire la table des 24 rotations orthogonales, puis libere.
static func _amorcer_bases_orientation() -> void:
	if not _bases_orientation.is_empty():
		return
	var helper := GridMap.new()
	for i in range(24):
		_bases_orientation.append(helper.get_basis_with_orthogonal_index(i))
	helper.free()

func _process(_delta: float) -> void:
	var centre := _centre_tuile_observateur()
	if _doit_rafraichir(centre):
		_rafraichir_vers(centre)

func _centre_tuile_observateur() -> Vector2i:
	var obs := get_tree().get_first_node_in_group(groupe_observateur) as Node3D
	if obs == null:
		return Vector2i.ZERO
	var cote: float = carte.get("cote")
	var cx := int(floor(obs.global_position.x / cote))
	var cz := int(floor(obs.global_position.z / cote))
	return Vector2i(
		int(floor(float(cx) / float(taille_tuile_cellules))),
		int(floor(float(cz) / float(taille_tuile_cellules))))

func _doit_rafraichir(centre: Vector2i) -> bool:
	if not _amorce:
		return true
	var ecart := centre - _centre_pose_tuile
	return absi(ecart.x) >= _pas_tuiles or absi(ecart.y) >= _pas_tuiles

func _rafraichir_vers(centre: Vector2i) -> void:
	var vise := _tuiles_du_disque(centre)
	for t in vise.keys():
		if not _tuiles.has(t):
			_creer_tuile(t)
	for t in _tuiles.keys():
		if not vise.has(t):
			_supprimer_tuile(t)
	_centre_pose_tuile = centre
	_amorce = true

func _tuiles_du_disque(centre: Vector2i) -> Dictionary:
	var ens: Dictionary = {}
	var r_ext := _rayon_tuiles
	var r_int := _rayon_interne_tuiles
	var r_ext2 := r_ext * r_ext
	var r_int2 := r_int * r_int
	for dx in range(-r_ext, r_ext + 1):
		for dz in range(-r_ext, r_ext + 1):
			var d2 := dx * dx + dz * dz
			if d2 <= r_ext2 and d2 >= r_int2:
				ens[Vector2i(centre.x + dx, centre.y + dz)] = true
	return ens

# DEUX PASSES par tuile. (1) recolte cellule -> item ; (2) alloue chaque
# MMI a la taille EXACTE et pose. Voir en-tete pour le pourquoi.
# Intention : eviter les slots vides vertex-shades a chaque frame.
# Consequence si echec : tuile invisible ou creation qui plante.
# Plan B : rollback via git de ce seul fichier.
func _creer_tuile(tuile: Vector2i) -> void:
	var cote: float = carte.get("cote")
	var origine_col := Vector2i(
		tuile.x * taille_tuile_cellules,
		tuile.y * taille_tuile_cellules)

	# PASSE 1 : item -> [cellules, orientations]. On lit le masque
	# directement au lieu d'appeler cellules_de (qui alloue un Array par
	# colonne) et on lit particularites en UN seul get au lieu du couple
	# item_de + orientation_de (qui font chacun un has + un get).
	# Mesure profileur : item_de + orientation_de = 60 ms cumulees, 4
	# acces dict par cellule ; ici 1 get par cellule pleine, 0 alloc de
	# tableau intermediaire par colonne.
	# Intention : reduire de 4x le nombre d'acces Dictionary chauds.
	# Consequence si mauvais code : cellule/orientation fausse a l'ecran.
	# Rollback : git checkout de ce seul fichier.
	var couche_base: int = int(carte.couche_base)
	var particularites: Dictionary = carte.particularites
	var cellules_par_item: Dictionary = {}
	var orientations_par_item: Dictionary = {}
	for lx in range(taille_tuile_cellules):
		for lz in range(taille_tuile_cellules):
			var col := Vector2i(origine_col.x + lx, origine_col.y + lz)
			var bits: int = carte.masque(col)
			if bits == 0:
				continue
			for rang in range(CarteTerrain.COUCHES_MAXIMALES):
				if (bits & (1 << rang)) == 0:
					continue
				var cellule := Vector3i(col.x, couche_base + rang, col.y)
				var code: int = int(particularites.get(cellule, -1))
				var item: int
				var orientation: int
				if code == -1:
					item = CarteTerrain.ITEM_DEFAUT
					orientation = CarteTerrain.ORIENTATION_DEFAUT
				else:
					item = CarteTerrain.item_du_code(code)
					orientation = CarteTerrain.orientation_du_code(code)
				if item == CarteTerrain.ITEM_DEFAUT:
					if _item_defaut_repli == -1:
						continue
					item = _item_defaut_repli
				if mesh_library.get_item_mesh(item) == null:
					continue
				if not cellules_par_item.has(item):
					cellules_par_item[item] = []
					orientations_par_item[item] = []
				cellules_par_item[item].append(cellule)
				orientations_par_item[item].append(orientation)

	if cellules_par_item.is_empty():
		_tuiles[tuile] = {}
		return

	# Boite de la tuile pour custom_aabb -- calculee UNE fois pour tous
	# les MMI de la tuile.
	var origine_world := Vector3(
		float(origine_col.x) * cote,
		0.0,
		float(origine_col.y) * cote)
	var taille_world := float(taille_tuile_cellules) * cote
	var aabb_tuile := AABB(
		origine_world + Vector3(0, -50, 0),
		Vector3(taille_world, 200, taille_world))

	# TRACE INSTRUMENTATION : premiere tuile creee, log le custom_aabb
	# calcule pour verifier qu'il est bien serre a la taille de tuile.
	# Retire apres diagnostic.
	if _tuiles.is_empty():
		var msg := "[TERRAIN_MM] tuile %s aabb pos=%s size=%s (taille_tuile=%d cote=%.1f)" % [
			str(tuile), str(aabb_tuile.position), str(aabb_tuile.size),
			taille_tuile_cellules, cote]
		print(msg)
		var f := FileAccess.open("user://terrain_mm.log", FileAccess.WRITE)
		if f != null:
			f.store_line(msg)
			f.close()

	# PASSE 2 : alloue chaque MMI a la taille exacte et pose.
	# Orientations deja resolues en passe 1 -> plus aucun appel a carte
	# dans cette passe.
	var par_item: Dictionary = {}
	for item in cellules_par_item.keys():
		var cellules: Array = cellules_par_item[item]
		var orientations: Array = orientations_par_item[item]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh_library.get_item_mesh(item)
		multi.instance_count = cellules.size()
		for i in range(cellules.size()):
			var cellule: Vector3i = cellules[i]
			var pos := Vector3(
				float(cellule.x) * cote + cote * 0.5,
				float(cellule.y) * cote + cote * 0.5,
				float(cellule.z) * cote + cote * 0.5)
			var orientation: int = clampi(int(orientations[i]), 0, 23)
			multi.set_instance_transform(i, Transform3D(_bases_orientation[orientation], pos))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = multi
		mmi.custom_aabb = aabb_tuile
		add_child(mmi)
		par_item[item] = mmi
	_tuiles[tuile] = par_item

func _supprimer_tuile(tuile: Vector2i) -> void:
	if not _tuiles.has(tuile):
		return
	var par_item = _tuiles[tuile]
	for item in par_item.keys():
		var mmi = par_item[item]
		if mmi != null and is_instance_valid(mmi):
			mmi.queue_free()
	_tuiles.erase(tuile)
