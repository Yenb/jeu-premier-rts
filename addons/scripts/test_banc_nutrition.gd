extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_nutrition.gd
#
# Verrouille le cablage de banc_nutrition.gd : trois reserves de nutriment a
# trois vitesses (depense.gd), repas qui remplissent CHACUN leur reserve
# (consommer.gd, cible nommee par le materiau), malnutrition qui monte sous
# cause synthetisee puis redescend seule (charge.gd), etat 'malnutri' pose et
# retire en miroir du marqueur (etat_duree.gd), vitesse modulee
# (etat_effectif.gd). Les cinq mecanismes du coeur restent INCHANGES -- ce
# fichier ne verrouille que le cablage.
#
# data/banc_nutrition.json, data/materiaux.json et data/etats.json sont lus
# SUR LE DISQUE, jamais recopies ici (meme discipline que
# test_banc_maladie.gd) : les cout_base, le seuil de charge et le facteur de
# vitesse restent reglables par Yael sans toucher a ce fichier.
#
# DEUX FAMILLES DE CAS, a ne pas confondre :
# - les cas de mecanique posent leurs propres reserves de depart pour isoler
#   UNE transition, et ne disent rien de la jouabilite du banc ;
# - _config_reelle_du_disque_degrade_puis_repare rejoue data/banc_nutrition.
#   json EN ENTIER, sans un seul chiffre local. Sans lui, tout ce fichier
#   resterait VERT alors que le banc lance a l'ecran ne poserait jamais
#   'malnutri' -- exactement le trou trouve sur banc_maladie.

const BancNutrition = preload("res://scripts/banc_nutrition.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DELTA_TICK := 0.1

var _config: Dictionary
var _materiaux: Dictionary
var _etats: Dictionary

func _init() -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_nutrition.json"))
	_materiaux = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	_etats = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))

	_les_trois_materiaux_ne_different_que_par_le_type_de_nutriment()
	_le_gras_cale_longtemps_le_sucre_redescend_vite()
	_chaque_repas_remplit_sa_propre_reserve()
	_la_malnutrition_monte_quand_le_colon_ne_mange_pas()
	_malnutri_pose_au_franchissement_et_vitesse_reduite()
	_la_malnutrition_redescend_quand_le_colon_remange()
	_malnutri_retire_quand_la_charge_redescend()
	_aucune_malnutrition_tant_que_la_somme_reste_au_dessus_du_seuil()
	_toggle_cyclique_passe_par_rien()
	_config_reelle_du_disque_degrade_puis_repare()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_nutrition.gd -- trois reserves de nutriment a trois vitesses " +
		"(depense.gd), repas qui remplit la reserve nommee par son materiau " +
		"(consommer.gd), malnutrition qui monte sous cause synthetisee et " +
		"redescend seule (charge.gd), 'malnutri' pose puis retire en miroir du " +
		"marqueur (etat_duree.gd) et vitesse modulee (etat_effectif.gd), sans " +
		"qu'aucun mecanisme du coeur ne soit touche")
	quit(0)

# ---- Outils de cas ----

# Config REELLE du disque, dont seules les reserves de depart sont
# remplacees -- cout_base/seuil/taux_decroissance/seuil_qualite restent ceux
# du disque, sans quoi ce fichier reverrouillerait la calibration que Yael
# doit pouvoir regler.
func _config_avec_reserves(depart: Dictionary) -> Dictionary:
	var config: Dictionary = _config.duplicate(true)
	for nom in depart:
		config.reserves[nom]["reserve"] = float(depart[nom])
	return config

func _colon_avec(depart: Dictionary) -> Array:
	var config := _config_avec_reserves(depart)
	return [BancNutrition.fabriquer_colon(config), config]

func _repas_par_id(repas: Array, id: String) -> Variant:
	for r in repas:
		if r.id == id:
			return r
	return null

func _reserve(colon: Dictionary, nom: String) -> float:
	return float(colon.proprietes.reserves.get(nom, {}).get("reserve", 0.0))

func _avancer_n(colon: Dictionary, servi: Variant, config: Dictionary, n: int) -> Dictionary:
	var cumul := {"pose": 0, "retire": 0}
	for i in n:
		var r := BancNutrition.avancer(colon, servi, config, _etats, DELTA_TICK)
		if r.pose:
			cumul.pose += 1
		if r.retire:
			cumul.retire += 1
	return cumul

