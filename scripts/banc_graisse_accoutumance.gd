extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_graisse_accoutumance.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). Chantier « graisse +
# accoutumance » (audit prealable audit_mecaniques_corps_prealable.md, lignes 10
# et 12, les DEUX seules du tableau au verdict PARTIELLEMENT COUVERT --
# confirme a l'ecriture : AUCUN mecanisme du coeur touche ni cree).
#
# CE QU'ON DOIT VOIR : un colon immobile, plante dans une zone froide, avec un
# tas de nourriture a cote. Trois phases s'enchainent sans qu'aucune ne soit
# codee comme une phase -- elles emergent des nombres.
#   1. Il mange plus qu'il ne brule. Son energie remonte au-dessus du seuil de
#      surplus, et le SURPLUS SEUL part en graisse : la barre jaune se remplit
#      pendant que la barre verte reste plaquee juste au-dessus du seuil.
#   2. Clic gauche : la nourriture disparait. L'energie ne fait plus que
#      descendre (metabolisme de base + lutte contre le froid). Elle touche
#      zero, 'affame' puis 'famine' se posent.
#   3. En famine, le transfert S'INVERSE : la graisse redescend et alimente
#      l'energie exactement au rythme ou elle est brulee. Quand la graisse
#      touche zero a son tour, 'mort_famine' se pose et ecrase la vitesse a 0.
# En parallele, du premier tick au dernier, l'exposition au froid depose une
# marque epigenetique qui REDUIT le surcout thermique : le colon s'endurcit, sa
# combustion ralentit, et la phase 3 dure plus longtemps qu'elle ne l'aurait
# fait sans elle. Clic droit : la source de froid s'eteint et la marque se met a
# decroitre (voir ECARTS A LA CONSIGNE plus bas).
#
# LE GESTE QUE CE BANC EXISTE POUR PROUVER -- consommer.gd:transferer AVEC LA
# MEME ENTITE COMME SOURCE ET COMME RECEVEUR. Deux reserves d'un meme colon,
# jamais deux objets distincts : Consommer.transferer(colon, colon, "energie",
# "graisse", ...) puis, en famine, la meme paire dans l'autre sens. AUCUN
# appelant du depot ne le faisait avant ce chantier (tous les appels existants
# ont deux objets distincts) -- c'est le maillon SANS PRECEDENT identifie par
# l'audit §10, et la raison pour laquelle il n'etait que « partiellement
# couvert ». Il fonctionne parce que reserves_source et _crediter operent sur le
# meme proprietes.reserves mais sur des CLES DIFFERENTES : aucun aliasing.
#
# AUCUN PRE-BORNAGE DANS LE SENS FAMINE, ET C'EST VOULU. Trois appelants
# (ecoulement.gd, banc_fertilite.gd, banc_erosion.gd) ont du pre-borner leur
# quantite pour se proteger d'un defaut de consommer.gd (il creditait au
# receveur la quantite DEMANDEE, pas celle reellement retiree une fois bornee a
# 0.0). Ce defaut est FERME depuis le chantier de correction de consommer.gd :
# le credit vaut desormais reserve_avant - reserve_apres. Le transfert
# graisse -> energie de ce banc demande donc son taux nu et laisse consommer.gd
# borner : demander plus de graisse qu'il n'en reste ne cree aucune energie.
# C'est la CONTRE-EPREUVE de la correction, verrouillee par test.
# Le sens inverse (energie -> graisse) EST borne par ce cablage, mais pour une
# raison qui n'a rien a voir : le SURPLUS REEL (reserve - seuil_surplus) et la
# PLACE RESTANTE (capacite_graisse - graisse) sont des regles de domaine, pas
# une protection contre un bug -- rien dans le coeur ne borne le HAUT d'une
# reserve (finding de banc_fertilite.gd, toujours vrai).
#
# EXPRESSION.GD RESTE DORMANT, DIT PLUTOT QUE MASQUE. La marque
# 'accoutumance_froid' est posee et decrue par epigenetique.gd (mecanisme du
# coeur, appele tel quel), mais expression.gd:exprimer/appliquer n'est JAMAIS
# appele -- ni ici, ni nulle part dans le depot. Raison, mesuree avant ce
# chantier et ecrite dans data/epigenetique.json:exposition_radioactive._note :
# exprimer() relit par _lire_chemin la valeur DEJA ECRITE au tick precedent,
# donc rappele chaque tick il fait DIVERGER SANS BORNE la propriete visee au
# lieu de refleter la marque courante. Le contournement, qui a un precedent
# litteral (banc_produit_nucleaire.gd affiche le modulateur brut et ne mute
# jamais 'vitesse') : CE CABLAGE lit lui-meme le modulateur et le compose dans
# son surcout thermique, surcout = ecart * cout_par_degre * (1 - modulateur).
# Le champ 'cible' de l'entree de catalogue est donc DOCUMENTAIRE ici, jamais lu
# par personne -- seul expression.gd lit 'cible'. Cabler cette boucle reste un
# chantier a part, hors perimetre.
#
# PLAFOND SUR LE MODULATEUR, ET POURQUOI IL N'EST PAS DECORATIF. epigenetique.gd
# n'a AUCUNE borne haute : poser() ajoute modulateur_pose sans plafond. Un
# modulateur qui depasserait 1.0 rendrait (1 - modulateur) NEGATIF, et le surcout
# thermique deviendrait un GAIN : le froid RECHARGERAIT le colon. Le plafond
# (plafond_accoutumance, en donnee) est donc une condition de correction du
# cablage, pas un reglage de confort. Verrouille par test.
#
# DEUX MIROIRS PLATS, ET POURQUOI ILS SONT OBLIGATOIRES. seuil_etat.gd ne sait
# lire qu'une cle PLATE de proprietes (une reserve vit sous
# proprietes.reserves.<nom>.reserve -- un chemin en points qu'il ne parcourt
# jamais) et ne compare que VERS LE HAUT (valeur > seuil). « L'energie descend a
# zero » et « la graisse est epuisee » ne sont donc pas exprimables directement :
# le cablage ecrit chaque tick manque_energie (capacite - reserve) et
# manque_graisse, que data/seuils_etat.json compare. Constat B de l'audit ;
# precedent exact dose_radiation_objet (banc_activation_neutronique.gd).
#
# LES MIROIRS SONT PARTAGES, PAS PRIVES -- constate en lancant la scene, et
# voulu. 'manque_energie' et 'froid_ressenti' portent EXACTEMENT les memes noms
# que dans banc_faim_thermo.gd : une grandeur, un nom, jamais deux miroirs
# concurrents. Consequence directe et gratuite : les entrees PARTAGEES 'faim'
# (60.0) puis 'famine' (99.0) forment un escalier sur une seule grandeur, et
# 'frisson'/'hypothermie' se posent sur le colon de ce banc des le premier tick
# sans qu'une ligne ne les demande. Leurs modulations de vitesse se composent
# multiplicativement (etat_effectif.gd), et l'ecrasement de 'mort_famine' gagne
# sur toutes.
#
# manque_graisse EST SOUS GATE, et sans ce gate le banc mentirait des le premier
# tick. Le colon nait SANS graisse : un miroir ecrit inconditionnellement
# vaudrait la capacite entiere a t=0, et 'mort_famine' serait pose avant que
# quoi que ce soit ne se passe. Le miroir n'est donc ecrit que si 'famine' est
# actif, et vaut 0.0 sinon -- gate de cablage ordinaire (constat A : le cablage
# lit etats_actifs et ecrit lui-meme le nombre, depense.gd ne consulte jamais
# etat_effectif.gd et etat_effectif.gd ne pose jamais aucun etat). CONSEQUENCE
# DITE : 'mort_famine' est REVERSIBLE PAR CONSTRUCTION (contrairement a
# 'mort_maladie'/'mort_radiation', assis sur des grandeurs qui ne redescendent
# jamais) -- il ne se retire jamais dans ce banc parce que rien n'y ressuscite
# ni ne nourrit un mort, jamais parce qu'un mecanisme l'interdirait.
#
# UN TICK DE RETARD, assume. poser_miroirs lit 'famine' AVANT que SeuilEtat ne
# tourne ce tick : c'est donc l'etat du tick precedent qui decide du gate et du
# sens du transfert. A 60 images/s, un tick de retard sur une bascule qui arrive
# une fois par vie ne se voit sur aucune decimale affichee.
#
# UNE SEULE ECRITURE DE surcout_action PAR TICK (constat D de l'audit) :
# poser_surcout_action est l'UNIQUE ECRIVAIN de ce champ dans tout ce fichier.
# Ce banc n'a qu'une source de surcout (le froid) -- la discipline est tenue
# quand meme, parce qu'un deuxieme ecrivain ajoute plus tard n'aurait aucun
# endroit ou se declarer.
#
# ECARTS A LA CONSIGNE, signales plutot que codes en silence :
# - LE CLIC DROIT (bascule de la source de froid) n'etait pas demande. Sans lui,
#   le colon est expose au froid du premier au dernier tick et la DECROISSANCE
#   de la marque -- moitie du contrat d'epigenetique.gd, et un des tests exiges
#   -- ne serait jamais observable A L'ECRAN, seulement prouvee headless. Meme
#   nature d'ajout que les fleches d'humidite de banc_biomes.gd.
# - LE COLON NE SE DEPLACE PAS. 'vitesse' est portee, modulee par les etats et
#   AFFICHEE (c'est la preuve visible que 'mort_famine' ECRASE a 0.0), mais
#   aucun deplacement ne la consomme : la variable observee ici est la reserve,
#   pas le trajet. Aucun surcout d'effort, donc aucune collision d'ecrivains sur
#   surcout_action.
#
# COLON CONSTRUIT A LA MAIN (pas Objet.fabriquer, meme statut que
# banc_maladie.gd/banc_ecoulement.gd/banc_biomes.gd) : ni composition ni
# materiau, donc ni masse ni densite, et data/types.json n'est pas touche par ce
# chantier -- rien a enregistrer dans scripts/test_lint_donnees.gd.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit colon, nourriture, zone et rendu ; _process
#   enchaine les mecanismes du coeur, TOUS APPELES TELS QUELS (Temperature.locale
#   -> poser_surcout_action -> manger -> avancer_reserves -> Depense.avancer ->
#   poser_miroirs -> SeuilEtat.avancer -> Epigenetique.poser/avancer) et lit
#   leurs resultats pour l'affichage ; _unhandled_input porte les deux bascules
#   et ne calcule jamais rien.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_graisse_accoutumance.gd).
#
# AUCUN NOM DE PROPRIETE, D'ETAT NI DE MARQUE EN DUR : nom_reserve_energie/
# nom_reserve_graisse/nom_reserve_nourriture/nom_vitesse/nom_manque_energie/
# nom_manque_graisse/nom_froid_ressenti/nom_marque_accoutumance/nom_etat_famine/
# nom_etat_mort_famine arrivent tous de data/banc_graisse_accoutumance.json --
# c'est ce qui permet au test de faire traverser le meme code par un domaine
# entierement invente.

