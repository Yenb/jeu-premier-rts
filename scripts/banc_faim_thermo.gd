extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_faim_thermo.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « faim +
# thermoregulation -- un seul banc » (audit prealable
# audit_mecaniques_corps_prealable.md, lignes 1 et 11, toutes deux au verdict
# CABLABLE -- confirme a l'ecriture : AUCUN mecanisme du coeur touche ni cree).
#
# CE QU'ON DOIT VOIR : un colon qui marche sans fin entre des points tires au
# sort et qui n'a RIEN A MANGER. Son energie ne peut que descendre : elle part
# en metabolisme de base (cout_base, pose une fois a la construction), en
# effort de marche (proportionnel a sa velocite reelle) et en lutte thermique
# (proportionnelle a son ecart au confort). Il traverse une zone FROIDE (disque
# bleu, a gauche) et une zone CHAUDE (disque rouge, a droite) separees par du
# neutre (fond vert) ou rien ne lui coute que d'exister et de marcher. Il finit
# affame -- donc plus lent, donc depensant moins -- puis, energie a zero, il
# s'arrete pour de bon.
#
# LE PATRON QUE CE BANC EXISTE POUR PROUVER -- UNE SEULE ECRITURE DE
# surcout_action PAR TICK. depense.gd calcule reserve -= (cout_base +
# surcout_action) * delta : il n'y a QU'UN SEUL emplacement surcout_action par
# canal. Trois choses veulent y ecrire ici (l'effort, le froid, le chaud). Si
# trois morceaux de cablage ecrivaient chacun le leur, le dernier ecraserait
# les deux autres EN SILENCE -- aucun test ne rougirait, la depense serait
# simplement fausse. `poser_surcout_action` est donc l'UNIQUE ECRIVAIN de ce
# champ dans tout ce fichier : elle somme les trois contributions et ecrit une
# fois, puis rend leur DECOMPOSITION pour l'affichage -- l'affichage relit des
# nombres deja calcules, il n'en recalcule jamais aucun (meme discipline que
# banc_emergences.gd, dont le label detaille sans jamais reevaluer). Piege
# nomme par audit_mecaniques_corps_prealable.md, constat D ; aucun banc
# existant du depot ne l'avait rencontre (chacun n'a qu'une source de surcout).
#
# TROIS MIROIRS PLATS, ET POURQUOI ILS SONT OBLIGATOIRES. seuil_etat.gd ne
# sait lire qu'une cle PLATE de proprietes (une reserve vit sous
# proprietes.reserves.<nom>.reserve -- un chemin en points qu'il ne parcourt
# jamais) et ne compare que VERS LE HAUT (valeur > seuil). « L'energie descend
# sous un seuil » et « il fait trop froid » ne sont donc PAS exprimables
# directement. Le cablage ecrit chaque tick trois proprietes plates qui MONTENT
# quand la situation empire -- manque_energie (capacite - reserve),
# froid_ressenti (max(0, temp_cible - temperature locale)), chaud_ressenti
# (max(0, temperature locale - seuil_chaud)) -- et les quatre entrees de
# data/seuils_etat.json les comparent. Constat B du meme audit ; precedent
# exact : dose_radiation_objet dans banc_activation_neutronique.gd.
#
# DEUX MIROIRS THERMIQUES, JAMAIS UN abs() UNIQUE (question laissee ouverte par
# l'audit §11, tranchee ici) : le froid bascule sous temp_cible et le chaud
# au-dessus de seuil_chaud -- deux nombres DIFFERENTS en donnee -- avec deux
# couts par degre differents. Un abs() les aurait forces a etre symetriques,
# ce qui est physiquement faux. Tant que seuil_chaud >= temp_cible, les deux
# miroirs ne sont jamais non nuls en meme temps (verrouille par test).
#
# CES TROIS MIROIRS SONT REVERSIBLES, contrairement a TOUTES les grandeurs
# cumulees du depot (degats_impact_cumules, force_traction_cumulee,
# duree_maladie_cumulee...) qui ne redescendent jamais : ils sont RECALCULES a
# neuf chaque tick depuis l'etat courant, jamais accumules par `+=`. C'est ce
# qui rend les quatre etats reversibles sans une ligne de plus -- seuil_etat.gd
# retire au franchissement descendant. Le froid le montre EN DIRECT (le colon
# sort de la zone bleue et perd hypothermie puis frisson, dans cet ordre) ; la
# faim, elle, ne le montre jamais ici faute de nourriture -- REVERSIBILITE
# PROUVEE PAR LE TEST SEUL, meme statut que la guerison de 'malade' dans
# banc_maladie.gd, dit plutot que masque.
#
# LA TEMPERATURE DU CORPS N'EXISTE PAS DANS CE BANC, choix assume :
# temperature.gd:avancer n'est JAMAIS appele, le colon ne porte aucune
# propriete `temperature`, et les deux miroirs thermiques lisent la temperature
# LOCALE (temperature.gd:locale, l'ambiante plus les zones a portee) --
# c'est-a-dire ce qu'il FAIT autour de lui, pas ce qu'il vaut lui-meme. Y
# ajouter l'inertie thermique du corps (conductivite_thermique/
# chaleur_specifique, deja portees par temperature.gd) serait un autre
# chantier : le colon mettrait du temps a se refroidir en entrant dans le bleu
# et resterait froid un moment en en sortant. Rien ici ne l'empeche ; ce n'est
# simplement pas demande. Consequence a connaitre : le colon ne portant pas
# `temperature`, les entrees point_fusion/point_ebullition/sublimation/chaud du
# catalogue PARTAGE data/seuils_etat.json sont pour lui des chemins morts
# silencieux -- aucune collision possible avec les quatre entrees de ce
# chantier.
#
# L'ARRET FINAL EST UN GATE DE CABLAGE, PAS UN ETAT. Quand la reserve atteint
# 0.0 (bornee la par depense.gd), `vitesse_effective` rend 0.0 et le colon ne
# bouge plus. Aucun etat « epuise » n'a ete ajoute a data/etats.json : la
# consigne n'en demandait aucun, et un etat de plus dans un catalogue PARTAGE
# se paie pour tout le depot. C'est le meme geste de gate que
# banc_conduction.gd:375 / banc_corrosion.gd:300 (le cablage lit une condition
# et ecrit lui-meme le nombre) -- depense.gd ne consulte jamais
# etat_effectif.gd, et etat_effectif.gd ne pose jamais aucun etat.
#
# ORDRE DU TICK, et le retard d'UN tick qu'il implique. velocite.gd est une
# DERIVATION PASSIVE : son contrat exige qu'il soit le DERNIER appel du
# _process, apres tout ce qui mute position. Le surcout d'effort d'un tick est
# donc calcule depuis la velocite MESUREE AU TICK PRECEDENT. Ce retard est
# inherent au mecanisme, pas un defaut de ce banc : l'alternative (deriver la
# velocite avant de bouger) casserait la garantie « un seul ecrivain de
# velocite » que velocite.gd existe pour tenir. A 60 images/s, un tick de
# retard sur un surcout se voit sur la quatrieme decimale d'une reserve.
#
# COLON CONSTRUIT A LA MAIN (pas Objet.fabriquer, meme statut que
# banc_maladie.gd/banc_ecoulement.gd/banc_biomes.gd) : il n'a ni composition ni
# materiau, donc ni masse ni densite a calculer, et data/types.json n'est pas
# touche par ce chantier.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit le colon, les zones et le rendu ; _process
#   enchaine les cinq mecanismes du coeur, TOUS APPELES TELS QUELS
#   (Temperature.locale -> poser_surcout_action -> Depense.avancer ->
#   poser_manque_energie -> SeuilEtat.avancer -> vitesse_effective ->
#   deplacement -> Velocite.avancer), et lit leurs resultats pour l'affichage
#   et la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_faim_thermo.gd) : construire_colon/sources_temperature/
#   froid_ressenti/chaud_ressenti/surcout_effort/surcout_thermo/
#   poser_surcout_action/poser_manque_energie/vitesse_effective/
#   changements_etats/cible_aleatoire/seuil_faim/secondes_avant_famine/
#   secondes_avant_epuisement, plus les textes d'affichage et de log.
#
# AUCUN NOM DE PROPRIETE EN DUR : nom_reserve_energie/nom_vitesse/
# nom_manque_energie/nom_froid_ressenti/nom_chaud_ressenti arrivent tous de
# data/banc_faim_thermo.json -- c'est ce qui permet au test de faire traverser
# le meme code par un domaine entierement invente.

