extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_friction.gd
#
# Verrouille le cablage de banc_friction.gd, PREMIERE DEMONSTRATION REELLE
# de "friction" fusionnee a la fabrication (chantier « friction -- fusionner
# et cabler ») : vitesse_effective/avancer/basculer_mouille/est_mouille/
# fabriquer_objets/diagnostiquer/doit_imprimer_recap (fonctions statiques,
# pures) plus un CHEMIN REEL combinant Objet.fabriquer avec
# data/banc_friction.json/data/materiaux.json/data/etats.json/
# data/proprietes_immuables_composition.json lus sur disque -- la pierre
# doit reellement glisser moins loin que le fer, qui doit glisser moins loin
# que le bois, et un objet mouille doit reellement glisser plus loin qu'un
# objet sec sur le meme intervalle de temps.

const BancFriction = preload("res://scripts/banc_friction.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_vitesse_effective_friction_nulle_rend_la_vitesse_base_exacte()
	_vitesse_effective_friction_maximale_rend_zero()
	_vitesse_effective_friction_intermediaire_reduit_proportionnellement()
	_vitesse_effective_ne_rend_jamais_negatif_meme_au_dela_de_un()

	_avancer_friction_un_ne_bouge_jamais()
	_avancer_friction_zero_glisse_sans_resistance()
	_avancer_mute_distance_parcourue_sur_chaque_objet()

	_est_mouille_lit_etats_actifs()
	_basculer_mouille_pose_puis_retire_sur_tous_les_objets_a_la_fois()
	_basculer_mouille_sur_array_vide_ne_fait_rien()

	_diagnostiquer_rend_les_quatre_champs_attendus()
	_texte_objet_porte_id_et_les_quatre_valeurs()
	_ligne_recap_porte_le_temps_et_chaque_id()

	_doit_imprimer_recap_sous_lintervalle_faux_au_dela_vrai()
	_doit_imprimer_recap_intervalle_non_positif_imprime_toujours()

	_chemin_reel_fabrication_porte_la_friction_fusionnee()
	_chemin_reel_pierre_glisse_moins_que_bois()
	_chemin_reel_fer_glisse_entre_pierre_et_bois()
	_chemin_reel_mouille_glisse_plus_que_sec()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: vitesse_effective bornee et proportionnelle, avancer mute " +
		"position/distance_parcourue, bascule de mouille sur tous les " +
		"objets a la fois, diagnostic/textes/recap corrects, chemin reel " +
		"(data/banc_friction.json/materiaux.json/etats.json/proprietes_" +
		"immuables_composition.json) ou friction est bien fusionnee a la " +
		"fabrication, la pierre glisse moins que le bois, le fer entre les " +
		"deux, et un objet mouille glisse plus loin qu'un objet sec")
	quit(0)

# ---- vitesse_effective ----

func _vitesse_effective_friction_nulle_rend_la_vitesse_base_exacte() -> void:
	var v := BancFriction.vitesse_effective(120.0, 0.0)
	verif.v(is_equal_approx(v, 120.0), "friction effective 0.0 : doit glisser a vitesse_base EXACTE, sans aucune resistance, recu %f" % v)

func _vitesse_effective_friction_maximale_rend_zero() -> void:
	var v := BancFriction.vitesse_effective(120.0, 1.0)
	verif.v(is_equal_approx(v, 0.0), "friction effective 1.0 : ne doit JAMAIS glisser, recu %f" % v)

func _vitesse_effective_friction_intermediaire_reduit_proportionnellement() -> void:
	var v := BancFriction.vitesse_effective(100.0, 0.4)
	verif.v(is_equal_approx(v, 60.0), "friction effective 0.4 : vitesse_base * (1.0 - 0.4) = 60.0, recu %f" % v)

func _vitesse_effective_ne_rend_jamais_negatif_meme_au_dela_de_un() -> void:
	var v := BancFriction.vitesse_effective(100.0, 1.5)
	verif.v(v >= 0.0, "friction effective au-dela de 1.0 (donnee incoherente) : jamais une vitesse negative, recu %f" % v)

# ---- avancer ----

