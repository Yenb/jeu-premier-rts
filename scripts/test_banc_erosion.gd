extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_erosion.gd
#
# Verrouille le CABLAGE de scripts/banc_erosion.gd (construction de la
# grille, couvert par moitie, erosion par eau = entrainement sur les
# transferts rendus par ecoulement.gd, erosion par vent = appariement par
# vecteur, conservation du sol, couleurs, conversion des sources de vent) --
# jamais les mecanismes eux-memes : ecoulement.gd (test_ecoulement.gd),
# consommer.gd (test_consommer.gd), vent.gd (test_vent.gd),
# etat_effectif.gd (test_etat_effectif.gd) sont deja verrouilles ailleurs et
# INCHANGES par ce chantier.

const Somme = preload("res://scripts/somme.gd")
const BancErosion = preload("res://scripts/banc_erosion.gd")
const Ecoulement = preload("res://scripts/ecoulement.gd")
const Vent = preload("res://scripts/vent.gd")
const Verif = preload("res://scripts/verif.gd")

const TOLERANCE_CONSERVATION := 0.01

# Vent CONSTANT vers +x, meme forme que l'entree "vent" de
# data/banc_erosion.json (reference_force = force de fond, donc effet
# directionnel toujours PLEIN).
func _catalogue_vent(force: float = 6.0) -> Dictionary:
	return {
		"defaut": {
			"fond": {"direction": {"x": 1.0, "y": 0.0, "z": 0.0}, "force": force},
			"variation_lente": {"amplitude_angle": 0.0, "periode_angle": 0.0, "amplitude_force": 0.0, "periode_force": 0.0},
			"rafales": {"amplitude": 0.0, "frequence": 0.0},
			"attenuation_source": {"exposant": 1.0},
			"directionnel": {"reference_force": 6.0, "facteur_max_sous_vent": 2.2, "facteur_min_contre_vent": 0.4},
		},
	}

func _config() -> Dictionary:
	return {
		"grille_lignes": 4,
		"grille_colonnes": 4,
		"altitude_max": 20.0,
		"altitude_min": 2.0,
		"rayon_voisinage": 1.5,
		"taux_ecoulement": 5.0,
		"eau_initiale": 10.0,
		"sol_initial": 100.0,
		"sol_capacite": 100.0,
		"couvert_gauche": 0.8,
		"couvert_droite": 0.0,
		"coefficient_erosion_eau": 0.05,
		"taux_erosion_vent": 0.08,
		"nom_reserve_sol": "sol",
		"nom_reserve_eau": "niveau_eau",
		"nom_altitude": "altitude",
		"nom_couvert": "couvert_vegetal",
		"ajout_eau_clic": 5.0,
		"sources_vent": [],
	}

func _case(id: String, position: Vector3, sol: float, couvert: float, altitude: float = 0.0, eau: float = 0.0) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"altitude": altitude,
			"couvert_vegetal": couvert,
			"reserves": {
				"sol": {"reserve": sol, "capacite": 100.0},
				"niveau_eau": {"reserve": eau},
			},
		},
	}

func _init() -> void:
	var v := Verif.new()
	_la_grille_pose_le_meme_sol_partout_et_l_eau_sur_la_colonne_zero(v)
	_la_moitie_gauche_est_couverte_la_moitie_droite_est_nue(v)
	_le_sol_total_reste_constant_sur_la_grille_reelle(v)
	_le_sol_nu_s_erode_plus_vite_que_le_sol_couvert(v)
	_le_sol_emporte_par_l_eau_arrive_sur_la_case_aval(v)
	_le_sol_emporte_par_le_vent_arrive_dans_le_sens_du_vent(v)
	_sans_eau_et_sans_vent_le_sol_ne_bouge_pas(v)
	_un_couvert_total_empeche_toute_erosion_par_vent(v)
	_une_case_ne_donne_jamais_plus_de_sol_qu_elle_n_en_possede(v)
	_les_couleurs_de_sol_disent_l_epaisseur(v)
	_les_sources_de_vent_de_la_donnee_deviennent_des_vector3(v)
	_la_donnee_du_banc_declare_un_vent_constant_de_gauche_a_droite(v)
	_case_la_plus_proche_et_ajout_d_eau(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_erosion.gd conserve le sol (rien ne disparait, tout se depose), " +
			"erode par entrainement de l'eau vers la case aval et par le vent vers les seuls " +
			"voisins sous le vent, protege le sol couvert et n'erode rien sans eau ni vent")
		quit(0)

