extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_memoire_spatiale.gd
#
# Verrouille scripts/memoire_spatiale.gd comme mecanisme GENERIQUE de souvenir
# de POSITION -- pas un code de colon, de puits ni de nuit. Chose hors domaine
# (balise_thermique_88, jamais vue ailleurs dans le depot) et percevants nommes
# `sonde_N` : ce test prouve que memoriser/avancer/position_memorisee traversent
# le meme code quelle que soit la chose retenue et quel que soit le percevant.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque (le
# catalogue est un Dictionary construit ici, jamais data/memoire_spatiale.json).
#
# CE QUE CE TEST EXISTE POUR PROUVER, au-dela des trois fonctions :
# l'erreur est DETERMINISTE (CLAUDE.md, « aucun hasard non-seede » -- et le
# depot n'a AUCUN RNG). Cent appels identiques rendent le meme nombre a la
# virgule pres, et deux percevants de forme differente devient differemment
# pour la MEME chose.

const MemoireSpatiale = preload("res://scripts/memoire_spatiale.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_memoriser_cree_lentree_avec_force_et_position(v)
	_memoriser_accumule_la_force_et_rafraichit_la_position(v)
	_avancer_fait_decroitre_la_force(v)
	_entree_sous_le_plancher_est_supprimee(v)
	_position_memorisee_rend_la_position_avec_erreur(v)
	_erreur_augmente_quand_la_force_baisse(v)
	_erreur_augmente_quand_la_luminosite_baisse(v)
	_erreur_est_deterministe(v)
	_chose_absente_rend_zero_et_erreur_infinie(v)
	_deux_formes_differentes_donnent_deux_biais_differents(v)
	_biais_nul_vise_exactement_le_souvenir(v)
	_direction_du_biais_ne_depend_pas_de_lerreur(v)
	_propriete_structurelle_absente_alarme(v)
	_catalogue_sans_defaut_alarme(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: memoire_spatiale.gd retient, oublie et rend une position biaisee de facon " +
			"deterministe, generique a toute chose inventee")
		quit(0)

func _sonde(id: String, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _catalogue() -> Dictionary:
	return {
		"defaut": {
			"force_initiale": 0.5,
			"taux_decroissance": 0.1,
			"plancher_suppression": 0.05,
			"coef_memoire_faible": 2.0,
			"coef_nuit": 1.0,
		},
	}

func _forme(biais: float) -> Dictionary:
	return {"biais": biais}

func _memoriser_cree_lentree_avec_force_et_position(v) -> void:
	var sonde := _sonde("sonde_1", {"memoire_spatiale": {}})
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3(12.0, -4.0, 0.0), _catalogue())
	var registre: Dictionary = sonde.proprietes.memoire_spatiale
	v.v(registre.has("balise_thermique_88"), "memoriser doit creer l'entree pour la chose observee")
	var entree: Dictionary = registre["balise_thermique_88"]
	v.v(is_equal_approx(float(entree.force), 0.5),
		"memoriser doit poser force_initiale du catalogue")
	v.v(entree.position.x == 12.0 and entree.position.y == -4.0 and entree.position.z == 0.0,
		"memoriser doit serialiser la position observee en {x,y,z}, jamais un Vector3")
	v.v(not (entree.position is Vector3),
		"la position stockee ne doit JAMAIS etre un Vector3 (resumabilite JSON stricte)")

func _memoriser_accumule_la_force_et_rafraichit_la_position(v) -> void:
	var sonde := _sonde("sonde_2", {"memoire_spatiale": {}})
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3(12.0, 0.0, 0.0), _catalogue())
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3(90.0, 5.0, 0.0), _catalogue())
	var entree: Dictionary = sonde.proprietes.memoire_spatiale["balise_thermique_88"]
	v.v(is_equal_approx(float(entree.force), 1.0),
		"une seconde observation doit ACCUMULER la force (+=), jamais la remplacer")
	v.v(entree.position.x == 90.0 and entree.position.y == 5.0,
		"une seconde observation doit REECRIRE la position -- sans quoi reapercevoir " +
		"ne corrigerait jamais un souvenir perime")

