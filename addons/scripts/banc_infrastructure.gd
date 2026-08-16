extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_infrastructure.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « stockage +
# degradation + coordination + routes » (audit prealable
# audit_economie_logistique_prealable.md, lignes 5, 6, 7 et 8 -- toutes quatre
# au verdict CABLABLE, « zero .gd neuf »). CONFIRME A L'ECRITURE : AUCUN
# MECANISME DU COEUR TOUCHE, aucun .gd neuf du coeur, data/types.json NON
# touche -- donc rien a enregistrer dans scripts/test_lint_donnees.gd.
#
# COMPOSE SIX MECANISMES DEJA FERMES, TOUS INCHANGES : scripts/depense.gd (les
# lots se degradent, la route s'use, et c'est LUI qui applique le seuil qui
# ramene facteur_vitesse a 1.0), scripts/consommer.gd (transfert CONSERVE tas
# -> colon -> grenier), scripts/comptage.gd (combien de colons sont actifs),
# scripts/seuil_etat.gd (pose/retire 'surpeuplement'), scripts/etat_effectif.gd
# (vitesse ET rythme effectifs), scripts/portee.gd (« suis-je a l'abri »,
# « suis-je sur la route »). Plus scripts/banc_commun.gd:bouger_vers pour le
# pas de deplacement.
#
# CE QU'ON DOIT VOIR : un tas de marchandise dehors a gauche, un grenier a
# droite, une route doree de quatre cases entre les deux, et des colons qui
# font la navette. Ils chargent au tas, traversent, deposent au grenier. QUATRE
# PHENOMENES, chacun observable seul :
# - LE GRENIER SE REMPLIT ET REFUSE. Sa barre monte ; a la capacite il vire au
#   rouge, les colons s'entassent devant AVEC leur charge et n'en perdent pas
#   un gramme. Le bouton « AGRANDIR » lui rend 100 de capacite et la file
#   repart.
# - LES LOTS DEHORS MEURENT VITE. Six lots : trois sous le grenier (verts),
#   trois au tas (rouges). Les rouges sont ruines en une douzaine de secondes,
#   les verts ont a peine entame leur integrite au meme instant.
# - LA COORDINATION COUTE. Chaque « +5 COLONS » ajoute des porteurs ; au-dela
#   de seuil_agents chacun travaille MOINS VITE (le compteur du haut donne le
#   rythme effectif), et le debit total cesse de suivre le nombre.
# - LA ROUTE S'USE ET SE REPARE. Les cases grisent d'autant plus vite qu'il y
#   passe du monde ; a zero, le bonus de vitesse disparait d'un coup (les
#   colons ralentissent a vue d'oeil) et « REPARER » le rend.
#
# ---- LES CINQ POINTS DE CABLAGE QUI DECIDENT CE FICHIER ----
#
# (1) LE PLAFOND EST DU CABLAGE, ET C'EST UN REFUS, PAS UN ECRETAGE. Rien dans
# le coeur ne borne le HAUT d'une reserve (constat pose cinq fois dans le
# depot : depense.gd ne borne que 0.0, ni flux.gd ni consommer.gd ne
# connaissent de capacite). Deux comportements existaient deja, et ce ne sont
# PAS la meme regle de jeu : ECRETER (le surplus est PERDU, patron
# banc_fertilite.gd:plafonner_fertilite) et REFUSER (le porteur GARDE sa
# charge, patron banc_graisse_accoutumance.gd:peut_manger). Un grenier plein
# demande le second -- ecreter ferait disparaitre en silence ce qu'un colon a
# porte a travers toute la carte. `peut_deposer` est donc un gate strict, et
# `poser_encombrement` en est le MIROIR VISIBLE.
#
# (2) UN SEUL PREDICAT POUR LE REFUS ET POUR L'ETAT. `encombre` N'EST PAS pose
# par seuil_etat.gd, et c'est une decision : seuil_etat.gd compare
# STRICTEMENT vers le haut (`valeur > seuil`), alors que le refus est
# `reserve >= capacite`. Reserve pile a la capacite : le refus serait vrai et
# l'etat absent -- deux verites qui divergent exactement au bord, c'est-a-dire
# la desynchronisation silencieuse que « UN SEUL ECRIVAIN » existe pour
# empecher (banc_bonheur.gd:poser_bonheur, banc_faim_thermo.gd:
# poser_surcout_action). `est_plein` est l'unique prediat ; `peut_deposer` le
# lit, `poser_encombrement` le lit, personne ne le recalcule.
#
# (3) DEUX CANAUX DE surcout_action, DEUX ECRIVAINS UNIQUES, JAMAIS CROISES.
# depense.gd calcule `reserve -= (cout_base + surcout_action) * delta` : il n'y
# a QU'UN SEUL emplacement surcout_action par canal, et deux morceaux de
# cablage qui y ecrivent chacun le leur se detruisent EN SILENCE (piege nomme
# quatre fois dans le depot, aucun test ne rougirait). Ce fichier ecrit
# surcout_action a DEUX endroits, sur DEUX familles de canaux disjointes :
# `poser_surcout_degradation` sur le canal d'integrite des LOTS (rien d'autre
# n'y touche), `poser_usure_routes` sur le canal de duree des CASES DE ROUTE
# (rien d'autre n'y touche). Chaque fonction REECRIT le champ EN ENTIER a
# chaque tick, jamais un `+=` -- un residu du tick precedent est impossible.
#
# (4) « cout_base PAR PASSAGE » N'EXISTE PAS, ET C'EST DIT PLUTOT QUE MASQUE.
# `cout_base` de depense.gd est un cout PAR SECONDE, jamais par evenement. Le
# trafic passe donc par `surcout_action` -- ce qui est exactement la frontiere
# que depense.gd pose : `cout_base` est ce que la chose EST (une route
# s'effrite toute seule, lentement), `surcout_action` est l'action en cours
# (le nombre de colons qui la foulent CET instant). Les deux se somment dans
# le mecanisme, sans un cas particulier.
#
# (5) LE PIEGE DE LA LIGNE 7, PAYE PAR LE CABLAGE. Declarer « surpeuplement
# module rythme x0.7 » dans data/etats.json ne produirait STRICTEMENT RIEN :
# banc_commun.gd:agents_rythme lit `chose.proprietes.rythme` BRUTE, et aucune
# couche de decision ne passe par etat_effectif.gd (audit, constat repete). Le
# catalogue partage garde donc `surpeuplement` en MARQUEUR PUR (effets vides),
# et c'est `poser_rythme_effectif` qui compose lui-meme
# EtatEffectif.valeur(colon, rythme, etats) -- geste que seuls
# banc_bonheur.gd et banc_grief.gd faisaient jusqu'ici -- puis y applique le
# facteur de coordination. Sans cette ligne, la coordination serait vraie dans
# les donnees et inerte dans le jeu, en silence.
#
# ---- CE QUE CE BANC NE MONTRE PAS, dit plutot que masque ----
# Aucun colon ne PERCOIT ni ne DECIDE : ni perception.gd, ni proximite.gd, ni
# dominance.gd, ni agir.gd. La navette est une machine a etats de cablage
# (`nom_mode`), pas une decision -- meme decoupage assume que
# banc_bonheur.gd/banc_nutrition.gd. Ce chantier observe une LOGISTIQUE, pas un
# agent. Brancher la chaine de decision (le colon CHOISIT d'aller au grenier
# parce que sa saillance monte) est un chantier suivant.
# Les lots ne se transforment pas a integrite nulle (aucun produit.gd ici) :
# ils restent, noirs, a zero. Un colon rendu inactif alors qu'il porte une
# charge la garde -- il reprend sa navette la ou il en etait s'il redevient
# actif.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les quatre JSON et construit monde + rendu ;
#   les quatre boutons appellent chacun une fonction statique ; _process
#   appelle UNIQUEMENT avancer() et lit son bilan pour l'affichage et la
#   console -- aucune decision dans _process.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_infrastructure.gd) : construire_grenier/construire_tas/
#   construire_lots/construire_route/construire_colons/est_actif/
#   regler_actifs/actifs_apres/compter_actifs/poser_population/
#   facteur_coordination/poser_rythme_effectif/rythme_effectif/
#   capacite_grenier/stock_grenier/est_plein/peut_deposer/poser_encombrement/
#   agrandir_grenier/abrite/cout_abri/cout_exterieur/
#   poser_surcout_degradation/case_sous/facteur_vitesse_sous/
#   vitesse_effective/en_transit/trafic_par_case/poser_usure_routes/
#   reparer_route/
#   cible_de/deplacer_vers/avancer_colons/avancer, plus les couleurs et les
#   textes.
#
# AUCUN NOM DE PROPRIETE EN DUR : les quinze noms lus arrivent tous de
# data/banc_infrastructure.json -- c'est ce qui permet au test de faire
# traverser le meme code par un domaine entierement invente.

