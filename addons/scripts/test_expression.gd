extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_expression.gd
#
# Verrouille scripts/expression.gd comme mecanisme GENERIQUE de traduction
# genes/marques epigenetiques/senescence en valeurs effectives -- pas un
# code de colon. Domaine hors Orion : "champ_gravitique"/"resonance_*"/
# "exposition_gravitique"/"declin_gravitique", memes noms que les entrees
# deja posees en donnee dormante dans data/genes.json/data/epigenetique.json/
# data/senescence.json (chantier "fondation genetique dormante"), mais
# construits ICI en Dictionary local -- ce test ne lit jamais ces trois
# fichiers sur disque (les catalogues restent hors perimetre de ce
# chantier). Aucun nom de gene/marque/propriete de ce fichier ne touche au
# vocabulaire Orion (colon, arbre, feu, attache...).
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque.

const ExpressionGenetique = preload("res://scripts/expression.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_gene_dominant_rend_le_maximum_des_alleles(v)
	_gene_recessif_rend_le_minimum_des_alleles(v)
	_gene_additif_rend_la_somme_des_alleles(v)
	_gene_incomplet_rend_la_moyenne_des_alleles(v)
	_deux_genes_sur_la_meme_cible_s_additionnent(v)
	_valeur_effective_part_de_la_base_existante(v)
	_marque_epigenetique_module_la_meme_cible(v)
	_senescence_lineaire_module_selon_l_age(v)
	_mode_de_senescence_non_implemente_alarme_et_contribue_zero(v)
	_genes_etat_absent_alarme_et_rend_vide(v)
	_age_sous_age_debut_ne_contribue_pas(v)
	_gene_epigenetique_et_senescence_s_additionnent_sur_la_meme_cible(v)
	_gene_actif_absent_du_catalogue_alarme_et_ignore(v)
	_mode_expression_non_reconnu_alarme_et_contribue_zero(v)
	_marque_epigenetique_absente_du_catalogue_alarme(v)
	_propriete_structurelle_absente_alarme_et_rend_dictionnaire_vide(v)
	_marques_epigenetiques_et_age_absents_sont_facultatifs(v)
	_appliquer_ecrit_les_valeurs_sur_colon_proprietes(v)
	_appliquer_alarme_sur_segment_manquant_et_n_ecrit_rien(v)
	_ecrire_chemin_a_un_seul_segment_ecrit_directement(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: expression.gd traduit genes/marques epigenetiques/senescence en valeurs " +
			"effectives par chemin, generique a tout domaine invente")
		quit(0)

func _colon(id: String, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _gene_dominant_rend_le_maximum_des_alleles(v) -> void:
	var c := _colon("c1", {
		"genes_actifs": ["resonance_dominante"],
		"genes_etat": {"resonance_dominante": {"alleles": [0.3, 0.8]}},
	})
	var catalogue := {
		"resonance_dominante": {
			"cibles": [{"chemin": "champ_gravitique.intensite", "poids": 1.0}],
			"mode_expression": "dominant",
		},
	}
	var resultat := ExpressionGenetique.exprimer(c, catalogue, {}, {})
	v.v(is_equal_approx(resultat["champ_gravitique.intensite"], 0.8),
		"dominant doit rendre le maximum des alleles (0.8), pas la moyenne ni la somme")

func _gene_recessif_rend_le_minimum_des_alleles(v) -> void:
	var c := _colon("c2", {
		"genes_actifs": ["resonance_recessive"],
		"genes_etat": {"resonance_recessive": {"alleles": [0.3, 0.8]}},
	})
	var catalogue := {
		"resonance_recessive": {
			"cibles": [{"chemin": "champ_gravitique.intensite", "poids": 1.0}],
			"mode_expression": "recessif",
		},
	}
	var resultat := ExpressionGenetique.exprimer(c, catalogue, {}, {})
	v.v(is_equal_approx(resultat["champ_gravitique.intensite"], 0.3),
		"recessif doit rendre le minimum des alleles (0.3)")

func _gene_additif_rend_la_somme_des_alleles(v) -> void:
	var c := _colon("c3", {
		"genes_actifs": ["resonance_additive"],
		"genes_etat": {"resonance_additive": {"alleles": [0.3, 0.8]}},
	})
	var catalogue := {
		"resonance_additive": {
			"cibles": [{"chemin": "champ_gravitique.intensite", "poids": 1.0}],
			"mode_expression": "additif",
		},
	}
	var resultat := ExpressionGenetique.exprimer(c, catalogue, {}, {})
	v.v(is_equal_approx(resultat["champ_gravitique.intensite"], 1.1),
		"additif doit rendre la somme des alleles (1.1), au-dela du plus fort allele seul")

func _gene_incomplet_rend_la_moyenne_des_alleles(v) -> void:
	var c := _colon("c4", {
		"genes_actifs": ["resonance_incomplete"],
		"genes_etat": {"resonance_incomplete": {"alleles": [0.3, 0.8]}},
	})
	var catalogue := {
		"resonance_incomplete": {
			"cibles": [{"chemin": "champ_gravitique.intensite", "poids": 1.0}],
			"mode_expression": "incomplet",
		},
	}
	var resultat := ExpressionGenetique.exprimer(c, catalogue, {}, {})
	v.v(is_equal_approx(resultat["champ_gravitique.intensite"], 0.55),
		"incomplet doit rendre la moyenne des alleles (0.55), un melange entre les deux extremes")

func _deux_genes_sur_la_meme_cible_s_additionnent(v) -> void:
	var c := _colon("c5", {
		"genes_actifs": ["resonance_a", "resonance_b"],
		"genes_etat": {
			"resonance_a": {"alleles": [1.0, 1.0]},
			"resonance_b": {"alleles": [2.0, 2.0]},
		},
	})
	var catalogue := {
		"resonance_a": {
			"cibles": [{"chemin": "champ_gravitique.intensite", "poids": 1.0}],
			"mode_expression": "additif",
		},
		"resonance_b": {
			"cibles": [{"chemin": "champ_gravitique.intensite", "poids": 1.0}],
			"mode_expression": "additif",
		},
	}
	var resultat := ExpressionGenetique.exprimer(c, catalogue, {}, {})
	v.v(is_equal_approx(resultat["champ_gravitique.intensite"], 6.0),
		"deux genes ciblant le meme chemin doivent s'additionner (2.0 + 4.0), jamais s'ecraser")

func _valeur_effective_part_de_la_base_existante(v) -> void:
	var c := _colon("c6", {
		"genes_actifs": ["resonance_additive"],
		"genes_etat": {"resonance_additive": {"alleles": [0.3, 0.8]}},
		"champ_gravitique": {"intensite": 5.0},
	})
	var catalogue := {
		"resonance_additive": {
			"cibles": [{"chemin": "champ_gravitique.intensite", "poids": 1.0}],
			"mode_expression": "additif",
		},
	}
	var resultat := ExpressionGenetique.exprimer(c, catalogue, {}, {})
	v.v(is_equal_approx(resultat["champ_gravitique.intensite"], 6.1),
		"la contribution genetique doit s'additionner a la base deja presente (5.0 + 1.1), jamais l'ecraser")

func _marque_epigenetique_module_la_meme_cible(v) -> void:
	var c := _colon("c7", {
		"genes_actifs": [],
		"genes_etat": {},
		"marques_epigenetiques": {"exposition_gravitique": {"modulateur": 0.4, "age_marque": 12.0}},
	})
	var catalogue_epigenetique := {
		"exposition_gravitique": {"cible": "champ_gravitique.intensite"},
	}
	var resultat := ExpressionGenetique.exprimer(c, {}, catalogue_epigenetique, {})
	v.v(is_equal_approx(resultat["champ_gravitique.intensite"], 0.4),
		"une marque epigenetique doit moduler sa cible du modulateur courant deja stocke sur l'entite")

func _senescence_lineaire_module_selon_l_age(v) -> void:
	var c := _colon("c8", {"genes_actifs": [], "genes_etat": {}, "age": 45.0})
	var catalogue_senescence := {
		"declin_gravitique": {
			"cible": "champ_gravitique.intensite",
			"age_debut": 40.0,
			"modulateur_par_annee": -0.02,
			"mode": "lineaire",
		},
	}
	var resultat := ExpressionGenetique.exprimer(c, {}, {}, catalogue_senescence)
	v.v(is_equal_approx(resultat["champ_gravitique.intensite"], -0.1),
		"5 annees au-dela de age_debut a -0.02/an doit rendre -0.1")

# Un mode de senescence declare mais NON IMPLEMENTE alarme et contribue
# 0.0 -- jamais une courbe devinee. Trois modes vivent dans le catalogue
# partage, un seul est ecrit : les deux autres passent par ici.
func _mode_de_senescence_non_implemente_alarme_et_contribue_zero(v) -> void:
	var c := _colon("c20", {"genes_actifs": [], "genes_etat": {}, "age": 45.0})
	var catalogue_senescence := {
		"declin_zorg": {
			"cible": "champ_gravitique.intensite",
			"age_debut": 40.0,
			"modulateur_par_annee": -0.02,
			"mode": "exponentiel",
		},
	}
	var resultat := ExpressionGenetique.exprimer(c, {}, {}, catalogue_senescence)
	v.v(resultat.get("champ_gravitique.intensite", 0.0) == 0.0,
		"un mode de senescence non implemente doit alarmer et contribuer 0.0, jamais une courbe devinee")

# La cle 'genes_etat' a sa PROPRE garde : une entite qui porte 'genes_actifs'
# sans elle sort ici, jamais sur la premiere.
func _genes_etat_absent_alarme_et_rend_vide(v) -> void:
	var c := _colon("c21", {"genes_actifs": ["vivacite"]})
	v.v(ExpressionGenetique.exprimer(c, {}, {}, {}).is_empty(),
		"'genes_etat' absente alors que 'genes_actifs' est la : alarme puis retour vide")

func _age_sous_age_debut_ne_contribue_pas(v) -> void:
	var c := _colon("c9", {"genes_actifs": [], "genes_etat": {}, "age": 10.0})
	var catalogue_senescence := {
		"declin_gravitique": {
			"cible": "champ_gravitique.intensite",
			"age_debut": 40.0,
			"modulateur_par_annee": -0.02,
			"mode": "lineaire",
		},
	}
	var resultat := ExpressionGenetique.exprimer(c, {}, {}, catalogue_senescence)
	v.v(not resultat.has("champ_gravitique.intensite"),
		"un age sous age_debut ne doit produire aucune contribution, jamais une entree a zero")

func _gene_epigenetique_et_senescence_s_additionnent_sur_la_meme_cible(v) -> void:
	var c := _colon("c10", {
		"genes_actifs": ["resonance_additive"],
		"genes_etat": {"resonance_additive": {"alleles": [1.0, 1.0]}},
		"marques_epigenetiques": {"exposition_gravitique": {"modulateur": 0.5, "age_marque": 1.0}},
		"age": 41.0,
	})
	var catalogue_genes := {
		"resonance_additive": {
			"cibles": [{"chemin": "champ_gravitique.intensite", "poids": 1.0}],
			"mode_expression": "additif",
		},
	}
	var catalogue_epigenetique := {"exposition_gravitique": {"cible": "champ_gravitique.intensite"}}
	var catalogue_senescence := {
		"declin_gravitique": {
			"cible": "champ_gravitique.intensite",
			"age_debut": 40.0,
			"modulateur_par_annee": -0.02,
			"mode": "lineaire",
		},
	}
	var resultat := ExpressionGenetique.exprimer(c, catalogue_genes, catalogue_epigenetique, catalogue_senescence)
	# gene : 2.0 (somme) ; epigenetique : 0.5 ; senescence : -0.02 * 1 annee = -0.02 -- total 2.48
	v.v(is_equal_approx(resultat["champ_gravitique.intensite"], 2.48),
		"gene + marque epigenetique + senescence doivent s'additionner sur la meme cible, sans ordre de priorite")

func _gene_actif_absent_du_catalogue_alarme_et_ignore(v) -> void:
	var c := _colon("c11", {
		"genes_actifs": ["inconnu"],
		"genes_etat": {},
	})
	var resultat := ExpressionGenetique.exprimer(c, {}, {}, {})
	v.v(resultat.is_empty(),
		"un gene actif absent du catalogue doit alarmer et ne produire aucune contribution, jamais un crash")

func _mode_expression_non_reconnu_alarme_et_contribue_zero(v) -> void:
	var c := _colon("c12", {
		"genes_actifs": ["resonance_codominante"],
		"genes_etat": {"resonance_codominante": {"alleles": [0.5, 0.5]}},
	})
	var catalogue := {
		"resonance_codominante": {
			"cibles": [{"chemin": "champ_gravitique.intensite", "poids": 1.0}],
			"mode_expression": "codominant",
		},
	}
	var resultat := ExpressionGenetique.exprimer(c, catalogue, {}, {})
	v.v(is_equal_approx(resultat.get("champ_gravitique.intensite", 0.0), 0.0),
		"codominant (retire de cette V1) doit alarmer et contribuer 0.0, jamais deviner une formule")

func _marque_epigenetique_absente_du_catalogue_alarme(v) -> void:
	var c := _colon("c13", {
		"genes_actifs": [],
		"genes_etat": {},
		"marques_epigenetiques": {"inconnue": {"modulateur": 1.0, "age_marque": 1.0}},
	})
	var resultat := ExpressionGenetique.exprimer(c, {}, {}, {})
	v.v(resultat.is_empty(),
		"une marque absente du catalogue epigenetique doit alarmer et ne produire aucune contribution")

func _propriete_structurelle_absente_alarme_et_rend_dictionnaire_vide(v) -> void:
	var c := _colon("c14", {})
	var resultat := ExpressionGenetique.exprimer(c, {}, {}, {})
	v.v(resultat.is_empty(),
		"une entite sans 'genes_actifs'/'genes_etat' doit alarmer (deux fois) et rendre un Dictionary vide")

func _marques_epigenetiques_et_age_absents_sont_facultatifs(v) -> void:
	var c := _colon("c15", {
		"genes_actifs": ["resonance_additive"],
		"genes_etat": {"resonance_additive": {"alleles": [1.0, 1.0]}},
	})
	var catalogue := {
		"resonance_additive": {
			"cibles": [{"chemin": "champ_gravitique.intensite", "poids": 1.0}],
			"mode_expression": "additif",
		},
	}
	var resultat := ExpressionGenetique.exprimer(c, catalogue, {}, {})
	v.v(is_equal_approx(resultat["champ_gravitique.intensite"], 2.0),
		"l'absence de 'marques_epigenetiques'/'age' ne doit jamais alarmer -- deux couches facultatives ignorees proprement")

func _appliquer_ecrit_les_valeurs_sur_colon_proprietes(v) -> void:
	var c := _colon("c16", {
		"genes_actifs": ["resonance_additive"],
		"genes_etat": {"resonance_additive": {"alleles": [1.0, 1.0]}},
		"champ_gravitique": {"intensite": 3.0},
	})
	var catalogue := {
		"resonance_additive": {
			"cibles": [{"chemin": "champ_gravitique.intensite", "poids": 1.0}],
			"mode_expression": "additif",
		},
	}
	var valeurs := ExpressionGenetique.exprimer(c, catalogue, {}, {})
	ExpressionGenetique.appliquer(c, valeurs)
	v.v(is_equal_approx(c.proprietes.champ_gravitique.intensite, 5.0),
		"appliquer doit ecrire la valeur effective (3.0 + 2.0) sur colon.proprietes, par chemin")

func _appliquer_alarme_sur_segment_manquant_et_n_ecrit_rien(v) -> void:
	var c := _colon("c17", {"genes_actifs": [], "genes_etat": {}})
	ExpressionGenetique.appliquer(c, {"champ_gravitique.intensite": 9.0})
	v.v(not c.proprietes.has("champ_gravitique"),
		"un segment intermediaire absent doit alarmer et n'ecrire aucune structure, jamais une creation silencieuse")
	v.v(not c.proprietes.has("champ_gravitique.intensite"),
		"le chemin ne doit jamais devenir une cle litterale a plat non plus")

func _ecrire_chemin_a_un_seul_segment_ecrit_directement(v) -> void:
	var c := _colon("c18", {"genes_actifs": [], "genes_etat": {}})
	ExpressionGenetique.appliquer(c, {"masse": 42.0})
	v.v(c.proprietes.masse == 42.0,
		"un chemin a un seul segment (sans point) doit s'ecrire directement, aucun segment intermediaire a verifier")

func _resumabilite_json_stricte(v) -> void:
	var c := _colon("c19", {
		"genes_actifs": ["resonance_additive"],
		"genes_etat": {"resonance_additive": {"alleles": [1.0, 1.0]}},
		"marques_epigenetiques": {"exposition_gravitique": {"modulateur": 0.4, "age_marque": 12.0}},
		"age": 45.0,
		"champ_gravitique": {"intensite": 0.0},
	})
	var catalogue_genes := {
		"resonance_additive": {
			"cibles": [{"chemin": "champ_gravitique.intensite", "poids": 1.0}],
			"mode_expression": "additif",
		},
	}
	var catalogue_epigenetique := {"exposition_gravitique": {"cible": "champ_gravitique.intensite"}}
	var catalogue_senescence := {
		"declin_gravitique": {
			"cible": "champ_gravitique.intensite",
			"age_debut": 40.0,
			"modulateur_par_annee": -0.02,
			"mode": "lineaire",
		},
	}
	var valeurs := ExpressionGenetique.exprimer(c, catalogue_genes, catalogue_epigenetique, catalogue_senescence)
	ExpressionGenetique.appliquer(c, valeurs)
	var texte := JSON.stringify(c)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	v.v(is_equal_approx(relu.proprietes.champ_gravitique.intensite, c.proprietes.champ_gravitique.intensite),
		"la valeur ecrite par appliquer() doit survivre identique a l'aller-retour JSON")
