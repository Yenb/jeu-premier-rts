extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_simulation_acceleree.gd
#
# Verrouille le CABLAGE de scripts/banc_simulation_acceleree.gd (construction
# du terrain vieillissant, boucle acceleree a delta petit + facteur d'echelle,
# bascule entre les deux modes, comptage/affichage) -- jamais les mecanismes
# du coeur eux-memes, deja verrouilles ailleurs (test_senescence.gd,
# test_stade.gd, test_ecoulement.gd, test_depense.gd).
#
# PREUVE CENTRALE DU CHANTIER : le temps s'accelere par le FACTEUR D'ECHELLE
# (annees_par_seconde) et la REPETITION d'un delta PETIT, jamais par un grand
# delta -- et temperature.gd, le seul mecanisme qui diverge numeriquement a
# grand delta, n'est pas appelable ici PAR CONSTRUCTION (aucune case ne porte
# "temperature").

const Somme = preload("res://scripts/somme.gd")
const Banc = preload("res://scripts/banc_simulation_acceleree.gd")
const Verif = preload("res://scripts/verif.gd")

const CHEMIN_CONFIG := "res://data/banc_simulation_acceleree.json"

# Config de test : grille 4x4 (au lieu de 8x8) et annees_par_seconde eleve,
# pour que la succession complete tienne en quelques dizaines de blocs. Tout
# le reste est identique a data/banc_simulation_acceleree.json -- la
# calibration REELLE du fichier livre est verifiee separement, voir
# _la_calibration_livree_simule_des_milliers_d_annees_par_seconde.
func _config() -> Dictionary:
	return {
		"grille_lignes": 4,
		"grille_colonnes": 4,
		"altitude_max": 20.0,
		"altitude_min": 2.0,
		"rayon_voisinage": 1.5,
		"taux_ecoulement": 5.0,
		"eau_initiale": 10.0,
		"nom_reserve": "niveau_eau",
		"nom_altitude": "altitude",
		"taux_decroissance_plancher": 0.002,
		"facteur_permeabilite": 0.03,
		"evaporation_par_s": 0.001,
		"materiau_gauche": "terre",
		"materiau_droite": "roche",
		"iterations_par_tick": 100,
		"delta_fixe": 0.016,
		"annees_par_seconde": 100.0,
		"annees_par_seconde_temps_reel": 0.1,
		"intervalle_trace_annees": 1000.0,
		"stades_config": [
			{"nom": "nu", "age_seuil": 0.0},
			{"nom": "prairie", "age_seuil": 100.0},
			{"nom": "taillis", "age_seuil": 800.0},
			{"nom": "foret", "age_seuil": 3000.0},
		],
		"couleurs_stade": {
			"nu": [0.42, 0.30, 0.16],
			"prairie": [0.58, 0.85, 0.36],
			"taillis": [0.25, 0.62, 0.26],
			"foret": [0.07, 0.31, 0.12],
		},
		"couleur_stade_inconnu": [0.5, 0.5, 0.52],
		"couleur_eau": [0.05, 0.15, 0.55],
	}

func _materiaux() -> Dictionary:
	return {
		"terre": {"permeabilite": 0.8},
		"roche": {"permeabilite": 0.05},
	}

func _init() -> void:
	var v := Verif.new()
	_la_grille_porte_les_proprietes_structurelles_de_senescence_et_de_stade(v)
	_le_pas_neutre_pose_le_premier_stade_sans_rien_faire_avancer_d_autre(v)
	_le_mode_accelere_vieillit_de_n_fois_aps_fois_delta_par_tick(v)
	_le_meme_age_s_obtient_par_repetition_d_un_delta_petit_jamais_par_un_grand_delta(v)
	_la_succession_traverse_les_stades_dans_l_ordre_jusqu_a_foret(v)
	_l_eau_descend_la_pente_et_ne_remonte_jamais(v)
	_l_eau_se_stabilise_en_bas_de_pente(v)
	_aucune_divergence_numerique_ni_valeur_hors_bornes(v)
	_aucune_case_ne_porte_de_temperature(v)
	_le_passage_temps_reel_accelere_temps_reel_ne_casse_rien(v)
	_la_calibration_livree_simule_des_milliers_d_annees_par_seconde(v)
	_compter_stades_totalise_toutes_les_cases(v)
	_la_couleur_vient_du_stade_puis_se_sature_avec_l_eau(v)
	_case_la_plus_proche_trouve_la_bonne_case(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_simulation_acceleree.gd vieillit son terrain de milliers d'annees " +
			"par repetition d'un delta petit et d'un facteur d'echelle (jamais un grand delta), " +
			"traverse la succession dans l'ordre jusqu'a foret, fait descendre l'eau la pente " +
			"jusqu'a stabilisation, n'appelle jamais temperature.gd, et supporte les bascules " +
			"temps reel / accelere / temps reel sans rien casser")
		quit(0)

