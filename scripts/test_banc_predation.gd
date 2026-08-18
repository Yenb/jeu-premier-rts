extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_predation.gd
#
# Verrouille le cablage de banc_predation.gd -- L'ORCHESTRATEUR : ordre fixe de
# dix-sept pas, hierarchie qui decide qui mange, agression a trois causes
# tranchee par bifurcation.gd, naissances et morts en continu. Les DIX-NEUF
# mecanismes du coeur composes restent INCHANGES -- ce fichier ne verrouille
# que le cablage.
#
# data/banc_predation.json et les neuf catalogues partages sont lus SUR LE
# DISQUE, jamais recopies ici (meme discipline que test_banc_menace_combat.gd/
# test_banc_nutrition.gd) : la calibration reste reglable par Yael sans toucher
# a ce fichier.
#
# DEUX FAMILLES DE CAS, a ne pas confondre :
# - les cas de mecanique posent leurs propres positions/energies pour isoler UNE
#   transition, et ne disent rien de la jouabilite du banc ;
# - _config_reelle_du_disque_fait_vivre_la_population rejoue
#   data/banc_predation.json EN ENTIER, sans un seul chiffre local. Sans lui,
#   tout ce fichier resterait VERT alors que le banc lance a l'ecran ne
#   produirait ni repas, ni naissance, ni mort -- exactement le trou trouve sur
#   banc_maladie.

const Banc = preload("res://scripts/banc_predation.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DELTA_TICK := 0.1

var _config: Dictionary
var _etats: Dictionary
var _canaux: Dictionary
var _deformations: Dictionary
var _actions: Dictionary
var _orientations: Dictionary
var _profils: Dictionary
var _reproduction: Dictionary
var _heredite: Dictionary
var _materiaux: Dictionary
var _types: Dictionary

func _init() -> void:
	_config = _json("res://data/banc_predation.json")
	_etats = _json("res://data/etats.json")
	_canaux = _json("res://data/canaux.json")
	_deformations = _json("res://data/deformations.json")
	_actions = _json("res://data/types_choses.json")
	_orientations = _json("res://data/orientations.json")
	_profils = _json("res://data/profils_saillance.json")
	_reproduction = _json("res://data/reproduction.json")
	_heredite = _json("res://data/heredite.json")
	_materiaux = _json("res://data/materiaux.json")
	_types = Banc.catalogue_types(_config, _json("res://data/types.json"))

	_le_dominant_mange_en_premier()
	_le_non_dominant_attend()
	_le_score_de_hierarchie_est_recalcule_a_neuf()
	_la_proie_se_reproduit_quand_ses_reserves_sont_hautes()
	_la_proie_ne_se_reproduit_pas_sous_le_seuil()
	_le_predateur_meurt_de_faim_sans_proies()
	_la_proie_videe_meurt_et_laisse_un_reste()
	_les_naissances_ajoutent_des_entites_au_monde()
	_les_morts_sont_retirees_du_monde()
	_un_seul_des_deux_geste_l_autre_est_libere()
	_l_agression_bifurque_vers_la_faim()
	_l_agression_bifurque_vers_le_territoire()
	_l_agression_bifurque_vers_les_petits()
	_le_biais_compose_fait_gagner_la_cause_dominante()
	_la_deformation_monte_la_saillance_de_la_cible()
	_un_seul_ecrivain_pour_surcout_action_et_poids_verbes()
	_le_gate_de_mouvement_tient_le_troupeau()
	_aucune_bifurcation_sans_cause()
	_la_population_oscille()
	_config_reelle_du_disque_fait_vivre_la_population()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_predation.gd -- orchestrateur d'ordre fixe : le dominant " +
		"mange et le second attend (somme ponderee recalculee a neuf, push_error " +
		"sur egalite), la proie ne se reproduit que sous gate de reserve, le " +
		"predateur meurt de faim, la proie videe laisse un reste, les naissances " +
		"entrent dans le Monde et les morts en sortent par reconstruction, " +
		"l'agression bifurque vers faim/territoire/petits selon le biais COMPOSE, " +
		"la deformation monte la saillance de la cible de la sortie gagnante, " +
		"surcout_action et poids_verbes n'ont qu'un ecrivain, et la population " +
		"oscille -- sans qu'aucun mecanisme du coeur ne soit touche ni qu'un seul " +
		"de ne soit tire hors de la mutation genetique seedee")
	quit(0)

func _json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

# ---- Outils de cas ----

func _proie(id: String, position: Vector3) -> Dictionary:
	return Banc.fabriquer_animal(
		id, String(_config.type_par_espece.proie_predation), position, {}, _config, _types, {})

func _predateur(id: String, position: Vector3, biais: Dictionary) -> Dictionary:
	return Banc.fabriquer_animal(
		id, String(_config.type_par_espece.predateur_predation), position, biais, _config, _types, {})

func _biais_du_disque(id: String) -> Dictionary:
	for decl in _config.predateurs:
		if String(decl.id) == id:
			return decl.biais_agression
	return {}

func _poser_energie(animal: Dictionary, valeur: float) -> void:
	animal.proprietes.reserves[String(_config.nom_reserve_energie)]["reserve"] = valeur

func _poser_force(animal: Dictionary, valeur: float) -> void:
	animal.proprietes[String(_config.nom_force)] = valeur

# Une scene de test : la liste d'animaux devient un etat complet, Monde compris.
func _etat_avec(animaux: Array) -> Dictionary:
	var etat := {
		"animaux": animaux,
		"restes": [],
		"monde": Banc.monde_reconstruit(animaux),
		"rng": RandomNumberGenerator.new(),
		"temps": 0.0,
		"tick": 0,
		"naissances": 0,
		"morts": 0,
		"compteur_enfant": 0,
	}
	etat.rng.seed = int(_config.seed)
	return etat

