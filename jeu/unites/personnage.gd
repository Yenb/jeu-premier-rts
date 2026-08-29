extends CharacterBody3D

# UN PERSONNAGE QU'ON DEPLACE AU CLAVIER ET QU'ON ORIENTE A LA SOURIS, VU A LA
# PREMIERE PERSONNE. Il sert a ARPENTER le terrain et le couvert -- verifier a
# hauteur d'homme qu'un tronc barre le passage, qu'une touffe est a la bonne
# echelle, qu'une pente se monte.
#
# CE FICHIER NE SIMULE RIEN DU MONDE. Il ne connait ni plante, ni ressource, ni
# unite : il lit des touches et un deplacement de souris, il pose une vitesse et
# une orientation, le moteur physique fait le reste. Rien de ce qu'il fait
# n'entre dans l'etat de la simulation, et le couvert tourne identiquement sans
# lui (CLAUDE.md, « La simulation ne depend JAMAIS de l'affichage »).
#
# ---- LES QUATRE FLECHES ET L'ESPACE ----
# HAUT et BAS avancent et reculent. GAUCHE et DROITE font TOURNER, elles ne
# glissent pas de cote : c'est le meme pivot que la souris, en plus grossier et
# sans souris. ESPACE (ou ENTREE) fait SAUTER, une IMPULSION verticale qui ne se
# declenche que lorsque le personnage TOUCHE LE SOL -- sans quoi il sauterait en
# l'air, monterait indefiniment en maintenant la touche, ou sauterait a nouveau
# en chute libre. C'est un evenement, pas un etat : la touche relachee puis
# repressee redeclenche, tant qu'on est de nouveau au sol.
#
# LES ACTIONS SONT CELLES DE GODOT (`ui_up`, `ui_left`, `ui_accept`...), deja
# liees aux fleches et a l'espace par defaut : aucune table d'entrees a remplir,
# et un clavier qui n'est pas azerty marche tout de suite.
#
# ---- LA SOURIS ----
# SON DEPLACEMENT HORIZONTAL FAIT PIVOTER LE CORPS, SON DEPLACEMENT VERTICAL
# INCLINE LES YEUX SEULS. Le corps ne penche JAMAIS : une capsule inclinee
# glisse sur le terrain au lieu de s'y tenir, et c'est l'orientation du corps
# que lit la marche.
#
# L'INCLINAISON EST BORNEE sous le quart de tour. Au-dela, un geste continu fait
# passer le regard par la verticale et RETOURNE l'image : la souris pilote alors
# le lacet a l'envers de ce que le joueur voit. La marche, elle, ne risque rien
# -- elle lit l'orientation du CORPS, que le tangage ne touche jamais.
#
# ELLE S'ACCUMULE : une souris rend un DEPLACEMENT, jamais une position. Un
# angle recalcule a neuf a chaque evenement ramenerait le regard a l'horizontale
# entre deux mouvements.
#
# LE CURSEUR SE CAPTURE AU PREMIER CLIC, JAMAIS AU DEMARRAGE. Sans capture il
# sort de la fenetre et le regard se bloque au bord ; capture d'office, il est
# pris avant que le joueur ait rien demande, a chaque lancement. ECHAP le rend.
#
# LE PRIX, ASSUME : tant qu'on n'a pas clique une fois, la souris ne fait rien.
# C'est le seul etat ou le joueur garde son curseur pour toucher autre chose que
# le jeu -- une fenetre qui reprend le curseur des qu'on le lui rend enferme.
#
# ---- LA GEOMETRIE VIENT DE LA CARTE, PAS D'UN GOUT ----
# Une cellule du terrain fait 2 m. Le personnage en fait 1, soit une demi-cellule
# -- c'est ce rapport qui donne l'echelle a tout le reste : un arbre mature de
# 7,5 m fait sept fois sa taille, une touffe d'herbe lui monte au genou.
#
# SA HITBOX EST UNE CAPSULE, posee sur ses pieds : l'origine du noeud est au SOL,
# pas au centre du corps, si bien qu'on le pose sur le terrain a la hauteur du
# terrain, sans correction. Le collisionneur et la camera vivent dans la scene
# (jeu/unites/personnage.tscn), jamais fabriques ici -- le game designer doit
# pouvoir les regler a l'inspecteur.
#
# Entree : les quatre fleches, le deplacement de la souris, ECHAP et le clic.
# Sortie : sa position, son orientation et l'inclinaison de ses yeux, lues par le
# moteur physique et par sa camera. Il n'est appele par personne.
#
# Regles tenues : positions en Vector3. Aucun hasard. Aucun texte joueur. Aucune
# categorie du monde nommee. Rien de scripts/, data/ ni documents/ n'est ecrit.

