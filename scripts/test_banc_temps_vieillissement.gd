extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_temps_vieillissement.gd
#
# CHEMIN REEL, jamais une fixture locale : data/types.json, data/canaux.json,
# data/etats.json, data/seuils_etat.json, data/epigenetique.json,
# data/heredite.json et data/banc_temps_vieillissement.json sont tous lus sur
# le disque, et le tick rejoue est EXACTEMENT avancer_tick, la meme fonction
# que _process appelle -- jamais une reconstitution parallele qui pourrait
# deriver.
#
# Ce qui est verrouille, dans l'ordre : l'accumulateur en jours et son seuil a
# 730 (avant : rien ; apres : le cout de vie module) ; la courbe d'age (montee
# jusqu'au pic, descente ensuite, plancher tenu) ; la competence qui monte
# toujours ; le recalcul a neuf de la force (trois appels au meme age rendent
# le meme nombre) ; l'absence de tout appel d'expression dans le tick ; la
# diploidie de l'heredite et le fait que la part d'un parent n'est pas un
# parametre ; la transmission des marques, celle du patrimoine (conservee) et
# les deux voies opposees de transmission des liens.

const Banc = preload("res://scripts/banc_temps_vieillissement.gd")
const Monde = preload("res://scripts/monde.gd")
const Heredite = preload("res://scripts/heredite.gd")
const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA := 0.1
const CHEMIN_BANC := "res://scripts/banc_temps_vieillissement.gd"

func _init() -> void:
	var v := Verif.new()
	_accumulateur_monte_de_un_par_jour(v)
	_effet_differe_muet_avant_le_seuil(v)
	_effet_differe_module_le_cout_apres_le_seuil(v)
	_force_monte_jusqu_au_pic_puis_decline(v)
	_competence_monte_toujours(v)
	_force_est_recalculee_a_neuf(v)
	_le_tick_n_appelle_jamais_expression(v)
	_cadence_de_pose_sous_la_survie_de_la_marque(v)
	_temoins_restent_hors_du_cycle_de_reproduction(v)
	_les_deux_lignees_ne_se_melangent_pas(v)
	_genes_transmis_par_diploidie(v)
	_part_de_parent_n_est_pas_un_parametre(v)
	_marques_epigenetiques_transmises(v)
	_patrimoine_transfere_et_conserve(v)
	_les_deux_voies_de_liens_sont_cablees(v)
	_facteur_de_temps_cycle_sur_la_liste(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: un effet pose aujourd'hui frappe au 730e jour, la force monte puis " +
			"decline quand la competence monte toujours, et les enfants recoivent genes, " +
			"marques et patrimoine -- les liens suivant la voie declaree par leur parent")
		quit(0)

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

# Reproduit EXACTEMENT le chargement de banc_temps_vieillissement.gd:_ready.
func _contexte() -> Dictionary:
	var config := _charger("res://data/banc_temps_vieillissement.json")
	var types := Banc.types_du_banc(_charger("res://data/types.json"))
	var epigenetique_partage := _charger("res://data/epigenetique.json")
	var genes: Dictionary = config.get("catalogue_genes", {})

	var colons: Array = []
	for decl in config.get("colons", []):
		colons.append(Banc.construire_colon(decl, config, types, genes, epigenetique_partage))

	var monde := Monde.new()
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)

	return {
		"config": config,
		"types": types,
		"genes": genes,
		"colons": colons,
		"monde": monde,
		"canaux": _charger("res://data/canaux.json"),
		"etats": _charger("res://data/etats.json"),
		"heredite": _charger("res://data/heredite.json"),
		"epigenetique_partage": epigenetique_partage,
		"epigenetique": Banc.catalogue_epigenetique_effectif(config, colons, epigenetique_partage),
		"seuils": Banc.catalogue_seuils_effectif(_charger("res://data/seuils_etat.json"), config),
		"reproduction": config.get("catalogue_reproduction_local", {}),
		"horloges": {},
	}

