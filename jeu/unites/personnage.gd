extends Node3D

# UN PERSONNAGE QU'ON DEPLACE AU CLAVIER ET QU'ON ORIENTE A LA SOURIS, VU A LA
# PREMIERE PERSONNE. Il sert a ARPENTER le terrain et le couvert -- verifier a
# hauteur d'homme qu'un tronc barre le passage, qu'une touffe est a la bonne
# echelle, qu'une pente se monte.
#
# CE N'EST PLUS UN CharacterBody3D. Le joueur est une ENTITE DATA du Monde,
# comme les cubes : sa position fait autorite en donnee, et c'est collision.gd
# (joueur contre cubes) plus carte.sommet (sol, pente, chute) qui la deplacent,
# jamais le moteur physique Godot. Ce nœud ne fait que : lire les touches et la
# souris, RENDRE une intention de mouvement au manager qui l'appelle, porter le
# rendu (capsule visible, marqueur de debug a la position exacte, camera), et
# tenir les barres du joueur (endurance, faim, inanition).
#
# QUI ECRIT QUOI SUR CE NŒUD. La POSITION est ecrite par le manager
# (manager_proto_2), seule autorite : le rendu suit la donnee. La ROTATION (lacet
# du corps) et le TANGAGE (camera Yeux) sont pilotes ici, par l'entree du joueur.
# Ils n'entrent PAS dans la collision : la capsule est a symetrie de revolution
# autour de Y, donc l'orientation ne change aucun contact. Le jour ou le joueur
# porte une forme orientee (cone, chariot), l'orientation devra passer par la
# donnee -- pas aujourd'hui.
#
# ORDRE D'EXECUTION SANS COURSE. Le manager APPELLE intention_mouvement(delta) au
# moment ou il en a besoin ; l'intention (horizontale + saut) est lue a l'instant
# de l'appel, jamais posee dans une variable qu'un autre tick lirait avec un
# frame de retard. Aucune dependance a l'ordre de l'arbre.
#
# ---- LES QUATRE FLECHES ET L'ESPACE ----
# HAUT et BAS avancent et reculent. GAUCHE et DROITE font TOURNER, elles ne
# glissent pas de cote : le meme pivot que la souris, en plus grossier. ESPACE
# (ou ENTREE) fait SAUTER : le manager n'applique l'impulsion que si l'entite est
# AU SOL en donnee (au_sol, derive de carte.sommet). C'est un evenement, pas un
# etat.
#
# ---- LA SOURIS ----
# SON DEPLACEMENT HORIZONTAL FAIT PIVOTER LE CORPS (lacet accumule dans _lacet),
# SON DEPLACEMENT VERTICAL INCLINE LES YEUX SEULS (tangage accumule dans
# _tangage, borne sous le quart de tour). Le corps ne penche jamais : la marche
# lit le lacet, que le tangage ne touche pas. Le curseur se prend au premier clic
# ou au demarrage, ECHAP le rend.
#
# ---- LA GEOMETRIE VIENT DES DONNEES ----
# Les dimensions (rayon/hauteur de capsule, hauteur des yeux) et les vitesses
# (marche, saut) sont portees par l'entite joueur dans le Monde (voir
# manager_proto_2). Le manager les injecte ici par configurer_depuis_donnees des
# que l'entite existe : le mesh capsule est dimensionne, la camera posee a
# hauteur des yeux, les visibilites du corps et du marqueur reglees. A defaut
# d'entite (scene sans manager), les valeurs par defaut ci-dessous servent, et
# elles valent celles de la donnee.
#
# Entree : les quatre fleches, la souris, ECHAP, le clic. Sortie : une intention
# de mouvement (rendue au manager), sa rotation et l'inclinaison de ses yeux.
#
# Regles tenues : positions en Vector3. Aucun hasard. Aucun texte joueur. Aucune
# categorie du monde nommee. Rien de scripts/, data/ ni documents/ n'est ecrit.

# Radians par seconde. Un demi-tour en une seconde et demie environ.
@export var vitesse_rotation: float = 2.2

