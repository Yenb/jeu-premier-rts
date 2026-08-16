extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_fatigue_circadien.gd
#
# Verrouille les fonctions PURES de scripts/banc_fatigue_circadien.gd (chantier
# « fatigue + circadien + blesse != repos »). Le banc ne fait que CABLER six
# mecanismes du coeur deja verrouilles separement (depense.gd/velocite.gd/
# seuil_etat.gd/conditions.gd/charge.gd/etat_duree.gd) : aucune de leurs lois
# n'est retestee ici, seuls le montage, la calibration et l'affichage le sont.
#
# DEUX MOITIES, comme les autres tests de banc :
# - HORS DOMAINE : une config, un catalogue de zone, un catalogue d'etats et un
#   catalogue de seuils ENTIEREMENT INVENTES (journee de 10 heures, reserves
#   "torpeur_vlok"/"integrite_vlok", etats "vide_vlok"/"fissure_vlok")
#   traversent le meme code. Si le banc connaissait "sommeil", "sante",
#   "epuise" ou 24 heures, ce bloc rougirait.
# - CHEMIN REEL : data/banc_fatigue_circadien.json + data/etats.json +
#   data/seuils_etat.json relus SUR LE DISQUE, pour verifier la CALIBRATION
#   (l'epuisement et la dette sont bien atteignables, le blesse recupere
#   vraiment) -- meme discipline que la correction banc_maladie, ou un test qui
#   ne rejouait jamais le JSON reel laissait passer une calibration qui ne
#   declenchait rien.

const Banc = preload("res://scripts/banc_fatigue_circadien.gd")
const Verif = preload("res://scripts/verif.gd")

const CONFIG_VLOK := {
	"cycle": { "duree_jour_secondes": 20.0, "heures_par_jour": 10.0, "heure_depart": 5.0 },
	"nom_propriete_heure": "phase_vlok",
	"nom_propriete_vitesse": "allure_vlok",
	"nom_marqueur_zone": "doit_se_terrer_vlok",
	"nom_reserve_sommeil": "torpeur_vlok",
	"nom_reserve_sante": "integrite_vlok",
	"nom_miroir_manque": "manque_torpeur_vlok",
	"nom_canal_dette": "arriere_vlok",
	"nom_marqueur_dette": "arriere_franchi_vlok",
	"nom_etat_epuise": "vide_vlok",
	"nom_etat_endette": "endette_vlok",
	"nom_etat_blesse": "fissure_vlok",
	"capacite_sommeil": 50.0,
	"capacite_sante": 50.0,
	"cout_veille_par_s": 5.0,
	"coef_effort": 0.01,
	"recuperation_sommeil_par_s": 10.0,
	"recuperation_sante_par_s": 4.0,
	"dette": { "seuil": 2.0, "taux_decroissance": 4.0, "poids": 1.0, "portee_charge": 0.0 },
	"colons": [
		{
			"id": "arpenteur_vlok",
			"position": [0.0, 0.0, 0.0],
			"vitesse": 100.0,
			"sommeil_initial": 50.0,
			"sante_initial": 50.0,
			"etats_actifs": [],
			"patrouille": { "amplitude": 200.0, "periode": 4.0 },
		},
		{
			"id": "immobile_vlok",
			"position": [0.0, 500.0, 0.0],
			"vitesse": 100.0,
			"sommeil_initial": 50.0,
			"sante_initial": 20.0,
			"etats_actifs": ["fissure_vlok"],
			"patrouille": { "amplitude": 0.0, "periode": 0.0 },
		},
	],
	"priorite_couleurs": ["vide_vlok", "endette_vlok", "fissure_vlok"],
	"couleurs": {
		"eveille": [0.0, 1.0, 0.0],
		"dort": [0.0, 0.0, 1.0],
		"vide_vlok": [1.0, 0.0, 0.0],
		"endette_vlok": [1.0, 0.5, 0.0],
		"fissure_vlok": [0.5, 0.0, 0.5],
	},
	"intervalle_print": 1.0,
}

