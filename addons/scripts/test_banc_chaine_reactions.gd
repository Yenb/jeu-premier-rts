extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_chaine_reactions.gd
#
# Verrouille le cablage de banc_chaine_reactions.gd -- ce fichier ne fait
# plus QU'UN SEUL appel par tick a scripts/reaction.gd:detecter_et_reagir
# (mecanisme du COEUR, verrouille SEPAREMENT et hors domaine par
# scripts/test_reaction.gd). Ce test-ci verrouille uniquement : la
# fabrication des trois objets reels, le basculement de position, le
# diagnostic d'affichage, et le CHEMIN REEL de la cascade a deux etages sur
# les vraies donnees du depot (data/reactions.json/materiaux.json/types.json).
#
# AUCUN MECANISME DU COEUR TOUCHE : scripts/reaction.gd/charge.gd/
# produit.gd/objet.gd restent exactement ceux deja verrouilles par leurs
# propres tests.

const BancChaineReactions = preload("res://scripts/banc_chaine_reactions.gd")
const Reaction = preload("res://scripts/reaction.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DECLARATIONS := [
	{ "id": "alpha", "position_proche": [0.0, 0.0, 0.0], "position_loin": [0.0, -5000.0, 0.0], "composition": [ { "materiau": "alpha_mat", "volume": 2.0 } ] },
	{ "id": "beta", "position_proche": [1.0, 0.0, 0.0], "position_loin": [1.0, 0.0, 0.0], "composition": [ { "materiau": "beta_mat", "volume": 3.0 } ] },
]

const MATERIAUX_LOCAUX := {
	"alpha_mat": { "densite": 1.0, "reactivite": 1.0 },
	"beta_mat": { "densite": 1.0, "reactivite": 1.0 },
}

func _init() -> void:
	_materiau_de_lit_le_premier_element_de_la_composition()
	_fabriquer_objets_cree_autant_dobjets_que_de_declarations()
	_fabriquer_objets_fusionne_reactivite_depuis_les_proprietes_immuables()
	_basculer_positions_deplace_chaque_objet_selon_sa_propre_declaration()
	_basculer_positions_ignore_un_objet_sans_declaration()
	_diagnostiquer_sans_canal_rend_a_un_canal_faux()
	_diagnostiquer_avec_canal_lit_charge_et_seuil()

	_chemin_reel_cascade_a_deux_etages()
	_chemin_reel_hors_portee_rien_ne_reagit()
	_donnees_reelles()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_chaine_reactions.gd fabrique/bascule/diagnostique correctement, le chemin reel produit " +
		"acide_demo+fer->sel_metallique puis sel_metallique+eau_demo->sel_dissous en deux etages successifs, " +
		"hors de portee rien ne reagit jamais, et les catalogues partages chargent correctement")
	quit(0)

func _materiau_de_lit_le_premier_element_de_la_composition() -> void:
	var objet := {"id": "x", "position": Vector3.ZERO, "proprietes": {"composition": [{"materiau": "truc_zorg", "volume": 1.0}]}}
	verif.v(BancChaineReactions.materiau_de(objet) == "truc_zorg", "materiau_de doit lire composition[0].materiau")
	var vide := {"id": "y", "position": Vector3.ZERO, "proprietes": {}}
	verif.v(BancChaineReactions.materiau_de(vide) == "", "materiau_de sans composition doit rendre une chaine vide")

func _fabriquer_objets_cree_autant_dobjets_que_de_declarations() -> void:
	var objets := BancChaineReactions.fabriquer_objets(DECLARATIONS, false, MATERIAUX_LOCAUX, [])
	verif.v(objets.size() == 2, "fabriquer_objets doit produire un objet par declaration")
	var ids: Array = []
	for o in objets:
		ids.append(o.id)
	verif.v(ids.has("alpha") and ids.has("beta"), "fabriquer_objets doit reprendre les ids declares")

