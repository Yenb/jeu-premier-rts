extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_coupe.gd
#
# Verrouille le cablage de banc_coupe.gd -- composition de deux mecanismes
# deja fermes (frappe.gd/produit.gd), AUCUN touche par ce chantier : ce
# fichier verrouille uniquement banc_coupe.gd (fabriquer_cibles/
# fabriquer_outil/degat_coupe/emoussement/cibles_coupables/avancer_coupe/
# avancer_transformation/materiau_suivant), plus les catalogues de donnees
# partagees que ce chantier a etendus (resistance_cisaillement/tranchant_max
# dans data/proprietes_immuables_composition.json, "coupe_bois"/
# "coupe_pierre"/"coupe_fer" dans data/transformations.json,
# "copeaux_bois"/"limaille_fer" dans data/materiaux.json/data/types.json).

const BancCoupe = preload("res://scripts/banc_coupe.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_degat_coupe_formule_exacte()
	_degat_coupe_resistance_nulle_ou_negative_rend_zero()
	_degat_coupe_tranchant_nul_rend_zero()
	_emoussement_formule_exacte()
	_materiau_suivant_cycle()
	_materiau_suivant_absent_reprend_au_debut()
	_cibles_coupables_filtre_la_reserve_epuisee()
	_avancer_coupe_hors_de_portee_rend_dictionnaire_vide()
	_avancer_coupe_selectionne_a_portee_calcule_le_degat_et_emousse_l_outil()
	_avancer_coupe_deux_coups_cumulent_degat_et_usure()
	_avancer_coupe_tranchant_nul_ne_coupe_plus_rien()
	_avancer_transformation_transforme_a_reserve_epuisee()
	_avancer_transformation_idempotent_ne_retransforme_jamais()
	_avancer_transformation_ne_transforme_pas_avant_epuisement()
	_fabrication_reelle_fusionne_resistance_cisaillement_tranchant_max_durete()
	_fabrication_outil_initialise_tranchant_effectif_a_tranchant_max()
	_chemin_reel_le_fer_coupe_le_bois()
	_chemin_reel_le_bois_ne_coupe_pas_la_pierre()
	_chemin_reel_resistance_tres_haute_se_coupe_presque_pas()
	_donnees_reelles_banc_coupe_json()
	_donnees_reelles_catalogues_partages()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_coupe.gd -- degat de coupe = tranchant_effectif/resistance_cisaillement, l'outil s'emousse " +
		"proportionnellement a la durete de la cible, tranchant_effectif nul ne coupe plus rien, la reserve " +
		"d'integrite epuisee produit des debris (Produit.transformer) de facon idempotente, fabrication reelle " +
		"fusionne resistance_cisaillement/tranchant_max/durete, chemin reel : le fer coupe le bois en debris, le " +
		"bois s'emousse avant d'entamer significativement la pierre, une resistance tres haute (fer) se coupe " +
		"presque pas compare au bois, donnees reelles chargent correctement")
	quit(0)

