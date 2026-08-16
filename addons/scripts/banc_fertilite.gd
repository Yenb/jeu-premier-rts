extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_fertilite.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « fertilite -- le sol
# s'epuise et se refait » (audit_terrain_et_monde_prealable.md §4, verdict
# CABLABLE : aucun .gd neuf). Compose QUATRE mecanismes deja fermes, TOUS
# INCHANGES -- scripts/depense.gd (la fertilite descend), scripts/flux.gd
# (elle remonte par une source ambiante), scripts/consommer.gd (elle remonte
# par un transfert CONSERVE depuis un cadavre), scripts/produit.gd (le
# cadavre epuise devient de l'humus). AUCUN MECANISME DU COEUR TOUCHE.
#
# TERRAIN EN OBJETS ORDINAIRES, meme patron que scripts/banc_ecoulement.gd :
# grille 4x4 de cases-objets { id, position, proprietes } CONSTRUITES A LA
# MAIN (pas Objet.fabriquer -- une case n'a pas de composition), position en
# unites de GRILLE (x=colonne, y=ligne, z=0.0 TOUJOURS, FAIT SPATIAL PUR).
# Les SOURCES (legumineuse, cadavres) sont fabriquees, elles, par
# Objet.fabriquer (elles ont une composition, donc une masse reelle -- sans
# quoi Produit.transformer ne saurait calculer aucun volume d'humus) et
# declarees dans LE MEME repere de grille : portee_flux et l'appariement
# cadavre/case comparent des positions, ils n'auraient aucun sens dans deux
# reperes differents.
#
# LES QUATRE MECANISMES, ET POURQUOI CHACUN EST LE BON :
# - DESCEND -- scripts/depense.gd, un seul appel par tick sur toutes les
#   cases. "cout_base" (par zone, data/banc_fertilite.json) et
#   "surcout_action" (la recolte en cours) ponctionnent le MEME canal, comme
#   absorption+evaporation dans banc_ecoulement.gd. NEUTRALITE DE
#   depense.gd EXPLOITEE, jamais contournee : un cout_base NEGATIF fait
#   REMONTER la reserve (reserve - (cout_base+surcout)*delta), exactement
#   comme un taux_flux negatif fait descendre une reserve dans flux.gd --
#   c'est ainsi que la jachere se refait, sans une ligne de code neuve.
# - REMONTE, SOURCE AMBIANTE -- scripts/flux.gd. La legumineuse porte
#   "fixe_azote"/"taux_flux"/"portee_flux", la case porte "sol", la cible
#   est la reserve "fertilite". flux.gd NE DEPLETE JAMAIS SA SOURCE, ce qui
#   est physiquement correct ici : une legumineuse fixe l'azote de l'AIR,
#   elle ne se vide pas. Table de flux LOCALE au banc (patron
#   banc_conduction.gd/banc_sorts.gd), jamais data/flux.json partage.
# - REMONTE, TRANSFERT CONSERVE -- scripts/consommer.gd. Le cadavre perd une
#   RESERVE NOMMEE ("matiere_organique"), JAMAIS sa masse : masse/volume/
#   densite sont des SORTIES derivees de la composition, interdites en
#   ecriture ailleurs qu'a la fabrication (produit.gd/objet.gd, DENSITE
#   EFFECTIVE). consommer.gd exige que l'appelant ait DEJA apparie source et
#   receveur : "la case sous le cadavre" est une boucle de CABLAGE
#   (case_sous, ci-dessous, comparaison de positions par Portee.en_portee),
#   jamais un mecanisme -- precedent exact banc_manger.gd.
# - TERMINUS -- scripts/produit.gd. Quand "matiere_organique" atteint zero,
#   avancer_transformations (CE FICHIER) lit data/transformations.json:
#   decomposition_cadavre_demo et appelle lui-meme Produit.transformer vers
#   "humus" -- consommer.gd ne transforme JAMAIS lui-meme (meme discipline
#   que frappe.gd), il ne rend qu'un flag "source_epuisee".
#
# LE PLAFOND EST DU CABLAGE, PAS UN MECANISME : depense.gd borne le BAS
# (0.0, bug ferme 2026-08-07) et RIEN dans le coeur ne borne le HAUT -- ni
# flux.gd ni consommer.gd ne connaissent de capacite. "capacite" est donc
# posee sur le canal en donnee mais JAMAIS lue par depense.gd : c'est
# plafonner_fertilite (ci-dessous) qui ecrete apres chaque pas. Le surplus
# est PERDU (un sol sature ne stocke pas plus), et c'est visible : les deux
# cases legumineuse butent a 100 et n'y bougent plus. Aucune case cadavre
# n'ecrete jamais (calibration, voir data/banc_fertilite.json) -- la
# conservation du transfert y reste lisible a l'oeil comme au test.
#
# CE QU'ON DOIT VOIR : 16 cases colorees par leur fertilite (vert fonce =
# fertile, jaune = appauvri, rouge = epuise). Deux cases de RECOLTE (en
# haut a gauche) dont la fertilite chute des qu'on clique dessus pour lancer
# la recolte, et remonte des qu'on re-clique pour l'arreter. Deux cases de
# LEGUMINEUSE dont la fertilite monte jusqu'au plafond et s'y arrete. Deux
# cases de CADAVRE dont la fertilite monte exactement de ce que le cadavre
# pose dessus perd, jusqu'a ce que le cadavre soit vide et devienne un
# humus inerte (couleur et label changent, la case cesse de monter). Les dix
# autres cases sont en JACHERE et remontent lentement. Compteur en haut :
# fertilite moyenne. Trace console par seconde.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et construit grille/sources/
#   rendu. _unhandled_input bascule la recolte au clic. _process appelle
#   UNIQUEMENT avancer() (fonction statique, ci-dessous) et lit son resultat
#   pour l'affichage/la console -- aucune decision dans _process.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_fertilite.gd) : construire_grille/zone_pour_case/
#   fabriquer_sources/table_flux_pour/case_sous/avancer_cadavres/
#   avancer_transformations/basculer_recolte/plafonner_fertilite/
#   fertilite_moyenne/couleur_pour_fertilite/case_la_plus_proche/avancer,
#   plus le texte d'affichage et de log.