func _objet_test(id: String, friction_base: float, etats_actifs: Array = []) -> Dictionary:
	return {
		"id": id,
		"position": Vector3.ZERO,
		"proprietes": {
			"friction": friction_base,
			"etats_actifs": etats_actifs.duplicate(true),
			"distance_parcourue": 0.0,
		},
	}

func _avancer_friction_un_ne_bouge_jamais() -> void:
	var objet := _objet_test("rive", 1.0)
	for i in 30:
		BancFriction.avancer([objet], 120.0, Vector3.RIGHT, 0.1, {})
	verif.v(is_equal_approx(objet.position.x, 0.0), "friction base 1.0, aucun etat : la position ne doit JAMAIS bouger, recu %f" % objet.position.x)
	verif.v(is_equal_approx(objet.proprietes.distance_parcourue, 0.0), "friction base 1.0 : distance_parcourue doit rester EXACTEMENT 0.0, recu %f" % objet.proprietes.distance_parcourue)

func _avancer_friction_zero_glisse_sans_resistance() -> void:
	var objet := _objet_test("libre", 0.0)
	var vitesse_base := 120.0
	var delta := 0.1
	var n := 30
	for i in n:
		BancFriction.avancer([objet], vitesse_base, Vector3.RIGHT, delta, {})
	var attendu: float = vitesse_base * delta * n
	verif.v(is_equal_approx(objet.proprietes.distance_parcourue, attendu), "friction base 0.0 : distance_parcourue doit etre EXACTEMENT vitesse_base*temps = %f, recu %f" % [attendu, objet.proprietes.distance_parcourue])
	verif.v(is_equal_approx(objet.position.x, attendu), "friction base 0.0 : la position x doit avoir avance EXACTEMENT de vitesse_base*temps, recu %f" % objet.position.x)

func _avancer_mute_distance_parcourue_sur_chaque_objet() -> void:
	var a := _objet_test("a", 0.5)
	var b := _objet_test("b", 0.8)
	BancFriction.avancer([a, b], 100.0, Vector3.RIGHT, 1.0, {})
	verif.v(a.proprietes.distance_parcourue > b.proprietes.distance_parcourue, "friction plus basse (0.5) doit accumuler PLUS de distance que friction plus haute (0.8) sur le meme pas")
	verif.v(a.proprietes.distance_parcourue > 0.0 and b.proprietes.distance_parcourue > 0.0, "les deux objets doivent avoir avance (aucune friction a 1.0 ici)")

# ---- est_mouille / basculer_mouille ----

func _est_mouille_lit_etats_actifs() -> void:
	verif.v(not BancFriction.est_mouille(_objet_test("x", 0.4)), "sans 'mouille' dans etats_actifs : est_mouille doit rendre faux")
	verif.v(BancFriction.est_mouille(_objet_test("x", 0.4, ["mouille"])), "'mouille' present dans etats_actifs : est_mouille doit rendre vrai")

func _basculer_mouille_pose_puis_retire_sur_tous_les_objets_a_la_fois() -> void:
	var a := _objet_test("a", 0.4)
	var b := _objet_test("b", 0.65)
	var c := _objet_test("c", 0.5)
	BancFriction.basculer_mouille([a, b, c])
	verif.v(BancFriction.est_mouille(a) and BancFriction.est_mouille(b) and BancFriction.est_mouille(c), "premier clic : les TROIS objets doivent porter 'mouille' a la fois")
	BancFriction.basculer_mouille([a, b, c])
	verif.v(not BancFriction.est_mouille(a) and not BancFriction.est_mouille(b) and not BancFriction.est_mouille(c), "second clic : les TROIS objets doivent avoir perdu 'mouille' a la fois")

func _basculer_mouille_sur_array_vide_ne_fait_rien() -> void:
	BancFriction.basculer_mouille([])
	verif.v(true, "basculer_mouille sur un Array vide ne doit jamais planter")

# ---- diagnostiquer / textes ----