# Radians par pixel de deplacement de souris. Un ecran de mille pixels de large
# balaye un peu plus d'un demi-tour.
@export var sensibilite_souris: float = 0.003

# Radians. Reste sous le quart de tour -- voir l'en-tete, « LA SOURIS ».
@export var inclinaison_max: float = 1.5

# Multiplicateur de vitesse au sprint plein. La vitesse effective decroit
# ensuite avec l'endurance (voir vitesse_effective).
@export var vitesse_sprint_facteur: float = 2.0

# ENDURANCE. Une barre en unites, se vide en `endurance_temps_vidage` secondes
# sous sprint tenu, se remplit en `endurance_temps_remplissage` secondes hors
# sprint. Seuils definissent trois zones de vitesse (voir vitesse_effective).
@export var endurance_max: float = 10.0
@export var endurance_temps_vidage: float = 9.0
@export var endurance_temps_remplissage: float = 15.0
# Vitesse "essouffle" quand l'endurance atteint zero -- plus lent que la
# marche normale, force le joueur a lacher SHIFT et attendre.
@export var vitesse_essouffle: float = 2.0
const ENDURANCE_SEUIL_SPRINT_PLEIN := 5.0
const ENDURANCE_SEUIL_MARCHE := 3.0

# FAIM. Barre, vidage cumule selon les actions actives.
@export var faim_max: float = 2500.0
@export var faim_vidage_base: float = 1.0
@export var faim_vidage_bouge: float = 1.0
@export var faim_vidage_combat: float = 1.0
@export var faim_facteur_sprint: float = 2.0

# INANITION. Compteur temps depuis dernier nourrir(). Trois seuils.
const INANITION_SEUIL_LEGER := 6000.0
const INANITION_SEUIL_MOYEN := 12000.0
const INANITION_SEUIL_LOURD := 18000.0
const INANITION_FACTEUR_LEGER := 0.85
const INANITION_FACTEUR_MOYEN := 0.65
const INANITION_FACTEUR_LOURD := 0.40
const INANITION_DRAIN_MOYEN := 1.0
const INANITION_DRAIN_LOURD := 2.0

# ---- DEFAUTS DES DONNEES (surcharges par configurer_depuis_donnees) ----
var _rayon_capsule: float = 0.4
var _hauteur_capsule: float = 1.8
var _hauteur_yeux: float = 1.7
var _vitesse_marche: float = 4.0
var _vitesse_saut: float = 8.5

# ---- ETAT ----
var _lacet: float = 0.0     # rotation Y du corps, accumulee (souris + clavier)
var _tangage: float = 0.0   # inclinaison X des yeux, accumulee et bornee
var _endurance: float = 10.0
var _faim: float = 2500.0
var _temps_sans_manger: float = 0.0
var _pv_accumule_a_retirer: float = 0.0
var _facteur_inanition: float = 1.0

var _hud_endurance_fond: ColorRect = null
var _hud_endurance_barre: ColorRect = null
var _hud_endurance_label: Label = null
var _hud_faim_fond: ColorRect = null
var _hud_faim_barre: ColorRect = null
var _hud_faim_label: Label = null
var _hud_inanition_fond: ColorRect = null
var _hud_inanition_barre: ColorRect = null
var _hud_inanition_label: Label = null

@onready var _yeux: Camera3D = $Yeux
@onready var _corps_visible: MeshInstance3D = $corps_visible
@onready var _marqueur_debug: MeshInstance3D = $marqueur_debug

# ---- LE CALCUL PUR (statique, testable sans clavier ni moteur) ----
# Ces fonctions ne lisent aucune touche, aucun evenement, ne touchent aucun nœud.
# Elles se verrouillent headless (jeu/unites/test_personnage.gd).

# LA VITESSE HORIZONTALE VOULUE, dans le repere du monde. L'axe -Z d'une Basis est
# le « devant » en Godot : avancer, c'est aller vers ou l'on regarde.
static func vitesse_voulue(orientation: Basis, avance: float, vitesse_marche: float) -> Vector3:
	var devant := -orientation.z
	devant.y = 0.0
	if devant.length_squared() <= 0.0:
		return Vector3.ZERO
	return devant.normalized() * (avance * vitesse_marche)

