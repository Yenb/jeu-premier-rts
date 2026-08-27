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
	_rafraichir_vers(_centre_tuile_observateur())

# UN QUAD PAR FORME CUBIQUE. Chaque cube (BoxMesh) sera rendu face par face au
# lieu d'un cube plein. Le quad porte le materiau du cube, en DOUBLE FACE pour
# ne jamais laisser de trou si une face etait orientee a l'envers.
func _preparer_quads(cote: float) -> void:
	for item in mesh_library.get_item_list():
		var mesh := mesh_library.get_item_mesh(item)
		if not (mesh is BoxMesh):
			continue
		var quad := PlaneMesh.new()
		quad.size = Vector2(cote, cote)
		var mat := (mesh as BoxMesh).material
		if mat is BaseMaterial3D:
			var mat2 := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			mat2.cull_mode = BaseMaterial3D.CULL_DISABLED
			# ALLEGE LE FRAGMENT DU SOL SANS TOUCHER A LA LUMIERE NI A L'OMBRE.
			# Le sol est de la couleur unie : il n'a ni metal, ni reflet, ni relief
			# speculaire a calculer. On coupe tout le calcul PBR inutile -- speculaire,
			# metal, rugosite variable -- et on garde l'eclairage diffus + l'ombre en
			# PER-PIXEL (shading_mode non touche), donc l'ombre reste nette. Diffuse
			# Lambert au lieu de Burley : la BRDF diffuse la moins chere. C'est la passe
			# opaque du sol qui domine le GPU ; ce fragment allege agit dessus.
			mat2.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			mat2.metallic = 0.0
			mat2.roughness = 1.0
			mat2.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
			quad.material = mat2
		elif mat != null:
			quad.material = mat
		_quad_par_item[item] = quad

