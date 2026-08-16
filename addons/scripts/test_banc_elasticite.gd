extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_elasticite.gd
#
# Verrouille le cablage de banc_elasticite.gd, PREMIERE DEMONSTRATION REELLE
# de "elasticite" fusionnee a la fabrication (chantier « elasticite --
# deformation reversible ») : deformation_sous_force/deformation_permanente/
# avancer/basculer_force/fabriquer_objets/diagnostiquer/doit_imprimer_recap
# (fonctions statiques, pures) plus un CHEMIN REEL combinant Objet.fabriquer
# avec data/banc_elasticite.json/data/materiaux.json/data/etats.json/
# data/proprietes_immuables_composition.json lus sur disque -- sous force les
# trois doivent reellement se deformer, et force retiree, le bois doit
# reellement recuperer une plus grande FRACTION de sa deformation que la
# pierre.

const BancElasticite = preload("res://scripts/banc_elasticite.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_deformation_sous_force_nulle_rend_zero()
	_deformation_sous_force_guard_rigidite_non_positive_rend_inf()
	_deformation_sous_force_proportionnelle()

	_deformation_permanente_elasticite_un_rend_zero_exact()
	_deformation_permanente_elasticite_zero_ne_revient_jamais()
	_deformation_permanente_intermediaire()

	_avancer_sous_force_les_trois_se_deforment()
	_avancer_force_retiree_isole_elasticite_bois_revient_plus_pierre_moins()
	_avancer_elasticite_un_revient_entierement_apres_retrait()
	_avancer_elasticite_zero_ne_revient_jamais_apres_retrait()
	_avancer_sans_force_aucune_deformation()
	_avancer_deformation_maximale_ne_redescend_jamais_sous_force()

	_basculer_force_inverse()

	_diagnostiquer_rend_les_quatre_champs_attendus()
	_texte_objet_porte_id_et_les_valeurs_et_letat_de_force()
	_ligne_force_porte_le_temps_et_letat()
	_ligne_recap_porte_le_temps_et_chaque_id()
	_doit_imprimer_recap_sous_lintervalle_faux_au_dela_vrai()

	_chemin_reel_fabrication_porte_elasticite_fusionnee()
	_chemin_reel_sous_force_les_trois_se_deforment()
	_chemin_reel_force_retiree_bois_recupere_plus_que_pierre_et_fer()
	_chemin_reel_pierre_reste_quasi_deformee()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: deformation_sous_force/deformation_permanente bornees et " +
		"proportionnelles, avancer mute deformation_actuelle/maximale_" +
		"atteinte/permanente selon la force, bascule de force sur tous les " +
		"objets a la fois, diagnostic/textes/recap corrects, chemin reel " +
		"(data/banc_elasticite.json/materiaux.json/etats.json/proprietes_" +
		"immuables_composition.json) ou elasticite est bien fusionnee a la " +
		"fabrication, les trois se deforment sous force, et le bois " +
		"recupere une plus grande fraction de sa deformation que la pierre " +
		"une fois la force retiree")
	quit(0)

# ---- deformation_sous_force ----

func _deformation_sous_force_nulle_rend_zero() -> void:
	var d := BancElasticite.deformation_sous_force(0.0, 100.0)
	verif.v(is_equal_approx(d, 0.0), "force nulle : aucune deformation, recu %f" % d)

func _deformation_sous_force_guard_rigidite_non_positive_rend_inf() -> void:
	var d := BancElasticite.deformation_sous_force(100.0, 0.0)
	verif.v(is_inf(d), "rigidite nulle (donnee incoherente) : garde defensive, doit rendre INF, recu %f" % d)
	var d2 := BancElasticite.deformation_sous_force(100.0, -5.0)
	verif.v(is_inf(d2), "rigidite negative (donnee incoherente) : garde defensive, doit rendre INF, recu %f" % d2)

