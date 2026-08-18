extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_faim_thermo.gd
#
# Verrouille les fonctions PURES de scripts/banc_faim_thermo.gd (chantier
# « faim + thermoregulation -- un seul banc »). Le banc ne fait que CABLER
# cinq mecanismes du coeur deja verrouilles separement (depense.gd/
# velocite.gd/temperature.gd/seuil_etat.gd/etat_effectif.gd, TOUS INCHANGES
# par ce chantier) : aucune de leurs lois n'est retestee ici. Ce qui est
# teste, c'est ce que le CABLAGE ajoute -- la somme des surcouts en UNE
# ecriture, les trois miroirs plats, et la calibration reelle des seuils.
#
# DEUX MOITIES, comme les autres tests de banc :
# - HORS DOMAINE : une config, un catalogue de seuils et un catalogue d'etats
#   ENTIEREMENT INVENTES (reserve "flux_vlok", vitesse "allure_vlok", miroirs
#   "creux_vlok"/"gel_vlok"/"brulure_vlok", etats "vide_vlok"/"gele_vlok"/
#   "cuit_vlok", degres "vlok" ou le confort est a 100) traversent le meme
#   code. Si le banc nommait "energie", "vitesse", "affame", "manque_energie"
#   ou "froid_ressenti" en dur, ce bloc rougirait.
# - CHEMIN REEL : data/banc_faim_thermo.json + data/temperature.json +
#   data/seuils_etat.json + data/etats.json relus SUR LE DISQUE, pour verifier
#   la CALIBRATION (les quatre etats reellement atteignables sur le terrain) et
#   l'ACCORD entre les noms de miroirs du banc et les propriete_continue des
#   entrees partagees -- accord qu'aucun autre test ne verifie et dont la
#   rupture serait SILENCIEUSE (un miroir ecrit sous un nom que personne ne
#   compare : aucun etat ne se poserait plus jamais, sans une seule alarme).

const Banc = preload("res://scripts/banc_faim_thermo.gd")
const Depense = preload("res://scripts/depense.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Temperature = preload("res://scripts/temperature.gd")
const Verif = preload("res://scripts/verif.gd")

# Domaine invente de bout en bout. Le confort est a 100 degres "vlok" et la
# bande neutre va de 100 a 140 : rien ici ne ressemble a un corps humain.
const CONFIG_VLOK := {
	"graine": 7,
	"terrain_largeur": 50.0,
	"terrain_hauteur": 30.0,
	"position_depart": [10.0, 5.0, 0.0],
	"rayon_arrivee": 1.0,
	"vitesse_base": 10.0,
	"capacite_energie": 20.0,
	"metabolisme_base_par_s": 2.0,
	"coef_effort": 0.5,
	"temp_cible": 100.0,
	"seuil_chaud": 140.0,
	"cout_par_degre_froid": 3.0,
	"cout_par_degre_chaud": 7.0,
	"nom_reserve_energie": "flux_vlok",
	"nom_vitesse": "allure_vlok",
	"nom_manque_energie": "creux_vlok",
	"nom_froid_ressenti": "gel_vlok",
	"nom_chaud_ressenti": "brulure_vlok",
	"ref_seuil_faim": "creux_vlok",
	"zones": [
		{ "id": "froid_vlok", "position": [0.0, 0.0, 0.0], "rayon": 10.0, "temperature": 60.0, "force": 1.0, "couleur": [0.0, 0.0, 1.0] },
		{ "id": "chaud_vlok", "position": [40.0, 0.0, 0.0], "rayon": 10.0, "temperature": 200.0, "force": 1.0, "couleur": [1.0, 0.0, 0.0] },
	],
	"couleur_zone_neutre": [0.0, 1.0, 0.0],
	"couleur_colon": [1.0, 1.0, 1.0],
	"taille_colon": 2.0,
}

const SEUILS_VLOK := {
	"creux_vlok": { "propriete_continue": "creux_vlok", "seuil": 12.0, "etat": "vide_vlok" },
	"gel_vlok": { "propriete_continue": "gel_vlok", "seuil": 4.0, "etat": "gele_vlok" },
	"gel_profond_vlok": { "propriete_continue": "gel_vlok", "seuil": 9.0, "etat": "fige_vlok" },
	"brulure_vlok": { "propriete_continue": "brulure_vlok", "seuil": 6.0, "etat": "cuit_vlok" },
}

const ETATS_VLOK := {
	"vide_vlok": { "effets": [ { "propriete": "allure_vlok", "mode": "moduler", "facteur": 0.25 } ] },
	"gele_vlok": { "effets": [ { "propriete": "allure_vlok", "mode": "moduler", "facteur": 0.5 } ] },
	"fige_vlok": { "effets": [ { "propriete": "allure_vlok", "mode": "moduler", "facteur": 0.1 } ] },
	"cuit_vlok": { "effets": [ { "propriete": "allure_vlok", "mode": "moduler", "facteur": 0.2 } ] },
}

func _init() -> void:
	var v := Verif.new()
	# Hors domaine.
	_colon_pose_sans_type_ni_temperature(v)
	_metabolisme_de_base_consomme_en_permanence(v)
	_le_mouvement_augmente_la_consommation(v)
	_le_froid_augmente_la_consommation(v)
	_le_chaud_augmente_la_consommation(v)
	_les_surcouts_se_somment_en_une_seule_ecriture(v)
	_hors_zone_aucun_surcout_thermique(v)
	_manque_energie_monte_quand_la_reserve_descend(v)
	_les_quatre_etats_sont_poses_au_seuil_et_retires_en_dessous(v)
	_vitesse_effective_composee_puis_nulle_a_reserve_vide(v)
	_changements_etats_et_projections(v)
	_cible_aleatoire_reste_dans_le_terrain_et_a_plat(v)
	# Chemin reel.
	_chemin_reel_les_noms_de_miroirs_sont_ceux_du_catalogue_partage(v)
	_chemin_reel_calibration_des_deux_zones(v)
	_chemin_reel_les_quatre_etats_sont_atteignables(v)

	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_faim_thermo -- metabolisme de base permanent, mouvement et froid et chaud " +
			"augmentant chacun la consommation, surcouts sommes en UNE SEULE ecriture de surcout_action, " +
			"aucun surcout thermique hors zone, manque_energie montant quand la reserve descend, " +
			"affame/frisson/hypothermie/hyperthermie poses au seuil et retires en dessous, " +
			"vitesse composee multiplicativement puis nulle a reserve vide, " +
			"un domaine invente traverse le meme code, et sur le chemin reel les noms de miroirs " +
			"correspondent aux entrees partagees et les quatre etats sont atteignables sur le terrain")
		quit(0)