# Metres par seconde. A hauteur d'homme sur des cellules de 2 m, 3 m/s traverse
# une cellule et demie par seconde -- assez pour couvrir du terrain, assez lent
# pour voir ou l'on met les pieds.
@export var vitesse: float = 3.0

# Radians par seconde. Un demi-tour en une seconde et demie environ.
@export var vitesse_rotation: float = 2.2

# Radians par pixel de deplacement de souris. Un ecran de mille pixels de large
# balaye un peu plus d'un demi-tour.
@export var sensibilite_souris: float = 0.003

# Radians. Reste sous le quart de tour -- voir l'en-tete, « L'INCLINAISON EST
# BORNEE ».
@export var inclinaison_max: float = 1.5

# Metres par seconde carree, vers le bas. Il ne vole pas : sans elle il resterait
# suspendu la ou on l'a pose, et le relief ne voudrait plus rien dire.
@export var gravite: float = 18.0

# Metres par seconde, vitesse verticale INITIALE d'un saut. La HAUTEUR atteinte
# vaut vitesse_saut^2 / (2 * gravite) -- 8.5 m/s sous 18 m/s^2 monte a 2 m, soit
# deux fois la taille du personnage.
@export var vitesse_saut: float = 8.5

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
# Seuils sur l'axe endurance (unites). Au-dessus de plein : sprint max.
# Entre plein et marche : lerp vers vitesse de marche. Sous marche : lerp
# entre marche et essouffle.
const ENDURANCE_SEUIL_SPRINT_PLEIN := 5.0
const ENDURANCE_SEUIL_MARCHE := 3.0

var _endurance: float = 10.0
var _hud_endurance_fond: ColorRect = null
var _hud_endurance_barre: ColorRect = null

# FAIM. Barre 50, vidage cumule selon les actions actives.
# Base "juste exister" -1/s. +1/s si le joueur bouge (touche HAUT/BAS). +1/s
# si combat/tire (bouton souris tenu). Le total est double si SPRINT tenu.
# Se remplit uniquement en mangeant (nourrir()).
@export var faim_max: float = 50.0
@export var faim_vidage_base: float = 1.0
@export var faim_vidage_bouge: float = 1.0
@export var faim_vidage_combat: float = 1.0
@export var faim_facteur_sprint: float = 2.0
var _faim: float = 50.0
var _hud_faim_fond: ColorRect = null
var _hud_faim_label: Label = null
var _hud_endurance_label: Label = null

# INANITION. Compteur temps depuis dernier nourrir(). Trois seuils :
# 60 s -> vitesse x0.85. 120 s -> vitesse x0.65 + 1 PV/s draine. 180 s ->
# vitesse x0.40 + 2 PV/s. Le facteur multiplie vitesse_effective (n'ecrase
# rien). Le drain est cumule en float et applique au manager par entier.
var _temps_sans_manger: float = 0.0
var _pv_accumule_a_retirer: float = 0.0
var _hud_inanition_fond: ColorRect = null
var _hud_inanition_barre: ColorRect = null
var _hud_inanition_label: Label = null
const INANITION_SEUIL_LEGER := 60.0
const INANITION_SEUIL_MOYEN := 120.0
const INANITION_SEUIL_LOURD := 180.0
const INANITION_FACTEUR_LEGER := 0.85
const INANITION_FACTEUR_MOYEN := 0.65
const INANITION_FACTEUR_LOURD := 0.40
const INANITION_DRAIN_MOYEN := 1.0
const INANITION_DRAIN_LOURD := 2.0
var _hud_faim_barre: ColorRect = null

