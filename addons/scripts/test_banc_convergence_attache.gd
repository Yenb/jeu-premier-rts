extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_convergence_attache.gd
#
# Verrouille le cablage de banc_convergence_attache.gd : PREMIER CABLAGE
# REEL de scripts/comptage.gd SUR DES COLONS ORION (apres banc_comptage.gd,
# hors domaine). Chemin REEL : data/types.json, data/canaux.json,
# data/liens_personnels.json, data/comptages.json,
# data/banc_convergence_attache.json (magnitude_exposition,
# catalogue_attaches_par_trait, declencheur) tous lus sur disque -- comme
# le fait ce banc, jamais une fixture locale inventee pour les poids.
#
# Fonction pure pour les fonctions statiques testees
# (_avancer_tick_pour_colons, _compter_attaches_brule, _moyenne_glissante) :
# aucun noeud, aucun rendu.

const BancConvergenceAttache = preload("res://scripts/banc_convergence_attache.gd")
const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DELTA_TICK := 0.1

func _init() -> void:
	_pipeline_produit_lien_puis_attache()
	_comptage_reel_apres_convergence()
	_comptage_intermediaire()
	_resumabilite_du_banc()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_convergence_attache.gd cable comptage.gd sur des colons reels -- " +
		"perception -> lien_personnel -> attache_par_trait produit un fait collectif " +
		"lu par un lecteur agrege, jamais porte par un objet-groupe")
	quit(0)

func _types_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))

func _catalogue_canaux_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/canaux.json"))

func _catalogue_liens_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/liens_personnels.json"))

func _catalogue_comptages_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/comptages.json"))

func _donnees_banc_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_convergence_attache.json"))

# data/types.json porte deja objet_physique/dynamique/percevant/agent/colon
# ensemble (colon.herite les resout tous depuis CE MEME fichier) -- seul
# "arbre" (LOCAL a ce banc, jamais data/types.json:arbre) manque, ajoute ici
# directement sur la table dupliquee, meme resultat que
# banc_convergence_attache.gd:_ready sans repasser par son code Node.
func _catalogue_types_reel() -> Dictionary:
	var table := _types_reels().duplicate(true)
	table["arbre"] = {"brule": true}
	return table

func _colon_reel(id: String, position: Vector3, sensibilite: Dictionary = {}) -> Dictionary:
	var colon := Objet.fabriquer(id, "colon", position, _catalogue_types_reel())
	colon.proprietes["sensibilite_generalisation"] = sensibilite
	return colon

func _arbre_reel(id: String, position: Vector3) -> Dictionary:
	return Objet.fabriquer(id, "arbre", position, _catalogue_types_reel())

# Trois arbres reels, tous proches de l'origine -- largement a portee de vue
# (canaux_config.vue.portee 1600.0, data/types.json:colon) de tout colon
# positionne pres de l'origine egalement.
func _monde_avec_trois_arbres() -> Monde:
	var monde := Monde.new()
	var positions := [Vector3(20.0, 0.0, 0.0), Vector3(-20.0, 0.0, 0.0), Vector3(0.0, 20.0, 0.0)]
	for i in positions.size():
		var arbre := _arbre_reel("arbre_%d" % i, positions[i])
		monde.ajouter(arbre, "arbre", positions[i])
	return monde

func _pipeline_produit_lien_puis_attache() -> void:
	var donnees := _donnees_banc_reelles()
	var declencheur: String = donnees.get("declencheur", "brule")
	var magnitude: float = donnees.get("magnitude_exposition", 0.0)
	var catalogue_attaches: Dictionary = donnees.get("catalogue_attaches_par_trait", {})
	var canaux := _catalogue_canaux_reel()
	var liens := _catalogue_liens_reel()

	var monde := _monde_avec_trois_arbres()
	var colon := _colon_reel("colon_test", Vector3.ZERO)
	monde.ajouter(colon, "colon", colon.position)

	for i in 3:
		BancConvergenceAttache._avancer_tick_pour_colons(
			[colon], monde, canaux, declencheur, magnitude, liens, catalogue_attaches, DELTA_TICK,
		)
	verif.v(not colon.proprietes.liens_personnels.is_empty(),
		"apres quelques ticks d'exposition reelle, un lien personnel doit exister vers au moins un arbre")
	verif.v(colon.proprietes.attaches.is_empty(),
		"apres seulement 3 ticks (force encore sous le seuil reel), aucune attache par trait ne doit etre formee")

	for i in 7:
		BancConvergenceAttache._avancer_tick_pour_colons(
			[colon], monde, canaux, declencheur, magnitude, liens, catalogue_attaches, DELTA_TICK,
		)
	var a_lattache_brule := false
	for attache in colon.proprietes.attaches:
		if attache.get("propriete", "") == "brule":
			a_lattache_brule = true
	verif.v(a_lattache_brule,
		"apres assez de ticks (10 au total) pour franchir le seuil reel sur au moins deux arbres distincts, l'attache par trait 'brule' doit s'etre formee")