func _deformation_sous_force_proportionnelle() -> void:
	var d := BancElasticite.deformation_sous_force(1000.0, 100.0)
	verif.v(is_equal_approx(d, 10.0), "force 1000.0 / rigidite 100.0 = 10.0, recu %f" % d)

# ---- deformation_permanente ----

func _deformation_permanente_elasticite_un_rend_zero_exact() -> void:
	var p := BancElasticite.deformation_permanente(50.0, 1.0)
	verif.v(is_equal_approx(p, 0.0), "elasticite 1.0 : retour TOTAL, deformation permanente doit etre EXACTEMENT 0.0, recu %f" % p)

func _deformation_permanente_elasticite_zero_ne_revient_jamais() -> void:
	var p := BancElasticite.deformation_permanente(50.0, 0.0)
	verif.v(is_equal_approx(p, 50.0), "elasticite 0.0 : AUCUN retour, deformation permanente doit rester EXACTEMENT la maximale atteinte (50.0), recu %f" % p)

func _deformation_permanente_intermediaire() -> void:
	var p := BancElasticite.deformation_permanente(100.0, 0.3)
	verif.v(is_equal_approx(p, 70.0), "elasticite 0.3 sur maximale 100.0 : permanente = 100.0*(1.0-0.3) = 70.0, recu %f" % p)

# ---- avancer ----

func _objet_test(id: String, elasticite: float, rigidite: float) -> Dictionary:
	return {
		"id": id,
		"position": Vector3.ZERO,
		"proprietes": {
			"elasticite": elasticite,
			"rigidite": rigidite,
			"etats_actifs": [],
			"deformation_actuelle": 0.0,
			"deformation_maximale_atteinte": 0.0,
			"deformation_permanente": 0.0,
		},
	}

func _avancer_sous_force_les_trois_se_deforment() -> void:
	var bois := _objet_test("bois", 0.3, 11.0)
	var pierre := _objet_test("pierre", 0.05, 50.0)
	var fer := _objet_test("fer", 0.2, 200.0)
	BancElasticite.avancer([bois, pierre, fer], 1000.0, true, {})
	verif.v(bois.proprietes.deformation_actuelle > 0.0, "sous force, le bois doit se deformer, recu %f" % bois.proprietes.deformation_actuelle)
	verif.v(pierre.proprietes.deformation_actuelle > 0.0, "sous force, la pierre doit se deformer, recu %f" % pierre.proprietes.deformation_actuelle)
	verif.v(fer.proprietes.deformation_actuelle > 0.0, "sous force, le fer doit se deformer, recu %f" % fer.proprietes.deformation_actuelle)

# Rigidite IDENTIQUE pour les trois -- isole elasticite comme SEULE variable
# (meme deformation_maximale_atteinte pour les trois, voir motif recurrent
# CLAUDE.md : ne jamais tester une propriete cablee avec une valeur qui
# laisserait une autre grandeur decider du resultat a sa place).
func _avancer_force_retiree_isole_elasticite_bois_revient_plus_pierre_moins() -> void:
	var bois := _objet_test("bois", 0.3, 100.0)
	var pierre := _objet_test("pierre", 0.05, 100.0)
	var fer := _objet_test("fer", 0.2, 100.0)
	var objets := [bois, pierre, fer]
	BancElasticite.avancer(objets, 1000.0, true, {})
	var maximale: float = bois.proprietes.deformation_maximale_atteinte
	verif.v(is_equal_approx(pierre.proprietes.deformation_maximale_atteinte, maximale) and is_equal_approx(fer.proprietes.deformation_maximale_atteinte, maximale), "garde : a rigidite egale, les trois doivent atteindre EXACTEMENT la meme deformation maximale, recu bois=%f pierre=%f fer=%f" % [maximale, pierre.proprietes.deformation_maximale_atteinte, fer.proprietes.deformation_maximale_atteinte])

	BancElasticite.avancer(objets, 1000.0, false, {})
	var recup_bois: float = maximale - bois.proprietes.deformation_permanente
	var recup_pierre: float = maximale - pierre.proprietes.deformation_permanente
	var recup_fer: float = maximale - fer.proprietes.deformation_permanente
	verif.v(recup_bois > recup_fer, "a rigidite egale, le bois (elasticite 0.3) doit recuperer PLUS que le fer (0.2) -- bois=%f fer=%f" % [recup_bois, recup_fer])
	verif.v(recup_fer > recup_pierre, "a rigidite egale, le fer (elasticite 0.2) doit recuperer PLUS que la pierre (0.05) -- fer=%f pierre=%f" % [recup_fer, recup_pierre])
	verif.v(recup_bois > recup_pierre, "a rigidite egale, le bois doit recuperer PLUS que la pierre -- bois=%f pierre=%f" % [recup_bois, recup_pierre])

