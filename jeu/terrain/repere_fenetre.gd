@tool
extends MeshInstance3D

# LE CURSEUR DE SCULPTURE : ou tombe la fenetre sur la maquette. Un contour et
# une croix, dessines par-dessus la vue d'ensemble. Il repond a « je suis ou »,
# et surtout il SE DEPLACE A LA SOURIS : c'est lui qu'on tire aux fleches du
# gizmo pour choisir l'endroit a sculpter.
#
# Entree : l'outil de fenetre, designe par un chemin de scene -- tout le reste
# se lit chez lui et chez sa carte. Sortie : son propre maillage de lignes, sa
# position, et le CENTRE qu'il ecrit sur l'outil.
#
# SA POSITION EST LE CENTRE DE LA FENETRE, et c'est tout le mecanisme. Le
# maillage est trace autour de son ORIGINE LOCALE, jamais aux coordonnees de la
# carte : un rectangle dessine a sa place absolue ne bougerait pas quand on
# deplace le noeud, et le gizmo n'aurait aucun effet. Deplacer le noeud deplace
# donc la fenetre, et taper un centre deplace le noeud -- les deux sens, une
# seule verite.
#
# IL FLOTTE AU-DESSUS DE LA SURFACE DE LA MAQUETTE, jamais a une hauteur en
# dur. La maquette dessine ses cellules a la couche du relief : sa face
# superieure est a quatorze metres pour une carte plate, et un curseur pose a
# zero passe DESSOUS -- vu de dessus, la seule vue utile pour choisir un
# endroit, la maquette le cache. La hauteur se demande donc a la maquette, et
# une marge l'en decolle.
#
# ELLE SE MESURE PAR RAPPORT A LA MAQUETTE, JAMAIS AU PARENT. C'est la maquette
# qui dessine la carte : la colonne visee est celle sur laquelle le curseur
# tombe A L'ECRAN, sur ce fond-la. Lire la position locale rendrait le curseur
# dependant du noeud qui les porte tous les deux -- deplacer ce parent
# promenerait la marque sur la carte sans que le centre bouge d'une colonne, et
# le chargement se ferait ailleurs que la ou elle pointe. Mesuree contre la
# maquette, deplacer le parent emmene les deux ensemble et ne change rien, ce
# qui est exact : la marque n'a pas bouge SUR la carte.
#
# IL DECLENCHE LE DEPLACEMENT QUAND LA MAIN S'ARRETE, jamais pendant. Chaque
# image d'un glissement changerait de colonne : enregistrer et recharger a
# chaque fois ecrirait la carte des dizaines de fois par seconde pour un geste
# unique. On attend donc que la position ne bouge plus pendant quelques images,
# et c'est seulement la qu'on passe la main a l'outil.
#
# A L'OUVERTURE DE LA SCENE, C'EST LE CENTRE QUI GAGNE, jamais la position
# enregistree. Sans quoi un repere laisse de travers -- pousse par megarde, ou
# range ailleurs lors d'une session precedente -- imposerait SON endroit a la
# fenetre des le chargement, et le centre regle dans l'inspecteur serait ecrase
# sans que personne n'ait rien demande. La souris ne commande qu'ensuite, sur un
# geste reel.
#
# ON NE REECRIT JAMAIS LA POSITION PENDANT QU'ON LA TIRE. Le gizmo de l'editeur
# applique sa propre transformation a chaque image ; un script qui repose le
# noeud dans le meme temps se bat contre lui, et le resultat est un objet qui ne
# bouge plus du tout. La position tiree est donc gardee TELLE QUELLE, et seule
# la COLONNE qui en decoule est ecrite sur l'outil. Le rectangle peut alors
# tomber jusqu'a une demi-cellule a cote de ce qui se chargera -- un metre sur
# une carte de dix kilometres, invisible ; se battre avec le gizmo, lui, se voit
# tout de suite.
#
# LE REPOSITIONNEMENT N'A LIEU QUE DANS L'AUTRE SENS : un centre tape dans
# l'inspecteur, ou un recentrage a l'ouverture. La , personne ne tient le noeud.
#
# IL NE PORTE AUCUNE AUTRE DONNEE : demi-largeur et arete de cellule se lisent
# chez l'outil et chez sa carte. Deux endroits qui doivent s'accorder finissent
# toujours par diverger -- un repere qui porterait sa propre arete dessinerait
# un rectangle a la mauvaise echelle sur une carte qui en declare une autre,
# sans que rien ne le contredise a l'ecran.
#
# UNE DALLE PLEINE, PAS UN CONTOUR DE LIGNES. Un rectangle trace en lignes d'un
# pixel ne s'attrape pas a la souris : l'editeur selectionne au clic sur le
# maillage, et viser une ligne sur une maquette de dix kilometres est
# impraticable. Il se lit mal, aussi. La dalle se voit de loin et se clique
# n'importe ou -- c'est ce qui rend le gizmo utilisable.
#
# ELLE EST TRANSLUCIDE : on doit voir le relief SOUS la fenetre pour choisir ou
# sculpter. Opaque, elle cacherait exactement ce qu'on regarde.
#
# PAS DE CELLULES DE MAQUETTE POUR LA MARQUER : poser des cellules d'une teinte
# a part salirait ce que la maquette montre et demanderait de les retirer avant
# chaque deplacement.
#
# IL N'EXISTE QUE DANS L'EDITEUR, comme la maquette qu'il annote : en jeu, un
# rectangle orange suspendu montrerait au joueur ou le level designer avait
# laisse sa fenetre. Son maillage est lache au lancement, et son _process
# arrete.
#
# LE _process EST LE SEUL DU TERRAIN D'EDITION, et il ne CALCULE rien : il
# compare la position et le centre a ceux du dernier trace, et n'agit qu'au
# changement. C'est le prix d'un curseur qu'on tire a la souris -- rien dans
# Godot ne previent qu'un gizmo a bouge.
#
# Regles tenues : positions en Vector3, jamais Vector2 -- une COLONNE est un
# Vector2i, un index et pas une position. Aucun hasard. Aucun texte visible par
# le joueur. Rien de scripts/, data/ ni documents/ n'est lu ni ecrit.

