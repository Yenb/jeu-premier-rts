extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_genetique.gd
#
# CHEMIN REEL (meme regime que test_banc_deformation.gd/test_banc_charge.gd,
# PAS hors domaine -- ce banc fabrique de VRAIS colons Orion) : tout est lu
# sur disque (data/types.json, data/banc_genetique.json, data/canaux.json,
# data/menaces.json, data/profils_saillance.json, data/types_choses.json,
# data/orientations.json, data/transformations.json), jamais une fixture
# inventee. Verrouille que ExpressionGenetique.exprimer/appliquer, cablees
# par banc_genetique.gd, produisent bien un TRADE-OFF observable : le vif
# arrive avant le moyen, le moyen avant l'endurant ; l'endurant garde plus
# de reserve que le moyen, le moyen plus que le vif, a tout instant.
#
# CONSTAT GEOMETRIQUE (voir scripts/banc_genetique.gd, en-tete) : ce fichier
# NE VERROUILLE PAS un ordre de PERCEPTION distinct entre les trois colons
# -- le feu (400 unites) est a portee de vue des trois profils (1200 a
# 2000 unites), les trois le percoivent donc au meme premier tick. Seuls
# l'ARRIVEE (pilotee par vitesse) et l'EPUISEMENT (pilote par cout_base)
# sont mecaniquement ordonnes, et ce sont eux qui sont verrouilles ici.

