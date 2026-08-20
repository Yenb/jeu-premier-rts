extends StaticBody3D

# BANC "test_ennemi" -- le transporteur : petit cube qui cogne un gisement,
# stocke la charge prelevee, la rapporte au cube violet qui l'a pondu.
#
# FRAMEWORK COMPOSE, JAMAIS REECRIT :
# - Frappe.frapper pour la vie (10 coups) -- meme geste que vie_ennemi.gd.
# - Consommer.transferer pour cogner le gisement ET pour deposer a la mere :
#   conservatif par construction (borne a zero, credite la quantite
#   REELLEMENT prise, jamais la demandee). Aucune matiere n'est creee.
#
# FRAMEWORK ECARTE POUR CE PROTOTYPE, ET DIT POUR NE PAS DERIVER :
# - perception.gd attend un catalogue de canaux (vue/ouie/odorat...), un
#   profil, une geometrie -- disproportionne pour "voir dans un rayon de
#   10 m un noeud du groupe 'gisement'". Le jour ou le transporteur devra
#   distinguer plusieurs sens ou nourrir un LLM, on branchera le vrai.
# - memoire_spatiale.gd est un registre plat serialisable JSON pense pour
#   un colon LLM. Un transporteur qui memorise UN gisement tient dans
#   `var _gisement_memorise`.
# - velocite.gd OBSERVE, il ne PRODUIT PAS de mouvement -- le "va vers"
#   reste local, comme dans les bancs du framework.
#
# QUATRE ETATS SEULEMENT :
# - ERRANCE : marche aleatoire tant qu'aucun gisement n'est memorise.
#   Un scan tous les `secondes_par_scan` cherche un gisement a portee.
# - VERS_GISEMENT : va vers le gisement memorise. Au contact, passe a COGNE.
# - COGNE : Consommer.transferer(gisement -> soi) une fois par seconde.
#   Charge pleine -> VERS_MERE. Gisement epuise -> oublie, retour ERRANCE
#   (ou VERS_MERE si deja de la charge).
# - VERS_MERE : va vers le cube violet, depose au contact. Retour a
#   ERRANCE ou VERS_GISEMENT selon la memoire.
#
# LA MERE EST PASSEE PAR garde_transporteurs.gd, jamais devinee. Une mere
# invalide (cube violet detruit) fait errer le transporteur sans jamais
# rapporter -- il peut cogner mais reste plein.

const Frappe = preload("res://scripts/frappe.gd")
const Consommer = preload("res://scripts/consommer.gd")
const Perception = preload("res://scripts/perception.gd")
const Proximite = preload("res://scripts/proximite.gd")

# CATALOGUES LOCAUX : on utilise le mecanisme framework SANS ecrire dans
# data/canaux.json ni data/profils_saillance.json (fichiers destines aux
# colons du framework, un banc n'a pas a les polluer). Le framework
# ACCEPTE explicitement un catalogue passe en parametre a chaque appel --
# c'est prevu pour ce cas exact.
const CATALOGUE_CANAUX := {
	"vue": {"geometrie": "cone_oriente"},
}
const CATALOGUE_SAILLANCE := {
	# UNE SAILLANCE FORTE, une PORTEE plus large que la vue -- ce qui
	# tranche est la portee de VUE (portee_vision, sur le percevant), pas
	# la portee_saillance ici. Elle sert au FACTEUR de proximite.gd :
	# a mi-portee_vision, saillance = 8.0 * (1 - 5/20) = 6.0 -- encore
	# forte, donc le transporteur ne perd pas de temps a hesiter.
	"gisement_fer": {"saillance_intrinseque": 8.0, "portee_saillance": 20.0},
}

@export var vie_max: float = 3.0
@export var charge_max: float = 10.0
@export var degats_par_coup: float = 5.0
@export var vitesse: float = 3.0
@export var portee_vision: float = 10.0
@export var rayon_contact: float = 1.2
@export var secondes_par_direction: float = 2.0
@export var secondes_par_scan: float = 1.0
@export var secondes_par_coup: float = 1.0

enum {
	ETAT_ERRANCE,
	ETAT_VERS_GISEMENT,
	ETAT_COGNE,
	ETAT_VERS_MERE,
}

