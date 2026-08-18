extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_economie.gd
#
# Verrouille le cablage de banc_economie.gd : le portage (consommer.gd dans les
# deux sens, vitesse composee, surcout proportionnel), la fonte a DEUX produits
# (produit.gd appele deux fois sur le meme proprietes_ancien), la conservation
# GLOBALE (somme.gd, son premier appelant reel) et le seuil de rentabilite
# ABSOLU (retrait d'entrees de resultats avant dominance.gd). Les dix
# mecanismes du coeur restent INCHANGES -- ce fichier ne verrouille que le
# cablage.
#
# LA CONSERVATION EST LE CAS CENTRAL, et il porte sur une grandeur que
# somme.gd rend : la masse totale du monde. Son autre appelant du depot
# (banc_marche_competence.gd, session concurrente) lui demande une OFFRE (un
# total qui bouge) ; ici on lui demande un INVARIANT (un total dont le moindre
# ecart est un bug) -- d'ou les comparaisons a EPS plutot qu'a un ordre de
# grandeur.
#
# TROIS FAMILLES DE CAS, a ne pas confondre :
# - les cas de MECANIQUE isolent une fonction pure sur des nombres choisis
#   (vitesse a charge nulle/pleine, score de rentabilite, surcout) ;
# - les cas de CHEMIN REEL rejouent data/banc_economie.json EN ENTIER, avec les
#   vrais catalogues du disque -- sans eux, tout ce fichier resterait VERT
#   alors que le banc lance a l'ecran ne montrerait rien (c'est exactement le
#   trou qui avait laisse passer la calibration morte de banc_maladie, voir
#   docs/ETAT.md) ;
# - un cas HORS DOMAINE integral (des cueilleurs de spores sur une planete
#   inventee) : catalogue de materiaux, table de types, transformations, canal
#   perceptif et TOUS les noms de propriete sont fabriques dans ce fichier,
#   aucun n'existe ailleurs dans le depot. C'est lui qui prouve que le cablage
#   ne connait ni minerai, ni forge, ni scories.
#
# LA CONSERVATION SE MESURE, ELLE NE SE SUPPOSE PAS : chaque cas qui fait
# tourner le cycle rappelle Banc.masse_dans_le_monde et le compare a la
# reference prise AVANT, jamais a un nombre recopie ici.

