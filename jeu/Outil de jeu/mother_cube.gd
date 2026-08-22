extends RigidBody3D

# BANC "test_ennemi2 Mother box" -- LA MOTHER CUBE, pondue par le geniteur
# apres 4 generateurs d'energie vivants + stock >= 100 (voir
# gestation_mother_cube.gd). Petit cube 0.30 m avec 3 vies par defaut.
# Recoit des frappes via Frappe.frapper (framework), affiche sa vie en
# barre 3D via barre_de_vie.gdshader (patron generateur_energie.gd /
# vie_ennemi.gd).
#
# EXTENSIBLE : Yael prevoit d'ajouter des parametres plus tard (croissance
# progressive, production, comportements). Le fichier est structure comme
# les autres bancs (entite Dictionary, reserves nommees, @export
# parametres) pour recevoir de nouveaux champs sans refonte.
#
# NE COMPOSE PAS LA GESTATION : ce fichier ne connait pas son producteur.
# Il vit et meurt seul, s'inscrit dans le groupe "mother_cube" pour que
# le banc de gestation du geniteur puisse compter les vivantes (max 1
# par defaut).
#
# NE REINVENTE PAS LE CALCUL DE DEGATS : Frappe.frapper() (framework)
# soustrait la reserve, bornee a zero.

const Frappe = preload("res://scripts/frappe.gd")
const Perception = preload("res://scripts/perception.gd")

# CATALOGUE LOCAL des canaux perceptifs. Patron transporteur.gd:47-49 --
# on n'ecrit rien dans data/canaux.json (framework), on passe un catalogue
# local a Perception.percevoir. Une seule vue en cone_oriente ; angle >= 360
# (implicite absent) => sphere pure (voir perception.gd:198-200).
const CATALOGUE_CANAUX := {
	"vue": {"geometrie": "cone_oriente"},
}

@export var vie_max: float = 3.0
# PORTEE VUE : 30 m specifie par Yael pour la mother cube. Elle ne voit
# rien au-dela, meme dans l'ecosysteme ennemi. Regle par l'inspecteur.
@export var portee_vision: float = 30.0
# VITESSE PETITE / ADULTE : lerp lineaire selon ratio_taille (petite=0,
# adulte=1). Rapport x4 valide par Yael pour immobilisation progressive
# type reine termite physogastrique (documente par la recherche
# 2026-08-22, cuticule x20-150 chez Macrotermes bellicosus).
@export var vitesse_petite: float = 10.0
@export var vitesse_adulte: float = 2.5
# TAILLE : base 0.3 m (echelle 1.0), max 70 m (echelle ~233). La mother
# cube grossit de gain_par_manger_pct % PAR CARRE mange, DECROISSANT
# lineairement vers 0 quand ratio_taille -> 1. A ratio 0.5 le gain est
# divise par 2 (regle Yael "mange 2x moins efficace a mi-taille").
@export var taille_base_m: float = 0.3
@export var taille_max_m: float = 70.0
@export var gain_par_manger_pct: float = 5.0
# DISTANCE DE CONTACT : la mother cube frappe la nourriture quand la
# distance <= cette valeur. Mother cube 0.3 m + carre rouge 0.4 m ->
# 0.5 m de tolerance.
@export var distance_contact_mange: float = 0.6
# CADENCE FRAPPE : une frappe par seconde par defaut. Un carre rouge a
# 5 vies -> 5 s pour le manger. Regable dans l'inspecteur.
@export var secondes_par_frappe: float = 1.0

var entite: Dictionary
var _barre_vie: MeshInstance3D
var _materiau_vie: ShaderMaterial
# LE MONDE PARTAGE : resolu au _ready via le groupe -- sans lui, la
# perception ne peut rien voir. Une mother cube qui n'en trouve pas se
# rabat sur "je ne percois rien" (percevoir_nourriture rend []), plutot
# que planter.
var _monde_partage: Node = null

# Idempotent : queue_free peut declencher plusieurs chemins, on ne retire
# du monde qu'une fois.
var _est_mort: bool = false

# ETAT-MACHINE (morceau 3a) : ATTENTE -> percois nourriture -> VERS ->
# MANGE (au contact) -> ATTENTE quand la cible meurt/disparait.
enum {
	ETAT_ATTENTE,
	ETAT_VERS_NOURRITURE,
	ETAT_MANGE,
}
var _etat: int = ETAT_ATTENTE
# CIBLE VIVANTE : Node3D du carre rouge en cours de chasse/mangeage.
# is_instance_valid teste avant chaque usage -- une cible peut mourir
# entre deux frames (autre mangeur, joueur, mort naturelle).
var _cible_nourriture: Node3D = null
var _secondes_depuis_frappe: float = 0.0

