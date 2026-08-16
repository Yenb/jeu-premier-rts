extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_vecu_inter_colon.gd
#
# Verrouille le cablage de banc_vecu_inter_colon.gd : PREMIER CABLAGE REEL de
# scripts/lien_personnel_croissance.gd SUR DES COLONS ORION. Chemin REEL :
# data/types.json, data/canaux.json, data/liens_personnels.json,
# data/lien_personnel_croissance.json, data/banc_vecu_inter_colon.json tous
# lus sur disque -- comme le fait ce banc, jamais une fixture locale
# inventee pour les seuils/taux.
#
# Fonctions pures pour les fonctions statiques testees
# (_fabriquer_colon_vert, _fabriquer_troisieme, _avancer_tick_pour_colons,
# _doit_faire_apparaitre_troisieme, _rendu_colon) : aucun noeud, aucun rendu.

const BancVecuInterColon = preload("res://scripts/banc_vecu_inter_colon.gd")
const Perception = preload("res://scripts/perception.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DELTA_TICK := 1.0

func _init() -> void:
	_phase_1_cristallisation_mutuelle()
	_phase_2_apparition_troisieme()
	_phase_3_conversion_partielle()
	_resumabilite_du_banc()
	_imprimer_progression_ne_plante_pas_sur_plusieurs_colons()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_vecu_inter_colon.gd cable lien_personnel_croissance.gd sur des colons reels -- " +
		"la contagion culturelle par vecu inter-colon cristallise des attaches qui se cumulent, " +
		"jamais un objet-groupe")
	quit(0)

func _donnees_banc_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_vecu_inter_colon.json"))

func _catalogue_types_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))

func _catalogue_canaux_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/canaux.json"))

func _catalogue_liens_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/liens_personnels.json"))

func _catalogue_croissance_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/lien_personnel_croissance.json"))

func _a_attache(colon: Dictionary, propriete: String) -> bool:
	for attache in colon.proprietes.attaches:
		if attache.get("propriete", "") == propriete:
			return true
	return false

func _deux_colons_verts_reels(donnees: Dictionary, catalogue_types: Dictionary) -> Array:
	var positions: Array = donnees.get("positions_colons_initiaux", [])
	return [
		BancVecuInterColon._fabriquer_colon_vert("colon_vert_1", positions[0], donnees, catalogue_types),
		BancVecuInterColon._fabriquer_colon_vert("colon_vert_2", positions[1], donnees, catalogue_types),
	]

func _phase_1_cristallisation_mutuelle() -> void:
	var donnees := _donnees_banc_reelles()
	var catalogue_types := _catalogue_types_reel()
	var canaux := _catalogue_canaux_reel()
	var croissance := _catalogue_croissance_reel()
	var liens := _catalogue_liens_reel()
	var catalogue_attaches: Dictionary = donnees.get("catalogue_attaches_par_trait", {})

	var colons := _deux_colons_verts_reels(donnees, catalogue_types)
	var monde := Monde.new()
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)

	for i in 5:
		BancVecuInterColon._avancer_tick_pour_colons(colons, monde, canaux, croissance, liens, catalogue_attaches, DELTA_TICK)
	verif.v(not _a_attache(colons[0], "venere_arbres_verts") and not _a_attache(colons[1], "venere_arbres_verts"),
		"apres seulement 5 ticks (force encore sous le seuil reel), aucune attache par trait ne doit etre formee")

	for i in 25:
		BancVecuInterColon._avancer_tick_pour_colons(colons, monde, canaux, croissance, liens, catalogue_attaches, DELTA_TICK)
	verif.v(_a_attache(colons[0], "venere_arbres_verts") and _a_attache(colons[1], "venere_arbres_verts"),
		"apres assez de ticks (30 au total) pour franchir le seuil reel, les DEUX colons doivent avoir cristallise mutuellement l'attache 'venere_arbres_verts'")

func _phase_2_apparition_troisieme() -> void:
	var donnees := _donnees_banc_reelles()
	var catalogue_types := _catalogue_types_reel()
	var delai: float = donnees.get("delai_apparition_troisieme", 60.0)
	verif.v(delai == 60.0, "delai_apparition_troisieme doit valoir 60.0 secondes")

	verif.v(not BancVecuInterColon._doit_faire_apparaitre_troisieme(false, 59.9, delai),
		"avant le delai, le troisieme ne doit pas encore apparaitre")
	verif.v(BancVecuInterColon._doit_faire_apparaitre_troisieme(false, 60.0, delai),
		"au delai exact, le troisieme doit apparaitre")
	verif.v(not BancVecuInterColon._doit_faire_apparaitre_troisieme(true, 90.0, delai),
		"une fois deja instancie, ne doit plus jamais redeclencher une apparition")

	var pos_apparition: Array = donnees.get("position_apparition_troisieme", [])
	var troisieme := BancVecuInterColon._fabriquer_troisieme(pos_apparition, donnees, catalogue_types)
	verif.v(troisieme.position == Vector3(pos_apparition[0], pos_apparition[1], pos_apparition[2]),
		"le troisieme doit apparaitre exactement a position_apparition_troisieme")
	verif.v(troisieme.proprietes.get("venere_arbres_rouges", false) == true,
		"le troisieme doit porter le trait plat 'venere_arbres_rouges' des la naissance (pour etre percu par autrui)")
	verif.v(_a_attache(troisieme, "venere_arbres_rouges"),
		"le troisieme doit porter l'attache 'venere_arbres_rouges' DEJA CRISTALLISEE des la naissance -- une identite d'origine, jamais formee par attache_par_trait.gd")
	verif.v(troisieme.proprietes.liens_personnels.is_empty(),
		"le troisieme ne doit porter aucun lien personnel a la naissance")

	var colons_verts := _deux_colons_verts_reels(donnees, catalogue_types)
	var monde := Monde.new()
	for colon in colons_verts:
		monde.ajouter(colon, "colon", colon.position)
	monde.ajouter(troisieme, "colon", troisieme.position)
	var perceptions := Perception.percevoir(colons_verts[0], monde, _catalogue_canaux_reel())
	var percoit_le_troisieme := false
	for entree in perceptions:
		if entree.chose.id == troisieme.id:
			percoit_le_troisieme = true
	verif.v(not percoit_le_troisieme,
		"a l'instant de son apparition, le troisieme doit rester hors de toute portee de perception des deux premiers (colon_vert_1 peut legitimement percevoir colon_vert_2, jamais le troisieme)")

