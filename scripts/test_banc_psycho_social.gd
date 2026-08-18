extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_psycho_social.gd
#
# Verrouille les fonctions PURES de scripts/banc_psycho_social.gd (chantier
# « conflit interne + besoin critique + directives + apprentissage »). Le banc
# ne fait que CABLER des mecanismes du coeur deja verrouilles separement
# (dominance.gd/agir.gd/deformation.gd/epigenetique.gd/depense.gd/
# seuil_etat.gd/etat_effectif.gd/consommer.gd/proximite.gd/perception.gd, TOUS
# INCHANGES par ce chantier) : aucune de leurs lois n'est retestee ici. Ce qui
# est teste, c'est ce que le CABLAGE ajoute -- la mesure de l'ecart sur
# 'resultats' et non sur 'visibles', le miroir de stress, la somme des trois
# surcouts en UNE ecriture, la sigmoide, l'entree synthetique de directive et
# son gate, et l'accumulation/rouille de la marque de combat.
#
# DEUX MOITIES, comme les autres tests de banc :
# - HORS DOMAINE : une config, des catalogues d'etats/deformations/
#   epigenetique/profils/canaux/actions ENTIEREMENT INVENTES (domaine
#   « zorn » : reserve 'seve_zorn', canal 'oeil_zorn', verbes 'gober_zorn'/
#   'charger_zorn', etats 'tiraille_zorn'/'furie_zorn') traversent le meme
#   code. Si le banc nommait 'energie', 'vitesse', 'comestible', 'stresse',
#   'colere' ou 'vue' en dur, ce bloc rougirait.
# - CHEMIN REEL : data/banc_psycho_social.json et les catalogues PARTAGES relus
#   SUR LE DISQUE, pour verifier la CALIBRATION (le dilemme, l'ecrasement par
#   la faim, le poids de la directive sont-ils reellement atteignables sur
#   cette scene) et l'ACCORD entre les noms de miroirs du banc et les
#   propriete_continue des entrees de seuil -- accord dont la rupture serait
#   SILENCIEUSE (un miroir ecrit sous un nom que personne ne compare : aucun
#   etat ne se poserait plus jamais, sans une seule alarme).

const Banc = preload("res://scripts/banc_psycho_social.gd")
const Monde = preload("res://scripts/monde.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Depense = preload("res://scripts/depense.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Deformation = preload("res://scripts/deformation.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Perception = preload("res://scripts/perception.gd")
const Verif = preload("res://scripts/verif.gd")

# ---- Domaine invente de bout en bout ----

const CONFIG_ZORN := {
	"nom_reserve_energie": "seve_zorn",
	"nom_reserve_repas": "pulpe_zorn",
	"nom_vitesse": "allure_zorn",
	"nom_manque_energie": "creux_zorn",
	"nom_froid_ressenti": "gel_zorn",
	"nom_chaud_ressenti": "brulure_zorn",
	"nom_stress_interne": "tiraillement_zorn",
	"nom_ardeur_combat": "fougue_zorn",

	"capacite_energie": 20.0,
	"metabolisme_base_par_s": 1.0,
	"coef_effort": 0.5,
	"coef_stress": 4.0,
	"vitesse_base": 10.0,

	"temp_cible": 100.0,
	"seuil_chaud": 140.0,
	"cout_par_degre_froid": 3.0,
	"cout_par_degre_chaud": 7.0,

	"seuil_ecart": 0.6,

	"seuil_critique_ratio": 0.4,
	"raideur_sigmoide": 12.0,
	"gain_deformation_par_s": 4.0,
	"plafond_biais_faim": 6.0,
	"source_deformation": "creuse_zorn",
	"cible_deformation": "croquable_zorn",

	"nom_marque_combat": "rixe_zorn",
	"intervalle_pose_marque_s": 0.25,
	"plafond_modification": 0.5,
	"etat_colere": "furie_zorn",
	"etat_stresse": "tiraille_zorn",
	"verbe_combat": "charger_zorn",

	"directive": {
		"cible_id": "brasier_zorn",
		"bonus_score": 2.5,
		"ecrase_vital": 0,
		"etats_vitaux": ["creve_zorn"],
	},
	"repas": {
		"rayon_repas": 40.0,
		"taux_repas_par_s": 30.0,
		"verbe_repas": "gober_zorn",
	},
	"soin": {
		"rayon_soin": 40.0,
		"taux_soin_par_s": 12.0,
		"capacite_sante": 100.0,
		"nom_reserve_sante": "seve_vitale_zorn",
		"verbe_soin": "rafistoler_zorn",
		"propriete_blessure": "eclope_zorn",
	},
	"combat": {
		"rayon_combat": 40.0,
		"cout_combat_par_s": 15.0,
		"cout_energie_combat_par_s": 3.0,
		"capacite_vigueur": 100.0,
		"nom_reserve_vigueur": "hargne_zorn",
	},
	"seuils_locaux": {
		"tiraillement": { "propriete_continue": "tiraillement_zorn", "seuil": 0.15, "etat": "tiraille_zorn" },
		"fougue": { "propriete_continue": "fougue_zorn", "seuil": 0.5, "etat": "furie_zorn" },
	},
	"forme_colon": {
		"seuil_ecrasement": 1.0,
		"gain_inertie": 0.1,
		"rayon_liaison": 0.0,
		"gain_bas": 0.1,
		"plafond_bas": 0.5,
		"gain_haut": 1.0,
		"plafond_haut": 1.0,
	},
	"poids_verbes_colon": {
		"approcher_zorn": 1.0,
		"aider_zorn": 1.0,
		"gober_zorn": 1.0,
		"charger_zorn": 1.0,
	},
	"canaux": ["oeil_zorn"],
	"canaux_config": { "oeil_zorn": { "portee": 1600.0, "angle": 360.0, "sensibilite": 1.0, "seuil": 0.0 } },
	"deformation_sources": ["creuse_zorn"],
	"zones_temperature": [
		{ "id": "gouffre_zorn", "position": [880.0, 460.0, 0.0], "rayon": 300.0, "temperature": 40.0, "force": 1.0 },
	],
}

const CANAUX_ZORN := {
	"oeil_zorn": { "geometrie": "cone_oriente", "proprietes_captees": [] },
}

const PROFILS_ZORN := {
	"lueur_zorn": { "saillance_intrinseque": 3.0, "portee_saillance": 900.0 },
	"plaie_zorn": { "saillance_intrinseque": 3.2, "portee_saillance": 900.0 },
	"pitance_zorn": { "saillance_intrinseque": 2.0, "portee_saillance": 900.0 },
	"rival_zorn": { "saillance_intrinseque": 4.0, "portee_saillance": 900.0 },
}

const ACTIONS_ZORN := {
	"ardent_zorn": { "verbes": ["approcher_zorn"] },
	"eclope_zorn": { "verbes": ["aider_zorn"] },
	"croquable_zorn": { "verbes": ["gober_zorn"] },
	"hargneux_zorn": { "verbes": ["charger_zorn"] },
}

const DEFORMATIONS_ZORN := {
	"creuse_zorn": {
		"sens": "monte",
		"taux_decroissance_rapide": 1.0,
		"taux_decroissance_lent": 0.8,
		"w_rapide": 0.5,
		"w_lent": 0.5,
	},
}

const EPIGENETIQUE_ZORN := {
	"rixe_zorn": { "modulateur_pose": 0.02, "taux_decroissance": 0.01, "plancher_suppression": 0.015 },
}

const ETATS_ZORN := {
	"tiraille_zorn": { "effets": [] },
	"furie_zorn": { "effets": [] },
	"creve_zorn": { "effets": [ { "propriete": "allure_zorn", "mode": "moduler", "facteur": 0.5 } ] },
}

const CHOSES_ZORN := [
	{ "id": "brasier_zorn", "type": "brasier", "position": [700.0, 180.0, 0.0],
		"proprietes": { "ardent_zorn": true, "profil_saillance": "lueur_zorn" } },
	{ "id": "eclope_zorn", "type": "eclope", "position": [700.0, 340.0, 0.0],
		"proprietes": { "eclope_zorn": true, "profil_saillance": "plaie_zorn",
			"reserves": { "seve_vitale_zorn": { "reserve": 30.0 } } } },
	{ "id": "pitance_zorn", "type": "pitance", "position": [880.0, 460.0, 0.0],
		"proprietes": { "croquable_zorn": true, "profil_saillance": "pitance_zorn",
			"reserves": { "pulpe_zorn": { "reserve": 300.0 } } } },
	{ "id": "rival_zorn", "type": "rival", "position": [200.0, 320.0, 0.0],
		"proprietes": { "hargneux_zorn": true, "profil_saillance": "rival_zorn",
			"reserves": { "hargne_zorn": { "reserve": 100.0, "cout_base": 0.0, "surcout_action": 0.0 } } } },
]

const DECL_COLON_ZORN := { "position": [330.0, 260.0, 0.0], "biais_combat_base": 0.20, "modulateur_combat_depart": 0.0 }
const DECL_VETERAN_ZORN := { "position": [330.0, 260.0, 0.0], "biais_combat_base": 0.20, "modulateur_combat_depart": 0.40 }

func _init() -> void:
	var v := Verif.new()
	# Hors domaine.
	_colon_pose_sans_type_ni_temperature(v)
	_ecart_mesure_sur_resultats_jamais_sur_visibles(v)
	_saillances_dedupliquees_par_cible(v)
	_stress_monte_quand_les_deux_options_sont_proches(v)
	_stress_nul_quand_une_option_se_detache(v)
	_le_stress_consomme_de_l_energie(v)
	_les_quatre_surcouts_se_somment_en_une_seule_ecriture(v)
	_la_sigmoide_monte_quand_la_reserve_descend(v)
	_sous_le_seuil_critique_la_nourriture_ecrase_tout(v)
	_la_directive_ajoute_une_saillance_synthetique(v)
	_le_colon_obeit_si_la_directive_pese_plus(v)
	_le_colon_desobeit_si_son_besoin_pese_plus(v)
	_ecrase_vital_empeche_la_directive_sous_besoin_critique(v)
	_le_veteran_bifurque_vers_colere_plus_facilement(v)
	_l_experience_decroit_sans_combat(v)
	_le_repas_est_conservatif_et_borne(v)
	_le_soin_est_conservatif_et_coute_au_soigneur(v)
	_le_soin_est_borne_par_la_capacite(v)
	_l_allie_gueri_sort_de_la_saillance_et_du_verbe(v)
	_l_allie_gueri_libere_le_colon(v)
	_le_combat_detruit_la_vigueur_sans_la_transferer(v)
	_le_cout_de_combat_est_reecrit_a_neuf_chaque_appel(v)
	_l_adversaire_finit_par_etre_vaincu(v)
	# Chemin reel.
	_chemin_reel_les_noms_de_miroirs_sont_ceux_des_catalogues(v)
	_chemin_reel_la_cadence_de_pose_respecte_la_contrainte_du_catalogue(v)
	_chemin_reel_le_dilemme_est_atteignable(v)
	_chemin_reel_la_faim_ecrase_tout_et_la_directive_est_calibree(v)
	_chemin_reel_aucun_etat_parasite_ni_surcout_thermique_au_depart(v)
	_chemin_reel_le_soin_aboutit_et_libere_le_colon(v)
	_chemin_reel_le_combat_finit_avant_que_la_faim_tue(v)

	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_psycho_social -- ecart mesure sur resultats (jamais sur visibles) et dedupliqué par cible, " +
			"stress_interne miroir plat reversible, QUATRE surcouts (effort + thermo + stress + combat) sommes en UNE SEULE " +
			"ecriture de surcout_action, stress gate par l'etat et payant en energie, sigmoide monotone, " +
			"nourriture qui ecrase tout sous le seuil critique, directive ajoutee comme saillance CONCURRENTE " +
			"(obeissance et desobeissance par le poids, gate ecrase_vital par l'etat), veteran qui bascule en " +
			"colere a biais de base EGAL et se rouille sans combat, repas conservatif et borne, " +
			"SOIN conservatif qui coute au soigneur et borne par la capacite, allie gueri qui sort de la " +
			"saillance ET du verbe (les deux retraits, reversibles) et LIBERE le colon -- sur la scene reelle " +
			"il repart vers le feu, la ou il restait plante ; COMBAT qui DETRUIT la vigueur sans la transferer " +
			"(la difference exacte avec le soin), cout reecrit a neuf depuis le nombre de combattants et jamais " +
			"accumule, adversaire reellement vaincu bien avant que la faim morde, " +
			"un domaine invente traverse le meme code, et sur le chemin reel les noms de miroirs correspondent " +
			"aux entrees de seuil, la cadence de pose respecte la contrainte du catalogue, et le dilemme comme " +
			"l'ecrasement sont reellement atteignables sur la scene")
		quit(0)

