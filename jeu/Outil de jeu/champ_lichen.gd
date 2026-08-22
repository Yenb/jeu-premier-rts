extends Node

# BANC "test_ennemi2 Mother box" -- WRAPPER SCENE du champ scalaire du
# lichen. Un noeud unique par scene, groupe "champ_lichen", meme role que
# champ_herbe.gd.

const ChampSpatial = preload("res://jeu/Outil de jeu/champ_spatial.gd")
const TAILLE_CASE := 0.60

var champ: RefCounted

func _ready() -> void:
	champ = ChampSpatial.new(TAILLE_CASE)
	add_to_group("champ_lichen")
