extends SceneTree

# LANCEUR: echec-attendu
# Ce test echoue volontairement (verif.v(1 == 2, ...)) pour prouver que
# l'alarme des tests sonne bien en --headless. Son rouge est son succes :
# le lanceur (scripts/lanceur.gd) doit lire ce marqueur et inverser le
# verdict, jamais lister ce fichier par son nom.

const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	verif.v(1 == 2, "echec volontaire pour prouver que l'alarme sonne")
	if verif.echecs() > 0:
		quit(1)
	else:
		quit(0)