func _colon(ctx: Dictionary, id: String) -> Dictionary:
	for colon in ctx.colons:
		if String(colon.id) == id:
			return colon
	return {}

func _avancer(ctx: Dictionary, nb_ticks: int) -> void:
	for i in range(nb_ticks):
		var resultat: Dictionary = Banc.avancer_tick(
			ctx.colons, ctx.monde, DELTA, i, ctx.config, ctx.canaux, ctx.reproduction,
			ctx.etats, ctx.seuils, ctx.epigenetique, ctx.horloges)
		ctx["horloges"] = resultat.horloges

func _canal_vie(colon: Dictionary, config: Dictionary) -> Dictionary:
	return colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_vie), {})

# ---------------------------------------------------------------------------
# LIGNE 2 -- l'accumulateur et son seuil
# ---------------------------------------------------------------------------

func _accumulateur_monte_de_un_par_jour(v) -> void:
	var ctx := _contexte()
	var nom := String(ctx.config.nom_accumulateur_differe)
	var un_jour: float = 1.0 / float(ctx.config.jours_par_seconde)

	var decideur := _colon(ctx, "adulte")
	v.v(decideur.proprietes.has(nom), "un colon qui declare la decision doit porter l'accumulateur des sa construction")
	v.v(is_equal_approx(float(decideur.proprietes[nom]), 0.0), "l'accumulateur doit demarrer exactement a zero")

	Banc.poser_accumulateur_differe(decideur, un_jour, ctx.config)
	v.v(is_equal_approx(float(decideur.proprietes[nom]), 1.0),
		"un jour de simulation ecoule doit faire monter l'accumulateur d'exactement 1.0")
	Banc.poser_accumulateur_differe(decideur, 3.0 * un_jour, ctx.config)
	v.v(is_equal_approx(float(decideur.proprietes[nom]), 4.0),
		"trois jours de plus doivent porter l'accumulateur a 4.0 -- une addition, jamais un recalcul")

	var temoin := _colon(ctx, "jeune")
	v.v(not temoin.proprietes.has(nom),
		"un colon qui n'a rien decide ne doit jamais porter l'accumulateur")
	Banc.poser_accumulateur_differe(temoin, un_jour, ctx.config)
	v.v(not temoin.proprietes.has(nom),
		"la cle absente est un point neutre : poser_accumulateur_differe ne doit jamais l'inventer")

func _ticks_pour_jours(ctx: Dictionary, jours: float) -> int:
	return int(ceil(jours / (float(ctx.config.jours_par_seconde) * DELTA)))

func _effet_differe_muet_avant_le_seuil(v) -> void:
	var ctx := _contexte()
	var config: Dictionary = ctx.config
	var seuil: float = float(ctx.seuils[String(config.etat_effet_differe)].seuil)
	v.v(is_equal_approx(seuil, 730.0), "le seuil partage doit valoir 730 jours")

	# Un cran SOUS le seuil : la comparaison de seuil_etat.gd est strictement
	# au-dessus, un accumulateur pile a 730.0 ne declencherait pas.
	_avancer(ctx, _ticks_pour_jours(ctx, seuil) - 2)

	var decideur := _colon(ctx, "adulte")
	var actifs: Array = decideur.proprietes.get("etats_actifs", [])
	v.v(float(decideur.proprietes[String(config.nom_accumulateur_differe)]) < seuil,
		"verrou intermediaire : l'accumulateur doit encore etre sous le seuil")
	v.v(not actifs.has(String(config.etat_effet_differe)),
		"sous le seuil, l'etat differe ne doit pas etre pose -- rien ne doit se voir")
	v.v(is_equal_approx(float(_canal_vie(decideur, config).cout_base), float(config.cout_vie_base)),
		"sous le seuil, le cout de vie doit rester exactement celui de base")

	var temoin := _colon(ctx, "jeune")
	v.v(not temoin.proprietes.get("etats_actifs", []).has(String(config.etat_effet_differe)),
		"un colon sans accumulateur est un chemin mort pour l'entree de seuil partagee")

