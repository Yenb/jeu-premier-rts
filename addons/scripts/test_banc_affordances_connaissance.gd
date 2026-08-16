extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_affordances_connaissance.gd
#
# Verrouille le CABLAGE de banc_affordances_connaissance.gd -- les cinq lignes
# du bloc « connaissance » du tableau Affordances (audit_affordances_prealable.md
# 13 a 17) : la decouverte par usage pose la croyance, deux colons divergent, la
# transmission perd de la certitude, le dogme refuse, la croyance perimee fait
# manger le toxique, le gate d'experimentation s'ouvre et se ferme par la seule
# arithmetique, le livre fige les croyances de son auteur, un lecteur les
# acquiert, et le livre finit illisible.
#
# Les mecanismes composes (perception.gd, croyance.gd, proximite.gd,
# dominance.gd, agir.gd, objet.gd, monde.gd, depense.gd, etat_duree.gd,
# lien_personnel.gd) restent INCHANGES : ce fichier ne verrouille que le
# cablage. La genericite de croyance.gd est prouvee ailleurs, hors domaine
# (scripts/test_croyance.gd), celle de depense.gd par scripts/test_depense.gd.
#
# TOUTES LES DONNEES SONT LUES SUR LE DISQUE, jamais recopiees ici (meme
# discipline que test_banc_croyance.gd) : la calibration reste reglable par
# Yael sans toucher a ce fichier.
#
# DEUX FAMILLES DE CAS, a ne pas confondre :
# - les cas de mecanique isolent UNE transition et ne disent rien de la
#   jouabilite du banc ;
# - _config_reelle_du_disque_joue_le_scenario_entier rejoue
#   data/banc_affordances_connaissance.json EN ENTIER. Sans lui, tout ce fichier
#   resterait VERT alors que le banc lance a l'ecran ne montrerait ni
#   empoisonnement, ni experimentation, ni livre -- exactement le trou trouve
#   sur banc_maladie puis sur banc_predation.

const Banc = preload("res://scripts/banc_affordances_connaissance.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA_TICK := 0.1

# Les huit fichiers du COEUR qu'aucun nom de ce chantier ne doit avoir
# atteints. Verrouille la consigne « ne touche AUCUN mecanisme du coeur » par
# la seule preuve testable : la discipline moteur/donnees (CLAUDE.md, ADN) --
# si un mot de ce gameplay etait entre dans un de ces fichiers, il y serait
# LISIBLE.
const FICHIERS_COEUR := [
	"res://scripts/croyance.gd",
	"res://scripts/epigenetique.gd",
	"res://scripts/deformation.gd",
	"res://scripts/depense.gd",
	"res://scripts/objet.gd",
	"res://scripts/monde.gd",
	"res://scripts/agir.gd",
	"res://scripts/couplage.gd",
]
const MOTS_DE_CONTENU := [
	"experimenter", "experimentable", "curiosite", "contenu_croyance",
	"livre", "illisible", "empoisonne", "fidelite", "medecin", "apprenti",
	"novice", "fruit",
]

var verif := Verif.new()

var _config: Dictionary
var _catalogues: Dictionary
var _textes: Dictionary

func _init() -> void:
	_config = _json("res://data/banc_affordances_connaissance.json")
	_textes = _json("res://data/textes.json")
	_catalogues = {
		"canaux": _json("res://data/canaux.json"),
		"croyances": _json("res://data/croyances.json"),
		"etats": _json("res://data/etats.json"),
		"seuils": _json("res://data/seuils_combustible.json"),
		"profils": _json("res://data/profils_saillance.json"),
		"actions": _json("res://data/types_choses.json"),
		"types": _json("res://data/types.json"),
		"materiaux": _json("res://data/materiaux.json"),
		"liens": _json("res://data/liens_personnels.json"),
	}

	_la_decouverte_par_usage_pose_la_croyance()
	_deux_colons_ont_des_croyances_independantes()
	_la_transmission_reduit_la_certitude()
	_le_dogmatique_ne_change_pas_de_croyance()
	_la_croyance_perimee_survit_a_la_cle_retiree()
	_la_fausse_croyance_fait_manger_le_toxique()
	_le_gate_experimenter_est_ferme_sans_curiosite()
	_le_gate_experimenter_s_ouvre_avec_curiosite()
	_le_materiau_epuise_referme_le_gate()
	_le_livre_porte_les_croyances_de_l_auteur()
	_le_lecteur_acquiert_les_croyances_du_livre()
	_le_livre_se_degrade_et_devient_illisible()
	_le_label_illisible_passe_par_textes_json()
	_aucun_mecanisme_du_coeur_n_est_touche()
	_config_reelle_du_disque_joue_le_scenario_entier()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_affordances_connaissance.gd -- la decouverte par usage pose " +
		"la croyance a credibilite 1.0, deux colons divergent sans qu'aucun etat " +
		"ne soit pose en dur, la transmission perd de la certitude par la fidelite, " +
		"le dogme refuse, la croyance perimee fait manger le toxique et empoisonne, " +
		"le gate d'experimentation s'ouvre et se referme par la seule arithmetique, " +
		"le livre fige les croyances de son auteur, un lecteur les acquiert a la " +
		"fidelite du livre, et la reserve d'integrite epuisee le rend illisible -- " +
		"aucun mecanisme du coeur touche")
	quit(0)

