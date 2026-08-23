# PROTO -- peau visuelle du carre rouge, destructible par projectile.
# Aucun Timer, aucune vie interne : l'age et la mort sont geres par
# manager_proto. Ici on ne fait que : (1) declarer le nœud destructible
# pour que projectile.gd puisse le frapper, (2) queue_free au subir_frappe.
# Le manager purge de _carres au bascule rendu suivant (nœud detruit).
extends RigidBody3D

func _ready() -> void:
	add_to_group("destructible")

func subir_frappe(_degats: float) -> void:
	queue_free()
