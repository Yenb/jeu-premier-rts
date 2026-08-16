extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_rigidite.gd
#
# Verrouille le cablage de banc_rigidite.gd, PREMIERE DEMONSTRATION REELLE
# de "rigidite" fusionnee a la fabrication pour un usage MECANIQUE
# (chantier « rigidite -- resistance a la flexion ») : fleche/avancer/
# basculer_charge/fabriquer_objets/diagnostiquer/deplacement_centre
# (fonctions statiques, pures) plus un CHEMIN REEL combinant
# Objet.fabriquer avec data/banc_rigidite.json/data/materiaux.json/
# data/etats.json/data/proprietes_immuables_composition.json lus sur
# disque -- le bois doit reellement flechir plus que le fer, la pierre au
# milieu, et une charge au-dessus du seuil doit reellement fracturer la
# poutre la moins rigide sans fracturer la plus rigide.

const BancRigidite = preload("res://scripts/banc_rigidite.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_fleche_cas_intermediaire()
	_fleche_rigidite_tres_haute_ne_flechit_quasi_pas()
	_fleche_rigidite_nulle_rend_infini()
	_fleche_charge_nulle_rend_zero()

	_avancer_sans_charge_aucune_flexion()
	_avancer_mute_fleche_actuelle_et_maximale()
	_avancer_fleche_maximale_ne_redescend_jamais()
	_avancer_charge_au_dessus_du_seuil_fracture()
	_avancer_fracture_reste_posee_apres_retrait_charge()

	_basculer_charge_inverse_letat()

	_fabriquer_objets_initialise_les_trois_champs()

	_diagnostiquer_rend_les_cinq_champs_attendus()
	_texte_objet_porte_id_et_les_valeurs()
	_ligne_charge_porte_le_temps_et_letat()
	_ligne_fracture_porte_lid_et_la_fleche()

	_deplacement_centre_met_a_lechelle()

	_chemin_reel_fabrication_porte_la_rigidite_fusionnee()
	_chemin_reel_bois_flechit_plus_que_fer()
	_chemin_reel_pierre_flechit_entre_bois_et_fer()
	_chemin_reel_sans_charge_aucune_flexion()
	_chemin_reel_bois_casse_fer_resiste()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: fleche bornee et proportionnelle, avancer mute fleche_actuelle/" +
		"fleche_maximale_atteinte (monotone) et pose fracture via SeuilEtat, " +
		"basculer_charge inverse, diagnostic/textes corrects, chemin reel " +
		"(data/banc_rigidite.json/materiaux.json/etats.json/proprietes_" +
		"immuables_composition.json) ou rigidite est bien fusionnee a la " +
		"fabrication, le bois flechit plus que le fer, la pierre au milieu, " +
		"et une charge au-dessus du seuil fracture le bois sans fracturer le fer")
	quit(0)

# ---- fleche ----

func _fleche_cas_intermediaire() -> void:
	var f := BancRigidite.fleche(100.0, 10.0)
	verif.v(is_equal_approx(f, 10.0), "charge 100.0 / rigidite 10.0 = 10.0, recu %f" % f)

func _fleche_rigidite_tres_haute_ne_flechit_quasi_pas() -> void:
	var f := BancRigidite.fleche(500.0, 1000000.0)
	verif.v(f < 0.001, "rigidite tres haute (1e6) : la fleche doit etre quasi nulle, recu %f" % f)

func _fleche_rigidite_nulle_rend_infini() -> void:
	var f := BancRigidite.fleche(100.0, 0.0)
	verif.v(is_inf(f), "rigidite effective 0.0 (donnee incoherente) : fleche doit etre INF, recu %f" % f)

func _fleche_charge_nulle_rend_zero() -> void:
	var f := BancRigidite.fleche(0.0, 50.0)
	verif.v(is_equal_approx(f, 0.0), "charge nulle : fleche doit etre EXACTEMENT 0.0, recu %f" % f)

# ---- avancer ----

func _objet_test(id: String, rigidite_base: float) -> Dictionary:
	return {
		"id": id,
		"position": Vector3.ZERO,
		"proprietes": {
			"rigidite": rigidite_base,
			"etats_actifs": [],
			"fleche_actuelle": 0.0,
			"fleche_maximale_atteinte": 0.0,
		},
	}

func _catalogue_seuil_test(seuil: float) -> Dictionary:
	return {
		"fracture_flexion": {
			"propriete_continue": "fleche_maximale_atteinte",
			"seuil": seuil,
			"etat": "fracture",
		},
	}