func _avancer(etat: Dictionary, delta: float) -> Dictionary:
	return Banc.avancer(
		etat, _config, _etats, _canaux, _deformations, _profils, _actions,
		_orientations, _reproduction, _heredite, _types, _materiaux, delta)

func _avancer_n(etat: Dictionary, ticks: int) -> Dictionary:
	var dernier: Dictionary = {}
	for i in range(ticks):
		dernier = _avancer(etat, DELTA_TICK)
	return dernier

func _rapport_de(rapport: Dictionary, id: String) -> Dictionary:
	for a in rapport.animaux:
		if String(a.id) == id:
			return a
	return {}

func _present(etat: Dictionary, id: String) -> bool:
	return etat.monde.choses.has(id)

# ---- LA HIERARCHIE (audit ligne 7) ----

func _le_dominant_mange_en_premier() -> void:
	var proie := _proie("p", Vector3.ZERO)
	var fort := _predateur("fort", Vector3(30.0, 0.0, 0.0), _biais_du_disque("predateur_chasseur"))
	var faible := _predateur("faible", Vector3(-30.0, 0.0, 0.0), _biais_du_disque("predateur_chasseur"))
	_poser_force(fort, 9.0)
	_poser_force(faible, 2.0)
	verif.v(Banc.score_hierarchie(fort, _config) > Banc.score_hierarchie(faible, _config),
		"prerequis : le fort doit avoir le score de hierarchie le plus haut")

	var repas := Banc.repas_du_tick([proie, fort, faible], _config)
	verif.v(repas.size() == 1, "une proie a portee de deux predateurs doit donner UN SEUL repas (%d obtenu)" % repas.size())
	verif.v(String(repas[0].mangeur_id) == "fort",
		"le predateur au score le plus haut doit manger (mangeur '%s')" % String(repas[0].mangeur_id))

	# et le transfert est bien CONSERVATIF (consommer.gd) : ce que la proie perd,
	# le mangeur le gagne, exactement.
	_poser_energie(proie, 70.0)
	_poser_energie(fort, 20.0)
	var etat := _etat_avec([proie, fort, faible])
	var avant_proie := Banc.energie(proie, _config)
	var avant_fort := Banc.energie(fort, _config)
	var avant_faible := Banc.energie(faible, _config)
	_avancer(etat, DELTA_TICK)
	verif.v(Banc.energie(fort, _config) > avant_fort,
		"le mangeur doit gagner de l'energie (%.2f -> %.2f)" % [avant_fort, Banc.energie(fort, _config)])
	verif.v(Banc.energie(proie, _config) < avant_proie,
		"la proie doit en perdre (%.2f -> %.2f)" % [avant_proie, Banc.energie(proie, _config)])
	verif.v(Banc.energie(faible, _config) < avant_faible,
		"le non dominant ne gagne rien -- il ne fait que depenser (%.2f -> %.2f)" % [avant_faible, Banc.energie(faible, _config)])

func _le_non_dominant_attend() -> void:
	var proie := _proie("p", Vector3.ZERO)
	var fort := _predateur("fort", Vector3(30.0, 0.0, 0.0), _biais_du_disque("predateur_chasseur"))
	var faible := _predateur("faible", Vector3(-30.0, 0.0, 0.0), _biais_du_disque("predateur_chasseur"))
	_poser_force(fort, 9.0)
	_poser_force(faible, 2.0)
	var repas := Banc.repas_du_tick([proie, fort, faible], _config)
	verif.v(repas[0].attendants.has("faible"),
		"le predateur non dominant doit figurer dans les attendants (%s obtenu)" % [repas[0].attendants])

	# le fort retire, c'est le faible qui mange : la place se libere, elle n'est
	# pas reservee a un individu.
	var repas_seul := Banc.repas_du_tick([proie, faible], _config)
	verif.v(String(repas_seul[0].mangeur_id) == "faible",
		"le fort absent, le faible doit manger a son tour (mangeur '%s')" % String(repas_seul[0].mangeur_id))
	verif.v(repas_seul[0].attendants.is_empty(), "et n'avoir personne derriere lui")

	# hors de portee de morsure : aucun repas, quel que soit le score
	var loin := _predateur("loin", Vector3(float(_config.portee_morsure) + 50.0, 0.0, 0.0), {})
	_poser_force(loin, 99.0)
	verif.v(Banc.repas_du_tick([proie, loin], _config).is_empty(),
		"un predateur hors de portee_morsure ne mange pas, meme le plus fort du banc")