# Zone qui ENJAMBE la fin de journee, exactement comme la vraie (16h->8h sur
# 24) mais sur une journee de 10 heures : phase >= 7 OU phase <= 3.
const ZONE_VLOK := [
	{
		"id": "fin_vlok",
		"conditions": [ { "propriete": "phase_vlok", "operateur": ">=", "seuil": 7.0 } ],
		"resultat": { "doit_se_terrer_vlok": true },
	},
	{
		"id": "debut_vlok",
		"conditions": [ { "propriete": "phase_vlok", "operateur": "<=", "seuil": 3.0 } ],
		"resultat": { "doit_se_terrer_vlok": true },
	},
]

const ETATS_VLOK := {
	"vide_vlok": { "effets": [ { "propriete": "allure_vlok", "mode": "moduler", "facteur": 0.5 } ] },
	"endette_vlok": { "duree": 2.0, "effets": [ { "propriete": "allure_vlok", "mode": "moduler", "facteur": 0.5 } ] },
	"fissure_vlok": { "effets": [] },
}

const SEUILS_VLOK := {
	"vidage_vlok": {
		"propriete_continue": "manque_torpeur_vlok",
		"seuil": 30.0,
		"etat": "vide_vlok",
	},
}

func _init() -> void:
	var v := Verif.new()
	_horloge_boucle_et_ignore_24_heures(v)
	_doit_dormir_pose_en_zone_retire_hors_zone(v)
	_segments_horloge_viennent_du_catalogue(v)
	_fatigue_descend_avec_activite(v)
	_fatigue_remonte_pendant_le_sommeil_et_le_colon_ne_bouge_plus(v)
	_epuise_pose_au_dela_du_seuil_puis_retire(v)
	_dette_monte_en_veille_dans_la_zone(v)
	_dette_redescend_hors_zone(v)
	_cause_de_dette_n_atteint_que_son_propre_colon(v)
	_blesse_recupere_sante_sans_recuperer_sommeil(v)
	_chemin_reel_calibration_et_pose(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_fatigue_circadien -- horloge locale bouclee sans jamais supposer 24 heures, " +
			"doit_dormir pose sur une zone qui enjambe minuit (une entree vraie gagne sur une fausse) et retire hors zone, " +
			"horloge affichee echantillonnee depuis le catalogue reel, " +
			"fatigue qui descend plus vite avec l'activite, remonte pendant le sommeil pendant que le colon se fige, " +
			"epuise pose au-dela du seuil puis RETIRE quand la reserve remonte, " +
			"dette qui monte en veille sous zone et redescend hors zone, " +
			"cause de dette qui n'atteint jamais un autre colon, " +
			"blesse qui recupere sa sante sans recuperer sa fatigue, " +
			"et sur le chemin reel une calibration ou tout cela est reellement atteignable")
		quit(0)

# ---- Horloge du jour (RECOPIEE de banc_lumiere.gd, jamais referencee) ----

func _horloge_boucle_et_ignore_24_heures(v) -> void:
	# Journee de 10 heures mappee sur 20 s reelles : 2 s par heure.
	v.v(is_equal_approx(Banc.heure_courante(0.0, 20.0, 10.0, 5.0), 5.0), "a t=0 l'heure doit valoir heure_depart")
	v.v(is_equal_approx(Banc.heure_courante(4.0, 20.0, 10.0, 5.0), 7.0), "4 s reelles = 2 heures simulees sur une journee de 10 h en 20 s")
	v.v(is_equal_approx(Banc.heure_courante(12.0, 20.0, 10.0, 5.0), 1.0),
		"l'heure doit BOUCLER par fmod sur heures_par_jour, jamais sur 24.0 en dur")
	v.v(is_equal_approx(Banc.heure_courante(9.0, 0.0, 10.0, 5.0), 5.0),
		"garde defensive : duree_jour_secondes <= 0 doit figer l'heure, jamais diviser par zero")

# ---- La zone circadienne (conditions.gd, deux entrees, meme cle) ----