func _fabriquer_objets_fusionne_reactivite_depuis_les_proprietes_immuables() -> void:
	var objets := BancChaineReactions.fabriquer_objets(DECLARATIONS, false, MATERIAUX_LOCAUX, ["reactivite"])
	for o in objets:
		verif.v(is_equal_approx(o.proprietes.get("reactivite", -1.0), 1.0),
			"avec 'reactivite' dans proprietes_immuables, chaque objet fabrique doit porter sa reactivite fusionnee")

func _basculer_positions_deplace_chaque_objet_selon_sa_propre_declaration() -> void:
	var objets := BancChaineReactions.fabriquer_objets(DECLARATIONS, false, MATERIAUX_LOCAUX, [])
	BancChaineReactions.basculer_positions(objets, DECLARATIONS, true)
	var alpha: Dictionary = objets[0]
	var beta: Dictionary = objets[1]
	verif.v(is_equal_approx(alpha.position.x, 0.0) and is_equal_approx(alpha.position.y, 0.0),
		"proche : alpha doit prendre sa position_proche")
	verif.v(is_equal_approx(beta.position.x, 1.0) and is_equal_approx(beta.position.y, 0.0),
		"beta a la meme position_proche/position_loin (objet fixe) : ne doit jamais bouger")
	BancChaineReactions.basculer_positions(objets, DECLARATIONS, false)
	verif.v(is_equal_approx(alpha.position.y, -5000.0), "loin : alpha doit prendre sa position_loin")

func _basculer_positions_ignore_un_objet_sans_declaration() -> void:
	var objets := [{"id": "inconnu", "position": Vector3(9.0, 9.0, 9.0), "proprietes": {}}]
	BancChaineReactions.basculer_positions(objets, DECLARATIONS, true)
	verif.v(is_equal_approx(objets[0].position.x, 9.0), "un objet sans declaration correspondante ne doit jamais bouger")

func _diagnostiquer_sans_canal_rend_a_un_canal_faux() -> void:
	var objet := {"id": "x", "position": Vector3.ZERO, "proprietes": {"composition": [{"materiau": "m", "volume": 1.0}], "reactivite": 0.4}}
	var diag := BancChaineReactions.diagnostiquer(objet)
	verif.v(not diag.a_un_canal, "sans canal 'reaction', a_un_canal doit etre faux")
	verif.v(is_equal_approx(diag.reactivite, 0.4), "diagnostiquer doit lire la reactivite courante")
	verif.v(diag.profondeur_chaine == 0, "sans _profondeur_chaine, le diagnostic doit rendre 0")

func _diagnostiquer_avec_canal_lit_charge_et_seuil() -> void:
	var objet := {
		"id": "x", "position": Vector3.ZERO,
		"proprietes": {
			"composition": [{"materiau": "m", "volume": 1.0}],
			"_profondeur_chaine": 2,
			"etats": {"reaction": {"charge": 0.6, "seuil": 1.0}},
		},
	}
	var diag := BancChaineReactions.diagnostiquer(objet)
	verif.v(diag.a_un_canal, "avec un canal 'reaction' present, a_un_canal doit etre vrai")
	verif.v(is_equal_approx(diag.charge, 0.6) and is_equal_approx(diag.seuil, 1.0), "diagnostiquer doit lire charge/seuil du canal")
	verif.v(diag.profondeur_chaine == 2, "diagnostiquer doit lire _profondeur_chaine tel quel")

