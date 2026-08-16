extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_fertilite.gd
#
# Verrouille le CABLAGE de scripts/banc_fertilite.gd (grille de terrain,
# zones, baisse par recolte, remontee par legumineuse, transfert conserve
# depuis un cadavre, transformation terminale en humus, jachere, plafond) --
# jamais les mecanismes du coeur eux-memes, tous deja verrouilles ailleurs
# (test_depense.gd/test_flux.gd/test_consommer.gd/test_produit.gd).
#
# Charge les VRAIES donnees du disque (data/banc_fertilite.json,
# data/materiaux.json, data/types.json, data/transformations.json,
# data/etats.json) plutot qu'une config locale : ce banc tourne deja en 4x4,
# le test verrouille donc exactement ce que Yael verra a l'ecran, calibration
# comprise -- une valeur changee en donnee fait rougir ce test, jamais
# derailler le banc en silence.

const BancFertilite = preload("res://scripts/banc_fertilite.gd")
const Verif = preload("res://scripts/verif.gd")

const EPSILON := 0.0001

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _etats: Dictionary = {}
var _types_partages: Dictionary = {}
var _proprietes_immuables: Array = []
var _config_produire: Dictionary = {}
var _catalogue_types: Dictionary = {}

func _init() -> void:
	_charger()

	var v := Verif.new()
	_la_grille_pose_seize_cases_a_la_fertilite_initiale(v)
	_les_zones_suivent_exactement_la_donnee(v)
	_la_recolte_fait_baisser_la_fertilite(v)
	_la_recolte_ne_se_lance_que_sur_une_case_de_recolte(v)
	_la_legumineuse_fait_remonter_la_fertilite(v)
	_le_cadavre_transfere_sa_matiere_organique_a_la_case_sous_lui(v)
	_le_cadavre_epuise_se_transforme_en_humus_et_cesse_de_donner(v)
	_la_jachere_remonte_lentement(v)
	_une_case_sans_source_reste_stable(v)
	_la_fertilite_ne_depasse_jamais_la_capacite(v)

	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_fertilite.gd fait descendre la fertilite par la recolte (depense.gd), " +
			"la fait remonter par la legumineuse (flux.gd) et par un cadavre dont la perte " +
			"est exactement le gain du sol (consommer.gd), transforme le cadavre epuise en " +
			"humus (produit.gd), refait la jachere par un cout_base negatif, laisse stable " +
			"une case sans source, et ne depasse jamais la capacite")
		quit(0)

func _charger() -> void:
	_config = _json("res://data/banc_fertilite.json")
	_materiaux = _json("res://data/materiaux.json")
	_etats = _json("res://data/etats.json")
	_types_partages = _json("res://data/types.json")
	_proprietes_immuables = _json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var transformations: Dictionary = _json("res://data/transformations.json").get("transformations", {})
	_config_produire = transformations.get(_config.transformation_terminale, {}).get("a_zero", {}).get("produire", {})

	_catalogue_types = _config.get("types", {}).duplicate(true)
	_catalogue_types["objet_physique"] = _types_partages.get("objet_physique", {})
	var type_produit: String = _config_produire.get("type_produit", "")
	_catalogue_types[type_produit] = _types_partages.get(type_produit, {})

func _json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

# Un pas complet du banc, exactement celui que _process appelle.
func _pas(cases: Array, sources: Array, delta: float) -> Dictionary:
	return BancFertilite.avancer(cases, sources, _config, _etats, _catalogue_types, _materiaux, _config_produire, delta)

func _cases() -> Array:
	return BancFertilite.construire_grille(_config)

func _sources() -> Array:
	return BancFertilite.fabriquer_sources(_config, _catalogue_types, _materiaux, _proprietes_immuables)

func _case(cases: Array, id: String) -> Dictionary:
	for case in cases:
		if case.id == id:
			return case
	return {}

func _source(sources: Array, id: String) -> Dictionary:
	for source in sources:
		if source.id == id:
			return source
	return {}