func _mourir() -> void:
	if _est_mort:
		return
	_est_mort = true
	# SORT DU MONDE AVANT queue_free (patron carre_rouge.gd / gisement_fer.gd).
	# Sans ce retrait, un percevant continuerait a la voir comme un fantome.
	if _monde_partage != null:
		_monde_partage.monde.retirer(entite.id)
	queue_free()

func _ready() -> void:
	add_to_group("mother_cube")
	entite = {
		"id": str(get_instance_id()),
		"position": global_position,
		"proprietes": {
			"reserves": {
				"vie": {"reserve": vie_max, "capacite": vie_max},
			},
			# CANAUX PERCEPTIFS -- structurels pour perception.gd (cf.
			# perception.gd:118 : cle absente = push_error). Une seule vue,
			# angle absent = sphere pure a portee_vision metres.
			"canaux": ["vue"],
			"canaux_config": {
				"vue": {"portee": portee_vision, "sensibilite": 1.0, "seuil": 0.0},
			},
		},
		"noeud": self,
	}
	# INSCRIT AU MONDE PARTAGE : sans ca, la mother cube ne serait pas
	# elle-meme percue par d'autres entites (a cabler plus tard : joueur).
	# Meme patron carre_rouge.gd / gisement_fer.gd.
	_monde_partage = get_tree().get_first_node_in_group("monde_partage")
	if _monde_partage != null:
		_monde_partage.monde.ajouter(entite, "mother_cube", global_position)

	_barre_vie = get_node("BarreDeVie/Barre") as MeshInstance3D
	# DUPLIQUE le materiau pour ne pas partager la fraction entre plusieurs
	# instances futures. Meme patron que generateur_energie.gd:_ready.
	_materiau_vie = _barre_vie.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre_vie.set_surface_override_material(0, _materiau_vie)
	_rafraichir_barre()

func _process(delta: float) -> void:
	# SYNCHRONISATION POSITION MONDE : la mother cube bouge (physique
	# RigidBody + mouvement volontaire au morceau 3). entite.position doit
	# refleter la position vivante pour que Perception.percevoir mesure
	# les distances correctement. Patron transporteur.gd:156.
	if _est_mort:
		return
	entite["position"] = global_position
	# ACCUMULATION COMPTEUR FRAPPE : incremente tant qu'une cible est
	# vivante, quel que soit l'etat. Une oscillation MANGE<->VERS a la
	# frontiere du contact ne reset plus le compteur (bug corrige 2026-08-22).
	if _cible_nourriture != null and is_instance_valid(_cible_nourriture):
		_secondes_depuis_frappe += delta
	else:
		_secondes_depuis_frappe = 0.0
	match _etat:
		ETAT_ATTENTE:
			_faire_attente()
		ETAT_VERS_NOURRITURE:
			_faire_vers_nourriture(delta)
		ETAT_MANGE:
			_faire_mange(delta)

# ATTENTE : cherche la nourriture la plus proche via perception. Si
# quelque chose est vu, vise et passe en VERS_NOURRITURE. Sinon reste
# immobile (stopper la derive horizontale).
func _faire_attente() -> void:
	linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)
	var vus: Array = percevoir_nourriture()
	if vus.is_empty():
		return
	# Le tri est par distance croissante (percevoir_nourriture le fait).
	# On prend le plus proche.
	var noeud = vus[0].chose.get("noeud", null)
	# is_instance_valid AVANT is : is sur instance liberee plante en Godot 4.
	# Patron transporteur.gd:222-224.
	if noeud == null or not is_instance_valid(noeud) or not (noeud is Node3D):
		return
	_cible_nourriture = noeud as Node3D
	_etat = ETAT_VERS_NOURRITURE

# VERS_NOURRITURE : marche horizontale vers la cible. Meme pattern que
# geniteur.gd:_avancer_vers_cible. Perte de cible (invalide) -> retour
# ATTENTE. Contact -> MANGE + reset compteur de frappe.
func _faire_vers_nourriture(_delta: float) -> void:
	if _cible_nourriture == null or not is_instance_valid(_cible_nourriture):
		_cible_nourriture = null
		_etat = ETAT_ATTENTE
		return
	var vers: Vector3 = _cible_nourriture.global_position - global_position
	vers.y = 0.0
	if vers.length() <= distance_contact_mange:
		linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)
		_etat = ETAT_MANGE
		# NE PAS reset _secondes_depuis_frappe : le compteur accumule tant
		# que la cible est vivante (voir _process). Sinon une oscillation
		# MANGE<->VERS_NOURRITURE (contact frontier) reinitialise le
		# compteur chaque frame, aucun degat n'est jamais applique.
		# Observe le 2026-08-22 : 3 frappes en 8s au lieu de 8 attendues.
		return
	var direction := vers.normalized()
	# Vitesse variable : lerp(vitesse_petite, vitesse_adulte, ratio_taille).
	var v: float = _vitesse_courante()
	linear_velocity = Vector3(direction.x * v, linear_velocity.y, direction.z * v)