func _objet(id: String, position: Vector3, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": position, "proprietes": proprietes}

func _proprietes_cible(resistance_cisaillement: float, durete: float, transformation_coupe: String, reserve: float = 2.0, masse: float = 100.0) -> Dictionary:
	return {
		"resistance_cisaillement": resistance_cisaillement,
		"durete": durete,
		"etats_actifs": [],
		"transformation_coupe": transformation_coupe,
		"masse": masse,
		"reserves": {"integrite": {"reserve": reserve, "cout_base": 0.0, "surcout_action": 0.0}},
	}

func _proprietes_outil(tranchant_max: float, tranchant_effectif: float) -> Dictionary:
	return {
		"tranchant_max": tranchant_max,
		"tranchant_effectif": tranchant_effectif,
		"materiau_outil": "test",
		"etats_actifs": [],
	}

func _config_coupe() -> Dictionary:
	return {
		"nom_reserve_integrite": "integrite",
		"rayon_coupe": 50.0,
		"criteres": [{"poids": 1.0, "source": "position_z"}],
		"taux_emoussement": 0.1,
	}

func _degat_coupe_formule_exacte() -> void:
	verif.v(is_equal_approx(BancCoupe.degat_coupe(9.0, 10.0), 0.9), "degat_coupe(9.0, 10.0) doit valoir exactement 0.9 (tranchant_effectif / resistance_cisaillement)")
	verif.v(is_equal_approx(BancCoupe.degat_coupe(9.0, 20.0), 0.45), "degat_coupe(9.0, 20.0) doit valoir exactement 0.45")
	verif.v(is_equal_approx(BancCoupe.degat_coupe(2.0, 10.0), 0.2), "degat_coupe(2.0, 10.0) doit valoir exactement 0.2")

func _degat_coupe_resistance_nulle_ou_negative_rend_zero() -> void:
	verif.v(BancCoupe.degat_coupe(9.0, 0.0) == 0.0, "une resistance_cisaillement nulle doit rendre 0.0, jamais une division par zero")
	verif.v(BancCoupe.degat_coupe(9.0, -5.0) == 0.0, "une resistance_cisaillement negative doit rendre 0.0, jamais une valeur negative ou une exception")

func _degat_coupe_tranchant_nul_rend_zero() -> void:
	verif.v(BancCoupe.degat_coupe(0.0, 10.0) == 0.0, "un tranchant_effectif nul doit rendre un degat nul par la seule arithmetique -- 'l'outil ne coupe plus'")

func _emoussement_formule_exacte() -> void:
	verif.v(is_equal_approx(BancCoupe.emoussement(0.05, 6.0), 0.3), "emoussement(0.05, 6.0) doit valoir exactement 0.3 (taux_emoussement_base * durete_cible)")
	verif.v(BancCoupe.emoussement(0.05, 0.0) == 0.0, "une cible sans durete (0.0) ne doit jamais user l'outil")

func _materiau_suivant_cycle() -> void:
	verif.v(BancCoupe.materiau_suivant("fer", BancCoupe.ORDRE_MATERIAUX_OUTIL) == "bois", "fer doit ceder la place a bois")
	verif.v(BancCoupe.materiau_suivant("bois", BancCoupe.ORDRE_MATERIAUX_OUTIL) == "pierre", "bois doit ceder la place a pierre")
	verif.v(BancCoupe.materiau_suivant("pierre", BancCoupe.ORDRE_MATERIAUX_OUTIL) == "fer", "pierre doit boucler sur fer")

func _materiau_suivant_absent_reprend_au_debut() -> void:
	verif.v(BancCoupe.materiau_suivant("inconnu", BancCoupe.ORDRE_MATERIAUX_OUTIL) == BancCoupe.ORDRE_MATERIAUX_OUTIL[0], "un materiau absent de l'ordre doit reprendre au debut, jamais une erreur")

func _cibles_coupables_filtre_la_reserve_epuisee() -> void:
	var vivante := _objet("a", Vector3.ZERO, {"reserves": {"integrite": {"reserve": 1.0}}})
	var epuisee := _objet("b", Vector3.ZERO, {"reserves": {"integrite": {"reserve": 0.0}}})
	var sans_reserve := _objet("c", Vector3.ZERO, {})
	var coupables := BancCoupe.cibles_coupables([vivante, epuisee, sans_reserve], "integrite")
	verif.v(coupables.size() == 1 and coupables[0].id == "a", "seule une cible avec reserve strictement positive doit rester coupable")

func _avancer_coupe_hors_de_portee_rend_dictionnaire_vide() -> void:
	var cibles := [_objet("a", Vector3(1000.0, 0.0, 0.0), _proprietes_cible(10.0, 2.0, ""))]
	var outil := _objet("outil", Vector3.ZERO, _proprietes_outil(9.0, 9.0))
	var resultat := BancCoupe.avancer_coupe(cibles, outil, Vector3.ZERO, _config_coupe(), {})
	verif.v(resultat.is_empty(), "aucune cible a portee du point de clic doit rendre un Dictionary vide, rien ne se passe")
	verif.v(cibles[0].proprietes.reserves.integrite.reserve == 2.0, "une cible hors de portee ne doit jamais voir sa reserve bouger")
	verif.v(outil.proprietes.tranchant_effectif == 9.0, "un outil qui ne coupe rien ne doit jamais s'emousser")

func _avancer_coupe_selectionne_a_portee_calcule_le_degat_et_emousse_l_outil() -> void:
	var a := _objet("a", Vector3(10.0, 0.0, 0.0), _proprietes_cible(10.0, 2.0, ""))
	var b := _objet("b", Vector3(1000.0, 0.0, 0.0), _proprietes_cible(10.0, 2.0, ""))
	var outil := _objet("outil", Vector3.ZERO, _proprietes_outil(9.0, 9.0))
	var resultat := BancCoupe.avancer_coupe([a, b], outil, Vector3.ZERO, _config_coupe(), {})
	verif.v(resultat.get("cible", {}).get("id", "") == "a", "le clic pres de 'a' doit selectionner 'a', jamais 'b' hors de portee")
	verif.v(is_equal_approx(resultat.degats, 0.9), "le degat doit valoir tranchant_effectif(9.0) / resistance_cisaillement(10.0) = 0.9")
	verif.v(is_equal_approx(a.proprietes.reserves.integrite.reserve, 1.1), "Frappe.frapper doit soustraire le degat de la reserve nommee (2.0 - 0.9 = 1.1)")
	verif.v(is_equal_approx(outil.proprietes.tranchant_effectif, 8.8), "l'outil doit s'emousser de taux_emoussement(0.1) * durete_cible(2.0) = 0.2 (9.0 - 0.2 = 8.8)")
	verif.v(b.proprietes.reserves.integrite.reserve == 2.0, "la cible non selectionnee ne doit jamais voir sa reserve bouger")

func _avancer_coupe_deux_coups_cumulent_degat_et_usure() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_cible(100.0, 2.0, "", 100.0))
	var outil := _objet("outil", Vector3.ZERO, _proprietes_outil(9.0, 9.0))
	BancCoupe.avancer_coupe([a], outil, Vector3.ZERO, _config_coupe(), {})
	BancCoupe.avancer_coupe([a], outil, Vector3.ZERO, _config_coupe(), {})
	verif.v(is_equal_approx(outil.proprietes.tranchant_effectif, 8.6), "deux coups doivent cumuler l'usure (9.0 - 0.2 - 0.2 = 8.6), jamais remplacer")
	verif.v(a.proprietes.reserves.integrite.reserve < 100.0, "deux coups doivent cumuler le degat sur la reserve de la cible")

