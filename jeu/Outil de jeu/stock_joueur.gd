extends Node

# BANC "test_ennemi2 Mother box" -- LE STOCK DE RESSOURCE DU JOUEUR.
# Composant pose sur le Personnage. Emet `stock_changee(fraction)` a
# chaque variation pour que la barre HUD se mette a jour sans polling.
#
# API : `ajouter(quantite) -> float` rend ce qui a ETE ajoute (borne au
# `capacite - stock`). Utilise par inspecteur_bloc.gd au moment de
# l'extraction.

signal stock_changee(fraction: float)

@export var capacite: int = 40

var _stock: float = 0.0

func _ready() -> void:
	add_to_group("stock_joueur")
	stock_changee.emit(0.0)

func ajouter(quantite: float) -> float:
	if quantite <= 0.0:
		return 0.0
	var place := float(capacite) - _stock
	var effectif := minf(quantite, place)
	if effectif <= 0.0:
		return 0.0
	_stock += effectif
	stock_changee.emit(_stock / float(capacite))
	return effectif

func stock_courant() -> float:
	return _stock
