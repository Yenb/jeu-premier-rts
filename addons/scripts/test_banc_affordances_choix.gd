extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_affordances_choix.gd
#
# Verrouille le CABLAGE de scripts/banc_affordances_choix.gd (les trois poids de
# la ligne 11 -- urgence par deformation, distance par portee de profil, habitude
# par deformation --, la cadence de re-scoring de la ligne 12, la stabilite par
# inertie + engagement, et l'absence de toute file de plan) -- jamais
# scripts/perception.gd, scripts/proximite.gd, scripts/dominance.gd,
# scripts/agir.gd, scripts/deformation.gd ni scripts/couplage.gd eux-memes, deja
# verrouilles par leurs propres tests.
#
# LES TROIS CATALOGUES SONT LUS SUR LE DISQUE (data/canaux.json,
# data/profils_saillance.json, data/deformations.json) et la config du banc AUSSI
# (data/banc_affordances_choix.json) : la calibration de ce chantier est
# precisement ce qui peut se casser en silence -- les quatre distances et les
# quatre saillances nues portent TOUTE la demonstration, et un profil deplace de
# quelques dizaines d'unites inverserait l'arbitrage sans qu'aucune assertion de
# mecanisme ne rougisse. Lecon de banc_maladie, dont le canal ne contaminait
# JAMAIS personne pendant que son test restait vert faute de rejouer le JSON reel.
# Les seules fixtures de ce fichier sont celles du cas HORS DOMAINE, dont c'est
# tout l'objet.
#
# LE TICK N'EST JAMAIS RECONSTITUE ICI : ce fichier appelle Banc.avancer_tick, la
# MEME fonction statique que _process appelle. Rejouer l'ordre a la main aurait
# laisse la scene et le test deriver l'un de l'autre sans qu'aucun ne rougisse.

const Banc = preload("res://scripts/banc_affordances_choix.gd")
const Monde = preload("res://scripts/monde.gd")
const Deformation = preload("res://scripts/deformation.gd")
const Agir = preload("res://scripts/agir.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA := 0.1

func _json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _config() -> Dictionary:
	return _json("res://data/banc_affordances_choix.json")

func _canaux() -> Dictionary:
	return _json("res://data/canaux.json")

func _profils() -> Dictionary:
	return _json("res://data/profils_saillance.json")

func _deformations() -> Dictionary:
	return _json("res://data/deformations.json")

func _actions(config: Dictionary) -> Dictionary:
	var catalogue: Dictionary = _json("res://data/types_choses.json")
	for cle in config.get("catalogue_local", {}):
		if String(cle).begins_with("_"):
			continue
		catalogue[String(cle)] = config.catalogue_local[cle]
	return catalogue

func _init() -> void:
	var v := Verif.new()
	_les_distances_et_les_saillances_nues_du_disque_tiennent(v)
	_la_distance_fait_gagner_le_bois_proche(v)
	_l_habitude_fait_gagner_la_forge_quand_le_bois_s_eloigne(v)
	_l_urgence_fait_gagner_la_nourriture(v)
	_la_decision_est_stable_entre_deux_re_scorings(v)
	_le_re_scoring_change_la_decision_quand_l_urgence_change(v)
	_le_biais_ne_bascule_pas_avec_le_clic_il_monte_et_redescend(v)
	_la_deformation_est_par_percevant_et_par_cible(v)
	_les_deux_plafonds_de_biais_tiennent(v)
	_l_engagement_se_pose_par_presence_et_s_arrache_par_absence(v)
	_l_engagement_est_retire_quand_la_decision_change_de_cible(v)
	_l_inertie_et_l_engagement_resistent_a_un_ecart_faible(v)
	_le_poids_avancement_est_present_et_exactement_neutre(v)
	_le_score_affiche_designe_la_meme_cible_que_agir(v)
	_dominance_ecrase_la_forge_quand_l_urgence_est_au_plafond(v)
	_poids_verbes_ne_pese_jamais_entre_deux_cibles(v)
	_aucune_file_de_plan_dans_ce_banc(v)
	_hors_domaine_le_meme_code_traverse_un_vocabulaire_invente(v)

	if v.echecs() > 0:
		print("ECHEC: %d verification(s) en echec" % v.echecs())
		quit(1)
	else:
		print("OK: banc_affordances_choix -- les trois poids (urgence par deformation, distance par portee de profil, habitude par deformation), la cadence de re-scoring, la stabilite par inertie + engagement, et l'absence de toute file de plan")
		quit(0)

# ---- Outils de scenario -------------------------------------------------

# Construit la scene EXACTEMENT comme _ready la construit : memes fonctions
# statiques, aucune fixture parallele.
func _scene(config: Dictionary) -> Dictionary:
	var colon: Dictionary = Banc.construire_colon(config)
	var cibles: Array = Banc.construire_cibles(config)
	var monde = Monde.new()
	monde.ajouter(colon, "colon", colon.position)
	for cible in cibles:
		monde.ajouter(cible, "cible", cible.position)
	return {"colon": colon, "cibles": cibles, "monde": monde, "temps": 0.0, "infos": {}}

func _simuler(scene: Dictionary, config: Dictionary, ticks: int) -> void:
	for i in range(ticks):
		scene["temps"] = float(scene.temps) + DELTA
		scene["infos"] = Banc.avancer_tick(
			scene.colon, scene.monde, scene.cibles, DELTA, float(scene.temps), config,
			_canaux(), _profils(), _deformations(), _actions(config))

func _cible_decidee(scene: Dictionary) -> String:
	return String(scene.colon.get("decision_en_cours", {}).get("cible_id", ""))

func _verbe_decide(scene: Dictionary) -> String:
	return String(scene.colon.get("decision_en_cours", {}).get("verbe", ""))

func _saillance(scene: Dictionary, id: String) -> float:
	return float(scene.infos.get("saillances", {}).get(id, {}).get("saillance", 0.0))

func _nue(scene: Dictionary, id: String) -> float:
	return float(scene.infos.get("saillances", {}).get(id, {}).get("nue", 0.0))

func _distance(scene: Dictionary, id: String) -> float:
	return float(scene.infos.get("saillances", {}).get(id, {}).get("distance", 0.0))

# ---- Cas ---------------------------------------------------------------

func _les_distances_et_les_saillances_nues_du_disque_tiennent(v) -> void:
	# TOUTE la demonstration repose sur ces quatre nombres. Les verifier par le
	# MECANISME (Proximite.evaluer via avancer_tick), jamais par des constantes
	# recopiees a cote qui pourraient diverger du disque.
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 1)

	v.v(is_equal_approx(_distance(scene, "bois"), 120.0),
		"le bois doit etre a 120 unites du colon dans la scene du disque, recu %f" % _distance(scene, "bois"))
	v.v(is_equal_approx(_distance(scene, "forge"), 400.0),
		"la forge doit etre a 400 unites, recu %f" % _distance(scene, "forge"))
	v.v(is_equal_approx(_distance(scene, "repas"), 500.0),
		"le repas doit etre a 500 unites, recu %f" % _distance(scene, "repas"))

	# LES SAILLANCES NUES, calculees par proximite.gd depuis les profils REELS.
	v.v(abs(_nue(scene, "bois") - 3.0) < 0.001,
		"bois proche : saillance nue attendue 3.000 (5.0 x (1 - 120/300)), recu %f" % _nue(scene, "bois"))
	v.v(abs(_nue(scene, "forge") - 1.111) < 0.01,
		"forge : saillance nue attendue 1.111 (2.0 x (1 - 400/900)), recu %f" % _nue(scene, "forge"))
	v.v(abs(_nue(scene, "repas") - 0.714) < 0.01,
		"repas : saillance nue attendue 0.714 (2.5 x (1 - 500/700)), recu %f" % _nue(scene, "repas"))

	# LE BOIS ELOIGNE, l'autre bout du toggle : la portee COURTE le fait
	# s'effondrer la ou une portee longue l'aurait a peine entame.
	Banc.basculer_distance(scene.cibles, config, false)
	_simuler(scene, config, 1)
	v.v(is_equal_approx(_distance(scene, "bois"), 280.0),
		"le bois eloigne doit etre a 280 unites, recu %f" % _distance(scene, "bois"))
	v.v(abs(_nue(scene, "bois") - 0.333) < 0.01,
		"bois eloigne : saillance nue attendue 0.333 (5.0 x (1 - 280/300)), recu %f" % _nue(scene, "bois"))