const Depense = preload("res://scripts/depense.gd")
const Flux = preload("res://scripts/flux.gd")
const Consommer = preload("res://scripts/consommer.gd")
const Produit = preload("res://scripts/produit.gd")
const Objet = preload("res://scripts/objet.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Portee = preload("res://scripts/portee.gd")

const TAILLE_CASE := 150.0
const MARGE_CASE := 10.0
const TAILLE_SOURCE := 44.0
const INTERVALLE_PRINT := 1.0

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _etats: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _config_produire: Dictionary = {}
var _cases: Array = []
var _sources: Array = []
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _noeuds_sources: Dictionary = {}
var _labels_sources: Dictionary = {}
var _label_compteur: Label
var _temps: float = 0.0
var _prochain_print: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_fertilite.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_etats = _charger_json("res://data/etats.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var transformations: Dictionary = _charger_json("res://data/transformations.json").get("transformations", {})
	_config_produire = transformations.get(_config.transformation_terminale, {}).get("a_zero", {}).get("produire", {})

	# Catalogue LOCAL pour legumineuse/cadavre (jamais data/types.json, meme
	# patron que banc_manger.gd) + le paquet fondateur "objet_physique" et le
	# type produit "humus", tous deux PARTAGES (data/types.json) -- "humus"
	# doit y vivre, "type_produit" y est verifie par test_lint_donnees.gd.
	_catalogue_types = _config.get("types", {}).duplicate(true)
	var types_partages := _charger_json("res://data/types.json")
	_catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	_catalogue_types[_config_produire.get("type_produit", "")] = types_partages.get(_config_produire.get("type_produit", ""), {})

	_cases = construire_grille(_config)
	_sources = fabriquer_sources(_config, _catalogue_types, _materiaux, proprietes_immuables)

	for case in _cases:
		_creer_rendu_case(case)
	for source in _sources:
		_creer_rendu_source(source)

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label_compteur = Label.new()
	_label_compteur.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label_compteur)

	_poser_camera()
	_rafraichir_tout()
	print(_ligne_pose_initiale(_cases, _sources, _config))

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var case: Variant = case_la_plus_proche(_cases, get_global_mouse_position(), TAILLE_CASE)
	if case == null:
		return
	if not basculer_recolte(case, _config):
		return
	print(_ligne_toggle(_temps, case, _config))
	_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var bilan := avancer(_cases, _sources, _config, _etats, _catalogue_types, _materiaux, _config_produire, delta)
	_rafraichir_tout()

	for id in bilan.transformes:
		print(_ligne_transforme(_temps, id, _config_produire.get("type_produit", "")))

	if _temps >= _prochain_print:
		_prochain_print = _temps + INTERVALLE_PRINT
		print(_ligne_trace(_temps, bilan, _cases, _config))

func _rafraichir_tout() -> void:
	for case in _cases:
		_noeuds[case.id].color = couleur_pour_fertilite(_fertilite_de(case, _config), _config)
		_labels[case.id].text = _texte_case(case, _sources, _config)
	for source in _sources:
		_noeuds_sources[source.id].color = _couleur_source(source)
		_labels_sources[source.id].text = _texte_source(source, _config)
	_label_compteur.text = "fertilite moyenne : %.2f / %.2f" % [fertilite_moyenne(_cases, _config), float(_config.capacite)]

# ---- Fonctions PURES, testables headless (voir test_banc_fertilite.gd) ----

# Construit la grille grille_lignes x grille_colonnes, index colonne d'abord
# (position.x=colonne, position.y=ligne, position.z=0.0 TOUJOURS -- voir
# en-tete). Chaque case porte la propriete RECEPTRICE de flux.gd
# (config.propriete_sol) et un canal reserves.<nom_reserve> dont le
# "cout_base" vient de sa zone (NEGATIF = se refait toute seule) et dont
# "capacite" n'est jamais lue par depense.gd (voir en-tete, LE PLAFOND EST
# DU CABLAGE). "surcout_action" part a surcout_recolte sur les cases de
# recolte quand config.recolte_active_au_depart est vrai -- sinon le banc
# s'ouvrirait sur un monde ou rien ne descend, et il faudrait cliquer pour
# voir le phenomene central du chantier. Rend un Array plat, ordre
# ligne-majeur.
static func construire_grille(config: Dictionary) -> Array:
	var lignes: int = config.grille_lignes
	var colonnes: int = config.grille_colonnes
	var cases: Array = []
	var recolte_au_depart: bool = config.get("recolte_active_au_depart", false)
	for ligne in range(lignes):
		for colonne in range(colonnes):
			var zone := zone_pour_case(colonne, ligne, config)
			var surcout: float = float(config.surcout_recolte) if (zone == "recolte" and recolte_au_depart) else 0.0
			cases.append({
				"id": "case_%d_%d" % [colonne, ligne],
				"position": Vector3(float(colonne), float(ligne), 0.0),
				"proprietes": {
					"zone": zone,
					config.propriete_sol: true,
					"reserves": {
						config.nom_reserve: {
							"reserve": float(config.fertilite_initiale),
							"capacite": float(config.capacite),
							"cout_base": float(config.cout_base_par_zone.get(zone, 0.0)),
							"surcout_action": surcout,
							"seuils_ref": "",
						},
					},
				},
			})
	return cases

# Une case appartient a la zone qui liste explicitement son couple
# [colonne, ligne] dans config.zones ; toutes les autres retombent sur
# config.zone_defaut (la jachere). Nommer des zones est le seul nommage de
# categorie qu'un banc jetable s'autorise (CLAUDE.md, « un banc jetable peut
# nommer une categorie pour poser une scene d'observation ») -- aucun
# mecanisme du coeur ne lit jamais "zone".
static func zone_pour_case(colonne: int, ligne: int, config: Dictionary) -> String:
	for zone in config.zones:
		for couple in config.zones[zone]:
			if int(couple[0]) == colonne and int(couple[1]) == ligne:
				return String(zone)
	return String(config.zone_defaut)

# Fabrique les sources (legumineuse, cadavres) via Objet.fabriquer --
# catalogue LOCAL, composition fusionnee, MASSE REELLE calculee (requise par
# Produit.transformer). Chaque source garde son "role" (String, propre a CE
# banc, jamais lue par le coeur : "flux" ou "cadavre") et son type d'origine
# sous "proprietes_type" -- seul moyen pour ce fichier de savoir, apres
# transformation, qu'un objet est devenu de l'humus sans comparer un nom en
# dur (patron banc_manger.gd).
static func fabriquer_sources(config: Dictionary, table_types: Dictionary, materiaux: Dictionary, proprietes_immuables: Array) -> Array:
	var sources: Array = []
	for decl in config.get("sources", []):
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.type, Vector3(pos[0], pos[1], pos[2]), table_types, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet["proprietes_type"] = decl.type
		objet["role"] = decl.role
		sources.append(objet)
	return sources

# Table de flux LOCALE au banc, UNE ligne (patron banc_conduction.gd/
# banc_sorts.gd) -- jamais data/flux.json, catalogue partage qu'aucun autre
# banc de terrain n'utilise. Aucun nom n'est en dur : les trois viennent de
# la donnee.
static func table_flux_pour(config: Dictionary) -> Array:
	return [{
		"source": config.propriete_fixation,
		"receptrice": config.propriete_sol,
		"cible": config.nom_reserve,
	}]

# APPARIEMENT SOURCE/RECEVEUR, exige par consommer.gd (qui ne cherche
# jamais lui-meme sa paire) : rend la case dont la position de grille
# coincide avec celle de l'objet, a portee_appariement pres (comparaison
# deleguee a Portee.en_portee, jamais reimplementee). Rend null si aucune --
# un cadavre pose hors grille ne fertilise rien, cas neutre legitime.
static func case_sous(objet: Dictionary, cases: Array, portee_appariement: float) -> Variant:
	for case in cases:
		if Portee.en_portee(case.position, objet.position, portee_appariement):
			return case
	return null

# UN PAS de decomposition, une fois par cadavre. taux = taux_decomposition_
# base * biodegradabilite EFFECTIVE (EtatEffectif.valeur, JAMAIS
# reimplementee -- ce banc ne pose aucun etat, mais un futur etat qui
# ecraserait la biodegradabilite arreterait la decomposition sans une ligne
# de code ici, exactement comme "pourri" arrete un repas dans
# banc_manger.gd). Rend un Array de { id, case_id, source_epuisee } -- un
# cadavre deja transforme (plus aucune reserve source) rend
# source_epuisee=false par consommer.gd lui-meme, donc n'est jamais
# retransforme.
#
# BUG CONNU DE consommer.gd, CONTOURNE ICI SANS LE TOUCHER (meme geste
# exact que scripts/ecoulement.gd, voir CARTE.md §2 : « ecoulement.gd
# pre-borne quantite lui-meme avant tout appel ») : Consommer.transferer
# credite au receveur la quantite DEMANDEE (taux*delta), pas la quantite
# reellement retiree a la source une fois bornee a zero -- au DERNIER pas
# d'un cadavre presque vide, le sol gagnerait plus que le cadavre ne perd,
# et la conservation serait fausse. TROUVE PAR LE TEST de ce chantier, pas
# suppose : le sol recevait 6.08 pour un cadavre de 6.0. Ce fichier borne
# donc lui-meme la quantite a la reserve restante et passe delta=1.0, la
# quantite etant deja resolue -- consommer.gd reste INCHANGE.
static func avancer_cadavres(sources: Array, cases: Array, config: Dictionary, etats: Dictionary, delta: float) -> Array:
	var bilans: Array = []
	for source in sources:
		if source.get("role", "") != "cadavre":
			continue
		var case: Variant = case_sous(source, cases, float(config.portee_appariement))
		if case == null:
			continue
		var biodegradabilite: float = EtatEffectif.valeur(source, config.propriete_biodegradabilite, etats)
		var taux: float = float(config.taux_decomposition_base) * biodegradabilite
		# Demande NUE -- voir l'en-tete de consommer.gd.
		var resultat := Consommer.transferer(source, case, config.nom_reserve_cadavre, config.nom_reserve, taux * delta, 1.0)
		bilans.append({
			"id": source.id,
			"case_id": case.id,
			"source_epuisee": resultat.source_epuisee,
		})
	return bilans

# Transforme en humus tout cadavre dont la reserve source est a zero
# (Produit.transformer, INCHANGE, meme geste proprietes.clear()+merge() que
# banc_manger.gd/banc_coupe.gd). IDEMPOTENT SANS MARQUEUR SUPPLEMENTAIRE :
# le garde est la PRESENCE de la reserve elle-meme -- une fois transformee,
# "reserves" disparait entierement, le second appel ne retrouve plus jamais
# "matiere_organique". Rend l'Array des ids reellement transformes ce pas.
static func avancer_transformations(sources: Array, config: Dictionary, config_produire: Dictionary, table_types: Dictionary, materiaux: Dictionary) -> Array:
	var transformes: Array = []
	for source in sources:
		if source.get("role", "") != "cadavre":
			continue
		var reserves: Dictionary = source.proprietes.get("reserves", {})
		if not reserves.has(config.nom_reserve_cadavre):
			continue
		if float(reserves[config.nom_reserve_cadavre].get("reserve", 0.0)) > 0.0:
			continue
		var nouvelles_proprietes: Dictionary = Produit.transformer(source.proprietes, config_produire, table_types, materiaux)
		if nouvelles_proprietes.is_empty():
			continue
		source.proprietes.clear()
		source.proprietes.merge(nouvelles_proprietes, true)
		source["proprietes_type"] = config_produire.get("type_produit", "")
		transformes.append(source.id)
	return transformes

# Toggle de la recolte au clic : pose surcout_recolte comme "surcout_action"
# du canal, ou le remet a 0.0. Ne fait rien (rend false) sur une case qui
# n'est pas de la zone recolte -- une jachere ne se recolte pas.
static func basculer_recolte(case: Dictionary, config: Dictionary) -> bool:
	if case.proprietes.get("zone", "") != "recolte":
		return false
	var canal: Dictionary = case.proprietes.reserves[config.nom_reserve]
	var actif: bool = float(canal.get("surcout_action", 0.0)) > 0.0
	canal["surcout_action"] = 0.0 if actif else float(config.surcout_recolte)
	return true

# ECRETAGE AU PLAFOND -- du cablage, jamais un mecanisme (voir en-tete) :
# depense.gd ne borne que le BAS, ni flux.gd ni consommer.gd ne connaissent
# de capacite. Rend le TOTAL ecrete ce pas (surplus perdu, jamais reverse
# ailleurs), pour la trace.
static func plafonner_fertilite(cases: Array, config: Dictionary) -> float:
	var ecrete := 0.0
	var capacite: float = float(config.capacite)
	for case in cases:
		var canal: Dictionary = case.proprietes.reserves[config.nom_reserve]
		var reserve: float = float(canal.get("reserve", 0.0))
		if reserve > capacite:
			ecrete += reserve - capacite
			canal["reserve"] = capacite
	return ecrete

static func fertilite_moyenne(cases: Array, config: Dictionary) -> float:
	if cases.is_empty():
		return 0.0
	var total := 0.0
	for case in cases:
		total += _fertilite_de(case, config)
	return total / float(cases.size())

# LE PAS COMPLET, seul appele par _process (qui ne calcule jamais rien
# lui-meme). Ordre FIXE et voulu : flux (la source ambiante donne) ->
# depense (l'etat et l'action ponctionnent, ou rendent si cout_base est
# negatif) -> consommer (le cadavre transfere) -> transformation (le cadavre
# vide devient humus) -> ecretage au plafond, EN DERNIER, pour qu'aucun des
# trois apports ne puisse laisser une case au-dessus de sa capacite.
# Rend { transferts, transformes, ecrete, moyenne } -- diagnostic de trace,
# jamais relu comme une source de verite.
static func avancer(
	cases: Array,
	sources: Array,
	config: Dictionary,
	etats: Dictionary,
	table_types: Dictionary,
	materiaux: Dictionary,
	config_produire: Dictionary,
	delta: float,
) -> Dictionary:
	var monde_flux: Array = cases + sources
	Flux.avancer(monde_flux, table_flux_pour(config), delta)
	Depense.avancer(cases, delta, {})
	var transferts := avancer_cadavres(sources, cases, config, etats, delta)
	var transformes := avancer_transformations(sources, config, config_produire, table_types, materiaux)
	var ecrete := plafonner_fertilite(cases, config)
	return {
		"transferts": transferts,
		"transformes": transformes,
		"ecrete": ecrete,
		"moyenne": fertilite_moyenne(cases, config),
	}

# Vert fonce (fertile, au plafond) -> jaune (appauvri, a mi-capacite) ->
# rouge (epuise, a zero), deux interpolations lineaires successives.
# capacite <= 0.0 : rend la couleur epuisee, jamais une division par zero.
static func couleur_pour_fertilite(fertilite: float, config: Dictionary) -> Color:
	var couleurs: Dictionary = config.couleurs
	var fertile := _couleur(couleurs.fertile)
	var appauvri := _couleur(couleurs.appauvri)
	var epuise := _couleur(couleurs.epuise)
	var capacite: float = float(config.capacite)
	if capacite <= 0.0:
		return epuise
	var ratio: float = clamp(fertilite / capacite, 0.0, 1.0)
	if ratio >= 0.5:
		return appauvri.lerp(fertile, (ratio - 0.5) * 2.0)
	return epuise.lerp(appauvri, ratio * 2.0)

# Retrouve la case dont la position de GRILLE (convertie en pixels par
# taille_case) est la plus proche de "position_ecran". Rend null si "cases"
# est vide (chemin mort, jamais atteint en jeu reel). Recopie du meme geste
# que banc_ecoulement.gd:case_la_plus_proche -- deux bancs jetables ne se
# referencent jamais entre eux.
static func case_la_plus_proche(cases: Array, position_ecran: Vector2, taille_case: float) -> Variant:
	if cases.is_empty():
		return null
	var meilleure: Variant = null
	var meilleure_distance := INF
	for case in cases:
		var pos: Vector3 = case.position
		var distance: float = (Vector2(pos.x, pos.y) * taille_case).distance_to(position_ecran)
		if distance < meilleure_distance:
			meilleure_distance = distance
			meilleure = case
	return meilleure

# Cle courte de la source ACTIVE sur cette case, pour le label : la recolte
# d'abord (elle domine tout), puis une source de flux a portee, puis un
# cadavre encore plein pose dessus, sinon rien. Lecture seule, jamais une
# decision.
static func source_active(case: Dictionary, sources: Array, config: Dictionary) -> String:
	var canal: Dictionary = case.proprietes.reserves[config.nom_reserve]
	if float(canal.get("surcout_action", 0.0)) > 0.0:
		return "recolte"
	for source in sources:
		var proprietes: Dictionary = source.proprietes
		if proprietes.get(config.propriete_fixation, false) \
				and Portee.en_portee(case.position, source.position, float(proprietes.get("portee_flux", 0.0))):
			return "legumineuse"
		var reserve_cadavre: float = float(proprietes.get("reserves", {}).get(config.nom_reserve_cadavre, {}).get("reserve", 0.0))
		if reserve_cadavre > 0.0 and Portee.en_portee(case.position, source.position, float(config.portee_appariement)):
			return "cadavre"
	return "aucune"

static func _fertilite_de(case: Dictionary, config: Dictionary) -> float:
	return float(case.proprietes.reserves.get(config.nom_reserve, {}).get("reserve", 0.0))

static func _couleur(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])

