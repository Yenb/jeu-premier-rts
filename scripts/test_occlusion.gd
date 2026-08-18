extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_occlusion.gd
#
# Verrouille scripts/occlusion.gd comme GEOMETRIE PURE, jamais comme un code
# de son, de vue ou de pluie. Noms de propriete fictifs ("freine_le_flux"),
# sans aucun rapport avec absorption_sonore/densite/opacite/relief_bloquant --
# meme discipline hors domaine que test_velocite.gd/test_ecoulement.gd.
#
# Verrouille AUSSI la non-regression de l'extraction : les cas couverts ici
# sont exactement les regles que perception.gd:_facteur_obstacles appliquait
# avant d'etre vide de sa geometrie (projection, t dans ]0,1[, distance
# laterale, cumul multiplicatif, bornage [0,1], gates). test_perception.gd
# reste le juge du comportement bout-en-bout ; ce test-ci juge la geometrie
# seule.
#
# UNE ERREUR EST POUSSEE VOLONTAIREMENT par le dernier cas (obstacle sans
# 'position') : "occlusion.gd : obstacle #N sans 'position', ignore" dans la
# sortie n'est PAS un echec, c'est le comportement verifie.

const Occlusion = preload("res://scripts/occlusion.gd")
const Verif = preload("res://scripts/verif.gd")

const PROPRIETE := "freine_le_flux"
const LARGEUR := 0.5

func _init() -> void:
	var v := Verif.new()
	_sans_obstacle_le_facteur_est_neutre(v)
	_un_obstacle_sur_le_segment_attenue_de_sa_valeur(v)
	_un_obstacle_plus_dense_attenue_plus(v)
	_un_obstacle_hors_de_la_largeur_laterale_n_attenue_rien(v)
	_un_obstacle_derriere_un_bout_n_attenue_rien(v)
	_deux_obstacles_cumulent_multiplicativement(v)
	_la_valeur_est_bornee_entre_zero_et_un(v)
	_une_propriete_vide_court_circuite(v)
	_un_segment_degenere_court_circuite(v)
	_les_ids_exclus_ne_comptent_jamais_comme_obstacles(v)
	_le_sens_du_segment_ne_change_pas_le_resultat(v)
	_attenuer_par_distance_suit_la_puissance_inverse(v)
	_un_obstacle_sans_position_est_ignore_seul(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: occlusion.gd rend un facteur [0,1] par projection sur le segment " +
			"(t strictement dans ]0,1[), distance laterale bornee, cumul multiplicatif " +
			"de plusieurs obstacles, valeur bornee [0,1], gates neutres (propriete vide, " +
			"segment degenere, ids exclus), symetrique au sens du segment ; " +
			"attenuer_par_distance suit force/distance^exposant sans jamais diviser par " +
			"zero, aucun nom de propriete de domaine")
		quit(0)

func _obstacle(id: String, position: Vector3, valeur: float) -> Dictionary:
	return {"id": id, "position": position, "proprietes": {PROPRIETE: valeur}}

# Segment de reference, partage par la plupart des cas : de (0,0,0) a
# (10,0,0). Un obstacle pose en (5,0,0) est pile au milieu, distance
# laterale 0.0.
func _depuis() -> Vector3:
	return Vector3(0.0, 0.0, 0.0)

func _vers() -> Vector3:
	return Vector3(10.0, 0.0, 0.0)

func _sans_obstacle_le_facteur_est_neutre(v) -> void:
	var f := Occlusion.facteur(_depuis(), _vers(), [], PROPRIETE, LARGEUR)
	v.v(is_equal_approx(f, 1.0), "aucun obstacle : le facteur doit valoir exactement 1.0, pas %f" % f)

func _un_obstacle_sur_le_segment_attenue_de_sa_valeur(v) -> void:
	var obstacles := [_obstacle("mur", Vector3(5.0, 0.0, 0.0), 0.3)]
	var f := Occlusion.facteur(_depuis(), _vers(), obstacles, PROPRIETE, LARGEUR)
	v.v(is_equal_approx(f, 0.7), "un obstacle de valeur 0.3 doit rendre exactement 1.0-0.3=0.7, pas %f" % f)

