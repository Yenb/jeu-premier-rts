extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_manger.gd
#
# Verrouille le cablage de banc_manger.gd -- chantier « consommer.gd --
# transfert destructif + banc_manger » : le pipeline de decision (perception
# -> proximite -> dominance -> agir) resout "manger" sur la nourriture
# (comestible + profil_saillance), jamais sur bois/pierre (ni l'un ni
# l'autre) ; avancer_repas() appelle scripts/consommer.gd (INCHANGE) une
# fois a portee ; avancer_transformation_repas() appelle scripts/produit.gd
# (INCHANGE) une fois le contenu epuise.
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : perception.gd/
# proximite.gd/dominance.gd/agir.gd/ciblage.gd/consommer.gd/produit.gd/
# etat_effectif.gd/objet.gd restent exactement ceux deja verrouilles par
# leurs propres tests -- ce fichier verrouille uniquement banc_manger.gd.

const BancManger = preload("res://scripts/banc_manger.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

var _donnees: Dictionary = {}
var _materiaux: Dictionary = {}
var _proprietes_immuables: Array = []
var _etats: Dictionary = {}
var _canaux: Dictionary = {}
var _actions: Dictionary = {}
var _profils_saillance: Dictionary = {}
var _catalogue_types: Dictionary = {}

func _init() -> void:
	_charger_donnees_reelles()

	_le_colon_mange_la_nourriture_son_energie_monte()
	_la_nourriture_perd_du_contenu_proportionnellement()
	_quand_le_contenu_atteint_zero_transformee_en_reste()
	_le_colon_ne_percoit_ni_ne_mange_bois_ni_pierre()
	_un_objet_pourri_n_est_pas_mange()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_manger.gd resout 'manger' sur la nourriture (jamais bois/pierre), " +
		"consommer.gd transfere contenu -> energie, produit.gd remplace la nourriture epuisee " +
		"par reste_nourriture, un objet pourri (comestibilite ecrasee) n'est jamais mange")
	quit(0)

func _charger_donnees_reelles() -> void:
	_donnees = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_manger.json"))
	_materiaux = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	_proprietes_immuables = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	_etats = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	_canaux = JSON.parse_string(FileAccess.get_file_as_string("res://data/canaux.json"))
	_actions = JSON.parse_string(FileAccess.get_file_as_string("res://data/types_choses.json"))
	_profils_saillance = JSON.parse_string(FileAccess.get_file_as_string("res://data/profils_saillance.json"))

	_catalogue_types = _donnees.get("types", {}).duplicate(true)
	var types_partages: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	_catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	_catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	_catalogue_types["percevant"] = types_partages.get("percevant", {})
	_catalogue_types["agent"] = types_partages.get("agent", {})
	_catalogue_types["colon"] = types_partages.get("colon", {})
	_catalogue_types["reste_nourriture"] = types_partages.get("reste_nourriture", {})

	verif.v(_profils_saillance.has("nourriture"), "data/profils_saillance.json doit lister 'nourriture'")
	verif.v(types_partages.has("reste_nourriture"), "data/types.json doit lister 'reste_nourriture'")

	verif.v(_proprietes_immuables.has("valeur_nutritive_energie"), "data/proprietes_immuables_composition.json doit lister valeur_nutritive_energie")
	verif.v(_actions.has("comestible") and _actions.comestible.verbes.has("manger"), "data/types_choses.json doit resoudre 'comestible' -> verbe 'manger'")

# ---- Fixtures : scene reelle depuis data/banc_manger.json ----

func _fabriquer_scene() -> Dictionary:
	var objets := BancManger.fabriquer_objets(_donnees.objets, _catalogue_types, _materiaux, _proprietes_immuables)
	var monde := Monde.new()
	for objet in objets:
		monde.ajouter(objet, objet.get("proprietes_type", ""), objet.position)
	var colon := BancCommun.fabriquer_colon(_donnees.colon.id, "colon", _donnees.colon, _catalogue_types)
	monde.ajouter(colon, "colon", colon.position)
	return {"objets": objets, "monde": monde, "colon": colon}