func _la_grille_pose_le_meme_sol_partout_et_l_eau_sur_la_colonne_zero(v) -> void:
	var cases := BancErosion.construire_grille(_config())
	v.v(cases.size() == 16, "une grille 4x4 doit contenir exactement 16 cases, recu %d" % cases.size())
	for case in cases:
		var sol: float = case.proprietes.reserves.sol.reserve
		var eau: float = case.proprietes.reserves.niveau_eau.reserve
		v.v(is_equal_approx(sol, 100.0), "toute case doit partir avec sol_initial (100.0), recu %.2f sur %s" % [sol, case.id])
		if case.position.x == 0.0:
			v.v(is_equal_approx(eau, 10.0), "toute case de la colonne 0 doit porter eau_initiale (10.0), recu %.2f sur %s" % [eau, case.id])
		else:
			v.v(is_equal_approx(eau, 0.0), "une case hors colonne 0 ne doit porter aucune eau au depart, recu %.2f sur %s" % [eau, case.id])
	var altitude_gauche: float = -1.0
	var altitude_droite: float = -1.0
	for case in cases:
		if case.id == "case_0_0":
			altitude_gauche = case.proprietes.altitude
		if case.id == "case_3_0":
			altitude_droite = case.proprietes.altitude
	v.v(is_equal_approx(altitude_gauche, 20.0), "la colonne 0 doit porter altitude_max (20.0), recu %.2f" % altitude_gauche)
	v.v(altitude_droite < altitude_gauche, "la derniere colonne doit etre strictement plus basse que la colonne 0 (pente)")

func _la_moitie_gauche_est_couverte_la_moitie_droite_est_nue(v) -> void:
	var cases := BancErosion.construire_grille(_config())
	for case in cases:
		var attendu: float = 0.8 if case.position.x < 2.0 else 0.0
		v.v(is_equal_approx(case.proprietes.couvert_vegetal, attendu),
			"%s (colonne %d) doit porter couvert_vegetal=%.2f, recu %.2f" % [case.id, int(case.position.x), attendu, case.proprietes.couvert_vegetal])

# Le compteur du banc doit rester plat : le sol ne disparait JAMAIS (aucun
# depense.gd sur la reserve de sol), il ne fait que changer de case.
func _le_sol_total_reste_constant_sur_la_grille_reelle(v) -> void:
	var config := _charger("res://data/banc_erosion.json")
	var etats := _charger("res://data/etats.json")
	var cases := BancErosion.construire_grille(config)
	var sol_initial := Somme.reserves(cases, config.nom_reserve_sol)
	v.v(sol_initial > 0.0, "la grille reelle doit porter du sol au depart, recu %.2f" % sol_initial)
	var sources := BancErosion.sources_depuis_donnee(config)
	var temps := 0.0
	var delta := 0.1
	for pas in range(40):
		temps += delta
		var transferts: Array = Ecoulement.avancer(cases, config.rayon_voisinage, config.nom_reserve_eau, config.nom_altitude, config.taux_ecoulement, delta)
		BancErosion.eroder_par_eau(cases, transferts, config.nom_reserve_sol, config.coefficient_erosion_eau)
		BancErosion.eroder_par_vent(cases, config, config.vent, sources, etats, temps, delta)
	var sol_final := Somme.reserves(cases, config.nom_reserve_sol)
	v.v(abs(sol_final - sol_initial) < TOLERANCE_CONSERVATION,
		"le sol total doit rester constant apres 40 pas (depart %.4f, arrivee %.4f, ecart %.6f)" % [sol_initial, sol_final, sol_final - sol_initial])
	var colonne_gauche := 0.0
	var colonne_droite := 0.0
	for case in cases:
		if case.position.x == 0.0:
			colonne_gauche += case.proprietes.reserves[config.nom_reserve_sol].reserve
		if case.position.x == float(int(config.grille_colonnes) - 1):
			colonne_droite += case.proprietes.reserves[config.nom_reserve_sol].reserve
	v.v(colonne_droite > colonne_gauche,
		"le sol emporte doit s'accumuler en bas de pente : la derniere colonne (%.2f) doit porter plus de sol que la colonne 0 (%.2f)" % [colonne_droite, colonne_gauche])

