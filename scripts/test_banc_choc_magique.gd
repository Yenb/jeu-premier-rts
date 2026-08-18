extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_choc_magique.gd
#
# Verrouille le cablage de banc_choc_magique.gd -- composition de trois
# mecanismes deja fermes (frappe.gd/seuil_etat.gd/produit.gd), AUCUN touche
# par ce chantier : ce fichier verrouille uniquement banc_choc_magique.gd
# (fabriquer_objets/objets_frappables/avancer_frappes/avancer_fracture),
# plus les catalogues de donnees partagees que ce chantier a etendus
# (sensibilite_magique sur verre_demo dans data/materiaux.json, "choc_magique"
# dans data/seuils_etat.json).

const BancChocMagique = preload("res://scripts/banc_choc_magique.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const CATALOGUE_SEUILS_ETAT := {
	"choc_magique": {
		"propriete_continue": "choc_magique_cumule",
		"seuil_propriete": "resistance_impact",
		"etat": "fracture",
	},
}

const CRITERES := [{"propriete": "sensibilite_magique", "poids": 1.0, "source": "materiau"}]

func _init() -> void:
	_objets_frappables_filtre_la_reserve_epuisee()
	_avancer_frappes_hors_de_portee_ne_touche_personne()
	_avancer_frappes_frappe_chaque_cible_a_sa_propre_position_et_cumule()
	_avancer_frappes_ignore_une_cible_deja_detruite()
	_avancer_frappes_deux_pulses_cumulent()
	_choc_sous_resistance_impact_ne_fracture_pas()
	_avancer_fracture_pose_l_etat_au_franchissement_du_seuil()
	_avancer_fracture_haute_fragilite_produit_transforme()
	_avancer_fracture_basse_fragilite_reste_deforme_sans_transformation()
	_fabrication_reelle_fusionne_resistance_impact_fragilite_sensibilite_magique()
	_chemin_reel_verre_casse_avant_bois_avant_fer_verre_produit_des_eclats()
	_sans_sort_rien_ne_casse()
	_donnees_reelles_banc_choc_magique_json()
	_donnees_reelles_catalogues_partages()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_choc_magique.gd -- chaque caster frappe uniquement sa propre cible, " +
		"une cible hors de portee ou deja detruite n'est jamais touchee, deux pulses cumulent " +
		"choc_magique_cumule, fracture au franchissement de resistance_impact, jamais sous le seuil, " +
		"fragilite haute (verre) produit des eclats, fragilite basse (bois/fer) reste deformee sans " +
		"transformation, fabrication reelle fusionne resistance_impact/fragilite/sensibilite_magique, " +
		"chemin reel : verre casse strictement avant bois, bois strictement avant fer, sans sort rien " +
		"ne casse, donnees reelles chargent correctement")
	quit(0)