func _avancer_fait_decroitre_la_force(v) -> void:
	var sonde := _sonde("sonde_3", {"memoire_spatiale": {}})
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3(12.0, 0.0, 0.0), _catalogue())
	MemoireSpatiale.avancer(sonde, 2.0, _catalogue())
	var entree: Dictionary = sonde.proprietes.memoire_spatiale["balise_thermique_88"]
	v.v(is_equal_approx(float(entree.force), 0.3),
		"la force doit decroitre de taux_decroissance * delta (0.5 - 0.1 * 2.0)")
	v.v(entree.position.x == 12.0,
		"la decroissance ne doit JAMAIS deplacer la position memorisee")

func _entree_sous_le_plancher_est_supprimee(v) -> void:
	var sonde := _sonde("sonde_4", {"memoire_spatiale": {}})
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3(12.0, 0.0, 0.0), _catalogue())
	MemoireSpatiale.avancer(sonde, 5.0, _catalogue())
	var registre: Dictionary = sonde.proprietes.memoire_spatiale
	v.v(not registre.has("balise_thermique_88"),
		"une force tombee sous plancher_suppression doit RETIRER l'entree, jamais la laisser " +
		"a une valeur residuelle")

func _position_memorisee_rend_la_position_avec_erreur(v) -> void:
	var sonde := _sonde("sonde_5", {"memoire_spatiale": {}})
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3(100.0, 0.0, 0.0), _catalogue())
	# force 0.5, luminosite 1.0 -> erreur = (1 - 0.5) * 2.0 + 0.0 = 1.0
	var lu: Dictionary = MemoireSpatiale.position_memorisee(
		sonde, "balise_thermique_88", _forme(10.0), 12.0, 1.0, _catalogue())
	v.v(is_equal_approx(float(lu.force), 0.5), "la force rendue doit etre la force brute du souvenir")
	v.v(is_equal_approx(float(lu.erreur), 1.0),
		"erreur = (1-force)*coef_memoire_faible + (1-luminosite)*coef_nuit")
	var ecart: float = (lu.position as Vector3).distance_to(Vector3(100.0, 0.0, 0.0))
	v.v(is_equal_approx(ecart, 10.0),
		"la position rendue doit etre le souvenir DECALE de forme.biais * erreur (10.0 * 1.0)")
	v.v(is_equal_approx((lu.position as Vector3).z, 0.0),
		"le biais doit rester dans le plan XY, z a 0.0")

func _erreur_augmente_quand_la_force_baisse(v) -> void:
	var sonde := _sonde("sonde_6", {"memoire_spatiale": {}})
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3(100.0, 0.0, 0.0), _catalogue())
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3(100.0, 0.0, 0.0), _catalogue())
	var pleine: Dictionary = MemoireSpatiale.position_memorisee(
		sonde, "balise_thermique_88", _forme(10.0), 12.0, 1.0, _catalogue())
	MemoireSpatiale.avancer(sonde, 4.0, _catalogue())
	var usee: Dictionary = MemoireSpatiale.position_memorisee(
		sonde, "balise_thermique_88", _forme(10.0), 12.0, 1.0, _catalogue())
	v.v(float(usee.force) < float(pleine.force), "le temps doit faire baisser la force (precondition)")
	v.v(float(usee.erreur) > float(pleine.erreur),
		"l'erreur doit AUGMENTER quand la force du souvenir baisse")
	var ecart_plein: float = (pleine.position as Vector3).distance_to(Vector3(100.0, 0.0, 0.0))
	var ecart_use: float = (usee.position as Vector3).distance_to(Vector3(100.0, 0.0, 0.0))
	v.v(ecart_use > ecart_plein,
		"la position visee doit s'ecarter davantage du souvenir quand la memoire faiblit")

func _erreur_augmente_quand_la_luminosite_baisse(v) -> void:
	var sonde := _sonde("sonde_7", {"memoire_spatiale": {}})
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3(100.0, 0.0, 0.0), _catalogue())
	var jour: Dictionary = MemoireSpatiale.position_memorisee(
		sonde, "balise_thermique_88", _forme(10.0), 12.0, 1.0, _catalogue())
	var nuit: Dictionary = MemoireSpatiale.position_memorisee(
		sonde, "balise_thermique_88", _forme(10.0), 0.0, 0.0, _catalogue())
	v.v(is_equal_approx(float(jour.force), float(nuit.force)),
		"la luminosite ne doit JAMAIS toucher la force du souvenir (precondition)")
	v.v(float(nuit.erreur) > float(jour.erreur),
		"l'erreur doit AUGMENTER quand la luminosite baisse, a force egale")
	v.v(is_equal_approx(float(nuit.erreur) - float(jour.erreur), 1.0),
		"l'ecart jour/nuit doit valoir exactement coef_nuit pour une luminosite passant de 1.0 a 0.0")

