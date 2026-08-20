@tool
extends Node3D

# OUTIL D'EDITEUR, jamais du jeu. Il fait passer une FENETRE de terrain entre la
# carte et le GridMap frere, dans les deux sens : charger la fenetre pour la
# sculpter, l'enregistrer une fois sculptee. Il ne tourne QUE dans l'editeur --
# aucun _ready, aucun _process, le seul evenement qui l'active est une case
# cochee dans l'inspecteur. Lance en jeu, ce noeud ne fait rien.
#
# Entree : la carte, le centre de la fenetre EN COLONNES DE LA CARTE, et sa
# demi-largeur. Sortie : les cellules du GridMap frere (au chargement), ou les
# sommets de la carte et son fichier (a l'enregistrement).
#
# POURQUOI UNE FENETRE. Une carte de cent kilometres carres ne se materialise
# pas en cellules : 175 millions de cellules pesent des gigaoctets, en scene
# comme en memoire. Elle n'a pas besoin de l'etre pour se sculpter -- on ne
# sculpte qu'un endroit a la fois. La fenetre est cet endroit, et rien d'autre
# n'existe en cellules pendant qu'on y travaille.
#
# LA FENETRE SE POSE LA OU ELLE EST SUR LA CARTE, jamais autour de l'origine. La
# colonne 1000 de la carte devient la cellule 1000 du GridMap : deplacer le
# curseur DEPLACE le terrain rendu, au lieu d'en changer le contenu sur place.
# C'est la seule facon de voir qu'on a change d'endroit sur une carte plate, et
# c'est deja la convention du JEU -- terrain_visible.gd pose aux memes
# coordonnees. Deux conventions opposees sur un meme GridMap selon qu'on edite
# ou qu'on joue etait une incoherence, pas un choix.
#
# CE QUI EN DECOULE POUR LES OUTILS DE SCULPTURE : leur boite ne peut plus etre
# ecretee a la constante du generateur, sinon rien ne se sculpte au-dela des
# cent cinquante premieres cellules. Ils lisent desormais l'emprise sur la carte
# -- voir terrain_commun.gd:emprise_fraternelle.
#
# LA SCENE NE PORTE JAMAIS LE TERRAIN, c'est la carte qui le porte. Une fenetre
# chargee pese 630 000 cellules, soit une dizaine de megaoctets dans le fichier
# de scene a chaque sauvegarde -- et surtout DEUX VERITES qui divergeront. C'est
# la pratique etablie des editeurs de terrain (Terrain3D range ses regions dans
# un repertoire dedie, le plugin heightmap de Zylann un dossier de donnees) : la
# scene ne garde qu'une reference, jamais le contenu. D'ou « vider », a cocher
# avant d'enregistrer la scene.
#
# IL SCULPTE SANS COLLISION, ET C'EST CE QUI REND LA FENETRE UTILISABLE. Un
# GridMap cree un corps physique PAR CELLULE, et ce cout est paye a la frame qui
# suit la pose, pas a la pose. Mesure sur une fenetre de 630 000 cellules : pose
# 215 ms, puis 28 SECONDES de reconstruction -- contre 267 ms avec la meme
# bibliotheque privee de ses formes. Cent fois moins.
#
# AUCUN REGLAGE DU NOEUD NE L'EVITE : collision_layer et collision_mask a zero,
# interpolation coupee, noeud desactive -- les trois mesures restent a
# vingt-deux secondes. Les corps sont crees quels que soient les calques.
#
# ON NE MARCHE PAS SUR UN TERRAIN QU'ON SCULPTE : la collision ne sert qu'en
# jeu, ou terrain_visible.gd ne pose qu'un disque autour du joueur. « vider »
# rend sa bibliotheque d'origine au GridMap -- c'est le geste de fin, celui
# qu'on coche avant d'enregistrer la scene.
#
# CE QUI EST SCULPTE S'ENREGISTRE TOUT SEUL. Un bouton a cocher apres chaque
# geste est un bouton qu'on oublie, et ce qu'on oublie d'enregistrer n'existe
# pas au lancement du jeu -- le GridMap n'est qu'un cache, la carte est la seule
# verite. L'outil surveille donc la grille et ecrit quand la main s'arrete.
#
# QUAND LA MAIN S'ARRETE, JAMAIS PENDANT. Ecrire a chaque cellule posee
# relancerait un releve complet et une ecriture disque a chaque coup de
# pinceau. On attend que le compte de cellules cesse de bouger pendant
# `secondes_avant_enregistrement`, et on ecrit une fois.
#
# LE COMPTE DE CELLULES SUFFIT A DETECTER LE GESTE, et c'est un choix de cout :
# comparer les sommets colonne par colonne demanderait le releve qu'on cherche
# justement a ne pas refaire. Le cas qu'il rate -- retirer une cellule et en
# poser une autre dans la meme fenetre de temps -- laisse le compte identique ;
# le bouton « enregistrer » reste la pour ces cas, et le prochain geste rattrape.
#
# DEPLACER LA FENETRE EST UN SEUL GESTE : ce qui etait sous elle s'ECRIT dans la
# carte, puis se DECHARGE, et la nouvelle zone se rend. C'est toute la raison
# d'etre de la fenetre -- ne jamais tenir plus qu'un endroit en cellules. Un
# deplacement qui se contenterait de changer un chiffre laisserait le travail
# dans le GridMap, ou le chargement suivant l'effacerait sans un mot.
#
# CHARGER IMPOSE AUSSI L'ARETE DE LA CELLULE, lue sur la carte. Le GridMap ne la
# porte pas : la carte est seule a la declarer, et terrain_visible.gd la lui
# demande de son cote pour le jeu. Sans ce geste, l'editeur sculpterait a une
# echelle et le jeu afficherait a une autre, sur la meme carte -- aucune erreur,
# et un terrain qui change de taille au lancement.
#
# CHARGER EFFACE LE GRIDMAP. C'est le seul geste destructeur de ce fichier :
# une sculpture non enregistree ne survit pas a un chargement. D'ou le
# garde-fou -- enregistrer est refuse si le centre a change depuis le
# chargement, parce que le GridMap porterait alors le relief d'un endroit et
# l'outil l'ecrirait a un autre.
#
# LE SOMMET FAIT FOI, JAMAIS LES CELLULES UNE A UNE. La carte ne retient qu'une
# hauteur par colonne : une grotte creusee sous la surface ne s'y ecrit pas et
# se perd a l'enregistrement. La carte est un RELIEF, pas un volume.
#
# RIEN N'EST ANNULABLE : Ctrl+Z defait la case cochee, jamais ce qui a ete
# ecrit. Meme limite que outil_sculpture.gd, meme parade -- recharger la
# fenetre.
#
# Regles tenues : positions en Vector3i (grille), jamais Vector2 -- une COLONNE
# est un Vector2i, un index et pas une position. Aucun hasard. Les traces sont
# des sorties de mise au point pour l'editeur, jamais du texte joueur. Rien de
# scripts/, data/ ni documents/ n'est lu ni ecrit.

