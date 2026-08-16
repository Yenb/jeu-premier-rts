extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_fracture_sonore.gd
#
# Verrouille le cablage de banc_fracture_sonore.gd -- composition de trois
# mecanismes deja fermes (portee.gd/seuil_etat.gd/produit.gd), AUCUN touche
# par ce chantier : ce fichier verrouille uniquement
# banc_fracture_sonore.gd (fabriquer_objets/intensite_recue/
# avancer_exposition/avancer_fracture), plus les catalogues de donnees
# partagees que ce chantier a etendus (verre_demo/eclats_verre dans
# data/materiaux.json, "fracture_sonore" dans data/seuils_etat.json,
# "fracture_verre"/"eclats_verre" dans
# data/transformations.json/data/types.json).

const BancFractureSonore = preload("res://scripts/banc_fracture_sonore.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const CATALOGUE_SEUILS_ETAT := {
	"fracture_sonore": {
		"propriete_continue": "intensite_sonore_cumulee",
		"seuil_propriete": "resistance_impact",
		"etat": "fracture",
	},
}

func _init() -> void:
	_intensite_recue_hors_de_portee_rend_zero()
	_intensite_recue_decroit_avec_la_distance()
	_intensite_recue_nulle_a_rayon_source_nul()
	_avancer_exposition_sans_source_active_ne_change_rien()
	_avancer_exposition_accumule_avec_delta()
	_avancer_exposition_hors_de_portee_ne_change_rien()
	_intensite_sous_resistance_impact_ne_fracture_pas()
	_avancer_fracture_pose_l_etat_au_franchissement_du_seuil()
	_avancer_fracture_haute_fragilite_produit_transforme()
	_avancer_fracture_basse_fragilite_reste_deforme_sans_transformation()
	_fabrication_reelle_fusionne_resistance_impact_fragilite_son_emis()
	_chemin_reel_le_verre_casse_avant_le_fer_et_produit_des_eclats_sans_source_rien_ne_casse()
	_donnees_reelles_banc_fracture_sonore_json()
	_donnees_reelles_catalogues_partages()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_fracture_sonore.gd -- intensite recue nulle hors de portee et decroissante avec la distance, " +
		"accumulation continue avec delta uniquement si la source est active, sans source rien n'accumule, " +
		"fracture au franchissement de resistance_impact par intensite_sonore_cumulee, jamais sous le seuil, " +
		"fragilite haute (verre) produit des eclats, fragilite basse (fer) reste deformee sans transformation, " +
		"fabrication reelle fusionne resistance_impact/fragilite/son_emis, chemin reel : le verre casse et produit " +
		"des eclats strictement avant le fer, sans source rien ne casse, donnees reelles chargent correctement")
	quit(0)