# La camera vit dans la scene ; ce script ne fait qu'incliner celle qui s'y
# trouve, il n'en fabrique aucune.
@onready var _yeux: Camera3D = $Yeux

# ---- LE CALCUL, SORTI DE _physics_process ET DE _unhandled_input ----
#
# Les quatre fonctions ci-dessous sont STATIQUES et PURES : elles ne lisent
# aucune touche, aucun evenement, ne touchent aucun noeud, et se verrouillent
# donc sans clavier, sans souris et sans moteur physique
# (jeu/unites/test_personnage.gd). Ce qui reste ne fait plus que DECLENCHER --
# lire l'entree, appeler, poser le resultat. Un comportement enferme dans un
# rappel du moteur regresse en silence : la regle est dans CLAUDE.md, « Regle
# d'etat ».

# LA VITESSE HORIZONTALE VOULUE, dans le repere du monde. L'axe -Z d'une Basis
# est le « devant » en Godot : avancer, c'est aller vers ou l'on regarde, et cette
# seule ligne fait que tourner change la direction de la marche sans qu'on ait a
# le dire.
static func vitesse_voulue(orientation: Basis, avance: float, vitesse_marche: float) -> Vector3:
	var devant := -orientation.z
	devant.y = 0.0
	if devant.length_squared() <= 0.0:
		return Vector3.ZERO
	return devant.normalized() * (avance * vitesse_marche)

# L'ANGLE A AJOUTER CE PAS. `pivot` vaut +1 quand la touche DROITE est enfoncee ;
# tourner a droite est une rotation NEGATIVE autour de l'axe vertical en Godot,
# d'ou le signe -- l'oublier fait un personnage qui va a gauche quand on lui dit
# droite, ce qu'aucun test de distance ne verrait.
static func rotation_voulue(pivot: float, vitesse_pivot: float, delta: float) -> float:
	return -pivot * vitesse_pivot * delta

# L'ANGLE A AJOUTER POUR UN DEPLACEMENT DE SOURIS. Souris vers la DROITE
# (deplacement positif), rotation NEGATIVE : meme convention de signe que
# rotation_voulue, et le meme piege a tenir.
#
# AUCUN delta ICI, et c'est ce qui la separe de la rotation au clavier : une
# touche enfoncee est un ETAT que le temps integre, un deplacement de souris est
# un EVENEMENT deja proportionnel au geste. Le multiplier par delta rendrait la
# visee dependante de la machine.
static func pivot_souris(deplacement_x: float, sensibilite: float) -> float:
	return -deplacement_x * sensibilite

# L'INCLINAISON DES YEUX, ACCUMULEE PUIS BORNEE. Souris vers le HAUT
# (deplacement NEGATIF en Godot), regard vers le haut : d'ou la soustraction.
static func inclinaison_voulue(inclinaison: float, deplacement_y: float,
		sensibilite: float, borne: float) -> float:
	return clampf(inclinaison - deplacement_y * sensibilite, -borne, borne)

# CE QUE LA SOURIS PILOTE, ce pas. Rend `false` des que le curseur n'est plus
# capture : sans cette garde, bouger la souris pour cliquer ailleurs ferait
# pivoter le personnage a l'insu du joueur.
static func souris_pilote(mode_curseur: int, mode_capture: int) -> bool:
	return mode_curseur == mode_capture

# VITESSE EFFECTIVE selon endurance et sprint. Statique / pure -- testable
# headless sans clavier ni HUD. Sans sprint : marche a v_marche. Avec sprint :
# trois zones. Au-dessus du seuil "sprint plein" : v_sprint. Entre les deux
# seuils : lerp entre v_marche et v_sprint (fatigue progressive). Sous le
# seuil "marche" : lerp entre v_essouffle et v_marche (essouffle, plus lent
# que la marche normale).
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

	rotate_y(pivot_souris(evenement.relative.x, sensibilite_souris))
	_yeux.rotation.x = inclinaison_voulue(
		_yeux.rotation.x, evenement.relative.y, sensibilite_souris, inclinaison_max)