func _effet_differe_module_le_cout_apres_le_seuil(v) -> void:
	var ctx := _contexte()
	var config: Dictionary = ctx.config
	var seuil: float = float(ctx.seuils[String(config.etat_effet_differe)].seuil)
	_avancer(ctx, _ticks_pour_jours(ctx, seuil) + 3)

	var decideur := _colon(ctx, "adulte")
	var actifs: Array = decideur.proprietes.get("etats_actifs", [])
	v.v(actifs.has(String(config.etat_effet_differe)),
		"au-dela de 730 jours, l'etat differe doit etre pose")

	var facteur: float = float(ctx.etats[String(config.etat_effet_differe)].effets[0].facteur)
	v.v(facteur > 1.0, "l'effet declare doit bien aggraver le cout, jamais l'alleger")
	v.v(is_equal_approx(float(_canal_vie(decideur, config).cout_base),
			float(config.cout_vie_base) * facteur),
		"le cout de vie du canal doit valoir exactement la valeur effective composee par etat_effectif.gd")

	var temoin := _colon(ctx, "jeune")
	v.v(not temoin.proprietes.get("etats_actifs", []).has(String(config.etat_effet_differe)),
		"celui qui n'a rien decide ne doit jamais recevoir l'etat, si longtemps qu'on attende")
	v.v(is_equal_approx(float(_canal_vie(temoin, config).cout_base), float(config.cout_vie_base)),
		"son cout de vie doit rester celui de base")
	v.v(Banc.reserve_vie(temoin, config) > Banc.reserve_vie(decideur, config),
		"celui qui a decide doit avoir bien moins de reserve que celui qui n'a rien decide")

# ---------------------------------------------------------------------------
# LIGNE 3 -- la courbe d'age et la competence
# ---------------------------------------------------------------------------

func _force_monte_jusqu_au_pic_puis_decline(v) -> void:
	var config := _charger("res://data/banc_temps_vieillissement.json")
	var pic: float = float(config.pic_force_ans)
	var declin: float = float(config.declin_par_an_apres)
	var plancher: float = float(config.plancher_force)
	var base := 1.0

	var f5 := Banc.force_effective(5.0, base, pic, declin, plancher)
	var f15 := Banc.force_effective(15.0, base, pic, declin, plancher)
	var f_pic := Banc.force_effective(pic, base, pic, declin, plancher)
	var f40 := Banc.force_effective(40.0, base, pic, declin, plancher)
	var f60 := Banc.force_effective(60.0, base, pic, declin, plancher)

	v.v(f5 < f15 and f15 < f_pic, "avant le pic, la force doit monter avec l'age")
	v.v(is_equal_approx(f_pic, base), "au pic exactement, la force effective doit valoir la force de base")
	v.v(f_pic > f40 and f40 > f60, "apres le pic, la force doit descendre avec l'age")
	v.v(f5 < f60, "un enfant de cinq ans doit rester plus faible qu'un vieux de soixante")
	v.v(Banc.force_effective(500.0, base, pic, declin, plancher) >= plancher,
		"la droite descendante ne doit jamais passer sous le plancher, si vieux qu'on aille")
	v.v(is_equal_approx(Banc.force_effective(40.0, base, 0.0, declin, plancher), base),
		"un pic nul rend la base telle quelle, jamais une division par zero")

	# La force de BASE differe par les genes : ce que la courbe multiplie n'est
	# pas le meme nombre pour tout le monde.
	var forte := Banc.force_effective(20.0, 1.4, pic, declin, plancher)
	var faible := Banc.force_effective(20.0, 0.6, pic, declin, plancher)
	v.v(forte > faible, "au meme age, une force de base plus haute doit rendre une force effective plus haute")