# ---- Hors domaine ----

func _colon_pose_sans_type_ni_temperature(v) -> void:
	var colon: Dictionary = Banc.construire_colon(CONFIG_VLOK)
	var p: Dictionary = colon.proprietes
	v.v(colon.position == Vector3(10.0, 5.0, 0.0), "le colon doit partir de position_depart")
	v.v(colon.position.z == 0.0, "VERTICALITE : position.z doit rester 0.0 (Vector3 partout, meme a plat)")
	v.v(p.has("reserves") and p.reserves.has("flux_vlok"),
		"le canal de reserve doit porter le nom donne en DONNEE, jamais 'energie' en dur")
	v.v(is_equal_approx(float(p.reserves.flux_vlok.reserve), 20.0), "la reserve doit partir a capacite_energie")
	v.v(is_equal_approx(float(p.reserves.flux_vlok.cout_base), 2.0),
		"le metabolisme de base doit etre pose comme cout_base une fois pour toutes")
	v.v(is_equal_approx(float(p.reserves.flux_vlok.surcout_action), 0.0), "surcout_action doit partir a 0.0")
	v.v(is_equal_approx(float(p.allure_vlok), 10.0), "la vitesse de base doit etre posee sous le nom donne en donnee")
	v.v(not p.has("temperature"),
		"le colon ne doit porter AUCUNE propriete 'temperature' : ce banc n'appelle jamais temperature.gd:avancer, " +
		"et les entrees thermiques du catalogue PARTAGE doivent rester des chemins morts pour lui")
	v.v(p.get("etats_actifs", null) is Array and p.etats_actifs.is_empty(), "etats_actifs doit partir vide")

func _metabolisme_de_base_consomme_en_permanence(v) -> void:
	# Immobile, au confort exact : ni effort, ni thermique. La reserve doit
	# TOUT DE MEME descendre, au seul cout_base.
	var colon: Dictionary = Banc.construire_colon(CONFIG_VLOK)
	var monde: Array = [colon]
	for i in range(4):
		Banc.poser_surcout_action(colon, 100.0, CONFIG_VLOK)
		Depense.avancer(monde, 0.5)
	v.v(is_equal_approx(float(colon.proprietes.reserves.flux_vlok.reserve), 20.0 - 2.0 * 0.5 * 4),
		"METABOLISME DE BASE : au repos et au confort, la reserve doit descendre exactement de cout_base*delta a chaque tick")
	v.v(is_equal_approx(float(colon.proprietes.reserves.flux_vlok.surcout_action), 0.0),
		"au repos et au confort, surcout_action doit rester exactement 0.0 -- toute la depense vient de cout_base")