const Depense = preload("res://scripts/depense.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Temperature = preload("res://scripts/temperature.gd")
const Velocite = preload("res://scripts/velocite.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

var _config: Dictionary = {}
var _catalogue_etats: Dictionary = {}
var _catalogue_seuils: Dictionary = {}
var _catalogue_temperature: Dictionary = {}

var _colon: Dictionary = {}
var _monde: Array = []
var _sources: Array = []
var _rng := RandomNumberGenerator.new()
var _cible := Vector3.ZERO
var _temps: float = 0.0
var _seuil_faim: float = INF
var _epuisement_trace := false

var _noeud_colon: ColorRect
var _label_colon: Label
var _label_compteur: Label
var _label_detail: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_faim_thermo.json")
	_catalogue_etats = _charger_json("res://data/etats.json")
	_catalogue_seuils = _charger_json("res://data/seuils_etat.json")
	_catalogue_temperature = _charger_json("res://data/temperature.json")

	_seuil_faim = seuil_faim(_catalogue_seuils, _config)

	# Aucun hasard non seede (CLAUDE.md) : la graine vit en donnee, deux
	# lancements donnent exactement le meme trajet.
	_rng.seed = int(_config.graine)

	_colon = construire_colon(_config)
	_monde = [_colon]
	_sources = sources_temperature(_config)
	_cible = cible_aleatoire(_rng, _config)

	_construire_rendu()
	print(ligne_pose(_config, _seuil_faim))
	_rafraichir(0.0, {"effort": 0.0, "thermo": 0.0, "total": 0.0, "froid": 0.0, "chaud": 0.0}, float(_config.temp_cible), 0.0)

func _process(delta: float) -> void:
	_temps += delta

	# 1. Ce qu'il fait AUTOUR du colon -- mecanisme du coeur, appele tel quel.
	var temp_locale: float = Temperature.locale(_colon.position, _sources, _catalogue_temperature)

	# 2. UNE SEULE ecriture de surcout_action (effort + thermique somme), plus
	#    les deux miroirs thermiques. Voir en-tete.
	var decomposition: Dictionary = poser_surcout_action(_colon, temp_locale, _config)

	# 3. La reserve descend -- mecanisme du coeur, appele tel quel.
	Depense.avancer(_monde, delta)

	# 4. Le troisieme miroir, APRES la depense : le seuil de faim doit comparer
	#    la reserve de CE tick, jamais celle du precedent.
	poser_manque_energie(_colon, _config)

	# 5. Les quatre seuils -- mecanisme du coeur, appele tel quel. L'instantane
	#    est pris AVANT pour pouvoir tracer ce qui a change (seuil_etat.gd rend
	#    les ids ayant bascule, jamais QUELS etats).
	var etats_avant: Array = _colon.proprietes.get("etats_actifs", []).duplicate()
	SeuilEtat.avancer(_monde, _catalogue_seuils)
	for ligne in lignes_changement(_temps, changements_etats(etats_avant, _colon.proprietes.get("etats_actifs", []))):
		print(ligne)

	# 6. Vitesse effective (etats composes multiplicativement) puis pas.
	var vitesse: float = vitesse_effective(_colon, _config, _catalogue_etats)
	if vitesse > 0.0:
		if _colon.position.distance_to(_cible) <= float(_config.rayon_arrivee):
			_cible = cible_aleatoire(_rng, _config)
		_colon.position = BancCommun.bouger_vers(_colon.position, _cible, vitesse, delta)
	elif not _epuisement_trace:
		_epuisement_trace = true
		print(ligne_epuisement(_temps))

	# 7. DERNIER appel du tick, contrat de velocite.gd : apres tout ce qui mute
	#    position, jamais avant.
	Velocite.avancer(_monde, delta)

	_rafraichir(delta, decomposition, temp_locale, vitesse)

# ---- Fonctions PURES, testables headless (voir test_banc_faim_thermo.gd) ----

# Le colon ne porte AUCUNE propriete `temperature` (voir en-tete) et aucune
# composition. Un seul canal de reserve : son `cout_base` est le metabolisme de
# base, pose ICI une fois pour toutes et jamais reecrit ; `surcout_action` part
# a 0.0 et n'est ecrit que par poser_surcout_action.
static func construire_colon(config: Dictionary) -> Dictionary:
	var depart: Array = config.position_depart
	var reserves: Dictionary = {}
	reserves[String(config.nom_reserve_energie)] = {
		"reserve": float(config.capacite_energie),
		"cout_base": float(config.metabolisme_base_par_s),
		"surcout_action": 0.0,
	}
	var proprietes: Dictionary = {
		"reserves": reserves,
		"etats_actifs": [],
	}
	proprietes[String(config.nom_vitesse)] = float(config.vitesse_base)
	return {
		"id": "colon",
		"position": Vector3(float(depart[0]), float(depart[1]), float(depart[2])),
		"proprietes": proprietes,
	}

# Traduit les zones du banc dans la forme EXACTE que temperature.gd attend
# ({ position, rayon, temperature, force }) -- la couleur de rendu reste dans
# la zone et n'entre jamais dans le calcul. `sources` est integralement possede
# par l'appelant (contrat de temperature.gd, qui ne fabrique jamais aucune
# source).
static func sources_temperature(config: Dictionary) -> Array:
	var sources: Array = []
	for zone in config.get("zones", []):
		var p: Array = zone.position
		sources.append({
			"position": Vector3(float(p[0]), float(p[1]), float(p[2])),
			"rayon": float(zone.rayon),
			"temperature": float(zone.temperature),
			"force": float(zone.force),
		})
	return sources

# Jamais negatif : au-dessus de la cible de confort, il ne fait pas « moins
# froid que zero », il ne fait plus froid du tout.
static func froid_ressenti(temp_locale: float, temp_cible: float) -> float:
	return max(0.0, temp_cible - temp_locale)

# Symetrique du precedent, mais autour d'un AUTRE nombre (seuil_chaud), et
# jamais le meme abs() partage -- voir en-tete.
static func chaud_ressenti(temp_locale: float, seuil_chaud: float) -> float:
	return max(0.0, temp_locale - seuil_chaud)

# Proportionnel a la velocite REELLE, quel qu'ait ete le mecanisme qui a
# deplace le colon (velocite.gd derive passivement). Velocite absente (tout
# premier tick, jamais encore ecrite) : 0.0, jamais une valeur inventee.
static func surcout_effort(colon: Dictionary, config: Dictionary) -> float:
	var velocite: Vector3 = colon.proprietes.get("velocite", Vector3.ZERO)
	return float(config.coef_effort) * velocite.length()

# Les deux ecarts ne peuvent pas etre non nuls en meme temps (seuil_chaud >=
# temp_cible), mais la somme est ecrite sans cas particulier : additionner deux
# nombres dont l'un est toujours nul reste plus simple, et plus vrai, qu'un
# `if`.
static func surcout_thermo(froid: float, chaud: float, config: Dictionary) -> float:
	return froid * float(config.cout_par_degre_froid) + chaud * float(config.cout_par_degre_chaud)

# UNIQUE ECRIVAIN de canal.surcout_action, et des deux miroirs thermiques --
# voir en-tete, « UNE SEULE ECRITURE ». MUTE le colon en place ; rend la
# DECOMPOSITION ({ effort, thermo, total, froid, chaud }) pour que l'affichage
# la relise sans jamais rien recalculer. Canal absent (config incoherente) :
# push_error, rien n'est ecrit, la decomposition rendue est nulle -- jamais un
# canal invente a la volee.
static func poser_surcout_action(colon: Dictionary, temp_locale: float, config: Dictionary) -> Dictionary:
	var froid: float = froid_ressenti(temp_locale, float(config.temp_cible))
	var chaud: float = chaud_ressenti(temp_locale, float(config.seuil_chaud))
	var effort: float = surcout_effort(colon, config)
	var thermo: float = surcout_thermo(froid, chaud, config)

	var proprietes: Dictionary = colon.proprietes
	proprietes[String(config.nom_froid_ressenti)] = froid
	proprietes[String(config.nom_chaud_ressenti)] = chaud

	var nom_reserve := String(config.nom_reserve_energie)
	var reserves: Dictionary = proprietes.get("reserves", {})
	if not reserves.has(nom_reserve):
		push_error("banc_faim_thermo : canal de reserve '%s' absent du colon, surcout non pose" % nom_reserve)
		return {"effort": effort, "thermo": thermo, "total": 0.0, "froid": froid, "chaud": chaud}
	reserves[nom_reserve]["surcout_action"] = effort + thermo
	return {"effort": effort, "thermo": thermo, "total": effort + thermo, "froid": froid, "chaud": chaud}

# Le troisieme miroir. Ecrit APRES Depense.avancer (voir _process) pour que le
# seuil de faim compare la reserve de ce tick. Borne a 0.0 par le bas : une
# reserve au-dessus de sa capacite (impossible ici, aucun flux ne la recharge)
# ne donnerait pas un « manque negatif ».
static func poser_manque_energie(colon: Dictionary, config: Dictionary) -> float:
	var reserves: Dictionary = colon.proprietes.get("reserves", {})
	var canal: Dictionary = reserves.get(String(config.nom_reserve_energie), {})
	var manque: float = max(0.0, float(config.capacite_energie) - float(canal.get("reserve", 0.0)))
	colon.proprietes[String(config.nom_manque_energie)] = manque
	return manque

# GATE DE CABLAGE (voir en-tete, « L'ARRET FINAL ») : reserve vide -> 0.0,
# sans qu'aucun etat ne soit pose. Sinon la vitesse de base modulee par tous
# les etats actifs (etat_effectif.gd, composition multiplicative).
static func vitesse_effective(colon: Dictionary, config: Dictionary, catalogue_etats: Dictionary) -> float:
	var reserves: Dictionary = colon.proprietes.get("reserves", {})
	var canal: Dictionary = reserves.get(String(config.nom_reserve_energie), {})
	if float(canal.get("reserve", 0.0)) <= 0.0:
		return 0.0
	return EtatEffectif.valeur(colon, String(config.nom_vitesse), catalogue_etats)

# Compare deux instantanes d'etats_actifs. seuil_etat.gd rend les ids ayant
# bascule, jamais QUELS etats -- d'ou cette comparaison, cote cablage.
static func changements_etats(avant: Array, apres: Array) -> Dictionary:
	var gagnes: Array = []
	var perdus: Array = []
	for etat in apres:
		if not avant.has(etat):
			gagnes.append(String(etat))
	for etat in avant:
		if not apres.has(etat):
			perdus.append(String(etat))
	return {"gagnes": gagnes, "perdus": perdus}

# Tire un point dans le terrain. z reste a 0.0 (VERTICALITE : Vector3 partout,
# meme quand la troisieme dimension ne sert pas encore).
static func cible_aleatoire(rng: RandomNumberGenerator, config: Dictionary) -> Vector3:
	return Vector3(
		rng.randf_range(0.0, float(config.terrain_largeur)),
		rng.randf_range(0.0, float(config.terrain_hauteur)),
		0.0,
	)

# Le seuil de faim vit dans le catalogue PARTAGE data/seuils_etat.json, jamais
# recopie en donnee de banc : une seule source de verite, jamais deux nombres a
# garder d'accord. Le banc ne le relit que pour son compteur -- c'est
# seuil_etat.gd, et lui seul, qui pose l'etat. Entree absente : push_error et
# INF (le compteur affichera « jamais » plutot que de mentir).
static func seuil_faim(catalogue_seuils: Dictionary, config: Dictionary) -> float:
	var ref := String(config.ref_seuil_faim)
	if not catalogue_seuils.has(ref) or not catalogue_seuils[ref].has("seuil"):
		push_error("banc_faim_thermo : entree '%s' sans 'seuil' dans data/seuils_etat.json" % ref)
		return INF
	return float(catalogue_seuils[ref].seuil)

# Combien de secondes avant que manque_energie ne franchisse le seuil de faim,
# AU TAUX COURANT (qui change des que le colon accelere ou entre dans une
# zone) -- une projection, jamais une prediction. 0.0 si la famine est deja la,
# INF si rien ne se depense (taux nul : le colon ne s'affamera jamais).
static func secondes_avant_famine(colon: Dictionary, config: Dictionary, seuil: float) -> float:
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	var reserve: float = float(canal.get("reserve", 0.0))
	var restant: float = reserve - (float(config.capacite_energie) - seuil)
	if restant <= 0.0:
		return 0.0
	var taux: float = float(canal.get("cout_base", 0.0)) + float(canal.get("surcout_action", 0.0))
	if taux <= 0.0:
		return INF
	return restant / taux

# Meme projection, jusqu'a la reserve vide (donc jusqu'a l'arret definitif).
static func secondes_avant_epuisement(colon: Dictionary, config: Dictionary) -> float:
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	var reserve: float = float(canal.get("reserve", 0.0))
	if reserve <= 0.0:
		return 0.0
	var taux: float = float(canal.get("cout_base", 0.0)) + float(canal.get("surcout_action", 0.0))
	if taux <= 0.0:
		return INF
	return reserve / taux

static func texte_label_colon(colon: Dictionary, config: Dictionary, decomposition: Dictionary, temp_locale: float, vitesse: float) -> String:
	var proprietes: Dictionary = colon.proprietes
	var canal: Dictionary = proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	var etats: Array = proprietes.get("etats_actifs", [])
	var noms: Array = []
	for etat in etats:
		noms.append(String(etat))
	noms.sort()
	return "energie %.1f / %.1f\nmanque %.1f\nvitesse %.1f (base %.1f)\nsurcout %.3f = effort %.3f + thermo %.3f\nlocale %.1f C -- froid %.1f / chaud %.1f\netat : %s" % [
		float(canal.get("reserve", 0.0)),
		float(config.capacite_energie),
		float(proprietes.get(String(config.nom_manque_energie), 0.0)),
		vitesse,
		float(proprietes.get(String(config.nom_vitesse), 0.0)),
		float(decomposition.get("total", 0.0)),
		float(decomposition.get("effort", 0.0)),
		float(decomposition.get("thermo", 0.0)),
		temp_locale,
		float(proprietes.get(String(config.nom_froid_ressenti), 0.0)),
		float(proprietes.get(String(config.nom_chaud_ressenti), 0.0)),
		" + ".join(noms) if not noms.is_empty() else "-",
	]

static func texte_compteur(colon: Dictionary, config: Dictionary, seuil: float, temps: float) -> String:
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	return "t=%.1f s -- energie restante %.1f -- avant famine %s -- avant arret %s" % [
		temps,
		float(canal.get("reserve", 0.0)),
		texte_duree(secondes_avant_famine(colon, config, seuil)),
		texte_duree(secondes_avant_epuisement(colon, config)),
	]

# INF n'est pas un nombre a afficher : une projection qui n'aboutit jamais se
# dit, elle ne se chiffre pas.
static func texte_duree(secondes: float) -> String:
	if secondes == INF:
		return "jamais (rien ne se depense)"
	return "%.1f s" % secondes

static func lignes_changement(t: float, changements: Dictionary) -> Array:
	var lignes: Array = []
	for etat in changements.get("gagnes", []):
		lignes.append("t=%.1f etat POSE : %s" % [t, String(etat)])
	for etat in changements.get("perdus", []):
		lignes.append("t=%.1f etat RETIRE : %s" % [t, String(etat)])
	return lignes

static func ligne_pose(config: Dictionary, seuil: float) -> String:
	return "t=0.0 colon pose : energie %.1f, metabolisme %.2f/s, confort %.1f C, seuil chaud %.1f C, seuil de faim %.1f (manque_energie)" % [
		float(config.capacite_energie),
		float(config.metabolisme_base_par_s),
		float(config.temp_cible),
		float(config.seuil_chaud),
		seuil,
	]

# Trace de fin, UNE SEULE FOIS : sans elle, un lancement headless se termine
# sur un silence indistinguable d'un banc qui n'a rien fait.
static func ligne_epuisement(t: float) -> String:
	return "t=%.1f energie epuisee -- le colon ne bouge plus" % t

# ---- Rendu (impur, Node) -- aucune decision, seulement des noeuds.

func _draw() -> void:
	# Fond STATIQUE, dessine une seule fois : la zone neutre puis les deux
	# disques, chacun a son rayon REEL de source (jamais un carre decoratif qui
	# mentirait sur l'etendue de la zone).
	var neutre: Array = _config.couleur_zone_neutre
	draw_rect(Rect2(Vector2.ZERO, Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur))),
		Color(float(neutre[0]), float(neutre[1]), float(neutre[2])))
	for zone in _config.get("zones", []):
		var p: Array = zone.position
		var c: Array = zone.couleur
		draw_circle(Vector2(float(p[0]), float(p[1])), float(zone.rayon), Color(float(c[0]), float(c[1]), float(c[2])))

