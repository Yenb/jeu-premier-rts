extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_elimination_salete.gd
#
# Verrouille le cablage de banc_elimination_salete.gd : le besoin qui monte
# (depense.gd a cout_base NEGATIF), le seuil qui declenche (seuil_etat.gd sur
# miroir plat), le dechet qui nait (objet.gd + monde.gd), la salete qui
# s'accumule et REDESCEND (charge.gd), puis la maladie (etat_duree.gd,
# seuil_etat.gd sur le catalogue PARTAGE). Les six mecanismes du coeur restent
# INCHANGES -- ce fichier ne verrouille que le cablage. Toutes les grandeurs
# (canaux, seuils, durees, fiches materiau) sont lues sur data/*.json REEL,
# comme le fait le banc -- jamais une fixture locale pour un nombre qui decide
# (meme discipline que test_banc_maladie.gd).
#
# DEUX FAMILLES DE CAS, a ne pas confondre :
# - les cas de mecanique posent leurs propres colons, IMMOBILES, et leurs
#   propres dechets : ils isolent UNE transition ;
# - _config_reelle_du_disque_produit_dechets_et_maladie rejoue data/
#   banc_elimination_salete.json EN ENTIER, deplacement seede compris. Sans
#   lui, tout ce fichier resterait VERT alors que le banc lance a l'ecran ne
#   montrerait rien -- c'est exactement le trou qui avait laisse passer la
#   calibration morte de banc_maladie (voir docs/ETAT.md).
#
# FENETRES DE TEST COURTES, ET POURQUOI : un colon elimine A SES PIEDS, il se
# salit donc lui-meme des qu'il produit son premier dechet. Les cas qui
# isolent la salete tournent volontairement MOINS longtemps que le temps de
# production d'un colon a taux_repas 0.0 (_ticks_avant_premier_dechet, derive
# de la config reelle -- jamais un nombre magique), pour que les SEULS dechets
# du monde soient ceux que le test a poses.

const Banc = preload("res://scripts/banc_elimination_salete.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DELTA_TICK := 0.1

var _config: Dictionary
var _catalogues: Dictionary
# Jamais remis a zero de tout le fichier -- meme raison que le compteur du
# banc : monde.gd:ajouter refuse un id deja present et n'enregistre alors
# RIEN, en silence pour l'appelant qui ne lit pas la console.
var _compteur_pose := 0

func _init() -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_elimination_salete.json"))
	_catalogues = {
		"types": JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json")),
		"materiaux": JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json")),
		"etats": JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json")),
		"seuils_partages": JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json")),
	}

	_le_besoin_monte_avec_le_temps()
	_au_seuil_un_dechet_apparait_et_la_reserve_repart_de_zero()
	_qui_mange_plus_elimine_plus_souvent()
	_un_colon_mort_n_elimine_plus()
	_le_dechet_fabrique_porte_la_salete_de_sa_fiche_materiau()
	_les_dechets_font_monter_la_salete_des_colons_a_portee()
	_un_colon_hors_portee_des_dechets_n_accumule_rien()
	_au_seuil_de_salete_le_colon_est_expose_puis_incube()
	_nettoyer_les_dechets_fait_redescendre_la_salete()
	_le_nettoyage_preserve_l_etat_des_colons_et_ne_reutilise_jamais_un_id()
	_etat_courant_et_compter_etats()
	_config_reelle_du_disque_produit_dechets_et_maladie()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_elimination_salete.gd -- besoin qui monte (depense.gd a cout " +
		"negatif), dechet fabrique au seuil (seuil_etat.gd + objet.gd + monde.gd), " +
		"salete accumulee et reversible (charge.gd) puis maladie (etat_duree.gd) " +
		"s'enchainent sans qu'aucun mecanisme du coeur ne soit touche")
	quit(0)

# ---- Fixtures ---------------------------------------------------------------

func _config_test(colons: Array) -> Dictionary:
	var copie := _config.duplicate(true)
	copie["colons"] = colons
	return copie

func _colon_decl(id: String, position: Vector3, taux_repas: float) -> Dictionary:
	return {"id": id, "position": [position.x, position.y, position.z], "taux_repas": taux_repas}

func _colon_par_id(colons: Array, id: String) -> Dictionary:
	for colon in colons:
		if colon.id == id:
			return colon
	return {}

func _monde_avec(colons: Array):
	var monde = Monde.new()
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)
	return monde