func _doit_dormir_pose_en_zone_retire_hors_zone(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK, ETATS_VLOK)
	var nom: String = CONFIG_VLOK.nom_marqueur_zone

	# Milieu de journee : AUCUNE des deux entrees n'est vraie.
	Banc.poser_heure(colons, 5.0, CONFIG_VLOK)
	Banc.evaluer_zone(colons, ZONE_VLOK, CONFIG_VLOK)
	v.v(not colons[0].proprietes.has(nom), "hors zone, le marqueur ne doit pas etre pose")

	# Fin de journee : SEULE l'entree ">= 7" est vraie, l'entree "<= 3" est
	# FAUSSE. C'est LE cas du chantier -- en une seule passe, l'entree fausse
	# effacerait ce que la vraie vient de poser.
	Banc.poser_heure(colons, 8.0, CONFIG_VLOK)
	var entree := Banc.evaluer_zone(colons, ZONE_VLOK, CONFIG_VLOK)
	v.v(bool(colons[0].proprietes.get(nom, false)),
		"ZONE QUI ENJAMBE LA FIN DE JOURNEE : une entree VRAIE doit gagner sur une entree FAUSSE posant la meme cle")
	v.v(entree.size() == colons.size() and bool(entree[0].apres) and not bool(entree[0].avant),
		"l'entree en zone doit etre rendue comme un CHANGEMENT, avec son avant/apres")

	# Toujours en zone, l'heure a change mais pas le cote : plus aucun
	# changement (sans quoi la console cracherait a chaque frame).
	Banc.poser_heure(colons, 9.0, CONFIG_VLOK)
	v.v(Banc.evaluer_zone(colons, ZONE_VLOK, CONFIG_VLOK).is_empty(),
		"rester en zone ne doit rendre AUCUN changement")

	# Debut de journee : cette fois SEULE l'entree "<= 3" est vraie.
	Banc.poser_heure(colons, 2.0, CONFIG_VLOK)
	Banc.evaluer_zone(colons, ZONE_VLOK, CONFIG_VLOK)
	v.v(bool(colons[0].proprietes.get(nom, false)),
		"l'autre moitie de la zone (petit matin) doit poser la MEME cle")

	# Retour au grand jour : REVERSIBILITE, retirer_si_faux=true.
	Banc.poser_heure(colons, 5.0, CONFIG_VLOK)
	var sortie := Banc.evaluer_zone(colons, ZONE_VLOK, CONFIG_VLOK)
	v.v(not colons[0].proprietes.has(nom),
		"REVERSIBILITE : sortir de la zone doit RETIRER le marqueur, jamais le laisser colle")
	v.v(sortie.size() == colons.size() and not bool(sortie[0].apres),
		"la sortie de zone doit elle aussi etre rendue comme un changement")

func _segments_horloge_viennent_du_catalogue(v) -> void:
	var segments: Array = Banc.segments_horloge(ZONE_VLOK, CONFIG_VLOK, 10.0, 10)
	v.v(segments.size() == 10, "un segment par pas demande")
	# Centres echantillonnes a 0.5, 1.5, ... 9.5 : zone vraie pour <= 3 (0.5,
	# 1.5, 2.5) et pour >= 7 (7.5, 8.5, 9.5).
	v.v(bool(segments[0]) and bool(segments[2]) and not bool(segments[3]),
		"le debut de journee doit etre en zone jusqu'au seuil bas, pas au-dela")
	v.v(not bool(segments[6]) and bool(segments[7]) and bool(segments[9]),
		"la fin de journee doit basculer en zone au seuil haut et y rester jusqu'a la fin")
	v.v(Banc.segments_horloge(ZONE_VLOK, CONFIG_VLOK, 10.0, 0).is_empty(),
		"garde defensive : zero segment demande ne doit jamais diviser par zero")
	v.v(Banc.dans_zone(8.0, ZONE_VLOK, CONFIG_VLOK) and not Banc.dans_zone(5.0, ZONE_VLOK, CONFIG_VLOK),
		"dans_zone doit passer par la MEME loi que les colons, jamais une comparaison recodee")

# ---- La fatigue : une reserve qui descend, et remonte ----

func _fatigue_descend_avec_activite(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK, ETATS_VLOK)
	var nom: String = CONFIG_VLOK.nom_reserve_sommeil
	# 2 s de veille en plein jour (heure_depart 5.0, hors zone) : aucune dette,
	# aucun sommeil, seulement le metabolisme et l'effort.
	for i in range(20):
		Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 0.0, 0.1)
	var arpenteur: float = Banc.reserve_de(colons[0], nom)
	var immobile: float = Banc.reserve_de(colons[1], nom)
	v.v(arpenteur < 50.0 and immobile < 50.0, "la fatigue doit descendre pour les deux : le metabolisme de base ne depend d'aucune action")
	v.v(arpenteur < immobile,
		"L'ACTIVITE COUTE : le colon qui patrouille doit avoir MOINS de reserve que celui qui ne bouge pas, sur le meme temps")
	# Le surcout vient bien de la velocite DERIVEE, jamais d'un nombre pose a
	# la main : un colon immobile n'a aucun surcout.
	v.v(is_equal_approx(float(colons[1].proprietes.reserves[nom].surcout_action), 0.0),
		"un colon immobile ne doit porter AUCUN surcout d'effort")
	v.v(float(colons[0].proprietes.reserves[nom].surcout_action) > 0.0,
		"un colon qui bouge doit porter un surcout d'effort strictement positif")

