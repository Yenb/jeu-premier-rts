extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_rigidite.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « rigidite -- resistance a la flexion » : "rigidite"
# (data/materiaux.json, bois 11.0/pierre 50.0/fer 200.0, DORMANTE depuis
# la creation du catalogue) rejoint enfin data/proprietes_immuables_
# composition.json (voir §4) -- avant ce chantier, aucun objet fabrique
# par composition ne portait jamais proprietes.rigidite. Ce banc est la
# PREMIERE lecture reelle de "rigidite", pour un usage MECANIQUE (flexion)
# distinct de la fondation deja notee ailleurs pour un futur delai sonore
# (docs/design.md, "Vitesse de propagation du son par materiau") -- meme
# grandeur physique, deux mecanismes independants qui la consomment
# chacun a leur maniere (meme statut que "porosite", qui traverse deja
# humidite et combustion sans jamais etre le meme mecanisme).
#
# AUCUN MECANISME DU COEUR TOUCHE : seuil_etat.gd/etat_effectif.gd/
# objet.gd/banc_commun.gd restent inchanges. Une seule ligne de donnee
# au-dela de ce fichier et de data/banc_rigidite.json (jetable, propre au
# banc) : "rigidite" rejoint data/proprietes_immuables_composition.json
# (voir §4).
#
# LE CATALOGUE DE SEUIL EST LOCAL A CE BANC (data/banc_rigidite.json,
# champ "seuil_flexion"), JAMAIS ajoute a data/seuils_etat.json partage --
# contrairement a "fracture"/"fracture_sonore" (qui visent tous deux
# resistance_impact, la MEME grandeur materiau), la grandeur comparee ici
# ("fleche_maximale_atteinte") est propre a ce mecanisme, sans rapport
# avec degats_impact_cumules. SeuilEtat.avancer est appele TEL QUEL avec
# ce catalogue local d'une seule entree -- rien de nouveau dans
# seuil_etat.gd, meme fonction que banc_fracture.gd/banc_changement_etat.gd.
#
# CE QU'ON DOIT VOIR : trois poutres horizontales fabriquees (bois/pierre/
# fer, un materiau reel chacune, Objet.fabriquer/composition/
# materiaux.json -- jamais construites a la main), soutenues a leurs deux
# extremites (ancrages fixes dessines a chaque bout). AUCUNE charge au
# demarrage ; un clic gauche BASCULE une charge identique sur LES TROIS A
# LA FOIS (meme geste que banc_friction.gd:basculer_mouille). La FLECHE de
# chaque poutre est charge / rigidite_effective (EtatEffectif.valeur,
# jamais reimplementee) : le bois (rigidite 11.0) flechit beaucoup, le fer
# (200.0) a peine, la pierre (50.0) au milieu. Visuellement, le point
# CENTRAL de la poutre (Line2D a trois points, aucune courbe de Bezier) se
# deplace vers le bas proportionnellement a la fleche MAXIMALE ATTEINTE --
# jamais la fleche instantanee : une fois qu'une poutre a flechi, elle
# reste visiblement deformee meme si la charge est ensuite retiree, meme
# principe que degats_impact_cumules dans banc_fracture.gd (un
# accumulateur qui ne redescend jamais). Si cette fleche maximale depasse
# seuil_flexion (donnee locale au banc), la poutre CASSE : l'etat
# "fracture" est pose via SeuilEtat.avancer (data/seuils_etat.json local,
# meme patron que banc_fracture.gd:avancer_fracture) et ne se retire
# JAMAIS (fleche_maximale_atteinte ne redescend jamais). Avec les valeurs
# de demonstration (charge 500.0, seuil_flexion 20.0), le bois (fleche
# ~45.5) casse, la pierre (~10.0) et le fer (~2.5) resistent. Un Label par
# poutre affiche rigidite (base et effective), charge, fleche courante et
# maximale, et l'etat fracture ou non. La console imprime une ligne a
# chaque bascule de charge et a chaque fracture.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et fabrique les trois objets
#   (Objet.fabriquer, composition fusionnee -- meme patron que
#   banc_friction.gd). _unhandled_input bascule la charge sur les trois au
#   clic gauche. _process appelle UNIQUEMENT avancer() (fonction statique,
#   ci-dessous) puis lit ses resultats pour l'affichage/la console --
#   jamais un calcul refait ici.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_rigidite.gd) : fleche/avancer/basculer_charge/
#   fabriquer_objets/diagnostiquer/deplacement_centre, plus le texte
#   d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")

