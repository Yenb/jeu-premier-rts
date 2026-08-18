extends CharacterBody3D

# UN PERSONNAGE QU'ON DEPLACE AU CLAVIER, VU A LA PREMIERE PERSONNE. Il sert a
# ARPENTER le terrain et le couvert -- verifier a hauteur d'homme qu'un tronc
# barre le passage, qu'une touffe est a la bonne echelle, qu'une pente se monte.
#
# CE FICHIER NE SIMULE RIEN DU MONDE. Il ne connait ni plante, ni ressource, ni
# unite : il lit des touches, il pose une vitesse, le moteur physique fait le
# reste. Rien de ce qu'il fait n'entre dans l'etat de la simulation, et le couvert
# tourne identiquement sans lui (CLAUDE.md, « La simulation ne depend JAMAIS de
# l'affichage »).
#
# ---- LES QUATRE FLECHES, ET POURQUOI CELLES-LA FONT CA ----
# HAUT et BAS avancent et reculent. GAUCHE et DROITE font TOURNER, elles ne
# glissent pas de cote : sans souris, tourner est le seul moyen de regarder
# ailleurs, et une vue premiere personne qui ne peut pas pivoter ne montre qu'un
# couloir. Le jour ou la souris entre dans le jeu, ce sont ces deux touches qui
# se liberent pour le pas de cote.
#
# LES ACTIONS SONT CELLES DE GODOT (`ui_up`, `ui_bas`...), deja liees aux fleches
# par defaut : aucune table d'entrees a remplir, et un clavier qui n'est pas
# azerty marche tout de suite.
#
# ---- LA GEOMETRIE VIENT DE LA CARTE, PAS D'UN GOUT ----
# Une cellule du terrain fait 2 m. Le personnage en fait 1, soit une demi-cellule
# -- c'est ce rapport qui donne l'echelle a tout le reste : un arbre mature de
# 7,5 m fait sept fois sa taille, une touffe d'herbe lui monte au genou.
#
# SA HITBOX EST UNE CAPSULE, posee sur ses pieds : l'origine du noeud est au SOL,
# pas au centre du corps, si bien qu'on le pose sur le terrain a la hauteur du
# terrain, sans correction. Le collisionneur vit dans la scene
# (jeu/unites/personnage.tscn), jamais fabrique ici -- le game designer doit
# pouvoir l'elargir a l'inspecteur.
#
# Entree : les quatre fleches. Sortie : sa position et son orientation, lues par
# le moteur physique et par sa camera. Il n'est appele par personne.
#
# Regles tenues : positions en Vector3. Aucun hasard. Aucun texte joueur. Aucune
# categorie du monde nommee. Rien de scripts/, data/ ni addons/ n'est ecrit.

# Metres par seconde. A hauteur d'homme sur des cellules de 2 m, 3 m/s traverse
# une cellule et demie par seconde -- assez pour couvrir du terrain, assez lent
# pour voir ou l'on met les pieds.
@export var vitesse: float = 3.0

# Radians par seconde. Un demi-tour en une seconde et demie environ.
@export var vitesse_rotation: float = 2.2

# Metres par seconde carree, vers le bas. Il ne vole pas : sans elle il resterait
# suspendu la ou on l'a pose, et le relief ne voudrait plus rien dire.
@export var gravite: float = 18.0

# ---- LE CALCUL, SORTI DE _physics_process ----
#
# Les deux fonctions ci-dessous sont STATIQUES et PURES : elles ne lisent aucune
# touche, ne touchent aucun noeud, et se verrouillent donc sans clavier ni moteur
# physique (jeu/unites/test_personnage.gd). _physics_process ne fait plus que
# DECLENCHER -- il lit les touches, appelle, et pose le resultat. Un comportement
# enferme dans _physics_process regresse en silence : la regle est dans
# CLAUDE.md, « Regle d'etat ».

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
