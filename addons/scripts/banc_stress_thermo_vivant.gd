extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_stress_thermo_vivant.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). Chantier « stress plante +
# thermoregulation vivant » (audit prealable
# audit_ecosysteme_vivant_prealable.md, lignes 8 et 9, toutes deux au verdict
# CABLABLE -- CONFIRME a l'ecriture : AUCUN mecanisme du coeur touche ni cree).
# Compose CINQ mecanismes deja fermes, TOUS INCHANGES et appeles tels quels :
# scripts/temperature.gd (locale seule), scripts/charge.gd (canal d'humidite),
# scripts/depense.gd (la reserve d'energie descend), scripts/seuil_etat.gd (les
# cinq entrees du catalogue LOCAL), scripts/etat_effectif.gd (croissance
# effective), plus scripts/flux.gd pour que la croissance ait un consommateur
# reel.
#
# CE QU'ON DOIT VOIR : trois plantes et un animal, immobiles, chacun avec SA
# temperature de confort (tropicale 30, temperee 15, arctique 5, animal 37) et
# SES seuils. Deux zones de temperature (disque bleu a gauche, disque rouge a
# droite) et une bande neutre au milieu. Le clic gauche change la TEMPERATURE
# AMBIANTE (tempere -> grand froid -> canicule) ; le clic droit coupe ou remet
# l'arrosage. Au palier tempere les trois plantes sont vertes et poussent. En
# grand froid la TROPICALE meurt (rouge sombre) pendant que l'arctique ne bouge
# pas d'un chiffre. En canicule c'est l'ARCTIQUE qui meurt et la tropicale qui
# va bien. L'animal, lui, ne meurt pas de stress -- il DEPENSE : sa barre
# d'energie descend trois fois plus vite dans le froid qu'au palier tempere.
#
# LE STRESS EST UNE SOMME PONDEREE RECALCULEE A NEUF, JAMAIS UN '+='. Patron
# EXACT de banc_bonheur.gd:calculer_bonheur : `poids_stress` est un Dictionary
# source -> poids porte par CHAQUE plante, et ce fichier boucle dessus sans
# connaitre UN SEUL nom de source. Les quatre sources reelles (froid ressenti,
# chaud ressenti, exces d'eau, secheresse) vivent en donnee ; une cinquieme
# serait une ligne de donnee, zero ligne de code. Une source ABSENTE du
# `poids_stress` d'une plante rend exactement 0.0 (`get(source, 0.0)`), sans
# alarme, par contrat -- l'arctique ne porte AUCUN poids sur le froid, la
# tropicale aucun sur l'exces d'eau, et c'est ce qui les separe.
#
# ET SURTOUT : AUCUN MIROIR. Le bonheur MONTE quand la situation s'ameliore, il
# fallait donc l'inverser (`manque_bonheur`) pour ses deux etats bas. Le stress
# MONTE quand elle empire : la comparaison strictement vers le HAUT de
# seuil_etat.gd (`valeur > seuil`) tombe juste telle quelle, sans une propriete
# de plus. C'est la seule difference de fond avec le patron bonheur, et elle
# simplifie.
#
# JAMAIS UN abs() POUR COMBINER DEUX ECARTS OPPOSES. Quatre bascules, quatre
# nombres differents par vivant : le froid sous `temp_cible`, le chaud au-dessus
# de `seuil_chaud`, la secheresse sous `seuil_sec`, l'exces d'eau au-dessus de
# `seuil_humide` -- avec quatre poids independants. Un abs() unique aurait
# impose une symetrie physiquement fausse (une plante ne souffre pas de la
# secheresse comme elle souffre de la noyade) : decision deja prise et motivee
# pour data/etats.json:hyperthermie, reprise ici a l'identique sur l'eau.
#
# temp_cible ET LES DEUX COUTS PAR DEGRE SONT LUS SUR L'ENTITE, jamais dans une
# config globale de scene -- c'est la question laissee ouverte par l'audit ligne
# 9 (« aujourd'hui non : ce sont des cles du fichier de BANC, globales a la
# scene »), tranchee ici. Precedent exact : `seuil_rupture` pose par colon dans
# banc_grief.gd, `volatilite_magique` dans banc_sorts.gd. Le `cout_par_degre` de
# la consigne est SCINDE EN DEUX (froid/chaud), meme raison que
# temp_cible/seuil_chaud : un cout unique aurait reintroduit la symetrie
# interdite ci-dessus.
#
# LE CATALOGUE DE SEUILS EST LOCAL AU BANC (data/banc_stress_thermo_vivant.json:
# seuils_locaux, format EXACT de data/seuils_etat.json, passe tel quel a
# SeuilEtat.avancer -- patron data/banc_elimination_salete.json:
# seuils_elimination). RAISON, et c'est celle de l'audit ligne 9 : les entrees
# thermiques du catalogue PARTAGE portent un `seuil` UNIVERSEL ; les basculer
# vers `seuil_propriete` pour qu'elles varient par espece toucherait
# banc_faim_thermo.gd, fichier d'un autre chantier. Le catalogue local, lui,
# utilise `seuil_propriete` partout : CHAQUE vivant porte ses cinq seuils en
# cles plates. data/seuils_etat.json n'est NI charge NI passe ici -- ses entrees
# ne sont donc meme pas des chemins morts, elles ne sont jamais evaluees.
#
# LES TROIS ETATS THERMIQUES SONT LES ETATS PARTAGES EXISTANTS
# ('frisson'/'hypothermie'/'hyperthermie', data/etats.json), reposes depuis le
# catalogue LOCAL -- meme partage DELIBERE de nom d'etat que 'sublimation'
# posant le meme 'gaz' que 'point_ebullition', rendu sur par la MEMOIRE PAR
# ENTREE de seuil_etat.gd. Deux etats seulement sont NEUFS ('stress_leger',
# 'mort_stress') : un etat de plus dans un catalogue partage se paie pour tout
# le depot, la consigne n'en demandait pas d'autre.
#
# DEUX ECRIVAINS UNIQUES, ET PAS UN DE PLUS (audit, constat C -- un champ a deux
# ecrivains s'ecrase EN SILENCE, aucun test ne rougit, le nombre est seulement
# faux) :
# - `poser_couts_thermiques` ecrit `froid_ressenti`, `chaud_ressenti`,
#   `surcout_action` ET `cout_base` (ce dernier pour le gate de mort, voir plus
#   bas) ;
# - `poser_stress` ecrit `exces_eau`, `secheresse` et `stress_plante`, tous
#   trois dans le MEME geste depuis les MEMES nombres.
# L'ordre entre les deux n'est pas interchangeable : le stress LIT les deux
# miroirs thermiques que le premier vient d'ecrire.
#
# LA MORT EST DEFINITIVE PAR UN GATE DE CABLAGE, jamais par un mecanisme.
# `stress_plante` est recalcule a neuf, donc REVERSIBLE par construction : sans
# gate, rechauffer l'ambiante ferait redescendre le stress et seuil_etat.gd
# retirerait 'mort_stress' -- une plante morte ressusciterait au clic suivant.
# `poser_stress` CESSE donc de recalculer des que l'etat est actif (la valeur
# reste figee au-dessus du seuil), et `poser_couts_thermiques` met a zero
# cout_base ET surcout_action -- un mort ne depense plus. Meme geste que
# banc_graisse_accoutumance.gd pour 'mort_famine', et que le gate de
# banc_elimination_salete.gd sur un colon mort qui continuait d'eliminer (defaut
# trouve EN LANCANT LA SCENE, invisible au test). CONSEQUENCE ASSUMEE : un tick
# de retard inherent -- le gate lit l'etat pose au tick PRECEDENT, l'ordre
# inverse serait circulaire.
#
# LA CROISSANCE EST LE CONSOMMATEUR REEL DES DEUX ETATS NEUFS. Audit, constat
# (A) : declarer un effet dans data/etats.json ne produit RIEN tant qu'un
# cablage n'appelle pas EtatEffectif.valeur lui-meme -- aucune couche de
# decision ne passe par lui. `croissance_effective` compose la valeur, et
# `avancer_croissance` la passe a flux.gd comme taux d'un emetteur SYNTHETIQUE
# (patron exact banc_croissance.gd:avancer) qui alimente la reserve 'maturite',
# plafonnee a 1.0 PAR CE FICHIER (flux.gd ne borne jamais rien -- « ce fichier
# ne donne rien, il transfere »). Sans cette chaine, le x0.5 de 'stress_leger'
# serait vrai dans le catalogue et sans le moindre effet, EN SILENCE.
#
# L'HUMIDITE PASSE PAR charge.gd, normalisee par clamp(charge/seuil, 0, 1) --
# JAMAIS la charge brute, que charge.gd ne borne pas par le haut (patron
# banc_croissance.gd:charge_humidite_normalisee). La charge est en plus
# PLAFONNEE A SON SEUIL par ce fichier apres chaque appel : sans ce plafond, un
# arrosage prolonge accumulerait sans borne et l'assechement mettrait des
# minutes au lieu de deux secondes. Le canal ne pose AUCUN marqueur ('poser'
# vide) : seule la VALEUR importe, jamais le franchissement.
#
# AUCUNE TEMPERATURE DE CORPS, choix impose par la consigne et repris tel quel :
# temperature.gd:avancer n'est JAMAIS appele, aucun vivant ne porte de propriete
# 'temperature', et les deux miroirs thermiques lisent la temperature LOCALE
# (temperature.gd:locale). Un animal a vraie inertie thermique exigerait
# conductivite_thermique/chaleur_specifique, donc une composition et
# Objet.fabriquer plutot qu'une construction a la main -- autre chantier.
#
# CATALOGUE DE TEMPERATURE CONSTRUIT PAR LE BANC (`catalogue_temperature`), au
# format EXACT de data/temperature.json : temperature.gd recoit TOUJOURS son
# catalogue en parametre et n'en charge jamais aucun. C'est ce qui rend le clic
# gauche possible -- l'ambiante du palier courant y est posee a chaque appel.
# data/temperature.json n'est ni lu ni touche : y recopier une ambiante aurait
# cree deux nombres a garder d'accord alors que ce banc CHANGE le sien.
#
# VIVANTS CONSTRUITS A LA MAIN (pas Objet.fabriquer, meme statut que
# banc_faim_thermo.gd/banc_bonheur.gd/banc_maladie.gd) : ni composition ni
# materiau, donc data/types.json n'est pas touche et rien n'est a enregistrer
# dans scripts/test_lint_donnees.gd.
#
# AUCUNE CATEGORIE DANS CE FICHIER -- il ne connait ni « plante » ni « animal ».
# Ce qui distingue les quatre vivants n'est qu'un jeu de proprietes : qui porte
# un `poids_stress` a un stress, qui porte un canal d'humidite recoit de l'eau,
# qui porte une `croissance` pousse, qui declare une couleur la garde (les
# autres sont teintes par leur stress). L'animal n'est pas un cas particulier
# code : c'est un vivant qui ne porte ni poids de stress, ni seuils de stress,
# ni canal d'humidite, ni croissance.
#
# PAS UN SEUL RNG dans ce fichier : rien n'y est tire au sort, il n'y a donc
# rien a seeder.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les deux JSON et construit vivants et rendu ;
#   _unhandled_input fait tourner les deux toggles ; _process appelle UNIQUEMENT
#   `avancer` (statique) puis lit ce qu'elle rend pour l'affichage et la console
#   -- jamais un calcul refait ici.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_stress_thermo_vivant.gd) : avancer (TOUT le tick, dans son ordre
#   fixe -- le test conduit donc le VRAI tick et non une copie)/
#   construire_vivants/sources_temperature/
#   catalogue_temperature/ambiante/nom_palier/palier_suivant/causes_eau/
#   plafonner_humidite/humidite_normalisee/froid_ressenti/chaud_ressenti/
#   surcout_thermo/est_mort/poser_couts_thermiques/exces_eau/secheresse/
#   calculer_stress/poser_stress/croissance_effective/avancer_croissance/
#   maturite/energie/couleur_vivant/changements_etats, plus les textes.
#
# AUCUN NOM DE PROPRIETE EN DUR, et il a fallu un second passage pour y arriver :
# les `nom_*`/`propriete_*` arrivent tous de data/banc_stress_thermo_vivant.json,
# et `construire_vivants` recopie TOUTE cle de declaration telle quelle plutot
# que d'en enumerer une liste -- un premier jet nommait les cinq seuils
# (`seuil_froid_leger`, `seuil_stress_mortel`...) en dur dans ce fichier, ce que
# le test hors domaine aurait fait rougir. Seules `id` et `position` sont
# structurelles, comme partout dans le depot.

