extends Node3D

# LE PORTEUR DU COUVERT VEGETAL : il fait tenir ensemble le terrain, la
# simulation et l'ecran, et c'est tout ce qu'il fait.
#
# CE FICHIER NE DECIDE DE RIEN. La vie des plantes vit dans
# jeu/plantes/vegetation.gd (pur, sans noeud, testable headless) ; la lecture du
# terrain vit dans jeu/plantes/surface_terrain.gd. Ici : relever une fois,
# charger les especes que les semis reclament, prechauffer, appeler le tick,
# echanger le modele quand un stade change, poser et retirer les produits. Le
# rendu RELIT le rapport, il ne le recalcule jamais.
#
# PAS DE @tool, ET C'EST VOULU : ce noeud ne tourne QUE dans le jeu lance. Sous
# @tool, les plantes grandiraient et mourraient pendant que le game designer
# sculpte, et sa mise en place ne survivrait pas a une sauvegarde.
#
# CE NOEUD SE POSE EN ENFANT DIRECT DU GRIDMAP DU TERRAIN, et il le verifie. Tout
# le releve vit dans le repere LOCAL de la grille (voir surface_terrain.gd, ou
# to_global est ecarte parce qu'il rend une matrice vide hors de l'arbre).
#
# LA HAUTEUR DU SOL VIENT DE LA CARTE QUE LE TERRAIN PORTE, et de ses cellules
# seulement a defaut. Un terrain qui ne rend qu'un disque autour du joueur ne
# porte aucune cellule quand ce noeud s'eveille, et n'en portera jamais ailleurs
# que sous le joueur : le releve pris sur ses cellules serait vide, et le couvert
# mort-ne. Quel GridMap porte une carte, quel autre n'en porte pas : voir
# jeu/terrain/terrain_visible.gd et jeu/terrain/carte_terrain.gd.
#
# ---- UNE PLANTE N'EST PAS UN NOEUD DE DESSIN ----
# Les plantes d'une meme espece au meme stade sont le MEME modele a des positions
# differentes : rien ne les distingue. Elles sont donc des LIGNES dans un lot --
# un MultiMesh par maillage, une transform par plante -- et la carte graphique
# dessine le lot d'un seul ordre. Un noeud par plante ferait un ordre par plante,
# plus l'objet de scene qui va avec.
#
# Changer de stade, c'est sortir d'un lot et entrer dans un autre. Voir « LES
# LOTS DE RENDU » plus bas pour ce que le regroupement fait perdre.
#
# ---- ET UN TRONC, QUAND L'ESPECE EN DECLARE UN ----
# Une espece qui pose un `rayon_collision` recoit, sous le meme porteur, un
# StaticBody3D nomme d'apres son role : un cylindre de ce rayon, haut comme la
# stature du stade, qu'aucune unite ne traverse. Il est ECHANGE AVEC LE MODELE a
# chaque changement de stade -- une pousse ne barre pas le passage comme un arbre
# mature. A rayon nul, aucun corps n'est pose : c'est le cas de l'herbe, et le
# defaut.
#
# LA FORME EST PARTAGEE PAR TOUTES LES PLANTES D'UNE ESPECE ET D'UN STADE : une
# Shape3D est une ressource, la decrire une fois suffit pour mille arbres.
#
# ---- DEUX FACONS D'AVOIR UN CORPS ----
# Une espece qui declare des chemins de modeles recoit ses .glb. Une espece qui
# n'en declare AUCUN recoit une TOUFFE fabriquee ici a l'execution, haute comme
# la stature du stade et de la couleur de l'espece. Grossiere de pres, lisible de
# loin -- assez pour voir tourner un ecosysteme sans attendre qu'un maillage
# existe. Poser des chemins dans le JSON de l'espece la remplace, sans une ligne
# de code.
#
# LES MODELES SONT RECENTRES A L'INSTANCIATION. Un .glb exporte depuis une scene
# ou les modeles sont ranges cote a cote garde le decalage de sa place dans la
# rangee : trois modeles ainsi ranges sont a trois endroits, et une plante qui
# change de stade SAUTE d'autant -- elle parait disparaitre alors qu'elle est
# ailleurs. Defaut trouve EN REGARDANT L'ECRAN, invisible a tout test qui ne
# mesure pas la geometrie. Le recentrage est MESURE sur le modele reel : un
# modele deja centre rend un decalage nul et rien ne s'applique.
#
# LES SEMIS SONT SES PROPRES ENFANTS : chaque jeu/plantes/plante.tscn pose a la
# main sous ce noeud devient une plante de simulation, de l'espece qu'il declare,
# a la colonne ou le game designer l'a laisse. Son noeud est REUTILISE comme
# porteur, et ses enfants d'editeur sont liberes -- ils n'existent que pour se
# voir et se deplacer dans l'editeur.
#
# UN SEMIS HORS COUCHE EST POSE QUAND MEME, et seulement signale en console : le
# mecanisme ne supprime jamais ce que le game designer a place. Un semis d'espece
# INCONNUE, lui, ne peut pas etre pose -- il n'y a aucune table de stades a lui
# donner.
#
# Regles tenues : positions en Vector3. Aucun hasard hors du RNG seede que porte
# l'etat. Les prints sont des traces de mise au point, pas du texte joueur. Rien
# de scripts/, data/ ni addons/ n'est ecrit.

const Vegetation = preload("res://jeu/plantes/vegetation.gd")
const Surface = preload("res://jeu/plantes/surface_terrain.gd")
const PlanteScript = preload("res://jeu/plantes/plante.gd")
const EspeceScript = preload("res://jeu/plantes/espece.gd")