func _avancer_elasticite_un_revient_entierement_apres_retrait() -> void:
	var objet := _objet_test("total", 1.0, 100.0)
	BancElasticite.avancer([objet], 1000.0, true, {})
	verif.v(objet.proprietes.deformation_maximale_atteinte > 0.0, "garde : l'objet doit avoir reellement subi une deformation sous force avant le retrait")
	BancElasticite.avancer([objet], 1000.0, false, {})
	verif.v(is_equal_approx(objet.proprietes.deformation_permanente, 0.0), "elasticite 1.0 : apres retrait, deformation permanente doit etre EXACTEMENT 0.0, recu %f" % objet.proprietes.deformation_permanente)
	verif.v(is_equal_approx(objet.proprietes.deformation_actuelle, 0.0), "elasticite 1.0 : apres retrait, deformation actuelle doit etre EXACTEMENT 0.0 (retour total), recu %f" % objet.proprietes.deformation_actuelle)

func _avancer_elasticite_zero_ne_revient_jamais_apres_retrait() -> void:
	var objet := _objet_test("rigide", 0.0, 100.0)
	BancElasticite.avancer([objet], 1000.0, true, {})
	var maximale: float = objet.proprietes.deformation_maximale_atteinte
	verif.v(maximale > 0.0, "garde : l'objet doit avoir reellement subi une deformation sous force avant le retrait")
	BancElasticite.avancer([objet], 1000.0, false, {})
	verif.v(is_equal_approx(objet.proprietes.deformation_permanente, maximale), "elasticite 0.0 : apres retrait, deformation permanente doit rester EXACTEMENT la maximale atteinte (%f), recu %f" % [maximale, objet.proprietes.deformation_permanente])
	verif.v(is_equal_approx(objet.proprietes.deformation_actuelle, maximale), "elasticite 0.0 : apres retrait, deformation actuelle ne doit JAMAIS revenir, recu %f" % objet.proprietes.deformation_actuelle)

func _avancer_sans_force_aucune_deformation() -> void:
	var bois := _objet_test("bois", 0.3, 11.0)
	var pierre := _objet_test("pierre", 0.05, 50.0)
	var fer := _objet_test("fer", 0.2, 200.0)
	var objets := [bois, pierre, fer]
	for i in 10:
		BancElasticite.avancer(objets, 1000.0, false, {})
	for objet in objets:
		verif.v(is_equal_approx(objet.proprietes.deformation_actuelle, 0.0), "%s : sans force jamais appliquee, deformation_actuelle doit rester EXACTEMENT 0.0, recu %f" % [objet.id, objet.proprietes.deformation_actuelle])
		verif.v(is_equal_approx(objet.proprietes.deformation_permanente, 0.0), "%s : sans force jamais appliquee, deformation_permanente doit rester EXACTEMENT 0.0, recu %f" % [objet.id, objet.proprietes.deformation_permanente])

