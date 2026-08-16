extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_reproduction.gd
#
# CHEMIN REEL (meme regime que test_banc_genetique.gd, PAS hors domaine --
# ce banc fabrique de VRAIS colons Orion) : data/types.json, data/canaux.json,
# data/reproduction.json, data/heredite.json, data/banc_reproduction.json
# tous lus sur disque. Verrouille que stade.gd -> accouplement.gd ->
# gestation.gd -> heredite.gd -> Objet.fabriquer tournent ENSEMBLE via
# banc_reproduction.gd:avancer_cycle/naissance_prete/fabriquer_enfant,
# PREMIER banc a fermer ce cycle de bout en bout.
#
# QUATRE PHASES : (1) deux colons immatures, aucune perception mutuelle ne
# doit jamais poser d'accumulateur ni de gestation ; (2) une fois adultes,
# l'exposition mutuelle accumule jusqu'au seuil REEL et la gestation
# n'atterrit que sur le porteur declare en donnee ; (3) elle y avance, et
# le non_porteur n'en porte AUCUNE -- verrou de "lequel des deux geste",
# tranche par role_gestation et non par un appel selectif de ce banc ;
# (4) au seuil de gestation, l'enfant nait avec des allees herites
# verifiables (parents homozygotes [1,1]/[-1,-1] : la somme avant mutation
# est TOUJOURS exactement 0.0, verifie par rejouer la meme sequence RNG
# qu'un seed identique).

