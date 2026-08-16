extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_acide.gd
#
# Verrouille le cablage de banc_acide.gd, PREMIERE DEMONSTRATION REELLE de
# "resistance_acide" fusionnee a la fabrication (chantier « resistance_acide
# -- corrosion par acide ») : fabriquer_objets/basculer_source/
# avancer_exposition/avancer_corrosion/est_corrode/diagnostiquer (fonctions
# statiques, pures) plus un CHEMIN REEL combinant Objet.fabriquer avec
# data/banc_acide.json/data/materiaux.json/data/etats.json/
# data/seuils_etat.json/data/proprietes_immuables_composition.json lus sur
# disque -- le fer doit reellement corroder avant la pierre, la pierre
# avant le bois, et sans source rien ne doit corroder.

const BancAcide = preload("res://scripts/banc_acide.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_basculer_source_inverse_letat()

	_avancer_exposition_inactive_ne_change_rien()
	_avancer_exposition_active_accumule_avec_delta()
	_avancer_exposition_est_independante_du_framerate()

	_avancer_corrosion_pose_letat_au_franchissement_du_seuil()
	_avancer_corrosion_sous_le_seuil_ne_corrode_pas()
	_avancer_corrosion_reste_posee_apres_retrait_source()

	_fabriquer_objets_initialise_les_deux_champs()

	_diagnostiquer_rend_les_trois_champs_attendus()
	_texte_objet_porte_id_et_les_valeurs()
	_ligne_source_porte_le_temps_et_letat()
	_ligne_corrosion_porte_lid_et_lexposition()

	_chemin_reel_fabrication_porte_la_resistance_acide_fusionnee()
	_chemin_reel_sans_source_rien_ne_corrode()
	_chemin_reel_fer_corrode_avant_pierre_avant_bois()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: basculer_source inverse, avancer_exposition accumule avec " +
		"delta (gate stricte sur source_active), avancer_corrosion pose " +
		"'corrode_acide' via SeuilEtat au franchissement, fabriquer_objets " +
		"initialise les champs, diagnostic/textes corrects, chemin reel " +
		"(data/banc_acide.json/materiaux.json/etats.json/seuils_etat.json/" +
		"proprietes_immuables_composition.json lus sur disque) ou " +
		"resistance_acide est bien fusionnee, sans source rien ne corrode, " +
		"le fer corrode avant la pierre, qui corrode avant le bois")
	quit(0)

# ---- basculer_source ----

func _basculer_source_inverse_letat() -> void:
	verif.v(BancAcide.basculer_source(false) == true, "basculer_source(false) doit rendre true")
	verif.v(BancAcide.basculer_source(true) == false, "basculer_source(true) doit rendre false")

# ---- avancer_exposition ----

func _objet_test(id: String, resistance_acide: float) -> Dictionary:
	return {
		"id": id,
		"position": Vector3.ZERO,
		"proprietes": {
			"resistance_acide": resistance_acide,
			"etats_actifs": [],
			"exposition_acide_cumulee": 0.0,
		},
	}

func _avancer_exposition_inactive_ne_change_rien() -> void:
	var objet := _objet_test("x", 0.5)
	BancAcide.avancer_exposition([objet], false, 0.05, 1.0)
	verif.v(is_equal_approx(objet.proprietes.exposition_acide_cumulee, 0.0), "source inactive : exposition_acide_cumulee doit rester EXACTEMENT 0.0, recu %f" % objet.proprietes.exposition_acide_cumulee)

func _avancer_exposition_active_accumule_avec_delta() -> void:
	var objet := _objet_test("x", 0.5)
	BancAcide.avancer_exposition([objet], true, 0.05, 0.5)
	verif.v(is_equal_approx(objet.proprietes.exposition_acide_cumulee, 0.025), "source active, 0.05*0.5 : exposition_acide_cumulee attendue 0.025, recu %f" % objet.proprietes.exposition_acide_cumulee)
	BancAcide.avancer_exposition([objet], true, 0.05, 0.5)
	verif.v(is_equal_approx(objet.proprietes.exposition_acide_cumulee, 0.05), "deuxieme pas : exposition_acide_cumulee doit continuer d'accumuler, attendue 0.05, recu %f" % objet.proprietes.exposition_acide_cumulee)

func _avancer_exposition_est_independante_du_framerate() -> void:
	var objet_gros_pas := _objet_test("gros", 0.5)
	BancAcide.avancer_exposition([objet_gros_pas], true, 0.1, 1.0)
	var objet_petits_pas := _objet_test("petits", 0.5)
	for i in range(10):
		BancAcide.avancer_exposition([objet_petits_pas], true, 0.1, 0.1)
	verif.v(is_equal_approx(objet_gros_pas.proprietes.exposition_acide_cumulee, objet_petits_pas.proprietes.exposition_acide_cumulee), "un gros pas ou dix petits pas doivent accumuler le meme total -- gros=%f petits=%f" % [objet_gros_pas.proprietes.exposition_acide_cumulee, objet_petits_pas.proprietes.exposition_acide_cumulee])

