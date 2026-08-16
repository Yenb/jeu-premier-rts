extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_traction.gd
#
# Verrouille le cablage de banc_traction.gd, PREMIERE DEMONSTRATION REELLE
# de "resistance_traction" fusionnee a la fabrication (chantier
# « resistance_traction -- rupture par traction ») : fabriquer_objets/
# basculer_force/avancer_force/avancer_rupture/est_rompu/avancer_chute/
# diagnostiquer (fonctions statiques, pures) plus un CHEMIN REEL combinant
# Objet.fabriquer avec data/banc_traction.json/data/materiaux.json/
# data/etats.json/data/seuils_etat.json/data/proprietes_immuables_
# composition.json lus sur disque -- la pierre doit reellement rompre
# avant le bois, le fer doit resister, et sans force rien ne doit casser.

const BancTraction = preload("res://scripts/banc_traction.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_basculer_force_inverse_letat()

	_avancer_force_inactive_ne_change_rien()
	_avancer_force_active_accumule_avec_delta()
	_avancer_force_est_independante_du_framerate()

	_avancer_rupture_pose_letat_au_franchissement_du_seuil()
	_avancer_rupture_sous_le_seuil_ne_rompt_pas()
	_avancer_rupture_reste_posee_apres_retrait_force()

	_fabriquer_objets_initialise_les_quatre_champs()

	_avancer_chute_ignore_un_objet_intact()
	_avancer_chute_fait_tomber_un_objet_rompu()
	_avancer_chute_sarrete_au_sol_et_narrete_jamais_un_objet_deja_tombe()

	_diagnostiquer_rend_les_cinq_champs_attendus()
	_texte_objet_porte_id_et_les_valeurs()
	_ligne_force_porte_le_temps_et_letat()
	_ligne_rupture_porte_lid_et_la_force()
	_ligne_atterrissage_porte_lid()

	_chemin_reel_fabrication_porte_la_resistance_traction_fusionnee()
	_chemin_reel_sans_force_rien_ne_casse()
	_chemin_reel_pierre_rompt_avant_bois_fer_resiste()
	_chemin_reel_objet_rompu_tombe()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: basculer_force inverse, avancer_force accumule avec delta " +
		"(gate stricte sur force_active), avancer_rupture pose 'rompu' via " +
		"SeuilEtat au franchissement, fabriquer_objets initialise les " +
		"champs, avancer_chute fait tomber un objet rompu sous gravite " +
		"jusqu'au sol sans jamais rebondir, diagnostic/textes corrects, " +
		"chemin reel (data/banc_traction.json/materiaux.json/etats.json/" +
		"seuils_etat.json/proprietes_immuables_composition.json lus sur " +
		"disque) ou resistance_traction est bien fusionnee, sans force " +
		"rien ne casse, la pierre rompt avant le bois, le fer resiste, et " +
		"un objet rompu tombe reellement")
	quit(0)

# ---- basculer_force ----

func _basculer_force_inverse_letat() -> void:
	verif.v(BancTraction.basculer_force(false) == true, "basculer_force(false) doit rendre true")
	verif.v(BancTraction.basculer_force(true) == false, "basculer_force(true) doit rendre false")

# ---- avancer_force ----

func _objet_test(id: String, resistance_traction: float) -> Dictionary:
	return {
		"id": id,
		"position": Vector3.ZERO,
		"proprietes": {
			"resistance_traction": resistance_traction,
			"etats_actifs": [],
			"force_traction_cumulee": 0.0,
			"tombe": false,
			"vitesse_chute": 0.0,
		},
	}

func _avancer_force_inactive_ne_change_rien() -> void:
	var objet := _objet_test("x", 90.0)
	BancTraction.avancer_force([objet], false, 15.0, 1.0)
	verif.v(is_equal_approx(objet.proprietes.force_traction_cumulee, 0.0), "force inactive : force_traction_cumulee doit rester EXACTEMENT 0.0, recu %f" % objet.proprietes.force_traction_cumulee)

func _avancer_force_active_accumule_avec_delta() -> void:
	var objet := _objet_test("x", 90.0)
	BancTraction.avancer_force([objet], true, 15.0, 0.5)
	verif.v(is_equal_approx(objet.proprietes.force_traction_cumulee, 7.5), "force active, 15.0*0.5 : force_traction_cumulee attendue 7.5, recu %f" % objet.proprietes.force_traction_cumulee)
	BancTraction.avancer_force([objet], true, 15.0, 0.5)
	verif.v(is_equal_approx(objet.proprietes.force_traction_cumulee, 15.0), "deuxieme pas : force_traction_cumulee doit continuer d'accumuler, attendue 15.0, recu %f" % objet.proprietes.force_traction_cumulee)

