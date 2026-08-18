extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_economie.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « conservation + fonte
# + portage + cout de trajet » (audit prealable
# audit_economie_logistique_prealable.md, lignes 1/2/3/4 -- les quatre au
# verdict PARTIELLEMENT COUVERT sauf la 3, CABLABLE ; confirme a l'ecriture :
# AUCUN mecanisme du coeur touche ni cree).
#
# CE QU'ON DOIT VOIR : un colon qui ramasse du minerai, le porte a la forge en
# marchant VISIBLEMENT PLUS LENTEMENT parce qu'il est charge, le fond en un
# lingot ET un tas de scories, porte le lingot au grenier, et recommence. En
# haut de l'ecran, un seul nombre : la masse totale du monde, qui NE BOUGE
# JAMAIS. Au fond a droite, une miette de minerai a ~900 unites, grisee : le
# colon ne va jamais la chercher, quoi qu'il arrive.
#
# QUATRE CHOSES QUI NE VIVENT NULLE PART AILLEURS DANS LE DEPOT :
#
# (1) LA FUITE DE MASSE DE produit.gd EST FERMEE. Son en-tete l'assume
#     explicitement : « rendement_perdu n'existe pas comme champ [...] la masse
#     perdue disparait simplement (elle n'est nulle part) » -- les treize
#     entrees 'produire' de data/transformations.json perdent chacune leur
#     complement de rendement sans destination. Ici, fondre() appelle DEUX FOIS
#     Produit.transformer sur le MEME proprietes_ancien, AVANT tout ecrasement :
#     0.85 en lingot (data/transformations.json:fonte_metal), 0.15 en scories
#     (fonte_scories), somme EXACTE. Passer par extinction.gd est FERME et ce
#     n'est pas un oubli : a_zero.produire ne lit qu'UN SEUL produit et REMPLACE
#     les proprietes sur la MEME instance (meme id, meme position) -- il n'y a
#     nulle part ou mettre le second objet.
#
# (2) LE PREMIER RETRAIT D'UNE ENTREE DE 'resultats' DU DEPOT. Trois bancs
#     construisent ou INSERENT des entrees de saillance avant dominance.gd
#     (banc_charge.gd, banc_psycho_social.gd, banc_grief.gd) ; aucun n'en
#     RETIRE. Le geste est ici, et il repond a un manque reel du coeur nomme par
#     l'audit : dominance.gd est RELATIF par construction (il garde ce qui est a
#     moins de seuil_ecrasement du SOMMET), il ne peut donc pas porter un seuil
#     de rentabilite ABSOLU -- une ressource seule dans le champ reste la
#     decision, aussi faible soit sa saillance, et un colon irait a 890 unites
#     pour une miette s'il n'avait rien d'autre a faire.
#
# (3) LE PORTAGE, concept qui n'existait NULLE PART (ni propriete, ni mecanisme,
#     ni banc -- recherche exhaustive de l'audit, ligne 3). Il est neuf EN
#     DONNEE, jamais en mecanisme : charger et decharger sont des appels a
#     consommer.gd (transfert conserve), le plafond est du cablage, la vitesse
#     composee a trois precedents litteraux (banc_friction.gd/banc_faim_thermo.
#     gd/banc_grief.gd) et le surcout de fatigue est un TERME DE PLUS dans
#     l'unique ecrivain de surcout_action.
#
# (4) somme.gd MESURE UNE CONSERVATION, ce qu'aucun banc ne pouvait faire avant
#     sa livraison (« sans lui, la conservation globale ne peut meme pas etre
#     MESUREE », audit ligne 1). Il n'en est PAS le premier appelant : une
#     session concurrente (banc_marche_competence.gd, §3quinnonagies, lignes
#     9-12 du meme audit) l'a cable pendant ce chantier -- affirmation corrigee
#     plutot que laissee fausse. Les deux usages ne se recouvrent pas : la-bas
#     une OFFRE percue par un colon (un total qui bouge et doit bouger), ici un
#     INVARIANT (un total qui ne doit jamais bouger, et dont le moindre ecart
#     est un bug).
#
# CE QUE LE COLON PERD EN ETANT CHARGE EST UNE RESERVE NOMMEE, JAMAIS UNE
# MASSE. masse/volume/densite sont des SORTIES derivees de la composition,
# interdites en ecriture ailleurs qu'a la fabrication (scripts/produit.gd,
# en-tete ; meme discipline que data/materiaux.json:cadavre_demo). Tout porteur
# de matiere porte donc reserves.<nom_reserve_matiere>, posee par le cablage a
# la fabrication depuis proprietes.masse -- c'est elle que consommer.gd
# transfere et que somme.gd mesure. Corollaire : la fonte recoit un
# proprietes_ancien SYNTHETIQUE { "masse": m } et non l'objet lui-meme --
# produit.gd ne lit QUE cette cle dessus, son propre en-tete le dit.
#
# UNE SEULE ECRITURE DE surcout_action PAR TICK (constat (D) de l'audit) :
# poser_surcout_action est l'UNIQUE ECRIVAIN de ce champ dans tout ce fichier.
# Ce banc n'a qu'une source de surcout (le portage) -- la discipline est tenue
# quand meme, parce qu'un deuxieme ecrivain ajoute plus tard n'aurait aucun
# endroit ou se declarer. Le piege est nomme quatre fois dans le depot : deux
# morceaux de cablage qui y ecrivent chacun le leur se detruisent EN SILENCE,
# aucun test ne rougit, la depense est seulement fausse.
#
# LA SAILLANCE QUI ENTRE DANS dominance.gd EST LE SCORE NET DU TRAJET, jamais
# la valeur nue de la ressource : score = valeur / (1 + cout_par_case x
# distance). Filtrer et ponderer sont ici le MEME geste, et c'est voulu -- un
# seuil qui rejette et un poids qui departage sont deux usages du meme nombre.
# Les DEUX arbitrages coexistent et ne se remplacent pas : l'ABSOLU (ce filtre,
# « sous ce niveau je n'y vais pas ») et le RELATIF (dominance.gd, « une
# ressource proche bat une ressource lointaine »), ce dernier gratuit et deja
# la sans une ligne.
#
# AMBIGUITE DE LA CONSIGNE, TRANCHEE ET SIGNALEE -- a confirmer par Yael. Elle
# demandait a la fois « sous seuil_rentabilite, la ressource lointaine est
# retiree » et « elle passe le filtre quand les proches sont retirees ». Les
# deux ne tiennent pas ensemble sous un seuil ABSOLU : son score ne depend pas
# des autres candidats. Lecture retenue -- DEUX choses lointaines, pas une :
# un GISEMENT lointain (au-dessus du seuil, mais ecrase par dominance.gd tant
# que les proches existent ; il devient la decision des qu'elles disparaissent)
# et une MIETTE a ~900 unites (sous le seuil, retiree de resultats, grisee pour
# toujours -- le colon n'y va JAMAIS, meme seule au monde). Les deux phrases
# deviennent vraies en meme temps, sans inventer aucune mecanique. L'autre
# lecture -- un seuil compare au MEILLEUR score disponible -- serait un seuil
# relatif, c'est-a-dire dominance.gd une seconde fois.
#
# AUCUN PROFIL DE SAILLANCE PARTAGE, et c'est une decision : ce banc ne monte
# PAS scripts/proximite.gd (qui lit saillance_intrinseque DANS data/
# profils_saillance.json), il construit ses entrees de saillance lui-meme
# depuis une propriete LOCALE (valeur_ressource) -- precedents banc_grief.gd/
# banc_charge.gd. Passer par proximite.gd aurait force a ajouter des entrees a
# un catalogue PARTAGE (scripts/test_lint_donnees.gd verifie tout champ
# profil_saillance de data/*.json contre lui) pour un banc jetable. La couche 1
# (perception.gd), elle, EST montee telle quelle : c'est elle qui rend la
# distance reelle sur laquelle le cout de trajet se calcule.
#
# LE CLIC EST UNE BASCULE : il SORT les ressources marquees 'proche' du Monde
# (par RECONSTRUCTION DU NEANT -- monde.gd n'a aucune fonction de retrait,
# dette recensee CARTE.md §6, meme idiome que banc_elimination_salete.gd:
# monde_sans_dechets), et le clic suivant les REMET, avec leur reserve intacte.
# CORRECTION D'UNE DECISION DU PREMIER JET, ecrite ici plutot que masquee : ce
# clic etait a sens unique, au motif qu'« un retrait n'a rien vers quoi
# rebasculer ». Le motif etait faux ICI (il vaut pour un NETTOYAGE, ou la
# salete est DETRUITE -- banc_elimination_salete.gd) : la matiere sortie du
# plateau existe toujours, elle est seulement ailleurs. Et le defaut etait
# double, trouve par Yael A L'ECRAN : le colon epuisant les deux ressources
# proches en moins de sept secondes, passe ce delai le clic ne trouvait plus
# rien a sortir -- il l'ecrivait en console, ou personne ne regarde pendant
# qu'une scene tourne. Fermé sur les trois plans : la bascule (on peut remettre
# ce qu'on a sorti), la CALIBRATION (les proches portent de quoi tenir plusieurs
# voyages, voir data/banc_economie.json:_note_ressources) et l'AFFICHAGE (le
# label d'aide dit en permanence ce qui est hors plateau, et le clic trace meme
# quand il ne trouve rien).
# CONSEQUENCE SUR LE BILAN, dite plutot que masquee : sortir de la matiere fait
# BAISSER la somme du monde a cet instant precis. Le cablage tient ce qu'il a
# sorti (masse_retiree, signe : + a la sortie, - au retour) et affiche
# « monde + hors plateau », qui ne bouge jamais -- la matiere n'a pas disparu du
# bilan, elle a quitte le plateau.
#
# LA FONTE ATTEND LA FIN DU DEPOT, et sans cette garde le banc mentirait :
# fondre des que la reserve depasse le seuil produirait un lingot par tick
# pendant tout le dechargement, donc une dizaine de lingots minuscules par
# voyage. fondre_si_pret ne fond que si le lieu n'a RIEN RECU ce tick
# (quantite_deposee == 0.0) -- une garde de cablage, jamais un mecanisme.
#
# LE COLON NE PEUT PAS SE CLOUER AU SOL, mais rien ne l'en empeche
# structurellement : a charge == capacite, vitesse_base x (1 - charge/capacite)
# rend EXACTEMENT 0.0. C'est la CALIBRATION qui l'evite (la plus grosse
# ressource pese 84.0 pour une capacite de 100.0), pas une borne du code -- le
# cas degenere est verrouille POSITIVEMENT par test sur la fonction pure, pour
# qu'une donnee future qui le franchirait se voie tout de suite.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les quatre fichiers, fabrique colon, lieux et
#   ressources, cree le rendu ; _unhandled_input porte le seul clic et ne
#   calcule jamais rien ; _process appelle avancer(...) puis lit ses resultats
#   pour l'affichage et la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_economie.gd) : construire_colon/construire_ressources/
#   construire_lieux/vitesse_effective/surcout_portage/poser_surcout_action/
#   score_rentabilite/resultats_depuis_perceptions/filtrer_rentables/
#   choisir_cible/charger/decharger/fondre/fondre_si_pret/
#   masse_dans_le_monde/monde_sans/ids_ressources_vides/avancer, plus les
#   textes d'affichage et de log.
#
# AUCUN NOM DE PROPRIETE EN DUR : nom_reserve_matiere/nom_reserve_portage/
# nom_reserve_energie/nom_vitesse/propriete_ressource/propriete_valeur/
# propriete_depot/propriete_fond/propriete_proche arrivent tous de
# data/banc_economie.json -- c'est ce qui permet au test de faire traverser le
# meme code par un domaine entierement invente.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Consommer = preload("res://scripts/consommer.gd")
const Produit = preload("res://scripts/produit.gd")
const Depense = preload("res://scripts/depense.gd")
const Somme = preload("res://scripts/somme.gd")
const Perception = preload("res://scripts/perception.gd")
const Dominance = preload("res://scripts/dominance.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

# Les cinq phases du colon vivent HORS proprietes (comme action_en_cours, voir
# docs/design.md) : ce n'est pas un fait stable de l'objet, ca change a chaque
# arrivee. Aucun mecanisme du coeur ne les lit -- seul ce cablage.
const PHASE_CHERCHER := "chercher"
const PHASE_ALLER := "aller"
const PHASE_CHARGER := "charger"
const PHASE_PORTER := "porter"
const PHASE_DECHARGER := "decharger"

var _config: Dictionary = {}
var _types: Dictionary = {}
var _materiaux: Dictionary = {}
var _canaux: Dictionary = {}
var _transformations: Dictionary = {}

var _colon: Dictionary = {}
var _monde
var _compteur_produit := 0
var _masse_retiree := 0.0
var _masse_reference := 0.0
var _temps := 0.0
var _horloge_trace := 0.0
var _fin_tracee := false
var _attente_sans_cible := 0.0
# Les ressources SORTIES DU PLATEAU par le joueur, gardees telles quelles (avec
# leur reserve intacte) pour pouvoir revenir : le clic est une BASCULE, jamais
# une destruction -- voir en-tete, « LE CLIC ».
var _hors_plateau: Array = []
var _clics := 0

var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_colon: ColorRect
var _label_colon: Label
var _label_total: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_economie.json")
	_types = _charger_json("res://data/types.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_canaux = _charger_json("res://data/canaux.json")
	_transformations = _charger_json("res://data/transformations.json")

	_colon = construire_colon(_config)
	_monde = BancCommun.monde_depuis([
		{"choses": [_colon], "type": "colon"},
		{"choses": construire_lieux(_config), "type": "lieu"},
		{"choses": construire_ressources(_config, _materiaux), "type": "ressource"},
	])

	# Reference posee UNE FOIS, jamais recalculee : c'est elle que tout le
	# reste doit egaler pour que la conservation soit une preuve et non un
	# affichage.
	_masse_reference = masse_dans_le_monde(_monde, _colon, _config)

	_construire_rendu()
	print(ligne_pose(_config, _masse_reference))
	_rafraichir({"resultats": [], "retires": []})

func _unhandled_input(evenement: InputEvent) -> void:
	# Le clic ne fait que declencher : aucune decision, aucun calcul ici (voir
	# CLAUDE.md, Regle d'etat -- ce qui est enferme dans _unhandled_input
	# regresse en silence).
	if not (evenement is InputEventMouseButton) or not evenement.pressed:
		return
	if evenement.button_index != MOUSE_BUTTON_LEFT:
		return
	# COMPTEUR DE CLICS REÇUS, affiche a l'ecran. Ce n'est pas du confort : il
	# separe deux pannes que rien ne distinguait, et c'est exactement l'ambiguite
	# qui a coute une observation a Yael -- « le clic n'arrive pas jusqu'ici »
	# (le compteur reste a zero) et « le clic arrive et ne trouve rien a faire »
	# (le compteur monte, l'etat ne bouge pas). Aucun banc du depot n'a
	# aujourd'hui son clic CONFIRME a l'ecran (docs/ETAT.md le dit banc par
	# banc) : tant que ce compteur n'a pas monte une fois sous les yeux de
	# quelqu'un, le routage de _unhandled_input reste une supposition -- partagee
	# par les 73 bancs du depot qui en portent un (compte par grep).
	_clics += 1
	var bascule := basculer_les_proches(_monde, _hors_plateau, _config)
	_monde = bascule.monde
	_hors_plateau = bascule.hors_plateau
	_masse_retiree += float(bascule.masse_delta)
	for id in bascule.sortis:
		if _noeuds.has(id):
			_noeuds[id].queue_free()
			_noeuds.erase(id)
		if _labels.has(id):
			_labels[id].queue_free()
			_labels.erase(id)
	for id in bascule.rentres:
		_creer_rendu_chose(id)
	print(ligne_bascule(_temps, bascule))
	_rafraichir({"resultats": [], "retires": []})

func _process(delta: float) -> void:
	_temps += delta

	var resultat := avancer(
		_colon, _monde, _compteur_produit, delta, _config, _catalogues())
	_monde = resultat.monde
	_compteur_produit = int(resultat.compteur_produit)

	for entree in resultat.produits:
		print(ligne_produit(_temps, entree.id, float(entree.proprietes.masse)))
		_creer_rendu_chose(entree.id)
	for id in resultat.retirees:
		print(ligne_epuisee(_temps, id))
		if _noeuds.has(id):
			_noeuds[id].queue_free()
			_noeuds.erase(id)
		if _labels.has(id):
			_labels[id].queue_free()
			_labels.erase(id)
	if resultat.phase_changee:
		print(ligne_phase(_temps, _colon))
	# Trace de fin, UNE SEULE FOIS : sans elle, la scene se termine sur un
	# silence indistinguable d'un banc casse -- alors que c'est justement le
	# point d'arrivee, le seul qu'un seuil ABSOLU peut produire (il reste de la
	# matiere a portee de vue, et le colon n'y va pas).
	# ATTENTE OBLIGATOIRE AVANT DE LA POSER, defaut mesure en scene reelle : au
	# tick exact ou le colon finit de decharger, la fonte n'a pas encore eu lieu
	# et il n'a effectivement AUCUNE cible -- une trace posee la annoncerait la
	# fin une quinzaine de secondes trop tot, juste avant que le lingot ne
	# naisse et ne le relance.
	if String(_colon.phase) == PHASE_CHERCHER and resultat.visibles.is_empty():
		_attente_sans_cible += delta
	else:
		_attente_sans_cible = 0.0
	if not _fin_tracee and _attente_sans_cible >= float(_config.attente_avant_fin_s) and not resultat.retires.is_empty():
		_fin_tracee = true
		print(ligne_fin(_temps, resultat.retires))

	_horloge_trace += delta
	if _horloge_trace >= float(_config.intervalle_trace_s):
		_horloge_trace = 0.0
		print(ligne_trace(_temps, _colon, _monde, _config, _masse_retiree, _masse_reference))

	_rafraichir(resultat)

func _catalogues() -> Dictionary:
	return {
		"types": _types,
		"materiaux": _materiaux,
		"canaux": _canaux,
		"transformations": _transformations,
	}

# ---- Fonctions PURES, testables headless (voir test_banc_economie.gd) ----

# Le colon porte DEUX canaux de reserve : energie (cout_base = metabolisme,
# pose ici une fois et jamais reecrit ; surcout_action ecrit par
# poser_surcout_action et par personne d'autre) et le canal de PORTAGE, a cout
# nul -- une charge ne s'evapore pas toute seule, elle ne bouge que par
# transfert. Il porte aussi canaux/canaux_config (perception.gd, STRUCTURELLE)
# et forme (dominance.gd, STRUCTURELLE -- seuil_ecrasement en son sein reste
# facultatif).
static func construire_colon(config: Dictionary) -> Dictionary:
	var decl: Dictionary = config.colon
	var pos: Array = decl.position
	var reserves: Dictionary = {}
	reserves[String(config.nom_reserve_energie)] = {
		"reserve": float(decl.capacite_energie),
		"cout_base": float(decl.metabolisme_base_par_s),
		"surcout_action": 0.0,
	}
	reserves[String(config.nom_reserve_portage)] = {
		"reserve": 0.0,
		"cout_base": 0.0,
		"surcout_action": 0.0,
	}
	var proprietes: Dictionary = {
		"reserves": reserves,
		"canaux": decl.canaux.duplicate(true),
		"canaux_config": decl.canaux_config.duplicate(true),
		"forme": {"seuil_ecrasement": float(decl.seuil_ecrasement)},
	}
	proprietes[String(config.nom_vitesse)] = float(decl.vitesse_base)
	return {
		"id": String(decl.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": proprietes,
		"phase": PHASE_CHERCHER,
		"cible_id": "",
		"depot_id": "",
	}

# Les lieux (forge, grenier) sont des objets ordinaires du Monde qui portent
# une reserve de matiere -- jamais une structure a part. Seul celui qui porte
# la propriete de fonte fond ce qu'il recoit ; le grenier ne fait
# qu'accumuler, sans une ligne de plus.
static func construire_lieux(config: Dictionary) -> Array:
	var lieux: Array = []
	for decl in config.lieux:
		var pos: Array = decl.position
		var proprietes: Dictionary = {"reserves": {}}
		proprietes["reserves"][String(config.nom_reserve_matiere)] = {"reserve": 0.0}
		proprietes[String(config.propriete_fond)] = bool(decl.get(String(config.propriete_fond), false))
		if decl.has("offset_lingot"):
			proprietes["offset_lingot"] = decl.offset_lingot.duplicate(true)
		if decl.has("offset_scories"):
			proprietes["offset_scories"] = decl.offset_scories.duplicate(true)
		lieux.append({
			"id": String(decl.id),
			"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			"proprietes": proprietes,
		})
	return lieux

# Objet.fabriquer sur un catalogue LOCAL a une entree par id (patron
# banc_friction.gd:fabriquer_objets) : la masse est DERIVEE de la composition
# et de data/materiaux.json, jamais recopiee en donnee de banc. La reserve de
# matiere part EGALE a cette masse -- c'est le seul endroit du fichier ou les
# deux grandeurs se touchent, et c'est a la fabrication, la seule ou masse ait
# le droit d'etre lue comme une source. Fabrication REFUSEE (materiau absent,
# fiche sans densite) : objet.gd rend {}, la ressource est simplement absente
# de la scene -- contrat explicite d'objet.gd, verifie avant de lire .id.
static func construire_ressources(config: Dictionary, materiaux: Dictionary) -> Array:
	var catalogue: Dictionary = {}
	for decl in config.ressources:
		catalogue[String(decl.id)] = {"composition": [{"materiau": String(decl.materiau), "volume": float(decl.volume)}]}
	var ressources: Array = []
	for decl in config.ressources:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(
			String(decl.id), String(decl.id),
			Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			catalogue, materiaux)
		if objet.is_empty():
			continue
		_poser_matiere(objet, config, float(objet.proprietes.masse))
		objet.proprietes[String(config.propriete_ressource)] = true
		objet.proprietes[String(config.propriete_valeur)] = float(decl.valeur)
		objet.proprietes[String(config.propriete_depot)] = String(decl.depot)
		objet.proprietes[String(config.propriete_proche)] = bool(decl.get("proche", false))
		ressources.append(objet)
	return ressources

# La reserve de matiere est le SEUL compteur de matiere du banc. Pose ici et
# nulle part ailleurs, pour que « ou vit la matiere » ait une reponse unique.
static func _poser_matiere(objet: Dictionary, config: Dictionary, quantite: float) -> void:
	var reserves: Dictionary = objet.proprietes.get("reserves", {})
	reserves[String(config.nom_reserve_matiere)] = {"reserve": quantite}
	objet.proprietes["reserves"] = reserves

static func _reserve(objet: Dictionary, nom: String) -> float:
	return float(objet.get("proprietes", {}).get("reserves", {}).get(nom, {}).get("reserve", 0.0))

# vitesse_base x (1 - charge/capacite) -- la formule de la consigne, telle
# quelle. Trois precedents litteraux du meme geste (une vitesse effective
# COMPOSEE par le cablage avant BancCommun.bouger_vers, jamais une modulation
# dans le coeur) : banc_friction.gd, banc_faim_thermo.gd, banc_grief.gd.
# max(0.0, ...) : garde defensive, une vitesse negative ferait RECULER le colon
# au lieu de l'arreter. Capacite nulle ou negative (donnee cassee) : 0.0 plutot
# qu'une division par zero -- un porteur sans capacite ne porte rien et ne
# bouge pas, jamais une vitesse infinie.
static func vitesse_effective(vitesse_base: float, charge: float, capacite: float) -> float:
	if capacite <= 0.0:
		return 0.0
	return vitesse_base * max(0.0, 1.0 - charge / capacite)

static func surcout_portage(charge: float, coef: float) -> float:
	return coef * charge

# UNIQUE ECRIVAIN de canal.surcout_action (voir en-tete). MUTE le colon en
# place ; rend la DECOMPOSITION pour que l'affichage la relise sans jamais rien
# recalculer (meme discipline que banc_faim_thermo.gd/banc_emergences.gd).
# Canal absent (config incoherente) : push_error, rien n'est ecrit -- jamais un
# canal invente a la volee.
static func poser_surcout_action(colon: Dictionary, config: Dictionary) -> Dictionary:
	var charge: float = _reserve(colon, String(config.nom_reserve_portage))
	var portage: float = surcout_portage(charge, float(config.colon.coef_surcout_portage))
	var reserves: Dictionary = colon.proprietes.get("reserves", {})
	var nom_energie := String(config.nom_reserve_energie)
	if not reserves.has(nom_energie):
		push_error("banc_economie : canal de reserve '%s' absent du colon, surcout non pose" % nom_energie)
		return {"portage": portage, "total": 0.0, "charge": charge}
	reserves[nom_energie]["surcout_action"] = portage
	return {"portage": portage, "total": portage, "charge": charge}

# Le cout de trajet, en un seul nombre : ce que vaut la chose DIVISE par ce que
# coute d'y aller. Jamais une soustraction -- une valeur et une distance ne
# sont pas dans la meme unite, les retrancher l'une de l'autre n'aurait aucun
# sens et rendrait le seuil dependant de l'echelle des valeurs. Distance nulle
# (colon dessus) : le score vaut la valeur nue, aucun cas particulier.
static func score_rentabilite(saillance: float, distance: float, cout_par_case: float) -> float:
	return saillance / (1.0 + cout_par_case * distance)

# Construit les entrees de saillance depuis la couche 1 (perception.gd, appelee
# telle quelle) -- MEME FORME que Proximite.evaluer ({ chose, type, position,
# saillance }), plus la distance, que le filtre consomme juste apres. Ne retient
# que les choses qui portent la propriete de ressource ET qu'il reste de la
# matiere a prendre : une ressource videe n'est pas une decision a zero, c'est
# une absence de decision (meme contrat que proximite.gd, qui ne rend JAMAIS
# une entree a saillance nulle).
static func resultats_depuis_perceptions(perceptions: Array, config: Dictionary) -> Array:
	var resultats: Array = []
	for entree in perceptions:
		var proprietes: Dictionary = entree.chose.proprietes
		if not bool(proprietes.get(String(config.propriete_ressource), false)):
			continue
		if _reserve(entree.chose, String(config.nom_reserve_matiere)) <= 0.0:
			continue
		resultats.append({
			"chose": entree.chose,
			"type": entree.type,
			"position": entree.position,
			"distance": float(entree.distance),
			"saillance": float(proprietes.get(String(config.propriete_valeur), 0.0)),
		})
	return resultats

# LE GESTE NEUF DU DEPOT (voir en-tete, point 2) : RETIRER des entrees de
# resultats avant dominance.gd. La saillance rendue est le SCORE NET du trajet,
# jamais la valeur nue -- filtrer et ponderer sont ici le meme geste. Rend
# { gardes, retires } plutot que la seule liste gardee : ce qui a ete ecarte
# doit rester lisible (l'ecran le grise, la console le nomme), sans quoi un
# filtre trop severe ressemblerait a une scene vide.
static func filtrer_rentables(resultats: Array, config: Dictionary) -> Dictionary:
	var cout: float = float(config.cout_par_case)
	var seuil: float = float(config.seuil_rentabilite)
	var gardes: Array = []
	var retires: Array = []
	for entree in resultats:
		var score: float = score_rentabilite(float(entree.saillance), float(entree.distance), cout)
		# Dictionary NEUF, jamais entree.duplicate(true) : une copie profonde
		# dupliquerait la CHOSE elle-meme, et dominance.gd rendrait alors des
		# entrees pointant sur des copies mortes que plus rien du monde ne mute.
		var copie: Dictionary = {
			"chose": entree.chose,
			"type": entree.type,
			"position": entree.position,
			"distance": float(entree.distance),
			"saillance": score,
			"valeur_nue": float(entree.saillance),
		}
		if score < seuil:
			retires.append(copie)
			continue
		gardes.append(copie)
	return {"gardes": gardes, "retires": retires}

# Le maximum de ce qui reste VISIBLE apres dominance.gd. Egalite stricte : la
# premiere declaree l'emporte, jamais un RNG (meme depart que
# agir.gd:_verbe_par_poids, sans son alarme -- ici deux scores egaux sont deux
# ressources interchangeables, pas une donnee mal posee).
static func choisir_cible(visibles: Array):
	var meilleure = null
	for entree in visibles:
		if meilleure == null or float(entree.saillance) > float(meilleure.saillance):
			meilleure = entree
	return meilleure

# CHARGER : consommer.gd dans le sens ressource -> colon. Le taux est PRE-BORNE
# par la place restante, et pour une raison de DOMAINE (un porteur plein ne
# prend plus rien), jamais pour se proteger de consommer.gd -- il est
# conservatif par construction depuis sa correction, et demander plus que la
# source ne possede ne cree aucune matiere. Rien dans le coeur ne borne le HAUT
# d'une reserve : le plafond est du cablage, ici comme dans les cinq bancs qui
# plafonnent deja quelque chose.
# CE QUE LE COLON ACCEPTE DE PORTER, et pourquoi ce n'est pas sa capacite : a
# `charge == capacite` la vitesse composee rend EXACTEMENT 0.0 et le colon
# serait cloue au sol (voir vitesse_effective). La capacite reste la grandeur
# qui DIVISE dans la formule -- c'est elle qui dit ce qu'un dos vaut ; la
# fraction dit seulement jusqu'ou ce colon-la remplit le sien. Dans le premier
# jet, aucune ressource ne pesait assez pour atteindre la borne : elle etait
# implicite et une donnee un peu plus grosse l'aurait franchie en silence.
static func charge_max(config: Dictionary) -> float:
	return float(config.colon.capacite_portage) * float(config.colon.fraction_charge_max)

static func charger(ressource: Dictionary, colon: Dictionary, config: Dictionary, delta: float) -> float:
	if delta <= 0.0:
		return 0.0
	var nom_portage := String(config.nom_reserve_portage)
	var place: float = charge_max(config) - _reserve(colon, nom_portage)
	if place <= 0.0:
		return 0.0
	var taux: float = min(float(config.colon.taux_charge), place / delta)
	if taux <= 0.0:
		return 0.0
	return float(Consommer.transferer(
		ressource, colon,
		String(config.nom_reserve_matiere), nom_portage,
		taux, delta).quantite)

# DECHARGER : le MEME appel, source et receveur inverses. Aucun pre-bornage
# ici -- le lieu n'a pas de capacite dans ce banc, et consommer.gd borne
# lui-meme a ce que la charge possede reellement (contre-epreuve de sa
# correction, deja exercee par banc_graisse_accoutumance.gd dans le sens
# famine).
static func decharger(colon: Dictionary, lieu: Dictionary, config: Dictionary, delta: float) -> float:
	if delta <= 0.0:
		return 0.0
	return float(Consommer.transferer(
		colon, lieu,
		String(config.nom_reserve_portage), String(config.nom_reserve_matiere),
		float(config.colon.taux_decharge), delta).quantite)

# LA FONTE. Deux appels a Produit.transformer sur le MEME proprietes_ancien,
# AVANT tout ecrasement -- c'est la condition de l'exactitude : les deux
# rendements portent sur la MEME masse de depart, 0.85 + 0.15 = 1.0. Le
# proprietes_ancien est SYNTHETIQUE ({ "masse": m }) parce que la matiere
# fondue n'est plus un objet mais une reserve accumulee dans le lieu, et parce
# que produit.gd ne lit QUE cette cle dessus (son en-tete). Les deux produits
# sont de VRAIS objets fabriques en cours de partie (Produit.transformer
# delegue a Objet.fabriquer, ce cablage n'ajoute que l'id et la position) --
# patron banc_elimination_salete.gd:fabriquer_dechet. Le lieu est vide dans le
# MEME geste : sans ca, la matiere serait comptee deux fois au tick suivant.
# Rend { produits, compteur_produit } ; produits vide si la reserve est nulle
# ou si produit.gd refuse (rendement nul, type absent) -- jamais un objet a
# masse zero ajoute au Monde.
static func fondre(lieu: Dictionary, config: Dictionary, catalogues: Dictionary, compteur: int) -> Dictionary:
	var nom_matiere := String(config.nom_reserve_matiere)
	var masse: float = _reserve(lieu, nom_matiere)
	if masse <= 0.0:
		return {"produits": [], "compteur_produit": compteur}

	var transformations: Dictionary = catalogues.transformations.get("transformations", {})
	var proprietes_ancien: Dictionary = {"masse": masse}
	var produits: Array = []

	var sorties: Array = [
		{
			"ref": String(config.fonte.transformation_metal),
			"offset": lieu.proprietes.get("offset_lingot", [0.0, 0.0, 0.0]),
			"ressource": true,
		},
		{
			"ref": String(config.fonte.transformation_scories),
			"offset": lieu.proprietes.get("offset_scories", [0.0, 0.0, 0.0]),
			"ressource": false,
		},
	]
	for sortie in sorties:
		if not transformations.has(sortie.ref):
			push_error("banc_economie : transformation '%s' absente du catalogue" % sortie.ref)
			continue
		var produire: Dictionary = transformations[sortie.ref].get("a_zero", {}).get("produire", {})
		var proprietes: Dictionary = Produit.transformer(
			proprietes_ancien, produire, catalogues.types, catalogues.materiaux)
		if proprietes.is_empty():
			continue
		compteur += 1
		var offset: Array = sortie.offset
		# EMPILEMENT : sans ce decalage, six fontes posent six tas au MEME pixel
		# et l'ecran ne montre qu'un seul tas de scories la ou il y en a six.
		# Le rang tourne (modulo) pour ne jamais sortir du terrain, quel que
		# soit le nombre de fontes.
		var rang: int = ((compteur - 1) / 2) % int(config.fonte.rangs_empilement)
		# La pile s'etend DANS LE SENS de son propre offset : les lingots vers
		# la droite de la forge, les scories vers la gauche, jamais les deux
		# tas l'un dans l'autre.
		var decalage := Vector3(signf(float(offset[0])) * float(config.fonte.ecart_empilement) * float(rang), 0.0, 0.0)
		var objet: Dictionary = {
			"id": "%s_%d" % [String(produire.type_produit), compteur],
			"position": lieu.position + Vector3(float(offset[0]), float(offset[1]), float(offset[2])) + decalage,
			"proprietes": proprietes,
		}
		_poser_matiere(objet, config, float(proprietes.masse))
		# Seul le lingot est une ressource : les scories restent au sol pour
		# toujours, non parce qu'un code les y laisse, mais parce qu'elles ne
		# portent pas la propriete que le colon cherche.
		if bool(sortie.ressource):
			objet.proprietes[String(config.propriete_ressource)] = true
			objet.proprietes[String(config.propriete_valeur)] = float(config.fonte.valeur_lingot)
			objet.proprietes[String(config.propriete_depot)] = String(config.fonte.depot_lingot)
			objet.proprietes[String(config.propriete_proche)] = false
		produits.append(objet)

	_poser_matiere(lieu, config, 0.0)
	return {"produits": produits, "compteur_produit": compteur}

# La garde qui evite un lingot par tick pendant tout le dechargement (voir
# en-tete) : on ne fond que ce qui est POSE, jamais ce qui est en train
# d'arriver. Un lieu qui ne fond pas (le grenier) n'est jamais candidat --
# c'est une propriete de donnee, pas un test de nom.
static func fondre_si_pret(lieu: Dictionary, quantite_deposee: float, config: Dictionary, catalogues: Dictionary, compteur: int) -> Dictionary:
	if not bool(lieu.proprietes.get(String(config.propriete_fond), false)):
		return {"produits": [], "compteur_produit": compteur}
	if quantite_deposee > 0.0:
		return {"produits": [], "compteur_produit": compteur}
	if _reserve(lieu, String(config.nom_reserve_matiere)) < float(config.seuil_fonte):
		return {"produits": [], "compteur_produit": compteur}
	return fondre(lieu, config, catalogues, compteur)

# LA MESURE DE CONSERVATION, et le premier appelant reel de somme.gd. Deux
# appels parce que la matiere vit sous DEUX noms de reserve : au sol et dans
# les lieux elle s'appelle 'matiere', sur le dos du colon elle s'appelle
# 'charge_portee' -- un porteur n'est pas un tas. somme.gd ignore
# silencieusement une entite qui ne porte pas la reserve demandee (contrat de
# son en-tete), les deux sommes ne se recouvrent donc jamais.
static func masse_dans_le_monde(monde, colon: Dictionary, config: Dictionary) -> float:
	var objets: Array = BancCommun.objets_de(monde)
	return Somme.reserves(objets, String(config.nom_reserve_matiere)) \
		+ Somme.reserves([colon], String(config.nom_reserve_portage))

# Reconstruction du Monde du neant sans les ids nommes (monde.gd n'a AUCUNE
# fonction de retrait, dette recensee CARTE.md §6 -- meme idiome que
# banc_elimination_salete.gd:monde_sans_dechets/banc_occlusion.gd:monde_du_tick).
# Les choses conservees sont RE-AJOUTEES PAR REFERENCE : l'etat interne du
# colon (sa charge, sa phase, sa cible) traverse la reconstruction intact.
static func monde_sans(monde, ids: Array):
	var restantes: Array = []
	for entree in monde.choses.values():
		if not ids.has(entree.chose.id):
			restantes.append(entree)
	return BancCommun.monde_depuis([{"entrees": restantes}])

# Une ressource videe sort du monde -- sa reserve valant EXACTEMENT 0.0, la
# somme totale ne bouge pas d'un chiffre a ce retrait. C'est la seule raison
# pour laquelle on peut la retirer sans casser le bilan, et c'est pourquoi le
# test le verrouille.
static func ids_ressources_vides(monde, config: Dictionary) -> Array:
	var ids: Array = []
	for entree in monde.choses.values():
		var proprietes: Dictionary = entree.chose.proprietes
		if not bool(proprietes.get(String(config.propriete_ressource), false)):
			continue
		if _reserve(entree.chose, String(config.nom_reserve_matiere)) <= 0.0:
			ids.append(entree.chose.id)
	return ids

# Le seul clic du banc (voir en-tete) : une BASCULE, et non le retrait a sens
# unique du premier jet. DEFAUT TROUVE PAR YAEL A L'ECRAN, et il etait double :
# le colon epuise les deux ressources proches en moins de sept secondes, donc
# passe ce delai le clic ne trouvait plus rien a retirer (il l'ecrivait en
# console, invisible a l'ecran) -- un bouton qui ne fait rien 95% du temps.
# ECARTE, ET LA NOTE QUI LE DISAIT EST CORRIGEE PLUTOT QUE LAISSEE : « un
# retrait n'a rien vers quoi rebasculer » vaut pour un NETTOYAGE
# (banc_elimination_salete.gd, ou la salete est detruite), pas ici -- la
# matiere sortie du plateau existe toujours, elle est seulement ailleurs, et
# elle peut donc revenir. La conservation tient dans les DEUX sens : ce qui
# sort est ajoute a un stock hors plateau, ce qui rentre lui est retire, la
# somme des deux ne bouge jamais.
#
# `hors_plateau` porte les objets sortis, AVEC leur reserve intacte -- jamais
# une reconstruction depuis la declaration, qui les rendrait pleins et creerait
# de la matiere. Rend { monde, hors_plateau, sortis, rentres, masse_delta } ;
# `masse_delta` est SIGNE (positif quand la matiere sort du plateau, negatif
# quand elle y rentre), l'appelant l'ajoute a son compteur sans jamais choisir
# de signe lui-meme.
static func basculer_les_proches(monde, hors_plateau: Array, config: Dictionary) -> Dictionary:
	if not hors_plateau.is_empty():
		var rentres: Array = []
		var masse_rentree := 0.0
		for objet in hors_plateau:
			monde.ajouter(objet, "ressource", objet.position)
			rentres.append(objet.id)
			masse_rentree += _reserve(objet, String(config.nom_reserve_matiere))
		return {"monde": monde, "hors_plateau": [], "sortis": [], "rentres": rentres, "masse_delta": -masse_rentree}

	var sortis: Array = []
	var objets: Array = []
	var masse := 0.0
	for entree in monde.choses.values():
		var proprietes: Dictionary = entree.chose.proprietes
		if not bool(proprietes.get(String(config.propriete_proche), false)):
			continue
		sortis.append(entree.chose.id)
		objets.append(entree.chose)
		masse += _reserve(entree.chose, String(config.nom_reserve_matiere))
	if sortis.is_empty():
		return {"monde": monde, "hors_plateau": [], "sortis": [], "rentres": [], "masse_delta": 0.0}
	# Une cible retiree sous les pieds du colon ne le laisse pas coince : la
	# phase repart de la recherche au tick suivant (voir avancer, PHASE_ALLER),
	# rien a corriger ici.
	return {"monde": monde_sans(monde, sortis), "hors_plateau": objets, "sortis": sortis, "rentres": [], "masse_delta": masse}

# UN TICK COMPLET, l'ordre compris. Statique et sans noeud : le test rejoue
# EXACTEMENT ce que la scene execute, jamais une reconstitution parallele qui
# pourrait deriver (patron banc_grief.gd:avancer/banc_graisse_accoutumance.gd:
# avancer_colon). MUTE colon et monde en place ; rend le monde (reconstruit ou
# non), les produits nes ce tick, les ressources retirees, et de quoi tracer.
#
# L'ORDRE N'EST PAS LIBRE, trois contraintes le fixent :
#   (1) poser_surcout_action AVANT Depense.avancer -- sinon la depense de ce
#       tick utiliserait le surcout du precedent (donc la charge d'avant).
#   (2) la fonte APRES le dechargement -- fondre_si_pret lit ce qui vient
#       d'etre depose CE tick pour savoir si le depot est fini.
#   (3) le retrait des ressources videes EN DERNIER -- une ressource videe ce
#       tick doit d'abord avoir rendu sa matiere au colon, sinon elle sortirait
#       du monde avec, et le bilan baisserait sans raison.
static func avancer(colon: Dictionary, monde, compteur_produit: int, delta: float, config: Dictionary, catalogues: Dictionary) -> Dictionary:
	var decomposition: Dictionary = poser_surcout_action(colon, config)
	Depense.avancer([colon], delta)

	var phase_avant: String = String(colon.phase)
	var perceptions: Array = Perception.percevoir(colon, monde, catalogues.canaux)
	var resultats: Array = resultats_depuis_perceptions(perceptions, config)
	var filtre: Dictionary = filtrer_rentables(resultats, config)
	var visibles: Array = Dominance.visibles(filtre.gardes, colon)

	var depots: Dictionary = {}
	match String(colon.phase):
		PHASE_CHERCHER:
			var cible = choisir_cible(visibles)
			if cible != null:
				colon["cible_id"] = String(cible.chose.id)
				colon["phase"] = PHASE_ALLER
		PHASE_ALLER:
			var vers_cible = _entree_ou_null(monde, String(colon.cible_id))
			if vers_cible == null or _reserve(vers_cible.chose, String(config.nom_reserve_matiere)) <= 0.0:
				colon["phase"] = PHASE_CHERCHER
			elif colon.position.distance_to(vers_cible.chose.position) <= float(config.colon.portee_travail):
				colon["phase"] = PHASE_CHARGER
			else:
				_avancer_vers(colon, vers_cible.chose.position, config, delta)
		PHASE_CHARGER:
			var sur_cible = _entree_ou_null(monde, String(colon.cible_id))
			if sur_cible == null:
				colon["phase"] = PHASE_CHERCHER
			else:
				charger(sur_cible.chose, colon, config, delta)
				var plein: bool = _reserve(colon, String(config.nom_reserve_portage)) >= charge_max(config)
				var vide: bool = _reserve(sur_cible.chose, String(config.nom_reserve_matiere)) <= 0.0
				if plein or vide:
					colon["depot_id"] = String(sur_cible.chose.proprietes.get(String(config.propriete_depot), ""))
					colon["phase"] = PHASE_PORTER
		PHASE_PORTER:
			var vers_depot = _entree_ou_null(monde, String(colon.depot_id))
			if vers_depot == null:
				colon["phase"] = PHASE_CHERCHER
			elif colon.position.distance_to(vers_depot.chose.position) <= float(config.colon.portee_travail):
				colon["phase"] = PHASE_DECHARGER
			else:
				_avancer_vers(colon, vers_depot.chose.position, config, delta)
		PHASE_DECHARGER:
			var sur_depot = _entree_ou_null(monde, String(colon.depot_id))
			if sur_depot == null:
				colon["phase"] = PHASE_CHERCHER
			else:
				depots[String(sur_depot.chose.id)] = decharger(colon, sur_depot.chose, config, delta)
				if _reserve(colon, String(config.nom_reserve_portage)) <= 0.0:
					colon["phase"] = PHASE_CHERCHER

	var produits: Array = []
	for entree in monde.choses.values():
		var resultat_fonte: Dictionary = fondre_si_pret(
			entree.chose, float(depots.get(entree.chose.id, 0.0)), config, catalogues, compteur_produit)
		compteur_produit = int(resultat_fonte.compteur_produit)
		for objet in resultat_fonte.produits:
			produits.append(objet)
	for objet in produits:
		monde.ajouter(objet, "produit", objet.position)

	var retirees: Array = ids_ressources_vides(monde, config)
	if not retirees.is_empty():
		monde = monde_sans(monde, retirees)

	return {
		"monde": monde,
		"compteur_produit": compteur_produit,
		"produits": produits,
		"retirees": retirees,
		"resultats": filtre.gardes,
		"retires": filtre.retires,
		"visibles": visibles,
		"decomposition": decomposition,
		"phase_changee": phase_avant != String(colon.phase),
	}

static func _entree_ou_null(monde, id: String):
	if id == "" or not monde.choses.has(id):
		return null
	return monde.choses[id]

# Le pas, a la vitesse COMPOSEE par la charge -- BancCommun.bouger_vers, jamais
# reimplemente (il borne deja le pas a la distance restante, aucun
# depassement).
static func _avancer_vers(colon: Dictionary, cible: Vector3, config: Dictionary, delta: float) -> void:
	var vitesse: float = vitesse_effective(
		float(colon.proprietes.get(String(config.nom_vitesse), 0.0)),
		_reserve(colon, String(config.nom_reserve_portage)),
		float(config.colon.capacite_portage))
	if vitesse <= 0.0:
		return
	colon.position = BancCommun.bouger_vers(colon.position, cible, vitesse, delta)

# ---- Textes (aucune decision, seulement de la mise en forme) ----

static func texte_total(monde, colon: Dictionary, config: Dictionary, masse_retiree: float, reference: float) -> String:
	var dans_le_monde: float = masse_dans_le_monde(monde, colon, config)
	return "MASSE TOTALE %.3f = monde %.3f + retiree du plateau %.3f   (reference %.3f, ecart %.6f)" % [
		dans_le_monde + masse_retiree, dans_le_monde, masse_retiree, reference,
		absf(dans_le_monde + masse_retiree - reference),
	]

static func texte_colon(colon: Dictionary, config: Dictionary, decomposition: Dictionary) -> String:
	var charge: float = _reserve(colon, String(config.nom_reserve_portage))
	var capacite: float = float(config.colon.capacite_portage)
	var base: float = float(colon.proprietes.get(String(config.nom_vitesse), 0.0))
	return "%s\nphase %s -> %s\ncharge %.1f / %.1f\nvitesse %.1f (base %.1f)\nsurcout portage %.3f\nenergie %.1f" % [
		colon.id, String(colon.phase),
		String(colon.cible_id) if String(colon.phase) in [PHASE_ALLER, PHASE_CHARGER] else String(colon.depot_id),
		charge, capacite,
		vitesse_effective(base, charge, capacite), base,
		float(decomposition.get("portage", 0.0)),
		_reserve(colon, String(config.nom_reserve_energie)),
	]

# La MASSE affichee est celle FABRIQUEE, immuable ; la MATIERE est la reserve,
# qui descend a mesure qu'on la ramasse. Les deux sont montrees cote a cote
# exprès : c'est ce qui rend visible qu'un ramassage ne touche jamais la
# premiere. Un lieu (forge, grenier) n'a ni masse ni composition -- il n'affiche
# alors que ce qu'il contient, jamais un « masse 0.0 » qui se lirait comme une
# absence de matiere.
static func texte_chose(chose: Dictionary, type: String, config: Dictionary, score: float, filtree: bool) -> String:
	var matiere: float = _reserve(chose, String(config.nom_reserve_matiere))
	var masse = chose.proprietes.get("masse")
	var entete: String = "%s [%s]\nmatiere %.1f" % [chose.id, type, matiere]
	if masse != null:
		entete += "  (masse %.1f)" % float(masse)
	if not bool(chose.proprietes.get(String(config.propriete_ressource), false)):
		return entete
	return "%s\nvaleur %.1f -- score %.2f%s" % [
		entete,
		float(chose.proprietes.get(String(config.propriete_valeur), 0.0)),
		score,
		"  (SOUS LE SEUIL)" if filtree else "",
	]

static func ligne_pose(config: Dictionary, reference: float) -> String:
	return "t=0.0 pose : %d ressources, seuil de rentabilite %.2f, cout par case %.3f, capacite de portage %.1f -- masse totale de reference %.3f" % [
		config.ressources.size(), float(config.seuil_rentabilite), float(config.cout_par_case),
		float(config.colon.capacite_portage), reference,
	]

static func ligne_phase(t: float, colon: Dictionary) -> String:
	return "t=%.1f %s : phase %s (cible %s, depot %s)" % [
		t, colon.id, String(colon.phase), String(colon.cible_id), String(colon.depot_id),
	]

static func ligne_produit(t: float, id: String, masse: float) -> String:
	return "t=%.1f FONTE : %s ne du feu, masse %.3f" % [t, id, masse]

static func ligne_epuisee(t: float, id: String) -> String:
	return "t=%.1f %s : epuisee, retiree du monde (reserve exactement 0.0)" % [t, id]

static func ligne_fin(t: float, retires: Array) -> String:
	var noms: Array = []
	for entree in retires:
		noms.append("%s (score %.2f)" % [entree.chose.id, float(entree.saillance)])
	return "t=%.1f PLUS RIEN DE RENTABLE : le colon s'arrete alors qu'il reste de la matiere sous ses yeux -- %s" % [t, ", ".join(noms)]

# Le clic dit TOUJOURS quelque chose, y compris quand il n'a rien trouve : un
# bouton silencieux se lit comme un bouton casse (defaut trouve par Yael a
# l'ecran).
static func ligne_bascule(t: float, bascule: Dictionary) -> String:
	if not bascule.sortis.is_empty():
		return "t=%.1f CLIC : %d ressource(s) proche(s) SORTIE(S) du plateau (%.3f de matiere mise de cote)" % [
			t, bascule.sortis.size(), absf(float(bascule.masse_delta))]
	if not bascule.rentres.is_empty():
		return "t=%.1f CLIC : %d ressource(s) proche(s) REMISE(S) sur le plateau (%.3f de matiere rendue)" % [
			t, bascule.rentres.size(), absf(float(bascule.masse_delta))]
	return "t=%.1f CLIC : rien a sortir -- les ressources proches ont deja ete epuisees par le colon" % t

# L'etat de la bascule se lit A L'ECRAN, jamais seulement en console : c'est ce
# qui manquait quand le clic paraissait ne rien faire.
static func texte_aide(hors_plateau: Array, config: Dictionary, clics: int) -> String:
	var compteur := "clics gauche reçus : %d" % clics
	if hors_plateau.is_empty():
		return "%s\nclic gauche : sortir les ressources proches du plateau -- la grisee reste sous le seuil de rentabilite, le colon n'y va jamais" % compteur
	var noms: Array = []
	for objet in hors_plateau:
		noms.append("%s (%.1f)" % [objet.id, _reserve(objet, String(config.nom_reserve_matiere))])
	return "%s\nHORS PLATEAU : %s -- clic gauche pour les remettre" % [compteur, ", ".join(noms)]

static func ligne_trace(t: float, colon: Dictionary, monde, config: Dictionary, masse_retiree: float, reference: float) -> String:
	return "t=%.1f %s | %s" % [t, String(colon.phase), texte_total(monde, colon, config, masse_retiree, reference)]

# ---- Rendu (impur, Node) -- aucune decision, seulement des noeuds.

func _draw() -> void:
	var fond: Array = _config.couleur_fond
	draw_rect(Rect2(Vector2.ZERO, Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur))),
		Color(float(fond[0]), float(fond[1]), float(fond[2])))

func _construire_rendu() -> void:
	for entree in _monde.choses.values():
		if entree.chose.id == _colon.id:
			continue
		_creer_rendu_chose(entree.chose.id)

	var taille: float = float(_config.taille_colon)
	var brut: Array = _config.couleur_colon
	_noeud_colon = ColorRect.new()
	_noeud_colon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_colon.size = Vector2(taille, taille)
	_noeud_colon.color = Color(float(brut[0]), float(brut[1]), float(brut[2]))
	add_child(_noeud_colon)
	_label_colon = _creer_label(13)
	add_child(_label_colon)

	var couche := CanvasLayer.new()
	add_child(couche)
	_label_total = _creer_label(18)
	_label_total.position = Vector2(10.0, 8.0)
	couche.add_child(_label_total)
	_label_aide = _creer_label(13)
	_label_aide.position = Vector2(10.0, 36.0)
	couche.add_child(_label_aide)

	_poser_camera()

func _creer_rendu_chose(id: String) -> void:
	var entree = _monde.choses.get(id)
	if entree == null:
		return
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(_taille_pour(entree), _taille_pour(entree))
	carre.color = _couleur_pour(entree)
	add_child(carre)
	_noeuds[id] = carre

	var label := _creer_label(12)
	add_child(label)
	_labels[id] = label

func _taille_pour(entree: Dictionary) -> float:
	match String(entree.type):
		"lieu":
			return float(_config.taille_lieu)
		"produit":
			return float(_config.taille_produit)
		_:
			return float(_config.taille_ressource)

func _couleur_pour(entree: Dictionary) -> Color:
	var proprietes: Dictionary = entree.chose.proprietes
	var brut: Array
	if String(entree.type) == "lieu":
		brut = _config.couleur_forge if bool(proprietes.get(String(_config.propriete_fond), false)) else _config.couleur_grenier
	elif String(entree.type) == "produit":
		brut = _config.couleur_lingot if bool(proprietes.get(String(_config.propriete_ressource), false)) else _config.couleur_scories
	else:
		brut = _config.couleur_ressource
	return Color(float(brut[0]), float(brut[1]), float(brut[2]))

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _rafraichir(resultat: Dictionary) -> void:
	# Le score et le statut « filtree » ne sont JAMAIS recalcules ici : ils
	# viennent du tick, deja calcules par filtrer_rentables (meme discipline
	# que banc_faim_thermo.gd, dont le label relit une decomposition).
	var scores: Dictionary = {}
	var filtrees: Dictionary = {}
	for entree in resultat.get("resultats", []):
		scores[entree.chose.id] = float(entree.saillance)
	for entree in resultat.get("retires", []):
		scores[entree.chose.id] = float(entree.saillance)
		filtrees[entree.chose.id] = true

	for id in _noeuds.keys():
		var entree = _monde.choses.get(id)
		if entree == null:
			continue
		var carre: ColorRect = _noeuds[id]
		carre.position = Vector2(entree.chose.position.x, entree.chose.position.y) - carre.size / 2.0
		if filtrees.has(id):
			var terne: Array = _config.couleur_ressource_filtree
			carre.color = Color(float(terne[0]), float(terne[1]), float(terne[2]))
		else:
			carre.color = _couleur_pour(entree)
		var label: Label = _labels[id]
		label.position = carre.position + Vector2(0.0, carre.size.y + 2.0)
		label.text = texte_chose(entree.chose, String(entree.type), _config, float(scores.get(id, 0.0)), filtrees.has(id))

	var centre := Vector2(_colon.position.x, _colon.position.y)
	_noeud_colon.position = centre - _noeud_colon.size / 2.0
	_label_colon.position = centre + Vector2(float(_config.taille_colon), 0.0)
	_label_colon.text = texte_colon(_colon, _config, resultat.get("decomposition", {}))
	_label_total.text = texte_total(_monde, _colon, _config, _masse_retiree, _masse_reference)
	_label_aide.text = texte_aide(_hors_plateau, _config, _clics)

func _poser_camera() -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur)) / 2.0
	camera.zoom = Vector2(0.65, 0.65)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
