extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_rendu_terrain_multimesh.gd
#
# Verrouille res://jeu/terrain/rendu_terrain_multimesh.gd :
# - S2 : une salve de modifications dans une meme tuile collapse en UN
#   rebuild de tuile, pas N. Une balle qui creuse 10 sous-cubes de la meme
#   tuile en une image ne doit pas relancer 10 fois _supprimer_tuile +
#   _creer_tuile + rebuild BVH occludeur ;
# - S3 : le tick de teinte ne fait AUCUN _ressources.call() par cellule.
#   Les deux valeurs (profil, quantite) sont mises en cache au streaming
#   dans _creer_tuile et lues au tick.
#
# Entree : bibliotheque res://jeu/terrain/bloc.tres, cartes construites ici.
# Sortie : « OK: » et code 0 si tout tient, « ECHEC: » et code 1 sinon.
#
# Regles tenues : aucun hasard, aucun texte joueur. Rien de scripts/, data/
# ni documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")
const Rendu = preload("res://jeu/terrain/rendu_terrain_multimesh.gd")

const CHEMIN_BIBLIOTHEQUE := "res://jeu/terrain/bloc.tres"
const SECTIONS := 4  # S2, S3, S2.6 (rampes sans occludeur), S2.7 (face du cube adj. rampe)

var _v
var _biblio: MeshLibrary
var _racine: Node3D
var _faites := 0

func _init() -> void:
	_v = Verif.new()
	_tout.call_deferred()

func _tout() -> void:
	_biblio = load(CHEMIN_BIBLIOTHEQUE) as MeshLibrary
	if _biblio == null:
		_v.v(false, "%s ne se charge pas" % CHEMIN_BIBLIOTHEQUE)
		_conclure()
		return
	_racine = Node3D.new()
	get_root().add_child(_racine)

	_s2_rebuild_par_tuile()
	_s3_tick_teinte_sans_call()
	_s2_6_rampes_sans_occludeur()
	_s2_7_face_cube_contre_rampe()

	_conclure()

# S2 : dix colonnes modifiees dans la meme tuile publient dix entrees dans le
# drain. _absorber_modifications_carte doit collapser en UN rebuild. Avant fix :
# 10 _creer_tuile appels ; apres fix : 1.
func _s2_rebuild_par_tuile() -> void:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 40
	var rendu: Node3D = Rendu.new()
	rendu.carte = carte
	rendu.mesh_library = _biblio
	rendu.rayon_cellules = 30
	rendu.taille_tuile_cellules = 10
	rendu.groupe_observateur = &"aucun_pour_ce_test"
	rendu.tuiles_par_frame = 1000  # vider la file en une frame
	_racine.add_child(rendu)
	# _ready remplit _file_creation ; _process draine et bat les tuiles.
	rendu._process(0.0)

	var tuile_cible := Vector2i(0, 0)
	if not rendu._tuiles.has(tuile_cible) or (rendu._tuiles[tuile_cible] as Array).is_empty():
		_v.v(false, "la tuile cible (0,0) n'est pas batie apres le premier _process")
		rendu.queue_free()
		_faites += 1
		return

	# Vider le drain accumule par le streaming initial.
	carte.drainer_modifications("rendu_terrain_multimesh")
	rendu._creations_tuile_compte = 0

	# DIX COLONNES DIFFERENTES DE LA MEME TUILE. taille_tuile = 10 -> colonnes
	# 0..9 sur les deux axes appartiennent a la tuile (0,0).
	var sommet: int = int(carte.sommet_de_base())
	for i in range(10):
		var cellule := Vector3i(i, sommet, 0)
		var change: bool = carte.casser_sous_cube(cellule, 0)
		_v.v(change, "casser_sous_cube n'a rien fait sur la cellule %v" % [cellule])

	rendu._absorber_modifications_carte()

	_v.v(rendu._creations_tuile_compte == 1,
		"10 colonnes modifiees dans la meme tuile ont declenche %d rebuilds, 1 attendu"
			% rendu._creations_tuile_compte)

	# GARDE-FOU : deux tuiles differentes -> 2 rebuilds, pas 1.
	carte.drainer_modifications("rendu_terrain_multimesh")
	rendu._creations_tuile_compte = 0
	var tuile_2 := Vector2i(1, 0)
	if not rendu._tuiles.has(tuile_2) or (rendu._tuiles[tuile_2] as Array).is_empty():
		_v.v(false, "la tuile voisine (1,0) n'est pas batie : garde-fou impossible")
	else:
		carte.casser_sous_cube(Vector3i(0, sommet, 0), 1)   # tuile (0,0)
		carte.casser_sous_cube(Vector3i(10, sommet, 0), 0)  # tuile (1,0)
		rendu._absorber_modifications_carte()
		_v.v(rendu._creations_tuile_compte == 2,
			"deux tuiles touchees ont declenche %d rebuilds, 2 attendus"
				% rendu._creations_tuile_compte)

	rendu.queue_free()
	_faites += 1