func _objet(id: String, position: Vector3, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": position, "proprietes": proprietes}

func _proprietes_base(resistance_impact: float, fragilite: float, transformation_fracture: String, masse: float = 100.0) -> Dictionary:
	return {
		"resistance_impact": resistance_impact,
		"fragilite": fragilite,
		"resistance_compression": 100.0,
		"durete": 5.0,
		"choc_magique_cumule": 0.0,
		"etats_actifs": [],
		"transformation_fracture": transformation_fracture,
		"masse": masse,
		"reserves": {"integrite": {"reserve": 20.0, "cout_base": 0.0, "surcout_action": 0.0}},
	}

func _objets_frappables_filtre_la_reserve_epuisee() -> void:
	var vivant := _objet("a", Vector3.ZERO, {"reserves": {"integrite": {"reserve": 5.0}}})
	var mort := _objet("b", Vector3.ZERO, {"reserves": {"integrite": {"reserve": 0.0}}})
	var sans_reserve := _objet("c", Vector3.ZERO, {})
	var frappables := BancChocMagique.objets_frappables([vivant, mort, sans_reserve], "integrite")
	verif.v(frappables.size() == 1 and frappables[0].id == "a", "seul un objet avec reserve strictement positive doit rester frappable")

func _avancer_frappes_hors_de_portee_ne_touche_personne() -> void:
	# rayon_frappe negatif : meme la propre position d'un objet (distance 0)
	# ne doit jamais etre consideree "a portee" -- verifie que le rayon est
	# reellement respecte, pas court-circuite.
	var a := _objet("a", Vector3(10.0, 0.0, 0.0), _proprietes_base(5.0, 0.5, ""))
	var diagnostics := BancChocMagique.avancer_frappes([a], -1.0, CRITERES, {}, 1.5, "integrite")
	verif.v(diagnostics.is_empty(), "un rayon_frappe negatif ne doit jamais mettre quoi que ce soit a portee")
	verif.v(a.proprietes.choc_magique_cumule == 0.0, "sans frappe, choc_magique_cumule ne doit jamais bouger")

func _avancer_frappes_frappe_chaque_cible_a_sa_propre_position_et_cumule() -> void:
	var a := _objet("a", Vector3(-250.0, 0.0, 0.0), _proprietes_base(1.0, 0.9, ""))
	var b := _objet("b", Vector3(0.0, 0.0, 0.0), _proprietes_base(4.0, 0.3, ""))
	var c := _objet("c", Vector3(250.0, 0.0, 0.0), _proprietes_base(8.0, 0.2, ""))
	var diagnostics := BancChocMagique.avancer_frappes([a, b, c], 5.0, CRITERES, {}, 1.5, "integrite")
	verif.v(diagnostics.size() == 3, "chaque caster (un par cible, espacees de 250 unites, rayon 5.0) doit toucher exactement sa propre cible")
	verif.v(is_equal_approx(a.proprietes.choc_magique_cumule, 1.5), "a doit accumuler exactement degats (0.0 + 1.5)")
	verif.v(is_equal_approx(b.proprietes.choc_magique_cumule, 1.5), "b doit accumuler exactement degats, independamment de a/c")
	verif.v(is_equal_approx(c.proprietes.choc_magique_cumule, 1.5), "c doit accumuler exactement degats, independamment de a/b")
	verif.v(is_equal_approx(a.proprietes.reserves.integrite.reserve, 18.5), "Frappe.frapper doit soustraire les degats de la reserve nommee (20.0 - 1.5 = 18.5)")

func _avancer_frappes_ignore_une_cible_deja_detruite() -> void:
	var vivant := _objet("a", Vector3(-250.0, 0.0, 0.0), _proprietes_base(1.0, 0.9, ""))
	var mort := _objet("b", Vector3(0.0, 0.0, 0.0), _proprietes_base(4.0, 0.3, ""))
	mort.proprietes.reserves.integrite.reserve = 0.0
	var diagnostics := BancChocMagique.avancer_frappes([vivant, mort], 5.0, CRITERES, {}, 1.5, "integrite")
	verif.v(diagnostics.size() == 1 and diagnostics[0].cible.id == "a", "une cible deja detruite (reserve 0.0) ne doit plus jamais etre frappee")
	verif.v(mort.proprietes.choc_magique_cumule == 0.0, "une cible deja detruite ne doit jamais voir son cumul bouger")

func _avancer_frappes_deux_pulses_cumulent() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_base(50.0, 0.5, ""))
	BancChocMagique.avancer_frappes([a], 5.0, CRITERES, {}, 1.5, "integrite")
	BancChocMagique.avancer_frappes([a], 5.0, CRITERES, {}, 1.5, "integrite")
	verif.v(is_equal_approx(a.proprietes.choc_magique_cumule, 3.0), "deux pulses successifs doivent cumuler (1.5 + 1.5 = 3.0), jamais remplacer")

func _choc_sous_resistance_impact_ne_fracture_pas() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_base(10.0, 0.9, "prod_test"))
	a.proprietes.choc_magique_cumule = 4.0
	var resultat := BancChocMagique.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, {}, {}, {}, 0.5)
	verif.v(resultat.bascules.is_empty(), "un cumul de choc strictement sous resistance_impact ne doit jamais poser 'fracture' (4.0 < 10.0)")
	verif.v(not a.proprietes.etats_actifs.has("fracture"), "'fracture' ne doit pas etre actif sous le seuil")

func _avancer_fracture_pose_l_etat_au_franchissement_du_seuil() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_base(5.0, 0.1, ""))
	a.proprietes.choc_magique_cumule = 6.0
	var resultat := BancChocMagique.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, {}, {}, {}, 0.5)
	verif.v(resultat.bascules.has("a"), "un cumul de choc au-dela de resistance_impact doit basculer l'objet (6.0 > 5.0)")
	verif.v(a.proprietes.etats_actifs.has("fracture"), "'fracture' doit etre pose dans etats_actifs au franchissement")
	var resultat2 := BancChocMagique.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, {}, {}, {}, 0.5)
	verif.v(resultat2.bascules.is_empty(), "une fois pose, 'fracture' ne doit plus rebasculer -- choc_magique_cumule ne redescend jamais, jamais un aller-retour")

