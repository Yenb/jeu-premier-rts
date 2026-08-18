extends SceneTree

# Test manuel :
# godot --headless --script jeu/unites/test_personnage.gd
#
# Verrouille le personnage arpenteur SANS CLAVIER ET SANS MOTEUR PHYSIQUE : le
# calcul de marche et de rotation vit dans deux fonctions statiques et pures, ce
# qui rend le jugement possible headless. Ce qui reste dans _physics_process ne
# fait que declencher -- lire les touches, appeler, poser le resultat.
#
# Ce qui est tenu :
# - AVANCER, C'EST ALLER OU L'ON REGARDE : la direction de marche suit
#   l'orientation, donc tourner change la trajectoire sans qu'une ligne le dise ;
# - la marche est HORIZONTALE : regarder vers le sol ne fait pas s'enfoncer ;
# - DROITE TOURNE A DROITE. Un signe inverse donne un personnage qui part a
#   gauche quand on lui dit droite, et aucun test de distance ne le verrait ;
# - la geometrie de la scene : capsule de 1 m posee sur ses pieds, yeux dedans,
#   sur une carte dont la cellule fait 2 m ;
# - relacher les touches immobilise, et la vitesse est exactement celle demandee.
#
# Regles tenues : positions en Vector3. Aucun hasard. Rien de scripts/, data/ ni
# addons/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const Personnage = preload("res://jeu/unites/personnage.gd")
const PersonnageScene = preload("res://jeu/unites/personnage.tscn")

# Le cote d'une cellule du terrain, en metres -- jeu/terrain/bloc.tres.
const CELLULE := 2.0
const TAILLE_VOULUE := 1.0

var _v

func _init() -> void:
	_v = Verif.new()
	_juger_la_marche()
	_juger_la_rotation()
	_juger_la_geometrie()
	_conclure()

# ---- La marche ----

func _juger_la_marche() -> void:
	var vitesse := 3.0

	# DE FACE : le devant de Godot est l'axe -Z.
	var devant := Personnage.vitesse_voulue(Basis.IDENTITY, 1.0, vitesse)
	_v.v(devant.is_equal_approx(Vector3(0.0, 0.0, -vitesse)),
		"avancer sans avoir tourne ne va pas droit devant : %s" % devant)

	var arriere := Personnage.vitesse_voulue(Basis.IDENTITY, -1.0, vitesse)
	_v.v(arriere.is_equal_approx(Vector3(0.0, 0.0, vitesse)),
		"reculer ne fait pas l'oppose d'avancer : %s" % arriere)

	_v.v(Personnage.vitesse_voulue(Basis.IDENTITY, 0.0, vitesse).is_zero_approx(),
		"sans touche enfoncee le personnage bouge encore")

	# APRES UN QUART DE TOUR A GAUCHE, le devant doit avoir bascule sur -X.
	var pivote := Basis(Vector3.UP, PI / 2.0)
	var apres := Personnage.vitesse_voulue(pivote, 1.0, vitesse)
	_v.v(apres.is_equal_approx(Vector3(-vitesse, 0.0, 0.0)),
		"apres un quart de tour, avancer ne suit pas l'orientation : %s" % apres)

	# LA MARCHE EST HORIZONTALE. Un personnage penche vers le sol ne doit pas
	# s'enfoncer : la composante verticale appartient a la gravite, pas aux
	# fleches. Sans ce jugement, un jour ou la camera s'inclinera, il plongera.
	var penche := Basis(Vector3.RIGHT, -PI / 4.0)
	var a_plat := Personnage.vitesse_voulue(penche, 1.0, vitesse)
	_v.v(is_zero_approx(a_plat.y),
		"le personnage penche descend en avancant (y = %.3f)" % a_plat.y)
	_v.v(is_equal_approx(a_plat.length(), vitesse),
		"penche, il n'avance plus a la vitesse demandee (%.3f au lieu de %.3f)" % [
			a_plat.length(), vitesse])

	print("marche : %.1f m/s droit devant, l'orientation la porte, et elle reste a plat" % vitesse)

# ---- La rotation ----

