# RENDU du terrain streame autour de l'observateur, via UN MultiMesh PAR FORME
# ET PAR TUILE. Remplace le rendu par tuiles de GridMap : chaque forme de la
# bibliotheque (bloc, bloc_rouge, rampe...) a son propre MultiMeshInstance3D,
# rempli des cellules visibles de sa forme. Ajouter une forme future = ajouter
# un item dans la bibliotheque, zero ligne ici : le manager lit toutes les
# formes qu'elle porte.
#
# POURQUOI UN MULTIMESH PAR FORME. Un seul MultiMesh ne rend qu'un seul mesh ;
# le terrain porte plusieurs formes (cubes de couleurs, rampe). Un registre
# forme -> MultiMesh isole chaque forme, laisse controler sa geometrie
# independamment, et rend chaque instance en copie fidele du mesh source --
# memes normales, meme materiau, meme ombrage que le mesh seul.
#
# STREAMING PAR VISIBILITE. Repris tel quel du rendu precedent : un rang n'est
# rendu que s'il a au moins une face exposee (`visible_bits_col`). Les cellules
# enfouies sous un plafond continu ne produisent aucune instance.
#
# CHUNKS OBLIGATOIRES. Godot 4 n'a pas de frustum culling par instance de
# MultiMesh (godot-proposals#10669) : un MultiMesh global vertex-shaderait tout,
# hors champ compris. Chaque tuile porte donc ses MultiMesh avec un `custom_aabb`
# serre a sa boite, et Godot cull chaque tuile independamment. Voir
# jeu/PROTOCOLE_MULTIMESH.md.
#
# UNE TUILE SE CREE ET SE DETRUIT D'UN BLOC : pas de free-list intra-tuile. Les
# MultiMesh d'une tuile sont alloues pleins a sa creation (instance_count = le
# compte exact de cellules de la forme) et liberes d'un coup a sa sortie du
# disque. La free-list du patron `visuel_herbe.gd` ne vaut que pour une
# population qui nait et meurt individu par individu.
#
# COLLISION : AUCUNE. Ce noeud ne fait que du rendu. La collision reste portee
# par le GridMap Terrain proche, dans son seul rayon autour du joueur. Loin du
# joueur, le terrain est de la donnee (la carte) plus ce rendu, sans corps
# physique -- meme division rendu/donnee/collision que le reste du jeu.
#
# ENTREE : `carte`, `mesh_library` (la bibliotheque des formes), observateur par
# groupe, rayon en cellules, taille de tuile. SORTIE : un sous-arbre de
# MultiMeshInstance3D, groupes par tuile.
#
# Regles tenues : positions en Vector3, jamais Vector2 -- une COLONNE est un
# Vector2i, un index et pas une position. Aucun hasard. Aucun texte visible par
# le joueur. Aucun nom de forme en dur : les items se lisent sur la bibliotheque.
# Rien de scripts/, data/ ni documents/ n'est lu ni ecrit.

extends Node3D

const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")

@export var carte: Resource
@export var mesh_library: MeshLibrary
@export var rayon_cellules: int = 120
@export var rayon_interne_cellules: int = 0
@export var taille_tuile_cellules: int = 20
@export var pas_de_rafraichissement: int = 4
@export var groupe_observateur: StringName = &"observateur"

# La forme "limite" ne porte aucun maillage (mur invisible) : jamais rendue.
const ITEM_LIMITE := 1

# tuile Vector2i -> Array[MultiMeshInstance3D] (un par forme presente).
var _tuiles: Dictionary = {}
var _centre_pose_tuile: Vector2i = Vector2i.ZERO
var _amorce := false
var _rayon_tuiles: int = 0
var _rayon_interne_tuiles: int = 0
var _pas_tuiles: int = 1

# GRIDMAP DE REFERENCE, jamais peuple ni rendu : sert UNIQUEMENT a convertir une
# cellule en position par `map_to_local`, exactement comme le rendu GridMap le
# faisait. On n'invente pas la position (index x cote) : on demande la meme
# conversion que l'ancien rendu, sinon les cubes se decalent du centrage des
# cellules.
var _regle: GridMap

func _ready() -> void:
	if carte == null:
		push_error("rendu_terrain_multimesh sans carte")
		return
	if mesh_library == null:
		push_error("rendu_terrain_multimesh sans mesh_library")
		return
	_rayon_tuiles = int(ceil(float(rayon_cellules) / float(taille_tuile_cellules)))
	_rayon_interne_tuiles = int(ceil(float(rayon_interne_cellules) / float(taille_tuile_cellules)))
	_pas_tuiles = maxi(1, int(ceil(float(pas_de_rafraichissement) / float(taille_tuile_cellules))))
	# La regle porte la meme taille de cellule que la carte : c'est ce qui aligne
	# `map_to_local` sur le placement de l'ancien rendu.
	_regle = GridMap.new()
	var cote: float = carte.get("cote")
	_regle.cell_size = Vector3(cote, cote, cote)
	_regle.visible = false
	add_child(_regle)
	_rafraichir_vers(_centre_tuile_observateur())

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

