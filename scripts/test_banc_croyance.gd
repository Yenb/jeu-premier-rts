extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_croyance.gd
#
# Verrouille le CABLAGE de banc_croyance.gd : la croyance s'intercale entre
# perception.gd et les couches de saillance, les quatre couches decident sur
# la copie et jamais sur le monde, un colon agit sur une information fausse
# sans aucune branche speciale, le dogme refuse la correction, et la
# credibilite d'une transmission est la force d'un lien personnel.
#
# Les mecanismes composes (perception.gd, croyance.gd, proximite.gd,
# dominance.gd, agir.gd, lien_personnel.gd, monde.gd) restent INCHANGES : ce
# fichier ne verrouille que le cablage. La genericite de croyance.gd est
# prouvee ailleurs, hors domaine (scripts/test_croyance.gd).
#
# data/banc_croyance.json, data/croyances.json, data/canaux.json,
# data/profils_saillance.json, data/types_choses.json et
# data/liens_personnels.json sont lus SUR LE DISQUE, jamais recopies ici
# (meme discipline que test_banc_menace_combat.gd) : la calibration reste
# reglable par Yael sans toucher a ce fichier.
#
# DEUX FAMILLES DE CAS, a ne pas confondre :
# - les cas de mecanique isolent UNE transition et ne disent rien de la
#   jouabilite du banc ;
# - _config_reelle_du_disque_joue_le_scenario_entier rejoue
#   data/banc_croyance.json EN ENTIER, sans un seul chiffre local. Sans lui,
#   tout ce fichier resterait VERT alors que le banc lance a l'ecran ne
#   montrerait jamais ni dogme ni transmission -- exactement le trou trouve
#   sur banc_maladie.

const Banc = preload("res://scripts/banc_croyance.gd")
const Croyance = preload("res://scripts/croyance.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA_TICK := 0.1

var verif := Verif.new()

var _config: Dictionary
var _croyances: Dictionary
var _canaux: Dictionary
var _profils: Dictionary
var _actions: Dictionary
var _liens: Dictionary

func _init() -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_croyance.json"))
	_croyances = JSON.parse_string(FileAccess.get_file_as_string("res://data/croyances.json"))
	_canaux = JSON.parse_string(FileAccess.get_file_as_string("res://data/canaux.json"))
	_profils = JSON.parse_string(FileAccess.get_file_as_string("res://data/profils_saillance.json"))
	_actions = JSON.parse_string(FileAccess.get_file_as_string("res://data/types_choses.json"))
	_liens = JSON.parse_string(FileAccess.get_file_as_string("res://data/liens_personnels.json"))

	_au_depart_personne_ne_croit_rien()
	_une_observation_forme_les_croyances_de_ce_qui_est_percu()
	_la_pierre_ne_produit_aucune_croyance()
	_le_lien_personnel_vers_l_emetteur_est_pose_a_la_construction()
	_la_cadence_d_observation_seule_separe_le_dogmatique_des_autres()
	_le_fruit_toxique_perd_la_cle_et_la_croyance_perimee_survit()
	_le_verbe_reste_manger_sur_une_croyance_perimee()
	_la_decision_suit_la_copie_pas_le_monde()
	_les_id_survivent_a_la_chaine_entiere()
	_la_verification_au_contact_corrige_l_informe()
	_la_transmission_corrige_qui_a_un_lien()
	_le_dogmatique_refuse_la_transmission()
	_l_isole_n_est_meme_pas_ecoute()
	_le_feu_eloigne_rend_la_croyance_perimee_puis_oubliee()
	_ecart_croyance_rend_les_trois_etats()
	_config_reelle_du_disque_joue_le_scenario_entier()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_croyance.gd -- la croyance s'intercale entre perception.gd et " +
		"les couches de saillance, les quatre couches decident sur la copie crue et " +
		"jamais sur le monde, un colon agit sur une croyance perimee sans aucune " +
		"branche speciale, la verification au contact corrige, le dogme refuse et la " +
		"credibilite d'une transmission est la force d'un lien personnel -- aucun " +
		"mecanisme du coeur touche")
	quit(0)

# ---- Outils de cas ----

func _scene() -> Dictionary:
	var objets := Banc.fabriquer_objets(_config)
	var colons := Banc.fabriquer_colons(_config)
	var monde := Monde.new()
	for chose in objets:
		monde.ajouter(chose, "objet", chose.position)
	for chose in colons:
		monde.ajouter(chose, "colon", chose.position)
	return {"objets": objets, "colons": colons, "monde": monde}

