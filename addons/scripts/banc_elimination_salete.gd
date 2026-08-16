extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_elimination_salete.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). Chantier « elimination +
# salete -> maladie » (audit_mecaniques_corps_prealable.md, lignes 7 et 8,
# toutes deux au verdict CABLABLE -- confirme a l'ecriture, aucune correction
# au verdict). Compose SIX patrons deja fermes, TOUS INCHANGES :
# scripts/depense.gd (le besoin qui monte), scripts/seuil_etat.gd (le besoin
# qui declenche, PUIS la mort), scripts/objet.gd + scripts/monde.gd (le dechet
# qui nait en cours de partie), scripts/charge.gd (la salete qui s'accumule
# et REDESCEND), scripts/etat_duree.gd (incubation puis symptomes),
# scripts/etat_effectif.gd (vitesse modulee par 'malade', ecrasee par
# 'mort_maladie'). AUCUN MECANISME DU COEUR TOUCHE, aucun .gd neuf du coeur.
#
# COLONS CONSTRUITS A LA MAIN (pas Objet.fabriquer, pas data/types.json:colon
# -- demonstration de cablage, meme statut que banc_maladie.gd/
# banc_contagion.gd). LES DECHETS, EUX, SONT DE VRAIS OBJETS FABRIQUES :
# Objet.fabriquer(data/types.json:dechet) puis _monde.ajouter, en cours de
# partie et non dans _ready -- patron banc_reproduction.gd:_naitre. C'est la
# seule facon d'obtenir 'salete_emise' depuis la fiche materiau
# (data/materiaux.json:dechet_demo) sans recopier le nombre dans le cablage :
# il est fusionne par la moyenne ponderee des volumes d'objet.gd, via une
# liste LOCALE de proprietes_immuables (jamais data/proprietes_immuables_
# composition.json, qui est universel et affecterait tout objet compose --
# meme decision que 'sensibilite_magique' dans banc_emergences.gd).
#
# LA CHAINE, EN UN SEUL PASSAGE (avancer(), fonction PURE) :
# 1) poser_taux_elimination : ECRIT cout_base ET surcout_action du canal, UNE
#    SEULE FOIS par tick et par UN SEUL ecrivain -- constat (D) de l'audit :
#    il n'y a qu'UN emplacement surcout_action par canal, deux morceaux de
#    cablage qui y ecrivent chacun le leur se detruisent en silence. Ici
#    surcout = -(coef_repas * taux_repas) : le colon qui mange beaucoup
#    elimine plus souvent, sans une ligne de mecanisme. Un colon MORT voit ses
#    deux taux mis a 0.0 (gate de cablage, voir la fonction).
# 2) Depense.avancer : la reserve MONTE au lieu de descendre, parce que
#    cout_base ET surcout sont NEGATIFS (depense.gd fait reserve =
#    max(0, reserve - (cout_base + surcout) * delta)) -- neutralite du
#    mecanisme exploitee, jamais contournee ; precedent, la jachere de
#    banc_fertilite.gd. AUCUNE borne haute n'existe dans le coeur : c'est le
#    seuil (3) qui vide la reserve, jamais un ecretage.
# 3) refleter_urgence : MIROIR PLAT. Une reserve vit sous proprietes.reserves.
#    <nom>.reserve et seuil_etat.gd ne sait lire qu'une cle PLATE (constat (B)
#    de l'audit) -- le cablage recopie donc la valeur dans proprietes.
#    urgence_elimination a chaque tick. Le miroir n'a PAS besoin d'etre
#    inverse ici (contrairement a 'affame'/'manque_energie' de la ligne 1 de
#    l'audit) : la reserve MONTE deja, et seuil_etat.gd compare vers le HAUT.
# 4) SeuilEtat.avancer(colons, config.seuils_elimination) : catalogue LOCAL au
#    banc (data/banc_elimination_salete.json, format exact de
#    data/seuils_etat.json -- seuil_etat.gd recoit toujours son catalogue en
#    parametre et ne charge jamais rien ; meme geste que data/banc_erosion.
#    json:vent face a data/vent.json). Pose 'doit_eliminer' (data/etats.json,
#    marqueur pur, effets vides).
# 5) Ce cablage, pour chaque id BASCULE qui porte bien 'doit_eliminer' (un
#    franchissement DESCENDANT figure aussi dans les bascules -- meme garde
#    que banc_maladie.gd sur 'mort_maladie') : fabrique un dechet a la
#    position du colon, l'ajoute au Monde, et VIDE la reserve. Personne ne
#    retire 'doit_eliminer' a la main : la reserve videe fait redescendre le
#    miroir sous le seuil, et seuil_etat.gd le retire LUI-MEME au tick
#    suivant, par sa propre reversibilite.
# 6) Charge.avancer(colons, causes, delta) ou causes = un { position, poids }
#    par dechet du Monde, poids = sa 'salete_emise' (comptage IMPLICITE,
#    charge.gd somme deja les causes a portee -- meme decision que
#    banc_maladie.gd/banc_contagion.gd). Au franchissement MONTANT, charge.gd
#    pose le marqueur 'expose_salete' ; au franchissement DESCENDANT il le
#    RETIRE tout seul.
# 7) Ce cablage lit ce marqueur et pose EtatDuree.poser("incube_maladie") --
#    la meme entree PARTAGEE de data/etats.json que banc_maladie.gd, jamais
#    une copie locale (deux bancs ne se referencent jamais entre eux, mais ils
#    lisent les memes donnees). Puis 'incube_maladie' qui expire pose
#    'malade' ; 'malade' qui expire sans mort prealable est une GUERISON.
# 8) Tant que 'malade' est actif, ce cablage accumule lui-meme
#    duree_maladie_cumulee (delta-scale, ne redescend jamais -- meme idiome
#    que force_traction_cumulee/exposition_acide_cumulee), et SeuilEtat.
#    avancer(colons, seuils_partages) -- data/seuils_etat.json, catalogue
#    PARTAGE lu sur disque et JAMAIS modifie par ce chantier -- pose
#    'mort_maladie' au-dela de son seuil.
#
# DIFFERENCE VOULUE AVEC banc_maladie.gd, ET SA CONSEQUENCE : la-bas, un colon
# contamine se fait RETIRER son canal receveur pour toujours (« porteur ou
# mort, il ne redevient jamais susceptible »). Ici le canal 'etats.salete'
# RESTE sur le colon toute sa vie -- sans lui, la charge ne pourrait plus
# jamais redescendre et « nettoyer fait redescendre la salete » serait
# infaisable. Consequence assumee, c'est meme le sujet du banc : un colon
# gueri qui repasse dans un tas de dechets retombe malade. La garde contre
# une double incubation n'est donc pas le retrait du canal mais _peut_incuber
# ci-dessous (deja en incubation, deja malade, ou mort -> on ne repose rien).
#
# DEPLACEMENT ALEATOIRE, RNG SEEDE (CLAUDE.md, aucun hasard non-seede) : meme
# geste que banc_maladie.gd:deplacer_colons -- chaque colon vivant (vitesse
# EFFECTIVE > 0.0, EtatEffectif.valeur, jamais reimplementee) marche vers une
# destination tiree dans data/banc_elimination_salete.json:zone
# (BancCommun.bouger_vers, jamais reimplemente). Un colon mort ne tire plus
# jamais de destination.
#
# CLIC GAUCHE : NETTOYAGE, PONCTUEL (jamais bistable -- un nettoyage n'a rien
# vers quoi rebasculer ; meme lecture que le feu au clic de banc_succession.gd,
# signalee la-bas et retenue). Le Monde est RECONSTRUIT DU NEANT sans les
# dechets (monde.gd n'a AUCUNE fonction de retrait, voir CARTE.md §6 -- meme
# idiome que banc_occlusion.gd/banc_absorption_sonore.gd:monde_du_tick) : les
# colons y sont RE-AJOUTES PAR REFERENCE, leur etat interne est donc
# integralement preserve. Le compteur de dechets, lui, n'est JAMAIS remis a
# zero -- monde.gd:ajouter refuse un id deja present, un id reutilise apres un
# nettoyage serait une chose non enregistree en silence.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les cinq fichiers de donnees, fabrique les
#   colons, cree le rendu. _unhandled_input declenche le nettoyage. _process
#   appelle avancer(...) puis deplacer_colons(...), imprime les traces,
#   redessine.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_elimination_salete.gd) : fabriquer_colons/fabriquer_dechet/
#   dechets_du_monde/causes_de_dechets/poser_surcout_repas/refleter_urgence/
#   avancer/monde_sans_dechets/deplacer_colons/etat_courant/compter_etats,
#   plus les textes d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Depense = preload("res://scripts/depense.gd")
const Charge = preload("res://scripts/charge.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const PROPRIETE_VITESSE := "vitesse"
const NOM_RESERVE := "besoin_elimination"
const PROPRIETE_MIROIR := "urgence_elimination"
const ETAT_ELIMINER := "doit_eliminer"
const MARQUEUR_SALETE := "expose_salete"
const ETAT_INCUBATION := "incube_maladie"
const ETAT_MALADE := "malade"
const ETAT_MORT := "mort_maladie"

const TAILLE_COLON := 26.0
const TAILLE_DECHET := 12.0
const DISTANCE_ARRIVEE := 4.0
const TAILLE_POLICE_LABEL := 12

var _config: Dictionary = {}
var _types: Dictionary = {}
var _materiaux: Dictionary = {}
var _etats: Dictionary = {}
var _seuils_partages: Dictionary = {}
var _colons: Array = []
var _monde
var _compteur_dechet := 0
var _rng := RandomNumberGenerator.new()
var _temps := 0.0
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _noeuds_dechet: Dictionary = {}
var _label_compteur: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_elimination_salete.json")
	_types = _charger_json("res://data/types.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_etats = _charger_json("res://data/etats.json")
	_seuils_partages = _charger_json("res://data/seuils_etat.json")
	_rng.seed = int(_config.get("seed", 0))

	_colons = fabriquer_colons(_config)
	_monde = BancCommun.monde_depuis([{"choses": _colons, "type": "colon"}])
	for colon in _colons:
		_creer_rendu_colon(colon)

	_label_compteur = Label.new()
	_label_compteur.position = Vector2(20.0, 10.0)
	add_child(_label_compteur)
	_poser_camera()
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var retires: int = dechets_du_monde(_monde, _config.type_dechet).size()
		_monde = monde_sans_dechets(_monde, _config.type_dechet)
		for id in _noeuds_dechet:
			_noeuds_dechet[id].queue_free()
		_noeuds_dechet.clear()
		print(_ligne_nettoyage(_temps, retires))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta

	var resultat := avancer(_colons, _monde, _compteur_dechet, delta, _config, _catalogues())
	_compteur_dechet = resultat.compteur_dechet
	deplacer_colons(_colons, _config.zone, _etats, _rng, delta)

	for entree in resultat.nouveaux_dechets:
		print(_ligne_dechet(_temps, entree.colon_id, entree.id))
		_creer_rendu_dechet(entree.id)
	for id in resultat.nouveaux_exposes:
		print(_ligne_expose(_temps, id))
	for id in resultat.nouveaux_malades:
		print(_ligne_symptomes(_temps, id))
	for id in resultat.gueris:
		print(_ligne_gueri(_temps, id))
	for id in resultat.morts:
		print(_ligne_mort(_temps, id))

	_rafraichir_tout()

func _catalogues() -> Dictionary:
	return {
		"types": _types,
		"materiaux": _materiaux,
		"etats": _etats,
		"seuils_partages": _seuils_partages,
	}

# ---- Fonctions PURES, testables headless (test_banc_elimination_salete.gd) --

# Construit les colons de data/banc_elimination_salete.json (ou toute config
# du meme format). Chaque colon porte : 'vitesse' (base, modulee/ecrasee
# ensuite par etat_effectif.gd), le canal de reserve besoin_elimination
# (duplique par colon -- jamais partage, bug d'aliasing deja ferme ailleurs,
# voir banc_commun.gd:resoudre_chantier), le canal de charge etats.salete
# (duplique de meme), 'taux_repas' (le nombre que le cablage compose en
# surcout, jamais lu par un mecanisme du coeur), 'urgence_elimination' et
# 'duree_maladie_cumulee' a 0.0 (STRUCTURELLES pour seuil_etat.gd des le
# premier tick).
static func fabriquer_colons(config: Dictionary) -> Array:
	var colons: Array = []
	for decl in config.colons:
		var pos: Array = decl.position
		var position3 := Vector3(pos[0], pos[1], pos[2])
		colons.append({
			"id": decl.id,
			"position": position3,
			"destination": position3,
			"proprietes": {
				"vitesse": float(config.vitesse_base),
				"taux_repas": float(decl.get("taux_repas", 0.0)),
				"reserves": {NOM_RESERVE: config.canal_besoin_elimination.duplicate(true)},
				"etats": {"salete": config.canal_salete.duplicate(true)},
				PROPRIETE_MIROIR: 0.0,
				"duree_maladie_cumulee": 0.0,
				"etats_actifs": [],
			},
		})
	return colons

# UN SEUL ECRIVAIN des deux champs du canal (constat (D) de l'audit : un seul
# emplacement surcout_action par canal, deux ecrivains se detruiraient en
# silence). Le surcout est NEGATIF comme cout_base, la reserve monte donc PLUS
# VITE pour qui mange plus ; un colon a taux_repas 0.0 retombe exactement sur
# la montee de base -- aucun cas particulier code, l'arithmetique suffit.
#
# GATE DE CABLAGE SUR LA MORT (precedent unanime : banc_corrosion.gd/
# banc_conduction.gd ecrivent de meme un cout_base selon un etat actif --
# depense.gd ne consulte JAMAIS etat_effectif.gd, constat (A) de l'audit) :
# un colon mort voit ses DEUX taux mis a 0.0, sa reserve se fige, son miroir
# reste sous le seuil, il n'elimine plus jamais. TROUVE EN LANCANT LA SCENE
# REELLE, invisible au test d'origine : un cadavre continuait de produire des
# dechets a t=27.0s apres etre mort a t=26.3s.
static func poser_taux_elimination(colons: Array, config: Dictionary) -> void:
	var canal_ref: Dictionary = config.canal_besoin_elimination
	var coef_repas: float = float(config.coef_repas)
	for colon in colons:
		var reserves: Dictionary = colon.proprietes.get("reserves", {})
		if not reserves.has(NOM_RESERVE):
			continue
		var canal: Dictionary = reserves[NOM_RESERVE]
		if colon.proprietes.get("etats_actifs", []).has(ETAT_MORT):
			canal["cout_base"] = 0.0
			canal["surcout_action"] = 0.0
			continue
		canal["cout_base"] = float(canal_ref.cout_base)
		canal["surcout_action"] = -(coef_repas * float(colon.proprietes.get("taux_repas", 0.0)))

# MIROIR PLAT : seuil_etat.gd ne sait pas descendre dans proprietes.reserves.
# <nom>.reserve (constat (B) de l'audit). Recopie, jamais un calcul.
static func refleter_urgence(colons: Array) -> void:
	for colon in colons:
		var reserves: Dictionary = colon.proprietes.get("reserves", {})
		if not reserves.has(NOM_RESERVE):
			continue
		colon.proprietes[PROPRIETE_MIROIR] = float(reserves[NOM_RESERVE].get("reserve", 0.0))

# Le besoin repart de zero. Le miroir est remis a zero DANS LE MEME GESTE :
# sans lui, seuil_etat.gd relirait la valeur d'avant au tick suivant et
# 'doit_eliminer' resterait pose un tick de trop.
static func vider_reserve(colon: Dictionary) -> void:
	var reserves: Dictionary = colon.proprietes.get("reserves", {})
	if reserves.has(NOM_RESERVE):
		reserves[NOM_RESERVE]["reserve"] = 0.0
	colon.proprietes[PROPRIETE_MIROIR] = 0.0

# Objet.fabriquer complet (patron banc_reproduction.gd:fabriquer_enfant) : le
# type et la composition viennent de data/types.json:dechet, la densite et la
# salete_emise de data/materiaux.json:dechet_demo. La liste de proprietes
# immuables est LOCALE a ce banc (voir en-tete) -- data/proprietes_immuables_
# composition.json n'est pas touche. Rend {} si objet.gd REFUSE la
# fabrication (materiau absent, fiche sans densite) : l'appelant doit le
# verifier avant de lire .id/.position (contrat explicite d'objet.gd).
static func fabriquer_dechet(id: String, position: Vector3, config: Dictionary, catalogues: Dictionary) -> Dictionary:
	return Objet.fabriquer(
		id, config.type_dechet, position,
		catalogues.types, catalogues.materiaux,
		[config.propriete_salete],
	)

# Les dechets sont lus DEPUIS LE MONDE, jamais depuis une liste tenue en
# parallele par le banc : le Monde est la seule source de verite, sans quoi un
# nettoyage devrait etre applique a deux endroits.
static func dechets_du_monde(monde, type_dechet: String) -> Array:
	var dechets: Array = []
	for entree in monde.choses.values():
		if entree.type == type_dechet:
			dechets.append(entree.chose)
	return dechets

# Une cause { position, poids } par dechet -- le poids est la salete_emise
# FUSIONNEE sur l'objet, jamais un nombre recopie dans ce fichier. Comptage
# IMPLICITE : charge.gd somme deja toutes les causes a portee, deux dechets
# cote a cote salissent deux fois plus vite sans une ligne de plus.
static func causes_de_dechets(dechets: Array, propriete_salete: String) -> Array:
	var causes: Array = []
	for dechet in dechets:
		causes.append({
			"position": dechet.position,
			"poids": float(dechet.proprietes.get(propriete_salete, 0.0)),
		})
	return causes

static func _colon_par_id(colons: Array, id: String) -> Variant:
	for colon in colons:
		if colon.id == id:
			return colon
	return null

# Garde contre une double incubation (voir en-tete, DIFFERENCE VOULUE AVEC
# banc_maladie.gd) : le canal receveur restant en place toute la vie du colon,
# c'est ici -- et nulle part ailleurs -- qu'un colon deja en incubation, deja
# malade ou mort cesse d'etre relance.
static func _peut_incuber(colon: Dictionary) -> bool:
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	return not (actifs.has(ETAT_INCUBATION) or actifs.has(ETAT_MALADE) or actifs.has(ETAT_MORT))

# UN PAS complet d'elimination + salete + maladie (le deplacement est une
# fonction separee, voir deplacer_colons). MUTE colons et monde en place ;
# 'compteur_dechet' entre et ressort par le resultat plutot que de vivre dans
# un etat statique -- une fonction pure ne garde pas de memoire entre deux
# appels, et deux tests qui tournent dans le meme processus ne doivent jamais
# se contaminer.
#
# Rend { nouveaux_dechets: Array de { id, colon_id }, nouveaux_exposes,
# nouveaux_malades, gueris, morts: Array d'id, compteur_dechet: int } -- pour
# que l'appelant (le Node, ou un test) trace chaque transition sans jamais
# relire l'etat avant/apres lui-meme.
static func avancer(colons: Array, monde, compteur_dechet: int, delta: float, config: Dictionary, catalogues: Dictionary) -> Dictionary:
	poser_taux_elimination(colons, config)
	Depense.avancer(colons, delta)
	refleter_urgence(colons)

	var nouveaux_dechets: Array = []
	for id in SeuilEtat.avancer(colons, config.seuils_elimination):
		var colon: Variant = _colon_par_id(colons, id)
		if colon == null or not colon.proprietes.get("etats_actifs", []).has(ETAT_ELIMINER):
			continue
		compteur_dechet += 1
		var dechet := fabriquer_dechet("dechet_%d" % compteur_dechet, colon.position, config, catalogues)
		if dechet.is_empty():
			continue
		monde.ajouter(dechet, config.type_dechet, dechet.position)
		vider_reserve(colon)
		nouveaux_dechets.append({"id": dechet.id, "colon_id": id})

	var causes := causes_de_dechets(dechets_du_monde(monde, config.type_dechet), config.propriete_salete)
	var nouveaux_exposes: Array = []
	for id in Charge.avancer(colons, causes, delta):
		var colon: Variant = _colon_par_id(colons, id)
		if colon == null or not colon.proprietes.get(MARQUEUR_SALETE, false):
			continue
		nouveaux_exposes.append(id)
		if _peut_incuber(colon):
			EtatDuree.poser(colon, ETAT_INCUBATION, catalogues.etats)

	var nouveaux_malades: Array = []
	var gueris: Array = []
	for entree in EtatDuree.avancer(colons, delta, catalogues.etats):
		var colon: Variant = _colon_par_id(colons, entree.id)
		if colon == null:
			continue
		if entree.nom_etat == ETAT_INCUBATION:
			EtatDuree.poser(colon, ETAT_MALADE, catalogues.etats)
			nouveaux_malades.append(entree.id)
		elif entree.nom_etat == ETAT_MALADE:
			if not colon.proprietes.get("etats_actifs", []).has(ETAT_MORT):
				gueris.append(entree.id)

	for colon in colons:
		if colon.proprietes.get("etats_actifs", []).has(ETAT_MALADE):
			colon.proprietes["duree_maladie_cumulee"] = colon.proprietes.get("duree_maladie_cumulee", 0.0) + delta

	var morts: Array = []
	for id in SeuilEtat.avancer(colons, catalogues.seuils_partages):
		var colon: Variant = _colon_par_id(colons, id)
		if colon == null or not colon.proprietes.get("etats_actifs", []).has(ETAT_MORT):
			continue
		morts.append(id)

	return {
		"nouveaux_dechets": nouveaux_dechets,
		"nouveaux_exposes": nouveaux_exposes,
		"nouveaux_malades": nouveaux_malades,
		"gueris": gueris,
		"morts": morts,
		"compteur_dechet": compteur_dechet,
	}

# Le Monde RECONSTRUIT DU NEANT sans les dechets (monde.gd n'a aucune fonction
# de retrait, CARTE.md §6 -- meme idiome que banc_occlusion.gd:monde_du_tick).
# Les choses conservees y sont RE-AJOUTEES PAR REFERENCE : l'etat interne des
# colons traverse le nettoyage intact.
static func monde_sans_dechets(monde, type_dechet: String):
	var restantes: Array = []
	for entree in monde.choses.values():
		if entree.type != type_dechet:
			restantes.append(entree)
	return BancCommun.monde_depuis([{"entrees": restantes}])

# Deplacement aleatoire SEEDE, recopie de banc_maladie.gd:deplacer_colons (deux
# bancs ne se referencent jamais entre eux). Un colon dont la vitesse EFFECTIVE
# est nulle (mort) ne bouge plus et ne tire plus de destination.
static func deplacer_colons(colons: Array, zone: Dictionary, etats: Dictionary, rng: RandomNumberGenerator, delta: float) -> void:
	for colon in colons:
		var vitesse_effective: float = EtatEffectif.valeur(colon, PROPRIETE_VITESSE, etats)
		if vitesse_effective <= 0.0:
			continue
		if colon.position.distance_to(colon.destination) <= DISTANCE_ARRIVEE:
			colon.destination = _destination_aleatoire(zone, rng)
		colon.position = BancCommun.bouger_vers(colon.position, colon.destination, vitesse_effective, delta)

static func _destination_aleatoire(zone: Dictionary, rng: RandomNumberGenerator) -> Vector3:
	var mini: Array = zone["min"]
	var maxi: Array = zone["max"]
	return Vector3(
		rng.randf_range(mini[0], maxi[0]),
		rng.randf_range(mini[1], maxi[1]),
		0.0,
	)

# Etat courant d'un colon pour l'affichage/couleur, PUR -- un seul nom a la
# fois, priorite mort > malade > incubation > expose > sain. Un colon mort
# reste aussi 'malade' dans etats_actifs (data/etats.json:mort_maladie), et un
# colon malade peut encore porter le marqueur 'expose_salete' : la priorite
# tranche, ce fichier ne hierarchise jamais les etats ailleurs qu'ici.
static func etat_courant(colon: Dictionary) -> String:
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	if actifs.has(ETAT_MORT):
		return "mort"
	if actifs.has(ETAT_MALADE):
		return "malade"
	if actifs.has(ETAT_INCUBATION):
		return "incubation"
	if colon.proprietes.get(MARQUEUR_SALETE, false):
		return "expose"
	return "sain"

static func compter_etats(colons: Array) -> Dictionary:
	var compte := {"sain": 0, "expose": 0, "incubation": 0, "malade": 0, "mort": 0}
	for colon in colons:
		var e := etat_courant(colon)
		compte[e] = compte.get(e, 0) + 1
	return compte

static func charge_salete(colon: Dictionary) -> float:
	return float(colon.proprietes.get("etats", {}).get("salete", {}).get("charge", 0.0))

static func _texte_label(colon: Dictionary, etats: Dictionary) -> String:
	return "%s\netat=%s\nurgence=%.1f\nsalete=%.2f\nvitesse=%.1f" % [
		colon.id,
		etat_courant(colon),
		float(colon.proprietes.get(PROPRIETE_MIROIR, 0.0)),
		charge_salete(colon),
		EtatEffectif.valeur(colon, PROPRIETE_VITESSE, etats),
	]

static func _texte_compteur(compte: Dictionary, dechets: int) -> String:
	return "dechets au sol=%d   sains=%d  exposes=%d  incubation=%d  malades=%d  morts=%d" % [
		dechets, compte.sain, compte.expose, compte.incubation, compte.malade, compte.mort
	]

static func _ligne_dechet(t: float, colon_id: String, dechet_id: String) -> String:
	return "t=%.1fs %s : elimine -- %s au sol" % [t, colon_id, dechet_id]

static func _ligne_expose(t: float, id: String) -> String:
	return "t=%.1fs %s : EXPOSE a la salete (seuil du canal franchi)" % [t, id]

static func _ligne_symptomes(t: float, id: String) -> String:
	return "t=%.1fs %s : symptomes (fin d'incubation, vitesse reduite)" % [t, id]

static func _ligne_gueri(t: float, id: String) -> String:
	return "t=%.1fs %s : gueri" % [t, id]

static func _ligne_mort(t: float, id: String) -> String:
	return "t=%.1fs %s : MORT" % [t, id]

static func _ligne_nettoyage(t: float, retires: int) -> String:
	return "t=%.1fs NETTOYAGE : %d dechet(s) retire(s) du monde" % [t, retires]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction des
# noeuds et la couleur qui traduit l'etat.

func _couleur_pour(colon: Dictionary) -> Color:
	var rgb: Array = _config.couleurs.get(etat_courant(colon), [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _creer_rendu_colon(colon: Dictionary) -> void:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(TAILLE_COLON, TAILLE_COLON)
	add_child(carre)
	_noeuds[colon.id] = carre

	var label := Label.new()
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	_labels[colon.id] = label

func _creer_rendu_dechet(id: String) -> void:
	var rgb: Array = _config.couleur_dechet
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(TAILLE_DECHET, TAILLE_DECHET)
	carre.color = Color(rgb[0], rgb[1], rgb[2])
	add_child(carre)
	_noeuds_dechet[id] = carre

func _rafraichir_tout() -> void:
	for colon in _colons:
		var carre: ColorRect = _noeuds[colon.id]
		carre.color = _couleur_pour(colon)
		carre.position = Vector2(colon.position.x, colon.position.y) - carre.size / 2.0
		var label: Label = _labels[colon.id]
		label.position = carre.position - Vector2(10.0, 70.0)
		label.text = _texte_label(colon, _etats)

	var dechets := dechets_du_monde(_monde, _config.type_dechet)
	for dechet in dechets:
		if not _noeuds_dechet.has(dechet.id):
			continue
		var carre: ColorRect = _noeuds_dechet[dechet.id]
		carre.position = Vector2(dechet.position.x, dechet.position.y) - carre.size / 2.0
	_label_compteur.text = _texte_compteur(compter_etats(_colons), dechets.size())

func _poser_camera() -> void:
	var zone: Dictionary = _config.zone
	var mini: Array = zone["min"]
	var maxi: Array = zone["max"]
	var camera := Camera2D.new()
	camera.position = Vector2((mini[0] + maxi[0]) / 2.0, (mini[1] + maxi[1]) / 2.0)
	camera.zoom = Vector2(0.75, 0.75)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
