extends GridMap

# LE DESSINATEUR de la carte de terrain, et rien d'autre. Il lit une
# carte_terrain.gd et pose, dans SES propres cellules, les colonnes qui tombent
# dans un rayon autour de l'observateur. Il ne decide rien du terrain : la carte
# est la seule autorite sur ce qui est plein.
#
# Entree : une carte (exportee), un rayon en cellules, un groupe ou trouver
# l'observateur. Sortie : ses cellules, posees et effacees au fil des
# deplacements.
#
# LE COMPTE DE CELLULES EST BORNE PAR LE RAYON, JAMAIS PAR LA CARTE. C'est la
# seule raison d'etre de ce fichier : un GridMap qui porterait la carte entiere
# coute 16,5 octets de scene et 86 octets de memoire par cellule, ce qui borne
# l'emprise bien avant que le jeu ne le demande. Ici le cout suit r², et rien
# d'autre -- doubler le rayon coute quatre fois, agrandir la carte coute zero.
#
# L'OBSERVATEUR SE TROUVE PAR GROUPE, jamais par un champ a remplir sur chaque
# type : c'est la camera du joueur qui decide de ce qui se dessine, et aucun
# objet du monde n'a besoin de savoir ou elle est. Sans observateur, le disque
# se pose autour de l'origine et n'en bouge plus -- un cas neutre, pas une
# panne.
#
# LE CALCUL EST HORS DE _process, tout entier en fonctions statiques : la boucle
# d'images DECLENCHE, elle ne calcule jamais. Ce qui se verrouille sans moteur
# de rendu ni clavier est exactement ce qui decide de ce qui est pose.
#
# RIEN N'EST SUPPOSE DE LA GEOMETRIE DE LA CELLULE : la colonne sous une
# position se demande a local_to_map, jamais recalculee ici. Le centrage des
# cellules est un reglage du noeud.
#
# LA TAILLE DE LA CELLULE SE LIT SUR LA CARTE, elle ne se regle pas ici. La
# carte porte deja `cote` ; la reecrire dans la scene ferait deux vérités, et
# celle de la scene gagnerait en silence -- un terrain dessine a la mauvaise
# echelle, sur une carte qui dit autre chose, et aucune erreur nulle part.
#
# IL REPREND LA BIBLIOTHEQUE DE JEU AVANT DE DESSINER. La meme scene sert a
# SCULPTER : l'outil de fenetre y pose alors une bibliotheque privee de ses
# formes de collision, parce qu'un GridMap cree un corps physique par cellule et
# que six cent mille corps coutent vingt-huit secondes. Enregistree ainsi, la
# scene rend un SOL TRAVERSABLE en jeu -- les cellules se voient, rien ne les
# arrete, et aucune erreur ne sort. Le terrain redemande donc au lancement celle
# que l'outil a mise de cote. Meme regle que la taille de cellule : ce que la
# scene transporte n'est pas ce qui fait autorite.
#
# IL PREND CE QUE LA SCENE PORTE AVANT DE L'EFFACER, et c'est ce qui rend le
# terrain sculpte FIABLE. La meme scene sert a sculpter : ce que le GridMap
# transporte est du TRAVAIL, pas un residu. L'effacer sans le lire perd tout ce
# qui n'a pas transite par l'editeur -- et ce transit depend d'un _process
# d'editeur, d'un script recharge, d'une fenetre chargee : quatre conditions
# dont aucune ne se signale quand elle manque.
#
# ON LE PREND, ON L'ECRIT DANS LA CARTE, PUIS on efface et on redessine. Le
# GridMap de la scene cesse d'etre une impasse : ce qui y est sculpte et
# enregistre avec la scene arrive dans le jeu, toujours, quel que soit ce qui a
# tourne ou non dans l'editeur.
#
# ENSUITE SEULEMENT LA GRILLE PART VIDE : le compte de cellules redevient
# independant de ce que la scene transporte, et ce qui tombe hors du disque du
# joueur ne reste pas pose pour toujours.
#
# LE RAFRAICHISSEMENT A UN SEUIL. Sans lui, un observateur qui marche
# recalculerait deux disques entiers a chaque image pour un ou deux pas de
# grille de difference. Le seuil se paie en marge : le rayon reellement garanti
# est `rayon_cellules - pas_de_rafraichissement`.
#
# CE QUE LE SEUIL DECLENCHE S'ETALE SUR PLUSIEURS IMAGES, EN JEU. MESURE
# (test_terrain_visible.gd, _cout_au_rayon_de_jeu) : au rayon et au pas
# reellement utilises, un seul seuil franchi coute 12,5 ms pour 796 colonnes
# entrantes et sortantes -- les trois quarts d'une image a soixante par
# seconde, POUR CHAQUE fois que l'observateur avance de huit metres. Pose et
# effacement partent donc dans deux files d'attente (`_a_poser`,
# `_a_effacer`), et `_process` n'en draine que `colonnes_par_image` a chaque
# image. `rafraichir()` reste inchangee, entiere et synchrone -- c'est elle
# que verrouillent les tests, et c'est elle que pose le PREMIER affichage : un
# monde vide qui se remplit sur plusieurs images serait pire que le cout unique
# du depart.
#
# UN SEUIL FRANCHI PENDANT QU'UNE FILE SE VIDE NE LA REDEMARRE PAS : il
# AJUSTE les deux files a la nouvelle cible. Une colonne qui redevient visee
# alors qu'elle attendait d'etre effacee sort de cette file sans qu'un seul
# bloc n'ait bouge ; une colonne qui n'est plus visee alors qu'elle attendait
# d'etre posee sort de l'autre file, tout aussi gratuitement. Repartir de zero
# a chaque seuil franchi referait le travail deja fait ET le perdrait au
# demi-tour suivant.
#
# Regles tenues : positions en Vector3, jamais Vector2 -- une COLONNE est un
# Vector2i, un index et pas une position, meme convention que
# surface_terrain.gd. Aucun hasard. Aucun texte visible par le joueur. Aucun nom
# de contenu. Rien de scripts/, data/ ni documents/ n'est lu ni ecrit.

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