# CLAUDE.md, regle non negociable : « aucun hasard non-seede » -- et le depot
# n'a AUCUN RNG. Cent appels aux memes entrees doivent rendre exactement le
# meme nombre, sans aucune tolerance : ce n'est pas une convergence, c'est une
# fonction pure.
func _erreur_est_deterministe(v) -> void:
	var sonde := _sonde("sonde_8", {"memoire_spatiale": {}})
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3(100.0, -30.0, 0.0), _catalogue())
	var reference: Dictionary = MemoireSpatiale.position_memorisee(
		sonde, "balise_thermique_88", _forme(17.0), 3.0, 0.4, _catalogue())
	var stable := true
	for _i in range(100):
		var relu: Dictionary = MemoireSpatiale.position_memorisee(
			sonde, "balise_thermique_88", _forme(17.0), 3.0, 0.4, _catalogue())
		if relu.position != reference.position or relu.erreur != reference.erreur:
			stable = false
	v.v(stable, "cent appels aux memes entrees doivent rendre EXACTEMENT la meme position et " +
		"la meme erreur -- aucun RNG, aucune derive")

func _chose_absente_rend_zero_et_erreur_infinie(v) -> void:
	var sonde := _sonde("sonde_9", {"memoire_spatiale": {}})
	var lu: Dictionary = MemoireSpatiale.position_memorisee(
		sonde, "balise_thermique_88", _forme(10.0), 12.0, 1.0, _catalogue())
	v.v(lu.position == Vector3.ZERO, "une chose jamais memorisee doit rendre Vector3.ZERO")
	v.v(float(lu.force) == 0.0, "une chose jamais memorisee doit rendre une force de 0.0")
	v.v(lu.erreur == INF,
		"une chose jamais memorisee doit rendre une erreur INFINIE -- « je ne sais pas » ne se " +
		"confond jamais avec « je sais tres mal »")

func _deux_formes_differentes_donnent_deux_biais_differents(v) -> void:
	var souvenir := Vector3(100.0, 0.0, 0.0)
	var calme := _sonde("sonde_10", {"memoire_spatiale": {}})
	var agitee := _sonde("sonde_11", {"memoire_spatiale": {}})
	MemoireSpatiale.memoriser(calme, "balise_thermique_88", souvenir, _catalogue())
	MemoireSpatiale.memoriser(agitee, "balise_thermique_88", souvenir, _catalogue())
	var lu_calme: Dictionary = MemoireSpatiale.position_memorisee(
		calme, "balise_thermique_88", _forme(5.0), 12.0, 1.0, _catalogue())
	var lu_agitee: Dictionary = MemoireSpatiale.position_memorisee(
		agitee, "balise_thermique_88", _forme(40.0), 12.0, 1.0, _catalogue())
	v.v(is_equal_approx(float(lu_calme.erreur), float(lu_agitee.erreur)),
		"forme.biais ne doit pas toucher l'erreur elle-meme -- il ne dit que de COMBIEN on devie")
	v.v(lu_calme.position != lu_agitee.position,
		"deux percevants de forme differente doivent viser deux points differents pour la MEME chose")
	var ecart_calme: float = (lu_calme.position as Vector3).distance_to(souvenir)
	var ecart_agitee: float = (lu_agitee.position as Vector3).distance_to(souvenir)
	v.v(ecart_agitee > ecart_calme, "un percevant a plus fort biais doit devier davantage")

func _biais_nul_vise_exactement_le_souvenir(v) -> void:
	var sonde := _sonde("sonde_12", {"memoire_spatiale": {}})
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3(100.0, -8.0, 0.0), _catalogue())
	var lu: Dictionary = MemoireSpatiale.position_memorisee(
		sonde, "balise_thermique_88", {}, 0.0, 0.0, _catalogue())
	v.v(lu.position == Vector3(100.0, -8.0, 0.0),
		"une forme sans cle 'biais' (defaut 0.0) doit viser exactement le souvenir, meme de nuit " +
		"-- point neutre legitime, jamais une alarme")
	v.v(float(lu.erreur) > 0.0,
		"l'erreur reste calculee et non nulle : ne pas devier n'est pas ne pas se tromper")