func _diagnostiquer_rend_les_quatre_champs_attendus() -> void:
	var objet := _objet_test("x", 0.4, ["mouille"])
	var etats := {"mouille": {"duree": 6.0, "effets": [{"propriete": "friction", "mode": "moduler", "facteur": 0.4}]}}
	var diag := BancFriction.diagnostiquer(objet, etats)
	verif.v(is_equal_approx(diag.friction_base, 0.4), "friction_base doit etre la valeur de base non modulee")
	verif.v(is_equal_approx(diag.friction_effective, 0.16), "friction_effective doit appliquer la modulation 'mouille' x0.4 (0.4 -> 0.16), recu %f" % diag.friction_effective)
	verif.v(diag.mouille, "diag.mouille doit refleter etats_actifs")
	verif.v(is_equal_approx(diag.distance_parcourue, 0.0), "distance_parcourue initiale doit etre 0.0")

func _texte_objet_porte_id_et_les_quatre_valeurs() -> void:
	var texte := BancFriction.texte_objet("bois_friction", {"friction_base": 0.4, "friction_effective": 0.16, "mouille": true, "distance_parcourue": 42.5})
	verif.v(texte.find("bois_friction") != -1, "le texte doit porter l'id de l'objet")
	verif.v(texte.find("0.40") != -1, "le texte doit porter la friction de base")
	verif.v(texte.find("0.160") != -1, "le texte doit porter la friction effective")
	verif.v(texte.find("mouille") != -1, "le texte doit porter l'etat mouille")
	verif.v(texte.find("42.5") != -1, "le texte doit porter la distance parcourue")

func _ligne_recap_porte_le_temps_et_chaque_id() -> void:
	var a := _objet_test("bois_friction", 0.4)
	a.proprietes["distance_parcourue"] = 10.0
	var b := _objet_test("pierre_friction", 0.65)
	b.proprietes["distance_parcourue"] = 3.0
	var ligne := BancFriction.ligne_recap(5.0, [a, b], {})
	verif.v(ligne.find("t=5.0") != -1, "la ligne recap doit porter le temps")
	verif.v(ligne.find("bois_friction=10.0") != -1, "la ligne recap doit porter la distance du bois")
	verif.v(ligne.find("pierre_friction=3.0") != -1, "la ligne recap doit porter la distance de la pierre")

# ---- doit_imprimer_recap ----

func _doit_imprimer_recap_sous_lintervalle_faux_au_dela_vrai() -> void:
	verif.v(not BancFriction.doit_imprimer_recap(1.5, 0.0, 2.0), "1.5s ecoulees, intervalle 2.0 : ne doit PAS imprimer")
	verif.v(BancFriction.doit_imprimer_recap(2.0, 0.0, 2.0), "exactement l'intervalle ecoule : doit imprimer")
	verif.v(BancFriction.doit_imprimer_recap(3.0, 0.0, 2.0), "au-dela de l'intervalle : doit imprimer")

func _doit_imprimer_recap_intervalle_non_positif_imprime_toujours() -> void:
	verif.v(BancFriction.doit_imprimer_recap(0.0, 0.0, 0.0), "intervalle a 0.0 (garde degeneree) : doit toujours imprimer")

# ---- Chemin reel ----

func _catalogue_etats_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))

func _materiaux_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))

func _proprietes_immuables_reelles() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])

func _donnees_banc_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_friction.json"))

func _objets_reels() -> Array:
	var donnees := _donnees_banc_reelles()
	return BancFriction.fabriquer_objets(donnees.get("objets", []), _materiaux_reels(), _proprietes_immuables_reelles())

func _chemin_reel_fabrication_porte_la_friction_fusionnee() -> void:
	var objets := _objets_reels()
	verif.v(objets.size() == 3, "data/banc_friction.json doit declarer exactement trois objets, recu %d" % objets.size())
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	verif.v(is_equal_approx(par_id.bois_friction.proprietes.get("friction", -1.0), 0.4), "chemin reel : bois_friction doit porter friction FUSIONNEE 0.4 (data/materiaux.json:bois), recu %f" % par_id.bois_friction.proprietes.get("friction", -1.0))
	verif.v(is_equal_approx(par_id.pierre_friction.proprietes.get("friction", -1.0), 0.65), "chemin reel : pierre_friction doit porter friction FUSIONNEE 0.65 (data/materiaux.json:pierre), recu %f" % par_id.pierre_friction.proprietes.get("friction", -1.0))
	verif.v(is_equal_approx(par_id.fer_friction.proprietes.get("friction", -1.0), 0.5), "chemin reel : fer_friction doit porter friction FUSIONNEE 0.5 (data/materiaux.json:fer), recu %f" % par_id.fer_friction.proprietes.get("friction", -1.0))