const TABLE_FICTIVE := {
	"produit_test": {"composition": [{"materiau": "materiau_produit_test", "volume": 1.0}]},
}
const MATERIAUX_FICTIFS := {
	"materiau_produit_test": {"densite": 2.0},
}
const TRANSFORMATIONS_FICTIVES := {
	"prod_test": {"a_zero": {"produire": {"type_produit": "produit_test", "rendement": 0.8}}},
}

func _avancer_fracture_haute_fragilite_produit_transforme() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_base(5.0, 0.9, "prod_test", 200.0))
	a.proprietes.choc_magique_cumule = 6.0
	var resultat := BancChocMagique.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, TRANSFORMATIONS_FICTIVES, TABLE_FICTIVE, MATERIAUX_FICTIFS, 0.5)
	verif.v(resultat.transformes.has("a"), "une fragilite au-dessus du seuil doit produire une transformation (Produit.transformer)")
	verif.v(a.proprietes.composition[0].materiau == "materiau_produit_test", "l'objet transforme doit porter la composition du type_produit configure")
	verif.v(abs(a.proprietes.masse - 200.0 * 0.8) < 0.01, "la masse produite doit valoir exactement rendement * masse_ancien")
	verif.v(not a.proprietes.has("resistance_impact"), "un objet transforme ne doit plus porter resistance_impact -- proprietes entierement remplacees")

func _avancer_fracture_basse_fragilite_reste_deforme_sans_transformation() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_base(5.0, 0.1, "prod_test", 200.0))
	a.proprietes.choc_magique_cumule = 6.0
	var resultat := BancChocMagique.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, TRANSFORMATIONS_FICTIVES, TABLE_FICTIVE, MATERIAUX_FICTIFS, 0.5)
	verif.v(resultat.bascules.has("a"), "l'objet doit tout de meme fracturer (etat pose)")
	verif.v(resultat.transformes.is_empty(), "une fragilite sous le seuil ne doit jamais produire de transformation, meme avec une transformation_fracture valide")
	verif.v(a.proprietes.has("resistance_impact"), "un objet non transforme doit garder toutes ses proprietes d'origine")
	verif.v(a.proprietes.masse == 200.0, "un objet non transforme ne doit jamais voir sa masse changer -- deformation seule, jamais de perte de matiere")

func _fabrication_reelle_fusionne_resistance_impact_fragilite_sensibilite_magique() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(materiaux.has("verre_demo"), "data/materiaux.json doit porter 'verre_demo'")
	verif.v(materiaux.verre_demo.has("sensibilite_magique"), "data/materiaux.json:verre_demo doit declarer sensibilite_magique")

	var objet_physique: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json")).get("objet_physique", {})
	var declarations := [
		{"id": "verre_t", "position": [0.0, 0.0, 0.0], "composition": [{"materiau": "verre_demo", "volume": 1.0}], "transformation_fracture": "fracture_verre"},
		{"id": "bois_t", "position": [10.0, 0.0, 0.0], "composition": [{"materiau": "bois", "volume": 1.0}], "transformation_fracture": ""},
		{"id": "fer_t", "position": [20.0, 0.0, 0.0], "composition": [{"materiau": "fer", "volume": 1.0}], "transformation_fracture": ""},
	]
	var objets := BancChocMagique.fabriquer_objets(declarations, objet_physique, materiaux, proprietes_immuables, "integrite", {"reserve": 20.0, "cout_base": 0.0, "surcout_action": 0.0})
	var verre: Dictionary = objets[0]
	var bois: Dictionary = objets[1]
	var fer: Dictionary = objets[2]

	verif.v(is_equal_approx(verre.proprietes.resistance_impact, 1.0), "verre reel doit fusionner resistance_impact=1.0 depuis materiaux.json")
	verif.v(is_equal_approx(verre.proprietes.fragilite, 0.9), "verre reel doit fusionner fragilite=0.9 depuis materiaux.json")
	verif.v(is_equal_approx(bois.proprietes.resistance_impact, 4.0), "bois reel doit fusionner resistance_impact=4.0 depuis materiaux.json")
	verif.v(is_equal_approx(fer.proprietes.resistance_impact, 8.0), "fer reel doit fusionner resistance_impact=8.0 depuis materiaux.json")

	verif.v(verre.proprietes.choc_magique_cumule == 0.0, "un objet fraichement fabrique doit demarrer a choc_magique_cumule=0.0")
	verif.v(verre.proprietes.etats_actifs.is_empty(), "un objet fraichement fabrique ne doit porter aucun etat actif")
	verif.v(verre.proprietes.transformation_fracture == "fracture_verre", "le verre doit porter sa propre declaration transformation_fracture")
	verif.v(bois.proprietes.transformation_fracture == "" and fer.proprietes.transformation_fracture == "", "bois et fer ne doivent declarer aucune transformation_fracture")
	verif.v(not is_same(verre.proprietes.reserves, bois.proprietes.reserves), "chaque objet fabrique doit avoir sa propre reserve, jamais un Dictionary partage")