func _le_score_de_hierarchie_est_recalcule_a_neuf() -> void:
	var animal := _predateur("a", Vector3.ZERO, {})
	var attendu: float = float(_config.hierarchie.poids_masse) * float(animal.proprietes.masse) \
		+ float(_config.hierarchie.poids_force) * float(animal.proprietes.force)
	verif.v(is_equal_approx(Banc.score_hierarchie(animal, _config), attendu),
		"le score doit valoir exactement poids_masse x masse + poids_force x force (%.4f attendu, %.4f obtenu)"
			% [attendu, Banc.score_hierarchie(animal, _config)])
	# cent lectures d'affilee sur un animal immobile rendent le MEME nombre :
	# c'est une LECTURE, jamais un '+=' (le champ derive ne peut pas deriver).
	var premier := Banc.score_hierarchie(animal, _config)
	for i in range(100):
		Banc.score_hierarchie(animal, _config)
	verif.v(is_equal_approx(Banc.score_hierarchie(animal, _config), premier),
		"cent lectures ne doivent JAMAIS faire deriver le score -- recalcul a neuf, jamais une accumulation")
	# et le gene 'vigueur' entre reellement dedans : la hierarchie est heritable
	var vigoureux := Banc.fabriquer_animal(
		"v", String(_config.type_par_espece.predateur_predation), Vector3.ZERO, {},
		_config, _types, {"vigueur": {"alleles": [1.0, 1.0]}})
	verif.v(Banc.score_hierarchie(vigoureux, _config) > Banc.score_hierarchie(animal, _config),
		"un animal aux alleles 'vigueur' positifs doit avoir un score PLUS HAUT -- la hierarchie est heritable (%.2f contre %.2f)"
			% [Banc.score_hierarchie(vigoureux, _config), Banc.score_hierarchie(animal, _config)])

# ---- LA REPRODUCTION SOUS GATE (audit ligne 5) ----

func _la_proie_se_reproduit_quand_ses_reserves_sont_hautes() -> void:
	var a := _proie("proie_a", Vector3(-40.0, 0.0, 0.0))
	var b := _proie("proie_b", Vector3(40.0, 0.0, 0.0))
	_poser_energie(a, float(_config.capacite_energie))
	_poser_energie(b, float(_config.capacite_energie))
	verif.v(Banc.reproduction_autorisee(a, _config), "prerequis : reserve pleine -> gate ouvert")
	var etat := _etat_avec([a, b])
	var naissance_vue := false
	for i in range(400):
		if not _avancer(etat, DELTA_TICK).naissances.is_empty():
			naissance_vue = true
			break
	verif.v(naissance_vue, "deux proies adultes a reserve haute doivent produire une naissance en 40 s")
	verif.v(int(etat.naissances) >= 1, "le compteur de naissances doit avoir monte (%d)" % int(etat.naissances))

func _la_proie_ne_se_reproduit_pas_sous_le_seuil() -> void:
	var seuil: float = float(_config.seuil_reproduction.proie_predation)
	var a := _proie("proie_a", Vector3(-40.0, 0.0, 0.0))
	var b := _proie("proie_b", Vector3(40.0, 0.0, 0.0))
	_poser_energie(a, seuil - 20.0)
	_poser_energie(b, seuil - 20.0)
	verif.v(not Banc.reproduction_autorisee(a, _config), "prerequis : sous le seuil -> gate ferme")
	var etat := _etat_avec([a, b])
	# assez court pour que le regain (cout_base negatif) ne les ait pas encore
	# ramenees au-dessus du seuil : c'est bien le GATE qui retient, pas le hasard
	var accumule := 0.0
	for i in range(30):
		_avancer(etat, DELTA_TICK)
		accumule = max(accumule, float(a.proprietes.get("accouplement_accumulateur", {}).get("proie_b", 0.0)))
	verif.v(is_equal_approx(accumule, 0.0),
		"sous le seuil, accouplement.gd ne doit JAMAIS etre appele -- son accumulateur reste a zero (%.3f obtenu)" % accumule)
	verif.v(not a.proprietes.has("gestation"), "et aucune gestation ne doit etre posee")

func _un_seul_des_deux_geste_l_autre_est_libere() -> void:
	var a := _proie("proie_a", Vector3(-40.0, 0.0, 0.0))
	var b := _proie("proie_b", Vector3(40.0, 0.0, 0.0))
	_poser_energie(a, float(_config.capacite_energie))
	_poser_energie(b, float(_config.capacite_energie))
	var etat := _etat_avec([a, b])
	var vu := false
	for i in range(200):
		_avancer(etat, DELTA_TICK)
		if a.proprietes.has("gestation") or b.proprietes.has("gestation"):
			vu = true
			break
	verif.v(vu, "prerequis : une gestation doit avoir ete posee")
	verif.v(a.proprietes.has("gestation") != b.proprietes.has("gestation"),
		"accouplement.gd pose gestation SYMETRIQUEMENT -- le cablage doit en liberer UN des deux au meme tick, sinon deux enfants naissent d'un seul accouplement")
	verif.v(a.proprietes.has("gestation"),
		"la convention deterministe designe l'id le plus PETIT alphabetiquement comme porteur ('proie_a')")

	# et l'accumulateur est vide a la naissance : sans ce geste la gestation
	# serait REPOSEE au tick suivant (accouplement.gd n'oublie jamais)
	for i in range(400):
		if not _avancer(etat, DELTA_TICK).naissances.is_empty():
			break
	verif.v(a.proprietes.get("accouplement_accumulateur", {}).is_empty(),
		"l'accumulateur du porteur doit etre VIDE apres la naissance (%s obtenu)" % [a.proprietes.get("accouplement_accumulateur", {})])
	verif.v(b.proprietes.get("accouplement_accumulateur", {}).is_empty(),
		"celui du partenaire aussi -- les DEUX, jamais le seul porteur")

# ---- LA MORT (audit ligne 2) ----