func _chemin_reel_pierre_glisse_moins_que_bois() -> void:
	var objets := _objets_reels()
	var etats := _catalogue_etats_reel()
	var donnees := _donnees_banc_reelles()
	var vitesse_base: float = donnees.get("vitesse_base", 120.0)
	var direction := Vector3(1.0, 0.0, 0.0)
	for i in 50:
		BancFriction.avancer(objets, vitesse_base, direction, 0.1, etats)
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	var d_bois: float = par_id.bois_friction.proprietes.distance_parcourue
	var d_pierre: float = par_id.pierre_friction.proprietes.distance_parcourue
	verif.v(d_pierre < d_bois, "chemin reel, a sec : la pierre (friction 0.65) doit glisser MOINS loin que le bois (friction 0.4) sur le meme temps -- pierre=%f bois=%f" % [d_pierre, d_bois])

func _chemin_reel_fer_glisse_entre_pierre_et_bois() -> void:
	var objets := _objets_reels()
	var etats := _catalogue_etats_reel()
	var donnees := _donnees_banc_reelles()
	var vitesse_base: float = donnees.get("vitesse_base", 120.0)
	var direction := Vector3(1.0, 0.0, 0.0)
	for i in 50:
		BancFriction.avancer(objets, vitesse_base, direction, 0.1, etats)
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	var d_bois: float = par_id.bois_friction.proprietes.distance_parcourue
	var d_fer: float = par_id.fer_friction.proprietes.distance_parcourue
	var d_pierre: float = par_id.pierre_friction.proprietes.distance_parcourue
	verif.v(d_pierre < d_fer, "chemin reel, a sec : le fer (friction 0.5) doit glisser plus loin que la pierre (friction 0.65) -- pierre=%f fer=%f" % [d_pierre, d_fer])
	verif.v(d_fer < d_bois, "chemin reel, a sec : le fer (friction 0.5) doit glisser moins loin que le bois (friction 0.4) -- fer=%f bois=%f" % [d_fer, d_bois])

func _chemin_reel_mouille_glisse_plus_que_sec() -> void:
	var etats := _catalogue_etats_reel()
	var donnees := _donnees_banc_reelles()
	var vitesse_base: float = donnees.get("vitesse_base", 120.0)
	var direction := Vector3(1.0, 0.0, 0.0)

	var objets_sec := _objets_reels()
	var objets_mouille := _objets_reels()
	BancFriction.basculer_mouille(objets_mouille)
	verif.v(BancFriction.est_mouille(objets_mouille[0]), "garde : le second jeu d'objets doit reellement porter 'mouille' avant la mesure")

	for i in 50:
		BancFriction.avancer(objets_sec, vitesse_base, direction, 0.1, etats)
		BancFriction.avancer(objets_mouille, vitesse_base, direction, 0.1, etats)

	var par_id_sec: Dictionary = {}
	for objet in objets_sec:
		par_id_sec[objet.id] = objet
	var par_id_mouille: Dictionary = {}
	for objet in objets_mouille:
		par_id_mouille[objet.id] = objet

	for id in ["bois_friction", "pierre_friction", "fer_friction"]:
		var d_sec: float = par_id_sec[id].proprietes.distance_parcourue
		var d_mouille: float = par_id_mouille[id].proprietes.distance_parcourue
		verif.v(d_mouille > d_sec, "chemin reel : '%s' mouille doit glisser PLUS loin que '%s' sec sur le meme temps -- sec=%f mouille=%f" % [id, id, d_sec, d_mouille])

	var d_bois_mouille: float = par_id_mouille.bois_friction.proprietes.distance_parcourue
	var d_pierre_mouille: float = par_id_mouille.pierre_friction.proprietes.distance_parcourue
	verif.v(d_bois_mouille > d_pierre_mouille, "chemin reel : le bois mouille doit glisser plus loin que la pierre mouillee -- bois=%f pierre=%f" % [d_bois_mouille, d_pierre_mouille])
