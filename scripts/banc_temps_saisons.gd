extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_temps_saisons.tscn, PAS la scene
# principale). Compose TREIZE mecanismes deja fermes, TOUS INCHANGES :
# horloge.gd, flux.gd, conditions.gd, depense.gd, charge.gd, seuil_etat.gd,
# somme.gd, croyance.gd, perception.gd, propagation.gd, extinction.gd,
# produit.gd, objet.gd (+ monde.gd, lumiere.gd, banc_commun.gd). AUCUN .gd du
# coeur n'est ecrit ici, et AUCUNE mecanique neuve : ce fichier fait tenir
# ensemble des bancs qui existaient deja.
#
# QUATRE FILS, UN SEUL MONDE
#
# 1. DEUX DEBITS SUR LA MEME RESERVE. flux.gd ADDITIONNE au lieu d'ecrire :
#    deux lignes de table visant la meme cible se composent sans se connaitre.
#    La ligne RAPIDE part chaque tick avec le delta reel ; la ligne LENTE part
#    UNE FOIS par changement de saison avec delta 1.0, sa quantite etant deja
#    resolue (patron banc_fertilite.gd:avancer_cadavres). Son emetteur porte
#    un taux NEGATIF -- flux.gd est neutre, il transfere dans les deux sens.
#    Le changement de saison se lit en comparant le nom rendu par horloge.gd a
#    celui garde sur l'entite calendrier (patron
#    banc_temps_anticipation.gd:compter_cycles).
#
# 2. LA PERTURBATION EST UNE ABSENCE DE DONNEE. conditions.gd ne compare que
#    des NOMBRES : un nom de saison y vaudrait zero et la comparaison
#    reussirait ou echouerait sans bruit. Le cablage ecrit donc trois miroirs
#    0.0/1.0 sur chaque plante, unique ecrivain, toujours presents. Sauter la
#    saison froide, c'est ne pas ecrire son miroir cette annee-la : rien n'est
#    pose, la ligne lente ne trouve aucun receveur, les reserves ne descendent
#    pas. L'annee volcanique ecrit un miroir de plus et une entree a DEUX
#    conditions en ET pose alors deux cles supplementaires.
#    QUAND ces annees tombent vient d'un ACCUMULATEUR PLAT plus seuil_etat.gd
#    (seuil LU PAR OBJET, catalogue local), remis a zero par le cablage apres
#    usage : une cadence rejouable, jamais un tirage.
#
# 3. LA CONTAGION. Le moral est un CHAMP DERIVE recalcule a neuf chaque tick,
#    jamais un cumul (patron banc_bonheur.gd:poser_bonheur) : somme ponderee
#    des sources que ce colon valorise, moins la penalite de zone. Un colon
#    sous le seuil devient une CAUSE a sa position, charge.gd accumule sur les
#    colons a portee de leur canal (patron banc_maladie.gd:causes_de_porteurs),
#    et le marqueur pose est recopie en miroir 0.0/1.0 avant d'etre compare --
#    charge.gd efface ses cles en redescendant, seuil_etat.gd sort sans rien
#    faire sur une propriete absente. UN SEUL canal par colon : la meme liste
#    de causes irait a tous les canaux d'une meme chose.
#
# 4. L'HISTOIRE. Un objet fabrique en cours de partie porte une copie PROFONDE
#    des croyances de son auteur (patron
#    banc_affordances_connaissance.gd:fabriquer_livre) ; sans la copie
#    profonde, l'objet suivrait ce que l'auteur apprend ensuite et ne figerait
#    rien. Un lecteur verse ce registre par Croyance.corriger, la fidelite
#    servant de credibilite. La fierte est le PRODUIT de deux parts
#    recalculees a neuf -- ce qui a ete lu, ce qui reste lisible -- et devient
#    une source de plus dans la somme du moral. Bruler passe par
#    propagation.gd (le feu saute de rayonnage en rayonnage), extinction.gd
#    (un agent a portee de travail peut sauver ce qu'il touche) et depense.gd
#    (deux paliers : illisible, puis consume) ; au second palier le cablage
#    appelle lui-meme Produit.transformer puis vide et remplit proprietes
#    (patron banc_fertilite.gd:avancer_transformations), depense.gd n'ayant
#    aucune branche qui produise. Les croyances deja acquises survivent sur
#    les lecteurs et ne partent que par l'oubli de croyance.gd.
#
# CE QUE CE BANC NE MONTRE PAS : personne ne decide ni ne se deplace -- ni
# proximite.gd, ni dominance.gd, ni agir.gd. SEUL L'AUTEUR OBSERVE le monde ;
# les autres n'apprennent que par la lecture, sans quoi ils sauraient deja
# tout et la transmission ne se verrait pas. Aucun hasard nulle part.
#
# LE FANTOME : une chose dont proprietes a ete vide alarmerait indefiniment
# dans tout mecanisme qui traite une propriete comme structurelle. Le filtre
# vit au cablage (monde_vivant, patron banc_soudure.gd), jamais dans un
# mecanisme.
#
# Deux moities : le Node charge les catalogues, construit, bascule au clic et
# au clavier, appelle avancer() et redessine ; tout le reste est statique et
# testable headless (voir test_banc_temps_saisons.gd).