func _le_mouvement_augmente_la_consommation(v) -> void:
	var immobile: Dictionary = Banc.construire_colon(CONFIG_VLOK)
	var mouvant: Dictionary = Banc.construire_colon(CONFIG_VLOK)
	# Velocite ECRITE A LA MAIN ici : c'est velocite.gd qui la derive dans le
	# banc reel (verrouille par son propre test), ce test n'a pas a rejouer sa
	# loi -- seulement a prouver que le surcout la lit.
	mouvant.proprietes["velocite"] = Vector3(6.0, 8.0, 0.0)
	Banc.poser_surcout_action(immobile, 100.0, CONFIG_VLOK)
	Banc.poser_surcout_action(mouvant, 100.0, CONFIG_VLOK)
	var monde: Array = [immobile, mouvant]
	Depense.avancer(monde, 1.0)
	v.v(is_equal_approx(float(mouvant.proprietes.reserves.flux_vlok.surcout_action), 5.0),
		"EFFORT : coef_effort (0.5) x longueur de la velocite (10) doit donner exactement 5.0")
	v.v(float(mouvant.proprietes.reserves.flux_vlok.reserve) < float(immobile.proprietes.reserves.flux_vlok.reserve),
		"LE MOUVEMENT AUGMENTE LA CONSOMMATION : a temperature de confort, le colon qui bouge doit avoir moins d'energie que l'immobile")

func _le_froid_augmente_la_consommation(v) -> void:
	var neutre: Dictionary = Banc.construire_colon(CONFIG_VLOK)
	var gele: Dictionary = Banc.construire_colon(CONFIG_VLOK)
	Banc.poser_surcout_action(neutre, 100.0, CONFIG_VLOK)
	var decomposition: Dictionary = Banc.poser_surcout_action(gele, 90.0, CONFIG_VLOK)
	v.v(is_equal_approx(float(gele.proprietes.gel_vlok), 10.0),
		"FROID RESSENTI : 10 degres sous le confort doivent donner exactement 10.0 de froid, sous le nom donne en donnee")
	v.v(is_equal_approx(float(decomposition.thermo), 30.0),
		"LE FROID AUGMENTE LA CONSOMMATION : 10 degres de froid x cout_par_degre_froid (3.0) = 30.0")
	var monde: Array = [neutre, gele]
	Depense.avancer(monde, 0.1)
	v.v(float(gele.proprietes.reserves.flux_vlok.reserve) < float(neutre.proprietes.reserves.flux_vlok.reserve),
		"a effort egal (nul), le colon au froid doit perdre son energie plus vite que celui au confort")

func _le_chaud_augmente_la_consommation(v) -> void:
	var neutre: Dictionary = Banc.construire_colon(CONFIG_VLOK)
	var cuit: Dictionary = Banc.construire_colon(CONFIG_VLOK)
	# Juste SOUS le seuil chaud : rien ne doit se declencher -- « au-dessus d'un
	# seuil », jamais « des qu'il fait plus chaud que le confort ».
	var sous_le_seuil: Dictionary = Banc.poser_surcout_action(neutre, 139.0, CONFIG_VLOK)
	v.v(is_equal_approx(float(sous_le_seuil.thermo), 0.0),
		"SEUIL CHAUD : 39 degres au-dessus du confort mais SOUS seuil_chaud ne doivent rien couter -- la bande neutre existe")
	var decomposition: Dictionary = Banc.poser_surcout_action(cuit, 150.0, CONFIG_VLOK)
	v.v(is_equal_approx(float(cuit.proprietes.brulure_vlok), 10.0),
		"CHAUD RESSENTI : 10 degres au-dessus de seuil_chaud doivent donner exactement 10.0")
	v.v(is_equal_approx(float(decomposition.thermo), 70.0),
		"LE CHAUD AUGMENTE LA CONSOMMATION : 10 degres de chaud x cout_par_degre_chaud (7.0) = 70.0")
	v.v(is_equal_approx(float(cuit.proprietes.gel_vlok), 0.0),
		"les deux miroirs thermiques ne doivent JAMAIS etre non nuls en meme temps (seuil_chaud >= temp_cible)")

