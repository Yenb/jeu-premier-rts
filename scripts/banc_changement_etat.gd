extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_changement_etat.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1, coexiste avec les
# autres bancs). PREMIERE DEMONSTRATION REELLE de scripts/seuil_etat.gd
# (chantier "colonne thermique", cases 3/4/8 du tableau Thermique -- voir
# docs/orion-matrice-elements.md) : temperature.gd (deja ferme, NON
# TOUCHE) fait chauffer/refroidir un objet en fer FABRIQUE PAR
# COMPOSITION (Objet.fabriquer, materiaux/proprietes_immuables reels,
# jamais un point_fusion/point_ebullition pose a la main) ; seuil_etat.gd
# (NON TOUCHE, deja ferme et prouve hors domaine) lit sa temperature et
# bascule solide -> liquide -> gaz au franchissement de point_fusion/
# point_ebullition, et pose/retire "chaud" independamment ; etat_effectif.gd
# (deja ferme, NON TOUCHE) module sa malleabilite EFFECTIVE des que "chaud"
# est actif. Noms de domaine reels (fer/solide/liquide/gaz/chaud/
# malleabilite) -- exception documentee (CLAUDE.md : "un banc jetable peut
# nommer une categorie pour poser une scene d'observation").
#
# JETABLE PAR DEFINITION : aucune regle de jeu ne doit vivre ici, seulement
# du cablage et de la lecture. Toute la logique est en fonctions STATIQUES
# testables (temperature_source/sources_du_tick/texte_etat/
# couleur_pour_etats/texte_label/ligne_log) -- _process ne fait
# qu'appeler Temperature.avancer PUIS SeuilEtat.avancer (deja les
# mecanismes reels) puis LIRE leurs resultats, jamais recalculer une loi
# deja ecrite ailleurs.
#
# CE QU'ON DOIT VOIR : un carre fer, IMMOBILE, chauffe par une source FIXE
# a sa position (distance nulle -- attenuation toujours pleine, la
# temperature locale suit directement la temperature de la source) dont la
# temperature CROIT PROGRESSIVEMENT (rampe lineaire, fonction pure du
# temps, aucun hasard -- meme discipline que vent.gd/banc_temperature.gd)
# pendant `duree_chauffe` secondes, PUIS s'ETEINT (la source disparait du
# tableau passe a Temperature.avancer -- l'objet retombe vers l'ambiante
# par la MEME loi de Newton que loin de toute source, aucun cas special).
# La couleur du carre encode la PHASE (gris acier solide, orange-rouge
# liquide au franchissement de point_fusion, jaune pale quasi-transparent
# gazeux au franchissement de point_ebullition) et un LISERE plus chaud
# des que l'etat "chaud" est actif sur la phase solide (annonce visuelle
# de la fusion a venir, avant meme le changement de phase). Un Label
# (CanvasLayer, patron banc_champ.gd/banc_temperature.gd) affiche EN
# PERMANENCE : la temperature de l'objet, la temperature locale (celle que
# la source lui impose), les etats actifs (phase + "chaud" le cas
# echeant), sa malleabilite EFFECTIVE (EtatEffectif.valeur, jamais
# reimplementee -- monte des que "chaud" est actif, quelle que soit la
# phase) et sa FLUIDITE EFFECTIVE (voir CASE 7 ci-dessous). La console
# imprime une ligne A CHAQUE BASCULE (le tableau rendu par
# SeuilEtat.avancer, jamais par frame) : temps, temperature, etats,
# malleabilite effective, fluidite effective -- une phrase par transition.
#
# CASE 7 (fluidite_liquide, chantier "fluidite_liquide") : fusionnee a la
# fabrication depuis data/materiaux.json (proprietes_immuables_
# composition.json, deja fait par le chantier "colonne thermique" -- rien
# ajoute ici), donc TOUJOURS presente sur proprietes une fois l'objet
# fabrique, quelle que soit sa phase -- contrairement a malleabilite/chaud
# (un MODULATEUR, qui ne fait jamais tomber une valeur a zero), la matrice
# (docs/orion-matrice-elements.md) documente la portee de fluidite_liquide
# comme un SEUIL ({"seuil": "point_fusion"}), pas un bonus : un fer solide
# ne doit porter AUCUNE fluidite effective, un fer liquide porte sa vraie
# valeur materiau (fer 0.6). etat_effectif.gd n'offre que ECRASER (valeur
# fixe, perdrait la distinction bois/pierre/fer) et MODULER (multiplie,
# ne tombe jamais a zero) -- aucun des deux n'exprime "lisible seulement
# si liquide". `fluidite_effective` (fonction statique ci-dessous) fait
# donc le garde ICI, cote appelant : etats_actifs.has("liquide") avant de
# lire EtatEffectif.valeur -- si absent, 0.0 (aucune fluidite, jamais la
# base materiau) ; si present, valeur() (aucun etat de data/etats.json ne
# module "fluidite_liquide", valeur() rend donc la base telle quelle).
# data/etats.json N'A PAS ete etendu pour ce chantier -- rien n'y module
# fluidite_liquide, le garde suffit.
#
# PORTEE VOLONTAIREMENT LIMITEE : ce banc ne route rien par
# attaches.gd/proximite.gd/jugement.gd/dominance.gd/agir.gd -- aucune
# decision, seulement l'appel des mecanismes de temperature et de seuil
# d'etat sur un objet immobile.
#
# LIMITE STRICTE (rappel explicite du chantier) : ce fichier cable
# UNIQUEMENT ce banc -- aucun mecanisme neuf, aucune extension du coeur.
# temperature.gd/seuil_etat.gd/etat_effectif.gd/objet.gd sont deja ecrits
# et verts ; ce fichier ne fait que les appeler et lire leurs resultats
# publics.