# ---- Outils de cas ----

func _json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _scene() -> Dictionary:
	return Banc.etat_initial(_config, _catalogues)

# Simule "duree" secondes a DELTA_TICK. Rend le dernier resultat d'avancer()
# plus le temps atteint, pour enchainer plusieurs phases sur la meme scene.
func _simuler(etat: Dictionary, duree: float, temps_depart := 0.0) -> Dictionary:
	var temps := temps_depart
	var resultat: Dictionary = {}
	var evenements: Array = []
	for i in range(int(round(duree / DELTA_TICK))):
		temps += DELTA_TICK
		resultat = Banc.avancer(etat, _config, _catalogues, DELTA_TICK, temps)
		evenements.append_array(resultat.evenements)
	return {"resultat": resultat, "temps": temps, "evenements": evenements}

func _colon(etat: Dictionary, id: String) -> Dictionary:
	return Banc.colon_par_id(etat.colons, id)

func _etat_colon(resultat: Dictionary, id: String) -> Dictionary:
	for e in resultat.get("colons", []):
		if String(e.id) == id:
			return e
	return {}

func _a_evenement(evenements: Array, colon: String, genre: String, chose_id: String, propriete: String) -> bool:
	for ev in evenements:
		if String(ev.colon) == colon and String(ev.genre) == genre \
			and String(ev.chose_id) == chose_id and String(ev.propriete) == propriete:
			return true
	return false

func _auteur() -> String:
	return String(_config.auteur)

func _fruit() -> String:
	return String(_config.fruit_bascule)

# ---- Ligne 13 : seul celui qui s'en sert sait ----

