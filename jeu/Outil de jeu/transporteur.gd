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
	"gisement_fer": {
		"saillance_intrinseque": 8.0, "portee_saillance": 20.0,
		"sens": "attirance",
	},
	# LE JOUEUR : plus SAILLANT que le gisement (20 contre 8) et VU DE
	# PLUS LOIN -- la peur prime toujours sur la faim. `sens: "fuite"`
	# est un champ LOCAL a ce banc (proximite.gd l'ignore silencieusement,
	# il ne lit que saillance_intrinseque et portee_saillance) : c'est le
	# transporteur qui trie attirance/fuite apres l'evaluation.
	"joueur_menace": {
		"saillance_intrinseque": 20.0, "portee_saillance": 15.0,
		"sens": "fuite",
	},
	# UN AUTRE CUBE VIOLET (que la mere) : le transporteur y va quand sa
	# mere est pleine. La saillance est plus faible que celle du gisement --
	# on prefere d'abord aller collecter, on ne relaie que si le stock est
	# deja plein.
	"cube_violet_disponible": {
		"saillance_intrinseque": 6.0, "portee_saillance": 15.0,
		"sens": "attirance",
	},
}

@export var vie_max: float = 3.0
@export var charge_max: float = 10.0
@export var degats_par_coup: float = 5.0
@export var vitesse: float = 3.0
@export var portee_vision: float = 5.0
@export var rayon_contact: float = 1.2
@export var secondes_par_direction: float = 2.0
@export var secondes_par_scan: float = 1.0
@export var secondes_par_coup: float = 1.0