# ---- construction ----

func _la_grille_porte_les_proprietes_structurelles_de_senescence_et_de_stade(v) -> void:
	var cases := Banc.construire_grille(_config(), _materiaux())
	v.v(cases.size() == 16, "une grille 4x4 doit contenir exactement 16 cases, recu %d" % cases.size())
	for case in cases:
		var p: Dictionary = case.proprietes
		v.v(p.has("age") and typeof(p.age) == TYPE_FLOAT,
			"%s doit porter 'age' (structurelle pour senescence.gd/stade.gd), en float" % case.id)
		v.v(p.has("stades_config") and p.stades_config.size() == 4,
			"%s doit porter 'stades_config' (structurelle pour stade.gd), 4 entrees" % case.id)
		v.v(p.get("stade", "?") == "",
			"%s doit partir sans stade : c'est stade.gd qui pose le premier, jamais ce banc" % case.id)
		v.v(is_equal_approx(case.position.z, 0.0),
			"%s doit garder position.z=0.0 (fait spatial pur, l'altitude vit en propriete)" % case.id)
	# La table de stades ne doit JAMAIS etre partagee entre deux cases : muter
	# celle d'une case ne doit pas toucher celle d'une autre (duplicate(true)).
	cases[0].proprietes.stades_config[0]["nom"] = "mute"
	v.v(cases[1].proprietes.stades_config[0].nom == "nu",
		"stades_config doit etre copiee par valeur sur chaque case, jamais partagee par reference")

func _le_pas_neutre_pose_le_premier_stade_sans_rien_faire_avancer_d_autre(v) -> void:
	var config := _config()
	var cases := Banc.construire_grille(config, _materiaux())
	var eau_avant := Somme.reserves(cases, "niveau_eau")
	Banc.avancer_bloc(cases, config, 0.0, 0.0, 1)
	v.v(cases[0].proprietes.stade == "nu",
		"un pas de delta 0.0 doit laisser stade.gd poser le premier stade autorise par l'age 0.0, recu '%s'" % cases[0].proprietes.stade)
	v.v(is_equal_approx(Banc.annees_simulees(cases), 0.0),
		"un pas de delta 0.0 ne doit faire avancer aucun age")
	v.v(is_equal_approx(Somme.reserves(cases, "niveau_eau"), eau_avant),
		"un pas de delta 0.0 ne doit ni deplacer ni consommer d'eau")

# ---- acceleration ----

func _le_mode_accelere_vieillit_de_n_fois_aps_fois_delta_par_tick(v) -> void:
	var config := _config()
	var cases := Banc.construire_grille(config, _materiaux())
	var iterations := int(config.iterations_par_tick)
	var delta := float(config.delta_fixe)
	var aps := float(config.annees_par_seconde)
	var attendu := float(iterations) * delta * aps

	var bilan := Banc.avancer_bloc(cases, config, delta, aps, iterations)
	v.v(abs(Banc.annees_simulees(cases) - attendu) < 1e-3,
		"un tick accelere doit vieillir de iterations*delta*annees_par_seconde (%.4f attendu, %.4f recu)" % [attendu, Banc.annees_simulees(cases)])
	v.v(abs(float(bilan.annees) - attendu) < 1e-6,
		"avancer_bloc doit rendre exactement l'avance d'age du bloc (%.4f attendu, %.4f recu)" % [attendu, float(bilan.annees)])

	Banc.avancer_bloc(cases, config, delta, aps, iterations)
	v.v(abs(Banc.annees_simulees(cases) - 2.0 * attendu) < 1e-3,
		"deux ticks acceleres doivent vieillir exactement du double d'un seul (%.4f attendu, %.4f recu)" % [2.0 * attendu, Banc.annees_simulees(cases)])

	# Le facteur d'echelle est le SEUL levier de vitesse : le doubler double
	# l'age simule, a delta et iterations identiques.
	var cases_rapides := Banc.construire_grille(config, _materiaux())
	Banc.avancer_bloc(cases_rapides, config, delta, aps * 2.0, iterations)
	v.v(abs(Banc.annees_simulees(cases_rapides) - 2.0 * attendu) < 1e-3,
		"doubler annees_par_seconde doit doubler l'age simule, a delta et iterations identiques")