# ---- Cas ----

# Le triplet de data/materiaux.json n'isole une variable QUE si les deux
# autres sont identiques (meme discipline que combustible_dense_demo/
# combustible_poreux_demo). Si un jour comestibilite ou
# valeur_nutritive_energie divergeaient, la difference observee entre les
# trois repas ne viendrait plus des cout_base et ce banc ne prouverait plus
# ce qu'il pretend.
func _les_trois_materiaux_ne_different_que_par_le_type_de_nutriment() -> void:
	var noms: Array = []
	for decl in _config.repas:
		noms.append(String(decl.materiau))
	verif.v(noms.size() == 3, "le banc doit servir exactement trois repas")

	var types_vus: Dictionary = {}
	var reference: Dictionary = _materiaux[noms[0]]
	for nom in noms:
		var fiche: Dictionary = _materiaux.get(nom, {})
		verif.v(fiche.has("type_nutriment"), "%s doit porter 'type_nutriment'" % nom)
		verif.v(float(fiche.get("comestibilite", -1.0)) == float(reference.comestibilite),
			"%s doit avoir la MEME comestibilite que les deux autres repas (seul type_nutriment differe)" % nom)
		verif.v(float(fiche.get("valeur_nutritive_energie", -1.0)) == float(reference.valeur_nutritive_energie),
			"%s doit avoir la MEME valeur_nutritive_energie que les deux autres repas" % nom)
		types_vus[String(fiche.get("type_nutriment", ""))] = true
	verif.v(types_vus.size() == 3, "les trois repas doivent viser trois reserves DIFFERENTES")

	for nom_reserve in types_vus:
		verif.v(_config.reserves.has(nom_reserve),
			"la reserve '%s' nommee par un materiau doit exister sur le colon" % nom_reserve)

# LE COEUR DU « profil de repas » : depense.gd boucle sur les trois reserves
# et applique a chacune SON cout_base, sans qu'aucune ne connaisse les
# autres. Les trois partent du MEME nombre pour que la seule difference
# observable soit la vitesse de descente.
func _le_gras_cale_longtemps_le_sucre_redescend_vite() -> void:
	var paire := _colon_avec({"gras": 40.0, "proteine": 40.0, "sucre": 40.0})
	var colon: Dictionary = paire[0]
	var config: Dictionary = paire[1]
	_avancer_n(colon, null, config, 100)  # 10 s, personne ne mange

	var gras := _reserve(colon, "gras")
	var proteine := _reserve(colon, "proteine")
	var sucre := _reserve(colon, "sucre")

	verif.v(gras > proteine, "apres 10s sans manger, le gras doit avoir moins descendu que la proteine")
	verif.v(proteine > sucre, "apres 10s sans manger, la proteine doit avoir moins descendu que le sucre")

	# Chiffres EXACTS, jamais recopies : cout_base * duree, lus sur le disque.
	# depense.gd est lineaire (reserve -= (cout_base + surcout_action) * delta).
	for nom in ["gras", "proteine", "sucre"]:
		var attendu: float = 40.0 - float(_config.reserves[nom].cout_base) * 10.0
		verif.v(abs(_reserve(colon, nom) - attendu) < 0.01,
			"la reserve '%s' doit valoir exactement 40.0 - cout_base*10s = %.2f (trouve %.2f)" %
			[nom, attendu, _reserve(colon, nom)])

	verif.v(_reserve(colon, "sucre") >= 0.0, "aucune reserve ne descend sous 0.0 (borne basse de depense.gd)")