const Temperature = preload("res://scripts/temperature.gd")
const Charge = preload("res://scripts/charge.gd")
const Depense = preload("res://scripts/depense.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Flux = preload("res://scripts/flux.gd")

var _config: Dictionary = {}
var _catalogue_etats: Dictionary = {}

var _vivants: Array = []
var _sources: Array = []
var _palier: int = 0
var _arrosage: bool = true
var _temps: float = 0.0
var _prochaine_trace: float = 0.0
# id -> Dictionary { froid, chaud, thermo, stress, exces, secheresse, locale,
# croissance, maturite } -- l'affichage RELIT ces nombres, il n'en recalcule
# jamais aucun (meme discipline que banc_faim_thermo.gd).
var _diag: Dictionary = {}

var _noeuds: Dictionary = {}          # id -> ColorRect, le carre du vivant
var _barres_energie: Dictionary = {}  # id -> ColorRect
var _barres_maturite: Dictionary = {} # id -> ColorRect (absente si pas de croissance)
var _labels: Dictionary = {}          # id -> Label
var _noeud_eau: ColorRect
var _label_compteur: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_stress_thermo_vivant.json")
	_catalogue_etats = _charger_json("res://data/etats.json")

	_vivants = construire_vivants(_config)
	_sources = sources_temperature(_config)

	_creer_rendu()
	_poser_camera()
	print(ligne_pose(_config, _vivants))
	_diag = avancer(_vivants, _sources, _config, _catalogue_etats, _palier, _arrosage, 0.0)
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_palier = palier_suivant(_palier, _config.get("paliers", []).size())
		print(ligne_palier(_temps, _config, _palier))
		queue_redraw()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_arrosage = not _arrosage
		print(ligne_arrosage(_temps, _arrosage))

func _process(delta: float) -> void:
	_temps += delta
	_diag = avancer(_vivants, _sources, _config, _catalogue_etats, _palier, _arrosage, delta)
	for vivant in _vivants:
		for ligne in lignes_changement(_temps, String(vivant.id), _diag[vivant.id].changements):
			print(ligne)
	if _temps >= _prochaine_trace:
		_prochaine_trace = _temps + float(_config.periode_trace_s)
		for vivant in _vivants:
			print(ligne_etat(_temps, vivant, _config, _diag.get(vivant.id, {})))
	_rafraichir_tout()

# ---- Fonctions PURES, testables headless (voir test_banc_stress_thermo_vivant.gd) ----

# UN PAS complet, et TOUT le pas -- fonction statique pour que le test conduise
# le VRAI tick et non une copie de son ordre (patron banc_grief.gd:avancer,
# banc_croissance.gd:avancer). Le Node ne fait qu'imprimer ce qu'elle rend.
# ORDRE FIXE ET ASSUME, aucun maillon interchangeable :
# 1. l'eau bouge (charge.gd) puis la charge est plafonnee par le cablage ;
# 2. la temperature locale est lue (temperature.gd:locale, catalogue du palier) ;
# 3. les deux miroirs thermiques et les deux couts sont ECRITS, une seule fois ;
# 4. la reserve descend (depense.gd) ;
# 5. le stress est recalcule a neuf -- APRES 3, dont il lit les deux miroirs ;
# 6. les cinq seuils tranchent (seuil_etat.gd, catalogue LOCAL) ;
# 7. la croissance effective (etat_effectif.gd) alimente la maturite (flux.gd).
# Inverser 5 et 6 ferait comparer le stress du tick PRECEDENT ; inverser 6 et 7
# ferait pousser une plante morte pendant un tick de plus. MUTE les vivants en
# place ; rend id -> { locale, froid, chaud, thermo, humidite, exces, secheresse,
# stress, croissance, maturite, energie, changements } -- l'affichage et la
# console RELISENT ces nombres, ils n'en recalculent jamais aucun.
static func avancer(
	vivants: Array,
	sources: Array,
	config: Dictionary,
	catalogue_etats: Dictionary,
	palier: int,
	arrosage: bool,
	delta: float,
) -> Dictionary:
	var catalogue_temp: Dictionary = catalogue_temperature(config, palier)
	Charge.avancer(vivants, causes_eau(config, arrosage), delta)
	for vivant in vivants:
		plafonner_humidite(vivant, config)

	var diag: Dictionary = {}
	var avant: Dictionary = {}
	for vivant in vivants:
		avant[vivant.id] = vivant.proprietes.get("etats_actifs", []).duplicate()
		var locale: float = Temperature.locale(vivant.position, sources, catalogue_temp)
		diag[vivant.id] = poser_couts_thermiques(vivant, locale, config)
		diag[vivant.id]["locale"] = locale

	Depense.avancer(vivants, delta)

	for vivant in vivants:
		var eau: Dictionary = poser_stress(vivant, config)
		for cle in eau:
			diag[vivant.id][cle] = eau[cle]

	SeuilEtat.avancer(vivants, config.seuils_locaux)

	for vivant in vivants:
		var taux: float = croissance_effective(vivant, config, catalogue_etats)
		diag[vivant.id]["croissance"] = taux
		diag[vivant.id]["maturite"] = avancer_croissance(vivant, taux, delta, config)
		diag[vivant.id]["energie"] = energie(vivant, config)
		diag[vivant.id]["changements"] = changements_etats(
			avant[vivant.id], vivant.proprietes.get("etats_actifs", []))
	return diag

# Les vivants, CONSTRUITS A LA MAIN (voir en-tete). Chaque declaration est
# recopiee TELLE QUELLE en proprietes plates -- c'est ce qui met `temp_cible`,
# les deux couts par degre et les cinq seuils SUR L'ENTITE et non dans une
# config globale (audit ligne 9). Les Dictionary sont DUPLIQUES (`duplicate(true)`,
# meme precaution d'aliasing que banc_commun.gd:resoudre_chantier) : sans elle,
# deux vivants partageraient le meme canal d'humidite et charge.gd le muterait
# deux fois par tick.
static func construire_vivants(config: Dictionary) -> Array:
	var vivants: Array = []
	for decl in config.get("vivants", []):
		var pos: Array = decl.position
		var proprietes: Dictionary = {"etats_actifs": []}

		# TOUTE cle de declaration devient une propriete PLATE, telle quelle et
		# sous SON PROPRE nom -- ce fichier n'en connait aucun. Seules `id` et
		# `position` sont structurelles (elles montent d'un cran, dans la chose
		# elle-meme, comme partout dans le depot). C'est ce qui met `temp_cible`,
		# les deux couts par degre et les cinq seuils SUR L'ENTITE et non dans une
		# config globale (audit ligne 9), et c'est aussi ce qui permet a un
		# domaine entierement invente de traverser ce meme code.
		for cle in decl:
			if String(cle) == "id" or String(cle) == "position":
				continue
			var valeur = decl[cle]
			if valeur is Dictionary or valeur is Array:
				valeur = valeur.duplicate(true)
			proprietes[String(cle)] = valeur

		var reserves: Dictionary = {}
		reserves[String(config.nom_reserve_energie)] = {
			"reserve": float(proprietes.get(String(config.nom_capacite_energie), 0.0)),
			"cout_base": float(proprietes.get(String(config.nom_cout_base), 0.0)),
			"surcout_action": 0.0,
		}
		if proprietes.has(String(config.nom_croissance)):
			reserves[String(config.nom_reserve_maturite)] = {"reserve": 0.0}
			proprietes[String(config.propriete_receptrice_croissance)] = true
		proprietes["reserves"] = reserves

		if proprietes.get(String(config.nom_recoit_eau), false):
			proprietes["etats"] = {
				String(config.nom_canal_humidite): config.canal_humidite_defaut.duplicate(true),
			}

		vivants.append({
			"id": String(decl.id),
			"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			"proprietes": proprietes,
		})
	return vivants

# Traduit les zones du banc dans la forme EXACTE que temperature.gd attend
# ({ position, rayon, temperature, force }) -- la couleur de rendu reste dans la
# zone et n'entre jamais dans le calcul. `sources` est integralement possede par
# l'appelant (contrat de temperature.gd, qui ne fabrique jamais aucune source).
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

# Le catalogue que temperature.gd attend, AU FORMAT EXACT de
# data/temperature.json, construit a chaque appel avec l'ambiante du palier
# courant -- c'est ce qui rend le clic gauche possible (voir en-tete).
static func catalogue_temperature(config: Dictionary, palier: int) -> Dictionary:
	return {
		"defaut": {
			"ambiante": ambiante(config, palier),
			"attenuation": {"exposant": float(config.get("temperature", {}).get("exposant", 1.0))},
		},
	}

# Palier hors bornes (donnee incoherente) : push_error et repli sur le PREMIER
# palier, jamais une ambiante inventee.
static func ambiante(config: Dictionary, palier: int) -> float:
	var paliers: Array = config.get("paliers", [])
	if paliers.is_empty():
		push_error("banc_stress_thermo_vivant : aucun palier de temperature en donnee")
		return 0.0
	if palier < 0 or palier >= paliers.size():
		push_error("banc_stress_thermo_vivant : palier %d hors bornes, repli sur le premier" % palier)
		return float(paliers[0].ambiante)
	return float(paliers[palier].ambiante)

static func nom_palier(config: Dictionary, palier: int) -> String:
	var paliers: Array = config.get("paliers", [])
	if palier < 0 or palier >= paliers.size():
		return ""
	return String(paliers[palier].nom)

# Toggle CYCLIQUE sur les paliers declares. PURE, meme forme exacte que
# banc_bonheur.gd:source_suivante.
static func palier_suivant(palier: int, nb_paliers: int) -> int:
	if nb_paliers <= 0:
		return 0
	return (palier + 1) % nb_paliers

# La cause que charge.gd attend. Arrosage coupe : AUCUNE cause -- charge.gd
# n'applique sa decroissance QUE quand la somme a portee est nulle, une cause de
# poids 0.0 laisserait donc la charge PLATE au lieu de la faire descendre.
static func causes_eau(config: Dictionary, arrosage: bool) -> Array:
	if not arrosage:
		return []
	var decl: Dictionary = config.get("source_eau", {})
	var p: Array = decl.get("position", [0.0, 0.0, 0.0])
	return [{
		"position": Vector3(float(p[0]), float(p[1]), float(p[2])),
		"poids": float(decl.get("poids", 1.0)),
	}]

# PLAFOND AU CABLAGE : charge.gd ne borne une charge qu'a 0.0 par le BAS, jamais
# par le haut (voir son en-tete). Sans ce plafond, un arrosage prolonge
# accumulerait sans borne et l'assechement mettrait des minutes. MUTE le canal en
# place ; un vivant sans canal d'humidite n'est pas touche (chemin mort legitime).
static func plafonner_humidite(vivant: Dictionary, config: Dictionary) -> void:
	var canal: Dictionary = vivant.proprietes.get("etats", {}).get(String(config.nom_canal_humidite), {})
	if canal.is_empty():
		return
	var seuil: float = float(canal.get("seuil", 0.0))
	if seuil > 0.0 and float(canal.get("charge", 0.0)) > seuil:
		canal["charge"] = seuil

# clamp(charge/seuil, 0.0, 1.0) -- JAMAIS la charge brute (patron
# banc_croissance.gd:charge_humidite_normalisee). Vivant sans canal : 0.0, ce qui
# le laisse en secheresse maximale s'il porte un poids dessus -- il n'en porte
# aucun dans ce banc, l'animal n'ayant pas de `poids_stress` du tout.
static func humidite_normalisee(vivant: Dictionary, config: Dictionary) -> float:
	var canal: Dictionary = vivant.proprietes.get("etats", {}).get(String(config.nom_canal_humidite), {})
	if canal.is_empty():
		return 0.0
	var seuil: float = float(canal.get("seuil", 0.0))
	var charge: float = float(canal.get("charge", 0.0))
	if seuil <= 0.0:
		return 1.0 if charge > 0.0 else 0.0
	return clamp(charge / seuil, 0.0, 1.0)

# Jamais negatif : au-dessus de la cible de confort, il ne fait pas « moins froid
# que zero », il ne fait plus froid du tout.
static func froid_ressenti(temp_locale: float, temp_cible: float) -> float:
	return max(0.0, temp_cible - temp_locale)

# Symetrique du precedent, mais autour d'un AUTRE nombre (seuil_chaud), et jamais
# le meme abs() partage -- voir en-tete.
static func chaud_ressenti(temp_locale: float, seuil_chaud: float) -> float:
	return max(0.0, temp_locale - seuil_chaud)

# Les deux ecarts ne peuvent pas etre non nuls en meme temps (seuil_chaud >=
# temp_cible), mais la somme est ecrite sans cas particulier : additionner deux
# nombres dont l'un est toujours nul reste plus simple, et plus vrai, qu'un `if`.
# LES DEUX COUTS SONT LUS SUR LE VIVANT, jamais dans la config.
static func surcout_thermo(vivant: Dictionary, froid: float, chaud: float, config: Dictionary) -> float:
	var proprietes: Dictionary = vivant.proprietes
	return froid * float(proprietes.get(String(config.nom_cout_par_degre_froid), 0.0)) \
		+ chaud * float(proprietes.get(String(config.nom_cout_par_degre_chaud), 0.0))

# LE GATE DE MORT, lu par les deux ecrivains uniques. Lit l'etat pose au tick
# PRECEDENT (un tick de retard inherent, voir en-tete).
static func est_mort(vivant: Dictionary, config: Dictionary) -> bool:
	return vivant.proprietes.get("etats_actifs", []).has(String(config.etat_mort_stress))

# UNIQUE ECRIVAIN de `froid_ressenti`, `chaud_ressenti`, `surcout_action` ET
# `cout_base` -- voir en-tete, « DEUX ECRIVAINS UNIQUES ». MUTE le vivant en
# place ; rend la DECOMPOSITION ({ froid, chaud, thermo }) pour que l'affichage
# la relise sans jamais rien recalculer.
# GATE DE MORT : un vivant mort garde ses deux miroirs a jour (le label ne doit
# pas mentir sur ce qu'il fait autour de lui) mais ne depense plus RIEN --
# cout_base et surcout_action tombent tous deux a 0.0. Canal de reserve absent
# (config incoherente) : push_error, rien n'est ecrit sur la reserve, la
# decomposition rendue reste juste.
static func poser_couts_thermiques(vivant: Dictionary, temp_locale: float, config: Dictionary) -> Dictionary:
	var proprietes: Dictionary = vivant.proprietes
	var froid: float = froid_ressenti(temp_locale, float(proprietes.get(String(config.nom_temp_cible), temp_locale)))
	var chaud: float = chaud_ressenti(temp_locale, float(proprietes.get(String(config.nom_seuil_chaud), temp_locale)))
	proprietes[String(config.nom_froid_ressenti)] = froid
	proprietes[String(config.nom_chaud_ressenti)] = chaud

	var thermo: float = surcout_thermo(vivant, froid, chaud, config)
	var mort: bool = est_mort(vivant, config)

	var nom_reserve := String(config.nom_reserve_energie)
	var reserves: Dictionary = proprietes.get("reserves", {})
	if not reserves.has(nom_reserve):
		push_error("banc_stress_thermo_vivant : canal de reserve '%s' absent de '%s', couts non poses"
			% [nom_reserve, String(vivant.get("id", "?"))])
		return {"froid": froid, "chaud": chaud, "thermo": thermo}
	reserves[nom_reserve]["surcout_action"] = 0.0 if mort else thermo
	reserves[nom_reserve]["cout_base"] = 0.0 if mort else float(proprietes.get(String(config.nom_cout_base), 0.0))
	return {"froid": froid, "chaud": chaud, "thermo": 0.0 if mort else thermo}

# L'eau EN TROP, au-dessus du confort haut de CETTE plante. Jamais un abs()
# partage avec la secheresse : deux bascules, deux nombres, deux poids.
static func exces_eau(humidite: float, seuil_humide: float) -> float:
	return max(0.0, humidite - seuil_humide)

# L'eau QUI MANQUE, sous le confort bas de CETTE plante.
static func secheresse(humidite: float, seuil_sec: float) -> float:
	return max(0.0, seuil_sec - humidite)

# LA SOMME PONDEREE. Lecture PURE : n'ecrit rien, ne mute rien -- `poser_stress`
# est le seul ecrivain. Boucle sur les poids DE LA PLANTE, jamais sur une liste
# de sources connue de ce fichier : un poids sur une source que le monde n'offre
# pas rend exactement 0.0 (`get(source, 0.0)`), sans alarme, par contrat. Un
# vivant sans `poids_stress` rend exactement 0.0 -- c'est tout ce qui distingue
# l'animal des trois plantes, aucune categorie n'est codee.
static func calculer_stress(vivant: Dictionary, config: Dictionary) -> float:
	var proprietes: Dictionary = vivant.proprietes
	var poids: Dictionary = proprietes.get(String(config.nom_poids_stress), {})
	var stress := 0.0
	for source in poids:
		stress += float(poids[source]) * float(proprietes.get(String(source), 0.0))
	return stress

# UNIQUE ECRIVAIN de `exces_eau`, `secheresse` et `stress_plante` -- les trois
# dans le MEME geste, depuis les MEMES nombres (voir en-tete). RECALCULE A NEUF,
# jamais un '+=' : c'est ce recalcul, et lui seul, qui empeche un champ derive de
# deriver (resultat negatif deja mesure deux fois sur expression.gd).
# UN VIVANT SANS `poids_stress` N'EST PAS TOUCHE DU TOUT -- aucune des trois
# proprietes ne lui est ecrite, les deux entrees de stress du catalogue local
# sont pour lui des chemins morts silencieux, jamais une alarme.
# GATE DE MORT : un vivant deja mort garde ses trois valeurs FIGEES (voir
# en-tete, « LA MORT EST DEFINITIVE PAR UN GATE DE CABLAGE »).
# MUTE le vivant en place ; rend { humidite, exces, secheresse, stress } pour que
# l'affichage relise sans jamais rien recalculer.
static func poser_stress(vivant: Dictionary, config: Dictionary) -> Dictionary:
	var proprietes: Dictionary = vivant.proprietes
	if not proprietes.has(String(config.nom_poids_stress)):
		return {}
	var humidite: float = humidite_normalisee(vivant, config)
	if est_mort(vivant, config):
		return {
			"humidite": humidite,
			"exces": float(proprietes.get(String(config.nom_exces_eau), 0.0)),
			"secheresse": float(proprietes.get(String(config.nom_secheresse), 0.0)),
			"stress": float(proprietes.get(String(config.nom_stress), 0.0)),
		}
	var exces: float = exces_eau(humidite, float(proprietes.get(String(config.nom_seuil_humide), 1.0)))
	var sec: float = secheresse(humidite, float(proprietes.get(String(config.nom_seuil_sec), 0.0)))
	proprietes[String(config.nom_exces_eau)] = exces
	proprietes[String(config.nom_secheresse)] = sec
	var stress: float = calculer_stress(vivant, config)
	proprietes[String(config.nom_stress)] = stress
	return {"humidite": humidite, "exces": exces, "secheresse": sec, "stress": stress}

# La croissance de base modulee par TOUS les etats actifs -- etat_effectif.gd,
# composition multiplicative, jamais reimplementee ici. C'EST LA SEULE LECTURE
# QUI DONNE UN EFFET AUX DEUX ETATS NEUFS (audit, constat A) : sans elle, le
# x0.5 de 'stress_leger' et l'ecrasement de 'mort_stress' seraient vrais dans le
# catalogue et sans le moindre effet, en silence.
static func croissance_effective(vivant: Dictionary, config: Dictionary, catalogue_etats: Dictionary) -> float:
	if not vivant.proprietes.has(String(config.nom_croissance)):
		return 0.0
	return EtatEffectif.valeur(vivant, String(config.nom_croissance), catalogue_etats)

# Le taux compose devient le `taux_flux` d'un emetteur SYNTHETIQUE, ce tick, pour
# CE vivant -- flux.gd ne connait qu'UN taux par source, jamais un coefficient
# par receveur (patron exact banc_croissance.gd:avancer). Le plafond de la
# reserve vit ICI : flux.gd ne borne jamais rien (« ce fichier ne donne rien, il
# transfere »). Rend la maturite atteinte.
static func avancer_croissance(vivant: Dictionary, taux: float, delta: float, config: Dictionary) -> float:
	var nom_maturite := String(config.nom_reserve_maturite)
	var reserves: Dictionary = vivant.proprietes.get("reserves", {})
	if not reserves.has(nom_maturite):
		return 0.0
	var emetteur := {
		"id": "%s_emetteur_croissance" % String(vivant.id),
		"position": vivant.position,
		"proprietes": {
			String(config.propriete_source_croissance): true,
			"taux_flux": taux,
			"portee_flux": float(config.portee_flux_croissance),
		},
	}
	Flux.avancer([emetteur, vivant], [{
		"source": String(config.propriete_source_croissance),
		"receptrice": String(config.propriete_receptrice_croissance),
		"cible": nom_maturite,
	}], delta)
	var canal: Dictionary = reserves[nom_maturite]
	canal["reserve"] = min(float(config.maturite_max), float(canal.get("reserve", 0.0)))
	return float(canal["reserve"])

static func maturite(vivant: Dictionary, config: Dictionary) -> float:
	return float(vivant.proprietes.get("reserves", {}).get(String(config.nom_reserve_maturite), {}).get("reserve", 0.0))

static func energie(vivant: Dictionary, config: Dictionary) -> float:
	return float(vivant.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {}).get("reserve", 0.0))

