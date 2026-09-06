extends Node

# Test de bout en bout de l'extension C++. Instancie MesheurTuile (classe C++
# enregistree par extension_terrain) et appelle bonjour(). Si la console affiche
# "MesheurTuile C++ vivant.", la chaine GDScript -> C++ fonctionne.
# A retirer une fois le vrai mesher branche.

func _ready() -> void:
	var m = MesheurTuile.new()
	print("TEST C++ -> ", m.bonjour())
	get_tree().quit()
