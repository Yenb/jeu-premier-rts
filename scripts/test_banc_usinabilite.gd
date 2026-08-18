extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_usinabilite.gd
#
# Verrouille le cablage de banc_usinabilite.gd, PREMIERE DEMONSTRATION REELLE
# de "usinabilite" fusionnee a la fabrication (chantier « usinabilite --
# temps de fabrication par materiau ») : cout_effectif/avancer/
# basculer_fabrication/travail_restant/est_fabrique/fabriquer_objets/
# diagnostiquer/doit_imprimer_recap (fonctions statiques, pures) plus un
# CHEMIN REEL combinant Objet.fabriquer avec data/banc_usinabilite.json/
# data/materiaux.json/data/etats.json/data/proprietes_immuables_
# composition.json lus sur disque -- le bois doit reellement finir avant
# le fer, qui doit finir avant la pierre.

const BancUsinabilite = preload("res://scripts/banc_usinabilite.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_cout_effectif_proportionnel_a_usinabilite()
	_cout_effectif_usinabilite_nulle_rend_zero()

	_avancer_inactif_ne_consomme_rien()
	_avancer_actif_consomme_la_reserve()
	_avancer_ne_passe_jamais_en_negatif()

	_basculer_fabrication_inverse_letat()

	_travail_restant_lit_la_reserve()
	_est_fabrique_vrai_seulement_a_reserve_nulle()

	_diagnostiquer_rend_les_quatre_champs_attendus()
	_texte_objet_porte_id_et_les_valeurs()
	_ligne_recap_porte_le_temps_et_chaque_id()

	_doit_imprimer_recap_sous_lintervalle_faux_au_dela_vrai()
	_doit_imprimer_recap_intervalle_non_positif_imprime_toujours()

	_usinabilite_maximale_finit_le_plus_vite()
	_usinabilite_tres_basse_prend_tres_longtemps()

	_chemin_reel_fabrication_porte_lusinabilite_fusionnee()
	_chemin_reel_bois_finit_avant_fer()
	_chemin_reel_fer_finit_avant_pierre()
	_chemin_reel_inactif_ne_progresse_pas()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: cout_effectif proportionnel a usinabilite, avancer respecte le " +
		"drapeau actif et ne descend jamais sous zero, bascule/diagnostic/textes/" +
		"recap corrects, usinabilite extreme (1.0/tres basse) confirmee en " +
		"fonction pure, chemin reel (data/banc_usinabilite.json/materiaux.json/" +
		"etats.json/proprietes_immuables_composition.json) ou usinabilite est " +
		"bien fusionnee a la fabrication, et le bois finit avant le fer, qui " +
		"finit avant la pierre")
	quit(0)

# ---- cout_effectif ----

func _cout_effectif_proportionnel_a_usinabilite() -> void:
	var c_bas := BancUsinabilite.cout_effectif(2.0, 0.3)
	var c_haut := BancUsinabilite.cout_effectif(2.0, 0.8)
	verif.v(is_equal_approx(c_bas, 0.6), "cout_effectif(2.0, 0.3) doit valoir 0.6 exact, recu %f" % c_bas)
	verif.v(is_equal_approx(c_haut, 1.6), "cout_effectif(2.0, 0.8) doit valoir 1.6 exact, recu %f" % c_haut)
	verif.v(c_haut > c_bas, "usinabilite plus haute doit produire un cout_effectif STRICTEMENT plus grand (consomme plus vite)")

func _cout_effectif_usinabilite_nulle_rend_zero() -> void:
	var c := BancUsinabilite.cout_effectif(5.0, 0.0)
	verif.v(is_equal_approx(c, 0.0), "usinabilite 0.0 : cout_effectif doit etre EXACTEMENT 0.0 (jamais de fabrication), recu %f" % c)

# ---- avancer ----

func _objet_test(id: String, reserve: float, cout_base: float) -> Dictionary:
	return {
		"id": id,
		"position": Vector3.ZERO,
		"proprietes": {
			"reserves": {
				"travail": {"reserve": reserve, "cout_base": cout_base, "surcout_action": 0.0},
			},
		},
	}

func _avancer_inactif_ne_consomme_rien() -> void:
	var objet := _objet_test("x", 10.0, 1.0)
	for i in 10:
		BancUsinabilite.avancer([objet], 0.5, false)
	verif.v(is_equal_approx(BancUsinabilite.travail_restant(objet), 10.0), "fabrication inactive : travail_restant ne doit JAMAIS bouger, recu %f" % BancUsinabilite.travail_restant(objet))

func _avancer_actif_consomme_la_reserve() -> void:
	var objet := _objet_test("x", 10.0, 1.0)
	BancUsinabilite.avancer([objet], 1.0, true)
	verif.v(is_equal_approx(BancUsinabilite.travail_restant(objet), 9.0), "fabrication active, cout_base 1.0, delta 1.0 : travail_restant doit descendre a 9.0 exact, recu %f" % BancUsinabilite.travail_restant(objet))

