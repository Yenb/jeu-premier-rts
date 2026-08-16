extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_fracture.gd
#
# Verrouille le cablage de banc_fracture.gd -- composition de trois
# mecanismes deja fermes (frappe.gd/seuil_etat.gd/produit.gd), AUCUN
# touche par ce chantier : ce fichier verrouille uniquement
# banc_fracture.gd (fabriquer_objets/objets_frappables/avancer_frappe/
# avancer_fracture), plus les catalogues de donnees partagees que ce
# chantier a etendus (resistance_impact/fragilite/resistance_compression
# dans data/proprietes_immuables_composition.json, "fracture" dans
# data/etats.json/data/seuils_etat.json, "fracture_pierre"/"eclats_pierre"
# dans data/transformations.json/data/materiaux.json/data/types.json).

const BancFracture = preload("res://scripts/banc_fracture.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const CATALOGUE_SEUILS_ETAT := {
	"fracture": {
		"propriete_continue": "degats_impact_cumules",
		"seuil_propriete": "resistance_impact",
		"etat": "fracture",
	},
}

func _init() -> void:
	_objets_frappables_filtre_la_reserve_epuisee()
	_avancer_frappe_hors_de_portee_rend_dictionnaire_vide()
	_avancer_frappe_selectionne_a_portee_et_cumule_les_degats()
	_avancer_frappe_deux_coups_cumulent()
	_un_objet_jamais_frappe_ne_fracture_jamais()
	_degats_sous_resistance_impact_ne_fracture_pas()
	_avancer_fracture_pose_l_etat_au_franchissement_du_seuil()
	_avancer_fracture_haute_fragilite_produit_transforme()
	_avancer_fracture_basse_fragilite_reste_deforme_sans_transformation()
	_fabrication_reelle_fusionne_resistance_impact_fragilite_resistance_compression()
	_chemin_reel_pierre_casse_avant_le_fer_et_produit_des_eclats_le_fer_se_deforme_sans_eclats()
	_donnees_reelles_banc_fracture_json()
	_donnees_reelles_catalogues_partages()
	_positions_eclats_fixe_et_deterministe()
	_offset_secousse_deterministe_et_s_eteint_a_zero()
	_teinte_flash_actif_domine_tout()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_fracture.gd -- selection/cumul de degats, fracture au franchissement de resistance_impact, " +
		"fragilite haute produit des eclats (Produit.transformer), fragilite basse reste deformee sans transformation, " +
		"objet jamais frappe ou sous le seuil ne fracture jamais, " +
		"fabrication reelle fusionne resistance_impact/fragilite/resistance_compression, chemin reel : la pierre " +
		"casse avant le fer et produit des eclats, le fer se deforme sans jamais se transformer, donnees reelles " +
		"chargent correctement, la grappe d'eclats et la secousse de camera sont deterministes (aucun hasard), " +
		"le flash domine tout autre etat visuel")
	quit(0)