const NOM_TRONC := "Tronc"

# ---- LES REGLAGES DE L'INSPECTEUR ----
#
# CE QUI EST ICI EST CE QUI EST PARTAGE PAR TOUTES LES ESPECES. Ce qui varie de
# l'une a l'autre -- stades, statures, plafond de couche, trouee, reproduction,
# production, modeles -- vit dans le JSON de l'espece, parce qu'il y a autant de
# jeux de valeurs que d'especes et que le code ne connait pas leur nombre. Un
# `@export` par espece mettrait un nom de contenu dans un .gd, ce que l'ADN
# interdit (CLAUDE.md). Pour regler une espece sans ouvrir son fichier, voir
# `surcharges_especes` plus bas.
#
# CES VALEURS SURCHARGENT jeu/plantes/vegetation.json : _ready() fusionne les deux
# et ne passe QU'UN Dictionary a la simulation, qui ne sait rien de ce noeud. Le
# fichier reste la seule source pour tout ce qui tourne sans noeud, tests compris,
# et test_plante.gd rougit des que les deux s'ecartent.

@export_group("Peuplement")

# L'ECHELLE A LAQUELLE LE COUVERT REGARDE SON VOISINAGE. Le SEUIL, lui, vit sur
# chaque espece (`max_voisins` sur le noeud Arbre, Herbe...) : une herbe qui fait
# tapis supporte des dizaines de voisines la ou un arbre en refuse six. Le rayon
# reste commun parce qu'il choisit le rayon de rafraichissement de tout le couvert
# (vegetation.gd:rafraichir_autour), qui ne peut pas varier d'une plante a l'autre.
@export var rayon_voisinage_cellules: int = 5

# LA DOMINANCE : dans ce rayon, une voisine de stature strictement superieure fige
# la croissance. Elle ne tue pas -- elle fait attendre.
@export var rayon_ombre_cellules: int = 3

# L'ETABLISSEMENT : dans ce rayon autour du point d'arrivee, un rejet compte les
# vivantes et renonce si elles depassent le seuil de SON espece.
@export var rayon_trouee_cellules: int = 2

@export_group("Prechauffage")

# COMBIEN DE TICKS LA SIMULATION JOUE AVANT LA PREMIERE IMAGE. A zero, le couvert
# demarre tel que le game designer l'a pose. Plus haut, le joueur arrive sur une
# vegetation deja vecue au lieu d'un terrain nu.
#
# LE TEMPS SIMULE EST ticks x delta. Une plante posee a la main qui vit moins que
# ce total sera morte avant la premiere image -- ce n'est pas un defaut, c'est ce
# qu'on a demande.
@export var ticks_prechauffage: int = 0

# Les secondes simulees par tick de prechauffage. AUCUNE VALEUR NE PEUT DEFORMER
# LA SIMULATION : un pas trop grand devant les durees en jeu est decoupe en
# tranches fideles (vegetation.gd:pas_maximal). Le monter fait donc chauffer plus
# longtemps, jamais plus grossierement -- au prix du temps de demarrage.
@export var delta_prechauffage: float = 1.0

@export_group("Rythme")

# LE PAS DE LA SIMULATION, en secondes simulees. Le tick ne suit PLUS la frequence
# d'images : il est joue a intervalle fixe, quel que soit le nombre d'images par
# seconde. Une plante met des dizaines de secondes a changer de stade -- l'evaluer
# soixante fois par seconde etait du gaspillage pur, et c'est ce qui faisait ramer
# le couvert bien avant que le nombre de plantes ne pose probleme.
#
# LA VALEUR VIENT D'UNE MESURE, pas d'une regle inventee. Une plante a l'ombre y
# reste longtemps (76 s en mediane), mais ses ECLAIRCIES sont breves : 9 secondes
# en mediane, 46 au maximum. C'est la duree des eclaircies qui contraint le pas --
# un pas de 10 s raterait la moitie d'entre elles, et comme l'ombre dure huit fois
# plus longtemps que la lumiere, l'echantillonnage tomberait presque toujours
# pendant l'ombre : les plantes en concurrence SOUS-POUSSERAIENT systematiquement.
# A 2 secondes, aucune eclaircie n'est ratee.
@export var pas_simulation: float = 2.0

# Combien de ticks au plus dans une seule image. LE RETARD EST ABANDONNE, jamais
# rattrape : si la simulation ne suit pas, rattraper ferait un tick de plus a
# chaque image, qui prendrait encore plus de retard -- le jeu se fige au lieu de
# ralentir. Perdre du temps simule est le moindre mal, et c'est dit plutot que
# masque.
@export var ticks_max_par_image: int = 4

@export_group("Observation")

# Multiplie le pas de temps de la simulation, jamais celui du moteur. Il est
# DECOUPE comme le prechauffage : accelerer montre la meme simulation plus vite,
# jamais une simulation plus grossiere -- au prix du temps de calcul, qui monte
# avec le facteur.
@export var facteur_temps: float = 1.0