func _le_sol_nu_s_erode_plus_vite_que_le_sol_couvert(v) -> void:
	# Deux paires INDEPENDANTES, hors de portee l'une de l'autre (y=0 et
	# y=10, rayon_voisinage=1.5) : la seule difference est le couvert.
	var cases := [
		_case("couverte", Vector3(0.0, 0.0, 0.0), 100.0, 0.8),
		_case("aval_couverte", Vector3(1.0, 0.0, 0.0), 100.0, 0.8),
		_case("nue", Vector3(0.0, 10.0, 0.0), 100.0, 0.0),
		_case("aval_nue", Vector3(1.0, 10.0, 0.0), 100.0, 0.0),
	]
	BancErosion.eroder_par_vent(cases, _config(), _catalogue_vent(), [], {}, 0.0, 1.0)
	var perte_couverte: float = 100.0 - cases[0].proprietes.reserves.sol.reserve
	var perte_nue: float = 100.0 - cases[2].proprietes.reserves.sol.reserve
	v.v(perte_couverte > 0.0, "un sol couvert a 0.8 doit tout de meme s'eroder un peu, recu %.4f" % perte_couverte)
	v.v(perte_nue > perte_couverte,
		"un sol nu doit s'eroder strictement plus vite qu'un sol couvert (nu %.4f, couvert %.4f)" % [perte_nue, perte_couverte])

func _le_sol_emporte_par_l_eau_arrive_sur_la_case_aval(v) -> void:
	var cases := [
		_case("haut", Vector3(0.0, 0.0, 0.0), 100.0, 0.0, 20.0, 10.0),
		_case("bas", Vector3(1.0, 0.0, 0.0), 100.0, 0.0, 2.0, 0.0),
	]
	var transferts := Ecoulement.avancer(cases, 1.5, "niveau_eau", "altitude", 5.0, 0.1)
	v.v(transferts.size() > 0, "l'eau doit couler de la case haute vers la case basse (aucun transfert rendu)")
	var faits := BancErosion.eroder_par_eau(cases, transferts, "sol", 0.05)
	v.v(faits.size() > 0, "un transfert d'eau doit entrainer un transfert de sol sur la MEME paire")
	v.v(faits[0].source_id == "haut" and faits[0].receveur_id == "bas",
		"le sol doit partir de la case amont vers la case aval, recu %s -> %s" % [faits[0].source_id, faits[0].receveur_id])
	var sol_haut: float = cases[0].proprietes.reserves.sol.reserve
	var sol_bas: float = cases[1].proprietes.reserves.sol.reserve
	v.v(sol_haut < 100.0, "la case amont doit avoir perdu du sol, recu %.4f" % sol_haut)
	v.v(sol_bas > 100.0, "la case aval doit avoir gagne du sol, recu %.4f" % sol_bas)
	v.v(is_equal_approx(sol_haut + sol_bas, 200.0),
		"le sol emporte par l'eau doit etre conserve exactement (%.6f attendu 200.0)" % (sol_haut + sol_bas))
	var attendu: float = BancErosion.somme_quantites(transferts) * 0.05
	v.v(is_equal_approx(100.0 - sol_haut, attendu),
		"la quantite de sol emportee doit valoir exactement debit_eau * coefficient_erosion_eau (%.6f attendu, %.6f recu)" % [attendu, 100.0 - sol_haut])

