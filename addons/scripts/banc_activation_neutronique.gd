extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_activation_neutronique.tscn, PAS
# la scene principale -- run/main_scene reste banc_p1). Chantier « activation
# neutronique -- objet irradie devient source secondaire ». AUCUN MECANISME
# DU COEUR TOUCHE : charge.gd/depense.gd/seuil_etat.gd/combustible.gd/
# perception.gd/etat_duree.gd/etat_effectif.gd/epigenetique.gd/objet.gd
# restent EXACTEMENT ceux deja verrouilles par leurs propres tests.
#
# LA CHAINE : source primaire -> irradie les objets (canal "radiation",
# scripts/charge.gd, MEME mecanisme que scripts/banc_radiation.gd) -> chaque
# objet accumule "dose_radiation_objet" (le MAXIMUM jamais atteint par sa
# charge, jamais un miroir direct -- voir plus bas, DECISION YAEL) -> au
# seuil fixe 30.0 (data/seuils_etat.json:activation_neutronique),
# scripts/seuil_etat.gd pose "active_neutronique" (etat IRREVERSIBLE, une
# cicatrice) -> le cablage detecte ce premier franchissement et pose A LA
# MAIN, UNE SEULE FOIS, un "force_radiation" et une reserve
# "radioactivite_acquise" sur l'objet (patron
# scripts/banc_radiation.gd:fabriquer_source / scripts/
# banc_produit_nucleaire.gd:avancer_source, memes gestes) -- l'objet devient
# source secondaire du canal "radiation" -> scripts/depense.gd consomme
# "radioactivite_acquise" chaque tick, scripts/combustible.gd:restant en
# derive la proportion restante, "force_radiation" la suit exactement
# (memes gestes que force_radiation_actuelle dans banc_produit_nucleaire.gd)
# -> le colon, qui ne percoit JAMAIS la source primaire directement (aucun
# appel de perception ne l'interroge -- protection par CONSTRUCTION, pas par
# un filtre ajoute), percoit les objets actives via une seule requete
# scripts/perception.gd sur un Monde qui les contient tous -- MEME canal
# "radiation", MEME propriete d'emission "force_radiation", rien de neuf cote
# perception.gd. Une fois expose, le colon subit EXACTEMENT le meme escalier
# que scripts/banc_produit_nucleaire.gd : nausee_radiation (reversible,
# etat_duree.gd), une marque epigenetique (epigenetique.gd), et
# syndrome_radiation/mort_radiation (irreversibles, scripts/seuil_etat.gd sur
# "dose_radiation_cumulee", catalogue PARTAGE reutilise tel quel depuis
# data/seuils_etat.json -- aucune nouvelle entree, aucune collision).
#
# DECISION YAEL (question posee avant d'ecrire, consigne d'origine ambigue) :
# "dose_radiation_objet" n'est PAS un miroir direct de
# proprietes.etats.radiation.charge (scripts/charge.gd) -- charge.gd est
# REVERSIBLE par construction, sa charge redescend d'elle-meme
# (taux_decroissance) des qu'aucune cause n'est plus a portee. Un miroir
# direct aurait donc rendu "active_neutronique" REVERSIBLE (retire par
# scripts/seuil_etat.gd des que la charge retombe sous 30.0), en
# contradiction avec le role de CICATRICE PERMANENTE voulu -- le meme statut
# que fracture/rompu/corrode_acide/syndrome_radiation dans ce depot, tous
# poses sur une grandeur qui ne redescend JAMAIS. "dose_radiation_objet" suit
# donc le MAXIMUM jamais atteint par la charge -- meme geste que
# scripts/banc_rigidite.gd (fleche maximale atteinte, "meme principe que
# degats_impact_cumules"), pas un simple miroir.
#
# POURQUOI LA SOURCE PRIMAIRE EST HAND-BUILT, SANS RESERVE : un point
# d'emission n'a besoin d'aucune matiere physique (meme raison que
# scripts/banc_radiation.gd:fabriquer_source). Contrairement a
# scripts/banc_produit_nucleaire.gd, cette source NE S'EPUISE PAS
# elle-meme -- elle est retiree/remise a la main par un clic (bistable),
# la tache ne demande pas de depletion progressive pour la source primaire.
#
# GEOMETRIE (voir data/banc_activation_neutronique.json._note pour le detail
# chiffre) : bois_active/pierre_active/fer_active a portee de la source
# primaire (~210-280 unites) ; colon_active a 600 unites de la source
# (hors de portee_perception_primaire 500.0 -- protege PAR CONSTRUCTION,
# aucune requete de perception ne teste jamais colon<->source) mais a
# 320-405 unites des trois objets (a portee_perception_secondaire 500.0).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et fabrique source/objets/colon.
#   _unhandled_input bascule la source primaire au clic gauche. _process
#   appelle UNIQUEMENT avancer() (fonction statique, ci-dessous) puis lit ses
#   resultats pour l'affichage/la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_activation_neutronique.gd) : perceoit_source_primaire/
#   monde_source/monde_objets/avancer_objets/avancer_colon/avancer/
#   activer_source_secondaire/fabriquer_*/diagnostiquer_*, plus le texte
#   d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const Perception = preload("res://scripts/perception.gd")
const Charge = preload("res://scripts/charge.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Depense = preload("res://scripts/depense.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Epigenetique = preload("res://scripts/epigenetique.gd")
const Combustible = preload("res://scripts/combustible.gd")

const TAILLE := 70.0
const TAILLE_SOURCE := 34.0
const TAILLE_COLON := 40.0
const PROPRIETE_SENSIBILITE := "sensibilite_radiation"
const PROPRIETE_FORCE := "force_radiation"
const PROPRIETE_DOSE_OBJET := "dose_radiation_objet"
const NOM_CANAL_RADIATION := "radiation"
const NOM_ETAT_ACTIVATION := "active_neutronique"
const NOM_RESERVE_ACQUISE := "radioactivite_acquise"

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _seuils_etat: Dictionary = {}
var _epigenetique: Dictionary = {}
var _catalogue_canaux: Dictionary = {}

var _source: Dictionary = {}
var _objets: Array = []
var _colon: Dictionary = {}
var _source_active: bool = true

var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_source: ColorRect
var _label_source: Label
var _noeud_colon: ColorRect
var _label_colon: Label
var _actif_avant: Dictionary = {}
var _etat_colon_avant: String = "sain"
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_activation_neutronique.json")
	_etats = _charger_json("res://data/etats.json")
	_seuils_etat = _charger_json("res://data/seuils_etat.json")
	_epigenetique = _charger_json("res://data/epigenetique.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	var table_types: Dictionary = _charger_json("res://data/types.json")
	var materiaux: Dictionary = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	_source = fabriquer_source(_config.source)
	_objets = fabriquer_objets(_config.objets, materiaux, proprietes_immuables, _config)
	var pos_colon: Array = _config.colon.position
	_colon = fabriquer_colon(_config.colon.id, Vector3(pos_colon[0], pos_colon[1], pos_colon[2]), table_types, _config)

	for objet in _objets:
		_actif_avant[objet.id] = false
		_creer_rendu_objet(objet)
	_creer_rendu_source()
	_creer_rendu_colon()
	_poser_camera()

	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_source_active = not _source_active
		print(_ligne_toggle(_temps, _source_active))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var resultat := avancer(_source, _source_active, _objets, _colon, delta, _config, _etats, _seuils_etat, _epigenetique, _catalogue_canaux)

	for objet in _objets:
		var id: String = objet.id
		var actif: bool = objet.proprietes.get("etats_actifs", []).has(NOM_ETAT_ACTIVATION)
		if actif != _actif_avant.get(id, false):
			print(_ligne_activation(_temps, id, objet.proprietes.get(PROPRIETE_DOSE_OBJET, 0.0)))
			_actif_avant[id] = actif

	var etat_colon: String = diagnostiquer_colon(_colon, _etats, _config).etat
	if etat_colon != _etat_colon_avant:
		print(_ligne_etat_colon(_temps, etat_colon))
		_etat_colon_avant = etat_colon

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var diag := diagnostiquer_objet(objet, _etats, _config)
		_noeuds[id].color = Color(0.85, 0.55, 0.15) if diag.active else Color(0.5, 0.5, 0.55)
		_labels[id].text = _texte_label_objet(id, diag)

	_noeud_source.visible = _source_active
	_label_source.text = _texte_label_source(_source, _source_active)

	var diag_colon := diagnostiquer_colon(_colon, _etats, _config)
	_noeud_colon.color = _couleur_colon(diag_colon.etat)
	_label_colon.text = _texte_label_colon(diag_colon)

func _charger_json(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

# ---- Fonctions PURES, testables headless (voir test_banc_activation_neutronique.gd) ----

# La source primaire n'entre dans le Monde du tick QUE si source_active est
# vrai -- meme idiome que banc_radiation.gd:monde_pour_objet.
static func monde_source(source: Dictionary, source_active: bool) -> Monde:
	var presentes: Array = [source] if source_active else []
	return BancCommun.monde_depuis([{"choses": presentes, "type": "source_radioactive"}])

# La source primaire est-elle visible pour CET objet ? Construit une entite
# de perception MINIMALE (canal "radiation" seul), delegue entierement a
# Perception.percevoir -- meme patron que banc_radiation.gd:perceoit_source.
static func perceoit_source_primaire(id_objet: String, position_objet: Vector3, source: Dictionary, source_active: bool, portee: float, seuil: float, catalogue_canaux: Dictionary) -> bool:
	var monde := monde_source(source, source_active)
	var entite := {
		"id": id_objet,
		"position": position_objet,
		"proprietes": {
			"canaux": [NOM_CANAL_RADIATION],
			"canaux_config": { NOM_CANAL_RADIATION: { "portee": portee, "seuil": seuil } },
		},
	}
	var perceptions: Array = Perception.percevoir(entite, monde, catalogue_canaux)
	for entree in perceptions:
		if entree.chose.id == source.id and NOM_CANAL_RADIATION in entree.canaux:
			return true
	return false

# Le Monde des objets, pour la perception du colon -- TOUS les objets y
# entrent, actives ou non (un objet non active porte force_radiation=0.0,
# scripts/perception.gd le filtre lui-meme via son propre "seuil", jamais un
# filtre ajoute ici -- perception reste aveugle/exhaustive, seule la donnee
# decide).
static func monde_objets(objets: Array) -> Monde:
	return BancCommun.monde_depuis([{"choses": objets, "type": "objet_irradie"}])

# Pose A LA MAIN, UNE SEULE FOIS par objet, la reserve "radioactivite_acquise"
# -- patron scripts/banc_radiation.gd:fabriquer_source / scripts/
# banc_produit_nucleaire.gd:avancer_source (source hand-built, aucune
# composition necessaire pour un point d'emission). Le "force_radiation" de
# l'objet est recalcule juste APRES par l'appelant (avancer_objets) depuis la
# proportion restante de cette reserve -- jamais pose ici directement, pour
# ne suivre qu'UNE SEULE formule (scripts/combustible.gd:restant).
static func activer_source_secondaire(objet: Dictionary, config: Dictionary) -> void:
	var reserves: Dictionary = objet.proprietes.get("reserves", {})
	reserves[NOM_RESERVE_ACQUISE] = config.reserve_acquise_defaut.duplicate(true)
	objet.proprietes["reserves"] = reserves

# UN PAS sur les trois objets cibles : (1) perception decide si la source
# primaire est visible, une cause ponderee (force_radiation source *
# sensibilite_radiation EFFECTIVE de l'objet, scripts/etat_effectif.gd:valeur,
# jamais reimplementee) alimente Charge.avancer -- MEME idiome que
# scripts/banc_radiation.gd:avancer. (2) "dose_radiation_objet" suit le
# MAXIMUM jamais atteint par la charge de ce canal -- voir DECISION YAEL en
# tete de fichier. (3) SeuilEtat.avancer pose "active_neutronique" au
# franchissement (permanent, la propriete comparee ne redescend jamais).
# (4) Depense.avancer decremente les reserves "radioactivite_acquise" DEJA
# existantes (objets actives lors d'un tick precedent -- une reserve neuve
# n'est jamais decrementee le tick meme de sa creation, meme ordre que
# banc_produit_nucleaire.gd:avancer_source). (5) tout objet fraichement
# actif ce tick (et pas encore muni de sa reserve) la recoit, pleine.
# (6) "force_radiation" de CHAQUE objet muni de la reserve suit exactement
# force_radiation_secondaire_base * Combustible.restant(...).proportion --
# 0.0 des que la reserve est epuisee. Rend { bascules_activation,
# franchis_reserve }.
static func avancer_objets(objets: Array, source: Dictionary, source_active: bool, delta: float, config: Dictionary, etats: Dictionary, seuils_etat: Dictionary, catalogue_canaux: Dictionary) -> Dictionary:
	var portee: float = config.portee_perception_primaire
	var seuil_perception: float = config.seuil_perception_primaire
	var force_source: float = source.proprietes.get(PROPRIETE_FORCE, 0.0)

	for objet in objets:
		var causes: Array = []
		if perceoit_source_primaire(objet.id, objet.position, source, source_active, portee, seuil_perception, catalogue_canaux):
			var sensibilite: float = EtatEffectif.valeur(objet, PROPRIETE_SENSIBILITE, etats)
			if sensibilite > 0.0:
				causes.append({"position": source.position, "poids": force_source * sensibilite})
		Charge.avancer([objet], causes, delta)
		var charge_courante: float = objet.proprietes.get("etats", {}).get(NOM_CANAL_RADIATION, {}).get("charge", 0.0)
		objet.proprietes[PROPRIETE_DOSE_OBJET] = max(objet.proprietes.get(PROPRIETE_DOSE_OBJET, 0.0), charge_courante)

	var bascules_activation := SeuilEtat.avancer(objets, seuils_etat)

	var franchis_reserve := Depense.avancer(objets, delta)

	for objet in objets:
		var actifs: Array = objet.proprietes.get("etats_actifs", [])
		var reserves: Dictionary = objet.proprietes.get("reserves", {})
		if actifs.has(NOM_ETAT_ACTIVATION) and not reserves.has(NOM_RESERVE_ACQUISE):
			activer_source_secondaire(objet, config)

	for objet in objets:
		var reserves2: Dictionary = objet.proprietes.get("reserves", {})
		if reserves2.has(NOM_RESERVE_ACQUISE):
			objet.proprietes[PROPRIETE_FORCE] = config.force_radiation_secondaire_base * Combustible.restant(objet, NOM_RESERVE_ACQUISE).proportion

	return { "bascules_activation": bascules_activation, "franchis_reserve": franchis_reserve }

# UN PAS sur le colon : (1) une SEULE requete Perception.percevoir sur le
# Monde de TOUS les objets rend les causes (position + force_radiation de
# chaque objet REELLEMENT percu -- la source primaire n'apparait JAMAIS dans
# ce Monde, protection PAR CONSTRUCTION). (2) Charge.avancer met a jour les
# DEUX canaux du colon (exposition_radioactive/nausee_radiation) avec les
# MEMES causes -- MEME geste que scripts/banc_produit_nucleaire.gd:
# avancer_colon, recopie ici (deux bancs jetables ne se referencent jamais
# entre eux). (3)-(6) reprennent EXACTEMENT ce meme fichier patron : marque
# epigenetique tant qu'expose, nausee_radiation reversible tant qu'expose,
# dose_radiation_cumulee qui ne redescend jamais, SeuilEtat.avancer pose
# syndrome_radiation/mort_radiation (catalogue PARTAGE, aucune nouvelle
# entree). Rend { visible, bascules_charge, expirees_nausee, bascules_seuil }.
static func avancer_colon(colon: Dictionary, objets: Array, delta: float, config: Dictionary, etats: Dictionary, seuils_etat: Dictionary, catalogue_epigenetique: Dictionary, catalogue_canaux: Dictionary) -> Dictionary:
	var portee: float = config.portee_perception_secondaire
	var seuil_perception: float = config.seuil_perception_secondaire
	var monde := monde_objets(objets)
	var entite := {
		"id": colon.id,
		"position": colon.position,
		"proprietes": {
			"canaux": [NOM_CANAL_RADIATION],
			"canaux_config": { NOM_CANAL_RADIATION: { "portee": portee, "seuil": seuil_perception } },
		},
	}
	var perceptions: Array = Perception.percevoir(entite, monde, catalogue_canaux)
	var causes: Array = []
	for entree in perceptions:
		causes.append({"position": entree.position, "poids": entree.chose.proprietes.get(PROPRIETE_FORCE, 0.0)})
	var visible := not causes.is_empty()

	var bascules_charge := Charge.avancer([colon], causes, delta)

	if colon.proprietes.get(config.declencheur_mutation, false):
		Epigenetique.poser(colon, config.nom_marque_epigenetique, catalogue_epigenetique)
	Epigenetique.avancer(colon, delta, catalogue_epigenetique)

	if colon.proprietes.get(config.declencheur_nausee, false):
		EtatDuree.poser(colon, config.nom_etat_nausee, etats)
	var expirees_nausee := EtatDuree.avancer([colon], delta, etats)

	if visible:
		colon.proprietes["dose_radiation_cumulee"] = colon.proprietes.get("dose_radiation_cumulee", 0.0) + config.dose_par_s * delta

	var bascules_seuil := SeuilEtat.avancer([colon], seuils_etat)

	return {
		"visible": visible,
		"bascules_charge": bascules_charge,
		"expirees_nausee": expirees_nausee,
		"bascules_seuil": bascules_seuil,
	}

# MORT -- meme decision Yael que banc_produit_nucleaire.gd (figer, jamais un
# retrait du monde). Une fois "mort_radiation" actif, plus aucun mecanisme de
# ce banc ne met a jour le colon.
static func colon_fige(colon: Dictionary) -> bool:
	return colon.proprietes.get("etats_actifs", []).has("mort_radiation")

# UN PAS de simulation complet, composant les deux effets. Rend
# { bascules_activation, franchis_reserve, visible_colon, bascules_charge_colon,
# bascules_seuil_colon, colon_fige }.
static func avancer(source: Dictionary, source_active: bool, objets: Array, colon: Dictionary, delta: float, config: Dictionary, etats: Dictionary, seuils_etat: Dictionary, catalogue_epigenetique: Dictionary, catalogue_canaux: Dictionary) -> Dictionary:
	var resultat_objets := avancer_objets(objets, source, source_active, delta, config, etats, seuils_etat, catalogue_canaux)

	var fige: bool = colon_fige(colon)
	var resultat_colon: Dictionary
	if fige:
		resultat_colon = { "visible": false, "bascules_charge": [], "expirees_nausee": [], "bascules_seuil": [] }
	else:
		resultat_colon = avancer_colon(colon, objets, delta, config, etats, seuils_etat, catalogue_epigenetique, catalogue_canaux)

	return {
		"bascules_activation": resultat_objets.bascules_activation,
		"franchis_reserve": resultat_objets.franchis_reserve,
		"visible_colon": resultat_colon.visible,
		"bascules_charge_colon": resultat_colon.bascules_charge,
		"bascules_seuil_colon": resultat_colon.bascules_seuil,
		"colon_fige": fige,
	}

# Hand-built, AUCUNE composition -- voir en-tete du fichier. SANS reserve :
# la source primaire ne s'epuise jamais d'elle-meme, elle est seulement
# retiree/remise par le clic.
static func fabriquer_source(decl: Dictionary) -> Dictionary:
	var pos: Array = decl.position
	return {
		"id": decl.id,
		"position": Vector3(pos[0], pos[1], pos[2]),
		"proprietes": { PROPRIETE_FORCE: decl.get("force_radiation", 0.0) },
	}

# Construit les trois objets cibles via Objet.fabriquer (composition
# fusionnee -- "sensibilite_radiation" deja dans data/proprietes_immuables_
# composition.json). Chaque objet recoit ENSUITE son propre canal de charge,
# "dose_radiation_objet" et "force_radiation" a 0.0, "reserves" vide (aucune
# reserve "radioactivite_acquise" avant activation) -- meme patron que
# scripts/banc_radiation.gd:fabriquer_objets.
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array, config: Dictionary) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet.proprietes["etats"] = {config.nom_canal_radiation: config.canal_radiation_defaut.duplicate(true)}
		objet.proprietes["etats_actifs"] = []
		objet.proprietes["reserves"] = {}
		objet.proprietes[PROPRIETE_DOSE_OBJET] = 0.0
		objet.proprietes[PROPRIETE_FORCE] = 0.0
		objets.append(objet)
	return objets

# Construit le colon via Objet.fabriquer(type "colon"), table_types etant
# data/types.json ENTIER -- meme patron que
# scripts/banc_produit_nucleaire.gd:fabriquer_colon. Ce fichier AJOUTE
# seulement les deux canaux NEUFS a "etats" (Dictionary deja present, fusionne
# dedans, jamais ecrase) et "dose_radiation_cumulee" (0.0).
static func fabriquer_colon(id: String, position: Vector3, table_types: Dictionary, config: Dictionary) -> Dictionary:
	var colon := Objet.fabriquer(id, "colon", position, table_types)
	if colon.is_empty():
		return colon
	var etats: Dictionary = colon.proprietes.get("etats", {})
	etats[config.nom_canal_mutation] = config.canal_mutation_defaut.duplicate(true)
	etats[config.nom_canal_nausee] = config.canal_nausee_defaut.duplicate(true)
	colon.proprietes["etats"] = etats
	colon.proprietes["dose_radiation_cumulee"] = 0.0
	return colon

# Diagnostic d'affichage d'un objet cible, PUR : lit uniquement des valeurs
# deja calculees ailleurs, ne reimplemente jamais leur loi.
static func diagnostiquer_objet(objet: Dictionary, etats: Dictionary, config: Dictionary) -> Dictionary:
	var reserves: Dictionary = objet.proprietes.get("reserves", {})
	var restant: Dictionary = Combustible.restant(objet, NOM_RESERVE_ACQUISE) if reserves.has(NOM_RESERVE_ACQUISE) else {"absolu": 0.0, "proportion": 0.0}
	return {
		"dose": objet.proprietes.get(PROPRIETE_DOSE_OBJET, 0.0),
		"active": objet.proprietes.get("etats_actifs", []).has(NOM_ETAT_ACTIVATION),
		"force_radiation": objet.proprietes.get(PROPRIETE_FORCE, 0.0),
		"reserve_acquise": restant.absolu,
	}

# Diagnostic d'affichage du colon, PUR -- meme patron que
# scripts/banc_produit_nucleaire.gd:diagnostiquer_colon (sans le volet
# epigenetique, non demande par la tache pour ce banc).
static func diagnostiquer_colon(colon: Dictionary, etats: Dictionary, config: Dictionary) -> Dictionary:
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	var etat := "sain"
	if actifs.has("mort_radiation"):
		etat = "mort"
	elif actifs.has("syndrome_radiation"):
		etat = "syndrome"
	elif actifs.has(config.nom_etat_nausee):
		etat = "nausee"
	return {
		"etat": etat,
		"dose": colon.proprietes.get("dose_radiation_cumulee", 0.0),
		"vitesse_effective": EtatEffectif.valeur(colon, "vitesse", etats),
	}

static func _couleur_colon(etat: String) -> Color:
	match etat:
		"mort":
			return Color(0.15, 0.15, 0.15)
		"syndrome":
			return Color(0.6, 0.3, 0.7)
		"nausee":
			return Color(0.7, 0.6, 0.2)
		_:
			return Color(0.3, 0.55, 0.35)

static func _texte_label_objet(id: String, diag: Dictionary) -> String:
	return "%s\ndose_radiation_objet=%.2f\nactive_neutronique=%s\nforce_radiation=%.3f\nradioactivite_acquise=%.2f" % [
		id, diag.dose, diag.active, diag.force_radiation, diag.reserve_acquise
	]

static func _texte_label_source(source: Dictionary, source_active: bool) -> String:
	return "%s\nforce_radiation=%.2f\nactive=%s" % [source.id, source.proprietes.get(PROPRIETE_FORCE, 0.0), source_active]

static func _texte_label_colon(diag: Dictionary) -> String:
	return "colon_active\ndose_radiation_cumulee=%.2f\netat=%s\nvitesse_effective=%.1f" % [
		diag.dose, diag.etat, diag.vitesse_effective
	]

static func _ligne_toggle(t: float, source_active: bool) -> String:
	return "t=%.1fs SOURCE PRIMAIRE : %s" % [t, "presente" if source_active else "retiree"]

static func _ligne_activation(t: float, id: String, dose: float) -> String:
	return "t=%.1fs %s : active_neutronique POSE (dose_radiation_objet=%.2f), devient source secondaire" % [t, id, dose]

static func _ligne_etat_colon(t: float, etat: String) -> String:
	return "t=%.1fs colon_active : etat -> %s" % [t, etat]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction des
# noeuds et de la camera.

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id
	var centre := Vector2(objet.position.x, objet.position.y)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 100.0)
	add_child(label)
	_labels[id] = label

func _creer_rendu_source() -> void:
	var centre := Vector2(_source.position.x, _source.position.y)
	_noeud_source = ColorRect.new()
	_noeud_source.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_source.color = Color(0.95, 0.6, 0.1)
	_noeud_source.size = Vector2(TAILLE_SOURCE, TAILLE_SOURCE)
	_noeud_source.position = centre - _noeud_source.size / 2.0
	add_child(_noeud_source)

	_label_source = Label.new()
	_label_source.position = _noeud_source.position - Vector2(20.0, 60.0)
	add_child(_label_source)

func _creer_rendu_colon() -> void:
	var centre := Vector2(_colon.position.x, _colon.position.y)
	_noeud_colon = ColorRect.new()
	_noeud_colon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_colon.size = Vector2(TAILLE_COLON, TAILLE_COLON)
	_noeud_colon.position = centre - _noeud_colon.size / 2.0
	add_child(_noeud_colon)

	_label_colon = Label.new()
	_label_colon.position = _noeud_colon.position - Vector2(20.0, 90.0)
	add_child(_label_colon)

func _poser_camera() -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(_source.position.x + 300.0, _source.position.y)
	camera.zoom = Vector2(0.35, 0.35)
	camera.enabled = true
	add_child(camera)