func _objet(id: String, position: Vector3, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": position, "proprietes": proprietes}

func _proprietes_base(resistance_impact: float, fragilite: float, transformation_fracture: String, masse: float = 100.0) -> Dictionary:
	return {
		"resistance_impact": resistance_impact,
		"fragilite": fragilite,
		"resistance_compression": 100.0,
		"durete": 5.0,
		"degats_impact_cumules": 0.0,
		"etats_actifs": [],
		"transformation_fracture": transformation_fracture,
		"masse": masse,
		"reserves": {"integrite": {"reserve": 20.0, "cout_base": 0.0, "surcout_action": 0.0}},
	}

func _objets_frappables_filtre_la_reserve_epuisee() -> void:
	var vivant := _objet("a", Vector3.ZERO, {"reserves": {"integrite": {"reserve": 5.0}}})
	var mort := _objet("b", Vector3.ZERO, {"reserves": {"integrite": {"reserve": 0.0}}})
	var sans_reserve := _objet("c", Vector3.ZERO, {})
	var frappables := BancFracture.objets_frappables([vivant, mort, sans_reserve], "integrite")
	verif.v(frappables.size() == 1 and frappables[0].id == "a", "seul un objet avec reserve strictement positive doit rester frappable")

func _config_frappe() -> Dictionary:
	return {
		"nom_reserve_integrite": "integrite",
		"rayon_frappe": 50.0,
		"degats": 3.0,
		"criteres": [{"poids": 1.0, "source": "position_z"}],
	}

func _avancer_frappe_hors_de_portee_rend_dictionnaire_vide() -> void:
	var objets := [_objet("a", Vector3(1000.0, 0.0, 0.0), _proprietes_base(5.0, 0.5, ""))]
	var resultat := BancFracture.avancer_frappe(objets, Vector3.ZERO, _config_frappe(), {})
	verif.v(resultat.is_empty(), "aucun objet a portee du point de clic doit rendre un Dictionary vide, rien ne se passe")
	verif.v(objets[0].proprietes.degats_impact_cumules == 0.0, "un objet hors de portee ne doit jamais voir son cumul de degats bouger")

func _avancer_frappe_selectionne_a_portee_et_cumule_les_degats() -> void:
	var a := _objet("a", Vector3(10.0, 0.0, 0.0), _proprietes_base(5.0, 0.5, ""))
	var b := _objet("b", Vector3(1000.0, 0.0, 0.0), _proprietes_base(5.0, 0.5, ""))
	var resultat := BancFracture.avancer_frappe([a, b], Vector3.ZERO, _config_frappe(), {})
	verif.v(resultat.get("cible", {}).get("id", "") == "a", "le clic pres de 'a' doit selectionner 'a', jamais 'b' hors de portee")
	verif.v(is_equal_approx(a.proprietes.reserves.integrite.reserve, 17.0), "Frappe.frapper doit soustraire les degats de la reserve nommee (20.0 - 3.0 = 17.0)")
	verif.v(is_equal_approx(a.proprietes.degats_impact_cumules, 3.0), "le cablage doit ecrire lui-meme degats_impact_cumules += degats (0.0 + 3.0 = 3.0), frappe.gd ne le fait jamais")
	verif.v(b.proprietes.degats_impact_cumules == 0.0, "l'objet non selectionne ne doit jamais voir son cumul bouger")

func _avancer_frappe_deux_coups_cumulent() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_base(50.0, 0.5, ""))
	BancFracture.avancer_frappe([a], Vector3.ZERO, _config_frappe(), {})
	BancFracture.avancer_frappe([a], Vector3.ZERO, _config_frappe(), {})
	verif.v(is_equal_approx(a.proprietes.degats_impact_cumules, 6.0), "deux coups successifs doivent cumuler (3.0 + 3.0 = 6.0), jamais remplacer")

func _un_objet_jamais_frappe_ne_fracture_jamais() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_base(5.0, 0.9, "prod_test"))
	for i in 20:
		var resultat := BancFracture.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, {}, {}, {}, 0.5)
		verif.v(resultat.bascules.is_empty(), "un objet jamais frappe (degats_impact_cumules toujours 0.0) ne doit jamais fracturer")
	verif.v(not a.proprietes.etats_actifs.has("fracture"), "sans jamais avoir ete frappe, 'fracture' ne doit jamais etre pose")

func _degats_sous_resistance_impact_ne_fracture_pas() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_base(10.0, 0.9, "prod_test"))
	a.proprietes.degats_impact_cumules = 4.0
	var resultat := BancFracture.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, {}, {}, {}, 0.5)
	verif.v(resultat.bascules.is_empty(), "un cumul de degats strictement sous resistance_impact ne doit jamais poser 'fracture' (4.0 < 10.0)")
	verif.v(not a.proprietes.etats_actifs.has("fracture"), "'fracture' ne doit pas etre actif sous le seuil")

