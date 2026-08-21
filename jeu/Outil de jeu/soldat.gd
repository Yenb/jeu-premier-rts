extends StaticBody3D

# BANC "test_ennemi" -- le soldat : fonce sur le joueur, le frappe au
# contact. Meme motif que transporteur.gd (perception + saillance +
# machine a etats), avec deux differences :
# - Le joueur est une ATTIRANCE (cible), pas une fuite.
# - Il frappe une cible en Node3D (pas un transfert de reserve). Cible :
#   un descendant du personnage qui expose `subir_frappe`, meme
#   convention que le personnage envers un ennemi.
#
# NE VOIT QUE LE JOUEUR : catalogue local avec un seul profil. Un soldat
# ignore gisements et autres cubes -- rien d'autre a chasser.
#
# QUAND IL NE VOIT RIEN, IL ERRE. Le joueur est peut-etre a portee de
# vue si le soldat bouge -- meme motif que le transporteur qui erre
# jusqu'a apercevoir un gisement.

const Frappe = preload("res://scripts/frappe.gd")
const Perception = preload("res://scripts/perception.gd")
const Proximite = preload("res://scripts/proximite.gd")
const LienPersonnel = preload("res://scripts/lien_personnel.gd")

# MEMOIRE DE CIBLE : le lien personnel monte a chaque perception, decroit
# a chaque tick sans perception. Le soldat continue a chasser tant que le
# lien avec le joueur est > plancher -- meme s'il ne le voit plus a
# l'instant. Sans ce mecanisme, un joueur qui recule pile entre deux
# scans (portee 8 m, vitesse joueur superieure) faisait abandonner le
# soldat comme un idiot. Calibre pour ~3 s de memoire :
#   magnitude par perception (chaque 0.5 s) = 1.0
#   taux_decroissance = 0.4 / seconde  => une perception seule survit ~2.5 s
#   plancher_suppression = 0.05
# Une perception REPETEE (le joueur toujours en vue) fait empiler la force,
# donc la memoire dure d'autant plus longtemps quand on l'a bien traque.
const CATALOGUE_LIEN := {
	"defaut": {
		"taux_decroissance": 0.4,
		"plancher_suppression": 0.05,
	},
}
const MAGNITUDE_PERCEPTION := 1.0

const CATALOGUE_CANAUX := {
	"vue": {"geometrie": "cone_oriente"},
}
const CATALOGUE_SAILLANCE := {
	"joueur_menace": {
		"saillance_intrinseque": 20.0, "portee_saillance": 40.0,
	},
}

@export var vie_max: float = 20.0
@export var vitesse: float = 3.0
@export var portee_vision: float = 8.0
@export var rayon_contact: float = 1.2
@export var degats_par_coup: float = 10.0
@export var secondes_par_coup: float = 1.0
@export var secondes_par_direction: float = 2.0
@export var secondes_par_scan: float = 0.5

# RAYON DE DEFENSE : le soldat garde le territoire de son cube parent,
# jamais plus loin que ca. Une chasse qui l'entraine trop loin l'oblige
# a rentrer -- il ne poursuit pas jusqu'a l'autre bout de la carte.
@export var rayon_defense: float = 10.0

enum {
	ETAT_ERRANCE,
	ETAT_VERS_JOUEUR,
	ETAT_ATTAQUE,
	ETAT_RETOUR_FOYER,
}

# CUBE PARENT : passe par gestation_soldat.gd apres l'instanciation --
# meme pattern que garde_transporteurs pour la mere du transporteur.
var cube_parent: Node3D
var entite: Dictionary
var _monde_partage: Node = null
# LA POSITION DU FOYER, capturee a la premiere frame -- l'add_child se
# fait AVANT le repositionnement, donc au _ready global_position vaut
# la position par defaut. On differe. Meme piege deja paye sur le
# transporteur (voir historique de _foyer).
var _position_foyer: Vector3 = Vector3.ZERO
var _foyer_pret := false
var _barre: MeshInstance3D
var _materiau: ShaderMaterial
var _etat := ETAT_ERRANCE
var _joueur_vise: Node3D = null
var _direction := Vector3.ZERO
var _depuis_direction := 0.0
var _depuis_scan := 0.0
var _depuis_coup := 0.0