const Objet = preload("res://scripts/objet.gd")
const Temperature = preload("res://scripts/temperature.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")

const TAILLE_OBJET := 90.0
const TAILLE_SOURCE := 30.0

var _donnees: Dictionary = {}
var _catalogue_temperature: Dictionary = {}
var _catalogue_seuils: Dictionary = {}
var _catalogue_etats: Dictionary = {}
var _objet: Dictionary = {}
var _position_source := Vector3.ZERO
var _rayon_source := 100.0
var _force_source := 1.0
var _ambiante := 20.0
var _ramp_rate := 40.0
var _duree_chauffe := 90.0
var _couleur_solide := Color(0.55, 0.55, 0.58)
var _couleur_chaud_tint := Color(0.85, 0.45, 0.1)
var _couleur_liquide := Color(0.95, 0.35, 0.05)
var _couleur_gaz := Color(0.95, 0.95, 0.55, 0.4)
var _noeud_objet: ColorRect
var _noeud_source: ColorRect
var _label: Label
var _temps_ecoule := 0.0
var _prochain_print := 0.0
var _intervalle_print := 2.0

func _ready() -> void:
	_donnees = _charger_json("res://data/banc_changement_etat.json")
	_catalogue_temperature = _charger_json("res://data/temperature.json")
	_catalogue_seuils = _charger_json("res://data/seuils_etat.json")
	_catalogue_etats = _charger_json("res://data/etats.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	_intervalle_print = _donnees.get("intervalle_print", 2.0)

	var decl_objet: Dictionary = _donnees.get("objet", {})
	var pos_objet: Array = decl_objet.get("position", [0.0, 0.0, 0.0])
	var catalogue_types := {
		"fer_test": {
			"composition": decl_objet.get("composition", [{"materiau": "fer", "volume": 1.0}]),
		},
	}
	_objet = Objet.fabriquer("fer_test", "fer_test", Vector3(pos_objet[0], pos_objet[1], pos_objet[2]), catalogue_types, materiaux, proprietes_immuables)
	# Meme patron que banc_humidite.gd:fabriquer_objets -- un catalogue LOCAL
	# a une seule cle "composition" ne passe jamais par le paquet
	# objet_physique (aucune cle "herite"), donc "temperature" n'existe pas
	# encore sur l'objet fabrique : posee ICI, au meme defaut que le paquet
	# (data/types.json:objet_physique.temperature, 20.0), jamais devinee.
	_objet.proprietes["temperature"] = decl_objet.get("temperature_initiale", 20.0)
	_objet.proprietes["etats_actifs"] = []

	var decl_source: Dictionary = _donnees.get("source", {})
	var pos_source: Array = decl_source.get("position", pos_objet)
	_position_source = Vector3(pos_source[0], pos_source[1], pos_source[2])
	_rayon_source = decl_source.get("rayon", 100.0)
	_force_source = decl_source.get("force", 1.0)
	_ambiante = _catalogue_temperature.get("defaut", {}).get("ambiante", 20.0)
	_ramp_rate = decl_source.get("ramp_rate", 40.0)
	_duree_chauffe = decl_source.get("duree_chauffe", 90.0)

	var decl_couleurs: Dictionary = _donnees.get("couleurs", {})
	_couleur_solide = _couleur_depuis_array(decl_couleurs.get("solide", [0.55, 0.55, 0.58]))
	_couleur_chaud_tint = _couleur_depuis_array(decl_couleurs.get("chaud_tint", [0.85, 0.45, 0.1]))
	_couleur_liquide = _couleur_depuis_array(decl_couleurs.get("liquide", [0.95, 0.35, 0.05]))
	var gaz_rgb: Array = decl_couleurs.get("gaz", [0.95, 0.95, 0.55])
	_couleur_gaz = Color(gaz_rgb[0], gaz_rgb[1], gaz_rgb[2], decl_couleurs.get("gaz_alpha", 0.4))

	_noeud_source = _dessiner_carre(_position_source, TAILLE_SOURCE, Color(0.9, 0.2, 0.1))
	_noeud_objet = _dessiner_carre(_objet.position, TAILLE_OBJET, _couleur_solide)

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label = Label.new()
	_label.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label)

	var decl_camera: Dictionary = _donnees.get("camera", {})
	var pos_camera: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos_camera[0], pos_camera[1])
	camera.zoom = Vector2(decl_camera.get("zoom", 0.7), decl_camera.get("zoom", 0.7))
	camera.enabled = true
	add_child(camera)

	_actualiser_rendu(sources_du_tick(0.0, _position_source, _rayon_source, _force_source, _ambiante, _ramp_rate, _duree_chauffe))

