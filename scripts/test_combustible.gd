extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_combustible.gd
#
# Verrouille scripts/combustible.gd:restant -- calcul PUR, hors domaine
# par construction (canal "zorg_carburant", jamais vu ailleurs dans le
# depot). Verrouille aussi la SEPARATION capacite (immuable) / reserve
# (qui decroit) sur le meme canal.

const Combustible = preload("res://scripts/combustible.gd")
const Verif = preload("res://scripts/verif.gd")

func _chose(reserves: Variant) -> Dictionary:
	var proprietes: Dictionary = {}
	if reserves != null:
		proprietes["reserves"] = reserves
	return {"id": "z", "position": Vector3.ZERO, "proprietes": proprietes}

func _init() -> void:
	var v := Verif.new()
	_restant_a_pleine_capacite(v)
	_restant_a_moitie_consomme(v)
	_restant_epuise(v)
	_restant_canal_absent_rend_zero_sans_alarme(v)
	_restant_sans_reserves_du_tout_rend_zero(v)
	_restant_capacite_nulle_rend_zero_sans_division_par_zero(v)
	_restant_reserve_negative_reste_lisible_en_absolu_mais_bornee_en_proportion(v)
	_restant_proportion_bornee_meme_si_reserve_depasse_capacite(v)
	_restant_ne_mute_jamais_la_chose(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: combustible.gd -- restant() lit capacite (immuable) et reserve (qui decroit) sur le " +
			"meme canal, rend absolu et proportion bornee, canal/reserves absents rendent un point neutre " +
			"sans alarme, jamais de division par zero")
		quit(0)

func _restant_a_pleine_capacite(v) -> void:
	var chose := _chose({"zorg_carburant": {"capacite": 10.0, "reserve": 10.0}})
	var r := Combustible.restant(chose, "zorg_carburant")
	v.v(is_equal_approx(r.absolu, 10.0), "a pleine capacite, l'absolu doit egaler la reserve (10.0)")
	v.v(is_equal_approx(r.proportion, 1.0), "a pleine capacite, la proportion doit valoir 1.0")

func _restant_a_moitie_consomme(v) -> void:
	var chose := _chose({"zorg_carburant": {"capacite": 10.0, "reserve": 5.0}})
	var r := Combustible.restant(chose, "zorg_carburant")
	v.v(is_equal_approx(r.absolu, 5.0), "a moitie consomme, l'absolu doit valoir 5.0")
	v.v(is_equal_approx(r.proportion, 0.5), "a moitie consomme, la proportion doit valoir exactement 0.5")

func _restant_epuise(v) -> void:
	var chose := _chose({"zorg_carburant": {"capacite": 10.0, "reserve": 0.0}})
	var r := Combustible.restant(chose, "zorg_carburant")
	v.v(is_equal_approx(r.absolu, 0.0) and is_equal_approx(r.proportion, 0.0),
		"epuise, l'absolu ET la proportion doivent valoir 0.0")

func _restant_canal_absent_rend_zero_sans_alarme(v) -> void:
	var chose := _chose({"autre_canal": {"capacite": 10.0, "reserve": 10.0}})
	var r := Combustible.restant(chose, "zorg_carburant")
	v.v(is_equal_approx(r.absolu, 0.0) and is_equal_approx(r.proportion, 0.0),
		"un canal absent de 'reserves' doit rendre un point neutre (0.0/0.0), jamais une alarme")

func _restant_sans_reserves_du_tout_rend_zero(v) -> void:
	var chose := _chose(null)
	var r := Combustible.restant(chose, "zorg_carburant")
	v.v(is_equal_approx(r.absolu, 0.0) and is_equal_approx(r.proportion, 0.0),
		"une chose sans 'reserves' du tout doit rendre un point neutre, jamais planter")

func _restant_capacite_nulle_rend_zero_sans_division_par_zero(v) -> void:
	var chose := _chose({"zorg_carburant": {"capacite": 0.0, "reserve": 0.0}})
	var r := Combustible.restant(chose, "zorg_carburant")
	v.v(is_equal_approx(r.proportion, 0.0), "capacite nulle : proportion doit rendre 0.0, jamais une division par zero")

func _restant_reserve_negative_reste_lisible_en_absolu_mais_bornee_en_proportion(v) -> void:
	var chose := _chose({"zorg_carburant": {"capacite": 10.0, "reserve": -3.0}})
	var r := Combustible.restant(chose, "zorg_carburant")
	v.v(is_equal_approx(r.absolu, -3.0),
		"l'absolu doit rester EXACTEMENT la reserve, meme negative -- ce fichier ne borne rien, il relit ce que depense.gd a deja borne")
	v.v(is_equal_approx(r.proportion, 0.0), "la proportion doit rester bornee a 0.0 meme si la reserve est negative")

func _restant_proportion_bornee_meme_si_reserve_depasse_capacite(v) -> void:
	var chose := _chose({"zorg_carburant": {"capacite": 10.0, "reserve": 15.0}})
	var r := Combustible.restant(chose, "zorg_carburant")
	v.v(is_equal_approx(r.proportion, 1.0), "la proportion ne doit jamais depasser 1.0, meme si la reserve depasse la capacite")

func _restant_ne_mute_jamais_la_chose(v) -> void:
	var chose := _chose({"zorg_carburant": {"capacite": 10.0, "reserve": 5.0}})
	var avant := JSON.stringify(chose.proprietes)
	Combustible.restant(chose, "zorg_carburant")
	var apres := JSON.stringify(chose.proprietes)
	v.v(avant == apres, "restant() ne doit jamais muter la chose -- fonction PURE, lecture seule")
