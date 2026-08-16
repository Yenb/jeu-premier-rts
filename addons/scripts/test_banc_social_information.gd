extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_social_information.gd
#
# Verrouille le CABLAGE de banc_social_information.gd : une reputation naît de
# ce qu'un temoin a VU, circule par Croyance.corriger a la credibilite d'un lien
# personnel, s'arrete net a la portee, et tombe PAR SAISON ; un novice imite le
# maitre competent qu'il percoit a portee, sans que le maitre perde rien.
#
# Les mecanismes composes (perception.gd, croyance.gd, lien_personnel.gd,
# epigenetique.gd, portee.gd, monde.gd) restent INCHANGES : ce fichier ne
# verrouille que le cablage, et le VERIFIE (voir
# _aucun_mecanisme_du_coeur_ne_nomme_ce_banc). Leur genericite est prouvee
# ailleurs, hors domaine, par leurs propres tests.
#
# data/banc_social_information.json, data/croyances.json, data/canaux.json,
# data/liens_personnels.json et data/epigenetique.json sont lus SUR LE DISQUE,
# jamais recopies ici (meme discipline que test_banc_croyance.gd/
# test_banc_marche_competence.gd) : la calibration reste reglable par Yael sans
# toucher a ce fichier, et les contraintes de cadence sont verifiees contre les
# nombres REELS du catalogue partage.
#
# TROIS FAMILLES DE CAS, a ne pas confondre :
# - les cas de MECANIQUE isolent une transition et ne disent rien de la
#   jouabilite du banc ;
# - _un_domaine_entierement_invente_traverse_le_meme_code fait passer le MEME
#   code par un vocabulaire sans aucun rapport avec Orion -- c'est ce qui prouve
#   qu'aucun nom de contenu n'est en dur dans le cablage ;
# - _config_reelle_du_disque_joue_le_scenario_entier rejoue
#   data/banc_social_information.json EN ENTIER, sans un seul chiffre local.
#   Sans lui, tout ce fichier resterait VERT alors que le banc lance a l'ecran
#   ne montrerait ni propagation ni imitation.

const Banc = preload("res://scripts/banc_social_information.gd")
const Perception = preload("res://scripts/perception.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA_TICK := 0.05

var verif := Verif.new()

var _config: Dictionary
var _croyances: Dictionary
var _canaux: Dictionary
var _liens: Dictionary
var _epigenetique: Dictionary

func _init() -> void:
	_config = _json("res://data/banc_social_information.json")
	_croyances = _json("res://data/croyances.json")
	_canaux = _json("res://data/canaux.json")
	_liens = _json("res://data/liens_personnels.json")
	_epigenetique = _json("res://data/epigenetique.json")

	_la_propriete_de_reputation_est_observable()
	_le_temoin_acquiert_la_reputation_de_ses_yeux()
	_seul_le_temoin_voit_le_vol()
	_la_propagation_reduit_la_certitude()
	_le_lointain_hors_portee_ne_recoit_rien()
	_le_lointain_rapproche_recoit()
	_sous_le_seuil_de_transmission_le_cablage_renonce()
	_la_reputation_decroit_par_saison_puis_disparait()
	_hors_saison_rien_ne_decroit()
	_le_novice_gagne_de_la_competence_par_imitation()
	_le_novice_ne_depasse_pas_fidelite_fois_le_maitre()
	_l_ecart_sous_seuil_ne_declenche_pas_l_imitation()
	_le_maitre_ne_perd_rien()
	_le_modele_n_est_pas_nomme()
	_les_quatre_cadences_sont_en_secondes()
	_l_intervalle_de_pose_reste_sous_la_borne_du_catalogue()
	_les_distances_et_portees_reelles_du_disque()
	_aucun_mecanisme_du_coeur_ne_nomme_ce_banc()
	_un_domaine_entierement_invente_traverse_le_meme_code()
	_config_reelle_du_disque_joue_le_scenario_entier()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_social_information.gd -- la reputation naît de ce qu'un temoin " +
		"a vu, circule par Croyance.corriger a la credibilite d'un lien personnel, " +
		"s'arrete a la portee et tombe par saison ; le novice imite le maitre " +
		"competent a portee sans que celui-ci perde rien -- aucun mecanisme du " +
		"coeur touche")
	quit(0)