var _config: Dictionary = {}
var _types: Dictionary = {}
var _releve: Dictionary = {}
var _etat: Dictionary = {}
var _rendus: Dictionary = {}
var _noeuds: Dictionary = {}
# LES LOTS DE RENDU : une cle « espece#stade » -> un paquet de MultiMesh, un par
# maillage du modele. C'est ce qui remplace un noeud de dessin par plante.
var _lots: Dictionary = {}
# id d'une plante -> la cle du lot ou elle est inscrite. Sans lui, la retirer
# demanderait de fouiller tous les lots.
var _lot_de: Dictionary = {}
# id -> sa position. Le rendu la relit a chaque changement de stade, et une
# plante sans tronc n'a plus de noeud pour la porter.
var _poses: Dictionary = {}
# Le plus grand pas fidele, deduit des especes chargees -- voir
# vegetation.gd:pas_maximal. Ni le rendu ni le prechauffage n'appellent avancer()
# directement : les deux passent par les tranches, et aucun ne peut donc choisir
# un pas qui deformerait la simulation.
var _pas_max := 0.0
# Le temps simule en attente d'etre joue. Le tick etant a pas FIXE, ce qui reste
# sous un pas complet est reporte a l'image suivante.
var _accumulateur := 0.0

func _ready() -> void:
	var grille := get_parent() as GridMap
	if grille == null:
		push_error("couvert.gd : ce noeud doit etre enfant DIRECT du GridMap du terrain")
		set_process(false)
		return
	if transform != Transform3D.IDENTITY:
		push_error("couvert.gd : ce noeud porte une transform propre -- les colonnes du releve ne coincideront pas avec celles du terrain")

	_config = appliquer_reglages(Vegetation.charger_config(), reglages())
	if _config.is_empty():
		set_process(false)
		return

	# LA CARTE GAGNE SUR LES CELLULES QUAND LE TERRAIN EN PORTE UNE. Un GridMap
	# qui ne rend qu'un disque autour du joueur n'a encore AUCUNE cellule ici --
	# l'ordre des _ready va des enfants vers le parent, et c'est le parent qui
	# les pose. Le releve viendrait vide, et plus rien ne pousserait nulle part.
	# La carte, elle, decrit tout le terrain sans rien rendre.
	var carte_du_terrain = grille.get("carte")
	if carte_du_terrain != null:
		_releve = Surface.relever_depuis_carte(grille, carte_du_terrain)
	else:
		_releve = Surface.relever(grille)
	if not Surface.porte_du_terrain(_releve):
		push_error("couvert.gd : le terrain ne porte aucune colonne -- rien sur quoi planter")
		set_process(false)
		return

	_types = _charger_les_especes()
	_pas_max = Vegetation.pas_maximal(_types, _config)
	if _pas_max > 0.0 and pas_simulation > _pas_max:
		push_error("couvert.gd : un pas de %.1f s depasse le plus grand pas fidele (%.1f s) -- des stades seront sautes" % [
			pas_simulation, _pas_max])
	var semis := _semis()
	if _types.is_empty():
		push_error("couvert.gd : aucune espece chargee -- rien ne peut pousser")
		set_process(false)
		return
	_preparer_les_rendus()

	_etat = Vegetation.etat_initial(semis, _releve, _config, _types)
	for refus in _etat.refus:
		push_warning("couvert.gd : semis '%s' en colonne %s -- %s" % [
			refus.id, refus.colonne, refus.raison])
	for graine in semis:
		if graine.noeud != null:
			for enfant in graine.noeud.get_children():
				enfant.queue_free()

	_prechauffer()

	# LA POSE VIENT APRES, EN UNE SEULE PASSE. Pendant le prechauffage il n'y a
	# rien a l'ecran : poser puis retirer des milliers de noeuds pour montrer une
	# croissance que personne ne regarde coute cher et ne rend rien.
	for plante in _etat.plantes:
		_poser_plante(plante)
	for graine in _etat.graines:
		_poser_graine(String(graine.id))
	_liberer_les_semis_disparus(semis)

	# LE COMPTE EST CELUI DES VIVANTES, jamais la taille de la liste : les mortes y
	# figurent jusqu'a la purge du tick suivant, et une trace qui les compte annonce
	# une foret plus grande que celle qu'on voit.
	print("couvert : %d semis, %d espece(s), %d tick(s) de prechauffage -> %d vivante(s), %d produit(s)" % [
		semis.size(), _types.size(), ticks_prechauffage,
		Vegetation.vivantes(_etat.plantes, _config).size(), (_etat.graines as Array).size()])

func _process(delta: float) -> void:
	if _etat.is_empty():
		return
	_accumulateur += delta * facteur_temps
	var joues := 0
	while _accumulateur >= pas_simulation and joues < ticks_max_par_image:
		_accumulateur -= pas_simulation
		joues += 1
		_appliquer(Vegetation.avancer_par_tranches(
			_etat, _config, _types, _releve, pas_simulation, _pas_max))
	if joues >= ticks_max_par_image:
		# Le retard restant est ABANDONNE -- voir ticks_max_par_image.
		_accumulateur = 0.0

# Le rendu, et rien d'autre : il RELIT le rapport du tick, il ne recalcule jamais
# ce qui vient de se passer.
func _appliquer(rapport: Dictionary) -> void:
	for id in rapport.morts:
		_retirer_plante(String(id))
	for changement in rapport.changements:
		_poser_modele(String(changement.id), String(changement.type), int(changement.numero))
	for naissance in rapport.naissances:
		var nee: Variant = _plante_par_id(String(naissance.id))
		if nee != null:
			_poser_plante(nee)
	for produit in rapport.produits:
		_poser_graine(String(produit.id))
	for id in rapport.perdues:
		retirer_graine(String(id))

# ---- Le prechauffage ----

