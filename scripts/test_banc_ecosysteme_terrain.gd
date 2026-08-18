extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_ecosysteme_terrain.gd
#
# Verrouille les fonctions PURES de scripts/banc_ecosysteme_terrain.gd
# (chantier « refuge + extinction + capacite de charge + territoire »,
# audit_ecosysteme_vivant_prealable.md lignes 1/2/3/4). Le banc ne fait que
# CABLER des mecanismes du coeur, tous verrouilles separement
# (test_conditions.gd, test_comptage.gd, test_seuil_etat.gd,
# test_perception.gd, test_proximite.gd, test_consommer.gd, test_depense.gd) :
# aucune de leurs lois n'est retestee ici.
#
# DEUX MOITIES, comme les autres tests de banc :
# - HORS DOMAINE : une config, un catalogue de biomes, une table de comptages,
#   un catalogue de canaux, des profils de saillance et un catalogue de seuils
#   ENTIEREMENT INVENTES (« vlok ») traversent le meme code. Aucun nom de ce
#   banc n'y apparait -- ni « biome », ni « proie », ni « refuge », ni
#   « energie », ni meme « surpeuplement ». Si le banc marchait en nommant une
#   chose du monde, ce bloc rougirait.
# - CHEMIN REEL : data/banc_ecosysteme_terrain.json + data/biomes.json +
#   data/profils_saillance.json + data/comptages.json + data/seuils_etat.json +
#   data/etats.json + data/canaux.json charges depuis le disque, pour verifier
#   la CALIBRATION (foret cachee / desert expose des le depart, capacite du
#   desert franchie par le renfort, predateur mort de faim sous refuge leve) --
#   lecon de banc_maladie, dont le seuil d'origine ne franchissait jamais rien
#   pendant que son test restait VERT.

const Banc = preload("res://scripts/banc_ecosysteme_terrain.gd")
const Monde = preload("res://scripts/monde.gd")
# Appele par le TEST seul (jamais une loi de seuil retestee ici, elle est
# verrouillee par test_seuil_etat.gd) : ces cas verifient ce que le CABLAGE en
# attend -- quelle case bascule, et qu'elle rebascule en sens inverse.
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Verif = preload("res://scripts/verif.gd")

# ---- DOMAINE INVENTE ---------------------------------------------------------

const CONFIG_VLOK := {
	"grille_lignes": 1,
	"grille_colonnes": 4,
	"taille_case": 100.0,
	"portee_appariement": 50.0,

	"nom_humidite": "brume_vlok",
	"nom_temperature": "charge_vlok",
	"nom_biome": "strate_vlok",
	"nom_fraction_refuge": "couvert_vlok",
	"nom_capacite_charge": "plafond_vlok",
	"nom_population_locale": "densite_vlok",
	"nom_biome_local": "strate_sous_vlok",
	"nom_espece": "role_vlok",
	"nom_reserve_energie": "flux_vlok",
	"nom_manque_energie": "creux_vlok",
	"nom_vitesse": "allure_vlok",
	"nom_canal_vue": "oeil_vlok",
	"nom_rayon_territoire": "domaine_vlok",
	"nom_etat_surpeuplement": "trop_vlok",

	"valeur_espece_proie": "brouteur_vlok",
	"valeur_espece_predateur": "traqueur_vlok",
	"regle_proie": "brouteurs_vlok",
	"regle_predateur": "traqueurs_vlok",

	"zone_defaut": "",
	"zones": [
		{ "nom": "dense_vlok", "colonne_min": 0, "colonne_max": 1, "humidite": 0.9, "temperature": 1.0 },
		{ "nom": "nu_vlok", "colonne_min": 2, "colonne_max": 3, "humidite": 0.1, "temperature": 1.0 },
	],

	"seuil_refuge_cachee": 0.5,
	"bonus_refuge_toggle": 0.45,
	"profil_proie_exposee": "vu_vlok",
	"profil_proie_cachee": "tapi_vlok",
	"seuil_perception_proie": 1.5,

	"rayon_territoire_base": 200.0,
	"rayon_echantillon": 250.0,
	"densite_reference": 2.0,
	"rayon_territoire_max": 600.0,
	"angle_vue": 360.0,
	"sensibilite_vue": 1.0,

	"capacite_energie": 50.0,
	"cout_base_proie": -2.0,
	"cout_base_predateur": 3.0,
	"surcout_chasse": 1.0,
	"surcout_surpeuplement": 8.0,
	"taux_predation": 6.0,
	"portee_capture": 60.0,
	"vitesse_predateur": 40.0,

	"seuils_locaux": {
		"trop_vlok": {
			"propriete_continue": "densite_vlok",
			"seuil_propriete": "plafond_vlok",
			"etat": "trop_vlok",
		},
	},

	"proies": [
		{ "id": "brouteur_dense", "position": [0.0, 0.0, 0.0], "energie": 50.0 },
		{ "id": "brouteur_nu", "position": [200.0, 0.0, 0.0], "energie": 50.0 },
	],
	"predateurs": [
		{ "id": "traqueur_nu", "position": [300.0, 0.0, 0.0], "energie": 50.0 },
	],
	"renfort_proies": [
		{ "id": "renfort_vlok_1", "position": [300.0, 0.0, 0.0], "energie": 50.0 },
		{ "id": "renfort_vlok_2", "position": [200.0, 0.0, 0.0], "energie": 50.0 },
	],
	"periode_trace_s": 1.0,
}