# consommer.gd ne connait aucun nom de propriete : c'est le cablage qui
# resout la reserve receptrice depuis type_nutriment. Ce cas prouve que le
# repas gras ne remplit QUE 'gras', jamais les deux autres.
func _chaque_repas_remplit_sa_propre_reserve() -> void:
	var repas := BancNutrition.fabriquer_repas(_config, _materiaux)
	verif.v(repas.size() == 3, "fabriquer_repas doit construire les trois repas du disque")

	for decl in _config.repas:
		var cible: String = String(_materiaux[String(decl.materiau)].type_nutriment)
		var paire := _colon_avec({"gras": 40.0, "proteine": 40.0, "sucre": 40.0})
		var colon: Dictionary = paire[0]
		var config: Dictionary = paire[1]
		var servi: Variant = _repas_par_id(repas, String(decl.id))
		var contenu_avant: float = float(servi.proprietes.reserves[String(_config.nom_reserve_contenu)].reserve)

		_avancer_n(colon, servi, config, 50)  # 5 s de repas

		var contenu_apres: float = float(servi.proprietes.reserves[String(_config.nom_reserve_contenu)].reserve)
		verif.v(contenu_apres < contenu_avant, "%s doit avoir perdu du contenu (transfert DESTRUCTIF)" % decl.id)

		var attendu_sans_repas: float = 40.0 - float(_config.reserves[cible].cout_base) * 5.0
		verif.v(_reserve(colon, cible) > attendu_sans_repas + 1.0,
			"%s doit avoir fait MONTER la reserve '%s' bien au-dessus de ce qu'elle vaudrait sans repas" % [decl.id, cible])

		for nom in ["gras", "proteine", "sucre"]:
			if nom == cible:
				continue
			var attendu: float = 40.0 - float(_config.reserves[nom].cout_base) * 5.0
			verif.v(abs(_reserve(colon, nom) - attendu) < 0.01,
				"%s ne doit RIEN changer a la reserve '%s' (attendu %.2f, trouve %.2f)" %
				[decl.id, nom, attendu, _reserve(colon, nom)])

		# Conservation : ce que le colon gagne est EXACTEMENT ce que le repas
		# perd (consommer.gd credite la quantite REELLEMENT retiree).
		var gagne: float = _reserve(colon, cible) - attendu_sans_repas
		verif.v(abs(gagne - (contenu_avant - contenu_apres)) < 0.01,
			"%s : le gain du colon doit egaler la perte du repas, a la dependance pres" % decl.id)

# charge.gd ne lit jamais une reserve : la cause est SYNTHETISEE par le
# cablage des que la somme des trois reserves passe sous seuil_qualite, a
# distance ZERO du colon (portee_charge 0.0, Portee.en_portee compare
# distance <= portee).
func _la_malnutrition_monte_quand_le_colon_ne_mange_pas() -> void:
	var seuil_qualite: float = float(_config.seuil_qualite)
	var paire := _colon_avec({"gras": 2.0, "proteine": 2.0, "sucre": 2.0})
	var colon: Dictionary = paire[0]
	var config: Dictionary = paire[1]

	verif.v(BancNutrition.somme_nutriments(colon, BancNutrition.noms_reserves(config)) < seuil_qualite,
		"le colon de ce cas doit demarrer SOUS seuil_qualite")
	verif.v(BancNutrition.charge_malnutrition(colon, config) == 0.0, "la charge doit demarrer a 0.0")

	var causes := BancNutrition.causes_de_malnutrition(colon, 0.0, config)
	verif.v(causes.size() == 1, "sous seuil_qualite, le cablage doit synthetiser exactement UNE cause")
	verif.v(causes[0].position == colon.position, "la cause doit etre a la position du colon lui-meme (distance 0)")
	verif.v(float(causes[0].poids) == float(_config.accumulation_malnutrition_par_s),
		"le poids de la cause doit venir de la donnee, jamais d'un nombre en dur")
	verif.v(BancNutrition.causes_de_malnutrition(colon, seuil_qualite, config).is_empty(),
		"a la somme EXACTEMENT egale au seuil, aucune cause -- la degradation demande de passer SOUS")

	_avancer_n(colon, null, config, 10)  # 1 s
	var apres_1s := BancNutrition.charge_malnutrition(colon, config)
	verif.v(apres_1s > 0.0, "la charge de malnutrition doit monter quand le colon ne mange pas")
	verif.v(abs(apres_1s - float(_config.accumulation_malnutrition_par_s)) < 0.01,
		"apres 1s la charge doit valoir exactement accumulation_malnutrition_par_s (%.2f, trouve %.2f)" %
		[float(_config.accumulation_malnutrition_par_s), apres_1s])

	_avancer_n(colon, null, config, 10)
	verif.v(BancNutrition.charge_malnutrition(colon, config) > apres_1s,
		"la charge doit continuer de monter tant que la cause persiste")

