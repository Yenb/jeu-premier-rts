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
# IL DRAINE LA CARTE A CHAQUE `_process`. Une colonne modifiee en jeu (creusee
# par une balle, par exemple) est publiee par `carte_terrain.drainer_modifications`
# ; ce noeud INVALIDE la tuile qui la contient, la supprime synchroniquement, et
# la remet dans la file de creation pour rebuild etale a la meme cadence que
# les entrees/sorties de disque. Une tuile hors disque est ignoree (rien a rendre).
# Une tuile en attente de creation (pas encore batie) est ignoree aussi : elle
# lira l'etat a jour de la carte quand elle sera batie.
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
const SolShader = preload("res://jeu/terrain/sol_minimal.gdshader")
const SolMiniCubeShader = preload("res://jeu/terrain/sol_mini_cube.gdshader")

@export var carte: Resource
@export var mesh_library: MeshLibrary
@export var rayon_cellules: int = 120
@export var rayon_interne_cellules: int = 0
@export var taille_tuile_cellules: int = 10
@export var pas_de_rafraichissement: int = 4
@export var groupe_observateur: StringName = &"observateur"
# COMBIEN DE TUILES BATIES PAR FRAME. Franchir une bordure fait entrer tout un
# ANNEAU de tuiles d'un coup ; les batir toutes dans la meme frame (avec un
# occludeur bake par tuile) gele le jeu -- mesure : 127 ms. Elles sont mises en
# file et batties quelques-unes par frame. Meme etalement que
# jeu/Proto/terrain_streame.gd, patron deja eprouve.
@export var tuiles_par_frame: int = 1

# DISTANCE DE RENDU (LOD par distance). Au-dela, une tuile n'est plus dessinee --
# le lointain n'a pas besoin d'etre net. Posee sur chaque MultiMeshInstance3D via
# `visibility_range_end`. A 0, aucune limite : tout se dessine jusqu'au rayon.
@export var distance_rendu_metres: float = 0.0

# S6 -- CHEMIN "INSTANCES RS DIRECTES", filet de securite par flag.
# Faux (defaut) : chemin historique inchange, un MultiMeshInstance3D par forme et
# par tuile est add_child dans le SceneTree ; c'est le chemin que les tests
# S1/S2/S2.5-2.7 lisent (ils iterent `_tuiles[t] as Array` et testent
# `n is MultiMeshInstance3D`).
# Vrai : bascule sur des instances RenderingServer directes (aucun MMi dans le
# SceneTree). Meme MultiMesh cote GPU, meme custom_aabb, meme culling ; seul
# l'overhead SceneTree de ~4500 noeuds MMi par frame disparait. L'occludeur reste
# un OccluderInstance3D (Godot 4 le requiert). Le stockage `_tuiles[tuile]` devient
# alors un Dictionary { "instances_rs": [{mm, rid}], "occluder": OccluderInstance3D }
# au lieu d'un Array de noeuds -- garder ce flag a false tant que le nouveau chemin
# n'est pas valide en jeu, l'inverser dans un commit separe une fois teste.
@export var utilise_rs_direct: bool = false

# S7 -- PIPELINE INTRA-TUILE, filet de securite par flag.
# Faux (defaut) : _creer_tuile execute les 3 phases (parser, bake instances,
#   bake occluder) EN SEQUENCE dans la meme frame -- comportement historique,
#   tests S1/S2 non impactes. Un pic streaming reste concentre sur une frame.
# Vrai : chaque tuile qui rentre en creation est enfilee dans _tuiles_en_pipeline
#   avec phase=0. _process avance chaque frame `tuiles_avancees_par_frame` tuiles
#   d'UNE phase. Latence perceptible : une tuile fraiche apparait a la 2e frame
#   du drain (instances) et devient occludante a la 3e. Meme raison d'etre que
#   utilise_rs_direct : garder faux tant que non valide en jeu.
@export var utilise_pipeline_intra_tuile: bool = false
@export var tuiles_avancees_par_frame: int = 1

# ETAPE (a) du portage C++ de _phase_parser (extension_terrain/src/mesheur_tuile.cpp).
# Faux (defaut) : chemin historique inchange, GDScript emet toutes les faces.
# Vrai : le C++ prend en charge UNIQUEMENT les faces cubiques PROPRES (cellule
#   avec sous_cubes plein et sans PV en cours). Les mini-cubes, non-cubes,
#   occluder cells et la resolution des profils teinte restent en GDScript pour
#   cette etape. La teinte des cubes propres est repoussee ici a partir du
#   mapping face->cellule que le C++ rend en parallele des transforms -- sans
#   cela elle disparaitrait sur ces cellules. Voir _appliquer_cpp_a.
@export var utilise_cpp_phase0: bool = false

# La forme "limite" ne porte aucun maillage (mur invisible) : jamais rendue.
const ITEM_LIMITE := 1

# tuile Vector2i -> Array[MultiMeshInstance3D] (un par forme presente).
var _tuiles: Dictionary = {}
var _centre_pose_tuile: Vector2i = Vector2i.ZERO
var _amorce := false
var _rayon_tuiles: int = 0
var _rayon_interne_tuiles: int = 0
var _pas_tuiles: int = 1
# LES TUILES EN ATTENTE DE CONSTRUCTION, drainee par _process a raison de
# `tuiles_par_frame`. Une tuile en file est marquee dans `_tuiles` par un Array
# VIDE (batie -> Array de noeuds). Si elle sort du disque avant d'etre batie,
# _supprimer_tuile la retire de `_tuiles` et le drain la saute.
var _file_creation: Array = []
# TUILES A SUPPRIMER, etalees dans _process au meme rythme que la creation.
# Supprimer ~25 tuiles d'un coup force ~25 rebuilds du BVH d'occlusion en une
# seule frame ; les etaler en reduit le pic a 1 par frame.
var _a_supprimer: Dictionary = {}
# S7 -- PIPELINE INTRA-TUILE EN 3 PHASES. Chaque tuile en cours de bake vit ici,
# _tuiles[tuile] garde la sentinelle Array vide tant que les 3 phases ne sont pas
# finies. Repartit le pic de streaming : parsing frame N, instances N+1, occluder
# N+2. Total inchange, pic divise par ~3 (Zylann/godot_voxel : BVH d'occlusion
# coute 3-5x le parsing). tuile -> {
#   "phase": int (0/1/2),
#   "parsed": Dictionary,                     # apres phase 0
#   "instances_rs": Array of {mm, rid},       # apres phase 1, chemin RS direct
#   "noeuds": Array of MultiMeshInstance3D,   # apres phase 1, chemin nœud
#   "mm_par_item_normal": Dictionary,         # apres phase 1
#   "mm_par_item_sol": Dictionary,            # apres phase 1
# }
var _tuiles_en_pipeline: Dictionary = {}

# GRIDMAP DE REFERENCE, jamais peuple ni rendu : sert UNIQUEMENT a convertir une
# cellule en position par `map_to_local`, exactement comme le rendu GridMap le
# faisait. On n'invente pas la position (index x cote) : on demande la meme
# conversion que l'ancien rendu, sinon les cubes se decalent du centrage des
# cellules.
var _regle: GridMap

# LES SIX FACES D'UN CUBE : la normale (vers le vide) et la rotation qui oriente
# le quad vers elle. Un cube n'est PAS rendu plein : il ne pose qu'un quad par
# face exposee (voisin vide). Une face collee a un voisin plein ne se voit
# jamais et n'existe pas dans le rendu -- c'est le vrai economie de triangles.
var _faces: Array = []
# item -> PlaneMesh (avec le materiau du cube) pour les formes CUBIQUES. Une
# forme non-cube (rampe, cylindre, sphere) n'y figure pas : elle garde son mesh
# complet, instancie tel quel -- le face culling n'a de sens que pour un cube.
var _quad_par_item: Dictionary = {}
# item -> hauteur reelle du BoxMesh (size.y). Un item plus court que la cellule
# (ex. bloc_beche a 15/16) est dessine ABAISSE : face du dessus descendue,
# faces laterales mises a l'echelle verticale. Un cube pleine hauteur y vaut
# `cote` et passe par le meme code sans difference visible. Lu dans _ajouter_face.
var _hauteur_par_item: Dictionary = {}
# INDEX DE TEINTE PAR RESERVE. Tuile -> Dict { cellule -> Array[{mmi, idx}] }.
# Rempli au streaming pour chaque cellule qui a un profil de reserve (via
# ressources_terrain). Le tick lit `quantite_a(cellule) / profil.reserve`,
# calcule un gain [0.4..1.0] et pose la couleur d'instance. Vide si aucun
# bloc profilé n'est visible -- pas de balayage global.
var _teinte_par_tuile: Dictionary = {}
var _ressources: Node = null
var _horloge_teinte: float = 0.0
const TEINTE_INTERVALLE := 1.0  # 1 Hz, aligne sur le tick regen
const TEINTE_GAIN_VIDE := 0.2
# Cache derniere teinte posee par cellule pour eviter les re-poses inutiles.
var _teinte_precedente: Dictionary = {}
# CACHES DE TEINTE PAR CELLULE. Alimentes au streaming (dans _creer_tuile pour
# chaque cellule declaree teintable), purges au dechargement de tuile
# (_supprimer_tuile). Modification de carte : _absorber_modifications_carte
# passe par _supprimer_tuile puis _creer_tuile, donc les caches sont purges et
# re-alimentes en un seul cycle -- pas d'invalidation explicite ici.
# Le tick de teinte lit ces caches, plus aucun _ressources.call() par cellule.
var _cache_profil_cellule: Dictionary = {}    # Vector3i cellule -> Resource
var _cache_quantite_cellule: Dictionary = {}  # Vector3i cellule -> int
# COMPTEUR DEBUG/PERF, incremente en tete de _creer_tuile. Sert au test S2 a
# prouver qu'une salve de modifs dans une meme tuile collapse en UN rebuild.
var _creations_tuile_compte: int = 0
# item -> BoxMesh de cote/3, materiau du cube. Pose UN mini-cube par bit a 1
# dans le masque `carte.sous_cubes(cellule)` -- resolution 3x3x3.
var _mini_box_par_item: Dictionary = {}

