extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_cache_sommet.gd
#
# Verrouille le cache _cache_sommet de res://jeu/terrain/carte_terrain.gd :
# le cache doit rendre EXACTEMENT ce que le calcul complet rendrait, sinon il
# n'a pas lieu d'etre. Quatre cas :
#  1. Terrain plat : la hauteur relue (cache) egale la hauteur de reference
#     bit-a-bit ; deux points de la meme sous-cellule donnent la meme hauteur ;
#     sommet et sommet_sous coincident quand y_max est bien au-dessus du sol.
#  2. Terrain sculpte : apres casser_sous_cube (marquer_sale interne), la
#     hauteur relue reflete la mutation -- le cache s'est bien vide.
#  3. Cellule a rampe (item a profil non-plein via poser_profil_hauteur) : la
#     surface reste continue dans la cellule, deux points voisins de la meme
#     sous-cellule donnent des hauteurs differentes. Le cache n'a pas
#     quantifie la rampe en 9 marches.
#  4. Surplomb (bloc suspendu au-dessus du sol) : sommet_sous(y_max entre le
#     sol et le bloc) rend le sol du dessous, pas le bloc du dessus ; un appel
#     ulterieur a sommet_sous(y_max au-dessus du bloc) rend le bloc (le cache
#     n'a pas ete pollue par la reponse plafonnee).
#
# Aucune categorie de contenu nommee. Rien de scripts/, data/ ni documents/
# n'est ecrit. Prints = traces de mise au point.

const Verif = preload("res://scripts/verif.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")

var _v


func _init() -> void:
	_v = Verif.new()
	_juger_plat()
	_juger_sculpte_invalide_cache()
	_juger_rampe_continue()
	_juger_surplomb()
	_juger_demi_cote_realloue()
	_conclure()


func _juger_demi_cote_realloue() -> void:
	# Round 9 : _table_sommet est une PackedFloat32Array de taille
	# (2*demi_cote)^2 * 9. Changer demi_cote via le setter doit reallouer la
	# table a la nouvelle taille et la remplir de NAN, sans quoi l'index
	# arithmetique de pas_simple_lot pointerait hors-tableau (crash) ou lirait
	# des valeurs perimees.
	var carte: Resource = CarteTerrain.new()
	# Chauffer la table au sommet plat.
	var _y_avant: Variant = carte.sommet(0.5, 0.5)
	var t_avant: PackedFloat32Array = carte.table_sommet()
	var attendu_avant: int = (2 * 150) * (2 * 150) * 9
	_v.v(t_avant.size() == attendu_avant,
		"demi_cote : table taille %d != %d attendu (demi_cote=150)" % [t_avant.size(), attendu_avant])
	# Changer demi_cote : le setter doit reallouer et remettre a NAN.
	carte.demi_cote = 40
	var t_apres: PackedFloat32Array = carte.table_sommet()
	var attendu_apres: int = (2 * 40) * (2 * 40) * 9
	_v.v(t_apres.size() == attendu_apres,
		"demi_cote : table taille %d != %d attendu apres realloc (demi_cote=40)" % [t_apres.size(), attendu_apres])
	# Toutes les cases doivent etre NAN apres realloc.
	var toutes_nan: bool = true
	for k in range(t_apres.size()):
		if not is_nan(t_apres[k]):
			toutes_nan = false
			break
	_v.v(toutes_nan, "demi_cote : table apres realloc contient des valeurs non-NAN")
	# La carte doit rester interrogeable dans la nouvelle emprise (colonne (0,0)
	# reste dans [-40, 39]).
	var y_new: Variant = carte.sommet(0.5, 0.5)
	_v.v(y_new != null, "demi_cote : sommet sur nouvelle emprise = null")
	print("demi_cote : setter reallouee (%d -> %d cases), NAN, carte interrogeable" % [attendu_avant, attendu_apres])


func _juger_plat() -> void:
	var carte: Resource = CarteTerrain.new()
	# couches_pleines=7 -> sommet plat a couche_max = couche_base + 6.
	# Hauteur du sous-cube du haut = 6 * 2 + 2 = 14 m (cote=2, iy=2).
	var y_ref: Variant = carte.sommet(3.4, -5.1)
	_v.v(y_ref != null, "plat : sommet(3.4, -5.1) = null sur terrain plat")
	if y_ref == null:
		return
	# Deuxieme appel au meme point : cache lu, meme valeur au bit pres.
	var y_relu: Variant = carte.sommet(3.4, -5.1)
	_v.v(y_relu != null and float(y_relu) == float(y_ref),
		"plat : deuxieme lecture (cache) != premiere (%s vs %s)" % [str(y_relu), str(y_ref)])
	# Deux points de la MEME sous-cellule (ix, iz) sur terrain plat : meme
	# hauteur (le cache renvoie la meme cle donc la meme valeur).
	var y_a: Variant = carte.sommet(3.4, -5.1)
	var y_b: Variant = carte.sommet(3.5, -5.0)
	_v.v(y_a != null and y_b != null and float(y_a) == float(y_b),
		"plat : deux points d'une meme sous-cellule -> hauteurs differentes")
	# sommet_sous avec y_max au-dessus du sol : meme reponse que sommet.
	var y_sous: Variant = carte.sommet_sous(3.4, -5.1, 100.0)
	_v.v(y_sous != null and float(y_sous) == float(y_ref),
		"plat : sommet_sous(y_max=100) != sommet (%s vs %s)" % [str(y_sous), str(y_ref)])
	print("plat : cache lu bit-exact, sommet et sommet_sous coherents (y=%s)" % str(y_ref))