const Depense = preload("res://scripts/depense.gd")
const Consommer = preload("res://scripts/consommer.gd")
const Comptage = preload("res://scripts/comptage.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Portee = preload("res://scripts/portee.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

# Marge de comparaison flottante, UNIQUEMENT pour decider qu'une navette est
# finie (charge pleine / charge vide) -- jamais pour le gate de capacite du
# grenier, qui reste une comparaison exacte (voir point (2) de l'en-tete).
const EPS := 0.0001

var _config: Dictionary = {}
var _comptages: Dictionary = {}
var _seuils_combustible: Dictionary = {}
var _etats: Dictionary = {}

var _etat: Dictionary = {}
var _actifs: int = 0
var _temps: float = 0.0
var _prochaine_trace: float = 0.0
var _dernier_bilan: Dictionary = {}

var _noeuds: Dictionary = {}          # id -> ColorRect (colons, lots, cases, grenier, tas)
var _labels: Dictionary = {}          # id -> Label
var _barre_fond: ColorRect
var _barre_grenier: ColorRect
var _label_compteur: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_infrastructure.json")
	_comptages = _charger_json("res://data/comptages.json")
	_seuils_combustible = _charger_json("res://data/seuils_combustible.json")
	_etats = _charger_json("res://data/etats.json")

	_etat = construire_monde(_config)
	_actifs = int(_config.colons.actifs_initial)

	_creer_rendu()
	_poser_camera()
	print(ligne_pose(_etat, _config))
	_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	_dernier_bilan = avancer(_etat, _config, _comptages, _seuils_combustible, _etats, delta)
	_rafraichir_tout()

	for ligne in lignes_evenement(_temps, _dernier_bilan, _etat, _config):
		print(ligne)

	if _temps >= _prochaine_trace:
		_prochaine_trace = _temps + float(_config.periode_trace_s)
		print(ligne_trace(_temps, _dernier_bilan, _etat, _config))

# ---- Les quatre toggles. Chacun delegue a une fonction PURE et se contente
# d'imprimer ce qu'elle rend -- le clic declenche, il ne calcule jamais.

func _toggle_colons(pas: int) -> void:
	_actifs = actifs_apres(_actifs, pas, _config)
	regler_actifs(_etat.colons, _actifs, _config)
	print(ligne_colons(_temps, _actifs))
	_rafraichir_tout()

func _toggle_grenier() -> void:
	var capacite := agrandir_grenier(_etat.grenier, _config)
	print(ligne_agrandissement(_temps, capacite, stock_grenier(_etat.grenier, _config)))
	_rafraichir_tout()

func _toggle_route() -> void:
	var reparees := reparer_route(_etat.route, _config)
	print(ligne_reparation(_temps, reparees, _config))
	_rafraichir_tout()

# =====================================================================
# Fonctions PURES, testables headless (voir test_banc_infrastructure.gd)
# =====================================================================

# ---- Construction ----

# Le monde complet du banc, en UN Dictionary : { grenier, tas, lots, route,
# colons }. Les cinq morceaux sont des Array/Dictionary nus de choses
# { id, position, proprietes } CONSTRUITES A LA MAIN (patron
# banc_faim_thermo.gd/banc_cratere.gd) -- ni composition, ni materiau, donc ni
# Objet.fabriquer ni data/types.json.
static func construire_monde(config: Dictionary) -> Dictionary:
	return {
		"grenier": construire_grenier(config),
		"tas": construire_tas(config),
		"lots": construire_lots(config),
		"route": construire_route(config),
		"colons": construire_colons(config),
	}

# Le grenier porte UN canal de stockage. `capacite_stockage` y est posee EN
# DONNEE mais n'est JAMAIS lue par depense.gd (qui ne borne que le bas) : c'est
# `est_plein`, et lui seul, qui s'en sert -- voir point (1) de l'en-tete.
# `cout_base` a 0.0 : ce qui est dans le grenier ne se depense pas de soi-meme
# (la degradation, elle, vit sur les LOTS, autre canal, autre objet).
static func construire_grenier(config: Dictionary) -> Dictionary:
	var decl: Dictionary = config.grenier
	var pos: Array = decl.position
	var canal: Dictionary = {
		"reserve": float(decl.stockage_initial),
		"cout_base": float(decl.cout_base),
		"surcout_action": 0.0,
		"seuils_ref": "",
	}
	canal[String(config.nom_capacite_stockage)] = float(decl.capacite_initiale)
	return {
		"id": String(decl.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": {
			"etats_actifs": [],
			"reserves": { String(config.nom_reserve_stockage): canal },
		},
	}

# Le tas exterieur : la SOURCE de la navette. Meme nom de reserve que le
# grenier -- consommer.gd ne connait que des noms de RESERVE, il ne saura
# jamais que l'un est un tas et l'autre un grenier.
static func construire_tas(config: Dictionary) -> Dictionary:
	var decl: Dictionary = config.tas
	var pos: Array = decl.position
	return {
		"id": String(decl.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": {
			"etats_actifs": [],
			"reserves": {
				String(config.nom_reserve_stockage): {
					"reserve": float(decl.stock_initial),
					"cout_base": 0.0,
					"surcout_action": 0.0,
					"seuils_ref": "",
				},
			},
		},
	}

# Les lots : des choses posees quelque part, dont l'integrite descend. Leur
# `cout_base` est REECRIT chaque tick par poser_surcout_degradation (voir point
# (3)) ; la valeur posee ici n'est qu'un depart lisible avant le premier tick.
static func construire_lots(config: Dictionary) -> Array:
	var deg: Dictionary = config.degradation
	var lots: Array = []
	for decl in deg.get("lots", []):
		var pos: Array = decl.position
		lots.append({
			"id": String(decl.id),
			"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			"proprietes": {
				"etats_actifs": [],
				"reserves": {
					String(config.nom_reserve_integrite): {
						"reserve": float(deg.integrite_lot),
						"capacite": float(deg.integrite_lot),
						"cout_base": cout_abri(config),
						"surcout_action": 0.0,
						"seuils_ref": "",
					},
				},
			},
		})
	return lots