func _fertilite(cases: Array, id: String) -> float:
	return float(_case(cases, id).proprietes.reserves[_config.nom_reserve].reserve)

func _matiere(source: Dictionary) -> float:
	return float(source.proprietes.get("reserves", {}).get(_config.nom_reserve_cadavre, {}).get("reserve", 0.0))

# ---- Assertions ----

func _la_grille_pose_seize_cases_a_la_fertilite_initiale(v) -> void:
	var cases := _cases()
	v.v(cases.size() == 16, "une grille 4x4 doit contenir exactement 16 cases, recu %d" % cases.size())
	for case in cases:
		var canal: Dictionary = case.proprietes.reserves[_config.nom_reserve]
		v.v(is_equal_approx(float(canal.reserve), float(_config.fertilite_initiale)),
			"%s doit partir a fertilite_initiale (%.1f), recu %.2f" % [case.id, _config.fertilite_initiale, canal.reserve])
		v.v(is_equal_approx(float(canal.capacite), float(_config.capacite)),
			"%s doit porter la capacite en donnee sur son canal" % case.id)
		v.v(case.proprietes.get(_config.propriete_sol, false),
			"%s doit porter la propriete receptrice de flux.gd ('%s')" % [case.id, _config.propriete_sol])

func _les_zones_suivent_exactement_la_donnee(v) -> void:
	var cases := _cases()
	v.v(_case(cases, "case_0_0").proprietes.zone == "recolte", "case_0_0 doit etre en zone recolte")
	v.v(_case(cases, "case_0_2").proprietes.zone == "legumineuse", "case_0_2 doit etre en zone legumineuse")
	v.v(_case(cases, "case_3_0").proprietes.zone == "cadavre", "case_3_0 doit etre en zone cadavre")
	v.v(_case(cases, "case_2_2").proprietes.zone == String(_config.zone_defaut),
		"une case non listee dans config.zones doit retomber sur la zone par defaut (jachere)")
	var comptes: Dictionary = {}
	for case in cases:
		var zone: String = case.proprietes.zone
		comptes[zone] = int(comptes.get(zone, 0)) + 1
	v.v(comptes.get("recolte", 0) == 2 and comptes.get("legumineuse", 0) == 2 and comptes.get("cadavre", 0) == 2,
		"les trois zones nommees doivent porter exactement 2 cases chacune, recu %s" % str(comptes))
	v.v(comptes.get(String(_config.zone_defaut), 0) == 10,
		"les 10 cases restantes doivent etre en jachere, recu %d" % comptes.get(String(_config.zone_defaut), 0))