func _physics_process(delta: float) -> void:
	rotate_y(rotation_voulue(
		Input.get_axis("ui_left", "ui_right"), vitesse_rotation, delta))

	# Endurance : vide au sprint tenu, remplit sinon. La vitesse decoule.
	var sprint: bool = Input.is_physical_key_pressed(KEY_SHIFT)
	if sprint:
		_endurance = maxf(0.0, _endurance - (endurance_max / endurance_temps_vidage) * delta)
	else:
		_endurance = minf(endurance_max, _endurance + (endurance_max / endurance_temps_remplissage) * delta)
	_rafraichir_hud_endurance()
	# Faim : vidage cumule (base + bouge + combat) x2 si sprint.
	var bouge: bool = Input.get_axis("ui_down", "ui_up") != 0.0
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
	# Inanition : compteur monte tant qu'on n'a pas mange. Facteur applique
	# sur la vitesse effective (n'ecrase rien). Drain PV cumule en float,
	# envoye au manager quand accumule >= 1.
	# Le compteur d'inanition monte quand la faim est vide (corps consomme
	# ses tissus) et redescend progressivement quand elle est > 0 (recuperation
	# des reserves). Symetrique : autant de temps a recuperer qu'a s'affamer.
	if _faim <= 0.0:
		_temps_sans_manger += delta
	else:
		_temps_sans_manger = maxf(0.0, _temps_sans_manger - delta)
	_rafraichir_hud_inanition()
	var facteur_inanition: float = 1.0
	var drain_pv: float = 0.0
	if _temps_sans_manger >= INANITION_SEUIL_LOURD:
		facteur_inanition = INANITION_FACTEUR_LOURD
		drain_pv = INANITION_DRAIN_LOURD
	elif _temps_sans_manger >= INANITION_SEUIL_MOYEN:
		facteur_inanition = INANITION_FACTEUR_MOYEN
		drain_pv = INANITION_DRAIN_MOYEN
	elif _temps_sans_manger >= INANITION_SEUIL_LEGER:
		facteur_inanition = INANITION_FACTEUR_LEGER
	if drain_pv > 0.0:
		_pv_accumule_a_retirer += drain_pv * delta
		if _pv_accumule_a_retirer >= 1.0:
			var q: int = int(floor(_pv_accumule_a_retirer))
			_pv_accumule_a_retirer -= float(q)
			var manager := get_tree().get_first_node_in_group(&"manager_proto")
			if manager != null and manager.has_method("retirer_pv_joueur"):
				manager.call("retirer_pv_joueur", float(q))
	var v_effective: float = vitesse_effective(sprint, _endurance,
		vitesse, vitesse * vitesse_sprint_facteur, vitesse_essouffle) * facteur_inanition
	var horizontale := vitesse_voulue(
		global_transform.basis, Input.get_axis("ui_down", "ui_up"), v_effective)
	velocity.x = horizontale.x
	velocity.z = horizontale.z

	# LA CHUTE S'ACCUMULE, elle ne se repose pas a chaque pas : une vitesse
	# verticale remise a zero chaque image ferait descendre les pentes par petits
	# sauts au lieu d'y glisser.
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravite * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = vitesse_saut

	move_and_slide()

func _ready() -> void:
	_preparer_hud_endurance()
	_preparer_hud_faim()
	_preparer_hud_inanition()

# API PUBLIQUE : consommer de la nourriture (appelee par l'inspecteur au clic
# sur un bloc bleu). Ajoute a la faim, borne au max.
func nourrir(quantite: float) -> void:
	_faim = minf(faim_max, _faim + quantite)
	# Le compteur d'inanition ne se reset PAS instantanement : manger repose
	# la faim, la recuperation du compteur se fait progressivement dans
	# _physics_process (delta par delta) tant que faim > 0.
	_rafraichir_hud_faim()