# ---- Outils de cas ----

func _json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _scene(config: Dictionary = {}) -> Dictionary:
	return Banc.fabriquer_scene(config if not config.is_empty() else _config)

# Simule "duree" secondes a DELTA_TICK, en appelant LA MEME fonction que
# _process. Rend le dernier resultat plus le temps atteint, pour enchainer
# plusieurs phases sur la meme scene.
func _simuler(
	scene: Dictionary,
	duree: float,
	temps_depart := 0.0,
	config: Dictionary = {},
	croyances: Dictionary = {},
	epigenetique: Dictionary = {},
) -> Dictionary:
	var cfg: Dictionary = config if not config.is_empty() else _config
	var cro: Dictionary = croyances if not croyances.is_empty() else _croyances
	var epi: Dictionary = epigenetique if not epigenetique.is_empty() else _epigenetique
	var temps := temps_depart
	var resultat: Dictionary = {}
	var evenements: Array = []
	for i in range(int(round(duree / DELTA_TICK))):
		temps += DELTA_TICK
		resultat = Banc.avancer(
			scene.colons, scene.monde, cfg, _canaux, cro, _liens, epi,
			DELTA_TICK, temps, scene.horloges)
		evenements.append_array(resultat.evenements)
	return {"resultat": resultat, "temps": temps, "evenements": evenements}

func _colon(scene: Dictionary, id: String) -> Dictionary:
	return Banc.colon_par_id(scene.colons, id)

func _role(scene: Dictionary, role: String, config: Dictionary = {}) -> Dictionary:
	return Banc.colon_par_role(scene.colons, config if not config.is_empty() else _config, role)

func _sujet_id(scene: Dictionary) -> String:
	return String(_role(scene, "sujet_reputation").id)

func _nom_reputation() -> String:
	return String(_config.nom_propriete_reputation)

func _nom_marque() -> String:
	return String(_config.nom_marque_competence)

func _certitude(colon: Dictionary, scene: Dictionary) -> float:
	return Banc.certitude_crue(colon, _sujet_id(scene), _nom_reputation())

func _lien_declare(id: String, vers: String) -> float:
	return float(Banc.declaration_de(_config, id).get("liens", {}).get(vers, 0.0))

# ---- Cas ----

# LE PIEGE QUE data/croyances.json:_note_experimentable a deja paye une fois :
# une propriete absente de proprietes_observables n'est JAMAIS recopiee par
# observer(), en silence -- le temoin ne verrait rien et il n'y aurait rien a
# propager.
func _la_propriete_de_reputation_est_observable() -> void:
	verif.v(_croyances.proprietes_observables.has(_nom_reputation()),
		"la propriete de reputation doit etre dans data/croyances.json:" +
		"proprietes_observables -- sinon observer() ne la capte JAMAIS, en silence")

func _le_temoin_acquiert_la_reputation_de_ses_yeux() -> void:
	var scene := _scene()
	_simuler(scene, 1.0)
	var temoin := _role(scene, "temoin")
	verif.v(Banc.valeur_crue(temoin, _sujet_id(scene), _nom_reputation()) == true,
		"le temoin qui percoit le voleur doit acquerir la croyance de reputation")
	verif.v(_certitude(temoin, scene) > 0.0,
		"la croyance du temoin doit porter une certitude non nulle")