func _competence_monte_toujours(v) -> void:
	var ctx := _contexte()
	var config: Dictionary = ctx.config
	var vieux := _colon(ctx, "vieux")
	var jeune := _colon(ctx, "jeune")

	var depart_vieux := Banc.competence_effective(vieux, config)
	var depart_jeune := Banc.competence_effective(jeune, config)
	v.v(depart_vieux > depart_jeune,
		"a la construction, le vieux doit deja porter les annees qu'il a vecues -- le jeune non")

	var releves: Array = []
	for _i in range(6):
		_avancer(ctx, 40)
		releves.append(Banc.competence_effective(vieux, config))
	for i in range(1, releves.size()):
		v.v(float(releves[i]) > float(releves[i - 1]),
			"la competence doit monter a chaque releve, jamais stagner ni redescendre")

	v.v(Banc.competence_effective(vieux, config) > depart_vieux,
		"apres une longue traversee, la competence du vieux doit avoir monte")
	v.v(Banc.competence_effective(jeune, config) > depart_jeune,
		"celle du jeune aussi -- personne ne cesse de vieillir")
	v.v(Banc.competence_effective(vieux, config) > Banc.competence_effective(jeune, config),
		"le vieux doit rester le plus competent, l'ecart d'annees ne se rattrape pas")
	v.v(Banc.force_effective(float(vieux.proprietes.age), 1.0, float(config.pic_force_ans),
			float(config.declin_par_an_apres), float(config.plancher_force))
		< Banc.force_effective(float(jeune.proprietes.age), 1.0, float(config.pic_force_ans),
			float(config.declin_par_an_apres), float(config.plancher_force)),
		"et rester le plus faible : la force et le savoir ne suivent pas la meme courbe")

func _force_est_recalculee_a_neuf(v) -> void:
	var ctx := _contexte()
	var config: Dictionary = ctx.config
	var colon := _colon(ctx, "veteran")

	var premiere := Banc.poser_force_effective(colon, config)
	var deuxieme := Banc.poser_force_effective(colon, config)
	var troisieme := Banc.poser_force_effective(colon, config)
	v.v(is_equal_approx(premiere, deuxieme) and is_equal_approx(deuxieme, troisieme),
		"a age inchange, trois appels doivent rendre exactement le meme nombre -- aucune accumulation")
	v.v(is_equal_approx(float(colon.proprietes[String(config.nom_force_effective)]), premiere),
		"la valeur ecrite doit etre celle rendue, jamais une somme")

	var base_avant: float = float(colon.proprietes[String(config.nom_force_base)])
	_avancer(ctx, 30)
	v.v(is_equal_approx(float(colon.proprietes[String(config.nom_force_base)]), base_avant),
		"la force de BASE ne doit jamais bouger : c'est elle qui empeche le champ derive de deriver")

func _le_tick_n_appelle_jamais_expression(v) -> void:
	var texte := FileAccess.get_file_as_string(CHEMIN_BANC)
	v.v(not texte.is_empty(), "le fichier de banc doit etre lisible sur le disque")

	var debut := texte.find("static func avancer_tick(")
	v.v(debut != -1, "avancer_tick doit exister dans le fichier")
	var fin := texte.find("\nstatic func ", debut + 1)
	if fin == -1:
		fin = texte.length()
	var bloc := texte.substr(debut, fin - debut)

	# Compose les noms cherches morceau par morceau, pour que ce test ne
	# rougisse pas sur sa propre phrase.
	var verbe_lecture := "expr" + "imer"
	var verbe_ecriture := "appl" + "iquer"
	v.v(bloc.find(verbe_lecture) == -1 and bloc.find(verbe_ecriture) == -1,
		"le tick ne doit appeler ni la lecture ni l'ecriture du mecanisme de generation : " +
		"rappele en boucle, il fait diverger sans borne la propriete visee")

	var debut_process := texte.find("func _process(")
	v.v(debut_process != -1, "_process doit exister")
	var fin_process := texte.find("\nfunc ", debut_process + 1)
	var bloc_process := texte.substr(debut_process, fin_process - debut_process)
	v.v(bloc_process.find("avancer_tick(") != -1,
		"_process doit passer par avancer_tick -- le test ne doit jamais rejouer un tick different de la scene")