# DES TICKS JOUES D'AVANCE, ET RIEN D'AUTRE. Aucune mecanique neuve : c'est
# EXACTEMENT la fonction de tick que _process appelle en jeu, appelee en boucle
# avant la premiere image. _process ne l'appelle PAS a chaque image -- il
# accumule le temps ecoule et ne joue un tour que lorsque `pas_simulation` est
# atteint, ce qui, au reglage courant, arrive une fois toutes les quelques
# secondes et jamais soixante fois par seconde. Le rapport de chaque tour est
# ignore VOLONTAIREMENT -- il ne sert qu'a tenir l'ecran a jour, et l'ecran
# n'existe pas encore.
#
# N ticks d'avance plus M ticks normaux doivent rendre le meme etat que N+M ticks
# normaux. Si les deux divergent, c'est que _process fait un travail de simulation
# que avancer() ne fait pas. test_plante.gd le verrouille.
func _prechauffer() -> void:
	if ticks_prechauffage <= 0:
		return
	for _i in range(ticks_prechauffage):
		Vegetation.avancer_par_tranches(
			_etat, _config, _types, _releve, delta_prechauffage, _pas_max)

# UN SEMIS PEUT NE PAS SURVIVRE A SON PROPRE PRECHAUFFAGE : pose a la main, il a
# vecu des minutes avant la premiere image et peut etre mort de vieillesse. Son
# noeud d'editeur, lui, est toujours la -- vide, invisible, jamais reclame. Il est
# libere ici, sans quoi chaque lancement laisserait autant de fantomes que de
# semis trop vieux.
func _liberer_les_semis_disparus(semis: Array) -> void:
	for graine in semis:
		if graine.noeud == null:
			continue
		if _poses.has(String(graine.id)):
			continue
		graine.noeud.queue_free()

# ---- Les reglages ----

func reglages() -> Dictionary:
	return {
		"rayon_voisinage_cellules": rayon_voisinage_cellules,
		"rayon_ombre_cellules": rayon_ombre_cellules,
		"rayon_trouee_cellules": rayon_trouee_cellules,
	}

# La fusion, PURE : rend une config NEUVE, l'originale n'est jamais mutee. Sans la
# copie profonde, deux couverts dans la meme scene se regleraient l'un l'autre par
# le Dictionary que JSON.parse_string leur a rendu.
static func appliquer_reglages(base: Dictionary, valeurs: Dictionary) -> Dictionary:
	if base.is_empty():
		return {}
	var config: Dictionary = base.duplicate(true)
	for cle in valeurs:
		config[cle] = valeurs[cle]
	return config

# ---- Les semis et les especes ----

# Les semis : les enfants qui portent le script de plante, dans l'ordre de la
# scene -- donc DETERMINISTE. Leur position est convertie en colonne par le
# releve, jamais gardee telle quelle : un semis lache entre deux cellules doit
# pousser SUR une cellule, pas a cheval.
func _semis() -> Array:
	var semis: Array = []
	for enfant in get_children():
		if enfant.get_script() != PlanteScript:
			continue
		var espece := String(enfant.type)
		if espece == "":
			espece = String(_config.type_par_defaut)
		semis.append({
			"id": String(enfant.name),
			"colonne": Surface.colonne_de(enfant.position, _releve),
			"type": espece,
			"noeud": enfant,
		})
	return semis

# LES ESPECES DECLAREES A L'INSPECTEUR, indexees par leur nom -- celui qu'un semis
# ecrit dans son champ `Type`. Une espece sans nom, sans stade, ou dont le nom est
# deja pris est nommee en console : jamais un couvert a moitie peuple en silence.
# LES ESPECES SONT DES NOEUDS ENFANTS, exactement comme les semis : le game
# designer les voit dans l'arbre de scene, en clique une, et n'a sous les yeux que
# ses reglages. Deux especes ne se melangent jamais dans le meme inspecteur.
#
# Une espece sans nom, sans stade, ou dont le nom est deja pris est nommee en
# console : jamais un couvert a moitie peuple en silence.
func _charger_les_especes() -> Dictionary:
	var types: Dictionary = {}
	for enfant in get_children():
		if enfant.get_script() != EspeceScript:
			continue
		var nom := String(enfant.nom)
		if nom == "":
			push_error("couvert.gd : l'espece '%s' n'a pas de nom -- aucun semis ne peut la reclamer" % enfant.name)
			continue
		if types.has(nom):
			push_error("couvert.gd : deux especes portent le nom '%s' -- la seconde est ignoree" % nom)
			continue
		var prepare := Vegetation.preparer_depuis_champs(nom, enfant.champs(), _config)
		if prepare.is_empty():
			push_error("couvert.gd : l'espece '%s' ne declare aucun stade -- elle ne peut pas vivre" % nom)
			continue
		types[nom] = prepare
	return types

# ---- Les corps ----