# Deux strates, DISJOINTES (brume >= 0.5 contre brume < 0.5) : la premiere est
# tres couverte et peu nourrissante, la seconde nue et large.
const BIOMES_VLOK := [
	{
		"id": "dense_vlok",
		"conditions": [ { "propriete": "brume_vlok", "operateur": ">=", "seuil": 0.5 } ],
		"resultat": { "strate_vlok": "dense_vlok", "couvert_vlok": 0.8, "plafond_vlok": 20.0 },
	},
	{
		"id": "nu_vlok",
		"conditions": [ { "propriete": "brume_vlok", "operateur": "<", "seuil": 0.5 } ],
		"resultat": { "strate_vlok": "nu_vlok", "couvert_vlok": 0.1, "plafond_vlok": 2.0 },
	},
]

const COMPTAGES_VLOK := {
	"brouteurs_vlok": { "propriete": "role_vlok", "mode": "egale", "valeur_reference": "brouteur_vlok" },
	"traqueurs_vlok": { "propriete": "role_vlok", "mode": "egale", "valeur_reference": "traqueur_vlok" },
}

const CANAUX_VLOK := { "oeil_vlok": { "geometrie": "cone_oriente", "proprietes_captees": [] } }

const PROFILS_VLOK := {
	"vu_vlok": { "saillance_intrinseque": 6.0, "portee_saillance": 600.0 },
	"tapi_vlok": { "saillance_intrinseque": 0.8, "portee_saillance": 600.0 },
}

func _init() -> void:
	var v := Verif.new()

	_grille_et_zones_posent_les_conditions(v)
	_le_refuge_reecrit_le_profil_de_saillance(v)
	_le_predateur_ne_retient_que_ce_qui_passe_le_seuil(v)
	_comptage_par_biome(v)
	_surpeuplement_pose_et_retire(v)
	_le_territoire_grandit_quand_les_proies_se_rarefient(v)
	_le_territoire_ne_boucle_pas(v)
	_division_par_zero_geree(v)
	_un_seul_ecrivain_de_surcout_et_plafond_au_cablage(v)
	_la_mort_est_un_gate_de_cablage(v)

	_reel_foret_cachee_desert_expose(v)
	_reel_le_renfort_franchit_la_capacite_du_desert(v)
	_reel_le_predateur_meurt_de_faim_sous_refuge_leve(v)
	_reel_le_predateur_survit_sans_refuge(v)
	_reel_une_proie_chassee_meurt_reellement(v)

	if v.echecs() > 0:
		print("ECHEC: %d probleme(s)" % v.echecs())
		quit(1)
	else:
		print("OK: banc_ecosysteme_terrain -- grille et zones posent les conditions, le refuge reecrit " +
			"profil_saillance (et lui seul), le predateur ne retient que ce qui passe le seuil de saillance, " +
			"comptage par biome exact, surpeuplement pose PUIS retire quand la population redescend, " +
			"territoire qui grandit a proies rares, territoire idempotent (rayon d'echantillon fixe, jamais " +
			"relu depuis la portee courante), division par zero rendant le rayon MAX et jamais INF, " +
			"un seul ecrivain de surcout_action et plafond au cablage, mort par gate de cablage ; " +
			"un domaine entierement invente traverse le meme code, et sur le chemin reel une proie de foret " +
			"est cachee, une proie de desert exposee, le renfort franchit la capacite du desert, " +
			"le predateur meurt de faim sous refuge leve, survit sans lui, et une proie chassee meurt " +
			"reellement (l'ordre chasse-apres-depense est verrouille)")
		quit(0)

# ---- DOMAINE INVENTE ---------------------------------------------------------

func _grille_et_zones_posent_les_conditions(v) -> void:
	var cases: Array = Banc.construire_grille(CONFIG_VLOK)
	v.v(cases.size() == 4, "4 colonnes x 1 ligne doivent donner 4 cases")
	v.v(String(cases[0].id) == "case_0_0" and String(cases[3].id) == "case_3_0",
		"les ids doivent suivre colonne_ligne, ordre ligne-majeur")
	var a_plat := true
	var en_unites_monde := true
	for case in cases:
		if case.position.z != 0.0:
			a_plat = false
	if not is_equal_approx(cases[1].position.x, 100.0):
		en_unites_monde = false
	v.v(a_plat, "VERTICALITE : position.z doit rester 0.0 sur toutes les cases")
	v.v(en_unites_monde, "les positions doivent etre en unites MONDE (colonne * taille_case), pas en unites de grille")
	v.v(is_equal_approx(float(cases[0].proprietes.brume_vlok), 0.9)
			and is_equal_approx(float(cases[3].proprietes.brume_vlok), 0.1),
		"chaque case doit porter les conditions de SA bande de colonnes")
	v.v(not cases[0].proprietes.has("strate_vlok"),
		"construire_grille ne doit JAMAIS poser le biome -- c'est conditions.gd qui le pose")

	var humidite_avant: float = float(cases[0].proprietes.brume_vlok)
	Banc.evaluer_biomes(cases, BIOMES_VLOK, CONFIG_VLOK.nom_biome)
	v.v(String(cases[0].proprietes.get("strate_vlok", "")) == "dense_vlok"
			and String(cases[3].proprietes.get("strate_vlok", "")) == "nu_vlok",
		"conditions.gd doit poser la strate de chaque bande")
	v.v(is_equal_approx(float(cases[0].proprietes.couvert_vlok), 0.8)
			and is_equal_approx(float(cases[0].proprietes.plafond_vlok), 20.0),
		"le 'resultat' du catalogue doit poser AUSSI le couvert et le plafond, zero ligne de GDScript")
	v.v(is_equal_approx(float(cases[0].proprietes.brume_vlok), humidite_avant),
		"LE CLIMAT NE DERIVE JAMAIS : conditions.gd ne doit jamais toucher la condition qui l'a declenche")

	# REVERSIBILITE : la condition tombe, les trois cles du resultat partent
	# ensemble -- c'est retirer_si_faux, et lui seul.
	cases[0].proprietes["brume_vlok"] = 0.1
	Banc.evaluer_biomes(cases, BIOMES_VLOK, CONFIG_VLOK.nom_biome)
	v.v(String(cases[0].proprietes.get("strate_vlok", "")) == "nu_vlok"
			and is_equal_approx(float(cases[0].proprietes.couvert_vlok), 0.1),
		"REVERSIBILITE : couvert et plafond doivent suivre le biome, jamais rester figes")