func _chemin_reel_verre_casse_avant_bois_avant_fer_verre_produit_des_eclats() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	var objet_physique: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json")).get("objet_physique", {})
	var catalogue_types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var catalogue_seuils_etat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json"))
	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})

	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_choc_magique.json"))
	var objets := BancChocMagique.fabriquer_objets(config.objets, objet_physique, materiaux, proprietes_immuables, config.nom_reserve_integrite, config.reserve_integrite_defaut)
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet

	var pulses := 0
	var verre_fracture_a := -1
	var bois_fracture_a := -1
	var fer_fracture_a := -1
	while pulses < 20 and (verre_fracture_a < 0 or bois_fracture_a < 0 or fer_fracture_a < 0):
		BancChocMagique.avancer_frappes(objets, config.rayon_frappe, config.criteres, materiaux, config.degats, config.nom_reserve_integrite)
		var resultat := BancChocMagique.avancer_fracture(objets, catalogue_seuils_etat, transformations, catalogue_types, materiaux, config.seuil_fragilite_eclats)
		if resultat.bascules.has("verre_0") and verre_fracture_a < 0:
			verre_fracture_a = pulses
		if resultat.bascules.has("bois_0") and bois_fracture_a < 0:
			bois_fracture_a = pulses
		if resultat.bascules.has("fer_0") and fer_fracture_a < 0:
			fer_fracture_a = pulses
		pulses += 1

	verif.v(verre_fracture_a >= 0, "chemin reel : le verre doit finir par fracturer sous pulses repetes")
	verif.v(bois_fracture_a >= 0, "chemin reel : le bois doit finir par fracturer sous pulses repetes")
	verif.v(fer_fracture_a >= 0, "chemin reel : le fer doit finir par fracturer sous pulses repetes")
	verif.v(verre_fracture_a < bois_fracture_a, "chemin reel : le verre (resistance_impact 1.0) doit fracturer STRICTEMENT avant le bois (4.0)")
	verif.v(bois_fracture_a < fer_fracture_a, "chemin reel : le bois (resistance_impact 4.0) doit fracturer STRICTEMENT avant le fer (8.0)")
	verif.v(par_id.verre_0.proprietes.composition[0].materiau == "eclats_verre", "chemin reel : le verre fracture doit produire des eclats (fragilite 0.9, au-dessus du seuil)")
	verif.v(par_id.bois_0.proprietes.composition[0].materiau == "bois", "chemin reel : le bois fracture-mais-deforme doit rester du bois, jamais transforme (fragilite sous le seuil)")
	verif.v(par_id.fer_0.proprietes.composition[0].materiau == "fer", "chemin reel : le fer fracture-mais-deforme doit rester du fer, jamais transforme (fragilite sous le seuil)")
	verif.v(par_id.bois_0.proprietes.etats_actifs.has("fracture"), "chemin reel : le bois doit porter l'etat 'fracture' meme sans jamais se transformer")
	verif.v(par_id.fer_0.proprietes.etats_actifs.has("fracture"), "chemin reel : le fer doit porter l'etat 'fracture' meme sans jamais se transformer")

func _sans_sort_rien_ne_casse() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	var objet_physique: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json")).get("objet_physique", {})
	var catalogue_types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var catalogue_seuils_etat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json"))
	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_choc_magique.json"))
	var objets := BancChocMagique.fabriquer_objets(config.objets, objet_physique, materiaux, proprietes_immuables, config.nom_reserve_integrite, config.reserve_integrite_defaut)

	# SANS JAMAIS APPELER avancer_frappes -- seule avancer_fracture tourne,
	# de nombreuses fois : rien ne doit jamais fracturer.
	for i in 50:
		var resultat := BancChocMagique.avancer_fracture(objets, catalogue_seuils_etat, transformations, catalogue_types, materiaux, config.seuil_fragilite_eclats)
		verif.v(resultat.bascules.is_empty(), "sans sort actif (jamais de frappe), rien ne doit jamais fracturer")
	for objet in objets:
		verif.v(objet.proprietes.choc_magique_cumule == 0.0, "sans sort actif, choc_magique_cumule doit rester a 0.0 pour toujours")

