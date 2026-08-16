extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_ciblage.gd
#
# Verrouille scripts/ciblage.gd (chantier "cible generale") : Ciblage.viser
# dispatche PAR VERBE (data/orientations.json), jamais par un nom en dur --
# un verbe DECLENCHEUR (ex. "defendre", "approcher") vise la chose-menace
# (meme geste que l'ancien _selection_par_menace de banc_p1.gd) ; un verbe
# oriente vers la chose JUGEE (ex. "se_proteger") vise la chose rendue par
# jugement.gd (celle qui porte la propriete jugee), jamais le declencheur.
#
# _hors_domaine() verrouille que le mecanisme ne connait ni "defendre" ni
# "se_proteger" en dur : un verbe et un couple jugee/declencheur invente,
# sans aucun rapport avec le feu ni l'abri, traversent le meme code.
#
# _verbe_jugee_sans_propriete_jugee_rend_null() verrouille le cas
# d'incoherence : un verbe oriente "jugee" dont la chose portee par la
# decision ne porte aucune propriete de la table jugements ne doit jamais
# deviner une cible -- null, pas la chose au hasard.

const Ciblage = preload("res://scripts/ciblage.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_verbe_declencheur_vise_la_chose_menace()
	_verbe_jugee_vise_la_chose_jugee_pas_le_declencheur()
	_hors_domaine()
	_verbe_jugee_sans_propriete_jugee_rend_null()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: verbe declencheur -> chose-menace, verbe jugee -> chose jugee " +
		"(jamais le declencheur), domaine invente traverse le meme code")
	quit(0)

# Meme scene que l'ancien _selection_par_menace (test_banc_p1.gd) : une
# foret irremplacable ET inflammable, un feu qui la menace. Decision
# ORIGINE ATTACHE (pas de "chose", "menace" positive) : Ciblage.viser doit
# retrouver la foret qui brule, exactement comme avant le chantier "cible
# generale". "defendre" absent de data/orientations.json -> declencheur
# par defaut.
func _verbe_declencheur_vise_la_chose_menace() -> void:
	var menaces := { "inflammable": "brule" }
	var orientations := { "se_proteger": "jugee" }

	var foret := { "id": "foret", "position": Vector3(900, 0, 0), "proprietes": { "irremplacable": true, "inflammable": true } }
	var feu := { "id": "feu", "position": Vector3(910, 0, 0), "proprietes": { "brule": true } }

	var perceptions := [
		{ "chose": foret, "type": "arbre", "position": Vector3(900, 0, 0), "distance": 900.0 },
		{ "chose": feu, "type": "feu", "position": Vector3(910, 0, 0), "distance": 910.0 },
	]
	var decision := { "type": "irremplacable", "menace": 0.6, "saillance": 2.0, "action": "defendre" }

	var chose = Ciblage.viser(decision, perceptions, menaces, {}, orientations)
	verif.v(chose != null and chose.id == "feu",
		"verbe declencheur : doit viser le feu qui menace la foret, pas la foret elle-meme")

# Le feu (declencheur) ET la grotte (chose jugee) sont tous deux percus --
# le verbe "se_proteger" doit viser la grotte, jamais le feu.
func _verbe_jugee_vise_la_chose_jugee_pas_le_declencheur() -> void:
	var jugements := { "abrite": "brule" }
	var orientations := { "se_proteger": "jugee" }

	var feu := { "id": "feu", "position": Vector3(0, 0, 0), "proprietes": { "brule": true } }
	var grotte := { "id": "grotte", "position": Vector3(5, 0, 0), "proprietes": { "abrite": true } }

	var perceptions := [
		{ "chose": feu, "type": "feu", "position": Vector3(0, 0, 0), "distance": 0.0 },
		{ "chose": grotte, "type": "grotte", "position": Vector3(5, 0, 0), "distance": 5.0 },
	]
	# Decision origine jugement.gd (meme forme que proximite.gd) : la chose
	# portee EST deja la chose jugee.
	var decision := { "chose": grotte, "type": "grotte", "position": grotte.position, "saillance": 1.0, "action": "se_proteger" }

	var chose = Ciblage.viser(decision, perceptions, {}, jugements, orientations)
	verif.v(chose != null and chose.id == "grotte", "verbe jugee : doit viser la grotte")
	verif.v(chose.id != "feu", "verbe jugee : ne doit jamais viser le declencheur")

# LA serrure hors domaine : "instinct_invente" (verbe), "protege"/"expose"
# (couple jugee/declencheur) n'ont aucun rapport avec le feu ni l'abri, et
# ne sont vus nulle part ailleurs dans le depot. Si ce test passe,
# ciblage.gd ne connait aucun nom de verbe ni de propriete en dur.
func _hors_domaine() -> void:
	var jugements := { "protege": "expose" }
	var orientations := { "instinct_invente": "jugee" }

	var expose := { "id": "expose", "position": Vector3(0, 0, 0), "proprietes": { "expose": true } }
	var refuge := { "id": "refuge", "position": Vector3(7, 0, 0), "proprietes": { "protege": true } }

	var perceptions := [
		{ "chose": expose, "type": "expose", "position": Vector3(0, 0, 0), "distance": 0.0 },
		{ "chose": refuge, "type": "refuge", "position": Vector3(7, 0, 0), "distance": 7.0 },
	]
	var decision := { "chose": refuge, "type": "refuge", "position": refuge.position, "saillance": 1.0, "action": "instinct_invente" }

	var chose = Ciblage.viser(decision, perceptions, {}, jugements, orientations)
	verif.v(chose != null and chose.id == "refuge",
		"un verbe et un couple invente doivent traverser le meme code sans ligne ajoutee")

# Incoherence de donnees : verbe oriente "jugee" mais la chose portee par
# la decision ne porte aucune propriete de la table jugements -- ne doit
# jamais deviner une cible.
func _verbe_jugee_sans_propriete_jugee_rend_null() -> void:
	var jugements := { "abrite": "brule" }
	var orientations := { "se_proteger": "jugee" }

	var chose_ordinaire := { "id": "chose_ordinaire", "position": Vector3(0, 0, 0), "proprietes": {} }
	var decision := { "chose": chose_ordinaire, "type": "neutre", "position": chose_ordinaire.position, "saillance": 1.0, "action": "se_proteger" }

	var chose = Ciblage.viser(decision, [], {}, jugements, orientations)
	verif.v(chose == null,
		"verbe jugee sans propriete jugee sur la chose portee : null, jamais une cible devinee")
