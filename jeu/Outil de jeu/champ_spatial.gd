extends RefCounted

# CHAMP SPATIAL SCALAIRE -- un tableau `case -> compte` qui pese ce qui est
# pose sur une grille virtuelle. Pattern automate cellulaire, sans physique,
# sans Area3D, sans monde.gd, sans balayage global.
#
# UNE INSTANCE PAR ESPECE (herbe, lichen, ...) : deux especes ne se
# rentrent pas dans le meme compteur, donc pas dans le meme champ.
#
# ENTREE : inscrire(pos), retirer(pos) -- appeles a la naissance et a la
# mort d'un cube, une seule fois. Le cout est O(1) par appel.
# LECTURE : voisins_dans(pos, rayon_cases) -- rend un entier, la somme des
# comptes dans les (2r+1)^2 cases centrees sur la case de pos. Cout O(k^2)
# ou k = rayon_cases (typiquement 1 a 3), constant, JAMAIS lie a N.
#
# TAILLE DE CASE : reglee a l'instanciation, choisie par l'appelant selon
# le rayon de perception de son espece. Convention : case = rayon / 2, ce
# qui rend un examen de 3x3 = 9 cases equivalent a une couverture de
# 1.5 rayon en cote (sous-estime la surface du disque de ~30 %, acceptable
# pour un seuil de saturation qui est de toute facon un reglage empirique).
#
# CE FICHIER NE CONNAIT AUCUN NOM D'ESPECE. Il ne connait que des
# positions et un compteur. Reutilise par n'importe quelle espece.

var _taille_case: float
var _densite: Dictionary = {}  # Vector2i -> int

func _init(taille_case: float) -> void:
	_taille_case = taille_case

func _case_de(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / _taille_case)), int(floor(pos.z / _taille_case)))

# Un cube nait a `pos` : sa case gagne +1. O(1).
func inscrire(pos: Vector3) -> void:
	var c := _case_de(pos)
	_densite[c] = int(_densite.get(c, 0)) + 1

# Un cube meurt a `pos` : sa case perd -1. O(1).
func retirer(pos: Vector3) -> void:
	var c := _case_de(pos)
	var n := int(_densite.get(c, 0)) - 1
	if n <= 0:
		_densite.erase(c)
	else:
		_densite[c] = n

# Compte total dans les (2r+1)^2 cases centrees sur la case de `pos`. O(k^2).
# `rayon_cases` = 1 balaie 9 cases (3x3), 2 en balaie 25 (5x5), etc.
func voisins_dans(pos: Vector3, rayon_cases: int) -> int:
	var c := _case_de(pos)
	var total := 0
	for dx in range(-rayon_cases, rayon_cases + 1):
		for dz in range(-rayon_cases, rayon_cases + 1):
			total += int(_densite.get(c + Vector2i(dx, dz), 0))
	return total
