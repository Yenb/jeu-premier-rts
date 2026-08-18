extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_magie_perception.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « sensibilite_magique -- perception magique » : PREMIERE
# DEMONSTRATION REELLE du canal "magie" (data/canaux.json), meme mecanique
# EXACTE que le canal ouie/son_emis (scripts/perception.gd:
# _percevoir_propagation_obstacles, filtre de seuil deja PROUVE par
# scripts/banc_son.gd) -- seul ce qui change ici est le NOM de la propriete
# d'emission (force_magique au lieu de son_emis) et celui de l'obstacle
# (opacite au lieu de absorption_sonore), tous deux PILOTES PAR LA DONNEE
# (data/canaux.json:magie), jamais en dur.
#
# AUCUN MECANISME DU COEUR TOUCHE PAR CE FICHIER : perception.gd/charge.gd/
# etat_effectif.gd/objet.gd/monde.gd/banc_commun.gd restent inchanges. Le
# canal "magie" a ete rendu possible par un chantier SEPARE, anterieur et
# deja livre (« propriete_emission configurable par canal », voir
# scripts/perception.gd et docs/ETAT.md) -- ce fichier COMPOSE seulement :
# - Objet.fabriquer (INCHANGE) -- dix sources magiques REELLES (bois/pierre/
#   fer, data/materiaux.json, plus source_magique_demo et verre_demo, tous
#   deux deja au catalogue), fusionnant "force_magique" comme n'importe
#   quelle autre propriete immuable (meme patron que
#   banc_son.gd:fabriquer_sources pour "son_emis").
# - BancCommun.fabriquer_colon (INCHANGE) -- deux colons (mage/guerrier),
#   type partage "colon" (data/types.json), qui ne porte PAS "magie" dans sa
#   liste "canaux" par defaut (seuls vue/ouie/odorat/toucher/gout/
#   nociception y sont). fabriquer_colon_magie (CI-DESSOUS, propre a ce
#   banc) AJOUTE "magie" a cette liste et pose canaux_config.magie EN ENTIER
#   (portee/seuil, data/banc_magie_perception.json:colons.*.magie_config) --
#   pas une SURCHARGE par-dessus un defaut existant (aucun defaut n'existe
#   pour un canal absent du type partage), mais le meme geste de mutation
#   locale APRES fabrication que banc_son.gd:fabriquer_colon_son applique a
#   ouie_surcharge. objet.gd:fabriquer duplique deja chaque paquet herite
#   (.duplicate(true)) : muter colon.proprietes.canaux ici est donc sans
#   risque d'aliasing entre les deux colons.
# - Perception.percevoir (INCHANGE COTE SIGNATURE) -- appele CHAQUE TICK par
#   colon ; ce fichier isole ensuite les entrees captees par le canal MAGIE
#   precisement (captures_magie), puisque vue/odorat perçoivent aussi les
#   memes sources sans filtre d'intensite (aucune propriete
#   "irremplacable"/"notre_ouvrage"/etc. sur nos sources, mais la geometrie
#   seule suffirait a les capter par un autre canal).
#
# CHOIX D'OBSTACLE, documente ici comme demande par la tache : "opacite"
# (data/canaux.json:magie.propriete_obstacle) -- deja fusionnee et DORMANTE
# sur tout objet fabrique par composition (bois/pierre/fer valent toutes
# 1.0, voir data/proprietes_immuables_composition.json), jamais une
# propriete magique dediee a l'obstruction (aucune n'existe encore) : un mur
# opaque bloque le champ magique comme il bloquerait la vue. Consequence
# assumee : opacite valant 1.0 sur les trois materiaux reels du depot, tout
# obstacle bois/pierre/fer BLOQUE TOTALEMENT le champ (facteur 0.0), jamais
# une attenuation partielle comme absorption_sonore/ouie -- prouve par un
# test MECANISME dedie (voir test_banc_magie_perception.gd), pas par une
# demonstration visuelle separee (limite de perimetre assumee, la
# demonstration visuelle de ce banc porte sur le SEUIL, pas sur l'obstacle
# -- deja prouve generique par banc_occlusion.gd/banc_absorption_sonore.gd
# pour ouie).
#
# "sensibilite_magique" (data/materiaux.json, dormante) N'INTERVIENT PAS
# ICI -- decision Yael (chantier « sensibilite_magique -- perception
# magique ») : c'est un stat du RECEPTEUR (seuil de detection), jamais
# fusionnee, jamais lue. Le seuil reel vit sur le COLON
# (canaux_config.magie.seuil, magie_config dans la donnee de ce banc),
# jamais derive d'une propriete materiau. La SOURCE porte "force_magique"
# (intensite d'emission, role EMETTEUR) -- les deux roles sont
# INDEPENDANTS, jamais confondus (meme discipline que
# pouvoir_calorifique/inflammabilite).
#
# DEUX GRAPPES LOGIQUES, tres eloignees l'une de l'autre (meme patron que
# banc_son.gd:colon_humain/colon_chien) : mage entoure de six sources a
# distance ~300-1400 ; guerrier, quatre sources a distance 300. Meme portee
# (600.0) pour les deux colons, seul leur SEUIL diverge (0.02 pour le mage,
# 0.1 pour le guerrier) -- a distance 300 (facteur d'attenuation 0.5) :
# bois attenue 0.15, pierre 0.05, fer 0.025, source_magique_demo 0.45. Le
# mage (seuil 0.02) percoit les QUATRE (fer, pierre, bois, demo --
# 0.025/0.05/0.15/0.45 tous >= 0.02) ; le guerrier (seuil 0.1) ne percoit
# que les DEUX plus fortes (bois 0.15, demo 0.45 >= 0.1 ; pierre 0.05 et
# fer 0.025 < 0.1, ignorees). source_neutre_mage (verre_demo, force_magique
# absente -- 0.0 par defaut generique) reste a portee (distance ~354) mais
# n'est JAMAIS percue, quel que soit le seuil (0.0 < tout seuil strictement
# positif) -- preuve qu'une chose muette sur "force_magique" ne se fait
# jamais capter par accident. source_lointaine_mage (bois, distance ~1414 >
# portee 600) n'est JAMAIS percue non plus, mais pour une raison DIFFERENTE
# (hors de la geometrie meme, avant tout filtre de seuil) -- meme
# distinction que banc_son.gd:_mecanisme_hors_de_portee_aucune_source_captee.
# CES DISTANCES LOGIQUES NE CHANGENT PAS (chantier « rendu lisible », voir
# ci-dessous) -- le rendu, lui, place les objets ailleurs a l'ecran.
#
# CHANTIER « RENDU LISIBLE DE BANC_MAGIE_PERCEPTION » -- LA POSITION
# D'AFFICHAGE EST SEPAREE DE LA POSITION LOGIQUE. "position" (sur chaque
# source/colon, ci-dessus) reste EXACTEMENT ce que lisent
# Perception.percevoir/Monde -- aucune valeur de distance/seuil/
# force_magique ne bouge, verrouille par le meme test_banc_magie_
# perception.gd que la session precedente. "affichage" (NOUVEAU,
# data/banc_magie_perception.json) donne a chaque id une position ECRAN
# INDEPENDANTE : positions_affichage() la calcule une fois dans _ready --
# chaque colon a sa propre position d'affichage, chaque source de son
# cluster s'empile en COLONNE VERTICALE a cote de lui (decalage_colonne_x,
# ESPACEMENT_COLONNE entre deux sources consecutives), la source lointaine
# est placee isolement (affichage.isolees). Deux CARRES peuvent donc se
# superposer en LOGIQUE (perception) sans jamais se superposer a l'ECRAN.
# Nom AU-DESSUS du carre, valeur (force_magique pour une source, seuil pour
# un colon) EN DESSOUS -- sauf pour un colon dont le NOM reste au-dessus
# mais dont la valeur (seuil) descend SOUS le carre (remplace l'ancien
# texte "percoit: ...", desormais rendu par des LIGNES, voir
# _mettre_a_jour_lignes) : une source empile nom+valeur tous deux AU-DESSUS
# (aucun contenu sous son carre, pour ne jamais chevaucher le carre du
# voisin de colonne, voir decalage_nom_au_dessus/decalage_valeur_au_dessus
# -- l'ecart CONST=48px entre le haut d'un carre et le bas du bloc de
# labels du voisin au-dessus est INDEPENDANT du zoom, voir ces deux
# fonctions). Verifie a l'ecran par defaut (1152x648, _TAILLE_ECRAN_DEFAUT)
# avec les constantes ci-dessous : zoom obtenu ~0.88, marge label-a-label
# ~40px (> 30px demande) -- NON PROUVE pour une fenetre nettement plus
# petite, meme limite que toutes les autres tailles de police fixes en
# CanvasLayer de ce depot (voir banc_son.gd/banc_champ.gd).
#
# - Node (impur) : _ready charge donnees/catalogues, fabrique sources et
#   colons (logique INCHANGEE), calcule les positions d'affichage, cree le
#   rendu. _process recalcule sources_percues(...) par colon chaque tick
#   (logique INCHANGEE), logue au CHANGEMENT seulement, met a jour le texte
#   de seuil et les lignes de perception.
# - Fonctions statiques (pures, testables headless, voir
#   scripts/test_banc_magie_perception.gd) : fabriquer_sources/
#   fabriquer_colon_magie/captures_magie/sources_percues (INCHANGEES,
#   mecanisme) ; position_colonne/positions_affichage/
#   decalage_valeur_au_dessus/decalage_nom_au_dessus/decalage_dessous/
#   texte_valeur_source/texte_valeur_colon/zoom_pour_cadrage/
#   centre_de_cadrage (NOUVELLES ou ajustees, rendu pur).

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const TAILLE := 48.0
const TAILLE_POLICE_NOM := 20
const TAILLE_POLICE_VALEUR := 12
const LARGEUR_LABEL := 220.0
const MARGE_LABEL := 6.0
const RESERVE_LIGNE := 4.0
const GAP_INTERNE := 2.0
const ESPACEMENT_COLONNE := 100.0
const LARGEUR_LIGNE_PERCEPTION := 3.0
const MARGE_CADRAGE := 120.0
const ZOOM_MIN := 0.05
const ZOOM_MAX := 2.0
const _TAILLE_ECRAN_DEFAUT := Vector2(1152.0, 648.0)

