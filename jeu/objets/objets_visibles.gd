extends Node3D

# CE QUI FAIT BASCULER UN OBJET DE DONNEE A NŒUD, et rien d'autre. Les objets
# existent en permanence dans le Monde ; ce nœud fabrique un corps pour ceux qui
# tombent dans un rayon autour de l'observateur, et libere celui des autres.
#
# Entree : un Monde deja peuple, une carte, un rayon, un groupe ou trouver
# l'observateur, et un catalogue de scenes par CLE de type. Sortie : des nœuds
# enfants, poses et liberes au fil des deplacements.
#
# TOUT EST DONNEE ; LE NŒUD EST UNE COUCHE TEMPORAIRE. Loin de l'observateur un
# objet n'a ni nœud ni corps physique -- il est une position et des proprietes
# dans le Monde, et il y reste. La simulation ne depend jamais de cette couche
# et ne s'arrete pas quand elle disparait. Voir SUIVI.md, DECISIONS.
#
# LE COMPTE DE NŒUDS SUIT r², JAMAIS LA POPULATION. Dix mille objets sur cent
# kilometres carres coutent le meme nombre de nœuds que cinquante : le rayon
# seul le decide. Doubler le rayon coute quatre fois, agrandir la carte coute
# zero.
#
# LA HAUTEUR VIENT DE LA CARTE, jamais d'un corps physique ni d'un rayon lance
# vers le bas. Un objet qui bascule n'a rien sous lui a cet instant : le sol
# n'est peut-etre pas encore rendu la ou il apparait. carte_terrain.gd:
# hauteur_du_sol le donne en temps constant, et c'est la MEME source que celle
# ou le terrain rendu prend ses couches -- deux sources donneraient un objet
# enfonce ou flottant au moment precis du basculement.
#
# IL NE FABRIQUE AUCUN OBJET, il ne fait que les MONTRER. Poser, deplacer,
# detruire se font dans le Monde, ou l'objet vit ; ce fichier ne connait ni ce
# qu'un objet fait, ni ce qu'il devient. La cle de type choisit une scene dans
# un catalogue de DONNEES -- aucun nom de contenu n'apparait ici.
#
# LA REQUETE PASSE PAR LE MONDE, jamais par un balayage : monde.gd range par
# case et ne lit que celles que le rayon touche. Parcourir toutes les choses
# pour filtrer ensuite ferait payer la population a chaque rafraichissement,
# ce que ce fichier existe pour eviter.
#
# Regles tenues : positions en Vector3, jamais Vector2 -- une COLONNE est un
# Vector2i, un index et pas une position. Aucun hasard. Aucun texte visible par
# le joueur. Aucun nom de contenu. Rien de scripts/, data/ ni documents/ n'est
# ecrit.

# La carte qui dit ou est le sol. Sans elle, rien ne se pose.
@export var carte: Resource

# Rayon de presence, EN METRES. Au-dela, l'objet reste une donnee.
@export var rayon_metres: float = 100.0

# De combien l'observateur doit s'ecarter, en metres, avant qu'on retouche quoi
# que ce soit. Le seuil se paie en marge : le rayon reellement garanti est
# `rayon_metres - pas_de_rafraichissement`.
@export var pas_de_rafraichissement: float = 8.0

@export var groupe_observateur: StringName = &"observateur"

# CLE DE TYPE -> PackedScene. C'est ici que le contenu entre, et nulle part
# ailleurs : ajouter une sorte d'objet est une ligne de donnees, zero ligne de
# code.
@export var scenes: Dictionary = {}

# Le Monde ou vivent les objets. Pose par le jeu, jamais fabrique ici : ce
# fichier montre, il ne possede pas.
var monde = null

# id de la chose -> le nœud qui la montre. Jamais deduit des enfants : un nœud
# libere reste dans l'arbre une frame de plus, et le compte mentirait.
var _poses: Dictionary = {}
var _centre_pose := Vector3.INF

func _process(_delta: float) -> void:
	if monde == null or carte == null:
		return
	# Variant explicite : _position_observateur rend null quand il n'y a personne,
	# et une inference depuis un Variant est refusee par le compilateur.
	var ou: Variant = _position_observateur()
	if ou == null:
		return
	var ici: Vector3 = ou
	if not doit_rafraichir(_centre_pose, ici, pas_de_rafraichissement):
		return
	rafraichir(ici)