static func capacite_energie(vivant: Dictionary, config: Dictionary) -> float:
	return float(vivant.proprietes.get(String(config.nom_capacite_energie), 0.0))

# Compare deux instantanes d'etats_actifs -- seuil_etat.gd rend les ids ayant
# bascule, jamais QUELS etats, d'ou cette comparaison cote cablage. PURE.
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

# LA COULEUR, PURE et sans une seule categorie : un vivant qui declare sa propre
# couleur la garde (c'est le cas de l'animal, qui n'a pas de stress a montrer) ;
# les autres sont teintes par le rapport de leur stress a LEUR seuil mortel --
# vert, puis jaune a mi-chemin, puis rouge au seuil. Un mort prend la couleur de
# mort, sans quoi « stress maximal » et « morte » seraient indistinguables.
# Rend un Array [r, g, b], jamais un Color : cette fonction doit rester testable
# headless comme les autres.
static func couleur_vivant(vivant: Dictionary, config: Dictionary) -> Array:
	if est_mort(vivant, config):
		return config.couleur_mort
	var proprietes: Dictionary = vivant.proprietes
	if proprietes.has(String(config.nom_couleur)):
		return proprietes[String(config.nom_couleur)]
	var mortel: float = float(proprietes.get(String(config.nom_seuil_stress_mortel), 0.0))
	if mortel <= 0.0:
		return config.couleur_stress_bas
	var ratio: float = clamp(float(proprietes.get(String(config.nom_stress), 0.0)) / mortel, 0.0, 1.0)
	if ratio <= 0.5:
		return _melange(config.couleur_stress_bas, config.couleur_stress_moyen, ratio * 2.0)
	return _melange(config.couleur_stress_moyen, config.couleur_stress_haut, (ratio - 0.5) * 2.0)