func _le_refuge_reecrit_le_profil_de_saillance(v) -> void:
	var cases: Array = _cases_vlok()
	var animaux: Array = Banc.construire_animaux(CONFIG_VLOK, false)
	Banc.poser_biome_local(animaux, cases, CONFIG_VLOK)

	var dense := _par_id(animaux, "brouteur_dense")
	var nu := _par_id(animaux, "brouteur_nu")
	var traqueur := _par_id(animaux, "traqueur_nu")
	v.v(String(dense.proprietes.get("strate_sous_vlok", "")) == "dense_vlok"
			and String(nu.proprietes.get("strate_sous_vlok", "")) == "nu_vlok",
		"chaque animal doit recopier en cle plate le biome de la case sous lui")

	var changements: Array = Banc.poser_profils_proies(animaux, cases, 0.0, CONFIG_VLOK)
	v.v(String(dense.proprietes.get("profil_saillance", "")) == "tapi_vlok",
		"couvert 0.8 >= seuil 0.5 : la proie doit porter le profil CACHE")
	v.v(String(nu.proprietes.get("profil_saillance", "")) == "vu_vlok",
		"couvert 0.1 < seuil 0.5 : la proie doit porter le profil EXPOSE")
	v.v(not traqueur.proprietes.has("profil_saillance"),
		"un predateur ne doit JAMAIS recevoir de profil de proie -- il percoit, il n'est pas percu")
	v.v(changements.size() == 2, "le premier passage doit rendre les DEUX proies comme changements")

	var seconds: Array = Banc.poser_profils_proies(animaux, cases, 0.0, CONFIG_VLOK)
	v.v(seconds.is_empty(),
		"sans changement de refuge, un second passage ne doit rendre AUCUN changement (sinon la console cracherait a chaque image)")

	# Le bonus du toggle : la strate nue (0.1) passe a 0.55, au-dessus du seuil.
	var leves: Array = Banc.poser_profils_proies(animaux, cases, 0.45, CONFIG_VLOK)
	v.v(String(nu.proprietes.get("profil_saillance", "")) == "tapi_vlok",
		"le bonus de refuge doit faire basculer la proie exposee vers le profil cache")
	v.v(leves.size() == 1, "seule la proie qui bascule doit figurer dans les changements")
	v.v(is_equal_approx(float(cases[3].proprietes.couvert_vlok), 0.1),
		"LE REFUGE DU BIOME N'EST JAMAIS MUTE : le bonus est recompose a neuf a chaque lecture")
	v.v(is_equal_approx(Banc.refuge_effectif(cases[3], 0.95, CONFIG_VLOK), 1.0),
		"le refuge effectif doit etre borne a 1.0 (c'est une fraction)")
	v.v(is_equal_approx(Banc.refuge_effectif(null, 0.5, CONFIG_VLOK), 0.0),
		"une chose hors grille n'a aucun couvert, jamais un refuge invente")

func _le_predateur_ne_retient_que_ce_qui_passe_le_seuil(v) -> void:
	var cases: Array = _cases_vlok()
	var animaux: Array = Banc.construire_animaux(CONFIG_VLOK, false)
	Banc.poser_biome_local(animaux, cases, CONFIG_VLOK)
	Banc.poser_profils_proies(animaux, cases, 0.0, CONFIG_VLOK)

	var traqueur := _par_id(animaux, "traqueur_nu")
	Banc.poser_territoire(traqueur, 600.0, CONFIG_VLOK)
	var monde = _monde_de(animaux, CONFIG_VLOK)

	var percues: Array = Banc.proies_percues(traqueur, monde, CANAUX_VLOK, PROFILS_VLOK, CONFIG_VLOK)
	v.v(percues.size() == 1, "le predateur ne doit retenir QUE la proie exposee (2 proies dans sa portee, 1 retenue)")
	v.v(String(percues[0].chose.id) == "brouteur_nu", "la proie retenue doit etre l'exposee, jamais la cachee")

	# LA PROIE CACHEE EST BIEN PERCUE ET EVALUEE -- ce n'est pas proximite.gd
	# qui l'exclut, c'est le seuil de decision du cablage. On le prouve en
	# abaissant le seuil : elle reapparait, sans qu'aucune position ne bouge.
	var config_seuil_bas: Dictionary = CONFIG_VLOK.duplicate(true)
	config_seuil_bas["seuil_perception_proie"] = 0.0
	var toutes: Array = Banc.proies_percues(traqueur, monde, CANAUX_VLOK, PROFILS_VLOK, config_seuil_bas)
	v.v(toutes.size() == 2,
		"seuil a 0.0 : les DEUX proies doivent revenir -- la cachee etait percue et evaluee, seul le seuil la rejetait")
	v.v(String(toutes[0].chose.id) == "brouteur_nu",
		"ORDRE DETERMINISTE : la plus saillante d'abord, jamais l'ordre de la requete spatiale")

	# Une proie cachee reste sous le seuil A TOUTE DISTANCE, y compris collee
	# au predateur (facteur de distance 1.0, saillance plafond 0.8 < 1.5).
	var dense := _par_id(animaux, "brouteur_dense")
	dense.position = traqueur.position
	var monde_colle = _monde_de(animaux, CONFIG_VLOK)
	var collee: Array = Banc.proies_percues(traqueur, monde_colle, CANAUX_VLOK, PROFILS_VLOK, CONFIG_VLOK)
	var trouvee := false
	for entree in collee:
		if String(entree.chose.id) == "brouteur_dense":
			trouvee = true
	v.v(not trouvee, "une proie cachee doit rester sous le seuil MEME collee au predateur -- 0.8 x 1.0 < 1.5")

