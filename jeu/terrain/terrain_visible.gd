extends GridMap

# POSE LES CELLULES DE COLLISION du terrain proche autour de l'observateur. Il
# lit une carte_terrain.gd et pose, dans ses propres cellules, les colonnes qui
# tombent dans un rayon autour de l'observateur. La carte est la seule autorite
# sur ce qui est plein ; ce noeud n'en decide rien.
#
# Entree : une carte (exportee), un rayon en cellules, un groupe ou trouver
# l'observateur. Sortie : ses cellules, posees et effacees au fil des
# deplacements.
#
# IL NE DESSINE RIEN : sa bibliotheque finale est privee de ses maillages
# (sans_mesh), les formes de collision restent. Le sol est dessine par le
# TerrainStreame ; ce noeud ne sert qu'a porter le joueur.
#
# LE COMPTE DE CELLULES EST BORNE PAR LE RAYON, jamais par la carte : le cout
# suit r². Un GridMap qui porterait la carte entiere bornerait l'emprise bien
# avant que le jeu ne le demande.
#
# L'OBSERVATEUR SE TROUVE PAR GROUPE, jamais par un champ a remplir sur chaque
# type. Sans observateur, le disque se pose autour de l'origine -- cas neutre,
# pas une panne.
#
# LE CALCUL EST HORS DE _process, en fonctions statiques : la boucle d'images
# declenche, elle ne calcule jamais. Ce qui decide de la pose se verrouille sans
# moteur de rendu ni clavier.
#
# LA GEOMETRIE DE LA CELLULE N'EST PAS SUPPOSEE : la colonne sous une position se
# demande a local_to_map. LA TAILLE DE LA CELLULE SE LIT SUR LA CARTE (`cote`),
# jamais reglee ici -- sinon deux verites divergeraient, celle de la scene
# gagnant en silence.
#
# IL REPREND LA BIBLIOTHEQUE DE JEU DE LA SCENE avant de poser : l'outil de
# sculpture y laisse une bibliotheque sans collision, qui rendrait le sol
# traversable en jeu. Ce que la scene transporte ne fait pas autorite.
#
# IL PREND LE TRAVAIL SCULPTE QUE LA SCENE PORTE, l'ecrit dans la carte, puis
# efface et redessine : ce qui est dans le GridMap de la scene est du travail,
# pas un residu. La grille part vide ensuite, et le compte redevient borne par
# le seul rayon.
#
# LE RAFRAICHISSEMENT A UN SEUIL (`pas_de_rafraichissement`) : le rayon garanti
# est `rayon_cellules - pas_de_rafraichissement`. Pose et effacement partent dans
# deux files (`_a_poser`, `_a_effacer`), drainees par `_process` a raison de
# `colonnes_par_image`. `rafraichir()` reste synchrone : elle pose le premier
# affichage, et c'est elle que verrouillent les tests.
#
# UN SEUIL FRANCHI PENDANT QU'UNE FILE SE VIDE NE LA REDEMARRE PAS : `_retargeter`
# ajuste les deux files a la nouvelle cible. Une colonne qui redevient visee sort
# de la file d'effacement, une colonne qui ne l'est plus sort de la file de pose,
# sans qu'un bloc bouge.
#
# IL DRAINE LA CARTE A CHAQUE `_process`. Une colonne modifiee en jeu (creusee
# par une balle, par exemple) est publiee par `carte_terrain.drainer_modifications`
# ; ce noeud efface puis re-pose la colonne si elle est deja posee dans son
# disque. Une colonne hors disque est ignoree -- elle sera posee correctement
# quand elle rentrera dans le disque, la carte est autoritative.
#
# Regles tenues : positions en Vector3, jamais Vector2 -- une COLONNE est un
# Vector2i, un index et pas une position. Aucun hasard. Aucun texte visible par
# le joueur. Aucun nom de contenu. Rien de scripts/, data/ ni documents/ n'est
# lu ni ecrit.

