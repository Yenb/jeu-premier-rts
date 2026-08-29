extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_carte_sous_cube.gd
#
# Verrouille l'API de subdivision 3x3x3 = 27 sous-cubes par cellule dans
# res://jeu/terrain/carte_terrain.gd :
# - une cellule pleine par defaut n'a AUCUNE entree dans le dict (defaut
#   gratuit, meme convention que `volumes` et `particularites`) ;
# - `casser_sous_cube` retire un bit et publie la colonne dans TOUS les drains
#   connus, comme `poser_masque` -- streamers rendu et collision voient la
#   modification au prochain _process ;
# - recasser un sous-cube deja detruit rend false, aucune publication superflue ;
# - un index hors [0, 27[ est rejete silencieusement, ne crashe pas ;
# - casser les 27 sous-cubes d'une cellule la SORT du dict ET retire la couche
#   du masque colonne via `retirer_cellule` -- sans quoi le sommet, les
#   particularites et le rendu resteraient decoherents.
#
# Regles tenues : aucun hasard. Rien de scripts/, data/ ni documents/ n'est
# ecrit. Prints = traces de mise au point, pas de texte joueur.

const Verif = preload("res://scripts/verif.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")

var _v

func _init() -> void:
	_v = Verif.new()
	_juger_defaut()
	_juger_casser_et_relire()
	_juger_bornes_index()
	_juger_publication_drain()
	_juger_videment_complet()
	_juger_sommet_precis()
	_conclure()

func _juger_defaut() -> void:
	var carte: Resource = CarteTerrain.new()
	var cell := Vector3i(3, carte.couche_base, 7)
	_v.v(carte.sous_cubes(cell) == CarteTerrain.MASQUE_SOUS_CUBE_PLEIN,
		"une cellule pleine par defaut rend MASQUE_SOUS_CUBE_PLEIN, pas %d"
			% carte.sous_cubes(cell))
	_v.v(carte.est_sous_cube_plein(cell, 0), "sous-cube 0 plein par defaut")
	_v.v(carte.est_sous_cube_plein(cell, 13), "sous-cube central 13 plein par defaut")
	_v.v(carte.est_sous_cube_plein(cell, 26), "sous-cube 26 plein par defaut")
	print("defaut : cellule pleine sans entree dans le dict, tous sous-cubes pleins")

func _juger_casser_et_relire() -> void:
	var carte: Resource = CarteTerrain.new()
	var cell := Vector3i(1, carte.couche_base, 2)
	_v.v(carte.casser_sous_cube(cell, 5), "casser un sous-cube plein rend true")
	_v.v(not carte.est_sous_cube_plein(cell, 5), "sous-cube 5 detruit apres casser")
	_v.v(carte.est_sous_cube_plein(cell, 4), "voisin 4 reste plein")
	_v.v(carte.est_sous_cube_plein(cell, 6), "voisin 6 reste plein")
	_v.v(not carte.casser_sous_cube(cell, 5),
		"recasser un sous-cube deja detruit rend false")
	print("casser : bit 5 detruit, voisins intacts, recasser sans effet")

func _juger_bornes_index() -> void:
	var carte: Resource = CarteTerrain.new()
	var cell := Vector3i(0, carte.couche_base, 0)
	_v.v(not carte.casser_sous_cube(cell, -1), "index -1 rejete")
	_v.v(not carte.casser_sous_cube(cell, 27), "index 27 rejete")
	_v.v(not carte.casser_sous_cube(cell, 100), "index 100 rejete")
	_v.v(not carte.est_sous_cube_plein(cell, -1), "est_plein sur index -1 = false")
	_v.v(not carte.est_sous_cube_plein(cell, 27), "est_plein sur index 27 = false")
	_v.v(carte.sous_cubes(cell) == CarteTerrain.MASQUE_SOUS_CUBE_PLEIN,
		"aucun index hors bornes n'a alter le masque")
	print("bornes : indices hors [0, 27[ rejetes silencieusement")