var _config: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _monde := Monde.new()
var _sources: Array = []
var _colons: Array = []
var _types_sources: Dictionary = {}
var _positions_affichage: Dictionary = {}
var _noeuds: Dictionary = {}
var _labels_nom: Dictionary = {}
var _labels_valeur: Dictionary = {}
var _lignes_perception: Dictionary = {}
var _captures_precedentes: Dictionary = {}
var _temps: float = 0.0

var _couche_ui: CanvasLayer
var _camera: Camera2D
var _zoom: float = 1.0
var _taille_ecran: Vector2 = _TAILLE_ECRAN_DEFAUT

func _ready() -> void:
	_config = _charger_json("res://data/banc_magie_perception.json")
	var materiaux: Dictionary = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var types_partages: Dictionary = _charger_json("res://data/types.json")
	var catalogue_types: Dictionary = _config.get("types", {}).duplicate(true)
	catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	catalogue_types["percevant"] = types_partages.get("percevant", {})
	catalogue_types["agent"] = types_partages.get("agent", {})
	catalogue_types["colon"] = types_partages.get("colon", {})
	_catalogue_canaux = _charger_json("res://data/canaux.json")

	var declarations_sources: Array = _config.get("sources", [])
	_sources = fabriquer_sources(declarations_sources, catalogue_types, materiaux, proprietes_immuables)
	for decl in declarations_sources:
		_types_sources[decl.id] = decl.type

	_colons = fabriquer_colons(_config.get("colons", {}), catalogue_types)

	_positions_affichage = positions_affichage(_config.get("affichage", {}), ESPACEMENT_COLONNE)

	_couche_ui = CanvasLayer.new()
	add_child(_couche_ui)
	_taille_ecran = _taille_ecran_reelle()
	_poser_camera(_positions_affichage.values())

	for source in _sources:
		_monde.ajouter(source, _types_sources[source.id], source.position)
		var pos_aff: Vector2 = _positions_affichage.get(source.id, Vector2(source.position.x, source.position.y))
		_noeuds[source.id] = _creer_rendu(pos_aff, _couleur_de(_types_sources[source.id]))
		_labels_nom[source.id] = _creer_label(pos_aff, TAILLE_POLICE_NOM, Color.WHITE, decalage_nom_au_dessus(_zoom))
		_labels_nom[source.id].text = source.id
		_labels_valeur[source.id] = _creer_label(pos_aff, TAILLE_POLICE_VALEUR, Color.WHITE, decalage_valeur_au_dessus(_zoom))
		_labels_valeur[source.id].text = texte_valeur_source(source.proprietes)

	for colon in _colons:
		_monde.ajouter(colon, "colon", colon.position)
		var couleur: Color = _couleur_de(colon.id)
		var pos_aff_colon: Vector2 = _positions_affichage.get(colon.id, Vector2(colon.position.x, colon.position.y))
		_noeuds[colon.id] = _creer_rendu(pos_aff_colon, couleur)
		_labels_nom[colon.id] = _creer_label(pos_aff_colon, TAILLE_POLICE_NOM, couleur, decalage_nom_au_dessus(_zoom))
		_labels_nom[colon.id].text = colon.id
		_labels_valeur[colon.id] = _creer_label(pos_aff_colon, TAILLE_POLICE_VALEUR, couleur, decalage_dessous(_zoom))
		_lignes_perception[colon.id] = {}

	_creer_legende()

