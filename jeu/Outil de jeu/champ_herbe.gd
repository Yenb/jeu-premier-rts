extends Node

# BANC "test_ennemi2 Mother box" -- WRAPPER SCENE du champ scalaire de
# l'herbe verte. Un noeud unique par scene, dans le groupe "champ_herbe",
# que chaque cube d'herbe trouve pour s'inscrire, se retirer et lire sa
# densite locale. Meme patron que monde_partage.gd.
#
# TAILLE DE CASE : la moitie du rayon de voisinage de l'herbe. Un examen
# 3x3 (rayon_cases=1) couvre alors ~1.5 rayon en cote, sous-estimant la
# surface du disque d'environ 30 % -- ecart absorbe par le reglage du seuil.

const ChampSpatial = preload("res://jeu/Outil de jeu/champ_spatial.gd")
const TAILLE_CASE := 0.20

var champ: RefCounted

func _ready() -> void:
	champ = ChampSpatial.new(TAILLE_CASE)
	add_to_group("champ_herbe")
