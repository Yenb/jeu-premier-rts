extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_lien_personnel.gd
#
# Verrouille scripts/lien_personnel.gd comme mecanisme GENERIQUE de force
# de lien vers une chose PRECISE -- pas un code de colon, de foret ni de
# chambre. Chose hors domaine (cristal_gravitique_42, jamais vu ailleurs
# dans le depot) : ce test prouve que poser/avancer/force traversent le
# meme code quelle que soit la chose visee.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque
# (le catalogue est un Dictionary construit ici, jamais data/liens_personnels.json).

const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_poser_cree_lentree_avec_la_magnitude_donnee(v)
	_second_poser_accumule_ne_remplace_pas(v)
	_avancer_decroit_selon_taux_et_delta(v)
	_avancer_retire_lentree_sous_le_plancher(v)
	_force_rend_zero_pour_chose_sans_lien(v)
	_force_rend_la_valeur_numerique_correcte(v)
	_avancer_alarme_sur_catalogue_sans_defaut(v)
	_propriete_structurelle_absente_alarme(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: lien_personnel.gd pose/avance/lit une force de lien vers une chose precise, " +
			"generique a toute chose invente")
		quit(0)

func _entite(id: String, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _catalogue() -> Dictionary:
	return {
		"defaut": {
			"taux_decroissance": 0.001,
			"plancher_suppression": 0.01,
		},
	}

func _poser_cree_lentree_avec_la_magnitude_donnee(v) -> void:
	var gardien := _entite("gardien_1", {"liens_personnels": {}})
	LienPersonnel.poser(gardien, "cristal_gravitique_42", 0.5)
	var liens: Dictionary = gardien.proprietes.liens_personnels
	v.v(liens.has("cristal_gravitique_42"), "poser doit creer l'entree pour la chose visee")
	v.v(liens["cristal_gravitique_42"] == 0.5, "poser doit poser la magnitude donnee")

func _second_poser_accumule_ne_remplace_pas(v) -> void:
	var gardien := _entite("gardien_2", {"liens_personnels": {}})
	LienPersonnel.poser(gardien, "cristal_gravitique_42", 0.5)
	LienPersonnel.poser(gardien, "cristal_gravitique_42", 0.3)
	var force_actuelle: float = gardien.proprietes.liens_personnels["cristal_gravitique_42"]
	v.v(is_equal_approx(force_actuelle, 0.8), "un renouvellement doit accumuler (+=), jamais remplacer")

func _avancer_decroit_selon_taux_et_delta(v) -> void:
	var gardien := _entite("gardien_3", {
		"liens_personnels": {"cristal_gravitique_42": 1.0},
	})
	LienPersonnel.avancer(gardien, 100.0, _catalogue())
	var force_restante: float = gardien.proprietes.liens_personnels["cristal_gravitique_42"]
	v.v(is_equal_approx(force_restante, 0.9), "la force doit decroitre de taux_decroissance * delta (0.001 * 100.0)")

func _avancer_retire_lentree_sous_le_plancher(v) -> void:
	var gardien := _entite("gardien_4", {
		"liens_personnels": {"cristal_gravitique_42": 0.02},
	})
	LienPersonnel.avancer(gardien, 100.0, _catalogue())
	var liens: Dictionary = gardien.proprietes.liens_personnels
	v.v(not liens.has("cristal_gravitique_42"),
		"une force tombee sous plancher_suppression doit retirer l'entree, jamais rester a une valeur residuelle")

func _force_rend_zero_pour_chose_sans_lien(v) -> void:
	var gardien := _entite("gardien_5", {"liens_personnels": {}})
	var f := LienPersonnel.force(gardien, "cristal_gravitique_42", _catalogue())
	v.v(f == 0.0, "force doit rendre 0.0 pour une chose sans lien enregistre, jamais une alarme")

func _force_rend_la_valeur_numerique_correcte(v) -> void:
	var gardien := _entite("gardien_6", {
		"liens_personnels": {"cristal_gravitique_42": 0.73},
	})
	var f := LienPersonnel.force(gardien, "cristal_gravitique_42", _catalogue())
	v.v(is_equal_approx(f, 0.73), "force doit rendre la valeur numerique exacte enregistree")

func _avancer_alarme_sur_catalogue_sans_defaut(v) -> void:
	var gardien := _entite("gardien_7", {
		"liens_personnels": {"cristal_gravitique_42": 1.0},
	})
	LienPersonnel.avancer(gardien, 100.0, {})
	var force_restante: float = gardien.proprietes.liens_personnels["cristal_gravitique_42"]
	v.v(force_restante == 1.0,
		"un catalogue sans entree 'defaut' doit alarmer et laisser le registre intact")

func _propriete_structurelle_absente_alarme(v) -> void:
	var gardien := _entite("gardien_8", {})
	LienPersonnel.poser(gardien, "cristal_gravitique_42", 0.5)
	v.v(not gardien.proprietes.has("liens_personnels"),
		"proprietes sans la cle structurelle 'liens_personnels' ne doit rien ecrire (alarme, pas defaut silencieux)")
	LienPersonnel.avancer(gardien, 1.0, _catalogue())
	var f := LienPersonnel.force(gardien, "cristal_gravitique_42", _catalogue())
	v.v(f == 0.0, "force sur une entite sans cle 'liens_personnels' doit alarmer et rendre 0.0")

# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# proprietes.liens_personnels ne doit porter que du JSON pur -- aucun
# Vector3, aucun Callable -- et redonner exactement la meme structure
# apres un aller-retour JSON.stringify/parse_string.
func _resumabilite_json_stricte(v) -> void:
	var gardien := _entite("gardien_9", {
		"position": {"x": 1.0, "y": 0.0, "z": 2.0},
		"liens_personnels": {},
	})
	LienPersonnel.poser(gardien, "cristal_gravitique_42", 0.5)
	LienPersonnel.avancer(gardien, 1.0, _catalogue())
	var texte := JSON.stringify(gardien)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	var force_originale: float = gardien.proprietes.liens_personnels["cristal_gravitique_42"]
	var force_relue: float = relu.proprietes.liens_personnels["cristal_gravitique_42"]
	v.v(is_equal_approx(force_relue, force_originale),
		"la force doit survivre identique a l'aller-retour JSON")
	v.v(relu.proprietes.position.x == 1.0 and relu.proprietes.position.z == 2.0,
		"une position deja serialisee en {x,y,z} doit survivre identique, jamais un Vector3")