const BancReproduction = preload("res://scripts/banc_reproduction.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA_TICK := 0.1

func _init() -> void:
	var v := Verif.new()
	_phase1_immatures_ne_produisent_rien(v)
	_phase2_matures_et_exposes_accouplent_au_seuil_reel(v)
	_phase3_seul_le_porteur_voit_sa_gestation_avancer(v)
	_phase4_naissance_avec_alleles_herites_verifiables(v)
	_naissance_prete_faux_sans_gestation(v)
	_resumabilite_json_stricte(v)
	_couleur_colon_lit_le_nom_pose_jamais_le_defaut(v)
	_verifier_changement_stade_n_imprime_que_sur_changement_reel(v)
	_verifier_accouplement_annonce_une_seule_fois(v)
	_verifier_progression_gestation_respecte_l_intervalle(v)
	_imprimer_ages_ne_plante_pas_sur_plusieurs_colons(v)
	_accoucher_produit_un_enfant_et_efface_la_gestation_du_porteur(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_reproduction.gd cable stade.gd -> accouplement.gd -> gestation.gd -> " +
			"heredite.gd -> Objet.fabriquer ensemble, de bout en bout, sur un chemin reel")
		quit(0)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

# Reproduit EXACTEMENT le chargement de banc_reproduction.gd:_ready -- lu
# sur disque, jamais une fixture locale.
func _catalogues() -> Dictionary:
	var donnees := _charger_json("res://data/banc_reproduction.json")
	var catalogue_types := {}
	var types_partages := _charger_json("res://data/types.json")
	catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	catalogue_types["percevant"] = types_partages.get("percevant", {})
	catalogue_types["agent"] = types_partages.get("agent", {})
	catalogue_types["colon"] = types_partages.get("colon", {})
	return {
		"donnees": donnees,
		"types": catalogue_types,
		"canaux": _charger_json("res://data/canaux.json"),
		"reproduction": _charger_json("res://data/reproduction.json"),
		"heredite": _charger_json("res://data/heredite.json"),
		"genes": donnees.get("catalogue_genes", {}),
	}

func _fabriquer_deux(cat: Dictionary) -> Dictionary:
	var declarations: Dictionary = cat.donnees.get("colons", {})
	return {
		"parent_a": BancReproduction._fabriquer_colon_reproduction("parent_a", declarations.parent_a, cat.types, cat.genes),
		"parent_b": BancReproduction._fabriquer_colon_reproduction("parent_b", declarations.parent_b, cat.types, cat.genes),
	}

func _monde_avec(colons: Dictionary) -> Monde:
	var monde := Monde.new()
	for nom in colons:
		monde.ajouter(colons[nom], "colon", colons[nom].position)
	return monde

func _phase1_immatures_ne_produisent_rien(v) -> void:
	var cat := _catalogues()
	var colons := _fabriquer_deux(cat)
	var monde := _monde_avec(colons)
	var a: Dictionary = colons.parent_a
	var b: Dictionary = colons.parent_b
	# 50 ticks de 0.1s a annees_par_seconde 2.0 -- age atteint 10.0 annees
	# (stade "enfant", seuil "adulte" 18.0 jamais franchi).
	for i in range(50):
		BancReproduction.avancer_cycle([a, b], monde, cat.canaux, cat.reproduction, DELTA_TICK, i, cat.donnees.annees_par_seconde)
	v.v(a.proprietes.stade != "adulte" and b.proprietes.stade != "adulte",
		"a 10 annees, les deux colons ne doivent pas encore etre adultes")
	v.v(not a.proprietes.has("gestation") and not b.proprietes.has("gestation"),
		"deux colons immatures ne doivent jamais entrer en gestation, malgre une perception mutuelle continue")
	v.v(not a.proprietes.has("accouplement_accumulateur") and not b.proprietes.has("accouplement_accumulateur"),
		"accouplement.gd doit sauter la phase avant meme de toucher l'accumulateur (garde stades_fertiles)")

# Fait vieillir les deux colons jusqu'a l'age donne EN UN SEUL SAUT
# (senescence.gd/stade.gd n'exigent aucune progressivite, voir
# test_stade.gd:_avance_au_stade_suivant_quand_age_depasse_son_seuil) --
# garde les phases 2/3/4 rapides sans reimplementer le cycle.
func _vieillir_jusqu_a(colons: Array, age_vise: float, annees_par_seconde: float) -> void:
	var Senescence = load("res://scripts/senescence.gd")
	var Stade = load("res://scripts/stade.gd")
	for colon in colons:
		var delta_annees: float = age_vise - colon.proprietes.age
		if delta_annees > 0.0:
			Senescence.avancer(colon, delta_annees / annees_par_seconde, annees_par_seconde)
			Stade.avancer(colon)

func _phase2_matures_et_exposes_accouplent_au_seuil_reel(v) -> void:
	var cat := _catalogues()
	var colons := _fabriquer_deux(cat)
	var monde := _monde_avec(colons)
	var a: Dictionary = colons.parent_a
	var b: Dictionary = colons.parent_b
	_vieillir_jusqu_a([a, b], 18.0, cat.donnees.annees_par_seconde)
	v.v(a.proprietes.stade == "adulte" and b.proprietes.stade == "adulte",
		"a 18 annees exactement, les deux colons doivent etre adultes")

	# seuil_accouplement 1.0, taux_montee 0.05 (data/reproduction.json:colon)
	# : 1.0 / 0.05 = 20.0s d'exposition. 199 ticks de 0.1s = 19.9s, encore
	# sous le seuil.
	for i in range(199):
		BancReproduction.avancer_cycle([a, b], monde, cat.canaux, cat.reproduction, DELTA_TICK, i, cat.donnees.annees_par_seconde)
	v.v(not a.proprietes.has("gestation"), "a 19.9s d'exposition, sous le seuil de 20.0s, gestation ne doit pas encore etre posee")

	# Le 200e tick franchit exactement le seuil (20.0s).
	BancReproduction.avancer_cycle([a, b], monde, cat.canaux, cat.reproduction, DELTA_TICK, 199, cat.donnees.annees_par_seconde)
	# La fecondation est symetrique, la gestation ne l'est plus : seul le
	# colon declare "porteur" en donnee gestate. Un seul enfant par
	# accouplement, sans qu'aucune ligne de ce banc ne designe personne.
	v.v(a.proprietes.has("gestation"),
		"au franchissement exact du seuil, le porteur declare doit entrer en gestation")
	v.v(not b.proprietes.has("gestation"),
		"le non_porteur ne gestate JAMAIS -- c'est la donnee qui l'exclut, plus une convention de banc")
	v.v(a.proprietes.gestation.partenaire_id == "parent_b",
		"la gestation du porteur doit nommer le partenaire qui l'a fecondee")

func _phase3_seul_le_porteur_voit_sa_gestation_avancer(v) -> void:
	var cat := _catalogues()
	var colons := _fabriquer_deux(cat)
	var monde := _monde_avec(colons)
	var a: Dictionary = colons.parent_a
	var b: Dictionary = colons.parent_b
	_vieillir_jusqu_a([a, b], 18.0, cat.donnees.annees_par_seconde)
	for i in range(200):
		BancReproduction.avancer_cycle([a, b], monde, cat.canaux, cat.reproduction, DELTA_TICK, i, cat.donnees.annees_par_seconde)
	v.v(a.proprietes.has("gestation"), "le porteur declare doit avoir une gestation posee avant cette phase")

	# 50 ticks supplementaires. Un seul accouplement ne peut plus produire
	# deux enfants : ce n'est plus un appel selectif du banc qui l'empeche,
	# c'est que le non_porteur n'a JAMAIS recu de gestation.
	for i in range(200, 250):
		BancReproduction.avancer_cycle([a, b], monde, cat.canaux, cat.reproduction, DELTA_TICK, i, cat.donnees.annees_par_seconde)
	v.v(a.proprietes.gestation.has("duree_gestation_ecoulee") and a.proprietes.gestation.duree_gestation_ecoulee > 0.0,
		"la gestation du porteur doit avoir avance")
	v.v(not b.proprietes.has("gestation"),
		"le non_porteur ne porte AUCUNE gestation -- la donnee l'exclut, plus une convention de ce banc")

func _phase4_naissance_avec_alleles_herites_verifiables(v) -> void:
	var cat := _catalogues()
	var colons := _fabriquer_deux(cat)
	var monde := _monde_avec(colons)
	var a: Dictionary = colons.parent_a
	var b: Dictionary = colons.parent_b
	_vieillir_jusqu_a([a, b], 18.0, cat.donnees.annees_par_seconde)
	var i := 0
	# Accumule jusqu'a l'accouplement (seuil 20.0s) PUIS la gestation
	# (duree_gestation 30.0s, data/reproduction.json:colon) -- large marge
	# de ticks, s'arrete des que naissance_prete est atteint.
	for _n in range(600):
		BancReproduction.avancer_cycle([a, b], monde, cat.canaux, cat.reproduction, DELTA_TICK, i, cat.donnees.annees_par_seconde)
		i += 1
		if BancReproduction.naissance_prete(a):
			break
	v.v(BancReproduction.naissance_prete(a), "apres accouplement + duree_gestation reelle, naissance_prete doit finir par etre atteint")

	var rng := RandomNumberGenerator.new()
	rng.seed = int(cat.donnees.seed)
	var enfant := BancReproduction.fabriquer_enfant("enfant_test", a, a.position, cat.types, cat.genes, cat.heredite, rng)

	v.v(enfant.proprietes.genes_actifs == ["vivacite"], "l'enfant doit porter le meme genes_actifs que le porteur")
	var alleles: Array = enfant.proprietes.genes_etat.vivacite.alleles
	v.v(alleles.size() == 2, "sexuee doit toujours rendre exactement deux alleles")

	# parent_a est homozygote [1,1], parent_b homozygote [-1,-1] : le tirage
	# sexuee rend TOUJOURS [1,-1] avant mutation (un seul allele possible
	# chez chacun), somme 0.0 -- l'enfant nait a la vitesse de BASE du type
	# colon, EXACTEMENT entre ses deux parents, sauf mutation (rejouee ici
	# depuis le meme seed, meme technique que test_heredite.gd).
	var reference := RandomNumberGenerator.new()
	reference.seed = int(cat.donnees.seed)
	reference.randi_range(0, 0)
	reference.randi_range(0, 0)
	var regle: Dictionary = cat.heredite.defaut
	var attendus: Array = [1.0, -1.0]
	for idx in range(2):
		if reference.randf() < regle.taux_mutation_base:
			attendus[idx] += reference.randfn(0.0, regle.ecart_type_mutation)
	v.v(is_equal_approx(alleles[0], attendus[0]) and is_equal_approx(alleles[1], attendus[1]),
		"les deux alleles de l'enfant doivent suivre exactement la sequence RNG rejouee au meme seed (1.0 de parent_a, -1.0 de parent_b, mutation eventuelle comprise)")

	var vitesse_attendue: float = cat.types.colon.vitesse + (attendus[0] + attendus[1]) * cat.genes.vivacite.cibles[0].poids
	v.v(is_equal_approx(enfant.proprietes.vitesse, vitesse_attendue),
		"la vitesse exprimee de l'enfant doit suivre exactement base + somme(alleles_herites) * poids")
	v.v(is_equal_approx(enfant.proprietes.vitesse, cat.types.colon.vitesse) or not is_equal_approx(regle.taux_mutation_base, 0.0),
		"sans mutation, l'enfant nait EXACTEMENT a la vitesse de base du type colon -- exactement entre ses deux parents")

func _naissance_prete_faux_sans_gestation(v) -> void:
	var colon := {"id": "x", "position": Vector3.ZERO, "proprietes": {}}
	v.v(not BancReproduction.naissance_prete(colon), "un colon sans gestation ne doit jamais rendre naissance_prete")

func _resumabilite_json_stricte(v) -> void:
	var cat := _catalogues()
	var colons := _fabriquer_deux(cat)
	var monde := _monde_avec(colons)
	var a: Dictionary = colons.parent_a
	var b: Dictionary = colons.parent_b
	_vieillir_jusqu_a([a, b], 18.0, cat.donnees.annees_par_seconde)
	for i in range(200):
		BancReproduction.avancer_cycle([a, b], monde, cat.canaux, cat.reproduction, DELTA_TICK, i, cat.donnees.annees_par_seconde)
	var texte := JSON.stringify(a)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	v.v(relu.proprietes.gestation.partenaire_id == "parent_b",
		"gestation doit survivre identique a l'aller-retour JSON")
	v.v(is_equal_approx(relu.proprietes.age, a.proprietes.age),
		"age doit survivre identique a l'aller-retour JSON")

# Audit couverture 2026-08-06 : _couleur_colon/_verifier_changement_stade/
# _verifier_accouplement/_verifier_progression_gestation/_accoucher/
# _imprimer_ages/_imprimer_naissance sont des fonctions INSTANCE, aucune
# appelee par un test avant cette session. Meme patron que les autres
# bancs : BancReproduction.new() nu, jamais ajoute a l'arbre.
#
# _imprimer_naissance n'a PAS de test dedie : fonction 100% print (aucun
# etat mute, aucune valeur rendue), deja exercee de bout en bout par
# _accoucher_produit_un_enfant_et_efface_la_gestation_du_porteur ci-dessous
# (memes lignes executees contre des donnees reelles) -- rien de plus a
# observer au-dela de "ne plante pas", deja couvert par cet appel reel.

func _couleur_colon_lit_le_nom_pose_jamais_le_defaut(v) -> void:
	var b := BancReproduction.new()
	b._couleurs_colons = {"parent_a": [0.9, 0.1, 0.1], "parent_b": [0.1, 0.1, 0.9]}
	v.v(b._couleur_colon("parent_a") == Color(0.9, 0.1, 0.1), "doit rendre la couleur posee pour 'parent_a'")
	v.v(b._couleur_colon("parent_b") == Color(0.1, 0.1, 0.9), "doit distinguer deux colons poses")
	v.v(b._couleur_colon("inconnu") == Color(1.0, 1.0, 1.0), "un nom absent doit rendre le blanc par defaut")

func _verifier_changement_stade_n_imprime_que_sur_changement_reel(v) -> void:
	var b := BancReproduction.new()
	b._temps_ecoule = 3.0
	var colon := {"id": "c1", "proprietes": {"stade": "nouveau_ne", "age": 0.5}}
	b._stades_precedents[colon.id] = "nouveau_ne"
	b._verifier_changement_stade(colon)
	v.v(b._stades_precedents[colon.id] == "nouveau_ne", "meme stade : aucun changement enregistre")

	colon.proprietes["stade"] = "enfant"
	b._verifier_changement_stade(colon)
	v.v(b._stades_precedents[colon.id] == "enfant", "un stade different doit etre enregistre comme le nouveau precedent")

func _verifier_accouplement_annonce_une_seule_fois(v) -> void:
	var b := BancReproduction.new()
	b._temps_ecoule = 5.0
	b._porteur = {"id": "parent_a", "proprietes": {}}
	b._verifier_accouplement()
	v.v(not b._accouplement_annonce, "sans gestation posee, l'accouplement ne doit jamais s'annoncer")

	b._porteur.proprietes["gestation"] = {"partenaire_id": "parent_b"}
	b._verifier_accouplement()
	v.v(b._accouplement_annonce, "gestation posee : l'accouplement doit s'annoncer")

func _verifier_progression_gestation_respecte_l_intervalle(v) -> void:
	var b := BancReproduction.new()
	b._catalogue_reproduction = {"colon": {"duree_gestation": 30.0}}
	b._intervalle_print_gestation = 5.0
	b._porteur = {
		"id": "parent_a",
		"proprietes": {"reproduction_ref": "colon", "gestation": {"duree_gestation_ecoulee": 5.0}},
	}
	b._temps_ecoule = 3.0
	b._prochain_print_gestation = 5.0
	b._verifier_progression_gestation()
	v.v(b._prochain_print_gestation == 5.0, "avant l'intervalle (temps 3.0 < prochain 5.0) : aucune mise a jour")

	b._temps_ecoule = 10.0
	b._verifier_progression_gestation()
	v.v(b._prochain_print_gestation == 15.0,
		"au franchissement (temps 10.0 >= prochain 5.0) : prochain doit avancer de l'intervalle (5.0 -> 15.0)")

func _imprimer_ages_ne_plante_pas_sur_plusieurs_colons(v) -> void:
	var b := BancReproduction.new()
	b._temps_ecoule = 12.0
	b._colons = [
		{"id": "c1", "proprietes": {"age": 5.0, "stade": "enfant"}},
		{"id": "c2", "proprietes": {"age": 20.0, "stade": "adulte"}},
	]
	b._imprimer_ages()
	v.v(true, "_imprimer_ages doit parcourir tous les colons (stades differents, cle 'age' lue par point) sans planter")

# Chemin REEL complet, meme sequence que _phase4_naissance_avec_alleles_herites_verifiables
# jusqu'a naissance_prete, mais appelle ENSUITE l'instance _accoucher() (pas
# fabriquer_enfant() seule) : verrouille l'effet de bord complet -- ajout a
# _colons, noeud dessine, compteur, gestation effacee du porteur, enfant
# enregistre dans le monde.
func _accoucher_produit_un_enfant_et_efface_la_gestation_du_porteur(v) -> void:
	var cat := _catalogues()
	var colons := _fabriquer_deux(cat)
	var monde := _monde_avec(colons)
	var a: Dictionary = colons.parent_a
	var b: Dictionary = colons.parent_b
	_vieillir_jusqu_a([a, b], 18.0, cat.donnees.annees_par_seconde)
	var i := 0
	for _n in range(600):
		BancReproduction.avancer_cycle([a, b], monde, cat.canaux, cat.reproduction, DELTA_TICK, i, cat.donnees.annees_par_seconde)
		i += 1
		if BancReproduction.naissance_prete(a):
			break
	v.v(BancReproduction.naissance_prete(a), "verrou intermediaire : la naissance doit etre prete avant ce test")

	var banc := BancReproduction.new()
	banc._catalogue_types = cat.types
	banc._catalogue_genes = cat.genes
	banc._catalogue_heredite = cat.heredite
	banc._rng = RandomNumberGenerator.new()
	banc._rng.seed = int(cat.donnees.seed)
	banc._monde = monde
	banc._colons = [a, b]
	banc._porteur = a
	banc._offset_enfant = Vector3(20.0, -30.0, 0.0)
	banc._couleur_enfant = Color.WHITE

	banc._accoucher()

	v.v(banc._colons.size() == 3, "_accoucher doit ajouter exactement un enfant a _colons")
	var enfant: Dictionary = banc._colons[2]
	v.v(enfant.id == "enfant_1", "le premier enfant doit s'appeler enfant_1 (compteur demarre a 1)")
	v.v(banc._noeuds.has(enfant.id), "_accoucher doit dessiner un noeud pour l'enfant")
	v.v(not a.proprietes.has("gestation"), "la gestation du porteur doit etre effacee apres la naissance")
	v.v(banc._naissance_annoncee, "_naissance_annoncee doit passer a true")
	v.v(banc._compteur_enfant == 1, "le compteur d'enfant doit passer a 1")
	v.v(monde.par_id(enfant.id) != null, "l'enfant doit etre enregistre dans le monde (percevable)")

	# VERROU DU RETOUR EN RAFALE. L'accumulateur d'accouplement n'a aucune
	# decroissance : reste au-dessus du seuil, le partenaire repose une
	# gestation des le tick suivant, sans qu'aucune trace ne le dise.
	v.v(not a.proprietes.has("accouplement_accumulateur")
			and not b.proprietes.has("accouplement_accumulateur"),
		"la cloture doit vider l'accumulateur des DEUX parents, jamais du seul porteur")
	for n in range(1, 30):
		BancReproduction.avancer_cycle([a, b], monde, cat.canaux, cat.reproduction, DELTA_TICK, i + n, cat.donnees.annees_par_seconde)
	v.v(not a.proprietes.has("gestation"),
		"aucune gestation ne doit revenir dans les ticks qui suivent une naissance")
