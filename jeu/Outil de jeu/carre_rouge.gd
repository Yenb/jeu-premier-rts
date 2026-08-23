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
# POURRITURE : le carre rouge disparait au timeout meme s'il n'a pas ete
# mange. Yael 2026-08-22 : ressource EPHEMERE, pas eternelle. Sans ca,
# les carres rouges s'accumulent indefiniment (le generateur en pond 1
# toutes les 60s, la mother cube n'existe pas dans v2 pour les consommer)
# et polluent la carte. 120 s = 2 min donne assez de temps pour qu'une
# mother cube ait le temps d'arriver quand elle existera.
@export var duree_pourriture: float = 600.0
# PASSIF : quand `true`, le carre rouge n'inscrit pas au monde partage et
# ne demarre pas son Timer de pourriture. Utilise par manager_proto qui
# gere lui-meme l'age et la mort en donnee (split donnee/rendu). Toutes
# les autres capacites restent actives : barre de vie, groupe
# "destructible", subir_frappe, _mourir sur vie a zero, nourriture.
@export var passif: bool = false

var entite: Dictionary
var _barre_vie: MeshInstance3D
var _materiau_vie: ShaderMaterial
# LE MONDE PARTAGE : memorise pour pouvoir appeler monde.deplacer quand
# le carre rouge est pousse par la physique (mother cube qui le mange,
# generateur qui le pousse en passant).
var _monde_partage: Node = null

# Idempotent (protection contre double _mourir).
var _est_mort: bool = false

func _mourir() -> void:
	if _est_mort:
		return
	_est_mort = true
	# SORT DU MONDE AVANT queue_free (patron gisement_fer.gd:71-73). Sans
	# ce retrait, la mother cube percevrait encore un fantome dans
	# monde.gd et s'y dirigerait pour rien.
	if _monde_partage != null:
		_monde_partage.monde.retirer(entite.id)
	queue_free()

func _process(_delta: float) -> void:
	# Synchro position monde : le carre rouge peut etre pousse par la
	# physique (mother cube qui le mange). Sans monde.deplacer, la mother
	# cube le percevrait a son ancienne case.
	if _est_mort or entite.is_empty():
		return
	entite["position"] = global_position
	if _monde_partage != null:
		_monde_partage.monde.deplacer(entite)

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
	# PASSIF : skip. Le manager_proto gere la donnee et la vue sans monde.
	if not passif:
		_monde_partage = get_tree().get_first_node_in_group("monde_partage")
		if _monde_partage != null:
			_monde_partage.monde.ajouter(entite, "carre_rouge", global_position)

		# TIMER DE POURRITURE : ephemere. Meme patron que le cadavre de
		# generateur (duree_decomposition_cadavre). _mourir est idempotent
		# (voir garde _est_mort), donc coexiste avec la mort par frappes.
		var timer_pourri := Timer.new()
		timer_pourri.wait_time = duree_pourriture
		timer_pourri.one_shot = true
		timer_pourri.autostart = true
		timer_pourri.timeout.connect(_mourir)
		add_child(timer_pourri)

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