# ---- Boucle ----

func _process(delta: float) -> void:
	_temps += delta

	for colon in _colons:
		var magie_config: Dictionary = colon.proprietes.canaux_config.magie
		var ids: Array = sources_percues(colon, _monde, _catalogue_canaux)
		ids.sort()
		if ids != _captures_precedentes.get(colon.id, []):
			_captures_precedentes[colon.id] = ids
			print(ligne_log(_temps, colon.id, ids))
		_labels_valeur[colon.id].text = texte_valeur_colon(magie_config.get("seuil", 0.0))
		_mettre_a_jour_lignes(colon.id, ids)

# Cree/retire les Line2D (couleur du colon) entre lui et chaque source
# PERCUE ce tick -- jamais vers une source non percue. Impure (Node),
# jamais testee headless (meme statut que le reste du rendu de ce fichier).
func _mettre_a_jour_lignes(colon_id: String, ids_percus: Array) -> void:
	var couleur: Color = _couleur_de(colon_id)
	var actuelles: Dictionary = _lignes_perception[colon_id]
	for id in ids_percus:
		if not actuelles.has(id):
			var ligne := Line2D.new()
			ligne.width = LARGEUR_LIGNE_PERCEPTION
			ligne.default_color = couleur
			ligne.points = PackedVector2Array([_positions_affichage[colon_id], _positions_affichage[id]])
			add_child(ligne)
			actuelles[id] = ligne
	var a_retirer: Array = []
	for id in actuelles:
		if not (id in ids_percus):
			actuelles[id].queue_free()
			a_retirer.append(id)
	for id in a_retirer:
		actuelles.erase(id)

