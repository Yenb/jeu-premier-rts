extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_champ_occulte.gd
#
# Verrouille scripts/champ_occulte.gd comme CHAMP SCALAIRE ATTENUE PAR LES
# OBSTACLES, jamais comme un code de pluie, de mer ou de montagne. Noms de
# propriete fictifs ("flux_ambiant_emis" / "freine_le_flux"), sans aucun
# rapport avec humidite_emission/relief_bloquant -- meme discipline hors
# domaine que test_occlusion.gd/test_ecoulement.gd.
#
# CE QUE CE TEST DOIT PROUVER AVANT TOUT (la raison d'etre du mecanisme,
# audit_terrain_et_monde_prealable.md §7) : derriere un obstacle l'intensite
# est REDUITE, jamais coupee -- une ombre, pas une frontiere. C'est ce que
# perception.gd ne pouvait pas rendre (filtre binaire percu/non percu).
#
# UNE ERREUR EST POUSSEE VOLONTAIREMENT par l'avant-dernier cas (source sans
# 'position') : "champ_occulte.gd : source #N sans 'position', ignoree" dans
# la sortie n'est PAS un echec, c'est le comportement verifie.

const ChampOcculte = preload("res://scripts/champ_occulte.gd")
const Verif = preload("res://scripts/verif.gd")

const EMISSION := "flux_ambiant_emis"
const OBSTACLE := "freine_le_flux"
const LARGEUR := 0.5
const EXPOSANT := 1.0

func _init() -> void:
	var v := Verif.new()
	_sans_obstacle_l_intensite_suit_la_loi_de_distance(v)
	_un_obstacle_entre_les_deux_reduit_sans_couper(v)
	_un_obstacle_plus_dense_reduit_plus(v)
	_un_obstacle_hors_du_segment_ne_reduit_rien(v)
	_plusieurs_obstacles_cumulent_multiplicativement(v)
	_une_source_tres_loin_ne_contribue_presque_rien(v)
	_plusieurs_sources_s_additionnent(v)
	_une_occlusion_ne_retire_rien_aux_autres_sources(v)
	_une_source_sans_propriete_d_emission_ne_contribue_rien(v)
	_une_propriete_d_obstacle_vide_annule_toute_occlusion(v)
	_une_source_sans_position_est_ignoree_seule(v)
	_aucune_source_rend_zero(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: champ_occulte.gd rend une INTENSITE (jamais un booleen percu/non percu) : " +
			"somme additive des sources, chacune attenuee par la distance (puissance inverse) " +
			"et par les obstacles du segment source->point (cumul multiplicatif) ; derriere un " +
			"obstacle l'intensite est reduite mais jamais coupee, un obstacle hors du segment " +
			"ne reduit rien, une source lointaine tend vers zero, une source incomplete est " +
			"ignoree seule, aucun nom de propriete de domaine")
		quit(0)

func _source(position: Vector3, force: float) -> Dictionary:
	return {"id": "source", "position": position, "proprietes": {EMISSION: force}}

func _obstacle(id: String, position: Vector3, valeur: float) -> Dictionary:
	return {"id": id, "position": position, "proprietes": {OBSTACLE: valeur}}

func _intensite(position: Vector3, sources: Array, obstacles: Array) -> float:
	return ChampOcculte.intensite_locale(position, sources, obstacles, OBSTACLE, LARGEUR, EMISSION, EXPOSANT)

# Source en (0,0,0), force 100.0 ; point interroge en (10,0,0), distance
# 10.0, exposant 1.0 -> 100/10 = 10.0 exactement.
func _sans_obstacle_l_intensite_suit_la_loi_de_distance(v) -> void:
	var i := _intensite(Vector3(10.0, 0.0, 0.0), [_source(Vector3.ZERO, 100.0)], [])
	v.v(is_equal_approx(i, 10.0), "sans obstacle : intensite = force/distance^exposant = 100/10 = 10.0, pas %f" % i)
	var i2 := ChampOcculte.intensite_locale(Vector3(10.0, 0.0, 0.0), [_source(Vector3.ZERO, 100.0)], [], OBSTACLE, LARGEUR, EMISSION, 2.0)
	v.v(is_equal_approx(i2, 1.0), "exposant 2.0 : 100/100 = 1.0, pas %f" % i2)

func _un_obstacle_entre_les_deux_reduit_sans_couper(v) -> void:
	var sources := [_source(Vector3.ZERO, 100.0)]
	var obstacles := [_obstacle("relief", Vector3(5.0, 0.0, 0.0), 0.6)]
	var i := _intensite(Vector3(10.0, 0.0, 0.0), sources, obstacles)
	v.v(is_equal_approx(i, 4.0), "un obstacle de valeur 0.6 doit rendre 10.0*(1-0.6)=4.0, pas %f" % i)
	v.v(i > 0.0, "DOCTRINE : derriere l'obstacle l'intensite est REDUITE, jamais coupee -- une ombre, pas une frontiere")