const Commun = preload("res://jeu/terrain/terrain_commun.gd")

# Combien de colonnes poser avant de rendre la main a l'editeur.
#
# MESURE, PAS AU JUGE, et le premier reglage etait trop timide : a 300 colonnes,
# une fenetre de 90 000 colonnes demandait 300 frames -- cinq secondes au mieux,
# bien plus dans un editeur qui tourne au ralenti quand rien ne bouge, et le
# chargement se lisait comme une panne. A 10 000, la meme fenetre tient en neuf
# frames, et chaque frame reste sous les trente millisecondes que vise
# outil_sculpture.gd : 630 000 cellules se posent en 216 ms au total.

# ECRIT CHAQUE BRANCHE DE deplacer_vers dans la console. Voir repere_fenetre.gd :
# aucun banc en ligne de commande ne parcourt ce chemin.
@export var journal := true

# Voir repere_fenetre.gd : si cette ligne n'apparait pas, le script execute
# n'est pas celui du disque.
const VERSION := "fenetre 6 -- sans collision, vidage, streaming"

# La carte a travailler. Sans elle, cet outil ne fait rien et le dit.
@export var carte: Resource

# Voir le commentaire ci-dessus : c'est un reglage, il se regle.
@export var colonnes_par_frame: int = 10000

# La bibliotheque que portait le GridMap avant le premier chargement, mise de
# cote pour lui etre rendue. Renseignee toute seule ; exportee pour survivre a
# la fermeture de l'editeur, sans quoi « vider » ne saurait plus quoi restaurer.
@export var bibliotheque_de_jeu: MeshLibrary