# Ce que le TEMOIN a vu, les autres ne l'ont PAS vu -- sans quoi ils formeraient
# la croyance par observation directe et il n'y aurait plus rien a propager
# (meme piege que banc_croyance.gd evite en ne faisant marcher personne).
func _seul_le_temoin_voit_le_vol() -> void:
	var scene := _scene()
	var sujet_id := _sujet_id(scene)
	var temoin_voit := false
	for entree in Perception.percevoir(_role(scene, "temoin"), scene.monde, _canaux):
		if String(entree.chose.id) == sujet_id:
			temoin_voit = true
	verif.v(temoin_voit, "le temoin doit percevoir le sujet de la reputation")
	for role in ["entretient_competence", "imite"]:
		var autre := _role(scene, role)
		var voit := false
		for entree in Perception.percevoir(autre, scene.monde, _canaux):
			if String(entree.chose.id) == sujet_id:
				voit = true
		verif.v(not voit, "%s ne doit PAS percevoir le vol -- sa croyance ne peut " % autre.id +
			"venir que de la parole du temoin")

# LA PAROLE AFFAIBLIT CE QU'ELLE PORTE : gain_par_echec x credibilite, ou
# credibilite = force du lien DU RECEVEUR vers l'emetteur x propagation_par_temoin.
# Verifie au chiffre contre les nombres du disque, jamais contre une constante.
func _la_propagation_reduit_la_certitude() -> void:
	var scene := _scene()
	_simuler(scene, 3.0)
	var temoin := _role(scene, "temoin")
	var fidelite: float = float(_config.propagation_par_temoin)
	for id in ["maitre", "novice"]:
		var recepteur := _colon(scene, id)
		if recepteur.is_empty():
			continue
		var credibilite: float = _lien_declare(id, String(temoin.id)) * fidelite
		verif.v(is_equal_approx(_certitude(recepteur, scene),
			float(_croyances.gain_par_echec) * credibilite),
			"%s doit porter gain_par_echec x credibilite, jamais la certitude du temoin" % id)
		verif.v(_certitude(recepteur, scene) < _certitude(temoin, scene),
			"%s, qui a ENTENDU, doit etre moins sur que le temoin, qui a VU" % id)

func _le_lointain_hors_portee_ne_recoit_rien() -> void:
	var scene := _scene()
	_simuler(scene, 5.0)
	var lointain := _colon(scene, "lointain")
	verif.v(not lointain.proprietes.croyances.has(_sujet_id(scene)),
		"hors de la portee de propagation, le cablage ne parle meme pas -- aucune " +
		"croyance ne doit apparaitre")

func _le_lointain_rapproche_recoit() -> void:
	var scene := _scene()
	_simuler(scene, 2.0)
	var eloigne := Banc.basculer_eloigne(scene.colons, _config, true)
	verif.v(not eloigne, "la bascule doit rendre l'etat RAPPROCHE")
	_simuler(scene, 3.0, 2.0)
	var lointain := _colon(scene, "lointain")
	verif.v(Banc.valeur_crue(lointain, _sujet_id(scene), _nom_reputation()) == true,
		"une fois entre dans la portee, il doit recevoir la reputation")
	verif.v(_certitude(lointain, scene) > 0.0,
		"la croyance recue doit porter une certitude non nulle")

# DEUX REFUS DISTINCTS (contrat de data/croyances.json, tenu par l'appelant) :
# sous seuil_bornes_transmission, le CABLAGE renonce et n'appelle meme pas
# corriger(). Aucun destinataire de la scene reelle n'y tombe -- ce cas force la
# fidelite pour exercer la branche.
func _sous_le_seuil_de_transmission_le_cablage_renonce() -> void:
	var config: Dictionary = _config.duplicate(true)
	config["propagation_par_temoin"] = 0.001
	var scene := _scene(config)
	var r := _simuler(scene, 3.0, 0.0, config)
	var sourd := false
	for ev in r.evenements:
		if String(ev.genre) == "sourd":
			sourd = true
	verif.v(sourd, "sous seuil_bornes_transmission, le refus doit etre trace comme 'sourd'")
	for id in ["maitre", "novice"]:
		verif.v(not _colon(scene, id).proprietes.croyances.has(_sujet_id(scene)),
			"%s ne doit RIEN recevoir quand le cablage renonce avant corriger()" % id)