func _avancer_force_est_independante_du_framerate() -> void:
	var objet_gros_pas := _objet_test("gros", 90.0)
	BancTraction.avancer_force([objet_gros_pas], true, 10.0, 1.0)
	var objet_petits_pas := _objet_test("petits", 90.0)
	for i in range(10):
		BancTraction.avancer_force([objet_petits_pas], true, 10.0, 0.1)
	verif.v(is_equal_approx(objet_gros_pas.proprietes.force_traction_cumulee, objet_petits_pas.proprietes.force_traction_cumulee), "un gros pas ou dix petits pas doivent accumuler le meme total -- gros=%f petits=%f" % [objet_gros_pas.proprietes.force_traction_cumulee, objet_petits_pas.proprietes.force_traction_cumulee])

# ---- avancer_rupture ----

func _catalogue_seuils_test() -> Dictionary:
	return {
		"traction": {
			"propriete_continue": "force_traction_cumulee",
			"seuil_propriete": "resistance_traction",
			"etat": "rompu",
		},
	}

func _avancer_rupture_pose_letat_au_franchissement_du_seuil() -> void:
	var objet := _objet_test("faible", 5.0)
	objet.proprietes.force_traction_cumulee = 10.0
	var bascules := BancTraction.avancer_rupture([objet], _catalogue_seuils_test())
	verif.v(bascules.has("faible"), "force cumulee 10.0 > resistance 5.0 : doit basculer, bascules=%s" % str(bascules))
	verif.v(BancTraction.est_rompu(objet), "au-dessus du seuil : l'objet doit porter 'rompu'")

func _avancer_rupture_sous_le_seuil_ne_rompt_pas() -> void:
	var objet := _objet_test("solide", 90.0)
	objet.proprietes.force_traction_cumulee = 10.0
	var bascules := BancTraction.avancer_rupture([objet], _catalogue_seuils_test())
	verif.v(not bascules.has("solide"), "force cumulee 10.0 < resistance 90.0 : ne doit pas basculer, bascules=%s" % str(bascules))
	verif.v(not BancTraction.est_rompu(objet), "sous le seuil : l'objet ne doit pas porter 'rompu'")

func _avancer_rupture_reste_posee_apres_retrait_force() -> void:
	var objet := _objet_test("faible", 5.0)
	BancTraction.avancer_force([objet], true, 15.0, 1.0)
	BancTraction.avancer_rupture([objet], _catalogue_seuils_test())
	verif.v(BancTraction.est_rompu(objet), "garde : doit etre rompu apres la force")
	BancTraction.avancer_rupture([objet], _catalogue_seuils_test())
	verif.v(BancTraction.est_rompu(objet), "force retiree APRES rupture : l'etat doit rester pose (force_traction_cumulee ne redescend jamais)")

# ---- fabriquer_objets ----

func _fabriquer_objets_initialise_les_quatre_champs() -> void:
	var materiaux := {"bois": {"densite": 0.6, "resistance_traction": 90.0}}
	var declarations := [{"id": "lien_x", "position": [0.0, 0.0, 0.0], "composition": [{"materiau": "bois", "volume": 1.0}]}]
	var objets := BancTraction.fabriquer_objets(declarations, materiaux, ["resistance_traction"], 250.0)
	verif.v(objets.size() == 1, "une declaration doit produire un objet, recu %d" % objets.size())
	var objet: Dictionary = objets[0]
	verif.v(is_equal_approx(objet.proprietes.get("resistance_traction", -1.0), 90.0), "resistance_traction doit etre fusionnee depuis le materiau, recu %f" % objet.proprietes.get("resistance_traction", -1.0))
	verif.v(objet.proprietes.etats_actifs.is_empty(), "etats_actifs doit demarrer vide")
	verif.v(is_equal_approx(objet.proprietes.force_traction_cumulee, 0.0), "force_traction_cumulee doit demarrer a 0.0")
	verif.v(not objet.proprietes.tombe, "tombe doit demarrer a faux")
	verif.v(is_equal_approx(objet.position.z, 250.0), "position.z doit demarrer a la hauteur de suspension, recu %f" % objet.position.z)

# ---- avancer_chute ----

func _avancer_chute_ignore_un_objet_intact() -> void:
	var objet := _objet_test("intact", 90.0)
	objet.position.z = 250.0
	var atterris := BancTraction.avancer_chute([objet], 900.0, 1.0)
	verif.v(atterris.is_empty(), "un objet intact (pas 'rompu') ne doit jamais atterrir")
	verif.v(is_equal_approx(objet.position.z, 250.0), "un objet intact ne doit jamais bouger, recu %f" % objet.position.z)

