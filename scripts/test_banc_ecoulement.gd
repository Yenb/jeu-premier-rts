extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_ecoulement.gd
#
# Verrouille le CABLAGE de scripts/banc_ecoulement.gd (construction de la
# grille, repartition terre/roche, altitude en pente, absorption/evaporation
# calquee sur depense.gd, couleur, detection au clic/survol) -- jamais
# scripts/ecoulement.gd lui-meme (deja verrouille par test_ecoulement.gd).

const Somme = preload("res://scripts/somme.gd")
const BancEcoulement = preload("res://scripts/banc_ecoulement.gd")
const Depense = preload("res://scripts/depense.gd")
const Verif = preload("res://scripts/verif.gd")

func _config() -> Dictionary:
	return {
		"grille_lignes": 4,
		"grille_colonnes": 4,
		"altitude_max": 20.0,
		"altitude_min": 2.0,
		"rayon_voisinage": 1.5,
		"taux_ecoulement": 5.0,
		"evaporation_par_s": 0.01,
		"eau_initiale": 10.0,
		"nom_reserve": "niveau_eau",
		"nom_altitude": "altitude",
		"taux_decroissance_plancher": 0.02,
		"facteur_permeabilite": 0.3,
		"materiau_gauche": "terre",
		"materiau_droite": "roche",
		"ajout_clic": 5.0,
	}

func _materiaux() -> Dictionary:
	return {
		"terre": {"permeabilite": 0.8},
		"roche": {"permeabilite": 0.05},
	}

func _init() -> void:
	var v := Verif.new()
	_la_grille_contient_lignes_fois_colonnes_cases(v)
	_la_colonne_zero_porte_seule_l_eau_initiale(v)
	_l_altitude_decroit_de_gauche_a_droite(v)
	_moitie_gauche_terre_moitie_droite_roche(v)
	_terre_absorbe_plus_vite_que_roche(v)
	_diagnostic_absorption_evaporation_egale_le_decrement_reel_de_depense(v)
	_la_somme_d_eau_compte_toutes_les_cases(v)
	_couleur_sature_au_dela_de_la_reference_reste_bornee(v)
	_couleur_a_niveau_nul_est_la_couleur_seche(v)
	_case_la_plus_proche_trouve_la_bonne_case(v)
	_ajouter_eau_credite_le_canal_sans_ecraser_l_existant(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_ecoulement.gd construit une grille en pente terre/roche, " +
			"pose l'eau initiale sur la colonne 0 seule, calque son diagnostic " +
			"d'absorption/evaporation sur depense.gd, colore et localise les cases correctement")
		quit(0)

func _la_grille_contient_lignes_fois_colonnes_cases(v) -> void:
	var cases := BancEcoulement.construire_grille(_config(), _materiaux())
	v.v(cases.size() == 16, "une grille 4x4 doit contenir exactement 16 cases, recu %d" % cases.size())

func _la_colonne_zero_porte_seule_l_eau_initiale(v) -> void:
	var cases := BancEcoulement.construire_grille(_config(), _materiaux())
	for case in cases:
		var niveau: float = case.proprietes.reserves.niveau_eau.reserve
		if case.position.x == 0.0:
			v.v(is_equal_approx(niveau, 10.0), "toute case de la colonne 0 doit porter eau_initiale (10.0), recu %.2f sur %s" % [niveau, case.id])
		else:
			v.v(is_equal_approx(niveau, 0.0), "une case hors colonne 0 ne doit porter aucune eau au depart, recu %.2f sur %s" % [niveau, case.id])

func _l_altitude_decroit_de_gauche_a_droite(v) -> void:
	var cases := BancEcoulement.construire_grille(_config(), _materiaux())
	var altitude_col0: float = -1.0
	var altitude_col3: float = -1.0
	for case in cases:
		if case.id == "case_0_0":
			altitude_col0 = case.proprietes.altitude
		if case.id == "case_3_0":
			altitude_col3 = case.proprietes.altitude
	v.v(is_equal_approx(altitude_col0, 20.0), "la colonne 0 doit porter altitude_max (20.0), recu %.2f" % altitude_col0)
	v.v(altitude_col3 < altitude_col0, "la derniere colonne doit etre strictement plus basse que la colonne 0")

func _moitie_gauche_terre_moitie_droite_roche(v) -> void:
	var cases := BancEcoulement.construire_grille(_config(), _materiaux())
	for case in cases:
		var attendu: String = "terre" if case.position.x < 2.0 else "roche"
		v.v(case.proprietes.type_sol == attendu,
			"%s (colonne %d) doit porter type_sol='%s', recu '%s'" % [case.id, int(case.position.x), attendu, case.proprietes.type_sol])

