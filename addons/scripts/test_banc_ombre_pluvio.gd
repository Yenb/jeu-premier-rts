extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_ombre_pluvio.gd
#
# Verrouille le CABLAGE de scripts/banc_ombre_pluvio.gd (construction de la
# grille, profil de montagne, normalisation altitude -> relief_bloquant,
# liste d'obstacles, ecriture de l'humidite sur chaque case, couleurs,
# survol) -- jamais scripts/champ_occulte.gd ni scripts/occlusion.gd
# eux-memes (deja verrouilles par test_champ_occulte.gd/test_occlusion.gd).
#
# VERROUILLE AUSSI LA DONNEE REELLE (data/banc_ombre_pluvio.json, relue sur
# le disque par le dernier cas) : le premier lancement de ce banc a construit
# une grille SANS AUCUN RELIEF parce que JSON.parse_string rend tout nombre
# en float et qu'Array.has() est strict sur le type -- [1.0,2.0,3.0].has(1)
# rend false. Le bug etait invisible a l'oeil (une grille sans ombre reste
# une grille plausible). Ce cas empeche qu'il revienne.

const Banc = preload("res://scripts/banc_ombre_pluvio.gd")
const Verif = preload("res://scripts/verif.gd")

const CHEMIN_CONFIG := "res://data/banc_ombre_pluvio.json"

# Config de test, volontairement plus petite que la reelle et aux nombres
# ronds (source a distance 4.0 de la colonne 0, force 60.0 -> 15.0).
func _config() -> Dictionary:
	return {
		"grille_colonnes": 10,
		"grille_lignes": 6,
		"colonne_relief": 4,
		"lignes_relief": [1, 2, 3],
		"ligne_sommet": 2,
		"altitude_plaine": 2.0,
		"altitude_epaule": 8.0,
		"altitude_sommet": 14.0,
		"altitude_plancher": 2.0,
		"altitude_plafond": 20.0,
		"source_position": {"x": -4.0, "y": 2.0, "z": 0.0},
		"humidite_emission": 60.0,
		"propriete_emission": "humidite_emission",
		"propriete_obstacle": "relief_bloquant",
		"nom_propriete_humidite": "humidite",
		"nom_altitude": "altitude",
		"largeur_obstacle": 0.6,
		"exposant_distance": 1.0,
		"humidite_reference": 15.0,
		"vent_direction": {"x": 1.0, "y": 0.0, "z": 0.0},
		"vent_force": 3.0,
		"case_temoin_devant": {"colonne": 1, "ligne": 2},
		"case_temoin_ombre": {"colonne": 8, "ligne": 2},
		"case_temoin_bord": {"colonne": 8, "ligne": 5},
	}

func _init() -> void:
	var v := Verif.new()
	_la_grille_contient_colonnes_fois_lignes_cases(v)
	_le_relief_est_un_profil_de_montagne_pas_un_mur(v)
	_relief_bloquant_normalise_l_altitude_entre_zero_et_un(v)
	_les_obstacles_sont_les_seules_cases_de_relief(v)
	_la_source_est_hors_grille_et_porte_la_propriete_d_emission(v)
	_devant_la_montagne_les_cases_recoivent_beaucoup(v)
	_derriere_la_montagne_l_ombre_est_graduee_jamais_une_coupure(v)
	_sans_relief_les_cases_derriere_recoivent_strictement_plus(v)
	_une_case_de_relief_n_est_jamais_son_propre_obstacle(v)
	_l_humidite_est_ecrasee_a_chaque_appel_jamais_accumulee(v)
	_la_couleur_va_du_jaune_sec_au_bleu_humide(v)
	_le_survol_retrouve_la_case_la_plus_proche(v)
	_la_donnee_reelle_du_disque_construit_bien_trois_reliefs(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_ombre_pluvio.gd pose une grille de cases-objets, un profil de " +
			"montagne a trois cases (sommet + deux epaules) normalise en relief_bloquant " +
			"[0,1], une mer hors grille, et ecrit sur chaque case l'intensite rendue par " +
			"champ_occulte.gd : humide devant, ombre GRADUEE derriere (la plus seche sur " +
			"l'axe, plus humide en s'en ecartant, jamais nulle), aucune ombre sans relief")
		quit(0)