var entite: Dictionary
var mere: Node3D
# LE MONDE PARTAGE, resolu au _ready via le groupe -- sans lui, la
# perception ne peut rien voir. Un transporteur qui n'en trouve pas se
# rabat sur l'errance pure (equivalent d'etre aveugle), plutot que
# planter le jeu.
var _monde_partage: Node = null

var _barre_vie: MeshInstance3D
var _materiau_vie: ShaderMaterial
var _barre_charge: MeshInstance3D
var _materiau_charge: ShaderMaterial

var _etat := ETAT_ERRANCE
var _direction := Vector3.ZERO
var _depuis_direction := 0.0
var _depuis_scan := 0.0
var _depuis_coup := 0.0
var _gisement_vise: Node3D = null

static var _prochaine_graine := 20260821
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = _prochaine_graine
	_prochaine_graine += 1
	entite = {
		"id": str(get_instance_id()),
		"position": global_position,
		"proprietes": {
			"reserves": {
				"vie": {"reserve": vie_max, "capacite": vie_max},
				"charge": {"reserve": 0.0, "capacite": charge_max},
			},
			# LES CANAUX PERCEPTIFS, STRUCTURELS pour perception.gd. Une
			# seule vue (cone_oriente a 360, donc sphere pure) suffit ici --
			# le transporteur n'a pas d'ouie ni d'odorat.
			"canaux": ["vue"],
			"canaux_config": {
				"vue": {"portee": portee_vision, "sensibilite": 1.0, "seuil": 0.0},
			},
		},
	}
	_monde_partage = get_tree().get_first_node_in_group("monde_partage")
	_barre_vie = get_node("BarreDeVie/Barre") as MeshInstance3D
	_materiau_vie = _barre_vie.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre_vie.set_surface_override_material(0, _materiau_vie)
	_barre_charge = get_node("BarreDeCharge/Barre") as MeshInstance3D
	_materiau_charge = _barre_charge.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre_charge.set_surface_override_material(0, _materiau_charge)
	_rafraichir_barres()
	_tirer_direction()

func subir_frappe(degats: float) -> void:
	Frappe.frapper(entite, degats, "vie")
	_rafraichir_barres()
	if entite.proprietes.reserves.vie.reserve <= 0.0:
		queue_free()

func _process(delta: float) -> void:
	entite["position"] = global_position
	match _etat:
		ETAT_ERRANCE:
			_faire_errance(delta)
		ETAT_VERS_GISEMENT:
			_faire_vers_gisement(delta)
		ETAT_COGNE:
			_faire_cogne(delta)
		ETAT_VERS_MERE:
			_faire_vers_mere(delta)

# ------------------ ERRANCE ------------------

func _faire_errance(delta: float) -> void:
	_depuis_scan += delta
	if _depuis_scan >= secondes_par_scan:
		_depuis_scan = 0.0
		var vu := _chercher_gisement()
		if vu != null:
			_gisement_vise = vu
			_etat = ETAT_VERS_GISEMENT
			return
	_marcher_aleatoire(delta)

# CHERCHE LA CIBLE LA PLUS SAILLANTE : compose Perception + Proximite.
# Perception rend tout ce qui tombe dans le cone_oriente (ici sphere de
# portee_vision). Proximite pondere par le profil_saillance de chaque
# chose (le gisement en porte un, le cube violet non pour l'instant).
# On rend le NOEUD 3D de la plus saillante, ou null si rien.
func _chercher_gisement() -> Node3D:
	if _monde_partage == null:
		return null
	var percues := Perception.percevoir(entite, _monde_partage.monde, CATALOGUE_CANAUX)
	if percues.is_empty():
		return null
	var evaluees := Proximite.evaluer(percues, entite, CATALOGUE_SAILLANCE)
	if evaluees.is_empty():
		return null
	var meilleur: Dictionary = evaluees[0]
	for i in range(1, evaluees.size()):
		if evaluees[i].saillance > meilleur.saillance:
			meilleur = evaluees[i]
	# LE NOEUD 3D EST PORTE PAR LA CHOSE, pas devine : gisement_fer.gd le
	# pose explicitement dans son entite au _ready.
	var noeud = meilleur.chose.get("noeud", null)
	if noeud is Node3D and is_instance_valid(noeud):
		return noeud
	return null

