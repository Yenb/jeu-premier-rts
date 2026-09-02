extends Node

# BANC "test_ennemi2 Mother box" -- LA TABLE DES RESSOURCES DU TERRAIN.
# Au demarrage, balaye UNE FOIS le GridMap frere, releve chaque cellule
# et lui associe une reserve initiale selon son PROFIL DE BLOC (voir
# `profil_bloc.gd` et `profils_blocs/*.tres`).
#
# UNE CELLULE = UNE RESERVE INDEPENDANTE. Une unite viendra sur UN bloc
# precis pour l'exploiter, sans toucher aux voisins.
#
# REGENERATION : chaque profil declare `regeneration_reserve` en unites
# PAR MINUTE. Un tick a 1 Hz repartit ce taux (regen/60 par seconde). Le
# tick ne parcourt QUE les cellules non pleines (`_a_regenerer`) --
# tant qu'aucune cellule n'a ete videe, le tick ne fait RIEN.
#
# GATE DE REGENERATION : une cellule ne recharge que si RIEN N'EST
# AU-DESSUS D'ELLE (pattern balance/pression, voir CLAUDE.md § LOCALITE
# SPATIALE). Verifie par un raycast vertical vers le haut, UNIQUEMENT au
# tick de regeneration et UNIQUEMENT sur les cellules non pleines. Cout
# nul tant que rien n'est vide.
#
# STOCK EN FLOAT INTERNE, RENDU EN INT : la regen est fractionnaire
# (2/60 = 0.033 par sec), on accumule proprement en float. `quantite_a`
# rend l'entier plancher pour l'affichage et la mecanique.

const ProfilBloc = preload("res://jeu/Outil de jeu/profil_bloc.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")
const INTERVALLE_TICK := 1.0  # 1 Hz

@export var profils: Array[Resource] = []

var _quantites: Dictionary = {}          # Vector3i -> int (stock courant)
var _profil_par_cellule: Dictionary = {} # Vector3i -> ProfilBloc
var _a_regenerer: Dictionary = {}        # Vector3i -> bool (cellules non pleines)
var _temps_regen: Dictionary = {}        # Vector3i -> float (secondes accumulees depuis dernier tick regen reussi)
var _profils_par_nom: Dictionary = {}    # nom_item -> ProfilBloc (garde du scan pour l'inscription runtime)
var _grille: GridMap = null
var _horloge: float = 0.0

func _ready() -> void:
	_grille = _trouver_grille()
	if _grille == null:
		push_error("ressources_terrain.gd : aucun GridMap parmi les freres, table vide")
		return
	var meshlib: MeshLibrary = _grille.mesh_library
	if meshlib == null:
		push_error("ressources_terrain.gd : GridMap sans mesh_library")
		return

	# Scanner la CARTE DATA (source de verite non-streamee), pas le GridMap
	# `_grille` (streame -- ne contient que les cellules autour du joueur au
	# moment du scan). Sans ca, les blocs bleus places loin de la position
	# initiale n'auraient jamais de reserve.
	var carte: Resource = _grille.get("carte") as Resource
	if carte == null:
		push_error("ressources_terrain.gd : GridMap sans propriete carte, scan impossible")
		return

	var par_nom: Dictionary = {}
	for p in profils:
		if p == null:
			continue
		par_nom[String(p.nom_item)] = p
	# Garde pour l'inscription runtime (cellules creees en jeu, ex. bloc bêché).
	_profils_par_nom = par_nom

	var particularites: Dictionary = carte.particularites
	for cellule in particularites:
		var code: int = int(particularites[cellule])
		var item: int = CarteTerrain.item_du_code(code)
		var nom := meshlib.get_item_name(item)
		var profil = par_nom.get(nom, null)
		if profil == null:
			continue
		if int(profil.reserve) > 0:
			_quantites[cellule] = int(profil.reserve)
			_profil_par_cellule[cellule] = profil
	add_to_group("ressources_terrain")

