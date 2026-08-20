extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_repere_fenetre.gd
#
# Verrouille res://jeu/terrain/repere_fenetre.gd et le cablage D'EDITION de
# res://jeu/terrain/carte_100km2.tscn -- la scene ou l'on sculpte ET ou l'on
# joue. Ce qui releve du JEU (terrain pose autour du personnage, sol solide,
# echelle) est verrouille a part par test_scene_carte.gd, jamais redit ici :
# - le rectangle a EXACTEMENT la largeur de ce qui se charge ;
# - LE GIZMO COMMANDE LA FENETRE : deplacer le noeud a la souris ecrit un
#   nouveau centre sur l'outil. C'est le geste qu'on veut -- tirer les fleches
#   au lieu de taper deux entiers ;
# - ET LA FENETRE COMMANDE LE GIZMO : taper un centre replace le noeud. Les deux
#   sens, une seule verite ;
# - LE MAILLAGE EST UNE DALLE PLEINE, centree sur l'origine locale. Un contour
#   de lignes ne s'attrape pas a la souris -- l'editeur selectionne au clic sur
#   le maillage -- et trace aux coordonnees absolues il ne bougerait meme pas
#   avec le noeud. Les deux rendaient le gizmo inutilisable ;
# - ELLE EST TRANSLUCIDE : opaque, elle cacherait le relief qu'on regarde pour
#   choisir ou sculpter ;
# - A L'OUVERTURE, LE CENTRE GAGNE SUR LA POSITION : un repere laisse de
#   travers lors d'une session precedente ne doit pas imposer SON endroit a la
#   fenetre des le chargement de la scene ;
# - DEPLACER LE PARENT NE DEPLACE PAS LA FENETRE. Le curseur se mesure contre la
#   MAQUETTE, jamais contre le noeud qui les porte : promener ce parent emmene
#   les deux ensemble, la marque ne bouge pas SUR la carte, et le centre ne doit
#   pas bouger non plus. Lire la position locale donnait l'inverse -- la marque
#   se promenait a l'ecran et le chargement restait ou il etait ;
# - LE CURSEUR FLOTTE AU-DESSUS DE LA SURFACE DE LA MAQUETTE. Pose a zero, il
#   passe quatorze metres DESSOUS -- mesure sur la scene -- et disparait
#   derriere elle dans la seule vue qui serve a choisir un endroit ;
# - LA POSITION S'ACCROCHE A LA COLONNE : le gizmo rend du continu, la carte ne
#   connait que des entiers, et le rectangle doit montrer ce qui se chargera ;
# - le repere ne porte AUCUNE donnee : centre, demi-largeur et arete de cellule
#   se lisent chez l'outil et chez sa carte. Une arete recopiee sur le repere
#   dessinerait un rectangle a la mauvaise echelle sur une carte qui en declare
#   une autre, sans que rien ne le contredise ;
# - LE TERRAIN DE TRAVAIL N'A QU'UN SEUL GRIDMAP FRERE. terrain_commun.gd refuse
#   de choisir entre deux GridMap freres : la maquette posee a cote du terrain
#   arreterait net les trois outils de sculpture, avec une erreur qui ne parle
#   ni de maquette ni de vue d'ensemble ;
# - les trois outils de la scene retrouvent bien ce terrain-la ;
# - la maquette est sous Apercu, donc DECALEE du terrain de travail : posee au
#   meme endroit, elle noierait les six cents metres qu'on sculpte dans dix
#   kilometres de vue d'ensemble.
#
# Entree : la scene sur le disque, instanciee et poussee dans l'arbre. Sortie :
# une ligne « OK: » et le code 0 si tout tient, « ECHEC: » et le code 1 sinon.
#
# LES JUGEMENTS SONT DIFFERES, jamais joues dans _init : la racine du SceneTree
# n'y est pas encore prete, un noeud qu'on y ajoute n'entre pas dans l'arbre et
# son _ready ne part jamais.
#
# Regles tenues : positions en Vector3, jamais Vector2. Aucun hasard. Les prints
# sont des traces de mise au point, pas du texte joueur. Rien de scripts/, data/
# ni documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const Repere = preload("res://jeu/terrain/repere_fenetre.gd")
const Commun = preload("res://jeu/terrain/terrain_commun.gd")

const CHEMIN_SCENE := "res://jeu/terrain/carte_100km2.tscn"

const COTE := 2.0
const DEMI := 150
const CENTRE := Vector2i(1000, -700)
const TOLERANCE := 0.001

var _v

# UN APPEL QUI PLANTE SAUTE TOUT CE QUI SUIT SANS RIEN COMPTER : la section
# s'interrompt, aucun _v.v ne s'execute, et le test conclut OK sur zero echec.
# Chaque section signe donc son passage, et la conclusion exige les trois
# signatures. C'est la seule chose qui distingue « tout tient » de « rien ne
# s'est execute ».
const SECTIONS := 3
var _faites := 0