# Les cases de route : des CASES-OBJETS ordinaires (docs/design.md,
# « Propagation et terrain » -- un terrain se modelise en objets, jamais une
# structure separee). Chacune porte `facteur_vitesse` en propriete PLATE : le
# cablage la lit pour composer la vitesse, et c'est depense.gd LUI-MEME qui la
# ramene a 1.0 au zero de la reserve (data/seuils_combustible.json:usure_route)
# -- ce fichier ne remet JAMAIS facteur_vitesse a 1.0 de sa main.
# `seuils_franchis` part vide et est REVIDE a chaque reparation : sans ca
# depense.gd n'appliquerait jamais deux fois le meme seuil (piege deja paye par
# banc_cratere.gd).
static func construire_route(config: Dictionary) -> Array:
	var r: Dictionary = config.route
	var cases: Array = []
	var rang := 0
	for pos in r.get("cases", []):
		var proprietes: Dictionary = {
			"reserves": {
				String(config.nom_reserve_route): {
					"reserve": float(r.duree_route),
					"capacite": float(r.duree_route),
					"cout_base": float(r.cout_base_route),
					"surcout_action": 0.0,
					"seuils_ref": String(r.seuils_ref),
					"seuils_franchis": [],
				},
			},
		}
		proprietes[String(config.nom_facteur_vitesse)] = float(r.facteur_vitesse)
		cases.append({
			"id": "route_%d" % rang,
			"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			"proprietes": proprietes,
		})
		rang += 1
	return cases

# population_max colons sont TOUS construits ; seuls les `actifs_initial`
# premiers portent la cle d'activite. Un colon inactif n'est pas retire du
# monde -- il est simplement absent du COMPTAGE (regle "presente" de
# data/comptages.json), ne bouge pas et ne travaille pas. C'est ce qui rend le
# toggle instantane et le comptage reel : comptage.gd recoit toujours la liste
# COMPLETE, c'est la regle qui trie.
# `decalage_x`/`decalage_y` sont deux FLOTTANTS (jamais un Vector3 dans
# proprietes -- resumabilite JSON stricte, docs/design.md) : ils ecartent les
# files d'attente pour que trente colons devant un meme grenier restent
# lisibles. Purement cosmetiques, jamais lus par un mecanisme.
static func construire_colons(config: Dictionary) -> Array:
	var c: Dictionary = config.colons
	var depart: Array = c.depart
	var colonnes: int = int(c.colonnes_depart)
	var espacement: float = float(c.espacement_depart)
	var colons: Array = []
	for i in range(int(c.population_max)):
		var colonne: int = i % colonnes
		var ligne: int = i / colonnes
		var canal: Dictionary = {
			"reserve": 0.0,
			"cout_base": 0.0,
			"surcout_action": 0.0,
			"seuils_ref": "",
		}
		canal[String(config.nom_capacite_charge)] = float(c.capacite_charge)
		var proprietes: Dictionary = {
			"etats_actifs": [],
			"reserves": { String(config.nom_reserve_charge): canal },
		}
		proprietes[String(config.nom_vitesse)] = float(c.vitesse_base)
		proprietes[String(config.nom_rythme)] = float(c.rythme_base)
		proprietes[String(config.nom_rythme_effectif)] = float(c.rythme_base)
		proprietes[String(config.nom_seuil_agents)] = float(c.seuil_agents)
		proprietes[String(config.nom_population_active)] = 0.0
		proprietes[String(config.nom_mode)] = String(config.mode_vers_tas)
		proprietes["decalage_x"] = (float(ligne) - 2.0) * 18.0
		proprietes["decalage_y"] = (float(colonne) - float(colonnes - 1) / 2.0) * 26.0
		colons.append({
			"id": "colon_%02d" % i,
			"position": Vector3(
				float(depart[0]) + float(colonne) * espacement,
				float(depart[1]) + float(ligne) * espacement,
				float(depart[2])),
			"proprietes": proprietes,
		})
	regler_actifs(colons, int(c.actifs_initial), config)
	return colons

# ---- Coordination (ligne 7 de l'audit) ----

static func est_actif(colon: Dictionary, config: Dictionary) -> bool:
	return colon.proprietes.has(String(config.nom_actif))

# Pose la cle d'activite sur les `nombre` premiers colons, la RETIRE sur les
# autres. Retirer plutot que poser `false` n'est pas un detail : la regle de
# comptage est en mode "presente", qui compte une cle presente QUELLE QUE SOIT
# sa valeur -- un `false` laisse en place compterait (voir comptage.gd).
static func regler_actifs(colons: Array, nombre: int, config: Dictionary) -> int:
	var cle := String(config.nom_actif)
	var poses := 0
	for i in range(colons.size()):
		if i < nombre:
			colons[i].proprietes[cle] = true
			poses += 1
		else:
			colons[i].proprietes.erase(cle)
	return poses

static func actifs_apres(actuel: int, pas: int, config: Dictionary) -> int:
	return clampi(actuel + pas, 0, int(config.colons.population_max))

# comptage.gd sur la liste COMPLETE -- il n'a aucune notion d'espace ni
# d'activite, c'est la regle de data/comptages.json qui trie. Rend un int,
# jamais une liste (contrat du mecanisme).
static func compter_actifs(colons: Array, comptages: Dictionary, config: Dictionary) -> int:
	return Comptage.compter(colons, String(config.comptage_ref), comptages)

# Le compte, recopie en cle PLATE sur CHAQUE colon -- seul moyen pour
# seuil_etat.gd de le comparer (il ne lit qu'une cle plate, jamais un
# sous-dictionnaire). Refait A NEUF chaque tick, jamais accumule : aucun
# objet-groupe n'existe (docs/design.md, « Les collectifs n'existent pas »).
static func poser_population(colons: Array, population: int, config: Dictionary) -> void:
	var cle := String(config.nom_population_active)
	for colon in colons:
		colon.proprietes[cle] = float(population)

# Le facteur de coordination, GATE PAR L'ETAT 'surpeuplement' (pose par
# seuil_etat.gd depuis le catalogue LOCAL du banc) : sous le seuil, exactement
# 1.0 -- jamais un « presque 1.0 » qui ferait douter. Au-dela :
# 1 - perte_efficacite * (population - seuil), borne par le bas pour qu'un
# nombre absurde de colons ne rende jamais un rythme NEGATIF. Le seuil est lu
# PAR COLON (proprietes[nom_seuil_agents]) : un colon qui ne le porte pas replie
# sur INF et n'est jamais surpeuple -- chemin mort silencieux, meme idiome que
# « un objet sans point_fusion ne fond jamais ».
static func facteur_coordination(colon: Dictionary, population: int, config: Dictionary) -> float:
	if not colon.proprietes.get("etats_actifs", []).has(String(config.etat_surpeuplement)):
		return 1.0
	var seuil: float = float(colon.proprietes.get(String(config.nom_seuil_agents), INF))
	var excedent: float = max(0.0, float(population) - seuil)
	var facteur: float = 1.0 - float(config.colons.perte_efficacite) * excedent
	return max(float(config.colons.facteur_min_coordination), facteur)