func _objet(id: String, position: Vector3, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": position, "proprietes": proprietes}

func _proprietes_base(resistance_impact: float, fragilite: float, transformation_fracture: String, masse: float = 100.0) -> Dictionary:
	return {
		"resistance_impact": resistance_impact,
		"fragilite": fragilite,
		"resistance_compression": 100.0,
		"durete": 5.0,
		"intensite_sonore_cumulee": 0.0,
		"etats_actifs": [],
		"transformation_fracture": transformation_fracture,
		"masse": masse,
	}

func _intensite_recue_hors_de_portee_rend_zero() -> void:
	var intensite := BancFractureSonore.intensite_recue(Vector3(1000.0, 0.0, 0.0), Vector3.ZERO, 5.0, 300.0)
	verif.v(intensite == 0.0, "un objet hors du rayon de la source doit recevoir une intensite nulle, quel que soit son_emis_source")

func _intensite_recue_decroit_avec_la_distance() -> void:
	var proche := BancFractureSonore.intensite_recue(Vector3(50.0, 0.0, 0.0), Vector3.ZERO, 1.0, 300.0)
	var loin := BancFractureSonore.intensite_recue(Vector3(250.0, 0.0, 0.0), Vector3.ZERO, 1.0, 300.0)
	verif.v(proche > loin, "un objet plus proche de la source doit recevoir une intensite plus haute")
	verif.v(is_equal_approx(proche, 1.0 * (1.0 - 50.0 / 300.0)), "l'intensite recue doit valoir exactement son_emis_source * (1.0 - distance/rayon_source)")

func _intensite_recue_nulle_a_rayon_source_nul() -> void:
	var intensite := BancFractureSonore.intensite_recue(Vector3.ZERO, Vector3.ZERO, 5.0, 0.0)
	verif.v(intensite == 0.0, "un rayon_source nul ou negatif doit rendre une intensite nulle, jamais une division par zero")

func _avancer_exposition_sans_source_active_ne_change_rien() -> void:
	var a := _objet("a", Vector3(50.0, 0.0, 0.0), _proprietes_base(1.0, 0.9, ""))
	BancFractureSonore.avancer_exposition([a], false, Vector3.ZERO, 5.0, 300.0, 1.0)
	verif.v(a.proprietes.intensite_sonore_cumulee == 0.0, "SANS SOURCE ACTIVE, rien ne doit jamais accumuler, meme a portee, meme sur un grand delta")

func _avancer_exposition_accumule_avec_delta() -> void:
	var a := _objet("a", Vector3(50.0, 0.0, 0.0), _proprietes_base(1.0, 0.9, ""))
	BancFractureSonore.avancer_exposition([a], true, Vector3.ZERO, 1.0, 300.0, 0.5)
	var attendu: float = (1.0 * (1.0 - 50.0 / 300.0)) * 0.5
	verif.v(is_equal_approx(a.proprietes.intensite_sonore_cumulee, attendu), "l'accumulation doit valoir exactement intensite_recue * delta apres un pas")
	BancFractureSonore.avancer_exposition([a], true, Vector3.ZERO, 1.0, 300.0, 0.5)
	verif.v(is_equal_approx(a.proprietes.intensite_sonore_cumulee, attendu * 2.0), "deux pas successifs doivent cumuler, jamais remplacer")

func _avancer_exposition_hors_de_portee_ne_change_rien() -> void:
	var a := _objet("a", Vector3(1000.0, 0.0, 0.0), _proprietes_base(1.0, 0.9, ""))
	BancFractureSonore.avancer_exposition([a], true, Vector3.ZERO, 5.0, 300.0, 1.0)
	verif.v(a.proprietes.intensite_sonore_cumulee == 0.0, "un objet hors de portee de la source ne doit jamais accumuler, meme source active")

func _intensite_sous_resistance_impact_ne_fracture_pas() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_base(10.0, 0.9, "prod_test"))
	a.proprietes.intensite_sonore_cumulee = 4.0
	var resultat := BancFractureSonore.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, {}, {}, {}, 0.5)
	verif.v(resultat.bascules.is_empty(), "une intensite cumulee strictement sous resistance_impact ne doit jamais poser 'fracture' (4.0 < 10.0)")
	verif.v(not a.proprietes.etats_actifs.has("fracture"), "'fracture' ne doit pas etre actif sous le seuil")