static func _melange(a: Array, b: Array, t: float) -> Array:
	var melange: Array = []
	for i in range(3):
		melange.append(float(a[i]) + (float(b[i]) - float(a[i])) * clamp(t, 0.0, 1.0))
	return melange

# ---- Textes (purs eux aussi -- aucun nombre n'y est recalcule) ----

static func texte_etats(vivant: Dictionary) -> String:
	var noms: Array = []
	for etat in vivant.proprietes.get("etats_actifs", []):
		noms.append(String(etat))
	noms.sort()
	return " + ".join(noms) if not noms.is_empty() else "-"

# Un vivant sans `poids_stress` affiche "-" et JAMAIS "0.000" : les deux valent
# zero dans les faits, mais « je n'ai pas de stress » et « mon stress vaut zero »
# ne se disent pas pareil -- meme distinction que banc_bonheur.gd:texte_poids_source.
static func texte_stress(vivant: Dictionary, config: Dictionary) -> String:
	if not vivant.proprietes.has(String(config.nom_poids_stress)):
		return "-"
	return "%.3f / %.2f" % [
		float(vivant.proprietes.get(String(config.nom_stress), 0.0)),
		float(vivant.proprietes.get(String(config.nom_seuil_stress_mortel), 0.0)),
	]

static func texte_label(vivant: Dictionary, config: Dictionary, diag: Dictionary) -> String:
	var proprietes: Dictionary = vivant.proprietes
	return "%s\nstress %s\ncible %.0f C -- locale %.1f C\nfroid %.1f / chaud %.1f -- surcout %.3f\nenergie %.1f / %.0f\netat : %s" % [
		String(vivant.id),
		texte_stress(vivant, config),
		float(proprietes.get(String(config.nom_temp_cible), 0.0)),
		float(diag.get("locale", 0.0)),
		float(proprietes.get(String(config.nom_froid_ressenti), 0.0)),
		float(proprietes.get(String(config.nom_chaud_ressenti), 0.0)),
		float(diag.get("thermo", 0.0)),
		energie(vivant, config),
		capacite_energie(vivant, config),
		texte_etats(vivant),
	]