# QUEL morceau de la carte la fenetre represente : la colonne de la carte qui
# tombe sur l'origine du GridMap. Le deplacer, puis charger, c'est aller
# sculpter ailleurs.
@export var centre := Vector2i.ZERO

# Demi-largeur de la fenetre, en colonnes. La fenetre couvre [-demi, demi - 1]
# sur les deux axes, autour de l'origine du GridMap.
@export var demi_fenetre: int = 150

# Le centre effectivement charge dans le GridMap. Ecrit par le chargement, relu
# par le garde-fou de l'enregistrement.
#
# IL EST EXPORTE, DONC IL SURVIT A LA FERMETURE DE L'EDITEUR : un garde-fou qui
# s'oublie entre deux sessions refuserait d'enregistrer une fenetre pourtant
# valide, et la seule parade serait de le desactiver.
@export var centre_charge := Vector2i.ZERO
@export var fenetre_chargee := false

@export var charger := false:
	set(demande):
		charger = false
		if demande:
			_charger()

@export var enregistrer := false:
	set(demande):
		enregistrer = false
		if demande:
			_enregistrer()

# Vide le GridMap sans rien ecrire : ce qui a ete enregistre vit dans la carte,
# et la scene n'a pas a le porter une seconde fois.
@export var vider := false:
	set(demande):
		vider = false
		if demande:
			_vider()

# Ce que fait un deplacement du curseur : enregistrer ce qui etait la, puis
# rendre la nouvelle zone. A false, deplacer ne fait que changer le centre et
# c'est « charger » qui decide -- utile pour viser sans rien ecrire.
@export var suivre_le_curseur := true

# Voir l'en-tete : ce qui est sculpte part dans la carte sans qu'on le demande.
@export var enregistrement_automatique := true

# Combien de temps la grille doit rester immobile avant d'ecrire. Trop court,
# on ecrit au milieu d'un geste ; trop long, on perd le travail si l'editeur
# ferme.
@export var secondes_avant_enregistrement: float = 1.5

var _cellules_vues := -1
var _immobile_depuis := 0.0

var _en_cours := false

# LES COLONNES REELLEMENT POSEES PAR LE DERNIER CHARGEMENT, et elles seules.
#
# SANS CET ENSEMBLE, ENREGISTRER CREUSE. Il ecrit toute la fenetre, et une
# colonne absente du GridMap compte comme VIDE -- or « absente » a deux causes
# que rien ne distingue : le sculpteur l'a creusee jusqu'au vide, ou elle n'a
# jamais ete chargee. Le second cas se produit des qu'un chargement est
# interrompu, ou que la grille porte autre chose que la fenetre demandee. Ce
# qui n'a pas ete charge n'est donc jamais ecrit.
var _colonnes_chargees: Dictionary = {}

# CE QU'UN GRIDMAP PORTE, en une ligne lisible : combien de cellules, sur
# combien de colonnes, et entre quelles bornes. Les BORNES sont ce qui tranche :
# deux emprises cote a cote se voient a leur etendue, la ou un simple compte ne
# dirait rien.
static func emprise_lisible(grille: GridMap) -> String:
	var cellules := grille.get_used_cells()
	if cellules.is_empty():
		return "VIDE (0 cellule)"
	var colonnes: Dictionary = {}
	var bas := Vector2i(cellules[0].x, cellules[0].z)
	var haut := bas
	for c in cellules:
		var colonne := Vector2i(c.x, c.z)
		colonnes[colonne] = true
		bas.x = mini(bas.x, colonne.x)
		bas.y = mini(bas.y, colonne.y)
		haut.x = maxi(haut.x, colonne.x)
		haut.y = maxi(haut.y, colonne.y)
	return "%d cellules, %d colonnes, de %v a %v (%d x %d)" % [
		cellules.size(), colonnes.size(), bas, haut,
		haut.x - bas.x + 1, haut.y - bas.y + 1]