const Commun = preload("res://jeu/terrain/terrain_commun.gd")
const Outil = preload("res://jeu/terrain/outil_fenetre.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")

# La carte a dessiner. Sans elle, ce noeud ne pose rien et le dit.
@export var carte: Resource

# Rayon du disque pose, EN CELLULES. Le compte de cellules posees vaut
# π·rayon² × couches, et ne depend d'aucune autre grandeur.
@export var rayon_cellules: int = 50

# De combien de cellules l'observateur doit s'ecarter du centre pose avant
# qu'on retouche quoi que ce soit.
@export var pas_de_rafraichissement: int = 4

# Ou se trouve celui autour de qui le terrain se dessine.
@export var groupe_observateur: StringName = &"observateur"

# COMBIEN DE COLONNES DRAINER PAR IMAGE, en jeu. Voir l'en-tete pour la
# mesure : cent vingt colonnes tiennent sous 2 ms, et laissent le reste de
# l'image au moteur physique, au rendu, a la vegetation.
@export var colonnes_par_image: int = 120

# L'ensemble des colonnes actuellement posees : colonne -> true. Il n'est jamais
# deduit du GridMap -- get_used_cells couterait une lecture de tout ce qui est
# pose a chaque rafraichissement.
var _pose: Dictionary = {}
var _centre_pose: Vector2i = Vector2i.ZERO
var _amorce := false

# CE QUI ATTEND D'ETRE POSE OU EFFACE, colonne -> true. Draine par
# `_avancer_file`, ajuste par `_retargeter`. Voir l'en-tete.
var _a_poser: Dictionary = {}
var _a_effacer: Dictionary = {}
var _bloc := GridMap.INVALID_CELL_ITEM
# Cellules entamees : leur collision ne peut pas etre portee par le GridMap
# (une case = un item, pas 27 sous-collisions). On pose un StaticBody3D
# externe avec N BoxShape3D enfants. Ce dict garde la reference pour
# pouvoir les detruire au rebuild de colonne.
var _bodies_cellules_cassees: Dictionary = {}  # Vector3i cellule -> StaticBody3D
# INDEX SECONDAIRE : colonne -> Array[Vector3i]. Tenu strictement en parallele
# de _bodies_cellules_cassees : toute ecriture/suppression dans le dict primaire
# passe par _inscrire_body / _retirer_body, jamais directement. Sans cet index,
# _effacer_bodies_sous_cubes balayait toutes les cles du dict primaire et
# filtrait sur x/z -- cout O(N) par colonne alors que k cellules sont concernees.
var _bodies_par_colonne: Dictionary = {}  # Vector2i colonne -> Array[Vector3i]

func _ready() -> void:
	# CE GRIDMAP NE DESSINE RIEN : sa bibliotheque finale est privee de
	# ses maillages (sans_mesh), les formes de collision restent. Il ne
	# sert qu'a porter le joueur -- le TerrainStreame dessine le sol, y
	# compris sous les pieds. La collision native GridMap est le seul sol
	# physique fiable : celle du TerrainStreame ne retient pas le joueur.
	_bloc = Commun.premier_bloc(self)
	if carte == null:
		push_error("terrain_visible sans carte : rien a dessiner")
		return
	if _bloc == GridMap.INVALID_CELL_ITEM:
		return
	# LA CARTE DIT LA TAILLE DE SA CELLULE, la scene ne la redit pas.
	cell_size = Vector3(carte.cote, carte.cote, carte.cote)

	# LA COLLISION SE REPREND AVANT DE DESSINER. Voir l'en-tete.
	var de_jeu := Commun.bibliotheque_de_jeu_fraternelle(self)
	if de_jeu != null and de_jeu != mesh_library:
		print("terrain_visible : la scene portait une bibliotheque d'edition, "
			+ "celle du jeu est reprise -- sans quoi le sol serait traversable")
		mesh_library = de_jeu
		_bloc = Commun.premier_bloc(self)
	# Voir l'en-tete : ce que la scene transporte est du TRAVAIL, on le prend
	# avant de l'effacer.
	var transportees := get_used_cells().size()
	if transportees > 0:
		# RIEN NE S'EFFACE TOUT SEUL : on prend ce que la scene porte, on ne
		# retire jamais ce qu'elle ne porte pas. Voir outil_fenetre.gd.
		var prises := Outil.enregistrer_ce_qui_est_pose(self, carte)
		if prises > 0:
			print("terrain_visible : %d colonnes reprises de la scene et ecrites dans la carte" % prises)
		clear()
		print("terrain_visible : %d cellules transportees par la scene, reprises puis effacees" % transportees)
	# LE RENDU EST COUPE, LA COLLISION RESTE. La bibliotheque finale est privee
	# de ses maillages : chaque cellule posee cree sa forme de collision et ne
	# dessine rien. Inconditionnel -- quelle que soit la source de la biblio,
	# ce GridMap ne rend jamais.
	mesh_library = sans_mesh(mesh_library)
	_bloc = Commun.premier_bloc(self)
	_rafraichir_vers(_centre_observateur())