func _comptage_par_biome(v) -> void:
	var cases: Array = _cases_vlok()
	var animaux: Array = Banc.construire_animaux(CONFIG_VLOK, true)
	Banc.poser_biome_local(animaux, cases, CONFIG_VLOK)
	var populations: Dictionary = Banc.populations_par_biome(animaux, cases, COMPTAGES_VLOK, CONFIG_VLOK)

	v.v(populations.size() == 2, "il doit y avoir exactement une entree par biome PRESENT sur la grille")
	# dense : brouteur_dense seul (colonnes 0-1). nu : brouteur_nu +
	# renfort_vlok_2 (x=200) + traqueur_nu + renfort_vlok_1 (x=300).
	v.v(int(populations["dense_vlok"].proies) == 1 and int(populations["dense_vlok"].predateurs) == 0
			and int(populations["dense_vlok"].total) == 1,
		"le biome dense doit compter 1 proie et 0 predateur")
	v.v(int(populations["nu_vlok"].proies) == 3 and int(populations["nu_vlok"].predateurs) == 1
			and int(populations["nu_vlok"].total) == 4,
		"le biome nu doit compter 3 proies et 1 predateur -- le total compte les DEUX especes")

	Banc.poser_population_locale(cases, populations, CONFIG_VLOK)
	v.v(is_equal_approx(float(cases[0].proprietes.densite_vlok), 1.0)
			and is_equal_approx(float(cases[3].proprietes.densite_vlok), 4.0),
		"la population du biome doit etre recopiee en cle PLATE sur chaque case de ce biome")

func _surpeuplement_pose_et_retire(v) -> void:
	var cases: Array = _cases_vlok()
	var animaux: Array = Banc.construire_animaux(CONFIG_VLOK, true)
	Banc.poser_biome_local(animaux, cases, CONFIG_VLOK)
	Banc.poser_population_locale(cases, Banc.populations_par_biome(animaux, cases, COMPTAGES_VLOK, CONFIG_VLOK), CONFIG_VLOK)

	var seuils: Dictionary = CONFIG_VLOK.seuils_locaux
	var avant: Dictionary = Banc.instantane_surpeuplement(cases, CONFIG_VLOK)
	SeuilEtat.avancer(cases, seuils)
	var changements: Array = Banc.changements_surpeuplement(avant, cases, CONFIG_VLOK)
	v.v(cases[3].proprietes.etats_actifs.has("trop_vlok"),
		"population 4 > plafond 2 : la case du biome nu doit passer en surpeuplement")
	v.v(not cases[0].proprietes.etats_actifs.has("trop_vlok"),
		"population 1 <= plafond 20 : la case du biome dense ne doit RIEN porter")
	v.v(changements.size() == 2, "les deux cases du biome nu doivent apparaitre comme changements")
	var surpeuples: Dictionary = Banc.biomes_surpeuples(cases, CONFIG_VLOK)
	v.v(surpeuples.has("nu_vlok") and not surpeuples.has("dense_vlok"),
		"biomes_surpeuples doit lire etats_actifs sur les cases, jamais une variable tenue a cote")

	# REVERSIBILITE : deux morts, la population repasse sous le plafond,
	# seuil_etat.gd retire l'etat de lui-meme, sans une ligne de cablage.
	var restants: Array = []
	for animal in animaux:
		if String(animal.id).begins_with("renfort_"):
			continue
		restants.append(animal)
	Banc.poser_biome_local(restants, cases, CONFIG_VLOK)
	Banc.poser_population_locale(cases, Banc.populations_par_biome(restants, cases, COMPTAGES_VLOK, CONFIG_VLOK), CONFIG_VLOK)
	SeuilEtat.avancer(cases, seuils)
	v.v(not cases[3].proprietes.etats_actifs.has("trop_vlok"),
		"REVERSIBILITE : population 2 <= plafond 2 (comparaison STRICTE), le surpeuplement doit se retirer tout seul")

	# Une case SANS biome ne porte pas de plafond : repli INF, jamais de
	# surpeuplement -- chemin mort silencieux, jamais une alarme.
	var orpheline: Dictionary = {"id": "orpheline", "position": Vector3.ZERO, "proprietes": {"etats_actifs": [], "densite_vlok": 9999.0}}
	SeuilEtat.avancer([orpheline], seuils)
	v.v(not orpheline.proprietes.etats_actifs.has("trop_vlok"),
		"une case sans capacite_charge doit replier sur INF et ne jamais poser de surpeuplement")

