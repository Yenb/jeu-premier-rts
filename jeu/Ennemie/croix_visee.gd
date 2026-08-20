extends Control

# BANC "test_ennemi" -- une croix au centre de l'ecran, pour voir ou vise le
# clic de interaction_destruction.gd. Purement visuel : elle ne lit ni ne
# calcule rien sur la visee reelle -- le centre de l'ecran EST le centre de
# la camera active, tant que le champ de vision n'est pas deforme.

@export var taille: float = 8.0
@export var epaisseur: float = 2.0
@export var couleur: Color = Color(1, 1, 1, 0.85)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# LA TAILLE DU VIEWPORT, JAMAIS `size` : `size` vaut ce que l'ancrage a
	# calcule au dernier passage de mise en page, pas forcement encore fait
	# au premier `_draw()`. Le viewport, lui, dit toujours la taille REELLE
	# a l'instant du dessin.
	get_viewport().size_changed.connect(queue_redraw)

func _draw() -> void:
	var centre := get_viewport().get_visible_rect().size / 2.0
	draw_line(centre - Vector2(taille, 0), centre + Vector2(taille, 0), couleur, epaisseur)
	draw_line(centre - Vector2(0, taille), centre + Vector2(0, taille), couleur, epaisseur)