func _avancer_deformation_maximale_ne_redescend_jamais_sous_force() -> void:
	var objet := _objet_test("variable", 0.3, 100.0)
	BancElasticite.avancer([objet], 2000.0, true, {})
	var haute: float = objet.proprietes.deformation_maximale_atteinte
	BancElasticite.avancer([objet], 500.0, true, {})
	verif.v(is_equal_approx(objet.proprietes.deformation_actuelle, 5.0), "une force plus faible doit reduire la deformation ACTUELLE (500.0/100.0=5.0), recu %f" % objet.proprietes.deformation_actuelle)
	verif.v(is_equal_approx(objet.proprietes.deformation_maximale_atteinte, haute), "la deformation MAXIMALE ATTEINTE ne doit JAMAIS redescendre meme si la force diminue, recu %f attendu %f" % [objet.proprietes.deformation_maximale_atteinte, haute])

# ---- basculer_force ----

func _basculer_force_inverse() -> void:
	verif.v(BancElasticite.basculer_force(false), "basculer_force(false) doit rendre true")
	verif.v(not BancElasticite.basculer_force(true), "basculer_force(true) doit rendre false")

# ---- diagnostiquer / textes ----

func _diagnostiquer_rend_les_quatre_champs_attendus() -> void:
	var objet := _objet_test("x", 0.3, 100.0)
	objet.proprietes["deformation_actuelle"] = 7.5
	objet.proprietes["deformation_permanente"] = 3.2
	var diag := BancElasticite.diagnostiquer(objet, {})
	verif.v(is_equal_approx(diag.elasticite, 0.3), "diag.elasticite doit refleter la propriete de base")
	verif.v(is_equal_approx(diag.rigidite_effective, 100.0), "diag.rigidite_effective doit refleter la base sans etat actif")
	verif.v(is_equal_approx(diag.deformation_actuelle, 7.5), "diag.deformation_actuelle doit refleter la valeur posee")
	verif.v(is_equal_approx(diag.deformation_permanente, 3.2), "diag.deformation_permanente doit refleter la valeur posee")

func _texte_objet_porte_id_et_les_valeurs_et_letat_de_force() -> void:
	var diag := {"elasticite": 0.3, "rigidite_effective": 11.0, "deformation_actuelle": 7.50, "deformation_permanente": 3.20}
	var texte_pose := BancElasticite.texte_objet("bois_elasticite", diag, true)
	verif.v(texte_pose.find("bois_elasticite") != -1, "le texte doit porter l'id de l'objet")
	verif.v(texte_pose.find("0.30") != -1, "le texte doit porter l'elasticite")
	verif.v(texte_pose.find("7.50") != -1, "le texte doit porter la deformation actuelle")
	verif.v(texte_pose.find("3.20") != -1, "le texte doit porter la deformation permanente")
	verif.v(texte_pose.find("posee") != -1, "force active : le texte doit dire 'posee'")
	var texte_retiree := BancElasticite.texte_objet("bois_elasticite", diag, false)
	verif.v(texte_retiree.find("retiree") != -1, "force inactive : le texte doit dire 'retiree'")

func _ligne_force_porte_le_temps_et_letat() -> void:
	var pose := BancElasticite.ligne_force(3.0, true)
	verif.v(pose.find("t=3.0") != -1 and pose.find("POSEE") != -1, "ligne_force(actif=true) doit porter le temps et POSEE")
	var retiree := BancElasticite.ligne_force(4.0, false)
	verif.v(retiree.find("t=4.0") != -1 and retiree.find("RETIREE") != -1, "ligne_force(actif=false) doit porter le temps et RETIREE")

func _ligne_recap_porte_le_temps_et_chaque_id() -> void:
	var a := _objet_test("bois_elasticite", 0.3, 11.0)
	a.proprietes["deformation_actuelle"] = 10.0
	var b := _objet_test("pierre_elasticite", 0.05, 50.0)
	b.proprietes["deformation_actuelle"] = 3.0
	var ligne := BancElasticite.ligne_recap(5.0, [a, b], {})
	verif.v(ligne.find("t=5.0") != -1, "la ligne recap doit porter le temps")
	verif.v(ligne.find("bois_elasticite=10.00") != -1, "la ligne recap doit porter la deformation du bois")
	verif.v(ligne.find("pierre_elasticite=3.00") != -1, "la ligne recap doit porter la deformation de la pierre")