func _cadence_de_pose_sous_la_survie_de_la_marque(v) -> void:
	var config := _charger("res://data/banc_temps_vieillissement.json")
	var epigenetique := _charger("res://data/epigenetique.json")
	var nom := String(config.nom_marque_competence)
	v.v(epigenetique.has(nom), "la marque d'annees doit exister dans le catalogue partage")

	var regle: Dictionary = epigenetique[nom]
	var pose: float = float(regle.modulateur_pose)
	var decroissance: float = float(regle.taux_decroissance)
	var plancher: float = float(regle.plancher_suppression)
	v.v(decroissance > 0.0, "une decroissance nulle ferait de ce mecanisme un simple compteur")
	var survie: float = (pose - plancher) / decroissance
	var intervalle := Banc.intervalle_pose_s(config)
	v.v(intervalle > 0.0 and intervalle < survie,
		"l'intervalle de pose doit rester sous la survie d'une marque fraiche, sinon elle est effacee entre deux poses")
	v.v(pose / intervalle > decroissance,
		"la montee nette doit rester strictement positive : la competence monte toujours")
	v.v(float(regle.taux_transmission_enfant) > 0.0,
		"la marque doit etre transmissible, sinon l'enfant n'heriterait de rien d'acquis")

# ---------------------------------------------------------------------------
# LIGNE 4 -- l'heritage
# ---------------------------------------------------------------------------

# Fait tourner le cycle jusqu'a ce que les deux porteurs soient prets a
# accoucher, puis rend le contexte tel quel.
func _contexte_a_la_naissance(v) -> Dictionary:
	var ctx := _contexte()
	var pret := false
	for _n in range(400):
		_avancer(ctx, 1)
		if Banc.naissance_prete(_colon(ctx, "porteur_a")) and Banc.naissance_prete(_colon(ctx, "porteur_b")):
			pret = true
			break
	v.v(pret, "apres exposition mutuelle puis gestation, les deux porteurs doivent etre prets a accoucher")
	return ctx

func _temoins_restent_hors_du_cycle_de_reproduction(v) -> void:
	var ctx := _contexte_a_la_naissance(v)
	for id in ["jeune", "adulte", "veteran", "vieux"]:
		var temoin := _colon(ctx, String(id))
		v.v(not temoin.proprietes.has("gestation"),
			"le temoin '%s' ne doit jamais entrer en gestation" % id)
		v.v(not temoin.proprietes.has("accouplement_accumulateur"),
			"le temoin '%s' doit etre ecarte par la garde du mecanisme, avant meme l'accumulateur" % id)

func _les_deux_lignees_ne_se_melangent_pas(v) -> void:
	var ctx := _contexte_a_la_naissance(v)
	v.v(String(_colon(ctx, "porteur_a").proprietes.gestation.partenaire_id) == "partenaire_a",
		"le porteur de la premiere lignee ne peut feconder que son partenaire d'espece")
	v.v(String(_colon(ctx, "porteur_b").proprietes.gestation.partenaire_id) == "partenaire_b",
		"le porteur de la seconde lignee non plus -- l'egalite d'espece suffit a les separer")
	v.v(not _colon(ctx, "partenaire_a").proprietes.gestation.has("duree_gestation_ecoulee"),
		"la gestation du partenaire ne doit jamais avancer, sinon un accouplement rendrait deux enfants")

func _naitre(ctx: Dictionary, id_porteur: String, id_enfant: String) -> Dictionary:
	var porteur := _colon(ctx, id_porteur)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(ctx.config.seed)
	var enfant := Banc.fabriquer_enfant(id_enfant, porteur, porteur.position, ctx.config,
		ctx.types, ctx.genes, ctx.heredite, ctx.epigenetique, rng)
	var heritage := Banc.transmettre_heritage(porteur, enfant, ctx.config, ctx.epigenetique)
	return {"porteur": porteur, "enfant": enfant, "heritage": heritage}