func _le_meme_age_s_obtient_par_repetition_d_un_delta_petit_jamais_par_un_grand_delta(v) -> void:
	var config := _config()
	var iterations := int(config.iterations_par_tick)
	var delta := float(config.delta_fixe)
	var aps := float(config.annees_par_seconde)

	var petits := Banc.construire_grille(config, _materiaux())
	Banc.avancer_bloc(petits, config, delta, aps, iterations)

	# LE MEME age simule, obtenu en UN SEUL pas de delta geant -- la voie que
	# ce banc REFUSE. L'age coincide (senescence.gd est lineaire), le MONDE
	# non : a grand delta, ecoulement.gd vide une case entiere vers son
	# premier voisin plus bas dans l'ordre d'iteration (defaut assume dans son
	# propre en-tete). C'est exactement ce que ce test rend visible.
	var geant := Banc.construire_grille(config, _materiaux())
	Banc.avancer_bloc(geant, config, delta * float(iterations), aps, 1)

	v.v(abs(Banc.annees_simulees(petits) - Banc.annees_simulees(geant)) < 1e-3,
		"les deux voies doivent donner le MEME age simule (c'est ce qui rend la comparaison honnete)")
	v.v(not is_equal_approx(Banc.somme_colonne(petits, 3, "niveau_eau"), Banc.somme_colonne(geant, 3, "niveau_eau")),
		"a age simule egal, un pas geant doit donner un ETAT D'EAU different de N pas petits -- si les deux coincidaient, ce banc n'aurait aucune raison d'exister")

func _la_succession_traverse_les_stades_dans_l_ordre_jusqu_a_foret(v) -> void:
	var config := _config()
	var cases := Banc.construire_grille(config, _materiaux())
	var iterations := int(config.iterations_par_tick)
	var delta := float(config.delta_fixe)
	var aps := float(config.annees_par_seconde)

	# Pas neutre d'abord (celui que _ready fait), pour partir de l'etat que le
	# joueur voit reellement avant le premier tick : sans lui, le premier bloc
	# accelere traverse "nu" ENTIEREMENT entre deux observations et le stade de
	# depart n'est jamais vu -- un artefact d'echantillonnage du test, pas un
	# saut de stade.gd.
	Banc.avancer_bloc(cases, config, 0.0, 0.0, 1)
	var vus: Array = [cases[0].proprietes.stade]
	var dernier: String = cases[0].proprietes.stade
	for _tick in range(40):
		Banc.avancer_bloc(cases, config, delta, aps, iterations)
		var stade: String = cases[0].proprietes.stade
		if stade != dernier:
			vus.append(stade)
			dernier = stade
		if stade == "foret":
			break

	v.v(vus == ["nu", "prairie", "taillis", "foret"],
		"la succession doit traverser nu -> prairie -> taillis -> foret, dans cet ordre et sans saut, recu %s" % str(vus))
	for case in cases:
		v.v(case.proprietes.stade == "foret",
			"toutes les cases doivent avoir atteint 'foret' apres assez d'iterations, %s est a '%s'" % [case.id, case.proprietes.stade])
	v.v(Banc.annees_simulees(cases) >= 3000.0,
		"atteindre 'foret' suppose au moins 3000 annees simulees, recu %.0f" % Banc.annees_simulees(cases))

# ---- eau ----