# LA DECROISSANCE EST SAISONNIERE : elle ne tombe pas en pente douce, elle tombe
# PAR MARCHES de taux_decroissance x duree_saison, une fois par saison.
func _la_reputation_decroit_par_saison_puis_disparait() -> void:
	var scene := _scene()
	_simuler(scene, 1.0)
	Banc.poser_vol(scene.colons, _config, false)
	var temoin := _role(scene, "temoin")
	var avant := _certitude(temoin, scene)
	verif.v(avant > 0.0, "le temoin doit avoir une croyance avant que le vol cesse")

	var saison: float = Banc.duree_saison_s(_config)
	var perte: float = float(_croyances.taux_decroissance) * saison
	var r := _simuler(scene, saison, 1.0)
	verif.v(int(r.resultat.saison) == 1, "une saison doit s'etre ecoulee")
	verif.v(is_equal_approx(_certitude(temoin, scene), avant - perte),
		"la certitude doit perdre EXACTEMENT taux_decroissance x duree_saison, " +
		"d'un seul coup")

	# Assez de saisons pour passer sous plancher_suppression, quelle que soit la
	# calibration : le nombre est DERIVE des nombres du disque, jamais ecrit ici.
	var restantes: int = int(ceil(avant / max(perte, 0.0001))) + 1
	_simuler(scene, saison * float(restantes), 1.0 + saison)
	verif.v(not temoin.proprietes.croyances.has(_sujet_id(scene)),
		"passe le plancher, croyance.gd doit RETIRER l'entree -- jamais la laisser " +
		"a une valeur residuelle")

# LE PENDANT DU CAS PRECEDENT : entre deux saisons, rien ne decroit. C'est ce
# qui distingue une cadence saisonniere d'un taux par seconde.
func _hors_saison_rien_ne_decroit() -> void:
	var scene := _scene()
	_simuler(scene, 1.0)
	Banc.poser_vol(scene.colons, _config, false)
	var temoin := _role(scene, "temoin")
	var avant := _certitude(temoin, scene)
	_simuler(scene, Banc.duree_saison_s(_config) * 0.5, 1.0)
	verif.v(is_equal_approx(_certitude(temoin, scene), avant),
		"sous l'echeance de saison, l'oubli ne doit RIEN retirer")

func _le_novice_gagne_de_la_competence_par_imitation() -> void:
	var scene := _scene()
	var novice := _role(scene, "imite")
	verif.v(is_equal_approx(Banc.modulateur(novice, _nom_marque()), 0.0),
		"le novice doit partir sans aucune competence")
	_simuler(scene, 2.0)
	verif.v(Banc.modulateur(novice, _nom_marque()) > 0.0,
		"le novice qui percoit un modele plus competent a portee doit GAGNER de " +
		"la competence")

func _le_novice_ne_depasse_pas_fidelite_fois_le_maitre() -> void:
	var scene := _scene()
	_simuler(scene, 20.0)
	var novice := _role(scene, "imite")
	var maitre := _role(scene, "entretient_competence")
	var plafond: float = float(_config.fidelite_imitation) * Banc.modulateur(maitre, _nom_marque())
	var pose: float = float(_epigenetique[_nom_marque()].modulateur_pose)
	verif.v(Banc.modulateur(novice, _nom_marque()) <= plafond + pose,
		"l'imitation ne doit jamais depasser fidelite x le modele, a une pose pres " +
		"-- c'est LA borne, epigenetique.gd n'acceptant aucune magnitude")
	verif.v(Banc.modulateur(novice, _nom_marque()) < Banc.modulateur(maitre, _nom_marque()),
		"un imitateur ne rattrape jamais son modele")

