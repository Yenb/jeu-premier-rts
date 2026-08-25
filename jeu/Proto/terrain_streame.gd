# RENDU du terrain visible STREAME autour de l'observateur, via TUILES
# de GridMap dynamiques. Chaque
# tuile = un noeud GridMap enfant, peuple par set_cell_item avec la
# MEME MeshLibrary que le GridMap Terrain proche. Le rendu est
# VISUELLEMENT IDENTIQUE au proche parce que c'est le meme moteur de
# rendu (GridMap natif Godot), meme mesh, meme materiau, meme shading.
#
# STREAMING PAR VISIBILITE. Un rang est POSE seulement s'il a au
# moins une face exposee. Bitwise sur le masque complet des 4 voisins :
# sealed = (bits >> 1) & nxp & nxm & nzp & nzm ;
# visible = bits & ~sealed. Les cellules enfouies sous un plafond
# continu ne sont pas placees dans le GridMap.
#
# COLLISION : ABSENTE de ces GridMap. La MeshLibrary est depouillee
# via Outil.sans_collision : les shapes ne sont pas copiees, donc
# set_cell_item n'ajoute aucun corps physique. La collision reste
# geree par le GridMap Terrain proche uniquement.
#
# RECONSTRUCTION LOCALE. `_supprimer_tuile(t); _creer_tuile(t)` rebatit
# un seul chunk apres modification -- utilise pour le minage/explosion.
# Consequence si mauvaise reconstruction : trou visuel jusqu'au prochain
# rafraichissement. Plan B : rollback ce fichier.
#
# ENTREE : `carte`, `mesh_library` (partagee avec le Terrain proche),
# observateur par groupe, rayon cellules, taille de tuile.
# SORTIE : sous-arbre de GridMap, un par tuile non vide.

extends Node3D

const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")
const Outil = preload("res://jeu/terrain/outil_fenetre.gd")

@export var carte: Resource
@export var mesh_library: MeshLibrary
@export var rayon_cellules: int = 120
@export var rayon_interne_cellules: int = 0
@export var taille_tuile_cellules: int = 10
@export var pas_de_rafraichissement: int = 4
@export var groupe_observateur: StringName = &"observateur"

var _tuiles: Dictionary = {}  # tuile Vector2i -> GridMap ou null
var _centre_pose_tuile: Vector2i = Vector2i.ZERO
var _amorce := false
var _rayon_tuiles: int = 0
var _rayon_interne_tuiles: int = 0
var _pas_tuiles: int = 1
var _biblio_sans_collision: MeshLibrary = null
# Prochaine frame absolue autorisee pour DEMARRER la construction
# d'une tuile. Chaque nouvelle tuile prend le slot suivant, puis
# incremente. Evite que N tuiles arrivees la meme frame executent
# TOUTES leur etape 0 avant le premier await -> pic massif.
var _prochain_slot_frame: int = -1

const ITEM_LIMITE := 1

func _ready() -> void:
	if carte == null:
		push_error("terrain_streame sans carte")
		return
	if mesh_library == null:
		push_error("terrain_streame sans mesh_library")
		return
	_biblio_sans_collision = Outil.sans_collision(mesh_library)
	_rayon_tuiles = int(ceil(float(rayon_cellules) / float(taille_tuile_cellules)))
	_rayon_interne_tuiles = int(ceil(float(rayon_interne_cellules) / float(taille_tuile_cellules)))
	_pas_tuiles = maxi(1, int(ceil(float(pas_de_rafraichissement) / float(taille_tuile_cellules))))
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

# CALCUL BITWISE DES RANGS VISIBLES DANS UNE COLONNE. Un rang est scelle
# ssi plein ici ET plein en +Y (bits >> 1) ET plein dans les 4 voisins
# lateraux. Statique -> testable en headless.
static func visible_bits_col(bits: int, nxp: int, nxm: int, nzp: int, nzm: int) -> int:
	var sealed_bits := (bits >> 1) & nxp & nxm & nzp & nzm
	return bits & ~sealed_bits

