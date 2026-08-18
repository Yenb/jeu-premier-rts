extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_biomes.gd
#
# Verrouille les fonctions PURES de scripts/banc_biomes.gd (chantier "biomes
# -- conditions multiples -> type de terrain"). Le banc ne fait que CABLER
# scripts/conditions.gd (mecanisme du coeur, verrouille separement par
# test_conditions.gd) : rien de la loi d'evaluation n'est reteste ici, seuls
# la grille, le climat, la detection de changement et l'affichage le sont.
#
# DEUX MOITIES, comme les autres tests de banc :
# - HORS DOMAINE : une config et un catalogue ENTIEREMENT INVENTES (grille
#   3x2, proprietes "_vlok", "climat" au lieu de "biome") traversent le meme
#   code -- si le banc marchait en nommant un biome, ce bloc rougirait.
# - CHEMIN REEL : data/banc_biomes.json + data/biomes.json charges depuis le
#   disque, pour verifier la CALIBRATION (les cinq rendus visibles au repos)
#   et la REVERSIBILITE sur une case reelle.

const Banc = preload("res://scripts/banc_biomes.gd")
const Verif = preload("res://scripts/verif.gd")

const CONFIG_VLOK := {
	"grille_lignes": 2,
	"grille_colonnes": 3,
	"humidite_min": 0.0,
	"humidite_max": 1.0,
	"temperature_min": 10.0,
	"temperature_max": 20.0,
	"pas_temperature": 5.0,
	"pas_humidite": 0.1,
	"nom_humidite": "flux_vlok",
	"nom_temperature": "charge_vlok",
	"nom_biome": "climat_vlok",
	"couleurs_biome": { "haut_vlok": [1.0, 0.0, 0.0] },
	"couleur_aucun_biome": [0.1, 0.2, 0.3],
}

const CATALOGUE_VLOK := [
	{
		"id": "haut_vlok",
		"conditions": [ { "propriete": "charge_vlok", "operateur": ">=", "seuil": 15.0 } ],
		"resultat": { "climat_vlok": "haut_vlok" },
	},
]

func _init() -> void:
	var v := Verif.new()
	_grille_posee_avec_ses_bases(v)
	_gradients_aux_bornes_et_gardes_degenerees(v)
	_appliquer_climat_est_idempotent_et_borne(v)
	_evaluer_biomes_ne_rend_que_les_changements(v)
	_compter_par_biome_compte_aussi_les_cases_sans_biome(v)
	_couleur_et_compteur_lisent_la_donnee(v)
	_chemin_reel_les_cinq_rendus_visibles_au_repos(v)
	_chemin_reel_reversibilite_sur_une_case(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_biomes -- grille et bases posees une fois, gradients aux bornes, " +
			"appliquer_climat idempotent et humidite bornee, evaluer_biomes ne rend que les changements, " +
			"comptage des cases sans biome, palette et compteur lus en donnee, " +
			"un domaine invente traverse le meme code, et sur le chemin reel les cinq rendus " +
			"sont visibles au repos et un biome se retire puis revient")
		quit(0)

func _grille_posee_avec_ses_bases(v) -> void:
	var cases: Array = Banc.construire_grille(CONFIG_VLOK)
	v.v(cases.size() == 6, "3 colonnes x 2 lignes doivent donner 6 cases")
	v.v(cases[0].id == "case_0_0" and cases[5].id == "case_2_1", "les ids doivent suivre colonne_ligne, ordre ligne-majeur")
	var toutes_a_plat := true
	for case in cases:
		if case.position.z != 0.0:
			toutes_a_plat = false
	v.v(toutes_a_plat, "VERTICALITE : position.z doit rester 0.0 sur toutes les cases (l'altitude n'est pas dans position)")
	v.v(cases[0].proprietes.has("humidite_base") and cases[0].proprietes.has("temperature_base"),
		"chaque case doit porter ses valeurs de BASE des la construction")
	v.v(not cases[0].proprietes.has("flux_vlok") and not cases[0].proprietes.has("charge_vlok"),
		"construire_grille ne doit JAMAIS poser les proprietes effectives -- c'est appliquer_climat qui les pose")

func _gradients_aux_bornes_et_gardes_degenerees(v) -> void:
	v.v(is_equal_approx(Banc.humidite_pour_colonne(0, 3, CONFIG_VLOK), 0.0), "colonne 0 doit valoir humidite_min")
	v.v(is_equal_approx(Banc.humidite_pour_colonne(2, 3, CONFIG_VLOK), 1.0), "derniere colonne doit valoir humidite_max")
	v.v(is_equal_approx(Banc.temperature_pour_ligne(0, 2, CONFIG_VLOK), 10.0), "ligne 0 doit valoir temperature_min")
	v.v(is_equal_approx(Banc.temperature_pour_ligne(1, 2, CONFIG_VLOK), 20.0), "derniere ligne doit valoir temperature_max")
	v.v(is_equal_approx(Banc.humidite_pour_colonne(0, 1, CONFIG_VLOK), 0.0),
		"garde defensive : une seule colonne doit rendre humidite_min, jamais diviser par zero")
	v.v(is_equal_approx(Banc.temperature_pour_ligne(0, 1, CONFIG_VLOK), 10.0),
		"garde defensive : une seule ligne doit rendre temperature_min, jamais diviser par zero")