# Instance de MesheurTuile (GDExtension) instancie paresseusement au premier
# usage. Voir extension_terrain/. Nul tant que utilise_cpp_phase0 = false.
var _mesheur: Object = null

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
	# Les six orientations de face : le quad (PlaneMesh, normale +Y) tourne pour
	# pointer sa normale vers le vide.
	_faces = [
		{"n": Vector3(0, 1, 0), "b": Basis()},
		{"n": Vector3(0, -1, 0), "b": Basis(Vector3(1, 0, 0), PI)},
		{"n": Vector3(1, 0, 0), "b": Basis(Vector3(0, 0, 1), -PI / 2.0)},
		{"n": Vector3(-1, 0, 0), "b": Basis(Vector3(0, 0, 1), PI / 2.0)},
		{"n": Vector3(0, 0, 1), "b": Basis(Vector3(1, 0, 0), PI / 2.0)},
		{"n": Vector3(0, 0, -1), "b": Basis(Vector3(1, 0, 0), -PI / 2.0)},
	]
	_preparer_quads(cote)
	_preparer_mini_cubes(cote)
	_rafraichir_vers(_centre_tuile_observateur())

# UN QUAD PAR FORME CUBIQUE. Chaque cube (BoxMesh) sera rendu face par face au
# lieu d'un cube plein. Le quad porte le materiau du cube, en DOUBLE FACE pour
# ne jamais laisser de trou si une face etait orientee a l'envers.
func _preparer_quads(cote: float) -> void:
	for item in mesh_library.get_item_list():
		var mesh := mesh_library.get_item_mesh(item)
		if not (mesh is BoxMesh):
			continue
		# Hauteur reelle du bloc : sert a abaisser les items plus courts que la
		# cellule (bloc_beche). Un cube plein a size.y == cote.
		_hauteur_par_item[item] = (mesh as BoxMesh).size.y
		var quad := PlaneMesh.new()
		quad.size = Vector2(cote, cote)
		var mat := (mesh as BoxMesh).material
		# SHADER CUSTOM MINIMAL : couleur unie + ombre, zero PBR.
		var smat := ShaderMaterial.new()
		# Shader "teintable par instance" (sol_mini_cube) : ALBEDO = couleur *
		# COLOR. COLOR par defaut = blanc -> aspect identique tant qu'aucune
		# teinte per-instance n'est posee. Sert au tick de teinte (feedback
		# reserve) pour tout bloc profile, generique.
		smat.shader = SolMiniCubeShader
		var c := Color(0.45, 0.36, 0.27, 1.0)
		if mat is BaseMaterial3D:
			c = (mat as BaseMaterial3D).albedo_color
		elif mat != null:
			quad.material = mat
			_quad_par_item[item] = quad
			continue
		smat.set_shader_parameter("couleur", c)
		quad.material = smat
		_quad_par_item[item] = quad

# UN MINI-BOX PAR FORME CUBIQUE. Cote = cote_cellule / 3 : la cellule contient
# 27 mini-cubes (3x3x3). Materiau DEDIE avec `sol_mini_cube.gdshader` qui
# multiplie ALBEDO par COLOR d'instance -- permet de foncer chaque mini-cube
# selon ses PV (voir _mmi_mini_cubes).
func _preparer_mini_cubes(cote: float) -> void:
	var mini_cote := cote / 3.0
	for item in _quad_par_item.keys():
		var quad: PlaneMesh = _quad_par_item[item]
		var mat_quad = quad.material
		var couleur_item := Color(0.45, 0.36, 0.27, 1.0)
		if mat_quad is ShaderMaterial:
			var col_shader = (mat_quad as ShaderMaterial).get_shader_parameter("couleur")
			if col_shader != null:
				couleur_item = col_shader
		elif mat_quad is BaseMaterial3D:
			couleur_item = (mat_quad as BaseMaterial3D).albedo_color
		var smat := ShaderMaterial.new()
		smat.shader = SolMiniCubeShader
		smat.set_shader_parameter("couleur", couleur_item)
		var box := BoxMesh.new()
		box.size = Vector3(mini_cote, mini_cote, mini_cote)
		box.material = smat
		_mini_box_par_item[item] = box

# S6 -- Liberation des RIDs a la fermeture. En chemin nœud, queue_free suffit
# (le SceneTree nettoie a l'exit) ; en chemin RS direct, les RIDs ne sont detenus
# par personne d'autre -- sans free explicite ici, ils fuient (leak).
func _exit_tree() -> void:
	for tuile in _tuiles.keys():
		_supprimer_tuile(tuile)

func _process(_delta: float) -> void:
	_absorber_modifications_carte()
	# Tick teinte a 1 Hz (aligne sur regen). Cache anti-repose evite les
	# set_instance_color inutiles tant qu'aucune reserve ne change.
	_horloge_teinte += _delta
	if _horloge_teinte >= TEINTE_INTERVALLE:
		_horloge_teinte = 0.0
		_tick_teinte()
	var centre := _centre_tuile_observateur()
	if _doit_rafraichir(centre):
		_rafraichir_vers(centre)
	# ETALEMENT CREATION : quelques tuiles par frame, jamais tout l'anneau d'un coup.
	var faits := 0
	while faits < tuiles_par_frame and not _file_creation.is_empty():
		var t: Vector2i = _file_creation.pop_back()
		if _a_supprimer.has(t):
			continue
		# SENTINELLE "EN FILE" : Array vide, commune aux deux chemins de stockage.
		# Une tuile deja batie porte soit un Array non vide (nœud), soit un
		# Dictionary (rs_direct) -- ni l'un ni l'autre ne match ici.
		if _tuiles.has(t) and _tuiles[t] is Array and (_tuiles[t] as Array).is_empty():
			_creer_tuile(t)
			faits += 1
	# S7 -- DRAIN PIPELINE INTRA-TUILE. Chaque frame, avance au plus
	# `tuiles_avancees_par_frame` tuiles d'UNE phase chacune (une tuile n'est
	# ratissee qu'UNE fois par frame -- pas de 0->1->2 dans le meme tick). Une
	# tuile poussee par _creer_tuile plus tot dans cette frame peut donc etre
	# avancee de phase 0 -> 1 le meme tick : c'est acceptable, phase 0 = parsing
	# LEGER, elle ne se fait pas doubler par phase 1 (bake) ni par phase 2
	# (occludeur, le lourd).
	if utilise_pipeline_intra_tuile and not _tuiles_en_pipeline.is_empty():
		var avances := 0
		var cles_pipe := _tuiles_en_pipeline.keys()
		for cle_p in cles_pipe:
			if avances >= tuiles_avancees_par_frame:
				break
			# Une tuile supprimee entre-temps a deja disparu de _tuiles_en_pipeline
			# via _supprimer_tuile ; le has() ci-dessous couvre l'unique cas de race
			# (drain suppression et drain pipeline dans le meme tick).
			if not _tuiles_en_pipeline.has(cle_p):
				continue
			var etat: Dictionary = _tuiles_en_pipeline[cle_p]
			var phase: int = int(etat.get("phase", 0))
			if phase == 0:
				etat["parsed"] = _phase_parser(cle_p)
				etat["phase"] = 1
			elif phase == 1:
				_phase_baker_instances(cle_p, etat)
				etat["phase"] = 2
			elif phase == 2:
				_phase_baker_occluder(cle_p, etat)
				_tuiles_en_pipeline.erase(cle_p)
			avances += 1
	# ETALEMENT SUPPRESSION : meme rythme que la creation. Avant ce drain, toutes
	# les tuiles sortantes etaient detruites d'un coup dans _rafraichir_vers —
	# ~25 OccluderInstance3D liberes en une frame, ~25 rebuilds du BVH d'occlusion.
	var supprimes := 0
	if not _a_supprimer.is_empty():
		var cles := _a_supprimer.keys()
		while supprimes < tuiles_par_frame and supprimes < cles.size():
			var t: Vector2i = cles[supprimes]
			_a_supprimer.erase(t)
			_supprimer_tuile(t)
			supprimes += 1

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
		# Une tuile marquee pour suppression mais revenue dans le disque : annuler.
		_a_supprimer.erase(t)
		if not _tuiles.has(t):
			_tuiles[t] = []
			_file_creation.append(t)
	for t in _tuiles.keys():
		if not vise.has(t) and not _a_supprimer.has(t):
			_a_supprimer[t] = true
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