static func texte_compteur(vivants: Array, config: Dictionary, palier: int, arrosage: bool, temps: float) -> String:
	var morts := 0
	var stresses := 0
	for vivant in vivants:
		if est_mort(vivant, config):
			morts += 1
		elif vivant.proprietes.get("etats_actifs", []).has(String(config.etat_stress_leger)):
			stresses += 1
	return "t=%.1f s -- ambiante %s (%.0f C) -- arrosage %s -- %s %d | %s %d | vivants %d" % [
		temps,
		nom_palier(config, palier),
		ambiante(config, palier),
		"actif" if arrosage else "coupe",
		String(config.etat_stress_leger), stresses,
		String(config.etat_mort_stress), morts,
		vivants.size() - morts,
	]

static func texte_aide(config: Dictionary) -> String:
	var noms: Array = []
	for p in config.get("paliers", []):
		noms.append("%s %.0f C" % [String(p.nom), float(p.ambiante)])
	return "clic gauche : ambiante (%s) -- clic droit : arrosage\nchaque vivant porte SA temperature de confort et SES seuils ; le stress est une somme ponderee recalculee a neuf, jamais accumulee" % " -> ".join(noms)

static func lignes_changement(t: float, id: String, changements: Dictionary) -> Array:
	var lignes: Array = []
	for etat in changements.get("gagnes", []):
		lignes.append("t=%.1f %s etat POSE : %s" % [t, id, String(etat)])
	for etat in changements.get("perdus", []):
		lignes.append("t=%.1f %s etat RETIRE : %s" % [t, id, String(etat)])
	return lignes

