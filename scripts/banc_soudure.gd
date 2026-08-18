extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_soudure.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). PREMIERE DEMONSTRATION REELLE du chantier "soudabilite" (voir
# audit_soudabilite.md) : scripts/soudure.gd (nouveau) joue avec
# temperature.gd/seuil_etat.gd/charge.gd (tous trois deja fermes, NON
# TOUCHES) pour la premiere fois -- deux blocs de fer chauffes au contact
# fusionnent en un seul objet composite, sans qu'aucune fusion ne soit
# ecrite a la main dans ce fichier.
#
# INTERACTIF (refonte) : le clic gauche PLACE ET ACTIVE la source de
# chaleur A LA POSITION DU CURSEUR, tant qu'il reste maintenu -- meme
# patron que banc_temperature.gd (Input lu dans _process, jamais dans un
# mecanisme ; la logique qui en resulte sort en fonction statique
# testable, sources_du_tick ci-dessous) mais adapte a la SOURIS (position
# vivante + etat maintenu/relache) plutot qu'au CLAVIER (deplacement d'un
# objet). Relacher le clic vide `sources` -- Temperature.avancer (NON
# TOUCHE) fait alors redescendre tout objet expose vers l'ambiante par la
# MEME loi de Newton, aucun cas special ecrit ici. `BancChangementEtat`
# n'est plus reutilise (l'ancienne rampe automatique par le temps n'a plus
# de sens des que la chaleur vient du joueur) -- sources_du_tick est un
# COPIER-PATRON de sa forme (meme doctrine que temperature.gd vs vent.gd,
# "copier-patron jamais copier-code"), pas un import.
#
# DEUX ETAGES, jamais confondus (voir data/soudure.json, scripts/soudure.gd) :
# - DETECTION, reversible : `Charge.avancer` (NON TOUCHE) tel quel, UN APPEL
#   PAR OBJET CIBLE (meme patron que scripts/banc_humidite.gd -- charge.gd
#   n'a lui-meme aucune notion de "qui est mon voisin", ce cablage construit
#   les causes). Un voisin compte comme cause si (a) il est a portee via le
#   canal charge.gd lui-meme (portee_charge), (b) il porte
#   `proprietes.soudabilite > 0` (fusionnee a la fabrication, voir
#   data/proprietes_immuables_composition.json), (c) il porte l'etat
#   "chaud" dans `etats_actifs` -- pose par scripts/seuil_etat.gd
#   (data/seuils_etat.json:chaud, seuil universel 150.0, catalogue PARTAGE,
#   NON TOUCHE) une fois sa temperature (scripts/temperature.gd, NON
#   TOUCHE) franchie. Reversible : refroidir ou s'eloigner retire le
#   marqueur exactement comme charge.gd le fait deja pour peur/contagion/
#   humidite -- aucune ligne neuve dans charge.gd.
# - DECLENCHEMENT, ONE-SHOT : des que deux objets portent SIMULTANEMENT le
#   marqueur ET sont en contact reel, `Soudure.souder` (scripts/soudure.gd)
#   s'execute UNE FOIS -- le second objet est alors VIDE
#   (`proprietes.clear()`), la condition ne peut plus jamais se representer
#   pour cette paire (l'un des deux n'existe plus).
#
# LE BOIS NE SE SOUDE JAMAIS : sa `soudabilite` (data/materiaux.json) est
# 0.0 -- ce cablage ne fait JAMAIS avancer son canal `etats.soudure`
# (`_process` filtre sur `est_soudable(objet.proprietes)` AVANT d'appeler
# `Charge.avancer`), quelle que soit sa chaleur ou sa proximite : le rayon
# de la source couvre les trois objets a la fois si le curseur est place
# entre eux, pour prouver que seule la matiere l'exclut, jamais la mise en
# scene.
#
# GHOST APRES SOUDURE, CONSEQUENCE OBSERVEE DU MANQUE DEJA SIGNALE
# (audit_soudabilite.md §3 point 3, CARTE.md §6) : ce depot n'a AUCUNE
# fonction de retrait d'objet (scripts/monde.gd) -- l'objet absorbe reste
# dans `_monde` pour toujours, `proprietes` entierement vide. Consequence
# concrete : `temperature.gd:avancer` traite `proprietes.temperature`
# comme STRUCTURELLE (push_error si absente) -- passer un fantome tel quel
# a chaque tick aurait donc alarme INDEFINIMENT apres la premiere soudure.
# Corrige ICI, au cablage, jamais dans temperature.gd/seuil_etat.gd (non
# touches) : `_monde_vivant()` filtre les fantomes AVANT tout appel a
# `Temperature.avancer`/`SeuilEtat.avancer`. `Charge.avancer`/
# `causes_de_soudure`/`paires_pretes` n'ont besoin d'AUCUN filtre
# equivalent : ils testent deja `proprietes.is_empty()` eux-memes (ce
# fichier), ou re-testent une propriete par `.get(cle, defaut)` (charge.gd)
# -- seule une propriete STRUCTURELLE (comme `temperature`) exige ce filtre
# en amont.
#
# DEUXIEME FANTOME (composite sans temperature) : `Soudure.souder` (NON
# TOUCHE) vide puis REMPLACE ENTIEREMENT les proprietes du survivant par
# `fabriquer_composite`, qui appelle `Objet.fabriquer` sur une table
# synthetique `{"composition": ...}` SANS "herite" -- le composite ne
# porte donc plus "temperature" ni son canal `etats.soudure`, exactement
# comme un objet de ce banc juste apres sa fabrication initiale en
# _ready(). Corrige AU CABLAGE seul (`_poser_etat_initial`, factorisee
# entre `_ready()` et le point d'appel post-soudure de `_process`) :
# `_process` capture la temperature du survivant AVANT d'appeler
# `Soudure.souder`, puis la reapplique juste apres succes -- un composite
# ne "renait" pas froid, il garde sa propre derniere temperature connue.
#
# LABELS : un SEUL Label, fixe a l'ecran (CanvasLayer, meme patron que
# banc_temperature.gd/banc_vent.gd -- jamais un Label par objet en
# espace-monde). fer_0/fer_1 doivent rester a PORTEE DE CONTACT l'un de
# l'autre pour que la demonstration marche (voir data/banc_soudure.json) --
# les eloigner horizontalement pour faire de la place a des labels flottants
# aurait casse le chantier lui-meme. Chaque bloc de texte (id, statut,
# temperature, etats, charge de soudure, masse -- `texte_label`) est donc
# simplement empile verticalement dans le MEME controle par Godot, qui ne
# les superpose jamais -- aucune position a calculer, aucun chevauchement
# possible quelle que soit la proximite des carres. Les carres eux-memes
# restent en espace-monde (ils ne se chevauchaient pas, seuls des labels
# auraient pu l'etre).
#
# STATUT, DERIVE JAMAIS DECLARE (meme doctrine que "solide = absence de
# liquide/gaz", data/seuils_etat.json) : `statut_pour_objet` ne lit qu'un
# fantome (proprietes vide), une composition a plusieurs elements (une
# soudure a eu lieu -- "soude", jamais un drapeau pose a la main par ce
# chantier) ou le marqueur de charge -- rien de plus, aucune nouvelle
# propriete sur le monde.
#
# LIMITE STRICTE (rappel du chantier) : ce fichier cable UNIQUEMENT ce
# banc -- aucun mecanisme neuf au-dela de scripts/soudure.gd, aucune
# extension du coeur. charge.gd/objet.gd/produit.gd/extinction.gd/
# temperature.gd/seuil_etat.gd et tout autre banc restent intouches.

const Objet = preload("res://scripts/objet.gd")
const Temperature = preload("res://scripts/temperature.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Charge = preload("res://scripts/charge.gd")
const Soudure = preload("res://scripts/soudure.gd")
const Portee = preload("res://scripts/portee.gd")

const TAILLE := 35.0
const TAILLE_CURSEUR := 50.0

var _monde: Array = []
var _noeuds: Array = []
var _label: Label
var _noeud_curseur: ColorRect

var _materiaux: Dictionary = {}
var _proprietes_immuables: Array = []
var _cat_temperature: Dictionary = {}
var _cat_seuils: Dictionary = {}

var _portee_contact := 0.0
var _seuil_charge := 0.0
var _taux_decroissance := 0.0
var _nom_marqueur := ""

var _rayon_source := 0.0
var _temperature_source := 0.0
var _force_source := 1.0
var _ambiante := 20.0

var _couleur_fer := Color(0.55, 0.55, 0.58)
var _couleur_bois := Color(0.55, 0.35, 0.15)
var _couleur_chaud_tint := Color(0.85, 0.45, 0.1)
var _couleur_pret_tint := Color(0.95, 0.85, 0.1)
var _couleur_curseur := Color(0.95, 0.55, 0.1, 0.35)

var _temps := 0.0

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_soudure.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_proprietes_immuables = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	_cat_temperature = _charger_json("res://data/temperature.json")
	_cat_seuils = _charger_json("res://data/seuils_etat.json")
	var cat_soudure := _charger_json("res://data/soudure.json")

	var config_soudure: Dictionary = cat_soudure.defaut
	_portee_contact = config_soudure.portee_contact
	_seuil_charge = config_soudure.seuil_charge
	_taux_decroissance = config_soudure.taux_decroissance
	_nom_marqueur = config_soudure.nom_marqueur

	var temperature_initiale: float = donnees.get("temperature_initiale", 20.0)
	for decl in donnees.objets:
		var pos_arr: Array = decl.position
		var position := Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
		var table := {decl.id: {"composition": decl.composition}}
		var objet := Objet.fabriquer(decl.id, decl.id, position, table, _materiaux, _proprietes_immuables)
		if objet.is_empty():
			push_error("banc_soudure.gd : fabrication refusee pour '%s'" % decl.id)
			continue
		poser_etat_initial(objet, temperature_initiale, _nom_marqueur, _seuil_charge, _portee_contact, _taux_decroissance)
		_monde.append(objet)

	var decl_source: Dictionary = donnees.source
	_rayon_source = decl_source.rayon
	_temperature_source = decl_source.temperature
	_force_source = decl_source.force
	_ambiante = _cat_temperature.defaut.ambiante

	var decl_couleurs: Dictionary = donnees.get("couleurs", {})
	_couleur_fer = _couleur_depuis_array(decl_couleurs.get("fer", [0.55, 0.55, 0.58]))
	_couleur_bois = _couleur_depuis_array(decl_couleurs.get("bois", [0.55, 0.35, 0.15]))
	_couleur_chaud_tint = _couleur_depuis_array(decl_couleurs.get("chaud_tint", [0.85, 0.45, 0.1]))
	_couleur_pret_tint = _couleur_depuis_array(decl_couleurs.get("pret_tint", [0.95, 0.85, 0.1]))
	_couleur_curseur = _couleur_depuis_array(decl_couleurs.get("curseur", [0.95, 0.55, 0.1, 0.35]))

	for objet in _monde:
		_noeuds.append(_dessiner_carre(objet.position, _couleur_fer))

	_noeud_curseur = _dessiner_carre(Vector3.ZERO, _couleur_curseur, TAILLE_CURSEUR)
	_noeud_curseur.visible = false

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label = Label.new()
	_label.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label)

	var decl_camera: Dictionary = donnees.get("camera", {})
	var pos_camera: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos_camera[0], pos_camera[1])
	camera.zoom = Vector2(decl_camera.get("zoom", 1.0), decl_camera.get("zoom", 1.0))
	camera.enabled = true
	add_child(camera)

	_actualiser_rendu(false, Vector3.ZERO)

