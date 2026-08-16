extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_stress_thermo_vivant.gd
#
# Verrouille les fonctions PURES de scripts/banc_stress_thermo_vivant.gd
# (chantier « stress plante + thermoregulation vivant », audit prealable
# audit_ecosysteme_vivant_prealable.md lignes 8 et 9). Le banc ne fait que
# CABLER six mecanismes du coeur deja verrouilles separement (temperature.gd/
# charge.gd/depense.gd/seuil_etat.gd/etat_effectif.gd/flux.gd, TOUS INCHANGES
# par ce chantier) : aucune de leurs lois n'est retestee ici. Ce qui est teste,
# c'est ce que le CABLAGE ajoute -- la somme ponderee recalculee a neuf, les
# quatre bascules asymetriques, les seuils LUS PAR OBJET, le gate de mort, et la
# calibration reelle.
#
# DEUX MOITIES, comme les autres tests de banc :
# - HORS DOMAINE : une config, un catalogue de seuils LOCAL et un catalogue
#   d'etats ENTIEREMENT INVENTES (reserve "seve_zork", croissance "pousse_zork",
#   stress "tension_zork", miroirs "gel_zork"/"cuisson_zork"/"noyade_zork"/
#   "soif_zork", etats "tendu_zork"/"fini_zork"/"raide_zork"/"grille_zork",
#   degres "zork" ou le confort d'une mousse est a 100) traversent le meme code.
#   Si le banc nommait "stress_plante", "froid_ressenti", "temp_cible",
#   "seuil_stress_mortel" ou "stress_leger" en dur, ce bloc rougirait.
# - CHEMIN REEL : data/banc_stress_thermo_vivant.json + data/etats.json relus SUR
#   LE DISQUE, pour verifier la CALIBRATION (les trois paliers, les deux
#   arrosages, qui meurt de quoi) et l'ACCORD entre les noms de miroirs du banc
#   et les `propriete_continue` du catalogue local -- accord dont la rupture
#   serait SILENCIEUSE (un miroir ecrit sous un nom que personne ne compare :
#   aucun etat ne se poserait plus jamais, sans une seule alarme).
#
# LE TEST CONDUIT LE VRAI TICK (Banc.avancer, la fonction statique qui porte
# TOUT le pas et son ordre) -- jamais une copie de cet ordre recopiee ici, qui
# aurait derive du banc en silence.

const Banc = preload("res://scripts/banc_stress_thermo_vivant.gd")
const Charge = preload("res://scripts/charge.gd")
const Depense = preload("res://scripts/depense.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Temperature = preload("res://scripts/temperature.gd")
const Verif = preload("res://scripts/verif.gd")

# Domaine invente de bout en bout. Le confort d'une mousse est a 100 degres
# "zork", celui d'une bete a 150 : rien ici ne ressemble a une plante ni a un
# animal.
const CONFIG_ZORK := {
	"terrain_largeur": 200.0,
	"terrain_hauteur": 100.0,
	"temperature": {"exposant": 1.0},
	"paliers": [
		{"nom": "doux_zork", "ambiante": 100.0, "couleur_fond": [0.0, 0.0, 0.0]},
		{"nom": "givre_zork", "ambiante": 60.0, "couleur_fond": [0.0, 0.0, 0.0]},
		{"nom": "four_zork", "ambiante": 180.0, "couleur_fond": [0.0, 0.0, 0.0]},
	],
	"zones": [
		{"id": "antre_zork", "position": [0.0, 0.0, 0.0], "rayon": 10.0,
			"temperature": 400.0, "force": 0.5, "couleur": [1.0, 0.0, 0.0]},
	],
	"source_eau": {"id": "puits_zork", "position": [50.0, 0.0, 0.0], "poids": 1.0},
	"canal_humidite_defaut": {
		"charge": 4.0, "seuil": 4.0, "portee_charge": 500.0,
		"taux_decroissance": 2.0, "poser": {},
	},
	"nom_canal_humidite": "moiteur_zork",
	"nom_reserve_energie": "seve_zork",
	"nom_reserve_maturite": "ampleur_zork",
	"nom_croissance": "pousse_zork",
	"nom_vitesse": "derive_zork",
	"nom_stress": "tension_zork",
	"nom_froid_ressenti": "gel_zork",
	"nom_chaud_ressenti": "cuisson_zork",
	"nom_exces_eau": "noyade_zork",
	"nom_secheresse": "soif_zork",
	"nom_poids_stress": "poids_tension_zork",
	"nom_temp_cible": "confort_zork",
	"nom_seuil_chaud": "bascule_chaude_zork",
	"nom_cout_par_degre_froid": "prix_gel_zork",
	"nom_cout_par_degre_chaud": "prix_cuisson_zork",
	"nom_seuil_humide": "trop_humide_zork",
	"nom_seuil_sec": "trop_sec_zork",
	"nom_capacite_energie": "cuve_zork",
	"nom_cout_base": "entretien_zork",
	"nom_recoit_eau": "boit_zork",
	"nom_couleur": "teinte_zork",
	"nom_seuil_stress_mortel": "rupture_zork",
	"propriete_source_croissance": "donne_pousse_zork",
	"propriete_receptrice_croissance": "recoit_pousse_zork",
	"portee_flux_croissance": 1.0,
	"maturite_max": 1.0,
	"etat_stress_leger": "tendu_zork",
	"etat_mort_stress": "fini_zork",
	"seuils_locaux": {
		"tension_legere": {"propriete_continue": "tension_zork",
			"seuil_propriete": "palier_tendu_zork", "etat": "tendu_zork"},
		"tension_mortelle": {"propriete_continue": "tension_zork",
			"seuil_propriete": "rupture_zork", "etat": "fini_zork"},
		"gel_leger": {"propriete_continue": "gel_zork",
			"seuil_propriete": "palier_gel_zork", "etat": "raide_zork"},
		"cuisson_grave": {"propriete_continue": "cuisson_zork",
			"seuil_propriete": "palier_cuisson_zork", "etat": "grille_zork"},
	},
	"vivants": [
		{
			"id": "mousse_zork",
			"position": [50.0, 0.0, 0.0],
			"confort_zork": 100.0,
			"bascule_chaude_zork": 140.0,
			"prix_gel_zork": 0.01,
			"prix_cuisson_zork": 0.03,
			"cuve_zork": 50.0,
			"entretien_zork": 1.0,
			"palier_gel_zork": 5.0,
			"palier_cuisson_zork": 5.0,
			"pousse_zork": 0.10,
			"boit_zork": true,
			"trop_sec_zork": 0.60,
			"trop_humide_zork": 0.90,
			"poids_tension_zork": {
				"gel_zork": 0.10, "cuisson_zork": 0.02,
				"noyade_zork": 2.00, "soif_zork": 1.00,
			},
			"palier_tendu_zork": 0.50,
			"rupture_zork": 1.50,
		},
		{
			"id": "bete_zork",
			"position": [50.0, 20.0, 0.0],
			"confort_zork": 150.0,
			"bascule_chaude_zork": 160.0,
			"prix_gel_zork": 0.02,
			"prix_cuisson_zork": 0.05,
			"cuve_zork": 80.0,
			"entretien_zork": 2.0,
			"palier_gel_zork": 20.0,
			"palier_cuisson_zork": 10.0,
			"derive_zork": 9.0,
			"teinte_zork": [1.0, 1.0, 1.0],
		},
	],
	"couleur_mort": [0.1, 0.1, 0.1],
	"couleur_stress_bas": [0.0, 1.0, 0.0],
	"couleur_stress_moyen": [1.0, 1.0, 0.0],
	"couleur_stress_haut": [1.0, 0.0, 0.0],
}

const ETATS_ZORK := {
	"tendu_zork": {"effets": [{"propriete": "pousse_zork", "mode": "moduler", "facteur": 0.5}]},
	"fini_zork": {"effets": [
		{"propriete": "pousse_zork", "mode": "ecraser", "valeur": 0.0},
		{"propriete": "derive_zork", "mode": "ecraser", "valeur": 0.0},
	]},
	"raide_zork": {"effets": []},
	"grille_zork": {"effets": []},
}

func _init() -> void:
	var v := Verif.new()
	# Hors domaine.
	_vivants_poses_sans_type_ni_temperature(v)
	_chaque_vivant_a_sa_propre_temp_cible(v)
	_les_deux_miroirs_thermiques_ne_sont_jamais_symetriques(v)
	_le_surcout_thermo_est_lu_sur_le_vivant(v)
	_l_animal_depense_plus_dans_le_froid(v)
	_le_stress_monte_avec_le_froid(v)
	_le_stress_monte_avec_la_chaleur(v)
	_exces_eau_et_secheresse_contribuent_et_ne_sont_pas_un_abs(v)
	_le_recalcul_est_a_neuf(v)
	_escalier_stress_leger_puis_mort_stress(v)
	_le_gate_de_mort_est_definitif(v)
	_un_vivant_sans_poids_de_stress_traverse_sans_rien_recevoir(v)
	_la_croissance_est_le_consommateur_reel_des_deux_etats(v)
	_les_seuils_thermiques_sont_lus_par_objet(v)
	_paliers_arrosage_et_plafond_d_humidite(v)
	# Chemin reel.
	_chemin_reel_les_noms_de_miroirs_sont_ceux_du_catalogue_local(v)
	_chemin_reel_les_deux_etats_neufs_sont_conformes(v)
	_chemin_reel_geometrie_et_palier_de_depart(v)
	_chemin_reel_la_tropicale_meurt_de_froid(v)
	_chemin_reel_l_arctique_meurt_de_chaud(v)
	_chemin_reel_l_assechement_stresse_la_tropicale_seule(v)

	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_stress_thermo_vivant -- stress = somme ponderee RECALCULEE A NEUF (jamais +=), " +
			"montant avec le froid pour la tropicale et avec la chaleur pour l'arctique, " +
			"exces d'eau et secheresse contribuant chacun par SON propre seuil et SON propre poids " +
			"(jamais un abs()), escalier stress_leger puis mort_stress pose par seuil_etat.gd sur des " +
			"seuils LUS PAR OBJET, mort rendue definitive par le gate de cablage, chaque vivant portant " +
			"SA temp_cible et SES couts par degre, l'animal depensant plus d'energie dans le froid, " +
			"la croissance effective donnant un effet reel aux deux etats, " +
			"un domaine entierement invente traversant le meme code, " +
			"et sur le chemin reel les trois paliers rendant exactement la calibration annoncee")
		quit(0)