func _process(delta: float) -> void:
	_horloge += delta
	if _horloge < INTERVALLE_TICK:
		return
	var pas := _horloge
	_horloge = 0.0
	_tick_regeneration(pas)

# Ne parcourt QUE les cellules non pleines. Une cellule pleine n'est pas
# dans `_a_regenerer`. Une cellule vide/partielle y est. Coût nul tant
# qu'aucune extraction n'a vidé une cellule.
#
# REGENERATION PAR PAS : chaque cellule accumule `dt` secondes tant qu'un
# tour ne peut pas se faire (rien au-dessus). Quand l'accumule atteint
# `duree_regen_secondes`, on ajoute `quantite_regen` unites et on remet
# le compteur a zero. Ainsi le joueur voit "toutes les X secondes, +N".
func _tick_regeneration(dt: float) -> void:
	if _a_regenerer.is_empty():
		return
	var espace := get_tree().root.get_world_3d().direct_space_state
	if espace == null:
		return
	var terminees: Array = []
	for cellule in _a_regenerer:
		var profil = _profil_par_cellule.get(cellule, null)
		if profil == null:
			terminees.append(cellule)
			continue
		if int(profil.quantite_regen) <= 0 or float(profil.duree_regen_secondes) <= 0.0:
			# Profil sans regeneration : cellule videe reste vidée pour
			# toujours. Sortir de la liste, plus la peine d'y revenir.
			terminees.append(cellule)
			continue
		# Gate : rien au-dessus de la cellule ?
		if _quelque_chose_au_dessus(cellule, espace):
			# Un objet couvre : le compteur ne monte PAS (regeneration
			# strictement conditionnee a l'absence de couverture).
			continue
		var t := float(_temps_regen.get(cellule, 0.0)) + dt
		if t >= float(profil.duree_regen_secondes):
			t = 0.0
			var q := int(_quantites.get(cellule, 0)) + int(profil.quantite_regen)
			var cap := int(profil.reserve)
			if q >= cap:
				q = cap
				terminees.append(cellule)
			_quantites[cellule] = q
		_temps_regen[cellule] = t
	for c in terminees:
		_a_regenerer.erase(c)
		_temps_regen.erase(c)

func _quelque_chose_au_dessus(cellule: Vector3i, espace) -> bool:
	var centre := _grille.to_global(_grille.map_to_local(cellule))
	var pas: Vector3 = _grille.cell_size
	var depart := centre + Vector3(0, pas.y * 0.5 + 0.01, 0)
	var arrivee := depart + Vector3(0, 100.0, 0)
	var requete := PhysicsRayQueryParameters3D.create(depart, arrivee)
	# HIT_FROM_INSIDE indispensable : le raycast part de 1 cm au-dessus du
	# bloc de la case. Un geniteur pose sur la case a sa collision qui
	# commence au SOL (y_top_cellule). Le point de depart du raycast tombe
	# donc DANS la collision du geniteur -- sans hit_from_inside, Godot 4
	# ignore la frappe, le gate croit qu'il n'y a rien au-dessus, la
	# regeneration continue sous le geniteur : les cases se rechargent
	# aussi vite qu'on les vide, l'exploitation devient infinie.
	requete.hit_from_inside = true
	# ACCEPTE TOUT COLLIDER : un bloc GridMap DIRECTEMENT au-dessus bloque
	# la regeneration (physiquement une case couverte par un autre bloc
	# ne recoit pas de lumiere). Le raycast part du CENTRE haut du bloc,
	# il ne touche que ce qui est reellement au-dessus, pas les voisins
	# diagonaux.
	var frappe: Dictionary = espace.intersect_ray(requete)
	return not frappe.is_empty()