func _process(delta: float) -> void:
	_temps += delta

	var chauffe: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var position_curseur := _position_monde_du_curseur()
	var sources := sources_du_tick(chauffe, position_curseur, _rayon_source, _temperature_source, _force_source)

	var monde_vivant := _monde_vivant()
	Temperature.avancer(monde_vivant, sources, delta, _cat_temperature)
	var bascules_etat: Array = SeuilEtat.avancer(monde_vivant, _cat_seuils)
	for id in bascules_etat:
		var objet := _par_id(id)
		if not objet.is_empty():
			print(ligne_bascule_etat(_temps, id, objet.proprietes.get("etats_actifs", [])))

	for objet in _monde:
		if objet.proprietes.is_empty():
			continue
		if not est_soudable(objet.proprietes):
			continue
		var causes := causes_de_soudure(objet, _monde)
		var bascules_charge: Array = Charge.avancer([objet], causes, delta)
		for id in bascules_charge:
			print(ligne_bascule_charge(_temps, id, objet.proprietes.get(_nom_marqueur, false)))

	for paire in paires_pretes(_monde, _nom_marqueur, _portee_contact):
		var a: Dictionary = paire.a
		var b: Dictionary = paire.b
		if a.proprietes.is_empty() or b.proprietes.is_empty():
			continue
		var masse_a: float = a.proprietes.masse
		var masse_b: float = b.proprietes.masse
		var temperature_avant: float = a.proprietes.get("temperature", _ambiante)
		var id_b: String = b.id
		if Soudure.souder(a, b, _materiaux, _proprietes_immuables):
			poser_etat_initial(a, temperature_avant, _nom_marqueur, _seuil_charge, _portee_contact, _taux_decroissance)
			print(ligne_soudure(_temps, a.id, id_b, masse_a, masse_b, a.proprietes.masse))
			print(ligne_fantome(_temps, id_b))

	_actualiser_rendu(chauffe, position_curseur)