# UN CORPS PAR STADE ET PAR ESPECE, prepare une fois. Une espece a modeles recoit
# ses scenes ; une espece sans modele recoit des touffes hautes comme ses statures.
# Charger ou fabriquer a chaque changement de stade relirait les memes fichiers des
# centaines de fois.
func _preparer_les_rendus() -> void:
	var largeur := float(_config.largeur_touffe)
	var brins := int(_config.brins_touffe)
	for nom in _types:
		var type: Dictionary = _types[nom]
		var chemins: Array = type.modeles_stades
		var stades: Array = []
		for i in range((type.stades as Array).size()):
			var stature := float((type.stades as Array)[i].get("stature", 1.0))
			if i < chemins.size() and String(chemins[i]) != "":
				stades.append(_corps_depuis_chemin(String(chemins[i])))
			else:
				stades.append(_corps_touffe(stature, largeur, brins, type.couleur))
		var produit := _corps_touffe(largeur, largeur, brins, type.couleur)
		if String(type.modele_produit) != "":
			produit = _corps_depuis_chemin(String(type.modele_produit))
		# UNE FORME PAR STADE, PARTAGEE PAR TOUTES LES PLANTES DE L'ESPECE. Une
		# Shape3D est une ressource : mille arbres au meme stade pointent la meme,
		# et le moteur physique ne la decrit qu'une fois. En fabriquer une par
		# plante multiplierait la memoire par la population sans rien changer a
		# l'ecran. Vide quand l'espece ne declare aucun rayon.
		var troncs: Array = []
		for i in range((type.stades as Array).size()):
			troncs.append(forme_de_tronc(
				float(type.rayon_collision),
				float((type.stades as Array)[i].get("stature", 0.0))))
		# LA DISTANCE DE RENDU VOYAGE AVEC L'ENTREE, jamais relue au moment de
		# poser : le lot ne connait que l'entree qu'on lui donne, et lui
		# faire retrouver l'espece rouvrirait une table a chaque plante posee.
		var distance := float(type.get("distance_rendu", 0.0))
		for entree in stades:
			if not entree.is_empty():
				entree["distance_rendu"] = distance
				entree["pieces"] = pieces_de(entree)
		if not produit.is_empty():
			produit["distance_rendu"] = distance
			produit["pieces"] = pieces_de(produit)
		_rendus[nom] = {"stades": stades, "produit": produit, "troncs": troncs}

# LE FUT D'UNE PLANTE : un cylindre du rayon declare par l'espece, haut comme la
# stature du stade, POSE SUR LE SOL -- une CylinderShape3D est centree sur son
# origine, il faut donc la remonter d'une demi-hauteur pour que sa base touche
# y = 0, la ou la plante est posee. Sans ce decalage la moitie du tronc serait
# enterree et l'autre flotterait.
#
# Rend null quand le rayon ou la stature est nul : une plante sans fut ne recoit
# aucun corps, ce qui est le cas de l'herbe et de tout stade de stature zero.
static func forme_de_tronc(rayon: float, hauteur: float) -> CylinderShape3D:
	if rayon <= 0.0 or hauteur <= 0.0:
		return null
	var forme := CylinderShape3D.new()
	forme.radius = rayon
	forme.height = hauteur
	return forme

# Un corps charge depuis un .glb ou une scene, avec son recentrage MESURE.
func _corps_depuis_chemin(chemin: String) -> Dictionary:
	if not ResourceLoader.exists(chemin):
		push_error("couvert.gd : modele introuvable '%s' -- ce qui l'utilise restera invisible" % chemin)
		return {}
	var scene := load(chemin) as PackedScene
	if scene == null:
		push_error("couvert.gd : '%s' n'est pas une scene instanciable" % chemin)
		return {}
	var decalage := recentrage(scene)
	if decalage.length() > 0.01:
		print("couvert : '%s' n'est pas centre sur son origine, recentre de %s a l'affichage" % [
			chemin.get_file(), decalage])
	return {"scene": scene, "decalage": decalage}

func _corps_touffe(hauteur: float, largeur: float, brins: int, couleur: Array) -> Dictionary:
	return {"maillage": maillage_touffe(hauteur, largeur, brins, couleur), "decalage": Vector3.ZERO}

# LA TOUFFE : quelques lames verticales croisees, posees sur y = 0 et hautes comme
# la stature du stade. Elles se croisent en tournant autour de l'axe vertical, ce
# qui donne du volume sous n'importe quel angle sans qu'aucune ne soit orientee
# vers la camera -- une seule lame plate disparaitrait vue de profil.
#
# LES DEUX FACES SONT RENDUES (cull_mode desactive) : une lame vue de derriere
# serait invisible, et la moitie de la touffe manquerait selon l'angle. La normale
# pointe vers le haut plutot que sur le cote, sinon les lames s'assombrissent
# chacune differemment et la touffe scintille en tournant.
#
# AUCUN HASARD : les angles sont repartis regulierement. Deux touffes de meme
# stade sont identiques -- grossier, mais reproductible, et une variation
# aleatoire devrait passer par le RNG seede de l'etat, qui n'a rien a faire dans
# le rendu.
static func maillage_touffe(hauteur: float, largeur: float, brins: int, couleur: Array) -> ArrayMesh:
	var sommets := PackedVector3Array()
	var normales := PackedVector3Array()
	var indices := PackedInt32Array()
	var combien := maxi(brins, 1)
	for i in range(combien):
		var angle := PI * float(i) / float(combien)
		var cote := Vector3(cos(angle), 0.0, sin(angle)) * largeur * 0.5
		# La lame se retrecit vers le haut : un rectangle plein fait un panneau,
		# un trapeze fait une feuille.
		var haut := cote * 0.3
		var base := sommets.size()
		sommets.append_array(PackedVector3Array([
			-cote, cote, haut + Vector3(0.0, hauteur, 0.0), -haut + Vector3(0.0, hauteur, 0.0)]))
		for _n in range(4):
			normales.append(Vector3.UP)
		indices.append_array(PackedInt32Array([
			base, base + 1, base + 2, base, base + 2, base + 3]))

	var tableaux := []
	tableaux.resize(Mesh.ARRAY_MAX)
	tableaux[Mesh.ARRAY_VERTEX] = sommets
	tableaux[Mesh.ARRAY_NORMAL] = normales
	tableaux[Mesh.ARRAY_INDEX] = indices

	var materiau := StandardMaterial3D.new()
	materiau.albedo_color = Color(float(couleur[0]), float(couleur[1]), float(couleur[2]))
	materiau.cull_mode = BaseMaterial3D.CULL_DISABLED

	var maillage := ArrayMesh.new()
	maillage.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tableaux)
	maillage.surface_set_material(0, materiau)
	return maillage