func _process(_delta: float) -> void:
	var centre := _centre_tuile_observateur()
	if _doit_rafraichir(centre):
		_rafraichir_vers(centre)
	# ETALEMENT : quelques tuiles par frame, jamais tout l'anneau d'un coup.
	var faits := 0
	while faits < tuiles_par_frame and not _file_creation.is_empty():
		var t: Vector2i = _file_creation.pop_back()
		# Sautee si retiree du disque entre-temps (le joueur a bouge) : elle n'est
		# plus dans _tuiles, ou elle a deja ete batie.
		if _tuiles.has(t) and (_tuiles[t] as Array).is_empty():
			_creer_tuile(t)
			faits += 1

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
			# MARQUEE EN FILE (Array vide) : _process la batira. La marquer tout de
			# suite empeche un rafraichissement suivant de la re-mettre en file.
			_tuiles[t] = []
			_file_creation.append(t)
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

	# forme (item) -> Array[Transform3D]. Deux groupes pour l'OMBRE, selon le NIVEAU
	# du cube. `par_forme` : tout ce qui EMERGE (relief, murs, batiments) et les
	# formes non-cube -> projette normalement. `par_forme_sol` : le sol de base
	# (couche == sommet_de_base) -> `cast_shadow off`, car un sol plat ne jette
	# aucune ombre utile (elle tomberait sous lui) et les passes d'ombre ignorent
	# l'occlusion : l'y garder re-dessine tout le sol pour rien. Il RECOIT toujours
	# les ombres des objets poses dessus.
	var par_forme: Dictionary = {}
	var par_forme_sol: Dictionary = {}
	# HAUTEUR REELLE DE LA TUILE, suivie au fil des poses : l'AABB s'y serre pour
	# que le frustum culling ecarte les tuiles hors champ. Un AABB haut de toutes
	# les couches possibles ne se ferait jamais culler.
	var couche_min := couche_base + CarteTerrain.COUCHES_MAXIMALES
	var couche_max := couche_base
	# LE SOL DE BASE N'OCCULTE RIEN (il est plat). Seuls les cubes qui EMERGENT
	# au-dessus du sommet de base -- murs, batiments, relief -- bloquent la vue et
	# entrent dans l'occludeur. Le sol plat streame en permanence ; l'en exclure
	# evite une recomputation d'occlusion a chaque pas.
	var sommet_base := int(carte.sommet_de_base())
	var positions_occl: Array[Vector3] = []

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
				# Position du centre de la cellule par la conversion native.
				var pos := _regle.map_to_local(cellule)
				# LE SOL DE BASE (couche == sommet) ne projette pas d'ombre ; tout ce
				# qui emerge projette. Le RENDU (les faces) est identique dans les deux
				# cas -- seul le GROUPE change, donc le cast_shadow du MMi.
				var cible: Dictionary = par_forme_sol if couche == sommet_base else par_forme
				if _quad_par_item.has(item):
					# CUBE : un quad par face exposee. Une face n'est CACHEE que si le
					# voisin de ce cote est un CUBE PLEIN (il remplit sa cellule). Un
					# voisin vide, ou une rampe/cylindre/sphere qui ne remplit pas sa
					# cellule, laisse la face visible -- sinon un trou apparait.
					if not _voisin_couvre(col, couche + 1, bits, rang + 1):
						_ajouter_face(cible, item, pos, 0, cote)
					if not _voisin_couvre(col, couche - 1, bits, rang - 1):
						_ajouter_face(cible, item, pos, 1, cote)
					if not _voisin_couvre(Vector2i(col.x + 1, col.y), couche, nxp, rang):
						_ajouter_face(cible, item, pos, 2, cote)
					if not _voisin_couvre(Vector2i(col.x - 1, col.y), couche, nxm, rang):
						_ajouter_face(cible, item, pos, 3, cote)
					if not _voisin_couvre(Vector2i(col.x, col.y + 1), couche, nzp, rang):
						_ajouter_face(cible, item, pos, 4, cote)
					if not _voisin_couvre(Vector2i(col.x, col.y - 1), couche, nzm, rang):
						_ajouter_face(cible, item, pos, 5, cote)
				else:
					# FORME NON-CUBE (rampe, cylindre, sphere) : mesh complet, orientee.
					# Elle a du volume -> projette toujours (jamais dans par_forme_sol).
					var base := _regle.get_basis_with_orthogonal_index(orientation)
					var t := Transform3D(base, pos) * mesh_library.get_item_mesh_transform(item)
					if not par_forme.has(item):
						par_forme[item] = [] as Array
					par_forme[item].append(t)
				couche_min = mini(couche_min, couche)
				couche_max = maxi(couche_max, couche)
				if couche > sommet_base:
					positions_occl.append(pos)

	var noeuds: Array = []
	for item in par_forme.keys():
		var mmi := _mmi_de_forme(item, par_forme[item], origine_col, couche_min, couche_max, taille, cote)
		if mmi != null:
			add_child(mmi)
			noeuds.append(mmi)
	# LE SOL DE BASE NE PROJETTE PAS : il quitte les passes d'ombre. Il RECOIT
	# toujours les ombres des objets poses dessus -- `cast_shadow` ne touche que la
	# projection, jamais la reception.
	for item in par_forme_sol.keys():
		var mmi := _mmi_de_forme(item, par_forme_sol[item], origine_col, couche_min, couche_max, taille, cote)
		if mmi != null:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			noeuds.append(mmi)
	# L'OCCLUDEUR DU RELIEF, s'il y en a. Ce qui est derriere ces cubes -- autres
	# cubes, arbres, unites -- n'est plus dessine par Godot.
	if not positions_occl.is_empty():
		var occl := _occludeur_de_cubes(positions_occl, cote)
		add_child(occl)
		noeuds.append(occl)
	_tuiles[tuile] = noeuds

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
	return _quad_par_item.has(carte.item_de(Vector3i(col.x, couche, col.y)))

