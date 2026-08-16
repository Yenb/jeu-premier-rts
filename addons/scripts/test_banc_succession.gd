extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_succession.gd
#
# Verrouille le CABLAGE de scripts/banc_succession.gd (construction de la
# grille, chainage senescence -> stade, exclusivite des stades, remise a zero
# par le feu, redemarrage apres feu, horloge conditionnelle) -- jamais
# scripts/stade.gd ni scripts/senescence.gd eux-memes (deja verrouilles par
# test_stade.gd/test_senescence.gd, hors domaine).
#
# Verifie aussi, sur le disque, que data/banc_succession.json declare bien
# ses stades par age_seuil STRICTEMENT croissant : stade.gd cherche le
# DERNIER element dont age_seuil <= age, un catalogue mal ordonne rendrait la
# succession observee incoherente sans qu'aucun mecanisme n'alarme.

const BancSuccession = preload("res://scripts/banc_succession.gd")
const Verif = preload("res://scripts/verif.gd")

const CHEMIN_CONFIG := "res://data/banc_succession.json"

func _config() -> Dictionary:
	return {
		"grille_lignes": 3,
		"grille_colonnes": 3,
		"annees_par_seconde": 10.0,
		"propriete_croissance": "croissance_possible",
		"colonne_sterile": 2,
		"rayon_feu": 1.5,
		"stades_config": [
			{ "nom": "nu", "age_seuil": 0.0 },
			{ "nom": "prairie", "age_seuil": 4.0 },
			{ "nom": "taillis", "age_seuil": 16.0 },
			{ "nom": "foret", "age_seuil": 60.0 },
		],
		"couleurs_stade": {
			"nu": [0.42, 0.30, 0.16],
			"prairie": [0.58, 0.85, 0.36],
			"taillis": [0.25, 0.62, 0.26],
			"foret": [0.07, 0.31, 0.12],
		},
	}

func _config_avec(surcharges: Dictionary) -> Dictionary:
	var config := _config()
	for cle in surcharges:
		config[cle] = surcharges[cle]
	return config

func _noms_stades(config: Dictionary) -> Array:
	var noms: Array = []
	for entree in config.stades_config:
		noms.append(entree.nom)
	return noms

func _case_par_id(cases: Array, id: String) -> Dictionary:
	for case in cases:
		if case.id == id:
			return case
	return {}

func _init() -> void:
	var v := Verif.new()
	_la_grille_contient_lignes_fois_colonnes_cases_toutes_au_premier_stade(v)
	_une_case_traverse_les_quatre_stades_dans_l_ordre(v)
	_les_stades_restent_exclusifs_a_chaque_instant(v)
	_un_feu_remet_age_a_zero_et_stade_au_premier(v)
	_apres_un_feu_la_succession_repart_normalement(v)
	_annees_par_seconde_nul_empeche_tout_vieillissement(v)
	_la_colonne_sterile_ne_vieillit_jamais_pendant_que_les_autres_progressent(v)
	_le_feu_ne_touche_que_la_cible_et_ses_voisines_immediates(v)
	_le_feu_ne_retire_jamais_la_condition_de_croissance(v)
	_la_couleur_change_a_chaque_stade_et_reste_neutre_pour_un_stade_inconnu(v)
	_le_compteur_totalise_toujours_toutes_les_cases(v)
	_le_catalogue_reel_declare_ses_stades_par_age_seuil_strictement_croissant(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_succession.gd fait traverser a une case les stades nu -> prairie -> " +
			"taillis -> foret dans l'ordre et un seul a la fois, remet age et stade a zero " +
			"sur la case brulee et ses voisines immediates seules, fait repartir la succession " +
			"apres le feu, et arrete completement l'horloge quand annees_par_seconde vaut 0.0")
		quit(0)

func _la_grille_contient_lignes_fois_colonnes_cases_toutes_au_premier_stade(v) -> void:
	var config := _config()
	var cases := BancSuccession.construire_grille(config)
	v.v(cases.size() == 9, "une grille 3x3 doit contenir exactement 9 cases, recu %d" % cases.size())
	for case in cases:
		v.v(is_equal_approx(case.proprietes.age, 0.0), "%s doit demarrer a age 0.0, recu %.2f" % [case.id, case.proprietes.age])
		v.v(case.proprietes.stade == "nu", "%s doit demarrer au premier stade du catalogue ('nu'), recu '%s'" % [case.id, case.proprietes.stade])
		v.v(case.proprietes.has("stades_config"), "%s doit porter stades_config (STRUCTURELLE pour stade.gd)" % case.id)
		v.v(is_equal_approx(case.position.z, 0.0), "%s doit garder position.z a 0.0 (fait spatial pur en unites de grille)" % case.id)