# LE GATE D'ECART, isole du plafond : la fidelite est poussee assez haut pour
# que le plafond ne puisse PAS mordre, et rien ne doit quand meme etre pose.
func _l_ecart_sous_seuil_ne_declenche_pas_l_imitation() -> void:
	var config: Dictionary = _config.duplicate(true)
	config["fidelite_imitation"] = 100.0
	var scene := _scene(config)
	var novice := _role(scene, "imite", config)
	var maitre := _role(scene, "entretient_competence", config)
	var nom := String(config.nom_marque_competence)
	# Ecart deliberement SOUS seuil_ecart, pose a la main.
	var proche: float = Banc.modulateur(maitre, nom) - float(config.seuil_ecart) * 0.5
	novice.proprietes.marques_epigenetiques[nom] = {"modulateur": proche, "age_marque": 0.0}
	var evenements := Banc.imiter_si_cadence(novice, maitre, config, _epigenetique, 0.0)
	verif.v(evenements.is_empty(),
		"sous seuil_ecart il n'y a plus rien a apprendre : aucune pose, aucun evenement")
	verif.v(is_equal_approx(Banc.modulateur(novice, nom), proche),
		"le modulateur de l'imitant ne doit pas bouger d'un iota")
	# Contre-epreuve : au-dessus du seuil, la MEME fonction pose.
	var loin: float = Banc.modulateur(maitre, nom) - float(config.seuil_ecart) * 2.0
	novice.proprietes.marques_epigenetiques[nom] = {"modulateur": loin, "age_marque": 0.0}
	verif.v(not Banc.imiter_si_cadence(novice, maitre, config, _epigenetique, 10.0).is_empty(),
		"au-dessus du seuil, la meme fonction doit poser -- c'est bien l'ecart qui " +
		"decide, pas un cas particulier")

# Le maitre EXERCE son metier : sans cet entretien, Epigenetique.avancer ferait
# fondre sa marque et « le maitre ne perd rien » serait faux tous tests verts.
func _le_maitre_ne_perd_rien() -> void:
	var scene := _scene()
	var maitre := _role(scene, "entretient_competence")
	var plafond: float = float(Banc.declaration_de(_config, String(maitre.id)).plafond_competence)
	_simuler(scene, 20.0)
	var regle: Dictionary = _epigenetique[_nom_marque()]
	var creux: float = float(regle.taux_decroissance) * Banc.intervalle_imitation_s(_config)
	verif.v(Banc.modulateur(maitre, _nom_marque()) >= plafond - creux,
		"la competence du maitre ne doit jamais descendre de plus d'un intervalle " +
		"de decroissance sous son plafond -- il exerce, il ne rouille pas")

# LE MODELE N'EST PAS NOMME : c'est le plus competent PERCU a portee. Le maitre,
# qui percoit le novice, ne l'imite jamais -- parce que son ecart est negatif,
# pas parce qu'un cas particulier l'exclut.
func _le_modele_n_est_pas_nomme() -> void:
	var scene := _scene()
	var r := _simuler(scene, 1.0)
	var novice := _role(scene, "imite")
	var maitre := _role(scene, "entretient_competence")
	verif.v(String(r.resultat.infos[novice.id].modele_id) == String(maitre.id),
		"le modele du novice doit etre le plus competent percu a portee")
	verif.v(String(r.resultat.infos[maitre.id].modele_id) == "",
		"le maitre ne prend aucun modele -- il ne declare pas imiter")
	var vide := Banc.modele_pour(novice, [], scene.colons, _config)
	verif.v(vide.is_empty(), "sans perception, aucun modele -- point neutre, jamais une alarme")