static func _texte_case(case: Dictionary, sources: Array, config: Dictionary) -> String:
	return "%s\nfertilite=%.1f\nzone=%s\nsource=%s" % [
		case.id, _fertilite_de(case, config), case.proprietes.get("zone", "?"),
		source_active(case, sources, config),
	]

static func _texte_source(source: Dictionary, config: Dictionary) -> String:
	var reserves: Dictionary = source.proprietes.get("reserves", {})
	if reserves.has(config.nom_reserve_cadavre):
		return "%s\n%s=%.2f" % [source.id, config.nom_reserve_cadavre, float(reserves[config.nom_reserve_cadavre].get("reserve", 0.0))]
	if source.proprietes.get(config.propriete_fixation, false):
		return "%s\ntaux_flux=%.2f" % [source.id, float(source.proprietes.get("taux_flux", 0.0))]
	return "%s\n%s" % [source.id, source.get("proprietes_type", "?")]

static func _ligne_pose_initiale(cases: Array, sources: Array, config: Dictionary) -> String:
	return "t=0.0 grille posee : %d cases, %d sources, fertilite moyenne=%.2f" % [
		cases.size(), sources.size(), fertilite_moyenne(cases, config),
	]

static func _ligne_toggle(t: float, case: Dictionary, config: Dictionary) -> String:
	var actif: bool = float(case.proprietes.reserves[config.nom_reserve].get("surcout_action", 0.0)) > 0.0
	return "t=%.1f recolte %s sur %s (fertilite=%.1f)" % [
		t, "LANCEE" if actif else "ARRETEE", case.id, _fertilite_de(case, config),
	]