# CE QU'IL FAUT AJOUTER A UN MODELE POUR QU'IL TOMBE OU ON LE POSE : de quoi
# ramener son empreinte au sol sur l'origine et sa base sur y = 0. Rend
# Vector3.ZERO pour un modele sans maillage -- inventer un decalage serait pire
# que de n'en poser aucun.
static func recentrage(scene: PackedScene) -> Vector3:
	var noeud := scene.instantiate() as Node3D
	if noeud == null:
		return Vector3.ZERO
	var boite: Variant = englobante(noeud, Transform3D.IDENTITY)
	noeud.free()
	if boite == null:
		return Vector3.ZERO
	var b: AABB = boite
	return Vector3(
		-(b.position.x + b.size.x * 0.5),
		-b.position.y,
		-(b.position.z + b.size.z * 0.5))

# L'encombrement reel d'un arbre de noeuds, transforms enchainees. Rend null quand
# il ne porte aucun maillage -- jamais une boite vide, qu'un appelant prendrait
# pour un objet a l'origine.
static func englobante(noeud: Node, parent: Transform3D) -> Variant:
	var local := parent
	if noeud is Node3D:
		local = parent * (noeud as Node3D).transform
	var boite: Variant = null
	if noeud is MeshInstance3D and (noeud as MeshInstance3D).mesh != null:
		boite = local * (noeud as MeshInstance3D).mesh.get_aabb()
	for enfant in noeud.get_children():
		var celle: Variant = englobante(enfant, local)
		if celle == null:
			continue
		boite = celle if boite == null else (boite as AABB).merge(celle)
	return boite

# LES PIECES D'UN MODELE : ses maillages, chacun avec la transform qu'il porte
# DANS le modele, decalage de recentrage compris. Un lot de rendu ne sait poser
# qu'un maillage a la fois ; un `.glb` en porte souvent plusieurs.
#
# LE MODELE EST INSTANCIE UNE FOIS, ICI, PUIS LIBERE : ce qu'on garde est une
# liste de ressources et de transforms, jamais un arbre de noeuds. C'est ce qui
# permet a mille plantes de ne rien instancier du tout.
#
# LE MATERIAU SUIT LA PIECE quand il est pose sur le noeud plutot que sur le
# maillage : un `.glb` peut faire l'un ou l'autre, et le perdre rendrait la
# plante grise sans qu'aucune erreur ne sorte.
static func pieces_de(entree: Dictionary) -> Array:
	if entree.is_empty():
		return []
	var decalage: Vector3 = entree.get("decalage", Vector3.ZERO)
	if entree.has("maillage"):
		return [{
			"maillage": entree.maillage,
			"pose": Transform3D(Basis(), decalage),
			"materiau": null,
		}]
	if not entree.has("scene"):
		return []
	var corps := (entree.scene as PackedScene).instantiate() as Node3D
	if corps == null:
		return []
	var pieces: Array = []
	ramasser_pieces(corps, Transform3D(corps.transform.basis, decalage), pieces)
	corps.free()
	return pieces

static func ramasser_pieces(noeud: Node, pose: Transform3D, pieces: Array) -> void:
	if noeud is MeshInstance3D and (noeud as MeshInstance3D).mesh != null:
		var vue := noeud as MeshInstance3D
		var materiau: Material = vue.material_override
		if materiau == null and vue.get_surface_override_material_count() > 0:
			materiau = vue.get_surface_override_material(0)
		pieces.append({"maillage": vue.mesh, "pose": pose, "materiau": materiau})
	for enfant in noeud.get_children():
		var locale := pose
		if enfant is Node3D:
			locale = pose * (enfant as Node3D).transform
		ramasser_pieces(enfant, locale, pieces)

# ---- Le rendu ----

func _plante_par_id(id: String) -> Variant:
	for plante in _etat.plantes:
		if String(plante.id) == id:
			return plante
	return null

func _poser_plante(plante: Dictionary) -> void:
	var id := String(plante.id)
	_poses[id] = plante.position
	var type := Vegetation.type_de(plante, _types)
	if type.is_empty():
		return
	_poser_modele(id, String(type.nom), Vegetation.numero_de_stade(plante, type))

# L'ECHANGE DE CORPS, et c'est tout ce qu'un changement de stade fait a l'ecran :
# la plante sort du lot de son ancien stade et entre dans celui du nouveau. Son
# tronc suit par le meme geste -- une pousse ne barre pas le passage comme un
# arbre mature.
func _poser_modele(id: String, espece: String, numero: int) -> void:
	_radier(id)
	_liberer_tronc(id)
	if not _rendus.has(espece):
		return
	var rendu: Dictionary = _rendus[espece]
	var stades: Array = rendu.stades
	if numero < 1 or numero > stades.size():
		return
	_inscrire(_cle_de_lot(espece, str(numero)), stades[numero - 1], id)
	_poser_tronc(id, rendu.troncs, numero)