# CONSTAT D DE L'AUDIT : une cadence « par heure » n'est pas une cadence. Les
# quatre derivent d'un SEUL facteur d'echelle, et aucune ne vaut le nombre brut.
func _les_quatre_cadences_sont_en_secondes() -> void:
	var echelle: float = float(_config.secondes_par_heure_simulee)
	verif.v(is_equal_approx(Banc.intervalle_observation_s(_config),
		float(_config.cadence_observation_h) * echelle),
		"l'intervalle d'observation doit etre la cadence horaire MISE A L'ECHELLE")
	verif.v(is_equal_approx(Banc.intervalle_propagation_s(_config),
		float(_config.heures_par_propagation) * echelle),
		"l'intervalle de propagation doit etre mis a l'echelle")
	verif.v(is_equal_approx(Banc.intervalle_imitation_s(_config),
		echelle / float(_config.prob_par_observation_h)),
		"prob_par_observation_h est un NOMBRE PAR HEURE : l'intervalle en secondes " +
		"en est l'inverse mis a l'echelle")
	verif.v(is_equal_approx(Banc.duree_saison_s(_config),
		float(_config.heures_par_saison) * echelle),
		"la duree d'une saison doit etre mise a l'echelle")
	verif.v(not is_equal_approx(Banc.intervalle_imitation_s(_config),
		float(_config.prob_par_observation_h)),
		"le nombre 'par heure' ne doit JAMAIS etre consomme tel quel comme un " +
		"intervalle en secondes")
	var sans_occasion: Dictionary = _config.duplicate(true)
	sans_occasion["prob_par_observation_h"] = 0.0
	verif.v(is_equal_approx(Banc.intervalle_imitation_s(sans_occasion), 0.0),
		"une frequence nulle rend 0.0 -- point neutre, jamais une division par zero")

# LE PIEGE DEJA PAYE TROIS FOIS (constat F de l'audit) : au-dessus de
# (modulateur_pose - plancher_suppression) / taux_decroissance, la marque est
# effacee ENTRE DEUX POSES et n'accumule JAMAIS rien, sans que rien ne rougisse.
# Verifie contre les nombres REELS du disque, jamais contre une copie locale.
func _l_intervalle_de_pose_reste_sous_la_borne_du_catalogue() -> void:
	var regle: Dictionary = _epigenetique[_nom_marque()]
	var borne: float = (float(regle.modulateur_pose) - float(regle.plancher_suppression)) \
		/ float(regle.taux_decroissance)
	verif.v(Banc.intervalle_imitation_s(_config) < borne,
		"l'intervalle de pose (%.3f s) doit rester SOUS %.3f s, sinon la marque est " % [
			Banc.intervalle_imitation_s(_config), borne] +
		"effacee entre deux poses et n'accumule jamais rien")

# LES SIX DISTANCES ET LES DEUX PORTEES, contre les nombres REELS de la config :
# deplacer un colon de quelques dizaines d'unites casserait la demonstration en
# silence.
func _les_distances_et_portees_reelles_du_disque() -> void:
	var scene := _scene()
	var propagation: float = Banc.portee_propagation(_config)
	var imitation: float = Banc.portee_imitation(_config)
	var temoin := _role(scene, "temoin")
	var sujet := _role(scene, "sujet_reputation")
	var maitre := _role(scene, "entretient_competence")
	var novice := _role(scene, "imite")
	var lointain := _colon(scene, "lointain")

	verif.v(temoin.position.distance_to(sujet.position)
		<= _portee_vue(temoin), "le temoin doit voir le sujet")
	verif.v(maitre.position.distance_to(sujet.position)
		> _portee_vue(maitre), "le maitre ne doit PAS voir le sujet")
	verif.v(novice.position.distance_to(sujet.position)
		> _portee_vue(novice), "le novice ne doit PAS voir le sujet")
	verif.v(temoin.position.distance_to(maitre.position) <= propagation
		and temoin.position.distance_to(novice.position) <= propagation,
		"maitre et novice doivent etre a portee de propagation")
	verif.v(temoin.position.distance_to(lointain.position) > propagation,
		"le lointain doit etre HORS portee de propagation au depart")
	verif.v(novice.position.distance_to(maitre.position) <= imitation,
		"le novice doit etre a portee d'imitation du maitre")
	Banc.basculer_eloigne(scene.colons, _config, true)
	verif.v(temoin.position.distance_to(lointain.position) <= propagation,
		"rapproche, le lointain doit entrer dans la portee de propagation")

func _portee_vue(colon: Dictionary) -> float:
	for nom_canal in colon.proprietes.canaux_config:
		return float(colon.proprietes.canaux_config[nom_canal].portee)
	return 0.0