func _la_decouverte_par_usage_pose_la_croyance() -> void:
	var etat := _scene()
	# CE QUE L'USAGE APPREND ET QUE LE REGARD NE DONNE PAS : 'toxique' n'est pas
	# dans data/croyances.json:proprietes_observables. Avant le premier usage, le
	# colon n'a AUCUNE croyance dessus -- « je ne sais pas » ; apres, il sait que
	# non. Les deux etats sont distincts (docs/design.md, « ce qui n'a jamais ete
	# percu est ABSENT, jamais present a zero »).
	var medecin := _colon(etat, _auteur())
	verif.v(medecin.proprietes.croyances.is_empty(),
		"prealable : aucune croyance n'est posee en dur a la construction -- " +
		"elles naissent toutes de la perception vecue, et 'toxique' n'est " +
		"l'objet d'aucune avant le premier usage")
	var r := _simuler(etat, 1.0)
	verif.v(Banc.valeur_crue(medecin, _fruit(), "toxique") == false,
		"celui qui se sert du fruit sain apprend qu'il n'est pas toxique -- une " +
		"propriete absente de la chose reelle vaut false, c'est la valeur " +
		"VERIFIEE, jamais un defaut silencieux")
	verif.v(Banc.valeur_crue(medecin, _fruit(), "comestible") == true,
		"et il confirme au passage ce que son regard lui disait deja")
	verif.v(Banc.certitude_crue(medecin, _fruit(), "toxique")
		<= float(_catalogues.croyances.gain_par_echec) + 0.0001,
		"l'usage ECRASE la certitude a gain_par_echec x 1.0, jamais plus -- c'est " +
		"ce plafond, sous resistance_par_certitude, qui garde l'experience " +
		"directe eternellement corrigible")
	verif.v(_a_evenement(r.evenements, _auteur(), "apprend", _fruit(), "toxique"),
		"la decouverte par usage doit etre tracee, jamais silencieuse")

# CE QUI SEPARE DEUX REGISTRES N'EST QU'UNE GEOMETRIE ET UN NOMBRE : le medecin
# et le novice se servent du MEME fruit, dans le MEME monde, au MEME instant, et
# n'en croient pas la meme chose -- l'un parce que sa certitude reste corrigible,
# l'autre parce qu'il a regarde sept fois. Aucun etat n'est pose en dur.
func _deux_colons_ont_des_croyances_independantes() -> void:
	var etat := _scene()
	var r := _simuler(etat, 10.0)
	var medecin := _colon(etat, _auteur())
	var novice := _colon(etat, "novice")
	verif.v(Banc.valeur_crue(medecin, _fruit(), "comestible") == false,
		"le medecin, corrigible, a appris par l'usage que le fruit ne se mange plus")
	verif.v(Banc.valeur_crue(novice, _fruit(), "comestible") == true,
		"le novice, au meme instant et sur la meme chose, croit toujours l'inverse")
	verif.v(medecin.proprietes.croyances != novice.proprietes.croyances,
		"deux colons tiennent DEUX registres independants, jamais un partage")
	verif.v(not _a_evenement(r.evenements, "apprenti", "apprend", _fruit(), "toxique"),
		"l'apprenti, hors de portee d'usage, n'apprend JAMAIS rien par lui-meme : " +
		"tout ce qu'il finit par savoir lui vient d'un autre")

# ---- Ligne 14 : la transmission ----

func _la_transmission_reduit_la_certitude() -> void:
	var etat := _scene()
	_simuler(etat, 8.0)
	var medecin := _colon(etat, _auteur())
	var apprenti := _colon(etat, "apprenti")
	var certitude_source := Banc.certitude_crue(medecin, _fruit(), "toxique")
	var evenements := Banc.transmettre(etat.colons, _config, _catalogues.croyances, _catalogues.liens)
	verif.v(Banc.valeur_crue(apprenti, _fruit(), "toxique") == true,
		"un colon lie a l'emetteur doit recevoir la valeur transmise TELLE QUELLE " +
		"-- la fidelite degrade la certitude, jamais la valeur")
	var recue := Banc.certitude_crue(apprenti, _fruit(), "toxique")
	verif.v(recue < certitude_source,
		"la certitude du receveur doit etre STRICTEMENT sous celle de l'emetteur")
	var lien: float = float(apprenti.proprietes.liens_personnels.get(_auteur(), 0.0))
	verif.v(is_equal_approx(recue,
		float(_catalogues.croyances.gain_par_echec) * lien * float(_config.fidelite_parole)),
		"la certitude recue doit valoir gain_par_echec x force_du_lien x fidelite_parole " +
		"-- aucun nombre invente par le cablage")
	verif.v(_a_evenement(evenements, "apprenti", "recoit", _fruit(), "toxique"),
		"une transmission acceptee doit produire un evenement 'recoit'")