# ---- Chemin reel : vraies donnees du depot ----

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _chemin_reel_cascade_a_deux_etages() -> void:
	var config: Dictionary = _charger_json("res://data/banc_chaine_reactions.json")
	var reactions: Array = _charger_json("res://data/reactions.json").get("reactions", [])
	var table: Dictionary = _charger_json("res://data/types.json")
	var materiaux: Dictionary = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	var objets := BancChaineReactions.fabriquer_objets(config.objets, true, materiaux, proprietes_immuables)
	var par_id: Dictionary = {}
	for o in objets:
		par_id[o.id] = o

	var vu_sel_metallique := false
	var vu_sel_dissous := false
	for i in range(400):
		var transformations := Reaction.detecter_et_reagir(objets, reactions, 0.3, int(config.profondeur_chaine_max), table, materiaux)
		for t in transformations:
			if t.type_produit == "sel_metallique":
				vu_sel_metallique = true
			if t.type_produit == "sel_dissous":
				vu_sel_dissous = true
		if vu_sel_dissous:
			break

	verif.v(vu_sel_metallique, "chemin reel : acide_demo+fer doit finir par produire sel_metallique")
	verif.v(vu_sel_dissous, "chemin reel : sel_metallique+eau_demo doit finir par produire sel_dissous -- preuve du chainage automatique")
	verif.v(BancChaineReactions.materiau_de(par_id.fer) == "sel_dissous",
		"chemin reel : l'objet 'fer' d'origine doit porter finalement le materiau sel_dissous (meme id, deux transformations successives)")
	verif.v(int(par_id.fer.proprietes.get("_profondeur_chaine", -1)) == 2,
		"chemin reel : apres deux etages de reaction, _profondeur_chaine doit valoir exactement 2")
	verif.v(BancChaineReactions.materiau_de(par_id.acide_demo) == "acide_demo",
		"chemin reel : acide_demo (materiau_a des deux entrees ou il figure) ne doit JAMAIS etre transforme")
	verif.v(BancChaineReactions.materiau_de(par_id.eau_demo) == "eau_demo",
		"chemin reel : eau_demo (materiau_a de la deuxieme entree) ne doit JAMAIS etre transforme")

func _chemin_reel_hors_portee_rien_ne_reagit() -> void:
	var config: Dictionary = _charger_json("res://data/banc_chaine_reactions.json")
	var reactions: Array = _charger_json("res://data/reactions.json").get("reactions", [])
	var table: Dictionary = _charger_json("res://data/types.json")
	var materiaux: Dictionary = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	var objets := BancChaineReactions.fabriquer_objets(config.objets, false, materiaux, proprietes_immuables)
	var par_id: Dictionary = {}
	for o in objets:
		par_id[o.id] = o

	for i in range(100):
		Reaction.detecter_et_reagir(objets, reactions, 0.3, int(config.profondeur_chaine_max), table, materiaux)

	verif.v(BancChaineReactions.materiau_de(par_id.fer) == "fer", "hors de portee_reaction, fer ne doit jamais devenir sel_metallique")
	verif.v(BancChaineReactions.materiau_de(par_id.acide_demo) == "acide_demo", "hors portee, acide_demo reste acide_demo")
	verif.v(BancChaineReactions.materiau_de(par_id.eau_demo) == "eau_demo", "hors portee, eau_demo reste eau_demo")

func _donnees_reelles() -> void:
	var config: Dictionary = _charger_json("res://data/banc_chaine_reactions.json")
	verif.v(config.has("profondeur_chaine_max") and int(config.profondeur_chaine_max) > 0,
		"data/banc_chaine_reactions.json doit declarer profondeur_chaine_max strictement positif")
	var ids: Array = []
	for decl in config.get("objets", []):
		ids.append(decl.id)
	verif.v(ids.has("acide_demo") and ids.has("fer") and ids.has("eau_demo"),
		"data/banc_chaine_reactions.json doit declarer acide_demo/fer/eau_demo")

	var reactions: Array = _charger_json("res://data/reactions.json").get("reactions", [])
	var trouve_cascade := false
	for entree in reactions:
		if entree.materiau_a == "eau_demo" and entree.materiau_b == "sel_metallique" and entree.type_produit == "sel_dissous":
			trouve_cascade = true
	verif.v(trouve_cascade, "data/reactions.json doit porter l'entree eau_demo+sel_metallique->sel_dissous")

	var materiaux: Dictionary = _charger_json("res://data/materiaux.json")
	for nom in ["eau_demo", "sel_dissous"]:
		verif.v(materiaux.has(nom), "data/materiaux.json doit porter l'entree '%s'" % nom)
	verif.v(materiaux.get("sel_metallique", {}).has("reactivite"),
		"data/materiaux.json : sel_metallique doit desormais porter 'reactivite' (n'est plus un materiau terminal)")

	var types_catalogue: Dictionary = _charger_json("res://data/types.json")
	verif.v(types_catalogue.has("sel_dissous"), "data/types.json doit porter le type 'sel_dissous'")