func _la_distance_fait_gagner_le_bois_proche(v) -> void:
	# ETAT (A). Le colon est rassasie, le bois est proche : il gagne SANS aucune
	# deformation -- la seule des trois cibles qui l'emporte par sa position.
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 1)

	v.v(_cible_decidee(scene) == "bois",
		"rassasie et bois proche : la decision doit etre le bois, recu '%s'" % _cible_decidee(scene))
	v.v(_verbe_decide(scene) == "ramasser",
		"le verbe resolu doit venir de la propriete de la cible gagnante, recu '%s'" % _verbe_decide(scene))
	v.v(is_equal_approx(_saillance(scene, "bois"), _nue(scene, "bois")),
		"le bois ne porte AUCUNE deformation : sa saillance doit valoir exactement sa nue (%f contre %f)"
			% [_saillance(scene, "bois"), _nue(scene, "bois")])
	v.v(_saillance(scene, "bois") > _saillance(scene, "forge") and _saillance(scene, "bois") > _saillance(scene, "repas"),
		"il doit battre les deux autres au premier tick (bois %f, forge %f, repas %f)"
			% [_saillance(scene, "bois"), _saillance(scene, "forge"), _saillance(scene, "repas")])

	# ET LA CONTRE-EPREUVE, qui est le point : le MEME objet, 160 unites plus
	# loin, ne gagne plus rien -- parce que sa portee de profil est courte.
	Banc.basculer_distance(scene.cibles, config, false)
	_simuler(scene, config, 40)
	v.v(_cible_decidee(scene) != "bois",
		"eloigne de 160 unites, le meme bois ne doit plus gagner, recu '%s'" % _cible_decidee(scene))