func _l_eau_descend_la_pente_et_ne_remonte_jamais(v) -> void:
	var config := _config()
	var cases := Banc.construire_grille(config, _materiaux())
	v.v(is_equal_approx(Banc.somme_colonne(cases, 0, "niveau_eau"), 40.0),
		"au depart, toute l'eau doit etre au sommet (colonne 0), 4 cases a 10.0")
	v.v(is_equal_approx(Banc.somme_colonne(cases, 3, "niveau_eau"), 0.0),
		"au depart, le bas de pente (colonne 3) doit etre sec")

	for _tick in range(20):
		Banc.avancer_bloc(cases, config, float(config.delta_fixe), float(config.annees_par_seconde), int(config.iterations_par_tick))

	var haut := Banc.somme_colonne(cases, 0, "niveau_eau")
	var bas := Banc.somme_colonne(cases, 3, "niveau_eau")
	v.v(bas > haut,
		"apres ecoulement, le bas de pente doit porter strictement plus d'eau que le sommet (%.2f en bas, %.2f en haut)" % [bas, haut])
	v.v(haut < 1.0,
		"le sommet doit s'etre vide (l'eau ne remonte jamais), recu %.2f" % haut)

func _l_eau_se_stabilise_en_bas_de_pente(v) -> void:
	var config := _config()
	var cases := Banc.construire_grille(config, _materiaux())
	var delta := float(config.delta_fixe)
	var aps := float(config.annees_par_seconde)
	var iterations := int(config.iterations_par_tick)

	var premier := Banc.avancer_bloc(cases, config, delta, aps, iterations)
	for _tick in range(30):
		Banc.avancer_bloc(cases, config, delta, aps, iterations)
	var tardif := Banc.avancer_bloc(cases, config, delta, aps, iterations)

	v.v(float(premier.quantite) > 0.0,
		"le premier tick doit deplacer de l'eau (la pente est chargee au sommet)")
	v.v(float(tardif.quantite) < float(premier.quantite) * 0.1,
		"une fois l'eau arrivee en bas, la quantite deplacee par tick doit s'effondrer (stabilisation) : %.4f tardif contre %.4f au premier tick" % [float(tardif.quantite), float(premier.quantite)])

	# Stabilisee EN BAS, pas repartie au hasard : la colonne la plus basse
	# porte strictement plus que chacune des autres.
	var bas := Banc.somme_colonne(cases, 3, "niveau_eau")
	for colonne in range(3):
		v.v(bas > Banc.somme_colonne(cases, colonne, "niveau_eau"),
			"la colonne la plus basse doit porter strictement plus d'eau que la colonne %d" % colonne)

# ---- stabilite numerique ----

func _aucune_divergence_numerique_ni_valeur_hors_bornes(v) -> void:
	var config := _config()
	var cases := Banc.construire_grille(config, _materiaux())
	var total_initial := Somme.reserves(cases, "niveau_eau")
	var precedent := total_initial
	var age_precedent := 0.0

	for _tick in range(30):
		Banc.avancer_bloc(cases, config, float(config.delta_fixe), float(config.annees_par_seconde), int(config.iterations_par_tick))
		var total := Somme.reserves(cases, "niveau_eau")
		var age := Banc.annees_simulees(cases)
		v.v(is_finite(total), "l'eau totale doit rester finie (aucune divergence numerique), recu %s" % str(total))
		v.v(is_finite(age), "l'age simule doit rester fini, recu %s" % str(age))
		v.v(total <= precedent + 1e-6,
			"l'eau totale ne doit JAMAIS remonter : l'ecoulement deplace, depense.gd retire, rien n'ajoute (%.6f apres %.6f)" % [total, precedent])
		v.v(total >= -1e-9, "l'eau totale ne doit jamais devenir negative, recu %.6f" % total)
		v.v(age > age_precedent, "l'age doit croitre strictement a chaque tick accelere")
		precedent = total
		age_precedent = age

	for case in cases:
		var niveau: float = case.proprietes.reserves.niveau_eau.reserve
		v.v(is_finite(niveau) and niveau >= 0.0 and niveau <= total_initial,
			"%s doit garder une reserve finie dans [0, %.2f], recu %s" % [case.id, total_initial, str(niveau)])
		v.v(is_finite(float(case.proprietes.altitude)),
			"%s doit garder une altitude finie (aucun mecanisme de ce banc ne l'ecrit)" % case.id)

