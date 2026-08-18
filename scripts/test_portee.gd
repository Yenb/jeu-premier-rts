extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_portee.gd
#
# Verrouille scripts/portee.gd -- calcul PUR, hors domaine par construction
# (positions et portees arbitraires, aucun rapport avec colon/feu/aimant).
# Chantier "Direction majeure" (voir docs/design.md) : cette fonction est
# la seule part extraite du geste partage par attaches.gd/propagation.gd/
# flux.gd/extinction.gd/charge.gd -- ces tests prouvent qu'elle repond
# EXACTEMENT comme les cinq comparaisons "distance <= portee" qu'elle
# remplace, frontiere comprise.

const Portee = preload("res://scripts/portee.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_strictement_dans_la_portee(v)
	_exactement_a_la_portee_compte_comme_dedans(v)
	_juste_au_dela_de_la_portee_est_hors_portee(v)
	_positions_confondues_avec_portee_nulle_est_dans_la_portee(v)
	_positions_distinctes_avec_portee_nulle_est_hors_portee(v)
	_portee_negative_est_toujours_hors_portee(v)
	_ne_depend_pas_de_l_ordre_des_deux_positions(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: portee.gd -- distance <= portee, frontiere incluse, ordre des positions indifferent")
		quit(0)

func _strictement_dans_la_portee(v) -> void:
	v.v(Portee.en_portee(Vector3(0, 0, 0), Vector3(3, 0, 0), 10.0),
		"distance 3 dans une portee de 10 doit rendre true")

func _exactement_a_la_portee_compte_comme_dedans(v) -> void:
	v.v(Portee.en_portee(Vector3(0, 0, 0), Vector3(5, 0, 0), 5.0),
		"distance EXACTEMENT egale a la portee doit rendre true (<=, jamais <)")

func _juste_au_dela_de_la_portee_est_hors_portee(v) -> void:
	v.v(not Portee.en_portee(Vector3(0, 0, 0), Vector3(5.01, 0, 0), 5.0),
		"distance juste au-dela de la portee doit rendre false")

func _positions_confondues_avec_portee_nulle_est_dans_la_portee(v) -> void:
	v.v(Portee.en_portee(Vector3(7, 2, 0), Vector3(7, 2, 0), 0.0),
		"deux positions confondues (distance 0.0) doivent rester dans une portee 0.0")

func _positions_distinctes_avec_portee_nulle_est_hors_portee(v) -> void:
	v.v(not Portee.en_portee(Vector3(0, 0, 0), Vector3(0.01, 0, 0), 0.0),
		"deux positions distinctes ne sont jamais dans une portee 0.0")

func _portee_negative_est_toujours_hors_portee(v) -> void:
	v.v(not Portee.en_portee(Vector3(0, 0, 0), Vector3(0, 0, 0), -1.0),
		"une portee negative ne doit jamais matcher, meme a distance 0.0 (donnee cassee, pas un cas special)")

func _ne_depend_pas_de_l_ordre_des_deux_positions(v) -> void:
	var a := Vector3(1, 2, 3)
	var b := Vector3(9, -4, 6)
	v.v(Portee.en_portee(a, b, 8.0) == Portee.en_portee(b, a, 8.0),
		"en_portee(a, b, p) doit rendre exactement la meme reponse que en_portee(b, a, p)")
