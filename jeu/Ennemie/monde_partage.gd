extends Node

# BANC "test_ennemi" -- un nœud unique qui expose une instance de
# scripts/monde.gd, PARTAGEE par tous les objets de la scene qui veulent
# etre percus ou percevoir. Sans lui, chaque banc aurait son propre monde
# privee et rien ne verrait rien.
#
# S'ENREGISTRE DANS UN GROUPE : les autres bancs le trouvent par
# `get_tree().get_first_node_in_group("monde_partage")`, jamais par un
# chemin absolu -- deplacer ce noeud dans la scene ne doit rien casser.

const Monde = preload("res://scripts/monde.gd")

var monde: RefCounted

func _ready() -> void:
	monde = Monde.new()
	add_to_group("monde_partage")