func _process(delta: float) -> void:
	_temps_ecoule += delta

	var sources := sources_du_tick(_temps_ecoule, _position_source, _rayon_source, _force_source, _ambiante, _ramp_rate, _duree_chauffe)
	var monde := [_objet]
	Temperature.avancer(monde, sources, delta, _catalogue_temperature)
	var bascules: Array = SeuilEtat.avancer(monde, _catalogue_seuils)

	_actualiser_rendu(sources)

	if not bascules.is_empty() or _temps_ecoule >= _prochain_print:
		if _temps_ecoule >= _prochain_print:
			_prochain_print = _temps_ecoule + _intervalle_print
		print(ligne_log(_temps_ecoule, _objet.id, _objet.proprietes.temperature, _objet.proprietes.get("etats_actifs", []), _malleabilite_effective(), _fluidite_effective()))

func _actualiser_rendu(sources: Array) -> void:
	var etats_actifs: Array = _objet.proprietes.get("etats_actifs", [])
	_noeud_objet.color = couleur_pour_etats(etats_actifs, _couleur_solide, _couleur_chaud_tint, _couleur_liquide, _couleur_gaz)
	var t_locale: float = Temperature.locale(_objet.position, sources, _catalogue_temperature)
	_label.text = texte_label(_objet.proprietes.temperature, t_locale, etats_actifs, _malleabilite_effective(), _fluidite_effective())
	_noeud_source.visible = not sources.is_empty()
	if not sources.is_empty():
		_noeud_source.color = _couleur_pour_temperature_source(sources[0].temperature)

func _malleabilite_effective() -> float:
	return EtatEffectif.valeur(_objet, "malleabilite", _catalogue_etats)

func _fluidite_effective() -> float:
	return fluidite_effective(_objet, _catalogue_etats)

# ---- Fonctions statiques, pures, testables ----

# Temperature que la source impose a l'instant `t` : une rampe lineaire
# depuis l'ambiante, PLAFONNEE a la valeur atteinte a `duree_chauffe`
# (jamais au-dela -- la source cesse ensuite d'exister, voir
# sources_du_tick) -- fonction PURE du temps, aucun etat, aucun hasard,
# meme discipline que vent.gd/banc_temperature.gd:position_source_mobile.
static func temperature_source(t: float, ambiante: float, ramp_rate: float, duree_chauffe: float) -> float:
	var t_effectif: float = min(t, duree_chauffe)
	return ambiante + ramp_rate * t_effectif

