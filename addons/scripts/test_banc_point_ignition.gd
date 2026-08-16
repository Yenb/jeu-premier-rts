extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_point_ignition.gd
#
# Verrouille les fonctions statiques testables de banc_point_ignition.gd
# (diagnostiquer/_teinte_pour_diagnostic/_texte_label/_ligne_pose/_ligne_log)
# et, CHEMIN REEL (meme regime que test_banc_inflammabilite.gd), la
# fabrication effective des deux objets depuis data/banc_point_ignition.json
# + data/materiaux.json + data/proprietes_immuables_composition.json +
# data/menaces.json + data/temperature.json, lus sur disque -- puis UNE
# BOUCLE REELLE qui avance Propagation.avancer()/Temperature.locale() tick
# par tick jusqu'a l'ignition de cible_chaude, verifiant que cible_froide
# n'accumule JAMAIS d'exposition.

const BancPointIgnition = preload("res://scripts/banc_point_ignition.gd")
const Objet = preload("res://scripts/objet.gd")
const Propagation = preload("res://scripts/propagation.gd")
const Temperature = preload("res://scripts/temperature.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_diagnostic_intact_sans_exposition(v)
	_diagnostic_expose_en_accumulation(v)
	_diagnostic_en_feu(v)
	_diagnostic_bloque_froid(v)
	_teinte_bloque_froid_distincte_de_en_feu(v)
	_texte_label_porte_temperature_et_point_ignition(v)
	_ligne_pose_porte_temperature_et_point_ignition(v)
	_ligne_log_porte_le_statut(v)
	_donnees_reelles_deux_objets(v)
	_chemin_reel_chaude_s_enflamme_froide_jamais(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_point_ignition.gd -- diagnostic compose Propagation.delai_ignition/Temperature.locale " +
			"sans jamais reimplementer leur loi, teinte/texte distinguent bloque_froid de en_feu, chemin reel " +
			"verifie : cible_chaude s'enflamme normalement, cible_froide n'accumule jamais d'exposition malgre " +
			"une inflammabilite et une exposition identiques")
		quit(0)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _chose(delai_propagation: float, point_ignition: float, brule: bool = false) -> Dictionary:
	return {
		"proprietes": {
			"inflammable": true,
			"delai_propagation": delai_propagation,
			"point_ignition": point_ignition,
			"brule": brule,
		}
	}

func _diagnostic_intact_sans_exposition(v) -> void:
	var diag := BancPointIgnition.diagnostiquer(_chose(2.0, 300.0), 0.0, 500.0, "inflammable", {"inflammable": "brule"})
	v.v(diag.statut == "intact", "sans exposition, au-dessus du point_ignition, le statut doit etre 'intact'")

func _diagnostic_expose_en_accumulation(v) -> void:
	var diag := BancPointIgnition.diagnostiquer(_chose(2.0, 300.0), 0.5, 500.0, "inflammable", {"inflammable": "brule"})
	v.v(diag.statut == "expose", "avec une exposition positive, au-dessus du point_ignition, le statut doit etre 'expose'")

func _diagnostic_en_feu(v) -> void:
	var diag := BancPointIgnition.diagnostiquer(_chose(2.0, 300.0, true), 0.0, 500.0, "inflammable", {"inflammable": "brule"})
	v.v(diag.statut == "en_feu", "une chose qui porte deja la propriete-menace doit rendre 'en_feu'")

func _diagnostic_bloque_froid(v) -> void:
	var diag := BancPointIgnition.diagnostiquer(_chose(2.0, 300.0), 0.5, 100.0, "inflammable", {"inflammable": "brule"})
	v.v(diag.statut == "bloque_froid", "une temperature sous le point_ignition doit rendre 'bloque_froid', meme avec exposition positive")
	v.v(diag.delai_requis == -1.0, "'bloque_froid' doit porter delai_requis -1.0, jamais un delai fini")

func _teinte_bloque_froid_distincte_de_en_feu(v) -> void:
	var teinte_bloque := BancPointIgnition._teinte_pour_diagnostic({"statut": "bloque_froid", "delai_requis": -1.0}, 0.0)
	var teinte_feu := BancPointIgnition._teinte_pour_diagnostic({"statut": "en_feu", "delai_requis": 2.0}, 0.0)
	v.v(teinte_bloque != teinte_feu, "bloque_froid et en_feu doivent avoir deux teintes DIFFERENTES, distinguables sans lire le texte")

func _texte_label_porte_temperature_et_point_ignition(v) -> void:
	var diag := {"statut": "expose", "point_ignition": 300.0, "delai_requis": 2.0}
	var texte := BancPointIgnition._texte_label("cible_chaude", 500.0, diag, 1.0)
	v.v(texte.find("500.0") != -1 and texte.find("300.0") != -1,
		"le label doit porter la temperature locale ET le point_ignition")

func _ligne_pose_porte_temperature_et_point_ignition(v) -> void:
	var ligne := BancPointIgnition._ligne_pose("cible_chaude", 500.0, 300.0)
	v.v(ligne.find("cible_chaude") != -1 and ligne.find("500.0") != -1 and ligne.find("300.0") != -1,
		"la ligne de pose doit porter l'objet, la temperature locale et le point_ignition")

func _ligne_log_porte_le_statut(v) -> void:
	var diag := {"statut": "bloque_froid", "point_ignition": 300.0, "delai_requis": -1.0}
	var ligne := BancPointIgnition._ligne_log(4.0, "cible_froide", 20.0, diag, 0.0)
	v.v(ligne.find("cible_froide") != -1 and ligne.find("BLOQUE") != -1,
		"la ligne de log doit porter l'objet et le statut lisible")

func _donnees_reelles_deux_objets(v) -> void:
	var donnees := _charger_json("res://data/banc_point_ignition.json")
	v.v(donnees.objets.size() == 2, "le banc doit declarer exactement deux objets")
	v.v(donnees.feux.size() == 2, "le banc doit declarer exactement deux foyers")

	var materiaux := _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	v.v(proprietes_immuables.has("point_ignition"), "point_ignition doit etre fusionne par le patron generique, catalogue reel")

	var catalogue_types: Dictionary = {}
	for decl in donnees.objets:
		catalogue_types[decl.id] = {"inflammable": true, "portee_propagation": 900.0, "delai_propagation": 2.0, "composition": decl.composition}
	var chaude := Objet.fabriquer("cible_chaude", "cible_chaude", Vector3.ZERO, catalogue_types, materiaux, proprietes_immuables)
	v.v(is_equal_approx(chaude.proprietes.point_ignition, 300.0), "cible_chaude (bois) doit porter point_ignition=300.0 dans le catalogue reel")

	var catalogue_temperature := _charger_json("res://data/temperature.json")
	var source: Dictionary = donnees.source_temperature
	var pos_source: Array = source.position
	var source_dict := {
		"position": Vector3(pos_source[0], pos_source[1], pos_source[2]),
		"rayon": source.rayon, "temperature": source.temperature, "force": source.force,
	}
	var pos_chaude: Array = donnees.objets[0].position
	var temperature_chaude := Temperature.locale(Vector3(pos_chaude[0], pos_chaude[1], pos_chaude[2]), [source_dict], catalogue_temperature)
	v.v(temperature_chaude > 300.0, "la temperature locale reelle de cible_chaude doit depasser son point_ignition (300.0)")

	var pos_froide: Array = donnees.objets[1].position
	var temperature_froide := Temperature.locale(Vector3(pos_froide[0], pos_froide[1], pos_froide[2]), [source_dict], catalogue_temperature)
	v.v(temperature_froide < 300.0, "la temperature locale reelle de cible_froide doit rester sous son point_ignition (300.0) -- hors du rayon de la source")

func _chemin_reel_chaude_s_enflamme_froide_jamais(v) -> void:
	var donnees := _charger_json("res://data/banc_point_ignition.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var menaces := _charger_json("res://data/menaces.json")
	var catalogue_temperature := _charger_json("res://data/temperature.json")

	var delai_base: float = donnees.get("delai_propagation_base", 1.0)
	var portee: float = donnees.get("portee_propagation", 900.0)
	var catalogue_types: Dictionary = {}
	for decl in donnees.objets:
		catalogue_types[decl.id] = {"inflammable": true, "portee_propagation": portee, "delai_propagation": delai_base, "composition": decl.composition}

	var monde: Array = []
	for decl_feu in donnees.feux:
		var pos_feu: Array = decl_feu.position
		monde.append({"id": decl_feu.id, "position": Vector3(pos_feu[0], pos_feu[1], pos_feu[2]), "proprietes": {"brule": true}})

	var objets: Array = []
	for decl in donnees.objets:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue_types, materiaux, proprietes_immuables)
		monde.append(objet)
		objets.append(objet)

	var decl_source: Dictionary = donnees.source_temperature
	var pos_source: Array = decl_source.position
	var source := {
		"position": Vector3(pos_source[0], pos_source[1], pos_source[2]),
		"rayon": decl_source.rayon, "temperature": decl_source.temperature, "force": decl_source.force,
	}

	var exposition: Dictionary = {}
	var enflammees_totales: Array = []
	var pas := 0.1
	for i in 500:
		var temperature_locale: Dictionary = {}
		for objet in objets:
			temperature_locale[objet.id] = Temperature.locale(objet.position, [source], catalogue_temperature)
		var enflammees: Array = Propagation.avancer(monde, menaces, exposition, pas, {}, BancPointIgnition.INTENSITE, {}, {}, temperature_locale)
		for id in enflammees:
			if not enflammees_totales.has(id):
				enflammees_totales.append(id)

	v.v(enflammees_totales.has("cible_chaude"), "cible_chaude doit finir par s'enflammer -- temperature reelle au-dessus de son point_ignition")
	v.v(not enflammees_totales.has("cible_froide"), "cible_froide ne doit JAMAIS s'enflammer -- temperature reelle sous son point_ignition, malgre 500 pas d'exposition")
	v.v(is_equal_approx(exposition.get("cible_froide", -1.0), 0.0), "cible_froide doit avoir une exposition remise a 0.0 en permanence, jamais accumulee")