func _appliquer_climat_est_idempotent_et_borne(v) -> void:
	var cases: Array = Banc.construire_grille(CONFIG_VLOK)
	Banc.appliquer_climat(cases, 5.0, 0.0, CONFIG_VLOK)
	var apres_un: float = cases[0].proprietes.charge_vlok
	Banc.appliquer_climat(cases, 5.0, 0.0, CONFIG_VLOK)
	var apres_deux: float = cases[0].proprietes.charge_vlok
	v.v(is_equal_approx(apres_un, 15.0), "temperature effective = base (10) + decalage (5)")
	v.v(is_equal_approx(apres_un, apres_deux),
		"IDEMPOTENCE : deux appels au meme decalage doivent donner exactement le meme etat, jamais une derive cumulative")
	# Retour au decalage nul : la base n'a jamais ete mutee, donc l'etat
	# d'origine doit revenir exactement.
	Banc.appliquer_climat(cases, 0.0, 0.0, CONFIG_VLOK)
	v.v(is_equal_approx(cases[0].proprietes.charge_vlok, 10.0),
		"revenir a un decalage nul doit restituer exactement la valeur de base")
	# Bornes de l'humidite : un ratio ne sort jamais de [0,1], la temperature
	# n'a aucun plafond.
	Banc.appliquer_climat(cases, 1000.0, 5.0, CONFIG_VLOK)
	v.v(is_equal_approx(cases[5].proprietes.flux_vlok, 1.0), "humidite effective doit etre bornee a 1.0 par le haut")
	v.v(cases[0].proprietes.charge_vlok > 900.0, "la temperature ne doit JAMAIS etre bornee (des degres n'ont pas de plafond)")
	Banc.appliquer_climat(cases, 0.0, -5.0, CONFIG_VLOK)
	v.v(is_equal_approx(cases[0].proprietes.flux_vlok, 0.0), "humidite effective doit etre bornee a 0.0 par le bas")

func _evaluer_biomes_ne_rend_que_les_changements(v) -> void:
	var cases: Array = Banc.construire_grille(CONFIG_VLOK)
	Banc.appliquer_climat(cases, 0.0, 0.0, CONFIG_VLOK)
	var premiers: Array = Banc.evaluer_biomes(cases, CATALOGUE_VLOK, "climat_vlok")
	v.v(premiers.size() == 3,
		"au premier passage, les 3 cases de la ligne chaude (20>=15) doivent apparaitre comme changements")
	v.v(String(premiers[0].avant) == "" and String(premiers[0].apres) == "haut_vlok",
		"un changement doit porter l'etat AVANT et APRES, la chaine vide valant 'aucun biome'")
	var seconds: Array = Banc.evaluer_biomes(cases, CATALOGUE_VLOK, "climat_vlok")
	v.v(seconds.is_empty(),
		"sans changement de climat, un second passage ne doit rendre AUCUN changement (sinon la console cracherait a chaque frame)")
	# Refroidir sous le seuil : le biome doit etre RETIRE, donc redevenir un
	# changement.
	Banc.appliquer_climat(cases, -10.0, 0.0, CONFIG_VLOK)
	var retraits: Array = Banc.evaluer_biomes(cases, CATALOGUE_VLOK, "climat_vlok")
	v.v(retraits.size() == 3 and String(retraits[0].apres) == "",
		"REVERSIBILITE : refroidir sous le seuil doit RETIRER le biome et le signaler comme changement")

func _compter_par_biome_compte_aussi_les_cases_sans_biome(v) -> void:
	var cases: Array = Banc.construire_grille(CONFIG_VLOK)
	Banc.appliquer_climat(cases, 0.0, 0.0, CONFIG_VLOK)
	Banc.evaluer_biomes(cases, CATALOGUE_VLOK, "climat_vlok")
	var comptes: Dictionary = Banc.compter_par_biome(cases, "climat_vlok")
	var total := 0
	for cle in comptes:
		total += int(comptes[cle])
	v.v(total == cases.size(), "le comptage doit couvrir TOUTES les cases, aucune perdue en route")
	v.v(int(comptes.get("haut_vlok", 0)) == 3 and int(comptes.get("", 0)) == 3,
		"les cases sans biome doivent etre comptees sous la cle '' (chaine vide), jamais oubliees ni rangees sous un nom invente")