# Montee par seconde d'un colon, derivee de la config REELLE : cout_base et
# surcout sont tous deux negatifs, depense.gd soustrait, la reserve monte donc
# de -(cout_base + surcout). Jamais un nombre recopie ici.
func _montee_par_seconde(taux_repas: float) -> float:
	var cout_base: float = float(_config.canal_besoin_elimination.cout_base)
	return -(cout_base) + float(_config.coef_repas) * taux_repas

func _seuil_urgence() -> float:
	return float(_config.seuils_elimination.urgence_elimination.seuil)

# Nombre de ticks avant qu'un colon a taux_repas 0.0 ne produise son premier
# dechet -- borne haute des fenetres de test qui doivent rester "sans dechet
# spontane" (voir en-tete). +1 parce que seuil_etat.gd compare STRICTEMENT
# au-dessus.
func _ticks_avant_premier_dechet() -> int:
	return int(_seuil_urgence() / _montee_par_seconde(0.0) / DELTA_TICK) + 1

func _avancer_n_fois(colons: Array, monde, n: int, compteur: int = 0) -> Dictionary:
	var cumul := {
		"nouveaux_dechets": [], "nouveaux_exposes": [], "nouveaux_malades": [],
		"gueris": [], "morts": [], "compteur_dechet": compteur,
	}
	for i in n:
		var r := Banc.avancer(colons, monde, cumul.compteur_dechet, DELTA_TICK, _config, _catalogues)
		cumul.compteur_dechet = r.compteur_dechet
		for cle in ["nouveaux_dechets", "nouveaux_exposes", "nouveaux_malades", "gueris", "morts"]:
			cumul[cle].append_array(r[cle])
	return cumul

# Pose des dechets REELS (Objet.fabriquer, meme chemin que le banc) autour
# d'une position, sans passer par la production d'un colon.
func _poser_dechets(monde, position: Vector3, combien: int) -> void:
	for i in combien:
		_compteur_pose += 1
		var dechet := Banc.fabriquer_dechet("dechet_pose_%d" % _compteur_pose, position, _config, _catalogues)
		monde.ajouter(dechet, _config.type_dechet, dechet.position)

# ---- Elimination ------------------------------------------------------------

func _le_besoin_monte_avec_le_temps() -> void:
	var colons := Banc.fabriquer_colons(_config_test([_colon_decl("sobre", Vector3.ZERO, 0.0)]))
	var monde = _monde_avec(colons)
	var colon := _colon_par_id(colons, "sobre")

	verif.v(colon.proprietes.urgence_elimination == 0.0, "le besoin part de zero")

	_avancer_n_fois(colons, monde, 10)
	var apres_1s: float = colon.proprietes.urgence_elimination
	verif.v(is_equal_approx(apres_1s, _montee_par_seconde(0.0)),
		"apres 1s le besoin doit valoir exactement la montee par seconde derivee du cout_base NEGATIF (depense.gd inchange, cout negatif = reserve qui monte)")

	_avancer_n_fois(colons, monde, 10)
	verif.v(colon.proprietes.urgence_elimination > apres_1s,
		"le besoin doit continuer de monter avec le temps")
	verif.v(is_equal_approx(colon.proprietes.urgence_elimination, colon.proprietes.reserves.besoin_elimination.reserve),
		"le miroir plat 'urgence_elimination' doit valoir EXACTEMENT la reserve -- c'est la seule chose que seuil_etat.gd sait lire")