func _avancer_ne_passe_jamais_en_negatif() -> void:
	var objet := _objet_test("x", 1.0, 5.0)
	for i in 20:
		BancUsinabilite.avancer([objet], 1.0, true)
	verif.v(is_equal_approx(BancUsinabilite.travail_restant(objet), 0.0), "reserve epuisee largement au-dela du necessaire : travail_restant doit rester EXACTEMENT 0.0, jamais negatif, recu %f" % BancUsinabilite.travail_restant(objet))

# ---- basculer_fabrication ----

func _basculer_fabrication_inverse_letat() -> void:
	verif.v(BancUsinabilite.basculer_fabrication(false) == true, "basculer_fabrication(false) doit rendre true")
	verif.v(BancUsinabilite.basculer_fabrication(true) == false, "basculer_fabrication(true) doit rendre false")

# ---- travail_restant / est_fabrique ----

func _travail_restant_lit_la_reserve() -> void:
	var objet := _objet_test("x", 4.5, 1.0)
	verif.v(is_equal_approx(BancUsinabilite.travail_restant(objet), 4.5), "travail_restant doit lire exactement proprietes.reserves.travail.reserve")

func _est_fabrique_vrai_seulement_a_reserve_nulle() -> void:
	verif.v(not BancUsinabilite.est_fabrique(_objet_test("x", 0.01, 1.0)), "reserve strictement positive : est_fabrique doit rendre faux")
	verif.v(BancUsinabilite.est_fabrique(_objet_test("x", 0.0, 1.0)), "reserve exactement nulle : est_fabrique doit rendre vrai")

# ---- diagnostiquer / textes ----

func _diagnostiquer_rend_les_quatre_champs_attendus() -> void:
	var objet := _objet_test("x", 3.0, 1.0)
	objet.proprietes["usinabilite"] = 0.8
	objet.proprietes["travail_initial"] = 10.0
	var diag := BancUsinabilite.diagnostiquer(objet)
	verif.v(is_equal_approx(diag.usinabilite, 0.8), "usinabilite doit refleter proprietes.usinabilite")
	verif.v(is_equal_approx(diag.travail_restant, 3.0), "travail_restant doit refleter la reserve")
	verif.v(is_equal_approx(diag.travail_initial, 10.0), "travail_initial doit refleter proprietes.travail_initial")
	verif.v(not diag.fabrique, "reserve non nulle : fabrique doit etre faux")

func _texte_objet_porte_id_et_les_valeurs() -> void:
	var texte := BancUsinabilite.texte_objet("bois_usinabilite", {"usinabilite": 0.8, "travail_restant": 4.5, "travail_initial": 10.0, "fabrique": false})
	verif.v(texte.find("bois_usinabilite") != -1, "le texte doit porter l'id de l'objet")
	verif.v(texte.find("0.80") != -1, "le texte doit porter l'usinabilite")
	verif.v(texte.find("4.50") != -1, "le texte doit porter le travail restant")
	verif.v(texte.find("en cours") != -1, "le texte doit porter l'etat 'en cours' quand non fabrique")

func _ligne_recap_porte_le_temps_et_chaque_id() -> void:
	var a := _objet_test("bois_usinabilite", 3.0, 1.0)
	var b := _objet_test("pierre_usinabilite", 7.0, 1.0)
	var ligne := BancUsinabilite.ligne_recap(5.0, [a, b])
	verif.v(ligne.find("t=5.0") != -1, "la ligne recap doit porter le temps")
	verif.v(ligne.find("bois_usinabilite=3.00") != -1, "la ligne recap doit porter le travail restant du bois")
	verif.v(ligne.find("pierre_usinabilite=7.00") != -1, "la ligne recap doit porter le travail restant de la pierre")

# ---- doit_imprimer_recap ----

func _doit_imprimer_recap_sous_lintervalle_faux_au_dela_vrai() -> void:
	verif.v(not BancUsinabilite.doit_imprimer_recap(1.5, 0.0, 2.0), "1.5s ecoulees, intervalle 2.0 : ne doit PAS imprimer")
	verif.v(BancUsinabilite.doit_imprimer_recap(2.0, 0.0, 2.0), "exactement l'intervalle ecoule : doit imprimer")

func _doit_imprimer_recap_intervalle_non_positif_imprime_toujours() -> void:
	verif.v(BancUsinabilite.doit_imprimer_recap(0.0, 0.0, 0.0), "intervalle a 0.0 (garde degeneree) : doit toujours imprimer")

# ---- usinabilite extreme (fonction pure, hors chemin reel) ----