func _avancer_sans_charge_aucune_flexion() -> void:
	var objet := _objet_test("x", 10.0)
	BancRigidite.avancer([objet], 500.0, false, {}, _catalogue_seuil_test(20.0))
	verif.v(is_equal_approx(objet.proprietes.fleche_actuelle, 0.0), "charge_active faux : fleche_actuelle doit rester EXACTEMENT 0.0, recu %f" % objet.proprietes.fleche_actuelle)
	verif.v(is_equal_approx(objet.proprietes.fleche_maximale_atteinte, 0.0), "charge_active faux : fleche_maximale_atteinte doit rester EXACTEMENT 0.0, recu %f" % objet.proprietes.fleche_maximale_atteinte)

func _avancer_mute_fleche_actuelle_et_maximale() -> void:
	var objet := _objet_test("x", 10.0)
	BancRigidite.avancer([objet], 100.0, true, {}, _catalogue_seuil_test(1000.0))
	verif.v(is_equal_approx(objet.proprietes.fleche_actuelle, 10.0), "charge active, 100.0/10.0 : fleche_actuelle attendue 10.0, recu %f" % objet.proprietes.fleche_actuelle)
	verif.v(is_equal_approx(objet.proprietes.fleche_maximale_atteinte, 10.0), "premier pas : fleche_maximale_atteinte doit egaler la fleche courante, recu %f" % objet.proprietes.fleche_maximale_atteinte)

func _avancer_fleche_maximale_ne_redescend_jamais() -> void:
	var objet := _objet_test("x", 10.0)
	BancRigidite.avancer([objet], 100.0, true, {}, _catalogue_seuil_test(1000.0))
	BancRigidite.avancer([objet], 0.0, false, {}, _catalogue_seuil_test(1000.0))
	verif.v(is_equal_approx(objet.proprietes.fleche_actuelle, 0.0), "charge retiree : fleche_actuelle doit retomber a 0.0, recu %f" % objet.proprietes.fleche_actuelle)
	verif.v(is_equal_approx(objet.proprietes.fleche_maximale_atteinte, 10.0), "charge retiree : fleche_maximale_atteinte doit rester a son maximum passe (10.0), jamais redescendre, recu %f" % objet.proprietes.fleche_maximale_atteinte)

func _avancer_charge_au_dessus_du_seuil_fracture() -> void:
	var objet := _objet_test("faible", 10.0)
	var bascules := BancRigidite.avancer([objet], 500.0, true, {}, _catalogue_seuil_test(20.0))
	verif.v(bascules.has("faible"), "charge 500.0 / rigidite 10.0 = 50.0 > seuil 20.0 : doit basculer et fracturer, bascules=%s" % str(bascules))
	verif.v(BancRigidite.est_fracture(objet), "fleche au-dessus du seuil : l'objet doit porter 'fracture'")

func _avancer_fracture_reste_posee_apres_retrait_charge() -> void:
	# etats non vide (contient 'fracture', effets=[]) : l'objet portera
	# 'fracture' des le premier appel, un catalogue {} ferait alarmer
	# etat_effectif.gd sur une reference cassee au second appel (voir
	# etat_effectif.gd, "Un nom present dans etats_actifs mais absent du
	# catalogue est une reference cassee").
	var etats := {"fracture": {"effets": []}}
	var objet := _objet_test("faible", 10.0)
	BancRigidite.avancer([objet], 500.0, true, etats, _catalogue_seuil_test(20.0))
	verif.v(BancRigidite.est_fracture(objet), "garde : doit etre fracture apres la charge")
	BancRigidite.avancer([objet], 500.0, false, etats, _catalogue_seuil_test(20.0))
	verif.v(BancRigidite.est_fracture(objet), "charge retiree APRES fracture : l'etat doit rester pose (fleche_maximale_atteinte ne redescend jamais)")

# ---- basculer_charge ----

func _basculer_charge_inverse_letat() -> void:
	verif.v(BancRigidite.basculer_charge(false) == true, "basculer_charge(false) doit rendre true")
	verif.v(BancRigidite.basculer_charge(true) == false, "basculer_charge(true) doit rendre false")

# ---- fabriquer_objets ----

func _fabriquer_objets_initialise_les_trois_champs() -> void:
	var materiaux := {"bois": {"densite": 0.6, "rigidite": 11.0}}
	var declarations := [{"id": "poutre_x", "position": [0.0, 0.0, 0.0], "composition": [{"materiau": "bois", "volume": 1.0}]}]
	var objets := BancRigidite.fabriquer_objets(declarations, materiaux, ["rigidite"])
	verif.v(objets.size() == 1, "une declaration doit produire un objet, recu %d" % objets.size())
	var objet: Dictionary = objets[0]
	verif.v(is_equal_approx(objet.proprietes.get("rigidite", -1.0), 11.0), "rigidite doit etre fusionnee depuis le materiau, recu %f" % objet.proprietes.get("rigidite", -1.0))
	verif.v(objet.proprietes.etats_actifs.is_empty(), "etats_actifs doit demarrer vide")
	verif.v(is_equal_approx(objet.proprietes.fleche_actuelle, 0.0), "fleche_actuelle doit demarrer a 0.0")
	verif.v(is_equal_approx(objet.proprietes.fleche_maximale_atteinte, 0.0), "fleche_maximale_atteinte doit demarrer a 0.0")