# CALCUL BITWISE DES RANGS VISIBLES DANS UNE COLONNE : un rang est scelle ssi
# le plafond de MA colonne couvre + les 4 voisins lateraux COUVRENT au meme rang.
# `mon_couvrant`, `nxp_couvrant` etc. sont les masques COUVRANTS : bit a 1 seulement
# si la cellule est un cube pleinement plein (item cubique + sous-cubes intacts).
# Une rampe ou une forme non-cube compte comme PLEINE dans le masque volumes brut
# (elle occupe sa cellule), mais elle ne COUVRE PAS la face carree du cube adjacent
# -- il reste toujours un triangle vide sur le cote de la pente. La faire compter
# comme couvrante ferait disparaitre le cube voisin et laisserait voir a travers
# la rampe (bug S2.7 : capture d'ecran, etages sombres a travers un mur).
static func visible_bits_col(bits: int, mon_couvrant: int,
		nxp_couvrant: int, nxm_couvrant: int,
		nzp_couvrant: int, nzm_couvrant: int) -> int:
	var sealed_bits := (mon_couvrant >> 1) & nxp_couvrant & nxm_couvrant & nzp_couvrant & nzm_couvrant
	return bits & ~sealed_bits

# Masque bitwise complet d'une colonne, memoize par tuile.
func _masque_col(col: Vector2i, memo: Dictionary) -> int:
	if not memo.has(col):
		memo[col] = carte.masque(col)
	return memo[col]

# MASQUE COUVRANT d'une colonne : `_masque_col` filtre des rangs qui ne
# couvrent pas la face carree de la cellule voisine :
# - cellule dont l'item n'est PAS cubique (rampe, cylindre, sphere : pente ou
#   arrondi -> laisse toujours un vide sur le cote) ;
# - cellule cassee (sous_cubes != PLEIN : troue).
# Memoize separement de _masque_col : les deux valeurs sont utilisees ensemble
# et lues plusieurs fois par tuile (chaque colonne teste ses 4 voisins).
func _masque_couvrant_col(col: Vector2i, memo: Dictionary) -> int:
	if memo.has(col):
		return memo[col]
	var bits: int = carte.masque(col)
	if bits == 0:
		memo[col] = 0
		return 0
	var particularites: Dictionary = carte.particularites
	var base: int = int(carte.couche_base)
	var couvrant := bits
	for rang in range(CarteTerrain.COUCHES_MAXIMALES):
		if (bits & (1 << rang)) == 0:
			continue
		var cellule := Vector3i(col.x, base + rang, col.y)
		var code: int = int(particularites.get(cellule, -1))
		var item: int
		if code == -1:
			item = CarteTerrain.ITEM_DEFAUT
		else:
			item = CarteTerrain.item_du_code(code)
		if not _quad_par_item.has(item):
			couvrant &= ~(1 << rang)  # non-cube : ne couvre pas
			continue
		if carte.sous_cubes(cellule) != CarteTerrain.MASQUE_SOUS_CUBE_PLEIN:
			couvrant &= ~(1 << rang)  # cube casse : ne couvre pas
	memo[col] = couvrant
	return couvrant

# CREE UNE TUILE. Deux chemins :
# - utilise_pipeline_intra_tuile=false : les 3 phases s'executent en sequence
#   dans la meme frame (comportement historique, pic streaming concentre).
# - utilise_pipeline_intra_tuile=true : la tuile rentre en _tuiles_en_pipeline
#   avec phase=0, _process avance chaque frame `tuiles_avancees_par_frame` tuiles
#   d'UNE phase (S7 : parsing / bake instances / bake occluder etales sur 3 frames).
# _creations_tuile_compte compte les ENTREES (une tuile qui commence a etre bakee),
# semantique preservee pour le test S2 de coalescence.
func _creer_tuile(tuile: Vector2i) -> void:
	_creations_tuile_compte += 1
	if utilise_pipeline_intra_tuile:
		_tuiles_en_pipeline[tuile] = {"phase": 0}
		return
	var etat: Dictionary = {"parsed": _phase_parser(tuile)}
	_phase_baker_instances(tuile, etat)
	_phase_baker_occluder(tuile, etat)

# S7 -- PHASE 0 (PARSER). Parcourt les colonnes de la tuile, calcule les faces
# visibles par forme, collecte les buckets teintables et le set d'occludeurs.
# AUCUN bake (aucun MultiMesh, aucun add_child, aucune instance RS). Alimente les
# caches teinte (_cache_profil_cellule / _cache_quantite_cellule) et les compteurs
# d'AABB (couche_min / couche_max). Retour : dict "parsed" self-contenu, suffisant
# pour la phase 1 -- rien ne demande de re-parcourir les colonnes ensuite.
func _phase_parser(tuile: Vector2i) -> Dictionary:
	var cote: float = carte.get("cote")
	var couche_base: int = int(carte.couche_base)
	var particularites: Dictionary = carte.particularites
	var taille := taille_tuile_cellules
	var origine_col := Vector2i(tuile.x * taille, tuile.y * taille)
	var memo_bits: Dictionary = {}
	var memo_couvrant: Dictionary = {}

	# forme (item) -> Array[Transform3D]. Voir doc historique de _creer_tuile.
	var par_forme: Dictionary = {}
	var par_forme_sol: Dictionary = {}
	var par_forme_mini: Dictionary = {}
	var teinte_normal: Dictionary = {}
	var teinte_sol: Dictionary = {}
	if _ressources == null:
		_ressources = get_tree().get_first_node_in_group(&"ressources_terrain")
	var couche_min := couche_base + CarteTerrain.COUCHES_MAXIMALES
	var couche_max := couche_base
	var sommet_base := int(carte.sommet_de_base())
	var cellules_occl: Dictionary = {}

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
			var mon_couvrant := _masque_couvrant_col(col, memo_couvrant)
			var nxp_c := _masque_couvrant_col(Vector2i(col.x + 1, col.y), memo_couvrant)
			var nxm_c := _masque_couvrant_col(Vector2i(col.x - 1, col.y), memo_couvrant)
			var nzp_c := _masque_couvrant_col(Vector2i(col.x, col.y + 1), memo_couvrant)
			var nzm_c := _masque_couvrant_col(Vector2i(col.x, col.y - 1), memo_couvrant)
			var visible_bits := visible_bits_col(bits, mon_couvrant, nxp_c, nxm_c, nzp_c, nzm_c)
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
				var pos := _regle.map_to_local(cellule)
				var cible: Dictionary = par_forme_sol if couche == sommet_base else par_forme
				if _quad_par_item.has(item):
					var masque_sous: int = carte.sous_cubes(cellule)
					var pv_map: Dictionary = carte.pv_sous_cubes_cellule(cellule)
					if masque_sous != CarteTerrain.MASQUE_SOUS_CUBE_PLEIN or not pv_map.is_empty():
						_ajouter_mini_cubes(par_forme_mini, item, pos, cote, masque_sous, pv_map)
					else:
						var profil_cell: Resource = null
						if _ressources != null and _ressources.has_method("profil_de_cellule"):
							profil_cell = _ressources.call("profil_de_cellule", cellule) as Resource
						var teintable: bool = profil_cell != null
						if teintable:
							_cache_profil_cellule[cellule] = profil_cell
							_cache_quantite_cellule[cellule] = int(_ressources.call("quantite_a", cellule))
						# ETAPE (a) : quand utilise_cpp_phase0, le C++ emet les 6 faces
						# ET publie le mapping face->cellule. La teinte est
						# repoussee apres la boucle dans _appliquer_cpp_a a
						# partir de ce mapping. Le cache profil/quantite ci-dessus
						# reste peuple pour cette cellule quelle que soit la
						# valeur du flag -- _tick_teinte en depend.
						if not utilise_cpp_phase0:
							var bucket_teinte: Dictionary = teinte_sol if cible == par_forme_sol else teinte_normal
							if not _voisin_couvre(col, couche + 1, bits, rang + 1):
								var i0 := _ajouter_face(cible, item, pos, 0, cote)
								if teintable:
									_pousser_teinte(bucket_teinte, item, cellule, i0)
							if not _voisin_couvre(col, couche - 1, bits, rang - 1):
								var i1 := _ajouter_face(cible, item, pos, 1, cote)
								if teintable:
									_pousser_teinte(bucket_teinte, item, cellule, i1)
							if not _voisin_couvre(Vector2i(col.x + 1, col.y), couche, nxp, rang):
								var i2 := _ajouter_face(cible, item, pos, 2, cote)
								if teintable:
									_pousser_teinte(bucket_teinte, item, cellule, i2)
							if not _voisin_couvre(Vector2i(col.x - 1, col.y), couche, nxm, rang):
								var i3 := _ajouter_face(cible, item, pos, 3, cote)
								if teintable:
									_pousser_teinte(bucket_teinte, item, cellule, i3)
							if not _voisin_couvre(Vector2i(col.x, col.y + 1), couche, nzp, rang):
								var i4 := _ajouter_face(cible, item, pos, 4, cote)
								if teintable:
									_pousser_teinte(bucket_teinte, item, cellule, i4)
							if not _voisin_couvre(Vector2i(col.x, col.y - 1), couche, nzm, rang):
								var i5 := _ajouter_face(cible, item, pos, 5, cote)
								if teintable:
									_pousser_teinte(bucket_teinte, item, cellule, i5)
				else:
					var base := _regle.get_basis_with_orthogonal_index(orientation)
					var t := Transform3D(base, pos) * mesh_library.get_item_mesh_transform(item)
					if not par_forme.has(item):
						par_forme[item] = [] as Array
					par_forme[item].append(t)
				couche_min = mini(couche_min, couche)
				couche_max = maxi(couche_max, couche)
				if couche > sommet_base and _quad_par_item.has(item):
					cellules_occl[cellule] = true
	# ETAPE (a) : le C++ ajoute ses faces cubiques propres et repousse la teinte
	# a partir du mapping face->cellule qu'il rend. Aucun effet quand le flag
	# est faux -- rien n'est appele.
	if utilise_cpp_phase0:
		_appliquer_cpp_a(par_forme, par_forme_sol, teinte_normal, teinte_sol,
				origine_col, cote, couche_base, particularites)
	return {
		"par_forme": par_forme,
		"par_forme_sol": par_forme_sol,
		"par_forme_mini": par_forme_mini,
		"teinte_normal": teinte_normal,
		"teinte_sol": teinte_sol,
		"cellules_occl": cellules_occl,
		"couche_min": couche_min,
		"couche_max": couche_max,
		"origine_col": origine_col,
		"cote": cote,
		"taille": taille,
	}