func _les_surcouts_se_somment_en_une_seule_ecriture(v) -> void:
	# LE PIEGE DE CE CHANTIER (audit, constat D) : un seul emplacement
	# surcout_action, trois contributions. Si un morceau de cablage ecrivait le
	# sien apres un autre, le total vaudrait l'un des deux au lieu de leur
	# somme -- en silence.
	var colon: Dictionary = Banc.construire_colon(CONFIG_VLOK)
	colon.proprietes["velocite"] = Vector3(10.0, 0.0, 0.0)
	var d: Dictionary = Banc.poser_surcout_action(colon, 90.0, CONFIG_VLOK)
	var pose: float = float(colon.proprietes.reserves.flux_vlok.surcout_action)
	v.v(is_equal_approx(float(d.effort), 5.0) and is_equal_approx(float(d.thermo), 30.0),
		"la decomposition rendue doit donner effort et thermo separement, pour un affichage qui ne recalcule rien")
	v.v(is_equal_approx(pose, 35.0),
		"SOMME : surcout_action doit valoir effort (5.0) + thermo (30.0) = 35.0, jamais l'un des deux seul")
	v.v(is_equal_approx(pose, float(d.total)), "le total rendu doit etre EXACTEMENT ce qui a ete ecrit dans le canal")
	# Idempotence : rappeler la fonction au meme etat REECRIT la meme valeur,
	# jamais une accumulation (le surcout est recalcule a neuf chaque tick).
	Banc.poser_surcout_action(colon, 90.0, CONFIG_VLOK)
	v.v(is_equal_approx(float(colon.proprietes.reserves.flux_vlok.surcout_action), 35.0),
		"IDEMPOTENCE : deux appels au meme etat doivent reecrire la meme valeur, jamais s'additionner")

func _hors_zone_aucun_surcout_thermique(v) -> void:
	var colon: Dictionary = Banc.construire_colon(CONFIG_VLOK)
	var sources: Array = Banc.sources_temperature(CONFIG_VLOK)
	v.v(sources.size() == 2 and sources[0].has("position") and sources[0].has("rayon")
		and sources[0].has("temperature") and sources[0].has("force"),
		"sources_temperature doit rendre exactement la forme que temperature.gd attend")
	v.v(not sources[0].has("couleur"), "la couleur de rendu ne doit jamais entrer dans le calcul de temperature")
	# Point hors des deux rayons : temperature.gd rend l'ambiante seule, mais
	# l'ambiante du catalogue vlok EST le confort -- donc rien ne coute.
	var catalogue := { "defaut": { "ambiante": 100.0, "attenuation": { "exposant": 1.0 } } }
	var locale: float = Temperature.locale(Vector3(20.0, 25.0, 0.0), sources, catalogue)
	var d: Dictionary = Banc.poser_surcout_action(colon, locale, CONFIG_VLOK)
	v.v(is_equal_approx(locale, 100.0), "hors de toute zone, la temperature locale doit valoir l'ambiante seule")
	v.v(is_equal_approx(float(d.froid), 0.0) and is_equal_approx(float(d.chaud), 0.0),
		"HORS ZONE : les deux miroirs thermiques doivent valoir exactement 0.0")
	v.v(is_equal_approx(float(d.thermo), 0.0), "HORS ZONE : aucun surcout thermique, exactement 0.0")

func _manque_energie_monte_quand_la_reserve_descend(v) -> void:
	var colon: Dictionary = Banc.construire_colon(CONFIG_VLOK)
	var monde: Array = [colon]
	v.v(is_equal_approx(Banc.poser_manque_energie(colon, CONFIG_VLOK), 0.0),
		"reserve pleine : le manque doit valoir exactement 0.0")
	var precedent := 0.0
	for i in range(3):
		Banc.poser_surcout_action(colon, 100.0, CONFIG_VLOK)
		Depense.avancer(monde, 1.0)
		var manque: float = Banc.poser_manque_energie(colon, CONFIG_VLOK)
		v.v(manque > precedent, "MIROIR : manque_energie doit monter a chaque tick ou la reserve descend")
		v.v(is_equal_approx(manque, 20.0 - float(colon.proprietes.reserves.flux_vlok.reserve)),
			"le manque doit valoir EXACTEMENT capacite - reserve, jamais une grandeur accumulee a cote")
		precedent = manque
	v.v(is_equal_approx(float(colon.proprietes.creux_vlok), precedent),
		"le miroir doit etre pose sous le nom donne en DONNEE, jamais 'manque_energie' en dur")
	# Reserve vide : depense.gd borne a 0.0, donc le manque plafonne a la
	# capacite et ne devient jamais absurde.
	colon.proprietes.reserves.flux_vlok["reserve"] = 0.0
	v.v(is_equal_approx(Banc.poser_manque_energie(colon, CONFIG_VLOK), 20.0),
		"reserve vide : le manque doit valoir exactement la capacite")

