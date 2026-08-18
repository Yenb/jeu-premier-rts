extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_jugement.gd
#
# Verrouille scripts/jugement.gd (couche 2bis, voir docs/design.md,
# "Jugement : troisieme source de saillance") : une chose portant la
# propriete JUGEE (ex. "abrite") ne ressort saillante que si une pression
# (saillance deja calculee en couche 2, sur une chose portant la
# propriete DECLENCHEUR, ex. "brule") existe dans "resultats". Sans
# pression, RIEN -- jamais une entree a zero (meme contrat que
# proximite.gd).
#
# _hors_domaine() verrouille que le mecanisme ne connait ni le feu ni
# l'abri : un couple invente ({ "sec": "inonde" }), avec des types jamais
# vus ailleurs dans le depot, traverse le meme code sans une ligne
# ajoutee.
#
# _plafond_absent_alarme_sans_saillance_non_bornee() verrouille le CAS DU
# COUPLE (docs/design.md, "Propriete structurelle vs facultative") :
# gain_jugement present SANS plafond_jugement doit alarmer et ne RIEN
# produire -- jamais une saillance non bornee qui serait un defaut
# silencieux plus fort que ce que le gain seul declarait.

const Jugement = preload("res://scripts/jugement.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	var jugements := { "abrite": "brule" }

	var feu := { "id": "feu", "position": Vector3(0, 0, 0), "proprietes": { "brule": true } }
	var grotte := { "id": "grotte", "position": Vector3(5, 0, 0), "proprietes": { "abrite": true } }

	var perceptions := [
		{ "chose": feu, "type": "feu", "position": Vector3(0, 0, 0), "distance": 0.0 },
		{ "chose": grotte, "type": "grotte", "position": Vector3(5, 0, 0), "distance": 5.0 },
	]

	var colon := {
		"proprietes": {
			"forme": { "gain_jugement": 0.5, "plafond_jugement": 5.0 },
		},
	}

	# NOMINAL : le feu est deja saillant en couche 2 (pression) -- la
	# grotte, elle, n'a aucune saillance propre et serait absente de
	# resultats si jugement.gd n'existait pas.
	var resultats_avec_feu := [
		{ "chose": feu, "type": "feu", "position": Vector3(0, 0, 0), "saillance": 2.0 },
	]
	var res_nominal := Jugement.evaluer(perceptions, colon, resultats_avec_feu, jugements)
	verif.v(res_nominal.size() == 1, "nominal : la grotte doit ressortir jugee saillante")
	if res_nominal.size() == 1:
		verif.v(res_nominal[0].chose.id == "grotte", "l'entree doit designer la grotte, pas le feu")
		verif.v(res_nominal[0].saillance > 0.0, "pression positive : saillance strictement positive")
		verif.v(is_equal_approx(res_nominal[0].saillance, 1.0),
			"saillance = pression (2.0) * gain_jugement (0.5) = 1.0")

	# NEGATIF : meme scene, mais aucune chose ne porte "brule" dans
	# resultats -- pression nulle, la grotte doit etre ABSENTE, jamais une
	# entree a saillance zero.
	var resultats_sans_feu: Array = []
	var res_negatif := Jugement.evaluer(perceptions, colon, resultats_sans_feu, jugements)
	verif.v(res_negatif.is_empty(), "sans pression, la grotte doit etre absente du resultat")

	_hors_domaine()
	_plafond_absent_alarme_sans_saillance_non_bornee()
	_forme_absente_alarme_et_rend_vide()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: grotte jugee saillante (%.2f) sous pression du feu, absente sans pression, " % [
		res_nominal[0].saillance if res_nominal.size() == 1 else 0.0
	] + "domaine invente traverse le meme code, plafond absent alarme sans saillance non bornee")
	quit(0)