func _genes_transmis_par_diploidie(v) -> void:
	var ctx := _contexte_a_la_naissance(v)
	var n := _naitre(ctx, "porteur_a", "enfant_test_a")
	var enfant: Dictionary = n.enfant
	var porteur: Dictionary = n.porteur

	v.v(enfant.proprietes.genes_actifs == porteur.proprietes.genes_actifs,
		"l'enfant doit porter la meme liste de genes actifs que son parent -- le kit ne la produit jamais")
	for nom_gene in porteur.proprietes.genes_actifs:
		var alleles: Array = enfant.proprietes.genes_etat.get(nom_gene, {}).get("alleles", [])
		v.v(alleles.size() == 2,
			"le mode sexue doit toujours rendre exactement deux alleles, un de chaque parent")
		# Les deux parents sont homozygotes de signes opposes : le premier
		# allele ne peut venir que de la porteuse, le second que du partenaire.
		v.v(abs(float(alleles[0]) - 1.0) < 0.5,
			"le premier allele doit venir de la porteuse, a la mutation pres")
		v.v(abs(float(alleles[1]) + 1.0) < 0.5,
			"le second allele doit venir du partenaire, a la mutation pres")

	var base_enfant: float = float(enfant.proprietes[String(ctx.config.nom_force_base)])
	var base_porteur: float = float(porteur.proprietes[String(ctx.config.nom_force_base)])
	var base_partenaire: float = float(_colon(ctx, "partenaire_a").proprietes[String(ctx.config.nom_force_base)])
	v.v(base_enfant < base_porteur and base_enfant > base_partenaire,
		"la force de base de l'enfant doit tomber entre celles de ses deux parents")

func _part_de_parent_n_est_pas_un_parametre(v) -> void:
	var source := FileAccess.get_file_as_string("res://scripts/heredite.gd")
	v.v(not source.is_empty(), "le mecanisme d'heredite doit etre lisible sur le disque")
	v.v(source.find("part_parent") == -1,
		"aucune part de parent n'est reglable : la diploidie est ecrite dans le mecanisme, jamais en donnee")

	var catalogue := _charger("res://data/heredite.json")
	v.v(not catalogue.defaut.has("part_parent_1"),
		"le catalogue partage ne doit pas non plus porter une part de parent")

	# La preuve par le comportement : quelle que soit la TAILLE des tableaux
	# parents, le kit rendu en porte toujours deux, un tire chez chacun.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var porteuse := {
		"id": "p", "position": Vector3.ZERO,
		"proprietes": {
			"mode_reproduction": "sexuee",
			"genes_actifs": ["g"],
			"genes_etat": {"g": {"alleles": [2.0, 2.0, 2.0, 2.0, 2.0]}},
			"marques_epigenetiques": {},
			"gestation": {
				"partenaire_id": "q",
				"partenaire_genes_etat": {"g": {"alleles": [-2.0]}},
				"partenaire_marques_epigenetiques": {},
			},
		},
	}
	var kit := Heredite.fabriquer_genes_enfant(porteuse, catalogue, {}, rng)
	var alleles: Array = kit.genes_etat.g.alleles
	v.v(alleles.size() == 2,
		"cinq alleles chez l'un et un seul chez l'autre rendent quand meme deux alleles -- moitie chacun, en dur")

func _marques_epigenetiques_transmises(v) -> void:
	var ctx := _contexte_a_la_naissance(v)
	var n := _naitre(ctx, "porteur_a", "enfant_test_marques")
	var config: Dictionary = ctx.config
	var nom := String(config.nom_marque_competence)

	var chez_porteur := Banc.modulateur_competence(n.porteur, config)
	var chez_partenaire := Banc.modulateur_competence(_colon(ctx, "partenaire_a"), config)
	var chez_enfant := Banc.modulateur_competence(n.enfant, config)
	var taux: float = float(ctx.epigenetique_partage[nom].taux_transmission_enfant)

	v.v(chez_porteur > 0.0, "le parent doit porter une marque d'annees vecues avant la naissance")
	v.v(chez_enfant > 0.0, "l'enfant doit naitre avec une part de la marque de ses parents")
	v.v(is_equal_approx(chez_enfant, max(chez_porteur, chez_partenaire) * taux),
		"la marque recue doit valoir exactement le plus fort des deux parents multiplie par le taux du catalogue")
	v.v(chez_enfant < chez_porteur,
		"l'enfant ne doit jamais naitre aussi competent que son parent")