func _l_habitude_fait_gagner_la_forge_quand_le_bois_s_eloigne(v) -> void:
	# ETAT (B). La forge ne gagne JAMAIS nue (1.111 contre 3.000 pour le bois
	# proche) : c'est la deformation d'habitude, et elle seule, qui la porte a
	# 2.000 et lui fait passer devant un bois eloigne.
	var config := _config()
	var scene := _scene(config)
	Banc.basculer_distance(scene.cibles, config, false)
	_simuler(scene, config, 60)

	v.v(_cible_decidee(scene) == "forge",
		"rassasie et bois eloigne : la decision doit etre la forge, recu '%s'" % _cible_decidee(scene))
	v.v(_verbe_decide(scene) == "forger",
		"le verbe resolu doit etre celui de la forge, recu '%s'" % _verbe_decide(scene))
	v.v(_saillance(scene, "forge") > _nue(scene, "forge"),
		"l'habitude doit MONTER la saillance de la forge (%f contre %f nue)"
			% [_saillance(scene, "forge"), _nue(scene, "forge")])
	var attendu: float = _nue(scene, "forge") * (1.0 + float(scene.infos.biais_habitude))
	v.v(is_equal_approx(_saillance(scene, "forge"), attendu),
		"la saillance deformee doit valoir exactement nue x (1 + biais) : attendu %f, recu %f"
			% [attendu, _saillance(scene, "forge")])

	# UN COLON SANS PLI N'A AUCUNE DEFORMATION D'HABITUDE : ce n'est pas un cas
	# particulier code, c'est la meme arithmetique lue a zero (magnitude nulle,
	# poser() jamais appele, registre jamais cree).
	var config_sans := _config()
	config_sans.colon["pli_atelier"] = 0.0
	var scene_sans := _scene(config_sans)
	Banc.basculer_distance(scene_sans.cibles, config_sans, false)
	_simuler(scene_sans, config_sans, 60)
	v.v(not scene_sans.colon.proprietes.deformation_etat.has(String(config.source_deformation_habitude)),
		"un colon a pli NUL ne doit porter aucun registre d'habitude, recu %s"
			% str(scene_sans.colon.proprietes.deformation_etat.keys()))
	v.v(is_equal_approx(_saillance(scene_sans, "forge"), _nue(scene_sans, "forge")),
		"la forge doit lui arriver a sa saillance NUE, sans un poil de modulation (%f contre %f)"
			% [_saillance(scene_sans, "forge"), _nue(scene_sans, "forge")])

func _l_urgence_fait_gagner_la_nourriture(v) -> void:
	# ETAT (C). Le repas est la cible la PLUS LOINTAINE et la MOINS saillante en
	# soi (0.714) : sans deformation il ne gagne jamais. C'est la ligne 11 dans sa
	# forme la plus nette -- un etat interne fait gagner une cible.
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 1)
	v.v(_cible_decidee(scene) != "repas",
		"rassasie, le repas ne doit PAS gagner, recu '%s'" % _cible_decidee(scene))

	Banc.basculer_faim(scene.colon, config, false)
	_simuler(scene, config, 100)
	v.v(_cible_decidee(scene) == "repas",
		"affame, la decision doit etre le repas, recu '%s'" % _cible_decidee(scene))
	v.v(_verbe_decide(scene) == "manger",
		"le verbe resolu doit etre celui du comestible, recu '%s'" % _verbe_decide(scene))
	v.v(_saillance(scene, "repas") > _saillance(scene, "bois"),
		"le repas doit passer devant le bois PROCHE (%f contre %f)"
			% [_saillance(scene, "repas"), _saillance(scene, "bois")])
	var attendu: float = _nue(scene, "repas") * (1.0 + float(scene.infos.biais_urgence))
	v.v(is_equal_approx(_saillance(scene, "repas"), attendu),
		"la saillance deformee doit valoir exactement nue x (1 + biais) : attendu %f, recu %f"
			% [attendu, _saillance(scene, "repas")])

	# ET LE RETOUR : rassasie, le biais retombe et l'arbitrage revient au bois.
	Banc.basculer_faim(scene.colon, config, true)
	_simuler(scene, config, 200)
	v.v(_cible_decidee(scene) == "bois",
		"rassasie de nouveau, la decision doit revenir au bois proche, recu '%s'" % _cible_decidee(scene))

func _la_decision_est_stable_entre_deux_re_scorings(v) -> void:
	# LIGNE 12. Entre deux echeances, RIEN n'est recalcule : la decision
	# precedente est conservee telle quelle, meme si le monde a change.
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 1)
	var premiere := _cible_decidee(scene)
	v.v(bool(scene.infos.rescore),
		"le tout premier tick doit re-scorer (echeance a 0.0)")

	var ticks_sous_cadence: int = int(float(config.cadence_scoring_s) / DELTA) - 2
	var rescorings := 0
	for i in range(ticks_sous_cadence):
		_simuler(scene, config, 1)
		if bool(scene.infos.rescore):
			rescorings += 1
	v.v(rescorings == 0,
		"aucun re-scoring ne doit avoir lieu avant l'echeance, recu %d" % rescorings)
	v.v(_cible_decidee(scene) == premiere,
		"la decision doit tenir inchangee entre deux re-scorings, recu '%s' au lieu de '%s'"
			% [_cible_decidee(scene), premiere])

	# LE CAS QUI PROUVE QUE C'EST BIEN LA CADENCE, ET PAS UN HASARD : on affame le
	# colon SOUS l'echeance ; sa decision ne bouge pas d'un pouce tant que
	# l'echeance n'est pas atteinte. C'est le prix de la ligne 12, dit plutot que
	# masque -- il est AVEUGLE pendant ce temps.
	var scene2 := _scene(config)
	_simuler(scene2, config, 1)
	Banc.basculer_faim(scene2.colon, config, false)
	for i in range(ticks_sous_cadence):
		_simuler(scene2, config, 1)
		v.v(_cible_decidee(scene2) == premiere,
			"sous l'echeance, meme affame, la decision ne doit pas changer (recu '%s')" % _cible_decidee(scene2))
	v.v(float(scene2.infos.biais_urgence) > 0.0,
		"le biais d'urgence, lui, doit avoir monte pendant ce temps : le corps ne s'arrete pas, seule la decision est cadencee")