# ---- diagnostiquer / textes ----

func _diagnostiquer_rend_les_cinq_champs_attendus() -> void:
	var objet := _objet_test("x", 50.0)
	objet.proprietes.fleche_actuelle = 12.5
	objet.proprietes.fleche_maximale_atteinte = 15.0
	var diag := BancRigidite.diagnostiquer(objet, {})
	verif.v(is_equal_approx(diag.rigidite_base, 50.0), "rigidite_base doit etre la valeur de base non modulee")
	verif.v(is_equal_approx(diag.rigidite_effective, 50.0), "rigidite_effective sans etat actif doit egaler la base")
	verif.v(is_equal_approx(diag.fleche_actuelle, 12.5), "fleche_actuelle doit refleter proprietes.fleche_actuelle")
	verif.v(is_equal_approx(diag.fleche_maximale_atteinte, 15.0), "fleche_maximale_atteinte doit refleter proprietes.fleche_maximale_atteinte")
	verif.v(not diag.fracture, "sans 'fracture' dans etats_actifs, diag.fracture doit etre faux")

func _texte_objet_porte_id_et_les_valeurs() -> void:
	var texte := BancRigidite.texte_objet("bois_rigidite", {"rigidite_base": 11.0, "rigidite_effective": 11.0, "fleche_actuelle": 45.5, "fleche_maximale_atteinte": 45.5, "fracture": true})
	verif.v(texte.find("bois_rigidite") != -1, "le texte doit porter l'id de l'objet")
	verif.v(texte.find("11.0") != -1, "le texte doit porter la rigidite")
	verif.v(texte.find("45.50") != -1, "le texte doit porter la fleche")
	verif.v(texte.find("fracture") != -1, "le texte doit porter l'etat fracture")

func _ligne_charge_porte_le_temps_et_letat() -> void:
	var ligne := BancRigidite.ligne_charge(3.0, true)
	verif.v(ligne.find("t=3.0") != -1, "la ligne doit porter le temps")
	verif.v(ligne.find("POSEE") != -1, "la ligne doit dire POSEE quand actif=true")
	var ligne2 := BancRigidite.ligne_charge(4.0, false)
	verif.v(ligne2.find("RETIREE") != -1, "la ligne doit dire RETIREE quand actif=false")

func _ligne_fracture_porte_lid_et_la_fleche() -> void:
	var ligne := BancRigidite.ligne_fracture(5.0, "bois_rigidite", {"fleche_maximale_atteinte": 45.5, "rigidite_effective": 11.0})
	verif.v(ligne.find("bois_rigidite") != -1, "la ligne doit porter l'id de la poutre")
	verif.v(ligne.find("FRACTURE") != -1, "la ligne doit dire FRACTURE")
	verif.v(ligne.find("45.50") != -1, "la ligne doit porter la fleche maximale")

# ---- deplacement_centre ----

func _deplacement_centre_met_a_lechelle() -> void:
	var d := BancRigidite.deplacement_centre(10.0, 3.0)
	verif.v(is_equal_approx(d, 30.0), "deplacement_centre(10.0, 3.0) doit rendre 30.0, recu %f" % d)
	verif.v(is_equal_approx(BancRigidite.deplacement_centre(0.0, 3.0), 0.0), "sans fleche, aucun deplacement")

# ---- Chemin reel ----

func _catalogue_etats_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))

func _materiaux_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))

func _proprietes_immuables_reelles() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])

func _donnees_banc_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_rigidite.json"))

func _objets_reels() -> Array:
	var donnees := _donnees_banc_reelles()
	return BancRigidite.fabriquer_objets(donnees.get("objets", []), _materiaux_reels(), _proprietes_immuables_reelles())

func _par_id(objets: Array) -> Dictionary:
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	return par_id