func _le_predateur_meurt_de_faim_sans_proies() -> void:
	var seul := _predateur("affame", Vector3.ZERO, _biais_du_disque("predateur_chasseur"))
	var etat := _etat_avec([seul])
	var mort_vue := false
	for i in range(600):
		if not _avancer(etat, DELTA_TICK).morts.is_empty():
			mort_vue = true
			break
	verif.v(mort_vue, "un predateur sans aucune proie doit finir par mourir de faim")
	verif.v(seul.proprietes.etats_actifs.has(String(_config.etat_mort)),
		"et porter l'etat de mort du catalogue PARTAGE (%s)" % String(_config.etat_mort))
	# La mort tombe au franchissement de manque_energie > seuil (99.0), donc a
	# une reserve strictement SOUS 1.0 -- jamais exactement 0.0 : le seuil
	# precede l'epuisement, il ne coincide pas avec lui. Verrouille tel quel
	# plutot que corrige : c'est la calibration du catalogue local, elle est
	# reglable, et un test qui exigerait 0.0 pile rougirait au premier reglage.
	verif.v(Banc.energie(seul, _config) < 1.0 and Banc.energie(seul, _config) >= 0.0,
		"sa reserve doit etre SOUS le seuil de mort et jamais negative -- depense.gd la borne a 0.0 (%.3f obtenu)"
			% Banc.energie(seul, _config))

	# contre-epreuve : une proie SEULE ne meurt jamais, son cout_base est negatif
	var proie := _proie("brouteuse", Vector3.ZERO)
	_poser_energie(proie, 90.0)
	var etat_proie := _etat_avec([proie])
	_avancer_n(etat_proie, 300)
	verif.v(not Banc.est_mort(proie, _config),
		"une proie seule ne meurt jamais de faim -- cout_base NEGATIF, elle broute (patron de la jachere)")
	verif.v(is_equal_approx(Banc.energie(proie, _config), float(_config.capacite_energie)),
		"et sa reserve est PLAFONNEE a la capacite -- rien dans le coeur ne borne le haut d'une reserve (%.2f obtenu)"
			% Banc.energie(proie, _config))

func _la_proie_videe_meurt_et_laisse_un_reste() -> void:
	var proie := _proie("p", Vector3.ZERO)
	var predateur := _predateur("chasseur", Vector3(20.0, 0.0, 0.0), _biais_du_disque("predateur_chasseur"))
	_poser_energie(proie, 20.0)
	var etat := _etat_avec([proie, predateur])
	var morts: Array = []
	for i in range(200):
		var r := _avancer(etat, DELTA_TICK)
		if not r.morts.is_empty():
			morts = r.morts
			break
	verif.v(morts.has("p"), "la proie videe par consommer.gd doit mourir (morts=%s)" % [morts])
	verif.v(etat.restes.size() == 1, "et laisser EXACTEMENT un reste (%d obtenu)" % etat.restes.size())
	var masse_reste: float = float(etat.restes[0].proprietes.get("masse", 0.0))
	var attendu: float = float(_config.types_locaux.proie_animal.masse) * float(_config.produit_reste.rendement)
	verif.v(is_equal_approx(masse_reste, attendu),
		"la masse du reste doit valoir rendement x masse du mort, calculee par produit.gd (%.3f attendu, %.3f obtenu)"
			% [attendu, masse_reste])

func _les_morts_sont_retirees_du_monde() -> void:
	var proie := _proie("p", Vector3.ZERO)
	var predateur := _predateur("chasseur", Vector3(20.0, 0.0, 0.0), _biais_du_disque("predateur_chasseur"))
	_poser_energie(proie, 20.0)
	var etat := _etat_avec([proie, predateur])
	verif.v(_present(etat, "p"), "prerequis : la proie est dans le Monde au depart")
	for i in range(200):
		if not _avancer(etat, DELTA_TICK).morts.is_empty():
			break
	verif.v(not _present(etat, "p"),
		"une fois morte, la proie doit AVOIR QUITTE le Monde -- monde.gd n'a aucune fonction de retrait, le Monde est RECONSTRUIT du neant")
	verif.v(_present(etat, "chasseur"),
		"et le survivant doit y avoir ete re-ajoute PAR REFERENCE, jamais recopie")
	var ids: Array = []
	for animal in etat.animaux:
		ids.append(String(animal.id))
	verif.v(not ids.has("p"), "le mort doit aussi sortir de la liste animee (ids=%s)" % [ids])

func _les_naissances_ajoutent_des_entites_au_monde() -> void:
	var a := _proie("proie_a", Vector3(-40.0, 0.0, 0.0))
	var b := _proie("proie_b", Vector3(40.0, 0.0, 0.0))
	_poser_energie(a, float(_config.capacite_energie))
	_poser_energie(b, float(_config.capacite_energie))
	var etat := _etat_avec([a, b])
	var ne := ""
	for i in range(400):
		var r := _avancer(etat, DELTA_TICK)
		if not r.naissances.is_empty():
			ne = String(r.naissances[0].id)
			break
	verif.v(ne != "", "prerequis : une naissance doit avoir eu lieu")
	verif.v(_present(etat, ne), "l'enfant doit etre DANS le Monde (Objet.fabriquer + Monde.ajouter)")
	verif.v(etat.animaux.size() == 3, "et dans la liste animee (%d animaux)" % etat.animaux.size())
	var enfant := Banc._animal_par_id(etat.animaux, ne)
	verif.v(is_equal_approx(float(enfant.proprietes.age), 0.0) or float(enfant.proprietes.age) < 1.0,
		"un enfant nait a l'age 0.0, jamais a l'age de depart des fondateurs (%.3f obtenu)" % float(enfant.proprietes.age))
	verif.v(Banc.est_juvenile(enfant),
		"il demarre JUVENILE (stade '%s') -- c'est ce delai de maturite qui dephase le cycle" % String(enfant.proprietes.stade))
	verif.v(not enfant.proprietes.stades_fertiles.has(String(enfant.proprietes.stade)),
		"et il n'est donc PAS fertile a la naissance")
	verif.v(not a.proprietes.has("gestation"),
		"la gestation doit avoir ete RETIREE de la porteuse par le cablage -- gestation.gd ne le fait jamais lui-meme")
	verif.v(Banc.energie(a, _config) < float(_config.capacite_energie),
		"et la reproduction doit avoir COUTE de l'energie a la porteuse (%.2f)" % Banc.energie(a, _config))

