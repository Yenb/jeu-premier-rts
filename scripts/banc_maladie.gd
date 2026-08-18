extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_maladie.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « maladie par
# contact -- contagion, incubation, mort ». Compose QUATRE patrons deja
# fermes, jamais reecrits : scripts/charge.gd (contagion -- calque sur
# scripts/banc_contagion.gd:causes_de_attache, filtre par propriete
# numerique 'porteur' plutot que par attache), scripts/etat_duree.gd
# (incubation qui expire seule, meme patron que 'irradie'/'empoisonne'),
# scripts/etat_effectif.gd (symptomes -- vitesse modulee par 'malade',
# ecrasee par 'mort_maladie'), scripts/seuil_etat.gd (mort -- meme patron
# que 'syndrome_radiation'/'mort_radiation', propriete_continue cumulee
# par ce cablage). AUCUN MECANISME DU COEUR TOUCHE.
#
# COLONS CONSTRUITS A LA MAIN (pas Objet.fabriquer, pas data/types.json --
# demonstration de cablage, pas integration au jeu, meme statut que
# scripts/banc_contagion.gd/scripts/banc_toxicite.gd).
#
# LA CHAINE DE CONTAGION, EN UN SEUL PASSAGE :
# 1) causes_de_porteurs(...) scanne tous les colons, retient une cause
#    { position } par colon dont proprietes.porteur > 0.0 -- comptage
#    IMPLICITE (charge.gd somme deja les causes a portee), jamais
#    Comptage.compter (meme decision que banc_contagion.gd).
# 2) Charge.avancer(...) recoit ces causes. SEULS les colons pas encore
#    infectes portent encore un canal proprietes.etats.maladie (le patient
#    zero n'en a jamais eu, un colon fraichement infecte se le fait
#    RETIRER immediatement, voir 3 -- consequence : un colon ne peut
#    JAMAIS etre traite deux fois par charge.gd, la liste des bascules
#    qu'il rend est donc TOUJOURS une liste de contaminations FRAICHES,
#    jamais besoin de comparer a un etat 'avant' comme banc_toxicite.gd
#    le fait). Au franchissement, charge.gd pose un simple marqueur
#    booleen (expose_maladie, jamais 'porteur'/'incube_maladie'
#    directement -- charge.gd ne connait aucun des deux).
# 3) Ce cablage, pour chaque id bascule : pose proprietes.porteur = 1.0
#    (le colon devient contagieux DES CET INSTANT, avant meme les
#    symptomes), EtatDuree.poser(colon, "incube_maladie", etats) (la
#    duree vit dans data/etats.json, PAS ici), et RETIRE
#    proprietes.etats (le colon sort du pool des receveurs pour toujours
#    -- porteur ou mort, il ne redevient jamais susceptible).
# 4) EtatDuree.avancer(...) fait decroitre l'intensite de 'incube_maladie'
#    puis 'malade' ; leurs expirations (Array { id, nom_etat }) sont LUES
#    par ce cablage, jamais recalculees : une expiration de
#    'incube_maladie' pose 'malade' (symptomes -- vitesse moduleee des
#    cet instant, EtatDuree/EtatEffectif inchanges) ; une expiration de
#    'malade' SANS mort prealable est une GUERISON -- proprietes.porteur
#    remis a 0.0 (plus contagieux). Sous la calibration reelle de ce banc
#    (data/banc_maladie.json : seuil_mort < maladie_duree_s), la guerison
#    n'est JAMAIS observee en direct -- elle reste prouvee par
#    scripts/test_banc_maladie.gd seul, meme statut que la reversibilite
#    de charge.gd dans banc_contagion.gd.
# 5) Tant que 'malade' est actif, ce cablage accumule lui-meme
#    proprietes.duree_maladie_cumulee (delta-scale, ne redescend jamais --
#    meme idiome que force_traction_cumulee/exposition_acide_cumulee).
# 6) SeuilEtat.avancer(...) (catalogue PARTAGE data/seuils_etat.json passe
#    TEL QUEL, seule l'entree 'mort_par_maladie' se declenche jamais ici)
#    compare cette grandeur au seuil et pose 'mort_maladie' -- ce cablage
#    remet alors proprietes.porteur a 0.0 (un colon mort ne contamine
#    plus, point 6 des issues verifiables).
#
# DEPLACEMENT ALEATOIRE, RNG SEEDE (CLAUDE.md, aucun hasard non-seede) :
# chaque colon vivant (vitesse EFFECTIVE > 0.0, EtatEffectif.valeur,
# jamais reimplementee) marche vers une destination aleatoire dans
# data/banc_maladie.json:zone ; a l'arrivee (BancCommun.bouger_vers, meme
# outil que tous les autres bancs), une nouvelle destination est tiree.
# Un colon mort (vitesse effective ecrasee a 0.0 par 'mort_maladie') ne
# tire plus jamais de destination -- immobile pour de bon, pas de RNG
# gaspille.
#
# TOGGLE : le clic gauche met en pause/reprend la simulation entiere
# (_en_pause, gate stricte en tete de _process) -- jamais d'infection
# manuelle, la propagation est entierement autonome.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge data/banc_maladie.json/data/etats.json/
#   data/seuils_etat.json, fabrique les colons, cree le rendu.
#   _unhandled_input bascule la pause. _process appelle avancer(...) puis
#   deplacer_colons(...), imprime les traces console, redessine.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_maladie.gd) : fabriquer_colons/causes_de_porteurs/avancer/
#   deplacer_colons/compter_etats/etat_courant, plus le texte d'affichage
#   et de log.