# La DIRECTION est une propriete de la CHOSE (hash de son id), l'AMPLITUDE une
# propriete du percevant : quand l'erreur grandit, le souvenir vise doit
# s'eloigner LE LONG DE LA MEME DROITE, jamais tourner. Sans ca, la cible
# tremblerait d'un tick a l'autre.
func _direction_du_biais_ne_depend_pas_de_lerreur(v) -> void:
	var souvenir := Vector3(100.0, 0.0, 0.0)
	var sonde := _sonde("sonde_13", {"memoire_spatiale": {}})
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", souvenir, _catalogue())
	var faible: Dictionary = MemoireSpatiale.position_memorisee(
		sonde, "balise_thermique_88", _forme(10.0), 12.0, 1.0, _catalogue())
	var forte: Dictionary = MemoireSpatiale.position_memorisee(
		sonde, "balise_thermique_88", _forme(10.0), 0.0, 0.0, _catalogue())
	var dir_faible: Vector3 = ((faible.position as Vector3) - souvenir).normalized()
	var dir_forte: Vector3 = ((forte.position as Vector3) - souvenir).normalized()
	v.v(dir_faible.distance_to(dir_forte) < 0.0001,
		"la direction du biais doit rester la meme quand l'erreur grandit -- elle derive de " +
		"chose_id, jamais de l'erreur")

func _propriete_structurelle_absente_alarme(v) -> void:
	var sonde := _sonde("sonde_14", {})
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3.ONE, _catalogue())
	v.v(not sonde.proprietes.has("memoire_spatiale"),
		"proprietes sans la cle structurelle 'memoire_spatiale' ne doit rien ecrire " +
		"(alarme, pas defaut silencieux)")
	MemoireSpatiale.avancer(sonde, 1.0, _catalogue())
	var lu: Dictionary = MemoireSpatiale.position_memorisee(
		sonde, "balise_thermique_88", _forme(10.0), 12.0, 1.0, _catalogue())
	v.v(lu.erreur == INF and lu.position == Vector3.ZERO,
		"position_memorisee sur une entite sans cle structurelle doit alarmer et rendre le repli " +
		"d'absence")

func _catalogue_sans_defaut_alarme(v) -> void:
	var sonde := _sonde("sonde_15", {"memoire_spatiale": {}})
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3.ONE, {})
	v.v(sonde.proprietes.memoire_spatiale.is_empty(),
		"un catalogue sans entree 'defaut' doit alarmer et ne rien memoriser")
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3(50.0, 0.0, 0.0), _catalogue())
	MemoireSpatiale.avancer(sonde, 100.0, {})
	v.v(is_equal_approx(float(sonde.proprietes.memoire_spatiale["balise_thermique_88"].force), 0.5),
		"un catalogue sans entree 'defaut' doit alarmer et laisser le registre INTACT")
	var lu: Dictionary = MemoireSpatiale.position_memorisee(
		sonde, "balise_thermique_88", _forme(10.0), 12.0, 1.0, {})
	v.v(lu.erreur == INF, "position_memorisee sur un catalogue sans 'defaut' doit rendre le repli d'absence")

# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# proprietes.memoire_spatiale ne doit porter que du JSON pur -- aucun Vector3,
# aucun Callable -- et redonner exactement la meme structure apres un
# aller-retour JSON.stringify/parse_string. C'est la seule raison pour laquelle
# la position est stockee en {x,y,z} et non en Vector3.
func _resumabilite_json_stricte(v) -> void:
	var sonde := _sonde("sonde_16", {
		"position": {"x": 1.0, "y": 0.0, "z": 2.0},
		"memoire_spatiale": {},
	})
	MemoireSpatiale.memoriser(sonde, "balise_thermique_88", Vector3(7.0, -3.0, 0.0), _catalogue())
	MemoireSpatiale.avancer(sonde, 1.0, _catalogue())
	var texte := JSON.stringify(sonde)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	var origine: Dictionary = sonde.proprietes.memoire_spatiale["balise_thermique_88"]
	var copie: Dictionary = relu.proprietes.memoire_spatiale["balise_thermique_88"]
	v.v(is_equal_approx(float(copie.force), float(origine.force)),
		"la force doit survivre identique a l'aller-retour JSON")
	v.v(copie.position.x == 7.0 and copie.position.y == -3.0 and copie.position.z == 0.0,
		"la position memorisee doit survivre identique a l'aller-retour JSON, jamais un Vector3")