# ---- Fonctions statiques, pures, testables (mecanisme, INCHANGEES) ----

# Meme patron que banc_son.gd:fabriquer_sources -- une source REELLE par
# declaration (composition fusionnee via Objet.fabriquer), "type" resolu
# contre catalogue_types (data/banc_magie_perception.json:types, fusionne
# par l'appelant avec les paquets partages).
static func fabriquer_sources(declarations: Array, catalogue_types: Dictionary, materiaux: Dictionary, proprietes_immuables: Array) -> Array:
	var sources: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var source := Objet.fabriquer(decl.id, decl.type, Vector3(pos[0], pos[1], pos[2]), catalogue_types, materiaux, proprietes_immuables)
		if source.is_empty():
			continue
		sources.append(source)
	return sources

static func fabriquer_colons(declarations: Dictionary, catalogue_types: Dictionary) -> Array:
	var colons: Array = []
	for nom in declarations:
		colons.append(fabriquer_colon_magie(nom, declarations[nom], catalogue_types))
	return colons

# Fabrique un colon partage (BancCommun.fabriquer_colon, INCHANGE) puis
# AJOUTE "magie" a sa liste "canaux" (absente du type partage "colon") et
# pose canaux_config.magie EN ENTIER depuis decl.magie_config -- jamais un
# mecanisme du coeur qui la lirait pour ce banc, meme geste que la
# surcharge locale de ouie dans banc_son.gd:fabriquer_colon_son. objet.gd:
# fabriquer duplique deja "canaux" par colon (.duplicate(true) sur chaque
# paquet herite) : append() ici ne peut donc jamais contaminer un autre
# colon fabrique par le meme catalogue_types.
static func fabriquer_colon_magie(nom: String, decl: Dictionary, catalogue_types: Dictionary) -> Dictionary:
	var colon := BancCommun.fabriquer_colon(nom, "colon", decl, catalogue_types)
	colon.proprietes.canaux.append("magie")
	colon.proprietes.canaux_config["magie"] = decl.get("magie_config", {})
	return colon