# La position de l'observateur dans le repere de ce nœud, ou null s'il n'y en a
# pas. Sans observateur, rien ne se pose -- cas neutre, pas une panne.
func _position_observateur() -> Variant:
	var observateur := get_tree().get_first_node_in_group(groupe_observateur) as Node3D
	if observateur == null or not is_inside_tree():
		return null
	return to_local(observateur.global_position)

# LE PREMIER PASSAGE POSE TOUJOURS : sans lui, un observateur immobile a
# l'endroit exact du dernier centre ne declencherait jamais rien.
static func doit_rafraichir(centre_pose: Vector3, ou: Vector3, pas: float) -> bool:
	if centre_pose == Vector3.INF:
		return true
	return centre_pose.distance_to(ou) >= maxf(pas, 0.0)

# Les identifiants presents dans une reponse du Monde.
#
# LE MONDE REND UNE ENVELOPPE, pas la chose : { chose, type, position }. La
# chose est dedans, et c'est son id qui sert de cle -- jamais l'enveloppe, qui
# est refabriquee a chaque requete, ni la chose elle-meme, pour qu'un nœud
# survive a une chose recopiee.
static func identifiants(reponses: Array) -> Dictionary:
	var vus: Dictionary = {}
	for enveloppe in reponses:
		if enveloppe == null:
			continue
		var chose = enveloppe.get("chose")
		if chose == null:
			continue
		vus[chose.get("id")] = chose
	return vus

static func entrants(poses: Dictionary, presents: Dictionary) -> Array:
	var liste: Array = []
	for id in presents:
		if not poses.has(id):
			liste.append(id)
	return liste

static func sortants(poses: Dictionary, presents: Dictionary) -> Array:
	var liste: Array = []
	for id in poses:
		if not presents.has(id):
			liste.append(id)
	return liste

# LA POSITION D'UN OBJET, sol compris. Rend null quand la colonne ne porte rien :
# un objet au-dessus du vide ne se pose pas, il reste une donnee.
static func position_posee(source: Resource, colonne: Vector2i) -> Variant:
	var sol: Variant = source.hauteur_du_sol(colonne)
	if sol == null:
		return null
	return Vector3(
		float(colonne.x) * source.cote, float(sol), float(colonne.y) * source.cote)

# La colonne sous une position, dans le repere de la carte.
static func colonne_de(position: Vector3, source: Resource) -> Vector2i:
	return Vector2i(
		int(round(position.x / source.cote)), int(round(position.z / source.cote)))

# Pose ce qui entre dans le rayon, libere ce qui en sort. Rend le bilan :
# { poses, entrants, sortants }.
func rafraichir(ou: Vector3) -> Dictionary:
	var presents := identifiants(monde.choses_dans_rayon(ou, rayon_metres))

	var a_liberer := sortants(_poses, presents)
	for id in a_liberer:
		var noeud: Node = _poses[id]
		_poses.erase(id)
		if is_instance_valid(noeud):
			noeud.queue_free()

	var a_poser := entrants(_poses, presents)
	var poses := 0
	for id in a_poser:
		var noeud := _fabriquer(presents[id])
		if noeud != null:
			_poses[id] = noeud
			poses += 1

	_centre_pose = ou
	return { "poses": _poses.size(), "entrants": poses, "sortants": a_liberer.size() }

# Fabrique le nœud d'une chose, ou null quand rien ne peut etre pose -- type
# sans scene au catalogue, ou colonne sans sol. Les deux sont des refus, pas des
# pannes : la chose reste une donnee.
func _fabriquer(chose) -> Node:
	var cle = chose.get("type")
	if not scenes.has(cle):
		return null
	var paquet: PackedScene = scenes[cle]
	if paquet == null:
		return null

	var colonne = chose.get("colonne")
	if not (colonne is Vector2i):
		return null
	var pose: Variant = position_posee(carte, colonne)
	if pose == null:
		return null

	var noeud := paquet.instantiate() as Node3D
	if noeud == null:
		return null
	add_child(noeud)
	noeud.position = pose
	return noeud

# Combien d'objets sont actuellement montres. Le compte que borne le rayon.
func montres() -> int:
	return _poses.size()