enum {
	ETAT_ERRANCE,
	ETAT_VERS_GISEMENT,
	ETAT_COGNE,
	ETAT_VERS_MERE,
	ETAT_VERS_AUTRE_CUBE,
	ETAT_FUITE,
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
# LE CUBE ALTERNATIF -- utilise quand la mere est pleine et qu'on trouve
# un autre cube pas plein. Oublie apres depot.
var _cube_alternatif: Node3D = null

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
	# LA MENACE PREND PRIORITE : evaluee a CHAQUE frame. Une menace percue
	# force ETAT_FUITE, quel que soit l'etat en cours (aller vers un
	# gisement, cogner, revenir a la mere -- tout est mis en pause). Une
	# menace qui sort de portee laisse le transporteur reprendre son
	# comportement normal a partir d'ERRANCE (il devra retrouver le
	# gisement, comme un vrai animal apeure qui perd le fil).
	var menace := _percevoir_la_plus_menacante()
	if menace != null:
		_etat = ETAT_FUITE
		_fuir(menace, delta)
		return
	if _etat == ETAT_FUITE:
		_etat = ETAT_ERRANCE
	match _etat:
		ETAT_ERRANCE:
			_faire_errance(delta)
		ETAT_VERS_GISEMENT:
			_faire_vers_gisement(delta)
		ETAT_COGNE:
			_faire_cogne(delta)
		ETAT_VERS_MERE:
			_faire_vers_mere(delta)
		ETAT_VERS_AUTRE_CUBE:
			_faire_vers_autre_cube(delta)

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

# RETOURNE LA CHOSE LA PLUS SAILLANTE avec le sens demande ("attirance"
# ou "fuite"). Rend null si rien de percu dans ce sens.
#
# CE FILTRAGE PAR "sens" EST LOCAL AU TRANSPORTEUR, pas au framework :
# proximite.gd ne connait pas cette notion, il rend juste une saillance.
# C'est ici qu'on decide qu'un profil "attirance" me fait aller vers, un
# profil "fuite" me fait aller contre.
func _percevoir_plus_saillante(sens_voulu: String) -> Node3D:
	if _monde_partage == null:
		return null
	var percues := Perception.percevoir(entite, _monde_partage.monde, CATALOGUE_CANAUX)
	if percues.is_empty():
		return null
	var evaluees := Proximite.evaluer(percues, entite, CATALOGUE_SAILLANCE)
	var meilleure_saillance := 0.0
	var meilleur: Dictionary = {}
	for eva in evaluees:
		var ref: String = eva.chose.proprietes.get("profil_saillance", "")
		var sens: String = CATALOGUE_SAILLANCE.get(ref, {}).get("sens", "")
		if sens != sens_voulu:
			continue
		if eva.saillance > meilleure_saillance:
			meilleure_saillance = eva.saillance
			meilleur = eva
	if meilleur.is_empty():
		return null
	var noeud = meilleur.chose.get("noeud", null)
	# is_instance_valid AVANT is : voir _percevoir_plus_saillante_avec_profil.
	if noeud == null or not is_instance_valid(noeud) or not (noeud is Node3D):
		return null
	return noeud

func _chercher_gisement() -> Node3D:
	# Filtre par PROFIL : on ne veut pas confondre un gisement avec un
	# cube violet disponible (les deux ont sens=attirance mais rien a
	# voir a l'usage).
	return _percevoir_plus_saillante_avec_profil("attirance", "gisement_fer",
		func(_noeud): return true)

func _percevoir_la_plus_menacante() -> Node3D:
	return _percevoir_plus_saillante("fuite")

# CHERCHE UN AUTRE CUBE VIOLET pas plein et pas sa mere. Filtre applique
# sur le noeud, pas sur le catalogue -- la "disponibilite" est un etat
# dynamique du cube (son stock), pas un profil de saillance.
func _chercher_cube_disponible_autre_que_mere() -> Node3D:
	return _percevoir_plus_saillante_avec_profil(
		"attirance", "cube_violet_disponible",
		func(noeud):
			if noeud == mere:
				return false
			if noeud.has_method("est_plein") and noeud.est_plein():
				return false
			return true)

# VARIANTE de _percevoir_plus_saillante qui filtre par NOM de profil ET
# par un predicat sur le noeud. Le predicat est indispensable pour
# "cube pas plein" -- l'etat dynamique du cube (stock) n'est pas dans le
# catalogue de saillance, il est sur l'instance.
func _percevoir_plus_saillante_avec_profil(
		sens_voulu: String, profil_voulu: String, predicat: Callable) -> Node3D:
	if _monde_partage == null:
		return null
	var percues := Perception.percevoir(entite, _monde_partage.monde, CATALOGUE_CANAUX)
	if percues.is_empty():
		return null
	var evaluees := Proximite.evaluer(percues, entite, CATALOGUE_SAILLANCE)
	var meilleure_saillance := 0.0
	var meilleur_noeud: Node3D = null
	for eva in evaluees:
		var ref: String = eva.chose.proprietes.get("profil_saillance", "")
		if ref != profil_voulu:
			continue
		var sens: String = CATALOGUE_SAILLANCE.get(ref, {}).get("sens", "")
		if sens != sens_voulu:
			continue
		var noeud = eva.chose.get("noeud", null)
		# is_instance_valid AVANT is : is sur une instance libere leve
		# "Left operand of 'is' is a previously freed instance." en Godot 4.
		# Cas : un gisement/cube epuise a ete queue_free avant que son
		# entree du monde ait ete retiree ce meme frame.
		if noeud == null or not is_instance_valid(noeud) or not (noeud is Node3D):
			continue
		if not predicat.call(noeud):
			continue
		if eva.saillance > meilleure_saillance:
			meilleure_saillance = eva.saillance
			meilleur_noeud = noeud
	return meilleur_noeud

# LA FUITE : simple, sans strategie -- direction OPPOSEE a la menace, a
# vitesse normale. Un vrai animal qui panique ne calcule pas d'itineraire,
# il s'eloigne, point. Rien de plus subtil ici : c'est le comportement
# qui donne le "cote debile" qui a fait rire Yael.
func _fuir(menace: Node3D, delta: float) -> void:
	if not is_instance_valid(menace):
		return
	var vers_menace: Vector3 = menace.global_position - global_position
	vers_menace.y = 0.0
	if vers_menace.length() <= 0.001:
		# COLLE SUR LA MENACE : direction arbitraire pour se decoller.
		vers_menace = Vector3.RIGHT
	var direction: Vector3 = -vers_menace.normalized()
	global_position = global_position + direction * vitesse * delta

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
		# Mere morte : on ne peut plus deposer chez elle. Peut-etre chez
		# un autre cube -- on tente la perception.
		_choisir_autre_cube_ou_errer()
		return
	# MERE PLEINE : on ne peut plus lui deposer, chercher un autre cube.
	if mere.has_method("est_plein") and mere.est_plein():
		_choisir_autre_cube_ou_errer()
		return
	var vers: Vector3 = mere.global_position - global_position
	vers.y = 0.0
	if vers.length() <= rayon_contact:
		_deposer_dans(mere)
		_apres_depot()
		return
	_avancer_vers(vers, delta)

# ------------------ VERS AUTRE CUBE ------------------

func _faire_vers_autre_cube(delta: float) -> void:
	# Le cube alternatif a peut-etre ete detruit, ou vient de se remplir --
	# on rechecke a chaque tick.
	if not is_instance_valid(_cube_alternatif) \
			or (_cube_alternatif.has_method("est_plein") and _cube_alternatif.est_plein()):
		_cube_alternatif = null
		# Si la mere est de nouveau disponible, on y retourne.
		if is_instance_valid(mere) and not (mere.has_method("est_plein") and mere.est_plein()):
			_etat = ETAT_VERS_MERE
		else:
			_choisir_autre_cube_ou_errer()
		return
	var vers: Vector3 = _cube_alternatif.global_position - global_position
	vers.y = 0.0
	if vers.length() <= rayon_contact:
		_deposer_dans(_cube_alternatif)
		_cube_alternatif = null
		_apres_depot()
		return
	_avancer_vers(vers, delta)

# CHERCHE UN AUTRE CUBE DISPONIBLE via perception+saillance. S'il en
# trouve un, cible-le ; sinon erre en attendant que la mere se libere.
func _choisir_autre_cube_ou_errer() -> void:
	var autre := _chercher_cube_disponible_autre_que_mere()
	if autre != null:
		_cube_alternatif = autre
		_etat = ETAT_VERS_AUTRE_CUBE
	else:
		_etat = ETAT_ERRANCE

# GESTE DE DEPOT partage : mere ou autre cube, meme Consommer.transferer,
# meme geste. La cible refresh sa propre barre de stock (sinon la barre
# bleue ne bougerait qu'au frappe/coup).
func _deposer_dans(cible: Node3D) -> void:
	if not is_instance_valid(cible):
		return
	Consommer.transferer(entite, cible.entite, "charge", "stock_metal",
		charge_max, 1.0)
	_rafraichir_barres()
	if cible.has_method("_rafraichir_barres"):
		cible._rafraichir_barres()

func _apres_depot() -> void:
	# Retour : chercher un gisement (memoire perdue si le gisement est
	# detruit, sinon le meme est encore utile).
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