func _malnutri_pose_au_franchissement_et_vitesse_reduite() -> void:
	var paire := _colon_avec({"gras": 2.0, "proteine": 2.0, "sucre": 2.0})
	var colon: Dictionary = paire[0]
	var config: Dictionary = paire[1]
	var seuil: float = float(_config.canal_malnutrition.seuil)
	var accumulation: float = float(_config.accumulation_malnutrition_par_s)
	var vitesse_base: float = float(_config.colon.vitesse)

	verif.v(not BancNutrition.est_malnutri(colon, config), "le colon ne demarre jamais malnutri")
	verif.v(is_equal_approx(EtatEffectif.valeur(colon, "vitesse", _etats), vitesse_base),
		"avant 'malnutri', la vitesse effective doit etre EXACTEMENT la vitesse de base")

	# Ticks calcules depuis le seuil et l'accumulation REELS, jamais un
	# nombre en dur -- ce cas survit a un reglage de calibration. Un tick de
	# marge : la charge est une somme de flottants, s'arreter pile sur le
	# seuil ferait dependre le cas de l'arrondi, jamais de la loi.
	var ticks_juste_avant := int(seuil / accumulation / DELTA_TICK) - 1
	var r := _avancer_n(colon, null, config, ticks_juste_avant)
	verif.v(not BancNutrition.est_malnutri(colon, config),
		"'malnutri' ne doit PAS etre pose tant que la charge n'a pas DEPASSE le seuil")
	verif.v(r.pose == 0, "aucune pose ne doit avoir ete signalee avant le franchissement")

	r = _avancer_n(colon, null, config, 5)
	verif.v(BancNutrition.est_malnutri(colon, config), "'malnutri' doit etre pose une fois le seuil depasse")
	verif.v(r.pose == 1, "la transition doit etre signalee EXACTEMENT une fois, jamais a chaque tick")

	verif.v(colon.proprietes.get(String(_config.nom_marqueur_malnutrition), false),
		"charge.gd doit avoir pose son marqueur sur proprietes")
	verif.v(not colon.proprietes.get("etats_intensite", {}).has(String(_config.etat_malnutri)),
		"'malnutri' ne porte pas de 'duree' : il ne doit JAMAIS entrer dans etats_intensite")

	var facteur: float = float(_etats[String(_config.etat_malnutri)].effets[0].facteur)
	verif.v(is_equal_approx(EtatEffectif.valeur(colon, "vitesse", _etats), vitesse_base * facteur),
		"une fois malnutri, la vitesse effective doit etre reduite exactement par le facteur de data/etats.json")

	# Reposer chaque tick ne doit jamais empiler le nom ni relancer une pose.
	_avancer_n(colon, null, config, 30)
	var occurrences := 0
	for nom in colon.proprietes.etats_actifs:
		if String(nom) == String(_config.etat_malnutri):
			occurrences += 1
	verif.v(occurrences == 1, "le repose-chaque-tick ne doit jamais empiler 'malnutri' dans etats_actifs")

func _la_malnutrition_redescend_quand_le_colon_remange() -> void:
	var paire := _colon_avec({"gras": 2.0, "proteine": 2.0, "sucre": 2.0})
	var colon: Dictionary = paire[0]
	var config: Dictionary = paire[1]
	var repas := BancNutrition.fabriquer_repas(_config, _materiaux)

	_avancer_n(colon, null, config, 60)  # 6 s de jeune
	var charge_haute := BancNutrition.charge_malnutrition(colon, config)
	verif.v(charge_haute > 0.0, "la charge doit avoir monte pendant le jeune")

	# On remange assez pour repasser AU-DESSUS de seuil_qualite.
	_avancer_n(colon, repas[0], config, 150)
	var somme := BancNutrition.somme_nutriments(colon, BancNutrition.noms_reserves(config))
	verif.v(somme >= float(_config.seuil_qualite),
		"apres avoir remange, la somme des nutriments doit etre repassee au-dessus de seuil_qualite (trouve %.2f)" % somme)
	verif.v(BancNutrition.charge_malnutrition(colon, config) < charge_haute,
		"la charge de malnutrition doit REDESCENDRE quand le colon remange -- c'est la reversibilite de charge.gd")