# Parmi tout ce que Perception.percevoir rend (tous canaux confondus --
# vue/odorat captent aussi geometriquement nos sources, sans filtre
# d'intensite), ne retient que les entrees captees par le canal "magie"
# precisement -- necessaire pour observer le filtre de seuil isole des
# autres canaux (meme role que banc_son.gd:captures_ouie).
static func captures_magie(colon: Dictionary, monde, catalogue_canaux: Dictionary) -> Array:
	var perceptions: Array = Perception.percevoir(colon, monde, catalogue_canaux)
	var resultat: Array = []
	for entree in perceptions:
		if "magie" in entree.canaux:
			resultat.append(entree)
	return resultat

static func ids_de(perceptions: Array) -> Array:
	var ids: Array = []
	for entree in perceptions:
		ids.append(entree.chose.id)
	return ids

# Point d'entree unique : rend les ids des sources magiques reellement
# percues par ce colon, ce tick -- le seuil est deja applique par
# perception.gd (canal magie), aucun second filtre propre a ce banc.
static func sources_percues(colon: Dictionary, monde, catalogue_canaux: Dictionary) -> Array:
	return ids_de(captures_magie(colon, monde, catalogue_canaux))

# ---- Fonctions statiques, pures, testables (RENDU, chantier « rendu lisible ») ----

# Empile "ids" (ORDRE de la liste = ordre visuel, haut vers bas) en colonne
# verticale CENTREE sur centre.y, espacee de "espacement" entre deux
# consecutives, decalee de "decalage_x" par rapport a centre.x -- PURE,
# ignore tout ce qui n'est pas geometrique (jamais lue par le mecanisme,
# uniquement par positions_affichage ci-dessous).
static func position_colonne(centre: Vector2, decalage_x: float, ids: Array, espacement: float) -> Dictionary:
	var resultat: Dictionary = {}
	var n: int = ids.size()
	for i in range(n):
		var y: float = centre.y + (float(i) - float(n - 1) / 2.0) * espacement
		resultat[ids[i]] = Vector2(centre.x + decalage_x, y)
	return resultat