# VERROU NEGATIF DE DOCTRINE : aucun des cinq mecanismes composes ne doit porter
# le moindre nom de contenu de ce banc. Les fichiers sont relus SUR LE DISQUE ;
# les noms cherches sortent de la CONFIG, jamais d'une liste ecrite ici -- un
# renommage en donnee suit donc automatiquement.
func _aucun_mecanisme_du_coeur_ne_nomme_ce_banc() -> void:
	var noms: Array = [_nom_reputation(), _nom_marque()]
	for decl in _config.get("colons", []):
		noms.append(String(decl.id))
	for chemin in ["res://scripts/croyance.gd", "res://scripts/lien_personnel.gd",
			"res://scripts/perception.gd", "res://scripts/portee.gd",
			"res://scripts/epigenetique.gd"]:
		var source := FileAccess.get_file_as_string(chemin)
		verif.v(not source.is_empty(), "le mecanisme %s doit etre lisible sur le disque" % chemin)
		for nom in noms:
			verif.v(not source.contains(String(nom)),
				"%s ne doit contenir AUCUN nom de contenu de ce banc ('%s') -- " % [chemin, nom] +
				"un mecanisme du coeur ne connait que des verbes")

# LE MEME CODE, UN VOCABULAIRE SANS AUCUN RAPPORT AVEC ORION -- et des
# CATALOGUES inventes, passes en parametre comme croyance.gd/epigenetique.gd
# l'exigent. Si un seul nom de contenu etait en dur dans le cablage, ce cas
# rougirait.
func _un_domaine_entierement_invente_traverse_le_meme_code() -> void:
	var config := _config_hors_domaine()
	var croyances: Dictionary = {
		"proprietes_observables": ["signal_defectueux"],
		"proprietes_conservees": [],
		"certitude_initiale": 0.3,
		"gain_par_verification": 0.1,
		"plafond_certitude": 1.0,
		"taux_decroissance": 0.02,
		"plancher_suppression": 0.05,
		"gain_par_echec": 0.8,
		"resistance_par_certitude": 0.9,
		"seuil_bornes_transmission": 0.2,
	}
	var epigenetique: Dictionary = {
		"calibrage_sonde": {
			"modulateur_pose": 0.04,
			"taux_decroissance": 0.05,
			"plancher_suppression": 0.02,
		},
	}
	var scene := _scene(config)
	var r := _simuler(scene, 4.0, 0.0, config, croyances, epigenetique)
	var relais := Banc.colon_par_role(scene.colons, config, "temoin")
	var voisin := Banc.colon_par_id(scene.colons, "sonde_voisine")
	var apprenante := Banc.colon_par_role(scene.colons, config, "imite")
	verif.v(Banc.valeur_crue(relais, "sonde_avariee", "signal_defectueux") == true,
		"hors domaine : le relais doit acquerir la croyance de ses propres capteurs")
	verif.v(Banc.valeur_crue(voisin, "sonde_avariee", "signal_defectueux") == true,
		"hors domaine : la sonde voisine doit recevoir par propagation")
	verif.v(Banc.certitude_crue(voisin, "sonde_avariee", "signal_defectueux")
		< Banc.certitude_crue(relais, "sonde_avariee", "signal_defectueux"),
		"hors domaine : la propagation doit affaiblir la certitude, ici comme ailleurs")
	verif.v(Banc.modulateur(apprenante, "calibrage_sonde") > 0.0,
		"hors domaine : l'apprenante doit gagner du calibrage en imitant l'etalon")
	verif.v(not r.evenements.is_empty(), "hors domaine : le tick doit produire des evenements")

