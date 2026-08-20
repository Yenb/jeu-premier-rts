extends SceneTree

# Test manuel :
# godot --headless --script jeu/objets/test_objets_visibles.gd
#
# Verrouille res://jeu/objets/objets_visibles.gd, la bascule donnee <-> nœud :
# - LE COMPTE DE NŒUDS SUIT LE RAYON, JAMAIS LA POPULATION. Dix mille objets
#   semes sur cent kilometres carres coutent le meme nombre de nœuds que
#   cinquante. C'est toute la raison d'etre de ce fichier, et rien d'autre ne le
#   verifierait : un rendu qui instancie tout est juste, seulement ruineux ;
# - TRAVERSER LA CARTE NE FAIT PAS CROITRE CE COMPTE. Un objet quitte doit etre
#   LIBERE, pas seulement cache : un nœud oublie ne se voit dans aucun compte
#   d'objets visibles, seulement dans la memoire ;
# - LA DONNEE SURVIT AU NŒUD. Ce qui sort du rayon reste dans le Monde et
#   revient quand on repasse -- c'est la difference entre decharger et detruire ;
# - LA HAUTEUR VIENT DE LA CARTE, et c'est la MEME que celle du terrain rendu.
#   Deux sources donneraient un objet enfonce ou flottant au moment ou il
#   bascule, et rien ne le signalerait ;
# - UNE COLONNE SANS SOL NE POSE RIEN : l'objet reste une donnee au lieu de
#   flotter au-dessus du vide ;
# - UN TYPE SANS SCENE AU CATALOGUE est un refus, pas une panne.
#
# Entree : un Monde et une carte construits ici, jamais le depot. Sortie : une
# ligne « OK: » et le code 0 si tout tient, « ECHEC: » et le code 1 sinon.
#
# LES JUGEMENTS SONT DIFFERES : la racine du SceneTree n'est pas prete dans
# _init, un nœud qu'on y ajoute n'entre pas dans l'arbre et son _ready ne part
# jamais.
#
# Regles tenues : positions en Vector3, jamais Vector2 -- une colonne est un
# Vector2i. Aucun hasard non seede. Les prints sont des traces de mise au point,
# pas du texte joueur. Rien de scripts/, data/ ni documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const Monde = preload("res://scripts/monde.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")
const ObjetsVisibles = preload("res://jeu/objets/objets_visibles.gd")
const TerrainVisible = preload("res://jeu/terrain/terrain_visible.gd")

const EMPRISE := 2500
const RAYON := 60.0
const PAS := 8.0
const CLE := "objet"

# La population semee, et la graine du tirage.
const GRAINE := 20260820
const SEMES := 10000

# La traversee : la carte d'un bord a l'autre, moins la marge qui garde le
# rayon entier.
const METRES_TRAVERSES := 9000.0

var _v
var _racine: Node3D

func _init() -> void:
	_v = Verif.new()
	_tout.call_deferred()

func _tout() -> void:
	var temoin: Node = ObjetsVisibles.new()
	# UN SCRIPT QUI NE COMPILE PAS ROUGIT, IL NE SE SAUTE PAS.
	if temoin == null:
		_v.v(false, "objets_visibles.gd ne s'instancie pas : le script ne compile pas")
		_conclure()
		return
	temoin.free()
	_racine = Node3D.new()
	get_root().add_child(_racine)

	await _hauteur_accordee()
	_refus()
	await _borne_et_traversee()
	_conclure()

func _carte() -> Resource:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = EMPRISE
	return carte

# Une scene d'objet minimale, fabriquee ici : ce test ne depend d'aucun contenu
# du depot.
func _scene_objet() -> PackedScene:
	var modele := Node3D.new()
	modele.name = "Objet"
	var paquet := PackedScene.new()
	paquet.pack(modele)
	modele.free()
	return paquet

func _montreur(carte: Resource) -> Node3D:
	var montreur: Node3D = ObjetsVisibles.new()
	montreur.carte = carte
	montreur.rayon_metres = RAYON
	montreur.pas_de_rafraichissement = PAS
	montreur.scenes = { CLE: _scene_objet() }
	montreur.monde = Monde.new()
	_racine.add_child(montreur)
	return montreur