const Charge = preload("res://scripts/charge.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Portee = preload("res://scripts/portee.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const PROPRIETE_VITESSE := "vitesse"
const TAILLE := 26.0
const DISTANCE_ARRIVEE := 4.0
const TAILLE_POLICE_LABEL := 12

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _seuils_etat: Dictionary = {}
var _colons: Array = []
var _rng := RandomNumberGenerator.new()
var _en_pause := false
var _temps := 0.0
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _label_compteur: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_maladie.json")
	_etats = _charger_json("res://data/etats.json")
	_seuils_etat = _charger_json("res://data/seuils_etat.json")
	_rng.seed = int(_config.get("seed", 0))

	_colons = fabriquer_colons(_config, _etats)
	for colon in _colons:
		_creer_rendu_colon(colon)
	_label_compteur = Label.new()
	_label_compteur.position = Vector2(20.0, 10.0)
	add_child(_label_compteur)
	_poser_camera()
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_en_pause = not _en_pause
		print(_ligne_pause(_temps, _en_pause))

func _process(delta: float) -> void:
	if _en_pause:
		return
	_temps += delta

	var resultat := avancer(_colons, delta, _etats, _seuils_etat)
	deplacer_colons(_colons, _config.zone, _config.vitesse_base, _etats, _rng, delta)

	for entree in resultat.nouveaux_porteurs:
		print(_ligne_contamination(_temps, entree.id, entree.infecteur_id))
	for id in resultat.nouveaux_malades:
		print(_ligne_symptomes(_temps, id))
	for id in resultat.gueris:
		print(_ligne_gueri(_temps, id))
	for id in resultat.morts:
		print(_ligne_mort(_temps, id))

	_rafraichir_tout()

# ---- Fonctions PURES, testables headless (voir test_banc_maladie.gd) ----

# Construit les neuf colons de data/banc_maladie.json (ou toute config du
# meme format) : le patient zero demarre deja 'malade'/'porteur', aucune
# incubation ; les autres demarrent sains, avec un canal proprietes.etats.
# maladie STRUCTURELLEMENT present (canal_maladie, duplique par colon --
# jamais partage, voir banc_commun.gd:resoudre_chantier, bug d'aliasing
# deja corrige ailleurs). Chaque colon porte 'vitesse' (base, modulee/
# ecrasee ensuite par etat_effectif.gd) et 'duree_maladie_cumulee' (0.0,
# structurelle pour scripts/seuil_etat.gd des le depart).
static func fabriquer_colons(config: Dictionary, etats: Dictionary) -> Array:
	var colons: Array = []
	var vitesse_base: float = config.vitesse_base
	var patient_zero_id: String = config.patient_zero_id
	for decl in config.colons:
		var pos: Array = decl.position
		var position3 := Vector3(pos[0], pos[1], pos[2])
		var colon := {
			"id": decl.id,
			"position": position3,
			"destination": position3,
			"proprietes": {
				"vitesse": vitesse_base,
				"porteur": 0.0,
				"duree_maladie_cumulee": 0.0,
				"etats_actifs": [],
			},
		}
		if decl.id == patient_zero_id:
			colon.proprietes["porteur"] = 1.0
			EtatDuree.poser(colon, "malade", etats)
		else:
			colon.proprietes["etats"] = {"maladie": config.canal_maladie.duplicate(true)}
		colons.append(colon)
	return colons

# Une cause { position } par colon dont proprietes.porteur > 0.0 -- calque
# sur banc_contagion.gd:causes_de_attache, comptage IMPLICITE (charge.gd
# somme deja les causes a portee).
static func causes_de_porteurs(colons: Array) -> Array:
	var causes: Array = []
	for colon in colons:
		if colon.proprietes.get("porteur", 0.0) > 0.0:
			causes.append({"position": colon.position})
	return causes
static func _colon_par_id(colons: Array, id: String) -> Variant:
	for colon in colons:
		if colon.id == id:
			return colon
	return null

# Le porteur le plus proche du colon fraichement contamine, pour la trace
# console UNIQUEMENT (point 6 de la consigne : "quel colon, par qui") --
# n'affecte jamais la mecanique, charge.gd a deja somme toutes les causes
# a portee au moment du franchissement.
static func _infecteur_le_plus_proche(colon: Dictionary, colons: Array) -> String:
	var meilleur := ""
	var meilleure_d := INF
	for autre in colons:
		if autre.id == colon.id or autre.proprietes.get("porteur", 0.0) <= 0.0:
			continue
		var d: float = colon.position.distance_to(autre.position)
		if d < meilleure_d:
			meilleure_d = d
			meilleur = autre.id
	return meilleur

# UN PAS de simulation complet sur la contagion/incubation/mort (le
# deplacement est une fonction separee, voir deplacer_colons). Rend
# { nouveaux_porteurs: Array de {id, infecteur_id}, nouveaux_malades:
# Array d'id, gueris: Array d'id, morts: Array d'id } -- pour que
# l'appelant (le Node, ou un test) trace chaque transition sans jamais
# relire l'etat avant/apres lui-meme.
static func avancer(colons: Array, delta: float, etats: Dictionary, seuils_etat: Dictionary) -> Dictionary:
	var nouveaux_porteurs: Array = []
	var causes := causes_de_porteurs(colons)
	var bascules_charge := Charge.avancer(colons, causes, delta)
	for id in bascules_charge:
		var colon: Variant = _colon_par_id(colons, id)
		if colon == null or not colon.proprietes.get("expose_maladie", false):
			continue
		var infecteur := _infecteur_le_plus_proche(colon, colons)
		colon.proprietes["porteur"] = 1.0
		EtatDuree.poser(colon, "incube_maladie", etats)
		colon.proprietes.erase("etats")
		nouveaux_porteurs.append({"id": id, "infecteur_id": infecteur})

	var nouveaux_malades: Array = []
	var gueris: Array = []
	var expirees := EtatDuree.avancer(colons, delta, etats)
	for entree in expirees:
		var colon: Variant = _colon_par_id(colons, entree.id)
		if colon == null:
			continue
		if entree.nom_etat == "incube_maladie":
			EtatDuree.poser(colon, "malade", etats)
			nouveaux_malades.append(entree.id)
		elif entree.nom_etat == "malade":
			if not colon.proprietes.get("etats_actifs", []).has("mort_maladie"):
				colon.proprietes["porteur"] = 0.0
				gueris.append(entree.id)

	for colon in colons:
		if colon.proprietes.get("etats_actifs", []).has("malade"):
			colon.proprietes["duree_maladie_cumulee"] = colon.proprietes.get("duree_maladie_cumulee", 0.0) + delta

	var morts: Array = []
	var bascules_mort := SeuilEtat.avancer(colons, seuils_etat)
	for id in bascules_mort:
		var colon: Variant = _colon_par_id(colons, id)
		if colon == null or not colon.proprietes.get("etats_actifs", []).has("mort_maladie"):
			continue
		colon.proprietes["porteur"] = 0.0
		morts.append(id)

	return {
		"nouveaux_porteurs": nouveaux_porteurs,
		"nouveaux_malades": nouveaux_malades,
		"gueris": gueris,
		"morts": morts,
	}

# Deplacement aleatoire SEEDE (rng, jamais un hasard nu) : un colon dont la
# vitesse EFFECTIVE (EtatEffectif.valeur, jamais reimplementee) est nulle
# (mort) ne bouge jamais et ne tire plus de destination -- immobile pour de
# bon. Les autres marchent vers "destination" (BancCommun.bouger_vers,
# jamais reimplemente) ; une fois arrives (DISTANCE_ARRIVEE), une nouvelle
# destination aleatoire est tiree dans "zone". MUTE position/destination en
# place sur chaque colon.
static func deplacer_colons(colons: Array, zone: Dictionary, vitesse_base: float, etats: Dictionary, rng: RandomNumberGenerator, delta: float) -> void:
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
# fois, priorite mort > malade > incubation > sain (un colon mort reste
# aussi 'malade' dans etats_actifs, voir data/etats.json:mort_maladie).
static func etat_courant(colon: Dictionary) -> String:
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	if actifs.has("mort_maladie"):
		return "mort"
	if actifs.has("malade"):
		return "malade"
	if actifs.has("incube_maladie"):
		return "incubation"
	return "sain"

# Compte des quatre categories sur l'ensemble des colons, PUR.
static func compter_etats(colons: Array) -> Dictionary:
	var compte := {"sain": 0, "incubation": 0, "malade": 0, "mort": 0}
	for colon in colons:
		var e := etat_courant(colon)
		compte[e] = compte.get(e, 0) + 1
	return compte

static func _texte_label(colon: Dictionary, etats: Dictionary) -> String:
	var proprietes: Dictionary = colon.proprietes
	var charge: float = proprietes.get("etats", {}).get("maladie", {}).get("charge", 0.0)
	return "%s\netat=%s\nvitesse=%.1f\ncharge_maladie=%.2f\nporteur=%s" % [
		colon.id,
		etat_courant(colon),
		EtatEffectif.valeur(colon, PROPRIETE_VITESSE, etats),
		charge,
		"oui" if proprietes.get("porteur", 0.0) > 0.0 else "non",
	]

static func _texte_compteur(compte: Dictionary) -> String:
	return "sains=%d  incubation=%d  malades=%d  morts=%d" % [
		compte.sain, compte.incubation, compte.malade, compte.mort
	]

static func _ligne_pause(t: float, en_pause: bool) -> String:
	return "t=%.1fs SIMULATION : %s" % [t, "en pause" if en_pause else "reprise"]

static func _ligne_contamination(t: float, id: String, infecteur_id: String) -> String:
	if infecteur_id.is_empty():
		return "t=%.1fs %s : CONTAMINE" % [t, id]
	return "t=%.1fs %s : CONTAMINE par %s" % [t, id, infecteur_id]

static func _ligne_symptomes(t: float, id: String) -> String:
	return "t=%.1fs %s : symptomes (fin d'incubation, vitesse reduite)" % [t, id]

static func _ligne_gueri(t: float, id: String) -> String:
	return "t=%.1fs %s : gueri (n'est plus porteur)" % [t, id]

static func _ligne_mort(t: float, id: String) -> String:
	return "t=%.1fs %s : MORT" % [t, id]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la couleur qui traduit l'etat.

func _couleur_pour(colon: Dictionary) -> Color:
	var rgb: Array = _config.couleurs.get(etat_courant(colon), [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _creer_rendu_colon(colon: Dictionary) -> void:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(TAILLE, TAILLE)
	add_child(carre)
	_noeuds[colon.id] = carre

	var label := Label.new()
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	_labels[colon.id] = label

func _rafraichir_tout() -> void:
	for colon in _colons:
		var carre: ColorRect = _noeuds[colon.id]
		carre.color = _couleur_pour(colon)
		carre.position = Vector2(colon.position.x, colon.position.y) - carre.size / 2.0
		var label: Label = _labels[colon.id]
		label.position = carre.position - Vector2(10.0, 70.0)
		label.text = _texte_label(colon, _etats)
	_label_compteur.text = _texte_compteur(compter_etats(_colons))

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