# Ajoute une instance de quad pour la face `i` d'un cube centre en `centre` :
# translation vers le centre de la face (normale x demi-cote) et rotation qui
# oriente le quad vers le vide.
func _ajouter_face(par_forme: Dictionary, item: int, centre: Vector3, i: int, cote: float) -> void:
	var f: Dictionary = _faces[i]
	var t := Transform3D(f.b, centre + (f.n as Vector3) * (cote * 0.5))
	if not par_forme.has(item):
		par_forme[item] = [] as Array
	par_forme[item].append(t)

# UN MultiMeshInstance3D pour une forme. Le mesh est le QUAD de la forme si elle
# est cubique (rendu face par face), sinon le mesh complet de la bibliotheque.
# `custom_aabb` serre a la boite de la tuile pour le frustum culling. Rend null
# si la forme n'a aucun maillage (ex. limite).
func _mmi_de_forme(item: int, transforms: Array, origine_col: Vector2i,
		couche_min: int, couche_max: int, taille: int, cote: float) -> MultiMeshInstance3D:
	var mesh: Mesh = _quad_par_item.get(item, null)
	if mesh == null:
		mesh = mesh_library.get_item_mesh(item)
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
	# Hauteur = la plage REELLE des couches posees dans cette tuile, plus une
	# marge d'une cellule pour le debord du mesh. Serree, elle laisse le frustum
	# culling ecarter la tuile hors champ ; haute de toutes les couches, jamais.
	var hauteur_couches := couche_max - couche_min + 1
	var pos_aabb := Vector3(
		float(origine_col.x) * cote - cote,
		float(couche_min) * cote - cote,
		float(origine_col.y) * cote - cote)
	var taille_aabb := Vector3(
		float(taille) * cote + 2.0 * cote,
		float(hauteur_couches) * cote + 2.0 * cote,
		float(taille) * cote + 2.0 * cote)
	mmi.custom_aabb = AABB(pos_aabb, taille_aabb)
	# LOD PAR DISTANCE : au-dela de `distance_rendu_metres`, Godot cesse de dessiner
	# cette tuile. 0 = pas de limite.
	if distance_rendu_metres > 0.0:
		mmi.visibility_range_end = distance_rendu_metres
	return mmi

# UN OccluderInstance3D pour une liste de cubes (leurs centres). Chaque cube est
# une boite fermee de cote `cote` ; Godot rasterise cette geometrie et n'affiche
# plus ce qui tombe entierement derriere. Les sommets sont en coordonnees monde
# (ce noeud est a l'origine), comme les MultiMesh.
func _occludeur_de_cubes(positions: Array, cote: float) -> OccluderInstance3D:
	var h := cote * 0.5
	var coins := [
		Vector3(-h, -h, -h), Vector3(h, -h, -h), Vector3(h, -h, h), Vector3(-h, -h, h),
		Vector3(-h, h, -h), Vector3(h, h, -h), Vector3(h, h, h), Vector3(-h, h, h)]
	var faces := [
		0, 2, 1, 0, 3, 2,
		4, 5, 6, 4, 6, 7,
		0, 1, 5, 0, 5, 4,
		1, 2, 6, 1, 6, 5,
		2, 3, 7, 2, 7, 6,
		3, 0, 4, 3, 4, 7]
	var sommets := PackedVector3Array()
	var indices := PackedInt32Array()
	var base := 0
	for c in positions:
		for coin in coins:
			sommets.append(c + coin)
		for idx in faces:
			indices.append(base + idx)
		base += 8
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(sommets, indices)
	var inst := OccluderInstance3D.new()
	inst.occluder = occ
	return inst

func _supprimer_tuile(tuile: Vector2i) -> void:
	if not _tuiles.has(tuile):
		return
	var noeuds = _tuiles[tuile]
	if noeuds != null:
		for mmi in noeuds:
			if is_instance_valid(mmi):
				mmi.queue_free()
	_tuiles.erase(tuile)