func _le_re_scoring_change_la_decision_quand_l_urgence_change(v) -> void:
	# L'AUTRE MOITIE DE LA LIGNE 12 : la cadence retarde, elle ne fige pas. A
	# l'echeance, les quatre couches repartent de zero sur le monde tel qu'il est.
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 1)
	var depart := _cible_decidee(scene)
	Banc.basculer_faim(scene.colon, config, false)

	var change_vu := false
	var cible_apres := ""
	for i in range(120):
		_simuler(scene, config, 1)
		if bool(scene.infos.change):
			change_vu = true
			cible_apres = _cible_decidee(scene)
			break
	v.v(change_vu,
		"un re-scoring doit finir par changer la decision apres la montee de l'urgence")
	v.v(cible_apres == "repas" and depart != "repas",
		"le changement doit aller vers le repas (de '%s' vers '%s')" % [depart, cible_apres])
	v.v(bool(scene.infos.rescore),
		"un changement de decision ne peut se produire QUE sur un tick de re-scoring")

func _le_biais_ne_bascule_pas_avec_le_clic_il_monte_et_redescend(v) -> void:
	# Le clic ecrit une RESERVE, jamais un biais. Le biais monte par pose x delta
	# et redescend par soustraction fixe -- c'est ce delai qui rend la cadence
	# observable a l'oeil.
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 1)
	v.v(float(scene.infos.biais_urgence) == 0.0,
		"rassasie, l'urgence vaut 0.0 : aucune magnitude posee, aucun biais, recu %f" % float(scene.infos.biais_urgence))
	v.v(not scene.colon.proprietes.deformation_etat.has(String(config.source_deformation_urgence)),
		"et le registre d'urgence ne doit meme pas exister, recu %s"
			% str(scene.colon.proprietes.deformation_etat.keys()))

	Banc.basculer_faim(scene.colon, config, false)
	_simuler(scene, config, 1)
	var apres_un_tick: float = float(scene.infos.biais_urgence)
	v.v(apres_un_tick > 0.0 and apres_un_tick < float(config.plafond_biais_urgence),
		"un tick apres le clic, le biais doit avoir commence a monter SANS etre deja au plafond, recu %f" % apres_un_tick)
	_simuler(scene, config, 60)
	v.v(float(scene.infos.biais_urgence) > apres_un_tick,
		"il doit continuer de monter tant que la faim dure (%f puis %f)" % [apres_un_tick, float(scene.infos.biais_urgence)])

	Banc.basculer_faim(scene.colon, config, true)
	var au_sommet: float = float(scene.infos.biais_urgence)
	_simuler(scene, config, 20)
	v.v(float(scene.infos.biais_urgence) < au_sommet,
		"rassasie, il doit REDESCENDRE (%f puis %f)" % [au_sommet, float(scene.infos.biais_urgence)])

func _la_deformation_est_par_percevant_et_par_cible(v) -> void:
	# LA RAISON POUR LAQUELLE C'EST deformation.gd ET RIEN D'AUTRE : le biais est
	# indexe [source][cible] sur l'entite qui REGARDE, jamais sur la chose vue.
	# Deux sources sur deux cibles distinctes ne se touchent jamais.
	var config := _config()
	var scene := _scene(config)
	Banc.basculer_faim(scene.colon, config, false)
	_simuler(scene, config, 60)

	var etat: Dictionary = scene.colon.proprietes.deformation_etat
	v.v(etat.has(String(config.source_deformation_urgence)) and etat.has(String(config.source_deformation_habitude)),
		"les DEUX sources doivent tenir chacune leur registre, recu %s" % str(etat.keys()))
	v.v(etat[String(config.source_deformation_urgence)].has(String(config.cible_deformation_urgence)),
		"l'urgence doit viser sa cible declaree, recu %s" % str(etat[String(config.source_deformation_urgence)].keys()))
	v.v(etat[String(config.source_deformation_habitude)].has(String(config.cible_deformation_habitude)),
		"l'habitude doit viser la sienne, recu %s" % str(etat[String(config.source_deformation_habitude)].keys()))

	# LE BOIS NE PORTE NI L'UNE NI L'AUTRE DES DEUX PROPRIETES CIBLEES : sa
	# saillance traverse les deux biais sans en prendre un seul.
	v.v(is_equal_approx(_saillance(scene, "bois"), _nue(scene, "bois")),
		"le bois ne porte aucune des deux cibles : sa saillance doit rester exactement nue (%f contre %f)"
			% [_saillance(scene, "bois"), _nue(scene, "bois")])

	# ET LE TEMOIN : un lecteur sans deformation voit les trois cibles a leur
	# valeur nue, au meme instant, aux memes distances.
	v.v(_nue(scene, "repas") < _saillance(scene, "repas"),
		"la saillance nue du repas doit rester sous celle que CE colon lui donne (%f contre %f)"
			% [_nue(scene, "repas"), _saillance(scene, "repas")])