func _chemin_reel_fabrication_porte_la_rigidite_fusionnee() -> void:
	var par_id := _par_id(_objets_reels())
	verif.v(par_id.size() == 3, "data/banc_rigidite.json doit declarer exactement trois objets, recu %d" % par_id.size())
	verif.v(is_equal_approx(par_id.bois_rigidite.proprietes.get("rigidite", -1.0), 11.0), "chemin reel : bois_rigidite doit porter rigidite FUSIONNEE 11.0 (data/materiaux.json:bois), recu %f" % par_id.bois_rigidite.proprietes.get("rigidite", -1.0))
	verif.v(is_equal_approx(par_id.pierre_rigidite.proprietes.get("rigidite", -1.0), 50.0), "chemin reel : pierre_rigidite doit porter rigidite FUSIONNEE 50.0 (data/materiaux.json:pierre), recu %f" % par_id.pierre_rigidite.proprietes.get("rigidite", -1.0))
	verif.v(is_equal_approx(par_id.fer_rigidite.proprietes.get("rigidite", -1.0), 200.0), "chemin reel : fer_rigidite doit porter rigidite FUSIONNEE 200.0 (data/materiaux.json:fer), recu %f" % par_id.fer_rigidite.proprietes.get("rigidite", -1.0))

func _catalogue_seuils_reel(donnees: Dictionary) -> Dictionary:
	return {
		"fracture_flexion": {
			"propriete_continue": "fleche_maximale_atteinte",
			"seuil": donnees.get("seuil_flexion", INF),
			"etat": "fracture",
		},
	}

func _chemin_reel_bois_flechit_plus_que_fer() -> void:
	var donnees := _donnees_banc_reelles()
	var etats := _catalogue_etats_reel()
	var par_id := _par_id(_objets_reels())
	BancRigidite.avancer(par_id.values(), donnees.get("charge_valeur", 0.0), true, etats, _catalogue_seuils_reel(donnees))
	var f_bois: float = par_id.bois_rigidite.proprietes.fleche_actuelle
	var f_fer: float = par_id.fer_rigidite.proprietes.fleche_actuelle
	verif.v(f_bois > f_fer, "chemin reel : le bois (rigidite 11.0) doit flechir plus que le fer (rigidite 200.0) sous la meme charge -- bois=%f fer=%f" % [f_bois, f_fer])

func _chemin_reel_pierre_flechit_entre_bois_et_fer() -> void:
	var donnees := _donnees_banc_reelles()
	var etats := _catalogue_etats_reel()
	var par_id := _par_id(_objets_reels())
	BancRigidite.avancer(par_id.values(), donnees.get("charge_valeur", 0.0), true, etats, _catalogue_seuils_reel(donnees))
	var f_bois: float = par_id.bois_rigidite.proprietes.fleche_actuelle
	var f_pierre: float = par_id.pierre_rigidite.proprietes.fleche_actuelle
	var f_fer: float = par_id.fer_rigidite.proprietes.fleche_actuelle
	verif.v(f_fer < f_pierre, "chemin reel : le fer doit flechir moins que la pierre -- fer=%f pierre=%f" % [f_fer, f_pierre])
	verif.v(f_pierre < f_bois, "chemin reel : la pierre doit flechir moins que le bois -- pierre=%f bois=%f" % [f_pierre, f_bois])

func _chemin_reel_sans_charge_aucune_flexion() -> void:
	var donnees := _donnees_banc_reelles()
	var etats := _catalogue_etats_reel()
	var par_id := _par_id(_objets_reels())
	BancRigidite.avancer(par_id.values(), donnees.get("charge_valeur", 0.0), false, etats, _catalogue_seuils_reel(donnees))
	for id in ["bois_rigidite", "pierre_rigidite", "fer_rigidite"]:
		var f: float = par_id[id].proprietes.fleche_actuelle
		verif.v(is_equal_approx(f, 0.0), "chemin reel, charge jamais posee : '%s' doit avoir une fleche EXACTEMENT nulle, recu %f" % [id, f])

func _chemin_reel_bois_casse_fer_resiste() -> void:
	var donnees := _donnees_banc_reelles()
	var etats := _catalogue_etats_reel()
	var par_id := _par_id(_objets_reels())
	BancRigidite.avancer(par_id.values(), donnees.get("charge_valeur", 0.0), true, etats, _catalogue_seuils_reel(donnees))
	verif.v(BancRigidite.est_fracture(par_id.bois_rigidite), "chemin reel, charge de demonstration : le bois doit fracturer (fleche %f > seuil %f)" % [par_id.bois_rigidite.proprietes.fleche_actuelle, donnees.get("seuil_flexion", INF)])
	verif.v(not BancRigidite.est_fracture(par_id.fer_rigidite), "chemin reel, charge de demonstration : le fer doit resister (fleche %f <= seuil %f)" % [par_id.fer_rigidite.proprietes.fleche_actuelle, donnees.get("seuil_flexion", INF)])
