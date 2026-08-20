extends StaticBody3D

# BANC "test_ennemi" -- un gisement de METAL, immobile, une reserve
# finie qu'un tiers vient PRELEVER coup par coup.
#
# NE REINVENTE RIEN : la reserve VIT dans la structure standard des
# canaux du framework (proprietes.reserves.metal.reserve, meme forme
# que depense.gd/flux.gd/consommer.gd). Le transporteur appellera
# Consommer.transferer(gisement.entite, transporteur.entite, "metal",
# "charge", taux, delta) -- ce fichier n'a AUCUN geste "preleve" a
# ecrire, le framework le fait deja de facon conservative (borne a
# zero, crediter la quantite REELLEMENT prise, jamais la demandee).
#
# CE QU'IL FAIT ICI, ET LUI SEUL : exposer l'entite (pour que les
# transporteurs y accedent), rafraichir la barre a chaque changement,
# se detruire quand la reserve arrive a zero. Le tick de suivi est un
# Timer d'une seconde, meme rythme que tout ce banc.

@export var metal_max: float = 500.0

var entite: Dictionary

var _barre: MeshInstance3D
var _materiau: ShaderMaterial

func _ready() -> void:
	add_to_group("gisement")
	entite = {
		"id": str(get_instance_id()),
		"position": global_position,
		"proprietes": {
			"reserves": {"metal": {"reserve": metal_max, "capacite": metal_max}},
			# LE PROFIL DE SAILLANCE : lu par proximite.gd:evaluer, resolu
			# dans le catalogue LOCAL de transporteur.gd. Une saillance forte
			# et une portee large -- un tas de ferraille se voit et attire.
			"profil_saillance": "gisement_fer",
		},
		# LA REFERENCE AU NOEUD 3D : le transporteur en a besoin pour lire
		# la position vivante (chose.global_position) et pour tester
		# is_instance_valid apres destruction. `chose` dans monde.gd est un
		# Dictionary, pas un noeud, mais peut porter ce champ.
		"noeud": self,
	}

	# S'ENREGISTRE DANS LE MONDE PARTAGE : sans ca, aucun percevant ne le
	# trouverait via perception.gd.
	var monde_partage := get_tree().get_first_node_in_group("monde_partage")
	if monde_partage != null:
		monde_partage.monde.ajouter(entite, "gisement", global_position)
	_barre = get_node("BarreDeMetal/Barre") as MeshInstance3D
	_materiau = _barre.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre.set_surface_override_material(0, _materiau)
	_rafraichir_barre()

	# LE TICK NE SERT QU'A DEUX CHOSES : voir si la barre doit rafraichir,
	# voir si la reserve est vide. Les transporteurs mutent la reserve en
	# place via Consommer.transferer -- ce noeud ne l'apprend qu'en la
	# relisant. Un signal serait plus propre, un Timer est plus simple.
	var minuteur := Timer.new()
	minuteur.wait_time = 0.25
	minuteur.autostart = true
	minuteur.timeout.connect(_verifier)
	add_child(minuteur)

func _verifier() -> void:
	_rafraichir_barre()
	if entite.proprietes.reserves.metal.reserve <= 0.0:
		# SORT DU MONDE AVANT DE MOURIR : sans ce retrait, un transporteur
		# le percevrait encore comme un fantome dans monde.gd et s'y
		# dirigerait pour rien.
		var monde_partage := get_tree().get_first_node_in_group("monde_partage")
		if monde_partage != null:
			monde_partage.monde.retirer(entite.id)
		queue_free()

func _rafraichir_barre() -> void:
	var fraction := clampf(entite.proprietes.reserves.metal.reserve / metal_max, 0.0, 1.0)
	_materiau.set_shader_parameter("fraction", fraction)