func _les_quatre_etats_sont_poses_au_seuil_et_retires_en_dessous(v) -> void:
	var colon: Dictionary = Banc.construire_colon(CONFIG_VLOK)
	var monde: Array = [colon]

	# Faim : seuil 12 de manque sur une capacite 20 -> bascule sous 8 d'energie.
	colon.proprietes.reserves.flux_vlok["reserve"] = 9.0
	Banc.poser_manque_energie(colon, CONFIG_VLOK)
	SeuilEtat.avancer(monde, SEUILS_VLOK)
	v.v(not colon.proprietes.etats_actifs.has("vide_vlok"),
		"JUSTE AU-DESSUS du seuil de faim, l'etat ne doit pas etre pose (comparaison strictement au-dessus)")
	colon.proprietes.reserves.flux_vlok["reserve"] = 7.0
	Banc.poser_manque_energie(colon, CONFIG_VLOK)
	SeuilEtat.avancer(monde, SEUILS_VLOK)
	v.v(colon.proprietes.etats_actifs.has("vide_vlok"),
		"FAIM : sous le seuil d'energie, l'etat de faim doit etre pose par seuil_etat.gd sur le miroir")
	# REVERSIBILITE -- impossible a observer dans le banc reel (aucune
	# nourriture), prouvee ici : le miroir REDESCEND, contrairement a toutes les
	# grandeurs cumulees du depot.
	colon.proprietes.reserves.flux_vlok["reserve"] = 15.0
	Banc.poser_manque_energie(colon, CONFIG_VLOK)
	SeuilEtat.avancer(monde, SEUILS_VLOK)
	v.v(not colon.proprietes.etats_actifs.has("vide_vlok"),
		"REVERSIBILITE : reserve remontee, l'etat de faim doit etre RETIRE tout seul -- le miroir n'est pas une grandeur cumulee")

	# Froid : deux etages sur la MEME propriete continue.
	Banc.poser_surcout_action(colon, 97.0, CONFIG_VLOK)
	SeuilEtat.avancer(monde, SEUILS_VLOK)
	v.v(not colon.proprietes.etats_actifs.has("gele_vlok"),
		"3 degres de froid (seuil 4) ne doivent rien poser")
	Banc.poser_surcout_action(colon, 94.0, CONFIG_VLOK)
	SeuilEtat.avancer(monde, SEUILS_VLOK)
	v.v(colon.proprietes.etats_actifs.has("gele_vlok") and not colon.proprietes.etats_actifs.has("fige_vlok"),
		"PREMIER ETAGE DE FROID : au-dela du premier seuil et sous le second, seul l'etat leger doit etre actif")
	Banc.poser_surcout_action(colon, 88.0, CONFIG_VLOK)
	SeuilEtat.avancer(monde, SEUILS_VLOK)
	v.v(colon.proprietes.etats_actifs.has("gele_vlok") and colon.proprietes.etats_actifs.has("fige_vlok"),
		"SECOND ETAGE DE FROID : au-dela du second seuil, les DEUX etats doivent rester actifs (memoire par entree)")
	Banc.poser_surcout_action(colon, 100.0, CONFIG_VLOK)
	SeuilEtat.avancer(monde, SEUILS_VLOK)
	v.v(not colon.proprietes.etats_actifs.has("gele_vlok") and not colon.proprietes.etats_actifs.has("fige_vlok"),
		"REVERSIBILITE DU FROID : revenu au confort, le colon doit perdre les deux etats de froid")

	# Chaud : un seul etage, sur l'AUTRE miroir.
	Banc.poser_surcout_action(colon, 145.0, CONFIG_VLOK)
	SeuilEtat.avancer(monde, SEUILS_VLOK)
	v.v(not colon.proprietes.etats_actifs.has("cuit_vlok"),
		"5 degres au-dessus de seuil_chaud (seuil 6) ne doivent rien poser")
	Banc.poser_surcout_action(colon, 150.0, CONFIG_VLOK)
	SeuilEtat.avancer(monde, SEUILS_VLOK)
	v.v(colon.proprietes.etats_actifs.has("cuit_vlok"),
		"CHAUD : au-dela du seuil chaud, l'etat de chaleur doit etre pose")
	v.v(not colon.proprietes.etats_actifs.has("gele_vlok"),
		"un colon au chaud ne doit jamais porter en meme temps un etat de froid")