func _marcher_aleatoire(delta: float) -> void:
	_depuis_direction += delta
	if _depuis_direction >= secondes_par_direction:
		_tirer_direction()
		_depuis_direction = 0.0
	global_position = global_position + _direction * vitesse * delta

func _tirer_direction() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	_direction = Vector3(cos(angle), 0.0, sin(angle))

# ------------------ VERS GISEMENT ------------------

func _faire_vers_gisement(delta: float) -> void:
	if not is_instance_valid(_gisement_vise):
		_gisement_vise = null
		_etat = ETAT_ERRANCE
		return
	var vers: Vector3 = _gisement_vise.global_position - global_position
	vers.y = 0.0
	if vers.length() <= rayon_contact:
		_etat = ETAT_COGNE
		_depuis_coup = secondes_par_coup   # premier coup au premier tick
		return
	_avancer_vers(vers, delta)

# ------------------ COGNE ------------------

func _faire_cogne(delta: float) -> void:
	if not is_instance_valid(_gisement_vise):
		_gisement_vise = null
		_choisir_apres_cognage()
		return
	_depuis_coup += delta
	if _depuis_coup < secondes_par_coup:
		return
	_depuis_coup = 0.0
	# CONSOMMER.TRANSFERER, PAS un appel bricole : conservatif, borne a zero.
	# taux * delta = degats_par_coup * 1.0 = 5.0 par coup exact.
	var bilan := Consommer.transferer(
		_gisement_vise.entite, entite, "metal", "charge",
		degats_par_coup, 1.0)
	_rafraichir_barres()
	if bilan.source_epuisee:
		_gisement_vise = null
	if entite.proprietes.reserves.charge.reserve >= charge_max:
		_choisir_apres_cognage()
		return
	if _gisement_vise == null:
		_choisir_apres_cognage()

func _choisir_apres_cognage() -> void:
	if entite.proprietes.reserves.charge.reserve > 0.0:
		_etat = ETAT_VERS_MERE
	else:
		_etat = ETAT_ERRANCE

# ------------------ VERS MERE ------------------

func _faire_vers_mere(delta: float) -> void:
	if not is_instance_valid(mere):
		# Mere morte : on ne peut plus deposer, on erre avec la charge.
		_etat = ETAT_ERRANCE
		return
	var vers: Vector3 = mere.global_position - global_position
	vers.y = 0.0
	if vers.length() <= rayon_contact:
		_deposer_a_la_mere()
		return
	_avancer_vers(vers, delta)

func _deposer_a_la_mere() -> void:
	if not is_instance_valid(mere):
		return
	# CONSOMMER.TRANSFERER, meme geste que le cognage : la charge du
	# transporteur devient le stock_metal de la mere, quantite REELLEMENT
	# transferee garantie egale a ce qui a quitte la source.
	Consommer.transferer(entite, mere.entite, "charge", "stock_metal",
		charge_max, 1.0)
	_rafraichir_barres()
	# LA MERE RAFRAICHIT SA PROPRE BARRE DE STOCK -- sinon la barre
	# bleue ne bougerait qu'a un frappe/coup, jamais au depot.
	if mere.has_method("_rafraichir_barres"):
		mere._rafraichir_barres()
	# Retour : chercher un gisement (memoire perdue si on veut, mais
	# souvent le meme est encore utile s'il n'est pas epuise).
	if is_instance_valid(_gisement_vise):
		_etat = ETAT_VERS_GISEMENT
	else:
		_etat = ETAT_ERRANCE

# ------------------ COMMUN ------------------

func _avancer_vers(direction_brute: Vector3, delta: float) -> void:
	var direction: Vector3 = direction_brute.normalized()
	global_position = global_position + direction * vitesse * delta

func _rafraichir_barres() -> void:
	var fraction_vie := clampf(entite.proprietes.reserves.vie.reserve / vie_max, 0.0, 1.0)
	_materiau_vie.set_shader_parameter("fraction", fraction_vie)
	var fraction_charge := clampf(entite.proprietes.reserves.charge.reserve / charge_max, 0.0, 1.0)
	_materiau_charge.set_shader_parameter("fraction", fraction_charge)