func _avancer_coupe_tranchant_nul_ne_coupe_plus_rien() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_cible(10.0, 2.0, "", 5.0))
	var outil := _objet("outil", Vector3.ZERO, _proprietes_outil(9.0, 0.0))
	var resultat := BancCoupe.avancer_coupe([a], outil, Vector3.ZERO, _config_coupe(), {})
	verif.v(is_equal_approx(resultat.degats, 0.0), "un outil au tranchant deja nul ne doit infliger aucun degat")
	verif.v(a.proprietes.reserves.integrite.reserve == 5.0, "la reserve de la cible ne doit jamais bouger si le degat est nul")
	verif.v(outil.proprietes.tranchant_effectif == 0.0, "un tranchant deja a zero doit y rester (jamais negatif)")

func _avancer_transformation_transforme_a_reserve_epuisee() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_cible(10.0, 2.0, "prod_test", 0.0, 200.0))
	var resultat := BancCoupe.avancer_transformation([a], TRANSFORMATIONS_FICTIVES, TABLE_FICTIVE, MATERIAUX_FICTIFS, "integrite")
	verif.v(resultat.has("a"), "une reserve d'integrite epuisee doit produire une transformation (Produit.transformer)")
	verif.v(a.proprietes.composition[0].materiau == "materiau_produit_test", "la cible transformee doit porter la composition du type_produit configure")
	verif.v(abs(a.proprietes.masse - 200.0 * 0.8) < 0.01, "la masse produite doit valoir exactement rendement * masse_ancienne")
	verif.v(not a.proprietes.has("resistance_cisaillement"), "une cible transformee ne doit plus porter resistance_cisaillement -- proprietes entierement remplacees")

func _avancer_transformation_idempotent_ne_retransforme_jamais() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_cible(10.0, 2.0, "prod_test", 0.0, 200.0))
	var premier := BancCoupe.avancer_transformation([a], TRANSFORMATIONS_FICTIVES, TABLE_FICTIVE, MATERIAUX_FICTIFS, "integrite")
	verif.v(premier.has("a"), "la premiere transformation doit reussir")
	var masse_apres_premiere: float = a.proprietes.masse
	var second := BancCoupe.avancer_transformation([a], TRANSFORMATIONS_FICTIVES, TABLE_FICTIVE, MATERIAUX_FICTIFS, "integrite")
	verif.v(second.is_empty(), "une cible deja transformee (transformation_coupe efface par proprietes.clear()) ne doit jamais se retransformer")
	verif.v(a.proprietes.masse == masse_apres_premiere, "la masse ne doit plus jamais changer une fois transformee")