const Banc = preload("res://scripts/banc_economie.gd")
const Monde = preload("res://scripts/monde.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Perception = preload("res://scripts/perception.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DELTA := 0.1
# Tolerance de comparaison de masses : la chaine passe par une division
# (volume = masse/densite) puis une multiplication (masse = densite*volume)
# dans objet.gd -- l'egalite BINAIRE n'est pas garantie, l'egalite a 1e-6 pres
# l'est largement sur les ordres de grandeur de ce banc (~200 kg).
const EPS := 1e-6

var _config: Dictionary
var _catalogues: Dictionary

func _init() -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_economie.json"))
	_catalogues = {
		"types": JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json")),
		"materiaux": JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json")),
		"canaux": JSON.parse_string(FileAccess.get_file_as_string("res://data/canaux.json")),
		"transformations": JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")),
	}

	_le_ramassage_transfere_sans_rien_creer()
	_la_vitesse_baisse_proportionnellement_a_la_charge()
	_un_colon_sans_charge_va_a_vitesse_normale()
	_le_surcout_de_fatigue_monte_avec_la_charge()
	_la_fonte_produit_un_lingot_et_des_scories()
	_les_scories_existent_dans_le_monde_apres_la_fonte()
	_la_masse_totale_est_constante_sur_le_cycle_reel()
	_la_ressource_lointaine_est_filtree_sous_le_seuil()
	_la_lointaine_rentable_passe_quand_les_proches_sont_retirees()
	_le_seuil_abaisse_fait_repasser_la_miette()
	_la_depose_remet_la_charge_a_zero()
	_le_retrait_des_proches_ne_perd_aucune_masse()
	_hors_domaine_des_cueilleurs_de_spores()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_economie.gd -- portage conserve (consommer.gd dans les deux " +
		"sens), vitesse composee par la charge, fonte a DEUX produits dont la " +
		"somme est exacte (produit.gd deux fois sur le meme ancien), masse " +
		"totale invariante (somme.gd) et seuil de rentabilite ABSOLU qui RETIRE " +
		"des entrees avant dominance.gd -- sans qu'aucun mecanisme du coeur ne " +
		"soit touche")
	quit(0)

# ---- Fixtures ---------------------------------------------------------------

# Monte la scene REELLE du disque : colon, lieux et ressources de
# data/banc_economie.json, dans un vrai Monde.
func _scene_reelle() -> Dictionary:
	return _scene_depuis(_config, _catalogues)

func _scene_depuis(config: Dictionary, catalogues: Dictionary) -> Dictionary:
	var colon := Banc.construire_colon(config)
	var monde = Monde.new()
	monde.ajouter(colon, "colon", colon.position)
	var lieux := Banc.construire_lieux(config)
	for lieu in lieux:
		monde.ajouter(lieu, "lieu", lieu.position)
	var ressources := Banc.construire_ressources(config, catalogues.materiaux)
	for ressource in ressources:
		monde.ajouter(ressource, "ressource", ressource.position)
	return {"colon": colon, "monde": monde, "lieux": lieux, "ressources": ressources}

func _par_id(objets: Array, id: String) -> Dictionary:
	for objet in objets:
		if String(objet.id) == id:
			return objet
	return {}

func _reserve(objet: Dictionary, nom: String) -> float:
	return float(objet.proprietes.get("reserves", {}).get(nom, {}).get("reserve", 0.0))

# La chaine de decision COMPLETE, exactement celle de Banc.avancer : couche 1
# (perception.gd) -> entrees de saillance -> FILTRE de rentabilite ->
# dominance.gd -> choix. Recopiee ici plutot qu'appelee, parce que ces cas
# testent la DECISION seule, sans faire avancer le monde d'un tick.
func _decision(colon: Dictionary, monde, config: Dictionary, catalogues: Dictionary) -> Dictionary:
	var perceptions := Perception.percevoir(colon, monde, catalogues.canaux)
	var filtre := Banc.filtrer_rentables(Banc.resultats_depuis_perceptions(perceptions, config), config)
	var visibles := Dominance.visibles(filtre.gardes, colon)
	return {"filtre": filtre, "visibles": visibles, "cible": Banc.choisir_cible(visibles)}

func _ids(entrees: Array) -> Array:
	var ids: Array = []
	for entree in entrees:
		ids.append(String(entree.chose.id))
	return ids

# Fait tourner N ticks du cycle REEL et rend le monde final (avancer peut le
# reconstruire -- une ressource videe en sort).
func _avancer_n(colon: Dictionary, monde, n: int, config: Dictionary, catalogues: Dictionary) -> Dictionary:
	var compteur := 0
	var produits: Array = []
	for i in range(n):
		var resultat := Banc.avancer(colon, monde, compteur, DELTA, config, catalogues)
		monde = resultat.monde
		compteur = int(resultat.compteur_produit)
		for objet in resultat.produits:
			produits.append(objet)
	return {"monde": monde, "compteur": compteur, "produits": produits}

# ---- Cas --------------------------------------------------------------------

# CONSERVATION AU RAMASSAGE : ce que la ressource perd, le colon le gagne, au
# meme tick et au meme chiffre. C'est la garantie de consommer.gd (conservatif
# par construction depuis sa correction), verifiee ici sur le chemin du banc et
# non sur le mecanisme seul.
func _le_ramassage_transfere_sans_rien_creer() -> void:
	var scene := _scene_reelle()
	var ressource := _par_id(scene.ressources, "minerai_proche_1")
	var nom_matiere := String(_config.nom_reserve_matiere)
	var nom_portage := String(_config.nom_reserve_portage)

	var avant_ressource := _reserve(ressource, nom_matiere)
	var avant_colon := _reserve(scene.colon, nom_portage)
	verif.v(avant_ressource > 0.0, "la ressource doit porter de la matiere au depart")

	var pris := Banc.charger(ressource, scene.colon, _config, DELTA)
	var apres_ressource := _reserve(ressource, nom_matiere)
	var apres_colon := _reserve(scene.colon, nom_portage)

	verif.v(pris > 0.0, "un ramassage doit transferer quelque chose")
	verif.v(absf((avant_ressource - apres_ressource) - pris) < EPS,
		"la ressource doit perdre EXACTEMENT ce qui a ete pris (%.6f vs %.6f)" % [avant_ressource - apres_ressource, pris])
	verif.v(absf((apres_colon - avant_colon) - pris) < EPS,
		"le colon doit gagner EXACTEMENT ce qui a ete pris")
	verif.v(absf((avant_ressource + avant_colon) - (apres_ressource + apres_colon)) < EPS,
		"la somme des deux ne doit pas bouger d'un chiffre")

	# La ressource ne perd JAMAIS sa masse : c'est une reserve qui bouge, pas
	# une propriete derivee de la composition (voir en-tete de banc_economie.gd).
	verif.v(float(ressource.proprietes.masse) == avant_ressource,
		"la masse de la ressource ne doit jamais etre reecrite par un ramassage")

# La formule de la consigne, telle quelle -- y compris son cas DEGENERE : a
# charge == capacite la vitesse est EXACTEMENT nulle et le colon serait cloue
# au sol. Verrouille POSITIVEMENT pour qu'une donnee future qui franchirait ce
# point se voie tout de suite (la calibration du banc l'evite : la plus grosse
# ressource pese 84.0 pour une capacite de 100.0).
func _la_vitesse_baisse_proportionnellement_a_la_charge() -> void:
	verif.v(Banc.vitesse_effective(200.0, 50.0, 100.0) == 100.0, "a demi-charge, la moitie de la vitesse de base")
	verif.v(Banc.vitesse_effective(200.0, 25.0, 100.0) == 150.0, "au quart de charge, trois quarts de la vitesse")
	verif.v(Banc.vitesse_effective(200.0, 100.0, 100.0) == 0.0, "a pleine charge, vitesse EXACTEMENT nulle")
	verif.v(Banc.vitesse_effective(200.0, 150.0, 100.0) == 0.0, "au-dela de la capacite, jamais une vitesse negative")
	verif.v(Banc.vitesse_effective(200.0, 10.0, 0.0) == 0.0, "capacite nulle : 0.0, jamais une division par zero")

	# Et sur le chemin reel : deux ticks identiques, l'un a vide, l'autre
	# charge, ne parcourent pas la meme distance.
	var scene := _scene_reelle()
	var cible := Vector3(1500.0, 500.0, 0.0)
	var depart: Vector3 = scene.colon.position
	Banc._avancer_vers(scene.colon, cible, _config, DELTA)
	var pas_a_vide: float = depart.distance_to(scene.colon.position)

	var charge := _scene_reelle()
	charge.colon.proprietes.reserves[String(_config.nom_reserve_portage)]["reserve"] = 50.0
	var depart_charge: Vector3 = charge.colon.position
	Banc._avancer_vers(charge.colon, cible, _config, DELTA)
	var pas_charge: float = depart_charge.distance_to(charge.colon.position)

	verif.v(pas_charge < pas_a_vide, "charge, le colon avance moins loin dans le meme temps (%.3f vs %.3f)" % [pas_charge, pas_a_vide])
	var ratio: float = 1.0 - 50.0 / float(_config.colon.capacite_portage)
	verif.v(absf(pas_charge - pas_a_vide * ratio) < 1e-3, "le pas doit suivre EXACTEMENT (1 - charge/capacite)")

func _un_colon_sans_charge_va_a_vitesse_normale() -> void:
	var base: float = float(_config.colon.vitesse_base)
	verif.v(Banc.vitesse_effective(base, 0.0, float(_config.colon.capacite_portage)) == base,
		"a vide, la vitesse effective est EXACTEMENT la vitesse de base")

	var scene := _scene_reelle()
	verif.v(_reserve(scene.colon, String(_config.nom_reserve_portage)) == 0.0, "un colon nait a vide")
	var decomposition := Banc.poser_surcout_action(scene.colon, _config)
	verif.v(float(decomposition.total) == 0.0, "a vide, aucun surcout de portage")

# Le surcout est un TERME de l'UNIQUE ecrivain de surcout_action, et il monte
# avec la charge. Le canal ecrit est bien celui de l'energie, jamais celui du
# portage (qui reste a cout nul -- une charge ne s'evapore pas).
func _le_surcout_de_fatigue_monte_avec_la_charge() -> void:
	var coef: float = float(_config.colon.coef_surcout_portage)
	verif.v(Banc.surcout_portage(50.0, coef) == coef * 50.0, "le surcout est proportionnel a la charge")
	verif.v(Banc.surcout_portage(0.0, coef) == 0.0, "aucune charge, aucun surcout")

	var scene := _scene_reelle()
	var nom_energie := String(_config.nom_reserve_energie)
	var nom_portage := String(_config.nom_reserve_portage)
	var canal: Dictionary = scene.colon.proprietes.reserves[nom_energie]

	scene.colon.proprietes.reserves[nom_portage]["reserve"] = 20.0
	var leger := Banc.poser_surcout_action(scene.colon, _config)
	var surcout_leger: float = float(canal.surcout_action)

	scene.colon.proprietes.reserves[nom_portage]["reserve"] = 80.0
	var lourd := Banc.poser_surcout_action(scene.colon, _config)
	var surcout_lourd: float = float(canal.surcout_action)

	verif.v(surcout_lourd > surcout_leger, "plus charge, plus le surcout est haut (%.3f vs %.3f)" % [surcout_lourd, surcout_leger])
	verif.v(absf(surcout_lourd - float(lourd.portage)) < EPS, "le canal doit porter EXACTEMENT ce que la decomposition annonce")
	verif.v(absf(surcout_leger - float(leger.portage)) < EPS, "idem a charge legere")
	verif.v(float(scene.colon.proprietes.reserves[nom_portage].cout_base) == 0.0,
		"le canal de portage reste a cout nul : une charge ne se consume jamais toute seule")

# LA FONTE, et l'invariant qui la justifie : deux appels sur le MEME ancien,
# 0.85 + 0.15 = 1.0. Sans le second produit, produit.gd perdrait 15% de la
# masse sans destination (son propre en-tete l'assume) -- c'est cette fuite que
# le chantier ferme.
func _la_fonte_produit_un_lingot_et_des_scories() -> void:
	var scene := _scene_reelle()
	var forge := _par_id(scene.lieux, "forge")
	var masse := 100.0
	Banc._poser_matiere(forge, _config, masse)

	var resultat := Banc.fondre(forge, _config, _catalogues, 0)
	verif.v(resultat.produits.size() == 2, "la fonte doit produire DEUX objets, jamais un seul")
	if resultat.produits.size() != 2:
		return

	var lingot: Dictionary = resultat.produits[0]
	var scories: Dictionary = resultat.produits[1]
	var masse_lingot: float = float(lingot.proprietes.masse)
	var masse_scories: float = float(scories.proprietes.masse)

	var transformations: Dictionary = _catalogues.transformations.transformations
	var rendement_metal: float = float(transformations[String(_config.fonte.transformation_metal)].a_zero.produire.rendement)
	var rendement_scories: float = float(transformations[String(_config.fonte.transformation_scories)].a_zero.produire.rendement)

	verif.v(absf(masse_lingot - masse * rendement_metal) < EPS,
		"le lingot doit peser EXACTEMENT rendement x masse fondue (%.6f)" % masse_lingot)
	verif.v(absf(masse_scories - masse * rendement_scories) < EPS,
		"les scories doivent peser EXACTEMENT le complement (%.6f)" % masse_scories)
	verif.v(absf((masse_lingot + masse_scories) - masse) < EPS,
		"LA SOMME DES DEUX PRODUITS DOIT EGALER LA MASSE FONDUE -- rien ne disparait")

	verif.v(_reserve(forge, String(_config.nom_reserve_matiere)) == 0.0,
		"le lieu doit etre vide apres la fonte, sinon la matiere serait comptee deux fois")
	verif.v(bool(lingot.proprietes.get(String(_config.propriete_ressource), false)),
		"le lingot est une ressource : le colon le porte au grenier")
	verif.v(not bool(scories.proprietes.get(String(_config.propriete_ressource), false)),
		"les scories ne sont PAS une ressource : c'est pour ca qu'elles restent au sol")
	verif.v(String(lingot.proprietes.get(String(_config.propriete_depot), "")) == String(_config.fonte.depot_lingot),
		"le lingot doit viser le grenier, jamais la forge")

	# Une reserve nulle ne fond rien -- chemin mort, jamais deux objets a masse
	# zero ajoutes au monde.
	var vide := Banc.fondre(forge, _config, _catalogues, 0)
	verif.v(vide.produits.is_empty(), "un lieu vide ne fond rien")

func _les_scories_existent_dans_le_monde_apres_la_fonte() -> void:
	var scene := _scene_reelle()
	var monde = scene.monde
	# 400 ticks : de quoi ramasser le premier minerai, le porter a la forge et
	# le fondre (mesure en scene reelle : fonte a t=4.9 s).
	var suite := _avancer_n(scene.colon, monde, 400, _config, _catalogues)
	monde = suite.monde

	var scories_au_sol: Array = []
	var lingots: Array = []
	for entree in monde.choses.values():
		if String(entree.type) != "produit":
			continue
		if bool(entree.chose.proprietes.get(String(_config.propriete_ressource), false)):
			lingots.append(entree.chose)
		else:
			scories_au_sol.append(entree.chose)

	verif.v(not suite.produits.is_empty(), "le cycle reel doit avoir fondu au moins une fois en 40 s")
	verif.v(not scories_au_sol.is_empty(), "un tas de scories doit exister DANS LE MONDE apres la fonte")
	for tas in scories_au_sol:
		verif.v(_reserve(tas, String(_config.nom_reserve_matiere)) > 0.0,
			"un tas de scories porte de la matiere -- c'est ce qui le fait compter dans le bilan")

# LA CONSERVATION GLOBALE, mesuree par somme.gd sur le cycle REEL du disque --
# ce qu'aucun banc du depot ne pouvait meme mesurer avant sa livraison.
func _la_masse_totale_est_constante_sur_le_cycle_reel() -> void:
	var scene := _scene_reelle()
	var monde = scene.monde
	var reference := Banc.masse_dans_le_monde(monde, scene.colon, _config)
	verif.v(reference > 0.0, "la scene reelle doit porter de la matiere au depart")

	var compteur := 0
	var pire_ecart := 0.0
	for i in range(600):
		var resultat := Banc.avancer(scene.colon, monde, compteur, DELTA, _config, _catalogues)
		monde = resultat.monde
		compteur = int(resultat.compteur_produit)
		pire_ecart = max(pire_ecart, absf(Banc.masse_dans_le_monde(monde, scene.colon, _config) - reference))
	verif.v(pire_ecart < EPS,
		"la masse totale doit rester constante a chaque tick du cycle (pire ecart %.9f)" % pire_ecart)
	verif.v(compteur > 0, "le cycle doit avoir produit quelque chose en 60 s, sinon ce cas ne prouve rien")

# LE SEUIL ABSOLU : la miette est PERCUE (elle est bien dans les perceptions et
# dans les resultats bruts) et pourtant RETIREE avant dominance.gd. C'est le
# geste neuf -- les trois bancs qui touchent a resultats n'y AJOUTENT que des
# entrees, aucun n'en retire.
func _la_ressource_lointaine_est_filtree_sous_le_seuil() -> void:
	var scene := _scene_reelle()
	var perceptions := Perception.percevoir(scene.colon, scene.monde, _catalogues.canaux)
	var bruts := Banc.resultats_depuis_perceptions(perceptions, _config)
	verif.v(_ids(bruts).has("miette_lointaine"),
		"la miette doit etre PERCUE : le filtre retire ce qui est vu, pas ce qui est invisible")

	var filtre := Banc.filtrer_rentables(bruts, _config)
	verif.v(_ids(filtre.retires).has("miette_lointaine"), "la miette doit etre retiree, sous le seuil de rentabilite")
	verif.v(not _ids(filtre.gardes).has("miette_lointaine"), "et ne jamais survivre dans les gardes")
	verif.v(_ids(filtre.gardes).has("minerai_proche_1"), "une ressource proche passe le filtre")

	# Le score, verifie a la main sur la formule -- jamais un nombre recopie.
	for entree in filtre.retires:
		var attendu: float = Banc.score_rentabilite(float(entree.valeur_nue), float(entree.distance), float(_config.cout_par_case))
		verif.v(absf(float(entree.saillance) - attendu) < EPS, "la saillance rendue est le SCORE NET du trajet")
		verif.v(float(entree.saillance) < float(_config.seuil_rentabilite), "un retire est bien sous le seuil")

	# Et il n'y va JAMAIS, meme seul au monde : c'est ce qu'un seuil ABSOLU
	# produit et qu'un seuil relatif (dominance.gd) ne peut pas produire.
	var seul := _config.duplicate(true)
	seul["ressources"] = [_decl_ressource("miette_lointaine")]
	var scene_seule := _scene_depuis(seul, _catalogues)
	var decision := _decision(scene_seule.colon, scene_seule.monde, seul, _catalogues)
	verif.v(decision.cible == null,
		"seule ressource du monde et pourtant AUCUNE decision : le colon ne va pas a 900 unites pour une miette")

# L'AUTRE MOITIE, et elle ne joue PAS sur le meme mecanisme : le gisement
# lointain passe le filtre (son score est au-dessus du seuil) mais dominance.gd
# l'ECRASE tant que les proches existent. Les retirer ne change pas son score
# d'un chiffre -- c'est le sommet qui a baisse.
func _la_lointaine_rentable_passe_quand_les_proches_sont_retirees() -> void:
	var scene := _scene_reelle()
	var avant := _decision(scene.colon, scene.monde, _config, _catalogues)
	verif.v(_ids(avant.filtre.gardes).has("gisement_lointain"), "le gisement lointain passe le filtre des le depart")
	verif.v(not _ids(avant.visibles).has("gisement_lointain"), "mais dominance.gd l'ecrase tant que les proches sont la")
	verif.v(avant.cible != null and String(avant.cible.chose.id) == "minerai_proche_1",
		"la decision va d'abord au plus rentable des proches")

	var score_avant := 0.0
	for entree in avant.filtre.gardes:
		if String(entree.chose.id) == "gisement_lointain":
			score_avant = float(entree.saillance)

	var retrait := Banc.basculer_les_proches(scene.monde, [], _config)
	var apres := _decision(scene.colon, retrait.monde, _config, _catalogues)
	verif.v(apres.cible != null and String(apres.cible.chose.id) == "gisement_lointain",
		"les proches retirees, le gisement lointain devient la decision")
	verif.v(not _ids(apres.visibles).has("miette_lointaine"),
		"la miette, elle, reste retiree -- un seuil absolu ne depend pas de ce qui reste")

	var score_apres := 0.0
	for entree in apres.filtre.gardes:
		if String(entree.chose.id) == "gisement_lointain":
			score_apres = float(entree.saillance)
	verif.v(absf(score_avant - score_apres) < EPS,
		"le score du gisement n'a pas bouge : c'est le SOMMET qui a baisse, jamais lui qui a monte")

# Verrouillage DANS L'AUTRE SENS (patron banc_ecosysteme_terrain.gd, dont le
# seuil abaisse fait reapparaitre la proie cachee sans qu'aucune position ne
# bouge) : ce qui exclut la miette est bien le SEUIL, et rien d'autre.
func _le_seuil_abaisse_fait_repasser_la_miette() -> void:
	var permissif := _config.duplicate(true)
	permissif["seuil_rentabilite"] = 0.0
	var scene := _scene_depuis(permissif, _catalogues)
	var filtre := Banc.filtrer_rentables(
		Banc.resultats_depuis_perceptions(
			Perception.percevoir(scene.colon, scene.monde, _catalogues.canaux), permissif),
		permissif)
	verif.v(_ids(filtre.gardes).has("miette_lointaine"), "seuil a 0.0 : la miette repasse, aucune position n'a bouge")
	verif.v(filtre.retires.is_empty(), "et plus rien n'est retire")

# La depose vide la charge EXACTEMENT, et le lieu gagne EXACTEMENT ce que le
# colon a perdu.
func _la_depose_remet_la_charge_a_zero() -> void:
	var scene := _scene_reelle()
	var forge := _par_id(scene.lieux, "forge")
	var nom_portage := String(_config.nom_reserve_portage)
	var nom_matiere := String(_config.nom_reserve_matiere)

	scene.colon.proprietes.reserves[nom_portage]["reserve"] = 30.0
	var avant_lieu := _reserve(forge, nom_matiere)

	# Un delta largement suffisant pour tout deposer : consommer.gd borne
	# lui-meme a ce que la charge possede, aucun pre-bornage ici (contre-epreuve
	# de sa correction).
	var pose := Banc.decharger(scene.colon, forge, _config, 10.0)
	verif.v(absf(pose - 30.0) < EPS, "la depose transfere EXACTEMENT la charge, jamais la quantite demandee (%.6f)" % pose)
	verif.v(_reserve(scene.colon, nom_portage) == 0.0, "la charge portee retombe EXACTEMENT a zero")
	verif.v(absf(_reserve(forge, nom_matiere) - (avant_lieu + 30.0)) < EPS, "le lieu gagne exactement ce qui a ete pose")

	# Et la phase repart de la recherche au tick suivant, sur le chemin reel.
	scene.colon["phase"] = "decharger"
	scene.colon["depot_id"] = "forge"
	scene.colon.proprietes.reserves[nom_portage]["reserve"] = 1.0
	var resultat := Banc.avancer(scene.colon, scene.monde, 0, 10.0, _config, _catalogues)
	verif.v(String(scene.colon.phase) == "chercher", "charge vide, le colon repart chercher (phase %s)" % String(scene.colon.phase))

# Le clic sort de la matiere du PLATEAU, pas du BILAN : ce qui est sorti est
# rendu par la fonction, et monde + hors plateau reste egal a la reference --
# DANS LES DEUX SENS, aller ET retour (le clic est une bascule, correction
# faite apres observation a l'ecran : voir banc_economie.gd, « LE CLIC »).
func _le_retrait_des_proches_ne_perd_aucune_masse() -> void:
	var scene := _scene_reelle()
	var reference := Banc.masse_dans_le_monde(scene.monde, scene.colon, _config)

	var sortie := Banc.basculer_les_proches(scene.monde, [], _config)
	verif.v(sortie.sortis.size() == 2, "les deux ressources marquees proches sortent, jamais les lointaines")
	verif.v(sortie.rentres.is_empty(), "rien ne rentre quand rien n'etait hors plateau")
	verif.v(float(sortie.masse_delta) > 0.0, "le delta est POSITIF quand la matiere quitte le plateau")
	var apres := Banc.masse_dans_le_monde(sortie.monde, scene.colon, _config)
	verif.v(absf((apres + float(sortie.masse_delta)) - reference) < EPS,
		"monde + hors plateau doit egaler la reference (%.9f)" % absf(apres + float(sortie.masse_delta) - reference))
	verif.v(apres < reference, "et la masse DANS LE MONDE, elle, a bien baisse -- dit plutot que masque")

	# Le retour : les MEMES objets, avec leur reserve intacte -- jamais une
	# reconstruction depuis la declaration, qui les rendrait pleins et creerait
	# de la matiere.
	var retour := Banc.basculer_les_proches(sortie.monde, sortie.hors_plateau, _config)
	verif.v(retour.rentres.size() == 2, "le clic suivant remet les deux ressources")
	verif.v(retour.hors_plateau.is_empty(), "et le stock hors plateau se vide")
	verif.v(float(retour.masse_delta) < 0.0, "le delta est NEGATIF quand la matiere revient")
	verif.v(absf(float(retour.masse_delta) + float(sortie.masse_delta)) < EPS,
		"ce qui revient egale EXACTEMENT ce qui etait parti")
	verif.v(absf(Banc.masse_dans_le_monde(retour.monde, scene.colon, _config) - reference) < EPS,
		"apres l'aller-retour, la masse du monde est revenue a la reference")

	# Une bascule sur un monde sans ressource proche ne casse rien et le DIT
	# (un clic muet se lit comme un clic casse -- c'est ce qui s'est passe).
	var vide := Banc.basculer_les_proches(retour.monde, [], _config)
	var re_vide := Banc.basculer_les_proches(vide.monde, [], _config)
	verif.v(re_vide.sortis.is_empty() and float(re_vide.masse_delta) == 0.0,
		"deux sorties de suite ne sortent rien la seconde fois, et ne bougent aucune masse")

func _decl_ressource(id: String) -> Dictionary:
	for decl in _config.ressources:
		if String(decl.id) == id:
			return decl
	return {}

# ---- HORS DOMAINE -----------------------------------------------------------

# Des cueilleurs de spores sur une planete inventee : catalogue de materiaux,
# table de types, transformations, canal perceptif ET tous les noms de
# propriete sont fabriques ici, aucun n'existe ailleurs dans le depot. Pas un
# minerai, pas une forge, pas un lingot -- et le meme code traverse la chaine
# entiere : ramassage conserve, portage qui ralentit, raffinage a deux
# produits, conservation exacte, seuil de rentabilite qui retire.
func _hors_domaine_des_cueilleurs_de_spores() -> void:
	var materiaux := {
		"mousse_zorg": {"densite": 1.5},
		"essence_zorg": {"densite": 0.9},
		"limon_zorg": {"densite": 0.4},
	}
	var types := {
		"fiole_essence": {"composition": [{"materiau": "essence_zorg", "volume": 1.0}]},
		"depot_limon": {"composition": [{"materiau": "limon_zorg", "volume": 1.0}]},
	}
	var transformations := {"transformations": {
		"distillation_zorg": {"a_zero": {"produire": {"type_produit": "fiole_essence", "rendement": 0.6}}},
		"depot_zorg": {"a_zero": {"produire": {"type_produit": "depot_limon", "rendement": 0.4}}},
	}}
	var canaux := {"palpe_zorg": {"geometrie": "cone_oriente", "proprietes_captees": []}}
	var catalogues := {"types": types, "materiaux": materiaux, "canaux": canaux, "transformations": transformations}

	var config := {
		"nom_reserve_matiere": "spores",
		"nom_reserve_portage": "sacoche",
		"nom_reserve_energie": "souffle",
		"propriete_ressource": "cueillable",
		"propriete_valeur": "attrait_zorg",
		"propriete_depot": "ou_deposer",
		"propriete_fond": "distille",
		"propriete_proche": "a_portee_de_camp",
		"nom_vitesse": "allure",
		"cout_par_case": 0.02,
		"seuil_rentabilite": 1.0,
		"seuil_fonte": 1.0,
		"colon": {
			"id": "cueilleur",
			"position": [0.0, 0.0, 0.0],
			"capacite_portage": 40.0,
			"fraction_charge_max": 0.7,
			"vitesse_base": 100.0,
			"coef_surcout_portage": 0.05,
			"metabolisme_base_par_s": 0.1,
			"capacite_energie": 200.0,
			"portee_travail": 30.0,
			"taux_charge": 100.0,
			"taux_decharge": 100.0,
			"seuil_ecrasement": 0.5,
			"canaux": ["palpe_zorg"],
			"canaux_config": {"palpe_zorg": {"portee": 900.0, "angle": 360.0, "sensibilite": 1.0, "seuil": 0.0}},
		},
		"lieux": [
			{"id": "alambic", "position": [60.0, 0.0, 0.0], "distille": true, "offset_lingot": [20.0, 0.0, 0.0], "offset_scories": [-20.0, 0.0, 0.0]},
			{"id": "cellier", "position": [120.0, 0.0, 0.0], "distille": false},
		],
		"ressources": [
			{"id": "touffe_proche", "position": [40.0, 0.0, 0.0], "materiau": "mousse_zorg", "volume": 0.01, "valeur": 5.0, "depot": "alambic", "proche": true},
			{"id": "touffe_lointaine", "position": [800.0, 0.0, 0.0], "materiau": "mousse_zorg", "volume": 0.002, "valeur": 1.2, "depot": "alambic", "proche": false},
		],
		"fonte": {
			"transformation_metal": "distillation_zorg",
			"transformation_scories": "depot_zorg",
			"valeur_lingot": 7.0,
			"depot_lingot": "cellier",
			"ecart_empilement": 12.0,
			"rangs_empilement": 3,
		},
	}

	var scene := _scene_depuis(config, catalogues)
	verif.v(scene.ressources.size() == 2, "les deux touffes doivent se fabriquer sur un catalogue entierement invente")

	var reference := Banc.masse_dans_le_monde(scene.monde, scene.colon, config)
	verif.v(reference > 0.0, "la scene inventee porte de la matiere")

	# Le filtre trie sur les memes regles, avec d'autres nombres.
	var decision := _decision(scene.colon, scene.monde, config, catalogues)
	verif.v(_ids(decision.filtre.retires).has("touffe_lointaine"), "la touffe lointaine est sous le seuil, meme code")
	verif.v(decision.cible != null and String(decision.cible.chose.id) == "touffe_proche", "le cueilleur vise la touffe proche")

	# Le cycle entier, sans un seul nom du depot.
	var monde = scene.monde
	var compteur := 0
	var pire_ecart := 0.0
	var produits: Array = []
	for i in range(400):
		var resultat := Banc.avancer(scene.colon, monde, compteur, DELTA, config, catalogues)
		monde = resultat.monde
		compteur = int(resultat.compteur_produit)
		for objet in resultat.produits:
			produits.append(objet)
		pire_ecart = max(pire_ecart, absf(Banc.masse_dans_le_monde(monde, scene.colon, config) - reference))

	verif.v(produits.size() >= 2, "le raffinage inventé doit avoir produit sa paire (fiole + depot), %d obtenu(s)" % produits.size())
	verif.v(pire_ecart < EPS, "la conservation tient sur un domaine entierement invente (pire ecart %.9f)" % pire_ecart)

	if produits.size() >= 2:
		var somme_produits: float = float(produits[0].proprietes.masse) + float(produits[1].proprietes.masse)
		var attendu: float = float(produits[0].proprietes.masse) / 0.6
		verif.v(absf(somme_produits - attendu) < 1e-4,
			"0.6 + 0.4 = 1.0 : la somme des deux produits egale la matiere distillee (%.6f vs %.6f)" % [somme_produits, attendu])
