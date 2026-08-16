extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_usure_attache.gd
#
# Verrouille scripts/usure_attache.gd comme mecanisme GENERIQUE d'erosion
# des attaches deja cristallisees -- pas un code de colon. Domaine invente
# (cristal_gravitique_*, meme famille que test_deformation.gd/
# test_epigenetique.gd) : ce test prouve que avancer() traverse le meme
# code quel que soit le domaine.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque
# (les deux catalogues sont des Dictionary construits ici, jamais
# data/usure_attaches.json ni data/contradictions_attaches.json).

const Usure = preload("res://scripts/usure_attache.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_usure_passive_erode_la_force_sans_perception(v)
	_plancher_jamais_franchi_meme_apres_longtemps(v)
	_perception_du_trait_gele_l_usure(v)
	_contradiction_erode_plus_vite_que_l_usure_passive(v)
	_plusieurs_attaches_independantes(v)
	_attaches_absente_alarme_sans_rien_ecrire(v)
	_catalogue_usure_sans_defaut_alarme_sans_rien_ecrire(v)
	_catalogue_usure_incomplet_alarme_sans_rien_ecrire(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: usure_attache.gd erode la force des attaches cristallisees sans jamais les retirer, " +
			"generique a tout domaine invente")
		quit(0)

func _cristal(id: String, attaches: Array) -> Dictionary:
	return {"id": id, "position": Vector3.ZERO, "proprietes": {"attaches": attaches}}

func _perception(trait_porte: String) -> Array:
	return [{"chose": {"id": "chose_percue", "position": Vector3.ZERO, "proprietes": {trait_porte: true}}}]

func _catalogue_usure(passive: float = 0.1, contradiction: float = 0.5, plancher: float = 0.1) -> Dictionary:
	return {"defaut": {"taux_usure_passive": passive, "taux_usure_contradiction": contradiction, "force_plancher": plancher}}

func _catalogue_contradictions() -> Dictionary:
	return {"gravitique_polarite": {"trait": "champ_positif", "trait_contradictoire": "champ_negatif"}}

func _usure_passive_erode_la_force_sans_perception(v) -> void:
	var e := _cristal("cristal_1", [{"propriete": "champ_positif", "force": 1.0}])
	Usure.avancer(e, [], _catalogue_usure(0.1, 0.5, 0.1), {}, 1.0)
	v.v(is_equal_approx(e.proprietes.attaches[0].force, 0.9),
		"sans aucune perception, la force doit decroitre exactement de taux_usure_passive * delta")

func _plancher_jamais_franchi_meme_apres_longtemps(v) -> void:
	var e := _cristal("cristal_2", [{"propriete": "champ_positif", "force": 0.15}])
	var catalogue := _catalogue_usure(0.1, 0.5, 0.1)
	for _i in range(1000):
		Usure.avancer(e, [], catalogue, {}, 1.0)
		v.v(e.proprietes.attaches[0].force >= 0.1, "la force ne doit jamais descendre sous force_plancher, a aucun tick intermediaire")
	v.v(is_equal_approx(e.proprietes.attaches[0].force, 0.1),
		"apres un temps arbitrairement long sans renouvellement, la force doit se stabiliser EXACTEMENT au plancher, jamais en dessous")
	v.v(e.proprietes.attaches.size() == 1,
		"une attache emoussee au plancher ne doit JAMAIS etre retiree de proprietes.attaches -- sedimentation, pas effacement")

func _perception_du_trait_gele_l_usure(v) -> void:
	var e := _cristal("cristal_3", [{"propriete": "champ_positif", "force": 0.5}])
	Usure.avancer(e, _perception("champ_positif"), _catalogue_usure(0.5, 0.5, 0.1), {}, 10.0)
	v.v(is_equal_approx(e.proprietes.attaches[0].force, 0.5),
		"percevoir une chose portant le trait de l'attache doit geler toute usure ce tick, meme a grand delta")

func _contradiction_erode_plus_vite_que_l_usure_passive(v) -> void:
	var e_passif := _cristal("cristal_4a", [{"propriete": "champ_positif", "force": 1.0}])
	var e_contredit := _cristal("cristal_4b", [{"propriete": "champ_positif", "force": 1.0}])
	var catalogue := _catalogue_usure(0.1, 0.5, 0.1)
	Usure.avancer(e_passif, [], catalogue, _catalogue_contradictions(), 1.0)
	Usure.avancer(e_contredit, _perception("champ_negatif"), catalogue, _catalogue_contradictions(), 1.0)
	v.v(e_contredit.proprietes.attaches[0].force < e_passif.proprietes.attaches[0].force,
		"percevoir une chose portant le trait contradictoire doit eroder la force plus vite que l'usure passive seule")
	v.v(is_equal_approx(e_contredit.proprietes.attaches[0].force, 0.5),
		"la contradiction doit appliquer exactement taux_usure_contradiction, jamais taux_usure_passive EN PLUS")

func _plusieurs_attaches_independantes(v) -> void:
	var e := _cristal("cristal_5", [
		{"propriete": "champ_positif", "force": 1.0},
		{"propriete": "champ_secondaire", "force": 1.0},
	])
	Usure.avancer(e, _perception("champ_positif"), _catalogue_usure(0.1, 0.5, 0.1), {}, 1.0)
	v.v(is_equal_approx(e.proprietes.attaches[0].force, 1.0),
		"l'attache dont le trait est percu doit rester gelee, independamment des autres")
	v.v(is_equal_approx(e.proprietes.attaches[1].force, 0.9),
		"une autre attache du meme colon, dont le trait n'est pas percu, doit continuer d'eroder normalement")

func _attaches_absente_alarme_sans_rien_ecrire(v) -> void:
	var e := {"id": "cristal_6", "position": Vector3.ZERO, "proprietes": {}}
	Usure.avancer(e, [], _catalogue_usure(), {}, 1.0)
	v.v(not e.proprietes.has("attaches"), "propriete structurelle 'attaches' absente doit alarmer sans rien creer")

func _catalogue_usure_sans_defaut_alarme_sans_rien_ecrire(v) -> void:
	var e := _cristal("cristal_7", [{"propriete": "champ_positif", "force": 1.0}])
	Usure.avancer(e, [], {}, {}, 1.0)
	v.v(is_equal_approx(e.proprietes.attaches[0].force, 1.0),
		"un catalogue usure sans entree 'defaut' doit alarmer et ne rien ecrire sur aucune attache")

func _catalogue_usure_incomplet_alarme_sans_rien_ecrire(v) -> void:
	var e1 := _cristal("cristal_8a", [{"propriete": "champ_positif", "force": 1.0}])
	Usure.avancer(e1, [], {"defaut": {"taux_usure_contradiction": 0.5, "force_plancher": 0.1}}, {}, 1.0)
	v.v(is_equal_approx(e1.proprietes.attaches[0].force, 1.0),
		"'defaut' sans 'taux_usure_passive' doit alarmer sans rien ecrire")

	var e2 := _cristal("cristal_8b", [{"propriete": "champ_positif", "force": 1.0}])
	Usure.avancer(e2, [], {"defaut": {"taux_usure_passive": 0.1, "force_plancher": 0.1}}, {}, 1.0)
	v.v(is_equal_approx(e2.proprietes.attaches[0].force, 1.0),
		"'defaut' sans 'taux_usure_contradiction' doit alarmer sans rien ecrire")

	var e3 := _cristal("cristal_8c", [{"propriete": "champ_positif", "force": 1.0}])
	Usure.avancer(e3, [], {"defaut": {"taux_usure_passive": 0.1, "taux_usure_contradiction": 0.5}}, {}, 1.0)
	v.v(is_equal_approx(e3.proprietes.attaches[0].force, 1.0),
		"'defaut' sans 'force_plancher' doit alarmer sans rien ecrire")

func _resumabilite_json_stricte(v) -> void:
	var e := {
		"id": "cristal_9",
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"proprietes": {"attaches": [{"propriete": "champ_positif", "force": 1.0}]},
	}
	Usure.avancer(e, [], _catalogue_usure(0.1, 0.5, 0.1), {}, 2.0)
	var texte := JSON.stringify(e)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	v.v(is_equal_approx(relu.proprietes.attaches[0].force, e.proprietes.attaches[0].force),
		"le champ force erode doit survivre identique a l'aller-retour JSON")
