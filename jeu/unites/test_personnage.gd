extends SceneTree

# Test manuel :
# godot --headless --script jeu/unites/test_personnage.gd
#
# Verrouille le personnage arpenteur SANS CLAVIER, SANS SOURIS ET SANS MOTEUR
# PHYSIQUE : la marche, la rotation et la visee vivent dans des fonctions
# statiques et pures, ce qui rend le jugement possible headless. Le personnage
# n'est PLUS un CharacterBody3D : c'est un Node3D dont la position est mue en
# donnee (voir manager_proto_2). Ce test verrouille le calcul pur et la geometrie
# de la scene ; l'appartenance au groupe "observateur" (posee sur l'INSTANCE dans
# chaque scene, pas sur la source) est verrouillee par test_scene_carte et
# test_carte_prototype, et l'entite data joueur par les tests de manager_proto_2.
#
# Ce qui est tenu :
# - AVANCER, C'EST ALLER OU L'ON REGARDE : la direction de marche suit
#   l'orientation, donc tourner change la trajectoire sans qu'une ligne le dise ;
# - la marche est HORIZONTALE : regarder vers le sol ne fait pas s'enfoncer ;
# - DROITE TOURNE A DROITE, a la touche comme a la souris. Un signe inverse
#   donne un personnage qui part a gauche quand on lui dit droite, et aucun test
#   de distance ne le verrait ;
# - SOURIS VERS LE HAUT, REGARD VERS LE HAUT : second piege de signe, celui-la
#   sur l'axe que Godot compte a l'envers du geste ;
# - l'inclinaison S'ACCUMULE et reste BORNEE sous le quart de tour, sans quoi la
#   vue se retourne et la direction de marche perd son sens ;
# - le curseur relache NE PILOTE PLUS : la souris qui va cliquer ailleurs ne
#   fait pas pivoter le personnage ;
# - la geometrie de la scene : capsule d'adulte (1,8 m) posee sur ses pieds, yeux
#   dedans, marqueur de debug a l'origine = position data exacte ;
# - relacher les touches immobilise, et la vitesse est exactement celle demandee.
#
# Regles tenues : positions en Vector3. Aucun hasard. Rien de scripts/, data/ ni
# documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const Personnage = preload("res://jeu/unites/personnage.gd")
const PersonnageScene = preload("res://jeu/unites/personnage.tscn")

# Le cote d'une cellule du terrain, en metres -- jeu/terrain/bloc.tres.
const CELLULE := 2.0
const TAILLE_VOULUE := 1.8

# Largeur d'ecran servant d'etalon a la sensibilite. Le reglage est arbitraire,
# la GRANDEUR ne l'est pas : viser demande de pouvoir se retourner d'un geste
# sans que le moindre frisson fasse un tour complet.
const BALAYAGE_ECRAN := 1000.0

var _v

func _init() -> void:
	_v = Verif.new()
	_juger_la_marche()
	_juger_la_rotation()
	_juger_la_souris()
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
	# fleches. C'est ce jugement qui rend sans danger une camera qui s'incline.
	var penche := Basis(Vector3.RIGHT, -PI / 4.0)
	var a_plat := Personnage.vitesse_voulue(penche, 1.0, vitesse)
	_v.v(is_zero_approx(a_plat.y),
		"le personnage penche descend en avancant (y = %.3f)" % a_plat.y)
	_v.v(is_equal_approx(a_plat.length(), vitesse),
		"penche, il n'avance plus a la vitesse demandee (%.3f au lieu de %.3f)" % [
			a_plat.length(), vitesse])

	print("marche : %.1f m/s droit devant, l'orientation la porte, et elle reste a plat" % vitesse)

# ---- La rotation au clavier ----

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

# ---- La visee a la souris ----