func _un_obstacle_plus_dense_attenue_plus(v) -> void:
	var leger := Occlusion.facteur(_depuis(), _vers(), [_obstacle("m", Vector3(5.0, 0.0, 0.0), 0.2)], PROPRIETE, LARGEUR)
	var dense := Occlusion.facteur(_depuis(), _vers(), [_obstacle("m", Vector3(5.0, 0.0, 0.0), 0.8)], PROPRIETE, LARGEUR)
	v.v(dense < leger, "un obstacle plus dense (0.8) doit rendre un facteur strictement plus petit qu'un obstacle leger (0.2)")
	v.v(is_equal_approx(dense, 0.2) and is_equal_approx(leger, 0.8),
		"les deux facteurs doivent valoir exactement 1.0 - valeur (0.2 et 0.8)")

# Distance laterale 2.0, tres au-dela de LARGEUR (0.5) : jamais retenu,
# meme a attenuation totale.
func _un_obstacle_hors_de_la_largeur_laterale_n_attenue_rien(v) -> void:
	var obstacles := [_obstacle("a_cote", Vector3(5.0, 2.0, 0.0), 1.0)]
	var f := Occlusion.facteur(_depuis(), _vers(), obstacles, PROPRIETE, LARGEUR)
	v.v(is_equal_approx(f, 1.0), "un obstacle hors de la largeur laterale, meme opaque a 100%%, ne doit jamais compter (facteur %f)" % f)

# t <= 0.0 (derriere le depart) et t >= 1.0 (au-dela de l'arrivee, ou
# exactement dessus) : jamais retenus.
func _un_obstacle_derriere_un_bout_n_attenue_rien(v) -> void:
	var derriere := [_obstacle("derriere", Vector3(-3.0, 0.0, 0.0), 1.0)]
	var au_dela := [_obstacle("au_dela", Vector3(14.0, 0.0, 0.0), 1.0)]
	var sur_le_bout := [_obstacle("sur_le_bout", Vector3(10.0, 0.0, 0.0), 1.0)]
	v.v(is_equal_approx(Occlusion.facteur(_depuis(), _vers(), derriere, PROPRIETE, LARGEUR), 1.0),
		"un obstacle en amont du depart (t<0) ne doit jamais compter")
	v.v(is_equal_approx(Occlusion.facteur(_depuis(), _vers(), au_dela, PROPRIETE, LARGEUR), 1.0),
		"un obstacle au-dela de l'arrivee (t>1) ne doit jamais compter")
	v.v(is_equal_approx(Occlusion.facteur(_depuis(), _vers(), sur_le_bout, PROPRIETE, LARGEUR), 1.0),
		"un obstacle exactement sur l'arrivee (t=1) ne doit jamais compter")

func _deux_obstacles_cumulent_multiplicativement(v) -> void:
	var obstacles := [
		_obstacle("premier", Vector3(3.0, 0.0, 0.0), 0.5),
		_obstacle("second", Vector3(7.0, 0.0, 0.0), 0.5),
	]
	var f := Occlusion.facteur(_depuis(), _vers(), obstacles, PROPRIETE, LARGEUR)
	v.v(is_equal_approx(f, 0.25), "deux obstacles a 0.5 doivent cumuler en 0.5*0.5=0.25 (jamais une somme), pas %f" % f)
	var un_seul := Occlusion.facteur(_depuis(), _vers(), [obstacles[0]], PROPRIETE, LARGEUR)
	v.v(f < un_seul, "deux obstacles doivent attenuer strictement plus qu'un seul")

# Une valeur > 1.0 borne a 1.0 (blocage TOTAL, jamais un facteur negatif) ;
# une valeur negative borne a 0.0 (transparent, jamais une amplification).
func _la_valeur_est_bornee_entre_zero_et_un(v) -> void:
	var enorme := Occlusion.facteur(_depuis(), _vers(), [_obstacle("montagne", Vector3(5.0, 0.0, 0.0), 20.0)], PROPRIETE, LARGEUR)
	var negative := Occlusion.facteur(_depuis(), _vers(), [_obstacle("absurde", Vector3(5.0, 0.0, 0.0), -5.0)], PROPRIETE, LARGEUR)
	v.v(is_equal_approx(enorme, 0.0), "une valeur au-dessus de 1.0 doit borner a 1.0 -> facteur 0.0 (blocage total), pas %f" % enorme)
	v.v(is_equal_approx(negative, 1.0), "une valeur negative doit borner a 0.0 -> facteur neutre 1.0, jamais une amplification (%f)" % negative)