# S7 -- PHASE 1 (BAKER INSTANCES + INDEX TEINTE). Lit `etat.parsed`, alloue les
# MultiMesh et les porteurs (instances RS ou MMi selon utilise_rs_direct), remplit
# l'index de teinte de la tuile. Ne fait AUCUN occludeur (phase 2). Ecrit dans
# etat : instances_rs / noeuds / mm_par_item_normal / mm_par_item_sol -- lus par
# la phase 2 ET par _supprimer_tuile en cas d'annulation en cours de pipeline.
func _phase_baker_instances(_tuile: Vector2i, etat: Dictionary) -> void:
	var parsed: Dictionary = etat["parsed"]
	var par_forme: Dictionary = parsed["par_forme"]
	var par_forme_sol: Dictionary = parsed["par_forme_sol"]
	var par_forme_mini: Dictionary = parsed["par_forme_mini"]
	var teinte_normal: Dictionary = parsed["teinte_normal"]
	var teinte_sol: Dictionary = parsed["teinte_sol"]
	var couche_min: int = int(parsed["couche_min"])
	var couche_max: int = int(parsed["couche_max"])
	var origine_col: Vector2i = parsed["origine_col"]
	var cote: float = parsed["cote"]
	var taille: int = int(parsed["taille"])

	var mm_par_item_normal: Dictionary = {}
	var mm_par_item_sol: Dictionary = {}
	var noeuds: Array = []
	var instances_rs: Array = []
	if utilise_rs_direct:
		for item in par_forme.keys():
			var e: Dictionary = _rs_de_forme(item, par_forme[item], origine_col, couche_min, couche_max, taille, cote, false)
			if not e.is_empty():
				instances_rs.append(e)
				mm_par_item_normal[item] = e["mm"]
		for item in par_forme_sol.keys():
			var e: Dictionary = _rs_de_forme(item, par_forme_sol[item], origine_col, couche_min, couche_max, taille, cote, true)
			if not e.is_empty():
				instances_rs.append(e)
				mm_par_item_sol[item] = e["mm"]
		for item in par_forme_mini.keys():
			var e: Dictionary = _rs_mini_cubes(item, par_forme_mini[item], origine_col, couche_min, couche_max, taille, cote)
			if not e.is_empty():
				instances_rs.append(e)
	else:
		for item in par_forme.keys():
			var mmi := _mmi_de_forme(item, par_forme[item], origine_col, couche_min, couche_max, taille, cote)
			if mmi != null:
				add_child(mmi)
				noeuds.append(mmi)
				mm_par_item_normal[item] = mmi.multimesh
		for item in par_forme_sol.keys():
			var mmi := _mmi_de_forme(item, par_forme_sol[item], origine_col, couche_min, couche_max, taille, cote)
			if mmi != null:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mmi)
				noeuds.append(mmi)
				mm_par_item_sol[item] = mmi.multimesh
		for item in par_forme_mini.keys():
			var mmi := _mmi_mini_cubes(item, par_forme_mini[item], origine_col, couche_min, couche_max, taille, cote)
			if mmi != null:
				add_child(mmi)
				noeuds.append(mmi)
	# Index teinte de la tuile.
	var index_tuile: Dictionary = {}
	_agreger_teinte(index_tuile, teinte_normal, mm_par_item_normal)
	_agreger_teinte(index_tuile, teinte_sol, mm_par_item_sol)
	if not index_tuile.is_empty():
		_teinte_par_tuile[_tuile] = index_tuile
	etat["instances_rs"] = instances_rs
	etat["noeuds"] = noeuds
	etat["mm_par_item_normal"] = mm_par_item_normal
	etat["mm_par_item_sol"] = mm_par_item_sol

# S7 -- PHASE 2 (BAKER OCCLUDEUR + FINALISER _tuiles[tuile]). Bake l'occludeur
# greedy meshing (le lourd -- 3-5x le parsing selon Zylann/godot_voxel), l'attache,
# puis ecrit _tuiles[tuile] avec le contenu final selon le chemin (Array pour
# nœud, Dictionary pour RS direct). Rend la sentinelle Array vide obsolete -- la
# tuile est desormais consideree comme "batie".
func _phase_baker_occluder(tuile: Vector2i, etat: Dictionary) -> void:
	var parsed: Dictionary = etat["parsed"]
	var cellules_occl: Dictionary = parsed["cellules_occl"]
	var cote: float = float(parsed["cote"])
	var occluder_noeud: OccluderInstance3D = null
	if not cellules_occl.is_empty():
		var occl := _occludeur_de_cubes(cellules_occl, cote)
		if occl != null:
			add_child(occl)
			occluder_noeud = occl
	if utilise_rs_direct:
		_tuiles[tuile] = {
			"instances_rs": etat.get("instances_rs", []),
			"occluder": occluder_noeud,
		}
	else:
		var arr: Array = etat.get("noeuds", [])
		if occluder_noeud != null:
			arr.append(occluder_noeud)
		_tuiles[tuile] = arr

# LE VOISIN COUVRE-T-IL LA FACE ? Vrai seulement s'il est PLEIN a cette couche ET
# que c'est un CUBE (il remplit sa cellule entiere). Une rampe, un cylindre, une
# sphere sont "pleins" au sens du masque mais laissent un vide -- ils ne couvrent
# pas, la face du cube derriere reste visible. Hors des couches representables,
# aucun voisin : la face est exposee.
func _voisin_couvre(col: Vector2i, couche: int, masque: int, rang: int) -> bool:
	if rang < 0 or rang >= CarteTerrain.COUCHES_MAXIMALES:
		return false
	if (masque & (1 << rang)) == 0:
		return false
	var cellule := Vector3i(col.x, couche, col.y)
	if not _quad_par_item.has(carte.item_de(cellule)):
		return false
	# Cellule entamee = ne couvre pas : la face du cube en face doit rester
	# visible, le rendu classique du cube plein serait un mur solide sur la
	# geometrie sous-jacente cassee.
	return carte.sous_cubes(cellule) == CarteTerrain.MASQUE_SOUS_CUBE_PLEIN