func _juger_la_souris() -> void:
	var sensibilite := 0.003
	var borne := 1.5

	# MEME PIEGE DE SIGNE QUE LA TOUCHE, sur un autre chemin : souris vers la
	# DROITE, angle NEGATIF. Deux entrees, un seul sens de rotation a tenir.
	var vers_la_droite := Personnage.pivot_souris(100.0, sensibilite)
	_v.v(vers_la_droite < 0.0,
		"la souris vers la DROITE fait pivoter a gauche (angle %.4f)" % vers_la_droite)

	var vers_la_gauche := Personnage.pivot_souris(-100.0, sensibilite)
	_v.v(is_equal_approx(vers_la_gauche, -vers_la_droite),
		"les deux sens de souris ne pivotent pas d'autant")

	_v.v(is_zero_approx(Personnage.pivot_souris(0.0, sensibilite)),
		"une souris immobile fait quand meme pivoter le personnage")

	# LE PIVOT SUIT LE GESTE, jamais le temps : deux fois plus de deplacement,
	# deux fois plus d'angle. C'est ce qui distingue un EVENEMENT de souris d'une
	# touche ENFONCEE, que le temps integre.
	_v.v(is_equal_approx(Personnage.pivot_souris(200.0, sensibilite), vers_la_droite * 2.0),
		"le pivot de souris n'est pas proportionnel au deplacement")

	# SECOND PIEGE DE SIGNE, celui que la touche n'a pas : Godot compte le
	# deplacement vertical vers le BAS, donc pousser la souris vers le HAUT rend
	# un nombre NEGATIF -- et doit faire lever les yeux.
	var regard_haut := Personnage.inclinaison_voulue(0.0, -100.0, sensibilite, borne)
	_v.v(regard_haut > 0.0,
		"pousser la souris vers le HAUT baisse le regard (inclinaison %.4f)" % regard_haut)

	var regard_bas := Personnage.inclinaison_voulue(0.0, 100.0, sensibilite, borne)
	_v.v(is_equal_approx(regard_bas, -regard_haut),
		"lever et baisser le regard ne coutent pas le meme geste")

	# ELLE S'ACCUMULE : deux petits mouvements valent un grand. Un angle
	# recalcule a neuf a chaque evenement ramenerait le regard a l'horizontale
	# entre deux mouvements de souris.
	var un_pas := Personnage.inclinaison_voulue(0.0, -100.0, sensibilite, borne)
	var deux_pas := Personnage.inclinaison_voulue(un_pas, -100.0, sensibilite, borne)
	_v.v(is_equal_approx(deux_pas, Personnage.inclinaison_voulue(0.0, -200.0, sensibilite, borne)),
		"l'inclinaison ne s'accumule pas : %.4f apres deux pas" % deux_pas)

	# BORNEE DANS LES DEUX SENS. Un geste demesure ne doit pas retourner la vue.
	var tout_en_haut := Personnage.inclinaison_voulue(0.0, -100000.0, sensibilite, borne)
	_v.v(is_equal_approx(tout_en_haut, borne),
		"le regard depasse la borne vers le haut (%.4f pour %.4f)" % [tout_en_haut, borne])
	var tout_en_bas := Personnage.inclinaison_voulue(0.0, 100000.0, sensibilite, borne)
	_v.v(is_equal_approx(tout_en_bas, -borne),
		"le regard depasse la borne vers le bas (%.4f pour %.4f)" % [tout_en_bas, borne])

	# LE CURSEUR RELACHE NE PILOTE PLUS. Sans cette garde, bouger la souris pour
	# cliquer ailleurs ferait pivoter le personnage a l'insu du joueur.
	_v.v(Personnage.souris_pilote(Input.MOUSE_MODE_CAPTURED, Input.MOUSE_MODE_CAPTURED),
		"le curseur capture ne pilote pas la visee")
	_v.v(not Personnage.souris_pilote(Input.MOUSE_MODE_VISIBLE, Input.MOUSE_MODE_CAPTURED),
		"le curseur relache pilote encore la visee")

	_juger_les_reglages()

	print("souris : droite = angle negatif, haut = regard leve, accumulation bornee a %.2f rad" % borne)

# ---- Les reglages reellement poses sur le disque ----

func _juger_les_reglages() -> void:
	var noeud := PersonnageScene.instantiate()

	# LA BORNE RESTE STRICTEMENT SOUS LE QUART DE TOUR : au-dela, un geste continu
	# fait passer le regard par la verticale et retourne l'image. La marche n'y
	# est pour rien -- elle lit l'orientation du CORPS, que le tangage ne touche
	# jamais, et le cas penche ci-dessus le verrouille deja.
	var borne: float = noeud.inclinaison_max
	_v.v(borne > 0.0 and borne < PI / 2.0,
		"l'inclinaison maximale vaut %.4f rad : hors de ]0 ; PI/2[" % borne)

	# ET ELLE LAISSE VOIR LE CIEL ET LE SOL. Une borne trop basse rend un regard
	# qui ne peut plus se lever vers une canopee ni se baisser sur ses pieds --
	# les deux gestes memes que ce personnage existe pour faire.
	_v.v(borne > deg_to_rad(70.0),
		"l'inclinaison maximale vaut %.1f degres : trop peu pour lever les yeux sur un arbre" % rad_to_deg(borne))

	# LA SENSIBILITE EST UNE GRANDEUR, pas un gout : un balayage d'ecran doit
	# faire au moins un quart de tour, et jamais plus de deux tours.
	var sensibilite: float = noeud.sensibilite_souris
	var balayage := sensibilite * BALAYAGE_ECRAN
	_v.v(balayage >= PI / 2.0,
		"un ecran entier de souris ne fait que %.2f rad : trop lourd pour viser" % balayage)
	_v.v(balayage <= 4.0 * PI,
		"un ecran entier de souris fait %.2f rad : le moindre frisson fait des tours" % balayage)

	print("reglages : borne a %.2f rad, un ecran de souris balaye %.2f rad" % [borne, balayage])

	noeud.free()