func _construire_rendu() -> void:
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
	_label_compteur = _creer_label(16)
	_label_compteur.position = Vector2(10.0, 10.0)
	couche.add_child(_label_compteur)
	_label_detail = _creer_label(13)
	_label_detail.position = Vector2(10.0, 40.0)
	couche.add_child(_label_detail)

	_poser_camera()

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	# Contour sombre : le meme label doit rester lisible sur le bleu de la zone
	# froide comme sur le rouge de la zone chaude.
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _rafraichir(_delta: float, decomposition: Dictionary, temp_locale: float, vitesse: float) -> void:
	var taille: float = float(_config.taille_colon)
	var centre := Vector2(_colon.position.x, _colon.position.y)
	_noeud_colon.position = centre - _noeud_colon.size / 2.0
	_label_colon.position = centre + Vector2(taille, taille)
	_label_colon.text = texte_label_colon(_colon, _config, decomposition, temp_locale, vitesse)
	_label_compteur.text = texte_compteur(_colon, _config, _seuil_faim, _temps)
	_label_detail.text = "zone froide (bleu) : le surcout thermique monte -- zone chaude (rouge) : idem -- vert : rien que le metabolisme et la marche"

func _poser_camera() -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur)) / 2.0
	camera.zoom = Vector2(0.9, 0.9)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
