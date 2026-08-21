extends Node

# COMPOSANT GENERIQUE -- enfant d'un noeud qui doit etre perceptible par
# perception.gd. Enregistre son PARENT dans le monde partage au _ready,
# rafraichit sa position a chaque frame, le retire quand il meurt.
#
# NE FAIT RIEN D'AUTRE, et surtout pas de la logique de jeu : ce fichier
# ne sait ni ce qu'est un joueur, ni ce qu'est une menace. Il n'est que
# le pont entre un noeud 3D et l'index spatial du framework. Le
# `profil_saillance` et le `type` sont regles a l'inspecteur -- deux
# reglages, jamais des noms de contenu en dur ici.

@export var type_dans_monde: String = "objet"
@export var profil_saillance: String = ""

var _monde_partage: Node = null
var _entite: Dictionary

func _ready() -> void:
	_monde_partage = get_tree().get_first_node_in_group("monde_partage")
	if _monde_partage == null:
		return
	var parent := get_parent() as Node3D
	if parent == null:
		push_error("presence_dans_monde.gd : parent n'est pas un Node3D")
		return
	_entite = {
		"id": str(parent.get_instance_id()),
		"position": parent.global_position,
		"proprietes": {},
		"noeud": parent,
	}
	if profil_saillance != "":
		_entite.proprietes["profil_saillance"] = profil_saillance
	_monde_partage.monde.ajouter(_entite, type_dans_monde, parent.global_position)

func _process(_delta: float) -> void:
	# LA POSITION SUIT LE PARENT. Sans ce refresh, un joueur qui marche
	# resterait perceptible a sa position d'origine, et invisible ou il
	# est vraiment.
	var parent := get_parent() as Node3D
	if parent == null or _monde_partage == null or _entite.is_empty():
		return
	_entite.position = parent.global_position
	_monde_partage.monde.deplacer(_entite)

func _exit_tree() -> void:
	if _monde_partage != null and not _entite.is_empty():
		_monde_partage.monde.retirer(_entite.id)