func _malnutri_retire_quand_la_charge_redescend() -> void:
	var paire := _colon_avec({"gras": 2.0, "proteine": 2.0, "sucre": 2.0})
	var colon: Dictionary = paire[0]
	var config: Dictionary = paire[1]
	var repas := BancNutrition.fabriquer_repas(_config, _materiaux)
	var vitesse_base: float = float(_config.colon.vitesse)

	_avancer_n(colon, null, config, 100)
	verif.v(BancNutrition.est_malnutri(colon, config), "prealable : le colon doit etre malnutri avant de remanger")

	var r := _avancer_n(colon, repas[0], config, 400)
	verif.v(not BancNutrition.est_malnutri(colon, config),
		"'malnutri' doit etre RETIRE une fois la charge repassee sous le seuil")
	verif.v(r.retire == 1, "le retrait doit etre signale EXACTEMENT une fois")
	verif.v(not colon.proprietes.has(String(_config.nom_marqueur_malnutrition)),
		"charge.gd doit avoir retire son marqueur de proprietes au franchissement descendant")
	verif.v(is_equal_approx(EtatEffectif.valeur(colon, "vitesse", _etats), vitesse_base),
		"la vitesse effective doit revenir EXACTEMENT a la base une fois 'malnutri' retire")

func _aucune_malnutrition_tant_que_la_somme_reste_au_dessus_du_seuil() -> void:
	var paire := _colon_avec({"gras": 500.0, "proteine": 500.0, "sucre": 500.0})
	var colon: Dictionary = paire[0]
	var config: Dictionary = paire[1]
	var r := _avancer_n(colon, null, config, 600)  # 60 s

	verif.v(BancNutrition.charge_malnutrition(colon, config) == 0.0,
		"un colon dont la somme reste au-dessus de seuil_qualite ne doit accumuler AUCUNE malnutrition, meme en 60s")
	verif.v(not BancNutrition.est_malnutri(colon, config), "et ne doit jamais porter 'malnutri'")
	verif.v(r.pose == 0 and r.retire == 0, "aucune transition ne doit etre signalee")

func _toggle_cyclique_passe_par_rien() -> void:
	verif.v(BancNutrition.repas_suivant(0, 3) == 1, "le toggle passe du premier au deuxieme repas")
	verif.v(BancNutrition.repas_suivant(2, 3) == 3, "apres le dernier repas, le toggle passe a RIEN (index == nb_repas)")
	verif.v(BancNutrition.repas_suivant(3, 3) == 0, "apres RIEN, le toggle revient au premier repas")

# LE SEUL CAS QUI REJOUE data/banc_nutrition.json EN ENTIER -- reserves de
# depart reelles, cout_base reels, seuil/accumulation/taux_decroissance
# reels. Tous les autres cas posent leurs propres reserves de depart : ils
# resteraient VERTS meme si la calibration du disque ne franchissait jamais
# rien a l'ecran (trou reel trouve sur banc_maladie, voir son ETAT.md).
#
# Deux assertions seulement, les plus larges qui gardent le contrat : la
# calibration reste libre de bouger tant que le banc SE DEGRADE tout seul
# puis SE REPARE quand on le nourrit. Ne jamais y coder un instant precis --
# ce serait reverrouiller la calibration que Yael doit pouvoir regler.
func _config_reelle_du_disque_degrade_puis_repare() -> void:
	var colon := BancNutrition.fabriquer_colon(_config)
	var repas := BancNutrition.fabriquer_repas(_config, _materiaux)

	var poses := 0
	for i in 400:  # 40 s sans rien servir, exactement le banc lance sans clic
		if BancNutrition.avancer(colon, null, _config, _etats, DELTA_TICK).pose:
			poses += 1
	verif.v(poses == 1,
		"la config reelle du disque doit poser 'malnutri' toute seule en 40s, sans un seul clic -- sinon le banc lance a l'ecran ne montre rien")

	var retires := 0
	for i in 600:  # 60 s de repas gras
		if BancNutrition.avancer(colon, repas[0], _config, _etats, DELTA_TICK).retire:
			retires += 1
	verif.v(retires == 1,
		"la config reelle du disque doit RETIRER 'malnutri' en 60s de repas -- sinon la reparation n'est jamais observable a l'ecran")