func _le_dogmatique_ne_change_pas_de_croyance() -> void:
	var etat := _scene()
	_simuler(etat, 8.0)
	var novice := _colon(etat, "novice")
	var certitude_avant := Banc.certitude_crue(novice, _fruit(), "comestible")
	verif.v(certitude_avant >= float(_catalogues.croyances.resistance_par_certitude),
		"le novice doit avoir franchi resistance_par_certitude par la seule " +
		"accumulation d'observations -- aucun etat 'dogmatique' n'existe")
	var evenements := Banc.transmettre(etat.colons, _config, _catalogues.croyances, _catalogues.liens)
	verif.v(Banc.valeur_crue(novice, _fruit(), "comestible") == true,
		"au-dela de resistance_par_certitude, la correction est IGNOREE")
	verif.v(is_equal_approx(Banc.certitude_crue(novice, _fruit(), "comestible"), certitude_avant),
		"une correction refusee ne touche NI la valeur NI la certitude")
	verif.v(_a_evenement(evenements, "novice", "dogme", _fruit(), "comestible"),
		"le refus par dogme doit etre trace, jamais silencieux")
	var lien: float = float(novice.proprietes.liens_personnels.get(_auteur(), 0.0))
	verif.v(lien * float(_config.fidelite_parole) >= float(_catalogues.croyances.seuil_bornes_transmission),
		"le refus montre ici doit bien etre celui du MECANISME : le cablage a " +
		"appele corriger(), il n'a pas renonce sous seuil_bornes_transmission")

# ---- Ligne 15 : l'affordance fausse ----

# FENETRE COURTE ET VOULUE : la bascule est posee a t=0.5 et l'ecart est lu a
# t=0.8, AVANT le prochain usage du medecin (t=1.1) donc avant qu'un livre
# n'existe. Ce qu'on mesure ici est l'effet du REGARD SEUL sur une cle retiree,
# et rien d'autre -- la source d'information des autres colons est le sujet des
# cas suivants, pas de celui-ci.
func _la_croyance_perimee_survit_a_la_cle_retiree() -> void:
	var etat := _scene()
	var r := _simuler(etat, 0.5)
	Banc.poser_etat_fruit(etat.objets, _config, true)
	var fruit := Banc.objet_par_id(etat.objets, _fruit())
	verif.v(not fruit.proprietes.has("comestible"),
		"le fruit toxique doit PERDRE la cle 'comestible', jamais la mettre a " +
		"false -- observer() n'itere que les proprietes presentes")
	_simuler(etat, 0.3, r.temps)
	for id in ["apprenti", "novice"]:
		verif.v(Banc.valeur_crue(_colon(etat, id), _fruit(), "comestible") == true,
			"la croyance perimee de %s doit SURVIVRE : une cle retiree n'est " % id +
			"jamais reobservee, un coup d'oeil ne revele pas qu'un fruit est " +
			"devenu toxique")

func _la_fausse_croyance_fait_manger_le_toxique() -> void:
	var etat := _scene()
	var r := _simuler(etat, 12.0)
	var novice := _colon(etat, "novice")
	verif.v(_a_evenement(r.evenements, "novice", "empoisonne", _fruit(),
		String(_config.propriete_toxique)),
		"un colon qui CROIT comestible ce qui est toxique doit le manger et " +
		"s'empoisonner -- Croyance.filtrer remplace les proprietes, agir.gd " +
		"resout 'manger' sans une ligne de mecanisme")
	verif.v(novice.proprietes.get("etats_actifs", []).has(String(_config.etat_empoisonne))
		or _a_evenement(r.evenements, "novice", "gueri", "", String(_config.etat_empoisonne)),
		"l'etat 'empoisonne' doit etre POSE (et s'epuiser tout seul ensuite)")
	var medecin := _colon(etat, _auteur())
	verif.v(Banc.valeur_crue(medecin, _fruit(), "comestible") == false,
		"celui qui a corrige sa croyance cesse de croire le fruit comestible")