const Consommer = preload("res://scripts/consommer.gd")
const Depense = preload("res://scripts/depense.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Epigenetique = preload("res://scripts/epigenetique.gd")
const Temperature = preload("res://scripts/temperature.gd")

var _config: Dictionary = {}
var _catalogue_etats: Dictionary = {}
var _catalogue_seuils: Dictionary = {}
var _catalogue_temperature: Dictionary = {}
var _catalogue_epigenetique: Dictionary = {}

var _colon: Dictionary = {}
var _nourriture: Dictionary = {}
var _monde: Array = []
var _temps: float = 0.0
var _horloge_marque: float = 0.0
var _horloge_trace: float = 0.0
var _nourriture_active := true
var _froid_actif := true
var _mort_tracee := false

var _noeud_colon: ColorRect
var _noeud_nourriture: ColorRect
var _label_colon: Label
var _label_compteur: Label
var _label_aide: Label
var _barres: Dictionary = {}

func _ready() -> void:
	_config = _charger_json("res://data/banc_graisse_accoutumance.json")
	_catalogue_etats = _charger_json("res://data/etats.json")
	_catalogue_seuils = _charger_json("res://data/seuils_etat.json")
	_catalogue_temperature = _charger_json("res://data/temperature.json")
	_catalogue_epigenetique = _charger_json("res://data/epigenetique.json")

	_colon = construire_colon(_config)
	_nourriture = construire_nourriture(_config)
	# La nourriture entre dans le monde avance par depense.gd : son canal est a
	# cout nul, elle ne pourrit pas toute seule. Elle ne perd de la matiere que
	# par le transfert, jamais par le temps.
	_monde = [_colon, _nourriture]

	_construire_rendu()
	print(ligne_pose(_config, _catalogue_seuils))
	_rafraichir(decomposition_nulle(), float(_config.temp_cible))

func _process(delta: float) -> void:
	_temps += delta

	# Ce qu'il fait AUTOUR du colon -- mecanisme du coeur, appele tel quel.
	# Source coupee (clic droit) : plus aucune source, temperature.gd degenere en
	# l'ambiante seule, sans cas particulier code ici.
	var temp_locale: float = Temperature.locale(
		_colon.position, sources_temperature(_config, _froid_actif), _catalogue_temperature)

	# TOUT le tick vit dans avancer_colon, une fonction STATIQUE : ce _process ne
	# calcule rien qu'un test ne pourrait rejouer. Regle d'etat de CLAUDE.md --
	# ce qui est enferme dans _process regresse en silence.
	var resultat: Dictionary = avancer_colon(
		_colon, _nourriture, _monde, delta, temp_locale,
		_nourriture_active, _horloge_marque, _config,
		_catalogue_seuils, _catalogue_epigenetique)
	_horloge_marque = float(resultat.horloge)

	for ligne in lignes_changement(_temps, resultat.changements):
		print(ligne)
	# Trace periodique : sans elle, un lancement headless se termine sur un
	# silence indistinguable d'un banc qui n'a rien fait (le reste de la console
	# ne dit que les CHANGEMENTS d'etat, jamais l'etat).
	_horloge_trace += delta
	if _horloge_trace >= float(_config.intervalle_trace_s):
		_horloge_trace = 0.0
		print(ligne_trace(_temps, _colon, _config, resultat.decomposition, _nourriture_active))
	if est_mort(_colon, _config) and not _mort_tracee:
		_mort_tracee = true
		print(ligne_mort(_temps, _colon, _config))

	_rafraichir(resultat.decomposition, temp_locale)

func _unhandled_input(evenement: InputEvent) -> void:
	# Le clic ne fait que basculer un drapeau : aucune decision, aucun calcul.
	if not (evenement is InputEventMouseButton) or not evenement.pressed:
		return
	if evenement.button_index == MOUSE_BUTTON_LEFT:
		_nourriture_active = not _nourriture_active
		print(ligne_bascule(_temps, "nourriture", _nourriture_active))
	elif evenement.button_index == MOUSE_BUTTON_RIGHT:
		_froid_actif = not _froid_actif
		print(ligne_bascule(_temps, "source de froid", _froid_actif))

# ---- Fonctions PURES, testables headless ----

# UN TICK COMPLET, l'ordre compris. Statique et sans noeud : le test rejoue
# EXACTEMENT ce que la scene execute, jamais une reconstitution parallele qui
# pourrait deriver. MUTE colon/nourriture/monde en place ; rend
# { decomposition, changements, horloge, transferts, miroirs, mange }.
#
# L'ORDRE N'EST PAS LIBRE, quatre contraintes le fixent :
#   (1) poser_surcout_action AVANT Depense.avancer -- sinon la depense de ce
#       tick utiliserait le surcout du precedent.
#   (2) avancer_reserves AVANT Depense.avancer -- en famine, la graisse doit
#       avoir recharge l'energie avant qu'elle ne soit brulee, sinon la reserve
#       est bornee a 0.0 par depense.gd et le transfert du tick suivant repart
#       d'un cout deja consomme.
#   (3) poser_miroirs APRES Depense.avancer -- les seuils doivent comparer la
#       reserve de CE tick, jamais celle du precedent.
#   (4) SeuilEtat.avancer APRES les miroirs, et donc APRES les transferts : le
#       gate 'famine' lu par avancer_reserves/poser_miroirs est celui du tick
#       PRECEDENT (voir en-tete, « UN TICK DE RETARD »).
static func avancer_colon(
	colon: Dictionary,
	nourriture: Dictionary,
	monde: Array,
	delta: float,
	temp_locale: float,
	nourriture_active: bool,
	horloge_marque: float,
	config: Dictionary,
	catalogue_seuils: Dictionary,
	catalogue_epigenetique: Dictionary,
) -> Dictionary:
	var decomposition: Dictionary = poser_surcout_action(colon, temp_locale, config)

	var mort: bool = est_mort(colon, config)
	var mange: float = 0.0
	var transferts: Dictionary = {"surplus": 0.0, "famine": 0.0}
	if not mort:
		if nourriture_active:
			mange = manger(nourriture, colon, config, delta)
		transferts = avancer_reserves(colon, config, delta)
		# Un mort ne brule plus rien : gate de cablage, jamais un etat qui
		# mettrait depense.gd a l'arret (depense.gd ne lit aucun etat).
		Depense.avancer(monde, delta)

	var miroirs: Dictionary = poser_miroirs(colon, config)

	var etats_avant: Array = colon.proprietes.get("etats_actifs", []).duplicate()
	SeuilEtat.avancer(monde, catalogue_seuils)
	var changements: Dictionary = changements_etats(etats_avant, colon.proprietes.get("etats_actifs", []))

	# La marque : posee par intervalle tant que le froid mord, decrue
	# INCONDITIONNELLEMENT (patron banc_produit_nucleaire.gd).
	var expose: bool = (not mort) and float(decomposition.get("froid", 0.0)) > 0.0
	var horloge: Dictionary = avancer_horloge_marque(
		horloge_marque, delta, float(config.intervalle_pose_accoutumance_s), expose)
	if bool(horloge.poser):
		Epigenetique.poser(colon, String(config.nom_marque_accoutumance), catalogue_epigenetique)
	Epigenetique.avancer(colon, delta, catalogue_epigenetique)

	return {
		"decomposition": decomposition,
		"changements": changements,
		"horloge": float(horloge.horloge),
		"transferts": transferts,
		"miroirs": miroirs,
		"mange": mange,
	}

# Le colon porte DEUX canaux de reserve. 'energie' brule (cout_base =
# metabolisme, pose ici une fois et jamais reecrit ; surcout_action ecrit par
# poser_surcout_action et par personne d'autre). 'graisse' est un canal a COUT
# NUL : depense.gd le parcourt et n'en retire rien -- la graisse ne se perd que
# par transfert, jamais par le temps. marques_epigenetiques est STRUCTURELLE
# pour epigenetique.gd (son absence est une alarme, pas « aucune marque ») :
# posee vide ici, comme data/types.json:dynamique le fait pour les types reels.
static func construire_colon(config: Dictionary) -> Dictionary:
	var depart: Array = config.position_colon
	var reserves: Dictionary = {}
	reserves[String(config.nom_reserve_energie)] = {
		"reserve": float(config.energie_initiale),
		"cout_base": float(config.metabolisme_base_par_s),
		"surcout_action": 0.0,
	}
	reserves[String(config.nom_reserve_graisse)] = {
		"reserve": float(config.graisse_initiale),
		"cout_base": 0.0,
		"surcout_action": 0.0,
	}
	var proprietes: Dictionary = {
		"reserves": reserves,
		"etats_actifs": [],
		"marques_epigenetiques": {},
	}
	proprietes[String(config.nom_vitesse)] = float(config.vitesse_base)
	return {
		"id": "colon",
		"position": Vector3(float(depart[0]), float(depart[1]), float(depart[2])),
		"proprietes": proprietes,
	}

# Un tas de matiere comestible, sans etat ni marque : ce n'est pas une entite,
# seulement une source de transfert. Canal a cout nul, meme raison que la
# graisse ci-dessus.
static func construire_nourriture(config: Dictionary) -> Dictionary:
	var depart: Array = config.position_nourriture
	var reserves: Dictionary = {}
	reserves[String(config.nom_reserve_nourriture)] = {
		"reserve": float(config.nourriture_initiale),
		"cout_base": 0.0,
		"surcout_action": 0.0,
	}
	return {
		"id": "nourriture",
		"position": Vector3(float(depart[0]), float(depart[1]), float(depart[2])),
		"proprietes": {"reserves": reserves},
	}

# Traduit la zone du banc dans la forme EXACTE que temperature.gd attend
# ({ position, rayon, temperature, force }) -- la couleur de rendu reste dans la
# zone et n'entre jamais dans le calcul. Source coupee : Array VIDE, jamais une
# source a force nulle qui ferait croire qu'il reste quelque chose.
static func sources_temperature(config: Dictionary, froid_actif: bool) -> Array:
	if not froid_actif:
		return []
	var zone: Dictionary = config.zone_froide
	var p: Array = zone.position
	return [{
		"position": Vector3(float(p[0]), float(p[1]), float(p[2])),
		"rayon": float(zone.rayon),
		"temperature": float(zone.temperature),
		"force": float(zone.force),
	}]

# Jamais negatif : au-dessus de la cible de confort, il ne fait pas « moins
# froid que zero », il ne fait plus froid du tout.
static func froid_ressenti(temp_locale: float, temp_cible: float) -> float:
	return max(0.0, temp_cible - temp_locale)

# Lit la marque posee par epigenetique.gd et la BORNE. Marque absente (jamais
# posee, ou retiree sous son plancher_suppression) : 0.0, point neutre legitime,
# jamais une alarme. Borne haute obligatoire -- voir en-tete, « PLAFOND SUR LE
# MODULATEUR » : au-dela de 1.0 le surcout thermique changerait de signe.
static func modulateur_accoutumance(colon: Dictionary, config: Dictionary) -> float:
	var marques: Dictionary = colon.proprietes.get("marques_epigenetiques", {})
	var canal: Dictionary = marques.get(String(config.nom_marque_accoutumance), {})
	var brut: float = float(canal.get("modulateur", 0.0))
	return clamp(brut, 0.0, float(config.plafond_accoutumance))

# LE contournement du blocage d'expression.gd (voir en-tete) : le modulateur est
# compose ICI, dans le cablage, jamais par exprimer()/appliquer().
static func surcout_thermo(froid: float, modulateur: float, config: Dictionary) -> float:
	return froid * float(config.cout_par_degre_froid) * (1.0 - modulateur)

# UNIQUE ECRIVAIN de canal.surcout_action et du miroir de froid. MUTE le colon
# en place ; rend la DECOMPOSITION pour que l'affichage la relise sans jamais
# rien recalculer (meme discipline que banc_emergences.gd). Canal absent (config
# incoherente) : push_error, rien n'est ecrit, decomposition a total nul --
# jamais un canal invente a la volee.
static func poser_surcout_action(colon: Dictionary, temp_locale: float, config: Dictionary) -> Dictionary:
	var froid: float = froid_ressenti(temp_locale, float(config.temp_cible))
	var modulateur: float = modulateur_accoutumance(colon, config)
	var brut: float = froid * float(config.cout_par_degre_froid)
	var thermo: float = surcout_thermo(froid, modulateur, config)

	var proprietes: Dictionary = colon.proprietes
	proprietes[String(config.nom_froid_ressenti)] = froid

	var nom_reserve := String(config.nom_reserve_energie)
	var reserves: Dictionary = proprietes.get("reserves", {})
	if not reserves.has(nom_reserve):
		push_error("banc_graisse_accoutumance : canal de reserve '%s' absent du colon, surcout non pose" % nom_reserve)
		return {"froid": froid, "modulateur": modulateur, "brut": brut, "thermo": 0.0, "total": 0.0}
	reserves[nom_reserve]["surcout_action"] = thermo
	return {"froid": froid, "modulateur": modulateur, "brut": brut, "thermo": thermo, "total": thermo}

static func decomposition_nulle() -> Dictionary:
	return {"froid": 0.0, "modulateur": 0.0, "brut": 0.0, "thermo": 0.0, "total": 0.0}

static func est_famine(colon: Dictionary, config: Dictionary) -> bool:
	return colon.proprietes.get("etats_actifs", []).has(String(config.nom_etat_famine))

static func est_mort(colon: Dictionary, config: Dictionary) -> bool:
	return colon.proprietes.get("etats_actifs", []).has(String(config.nom_etat_mort_famine))

static func _reserve(colon: Dictionary, nom: String) -> float:
	return float(colon.proprietes.get("reserves", {}).get(nom, {}).get("reserve", 0.0))

# Le cout total COURANT du canal d'energie (metabolisme + surcout thermique de
# ce tick). C'est lui qui plafonne la mobilisation de graisse -- voir
# taux_famine_effectif.
static func cout_energie_courant(colon: Dictionary, config: Dictionary) -> float:
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	return float(canal.get("cout_base", 0.0)) + float(canal.get("surcout_action", 0.0))

# La graisse n'est pas mobilisee a un taux fixe : elle est brulee EXACTEMENT au
# rythme ou l'energie part, dans la limite de taux_famine_max (le corps ne sait
# pas en liberer plus vite). Ce n'est pas un raffinement gratuit -- un taux fixe
# SUPERIEUR au cout aurait fait remonter l'energie au-dessus du seuil de famine,
# donc retirer l'etat, donc arreter le transfert, donc redescendre : un
# clignotement permanent de 'famine' au lieu d'une agonie lisible. Et c'est ce
# qui rend l'accoutumance DIRECTEMENT visible : moins de combustion, graisse qui
# dure plus longtemps, sans une ligne de plus.
static func taux_famine_effectif(colon: Dictionary, config: Dictionary) -> float:
	return min(float(config.taux_famine_max), cout_energie_courant(colon, config))

# SENS 1 -- energie vers graisse. Borne par le CABLAGE, mais pour des raisons de
# DOMAINE (surplus reel, place restante), jamais pour se proteger de
# consommer.gd : rien dans le coeur ne borne le haut d'une reserve.
static func transferer_surplus(colon: Dictionary, config: Dictionary, delta: float) -> float:
	if delta <= 0.0:
		return 0.0
	var nom_e := String(config.nom_reserve_energie)
	var nom_g := String(config.nom_reserve_graisse)
	var surplus: float = _reserve(colon, nom_e) - float(config.seuil_surplus)
	if surplus <= 0.0:
		return 0.0
	var place: float = float(config.capacite_graisse) - _reserve(colon, nom_g)
	if place <= 0.0:
		return 0.0
	var taux: float = min(float(config.taux_surplus_max), min(surplus, place) / delta)
	if taux <= 0.0:
		return 0.0
	return float(Consommer.transferer(colon, colon, nom_e, nom_g, taux, delta).quantite)

# SENS 2 -- graisse vers energie. AUCUN pre-bornage : le taux nu part tel quel,
# et consommer.gd borne lui-meme a ce que la graisse possede reellement. Voir
# en-tete, « AUCUN PRE-BORNAGE DANS LE SENS FAMINE ».
static func transferer_famine(colon: Dictionary, config: Dictionary, delta: float) -> float:
	if delta <= 0.0:
		return 0.0
	var taux: float = taux_famine_effectif(colon, config)
	if taux <= 0.0:
		return 0.0
	return float(Consommer.transferer(
		colon, colon,
		String(config.nom_reserve_graisse), String(config.nom_reserve_energie),
		taux, delta).quantite)

# UN SEUL des deux sens par tick, jamais les deux : le gate est 'famine'
# (constat A de l'audit -- le cablage lit etats_actifs et decide). Un mort ne
# transfere plus rien.
static func avancer_reserves(colon: Dictionary, config: Dictionary, delta: float) -> Dictionary:
	if est_mort(colon, config):
		return {"surplus": 0.0, "famine": 0.0}
	if est_famine(colon, config):
		return {"surplus": 0.0, "famine": transferer_famine(colon, config, delta)}
	return {"surplus": transferer_surplus(colon, config, delta), "famine": 0.0}

# SATIETE, gate de cablage. RIEN DANS LE COEUR NE BORNE LE HAUT D'UNE RESERVE
# (finding de banc_fertilite.gd, toujours vrai : depense.gd ne borne que 0.0, ni
# flux.gd ni consommer.gd ne connaissent de capacite). Sans ce gate, une fois la
# graisse pleine le surplus n'a plus ou aller et l'energie monte SANS FIN --
# constate en lancant la scene, l'energie passait la capacite et continuait.
# Un colon plein cesse simplement de manger ; il s'y remet des que le
# metabolisme a entame sa reserve. C'est une regle de DOMAINE ecrite par le
# cablage, jamais un manque du mecanisme.
static func peut_manger(colon: Dictionary, config: Dictionary) -> bool:
	return _reserve(colon, String(config.nom_reserve_energie)) < float(config.capacite_energie)

# Transfert entre DEUX objets distincts -- le cas ordinaire, deja prouve par
# banc_manger.gd. Le taux arrive deja resolu (consommer.gd ne lit jamais aucun
# nom de propriete de domaine).
static func manger(nourriture: Dictionary, colon: Dictionary, config: Dictionary, delta: float) -> float:
	if not peut_manger(colon, config):
		return 0.0
	return float(Consommer.transferer(
		nourriture, colon,
		String(config.nom_reserve_nourriture), String(config.nom_reserve_energie),
		float(config.taux_manger), delta).quantite)

# LES DEUX MIROIRS PLATS. manque_graisse est SOUS GATE 'famine' -- sans ce gate,
# un colon qui nait sans graisse serait declare mort de faim au premier tick
# (voir en-tete). Bornes a 0.0 par le bas : une reserve au-dessus de sa capacite
# ne donne pas un « manque negatif ».
static func poser_miroirs(colon: Dictionary, config: Dictionary) -> Dictionary:
	var manque_e: float = max(0.0, float(config.capacite_energie) - _reserve(colon, String(config.nom_reserve_energie)))
	var manque_g: float = 0.0
	if est_famine(colon, config):
		manque_g = max(0.0, float(config.capacite_graisse) - _reserve(colon, String(config.nom_reserve_graisse)))
	colon.proprietes[String(config.nom_manque_energie)] = manque_e
	colon.proprietes[String(config.nom_manque_graisse)] = manque_g
	return {"manque_energie": manque_e, "manque_graisse": manque_g}

# Accumulateur d'intervalle. epigenetique.gd:poser ajoute un montant FIXE lu au
# catalogue, sans delta : appele a chaque image, la marque monterait a une
# vitesse qui dependrait de la machine. Poser par intervalle de temps rend
# l'accumulation independante du nombre d'images par seconde. Exposition
# coupee : l'horloge est REMISE A ZERO plutot que gelee -- un residu garde en
# memoire ferait poser une marque immediatement au retour dans le froid.
static func avancer_horloge_marque(horloge: float, delta: float, intervalle: float, expose: bool) -> Dictionary:
	if not expose:
		return {"horloge": 0.0, "poser": false}
	if intervalle <= 0.0:
		return {"horloge": 0.0, "poser": true}
	var suivant: float = horloge + delta
	if suivant < intervalle:
		return {"horloge": suivant, "poser": false}
	return {"horloge": suivant - intervalle, "poser": true}

# La vitesse n'est jamais consommee par un deplacement dans ce banc (voir
# en-tete, ECARTS) : elle est AFFICHEE, et c'est la preuve visible que
# 'mort_famine' ECRASE (etat_effectif.gd, un ecraseur gagne toujours sur un
# modulateur -- 'affame' module par 0.5, l'ecrasement a 0.0 l'emporte).
static func vitesse_effective(colon: Dictionary, config: Dictionary, catalogue_etats: Dictionary) -> float:
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

# Combien de secondes de graisse restent AU RYTHME COURANT de combustion -- une
# projection, jamais une prediction : elle s'allonge a chaque fois que
# l'accoutumance monte. C'est le chiffre qui rend « il survit plus longtemps »
# lisible sans attendre la fin.
static func secondes_de_graisse(colon: Dictionary, config: Dictionary) -> float:
	var graisse: float = _reserve(colon, String(config.nom_reserve_graisse))
	if graisse <= 0.0:
		return 0.0
	var cout: float = cout_energie_courant(colon, config)
	if cout <= 0.0:
		return INF
	return graisse / cout

# Le seuil vit dans le catalogue PARTAGE data/seuils_etat.json, jamais recopie
# en donnee de banc : une seule source de verite, jamais deux nombres a garder
# d'accord. Entree absente ou sans 'seuil' : push_error et INF.
static func seuil_de(catalogue_seuils: Dictionary, ref: String) -> float:
	if not catalogue_seuils.has(ref) or not catalogue_seuils[ref].has("seuil"):
		push_error("banc_graisse_accoutumance : entree '%s' sans 'seuil' dans data/seuils_etat.json" % ref)
		return INF
	return float(catalogue_seuils[ref].seuil)

# ---- Textes (aucune decision, seulement de la mise en forme) ----

static func texte_label_colon(colon: Dictionary, config: Dictionary, decomposition: Dictionary, temp_locale: float, vitesse: float) -> String:
	var proprietes: Dictionary = colon.proprietes
	var noms: Array = []
	for etat in proprietes.get("etats_actifs", []):
		noms.append(String(etat))
	noms.sort()
	return "energie %.1f / %.1f (surplus > %.1f)\ngraisse %.1f / %.1f\nmanque : energie %.1f -- graisse %.1f\nlocale %.1f C -- froid %.1f\nsurcout thermo %.3f = brut %.3f x (1 - accoutumance %.3f)\nvitesse %.1f (base %.1f)\netat : %s" % [
		_reserve(colon, String(config.nom_reserve_energie)),
		float(config.capacite_energie),
		float(config.seuil_surplus),
		_reserve(colon, String(config.nom_reserve_graisse)),
		float(config.capacite_graisse),
		float(proprietes.get(String(config.nom_manque_energie), 0.0)),
		float(proprietes.get(String(config.nom_manque_graisse), 0.0)),
		temp_locale,
		float(decomposition.get("froid", 0.0)),
		float(decomposition.get("thermo", 0.0)),
		float(decomposition.get("brut", 0.0)),
		float(decomposition.get("modulateur", 0.0)),
		vitesse,
		float(proprietes.get(String(config.nom_vitesse), 0.0)),
		" + ".join(noms) if not noms.is_empty() else "-",
	]

static func texte_compteur(colon: Dictionary, config: Dictionary, temps: float, nourriture_active: bool, froid_actif: bool) -> String:
	return "t=%.1f s -- nourriture %s -- froid %s -- graisse restante %s" % [
		temps,
		"presente" if nourriture_active else "RETIREE",
		"actif" if froid_actif else "COUPE",
		texte_duree(secondes_de_graisse(colon, config)),
	]

# INF n'est pas un nombre a afficher : une projection qui n'aboutit jamais se
# dit, elle ne se chiffre pas.
static func texte_duree(secondes: float) -> String:
	if secondes == INF:
		return "indefiniment (rien ne brule)"
	return "%.1f s" % secondes

static func lignes_changement(t: float, changements: Dictionary) -> Array:
	var lignes: Array = []
	for etat in changements.get("gagnes", []):
		lignes.append("t=%.1f etat POSE : %s" % [t, String(etat)])
	for etat in changements.get("perdus", []):
		lignes.append("t=%.1f etat RETIRE : %s" % [t, String(etat)])
	return lignes

static func ligne_pose(config: Dictionary, catalogue_seuils: Dictionary) -> String:
	return "t=0.0 colon pose : energie %.1f / %.1f, graisse %.1f / %.1f, seuil de surplus %.1f, metabolisme %.2f/s, confort %.1f C -- seuils %s (%s) et %s (%s)" % [
		float(config.energie_initiale), float(config.capacite_energie),
		float(config.graisse_initiale), float(config.capacite_graisse),
		float(config.seuil_surplus),
		float(config.metabolisme_base_par_s),
		float(config.temp_cible),
		String(config.nom_etat_famine), texte_duree_seuil(seuil_de(catalogue_seuils, String(config.ref_seuil_famine))),
		String(config.nom_etat_mort_famine), texte_duree_seuil(seuil_de(catalogue_seuils, String(config.ref_seuil_mort_famine))),
	]

static func texte_duree_seuil(seuil: float) -> String:
	if seuil == INF:
		return "absent du catalogue"
	return "%.1f" % seuil

static func ligne_trace(t: float, colon: Dictionary, config: Dictionary, decomposition: Dictionary, nourriture_active: bool) -> String:
	var noms: Array = []
	for etat in colon.proprietes.get("etats_actifs", []):
		noms.append(String(etat))
	noms.sort()
	return "t=%.1f %s | energie %.2f | graisse %.2f | accoutumance %.3f | surcout %.3f (brut %.3f) | etats %s" % [
		t,
		"repas" if nourriture_active else "jeune",
		_reserve(colon, String(config.nom_reserve_energie)),
		_reserve(colon, String(config.nom_reserve_graisse)),
		float(decomposition.get("modulateur", 0.0)),
		float(decomposition.get("thermo", 0.0)),
		float(decomposition.get("brut", 0.0)),
		" + ".join(noms) if not noms.is_empty() else "-",
	]

static func ligne_mort(t: float, colon: Dictionary, config: Dictionary) -> String:
	return "t=%.1f MORT DE FAIM -- energie %.2f, graisse %.2f, accoutumance atteinte %.3f" % [
		t,
		_reserve(colon, String(config.nom_reserve_energie)),
		_reserve(colon, String(config.nom_reserve_graisse)),
		modulateur_accoutumance(colon, config),
	]

static func ligne_bascule(t: float, quoi: String, actif: bool) -> String:
	return "t=%.1f bascule : %s -> %s" % [t, quoi, "ON" if actif else "OFF"]

# ---- Rendu (impur, Node) -- aucune decision, seulement des noeuds. ----

func _draw() -> void:
	var fond: Array = _config.couleur_fond
	draw_rect(Rect2(Vector2.ZERO, Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur))),
		Color(float(fond[0]), float(fond[1]), float(fond[2])))
	if _froid_actif:
		var zone: Dictionary = _config.zone_froide
		var p: Array = zone.position
		var c: Array = zone.couleur
		# Rayon REEL de la source, jamais un disque decoratif qui mentirait sur
		# l'etendue du froid.
		draw_circle(Vector2(float(p[0]), float(p[1])), float(zone.rayon),
			Color(float(c[0]), float(c[1]), float(c[2])))