# monde.gd exige un champ `position` STRUCTUREL : c'est lui qui range la chose
# dans sa case. La colonne reste ce qui designe le sol.
func _chose(id: int, colonne: Vector2i, cote: float) -> Dictionary:
	return {
		"id": id, "type": CLE, "colonne": colonne,
		"position": Vector3(float(colonne.x) * cote, 0.0, float(colonne.y) * cote),
	}

# LE PIEGE NOMME DANS SUIVI.md : la hauteur portee par la donnee et le sol rendu
# viennent-ils de la MEME source ? On mesure le sol au rayon sur un terrain
# reellement pose, et on le compare a ce que la carte annonce sans rien rendre.
func _hauteur_accordee() -> void:
	var carte := _carte()
	var colonne := Vector2i(3, -2)

	var annoncee: Variant = carte.hauteur_du_sol(colonne)
	_v.v(annoncee != null, "la carte n'annonce aucun sol sur une colonne pleine")
	if annoncee == null:
		return

	var terrain: GridMap = TerrainVisible.new()
	terrain.mesh_library = load("res://jeu/terrain/bloc.tres")
	terrain.carte = carte
	terrain.rayon_cellules = 6
	_racine.add_child(terrain)
	# La physique a besoin d'une image pour donner un corps aux cellules posees :
	# un rayon tire avant ne touche rien, et on conclurait a tort.
	await physics_frame

	var ou: Variant = ObjetsVisibles.position_posee(carte, colonne)
	_v.v(ou != null, "aucune position posee sur une colonne pleine")
	if ou == null:
		terrain.queue_free()
		return

	# Le rayon part au-dessus de la colonne et descend : il touche le terrain
	# REELLEMENT pose, pas ce que la carte raconte.
	var depart: Vector3 = (ou as Vector3) + Vector3(0.0, 40.0, 0.0)
	var arrivee: Vector3 = (ou as Vector3) - Vector3(0.0, 40.0, 0.0)
	var requete := PhysicsRayQueryParameters3D.create(
		terrain.to_global(depart), terrain.to_global(arrivee))
	var touche := terrain.get_world_3d().direct_space_state.intersect_ray(requete)
	if touche.is_empty():
		_v.v(false, "le terrain rendu n'a aucun sol la ou la carte en annonce un")
	else:
		var mesuree: float = terrain.to_local(touche["position"]).y
		_v.v(absf(mesuree - float(annoncee)) < 0.01,
			"la carte annonce le sol a %.2f m, le terrain rendu le pose a %.2f m : deux sources" % [
				float(annoncee), mesuree])
		print("hauteur : carte %.2f m, terrain rendu %.2f m" % [float(annoncee), mesuree])
	terrain.queue_free()

func _refus() -> void:
	var carte := _carte()
	var montreur := _montreur(carte)

	# UNE COLONNE SANS SOL NE POSE RIEN.
	var creusee := Vector2i(500, 500)
	carte.sculpter(creusee, carte.couche_base - 1)
	_v.v(ObjetsVisibles.position_posee(carte, creusee) == null,
		"une colonne creusee jusqu'au vide rend quand meme une position")
	_v.v(ObjetsVisibles.position_posee(carte, Vector2i(EMPRISE, 0)) == null,
		"une colonne hors emprise rend quand meme une position")

	# UN TYPE SANS SCENE est un refus, pas une panne.
	montreur.monde.ajouter(_chose(1, Vector2i(0, 0), carte.cote), CLE, Vector3.ZERO)
	montreur.monde.ajouter({
			"id": 2, "type": "inconnu", "colonne": Vector2i(1, 1),
			"position": Vector3(2, 0, 2),
		}, "inconnu", Vector3(2, 0, 2))
	montreur.monde.ajouter(_chose(3, creusee, carte.cote), CLE,
		Vector3(float(creusee.x) * carte.cote, 0.0, float(creusee.y) * carte.cote))

	montreur.rafraichir(Vector3.ZERO)
	_v.v(montreur.montres() == 1,
		"%d objets montres : seul celui qui a une scene ET un sol devait l'etre" % montreur.montres())
	montreur.queue_free()