func _les_deux_plafonds_de_biais_tiennent(v) -> void:
	# deformation.gd n'a AUCUNE borne haute et decroit par SOUSTRACTION FIXE : il
	# n'existe AUCUN equilibre naturel. Sans ces deux plafonds de cablage, le
	# repas finirait par tout ecraser et le banc ne montrerait plus d'arbitrage.
	var config := _config()
	var scene := _scene(config)
	Banc.basculer_faim(scene.colon, config, false)
	_simuler(scene, config, 600)

	v.v(float(scene.infos.biais_urgence) <= float(config.plafond_biais_urgence) + 0.5,
		"le biais d'urgence doit rester au voisinage de son plafond %f apres 60 s, recu %f"
			% [float(config.plafond_biais_urgence), float(scene.infos.biais_urgence)])
	v.v(float(scene.infos.biais_habitude) <= float(config.plafond_biais_habitude) + 0.5,
		"le biais d'habitude doit rester au voisinage de son plafond %f, recu %f"
			% [float(config.plafond_biais_habitude), float(scene.infos.biais_habitude)])

	# CONTRE-EPREUVE : au-dessus du plafond, le cablage cesse de poser -- ce n'est
	# pas le mecanisme qui borne, il n'a AUCUNE borne haute. Le registre est
	# pousse a la main bien au-dela, parce qu'en regime le biais OSCILLE d'une
	# magnitude de tick autour du plafond (la pose s'arrete, la decroissance le
	# fait repasser dessous, la pose reprend) -- comportement documente dans
	# data/deformations.json, invisible a l'ecran, et qu'une assertion « pose
	# exactement nulle en regime » prendrait a tort pour un defaut.
	Deformation.poser(scene.colon, String(config.source_deformation_urgence),
		String(config.cible_deformation_urgence), 100.0)
	var pose: float = float(Banc.poser_deformations(scene.colon, 1.0, DELTA, config, _deformations()).urgence)
	v.v(pose == 0.0,
		"au-dessus du plafond, poser_deformations ne doit plus rien poser du tout, recu %f" % pose)

func _l_engagement_se_pose_par_presence_et_s_arrache_par_absence(v) -> void:
	# couplage.gd : « se pose par presence, se retire par absence ou satisfaction,
	# jamais par choix ». Le bois proche (120) est dans la portee d'engagement
	# (450) ; le repas (500) ne l'est pas.
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 1)

	var engagement = scene.colon.proprietes.engagement
	v.v(engagement != null and String(engagement.cible_id) == "bois",
		"le colon doit etre couple au bois proche des le premier re-scoring, recu %s" % str(engagement))
	v.v(is_equal_approx(float(engagement.poids), float(config.engagements_locaux.attelage_cible.poids)),
		"le poids doit venir du catalogue LOCAL du banc, recu %f" % float(engagement.poids))

	# L'ENGAGEMENT NE SE SATISFAIT JAMAIS ICI : rien n'avance travail_restant.
	_simuler(scene, config, 100)
	v.v(scene.colon.proprietes.engagement != null,
		"personne n'avance le travail : l'engagement ne doit jamais se satisfaire")
	v.v(String(scene.infos.issue_engagement) == "garde",
		"couplage.gd doit rendre 'garde' tant que la cible est a portee, recu '%s'" % String(scene.infos.issue_engagement))

	# ELOIGNER LE BOIS AU-DELA DE LA PORTEE L'ARRACHE, sans qu'aucune decision
	# n'intervienne -- c'est l'ABSENCE qui retire, pas un choix.
	var config_loin := _config()
	config_loin["portee_engagement"] = 50.0
	_simuler(scene, config_loin, 1)
	v.v(String(scene.infos.issue_engagement) == "arrache",
		"une cible sortie de portee doit rendre 'arrache', recu '%s'" % String(scene.infos.issue_engagement))
	v.v(scene.colon.proprietes.engagement == null,
		"et couplage.gd doit avoir remis l'engagement a null lui-meme")

func _l_engagement_est_retire_quand_la_decision_change_de_cible(v) -> void:
	# LE GESTE QUE agir.gd RECLAME NOMMEMENT dans son en-tete. Sans lui, un colon
	# parti manger resterait couple au bois qu'il a quitte, et le poids
	# d'engagement le ramenerait au re-scoring suivant : une oscillation a deux
	# temps, invisible tant qu'on ne regarde pas deux echeances de suite.
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 1)
	v.v(String(scene.colon.proprietes.engagement.cible_id) == "bois",
		"pre-requis : le colon doit partir couple au bois")

	Banc.basculer_faim(scene.colon, config, false)
	_simuler(scene, config, 120)
	v.v(_cible_decidee(scene) == "repas",
		"pre-requis : la decision doit avoir bascule vers le repas, recu '%s'" % _cible_decidee(scene))
	v.v(scene.colon.proprietes.engagement == null,
		"le colon parti manger ne doit plus etre couple au bois, recu %s" % str(scene.colon.proprietes.engagement))

	# ET IL N'EST COUPLE A RIEN : le repas est a 500 unites pour une portee de
	# 450. « Se pose par presence » veut dire exactement ca.
	v.v(_distance(scene, "repas") > float(config.portee_engagement),
		"pre-requis de ce verrou : le repas doit etre hors de la portee d'engagement (%f contre %f)"
			% [_distance(scene, "repas"), float(config.portee_engagement)])