# ECRIT CHAQUE ETAPE DE LA CHAINE dans la console. Il n'y a aucun autre moyen de
# voir ou elle casse : Engine.is_editor_hint() est faux hors editeur, donc aucun
# banc lance en ligne de commande ne parcourt ce chemin. A couper une fois la
# panne trouvee.
@export var journal := true

# UN MARQUEUR DE VERSION, et ce n'est pas de la decoration : l'editeur garde en
# memoire des versions intermediaires d'un script @tool, et on peut passer une
# heure a corriger du code qui ne s'execute pas. Si cette ligne n'apparait pas
# au chargement de la scene, le script lu n'est pas celui du disque.
const VERSION := "repere 6 -- dalle, altitude, streaming"

# L'outil de fenetre dont ce repere montre et commande l'emprise.
@export var outil_fenetre: NodePath

# La maquette sur laquelle ce curseur pointe. C'est le repere de mesure, pas une
# decoration : voir l'en-tete. Laisse vide, le curseur retombe sur sa position
# locale et redevient sensible au deplacement de son parent.
@export var maquette: NodePath

# Translucide : la fenetre doit laisser voir le relief qu'elle couvre.
@export var couleur := Color(1.0, 0.45, 0.1, 0.45)

# Epaisseur de la dalle, en metres. Assez haute pour se voir de loin sur une
# carte de dix kilometres, assez basse pour ne pas devenir un mur.
@export var epaisseur: float = 12.0

# De combien le curseur flotte au-dessus de la surface de la maquette. Voir
# l'en-tete : a zero il passe dessous et disparait sous elle.
@export var altitude: float = 25.0

# Combien d'images sans bouger avant de considerer le geste termine. Voir
# l'en-tete : c'est ce qui evite d'enregistrer et de recharger la carte a chaque
# image d'un glissement.
@export var images_avant_suivi: int = 20

var _position_appliquee := Vector3.INF
var _centre_applique := Vector2i.ZERO
var _demi_applique := -1