# La source de ce tick, dans la forme attendue par temperature.gd:
# locale/avancer -- construite ICI, jamais par le mecanisme (voir
# temperature.gd, en-tete). Au-dela de `duree_chauffe`, la source
# DISPARAIT du tableau (Array vide) -- l'objet retombe vers l'ambiante par
# la MEME loi de Newton que temperature.gd applique deja loin de toute
# source, aucun cas special ecrit ici.
static func sources_du_tick(t: float, position: Vector3, rayon: float, force: float, ambiante: float, ramp_rate: float, duree_chauffe: float) -> Array:
	if t > duree_chauffe:
		return []
	return [{
		"position": position,
		"rayon": rayon,
		"temperature": temperature_source(t, ambiante, ramp_rate, duree_chauffe),
		"force": force,
	}]

# Texte lisible des etats actifs -- phase (solide/liquide/gaz) PLUS
# "chaud" s'il est present, dans cet ordre -- jamais recalcule depuis un
# ordre d'iteration de Dictionary/Array, seulement une jointure textuelle.
static func texte_etat(etats_actifs: Array) -> String:
	if etats_actifs.is_empty():
		return "(aucun)"
	return " + ".join(etats_actifs)

# Couleur de phase (solide/liquide/gaz, priorite gaz > liquide > solide --
# les trois sont mutuellement exclusifs par construction de
# data/seuils_etat.json, cet ordre ne fait jamais cohabiter deux phases)
# PLUS un lisere plus chaud si "chaud" est actif SANS avoir encore changé
# de phase (annonce visuelle de la fusion a venir) -- une fois liquide ou
# gaz, la couleur de phase domine deja, "chaud" n'y ajoute plus rien de
# visible (il reste actif, lu dans le Label, pas dans la teinte).
static func couleur_pour_etats(etats_actifs: Array, couleur_solide: Color, couleur_chaud_tint: Color, couleur_liquide: Color, couleur_gaz: Color) -> Color:
	var base: Color
	if etats_actifs.has("gaz"):
		base = couleur_gaz
	elif etats_actifs.has("liquide"):
		base = couleur_liquide
	else:
		base = couleur_solide
	if etats_actifs.has("chaud") and not etats_actifs.has("liquide") and not etats_actifs.has("gaz"):
		base = base.lerp(couleur_chaud_tint, 0.6)
	return base

# CASE 7 (fluidite_liquide) : lisible SEULEMENT si "liquide" est actif --
# voir en-tete du fichier. etat_effectif.gd n'offre ni ECRASER (perdrait la
# distinction bois/pierre/fer) ni MODULER (ne tombe jamais a zero) pour
# exprimer ce garde -- fait ICI, cote appelant, avant de deleguer a
# EtatEffectif.valeur (qui rend alors la base materiau telle quelle, aucun
# etat de data/etats.json ne modulant "fluidite_liquide"). Un objet sans
# "fluidite_liquide" en donnee (proprietes.get par defaut a 0.0 dans
# etat_effectif.gd) n'est pas affecte : il rend 0.0 dans les deux cas.
static func fluidite_effective(chose: Dictionary, etats: Dictionary) -> float:
	var actifs: Array = chose.get("proprietes", {}).get("etats_actifs", [])
	if not actifs.has("liquide"):
		return 0.0
	return EtatEffectif.valeur(chose, "fluidite_liquide", etats)

static func texte_label(temperature: float, temperature_locale: float, etats_actifs: Array, malleabilite_effective: float, fluidite: float) -> String:
	return "fer_test\ntemperature = %.1f\ntemperature locale = %.1f\netats = %s\nmalleabilite effective = %.3f\nfluidite effective = %.3f" % [
		temperature, temperature_locale, texte_etat(etats_actifs), malleabilite_effective, fluidite
	]

static func ligne_log(t: float, id: String, temperature: float, etats_actifs: Array, malleabilite_effective: float, fluidite: float) -> String:
	return "t=%.1f %s : temperature=%.1f etats=%s malleabilite_effective=%.3f fluidite_effective=%.3f" % [
		t, id, temperature, texte_etat(etats_actifs), malleabilite_effective, fluidite
	]

# ---- Rendu, jetable ----

func _couleur_pour_temperature_source(temperature: float) -> Color:
	var ratio: float = clamp((temperature - _ambiante) / 3000.0, 0.0, 1.0)
	return Color(0.6, 0.15, 0.05).lerp(Color(1.0, 0.9, 0.3), ratio)

func _dessiner_carre(position3: Vector3, taille: float, couleur: Color) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	carre.color = couleur
	carre.position = Vector2(position3.x, position3.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _couleur_depuis_array(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