func _init() -> void:
	_v = Verif.new()
	_tout.call_deferred()

func _tout() -> void:
	var temoin: Node = Repere.new()
	# UN SCRIPT QUI NE COMPILE PAS ROUGIT, IL NE SE SAUTE PAS.
	if temoin == null:
		_v.v(false, "repere_fenetre.gd ne s'instancie pas : le script ne compile pas")
		_conclure()
		return
	temoin.free()
	_geometrie()
	_suivi()
	_scene()
	_conclure()

func _geometrie() -> void:
	# LA DALLE COUVRE EXACTEMENT CE QUI SE CHARGE : 2 x demi colonnes.
	var taille := Repere.taille_de(DEMI, COTE, 12.0)
	_v.v(absf(taille.x - float(2 * DEMI) * COTE) < TOLERANCE,
		"la dalle fait %.2f m de large, %.2f attendus" % [taille.x, float(2 * DEMI) * COTE])
	_v.v(absf(taille.z - float(2 * DEMI) * COTE) < TOLERANCE,
		"la dalle fait %.2f m de profond, %.2f attendus" % [taille.z, float(2 * DEMI) * COTE])
	_v.v(taille.y > 0.0, "la dalle n'a aucune epaisseur : rien a cliquer")

	# UN VOLUME, PAS UN TRAIT : c'est ce qui la rend cliquable dans la vue 3D.
	_v.v(taille.x > 1.0 and taille.z > 1.0,
		"la dalle est degeneree : %v" % taille)
	var matiere := Repere.materiau_de(Color(1, 0.45, 0.1, 0.45))
	_v.v(matiere.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
		"le repere est eclaire : sa teinte changerait avec le soleil")
	# TRANSLUCIDE, sinon elle cache le relief qu'on regarde.
	_v.v(matiere.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
		"la dalle est opaque : elle cacherait le terrain sous la fenetre")
	_v.v(matiere.cull_mode == BaseMaterial3D.CULL_DISABLED,
		"la dalle disparait vue d'un cote")
	_faites += 1

func _suivi() -> void:
	# LES DEUX SENS SONT EXACTEMENT INVERSES : c'est ce qui empeche le rectangle
	# de deriver d'une colonne a chaque aller-retour.
	for colonne in [Vector2i.ZERO, CENTRE, Vector2i(-2500, 2499), Vector2i(1, -1)]:
		var ou := Repere.position_de(colonne, COTE)
		_v.v(Repere.centre_de(ou, COTE) == colonne,
			"la colonne %v revient a %v apres un aller-retour" % [
				colonne, Repere.centre_de(ou, COTE)])

	# DEPLACER DE 500 COLONNES DEPLACE DE 500 x COTE METRES.
	var ici := Repere.position_de(Vector2i.ZERO, COTE)
	var la_bas := Repere.position_de(Vector2i(500, -300), COTE)
	_v.v(absf((la_bas.x - ici.x) - 500.0 * COTE) < TOLERANCE,
		"le rectangle s'est deplace de %.2f m pour 500 colonnes" % (la_bas.x - ici.x))
	_v.v(absf((la_bas.z - ici.z) + 300.0 * COTE) < TOLERANCE,
		"le rectangle n'a pas suivi le centre sur z")
	_v.v(absf(ici.y) < TOLERANCE and absf(la_bas.y) < TOLERANCE,
		"le repere se deplace en hauteur : il doit rester dans le plan de la maquette")

	# UNE POSITION CONTINUE S'ACCROCHE A LA COLONNE LA PLUS PROCHE.
	var entre_deux := Repere.position_de(Vector2i(10, 10), COTE) + Vector3(0.4, 0.0, -0.4)
	_v.v(Repere.centre_de(entre_deux, COTE) == Vector2i(10, 10),
		"une position a 40 cm de la colonne 10 s'accroche a %v" % [
			Repere.centre_de(entre_deux, COTE)])
	_faites += 1