# ---- avancer_corrosion ----

func _catalogue_seuils_test() -> Dictionary:
	return {
		"acide": {
			"propriete_continue": "exposition_acide_cumulee",
			"seuil_propriete": "resistance_acide",
			"etat": "corrode_acide",
		},
	}

func _avancer_corrosion_pose_letat_au_franchissement_du_seuil() -> void:
	var objet := _objet_test("faible", 0.1)
	objet.proprietes.exposition_acide_cumulee = 0.2
	var bascules := BancAcide.avancer_corrosion([objet], _catalogue_seuils_test())
	verif.v(bascules.has("faible"), "exposition cumulee 0.2 > resistance 0.1 : doit basculer, bascules=%s" % str(bascules))
	verif.v(BancAcide.est_corrode(objet), "au-dessus du seuil : l'objet doit porter 'corrode_acide'")

func _avancer_corrosion_sous_le_seuil_ne_corrode_pas() -> void:
	var objet := _objet_test("resistant", 0.5)
	objet.proprietes.exposition_acide_cumulee = 0.2
	var bascules := BancAcide.avancer_corrosion([objet], _catalogue_seuils_test())
	verif.v(not bascules.has("resistant"), "exposition cumulee 0.2 < resistance 0.5 : ne doit pas basculer, bascules=%s" % str(bascules))
	verif.v(not BancAcide.est_corrode(objet), "sous le seuil : l'objet ne doit pas porter 'corrode_acide'")

func _avancer_corrosion_reste_posee_apres_retrait_source() -> void:
	var objet := _objet_test("faible", 0.1)
	BancAcide.avancer_exposition([objet], true, 0.15, 1.0)
	BancAcide.avancer_corrosion([objet], _catalogue_seuils_test())
	verif.v(BancAcide.est_corrode(objet), "garde : doit etre corrode apres la source")
	BancAcide.avancer_corrosion([objet], _catalogue_seuils_test())
	verif.v(BancAcide.est_corrode(objet), "source retiree APRES corrosion : l'etat doit rester pose (exposition_acide_cumulee ne redescend jamais)")

# ---- fabriquer_objets ----

func _fabriquer_objets_initialise_les_deux_champs() -> void:
	var materiaux := {"bois": {"densite": 0.6, "resistance_acide": 0.5}}
	var declarations := [{"id": "morceau_x", "position": [0.0, 0.0, 0.0], "composition": [{"materiau": "bois", "volume": 1.0}]}]
	var objets := BancAcide.fabriquer_objets(declarations, materiaux, ["resistance_acide"])
	verif.v(objets.size() == 1, "une declaration doit produire un objet, recu %d" % objets.size())
	var objet: Dictionary = objets[0]
	verif.v(is_equal_approx(objet.proprietes.get("resistance_acide", -1.0), 0.5), "resistance_acide doit etre fusionnee depuis le materiau, recu %f" % objet.proprietes.get("resistance_acide", -1.0))
	verif.v(objet.proprietes.etats_actifs.is_empty(), "etats_actifs doit demarrer vide")
	verif.v(is_equal_approx(objet.proprietes.exposition_acide_cumulee, 0.0), "exposition_acide_cumulee doit demarrer a 0.0")

# ---- diagnostiquer / textes ----

func _diagnostiquer_rend_les_trois_champs_attendus() -> void:
	var objet := _objet_test("x", 0.5)
	objet.proprietes.exposition_acide_cumulee = 0.125
	var diag := BancAcide.diagnostiquer(objet)
	verif.v(is_equal_approx(diag.resistance_acide, 0.5), "resistance_acide doit refleter proprietes.resistance_acide")
	verif.v(is_equal_approx(diag.exposition_acide_cumulee, 0.125), "exposition_acide_cumulee doit refleter proprietes.exposition_acide_cumulee")
	verif.v(not diag.corrode, "sans 'corrode_acide' dans etats_actifs, diag.corrode doit etre faux")

func _texte_objet_porte_id_et_les_valeurs() -> void:
	var texte := BancAcide.texte_objet("fer_acide", {"resistance_acide": 0.1, "exposition_acide_cumulee": 0.15, "corrode": true})
	verif.v(texte.find("fer_acide") != -1, "le texte doit porter l'id de l'objet")
	verif.v(texte.find("0.10") != -1, "le texte doit porter la resistance_acide")
	verif.v(texte.find("0.150") != -1, "le texte doit porter l'exposition cumulee")
	verif.v(texte.find("corrode_acide") != -1, "le texte doit porter l'etat corrode_acide")

func _ligne_source_porte_le_temps_et_letat() -> void:
	var ligne := BancAcide.ligne_source(3.0, true)
	verif.v(ligne.find("t=3.0") != -1, "la ligne doit porter le temps")
	verif.v(ligne.find("POSEE") != -1, "la ligne doit dire POSEE quand actif=true")
	var ligne2 := BancAcide.ligne_source(4.0, false)
	verif.v(ligne2.find("RETIREE") != -1, "la ligne doit dire RETIREE quand actif=false")