func _la_recolte_fait_baisser_la_fertilite(v) -> void:
	var cases := _cases()
	var sources := _sources()
	var case_recoltee := _case(cases, "case_0_0")
	var case_temoin := _case(cases, "case_1_0")

	# La recolte est ACTIVE des la construction (recolte_active_au_depart) :
	# le banc s'ouvre sur la chute, le clic l'arrete puis la relance.
	v.v(is_equal_approx(float(case_recoltee.proprietes.reserves[_config.nom_reserve].surcout_action), float(_config.surcout_recolte)),
		"une case de recolte doit porter surcout_recolte des la construction")
	v.v(BancFertilite.source_active(case_recoltee, sources, _config) == "recolte",
		"une case en cours de recolte doit afficher la recolte comme source active")

	var avant := _fertilite(cases, "case_0_0")
	for i in range(20):
		_pas(cases, sources, 0.5)
	var apres := _fertilite(cases, "case_0_0")
	v.v(apres < avant - 1.0, "10s de recolte doivent faire chuter la fertilite (%.2f -> %.2f)" % [avant, apres])
	var attendu: float = avant - (float(_config.surcout_recolte) + float(_config.cout_base_par_zone.recolte)) * 10.0
	v.v(abs(apres - attendu) < EPSILON,
		"la chute doit valoir exactement (surcout_recolte + cout_base)*duree (%.3f attendu, %.3f recu)" % [attendu, apres])

	# Le clic ARRETE la recolte : le surcout retombe a zero, la case se refait
	# par son seul cout_base negatif, pendant que l'autre case continue de
	# chuter -- deux cases de la meme zone, deux etats independants.
	v.v(BancFertilite.basculer_recolte(case_recoltee, _config), "le toggle doit accepter une case de zone recolte")
	var creux := _fertilite(cases, "case_0_0")
	var temoin_avant := _fertilite(cases, "case_1_0")
	for i in range(10):
		_pas(cases, sources, 0.5)
	v.v(_fertilite(cases, "case_0_0") > creux,
		"une recolte arretee doit laisser la case se refaire (%.2f -> %.2f)" % [creux, _fertilite(cases, "case_0_0")])
	v.v(_fertilite(cases, "case_1_0") < temoin_avant,
		"la seconde case de recolte, jamais basculee, doit continuer de chuter")
	v.v(is_equal_approx(float(case_temoin.proprietes.reserves[_config.nom_reserve].surcout_action), float(_config.surcout_recolte)),
		"basculer une case ne doit jamais toucher le surcout d'une autre")

	# Re-cliquer relance la recolte : le toggle marche dans les deux sens.
	BancFertilite.basculer_recolte(case_recoltee, _config)
	var reprise := _fertilite(cases, "case_0_0")
	for i in range(10):
		_pas(cases, sources, 0.5)
	v.v(_fertilite(cases, "case_0_0") < reprise,
		"une recolte relancee doit refaire chuter la case (%.2f)" % reprise)

func _la_recolte_ne_se_lance_que_sur_une_case_de_recolte(v) -> void:
	var cases := _cases()
	var jachere := _case(cases, "case_2_2")
	v.v(not BancFertilite.basculer_recolte(jachere, _config),
		"le toggle doit refuser une case de jachere")
	v.v(is_equal_approx(float(jachere.proprietes.reserves[_config.nom_reserve].surcout_action), 0.0),
		"une case refusee ne doit porter aucun surcout")

func _la_legumineuse_fait_remonter_la_fertilite(v) -> void:
	var cases := _cases()
	var sources := _sources()
	var legumineuse := _source(sources, "legumineuse_0")
	v.v(not legumineuse.is_empty() and legumineuse.proprietes.get(_config.propriete_fixation, false),
		"la legumineuse doit etre fabriquee et porter la propriete source de flux.gd")

	var avant := _fertilite(cases, "case_0_2")
	_pas(cases, sources, 0.5)
	var gain := _fertilite(cases, "case_0_2") - avant
	var attendu: float = float(legumineuse.proprietes.taux_flux) * 0.5
	v.v(abs(gain - attendu) < EPSILON,
		"une case sous la legumineuse doit gagner taux_flux*delta (%.3f attendu, %.3f recu)" % [attendu, gain])
	v.v(BancFertilite.source_active(_case(cases, "case_1_2"), sources, _config) == "legumineuse",
		"les DEUX cases de la zone legumineuse doivent etre a portee de la source")

	# flux.gd NE DEPLETE JAMAIS sa source : la legumineuse fixe l'azote de
	# l'air, elle ne se vide pas (difference doctrinale avec consommer.gd).
	v.v(not legumineuse.proprietes.has("reserves"),
		"la legumineuse ne doit porter aucune reserve a vider -- flux.gd ne deplete jamais sa source")

	# Une case hors de portee_flux ne recoit rien de la legumineuse.
	var hors_portee := _case(cases, "case_0_1")
	v.v(BancFertilite.source_active(hors_portee, sources, _config) == "aucune",
		"une case voisine hors de portee_flux ne doit voir aucune source active")