# S3 : le tick ne doit plus faire aucun _ressources.call(). Stub instrumente
# qui compte les appels et rend un profil valide (Resource avec propriete
# `reserve` exportee).
func _s3_tick_teinte_sans_call() -> void:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 40

	# Stub compte-appels dans le bon groupe.
	var stub_script := GDScript.new()
	stub_script.source_code = "extends Node\n" \
		+ "var appels_profil: int = 0\n" \
		+ "var appels_quantite: int = 0\n" \
		+ "var profil: Resource\n" \
		+ "func profil_de_cellule(_cellule):\n" \
		+ "\tappels_profil += 1\n" \
		+ "\treturn profil\n" \
		+ "func quantite_a(_cellule):\n" \
		+ "\tappels_quantite += 1\n" \
		+ "\treturn 60\n"
	stub_script.reload()
	var stub: Node = Node.new()
	stub.set_script(stub_script)
	stub.add_to_group(&"ressources_terrain")
	_racine.add_child(stub)

	# Profil : Resource avec propriete `reserve` exportee, lue par profil.get(
	# "reserve") dans _tick_teinte.
	var profil_script := GDScript.new()
	profil_script.source_code = "extends Resource\n@export var reserve: int = 100\n"
	profil_script.reload()
	var profil_res: Resource = profil_script.new()
	stub.set("profil", profil_res)

	var rendu: Node3D = Rendu.new()
	rendu.carte = carte
	rendu.mesh_library = _biblio
	rendu.rayon_cellules = 20
	rendu.taille_tuile_cellules = 10
	rendu.groupe_observateur = &"aucun_pour_ce_test"
	rendu.tuiles_par_frame = 1000
	_racine.add_child(rendu)
	rendu._process(0.0)

	var apres_streaming_profil: int = int(stub.appels_profil)
	var apres_streaming_qte: int = int(stub.appels_quantite)
	_v.v(apres_streaming_profil > 0,
		"le streaming n'a fait AUCUN appel a profil_de_cellule : le test ne prouve rien")
	_v.v(rendu._cache_profil_cellule.size() > 0,
		"le cache profil est vide apres streaming : rien a teinter")

	for i in range(5):
		rendu._tick_teinte()

	var delta_profil: int = int(stub.appels_profil) - apres_streaming_profil
	var delta_qte: int = int(stub.appels_quantite) - apres_streaming_qte
	_v.v(delta_profil == 0,
		"_tick_teinte a fait %d appels a profil_de_cellule apres cache, 0 attendus" % delta_profil)
	_v.v(delta_qte == 0,
		"_tick_teinte a fait %d appels a quantite_a apres cache, 0 attendus" % delta_qte)

	# INVALIDATION : une modif carte purge le cache de la tuile, _creer_tuile
	# le re-alimente. Le tick suivant ne rappelle toujours pas.
	var repere_profil: int = int(stub.appels_profil)
	carte.casser_sous_cube(Vector3i(0, int(carte.sommet_de_base()), 0), 0)
	rendu._absorber_modifications_carte()
	var apres_rebuild_profil: int = int(stub.appels_profil)
	_v.v(apres_rebuild_profil > repere_profil,
		"le rebuild d'une tuile n'a fait AUCUN appel profil : cache pas re-alimente")
	var avant_tick: int = int(stub.appels_profil)
	rendu._tick_teinte()
	_v.v(int(stub.appels_profil) == avant_tick,
		"_tick_teinte apres rebuild a fait un appel supplementaire")

	print("_tick_teinte : %d cellules teintables en cache, 0 call par tick" \
		% rendu._cache_profil_cellule.size())

	rendu.queue_free()
	stub.queue_free()
	_faites += 1

# S2.6 : une rampe emergente NE genere PAS d'occludeur cube plein. Un cube
# emergent, si. Diagnostic : la camera qui monte une rampe passait a l'interieur
# du cube d'occludeur baké autour de la rampe, ce qui cassait le culling
# Vulkan et faisait disparaitre le terrain lointain. Correction : filtrer
# positions_occl sur _quad_par_item.has(item).
const ITEM_RAMPE_TEST := 2  # ITEM_RAMPE de bloc.tres, voir test_rampe.gd

