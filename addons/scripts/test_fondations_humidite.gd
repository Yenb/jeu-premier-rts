extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_fondations_humidite.gd
#
# Verrouille le chantier "fondations dormantes friction et
# conductivite_electrique sous humidite" : data/etats.json:mouille porte
# desormais, en plus de son ecrasement d'inflammabilite deja teste par
# test_etat_effectif.gd, deux effets MODULER supplementaires (friction,
# conductivite_electrique) resolus par le meme mecanisme generique
# scripts/etat_effectif.gd -- aucune ligne de ce fichier n'a change pour ce
# chantier, ce test le prouve en chargeant le VRAI catalogue sur disque.
#
# Ne verrouille PAS de mecanisme consommateur : friction et
# conductivite_electrique restent DORMANTES (personne ne les fusionne sur
# proprietes a la fabrication, personne ne les lit encore) -- ce test
# construit lui-meme un objet portant ces proprietes, aux valeurs reelles de
# data/materiaux.json (bois), pour prouver que la RESOLUTION est correcte le
# jour ou un mecanisme les consommera.

const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	_friction_reduite_par_mouille(v, etats)
	_conductivite_electrique_augmentee_par_mouille(v, etats)
	_sans_mouille_les_deux_proprietes_restent_a_leur_base(v, etats)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: data/etats.json:mouille -- friction moduletee par 0.4 et " +
			"conductivite_electrique moduletee par 10.0, resolues par le meme " +
			"etat_effectif.gd generique, sans aucun mecanisme consommateur")
		quit(0)

func _chose_bois_mouille() -> Dictionary:
	# Valeurs reelles de data/materiaux.json:bois -- friction 0.4,
	# conductivite_electrique 1e-15 -- portees ici directement sur
	# proprietes (aucune fusion a la fabrication n'existe encore).
	return {
		"id": "bois_mouille",
		"position": Vector3.ZERO,
		"proprietes": {
			"friction": 0.4,
			"conductivite_electrique": 1e-15,
			"etats_actifs": ["mouille"],
		},
	}

func _chose_bois_sec() -> Dictionary:
	return {
		"id": "bois_sec",
		"position": Vector3.ZERO,
		"proprietes": {
			"friction": 0.4,
			"conductivite_electrique": 1e-15,
		},
	}

func _friction_reduite_par_mouille(v, etats: Dictionary) -> void:
	var chose := _chose_bois_mouille()
	var resultat := EtatEffectif.valeur(chose, "friction", etats)
	v.v(is_equal_approx(resultat, 0.4 * 0.4),
		"'mouille' doit moduler 'friction' par 0.4 (0.4 -> 0.16, surface glissante)")
	v.v(resultat < 0.4, "la friction effective mouillee doit rester strictement inferieure a la base seche")

func _conductivite_electrique_augmentee_par_mouille(v, etats: Dictionary) -> void:
	var chose := _chose_bois_mouille()
	var resultat := EtatEffectif.valeur(chose, "conductivite_electrique", etats)
	v.v(is_equal_approx(resultat, 1e-15 * 10.0),
		"'mouille' doit moduler 'conductivite_electrique' par 10.0 (1e-15 -> 1e-14)")
	v.v(resultat > 1e-15, "la conductivite effective mouillee doit rester strictement superieure a la base seche")

func _sans_mouille_les_deux_proprietes_restent_a_leur_base(v, etats: Dictionary) -> void:
	var chose := _chose_bois_sec()
	v.v(is_equal_approx(EtatEffectif.valeur(chose, "friction", etats), 0.4),
		"sans 'mouille' actif, la friction effective doit rester exactement la base")
	v.v(is_equal_approx(EtatEffectif.valeur(chose, "conductivite_electrique", etats), 1e-15),
		"sans 'mouille' actif, la conductivite effective doit rester exactement la base")