# L'ANGLE A AJOUTER CE PAS. `pivot` vaut +1 quand DROITE est enfoncee ; tourner a
# droite est une rotation NEGATIVE autour de l'axe vertical en Godot.
static func rotation_voulue(pivot: float, vitesse_pivot: float, delta: float) -> float:
	return -pivot * vitesse_pivot * delta

# L'ANGLE A AJOUTER POUR UN DEPLACEMENT DE SOURIS. Souris a DROITE, rotation
# NEGATIVE. AUCUN delta : un deplacement de souris est un EVENEMENT deja
# proportionnel au geste, pas un etat que le temps integre.
static func pivot_souris(deplacement_x: float, sensibilite: float) -> float:
	return -deplacement_x * sensibilite

# L'INCLINAISON DES YEUX, ACCUMULEE PUIS BORNEE. Souris vers le HAUT (deplacement
# NEGATIF en Godot), regard vers le haut : d'ou la soustraction.
static func inclinaison_voulue(inclinaison: float, deplacement_y: float,
		sensibilite: float, borne: float) -> float:
	return clampf(inclinaison - deplacement_y * sensibilite, -borne, borne)

# CE QUE LA SOURIS PILOTE, ce pas. `false` des que le curseur n'est plus capture.
static func souris_pilote(mode_curseur: int, mode_capture: int) -> bool:
	return mode_curseur == mode_capture

# VITESSE EFFECTIVE selon endurance et sprint. Statique / pure.
static func vitesse_effective(sprint: bool, endurance: float,
		v_marche: float, v_sprint: float, v_essouffle: float) -> float:
	if not sprint:
		return v_marche
	if endurance >= ENDURANCE_SEUIL_SPRINT_PLEIN:
		return v_sprint
	if endurance >= ENDURANCE_SEUIL_MARCHE:
		var t: float = (endurance - ENDURANCE_SEUIL_MARCHE) \
			/ (ENDURANCE_SEUIL_SPRINT_PLEIN - ENDURANCE_SEUIL_MARCHE)
		return lerp(v_marche, v_sprint, t)
	var u: float = endurance / ENDURANCE_SEUIL_MARCHE
	return lerp(v_essouffle, v_marche, u)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_preparer_hud_endurance()
	_preparer_hud_faim()
	_preparer_hud_inanition()

# INJECTION DES DONNEES, appelee par le manager des que l'entite joueur existe
# (appel direct, pas de course d'ordre au _ready). Dimensionne le mesh capsule,
# pose la camera a hauteur des yeux, regle les visibilites. Les valeurs absentes
# gardent les defauts (identiques a la donnee).
func configurer_depuis_donnees(entite: Dictionary) -> void:
	var p: Dictionary = entite.get("proprietes", {})
	_rayon_capsule = float(p.get("rayon_capsule", _rayon_capsule))
	_hauteur_capsule = float(p.get("hauteur_capsule", _hauteur_capsule))
	_hauteur_yeux = float(p.get("hauteur_yeux", _hauteur_yeux))
	_vitesse_marche = float(p.get("vitesse_marche", _vitesse_marche))
	_vitesse_saut = float(p.get("vitesse_saut", _vitesse_saut))
	if _corps_visible != null and _corps_visible.mesh is CapsuleMesh:
		var m: CapsuleMesh = _corps_visible.mesh
		m.radius = _rayon_capsule
		m.height = _hauteur_capsule
		# Origine du nœud aux PIEDS : le centre de la capsule remonte d'une
		# demi-hauteur pour que le corps repose sur le sol.
		_corps_visible.position = Vector3(0.0, _hauteur_capsule * 0.5, 0.0)
		_corps_visible.visible = bool(p.get("corps_visible", true))
	if _marqueur_debug != null:
		_marqueur_debug.visible = bool(p.get("marqueur_debug_visible", true))
	if _yeux != null:
		_yeux.position = Vector3(0.0, _hauteur_yeux, 0.0)

