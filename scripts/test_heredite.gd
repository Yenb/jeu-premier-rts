extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_heredite.gd
#
# Verrouille scripts/heredite.gd comme mecanisme GENERIQUE de derniere
# phase du cycle de reproduction : produit un kit genetique d'enfant
# (genes_etat/marques_epigenetiques) a partir d'une porteuse et de son
# partenaire deja copie dans gestation -- pas un code de colon. Domaine
# invente (cristal_gravitique_*, meme famille que test_accouplement.gd/
# test_gestation.gd) : ce test prouve que fabriquer_genes_enfant()
# traverse le meme code quel que soit le domaine.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque
# (les deux catalogues sont des Dictionary construits ici, jamais
# data/heredite.json ni data/epigenetique.json).

const Heredite = preload("res://scripts/heredite.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_sexuee_melange_un_allele_de_chaque_parent(v)
	_asexuee_copie_les_alleles_du_parent_sans_mutation(v)
	_asexuee_copie_est_independante_de_la_porteuse(v)
	_parthenogenese_rearrange_les_alleles_du_parent_unique(v)
	_mode_inconnu_alarme_et_rend_vide(v)
	_mutation_ajoute_un_bruit_gaussien_a_l_ecart_type_du_catalogue(v)
	_taux_asexuee_distinct_de_taux_base(v)
	_gene_sans_alleles_est_ignore_silencieusement(v)
	_marque_plus_forte_des_deux_parents_transmise_selon_taux(v)
	_marque_sous_plancher_non_transmise(v)
	_marque_absente_du_catalogue_epigenetique_alarme_et_ignoree(v)
	_rng_seede_produit_un_resultat_deterministe(v)
	_proprietes_structurelles_absentes_alarment(v)
	_catalogue_heredite_incomplet_alarme(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: heredite.gd produit un kit genetique d'enfant selon le mode de reproduction, " +
			"generique a tout domaine invente")
		quit(0)

func _cristal(id: String, mode: String, alleles: Array, marques: Dictionary, partenaire_alleles: Array, partenaire_marques: Dictionary) -> Dictionary:
	return {
		"id": id,
		"position": Vector3.ZERO,
		"proprietes": {
			"mode_reproduction": mode,
			"genes_actifs": ["resonance_gravitique"],
			"genes_etat": {"resonance_gravitique": {"alleles": alleles}},
			"marques_epigenetiques": marques,
			"gestation": {
				"partenaire_id": "cristal_partenaire",
				"partenaire_genes_etat": {"resonance_gravitique": {"alleles": partenaire_alleles}},
				"partenaire_marques_epigenetiques": partenaire_marques,
				"accouplement_tick": 0,
			},
		},
	}

func _catalogue_heredite(taux_base: float = 0.0, taux_asexuee: float = 0.0, ecart: float = 0.05) -> Dictionary:
	return {"defaut": {"taux_mutation_base": taux_base, "taux_mutation_asexuee": taux_asexuee, "ecart_type_mutation": ecart}}

func _catalogue_epigenetique(taux_transmission: float = 0.5, plancher: float = 0.01) -> Dictionary:
	return {"exposition_gravitique": {"cible": "champ_gravitique.intensite", "taux_transmission_enfant": taux_transmission, "plancher_suppression": plancher}}

func _rng(seed_valeur: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_valeur
	return rng

func _sexuee_melange_un_allele_de_chaque_parent(v) -> void:
	var e := _cristal("cristal_1", "sexuee", [0.1, 0.9], {}, [0.2, 0.8], {})
	var kit := Heredite.fabriquer_genes_enfant(e, _catalogue_heredite(), _catalogue_epigenetique(), _rng(42))
	var alleles: Array = kit.genes_etat.resonance_gravitique.alleles
	v.v(alleles.size() == 2, "sexuee doit toujours rendre exactement deux alleles, quelle que soit la taille des tableaux parents")
	v.v(alleles[0] == 0.1 or alleles[0] == 0.9, "le premier allele doit venir du tableau de la porteuse")
	v.v(alleles[1] == 0.2 or alleles[1] == 0.8, "le second allele doit venir du tableau du partenaire")

func _asexuee_copie_les_alleles_du_parent_sans_mutation(v) -> void:
	var e := _cristal("cristal_2", "asexuee", [0.3, 0.6, 0.9], {}, [], {})
	var kit := Heredite.fabriquer_genes_enfant(e, _catalogue_heredite(0.0, 0.0), _catalogue_epigenetique(), _rng(1))
	v.v(kit.genes_etat.resonance_gravitique.alleles == [0.3, 0.6, 0.9],
		"asexuee sans mutation doit copier exactement les alleles de la porteuse, meme taille (3), meme ordre")

func _asexuee_copie_est_independante_de_la_porteuse(v) -> void:
	var e := _cristal("cristal_3", "asexuee", [0.4, 0.5], {}, [], {})
	var kit := Heredite.fabriquer_genes_enfant(e, _catalogue_heredite(0.0, 0.0), _catalogue_epigenetique(), _rng(2))
	e.proprietes.genes_etat.resonance_gravitique.alleles[0] = 999.0
	v.v(kit.genes_etat.resonance_gravitique.alleles[0] == 0.4,
		"la copie rendue ne doit jamais suivre l'etat vivant de la porteuse mutee apres coup")

func _parthenogenese_rearrange_les_alleles_du_parent_unique(v) -> void:
	var e := _cristal("cristal_4", "parthenogenese", [0.1, 0.9], {}, [], {})
	var kit := Heredite.fabriquer_genes_enfant(e, _catalogue_heredite(0.0), _catalogue_epigenetique(), _rng(7))
	var alleles: Array = kit.genes_etat.resonance_gravitique.alleles
	v.v(alleles.size() == 2, "parthenogenese doit rendre le meme nombre d'alleles que le parent unique")
	for a in alleles:
		v.v(a == 0.1 or a == 0.9, "chaque allele rearrange doit venir du tableau du parent unique, jamais une valeur etrangere")

func _mode_inconnu_alarme_et_rend_vide(v) -> void:
	var e := _cristal("cristal_5", "clonage_extraterrestre", [0.1, 0.9], {}, [0.2, 0.8], {})
	var kit := Heredite.fabriquer_genes_enfant(e, _catalogue_heredite(), _catalogue_epigenetique(), _rng(3))
	v.v(kit.genes_etat.is_empty() and kit.marques_epigenetiques.is_empty(),
		"un mode_reproduction non reconnu doit alarmer et rendre un Dictionary vide, jamais deviner un mode")

func _mutation_ajoute_un_bruit_gaussien_a_l_ecart_type_du_catalogue(v) -> void:
	var e := _cristal("cristal_6", "sexuee", [0.5], {}, [0.5], {})
	var ecart := 0.2
	var kit := Heredite.fabriquer_genes_enfant(e, _catalogue_heredite(1.0, 0.0, ecart), _catalogue_epigenetique(), _rng(99))

	var reference := _rng(99)
	reference.randi_range(0, 0)
	reference.randi_range(0, 0)
	var attendu: Array = []
	for _i in range(2):
		reference.randf()
		attendu.append(0.5 + reference.randfn(0.0, ecart))

	var alleles: Array = kit.genes_etat.resonance_gravitique.alleles
	v.v(is_equal_approx(alleles[0], attendu[0]) and is_equal_approx(alleles[1], attendu[1]),
		"a taux_mutation 1.0, chaque allele doit recevoir exactement rng.randfn(0.0, ecart_type_mutation) du catalogue, meme sequence de tirages qu'une reference rejouee au meme seed")

func _taux_asexuee_distinct_de_taux_base(v) -> void:
	var e := _cristal("cristal_7", "asexuee", [0.5, 0.5], {}, [], {})
	var kit := Heredite.fabriquer_genes_enfant(e, _catalogue_heredite(1.0, 0.0), _catalogue_epigenetique(), _rng(5))
	v.v(kit.genes_etat.resonance_gravitique.alleles == [0.5, 0.5],
		"asexuee doit lire taux_mutation_asexuee (ici 0.0), jamais taux_mutation_base (ici 1.0) -- aucune mutation attendue malgre un taux_mutation_base a 1.0")

func _gene_sans_alleles_est_ignore_silencieusement(v) -> void:
	var e := _cristal("cristal_8", "sexuee", [], {}, [0.2, 0.8], {})
	var kit := Heredite.fabriquer_genes_enfant(e, _catalogue_heredite(), _catalogue_epigenetique(), _rng(11))
	v.v(kit.genes_etat.is_empty(),
		"un gene actif sans allele chez la porteuse doit etre ignore silencieusement, jamais une alarme ni une valeur inventee")

func _marque_plus_forte_des_deux_parents_transmise_selon_taux(v) -> void:
	var e := _cristal("cristal_9", "sexuee", [0.1, 0.9], {"exposition_gravitique": {"modulateur": 0.2, "age_marque": 10.0}}, [0.2, 0.8], {"exposition_gravitique": {"modulateur": 0.5, "age_marque": 3.0}})
	var kit := Heredite.fabriquer_genes_enfant(e, _catalogue_heredite(), _catalogue_epigenetique(0.5, 0.01), _rng(13))
	v.v(kit.marques_epigenetiques.has("exposition_gravitique"), "la marque doit etre transmise (0.5 * 0.5 = 0.25, au-dessus du plancher 0.01)")
	v.v(is_equal_approx(kit.marques_epigenetiques.exposition_gravitique.modulateur, 0.25),
		"le modulateur transmis doit etre max(0.2, 0.5) * taux_transmission_enfant, jamais une moyenne ni une somme")
	v.v(kit.marques_epigenetiques.exposition_gravitique.age_marque == 0.0,
		"une marque transmise doit demarrer avec age_marque a 0.0 sur l'enfant, un horodatage frais")

func _marque_sous_plancher_non_transmise(v) -> void:
	var e := _cristal("cristal_10", "sexuee", [0.1, 0.9], {"exposition_gravitique": {"modulateur": 0.1, "age_marque": 1.0}}, [0.2, 0.8], {})
	var kit := Heredite.fabriquer_genes_enfant(e, _catalogue_heredite(), _catalogue_epigenetique(0.05, 0.01), _rng(17))
	v.v(not kit.marques_epigenetiques.has("exposition_gravitique"),
		"un modulateur transmis (0.1 * 0.05 = 0.005) sous plancher_suppression (0.01) ne doit jamais etre transmis")

func _marque_absente_du_catalogue_epigenetique_alarme_et_ignoree(v) -> void:
	var e := _cristal("cristal_11", "sexuee", [0.1, 0.9], {"marque_inconnue": {"modulateur": 0.5, "age_marque": 1.0}}, [0.2, 0.8], {})
	var kit := Heredite.fabriquer_genes_enfant(e, _catalogue_heredite(), _catalogue_epigenetique(), _rng(19))
	v.v(not kit.marques_epigenetiques.has("marque_inconnue"),
		"une marque absente du catalogue epigenetique doit alarmer et ne jamais etre transmise")

func _rng_seede_produit_un_resultat_deterministe(v) -> void:
	var e1 := _cristal("cristal_12a", "sexuee", [0.1, 0.9], {"exposition_gravitique": {"modulateur": 0.3, "age_marque": 0.0}}, [0.2, 0.8], {})
	var e2 := _cristal("cristal_12b", "sexuee", [0.1, 0.9], {"exposition_gravitique": {"modulateur": 0.3, "age_marque": 0.0}}, [0.2, 0.8], {})
	var kit1 := Heredite.fabriquer_genes_enfant(e1, _catalogue_heredite(0.3, 0.0, 0.1), _catalogue_epigenetique(), _rng(2024))
	var kit2 := Heredite.fabriquer_genes_enfant(e2, _catalogue_heredite(0.3, 0.0, 0.1), _catalogue_epigenetique(), _rng(2024))
	v.v(kit1.genes_etat == kit2.genes_etat, "deux appels au meme seed doivent produire exactement les memes genes_etat")
	v.v(kit1.marques_epigenetiques == kit2.marques_epigenetiques, "deux appels au meme seed doivent produire exactement les memes marques_epigenetiques")

func _proprietes_structurelles_absentes_alarment(v) -> void:
	var sans_gestation := {"id": "c13", "position": Vector3.ZERO, "proprietes": {"mode_reproduction": "sexuee", "genes_actifs": [], "genes_etat": {}, "marques_epigenetiques": {}}}
	var kit_a := Heredite.fabriquer_genes_enfant(sans_gestation, _catalogue_heredite(), _catalogue_epigenetique(), _rng(1))
	v.v(kit_a.genes_etat.is_empty() and kit_a.marques_epigenetiques.is_empty(), "sans 'gestation', alarme et Dictionary vide")

	var sans_genes_actifs := {"id": "c14", "position": Vector3.ZERO, "proprietes": {"mode_reproduction": "sexuee", "genes_etat": {}, "marques_epigenetiques": {}, "gestation": {"partenaire_genes_etat": {}, "partenaire_marques_epigenetiques": {}}}}
	var kit_b := Heredite.fabriquer_genes_enfant(sans_genes_actifs, _catalogue_heredite(), _catalogue_epigenetique(), _rng(1))
	v.v(kit_b.genes_etat.is_empty() and kit_b.marques_epigenetiques.is_empty(), "sans 'genes_actifs', alarme et Dictionary vide")

	var sans_genes_etat := {"id": "c15", "position": Vector3.ZERO, "proprietes": {"mode_reproduction": "sexuee", "genes_actifs": [], "marques_epigenetiques": {}, "gestation": {"partenaire_genes_etat": {}, "partenaire_marques_epigenetiques": {}}}}
	var kit_c := Heredite.fabriquer_genes_enfant(sans_genes_etat, _catalogue_heredite(), _catalogue_epigenetique(), _rng(1))
	v.v(kit_c.genes_etat.is_empty() and kit_c.marques_epigenetiques.is_empty(), "sans 'genes_etat', alarme et Dictionary vide")

	var sans_marques := {"id": "c16", "position": Vector3.ZERO, "proprietes": {"mode_reproduction": "sexuee", "genes_actifs": [], "genes_etat": {}, "gestation": {"partenaire_genes_etat": {}, "partenaire_marques_epigenetiques": {}}}}
	var kit_d := Heredite.fabriquer_genes_enfant(sans_marques, _catalogue_heredite(), _catalogue_epigenetique(), _rng(1))
	v.v(kit_d.genes_etat.is_empty() and kit_d.marques_epigenetiques.is_empty(), "sans 'marques_epigenetiques', alarme et Dictionary vide")

func _catalogue_heredite_incomplet_alarme(v) -> void:
	var e := _cristal("cristal_17", "sexuee", [0.1, 0.9], {}, [0.2, 0.8], {})
	var kit_sans_defaut := Heredite.fabriquer_genes_enfant(e, {}, _catalogue_epigenetique(), _rng(1))
	v.v(kit_sans_defaut.genes_etat.is_empty(), "un catalogue heredite sans entree 'defaut' doit alarmer et rendre un Dictionary vide")

	var catalogue_sans_ecart := {"defaut": {"taux_mutation_base": 0.0, "taux_mutation_asexuee": 0.0}}
	var kit_sans_ecart := Heredite.fabriquer_genes_enfant(e, catalogue_sans_ecart, _catalogue_epigenetique(), _rng(1))
	v.v(kit_sans_ecart.genes_etat.is_empty(), "un catalogue 'defaut' sans 'ecart_type_mutation' doit alarmer et rendre un Dictionary vide")

	var catalogue_sans_taux := {"defaut": {"ecart_type_mutation": 0.05}}
	var kit_sans_taux := Heredite.fabriquer_genes_enfant(e, catalogue_sans_taux, _catalogue_epigenetique(), _rng(1))
	v.v(kit_sans_taux.genes_etat.is_empty(), "un catalogue 'defaut' sans le taux du mode courant doit alarmer et rendre un Dictionary vide")

func _resumabilite_json_stricte(v) -> void:
	var e := _cristal("cristal_18", "sexuee", [0.1, 0.9], {"exposition_gravitique": {"modulateur": 0.4, "age_marque": 2.0}}, [0.2, 0.8], {})
	var kit := Heredite.fabriquer_genes_enfant(e, _catalogue_heredite(0.0, 0.0), _catalogue_epigenetique(0.5, 0.01), _rng(21))
	var texte := JSON.stringify(kit)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	v.v(relu.genes_etat.resonance_gravitique.alleles == kit.genes_etat.resonance_gravitique.alleles,
		"genes_etat doit survivre identique a l'aller-retour JSON")
	v.v(is_equal_approx(relu.marques_epigenetiques.exposition_gravitique.modulateur, kit.marques_epigenetiques.exposition_gravitique.modulateur),
		"marques_epigenetiques doit survivre identique a l'aller-retour JSON")