func _avancer_fracture_pose_l_etat_au_franchissement_du_seuil() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_base(5.0, 0.1, ""))
	a.proprietes.degats_impact_cumules = 6.0
	var resultat := BancFracture.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, {}, {}, {}, 0.5)
	verif.v(resultat.bascules.has("a"), "un cumul de degats au-dela de resistance_impact doit basculer l'objet (6.0 > 5.0)")
	verif.v(a.proprietes.etats_actifs.has("fracture"), "'fracture' doit etre pose dans etats_actifs au franchissement")
	var resultat2 := BancFracture.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, {}, {}, {}, 0.5)
	verif.v(resultat2.bascules.is_empty(), "une fois pose, 'fracture' ne doit plus rebasculer -- degats_impact_cumules ne redescend jamais, jamais un aller-retour")

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
	a.proprietes.degats_impact_cumules = 6.0
	var resultat := BancFracture.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, TRANSFORMATIONS_FICTIVES, TABLE_FICTIVE, MATERIAUX_FICTIFS, 0.5)
	verif.v(resultat.transformes.has("a"), "une fragilite au-dessus du seuil doit produire une transformation (Produit.transformer)")
	verif.v(a.proprietes.composition[0].materiau == "materiau_produit_test", "l'objet transforme doit porter la composition du type_produit configure")
	verif.v(abs(a.proprietes.masse - 200.0 * 0.8) < 0.01, "la masse produite doit valoir exactement rendement * masse_ancien")
	verif.v(not a.proprietes.has("resistance_impact"), "un objet transforme ne doit plus porter resistance_impact -- proprietes entierement remplacees")

func _avancer_fracture_basse_fragilite_reste_deforme_sans_transformation() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_base(5.0, 0.1, "prod_test", 200.0))
	a.proprietes.degats_impact_cumules = 6.0
	var resultat := BancFracture.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, TRANSFORMATIONS_FICTIVES, TABLE_FICTIVE, MATERIAUX_FICTIFS, 0.5)
	verif.v(resultat.bascules.has("a"), "l'objet doit tout de meme fracturer (etat pose)")
	verif.v(resultat.transformes.is_empty(), "une fragilite sous le seuil ne doit jamais produire de transformation, meme avec une transformation_fracture valide")
	verif.v(a.proprietes.has("resistance_impact"), "un objet non transforme doit garder toutes ses proprietes d'origine")
	verif.v(a.proprietes.masse == 200.0, "un objet non transforme ne doit jamais voir sa masse changer -- deformation seule, jamais de perte de matiere")

func _fabrication_reelle_fusionne_resistance_impact_fragilite_resistance_compression() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(proprietes_immuables.has("resistance_impact"), "data/proprietes_immuables_composition.json doit lister resistance_impact")
	verif.v(proprietes_immuables.has("fragilite"), "data/proprietes_immuables_composition.json doit lister fragilite")
	verif.v(proprietes_immuables.has("resistance_compression"), "data/proprietes_immuables_composition.json doit lister resistance_compression")

	var objet_physique: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json")).get("objet_physique", {})
	var declarations := [
		{"id": "fer_t", "position": [0.0, 0.0, 0.0], "composition": [{"materiau": "fer", "volume": 1.0}], "transformation_fracture": ""},
		{"id": "pierre_t", "position": [10.0, 0.0, 0.0], "composition": [{"materiau": "pierre", "volume": 1.0}], "transformation_fracture": "fracture_pierre"},
	]
	var objets := BancFracture.fabriquer_objets(declarations, objet_physique, materiaux, proprietes_immuables, "integrite", {"reserve": 20.0, "cout_base": 0.0, "surcout_action": 0.0})
	var fer: Dictionary = objets[0]
	var pierre: Dictionary = objets[1]

	verif.v(is_equal_approx(fer.proprietes.resistance_impact, 8.0), "fer reel doit fusionner resistance_impact=8.0 depuis materiaux.json")
	verif.v(is_equal_approx(fer.proprietes.fragilite, 0.2), "fer reel doit fusionner fragilite=0.2 depuis materiaux.json")
	verif.v(is_equal_approx(fer.proprietes.resistance_compression, 400.0), "fer reel doit fusionner resistance_compression=400.0 depuis materiaux.json")
	verif.v(is_equal_approx(pierre.proprietes.resistance_impact, 2.0), "pierre reelle doit fusionner resistance_impact=2.0 depuis materiaux.json")
	verif.v(is_equal_approx(pierre.proprietes.fragilite, 0.7), "pierre reelle doit fusionner fragilite=0.7 depuis materiaux.json")
	verif.v(is_equal_approx(pierre.proprietes.resistance_compression, 130.0), "pierre reelle doit fusionner resistance_compression=130.0 depuis materiaux.json")

	verif.v(fer.proprietes.degats_impact_cumules == 0.0, "un objet fraichement fabrique doit demarrer a degats_impact_cumules=0.0")
	verif.v(fer.proprietes.etats_actifs.is_empty(), "un objet fraichement fabrique ne doit porter aucun etat actif")
	verif.v(fer.proprietes.transformation_fracture == "", "le fer doit porter sa propre declaration transformation_fracture (vide)")
	verif.v(pierre.proprietes.transformation_fracture == "fracture_pierre", "la pierre doit porter sa propre declaration transformation_fracture ('fracture_pierre')")
	verif.v(fer.proprietes.has("reserves") and fer.proprietes.reserves.integrite.reserve == 20.0, "chaque objet doit porter sa propre reserve d'integrite")
	verif.v(not is_same(fer.proprietes.reserves, pierre.proprietes.reserves), "chaque objet fabrique doit avoir sa propre reserve, jamais un Dictionary partage")