# Depuis combien d'images la main s'est arretee, et le centre qui attend d'etre
# rendu. -1 : rien en attente.
var _immobile := 0
var _en_attente := false
var _deplacement_en_cours := false

func _ready() -> void:
	# Outil d'editeur : rien a montrer au joueur, aucune image a occuper.
	if not Engine.is_editor_hint():
		mesh = null
		set_process(false)
		return
	if journal:
		print("[%s] pret. altitude=%.1f, images_avant_suivi=%d" % [
			VERSION, altitude, images_avant_suivi])
	recentrer()

# Replace le repere sur le centre de la fenetre, quelle que soit la position ou
# on l'a laisse. Voir l'en-tete : a l'ouverture, l'inspecteur fait foi.
func recentrer() -> void:
	var outil := _outil()
	if outil == null:
		return
	var arete := cote_de(outil)
	if arete <= 0.0:
		return
	_poser(outil.centre, outil.demi_fenetre, arete)

func _process(_delta: float) -> void:
	_suivre()

# Les deux sens du meme lien, dans l'ordre qui donne la main a la SOURIS : si le
# noeud a bouge, c'est le geste le plus recent et il commande ; sinon on obeit
# au centre tape dans l'inspecteur.
func _suivre() -> void:
	var outil := _outil()
	if outil == null:
		return
	var arete := cote_de(outil)
	if arete <= 0.0:
		return

	var ou := position_sur_maquette()
	var bouge := not _meme_plan(ou, _position_appliquee)
	if journal and bouge:
		print("[repere] BOUGE : sur maquette %v, applique %v -> centre vise %v" % [
			ou, _position_appliquee, centre_de(ou, arete)])
	# SEUL LE PLAN COMPTE. La hauteur est imposee par la maquette, pas par la
	# main : la comparer ferait passer une reconstruction de la vue d'ensemble
	# pour un geste de l'utilisateur.
	if bouge:
		# LA SOURIS A PARLE, et on la laisse tenir le noeud. Voir l'en-tete :
		# repositionner ici reviendrait a se battre avec le gizmo.
		var vise := centre_de(ou, arete)
		if outil.centre != vise:
			outil.centre = vise
		if outil.demi_fenetre != _demi_applique:
			tracer(outil.demi_fenetre, arete)
		_position_appliquee = ou
		_centre_applique = vise
		_demi_applique = outil.demi_fenetre
		# LA MAIN BOUGE ENCORE : on repart de zero, rien ne se declenche.
		_immobile = 0
		_en_attente = true
		return

	if outil.centre != _centre_applique or outil.demi_fenetre != _demi_applique:
		_poser(outil.centre, outil.demi_fenetre, arete)
		_immobile = 0
		_en_attente = true
		return

	# LA MAIN S'EST ARRETEE. On laisse passer quelques images, puis on rend la
	# zone quittee a la carte et on charge celle qu'on vise.
	if not _en_attente or _deplacement_en_cours:
		return
	_immobile += 1
	if journal and _immobile % 5 == 0:
		print("[repere] immobile %d/%d, en_attente=%s" % [
			_immobile, maxi(images_avant_suivi, 1), _en_attente])
	if _immobile < maxi(images_avant_suivi, 1):
		return
	_en_attente = false
	_immobile = 0
	_declencher(outil)

func _declencher(outil: Node) -> void:
	if journal:
		print("[repere] DECLENCHE vers %v" % [_centre_applique])
	_deplacement_en_cours = true
	var fait: bool = await outil.deplacer_vers(_centre_applique)
	_deplacement_en_cours = false
	if journal:
		print("[repere] deplacer_vers a rendu %s" % fait)
	if not fait:
		return
	# La carte a change : la vue d'ensemble doit montrer le relief qu'on vient
	# d'y ecrire.
	var fond := _maquette()
	if fond != null and fond.has_method("construire"):
		var Outil := load("res://jeu/terrain/outil_fenetre.gd")
		if journal:
			print("  [maquette] avant construire : %s" % [
				Outil.emprise_lisible(fond.grille())])
		fond.construire()
		if journal:
			print("  [maquette] apres construire : %s" % [
				Outil.emprise_lisible(fond.grille())])
			print("  [maquette] son GridMap est a %v, cellules de %v" % [
				fond.grille().global_position, fond.grille().cell_size])