func _ready() -> void:
	# RENDU GridMap RESTAURE. La ligne `visible = false` a ete retiree :
	# le TerrainLointain ne couvre pas la zone 0..rayon_interne autour
	# du joueur, donc sans le GridMap visible le sol proche est absent.
	# Le GridMap rend ses 6 faces par cube (pas de HFC natif) sur le
	# rayon 15 -- cout accepte pour avoir le sol beige sous les pieds.
	# COLLISION GridMap NATIVE PRESERVEE. L'appel sans_collision a ete
	# retire : create_trimesh_collision cree bien des StaticBody3D dans
	# TerrainLointain (verifie : 113/113 MI ont un enfant StaticBody3D)
	# mais le joueur tombe quand meme (mesure : Y=14.18 -> -22.8 en 2s).
	# La collision native GridMap est donc le seul sol physique fiable
	# aujourd'hui. Doublage assume (GridMap + trimesh multimesh) le temps
	# de diagnostiquer pourquoi trimesh ne retient pas le joueur.
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
	_rafraichir_vers(_centre_observateur())

func _process(_delta: float) -> void:
	if carte == null or _bloc == GridMap.INVALID_CELL_ITEM:
		return
	var centre := _centre_observateur()
	if doit_rafraichir(_centre_pose, centre, pas_de_rafraichissement, _amorce):
		_retargeter(centre)
	if not _a_poser.is_empty() or not _a_effacer.is_empty():
		_avancer_file()

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
		_a_effacer.erase(colonne)
		_pose.erase(colonne)
		restant -= 1
	for colonne in _a_poser.keys():
		if restant <= 0:
			break
		poser_colonne(self, carte, colonne, _bloc)
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
		var item: int = source.item_de(cellule)
		if item == CarteTerrain.ITEM_DEFAUT:
			item = bloc
		grille.set_cell_item(cellule, item, source.orientation_de(cellule))
		posees += 1
	return posees

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