func _au_seuil_un_dechet_apparait_et_la_reserve_repart_de_zero() -> void:
	var colons := Banc.fabriquer_colons(_config_test([_colon_decl("sobre", Vector3.ZERO, 0.0)]))
	var monde = _monde_avec(colons)
	var colon := _colon_par_id(colons, "sobre")
	var ticks := _ticks_avant_premier_dechet()

	var avant := _avancer_n_fois(colons, monde, ticks - 1)
	verif.v(avant.nouveaux_dechets.is_empty(),
		"aucun dechet ne doit apparaitre TANT QUE le besoin n'a pas depasse le seuil")
	verif.v(Banc.dechets_du_monde(monde, _config.type_dechet).is_empty(),
		"le monde ne doit contenir aucun dechet avant le franchissement")

	var apres := _avancer_n_fois(colons, monde, 1, avant.compteur_dechet)
	verif.v(apres.nouveaux_dechets.size() == 1, "un dechet, et un seul, doit apparaitre au franchissement du seuil")
	verif.v(apres.nouveaux_dechets[0].colon_id == "sobre", "la trace doit nommer le colon qui a elimine")
	verif.v(Banc.dechets_du_monde(monde, _config.type_dechet).size() == 1, "le dechet doit etre enregistre dans le Monde")
	verif.v(colon.proprietes.reserves.besoin_elimination.reserve == 0.0, "la reserve doit repartir EXACTEMENT de zero")
	verif.v(colon.proprietes.urgence_elimination == 0.0, "le miroir doit repartir de zero dans le meme geste")

	var dechet: Dictionary = Banc.dechets_du_monde(monde, _config.type_dechet)[0]
	verif.v(dechet.position == Vector3.ZERO, "le dechet doit naitre A LA POSITION du colon")

	# 'doit_eliminer' n'est retire par personne a la main : c'est seuil_etat.gd
	# qui le reprend au franchissement descendant, une fois la reserve videe.
	_avancer_n_fois(colons, monde, 1, apres.compteur_dechet)
	verif.v(not colon.proprietes.etats_actifs.has("doit_eliminer"),
		"'doit_eliminer' doit etre RETIRE par seuil_etat.gd lui-meme au tick suivant (reversibilite du mecanisme, jamais un retrait code dans le cablage)")

func _qui_mange_plus_elimine_plus_souvent() -> void:
	var declarations := []
	for decl in _config.colons:
		declarations.append(decl)
	var colons := Banc.fabriquer_colons(_config_test(declarations))
	var monde = _monde_avec(colons)

	var r := _avancer_n_fois(colons, monde, 600)
	var comptes := {}
	for entree in r.nouveaux_dechets:
		comptes[entree.colon_id] = comptes.get(entree.colon_id, 0) + 1

	var glouton: String = _config.colons[0].id
	var sobre: String = _config.colons[_config.colons.size() - 1].id
	verif.v(comptes.get(glouton, 0) > comptes.get(sobre, 0),
		"le colon a taux_repas le plus eleve doit produire STRICTEMENT plus de dechets que celui a taux_repas 0.0 en 60s -- c'est le surcout_action negatif pose par le cablage, aucune ligne de mecanisme")

# TROUVE EN LANCANT LA SCENE REELLE, pas par ce fichier : un cadavre continuait
# d'eliminer (dechet a t=27.0s pour un colon mort a t=26.3s). Le gate de
# cablage sur la mort (poser_taux_elimination) ferme ce trou -- ce cas l'y
# maintient. La mort n'est PAS posee a la main ici : duree_maladie_cumulee est
# mise au-dela du seuil reel et c'est seuil_etat.gd qui pose 'mort_maladie'
# lui-meme, sans quoi son bootstrap (memoire absente -> repli sur
# etats_actifs) retirerait aussitot un etat pose sans sa grandeur.
func _un_colon_mort_n_elimine_plus() -> void:
	var colons := Banc.fabriquer_colons(_config_test([_colon_decl("cadavre", Vector3.ZERO, 0.0)]))
	var monde = _monde_avec(colons)
	var colon := _colon_par_id(colons, "cadavre")
	colon.proprietes["duree_maladie_cumulee"] = float(_config.seuil_mort) + 1.0

	var r := _avancer_n_fois(colons, monde, _ticks_avant_premier_dechet() * 3)
	verif.v(colon.proprietes.etats_actifs.has("mort_maladie"), "garde du cas : le colon doit bien etre mort")
	verif.v(r.nouveaux_dechets.is_empty(),
		"un colon MORT ne doit plus jamais eliminer, meme apres trois fois le delai d'un colon vivant -- gate de cablage sur cout_base/surcout_action, jamais une ligne de depense.gd")
	verif.v(colon.proprietes.urgence_elimination <= _montee_par_seconde(0.0) * DELTA_TICK * 2.0,
		"le besoin d'un colon mort doit rester fige (les deux taux du canal a 0.0), a un tick pres avant que la mort ne soit posee")