func _l_inertie_et_l_engagement_resistent_a_un_ecart_faible(v) -> void:
	# LA STABILITE AU MOMENT MEME DU RE-SCORING, distincte de celle que produit la
	# cadence : a saillance a peine superieure, l'alternative ne passe pas.
	# PLI NUL POUR CE CAS SEULEMENT : sans lui, la deformation d'habitude
	# multiplierait la saillance de la forge par 1.8 et le nombre qu'on cherche a
	# placer entre deux bornes ne serait plus celui qu'on regle.
	var config := _config()
	config.colon["pli_atelier"] = 0.0
	var scene := _scene(config)
	_simuler(scene, config, 1)
	v.v(_cible_decidee(scene) == "bois",
		"pre-requis : la decision de depart doit etre le bois")

	# On remonte la saillance de la forge juste au-dessus de celle du bois, sans
	# atteindre bois + gain_inertie + poids d'engagement (3.0 + 0.25 + 0.5).
	var profils := _profils()
	profils["forge_choix"] = {"saillance_intrinseque": 6.0, "portee_saillance": 900.0}
	var nue_forge: float = 6.0 * (1.0 - 400.0 / 900.0)
	v.v(nue_forge > 3.0 and nue_forge < 3.75,
		"pre-requis de ce verrou : la forge doit passer AU-DESSUS du bois nu sans atteindre bois + inertie + engagement (recu %f)" % nue_forge)

	for i in range(60):
		scene["temps"] = float(scene.temps) + DELTA
		scene["infos"] = Banc.avancer_tick(
			scene.colon, scene.monde, scene.cibles, DELTA, float(scene.temps), config,
			_canaux(), profils, _deformations(), _actions(config))
	v.v(_cible_decidee(scene) == "bois",
		"une alternative superieure de moins que gain_inertie + poids d'engagement ne doit PAS deloger la decision, recu '%s'"
			% _cible_decidee(scene))

	# CONTRE-EPREUVE : au-dessus de la somme des deux bonus, elle passe.
	# L'ENGAGEMENT RALENTIT, IL NE VERROUILLE PAS -- agir.gd le dit dans son
	# en-tete (« l'arrachement par saillance N'EST PAS empeche ici »).
	profils["forge_choix"] = {"saillance_intrinseque": 12.0, "portee_saillance": 900.0}
	for i in range(60):
		scene["temps"] = float(scene.temps) + DELTA
		scene["infos"] = Banc.avancer_tick(
			scene.colon, scene.monde, scene.cibles, DELTA, float(scene.temps), config,
			_canaux(), profils, _deformations(), _actions(config))
	v.v(_cible_decidee(scene) == "forge",
		"au-dela des deux bonus, l'alternative doit gagner -- l'engagement RALENTIT, il ne verrouille pas, recu '%s'"
			% _cible_decidee(scene))

func _le_poids_avancement_est_present_et_exactement_neutre(v) -> void:
	# LE QUATRIEME MECANISME DE STABILITE nomme par l'audit : il est bien traverse
	# (les deux cles sont posees, couplage.gd en a besoin), et il vaut EXACTEMENT
	# 1.000 ici puisque rien n'avance le travail. Le verifier plutot que le
	# supposer -- une valeur autre que 1.0 fausserait toute la calibration en
	# silence.
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 1)
	for cible in scene.cibles:
		var p: Dictionary = cible.proprietes
		v.v(p.has("travail_restant") and p.has("travail_initial"),
			"chaque cible doit porter les DEUX cles (couplage.gd lit travail_restant), '%s' porte %s"
				% [String(cible.id), str(p.keys())])
		v.v(float(p.travail_initial) > 0.0 and is_equal_approx(float(p.travail_restant), float(p.travail_initial)),
			"restant et initial doivent rester egaux et strictement positifs sur '%s' (%f / %f)"
				% [String(cible.id), float(p.travail_restant), float(p.travail_initial)])

	# La preuve par le NOMBRE : la saillance nue du bois vaut exactement le produit
	# poids x facteur de distance, donc le facteur d'avancement vaut 1.000.
	var attendu: float = 5.0 * (1.0 - 120.0 / 300.0)
	v.v(abs(_nue(scene, "bois") - attendu) < 0.001,
		"_poids_avancement doit valoir exactement 1.000 : attendu %f, recu %f" % [attendu, _nue(scene, "bois")])

func _le_score_affiche_designe_la_meme_cible_que_agir(v) -> void:
	# LE VERROU DE LA RECOMPOSITION. agir.gd:_score est prive et choisir() ne rend
	# pas le nombre compare : score_visible le refait pour l'ecran. Ce test exige
	# que son argmax soit EXACTEMENT la cible retenue par Agir.choisir, sur la
	# MEME liste de visibles et dans les trois etats du banc -- une divergence
	# future de agir.gd fera rougir ce banc au lieu de mentir a l'ecran.
	var config := _config()

	# LE TOUT PREMIER RE-SCORING, cas limite qui a REELLEMENT casse une fois
	# (defaut trouve en lancant la scene, invisible a l'argmax) : aucune tache en
	# cours, aucun engagement, donc le score affiche doit valoir EXACTEMENT la
	# saillance. Il valait saillance + gain_inertie tant que action_en_cours etait
	# memorise avant que le resume ne soit calcule.
	var premiere := _scene(config)
	_simuler(premiere, config, 1)
	var d0: Dictionary = premiere.colon.decision_en_cours
	v.v(is_equal_approx(float(d0.score), float(d0.saillance)),
		"au premier re-scoring, le score affiche doit valoir exactement la saillance (aucun bonus possible) : %f contre %f"
			% [float(d0.score), float(d0.saillance)])
	v.v(is_equal_approx(float(d0.score), _saillance(premiere, "bois")),
		"et cette saillance doit etre celle que proximite.gd a rendue pour la cible retenue, recu %f" % float(d0.score))

	for etat in ["A", "B", "C"]:
		var scene := _scene(config)
		if etat == "B":
			Banc.basculer_distance(scene.cibles, config, false)
		if etat == "C":
			Banc.basculer_faim(scene.colon, config, false)
		_simuler(scene, config, 120)

		var r: Dictionary = Banc.decider(scene.colon, scene.monde, config,
			_canaux(), _profils(), _deformations(), _actions(config))
		v.v(r.decision != null,
			"etat %s : une decision doit exister" % etat)
		var meilleur := ""
		var meilleur_score := -INF
		for visible in r.visibles:
			var s: float = Banc.score_visible(visible, scene.colon)
			if s > meilleur_score:
				meilleur_score = s
				meilleur = String(visible.chose.id)
		v.v(meilleur == String(r.decision.chose.id),
			"etat %s : l'argmax du score recompose (%s) doit etre la cible retenue par Agir.choisir (%s)"
				% [etat, meilleur, String(r.decision.chose.id)])