const PROPRIETE_RIGIDITE := "rigidite"
const ETAT_NOM_ENTREE_SEUIL := "fracture_flexion"
const LONGUEUR_POUTRE := 220.0
const HAUTEUR_ANCRAGE := 24.0
const LARGEUR_ANCRAGE := 16.0
const EPAISSEUR_POUTRE := 10.0

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _materiaux: Dictionary = {}
var _catalogue_seuils: Dictionary = {}
var _charge_valeur := 0.0
var _seuil_flexion := 0.0
var _facteur_affichage := 1.0
var _objets: Array = []
var _charge_active := false
var _lignes: Dictionary = {}
var _labels: Dictionary = {}
var _fracture_avant: Dictionary = {}
var _temps := 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_rigidite.json")
	_etats = _charger_json("res://data/etats.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	_charge_valeur = _config.get("charge_valeur", 0.0)
	_seuil_flexion = _config.get("seuil_flexion", INF)
	_facteur_affichage = _config.get("facteur_affichage", 1.0)
	_catalogue_seuils = {
		ETAT_NOM_ENTREE_SEUIL: {
			"propriete_continue": "fleche_maximale_atteinte",
			"seuil": _seuil_flexion,
			"etat": "fracture",
		},
	}

	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, proprietes_immuables)
	for objet in _objets:
		_fracture_avant[objet.id] = false
		_creer_rendu_poutre(objet)

	_rafraichir_tout()
	_poser_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_charge_active = basculer_charge(_charge_active)
		print(ligne_charge(_temps, _charge_active))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var bascules: Array = avancer(_objets, _charge_valeur, _charge_active, _etats, _catalogue_seuils)
	for id in bascules:
		if est_fracture(_objet_par_id(id)) and not _fracture_avant.get(id, false):
			_fracture_avant[id] = true
			print(ligne_fracture(_temps, id, diagnostiquer(_objet_par_id(id), _etats)))
	_rafraichir_tout()

func _objet_par_id(id: String) -> Dictionary:
	for objet in _objets:
		if objet.id == id:
			return objet
	return {}

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var diag := diagnostiquer(objet, _etats)
		var centre := Vector2(objet.position.x, objet.position.y)
		var deplacement := deplacement_centre(diag.fleche_maximale_atteinte, _facteur_affichage)
		var gauche := centre - Vector2(LONGUEUR_POUTRE / 2.0, 0.0)
		var droite := centre + Vector2(LONGUEUR_POUTRE / 2.0, 0.0)
		var milieu := centre + Vector2(0.0, deplacement)
		var ligne: Line2D = _lignes[id]
		ligne.points = PackedVector2Array([gauche, milieu, droite])
		ligne.default_color = _couleur_pour(objet, diag.fracture)
		_labels[id].text = texte_objet(id, diag)
		_labels[id].position = centre - Vector2(LONGUEUR_POUTRE / 2.0, 70.0)

# ---- Fonctions PURES, testables headless (voir test_banc_rigidite.gd) ----

# fleche = charge / rigidite_effective -- une rigidite effective nulle ou
# negative (donnee incoherente, jamais produite par les materiaux reels de
# ce depot) flechirait a l'infini plutot que de diviser par zero
# silencieusement : garde defensive, jamais un chemin reellement atteint
# par une fiche materiau reelle.
static func fleche(charge: float, rigidite_effective: float) -> float:
	if rigidite_effective <= 0.0:
		return INF
	return charge / rigidite_effective

# UN PAS de simulation complet : pour chaque objet, lit sa rigidite
# EFFECTIVE (EtatEffectif.valeur, jamais reimplementee), en deduit la
# fleche courante (0.0 si la charge n'est pas active), accumule la fleche
# MAXIMALE ATTEINTE (jamais redescendue -- meme principe que
# degats_impact_cumules dans banc_fracture.gd), puis appelle
# SeuilEtat.avancer (INCHANGE) sur le catalogue local pour poser "fracture"
# au franchissement de seuil_flexion. Rend l'Array des id ayant vu un etat
# basculer ce passage (meme contrat que SeuilEtat.avancer).
static func avancer(objets: Array, charge_valeur: float, charge_active: bool, etats: Dictionary, catalogue_seuils: Dictionary) -> Array:
	var charge_actuelle := charge_valeur if charge_active else 0.0
	for objet in objets:
		var rigidite_eff: float = EtatEffectif.valeur(objet, PROPRIETE_RIGIDITE, etats)
		var f := fleche(charge_actuelle, rigidite_eff)
		objet.proprietes["fleche_actuelle"] = f
		var maximale: float = objet.proprietes.get("fleche_maximale_atteinte", 0.0)
		objet.proprietes["fleche_maximale_atteinte"] = max(maximale, f)
	return SeuilEtat.avancer(objets, catalogue_seuils)