func _le_dechet_fabrique_porte_la_salete_de_sa_fiche_materiau() -> void:
	var dechet := Banc.fabriquer_dechet("dechet_fiche", Vector3(5.0, 5.0, 0.0), _config, _catalogues)
	verif.v(not dechet.is_empty(), "objet.gd doit accepter la fabrication du type 'dechet' (materiau et densite presents)")

	var materiaux: Dictionary = _catalogues.materiaux
	var attendu: float = float(materiaux.dechet_demo.salete_emise)
	verif.v(is_equal_approx(float(dechet.proprietes.get(_config.propriete_salete, -1.0)), attendu),
		"'salete_emise' doit etre FUSIONNEE sur l'objet depuis data/materiaux.json:dechet_demo par objet.gd, jamais un nombre recopie dans le cablage")
	verif.v(dechet.proprietes.has("densite") and dechet.proprietes.densite > 0.0,
		"un dechet reste un objet physique ordinaire : sa densite est derivee de sa composition")

# ---- Salete -----------------------------------------------------------------

func _les_dechets_font_monter_la_salete_des_colons_a_portee() -> void:
	var colons := Banc.fabriquer_colons(_config_test([_colon_decl("proche", Vector3.ZERO, 0.0)]))
	var monde = _monde_avec(colons)
	var colon := _colon_par_id(colons, "proche")
	_poser_dechets(monde, Vector3(10.0, 0.0, 0.0), 1)

	verif.v(Banc.charge_salete(colon) == 0.0, "la charge de salete part de zero")
	_avancer_n_fois(colons, monde, 10)
	var apres_1s := Banc.charge_salete(colon)
	verif.v(is_equal_approx(apres_1s, float(_catalogues.materiaux.dechet_demo.salete_emise)),
		"apres 1s a portee d'UN dechet, la charge doit valoir exactement sa salete_emise (charge.gd somme les poids des causes a portee)")

	_poser_dechets(monde, Vector3(-10.0, 0.0, 0.0), 1)
	var avant_deux := Banc.charge_salete(colon)
	_avancer_n_fois(colons, monde, 10)
	var monte_avec_deux := Banc.charge_salete(colon) - avant_deux
	verif.v(monte_avec_deux > apres_1s * 1.5,
		"deux dechets a portee doivent faire monter la charge nettement plus vite qu'un seul -- comptage IMPLICITE, charge.gd somme deja les causes")

func _un_colon_hors_portee_des_dechets_n_accumule_rien() -> void:
	var portee: float = float(_config.canal_salete.portee_charge)
	var colons := Banc.fabriquer_colons(_config_test([
		_colon_decl("proche", Vector3.ZERO, 0.0),
		_colon_decl("loin", Vector3(portee * 10.0, 0.0, 0.0), 0.0),
	]))
	var monde = _monde_avec(colons)
	_poser_dechets(monde, Vector3.ZERO, 3)

	# Fenetre volontairement plus courte que la production spontanee : les
	# seuls dechets du monde sont ceux poses ci-dessus.
	var r := _avancer_n_fois(colons, monde, _ticks_avant_premier_dechet() - 1)
	verif.v(r.nouveaux_dechets.is_empty(), "aucun dechet spontane ne doit brouiller ce cas")

	var loin := _colon_par_id(colons, "loin")
	verif.v(Banc.charge_salete(loin) == 0.0,
		"un colon hors de portee_charge ne doit accumuler AUCUNE salete, meme apres plusieurs secondes")
	verif.v(not loin.proprietes.has("expose_salete"), "un colon hors de portee n'est jamais expose")
	verif.v(not loin.proprietes.etats_actifs.has("incube_maladie"), "un colon hors de portee n'incube jamais")
	verif.v(Banc.charge_salete(_colon_par_id(colons, "proche")) > 0.0,
		"contre-epreuve : le colon reste au milieu des memes dechets, lui, s'est bien sali")