func _le_cadavre_transfere_sa_matiere_organique_a_la_case_sous_lui(v) -> void:
	var cases := _cases()
	var sources := _sources()
	var cadavre := _source(sources, "cadavre_0")
	v.v(float(cadavre.proprietes.get("masse", 0.0)) > 0.0,
		"le cadavre doit porter une masse REELLE calculee par Objet.fabriquer (requise par produit.gd)")

	var case_dessous: Variant = BancFertilite.case_sous(cadavre, cases, float(_config.portee_appariement))
	v.v(case_dessous != null and case_dessous.id == "case_3_0",
		"l'appariement doit trouver la case exactement sous le cadavre")

	var matiere_avant := _matiere(cadavre)
	var fertilite_avant := _fertilite(cases, "case_3_0")
	BancFertilite.avancer_cadavres(sources, cases, _config, _etats, 0.5)
	var perdu := matiere_avant - _matiere(cadavre)
	var gagne := _fertilite(cases, "case_3_0") - fertilite_avant

	v.v(perdu > 0.0, "le cadavre doit perdre de la matiere organique (%.3f)" % perdu)
	v.v(abs(perdu - gagne) < EPSILON,
		"TRANSFERT CONSERVE : le sol doit gagner exactement ce que le cadavre perd (%.6f perdu, %.6f gagne)" % [perdu, gagne])

	var attendu: float = float(_config.taux_decomposition_base) * float(_materiaux.cadavre_demo.biodegradabilite) * 0.5
	v.v(abs(perdu - attendu) < EPSILON,
		"le taux doit composer taux_decomposition_base et la biodegradabilite du materiau (%.4f attendu, %.4f recu)" % [attendu, perdu])

	# Une case sans cadavre dessus ne recoit rien de ce transfert.
	v.v(is_equal_approx(_fertilite(cases, "case_2_0"), float(_config.fertilite_initiale)),
		"une case voisine sans cadavre ne doit rien recevoir du transfert")

func _le_cadavre_epuise_se_transforme_en_humus_et_cesse_de_donner(v) -> void:
	var cases := _cases()
	var sources := _sources()
	var petit := _source(sources, "cadavre_1")
	var type_produit: String = _config_produire.get("type_produit", "")
	var matiere_initiale := _matiere(petit)

	var transforme := false
	for i in range(200):
		var bilan := _pas(cases, sources, 0.5)
		if bilan.transformes.has("cadavre_1"):
			transforme = true
			break
	v.v(transforme, "le petit cadavre doit finir par s'epuiser et etre transforme une fois")
	v.v(petit.get("proprietes_type", "") == type_produit,
		"le cadavre transforme doit porter le type produit ('%s'), recu '%s'" % [type_produit, petit.get("proprietes_type", "")])
	v.v(not petit.proprietes.get("reserves", {}).has(_config.nom_reserve_cadavre),
		"le cadavre transforme ne doit plus porter la reserve source (garde d'idempotence)")
	v.v(float(petit.proprietes.get("masse", 0.0)) > 0.0,
		"l'humus produit doit porter une masse calculee par produit.gd/objet.gd")

	# Le sol a bien recu TOUTE la matiere organique du cadavre (aucune case
	# cadavre n'ecrete : calibration de data/banc_fertilite.json).
	var recu := _fertilite(cases, "case_3_1") - float(_config.fertilite_initiale)
	v.v(abs(recu - matiere_initiale) < EPSILON,
		"la case doit avoir recu la totalite de la matiere organique du cadavre (%.3f attendu, %.3f recu)" % [matiere_initiale, recu])

	# Une fois l'humus pose, la case ne monte plus : rien ne repart.
	var stable_avant := _fertilite(cases, "case_3_1")
	for i in range(10):
		_pas(cases, sources, 0.5)
	v.v(is_equal_approx(_fertilite(cases, "case_3_1"), stable_avant),
		"une case sous un humus inerte ne doit plus rien recevoir (%.3f -> %.3f)" % [stable_avant, _fertilite(cases, "case_3_1")])
	v.v(BancFertilite.source_active(_case(cases, "case_3_1"), sources, _config) == "aucune",
		"un humus ne doit plus compter comme source active")

	# Un second appel ne retransforme jamais (le garde est la reserve elle-meme).
	var encore := BancFertilite.avancer_transformations(sources, _config, _config_produire, _catalogue_types, _materiaux)
	v.v(not encore.has("cadavre_1"), "un cadavre deja transforme ne doit jamais l'etre une seconde fois")