func _chemin_reel_pierre_casse_avant_le_fer_et_produit_des_eclats_le_fer_se_deforme_sans_eclats() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	var objet_physique: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json")).get("objet_physique", {})
	var catalogue_types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var catalogue_seuils_etat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json"))
	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})
	verif.v(transformations.get("fracture_pierre", {}).get("a_zero", {}).get("produire", {}).get("type_produit", "") == "eclats_pierre", "data/transformations.json:fracture_pierre doit produire 'eclats_pierre'")

	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_fracture.json"))
	var objets := BancFracture.fabriquer_objets(config.objets, objet_physique, materiaux, proprietes_immuables, config.nom_reserve_integrite, config.reserve_integrite_defaut)
	var fer: Dictionary = objets[0]
	var pierre: Dictionary = objets[1]
	var masse_fer_avant: float = fer.proprietes.masse

	var config_frappe := {
		"nom_reserve_integrite": config.nom_reserve_integrite,
		"rayon_frappe": config.rayon_frappe,
		"degats": config.degats,
		"criteres": config.criteres,
	}

	# UN coup sur la pierre (resistance_impact 2.0 < degats 3.0) : doit
	# fracturer et se transformer en eclats des le premier coup.
	BancFracture.avancer_frappe(objets, pierre.position, config_frappe, materiaux)
	var resultat_pierre := BancFracture.avancer_fracture(objets, catalogue_seuils_etat, transformations, catalogue_types, materiaux, config.seuil_fragilite_eclats)
	verif.v(resultat_pierre.bascules.has("pierre_0"), "chemin reel : un seul coup doit suffire a fracturer la pierre (degats 3.0 > resistance_impact 2.0)")
	verif.v(resultat_pierre.transformes.has("pierre_0"), "chemin reel : la pierre (fragilite 0.7, au-dessus du seuil) doit produire des eclats")
	verif.v(pierre.proprietes.composition[0].materiau == "eclats_pierre", "chemin reel : la pierre transformee doit porter la composition 'eclats_pierre'")

	# DEUX coups sur le fer (cumul 6.0 < resistance_impact 8.0) : ne doit
	# PAS encore fracturer.
	BancFracture.avancer_frappe(objets, fer.position, config_frappe, materiaux)
	BancFracture.avancer_fracture(objets, catalogue_seuils_etat, transformations, catalogue_types, materiaux, config.seuil_fragilite_eclats)
	BancFracture.avancer_frappe(objets, fer.position, config_frappe, materiaux)
	var resultat_fer_intermediaire := BancFracture.avancer_fracture(objets, catalogue_seuils_etat, transformations, catalogue_types, materiaux, config.seuil_fragilite_eclats)
	verif.v(not resultat_fer_intermediaire.bascules.has("fer_0"), "chemin reel : deux coups (cumul 6.0) ne doivent pas encore fracturer le fer (resistance_impact 8.0)")
	verif.v(fer.proprietes.composition[0].materiau == "fer", "chemin reel : le fer non fracture doit rester du fer")

	# TROISIEME coup (cumul 9.0 > 8.0) : doit fracturer, MAIS jamais se
	# transformer (fragilite 0.2, sous seuil_fragilite_eclats 0.5).
	BancFracture.avancer_frappe(objets, fer.position, config_frappe, materiaux)
	var resultat_fer := BancFracture.avancer_fracture(objets, catalogue_seuils_etat, transformations, catalogue_types, materiaux, config.seuil_fragilite_eclats)
	verif.v(resultat_fer.bascules.has("fer_0"), "chemin reel : le troisieme coup doit fracturer le fer (cumul 9.0 > resistance_impact 8.0)")
	verif.v(resultat_fer.transformes.is_empty(), "chemin reel : le fer (fragilite 0.2, sous le seuil) ne doit JAMAIS se transformer en eclats")
	verif.v(fer.proprietes.composition[0].materiau == "fer", "chemin reel : le fer fracture-mais-deforme doit rester du fer, jamais transforme")
	verif.v(fer.proprietes.masse == masse_fer_avant, "chemin reel : la masse du fer fracture-mais-deforme ne doit jamais changer -- aucune perte de matiere sans transformation")
	verif.v(fer.proprietes.etats_actifs.has("fracture"), "chemin reel : le fer doit porter l'etat 'fracture' meme sans jamais se transformer")