# ---- Ligne 16 : le gate d'experimentation ----

func _le_gate_experimenter_est_ferme_sans_curiosite() -> void:
	var etat := _scene()
	var r := _simuler(etat, 12.0)
	for id in ["apprenti", "novice"]:
		var colon := _colon(etat, id)
		verif.v(float(colon.proprietes.get("curiosite", 0.0)) < float(_config.seuil_curiosite),
			"%s doit heriter la curiosite du TYPE (data/types.json:colon), sous le seuil" % id)
		verif.v(is_equal_approx(Banc.poids_experimenter(colon, _config), 0.0),
			"sans curiosite, poids_verbes.experimenter doit valoir EXACTEMENT 0.0 " +
			"-- agir.gd exige p > 0.0, le verbe devient inchoisissable par la " +
			"seule arithmetique")
		verif.v(is_equal_approx(float(_etat_colon(r.resultat, id).poids_experimenter), 0.0),
			"%s ne doit jamais porter de poids d'experimentation dans le pas reel" % id)

func _le_gate_experimenter_s_ouvre_avec_curiosite() -> void:
	var etat := _scene()
	var r := _simuler(etat, 12.0)
	var medecin := _colon(etat, _auteur())
	verif.v(float(medecin.proprietes.get("curiosite", 0.0)) >= float(_config.seuil_curiosite),
		"le medecin doit SURCHARGER la curiosite du type, au-dessus du seuil")
	verif.v(_a_evenement(r.evenements, _auteur(), "experimente", "objet_inconnu",
		String(_config.propriete_toxique)),
		"le colon curieux doit avoir experimente l'objet inconnu et en avoir " +
		"appris ce qu'aucun regard ne capte")
	verif.v(Banc.valeur_crue(medecin, "objet_inconnu", String(_config.propriete_toxique)) == true,
		"le resultat d'une experimentation est une croyance corrigee, jamais un " +
		"effet de bord invente")
	# LES TROIS CONDITIONS SONT BIEN INDEPENDANTES : chacune, prise seule, ferme
	# le gate -- verifie sur une copie pour ne pas polluer la scene.
	var sonde: Dictionary = {"id": "sonde", "proprietes": {
		"curiosite": float(_config.seuil_curiosite),
		String(_config.nom_miroir_temps_libre): float(_config.seuil_temps_libre),
		String(_config.nom_miroir_materiau): float(_config.seuil_materiau),
	}}
	verif.v(is_equal_approx(Banc.poids_experimenter(sonde, _config), float(_config.poids_experimenter)),
		"les trois conditions exactement au seuil doivent ouvrir le gate")
	for cle in ["curiosite", String(_config.nom_miroir_temps_libre), String(_config.nom_miroir_materiau)]:
		var manquante: Dictionary = {"id": "sonde", "proprietes": sonde.proprietes.duplicate(true)}
		manquante.proprietes[cle] = 0.0
		verif.v(is_equal_approx(Banc.poids_experimenter(manquante, _config), 0.0),
			"'%s' seule sous son seuil doit suffire a fermer le gate -- un ET, " % cle +
			"jamais une moyenne")

func _le_materiau_epuise_referme_le_gate() -> void:
	var etat := _scene()
	_simuler(etat, 20.0)
	var medecin := _colon(etat, _auteur())
	verif.v(float(medecin.proprietes.get(String(_config.nom_miroir_materiau), 0.0))
		< float(_config.seuil_materiau),
		"experimenter consomme le materiau (surcout_action + depense.gd) jusqu'a " +
		"passer sous le seuil")
	verif.v(is_equal_approx(Banc.poids_experimenter(medecin, _config), 0.0),
		"le materiau epuise REFERME le gate de lui-meme -- aucune ligne ne dit " +
		"'il s'arrete', c'est la meme arithmetique lue a zero")