# CALCUL BITWISE DES RANGS VISIBLES DANS UNE COLONNE, identique au rendu
# precedent : un rang est scelle ssi plein ici ET plein en +Y ET plein dans les
# 4 voisins lateraux. Statique -> testable en headless.
static func visible_bits_col(bits: int, nxp: int, nxm: int, nzp: int, nzm: int) -> int:
	var sealed_bits := (bits >> 1) & nxp & nxm & nzp & nzm
	return bits & ~sealed_bits

# Masque bitwise complet d'une colonne, memoize par tuile.
func _masque_col(col: Vector2i, memo: Dictionary) -> int:
	if not memo.has(col):
		memo[col] = carte.masque(col)
	return memo[col]

# CREE UNE TUILE : parcourt ses colonnes, groupe les transforms des cellules
# visibles PAR FORME, puis pose un MultiMeshInstance3D par forme presente. Tout
# d'un bloc -- la tuile est monolithique.
func _creer_tuile(tuile: Vector2i) -> void:
	var cote: float = carte.get("cote")
	var couche_base: int = int(carte.couche_base)
	var particularites: Dictionary = carte.particularites
	var taille := taille_tuile_cellules
	var origine_col := Vector2i(tuile.x * taille, tuile.y * taille)
	var memo_bits: Dictionary = {}

	# forme (item) -> Array[Transform3D] des cellules de cette forme.
	var par_forme: Dictionary = {}

	for lx in range(taille):
		for lz in range(taille):
			var col := Vector2i(origine_col.x + lx, origine_col.y + lz)
			var bits: int = _masque_col(col, memo_bits)
			if bits == 0:
				continue
			var nxp := _masque_col(Vector2i(col.x + 1, col.y), memo_bits)
			var nxm := _masque_col(Vector2i(col.x - 1, col.y), memo_bits)
			var nzp := _masque_col(Vector2i(col.x, col.y + 1), memo_bits)
			var nzm := _masque_col(Vector2i(col.x, col.y - 1), memo_bits)
			var visible_bits := visible_bits_col(bits, nxp, nxm, nzp, nzm)
			if visible_bits == 0:
				continue
			var r_top := CarteTerrain.rang_le_plus_haut(bits)
			for rang in range(r_top + 1):
				if (visible_bits & (1 << rang)) == 0:
					continue
				var couche := couche_base + rang
				var cellule := Vector3i(col.x, couche, col.y)
				var code: int = int(particularites.get(cellule, -1))
				var item: int
				var orientation: int
				if code == -1:
					item = CarteTerrain.ITEM_DEFAUT
					orientation = CarteTerrain.ORIENTATION_DEFAUT
				else:
					item = CarteTerrain.item_du_code(code)
					orientation = CarteTerrain.orientation_du_code(code)
				if item == ITEM_LIMITE:
					continue
				# POSITION, ORIENTATION ET CALAGE PAR LES CONVERSIONS NATIVES DU
				# GRIDMAP, jamais calcules a la main : `map_to_local` pour le centre
				# de la cellule, `get_basis_with_orthogonal_index` pour la rotation,
				# `get_item_mesh_transform` pour le calage propre de la forme.
				# GENERIQUE : toute forme future orientee tombe juste sans une ligne
				# de plus.
				var pos := _regle.map_to_local(cellule)
				var base := _regle.get_basis_with_orthogonal_index(orientation)
				var t := Transform3D(base, pos) * mesh_library.get_item_mesh_transform(item)
				if not par_forme.has(item):
					par_forme[item] = [] as Array
				par_forme[item].append(t)

	var noeuds: Array = []
	for item in par_forme.keys():
		var mmi := _mmi_de_forme(item, par_forme[item], origine_col, couche_base, taille, cote)
		if mmi != null:
			add_child(mmi)
			noeuds.append(mmi)
	_tuiles[tuile] = noeuds

# UN MultiMeshInstance3D pour une forme : le mesh vient de la bibliotheque, une
# instance par transform. `custom_aabb` serre a la boite de la tuile pour le
# frustum culling. Rend null si la forme n'a pas de maillage (ex. limite).
func _mmi_de_forme(item: int, transforms: Array, origine_col: Vector2i,
		couche_base: int, taille: int, cote: float) -> MultiMeshInstance3D:
	var mesh := mesh_library.get_item_mesh(item)
	if mesh == null:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# BOITE SERREE A LA TUILE, en coordonnees monde (ce noeud est a l'origine).
	# Hauteur = toutes les couches representables, plus une marge d'une cellule.
	var couches := CarteTerrain.COUCHES_MAXIMALES
	var pos_aabb := Vector3(
		float(origine_col.x) * cote - cote,
		float(couche_base) * cote - cote,
		float(origine_col.y) * cote - cote)
	var taille_aabb := Vector3(
		float(taille) * cote + 2.0 * cote,
		float(couches) * cote + 2.0 * cote,
		float(taille) * cote + 2.0 * cote)
	mmi.custom_aabb = AABB(pos_aabb, taille_aabb)
	return mmi

func _supprimer_tuile(tuile: Vector2i) -> void:
	if not _tuiles.has(tuile):
		return
	var noeuds = _tuiles[tuile]
	if noeuds != null:
		for mmi in noeuds:
			if is_instance_valid(mmi):
				mmi.queue_free()
	_tuiles.erase(tuile)