func _nourriture_de(objets: Array) -> Dictionary:
	for objet in objets:
		if objet.get("proprietes_type", "") == "nourriture":
			return objet
	return {}

func _avancer_tick(colon: Dictionary, monde, config: Dictionary, etats: Dictionary, delta: float) -> Dictionary:
	var g := BancManger.agir_et_deplacer(colon, monde, _canaux, _profils_saillance, _actions, delta)
	return BancManger.avancer_repas(g.decision, colon, config, etats, delta)

# ---- Le colon mange la nourriture, son energie monte ----

func _le_colon_mange_la_nourriture_son_energie_monte() -> void:
	var scene := _fabriquer_scene()
	var colon: Dictionary = scene.colon
	var monde = scene.monde
	var energie_initiale: float = colon.proprietes.reserves.energie.reserve

	var a_mange := false
	for i in 200:
		var r := _avancer_tick(colon, monde, _donnees, _etats, 0.1)
		if r.mange:
			a_mange = true

	verif.v(a_mange, "chemin reel : le colon doit finir par manger (verbe 'manger' resolu, a portee)")
	verif.v(colon.proprietes.reserves.energie.reserve > energie_initiale, "chemin reel : l'energie du colon doit avoir monte")

# ---- La nourriture perd du contenu proportionnellement (meme quantite que l'energie gagnee) ----

func _la_nourriture_perd_du_contenu_proportionnellement() -> void:
	var scene := _fabriquer_scene()
	var colon: Dictionary = scene.colon
	var monde = scene.monde
	var objets: Array = scene.objets
	var nourriture := _nourriture_de(objets)
	var contenu_initial: float = nourriture.proprietes.reserves.contenu.reserve
	var energie_initiale: float = colon.proprietes.reserves.energie.reserve

	for i in 30:
		_avancer_tick(colon, monde, _donnees, _etats, 0.1)

	var contenu_apres: float = nourriture.proprietes.reserves.contenu.reserve
	var energie_apres: float = colon.proprietes.reserves.energie.reserve
	verif.v(contenu_apres < contenu_initial, "chemin reel : le contenu de la nourriture doit avoir baisse")
	var perdu := contenu_initial - contenu_apres
	var gagne := energie_apres - energie_initiale
	verif.v(is_equal_approx(perdu, gagne), "la perte de contenu doit exactement egaler le gain d'energie (meme 'quantite', voir consommer.gd) -- perdu=%.4f gagne=%.4f" % [perdu, gagne])

# ---- Quand le contenu atteint zero, transformation en reste_nourriture ----

func _quand_le_contenu_atteint_zero_transformee_en_reste() -> void:
	var scene := _fabriquer_scene()
	var colon: Dictionary = scene.colon
	var monde = scene.monde
	var objets: Array = scene.objets
	var nourriture := _nourriture_de(objets)

	var transforme := false
	for i in 400:
		var r := _avancer_tick(colon, monde, _donnees, _etats, 0.1)
		if r.source_epuisee and not transforme:
			transforme = BancManger.avancer_transformation_repas(nourriture, _donnees, _catalogue_types, _materiaux)

	verif.v(transforme, "chemin reel : la nourriture doit finir par etre transformee (contenu epuise)")
	verif.v(nourriture.get("proprietes_type", "") == "reste_nourriture", "l'objet transforme doit porter le type 'reste_nourriture'")
	verif.v(not nourriture.proprietes.has("reserves"), "une fois transforme, l'objet ne doit plus porter de canal 'reserves' (comportement produit.gd:transformer, proprietes.clear())")
	verif.v(not nourriture.proprietes.get("comestible", false), "une fois transforme en reste, l'objet ne doit plus etre comestible")

	# IDEMPOTENT : un second appel sur un objet deja transforme ne doit rien refaire.
	var re_transforme := BancManger.avancer_transformation_repas(nourriture, _donnees, _catalogue_types, _materiaux)
	verif.v(not re_transforme, "avancer_transformation_repas doit etre idempotent -- un objet deja transforme ne se transforme pas deux fois")