# Compose la position d'AFFICHAGE de chaque colon, chaque source de sa
# colonne (position_colonne ci-dessus) et chaque source isolee
# (affichage.isolees) -- lit UNIQUEMENT data/banc_magie_perception.json:
# affichage, jamais "sources"/"colons.*.position" (la position LOGIQUE,
# lue ailleurs par fabriquer_sources/fabriquer_colon_magie, jamais ici).
static func positions_affichage(affichage: Dictionary, espacement: float) -> Dictionary:
	var resultat: Dictionary = {}
	for colon_id in affichage.get("colons", {}):
		var decl: Dictionary = affichage.colons[colon_id]
		var pos: Array = decl.position
		var centre := Vector2(pos[0], pos[1])
		resultat[colon_id] = centre
		var decalage_x: float = decl.get("decalage_colonne_x", 0.0)
		var ids: Array = decl.get("sources", [])
		var colonne: Dictionary = position_colonne(centre, decalage_x, ids, espacement)
		for id in colonne:
			resultat[id] = colonne[id]
	for id in affichage.get("isolees", {}):
		var p: Array = affichage.isolees[id]
		resultat[id] = Vector2(p[0], p[1])
	return resultat

# Decalage Y (ecran, CanvasLayer) du bas du label de VALEUR au-dessus d'un
# carre de taille TAILLE zoome par "zoom" -- MARGE_LABEL separe le haut du
# carre du bas du label, RESERVE_LIGNE approxime la hauteur d'une ligne de
# police TAILLE_POLICE_VALEUR (police fixe en pixels ecran, jamais zoomee,
# voir _creer_label). Racine des trois autres decalages ci-dessous.
static func decalage_valeur_au_dessus(zoom: float) -> float:
	return -(TAILLE / 2.0 * zoom + MARGE_LABEL) - (float(TAILLE_POLICE_VALEUR) + RESERVE_LIGNE)

# Decalage Y du bas du label de NOM, empile juste au-dessus du label de
# VALEUR (GAP_INTERNE entre les deux) -- ensemble, nom+valeur forment un
# bloc UNIQUE au-dessus du carre (patron des SOURCES ; un COLON n'utilise
# que decalage_nom_au_dessus ici, sa valeur -- le seuil -- descend SOUS le
# carre via decalage_dessous, voir _ready).
static func decalage_nom_au_dessus(zoom: float) -> float:
	return decalage_valeur_au_dessus(zoom) - GAP_INTERNE - (float(TAILLE_POLICE_NOM) + RESERVE_LIGNE)

# Decalage Y du haut d'un label EN DESSOUS d'un carre -- utilise pour le
# seuil du colon (remplace l'ancien texte "percoit: ...", desormais rendu
# par des lignes, voir _mettre_a_jour_lignes).
static func decalage_dessous(zoom: float) -> float:
	return TAILLE / 2.0 * zoom + MARGE_LABEL

static func texte_valeur_source(proprietes: Dictionary) -> String:
	return "force_magique=%.2f" % proprietes.get("force_magique", 0.0)

static func texte_valeur_colon(seuil: float) -> String:
	return "seuil=%.2f" % seuil

static func ligne_log(t: float, colon_id: String, ids: Array) -> String:
	var percu: String = ", ".join(ids) if not ids.is_empty() else "(rien)"
	return "t=%.1f %s percoit : %s" % [t, colon_id, percu]