func _le_sol_emporte_par_le_vent_arrive_dans_le_sens_du_vent(v) -> void:
	# Trois cases alignees sur l'axe du vent (+x) : le sol descend de gauche
	# a droite, jamais l'inverse.
	var cases := [
		_case("gauche", Vector3(0.0, 0.0, 0.0), 100.0, 0.0),
		_case("milieu", Vector3(1.0, 0.0, 0.0), 100.0, 0.0),
		_case("droite", Vector3(2.0, 0.0, 0.0), 100.0, 0.0),
	]
	var faits := BancErosion.eroder_par_vent(cases, _config(), _catalogue_vent(), [], {}, 0.0, 1.0)
	for fait in faits:
		var source: Vector3 = _position_de(cases, fait.source_id)
		var receveur: Vector3 = _position_de(cases, fait.receveur_id)
		v.v(receveur.x > source.x,
			"le vent souffle vers +x : aucun transfert ne doit aller vers une case de x inferieur ou egal (%s -> %s)" % [fait.source_id, fait.receveur_id])
	v.v(cases[0].proprietes.reserves.sol.reserve < 100.0, "la case la plus au vent doit perdre du sol")
	v.v(cases[2].proprietes.reserves.sol.reserve > 100.0, "la case la plus sous le vent doit gagner du sol")
	var total: float = cases[0].proprietes.reserves.sol.reserve + cases[1].proprietes.reserves.sol.reserve + cases[2].proprietes.reserves.sol.reserve
	v.v(abs(total - 300.0) < TOLERANCE_CONSERVATION,
		"le sol emporte par le vent doit etre conserve (%.6f attendu 300.0)" % total)
	# Un voisin PERPENDICULAIRE au vent (facteur exactement 1.0) ne recoit
	# jamais rien -- c'est ce que la gate "> 1.0" garantit, et ce qu'une gate
	# "> 0.0" (facteur_min_contre_vent = 0.4) aurait laisse passer.
	var perpendiculaires := [
		_case("centre", Vector3(0.0, 0.0, 0.0), 100.0, 0.0),
		_case("dessus", Vector3(0.0, -1.0, 0.0), 100.0, 0.0),
		_case("dessous", Vector3(0.0, 1.0, 0.0), 100.0, 0.0),
	]
	BancErosion.eroder_par_vent(perpendiculaires, _config(), _catalogue_vent(), [], {}, 0.0, 1.0)
	for case in perpendiculaires:
		v.v(is_equal_approx(case.proprietes.reserves.sol.reserve, 100.0),
			"un voisin perpendiculaire au vent ne doit ni perdre ni recevoir de sol, recu %.4f sur %s" % [case.proprietes.reserves.sol.reserve, case.id])

func _sans_eau_et_sans_vent_le_sol_ne_bouge_pas(v) -> void:
	var config := _config()
	var cases := BancErosion.construire_grille(config)
	for case in cases:
		case.proprietes.reserves.niveau_eau.reserve = 0.0
	var sans_vent := _catalogue_vent(0.0)
	for pas in range(20):
		var transferts: Array = Ecoulement.avancer(cases, config.rayon_voisinage, config.nom_reserve_eau, config.nom_altitude, config.taux_ecoulement, 0.1)
		v.v(transferts.is_empty(), "sans eau, ecoulement.gd ne doit rendre aucun transfert")
		BancErosion.eroder_par_eau(cases, transferts, config.nom_reserve_sol, config.coefficient_erosion_eau)
		var faits: Array = BancErosion.eroder_par_vent(cases, config, sans_vent, [], {}, float(pas) * 0.1, 0.1)
		v.v(faits.is_empty(), "un vent de force nulle ne doit emporter aucun sol")
	for case in cases:
		v.v(is_equal_approx(case.proprietes.reserves.sol.reserve, 100.0),
			"sans eau et sans vent, chaque case doit garder exactement son sol de depart, recu %.4f sur %s" % [case.proprietes.reserves.sol.reserve, case.id])