func _patrimoine_transfere_et_conserve(v) -> void:
	var ctx := _contexte_a_la_naissance(v)
	var config: Dictionary = ctx.config
	var porteur := _colon(ctx, "porteur_a")
	var avant := Banc.reserve_patrimoine(porteur, config)
	v.v(avant > 0.0, "le parent doit porter un patrimoine avant la naissance")

	var n := _naitre(ctx, "porteur_a", "enfant_test_objets")
	var apres_porteur := Banc.reserve_patrimoine(n.porteur, config)
	var apres_enfant := Banc.reserve_patrimoine(n.enfant, config)

	v.v(apres_enfant > 0.0, "l'enfant doit recevoir une part du patrimoine")
	v.v(is_equal_approx(apres_enfant, avant * float(config.part_heritage_objets)),
		"la part recue doit etre exactement celle declaree en donnee")
	v.v(is_equal_approx(apres_porteur + apres_enfant, avant),
		"la somme des deux doit etre invariante : le transfert est conserve, rien n'est cree")
	v.v(is_equal_approx(float(n.heritage.objets), apres_enfant),
		"la trace doit rapporter la quantite reellement transferee, jamais celle demandee")

	var enfant_neutre := _colon(ctx, "jeune")
	v.v(is_equal_approx(Banc.reserve_patrimoine(enfant_neutre, config), 0.0),
		"un colon qui ne declare aucun patrimoine n'en porte aucun")

func _les_deux_voies_de_liens_sont_cablees(v) -> void:
	var ctx := _contexte_a_la_naissance(v)
	var config: Dictionary = ctx.config

	var voie_a := _naitre(ctx, "porteur_a", "enfant_voie_a")
	var voie_b := _naitre(ctx, "porteur_b", "enfant_voie_b")

	v.v(String(voie_a.heritage.voie) == "A" and String(voie_b.heritage.voie) == "B",
		"chaque porteur doit declarer sa voie, jamais un defaut du code")

	var herites_a := Banc.liens_herites(voie_a.enfant, config)
	var herites_b := Banc.liens_herites(voie_b.enfant, config)

	v.v(herites_a.has("jeune"),
		"voie A : l'enfant doit porter la marque du lien fort de son parent")
	v.v(not herites_a.has("adulte"),
		"voie A : un lien sous le seuil ne doit pas passer -- le gate est lu sur le parent")
	v.v(herites_b.is_empty(),
		"voie B : l'enfant doit partir neutre, aucune marque de lien posee")

	# Les deux parents portent EXACTEMENT les memes liens : seule la voie
	# declaree les separe, jamais une difference de situation.
	var porteur_b := _colon(ctx, "porteur_b")
	v.v(LienPersonnel.force(voie_a.porteur, "jeune", {}) > 0.0
			and is_equal_approx(LienPersonnel.force(porteur_b, "jeune", {}),
				LienPersonnel.force(voie_a.porteur, "jeune", {})),
		"les deux porteurs doivent porter le meme lien vers la meme cible")
	v.v(is_equal_approx(LienPersonnel.force(voie_a.enfant, "jeune", {}), 0.0),
		"aucune des deux voies ne pose un lien personnel sur l'enfant -- le registre reste ne du vecu")

func _facteur_de_temps_cycle_sur_la_liste(v) -> void:
	v.v(Banc.facteur_suivant(0, 3) == 1 and Banc.facteur_suivant(2, 3) == 0,
		"le facteur de temps doit boucler sur la liste declaree")
	v.v(Banc.facteur_suivant(0, 0) == 0, "une liste vide ne doit jamais faire diviser par zero")