func _aucune_case_ne_porte_de_temperature(v) -> void:
	var config := _config()
	var cases := Banc.construire_grille(config, _materiaux())
	Banc.avancer_bloc(cases, config, float(config.delta_fixe), float(config.annees_par_seconde), int(config.iterations_par_tick))
	for case in cases:
		v.v(not case.proprietes.has("temperature"),
			"%s ne doit JAMAIS porter 'temperature' : temperature.gd est le seul mecanisme qui diverge a grand delta, ce banc ne l'appelle pas et aucune case n'est appelable par lui" % case.id)

func _le_passage_temps_reel_accelere_temps_reel_ne_casse_rien(v) -> void:
	var config := _config()
	var cases := Banc.construire_grille(config, _materiaux())
	var delta_reel := 0.016
	var aps_lent := float(config.annees_par_seconde_temps_reel)
	var aps_rapide := float(config.annees_par_seconde)
	var iterations := int(config.iterations_par_tick)

	# Phase 1 -- temps reel : un seul appel par tick, delta du moteur.
	for _tick in range(10):
		Banc.avancer_bloc(cases, config, delta_reel, aps_lent, 1)
	var age_apres_phase1 := Banc.annees_simulees(cases)
	var eau_apres_phase1 := Somme.reserves(cases, "niveau_eau")
	var stade_apres_phase1: String = cases[0].proprietes.stade
	v.v(age_apres_phase1 > 0.0, "le temps reel doit tout de meme faire avancer l'age, recu %.6f" % age_apres_phase1)
	v.v(stade_apres_phase1 == "nu", "en temps reel lent, la succession ne doit pas avoir depasse le premier stade, recu '%s'" % stade_apres_phase1)

	# Phase 2 -- accelere.
	for _tick in range(25):
		Banc.avancer_bloc(cases, config, float(config.delta_fixe), aps_rapide, iterations)
	var age_apres_phase2 := Banc.annees_simulees(cases)
	var eau_apres_phase2 := Somme.reserves(cases, "niveau_eau")
	v.v(age_apres_phase2 > age_apres_phase1, "l'acceleration doit reprendre l'age la ou le temps reel l'avait laisse, en montant")
	v.v(cases[0].proprietes.stade == "foret", "apres la phase acceleree, la succession doit etre a 'foret', recu '%s'" % cases[0].proprietes.stade)
	v.v(eau_apres_phase2 <= eau_apres_phase1 + 1e-6, "l'eau totale ne doit pas remonter en passant d'un mode a l'autre")

	# Phase 3 -- retour au temps reel : le monde garde toute son histoire.
	for _tick in range(10):
		Banc.avancer_bloc(cases, config, delta_reel, aps_lent, 1)
	var age_final := Banc.annees_simulees(cases)
	v.v(age_final > age_apres_phase2, "le retour au temps reel doit continuer a faire avancer l'age, jamais le remettre a zero")
	v.v(cases[0].proprietes.stade == "foret", "le retour au temps reel ne doit JAMAIS faire reculer un stade, recu '%s'" % cases[0].proprietes.stade)
	v.v(Somme.reserves(cases, "niveau_eau") <= eau_apres_phase2 + 1e-6,
		"le retour au temps reel ne doit pas recreer d'eau")
	for case in cases:
		v.v(is_finite(float(case.proprietes.age)) and is_finite(float(case.proprietes.reserves.niveau_eau.reserve)),
			"%s doit rester numeriquement sain apres trois bascules de mode" % case.id)