static func ligne_pose(config: Dictionary, vivants: Array) -> String:
	var morceaux: Array = []
	for vivant in vivants:
		morceaux.append("%s (cible %.0f C, chaud %.0f C)" % [
			String(vivant.id),
			float(vivant.proprietes.get(String(config.nom_temp_cible), 0.0)),
			float(vivant.proprietes.get(String(config.nom_seuil_chaud), 0.0)),
		])
	return "t=0.0 %d vivants poses, chacun avec SA cible thermique -- %s\nambiante de depart %s (%.0f C), arrosage actif" % [
		vivants.size(),
		" | ".join(morceaux),
		nom_palier(config, 0),
		ambiante(config, 0),
	]

static func ligne_palier(t: float, config: Dictionary, palier: int) -> String:
	return "t=%.1f AMBIANTE : %s (%.0f C)" % [t, nom_palier(config, palier), ambiante(config, palier)]

static func ligne_arrosage(t: float, arrosage: bool) -> String:
	return "t=%.1f ARROSAGE : %s" % [t, "actif" if arrosage else "coupe"]

# DEFAUT TROUVE EN LANCANT LA SCENE, invisible au test : la trace affichait
# « eau=0.00 exces=0.00 sec=0.00 » pour l'animal, qui ne porte AUCUN canal
# d'humidite -- l'ecran disait « il est a sec » la ou il fallait lire « la
# question ne se pose pas pour lui ». Meme distinction que texte_stress : un
# vivant hors de ce circuit affiche des tirets, jamais des zeros.
static func texte_eau(vivant: Dictionary, config: Dictionary, diag: Dictionary) -> String:
	if not vivant.proprietes.has("etats"):
		return "eau=- exces=- sec=-"
	return "eau=%.2f exces=%.2f sec=%.2f" % [
		float(diag.get("humidite", 0.0)),
		float(diag.get("exces", 0.0)),
		float(diag.get("secheresse", 0.0)),
	]