func _vitesse_effective_composee_puis_nulle_a_reserve_vide(v) -> void:
	var colon: Dictionary = Banc.construire_colon(CONFIG_VLOK)
	v.v(is_equal_approx(Banc.vitesse_effective(colon, CONFIG_VLOK, ETATS_VLOK), 10.0),
		"sans aucun etat, la vitesse effective doit valoir la vitesse de base")
	colon.proprietes.etats_actifs = ["vide_vlok"]
	v.v(is_equal_approx(Banc.vitesse_effective(colon, CONFIG_VLOK, ETATS_VLOK), 2.5),
		"un etat modulateur doit multiplier la vitesse de base")
	colon.proprietes.etats_actifs = ["vide_vlok", "fige_vlok"]
	v.v(is_equal_approx(Banc.vitesse_effective(colon, CONFIG_VLOK, ETATS_VLOK), 0.25),
		"deux etats modulateurs doivent se composer MULTIPLICATIVEMENT (0.25 x 0.1), aucun des deux ne connaissant l'autre")
	colon.proprietes.reserves.flux_vlok["reserve"] = 0.0
	v.v(is_equal_approx(Banc.vitesse_effective(colon, CONFIG_VLOK, ETATS_VLOK), 0.0),
		"ARRET FINAL : reserve vide, la vitesse effective doit valoir 0.0 -- gate de cablage, aucun etat ajoute pour ca")

func _changements_etats_et_projections(v) -> void:
	var changements: Dictionary = Banc.changements_etats(["a_vlok", "b_vlok"], ["b_vlok", "c_vlok"])
	v.v(changements.gagnes == ["c_vlok"] and changements.perdus == ["a_vlok"],
		"changements_etats doit rendre les etats gagnes ET perdus, jamais ceux qui n'ont pas bouge")
	v.v(Banc.lignes_changement(1.0, changements).size() == 2, "une ligne de console par changement, ni plus ni moins")
	v.v(Banc.changements_etats(["a_vlok"], ["a_vlok"]).gagnes.is_empty(),
		"sans changement, aucune ligne ne doit etre tracee (sinon la console cracherait a chaque frame)")

	var colon: Dictionary = Banc.construire_colon(CONFIG_VLOK)
	colon.proprietes.reserves.flux_vlok["surcout_action"] = 0.0
	# cout_base 2.0, capacite 20, seuil de faim 12 -> famine a 8 d'energie,
	# donc 12 d'energie a bruler a 2.0/s = 6 s.
	v.v(is_equal_approx(Banc.secondes_avant_famine(colon, CONFIG_VLOK, 12.0), 6.0),
		"la projection avant famine doit valoir (reserve - (capacite - seuil)) / taux courant")
	v.v(is_equal_approx(Banc.secondes_avant_epuisement(colon, CONFIG_VLOK), 10.0),
		"la projection avant arret doit valoir reserve / taux courant")
	colon.proprietes.reserves.flux_vlok["reserve"] = 5.0
	v.v(is_equal_approx(Banc.secondes_avant_famine(colon, CONFIG_VLOK, 12.0), 0.0),
		"famine deja la : la projection doit valoir 0.0, jamais un nombre negatif")
	colon.proprietes.reserves.flux_vlok["cout_base"] = 0.0
	v.v(Banc.secondes_avant_epuisement(colon, CONFIG_VLOK) == INF,
		"rien ne se depense : la projection doit valoir INF, jamais une division par zero")
	v.v(Banc.texte_duree(INF).find("jamais") >= 0, "INF ne doit jamais s'afficher comme un nombre")

func _cible_aleatoire_reste_dans_le_terrain_et_a_plat(v) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(CONFIG_VLOK.graine)
	var dans_le_terrain := true
	var a_plat := true
	var premiere := Vector3.ZERO
	for i in range(50):
		var cible: Vector3 = Banc.cible_aleatoire(rng, CONFIG_VLOK)
		if i == 0:
			premiere = cible
		if cible.x < 0.0 or cible.x > 50.0 or cible.y < 0.0 or cible.y > 30.0:
			dans_le_terrain = false
		if cible.z != 0.0:
			a_plat = false
	v.v(dans_le_terrain, "toute cible tiree doit rester dans le terrain")
	v.v(a_plat, "VERTICALITE : z doit rester 0.0 sur toute cible tiree")
	# Aucun hasard non seede : meme graine, meme premier tirage.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = int(CONFIG_VLOK.graine)
	v.v(Banc.cible_aleatoire(rng2, CONFIG_VLOK) == premiere,
		"HASARD SEEDE : deux RNG de meme graine doivent rendre exactement le meme premier tirage")

# ---- Chemin reel : les fichiers du disque ----