# La meme bibliotheque, privee de ses formes de collision. Maillages, noms,
# transformations et vignettes sont conserves : a l'ecran rien ne change, et les
# identifiants d'items restent les memes -- ce que le GridMap a deja pose
# continue de designer le meme bloc.
static func sans_collision(source: MeshLibrary) -> MeshLibrary:
	var allegee := MeshLibrary.new()
	for identifiant in source.get_item_list():
		allegee.create_item(identifiant)
		allegee.set_item_name(identifiant, source.get_item_name(identifiant))
		allegee.set_item_mesh(identifiant, source.get_item_mesh(identifiant))
		allegee.set_item_mesh_transform(identifiant, source.get_item_mesh_transform(identifiant))
		var vignette := source.get_item_preview(identifiant)
		if vignette != null:
			allegee.set_item_preview(identifiant, vignette)
	return allegee

# Les colonnes que couvre une fenetre, EN COLONNES DE LA CARTE. Ce sont aussi
# celles du GridMap : la fenetre se pose la ou elle est, voir l'en-tete.
static func colonnes_de(centre_fenetre: Vector2i, demi: int) -> Array[Vector2i]:
	var colonnes: Array[Vector2i] = []
	for x in range(centre_fenetre.x - demi, centre_fenetre.x + demi):
		for z in range(centre_fenetre.y - demi, centre_fenetre.y + demi):
			colonnes.append(Vector2i(x, z))
	return colonnes

# LA CELLULE DU GRIDMAP EST LA COLONNE DE LA CARTE. Ces deux fonctions n'ont
# plus rien a convertir ; elles restent parce que l'intention se lit -- « ici on
# passe d'un monde a l'autre » -- et parce qu'un decalage qui reviendrait un
# jour n'aurait qu'un seul endroit ou s'ecrire.
static func vers_carte(cellule: Vector2i, _centre_fenetre: Vector2i) -> Vector2i:
	return cellule

static func vers_grille(colonne: Vector2i, _centre_fenetre: Vector2i) -> Vector2i:
	return colonne

# Le sommet de chaque colonne du GridMap, releve en UNE passe sur les cellules
# occupees. Lire colonne par colonne coute une requete par cellule de la
# fenetre ; ici le cout suit ce qui est POSE. Meme geste que
# surface_terrain.gd:relever.
static func sommets_du_gridmap(grille: GridMap) -> Dictionary:
	var sommets: Dictionary = {}
	for cellule in grille.get_used_cells():
		var colonne := Vector2i(cellule.x, cellule.z)
		if not sommets.has(colonne) or cellule.y > int(sommets[colonne]):
			sommets[colonne] = cellule.y
	return sommets

# Pose dans le GridMap les colonnes d'indice [depuis, depuis + combien) de la
# fenetre, telles que la carte les decrit. Rend { index, cellules }.
#
# UNE COLONNE HORS EMPRISE NE POSE RIEN, et c'est ainsi qu'une fenetre a cheval
# sur le bord de la carte se voit : le terrain s'y arrete, au lieu de se
# prolonger dans du vide que rien ne borne.
static func charger_tranche(grille: GridMap, source: Resource, colonnes: Array[Vector2i],
		centre_fenetre: Vector2i, bloc: int, depuis: int, combien: int) -> Dictionary:
	var index := clampi(depuis, 0, colonnes.size())
	var fin := mini(index + maxi(combien, 1), colonnes.size())
	var cellules := 0
	while index < fin:
		var colonne := colonnes[index]
		var haut: Variant = source.sommet(colonne)
		if haut != null:
			for y in range(source.couche_base, int(haut) + 1):
				grille.set_cell_item(Vector3i(colonne.x, y, colonne.y), bloc)
				cellules += 1
		index += 1
	return { "index": fin, "cellules": cellules }