# ---- Hors domaine ----

func _vivants_poses_sans_type_ni_temperature(v) -> void:
	var vivants: Array = Banc.construire_vivants(CONFIG_ZORK)
	v.v(vivants.size() == 2, "les deux vivants declares doivent etre construits")
	var mousse: Dictionary = vivants[0]
	var bete: Dictionary = vivants[1]

	v.v(mousse.position == Vector3(50.0, 0.0, 0.0), "le vivant doit partir de sa position declaree")
	v.v(mousse.position.z == 0.0, "VERTICALITE : position.z doit rester 0.0 (Vector3 partout, meme a plat)")
	v.v(not mousse.proprietes.has("temperature") and not bete.proprietes.has("temperature"),
		"AUCUNE TEMPERATURE DE CORPS : aucun vivant ne doit porter 'temperature' -- ce banc n'appelle " +
		"jamais temperature.gd:avancer, les deux miroirs lisent la temperature LOCALE")
	v.v(mousse.proprietes.get("etats_actifs", null) is Array and mousse.proprietes.etats_actifs.is_empty(),
		"etats_actifs doit partir vide")

	# Les proprietes de declaration sont posees PLATES, sous LEUR nom.
	v.v(is_equal_approx(float(mousse.proprietes.confort_zork), 100.0),
		"temp_cible doit vivre SUR L'ENTITE, sous le nom donne en donnee, jamais dans une config globale")
	v.v(is_equal_approx(float(mousse.proprietes.palier_tendu_zork), 0.50)
		and is_equal_approx(float(mousse.proprietes.rupture_zork), 1.50),
		"les seuils lus PAR OBJET par le catalogue local doivent etre poses en cles plates sur le vivant")

	v.v(mousse.proprietes.reserves.has("seve_zork"),
		"le canal de reserve doit porter le nom donne en DONNEE, jamais 'energie' en dur")
	v.v(is_equal_approx(float(mousse.proprietes.reserves.seve_zork.reserve), 50.0),
		"la reserve doit partir a la capacite declaree")
	v.v(is_equal_approx(float(mousse.proprietes.reserves.seve_zork.cout_base), 1.0),
		"le cout de base doit etre pose comme cout_base a la construction")
	v.v(is_equal_approx(float(mousse.proprietes.reserves.seve_zork.surcout_action), 0.0),
		"surcout_action doit partir a 0.0")

	# Ce qui distingue les deux vivants n'est QU'UN JEU DE PROPRIETES -- aucune
	# categorie n'est codee nulle part.
	v.v(mousse.proprietes.has("etats") and mousse.proprietes.etats.has("moiteur_zork"),
		"un vivant qui boit doit recevoir son canal d'humidite")
	v.v(not bete.proprietes.has("etats"),
		"un vivant qui ne boit pas ne doit recevoir AUCUN canal d'humidite -- charge.gd l'ignorera")
	v.v(mousse.proprietes.reserves.has("ampleur_zork") and mousse.proprietes.get("recoit_pousse_zork", false),
		"un vivant qui pousse doit recevoir sa reserve de maturite et le marqueur receptrice de flux.gd")
	v.v(not bete.proprietes.reserves.has("ampleur_zork"),
		"un vivant qui ne pousse pas ne doit recevoir AUCUNE reserve de maturite")

	# ALIASING : deux vivants ne doivent jamais partager un sous-dictionnaire de
	# la donnee du disque (charge.gd muterait le meme canal deux fois par tick).
	mousse.proprietes.etats.moiteur_zork["charge"] = 99.0
	v.v(is_equal_approx(float(CONFIG_ZORK.canal_humidite_defaut.charge), 4.0),
		"ALIASING : le canal d'humidite doit etre DUPLIQUE, jamais partage avec la donnee du disque")
	mousse.proprietes.poids_tension_zork["gel_zork"] = 42.0
	v.v(is_equal_approx(float(CONFIG_ZORK.vivants[0].poids_tension_zork.gel_zork), 0.10),
		"ALIASING : les poids de stress doivent etre DUPLIQUES, jamais partages avec la donnee du disque")