func _avancer_fracture_pose_l_etat_au_franchissement_du_seuil() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_base(5.0, 0.1, ""))
	a.proprietes.intensite_sonore_cumulee = 6.0
	var resultat := BancFractureSonore.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, {}, {}, {}, 0.5)
	verif.v(resultat.bascules.has("a"), "une intensite cumulee au-dela de resistance_impact doit basculer l'objet (6.0 > 5.0)")
	verif.v(a.proprietes.etats_actifs.has("fracture"), "'fracture' doit etre pose dans etats_actifs au franchissement")
	var resultat2 := BancFractureSonore.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, {}, {}, {}, 0.5)
	verif.v(resultat2.bascules.is_empty(), "une fois pose, 'fracture' ne doit plus rebasculer -- intensite_sonore_cumulee ne redescend jamais, jamais un aller-retour")

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
	a.proprietes.intensite_sonore_cumulee = 6.0
	var resultat := BancFractureSonore.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, TRANSFORMATIONS_FICTIVES, TABLE_FICTIVE, MATERIAUX_FICTIFS, 0.5)
	verif.v(resultat.transformes.has("a"), "une fragilite au-dessus du seuil doit produire une transformation (Produit.transformer)")
	verif.v(a.proprietes.composition[0].materiau == "materiau_produit_test", "l'objet transforme doit porter la composition du type_produit configure")
	verif.v(abs(a.proprietes.masse - 200.0 * 0.8) < 0.01, "la masse produite doit valoir exactement rendement * masse_ancien")
	verif.v(not a.proprietes.has("resistance_impact"), "un objet transforme ne doit plus porter resistance_impact -- proprietes entierement remplacees")

func _avancer_fracture_basse_fragilite_reste_deforme_sans_transformation() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_base(5.0, 0.1, "prod_test", 200.0))
	a.proprietes.intensite_sonore_cumulee = 6.0
	var resultat := BancFractureSonore.avancer_fracture([a], CATALOGUE_SEUILS_ETAT, TRANSFORMATIONS_FICTIVES, TABLE_FICTIVE, MATERIAUX_FICTIFS, 0.5)
	verif.v(resultat.bascules.has("a"), "l'objet doit tout de meme fracturer (etat pose)")
	verif.v(resultat.transformes.is_empty(), "une fragilite sous le seuil ne doit jamais produire de transformation, meme avec une transformation_fracture valide")
	verif.v(a.proprietes.has("resistance_impact"), "un objet non transforme doit garder toutes ses proprietes d'origine")
	verif.v(a.proprietes.masse == 200.0, "un objet non transforme ne doit jamais voir sa masse changer -- deformation seule, jamais de perte de matiere")

func _fabrication_reelle_fusionne_resistance_impact_fragilite_son_emis() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(materiaux.has("verre_demo"), "data/materiaux.json doit porter 'verre_demo'")
	verif.v(is_equal_approx(materiaux.verre_demo.resistance_impact, 1.0), "verre_demo doit declarer resistance_impact=1.0")
	verif.v(is_equal_approx(materiaux.verre_demo.fragilite, 0.9), "verre_demo doit declarer fragilite=0.9")
	verif.v(is_equal_approx(materiaux.verre_demo.son_emis, 0.0), "verre_demo doit declarer son_emis=0.0")

	var objet_physique: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json")).get("objet_physique", {})
	var declarations := [
		{"id": "verre_t", "position": [0.0, 0.0, 0.0], "composition": [{"materiau": "verre_demo", "volume": 1.0}], "transformation_fracture": "fracture_verre"},
		{"id": "fer_t", "position": [10.0, 0.0, 0.0], "composition": [{"materiau": "fer", "volume": 1.0}], "transformation_fracture": ""},
	]
	var objets := BancFractureSonore.fabriquer_objets(declarations, objet_physique, materiaux, proprietes_immuables)
	var verre: Dictionary = objets[0]
	var fer: Dictionary = objets[1]

	verif.v(is_equal_approx(verre.proprietes.resistance_impact, 1.0), "verre reel doit fusionner resistance_impact=1.0 depuis materiaux.json")
	verif.v(is_equal_approx(verre.proprietes.fragilite, 0.9), "verre reel doit fusionner fragilite=0.9 depuis materiaux.json")
	verif.v(is_equal_approx(fer.proprietes.resistance_impact, 8.0), "fer reel doit fusionner resistance_impact=8.0 depuis materiaux.json")
	verif.v(is_equal_approx(fer.proprietes.fragilite, 0.2), "fer reel doit fusionner fragilite=0.2 depuis materiaux.json")

	verif.v(verre.proprietes.intensite_sonore_cumulee == 0.0, "un objet fraichement fabrique doit demarrer a intensite_sonore_cumulee=0.0")
	verif.v(verre.proprietes.etats_actifs.is_empty(), "un objet fraichement fabrique ne doit porter aucun etat actif")
	verif.v(verre.proprietes.transformation_fracture == "fracture_verre", "le verre doit porter sa propre declaration transformation_fracture")
	verif.v(fer.proprietes.transformation_fracture == "", "le fer doit porter sa propre declaration transformation_fracture (vide)")