static var _prochaine_graine := 20261101
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = _prochaine_graine
	_prochaine_graine += 1
	entite = {
		"id": str(get_instance_id()),
		"position": global_position,
		"proprietes": {
			"reserves": {"vie": {"reserve": vie_max, "capacite": vie_max}},
			"canaux": ["vue"],
			"canaux_config": {
				"vue": {"portee": portee_vision, "sensibilite": 1.0, "seuil": 0.0},
			},
			# STRUCTURELLE pour LienPersonnel.avancer/poser/force.
			"liens_personnels": {},
		},
	}
	_barre = get_node("BarreDeVie/Barre") as MeshInstance3D
	_materiau = _barre.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre.set_surface_override_material(0, _materiau)
	_rafraichir_barre()
	_monde_partage = get_tree().get_first_node_in_group("monde_partage")
	_tirer_direction()

func subir_frappe(degats: float) -> void:
	Frappe.frapper(entite, degats, "vie")
	_rafraichir_barre()
	if entite.proprietes.reserves.vie.reserve <= 0.0:
		queue_free()

func _process(delta: float) -> void:
	entite["position"] = global_position
	# LA MEMOIRE DE CIBLE DECROIT A CHAQUE TICK, meme si _joueur_vise
	# reste pointe. C'est ce qui la fait s'oublier au bout de ~3 s de
	# non-perception. Le geste inverse (perception -> poser) se fait
	# dans _chercher_joueur.
	LienPersonnel.avancer(entite, delta, CATALOGUE_LIEN)
	if not _foyer_pret:
		# Capture APRES le repositionnement du soldat par gestation_soldat.
		# Si cube_parent existe encore, on prend sa position (plus stable
		# si le cube se deplace un jour). Sinon la position du soldat lui-
		# meme, deja stable.
		if is_instance_valid(cube_parent):
			_position_foyer = cube_parent.global_position
		else:
			_position_foyer = global_position
		_foyer_pret = true

	# GARDE DEFENSIVE : le rayon s'applique a la CIBLE, pas au soldat en
	# chasse. Un soldat qui a mordu peut sortir du rayon pour atteindre,
	# sinon on faisait un yo-yo pathetique (le soldat sort de 1 metre,
	# rebrousse chemin, revoit le joueur, refonce, ressort...). Un
	# joueur hors du rayon n'est PAS accroche a l'entree -- voir
	# _chercher_joueur.
	# Seul l'ERRANCE respecte la limite : un soldat qui s'ecarte sans
	# cible rentre.
	if _etat == ETAT_ERRANCE \
			and global_position.distance_to(_position_foyer) > rayon_defense:
		_etat = ETAT_RETOUR_FOYER

	match _etat:
		ETAT_ERRANCE:
			_faire_errance(delta)
		ETAT_VERS_JOUEUR:
			_faire_vers_joueur(delta)
		ETAT_ATTAQUE:
			_faire_attaque(delta)
		ETAT_RETOUR_FOYER:
			_faire_retour_foyer(delta)

# ------------------ ERRANCE ------------------

func _faire_errance(delta: float) -> void:
	_depuis_scan += delta
	if _depuis_scan >= secondes_par_scan:
		_depuis_scan = 0.0
		var vu := _chercher_joueur()
		if vu != null:
			_joueur_vise = vu
			_etat = ETAT_VERS_JOUEUR
			return
	_marcher_aleatoire(delta)

func _marcher_aleatoire(delta: float) -> void:
	_depuis_direction += delta
	if _depuis_direction >= secondes_par_direction:
		_tirer_direction()
		_depuis_direction = 0.0
	global_position = global_position + _direction * vitesse * delta

func _tirer_direction() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	_direction = Vector3(cos(angle), 0.0, sin(angle))

# ------------------ RETOUR AU FOYER ------------------

func _faire_retour_foyer(delta: float) -> void:
	var vers: Vector3 = _position_foyer - global_position
	vers.y = 0.0
	# Une fois de retour dans le rayon, on reprend l'errance -- prochain
	# scan cherchera un joueur peut-etre visible depuis ici.
	if vers.length() <= rayon_defense * 0.5:
		_etat = ETAT_ERRANCE
		return
	global_position = global_position + vers.normalized() * vitesse * delta

# ------------------ VERS JOUEUR ------------------

