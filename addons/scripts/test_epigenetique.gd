extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_epigenetique.gd
#
# Verrouille scripts/epigenetique.gd comme mecanisme GENERIQUE de marque
# acquise par exposition, decroissante en son absence -- pas un code de
# colon. Domaine hors Orion : "exposition_gravitique"/"champ_gravitique",
# meme vocabulaire que test_expression.gd/data/epigenetique.json (fondation
# dormante), mais construit ICI en Dictionary local -- ce test ne lit
# jamais data/epigenetique.json sur disque.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque.

const Epigenetique = preload("res://scripts/epigenetique.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_poser_cree_la_marque_avec_le_modulateur_du_catalogue(v)
	_second_poser_renforce_accumule_ne_remplace_pas(v)
	_poser_ne_touche_pas_age_marque(v)
	_avancer_decroit_le_modulateur_par_soustraction_fixe(v)
	_avancer_incremente_age_marque_de_delta(v)
	_avancer_retire_la_marque_sous_le_plancher(v)
	_avancer_alarme_sur_marque_absente_du_catalogue_et_la_laisse_intacte(v)
	_poser_alarme_sur_marque_absente_du_catalogue_et_n_ecrit_rien(v)
	_poser_alarme_sur_propriete_structurelle_absente(v)
	_avancer_alarme_sur_propriete_structurelle_absente(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: epigenetique.gd pose/avance une marque acquise par exposition, " +
			"generique a tout domaine invente")
		quit(0)

func _entite(id: String, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _catalogue() -> Dictionary:
	return {
		"exposition_gravitique": {
			"cible": "champ_gravitique.intensite",
			"modulateur_pose": 0.05,
			"taux_decroissance": 0.01,
			"plancher_suppression": 0.005,
			"taux_transmission_enfant": 0.25,
			"source_environnementale": "exposition_gravitique_repetee",
		},
	}

func _poser_cree_la_marque_avec_le_modulateur_du_catalogue(v) -> void:
	var e := _entite("e1", {"marques_epigenetiques": {}})
	Epigenetique.poser(e, "exposition_gravitique", _catalogue())
	var marques: Dictionary = e.proprietes.marques_epigenetiques
	v.v(marques.has("exposition_gravitique"), "poser doit creer l'entree pour la marque visee")
	v.v(is_equal_approx(marques["exposition_gravitique"].modulateur, 0.05),
		"poser doit poser exactement modulateur_pose du catalogue")
	v.v(marques["exposition_gravitique"].age_marque == 0.0,
		"une marque fraichement creee doit demarrer avec age_marque a 0.0")

func _second_poser_renforce_accumule_ne_remplace_pas(v) -> void:
	var e := _entite("e2", {"marques_epigenetiques": {}})
	Epigenetique.poser(e, "exposition_gravitique", _catalogue())
	Epigenetique.poser(e, "exposition_gravitique", _catalogue())
	var modulateur: float = e.proprietes.marques_epigenetiques.exposition_gravitique.modulateur
	v.v(is_equal_approx(modulateur, 0.10), "un renouvellement doit accumuler (+=), jamais remplacer")

func _poser_ne_touche_pas_age_marque(v) -> void:
	var e := _entite("e3", {
		"marques_epigenetiques": {"exposition_gravitique": {"modulateur": 0.05, "age_marque": 12.0}},
	})
	Epigenetique.poser(e, "exposition_gravitique", _catalogue())
	v.v(e.proprietes.marques_epigenetiques.exposition_gravitique.age_marque == 12.0,
		"poser sur une marque existante ne doit jamais toucher age_marque, seul avancer le fait")

func _avancer_decroit_le_modulateur_par_soustraction_fixe(v) -> void:
	var e := _entite("e4", {
		"marques_epigenetiques": {"exposition_gravitique": {"modulateur": 0.05, "age_marque": 0.0}},
	})
	Epigenetique.avancer(e, 1.0, _catalogue())
	var modulateur: float = e.proprietes.marques_epigenetiques.exposition_gravitique.modulateur
	v.v(is_equal_approx(modulateur, 0.04),
		"le modulateur doit decroitre de taux_decroissance * delta (0.01 * 1.0), un montant absolu, jamais une fraction")

func _avancer_incremente_age_marque_de_delta(v) -> void:
	var e := _entite("e5", {
		"marques_epigenetiques": {"exposition_gravitique": {"modulateur": 0.05, "age_marque": 3.0}},
	})
	Epigenetique.avancer(e, 2.5, _catalogue())
	var age: float = e.proprietes.marques_epigenetiques.exposition_gravitique.age_marque
	v.v(is_equal_approx(age, 5.5), "age_marque doit s'incrementer de delta a chaque avancer, sans jamais redescendre")

func _avancer_retire_la_marque_sous_le_plancher(v) -> void:
	var e := _entite("e6", {
		"marques_epigenetiques": {"exposition_gravitique": {"modulateur": 0.006, "age_marque": 0.0}},
	})
	Epigenetique.avancer(e, 1.0, _catalogue())
	v.v(not e.proprietes.marques_epigenetiques.has("exposition_gravitique"),
		"un modulateur tombe sous plancher_suppression doit retirer l'entree, jamais rester a une valeur residuelle")

func _avancer_alarme_sur_marque_absente_du_catalogue_et_la_laisse_intacte(v) -> void:
	var e := _entite("e7", {
		"marques_epigenetiques": {"marque_inconnue": {"modulateur": 0.05, "age_marque": 0.0}},
	})
	Epigenetique.avancer(e, 1.0, _catalogue())
	var canal: Dictionary = e.proprietes.marques_epigenetiques.marque_inconnue
	v.v(canal.modulateur == 0.05 and canal.age_marque == 0.0,
		"une marque absente du catalogue doit alarmer et rester intacte, jamais decroitre ni etre inventee")

func _poser_alarme_sur_marque_absente_du_catalogue_et_n_ecrit_rien(v) -> void:
	var e := _entite("e8", {"marques_epigenetiques": {}})
	Epigenetique.poser(e, "marque_inconnue", _catalogue())
	v.v(e.proprietes.marques_epigenetiques.is_empty(),
		"une marque absente du catalogue doit alarmer et n'ecrire aucune entree")

func _poser_alarme_sur_propriete_structurelle_absente(v) -> void:
	var e := _entite("e9", {})
	Epigenetique.poser(e, "exposition_gravitique", _catalogue())
	v.v(not e.proprietes.has("marques_epigenetiques"),
		"proprietes sans la cle structurelle 'marques_epigenetiques' ne doit rien ecrire (alarme, pas defaut silencieux)")

func _avancer_alarme_sur_propriete_structurelle_absente(v) -> void:
	var e := _entite("e10", {})
	Epigenetique.avancer(e, 1.0, _catalogue())
	v.v(not e.proprietes.has("marques_epigenetiques"),
		"avancer sur une entite sans 'marques_epigenetiques' doit alarmer sans rien ecrire")

func _resumabilite_json_stricte(v) -> void:
	var e := {
		"id": "e11",
		"position": {"x": 1.0, "y": 0.0, "z": 2.0},
		"proprietes": {"marques_epigenetiques": {}},
	}
	Epigenetique.poser(e, "exposition_gravitique", _catalogue())
	Epigenetique.avancer(e, 1.0, _catalogue())
	var texte := JSON.stringify(e)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	var canal: Dictionary = e.proprietes.marques_epigenetiques.exposition_gravitique
	var canal_relu: Dictionary = relu.proprietes.marques_epigenetiques.exposition_gravitique
	v.v(is_equal_approx(canal_relu.modulateur, canal.modulateur) and is_equal_approx(canal_relu.age_marque, canal.age_marque),
		"modulateur et age_marque doivent survivre identiques a l'aller-retour JSON")