# ---- Hors domaine ----

func _colon_pose_sans_type_ni_temperature(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	var p: Dictionary = colon.proprietes
	v.v(colon.position == Vector3(330.0, 260.0, 0.0), "le colon doit partir de sa position declaree")
	v.v(colon.position.z == 0.0, "VERTICALITE : position.z doit rester 0.0 (Vector3 partout, meme a plat)")
	v.v(p.has("reserves") and p.reserves.has("seve_zorn"),
		"le canal de reserve doit porter le nom donne en DONNEE, jamais 'energie' en dur")
	v.v(is_equal_approx(float(p.reserves.seve_zorn.reserve), 20.0), "la reserve doit partir a capacite_energie")
	v.v(is_equal_approx(float(p.reserves.seve_zorn.cout_base), 1.0),
		"le metabolisme doit etre pose comme cout_base une fois pour toutes")
	v.v(is_equal_approx(float(p.reserves.seve_zorn.surcout_action), 0.0), "surcout_action doit partir a 0.0")
	v.v(is_equal_approx(float(p.allure_zorn), 10.0), "la vitesse de base doit etre posee sous le nom donne en donnee")
	v.v(not p.has("temperature"),
		"le colon ne doit porter AUCUNE propriete 'temperature' : ce banc n'appelle jamais temperature.gd:avancer, " +
		"et les entrees thermiques d'un catalogue partage doivent rester des chemins morts pour lui")
	v.v(p.get("deformation_sources", []).has("creuse_zorn"),
		"deformation_sources doit declarer la source du banc -- sans elle, Deformation.poser refuse toute ecriture")
	v.v(p.get("deformation_etat", null) is Dictionary and p.deformation_etat.is_empty(),
		"deformation_etat doit partir vide (structurelle, mais aucune exposition encore posee)")
	v.v(p.get("marques_epigenetiques", null) is Dictionary and p.marques_epigenetiques.is_empty(),
		"un colon sans experience de depart ne doit porter AUCUNE marque -- jamais une entree a zero inventee")
	var veteran: Dictionary = Banc.construire_colon("zorn_v", DECL_VETERAN_ZORN, CONFIG_ZORN)
	v.v(is_equal_approx(float(veteran.proprietes.marques_epigenetiques.rixe_zorn.modulateur), 0.40),
		"un colon avec experience de depart doit porter la marque a ce modulateur exact")
	v.v(is_equal_approx(float(veteran.proprietes.biais_combat_base), float(colon.proprietes.biais_combat_base)),
		"LES ARCHETYPES N'EXISTENT PAS : les deux colons doivent avoir le MEME biais de base, seul le vecu les separe")

# LE PIEGE QUE LA LIGNE 9 EXISTE POUR EVITER (constat (F) de l'audit) :
# dominance.gd a DEJA retire de 'visibles' toute entree dont l'ecart au sommet
# depasse seuil_ecrasement. Mesurer l'ecart sur 'visibles' rendrait donc tout
# ecart superieur a ce seuil INVISIBLE -- et le colon serait declare « decire »
# alors qu'il vient justement de trancher net.
func _ecart_mesure_sur_resultats_jamais_sur_visibles(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	var resultats: Array = [
		{"chose": {"id": "a_zorn", "proprietes": {}}, "type": "a", "position": Vector3.ZERO, "saillance": 5.0},
		{"chose": {"id": "b_zorn", "proprietes": {}}, "type": "b", "position": Vector3.ZERO, "saillance": 1.0},
	]
	var visibles: Array = Dominance.visibles(resultats, colon)
	v.v(visibles.size() == 1,
		"pre-requis du cas : avec un ecart (4.0) au-dela de seuil_ecrasement (1.0), dominance.gd ne doit garder qu'une entree")
	v.v(Banc.ecart_deux_plus_hautes(visibles) == INF,
		"sur 'visibles' l'ecart serait INF -- c'est exactement le piege que ce cas verrouille")
	v.v(is_equal_approx(Banc.ecart_deux_plus_hautes(resultats), 4.0),
		"sur 'resultats' l'ecart reel doit valoir 4.0 : c'est la SEULE liste ou il est mesurable")
	v.v(is_equal_approx(Banc.poser_stress_interne(colon, resultats, CONFIG_ZORN), 0.0),
		"un ecart de 4.0 doit donner un stress exactement nul -- le colon a tranche, il n'hesite pas")

func _saillances_dedupliquees_par_cible(v) -> void:
	# Deux entrees pour LA MEME chose (sa saillance naturelle et l'entree
	# synthetique de la directive) : sans deduplication, le colon « hesiterait
	# entre le feu et le feu ».
	var feu := {"id": "brasier_zorn", "proprietes": {}}
	var resultats: Array = [
		{"chose": feu, "type": "brasier", "position": Vector3.ZERO, "saillance": 1.74},
		{"chose": feu, "type": "brasier", "position": Vector3.ZERO, "saillance": 2.5, "directive": true},
		{"chose": {"id": "eclope_zorn", "proprietes": {}}, "type": "eclope", "position": Vector3.ZERO, "saillance": 1.85},
	]
	var cibles: Array = Banc.saillances_par_cible(resultats)
	v.v(cibles.size() == 2, "deux entrees portant la MEME chose ne doivent compter que pour UNE cible")
	v.v(String(cibles[0].cible) == "brasier_zorn" and is_equal_approx(float(cibles[0].saillance), 2.5),
		"la cible dedupliquee doit garder sa saillance la PLUS HAUTE, jamais la premiere rencontree")
	v.v(is_equal_approx(Banc.ecart_deux_plus_hautes(resultats), 0.65),
		"l'ecart doit se mesurer entre deux cibles DISTINCTES (2.5 - 1.85), jamais entre deux entrees de la meme chose")
	# Une entree d'origine ATTACHE ne porte aucune identite de chose (voir
	# attaches.gd) : son type tient lieu d'identite.
	var avec_attache: Array = [
		{"type": "irremplacable", "saillance": 3.0},
		{"type": "notre_ouvrage", "saillance": 1.0},
	]
	v.v(Banc.saillances_par_cible(avec_attache).size() == 2,
		"deux attaches de propriete differente sont deux cibles distinctes, meme sans 'chose'")
	v.v(Banc.ecart_deux_plus_hautes([{"type": "seul", "saillance": 1.0}]) == INF,
		"une seule cible : l'ecart doit valoir INF, jamais 0.0 (qui se lirait comme le conflit maximal)")

func _stress_monte_quand_les_deux_options_sont_proches(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	var monde = _monde_zorn(["brasier_zorn", "eclope_zorn", "pitance_zorn"])
	var r: Dictionary = _decider_zorn(colon, monde, null, CONFIG_ZORN)
	var ecart: float = Banc.ecart_deux_plus_hautes(r.resultats)
	v.v(ecart < float(CONFIG_ZORN.seuil_ecart),
		"pre-requis de la scene : les deux cibles du dilemme doivent etre plus proches que seuil_ecart")
	var stress: float = Banc.poser_stress_interne(colon, r.resultats, CONFIG_ZORN)
	v.v(stress > 0.0, "CONFLIT : deux options trop proches doivent faire monter le stress")
	v.v(is_equal_approx(stress, float(CONFIG_ZORN.seuil_ecart) - ecart),
		"le stress doit valoir EXACTEMENT seuil_ecart - ecart, jamais une grandeur accumulee a cote")
	v.v(is_equal_approx(float(colon.proprietes.tiraillement_zorn), stress),
		"le miroir doit etre pose sous le nom donne en DONNEE, jamais 'stress_interne' en dur")
	# MIROIR PLAT : deux appels au meme etat REECRIVENT la meme valeur, jamais
	# une accumulation -- c'est ce qui rend l'etat reversible sans une ligne.
	Banc.poser_stress_interne(colon, r.resultats, CONFIG_ZORN)
	v.v(is_equal_approx(float(colon.proprietes.tiraillement_zorn), stress),
		"IDEMPOTENCE : le miroir est recalcule a neuf chaque tick, jamais accumule par +=")
	# Et l'etat suit, par le catalogue LOCAL.
	SeuilEtat.avancer([colon], CONFIG_ZORN.seuils_locaux)
	v.v(colon.proprietes.etats_actifs.has("tiraille_zorn"),
		"au-dela du seuil local, l'etat de stress doit etre pose par seuil_etat.gd, jamais a la main")

func _stress_nul_quand_une_option_se_detache(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	# Le brasier retire : il ne reste que l'eclope et une pitance lointaine.
	var monde = _monde_zorn(["eclope_zorn", "pitance_zorn"])
	var r: Dictionary = _decider_zorn(colon, monde, null, CONFIG_ZORN)
	var ecart: float = Banc.ecart_deux_plus_hautes(r.resultats)
	v.v(ecart > float(CONFIG_ZORN.seuil_ecart),
		"pre-requis : une seule option proche doit laisser un ecart au-dela de seuil_ecart")
	v.v(is_equal_approx(Banc.poser_stress_interne(colon, r.resultats, CONFIG_ZORN), 0.0),
		"AUCUN CONFLIT : une option qui se detache doit donner un stress exactement nul")
	# REVERSIBILITE : l'etat pose se retire tout seul au franchissement
	# descendant, sans une ligne de cablage.
	colon.proprietes.etats_actifs = ["tiraille_zorn"]
	SeuilEtat.avancer([colon], CONFIG_ZORN.seuils_locaux)
	v.v(not colon.proprietes.etats_actifs.has("tiraille_zorn"),
		"REVERSIBILITE : le stress retombe, seuil_etat.gd doit RETIRER l'etat de lui-meme")

func _le_stress_consomme_de_l_energie(v) -> void:
	var calme: Dictionary = Banc.construire_colon("zorn_calme", DECL_COLON_ZORN, CONFIG_ZORN)
	var tiraille: Dictionary = Banc.construire_colon("zorn_tiraille", DECL_COLON_ZORN, CONFIG_ZORN)
	tiraille.proprietes[String(CONFIG_ZORN.nom_stress_interne)] = 0.5
	tiraille.proprietes.etats_actifs = ["tiraille_zorn"]
	# Le calme porte le MEME miroir : seule la presence de l'ETAT doit changer
	# quelque chose -- c'est tout le role du marqueur pur.
	calme.proprietes[String(CONFIG_ZORN.nom_stress_interne)] = 0.5
	v.v(is_equal_approx(Banc.surcout_stress(calme, CONFIG_ZORN), 0.0),
		"GATE PAR L'ETAT : un stress qui n'a pas franchi son seuil ne coute RIEN, meme miroir non nul")
	v.v(is_equal_approx(Banc.surcout_stress(tiraille, CONFIG_ZORN), 2.0),
		"une fois l'etat pose, le stress doit couter coef_stress x miroir (4.0 x 0.5)")
	Banc.poser_surcout_action(calme, 100.0, false, CONFIG_ZORN)
	Banc.poser_surcout_action(tiraille, 100.0, false, CONFIG_ZORN)
	var monde: Array = [calme, tiraille]
	Depense.avancer(monde, 1.0)
	v.v(float(tiraille.proprietes.reserves.seve_zorn.reserve) < float(calme.proprietes.reserves.seve_zorn.reserve),
		"L'HESITATION COUTE : a effort et temperature egaux, le colon stresse doit avoir moins d'energie")

# LE PIEGE DE CE CHANTIER (constat (C) de l'audit) : un seul emplacement
# surcout_action, QUATRE contributions depuis que le combat coute. Si un morceau
# de cablage ecrivait le sien apres un autre, le total vaudrait l'un des quatre
# au lieu de leur somme -- en silence, sans qu'aucun test ne rougisse. Le
# quatrieme terme a ete AJOUTE a cette fonction plutot que de recevoir son propre
# point d'ecriture : c'est la contre-epreuve vivante du patron.
func _les_quatre_surcouts_se_somment_en_une_seule_ecriture(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	colon.proprietes["velocite"] = Vector3(6.0, 8.0, 0.0)
	colon.proprietes[String(CONFIG_ZORN.nom_stress_interne)] = 0.5
	colon.proprietes.etats_actifs = ["tiraille_zorn"]
	var d: Dictionary = Banc.poser_surcout_action(colon, 90.0, true, CONFIG_ZORN)
	v.v(is_equal_approx(float(d.effort), 5.0), "EFFORT : coef_effort (0.5) x longueur de la velocite (10) = 5.0")
	v.v(is_equal_approx(float(d.froid), 10.0), "FROID RESSENTI : 10 degres sous le confort, sous le nom donne en donnee")
	v.v(is_equal_approx(float(d.thermo), 30.0), "THERMO : 10 degres x cout_par_degre_froid (3.0) = 30.0")
	v.v(is_equal_approx(float(d.stress), 2.0), "STRESS : coef_stress (4.0) x miroir (0.5) = 2.0")
	v.v(is_equal_approx(float(d.combat), 3.0), "COMBAT : cout_energie_combat_par_s (3.0), pose des que le colon est au contact")
	var pose: float = float(colon.proprietes.reserves.seve_zorn.surcout_action)
	v.v(is_equal_approx(pose, 40.0),
		"SOMME : surcout_action doit valoir effort (5.0) + thermo (30.0) + stress (2.0) + combat (3.0) = 40.0, " +
		"jamais l'un des quatre seul")
	v.v(is_equal_approx(pose, float(d.total)), "le total rendu doit etre EXACTEMENT ce qui a ete ecrit dans le canal")
	# HORS COMBAT, le quatrieme terme disparait -- il ne reste jamais colle.
	var hors: Dictionary = Banc.poser_surcout_action(colon, 90.0, false, CONFIG_ZORN)
	v.v(is_equal_approx(float(hors.combat), 0.0) and is_equal_approx(float(hors.total), 37.0),
		"REVERSIBLE : hors contact, le terme de combat retombe a 0.0 et le total revient a 37.0")
	Banc.poser_surcout_action(colon, 90.0, true, CONFIG_ZORN)
	v.v(is_equal_approx(float(colon.proprietes.reserves.seve_zorn.surcout_action), 40.0),
		"IDEMPOTENCE : deux appels au meme etat doivent reecrire la meme valeur, jamais s'additionner")
	v.v(is_equal_approx(float(colon.proprietes.brulure_zorn), 0.0),
		"les deux miroirs thermiques ne doivent jamais etre non nuls ensemble (seuil_chaud >= temp_cible)")

func _la_sigmoide_monte_quand_la_reserve_descend(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	var canal: Dictionary = colon.proprietes.reserves.seve_zorn
	var precedent := -1.0
	var monotone := true
	for i in range(21):
		canal["reserve"] = 20.0 * (1.0 - float(i) / 20.0)
		var u: float = Banc.urgence_faim(colon, CONFIG_ZORN)
		if u <= precedent:
			monotone = false
		precedent = u
	v.v(monotone, "SIGMOIDE : l'urgence doit monter STRICTEMENT a chaque cran ou la reserve descend")
	canal["reserve"] = 20.0
	v.v(Banc.urgence_faim(colon, CONFIG_ZORN) < 0.01, "reserve pleine : l'urgence doit etre quasi nulle")
	canal["reserve"] = 20.0 * float(CONFIG_ZORN.seuil_critique_ratio)
	v.v(is_equal_approx(Banc.urgence_faim(colon, CONFIG_ZORN), 0.5),
		"AU SEUIL CRITIQUE EXACT : l'urgence doit valoir exactement 0.5 -- c'est la definition du point d'inflexion")
	canal["reserve"] = 0.0
	v.v(Banc.urgence_faim(colon, CONFIG_ZORN) > 0.99, "reserve vide : l'urgence doit etre quasi maximale")
	# La deformation posee est PROPORTIONNELLE AU DELTA : sans ce facteur, le
	# biais monterait a une vitesse dependant de la machine.
	v.v(is_equal_approx(Banc.poser_deformation_faim(colon, 1.0, 0.5, CONFIG_ZORN, DEFORMATIONS_ZORN), 2.0),
		"la magnitude posee doit valoir gain (4.0) x urgence x delta, jamais un montant fixe par image")
	v.v(is_equal_approx(Banc.poser_deformation_faim(colon, 0.0, 0.5, CONFIG_ZORN, DEFORMATIONS_ZORN), 0.0),
		"urgence nulle : RIEN ne doit etre pose (jamais une ecriture a zero qui creerait le canal pour rien)")

# LE COEUR DE LA LIGNE 10 : la nourriture, ignoree tant que le colon n'a pas
# faim, devient le sommet PUIS ecrase tout le reste -- sans une seule ligne
# neuve, c'est dominance.gd qui retire les autres options de la liste.
func _sous_le_seuil_critique_la_nourriture_ecrase_tout(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	var monde = _monde_zorn(["brasier_zorn", "eclope_zorn", "pitance_zorn"])

	var avant: Dictionary = _decider_zorn(colon, monde, null, CONFIG_ZORN)
	var cibles_avant: Array = Banc.saillances_par_cible(avant.resultats)
	v.v(String(cibles_avant[0].cible) != "pitance_zorn",
		"REPOS : reserve pleine, la nourriture ne doit PAS etre la cible la plus saillante")
	v.v(not _visibles_contient(avant.visibles, "pitance_zorn"),
		"REPOS : la nourriture lointaine doit meme etre ECRASEE par dominance.gd -- le colon ne la considere pas")

	# La reserve descend sous le seuil critique, et la sigmoide travaille.
	colon.proprietes.reserves.seve_zorn["reserve"] = 20.0 * 0.2
	for i in range(400):
		Banc.poser_deformation_faim(colon, Banc.urgence_faim(colon, CONFIG_ZORN), 0.05, CONFIG_ZORN, DEFORMATIONS_ZORN)
		Deformation.avancer(colon, 0.05, DEFORMATIONS_ZORN)

	var biais: float = Deformation.biais(colon, "creuse_zorn", "croquable_zorn", DEFORMATIONS_ZORN)
	v.v(biais > 3.0, "la deformation doit avoir reellement accumule un biais fort a urgence quasi maximale")
	# LE PLAFOND, ET POURQUOI IL EST OBLIGATOIRE (resultat negatif de ce
	# chantier) : deformation.gd decroit par SOUSTRACTION FIXE, il n'existe aucun
	# equilibre naturel -- sans ce plafond de cablage, vingt secondes a urgence
	# quasi maximale portaient le biais a ~58 et il mettait plus de deux minutes
	# a redescendre. La marge d'une magnitude de tick est normale : la pose
	# s'arrete AU plafond, elle ne le rabote pas.
	v.v(biais < float(CONFIG_ZORN.plafond_biais_faim) + 0.5,
		"PLAFOND : le biais doit rester borne par plafond_biais_faim -- sans lui il monte LINEAIREMENT et sans borne")
	var apres: Dictionary = _decider_zorn(colon, monde, null, CONFIG_ZORN)
	var cibles_apres: Array = Banc.saillances_par_cible(apres.resultats)
	v.v(String(cibles_apres[0].cible) == "pitance_zorn",
		"FAIM CRITIQUE : la nourriture doit devenir la cible la plus saillante")
	v.v(apres.visibles.size() == 1 and _visibles_contient(apres.visibles, "pitance_zorn"),
		"ECRASEMENT : tout le reste doit SORTIR de la liste -- dominance.gd les retire, ils ne sont pas " +
		"« moins prioritaires », ils n'existent plus")
	v.v(apres.decision != null and String(apres.decision.action) == "gober_zorn",
		"LE COLON MANGE QUOI QU'ON DISE : le verbe resolu doit etre celui de la nourriture")
	# REVERSIBILITE : rassasie, le biais retombe et le dilemme revient.
	colon.proprietes.reserves.seve_zorn["reserve"] = 20.0
	for i in range(400):
		Banc.poser_deformation_faim(colon, Banc.urgence_faim(colon, CONFIG_ZORN), 0.05, CONFIG_ZORN, DEFORMATIONS_ZORN)
		Deformation.avancer(colon, 0.05, DEFORMATIONS_ZORN)
	v.v(Deformation.biais(colon, "creuse_zorn", "croquable_zorn", DEFORMATIONS_ZORN) < 0.1,
		"REVERSIBILITE : rassasie, le biais doit retomber -- sinon le banc ne reviendrait jamais au dilemme")
	var rassasie: Dictionary = _decider_zorn(colon, monde, null, CONFIG_ZORN)
	v.v(String(Banc.saillances_par_cible(rassasie.resultats)[0].cible) != "pitance_zorn",
		"REVERSIBILITE : rassasie, la nourriture doit redevenir une option parmi d'autres")

func _la_directive_ajoute_une_saillance_synthetique(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	var monde = _monde_zorn(["brasier_zorn", "eclope_zorn", "pitance_zorn"])
	var cible: Dictionary = _chose_zorn("brasier_zorn")
	var sans: Dictionary = _decider_zorn(colon, monde, null, CONFIG_ZORN)
	var avec: Dictionary = _decider_zorn(colon, monde, cible, CONFIG_ZORN)
	v.v(avec.resultats.size() == sans.resultats.size() + 1,
		"la directive doit AJOUTER exactement une entree a 'resultats', jamais en modifier une existante")
	var trouvee = null
	for entree in avec.resultats:
		if bool(entree.get("directive", false)):
			trouvee = entree
	v.v(trouvee != null, "l'entree synthetique doit etre marquee, pour qu'on sache POURQUOI le colon a choisi")
	if trouvee != null:
		v.v(is_equal_approx(float(trouvee.saillance), float(CONFIG_ZORN.directive.bonus_score)),
			"la saillance synthetique doit valoir exactement bonus_score")
		v.v(trouvee.chose.id == "brasier_zorn" and trouvee.position == cible.position,
			"l'entree doit porter la chose visee et sa position -- c'est une saillance concurrente, pas un ordre abstrait")
	# Aucune saillance existante n'est touchee : l'ordre AJOUTE, il ne regle rien.
	var naturelle_sans := _saillance_de(sans.resultats, "brasier_zorn")
	var naturelle_avec := -1.0
	for entree in avec.resultats:
		if not bool(entree.get("directive", false)) and entree.get("chose", {}).get("id", "") == "brasier_zorn":
			naturelle_avec = float(entree.saillance)
	v.v(is_equal_approx(naturelle_sans, naturelle_avec),
		"UN ORDRE NE SUPPRIME NI NE MODIFIE AUCUNE SAILLANCE (docs/design.md) : la saillance naturelle du feu " +
		"doit rester rigoureusement inchangee")

func _le_colon_obeit_si_la_directive_pese_plus(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	var monde = _monde_zorn(["brasier_zorn", "eclope_zorn", "pitance_zorn"])
	var sans: Dictionary = _decider_zorn(colon, monde, null, CONFIG_ZORN)
	v.v(sans.decision != null and sans.decision.chose.id == "eclope_zorn",
		"pre-requis de la scene : SANS directive, le colon doit choisir l'autre cible (sinon l'obeissance ne se verrait pas)")
	var avec: Dictionary = _decider_zorn(colon, monde, _chose_zorn("brasier_zorn"), CONFIG_ZORN)
	v.v(avec.decision != null and avec.decision.chose.id == "brasier_zorn",
		"OBEISSANCE : le bonus depassant le sommet naturel, le colon doit changer de cible")
	v.v(bool(avec.decision.get("directive", false)),
		"l'entree RETENUE doit etre la synthetique -- c'est la preuve qu'il obeit a l'ordre, pas a sa propre saillance")
	v.v(String(avec.decision.action) == "approcher_zorn",
		"le verbe reste resolu par la PROPRIETE de la chose visee, jamais impose par la directive")

func _le_colon_desobeit_si_son_besoin_pese_plus(v) -> void:
	# ecrase_vital = 1 : la directive est TOUJOURS ajoutee. La desobeissance
	# testee ici est donc celle du POIDS SEUL, jamais celle du gate.
	var config: Dictionary = CONFIG_ZORN.duplicate(true)
	config.directive["ecrase_vital"] = 1
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, config)
	var monde = _monde_zorn(["brasier_zorn", "eclope_zorn", "pitance_zorn"])
	colon.proprietes.reserves.seve_zorn["reserve"] = 20.0 * 0.2
	colon.proprietes.etats_actifs = ["creve_zorn"]
	for i in range(400):
		Banc.poser_deformation_faim(colon, Banc.urgence_faim(colon, config), 0.05, config, DEFORMATIONS_ZORN)
		Deformation.avancer(colon, 0.05, DEFORMATIONS_ZORN)
	var r: Dictionary = _decider_zorn(colon, monde, _chose_zorn("brasier_zorn"), config)
	var a_l_entree := false
	for entree in r.resultats:
		if bool(entree.get("directive", false)):
			a_l_entree = true
	v.v(a_l_entree,
		"pre-requis : avec ecrase_vital non nul, l'entree doit etre ajoutee MEME sous besoin critique")
	v.v(r.decision != null and r.decision.chose.id == "pitance_zorn",
		"DESOBEISSANCE PAR LE POIDS : le besoin pesant plus que l'ordre, le colon doit aller manger")
	v.v(not bool(r.decision.get("directive", false)),
		"l'entree retenue ne doit PAS etre la synthetique -- aucun cas particulier, dominance/agir ont arbitre")

func _ecrase_vital_empeche_la_directive_sous_besoin_critique(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	var cible: Dictionary = _chose_zorn("brasier_zorn")
	v.v(Banc.directive_autorisee(colon, CONFIG_ZORN),
		"sans etat vital actif, la directive doit etre autorisee")
	v.v(Banc.entree_directive(colon, cible, CONFIG_ZORN) != null, "et l'entree doit donc etre construite")
	colon.proprietes.etats_actifs = ["creve_zorn"]
	v.v(not Banc.directive_autorisee(colon, CONFIG_ZORN),
		"GATE PAR ETAT : un etat vital actif doit fermer la directive (ecrase_vital = 0)")
	v.v(Banc.entree_directive(colon, cible, CONFIG_ZORN) == null,
		"l'entree ne doit MEME PAS etre construite -- pas ajoutee puis perdante, absente")
	var monde = _monde_zorn(["brasier_zorn", "eclope_zorn"])
	var r: Dictionary = _decider_zorn(colon, monde, cible, CONFIG_ZORN)
	for entree in r.resultats:
		v.v(not bool(entree.get("directive", false)),
			"aucune entree de directive ne doit figurer dans 'resultats' quand le gate est ferme")
	v.v(Banc.entree_directive(colon, null, CONFIG_ZORN) == null,
		"cible absente de la scene : aucune entree, jamais une saillance pointant vers rien")

func _le_veteran_bifurque_vers_colere_plus_facilement(v) -> void:
	var novice: Dictionary = Banc.construire_colon("zorn_novice", DECL_COLON_ZORN, CONFIG_ZORN)
	var veteran: Dictionary = Banc.construire_colon("zorn_veteran", DECL_VETERAN_ZORN, CONFIG_ZORN)
	var au_combat := {"action": "charger_zorn"}
	# LE GATE, verrouille en premier -- DEFAUT REEL trouve en lancant la scene
	# (voir poser_ardeur_combat) : ecrit inconditionnellement, ce miroir mettait
	# le veteran en colere des le premier tick SANS AUCUN ADVERSAIRE, et comme
	# combat_en_cours lit cet etat, il accumulait de l'experience en permanence
	# et ne se rouillait jamais. Le test seul ne l'avait pas vu.
	v.v(is_equal_approx(Banc.poser_ardeur_combat(veteran, null, CONFIG_ZORN), 0.0),
		"HORS COMBAT : l'ardeur doit valoir exactement 0.0, meme pour un veteran charge d'experience")
	v.v(is_equal_approx(Banc.poser_ardeur_combat(veteran, {"action": "gober_zorn"}, CONFIG_ZORN), 0.0),
		"un verbe qui n'est pas celui du combat ne doit reveiller aucune ardeur")
	SeuilEtat.avancer([veteran], CONFIG_ZORN.seuils_locaux)
	v.v(not veteran.proprietes.etats_actifs.has("furie_zorn"),
		"HORS COMBAT : aucune colere ne doit etre posee -- sinon le veteran serait furieux devant un plat de soupe")

	v.v(is_equal_approx(Banc.poser_ardeur_combat(novice, au_combat, CONFIG_ZORN), 0.20),
		"au combat et sans marque, l'ardeur doit valoir le seul biais de base")
	v.v(is_equal_approx(Banc.poser_ardeur_combat(veteran, au_combat, CONFIG_ZORN), 0.60),
		"au combat et avec marque, l'ardeur doit valoir biais de base + modulateur")
	SeuilEtat.avancer([novice, veteran], CONFIG_ZORN.seuils_locaux)
	v.v(veteran.proprietes.etats_actifs.has("furie_zorn"),
		"LE VETERAN BIFURQUE : a biais de base EGAL, son experience seule lui fait franchir le seuil")
	v.v(not novice.proprietes.etats_actifs.has("furie_zorn"),
		"LE NOVICE NON : meme scene, meme base, il n'a simplement rien vecu")

	# Le novice combat : il finit par y arriver, et pas avant.
	var ticks := 0
	while ticks < 400 and not novice.proprietes.etats_actifs.has("furie_zorn"):
		Banc.avancer_experience(novice, true, 0.05, CONFIG_ZORN, EPIGENETIQUE_ZORN)
		Banc.poser_ardeur_combat(novice, au_combat, CONFIG_ZORN)
		SeuilEtat.avancer([novice], CONFIG_ZORN.seuils_locaux)
		ticks += 1
	v.v(novice.proprietes.etats_actifs.has("furie_zorn"),
		"APPRENTISSAGE : le novice qui combat doit finir par basculer lui aussi")
	v.v(ticks > 1, "et jamais des le premier tick -- sinon l'experience n'aurait rien change")

	# LE PLAFOND VIT AU CABLAGE : poser() n'en a aucun.
	for i in range(2000):
		Banc.avancer_experience(novice, true, 0.05, CONFIG_ZORN, EPIGENETIQUE_ZORN)
	v.v(is_equal_approx(Banc.modulateur_experience(novice, CONFIG_ZORN), float(CONFIG_ZORN.plafond_modification)),
		"PLAFOND : le modulateur lu par le cablage doit etre borne par plafond_modification, jamais par le mecanisme")
	v.v(float(novice.proprietes.marques_epigenetiques.rixe_zorn.modulateur) > float(CONFIG_ZORN.plafond_modification),
		"et la marque BRUTE doit bien avoir depasse ce plafond -- la preuve que la borne est cote cablage")

func _l_experience_decroit_sans_combat(v) -> void:
	var veteran: Dictionary = Banc.construire_colon("zorn_veteran", DECL_VETERAN_ZORN, CONFIG_ZORN)
	var depart: float = Banc.modulateur_experience(veteran, CONFIG_ZORN)
	for i in range(100):
		Banc.avancer_experience(veteran, false, 0.05, CONFIG_ZORN, EPIGENETIQUE_ZORN)
	var apres: float = Banc.modulateur_experience(veteran, CONFIG_ZORN)
	v.v(apres < depart, "LE VETERAN SE ROUILLE : sans combat, le modulateur doit decroitre")
	v.v(is_equal_approx(apres, depart - 0.01 * 5.0),
		"la decroissance doit valoir EXACTEMENT taux_decroissance x temps ecoule (soustraction fixe, pas une fraction)")
	# Jusqu'a disparition complete de l'entree (plancher_suppression).
	for i in range(2000):
		Banc.avancer_experience(veteran, false, 0.05, CONFIG_ZORN, EPIGENETIQUE_ZORN)
	v.v(not veteran.proprietes.marques_epigenetiques.has("rixe_zorn"),
		"sous son plancher, epigenetique.gd doit RETIRER l'entree -- jamais un residu quasi nul qui s'accumule")
	v.v(is_equal_approx(Banc.modulateur_experience(veteran, CONFIG_ZORN), 0.0),
		"marque absente : le cablage doit lire 0.0, jamais alarmer ni inventer une entree")
	# CADENCE : poser par intervalle, jamais a chaque image.
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	var r: Dictionary = Banc.avancer_experience(colon, true, 0.05, CONFIG_ZORN, EPIGENETIQUE_ZORN)
	v.v(int(r.poses) == 0, "CADENCE : un tick plus court que l'intervalle ne doit poser AUCUNE marque")
	var total := 0
	for i in range(5):
		total += int(Banc.avancer_experience(colon, true, 0.05, CONFIG_ZORN, EPIGENETIQUE_ZORN).poses)
	v.v(total == 1, "CADENCE : exactement une pose une fois l'intervalle (0.25 s) accumule, jamais une par image")
	# Sortir du combat remet l'horloge a zero : un colon qui alterne des
	# fractions de seconde ne doit pas accumuler un intervalle jamais tenu.
	Banc.avancer_experience(colon, true, 0.2, CONFIG_ZORN, EPIGENETIQUE_ZORN)
	Banc.avancer_experience(colon, false, 0.01, CONFIG_ZORN, EPIGENETIQUE_ZORN)
	v.v(is_equal_approx(float(colon.proprietes[Banc.CLE_HORLOGE_MARQUE]), 0.0),
		"hors combat, l'horloge de pose doit etre remise a zero, jamais gelee")
	# combat_en_cours : les DEUX conditions, sans priorite entre elles.
	v.v(Banc.combat_en_cours(colon, {"action": "charger_zorn"}, CONFIG_ZORN),
		"le verbe resolu doit suffire a declarer le combat")
	v.v(not Banc.combat_en_cours(colon, {"action": "gober_zorn"}, CONFIG_ZORN),
		"un autre verbe ne doit jamais declarer le combat")
	v.v(not Banc.combat_en_cours(colon, null, CONFIG_ZORN),
		"aucune decision et aucune colere : pas de combat, jamais une alarme")
	colon.proprietes.etats_actifs = ["furie_zorn"]
	v.v(Banc.combat_en_cours(colon, null, CONFIG_ZORN),
		"l'etat de colere doit suffire, meme sans decision -- il fait durer l'accumulation")

func _le_repas_est_conservatif_et_borne(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	var repas: Dictionary = _chose_zorn("pitance_zorn")
	colon.proprietes.reserves.seve_zorn["reserve"] = 5.0
	colon.position = repas.position
	var avant_total: float = 5.0 + 300.0
	var q: float = Banc.manger_si_possible(colon, {"action": "gober_zorn"}, repas, 0.1, CONFIG_ZORN)
	v.v(q > 0.0, "a portee et avec le bon verbe, le repas doit transferer quelque chose")
	v.v(is_equal_approx(float(colon.proprietes.reserves.seve_zorn.reserve)
		+ float(repas.proprietes.reserves.pulpe_zorn.reserve), avant_total),
		"CONSERVATION : ce que le colon gagne, la nourriture doit l'avoir perdu, exactement")
	# BORNE HAUTE AU CABLAGE : rien dans le coeur ne borne le haut d'une reserve,
	# et ecreter APRES transfert detruirait de la matiere deja retiree.
	for i in range(200):
		Banc.manger_si_possible(colon, {"action": "gober_zorn"}, repas, 0.1, CONFIG_ZORN)
	v.v(float(colon.proprietes.reserves.seve_zorn.reserve) <= 20.0 + 0.0001,
		"la reserve ne doit JAMAIS depasser la capacite -- le taux est pre-borne, jamais ecrete apres coup")
	v.v(is_equal_approx(float(colon.proprietes.reserves.seve_zorn.reserve)
		+ float(repas.proprietes.reserves.pulpe_zorn.reserve), avant_total),
		"CONSERVATION apres saturation : aucune matiere ne doit avoir disparu")
	# Les trois gates.
	colon.proprietes.reserves.seve_zorn["reserve"] = 5.0
	v.v(is_equal_approx(Banc.manger_si_possible(colon, {"action": "approcher_zorn"}, repas, 0.1, CONFIG_ZORN), 0.0),
		"mauvais verbe : aucun transfert")
	colon.position = Vector3(0.0, 0.0, 0.0)
	v.v(is_equal_approx(Banc.manger_si_possible(colon, {"action": "gober_zorn"}, repas, 0.1, CONFIG_ZORN), 0.0),
		"hors de portee : aucun transfert")
	v.v(is_equal_approx(Banc.manger_si_possible(colon, null, repas, 0.1, CONFIG_ZORN), 0.0),
		"aucune decision : aucun transfert, jamais une alarme")

# LE SOIN EST LE REPAS DANS L'AUTRE SENS -- le colon est la SOURCE. Ce que
# l'allie gagne, le colon doit l'avoir perdu, exactement : c'est ce qui fait que
# soigner rapproche la faim critique.
func _le_soin_est_conservatif_et_coute_au_soigneur(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	var eclope: Dictionary = _chose_zorn("eclope_zorn")
	colon.position = eclope.position
	var energie_avant: float = float(colon.proprietes.reserves.seve_zorn.reserve)
	var total_avant: float = energie_avant + 30.0
	var q: float = Banc.soigner_si_possible(colon, {"action": "rafistoler_zorn"}, eclope, 0.1, CONFIG_ZORN)
	v.v(q > 0.0, "a portee et avec le bon verbe, le soin doit transferer quelque chose")
	v.v(float(colon.proprietes.reserves.seve_zorn.reserve) < energie_avant,
		"LE SOIN COUTE : l'energie du soigneur doit avoir baisse -- une sante qui sortirait du neant ne relierait rien")
	v.v(is_equal_approx(float(colon.proprietes.reserves.seve_zorn.reserve)
		+ float(eclope.proprietes.reserves.seve_vitale_zorn.reserve), total_avant),
		"CONSERVATION : ce que l'allie gagne, le colon doit l'avoir perdu, exactement")
	# Les trois gates, MEME forme que le repas.
	v.v(is_equal_approx(Banc.soigner_si_possible(colon, {"action": "gober_zorn"}, eclope, 0.1, CONFIG_ZORN), 0.0),
		"mauvais verbe : aucun soin")
	colon.position = Vector3(0.0, 0.0, 0.0)
	v.v(is_equal_approx(Banc.soigner_si_possible(colon, {"action": "rafistoler_zorn"}, eclope, 0.1, CONFIG_ZORN), 0.0),
		"hors de portee : aucun soin")
	v.v(is_equal_approx(Banc.soigner_si_possible(colon, null, eclope, 0.1, CONFIG_ZORN), 0.0),
		"aucune decision : aucun soin, jamais une alarme")
	v.v(is_equal_approx(Banc.soigner_si_possible(colon, {"action": "rafistoler_zorn"}, null, 0.1, CONFIG_ZORN), 0.0),
		"aucune cible : aucun soin, jamais une alarme")

# LA BORNE HAUTE EST AU CABLAGE (pre-bornage du taux), jamais un ecretage apres
# coup : ecreter apres transfert detruirait de l'energie deja retiree au colon.
func _le_soin_est_borne_par_la_capacite(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	var eclope: Dictionary = _chose_zorn("eclope_zorn")
	colon.position = eclope.position
	colon.proprietes.reserves.seve_zorn["reserve"] = 100000.0
	var total_avant: float = 100000.0 + 30.0
	for i in range(500):
		Banc.soigner_si_possible(colon, {"action": "rafistoler_zorn"}, eclope, 0.1, CONFIG_ZORN)
	v.v(float(eclope.proprietes.reserves.seve_vitale_zorn.reserve) <= 100.0 + 0.0001,
		"la sante ne doit JAMAIS depasser la capacite -- le taux est pre-borne, jamais ecrete apres coup")
	v.v(is_equal_approx(float(colon.proprietes.reserves.seve_zorn.reserve)
		+ float(eclope.proprietes.reserves.seve_vitale_zorn.reserve), total_avant),
		"CONSERVATION apres saturation : aucune matiere ne doit avoir disparu")

# LES DEUX RETRAITS, ET LA PREUVE QU'IL FAUT LES DEUX : l'un sort la chose de la
# SAILLANCE (proximite.gd), l'autre du VERBE (agir.gd). Plus la reversibilite.
func _l_allie_gueri_sort_de_la_saillance_et_du_verbe(v) -> void:
	var eclope: Dictionary = _chose_zorn("eclope_zorn")
	v.v(not Banc.mettre_a_jour_guerison(eclope, CONFIG_ZORN),
		"a 30 de sante sur 100, l'allie n'est pas gueri")
	v.v(eclope.proprietes.has("eclope_zorn") and eclope.proprietes.has("profil_saillance"),
		"tant qu'il est blesse, il garde sa propriete de blessure ET sa saillance")

	eclope.proprietes.reserves.seve_vitale_zorn["reserve"] = 100.0
	v.v(Banc.mettre_a_jour_guerison(eclope, CONFIG_ZORN), "a capacite pleine, l'allie doit etre gueri")
	v.v(not eclope.proprietes.has("eclope_zorn"),
		"LE VERBE : sans retrait de la propriete de blessure, agir.gd:_action resoudrait encore le verbe de soin")
	v.v(not eclope.proprietes.has("profil_saillance"),
		"LA SAILLANCE : sans gel du profil, proximite.gd le rendrait encore saillant et le colon resterait plante")
	v.v(String(eclope.proprietes.get("profil_saillance_gele", "")) == "plaie_zorn",
		"GELE, jamais efface : la valeur doit etre conservee pour pouvoir revenir")

	# REVERSIBLE PAR CONSTRUCTION (patron banc_p1.gd:mettre_a_jour_occupation).
	eclope.proprietes.reserves.seve_vitale_zorn["reserve"] = 40.0
	v.v(not Banc.mettre_a_jour_guerison(eclope, CONFIG_ZORN), "sante retombee : l'allie n'est plus gueri")
	v.v(eclope.proprietes.has("eclope_zorn")
		and String(eclope.proprietes.get("profil_saillance", "")) == "plaie_zorn"
		and not eclope.proprietes.has("profil_saillance_gele"),
		"tout doit revenir a l'identique -- le gel n'est jamais une perte")
	v.v(not Banc.mettre_a_jour_guerison(null, CONFIG_ZORN),
		"aucune cible : jamais une alarme, jamais un gueri invente")

# CE QUE LE CHANTIER EXISTE POUR CORRIGER, verrouille : avant le soin, le colon
# arrivait sur l'allie et y restait indefiniment. Une fois l'allie gueri, il doit
# CHANGER DE CIBLE -- c'est la seule preuve qui compte, et elle passe par les
# quatre couches reelles, jamais par une lecture de propriete.
func _l_allie_gueri_libere_le_colon(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	# Monde construit ICI plutot que par _monde_zorn : le cas a besoin de garder
	# la reference sur l'eclope pour le guerir EN PLACE, dans le monde meme que
	# les couches vont relire.
	var eclope: Dictionary = _chose_zorn("eclope_zorn")
	var brasier: Dictionary = _chose_zorn("brasier_zorn")
	var monde = Monde.new()
	monde.ajouter(eclope, "eclope", eclope.position)
	monde.ajouter(brasier, "brasier", brasier.position)
	var avant: Dictionary = _decider_zorn(colon, monde, null, CONFIG_ZORN)
	v.v(avant.decision != null and avant.decision.chose.id == "eclope_zorn",
		"CALIBRATION : blesse, l'allie doit etre la cible choisie")

	eclope.proprietes.reserves.seve_vitale_zorn["reserve"] = 100.0
	Banc.mettre_a_jour_guerison(eclope, CONFIG_ZORN)
	var apres: Dictionary = _decider_zorn(colon, monde, null, CONFIG_ZORN)
	v.v(apres.decision != null and apres.decision.chose.id == "brasier_zorn",
		"GUERI, LE COLON REPART : la cible doit changer -- c'est exactement ce qui manquait, le colon restait plante")
	v.v(not _visibles_contient(apres.visibles, "eclope_zorn"),
		"l'allie gueri ne doit plus figurer parmi les visibles")
	v.v(Banc.ecart_deux_plus_hautes(apres.resultats) == INF,
		"une seule cible restante : l'ecart est INF, donc aucun conflit -- un colon qui n'a qu'une option n'hesite pas")

# LE COMBAT DETRUIT, IL NE TRANSFERE PAS -- c'est la difference exacte avec le
# soin, et elle se verifie : la vigueur perdue ne doit se retrouver NULLE PART.
func _le_combat_detruit_la_vigueur_sans_la_transferer(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	var rival: Dictionary = _chose_zorn("rival_zorn")
	colon.position = rival.position
	var energie_avant: float = float(colon.proprietes.reserves.seve_zorn.reserve)
	var decisions := {colon.id: {"action": "charger_zorn"}}
	var cout: float = Banc.poser_cout_combat(rival, [colon], decisions, CONFIG_ZORN)
	v.v(is_equal_approx(cout, 15.0), "UN combattant au contact doit poser cout_combat_par_s (15.0)")
	Depense.avancer([rival], 1.0)
	v.v(is_equal_approx(float(rival.proprietes.reserves.hargne_zorn.reserve), 85.0),
		"la vigueur doit descendre de 15.0 en une seconde")
	v.v(is_equal_approx(float(colon.proprietes.reserves.seve_zorn.reserve), energie_avant),
		"LA VIGUEUR NE VA NULLE PART : combattre ne doit RIEN crediter au colon -- un combat detruit, il ne nourrit pas")

# LE COUT EST REECRIT A NEUF, jamais accumule : deux colons qui arrivent puis
# repartent laisseraient sinon un cout fantome qui viderait l'adversaire tout
# seul -- defaut silencieux, aucun test ne rougirait.
func _le_cout_de_combat_est_reecrit_a_neuf_chaque_appel(v) -> void:
	var a: Dictionary = Banc.construire_colon("zorn_a", DECL_COLON_ZORN, CONFIG_ZORN)
	var b: Dictionary = Banc.construire_colon("zorn_b", DECL_COLON_ZORN, CONFIG_ZORN)
	var rival: Dictionary = _chose_zorn("rival_zorn")
	a.position = rival.position
	b.position = rival.position
	var deux := {a.id: {"action": "charger_zorn"}, b.id: {"action": "charger_zorn"}}
	v.v(is_equal_approx(Banc.poser_cout_combat(rival, [a, b], deux, CONFIG_ZORN), 30.0),
		"DEUX combattants doivent poser deux fois le cout -- a deux on vient a bout plus vite")
	# Les deux s'eloignent : le cout doit retomber a ZERO, jamais rester colle.
	a.position = Vector3(0.0, 0.0, 0.0)
	b.position = Vector3(0.0, 0.0, 0.0)
	v.v(is_equal_approx(Banc.poser_cout_combat(rival, [a, b], deux, CONFIG_ZORN), 0.0),
		"REECRIT A NEUF : les combattants partis, le cout doit retomber a 0.0 -- jamais un cout fantome")
	v.v(is_equal_approx(float(rival.proprietes.reserves.hargne_zorn.cout_base), 0.0),
		"le canal lui-meme doit porter 0.0, pas seulement la valeur rendue")
	# Les trois gates de combat_au_contact.
	a.position = rival.position
	v.v(Banc.combat_au_contact(a, {"action": "charger_zorn"}, rival, CONFIG_ZORN), "au contact avec le bon verbe : vrai")
	v.v(not Banc.combat_au_contact(a, {"action": "rafistoler_zorn"}, rival, CONFIG_ZORN), "mauvais verbe : faux")
	v.v(not Banc.combat_au_contact(a, null, rival, CONFIG_ZORN), "aucune decision : faux, jamais une alarme")
	v.v(not Banc.combat_au_contact(a, {"action": "charger_zorn"}, null, CONFIG_ZORN), "aucune cible : faux")
	a.position = Vector3(0.0, 0.0, 0.0)
	v.v(not Banc.combat_au_contact(a, {"action": "charger_zorn"}, rival, CONFIG_ZORN),
		"VISER DE LOIN N'EST PAS COMBATTRE : hors de portee, faux")
	v.v(is_equal_approx(Banc.poser_cout_combat(null, [a], {}, CONFIG_ZORN), 0.0),
		"aucun adversaire : aucun cout, jamais une alarme")

# CE QUE LE CHANTIER EXISTE POUR CORRIGER, cote combat : sans fin au combat,
# l'adversaire ecrasait tout DEFINITIVEMENT et les colons mouraient de faim
# colles a lui. Le combat doit donc reellement se terminer.
func _l_adversaire_finit_par_etre_vaincu(v) -> void:
	var colon: Dictionary = Banc.construire_colon("zorn_1", DECL_COLON_ZORN, CONFIG_ZORN)
	var rival: Dictionary = _chose_zorn("rival_zorn")
	colon.position = rival.position
	var decisions := {colon.id: {"action": "charger_zorn"}}
	v.v(not Banc.est_vaincu(rival, CONFIG_ZORN), "a vigueur pleine, l'adversaire n'est pas vaincu")
	var delta := 1.0 / 60.0
	var pas := 0
	while pas < 3600 and not Banc.est_vaincu(rival, CONFIG_ZORN):
		Banc.poser_cout_combat(rival, [colon], decisions, CONFIG_ZORN)
		Depense.avancer([rival], delta)
		pas += 1
	v.v(pas < 3600, "LE COMBAT DOIT SE TERMINER -- sinon on retombe sur le defaut que ce cablage ferme")
	var duree: float = float(pas) * delta
	v.v(duree > 1.0 and duree < 20.0,
		"CALIBRATION : le combat doit durer entre 1 et 20 s (mesure %.1f s) -- assez pour etre vu, " % duree +
		"assez court pour finir bien avant que la faim morde")
	v.v(float(rival.proprietes.reserves.hargne_zorn.reserve) >= 0.0,
		"depense.gd borne deja par le bas : la vigueur ne doit jamais devenir negative")
	v.v(not Banc.est_vaincu(null, CONFIG_ZORN), "aucun adversaire : jamais un vaincu invente")

# CALIBRATION REELLE DU SOIN, sur les chiffres du disque et jamais sur des
# nombres locaux : le soin doit ABOUTIR (l'allie atteint sa capacite) sans que le
# colon s'y epuise, et il doit reellement liberer la cible. Un taux trop bas
# laisserait le colon soigner jusqu'a la famine ; une capacite trop haute
# rendrait la guerison inatteignable, et le banc n'aurait rien corrige.
func _chemin_reel_le_soin_aboutit_et_libere_le_colon(v) -> void:
	var config: Dictionary = _charger("res://data/banc_psycho_social.json")
	var colon: Dictionary = Banc.construire_colon("novice", config.colons.novice, config)
	var allie: Dictionary = _chose_reelle(config, "allie")
	colon.position = allie.position
	var delta := 1.0 / 60.0
	var pas := 0
	while pas < 3600 and not Banc.mettre_a_jour_guerison(allie, config):
		Banc.soigner_si_possible(colon, {"action": String(config.soin.verbe_soin)}, allie, delta, config)
		pas += 1
	var duree: float = float(pas) * delta
	v.v(pas < 3600, "CALIBRATION : le soin doit ABOUTIR -- sinon le colon reste plante, ce que ce chantier corrige")
	v.v(duree > 1.0 and duree < 20.0,
		"CALIBRATION : la guerison doit durer entre 1 et 20 s (mesure %.1f s) -- assez pour etre vue, " % duree +
		"assez court pour que le colon ne meure pas de faim en soignant")
	v.v(float(colon.proprietes.reserves[String(config.nom_reserve_energie)].reserve) > 0.0,
		"CALIBRATION : soigner ne doit pas vider le soigneur -- le soin coute, il ne tue pas")

	# Et la preuve qui compte : sur la scene REELLE, le colon change de cible.
	var monde = _monde_reel(config, ["feu", "allie", "repas"])
	var frais: Dictionary = Banc.construire_colon("novice", config.colons.novice, config)
	var avant: Dictionary = _decider_reel(frais, monde, null, config)
	v.v(avant.decision != null and avant.decision.chose.id == "allie",
		"CALIBRATION : blesse, l'allie l'emporte -- c'est l'etat de depart du banc")
	var monde_gueri = Monde.new()
	var allie_gueri: Dictionary = _chose_reelle(config, "allie")
	allie_gueri.proprietes.reserves[String(config.soin.nom_reserve_sante)]["reserve"] = float(config.soin.capacite_sante)
	Banc.mettre_a_jour_guerison(allie_gueri, config)
	monde_gueri.ajouter(allie_gueri, "allie_blesse", allie_gueri.position)
	for id in ["feu", "repas"]:
		var c: Dictionary = _chose_reelle(config, id)
		monde_gueri.ajouter(c, id, c.position)
	var apres: Dictionary = _decider_reel(frais, monde_gueri, null, config)
	v.v(apres.decision != null and apres.decision.chose.id == "feu",
		"SUR LA SCENE REELLE : l'allie gueri, le colon doit repartir vers le feu")

# LE DEFAUT EXACT QUE CE CABLAGE FERME, verrouille sur les chiffres du disque.
# MESURE AVANT correction, en faisant tourner la boucle reelle : l'adversaire
# actif (saillance 4.00) ecrasait tout DEFINITIVEMENT -- les deux colons
# fonçaient dessus, s'y plantaient, et mouraient de faim colles a lui, la
# nourriture plafonnant a 3.23 meme a faim critique. Le combat doit donc se
# terminer TRES largement avant que l'energie s'epuise.
func _chemin_reel_le_combat_finit_avant_que_la_faim_tue(v) -> void:
	var config: Dictionary = _charger("res://data/banc_psycho_social.json")
	var colon: Dictionary = Banc.construire_colon("novice", config.colons.novice, config)
	var adversaire: Dictionary = _chose_reelle(config, "adversaire")
	colon.position = adversaire.position
	var decisions := {colon.id: {"action": String(config.verbe_combat)}}
	var delta := 1.0 / 60.0
	var pas := 0
	while pas < 3600 and not Banc.est_vaincu(adversaire, config):
		Banc.poser_cout_combat(adversaire, [colon], decisions, config)
		Banc.poser_surcout_action(colon, float(config.temp_cible), true, config)
		Depense.avancer([colon, adversaire], delta)
		pas += 1
	var duree: float = float(pas) * delta
	v.v(pas < 3600, "CALIBRATION : le combat doit ABOUTIR -- sinon le colon meurt colle a son ennemi")
	v.v(duree < 10.0,
		"CALIBRATION : un colon seul doit venir a bout de l'adversaire en moins de 10 s (mesure %.1f s) -- " % duree +
		"c'est ce qui empeche l'adversaire d'ecraser la scene indefiniment")
	var reste: float = float(colon.proprietes.reserves[String(config.nom_reserve_energie)].reserve)
	v.v(reste > float(config.capacite_energie) * 0.5,
		"CALIBRATION : le colon doit sortir du combat avec plus de la moitie de son energie (reste %.1f) -- " % reste +
		"combattre coute, mais ne doit jamais mener a la famine")
	v.v(Banc.est_vaincu(adversaire, config), "et l'adversaire doit bien etre vaincu a la sortie de la boucle")

# ---- Chemin reel : les fichiers du disque ----

# ACCORD ENTRE LE BANC ET LES CATALOGUES. Si un nom de miroir cessait de
# correspondre au 'propriete_continue' d'une entree de seuil, le banc ecrirait
# sagement un nombre que plus personne ne comparerait : aucun etat ne se
# poserait plus jamais, et AUCUNE alarme ne le dirait (seuil_etat.gd traite une
# propriete absente comme un chemin mort legitime).
func _chemin_reel_les_noms_de_miroirs_sont_ceux_des_catalogues(v) -> void:
	var config: Dictionary = _charger("res://data/banc_psycho_social.json")
	var etats: Dictionary = _charger("res://data/etats.json")
	var seuils_partages: Dictionary = _charger("res://data/seuils_etat.json")
	var deformations: Dictionary = _charger("res://data/deformations.json")
	var epigenetique: Dictionary = _charger("res://data/epigenetique.json")
	var profils: Dictionary = _charger("res://data/profils_saillance.json")
	v.v(not config.is_empty(), "data/banc_psycho_social.json doit charger")

	var locaux: Dictionary = config.seuils_locaux
	v.v(String(locaux.stress_interne.propriete_continue) == String(config.nom_stress_interne),
		"l'entree locale de stress doit comparer le miroir que le banc ecrit reellement")
	v.v(String(locaux.stress_interne.etat) == String(config.etat_stresse),
		"et poser l'etat que le gate de surcout lit reellement")
	v.v(String(locaux.ardeur_combat.propriete_continue) == String(config.nom_ardeur_combat),
		"l'entree locale d'ardeur doit comparer le miroir que le banc ecrit reellement")
	v.v(String(locaux.ardeur_combat.etat) == String(config.etat_colere),
		"et poser l'etat que combat_en_cours lit reellement")
	for nom in [String(config.etat_stresse), String(config.etat_colere)]:
		v.v(etats.has(nom), "l'etat '%s' doit exister dans data/etats.json -- sinon etat_effectif.gd alarme" % nom)
		if etats.has(nom):
			v.v(not etats[nom].has("duree"),
				"'%s' ne doit porter AUCUNE duree : il est retire par le franchissement descendant, jamais par le temps" % nom)
			# CE QUE CE BANC EXIGE REELLEMENT DE CES DEUX ETATS -- et rien de plus.
			# 'stresse' lui appartient et reste un MARQUEUR PUR. 'colere', lui, est
			# PARTAGE avec le chantier « menace -> peur/colere » (audit ligne 4),
			# livre en parallele : il y porte des effets sur degats/precision/
			# prob_fuite, trois proprietes qu'AUCUN colon de ce banc ne porte en
			# base. Exiger « aucun effet » ici verrouillerait a tort une entree
			# partagee ; ce qui doit etre vrai, c'est qu'aucun de ses effets ne
			# touche la SEULE propriete que ce banc lit par etat_effectif.gd.
			for effet in etats[nom].get("effets", []):
				v.v(String(effet.get("propriete", "")) != String(config.nom_vitesse),
					"'%s' ne doit modifier NI ECRASER la vitesse : ce banc ne la lit que pour deplacer, " % nom +
					"un effet la-dessus rendrait le deplacement dependant d'un etat qu'aucune ligne de ce chantier ne veut")
	v.v(etats[String(config.etat_stresse)].get("effets", []).is_empty(),
		"'%s' est un MARQUEUR PUR : aucun effet module, il ne sert qu'au gate de surcout du cablage" % String(config.etat_stresse))

	v.v(seuils_partages.has("faim") and String(seuils_partages.faim.propriete_continue) == String(config.nom_manque_energie),
		"l'entree PARTAGEE 'faim' doit comparer le miroir de manque que ce banc ecrit -- c'est elle qui arme le gate vital")
	v.v(config.directive.etats_vitaux.has(String(seuils_partages.faim.etat)),
		"l'etat pose par 'faim' doit figurer dans etats_vitaux, sinon ecrase_vital ne se declencherait jamais")

	v.v(deformations.has(String(config.source_deformation)),
		"la source de deformation du banc doit exister dans data/deformations.json")
	if deformations.has(String(config.source_deformation)):
		v.v(String(deformations[String(config.source_deformation)].sens) == "monte",
			"le sens doit etre 'monte' : une faim AMPLIFIE la saillance de la nourriture, elle ne l'attenue pas")
	v.v(config.deformation_sources.has(String(config.source_deformation)),
		"la source doit etre declaree dans deformation_sources du colon, sinon Deformation.poser refuse tout")
	v.v(epigenetique.has(String(config.nom_marque_combat)),
		"la marque de combat doit exister dans data/epigenetique.json")
	for decl in config.choses:
		var ref := String(decl.proprietes.get("profil_saillance", ""))
		v.v(profils.has(ref), "le profil '%s' doit exister dans data/profils_saillance.json" % ref)

# LA CONTRAINTE DE CADENCE, mesuree et non supposee : un intervalle trop long
# efface la marque entre deux poses et n'accumule JAMAIS rien -- resultat
# negatif deja paye par le chantier « graisse + accoutumance ».
func _chemin_reel_la_cadence_de_pose_respecte_la_contrainte_du_catalogue(v) -> void:
	var config: Dictionary = _charger("res://data/banc_psycho_social.json")
	var epigenetique: Dictionary = _charger("res://data/epigenetique.json")
	var regle: Dictionary = epigenetique[String(config.nom_marque_combat)]
	var marge: float = float(regle.modulateur_pose) - float(regle.plancher_suppression)
	v.v(marge > 0.0,
		"plancher_suppression doit rester SOUS modulateur_pose, sinon une marque fraiche est retiree au premier avancer()")
	var intervalle_max: float = marge / float(regle.taux_decroissance)
	v.v(float(config.intervalle_pose_marque_s) < intervalle_max,
		"CADENCE : l'intervalle de pose (%.2f s) doit rester sous (modulateur_pose - plancher) / taux (%.2f s)" %
			[float(config.intervalle_pose_marque_s), intervalle_max])
	# Et la preuve par l'accumulation reelle, sur le catalogue reel.
	var colon: Dictionary = Banc.construire_colon("novice", config.colons.novice, config)
	for i in range(200):
		Banc.avancer_experience(colon, true, 0.05, config, epigenetique)
	v.v(Banc.modulateur_experience(colon, config) > 0.0,
		"a la cadence reelle et sur le catalogue reel, la marque doit REELLEMENT accumuler")

# CALIBRATION REELLE DE LA SCENE. Sans ce cas, un placement mal regle laisserait
# un banc qui ne montre rien tout en restant VERT -- le defaut exact rencontre
# par banc_maladie (voir docs/ETAT.md).
func _chemin_reel_le_dilemme_est_atteignable(v) -> void:
	var config: Dictionary = _charger("res://data/banc_psycho_social.json")
	var colon: Dictionary = Banc.construire_colon("novice", config.colons.novice, config)
	var monde = _monde_reel(config, ["feu", "allie", "repas"])
	var r: Dictionary = _decider_reel(colon, monde, null, config)
	var cibles: Array = Banc.saillances_par_cible(r.resultats)
	v.v(cibles.size() >= 2, "CALIBRATION : le colon doit percevoir au moins deux cibles saillantes au depart")
	var ecart: float = Banc.ecart_deux_plus_hautes(r.resultats)
	v.v(ecart < float(config.seuil_ecart),
		"CALIBRATION : l'ecart reel entre les deux plus hautes (%.3f) doit rester sous seuil_ecart (%.2f) -- " % [ecart, float(config.seuil_ecart)] +
		"sinon le dilemme n'existe pas et le banc ne montre rien")
	var stress: float = Banc.poser_stress_interne(colon, r.resultats, config)
	v.v(stress > float(config.seuils_locaux.stress_interne.seuil),
		"CALIBRATION : le stress produit par ce dilemme doit reellement franchir le seuil local")
	v.v(not _visibles_contient(r.visibles, "repas"),
		"CALIBRATION : au repos, la nourriture doit etre ECRASEE -- « elle est la mais la saillance est basse »")
	v.v(r.decision != null and r.decision.chose.id == "allie",
		"CALIBRATION : sans directive, le colon doit choisir l'allie -- c'est ce qui rend l'obeissance visible")

func _chemin_reel_la_faim_ecrase_tout_et_la_directive_est_calibree(v) -> void:
	var config: Dictionary = _charger("res://data/banc_psycho_social.json")
	var deformations: Dictionary = _charger("res://data/deformations.json")
	var seuils_partages: Dictionary = _charger("res://data/seuils_etat.json")
	var colon: Dictionary = Banc.construire_colon("novice", config.colons.novice, config)
	var monde = _monde_reel(config, ["feu", "allie", "repas"])

	# La directive, sur un colon repu : elle doit peser plus que le sommet.
	var avec: Dictionary = _decider_reel(colon, monde, _chose_reelle(config, "feu"), config)
	v.v(avec.decision != null and avec.decision.chose.id == String(config.directive.cible_id)
		and bool(avec.decision.get("directive", false)),
		"CALIBRATION : bonus_score doit depasser le sommet naturel, sinon la directive ne changerait jamais rien")

	# Puis la faim critique. Le seuil de la sigmoide et le seuil PARTAGE de faim
	# doivent s'armer au meme moment : c'est ce qui rend le gate vital coherent.
	var seuil_faim: float = float(seuils_partages.faim.seuil)
	var reserve_affame: float = float(config.capacite_energie) - seuil_faim
	v.v(abs(reserve_affame / float(config.capacite_energie) - float(config.seuil_critique_ratio)) < 0.05,
		"CALIBRATION : le point d'inflexion de la sigmoide (%.2f) doit coincider avec le seuil PARTAGE de faim (%.2f) -- " %
			[float(config.seuil_critique_ratio), reserve_affame / float(config.capacite_energie)] +
		"sinon le gate ecrase_vital s'armerait longtemps avant ou apres que le besoin prenne la main")

	colon.proprietes.reserves[String(config.nom_reserve_energie)]["reserve"] = float(config.capacite_energie) * 0.2
	for i in range(400):
		Banc.poser_deformation_faim(colon, Banc.urgence_faim(colon, config), 0.05, config, deformations)
		Deformation.avancer(colon, 0.05, deformations)
	# ecrase_vital ferme : la directive n'est meme pas construite.
	Banc.poser_manque_energie(colon, config)
	SeuilEtat.avancer([colon], seuils_partages)
	v.v(colon.proprietes.etats_actifs.has(String(seuils_partages.faim.etat)),
		"CALIBRATION : a 20%% de reserve, l'etat de faim PARTAGE doit reellement etre pose")
	v.v(Banc.entree_directive(colon, _chose_reelle(config, "feu"), config) == null,
		"GATE REEL : sous besoin critique, la directive ne doit meme pas etre construite")
	var affame: Dictionary = _decider_reel(colon, monde, _chose_reelle(config, "feu"), config)
	v.v(affame.visibles.size() == 1 and _visibles_contient(affame.visibles, "repas"),
		"CALIBRATION : a faim critique, la nourriture doit ECRASER tout le reste sur la scene reelle")
	v.v(affame.decision != null and String(affame.decision.action) == String(config.repas.verbe_repas),
		"CALIBRATION : le colon doit reellement resoudre le verbe de repas")

func _chemin_reel_aucun_etat_parasite_ni_surcout_thermique_au_depart(v) -> void:
	var config: Dictionary = _charger("res://data/banc_psycho_social.json")
	var seuils_partages: Dictionary = _charger("res://data/seuils_etat.json")
	var catalogue_temp: Dictionary = _charger("res://data/temperature.json")
	var colon: Dictionary = Banc.construire_colon("novice", config.colons.novice, config)
	var sources: Array = Banc.sources_temperature(config)
	var Temperature = load("res://scripts/temperature.gd")

	var temp_depart: float = Temperature.locale(colon.position, sources, catalogue_temp)
	var d: Dictionary = Banc.poser_surcout_action(colon, temp_depart, false, config)
	v.v(is_equal_approx(float(d.froid), 0.0) and is_equal_approx(float(d.chaud), 0.0),
		"CALIBRATION : au point de depart, hors de la zone froide, les deux miroirs thermiques doivent valoir 0.0")
	v.v(is_equal_approx(float(d.thermo), 0.0), "CALIBRATION : aucun surcout thermique au depart")

	Banc.poser_manque_energie(colon, config)
	Banc.poser_stress_interne(colon, [], config)
	Banc.poser_ardeur_combat(colon, null, config)
	SeuilEtat.avancer([colon], seuils_partages)
	SeuilEtat.avancer([colon], config.seuils_locaux)
	v.v(colon.proprietes.etats_actifs.is_empty(),
		"AUCUN PARASITE : au repos, reserve pleine et sans conflit, le colon ne doit porter aucun etat -- les entrees " +
		"thermiques du catalogue PARTAGE (point_fusion/chaud/...) sont des chemins morts, il ne porte pas 'temperature'")

	# La zone froide est bien SUR la nourriture : aller manger coute cher.
	var repas_pos: Vector3 = _chose_reelle(config, "repas").position
	var d_froid: Dictionary = Banc.poser_surcout_action(colon, Temperature.locale(repas_pos, sources, catalogue_temp), false, config)
	v.v(float(d_froid.froid) > 0.0 and float(d_froid.thermo) > 0.0,
		"CALIBRATION : la zone froide doit reellement couvrir la nourriture -- sinon le troisieme terme du surcout " +
		"ne serait jamais exerce et la somme a trois ne prouverait rien")

# ---- Fixtures ----

func _monde_zorn(ids: Array):
	var monde = Monde.new()
	for decl in CHOSES_ZORN:
		if ids.has(String(decl.id)):
			var chose: Dictionary = Banc.construire_chose(decl)
			monde.ajouter(chose, String(decl.type), chose.position)
	return monde

func _chose_zorn(id: String) -> Dictionary:
	for decl in CHOSES_ZORN:
		if String(decl.id) == id:
			return Banc.construire_chose(decl)
	push_error("test_banc_psycho_social : chose zorn inconnue '%s'" % id)
	return {}

func _decider_zorn(colon: Dictionary, monde, chose_directive, config: Dictionary) -> Dictionary:
	return Banc.decider(colon, monde, CANAUX_ZORN, {}, PROFILS_ZORN, DEFORMATIONS_ZORN, {},
		ACTIONS_ZORN, chose_directive, config)

func _monde_reel(config: Dictionary, ids: Array):
	var monde = Monde.new()
	for decl in config.choses:
		if ids.has(String(decl.id)):
			var chose: Dictionary = Banc.construire_chose(decl)
			monde.ajouter(chose, String(decl.get("type", "chose")), chose.position)
	return monde

func _chose_reelle(config: Dictionary, id: String) -> Dictionary:
	for decl in config.choses:
		if String(decl.id) == id:
			return Banc.construire_chose(decl)
	push_error("test_banc_psycho_social : chose reelle inconnue '%s'" % id)
	return {}

func _decider_reel(colon: Dictionary, monde, chose_directive, config: Dictionary) -> Dictionary:
	var actions: Dictionary = _charger("res://data/types_choses.json")
	for cle in config.catalogue_local:
		actions[cle] = config.catalogue_local[cle]
	return Banc.decider(colon, monde,
		_charger("res://data/canaux.json"), _charger("res://data/menaces.json"),
		_charger("res://data/profils_saillance.json"), _charger("res://data/deformations.json"),
		_charger("res://data/jugements.json"), actions, chose_directive, config)

func _visibles_contient(visibles: Array, id: String) -> bool:
	for entree in visibles:
		var chose = entree.get("chose", null)
		if chose is Dictionary and String(chose.get("id", "")) == id:
			return true
	return false

func _saillance_de(resultats: Array, id: String) -> float:
	for entree in resultats:
		var chose = entree.get("chose", null)
		if chose is Dictionary and String(chose.get("id", "")) == id:
			return float(entree.saillance)
	return -1.0

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
