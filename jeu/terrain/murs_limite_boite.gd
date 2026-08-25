@tool
extends StaticBody3D

# LA CEINTURE DE LA CARTE, EN QUATRE BOITES. Un mur solide et invisible, une
# cellule AU-DELA de l'emprise, pour qu'aucun corps ne quitte le plateau. Quatre
# CollisionShape3D + BoxShape3D remplacent les dizaines de milliers de cellules
# de l'ancienne ceinture GridMap. Aucun maillage : rien a rendre.
#
# Entree : la carte, qui declare son emprise (demi_cote), sa couche de base et
# l'arete de sa cellule (cote) ; une hauteur en couches ; une epaisseur.
# Sortie : quatre corps de collision poses au _ready, jamais dans la scene.
#
# LA FACE INTERNE EST CELLE DU GridMap, AU METRE PRES. La barriere ne bouge pas :
# le joueur bute exactement la ou il butait. Seule la face EXTERNE recule --
# l'epaisseur pousse vers le vide hors carte, jamais vers l'emprise jouable. C'est
# ce qui rend l'epaississement gratuit en gameplay.
#
# GEOMETRIE DEDUITE DE L'EMPRISE, jamais de map_to_local : la meme geometrie doit
# valoir sans GridMap. Convention du moteur (cellule NON centree sur les trois
# axes, verifiee : map_to_local(i) = (i+0.5)*cote) : la cellule d'indice i va de
# i*cote a (i+1)*cote. L'emprise sculptable occupe la grille [-demi_cote,
# demi_cote-1] ; sa cellule de bord +demi_cote-1 monte donc jusqu'a demi_cote*cote,
# et la ceinture commence la. Les faces internes sont a +/- demi_cote*cote.
#
# EPAISSEUR CONTRE LE TUNNELING. Un projectile rapide franchit un mur mince en une
# frame : a 100 m/s et 60 Hz il avance 1,67 m par pas, un mur de 2 m ne laisse que
# 0,33 m de marge. L'epaisseur par defaut (10 m) demande plus de 600 m/s pour etre
# traversee en un pas. Elle pousse vers l'exterieur : la face interne, donc la
# barriere, ne change pas.
#
# LES QUATRE BOITES SE CHEVAUCHENT AUX COINS : aucun trou. Nord et Sud couvrent
# toute la largeur (coins compris), Ouest et Est s'inserent entre eux.
#
# COUCHE DE COLLISION : 1, comme le GridMap de la ceinture (defaut GridMap et
# StaticBody3D). Un corps qui masque la couche 1 bute dessus.
#
# Regles tenues : positions en Vector3, jamais Vector2. Aucun hasard. Aucun texte
# visible par le joueur. Aucun nom de contenu. Rien de scripts/, data/ ni
# documents/ n'est lu ni ecrit.

# La carte dont on ceinture l'emprise. Sans elle, rien n'est pose et le dit.
@export var carte: Resource

# Hauteur du mur, en couches, depuis la couche de base. Decision de jeu : assez
# haut qu'aucune unite ne franchisse le bord (22 couches = 44 m).
@export var couches: int = 22

# Epaisseur des murs, en metres, poussee VERS L'EXTERIEUR. Bornee au minimum a la
# cote de la cellule : jamais plus mince que la ceinture d'origine.
@export var epaisseur: float = 10.0

func _ready() -> void:
	_construire()

# Bati au _ready, RUNTIME COMME EDITEUR (@tool) : sans les formes a l'edition, le
# corps parait vide et Godot avertit « pas de forme ». Dedoublonne d'abord -- un
# rechargement de scene rappelle _ready -- puis pose les quatre boites. Les
# CollisionShape crees n'ont pas d'owner : ils vivent dans l'arbre mais ne sont
# jamais enregistres dans la scene (la .tscn reste vide de formes).
func _construire() -> void:
	for enfant in get_children():
		if enfant is CollisionShape3D:
			enfant.free()
	if carte == null:
		update_configuration_warnings()
		return
	collision_layer = 1
	collision_mask = 0
	var f := faces(carte, couches)
	var t: float = maxf(epaisseur, float(carte.cote))
	var ext_min: float = f["interne_min"] - t
	var ext_max: float = f["interne_max"] + t
	var y0: float = f["y_bas"]
	var y1: float = f["y_haut"]
	# Ouest et Est : entre les deux faces internes en Z. Nord et Sud : toute la
	# largeur externe en X, pour couvrir les coins.
	_mur(Vector3(ext_min, y0, f["interne_min"]), Vector3(f["interne_min"], y1, f["interne_max"]))  # Ouest
	_mur(Vector3(f["interne_max"], y0, f["interne_min"]), Vector3(ext_max, y1, f["interne_max"]))  # Est
	_mur(Vector3(ext_min, y0, ext_min), Vector3(ext_max, y1, f["interne_min"]))                    # Sud
	_mur(Vector3(ext_min, y0, f["interne_max"]), Vector3(ext_max, y1, ext_max))                    # Nord

# Les quatre faces internes de la ceinture et la hauteur, deduites de l'emprise.
# Statique : le banc de test la reutilise sur la ceinture GridMap comme sur les
# boites, une seule source de verite pour la geometrie.
static func faces(source: Resource, hauteur: int) -> Dictionary:
	var c: float = float(source.cote)
	var dc: int = int(source.demi_cote)
	var b: int = int(source.couche_base)
	return {
		"interne_min": -float(dc) * c,  # face interne Ouest / Sud
		"interne_max": float(dc) * c,   # face interne Est / Nord
		"y_bas": float(b) * c,
		"y_haut": float(b + hauteur) * c,
	}

# Une boite de collision entre deux coins opposes. La taille est la difference,
# le centre le milieu.
func _mur(coin_a: Vector3, coin_b: Vector3) -> void:
	var forme := CollisionShape3D.new()
	var boite := BoxShape3D.new()
	boite.size = (coin_b - coin_a).abs()
	forme.shape = boite
	forme.position = (coin_a + coin_b) * 0.5
	add_child(forme)