func _chaque_vivant_a_sa_propre_temp_cible(v) -> void:
	var vivants: Array = Banc.construire_vivants(CONFIG_ZORK)
	var mousse: Dictionary = vivants[0]
	var bete: Dictionary = vivants[1]
	v.v(not is_equal_approx(float(mousse.proprietes.confort_zork), float(bete.proprietes.confort_zork)),
		"les deux vivants doivent porter deux cibles thermiques DIFFERENTES")
	# LE MEME monde, au MEME instant, a la MEME position thermique : deux
	# ressentis differents. C'est toute la ligne 9 de l'audit.
	Banc.poser_couts_thermiques(mousse, 120.0, CONFIG_ZORK)
	Banc.poser_couts_thermiques(bete, 120.0, CONFIG_ZORK)
	v.v(is_equal_approx(float(mousse.proprietes.gel_zork), 0.0),
		"a 120 degres, le vivant dont le confort est a 100 ne doit ressentir AUCUN froid")
	v.v(is_equal_approx(float(bete.proprietes.gel_zork), 30.0),
		"a 120 degres, le vivant dont le confort est a 150 doit ressentir exactement 30 de froid")

func _les_deux_miroirs_thermiques_ne_sont_jamais_symetriques(v) -> void:
	v.v(is_equal_approx(Banc.froid_ressenti(90.0, 100.0), 10.0), "10 degres sous le confort = 10 de froid")
	v.v(is_equal_approx(Banc.froid_ressenti(110.0, 100.0), 0.0),
		"au-dessus du confort il ne fait pas « moins froid que zero », il ne fait plus froid du tout")
	v.v(is_equal_approx(Banc.chaud_ressenti(150.0, 140.0), 10.0), "10 degres au-dessus de la bascule = 10 de chaud")
	v.v(is_equal_approx(Banc.chaud_ressenti(130.0, 140.0), 0.0),
		"BANDE NEUTRE : entre le confort et la bascule chaude, rien ne se ressent")

	var mousse: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[0]
	Banc.poser_couts_thermiques(mousse, 120.0, CONFIG_ZORK)
	v.v(is_equal_approx(float(mousse.proprietes.gel_zork), 0.0)
		and is_equal_approx(float(mousse.proprietes.cuisson_zork), 0.0),
		"les deux miroirs ne doivent JAMAIS etre non nuls en meme temps (bascule chaude >= confort)")

	# JAMAIS UN abs() : le MEME ecart de 10 degres, d'un cote puis de l'autre,
	# doit couter DEUX nombres differents -- c'est ce qu'un abs() rendrait
	# impossible.
	var froid: Dictionary = Banc.poser_couts_thermiques(mousse, 90.0, CONFIG_ZORK)
	var chaud: Dictionary = Banc.poser_couts_thermiques(mousse, 150.0, CONFIG_ZORK)
	v.v(is_equal_approx(float(froid.froid), 10.0) and is_equal_approx(float(chaud.chaud), 10.0),
		"les deux ecarts mesures doivent bien valoir 10 chacun")
	v.v(is_equal_approx(float(froid.thermo), 0.10) and is_equal_approx(float(chaud.thermo), 0.30),
		"JAMAIS UN abs() : le meme ecart de 10 doit couter 0.10 au froid et 0.30 au chaud, " +
		"deux couts par degre DIFFERENTS")

func _le_surcout_thermo_est_lu_sur_le_vivant(v) -> void:
	var vivants: Array = Banc.construire_vivants(CONFIG_ZORK)
	var mousse: Dictionary = vivants[0]
	var bete: Dictionary = vivants[1]
	var d_mousse: Dictionary = Banc.poser_couts_thermiques(mousse, 90.0, CONFIG_ZORK)
	var d_bete: Dictionary = Banc.poser_couts_thermiques(bete, 90.0, CONFIG_ZORK)
	v.v(is_equal_approx(float(d_mousse.thermo), 0.10),
		"mousse a 90 : 10 de froid x 0.01 = 0.10")
	v.v(is_equal_approx(float(d_bete.thermo), 1.20),
		"bete a 90 : 60 de froid x 0.02 = 1.20 -- cible ET cout par degre lus SUR L'ENTITE")
	v.v(is_equal_approx(float(mousse.proprietes.reserves.seve_zork.surcout_action), 0.10)
		and is_equal_approx(float(bete.proprietes.reserves.seve_zork.surcout_action), 1.20),
		"UN SEUL ECRIVAIN : le surcout rendu doit etre EXACTEMENT ce qui a ete ecrit dans le canal")
	# IDEMPOTENCE : rappeler la fonction au meme etat REECRIT la meme valeur,
	# jamais une accumulation.
	Banc.poser_couts_thermiques(mousse, 90.0, CONFIG_ZORK)
	v.v(is_equal_approx(float(mousse.proprietes.reserves.seve_zork.surcout_action), 0.10),
		"IDEMPOTENCE : deux appels au meme etat doivent reecrire la meme valeur, jamais s'additionner")

func _l_animal_depense_plus_dans_le_froid(v) -> void:
	# Deux betes IDENTIQUES, deux paliers d'ambiante differents, le meme delta.
	var au_doux: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[1]
	var au_givre: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[1]
	Banc.poser_couts_thermiques(au_doux, Banc.ambiante(CONFIG_ZORK, 0), CONFIG_ZORK)
	Banc.poser_couts_thermiques(au_givre, Banc.ambiante(CONFIG_ZORK, 1), CONFIG_ZORK)
	v.v(is_equal_approx(float(au_doux.proprietes.reserves.seve_zork.surcout_action), 1.00),
		"palier doux (100) : la bete ressent 50 de froid, donc 50 x 0.02 = 1.00")
	v.v(is_equal_approx(float(au_givre.proprietes.reserves.seve_zork.surcout_action), 1.80),
		"palier givre (60) : la bete ressent 90 de froid, donc 90 x 0.02 = 1.80")
	Depense.avancer([au_doux], 1.0)
	Depense.avancer([au_givre], 1.0)
	v.v(float(au_givre.proprietes.reserves.seve_zork.reserve)
		< float(au_doux.proprietes.reserves.seve_zork.reserve),
		"L'ANIMAL DEPENSE PLUS DANS LE FROID : a cout de base egal, la reserve doit descendre plus vite au givre")
	v.v(is_equal_approx(float(au_doux.proprietes.reserves.seve_zork.reserve), 80.0 - 3.0)
		and is_equal_approx(float(au_givre.proprietes.reserves.seve_zork.reserve), 80.0 - 3.8),
		"la consommation doit valoir exactement (cout_base + surcout) x delta, jamais un nombre a cote")