static func est_fracture(objet: Dictionary) -> bool:
	return objet.get("proprietes", {}).get("etats_actifs", []).has("fracture")

static func basculer_charge(actif: bool) -> bool:
	return not actif

# Construit les trois objets via Objet.fabriquer (composition fusionnee --
# meme patron que banc_friction.gd, catalogue LOCAL a une entree par id).
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet.proprietes["etats_actifs"] = []
		objet.proprietes["fleche_actuelle"] = 0.0
		objet.proprietes["fleche_maximale_atteinte"] = 0.0
		objets.append(objet)
	return objets

# Deplacement visuel du point central, pixels -- une simple mise a
# l'echelle de la fleche physique, pure et testable, jamais melangee au
# calcul de fleche() lui-meme.
static func deplacement_centre(fleche_maximale_atteinte: float, facteur_affichage: float) -> float:
	return fleche_maximale_atteinte * facteur_affichage

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees,
# ne reimplemente jamais une loi (meme doctrine que banc_friction.gd:
# diagnostiquer). Rend { rigidite_base, rigidite_effective, fleche_actuelle,
# fleche_maximale_atteinte, fracture }.
static func diagnostiquer(objet: Dictionary, etats: Dictionary) -> Dictionary:
	return {
		"rigidite_base": objet.get("proprietes", {}).get(PROPRIETE_RIGIDITE, 0.0),
		"rigidite_effective": EtatEffectif.valeur(objet, PROPRIETE_RIGIDITE, etats),
		"fleche_actuelle": objet.get("proprietes", {}).get("fleche_actuelle", 0.0),
		"fleche_maximale_atteinte": objet.get("proprietes", {}).get("fleche_maximale_atteinte", 0.0),
		"fracture": est_fracture(objet),
	}

static func texte_objet(id: String, diag: Dictionary) -> String:
	return "%s\nrigidite (base) = %.1f\nrigidite (effective) = %.2f\nfleche = %.2f\nfleche max = %.2f\netat = %s" % [
		id, diag.rigidite_base, diag.rigidite_effective, diag.fleche_actuelle, diag.fleche_maximale_atteinte,
		"fracture" if diag.fracture else "intacte"
	]

static func ligne_charge(t: float, actif: bool) -> String:
	return "t=%.1fs charge : %s (les trois poutres)" % [t, "POSEE" if actif else "RETIREE"]

static func ligne_fracture(t: float, id: String, diag: Dictionary) -> String:
	return "t=%.1fs %s : FRACTURE (fleche max = %.2f, rigidite effective = %.2f)" % [t, id, diag.fleche_maximale_atteinte, diag.rigidite_effective]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _couleur_pour(objet: Dictionary, fracture: bool) -> Color:
	if fracture:
		return Color(0.7, 0.2, 0.15)
	var decl_couleurs: Dictionary = _config.get("couleurs", {})
	var rgb: Array = decl_couleurs.get(objet.id, [0.6, 0.6, 0.6])
	return Color(rgb[0], rgb[1], rgb[2])

func _creer_rendu_poutre(objet: Dictionary) -> void:
	var id: String = objet.id
	var centre := Vector2(objet.position.x, objet.position.y)

	var ligne := Line2D.new()
	ligne.width = EPAISSEUR_POUTRE
	add_child(ligne)
	_lignes[id] = ligne

	for signe in [-1.0, 1.0]:
		var ancrage := ColorRect.new()
		ancrage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ancrage.size = Vector2(LARGEUR_ANCRAGE, HAUTEUR_ANCRAGE)
		ancrage.color = Color(0.35, 0.35, 0.38)
		ancrage.position = centre + Vector2(signe * LONGUEUR_POUTRE / 2.0 - LARGEUR_ANCRAGE / 2.0, 0.0)
		add_child(ancrage)

	var label := Label.new()
	add_child(label)
	_labels[id] = label

func _poser_camera() -> void:
	var decl_camera: Dictionary = _config.get("camera", {})
	var pos: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(decl_camera.get("zoom", 1.0), decl_camera.get("zoom", 1.0))
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