# Simule "duree" secondes a DELTA_TICK. Rend le dernier resultat d'avancer()
# plus le temps atteint, pour enchainer plusieurs phases sur la meme scene.
func _simuler(scene: Dictionary, duree: float, temps_depart := 0.0) -> Dictionary:
	var temps := temps_depart
	var resultat: Dictionary = {}
	var pas := int(round(duree / DELTA_TICK))
	for i in range(pas):
		temps += DELTA_TICK
		resultat = Banc.avancer(
			scene.colons, scene.monde, _config, _canaux, _croyances,
			_profils, _actions, DELTA_TICK, temps,
		)
	return {"resultat": resultat, "temps": temps}

func _colon(scene: Dictionary, id: String) -> Dictionary:
	for colon in scene.colons:
		if String(colon.id) == id:
			return colon
	return {}

func _etat(resultat: Dictionary, id: String) -> Dictionary:
	for etat in resultat.get("colons", []):
		if String(etat.id) == id:
			return etat
	return {}

# ---- Cas ----

func _au_depart_personne_ne_croit_rien() -> void:
	var scene := _scene()
	var vide := true
	for colon in scene.colons:
		if not colon.proprietes.croyances.is_empty():
			vide = false
	verif.v(vide, "aucune croyance ne doit etre posee en dur a la construction -- " +
		"elles naissent toutes de la perception vecue")

func _une_observation_forme_les_croyances_de_ce_qui_est_percu() -> void:
	var scene := _scene()
	_simuler(scene, DELTA_TICK)
	var ouvert := _colon(scene, "colon_ouvert")
	verif.v(Banc.valeur_crue(ouvert, "fruit", "comestible") == true,
		"un colon qui percoit le fruit sain doit croire qu'il est comestible")
	verif.v(Banc.valeur_crue(ouvert, "feu", "dangereux") == true,
		"un colon qui percoit le feu doit croire qu'il est dangereux")
	verif.v(is_equal_approx(Banc.certitude_crue(ouvert, "fruit", "comestible"),
		float(_croyances.certitude_initiale) - float(_croyances.taux_decroissance) * DELTA_TICK),
		"une croyance tout juste formee porte certitude_initiale, moins l'oubli du pas")

func _la_pierre_ne_produit_aucune_croyance() -> void:
	var scene := _scene()
	_simuler(scene, 1.0)
	for colon in scene.colons:
		verif.v(not colon.proprietes.croyances.has("pierre"),
			"la pierre ne porte aucune propriete observable : elle est PERCUE " +
			"(sa position est connue) et ne produit jamais de croyance")

func _le_lien_personnel_vers_l_emetteur_est_pose_a_la_construction() -> void:
	var scene := _scene()
	var emetteur := String(_config.emetteur)
	var ouvert := _colon(scene, "colon_ouvert")
	var isole := _colon(scene, "colon_isole")
	verif.v(ouvert.proprietes.liens_personnels.get(emetteur, 0.0) > 0.0,
		"le colon ouvert doit porter un lien personnel vers l'emetteur")
	verif.v(not isole.proprietes.liens_personnels.has(emetteur),
		"le colon isole ne doit porter AUCUN lien vers l'emetteur -- c'est ce qui " +
		"le rend sourd, jamais un drapeau declare")

# CE QUI SEPARE LES COLONS N'EST QU'UN NOMBRE (docs/design.md, « Les archetypes
# n'existent pas ») : la seule difference entre le dogmatique et l'ouvert est
# cadence_observation. Le test le VERIFIE plutot que de le supposer.
func _la_cadence_d_observation_seule_separe_le_dogmatique_des_autres() -> void:
	var scene := _scene()
	var dogmatique := _colon(scene, "colon_dogmatique")
	var ouvert := _colon(scene, "colon_ouvert")
	verif.v(dogmatique.proprietes.forme == ouvert.proprietes.forme
		and dogmatique.proprietes.poids_verbes == ouvert.proprietes.poids_verbes
		and dogmatique.proprietes.canaux_config == ouvert.proprietes.canaux_config,
		"le dogmatique et l'ouvert doivent avoir EXACTEMENT le meme corps")
	_simuler(scene, 5.0)
	var resistance: float = float(_croyances.resistance_par_certitude)
	verif.v(Banc.certitude_crue(dogmatique, "fruit", "comestible") >= resistance,
		"celui qui regarde souvent franchit resistance_par_certitude -- le dogme " +
		"nait de l'accumulation d'observations, jamais d'un etat pose")
	verif.v(Banc.certitude_crue(ouvert, "fruit", "comestible") < resistance,
		"celui qui regarde rarement reste sous la resistance, donc corrigible")