func _s2_6_rampes_sans_occludeur() -> void:
	# Tuile RAMPES SEULES (0,0) : que des cellules emergentes portant une rampe
	# -> aucun occludeur ne doit sortir.
	# Tuile CUBES SEULS (1,0) : que des cellules emergentes portant un cube
	# plein -> un occludeur avec N cubes exactement.
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 40
	var sommet_base: int = int(carte.sommet_de_base())

	var colonnes_rampes: Array[Vector2i] = []
	for x in range(2, 5):
		for z in range(2, 5):
			var col := Vector2i(x, z)
			carte.sculpter(col, sommet_base + 1)  # ajoute la couche sommet_base+1
			carte.poser_cellule(Vector3i(x, sommet_base + 1, z), ITEM_RAMPE_TEST, 0)
			colonnes_rampes.append(col)

	var colonnes_cubes: Array[Vector2i] = []
	for x in range(12, 15):
		for z in range(2, 5):
			var col := Vector2i(x, z)
			carte.sculpter(col, sommet_base + 1)  # cube plein a sommet_base+1 (item par defaut)
			colonnes_cubes.append(col)

	var rendu: Node3D = Rendu.new()
	rendu.carte = carte
	rendu.mesh_library = _biblio
	rendu.rayon_cellules = 25
	rendu.taille_tuile_cellules = 10
	rendu.groupe_observateur = &"aucun_pour_ce_test"
	rendu.tuiles_par_frame = 1000
	_racine.add_child(rendu)
	rendu._process(0.0)

	# Retrouver les occludeurs bakes par tuile. Ils sont enfants du rendu et
	# aussi listes dans _tuiles[t]. Compter par tuile.
	var occ_par_tuile: Dictionary = {}
	for tuile in rendu._tuiles:
		var noeuds = rendu._tuiles[tuile]
		if noeuds == null:
			continue
		for n in noeuds:
			if n is OccluderInstance3D:
				occ_par_tuile[tuile] = n
				break

	# Trouver dans quelle tuile tombent les colonnes rampes et cubes.
	var tuile_rampes: Vector2i = rendu._tuile_de_colonne(colonnes_rampes[0])
	var tuile_cubes: Vector2i = rendu._tuile_de_colonne(colonnes_cubes[0])

	_v.v(not occ_par_tuile.has(tuile_rampes),
		"la tuile de rampes %v a un occludeur, aucun attendu (les rampes ne doivent plus bake)"
			% [tuile_rampes])
	_v.v(occ_par_tuile.has(tuile_cubes),
		"la tuile de cubes %v n'a pas d'occludeur, un attendu (non-regression)"
			% [tuile_cubes])

	# NON-REGRESSION : la tuile de cubes a un occludeur avec le bon nombre de
	# cubes. Chaque cube => 8 sommets. Un ArrayOccluder3D expose .vertices.
	if occ_par_tuile.has(tuile_cubes):
		var occ: OccluderInstance3D = occ_par_tuile[tuile_cubes]
		var arr: ArrayOccluder3D = occ.occluder as ArrayOccluder3D
		if arr != null:
			var nb_cubes: int = arr.vertices.size() / 8
			_v.v(nb_cubes == colonnes_cubes.size(),
				"tuile cubes : %d cubes dans l'occludeur, %d attendus"
					% [nb_cubes, colonnes_cubes.size()])

	print("rampes sans occludeur : tuile rampes %v -> pas d'occludeur, tuile cubes %v -> occludeur avec %d cubes" \
		% [tuile_rampes, tuile_cubes, colonnes_cubes.size()])

	rendu.queue_free()
	_faites += 1