# UNIQUE ECRIVAIN de proprietes[nom_rythme_effectif]. Le rythme de BASE n'est
# jamais reecrit. Deux etages, dans cet ordre :
#   1. EtatEffectif.valeur -- composition multiplicative de TOUS les etats
#      actifs qui visent 'rythme' (aucun dans ce banc aujourd'hui ; 'heureux'
#      x1.1 et 'soumis' x0.7 en sont deja capables si un jour un colon les
#      porte). SANS CET APPEL, une modulation declaree dans data/etats.json
#      serait vraie dans le catalogue et INERTE dans le jeu, en silence --
#      banc_commun.gd:agents_rythme lit 'rythme' BRUTE. Voir point (5).
#   2. le facteur de coordination, propre a ce chantier.
# Rend { id -> rythme effectif } pour que l'affichage relise sans jamais
# recalculer.
static func poser_rythme_effectif(colons: Array, population: int, config: Dictionary, etats: Dictionary) -> Dictionary:
	var cle := String(config.nom_rythme_effectif)
	var rendus: Dictionary = {}
	for colon in colons:
		var base: float = EtatEffectif.valeur(colon, String(config.nom_rythme), etats)
		var effectif: float = base * facteur_coordination(colon, population, config)
		colon.proprietes[cle] = effectif
		rendus[colon.id] = effectif
	return rendus

# Relecture seule du champ deja ecrit -- jamais un second calcul.
static func rythme_effectif(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get(String(config.nom_rythme_effectif), 0.0))

# ---- Stockage fini (ligne 5 de l'audit) ----

static func canal_stockage(chose: Dictionary, config: Dictionary) -> Dictionary:
	return chose.proprietes.get("reserves", {}).get(String(config.nom_reserve_stockage), {})

static func stock_grenier(grenier: Dictionary, config: Dictionary) -> float:
	return float(canal_stockage(grenier, config).get("reserve", 0.0))

static func capacite_grenier(grenier: Dictionary, config: Dictionary) -> float:
	return float(canal_stockage(grenier, config).get(String(config.nom_capacite_stockage), 0.0))

# LE PREDICAT UNIQUE (point (2) de l'en-tete). Comparaison EXACTE `>=`, sans
# marge flottante : la marge ferait accepter un depot qui ferait passer la
# reserve au-dessus de sa capacite.
static func est_plein(grenier: Dictionary, config: Dictionary) -> bool:
	return stock_grenier(grenier, config) >= capacite_grenier(grenier, config)

# LE GATE, patron exact banc_graisse_accoutumance.gd:peut_manger. Le porteur
# refuse GARDE sa charge -- rien n'est ecrete, rien ne disparait.
static func peut_deposer(grenier: Dictionary, config: Dictionary) -> bool:
	return not est_plein(grenier, config)

# UNIQUE ECRIVAIN de l'etat 'encombre'. Pose ET retire depuis LE MEME predicat
# que le gate -- jamais un second calcul qui pourrait diverger au bord. Rend
# l'etat courant pour la trace et l'affichage.
static func poser_encombrement(grenier: Dictionary, config: Dictionary) -> bool:
	var plein := est_plein(grenier, config)
	var etat := String(config.etat_encombre)
	var actifs: Array = grenier.proprietes.get("etats_actifs", [])
	if plein:
		if not actifs.has(etat):
			actifs.append(etat)
	else:
		actifs.erase(etat)
	grenier.proprietes["etats_actifs"] = actifs
	return plein

static func est_encombre(grenier: Dictionary, config: Dictionary) -> bool:
	return grenier.proprietes.get("etats_actifs", []).has(String(config.etat_encombre))

# Toggle : +agrandissement de capacite, borne a capacite_max. La RESERVE n'est
# pas touchee -- agrandir un grenier ne le remplit pas. Rend la nouvelle
# capacite.
static func agrandir_grenier(grenier: Dictionary, config: Dictionary) -> float:
	var canal := canal_stockage(grenier, config)
	if canal.is_empty():
		push_error("banc_infrastructure : canal de stockage absent du grenier, agrandissement ignore")
		return 0.0
	var cle := String(config.nom_capacite_stockage)
	var nouvelle: float = min(
		float(canal.get(cle, 0.0)) + float(config.grenier.agrandissement),
		float(config.grenier.capacite_max))
	canal[cle] = nouvelle
	return nouvelle

# ---- Degradation hors stockage (ligne 6 de l'audit) ----

# « Suis-je a l'abri » = une comparaison de positions, deleguee a Portee (jamais
# reimplementee) -- patron banc_fertilite.gd:case_sous. Aucune notion de
# batiment, de mur ni de toit : un rayon autour du grenier, c'est tout.
static func abrite(lot: Dictionary, grenier: Dictionary, config: Dictionary) -> bool:
	return Portee.en_portee(lot.position, grenier.position, float(config.degradation.rayon_abri))

# Les deux taux, derives des DUREES DE VIE declarees en donnee plutot que
# poses en dur : integrite / duree_en_jours * jours_par_seconde. Changer
# duree_j_abri de 90 a 45 divise la duree de vie par deux sans une ligne de
# code.
static func cout_abri(config: Dictionary) -> float:
	var deg: Dictionary = config.degradation
	if float(deg.duree_j_abri) <= 0.0:
		return 0.0
	return float(deg.integrite_lot) * float(config.jours_par_seconde) / float(deg.duree_j_abri)

static func cout_exterieur(config: Dictionary) -> float:
	var deg: Dictionary = config.degradation
	if float(deg.duree_j_exterieur) <= 0.0:
		return 0.0
	return float(deg.integrite_lot) * float(config.jours_par_seconde) / float(deg.duree_j_exterieur)