# Ecrit dans la carte le relief du GridMap, sur toute la fenetre. Rend le nombre
# de colonnes dont le sommet a CHANGE.
#
# TOUTE LA FENETRE EST ECRITE, pas seulement ce qui a ete touche : une colonne
# creusee jusqu'au vide n'apparait dans aucune cellule, et n'ecrire que ce qu'on
# voit la laisserait pleine dans la carte. La fenetre fait autorite sur son
# emprise, entierement.
# CE QUE LE GRIDMAP PORTE RECOUVRE-T-IL BIEN LA FENETRE QU'ON VEUT ECRIRE ?
#
# LE FILET CONTRE LE GESTE QUI CREUSE. Enregistrer ecrit TOUTE la fenetre, et
# une colonne absente du GridMap compte comme VIDE : si le GridMap est pose
# ailleurs -- ou pas encore rempli -- aucune colonne ne correspond, et la
# fenetre entiere part en trou dans la carte. Rien a l'ecran ne le montre sur
# le coup ; ca se voit plus tard, en damier.
#
# Le seuil est LARGE : un sculpteur peut legitimement avoir creuse une bonne
# part de sa fenetre jusqu'au vide. Ce qu'on refuse est le cas ou le GridMap
# n'a RIEN a voir avec la zone demandee.
const RECOUVREMENT_MINIMAL := 0.05

static func recouvrement(sommets: Dictionary, centre_fenetre: Vector2i, demi: int) -> float:
	var attendues := demi * demi * 4
	if attendues <= 0:
		return 0.0
	var connues := 0
	for colonne in colonnes_de(centre_fenetre, demi):
		if sommets.has(colonne):
			connues += 1
	return float(connues) / float(attendues)

# `permises` : les colonnes que le chargement a REELLEMENT traitees. Vide, on
# ecrit toute la fenetre -- l'ancien comportement, garde pour les appels qui
# posent eux-memes leur grille et savent ce qu'elle contient.
static func enregistrer_fenetre(grille: GridMap, cible: Resource, centre_fenetre: Vector2i,
		demi: int, permises: Dictionary = {}) -> int:
	var sommets := sommets_du_gridmap(grille)

	# VOIR RECOUVREMENT_MINIMAL : on refuse d'ecrire une fenetre que la grille
	# ne porte pas, plutot que de la creuser en silence.
	var part := recouvrement(sommets, centre_fenetre, demi)
	if part < RECOUVREMENT_MINIMAL:
		push_error(("enregistrement refuse en %v : le GridMap ne recouvre que %.1f %% "
			+ "de cette fenetre. L'ecrire la creuserait entierement dans la carte.") % [
			centre_fenetre, part * 100.0])
		return 0
	var vide: int = cible.couche_base - 1
	var changees := 0
	for colonne in colonnes_de(centre_fenetre, demi):
		if not cible.dans_emprise(colonne):
			continue
		var avant: Variant = cible.sommet(colonne)

		# CE QUE LA GRILLE PORTE EST TOUJOURS ECRIT : c'est du travail, qu'il
		# ait ete charge ici ou pose a la main ailleurs dans la fenetre.
		#
		# CE QU'ELLE NE PORTE PAS n'est ecrit VIDE que si la colonne a bien ete
		# chargee. Sans cette distinction, une colonne jamais chargee part en
		# trou -- et avec la distinction posee sur les DEUX cas, c'est l'inverse
		# qui casse : ce qu'on sculpte hors des colonnes chargees ne s'ecrit
		# jamais, et le bouton « enregistrer » ne conserve rien.
		if not sommets.has(colonne):
			if not permises.is_empty() and not permises.has(colonne):
				continue
		var apres: int = int(sommets.get(colonne, vide))
		cible.sculpter(colonne, apres)
		var relu: Variant = cible.sommet(colonne)
		if relu != avant:
			changees += 1
	return changees