# LA GARDE STRUCTURELLE, exercee ici et nulle part ailleurs : `forme` porte
# le gain et le plafond du jugement, elle definit donc a elle seule ce qu'est
# un colon capable de juger. Absente, alarme PUIS retour neutre.
func _forme_absente_alarme_et_rend_vide() -> void:
	var perceptions := [
		{"chose": {"id": "a", "proprietes": {"abrite": true}}, "type": "a", "position": Vector3.ZERO, "distance": 0.0},
	]
	var resultats := [{"chose": {"id": "f", "proprietes": {"brule": true}}, "saillance": 3.0}]
	verif.v(Jugement.evaluer(perceptions, {"proprietes": {}}, resultats, {"abrite": "brule"}).is_empty(),
		"'forme' absente : alarme puis retour neutre, jamais une saillance jugee")

# LA serrure hors domaine : "sec"/"inonde" n'a aucun rapport avec le feu
# ni l'abri, et "eponge"/"riviere" ne sont des types vus nulle part
# ailleurs dans le depot (verifiable par grep). Si ce test passe,
# jugement.gd ne connait aucun nom de propriete ni de type.
func _hors_domaine() -> void:
	var jugements := { "sec": "inonde" }
	var riviere := { "id": "riviere", "position": Vector3(0, 0, 0), "proprietes": { "inonde": true } }
	var eponge := { "id": "eponge", "position": Vector3(3, 0, 0), "proprietes": { "sec": true } }

	var perceptions := [
		{ "chose": riviere, "type": "riviere", "position": Vector3(0, 0, 0), "distance": 0.0 },
		{ "chose": eponge, "type": "eponge", "position": Vector3(3, 0, 0), "distance": 3.0 },
	]
	var resultats := [
		{ "chose": riviere, "type": "riviere", "position": Vector3(0, 0, 0), "saillance": 3.0 },
	]
	var colon := {
		"proprietes": {
			"forme": { "gain_jugement": 1.0, "plafond_jugement": 10.0 },
		},
	}

	var res := Jugement.evaluer(perceptions, colon, resultats, jugements)
	verif.v(res.size() == 1, "hors domaine : attendu 1 resultat")
	if res.size() == 1:
		verif.v(res[0].chose.id == "eponge",
			"un couple invente doit traverser le meme code sans ligne ajoutee")
		verif.v(is_equal_approx(res[0].saillance, 3.0),
			"saillance = pression (3.0) * gain_jugement (1.0) = 3.0")

# LA serrure du cas du couple : gain_jugement present sans
# plafond_jugement ne doit JAMAIS produire une saillance non bornee --
# meme scene que le cas NOMINAL (pression positive, une chose jugee
# perceptible), mais forme incomplete. Si un defaut silencieux existait
# pour plafond_jugement, la grotte ressortirait quand meme, a une
# saillance non voulue -- ce test verrouille qu'elle est ABSENTE.
func _plafond_absent_alarme_sans_saillance_non_bornee() -> void:
	var jugements := { "abrite": "brule" }
	var feu := { "id": "feu", "position": Vector3(0, 0, 0), "proprietes": { "brule": true } }
	var grotte := { "id": "grotte", "position": Vector3(5, 0, 0), "proprietes": { "abrite": true } }

	var perceptions := [
		{ "chose": feu, "type": "feu", "position": Vector3(0, 0, 0), "distance": 0.0 },
		{ "chose": grotte, "type": "grotte", "position": Vector3(5, 0, 0), "distance": 5.0 },
	]
	var resultats := [
		{ "chose": feu, "type": "feu", "position": Vector3(0, 0, 0), "saillance": 2.0 },
	]
	var colon_incomplet := {
		"proprietes": {
			"forme": { "gain_jugement": 0.5 },
		},
	}

	var res := Jugement.evaluer(perceptions, colon_incomplet, resultats, jugements)
	verif.v(res.is_empty(),
		"gain_jugement sans plafond_jugement : aucune entree, jamais une saillance non bornee")