func _grille() -> Array:
	return Banc.construire_grille(_config())

func _humidite(cases: Array, colonne: int, ligne: int) -> float:
	return Banc.humidite_de(Banc.case_a(cases, colonne, ligne), _config())

func _avancer(cases: Array, obstacles: Array) -> void:
	Banc.avancer_humidite(cases, Banc.construire_sources(_config()), obstacles, _config())

func _la_grille_contient_colonnes_fois_lignes_cases(v) -> void:
	var cases := _grille()
	v.v(cases.size() == 60, "10x6 doit donner 60 cases, pas %d" % cases.size())
	for case in cases:
		v.v(case.position.z == 0.0, "position.z doit rester 0.0 partout (l'altitude vit dans proprietes)")
		v.v(case.proprietes.has("humidite"), "chaque case doit porter la propriete d'humidite des la construction")
	var coin: Variant = Banc.case_a(cases, 0, 0)
	v.v(coin != null and coin.id == "case_0_0", "la case (0,0) doit exister et s'appeler case_0_0")
	v.v(Banc.case_a(cases, 99, 99) == null, "une case hors grille doit rendre null, jamais une case voisine")

# Trois cases de relief sur la MEME colonne, dont une seule au sommet : c'est
# cette difference d'altitude qui gradue l'ombre (un mur uniforme donnerait
# une ombre plate).
func _le_relief_est_un_profil_de_montagne_pas_un_mur(v) -> void:
	var config := _config()
	v.v(is_equal_approx(Banc.altitude_pour_case(4, 2, config), 14.0), "la ligne du sommet doit porter altitude_sommet")
	v.v(is_equal_approx(Banc.altitude_pour_case(4, 1, config), 8.0), "une epaule doit porter altitude_epaule")
	v.v(is_equal_approx(Banc.altitude_pour_case(4, 3, config), 8.0), "l'autre epaule aussi")
	v.v(is_equal_approx(Banc.altitude_pour_case(4, 0, config), 2.0), "une ligne hors lignes_relief reste en plaine, meme sur la colonne du relief")
	v.v(is_equal_approx(Banc.altitude_pour_case(7, 2, config), 2.0), "une colonne hors relief reste en plaine, meme sur la ligne du sommet")
	v.v(Banc.altitude_pour_case(4, 2, config) > Banc.altitude_pour_case(4, 1, config),
		"le sommet doit etre strictement plus haut que ses epaules")

func _relief_bloquant_normalise_l_altitude_entre_zero_et_un(v) -> void:
	var config := _config()
	v.v(is_equal_approx(Banc.relief_bloquant_pour_altitude(2.0, config), 0.0), "l'altitude de plancher doit normaliser a 0.0 (transparent)")
	v.v(is_equal_approx(Banc.relief_bloquant_pour_altitude(20.0, config), 1.0), "l'altitude de plafond doit normaliser a 1.0 (blocage total)")
	v.v(is_equal_approx(Banc.relief_bloquant_pour_altitude(11.0, config), 0.5), "le milieu doit normaliser a 0.5")
	v.v(is_equal_approx(Banc.relief_bloquant_pour_altitude(999.0, config), 1.0), "au-dela du plafond : borne a 1.0, jamais plus")
	v.v(is_equal_approx(Banc.relief_bloquant_pour_altitude(-50.0, config), 0.0), "sous le plancher : borne a 0.0, jamais negatif")
	var config_incoherente := _config()
	config_incoherente["altitude_plafond"] = 2.0
	v.v(is_equal_approx(Banc.relief_bloquant_pour_altitude(10.0, config_incoherente), 0.0),
		"plafond <= plancher : rend 0.0, jamais une division par zero")

func _les_obstacles_sont_les_seules_cases_de_relief(v) -> void:
	var obstacles := Banc.obstacles_relief(_grille(), "relief_bloquant")
	v.v(obstacles.size() == 3, "exactement 3 cases de relief doivent servir d'obstacles, pas %d" % obstacles.size())
	for obstacle in obstacles:
		v.v(int(obstacle.position.x) == 4, "toutes les cases de relief doivent etre sur la colonne du relief")
		v.v(float(obstacle.proprietes.relief_bloquant) > 0.0, "un obstacle doit porter une obstruction strictement positive")