func _fatigue_remonte_pendant_le_sommeil_et_le_colon_ne_bouge_plus(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK, ETATS_VLOK)
	var nom: String = CONFIG_VLOK.nom_reserve_sommeil
	var arpenteur: Dictionary = colons[0]
	for i in range(30):
		Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 0.0, 0.1)
	var creux: float = Banc.reserve_de(arpenteur, nom)
	var position_a_l_endormissement: Vector3 = arpenteur.position

	v.v(Banc.basculer_sommeil(arpenteur), "le toggle doit rendre le nouvel etat, ici endormi")
	for i in range(10):
		Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 0.0, 0.1)
	v.v(Banc.reserve_de(arpenteur, nom) > creux,
		"COUT_BASE NEGATIF : pendant le sommeil la reserve doit REMONTER, sans aucun mecanisme neuf")
	v.v(arpenteur.position.is_equal_approx(position_a_l_endormissement),
		"un colon endormi ne doit plus bouger du tout")
	v.v(is_equal_approx(float(arpenteur.proprietes.reserves[nom].surcout_action), 0.0),
		"un colon endormi ne doit porter aucun surcout d'effort")

	# Le plafond est du CABLAGE : depense.gd ne borne que le bas.
	for i in range(200):
		Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 0.0, 0.1)
	v.v(is_equal_approx(Banc.reserve_de(arpenteur, nom), float(CONFIG_VLOK.capacite_sommeil)),
		"la reserve doit s'arreter EXACTEMENT a la capacite, ecretee par le cablage (rien dans le coeur ne borne le haut)")

	# Reveil : il repart d'ou il s'etait arrete, jamais un saut de position.
	v.v(not Banc.basculer_sommeil(arpenteur), "un second toggle doit reveiller")
	Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 0.0, 0.1)
	v.v(arpenteur.position.distance_to(position_a_l_endormissement) < 40.0,
		"au reveil le colon doit repartir d'ou il s'etait arrete (horloge de patrouille figee pendant le sommeil), jamais sauter")

# ---- L'epuisement : seuil_etat.gd sur le miroir plat ----

func _epuise_pose_au_dela_du_seuil_puis_retire(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK, ETATS_VLOK)
	var arpenteur: Dictionary = colons[0]
	var nom_etat: String = CONFIG_VLOK.nom_etat_epuise
	var miroir: String = CONFIG_VLOK.nom_miroir_manque

	Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 0.0, 0.1)
	v.v(arpenteur.proprietes.has(miroir),
		"le miroir plat inverse doit etre ecrit par le cablage a chaque tick -- seuil_etat.gd ne sait pas lire une reserve")
	v.v(not arpenteur.proprietes.get("etats_actifs", []).has(nom_etat),
		"a pleine reserve, aucun etat d'epuisement")

	# La reserve part de 50, le seuil du miroir est 30 : il faut descendre sous
	# 20 de reserve.
	for i in range(80):
		Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 0.0, 0.1)
	v.v(arpenteur.proprietes.get("etats_actifs", []).has(nom_etat),
		"au-dela du seuil, seuil_etat.gd doit poser l'etat d'epuisement")
	v.v(is_equal_approx(float(arpenteur.proprietes[miroir]), float(CONFIG_VLOK.capacite_sommeil) - Banc.reserve_de(arpenteur, CONFIG_VLOK.nom_reserve_sommeil)),
		"le miroir doit valoir EXACTEMENT capacite - reserve, jamais une valeur derivee autrement")

	# L'etat MODULE la vitesse -- lue par etat_effectif.gd, jamais recalculee.
	v.v(is_equal_approx(Banc.vitesse_effective(arpenteur, CONFIG_VLOK, ETATS_VLOK), 50.0),
		"l'etat d'epuisement doit MODULER la vitesse effective (100 x 0.5), via etat_effectif.gd")

	# REVERSIBILITE : dormir remonte la reserve, le miroir redescend, l'etat est
	# RETIRE par seuil_etat.gd lui-meme -- aucune ligne de cablage pour ca.
	Banc.basculer_sommeil(arpenteur)
	for i in range(60):
		Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 0.0, 0.1)
	v.v(not arpenteur.proprietes.get("etats_actifs", []).has(nom_etat),
		"REVERSIBILITE : une fois la reserve remontee, l'etat d'epuisement doit etre RETIRE par seuil_etat.gd, sans intervention du cablage")