# Une scene entierement inventee, au MEME format, sans un seul mot d'Orion.
func _config_hors_domaine() -> Dictionary:
	return {
		"canaux": ["vue"],
		"nom_propriete_reputation": "signal_defectueux",
		"nom_marque_competence": "calibrage_sonde",
		"unites_par_case": 10.0,
		"portee_propagation_cases": 30.0,
		"portee_imitation_cases": 20.0,
		"secondes_par_heure_simulee": 1.0,
		"cadence_observation_h": 0.2,
		"heures_par_propagation": 0.5,
		"prob_par_observation_h": 5.0,
		"heures_par_saison": 30.0,
		"propagation_par_temoin": 0.9,
		"fidelite_imitation": 0.5,
		"seuil_ecart": 0.1,
		"vol_au_depart": true,
		"colons": [
			{
				"id": "sonde_avariee", "position": [0.0, 0.0, 0.0],
				"portee_vue": 50.0, "sujet_reputation": true,
			},
			{
				"id": "relais", "position": [60.0, 0.0, 0.0],
				"portee_vue": 100.0, "temoin": true,
			},
			{
				"id": "sonde_voisine", "position": [60.0, 120.0, 0.0],
				"portee_vue": 40.0, "liens": {"relais": 0.9},
			},
			{
				"id": "etalon", "position": [200.0, 120.0, 0.0],
				"portee_vue": 60.0, "liens": {"relais": 0.9},
				"modulateur_competence_depart": 0.8,
				"entretient_competence": true, "plafond_competence": 0.8,
			},
			{
				"id": "apprenante", "position": [250.0, 120.0, 0.0],
				"portee_vue": 60.0, "liens": {"relais": 0.9},
				"modulateur_competence_depart": 0.0, "imite": true,
			},
		],
	}

# LE REJEU COMPLET. Aucun chiffre local : la scene entiere sort des fichiers du
# disque, exactement comme le banc lance a l'ecran.
func _config_reelle_du_disque_joue_le_scenario_entier() -> void:
	var scene := _scene()
	var temoin := _role(scene, "temoin")
	var maitre := _role(scene, "entretient_competence")
	var novice := _role(scene, "imite")
	var lointain := _colon(scene, "lointain")

	# Phase 1 -- le vol dure : le temoin voit, deux colons entendent, un troisieme
	# est trop loin, et le novice apprend.
	_simuler(scene, 5.0)
	verif.v(_certitude(temoin, scene) > _certitude(maitre, scene)
		and _certitude(maitre, scene) > 0.0,
		"phase 1 : le temoin sait mieux que ceux a qui il l'a dit")
	verif.v(_certitude(novice, scene) > 0.0, "phase 1 : le novice a entendu, lui aussi")
	verif.v(is_equal_approx(_certitude(lointain, scene), 0.0),
		"phase 1 : le lointain n'a rien entendu")
	verif.v(Banc.modulateur(novice, _nom_marque()) > 0.0,
		"phase 1 : le novice a gagne de la competence en regardant le maitre")

	# Phase 2 -- le lointain se rapproche : il entre dans la portee et recoit.
	Banc.basculer_eloigne(scene.colons, _config, true)
	_simuler(scene, 3.0, 5.0)
	verif.v(_certitude(lointain, scene) > 0.0,
		"phase 2 : rapproche, il recoit ce que tout le monde savait deja")

	# Phase 3 -- le vol cesse : plus rien a reobserver, et les saisons effacent.
	Banc.poser_vol(scene.colons, _config, false)
	var avant := _certitude(temoin, scene)
	var saison: float = Banc.duree_saison_s(_config)
	_simuler(scene, saison, 8.0)
	verif.v(_certitude(temoin, scene) < avant,
		"phase 3 : la cause disparue, la reputation du temoin decroit a la saison")
	var restantes: int = int(ceil(avant / max(float(_croyances.taux_decroissance) * saison, 0.0001))) + 2
	_simuler(scene, saison * float(restantes), 8.0 + saison)
	for colon in scene.colons:
		verif.v(not colon.proprietes.croyances.has(_sujet_id(scene)),
			"phase 3 : le temoin oublie, cesse de propager, et tout le monde finit " +
			"par oublier -- %s porte encore la croyance" % colon.id)
	verif.v(Banc.modulateur(maitre, _nom_marque()) > 0.0,
		"phase 3 : la competence du maitre, elle, ne depend d'aucune reputation")