func _un_obstacle_plus_dense_reduit_plus(v) -> void:
	var sources := [_source(Vector3.ZERO, 100.0)]
	var leger := _intensite(Vector3(10.0, 0.0, 0.0), sources, [_obstacle("colline", Vector3(5.0, 0.0, 0.0), 0.2)])
	var dense := _intensite(Vector3(10.0, 0.0, 0.0), sources, [_obstacle("montagne", Vector3(5.0, 0.0, 0.0), 0.8)])
	v.v(dense < leger, "un obstacle plus dense doit laisser passer strictement moins (%f vs %f)" % [dense, leger])
	v.v(is_equal_approx(leger, 8.0) and is_equal_approx(dense, 2.0),
		"les deux intensites doivent valoir exactement 10.0*(1-valeur) : 8.0 et 2.0")

# Distance laterale 3.0, tres au-dela de LARGEUR (0.5) : jamais retenu.
func _un_obstacle_hors_du_segment_ne_reduit_rien(v) -> void:
	var sources := [_source(Vector3.ZERO, 100.0)]
	var obstacles := [_obstacle("a_cote", Vector3(5.0, 3.0, 0.0), 1.0)]
	var i := _intensite(Vector3(10.0, 0.0, 0.0), sources, obstacles)
	v.v(is_equal_approx(i, 10.0), "un obstacle hors du segment, meme bloquant a 100%%, ne doit rien reduire (%f)" % i)

func _plusieurs_obstacles_cumulent_multiplicativement(v) -> void:
	var sources := [_source(Vector3.ZERO, 100.0)]
	var obstacles := [
		_obstacle("premier", Vector3(3.0, 0.0, 0.0), 0.5),
		_obstacle("second", Vector3(7.0, 0.0, 0.0), 0.5),
	]
	var i := _intensite(Vector3(10.0, 0.0, 0.0), sources, obstacles)
	v.v(is_equal_approx(i, 2.5), "deux obstacles a 0.5 : 10.0*0.5*0.5 = 2.5 (jamais une somme), pas %f" % i)

func _une_source_tres_loin_ne_contribue_presque_rien(v) -> void:
	var i := ChampOcculte.intensite_locale(Vector3(5000.0, 0.0, 0.0), [_source(Vector3.ZERO, 100.0)], [], OBSTACLE, LARGEUR, EMISSION, 2.0)
	v.v(i > 0.0 and i < 0.001, "une source tres loin doit tendre vers zero sans jamais y arriver exactement (%f)" % i)

func _plusieurs_sources_s_additionnent(v) -> void:
	var sources := [
		_source(Vector3(0.0, 0.0, 0.0), 100.0),
		_source(Vector3(20.0, 0.0, 0.0), 100.0),
	]
	var i := _intensite(Vector3(10.0, 0.0, 0.0), sources, [])
	v.v(is_equal_approx(i, 20.0), "deux sources equidistantes s'ADDITIONNENT : 10.0+10.0 = 20.0, pas %f" % i)

# Un obstacle place sur le segment de la PREMIERE source seulement ne doit
# rien retirer a la contribution de la seconde.
func _une_occlusion_ne_retire_rien_aux_autres_sources(v) -> void:
	var sources := [
		_source(Vector3(0.0, 0.0, 0.0), 100.0),
		_source(Vector3(10.0, 20.0, 0.0), 100.0),
	]
	var obstacles := [_obstacle("relief", Vector3(5.0, 0.0, 0.0), 1.0)]
	var i := _intensite(Vector3(10.0, 0.0, 0.0), sources, obstacles)
	v.v(is_equal_approx(i, 5.0), "la premiere source est bloquee totalement, la seconde (distance 20) contribue intacte 100/20=5.0, pas %f" % i)

func _une_source_sans_propriete_d_emission_ne_contribue_rien(v) -> void:
	var muette := {"id": "muette", "position": Vector3.ZERO, "proprietes": {}}
	var i := _intensite(Vector3(10.0, 0.0, 0.0), [muette], [])
	v.v(is_equal_approx(i, 0.0), "une source qui ne porte pas la propriete d'emission ne contribue rien, sans alarme (%f)" % i)

func _une_propriete_d_obstacle_vide_annule_toute_occlusion(v) -> void:
	var sources := [_source(Vector3.ZERO, 100.0)]
	var obstacles := [_obstacle("relief", Vector3(5.0, 0.0, 0.0), 1.0)]
	var i := ChampOcculte.intensite_locale(Vector3(10.0, 0.0, 0.0), sources, obstacles, "", LARGEUR, EMISSION, EXPOSANT)
	v.v(is_equal_approx(i, 10.0), "propriete_obstacle vide : le champ redevient un pur lumiere.gd:locale, aucune occlusion testee (%f)" % i)

# Structurel : une source sans 'position' n'a aucun sens. Elle est ignoree
# SEULE (push_error nommant son index), les autres continuent.
func _une_source_sans_position_est_ignoree_seule(v) -> void:
	var sources := [
		{"id": "incomplete", "proprietes": {EMISSION: 999.0}},
		_source(Vector3.ZERO, 100.0),
	]
	var i := _intensite(Vector3(10.0, 0.0, 0.0), sources, [])
	v.v(is_equal_approx(i, 10.0), "une source sans position est ignoree seule, la source valide contribue normalement (attendu 10.0, obtenu %f)" % i)

func _aucune_source_rend_zero(v) -> void:
	var i := _intensite(Vector3(10.0, 0.0, 0.0), [], [])
	v.v(is_equal_approx(i, 0.0), "aucune source : intensite 0.0, jamais une valeur inventee (%f)" % i)