# Pose UN mini-cube (BoxMesh de cote/3) par bit a 1 dans le masque. Position
# du centre : centre_cellule + (ix-1, iy-1, iz-1) * cote/3. Index : bit i =
# ix + iy*3 + iz*9.
func _ajouter_mini_cubes(par_forme_mini: Dictionary, item: int, centre: Vector3,
		cote: float, masque: int, pv_map: Dictionary) -> void:
	var pas := cote / 3.0
	if not par_forme_mini.has(item):
		par_forme_mini[item] = [] as Array
	var liste: Array = par_forme_mini[item]
	for i in range(27):
		if (masque & (1 << i)) == 0:
			continue
		var ix := i % 3
		@warning_ignore("integer_division")
		var iy := (i / 3) % 3
		@warning_ignore("integer_division")
		var iz := i / 9
		var offset := Vector3(
			float(ix - 1) * pas,
			float(iy - 1) * pas,
			float(iz - 1) * pas)
		# Teinte selon PV : blanc (COLOR=1) neuf, noir (COLOR=0) presque casse.
		# `carte.MAX_PV_SOUS_CUBE` : 0 -> teinte 1, MAX -> teinte 0.
		var pv: int = int(pv_map.get(i, 0))
		var t: float = clampf(1.0 - float(pv) / float(CarteTerrain.MAX_PV_SOUS_CUBE), 0.0, 1.0)
		liste.append({
			"transform": Transform3D(Basis.IDENTITY, centre + offset),
			"couleur": Color(t, t, t, 1.0),
		})

# MMi pour les mini-cubes d'un item. Mesh = _mini_box_par_item[item]. Meme
# AABB serree que _mmi_de_forme -- reutilise la meme fonction si possible.
func _mmi_mini_cubes(item: int, transforms: Array, origine_col: Vector2i,
		couche_min: int, couche_max: int, taille: int, cote: float) -> MultiMeshInstance3D:
	var bake: Dictionary = _bake_mm_mini_cubes(item, transforms, origine_col, couche_min, couche_max, taille, cote)
	if bake.is_empty():
		return null
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = bake["mm"]
	mmi.custom_aabb = bake["aabb"]
	if distance_rendu_metres > 0.0:
		mmi.visibility_range_end = distance_rendu_metres
	return mmi

# S6 -- BAKE PUR du MultiMesh + AABB pour les mini-cubes d'un item. Partage
# entre _mmi_mini_cubes (chemin nœud) et _rs_mini_cubes (chemin instance RS).
# Rend {} si l'item n'a pas de mini-box.
func _bake_mm_mini_cubes(item: int, transforms: Array, origine_col: Vector2i,
		couche_min: int, couche_max: int, taille: int, cote: float) -> Dictionary:
	var mesh: Mesh = _mini_box_par_item.get(item, null)
	if mesh == null:
		return {}
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		var t = transforms[i]
		mm.set_instance_transform(i, t.transform)
		mm.set_instance_color(i, t.couleur)
	var hauteur_couches := couche_max - couche_min + 1
	var pos_aabb := Vector3(
		float(origine_col.x) * cote - cote,
		float(couche_min) * cote - cote,
		float(origine_col.y) * cote - cote)
	var taille_aabb := Vector3(
		float(taille) * cote + 2.0 * cote,
		float(hauteur_couches) * cote + 2.0 * cote,
		float(taille) * cote + 2.0 * cote)
	return {"mm": mm, "aabb": AABB(pos_aabb, taille_aabb)}

# Ajoute une instance de quad pour la face `i` d'un cube centre en `centre` :
# translation vers le centre de la face (normale x demi-cote) et rotation qui
# oriente le quad vers le vide.
func _ajouter_face(par_forme: Dictionary, item: int, centre: Vector3, i: int, cote: float) -> int:
	var f: Dictionary = _faces[i]
	# Hauteur reelle du bloc (defaut = cote pour un cube plein). Un item plus
	# court est dessine abaisse : bas de la cellule inchange, dessus descendu.
	var h: float = float(_hauteur_par_item.get(item, cote))
	var base: Basis = f.b
	var origine: Vector3
	if i == 0:
		# Dessus : descend au sommet reel du bloc (sol de cellule + h).
		origine = centre + Vector3(0.0, h - cote * 0.5, 0.0)
	elif i == 1:
		# Dessous : inchange, au sol de la cellule.
		origine = centre + (f.n as Vector3) * (cote * 0.5)
	else:
		# Cotes : le quad partage (cote x cote) est mis a l'echelle verticale en
		# MONDE par ratio = h/cote -- base = diag(1, ratio, 1) * f.b, construite
		# colonne par colonne (Y de chaque colonne x ratio). Recentre a mi-hauteur
		# du slab pour que son bas reste au sol de la cellule.
		var ratio: float = h / cote
		base = Basis(
			Vector3(f.b.x.x, f.b.x.y * ratio, f.b.x.z),
			Vector3(f.b.y.x, f.b.y.y * ratio, f.b.y.z),
			Vector3(f.b.z.x, f.b.z.y * ratio, f.b.z.z))
		origine = centre + (f.n as Vector3) * (cote * 0.5) + Vector3(0.0, (h - cote) * 0.5, 0.0)
	var t := Transform3D(base, origine)
	if not par_forme.has(item):
		par_forme[item] = [] as Array
	par_forme[item].append(t)
	return (par_forme[item] as Array).size() - 1

# UN MultiMeshInstance3D pour une forme. Le mesh est le QUAD de la forme si elle
# est cubique (rendu face par face), sinon le mesh complet de la bibliotheque.
# `custom_aabb` serre a la boite de la tuile pour le frustum culling. Rend null
# si la forme n'a aucun maillage (ex. limite).
func _mmi_de_forme(item: int, transforms: Array, origine_col: Vector2i,
		couche_min: int, couche_max: int, taille: int, cote: float) -> MultiMeshInstance3D:
	var bake: Dictionary = _bake_mm_forme(item, transforms, origine_col, couche_min, couche_max, taille, cote)
	if bake.is_empty():
		return null
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = bake["mm"]
	mmi.custom_aabb = bake["aabb"]
	# LOD PAR DISTANCE : au-dela de `distance_rendu_metres`, Godot cesse de dessiner
	# cette tuile. 0 = pas de limite.
	if distance_rendu_metres > 0.0:
		mmi.visibility_range_end = distance_rendu_metres
	return mmi

# S6 -- BAKE PUR du MultiMesh + AABB pour une forme. Partage entre _mmi_de_forme
# (chemin nœud) et _rs_de_forme (chemin instance RS). Rend {} si la forme n'a
# aucun maillage (ex. limite).
func _bake_mm_forme(item: int, transforms: Array, origine_col: Vector2i,
		couche_min: int, couche_max: int, taille: int, cote: float) -> Dictionary:
	var mesh: Mesh = _quad_par_item.get(item, null)
	if mesh == null:
		mesh = mesh_library.get_item_mesh(item)
	if mesh == null:
		return {}
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, Color(1, 1, 1))
	# BOITE SERREE A LA TUILE, coordonnees monde (le nœud parent est a l'origine ;
	# une instance RS re-posera le même AABB dans son propre repere via set_transform
	# = self.global_transform).
	var hauteur_couches := couche_max - couche_min + 1
	var pos_aabb := Vector3(
		float(origine_col.x) * cote - cote,
		float(couche_min) * cote - cote,
		float(origine_col.y) * cote - cote)
	var taille_aabb := Vector3(
		float(taille) * cote + 2.0 * cote,
		float(hauteur_couches) * cote + 2.0 * cote,
		float(taille) * cote + 2.0 * cote)
	return {"mm": mm, "aabb": AABB(pos_aabb, taille_aabb)}