# ---- L'AGRESSION (audit ligne 6) ----

# Un chasseur affame, SEUL : pas d'intrus (densite 0), pas de petits
# (proximite 0). Seule la faim peut gagner.
func _l_agression_bifurque_vers_la_faim() -> void:
	var chasseur := _predateur("chasseur", Vector3.ZERO, _biais_du_disque("predateur_chasseur"))
	_poser_energie(chasseur, 30.0)
	var proie := _proie("p", Vector3(400.0, 0.0, 0.0))
	var etat := _etat_avec([chasseur, proie])
	var sortie := ""
	for i in range(200):
		var r := _avancer(etat, DELTA_TICK)
		var e := _rapport_de(r, "chasseur")
		if not e.is_empty() and String(e.sortie) != "":
			sortie = String(e.sortie)
			break
	verif.v(sortie == "agressif_faim",
		"un chasseur affame et seul doit bifurquer vers 'agressif_faim' (obtenu '%s')" % sortie)
	verif.v(chasseur.proprietes.etats_actifs.has("agressif_faim"), "l'etat doit etre pose dans etats_actifs")

# Un territorial RASSASIE (urgence de faim nulle) entoure d'intrus : seule la
# densite peut gagner.
func _l_agression_bifurque_vers_le_territoire() -> void:
	var territorial := _predateur("territorial", Vector3.ZERO, _biais_du_disque("predateur_territorial"))
	_poser_energie(territorial, float(_config.capacite_energie))
	var intrus: Array = [territorial]
	for i in range(3):
		var autre := _predateur("intrus_%d" % i, Vector3(80.0 + 30.0 * i, 40.0, 0.0), {})
		_poser_energie(autre, float(_config.capacite_energie))
		intrus.append(autre)
	verif.v(is_equal_approx(Banc.urgence_faim(territorial, _config), 0.0)
			or Banc.urgence_faim(territorial, _config) < 0.05,
		"prerequis : un territorial rassasie n'a presque aucune urgence de faim")
	verif.v(Banc.densite_intrus(territorial, intrus, _config) > 0.0,
		"prerequis : trois intrus a portee doivent donner une densite non nulle")
	var etat := _etat_avec(intrus)
	var sortie := ""
	for i in range(200):
		var e := _rapport_de(_avancer(etat, DELTA_TICK), "territorial")
		if not e.is_empty() and String(e.sortie) != "":
			sortie = String(e.sortie)
			break
	verif.v(sortie == "agressif_territoire",
		"un territorial rassasie entoure d'intrus doit bifurquer vers 'agressif_territoire' (obtenu '%s')" % sortie)

# Un protecteur RASSASIE, avec un juvenile de son espece a portee ET un intrus
# proche : la cause « petits » doit battre la cause « territoire », alors que
# les deux sont actives en meme temps.
func _l_agression_bifurque_vers_les_petits() -> void:
	var protecteur := _predateur("protecteur", Vector3.ZERO, _biais_du_disque("predateur_protecteur"))
	_poser_energie(protecteur, float(_config.capacite_energie))
	var petit := _predateur("petit", Vector3(60.0, 0.0, 0.0), {})
	petit.proprietes["age"] = 0.0
	petit.proprietes["stade"] = "nouveau_ne"
	_poser_energie(petit, float(_config.capacite_energie))
	var intrus := _predateur("intrus", Vector3(120.0, 0.0, 0.0), {})
	_poser_energie(intrus, float(_config.capacite_energie))
	var animaux := [protecteur, petit, intrus]
	verif.v(Banc.est_juvenile(petit), "prerequis : le petit doit etre juvenile")
	verif.v(Banc.proximite_menace_petits(protecteur, animaux, _config) > 0.0,
		"prerequis : un petit a portee ET un intrus proche donnent une proximite de menace non nulle")

	var contributions := Banc.contributions_agression(protecteur, animaux, _config)
	verif.v(float(contributions.agressif_petits) > float(contributions.agressif_territoire),
		"la contribution 'petits' doit DEPASSER la contribution 'territoire' pour ce biais (%.3f contre %.3f)"
			% [float(contributions.agressif_petits), float(contributions.agressif_territoire)])

	var etat := _etat_avec(animaux)
	var sortie := ""
	for i in range(200):
		var e := _rapport_de(_avancer(etat, DELTA_TICK), "protecteur")
		if not e.is_empty() and String(e.sortie) != "":
			sortie = String(e.sortie)
			break
	verif.v(sortie == "agressif_petits",
		"le protecteur doit bifurquer vers 'agressif_petits' (obtenu '%s')" % sortie)

	# et SANS petit a portee, la cause tombe a zero EXACTEMENT : elle ne peut
	# gagner qu'apres une naissance, et c'est le sujet.
	verif.v(is_equal_approx(Banc.proximite_menace_petits(protecteur, [protecteur, intrus], _config), 0.0),
		"sans aucun juvenile de la meme espece a portee, la cause 'petits' vaut exactement 0.0")