# La hauteur ou se poser : le dessus de la maquette, plus la marge. Sans
# maquette, l'altitude seule -- le curseur reste alors dans le plan de son
# parent.
func hauteur_visee() -> float:
	var fond := _maquette()
	if fond == null or not fond.has_method("hauteur_du_dessus"):
		return altitude
	return fond.hauteur_du_dessus() + altitude

static func _meme_plan(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) < 0.001 and absf(a.z - b.z) < 0.001

func _poser(centre: Vector2i, demi: int, arete: float) -> void:
	var voulue := position_de(centre, arete, hauteur_visee())
	var fond := _maquette()
	if fond != null and is_inside_tree() and fond.is_inside_tree():
		# On pose dans le repere de la MAQUETTE, puis on redescend vers le
		# parent : c'est la carte qu'on vise, pas un endroit du monde.
		global_position = fond.to_global(voulue)
	else:
		position = voulue
	tracer(demi, arete)
	_position_appliquee = position_sur_maquette()
	_centre_applique = centre
	_demi_applique = demi

# La position du curseur DANS LE REPERE DE LA MAQUETTE. Sans maquette designee,
# ou hors de l'arbre, on retombe sur la position locale -- ce qui reste juste
# tant que personne ne deplace le parent.
func position_sur_maquette() -> Vector3:
	var fond := _maquette()
	if fond == null or not is_inside_tree() or not fond.is_inside_tree():
		return position
	return fond.to_local(global_position)

func _maquette() -> Node3D:
	if maquette.is_empty():
		return null
	return get_node_or_null(maquette) as Node3D

func _outil() -> Node:
	if outil_fenetre.is_empty():
		return null
	return get_node_or_null(outil_fenetre)

# L'arete de cellule, lue sur la carte de l'outil. Rend zero quand il n'y a
# aucune carte : rien ne se trace, la ou une valeur de repli plausible
# dessinerait un rectangle faux qu'on croirait juste.
func cote_de(outil: Node) -> float:
	if outil == null or outil.carte == null:
		return 0.0
	return outil.carte.cote

# LE MILIEU GEOMETRIQUE DE LA FENETRE, en metres. Elle couvre les colonnes
# [centre - demi, centre + demi - 1] : son milieu tombe donc une DEMI-CELLULE
# avant la colonne du centre, jamais dessus. L'oublier decale le rectangle par
# rapport a ce qui se charge.
static func position_de(centre: Vector2i, arete: float, hauteur: float = 0.0) -> Vector3:
	return Vector3(
		(float(centre.x) - 0.5) * arete, hauteur, (float(centre.y) - 0.5) * arete)

# L'inverse exact : la colonne dont le milieu est le plus proche d'une position.
static func centre_de(ou: Vector3, arete: float) -> Vector2i:
	return Vector2i(
		int(round(ou.x / arete + 0.5)),
		int(round(ou.z / arete + 0.5)))

# La demi-largeur de la fenetre en metres, depuis son milieu.
static func demi_largeur(demi: int, arete: float) -> float:
	return float(demi) * arete

# La taille de la dalle : exactement l'emprise de la fenetre, sur l'epaisseur
# demandee. Ce qu'on voit est ce qui se chargera.
static func taille_de(demi: int, arete: float, hauteur: float) -> Vector3:
	var cote := demi_largeur(demi, arete) * 2.0
	return Vector3(cote, maxf(hauteur, 0.01), cote)

static func materiau_de(teinte: Color) -> StandardMaterial3D:
	var matiere := StandardMaterial3D.new()
	matiere.albedo_color = teinte
	matiere.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# TRANSLUCIDE : voir le relief sous la fenetre est tout l'interet.
	matiere.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Vue de dessous comme de dessus : la dalle n'a pas d'endroit.
	matiere.cull_mode = BaseMaterial3D.CULL_DISABLED
	return matiere

func tracer(demi: int, arete: float) -> void:
	var dalle := BoxMesh.new()
	dalle.size = taille_de(demi, arete, epaisseur)
	dalle.material = materiau_de(couleur)
	mesh = dalle
