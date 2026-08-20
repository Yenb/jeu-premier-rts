extends Node3D

# BANC "test_ennemi" -- une population qui se reproduit, gatee par la
# densite locale. NE REINVENTE RIEN : meme cablage que
# jeu/plantes/vegetation.gd (voir ses lignes 769-836) sur les DEUX
# mecanismes generiques du coeur -- Monde (scripts/monde.gd) pour compter
# les voisins par requete spatiale, Gestation (scripts/gestation.gd) pour
# le compte a rebours avant naissance. Ni l'un ni l'autre ne sait ce qu'est
# un "cube" ou un "ennemi" -- c'est ce bench qui leur donne un sens.
#
# Entree : un CubeEnnemi deja pose comme enfant de ce noeud (glisse a la
# main, ou pose par une naissance precedente). Sortie : d'autres instances
# de cube_ennemi.tscn, enfants de ce meme noeud.
#
# LA DENSITE SE COMPTE COMME CHEZ LA PLANTE : la mere se compte elle-meme
# (distance zero de son propre rayon), voir vegetation.gd:peut_pousser. Le
# seuil en tient donc compte -- pas de "-1" ecrit ici.
#
# LE TICK EST A L'INTERVALLE, JAMAIS A LA FREQUENCE D'IMAGES : meme regle
# que archiviste.gd et outil_fenetre.gd -- un Timer d'une seconde, pas
# _process.

const Monde = preload("res://scripts/monde.gd")
const Gestation = preload("res://scripts/gestation.gd")
const CubeEnnemi := preload("res://jeu/Ennemie/cube_ennemi.tscn")

# TOUTES LES UNE MINUTE : gestation.gd lit ce nombre en SECONDES BRUTES, pas
# une echelle de temps de jeu -- voir son en-tete.
@export var duree_gestation: float = 60.0

# AU-DELA DE CE NOMBRE DE VOISINS (LUI-MEME COMPRIS) DANS LE RAYON, LA MERE
# N'ENTAME PLUS DE GESTATION.
@export var max_voisins: int = 5
@export var rayon_voisinage: float = 3.0

# OU TOMBE UN ENFANT, EN METRES DEPUIS SA MERE.
@export var rayon_dispersion_min: float = 1.5
@export var rayon_dispersion_max: float = 2.5

# AUCUN HASARD NON SEEDE : meme graine, memes naissances, a chaque partie.
@export var graine: int = 20260820

# INTERRUPTEUR PROPRE, jamais un commentaire de code : quand faux, aucune
# gestation ne s'entame et aucune naissance ne se joue -- mais le reste
# (retrait des detruits, comptage de voisins pour ceux qui existent) reste
# actif. Sert a geler cette mecanique le temps de tester autre chose autour
# des cubes deja poses, sans supprimer ni le noeud ni ses reglages.
@export var reproduction_active := true

const REF_REPRODUCTION := "cube"

var _monde := Monde.new()
var _catalogue: Dictionary
var _rng := RandomNumberGenerator.new()
var _prochain_id := 0

func _ready() -> void:
	_rng.seed = graine
	_catalogue = {REF_REPRODUCTION: {"duree_gestation": duree_gestation}}
	for enfant in get_children():
		if enfant is Node3D:
			_enregistrer(enfant)

	var minuteur := Timer.new()
	minuteur.wait_time = 1.0
	minuteur.autostart = true
	minuteur.timeout.connect(_avancer_dune_seconde)
	add_child(minuteur)

func _enregistrer(noeud: Node3D) -> void:
	_prochain_id += 1
	var entite := {
		"id": "cube_%d" % _prochain_id,
		"position": noeud.global_position,
		"proprietes": {"reproduction_ref": REF_REPRODUCTION},
		"noeud": noeud,
	}
	_monde.ajouter(entite, "cube", entite.position)

func _avancer_dune_seconde() -> void:
	# UNE COPIE DES CLES : une naissance ajoute a _monde.choses PENDANT cette
	# boucle, et y ajouter tout en l'iterant est indefini en GDScript.
	for id in _monde.choses.keys().duplicate():
		var entree = _monde.choses.get(id)
		if entree == null:
			continue
		var entite: Dictionary = entree.chose
		# UN CUBE DETRUIT (clic, voir interaction_destruction.gd) SORT DU
		# MONDE ICI, AU PROCHAIN TICK -- sans quoi il resterait un fantome
		# compte pour toujours dans chaque requete de densite alentour.
		if not is_instance_valid(entite.noeud):
			_monde.retirer(id)
			continue

		# INTERRUPTEUR OFF : on continue de retirer les detruits, mais aucune
		# nouvelle gestation ni aucune naissance ne se joue.
		if not reproduction_active:
			continue

		# LA DENSITE GATE AVANT DE POSER LA GESTATION -- une mere deja
		# entouree n'entame rien, elle ne l'annule pas en cours de route
		# (meme discipline que vegetation.gd:peut_pousser).
		if not entite.proprietes.has("gestation"):
			var voisins := _monde.choses_dans_rayon(entite.position, rayon_voisinage).size()
			if voisins > max_voisins:
				continue
			Gestation.poser(entite, null, _catalogue)

		Gestation.avancer(entite, _catalogue, 1.0)
		var gestation: Dictionary = entite.proprietes.get("gestation", {})
		if gestation.get("naissance_prete", false):
			entite.proprietes.erase("gestation")
			_naitre(entite)

func _naitre(mere: Dictionary) -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var rayon := _rng.randf_range(rayon_dispersion_min, rayon_dispersion_max)
	var decalage := Vector3(cos(angle) * rayon, 0.0, sin(angle) * rayon)

	var instance := CubeEnnemi.instantiate() as Node3D
	add_child(instance)
	instance.global_position = mere.position + decalage
	print("[test_ennemi] naissance : %s -> %s" % [mere.id, instance.global_position])
	_enregistrer(instance)