func _le_territoire_grandit_quand_les_proies_se_rarefient(v) -> void:
	v.v(is_equal_approx(Banc.rayon_territoire(1.0, CONFIG_VLOK), 200.0),
		"a densite 1.0 (autant de proies que la reference), le territoire doit valoir exactement rayon_territoire_base")
	v.v(Banc.rayon_territoire(0.5, CONFIG_VLOK) > Banc.rayon_territoire(1.0, CONFIG_VLOK),
		"MOINS de proies doit donner un territoire PLUS GRAND")
	v.v(Banc.rayon_territoire(2.0, CONFIG_VLOK) < Banc.rayon_territoire(1.0, CONFIG_VLOK),
		"PLUS de proies doit donner un territoire plus petit")
	v.v(is_equal_approx(Banc.rayon_territoire(0.5, CONFIG_VLOK), 400.0),
		"densite 0.5 -> 200 / 0.5 = 400")

	# Chemin complet : la densite est mesuree dans le monde, pas donnee.
	var animaux: Array = Banc.construire_animaux(CONFIG_VLOK, false)
	var traqueur := _par_id(animaux, "traqueur_nu")
	var deux := Banc.densite_proies(traqueur, _monde_de(animaux, CONFIG_VLOK), COMPTAGES_VLOK, CONFIG_VLOK)
	v.v(is_equal_approx(deux, 0.5),
		"une seule proie dans le rayon d'echantillon (250) sur une reference de 2.0 doit donner 0.5")
	var rapproches: Array = [animaux[0], animaux[1], traqueur]
	rapproches[0].position = Vector3(250.0, 0.0, 0.0)
	var quatre := Banc.densite_proies(traqueur, _monde_de(rapproches, CONFIG_VLOK), COMPTAGES_VLOK, CONFIG_VLOK)
	v.v(quatre > deux and Banc.rayon_territoire(quatre, CONFIG_VLOK) < Banc.rayon_territoire(deux, CONFIG_VLOK),
		"une proie de plus a portee doit monter la densite ET retrecir le territoire")

func _le_territoire_ne_boucle_pas(v) -> void:
	var animaux: Array = Banc.construire_animaux(CONFIG_VLOK, false)
	var traqueur := _par_id(animaux, "traqueur_nu")
	var monde = _monde_de(animaux, CONFIG_VLOK)

	var densite := Banc.densite_proies(traqueur, monde, COMPTAGES_VLOK, CONFIG_VLOK)
	var rayon := Banc.rayon_territoire(densite, CONFIG_VLOK)
	Banc.poser_territoire(traqueur, rayon, CONFIG_VLOK)
	v.v(is_equal_approx(float(traqueur.proprietes.canaux_config.oeil_vlok.portee), rayon),
		"poser_territoire doit ecrire la portee du canal -- premier ecrivain dynamique de canaux_config")
	v.v(is_equal_approx(float(traqueur.proprietes.domaine_vlok), rayon),
		"poser_territoire doit AUSSI ecrire la cle plate, pour que le label et le cercle relisent sans recalculer")

	# LE PIEGE : si le rayon d'echantillon suivait le territoire, ecraser la
	# portee courante changerait le resultat. Il est FIXE : elle ne change rien.
	traqueur.proprietes.canaux_config.oeil_vlok["portee"] = 5000.0
	var densite_apres := Banc.densite_proies(traqueur, monde, COMPTAGES_VLOK, CONFIG_VLOK)
	v.v(is_equal_approx(densite_apres, densite),
		"LE RAYON D'ECHANTILLON EST FIXE : ecraser la portee courante du canal ne doit RIEN changer a la densite mesuree")
	v.v(is_equal_approx(Banc.rayon_territoire(densite_apres, CONFIG_VLOK), rayon),
		"le territoire doit etre recalcule A NEUF depuis rayon_territoire_base, jamais depuis sa valeur precedente")

	# Trois passages sur un monde immobile : exactement le meme nombre, jamais
	# une derive (patron du verrou d'idempotence de banc_bonheur.gd).
	var stable := true
	for _i in range(3):
		var d := Banc.densite_proies(traqueur, monde, COMPTAGES_VLOK, CONFIG_VLOK)
		Banc.poser_territoire(traqueur, Banc.rayon_territoire(d, CONFIG_VLOK), CONFIG_VLOK)
		if not is_equal_approx(float(traqueur.proprietes.domaine_vlok), rayon):
			stable = false
	v.v(stable, "IDEMPOTENCE : trois passages sur un monde immobile doivent rendre exactement le meme rayon")

func _division_par_zero_geree(v) -> void:
	var rayon := Banc.rayon_territoire(0.0, CONFIG_VLOK)
	v.v(rayon != INF, "densite nulle ne doit JAMAIS rendre INF")
	v.v(is_equal_approx(rayon, float(CONFIG_VLOK.rayon_territoire_max)),
		"densite nulle doit rendre le rayon MAXIMUM, borne par le cablage")

	# Chemin complet : un predateur seul au monde, aucune proie a portee.
	var seul: Dictionary = Banc.construire_predateur({"id": "orphelin", "position": [0.0, 0.0, 0.0], "energie": 50.0}, CONFIG_VLOK)
	var densite := Banc.densite_proies(seul, _monde_de([seul], CONFIG_VLOK), COMPTAGES_VLOK, CONFIG_VLOK)
	v.v(is_equal_approx(densite, 0.0), "un predateur sans aucune proie a portee doit mesurer une densite nulle")
	Banc.poser_territoire(seul, Banc.rayon_territoire(densite, CONFIG_VLOK), CONFIG_VLOK)
	v.v(is_equal_approx(float(seul.proprietes.domaine_vlok), float(CONFIG_VLOK.rayon_territoire_max)),
		"un predateur sans proie doit couvrir le territoire maximum, jamais un rayon infini")