func _usinabilite_maximale_finit_le_plus_vite() -> void:
	var travail_initial := 10.0
	var objet_max := _objet_test("max", travail_initial, BancUsinabilite.cout_effectif(1.0, 1.0))
	var objet_moyen := _objet_test("moyen", travail_initial, BancUsinabilite.cout_effectif(1.0, 0.5))
	var ticks := 0
	while not BancUsinabilite.est_fabrique(objet_max) and ticks < 1000:
		BancUsinabilite.avancer([objet_max], 0.1, true)
		ticks += 1
	var ticks_max := ticks
	ticks = 0
	while not BancUsinabilite.est_fabrique(objet_moyen) and ticks < 1000:
		BancUsinabilite.avancer([objet_moyen], 0.1, true)
		ticks += 1
	verif.v(ticks_max < ticks, "usinabilite 1.0 doit finir en STRICTEMENT moins de temps qu'usinabilite 0.5, recu %d contre %d ticks" % [ticks_max, ticks])

func _usinabilite_tres_basse_prend_tres_longtemps() -> void:
	var travail_initial := 10.0
	var objet := _objet_test("presque_impossible", travail_initial, BancUsinabilite.cout_effectif(1.0, 0.001))
	for i in 50:
		BancUsinabilite.avancer([objet], 0.1, true)
	verif.v(BancUsinabilite.travail_restant(objet) > travail_initial * 0.9, "usinabilite tres basse (0.001) : apres 5s de fabrication, le travail restant doit avoir a peine bouge, recu %f (initial %f)" % [BancUsinabilite.travail_restant(objet), travail_initial])

# ---- Chemin reel ----

func _catalogue_etats_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))

func _materiaux_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))

func _proprietes_immuables_reelles() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])

func _donnees_banc_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_usinabilite.json"))

func _objets_reels() -> Array:
	var donnees := _donnees_banc_reelles()
	var etats := _catalogue_etats_reel()
	return BancUsinabilite.fabriquer_objets(donnees.get("objets", []), _materiaux_reels(), _proprietes_immuables_reelles(), donnees.get("travail_initial", 10.0), donnees.get("cout_base_reference", 1.0), etats)

func _chemin_reel_fabrication_porte_lusinabilite_fusionnee() -> void:
	var objets := _objets_reels()
	verif.v(objets.size() == 3, "data/banc_usinabilite.json doit declarer exactement trois objets, recu %d" % objets.size())
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	verif.v(is_equal_approx(par_id.bois_usinabilite.proprietes.get("usinabilite", -1.0), 0.8), "chemin reel : bois_usinabilite doit porter usinabilite FUSIONNEE 0.8 (data/materiaux.json:bois), recu %f" % par_id.bois_usinabilite.proprietes.get("usinabilite", -1.0))
	verif.v(is_equal_approx(par_id.pierre_usinabilite.proprietes.get("usinabilite", -1.0), 0.3), "chemin reel : pierre_usinabilite doit porter usinabilite FUSIONNEE 0.3 (data/materiaux.json:pierre), recu %f" % par_id.pierre_usinabilite.proprietes.get("usinabilite", -1.0))
	verif.v(is_equal_approx(par_id.fer_usinabilite.proprietes.get("usinabilite", -1.0), 0.5), "chemin reel : fer_usinabilite doit porter usinabilite FUSIONNEE 0.5 (data/materiaux.json:fer), recu %f" % par_id.fer_usinabilite.proprietes.get("usinabilite", -1.0))

func _chemin_reel_bois_finit_avant_fer() -> void:
	var objets := _objets_reels()
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	var ticks := 0
	while not BancUsinabilite.est_fabrique(par_id.bois_usinabilite) and ticks < 2000:
		BancUsinabilite.avancer(objets, 0.1, true)
		ticks += 1
	verif.v(BancUsinabilite.est_fabrique(par_id.bois_usinabilite), "chemin reel : le bois doit finir par etre fabrique")
	verif.v(not BancUsinabilite.est_fabrique(par_id.fer_usinabilite), "chemin reel : au moment ou le bois finit, le fer (usinabilite plus basse) ne doit PAS etre deja fabrique")

func _chemin_reel_fer_finit_avant_pierre() -> void:
	var objets := _objets_reels()
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	var ticks := 0
	while not BancUsinabilite.est_fabrique(par_id.fer_usinabilite) and ticks < 2000:
		BancUsinabilite.avancer(objets, 0.1, true)
		ticks += 1
	verif.v(BancUsinabilite.est_fabrique(par_id.fer_usinabilite), "chemin reel : le fer doit finir par etre fabrique")
	verif.v(not BancUsinabilite.est_fabrique(par_id.pierre_usinabilite), "chemin reel : au moment ou le fer finit, la pierre (usinabilite la plus basse) ne doit PAS etre deja fabriquee")

func _chemin_reel_inactif_ne_progresse_pas() -> void:
	var objets := _objets_reels()
	for i in 50:
		BancUsinabilite.avancer(objets, 0.1, false)
	for objet in objets:
		verif.v(is_equal_approx(BancUsinabilite.travail_restant(objet), objet.proprietes.travail_initial), "chemin reel, fabrication jamais activee : '%s' doit garder son travail_restant initial intact, recu %f" % [objet.id, BancUsinabilite.travail_restant(objet)])
