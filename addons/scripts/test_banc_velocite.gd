extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_velocite.gd
#
# CHEMIN REEL (meme regime que test_banc_champ.gd) : tout est lu sur disque
# (data/types.json, data/banc_velocite.json, data/banc_champ.json,
# data/champs.json, data/materiaux.json), jamais une fixture inventee pour
# les catalogues. Verrouille la COMPOSITION de trois mouvements independants
# (colon volontaire seul, golem volontaire + champ, repere jamais deplace)
# avec Velocite.avancer, DERNIER appel de _process (voir banc_velocite.gd).

const Objet = preload("res://scripts/objet.gd")
const BancChamp = preload("res://scripts/banc_champ.gd")
const BancVelocite = preload("res://scripts/banc_velocite.gd")
const BancControle = preload("res://scripts/banc_controle.gd")
const Champ = preload("res://scripts/champ.gd")
const Velocite = preload("res://scripts/velocite.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA_TICK := 1.0 / 60.0

func _init() -> void:
	var v := Verif.new()
	_colon_et_golem_fabriques_correctement(v)
	_repere_jamais_controlable_jamais_compose(v)
	_colon_immobile_velocite_nulle_avant_tout_clic(v)
	_colon_en_mouvement_velocite_non_nulle_puis_nulle_a_l_arrivee(v)
	_golem_velocite_plus_grande_pres_de_l_aimant_que_loin(v)
	_repere_velocite_reste_exactement_nulle_malgre_le_mouvement_des_autres(v)
	_texte_label_affiche_les_quatre_lignes(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_velocite.gd compose le colon volontaire (bouger_vers, REUTILISE), " +
			"le golem/aimant de banc_champ.gd (REUTILISES) et un repere immobile avec " +
			"Velocite.avancer -- la velocite du colon retombe a zero a l'arrivee, celle du " +
			"golem augmente pres de l'aimant, celle du repere reste exactement nulle")
		quit(0)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _catalogues() -> Dictionary:
	var donnees := _charger_json("res://data/banc_velocite.json")
	var donnees_champ := _charger_json("res://data/banc_champ.json")
	var catalogue_types: Dictionary = donnees.get("types", {}).duplicate(true)
	catalogue_types.merge(donnees_champ.get("types", {}).duplicate(true))
	var types_partages := _charger_json("res://data/types.json")
	catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	return {
		"donnees": donnees,
		"donnees_champ": donnees_champ,
		"types": catalogue_types,
		"materiaux": _charger_json("res://data/materiaux.json"),
		"champs": _charger_json("res://data/champs.json"),
	}

func _colon_et_golem_fabriques_correctement(v) -> void:
	var cat := _catalogues()
	var colon := Objet.fabriquer("colon_1", "colon_velocite", Vector3(0.0, -240.0, 0.0), cat.types)
	v.v(not colon.is_empty(), "le colon doit se fabriquer sans etre refuse")
	v.v(colon.proprietes.controlable == true, "le colon doit etre controlable (clic joueur)")
	v.v(colon.proprietes.vitesse == 150.0, "le colon doit porter la vitesse plafond declaree en donnee")
	v.v(not colon.proprietes.has("composition"), "le colon ne doit jamais composer de materiau -- jamais dans le champ magnetique, seul le golem l'est")

	var golem := BancChamp.fabriquer_golem_magnetique("golem_1", "golem_magnetique", cat.donnees_champ.get("golem", {}), cat.types, cat.materiaux)
	v.v(not golem.is_empty() and golem.proprietes.has("composition") and golem.proprietes.controlable == true,
		"le golem doit rester EXACTEMENT celui de banc_champ.gd -- compose, controlable")

func _repere_jamais_controlable_jamais_compose(v) -> void:
	var cat := _catalogues()
	var repere := Objet.fabriquer("repere_1", "repere", Vector3(140.0, 240.0, 0.0), cat.types)
	v.v(not repere.is_empty(), "le repere doit se fabriquer sans etre refuse")
	v.v(not repere.proprietes.get("controlable", false), "le repere ne doit jamais etre controlable -- il ne bouge jamais")
	v.v(not repere.proprietes.has("composition"), "le repere ne compose aucun materiau -- objet_physique seul")

func _colon_immobile_velocite_nulle_avant_tout_clic(v) -> void:
	var cat := _catalogues()
	var colon := Objet.fabriquer("colon_1", "colon_velocite", Vector3(0.0, -240.0, 0.0), cat.types)
	Velocite.avancer([colon], DELTA_TICK)
	Velocite.avancer([colon], DELTA_TICK)
	v.v(colon.proprietes.velocite == Vector3.ZERO, "sans ordre, le colon reste immobile -- velocite exactement nulle")

func _colon_en_mouvement_velocite_non_nulle_puis_nulle_a_l_arrivee(v) -> void:
	var cat := _catalogues()
	var colon := Objet.fabriquer("colon_1", "colon_velocite", Vector3.ZERO, cat.types)
	Velocite.avancer([colon], DELTA_TICK)
	BancControle.donner_ordre(colon, Vector3(500.0, 0.0, 0.0))
	BancControle.avancer_controle(colon, DELTA_TICK)
	Velocite.avancer([colon], DELTA_TICK)
	v.v(colon.proprietes.velocite.length() > 0.0, "en mouvement, la velocite du colon doit etre non nulle")
	v.v(is_equal_approx(colon.proprietes.velocite.length(), colon.proprietes.vitesse),
		"loin de la cible, la velocite doit correspondre exactement au plafond de vitesse volontaire (bouger_vers non borne par la distance restante)")

	for i in range(1000):
		BancControle.avancer_controle(colon, DELTA_TICK)
		if colon.proprietes.get("ordre_joueur", {}).is_empty():
			break
	Velocite.avancer([colon], DELTA_TICK)
	var position_arrivee: Vector3 = colon.position
	BancControle.avancer_controle(colon, DELTA_TICK)
	Velocite.avancer([colon], DELTA_TICK)
	v.v(colon.position == position_arrivee, "une fois l'ordre accompli, le colon ne doit plus bouger")
	v.v(colon.proprietes.velocite == Vector3.ZERO, "une fois arrive et l'ordre accompli, la velocite doit retomber exactement a zero")

func _golem_velocite_plus_grande_pres_de_l_aimant_que_loin(v) -> void:
	var cat := _catalogues()

	var golem_pres := BancChamp.fabriquer_golem_magnetique("golem_1", "golem_magnetique", cat.donnees_champ.get("golem", {}), cat.types, cat.materiaux)
	var aimant_pres := BancChamp._fabriquer_aimant("aimant_1", "aimant", {}, cat.types, cat.materiaux)
	golem_pres.position = Vector3(80.0, 0.0, 0.0)
	Velocite.avancer([golem_pres, aimant_pres], DELTA_TICK)
	Champ.avancer([golem_pres, aimant_pres], DELTA_TICK, cat.champs, cat.materiaux)
	Velocite.avancer([golem_pres, aimant_pres], DELTA_TICK)
	var vitesse_pres: float = golem_pres.proprietes.velocite.length()

	var golem_loin := BancChamp.fabriquer_golem_magnetique("golem_2", "golem_magnetique", cat.donnees_champ.get("golem", {}), cat.types, cat.materiaux)
	var aimant_loin := BancChamp._fabriquer_aimant("aimant_2", "aimant", {}, cat.types, cat.materiaux)
	golem_loin.position = Vector3(200.0, 0.0, 0.0)
	Velocite.avancer([golem_loin, aimant_loin], DELTA_TICK)
	Champ.avancer([golem_loin, aimant_loin], DELTA_TICK, cat.champs, cat.materiaux)
	Velocite.avancer([golem_loin, aimant_loin], DELTA_TICK)
	var vitesse_loin: float = golem_loin.proprietes.velocite.length()

	v.v(vitesse_pres > vitesse_loin,
		"la velocite du golem (sous le seul effet du champ) doit etre plus grande pres de l'aimant (80u) que loin (200u), recu pres=%.4f loin=%.4f" % [vitesse_pres, vitesse_loin])

func _repere_velocite_reste_exactement_nulle_malgre_le_mouvement_des_autres(v) -> void:
	var cat := _catalogues()
	var repere := Objet.fabriquer("repere_1", "repere", Vector3(140.0, 240.0, 0.0), cat.types)
	var golem := BancChamp.fabriquer_golem_magnetique("golem_1", "golem_magnetique", cat.donnees_champ.get("golem", {}), cat.types, cat.materiaux)
	var aimant := BancChamp._fabriquer_aimant("aimant_1", "aimant", cat.donnees_champ.get("aimant", {}), cat.types, cat.materiaux)
	# Position de depart (data/banc_champ.json, 280 unites) volontairement HORS
	# de "portee" (240, data/champs.json) -- ce banc attend un clic pour que le
	# golem s'approche. Rapproche ici pour que le champ produise reellement un
	# deplacement SANS clic, seul le point verifie par ce test.
	golem.position = Vector3(150.0, 0.0, 0.0)
	for i in range(10):
		Champ.avancer([golem, aimant], DELTA_TICK, cat.champs, cat.materiaux)
		Velocite.avancer([repere, golem, aimant], DELTA_TICK)
	v.v(repere.proprietes.velocite == Vector3.ZERO,
		"le repere ne bouge jamais -- sa velocite doit rester exactement nulle meme apres plusieurs ticks ou d'autres objets bougent")
	v.v(golem.proprietes.velocite != Vector3.ZERO,
		"verification croisee : le golem, lui, doit avoir reellement bouge (velocite non nulle) sur la meme sequence")

func _texte_label_affiche_les_quatre_lignes(v) -> void:
	var colon := {"id": "colon_1", "position": Vector3.ZERO, "proprietes": {"velocite": Vector3(1.0, 0.0, 0.0)}}
	var golem := {"id": "golem_1", "position": Vector3.ZERO, "proprietes": {"velocite": Vector3(2.0, 0.0, 0.0)}}
	var aimant := {"id": "aimant_1", "position": Vector3.ZERO, "proprietes": {"velocite": Vector3.ZERO}}
	var repere := {"id": "repere_1", "position": Vector3.ZERO, "proprietes": {"velocite": Vector3.ZERO}}
	var texte := BancVelocite.texte_label(colon, golem, aimant, repere)
	v.v(texte.find("colon") != -1 and texte.find("golem") != -1 and texte.find("aimant") != -1 and texte.find("repere") != -1,
		"le texte doit citer les quatre objets")
	v.v(texte.find("1.00") != -1, "le texte doit afficher la velocite du colon avec deux decimales")