func _le_stress_monte_avec_le_froid(v) -> void:
	var mousse: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[0]
	# Humidite pleine : la contribution de l'eau est constante entre les deux
	# mesures, seul le froid change.
	var au_confort: Dictionary = _mesurer(mousse, 100.0)
	var au_froid: Dictionary = _mesurer(mousse, 90.0)
	var au_grand_froid: Dictionary = _mesurer(mousse, 80.0)
	v.v(is_equal_approx(float(au_confort.stress), 0.20),
		"au confort, le stress ne vient que de l'eau : noyade 0.10 x 2.00 = 0.20")
	v.v(is_equal_approx(float(au_froid.stress), 1.20),
		"LE STRESS MONTE AVEC LE FROID : 10 de gel x 0.10 = 1.00, plus les 0.20 de l'eau")
	v.v(float(au_grand_froid.stress) > float(au_froid.stress)
		and float(au_froid.stress) > float(au_confort.stress),
		"le stress doit monter strictement a mesure que le froid s'aggrave")

func _le_stress_monte_avec_la_chaleur(v) -> void:
	var mousse: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[0]
	var au_confort: Dictionary = _mesurer(mousse, 120.0)
	var au_chaud: Dictionary = _mesurer(mousse, 180.0)
	var a_la_fournaise: Dictionary = _mesurer(mousse, 220.0)
	v.v(is_equal_approx(float(au_confort.stress), 0.20),
		"dans la bande neutre, ni froid ni chaud ne contribuent")
	v.v(is_equal_approx(float(au_chaud.stress), 1.00),
		"LE STRESS MONTE AVEC LA CHALEUR : 40 de cuisson x 0.02 = 0.80, plus les 0.20 de l'eau")
	v.v(float(a_la_fournaise.stress) > float(au_chaud.stress),
		"le stress doit monter strictement a mesure que la chaleur s'aggrave")
	# Le froid et le chaud entrent par DEUX poids differents : le meme ecart de
	# 10 degres ne pese pas pareil des deux cotes.
	var froid_10: Dictionary = _mesurer(mousse, 90.0)
	var chaud_10: Dictionary = _mesurer(mousse, 150.0)
	v.v(not is_equal_approx(float(froid_10.stress), float(chaud_10.stress)),
		"JAMAIS UN abs() : le meme ecart de 10 degres ne doit pas produire le meme stress des deux cotes")

func _exces_eau_et_secheresse_contribuent_et_ne_sont_pas_un_abs(v) -> void:
	v.v(is_equal_approx(Banc.exces_eau(1.0, 0.90), 0.10) and is_equal_approx(Banc.exces_eau(0.5, 0.90), 0.0),
		"l'exces d'eau ne compte qu'AU-DESSUS du confort haut")
	v.v(is_equal_approx(Banc.secheresse(0.0, 0.60), 0.60) and is_equal_approx(Banc.secheresse(0.8, 0.60), 0.0),
		"la secheresse ne compte qu'EN DESSOUS du confort bas")

	var mousse: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[0]
	var canal: Dictionary = mousse.proprietes.etats.moiteur_zork

	# Trois niveaux d'eau, la temperature au confort exact : seule l'eau bouge.
	canal["charge"] = 4.0                    # h = 1.00 -> noyade 0.10
	var noye: Dictionary = _mesurer(mousse, 100.0)
	canal["charge"] = 3.0                    # h = 0.75 -> dans la bande, rien
	var a_l_aise: Dictionary = _mesurer(mousse, 100.0)
	canal["charge"] = 0.0                    # h = 0.00 -> soif 0.60
	var assoiffe: Dictionary = _mesurer(mousse, 100.0)

	v.v(is_equal_approx(float(noye.stress), 0.20),
		"L'EXCES D'EAU CONTRIBUE : 0.10 au-dessus du confort haut x 2.00 = 0.20")
	v.v(is_equal_approx(float(a_l_aise.stress), 0.0),
		"BANDE DE CONFORT : entre les deux seuils d'eau, l'eau ne contribue EXACTEMENT rien")
	v.v(is_equal_approx(float(assoiffe.stress), 0.60),
		"LA SECHERESSE CONTRIBUE : 0.60 sous le confort bas x 1.00 = 0.60")

	# JAMAIS UN abs() sur l'eau non plus : le MEME ecart de 0.10 hors de la bande,
	# d'un cote puis de l'autre, doit peser deux nombres differents.
	canal["charge"] = 2.0                    # h = 0.50 -> soif 0.10 x 1.00 = 0.10
	var sec_de_10: Dictionary = _mesurer(mousse, 100.0)
	v.v(is_equal_approx(float(sec_de_10.stress), 0.10),
		"0.10 sous le confort bas doit couter 0.10")
	v.v(not is_equal_approx(float(sec_de_10.stress), float(noye.stress)),
		"JAMAIS UN abs() SUR L'EAU : 0.10 de trop et 0.10 de trop peu ne doivent pas peser pareil")

func _le_recalcul_est_a_neuf(v) -> void:
	var mousse: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[0]
	Banc.poser_couts_thermiques(mousse, 90.0, CONFIG_ZORK)
	var premier: float = float(Banc.poser_stress(mousse, CONFIG_ZORK).stress)
	for i in range(100):
		Banc.poser_stress(mousse, CONFIG_ZORK)
	v.v(is_equal_approx(float(mousse.proprietes.tension_zork), premier),
		"RECALCUL A NEUF : cent passages sur un monde immobile doivent rendre EXACTEMENT le meme nombre, " +
		"jamais une accumulation -- c'est ce recalcul, et lui seul, qui empeche un champ derive de deriver")
	# Une valeur empoisonnee a la main doit etre ECRASEE, jamais complétée.
	mousse.proprietes["tension_zork"] = 999.0
	Banc.poser_stress(mousse, CONFIG_ZORK)
	v.v(is_equal_approx(float(mousse.proprietes.tension_zork), premier),
		"le stress doit etre ECRIT PAR-DESSUS la valeur precedente, jamais ajoute a elle")
	# Et il REDESCEND, contrairement a toutes les grandeurs cumulees du depot.
	Banc.poser_couts_thermiques(mousse, 100.0, CONFIG_ZORK)
	Banc.poser_stress(mousse, CONFIG_ZORK)
	v.v(float(mousse.proprietes.tension_zork) < premier,
		"REVERSIBLE : le stress doit redescendre des que les conditions s'ameliorent")

func _escalier_stress_leger_puis_mort_stress(v) -> void:
	var mousse: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[0]
	var monde: Array = [mousse]

	# Sous le premier seuil (0.50) : rien.
	_mesurer(mousse, 100.0)
	SeuilEtat.avancer(monde, CONFIG_ZORK.seuils_locaux)
	v.v(not mousse.proprietes.etats_actifs.has("tendu_zork"),
		"sous le premier seuil, aucun etat de stress ne doit etre pose (comparaison strictement au-dessus)")

	# Entre les deux seuils : le premier SEUL.
	_mesurer(mousse, 90.0)
	SeuilEtat.avancer(monde, CONFIG_ZORK.seuils_locaux)
	v.v(mousse.proprietes.etats_actifs.has("tendu_zork") and not mousse.proprietes.etats_actifs.has("fini_zork"),
		"PREMIER ETAGE : au-dela du premier seuil et sous le second, seul l'etat leger doit etre actif")

	# REVERSIBILITE du premier etage, tant que le second n'est pas franchi.
	_mesurer(mousse, 100.0)
	SeuilEtat.avancer(monde, CONFIG_ZORK.seuils_locaux)
	v.v(not mousse.proprietes.etats_actifs.has("tendu_zork"),
		"REVERSIBLE : le stress redescendu, seuil_etat.gd doit retirer l'etat leger tout seul")

	# Au-dela du second : les DEUX restent actifs (memoire PAR ENTREE).
	_mesurer(mousse, 80.0)
	SeuilEtat.avancer(monde, CONFIG_ZORK.seuils_locaux)
	v.v(mousse.proprietes.etats_actifs.has("tendu_zork") and mousse.proprietes.etats_actifs.has("fini_zork"),
		"SECOND ETAGE : au-dela du second seuil, les DEUX etats doivent rester actifs -- " +
		"aucune entree n'en retire une autre")

