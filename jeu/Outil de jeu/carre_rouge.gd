extends RigidBody3D

# BANC "test_ennemi2 Mother box" -- LE CARRE ROUGE, nourriture interne de
# la colonie ennemie. Pondu par un generateur d'energie (voir enrolement
# a cabler, morceau 2), consomme par la mother cube (voir morceau 3).
#
# INSCRIT AU MONDE PARTAGE : sans ca, la mother cube ne le percoit pas via
# Perception.percevoir (couche 1 du framework). Meme patron que
# gisement_fer.gd -- ajout au _ready, retrait au _mourir avant queue_free.
#
# PROPRIETE "nourriture" (float, defaut 5) : lue par la couche saillance
# de la mother cube pour filtrer les percepts de sa vue. La perception
# reste aveugle (rend TOUT dans son cone), la propriete "nourriture" fait
# le tri cote saillance -- respect CLAUDE.md § ADN (aucun test type ==
# "carre_rouge" dans le code de la mother cube, seulement
# proprietes.get("nourriture", 0.0) > 0.0).
# NOM VOLONTAIRE malgre l'existence d'un concept "nourriture" cote
# framework (banc_faim_thermo, banc_graisse_accoutumance) : ceux-ci sont
# des BANCS de framework qui utilisent "nourriture" comme reserve d'un
# colon, contexte different -- ici c'est une propriete-signal cote
# gameplay ennemi, pas une reserve. Yael a nomme ainsi le concept, on
# garde le mot exact.
#
# VIES : 5 (patron generateur, meme geste subir_frappe / Frappe.frapper).
# A 0 -> retrait du monde puis queue_free. Pas de phase cadavre ici
# (contraire du generateur) : un carre rouge mange disparait, il ne
# devient pas une seconde ressource.

const Frappe = preload("res://scripts/frappe.gd")

@export var vie_max: float = 5.0
# NOURRITURE : valeur de croissance apportee a la mother cube quand elle
# le mange. Yael a specifie 5. Exportee pour reglage inspecteur.
@export var nourriture: float = 5.0

var entite: Dictionary
var _barre_vie: MeshInstance3D
var _materiau_vie: ShaderMaterial

# Idempotent (protection contre double _mourir).
var _est_mort: bool = false

func _mourir() -> void:
	if _est_mort:
		return
	_est_mort = true
	# SORT DU MONDE AVANT queue_free (patron gisement_fer.gd:71-73). Sans
	# ce retrait, la mother cube percevrait encore un fantome dans
	# monde.gd et s'y dirigerait pour rien.
	var monde_partage := get_tree().get_first_node_in_group("monde_partage")
	if monde_partage != null:
		monde_partage.monde.retirer(entite.id)
	queue_free()

func _ready() -> void:
	add_to_group("carre_rouge")
	entite = {
		"id": str(get_instance_id()),
		"position": global_position,
		"proprietes": {
			"reserves": {"vie": {"reserve": vie_max, "capacite": vie_max}},
			"nourriture": nourriture,
		},
		"noeud": self,
	}
	# INSCRIT AU MONDE PARTAGE (patron gisement_fer.gd:47-49). La mother
	# cube passera par Perception.percevoir avec canal vue pour trouver
	# les carres rouges via cette inscription -- jamais via
	# get_nodes_in_group + balayage distance (interdit CLAUDE.md).
	var monde_partage := get_tree().get_first_node_in_group("monde_partage")
	if monde_partage != null:
		monde_partage.monde.ajouter(entite, "carre_rouge", global_position)

	_barre_vie = get_node("BarreDeVie/Barre") as MeshInstance3D
	# DUPLIQUE le materiau shader pour ne pas partager la fraction entre
	# plusieurs carres rouges (patron generateur_energie.gd).
	_materiau_vie = _barre_vie.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre_vie.set_surface_override_material(0, _materiau_vie)
	_rafraichir_barre()

# API publique -- appelee par ce qui frappe (mother cube en mangeage, ou
# joueur/arme quand cable plus tard).
func subir_frappe(degats: float) -> void:
	Frappe.frapper(entite, degats, "vie")
	_rafraichir_barre()
	if entite.proprietes.reserves.vie.reserve <= 0.0:
		_mourir()

func _rafraichir_barre() -> void:
	var f := clampf(entite.proprietes.reserves.vie.reserve / vie_max, 0.0, 1.0)
	_materiau_vie.set_shader_parameter("fraction", f)