# LA SURVEILLANCE. Voir l'en-tete : elle ne CALCULE rien, elle compte les
# cellules et attend que ce compte cesse de bouger.
func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	if not enregistrement_automatique or _en_cours or not fenetre_chargee:
		return
	if carte == null:
		return
	var grille := Commun.terrain_frere(self)
	if grille == null:
		return

	var suite := surveiller(
		grille.get_used_cells().size(), _cellules_vues, _immobile_depuis, delta,
		secondes_avant_enregistrement)
	_cellules_vues = suite["vues"]
	_immobile_depuis = suite["immobile"]
	if suite["ecrire"]:
		_enregistrer_automatiquement(grille)

# LA DECISION D'ECRIRE, sortie de _process pour etre verrouillable sans editeur
# ni horloge : la boucle d'images ne fait que la declencher. Rend
# { vues, immobile, ecrire }.
#
# `immobile` NEGATIF veut dire « deja ecrit pour ce compte-la » : sans cette
# marque, la grille restant immobile, on reecrirait le fichier a chaque image
# qui suit.
static func surveiller(maintenant: int, vues: int, immobile: float, delta: float,
		seuil: float) -> Dictionary:
	if maintenant != vues:
		# LA MAIN BOUGE ENCORE : on repart de zero, rien ne s'ecrit.
		return { "vues": maintenant, "immobile": 0.0, "ecrire": false }
	if immobile < 0.0:
		return { "vues": vues, "immobile": immobile, "ecrire": false }
	var cumul := immobile + delta
	if cumul < maxf(seuil, 0.0):
		return { "vues": vues, "immobile": cumul, "ecrire": false }
	return { "vues": vues, "immobile": -1.0, "ecrire": true }

func _enregistrer_automatiquement(grille: GridMap) -> void:
	var changees := enregistrer_fenetre(
		grille, carte, centre_charge, demi_fenetre, _colonnes_chargees)
	if changees == 0:
		return
	if carte.resource_path.is_empty():
		push_warning("la carte n'a aucun chemin sur le disque : le relief n'est ecrit qu'en memoire")
		return
	var erreur := ResourceSaver.save(carte, carte.resource_path)
	if erreur != OK:
		push_error("enregistrement automatique impossible (erreur %d)" % erreur)
		return
	print("enregistrement automatique : %d colonnes ecrites dans %s" % [
		changees, carte.resource_path])

# LE GESTE COMPLET, appele par le curseur quand il a fini de bouger : ce qui
# etait sous la fenetre part dans la carte, le GridMap se vide, la nouvelle zone
# se rend. Rend true si quelque chose a ete fait.
#
# SANS FENETRE CHARGEE, ON NE FAIT RIEN : viser sur une scene qu'on vient
# d'ouvrir ne doit pas declencher une ecriture que personne n'a demandee.
func deplacer_vers(vise: Vector2i) -> bool:
	if journal:
		print("[%s] deplacer_vers %v : chargee=%s, centre_charge=%v, suivre=%s, en_cours=%s" % [
			VERSION, vise, fenetre_chargee, centre_charge, suivre_le_curseur, _en_cours])
	if not suivre_le_curseur or _en_cours:
		if journal:
			print("  -> RIEN : suivre_le_curseur=%s, en_cours=%s" % [suivre_le_curseur, _en_cours])
		return false
	if not fenetre_chargee or vise == centre_charge:
		if journal:
			print("  -> RIEN : %s" % ("aucune fenetre chargee" if not fenetre_chargee
				else "on y est deja (%v)" % vise))
		centre = vise
		return false
	if carte == null:
		if journal:
			print("  -> RIEN : aucune carte")
		return false

	var grille := Commun.terrain_frere(self)
	if grille == null:
		if journal:
			print("  -> RIEN : aucun GridMap frere")
		return false

	# 1. CE QUI ETAIT LA PART DANS LA CARTE, avant que quoi que ce soit ne bouge.
	if journal:
		var ecart := vise - centre_charge
		var largeur := demi_fenetre * 2
		print("  [pas] %v -> %v : ecart %v colonnes, largeur de fenetre %d%s" % [
			centre_charge, vise, ecart, largeur,
			"" if (absi(ecart.x) == largeur or ecart.x == 0)
				and (absi(ecart.y) == largeur or ecart.y == 0)
				else "  <-- PAS UN MULTIPLE : deux zones se chevauchent ou laissent un vide"])
	var changees := enregistrer_fenetre(
		grille, carte, centre_charge, demi_fenetre, _colonnes_chargees)
	if not carte.resource_path.is_empty():
		var erreur := ResourceSaver.save(carte, carte.resource_path)
		if erreur != OK:
			push_error("ecriture de %s impossible (erreur %d) : deplacement annule" % [
				carte.resource_path, erreur])
			return false
	print("deplacement : %v enregistre (%d colonnes changees), on va en %v" % [
		centre_charge, changees, vise])

	# 2. LA NOUVELLE ZONE SE REND. charger vide le GridMap avant de poser.
	centre = vise
	await _charger()
	if journal:
		print("  -> FAIT : %d cellules rendues en %v" % [
			grille.get_used_cells().size(), centre_charge])
	return true