func _dominance_ecrase_la_forge_quand_l_urgence_est_au_plafond(v) -> void:
	# dominance.gd NE TRIE PAS, IL ECRASE : au-dela de seuil_ecrasement, une
	# entree n'est pas « moins prioritaire », elle N'EST PLUS DANS LA LISTE.
	var config := _config()
	var scene := _scene(config)
	Banc.basculer_faim(scene.colon, config, false)
	_simuler(scene, config, 120)

	var visibles: Array = scene.infos.visibles_ids
	v.v(visibles.has("repas") and visibles.has("bois"),
		"le sommet et le second doivent rester visibles, recu %s" % str(visibles))
	v.v(not visibles.has("forge"),
		"la forge, a plus de seuil_ecrasement du sommet, doit avoir ete RETIREE de la liste, recu %s" % str(visibles))
	var ecart: float = _saillance(scene, "repas") - _saillance(scene, "forge")
	v.v(ecart > float(config.colon.forme.seuil_ecrasement),
		"pre-requis de ce verrou : l'ecart au sommet (%f) doit depasser seuil_ecrasement (%f)"
			% [ecart, float(config.colon.forme.seuil_ecrasement)])

	# ET EN ETAT (A), RIEN N'EST ECRASE : l'ecrasement est un effet de
	# l'arbitrage, pas un reglage permanent.
	var scene_a := _scene(config)
	_simuler(scene_a, config, 60)
	v.v(scene_a.infos.visibles_ids.size() == 3,
		"rassasie, les trois cibles doivent rester visibles, recu %s" % str(scene_a.infos.visibles_ids))

func _poids_verbes_ne_pese_jamais_entre_deux_cibles(v) -> void:
	# RESULTAT NEGATIF DEJA PAYE AILLEURS, verrouille ici : agir.gd retient la
	# CIBLE au score, PUIS resout un verbe. Monter le poids d'un verbe ne fait
	# jamais gagner sa cible.
	var config := _config()
	config.colon.poids_verbes["manger"] = 10000.0
	var scene := _scene(config)
	_simuler(scene, config, 60)
	v.v(_cible_decidee(scene) == "bois",
		"un poids de verbe absurde ne doit PAS faire gagner sa cible, recu '%s'" % _cible_decidee(scene))
	v.v(_verbe_decide(scene) == "ramasser",
		"et le verbe resolu reste celui de la cible gagnante, recu '%s'" % _verbe_decide(scene))

	# Un poids NUL rend le verbe inchoisissable sans toucher a l'arbitrage des
	# cibles : la cible gagne toujours, l'action devient vide.
	var config_nul := _config()
	config_nul.colon.poids_verbes["ramasser"] = 0.0
	var scene_nul := _scene(config_nul)
	_simuler(scene_nul, config_nul, 60)
	v.v(_cible_decidee(scene_nul) == "bois" and _verbe_decide(scene_nul) == "",
		"a poids nul, la cible gagne toujours mais aucun verbe n'est resolu (cible '%s', verbe '%s')"
			% [_cible_decidee(scene_nul), _verbe_decide(scene_nul)])

func _aucune_file_de_plan_dans_ce_banc(v) -> void:
	# VERROU NEGATIF, doctrinal : 'actions_gardees' est une FILE DE PLAN, elle
	# tombe sous deux des quatre griefs qui ont fait rejeter BDI
	# (docs/design.md § Contraintes structurelles). ABANDONNEE, jamais ecrite.
	#
	# CE QUI EST CHERCHE EST UNE FORME DE CODE, PAS UN MOT. Les deux noms sont
	# NOMMES en prose dans l'en-tete du banc -- c'est meme la que leur abandon est
	# justifie, et un verrou qui interdirait le mot interdirait d'expliquer
	# pourquoi on ne l'a pas ecrit. Sont donc cherchees les trois formes sous
	# lesquelles un identifiant EXISTE reellement en GDScript ou en JSON : entre
	# guillemets DOUBLES (cle de Dictionary ou de donnee), suivi de ':=' ou de
	# '=' (declaration ou affectation). L'en-tete, lui, cite les deux noms entre
	# guillemets SIMPLES. Les noms sont composes morceau par morceau ici pour que
	# ce fichier ne se fasse pas rougir par son propre verrou.
	var interdit := "actions_" + "gardees"
	var interdit2 := "sur_" + "changement"
	var source := FileAccess.get_file_as_string("res://scripts/banc_affordances_choix.gd")
	var donnees := FileAccess.get_file_as_string("res://data/banc_affordances_choix.json")
	v.v(source != "" and donnees != "",
		"les deux fichiers du banc doivent etre lisibles sur le disque pour que ce verrou ait un sens")
	for nom in [interdit, interdit2]:
		for forme in ["\"%s\"" % nom, "%s :=" % nom, "%s =" % nom, "%s:" % nom]:
			v.v(not source.contains(forme),
				"le banc ne doit porter AUCUNE file d'actions pre-ecrites ni drapeau de changement : forme '%s' trouvee dans le code" % forme)
		v.v(not donnees.contains(nom),
			"ni en donnee : '%s' trouve dans data/banc_affordances_choix.json" % nom)
	v.v(source.contains("'%s'" % interdit),
		"garde-fou de ce verrou : l'en-tete DOIT nommer la case abandonnee et dire pourquoi -- un verrou qui interdirait le mot interdirait de l'expliquer")
	v.v(source.contains("deformation.gd") and source.contains("couplage.gd"),
		"garde-fou de ce verrou : il doit bien lire le fichier attendu (les mecanismes reellement cables y sont)")

	# ET LA PREUVE PAR L'ETAT : ce qui survit d'un re-scoring au suivant est UNE
	# decision, trois champs plats, jamais une liste.
	var config := _config()
	var scene := _scene(config)
	_simuler(scene, config, 120)
	var d = scene.colon.get("decision_en_cours", {})
	v.v(d is Dictionary,
		"la decision conservee doit etre UN Dictionary, jamais un Array")
	for cle in d:
		v.v(not (d[cle] is Array),
			"aucun champ de la decision conservee ne doit etre une liste, '%s' l'est" % String(cle))