func _le_gate_de_mort_est_definitif(v) -> void:
	var mousse: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[0]
	var monde: Array = [mousse]
	_mesurer(mousse, 80.0)
	SeuilEtat.avancer(monde, CONFIG_ZORK.seuils_locaux)
	v.v(Banc.est_mort(mousse, CONFIG_ZORK), "le vivant doit bien etre mort avant que le gate ne soit teste")
	var stress_a_la_mort: float = float(mousse.proprietes.tension_zork)

	# Le monde REDEVIENT clement : sans gate, le stress redescendrait et
	# seuil_etat.gd retirerait l'etat -- la plante ressusciterait.
	for i in range(5):
		Banc.poser_couts_thermiques(mousse, 100.0, CONFIG_ZORK)
		Banc.poser_stress(mousse, CONFIG_ZORK)
		SeuilEtat.avancer(monde, CONFIG_ZORK.seuils_locaux)
	v.v(is_equal_approx(float(mousse.proprietes.tension_zork), stress_a_la_mort),
		"GATE DE MORT : le stress d'un mort doit rester FIGE, jamais recalcule")
	v.v(mousse.proprietes.etats_actifs.has("fini_zork"),
		"GATE DE MORT : un vivant mort ne doit JAMAIS ressusciter quand le monde redevient clement")
	v.v(is_equal_approx(float(mousse.proprietes.reserves.seve_zork.cout_base), 0.0)
		and is_equal_approx(float(mousse.proprietes.reserves.seve_zork.surcout_action), 0.0),
		"GATE DE MORT : un mort ne depense plus rien -- cout_base ET surcout_action a 0.0")
	var avant: float = float(mousse.proprietes.reserves.seve_zork.reserve)
	Depense.avancer(monde, 10.0)
	v.v(is_equal_approx(float(mousse.proprietes.reserves.seve_zork.reserve), avant),
		"GATE DE MORT : dix secondes plus tard, la reserve d'un mort ne doit pas avoir bouge d'un chiffre")
	# Les miroirs, eux, restent a jour : ils parlent du MONDE, pas du vivant.
	v.v(is_equal_approx(float(mousse.proprietes.gel_zork), 0.0),
		"les deux miroirs thermiques d'un mort restent a jour -- le label ne doit pas mentir sur ce qu'il fait autour")

func _un_vivant_sans_poids_de_stress_traverse_sans_rien_recevoir(v) -> void:
	var bete: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[1]
	var monde: Array = [bete]
	Banc.poser_couts_thermiques(bete, 40.0, CONFIG_ZORK)
	var rendu: Dictionary = Banc.poser_stress(bete, CONFIG_ZORK)
	v.v(rendu.is_empty(), "un vivant sans poids de stress ne doit rien rendre du tout")
	v.v(not bete.proprietes.has("tension_zork") and not bete.proprietes.has("noyade_zork")
		and not bete.proprietes.has("soif_zork"),
		"CHEMIN MORT SILENCIEUX : aucune des trois proprietes de stress ne doit lui etre ecrite")
	SeuilEtat.avancer(monde, CONFIG_ZORK.seuils_locaux)
	v.v(not bete.proprietes.etats_actifs.has("tendu_zork") and not bete.proprietes.etats_actifs.has("fini_zork"),
		"les deux entrees de stress du catalogue LOCAL doivent rester des chemins morts pour lui, sans alarme")
	v.v(is_equal_approx(Banc.calculer_stress(bete, CONFIG_ZORK), 0.0),
		"la somme ponderee d'un vivant sans poids vaut exactement 0.0")
	v.v(Banc.texte_stress(bete, CONFIG_ZORK) == "-",
		"un vivant sans stress affiche '-' et JAMAIS '0.000' : « je n'en ai pas » et « il vaut zero » " +
		"ne se disent pas pareil")
	# MEME REGLE SUR L'EAU ET LA POUSSE -- defaut trouve en LANCANT LA SCENE, pas
	# ici : la trace affichait « eau=0.00 » pour un vivant qui n'a aucun canal
	# d'humidite, ce qui se lit « il est a sec » au lieu de « la question ne se
	# pose pas ».
	v.v(Banc.texte_eau(bete, CONFIG_ZORK, {}).find("-") >= 0
		and Banc.texte_eau(bete, CONFIG_ZORK, {}).find("0.00") < 0,
		"un vivant sans canal d'humidite affiche des tirets, jamais des zeros")
	v.v(Banc.texte_pousse(bete, CONFIG_ZORK, {}).find("-") >= 0
		and Banc.texte_pousse(bete, CONFIG_ZORK, {}).find("0.00") < 0,
		"un vivant qui ne pousse pas affiche des tirets, jamais des zeros")
	var mousse: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[0]
	v.v(Banc.texte_eau(mousse, CONFIG_ZORK, {"humidite": 1.0, "exces": 0.1, "secheresse": 0.0}).find("1.00") >= 0,
		"un vivant qui boit affiche bien ses trois nombres")

func _la_croissance_est_le_consommateur_reel_des_deux_etats(v) -> void:
	var mousse: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[0]
	v.v(is_equal_approx(Banc.croissance_effective(mousse, CONFIG_ZORK, ETATS_ZORK), 0.10),
		"sans aucun etat, la croissance effective doit valoir la croissance de base")
	mousse.proprietes.etats_actifs = ["tendu_zork"]
	v.v(is_equal_approx(Banc.croissance_effective(mousse, CONFIG_ZORK, ETATS_ZORK), 0.05),
		"CONSTAT (A) TENU : l'etat leger doit REELLEMENT diviser la croissance par deux")
	mousse.proprietes.etats_actifs = ["tendu_zork", "fini_zork"]
	v.v(is_equal_approx(Banc.croissance_effective(mousse, CONFIG_ZORK, ETATS_ZORK), 0.0),
		"un ecraseur gagne toujours sur un modulateur : la mort met la croissance a 0.0 " +
		"sans qu'aucun des deux etats n'ait a connaitre l'autre")

	var bete: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[1]
	v.v(is_equal_approx(Banc.croissance_effective(bete, CONFIG_ZORK, ETATS_ZORK), 0.0),
		"un vivant qui ne pousse pas rend exactement 0.0, jamais une valeur inventee")

	# La maturite monte reellement, et elle est PLAFONNEE par le cablage
	# (flux.gd ne borne jamais rien).
	var pousse: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[0]
	v.v(is_equal_approx(Banc.avancer_croissance(pousse, 0.10, 2.0, CONFIG_ZORK), 0.20),
		"la maturite doit monter de taux x delta, via flux.gd")
	Banc.avancer_croissance(pousse, 0.10, 100.0, CONFIG_ZORK)
	v.v(is_equal_approx(Banc.maturite(pousse, CONFIG_ZORK), 1.0),
		"PLAFOND AU CABLAGE : la maturite ne doit jamais depasser son maximum -- flux.gd ne borne rien lui-meme")
	v.v(is_equal_approx(Banc.avancer_croissance(pousse, 0.0, 10.0, CONFIG_ZORK), 1.0),
		"un taux nul ne doit rien changer, et surtout jamais faire redescendre la maturite")

