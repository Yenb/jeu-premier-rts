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
# ---- LES QUATRE FLECHES ----
# HAUT et BAS avancent et reculent. GAUCHE et DROITE font TOURNER, elles ne
# glissent pas de cote : c'est le meme pivot que la souris, en plus grossier et
# sans souris.
#
# LES ACTIONS SONT CELLES DE GODOT (`ui_up`, `ui_left`...), deja liees aux
# fleches par defaut : aucune table d'entrees a remplir, et un clavier qui n'est
# pas azerty marche tout de suite.
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

	var horizontale := vitesse_voulue(
		global_transform.basis, Input.get_axis("ui_down", "ui_up"), vitesse)
	velocity.x = horizontale.x
	velocity.z = horizontale.z

	# LA CHUTE S'ACCUMULE, elle ne se repose pas a chaque pas : une vitesse
	# verticale remise a zero chaque image ferait descendre les pentes par petits
	# sauts au lieu d'y glisser.
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravite * delta

	move_and_slide()