# MANGE : cible au contact. Frappe une fois par secondes_par_frappe
# jusqu'a mort de la cible. Cible morte/invalide -> retour ATTENTE. Si
# la cible s'eloigne, on reprend en VERS_NOURRITURE (le compteur continue
# a accumuler dans _process pour ne pas perdre la progression).
func _faire_mange(_delta: float) -> void:
	if _cible_nourriture == null or not is_instance_valid(_cible_nourriture):
		_cible_nourriture = null
		_etat = ETAT_ATTENTE
		return
	var vers: Vector3 = _cible_nourriture.global_position - global_position
	vers.y = 0.0
	if vers.length() > distance_contact_mange:
		_etat = ETAT_VERS_NOURRITURE
		return
	linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)
	# Accumulation du compteur : voir _process. Ici on ne fait que verifier
	# si le seuil est atteint pour frapper.
	if _secondes_depuis_frappe >= secondes_par_frappe:
		_secondes_depuis_frappe = 0.0
		if _cible_nourriture.has_method("subir_frappe"):
			# Lire la valeur nourriture AVANT la frappe : si la frappe tue
			# la cible, on n'y accedera plus (queue_free en fin de frame).
			var nourriture_gagnee: float = 0.0
			if "entite" in _cible_nourriture:
				nourriture_gagnee = float(_cible_nourriture.entite.proprietes.get("nourriture", 0.0))
			_cible_nourriture.subir_frappe(1.0)
			# La frappe tue-t-elle la cible ? -> croissance.
			if "entite" in _cible_nourriture and float(_cible_nourriture.entite.proprietes.reserves.vie.reserve) <= 0.0:
				nourrir(nourriture_gagnee)

# API publique -- appelee par _faire_mange quand la cible meurt sous les
# frappes. La croissance depend du ratio_taille actuel : gain plein a
# petite (ratio 0), gain nul a adulte (ratio 1). Le scale est cape a
# scale_max = taille_max_m / taille_base_m.
# Formule : gain_pct = gain_par_manger_pct * (1 - ratio_taille)
# Applique multiplicativement : scale *= (1 + gain_pct/100)
func nourrir(_valeur: float) -> void:
	var ratio: float = _ratio_taille()
	var gain_pct: float = gain_par_manger_pct * (1.0 - ratio)
	var facteur: float = 1.0 + gain_pct / 100.0
	var scale_max: float = _scale_max()
	var nouveau_scale: float = minf(scale.x * facteur, scale_max)
	scale = Vector3.ONE * nouveau_scale

# Ratio de croissance dans [0, 1]. 0 = taille de base (scale=1). 1 =
# taille max (scale = scale_max). Utilise par vitesse_courante et gain_pct
# pour interpoler lineairement.
func _ratio_taille() -> float:
	var scale_max: float = _scale_max()
	if scale_max <= 1.0:
		return 0.0
	return clampf((scale.x - 1.0) / (scale_max - 1.0), 0.0, 1.0)

func _scale_max() -> float:
	if taille_base_m <= 0.0:
		return 1.0
	return taille_max_m / taille_base_m

func _vitesse_courante() -> float:
	return lerp(vitesse_petite, vitesse_adulte, _ratio_taille())

# API publique -- appelee par ce qui frappe (arme, projectile, etc.).
func subir_frappe(degats: float) -> void:
	Frappe.frapper(entite, degats, "vie")
	_rafraichir_barre()
	if entite.proprietes.reserves.vie.reserve <= 0.0:
		_mourir()

# API publique -- rend la liste des percepts qui portent une propriete
# "nourriture" > 0 sur leur entite du monde. La couche perception
# (framework) est aveugle et rend TOUT dans le cone de vue ; la saillance
# ici est faite en local par filtrage sur propriete NOMMEE, PAS sur type
# (respect CLAUDE.md § ADN -- aucun test type == "carre_rouge").
#
# Rend un Array de percepts {chose, type, position, distance, canaux} tries
# du plus proche au plus loin. Vide si aucune nourriture percue ou si le
# monde partage est absent.
func percevoir_nourriture() -> Array:
	if _monde_partage == null:
		return []
	var percues := Perception.percevoir(entite, _monde_partage.monde, CATALOGUE_CANAUX)
	var nourritures: Array = []
	for p in percues:
		var props: Dictionary = p.chose.get("proprietes", {})
		if float(props.get("nourriture", 0.0)) > 0.0:
			nourritures.append(p)
	nourritures.sort_custom(func(a, b): return a.distance < b.distance)
	return nourritures

func _rafraichir_barre() -> void:
	var f := clampf(entite.proprietes.reserves.vie.reserve / vie_max, 0.0, 1.0)
	_materiau_vie.set_shader_parameter("fraction", f)