# S2.7 : un cube plein adjacent a une rampe voit sa face cote rampe DESSINEE.
# Avant fix : visible_bits_col tenait la rampe pour un voisin plein, le cube
# etait scelle et disparaissait -- la pente laissait voir a travers.
# Apres fix : la rampe est retiree du masque couvrant, le cube n'est plus scelle
# et sa face cote rampe est visible.
func _s2_7_face_cube_contre_rampe() -> void:
	# Cas synthetique sur la fonction statique visible_bits_col : cube au rang 6
	# entoure a 3 voisins par du couvrant plein + plafond couvrant + un voisin
	# rampe (couvrant = 0). Le rang 6 doit rester visible.
	var PLEIN_7 := (1 << 7) - 1  # rangs 0..6 pleins (masque de base par defaut)
	var bit_r6 := 1 << 6
	var plafond := 1 << 7  # rang r+1 = 7 dans MA colonne, plein
	var mon_couvrant := PLEIN_7 | plafond  # ma colonne : sol jusqu'au 6 + un cube au 7
	# On teste APRES fix : trois cotes plein couvrant, un cote rampe (0), plafond couvrant.
	var vis: int = Rendu.visible_bits_col(
		mon_couvrant,           # bits bruts, on veut voir mes cellules
		mon_couvrant,           # mon_couvrant
		PLEIN_7 | plafond,      # nxp_couvrant : plein
		PLEIN_7 | plafond,      # nxm_couvrant : plein
		PLEIN_7 | plafond,      # nzp_couvrant : plein
		0,                      # nzm_couvrant : rampe -> 0 (ne couvre pas)
	)
	_v.v((vis & bit_r6) != 0,
		"cube au rang 6 avec 1 voisin rampe : bit visible = 0, doit rester 1 (la face cote rampe doit s'ouvrir)")

	# GARDE-FOU : les 4 voisins REELLEMENT pleins + plafond -> cube au rang 6 scelle.
	var vis_scelle: int = Rendu.visible_bits_col(
		mon_couvrant, mon_couvrant,
		PLEIN_7 | plafond, PLEIN_7 | plafond, PLEIN_7 | plafond, PLEIN_7 | plafond,
	)
	_v.v((vis_scelle & bit_r6) == 0,
		"cube au rang 6 avec 4 voisins couvrants et plafond : bit visible = 1, doit etre 0 (scelle attendu)")

	# TEST INTEGRE : bake d'une tuile avec un cube et une rampe cote a cote au
	# meme rang emergent. Le cube doit apparaitre dans par_forme (au moins UNE
	# face) -- avant fix il disparaissait entierement.
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 40
	var sommet_base: int = int(carte.sommet_de_base())
	# On construit un "couloir" de plein autour d'un cube central pour maximiser
	# le scellement, avec UNE seule ouverture : une rampe adjacente.
	var couche := sommet_base + 1
	# Cube central + plafond au-dessus + 3 voisins pleins.
	var centre := Vector2i(5, 5)
	for dc in [Vector2i(0,0), Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1)]:
		var c: Vector2i = centre + dc
		carte.sculpter(c, couche)
	# Plafond du cube central.
	carte.poser_cellule(Vector3i(centre.x, couche + 1, centre.y), 0, 0)
	# Voisin cote -Z : RAMPE au meme rang.
	var col_rampe := centre + Vector2i(0, -1)
	carte.sculpter(col_rampe, couche)
	carte.poser_cellule(Vector3i(col_rampe.x, couche, col_rampe.y), 2, 0)

	var rendu: Node3D = Rendu.new()
	rendu.carte = carte
	rendu.mesh_library = _biblio
	rendu.rayon_cellules = 15
	rendu.taille_tuile_cellules = 10
	rendu.groupe_observateur = &"aucun_pour_ce_test"
	rendu.tuiles_par_frame = 1000
	_racine.add_child(rendu)
	rendu._process(0.0)

	# La tuile du cube central est batie. On cherche : combien de faces
	# du cube central sont rendues ? Le MultiMesh de l'item cube porte les
	# transforms de toutes ses faces sur la tuile. Sans acces direct au
	# per_forme, on regarde qu'il existe AU MOINS un MMi pour un item cubique.
	var tuile: Vector2i = rendu._tuile_de_colonne(centre)
	_v.v(rendu._tuiles.has(tuile) and not (rendu._tuiles[tuile] as Array).is_empty(),
		"la tuile du cube central n'est pas batie")
	var a_un_mmi_cube := false
	for n in (rendu._tuiles[tuile] as Array):
		if n is MultiMeshInstance3D:
			a_un_mmi_cube = true
			break
	_v.v(a_un_mmi_cube,
		"aucun MultiMeshInstance3D dans la tuile du cube central : le cube est cache")

	print("face cube contre rampe : visible_bits_col ouvre la face cote rampe (bit=1), garde scellement 4-couvrants (bit=0), tuile bakee avec MMi")

	rendu.queue_free()
	_faites += 1

func _conclure() -> void:
	_v.v(_faites == SECTIONS,
		"%d sections sur %d sont allees jusqu'au bout" % [_faites, SECTIONS])
	if _racine != null:
		_racine.queue_free()
	if _v.echecs() > 0:
		print("ECHEC: rendu_terrain_multimesh ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: rendu_terrain_multimesh -- une salve de modifs dans une meme tuile collapse en un rebuild, et le tick de teinte ne fait plus aucun call() par cellule")
	quit(0)