func _les_seuils_thermiques_sont_lus_par_objet(v) -> void:
	var vivants: Array = Banc.construire_vivants(CONFIG_ZORK)
	var mousse: Dictionary = vivants[0]
	var bete: Dictionary = vivants[1]
	# LE MEME monde : la mousse (seuil 5, confort 100) ne ressent que 4 de froid
	# et ne bascule pas ; la bete (seuil 20, confort 150) en ressent 54 et
	# bascule. C'est le seuil PAR OBJET, impossible avec un seuil universel.
	Banc.poser_couts_thermiques(mousse, 96.0, CONFIG_ZORK)
	Banc.poser_couts_thermiques(bete, 96.0, CONFIG_ZORK)
	SeuilEtat.avancer(vivants, CONFIG_ZORK.seuils_locaux)
	v.v(not mousse.proprietes.etats_actifs.has("raide_zork"),
		"SEUIL PAR OBJET : 4 de froid sous un seuil de 5 ne doit rien poser")
	v.v(bete.proprietes.etats_actifs.has("raide_zork"),
		"SEUIL PAR OBJET : 54 de froid au-dessus d'un seuil de 20 doit poser l'etat, DANS LE MEME MONDE")

	# Un vivant SANS le seuil declare replie sur INF et ne bascule JAMAIS --
	# chemin mort silencieux, jamais une alarme.
	var sans_seuil: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[1]
	sans_seuil.proprietes.erase("palier_gel_zork")
	Banc.poser_couts_thermiques(sans_seuil, 0.0, CONFIG_ZORK)
	SeuilEtat.avancer([sans_seuil], CONFIG_ZORK.seuils_locaux)
	v.v(not sans_seuil.proprietes.etats_actifs.has("raide_zork"),
		"un vivant sans le seuil declare replie sur INF et ne bascule JAMAIS, sans alarme")

func _paliers_arrosage_et_plafond_d_humidite(v) -> void:
	v.v(Banc.palier_suivant(0, 3) == 1 and Banc.palier_suivant(2, 3) == 0,
		"le toggle de palier doit etre CYCLIQUE")
	v.v(is_equal_approx(Banc.ambiante(CONFIG_ZORK, 1), 60.0), "l'ambiante doit venir du palier courant")
	var catalogue: Dictionary = Banc.catalogue_temperature(CONFIG_ZORK, 1)
	v.v(catalogue.has("defaut") and is_equal_approx(float(catalogue.defaut.ambiante), 60.0)
		and catalogue.defaut.has("attenuation"),
		"le catalogue construit doit avoir la forme EXACTE que temperature.gd attend")
	# Il doit reellement traverser temperature.gd, loin de toute zone.
	v.v(is_equal_approx(Temperature.locale(Vector3(50.0, 0.0, 0.0), Banc.sources_temperature(CONFIG_ZORK), catalogue), 60.0),
		"hors de toute zone, la temperature locale doit valoir l'ambiante du palier, telle quelle")

	var sources: Array = Banc.sources_temperature(CONFIG_ZORK)
	v.v(sources.size() == 1 and sources[0].has("position") and sources[0].has("rayon")
		and sources[0].has("temperature") and sources[0].has("force"),
		"sources_temperature doit rendre exactement la forme que temperature.gd attend")
	v.v(not sources[0].has("couleur"), "la couleur de rendu ne doit jamais entrer dans le calcul de temperature")

	# Arrosage coupe : AUCUNE cause -- charge.gd n'applique sa decroissance que
	# quand la somme a portee est nulle, une cause de poids 0.0 laisserait la
	# charge PLATE au lieu de la faire descendre.
	v.v(Banc.causes_eau(CONFIG_ZORK, false).is_empty(),
		"arrosage coupe : aucune cause, jamais une cause de poids nul")
	v.v(Banc.causes_eau(CONFIG_ZORK, true).size() == 1,
		"arrosage actif : exactement une cause")

	var mousse: Dictionary = Banc.construire_vivants(CONFIG_ZORK)[0]
	var canal: Dictionary = mousse.proprietes.etats.moiteur_zork
	Charge.avancer([mousse], Banc.causes_eau(CONFIG_ZORK, true), 10.0)
	v.v(float(canal.charge) > float(canal.seuil),
		"charge.gd ne borne pas le HAUT : sans plafond, la charge depasse bien son seuil")
	Banc.plafonner_humidite(mousse, CONFIG_ZORK)
	v.v(is_equal_approx(float(canal.charge), 4.0),
		"PLAFOND AU CABLAGE : la charge doit etre ramenee a son seuil apres chaque appel")
	v.v(is_equal_approx(Banc.humidite_normalisee(mousse, CONFIG_ZORK), 1.0),
		"l'humidite normalisee doit valoir 1.0 a saturation, jamais la charge brute")
	Charge.avancer([mousse], Banc.causes_eau(CONFIG_ZORK, false), 1.0)
	v.v(is_equal_approx(float(canal.charge), 2.0),
		"arrosage coupe : la charge doit descendre de taux_decroissance x delta")
	v.v(is_equal_approx(Banc.humidite_normalisee(mousse, CONFIG_ZORK), 0.5),
		"l'humidite normalisee doit valoir clamp(charge/seuil, 0, 1)")

# ---- Chemin reel : les fichiers du disque ----