func _au_seuil_de_salete_le_colon_est_expose_puis_incube() -> void:
	var colons := Banc.fabriquer_colons(_config_test([_colon_decl("sale", Vector3.ZERO, 0.0)]))
	var monde = _monde_avec(colons)
	var colon := _colon_par_id(colons, "sale")
	_poser_dechets(monde, Vector3.ZERO, 3)

	var seuil: float = float(_config.canal_salete.seuil)
	var poids: float = float(_catalogues.materiaux.dechet_demo.salete_emise)
	var ticks := int(seuil / (3.0 * poids) / DELTA_TICK) + 2
	verif.v(ticks < _ticks_avant_premier_dechet(),
		"garde de coherence : le seuil de salete doit etre atteignable AVANT qu'un colon immobile ne produise son propre dechet, sinon ce cas ne prouve rien")

	var r := _avancer_n_fois(colons, monde, ticks)
	verif.v(r.nouveaux_exposes.has("sale"), "le franchissement du seuil de salete doit etre rendu par avancer()")
	verif.v(colon.proprietes.get("expose_salete", false),
		"charge.gd doit avoir pose le marqueur 'expose_salete' sur le colon")
	verif.v(colon.proprietes.etats_actifs.has("incube_maladie"),
		"le cablage doit relayer le marqueur vers la chaine maladie : 'incube_maladie' pose (meme entree PARTAGEE de data/etats.json que banc_maladie)")

	# Meme chaine que banc_maladie : l'incubation expire seule, les symptomes
	# suivent, la vitesse effective tombe.
	var incubation_s: float = float(_catalogues.etats.incube_maladie.duree)
	var apres := _avancer_n_fois(colons, monde, int(incubation_s / DELTA_TICK) + 2)
	verif.v(apres.nouveaux_malades.has("sale"), "a l'expiration de l'incubation, 'malade' doit etre pose")
	verif.v(colon.proprietes.etats_actifs.has("malade") and not colon.proprietes.etats_actifs.has("incube_maladie"),
		"'incube_maladie' doit avoir cede la place a 'malade'")

	var EtatEffectif = preload("res://scripts/etat_effectif.gd")
	verif.v(EtatEffectif.valeur(colon, "vitesse", _catalogues.etats) < float(_config.vitesse_base),
		"une fois malade, la vitesse effective doit etre reduite par data/etats.json:malade")

func _nettoyer_les_dechets_fait_redescendre_la_salete() -> void:
	var colons := Banc.fabriquer_colons(_config_test([_colon_decl("sale", Vector3.ZERO, 0.0)]))
	var monde = _monde_avec(colons)
	var colon := _colon_par_id(colons, "sale")
	_poser_dechets(monde, Vector3.ZERO, 2)

	_avancer_n_fois(colons, monde, 20)
	var au_sommet := Banc.charge_salete(colon)
	verif.v(au_sommet > 0.0, "la charge doit d'abord etre montee")

	monde = Banc.monde_sans_dechets(monde, _config.type_dechet)
	verif.v(Banc.dechets_du_monde(monde, _config.type_dechet).is_empty(),
		"le nettoyage doit retirer TOUS les dechets du monde")
	verif.v(monde.choses.has("sale"), "le nettoyage ne retire jamais autre chose que des dechets")

	_avancer_n_fois(colons, monde, 10)
	var apres_nettoyage := Banc.charge_salete(colon)
	verif.v(apres_nettoyage < au_sommet,
		"sans plus aucune cause a portee, la charge doit REDESCENDRE d'elle-meme (taux_decroissance de charge.gd) -- c'est ce que le clic de nettoyage rend visible")
	var taux: float = float(_config.canal_salete.taux_decroissance)
	verif.v(is_equal_approx(au_sommet - apres_nettoyage, taux),
		"la redescente doit valoir exactement taux_decroissance par seconde, jamais un chiffre invente par le cablage")