func _process(_delta: float) -> void:
	if carte == null or _bloc == GridMap.INVALID_CELL_ITEM:
		return
	_absorber_modifications_carte()
	var centre := _centre_observateur()
	if doit_rafraichir(_centre_pose, centre, pas_de_rafraichissement, _amorce):
		_retargeter(centre)
	if not _a_poser.is_empty() or not _a_effacer.is_empty():
		_avancer_file()

# Drain des colonnes modifiees. Une colonne posee dans le disque est effacee
# puis re-posee depuis l'etat a jour de la carte. Une colonne hors disque est
# ignoree : la carte est autoritative, elle sera posee correctement au retour.
#
# EFFACEMENT PAR BALAYAGE DES COUCHES, pas par `effacer_colonne` : cette
# derniere lit `source.cellules_de(colonne)` qui rend les cellules PLEINES de
# la carte a jour -- une cellule creusee vient d'en SORTIR, elle ne serait
# jamais effacee du GridMap. On balaie donc TOUTES les couches representables
# et on invalide chaque case posee, avant de re-poser depuis la carte a jour.
func _absorber_modifications_carte() -> void:
	var modifs: Array = carte.drainer_modifications("terrain_visible")
	if modifs.is_empty():
		return
	var base: int = carte.couche_base
	for colonne in modifs:
		if not _pose.has(colonne):
			continue
		for rang in range(CarteTerrain.COUCHES_MAXIMALES):
			var cellule := Vector3i(colonne.x, base + rang, colonne.y)
			if get_cell_item(cellule) != GridMap.INVALID_CELL_ITEM:
				set_cell_item(cellule, GridMap.INVALID_CELL_ITEM)
		_effacer_bodies_sous_cubes(colonne)
		poser_colonne(self, carte, colonne, _bloc)
		_poser_bodies_sous_cubes(colonne)

# AJUSTE LES DEUX FILES A LA NOUVELLE CIBLE, ne les vide ni ne les recree.
# Voir l'en-tete.
func _retargeter(centre: Vector2i) -> void:
	var vise := colonnes_du_disque(centre, rayon_cellules)
	for colonne in vise.keys():
		if not carte.dans_emprise(colonne):
			vise.erase(colonne)

	# CE QUI EST VISE N'A PLUS DE RAISON D'ETRE EFFACE, et n'a rien a refaire
	# s'il est deja pose ou deja en file pour l'etre.
	for colonne in vise.keys():
		_a_effacer.erase(colonne)
		if not _pose.has(colonne) and not _a_poser.has(colonne):
			_a_poser[colonne] = true

	# CE QUI EST POSE ET N'EST PLUS VISE part a la file d'effacement.
	for colonne in _pose.keys():
		if not vise.has(colonne):
			_a_effacer[colonne] = true
	# CE QUI ATTENDAIT D'ETRE POSE ET N'EST PLUS VISE ne l'attend plus --
	# rien n'a jamais ete ecrit, rien a effacer non plus.
	for colonne in _a_poser.keys():
		if not vise.has(colonne):
			_a_poser.erase(colonne)

	_centre_pose = centre
	_amorce = true