func _avancer_transformation_ne_transforme_pas_avant_epuisement() -> void:
	var a := _objet("a", Vector3.ZERO, _proprietes_cible(10.0, 2.0, "prod_test", 1.5, 200.0))
	var resultat := BancCoupe.avancer_transformation([a], TRANSFORMATIONS_FICTIVES, TABLE_FICTIVE, MATERIAUX_FICTIFS, "integrite")
	verif.v(resultat.is_empty(), "une reserve encore strictement positive ne doit jamais transformer")
	verif.v(a.proprietes.has("resistance_cisaillement"), "une cible non transformee doit garder toutes ses proprietes d'origine")

func _fabrication_reelle_fusionne_resistance_cisaillement_tranchant_max_durete() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(proprietes_immuables.has("resistance_cisaillement"), "data/proprietes_immuables_composition.json doit lister resistance_cisaillement")
	verif.v(proprietes_immuables.has("tranchant_max"), "data/proprietes_immuables_composition.json doit lister tranchant_max")

	var objet_physique: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json")).get("objet_physique", {})
	var declarations := [
		{"id": "bois_t", "position": [0.0, 0.0, 0.0], "composition": [{"materiau": "bois", "volume": 1.0}], "transformation_coupe": "coupe_bois"},
		{"id": "pierre_t", "position": [10.0, 0.0, 0.0], "composition": [{"materiau": "pierre", "volume": 1.0}], "transformation_coupe": "coupe_pierre"},
		{"id": "fer_t", "position": [20.0, 0.0, 0.0], "composition": [{"materiau": "fer", "volume": 1.0}], "transformation_coupe": "coupe_fer"},
	]
	var cibles := BancCoupe.fabriquer_cibles(declarations, objet_physique, materiaux, proprietes_immuables, "integrite", {"reserve": 2.0, "cout_base": 0.0, "surcout_action": 0.0})
	var bois: Dictionary = cibles[0]
	var pierre: Dictionary = cibles[1]
	var fer: Dictionary = cibles[2]

	verif.v(is_equal_approx(bois.proprietes.resistance_cisaillement, 10.0), "bois reel doit fusionner resistance_cisaillement=10.0 depuis materiaux.json")
	verif.v(is_equal_approx(pierre.proprietes.resistance_cisaillement, 20.0), "pierre reelle doit fusionner resistance_cisaillement=20.0 depuis materiaux.json")
	verif.v(is_equal_approx(fer.proprietes.resistance_cisaillement, 170.0), "fer reel doit fusionner resistance_cisaillement=170.0 depuis materiaux.json")
	verif.v(is_equal_approx(bois.proprietes.durete, 2.0), "bois reel doit fusionner durete=2.0 depuis materiaux.json")
	verif.v(is_equal_approx(pierre.proprietes.durete, 6.0), "pierre reelle doit fusionner durete=6.0 depuis materiaux.json")
	verif.v(is_equal_approx(fer.proprietes.durete, 4.5), "fer reel doit fusionner durete=4.5 depuis materiaux.json")

	verif.v(bois.proprietes.reserves.integrite.reserve == 2.0, "chaque cible doit demarrer a la reserve d'integrite par defaut")
	verif.v(not is_same(bois.proprietes.reserves, pierre.proprietes.reserves), "chaque cible fabriquee doit avoir sa propre reserve, jamais un Dictionary partage")
	verif.v(bois.proprietes.transformation_coupe == "coupe_bois", "bois doit porter sa propre declaration transformation_coupe")
	verif.v(fer.proprietes.transformation_coupe == "coupe_fer", "fer doit porter sa propre declaration transformation_coupe")