# ACCORD ENTRE LE BANC ET SON CATALOGUE LOCAL. Si un nom de miroir de
# data/banc_stress_thermo_vivant.json cessait de correspondre au
# 'propriete_continue' d'une entree de 'seuils_locaux', le banc ecrirait sagement
# un nombre que plus personne ne comparerait : aucun etat ne se poserait plus
# jamais, et AUCUNE alarme ne le dirait (seuil_etat.gd traite une propriete
# absente comme un chemin mort legitime). Ce cas ferme ce trou.
func _chemin_reel_les_noms_de_miroirs_sont_ceux_du_catalogue_local(v) -> void:
	var config: Dictionary = _charger("res://data/banc_stress_thermo_vivant.json")
	var etats: Dictionary = _charger("res://data/etats.json")
	v.v(not config.is_empty() and not etats.is_empty(), "les deux fichiers du chemin reel doivent charger")

	var seuils: Dictionary = config.seuils_locaux
	var attendus := {
		"stress_leger": String(config.nom_stress),
		"mort_stress": String(config.nom_stress),
		"froid_leger": String(config.nom_froid_ressenti),
		"froid_grave": String(config.nom_froid_ressenti),
		"chaud_grave": String(config.nom_chaud_ressenti),
	}
	for ref in attendus:
		v.v(seuils.has(ref), "le catalogue LOCAL doit porter l'entree '%s'" % ref)
		if not seuils.has(ref):
			continue
		v.v(String(seuils[ref].propriete_continue) == String(attendus[ref]),
			"l'entree '%s' doit comparer le miroir que le banc ecrit reellement (%s)" % [ref, attendus[ref]])
		v.v(seuils[ref].has("seuil_propriete") and not seuils[ref].has("seuil"),
			"l'entree '%s' doit lire son seuil PAR OBJET -- c'est toute la raison du catalogue local" % ref)
		var nom_etat := String(seuils[ref].etat)
		v.v(etats.has(nom_etat), "l'etat '%s' doit exister dans data/etats.json" % nom_etat)
		if etats.has(nom_etat):
			v.v(not etats[nom_etat].has("duree"),
				"l'etat '%s' ne doit porter AUCUNE duree : il est retire par le franchissement " % nom_etat +
				"descendant, jamais par le temps")

	v.v(String(seuils.stress_leger.etat) == String(config.etat_stress_leger)
		and String(seuils.mort_stress.etat) == String(config.etat_mort_stress),
		"les deux noms d'etat que le cablage lit (gate de mort, compteur) doivent etre ceux du catalogue")

	# Chaque vivant doit porter les seuils que le catalogue va lire sur lui --
	# sinon repli sur INF, et l'entree ne se declenche jamais, EN SILENCE.
	for vivant in Banc.construire_vivants(config):
		for ref in ["froid_leger", "froid_grave", "chaud_grave"]:
			v.v(vivant.proprietes.has(String(seuils[ref].seuil_propriete)),
				"le vivant '%s' doit porter '%s', sans quoi l'entree '%s' ne se declencherait JAMAIS"
					% [String(vivant.id), String(seuils[ref].seuil_propriete), ref])
		# Les deux seuils de stress, eux, ne sont attendus que sur qui a des poids.
		if vivant.proprietes.has(String(config.nom_poids_stress)):
			v.v(vivant.proprietes.has(String(seuils.stress_leger.seuil_propriete))
				and vivant.proprietes.has(String(seuils.mort_stress.seuil_propriete)),
				"le vivant '%s' porte des poids de stress : il doit porter ses deux seuils" % String(vivant.id))
			v.v(float(vivant.proprietes[String(seuils.mort_stress.seuil_propriete)])
				> float(vivant.proprietes[String(seuils.stress_leger.seuil_propriete)]),
				"ESCALIER : le seuil mortel de '%s' doit rester strictement au-dessus du seuil leger"
					% String(vivant.id))

func _chemin_reel_les_deux_etats_neufs_sont_conformes(v) -> void:
	var config: Dictionary = _charger("res://data/banc_stress_thermo_vivant.json")
	var etats: Dictionary = _charger("res://data/etats.json")

	var leger: Dictionary = etats.get(String(config.etat_stress_leger), {})
	var mort: Dictionary = etats.get(String(config.etat_mort_stress), {})
	v.v(not leger.is_empty() and not mort.is_empty(),
		"les deux etats neufs doivent exister dans le catalogue PARTAGE data/etats.json")

	v.v(_effet(leger, String(config.nom_croissance)).get("mode", "") == "moduler"
		and is_equal_approx(float(_effet(leger, String(config.nom_croissance)).get("facteur", 0.0)), 0.5),
		"'stress_leger' doit MODULER la croissance par 0.5")
	v.v(_effet(mort, String(config.nom_croissance)).get("mode", "") == "ecraser"
		and is_equal_approx(float(_effet(mort, String(config.nom_croissance)).get("valeur", -1.0)), 0.0),
		"'mort_stress' doit ECRASER la croissance a 0.0 -- un ecraseur gagne toujours sur un modulateur")
	v.v(_effet(mort, String(config.nom_vitesse)).get("mode", "") == "ecraser"
		and is_equal_approx(float(_effet(mort, String(config.nom_vitesse)).get("valeur", -1.0)), 0.0),
		"'mort_stress' doit ECRASER la vitesse a 0.0")

	# Les trois etats thermiques sont ceux, PARTAGES, qui existaient deja : ce
	# chantier n'en a ajoute aucun.
	for nom in ["frisson", "hypothermie", "hyperthermie"]:
		v.v(etats.has(nom), "l'etat thermique PARTAGE '%s' doit exister -- ce banc le repose, il ne le cree pas" % nom)

func _chemin_reel_geometrie_et_palier_de_depart(v) -> void:
	var config: Dictionary = _charger("res://data/banc_stress_thermo_vivant.json")
	var sources: Array = Banc.sources_temperature(config)
	v.v(sources.size() == 2, "le terrain reel doit porter exactement deux zones")
	v.v(sources[0].position.distance_to(sources[1].position)
		> float(sources[0].rayon) + float(sources[1].rayon),
		"les deux zones ne doivent JAMAIS se chevaucher -- temperature.gd superpose ADDITIVEMENT, " +
		"elles s'annuleraient en partie et le banc mentirait sur ce qu'il montre")
	for source in sources:
		v.v(float(source.force) < 1.0,
			"la force d'une zone doit rester sous 1.0 : a force 1.0 son centre vaudrait sa temperature " +
			"QUELLE QUE SOIT l'ambiante, et le clic gauche n'aurait plus aucun effet sur qui s'y trouve")

	# Palier de depart : personne ne porte le moindre etat. Sans ce cas, une
	# calibration decalee laisserait un banc qui montre tout de suite tout, ou
	# rien, en restant VERT (defaut exact rencontre par banc_maladie).
	var diag: Dictionary = _rejouer(config, 0, true, 20)
	for id in diag:
		v.v(diag[id].etats.is_empty(),
			"PALIER DE DEPART : '%s' ne doit porter AUCUN etat -- ni stress, ni thermique" % id)
	v.v(is_equal_approx(float(diag.tropicale.stress), 0.000)
		and is_equal_approx(float(diag.temperee.stress), 0.150)
		and is_equal_approx(float(diag.arctique.stress), 0.360),
		"CALIBRATION du palier tempere : tropicale 0.000, temperee 0.150, arctique 0.360")
	v.v(diag.animal.stress == null,
		"l'animal ne porte aucun poids de stress : aucune valeur ne doit lui etre ecrite")
	# L'animal, lui, a froid des le depart -- une bete a 20 degres depense.
	v.v(float(diag.animal.froid) > 0.0 and float(diag.animal.thermo) > 0.0,
		"des le palier tempere, l'animal (cible 37) doit deja payer un surcout thermique")
	# Et la croissance tourne vraiment.
	v.v(float(diag.tropicale.maturite) > 0.0, "au palier tempere, une plante non stressee doit pousser")