func _charger() -> void:
	if _en_cours:
		push_warning("un transfert de fenetre est deja en cours : celui-ci est ignore")
		return
	var grille := Commun.terrain_frere(self)
	if grille == null:
		return
	if carte == null:
		push_error("outil_fenetre sans carte : rien a charger")
		return
	var bloc := Commun.premier_bloc(grille)
	if bloc == GridMap.INVALID_CELL_ITEM:
		return

	# LA CARTE DIT LA TAILLE DE SA CELLULE. Voir l'en-tete.
	grille.cell_size = Vector3(carte.cote, carte.cote, carte.cote)

	# ON MET DE COTE LA BIBLIOTHEQUE DE JEU AVANT DE LA REMPLACER, et une seule
	# fois : un second chargement mettrait de cote la version allegee, qui
	# deviendrait alors ce que « vider » restaure -- un terrain de jeu sans
	# collision, et rien pour le signaler.
	if bibliotheque_de_jeu == null:
		bibliotheque_de_jeu = grille.mesh_library
	grille.mesh_library = sans_collision(bibliotheque_de_jeu)

	# LE CENTRE EST FIGE ICI, ET RELU NULLE PART ENSUITE. La pose s'etale sur
	# plusieurs frames ; pendant ces attentes le curseur continue de tourner et
	# peut ecrire un nouveau `centre`. Le relire a la fin ferait annoncer
	# `centre_charge` a un endroit ou RIEN n'a ete pose -- et l'enregistrement
	# suivant, ne trouvant aucune colonne connue dans le GridMap, ecrirait du
	# VIDE sur toute la fenetre et creuserait la carte.
	var pose_sur := centre
	var colonnes := colonnes_de(pose_sur, demi_fenetre)
	_colonnes_chargees = {}
	print("chargement de la fenetre centree sur %v : %d colonnes de %.1f m, %d frames" % [
		pose_sur, colonnes.size(), carte.cote,
		ceili(float(colonnes.size()) / float(maxi(colonnes_par_frame, 1)))])
	# LE GRIDMAP EST VIDE D'ABORD : sans ca, le relief precedent survivrait sous
	# le nouveau partout ou celui-ci est plus bas.
	if journal:
		print("  [sculpture] avant clear : %s" % emprise_lisible(grille))
	grille.clear()
	if journal:
		print("  [sculpture] apres clear : %s" % emprise_lisible(grille))

	# LE CHRONO PART AVANT LA PREMIERE TRANCHE et court a travers les frames
	# attendues : ce qu'on veut mesurer n'est pas la pose (215 ms pour 630 000
	# cellules, mesure) mais ce que Godot fait ENSUITE -- reconstruire les
	# octants et creer un corps de collision par cellule. Un chrono qui
	# n'entourerait que les set_cell_item annoncerait un chargement instantane
	# pendant que l'editeur est fige.
	var debut := Time.get_ticks_msec()
	_en_cours = true
	var index := 0
	var cellules := 0
	while index < colonnes.size():
		var debut_tranche := index
		var tranche := charger_tranche(
			grille, carte, colonnes, pose_sur, bloc, index, maxi(colonnes_par_frame, 1))
		index = tranche["index"]
		# Voir _colonnes_chargees : on retient ce qui a ETE TRAITE, pose ou non.
		# Une colonne traitee et restee vide est un trou legitime de la carte ;
		# une colonne jamais traitee ne doit pas etre ecrite du tout.
		for i in range(debut_tranche, index):
			_colonnes_chargees[colonnes[i]] = true
		cellules += tranche["cellules"]
		if index >= colonnes.size():
			break
		# Hors arbre, aucune frame ne viendra jamais : attendre la pendrait.
		if get_tree() == null:
			continue
		await get_tree().process_frame
		if not is_instance_valid(grille):
			push_warning("le terrain a disparu : chargement interrompu a %d colonnes" % index)
			break
	_en_cours = false

	# CE QUI A ETE POSE, jamais ce que `centre` vaut maintenant. Voir plus haut.
	centre_charge = pose_sur
	fenetre_chargee = true
	# La surveillance repart de ce que le chargement vient de poser, sinon elle
	# prendrait la pose elle-meme pour une sculpture a enregistrer.
	_cellules_vues = grille.get_used_cells().size()
	_immobile_depuis = -1.0
	var duree := Time.get_ticks_msec() - debut
	print("  %d cellules posees en %d ms (%.1f us par cellule)" % [
		cellules, duree,
		(float(duree) * 1000.0 / float(maxi(cellules, 1)))])
	if journal:
		print("  [sculpture] apres rechargement : %s ; une emprise = %d colonnes" % [
			emprise_lisible(grille), demi_fenetre * demi_fenetre * 4])