# ACCORD ENTRE LE BANC ET LES CATALOGUES PARTAGES. Si un nom de miroir de
# data/banc_faim_thermo.json cessait de correspondre au 'propriete_continue'
# d'une entree de data/seuils_etat.json, le banc ecrirait sagement un nombre
# que plus personne ne comparerait : aucun etat ne se poserait plus jamais, et
# AUCUNE alarme ne le dirait (seuil_etat.gd traite une propriete absente comme
# un chemin mort legitime). Ce cas ferme ce trou.
func _chemin_reel_les_noms_de_miroirs_sont_ceux_du_catalogue_partage(v) -> void:
	var config: Dictionary = _charger("res://data/banc_faim_thermo.json")
	var seuils: Dictionary = _charger("res://data/seuils_etat.json")
	var etats: Dictionary = _charger("res://data/etats.json")
	v.v(not config.is_empty() and not seuils.is_empty() and not etats.is_empty(),
		"les trois fichiers du chemin reel doivent charger")

	var attendus := {
		"faim": [String(config.nom_manque_energie), "affame"],
		"frisson": [String(config.nom_froid_ressenti), "frisson"],
		"hypothermie": [String(config.nom_froid_ressenti), "hypothermie"],
		"hyperthermie": [String(config.nom_chaud_ressenti), "hyperthermie"],
	}
	for ref in attendus:
		v.v(seuils.has(ref), "data/seuils_etat.json doit porter l'entree '%s'" % ref)
		if not seuils.has(ref):
			continue
		v.v(String(seuils[ref].propriete_continue) == String(attendus[ref][0]),
			"l'entree '%s' doit comparer le miroir que le banc ecrit reellement (%s)" % [ref, attendus[ref][0]])
		var nom_etat := String(seuils[ref].etat)
		v.v(nom_etat == String(attendus[ref][1]), "l'entree '%s' doit poser l'etat '%s'" % [ref, attendus[ref][1]])
		v.v(etats.has(nom_etat), "l'etat '%s' doit exister dans data/etats.json" % nom_etat)
		if etats.has(nom_etat):
			v.v(not etats[nom_etat].has("duree"),
				"l'etat '%s' ne doit porter AUCUNE duree : il est retire par le franchissement descendant, jamais par le temps" % nom_etat)
			var vise_vitesse := false
			for effet in etats[nom_etat].get("effets", []):
				if String(effet.get("propriete", "")) == String(config.nom_vitesse):
					vise_vitesse = true
			v.v(vise_vitesse, "l'etat '%s' doit moduler la vitesse -- sinon rien ne serait observable" % nom_etat)

	v.v(float(seuils.hypothermie.seuil) > float(seuils.frisson.seuil),
		"ESCALIER : le seuil d'hypothermie doit rester strictement au-dessus de celui du frisson")
	v.v(float(config.seuil_chaud) >= float(config.temp_cible),
		"seuil_chaud doit rester >= temp_cible, sinon les deux miroirs thermiques pourraient etre non nuls ensemble")

# CALIBRATION REELLE : ce que le colon ressent effectivement aux trois endroits
# du terrain. Sans ce cas, un gradient mal regle laisserait un banc qui ne
# montre rien tout en restant VERT (le defaut exact rencontre par banc_maladie,
# voir docs/ETAT.md).
func _chemin_reel_calibration_des_deux_zones(v) -> void:
	var config: Dictionary = _charger("res://data/banc_faim_thermo.json")
	var catalogue: Dictionary = _charger("res://data/temperature.json")
	var sources: Array = Banc.sources_temperature(config)
	v.v(sources.size() == 2, "le terrain reel doit porter exactement deux zones")

	var froide: Vector3 = sources[0].position
	var chaude: Vector3 = sources[1].position
	v.v(froide.distance_to(chaude) > float(sources[0].rayon) + float(sources[1].rayon),
		"les deux zones ne doivent JAMAIS se chevaucher -- temperature.gd superpose additivement, elles s'annuleraient en partie")

	var colon: Dictionary = Banc.construire_colon(config)
	var au_depart: Dictionary = Banc.poser_surcout_action(colon, Temperature.locale(colon.position, sources, catalogue), config)
	v.v(is_equal_approx(float(au_depart.froid), 0.0) and is_equal_approx(float(au_depart.chaud), 0.0),
		"CALIBRATION : au point de depart (zone neutre), les deux miroirs doivent valoir 0.0 -- aucun surcout thermique")
	v.v(is_equal_approx(float(au_depart.thermo), 0.0), "CALIBRATION : aucun surcout thermique en zone neutre")

	var au_froid: Dictionary = Banc.poser_surcout_action(colon, Temperature.locale(froide, sources, catalogue), config)
	v.v(float(au_froid.froid) > 15.0,
		"CALIBRATION : au coeur de la zone froide, le froid ressenti doit depasser le seuil d'hypothermie")
	v.v(float(au_froid.thermo) > 0.0, "CALIBRATION : le froid doit reellement couter de l'energie")

	# La couronne de frisson SEUL : c'est elle, et elle seule, qui rend
	# l'escalier observable a l'ecran.
	var mi_chemin: Vector3 = froide + Vector3(float(sources[0].rayon) * 0.6, 0.0, 0.0)
	var couronne: Dictionary = Banc.poser_surcout_action(colon, Temperature.locale(mi_chemin, sources, catalogue), config)
	v.v(float(couronne.froid) > 5.0 and float(couronne.froid) < 15.0,
		"CALIBRATION : il doit exister une couronne ou seul le frisson est atteint, sinon l'escalier froid n'est jamais visible")

	var au_chaud: Dictionary = Banc.poser_surcout_action(colon, Temperature.locale(chaude, sources, catalogue), config)
	v.v(float(au_chaud.chaud) > 5.0,
		"CALIBRATION : au coeur de la zone chaude, le chaud ressenti doit depasser le seuil d'hyperthermie")
	v.v(is_equal_approx(float(au_chaud.froid), 0.0), "au coeur du chaud, le miroir de froid doit valoir 0.0")