# BARRE ENDURANCE (HUD 2D, haut-droit). Fabriquee en code, pas de TSCN. Fond
# sombre + remplissage colore selon niveau (vert / jaune / rouge).
func _preparer_hud_endurance() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	_hud_endurance_fond = ColorRect.new()
	_hud_endurance_fond.color = Color(0.1, 0.1, 0.1, 0.85)
	_hud_endurance_fond.anchor_left = 1.0
	_hud_endurance_fond.anchor_right = 1.0
	_hud_endurance_fond.anchor_top = 0.0
	_hud_endurance_fond.anchor_bottom = 0.0
	_hud_endurance_fond.offset_left = -220
	_hud_endurance_fond.offset_right = -20
	_hud_endurance_fond.offset_top = 20
	_hud_endurance_fond.offset_bottom = 50
	canvas.add_child(_hud_endurance_fond)
	_hud_endurance_barre = ColorRect.new()
	_hud_endurance_barre.color = Color(0.2, 0.85, 0.3, 1.0)
	_hud_endurance_barre.anchor_left = 0.0
	_hud_endurance_barre.anchor_top = 0.0
	_hud_endurance_barre.anchor_right = 1.0
	_hud_endurance_barre.anchor_bottom = 1.0
	_hud_endurance_barre.offset_left = 3
	_hud_endurance_barre.offset_top = 3
	_hud_endurance_barre.offset_right = -3
	_hud_endurance_barre.offset_bottom = -3
	_hud_endurance_fond.add_child(_hud_endurance_barre)
	# Label "SPRINT" a gauche de la barre (dans la meme canvas layer).
	_hud_endurance_label = Label.new()
	_hud_endurance_label.text = "SPRINT"
	_hud_endurance_label.anchor_left = 1.0
	_hud_endurance_label.anchor_right = 1.0
	_hud_endurance_label.anchor_top = 0.0
	_hud_endurance_label.anchor_bottom = 0.0
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
	# Couleur : verte au-dessus du seuil plein, jaune entre les deux seuils,
	# rouge sous le seuil marche.
	if _endurance >= ENDURANCE_SEUIL_SPRINT_PLEIN:
		_hud_endurance_barre.color = Color(0.2, 0.85, 0.3, 1.0)
	elif _endurance >= ENDURANCE_SEUIL_MARCHE:
		_hud_endurance_barre.color = Color(0.9, 0.75, 0.15, 1.0)
	else:
		_hud_endurance_barre.color = Color(0.85, 0.2, 0.15, 1.0)

# BARRE FAIM (HUD 2D). Empilee juste sous la barre de sprint. Meme largeur.
# Couleur orange constant -- pas de code visuel par seuil, seul le remplissage
# renseigne l'etat.
func _preparer_hud_faim() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	_hud_faim_fond = ColorRect.new()
	_hud_faim_fond.color = Color(0.1, 0.1, 0.1, 0.85)
	_hud_faim_fond.anchor_left = 1.0
	_hud_faim_fond.anchor_right = 1.0
	_hud_faim_fond.anchor_top = 0.0
	_hud_faim_fond.anchor_bottom = 0.0
	_hud_faim_fond.offset_left = -220
	_hud_faim_fond.offset_right = -20
	_hud_faim_fond.offset_top = 55
	_hud_faim_fond.offset_bottom = 85
	canvas.add_child(_hud_faim_fond)
	_hud_faim_barre = ColorRect.new()
	_hud_faim_barre.color = Color(0.95, 0.55, 0.15, 1.0)
	_hud_faim_barre.anchor_left = 0.0
	_hud_faim_barre.anchor_top = 0.0
	_hud_faim_barre.anchor_right = 1.0
	_hud_faim_barre.anchor_bottom = 1.0
	_hud_faim_barre.offset_left = 3
	_hud_faim_barre.offset_top = 3
	_hud_faim_barre.offset_right = -3
	_hud_faim_barre.offset_bottom = -3
	_hud_faim_fond.add_child(_hud_faim_barre)
	# Label "FAIM" a gauche de la barre.
	_hud_faim_label = Label.new()
	_hud_faim_label.text = "FAIM"
	_hud_faim_label.anchor_left = 1.0
	_hud_faim_label.anchor_right = 1.0
	_hud_faim_label.anchor_top = 0.0
	_hud_faim_label.anchor_bottom = 0.0
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