func _juger_la_rotation() -> void:
	var vitesse_pivot := 2.2
	var delta := 0.5

	# DROITE TOURNE A DROITE : autour de l'axe vertical de Godot, c'est un angle
	# NEGATIF. C'est le seul jugement qui attrape une inversion de signe.
	var droite := Personnage.rotation_voulue(1.0, vitesse_pivot, delta)
	_v.v(droite < 0.0, "la touche DROITE fait tourner a gauche (angle %.3f)" % droite)

	var gauche := Personnage.rotation_voulue(-1.0, vitesse_pivot, delta)
	_v.v(gauche > 0.0, "la touche GAUCHE fait tourner a droite (angle %.3f)" % gauche)
	_v.v(is_equal_approx(gauche, -droite), "les deux sens ne tournent pas d'autant")

	_v.v(is_zero_approx(Personnage.rotation_voulue(0.0, vitesse_pivot, delta)),
		"sans touche enfoncee le personnage tourne encore")

	# L'ANGLE SUIT LE TEMPS, jamais l'image : deux fois plus de temps, deux fois
	# plus d'angle. Sans ca, il tournerait plus vite sur une machine rapide.
	var deux_fois := Personnage.rotation_voulue(1.0, vitesse_pivot, delta * 2.0)
	_v.v(is_equal_approx(deux_fois, droite * 2.0),
		"la rotation ne suit pas le temps ecoule : %.3f pour le double de %.3f" % [
			deux_fois, droite])

	# UN DEMI-TOUR SE FAIT EN UN TEMPS TENABLE. Le reglage est arbitraire, la
	# GRANDEUR ne l'est pas : arpenter demande de pouvoir se retourner.
	var duree_demi_tour := PI / vitesse_pivot
	_v.v(duree_demi_tour < 3.0,
		"un demi-tour prend %.1f s : trop lent pour arpenter" % duree_demi_tour)

	print("rotation : droite = angle negatif, demi-tour en %.1f s" % duree_demi_tour)

# ---- La geometrie de la scene ----

func _juger_la_geometrie() -> void:
	var noeud := PersonnageScene.instantiate()
	_v.v(noeud is CharacterBody3D, "la scene du personnage n'est pas un CharacterBody3D")

	var hitbox := noeud.get_node_or_null("Hitbox") as CollisionShape3D
	_v.v(hitbox != null, "le personnage n'a pas de hitbox : il traverserait tout")
	var yeux := noeud.get_node_or_null("Yeux") as Camera3D
	_v.v(yeux != null, "le personnage n'a pas de camera")

	if hitbox != null and hitbox.shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = hitbox.shape
		_v.v(is_equal_approx(capsule.height, TAILLE_VOULUE),
			"le personnage mesure %.2f m au lieu de %.2f" % [capsule.height, TAILLE_VOULUE])
		_v.v(is_equal_approx(capsule.height, CELLULE / 2.0),
			"le personnage ne fait pas une demi-cellule : l'echelle de la carte est perdue")

		# POSE SUR SES PIEDS : l'origine du noeud doit etre au SOL, donc la capsule
		# remontee d'une demi-hauteur. Sans ce decalage on l'enterre a mi-corps en
		# le posant a la hauteur du terrain, et personne ne comprend pourquoi.
		_v.v(is_equal_approx(hitbox.position.y, capsule.height / 2.0),
			"la hitbox n'est pas posee sur les pieds (y = %.2f, attendu %.2f)" % [
				hitbox.position.y, capsule.height / 2.0])

		if yeux != null:
			_v.v(yeux.position.y > 0.0 and yeux.position.y <= capsule.height,
				"les yeux sont hors du corps (y = %.2f pour %.2f m)" % [
					yeux.position.y, capsule.height])
			print("geometrie : capsule de %.2f m posee sur ses pieds, yeux a %.2f m, cellule de %.1f m" % [
				capsule.height, yeux.position.y, CELLULE])
	else:
		_v.v(false, "la hitbox n'est pas une capsule")

	noeud.free()

func _conclure() -> void:
	if _v.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % _v.echecs())
		quit(1)
		return
	print("OK: personnage -- avancer suit l'orientation et reste a plat, droite tourne a droite, " +
		"la rotation suit le temps, capsule d'un metre posee sur ses pieds avec ses yeux dedans")
	quit()