# UNIQUE ECRIVAIN de cout_base ET surcout_action sur le canal d'integrite des
# LOTS (point (3) de l'en-tete). Ecriture COMPLETE a chaque tick, jamais un
# `+=` : un lot rentre a l'abri retombe exactement au cout d'abri, sans residu.
# `cout_base` porte la degradation d'abri (ce que le lot EST : de la matiere
# qui vieillit), `surcout_action` l'EXCEDENT du dehors -- depense.gd somme les
# deux, un lot dehors se degrade donc a cout_exterieur exactement.
# Pose aussi le miroir plat `abrite` sur le lot, pour l'affichage et la trace :
# ecrit dans LE MEME geste, depuis LE MEME test, jamais par une seconde
# fonction qui pourrait dire l'inverse.
# Rend { id -> { abrite, cout_base, surcout, total } } -- decomposition relue
# par l'affichage, jamais recalculee par lui.
static func poser_surcout_degradation(lots: Array, grenier: Dictionary, config: Dictionary) -> Dictionary:
	var base := cout_abri(config)
	var dehors := cout_exterieur(config)
	var cle_abrite := String(config.nom_abrite)
	var nom_integrite := String(config.nom_reserve_integrite)
	var rapport: Dictionary = {}
	for lot in lots:
		var sous_abri := abrite(lot, grenier, config)
		lot.proprietes[cle_abrite] = sous_abri
		var canal: Dictionary = lot.proprietes.get("reserves", {}).get(nom_integrite, {})
		if canal.is_empty():
			push_error("banc_infrastructure : canal '%s' absent du lot '%s', degradation non posee" % [nom_integrite, lot.id])
			continue
		var surcout: float = 0.0 if sous_abri else max(0.0, dehors - base)
		canal["cout_base"] = base
		canal["surcout_action"] = surcout
		rapport[lot.id] = {
			"abrite": sous_abri,
			"cout_base": base,
			"surcout": surcout,
			"total": base + surcout,
		}
	return rapport

static func integrite(lot: Dictionary, config: Dictionary) -> float:
	return float(lot.proprietes.get("reserves", {}).get(String(config.nom_reserve_integrite), {}).get("reserve", 0.0))

# ---- Routes (ligne 8 de l'audit) ----

# La case sous une chose, a portee_case pres -- patron exact
# banc_fertilite.gd:case_sous. Rend null si aucune : etre hors route est un
# fait neutre legitime, jamais une alarme. La PREMIERE case a portee gagne (les
# cases se recouvrent legerement) -- deterministe, l'ordre est celui de la
# donnee.
static func case_sous(chose: Dictionary, cases: Array, portee: float) -> Variant:
	for case in cases:
		if Portee.en_portee(chose.position, case.position, portee):
			return case
	return null

# 1.0 hors route -- le NEUTRE de la multiplication, jamais une branche
# separee. Sur une case usee, c'est depense.gd qui a deja repose
# facteur_vitesse a 1.0 : ce cablage lit simplement ce qu'il trouve.
static func facteur_vitesse_sous(chose: Dictionary, cases: Array, config: Dictionary) -> float:
	var case: Variant = case_sous(chose, cases, float(config.route.rayon_case))
	if case == null:
		return 1.0
	return float(case.proprietes.get(String(config.nom_facteur_vitesse), 1.0))

# vitesse effective = vitesse modulee par les etats x facteur de la case sous
# les pieds. EtatEffectif.valeur n'est JAMAIS reimplementee -- patron litteral
# banc_friction.gd:vitesse_effective (base x facteur) et
# banc_faim_thermo.gd:vitesse_effective.
static func vitesse_effective(colon: Dictionary, cases: Array, config: Dictionary, etats: Dictionary) -> float:
	return EtatEffectif.valeur(colon, String(config.nom_vitesse), etats) * facteur_vitesse_sous(colon, cases, config)

# Vrai quand le colon est en TRANSIT (il marche), faux quand il est a un poste
# de travail (il charge ou il decharge).
static func en_transit(colon: Dictionary, config: Dictionary) -> bool:
	var mode := String(colon.proprietes.get(String(config.nom_mode), ""))
	return mode == String(config.mode_vers_tas) or mode == String(config.mode_vers_grenier)

# Combien de colons ACTIFS ET EN TRANSIT foulent chaque case a cet instant. Un
# colon dans une zone de recouvrement compte pour UNE case (celle que case_sous
# rend).
#
# LE FILTRE `en_transit` EST UNE DECISION, TROUVEE EN LANCANT LA SCENE : sans
# lui, une file ARRETEE devant le grenier plein (les colons s'immobilisent a
# portee_travail de leur cible, donc encore dans le rayon de la derniere case)
# usait la route a plein regime alors que plus personne ne marchait -- une
# route usee par des gens qui attendent, ce qui n'a aucun sens. « Par
# passage » veut dire par PASSAGE : un colon qui charge ou decharge n'en est
# pas un.
static func trafic_par_case(cases: Array, colons: Array, config: Dictionary) -> Dictionary:
	var compte: Dictionary = {}
	for case in cases:
		compte[case.id] = 0
	var portee := float(config.route.rayon_case)
	for colon in colons:
		if not est_actif(colon, config) or not en_transit(colon, config):
			continue
		var case: Variant = case_sous(colon, cases, portee)
		if case != null:
			compte[case.id] = int(compte[case.id]) + 1
	return compte

# UNIQUE ECRIVAIN de surcout_action sur les canaux de ROUTE (point (3) de
# l'en-tete). `cout_base` reste celui pose a la construction (l'usure du temps,
# ce que la route EST) et n'est jamais reecrit ici ; `surcout_action` porte le
# TRAFIC (l'action en cours). Ecriture complete chaque tick : une case que
# personne ne foule retombe exactement a 0.0 de surcout.
# Rend { id -> surcout pose } pour la trace.
static func poser_usure_routes(cases: Array, colons: Array, config: Dictionary) -> Dictionary:
	var trafic := trafic_par_case(cases, colons, config)
	var cout := float(config.route.cout_par_passage)
	var nom := String(config.nom_reserve_route)
	var poses: Dictionary = {}
	for case in cases:
		var canal: Dictionary = case.proprietes.get("reserves", {}).get(nom, {})
		if canal.is_empty():
			push_error("banc_infrastructure : canal '%s' absent de la case '%s', usure non posee" % [nom, case.id])
			continue
		var surcout: float = float(trafic.get(case.id, 0)) * cout
		canal["surcout_action"] = surcout
		poses[case.id] = surcout
	return poses

# Toggle : recharge la reserve A NEUF, VIDE seuils_franchis et REND le facteur
# de vitesse declare en donnee. Les trois gestes sont solidaires -- sans le
# vidage, depense.gd n'appliquerait jamais une deuxieme fois le seuil et une
# route reparee ne pourrait plus jamais s'user (piege deja paye par
# banc_cratere.gd:impacter). Rend le nombre de cases reparees.
static func reparer_route(cases: Array, config: Dictionary) -> int:
	var r: Dictionary = config.route
	var nom := String(config.nom_reserve_route)
	var cle_facteur := String(config.nom_facteur_vitesse)
	var reparees := 0
	for case in cases:
		var canal: Dictionary = case.proprietes.get("reserves", {}).get(nom, {})
		if canal.is_empty():
			push_error("banc_infrastructure : canal '%s' absent de la case '%s', reparation ignoree" % [nom, case.id])
			continue
		canal["reserve"] = float(r.duree_route)
		canal["capacite"] = float(r.duree_route)
		canal["seuils_franchis"] = []
		case.proprietes[cle_facteur] = float(r.facteur_vitesse)
		reparees += 1
	return reparees

static func usure_route(case: Dictionary, config: Dictionary) -> float:
	return float(case.proprietes.get("reserves", {}).get(String(config.nom_reserve_route), {}).get("reserve", 0.0))

# ---- La navette ----

static func charge_de(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_charge), {}).get("reserve", 0.0))

static func capacite_charge(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_charge), {})
		.get(String(config.nom_capacite_charge), 0.0))