func _couleur_et_compteur_lisent_la_donnee(v) -> void:
	v.v(Banc.couleur_pour_biome("haut_vlok", CONFIG_VLOK) == Color(1.0, 0.0, 0.0),
		"la couleur doit venir de la palette en DONNEE, jamais d'un nom de biome en dur dans le code")
	v.v(Banc.couleur_pour_biome("", CONFIG_VLOK) == Color(0.1, 0.2, 0.3),
		"une case sans biome doit prendre couleur_aucun_biome")
	v.v(Banc.couleur_pour_biome("biome_absent_de_la_palette", CONFIG_VLOK) == Color(0.1, 0.2, 0.3),
		"un biome sans couleur declaree doit retomber sur couleur_aucun_biome, jamais planter -- un banc doit toujours laisser observer")
	# Ordre deterministe : alphabetique, "aucun" toujours en dernier, quel que
	# soit l'ordre d'insertion dans le Dictionary.
	var texte: String = Banc.texte_compteur({ "zeta_vlok": 2, "": 5, "alpha_vlok": 1 })
	v.v(texte.find("alpha_vlok 1") < texte.find("zeta_vlok 2"),
		"le compteur doit trier les biomes alphabetiquement, jamais suivre l'ordre d'iteration d'un Dictionary")
	v.v(texte.find("aucun 5") > texte.find("zeta_vlok 2"),
		"les cases sans biome doivent etre affichees EN DERNIER, sous un libelle explicite")

func _chemin_reel_les_cinq_rendus_visibles_au_repos(v) -> void:
	var config: Dictionary = _charger("res://data/banc_biomes.json")
	var catalogue: Array = _charger("res://data/biomes.json").get("biomes", [])
	v.v(not config.is_empty() and not catalogue.is_empty(), "data/banc_biomes.json et data/biomes.json doivent charger")
	var cases: Array = Banc.construire_grille(config)
	v.v(cases.size() == 36, "la grille reelle doit faire 6x6 = 36 cases")
	Banc.appliquer_climat(cases, 0.0, 0.0, config)
	Banc.evaluer_biomes(cases, catalogue, config.nom_biome)
	var comptes: Dictionary = Banc.compter_par_biome(cases, config.nom_biome)
	# CALIBRATION du gradient : le banc doit montrer les cinq rendus possibles
	# des le demarrage, sans qu'on ait besoin de cliquer.
	for attendu in ["desert", "foret", "toundra", "marais"]:
		v.v(int(comptes.get(attendu, 0)) > 0,
			"CALIBRATION : le biome '%s' doit etre visible des le demarrage, sans aucun clic" % attendu)
	v.v(int(comptes.get("", 0)) > 0,
		"CALIBRATION : au moins une case sans aucun biome doit etre visible -- les conditions ne pavent pas tout l'espace, et ca doit se voir")

func _chemin_reel_reversibilite_sur_une_case(v) -> void:
	var config: Dictionary = _charger("res://data/banc_biomes.json")
	var catalogue: Array = _charger("res://data/biomes.json").get("biomes", [])
	var nom_biome: String = config.nom_biome
	var cases: Array = Banc.construire_grille(config)

	Banc.appliquer_climat(cases, 0.0, 0.0, config)
	Banc.evaluer_biomes(cases, catalogue, nom_biome)
	var temoin: Dictionary = _par_id(cases, "case_3_2")
	var au_repos: String = String(temoin.proprietes.get(nom_biome, ""))
	v.v(au_repos == "foret", "pre-condition du test : la case temoin doit etre une foret au repos (h 0.59 / t 14)")

	# Grand froid : la foret doit ceder la place a la toundra.
	Banc.appliquer_climat(cases, -20.0, 0.0, config)
	Banc.evaluer_biomes(cases, catalogue, nom_biome)
	v.v(String(temoin.proprietes.get(nom_biome, "")) == "toundra",
		"REVERSIBILITE, chemin reel : refroidie de 20 degres, la foret doit devenir une toundra")

	# Retour au climat de depart : la foret doit revenir, a l'identique.
	Banc.appliquer_climat(cases, 0.0, 0.0, config)
	Banc.evaluer_biomes(cases, catalogue, nom_biome)
	v.v(String(temoin.proprietes.get(nom_biome, "")) == au_repos,
		"REVERSIBILITE, chemin reel : revenue a son climat de depart, la case doit retrouver EXACTEMENT son biome d'origine")

	# Assechement : le marais doit pouvoir devenir un desert -- la seconde
	# moitie de ce que le banc doit montrer, inatteignable par la seule
	# temperature (voir banc_biomes.gd, en-tete "HUMIDITE AUX FLECHES").
	var marais: Dictionary = _par_id(cases, "case_5_5")
	v.v(String(marais.proprietes.get(nom_biome, "")) == "marais", "pre-condition du test : la case temoin doit etre un marais (h 0.95 / t 35)")
	Banc.appliquer_climat(cases, 0.0, -0.9, config)
	Banc.evaluer_biomes(cases, catalogue, nom_biome)
	v.v(String(marais.proprietes.get(nom_biome, "")) == "desert",
		"REVERSIBILITE, chemin reel : asseche, un marais chaud doit devenir un desert")

func _par_id(cases: Array, id: String) -> Dictionary:
	for case in cases:
		if case.id == id:
			return case
	return {}

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