# DRAINE JUSQU'A `colonnes_par_image` DES DEUX FILES, effacement d'abord :
# une colonne qui sort ne doit pas s'attarder plus longtemps qu'il ne faut le
# temps que la file de pose se vide.
func _avancer_file() -> void:
	var restant := maxi(colonnes_par_image, 1)
	for colonne in _a_effacer.keys():
		if restant <= 0:
			break
		effacer_colonne(self, carte, colonne)
		_effacer_bodies_sous_cubes(colonne)
		_a_effacer.erase(colonne)
		_pose.erase(colonne)
		restant -= 1
	for colonne in _a_poser.keys():
		if restant <= 0:
			break
		poser_colonne(self, carte, colonne, _bloc)
		_poser_bodies_sous_cubes(colonne)
		_a_poser.erase(colonne)
		_pose[colonne] = true
		restant -= 1

# La colonne sous l'observateur, ou celle sous l'origine quand il n'y en a pas.
func _centre_observateur() -> Vector2i:
	var observateur := get_tree().get_first_node_in_group(groupe_observateur) as Node3D
	if observateur == null:
		return Vector2i.ZERO
	var cellule := local_to_map(to_local(observateur.global_position))
	return Vector2i(cellule.x, cellule.z)

func _rafraichir_vers(centre: Vector2i) -> void:
	var bilan := rafraichir(self, carte, _pose, centre, rayon_cellules, _bloc)
	_pose = bilan.pose
	_centre_pose = centre
	_amorce = true
	# Ajoute les bodies externes pour les cellules entamees POSEES par
	# rafraichir(). Le static ne peut pas les creer lui-meme, l'appelant le fait.
	for colonne in _pose:
		_poser_bodies_sous_cubes(colonne)

# Les colonnes d'un disque de `rayon` cellules autour d'un centre, en ENSEMBLE
# (colonne -> true).
#
# UN DISQUE, PAS UN CARRE : un carre pose ses coins a rayon×√2, soit 41 % de
# cellules en plus pour une distance de vue qui n'augmente pas. La comparaison
# se fait sur le carre des distances -- aucune racine, et aucun flottant.
static func colonnes_du_disque(centre: Vector2i, rayon: int) -> Dictionary:
	var ensemble: Dictionary = {}
	var carre := rayon * rayon
	for dx in range(-rayon, rayon + 1):
		for dz in range(-rayon, rayon + 1):
			if dx * dx + dz * dz <= carre:
				ensemble[Vector2i(centre.x + dx, centre.y + dz)] = true
	return ensemble

# Ce qui est dans `vise` sans etre dans `pose`.
static func entrantes(pose: Dictionary, vise: Dictionary) -> Array[Vector2i]:
	var liste: Array[Vector2i] = []
	for colonne in vise:
		if not pose.has(colonne):
			liste.append(colonne)
	return liste

# Ce qui est dans `pose` sans etre dans `vise`.
static func sortantes(pose: Dictionary, vise: Dictionary) -> Array[Vector2i]:
	var liste: Array[Vector2i] = []
	for colonne in pose:
		if not vise.has(colonne):
			liste.append(colonne)
	return liste

# LE PREMIER PASSAGE POSE TOUJOURS, quel que soit le seuil : sans `amorce`, un
# observateur pile sur la colonne (0,0) ne declencherait jamais rien et le
# terrain resterait vide.
static func doit_rafraichir(centre_pose: Vector2i, centre: Vector2i, pas: int,
		amorce: bool) -> bool:
	if not amorce:
		return true
	var ecart := centre - centre_pose
	return absi(ecart.x) >= pas or absi(ecart.y) >= pas