func _chemin_reel_la_tropicale_meurt_de_froid(v) -> void:
	var config: Dictionary = _charger("res://data/banc_stress_thermo_vivant.json")
	var diag: Dictionary = _rejouer(config, 1, true, 20)
	v.v(is_equal_approx(float(diag.tropicale.stress), 1.600),
		"GRAND FROID : le stress de la tropicale doit valoir exactement 16 de froid x 0.100")
	v.v(diag.tropicale.etats.has(String(config.etat_mort_stress)),
		"LA TROPICALE MEURT DE FROID au palier grand froid")
	v.v(diag.tropicale.etats.has(String(config.etat_stress_leger)),
		"ESCALIER : elle doit porter les DEUX etats, le leger n'etant jamais retire par le mortel")
	v.v(is_equal_approx(float(diag.temperee.stress), 1.080)
		and diag.temperee.etats.has(String(config.etat_stress_leger))
		and not diag.temperee.etats.has(String(config.etat_mort_stress)),
		"la temperee doit etre stressee (1.080) mais SURVIVRE -- son seuil mortel est plus haut")
	# RESSENTIR LE FROID N'EST PAS EN ETRE STRESSE, et c'est tout le sujet de
	# l'arctique : son 'froid_ressenti' monte a 18 comme celui de n'importe qui,
	# ses seuils thermiques a elle posent bien 'frisson' -- mais son
	# 'poids_stress' ne porte AUCUNE entree sur le froid, donc sa somme ponderee
	# ne bouge pas d'un chiffre entre le palier tempere et le grand froid.
	v.v(is_equal_approx(float(diag.arctique.stress), 0.360),
		"L'ARCTIQUE NE BOUGE PAS D'UN CHIFFRE dans le froid : elle ne porte AUCUN poids sur le froid, " +
		"son stress reste celui du palier tempere")
	v.v(not diag.arctique.etats.has(String(config.etat_stress_leger))
		and not diag.arctique.etats.has(String(config.etat_mort_stress)),
		"l'arctique ne doit etre ni stressee ni morte au grand froid")
	v.v(float(diag.arctique.froid) > 0.0 and diag.arctique.etats.has("frisson"),
		"elle RESSENT pourtant le froid (miroir non nul, 'frisson' pose par SON seuil a elle) : " +
		"ressentir n'est pas etre stresse, c'est le poids qui separe les deux")
	v.v(not diag.arctique.etats.has("hypothermie"),
		"son seuil grave a elle (30) n'est pas franchi par 18 de froid, la ou la temperee et la " +
		"tropicale, moins resistantes, passent les deux etages")
	# L'animal depense plus qu'au palier tempere -- meme monde, meme instant.
	var au_tempere: Dictionary = _rejouer(config, 0, true, 20)
	v.v(float(diag.animal.thermo) > float(au_tempere.animal.thermo),
		"L'ANIMAL DEPENSE PLUS D'ENERGIE DANS LE FROID")
	v.v(float(diag.animal.energie) < float(au_tempere.animal.energie),
		"a delta egal, sa reserve doit reellement etre descendue plus bas au palier froid")
	v.v(diag.animal.etats.has("frisson") and diag.animal.etats.has("hypothermie"),
		"au grand froid, l'animal doit porter ses deux etats thermiques, poses par SES seuils a lui")

func _chemin_reel_l_arctique_meurt_de_chaud(v) -> void:
	var config: Dictionary = _charger("res://data/banc_stress_thermo_vivant.json")
	var diag: Dictionary = _rejouer(config, 2, true, 20)
	v.v(is_equal_approx(float(diag.arctique.stress), 1.860),
		"CANICULE : le stress de l'arctique doit valoir 15 de chaud x 0.100 plus 0.30 d'exces d'eau x 1.200")
	v.v(diag.arctique.etats.has(String(config.etat_mort_stress)),
		"L'ARCTIQUE MEURT DE CHAUD au palier canicule")
	v.v(is_equal_approx(float(diag.tropicale.stress), 0.120) and diag.tropicale.etats.has("hyperthermie")
		and not diag.tropicale.etats.has(String(config.etat_stress_leger)),
		"LA TROPICALE VA BIEN EN CANICULE : elle ressent la chaleur (hyperthermie) mais ne s'en stresse presque pas")
	v.v(is_equal_approx(float(diag.temperee.stress), 1.170)
		and diag.temperee.etats.has(String(config.etat_stress_leger))
		and not diag.temperee.etats.has(String(config.etat_mort_stress)),
		"la temperee doit etre stressee (1.170) mais survivre a la canicule aussi")

func _chemin_reel_l_assechement_stresse_la_tropicale_seule(v) -> void:
	var config: Dictionary = _charger("res://data/banc_stress_thermo_vivant.json")
	# Palier tempere, arrosage COUPE : la temperature ne joue plus aucun role
	# (les trois sont a leur confort), seule l'eau parle.
	var diag: Dictionary = _rejouer(config, 0, false, 300)
	v.v(is_equal_approx(float(diag.tropicale.stress), 0.660)
		and diag.tropicale.etats.has(String(config.etat_stress_leger)),
		"ASSECHEMENT : la tropicale, la plus assoiffee des trois, doit basculer par la SECHERESSE SEULE")
	v.v(is_equal_approx(float(diag.temperee.stress), 0.210) and diag.temperee.etats.is_empty(),
		"la temperee doit encaisser l'assechement sans basculer")
	v.v(is_equal_approx(float(diag.arctique.stress), 0.005) and diag.arctique.etats.is_empty(),
		"l'arctique, qui ne demande presque pas d'eau, ne doit presque rien ressentir")
	v.v(is_equal_approx(float(diag.tropicale.humidite), 0.0),
		"arrosage coupe assez longtemps : l'humidite normalisee doit etre retombee a exactement 0.0")

# ---- Aides ----

# Un tour complet de mesure hors domaine : les couts thermiques (donc les deux
# miroirs) PUIS le stress, dans l'ordre du vrai tick -- le stress LIT les miroirs
# que le premier vient d'ecrire.
func _mesurer(vivant: Dictionary, temp_locale: float) -> Dictionary:
	Banc.poser_couts_thermiques(vivant, temp_locale, CONFIG_ZORK)
	return Banc.poser_stress(vivant, CONFIG_ZORK)

# Rejoue le VRAI tick du banc (Banc.avancer, la fonction statique qui porte tout
# le pas) sur le monde REEL, `pas` fois a 0.1 s, et rend un resume par id. Aucun
# ordre n'est recopie ici : une divergence entre le test et le banc est
# structurellement impossible.
func _rejouer(config: Dictionary, palier: int, arrosage: bool, pas: int) -> Dictionary:
	var etats: Dictionary = _charger("res://data/etats.json")
	var vivants: Array = Banc.construire_vivants(config)
	var sources: Array = Banc.sources_temperature(config)
	var diag: Dictionary = {}
	for i in range(pas):
		diag = Banc.avancer(vivants, sources, config, etats, palier, arrosage, 0.1)
	var resume: Dictionary = {}
	for vivant in vivants:
		var d: Dictionary = diag[vivant.id]
		resume[vivant.id] = {
			"stress": vivant.proprietes.get(String(config.nom_stress), null),
			"froid": float(vivant.proprietes.get(String(config.nom_froid_ressenti), 0.0)),
			"chaud": float(vivant.proprietes.get(String(config.nom_chaud_ressenti), 0.0)),
			"humidite": float(d.get("humidite", 0.0)),
			"thermo": float(d.get("thermo", 0.0)),
			"energie": float(d.get("energie", 0.0)),
			"maturite": float(d.get("maturite", 0.0)),
			"etats": vivant.proprietes.get("etats_actifs", []),
		}
	return resume

func _effet(etat: Dictionary, propriete: String) -> Dictionary:
	for effet in etat.get("effets", []):
		if String(effet.get("propriete", "")) == propriete:
			return effet
	return {}

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