func _un_seul_ecrivain_de_surcout_et_plafond_au_cablage(v) -> void:
	var animal: Dictionary = Banc.construire_predateur({"id": "t", "position": [0.0, 0.0, 0.0], "energie": 50.0}, CONFIG_VLOK)
	var canal: Dictionary = animal.proprietes.reserves.flux_vlok

	var rien := Banc.poser_surcout_action(animal, false, false, CONFIG_VLOK)
	v.v(is_equal_approx(float(canal.surcout_action), 0.0) and is_equal_approx(float(rien.total), 0.0),
		"ni chasse ni surpeuplement : le surcout doit valoir exactement 0.0")
	var chasse := Banc.poser_surcout_action(animal, true, false, CONFIG_VLOK)
	v.v(is_equal_approx(float(canal.surcout_action), 1.0) and is_equal_approx(float(chasse.chasse), 1.0),
		"en chasse seule : surcout = surcout_chasse")
	var deux := Banc.poser_surcout_action(animal, true, true, CONFIG_VLOK)
	v.v(is_equal_approx(float(canal.surcout_action), 9.0),
		"UNE SEULE ECRITURE : les deux contributions doivent se SOMMER (1.0 + 8.0), jamais s'ecraser")
	v.v(is_equal_approx(float(deux.chasse) + float(deux.surpeuplement), float(deux.total)),
		"la decomposition rendue doit sommer exactement au total ecrit -- l'affichage relit, il ne recalcule pas")
	# IDEMPOTENCE : reecrire n'accumule jamais.
	Banc.poser_surcout_action(animal, true, true, CONFIG_VLOK)
	v.v(is_equal_approx(float(canal.surcout_action), 9.0),
		"le surcout est ECRIT en entier chaque tick, jamais incremente sur le precedent")

	# Le plafond est du CABLAGE : rien dans le coeur ne borne le HAUT.
	canal["reserve"] = 999.0
	Banc.plafonner_energie([animal], CONFIG_VLOK)
	v.v(is_equal_approx(float(canal.reserve), 50.0),
		"plafonner_energie doit ecreter a la capacite -- depense.gd ne borne que le BAS")
	canal["reserve"] = 12.0
	v.v(is_equal_approx(Banc.poser_manque_energie(animal, CONFIG_VLOK), 38.0)
			and is_equal_approx(float(animal.proprietes.creux_vlok), 38.0),
		"le miroir plat doit valoir capacite - reserve, recalcule a neuf")
	canal["reserve"] = 60.0
	Banc.poser_manque_energie(animal, CONFIG_VLOK)
	v.v(is_equal_approx(float(animal.proprietes.creux_vlok), 0.0),
		"le miroir doit etre borne a 0.0 par le bas, jamais un manque negatif")

func _la_mort_est_un_gate_de_cablage(v) -> void:
	var vif: Dictionary = Banc.construire_proie({"id": "vif", "position": [0.0, 0.0, 0.0], "energie": 1.0}, CONFIG_VLOK)
	var vide: Dictionary = Banc.construire_proie({"id": "vide", "position": [0.0, 0.0, 0.0], "energie": 0.0}, CONFIG_VLOK)
	v.v(Banc.vivant(vif, CONFIG_VLOK) and not Banc.vivant(vide, CONFIG_VLOK),
		"vivant() doit lire la reserve, jamais un etat")
	v.v(Banc.survivants([vif, vide], CONFIG_VLOK).size() == 1, "survivants() ne doit garder que ce qui vit")
	var morts: Array = Banc.morts_de([vif, vide], CONFIG_VLOK)
	v.v(morts.size() == 1 and String(morts[0].id) == "vide" and String(morts[0].espece) == "brouteur_vlok",
		"morts_de() doit nommer le mort ET son espece, pour la trace")
	v.v(not vide.proprietes.etats_actifs.has("mort"),
		"AUCUN etat de mort ne doit etre pose -- la mort est un gate de cablage, patron banc_faim_thermo.gd")

	# La chasse est CONSERVATIVE : le predateur gagne exactement ce que la
	# proie perd, jamais la quantite demandee.
	var proie: Dictionary = Banc.construire_proie({"id": "p", "position": [0.0, 0.0, 0.0], "energie": 2.0}, CONFIG_VLOK)
	var traqueur: Dictionary = Banc.construire_predateur({"id": "t", "position": [0.0, 0.0, 0.0], "energie": 10.0}, CONFIG_VLOK)
	var mange := Banc.chasser(traqueur, proie, CONFIG_VLOK, 1.0)
	v.v(is_equal_approx(mange, 2.0), "la quantite transferee doit etre bornee au restant de la proie (2.0), jamais 6.0")
	v.v(is_equal_approx(float(proie.proprietes.reserves.flux_vlok.reserve), 0.0)
			and is_equal_approx(float(traqueur.proprietes.reserves.flux_vlok.reserve), 12.0),
		"CONSERVATION : le predateur doit gagner exactement ce que la proie a perdu")
	v.v(not Banc.vivant(proie, CONFIG_VLOK), "une proie videe par la chasse doit compter comme morte")