func _la_jachere_remonte_lentement(v) -> void:
	var cases := _cases()
	var sources := _sources()
	var avant := _fertilite(cases, "case_2_2")
	_pas(cases, sources, 0.5)
	var gain := _fertilite(cases, "case_2_2") - avant
	var attendu: float = -float(_config.cout_base_par_zone.jachere) * 0.5
	v.v(gain > 0.0, "une case en jachere doit remonter (cout_base negatif), recu %.4f" % gain)
	v.v(abs(gain - attendu) < EPSILON,
		"la jachere doit remonter exactement de -cout_base*delta (%.4f attendu, %.4f recu)" % [attendu, gain])
	v.v(gain < float(_config.surcout_recolte) * 0.5,
		"la remontee de jachere doit rester LENTE devant la ponction d'une recolte")

func _une_case_sans_source_reste_stable(v) -> void:
	# Meme grille, mais AUCUNE source posee : une case dont le cout_base vaut
	# 0.0 (zones legumineuse/cadavre) ne bouge alors plus du tout -- seule sa
	# depense la fait varier, et elle est nulle.
	var cases := _cases()
	var avant_legumineuse := _fertilite(cases, "case_0_2")
	var avant_cadavre := _fertilite(cases, "case_3_0")
	for i in range(10):
		_pas(cases, [], 0.5)
	v.v(is_equal_approx(_fertilite(cases, "case_0_2"), avant_legumineuse),
		"sans legumineuse, une case a cout_base nul doit rester strictement stable (%.4f -> %.4f)" % [avant_legumineuse, _fertilite(cases, "case_0_2")])
	v.v(is_equal_approx(_fertilite(cases, "case_3_0"), avant_cadavre),
		"sans cadavre, une case a cout_base nul doit rester strictement stable (%.4f -> %.4f)" % [avant_cadavre, _fertilite(cases, "case_3_0")])
	v.v(BancFertilite.source_active(_case(cases, "case_0_2"), [], _config) == "aucune",
		"une case sans aucune source doit l'afficher")

func _la_fertilite_ne_depasse_jamais_la_capacite(v) -> void:
	var cases := _cases()
	var sources := _sources()
	var capacite: float = float(_config.capacite)
	var ecrete_total := 0.0
	for i in range(200):
		ecrete_total += float(_pas(cases, sources, 0.5).ecrete)
	for case in cases:
		v.v(float(case.proprietes.reserves[_config.nom_reserve].reserve) <= capacite + EPSILON,
			"%s ne doit jamais depasser la capacite (%.3f)" % [case.id, case.proprietes.reserves[_config.nom_reserve].reserve])
	v.v(ecrete_total > 0.0,
		"au plafond, le surplus doit etre reellement ecrete (et donc compte), recu %.4f" % ecrete_total)
	v.v(is_equal_approx(_fertilite(cases, "case_0_2"), capacite),
		"une case sous la legumineuse doit finir exactement au plafond, jamais au-dessus")
	v.v(BancFertilite.couleur_pour_fertilite(capacite, _config).is_equal_approx(
			BancFertilite.couleur_pour_fertilite(capacite * 2.0, _config)),
		"la couleur doit rester bornee au-dela de la capacite, jamais divergente")
	v.v(not BancFertilite.couleur_pour_fertilite(0.0, _config).is_equal_approx(
			BancFertilite.couleur_pour_fertilite(capacite, _config)),
		"une case epuisee et une case fertile doivent rendre deux couleurs distinctes")