# Les cellules pleines d'une suite de colonnes, telles que la carte les decrit.
# Une colonne hors emprise ou creusee jusqu'au vide n'en rend aucune.
static func cellules_des_colonnes(source: Resource, colonnes: Array[Vector2i]) -> Array[Vector3i]:
	var cellules: Array[Vector3i] = []
	for colonne in colonnes:
		cellules.append_array(source.cellules_de(colonne))
	return cellules

# LE GESTE D'UNE SEULE COLONNE, partage par `rafraichir()` (tout d'un coup) et
# `_avancer_file()` (une colonne a la fois, etalee sur plusieurs images).
#
# CHAQUE CELLULE AVEC CE QU'ELLE EST, jamais toutes avec le meme bloc. Poser
# l'item par defaut partout redessine les rampes en cubes et perd toute
# orientation : la carte a tout garde, et l'ecran ne montre rien. `bloc` ne
# sert que de repli quand la carte ne dit rien de particulier.
static func poser_colonne(grille: GridMap, source: Resource, colonne: Vector2i, bloc: int) -> int:
	var posees := 0
	for cellule in source.cellules_de(colonne):
		# Cellule entamee (sous_cubes != PLEIN) : sa collision est portee par
		# un StaticBody3D externe cree par _poser_bodies_sous_cubes -- ne rien
		# poser dans le GridMap ici, sinon collision cube pleine + mini-cubes
		# se cumulent.
		if source.sous_cubes(cellule) != CarteTerrain.MASQUE_SOUS_CUBE_PLEIN:
			continue
		var item: int = source.item_de(cellule)
		if item == CarteTerrain.ITEM_DEFAUT:
			item = bloc
		grille.set_cell_item(cellule, item, source.orientation_de(cellule))
		posees += 1
	return posees

# LA MEME BIBLIOTHEQUE, privee de ses maillages. Formes de collision, noms et
# navmesh sont conserves : le GridMap cree toujours sa collision par cellule et
# ne dessine plus aucun triangle. Les identifiants d'items restent les memes --
# ce que la carte designe continue de designer le meme bloc.
static func sans_mesh(source: MeshLibrary) -> MeshLibrary:
	var allegee := MeshLibrary.new()
	for identifiant in source.get_item_list():
		allegee.create_item(identifiant)
		allegee.set_item_name(identifiant, source.get_item_name(identifiant))
		allegee.set_item_shapes(identifiant, source.get_item_shapes(identifiant))
		var navmesh := source.get_item_navigation_mesh(identifiant)
		if navmesh != null:
			allegee.set_item_navigation_mesh(identifiant, navmesh)
	return allegee

static func effacer_colonne(grille: GridMap, source: Resource, colonne: Vector2i) -> int:
	var effacees := 0
	for cellule in source.cellules_de(colonne):
		if grille.get_cell_item(cellule) != GridMap.INVALID_CELL_ITEM:
			grille.set_cell_item(cellule, GridMap.INVALID_CELL_ITEM)
			effacees += 1
	return effacees

# Pose ce qui entre dans le disque, efface ce qui en sort, et rend le bilan :
# { pose, entrantes, sortantes, cellules_posees, cellules_effacees }.
#
# LES COLONNES HORS EMPRISE N'ENTRENT PAS DANS L'ENSEMBLE POSE. Les garder
# ferait porter a l'ensemble des colonnes qui ne portent aucune cellule, et le
# compte de ce qui est pose cesserait de dire ce qui est a l'ecran.
#
# TOUT D'UN COUP, JAMAIS ETALEE : c'est la version que les tests verrouillent,
# et celle qui pose le premier affichage. Voir l'en-tete pour la version
# etalee sur plusieurs images, utilisee en jeu par `_process`.
static func rafraichir(grille: GridMap, source: Resource, pose: Dictionary,
		centre: Vector2i, rayon: int, bloc: int) -> Dictionary:
	var vise := colonnes_du_disque(centre, rayon)
	for colonne in vise.keys():
		if not source.dans_emprise(colonne):
			vise.erase(colonne)

	var a_poser := entrantes(pose, vise)
	var a_effacer := sortantes(pose, vise)

	var posees := 0
	for colonne in a_poser:
		posees += poser_colonne(grille, source, colonne, bloc)

	var effacees := 0
	for colonne in a_effacer:
		effacees += effacer_colonne(grille, source, colonne)

	return {
		"pose": vise,
		"entrantes": a_poser.size(),
		"sortantes": a_effacer.size(),
		"cellules_posees": posees,
		"cellules_effacees": effacees,
	}