func _scene() -> void:
	var paquet := load(CHEMIN_SCENE) as PackedScene
	if paquet == null:
		_v.v(false, "%s introuvable ou illisible" % CHEMIN_SCENE)
		return
	var racine := paquet.instantiate() as Node3D
	if racine == null:
		_v.v(false, "la racine de %s n'est pas un Node3D" % CHEMIN_SCENE)
		return
	get_root().add_child(racine)

	var terrain := racine.get_node_or_null("Terrain") as GridMap
	if terrain == null:
		_v.v(false, "aucun GridMap nomme Terrain sous la racine")
		racine.queue_free()
		return

	# LE JUGEMENT QUI GARDE LES OUTILS VIVANTS : un seul GridMap parmi les freres.
	var gridmaps := 0
	for enfant in racine.get_children():
		if enfant is GridMap:
			gridmaps += 1
	_v.v(gridmaps == 1,
		"%d GridMap freres du Terrain : terrain_commun.gd refusera de choisir et les trois outils s'arreteront" % gridmaps)

	# Les trois outils retrouvent ce terrain-la.
	for nom in ["Fenetre", "Sculpteur", "Remplisseur"]:
		var outil := racine.get_node_or_null(nom) as Node3D
		if outil == null:
			_v.v(false, "aucun outil nomme %s sous la racine" % nom)
			continue
		_v.v(Commun.terrain_frere(outil) == terrain,
			"l'outil %s ne retrouve pas le Terrain" % nom)

	var fenetre := racine.get_node_or_null("Fenetre")
	if fenetre != null:
		_v.v(fenetre.carte != null, "l'outil de fenetre ne porte aucune carte")
		# TOUT CE QU'UN OUTIL D'EDITEUR INTERROGE DOIT TOURNER DANS L'EDITEUR.
		# Sans @tool, la ressource y est un PLACEHOLDER : ses champs se lisent,
		# aucune de ses methodes ne repond, et charger comme enregistrer echoue
		# sur « Attempt to call a method on a placeholder instance ». Aucun test
		# headless ne peut le constater -- il n'y a pas d'editeur pour fabriquer
		# le placeholder ; ce jugement lit donc le mode du script.
		if fenetre.carte != null:
			var script_carte: Script = fenetre.carte.get_script()
			_v.v(script_carte != null and script_carte.is_tool(),
				"le script de la carte n'est pas @tool : la fenetre ne pourra ni charger ni enregistrer dans l'editeur")
		var script_outil: Script = fenetre.get_script()
		_v.v(script_outil != null and script_outil.is_tool(),
			"l'outil de fenetre n'est pas @tool : ses cases ne feront rien dans l'editeur")

	var repere := racine.get_node_or_null("Apercu/Repere") as MeshInstance3D
	if repere == null:
		_v.v(false, "aucun repere sous Apercu")
	else:
		# HORS EDITEUR, le repere ne montre rien au joueur et n'occupe aucune
		# image : un rectangle orange suspendu dirait au joueur ou le level
		# designer avait laisse sa fenetre.
		_v.v(repere.mesh == null, "le repere a trace un rectangle en jeu")
		_v.v(not repere.is_processing(),
			"le repere compare encore son centre a chaque image en jeu")
		if fenetre != null:
			# L'ARETE VIENT DE LA CARTE, jamais du repere.
			var arete: float = repere.cote_de(fenetre)
			_v.v(absf(arete - fenetre.carte.cote) < TOLERANCE,
				"le repere trace a l'arete %.3f, la carte declare %.3f" % [
					arete, fenetre.carte.cote])
			_v.v(not ("cote" in repere),
				"le repere porte encore sa propre arete : deux verites pour une meme grandeur")

			# LE GIZMO COMMANDE : on deplace le noeud comme le ferait la souris,
			# et l'outil doit recevoir le centre correspondant.
			var tiree := Repere.position_de(CENTRE, arete) + Vector3(0.3, 0.0, 0.3)
			repere.position = tiree
			repere._suivre()
			_v.v(fenetre.centre == CENTRE,
				"deplacer le repere a mis le centre a %v, %v attendu" % [
					fenetre.centre, CENTRE])
			# ON NE LUI REPREND PAS LE NOEUD. Le gizmo de l'editeur applique sa
			# transformation a chaque image : un script qui repose le noeud dans
			# le meme temps se bat contre lui, et l'objet ne bouge plus du tout.
			_v.v(_meme_plan(repere.position, tiree),
				"le repere a repris la main sur la position pendant le deplacement : %v au lieu de %v" % [
					repere.position, tiree])

			# Deux images de suite sans bouger ne doivent RIEN declencher.
			var stable := repere.position
			repere._suivre()
			repere._suivre()
			_v.v(_meme_plan(repere.position, stable),
				"le repere derive tout seul quand on ne le touche pas : %v" % repere.position)

			# ET LA FENETRE COMMANDE : on tape un centre, le noeud doit suivre.
			var ailleurs := Vector2i(-1200, 800)
			fenetre.centre = ailleurs
			repere._suivre()
			# ON NE COMPARE QUE LE PLAN : la hauteur est imposee par la maquette,
			# elle ne dit rien de la colonne visee.
			_v.v(_meme_plan(repere.position, Repere.position_de(ailleurs, arete)),
				"taper un centre n'a pas deplace le repere : %v" % repere.position)

			# DEPLACER LE PARENT NE CHANGE RIEN AU CENTRE. On promene l'Apercu,
			# qui porte a la fois la maquette et le curseur : leur position
			# relative ne bouge pas, donc la colonne visee non plus.
			var apercu := racine.get_node_or_null("Apercu") as Node3D
			if apercu != null:
				var avant_centre: Vector2i = fenetre.centre
				var avant_locale := repere.position
				apercu.position += Vector3(3000.0, 250.0, -1700.0)
				repere._suivre()
				_v.v(fenetre.centre == avant_centre,
					"deplacer le parent a change le centre : %v au lieu de %v" % [
						fenetre.centre, avant_centre])
				_v.v(_meme_plan(repere.position, avant_locale),
					"le curseur a bouge dans son parent alors que seul le parent a bouge")
				apercu.position -= Vector3(3000.0, 250.0, -1700.0)
				repere._suivre()

			# A L'OUVERTURE, LE CENTRE GAGNE. On laisse le repere n'importe ou,
			# comme une session precedente l'aurait laisse, et on recentre : le
			# centre de l'outil ne doit PAS avoir bouge.
			repere.position = Vector3(12345.0, 0.0, -6789.0)
			repere.recentrer()
			_v.v(fenetre.centre == ailleurs,
				"un repere laisse de travers a impose son endroit : centre passe a %v au lieu de %v" % [
					fenetre.centre, ailleurs])
			_v.v(_meme_plan(repere.position, Repere.position_de(ailleurs, arete)),
				"recentrer n'a pas ramene le repere sur la fenetre : %v" % repere.position)

			# La dalle a la bonne largeur, et elle est centree sur le noeud.
			repere.tracer(fenetre.demi_fenetre, arete)
			var dalle := repere.mesh as BoxMesh
			_v.v(dalle != null, "le repere ne porte pas une dalle : rien a cliquer")
			if dalle != null:
				var attendue := Repere.demi_largeur(fenetre.demi_fenetre, arete) * 2.0
				_v.v(absf(dalle.size.x - attendue) < 1.0,
					"la dalle fait %.1f m de large, %.1f attendus" % [
						dalle.size.x, attendue])
				var boite := dalle.get_aabb()
				_v.v(absf(boite.position.x + attendue * 0.5) < 1.0,
					"la dalle n'est pas centree sur le noeud : elle commence a %.1f" % [
						boite.position.x])

	var maquette := racine.get_node_or_null("Apercu/Maquette") as Node3D
	if maquette == null:
		_v.v(false, "aucune maquette sous Apercu")
	else:
		# EN JEU LA VUE D'ENSEMBLE N'EXISTE PAS ; c'est construire() qui la pose.
		_v.v(maquette.grille().get_used_cells().is_empty(),
			"la maquette a pose %d cellules en jeu" % maquette.grille().get_used_cells().size())
		maquette.construire()
		_v.v(maquette.grille().get_used_cells().size() > 0, "construire() n'a rien pose")

		# LE CURSEUR FLOTTE AU-DESSUS DE LA SURFACE, jamais dessous : pose a
		# zero il passe quatorze metres sous elle et disparait derriere.
		if repere != null:
			repere.recentrer()
			var dessus: float = maquette.hauteur_du_dessus()
			_v.v(repere.position.y > dessus,
				"le curseur est a %.2f m alors que la maquette monte a %.2f : il passe dessous" % [
					repere.position.y, dessus])
			_v.v(absf(repere.position.y - (dessus + repere.altitude)) < 0.01,
				"le curseur n'est pas a la marge demandee au-dessus de la maquette : %.2f" % [
					repere.position.y])
		# ELLE EST DECALEE DU TERRAIN DE TRAVAIL : au meme endroit, la fenetre
		# sculptee serait noyee dans la vue d'ensemble.
		var apercu := racine.get_node_or_null("Apercu") as Node3D
		_v.v(apercu != null and absf(apercu.position.y) > 1.0,
			"la vue d'ensemble est a la meme hauteur que le terrain de travail")
		print("scene : %d cellules de maquette a %.0f m, %d GridMap frere(s) du Terrain" % [
			maquette.grille().get_used_cells().size(),
			(apercu.position.y if apercu != null else 0.0), gridmaps])

	_faites += 1
	racine.queue_free()

# Deux positions designent-elles la meme colonne ? La hauteur est imposee par
# la maquette et ne dit rien de l'endroit vise.
static func _meme_plan(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) < 0.01 and absf(a.z - b.z) < 0.01

func _conclure() -> void:
	_v.v(_faites == SECTIONS,
		"%d sections sur %d sont allees jusqu'au bout : une s'est interrompue en cours de route" % [
			_faites, SECTIONS])
	if _v.echecs() > 0:
		print("ECHEC: le repere de fenetre ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: repere de fenetre -- rectangle a la largeur exacte de ce qui se charge, croix centree, suivi du centre, un seul GridMap frere, trois outils qui le retrouvent, et rien qui soit placeholder dans l'editeur")
	quit(0)