static func _ligne_transforme(t: float, id: String, type_produit: String) -> String:
	return "t=%.1f %s : matiere_organique epuisee, transforme en %s" % [t, id, type_produit]

static func _ligne_trace(t: float, bilan: Dictionary, cases: Array, config: Dictionary) -> String:
	var extremes := _extremes(cases, config)
	return "t=%.1f moyenne=%.2f min=%.2f (%s) max=%.2f (%s) transferts=%d ecrete=%.3f" % [
		t, bilan.moyenne, extremes.min_valeur, extremes.min_id, extremes.max_valeur, extremes.max_id,
		bilan.transferts.size(), bilan.ecrete,
	]

static func _extremes(cases: Array, config: Dictionary) -> Dictionary:
	var min_valeur := INF
	var max_valeur := -INF
	var min_id := "?"
	var max_id := "?"
	for case in cases:
		var f := _fertilite_de(case, config)
		if f < min_valeur:
			min_valeur = f
			min_id = case.id
		if f > max_valeur:
			max_valeur = f
			max_id = case.id
	return {"min_valeur": min_valeur, "min_id": min_id, "max_valeur": max_valeur, "max_id": max_id}

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _couleur_source(source: Dictionary) -> Color:
	var type: String = source.get("proprietes_type", "")
	var rgb: Array = _config.couleurs.get(type, _config.couleurs.get("cadavre", [1.0, 1.0, 1.0]))
	return _couleur(rgb)