# La cible REELLE d'un colon : le point de travail plus son decalage de file.
# Purement cosmetique (voir construire_colons), mais utilise AUSSI pour le test
# d'arrivee -- sinon un colon viserait un point et se declarerait arrive sur un
# autre.
static func cible_de(colon: Dictionary, point: Vector3) -> Vector3:
	return point + Vector3(
		float(colon.proprietes.get("decalage_x", 0.0)),
		float(colon.proprietes.get("decalage_y", 0.0)),
		0.0)

# Un pas de deplacement, borne a la distance restante (BancCommun.bouger_vers,
# jamais reimplemente). Rend la vitesse effective employee, pour la trace.
static func deplacer_vers(colon: Dictionary, point: Vector3, cases: Array, config: Dictionary, etats: Dictionary, delta: float) -> float:
	var vitesse := vitesse_effective(colon, cases, config, etats)
	colon.position = BancCommun.bouger_vers(colon.position, cible_de(colon, point), vitesse, delta)
	return vitesse

# LA MACHINE A ETATS DE LA NAVETTE -- du CABLAGE, jamais une decision (voir
# en-tete, CE QUE CE BANC NE MONTRE PAS). Quatre modes en boucle :
# vers_tas -> charge -> vers_grenier -> depot -> vers_tas.
#
# LES DEUX QUANTITES SONT PRE-BORNEES, et ce n'est PAS le pre-bornage devenu
# redondant autour de consommer.gd (celui-la bornait a la SOURCE, que le
# mecanisme borne desormais lui-meme) : ici on borne au PLAFOND du receveur,
# que rien dans le coeur ne connait. Le taux etant deja resolu en quantite, on
# passe delta=1.0 -- idiome exact de banc_fertilite.gd:avancer_cadavres.
#
# LE REFUS EST LE POINT DU CHANTIER : grenier plein, aucun transfert n'est
# tente, le colon reste en mode depot AVEC sa charge. Rien n'est ecrete, rien
# ne disparait, et il repartira des que la capacite grandit.
# Rend { charge, depose, refus, en_route } -- diagnostic de trace.
static func avancer_colons(
	colons: Array,
	tas: Dictionary,
	grenier: Dictionary,
	cases: Array,
	config: Dictionary,
	etats: Dictionary,
	delta: float,
) -> Dictionary:
	var c: Dictionary = config.colons
	var nom_mode := String(config.nom_mode)
	var nom_stock := String(config.nom_reserve_stockage)
	var nom_charge := String(config.nom_reserve_charge)
	var portee := float(c.portee_travail)

	var m_vers_tas := String(config.mode_vers_tas)
	var m_charge := String(config.mode_charge)
	var m_vers_grenier := String(config.mode_vers_grenier)
	var m_depot := String(config.mode_depot)

	var total_charge := 0.0
	var total_depose := 0.0
	var refus := 0
	var en_route := 0

	for colon in colons:
		if not est_actif(colon, config):
			continue
		var mode := String(colon.proprietes.get(nom_mode, m_vers_tas))
		var rythme := rythme_effectif(colon, config)

		if mode == m_vers_tas:
			deplacer_vers(colon, tas.position, cases, config, etats, delta)
			en_route += 1
			if colon.position.distance_to(cible_de(colon, tas.position)) <= portee:
				mode = m_charge

		elif mode == m_charge:
			var place: float = max(0.0, capacite_charge(colon, config) - charge_de(colon, config))
			var quantite: float = min(float(c.taux_charge) * rythme * delta, place)
			var epuise := false
			if quantite > 0.0:
				var r := Consommer.transferer(tas, colon, nom_stock, nom_charge, quantite, 1.0)
				total_charge += float(r.quantite)
				epuise = bool(r.source_epuisee)
			if place <= EPS or (epuise and charge_de(colon, config) > 0.0):
				mode = m_vers_grenier

		elif mode == m_vers_grenier:
			deplacer_vers(colon, grenier.position, cases, config, etats, delta)
			en_route += 1
			if colon.position.distance_to(cible_de(colon, grenier.position)) <= portee:
				mode = m_depot

		elif mode == m_depot:
			if not peut_deposer(grenier, config):
				refus += 1
			else:
				var place_grenier: float = max(0.0, capacite_grenier(grenier, config) - stock_grenier(grenier, config))
				var quantite_d: float = min(float(c.taux_depot) * rythme * delta, place_grenier)
				if quantite_d > 0.0:
					total_depose += float(Consommer.transferer(colon, grenier, nom_charge, nom_stock, quantite_d, 1.0).quantite)
			if charge_de(colon, config) <= EPS:
				mode = m_vers_tas

		else:
			push_error("banc_infrastructure : mode inconnu '%s' sur '%s', remis a l'etat initial" % [mode, colon.id])
			mode = m_vers_tas

		colon.proprietes[nom_mode] = mode

	return {
		"charge": total_charge,
		"depose": total_depose,
		"refus": refus,
		"en_route": en_route,
	}

# ---- LE PAS COMPLET, seul appele par _process ----

# ORDRE FIXE, et trois inversions seraient fausses :
# - le COMPTAGE avant seuil_etat.gd : sans population_active a jour, le seuil
#   comparerait celle du tick precedent ;
# - poser_rythme_effectif APRES seuil_etat.gd : le facteur de coordination est
#   GATE par l'etat 'surpeuplement' que seuil_etat.gd vient de poser ;
# - poser_usure_routes AVANT Depense.avancer : le surcout de trafic doit etre
#   sur le canal quand le mecanisme le lit, sinon l'usure d'un tick est
#   toujours celle du tick d'avant.
# poser_encombrement vient EN DERNIER, apres les depots : l'etat affiche est
# alors celui de la FIN du tick. Le REFUS, lui, ne l'attend pas -- il lit
# `est_plein` directement, il est donc exact a l'instant meme du depot.
static func avancer(
	etat: Dictionary,
	config: Dictionary,
	comptages: Dictionary,
	seuils_combustible: Dictionary,
	etats: Dictionary,
	delta: float,
) -> Dictionary:
	var population := compter_actifs(etat.colons, comptages, config)
	poser_population(etat.colons, population, config)
	var bascules := SeuilEtat.avancer(etat.colons, config.seuils_locaux)
	var rythmes := poser_rythme_effectif(etat.colons, population, config, etats)

	var degradation := poser_surcout_degradation(etat.lots, etat.grenier, config)
	var usure := poser_usure_routes(etat.route, etat.colons, config)
	var franchis := Depense.avancer(etat.lots + etat.route, delta, seuils_combustible)

	var travail := avancer_colons(etat.colons, etat.tas, etat.grenier, etat.route, config, etats, delta)
	var plein := poser_encombrement(etat.grenier, config)

	return {
		"population": population,
		"bascules": bascules,
		"rythmes": rythmes,
		"degradation": degradation,
		"usure": usure,
		"franchis": franchis,
		"travail": travail,
		"plein": plein,
	}

# ---- Couleurs (pures) ----