# LE CŒUR DE LA LIGNE 6 : MEME situation, MEMES grandeurs, seuls les biais
# different -- et les sorties different. C'est la doctrine « Les archetypes
# n'existent pas » rendue litterale.
func _le_biais_compose_fait_gagner_la_cause_dominante() -> void:
	var chasseur := _predateur("chasseur", Vector3.ZERO, _biais_du_disque("predateur_chasseur"))
	var territorial := _predateur("territorial", Vector3(10.0, 0.0, 0.0), _biais_du_disque("predateur_territorial"))
	_poser_energie(chasseur, 50.0)
	_poser_energie(territorial, 50.0)
	var animaux := [chasseur, territorial]
	for i in range(3):
		var autre := _predateur("intrus_%d" % i, Vector3(60.0 + 20.0 * i, 60.0, 0.0), {})
		_poser_energie(autre, 50.0)
		animaux.append(autre)

	# Le miroir plat doit exister AVANT toute lecture d'urgence : c'est le
	# cablage qui l'ecrit, a chaque tick, et jamais un mecanisme du coeur --
	# lire contributions_agression sur un animal jamais avance rendrait une
	# urgence de faim nulle (defaut reel trouve au premier lancement du test).
	for animal in animaux:
		Banc.poser_manque_energie(animal, _config)
	var c_chasseur := Banc.contributions_agression(chasseur, animaux, _config)
	var c_territorial := Banc.contributions_agression(territorial, animaux, _config)
	verif.v(is_equal_approx(Banc.urgence_faim(chasseur, _config), Banc.urgence_faim(territorial, _config)),
		"prerequis : les deux subissent EXACTEMENT la meme urgence de faim")
	verif.v(float(c_chasseur.agressif_faim) > float(c_chasseur.agressif_territoire),
		"chez le chasseur, la faim doit dominer (%.3f contre %.3f)"
			% [float(c_chasseur.agressif_faim), float(c_chasseur.agressif_territoire)])
	verif.v(float(c_territorial.agressif_territoire) > float(c_territorial.agressif_faim),
		"chez le territorial, MEMES grandeurs, c'est le territoire qui domine (%.3f contre %.3f)"
			% [float(c_territorial.agressif_territoire), float(c_territorial.agressif_faim)])

	var etat := _etat_avec(animaux)
	var sorties: Dictionary = {}
	for i in range(300):
		for e in _avancer(etat, DELTA_TICK).animaux:
			var id := String(e.id)
			if not sorties.has(id) and String(e.sortie) != "":
				sorties[id] = String(e.sortie)
	verif.v(String(sorties.get("chasseur", "")) == "agressif_faim",
		"le chasseur doit bifurquer vers la faim (obtenu '%s')" % String(sorties.get("chasseur", "")))
	verif.v(String(sorties.get("territorial", "")) == "agressif_territoire",
		"le territorial, dans la MEME scene, vers le territoire (obtenu '%s')" % String(sorties.get("territorial", "")))

func _aucune_bifurcation_sans_cause() -> void:
	var rassasie := _predateur("rassasie", Vector3.ZERO, _biais_du_disque("predateur_chasseur"))
	_poser_energie(rassasie, float(_config.capacite_energie))
	var etat := _etat_avec([rassasie])
	# CINQ ticks, pas cent : un predateur DEPENSE 3.2/s, il a donc reellement
	# faim au bout de quelques secondes et sa bifurcation vers 'agressif_faim'
	# est alors JUSTE (defaut de test trouve au premier lancement -- le cablage
	# n'avait rien de faux). Ce que ce cas verrouille est le point de depart :
	# reserve pleine, aucune cause, aucune sortie.
	var r := _avancer_n(etat, 5)
	var e := _rapport_de(r, "rassasie")
	verif.v(String(e.sortie) == "",
		"un predateur rassasie et seul n'a AUCUNE cause -- aucune sortie ne doit etre active (obtenu '%s')" % String(e.sortie))
	verif.v(not rassasie.proprietes.get(String(_config.nom_marqueur_agression), false),
		"et le marqueur de charge.gd ne doit jamais avoir ete pose")
	# une proie ne porte aucun canal d'agression : elle ne bifurque JAMAIS
	var proie := _proie("p", Vector3.ZERO)
	var etat_proie := _etat_avec([proie])
	var rp := _avancer_n(etat_proie, 50)
	verif.v(String(_rapport_de(rp, "p").sortie) == "",
		"une proie ne porte aucun canal d'agression -- elle ne bifurque jamais")

func _la_deformation_monte_la_saillance_de_la_cible() -> void:
	var chasseur := _predateur("chasseur", Vector3.ZERO, _biais_du_disque("predateur_chasseur"))
	_poser_energie(chasseur, 20.0)
	var proie := _proie("p", Vector3(300.0, 0.0, 0.0))
	var etat := _etat_avec([chasseur, proie])
	_avancer_n(etat, 5)
	var biais_debut := Banc.biais_de_sortie(chasseur, "agressif_faim", _config, _deformations)
	_avancer_n(etat, 60)
	var biais_haut := Banc.biais_de_sortie(chasseur, "agressif_faim", _config, _deformations)
	verif.v(biais_haut > biais_debut,
		"la deformation 'agression_faim' (sens 'monte') doit faire monter le biais sur la propriete de la proie (%.3f -> %.3f)"
			% [biais_debut, biais_haut])
	verif.v(biais_haut <= float(_config.plafond_biais_agression) + 0.5,
		"et le PLAFOND est au cablage -- deformation.gd n'a aucun equilibre naturel (%.3f pour un plafond de %.3f)"
			% [biais_haut, float(_config.plafond_biais_agression)])

	# la menace disparue, le biais REDESCEND : avancer() est appele a chaque
	# tick, sortie active ou non.
	_poser_energie(chasseur, float(_config.capacite_energie))
	var etat_seul := _etat_avec([chasseur])
	_avancer_n(etat_seul, 150)
	verif.v(Banc.biais_de_sortie(chasseur, "agressif_faim", _config, _deformations) < biais_haut,
		"le biais doit REDESCENDRE quand la cause disparait")