# Trois colons reels, memes surcharges que data/banc_convergence_attache.json
# (colon_rapide/colon_moyen/colon_lent -- seul sensibilite_generalisation.brule.seuil_force
# differe), tous exposes IDENTIQUEMENT aux memes trois arbres : apres assez
# de ticks pour que le plus lent converge aussi, les trois doivent avoir
# cristallise.
func _trois_colons_reels() -> Array:
	var donnees := _donnees_banc_reelles()
	var declarations: Dictionary = donnees.get("colons", {})
	var colons: Array = []
	for nom in declarations:
		var sensibilite: Dictionary = declarations[nom].get("sensibilite_generalisation", {})
		colons.append(_colon_reel(nom, Vector3.ZERO, sensibilite))
	return colons

func _comptage_reel_apres_convergence() -> void:
	var donnees := _donnees_banc_reelles()
	var declencheur: String = donnees.get("declencheur", "brule")
	var magnitude: float = donnees.get("magnitude_exposition", 0.0)
	var catalogue_attaches: Dictionary = donnees.get("catalogue_attaches_par_trait", {})
	var canaux := _catalogue_canaux_reel()
	var liens := _catalogue_liens_reel()
	var comptages := _catalogue_comptages_reel()

	var monde := _monde_avec_trois_arbres()
	var colons := _trois_colons_reels()
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)

	for i in 20:
		BancConvergenceAttache._avancer_tick_pour_colons(
			colons, monde, canaux, declencheur, magnitude, liens, catalogue_attaches, DELTA_TICK,
		)

	var compte := BancConvergenceAttache._compter_attaches_brule(colons, comptages)
	verif.v(compte == 3,
		"apres 20 ticks, assez pour que meme le colon le plus exigeant (seuil_force le plus haut) converge, les trois colons doivent porter l'attache 'brule' -- compte reel obtenu : %d" % compte)

func _comptage_intermediaire() -> void:
	var donnees := _donnees_banc_reelles()
	var declencheur: String = donnees.get("declencheur", "brule")
	var magnitude: float = donnees.get("magnitude_exposition", 0.0)
	var catalogue_attaches: Dictionary = donnees.get("catalogue_attaches_par_trait", {})
	var canaux := _catalogue_canaux_reel()
	var liens := _catalogue_liens_reel()
	var comptages := _catalogue_comptages_reel()

	var monde := _monde_avec_trois_arbres()
	var colons := _trois_colons_reels()
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)

	for i in 10:
		BancConvergenceAttache._avancer_tick_pour_colons(
			colons, monde, canaux, declencheur, magnitude, liens, catalogue_attaches, DELTA_TICK,
		)

	var compte := BancConvergenceAttache._compter_attaches_brule(colons, comptages)
	verif.v(compte == 2,
		"apres 10 ticks, deux colons (seuils bas et moyen) doivent avoir converge, le plus exigeant pas encore -- compte reel obtenu : %d" % compte)

func _resumabilite_du_banc() -> void:
	var donnees := _donnees_banc_reelles()
	var declencheur: String = donnees.get("declencheur", "brule")
	var magnitude: float = donnees.get("magnitude_exposition", 0.0)
	var catalogue_attaches: Dictionary = donnees.get("catalogue_attaches_par_trait", {})
	var canaux := _catalogue_canaux_reel()
	var liens := _catalogue_liens_reel()
	var comptages := _catalogue_comptages_reel()

	var monde := _monde_avec_trois_arbres()
	var colons := _trois_colons_reels()
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)

	for i in 10:
		BancConvergenceAttache._avancer_tick_pour_colons(
			colons, monde, canaux, declencheur, magnitude, liens, catalogue_attaches, DELTA_TICK,
		)

	var texte := JSON.stringify(colons)
	var relus: Variant = JSON.parse_string(texte)
	verif.v(relus != null, "JSON.stringify puis parse_string doit reussir sans erreur sur la liste de colons")
	var compte_original := BancConvergenceAttache._compter_attaches_brule(colons, comptages)
	var compte_relu := BancConvergenceAttache._compter_attaches_brule(relus, comptages)
	verif.v(compte_relu == compte_original,
		"le comptage doit rendre exactement la meme valeur avant et apres un aller-retour JSON sur la liste de colons (original : %d, relu : %d)" %
			[compte_original, compte_relu])