func _le_nettoyage_preserve_l_etat_des_colons_et_ne_reutilise_jamais_un_id() -> void:
	var colons := Banc.fabriquer_colons(_config_test([_colon_decl("sobre", Vector3.ZERO, 0.0)]))
	var monde = _monde_avec(colons)
	var colon := _colon_par_id(colons, "sobre")

	var r := _avancer_n_fois(colons, monde, _ticks_avant_premier_dechet())
	verif.v(r.nouveaux_dechets.size() == 1, "un dechet doit avoir ete produit")
	var premier_id: String = r.nouveaux_dechets[0].id

	colon.proprietes["urgence_elimination"] = 4.2
	monde = Banc.monde_sans_dechets(monde, _config.type_dechet)
	verif.v(monde.par_id("sobre").chose.proprietes.urgence_elimination == 4.2,
		"le Monde reconstruit doit re-ajouter les colons PAR REFERENCE -- leur etat interne traverse le nettoyage intact")

	var suite := _avancer_n_fois(colons, monde, _ticks_avant_premier_dechet(), r.compteur_dechet)
	verif.v(suite.nouveaux_dechets.size() >= 1, "le colon doit continuer a eliminer apres un nettoyage")
	verif.v(suite.nouveaux_dechets[0].id != premier_id,
		"le compteur de dechets ne doit JAMAIS repartir de zero apres un nettoyage -- monde.gd:ajouter refuse un id deja present et n'enregistrerait rien")

func _etat_courant_et_compter_etats() -> void:
	var sain := {"proprietes": {"etats_actifs": []}}
	var expose := {"proprietes": {"etats_actifs": [], "expose_salete": true}}
	var incubation := {"proprietes": {"etats_actifs": ["incube_maladie"], "expose_salete": true}}
	var malade := {"proprietes": {"etats_actifs": ["malade"]}}
	var mort := {"proprietes": {"etats_actifs": ["malade", "mort_maladie"]}}

	verif.v(Banc.etat_courant(sain) == "sain", "aucun etat, aucun marqueur -> 'sain'")
	verif.v(Banc.etat_courant(expose) == "expose", "marqueur 'expose_salete' seul -> 'expose'")
	verif.v(Banc.etat_courant(incubation) == "incubation", "'incube_maladie' l'emporte sur le marqueur de salete")
	verif.v(Banc.etat_courant(malade) == "malade", "'malade' -> 'malade'")
	verif.v(Banc.etat_courant(mort) == "mort", "'mort_maladie' l'emporte sur 'malade' encore actif")

	var compte := Banc.compter_etats([sain, expose, incubation, malade, mort, sain])
	verif.v(compte.sain == 2 and compte.expose == 1 and compte.incubation == 1 and compte.malade == 1 and compte.mort == 1,
		"compter_etats doit repartir chaque colon dans exactement une categorie")

# LE SEUL CAS QUI REJOUE data/banc_elimination_salete.json EN ENTIER -- trois
# colons a leurs positions reelles, deplacement aleatoire seede reel, canaux/
# seuils/durees reels. Assertions volontairement LARGES : une calibration doit
# rester reglable par Yael sans casser ce fichier ; ce qui est verrouille,
# c'est que la chaine DEMARRE et VA JUSQU'A LA MALADIE, jamais un compte ni un
# instant precis.
func _config_reelle_du_disque_produit_dechets_et_maladie() -> void:
	var colons := Banc.fabriquer_colons(_config)
	var monde = _monde_avec(colons)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_config.seed)

	var dechets := 0
	var exposes := 0
	var malades := 0
	var compteur := 0
	for i in 900:
		var r := Banc.avancer(colons, monde, compteur, DELTA_TICK, _config, _catalogues)
		compteur = r.compteur_dechet
		Banc.deplacer_colons(colons, _config.zone, _catalogues.etats, rng, DELTA_TICK)
		dechets += r.nouveaux_dechets.size()
		exposes += r.nouveaux_exposes.size()
		malades += r.nouveaux_malades.size()

	verif.v(dechets > 0, "la config reelle du disque doit produire des dechets en 90s -- sinon le banc n'a rien a montrer")
	verif.v(exposes > 0, "les dechets accumules doivent finir par exposer au moins un colon a la salete en 90s -- sinon le seuil du canal est hors d'atteinte, exactement la calibration morte que banc_maladie avait laissee passer")
	verif.v(malades > 0, "au moins un colon expose doit aller jusqu'aux symptomes en 90s -- sinon la chaine salete -> maladie n'est pas observable a l'ecran")
	verif.v(Banc.dechets_du_monde(monde, _config.type_dechet).size() == dechets,
		"tous les dechets produits doivent etre encore au sol -- rien ne les retire hors du clic de nettoyage")