# Nombre d'etapes de construction etalees sur autant de frames.
# Un chunk devient visible SEULEMENT apres la derniere etape.
# Etalement lisse les pics de construction sur les nouveaux chunks
# qui entrent dans le rayon (evite un spike a 5 chunks x N cellules
# en une seule frame).
const ETAPES_CONSTRUCTION := 5

# Cree le GridMap invisible et enregistre-le immediatement dans
# `_tuiles` (empeche une seconde creation par le prochain refresh).
# Lance la coroutine `_construire_etalee` qui remplit sur 5 frames
# et rend visible a la fin.
func _creer_tuile(tuile: Vector2i) -> void:
	var cote: float = carte.get("cote")
	var grille := GridMap.new()
	grille.mesh_library = _biblio_sans_collision
	grille.cell_size = Vector3(cote, cote, cote)
	# Cell_center_*=true par defaut : cell (i,j,k) au centre (i*cote,
	# j*cote, k*cote), pareil que le Terrain proche.
	grille.visible = false
	add_child(grille)
	_tuiles[tuile] = grille
	# STAGGER : chaque nouvelle tuile prend le slot frame suivant.
	# Si plusieurs tuiles sont creees la meme frame, elles demarrent
	# a frames+0, frames+1, frames+2, ... - une seule etape 0 par
	# frame reelle au lieu de N.
	var frame_courante := Engine.get_process_frames()
	if _prochain_slot_frame < frame_courante:
		_prochain_slot_frame = frame_courante
	var decalage := _prochain_slot_frame - frame_courante
	_prochain_slot_frame += 1
	_construire_etalee(tuile, grille, decalage)

# COROUTINE. Repartit le peuplement du GridMap sur ETAPES_CONSTRUCTION
# frames consecutives, une tranche de colonnes par etape. La derniere
# etape rend le GridMap visible. Si `_supprimer_tuile` est appele
# entre-temps, la grille devient invalide -> la coroutine sort
# proprement sans plus rien poser.
# Consequence si erreur : chunk jamais visible, ou visible avec cellules
# manquantes. Plan B : rollback ce fichier.
func _construire_etalee(tuile: Vector2i, grille: GridMap, decalage_initial: int) -> void:
	# STAGGER inter-tuiles : attend `decalage_initial` frames avant
	# de faire quoi que ce soit. Assure qu'une seule tuile execute
	# son etape 0 par frame reelle.
	for _i in range(decalage_initial):
		if not is_instance_valid(grille):
			return
		await get_tree().process_frame
	var couche_base: int = int(carte.couche_base)
	var particularites: Dictionary = carte.particularites
	var taille := taille_tuile_cellules
	var origine_col := Vector2i(tuile.x * taille, tuile.y * taille)
	var memo_bits: Dictionary = {}

	for etape in range(ETAPES_CONSTRUCTION):
		if not is_instance_valid(grille):
			return
		# Tranche de colonnes lx traitees a cette etape. Division qui
		# tolere une taille non multiple de 5 (tranches vides possibles
		# a l'extremite, benin).
		var lx_start := int(floor(float(etape) * float(taille) / float(ETAPES_CONSTRUCTION)))
		var lx_end := int(floor(float(etape + 1) * float(taille) / float(ETAPES_CONSTRUCTION)))
		for lx in range(lx_start, lx_end):
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
					var orientation: int = CarteTerrain.ORIENTATION_DEFAUT
					if code == -1:
						item = CarteTerrain.ITEM_DEFAUT
					else:
						item = CarteTerrain.item_du_code(code)
						orientation = CarteTerrain.orientation_du_code(code)
					if item == ITEM_LIMITE:
						continue
					grille.set_cell_item(cellule, item, orientation)
		if etape < ETAPES_CONSTRUCTION - 1:
			await get_tree().process_frame
	if is_instance_valid(grille):
		grille.visible = true

# Masque bitwise complet d'une colonne, memoize par tuile.
func _masque_col(col: Vector2i, memo: Dictionary) -> int:
	if not memo.has(col):
		memo[col] = carte.masque(col)
	return memo[col]

func _supprimer_tuile(tuile: Vector2i) -> void:
	if not _tuiles.has(tuile):
		return
	var grille = _tuiles[tuile]
	if grille != null and is_instance_valid(grille):
		grille.queue_free()
	_tuiles.erase(tuile)