# Zoom Camera2D qui fait tenir TOUS les points dans une fenetre
# `taille_ecran`, chacun entoure d'une `marge` -- meme formule que
# banc_son.gd:zoom_pour_cadrage.
static func zoom_pour_cadrage(points: Array, marge: float, taille_ecran: Vector2) -> float:
	if points.size() < 2:
		return ZOOM_MAX
	var mini: Vector2 = Vector2(points[0].x, points[0].y)
	var maxi: Vector2 = mini
	for p in points:
		mini.x = min(mini.x, p.x)
		mini.y = min(mini.y, p.y)
		maxi.x = max(maxi.x, p.x)
		maxi.y = max(maxi.y, p.y)
	var largeur_monde: float = max(maxi.x - mini.x + marge * 2.0, 1.0)
	var hauteur_monde: float = max(maxi.y - mini.y + marge * 2.0, 1.0)
	var zoom: float = min(taille_ecran.x / largeur_monde, taille_ecran.y / hauteur_monde)
	return clamp(zoom, ZOOM_MIN, ZOOM_MAX)

# Centre (Vector2) du meme ensemble de points -- meme formule que
# banc_son.gd:centre_de_cadrage.
static func centre_de_cadrage(points: Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var mini: Vector2 = Vector2(points[0].x, points[0].y)
	var maxi: Vector2 = mini
	for p in points:
		mini.x = min(mini.x, p.x)
		mini.y = min(mini.y, p.y)
		maxi.x = max(maxi.x, p.x)
		maxi.y = max(maxi.y, p.y)
	return (mini + maxi) / 2.0

# ---- Rendu (impur, Node) -- aucune decision, seulement construction des
# noeuds et de la camera.

func _couleur_de(nom: String) -> Color:
	var rgb: Array = _config.get("couleurs_types", {}).get(nom, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _creer_rendu(position_affichage: Vector2, couleur: Color) -> ColorRect:
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.color = couleur
	noeud.position = position_affichage - noeud.size / 2.0
	add_child(noeud)
	return noeud

func _creer_label(position_affichage: Vector2, taille_police: int, couleur: Color, decalage_y: float) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(LARGEUR_LABEL, 0.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", taille_police)
	label.add_theme_color_override("font_color", couleur)
	var ecran: Vector2 = _monde_vers_ecran(position_affichage)
	label.position = ecran + Vector2(-LARGEUR_LABEL / 2.0, decalage_y)
	_couche_ui.add_child(label)
	return label

# Legende fixe (CanvasLayer, coin haut-gauche) -- deux lignes, couleur de
# chaque colon (jaune mage / cyan guerrier, data/banc_magie_perception.json:
# couleurs_types), jamais recalculee (statique, posee une fois en _ready).
func _creer_legende() -> void:
	var legende_mage := Label.new()
	legende_mage.text = "— mage (seuil bas, perçoit les faibles)"
	legende_mage.add_theme_color_override("font_color", _couleur_de("mage"))
	legende_mage.position = Vector2(10.0, 10.0)
	_couche_ui.add_child(legende_mage)

	var legende_guerrier := Label.new()
	legende_guerrier.text = "— guerrier (seuil haut, ne perçoit que les fortes)"
	legende_guerrier.add_theme_color_override("font_color", _couleur_de("guerrier"))
	legende_guerrier.position = Vector2(10.0, 32.0)
	_couche_ui.add_child(legende_guerrier)

func _monde_vers_ecran(position_affichage: Vector2) -> Vector2:
	return (position_affichage - _camera.position) * _zoom + _taille_ecran / 2.0

func _poser_camera(points: Array) -> void:
	_zoom = zoom_pour_cadrage(points, MARGE_CADRAGE, _taille_ecran)
	var centre := centre_de_cadrage(points)
	_camera = Camera2D.new()
	_camera.position = centre
	_camera.zoom = Vector2(_zoom, _zoom)
	_camera.enabled = true
	add_child(_camera)

func _taille_ecran_reelle() -> Vector2:
	var taille: Vector2 = get_viewport().get_visible_rect().size
	if taille.x <= 0.0 or taille.y <= 0.0:
		return _TAILLE_ECRAN_DEFAUT
	return taille

func _charger_json(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