# Meme geste sur la croissance et la maturite : un vivant qui ne pousse pas
# n'affiche pas « croissance=0.000 », il n'en a pas.
static func texte_pousse(vivant: Dictionary, config: Dictionary, diag: Dictionary) -> String:
	if not vivant.proprietes.has(String(config.nom_croissance)):
		return "croissance=- maturite=-"
	return "croissance=%.3f maturite=%.2f" % [float(diag.get("croissance", 0.0)), maturite(vivant, config)]

static func ligne_etat(t: float, vivant: Dictionary, config: Dictionary, diag: Dictionary) -> String:
	var proprietes: Dictionary = vivant.proprietes
	return "t=%.1f %s | locale=%.1f froid=%.1f chaud=%.1f | %s | stress=%s | energie=%.1f %s | %s" % [
		t,
		String(vivant.id),
		float(diag.get("locale", 0.0)),
		float(proprietes.get(String(config.nom_froid_ressenti), 0.0)),
		float(proprietes.get(String(config.nom_chaud_ressenti), 0.0)),
		texte_eau(vivant, config, diag),
		texte_stress(vivant, config),
		energie(vivant, config),
		texte_pousse(vivant, config, diag),
		texte_etats(vivant),
	]

# ---- Rendu (impur, Node) -- aucune decision, seulement des noeuds, des
# couleurs et des longueurs de barre.