# ---- Fonctions statiques, pures, testables ----

# Une chose compte comme SOUDABLE si sa soudabilite (fusionnee a la
# fabrication depuis data/materiaux.json, voir data/
# proprietes_immuables_composition.json) est strictement positive -- une
# fiche sans la propriete (jamais le cas ici, bois la porte explicitement a
# 0.0) contribuerait 0.0, meme resultat.
static func est_soudable(proprietes: Dictionary) -> bool:
	return float(proprietes.get("soudabilite", 0.0)) > 0.0

# Construit les CAUSES (forme charge.gd : Array de { position }) pour UN
# objet cible -- un voisin compte si (b) il est soudable ET (c) il porte
# "chaud". La portee (a) n'est JAMAIS testee ici : c'est le role de
# charge.gd lui-meme (canal.portee_charge), cette fonction ne fait que
# LISTER des candidats, jamais filtrer par distance -- meme division du
# travail que banc_charge.gd:causes_de/banc_contagion.gd:causes_de_attache.
#
# GARDE "SOI-MEME CHAUD" (bug corrige, trouve a l'ecran -- "la charge du
# deuxieme fer s'arrete") : sans cette garde, la charge d'un objet montait
# des qu'un VOISIN etait chaud, MEME SI L'OBJET LUI-MEME etait encore
# froid -- et inversement, un objet deja chaud voyait SA PROPRE charge
# geler tant que son voisin n'avait pas encore franchi le seuil. Resultat
# observe : selon la ou le joueur pointait le curseur, l'un des deux
# semblait "bloque" pendant que l'autre progressait déjà, sans aucun lien
# avec sa propre temperature. Corrige en exigeant QUE L'OBJET LUI-MEME
# soit deja chaud avant meme de chercher un voisin -- rend [] sinon,
# charge.gd (NON TOUCHE) decroit alors normalement (aucune cause), meme
# effet reversible que pour un voisin qui refroidit. Les DEUX objets
# doivent donc etre chauds SIMULTANEMENT pour que leurs deux charges
# progressent ensemble -- coherent avec "deux objets chauds au contact
# soudent", jamais un seul.
static func causes_de_soudure(objet: Dictionary, monde: Array) -> Array:
	if not objet.proprietes.get("etats_actifs", []).has("chaud"):
		return []
	var causes: Array = []
	for autre in monde:
		if autre.id == objet.id:
			continue
		if autre.proprietes.is_empty():
			continue
		if not est_soudable(autre.proprietes):
			continue
		if not autre.proprietes.get("etats_actifs", []).has("chaud"):
			continue
		causes.append({"position": autre.position})
	return causes

