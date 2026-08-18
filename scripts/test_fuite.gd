extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_fuite.gd
#
# Verrouille scripts/fuite.gd : Fuite.direction ne lit que position et
# saillance (jamais un nom de type, jamais une propriete) et rend une
# direction NORMALISEE, jamais une cible-position.
#
# _deux_sources_le_colon_part_a_l_oppose_de_la_plus_forte() verrouille le
# cas central : deux choses a fuir, situees a angle droit l'une de
# l'autre, produisent une direction qui les fuit TOUTES LES DEUX a la
# fois (entre les deux), pas seulement la plus proche ou la plus forte.
#
# _hors_domaine() verrouille que le mecanisme ne connait ni le feu ni
# l'abri : des choses inventees, sans aucun rapport avec le feu, sans
# aucun champ au-dela de position/saillance, produisent une direction de
# fuite par le meme code.
#
# _rien_a_fuir_et_repulsions_qui_s_annulent_rendent_zero() verrouille les
# deux cas ou l'appelant ne doit pas deplacer le colon : liste vide, et
# deux repulsions egales et opposees qui s'annulent exactement.

const Fuite = preload("res://scripts/fuite.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_une_seule_chose_fuite_a_l_oppose()
	_deux_sources_le_colon_part_a_l_oppose_de_la_plus_forte()
	_hors_domaine()
	_rien_a_fuir_et_repulsions_qui_s_annulent_rendent_zero()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: une chose -> fuite directe, deux sources -> direction entre les deux, " +
		"domaine invente traverse le meme code, rien a fuir ou annulation -> ZERO")
	quit(0)

func _une_seule_chose_fuite_a_l_oppose() -> void:
	var colon_position := Vector3(0, 0, 0)
	var choses := [
		{ "position": Vector3(10, 0, 0), "saillance": 2.0 },
	]
	var d := Fuite.direction(colon_position, choses)
	verif.v(d.is_equal_approx(Vector3(-1, 0, 0)),
		"une seule chose a fuir : direction exactement a l'oppose, normalisee")

# Feu a (10, 0, 0), abri-menacant invente a (0, 10, 0) (peu importe ce
# que c'est : Fuite.direction ne lit que position/saillance) -- meme
# saillance (1.0) des deux : la direction doit fuir les DEUX a la fois,
# a angle egal des deux repulsions individuelles (-1,0,0) et (0,-1,0),
# jamais purement l'une ou l'autre.
func _deux_sources_le_colon_part_a_l_oppose_de_la_plus_forte() -> void:
	var colon_position := Vector3(0, 0, 0)
	var choses := [
		{ "position": Vector3(10, 0, 0), "saillance": 1.0 },
		{ "position": Vector3(0, 10, 0), "saillance": 1.0 },
	]
	var d := Fuite.direction(colon_position, choses)
	var attendu := Vector3(-1, -1, 0).normalized()
	verif.v(d.is_equal_approx(attendu),
		"deux sources egales a angle droit : direction exactement entre les deux fuites individuelles")
	verif.v(d.x < 0.0 and d.y < 0.0,
		"la direction doit s'eloigner des deux sources a la fois, pas une seule")

# LA serrure hors domaine : ni "feu" ni "abri" -- des Dictionary { position,
# saillance } nus, sans aucun autre champ, doivent traverser le meme code.
func _hors_domaine() -> void:
	var colon_position := Vector3(100, 100, 0)
	var choses := [
		{ "position": Vector3(105, 100, 0), "saillance": 3.0 },
	]
	var d := Fuite.direction(colon_position, choses)
	verif.v(d.is_equal_approx(Vector3(-1, 0, 0)),
		"donnee invente, sans nom de domaine : meme code, meme resultat")

func _rien_a_fuir_et_repulsions_qui_s_annulent_rendent_zero() -> void:
	var colon_position := Vector3(0, 0, 0)

	var d_vide := Fuite.direction(colon_position, [])
	verif.v(d_vide == Vector3.ZERO, "liste vide : aucune direction, l'appelant ne deplace pas")

	var choses_opposees := [
		{ "position": Vector3(10, 0, 0), "saillance": 1.0 },
		{ "position": Vector3(-10, 0, 0), "saillance": 1.0 },
	]
	var d_annulee := Fuite.direction(colon_position, choses_opposees)
	verif.v(d_annulee == Vector3.ZERO,
		"deux repulsions egales et opposees s'annulent exactement : ZERO, pas un vecteur au hasard")