func _le_fruit_toxique_perd_la_cle_et_la_croyance_perimee_survit() -> void:
	var scene := _scene()
	_simuler(scene, 1.0)
	Banc.basculer_fruit(scene.objets, _config, false)
	var fruit := Banc.objet_par_id(scene.objets, "fruit")
	verif.v(not fruit.proprietes.has("comestible"),
		"le fruit toxique doit PERDRE la cle 'comestible', jamais la mettre a false " +
		"-- observer() n'itere que les proprietes presentes")
	var r := _simuler(scene, 2.0, 1.0)
	var ouvert := _colon(scene, "colon_ouvert")
	verif.v(Banc.valeur_crue(ouvert, "fruit", "comestible") == true,
		"la croyance perimee doit SURVIVRE : un coup d'oeil ne revele pas qu'un " +
		"fruit est devenu toxique")
	verif.v(String(_etat(r.resultat, "colon_ouvert").ecart) == "faux",
		"un colon dont une croyance contredit le monde doit etre dans le FAUX")

func _le_verbe_reste_manger_sur_une_croyance_perimee() -> void:
	var scene := _scene()
	_simuler(scene, 1.0)
	Banc.basculer_fruit(scene.objets, _config, false)
	var r := _simuler(scene, 1.0, 1.0)
	var etat := _etat(r.resultat, "colon_ouvert")
	verif.v(String(etat.verbe) == "manger" and String(etat.cible_id) == "fruit",
		"agir.gd doit resoudre EXACTEMENT le meme verbe sur une croyance fausse -- " +
		"la fausse information ne coute pas une ligne de mecanisme")

# La preuve que les couches lisent la COPIE et non le monde : on change la
# realite SANS jamais laisser le colon la reobserver (sa cadence est longue),
# et la decision ne bouge pas d'un iota.
func _la_decision_suit_la_copie_pas_le_monde() -> void:
	var scene := _scene()
	_simuler(scene, 1.0)
	var avant := _etat(_simuler(scene, 1.0, 1.0).resultat, "colon_ouvert")
	Banc.basculer_fruit(scene.objets, _config, false)
	var apres := _etat(_simuler(scene, 1.0, 2.0).resultat, "colon_ouvert")
	verif.v(String(avant.verbe) == String(apres.verbe)
		and String(avant.cible_id) == String(apres.cible_id),
		"la decision doit rester identique quand le monde change sans etre reobserve")

func _les_id_survivent_a_la_chaine_entiere() -> void:
	var scene := _scene()
	var r := _simuler(scene, 1.0)
	var etat := _etat(r.resultat, "colon_dogmatique")
	verif.v(String(etat.cible_id) == "fruit",
		"l'id doit traverser Croyance.filtrer -- sans lui l'inertie, l'engagement " +
		"et les liens personnels casseraient tous en silence")
	verif.v(scene.monde.par_id(String(etat.cible_id)) != null,
		"l'id rendu par la decision doit designer une chose REELLE du monde")

func _la_verification_au_contact_corrige_l_informe() -> void:
	var scene := _scene()
	_simuler(scene, 1.0)
	Banc.basculer_fruit(scene.objets, _config, false)
	var r := _simuler(scene, 2.0, 1.0)
	var informe := _colon(scene, "colon_informe")
	verif.v(Banc.valeur_crue(informe, "fruit", "comestible") == false,
		"le colon au contact doit corriger sa croyance par l'experience directe")
	verif.v(Banc.valeur_crue(informe, "fruit", String(_config.propriete_toxique)) == true,
		"le contact revele ce que l'oeil ne capte pas -- 'toxique' n'est pas " +
		"observable, il est verifiable")
	# La certitude est ECRASEE a gain_par_echec x 1.0 par la derniere verification,
	# puis grignotee par l'oubli jusqu'a la verification suivante -- elle vit donc
	# dans une bande dont la LARGEUR est exactement un cycle d'oubli.
	var plafond_contact: float = float(_croyances.gain_par_echec)
	var creux_contact: float = plafond_contact \
		- float(_croyances.taux_decroissance) * float(_config.colons.colon_informe.cadence_verification)
	var certitude_informe := Banc.certitude_crue(informe, "fruit", "comestible")
	verif.v(certitude_informe <= plafond_contact and certitude_informe >= creux_contact,
		"une correction a credibilite 1.0 ecrase la certitude a gain_par_echec ; " +
		"entre deux contacts, l'oubli ne peut la faire descendre que d'un cycle")
	verif.v(plafond_contact < float(_croyances.resistance_par_certitude),
		"gain_par_echec doit rester SOUS resistance_par_certitude : c'est ce qui " +
		"garde l'experience directe eternellement corrigible")
	var etat := _etat(r.resultat, "colon_informe")
	verif.v(String(etat.ecart) == "correct",
		"un colon dont toutes les croyances collent au monde percu doit etre CORRECT")
	verif.v(String(etat.verbe) == "",
		"une fois corrige, aucune propriete crue ne resout de verbe : il cesse de " +
		"vouloir manger le fruit")

