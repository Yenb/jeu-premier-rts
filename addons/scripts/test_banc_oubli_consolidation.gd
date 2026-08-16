extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_oubli_consolidation.gd
#
# Verrouille les fonctions PURES de scripts/banc_oubli_consolidation.gd
# (chantier « oubli exponentiel + consolidation nocturne »,
# audit_perception_croyance_memoire_prealable.md lignes 3 et 4). Le banc ne fait
# que CABLER cinq mecanismes du coeur deja verrouilles separement
# (croyance.gd/memoire_spatiale.gd/horloge.gd/perception.gd/monde.gd) : aucune
# de leurs lois n'est retestee ici, seuls le montage, la calibration et
# l'affichage le sont.
#
# DEUX MOITIES, comme les autres tests de banc :
# - HORS DOMAINE : une config, un catalogue de croyances, un catalogue de
#   memoire et un catalogue d'etats ENTIEREMENT INVENTES (canal "echo_vlok",
#   propriete observable "dur_vlok", menace "acide_vlok", etat "sursaut_vlok",
#   journee de 10 heures) traversent le meme code, avec des perceptions
#   FABRIQUEES A LA MAIN -- perception.gd n'est pas monte dans cette moitie.
#   Si le banc connaissait "vue", "comestible", "dangereux", "peur" ou 24
#   heures, ce bloc rougirait.
# - CHEMIN REEL : data/banc_oubli_consolidation.json + data/croyances.json +
#   data/memoire_spatiale.json + data/etats.json + data/canaux.json relus SUR LE
#   DISQUE, avec perception.gd et monde.gd reels, pour verifier la CALIBRATION
#   (l'oubli est-il visible ? la consolidation rattrape-t-elle vraiment ? la
#   braise tient-elle plus longtemps que la baie ?) -- meme discipline que la
#   correction banc_maladie, ou un test qui ne rejouait jamais le JSON reel
#   laissait passer une calibration qui ne declenchait rien.

