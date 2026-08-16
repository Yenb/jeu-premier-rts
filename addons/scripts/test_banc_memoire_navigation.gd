extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_memoire_navigation.gd
#
# Verrouille scripts/banc_memoire_navigation.gd -- le CHEMIN REEL du chantier
# « memoire spatiale + navigation par memoire ». A la difference de
# test_memoire_spatiale.gd (hors domaine, mecanisme seul, catalogue invente),
# CE test rejoue les VRAIS fichiers du disque : data/banc_memoire_navigation.json,
# data/memoire_spatiale.json, data/canaux.json, data/lumiere.json. Lecon de
# banc_maladie, deja payee une fois : un banc dont le test invente sa propre
# calibration reste VERT pendant que la scene reelle ne franchit jamais rien.
#
# CE QUE CE TEST VERROUILLE, et qu'aucun autre ne verrouillerait :
# 1. le colon memorise la position OBSERVEE, jamais une position relue ;
# 2. hors de portee, le souvenir NE SUIT PAS le puits qui bouge -- c'est tout
#    le sujet du chantier, et c'est exactement ce que lien_personnel_attraction.gd
#    fait a l'envers (position reelle relue vivante a chaque tick) ;
# 3. le colon marche vers le SOUVENIR, pas vers le reel ;
# 4. la nuit augmente l'erreur a memoire egale ;
# 5. le temps qui passe finit par effacer le souvenir, et le colon s'arrete ;
# 6. reapercevoir REECRIT la position et fait redescendre l'erreur ;
# 7. la calibration declaree en donnee rend le banc observable (portees et
#    distances reelles), sans quoi les six points ci-dessus seraient vrais et
#    la scene ne montrerait rien ;
# 8. le pas complet est DETERMINISTE -- aucun RNG, nulle part.