func _une_propriete_vide_court_circuite(v) -> void:
	var obstacles := [_obstacle("mur", Vector3(5.0, 0.0, 0.0), 1.0)]
	var f := Occlusion.facteur(_depuis(), _vers(), obstacles, "", LARGEUR)
	v.v(is_equal_approx(f, 1.0), "propriete_obstacle vide : facteur neutre 1.0 quels que soient les obstacles, pas %f" % f)

func _un_segment_degenere_court_circuite(v) -> void:
	var obstacles := [_obstacle("mur", Vector3(5.0, 0.0, 0.0), 1.0)]
	var f := Occlusion.facteur(_depuis(), _depuis(), obstacles, PROPRIETE, LARGEUR)
	v.v(is_equal_approx(f, 1.0), "segment de longueur nulle : facteur neutre 1.0, pas %f" % f)

func _les_ids_exclus_ne_comptent_jamais_comme_obstacles(v) -> void:
	var obstacles := [_obstacle("lui_meme", Vector3(5.0, 0.0, 0.0), 1.0)]
	var sans_exclusion := Occlusion.facteur(_depuis(), _vers(), obstacles, PROPRIETE, LARGEUR)
	var avec_exclusion := Occlusion.facteur(_depuis(), _vers(), obstacles, PROPRIETE, LARGEUR, ["lui_meme"])
	v.v(is_equal_approx(sans_exclusion, 0.0), "sans exclusion, l'obstacle opaque doit bloquer totalement")
	v.v(is_equal_approx(avec_exclusion, 1.0), "un id exclu ne doit jamais compter comme obstacle, meme opaque et pile sur le segment")

func _le_sens_du_segment_ne_change_pas_le_resultat(v) -> void:
	var obstacles := [_obstacle("mur", Vector3(3.0, 0.2, 0.0), 0.4)]
	var aller := Occlusion.facteur(_depuis(), _vers(), obstacles, PROPRIETE, LARGEUR)
	var retour := Occlusion.facteur(_vers(), _depuis(), obstacles, PROPRIETE, LARGEUR)
	v.v(is_equal_approx(aller, retour), "le facteur doit etre le meme dans les deux sens du segment (%f vs %f)" % [aller, retour])

func _attenuer_par_distance_suit_la_puissance_inverse(v) -> void:
	v.v(is_equal_approx(Occlusion.attenuer_par_distance(100.0, 4.0, 1.0), 25.0),
		"exposant 1.0 : 100/4 = 25.0")
	v.v(is_equal_approx(Occlusion.attenuer_par_distance(100.0, 4.0, 2.0), 6.25),
		"exposant 2.0 : 100/16 = 6.25")
	v.v(is_equal_approx(Occlusion.attenuer_par_distance(100.0, 4.0, 0.0), 100.0),
		"exposant 0.0 : aucune attenuation, la force passe telle quelle")
	v.v(is_equal_approx(Occlusion.attenuer_par_distance(100.0, 0.0, 2.0), 100.0),
		"distance nulle : rend la force telle quelle, jamais une division par zero ni INF")
	var loin := Occlusion.attenuer_par_distance(100.0, 1000.0, 2.0)
	v.v(loin > 0.0 and loin < 0.001, "tres loin : l'intensite tend vers zero sans jamais y arriver exactement (%f)" % loin)

# Structurel : un obstacle sans 'position' n'a aucun sens. Il est ignore
# SEUL (push_error nommant son index), les autres continuent d'attenuer.
func _un_obstacle_sans_position_est_ignore_seul(v) -> void:
	var obstacles := [
		{"id": "incomplet", "proprietes": {PROPRIETE: 1.0}},
		_obstacle("valide", Vector3(5.0, 0.0, 0.0), 0.5),
	]
	var f := Occlusion.facteur(_depuis(), _vers(), obstacles, PROPRIETE, LARGEUR)
	v.v(is_equal_approx(f, 0.5), "un obstacle sans position est ignore seul, l'obstacle valide attenue normalement (attendu 0.5, obtenu %f)" % f)