func _avancer_chute_fait_tomber_un_objet_rompu() -> void:
	var objet := _objet_test("rompu", 90.0)
	objet.proprietes.etats_actifs = ["rompu"]
	objet.position.z = 250.0
	BancTraction.avancer_chute([objet], 900.0, 0.1)
	verif.v(objet.position.z < 250.0, "un objet rompu doit avoir commence a tomber, recu %f" % objet.position.z)
	verif.v(not objet.proprietes.tombe, "un seul petit pas ne doit pas encore atteindre le sol")

func _avancer_chute_sarrete_au_sol_et_narrete_jamais_un_objet_deja_tombe() -> void:
	var objet := _objet_test("rompu", 90.0)
	objet.proprietes.etats_actifs = ["rompu"]
	objet.position.z = 250.0
	for i in range(200):
		BancTraction.avancer_chute([objet], 900.0, 0.05)
	verif.v(is_equal_approx(objet.position.z, 0.0), "apres assez de temps, l'objet doit s'etre pose exactement au sol, recu %f" % objet.position.z)
	verif.v(objet.proprietes.tombe, "l'objet doit porter 'tombe' une fois au sol")
	var z_avant: float = objet.position.z
	BancTraction.avancer_chute([objet], 900.0, 0.05)
	verif.v(is_equal_approx(objet.position.z, z_avant), "un objet deja tombe ne doit plus jamais bouger (aucun rebond), recu %f" % objet.position.z)

# ---- diagnostiquer / textes ----

func _diagnostiquer_rend_les_cinq_champs_attendus() -> void:
	var objet := _objet_test("x", 90.0)
	objet.proprietes.force_traction_cumulee = 12.5
	objet.position.z = 100.0
	var diag := BancTraction.diagnostiquer(objet)
	verif.v(is_equal_approx(diag.resistance_traction, 90.0), "resistance_traction doit refleter proprietes.resistance_traction")
	verif.v(is_equal_approx(diag.force_traction_cumulee, 12.5), "force_traction_cumulee doit refleter proprietes.force_traction_cumulee")
	verif.v(not diag.rompu, "sans 'rompu' dans etats_actifs, diag.rompu doit etre faux")
	verif.v(is_equal_approx(diag.hauteur, 100.0), "hauteur doit refleter position.z")
	verif.v(not diag.tombe, "sans 'tombe', diag.tombe doit etre faux")

func _texte_objet_porte_id_et_les_valeurs() -> void:
	var texte := BancTraction.texte_objet("pierre_traction", {"resistance_traction": 5.0, "force_traction_cumulee": 6.0, "rompu": true})
	verif.v(texte.find("pierre_traction") != -1, "le texte doit porter l'id de l'objet")
	verif.v(texte.find("5.0") != -1, "le texte doit porter la resistance_traction")
	verif.v(texte.find("6.00") != -1, "le texte doit porter la force cumulee")
	verif.v(texte.find("rompu") != -1, "le texte doit porter l'etat rompu")

func _ligne_force_porte_le_temps_et_letat() -> void:
	var ligne := BancTraction.ligne_force(3.0, true)
	verif.v(ligne.find("t=3.0") != -1, "la ligne doit porter le temps")
	verif.v(ligne.find("POSEE") != -1, "la ligne doit dire POSEE quand actif=true")
	var ligne2 := BancTraction.ligne_force(4.0, false)
	verif.v(ligne2.find("RETIREE") != -1, "la ligne doit dire RETIREE quand actif=false")

func _ligne_rupture_porte_lid_et_la_force() -> void:
	var ligne := BancTraction.ligne_rupture(5.0, "pierre_traction", {"force_traction_cumulee": 6.0, "resistance_traction": 5.0})
	verif.v(ligne.find("pierre_traction") != -1, "la ligne doit porter l'id de l'objet")
	verif.v(ligne.find("ROMPU") != -1, "la ligne doit dire ROMPU")
	verif.v(ligne.find("6.00") != -1, "la ligne doit porter la force cumulee")

func _ligne_atterrissage_porte_lid() -> void:
	var ligne := BancTraction.ligne_atterrissage(7.0, "pierre_traction")
	verif.v(ligne.find("pierre_traction") != -1, "la ligne doit porter l'id de l'objet")
	verif.v(ligne.find("t=7.0") != -1, "la ligne doit porter le temps")

# ---- Chemin reel ----

func _catalogue_seuils_etat_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json"))

func _materiaux_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))

func _proprietes_immuables_reelles() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])

func _donnees_banc_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_traction.json"))

func _objets_reels() -> Array:
	var donnees := _donnees_banc_reelles()
	return BancTraction.fabriquer_objets(donnees.get("objets", []), _materiaux_reels(), _proprietes_immuables_reelles(), donnees.get("hauteur_suspension", 250.0))

func _par_id(objets: Array) -> Dictionary:
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	return par_id