const Banc = preload("res://scripts/banc_memoire_navigation.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

var _config: Dictionary = {}
var _canaux: Dictionary = {}
var _lumiere: Dictionary = {}
var _memoire: Dictionary = {}

func _init() -> void:
	_config = _charger("res://data/banc_memoire_navigation.json")
	_canaux = _charger("res://data/canaux.json")
	_lumiere = _charger("res://data/lumiere.json")
	_memoire = _charger("res://data/memoire_spatiale.json")

	var v := Verif.new()
	_calibration_declaree_rend_le_banc_observable(v)
	_heure_et_luminosite_viennent_de_la_bascule(v)
	_position_puits_rend_trois_positions_distinctes(v)
	_a_portee_le_colon_memorise_la_position_observee(v)
	_hors_portee_le_souvenir_ne_suit_pas_le_puits(v)
	_le_colon_marche_vers_le_souvenir_pas_vers_le_reel(v)
	_la_nuit_augmente_lerreur_a_memoire_egale(v)
	_le_temps_accelere_efface_plus_vite(v)
	_souvenir_oublie_le_colon_sarrete(v)
	_reapercevoir_reecrit_la_position_et_baisse_lerreur(v)
	_plafonner_memoire_ecrete_la_force(v)
	_le_pas_complet_est_deterministe(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_memoire_navigation.gd -- le colon retient ou il a vu le puits, vise ce " +
			"souvenir hors de portee, se perd la nuit et quand il oublie, et se corrige en reapercevant")
		quit(0)

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _scene() -> Dictionary:
	var colon := Banc.construire_colon(_config)
	var puits := Banc.construire_puits(_config)
	var monde = Monde.new()
	monde.ajouter(colon, String(_config.colon.type), colon.position)
	monde.ajouter(puits, String(_config.puits.type), puits.position)
	return {"colon": colon, "puits": puits, "monde": monde}

func _pas(scene: Dictionary, nuit: bool, accelere: bool, reperception: bool, temps: float, delta: float) -> Dictionary:
	return Banc.avancer(
		scene.colon, scene.puits, scene.monde, _config,
		_canaux, _lumiere, _memoire,
		nuit, accelere, reperception, temps, delta)

func _boucle(scene: Dictionary, nuit: bool, accelere: bool, reperception: bool, depart: float, pas: int, delta: float) -> Dictionary:
	var bilan: Dictionary = {}
	for i in range(pas):
		bilan = _pas(scene, nuit, accelere, reperception, depart + float(i) * delta, delta)
	return bilan

func _vec(brut: Array) -> Vector3:
	return Vector3(brut[0], brut[1], brut[2])

# La calibration DECLAREE doit rendre le banc observable. Sans ce cas, une
# retouche de data/banc_memoire_navigation.json (une portee, une position)
# laisserait tous les autres cas VERTS pendant que la scene ne montrerait plus
# rien : le puits jamais vu, ou jamais perdu de vue.
func _calibration_declaree_rend_le_banc_observable(v) -> void:
	var portee: float = float(_config.colon.portee_vue)
	var depart := _vec(_config.colon.position)
	var initiale := _vec(_config.puits.position_initiale)
	var lointaine := _vec(_config.puits.position_lointaine)
	var proche := _vec(_config.puits.position_proche)
	v.v(depart.distance_to(initiale) < portee,
		"le puits doit etre A PORTEE de vue au depart, sans quoi rien n'est jamais memorise")
	v.v(initiale.distance_to(lointaine) > portee,
		"le puits eloigne doit sortir de la portee de vue MEME quand le colon a fini sa marche " +
		"vers le souvenir")
	v.v(initiale.distance_to(proche) > 1.0,
		"la position de reperception doit differer de la position de depart -- sinon on ne verrait " +
		"qu'un renforcement, jamais une REECRITURE du souvenir")
	v.v(initiale.distance_to(proche) < portee,
		"le puits rapproche doit etre a portee du colon arrive a son souvenir, sans quoi la " +
		"bascule REPERCEVOIR ne corrige jamais rien")
	v.v(float(_config.facteur_temps_accelere) > float(_config.facteur_temps_normal),
		"le temps accelere doit reellement etre plus rapide que le temps normal")

func _heure_et_luminosite_viennent_de_la_bascule(v) -> void:
	var jour := Banc.heure_du_jour(false, 0.0, _config)
	var nuit := Banc.heure_du_jour(true, 0.0, _config)
	v.v(jour != nuit, "les deux bascules doivent poser deux heures differentes")
	v.v(is_equal_approx(Banc.heure_du_jour(false, 999.0, _config), jour),
		"avec duree_jour_secondes a 0.0, horloge.gd doit rendre l'heure de depart quel que soit " +
		"le temps ecoule -- le jour est volontairement fige pour separer les deux causes d'erreur")
	var lum_jour := Banc.luminosite_a(jour, _config, _lumiere)
	var lum_nuit := Banc.luminosite_a(nuit, _config, _lumiere)
	v.v(is_equal_approx(lum_jour, 1.0),
		"a la latitude declaree, l'heure de jour doit rendre une luminosite de 1.0 (lumiere.gd:soleil)")
	v.v(is_equal_approx(lum_nuit, 0.0),
		"l'heure de nuit doit rendre une luminosite de 0.0, sans quoi les deux causes d'erreur se melangent")

func _position_puits_rend_trois_positions_distinctes(v) -> void:
	var avant := Banc.position_puits(false, 0.0, _config)
	var apres := Banc.position_puits(false, float(_config.delai_deplacement) + 1.0, _config)
	var rapproche := Banc.position_puits(true, float(_config.delai_deplacement) + 1.0, _config)
	v.v(avant == _vec(_config.puits.position_initiale), "avant le delai, le puits est a sa position de depart")
	v.v(apres == _vec(_config.puits.position_lointaine), "apres le delai, le puits s'est eloigne")
	v.v(rapproche == _vec(_config.puits.position_proche),
		"la bascule REPERCEVOIR doit gagner sur le delai, a tout instant")

func _a_portee_le_colon_memorise_la_position_observee(v) -> void:
	var scene := _scene()
	var bilan := _pas(scene, false, false, false, 0.0, 0.1)
	v.v(bool(bilan.percu), "le puits a portee doit etre percu")
	v.v(bool(bilan.souvenir_connu), "un puits percu doit former un souvenir")
	var registre: Dictionary = scene.colon.proprietes.memoire_spatiale
	v.v(registre.has(String(_config.puits.id)), "le registre doit porter une entree pour le puits")
	var memorisee: Dictionary = registre[String(_config.puits.id)].position
	var attendue := _vec(_config.puits.position_initiale)
	v.v(is_equal_approx(float(memorisee.x), attendue.x) and is_equal_approx(float(memorisee.y), attendue.y),
		"la position memorisee doit etre celle qui a ete OBSERVEE, jamais une position relue ailleurs")
	v.v(float(bilan.erreur) < INF, "un souvenir forme doit rendre une erreur finie")

# LE POINT DU CHANTIER. lien_personnel_attraction.gd relit
# `wrapper.chose.position` a chaque tick : sa cible SUIT le puits qui bouge.
# Ici le souvenir reste ou il etait, et l'ecart au reel se creuse.
func _hors_portee_le_souvenir_ne_suit_pas_le_puits(v) -> void:
	var scene := _scene()
	_boucle(scene, false, false, false, 0.0, 10, 0.1)
	var memorisee_avant: Dictionary = (scene.colon.proprietes.memoire_spatiale[String(_config.puits.id)].position as Dictionary).duplicate()
	var bilan := _boucle(scene, false, false, false, float(_config.delai_deplacement), 20, 0.1)
	v.v(not bool(bilan.percu), "le puits eloigne ne doit plus etre percu")
	var memorisee_apres: Dictionary = scene.colon.proprietes.memoire_spatiale[String(_config.puits.id)].position
	v.v(is_equal_approx(float(memorisee_avant.y), float(memorisee_apres.y)),
		"le souvenir ne doit PAS suivre le puits qui bouge hors de portee -- c'est exactement la " +
		"telepathie que ce chantier ferme")
	v.v(float(bilan.ecart_reel_memorise) > float(_config.colon.portee_vue),
		"l'ecart entre le reel et le memorise doit depasser la portee de vue une fois le puits parti")

func _le_colon_marche_vers_le_souvenir_pas_vers_le_reel(v) -> void:
	var scene := _scene()
	_boucle(scene, false, false, false, 0.0, 10, 0.1)
	var bilan := _boucle(scene, false, false, false, float(_config.delai_deplacement), 100, 0.1)
	var souvenir := _vec(_config.puits.position_initiale)
	var reel: Vector3 = bilan.position_reelle
	v.v(scene.colon.position.distance_to(souvenir) < scene.colon.position.distance_to(reel),
		"le colon doit se rapprocher de son SOUVENIR, jamais de la position reelle du puits")
	v.v(scene.colon.position.distance_to(reel) > float(_config.colon.portee_vue),
		"le colon ne doit jamais retrouver le puits par hasard en suivant son souvenir")

func _la_nuit_augmente_lerreur_a_memoire_egale(v) -> void:
	var de_jour := _scene()
	var de_nuit := _scene()
	_boucle(de_jour, false, false, false, 0.0, 10, 0.1)
	_boucle(de_nuit, false, false, false, 0.0, 10, 0.1)
	var bilan_jour := _pas(de_jour, false, false, false, float(_config.delai_deplacement), 0.1)
	var bilan_nuit := _pas(de_nuit, true, false, false, float(_config.delai_deplacement), 0.1)
	v.v(is_equal_approx(float(bilan_jour.force), float(bilan_nuit.force)),
		"les deux colons doivent avoir la MEME force de souvenir (precondition)")
	v.v(float(bilan_nuit.erreur) > float(bilan_jour.erreur),
		"a memoire egale, la nuit doit augmenter l'erreur de navigation")
	v.v(float(bilan_nuit.ecart_reel_memorise) != float(bilan_jour.ecart_reel_memorise),
		"une erreur plus grande doit deplacer le point reellement vise")

func _le_temps_accelere_efface_plus_vite(v) -> void:
	var normal := _scene()
	var rapide := _scene()
	_boucle(normal, false, false, false, 0.0, 10, 0.1)
	_boucle(rapide, false, false, false, 0.0, 10, 0.1)
	var depart := float(_config.delai_deplacement)
	var bilan_normal := _boucle(normal, false, false, false, depart, 20, 0.1)
	var bilan_rapide := _boucle(rapide, false, true, false, depart, 20, 0.1)
	v.v(float(bilan_rapide.force) < float(bilan_normal.force),
		"le temps accelere doit faire decroitre la force du souvenir plus vite")
	v.v(float(bilan_rapide.erreur) > float(bilan_normal.erreur),
		"une force plus basse doit rendre une erreur plus grande")

# Ne pas savoir n'est pas savoir mal : sous le plancher, l'entree est RETIREE,
# l'erreur devient INF, et le colon s'arrete au lieu de foncer sur Vector3.ZERO.
func _souvenir_oublie_le_colon_sarrete(v) -> void:
	var scene := _scene()
	_boucle(scene, false, false, false, 0.0, 10, 0.1)
	var depart := float(_config.delai_deplacement)
	var bilan := _boucle(scene, false, true, false, depart, 300, 0.1)
	v.v(not bool(bilan.souvenir_connu),
		"apres assez de temps accelere, le souvenir doit etre OUBLIE (retire sous le plancher)")
	v.v(bilan.erreur == INF, "un souvenir oublie doit rendre une erreur INFINIE, jamais un grand nombre")
	v.v(not scene.colon.proprietes.memoire_spatiale.has(String(_config.puits.id)),
		"l'entree doit avoir ete RETIREE du registre, jamais laissee a une valeur residuelle")
	var avant: Vector3 = scene.colon.position
	_boucle(scene, false, true, false, depart + 30.0, 20, 0.1)
	v.v(scene.colon.position == avant,
		"sans souvenir, le colon ne doit plus bouger du tout -- jamais marcher vers Vector3.ZERO")

func _reapercevoir_reecrit_la_position_et_baisse_lerreur(v) -> void:
	var scene := _scene()
	_boucle(scene, false, false, false, 0.0, 10, 0.1)
	var depart := float(_config.delai_deplacement)
	var use := _boucle(scene, false, true, false, depart, 15, 0.1)
	var corrige := _boucle(scene, false, true, true, depart + 2.0, 15, 0.1)
	v.v(float(use.force) < float(_config.plafond_force),
		"le souvenir doit s'etre affaibli avant la correction (precondition)")
	v.v(bool(corrige.percu), "le puits rapproche doit redevenir percu")
	v.v(float(corrige.force) > float(use.force), "reapercevoir doit RENFORCER le souvenir")
	v.v(float(corrige.erreur) < float(use.erreur), "reapercevoir doit faire REDESCENDRE l'erreur")
	var memorisee: Dictionary = scene.colon.proprietes.memoire_spatiale[String(_config.puits.id)].position
	var attendue := _vec(_config.puits.position_proche)
	v.v(is_equal_approx(float(memorisee.x), attendue.x) and is_equal_approx(float(memorisee.y), attendue.y),
		"reapercevoir doit REECRIRE la position memorisee sur la nouvelle position observee")

func _plafonner_memoire_ecrete_la_force(v) -> void:
	var scene := _scene()
	var registre: Dictionary = scene.colon.proprietes.memoire_spatiale
	registre[String(_config.puits.id)] = {"position": {"x": 0.0, "y": 0.0, "z": 0.0}, "force": 5.0}
	var ecrete := Banc.plafonner_memoire(scene.colon, _config)
	v.v(is_equal_approx(Banc.force_memorisee(scene.colon, String(_config.puits.id)), float(_config.plafond_force)),
		"plafonner_memoire doit ecreter la force au plafond -- le coeur ne borne jamais le haut")
	v.v(is_equal_approx(ecrete, 5.0 - float(_config.plafond_force)),
		"plafonner_memoire doit rendre le total ecrete, pour la trace")
	var bilan := _boucle(scene, false, false, false, 0.0, 60, 0.1)
	v.v(float(bilan.force) <= float(_config.plafond_force) + 0.0001,
		"la force ne doit JAMAIS depasser le plafond, meme apres soixante observations d'affilee")

# CLAUDE.md, regle non negociable : « aucun hasard non-seede » -- et le depot
# n'a AUCUN RNG. Deux scenes identiques avancees a l'identique doivent finir
# exactement au meme endroit, au bit pres.
func _le_pas_complet_est_deterministe(v) -> void:
	var a := _scene()
	var b := _scene()
	var bilan_a := _boucle(a, true, true, false, 0.0, 80, 0.1)
	var bilan_b := _boucle(b, true, true, false, 0.0, 80, 0.1)
	v.v(a.colon.position == b.colon.position,
		"deux scenes identiques doivent laisser le colon EXACTEMENT au meme endroit")
	v.v(bilan_a.erreur == bilan_b.erreur and bilan_a.force == bilan_b.force,
		"deux scenes identiques doivent rendre exactement la meme erreur et la meme force")
	v.v(bilan_a.cible == bilan_b.cible, "deux scenes identiques doivent viser exactement le meme point")