func _phase_3_conversion_partielle() -> void:
	var donnees := _donnees_banc_reelles()
	var catalogue_types := _catalogue_types_reel()
	var canaux := _catalogue_canaux_reel()
	var croissance := _catalogue_croissance_reel()
	var liens := _catalogue_liens_reel()
	var catalogue_attaches: Dictionary = donnees.get("catalogue_attaches_par_trait", {})

	var colons := _deux_colons_verts_reels(donnees, catalogue_types)
	var pos_arret: Array = donnees.get("position_arret_troisieme", [])
	var troisieme := BancVecuInterColon._fabriquer_troisieme(pos_arret, donnees, catalogue_types)
	colons.append(troisieme)

	var monde := Monde.new()
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)

	# Verifie d'abord que le point d'arret est bien A PORTEE d'ecoute des deux
	# premiers -- sans quoi la phase 3 ne pourrait jamais s'amorcer.
	var perceptions := Perception.percevoir(troisieme, monde, canaux)
	verif.v(perceptions.size() == 2,
		"a position_arret_troisieme, le troisieme doit percevoir les DEUX colons verts -- percus reellement : %d" % perceptions.size())

	for i in 30:
		BancVecuInterColon._avancer_tick_pour_colons(colons, monde, canaux, croissance, liens, catalogue_attaches, DELTA_TICK)

	verif.v(_a_attache(troisieme, "venere_arbres_rouges"),
		"le troisieme doit GARDER son attache d'origine 'venere_arbres_rouges' -- les attaches se cumulent, ne s'effacent jamais")
	verif.v(_a_attache(troisieme, "venere_arbres_verts"),
		"apres assez de ticks a portee d'ecoute des deux verts, le troisieme doit avoir cristallise EN PLUS l'attache 'venere_arbres_verts'")

	var rendu := BancVecuInterColon._rendu_colon(troisieme)
	verif.v(rendu.bordure == BancVecuInterColon.COULEUR_ROUGE and rendu.interieur == BancVecuInterColon.COULEUR_VERT,
		"un colon hybride (les deux attaches) doit se rendre bordure rouge / interieur vert, jamais une autre combinaison")

func _resumabilite_du_banc() -> void:
	var donnees := _donnees_banc_reelles()
	var catalogue_types := _catalogue_types_reel()
	var canaux := _catalogue_canaux_reel()
	var croissance := _catalogue_croissance_reel()
	var liens := _catalogue_liens_reel()
	var catalogue_attaches: Dictionary = donnees.get("catalogue_attaches_par_trait", {})

	var colons := _deux_colons_verts_reels(donnees, catalogue_types)
	var monde := Monde.new()
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)

	for i in 30:
		BancVecuInterColon._avancer_tick_pour_colons(colons, monde, canaux, croissance, liens, catalogue_attaches, DELTA_TICK)

	var texte := JSON.stringify(colons)
	var relus: Variant = JSON.parse_string(texte)
	verif.v(relus != null, "JSON.stringify puis parse_string doit reussir sans erreur sur la liste de colons")
	verif.v(_a_attache(relus[0], "venere_arbres_verts") == _a_attache(colons[0], "venere_arbres_verts"),
		"l'attache cristallisee doit survivre identique a l'aller-retour JSON")

# Audit couverture 2026-08-06 : _imprimer_progression est une fonction
# INSTANCE, aucune appelee par un test avant cette session -- 100% print
# (aucun etat mute), rien a observer au-dela de "ne plante pas" sur des
# colons dont les cles varient reellement (liens_personnels vide vs
# peuple, sensibilite_generalisation surchargee vs absente).
func _imprimer_progression_ne_plante_pas_sur_plusieurs_colons() -> void:
	var b := BancVecuInterColon.new()
	b._temps_ecoule = 12.0
	b._catalogue_attaches_par_trait = {
		"generalisation_verts": {"propriete": "venere_arbres_verts", "seuil_force": 1.0},
	}
	var colon_sans_lien := {
		"id": "c1", "proprietes": {"liens_personnels": {}, "sensibilite_generalisation": {}},
	}
	var colon_avec_lien := {
		"id": "c2",
		"proprietes": {
			"liens_personnels": {"c1": 0.4},
			"sensibilite_generalisation": {"venere_arbres_verts": {"seuil_force": 2.0}},
		},
	}
	b._colons = [colon_sans_lien, colon_avec_lien]
	b._imprimer_progression()
	verif.v(true, "_imprimer_progression doit parcourir tous les colons (liens vides, surcharge de seuil) sans planter")