# Verifie la calibration REELLEMENT LIVREE dans data/banc_simulation_
# acceleree.json -- en ANNEES PAR TICK, jamais en annees par seconde reelle :
# le nombre de ticks par seconde depend de la machine et du cout d'
# Ecoulement.avancer (O(cases^2) par iteration), il n'est pas verifiable
# depuis un test. Le debit reel MESURE en headless sur la machine de
# developpement (~1740 annees/s, foret atteinte vers 2 s) est reporte dans
# docs/prototypes.md comme une MESURE, jamais comme une garantie.
func _la_calibration_livree_simule_des_milliers_d_annees_par_seconde(v) -> void:
	var texte := FileAccess.get_file_as_string(CHEMIN_CONFIG)
	var config: Dictionary = JSON.parse_string(texte)
	v.v(config != null and not config.is_empty(), "%s doit exister et etre lisible" % CHEMIN_CONFIG)
	var par_tick: float = float(config.iterations_par_tick) * float(config.delta_fixe) * float(config.annees_par_seconde)
	v.v(float(config.delta_fixe) <= 0.02,
		"delta_fixe doit rester PETIT (<= 0.02 s) : c'est toute la doctrine de ce banc, recu %.4f" % float(config.delta_fixe))
	v.v(int(config.iterations_par_tick) > 1,
		"le mode accelere doit reellement boucler plusieurs fois par tick, recu %d" % int(config.iterations_par_tick))
	v.v(par_tick >= 100.0,
		"un seul tick accelere doit avancer d'au moins un siecle, recu %.1f annees" % par_tick)
	v.v(float(config.annees_par_seconde) > float(config.annees_par_seconde_temps_reel),
		"le facteur d'echelle accelere doit etre strictement superieur a celui du temps reel")
	var derniere: Dictionary = config.stades_config[config.stades_config.size() - 1]
	v.v(float(derniere.age_seuil) / par_tick <= 50.0,
		"le dernier stade doit etre atteignable en quelques dizaines de ticks, recu %.0f ticks" % (float(derniere.age_seuil) / par_tick))

# ---- affichage ----

func _compter_stades_totalise_toutes_les_cases(v) -> void:
	var config := _config()
	var cases := Banc.construire_grille(config, _materiaux())
	Banc.avancer_bloc(cases, config, 0.0, 0.0, 1)
	var comptes := Banc.compter_stades(cases, config)
	v.v(int(comptes.get("nu", 0)) == 16, "les 16 cases doivent etre comptees au stade 'nu' au depart, recu %d" % int(comptes.get("nu", 0)))
	var total := 0
	for nom in comptes:
		total += int(comptes[nom])
	v.v(total == cases.size(), "le comptage par stade doit totaliser exactement le nombre de cases (%d attendu, %d recu)" % [cases.size(), total])

func _la_couleur_vient_du_stade_puis_se_sature_avec_l_eau(v) -> void:
	var config := _config()
	var sec_nu := Banc.couleur_pour_case("nu", 0.0, 10.0, config)
	var sec_foret := Banc.couleur_pour_case("foret", 0.0, 10.0, config)
	v.v(not sec_nu.is_equal_approx(sec_foret),
		"deux stades differents doivent rendre deux couleurs seches distinctes")
	var mouille := Banc.couleur_pour_case("nu", 10.0, 10.0, config)
	v.v(not sec_nu.is_equal_approx(mouille),
		"une case gorgee d'eau ne doit pas rendre la meme couleur qu'une case seche du meme stade")
	var au_dela := Banc.couleur_pour_case("nu", 50.0, 10.0, config)
	v.v(mouille.is_equal_approx(au_dela),
		"au-dela de la reference, la couleur doit rester bornee (jamais divergente)")
	var inconnu := Banc.couleur_pour_case("stade_absent_du_catalogue", 0.0, 10.0, config)
	v.v(inconnu.is_equal_approx(Banc.couleur_pour_case("", 0.0, 10.0, config)),
		"un stade absent de couleurs_stade doit retomber sur couleur_stade_inconnu, jamais planter")

func _case_la_plus_proche_trouve_la_bonne_case(v) -> void:
	var cases := Banc.construire_grille(_config(), _materiaux())
	var taille := 60.0
	var trouvee: Variant = Banc.case_la_plus_proche(cases, Vector2(3.0, 0.0) * taille, taille)
	v.v(trouvee != null and trouvee.id == "case_3_0",
		"un point exactement sur la case_3_0 (en pixels) doit retrouver cette case, recu %s" % (trouvee.id if trouvee != null else "null"))
	v.v(Banc.case_la_plus_proche([], Vector2.ZERO, taille) == null,
		"une grille vide doit rendre null, jamais planter")