func _fabrication_outil_initialise_tranchant_effectif_a_tranchant_max() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	var objet_physique: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json")).get("objet_physique", {})

	var outil_fer := BancCoupe.fabriquer_outil("fer", Vector3.ZERO, objet_physique, materiaux, proprietes_immuables)
	verif.v(is_equal_approx(outil_fer.proprietes.tranchant_max, 9.0), "outil en fer reel doit fusionner tranchant_max=9.0 depuis materiaux.json")
	verif.v(is_equal_approx(outil_fer.proprietes.tranchant_effectif, 9.0), "un outil fraichement fabrique doit demarrer avec tranchant_effectif == tranchant_max")

	var outil_bois := BancCoupe.fabriquer_outil("bois", Vector3.ZERO, objet_physique, materiaux, proprietes_immuables)
	verif.v(is_equal_approx(outil_bois.proprietes.tranchant_max, 2.0), "outil en bois reel doit fusionner tranchant_max=2.0 depuis materiaux.json")

	var outil_pierre := BancCoupe.fabriquer_outil("pierre", Vector3.ZERO, objet_physique, materiaux, proprietes_immuables)
	verif.v(is_equal_approx(outil_pierre.proprietes.tranchant_max, 5.0), "outil en pierre reel doit fusionner tranchant_max=5.0 depuis materiaux.json")