func _borne_et_traversee() -> void:
	var carte := _carte()
	var montreur := _montreur(carte)

	# DIX MILLE OBJETS SEMES SUR CENT KILOMETRES CARRES.
	var tirage := RandomNumberGenerator.new()
	tirage.seed = GRAINE
	for i in range(SEMES):
		var colonne := Vector2i(
			tirage.randi_range(-EMPRISE, EMPRISE - 1),
			tirage.randi_range(-EMPRISE, EMPRISE - 1))
		montreur.monde.ajouter(_chose(i + 10, colonne, carte.cote), CLE, Vector3(
			float(colonne.x) * carte.cote, 0.0, float(colonne.y) * carte.cote))

	var depart := Vector3(-METRES_TRAVERSES * 0.5, 0.0, 0.0)
	var debut := Time.get_ticks_msec()
	var bilan: Dictionary = montreur.rafraichir(depart)
	var au_depart: int = bilan.poses
	_v.v(au_depart > 0, "aucun objet montre alors que dix mille sont semes")

	# LE COMPTE SUIT LE RAYON : compare a ce qu'une densite uniforme donne sur
	# un disque de ce rayon. Large, ce qu'on refuse est un compte qui suivrait
	# la POPULATION -- dix mille, ou un ordre de grandeur au-dessus.
	var cote_metres: float = float(EMPRISE * 2) * carte.cote
	var densite: float = float(SEMES) / (cote_metres * cote_metres)
	var attendu: float = densite * PI * RAYON * RAYON
	_v.v(float(au_depart) < maxf(attendu * 6.0, 12.0),
		"%d objets montres pour environ %.1f attendus sur ce rayon" % [au_depart, attendu])
	_v.v(au_depart < SEMES / 10,
		"%d objets montres sur %d semes : le compte suit la population" % [au_depart, SEMES])

	# TRAVERSEE : le compte ne doit pas croitre, et rien ne doit trainer.
	var maximum := au_depart
	var ou := depart
	var pas := 0
	while ou.x < depart.x + METRES_TRAVERSES:
		ou.x += PAS
		bilan = montreur.rafraichir(ou)
		maximum = maxi(maximum, int(bilan.poses))
		pas += 1
	var duree := Time.get_ticks_msec() - debut

	_v.v(montreur.montres() <= maximum,
		"le compte final depasse le maximum releve : impossible sans fuite")
	_v.v(maximum < SEMES / 10,
		"le compte a culmine a %d sur %d semes : des nœuds trainent derriere" % [
			maximum, SEMES])

	# RIEN NE TRAINE : les enfants vivants valent ce qui est montre.
	await process_frame
	var vivants := 0
	for enfant in montreur.get_children():
		if is_instance_valid(enfant) and not enfant.is_queued_for_deletion():
			vivants += 1
	_v.v(vivants == montreur.montres(),
		"%d nœuds enfants vivants pour %d objets montres : des nœuds ont ete oublies" % [
			vivants, montreur.montres()])

	# LA DONNEE SURVIT AU NŒUD : on revient au depart, les objets reviennent.
	bilan = montreur.rafraichir(depart)
	_v.v(int(bilan.poses) == au_depart,
		"au retour, %d objets montres contre %d a l'aller : la donnee n'a pas survecu" % [
			bilan.poses, au_depart])

	print("borne : %d objets montres sur %d semes, culmine a %d, %d pas en %d ms" % [
		au_depart, SEMES, maximum, pas, duree])
	montreur.queue_free()

func _conclure() -> void:
	if _racine != null:
		_racine.queue_free()
	if _v.echecs() > 0:
		print("ECHEC: la bascule donnee/nœud ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: objets visibles -- compte borne par le rayon et non par la population, "
		+ "traversee sans fuite, donnee qui survit au nœud, hauteur accordee avec le terrain rendu, "
		+ "colonne sans sol et type sans scene refuses sans panne")
	quit(0)
