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
# IL PART D'UNE GRILLE VIDE, quoi qu'elle contienne. La meme scene sert a
# SCULPTER dans l'editeur : le GridMap y porte alors une fenetre de terrain, que
# le jeu n'a aucune raison de garder -- elle est deja dans la carte, et ce qui
# tombe hors du disque du joueur resterait pose pour toujours. Vider au demarrage
# rend le compte de cellules independant de ce que la scene transporte.
#
# LE RAFRAICHISSEMENT A UN SEUIL. Sans lui, un observateur qui marche
# recalculerait deux disques entiers a chaque image pour un ou deux pas de
# grille de difference. Le seuil se paie en marge : le rayon reellement garanti
# est `rayon_cellules - pas_de_rafraichissement`.
#
# Regles tenues : positions en Vector3, jamais Vector2 -- une COLONNE est un
# Vector2i, un index et pas une position, meme convention que
# surface_terrain.gd. Aucun hasard. Aucun texte visible par le joueur. Aucun nom
# de contenu. Rien de scripts/, data/ ni documents/ n'est lu ni ecrit.

const Commun = preload("res://jeu/terrain/terrain_commun.gd")

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

# L'ensemble des colonnes actuellement posees : colonne -> true. Il n'est jamais
# deduit du GridMap -- get_used_cells couterait une lecture de tout ce qui est
# pose a chaque rafraichissement.
var _pose: Dictionary = {}
var _centre_pose: Vector2i = Vector2i.ZERO
var _amorce := false
var _bloc := GridMap.INVALID_CELL_ITEM

func _ready() -> void:
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
	# Voir l'en-tete : ce que la scene transporte n'est pas ce que le jeu dessine.
	var transportees := get_used_cells().size()
	if transportees > 0:
		clear()
		print("terrain_visible : %d cellules transportees par la scene, effacees avant de dessiner" % transportees)
	_rafraichir_vers(_centre_observateur())

func _process(_delta: float) -> void:
	if carte == null or _bloc == GridMap.INVALID_CELL_ITEM:
		return
	var centre := _centre_observateur()
	if not doit_rafraichir(_centre_pose, centre, pas_de_rafraichissement, _amorce):
		return
	_rafraichir_vers(centre)

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

# Pose ce qui entre dans le disque, efface ce qui en sort, et rend le bilan :
# { pose, entrantes, sortantes, cellules_posees, cellules_effacees }.
#
# LES COLONNES HORS EMPRISE N'ENTRENT PAS DANS L'ENSEMBLE POSE. Les garder
# ferait porter a l'ensemble des colonnes qui ne portent aucune cellule, et le
# compte de ce qui est pose cesserait de dire ce qui est a l'ecran.
static func rafraichir(grille: GridMap, source: Resource, pose: Dictionary,
		centre: Vector2i, rayon: int, bloc: int) -> Dictionary:
	var vise := colonnes_du_disque(centre, rayon)
	for colonne in vise.keys():
		if not source.dans_emprise(colonne):
			vise.erase(colonne)

	var a_poser := entrantes(pose, vise)
	var a_effacer := sortantes(pose, vise)

	var cellules_posees := cellules_des_colonnes(source, a_poser)
	var cellules_effacees := cellules_des_colonnes(source, a_effacer)
	var ecrites := Commun.ecrire_cellules(grille, cellules_posees, bloc, 0,
		maxi(cellules_posees.size(), 1))
	var videes := Commun.ecrire_cellules(grille, cellules_effacees,
		GridMap.INVALID_CELL_ITEM, 0, maxi(cellules_effacees.size(), 1))

	return {
		"pose": vise,
		"entrantes": a_poser.size(),
		"sortantes": a_effacer.size(),
		"cellules_posees": ecrites.changees,
		"cellules_effacees": videes.changees,
	}