const Horloge = preload("res://scripts/horloge.gd")
const Lumiere = preload("res://scripts/lumiere.gd")
const Flux = preload("res://scripts/flux.gd")
const Conditions = preload("res://scripts/conditions.gd")
const Depense = preload("res://scripts/depense.gd")
const Charge = preload("res://scripts/charge.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Somme = preload("res://scripts/somme.gd")
const Croyance = preload("res://scripts/croyance.gd")
const Perception = preload("res://scripts/perception.gd")
const Propagation = preload("res://scripts/propagation.gd")
const Extinction = preload("res://scripts/extinction.gd")
const Produit = preload("res://scripts/produit.gd")
const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const TAILLE_POLICE_LABEL := 13
const TAILLE_POLICE_ENTETE := 20
const LARGEUR_CERCLE := 2.0

var _config: Dictionary = {}
var _textes: Dictionary = {}
var _catalogues: Dictionary = {}

var _etat: Dictionary = {}
var _temps := 0.0
var _prochaine_trace := 0.0
var _dernier: Dictionary = {}

var _couche_ui: CanvasLayer
var _fond: ColorRect
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres: Dictionary = {}
var _cercles: Dictionary = {}
var _label_entete: Label
var _label_compteur: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger("res://data/banc_temps_saisons.json")
	_textes = _charger("res://data/textes.json")
	_catalogues = {
		"canaux": _charger("res://data/canaux.json"),
		"croyances": _charger("res://data/croyances.json"),
		"lumiere": _charger("res://data/lumiere.json"),
		"materiaux": _charger("res://data/materiaux.json"),
		"menaces": _charger("res://data/menaces.json"),
		"seuils_etat": _charger("res://data/seuils_etat.json"),
		"seuils_reserve": _charger("res://data/seuils_combustible.json"),
		"transformations": _charger("res://data/transformations.json").get("transformations", {}),
		"types": _table_de_fabrication(_charger("res://data/types.json"), _config),
	}
	_etat = etat_initial(_config)

	_couche_ui = CanvasLayer.new()
	add_child(_couche_ui)
	_creer_rendu()
	_poser_camera()
	print(ligne_pose(_config))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			forcer_saut_saison_froide(_etat.calendrier, _config)
			print(ligne_forcage(_temps, texte(String(_config.cle_annee_sans_hiver), _config, _textes)))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			forcer_saison_volcanique(_etat.calendrier, _config)
			print(ligne_forcage(_temps, texte(String(_config.cle_annee_volcanique), _config, _textes)))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			print(ligne_brasier(_temps, basculer_brasier(_etat, _config)))
		elif event.keycode == KEY_M:
			print(ligne_choc(_temps, String(_config.colon_choque), basculer_serenite(_etat.colons, _config)))

func _process(delta: float) -> void:
	_temps += delta
	var bilan := avancer(_etat, _config, _catalogues, delta, _temps)
	_dernier = bilan
	for ligne in lignes_evenements(_temps, bilan, _config, _textes):
		print(ligne)
	if _temps >= _prochaine_trace:
		_prochaine_trace = _temps + float(_config.periode_trace_s)
		print(ligne_trace(_temps, bilan))
	_rafraichir_tout()

# ---------------------------------------------------------------------------
# Construction (pures)
# ---------------------------------------------------------------------------

# La table passee a Objet.fabriquer et a Produit.transformer : les types
# LOCAUX du banc, plus le paquet fondateur et le type produit pris au
# catalogue PARTAGE -- ce dernier doit y vivre, son nom y est verifie par le
# linter (patron banc_fertilite.gd:_ready).
static func _table_de_fabrication(types_partages: Dictionary, config: Dictionary) -> Dictionary:
	var table: Dictionary = config.get("types_locaux", {}).duplicate(true)
	table["objet_physique"] = types_partages.get("objet_physique", {})
	var produit := String(config.produire_cendre.type_produit)
	table[produit] = types_partages.get(produit, {})
	return table

# Le calendrier est une entite comme une autre : deux accumulateurs plats,
# deux seuils LUS PAR OBJET, le couple qu'attend seuil_etat.gd, et la
# derniere saison observee (une String, donc resumable en JSON, jamais un
# champ de Node). 'derniere_saison' part VIDE : le premier passage l'inscrit
# sans compter un changement qui n'a pas eu lieu.
static func construire_calendrier(config: Dictionary) -> Dictionary:
	var decl: Dictionary = config.calendrier
	var pos: Array = decl.position
	return {
		"id": String(decl.id),
		"position": Vector3(pos[0], pos[1], pos[2]),
		"proprietes": {
			"derniere_saison": "",
			"annees_ecoulees": 0.0,
			"annees_depuis_saut": float(decl.compte_saut_initial),
			"seuil_saut_hiver": float(decl.seuil_saut_hiver),
			"annees_depuis_volcan": float(decl.compte_volcan_initial),
			"seuil_hiver_volcanique": float(decl.seuil_hiver_volcanique),
			"annee_sans_hiver": 0.0,
			"annee_volcanique": 0.0,
			"etats_actifs": [],
			"seuils_etat_memoire": {},
		},
	}

# Une plante porte sa reserve (canal complet, capacite comprise -- flux.gd
# n'en creerait qu'un minimal), les TROIS miroirs de saison initialises a
# 0.0 (une propriete absente fait ECHOUER sa condition, jamais reussir) et
# la seule propriete que l'auteur peut observer.
static func construire_plantes(config: Dictionary) -> Array:
	var plantes: Array = []
	for decl in config.plantes:
		var pos: Array = decl.position
		var proprietes: Dictionary = {
			"reserves": {
				String(config.nom_reserve_vegetale): {
					"reserve": float(config.reserve_vegetale_initiale),
					"capacite": float(config.capacite_vegetale),
					"cout_base": 0.0,
					"surcout_action": 0.0,
					"seuils_ref": "",
				},
			},
		}
		proprietes[String(config.miroir_saison_pousse)] = 0.0
		proprietes[String(config.miroir_saison_froide)] = 0.0
		proprietes[String(config.miroir_volcanique)] = 0.0
		proprietes[String(config.propriete_comestible)] = true
		plantes.append({"id": String(decl.id), "position": Vector3(pos[0], pos[1], pos[2]), "proprietes": proprietes})
	return plantes

# Chaque emetteur porte SON taux et SA portee (flux.gd les lit sur la source,
# jamais dans la table) -- c'est ce qui garde les deux debits separables.
static func construire_sources(config: Dictionary) -> Array:
	var sources: Array = []
	for decl in config.sources_flux:
		var pos: Array = decl.position
		var proprietes: Dictionary = {"taux_flux": float(decl.taux_flux), "portee_flux": float(decl.portee_flux)}
		proprietes[String(decl.propriete)] = true
		sources.append({"id": String(decl.id), "position": Vector3(pos[0], pos[1], pos[2]), "proprietes": proprietes})
	return sources

# Colons CONSTRUITS A LA MAIN : ni composition ni materiau, data/types.json
# n'est donc pas touche. 'rythme' n'est pose QUE s'il est strictement positif
# -- BancCommun.agents_rythme retient toute chose qui porte la cle, un
# spectateur a rythme nul serait un agent inutile dans la liste.
static func construire_colons(config: Dictionary) -> Array:
	var colons: Array = []
	for decl in config.colons:
		var pos: Array = decl.position
		var proprietes: Dictionary = {
			"canaux": [String(config.nom_canal_vue)],
			"canaux_config": {String(config.nom_canal_vue): config.canal_vue.duplicate(true)},
			"croyances": {},
			"chroniques_lues": [],
			"etats_actifs": [],
			"seuils_etat_memoire": {},
			"etats": {String(config.nom_canal_contagion): config.canal_contagion.duplicate(true)},
		}
		proprietes[String(config.nom_poids_moral)] = decl.poids_moral.duplicate(true)
		proprietes[String(config.source_serenite)] = float(config.serenite_pleine)
		proprietes[String(config.source_abondance)] = 0.0
		proprietes[String(config.source_fierte)] = 0.0
		proprietes[String(config.nom_miroir_contagion)] = 0.0
		if float(decl.rythme) > 0.0:
			proprietes["rythme"] = float(decl.rythme)
		var colon: Dictionary = {
			"id": String(decl.id),
			"position": Vector3(pos[0], pos[1], pos[2]),
			"proprietes": proprietes,
			"auteur": bool(decl.auteur),
			"prochaine_observation": 0.0,
			"prochaine_lecture": 0.0,
		}
		colons.append(colon)
	return colons

static func construire_objets(config: Dictionary) -> Array:
	var pupitre: Dictionary = config.pupitre
	var brasier: Dictionary = config.brasier
	var pos_p: Array = pupitre.position
	var pos_b: Array = brasier.position
	var proprietes_brasier: Dictionary = {}
	proprietes_brasier[String(brasier.propriete_dangereux)] = true
	return [
		{"id": String(pupitre.id), "position": Vector3(pos_p[0], pos_p[1], pos_p[2]), "proprietes": {}},
		{"id": String(brasier.id), "position": Vector3(pos_b[0], pos_b[1], pos_b[2]), "proprietes": proprietes_brasier},
	]

static func etat_initial(config: Dictionary) -> Dictionary:
	var plantes := construire_plantes(config)
	var sources := construire_sources(config)
	var colons := construire_colons(config)
	var objets := construire_objets(config)
	var monde = BancCommun.monde_depuis([
		{"choses": plantes, "type": "plante"},
		{"choses": objets, "type": "objet"},
		{"choses": colons, "type": "colon"},
	])
	return {
		"calendrier": construire_calendrier(config),
		"plantes": plantes,
		"sources": sources,
		"colons": colons,
		"objets": objets,
		"chroniques": [],
		"monde": monde,
		"exposition": {},
	}

static func chose_par_id(choses: Array, id: String) -> Dictionary:
	for chose in choses:
		if String(chose.id) == id:
			return chose
	return {}

# Filtre les choses dont proprietes a ete vide (patron
# banc_soudure.gd:_monde_vivant) : une propriete STRUCTURELLE absente fait
# alarmer indefiniment le mecanisme qui la lit, et le filtre appartient a
# l'appelant, jamais au mecanisme.
static func monde_vivant(choses: Array) -> Array:
	var vivantes: Array = []
	for chose in choses:
		if not chose.proprietes.is_empty():
			vivantes.append(chose)
	return vivantes

# ---------------------------------------------------------------------------
# Le temps du monde et ses deux debits
# ---------------------------------------------------------------------------

static func heure_du_jour(temps: float, config: Dictionary) -> float:
	var cycle: Dictionary = config.cycle
	return Horloge.heure(temps, float(cycle.duree_jour_secondes), float(cycle.heures_par_jour), float(cycle.heure_depart))

static func saison_courante(temps: float, config: Dictionary) -> String:
	var cycle: Dictionary = config.cycle
	return Horloge.saison(temps, float(cycle.duree_jour_secondes), float(cycle.jours_par_saison), cycle.saisons)

static func luminosite(heure: float, config: Dictionary, catalogue: Dictionary) -> float:
	return float(Lumiere.soleil(heure, float(config.cycle.latitude), catalogue).intensite)

static func table_flux_rapide(config: Dictionary) -> Array:
	return [{
		"source": String(config.propriete_source_rapide),
		"receptrice": String(config.propriete_pousse),
		"cible": String(config.nom_reserve_vegetale),
	}]

static func table_flux_lent(config: Dictionary) -> Array:
	return [{
		"source": String(config.propriete_source_lent),
		"receptrice": String(config.propriete_dormance),
		"cible": String(config.nom_reserve_vegetale),
	}]

# UNIQUE ECRIVAIN des trois miroirs. Le miroir de saison froide n'est ecrit a
# 1.0 QUE si l'annee n'est pas une annee sautee : c'est toute la perturbation,
# et elle ne demande aucune branche ailleurs. Rappele chaque tick, jamais
# seulement au changement -- un forcage au clavier prend effet au tick suivant.
static func poser_miroirs_saison(plantes: Array, saison: String, calendrier: Dictionary, config: Dictionary) -> void:
	var sans_hiver: bool = float(calendrier.proprietes.get("annee_sans_hiver", 0.0)) > 0.0
	var volcanique: bool = float(calendrier.proprietes.get("annee_volcanique", 0.0)) > 0.0
	var froide: bool = (saison == String(config.saison_froide)) and not sans_hiver
	var pousse: bool = config.saisons_de_pousse.has(saison)
	for plante in plantes:
		plante.proprietes[String(config.miroir_saison_pousse)] = 1.0 if pousse else 0.0
		plante.proprietes[String(config.miroir_saison_froide)] = 1.0 if froide else 0.0
		plante.proprietes[String(config.miroir_volcanique)] = 1.0 if (froide and volcanique) else 0.0

# conditions.gd REJOUE a chaque tick avec retrait : une entree VRAIE gagne
# toujours sur une entree FAUSSE qui poserait la meme cle, quel que soit leur
# ordre (deux passes disjointes, patron banc_biomes.gd).
static func evaluer_saisons(plantes: Array, config: Dictionary) -> void:
	for plante in plantes:
		Conditions.evaluer(plante.proprietes, config.conditions_saison, true)

# UNIQUE ECRIVAIN du cout_base de la reserve vegetale : ouvert tant que la cle
# de gel est posee, referme sinon (patron banc_corrosion.gd, ou un etat gate
# de la meme facon le cout d'une reserve d'integrite).
static func poser_cout_gel(plantes: Array, config: Dictionary) -> void:
	for plante in plantes:
		var canal: Dictionary = plante.proprietes.get("reserves", {}).get(String(config.nom_reserve_vegetale), {})
		if canal.is_empty():
			continue
		canal["cout_base"] = float(config.cout_gel) if plante.proprietes.has(String(config.propriete_gel)) else 0.0

# Les DEUX bornes vivent au cablage : depense.gd ne borne que le bas et ne
# tourne pas sur une reserve sans cout, flux.gd ne borne rien du tout et son
# taux negatif descendrait sous zero. Rend le total ecrete au plafond.
static func borner_reserves(plantes: Array, config: Dictionary) -> float:
	var ecrete := 0.0
	var capacite: float = float(config.capacite_vegetale)
	for plante in plantes:
		var canal: Dictionary = plante.proprietes.get("reserves", {}).get(String(config.nom_reserve_vegetale), {})
		if canal.is_empty():
			continue
		var reserve: float = float(canal.get("reserve", 0.0))
		if reserve > capacite:
			ecrete += reserve - capacite
			reserve = capacite
		canal["reserve"] = max(0.0, reserve)
	return ecrete

# LA CADENCE. Un compte par annee, un seuil LU PAR OBJET, remise a zero apres
# usage : l'etat se retire de lui-meme au passage suivant et l'intervalle
# repart. Le saut a la PRIORITE -- une annee sans saison froide n'a pas de
# froid a rendre extreme, le compte volcanique n'est donc pas consomme.
# Rend { changement, nouvelle_annee, sans_hiver, volcanique }.
static func avancer_calendrier(calendrier: Dictionary, saison: String, config: Dictionary) -> Dictionary:
	var proprietes: Dictionary = calendrier.proprietes
	var precedente := String(proprietes.get("derniere_saison", ""))
	var changement: bool = precedente != "" and precedente != saison
	var nouvelle_annee: bool = changement and saison == String(config.cycle.saisons[0])
	proprietes["derniere_saison"] = saison
	if nouvelle_annee:
		proprietes["annees_ecoulees"] = float(proprietes.annees_ecoulees) + 1.0
		proprietes["annees_depuis_saut"] = float(proprietes.annees_depuis_saut) + 1.0
		proprietes["annees_depuis_volcan"] = float(proprietes.annees_depuis_volcan) + 1.0
		SeuilEtat.avancer([calendrier], config.seuils_locaux)
		var actifs: Array = proprietes.get("etats_actifs", [])
		proprietes["annee_sans_hiver"] = 0.0
		proprietes["annee_volcanique"] = 0.0
		if actifs.has(String(config.etat_saut_hiver)):
			proprietes["annee_sans_hiver"] = 1.0
			proprietes["annees_depuis_saut"] = 0.0
		elif actifs.has(String(config.etat_hiver_volcanique)):
			proprietes["annee_volcanique"] = 1.0
			proprietes["annees_depuis_volcan"] = 0.0
		SeuilEtat.avancer([calendrier], config.seuils_locaux)
	return {
		"changement": changement,
		"nouvelle_annee": nouvelle_annee,
		"sans_hiver": float(proprietes.annee_sans_hiver) > 0.0,
		"volcanique": float(proprietes.annee_volcanique) > 0.0,
	}

static func forcer_saut_saison_froide(calendrier: Dictionary, config: Dictionary) -> void:
	calendrier.proprietes["annee_sans_hiver"] = 1.0
	calendrier.proprietes["annee_volcanique"] = 0.0
	calendrier.proprietes["annees_depuis_saut"] = 0.0
	SeuilEtat.avancer([calendrier], config.seuils_locaux)

static func forcer_saison_volcanique(calendrier: Dictionary, config: Dictionary) -> void:
	calendrier.proprietes["annee_sans_hiver"] = 0.0
	calendrier.proprietes["annee_volcanique"] = 1.0
	calendrier.proprietes["annees_depuis_volcan"] = 0.0
	SeuilEtat.avancer([calendrier], config.seuils_locaux)

static func cle_annee(calendrier: Dictionary, config: Dictionary) -> String:
	if float(calendrier.proprietes.get("annee_sans_hiver", 0.0)) > 0.0:
		return String(config.cle_annee_sans_hiver)
	if float(calendrier.proprietes.get("annee_volcanique", 0.0)) > 0.0:
		return String(config.cle_annee_volcanique)
	return String(config.cle_annee_reguliere)

# ---------------------------------------------------------------------------
# Le moral et sa contagion
# ---------------------------------------------------------------------------

static func abondance(plantes: Array, config: Dictionary) -> float:
	if plantes.is_empty():
		return 0.0
	var plafond: float = float(config.capacite_vegetale) * float(plantes.size())
	if plafond <= 0.0:
		return 0.0
	return clamp(Somme.reserves(plantes, String(config.nom_reserve_vegetale)) / plafond, 0.0, 1.0)

static func poser_abondance(colons: Array, plantes: Array, config: Dictionary) -> float:
	var part := abondance(plantes, config)
	for colon in colons:
		colon.proprietes[String(config.source_abondance)] = part
	return part

static func chroniques_lisibles(chroniques: Array, config: Dictionary) -> int:
	var compte := 0
	for chronique in monde_vivant(chroniques):
		if not est_cendre(chronique, config) and not est_illisible(chronique, config):
			compte += 1
	return compte

static func part_lue(colon: Dictionary, config: Dictionary) -> float:
	var lues: Array = colon.proprietes.get("chroniques_lues", [])
	var requis: float = float(config.chroniques_pour_fierte)
	if requis <= 0.0:
		return 0.0
	return clamp(float(lues.size()) / requis, 0.0, 1.0)

static func part_conservee(chroniques: Array, config: Dictionary) -> float:
	if chroniques.is_empty():
		return 0.0
	return clamp(float(chroniques_lisibles(chroniques, config)) / float(chroniques.size()), 0.0, 1.0)

# UNIQUE ECRIVAIN de la source de fierte, PRODUIT de deux parts recalculees a
# neuf : ce que le colon a lu, et ce qui reste lisible. Perdre la moitie des
# rayonnages coupe la fierte de moitie sans qu'aucune ligne ne la retranche.
static func poser_fierte(colons: Array, chroniques: Array, config: Dictionary) -> void:
	var conservee := part_conservee(chroniques, config)
	for colon in colons:
		colon.proprietes[String(config.source_fierte)] = part_lue(colon, config) * conservee

# UNIQUE ECRIVAIN du moral ET de son miroir inverse, les deux dans le MEME
# geste et depuis le MEME nombre : deux ecrivains se desynchroniseraient au
# bord exact sans qu'aucun test ne rougisse. RECALCULE A NEUF, jamais un
# increment -- la penalite de zone est un TERME de la somme.
static func poser_moral(colon: Dictionary, config: Dictionary) -> Dictionary:
	var proprietes: Dictionary = colon.proprietes
	var poids: Dictionary = proprietes.get(String(config.nom_poids_moral), {})
	var total := 0.0
	for source in poids:
		total += float(poids[source]) * float(proprietes.get(String(source), 0.0))
	if proprietes.get("etats_actifs", []).has(String(config.etat_moral_bas)):
		total -= float(config.penalite_moral_zone)
	var moral: float = max(0.0, total)
	var manque: float = max(0.0, float(config.capacite_moral) - moral)
	proprietes[String(config.nom_moral)] = moral
	proprietes[String(config.nom_manque_moral)] = manque
	return {"moral": moral, "manque": manque}

# Une cause par colon en panique, a SA position -- comptage IMPLICITE,
# charge.gd somme deja les causes a portee (patron
# banc_maladie.gd:causes_de_porteurs).
static func causes_de_paniques(colons: Array, config: Dictionary) -> Array:
	var causes: Array = []
	for colon in colons:
		if colon.proprietes.get("etats_actifs", []).has(String(config.etat_panique)):
			causes.append({"position": colon.position})
	return causes

# UNIQUE ECRIVAIN du miroir de contagion. Toujours present (0.0 ou 1.0) :
# charge.gd EFFACE sa cle en redescendant, et une propriete absente ferait
# sortir seuil_etat.gd sans jamais retirer l'etat.
static func refleter_contagion(colon: Dictionary, config: Dictionary) -> void:
	var pose: bool = colon.proprietes.has(String(config.marqueur_contagion))
	colon.proprietes[String(config.nom_miroir_contagion)] = 1.0 if pose else 0.0

static func charge_contagion(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get("etats", {}).get(String(config.nom_canal_contagion), {}).get("charge", 0.0))

# Bascule la serenite du colon designe en donnee. Rend vrai si elle vient de
# tomber. Ne calcule rien d'autre : tout le reste est recalcule au tick suivant.
static func basculer_serenite(colons: Array, config: Dictionary) -> bool:
	var colon := chose_par_id(colons, String(config.colon_choque))
	if colon.is_empty():
		return false
	var cle := String(config.source_serenite)
	var effondree: bool = float(colon.proprietes.get(cle, 0.0)) <= float(config.serenite_effondree)
	colon.proprietes[cle] = float(config.serenite_pleine) if effondree else float(config.serenite_effondree)
	return not effondree

# ---------------------------------------------------------------------------
# L'histoire ecrite
# ---------------------------------------------------------------------------

static func observer_si_cadence(colon: Dictionary, perceptions: Array, catalogue: Dictionary, config: Dictionary, temps: float) -> bool:
	if temps < float(colon.prochaine_observation):
		return false
	colon["prochaine_observation"] = temps + float(config.cadence_observation)
	Croyance.observer(colon, perceptions, catalogue)
	return true

static func doit_ecrire(etat: Dictionary, config: Dictionary) -> bool:
	if etat.chroniques.size() >= int(config.chronique.maximum):
		return false
	var auteur := auteur_de(etat.colons)
	if auteur.is_empty() or auteur.proprietes.croyances.is_empty():
		return false
	var pupitre := chose_par_id(etat.objets, String(config.pupitre.id))
	if pupitre.is_empty():
		return false
	return auteur.position.distance_to(pupitre.position) <= float(config.portee_ecriture)

static func auteur_de(colons: Array) -> Dictionary:
	for colon in colons:
		if bool(colon.get("auteur", false)):
			return colon
	return {}

# UN OBJET REEL fabrique en cours de partie. Les proprietes qui ne viennent ni
# du type ni de la composition sont posees APRES la fabrication --
# Objet.fabriquer n'en relaie aucune autre. LE FIGEAGE EST UNE COPIE PROFONDE :
# sans elle, l'objet et son auteur partageraient le meme registre et l'un
# suivrait ce que l'autre apprend ensuite. Rend {} si la fabrication est
# refusee (contrat explicite d'objet.gd).
static func fabriquer_chronique(auteur: Dictionary, id: String, position: Vector3, config: Dictionary, table: Dictionary, materiaux: Dictionary) -> Dictionary:
	var decl: Dictionary = config.chronique
	var chronique := Objet.fabriquer(id, String(decl.type), position, table, materiaux)
	if chronique.is_empty():
		return {}
	chronique.proprietes["auteur"] = String(auteur.id)
	chronique.proprietes["contenu_croyance"] = auteur.proprietes.croyances.duplicate(true)
	chronique.proprietes["fidelite"] = float(decl.fidelite)
	chronique.proprietes["reserves"] = {
		String(config.nom_reserve_integrite): {
			"capacite": float(decl.integrite),
			"reserve": float(decl.integrite),
			"cout_base": float(decl.cout_lisibilite),
			"surcout_action": 0.0,
			"seuils_ref": String(decl.seuils_ref),
			"seuils_franchis": [],
		},
	}
	chronique["proprietes_type"] = String(decl.type)
	return chronique

static func est_illisible(chronique: Dictionary, config: Dictionary) -> bool:
	return bool(chronique.proprietes.get(String(config.chronique.propriete_illisible), false))

static func est_consumee(chronique: Dictionary, config: Dictionary) -> bool:
	return bool(chronique.proprietes.get(String(config.chronique.marqueur_consumee), false))

static func est_cendre(chronique: Dictionary, config: Dictionary) -> bool:
	return String(chronique.get("proprietes_type", "")) == String(config.produire_cendre.type_produit)

static func brule(chronique: Dictionary, config: Dictionary) -> bool:
	return bool(chronique.proprietes.get(String(config.propriete_menace), false))

static func integrite(chronique: Dictionary, config: Dictionary) -> float:
	return float(chronique.proprietes.get("reserves", {}).get(String(config.nom_reserve_integrite), {}).get("reserve", 0.0))

# UNIQUE ECRIVAIN du cout de la reserve d'integrite : ouvert en grand tant que
# la propriete-menace est posee, refermee au cout de degradation ordinaire des
# qu'un agent a eteint. depense.gd ne consulte jamais un etat lui-meme.
static func poser_cout_chronique(chroniques: Array, config: Dictionary) -> void:
	for chronique in chroniques:
		var canal: Dictionary = chronique.proprietes.get("reserves", {}).get(String(config.nom_reserve_integrite), {})
		if canal.is_empty():
			continue
		canal["cout_base"] = float(config.chronique.cout_incendie) if brule(chronique, config) \
			else float(config.chronique.cout_lisibilite)

# LA LECTURE. L'auteur ne se relit pas : sans ce gate il rabaisserait sa propre
# certitude, tenue d'une observation directe, a celle d'une relecture. Une
# chronique deja lue passe apres celles qui ne le sont pas, pour que la fierte
# monte au lieu de stagner. Rend les cles versees, pour la trace.
static func lire_si_cadence(colon: Dictionary, chroniques: Array, config: Dictionary, catalogue: Dictionary, temps: float) -> Array:
	if bool(colon.get("auteur", false)) or temps < float(colon.prochaine_lecture):
		return []
	var portee: float = float(config.portee_lecture)
	var lues: Array = colon.proprietes.chroniques_lues
	var choisie: Dictionary = {}
	for chronique in chroniques:
		if est_cendre(chronique, config) or est_illisible(chronique, config):
			continue
		if colon.position.distance_to(chronique.position) > portee:
			continue
		if not lues.has(String(chronique.id)):
			choisie = chronique
			break
		if choisie.is_empty():
			choisie = chronique
	if choisie.is_empty():
		return []
	colon["prochaine_lecture"] = temps + float(config.cadence_lecture)
	if not lues.has(String(choisie.id)):
		lues.append(String(choisie.id))
	var versees: Array = []
	var registre: Dictionary = choisie.proprietes.get("contenu_croyance", {})
	var credibilite: float = float(choisie.proprietes.get("fidelite", 0.0))
	for chose_id in registre:
		for propriete in registre[chose_id]:
			Croyance.corriger(colon, String(chose_id), String(propriete), registre[chose_id][propriete].valeur, credibilite, catalogue)
			versees.append("%s/%s" % [chose_id, propriete])
	return versees

# TERMINUS. depense.gd pose un marqueur au second palier et NE PRODUIT RIEN --
# c'est ce fichier qui appelle Produit.transformer, puis vide et remplit
# proprietes (patron banc_fertilite.gd:avancer_transformations). IDEMPOTENT
# SANS MARQUEUR SUPPLEMENTAIRE : apres transformation le marqueur a disparu
# avec le reste des proprietes, un second passage ne retrouve plus rien.
static func transformer_consumees(chroniques: Array, config: Dictionary, table: Dictionary, materiaux: Dictionary) -> Array:
	var transformees: Array = []
	for chronique in chroniques:
		if not est_consumee(chronique, config):
			continue
		var neuves: Dictionary = Produit.transformer(chronique.proprietes, config.produire_cendre, table, materiaux)
		if neuves.is_empty():
			continue
		chronique.proprietes.clear()
		chronique.proprietes.merge(neuves, true)
		chronique["proprietes_type"] = String(config.produire_cendre.type_produit)
		transformees.append(String(chronique.id))
	return transformees

static func basculer_brasier(etat: Dictionary, config: Dictionary) -> bool:
	var brasier := chose_par_id(etat.objets, String(config.brasier.id))
	if brasier.is_empty():
		return false
	var cle := String(config.propriete_menace)
	var allume: bool = bool(brasier.proprietes.get(cle, false))
	if allume:
		brasier.proprietes.erase(cle)
	else:
		brasier.proprietes[cle] = true
	return not allume

# ---------------------------------------------------------------------------
# UN PAS COMPLET
# ---------------------------------------------------------------------------

# ORDRE FIXE, chaque etape depend de la precedente :
#  1. le temps du monde, puis le calendrier (il consomme le changement de
#     saison AVANT que les miroirs ne soient ecrits, sans quoi la perturbation
#     de l'annee qui s'ouvre arriverait une saison en retard) ;
#  2. miroirs -> conditions -> flux LENT (le changement de saison seul) ->
#     flux RAPIDE (chaque tick) -> gel -> depense -> bornes ;
#  3. moral : abondance et fierte d'abord, moral ensuite, seuils apres, charge
#     enfin, miroir en dernier pour le tick suivant ;
#  4. observation de l'auteur, ecriture au changement de saison, lecture ;
#  5. feu : propagation, extinction par les agents a portee, degradation,
#     terminus ;
#  6. l'OUBLI EN DERNIER -- une croyance formee ce pas-ci ne doit pas perdre sa
#     certitude avant d'avoir servi une seule fois.
static func avancer(etat: Dictionary, config: Dictionary, catalogues: Dictionary, delta: float, temps: float) -> Dictionary:
	var calendrier: Dictionary = etat.calendrier
	var plantes: Array = etat.plantes
	var colons: Array = etat.colons
	var saison := saison_courante(temps, config)
	var bilan_calendrier := avancer_calendrier(calendrier, saison, config)

	poser_miroirs_saison(plantes, saison, calendrier, config)
	evaluer_saisons(plantes, config)
	var monde_flux: Array = plantes + etat.sources
	var lent := 0.0
	if bool(bilan_calendrier.changement):
		var avant_lent := Somme.reserves(plantes, String(config.nom_reserve_vegetale))
		Flux.avancer(monde_flux, table_flux_lent(config), 1.0)
		lent = Somme.reserves(plantes, String(config.nom_reserve_vegetale)) - avant_lent
	Flux.avancer(monde_flux, table_flux_rapide(config), delta)
	poser_cout_gel(plantes, config)
	Depense.avancer(plantes, delta, {})
	borner_reserves(plantes, config)

	poser_abondance(colons, plantes, config)
	poser_fierte(colons, etat.chroniques, config)
	for colon in colons:
		poser_moral(colon, config)
	var avant_etats := _instantane_etats(colons)
	SeuilEtat.avancer(colons, catalogues.seuils_etat)
	Charge.avancer(colons, causes_de_paniques(colons, config), delta)
	for colon in colons:
		refleter_contagion(colon, config)

	var evenements: Array = []
	var auteur := auteur_de(colons)
	if not auteur.is_empty():
		observer_si_cadence(auteur, Perception.percevoir(auteur, etat.monde, catalogues.canaux), catalogues.croyances, config, temps)
	if bool(bilan_calendrier.changement) and doit_ecrire(etat, config):
		var index: int = etat.chroniques.size()
		var pos: Array = config.chronique.positions[index]
		var chronique := fabriquer_chronique(auteur, "%s%d" % [String(config.chronique.prefixe_id), index],
			Vector3(pos[0], pos[1], pos[2]), config, catalogues.types, catalogues.materiaux)
		if not chronique.is_empty():
			etat.chroniques.append(chronique)
			etat.monde.ajouter(chronique, String(config.chronique.type), chronique.position)
			evenements.append({"genre": "ecrit", "qui": String(auteur.id), "quoi": String(chronique.id),
				"nombre": float(chronique.proprietes.contenu_croyance.size())})
	for colon in colons:
		var versees := lire_si_cadence(colon, etat.chroniques, config, catalogues.croyances, temps)
		if not versees.is_empty():
			evenements.append({"genre": "lit", "qui": String(colon.id), "quoi": String(versees[0]),
				"nombre": float(versees.size())})

	var vivantes := monde_vivant(etat.chroniques)
	var combustibles: Array = vivantes + monde_vivant(etat.objets)
	for id in Propagation.avancer(combustibles, catalogues.menaces, etat.exposition, delta, config.patron_incendie):
		evenements.append({"genre": "prend_feu", "qui": "", "quoi": String(id), "nombre": 0.0})
	for id in Extinction.avancer(vivantes, BancCommun.agents_rythme(colons), delta, catalogues.transformations):
		evenements.append({"genre": "eteint", "qui": "", "quoi": String(id), "nombre": 0.0})
	var illisibles_avant := _instantane_illisibles(vivantes, config)
	poser_cout_chronique(vivantes, config)
	Depense.avancer(vivantes, delta, catalogues.seuils_reserve)
	for chronique in vivantes:
		if not illisibles_avant.has(String(chronique.id)) and est_illisible(chronique, config):
			evenements.append({"genre": "illisible", "qui": "", "quoi": String(chronique.id), "nombre": 0.0})
	for id in transformer_consumees(vivantes, config, catalogues.types, catalogues.materiaux):
		evenements.append({"genre": "cendre", "qui": "", "quoi": String(id), "nombre": 0.0})

	for colon in colons:
		Croyance.avancer(colon, delta, catalogues.croyances)

	var etats_colons: Array = []
	for colon in colons:
		etats_colons.append(_etat_colon(colon, config))
	for colon in colons:
		for nom in ["etat_panique", "etat_moral_bas"]:
			var etat_nom := String(config.get(nom, ""))
			var avant: Array = avant_etats.get(String(colon.id), [])
			var apres: Array = colon.proprietes.get("etats_actifs", [])
			if apres.has(etat_nom) and not avant.has(etat_nom):
				evenements.append({"genre": "etat_pose", "qui": String(colon.id), "quoi": etat_nom, "nombre": 0.0})
			elif avant.has(etat_nom) and not apres.has(etat_nom):
				evenements.append({"genre": "etat_retire", "qui": String(colon.id), "quoi": etat_nom, "nombre": 0.0})

	return {
		"heure": heure_du_jour(temps, config),
		"saison": saison,
		"changement_saison": bool(bilan_calendrier.changement),
		"nouvelle_annee": bool(bilan_calendrier.nouvelle_annee),
		"sans_hiver": bool(bilan_calendrier.sans_hiver),
		"volcanique": bool(bilan_calendrier.volcanique),
		"annees": float(calendrier.proprietes.annees_ecoulees),
		"flux_lent": lent,
		"reserve_totale": Somme.reserves(plantes, String(config.nom_reserve_vegetale)),
		"abondance": abondance(plantes, config),
		"chroniques_ecrites": etat.chroniques.size(),
		"chroniques_lisibles": chroniques_lisibles(etat.chroniques, config),
		"colons": etats_colons,
		"evenements": evenements,
	}

static func _instantane_etats(colons: Array) -> Dictionary:
	var instantane: Dictionary = {}
	for colon in colons:
		instantane[String(colon.id)] = colon.proprietes.get("etats_actifs", []).duplicate()
	return instantane

static func _instantane_illisibles(chroniques: Array, config: Dictionary) -> Dictionary:
	var instantane: Dictionary = {}
	for chronique in chroniques:
		if est_illisible(chronique, config):
			instantane[String(chronique.id)] = true
	return instantane

static func _etat_colon(colon: Dictionary, config: Dictionary) -> Dictionary:
	var proprietes: Dictionary = colon.proprietes
	var actifs: Array = proprietes.get("etats_actifs", [])
	return {
		"id": String(colon.id),
		"moral": float(proprietes.get(String(config.nom_moral), 0.0)),
		"fierte": float(proprietes.get(String(config.source_fierte), 0.0)),
		"serenite": float(proprietes.get(String(config.source_serenite), 0.0)),
		"charge": charge_contagion(colon, config),
		"panique": actifs.has(String(config.etat_panique)),
		"moral_bas": actifs.has(String(config.etat_moral_bas)),
		"lues": proprietes.get("chroniques_lues", []).size(),
		"croyances": proprietes.croyances.size(),
	}

# ---------------------------------------------------------------------------
# Textes. Les LABELS a l'ecran passent par le catalogue i18n ; les traces
# console (print) sont des sorties de mise au point et n'y passent pas. Une
# cle absente ressort telle quelle, jamais remplacee par un repli ecrit ici :
# le trou doit se voir pour se combler.
# ---------------------------------------------------------------------------

static func texte(cle: String, config: Dictionary, textes: Dictionary) -> String:
	if cle == "":
		return ""
	return String(textes.get(String(config.langue), {}).get(cle, cle))

static func ligne_pose(config: Dictionary) -> String:
	var cycle: Dictionary = config.cycle
	var duree: float = float(cycle.duree_jour_secondes) * float(cycle.jours_par_saison)
	return ("t=0.0 %d plantes, %d colons -- une saison dure %.1f s, un cycle complet %.1f s ; " +
		"clic gauche : sauter la saison froide, clic droit : la rendre volcanique, F : brasier, M : moral") % [
		config.plantes.size(), config.colons.size(), duree, duree * float(cycle.saisons.size())]

static func ligne_forcage(t: float, libelle: String) -> String:
	return "t=%.1f FORCE : %s" % [t, libelle]

static func ligne_brasier(t: float, allume: bool) -> String:
	return "t=%.1f BRASIER : %s" % [t, "allume" if allume else "eteint"]

static func ligne_choc(t: float, id: String, effondree: bool) -> String:
	return "t=%.1f %s : serenite %s" % [t, id, "coupee" if effondree else "rendue"]

static func lignes_evenements(t: float, bilan: Dictionary, config: Dictionary, textes: Dictionary) -> Array:
	var lignes: Array = []
	if bool(bilan.changement_saison):
		lignes.append("t=%.1f SAISON -> %s%s | reserve totale %.1f (pas lent %.1f)" % [
			t, String(bilan.saison),
			"" if not bool(bilan.nouvelle_annee) else "  [cycle %.0f : %s]" % [
				float(bilan.annees), texte(cle_annee_du_bilan(bilan, config), config, textes)],
			float(bilan.reserve_totale), float(bilan.flux_lent)])
	for ev in bilan.evenements:
		lignes.append(ligne_evenement(t, ev))
	return lignes

static func cle_annee_du_bilan(bilan: Dictionary, config: Dictionary) -> String:
	if bool(bilan.sans_hiver):
		return String(config.cle_annee_sans_hiver)
	if bool(bilan.volcanique):
		return String(config.cle_annee_volcanique)
	return String(config.cle_annee_reguliere)

static func ligne_evenement(t: float, ev: Dictionary) -> String:
	match String(ev.genre):
		"ecrit":
			return "t=%.1f %s ECRIT %s -- %.0f chose(s) figee(s)" % [t, ev.qui, ev.quoi, float(ev.nombre)]
		"lit":
			return "t=%.1f %s LIT une chronique -- %.0f croyance(s) versee(s)" % [t, ev.qui, float(ev.nombre)]
		"prend_feu":
			return "t=%.1f %s PREND FEU" % [t, ev.quoi]
		"eteint":
			return "t=%.1f %s ETEINT par un agent a portee" % [t, ev.quoi]
		"illisible":
			return "t=%.1f %s : premier palier franchi -- ILLISIBLE" % [t, ev.quoi]
		"cendre":
			return "t=%.1f %s : second palier franchi -- CENDRE" % [t, ev.quoi]
		"etat_pose":
			return "t=%.1f %s : etat '%s' POSE" % [t, ev.qui, ev.quoi]
		"etat_retire":
			return "t=%.1f %s : etat '%s' retire" % [t, ev.qui, ev.quoi]
	return "t=%.1f %s ?" % [t, ev.qui]

static func ligne_trace(t: float, bilan: Dictionary) -> String:
	var corps := ""
	for etat in bilan.colons:
		corps += " | %s %.2f%s" % [String(etat.id), float(etat.moral),
			" PANIQUE" if bool(etat.panique) else (" bas" if bool(etat.moral_bas) else "")]
	return "t=%.1f h=%.1f %s | reserve %.1f | chroniques %d/%d%s" % [
		t, float(bilan.heure), String(bilan.saison), float(bilan.reserve_totale),
		int(bilan.chroniques_lisibles), int(bilan.chroniques_ecrites), corps]

static func texte_entete(bilan: Dictionary, config: Dictionary, textes: Dictionary) -> String:
	return "heure %.1f   saison : %s   cycle %.0f   est_hiver=%d  volcanique=%d\n%s" % [
		float(bilan.heure), String(bilan.saison), float(bilan.annees),
		1 if (String(bilan.saison) == String(config.saison_froide) and not bool(bilan.sans_hiver)) else 0,
		1 if bool(bilan.volcanique) else 0,
		texte(cle_annee_du_bilan(bilan, config), config, textes)]

static func texte_compteur(bilan: Dictionary, config: Dictionary) -> String:
	var paniques := 0
	var fierte := 0.0
	for etat in bilan.colons:
		if bool(etat.panique):
			paniques += 1
		fierte = max(fierte, float(etat.fierte))
	return "chroniques ecrites %d | lisibles %d | cendre %d | fierte max %.2f | %d en panique | abondance %.2f" % [
		int(bilan.chroniques_ecrites), int(bilan.chroniques_lisibles),
		int(bilan.chroniques_ecrites) - int(bilan.chroniques_lisibles),
		fierte, paniques, float(bilan.abondance)]

static func texte_plante(plante: Dictionary, config: Dictionary) -> String:
	var canal: Dictionary = plante.proprietes.get("reserves", {}).get(String(config.nom_reserve_vegetale), {})
	return "%s\n%.1f / %.0f\n%s" % [String(plante.id), float(canal.get("reserve", 0.0)),
		float(config.capacite_vegetale), _regime_plante(plante, config)]

static func _regime_plante(plante: Dictionary, config: Dictionary) -> String:
	if plante.proprietes.has(String(config.propriete_gel)):
		return "gel"
	if plante.proprietes.has(String(config.propriete_dormance)):
		return "dort"
	if plante.proprietes.has(String(config.propriete_pousse)):
		return "pousse"
	return "-"

static func texte_colon(etat: Dictionary) -> String:
	return "%s\nmoral %.2f  fierte %.2f\ncharge %.2f  lu %d  croyances %d%s" % [
		String(etat.id), float(etat.moral), float(etat.fierte), float(etat.charge),
		int(etat.lues), int(etat.croyances),
		"\nPANIQUE" if bool(etat.panique) else ("\nmoral bas" if bool(etat.moral_bas) else "")]

static func texte_chronique(chronique: Dictionary, config: Dictionary, textes: Dictionary) -> String:
	if est_cendre(chronique, config):
		return "%s\ncendre" % String(chronique.id)
	var cle := String(config.chronique.cle_illisible) if est_illisible(chronique, config) \
		else String(config.chronique.cle_titre)
	return "%s\n%s\nintegrite %.1f%s" % [String(chronique.id), texte(cle, config, textes),
		integrite(chronique, config), "\nEN FEU" if brule(chronique, config) else ""]

# ---------------------------------------------------------------------------
# Rendu (impur, Node) -- aucune decision, seulement couleurs et positions.
# ---------------------------------------------------------------------------

func _couleur(cle: String) -> Color:
	var rgb: Array = _config.couleurs.get(cle, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _creer_rendu() -> void:
	_fond = ColorRect.new()
	_fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fond.size = Vector2(6000.0, 5000.0)
	_fond.position = Vector2(-2500.0, -2500.0)
	add_child(_fond)

	for plante in _etat.plantes:
		_creer_carre(String(plante.id), plante.position, float(_config.taille_plante), _couleur("plante_dort"))
		_creer_barre(String(plante.id), plante.position, float(_config.taille_plante))
		_creer_label(String(plante.id), plante.position, float(_config.taille_plante))
	for source in _etat.sources:
		var cle_source := "source_rapide" if source.proprietes.has(String(_config.propriete_source_rapide)) else "source_lent"
		_creer_carre(String(source.id), source.position, float(_config.taille_objet), _couleur(cle_source))
		_creer_label(String(source.id), source.position, float(_config.taille_objet))
	for objet in _etat.objets:
		_creer_carre(String(objet.id), objet.position, float(_config.taille_objet),
			_couleur("brasier_eteint" if String(objet.id) == String(_config.brasier.id) else "pupitre"))
		_creer_label(String(objet.id), objet.position, float(_config.taille_objet))
	for colon in _etat.colons:
		_creer_cercle(String(colon.id), colon.position)
		_creer_carre(String(colon.id), colon.position, float(_config.taille_colon), _couleur("moral_haut"))
		_creer_label(String(colon.id), colon.position, float(_config.taille_colon))

	_label_entete = _creer_label_fixe(TAILLE_POLICE_ENTETE, Vector2(16.0, 10.0))
	_label_compteur = _creer_label_fixe(TAILLE_POLICE_LABEL, Vector2(16.0, 70.0))
	_label_aide = _creer_label_fixe(TAILLE_POLICE_LABEL, Vector2(16.0, 92.0))
	_label_aide.text = "clic gauche : saison froide sautee   clic droit : saison volcanique   F : brasier   M : moral"

func _creer_carre(cle: String, position: Vector3, taille: float, couleur: Color) -> void:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	carre.color = couleur
	carre.position = Vector2(position.x, position.y) - carre.size / 2.0
	add_child(carre)
	_noeuds[cle] = carre

func _creer_barre(cle: String, position: Vector3, taille: float) -> void:
	var largeur: float = float(_config.largeur_barre)
	var hauteur: float = float(_config.hauteur_barre)
	var origine := Vector2(position.x - largeur / 2.0, position.y + taille / 2.0 + 6.0)
	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.color = _couleur("barre_fond")
	fond.size = Vector2(largeur, hauteur)
	fond.position = origine
	add_child(fond)
	_barres_fond[cle] = fond
	var remplie := ColorRect.new()
	remplie.mouse_filter = Control.MOUSE_FILTER_IGNORE
	remplie.color = _couleur("barre_reserve")
	remplie.size = Vector2(0.0, hauteur)
	remplie.position = origine
	add_child(remplie)
	_barres[cle] = remplie

func _creer_cercle(cle: String, position: Vector3) -> void:
	var cercle := Line2D.new()
	cercle.width = LARGEUR_CERCLE
	cercle.default_color = _couleur("cercle_contagion")
	cercle.closed = true
	var rayon: float = float(_config.canal_contagion.portee_charge)
	var segments: int = int(_config.segments_cercle)
	var points := PackedVector2Array()
	for i in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		points.append(Vector2(position.x + cos(angle) * rayon, position.y + sin(angle) * rayon))
	cercle.points = points
	cercle.visible = false
	add_child(cercle)
	_cercles[cle] = cercle

func _creer_label(cle: String, position: Vector3, taille: float) -> void:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	label.position = Vector2(position.x - taille, position.y + taille / 2.0 + 22.0)
	add_child(label)
	_labels[cle] = label

func _creer_label_fixe(taille: int, position_ecran: Vector2) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	label.position = position_ecran
	_couche_ui.add_child(label)
	return label

func _rafraichir_tout() -> void:
	if _dernier.is_empty():
		return
	_fond.color = _couleur("fond_nuit").lerp(_couleur("fond_jour"),
		clamp(luminosite(float(_dernier.heure), _config, _catalogues.lumiere), 0.0, 1.0))

	var capacite: float = float(_config.capacite_vegetale)
	for plante in _etat.plantes:
		var cle := String(plante.id)
		_noeuds[cle].color = _couleur(_couleur_plante(plante))
		var canal: Dictionary = plante.proprietes.get("reserves", {}).get(String(_config.nom_reserve_vegetale), {})
		var part: float = clamp(float(canal.get("reserve", 0.0)) / capacite, 0.0, 1.0) if capacite > 0.0 else 0.0
		_barres[cle].size.x = float(_config.largeur_barre) * part
		_labels[cle].text = texte_plante(plante, _config)

	for objet in _etat.objets:
		if String(objet.id) == String(_config.brasier.id):
			_noeuds[objet.id].color = _couleur("brasier_allume" if objet.proprietes.has(String(_config.propriete_menace)) else "brasier_eteint")
		_labels[objet.id].text = String(objet.id)

	for etat_colon in _dernier.colons:
		var cle := String(etat_colon.id)
		_noeuds[cle].color = _couleur("moral_panique" if bool(etat_colon.panique)
			else ("moral_bas" if bool(etat_colon.moral_bas) else "moral_haut"))
		_labels[cle].text = texte_colon(etat_colon)
		_cercles[cle].visible = bool(etat_colon.panique)

	for chronique in _etat.chroniques:
		var cle := String(chronique.id)
		if not _noeuds.has(cle):
			_creer_carre(cle, chronique.position, float(_config.taille_chronique), _couleur("chronique"))
			_creer_barre(cle, chronique.position, float(_config.taille_chronique))
			_creer_label(cle, chronique.position, float(_config.taille_chronique))
			_barres[cle].color = _couleur("barre_integrite")
		_noeuds[cle].color = _couleur(_couleur_chronique(chronique))
		var pleine: float = float(_config.chronique.integrite)
		_barres[cle].size.x = float(_config.largeur_barre) * (clamp(integrite(chronique, _config) / pleine, 0.0, 1.0) if pleine > 0.0 else 0.0)
		_labels[cle].text = texte_chronique(chronique, _config, _textes)

	_label_entete.text = texte_entete(_dernier, _config, _textes)
	_label_compteur.text = texte_compteur(_dernier, _config)

func _couleur_plante(plante: Dictionary) -> String:
	if plante.proprietes.has(String(_config.propriete_gel)):
		return "plante_gel"
	if plante.proprietes.has(String(_config.propriete_pousse)):
		return "plante_pousse"
	return "plante_dort"

func _couleur_chronique(chronique: Dictionary) -> String:
	if est_cendre(chronique, _config):
		return "cendre"
	if brule(chronique, _config):
		return "chronique_brule"
	if est_illisible(chronique, _config):
		return "chronique_illisible"
	return "chronique"

func _poser_camera() -> void:
	var decl: Dictionary = _config.get("camera", {})
	var pos: Array = decl.get("position", [0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(decl.get("zoom", 1.0), decl.get("zoom", 1.0))
	camera.enabled = true
	add_child(camera)

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