# S6 -- CREATION D'UNE INSTANCE RENDERINGSERVER DIRECTE.
# Le MultiMesh doit etre garde en REFERENCE FORTE GDScript par l'appelant (dans
# _tuiles) : sans ca, GC -> RID invalide -> instance disparait silencieusement
# (issue godotengine/godot#80479). instance_set_scenario est OBLIGATOIRE (issue
# godotengine/godot#77113) : sans lui, l'instance n'est jamais rendue.
func _creer_instance_rs(mm: MultiMesh, transform_locale: Transform3D, aabb: AABB, cast_shadow_off: bool = false) -> RID:
	var rid := RenderingServer.instance_create()
	RenderingServer.instance_set_base(rid, mm.get_rid())
	RenderingServer.instance_set_scenario(rid, get_world_3d().scenario)
	RenderingServer.instance_set_transform(rid, transform_locale)
	RenderingServer.instance_set_custom_aabb(rid, aabb)
	if cast_shadow_off:
		RenderingServer.instance_geometry_set_cast_shadows_setting(rid, RenderingServer.SHADOW_CASTING_SETTING_OFF)
	if distance_rendu_metres > 0.0:
		RenderingServer.instance_geometry_set_visibility_range(
			rid, 0.0, distance_rendu_metres, 0.0, 0.0,
			RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
	return rid

# S6 -- Wrappers "instance RS" symetriques a _mmi_de_forme / _mmi_mini_cubes.
# Retournent {"mm", "rid"} ou {} si aucun maillage. La reference forte a mm est
# stockee dans le dict retourne -> l'appelant l'insere dans _tuiles, tant que
# l'entree y est le mm ne peut pas etre GC.
func _rs_de_forme(item: int, transforms: Array, origine_col: Vector2i,
		couche_min: int, couche_max: int, taille: int, cote: float,
		cast_shadow_off: bool) -> Dictionary:
	var bake: Dictionary = _bake_mm_forme(item, transforms, origine_col, couche_min, couche_max, taille, cote)
	if bake.is_empty():
		return {}
	var rid: RID = _creer_instance_rs(bake["mm"], global_transform, bake["aabb"], cast_shadow_off)
	return {"mm": bake["mm"], "rid": rid}

func _rs_mini_cubes(item: int, transforms: Array, origine_col: Vector2i,
		couche_min: int, couche_max: int, taille: int, cote: float) -> Dictionary:
	var bake: Dictionary = _bake_mm_mini_cubes(item, transforms, origine_col, couche_min, couche_max, taille, cote)
	if bake.is_empty():
		return {}
	var rid: RID = _creer_instance_rs(bake["mm"], global_transform, bake["aabb"], false)
	return {"mm": bake["mm"], "rid": rid}

# UN OccluderInstance3D pour un SET de cellules (Vector3i -> true), bakée en
# greedy meshing par direction de face. Godot rasterise cette geometrie et
# n'affiche plus ce qui tombe entierement derriere. Les sommets sont en
# coordonnees monde (ce noeud est a l'origine), comme les MultiMesh.
#
# GREEDY MESHING (S5) : au lieu de baker N cubes = 5*N quads = 10*N triangles,
# on fusionne les faces coplanaires contigues en rectangles maximaux (patron
# Minecraft, https://0fps.net/2012/06/30/meshing-in-a-minecraft-game/). Un mur
# de 10x10x5 cubes pleins passe de 300 quads a 5 quads (un par direction). La
# resolution CELLULE est preservee : un rectangle se casse des qu'une cellule
# intermediaire manque -- un tunnel creuse au milieu d'un mur reste visible
# pour le culler, la topologie du trou est conservee.
#
# EXCLUSIONS CONSERVEES :
# - Y+ jamais (S2.5) : la boucle n'itere pas cette direction.
# - Rampes/cylindres jamais (S2.6) : l'appelant _creer_tuile filtre deja.
# - Cellules cassees (sous_cubes != PLEIN) : l'appelant les envoie en mini-
#   cubes visuels, jamais dans cellules_occl.
#
# ArrayOccluder3D est DOUBLE-FACE : winding order n'importe pas.
func _occludeur_de_cubes(cellules: Dictionary, cote: float) -> OccluderInstance3D:
	if cellules.is_empty():
		return null
	# Bornes du volume englobant.
	var premiere: Vector3i = cellules.keys()[0]
	var min_c := premiere
	var max_c := premiere
	for c in cellules:
		if c.x < min_c.x: min_c.x = c.x
		if c.y < min_c.y: min_c.y = c.y
		if c.z < min_c.z: min_c.z = c.z
		if c.x > max_c.x: max_c.x = c.x
		if c.y > max_c.y: max_c.y = c.y
		if c.z > max_c.z: max_c.z = c.z

	var sommets := PackedVector3Array()
	var indices := PackedInt32Array()

	# 5 directions. axe_t = l'axe perpendiculaire a la face (parcouru par
	# tranches). axe_u / axe_v = les axes du plan de la face. sens = +1 (face
	# regarde vers +axe_t) ou -1. La direction Y+ (axe_t=1, sens=+1) est
	# ABSENTE volontairement.
	_greedy_direction(cellules, sommets, indices, cote, min_c, max_c, 0,  1, 2, 1, Vector3( 1,  0,  0))  # X+
	_greedy_direction(cellules, sommets, indices, cote, min_c, max_c, 0, -1, 2, 1, Vector3(-1,  0,  0))  # X-
	_greedy_direction(cellules, sommets, indices, cote, min_c, max_c, 1, -1, 0, 2, Vector3( 0, -1,  0))  # Y-
	_greedy_direction(cellules, sommets, indices, cote, min_c, max_c, 2,  1, 0, 1, Vector3( 0,  0,  1))  # Z+
	_greedy_direction(cellules, sommets, indices, cote, min_c, max_c, 2, -1, 0, 1, Vector3( 0,  0, -1))  # Z-

	if indices.is_empty():
		return null
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(sommets, indices)
	var inst := OccluderInstance3D.new()
	inst.occluder = occ
	return inst

# GREEDY MESHING pour UNE direction de face. Pour chaque tranche perpendiculaire
# a axe_t, construit un masque 2D des faces actives (cellule occludante ET
# voisine dans la direction non occludante), puis fusionne en rectangles
# maximaux -- extension en largeur (axe_u) puis en hauteur (axe_v).
func _greedy_direction(cellules: Dictionary, sommets: PackedVector3Array,
		indices: PackedInt32Array, cote: float, min_c: Vector3i, max_c: Vector3i,
		axe_t: int, sens: int, axe_u: int, axe_v: int, normale: Vector3) -> void:
	var t_min: int = _val(min_c, axe_t)
	var t_max: int = _val(max_c, axe_t)
	var u_min: int = _val(min_c, axe_u)
	var u_max: int = _val(max_c, axe_u)
	var v_min: int = _val(min_c, axe_v)
	var v_max: int = _val(max_c, axe_v)
	var large_u: int = u_max - u_min + 1
	var large_v: int = v_max - v_min + 1

	for t in range(t_min, t_max + 1):
		# Masque 2D des faces actives dans cette tranche. Array plat de
		# [large_u * large_v] booleens -- une seule allocation par tranche.
		var masque: PackedByteArray = PackedByteArray()
		masque.resize(large_u * large_v)
		var toutes_a_zero := true
		for iu in range(large_u):
			for iv in range(large_v):
				var cellule := _make_cell(t, u_min + iu, v_min + iv, axe_t, axe_u, axe_v)
				if not cellules.has(cellule):
					continue
				var voisin := _make_cell(t + sens, u_min + iu, v_min + iv, axe_t, axe_u, axe_v)
				if cellules.has(voisin):
					continue  # face interne, ne pas emettre
				masque[iu * large_v + iv] = 1
				toutes_a_zero = false
		if toutes_a_zero:
			continue

		# Greedy : parcourir les cellules non traitees, etendre.
		var traite: PackedByteArray = PackedByteArray()
		traite.resize(large_u * large_v)
		for iu in range(large_u):
			for iv in range(large_v):
				var idx0 := iu * large_v + iv
				if traite[idx0] != 0 or masque[idx0] == 0:
					continue
				# Extension en u.
				var u_fin := iu
				while u_fin + 1 < large_u:
					var i_test := (u_fin + 1) * large_v + iv
					if masque[i_test] == 0 or traite[i_test] != 0:
						break
					u_fin += 1
				# Extension en v : toute la bande [iu..u_fin] a v+1 doit etre libre.
				var v_fin := iv
				while v_fin + 1 < large_v:
					var ok := true
					for uu in range(iu, u_fin + 1):
						var i_test2 := uu * large_v + (v_fin + 1)
						if masque[i_test2] == 0 or traite[i_test2] != 0:
							ok = false
							break
					if not ok:
						break
					v_fin += 1
				# Marquer le rectangle comme traite.
				for uu in range(iu, u_fin + 1):
					for vv in range(iv, v_fin + 1):
						traite[uu * large_v + vv] = 1
				# Emettre le quad (2 triangles).
				_emettre_quad_greedy(sommets, indices, cote, t, sens,
					u_min + iu, u_min + u_fin, v_min + iv, v_min + v_fin,
					axe_t, axe_u, axe_v, normale)

func _emettre_quad_greedy(sommets: PackedVector3Array, indices: PackedInt32Array,
		cote: float, t: int, _sens: int,
		u_debut: int, u_fin: int, v_debut: int, v_fin: int,
		axe_t: int, axe_u: int, axe_v: int, normale: Vector3) -> void:
	var h := cote * 0.5
	var offs_t: Vector3 = normale * h
	var u_dir: Vector3 = _axe_vec(axe_u)
	var v_dir: Vector3 = _axe_vec(axe_v)
	# 4 coins, chacun ancre a la cellule qui porte ce coin du rectangle :
	# _regle.map_to_local rend le centre de la cellule ; on ajoute le decalage
	# vers le coin (offs_t + demi-cote sur u et v).
	var c_bl := _make_cell(t, u_debut, v_debut, axe_t, axe_u, axe_v)
	var c_br := _make_cell(t, u_fin,   v_debut, axe_t, axe_u, axe_v)
	var c_tr := _make_cell(t, u_fin,   v_fin,   axe_t, axe_u, axe_v)
	var c_tl := _make_cell(t, u_debut, v_fin,   axe_t, axe_u, axe_v)
	var p_bl: Vector3 = _regle.map_to_local(c_bl) + offs_t + u_dir * (-h) + v_dir * (-h)
	var p_br: Vector3 = _regle.map_to_local(c_br) + offs_t + u_dir * ( h) + v_dir * (-h)
	var p_tr: Vector3 = _regle.map_to_local(c_tr) + offs_t + u_dir * ( h) + v_dir * ( h)
	var p_tl: Vector3 = _regle.map_to_local(c_tl) + offs_t + u_dir * (-h) + v_dir * ( h)
	var base := sommets.size()
	sommets.append(p_bl)
	sommets.append(p_br)
	sommets.append(p_tr)
	sommets.append(p_tl)
	# Double-face (ArrayOccluder3D), l'ordre n'importe pas pour l'occlusion.
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base)
	indices.append(base + 2)
	indices.append(base + 3)