func _juger_publication_drain() -> void:
	var carte: Resource = CarteTerrain.new()
	var boot: Array = carte.drainer_modifications("test_sous_cube")
	_v.v(boot.is_empty(), "premier drain d'un nouveau consommateur rend vide")
	var cell := Vector3i(4, carte.couche_base, 9)
	var col := Vector2i(cell.x, cell.z)
	carte.casser_sous_cube(cell, 10)
	var modifs: Array = carte.drainer_modifications("test_sous_cube")
	_v.v(col in modifs,
		"casser publie la colonne %s dans le drain -- vue : %s" % [col, modifs])
	var modifs2: Array = carte.drainer_modifications("test_sous_cube")
	_v.v(modifs2.is_empty(), "drain vide sans nouvelle modification")
	print("drain : la colonne est publiee, drainee, puis vide")

func _juger_videment_complet() -> void:
	var carte: Resource = CarteTerrain.new()
	var cell := Vector3i(6, carte.couche_base, 3)
	var col := Vector2i(cell.x, cell.z)
	for i in range(27):
		carte.casser_sous_cube(cell, i)
	_v.v(not carte.est_pleine(col, cell.y),
		"la couche %d de la colonne %s doit etre retiree du masque colonne"
			% [cell.y, col])
	_v.v(carte.sous_cubes(cell) == 0,
		"sous_cubes doit rendre 0 sur cellule sortie de sa couche pleine")
	_v.v(not carte.est_sous_cube_plein(cell, 0),
		"aucun sous-cube ne doit rester plein apres videment complet")
	print("videment : 27 casses = couche retiree, dict propre, sous_cubes = 0")

func _juger_sommet_precis() -> void:
	# La nouvelle `sommet(x, z)` rend la Y monde du plus haut sous-cube plein
	# SOUS le point (x, z). Verifie que le sommet baisse par tiers de cote
	# quand les sous-cubes du haut sont casses sous ce point precis.
	var carte: Resource = CarteTerrain.new()
	var cote: float = carte.cote
	var col := Vector2i(2, 4)
	var cy: int = carte.sommet_de_base()
	var cell := Vector3i(col.x, cy, col.y)
	# Centre de la cellule en monde.
	var x_centre: float = (float(col.x) + 0.5) * cote
	var z_centre: float = (float(col.y) + 0.5) * cote
	# Cellule pleine : sommet = face haute = (cy+1) * cote.
	var y_plein: Variant = carte.sommet(x_centre, z_centre)
	_v.v(y_plein != null and is_equal_approx(float(y_plein), float(cy + 1) * cote),
		"cellule pleine : sommet(%f, %f) = %s, attendu %f"
			% [x_centre, z_centre, y_plein, float(cy + 1) * cote])
	# Casse le sous-cube haut au centre de la cellule (ix=1, iy=2, iz=1).
	# Index : 1 + 2*3 + 1*9 = 16.
	carte.casser_sous_cube(cell, 16)
	# Au centre X/Z, le plus haut sous-cube plein sous ce point est iy=1
	# -> Y = cy * cote + (1+1) * cote/3 = cy*cote + 2*cote/3.
	var y_casse: Variant = carte.sommet(x_centre, z_centre)
	var attendu: float = float(cy) * cote + 2.0 * cote / 3.0
	_v.v(y_casse != null and is_equal_approx(float(y_casse), attendu),
		"apres cassure sous-cube haut centre : sommet = %s, attendu %f" % [y_casse, attendu])
	# En dehors du centre X/Z, le sommet reste haut (les 8 autres sous-cubes
	# du haut restent pleins). Test coin (ix=0, iz=0) via x = col.x*cote + 0.1.
	var x_coin: float = float(col.x) * cote + 0.1
	var z_coin: float = float(col.y) * cote + 0.1
	var y_coin: Variant = carte.sommet(x_coin, z_coin)
	_v.v(y_coin != null and is_equal_approx(float(y_coin), float(cy + 1) * cote),
		"coin (ix=0, iz=0) intact : sommet = %s, attendu %f" % [y_coin, float(cy + 1) * cote])
	print("sommet precis : Y monde varie AU SOUS-CUBE PRES selon (x, z)")

func _conclure() -> void:
	if _v.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % _v.echecs())
		quit(1)
		return
	print("OK: sous-cubes -- defaut gratuit, casser + relire, bornes, publication " +
		"drain, videment complet retire la couche via retirer_cellule")
	quit()
