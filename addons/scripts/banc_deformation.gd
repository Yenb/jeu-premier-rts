extends Node2D

# Cablage de banc VISUEL, separe des autres bancs (Scene/banc_deformation.tscn,
# PAS la scene principale -- run/main_scene reste banc_p1). Existe pour VOIR
# scripts/deformation.gd (PHASE 4 piece 1, ferme et prouve hors domaine par
# test_deformation.gd) recevoir sa PREMIERE SOURCE REELLE -- habituation sur
# "brule" -- voir docs/cadrage_phase4_deformation.md, PHASE 4 piece 2, chantier
# "L'entite comme agent complet". JETABLE PAR DEFINITION.
#
# CE QUE CE BANC MONTRE : deux colons identiques a leur naissance (meme
# forme/poids_verbes vides, meme deformation de depart heritee de
# data/types.json:colon.deformation.habituation.brule -- rapide/lent a 0.0
# tous les deux) -- seule leur POSITION differe, c'est la variable
# experimentale de cette demonstration. "expose" reste en permanence a
# portee de vue d'un feu stationnaire (brule: true) ; "isole" est place hors
# de portee de toute source de "brule". A chaque tick ou un colon PERCOIT
# (Perception.percevoir, canal vue) une chose portant le declencheur,
# Deformation.poser(colon, "habituation", "brule", magnitude) est appele ;
# Deformation.avancer(colon, delta, catalogue) tourne pour LES DEUX colons a
# chaque tick, expose ou non. Une barre au-dessus de chaque colon (largeur =
# grandeur visuelle, meme convention que banc_p1.gd/banc_animal.gd) reflete
# Deformation.biais(colon, "habituation", "brule", catalogue) -- l'expose la
# voit grandir, l'isole reste a largeur nulle.
#
# PORTEE VOLONTAIREMENT LIMITEE A CETTE PIECE (voir cadrage) : ce banc ne
# route RIEN par attaches.gd/proximite.gd/jugement.gd/dominance.gd/agir.gd --
# la lecture de biais() par une couche de saillance est PIECE 3, pas ici. Ce
# fichier exerce seulement Perception (deja ferme, PHASE 3.5) et
# poser/avancer/biais (deja fermes, PHASE 4 piece 1), pour prouver que
# deformation.gd recoit correctement sa premiere source reelle. Aucun clic,
# aucune interaction : la divergence s'installe seule, tick apres tick.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge data/banc_deformation.json (feu + deux
#   colons, jetable) et fusionne entite/colon depuis data/types.json
#   par-dessus le catalogue local (meme geste que banc_charge.gd:_ready) ;
#   charge aussi data/canaux.json et data/deformations.json (catalogues
#   partages, jamais mutes). _process appelle avancer_colon(...) pour
#   chaque colon puis redessine sa barre depuis Deformation.biais(...).
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_deformation.gd) : percoit_declencheur(...) -- vrai si au
#   moins une chose PERCUE porte la propriete declencheur (nom en
#   parametre, jamais "brule" en dur) ; avancer_colon(...) -- enveloppe
#   Perception.percevoir + poser (si expose ce tick) + avancer pour UN
#   SEUL colon, UN SEUL tick.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const Deformation = preload("res://scripts/deformation.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const LARGEUR_BARRE := 40.0
const HAUTEUR_BARRE := 5.0