func _faire_vers_joueur(delta: float) -> void:
	if _joueur_vise == null or not is_instance_valid(_joueur_vise):
		_joueur_vise = null
		_etat = ETAT_ERRANCE
		return
	# RESCAN : renouvelle le lien si le joueur est encore vu. S'il ne
	# l'est plus, LienPersonnel.avancer (dans _process) fera decroitre
	# la force jusqu'au plancher -- c'est cette force qui decide de
	# l'abandon, pas la perception directe.
	_depuis_scan += delta
	if _depuis_scan >= secondes_par_scan:
		_depuis_scan = 0.0
		_chercher_joueur()   # pose le lien s'il voit, laisse tomber sinon

	var id_joueur := str(_joueur_vise.get_instance_id())
	if LienPersonnel.force(entite, id_joueur, CATALOGUE_LIEN) <= 0.0:
		# LA MEMOIRE S'EST DISSOUTE : ~3 s sans perception. Abandon.
		_joueur_vise = null
		_etat = ETAT_ERRANCE
		return

	var vers: Vector3 = _joueur_vise.global_position - global_position
	vers.y = 0.0
	if vers.length() <= rayon_contact:
		_etat = ETAT_ATTAQUE
		_depuis_coup = secondes_par_coup   # premier coup au premier tick
		return
	global_position = global_position + vers.normalized() * vitesse * delta

# ------------------ ATTAQUE ------------------

func _faire_attaque(delta: float) -> void:
	if _joueur_vise == null or not is_instance_valid(_joueur_vise):
		_joueur_vise = null
		_etat = ETAT_ERRANCE
		return
	# LE JOUEUR PEUT SE DEPLACER PENDANT QU'ON ATTAQUE : s'il quitte le
	# rayon de contact, on repart en poursuite.
	var vers: Vector3 = _joueur_vise.global_position - global_position
	vers.y = 0.0
	if vers.length() > rayon_contact:
		_etat = ETAT_VERS_JOUEUR
		return
	_depuis_coup += delta
	if _depuis_coup < secondes_par_coup:
		return
	_depuis_coup = 0.0
	_frapper_joueur(_joueur_vise)

# LE COUP : cherche dans les enfants du joueur un composant qui a
# `subir_frappe`, l'appelle. Meme motif que interaction_destruction.gd
# cote joueur (has_method("subir_frappe")), symetrique.
func _frapper_joueur(joueur: Node3D) -> void:
	for enfant in joueur.get_children():
		if enfant.has_method("subir_frappe"):
			enfant.subir_frappe(degats_par_coup)
			return

# ------------------ COMMUN ------------------

# CHERCHE LE JOUEUR via perception + saillance -- meme motif que
# transporteur.gd:_chercher_gisement.
func _chercher_joueur() -> Node3D:
	if _monde_partage == null:
		return null
	var percues := Perception.percevoir(entite, _monde_partage.monde, CATALOGUE_CANAUX)
	if percues.is_empty():
		return null
	var pertinentes: Array = []
	for p in percues:
		var ref: String = p.chose.proprietes.get("profil_saillance", "")
		if CATALOGUE_SAILLANCE.has(ref):
			pertinentes.append(p)
	if pertinentes.is_empty():
		return null
	var evaluees := Proximite.evaluer(pertinentes, entite, CATALOGUE_SAILLANCE)
	if evaluees.is_empty():
		return null
	var meilleur: Dictionary = evaluees[0]
	for i in range(1, evaluees.size()):
		if evaluees[i].saillance > meilleur.saillance:
			meilleur = evaluees[i]
	var noeud = meilleur.chose.get("noeud", null)
	if noeud == null or not is_instance_valid(noeud) or not (noeud is Node3D):
		return null
	# FILTRE TERRITORIAL : un joueur HORS du rayon defensif du cube
	# parent n'est pas une cible pour ce soldat. Il ne se laisse pas
	# tirer hors de sa zone comme un chien fou. Une fois qu'il a mordu,
	# il pourra sortir du rayon pour atteindre -- c'est _process qui
	# gere cette exception.
	if _foyer_pret and noeud.global_position.distance_to(_position_foyer) > rayon_defense:
		return null
	# LA PERCEPTION RENOUVELLE LA MEMOIRE : chaque fois qu'on VOIT le
	# joueur, le lien remonte. Voir soldat.gd:CATALOGUE_LIEN.
	LienPersonnel.poser(entite, str(noeud.get_instance_id()), MAGNITUDE_PERCEPTION)
	return noeud

func _rafraichir_barre() -> void:
	var fraction := clampf(entite.proprietes.reserves.vie.reserve / vie_max, 0.0, 1.0)
	_materiau.set_shader_parameter("fraction", fraction)
