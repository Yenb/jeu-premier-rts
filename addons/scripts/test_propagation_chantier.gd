extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_propagation_chantier.gd
#
# Verrouille l'allumage par propagation.gd comme point d'entree du chantier
# generique (voir scripts/extinction.gd) : une chose qui s'allume recoit
# travail_restant (mute par la suite, sur l'instance) et "transformation"
# (String, reference vers le catalogue data/transformations.json
# ["transformations"]) -- resolus depuis un patron (data/transformations.json
# ["patron"]) que le type de la chose peut surcharger cle par cle. Ce test
# ne resout PAS la reference "transformation" (ca, c'est extinction.gd, voir
# test_extinction.gd) : il verrouille seulement que l'allumage pose la bonne
# reference. Verrouille aussi la remise a zero de l'exposition, a l'allumage
# et quand la source de menace voisine disparait.

const Propagation = preload("res://scripts/propagation.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

const MENACES := { "inflammable": "brule" }

const PATRON := {
	"travail_restant": 3.0,
	"transformation": "defaut",
}

# arbre_dur surcharge travail_restant, garde "transformation" au patron.
const TYPES := {
	"arbre": { "inflammable": true, "portee_propagation": 90.0, "delai_propagation": 1.0 },
	"arbre_dur": {
		"inflammable": true, "portee_propagation": 90.0, "delai_propagation": 1.0,
		"travail_restant": 10.0,
	},
}

func _init() -> void:
	var v := Verif.new()
	_ignition_pose_le_chantier_du_patron(v)
	_le_type_surcharge_le_patron(v)
	_exposition_remise_a_zero_a_l_ignition(v)
	_exposition_remise_a_zero_quand_la_source_disparait(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: l'allumage pose le chantier resolu (patron surcharge par le type), " +
			"exposition remise a zero a l'ignition et a la disparition de la source")
		quit(0)

func _chose(id: String, type: String, pos: Vector3, allume: bool) -> Dictionary:
	var objet := Objet.fabriquer(id, type, pos, TYPES)
	if allume:
		objet.proprietes["brule"] = true
	return objet

func _jusqu_a_ignition(monde: Array, exposition: Dictionary, id: String, max_ticks: int) -> bool:
	for i in max_ticks:
		var enflammees := Propagation.avancer(monde, MENACES, exposition, 0.1, PATRON)
		if enflammees.has(id):
			return true
	return false

func _ignition_pose_le_chantier_du_patron(v) -> void:
	var monde := [
		_chose("feu_0", "arbre", Vector3(0, 0, 0), true),
		_chose("arbre_1", "arbre", Vector3(50, 0, 0), false),
	]
	var exposition := {}
	var t := _jusqu_a_ignition(monde, exposition, "arbre_1", 30)
	v.v(t, "arbre_1 doit s'allumer par propagation")
	var p: Dictionary = monde[1].proprietes
	v.v(p.get("travail_restant", -1.0) == PATRON.travail_restant,
		"sans surcharge de type, travail_restant vient du patron")
	v.v(p.get("transformation", "") == PATRON.transformation,
		"sans surcharge de type, la reference transformation vient du patron")

func _le_type_surcharge_le_patron(v) -> void:
	var monde := [
		_chose("feu_0", "arbre", Vector3(0, 0, 0), true),
		_chose("arbre_dur_1", "arbre_dur", Vector3(50, 0, 0), false),
	]
	var exposition := {}
	var t := _jusqu_a_ignition(monde, exposition, "arbre_dur_1", 30)
	v.v(t, "arbre_dur_1 doit s'allumer par propagation")
	var p: Dictionary = monde[1].proprietes
	v.v(p.get("travail_restant", -1.0) == 10.0,
		"le type doit surcharger travail_restant (10.0), pas le patron (3.0)")
	v.v(p.get("transformation", "") == PATRON.transformation,
		"une cle absente du type doit venir du patron (transformation)")

func _exposition_remise_a_zero_a_l_ignition(v) -> void:
	var monde := [
		_chose("feu_0", "arbre", Vector3(0, 0, 0), true),
		_chose("arbre_1", "arbre", Vector3(50, 0, 0), false),
	]
	var exposition := {}
	_jusqu_a_ignition(monde, exposition, "arbre_1", 30)
	v.v(exposition.get("arbre_1", -1.0) == 0.0,
		"l'exposition doit retomber a zero au tick ou la chose s'allume")

func _exposition_remise_a_zero_quand_la_source_disparait(v) -> void:
	var monde := [
		_chose("feu_0", "arbre", Vector3(0, 0, 0), true),
		_chose("arbre_1", "arbre", Vector3(50, 0, 0), false),
	]
	var exposition := {}
	for i in 5:
		Propagation.avancer(monde, MENACES, exposition, 0.1, PATRON)
	v.v(exposition.get("arbre_1", 0.0) > 0.0,
		"arbre_1 doit avoir accumule de l'exposition avant le seuil")
	monde[0].proprietes.erase("brule")
	Propagation.avancer(monde, MENACES, exposition, 0.1, PATRON)
	v.v(exposition.get("arbre_1", -1.0) == 0.0,
		"une fois la source disparue, l'exposition retombe a zero")