# API publique -- lister les cellules d'un type donne dans un rayon.
# Scan lineaire sur `_profil_par_cellule` (une fois par appel, pas par
# frame). Le rayon est en metres monde. Rend un Array de Vector3i, trie
# par distance CROISSANTE au centre.
func cellules_par_nom_dans_rayon(centre: Vector3, rayon: float, nom_item: String) -> Array[Vector3i]:
	var resultats: Array = []
	if _grille == null:
		return []
	var rayon2 := rayon * rayon
	for cellule in _profil_par_cellule:
		var profil = _profil_par_cellule[cellule]
		if String(profil.nom_item) != nom_item:
			continue
		var centre_cellule := _grille.to_global(_grille.map_to_local(cellule))
		var d2 := (centre_cellule - centre).length_squared()
		if d2 > rayon2:
			continue
		resultats.append({"cellule": cellule, "d2": d2})
	resultats.sort_custom(func(a, b): return a.d2 < b.d2)
	var final: Array[Vector3i] = []
	for r in resultats:
		final.append(r.cellule)
	return final

func _trouver_grille() -> GridMap:
	var parent := get_parent()
	if parent == null:
		return null
	for f in parent.get_children():
		if f is GridMap:
			return f
	return null

# API publique -- rend le profil (Resource) d'une cellule ou null si aucun.
# Sert aux consommateurs a interroger type_effondrement, reserve, etc.
func profil_de_cellule(cellule: Vector3i) -> Resource:
	return _profil_par_cellule.get(cellule, null)

# API publique -- lecture. Rend l'entier stock.
func quantite_a(cellule: Vector3i) -> int:
	return int(_quantites.get(cellule, 0))

# API publique -- combien de cellules ont un profil (peu importe le stock).
func compte_reserves() -> int:
	return _profil_par_cellule.size()

# API publique -- decrement une cellule d'une quantite donnee. Rend ce
# qui a ete effectivement preleve (borne au stock disponible). Marque la
# cellule pour regeneration si elle n'est plus pleine.
func preleve(cellule: Vector3i, quantite: float) -> float:
	if not _profil_par_cellule.has(cellule):
		return 0.0
	# Reserve NON PRELEVABLE (fertilite du sol) : lue, jamais retiree au clic.
	# Gate par propriete du profil, aucune categorie nommee (doctrine ADN).
	# Champ absent (vieux profil) -> defaut true, comportement inchange.
	var profil = _profil_par_cellule[cellule]
	var prelevable = profil.get("prelevable")
	if prelevable != null and not bool(prelevable):
		return 0.0
	var stock := int(_quantites.get(cellule, 0))
	var pris: int = mini(int(quantite), stock)
	_quantites[cellule] = stock - pris
	if pris > 0:
		_a_regenerer[cellule] = true
		if not _temps_regen.has(cellule):
			_temps_regen[cellule] = 0.0
	return float(pris)

# API publique -- inscrire une cellule creee EN JEU (ex. un bloc bêché) dans la
# table des reserves. Le scan de `_ready` ne voit que ce qui existait au
# chargement ; une cellule dont l'item change pendant le jeu passe par ici. Lit
# l'item courant de la cellule sur la carte data, trouve son profil par nom
# (garde `_profils_par_nom`), pose la reserve initiale du profil. Rend true si
# une reserve a ete posee. false si aucun profil ne correspond (item non
# profile, ou profil absent de `profils` a l'inspecteur) -- sans effet, sans
# erreur.
func inscrire_cellule(cellule: Vector3i) -> bool:
	if _grille == null:
		return false
	var meshlib: MeshLibrary = _grille.mesh_library
	if meshlib == null:
		return false
	var carte: Resource = _grille.get("carte") as Resource
	if carte == null:
		return false
	var code: int = int(carte.particularites.get(cellule, -1))
	if code < 0:
		return false
	var item: int = CarteTerrain.item_du_code(code)
	var nom := meshlib.get_item_name(item)
	var profil = _profils_par_nom.get(nom, null)
	if profil == null:
		return false
	if int(profil.reserve) <= 0:
		return false
	_quantites[cellule] = int(profil.reserve)
	_profil_par_cellule[cellule] = profil
	return true