func _une_case_traverse_les_quatre_stades_dans_l_ordre(v) -> void:
	var config := _config()
	var cases := BancSuccession.construire_grille(config)
	var case := _case_par_id(cases, "case_0_0")
	var sequence: Array = [case.proprietes.stade]
	for _i in range(200):
		BancSuccession.avancer_cases(cases, 0.05, config)
		if case.proprietes.stade != sequence[sequence.size() - 1]:
			sequence.append(case.proprietes.stade)
	v.v(sequence == ["nu", "prairie", "taillis", "foret"],
		"une case fertile doit traverser exactement nu -> prairie -> taillis -> foret dans cet ordre, recu %s" % str(sequence))

func _les_stades_restent_exclusifs_a_chaque_instant(v) -> void:
	var config := _config()
	var noms := _noms_stades(config)
	var cases := BancSuccession.construire_grille(config)
	var case := _case_par_id(cases, "case_0_0")
	for _i in range(200):
		BancSuccession.avancer_cases(cases, 0.05, config)
		var correspondances := 0
		for nom in noms:
			if case.proprietes.stade == nom:
				correspondances += 1
			v.v(not case.proprietes.has(nom),
				"un nom de stade ('%s') ne doit JAMAIS devenir une propriete a part sur la case -- proprietes.stade porte le stade courant, seul" % nom)
		v.v(correspondances == 1,
			"a tout instant, la case doit porter exactement UN stade du catalogue, recu %d pour '%s'" % [correspondances, case.proprietes.stade])

func _un_feu_remet_age_a_zero_et_stade_au_premier(v) -> void:
	var config := _config()
	var cases := BancSuccession.construire_grille(config)
	var case := _case_par_id(cases, "case_1_1")
	for _i in range(200):
		BancSuccession.avancer_cases(cases, 0.05, config)
	v.v(case.proprietes.stade == "foret", "avant le feu, la case centrale doit avoir atteint 'foret', recu '%s'" % case.proprietes.stade)
	var brulees: Array = BancSuccession.declencher_feu(cases, case, config)
	v.v(brulees.has("case_1_1"), "la case cliquee doit toujours figurer parmi les cases brulees")
	v.v(is_equal_approx(case.proprietes.age, 0.0), "un feu doit remettre age a 0.0, recu %.2f" % case.proprietes.age)
	v.v(case.proprietes.stade == "nu", "un feu doit remettre stade au premier stade du catalogue ('nu'), recu '%s'" % case.proprietes.stade)

func _apres_un_feu_la_succession_repart_normalement(v) -> void:
	var config := _config()
	var cases := BancSuccession.construire_grille(config)
	var case := _case_par_id(cases, "case_1_1")
	for _i in range(200):
		BancSuccession.avancer_cases(cases, 0.05, config)
	BancSuccession.declencher_feu(cases, case, config)
	var sequence: Array = [case.proprietes.stade]
	for _i in range(200):
		BancSuccession.avancer_cases(cases, 0.05, config)
		if case.proprietes.stade != sequence[sequence.size() - 1]:
			sequence.append(case.proprietes.stade)
	v.v(sequence == ["nu", "prairie", "taillis", "foret"],
		"apres un feu, la case brulee doit refaire toute la succession dans l'ordre (stade.gd ne bloque pas la remontee des lors que le cablage a remis age ET stade), recu %s" % str(sequence))

func _annees_par_seconde_nul_empeche_tout_vieillissement(v) -> void:
	var config := _config_avec({"annees_par_seconde": 0.0})
	var cases := BancSuccession.construire_grille(config)
	for _i in range(400):
		BancSuccession.avancer_cases(cases, 0.5, config)
	for case in cases:
		v.v(is_equal_approx(case.proprietes.age, 0.0),
			"a annees_par_seconde=0.0, l'age de %s ne doit jamais bouger, recu %.4f" % [case.id, case.proprietes.age])
		v.v(case.proprietes.stade == "nu",
			"a annees_par_seconde=0.0, %s doit rester au premier stade, recu '%s'" % [case.id, case.proprietes.stade])

func _la_colonne_sterile_ne_vieillit_jamais_pendant_que_les_autres_progressent(v) -> void:
	var config := _config()
	var cases := BancSuccession.construire_grille(config)
	for _i in range(200):
		BancSuccession.avancer_cases(cases, 0.05, config)
	for case in cases:
		if int(case.position.x) == 2:
			v.v(is_equal_approx(case.proprietes.age, 0.0),
				"la colonne sterile (croissance_possible=false) doit garder age 0.0, recu %.4f sur %s" % [case.proprietes.age, case.id])
			v.v(case.proprietes.stade == "nu",
				"la colonne sterile doit rester au premier stade, recu '%s' sur %s" % [case.proprietes.stade, case.id])
		else:
			v.v(case.proprietes.stade == "foret",
				"une colonne fertile doit avoir atteint 'foret' apres 10 s simulees, recu '%s' sur %s" % [case.proprietes.stade, case.id])
	v.v(is_equal_approx(BancSuccession.annees_par_seconde_pour_case(_case_par_id(cases, "case_2_0"), config), 0.0),
		"annees_par_seconde_pour_case doit rendre 0.0 sur une case sterile")
	v.v(is_equal_approx(BancSuccession.annees_par_seconde_pour_case(_case_par_id(cases, "case_0_0"), config), 10.0),
		"annees_par_seconde_pour_case doit rendre le taux nominal sur une case fertile")
	var sans_condition := _config_avec({"propriete_croissance": ""})
	var cases_sans_condition := BancSuccession.construire_grille(sans_condition)
	v.v(is_equal_approx(BancSuccession.annees_par_seconde_pour_case(cases_sans_condition[0], sans_condition), 10.0),
		"propriete_croissance vide doit desactiver la condition : taux nominal partout")