# ---- LES DEUX ECRIVAINS UNIQUES (audit, constat C) ----

func _un_seul_ecrivain_pour_surcout_action_et_poids_verbes() -> void:
	var predateur := _predateur("chasseur", Vector3.ZERO, _biais_du_disque("predateur_chasseur"))
	var proie := _proie("p", Vector3(200.0, 0.0, 0.0))

	# poids_verbes : la table de l'espece, EN ENTIER, jamais un melange
	Banc.poser_poids_verbes(predateur, _config)
	Banc.poser_poids_verbes(proie, _config)
	verif.v(predateur.proprietes.poids_verbes == _config.poids_verbes_predateur,
		"poids_verbes du predateur doit etre EXACTEMENT la table de son espece (%s obtenu)" % [predateur.proprietes.poids_verbes])
	verif.v(proie.proprietes.poids_verbes == _config.poids_verbes_proie,
		"celui de la proie, exactement la sienne (%s obtenu)" % [proie.proprietes.poids_verbes])
	# une table polluee a la main est REECRITE en entier au tick suivant
	predateur.proprietes.poids_verbes["parasite"] = 9.0
	Banc.poser_poids_verbes(predateur, _config)
	verif.v(not predateur.proprietes.poids_verbes.has("parasite"),
		"la table est reecrite EN ENTIER depuis la donnee -- jamais un increment sur la precedente")

	# surcout_action : les deux contributions sont sommees et ecrites d'un seul
	# geste, la decomposition rendue pour le label
	var d0 := Banc.poser_surcout_action(predateur, false, false, _config)
	verif.v(is_equal_approx(d0.total, 0.0), "immobile et calme : surcout exactement nul (%.3f)" % d0.total)
	var d1 := Banc.poser_surcout_action(predateur, true, false, _config)
	verif.v(is_equal_approx(d1.total, float(_config.surcout_mouvement)),
		"en mouvement seul : exactement surcout_mouvement (%.3f attendu, %.3f obtenu)" % [float(_config.surcout_mouvement), d1.total])
	var d2 := Banc.poser_surcout_action(predateur, true, true, _config)
	verif.v(is_equal_approx(d2.total, float(_config.surcout_mouvement) + float(_config.surcout_agression)),
		"en mouvement ET agressif : la SOMME des deux, jamais l'une qui ecrase l'autre (%.3f attendu, %.3f obtenu)"
			% [float(_config.surcout_mouvement) + float(_config.surcout_agression), d2.total])
	verif.v(is_equal_approx(
			float(predateur.proprietes.reserves[String(_config.nom_reserve_energie)].surcout_action), d2.total),
		"et c'est bien CE nombre qui est ecrit sur le canal que depense.gd lit")
	var d3 := Banc.poser_surcout_action(predateur, false, false, _config)
	verif.v(is_equal_approx(d3.total, 0.0),
		"revenu au repos, le surcout retombe a zero -- ecriture COMPLETE a chaque appel, jamais un residu (%.3f)" % d3.total)

# ---- LE GATE DE MOUVEMENT (decision (a) du banc) ----

func _le_gate_de_mouvement_tient_le_troupeau() -> void:
	# deux proies seules : elles se percoivent, resolvent 's_eloigner' l'une sur
	# l'autre (memes verbes, un seul poids_verbes) -- et NE BOUGENT PAS.
	var a := _proie("proie_a", Vector3(-60.0, 0.0, 0.0))
	var b := _proie("proie_b", Vector3(60.0, 0.0, 0.0))
	var etat := _etat_avec([a, b])
	var depart_a: Vector3 = a.position
	var r := _avancer_n(etat, 60)
	verif.v(a.position == depart_a,
		"une proie ne doit PAS fuir sa congenere -- sans ce gate le troupeau se disperserait et ne s'accouplerait jamais")
	var e := _rapport_de(r, "proie_a")
	verif.v(String(e.geste) == "",
		"le geste doit etre vide : la decision existe, le mouvement est refuse (geste '%s')" % String(e.geste))

	# le MEME poids_verbes, mais un predateur en face : elle fuit reellement.
	var proie := _proie("proie_a", Vector3.ZERO)
	var predateur := _predateur("chasseur", Vector3(150.0, 0.0, 0.0), _biais_du_disque("predateur_chasseur"))
	_poser_energie(predateur, float(_config.capacite_energie))
	var etat2 := _etat_avec([proie, predateur])
	# Mesure contre la position INITIALE du predateur, jamais contre sa position
	# vivante : il POURSUIT et il est plus rapide (124 contre 108), donc la
	# distance entre les deux se REDUIT meme quand la proie fuit reellement --
	# defaut de mesure trouve au premier lancement du test, pas un defaut du
	# cablage. Ce qu'on veut prouver est que la proie s'ecarte du DANGER, pas
	# qu'elle le distance.
	var depart_predateur: Vector3 = predateur.position
	var distance_avant: float = proie.position.distance_to(depart_predateur)
	var fuite_vue := false
	for i in range(60):
		if String(_rapport_de(_avancer(etat2, DELTA_TICK), "proie_a").geste) == "fuit":
			fuite_vue = true
			break
	_avancer_n(etat2, 20)
	verif.v(fuite_vue, "la MEME proie, MEME poids_verbes, doit FUIR un predateur (le gate laisse passer)")
	verif.v(proie.position.distance_to(depart_predateur) > distance_avant,
		"et s'ecarter reellement du point d'ou la menace venait (%.1f -> %.1f)"
			% [distance_avant, proie.position.distance_to(depart_predateur)])

