extends Node

# BANC "test_ennemi" -- la vie du joueur, mise sur le personnage comme
# composant. NE modifie PAS personnage.gd (generique, utilise dans
# plusieurs scenes) : ce composant est SPECIFIQUE au banc, il vit ici.
#
# LE SOLDAT LE TROUVE en cherchant `subir_frappe` sur les enfants du
# noeud du groupe "observateur" (le personnage) -- meme motif que
# interaction_destruction.gd cote joueur, symetrique.
#
# NE REINVENTE PAS LE CALCUL DE DEGATS : Frappe.frapper du framework.

const Frappe = preload("res://scripts/frappe.gd")

@export var vie_max: float = 100.0
# DELAI AVANT RELOAD apres la mort : le temps de voir la barre a zero.
@export var secondes_avant_reload: float = 2.0

signal vie_changee(fraction: float)
signal mort

var entite: Dictionary
var _mort_declaree := false

func _ready() -> void:
	add_to_group("vie_joueur")
	entite = {
		"id": str(get_instance_id()),
		"proprietes": {"reserves": {"vie": {"reserve": vie_max, "capacite": vie_max}}},
	}
	# EMISSION DIFFERE D'UNE FRAME : le HUD peut ne pas encore etre connecte
	# au signal dans le meme _ready(). Un call_deferred laisse tout le monde
	# se cabler avant.
	vie_changee.emit.bind(1.0).call_deferred()

func subir_frappe(degats: float) -> void:
	if _mort_declaree:
		return
	Frappe.frapper(entite, degats, "vie")
	var reserve: float = entite.proprietes.reserves.vie.reserve
	vie_changee.emit(clampf(reserve / vie_max, 0.0, 1.0))
	if reserve <= 0.0:
		_mort_declaree = true
		mort.emit()
		# RELOAD DIFFERE : laisse le HUD montrer la barre a zero, evite
		# aussi de detruire l'arbre pendant qu'un soldat est en train de
		# nous appeler.
		var delai := get_tree().create_timer(secondes_avant_reload)
		delai.timeout.connect(func(): get_tree().reload_current_scene())