const BancGenetique = preload("res://scripts/banc_genetique.gd")
const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Depense = preload("res://scripts/depense.gd")
const Extinction = preload("res://scripts/extinction.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA_TICK := 0.1

func _init() -> void:
	var v := Verif.new()
	_fabrication_reelle_module_vitesse_portee_cout_base(v)
	_moyen_reste_au_defaut_du_type_sans_gene(v)
	_ordre_arrivee_vif_avant_moyen_avant_endurant(v)
	_ordre_reserve_endurant_superieur_a_moyen_superieur_a_vif_a_tout_instant(v)
	_percoit_le_feu_des_que_le_feu_est_perceptible(v)
	_est_arrive_sur_le_feu_a_portee_de_travail_seulement(v)
	_reserve_energie_epuisee_vrai_sous_zero_jamais_avant(v)
	_extinction_reelle_eteint_le_feu_une_fois_le_travail_accompli(v)
	_resumabilite_json_stricte(v)
	_couleurs_lisent_le_nom_pose_jamais_le_defaut(v)
	_verifier_evenements_imprime_une_fois_et_ne_regresse_jamais(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_genetique.gd cable ExpressionGenetique sur trois colons reels -- " +
			"le vif arrive en premier et s'epuise en premier, l'endurant arrive en dernier " +
			"et dure le plus longtemps, aucun ne domine")
		quit(0)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

# Reproduit EXACTEMENT le chargement de banc_genetique.gd:_ready -- lu sur
# disque, jamais une fixture locale.
func _catalogues() -> Dictionary:
	var donnees := _charger_json("res://data/banc_genetique.json")
	var catalogue_types: Dictionary = donnees.get("types", {}).duplicate(true)
	var types_partages := _charger_json("res://data/types.json")
	catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	catalogue_types["percevant"] = types_partages.get("percevant", {})
	catalogue_types["agent"] = types_partages.get("agent", {})
	catalogue_types["colon"] = types_partages.get("colon", {})
	var donnees_transformations := _charger_json("res://data/transformations.json")
	return {
		"donnees": donnees,
		"types": catalogue_types,
		"canaux": _charger_json("res://data/canaux.json"),
		"menaces": _charger_json("res://data/menaces.json"),
		"profils_saillance": _charger_json("res://data/profils_saillance.json"),
		"actions": _charger_json("res://data/types_choses.json"),
		"orientations": _charger_json("res://data/orientations.json"),
		"transformations": donnees_transformations.get("transformations", {}),
		"deformations": _charger_json("res://data/deformations.json"),
	}

func _fabriquer_trois(cat: Dictionary) -> Dictionary:
	var declarations: Dictionary = cat.donnees.get("colons", {})
	var reserve_initiale: float = cat.donnees.get("reserve_energie_initiale", 100.0)
	var catalogue_genes: Dictionary = cat.donnees.get("catalogue_genes", {})
	return {
		"vif": BancGenetique._fabriquer_colon_genetique("vif", declarations.vif, cat.types, catalogue_genes, reserve_initiale),
		"moyen": BancGenetique._fabriquer_colon_genetique("moyen", declarations.moyen, cat.types, catalogue_genes, reserve_initiale),
		"endurant": BancGenetique._fabriquer_colon_genetique("endurant", declarations.endurant, cat.types, catalogue_genes, reserve_initiale),
	}

# Feu en FIXTURE LOCALE au test (voir banc_genetique.gd, en-tete : depuis
# la correction "clic gauche pose un feu", data/banc_genetique.json ne
# porte plus de position_feu -- le banc n'en fabrique plus au demarrage).
# Position choisie a portee de vue des trois profils (1200 a 2000 unites),
# pour que l'ordre d'ARRIVEE/EPUISEMENT reste deterministe -- ce fichier ne
# teste jamais un ordre de PERCEPTION distinct, voir banc_genetique.gd.
const POSITION_FEU_TEST := Vector3(0.0, 0.0, 0.0)

func _fabriquer_feu(cat: Dictionary) -> Dictionary:
	return Objet.fabriquer("feu_0", "feu", POSITION_FEU_TEST, cat.types)

func _fabrication_reelle_module_vitesse_portee_cout_base(v) -> void:
	var cat := _catalogues()
	var colons := _fabriquer_trois(cat)
	var vif: Dictionary = colons.vif
	var moyen: Dictionary = colons.moyen
	var endurant: Dictionary = colons.endurant
	v.v(vif.proprietes.vitesse > moyen.proprietes.vitesse and moyen.proprietes.vitesse > endurant.proprietes.vitesse,
		"vitesse doit strictement decroitre vif > moyen > endurant")
	v.v(vif.proprietes.canaux_config.vue.portee > moyen.proprietes.canaux_config.vue.portee
		and moyen.proprietes.canaux_config.vue.portee > endurant.proprietes.canaux_config.vue.portee,
		"portee de vue doit strictement decroitre vif > moyen > endurant")
	v.v(vif.proprietes.reserves.energie.cout_base > moyen.proprietes.reserves.energie.cout_base
		and moyen.proprietes.reserves.energie.cout_base > endurant.proprietes.reserves.energie.cout_base,
		"cout_base d'energie doit strictement decroitre vif > moyen > endurant (vif consomme le plus)")
	# Formule exacte : base (data/types.json:colon) + somme(alleles) * poids (data/banc_genetique.json)
	var gene: Dictionary = cat.donnees.catalogue_genes.vivacite
	var poids_vitesse: float = gene.cibles[1].poids
	var base_vitesse: float = cat.types.colon.vitesse
	v.v(is_equal_approx(vif.proprietes.vitesse, base_vitesse + 2.0 * poids_vitesse),
		"vitesse du vif doit suivre exactement base + somme(alleles) * poids")
	v.v(is_equal_approx(endurant.proprietes.vitesse, base_vitesse - 2.0 * poids_vitesse),
		"vitesse de l'endurant doit suivre exactement base - somme(alleles) * poids")

func _moyen_reste_au_defaut_du_type_sans_gene(v) -> void:
	var cat := _catalogues()
	var colons := _fabriquer_trois(cat)
	var moyen: Dictionary = colons.moyen
	v.v(moyen.proprietes.vitesse == cat.types.colon.vitesse,
		"moyen (alleles [0,0]) doit rester EXACTEMENT a la vitesse par defaut du type, aucun effet du gene")
	v.v(moyen.proprietes.canaux_config.vue.portee == cat.types.colon.canaux_config.vue.portee,
		"moyen doit rester exactement a la portee de vue par defaut du type")
	v.v(moyen.proprietes.reserves.energie.cout_base == cat.types.dynamique.reserves.energie.cout_base,
		"moyen doit rester exactement au cout_base par defaut du paquet dynamique")

# Simule le pipeline complet (agir_et_deplacer) tick par tick pour les
# trois colons a la fois, jusqu'a ce que chacun soit arrive -- rend le
# temps d'arrivee de chacun, jamais suppose a l'avance.
func _simuler_jusqu_a_arrivee(colons: Dictionary, monde, cat: Dictionary, feu: Dictionary, max_ticks: int) -> Dictionary:
	var arrivees: Dictionary = {}
	var temps := 0.0
	for i in range(max_ticks):
		temps += DELTA_TICK
		for nom in colons:
			if arrivees.has(nom):
				continue
			var colon: Dictionary = colons[nom]
			BancGenetique.agir_et_deplacer(colon, monde, cat.canaux, cat.menaces, cat.profils_saillance, cat.deformations, cat.actions, cat.orientations, DELTA_TICK)
			if BancGenetique._est_arrive_sur_le_feu(colon.position, feu, cat.transformations):
				arrivees[nom] = temps
		if arrivees.size() == colons.size():
			break
	return arrivees

func _ordre_arrivee_vif_avant_moyen_avant_endurant(v) -> void:
	var cat := _catalogues()
	var colons := _fabriquer_trois(cat)
	var feu := _fabriquer_feu(cat)
	var monde := Monde.new()
	monde.ajouter(feu, "feu", feu.position)
	for nom in colons:
		monde.ajouter(colons[nom], "colon", colons[nom].position)
	var arrivees := _simuler_jusqu_a_arrivee(colons, monde, cat, feu, 200)
	v.v(arrivees.size() == 3, "les trois colons doivent finir par arriver sur le feu (memes couches, meme catalogue_actions)")
	v.v(arrivees.vif < arrivees.moyen, "le vif (vitesse la plus haute) doit arriver strictement avant le moyen")
	v.v(arrivees.moyen < arrivees.endurant, "le moyen doit arriver strictement avant l'endurant (vitesse la plus basse)")

func _ordre_reserve_endurant_superieur_a_moyen_superieur_a_vif_a_tout_instant(v) -> void:
	var cat := _catalogues()
	var colons := _fabriquer_trois(cat)
	var objets: Array = [colons.vif, colons.moyen, colons.endurant]
	var toujours_ordonne := true
	for i in range(50):
		Depense.avancer(objets, DELTA_TICK, {})
		var e_vif: float = colons.vif.proprietes.reserves.energie.reserve
		var e_moyen: float = colons.moyen.proprietes.reserves.energie.reserve
		var e_endurant: float = colons.endurant.proprietes.reserves.energie.reserve
		if not (e_endurant > e_moyen and e_moyen > e_vif):
			toujours_ordonne = false
			break
	v.v(toujours_ordonne,
		"a CHAQUE tick, la reserve d'energie doit rester strictement ordonnee endurant > moyen > vif")

func _percoit_le_feu_des_que_le_feu_est_perceptible(v) -> void:
	var cat := _catalogues()
	var colons := _fabriquer_trois(cat)
	var feu := _fabriquer_feu(cat)
	var monde := Monde.new()
	monde.ajouter(feu, "feu", feu.position)
	monde.ajouter(colons.endurant, "colon", colons.endurant.position)
	var Perception = load("res://scripts/perception.gd")
	var perceptions: Array = Perception.percevoir(colons.endurant, monde, cat.canaux)
	v.v(BancGenetique._percoit_declencheur(perceptions, "brule"),
		"le feu (au centre, bien en-deca de la plus courte portee de vue, 1200) doit etre percu")
	v.v(not BancGenetique._percoit_declencheur(perceptions, "declencheur_inexistant"),
		"une propriete absente de toute chose percue ne doit jamais etre trouvee")

func _est_arrive_sur_le_feu_a_portee_de_travail_seulement(v) -> void:
	var cat := _catalogues()
	var feu := _fabriquer_feu(cat)
	v.v(not BancGenetique._est_arrive_sur_le_feu(Vector3(400.0, 0.0, 0.0), feu, cat.transformations),
		"a 400 unites (hors portee_travail 25.0), pas encore arrive")
	v.v(BancGenetique._est_arrive_sur_le_feu(Vector3(10.0, 0.0, 0.0), feu, cat.transformations),
		"a 10 unites (dans portee_travail 25.0), arrive")

func _reserve_energie_epuisee_vrai_sous_zero_jamais_avant(v) -> void:
	var colon := {"proprietes": {"reserves": {"energie": {"reserve": 0.5}}}}
	v.v(not BancGenetique._reserve_energie_epuisee(colon), "une reserve strictement positive n'est jamais epuisee")
	colon.proprietes.reserves.energie.reserve = 0.0
	v.v(BancGenetique._reserve_energie_epuisee(colon), "une reserve exactement a 0.0 est epuisee")
	colon.proprietes.reserves.energie.reserve = -3.0
	v.v(BancGenetique._reserve_energie_epuisee(colon), "une reserve negative (jamais bornee, voir depense.gd) reste epuisee")

# Verrouille le cablage de l'extinction (correction session ulterieure) :
# un agent (colon) a portee_travail d'un feu REEL (data/banc_genetique.json:
# types.feu, fabrique via Objet.fabriquer, comme _fabriquer_feu) fait
# baisser travail_restant, et a_zero (data/transformations.json:defaut)
# retire bien brule/profil_saillance une fois le chantier accompli --
# meme contrat que test_extinction.gd, ici sur le feu LOCAL de ce banc.
func _extinction_reelle_eteint_le_feu_une_fois_le_travail_accompli(v) -> void:
	var cat := _catalogues()
	var colons := _fabriquer_trois(cat)
	var feu := _fabriquer_feu(cat)
	feu.position = colons.vif.position
	var agents := BancCommun.agents_rythme([colons.vif])
	var apres_un_tick: Array = Extinction.avancer([feu], agents, DELTA_TICK, cat.transformations)
	v.v(apres_un_tick.is_empty(), "un seul tick ne doit pas suffire a accomplir le chantier (travail_initial 3.0)")
	v.v(feu.proprietes.travail_restant < feu.proprietes.travail_initial,
		"un agent a portee_travail doit deja avoir fait baisser travail_restant apres un tick")
	var eteint := false
	for i in range(200):
		var eteints: Array = Extinction.avancer([feu], agents, DELTA_TICK, cat.transformations)
		if eteints.has(feu.id):
			eteint = true
			break
	v.v(eteint, "le feu doit finir par etre eteint (travail_restant atteint 0)")
	v.v(not feu.proprietes.has("brule"),
		"a_zero (data/transformations.json:defaut) doit retirer 'brule' une fois le chantier accompli")
	v.v(not feu.proprietes.has("profil_saillance"),
		"a_zero doit retirer 'profil_saillance' une fois le chantier accompli")
	v.v(not feu.proprietes.has("travail_restant"),
		"extinction.gd retire toujours 'travail_restant' une fois le chantier accompli, meme absent de 'retirer'")

func _resumabilite_json_stricte(v) -> void:
	var cat := _catalogues()
	var colons := _fabriquer_trois(cat)
	var vif: Dictionary = colons.vif
	Depense.avancer([vif], DELTA_TICK, {})
	var texte := JSON.stringify(vif)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	v.v(is_equal_approx(relu.proprietes.reserves.energie.reserve, vif.proprietes.reserves.energie.reserve),
		"la reserve d'energie doit survivre identique a l'aller-retour JSON")
	v.v(relu.proprietes.genes_etat.vivacite.alleles == vif.proprietes.genes_etat.vivacite.alleles,
		"genes_etat (alleles) doit survivre identique a l'aller-retour JSON")
	v.v(is_equal_approx(relu.proprietes.vitesse, vif.proprietes.vitesse),
		"la vitesse exprimee doit survivre identique a l'aller-retour JSON")

# Audit couverture 2026-08-06 : _couleur_colon/_couleur_rendu/
# _couleur_reserve/_verifier_evenements sont des fonctions INSTANCE,
# aucune appelee par un test avant cette session. Meme patron que les
# autres bancs : BancGenetique.new() nu, jamais ajoute a l'arbre.

func _couleurs_lisent_le_nom_pose_jamais_le_defaut(v) -> void:
	var b := BancGenetique.new()
	b._couleurs_colons = {"vif": [0.9, 0.2, 0.1]}
	b._couleurs_types_rendu = {"feu": [0.8, 0.3, 0.0]}
	b._couleurs_reserves = {"energie": [0.1, 0.7, 0.2]}
	v.v(b._couleur_colon("vif") == Color(0.9, 0.2, 0.1), "_couleur_colon doit rendre la couleur posee, pas le defaut blanc")
	v.v(b._couleur_colon("inconnu") == Color(1.0, 1.0, 1.0), "_couleur_colon : nom absent -> blanc par defaut")
	v.v(b._couleur_rendu("feu") == Color(0.8, 0.3, 0.0), "_couleur_rendu doit rendre la couleur posee, pas le defaut blanc")
	v.v(b._couleur_rendu("inconnu") == Color(1.0, 1.0, 1.0), "_couleur_rendu : nom absent -> blanc par defaut")
	v.v(b._couleur_reserve("energie") == Color(0.1, 0.7, 0.2), "_couleur_reserve doit rendre la couleur posee, pas le defaut blanc")
	v.v(b._couleur_reserve("inconnu") == Color(1.0, 1.0, 1.0), "_couleur_reserve : nom absent -> blanc par defaut")

# Les trois evenements (percu/arrive/epuise) ne doivent s'imprimer qu'UNE
# FOIS, au franchissement -- et ne JAMAIS regresser une fois vrais, meme si
# la condition qui les a declenches cesse d'etre vraie au tick suivant
# (perceptions videes, chose_ciblee redevenue null). Meme classe de risque
# que le defaut trouve par l'audit (un etat affiche qui ne colle plus a
# l'etat reel).
func _verifier_evenements_imprime_une_fois_et_ne_regresse_jamais(v) -> void:
	var b := BancGenetique.new()
	b._transformations = {"defaut": {"portee_travail": 10.0}}
	var colon := {
		"id": "c1", "position": Vector3.ZERO,
		"proprietes": {"reserves": {"energie": {"reserve": 50.0}}},
	}
	b._etats_impression[colon.id] = {"percu": false, "arrive": false, "epuise": false}

	b._verifier_evenements(colon, [], null)
	var etat: Dictionary = b._etats_impression[colon.id]
	v.v(not etat.percu and not etat.arrive and not etat.epuise,
		"sans feu percu, sans cible, sans reserve epuisee : aucun evenement ne doit se declencher")

	var feu := {"id": "feu_x", "position": Vector3(5, 0, 0), "proprietes": {"brule": true, "travail_restant": 3.0, "transformation": "defaut"}}
	var perceptions := [{"chose": feu, "position": feu.position}]
	b._verifier_evenements(colon, perceptions, feu)
	v.v(etat.percu, "une chose percue portant 'brule' doit poser 'percu'")
	v.v(etat.arrive, "une cible a portee_travail (distance 5 <= 10) doit poser 'arrive'")
	v.v(not etat.epuise, "reserve encore a 50.0 : 'epuise' ne doit pas se declencher")

	colon.proprietes.reserves.energie.reserve = -1.0
	b._verifier_evenements(colon, perceptions, feu)
	v.v(etat.epuise, "reserve sous zero : 'epuise' doit se declencher")

	b._verifier_evenements(colon, [], null)
	v.v(etat.percu and etat.arrive and etat.epuise,
		"une fois vrais, les trois evenements ne doivent JAMAIS regresser, meme si plus rien n'est percu/vise ce tick")
