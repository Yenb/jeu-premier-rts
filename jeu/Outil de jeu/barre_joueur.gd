extends Control

# BANC "test_ennemi" -- la barre de vie du joueur, HUD 2D en bas au centre.
# Trouve le composant VieJoueur via le groupe -- pas de NodePath a
# renseigner a la main (une propriete @export sur un CanvasLayer racine
# ne descend pas jusqu'au script d'un enfant Control).

var _remplissage: ColorRect
const LARGEUR_MAX := 300.0

func _ready() -> void:
	_remplissage = get_node("Fond/Remplissage")
	var vie = get_tree().get_first_node_in_group("vie_joueur")
	if vie == null:
		push_error("barre_joueur.gd : aucun VieJoueur dans le groupe 'vie_joueur'")
		return
	vie.vie_changee.connect(_sur_vie_changee)

func _sur_vie_changee(fraction: float) -> void:
	# set_deferred : les ancres opposees du Remplissage ne sont pas egales
	# (anchor_top=0, anchor_bottom=1), donc Godot override size juste
	# apres _ready. set_deferred attend la fin de la frame pour poser la
	# taille, apres que le layout ait ete calcule.
	var nouvelle_taille := Vector2(LARGEUR_MAX * clampf(fraction, 0.0, 1.0), _remplissage.size.y)
	_remplissage.set_deferred("size", nouvelle_taille)