# ---- Ligne 17 : le livre ----

func _le_livre_porte_les_croyances_de_l_auteur() -> void:
	var etat := _scene()
	var r := _simuler(etat, 8.0)
	verif.v(not etat.livre.is_empty(), "l'auteur doit avoir ecrit son livre")
	verif.v(_a_evenement(r.evenements, _auteur(), "ecrit", String(_config.livre.id), ""),
		"l'ecriture doit etre tracee")
	var medecin := _colon(etat, _auteur())
	var contenu: Dictionary = etat.livre.proprietes.contenu_croyance
	verif.v(contenu.get(_fruit(), {}).get("toxique", {}).get("valeur", null) == true,
		"le livre doit porter ce que son auteur croyait au moment de l'ecriture")
	verif.v(String(etat.livre.proprietes.auteur) == _auteur(),
		"le livre doit nommer son auteur -- c'est ce qui l'empeche de se relire")
	# LE FIGEAGE EST UNE COPIE PROFONDE : on mute le registre de l'auteur et le
	# livre ne bouge pas.
	medecin.proprietes.croyances[_fruit()]["toxique"]["valeur"] = false
	verif.v(contenu.get(_fruit(), {}).get("toxique", {}).get("valeur", null) == true,
		"le contenu du livre doit etre une COPIE PROFONDE : sans duplicate(true) " +
		"le livre suivrait ce que son auteur apprend ensuite, et ne figerait rien")

func _le_lecteur_acquiert_les_croyances_du_livre() -> void:
	var etat := _scene()
	var r := _simuler(etat, 12.0)
	var apprenti := _colon(etat, "apprenti")
	verif.v(Banc.valeur_crue(apprenti, _fruit(), "toxique") == true,
		"le lecteur doit acquerir les croyances du livre -- il n'a jamais touche " +
		"le fruit et personne ne lui a parle")
	# La certitude est ECRASEE a gain_par_echec x fidelite a chaque lecture, puis
	# grignotee par l'oubli jusqu'a la suivante -- elle vit donc dans une bande
	# dont la LARGEUR est exactement un cycle de lecture (meme lecture que
	# test_banc_croyance.gd sur la verification au contact).
	var plafond: float = float(_catalogues.croyances.gain_par_echec) * float(_config.fidelite_livre)
	var creux: float = plafond - float(_catalogues.croyances.taux_decroissance) * float(_config.cadence_lecture)
	var lue := Banc.certitude_crue(apprenti, _fruit(), "toxique")
	verif.v(lue <= plafond + 0.0001 and lue >= creux - 0.0001,
		"la certitude lue doit valoir gain_par_echec x fidelite du livre, moins " +
		"au plus un cycle d'oubli")
	verif.v(plafond < float(_catalogues.croyances.gain_par_echec),
		"ce qu'on lit vaut moins que ce qu'on a vecu : la fidelite du livre " +
		"degrade la CERTITUDE, jamais la valeur")
	verif.v(_a_evenement(r.evenements, "apprenti", "lit", _fruit(), "toxique"),
		"la lecture doit etre tracee")
	verif.v(not _a_evenement(r.evenements, _auteur(), "lit", _fruit(), "toxique"),
		"l'auteur ne se relit JAMAIS -- sinon il rabaisserait sa propre certitude " +
		"(vecue) a celle de ce qu'il a ecrit (lue)")