# ---- Le colon ignore bois/pierre : ni percus comme saillants, ni mangeables ----

func _le_colon_ne_percoit_ni_ne_mange_bois_ni_pierre() -> void:
	# Monde SANS nourriture -- seuls bois_manger/pierre_manger, ni l'un ni
	# l'autre ne porte "comestible" ni "profil_saillance" (voir data/
	# banc_manger.json). Le colon est place directement AU CONTACT du bois
	# (distance nulle) pour eliminer toute hypothese de "trop loin".
	var declarations := [
		{"id": "bois_test", "type": "bois_manger", "position": [0.0, 0.0, 0.0]},
		{"id": "pierre_test", "type": "pierre_manger", "position": [50.0, 0.0, 0.0]},
	]
	var objets := BancManger.fabriquer_objets(declarations, _catalogue_types, _materiaux, _proprietes_immuables)
	var monde := Monde.new()
	for objet in objets:
		monde.ajouter(objet, objet.get("proprietes_type", ""), objet.position)
	var colon := BancCommun.fabriquer_colon("colon_test", "colon", {"id": "colon_test", "position": [0.0, 0.0, 0.0], "poids_verbes": {"manger": 1.0}}, _catalogue_types)
	monde.ajouter(colon, "colon", colon.position)

	var d := BancManger.decider(colon, monde, _canaux, _profils_saillance, _actions)
	verif.v(d.resultats.is_empty(), "ni bois ni pierre ne doivent jamais produire de saillance (aucun profil_saillance)")
	verif.v(d.decision == null, "sans rien de saillant, la decision doit rester null -- bois/pierre jamais consideres")

	# Meme au contact, aucune consommation ne doit jamais se produire.
	var r := BancManger.avancer_repas(d.decision, colon, _donnees, _etats, 0.1)
	verif.v(not r.mange, "aucune consommation ne doit se produire sur bois/pierre")
	verif.v(objets[0].proprietes.get("comestibilite", 0.0) == 0.0, "bois doit porter comestibilite=0.0 (materiaux.json)")
	verif.v(objets[1].proprietes.get("comestibilite", 0.0) == 0.0, "pierre doit porter comestibilite=0.0 (materiaux.json)")

# ---- Un objet pourri (comestibilite ecrasee a 0.0) n'est jamais mange ----

func _un_objet_pourri_n_est_pas_mange() -> void:
	var scene := _fabriquer_scene()
	var colon: Dictionary = scene.colon
	var objets: Array = scene.objets
	var nourriture := _nourriture_de(objets)
	nourriture.proprietes["etats_actifs"] = ["pourri"]
	colon.position = nourriture.position

	var decision := {"action": "manger", "chose": nourriture, "type": "nourriture", "position": nourriture.position}
	var contenu_avant: float = nourriture.proprietes.reserves.contenu.reserve
	var energie_avant: float = colon.proprietes.reserves.energie.reserve

	var r := {}
	for i in 30:
		r = BancManger.avancer_repas(decision, colon, _donnees, _etats, 0.1)

	verif.v(not r.mange, "un objet pourri (comestibilite ecrasee a 0.0 par etat_effectif) ne doit jamais etre mange")
	verif.v(is_equal_approx(nourriture.proprietes.reserves.contenu.reserve, contenu_avant), "le contenu d'un objet pourri ne doit jamais bouger")
	verif.v(is_equal_approx(colon.proprietes.reserves.energie.reserve, energie_avant), "l'energie du colon ne doit jamais monter face a un objet pourri")