# ---- CHEMIN REEL -------------------------------------------------------------

func _reel_foret_cachee_desert_expose(v) -> void:
	var reel := _reel()
	v.v(not reel.config.is_empty() and not reel.biomes.is_empty(),
		"data/banc_ecosysteme_terrain.json et data/biomes.json doivent charger")
	var cases: Array = reel.cases
	var animaux: Array = reel.animaux
	v.v(cases.size() == 64, "la grille reelle doit faire 8x8 = 64 cases")

	Banc.evaluer_biomes(cases, reel.biomes, String(reel.config.nom_biome))
	Banc.poser_biome_local(animaux, cases, reel.config)
	Banc.poser_profils_proies(animaux, cases, 0.0, reel.config)

	var foret := _par_id(animaux, "proie_foret_1")
	var desert := _par_id(animaux, "proie_desert_1")
	var prairie := _par_id(animaux, "proie_prairie_1")
	v.v(String(foret.proprietes.get(String(reel.config.nom_biome_local), "")) == "foret",
		"CALIBRATION : la proie de la bande gauche doit etre sur une FORET (humidite 0.70 / temperature 18)")
	v.v(String(prairie.proprietes.get(String(reel.config.nom_biome_local), "")) == "prairie",
		"CALIBRATION : la bande centrale doit declencher PRAIRIE (humidite 0.35), l'entree ajoutee par ce chantier")
	v.v(String(desert.proprietes.get(String(reel.config.nom_biome_local), "")) == "desert",
		"CALIBRATION : la bande droite doit declencher DESERT (humidite 0.05 / temperature 35)")
	v.v(String(foret.proprietes.get("profil_saillance", "")) == String(reel.config.profil_proie_cachee),
		"LIGNE 1, chemin reel : une proie en FORET (refuge 0.6 >= seuil 0.5) doit porter le profil CACHE")
	v.v(String(desert.proprietes.get("profil_saillance", "")) == String(reel.config.profil_proie_exposee),
		"LIGNE 1, chemin reel : une proie en DESERT (refuge 0.05 < seuil 0.5) doit porter le profil EXPOSE")
	v.v(String(prairie.proprietes.get("profil_saillance", "")) == String(reel.config.profil_proie_exposee),
		"LIGNE 1, chemin reel : une proie en PRAIRIE (refuge 0.2) doit etre exposee")

	# Le predateur du desert voit sa proie ; celui qu'on deplace en foret ne
	# voit rien, a distance IDENTIQUE -- c'est le refuge, jamais la geometrie.
	var monde = _monde_de(animaux, reel.config)
	var traqueur := _par_id(animaux, "predateur_3")
	Banc.poser_territoire(traqueur, float(reel.config.rayon_territoire_base), reel.config)
	var percues: Array = Banc.proies_percues(traqueur, monde, reel.canaux, reel.profils, reel.config)
	v.v(percues.size() >= 1, "CALIBRATION : le predateur du desert doit percevoir au moins une proie des le depart")

	var distance_desert: float = traqueur.position.distance_to(desert.position)
	traqueur.position = foret.position + Vector3(distance_desert, 0.0, 0.0)
	var monde_foret = _monde_de(animaux, reel.config)
	var en_foret: Array = Banc.proies_percues(traqueur, monde_foret, reel.canaux, reel.profils, reel.config)
	var voit_la_cachee := false
	for entree in en_foret:
		if String(entree.chose.id) == "proie_foret_1":
			voit_la_cachee = true
	v.v(not voit_la_cachee,
		"LIGNE 1, chemin reel : a distance IDENTIQUE, la proie de foret ne doit pas etre retenue -- seul le refuge les separe")

func _reel_le_renfort_franchit_la_capacite_du_desert(v) -> void:
	var reel := _reel(true)
	var cases: Array = reel.cases
	var animaux: Array = reel.animaux
	Banc.evaluer_biomes(cases, reel.biomes, String(reel.config.nom_biome))
	Banc.poser_biome_local(animaux, cases, reel.config)
	var populations: Dictionary = Banc.populations_par_biome(animaux, cases, reel.comptages, reel.config)

	v.v(int(populations["desert"].total) == 11,
		"CALIBRATION : le renfort doit porter la population du desert a 11 (2 proies + 8 renforts + 1 predateur)")
	Banc.poser_population_locale(cases, populations, reel.config)
	SeuilEtat.avancer(cases, reel.config.seuils_locaux)
	var surpeuples: Dictionary = Banc.biomes_surpeuples(cases, reel.config)
	v.v(surpeuples.has("desert"),
		"LIGNE 3, chemin reel : 11 > capacite_charge 8, le desert doit passer en surpeuplement")
	v.v(not surpeuples.has("foret") and not surpeuples.has("prairie"),
		"CALIBRATION : foret (80) et prairie (50) ne doivent JAMAIS surpeupler avec ces effectifs")

	# Le surcout de surpeuplement depasse le broutage : la reserve d'une proie
	# du desert DESCEND, c'est ce qui borne la population.
	var proie := _par_id(animaux, "proie_desert_1")
	Banc.poser_surcout_action(proie, false, true, reel.config)
	var canal: Dictionary = proie.proprietes.reserves[String(reel.config.nom_reserve_energie)]
	v.v(float(canal.cout_base) + float(canal.surcout_action) > 0.0,
		"CALIBRATION : sous surpeuplement, le surcout doit DEPASSER le broutage (cout_base negatif), sinon la capacite ne borne rien")
	Banc.poser_surcout_action(proie, false, false, reel.config)
	v.v(float(canal.cout_base) + float(canal.surcout_action) < 0.0,
		"CALIBRATION : hors surpeuplement, une proie doit se REFAIRE toute seule (cout_base negatif, jachere de banc_fertilite.gd)")