func _couleur(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))

func _draw() -> void:
	# Le fond porte la couleur du PALIER courant : sans elle, changer l'ambiante
	# ne se verrait qu'au fil des labels. Les deux disques sont dessines a leur
	# rayon REEL de source, jamais un carre decoratif qui mentirait sur l'etendue.
	var paliers: Array = _config.get("paliers", [])
	var fond: Array = paliers[_palier].couleur_fond if _palier < paliers.size() else [0.1, 0.1, 0.1]
	draw_rect(Rect2(Vector2.ZERO, Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur))),
		_couleur(fond))
	for zone in _config.get("zones", []):
		var p: Array = zone.position
		draw_circle(Vector2(float(p[0]), float(p[1])), float(zone.rayon), _couleur(zone.couleur))

func _creer_rendu() -> void:
	var taille: float = float(_config.taille_vivant)
	var largeur: float = float(_config.largeur_barre)
	var hauteur: float = float(_config.hauteur_barre)
	var espacement: float = float(_config.espacement_barre)
	var marge: float = float(_config.marge_bloc)

	for vivant in _vivants:
		var centre := Vector2(vivant.position.x, vivant.position.y)
		var x_barre: float = centre.x - largeur / 2.0

		var carre := ColorRect.new()
		carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
		carre.size = Vector2(taille, taille)
		carre.position = centre - carre.size / 2.0
		add_child(carre)
		_noeuds[vivant.id] = carre

		# Les barres, SOUS le carre, chacune sur sa ligne : energie pour tous,
		# maturite pour les seuls vivants qui poussent.
		var y: float = centre.y + taille / 2.0 + marge
		_creer_barre(_couleur(_config.couleur_fond_barre), Vector2(x_barre, y), largeur, hauteur)
		_barres_energie[vivant.id] = _creer_barre(_couleur(_config.couleur_barre_energie),
			Vector2(x_barre, y), largeur, hauteur)
		y += espacement
		if vivant.proprietes.has(String(_config.nom_croissance)):
			_creer_barre(_couleur(_config.couleur_fond_barre), Vector2(x_barre, y), largeur, hauteur)
			_barres_maturite[vivant.id] = _creer_barre(_couleur(_config.couleur_barre_maturite),
				Vector2(x_barre, y), 0.0, hauteur)
			y += espacement

		var label := _creer_label(int(_config.taille_police_label), Vector2(x_barre, y + marge))
		add_child(label)
		_labels[vivant.id] = label

	var decl_eau: Dictionary = _config.get("source_eau", {})
	var pos_eau: Array = decl_eau.get("position", [0.0, 0.0, 0.0])
	var taille_eau: float = float(_config.taille_source_eau)
	_noeud_eau = ColorRect.new()
	_noeud_eau.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_eau.size = Vector2(taille_eau, taille_eau)
	_noeud_eau.position = Vector2(float(pos_eau[0]), float(pos_eau[1])) - _noeud_eau.size / 2.0
	add_child(_noeud_eau)

	var couche := CanvasLayer.new()
	add_child(couche)
	_label_compteur = _creer_label(int(_config.taille_police_compteur), Vector2(10.0, 10.0))
	couche.add_child(_label_compteur)
	_label_aide = _creer_label(int(_config.taille_police_aide), Vector2(10.0, 40.0))
	couche.add_child(_label_aide)
	_label_aide.text = texte_aide(_config)

func _creer_label(taille_police: int, origine: Vector2) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille_police)
	# Contour sombre : le meme label doit rester lisible sur le bleu de la zone
	# froide comme sur le rouge de la zone chaude.
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	label.position = origine
	return label

func _creer_barre(couleur: Color, origine: Vector2, largeur: float, hauteur: float) -> ColorRect:
	var barre := ColorRect.new()
	barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barre.color = couleur
	barre.position = origine
	barre.size = Vector2(largeur, hauteur)
	add_child(barre)
	return barre

func _rafraichir_tout() -> void:
	var largeur: float = float(_config.largeur_barre)
	var hauteur: float = float(_config.hauteur_barre)
	for vivant in _vivants:
		var diag: Dictionary = _diag.get(vivant.id, {})
		_noeuds[vivant.id].color = _couleur(couleur_vivant(vivant, _config))
		_labels[vivant.id].text = texte_label(vivant, _config, diag)
		var capacite: float = capacite_energie(vivant, _config)
		var ratio: float = clamp(energie(vivant, _config) / capacite, 0.0, 1.0) if capacite > 0.0 else 0.0
		_barres_energie[vivant.id].size = Vector2(largeur * ratio, hauteur)
		if _barres_maturite.has(vivant.id):
			_barres_maturite[vivant.id].size = Vector2(
				largeur * clamp(maturite(vivant, _config) / float(_config.maturite_max), 0.0, 1.0), hauteur)
	_noeud_eau.color = _couleur(_config.couleur_source_eau_active if _arrosage
		else _config.couleur_source_eau_coupee)
	_label_compteur.text = texte_compteur(_vivants, _config, _palier, _arrosage, _temps)

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