func _ligne_corrosion_porte_lid_et_lexposition() -> void:
	var ligne := BancAcide.ligne_corrosion(5.0, "fer_acide", {"exposition_acide_cumulee": 0.15, "resistance_acide": 0.1})
	verif.v(ligne.find("fer_acide") != -1, "la ligne doit porter l'id de l'objet")
	verif.v(ligne.find("CORRODE") != -1, "la ligne doit dire CORRODE")
	verif.v(ligne.find("0.150") != -1, "la ligne doit porter l'exposition cumulee")

# ---- Chemin reel ----

func _catalogue_seuils_etat_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json"))

func _materiaux_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))

func _proprietes_immuables_reelles() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])

func _donnees_banc_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_acide.json"))

func _objets_reels() -> Array:
	var donnees := _donnees_banc_reelles()
	return BancAcide.fabriquer_objets(donnees.get("objets", []), _materiaux_reels(), _proprietes_immuables_reelles())

func _par_id(objets: Array) -> Dictionary:
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	return par_id

func _chemin_reel_fabrication_porte_la_resistance_acide_fusionnee() -> void:
	var par_id := _par_id(_objets_reels())
	verif.v(par_id.size() == 3, "data/banc_acide.json doit declarer exactement trois objets, recu %d" % par_id.size())
	verif.v(is_equal_approx(par_id.bois_acide.proprietes.get("resistance_acide", -1.0), 0.5), "chemin reel : bois_acide doit porter resistance_acide FUSIONNEE 0.5 (data/materiaux.json:bois), recu %f" % par_id.bois_acide.proprietes.get("resistance_acide", -1.0))
	verif.v(is_equal_approx(par_id.pierre_acide.proprietes.get("resistance_acide", -1.0), 0.3), "chemin reel : pierre_acide doit porter resistance_acide FUSIONNEE 0.3 (data/materiaux.json:pierre), recu %f" % par_id.pierre_acide.proprietes.get("resistance_acide", -1.0))
	verif.v(is_equal_approx(par_id.fer_acide.proprietes.get("resistance_acide", -1.0), 0.1), "chemin reel : fer_acide doit porter resistance_acide FUSIONNEE 0.1 (data/materiaux.json:fer), recu %f" % par_id.fer_acide.proprietes.get("resistance_acide", -1.0))

func _chemin_reel_sans_source_rien_ne_corrode() -> void:
	var etats_seuil := _catalogue_seuils_etat_reel()
	var par_id := _par_id(_objets_reels())
	for i in range(200):
		BancAcide.avancer_exposition(par_id.values(), false, 0.05, 0.1)
		BancAcide.avancer_corrosion(par_id.values(), etats_seuil)
	for id in ["bois_acide", "pierre_acide", "fer_acide"]:
		verif.v(not BancAcide.est_corrode(par_id[id]), "chemin reel, source jamais posee : '%s' ne doit jamais corroder" % id)
		verif.v(is_equal_approx(par_id[id].proprietes.exposition_acide_cumulee, 0.0), "chemin reel, source jamais posee : '%s' doit avoir une exposition cumulee EXACTEMENT nulle, recu %f" % [id, par_id[id].proprietes.exposition_acide_cumulee])

func _chemin_reel_fer_corrode_avant_pierre_avant_bois() -> void:
	var donnees := _donnees_banc_reelles()
	var etats_seuil := _catalogue_seuils_etat_reel()
	var par_id := _par_id(_objets_reels())
	var exposition_valeur: float = donnees.get("exposition_valeur", 0.0)
	var delta := 0.1
	var temps_corrosion: Dictionary = {}
	for i in range(200):
		BancAcide.avancer_exposition(par_id.values(), true, exposition_valeur, delta)
		var bascules := BancAcide.avancer_corrosion(par_id.values(), etats_seuil)
		for id in bascules:
			if not temps_corrosion.has(id) and BancAcide.est_corrode(par_id[id]):
				temps_corrosion[id] = (i + 1) * delta
	verif.v(temps_corrosion.has("fer_acide"), "chemin reel, exposition de demonstration : le fer doit corroder")
	verif.v(temps_corrosion.has("pierre_acide"), "chemin reel, exposition de demonstration : la pierre doit corroder")
	verif.v(temps_corrosion.has("bois_acide"), "chemin reel, exposition de demonstration : le bois doit corroder")
	if temps_corrosion.has("fer_acide") and temps_corrosion.has("pierre_acide") and temps_corrosion.has("bois_acide"):
		verif.v(temps_corrosion.fer_acide < temps_corrosion.pierre_acide, "le fer doit corroder AVANT la pierre -- fer=%f pierre=%f" % [temps_corrosion.fer_acide, temps_corrosion.pierre_acide])
		verif.v(temps_corrosion.pierre_acide < temps_corrosion.bois_acide, "la pierre doit corroder AVANT le bois -- pierre=%f bois=%f" % [temps_corrosion.pierre_acide, temps_corrosion.bois_acide])