func _doit_imprimer_recap_sous_lintervalle_faux_au_dela_vrai() -> void:
	verif.v(not BancElasticite.doit_imprimer_recap(1.5, 0.0, 2.0), "1.5s ecoulees, intervalle 2.0 : ne doit PAS imprimer")
	verif.v(BancElasticite.doit_imprimer_recap(2.0, 0.0, 2.0), "exactement l'intervalle ecoule : doit imprimer")
	verif.v(BancElasticite.doit_imprimer_recap(3.0, 0.0, 2.0), "au-dela de l'intervalle : doit imprimer")

# ---- Chemin reel ----

func _catalogue_etats_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))

func _materiaux_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))

func _proprietes_immuables_reelles() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])

func _donnees_banc_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_elasticite.json"))

func _objets_reels() -> Array:
	var donnees := _donnees_banc_reelles()
	return BancElasticite.fabriquer_objets(donnees.get("objets", []), _materiaux_reels(), _proprietes_immuables_reelles())

func _par_id(objets: Array) -> Dictionary:
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	return par_id

func _chemin_reel_fabrication_porte_elasticite_fusionnee() -> void:
	var objets := _objets_reels()
	verif.v(objets.size() == 3, "data/banc_elasticite.json doit declarer exactement trois objets, recu %d" % objets.size())
	var par_id := _par_id(objets)
	verif.v(is_equal_approx(par_id.bois_elasticite.proprietes.get("elasticite", -1.0), 0.3), "chemin reel : bois_elasticite doit porter elasticite FUSIONNEE 0.3 (data/materiaux.json:bois), recu %f" % par_id.bois_elasticite.proprietes.get("elasticite", -1.0))
	verif.v(is_equal_approx(par_id.pierre_elasticite.proprietes.get("elasticite", -1.0), 0.05), "chemin reel : pierre_elasticite doit porter elasticite FUSIONNEE 0.05 (data/materiaux.json:pierre), recu %f" % par_id.pierre_elasticite.proprietes.get("elasticite", -1.0))
	verif.v(is_equal_approx(par_id.fer_elasticite.proprietes.get("elasticite", -1.0), 0.2), "chemin reel : fer_elasticite doit porter elasticite FUSIONNEE 0.2 (data/materiaux.json:fer), recu %f" % par_id.fer_elasticite.proprietes.get("elasticite", -1.0))
	verif.v(is_equal_approx(par_id.bois_elasticite.proprietes.get("rigidite", -1.0), 11.0), "chemin reel : bois_elasticite doit porter rigidite FUSIONNEE 11.0 (data/materiaux.json:bois), recu %f" % par_id.bois_elasticite.proprietes.get("rigidite", -1.0))

func _chemin_reel_sous_force_les_trois_se_deforment() -> void:
	var objets := _objets_reels()
	var etats := _catalogue_etats_reel()
	var donnees := _donnees_banc_reelles()
	var force_valeur: float = donnees.get("force_valeur", 1000.0)
	BancElasticite.avancer(objets, force_valeur, true, etats)
	var par_id := _par_id(objets)
	verif.v(par_id.bois_elasticite.proprietes.deformation_actuelle > 0.0, "chemin reel, sous force : le bois doit se deformer")
	verif.v(par_id.pierre_elasticite.proprietes.deformation_actuelle > 0.0, "chemin reel, sous force : la pierre doit se deformer")
	verif.v(par_id.fer_elasticite.proprietes.deformation_actuelle > 0.0, "chemin reel, sous force : le fer doit se deformer")
	verif.v(par_id.bois_elasticite.proprietes.deformation_actuelle > par_id.pierre_elasticite.proprietes.deformation_actuelle, "chemin reel, sous force : le bois (rigidite 11.0) doit se deformer PLUS que la pierre (50.0)")
	verif.v(par_id.pierre_elasticite.proprietes.deformation_actuelle > par_id.fer_elasticite.proprietes.deformation_actuelle, "chemin reel, sous force : la pierre (rigidite 50.0) doit se deformer PLUS que le fer (200.0)")