# VIDER INVALIDE LA FENETRE, et ce n'est pas une precaution de forme : un
# GridMap vide releve des colonnes VIDES partout, et l'enregistrer effacerait
# toute la fenetre dans la carte -- six cents metres de sculpture, en une case
# cochee, sans rien a l'ecran pour le montrer.
func _vider() -> void:
	var grille := Commun.terrain_frere(self)
	if grille == null:
		return
	var avant := grille.get_used_cells().size()
	grille.clear()
	fenetre_chargee = false
	_colonnes_chargees = {}
	_cellules_vues = -1
	_immobile_depuis = 0.0
	# LE GESTE DE FIN REND SA COLLISION AU TERRAIN. Vider d'abord, restaurer
	# ensuite : sur une grille deja vide, la bibliotheque de jeu ne coute rien.
	if bibliotheque_de_jeu != null:
		grille.mesh_library = bibliotheque_de_jeu
	print("fenetre videe : %d cellules retirees, bibliotheque de jeu rendue. La carte garde ce qui a ete enregistre ; recharger pour reprendre." % avant)

func _enregistrer() -> void:
	if _en_cours:
		push_warning("un transfert de fenetre est deja en cours : celui-ci est ignore")
		return
	var grille := Commun.terrain_frere(self)
	if grille == null:
		return
	if carte == null:
		push_error("outil_fenetre sans carte : rien ou ecrire")
		return
	# LE GARDE-FOU. Le GridMap porte le relief du centre CHARGE ; l'ecrire a un
	# autre centre le recopierait la-bas et laisserait l'original intact, sans
	# qu'aucune erreur ne se voie.
	if not fenetre_chargee:
		push_error("aucune fenetre chargee : charger d'abord, sinon le GridMap n'est rattache a aucun endroit de la carte")
		return
	if centre_charge != centre:
		push_error("la fenetre chargee est centree sur %v, le centre demande est %v : recharger, ou remettre le centre a %v" % [
			centre_charge, centre, centre_charge])
		return

	var changees := enregistrer_fenetre(
		grille, carte, centre, demi_fenetre, _colonnes_chargees)
	print("enregistrement de la fenetre centree sur %v : %d colonnes changees, %d sculptees dans la carte" % [
		centre, changees, carte.colonnes_sculptees()])

	if carte.resource_path.is_empty():
		push_warning("la carte n'a aucun chemin sur le disque : le relief n'est ecrit qu'en memoire")
		return
	var erreur := ResourceSaver.save(carte, carte.resource_path)
	if erreur != OK:
		push_error("ecriture de %s impossible (erreur %d)" % [carte.resource_path, erreur])
		return
	print("  ecrit : %s" % carte.resource_path)