# Toutes les PAIRES d'objets porteurs SIMULTANEMENT de "nom_marqueur" ET en
# contact reel (meme portee que la detection, "portee_contact") -- ce que
# scripts/soudure.gd doit fusionner ce tick. Rend des REFERENCES (jamais
# des copies) pour que l'appelant puisse muter directement via
# Soudure.souder. Un fantome (proprietes vide, deja absorbe plus tot dans
# le meme balayage) est ignore.
static func paires_pretes(monde: Array, nom_marqueur: String, portee_contact: float) -> Array:
	var paires: Array = []
	for i in range(monde.size()):
		for j in range(i + 1, monde.size()):
			var a: Dictionary = monde[i]
			var b: Dictionary = monde[j]
			if a.proprietes.is_empty() or b.proprietes.is_empty():
				continue
			if not a.proprietes.get(nom_marqueur, false) or not b.proprietes.get(nom_marqueur, false):
				continue
			if not Portee.en_portee(a.position, b.position, portee_contact):
				continue
			paires.append({"a": a, "b": b})
	return paires

# La source de ce tick, dans la forme attendue par temperature.gd:locale/
# avancer -- construite ICI, jamais par le mecanisme. "chauffe" (deja lu
# par l'appelant, jamais Input directement ici -- meme discipline que
# banc_temperature.gd:deplacement_clavier) decide tout : relache, la
# source DISPARAIT du tableau (Array vide), les objets retombent vers
# l'ambiante par la MEME loi de Newton que temperature.gd applique deja
# loin de toute source, aucun cas special.
static func sources_du_tick(chauffe: bool, position: Vector3, rayon: float, temperature: float, force: float) -> Array:
	if not chauffe:
		return []
	return [{"position": position, "rayon": rayon, "temperature": temperature, "force": force}]