# COLLISION DES CELLULES ENTAMEES. Un StaticBody3D par cellule cassee, N
# BoxShape3D enfants (un par sous-cube plein). Cree apres `poser_colonne`
# (qui skip ces cellules dans le GridMap). Retire avant `effacer_colonne`
# ou avant un rebuild du drain.
func _poser_bodies_sous_cubes(colonne: Vector2i) -> void:
	if carte == null:
		return
	var cote: float = carte.cote
	var pas := cote / 3.0
	for cellule in carte.cellules_de(colonne):
		var masque: int = carte.sous_cubes(cellule)
		if masque == CarteTerrain.MASQUE_SOUS_CUBE_PLEIN:
			continue
		if masque == 0:
			continue
		# Idempotent : si un body existe deja pour cette cellule, on le
		# retire avant de recreer (etat a jour du masque).
		if _bodies_cellules_cassees.has(cellule):
			var ancien = _bodies_cellules_cassees[cellule]
			if ancien != null and is_instance_valid(ancien):
				ancien.queue_free()
			_retirer_body(cellule)
		var body := StaticBody3D.new()
		add_child(body)
		body.global_position = to_global(map_to_local(cellule))
		for i in range(27):
			if (masque & (1 << i)) == 0:
				continue
			var ix := i % 3
			var iy := (i / 3) % 3
			var iz := i / 9
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(pas, pas, pas)
			shape.shape = box
			shape.position = Vector3(
				float(ix - 1) * pas,
				float(iy - 1) * pas,
				float(iz - 1) * pas)
			body.add_child(shape)
		_inscrire_body(cellule, body)

func _effacer_bodies_sous_cubes(colonne: Vector2i) -> void:
	# Lit l'index secondaire : seules les cellules reellement cassees de cette
	# colonne sont touchees. Aucune iteration sur toute la population.
	if not _bodies_par_colonne.has(colonne):
		return
	# COPIE : _retirer_body edite _bodies_par_colonne[colonne], iterer dessus
	# directement sauterait des elements.
	var cellules: Array = (_bodies_par_colonne[colonne] as Array).duplicate()
	for cellule in cellules:
		var body = _bodies_cellules_cassees.get(cellule)
		if body != null and is_instance_valid(body):
			body.queue_free()
		_retirer_body(cellule)

# LES DEUX SEULS ECRIVAINS de _bodies_cellules_cassees : ils tiennent l'index
# secondaire _bodies_par_colonne en parallele. Toucher au dict primaire sans
# passer par eux desynchronise l'index et _effacer_bodies_sous_cubes rate des
# cellules.
func _inscrire_body(cellule: Vector3i, body: StaticBody3D) -> void:
	_bodies_cellules_cassees[cellule] = body
	var colonne := Vector2i(cellule.x, cellule.z)
	if not _bodies_par_colonne.has(colonne):
		_bodies_par_colonne[colonne] = []
	(_bodies_par_colonne[colonne] as Array).append(cellule)

func _retirer_body(cellule: Vector3i) -> void:
	_bodies_cellules_cassees.erase(cellule)
	var colonne := Vector2i(cellule.x, cellule.z)
	if not _bodies_par_colonne.has(colonne):
		return
	var liste: Array = _bodies_par_colonne[colonne]
	liste.erase(cellule)
	if liste.is_empty():
		_bodies_par_colonne.erase(colonne)
