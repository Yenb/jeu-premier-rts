extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_lien_personnel_saillance.gd
#
# Verrouille scripts/lien_personnel_saillance.gd comme mecanisme GENERIQUE
# de bonus de saillance par lien personnel -- pas un code de colon, de
# batisse ni de pompier. Domaine invente (robot_gardien / phare_1 / phare_2,
# jamais vus ailleurs dans le depot) : ce test prouve que bonus() traverse
# le meme code quelle que soit la chose visee ou la chose liee.
#
# Utilise la vraie classe Monde (scripts/monde.gd, deja generique et hors
# domaine par construction) comme fixture -- pas un duck-type maison :
# monde.par_id() est le seul contrat que bonus() attend.

const LienPersonnelSaillance = preload("res://scripts/lien_personnel_saillance.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_sans_lien_bonus_nul(v)
	_lien_sur_chose_proche_donne_bonus_positif(v)
	_hors_de_portee_menace_bonus_nul(v)
	_formule_exacte_verifiee(v)
	_plusieurs_liens_saditionnent(v)
	_chose_liee_detruite_ignoree_silencieusement(v)
	_propriete_structurelle_absente_alarme(v)
	_catalogue_sans_portee_menace_alarme(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: lien_personnel_saillance.gd rend un bonus de saillance additif " +
			"pour toute chose percue proche d'une chose liee, generique a tout domaine invente")
		quit(0)

func _entite(id: String, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _chose(id: String, position: Vector3) -> Dictionary:
	return {"id": id, "position": position, "proprietes": {}}

func _catalogue(portee_menace: float = 100.0) -> Dictionary:
	return {"defaut": {"portee_menace": portee_menace}}

func _monde_avec(choses: Array) -> Monde:
	var monde := Monde.new()
	for c in choses:
		monde.ajouter(c, "phare", c.position)
	return monde

func _sans_lien_bonus_nul(v) -> void:
	var robot := _entite("robot_gardien_1", {"liens_personnels": {}})
	var phare := _chose("phare_1", Vector3(0.0, 0.0, 0.0))
	var monde := _monde_avec([phare])
	var b := LienPersonnelSaillance.bonus(robot, phare, monde, _catalogue())
	v.v(b == 0.0, "sans aucun lien personnel, le bonus doit etre nul")

func _lien_sur_chose_proche_donne_bonus_positif(v) -> void:
	var phare_lie := _chose("phare_1", Vector3(0.0, 0.0, 0.0))
	var robot := _entite("robot_gardien_2", {"liens_personnels": {"phare_1": 1.0}})
	var chose_proche := _chose("intrus_1", Vector3(20.0, 0.0, 0.0))
	var monde := _monde_avec([phare_lie, chose_proche])
	var b := LienPersonnelSaillance.bonus(robot, chose_proche, monde, _catalogue(100.0))
	v.v(b > 0.0, "une chose percue proche d'une chose liee doit rendre un bonus strictement positif")

func _hors_de_portee_menace_bonus_nul(v) -> void:
	var phare_lie := _chose("phare_1", Vector3(0.0, 0.0, 0.0))
	var robot := _entite("robot_gardien_3", {"liens_personnels": {"phare_1": 1.0}})
	var chose_loin := _chose("intrus_2", Vector3(500.0, 0.0, 0.0))
	var monde := _monde_avec([phare_lie, chose_loin])
	var b := LienPersonnelSaillance.bonus(robot, chose_loin, monde, _catalogue(100.0))
	v.v(b == 0.0, "une chose percue hors de portee_menace de la chose liee doit rendre un bonus nul")

func _formule_exacte_verifiee(v) -> void:
	var phare_lie := _chose("phare_1", Vector3(0.0, 0.0, 0.0))
	var robot := _entite("robot_gardien_4", {"liens_personnels": {"phare_1": 2.0}})
	var chose_percue := _chose("intrus_3", Vector3(30.0, 0.0, 0.0))
	var monde := _monde_avec([phare_lie, chose_percue])
	var b := LienPersonnelSaillance.bonus(robot, chose_percue, monde, _catalogue(100.0))
	var attendu: float = 2.0 * (1.0 - 30.0 / 100.0)
	v.v(is_equal_approx(b, attendu),
		"le bonus doit valoir exactement force_du_lien * (1.0 - distance / portee_menace) (%.6f attendu, %.6f obtenu)" % [attendu, b])

func _plusieurs_liens_saditionnent(v) -> void:
	var phare_1 := _chose("phare_1", Vector3(0.0, 0.0, 0.0))
	var phare_2 := _chose("phare_2", Vector3(200.0, 0.0, 0.0))
	var robot := _entite("robot_gardien_5", {"liens_personnels": {"phare_1": 1.0, "phare_2": 1.0}})
	var chose_percue := _chose("intrus_4", Vector3(50.0, 0.0, 0.0))
	var monde := _monde_avec([phare_1, phare_2, chose_percue])
	var b := LienPersonnelSaillance.bonus(robot, chose_percue, monde, _catalogue(100.0))
	var attendu_phare_1: float = 1.0 * (1.0 - 50.0 / 100.0)
	var attendu_phare_2: float = 1.0 * (1.0 - 150.0 / 100.0) if 150.0 < 100.0 else 0.0
	var attendu: float = attendu_phare_1 + attendu_phare_2
	v.v(is_equal_approx(b, attendu),
		"plusieurs liens doivent additionner leurs contributions, jamais en garder une seule (%.6f attendu, %.6f obtenu)" % [attendu, b])

func _chose_liee_detruite_ignoree_silencieusement(v) -> void:
	var robot := _entite("robot_gardien_6", {"liens_personnels": {"phare_disparu": 1.0}})
	var chose_percue := _chose("intrus_5", Vector3(10.0, 0.0, 0.0))
	var monde := _monde_avec([chose_percue])
	var b := LienPersonnelSaillance.bonus(robot, chose_percue, monde, _catalogue(100.0))
	v.v(b == 0.0, "une chose liee absente du monde (detruite) doit etre ignoree, contribution nulle, jamais un crash")

func _propriete_structurelle_absente_alarme(v) -> void:
	var robot := _entite("robot_gardien_7", {})
	var chose_percue := _chose("intrus_6", Vector3(0.0, 0.0, 0.0))
	var monde := _monde_avec([chose_percue])
	var b := LienPersonnelSaillance.bonus(robot, chose_percue, monde, _catalogue(100.0))
	v.v(b == 0.0, "une entite sans cle 'liens_personnels' doit alarmer et rendre 0.0, jamais un defaut invente")

func _catalogue_sans_portee_menace_alarme(v) -> void:
	var phare_lie := _chose("phare_1", Vector3(0.0, 0.0, 0.0))
	var robot := _entite("robot_gardien_8", {"liens_personnels": {"phare_1": 1.0}})
	var chose_percue := _chose("intrus_7", Vector3(10.0, 0.0, 0.0))
	var monde := _monde_avec([phare_lie, chose_percue])
	var b := LienPersonnelSaillance.bonus(robot, chose_percue, monde, {})
	v.v(b == 0.0, "un catalogue sans 'defaut.portee_menace' doit alarmer et rendre 0.0")

# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) --
# bonus() ne mute jamais rien, mais l'entite lue doit rester JSON pur pour
# que ce mecanisme reste cablable a une entite reelle sans conversion.
func _resumabilite_json_stricte(v) -> void:
	var robot := _entite("robot_gardien_9", {
		"position": {"x": 1.0, "y": 0.0, "z": 2.0},
		"liens_personnels": {"phare_1": 0.5},
	})
	var texte := JSON.stringify(robot)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	v.v(relu.proprietes.liens_personnels.phare_1 == 0.5,
		"liens_personnels doit survivre identique a l'aller-retour JSON")