func _donnees_reelles_banc_choc_magique_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_choc_magique.json"))
	verif.v(donnees.nom_reserve_integrite == "integrite", "data/banc_choc_magique.json doit declarer nom_reserve_integrite")
	verif.v(donnees.has("rayon_frappe") and donnees.rayon_frappe > 0.0, "data/banc_choc_magique.json doit declarer un rayon_frappe strictement positif")
	verif.v(donnees.has("intervalle_frappe") and donnees.intervalle_frappe > 0.0, "data/banc_choc_magique.json doit declarer un intervalle_frappe strictement positif")
	verif.v(donnees.has("degats") and donnees.degats > 0.0, "data/banc_choc_magique.json doit declarer des degats strictement positifs")
	verif.v(donnees.has("seuil_fragilite_eclats"), "data/banc_choc_magique.json doit declarer seuil_fragilite_eclats")
	verif.v(not donnees.criteres.is_empty(), "data/banc_choc_magique.json doit declarer au moins un critere pour Frappe.selectionner")
	verif.v(donnees.objets.size() == 3, "data/banc_choc_magique.json doit declarer trois objets (verre/bois/fer)")

	var par_id: Dictionary = {}
	for objet in donnees.objets:
		par_id[objet.id] = objet
	verif.v(par_id.has("verre_0") and par_id.has("bois_0") and par_id.has("fer_0"), "data/banc_choc_magique.json doit porter verre_0, bois_0 et fer_0")
	verif.v(par_id.verre_0.composition[0].materiau == "verre_demo", "verre_0 doit composer du verre_demo")
	verif.v(par_id.bois_0.composition[0].materiau == "bois", "bois_0 doit composer du bois")
	verif.v(par_id.fer_0.composition[0].materiau == "fer", "fer_0 doit composer du fer")
	verif.v(par_id.verre_0.get("transformation_fracture", "") == "fracture_verre", "verre_0 doit declarer transformation_fracture='fracture_verre'")
	verif.v(par_id.bois_0.get("transformation_fracture", "not_found") == "", "bois_0 ne doit declarer aucune transformation_fracture")
	verif.v(par_id.fer_0.get("transformation_fracture", "not_found") == "", "fer_0 ne doit declarer aucune transformation_fracture")

	var pos_verre := Vector3(par_id.verre_0.position[0], par_id.verre_0.position[1], par_id.verre_0.position[2])
	var pos_bois := Vector3(par_id.bois_0.position[0], par_id.bois_0.position[1], par_id.bois_0.position[2])
	var pos_fer := Vector3(par_id.fer_0.position[0], par_id.fer_0.position[1], par_id.fer_0.position[2])
	verif.v(pos_verre.distance_to(pos_bois) > donnees.rayon_frappe * 2.0, "verre_0 et bois_0 doivent etre espaces de plus de deux fois le rayon_frappe -- chaque caster ne doit jamais voir plus d'une cible")
	verif.v(pos_bois.distance_to(pos_fer) > donnees.rayon_frappe * 2.0, "bois_0 et fer_0 doivent etre espaces de plus de deux fois le rayon_frappe")

func _donnees_reelles_catalogues_partages() -> void:
	var seuils_etat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json"))
	verif.v(seuils_etat.has("choc_magique"), "data/seuils_etat.json doit porter l'entree 'choc_magique'")
	verif.v(seuils_etat.choc_magique.propriete_continue == "choc_magique_cumule", "data/seuils_etat.json:choc_magique doit comparer choc_magique_cumule")
	verif.v(seuils_etat.choc_magique.seuil_propriete == "resistance_impact", "data/seuils_etat.json:choc_magique doit lire le seuil PAR OBJET sur resistance_impact")
	verif.v(seuils_etat.choc_magique.etat == "fracture", "data/seuils_etat.json:choc_magique doit poser le MEME etat 'fracture' que les entrees mecanique et sonore")
	verif.v(seuils_etat.has("fracture") and seuils_etat.has("fracture_sonore"), "data/seuils_etat.json doit toujours porter les deux entrees precedentes (coexistence, jamais un remplacement)")

	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	verif.v(etats.has("fracture") and not etats.fracture.has("duree"), "'fracture' reste irreversible (aucune duree), quel que soit le chemin qui l'a pose")

	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	verif.v(materiaux.verre_demo.has("sensibilite_magique"), "data/materiaux.json:verre_demo doit declarer sensibilite_magique")
	verif.v(materiaux.bois.has("sensibilite_magique") and materiaux.fer.has("sensibilite_magique"), "bois et fer doivent deja declarer sensibilite_magique (fondation dormante preexistante)")