# LE TRONC EST LE SEUL NOEUD QU'UNE PLANTE GARDE, et seulement si son espece
# declare un rayon : un corps physique ne rentre pas dans un lot de rendu, le
# moteur physique en veut un par obstacle. Une plante sans tronc n'a donc AUCUN
# noeud -- c'est le cas de l'herbe, et c'est la ou le regroupement rapporte le
# plus.
func _poser_tronc(id: String, troncs: Array, numero: int) -> void:
	var corps := _corps_solide(troncs, numero)
	if corps == null:
		return
	_porteur(id).add_child(corps)

# Le noeud d'une plante, cree au premier besoin. Il REPREND celui que le game
# designer a pose quand il existe : son nom est l'identifiant de la plante, et le
# perdre couperait le lien entre ce qu'il a place et ce qui pousse.
func _porteur(id: String) -> Node3D:
	if _noeuds.has(id):
		return _noeuds[id]
	var noeud := get_node_or_null(NodePath(id)) as Node3D
	if noeud == null:
		noeud = Node3D.new()
		noeud.name = id
		add_child(noeud)
	noeud.position = _poses.get(id, Vector3.ZERO)
	_noeuds[id] = noeud
	return noeud

# LE TRONC EST DETACHE TOUT DE SUITE (remove_child) avant d'etre libere :
# queue_free ne prend effet qu'en fin d'image, si bien que deux corps se
# superposeraient le temps d'une frame.
func _liberer_tronc(id: String) -> void:
	if not _noeuds.has(id):
		return
	var porteur: Node3D = _noeuds[id]
	var ancien := porteur.get_node_or_null(NodePath(NOM_TRONC))
	if ancien == null:
		return
	porteur.remove_child(ancien)
	ancien.queue_free()

# LE CORPS SOLIDE D'UN STADE : un StaticBody3D qui porte la forme partagee. C'est
# lui qui BLOQUE -- une Area3D detecterait sans arreter, ce qui n'est pas ce qu'un
# tronc fait. Rend null quand le stade ne declare aucune forme, auquel cas la
# plante n'a tout simplement pas d'enfant de collision.
#
# CE NOEUD N'EXISTE QUE POUR LE MOTEUR PHYSIQUE. La simulation ne le lit jamais et
# tourne identiquement sans lui (CLAUDE.md, « La simulation ne depend JAMAIS de
# l'affichage ») : jeu/plantes/vegetation.gd ignore jusqu'a son existence.
func _corps_solide(troncs: Array, numero: int) -> StaticBody3D:
	if numero < 1 or numero > troncs.size() or troncs[numero - 1] == null:
		return null
	var forme: CylinderShape3D = troncs[numero - 1]
	var corps := StaticBody3D.new()
	corps.name = NOM_TRONC
	var collision := CollisionShape3D.new()
	collision.shape = forme
	collision.position = Vector3(0.0, forme.height * 0.5, 0.0)
	corps.add_child(collision)
	return corps

# ---- LES LOTS DE RENDU ----
#
# UNE PLANTE N'EST PLUS UN OBJET A DESSINER, C'EST UNE LIGNE DANS UN LOT. Toutes
# les plantes d'une meme espece au meme stade sont le MEME modele a des positions
# differentes -- rien ne les distingue, ni couleur, ni echelle, ni rotation. Un
# MultiMesh porte donc le maillage UNE fois et la liste des positions, et la carte
# graphique dessine le lot entier d'un seul ordre au lieu d'un ordre par plante.
# Ce qu'on abandonne en echange : une ligne de lot n'est pas un noeud, elle ne
# porte ni script, ni enfant, ni reglage propre.
#
# UN MULTIMESH PAR MAILLAGE : un `.glb` est un arbre de noeuds qui peut en porter
# plusieurs, et un MultiMesh n'en connait qu'un. Chaque piece garde la transform
# qu'elle avait dans le modele, composee avec la position de la plante.
#
# LA DISTANCE DE RENDU DEVIENT CELLE DU LOT, et non plus celle de la plante : un
# lot se cache ou se dessine en bloc. C'est le prix du regroupement, et c'est
# pourquoi un lot reste une espece a un stade -- regrouper toute la carte ferait
# disparaitre une foret d'un coup.
#
# LE RETRAIT NE DECALE RIEN : la derniere ligne prend la place de celle qui part.
# Recompacter la liste ferait payer la population a chaque mort.
func _cle_de_lot(espece: String, stade: String) -> String:
	return "%s#%s" % [espece, stade]

# Le lot d'une cle, cree au premier besoin. Rend un Dictionary VIDE quand l'entree
# ne porte aucune piece -- un modele manquant a deja ete signale au chargement, et
# la plante reste alors simplement invisible.
func _lot(cle: String, entree: Dictionary) -> Dictionary:
	if _lots.has(cle):
		return _lots[cle]
	var pieces: Array = entree.get("pieces", [])
	if pieces.is_empty():
		return {}
	var instances: Array = []
	for i in range(pieces.size()):
		var piece: Dictionary = pieces[i]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = piece.maillage
		multi.instance_count = 0
		var noeud := MultiMeshInstance3D.new()
		# Nomme par son RANG, jamais par l'espece : le nom d'un noeud de scene n'a
		# pas a porter un nom de contenu.
		noeud.name = "lot_%d_%d" % [_lots.size(), i]
		noeud.multimesh = multi
		if piece.get("materiau") != null:
			noeud.material_override = piece.materiau
		poser_distance_rendu(noeud, float(entree.get("distance_rendu", 0.0)))
		add_child(noeud)
		instances.append({"noeud": noeud, "pose": piece.pose})
	var lot := {"instances": instances, "ids": [], "poses": [], "index": {}, "capacite": 0}
	_lots[cle] = lot
	return lot

