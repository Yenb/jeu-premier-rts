extends Control

# BANC "test_ennemi2 Mother box" -- barre HUD 2D en haut a gauche pour
# la ressource du joueur. Trouve le composant StockJoueur via le groupe
# (comme barre_joueur.gd pour la vie), pas de NodePath a renseigner.

var _remplissage: ColorRect
const LARGEUR_MAX := 250.0

func _ready() -> void:
	_remplissage = get_node("Fond/Remplissage")
	var stock = get_tree().get_first_node_in_group("stock_joueur")
	if stock == null:
		push_error("barre_ressource.gd : aucun StockJoueur dans le groupe 'stock_joueur'")
		return
	stock.stock_changee.connect(_sur_stock_changee)

func _sur_stock_changee(fraction: float) -> void:
	var nouvelle_taille := Vector2(LARGEUR_MAX * clampf(fraction, 0.0, 1.0), _remplissage.size.y)
	_remplissage.set_deferred("size", nouvelle_taille)