func _donnees_reelles_banc_fracture_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_fracture.json"))
	verif.v(donnees.nom_reserve_integrite == "integrite", "data/banc_fracture.json doit declarer nom_reserve_integrite")
	verif.v(donnees.has("rayon_frappe") and donnees.rayon_frappe > 0.0, "data/banc_fracture.json doit declarer un rayon_frappe strictement positif")
	verif.v(donnees.has("degats") and donnees.degats > 0.0, "data/banc_fracture.json doit declarer des degats strictement positifs")
	verif.v(donnees.has("seuil_fragilite_eclats"), "data/banc_fracture.json doit declarer seuil_fragilite_eclats")
	verif.v(not donnees.criteres.is_empty(), "data/banc_fracture.json doit declarer au moins un critere pour Frappe.selectionner")
	verif.v(donnees.objets.size() == 2, "data/banc_fracture.json doit declarer deux objets (fer/pierre)")

	var par_id: Dictionary = {}
	for objet in donnees.objets:
		par_id[objet.id] = objet
	verif.v(par_id.has("fer_0") and par_id.has("pierre_0"), "data/banc_fracture.json doit porter fer_0 et pierre_0")
	verif.v(par_id.fer_0.composition[0].materiau == "fer", "fer_0 doit composer du fer")
	verif.v(par_id.pierre_0.composition[0].materiau == "pierre", "pierre_0 doit composer de la pierre")
	verif.v(par_id.fer_0.get("transformation_fracture", "not_found") == "", "fer_0 ne doit declarer aucune transformation_fracture")
	verif.v(par_id.pierre_0.get("transformation_fracture", "") == "fracture_pierre", "pierre_0 doit declarer transformation_fracture='fracture_pierre'")

	var distance: float = Vector3(par_id.fer_0.position[0], par_id.fer_0.position[1], par_id.fer_0.position[2]).distance_to(Vector3(par_id.pierre_0.position[0], par_id.pierre_0.position[1], par_id.pierre_0.position[2]))
	verif.v(distance > donnees.rayon_frappe * 2.0, "fer_0 et pierre_0 doivent etre espaces de plus de deux fois le rayon_frappe -- sinon un clic pres de l'un mettrait aussi l'autre a portee")