func _reel_le_predateur_meurt_de_faim_sous_refuge_leve(v) -> void:
	var reel := _reel()
	var etat := _simuler(reel, true, 25.0, 0.1)
	v.v(etat.morts_predateurs == 3,
		"LIGNE 2, chemin reel : refuge leve, les TROIS predateurs doivent mourir de faim (energie 60 / cout_base 4 -> 15 s)")
	v.v(etat.morts_proies == 0,
		"refuge leve : aucune proie ne doit mourir -- elles broutent et personne ne les mange")
	v.v(etat.percues_totales == 0,
		"refuge leve : aucun predateur ne doit retenir la moindre proie, a aucun tick")

func _reel_le_predateur_survit_sans_refuge(v) -> void:
	var reel := _reel()
	var etat := _simuler(reel, false, 25.0, 0.1)
	v.v(etat.morts_predateurs == 0,
		"CONTRE-EPREUVE : sans refuge leve, aucun predateur ne doit mourir sur la meme duree -- c'est le refuge qui tue, pas le temps")
	v.v(etat.percues_totales > 0, "sans refuge leve, les predateurs doivent retenir des proies")

# VERROU DU RESULTAT NEGATIF trouve EN LANCANT LA SCENE, pas au test (voir
# banc_ecosysteme_terrain.gd:avancer, « LA CHASSE EST LE DERNIER MOUVEMENT
# D'ENERGIE DU TICK ») : quand la chasse passait AVANT depense.gd, le broutage
# de la proie la remplissait dans le meme tick apres l'avoir videe -- elle se
# stabilisait a taux_broutage * delta et NE MOURAIT JAMAIS, tous tests verts.
# Ce cas est le seul qui rougirait si l'ordre etait reinverse.
func _reel_une_proie_chassee_meurt_reellement(v) -> void:
	var reel := _reel()
	var etat := _simuler(reel, false, 30.0, 0.1)
	v.v(etat.morts_proies > 0,
		"une proie chassee doit REELLEMENT mourir -- si la chasse repassait avant la depense, son broutage la remplirait apres l'avoir videe et elle se stabiliserait juste au-dessus de zero pour toujours")
	v.v(etat.morts_predateurs == 0,
		"sur cette duree, aucun predateur ne doit encore mourir -- il vient de manger")

# Rejoue le tick complet du banc comme le fait _process : avancer(), puis
# retrait des morts et reconstruction du Monde. Rend le bilan.
func _simuler(reel: Dictionary, refuge_leve: bool, duree: float, pas: float) -> Dictionary:
	var config: Dictionary = reel.config
	var cases: Array = reel.cases
	var animaux: Array = reel.animaux
	var monde = _monde_de(animaux, config)
	var bonus := Banc.bonus_refuge(refuge_leve, config)
	var morts_proies := 0
	var morts_predateurs := 0
	var percues_totales := 0
	var t := 0.0
	while t < duree:
		t += pas
		var resultat: Dictionary = Banc.avancer(
			cases, animaux, monde, config, reel.biomes, reel.comptages,
			reel.seuils, reel.etats, reel.canaux, reel.profils, bonus, pas,
		)
		for etat in resultat.predateurs:
			percues_totales += int(etat.percues)
		for mort in resultat.morts:
			if String(mort.espece) == String(config.valeur_espece_predateur):
				morts_predateurs += 1
			else:
				morts_proies += 1
		if not resultat.morts.is_empty():
			animaux = resultat.survivants
			monde = _monde_de(animaux, config)
	return {
		"morts_proies": morts_proies,
		"morts_predateurs": morts_predateurs,
		"percues_totales": percues_totales,
		"animaux": animaux,
	}

# ---- Outils de test ----------------------------------------------------------

func _cases_vlok() -> Array:
	var cases: Array = Banc.construire_grille(CONFIG_VLOK)
	Banc.evaluer_biomes(cases, BIOMES_VLOK, CONFIG_VLOK.nom_biome)
	return cases

func _monde_de(animaux: Array, config: Dictionary):
	var monde = Monde.new()
	for animal in animaux:
		monde.ajouter(animal, String(animal.proprietes.get(String(config.nom_espece), "")), animal.position)
	return monde

func _reel(avec_renfort: bool = false) -> Dictionary:
	var config: Dictionary = _charger("res://data/banc_ecosysteme_terrain.json")
	return {
		"config": config,
		"biomes": _charger("res://data/biomes.json").get("biomes", []),
		"comptages": _charger("res://data/comptages.json"),
		"seuils": _charger("res://data/seuils_etat.json"),
		"etats": _charger("res://data/etats.json"),
		"canaux": _charger("res://data/canaux.json"),
		"profils": _charger("res://data/profils_saillance.json"),
		"cases": Banc.construire_grille(config),
		"animaux": Banc.construire_animaux(config, avec_renfort),
	}

func _par_id(animaux: Array, id: String) -> Dictionary:
	for animal in animaux:
		if String(animal.id) == id:
			return animal
	return {}

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
