extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_agir_proximite.gd
#
# Un colon sans aucune attache : seule la saillance de proximite existe
# pour lui. Verifie qu'agir.gd ne suppose rien sur l'origine d'une
# saillance (aucune lecture de "attache") ET resout le verbe de la
# branche proximite depuis une PROPRIETE portee par la chose percue,
# jamais depuis son nom de type -- meme fermeture que attaches.gd
# (voir docs/design.md, "Les archetypes n'existent pas"). Le catalogue
# d'actions est desormais indexe par propriete ("brule"), comme
# data/types_attaches.json l'est par "irremplacable"/"notre_ouvrage".
# Chaque entree porte une LISTE de verbes ("verbes", voir agir.gd),
# arbitree par colon.proprietes.poids_verbes (morceau 2) : le verbe au
# poids le plus haut STRICTEMENT POSITIF l'emporte, jamais le premier de
# la liste par defaut -- _poids_opposes_choisissent_des_verbes_differents
# verrouille que deux colons face aux memes visibles, poids opposes sur
# la meme propriete, retiennent des verbes differents.

const Attaches = preload("res://scripts/attaches.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()
var monde_vide := Monde.new()

func _init() -> void:
	# Table de fabrication (equivalent local a data/types.json) : "brule"
	# est la propriete portee par l'objet, jamais lue par son nom de type.
	# "profil_saillance" reference une entree du catalogue de saillance
	# (equivalent local a data/profils_saillance.json), jamais une valeur
	# copiee sur l'instance -- voir scripts/proximite.gd.
	var catalogue_fabrication := {
		"feu": {"profil_saillance": "feu", "brule": true},
	}
	var profils_saillance := {
		"feu": {"saillance_intrinseque": 4.0, "portee_saillance": 50.0},
	}
	# Catalogue d'actions (equivalent local a data/types_choses.json) :
	# indexe par PROPRIETE, jamais par type -- agir.gd scanne ces cles
	# contre chose.proprietes.
	var catalogue_actions := {
		"brule": {"verbes": ["fuir"]},
	}
	var colon := {
		"proprietes": {"attaches": [], "forme": {}, "poids_verbes": {"fuir": 1.0}},
	}

	var feu := Objet.fabriquer("feu_proche", "feu", Vector3(10, 0, 0), catalogue_fabrication)
	var perceptions := [
		{"chose": feu, "type": "feu", "position": Vector3(10, 0, 0), "distance": 10.0},
	]

	var att := Attaches.evaluer(perceptions, colon, {})
	var prox := Proximite.evaluer(perceptions, colon, profils_saillance, {})
	var resultats: Array = att + prox

	var vus := Dominance.visibles(resultats, colon)
	var retenu = Agir.choisir(vus, colon, catalogue_actions, monde_vide)

	verif.v(retenu != null, "le colon doit agir")
	if retenu != null:
		verif.v(retenu.action == "fuir", "action resolue depuis la propriete 'brule', pas depuis le type 'feu'")
		verif.v(not retenu.has("attache"), "aucune attache : le champ n'existe pas et n'est pas invente")
		verif.v(retenu.chose.id == "feu_proche", "cible : le feu proche")

	_meme_propriete_sur_type_invente()
	_type_absent_du_catalogue_ne_plante_pas()
	_poids_opposes_choisissent_des_verbes_differents()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: colon sans attache agit sur %s (action=%s) sans planter, verbe resolu par propriete" % [retenu.chose.id, retenu.action])
	quit(0)

# Hors domaine : une chose dont le NOM DE TYPE n'a jamais ete vu ailleurs
# dans le moteur, portant seulement la propriete "brule", doit etre
# actionnable par cette seule propriete -- preuve qu'agir.gd ne lit aucun
# nom de type dans la branche proximite.
func _meme_propriete_sur_type_invente() -> void:
	var catalogue_actions := {"brule": {"verbes": ["fuir"]}}
	var colon := {"proprietes": {"attaches": [], "forme": {}, "poids_verbes": {"fuir": 1.0}}}
	var chose := Objet.fabriquer("rocher_chaud", "rocher_chaud", Vector3(5, 0, 0), {
		"rocher_chaud": {"profil_saillance": "rocher_chaud", "brule": true},
	})
	var profils_saillance := {"rocher_chaud": {"saillance_intrinseque": 2.0, "portee_saillance": 30.0}}
	var perceptions := [
		{"chose": chose, "type": "rocher_chaud", "position": Vector3(5, 0, 0), "distance": 5.0},
	]
	var prox := Proximite.evaluer(perceptions, colon, profils_saillance, {})
	var vus := Dominance.visibles(prox, colon)
	var retenu = Agir.choisir(vus, colon, catalogue_actions, monde_vide)
	verif.v(retenu != null and retenu.action == "fuir",
		"un type jamais vu ailleurs, portant seulement 'brule', doit etre actionnable par la seule propriete")

# Une chose saillante SANS aucune propriete du catalogue est un cas
# LEGITIME (chose ordinaire) : action vide, aucune alarme, aucun plantage.
func _type_absent_du_catalogue_ne_plante_pas() -> void:
	var catalogue_actions := {"brule": {"verbes": ["fuir"]}}
	var colon := {"proprietes": {"attaches": [], "forme": {}}}
	var chose := Objet.fabriquer("cristal", "cristal", Vector3(5, 0, 0), {
		"cristal": {"profil_saillance": "cristal"},
	})
	var profils_saillance := {"cristal": {"saillance_intrinseque": 2.0, "portee_saillance": 30.0}}
	var perceptions := [
		{"chose": chose, "type": "cristal", "position": Vector3(5, 0, 0), "distance": 5.0},
	]
	var prox := Proximite.evaluer(perceptions, colon, profils_saillance, {})
	var vus := Dominance.visibles(prox, colon)
	var retenu = Agir.choisir(vus, colon, catalogue_actions, monde_vide)
	verif.v(retenu != null, "une chose saillante sans propriete actionnable doit quand meme etre choisie")
	if retenu != null:
		verif.v(retenu.action == "", "aucune propriete actionnable : action vide, cas legitime, pas d'alarme")

# Verrouille le morceau 2 : le verbe retenu depend du poids du COLON, pas
# de l'ordre de la liste. Deux colons, memes visibles (le meme feu),
# poids opposes sur la MEME propriete ("brule", deux verbes) : chacun
# retient un verbe different. Sans les poids (comportement du morceau 1,
# toujours le premier de la liste), les deux colons resoudraient
# "eteindre" -- ce test echouerait sur l'assertion du colon B.
func _poids_opposes_choisissent_des_verbes_differents() -> void:
	var catalogue_actions := {"brule": {"verbes": ["eteindre", "attiser"]}}
	var chose := Objet.fabriquer("feu_commun", "feu", Vector3(5, 0, 0), {
		"feu": {"profil_saillance": "feu", "brule": true},
	})
	var profils_saillance := {"feu": {"saillance_intrinseque": 4.0, "portee_saillance": 50.0}}
	var perceptions := [
		{"chose": chose, "type": "feu", "position": Vector3(5, 0, 0), "distance": 5.0},
	]
	# Saillance PARTAGEE par colon_a/colon_b (declares plus bas) : aucun des
	# deux ne porte de deformation ici, le colon passe pour ce calcul n'a
	# donc aucun effet -- voir PHASE 4 piece 3, proximite.gd:_appliquer_deformation.
	var prox := Proximite.evaluer(perceptions, {"proprietes": {}}, profils_saillance, {})

	var colon_a := {
		"proprietes": {"attaches": [], "forme": {}, "poids_verbes": {"eteindre": 2.0, "attiser": 0.0}},
	}
	var colon_b := {
		"proprietes": {"attaches": [], "forme": {}, "poids_verbes": {"eteindre": 0.0, "attiser": 2.0}},
	}

	var retenu_a = Agir.choisir(Dominance.visibles(prox, colon_a), colon_a, catalogue_actions, monde_vide)
	var retenu_b = Agir.choisir(Dominance.visibles(prox, colon_b), colon_b, catalogue_actions, monde_vide)

	verif.v(retenu_a != null and retenu_a.action == "eteindre",
		"poids fort sur eteindre (premier de la liste) : le colon A retient eteindre")
	verif.v(retenu_b != null and retenu_b.action == "attiser",
		"poids fort sur attiser (verbe SECOND de la liste) : le colon B retient attiser -- " +
		"sans les poids, ce test echouerait (le premier de la liste l'emporterait toujours)")