# Utilitaires d'axe (Vector3i n'accepte pas d'acces par indice).
func _val(v: Vector3i, axe: int) -> int:
	if axe == 0: return v.x
	if axe == 1: return v.y
	return v.z

func _make_cell(t: int, u: int, v: int, axe_t: int, axe_u: int, axe_v: int) -> Vector3i:
	var c := Vector3i(0, 0, 0)
	if axe_t == 0: c.x = t
	elif axe_t == 1: c.y = t
	else: c.z = t
	if axe_u == 0: c.x = u
	elif axe_u == 1: c.y = u
	else: c.z = u
	if axe_v == 0: c.x = v
	elif axe_v == 1: c.y = v
	else: c.z = v
	return c

func _axe_vec(axe: int) -> Vector3:
	if axe == 0: return Vector3(1, 0, 0)
	if axe == 1: return Vector3(0, 1, 0)
	return Vector3(0, 0, 1)

# Drain des colonnes modifiees. Pour chacune : sa tuile est reconstruite
# SYNCHRONEMENT dans la meme frame. Passer par `_file_creation` etalerait la
# reconstruction sur 1+ frames pendant lesquelles le rendu ET l'occludeur
# sont deja detruits -- resultat visible : le joueur regarde a travers un
# trou creuse et voit le VIDE en dessous, puis le rendu revient. Un rebuild
# de tuile isolee coute < 5ms, largement acceptable au rythme d'un tir.
# La file etalee reste utilisee pour les entrees/sorties de disque
# (anneau de ~25 tuiles d'un coup), la ou l'etalement gagne 120ms de pic.
# Tuile hors disque ou en attente de creation : ignoree.
func _absorber_modifications_carte() -> void:
	var modifs: Array = carte.drainer_modifications("rendu_terrain_multimesh")
	if modifs.is_empty():
		return
	# COLLECTE. Une tuile touchee par N colonnes modifiees ne se rebuild qu'UNE
	# fois : le Set dedoublonne. Avant, N colonnes -> N _supprimer_tuile + N
	# _creer_tuile + N rebuilds du BVH d'occludeur -- une salve de tir dans le
	# meme carre coutait 10 rebuilds pour 10 sous-cubes.
	var tuiles_a_reconstruire: Dictionary = {}
	for colonne in modifs:
		var t: Vector2i = _tuile_de_colonne(colonne)
		if not _tuiles.has(t):
			continue
		# En file (sentinelle Array vide) : trois sous-cas.
		# - Pas en pipeline : file classique, sera batie au drain avec l'etat a jour -> skip.
		# - En pipeline phase 0 : rien encore parse, le drain lira l'etat a jour -> skip.
		# - En pipeline phase >= 1 : `parsed` deja fige mais perime -> reconstruire.
		# Batie (Array non vide OU Dictionary rs_direct) : reconstruire.
		var contenu = _tuiles[t]
		var est_sentinelle: bool = contenu is Array and (contenu as Array).is_empty()
		if est_sentinelle:
			if not _tuiles_en_pipeline.has(t):
				continue
			var phase: int = int(_tuiles_en_pipeline[t].get("phase", 0))
			if phase == 0:
				continue
		tuiles_a_reconstruire[t] = true
	# REBUILD. Une passe, une par tuile.
	for t in tuiles_a_reconstruire:
		_a_supprimer.erase(t)
		_supprimer_tuile(t)
		_tuiles[t] = []
		_creer_tuile(t)

func _tuile_de_colonne(colonne: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(colonne.x) / float(taille_tuile_cellules))),
		int(floor(float(colonne.y) / float(taille_tuile_cellules))))

func _supprimer_tuile(tuile: Vector2i) -> void:
	# S7 -- Purger le pipeline AVANT tout autre nettoyage. Si la tuile a atteint
	# phase 1 (instances bakees), libere aussi les ressources partielles (RIDs RS
	# ou nœuds MMi) que _tuiles ne connait pas encore (sentinelle Array vide).
	if _tuiles_en_pipeline.has(tuile):
		var etat: Dictionary = _tuiles_en_pipeline[tuile]
		var phase: int = int(etat.get("phase", 0))
		if phase >= 2:
			# Phase 1 done : instances (RS ou nœud) existent. Libere-les.
			var rs_list: Array = etat.get("instances_rs", []) as Array
			for e in rs_list:
				var rid: RID = e["rid"]
				if rid.is_valid():
					RenderingServer.free_rid(rid)
			var noeuds_partiels: Array = etat.get("noeuds", []) as Array
			for n in noeuds_partiels:
				if is_instance_valid(n):
					n.queue_free()
		_tuiles_en_pipeline.erase(tuile)
	if not _tuiles.has(tuile):
		return
	var contenu = _tuiles[tuile]
	if contenu is Array:
		# CHEMIN NŒUD : Array de MultiMeshInstance3D + eventuel OccluderInstance3D.
		for mmi in (contenu as Array):
			if is_instance_valid(mmi):
				mmi.queue_free()
	elif contenu is Dictionary:
		# CHEMIN RS DIRECT : liberer les RIDs d'instances AVANT d'oublier les mm
		# (free_rid libere l'instance qui pointait sur mm.get_rid() ; la ref forte
		# a mm est dans le dict, GC quand on erase l'entree). Puis queue_free de
		# l'occludeur (reste un nœud dans les deux chemins).
		var d: Dictionary = contenu as Dictionary
		var rs_list: Array = d.get("instances_rs", []) as Array
		for e in rs_list:
			var rid: RID = e["rid"]
			if rid.is_valid():
				RenderingServer.free_rid(rid)
		var occl: OccluderInstance3D = d.get("occluder", null)
		if occl != null and is_instance_valid(occl):
			occl.queue_free()
	_tuiles.erase(tuile)
	# Nettoyage index teinte : les cellules de cette tuile disparaissent aussi
	# de _teinte_precedente pour re-teinter proprement si la tuile revient.
	if _teinte_par_tuile.has(tuile):
		var idx: Dictionary = _teinte_par_tuile[tuile]
		for cellule in idx:
			_teinte_precedente.erase(cellule)
			_cache_profil_cellule.erase(cellule)
			_cache_quantite_cellule.erase(cellule)
		_teinte_par_tuile.erase(tuile)

# Helper : memorise (cellule, idx) dans un bucket item -> Array. Appele au
# streaming pour chaque face teintable.
func _pousser_teinte(bucket: Dictionary, item: int, cellule: Vector3i, idx: int) -> void:
	if not bucket.has(item):
		bucket[item] = [] as Array
	(bucket[item] as Array).append({"cellule": cellule, "idx": idx})

# Helper : agrege un bucket (item -> [{cellule, idx}]) dans l'index de tuile
# (cellule -> [{mm, idx}]) en resolvant l'item vers son MultiMesh. Unifie entre
# les deux chemins : `mm` cote GPU est le meme que le porteur soit MMi ou instance
# RS -- le tick de teinte n'a pas a brancher sur le flag.
func _agreger_teinte(index_tuile: Dictionary, bucket: Dictionary, mm_par_item: Dictionary) -> void:
	for item in bucket:
		var mm: MultiMesh = mm_par_item.get(item, null)
		if mm == null:
			continue
		for entree in (bucket[item] as Array):
			var cellule: Vector3i = entree["cellule"]
			if not index_tuile.has(cellule):
				index_tuile[cellule] = [] as Array
			(index_tuile[cellule] as Array).append({"mm": mm, "idx": int(entree["idx"])})