func _un_couvert_total_empeche_toute_erosion_par_vent(v) -> void:
	var cases := [
		_case("protegee", Vector3(0.0, 0.0, 0.0), 100.0, 1.0),
		_case("aval", Vector3(1.0, 0.0, 0.0), 100.0, 1.0),
	]
	var faits := BancErosion.eroder_par_vent(cases, _config(), _catalogue_vent(), [], {}, 0.0, 1.0)
	v.v(faits.is_empty(), "un couvert_vegetal de 1.0 doit empecher TOUT transfert par le vent, recu %d" % faits.size())
	for case in cases:
		v.v(is_equal_approx(case.proprietes.reserves.sol.reserve, 100.0),
			"une case entierement couverte ne doit perdre aucun sol, recu %.4f sur %s" % [case.proprietes.reserves.sol.reserve, case.id])

# Pre-bornage : la demande (force * taux * exposition * delta) depasse
# largement la reserve -- la case donne ce qu'elle a, jamais plus, et la
# conservation tient (voir en-tete de banc_erosion.gd, PRE-BORNAGE).
func _une_case_ne_donne_jamais_plus_de_sol_qu_elle_n_en_possede(v) -> void:
	var config := _config()
	config.taux_erosion_vent = 100.0
	var cases := [
		_case("presque_vide", Vector3(0.0, 0.0, 0.0), 0.01, 0.0),
		_case("voisin_droit", Vector3(1.0, 0.0, 0.0), 0.0, 0.0),
		_case("voisin_diagonal", Vector3(1.0, 1.0, 0.0), 0.0, 0.0),
	]
	BancErosion.eroder_par_vent(cases, config, _catalogue_vent(), [], {}, 0.0, 1.0)
	var total := Somme.reserves(cases, "sol")
	v.v(is_equal_approx(cases[0].proprietes.reserves.sol.reserve, 0.0),
		"une case dont la demande depasse la reserve doit tomber exactement a zero, recu %.6f" % cases[0].proprietes.reserves.sol.reserve)
	v.v(is_equal_approx(total, 0.01),
		"meme quand la demande depasse la reserve, le sol total doit rester conserve (0.01 attendu, %.6f recu)" % total)

func _les_couleurs_de_sol_disent_l_epaisseur(v) -> void:
	var roche := BancErosion.couleur_pour_sol(0.0, 100.0)
	var mince := BancErosion.couleur_pour_sol(10.0, 100.0)
	var epais := BancErosion.couleur_pour_sol(100.0, 100.0)
	var depot := BancErosion.couleur_pour_sol(250.0, 100.0)
	v.v(not roche.is_equal_approx(mince), "une case sans sol (roche nue) doit avoir une couleur distincte d'une case a sol mince")
	v.v(epais.v < mince.v, "un sol epais doit etre strictement plus fonce qu'un sol mince (v %.3f vs %.3f)" % [epais.v, mince.v])
	v.v(depot.is_equal_approx(epais), "un depot au-dela de la capacite doit rendre exactement la meme couleur que la capacite, jamais divergente")
	v.v(BancErosion.couleur_pour_sol(50.0, 0.0).is_equal_approx(roche), "une capacite nulle doit rendre la roche nue, jamais une division par zero")
	var sec := BancErosion.couleur_pour_eau(0.0, 10.0)
	var mouille := BancErosion.couleur_pour_eau(10.0, 10.0)
	v.v(is_equal_approx(sec.a, 0.0), "une case sans eau doit rendre une superposition totalement transparente, recu a=%.3f" % sec.a)
	v.v(mouille.a > sec.a, "plus d'eau doit rendre la superposition bleue plus opaque")