func _inscrire(cle: String, entree: Dictionary, id: String) -> void:
	var lot := _lot(cle, entree)
	if lot.is_empty():
		return
	var rang: int = (lot.ids as Array).size()
	(lot.ids as Array).append(id)
	(lot.poses as Array).append(_poses.get(id, Vector3.ZERO))
	(lot.index as Dictionary)[id] = rang
	_lot_de[id] = cle
	_ecrire_lot(lot, rang)

func _radier(id: String) -> void:
	if not _lot_de.has(id):
		return
	var lot: Dictionary = _lots[_lot_de[id]]
	_lot_de.erase(id)
	var rang: int = int((lot.index as Dictionary)[id])
	(lot.index as Dictionary).erase(id)
	var dernier: int = (lot.ids as Array).size() - 1
	if rang != dernier:
		var deplace := String((lot.ids as Array)[dernier])
		(lot.ids as Array)[rang] = deplace
		(lot.poses as Array)[rang] = (lot.poses as Array)[dernier]
		(lot.index as Dictionary)[deplace] = rang
	(lot.ids as Array).resize(dernier)
	(lot.poses as Array).resize(dernier)
	_ecrire_lot(lot, rang if rang != dernier else -1)

# Ecrit le lot dans ses MultiMesh. `rang` designe la seule ligne qui a bouge, -1
# n'en redresse aucune.
#
# LA CAPACITE DOUBLE, ELLE NE SUIT PAS LE COMPTE : agrandir un MultiMesh
# reconstruit son tampon, et le faire a chaque plante couterait plus cher que ce
# que le regroupement fait gagner. Un agrandissement reecrit tout le lot, parce
# que le contenu du tampon neuf n'est garanti nulle part.
func _ecrire_lot(lot: Dictionary, rang: int) -> void:
	var combien: int = (lot.ids as Array).size()
	var tout := false
	if combien > int(lot.capacite):
		var capacite: int = maxi(int(lot.capacite), 32)
		while combien > capacite:
			capacite *= 2
		lot.capacite = capacite
		tout = true
	for instance in lot.instances:
		var multi: MultiMesh = (instance.noeud as MultiMeshInstance3D).multimesh
		if tout:
			multi.instance_count = int(lot.capacite)
			for i in range(combien):
				multi.set_instance_transform(i, pose_de_ligne(
					(lot.poses as Array)[i], instance.pose))
		elif rang >= 0 and rang < combien:
			multi.set_instance_transform(rang, pose_de_ligne(
				(lot.poses as Array)[rang], instance.pose))
		multi.visible_instance_count = combien

# La transform d'une ligne : la position de la plante, portant la piece la ou elle
# etait dans le modele.
static func pose_de_ligne(position: Vector3, piece: Transform3D) -> Transform3D:
	return Transform3D(Basis(), position) * piece

# Combien de lignes un lot porte, et quels lots existent. Pour les tests et les
# traces : rien du rendu n'en depend.
func lignes_du_lot(cle: String) -> int:
	if not _lots.has(cle):
		return 0
	return ((_lots[cle] as Dictionary).ids as Array).size()

func lots() -> Dictionary:
	return _lots

# LA DISTANCE DE RENDU, POSEE SUR CHAQUE PIECE QUI SE DESSINE. `visibility_range_
# end` appartient a GeometryInstance3D, pas a Node3D : un `.glb` est un Node3D qui
# en porte plusieurs, la poser sur sa racine ne toucherait rien. On descend donc
# l'arbre entier.
#
# A ZERO, RIEN N'EST ECRIT : la propriete garde son defaut, tout se dessine, et une
# espece qui ne declare pas de distance se comporte exactement comme avant.
#
# LA CAMERA EN DECIDE SEULE. Aucun appelant n'a besoin de savoir ou est le joueur,
# et c'est ce qui rend le geste valable pour mille types d'objets sans un champ a
# remplir sur chacun.
static func poser_distance_rendu(corps: Node, distance: float) -> int:
	if distance <= 0.0 or corps == null:
		return 0
	var poses := 0
	var a_visiter: Array = [corps]
	while not a_visiter.is_empty():
		var noeud: Node = a_visiter.pop_back()
		if noeud is GeometryInstance3D:
			(noeud as GeometryInstance3D).visibility_range_end = distance
			poses += 1
		for enfant in noeud.get_children():
			a_visiter.append(enfant)
	return poses

func _retirer_plante(id: String) -> void:
	_radier(id)
	_poses.erase(id)
	if not _noeuds.has(id):
		return
	_noeuds[id].queue_free()
	_noeuds.erase(id)

func _poser_graine(id: String) -> void:
	if _lot_de.has(id):
		return
	for graine in _etat.graines:
		if String(graine.id) != id:
			continue
		var espece := String(graine.type_plante)
		if not _rendus.has(espece):
			return
		_poses[id] = graine.position
		_inscrire(_cle_de_lot(espece, "produit"), _rendus[espece].produit, id)
		return

# Retire le corps d'un produit perdu OU ramasse. Le ramassage par les unites
# n'existe pas encore -- Vegetation.ramasser attend son appelant -- mais le geste
# est le meme des deux cotes, et il est pose ici pour que ce futur cablage n'ait
# pas a fouiller le rendu.
func retirer_graine(id: String) -> void:
	_radier(id)
	_poses.erase(id)