func _le_livre_se_degrade_et_devient_illisible() -> void:
	var etat := _scene()
	_simuler(etat, 8.0)
	verif.v(not etat.livre.is_empty(), "prealable : le livre doit exister")
	var integrite_avant := Banc.integrite_livre(etat.livre, _config)
	verif.v(integrite_avant < float(_config.livre.integrite),
		"la reserve d'integrite doit deja descendre (depense.gd)")
	verif.v(not Banc.est_illisible(etat.livre, _config),
		"le livre ne doit pas encore etre illisible")
	# Degradation ACCELEREE : le meme etat terminal, six fois plus vite.
	etat["degradation_acceleree"] = true
	var r := _simuler(etat, integrite_avant + 1.0, 8.0)
	verif.v(Banc.est_illisible(etat.livre, _config),
		"a reserve nulle, depense.gd doit poser le marqueur d'illisibilite " +
		"(data/seuils_combustible.json:epuisement_lisibilite)")
	verif.v(_a_evenement(r.evenements, "", "illisible", String(_config.livre.id),
		String(_config.livre.propriete_illisible)),
		"le passage a l'illisible doit etre trace")
	verif.v(not etat.livre.proprietes.contenu_croyance.is_empty(),
		"un livre illisible garde son contenu INTACT : le savoir n'est pas " +
		"detruit, il devient inatteignable")
	var apprenti := _colon(etat, "apprenti")
	verif.v(Banc.lire_si_cadence(apprenti, etat.livre, _config, _catalogues.croyances, 1000.0).is_empty(),
		"plus personne ne peut lire un livre illisible")

func _le_label_illisible_passe_par_textes_json() -> void:
	var etat := _scene()
	_simuler(etat, 8.0)
	verif.v(Banc.cle_label_livre(etat.livre, _config) == String(_config.livre.cle_titre),
		"un livre lisible affiche la cle de titre")
	var attendu_titre: String = String(_textes[String(_config.langue)][String(_config.livre.cle_titre)])
	verif.v(Banc.texte(String(_config.livre.cle_titre), _config, _textes) == attendu_titre,
		"le titre affiche doit venir de data/textes.json, jamais du code")
	etat["degradation_acceleree"] = true
	_simuler(etat, Banc.integrite_livre(etat.livre, _config) + 1.0, 8.0)
	verif.v(Banc.cle_label_livre(etat.livre, _config) == String(_config.livre.cle_illisible),
		"un livre epuise affiche la cle d'illisibilite")
	var attendu: String = String(_textes[String(_config.langue)][String(_config.livre.cle_illisible)])
	verif.v(Banc.texte(String(_config.livre.cle_illisible), _config, _textes) == attendu,
		"le label 'illisible' doit venir de data/textes.json, jamais du code")
	verif.v(Banc.texte("cle.qui.n.existe.pas", _config, _textes) == "cle.qui.n.existe.pas",
		"une cle absente ressort TELLE QUELLE -- jamais un texte de repli ecrit " +
		"en dur, qui serait exactement la faute que la regle i18n interdit")

# ---- La consigne elle-meme ----

# Preuve testable de « aucun mecanisme du coeur n'est touche » : la discipline
# moteur/donnees (CLAUDE.md, ADN). Si un mot de ce gameplay etait entre dans un
# fichier du coeur, il y serait LISIBLE -- ce test le lirait.
#
# SEUL LE CODE EST SCANNE, jamais les commentaires : les en-tetes du coeur
# CITENT des exemples de contenu pour s'expliquer (croyance.gd parle d'un
# « fruit » toxique, et de mecanismes « livres » par d'autres sessions), et
# c'est legitime -- l'ADN interdit qu'un nom de contenu DECIDE quelque chose,
# pas qu'un commentaire le nomme. Ecarter les lignes de commentaire est donc
# la lecture juste de la regle, pas un assouplissement.
func _aucun_mecanisme_du_coeur_n_est_touche() -> void:
	for chemin in FICHIERS_COEUR:
		var source := FileAccess.get_file_as_string(chemin)
		verif.v(source != "", "%s doit exister et etre lisible" % chemin)
		var code := ""
		for ligne in source.split("\n"):
			if String(ligne).strip_edges().begins_with("#"):
				continue
			code += String(ligne) + "\n"
		for mot in MOTS_DE_CONTENU:
			verif.v(not code.contains(mot),
				"%s ne doit contenir AUCUN nom de contenu de ce chantier dans son CODE -- '%s' trouve" % [chemin, mot])

