extends SceneTree

# Test anti-regression de terrain_visible_multimesh.gd, focalise sur
# `visible_bits_col` -- le masque bitwise qui decide quels rangs d'une
# colonne sont iteres au moment de la construction du chunk.
#
# Verrouille les scenarios ou une regression casserait le rendu :
#   (a) TERRAIN PLAT : masque plein, tous voisins pleins -> SEUL le rang
#       du sommet est visible (face +Y). Les rangs enfouis sont scelles.
#   (b) GROTTE CHEZ VOISIN : le voisin a un trou entre son sommet et le
#       fond. Regression historique : lire le voisin par r_top au lieu
#       du masque complet aurait cache les faces laterales exposees
#       vers ce trou. Le test refuse ca : les rangs de la grotte doivent
#       etre visibles ici.
#   (c) PONT (colonne perchee) : bit set en haut avec du vide en dessous
#       chez SOI. Le bit haut n'a pas de plein en +Y -> visible.
#   (d) BORD DE CARTE : un voisin renvoie masque = 0 (hors emprise).
#       Aucun rang de cette colonne n'est scelle vers ce cote -> tous
#       les rangs pleins de cette colonne sont visibles (mur de bord).
#
# Aucun noeud instancie -- `visible_bits_col` est static, pure sur des
# entiers. Ce test tourne sans SurfaceTool, sans rendu, sans carte.
#
# Regle tenue : `Verif.v(cond, msg)` compte les echecs, sortie 0/1
# conditionnee sur le compte. Aucun `assert` natif -- voir scripts/verif.gd.

const Verif = preload("res://scripts/verif.gd")
const TerrainVisibleMultimesh = preload("res://jeu/Proto/terrain_visible_multimesh.gd")

func _init() -> void:
	var v = Verif.new()

	# (a) Terrain plat : 7 couches pleines, tous voisins idem.
	# Attendu : SEUL le bit 6 (sommet) visible. Bits 0-5 scelles.
	var plein_7 := 0b1111111  # bits 0..6
	var vis_a := TerrainVisibleMultimesh.visible_bits_col(
		plein_7, plein_7, plein_7, plein_7, plein_7)
	v.v(vis_a == (1 << 6),
		"(a) plat : attendu bit 6 seul, obtenu 0b%s" % [_bin(vis_a)])

	# (b) Grotte chez le voisin +X : mask 0b1000001  # rang 0 + rang 6
	#     (rang 0 solide + rang 6 solide, air entre les deux).
	# Ma colonne : 0b1111111 (plein 0..6).
	# Autres voisins : plein 7.
	# Attendu : rang 6 (sommet), plus rangs 1..5 (face laterale +X
	# exposee vers le trou du voisin). Rang 0 reste scelle (voisin +X
	# solide en rang 0). Detail :
	#   - sealed = (bits>>1) & nxp & autres_pleins
	#          = 0b0011111 & 0b1000001  # rang 0 + rang 6 & 0b1111111 & 0b1111111 & 0b1111111
	#          = 0b0000001
	#   - visible = 0b1111111 & ~0b0000001 = 0b0111110
	var voisin_grotte := (1 << 6) | (1 << 0)  # 0b1000001  # rang 0 + rang 6
	var vis_b := TerrainVisibleMultimesh.visible_bits_col(
		plein_7, voisin_grotte, plein_7, plein_7, plein_7)
	v.v(vis_b == 0b1111110,
		"(b) grotte voisin : attendu 0b1111110, obtenu 0b%s" % [_bin(vis_b)])

	# (c) Pont : ma colonne = un bit haut seul (rang 6), rien en dessous.
	# Voisins pleins.
	# Attendu : rang 6 visible (pas de bit 7 chez moi -> face +Y expose).
	# bits >> 1 = 0 (0b1000000 >> 1 = 0b0100000, mais AND avec voisins
	# 0b1111111... plein_7 = 0b1111111 -> 0b0100000 & 0b1111111 = 0b0100000)
	# Attends, recalculons proprement :
	#   bits = 0b1000000 (rang 6 seul)
	#   sealed = (bits>>1) & nxp & nxm & nzp & nzm
	#          = 0b0100000 & 0b1111111 & 0b1111111 & 0b1111111 & 0b1111111
	#          = 0b0100000
	#   visible = 0b1000000 & ~0b0100000 = 0b1000000
	# -> rang 6 visible.
	var pont := 1 << 6
	var vis_c := TerrainVisibleMultimesh.visible_bits_col(
		pont, plein_7, plein_7, plein_7, plein_7)
	v.v(vis_c == (1 << 6),
		"(c) pont : attendu bit 6 seul, obtenu 0b%s" % [_bin(vis_c)])

	# (d) Bord de carte : voisin +X hors emprise (masque = 0).
	# Ma colonne : 0b1111111.
	# Autres voisins : plein 7.
	# Attendu : sealed = (bits>>1) & 0 & plein & plein & plein = 0.
	# Tous les rangs pleins visibles -> mur de bord entier.
	var vis_d := TerrainVisibleMultimesh.visible_bits_col(
		plein_7, 0, plein_7, plein_7, plein_7)
	v.v(vis_d == plein_7,
		"(d) bord de carte : attendu 0b1111111, obtenu 0b%s" % [_bin(vis_d)])

	# (e) Colonne totalement isolee (4 voisins hors emprise).
	# Attendu : tous les rangs pleins visibles.
	var vis_e := TerrainVisibleMultimesh.visible_bits_col(plein_7, 0, 0, 0, 0)
	v.v(vis_e == plein_7,
		"(e) colonne isolee : attendu 0b1111111, obtenu 0b%s" % [_bin(vis_e)])

	# (f) Colonne vide : bits = 0 -> visible = 0 (rien a rendre).
	var vis_f := TerrainVisibleMultimesh.visible_bits_col(0, plein_7, plein_7, plein_7, plein_7)
	v.v(vis_f == 0,
		"(f) colonne vide : attendu 0, obtenu 0b%s" % [_bin(vis_f)])

	if v.echecs() > 0:
		printerr("ECHEC: %d cas rouges sur visible_bits_col" % v.echecs())
		quit(1)
	else:
		print("OK: visible_bits_col verrouille sur 6 scenarios (plat, grotte, pont, bord, isole, vide)")
		quit(0)

# Repr binaire lisible pour messages d'echec.
static func _bin(n: int) -> String:
	var s := ""
	for i in range(6, -1, -1):
		s += "1" if (n & (1 << i)) != 0 else "0"
	return s