func _la_transmission_corrige_qui_a_un_lien() -> void:
	var scene := _scene()
	_simuler(scene, 1.0)
	Banc.basculer_fruit(scene.objets, _config, false)
	_simuler(scene, 2.0, 1.0)
	var evenements := Banc.transmettre(scene.colons, _config, _croyances, _liens)
	var ouvert := _colon(scene, "colon_ouvert")
	verif.v(Banc.valeur_crue(ouvert, "fruit", "comestible") == false,
		"un colon lie a l'emetteur doit recevoir la croyance corrigee")
	var recu := false
	for ev in evenements:
		if String(ev.colon) == "colon_ouvert" and String(ev.genre) == "recoit" \
			and String(ev.propriete) == "comestible":
			recu = true
			verif.v(is_equal_approx(float(ev.credibilite),
				float(ouvert.proprietes.liens_personnels[String(_config.emetteur)])),
				"la credibilite transmise doit etre EXACTEMENT la force du lien personnel")
			verif.v(is_equal_approx(float(ev.certitude),
				float(_croyances.gain_par_echec) * float(ev.credibilite)),
				"la certitude apres transmission doit valoir gain_par_echec x credibilite " +
				"-- une parole moins credible laisse une croyance moins assuree")
	verif.v(recu, "la transmission acceptee doit produire un evenement 'recoit'")

func _le_dogmatique_refuse_la_transmission() -> void:
	var scene := _scene()
	_simuler(scene, 5.0)
	Banc.basculer_fruit(scene.objets, _config, false)
	_simuler(scene, 2.0, 5.0)
	var dogmatique := _colon(scene, "colon_dogmatique")
	var certitude_avant := Banc.certitude_crue(dogmatique, "fruit", "comestible")
	var evenements := Banc.transmettre(scene.colons, _config, _croyances, _liens)
	verif.v(Banc.valeur_crue(dogmatique, "fruit", "comestible") == true,
		"au-dela de resistance_par_certitude la correction est IGNOREE -- le dogme resiste")
	verif.v(is_equal_approx(Banc.certitude_crue(dogmatique, "fruit", "comestible"), certitude_avant),
		"une correction refusee ne touche NI la valeur NI la certitude")
	var trace_dogme := false
	for ev in evenements:
		if String(ev.colon) == "colon_dogmatique" and String(ev.genre) == "dogme" \
			and String(ev.propriete) == "comestible":
			trace_dogme = true
	verif.v(trace_dogme, "le refus par dogme doit etre trace, jamais silencieux")

func _l_isole_n_est_meme_pas_ecoute() -> void:
	var scene := _scene()
	_simuler(scene, 1.0)
	Banc.basculer_fruit(scene.objets, _config, false)
	_simuler(scene, 2.0, 1.0)
	var isole := _colon(scene, "colon_isole")
	var evenements := Banc.transmettre(scene.colons, _config, _croyances, _liens)
	verif.v(Banc.valeur_crue(isole, "fruit", "comestible") == true,
		"sans lien personnel, la credibilite tombe sous seuil_bornes_transmission " +
		"et le cablage n'appelle meme pas corriger")
	var sourd := false
	var autre := false
	for ev in evenements:
		if String(ev.colon) == "colon_isole":
			if String(ev.genre) == "sourd":
				sourd = true
			else:
				autre = true
	verif.v(sourd, "le refus par credibilite doit etre trace comme 'sourd'")
	verif.v(not autre, "un colon sous le seuil ne doit produire AUCUN autre evenement " +
		"-- le cablage renonce avant d'appeler le mecanisme")