func _la_source_est_hors_grille_et_porte_la_propriete_d_emission(v) -> void:
	var sources := Banc.construire_sources(_config())
	v.v(sources.size() == 1, "une seule source (la mer)")
	v.v(sources[0].position.x < 0.0, "la mer doit etre posee HORS de la grille (a gauche de la colonne 0)")
	v.v(is_equal_approx(float(sources[0].proprietes.humidite_emission), 60.0), "la mer doit porter humidite_emission")

# Colonne 0, ligne 2 : pile sur l'axe de la mer, distance 4.0, force 60.0,
# exposant 1.0 -> 15.0 exactement, aucun obstacle possible (rien entre la mer
# et la premiere colonne).
func _devant_la_montagne_les_cases_recoivent_beaucoup(v) -> void:
	var cases := _grille()
	_avancer(cases, Banc.obstacles_relief(cases, "relief_bloquant"))
	v.v(is_equal_approx(_humidite(cases, 0, 2), 15.0), "la case (0,2), a 4.0 de la mer, doit recevoir 60/4 = 15.0, pas %f" % _humidite(cases, 0, 2))
	v.v(_humidite(cases, 0, 2) > _humidite(cases, 3, 2),
		"devant la montagne, l'humidite decroit deja avec la distance a la mer")

func _derriere_la_montagne_l_ombre_est_graduee_jamais_une_coupure(v) -> void:
	var cases := _grille()
	_avancer(cases, Banc.obstacles_relief(cases, "relief_bloquant"))
	var sur_l_axe := _humidite(cases, 8, 2)
	var une_ligne_a_cote := _humidite(cases, 8, 3)
	var au_bord := _humidite(cases, 8, 5)
	v.v(sur_l_axe > 0.0, "DOCTRINE : meme la case la plus a l'ombre garde une humidite strictement positive -- une ombre, jamais une coupure")
	v.v(sur_l_axe < une_ligne_a_cote, "la case sur l'axe mer-sommet doit etre strictement plus seche que celle d'a cote")
	v.v(une_ligne_a_cote < au_bord, "la case d'a cote doit rester plus seche que celle qui sort du cone d'ombre")
	v.v(au_bord > _humidite(cases, 8, 2) * 2.0, "l'ecart entre le bord et l'axe doit etre franc, pas marginal")
	var devant := _humidite(cases, 1, 2)
	v.v(sur_l_axe < devant, "derriere la montagne, on recoit beaucoup moins que devant")

# Le vrai controle de l'ombre : la MEME case, avec et sans obstacles. Tout
# ecart vient de l'occlusion, jamais de la distance (inchangee).
func _sans_relief_les_cases_derriere_recoivent_strictement_plus(v) -> void:
	var avec := _grille()
	_avancer(avec, Banc.obstacles_relief(avec, "relief_bloquant"))
	var sans := _grille()
	_avancer(sans, [])
	for ligne in [1, 2, 3]:
		v.v(_humidite(avec, 8, ligne) < _humidite(sans, 8, ligne),
			"ligne %d, colonne 8 : la meme case doit recevoir strictement moins avec le relief que sans" % ligne)
	v.v(is_equal_approx(_humidite(avec, 8, 5), _humidite(sans, 8, 5)),
		"une case hors du cone d'ombre doit recevoir EXACTEMENT la meme chose avec ou sans relief")
	v.v(is_equal_approx(_humidite(avec, 0, 2), _humidite(sans, 0, 2)),
		"une case DEVANT la montagne ne doit jamais etre affectee par elle")

# Piege reel de la geometrie : la case de relief est elle-meme dans la liste
# des obstacles ; sa projection sur le segment mer->elle-meme vaut exactement
# t=1.0, donc elle est exclue (occlusion.gd, t strictement dans ]0,1[). Si ce
# test rougit un jour, c'est que le bornage de t a bouge.
func _une_case_de_relief_n_est_jamais_son_propre_obstacle(v) -> void:
	var avec := _grille()
	_avancer(avec, Banc.obstacles_relief(avec, "relief_bloquant"))
	var sans := _grille()
	_avancer(sans, [])
	v.v(is_equal_approx(_humidite(avec, 4, 2), _humidite(sans, 4, 2)),
		"la case du sommet doit recevoir la meme humidite avec ou sans obstacles -- elle ne s'occulte pas elle-meme")