# ---- La dette de sommeil : charge.gd sur une cause synthetisee ----

func _dette_monte_en_veille_dans_la_zone(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK, ETATS_VLOK)
	var arpenteur: Dictionary = colons[0]
	# t = 4 s reelles -> phase 7.0 : en zone (>= 7). Il veille.
	for i in range(10):
		Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 4.0 + float(i) * 0.1, 0.1)
	v.v(Banc.dette_de(arpenteur, CONFIG_VLOK) > 0.0,
		"veiller dans la zone de sommeil doit faire MONTER la dette")
	v.v(is_equal_approx(Banc.dette_de(arpenteur, CONFIG_VLOK), 1.0),
		"la dette doit monter exactement de poids x temps (1.0/s pendant 1 s), jamais un cumul double")

	# Franchissement : charge.gd pose son marqueur, le cablage le relaie vers
	# un etat a duree que etat_effectif.gd module.
	for i in range(20):
		Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 5.0 + float(i) * 0.1, 0.1)
	v.v(bool(arpenteur.proprietes.get(CONFIG_VLOK.nom_marqueur_dette, false)),
		"au-dela du seuil, charge.gd doit poser son marqueur SUR proprietes")
	v.v(arpenteur.proprietes.get("etats_actifs", []).has(CONFIG_VLOK.nom_etat_endette),
		"le cablage doit relayer le marqueur vers l'etat a duree -- charge.gd ne touche jamais etats_actifs")

	# UN COLON QUI DORT NE PRODUIT PLUS DE CAUSE, meme en pleine zone.
	var endormi: Array = Banc.construire_colons(CONFIG_VLOK, ETATS_VLOK)
	Banc.basculer_sommeil(endormi[0])
	for i in range(20):
		Banc.avancer(endormi, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 4.0 + float(i) * 0.1, 0.1)
	v.v(is_equal_approx(Banc.dette_de(endormi[0], CONFIG_VLOK), 0.0),
		"dormir dans la zone ne doit produire AUCUNE dette : la cause n'existe plus")

func _dette_redescend_hors_zone(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK, ETATS_VLOK)
	var arpenteur: Dictionary = colons[0]
	for i in range(30):
		Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 4.0 + float(i) * 0.1, 0.1)
	var haut: float = Banc.dette_de(arpenteur, CONFIG_VLOK)
	v.v(haut > float(CONFIG_VLOK.dette.seuil), "pre-condition : la dette doit avoir depasse son seuil")
	v.v(arpenteur.proprietes.get("etats_actifs", []).has(CONFIG_VLOK.nom_etat_endette), "pre-condition : l'etat de dette doit etre actif")

	# Retour en plein jour (phase 5.0, hors zone) : plus aucune cause, la
	# charge redescend d'elle-meme.
	for i in range(10):
		Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 0.0, 0.1)
	var apres: float = Banc.dette_de(arpenteur, CONFIG_VLOK)
	v.v(apres < haut, "hors zone, la dette doit REDESCENDRE toute seule (taux_decroissance de charge.gd)")
	v.v(not bool(arpenteur.proprietes.get(CONFIG_VLOK.nom_marqueur_dette, false)),
		"sous le seuil, charge.gd doit RETIRER son marqueur -- le seuil est reversible")

	# Plus personne ne repose l'etat : son intensite s'epuise et etat_duree.gd
	# le retire de lui-meme.
	for i in range(30):
		Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 0.0, 0.1)
	v.v(is_equal_approx(Banc.dette_de(arpenteur, CONFIG_VLOK), 0.0),
		"la dette doit finir a zero exactement, jamais en negatif")
	v.v(not arpenteur.proprietes.get("etats_actifs", []).has(CONFIG_VLOK.nom_etat_endette),
		"une fois le marqueur retire, plus personne ne repose l'etat : son intensite s'epuise et etat_duree.gd le retire")