func _chemin_reel_le_verre_casse_avant_le_fer_et_produit_des_eclats_sans_source_rien_ne_casse() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	var objet_physique: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json")).get("objet_physique", {})
	var catalogue_types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var catalogue_seuils_etat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json"))
	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})
	verif.v(transformations.get("fracture_verre", {}).get("a_zero", {}).get("produire", {}).get("type_produit", "") == "eclats_verre", "data/transformations.json:fracture_verre doit produire 'eclats_verre'")

	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_fracture_sonore.json"))
	var objets := BancFractureSonore.fabriquer_objets(config.objets, objet_physique, materiaux, proprietes_immuables)
	var position_source := Vector3(config.position_source[0], config.position_source[1], config.position_source[2])
	var verre: Dictionary = objets[0]
	var fer: Dictionary = objets[1]

	# SANS SOURCE : de nombreux pas de temps ne doivent jamais rien
	# accumuler ni fracturer -- meme avec la position/rayon reels du banc.
	for i in 50:
		BancFractureSonore.avancer_exposition(objets, false, position_source, config.son_emis_source, config.rayon_source, 0.5)
	verif.v(verre.proprietes.intensite_sonore_cumulee == 0.0, "chemin reel : sans source active, le verre ne doit jamais accumuler d'intensite")
	verif.v(fer.proprietes.intensite_sonore_cumulee == 0.0, "chemin reel : sans source active, le fer ne doit jamais accumuler d'intensite")
	var resultat_sans_source := BancFractureSonore.avancer_fracture(objets, catalogue_seuils_etat, transformations, catalogue_types, materiaux, config.seuil_fragilite_eclats)
	verif.v(resultat_sans_source.bascules.is_empty(), "chemin reel : sans source active, rien ne doit jamais fracturer")

	# SOURCE ACTIVE : le verre (resistance_impact 1.0) doit fracturer et se
	# transformer en eclats nettement AVANT le fer (resistance_impact 8.0),
	# meme exposition, meme distance a la source.
	var pas := 0
	var verre_fracture_a := -1
	var fer_fracture_a := -1
	while pas < 2000 and (verre_fracture_a < 0 or fer_fracture_a < 0):
		BancFractureSonore.avancer_exposition(objets, true, position_source, config.son_emis_source, config.rayon_source, 0.1)
		var resultat := BancFractureSonore.avancer_fracture(objets, catalogue_seuils_etat, transformations, catalogue_types, materiaux, config.seuil_fragilite_eclats)
		if resultat.bascules.has("verre_0") and verre_fracture_a < 0:
			verre_fracture_a = pas
		if resultat.bascules.has("fer_0") and fer_fracture_a < 0:
			fer_fracture_a = pas
		pas += 1

	verif.v(verre_fracture_a >= 0, "chemin reel : le verre doit finir par fracturer sous exposition continue")
	verif.v(fer_fracture_a >= 0, "chemin reel : le fer doit finir par fracturer sous exposition continue (resistance_impact fini)")
	verif.v(verre_fracture_a < fer_fracture_a, "chemin reel : le verre (resistance_impact 1.0) doit fracturer STRICTEMENT avant le fer (resistance_impact 8.0), meme exposition, meme distance")
	verif.v(verre.proprietes.composition[0].materiau == "eclats_verre", "chemin reel : le verre fracture doit produire des eclats (fragilite 0.9, au-dessus du seuil)")
	verif.v(fer.proprietes.composition[0].materiau == "fer", "chemin reel : le fer fracture-mais-deforme doit rester du fer, jamais transforme (fragilite 0.2, sous le seuil)")
	verif.v(fer.proprietes.etats_actifs.has("fracture"), "chemin reel : le fer doit porter l'etat 'fracture' meme sans jamais se transformer")