const Banc = preload("res://scripts/banc_oubli_consolidation.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

const CONFIG_VLOK := {
	"cycle": {
		"duree_jour_secondes": 20.0,
		"heures_par_jour": 10.0,
		"heure_depart": 3.0,
		"heure_coucher": 8.0,
		"heure_lever": 2.0,
	},
	"nom_canal_vue": "echo_vlok",
	"nom_propriete_repere": "trace_vlok",
	"nom_propriete_menace": "acide_vlok",
	"nom_propriete_charge": "tension_vlok",
	"nom_etat_peur": "sursaut_vlok",
	"nom_registre_espacement": "etirement_vlok",
	"nom_registre_charge": "tension_par_trace_vlok",
	"cadence_observation": 2.0,
	"espacement_initial": 4.0,
	"gain_espacement_par_rappel": 1.5,
	"plafond_espacement": 9.0,
	"charge_neutre": 1.0,
	"plafond_force_memoire": 1.0,
	"heures_minimum_sommeil": 2.0,
	"cadence_consolidation": 1.0,
	"consolidations_max_par_nuit": 3,
	"gain_consolidation_certitude": 0.05,
	"gain_consolidation_force": 0.07,
	"retrait_a": 5.0,
	"retour_a": 20.0,
	"redepart_a": 24.0,
	"id_objet_rappele": "trace_a_vlok",
	"colon": { "id": "sonde_vlok", "position": [0.0, 0.0, 0.0], "portee_vue": 400.0 },
	"objets": {
		"trace_a_vlok": {
			"position": [100.0, 0.0, 0.0],
			"position_lointaine": [9000.0, 0.0, 0.0],
			"proprietes": { "dur_vlok": true, "trace_vlok": true },
		},
		"trace_b_vlok": {
			"position": [-100.0, 0.0, 0.0],
			"position_lointaine": [-9000.0, 0.0, 0.0],
			"proprietes": { "dur_vlok": true, "trace_vlok": true, "acide_vlok": true },
		},
	},
}

const CROYANCES_VLOK := {
	"proprietes_observables": ["dur_vlok"],
	"proprietes_conservees": [],
	"certitude_initiale": 0.4,
	"gain_par_verification": 0.2,
	"plafond_certitude": 1.0,
	"taux_decroissance": 999.0,
	"plancher_suppression": 0.05,
	"gain_par_echec": 0.8,
	"resistance_par_certitude": 0.9,
}

const MEMOIRE_VLOK := {
	"defaut": {
		"force_initiale": 0.5,
		"taux_decroissance": 999.0,
		"plancher_suppression": 0.05,
		"coef_memoire_faible": 1.0,
		"coef_nuit": 0.6,
	},
}

const ETATS_VLOK := {
	"sursaut_vlok": {
		"effets": [{ "propriete": "tension_vlok", "mode": "moduler", "facteur": 3.0 }],
	},
}

func _init() -> void:
	var v := Verif.new()
	_horloge_et_nuit_qui_enjambe_minuit(v)
	_jalons_de_position(v)
	_peur_posee_puis_effacee_et_charge_composee(v)
	_observation_forme_croyance_souvenir_et_etire_l_espacement(v)
	_charge_figee_seulement_sur_la_chose_qui_porte_la_menace(v)
	_decroissance_plus_rapide_au_debut_puis_qui_ralentit(v)
	_rappel_remonte_certitude_et_force(v)
	_charge_emotionnelle_ralentit_l_oubli(v)
	_sous_le_plancher_le_souvenir_disparait(v)
	_pas_de_consolidation_sous_le_minimum_d_heures(v)
	_consolidation_remonte_la_memoire_et_plafonne_par_nuit(v)
	_reveil_remet_les_compteurs_a_zero(v)
	_catalogues_du_disque_jamais_mutes(v)
	_chemin_reel_calibration(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_oubli_consolidation -- horloge du coeur et nuit qui enjambe minuit sans supposer 24 heures, " +
			"peur posee tant que la menace est percue puis effacee (charge emotionnelle composee par etat_effectif), " +
			"observation qui forme croyance ET souvenir et ETIRE l'espacement sous plafond de cablage, " +
			"charge figee au seul souvenir de la chose qui porte la menace, " +
			"decroissance exponentielle prouvee par des pertes successives strictement decroissantes, " +
			"rappel qui remonte certitude et force, charge emotionnelle qui ralentit l'oubli a certitude egale, " +
			"souvenir retire par le MECANISME sous son propre plancher (balayage a delta nul), " +
			"aucune consolidation sous le minimum d'heures dormies, consolidation qui remonte la memoire et plafonne par nuit, " +
			"compteurs remis a zero au reveil, catalogues du disque jamais mutes, " +
			"et sur le chemin reel une calibration ou tout cela est reellement atteignable")
		quit(0)

# ---------------------------------------------------------------------------
# HORS DOMAINE
# ---------------------------------------------------------------------------

func _percevoir_vlok(ids: Array) -> Array:
	var perceptions: Array = []
	for id in ids:
		var decl: Dictionary = CONFIG_VLOK.objets[id]
		var pos: Array = decl.position
		perceptions.append({
			"chose": {
				"id": String(id),
				"position": Vector3(pos[0], pos[1], pos[2]),
				"proprietes": decl.proprietes.duplicate(true),
			},
			"type": "",
			"position": Vector3(pos[0], pos[1], pos[2]),
			"distance": 100.0,
			"canaux": [CONFIG_VLOK.nom_canal_vue],
		})
	return perceptions

func _horloge_et_nuit_qui_enjambe_minuit(v) -> void:
	# Journee de 10 heures mappee sur 20 s : 2 s par heure, depart a 3 h.
	v.v(is_equal_approx(Banc.heure_a(0.0, CONFIG_VLOK), 3.0), "a t=0 l'heure doit valoir heure_depart")
	v.v(is_equal_approx(Banc.heure_a(4.0, CONFIG_VLOK), 5.0), "4 s reelles = 2 heures sur une journee de 10 h en 20 s")
	v.v(is_equal_approx(Banc.heure_a(20.0, CONFIG_VLOK), 3.0), "l'heure doit BOUCLER sur heures_par_jour, jamais sur 24.0 en dur")

	# Zone 8 h -> 2 h : elle ENJAMBE minuit, un « entre deux bornes » serait faux.
	v.v(not Banc.nuit_a(5.0, CONFIG_VLOK), "5 h est en plein jour dans une zone 8 -> 2")
	v.v(Banc.nuit_a(9.0, CONFIG_VLOK), "9 h est apres le coucher")
	v.v(Banc.nuit_a(1.0, CONFIG_VLOK), "1 h est avant le lever -- c'est l'enjambement de minuit")
	v.v(Banc.dort_a(5.0, CONFIG_VLOK, true), "le forcage doit endormir meme en plein jour")
	v.v(Banc.dort_a(9.0, CONFIG_VLOK, false), "la nuit doit endormir sans aucun forcage")

func _jalons_de_position(v) -> void:
	var proche := Banc.position_objet("trace_a_vlok", 1.0, false, CONFIG_VLOK)
	var loin := Banc.position_objet("trace_a_vlok", 10.0, false, CONFIG_VLOK)
	v.v(proche.x == 100.0, "avant retrait_a l'objet doit etre a sa position declaree")
	v.v(loin.x == 9000.0, "apres retrait_a l'objet doit etre eloigne, jamais retire du monde")
	v.v(Banc.position_objet("trace_a_vlok", 21.0, false, CONFIG_VLOK).x == 100.0,
		"entre retour_a et redepart_a l'objet RAPPELE doit revenir")
	v.v(Banc.position_objet("trace_a_vlok", 30.0, false, CONFIG_VLOK).x == 9000.0,
		"apres redepart_a il doit repartir")
	v.v(Banc.position_objet("trace_b_vlok", 21.0, false, CONFIG_VLOK).x == -9000.0,
		"UN SEUL objet est rappele -- l'autre reste loin, sinon on ne saurait pas d'ou vient la remontee")
	v.v(Banc.position_objet("trace_a_vlok", 10.0, true, CONFIG_VLOK).x == 100.0,
		"le forcage clavier doit ramener l'objet rappele immediatement")

func _peur_posee_puis_effacee_et_charge_composee(v) -> void:
	var colon := Banc.construire_colon(CONFIG_VLOK)
	v.v(is_equal_approx(Banc.charge_effective(colon, CONFIG_VLOK, ETATS_VLOK), 1.0),
		"sans etat, la charge effective doit valoir la base -- jamais 0.0, qui ferait diviser par zero")

	v.v(not Banc.poser_peur(colon, _percevoir_vlok(["trace_a_vlok"]), CONFIG_VLOK, ETATS_VLOK),
		"une chose sans la propriete de menace ne doit poser aucune peur")
	v.v(Banc.poser_peur(colon, _percevoir_vlok(["trace_b_vlok"]), CONFIG_VLOK, ETATS_VLOK),
		"une chose PORTANT la propriete de menace doit poser la peur -- filtre sur une propriete, jamais un type")
	v.v(colon.proprietes.etats_actifs.has(CONFIG_VLOK.nom_etat_peur), "l'etat doit etre reellement pose dans etats_actifs")
	v.v(is_equal_approx(Banc.charge_effective(colon, CONFIG_VLOK, ETATS_VLOK), 3.0),
		"la charge effective doit etre composee par etat_effectif.gd, jamais recalculee par le banc")

	Banc.poser_peur(colon, [], CONFIG_VLOK, ETATS_VLOK)
	v.v(not colon.proprietes.etats_actifs.has(CONFIG_VLOK.nom_etat_peur),
		"la menace disparue, le CABLAGE doit effacer l'etat -- 'peur' n'a pas de duree, rien ne le retirerait sinon")

func _observation_forme_croyance_souvenir_et_etire_l_espacement(v) -> void:
	var colon := Banc.construire_colon(CONFIG_VLOK)
	var observes: Array = Banc.observer_si_cadence(
		colon, _percevoir_vlok(["trace_a_vlok"]), CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 1.0, 0.0)
	v.v(observes.size() == 1, "une observation a la cadence doit rendre l'id observe")
	v.v(is_equal_approx(Banc.certitude_de(colon, "trace_a_vlok"), 0.4), "la premiere observation pose certitude_initiale")
	v.v(is_equal_approx(Banc.force_de(colon, "trace_a_vlok"), 0.5), "la premiere observation pose force_initiale")
	v.v(is_equal_approx(Banc.espacement_de(colon, "trace_a_vlok", CONFIG_VLOK), 4.0),
		"la premiere observation POSE l'espacement initial, elle ne l'etire pas")

	v.v(Banc.observer_si_cadence(colon, _percevoir_vlok(["trace_a_vlok"]), CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 1.0, 1.0).is_empty(),
		"sous la cadence, aucune observation -- sinon la certitude saturerait en quelques images")

	Banc.observer_si_cadence(colon, _percevoir_vlok(["trace_a_vlok"]), CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 1.0, 2.0)
	v.v(is_equal_approx(Banc.certitude_de(colon, "trace_a_vlok"), 0.6), "la seconde observation ajoute gain_par_verification")
	v.v(is_equal_approx(Banc.espacement_de(colon, "trace_a_vlok", CONFIG_VLOK), 6.0),
		"L'EFFET D'ESPACEMENT : la seconde observation multiplie S par gain_espacement_par_rappel")

	# Plafond du cablage : le coeur ne borne jamais le haut.
	for i in range(6):
		Banc.observer_si_cadence(colon, _percevoir_vlok(["trace_a_vlok"]), CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 1.0, 4.0 + float(i) * 2.0)
	v.v(is_equal_approx(Banc.espacement_de(colon, "trace_a_vlok", CONFIG_VLOK), 9.0),
		"l'espacement doit etre ECRETE au plafond du cablage -- sinon le taux tendrait vers zero et le souvenir serait eternel")
	Banc.plafonner_memoire(colon, CONFIG_VLOK)
	v.v(is_equal_approx(Banc.force_de(colon, "trace_a_vlok"), 1.0),
		"la force accumulee doit etre ECRETEE au plafond du cablage (memoire_spatiale.gd ne borne pas le haut)")

func _charge_figee_seulement_sur_la_chose_qui_porte_la_menace(v) -> void:
	var colon := Banc.construire_colon(CONFIG_VLOK)
	var perceptions := _percevoir_vlok(["trace_a_vlok", "trace_b_vlok"])
	Banc.poser_peur(colon, perceptions, CONFIG_VLOK, ETATS_VLOK)
	var charge: float = Banc.charge_effective(colon, CONFIG_VLOK, ETATS_VLOK)
	Banc.observer_si_cadence(colon, perceptions, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, charge, 0.0)

	v.v(is_equal_approx(Banc.charge_de(colon, "trace_b_vlok", CONFIG_VLOK), 3.0),
		"la charge doit etre FIGEE sur le souvenir de la chose qui porte la menace")
	v.v(is_equal_approx(Banc.charge_de(colon, "trace_a_vlok", CONFIG_VLOK), 1.0),
		"un souvenir neutre observe DANS LE MEME instant de panique doit rester au point neutre -- " +
		"sans quoi l'emotion s'attacherait au colon et non au souvenir, et la ligne 3 serait fausse")

	Banc.poser_peur(colon, [], CONFIG_VLOK, ETATS_VLOK)
	v.v(is_equal_approx(Banc.charge_de(colon, "trace_b_vlok", CONFIG_VLOK), 3.0),
		"la peur retombee, le souvenir doit RESTER charge -- c'est tout le sujet")

func _decroissance_plus_rapide_au_debut_puis_qui_ralentit(v) -> void:
	var colon := Banc.construire_colon(CONFIG_VLOK)
	Banc.observer_si_cadence(colon, _percevoir_vlok(["trace_a_vlok"]), CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 1.0, 0.0)

	var pertes: Array = []
	for i in range(5):
		var avant: float = Banc.certitude_de(colon, "trace_a_vlok")
		for j in range(10):
			Banc.oublier(colon, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 0.05)
		pertes.append(avant - Banc.certitude_de(colon, "trace_a_vlok"))

	for i in range(1, pertes.size()):
		v.v(float(pertes[i]) < float(pertes[i - 1]),
			"EXPONENTIELLE : la perte de la tranche %d doit etre STRICTEMENT inferieure a celle de la tranche %d" % [i, i - 1])
	v.v(float(pertes[0]) > 0.0, "la premiere tranche doit reellement perdre quelque chose")

	# Le taux n'est pas une constante : il est proportionnel a ce qui reste.
	var taux_bas: float = Banc.taux_effectif(Banc.certitude_de(colon, "trace_a_vlok"), colon, "trace_a_vlok", CONFIG_VLOK)
	v.v(taux_bas < 0.4 / 4.0, "le taux effectif doit avoir BAISSE avec la certitude -- c'est ce qui fait l'exponentielle")

func _rappel_remonte_certitude_et_force(v) -> void:
	var colon := Banc.construire_colon(CONFIG_VLOK)
	Banc.observer_si_cadence(colon, _percevoir_vlok(["trace_a_vlok"]), CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 1.0, 0.0)
	for i in range(40):
		Banc.oublier(colon, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 0.05)
	var certitude_creuse: float = Banc.certitude_de(colon, "trace_a_vlok")
	var force_creuse: float = Banc.force_de(colon, "trace_a_vlok")
	v.v(certitude_creuse < 0.4 and force_creuse < 0.5, "l'oubli doit avoir mordu avant le rappel")

	Banc.observer_si_cadence(colon, _percevoir_vlok(["trace_a_vlok"]), CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 1.0, 10.0)
	v.v(Banc.certitude_de(colon, "trace_a_vlok") > certitude_creuse, "LE RAPPEL doit remonter la certitude")
	v.v(Banc.force_de(colon, "trace_a_vlok") > force_creuse, "LE RAPPEL doit remonter la force du souvenir")

func _charge_emotionnelle_ralentit_l_oubli(v) -> void:
	var colon := Banc.construire_colon(CONFIG_VLOK)
	var perceptions := _percevoir_vlok(["trace_a_vlok", "trace_b_vlok"])
	Banc.poser_peur(colon, perceptions, CONFIG_VLOK, ETATS_VLOK)
	Banc.observer_si_cadence(
		colon, perceptions, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK,
		Banc.charge_effective(colon, CONFIG_VLOK, ETATS_VLOK), 0.0)
	Banc.poser_peur(colon, [], CONFIG_VLOK, ETATS_VLOK)

	v.v(is_equal_approx(Banc.certitude_de(colon, "trace_a_vlok"), Banc.certitude_de(colon, "trace_b_vlok")),
		"les deux souvenirs doivent partir de la MEME certitude -- sinon la comparaison ne prouverait rien")
	for i in range(40):
		Banc.oublier(colon, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 0.05)

	v.v(Banc.certitude_de(colon, "trace_b_vlok") > Banc.certitude_de(colon, "trace_a_vlok"),
		"a certitude de depart EGALE, le souvenir charge doit avoir MOINS decru")
	v.v(Banc.force_de(colon, "trace_b_vlok") > Banc.force_de(colon, "trace_a_vlok"),
		"la charge doit ralentir l'oubli de la memoire spatiale exactement comme celui de la croyance")

func _sous_le_plancher_le_souvenir_disparait(v) -> void:
	var colon := Banc.construire_colon(CONFIG_VLOK)
	Banc.observer_si_cadence(colon, _percevoir_vlok(["trace_a_vlok"]), CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 1.0, 0.0)
	v.v(colon.proprietes.croyances.has("trace_a_vlok"), "la croyance doit exister avant d'etre oubliee")

	for i in range(600):
		Banc.oublier(colon, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 0.05)

	v.v(not colon.proprietes.croyances.has("trace_a_vlok"),
		"sous le plancher, la chose doit avoir DISPARU des croyances -- retrait fait par le MECANISME lui-meme " +
		"(balayage a delta nul), jamais par un plancher recopie dans le banc")
	v.v(not colon.proprietes.memoire_spatiale.has("trace_a_vlok"),
		"le souvenir spatial doit avoir disparu du registre par le meme balayage")
	v.v(is_equal_approx(Banc.certitude_de(colon, "trace_a_vlok"), 0.0), "une chose oubliee doit se lire 0.0, jamais une valeur residuelle")

func _pas_de_consolidation_sous_le_minimum_d_heures(v) -> void:
	var colon := _colon_endormi_avec_souvenir(1.0)
	v.v(Banc.consolider_si_possible(colon, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 0.0) == 0,
		"sous heures_minimum_sommeil, aucune consolidation -- une sieste ne fixe rien")

	var eveille := _colon_endormi_avec_souvenir(5.0)
	eveille.proprietes["dort"] = false
	v.v(Banc.consolider_si_possible(eveille, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 0.0) == 0,
		"un colon eveille ne consolide jamais, quel qu'ait ete son sommeil")

func _consolidation_remonte_la_memoire_et_plafonne_par_nuit(v) -> void:
	var colon := _colon_endormi_avec_souvenir(5.0)
	var certitude_avant: float = Banc.certitude_de(colon, "trace_a_vlok")
	var force_avant: float = Banc.force_de(colon, "trace_a_vlok")

	v.v(Banc.consolider_si_possible(colon, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 0.0) == 1,
		"au-dela du minimum d'heures dormies, la consolidation doit avoir lieu")
	v.v(Banc.certitude_de(colon, "trace_a_vlok") > certitude_avant, "LA CONSOLIDATION doit remonter la certitude")
	v.v(Banc.force_de(colon, "trace_a_vlok") > force_avant, "LA CONSOLIDATION doit remonter la force du souvenir")
	v.v(is_equal_approx(Banc.certitude_de(colon, "trace_a_vlok"), certitude_avant + 0.05),
		"le gain doit etre celui du SOMMEIL (gain_consolidation_certitude), jamais gain_par_verification")

	v.v(Banc.consolider_si_possible(colon, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 0.5) == 0,
		"sous la cadence de consolidation, aucune passe de plus")

	var temps := 1.0
	while Banc.consolider_si_possible(colon, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, temps) == 1:
		temps += 1.0
	v.v(int(colon.proprietes.consolidations_ce_cycle) == int(CONFIG_VLOK.consolidations_max_par_nuit),
		"le plafond par nuit doit arreter la consolidation a consolidations_max_par_nuit")

	# DEFAUT REEL TROUVE EN LANCANT LA SCENE, verrouille ici : une chose dont la
	# CROYANCE est tombee sous le plancher ne doit plus voir sa POSITION
	# reconsolidee -- sinon elle remonte plus chaque nuit qu'elle ne decroit le
	# jour, et le souvenir devient immortel alors que le colon ne sait plus rien.
	var amnesique := _colon_endormi_avec_souvenir(5.0)
	amnesique.proprietes.croyances.erase("trace_a_vlok")
	var force_orpheline: float = Banc.force_de(amnesique, "trace_a_vlok")
	Banc.consolider_si_possible(amnesique, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 0.0)
	v.v(is_equal_approx(Banc.force_de(amnesique, "trace_a_vlok"), force_orpheline),
		"un souvenir spatial ORPHELIN (croyance oubliee) ne doit plus etre consolide")

	# Le sommeil ne peut renforcer QUE ce qui a ete percu eveille.
	var vierge := Banc.construire_colon(CONFIG_VLOK)
	vierge.proprietes["dort"] = true
	vierge.proprietes["heures_dormies_ce_cycle"] = 5.0
	Banc.consolider_si_possible(vierge, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 0.0)
	v.v(vierge.proprietes.croyances.is_empty() and vierge.proprietes.memoire_spatiale.is_empty(),
		"le sommeil ne doit RIEN inventer : sans croyance prealable, la consolidation ne cree aucune entree")

func _reveil_remet_les_compteurs_a_zero(v) -> void:
	var colon := _colon_endormi_avec_souvenir(5.0)
	Banc.consolider_si_possible(colon, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 0.0)
	v.v(int(colon.proprietes.consolidations_ce_cycle) == 1, "la passe doit avoir ete comptee")

	v.v(not Banc.cumuler_sommeil(colon, true, 0.5), "dormir encore n'est pas un reveil")
	v.v(is_equal_approx(float(colon.proprietes.heures_dormies_ce_cycle), 5.5),
		"les heures dormies doivent s'ACCUMULER -- aucun mecanisme du coeur ne les compte")
	v.v(Banc.cumuler_sommeil(colon, false, 0.5), "passer de dort a eveille doit etre signale comme un reveil")
	v.v(is_equal_approx(float(colon.proprietes.heures_dormies_ce_cycle), 0.0) and int(colon.proprietes.consolidations_ce_cycle) == 0,
		"le reveil doit remettre les DEUX compteurs de cycle a zero")

func _catalogues_du_disque_jamais_mutes(v) -> void:
	var colon := _colon_endormi_avec_souvenir(5.0)
	var taux_avant: float = float(CROYANCES_VLOK.taux_decroissance)
	var gain_avant: float = float(CROYANCES_VLOK.gain_par_verification)
	var force_avant: float = float(MEMOIRE_VLOK.defaut.force_initiale)
	Banc.consolider_si_possible(colon, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 0.0)
	Banc.oublier(colon, CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 0.1)
	v.v(is_equal_approx(float(CROYANCES_VLOK.taux_decroissance), taux_avant)
		and is_equal_approx(float(CROYANCES_VLOK.gain_par_verification), gain_avant)
		and is_equal_approx(float(MEMOIRE_VLOK.defaut.force_initiale), force_avant),
		"les catalogues recus doivent etre DUPLIQUES avant reecriture -- jamais mutes, ils sont partages")

func _colon_endormi_avec_souvenir(heures: float) -> Dictionary:
	var colon := Banc.construire_colon(CONFIG_VLOK)
	Banc.observer_si_cadence(colon, _percevoir_vlok(["trace_a_vlok"]), CONFIG_VLOK, CROYANCES_VLOK, MEMOIRE_VLOK, 1.0, 0.0)
	colon.proprietes["dort"] = true
	colon.proprietes["heures_dormies_ce_cycle"] = heures
	return colon

# ---------------------------------------------------------------------------
# CHEMIN REEL -- les fichiers du disque, perception.gd et monde.gd reels
# ---------------------------------------------------------------------------

func _chemin_reel_calibration(v) -> void:
	var config := _charger("res://data/banc_oubli_consolidation.json")
	var canaux := _charger("res://data/canaux.json")
	var croyances := _charger("res://data/croyances.json")
	var memoire := _charger("res://data/memoire_spatiale.json")
	var etats := _charger("res://data/etats.json")

	v.v(etats.has(config.nom_etat_peur), "l'etat de peur du banc doit exister dans data/etats.json")
	var porte_charge := false
	for effet in etats[config.nom_etat_peur].effets:
		if String(effet.propriete) == String(config.nom_propriete_charge):
			porte_charge = true
			v.v(String(effet.mode) == "moduler" and float(effet.facteur) > 1.0,
				"la charge emotionnelle doit MODULER par un facteur > 1.0 -- un facteur <= 1.0 accelererait l'oubli")
	v.v(porte_charge, "data/etats.json doit declarer l'effet de charge emotionnelle sur l'etat de peur")

	var colon := Banc.construire_colon(config)
	var objets := Banc.construire_objets(config)
	var monde = Monde.new()
	monde.ajouter(colon, "colon", colon.position)
	for objet in objets:
		monde.ajouter(objet, "objet", objet.position)

	var delta := 1.0 / 60.0
	var temps := 0.0
	var bilan: Dictionary = {}
	var mesures: Dictionary = {}
	var oublies_total: Array = []
	var consolidations_totales := 0
	while temps < 48.0:
		temps += delta
		bilan = Banc.avancer(colon, objets, monde, config, canaux, croyances, memoire, etats,
			false, false, temps, delta)
		consolidations_totales += int(bilan.consolidations_ce_pas)
		for id in bilan.oublies:
			oublies_total.append(String(id))
		for jalon in [6.0, 12.0, 22.0, 30.0]:
			if temps - delta < jalon and temps >= jalon:
				mesures[jalon] = Banc.souvenirs_de(colon, objets, config)

	v.v(mesures.has(6.0) and mesures.has(12.0) and mesures.has(22.0) and mesures.has(30.0),
		"les quatre jalons de mesure doivent avoir ete traverses")

	var a_6: Dictionary = _souvenir(mesures[6.0], String(config.id_objet_rappele))
	var a_12: Dictionary = _souvenir(mesures[12.0], String(config.id_objet_rappele))
	var a_22: Dictionary = _souvenir(mesures[22.0], String(config.id_objet_rappele))
	var a_30: Dictionary = _souvenir(mesures[30.0], String(config.id_objet_rappele))

	v.v(float(a_6.certitude) > 0.0 and float(a_6.force) > 0.0,
		"CALIBRATION : la phase de PERCEPTION doit avoir forme une croyance ET un souvenir spatial")
	v.v(float(a_12.certitude) < float(a_6.certitude),
		"CALIBRATION : la phase d'OUBLI doit etre visible -- la certitude doit avoir baisse entre t=6 et t=12")
	v.v(float(a_22.certitude) > 0.0,
		"CALIBRATION : la CONSOLIDATION doit avoir empeche l'oubli complet pendant la nuit")
	v.v(consolidations_totales > 0, "CALIBRATION : au moins une passe de consolidation doit avoir eu lieu en 48 s")
	v.v(float(a_30.certitude) > float(a_22.certitude),
		"CALIBRATION : le RAPPEL (retour de l'objet) doit remonter la certitude au-dessus de son creux")

	# La braise -- le souvenir CHARGE -- doit tenir plus longtemps que la baie.
	var neutre := ""
	for cle in config.objets:
		if String(cle) != String(config.id_objet_rappele) and not bool(config.objets[cle].proprietes.get(config.nom_propriete_menace, false)):
			neutre = String(cle)
	var charge_id := ""
	for cle in config.objets:
		if bool(config.objets[cle].proprietes.get(config.nom_propriete_menace, false)):
			charge_id = String(cle)
	v.v(neutre != "" and charge_id != "", "le banc doit porter au moins un objet neutre et un objet qui porte la menace")

	var s_neutre: Dictionary = _souvenir(mesures[12.0], neutre)
	var s_charge: Dictionary = _souvenir(mesures[12.0], charge_id)
	v.v(is_equal_approx(float(s_charge.charge), 2.0),
		"CALIBRATION : le souvenir de l'objet menacant doit porter la charge composee par data/etats.json (x2.0)")
	v.v(is_equal_approx(float(s_neutre.charge), float(config.charge_neutre)),
		"CALIBRATION : le souvenir neutre doit rester au point neutre")
	v.v(float(s_charge.certitude) > float(s_neutre.certitude),
		"CALIBRATION : a t=12, le souvenir CHARGE doit avoir mieux tenu que le souvenir neutre")

	v.v(float(bilan.heure) >= 0.0 and float(bilan.heure) < float(config.cycle.heures_par_jour),
		"l'heure rendue doit toujours rester dans la journee declaree")
	var texte: String = Banc.texte_souvenir(s_charge)
	v.v(texte.find("certitude") >= 0 and texte.find("force") >= 0 and texte.find("charge") >= 0,
		"le label doit porter certitude, force, taux et charge -- il LIT le bilan, il ne recalcule rien")
	v.v(Banc.texte_colon(bilan, config).find("heures dormies") >= 0,
		"le label du colon doit porter les heures dormies")

func _souvenir(souvenirs: Array, id: String) -> Dictionary:
	for s in souvenirs:
		if String(s.id) == id:
			return s
	return {}

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