func _donnees_reelles_catalogues_partages() -> void:
	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	verif.v(etats.has("fracture"), "data/etats.json doit porter l'entree partagee 'fracture'")
	verif.v(not etats.fracture.has("duree"), "'fracture' ne doit jamais porter 'duree' -- irreversible, degats_impact_cumules ne redescend jamais")
	var proprietes_visees: Array = []
	for effet in etats.fracture.effets:
		proprietes_visees.append(effet.propriete)
	verif.v(proprietes_visees.has("durete") and proprietes_visees.has("resistance_compression"), "'fracture' doit moduler durete ET resistance_compression")

	var seuils_etat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json"))
	verif.v(seuils_etat.has("fracture"), "data/seuils_etat.json doit porter l'entree partagee 'fracture'")
	verif.v(seuils_etat.fracture.propriete_continue == "degats_impact_cumules", "data/seuils_etat.json:fracture doit comparer degats_impact_cumules")
	verif.v(seuils_etat.fracture.seuil_propriete == "resistance_impact", "data/seuils_etat.json:fracture doit lire le seuil PAR OBJET sur resistance_impact")
	verif.v(seuils_etat.fracture.etat == "fracture", "data/seuils_etat.json:fracture doit poser l'etat 'fracture'")

	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})
	verif.v(transformations.has("fracture_pierre"), "data/transformations.json doit porter l'entree partagee 'fracture_pierre'")

	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	verif.v(materiaux.has("eclats_pierre") and materiaux.eclats_pierre.has("densite"), "data/materiaux.json doit porter 'eclats_pierre' avec une densite")

	var types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	verif.v(types.has("eclats_pierre"), "data/types.json doit porter le type 'eclats_pierre'")

# Retour visibilite (Yael) : la grappe d'eclats doit etre FIXE (jamais un
# hasard non seede) et non vide -- deux appels doivent rendre exactement
# le meme resultat.
func _positions_eclats_fixe_et_deterministe() -> void:
	var premier := BancFracture.positions_eclats()
	var second := BancFracture.positions_eclats()
	verif.v(not premier.is_empty(), "positions_eclats() ne doit jamais etre vide -- au moins un fragment visible")
	verif.v(premier.size() == second.size(), "deux appels doivent rendre le meme nombre d'offsets")
	for i in premier.size():
		verif.v(premier[i] == second[i], "deux appels doivent rendre exactement les memes offsets, aucun hasard")

# Retour visibilite (Yael) : la secousse de camera doit etre une fonction
# PURE et deterministe du temps restant -- jamais un Vector2 aleatoire --
# et s'eteindre exactement a zero une fois le temps ecoule, jamais un
# tremblement fige.
func _offset_secousse_deterministe_et_s_eteint_a_zero() -> void:
	var a := BancFracture.offset_secousse(0.1, 0.2)
	var b := BancFracture.offset_secousse(0.1, 0.2)
	verif.v(a == b, "deux appels aux memes arguments doivent rendre exactement le meme offset, aucun hasard")
	verif.v(BancFracture.offset_secousse(0.0, 0.2) == Vector2.ZERO, "temps_restant a 0.0 doit eteindre la secousse (Vector2.ZERO)")
	verif.v(BancFracture.offset_secousse(-1.0, 0.2) == Vector2.ZERO, "un temps_restant negatif doit rendre Vector2.ZERO, jamais une amplitude negative")
	verif.v(BancFracture.offset_secousse(0.2, -1.0) == Vector2.ZERO, "une duree_totale nulle ou negative doit rendre Vector2.ZERO, jamais une division par zero")
	var debut := BancFracture.offset_secousse(0.2, 0.2)
	var fin := BancFracture.offset_secousse(0.02, 0.2)
	verif.v(debut.length() > fin.length(), "l'amplitude doit decroitre a mesure que temps_restant se rapproche de zero")

# Retour visibilite (Yael) : le flash doit dominer TOUT autre etat visuel
# -- un objet fracture, transforme, ou simplement endommage doit quand
# meme flasher blanc au moment precis du choc.
func _teinte_flash_actif_domine_tout() -> void:
	var objet := _objet("a", Vector3.ZERO, {"reserves": {"integrite": {"reserve": 20.0}}})
	verif.v(BancFracture._teinte(objet, false, false, 20.0, true) == BancFracture.COULEUR_FLASH, "flash actif doit dominer l'etat intact")
	verif.v(BancFracture._teinte(objet, false, true, 20.0, true) == BancFracture.COULEUR_FLASH, "flash actif doit dominer l'etat fracture")
	verif.v(BancFracture._teinte(objet, true, false, 20.0, true) == BancFracture.COULEUR_FLASH, "flash actif doit dominer l'etat transforme")
	verif.v(BancFracture._teinte(objet, false, false, 20.0, false) != BancFracture.COULEUR_FLASH, "sans flash actif, la teinte ne doit jamais etre le blanc du flash")