# L'INTENTION DE MOUVEMENT, lue A L'INSTANT par le manager qui l'appelle. Rend la
# vitesse horizontale voulue (repere monde, deduite du lacet courant), si le saut
# est demande ce pas, et la vitesse de saut a appliquer. Applique aussi la
# rotation clavier au lacet (elle depend de delta). Le manager decide de
# l'impulsion selon au_sol data.
func intention_mouvement(delta: float) -> Dictionary:
	_lacet += rotation_voulue(
		Input.get_axis("ui_left", "ui_right"), vitesse_rotation, delta)
	var sprint: bool = Input.is_physical_key_pressed(KEY_SHIFT)
	var v_eff: float = vitesse_effective(sprint, _endurance,
		_vitesse_marche, _vitesse_marche * vitesse_sprint_facteur, vitesse_essouffle) \
		* _facteur_inanition
	var base := Basis(Vector3.UP, _lacet)
	var horizontale := vitesse_voulue(base, Input.get_axis("ui_down", "ui_up"), v_eff)
	var saut: bool = Input.is_action_just_pressed("ui_accept")
	return {"horizontale": horizontale, "saut": saut, "vitesse_saut": _vitesse_saut}

func _unhandled_input(evenement: InputEvent) -> void:
	if evenement.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if evenement is InputEventMouseButton and evenement.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if not (evenement is InputEventMouseMotion):
		return
	if not souris_pilote(Input.mouse_mode, Input.MOUSE_MODE_CAPTURED):
		return
	_lacet += pivot_souris(evenement.relative.x, sensibilite_souris)
	_tangage = inclinaison_voulue(_tangage, evenement.relative.y, sensibilite_souris, inclinaison_max)

# RENDU + BARRES EN _physics_process. L'interpolation physique est active
# (project.godot) : les transforms (rotation du corps, tangage de la camera Yeux)
# doivent etre poses dans le PAS PHYSIQUE, sinon Godot avertit qu'une Camera3D
# interpolee est bougee depuis l'idle. La POSITION n'est PAS ecrite ici -- le
# manager la pose depuis la donnee. Le lacet oriente le corps, le tangage les yeux
# seuls. Le mouvement, lui, est tire par le manager via intention_mouvement.
func _physics_process(delta: float) -> void:
	rotation = Vector3(0.0, _lacet, 0.0)
	if _yeux != null:
		_yeux.rotation.x = _tangage

	var sprint: bool = Input.is_physical_key_pressed(KEY_SHIFT)
	if sprint:
		_endurance = maxf(0.0, _endurance - (endurance_max / endurance_temps_vidage) * delta)
	else:
		_endurance = minf(endurance_max, _endurance + (endurance_max / endurance_temps_remplissage) * delta)
	_rafraichir_hud_endurance()
	var bouge: bool = Input.get_axis("ui_down", "ui_up") != 0.0 \
		or Input.get_axis("ui_left", "ui_right") != 0.0
	var combat: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var taux: float = faim_vidage_base
	if bouge:
		taux += faim_vidage_bouge
	if combat:
		taux += faim_vidage_combat
	if sprint:
		taux *= faim_facteur_sprint
	_faim = maxf(0.0, _faim - taux * delta)
	_rafraichir_hud_faim()
	if _faim <= 0.0:
		_temps_sans_manger += delta
	else:
		_temps_sans_manger = maxf(0.0, _temps_sans_manger - delta)
	_rafraichir_hud_inanition()
	_facteur_inanition = 1.0
	var drain_pv: float = 0.0
	if _temps_sans_manger >= INANITION_SEUIL_LOURD:
		_facteur_inanition = INANITION_FACTEUR_LOURD
		drain_pv = INANITION_DRAIN_LOURD
	elif _temps_sans_manger >= INANITION_SEUIL_MOYEN:
		_facteur_inanition = INANITION_FACTEUR_MOYEN
		drain_pv = INANITION_DRAIN_MOYEN
	elif _temps_sans_manger >= INANITION_SEUIL_LEGER:
		_facteur_inanition = INANITION_FACTEUR_LEGER
	if drain_pv > 0.0:
		_pv_accumule_a_retirer += drain_pv * delta
		if _pv_accumule_a_retirer >= 1.0:
			var q: int = int(floor(_pv_accumule_a_retirer))
			_pv_accumule_a_retirer -= float(q)
			var manager := get_tree().get_first_node_in_group(&"manager_proto")
			if manager != null and manager.has_method("retirer_pv_joueur"):
				manager.call("retirer_pv_joueur", float(q))