# BARRE INANITION (3e barre HUD, sous FAIM). Pleine = "vient de manger"
# (0 s), vide = seuil lourd atteint (180 s). Couleur rouge sombre.
func _preparer_hud_inanition() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	_hud_inanition_fond = ColorRect.new()
	_hud_inanition_fond.color = Color(0.1, 0.1, 0.1, 0.85)
	_hud_inanition_fond.anchor_left = 1.0
	_hud_inanition_fond.anchor_right = 1.0
	_hud_inanition_fond.anchor_top = 0.0
	_hud_inanition_fond.anchor_bottom = 0.0
	_hud_inanition_fond.offset_left = -220
	_hud_inanition_fond.offset_right = -20
	_hud_inanition_fond.offset_top = 90
	_hud_inanition_fond.offset_bottom = 120
	canvas.add_child(_hud_inanition_fond)
	_hud_inanition_barre = ColorRect.new()
	_hud_inanition_barre.color = Color(0.7, 0.1, 0.1, 1.0)
	_hud_inanition_barre.anchor_left = 0.0
	_hud_inanition_barre.anchor_top = 0.0
	_hud_inanition_barre.anchor_right = 1.0
	_hud_inanition_barre.anchor_bottom = 1.0
	_hud_inanition_barre.offset_left = 3
	_hud_inanition_barre.offset_top = 3
	_hud_inanition_barre.offset_right = -3
	_hud_inanition_barre.offset_bottom = -3
	_hud_inanition_fond.add_child(_hud_inanition_barre)
	# MARQUEURS DE PALIERS. Deux fines barres noires verticales aux seuils
	# 60 s (leger) et 120 s (moyen). Le seuil 180 s est deja le bord droit.
	# Ratio de remplissage inverse : 60 s -> 66 % (1 - 60/180), 120 s -> 33 %.
	_ajouter_marqueur_inanition(1.0 - INANITION_SEUIL_LEGER / INANITION_SEUIL_LOURD)
	_ajouter_marqueur_inanition(1.0 - INANITION_SEUIL_MOYEN / INANITION_SEUIL_LOURD)
	_hud_inanition_label = Label.new()
	_hud_inanition_label.text = "INANITION"
	_hud_inanition_label.anchor_left = 1.0
	_hud_inanition_label.anchor_right = 1.0
	_hud_inanition_label.anchor_top = 0.0
	_hud_inanition_label.anchor_bottom = 0.0
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
	# Pleine a 0 s, vide au seuil lourd. Clamp au cas ou le compteur depasse.
	var ratio: float = clampf(1.0 - _temps_sans_manger / INANITION_SEUIL_LOURD, 0.0, 1.0)
	_hud_inanition_barre.anchor_right = ratio

# Ajoute une fine barre noire verticale dans le fond de la barre inanition,
# a la position `ratio` (0.0 = gauche, 1.0 = droite).
func _ajouter_marqueur_inanition(ratio: float) -> void:
	var marqueur := ColorRect.new()
	marqueur.color = Color(0.0, 0.0, 0.0, 1.0)
	marqueur.anchor_left = ratio
	marqueur.anchor_right = ratio
	marqueur.anchor_top = 0.0
	marqueur.anchor_bottom = 1.0
	marqueur.offset_left = -1
	marqueur.offset_right = 1
	marqueur.offset_top = 0
	marqueur.offset_bottom = 0
	# Enfant du FOND : le marqueur reste visible meme quand la barre de
	# remplissage a passe dessous (rangee au-dessus dans l'ordre des enfants).
	_hud_inanition_fond.add_child(marqueur)