static func couleur_lot(lot: Dictionary, config: Dictionary) -> Color:
	var couleurs: Dictionary = config.couleurs
	var vive := _couleur(couleurs.lot_abrite if bool(lot.proprietes.get(String(config.nom_abrite), false)) else couleurs.lot_dehors)
	var ruine := _couleur(couleurs.lot_ruine)
	var capacite := float(config.degradation.integrite_lot)
	if capacite <= 0.0:
		return ruine
	return ruine.lerp(vive, clamp(integrite(lot, config) / capacite, 0.0, 1.0))

static func couleur_case_route(case: Dictionary, config: Dictionary) -> Color:
	var couleurs: Dictionary = config.couleurs
	var neuve := _couleur(couleurs.route_neuve)
	var usee := _couleur(couleurs.route_usee)
	var capacite := float(config.route.duree_route)
	if capacite <= 0.0:
		return usee
	return usee.lerp(neuve, clamp(usure_route(case, config) / capacite, 0.0, 1.0))

static func couleur_colon(colon: Dictionary, config: Dictionary) -> Color:
	var couleurs: Dictionary = config.couleurs
	if not est_actif(colon, config):
		return _couleur(couleurs.colon_inactif)
	if charge_de(colon, config) > EPS:
		return _couleur(couleurs.colon_charge)
	return _couleur(couleurs.colon_vide)

static func couleur_grenier(grenier: Dictionary, config: Dictionary) -> Color:
	var couleurs: Dictionary = config.couleurs
	return _couleur(couleurs.grenier_plein if est_encombre(grenier, config) else couleurs.grenier)

static func _couleur(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))

# ---- Textes (purs -- aucun nombre n'y est recalcule) ----

static func texte_compteur(etat: Dictionary, config: Dictionary, bilan: Dictionary, temps: float) -> String:
	var population := int(bilan.get("population", 0))
	return "t=%.1f s -- population active %d / %d (seuil %d) -- rythme effectif x%.2f -- grenier %.1f / %.1f%s" % [
		temps,
		population,
		int(config.colons.population_max),
		int(config.colons.seuil_agents),
		_rythme_moyen(bilan),
		stock_grenier(etat.grenier, config),
		capacite_grenier(etat.grenier, config),
		"  [PLEIN -- depots refuses]" if bool(bilan.get("plein", false)) else "",
	]

static func texte_aide(config: Dictionary) -> String:
	return ("+/- COLONS : au-dela de %d actifs, chacun travaille moins vite   |   " +
		"AGRANDIR : +%.0f de capacite au grenier   |   " +
		"REPARER : la route redonne son x%.1f") % [
			int(config.colons.seuil_agents),
			float(config.grenier.agrandissement),
			float(config.route.facteur_vitesse),
		]

static func texte_grenier(grenier: Dictionary, config: Dictionary) -> String:
	return "%s\n%.1f / %.1f%s" % [
		grenier.id,
		stock_grenier(grenier, config),
		capacite_grenier(grenier, config),
		"\nENCOMBRE" if est_encombre(grenier, config) else "",
	]

static func texte_tas(tas: Dictionary, config: Dictionary) -> String:
	return "%s\nreste %.0f" % [tas.id, float(canal_stockage(tas, config).get("reserve", 0.0))]

static func texte_lot(lot: Dictionary, config: Dictionary) -> String:
	var sous_abri := bool(lot.proprietes.get(String(config.nom_abrite), false))
	return "%s\n%.1f\n%s" % [
		lot.id,
		integrite(lot, config),
		"abri" if sous_abri else "dehors",
	]

static func texte_case_route(case: Dictionary, config: Dictionary) -> String:
	return "%s\nx%.2f\n%.1f s" % [
		case.id,
		float(case.proprietes.get(String(config.nom_facteur_vitesse), 1.0)),
		usure_route(case, config),
	]

static func ligne_pose(etat: Dictionary, config: Dictionary) -> String:
	return ("t=0.0 pose : grenier %.0f / %.0f, tas %.0f, %d lots (%d a l'abri), %d cases de route a x%.1f, " +
		"%d colons dont %d actifs (seuil de coordination %d)") % [
			stock_grenier(etat.grenier, config),
			capacite_grenier(etat.grenier, config),
			float(canal_stockage(etat.tas, config).get("reserve", 0.0)),
			etat.lots.size(),
			_compter_abrites(etat.lots, etat.grenier, config),
			etat.route.size(),
			float(config.route.facteur_vitesse),
			etat.colons.size(),
			int(config.colons.actifs_initial),
			int(config.colons.seuil_agents),
		]

static func ligne_colons(t: float, actifs: int) -> String:
	return "t=%.1f COLONS ACTIFS : %d" % [t, actifs]

static func ligne_agrandissement(t: float, capacite: float, stock: float) -> String:
	return "t=%.1f GRENIER AGRANDI : capacite %.0f (stock %.1f)" % [t, capacite, stock]

static func ligne_reparation(t: float, reparees: int, config: Dictionary) -> String:
	return "t=%.1f ROUTE REPAREE : %d cases rechargees a %.0f s, seuils_franchis vides, facteur rendu a x%.1f" % [
		t, reparees, float(config.route.duree_route), float(config.route.facteur_vitesse),
	]

# Les evenements du tick qui meritent une ligne a eux : un seuil de route
# franchi (depense.gd vient de reposer facteur_vitesse a 1.0) et une bascule
# d'etat (seuil_etat.gd rend les ids, jamais QUELS etats -- d'ou la relecture
# cote cablage).
static func lignes_evenement(t: float, bilan: Dictionary, etat: Dictionary, config: Dictionary) -> Array:
	var lignes: Array = []
	for id in bilan.get("franchis", []):
		for case in etat.route:
			if case.id == id:
				lignes.append("t=%.1f ROUTE USEE : %s epuisee, depense.gd repose %s a x%.1f" % [
					t, id, String(config.nom_facteur_vitesse),
					float(case.proprietes.get(String(config.nom_facteur_vitesse), 1.0)),
				])
	if not bilan.get("bascules", []).is_empty():
		lignes.append("t=%.1f COORDINATION : %d colons ont bascule (population %d, seuil %d)" % [
			t, bilan.bascules.size(), int(bilan.get("population", 0)), int(config.colons.seuil_agents),
		])
	return lignes

static func ligne_trace(t: float, bilan: Dictionary, etat: Dictionary, config: Dictionary) -> String:
	var travail: Dictionary = bilan.get("travail", {})
	return ("t=%.1f pop=%d rythme=x%.2f | grenier %.1f/%.1f%s | ce tick charge=%.2f depose=%.2f refus=%d | " +
		"lots abri %.1f / dehors %.1f | route min %.1f s") % [
			t,
			int(bilan.get("population", 0)),
			_rythme_moyen(bilan),
			stock_grenier(etat.grenier, config),
			capacite_grenier(etat.grenier, config),
			" PLEIN" if bool(bilan.get("plein", false)) else "",
			float(travail.get("charge", 0.0)),
			float(travail.get("depose", 0.0)),
			int(travail.get("refus", 0)),
			_integrite_moyenne(etat.lots, config, true),
			_integrite_moyenne(etat.lots, config, false),
			_usure_min(etat.route, config),
		]