func _creer_rendu_case(case: Dictionary) -> void:
	var centre := Vector2(case.position.x, case.position.y) * TAILLE_CASE
	var taille_visible := TAILLE_CASE - MARGE_CASE

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(taille_visible, taille_visible)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[case.id] = noeud

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = centre - Vector2(taille_visible / 2.0 - 4.0, taille_visible / 2.0 - 4.0)
	add_child(label)
	_labels[case.id] = label

func _creer_rendu_source(source: Dictionary) -> void:
	var centre := Vector2(source.position.x, source.position.y) * TAILLE_CASE

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE_SOURCE, TAILLE_SOURCE)
	noeud.position = centre - noeud.size / 2.0 + Vector2(0.0, 30.0)
	add_child(noeud)
	_noeuds_sources[source.id] = noeud

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = centre + Vector2(-TAILLE_SOURCE / 2.0, 30.0 + TAILLE_SOURCE / 2.0)
	add_child(label)
	_labels_sources[source.id] = label

func _poser_camera() -> void:
	var centre := Vector2(float(_config.grille_colonnes - 1), float(_config.grille_lignes - 1)) * TAILLE_CASE / 2.0
	var camera := Camera2D.new()
	camera.position = centre
	camera.zoom = Vector2(0.75, 0.75)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