func _donnees_reelles_banc_fracture_sonore_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_fracture_sonore.json"))
	verif.v(donnees.has("son_emis_source") and donnees.son_emis_source > 0.0, "data/banc_fracture_sonore.json doit declarer un son_emis_source strictement positif")
	verif.v(donnees.has("rayon_source") and donnees.rayon_source > 0.0, "data/banc_fracture_sonore.json doit declarer un rayon_source strictement positif")
	verif.v(donnees.has("seuil_fragilite_eclats"), "data/banc_fracture_sonore.json doit declarer seuil_fragilite_eclats")
	verif.v(donnees.objets.size() == 2, "data/banc_fracture_sonore.json doit declarer deux objets (verre/fer)")

	var par_id: Dictionary = {}
	for objet in donnees.objets:
		par_id[objet.id] = objet
	verif.v(par_id.has("verre_0") and par_id.has("fer_0"), "data/banc_fracture_sonore.json doit porter verre_0 et fer_0")
	verif.v(par_id.verre_0.composition[0].materiau == "verre_demo", "verre_0 doit composer du verre_demo")
	verif.v(par_id.fer_0.composition[0].materiau == "fer", "fer_0 doit composer du fer")
	verif.v(par_id.verre_0.get("transformation_fracture", "") == "fracture_verre", "verre_0 doit declarer transformation_fracture='fracture_verre'")
	verif.v(par_id.fer_0.get("transformation_fracture", "not_found") == "", "fer_0 ne doit declarer aucune transformation_fracture")

	var pos_source := Vector3(donnees.position_source[0], donnees.position_source[1], donnees.position_source[2])
	var pos_verre := Vector3(par_id.verre_0.position[0], par_id.verre_0.position[1], par_id.verre_0.position[2])
	var pos_fer := Vector3(par_id.fer_0.position[0], par_id.fer_0.position[1], par_id.fer_0.position[2])
	verif.v(is_equal_approx(pos_source.distance_to(pos_verre), pos_source.distance_to(pos_fer)), "verre_0 et fer_0 doivent etre a EGALE DISTANCE de la source -- seule resistance_impact doit expliquer l'ecart de vitesse de fracture")

func _donnees_reelles_catalogues_partages() -> void:
	var seuils_etat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json"))
	verif.v(seuils_etat.has("fracture_sonore"), "data/seuils_etat.json doit porter l'entree 'fracture_sonore'")
	verif.v(seuils_etat.fracture_sonore.propriete_continue == "intensite_sonore_cumulee", "data/seuils_etat.json:fracture_sonore doit comparer intensite_sonore_cumulee")
	verif.v(seuils_etat.fracture_sonore.seuil_propriete == "resistance_impact", "data/seuils_etat.json:fracture_sonore doit lire le seuil PAR OBJET sur resistance_impact")
	verif.v(seuils_etat.fracture_sonore.etat == "fracture", "data/seuils_etat.json:fracture_sonore doit poser le MEME etat 'fracture' que l'entree mecanique")
	verif.v(seuils_etat.has("fracture"), "data/seuils_etat.json doit toujours porter l'entree mecanique 'fracture' (coexistence, jamais un remplacement)")

	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	verif.v(etats.has("fracture") and not etats.fracture.has("duree"), "'fracture' reste irreversible (aucune duree), quel que soit le chemin qui l'a pose")

	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})
	verif.v(transformations.has("fracture_verre"), "data/transformations.json doit porter l'entree 'fracture_verre'")

	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	verif.v(materiaux.has("eclats_verre") and materiaux.eclats_verre.has("densite"), "data/materiaux.json doit porter 'eclats_verre' avec une densite")

	var types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	verif.v(types.has("eclats_verre"), "data/types.json doit porter le type 'eclats_verre'")