func _cause_de_dette_n_atteint_que_son_propre_colon(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK, ETATS_VLOK)
	# Les deux colons veillent en zone : DEUX causes existent. A portee 0.0,
	# chacune ne doit alimenter QUE le colon qui l'a produite.
	for i in range(10):
		Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 4.0 + float(i) * 0.1, 0.1)
	v.v(is_equal_approx(Banc.dette_de(colons[0], CONFIG_VLOK), 1.0) and is_equal_approx(Banc.dette_de(colons[1], CONFIG_VLOK), 1.0),
		"PORTEE 0.0 : deux veilleurs a des positions distinctes doivent accumuler 1.0 chacun, jamais 2.0 -- la cause d'un colon ne doit jamais nourrir son voisin")
	v.v(Banc.causes_dette(colons, CONFIG_VLOK).size() == 2,
		"une cause par colon eveille en zone, construite par le cablage -- charge.gd ne lit jamais une reserve ni un marqueur lui-meme")

# ---- Blesse != repos : deux reserves, deux destins ----

func _blesse_recupere_sante_sans_recuperer_sommeil(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK, ETATS_VLOK)
	var blesse: Dictionary = colons[1]
	var sain: Dictionary = colons[0]
	v.v(blesse.proprietes.get("etats_actifs", []).has(CONFIG_VLOK.nom_etat_blesse),
		"l'etat declare en donnee doit avoir ete pose par EtatDuree.poser, jamais recopie a la main")

	var sante_avant: float = Banc.reserve_de(blesse, CONFIG_VLOK.nom_reserve_sante)
	var sommeil_avant: float = Banc.reserve_de(blesse, CONFIG_VLOK.nom_reserve_sommeil)
	for i in range(20):
		Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 0.0, 0.1)

	v.v(Banc.reserve_de(blesse, CONFIG_VLOK.nom_reserve_sante) > sante_avant,
		"un blesse au repos doit voir sa SANTE remonter (cout_base negatif sur ce seul canal)")
	v.v(Banc.reserve_de(blesse, CONFIG_VLOK.nom_reserve_sommeil) < sommeil_avant,
		"DEUX RESERVES INDEPENDANTES : pendant que la sante remonte, la FATIGUE doit continuer de descendre -- se reposer n'est pas dormir")
	v.v(is_equal_approx(Banc.reserve_de(blesse, CONFIG_VLOK.nom_reserve_sommeil), sommeil_avant - float(CONFIG_VLOK.cout_veille_par_s) * 2.0),
		"la fatigue du blesse immobile doit descendre au SEUL cout de veille, sans le moindre effet du canal sante")
	v.v(is_equal_approx(float(sain.proprietes.reserves[CONFIG_VLOK.nom_reserve_sante].cout_base), 0.0),
		"un colon NON blesse ne doit porter aucun cout de soin -- le gate ne se declenche que sur l'etat")
	v.v(is_equal_approx(Banc.reserve_de(sain, CONFIG_VLOK.nom_reserve_sante), 50.0),
		"la sante d'un colon non blesse ne doit ni monter ni descendre dans ce banc")

	# La blessure ne s'en va jamais toute seule (aucune 'duree' au catalogue) :
	# c'est ce qui laisse le temps d'observer la separation des deux reserves.
	for i in range(400):
		Banc.avancer(colons, CONFIG_VLOK, ETATS_VLOK, ZONE_VLOK, SEUILS_VLOK, 0.0, 0.1)
	v.v(blesse.proprietes.get("etats_actifs", []).has(CONFIG_VLOK.nom_etat_blesse),
		"l'etat de blessure n'a pas de duree : il ne doit jamais expirer tout seul")
	v.v(is_equal_approx(Banc.reserve_de(blesse, CONFIG_VLOK.nom_reserve_sante), float(CONFIG_VLOK.capacite_sante)),
		"la sante doit s'arreter exactement a sa capacite, ecretee par le cablage")
	v.v(is_equal_approx(Banc.reserve_de(blesse, CONFIG_VLOK.nom_reserve_sommeil), 0.0),
		"la fatigue, elle, doit toucher zero et y rester -- depense.gd borne le bas, personne ne la remonte")