func _chemin_reel_force_retiree_bois_recupere_plus_que_pierre_et_fer() -> void:
	var objets := _objets_reels()
	var etats := _catalogue_etats_reel()
	var donnees := _donnees_banc_reelles()
	var force_valeur: float = donnees.get("force_valeur", 1000.0)
	BancElasticite.avancer(objets, force_valeur, true, etats)
	var par_id := _par_id(objets)
	var max_bois: float = par_id.bois_elasticite.proprietes.deformation_maximale_atteinte
	var max_pierre: float = par_id.pierre_elasticite.proprietes.deformation_maximale_atteinte
	var max_fer: float = par_id.fer_elasticite.proprietes.deformation_maximale_atteinte

	BancElasticite.avancer(objets, force_valeur, false, etats)
	var recup_bois: float = max_bois - par_id.bois_elasticite.proprietes.deformation_permanente
	var recup_pierre: float = max_pierre - par_id.pierre_elasticite.proprietes.deformation_permanente
	var recup_fer: float = max_fer - par_id.fer_elasticite.proprietes.deformation_permanente
	verif.v(recup_bois > recup_pierre, "chemin reel, force retiree : le bois doit recuperer davantage (en absolu) que la pierre -- bois=%f pierre=%f" % [recup_bois, recup_pierre])
	verif.v(recup_bois > recup_fer, "chemin reel, force retiree : le bois doit recuperer davantage (en absolu) que le fer -- bois=%f fer=%f" % [recup_bois, recup_fer])

	# Fraction recuperee (recup/maximale) -- egale a elasticite par construction,
	# ordre non ambigu meme quand la rigidite differe (bois 0.3 > fer 0.2 >
	# pierre 0.05), contrairement a l'ecart ABSOLU qui depend aussi de la
	# rigidite (elasticite/rigidite de pierre et fer coincident sur les
	# valeurs reelles du depot -- voir _chemin_reel_pierre_reste_quasi_
	# deformee, jamais un ecart absolu pierre/fer teste ici).
	var fraction_bois: float = recup_bois / max_bois
	var fraction_pierre: float = recup_pierre / max_pierre
	var fraction_fer: float = recup_fer / max_fer
	verif.v(fraction_bois > fraction_fer, "chemin reel : le bois doit recuperer une plus GRANDE FRACTION de sa deformation que le fer -- bois=%f fer=%f" % [fraction_bois, fraction_fer])
	verif.v(fraction_fer > fraction_pierre, "chemin reel : le fer doit recuperer une plus GRANDE FRACTION de sa deformation que la pierre -- fer=%f pierre=%f" % [fraction_fer, fraction_pierre])

func _chemin_reel_pierre_reste_quasi_deformee() -> void:
	var objets := _objets_reels()
	var etats := _catalogue_etats_reel()
	var donnees := _donnees_banc_reelles()
	var force_valeur: float = donnees.get("force_valeur", 1000.0)
	BancElasticite.avancer(objets, force_valeur, true, etats)
	var par_id := _par_id(objets)
	var maximale: float = par_id.pierre_elasticite.proprietes.deformation_maximale_atteinte
	BancElasticite.avancer(objets, force_valeur, false, etats)
	var permanente: float = par_id.pierre_elasticite.proprietes.deformation_permanente
	verif.v(permanente / maximale > 0.9, "chemin reel : la pierre (elasticite 0.05) doit garder plus de 90%% de sa deformation, recu ratio=%f" % (permanente / maximale))