func _le_feu_eloigne_rend_la_croyance_perimee_puis_oubliee() -> void:
	var scene := _scene()
	_simuler(scene, 1.0)
	Banc.basculer_feu(scene.objets, _config, false)
	var r := _simuler(scene, 2.0, 1.0)
	var isole := _colon(scene, "colon_isole")
	verif.v(Banc.valeur_crue(isole, "feu", "dangereux") == true,
		"une croyance sur une chose hors de portee doit PERSISTER un moment")
	verif.v(String(_etat(r.resultat, "colon_isole").ecart) == "perime",
		"une croyance juste mais plus verifiee doit rendre l'ecart PERIME, jamais FAUX")
	var attente: float = (float(_croyances.certitude_initiale) - float(_croyances.plancher_suppression)) \
		/ float(_croyances.taux_decroissance)
	_simuler(scene, attente + 2.0, 3.0)
	verif.v(not isole.proprietes.croyances.has("feu"),
		"passe le plancher de suppression, la croyance doit disparaitre -- l'oubli " +
		"retire l'entree, il ne la laisse jamais a une valeur residuelle")

func _ecart_croyance_rend_les_trois_etats() -> void:
	var scene := _scene()
	var r := _simuler(scene, 1.0)
	verif.v(String(_etat(r.resultat, "colon_ouvert").ecart) == "correct",
		"tout percu et tout juste : CORRECT")
	Banc.basculer_feu(scene.objets, _config, false)
	var r2 := _simuler(scene, 1.0, 1.0)
	verif.v(String(_etat(r2.resultat, "colon_ouvert").ecart) == "perime",
		"une chose crue mais plus percue : PERIME")
	Banc.basculer_fruit(scene.objets, _config, false)
	var r3 := _simuler(scene, 1.0, 2.0)
	verif.v(String(_etat(r3.resultat, "colon_ouvert").ecart) == "faux",
		"une croyance qui contredit le monde : FAUX, et il l'emporte sur PERIME")

# LE REJEU COMPLET. Aucun chiffre local : la scene entiere sort de
# data/banc_croyance.json et de data/croyances.json, exactement comme le banc
# lance a l'ecran.
func _config_reelle_du_disque_joue_le_scenario_entier() -> void:
	var scene := _scene()
	# Phase 1 -- tout le monde observe, tout le monde a raison.
	var r1 := _simuler(scene, 5.0)
	for id in ["colon_informe", "colon_ouvert", "colon_dogmatique", "colon_isole"]:
		verif.v(String(_etat(r1.resultat, id).ecart) == "correct",
			"phase 1 : %s doit croire juste tant que le monde ne change pas" % id)
		verif.v(String(_etat(r1.resultat, id).verbe) == "manger",
			"phase 1 : %s doit resoudre 'manger' sur le fruit sain" % id)
	# Phase 2 -- le fruit devient toxique. Seul celui qui TOUCHE s'en apercoit.
	Banc.basculer_fruit(scene.objets, _config, false)
	var r2 := _simuler(scene, 3.0, 5.0)
	verif.v(String(_etat(r2.resultat, "colon_informe").ecart) == "correct",
		"phase 2 : le colon au contact corrige par l'experience directe")
	for id in ["colon_ouvert", "colon_dogmatique", "colon_isole"]:
		verif.v(String(_etat(r2.resultat, id).ecart) == "faux",
			"phase 2 : %s continue de croire le fruit comestible" % id)
		verif.v(String(_etat(r2.resultat, id).verbe) == "manger",
			"phase 2 : %s decide de le manger malgre tout" % id)
	# Phase 3 -- la transmission separe les trois.
	Banc.transmettre(scene.colons, _config, _croyances, _liens)
	var r3 := _simuler(scene, 1.0, 8.0)
	verif.v(String(_etat(r3.resultat, "colon_ouvert").ecart) == "correct",
		"phase 3 : celui qui a un lien et pas de dogme est corrige par la parole d'un autre")
	verif.v(String(_etat(r3.resultat, "colon_dogmatique").ecart) == "faux",
		"phase 3 : le dogmatique ecoute et refuse quand meme")
	verif.v(String(_etat(r3.resultat, "colon_isole").ecart) == "faux",
		"phase 3 : l'isole n'a meme pas ete ecoute")
	verif.v(String(_etat(r3.resultat, "colon_ouvert").verbe) == "",
		"phase 3 : le colon corrige cesse de vouloir manger le fruit")
	verif.v(String(_etat(r3.resultat, "colon_isole").verbe) == "manger",
		"phase 3 : l'isole, lui, va toujours le manger")