func _les_sources_de_vent_de_la_donnee_deviennent_des_vector3(v) -> void:
	var config := _config()
	config.sources_vent = [{
		"position": {"x": 2.0, "y": 3.0, "z": 0.0},
		"rayon": 4.0,
		"vecteur": {"x": 0.0, "y": -5.0, "z": 0.0},
	}]
	var sources := BancErosion.sources_depuis_donnee(config)
	v.v(sources.size() == 1, "une source declaree en donnee doit rendre exactement une source, recu %d" % sources.size())
	v.v(sources[0].position is Vector3 and sources[0].vecteur is Vector3,
		"position et vecteur doivent etre convertis en Vector3 (vent.gd appelle distance_to dessus)")
	v.v(sources[0].position.is_equal_approx(Vector3(2.0, 3.0, 0.0)), "la position de la source doit etre conservee exactement")
	# La source doit reellement perturber le vent la ou elle est posee.
	var catalogue := _catalogue_vent()
	var au_centre: Vector3 = Vent.vecteur(Vector3(2.0, 3.0, 0.0), 0.0, catalogue, sources)
	var au_loin: Vector3 = Vent.vecteur(Vector3(20.0, 20.0, 0.0), 0.0, catalogue, sources)
	v.v(not au_centre.is_equal_approx(au_loin), "une source locale doit modifier le vent dans son rayon et pas au-dela")
	v.v(BancErosion.sources_depuis_donnee(_config()).is_empty(), "sans sources_vent declarees, la liste doit rester vide")

func _la_donnee_du_banc_declare_un_vent_constant_de_gauche_a_droite(v) -> void:
	var config := _charger("res://data/banc_erosion.json")
	var catalogue: Dictionary = config.vent
	var tot: Vector3 = Vent.vecteur(Vector3.ZERO, 0.0, catalogue, [])
	var tard: Vector3 = Vent.vecteur(Vector3(7.0, 7.0, 0.0), 137.4, catalogue, [])
	v.v(tot.is_equal_approx(tard), "le vent du banc doit etre CONSTANT dans le temps et l'espace (%s puis %s)" % [tot, tard])
	v.v(tot.x > 0.0 and is_equal_approx(tot.y, 0.0), "le vent du banc doit souffler de gauche a droite (+x), recu %s" % tot)
	v.v(float(config.couvert_gauche) > float(config.couvert_droite),
		"la moitie gauche doit etre plus couverte que la moitie droite (gauche %.2f, droite %.2f)" % [config.couvert_gauche, config.couvert_droite])

func _case_la_plus_proche_et_ajout_d_eau(v) -> void:
	var cases := BancErosion.construire_grille(_config())
	var trouvee: Variant = BancErosion.case_la_plus_proche(cases, Vector2(3.0, 0.0) * 82.0, 82.0)
	v.v(trouvee != null and trouvee.id == "case_3_0",
		"un point exactement sur case_3_0 (en pixels) doit retrouver cette case, recu %s" % ("null" if trouvee == null else trouvee.id))
	v.v(BancErosion.case_la_plus_proche([], Vector2.ZERO, 82.0) == null, "une grille vide doit rendre null, jamais planter")
	var case := {"id": "x", "position": Vector3.ZERO, "proprietes": {"reserves": {"niveau_eau": {"reserve": 3.0}}}}
	BancErosion.ajouter_eau(case, "niveau_eau", 5.0)
	v.v(is_equal_approx(case.proprietes.reserves.niveau_eau.reserve, 8.0),
		"ajouter_eau doit s'ajouter a la reserve existante, jamais l'ecraser (3.0+5.0=8.0), recu %.2f" % case.proprietes.reserves.niveau_eau.reserve)

func _position_de(cases: Array, id: String) -> Vector3:
	for case in cases:
		if case.id == id:
			return case.position
	return Vector3.ZERO

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