func _construire_rendu() -> void:
	_noeud_nourriture = _creer_rect(_config.couleur_nourriture, float(_config.taille_nourriture))
	add_child(_noeud_nourriture)
	_noeud_colon = _creer_rect(_config.couleur_colon, float(_config.taille_colon))
	add_child(_noeud_colon)

	_label_colon = _creer_label(13)
	add_child(_label_colon)

	var couche := CanvasLayer.new()
	add_child(couche)
	_label_compteur = _creer_label(16)
	_label_compteur.position = Vector2(10.0, 10.0)
	couche.add_child(_label_compteur)

	var y: float = 40.0
	for barre in _config.barres:
		_barres[String(barre.cle)] = _creer_barre(couche, barre, y)
		y += float(_config.hauteur_barre) + 10.0

	_label_aide = _creer_label(13)
	_label_aide.position = Vector2(10.0, y + 4.0)
	_label_aide.text = "clic gauche : retirer / remettre la nourriture -- clic droit : couper / rallumer le froid"
	couche.add_child(_label_aide)

	_poser_camera()

func _creer_rect(couleur: Array, taille: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size = Vector2(taille, taille)
	rect.color = Color(float(couleur[0]), float(couleur[1]), float(couleur[2]))
	return rect

func _creer_barre(couche: CanvasLayer, barre: Dictionary, y: float) -> Dictionary:
	var largeur: float = float(_config.largeur_barre)
	var hauteur: float = float(_config.hauteur_barre)
	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.position = Vector2(10.0, y)
	fond.size = Vector2(largeur, hauteur)
	var cf: Array = _config.couleur_fond_barre
	fond.color = Color(float(cf[0]), float(cf[1]), float(cf[2]))
	couche.add_child(fond)

	var remplissage := ColorRect.new()
	remplissage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	remplissage.position = Vector2(10.0, y)
	remplissage.size = Vector2(0.0, hauteur)
	var cb: Array = barre.couleur
	remplissage.color = Color(float(cb[0]), float(cb[1]), float(cb[2]))
	couche.add_child(remplissage)

	var titre := _creer_label(13)
	titre.position = Vector2(largeur + 20.0, y - 2.0)
	couche.add_child(titre)
	return {"remplissage": remplissage, "titre": titre, "max": float(barre.maximum), "nom": String(barre.nom)}

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	# Contour sombre : le meme label doit rester lisible sur le bleu de la zone
	# froide comme sur le fond neutre.
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _rafraichir(decomposition: Dictionary, temp_locale: float) -> void:
	queue_redraw()
	var centre := Vector2(_colon.position.x, _colon.position.y)
	_noeud_colon.position = centre - _noeud_colon.size / 2.0
	var centre_n := Vector2(_nourriture.position.x, _nourriture.position.y)
	_noeud_nourriture.position = centre_n - _noeud_nourriture.size / 2.0
	_noeud_nourriture.visible = _nourriture_active

	var vitesse: float = vitesse_effective(_colon, _config, _catalogue_etats)
	_label_colon.position = centre + Vector2(float(_config.taille_colon), float(_config.taille_colon))
	_label_colon.text = texte_label_colon(_colon, _config, decomposition, temp_locale, vitesse)
	_label_compteur.text = texte_compteur(_colon, _config, _temps, _nourriture_active, _froid_actif)

	# Les barres RELISENT des nombres deja calcules, elles n'en recalculent
	# aucun (meme discipline que le label).
	_valeur_barre(String(_config.nom_reserve_energie), _reserve(_colon, String(_config.nom_reserve_energie)))
	_valeur_barre(String(_config.nom_reserve_graisse), _reserve(_colon, String(_config.nom_reserve_graisse)))
	_valeur_barre(String(_config.nom_marque_accoutumance), float(decomposition.get("modulateur", 0.0)))

func _valeur_barre(cle: String, valeur: float) -> void:
	if not _barres.has(cle):
		return
	var barre: Dictionary = _barres[cle]
	var maximum: float = float(barre.max)
	var ratio: float = 0.0 if maximum <= 0.0 else clamp(valeur / maximum, 0.0, 1.0)
	barre.remplissage.size = Vector2(float(_config.largeur_barre) * ratio, float(_config.hauteur_barre))
	barre.titre.text = "%s %.2f / %.2f" % [String(barre.nom), valeur, maximum]

func _poser_camera() -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur)) / 2.0
	camera.zoom = Vector2(0.9, 0.9)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