# Tick de teinte : parcourt les cellules teintables de toutes les tuiles
# chargees, calcule un gain [0.4..1.0] selon la reserve courante, pose la
# couleur d'instance. Cache la derniere teinte par cellule pour eviter les
# set_instance_color inutiles (aucune reserve n'a change).
func _tick_teinte() -> void:
	if _teinte_par_tuile.is_empty():
		return
	if _ressources == null:
		_ressources = get_tree().get_first_node_in_group(&"ressources_terrain")
		if _ressources == null:
			return
	for tuile in _teinte_par_tuile:
		var index: Dictionary = _teinte_par_tuile[tuile]
		for cellule in index:
			var profil: Resource = _cache_profil_cellule.get(cellule) as Resource
			if profil == null:
				continue
			var cap: int = int(profil.get("reserve"))
			if cap <= 0:
				continue
			var q: int = int(_cache_quantite_cellule.get(cellule, 0))
			var ratio: float = clampf(float(q) / float(cap), 0.0, 1.0)
			var gain: float = TEINTE_GAIN_VIDE + (1.0 - TEINTE_GAIN_VIDE) * ratio
			var prec: float = float(_teinte_precedente.get(cellule, -1.0))
			if absf(gain - prec) < 0.005:
				continue
			_teinte_precedente[cellule] = gain
			var couleur := Color(gain, gain, gain)
			for face in (index[cellule] as Array):
				# `mm` (MultiMesh) : ref forte tenue via _tuiles (nœud MMi ou entree
				# {mm, rid}) ; purge de _teinte_par_tuile faite dans _supprimer_tuile
				# AVANT que la ref ne disparaisse -> pas de check de validite ici.
				var mm: MultiMesh = face["mm"]
				mm.set_instance_color(int(face["idx"]), couleur)

# ETAPE (a) -- assemble le blob d'entree pour MesheurTuile.bake_tuile_a. Voir
# l'entete de extension_terrain/src/mesheur_tuile.h pour le contrat. Le blob
# tient tout ce que le C++ doit lire sur la tuile + ses 4 anneaux (12x12), plus
# les tables qui ne bougent pas d'une tuile a l'autre (items cubiques,
# hauteurs). Le C++ ne rappelle jamais la carte apres reception.
func _blob_tuile_a(origine_col: Vector2i, cote: float, couche_base: int,
		particularites: Dictionary) -> Dictionary:
	var taille := taille_tuile_cellules
	var wsize := taille + 2
	var masques := PackedInt64Array()
	var couvrants := PackedInt64Array()
	masques.resize(wsize * wsize)
	couvrants.resize(wsize * wsize)
	var memo_bits: Dictionary = {}
	var memo_couvrant: Dictionary = {}
	for lx in range(-1, taille + 1):
		for lz in range(-1, taille + 1):
			var col := Vector2i(origine_col.x + lx, origine_col.y + lz)
			var idx := (lx + 1) + (lz + 1) * wsize
			masques[idx] = _masque_col(col, memo_bits)
			couvrants[idx] = _masque_couvrant_col(col, memo_couvrant)

	# Particularites de la tuile SEULE. Iteration par cellule via le masque de
	# chaque colonne : cout borne a taille² × r_top, jamais lie a la taille
	# globale du dict `particularites` de la carte.
	var part_arr := PackedInt32Array()
	var sc_arr := PackedInt32Array()
	var pv_arr := PackedInt32Array()
	for lx in range(taille):
		for lz in range(taille):
			var col := Vector2i(origine_col.x + lx, origine_col.y + lz)
			var bits: int = masques[(lx + 1) + (lz + 1) * wsize]
			if bits == 0:
				continue
			var r_top := CarteTerrain.rang_le_plus_haut(bits)
			for rang in range(r_top + 1):
				if (bits & (1 << rang)) == 0:
					continue
				var cellule := Vector3i(col.x, couche_base + rang, col.y)
				if particularites.has(cellule):
					part_arr.append(cellule.x)
					part_arr.append(cellule.y)
					part_arr.append(cellule.z)
					part_arr.append(int(particularites[cellule]))
				var m: int = int(carte.sous_cubes(cellule))
				if m != CarteTerrain.MASQUE_SOUS_CUBE_PLEIN:
					sc_arr.append(cellule.x)
					sc_arr.append(cellule.y)
					sc_arr.append(cellule.z)
					sc_arr.append(m)
				var pv_map: Dictionary = carte.pv_sous_cubes_cellule(cellule)
				if not pv_map.is_empty():
					pv_arr.append(cellule.x)
					pv_arr.append(cellule.y)
					pv_arr.append(cellule.z)

	# Tables item -> cubique / hauteur. Petites (une entree par forme de la
	# bibliotheque), reconstruites a chaque tuile car peu couteuses.
	var items_cub := PackedInt32Array()
	for item in _quad_par_item.keys():
		items_cub.append(int(item))
	var h_cle := PackedInt32Array()
	var h_val := PackedFloat32Array()
	for item in _hauteur_par_item.keys():
		h_cle.append(int(item))
		h_val.append(float(_hauteur_par_item[item]))

	# Offset de centre : ce que _regle.map_to_local rend pour la cellule (0,0,0).
	# Passe pour ne pas dependre des defauts cell_center_x/y/z du GridMap dans
	# le C++.
	var centre_offset: Vector3 = _regle.map_to_local(Vector3i(0, 0, 0))

	return {
		"origine_col": origine_col,
		"taille": taille,
		"couche_base": couche_base,
		"couches_max": CarteTerrain.COUCHES_MAXIMALES,
		"cote": cote,
		"sommet_base": int(carte.sommet_de_base()),
		"item_limite": ITEM_LIMITE,
		"item_defaut": CarteTerrain.ITEM_DEFAUT,
		"orientation_defaut": CarteTerrain.ORIENTATION_DEFAUT,
		"masque_sous_plein": CarteTerrain.MASQUE_SOUS_CUBE_PLEIN,
		"centre_offset": centre_offset,
		"masques": masques,
		"couvrants": couvrants,
		"particularites": part_arr,
		"sous_cubes_partiels": sc_arr,
		"cellules_pv": pv_arr,
		"items_cubiques": items_cub,
		"items_hauteur_cle": h_cle,
		"items_hauteur_val": h_val,
	}

# ETAPE (a) -- appelle MesheurTuile.bake_tuile_a et integre son resultat dans
# les buckets locaux de _phase_parser. Le C++ produit les faces cubes propres
# (par item, normal et sol). Le mapping face->cellule sert a repousser la
# teinte a partir du cache _cache_profil_cellule deja alimente par la boucle.
func _appliquer_cpp_a(par_forme: Dictionary, par_forme_sol: Dictionary,
		teinte_normal: Dictionary, teinte_sol: Dictionary,
		origine_col: Vector2i, cote: float, couche_base: int,
		particularites: Dictionary) -> void:
	if _mesheur == null:
		_mesheur = ClassDB.instantiate("MesheurTuile")
		if _mesheur == null:
			push_error("MesheurTuile introuvable -- extension_terrain non chargee")
			return
	var blob := _blob_tuile_a(origine_col, cote, couche_base, particularites)
	var res: Dictionary = _mesheur.call("bake_tuile_a", blob)
	_integrer_cpp(res.get("par_forme", {}), par_forme, teinte_normal)
	_integrer_cpp(res.get("par_forme_sol", {}), par_forme_sol, teinte_sol)

# ETAPE (a) -- pour chaque item, appende les transforms produits par le C++ a
# `dst_par_forme[item]` et pousse une paire teinte pour chaque face dont la
# cellule d'origine porte un profil (present dans _cache_profil_cellule, deja
# alimente par la boucle _phase_parser). L'index pousse est la position DANS
# le bucket final, decalee de la taille avant append (pour supporter un futur
# cas ou dst_par_forme[item] ne serait pas vide -- aujourd'hui il l'est pour
# les items cubiques, l'emission GDScript des cubes propres etant gatee).
func _integrer_cpp(src: Dictionary, dst_par_forme: Dictionary, dst_teinte: Dictionary) -> void:
	for item in src.keys():
		var entree: Dictionary = src[item]
		var transforms: Array = entree.get("transforms", [])
		var cellules: PackedInt32Array = entree.get("cellules", PackedInt32Array())
		var n: int = transforms.size()
		if n == 0:
			continue
		if not dst_par_forme.has(item):
			dst_par_forme[item] = [] as Array
		var bucket: Array = dst_par_forme[item]
		var offset: int = bucket.size()
		for k in range(n):
			bucket.append(transforms[k])
			var cellule := Vector3i(cellules[k * 3], cellules[k * 3 + 1], cellules[k * 3 + 2])
			if _cache_profil_cellule.has(cellule):
				_pousser_teinte(dst_teinte, int(item), cellule, offset + k)