# ---- L'OSCILLATION (audit ligne 5) ----

# Les cycles ne sont ecrits NULLE PART : ils emergent du couplage. On ne teste
# donc pas une forme de courbe (ce serait recopier la calibration), mais la
# PROPRIETE qui les definit -- les deux populations bougent, et il existe des
# instants ou elles bougent EN SENS CONTRAIRE.
func _la_population_oscille() -> void:
	var etat := Banc.etat_initial(_config, _types)
	var proies: Array = []
	var predateurs: Array = []
	for i in range(600):
		var r := _avancer(etat, DELTA_TICK)
		proies.append(int(r.proies))
		predateurs.append(int(r.predateurs))

	var min_proies: int = proies[0]
	var max_proies: int = proies[0]
	var min_pred: int = predateurs[0]
	var max_pred: int = predateurs[0]
	for i in range(proies.size()):
		min_proies = min(min_proies, proies[i])
		max_proies = max(max_proies, proies[i])
		min_pred = min(min_pred, predateurs[i])
		max_pred = max(max_pred, predateurs[i])
	verif.v(max_proies > min_proies,
		"la population de proies doit VARIER sur 60 s (min %d, max %d)" % [min_proies, max_proies])
	verif.v(max_pred > min_pred,
		"celle des predateurs aussi (min %d, max %d)" % [min_pred, max_pred])

	var contraires := 0
	var pas := 50
	for i in range(pas, proies.size()):
		var d_proies: int = proies[i] - proies[i - pas]
		var d_pred: int = predateurs[i] - predateurs[i - pas]
		if (d_proies > 0 and d_pred < 0) or (d_proies < 0 and d_pred > 0):
			contraires += 1
	if contraires <= 0:
		# La serie ECHANTILLONNEE, imprimee seulement quand le cas rougit : sans
		# elle, « 0 intervalle » ne dit pas SI la population s'est eteinte, a
		# explose ou est restee plate -- trois causes qui n'ont pas la meme
		# correction (leçon de banc_maladie, dont le seuil ne franchissait jamais
		# rien pendant que le test restait vert).
		var serie: Array = []
		for i in range(0, proies.size(), 50):
			serie.append("%d/%d" % [proies[i], predateurs[i]])
		print("DIAGNOSTIC oscillation (proies/predateurs toutes les 5 s) : %s" % " ".join(serie))
	verif.v(contraires > 0,
		"il doit exister des intervalles ou les deux populations bougent EN SENS CONTRAIRE -- c'est ca, le couplage proie-predateur (%d intervalles sur %d)"
			% [contraires, proies.size() - pas])
	verif.v(int(etat.naissances) > 0 and int(etat.morts) > 0,
		"et il doit y avoir eu des naissances ET des morts (%d / %d)" % [int(etat.naissances), int(etat.morts)])

# ---- LA CONFIG REELLE DU DISQUE ----

# Rejoue data/banc_predation.json EN ENTIER. Sans ce cas, tout ce fichier
# resterait VERT alors que le banc lance a l'ecran ne produirait ni repas, ni
# naissance, ni mort -- exactement le trou trouve sur banc_maladie.
func _config_reelle_du_disque_fait_vivre_la_population() -> void:
	var etat := Banc.etat_initial(_config, _types)
	var comptes := Banc.effectifs(etat.animaux, _config)
	verif.v(comptes.proies == 8 and comptes.predateurs == 3,
		"la config du disque doit poser 8 proies et 3 predateurs (obtenu %d/%d)" % [comptes.proies, comptes.predateurs])
	for animal in etat.animaux:
		verif.v(not Banc.est_juvenile(animal),
			"tous les fondateurs demarrent ADULTES (age_depart) -- '%s' est au stade '%s'"
				% [String(animal.id), String(animal.proprietes.get("stade", ""))])

	var repas_vus := 0
	var sorties: Dictionary = {}
	var naissances := 0
	var morts := 0
	for i in range(600):
		var r := _avancer(etat, DELTA_TICK)
		repas_vus += r.repas.size()
		naissances += r.naissances.size()
		morts += r.morts.size()
		for e in r.animaux:
			if String(e.sortie) != "":
				sorties[String(e.sortie)] = int(sorties.get(String(e.sortie), 0)) + 1
	verif.v(repas_vus > 0, "la config du disque doit produire des REPAS (%d)" % repas_vus)
	verif.v(naissances > 0, "des NAISSANCES (%d)" % naissances)
	verif.v(morts > 0, "et des MORTS (%d)" % morts)
	verif.v(sorties.has("agressif_faim"),
		"et au moins une bifurcation vers 'agressif_faim' -- un predateur qui ne chasse jamais ne mangerait pas (sorties vues : %s)" % [sorties.keys()])
	verif.v(etat.restes.size() > 0, "des restes doivent avoir ete fabriques par produit.gd (%d)" % etat.restes.size())
	verif.v(etat.restes.size() <= int(_config.restes_max),
		"et leur nombre reste borne par restes_max (%d pour un plafond de %d)" % [etat.restes.size(), int(_config.restes_max)])
	verif.v(etat.monde.choses.size() == etat.animaux.size(),
		"le Monde et la liste animee doivent rester d'accord a tout instant (%d contre %d)"
			% [etat.monde.choses.size(), etat.animaux.size()])