# API PUBLIQUE : consommer de la nourriture. Ajoute a la faim, borne au max.
func nourrir(quantite: float) -> void:
	_faim = minf(faim_max, _faim + quantite)

# API PUBLIQUE : coût par acte de travail (creuser, plus tard couper...). Cap a 0.
func depenser_pour_travail(cout: float) -> void:
	if cout <= 0.0:
		return
	_faim = maxf(0.0, _faim - cout)
	_rafraichir_hud_faim()

func _preparer_hud_endurance() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	_hud_endurance_fond = ColorRect.new()
	_hud_endurance_fond.color = Color(0.1, 0.1, 0.1, 0.85)
	_hud_endurance_fond.anchor_left = 1.0
	_hud_endurance_fond.anchor_right = 1.0
	_hud_endurance_fond.offset_left = -220
	_hud_endurance_fond.offset_right = -20
	_hud_endurance_fond.offset_top = 20
	_hud_endurance_fond.offset_bottom = 50
	canvas.add_child(_hud_endurance_fond)
	_hud_endurance_barre = ColorRect.new()
	_hud_endurance_barre.color = Color(0.2, 0.85, 0.3, 1.0)
	_hud_endurance_barre.anchor_right = 1.0
	_hud_endurance_barre.anchor_bottom = 1.0
	_hud_endurance_barre.offset_left = 3
	_hud_endurance_barre.offset_top = 3
	_hud_endurance_barre.offset_right = -3
	_hud_endurance_barre.offset_bottom = -3
	_hud_endurance_fond.add_child(_hud_endurance_barre)
	_hud_endurance_label = Label.new()
	_hud_endurance_label.text = "SPRINT"
	_hud_endurance_label.anchor_left = 1.0
	_hud_endurance_label.anchor_right = 1.0
	_hud_endurance_label.offset_left = -290
	_hud_endurance_label.offset_right = -225
	_hud_endurance_label.offset_top = 22
	_hud_endurance_label.offset_bottom = 50
	_hud_endurance_label.add_theme_color_override("font_color", Color.WHITE)
	canvas.add_child(_hud_endurance_label)
	_rafraichir_hud_endurance()

func _rafraichir_hud_endurance() -> void:
	if _hud_endurance_barre == null:
		return
	var ratio: float = clampf(_endurance / endurance_max, 0.0, 1.0)
	_hud_endurance_barre.anchor_right = ratio
	if _endurance >= ENDURANCE_SEUIL_SPRINT_PLEIN:
		_hud_endurance_barre.color = Color(0.2, 0.85, 0.3, 1.0)
	elif _endurance >= ENDURANCE_SEUIL_MARCHE:
		_hud_endurance_barre.color = Color(0.9, 0.75, 0.15, 1.0)
	else:
		_hud_endurance_barre.color = Color(0.85, 0.2, 0.15, 1.0)