func _hors_domaine_le_meme_code_traverse_un_vocabulaire_invente(v) -> void:
	# PREUVE que le cablage ne porte aucun nom en dur : meme code, vocabulaire
	# entierement invente, catalogues locaux. Rien de ce qui suit n'existe dans le
	# depot.
	var config := _config()
	config["canaux"] = ["sonar_grotte"]
	config["deformation_sources"] = ["soif_de_lumiere", "pli_de_ruche"]
	config["nom_reserve_energie"] = "lueur_interne"
	config["nom_pli_atelier"] = "pli_de_ruche"
	config["source_deformation_urgence"] = "soif_de_lumiere"
	config["source_deformation_habitude"] = "pli_de_ruche"
	config["cible_deformation_urgence"] = "luminescent"
	config["cible_deformation_habitude"] = "tissable"
	config["catalogue_local"] = {
		"luminescent": {"verbes": ["absorber"]},
		"filandreux": {"verbes": ["enrouler"]},
		"tissable": {"verbes": ["tisser"]},
	}
	config.colon["poids_verbes"] = {"absorber": 1.0, "enrouler": 1.0, "tisser": 1.0}
	config.cibles[0].proprietes = {"luminescent": true, "profil_saillance": "veine_de_lumiere"}
	config.cibles[1].proprietes = {"filandreux": true, "profil_saillance": "amas_de_fil"}
	config.cibles[2].proprietes = {"tissable": true, "profil_saillance": "metier_de_ruche"}

	var canaux := {"sonar_grotte": {"geometrie": "contact", "proprietes_captees": []}}
	var profils := {
		"veine_de_lumiere": {"saillance_intrinseque": 2.5, "portee_saillance": 700.0},
		"amas_de_fil": {"saillance_intrinseque": 5.0, "portee_saillance": 300.0},
		"metier_de_ruche": {"saillance_intrinseque": 2.0, "portee_saillance": 900.0},
	}
	var deformations := {
		"soif_de_lumiere": {"sens": "monte", "taux_decroissance_rapide": 1.0, "taux_decroissance_lent": 0.8, "w_rapide": 0.5, "w_lent": 0.5},
		"pli_de_ruche": {"sens": "monte", "taux_decroissance_rapide": 0.4, "taux_decroissance_lent": 0.2, "w_rapide": 0.6, "w_lent": 0.4},
	}

	var colon: Dictionary = Banc.construire_colon(config)
	var cibles: Array = Banc.construire_cibles(config)
	var monde = Monde.new()
	monde.ajouter(colon, "creature", colon.position)
	for cible in cibles:
		monde.ajouter(cible, "chose_de_grotte", cible.position)

	v.v(colon.proprietes.reserves.has("lueur_interne"),
		"la reserve doit porter le nom invente, recu %s" % str(colon.proprietes.reserves.keys()))
	v.v(colon.proprietes.has("pli_de_ruche"),
		"le pli doit porter le nom invente, proprietes %s" % str(colon.proprietes.keys()))

	var temps := 0.0
	var infos: Dictionary = {}
	for i in range(60):
		temps += DELTA
		infos = Banc.avancer_tick(colon, monde, cibles, DELTA, temps, config,
			canaux, profils, deformations, config.catalogue_local)
	v.v(String(colon.decision_en_cours.cible_id) == String(config.cibles[1].id),
		"la cible proche a portee courte doit gagner en vocabulaire invente aussi, recu '%s'"
			% String(colon.decision_en_cours.cible_id))
	v.v(String(colon.decision_en_cours.verbe) == "enrouler",
		"le verbe invente doit etre resolu, recu '%s'" % String(colon.decision_en_cours.verbe))
	v.v(colon.proprietes.deformation_etat.has("pli_de_ruche"),
		"la source de deformation inventee doit tenir son registre, recu %s"
			% str(colon.proprietes.deformation_etat.keys()))

	# ET L'URGENCE INVENTEE renverse l'arbitrage invente, par le meme chemin.
	Banc.basculer_faim(colon, config, false)
	for i in range(120):
		temps += DELTA
		infos = Banc.avancer_tick(colon, monde, cibles, DELTA, temps, config,
			canaux, profils, deformations, config.catalogue_local)
	v.v(String(colon.decision_en_cours.cible_id) == String(config.cibles[0].id),
		"l'urgence inventee doit faire gagner la cible inventee la plus lointaine, recu '%s'"
			% String(colon.decision_en_cours.cible_id))
	v.v(float(infos.biais_urgence) > 0.0 and colon.proprietes.deformation_etat.has("soif_de_lumiere"),
		"par la MEME voie : une source de deformation, jamais un cas particulier")