# Les QUATRE etats reels, poses par les entrees reelles du catalogue partage
# sur le colon reel -- y compris la preuve qu'aucun etat PARASITE du catalogue
# (liquide/gaz/chaud/fracture...) ne peut se poser sur lui.
func _chemin_reel_les_quatre_etats_sont_atteignables(v) -> void:
	var config: Dictionary = _charger("res://data/banc_faim_thermo.json")
	var seuils: Dictionary = _charger("res://data/seuils_etat.json")
	var etats: Dictionary = _charger("res://data/etats.json")
	var catalogue_temp: Dictionary = _charger("res://data/temperature.json")
	var sources: Array = Banc.sources_temperature(config)

	var colon: Dictionary = Banc.construire_colon(config)
	var monde: Array = [colon]

	# Zone neutre, reserve pleine : AUCUN etat, et surtout aucun parasite.
	Banc.poser_surcout_action(colon, Temperature.locale(colon.position, sources, catalogue_temp), config)
	Banc.poser_manque_energie(colon, config)
	SeuilEtat.avancer(monde, seuils)
	v.v(colon.proprietes.etats_actifs.is_empty(),
		"AUCUN PARASITE : au repos en zone neutre, le colon ne doit porter aucun etat -- les entrees thermiques " +
		"du catalogue partage (point_fusion/chaud/...) sont des chemins morts pour lui, il ne porte pas 'temperature'")

	# Faim : seuil 60 sur une capacite 100 -> bascule sous 40 d'energie.
	var seuil: float = Banc.seuil_faim(seuils, config)
	colon.proprietes.reserves[String(config.nom_reserve_energie)]["reserve"] = float(config.capacite_energie) - seuil - 1.0
	Banc.poser_manque_energie(colon, config)
	SeuilEtat.avancer(monde, seuils)
	v.v(colon.proprietes.etats_actifs.has("affame"), "CHEMIN REEL : 'affame' doit etre pose sous le seuil de faim")
	v.v(Banc.vitesse_effective(colon, config, etats) < float(config.vitesse_base),
		"CHEMIN REEL : un colon affame doit reellement aller moins vite")

	# Froid : les deux etages, sur la position reelle de la zone froide.
	Banc.poser_surcout_action(colon, Temperature.locale(sources[0].position, sources, catalogue_temp), config)
	SeuilEtat.avancer(monde, seuils)
	v.v(colon.proprietes.etats_actifs.has("frisson") and colon.proprietes.etats_actifs.has("hypothermie"),
		"CHEMIN REEL : au coeur de la zone froide, 'frisson' ET 'hypothermie' doivent etre actifs ensemble")
	var vitesse_gelee: float = Banc.vitesse_effective(colon, config, etats)
	v.v(vitesse_gelee < float(config.vitesse_base) * 0.5 * 0.8 * 0.3 + 0.001
		and vitesse_gelee > float(config.vitesse_base) * 0.5 * 0.8 * 0.3 - 0.001,
		"CHEMIN REEL : affame + frisson + hypothermie doivent composer MULTIPLICATIVEMENT (0.5 x 0.8 x 0.3)")

	# Chaud : l'autre bout du terrain. En passant, la reversibilite du froid.
	Banc.poser_surcout_action(colon, Temperature.locale(sources[1].position, sources, catalogue_temp), config)
	SeuilEtat.avancer(monde, seuils)
	v.v(colon.proprietes.etats_actifs.has("hyperthermie"),
		"CHEMIN REEL : au coeur de la zone chaude, 'hyperthermie' doit etre pose")
	v.v(not colon.proprietes.etats_actifs.has("frisson") and not colon.proprietes.etats_actifs.has("hypothermie"),
		"CHEMIN REEL, REVERSIBILITE : passe du froid au chaud, le colon doit avoir PERDU ses deux etats de froid")
	v.v(colon.proprietes.etats_actifs.has("affame"),
		"la faim ne doit pas disparaitre parce que la temperature a change -- les entrees sont independantes")

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
