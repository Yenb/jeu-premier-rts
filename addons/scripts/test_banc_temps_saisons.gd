extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_temps_saisons.gd
#
# Verrouille le cablage de banc_temps_saisons.gd. Les catalogues REELS sont
# lus sur disque, comme le fait le banc lui-meme : data/banc_temps_saisons.json,
# data/etats.json, data/seuils_etat.json, data/seuils_combustible.json,
# data/croyances.json, data/menaces.json, data/transformations.json,
# data/types.json, data/materiaux.json. Aucune fixture locale ne remplace une
# calibration -- une derive entre le disque et ce fichier doit rougir ici.
#
# DEUX FAMILLES DE CAS, a ne pas confondre :
# - les cas de mecanique posent leurs propres plantes, colons et chroniques,
#   aux distances et aux saisons qu'ils veulent : ils isolent UN maillon ;
# - le dernier cas rejoue la configuration du disque EN ENTIER a travers
#   avancer(), sur assez de temps pour traverser plusieurs saisons. Sans lui,
#   tout le reste pourrait rester vert alors que la scene lancee ne montrerait
#   rien.
# Aucun cas de la premiere famille ne remplace le second.

const Banc = preload("res://scripts/banc_temps_saisons.gd")
const Flux = preload("res://scripts/flux.gd")
const Depense = preload("res://scripts/depense.gd")
const Charge = preload("res://scripts/charge.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Somme = preload("res://scripts/somme.gd")
const Croyance = preload("res://scripts/croyance.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA := 0.1

var verif := Verif.new()

var _config: Dictionary
var _catalogues: Dictionary

func _init() -> void:
	_config = _charger("res://data/banc_temps_saisons.json")
	var types_partages := _charger("res://data/types.json")
	_catalogues = {
		"canaux": _charger("res://data/canaux.json"),
		"croyances": _charger("res://data/croyances.json"),
		"lumiere": _charger("res://data/lumiere.json"),
		"materiaux": _charger("res://data/materiaux.json"),
		"menaces": _charger("res://data/menaces.json"),
		"seuils_etat": _charger("res://data/seuils_etat.json"),
		"seuils_reserve": _charger("res://data/seuils_combustible.json"),
		"transformations": _charger("res://data/transformations.json").get("transformations", {}),
		"types": Banc._table_de_fabrication(types_partages, _config),
	}

	_flux_rapide_monte_a_chaque_tick()
	_flux_lent_ne_bouge_qu_au_changement_de_saison()
	_les_deux_debits_s_additionnent_sur_la_meme_reserve()
	_saison_froide_sautee_ne_declenche_pas_le_flux_lent()
	_saison_volcanique_pose_des_conditions_supplementaires()
	_la_perturbation_vient_d_un_accumulateur_et_d_un_seuil()
	_la_contagion_accumule_sur_les_voisins()
	_la_contagion_ne_touche_pas_un_colon_hors_rayon()
	_la_chronique_porte_les_croyances_de_l_auteur()
	_le_lecteur_acquiert_les_croyances_de_la_chronique()
	_la_fierte_monte_le_moral()
	_la_chronique_brulee_perd_ses_proprietes()
	_les_croyances_du_lecteur_survivent_a_la_destruction()
	_un_fantome_est_filtre_avant_tout_mecanisme()
	_le_total_des_reserves_est_constant_hors_transfert()
	_la_configuration_du_disque_traverse_plusieurs_saisons()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_temps_saisons.gd -- deux debits sur une reserve (flux.gd), " +
		"cadence de perturbation par accumulateur et seuil (seuil_etat.gd), " +
		"contagion d'humeur a portee (charge.gd) et histoire ecrite qui se lit, " +
		"se degrade et brule (croyance.gd, propagation.gd, extinction.gd, " +
		"depense.gd, produit.gd) tiennent ensemble sans qu'aucun mecanisme du " +
		"coeur ne soit touche")
	quit(0)

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _nom_reserve() -> String:
	return String(_config.nom_reserve_vegetale)

func _total(plantes: Array) -> float:
	return Somme.reserves(plantes, _nom_reserve())

# Prepare plantes + sources pour une saison donnee, miroirs et conditions
# deja resolus -- le point de depart commun de tous les cas de flux.
func _scene_vegetale(saison: String, sans_hiver: bool, volcanique: bool) -> Dictionary:
	var plantes := Banc.construire_plantes(_config)
	var sources := Banc.construire_sources(_config)
	var calendrier := Banc.construire_calendrier(_config)
	calendrier.proprietes["annee_sans_hiver"] = 1.0 if sans_hiver else 0.0
	calendrier.proprietes["annee_volcanique"] = 1.0 if volcanique else 0.0
	Banc.poser_miroirs_saison(plantes, saison, calendrier, _config)
	Banc.evaluer_saisons(plantes, _config)
	return {"plantes": plantes, "sources": sources, "calendrier": calendrier}

func _flux_rapide_monte_a_chaque_tick() -> void:
	var scene := _scene_vegetale(String(_config.saisons_de_pousse[0]), false, false)
	var plantes: Array = scene.plantes
	var monde: Array = plantes + scene.sources
	for plante in plantes:
		verif.v(plante.proprietes.has(String(_config.propriete_pousse)),
			"en saison de pousse, conditions.gd doit poser la propriete receptrice du debit rapide")

	var avant := _total(plantes)
	Flux.avancer(monde, Banc.table_flux_rapide(_config), DELTA)
	var apres_un := _total(plantes)
	Flux.avancer(monde, Banc.table_flux_rapide(_config), DELTA)
	var apres_deux := _total(plantes)

	var attendu: float = float(_config.sources_flux[0].taux_flux) * DELTA * float(plantes.size())
	verif.v(is_equal_approx(apres_un - avant, attendu),
		"le debit rapide doit monter d'exactement taux x delta x nombre de plantes a chaque tick")
	verif.v(is_equal_approx(apres_deux - apres_un, attendu),
		"le deuxieme tick doit monter d'autant que le premier -- un debit, jamais un evenement")

func _flux_lent_ne_bouge_qu_au_changement_de_saison() -> void:
	var scene := _scene_vegetale(String(_config.saison_froide), false, false)
	var plantes: Array = scene.plantes
	var monde: Array = plantes + scene.sources
	for plante in plantes:
		verif.v(plante.proprietes.has(String(_config.propriete_dormance)),
			"en saison froide, conditions.gd doit poser la propriete receptrice du debit lent")
		verif.v(not plante.proprietes.has(String(_config.propriete_pousse)),
			"en saison froide, la propriete receptrice du debit rapide doit avoir ete RETIREE")

	var avant := _total(plantes)
	Flux.avancer(monde, Banc.table_flux_rapide(_config), DELTA)
	verif.v(is_equal_approx(_total(plantes), avant),
		"le debit rapide ne transfere rien quand sa propriete receptrice est absente")

	Flux.avancer(monde, Banc.table_flux_lent(_config), 1.0)
	var attendu: float = float(_config.sources_flux[1].taux_flux) * float(plantes.size())
	verif.v(is_equal_approx(_total(plantes) - avant, attendu),
		"le debit lent doit retirer exactement son taux x nombre de plantes, en UN pas a delta 1.0")

	var apres_le_pas := _total(plantes)
	for i in 40:
		Flux.avancer(monde, Banc.table_flux_rapide(_config), DELTA)
	verif.v(is_equal_approx(_total(plantes), apres_le_pas),
		"entre deux changements de saison, quarante ticks ne doivent rien changer de plus")

func _les_deux_debits_s_additionnent_sur_la_meme_reserve() -> void:
	var plantes := Banc.construire_plantes(_config)
	var sources := Banc.construire_sources(_config)
	var monde: Array = plantes + sources
	# Les deux proprietes receptrices posees a la fois sur la meme plante --
	# etat que le calendrier ne produit jamais, pose ici expres : il isole le
	# fait que flux.gd ADDITIONNE au lieu d'ecrire.
	for plante in plantes:
		plante.proprietes[String(_config.propriete_pousse)] = true
		plante.proprietes[String(_config.propriete_dormance)] = true

	var avant := _total(plantes)
	Flux.avancer(monde, Banc.table_flux_rapide(_config), DELTA)
	Flux.avancer(monde, Banc.table_flux_lent(_config), 1.0)
	var attendu: float = (float(_config.sources_flux[0].taux_flux) * DELTA
		+ float(_config.sources_flux[1].taux_flux)) * float(plantes.size())
	verif.v(is_equal_approx(_total(plantes) - avant, attendu),
		"deux lignes de table visant la meme reserve doivent se composer, jamais s'ecraser")

func _saison_froide_sautee_ne_declenche_pas_le_flux_lent() -> void:
	var scene := _scene_vegetale(String(_config.saison_froide), true, false)
	var plantes: Array = scene.plantes
	var monde: Array = plantes + scene.sources
	for plante in plantes:
		verif.v(is_equal_approx(float(plante.proprietes[String(_config.miroir_saison_froide)]), 0.0),
			"une annee sautee n'ecrit pas le miroir de saison froide, meme quand l'horloge la nomme")
		verif.v(not plante.proprietes.has(String(_config.propriete_dormance)),
			"sans miroir, conditions.gd ne pose pas la propriete receptrice du debit lent")

	var avant := _total(plantes)
	Flux.avancer(monde, Banc.table_flux_lent(_config), 1.0)
	verif.v(is_equal_approx(_total(plantes), avant),
		"la ligne lente ne trouve aucun receveur : les reserves ne descendent pas de l'annee")

func _saison_volcanique_pose_des_conditions_supplementaires() -> void:
	var ordinaire := _scene_vegetale(String(_config.saison_froide), false, false)
	for plante in ordinaire.plantes:
		verif.v(not plante.proprietes.has(String(_config.propriete_gel)),
			"une saison froide ordinaire ne pose pas la cle de gel")
		verif.v(not plante.proprietes.has(String(_config.propriete_recolte_perdue)),
			"une saison froide ordinaire ne pose pas la perte de recolte")

	var volcanique := _scene_vegetale(String(_config.saison_froide), false, true)
	var plantes: Array = volcanique.plantes
	for plante in plantes:
		verif.v(plante.proprietes.has(String(_config.propriete_dormance)),
			"l'entree a deux conditions pose aussi la dormance -- une entree VRAIE gagne")
		verif.v(plante.proprietes.has(String(_config.propriete_gel)),
			"la saison volcanique pose la cle de gel en plus")
		verif.v(plante.proprietes.has(String(_config.propriete_recolte_perdue)),
			"la saison volcanique pose la perte de recolte en plus")

	Banc.poser_cout_gel(plantes, _config)
	var canal: Dictionary = plantes[0].proprietes.reserves[_nom_reserve()]
	verif.v(is_equal_approx(float(canal.cout_base), float(_config.cout_gel)),
		"la cle de gel doit ouvrir le cout_base de la reserve, jamais un effet declare en catalogue")
	var avant := _total(plantes)
	Depense.avancer(plantes, DELTA, {})
	verif.v(_total(plantes) < avant, "depense.gd doit alors ponctionner la reserve chaque tick")

	# La cle se retire d'elle-meme quand la saison volcanique passe.
	var calendrier: Dictionary = volcanique.calendrier
	calendrier.proprietes["annee_volcanique"] = 0.0
	Banc.poser_miroirs_saison(plantes, String(_config.saison_froide), calendrier, _config)
	Banc.evaluer_saisons(plantes, _config)
	Banc.poser_cout_gel(plantes, _config)
	verif.v(not plantes[0].proprietes.has(String(_config.propriete_gel)),
		"conditions.gd rejoue avec retrait doit reprendre la cle de gel")
	verif.v(is_equal_approx(float(canal.cout_base), 0.0),
		"le cout_base doit se refermer avec elle -- unique ecrivain, jamais deux")

# Le fait a prouver : la perturbation est REJOUABLE. Deux calendriers
# construits separement et pousses par la MEME suite de saisons rendent la
# MEME suite d'annees perturbees, et cette suite est celle que le compte et le
# seuil dictent -- aucun tirage n'intervient nulle part.
func _la_perturbation_vient_d_un_accumulateur_et_d_un_seuil() -> void:
	var saisons: Array = _config.cycle.saisons
	var suite_a := _suite_de_perturbations(6, saisons)
	var suite_b := _suite_de_perturbations(6, saisons)
	verif.v(suite_a == suite_b,
		"deux deroulements identiques doivent rendre exactement la meme suite d'annees perturbees")

	var seuil: float = float(_config.calendrier.seuil_saut_hiver)
	var depart: float = float(_config.calendrier.compte_saut_initial)
	var premier_saut: int = int(seuil - depart) + 1
	verif.v(suite_a.size() >= premier_saut and String(suite_a[premier_saut - 1]) == "saut",
		"le premier saut doit tomber a l'annee que le compte de depart et le seuil dictent")
	verif.v(premier_saut >= 2 and String(suite_a[premier_saut - 2]) == "-",
		"l'annee precedente doit etre reguliere -- une cadence, jamais un declenchement au premier tour")

	var calendrier := Banc.construire_calendrier(_config)
	Banc.forcer_saut_saison_froide(calendrier, _config)
	verif.v(float(calendrier.proprietes.annee_sans_hiver) > 0.0,
		"le forcage doit poser l'annee sautee sans attendre l'echeance")
	verif.v(is_equal_approx(float(calendrier.proprietes.annees_depuis_saut), 0.0),
		"le forcage doit remettre le compte a zero -- la cadence repart de la")
	Banc.forcer_saison_volcanique(calendrier, _config)
	verif.v(float(calendrier.proprietes.annee_volcanique) > 0.0
		and is_equal_approx(float(calendrier.proprietes.annee_sans_hiver), 0.0),
		"les deux forcages s'excluent : une annee sans saison froide n'a pas de froid a durcir")

func _suite_de_perturbations(annees: int, saisons: Array) -> Array:
	var calendrier := Banc.construire_calendrier(_config)
	var suite: Array = []
	Banc.avancer_calendrier(calendrier, String(saisons[0]), _config)
	for annee in range(annees):
		for i in range(1, saisons.size()):
			Banc.avancer_calendrier(calendrier, String(saisons[i]), _config)
		var bilan := Banc.avancer_calendrier(calendrier, String(saisons[0]), _config)
		if bool(bilan.sans_hiver):
			suite.append("saut")
		elif bool(bilan.volcanique):
			suite.append("volcan")
		else:
			suite.append("-")
	return suite

# Prepare les colons avec l'abondance reelle des plantes neuves, le moral
# pose, et les etats resolus une premiere fois.
func _scene_sociale() -> Array:
	var colons := Banc.construire_colons(_config)
	var plantes := Banc.construire_plantes(_config)
	Banc.poser_abondance(colons, plantes, _config)
	Banc.poser_fierte(colons, [], _config)
	for colon in colons:
		Banc.poser_moral(colon, _config)
	SeuilEtat.avancer(colons, _catalogues.seuils_etat)
	return colons

func _la_contagion_accumule_sur_les_voisins() -> void:
	var colons := _scene_sociale()
	for colon in colons:
		verif.v(not colon.proprietes.etats_actifs.has(String(_config.etat_panique)),
			"au repos, aucun colon ne doit porter l'etat de panique")

	Banc.basculer_serenite(colons, _config)
	for colon in colons:
		Banc.poser_moral(colon, _config)
	SeuilEtat.avancer(colons, _catalogues.seuils_etat)

	var choque := Banc.chose_par_id(colons, String(_config.colon_choque))
	verif.v(choque.proprietes.etats_actifs.has(String(_config.etat_panique)),
		"serenite coupee, le colon designe doit franchir le seuil de panique")
	var causes := Banc.causes_de_paniques(colons, _config)
	verif.v(causes.size() == 1, "une cause, et une seule, doit etre construite a la position du paniquant")

	for i in 30:
		Charge.avancer(colons, Banc.causes_de_paniques(colons, _config), DELTA)
		for colon in colons:
			Banc.refleter_contagion(colon, _config)
		SeuilEtat.avancer(colons, _catalogues.seuils_etat)
		for colon in colons:
			Banc.poser_moral(colon, _config)

	var voisin := Banc.chose_par_id(colons, "chroniqueur")
	verif.v(Banc.charge_contagion(voisin, _config) > 0.0,
		"un voisin dans le rayon doit voir sa charge de contagion monter")
	verif.v(voisin.proprietes.etats_actifs.has(String(_config.etat_moral_bas)),
		"au franchissement, le miroir plat doit faire poser l'etat de moral bas")
	verif.v(not voisin.proprietes.etats_actifs.has(String(_config.etat_panique)),
		"la contagion abaisse le moral du voisin sans le faire paniquer a son tour")

	# Reversibilite : la serenite rendue, la charge redescend et l'etat part.
	Banc.basculer_serenite(colons, _config)
	for i in 60:
		for colon in colons:
			Banc.poser_moral(colon, _config)
		SeuilEtat.avancer(colons, _catalogues.seuils_etat)
		Charge.avancer(colons, Banc.causes_de_paniques(colons, _config), DELTA)
		for colon in colons:
			Banc.refleter_contagion(colon, _config)
	SeuilEtat.avancer(colons, _catalogues.seuils_etat)
	verif.v(not voisin.proprietes.etats_actifs.has(String(_config.etat_moral_bas)),
		"la serenite rendue, la charge retombe et l'etat de moral bas se retire seul")

func _la_contagion_ne_touche_pas_un_colon_hors_rayon() -> void:
	var colons := _scene_sociale()
	Banc.basculer_serenite(colons, _config)
	for colon in colons:
		Banc.poser_moral(colon, _config)
	SeuilEtat.avancer(colons, _catalogues.seuils_etat)
	for i in 40:
		Charge.avancer(colons, Banc.causes_de_paniques(colons, _config), DELTA)
		for colon in colons:
			Banc.refleter_contagion(colon, _config)
		SeuilEtat.avancer(colons, _catalogues.seuils_etat)

	var isole := Banc.chose_par_id(colons, "colon_isole")
	verif.v(is_equal_approx(Banc.charge_contagion(isole, _config), 0.0),
		"un colon hors du rayon du canal ne recoit aucune charge")
	verif.v(not isole.proprietes.etats_actifs.has(String(_config.etat_moral_bas)),
		"et ne prend donc jamais l'etat de moral bas")

# Fabrique un auteur qui a REELLEMENT observe -- jamais un registre pose a la
# main : une croyance nait de la perception vecue.
func _auteur_ayant_observe() -> Dictionary:
	var colons := Banc.construire_colons(_config)
	var auteur := Banc.auteur_de(colons)
	var plantes := Banc.construire_plantes(_config)
	var perceptions: Array = []
	for plante in plantes:
		perceptions.append({"chose": plante})
	Croyance.observer(auteur, perceptions, _catalogues.croyances)
	return auteur

func _chronique_de(auteur: Dictionary) -> Dictionary:
	var pos: Array = _config.chronique.positions[0]
	return Banc.fabriquer_chronique(auteur, "chronique_test", Vector3(pos[0], pos[1], pos[2]),
		_config, _catalogues.types, _catalogues.materiaux)

func _la_chronique_porte_les_croyances_de_l_auteur() -> void:
	var auteur := _auteur_ayant_observe()
	verif.v(not auteur.proprietes.croyances.is_empty(),
		"l'auteur doit avoir forme au moins une croyance en observant le monde")

	var chronique := _chronique_de(auteur)
	verif.v(not chronique.is_empty(), "objet.gd doit accepter de fabriquer la chronique")
	var contenu: Dictionary = chronique.proprietes.contenu_croyance
	verif.v(contenu.size() == auteur.proprietes.croyances.size(),
		"la chronique doit porter autant de choses crues que son auteur au moment de l'ecriture")
	verif.v(float(chronique.proprietes.fidelite) == float(_config.chronique.fidelite),
		"la chronique doit porter la fidelite declaree en donnee")
	verif.v(Banc.integrite(chronique, _config) == float(_config.chronique.integrite),
		"sa reserve d'integrite doit demarrer pleine")

	# LA COPIE EST PROFONDE : ce que l'auteur apprend ensuite n'entre plus.
	auteur.proprietes.croyances["appris_plus_tard"] = {"dangereux": {"valeur": true, "certitude": 1.0}}
	verif.v(not chronique.proprietes.contenu_croyance.has("appris_plus_tard"),
		"le registre fige ne doit pas suivre ce que l'auteur apprend apres l'ecriture")

func _le_lecteur_acquiert_les_croyances_de_la_chronique() -> void:
	var auteur := _auteur_ayant_observe()
	var chronique := _chronique_de(auteur)
	var lecteur: Dictionary = Banc.construire_colons(_config)[1]
	lecteur.position = chronique.position
	verif.v(lecteur.proprietes.croyances.is_empty(),
		"un colon qui n'observe pas ne sait rien de lui-meme -- c'est ce que la lecture doit changer")

	var versees := Banc.lire_si_cadence(lecteur, [chronique], _config, _catalogues.croyances, 0.0)
	verif.v(not versees.is_empty(), "la lecture doit verser au moins une croyance")
	verif.v(lecteur.proprietes.croyances.size() == chronique.proprietes.contenu_croyance.size(),
		"le lecteur doit recevoir tout le registre fige")
	verif.v(lecteur.proprietes.chroniques_lues.has(String(chronique.id)),
		"la chronique lue doit etre inscrite une fois sur le lecteur")

	var chose_id: String = String(chronique.proprietes.contenu_croyance.keys()[0])
	var propriete: String = String(chronique.proprietes.contenu_croyance[chose_id].keys()[0])
	var certitude_lecteur: float = float(lecteur.proprietes.croyances[chose_id][propriete].certitude)
	var attendue: float = float(_catalogues.croyances.gain_par_echec) * float(_config.chronique.fidelite)
	verif.v(is_equal_approx(certitude_lecteur, attendue),
		"la fidelite degrade la CERTITUDE du lecteur, jamais la valeur transmise")
	verif.v(lecteur.proprietes.croyances[chose_id][propriete].valeur
		== chronique.proprietes.contenu_croyance[chose_id][propriete].valeur,
		"la valeur, elle, traverse telle quelle")

	# L'auteur ne se relit pas.
	auteur.position = chronique.position
	verif.v(Banc.lire_si_cadence(auteur, [chronique], _config, _catalogues.croyances, 0.0).is_empty(),
		"l'auteur ne doit jamais relire sa propre chronique")

	# Hors de portee, rien ne se lit.
	var loin: Dictionary = Banc.construire_colons(_config)[2]
	loin.position = chronique.position + Vector3(float(_config.portee_lecture) * 2.0, 0.0, 0.0)
	verif.v(Banc.lire_si_cadence(loin, [chronique], _config, _catalogues.croyances, 0.0).is_empty(),
		"un colon hors de portee de lecture ne recoit rien")

func _la_fierte_monte_le_moral() -> void:
	var auteur := _auteur_ayant_observe()
	var chronique := _chronique_de(auteur)
	var colons := Banc.construire_colons(_config)
	var plantes := Banc.construire_plantes(_config)
	Banc.poser_abondance(colons, plantes, _config)

	var lecteur: Dictionary = colons[1]
	lecteur.position = chronique.position
	Banc.poser_fierte(colons, [chronique], _config)
	var sans_lecture := Banc.poser_moral(lecteur, _config)
	verif.v(is_equal_approx(float(lecteur.proprietes[String(_config.source_fierte)]), 0.0),
		"tant que rien n'a ete lu, la part lue vaut zero, donc la fierte aussi")

	Banc.lire_si_cadence(lecteur, [chronique], _config, _catalogues.croyances, 0.0)
	Banc.poser_fierte(colons, [chronique], _config)
	var avec_lecture := Banc.poser_moral(lecteur, _config)
	verif.v(float(lecteur.proprietes[String(_config.source_fierte)]) > 0.0,
		"une chronique lue et lisible doit produire une fierte non nulle")
	verif.v(float(avec_lecture.moral) > float(sans_lecture.moral),
		"la fierte est un terme de plus dans la somme ponderee : le moral monte")
	verif.v(float(avec_lecture.manque) < float(sans_lecture.manque),
		"et son miroir inverse descend dans le MEME geste")

	# Ce qui n'est plus lisible ne rend plus fier.
	chronique.proprietes[String(_config.chronique.propriete_illisible)] = true
	Banc.poser_fierte(colons, [chronique], _config)
	verif.v(is_equal_approx(float(lecteur.proprietes[String(_config.source_fierte)]), 0.0),
		"la part conservee tombe a zero quand plus rien n'est lisible, la fierte avec elle")

func _la_chronique_brulee_perd_ses_proprietes() -> void:
	var auteur := _auteur_ayant_observe()
	var chronique := _chronique_de(auteur)
	chronique.proprietes[String(_config.propriete_menace)] = true
	Banc.poser_cout_chronique([chronique], _config)
	var canal: Dictionary = chronique.proprietes.reserves[String(_config.nom_reserve_integrite)]
	verif.v(is_equal_approx(float(canal.cout_base), float(_config.chronique.cout_incendie)),
		"la propriete-menace doit ouvrir le cout d'incendie sur la reserve d'integrite")

	var illisible_vu := false
	for i in 200:
		Depense.avancer([chronique], DELTA, _catalogues.seuils_reserve)
		if Banc.est_illisible(chronique, _config) and not illisible_vu:
			illisible_vu = true
			verif.v(not Banc.est_consumee(chronique, _config),
				"le premier palier doit tomber AVANT le second -- un escalier, jamais un seul seuil")
		if Banc.est_consumee(chronique, _config):
			break
	verif.v(illisible_vu, "le premier palier doit poser la cle d'illisibilite")
	verif.v(Banc.est_consumee(chronique, _config), "le second palier doit poser le marqueur de terminus")

	var transformees := Banc.transformer_consumees([chronique], _config, _catalogues.types, _catalogues.materiaux)
	verif.v(transformees.size() == 1, "le cablage doit appeler lui-meme la transformation -- depense.gd ne produit rien")
	verif.v(not chronique.proprietes.has("contenu_croyance"),
		"la chronique consumee perd son registre fige : il n'y a plus rien a lire")
	verif.v(not chronique.proprietes.has("reserves"),
		"elle perd aussi sa reserve d'integrite -- proprietes est vide puis remplie a neuf")
	verif.v(Banc.est_cendre(chronique, _config), "elle porte desormais le type produit")
	verif.v(float(chronique.proprietes.masse) > 0.0,
		"la masse du produit est derivee de la composition, jamais posee a la main")
	verif.v(Banc.transformer_consumees([chronique], _config, _catalogues.types, _catalogues.materiaux).is_empty(),
		"un second passage ne doit rien retransformer -- le garde est l'absence du marqueur")

func _les_croyances_du_lecteur_survivent_a_la_destruction() -> void:
	var auteur := _auteur_ayant_observe()
	var chronique := _chronique_de(auteur)
	var lecteur: Dictionary = Banc.construire_colons(_config)[1]
	lecteur.position = chronique.position
	Banc.lire_si_cadence(lecteur, [chronique], _config, _catalogues.croyances, 0.0)
	var acquises: int = lecteur.proprietes.croyances.size()
	verif.v(acquises > 0, "le lecteur doit d'abord avoir acquis quelque chose")

	chronique.proprietes[String(_config.chronique.marqueur_consumee)] = true
	Banc.transformer_consumees([chronique], _config, _catalogues.types, _catalogues.materiaux)
	verif.v(lecteur.proprietes.croyances.size() == acquises,
		"la destruction de la chronique ne retire rien aux croyances du lecteur")

	Croyance.avancer(lecteur, 1.0, _catalogues.croyances)
	verif.v(lecteur.proprietes.croyances.size() == acquises,
		"un pas d'oubli ne les efface pas d'un coup : elles decroissent")
	for i in 600:
		Croyance.avancer(lecteur, 0.1, _catalogues.croyances)
	verif.v(lecteur.proprietes.croyances.is_empty(),
		"faute d'y revenir, elles finissent par tomber sous le plancher et disparaitre")

func _un_fantome_est_filtre_avant_tout_mecanisme() -> void:
	var auteur := _auteur_ayant_observe()
	var chronique := _chronique_de(auteur)
	var fantome := _chronique_de(auteur)
	fantome["id"] = "chronique_fantome"
	fantome.proprietes.clear()

	var vivantes := Banc.monde_vivant([chronique, fantome])
	verif.v(vivantes.size() == 1 and String(vivantes[0].id) == String(chronique.id),
		"le filtre doit retenir la chronique reelle et ecarter celle dont proprietes a ete vide")

	var etat := Banc.etat_initial(_config)
	etat.chroniques.append(chronique)
	etat.chroniques.append(fantome)
	var bilan := Banc.avancer(etat, _config, _catalogues, DELTA, 1.0)
	verif.v(bilan.has("colons"), "un pas complet doit traverser un monde contenant un fantome sans s'interrompre")
	verif.v(int(bilan.chroniques_lisibles) == 1,
		"le fantome ne doit compter ni comme lisible ni comme cendre")

func _le_total_des_reserves_est_constant_hors_transfert() -> void:
	# L'automne n'est ni saison de pousse ni saison froide : aucune propriete
	# receptrice n'est posee, donc aucune ligne de flux ne transfere.
	var neutre := ""
	for saison in _config.cycle.saisons:
		if String(saison) != String(_config.saison_froide) and not _config.saisons_de_pousse.has(saison):
			neutre = String(saison)
			break
	verif.v(neutre != "", "la donnee doit declarer au moins une saison neutre pour que ce cas ait un sens")

	var scene := _scene_vegetale(neutre, false, false)
	var plantes: Array = scene.plantes
	var monde: Array = plantes + scene.sources
	var depart := _total(plantes)
	for i in 100:
		Flux.avancer(monde, Banc.table_flux_rapide(_config), DELTA)
		Flux.avancer(monde, Banc.table_flux_lent(_config), DELTA)
		Banc.poser_cout_gel(plantes, _config)
		Depense.avancer(plantes, DELTA, {})
		Banc.borner_reserves(plantes, _config)
	verif.v(is_equal_approx(_total(plantes), depart),
		"hors saison de pousse et hors saison froide, cent pas ne changent pas d'un iota le total des reserves")

func _la_configuration_du_disque_traverse_plusieurs_saisons() -> void:
	var etat := Banc.etat_initial(_config)
	var duree_saison: float = float(_config.cycle.duree_jour_secondes) * float(_config.cycle.jours_par_saison)
	var pas: int = int(duree_saison * float(_config.cycle.saisons.size()) * 2.0 / DELTA)
	var saisons_vues: Dictionary = {}
	var changements := 0
	var temps := 0.0
	var dernier: Dictionary = {}
	for i in pas:
		temps += DELTA
		dernier = Banc.avancer(etat, _config, _catalogues, DELTA, temps)
		saisons_vues[String(dernier.saison)] = true
		if bool(dernier.changement_saison):
			changements += 1

	verif.v(saisons_vues.size() == _config.cycle.saisons.size(),
		"deux cycles complets doivent faire passer TOUTES les saisons declarees")
	verif.v(changements >= _config.cycle.saisons.size() * 2 - 1,
		"chaque saison doit avoir ete comptee comme un changement")
	verif.v(int(dernier.chroniques_ecrites) == int(_config.chronique.maximum),
		"l'auteur doit avoir rempli les rayonnages sur cette duree")
	verif.v(float(dernier.reserve_totale) > 0.0 and float(dernier.reserve_totale)
		<= float(_config.capacite_vegetale) * float(_config.plantes.size()),
		"les reserves doivent rester dans leurs bornes -- le cablage plafonne et planche lui-meme")

	var lecteurs := 0
	for etat_colon in dernier.colons:
		if int(etat_colon.lues) > 0:
			lecteurs += 1
	verif.v(lecteurs >= 2, "au moins deux colons a portee doivent avoir lu")
	var isole := Banc.chose_par_id(etat.colons, "colon_isole")
	verif.v(isole.proprietes.chroniques_lues.is_empty(),
		"le colon hors de portee de tout rayonnage ne lit jamais rien -- c'est le temoin")

	# Le feu, sur la configuration reelle : deux rayonnages hors de portee de
	# travail du gardien doivent finir en cendre, celui qu'il touche est sauve.
	Banc.basculer_brasier(etat, _config)
	for i in 400:
		temps += DELTA
		dernier = Banc.avancer(etat, _config, _catalogues, DELTA, temps)
	var cendres := 0
	for chronique in etat.chroniques:
		if Banc.est_cendre(chronique, _config):
			cendres += 1
	verif.v(cendres >= 1, "le feu doit avoir consume au moins un rayonnage jusqu'au terminus")
	verif.v(int(dernier.chroniques_lisibles) < int(_config.chronique.maximum),
		"la bibliotheque brulee doit avoir perdu au moins un rayonnage lisible")