func _terre_absorbe_plus_vite_que_roche(v) -> void:
	var cout_terre := BancEcoulement.cout_base_absorption(0.8, _config())
	var cout_roche := BancEcoulement.cout_base_absorption(0.05, _config())
	v.v(cout_terre > cout_roche, "un sol plus permeable doit avoir un cout_base d'absorption strictement plus grand")
	v.v(cout_roche > 0.0, "meme une roche quasi impermeable doit garder un cout_base strictement positif (plancher)")

func _diagnostic_absorption_evaporation_egale_le_decrement_reel_de_depense(v) -> void:
	var cases := BancEcoulement.construire_grille(_config(), _materiaux())
	var delta := 0.5
	var diag := BancEcoulement.diagnostiquer_absorption_evaporation(cases, "niveau_eau", delta)
	var avant := Somme.reserves(cases, "niveau_eau")
	Depense.avancer(cases, delta, {})
	var apres := Somme.reserves(cases, "niveau_eau")
	var decrement_reel := avant - apres
	v.v(is_equal_approx(diag.absorbe + diag.evapore, decrement_reel),
		"absorbe+evapore doit egaler exactement le decrement reel produit par depense.gd (%.6f attendu, %.6f recu)" % [decrement_reel, diag.absorbe + diag.evapore])
	v.v(diag.absorbe > diag.evapore,
		"sur la colonne 0 (terre, cout_base d'absorption bien au-dessus d'evaporation_par_s=0.01), l'absorption doit dominer")

func _la_somme_d_eau_compte_toutes_les_cases(v) -> void:
	var cases := BancEcoulement.construire_grille(_config(), _materiaux())
	var total := Somme.reserves(cases, "niveau_eau")
	v.v(is_equal_approx(total, 40.0), "4 cases de colonne 0 a 10.0 chacune doivent sommer a 40.0, recu %.2f" % total)

func _couleur_sature_au_dela_de_la_reference_reste_bornee(v) -> void:
	var c_a_reference := BancEcoulement.couleur_pour_niveau(10.0, "terre", 10.0)
	var c_au_dela := BancEcoulement.couleur_pour_niveau(50.0, "terre", 10.0)
	v.v(c_a_reference.is_equal_approx(c_au_dela),
		"une reserve au-dela de la reference doit rendre exactement la meme couleur saturee que la reference elle-meme, jamais divergente")

func _couleur_a_niveau_nul_est_la_couleur_seche(v) -> void:
	var c_terre := BancEcoulement.couleur_pour_niveau(0.0, "terre", 10.0)
	var c_roche := BancEcoulement.couleur_pour_niveau(0.0, "roche", 10.0)
	v.v(not c_terre.is_equal_approx(c_roche),
		"terre et roche seches doivent rendre deux couleurs distinctes (couleur de sol, pas seulement d'eau)")

func _case_la_plus_proche_trouve_la_bonne_case(v) -> void:
	var cases := BancEcoulement.construire_grille(_config(), _materiaux())
	var taille := 60.0
	var trouvee: Variant = BancEcoulement.case_la_plus_proche(cases, Vector2(3.0, 0.0) * taille, taille)
	v.v(trouvee != null and trouvee.id == "case_3_0",
		"un point exactement sur la case_3_0 (en pixels) doit retrouver cette case, recu %s" % (trouvee.id if trouvee != null else "null"))
	v.v(BancEcoulement.case_la_plus_proche([], Vector2.ZERO, taille) == null,
		"une grille vide doit rendre null, jamais planter")

func _ajouter_eau_credite_le_canal_sans_ecraser_l_existant(v) -> void:
	var case := {"id": "x", "position": Vector3.ZERO, "proprietes": {"reserves": {"niveau_eau": {"reserve": 3.0}}}}
	BancEcoulement.ajouter_eau(case, "niveau_eau", 5.0)
	v.v(is_equal_approx(case.proprietes.reserves.niveau_eau.reserve, 8.0),
		"ajouter_eau doit s'ajouter a la reserve existante, jamais l'ecraser (3.0+5.0=8.0), recu %.2f" % case.proprietes.reserves.niveau_eau.reserve)
	var sans_canal := {"id": "y", "position": Vector3.ZERO, "proprietes": {}}
	BancEcoulement.ajouter_eau(sans_canal, "niveau_eau", 5.0)
	v.v(is_equal_approx(sans_canal.proprietes.reserves.niveau_eau.reserve, 5.0),
		"ajouter_eau doit creer le canal minimal si absent")