func _preparer_hud_faim() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	_hud_faim_fond = ColorRect.new()
	_hud_faim_fond.color = Color(0.1, 0.1, 0.1, 0.85)
	_hud_faim_fond.anchor_left = 1.0
	_hud_faim_fond.anchor_right = 1.0
	_hud_faim_fond.offset_left = -220
	_hud_faim_fond.offset_right = -20
	_hud_faim_fond.offset_top = 55
	_hud_faim_fond.offset_bottom = 85
	canvas.add_child(_hud_faim_fond)
	_hud_faim_barre = ColorRect.new()
	_hud_faim_barre.color = Color(0.95, 0.55, 0.15, 1.0)
	_hud_faim_barre.anchor_right = 1.0
	_hud_faim_barre.anchor_bottom = 1.0
	_hud_faim_barre.offset_left = 3
	_hud_faim_barre.offset_top = 3
	_hud_faim_barre.offset_right = -3
	_hud_faim_barre.offset_bottom = -3
	_hud_faim_fond.add_child(_hud_faim_barre)
	_hud_faim_label = Label.new()
	_hud_faim_label.text = "FAIM"
	_hud_faim_label.anchor_left = 1.0
	_hud_faim_label.anchor_right = 1.0
	_hud_faim_label.offset_left = -290
	_hud_faim_label.offset_right = -225
	_hud_faim_label.offset_top = 57
	_hud_faim_label.offset_bottom = 85
	_hud_faim_label.add_theme_color_override("font_color", Color.WHITE)
	canvas.add_child(_hud_faim_label)
	_rafraichir_hud_faim()

func _rafraichir_hud_faim() -> void:
	if _hud_faim_barre == null:
		return
	var ratio: float = clampf(_faim / faim_max, 0.0, 1.0)
	_hud_faim_barre.anchor_right = ratio

func _preparer_hud_inanition() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	_hud_inanition_fond = ColorRect.new()
	_hud_inanition_fond.color = Color(0.1, 0.1, 0.1, 0.85)
	_hud_inanition_fond.anchor_left = 1.0
	_hud_inanition_fond.anchor_right = 1.0
	_hud_inanition_fond.offset_left = -220
	_hud_inanition_fond.offset_right = -20
	_hud_inanition_fond.offset_top = 90
	_hud_inanition_fond.offset_bottom = 120
	canvas.add_child(_hud_inanition_fond)
	_hud_inanition_barre = ColorRect.new()
	_hud_inanition_barre.color = Color(0.7, 0.1, 0.1, 1.0)
	_hud_inanition_barre.anchor_right = 1.0
	_hud_inanition_barre.anchor_bottom = 1.0
	_hud_inanition_barre.offset_left = 3
	_hud_inanition_barre.offset_top = 3
	_hud_inanition_barre.offset_right = -3
	_hud_inanition_barre.offset_bottom = -3
	_hud_inanition_fond.add_child(_hud_inanition_barre)
	_ajouter_marqueur_inanition(1.0 - INANITION_SEUIL_LEGER / INANITION_SEUIL_LOURD)
	_ajouter_marqueur_inanition(1.0 - INANITION_SEUIL_MOYEN / INANITION_SEUIL_LOURD)
	_hud_inanition_label = Label.new()
	_hud_inanition_label.text = "INANITION"
	_hud_inanition_label.anchor_left = 1.0
	_hud_inanition_label.anchor_right = 1.0
	_hud_inanition_label.offset_left = -290
	_hud_inanition_label.offset_right = -225
	_hud_inanition_label.offset_top = 92
	_hud_inanition_label.offset_bottom = 120
	_hud_inanition_label.add_theme_color_override("font_color", Color.WHITE)
	canvas.add_child(_hud_inanition_label)
	_rafraichir_hud_inanition()

func _rafraichir_hud_inanition() -> void:
	if _hud_inanition_barre == null:
		return
	var ratio: float = clampf(1.0 - _temps_sans_manger / INANITION_SEUIL_LOURD, 0.0, 1.0)
	_hud_inanition_barre.anchor_right = ratio

func _ajouter_marqueur_inanition(ratio: float) -> void:
	var marqueur := ColorRect.new()
	marqueur.color = Color(0.0, 0.0, 0.0, 1.0)
	marqueur.anchor_left = ratio
	marqueur.anchor_right = ratio
	marqueur.anchor_bottom = 1.0
	marqueur.offset_left = -1
	marqueur.offset_right = 1
	_hud_inanition_fond.add_child(marqueur)