func _chemin_reel_fabrication_porte_la_resistance_traction_fusionnee() -> void:
	var par_id := _par_id(_objets_reels())
	verif.v(par_id.size() == 3, "data/banc_traction.json doit declarer exactement trois objets, recu %d" % par_id.size())
	verif.v(is_equal_approx(par_id.bois_traction.proprietes.get("resistance_traction", -1.0), 90.0), "chemin reel : bois_traction doit porter resistance_traction FUSIONNEE 90.0 (data/materiaux.json:bois), recu %f" % par_id.bois_traction.proprietes.get("resistance_traction", -1.0))
	verif.v(is_equal_approx(par_id.pierre_traction.proprietes.get("resistance_traction", -1.0), 5.0), "chemin reel : pierre_traction doit porter resistance_traction FUSIONNEE 5.0 (data/materiaux.json:pierre), recu %f" % par_id.pierre_traction.proprietes.get("resistance_traction", -1.0))
	verif.v(is_equal_approx(par_id.fer_traction.proprietes.get("resistance_traction", -1.0), 250.0), "chemin reel : fer_traction doit porter resistance_traction FUSIONNEE 250.0 (data/materiaux.json:fer), recu %f" % par_id.fer_traction.proprietes.get("resistance_traction", -1.0))

func _chemin_reel_sans_force_rien_ne_casse() -> void:
	var etats_seuil := _catalogue_seuils_etat_reel()
	var par_id := _par_id(_objets_reels())
	for i in range(200):
		BancTraction.avancer_force(par_id.values(), false, 15.0, 0.1)
		BancTraction.avancer_rupture(par_id.values(), etats_seuil)
	for id in ["bois_traction", "pierre_traction", "fer_traction"]:
		verif.v(not BancTraction.est_rompu(par_id[id]), "chemin reel, force jamais posee : '%s' ne doit jamais rompre" % id)
		verif.v(is_equal_approx(par_id[id].proprietes.force_traction_cumulee, 0.0), "chemin reel, force jamais posee : '%s' doit avoir une force cumulee EXACTEMENT nulle, recu %f" % [id, par_id[id].proprietes.force_traction_cumulee])

func _chemin_reel_pierre_rompt_avant_bois_fer_resiste() -> void:
	var donnees := _donnees_banc_reelles()
	var etats_seuil := _catalogue_seuils_etat_reel()
	var par_id := _par_id(_objets_reels())
	var force_valeur: float = donnees.get("force_valeur", 0.0)
	var delta := 0.1
	var temps_rupture: Dictionary = {}
	for i in range(200):
		BancTraction.avancer_force(par_id.values(), true, force_valeur, delta)
		var bascules := BancTraction.avancer_rupture(par_id.values(), etats_seuil)
		for id in bascules:
			if not temps_rupture.has(id) and BancTraction.est_rompu(par_id[id]):
				temps_rupture[id] = (i + 1) * delta
	verif.v(temps_rupture.has("pierre_traction"), "chemin reel, charge de demonstration : la pierre doit rompre")
	verif.v(temps_rupture.has("bois_traction"), "chemin reel, charge de demonstration : le bois doit rompre")
	verif.v(not temps_rupture.has("fer_traction"), "chemin reel, charge de demonstration : le fer doit resister sur toute la duree simulee")
	if temps_rupture.has("pierre_traction") and temps_rupture.has("bois_traction"):
		verif.v(temps_rupture.pierre_traction < temps_rupture.bois_traction, "la pierre doit rompre AVANT le bois -- pierre=%f bois=%f" % [temps_rupture.pierre_traction, temps_rupture.bois_traction])

func _chemin_reel_objet_rompu_tombe() -> void:
	var donnees := _donnees_banc_reelles()
	var etats_seuil := _catalogue_seuils_etat_reel()
	var gravite: float = donnees.get("gravite", 900.0)
	var par_id := _par_id(_objets_reels())
	var force_valeur: float = donnees.get("force_valeur", 0.0)
	var delta := 0.1
	for i in range(20):
		BancTraction.avancer_force(par_id.values(), true, force_valeur, delta)
		BancTraction.avancer_rupture(par_id.values(), etats_seuil)
		BancTraction.avancer_chute(par_id.values(), gravite, delta)
	verif.v(BancTraction.est_rompu(par_id.pierre_traction), "chemin reel : la pierre doit deja etre rompue apres 2s de force")
	verif.v(par_id.pierre_traction.position.z < donnees.get("hauteur_suspension", 250.0), "chemin reel : la pierre rompue doit avoir commence a tomber, hauteur=%f" % par_id.pierre_traction.position.z)
	verif.v(not BancTraction.est_rompu(par_id.fer_traction), "chemin reel : le fer, intact, ne doit pas tomber")
	verif.v(is_equal_approx(par_id.fer_traction.position.z, donnees.get("hauteur_suspension", 250.0)), "chemin reel : le fer intact doit rester a sa hauteur de suspension, recu %f" % par_id.fer_traction.position.z)