func _juger_sculpte_invalide_cache() -> void:
	var carte: Resource = CarteTerrain.new()
	# Chauffer le cache au point (0.5, 0.5) : sous-cellule (ix=0, iz=0) de la
	# colonne (0, 0), sommet plat par defaut.
	var y_avant: Variant = carte.sommet(0.5, 0.5)
	_v.v(y_avant != null, "sculpte : sommet avant sculpture = null")
	if y_avant == null:
		return
	# Casser le sous-cube du haut a (ix=0, iy=2, iz=0) de la cellule sommet.
	# sous_index = 0 + 2*3 + 0*9 = 6.
	var couche_sommet: int = carte.couche_base + 6
	var cell := Vector3i(0, couche_sommet, 0)
	var casse: bool = carte.casser_sous_cube(cell, 6)
	_v.v(casse, "sculpte : casser_sous_cube a rendu false")
	if not casse:
		return
	# Le cache doit avoir ete vide par marquer_sale (via casser_sous_cube :
	# set + marquer_sale direct, ou le chemin retirer_cellule -> poser_masque).
	var y_apres: Variant = carte.sommet(0.5, 0.5)
	_v.v(y_apres != null and float(y_apres) < float(y_avant),
		"sculpte : le cache n'a PAS ete vide -- meme hauteur avant/apres (%s -> %s)" % [str(y_avant), str(y_apres)])
	print("sculpte : cache invalide sur mutation, hauteur relue reflete la cassure (%s -> %s)" % [str(y_avant), str(y_apres)])


func _juger_rampe_continue() -> void:
	var carte: Resource = CarteTerrain.new()
	# Profil de rampe sur l'item 1 : 4 coins (u0v0, u0v1, u1v0, u1v1), montant
	# selon u (x local). Injecte sans passer par le fichier.
	var coins := PackedFloat32Array([0.0, 0.0, 1.0, 1.0])
	carte.poser_profil_hauteur(1, coins)
	# Cellule sommet de la colonne (0, 0), item 1, orientation 0.
	var couche_sommet: int = carte.couche_base + 6
	var cell := Vector3i(0, couche_sommet, 0)
	var pose: bool = carte.poser_cellule(cell, 1, 0)
	_v.v(pose, "rampe : poser_cellule(item=1) a rendu false")
	if not pose:
		return
	# Deux points DANS LA MEME sous-cellule (ix=0, iz=0), ecartes en x : le
	# profil interpole doit donner deux hauteurs distinctes. Un cache par sous-
	# cellule les quantifierait en une seule marche.
	var y_gauche: Variant = carte.sommet(0.05, 0.3)
	var y_droite: Variant = carte.sommet(0.6, 0.3)
	_v.v(y_gauche != null and y_droite != null,
		"rampe : sommet a rendu null sur cellule a profil")
	if y_gauche == null or y_droite == null:
		return
	_v.v(float(y_gauche) != float(y_droite),
		"rampe : deux points voisins d'une MEME sous-cellule -> MEME hauteur (profil quantifie : %s vs %s)" % [str(y_gauche), str(y_droite)])
	print("rampe : surface continue preservee, y(0.05) = %s != y(0.6) = %s" % [str(y_gauche), str(y_droite)])


func _juger_surplomb() -> void:
	var carte: Resource = CarteTerrain.new()
	var col := Vector2i(0, 0)
	var couche_bloc: int = carte.couche_base + 9
	# Ajouter le bit de la couche 9 au masque (couches 0..6 pleines par defaut).
	var bits_avec_bloc: int = carte.masque(col) | (1 << (couche_bloc - carte.couche_base))
	var pose: bool = carte.poser_masque(col, bits_avec_bloc)
	_v.v(pose, "surplomb : poser_masque a rendu false")
	if not pose:
		return
	# sommet rend le sommet absolu = dessus du bloc du haut (couche 9, y = 20).
	var y_top: Variant = carte.sommet(0.5, 0.5)
	_v.v(y_top != null and float(y_top) > 15.0,
		"surplomb : sommet ne rend PAS le bloc du haut (%s, attendu > 15)" % str(y_top))
	# sommet_sous(y_max=15) doit rendre le sol du dessous (y = 14), pas le bloc.
	var y_sous: Variant = carte.sommet_sous(0.5, 0.5, 15.0)
	_v.v(y_sous != null and float(y_sous) <= 15.0,
		"surplomb : sommet_sous(y_max=15) rend le bloc du haut (%s, attendu <= 15)" % str(y_sous))
	if y_sous != null and y_top != null:
		_v.v(float(y_sous) < float(y_top),
			"surplomb : sommet_sous(y_max=15) = %s pas < sommet = %s" % [str(y_sous), str(y_top)])
	# Redemander sommet_sous plus haut : le cache ne doit pas avoir ete
	# pollue par l'appel plafonne -- on redoit obtenir le sommet reel.
	var y_sous_haut: Variant = carte.sommet_sous(0.5, 0.5, 100.0)
	_v.v(y_sous_haut != null and y_top != null and float(y_sous_haut) == float(y_top),
		"surplomb : sommet_sous(y_max=100) != sommet (cache pollue par y_max=15 : %s vs %s)" % [str(y_sous_haut), str(y_top)])
	print("surplomb : sol sous y_max=15 (%s), sommet au-dessus (%s), cache non pollue" % [str(y_sous), str(y_top)])


func _conclure() -> void:
	if _v.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % _v.echecs())
		quit(1)
		return
	print("OK: _cache_sommet -- plat (lecture bit-exacte), sculpte (invalidation), rampe (continuite preservee), surplomb (y_max garde)")
	quit()