# ---- LE REJEU COMPLET ----

# Aucun chiffre local : la scene entiere sort de
# data/banc_affordances_connaissance.json et des catalogues partages,
# exactement comme le banc lance a l'ecran.
func _config_reelle_du_disque_joue_le_scenario_entier() -> void:
	var etat := _scene()

	# Phase 1 -- le monde est sain, personne ne se trompe.
	var r1 := _simuler(etat, float(_config.instant_toxicite_s) - 1.0)
	for id in ["medecin", "apprenti", "novice"]:
		verif.v(Banc.valeur_crue(_colon(etat, id), _fruit(), "comestible") == true,
			"phase 1 : %s doit croire le fruit comestible, et il a raison" % id)
	verif.v(String(_etat_colon(r1.resultat, "novice").verbe) == "manger",
		"phase 1 : le novice decide de manger le fruit")
	verif.v(etat.livre.is_empty(),
		"phase 1 : rien a ecrire tant que rien d'important n'est su")

	# Phase 2 -- le fruit devient toxique. Seul celui qui s'en sert l'apprend.
	# La fenetre couvre le prochain usage du NOVICE (cadence 4.0 s) : c'est lui,
	# et lui seul, qui doit encore manger ce que le medecin a deja compris.
	var r2 := _simuler(etat, 5.0, r1.temps)
	verif.v(bool(etat.toxicite_declenchee), "phase 2 : l'echeance de toxicite doit avoir joue")
	verif.v(Banc.valeur_crue(_colon(etat, "medecin"), _fruit(), "toxique") == true,
		"phase 2 : le medecin apprend par l'usage")
	verif.v(Banc.valeur_crue(_colon(etat, "novice"), _fruit(), "comestible") == true,
		"phase 2 : le novice, dogmatique, continue de croire le fruit comestible")
	verif.v(_a_evenement(r2.evenements, "novice", "empoisonne", _fruit(),
		String(_config.propriete_toxique)),
		"phase 2 : le novice mange ce qu'il croit comestible et s'empoisonne")
	verif.v(_a_evenement(r2.evenements, "novice", "dogme", _fruit(), "comestible"),
		"phase 2 : son propre usage le contredit, et le dogme refuse")
	verif.v(not etat.livre.is_empty(),
		"phase 2 : l'auteur ecrit des qu'il croit une chose toxique")

	# Phase 3 -- le livre agit sur qui n'a rien vu.
	var r3 := _simuler(etat, 4.0, r2.temps)
	verif.v(Banc.valeur_crue(_colon(etat, "apprenti"), _fruit(), "toxique") == true,
		"phase 3 : l'apprenti sait par le livre ce qu'il n'a jamais touche")
	verif.v(_a_evenement(r3.evenements, _auteur(), "experimente", "objet_inconnu",
		String(_config.propriete_toxique)) or _a_evenement(r2.evenements, _auteur(),
		"experimente", "objet_inconnu", String(_config.propriete_toxique)),
		"phase 3 : liberee du repas, la curiosite ouvre le gate et l'auteur " +
		"experimente l'objet inconnu")

	# Phase 4 -- l'oubli finit par desserrer le dogme.
	_simuler(etat, 14.0, r3.temps)
	var novice := _colon(etat, "novice")
	verif.v(Banc.certitude_crue(novice, _fruit(), "comestible") < float(_catalogues.croyances.resistance_par_certitude)
		or Banc.valeur_crue(novice, _fruit(), "comestible") == false,
		"phase 4 : plus rien ne nourrit le dogme (la cle a disparu de l'objet, " +
		"observer() ne la rafraichit plus) -- l'oubli le ramene sous la resistance")