# STATUT affiche, jamais un drapeau pose sur le monde -- voir en-tete.
# "fantome" prime sur tout (proprietes vide, plus rien d'autre a lire) ;
# "soude" se lit sur la composition elle-meme (plusieurs elements = une
# fusion a eu lieu, scripts/soudure.gd:fabriquer_composite concatene deux
# compositions reelles) ; "pret_a_souder" lit le marqueur pose par
# charge.gd ; sinon "intact".
static func statut_pour_objet(proprietes: Dictionary, nom_marqueur: String) -> String:
	if proprietes.is_empty():
		return "fantome"
	if proprietes.get("composition", []).size() > 1:
		return "soude"
	if proprietes.get(nom_marqueur, false):
		return "pret_a_souder"
	return "intact"

static func couleur_pour_objet(proprietes: Dictionary, couleur_fer: Color, couleur_bois: Color, couleur_chaud_tint: Color, couleur_pret_tint: Color) -> Color:
	var composition: Array = proprietes.get("composition", [])
	var materiau: String = String(composition[0].get("materiau", "")) if not composition.is_empty() else ""
	var base: Color = couleur_bois if materiau == "bois" else couleur_fer
	var etats: Array = proprietes.get("etats_actifs", [])
	if etats.has("chaud"):
		base = base.lerp(couleur_chaud_tint, 0.6)
	return base.lerp(couleur_pret_tint, 0.5) if proprietes.get("pret_a_souder", false) else base

# Bloc de texte d'un objet -- special-case le FANTOME (rien d'autre a lire
# sur des proprietes vides que son id) pour ne jamais afficher des zeros
# trompeurs (temperature=0.0/masse=0.0 laisserait croire a un objet froid
# et sans masse, pas a une absence).
#
# SPECIAL-CASE "SOUDE" (bug signale a l'ecran -- "la charge de fer_0
# disparait et n'augmente plus quand fer_1 statut=fantome") : UNE FOIS
# fusionne, un objet n'a structurellement plus aucun voisin soudable dans
# une scene a deux fers (l'absorbe est un fantome, jamais compte comme
# cause -- voir causes_de_soudure) -- sa charge de soudure retombe donc a
# zero et y reste POUR TOUJOURS, ce n'est jamais un defaut du mecanisme
# (rien a fusionner avec, la charge dit vrai). Mais afficher
# "charge_soudure = 0.00" juste a cote de "statut = soude" se lisait comme
# un RECUL alors que l'objet a deja atteint son but -- decision Yael
# (AskUserQuestion) : la ligne charge_soudure ne s'affiche plus du tout
# des que statut == "soude", plus rien qui puisse se lire comme une
# regression sur un objet deja fusionne.
static func texte_label(id: String, proprietes: Dictionary, nom_marqueur: String) -> String:
	var statut: String = statut_pour_objet(proprietes, nom_marqueur)
	if statut == "fantome":
		return "%s\nstatut = fantome (absorbe par une soudure)" % id
	var etats: Array = proprietes.get("etats_actifs", [])
	var etats_texte: String = " + ".join(etats) if not etats.is_empty() else "(aucun)"
	if statut == "soude":
		return "%s\nstatut = %s\ntemperature = %.1f\netats = %s\nmasse = %.1f" % [
			id,
			statut,
			proprietes.get("temperature", 0.0),
			etats_texte,
			proprietes.get("masse", 0.0),
		]
	var charge: float = proprietes.get("etats", {}).get("soudure", {}).get("charge", 0.0)
	return "%s\nstatut = %s\ntemperature = %.1f\netats = %s\ncharge_soudure = %.2f\nmasse = %.1f" % [
		id,
		statut,
		proprietes.get("temperature", 0.0),
		etats_texte,
		charge,
		proprietes.get("masse", 0.0),
	]

static func ligne_bascule_etat(t: float, id: String, etats_actifs: Array) -> String:
	return "t=%.1f %s : etats -> %s" % [t, id, (" + ".join(etats_actifs) if not etats_actifs.is_empty() else "(aucun)")]