func _fabriquer_scene_reelle() -> Dictionary:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	var objet_physique: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json")).get("objet_physique", {})
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_coupe.json"))
	var cibles := BancCoupe.fabriquer_cibles(config.cibles, objet_physique, materiaux, proprietes_immuables, config.nom_reserve_integrite, config.reserve_integrite_defaut)
	return {"materiaux": materiaux, "config": config, "cibles": cibles, "table_types": JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json")), "transformations": JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {}), "objet_physique": objet_physique, "proprietes_immuables": proprietes_immuables}

func _cible_par_id(cibles: Array, id: String) -> Dictionary:
	for cible in cibles:
		if cible.id == id:
			return cible
	return {}

# Chemin reel : l'outil en fer (tranchant_max 9.0) doit finir par reduire
# le bois (resistance_cisaillement 10.0) en copeaux -- boucle bornee (200
# coups, tres au-dessus du nombre necessaire) pour ne jamais dependre d'un
# calcul manuel fragile.
func _chemin_reel_le_fer_coupe_le_bois() -> void:
	var scene := _fabriquer_scene_reelle()
	var outil := BancCoupe.fabriquer_outil("fer", Vector3.ZERO, scene.objet_physique, scene.materiaux, scene.proprietes_immuables)
	var bois := _cible_par_id(scene.cibles, "bois_0")
	var transforme := false
	for i in 200:
		BancCoupe.avancer_coupe(scene.cibles, outil, bois.position, scene.config, scene.materiaux)
		var transformes := BancCoupe.avancer_transformation(scene.cibles, scene.transformations, scene.table_types, scene.materiaux, scene.config.nom_reserve_integrite)
		if transformes.has("bois_0"):
			transforme = true
			break
	verif.v(transforme, "chemin reel : l'outil en fer doit finir par reduire le bois en debris")
	verif.v(bois.proprietes.composition[0].materiau == "copeaux_bois", "chemin reel : le bois coupe doit porter la composition 'copeaux_bois'")

# Chemin reel : l'outil en bois (tranchant_max 2.0, durete faible) doit
# s'emousser completement AVANT d'avoir epuise l'integrite de la pierre --
# 'le bois ne coupe pas la pierre'.
func _chemin_reel_le_bois_ne_coupe_pas_la_pierre() -> void:
	var scene := _fabriquer_scene_reelle()
	var outil := BancCoupe.fabriquer_outil("bois", Vector3.ZERO, scene.objet_physique, scene.materiaux, scene.proprietes_immuables)
	var pierre := _cible_par_id(scene.cibles, "pierre_0")
	for i in 200:
		BancCoupe.avancer_coupe(scene.cibles, outil, pierre.position, scene.config, scene.materiaux)
		if outil.proprietes.tranchant_effectif <= 0.0:
			break
	verif.v(outil.proprietes.tranchant_effectif == 0.0, "chemin reel : l'outil en bois doit finir totalement emousse face a la pierre")
	verif.v(pierre.proprietes.reserves.integrite.reserve > 0.0, "chemin reel : la pierre ne doit jamais etre entierement coupee par un outil en bois")
	verif.v(not pierre.proprietes.has("composition") or pierre.proprietes.get("resistance_cisaillement", -1.0) != -1.0, "chemin reel : la pierre ne doit jamais avoir ete transformee en debris par l'outil en bois")

func _chemin_reel_resistance_tres_haute_se_coupe_presque_pas() -> void:
	var degat_bois := BancCoupe.degat_coupe(9.0, 10.0)
	var degat_fer := BancCoupe.degat_coupe(9.0, 170.0)
	verif.v(degat_fer < degat_bois * 0.1, "chemin reel : une resistance_cisaillement tres haute (fer, 170.0) doit produire un degat plus de dix fois plus faible que le bois (10.0), a tranchant egal")

func _donnees_reelles_banc_coupe_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_coupe.json"))
	verif.v(donnees.nom_reserve_integrite == "integrite", "data/banc_coupe.json doit declarer nom_reserve_integrite")
	verif.v(donnees.has("rayon_coupe") and donnees.rayon_coupe > 0.0, "data/banc_coupe.json doit declarer un rayon_coupe strictement positif")
	verif.v(donnees.has("taux_emoussement") and donnees.taux_emoussement > 0.0, "data/banc_coupe.json doit declarer un taux_emoussement strictement positif")
	verif.v(not donnees.criteres.is_empty(), "data/banc_coupe.json doit declarer au moins un critere pour Frappe.selectionner")
	verif.v(donnees.cibles.size() == 3, "data/banc_coupe.json doit declarer trois cibles (bois/pierre/fer)")
	verif.v(BancCoupe.ORDRE_MATERIAUX_OUTIL.has(donnees.materiau_outil_defaut), "materiau_outil_defaut doit etre un materiau valide de ORDRE_MATERIAUX_OUTIL")

	var par_id: Dictionary = {}
	for cible in donnees.cibles:
		par_id[cible.id] = cible
	verif.v(par_id.has("bois_0") and par_id.has("pierre_0") and par_id.has("fer_0"), "data/banc_coupe.json doit porter bois_0, pierre_0 et fer_0")
	verif.v(par_id.bois_0.transformation_coupe == "coupe_bois", "bois_0 doit declarer transformation_coupe='coupe_bois'")
	verif.v(par_id.pierre_0.transformation_coupe == "coupe_pierre", "pierre_0 doit declarer transformation_coupe='coupe_pierre'")
	verif.v(par_id.fer_0.transformation_coupe == "coupe_fer", "fer_0 doit declarer transformation_coupe='coupe_fer'")

	var positions: Array = []
	for cible in donnees.cibles:
		positions.append(Vector3(cible.position[0], cible.position[1], cible.position[2]))
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			verif.v(positions[i].distance_to(positions[j]) > donnees.rayon_coupe * 2.0, "les cibles doivent etre espacees de plus de deux fois le rayon_coupe -- sinon un clic pres de l'une mettrait aussi l'autre a portee")

func _donnees_reelles_catalogues_partages() -> void:
	var transformations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {})
	verif.v(transformations.get("coupe_bois", {}).get("a_zero", {}).get("produire", {}).get("type_produit", "") == "copeaux_bois", "data/transformations.json:coupe_bois doit produire 'copeaux_bois'")
	verif.v(transformations.get("coupe_pierre", {}).get("a_zero", {}).get("produire", {}).get("type_produit", "") == "eclats_pierre", "data/transformations.json:coupe_pierre doit produire 'eclats_pierre' (reutilise, pas un nouveau materiau)")
	verif.v(transformations.get("coupe_fer", {}).get("a_zero", {}).get("produire", {}).get("type_produit", "") == "limaille_fer", "data/transformations.json:coupe_fer doit produire 'limaille_fer'")

	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	verif.v(materiaux.has("copeaux_bois") and materiaux.copeaux_bois.has("densite"), "data/materiaux.json doit porter 'copeaux_bois' avec une densite")
	verif.v(materiaux.has("limaille_fer") and materiaux.limaille_fer.has("densite"), "data/materiaux.json doit porter 'limaille_fer' avec une densite")

	var types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	verif.v(types.has("copeaux_bois"), "data/types.json doit porter le type 'copeaux_bois'")
	verif.v(types.has("limaille_fer"), "data/types.json doit porter le type 'limaille_fer'")
	verif.v(types.has("eclats_pierre"), "data/types.json doit deja porter 'eclats_pierre' (reutilise depuis banc_fracture.gd)")

const TABLE_FICTIVE := {
	"produit_test": {"composition": [{"materiau": "materiau_produit_test", "volume": 1.0}]},
}
const MATERIAUX_FICTIFS := {
	"materiau_produit_test": {"densite": 2.0},
}
const TRANSFORMATIONS_FICTIVES := {
	"prod_test": {"a_zero": {"produire": {"type_produit": "produit_test", "rendement": 0.8}}},
}