func _le_feu_ne_touche_que_la_cible_et_ses_voisines_immediates(v) -> void:
	var config := _config_avec({"grille_lignes": 5, "grille_colonnes": 5, "colonne_sterile": -1})
	var cases := BancSuccession.construire_grille(config)
	for _i in range(200):
		BancSuccession.avancer_cases(cases, 0.05, config)
	var brulees: Array = BancSuccession.declencher_feu(cases, _case_par_id(cases, "case_2_2"), config)
	v.v(brulees.size() == 9, "un feu au centre d'une grille 5x5 doit bruler exactement 9 cases (la cible + ses 8 voisines Moore), recu %d" % brulees.size())
	for case in cases:
		var voisine: bool = absi(int(case.position.x) - 2) <= 1 and absi(int(case.position.y) - 2) <= 1
		if voisine:
			v.v(case.proprietes.stade == "nu", "%s (voisine immediate) doit avoir brule, recu '%s'" % [case.id, case.proprietes.stade])
		else:
			v.v(case.proprietes.stade == "foret", "%s (au-dela des voisines immediates) ne doit PAS avoir brule, recu '%s'" % [case.id, case.proprietes.stade])

func _le_feu_ne_retire_jamais_la_condition_de_croissance(v) -> void:
	var config := _config()
	var cases := BancSuccession.construire_grille(config)
	var sterile := _case_par_id(cases, "case_2_1")
	BancSuccession.declencher_feu(cases, sterile, config)
	v.v(sterile.proprietes.croissance_possible == false,
		"une case sterile brulee doit rester sterile -- le feu ne touche que age et stade")
	for _i in range(200):
		BancSuccession.avancer_cases(cases, 0.05, config)
	v.v(sterile.proprietes.stade == "nu",
		"une case sterile brulee ne doit toujours jamais progresser apres le feu, recu '%s'" % sterile.proprietes.stade)

func _la_couleur_change_a_chaque_stade_et_reste_neutre_pour_un_stade_inconnu(v) -> void:
	var config := _config()
	var vues: Array = []
	for nom in _noms_stades(config):
		var couleur := BancSuccession.couleur_pour_stade(nom, config)
		for deja in vues:
			v.v(not couleur.is_equal_approx(deja), "chaque stade doit avoir sa propre couleur -- '%s' en partage une avec un autre" % nom)
		vues.append(couleur)
	var inconnu := BancSuccession.couleur_pour_stade("stade_absent_du_catalogue", config)
	v.v(inconnu.is_equal_approx(Color(0.5, 0.5, 0.5)), "un stade absent de la table de couleurs doit rendre le gris neutre, jamais planter")

func _le_compteur_totalise_toujours_toutes_les_cases(v) -> void:
	var config := _config()
	var cases := BancSuccession.construire_grille(config)
	for _i in range(60):
		BancSuccession.avancer_cases(cases, 0.05, config)
		var comptes := BancSuccession.compter_par_stade(cases, config)
		var total := 0
		for nom in comptes:
			total += comptes[nom]
		v.v(total == cases.size(),
			"la somme des cases par stade doit toujours egaler le nombre de cases (%d attendu, %d recu) -- preuve de l'exclusivite au niveau de la grille" % [cases.size(), total])

func _le_catalogue_reel_declare_ses_stades_par_age_seuil_strictement_croissant(v) -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHEMIN_CONFIG))
	var stades: Array = config.stades_config
	v.v(stades.size() >= 2, "data/banc_succession.json doit declarer au moins deux stades, recu %d" % stades.size())
	for i in range(1, stades.size()):
		v.v(float(stades[i].age_seuil) > float(stades[i - 1].age_seuil),
			"data/banc_succession.json : age_seuil doit croitre STRICTEMENT (stade.gd prend le dernier seuil atteint) -- '%s' (%.1f) n'est pas au-dessus de '%s' (%.1f)" %
			[stades[i].nom, float(stades[i].age_seuil), stades[i - 1].nom, float(stades[i - 1].age_seuil)])
	v.v(is_equal_approx(float(stades[0].age_seuil), 0.0),
		"le premier stade du catalogue reel doit avoir age_seuil 0.0 -- c'est l'etat d'une case neuve et l'etat vers lequel un feu la ramene")
	v.v(BancSuccession.nom_stade_initial(config) == stades[0].nom,
		"nom_stade_initial doit rendre le premier stade declare par le catalogue reel")