static func ligne_bascule_charge(t: float, id: String, marque: bool) -> String:
	return "t=%.1f %s : pret_a_souder %s" % [t, id, ("pose" if marque else "retire")]

static func ligne_soudure(t: float, id_a: String, id_b: String, masse_a: float, masse_b: float, masse_composite: float) -> String:
	return "t=%.1f SOUDURE : %s (%.1f) + %s (%.1f) -> %s (%.1f)" % [t, id_a, masse_a, id_b, masse_b, id_a, masse_composite]

static func ligne_fantome(t: float, id: String) -> String:
	return "t=%.1f %s : fantome (absorbe par une soudure)" % [t, id]

# Pose sur "objet" tout ce que Objet.fabriquer ne pose jamais lui-meme sur
# une table synthetique sans "herite" (voir en-tete, DEUXIEME FANTOME) :
# la temperature (paquet objet_physique, jamais fusionne ici), l'etat de
# phase (vide, sera redecouvert au tick suivant par SeuilEtat.avancer
# depuis la temperature reappliquee) et le canal de soudure remis a zero
# (charge.gd, meme forme qu'a la fabrication initiale). MUTATION EN PLACE,
# meme convention que LienPersonnel.poser/Deformation.poser -- STATIQUE
# pour rester testable directement (voir test_banc_soudure.gd), les quatre
# reglages du canal sont donc recus en parametre plutot que lus sur
# l'instance. Appelee DEUX FOIS : une fois par objet en _ready()
# (temperature_initiale), une fois sur le survivant juste apres un
# Soudure.souder() reussi (sa PROPRE derniere temperature connue, capturee
# par l'appelant avant l'appel -- jamais remise a temperature_initiale, un
# composite ne "renait" pas froid).
static func poser_etat_initial(objet: Dictionary, temperature: float, nom_marqueur: String, seuil_charge: float, portee_contact: float, taux_decroissance: float) -> void:
	objet.proprietes["temperature"] = temperature
	objet.proprietes["etats_actifs"] = []
	var poser := {}
	poser[nom_marqueur] = true
	objet.proprietes["etats"] = {
		"soudure": {
			"charge": 0.0,
			"seuil": seuil_charge,
			"portee_charge": portee_contact,
			"taux_decroissance": taux_decroissance,
			"poser": poser,
		},
	}

# ---- Rendu et cablage, jetables ----

func _monde_vivant() -> Array:
	return _monde.filter(func(o): return not o.proprietes.is_empty())

func _par_id(id: String) -> Dictionary:
	for objet in _monde:
		if objet.id == id:
			return objet
	return {}

# Position-monde du curseur -- IMPUR (Node2D.get_global_mouse_position,
# tient compte de la Camera2D active), jamais appelee par un test headless
# (aucune souris en --headless). Seule la fonction PURE en aval,
# sources_du_tick, est testee -- meme separation que
# banc_temperature.gd:deplacement_clavier (Input lu ici, jamais dans la
# fonction statique).
func _position_monde_du_curseur() -> Vector3:
	var p := get_global_mouse_position()
	return Vector3(p.x, p.y, 0.0)

func _actualiser_rendu(chauffe: bool, position_curseur: Vector3) -> void:
	var blocs: Array = []
	for i in range(_monde.size()):
		var objet: Dictionary = _monde[i]
		var noeud: ColorRect = _noeuds[i]
		if objet.proprietes.is_empty():
			noeud.visible = false
			blocs.append(texte_label(objet.id, objet.proprietes, _nom_marqueur))
			continue
		noeud.visible = true
		noeud.color = couleur_pour_objet(objet.proprietes, _couleur_fer, _couleur_bois, _couleur_chaud_tint, _couleur_pret_tint)
		blocs.append(texte_label(objet.id, objet.proprietes, _nom_marqueur))
	_label.text = "\n\n".join(blocs)

	_noeud_curseur.visible = chauffe
	if chauffe:
		_noeud_curseur.position = Vector2(position_curseur.x, position_curseur.y) - _noeud_curseur.size / 2.0

func _dessiner_carre(position3: Vector3, couleur: Color, taille: float = TAILLE) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	carre.color = couleur
	carre.position = Vector2(position3.x, position3.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _couleur_depuis_array(rgb: Array) -> Color:
	if rgb.size() > 3:
		return Color(rgb[0], rgb[1], rgb[2], rgb[3])
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