func _l_humidite_est_ecrasee_a_chaque_appel_jamais_accumulee(v) -> void:
	var cases := _grille()
	var obstacles := Banc.obstacles_relief(cases, "relief_bloquant")
	_avancer(cases, obstacles)
	var apres_un_tick := _humidite(cases, 6, 2)
	_avancer(cases, obstacles)
	_avancer(cases, obstacles)
	v.v(is_equal_approx(_humidite(cases, 6, 2), apres_un_tick),
		"le champ est une fonction PURE des positions : trois appels doivent rendre exactement la meme valeur, jamais une accumulation")

func _la_couleur_va_du_jaune_sec_au_bleu_humide(v) -> void:
	var sec := Banc.couleur_pour_humidite(0.0, 15.0)
	var humide := Banc.couleur_pour_humidite(15.0, 15.0)
	var sature := Banc.couleur_pour_humidite(999.0, 15.0)
	v.v(sec.r > sec.b, "sec : le jaune doit dominer le bleu")
	v.v(humide.b > humide.r, "humide : le bleu doit dominer le jaune")
	v.v(is_equal_approx(sature.b, humide.b), "au-dela de la reference : borne, jamais une couleur qui continue de deriver")
	v.v(Banc.couleur_pour_humidite(10.0, 0.0).r > Banc.couleur_pour_humidite(10.0, 0.0).b,
		"reference nulle : rend la couleur seche, jamais une division par zero")
	var relief_actif := Banc.couleur_pour_relief(0.667, true)
	var relief_inactif := Banc.couleur_pour_relief(0.667, false)
	v.v(relief_actif != relief_inactif, "le relief doit changer de couleur quand l'occlusion est basculee")

func _le_survol_retrouve_la_case_la_plus_proche(v) -> void:
	var cases := _grille()
	var trouvee: Variant = Banc.case_la_plus_proche(cases, Vector2(3.0, 2.0) * 74.0, 74.0)
	v.v(trouvee != null and trouvee.id == "case_3_2", "le survol au centre exact d'une case doit rendre cette case")
	v.v(Banc.case_la_plus_proche([], Vector2.ZERO, 74.0) == null, "aucune case : rend null, jamais un crash")

# Relit data/banc_ombre_pluvio.json SUR LE DISQUE : la config reelle doit
# produire exactement trois obstacles. Verrou du piege JSON float/int decrit
# en tete de ce fichier.
func _la_donnee_reelle_du_disque_construit_bien_trois_reliefs(v) -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHEMIN_CONFIG))
	v.v(config != null and not config.is_empty(), "data/banc_ombre_pluvio.json doit exister et se parser")
	var cases := Banc.construire_grille(config)
	var obstacles := Banc.obstacles_relief(cases, config.propriete_obstacle)
	v.v(obstacles.size() == 3, "la config REELLE doit produire exactement 3 cases de relief, pas %d" % obstacles.size())
	Banc.avancer_humidite(cases, Banc.construire_sources(config), obstacles, config)
	var sur_l_axe: float = Banc.humidite_de(Banc.case_a(cases, int(config.case_temoin_ombre.colonne), int(config.case_temoin_ombre.ligne)), config)
	var au_bord: float = Banc.humidite_de(Banc.case_a(cases, int(config.case_temoin_bord.colonne), int(config.case_temoin_bord.ligne)), config)
	var devant: float = Banc.humidite_de(Banc.case_a(cases, int(config.case_temoin_devant.colonne), int(config.case_temoin_devant.ligne)), config)
	v.v(devant > au_bord and au_bord > sur_l_axe and sur_l_axe > 0.0,
		"config reelle : temoin devant (%.2f) > temoin bord (%.2f) > temoin ombre (%.2f) > 0.0" % [devant, au_bord, sur_l_axe])