# ---- Chemin reel : les trois JSON relus sur le disque ----

func _chemin_reel_calibration_et_pose(v) -> void:
	var config: Dictionary = _charger("res://data/banc_fatigue_circadien.json")
	var etats: Dictionary = _charger("res://data/etats.json")
	var seuils: Dictionary = _charger("res://data/seuils_etat.json")
	var zone: Array = config.get("zone_sommeil", [])
	v.v(not config.is_empty() and not etats.is_empty() and not seuils.is_empty(), "les trois JSON reels doivent charger")

	for nom_etat in [config.nom_etat_epuise, config.nom_etat_endette, config.nom_etat_blesse]:
		v.v(etats.has(nom_etat), "l'etat '%s' doit exister dans data/etats.json" % nom_etat)
	v.v(seuils.has("epuisement") and String(seuils.epuisement.propriete_continue) == config.nom_miroir_manque,
		"data/seuils_etat.json:epuisement doit comparer exactement le miroir plat que ce banc ecrit")
	v.v(String(seuils.epuisement.etat) == config.nom_etat_epuise,
		"l'entree de seuil doit poser l'etat que le banc affiche")

	var colons: Array = Banc.construire_colons(config, etats)
	v.v(colons.size() == 2, "le banc reel doit poser deux colons")
	v.v(colons[1].proprietes.get("etats_actifs", []).has(config.nom_etat_blesse),
		"CALIBRATION : le second colon doit etre blesse des le demarrage, sans aucun clic")
	v.v(colons[0].position.distance_to(colons[1].position) > 0.0,
		"CALIBRATION : les deux colons doivent occuper des positions DISTINCTES -- la cause de dette est a portee 0.0")

	# Le banc s'ouvre EN VEILLE : sans ca, le premier phenomene observable
	# serait deja passe au demarrage.
	v.v(not Banc.dans_zone(float(config.cycle.heure_depart), zone, config),
		"CALIBRATION : le banc doit s'ouvrir HORS de la zone de sommeil")

	# 20 s de veille reelle : l'epuisement doit etre atteint. Cette assertion
	# est celle qui aurait rougi sous une calibration qui ne declenche rien
	# (lecon de la correction banc_maladie).
	var temps := 0.0
	for i in range(1000):
		temps += 0.02
		Banc.avancer(colons, config, etats, zone, seuils, temps, 0.02)
	v.v(colons[0].proprietes.get("etats_actifs", []).has(config.nom_etat_epuise),
		"CALIBRATION : 20 s de veille doivent suffire a epuiser le colon actif, sinon le banc ne montre rien")
	v.v(colons[0].proprietes.get("etats_actifs", []).has(config.nom_etat_endette),
		"CALIBRATION : 20 s couvrent une entree en zone de sommeil, la dette doit avoir franchi son seuil")
	v.v(Banc.reserve_de(colons[1], config.nom_reserve_sante) > 25.0,
		"CALIBRATION : sur le meme temps, le blesse doit avoir REGAGNE de la sante")
	v.v(Banc.reserve_de(colons[1], config.nom_reserve_sommeil) < 100.0,
		"CALIBRATION : sur le meme temps, le blesse doit avoir PERDU du sommeil -- se reposer n'est pas dormir")

	# Le colon epuise ET endette compose les deux modulations, multiplicativement.
	var vitesse: float = Banc.vitesse_effective(colons[0], config, etats)
	v.v(vitesse < float(colons[0].proprietes[config.nom_propriete_vitesse]),
		"un colon epuise doit avoir une vitesse effective strictement inferieure a sa base")

	# La palette est lue en DONNEE, y compris pour la priorite d'affichage.
	v.v(Banc.couleur_pour_colon(colons[1], config) != Banc.couleur_pour_colon(colons[0], config),
		"deux colons dans des etats differents doivent recevoir des couleurs differentes, lues en donnee")
	var texte: String = Banc.texte_colon(colons[0], config)
	v.v(texte.find(config.nom_reserve_sommeil) >= 0 and texte.find(config.nom_etat_epuise) >= 0,
		"le label doit nommer la reserve et lister les etats reellement actifs")

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