# ---- La geometrie de la scene ----

func _juger_la_geometrie() -> void:
	var noeud := PersonnageScene.instantiate()

	# L'EXCEPTION PHYSIQUE EST RETIREE : le personnage est un Node3D, plus un
	# CharacterBody3D. Sa position est mue en donnee par le manager, pas par
	# move_and_slide. Tout Node3D expose global_position, ce dont le rendu et les
	# lecteurs du groupe "observateur" ont besoin.
	_v.v(noeud is Node3D, "la scene du personnage n'est pas un Node3D")
	_v.v(not (noeud is CharacterBody3D),
		"le personnage est encore un CharacterBody3D : l'exception physique n'est pas retiree")

	# PLUS DE HITBOX : un CollisionShape3D est inerte sur un Node3D. La collision du
	# joueur vit dans la donnee (forme capsule de l'entite du Monde), pas ici.
	_v.v(noeud.get_node_or_null("Hitbox") == null,
		"le personnage porte encore un CollisionShape3D Hitbox, inerte sur un Node3D")

	var corps := noeud.get_node_or_null("corps_visible") as MeshInstance3D
	_v.v(corps != null, "le personnage n'a pas de corps visible")
	var marqueur := noeud.get_node_or_null("marqueur_debug") as MeshInstance3D
	_v.v(marqueur != null, "le personnage n'a pas de marqueur de debug")
	var yeux := noeud.get_node_or_null("Yeux") as Camera3D
	_v.v(yeux != null, "le personnage n'a pas de camera")

	# LA CAMERA EST UN ENFANT, ET C'EST CE QUI PERMET D'INCLINER LE REGARD SANS
	# PENCHER LE CORPS : le tangage va sur les yeux seuls, jamais sur le corps.
	if yeux != null:
		_v.v(yeux.get_parent() == noeud,
			"les yeux ne sont pas un enfant direct du corps : les incliner pencherait le corps")

	# LE MARQUEUR DE DEBUG EST A L'ORIGINE DU NŒUD = la position data exacte (les
	# pieds). C'est ce qui permet de voir a l'ecran ou entite_joueur.position est.
	if marqueur != null:
		_v.v(marqueur.position.is_zero_approx(),
			"le marqueur de debug n'est pas a l'origine (position data) : %s" % marqueur.position)

	if corps != null and corps.mesh is CapsuleMesh:
		var capsule: CapsuleMesh = corps.mesh
		_v.v(is_equal_approx(capsule.height, TAILLE_VOULUE),
			"le personnage mesure %.2f m au lieu de %.2f (adulte)" % [capsule.height, TAILLE_VOULUE])

		# POSE SUR SES PIEDS : l'origine du noeud est au SOL, donc le corps remonte
		# d'une demi-hauteur. Sans ce decalage on l'enterre a mi-corps en le posant
		# a la hauteur du terrain. Le meme decalage vaut sur la forme capsule de la
		# donnee (transform_locale), voir manager_proto_2.
		_v.v(is_equal_approx(corps.position.y, capsule.height / 2.0),
			"le corps n'est pas pose sur les pieds (y = %.2f, attendu %.2f)" % [
				corps.position.y, capsule.height / 2.0])

		if yeux != null:
			_v.v(yeux.position.y > 0.0 and yeux.position.y <= capsule.height,
				"les yeux sont hors du corps (y = %.2f pour %.2f m)" % [
					yeux.position.y, capsule.height])
			print("geometrie : capsule de %.2f m posee sur ses pieds, yeux a %.2f m, cellule de %.1f m" % [
				capsule.height, yeux.position.y, CELLULE])
	else:
		_v.v(false, "le corps visible n'est pas une capsule")

	noeud.free()

func _conclure() -> void:
	if _v.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % _v.echecs())
		quit(1)
		return
	print("OK: personnage -- Node3D (plus un CharacterBody3D), avancer suit l'orientation et reste " +
		"a plat, droite tourne a droite a la touche comme a la souris, souris vers le haut leve le " +
		"regard, l'inclinaison s'accumule et reste bornee, le curseur relache ne pilote plus, " +
		"capsule d'adulte posee sur ses pieds avec ses yeux dedans, marqueur de debug a la position data")
	quit()