static func _rythme_moyen(bilan: Dictionary) -> float:
	var rythmes: Dictionary = bilan.get("rythmes", {})
	if rythmes.is_empty():
		return 0.0
	var total := 0.0
	for id in rythmes:
		total += float(rythmes[id])
	return total / float(rythmes.size())

static func _compter_abrites(lots: Array, grenier: Dictionary, config: Dictionary) -> int:
	var compte := 0
	for lot in lots:
		if abrite(lot, grenier, config):
			compte += 1
	return compte

static func _integrite_moyenne(lots: Array, config: Dictionary, sous_abri: bool) -> float:
	var total := 0.0
	var nombre := 0
	for lot in lots:
		if bool(lot.proprietes.get(String(config.nom_abrite), false)) != sous_abri:
			continue
		total += integrite(lot, config)
		nombre += 1
	return total / float(nombre) if nombre > 0 else 0.0

static func _usure_min(cases: Array, config: Dictionary) -> float:
	var minimum := INF
	for case in cases:
		minimum = min(minimum, usure_route(case, config))
	return 0.0 if minimum == INF else minimum

# =====================================================================
# Rendu (impur, Node) -- aucune decision, seulement des noeuds, des
# couleurs et des longueurs de barre.
# =====================================================================

func _creer_rendu() -> void:
	var rendu: Dictionary = _config.rendu

	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.color = _couleur(_config.couleurs.fond)
	fond.position = Vector2(-600.0, -300.0)
	fond.size = Vector2(2400.0, 1400.0)
	add_child(fond)

	# La route d'abord : les colons doivent passer PAR-DESSUS.
	for case in _etat.route:
		_creer_carre(case, Vector2(float(rendu.taille_case_route), float(rendu.hauteur_case_route)), int(rendu.taille_police))
	_creer_carre(_etat.tas, Vector2(float(rendu.taille_tas), float(rendu.taille_tas)), int(rendu.taille_police))
	_creer_carre(_etat.grenier, Vector2(float(rendu.taille_grenier), float(rendu.taille_grenier)), int(rendu.taille_police))
	for lot in _etat.lots:
		_creer_carre(lot, Vector2(float(rendu.taille_lot), float(rendu.taille_lot)), int(rendu.taille_police))
	for colon in _etat.colons:
		_creer_carre(colon, Vector2(float(rendu.taille_colon), float(rendu.taille_colon)), 0)

	# La barre de capacite du grenier, au-dessus de lui : fond fixe (la
	# capacite max declaree) + remplissage, seul a changer de taille -- meme
	# patron que banc_bonheur.gd/banc_nutrition.gd.
	var centre := Vector2(_etat.grenier.position.x, _etat.grenier.position.y)
	var origine := centre - Vector2(float(rendu.largeur_barre_grenier) / 2.0,
		float(rendu.taille_grenier) / 2.0 + float(rendu.hauteur_barre_grenier) + 10.0)
	_barre_fond = _creer_barre(_couleur(_config.couleurs.barre_fond), origine,
		float(rendu.largeur_barre_grenier), float(rendu.hauteur_barre_grenier))
	_barre_grenier = _creer_barre(_couleur(_config.couleurs.barre_remplie), origine,
		0.0, float(rendu.hauteur_barre_grenier))

	var couche := CanvasLayer.new()
	add_child(couche)
	_label_compteur = _creer_label_fixe(int(rendu.taille_police_compteur), Vector2(10.0, 10.0))
	couche.add_child(_label_compteur)
	_label_aide = _creer_label_fixe(int(rendu.taille_police), Vector2(10.0, 38.0))
	_label_aide.text = texte_aide(_config)
	couche.add_child(_label_aide)

	var pas := int(_config.colons.pas_toggle)
	_creer_bouton(couche, "+%d COLONS" % pas, Vector2(10.0, 66.0), func(): _toggle_colons(pas))
	_creer_bouton(couche, "-%d COLONS" % pas, Vector2(130.0, 66.0), func(): _toggle_colons(-pas))
	_creer_bouton(couche, "AGRANDIR LE GRENIER", Vector2(250.0, 66.0), _toggle_grenier)
	_creer_bouton(couche, "REPARER LA ROUTE", Vector2(430.0, 66.0), _toggle_route)

func _creer_carre(chose: Dictionary, taille: Vector2, taille_police: int) -> void:
	var centre := Vector2(chose.position.x, chose.position.y)
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = taille
	noeud.position = centre - taille / 2.0
	add_child(noeud)
	_noeuds[chose.id] = noeud
	if taille_police <= 0:
		return
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille_police)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	label.position = centre + Vector2(-taille.x / 2.0, taille.y / 2.0 + 4.0)
	add_child(label)
	_labels[chose.id] = label

func _creer_barre(couleur: Color, origine: Vector2, largeur: float, hauteur: float) -> ColorRect:
	var barre := ColorRect.new()
	barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barre.color = couleur
	barre.position = origine
	barre.size = Vector2(largeur, hauteur)
	add_child(barre)
	return barre

func _creer_label_fixe(taille: int, position_ecran: Vector2) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	label.position = position_ecran
	return label

func _creer_bouton(couche: CanvasLayer, texte: String, position_ecran: Vector2, action: Callable) -> void:
	var bouton := Button.new()
	bouton.text = texte
	bouton.position = position_ecran
	bouton.pressed.connect(action)
	couche.add_child(bouton)

func _rafraichir_tout() -> void:
	var rendu: Dictionary = _config.rendu

	_noeuds[_etat.grenier.id].color = couleur_grenier(_etat.grenier, _config)
	_labels[_etat.grenier.id].text = texte_grenier(_etat.grenier, _config)
	_noeuds[_etat.tas.id].color = _couleur(_config.couleurs.tas)
	_labels[_etat.tas.id].text = texte_tas(_etat.tas, _config)

	var capacite := capacite_grenier(_etat.grenier, _config)
	var reference: float = max(capacite, float(_config.grenier.capacite_max))
	_barre_fond.size.x = float(rendu.largeur_barre_grenier) * (capacite / reference if reference > 0.0 else 0.0)
	_barre_grenier.size.x = float(rendu.largeur_barre_grenier) * (
		clamp(stock_grenier(_etat.grenier, _config) / reference, 0.0, 1.0) if reference > 0.0 else 0.0)

	for lot in _etat.lots:
		_noeuds[lot.id].color = couleur_lot(lot, _config)
		_labels[lot.id].text = texte_lot(lot, _config)
	for case in _etat.route:
		_noeuds[case.id].color = couleur_case_route(case, _config)
		_labels[case.id].text = texte_case_route(case, _config)
	for colon in _etat.colons:
		var noeud: ColorRect = _noeuds[colon.id]
		noeud.color = couleur_colon(colon, _config)
		noeud.position = Vector2(colon.position.x, colon.position.y) - noeud.size / 2.0

	_label_compteur.text = texte_compteur(_etat, _config, _dernier_bilan, _temps)

func _poser_camera() -> void:
	var decl: Dictionary = _config.get("camera", {})
	var pos: Array = decl.get("position", [0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(float(pos[0]), float(pos[1]))
	camera.zoom = Vector2(float(decl.get("zoom", 1.0)), float(decl.get("zoom", 1.0)))
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