var _couleurs_types: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_deformations: Dictionary = {}
var _declencheur := ""
var _source_deformation := ""
var _cible_deformation := ""
var _magnitude := 0.0
var _biais_max := 1.0
var _monde := Monde.new()
var _colons: Array = []
var _noeuds: Dictionary = {}
var _barres: Dictionary = {}
var _temps_ecoule := 0.0

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_deformation.json")
	_couleurs_types = donnees.get("couleurs_types", {})
	# "feu" reste local (vocabulaire propre a ce banc, exception banc
	# jetable, voir CLAUDE.md) ; objet_physique/dynamique/percevant/agent (et "colon")
	# viennent du catalogue PARTAGE (data/types.json), meme geste que
	# banc_charge.gd:_ready.
	_catalogue_types = donnees.get("types", {}).duplicate(true)
	var types_partages := _charger_json("res://data/types.json")
	_catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	_catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	_catalogue_types["percevant"] = types_partages.get("percevant", {})
	_catalogue_types["agent"] = types_partages.get("agent", {})
	_catalogue_types["colon"] = types_partages.get("colon", {})
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_deformations = _charger_json("res://data/deformations.json")
	_declencheur = donnees.get("declencheur_habituation", "")
	_source_deformation = donnees.get("source_habituation", "")
	_cible_deformation = donnees.get("cible_habituation", "")
	_magnitude = donnees.get("magnitude_exposition", 0.0)
	_biais_max = donnees.get("biais_max", 1.0)

	var feu_decl: Dictionary = donnees.get("feu", {})
	_ajouter_chose("feu_0", "feu", feu_decl.get("position", [0.0, 0.0, 0.0]))

	var declarations: Dictionary = donnees.get("colons", {})
	for nom in declarations:
		_ajouter_colon(nom, declarations[nom])

func _ajouter_chose(id: String, type: String, pos: Array) -> void:
	var position3 := Vector3(pos[0], pos[1], pos[2])
	var objet := Objet.fabriquer(id, type, position3, _catalogue_types)
	_monde.ajouter(objet, type, position3)
	_noeuds[id] = _dessiner_carre(type, pos)

func _ajouter_colon(nom: String, decl: Dictionary) -> void:
	var colon := BancCommun.fabriquer_colon(nom, "colon", decl, _catalogue_types)
	_monde.ajouter(colon, "colon", colon.position)
	_colons.append(colon)
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	_noeuds[colon.id] = _dessiner_carre(nom, pos)
	_barres[colon.id] = _dessiner_barre(Color(1.0, 0.3, 0.6))

func _process(delta: float) -> void:
	_temps_ecoule += delta
	for colon in _colons:
		avancer_colon(
			colon, _monde, _catalogue_canaux, _catalogue_deformations,
			_declencheur, _source_deformation, _cible_deformation, _magnitude, delta,
		)
		var biais := Deformation.biais(colon, _source_deformation, _cible_deformation, _catalogue_deformations)
		_redessiner_barre(colon.id, biais)

# Vrai si au moins une chose PERCUE (Perception.percevoir, deja calculee par
# l'appelant) porte la propriete declencheur -- nom recu en parametre,
# jamais "brule" ecrit en dur ici.
static func percoit_declencheur(perceptions: Array, declencheur: String) -> bool:
	for entree in perceptions:
		if entree.chose.proprietes.get(declencheur, false):
			return true
	return false

# UN tick pour UN colon : percoit -> pose (si expose ce tick) -> avance,
# toujours -- meme si le colon n'a rien percu ce tick (avancer decroit ses
# deux registres independamment de poser, voir deformation.gd:avancer).
static func avancer_colon(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	catalogue_deformations: Dictionary,
	declencheur: String,
	source: String,
	cible: String,
	magnitude: float,
	delta: float,
) -> void:
	var perceptions := Perception.percevoir(colon, monde, catalogue_canaux)
	if percoit_declencheur(perceptions, declencheur):
		Deformation.poser(colon, source, cible, magnitude)
	Deformation.avancer(colon, delta, catalogue_deformations)

func _dessiner_carre(type: String, pos: Array) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(24.0, 24.0)
	carre.color = _couleur_de(type)
	carre.position = Vector2(pos[0], pos[1]) - carre.size / 2.0
	add_child(carre)
	return carre

func _dessiner_barre(couleur: Color) -> ColorRect:
	var barre := ColorRect.new()
	barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barre.color = couleur
	add_child(barre)
	return barre

func _redessiner_barre(id: String, biais: float) -> void:
	var noeud: ColorRect = _noeuds[id]
	var barre: ColorRect = _barres[id]
	var fraction: float = clamp(biais / _biais_max, 0.0, 1.0) if _biais_max > 0.0 else 0.0
	barre.size = Vector2(LARGEUR_BARRE * fraction, HAUTEUR_BARRE)
	barre.position = noeud.position + Vector2(-LARGEUR_BARRE / 2.0 + 12.0, -12.0)

func _couleur_de(type: String) -> Color:
	var rgb: Array = _couleurs_types.get(type, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
