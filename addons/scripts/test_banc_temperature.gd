extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_temperature.gd
#
# Verrouille le cablage de banc_temperature.gd, PREMIERE DEMONSTRATION
# REELLE de scripts/temperature.gd : deplacement_clavier/
# position_source_mobile/sources_du_tick/fabriquer_objet_test/
# couleur_pour_temperature/texte_objet/ligne_log (fonctions statiques,
# pures) plus un CHEMIN REEL combinant Temperature.avancer/locale avec
# data/banc_temperature.json/data/temperature.json lus sur disque --
# l'objet doit reellement se rechauffer pres du feu et refroidir en
# s'en eloignant.

const BancTemperature = preload("res://scripts/banc_temperature.gd")
const Temperature = preload("res://scripts/temperature.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_deplacement_clavier_axe_seul_a_la_vitesse_pleine()
	_deplacement_clavier_normalise_la_diagonale()
	_deplacement_clavier_sans_touche_rend_zero()
	_deplacement_clavier_haut_diminue_y_bas_laugmente()

	_position_source_mobile_formule_exacte()
	_position_source_mobile_periode_nulle_reste_au_centre()

	_sources_du_tick_construit_les_deux_sources_attendues()
	_fabriquer_objet_test_porte_temperature_et_conductivite()

	_couleur_pour_temperature_bornes_exactes()
	_couleur_pour_temperature_repli_neutre_si_maxi_sous_mini()

	_texte_objet_porte_les_trois_nombres()
	_ligne_log_porte_position_et_les_trois_nombres()

	_chemin_reel_lobjet_se_rechauffe_pres_du_feu_et_refroidit_en_seloignant()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: deplacement clavier normalise, mouvement sinusoidal de la " +
		"source mobile, construction des sources du tick, fabrication de " +
		"l'objet de test, couleur froid->chaud bornee, textes HUD/console, " +
		"chemin reel (data/banc_temperature.json/data/temperature.json) ou " +
		"l'objet se rechauffe pres du feu et refroidit en s'eloignant")
	quit(0)

# ---- deplacement_clavier ----

func _deplacement_clavier_axe_seul_a_la_vitesse_pleine() -> void:
	var d := BancTemperature.deplacement_clavier(false, true, false, false, 100.0, 1.0)
	verif.v(d.is_equal_approx(Vector3(100.0, 0.0, 0.0)), "droite seule : deplacement attendu (100,0,0) (vitesse*delta plein sur un seul axe), recu %s" % d)

func _deplacement_clavier_normalise_la_diagonale() -> void:
	var diagonale := BancTemperature.deplacement_clavier(false, true, false, true, 100.0, 1.0)
	verif.v(is_equal_approx(diagonale.length(), 100.0), "droite+bas ensemble : la diagonale doit etre NORMALISEE, longueur attendue exactement 100.0 (pas 141), recu %f" % diagonale.length())
	verif.v(diagonale.x > 0.0 and diagonale.y > 0.0, "droite+bas : les deux composantes doivent rester positives")

func _deplacement_clavier_sans_touche_rend_zero() -> void:
	var d := BancTemperature.deplacement_clavier(false, false, false, false, 100.0, 1.0)
	verif.v(d == Vector3.ZERO, "aucune touche enfoncee : deplacement attendu exactement Vector3.ZERO")

func _deplacement_clavier_haut_diminue_y_bas_laugmente() -> void:
	var haut := BancTemperature.deplacement_clavier(false, false, true, false, 50.0, 1.0)
	var bas := BancTemperature.deplacement_clavier(false, false, false, true, 50.0, 1.0)
	verif.v(haut.y < 0.0, "convention Godot 2D : 'haut' doit DIMINUER y, recu %f" % haut.y)
	verif.v(bas.y > 0.0, "convention Godot 2D : 'bas' doit AUGMENTER y, recu %f" % bas.y)

# ---- position_source_mobile ----

func _position_source_mobile_formule_exacte() -> void:
	var centre := Vector3(10.0, 20.0, 0.0)
	var p0 := BancTemperature.position_source_mobile(centre, 50.0, 8.0, 0.0)
	verif.v(p0.is_equal_approx(centre), "a t=0, sin(0)=0 : la source doit etre exactement au centre, recu %s" % p0)

	var p_quart := BancTemperature.position_source_mobile(centre, 50.0, 8.0, 2.0)  # T/4 : sin(pi/2)=1
	verif.v(p_quart.is_equal_approx(centre + Vector3(50.0, 0.0, 0.0)), "a T/4, decalage attendu exactement +amplitude sur X, recu %s" % p_quart)

	var p_moitie := BancTemperature.position_source_mobile(centre, 50.0, 8.0, 4.0)  # T/2 : sin(pi)=0
	verif.v(p_moitie.is_equal_approx(centre), "a T/2, sin(pi)=0 : la source doit revenir exactement au centre (verrou de periodicite), recu %s" % p_moitie)

	var p_trois_quarts := BancTemperature.position_source_mobile(centre, 50.0, 8.0, 6.0)  # 3T/4 : sin(3pi/2)=-1
	verif.v(p_trois_quarts.is_equal_approx(centre + Vector3(-50.0, 0.0, 0.0)), "a 3T/4, decalage attendu exactement -amplitude sur X, recu %s" % p_trois_quarts)

func _position_source_mobile_periode_nulle_reste_au_centre() -> void:
	var centre := Vector3(5.0, 5.0, 0.0)
	var p := BancTemperature.position_source_mobile(centre, 999.0, 0.0, 42.0)
	verif.v(p == centre, "periode a 0.0 : repli sur le centre, jamais une division par zero ni un mouvement devine")

# ---- sources_du_tick / fabriquer_objet_test ----

func _sources_du_tick_construit_les_deux_sources_attendues() -> void:
	var feu := {"position": Vector3(1.0, 2.0, 3.0), "rayon": 10.0, "temperature": 100.0, "force": 1.0}
	var sources := BancTemperature.sources_du_tick(feu, Vector3(5.0, 6.0, 7.0), 20.0, 50.0, 2.0)
	verif.v(sources.size() == 2, "deux sources attendues (feu + mobile), recu %d" % sources.size())
	verif.v(sources[0] == feu, "la premiere source doit etre exactement le Dictionary 'feu' recu, inchange")
	verif.v(sources[1].position == Vector3(5.0, 6.0, 7.0) and sources[1].rayon == 20.0 and sources[1].temperature == 50.0 and sources[1].force == 2.0,
		"la seconde source doit porter exactement la position/rayon/temperature/force de la source mobile recus en parametre")

func _fabriquer_objet_test_porte_temperature_et_conductivite() -> void:
	var objet := BancTemperature.fabriquer_objet_test(Vector3(1.0, 2.0, 3.0), 15.0, 0.7)
	verif.v(objet.id == "objet_test", "l'id doit etre 'objet_test'")
	verif.v(objet.position == Vector3(1.0, 2.0, 3.0), "la position doit etre celle recue en parametre")
	verif.v(is_equal_approx(objet.proprietes.temperature, 15.0), "la temperature initiale doit etre celle recue en parametre")
	verif.v(is_equal_approx(objet.proprietes.conductivite_thermique, 0.7), "la conductivite doit etre celle recue en parametre")

# ---- couleur_pour_temperature ----

func _couleur_pour_temperature_bornes_exactes() -> void:
	var froid := Color(0.0, 0.0, 1.0)
	var chaud := Color(1.0, 0.0, 0.0)
	verif.v(BancTemperature.couleur_pour_temperature(0.0, 0.0, 100.0, froid, chaud) == froid, "a la borne minimale, couleur attendue exactement froid")
	verif.v(BancTemperature.couleur_pour_temperature(100.0, 0.0, 100.0, froid, chaud) == chaud, "a la borne maximale, couleur attendue exactement chaud")
	var milieu := BancTemperature.couleur_pour_temperature(50.0, 0.0, 100.0, froid, chaud)
	verif.v(is_equal_approx(milieu.r, 0.5) and is_equal_approx(milieu.b, 0.5), "a mi-echelle, couleur attendue exactement a mi-chemin entre froid et chaud, recu %s" % milieu)
	verif.v(BancTemperature.couleur_pour_temperature(-500.0, 0.0, 100.0, froid, chaud) == froid, "tres en dessous du minimum : borne a froid, jamais une extrapolation")
	verif.v(BancTemperature.couleur_pour_temperature(500.0, 0.0, 100.0, froid, chaud) == chaud, "tres au dessus du maximum : borne a chaud, jamais une extrapolation")

func _couleur_pour_temperature_repli_neutre_si_maxi_sous_mini() -> void:
	var froid := Color(0.0, 0.0, 1.0)
	var chaud := Color(1.0, 0.0, 0.0)
	verif.v(BancTemperature.couleur_pour_temperature(50.0, 80.0, 80.0, froid, chaud) == froid, "maxi <= mini : repli neutre sur froid, jamais une division par zero")

# ---- textes ----

func _texte_objet_porte_les_trois_nombres() -> void:
	var texte := BancTemperature.texte_objet(20.0, 80.0)
	verif.v(texte.find("20.0") != -1, "le texte doit porter la temperature de l'objet")
	verif.v(texte.find("80.0") != -1, "le texte doit porter la temperature locale")
	verif.v(texte.find("60.0") != -1, "le texte doit porter l'ecart exact (80-20=60), jamais recalcule par le lecteur")

func _ligne_log_porte_position_et_les_trois_nombres() -> void:
	var ligne := BancTemperature.ligne_log(5.0, Vector3(10.0, 20.0, 0.0), 30.0, 90.0)
	verif.v(ligne.find("t=5.0") != -1, "la ligne doit porter le temps")
	verif.v(ligne.find("30.0") != -1, "la ligne doit porter la temperature de l'objet")
	verif.v(ligne.find("90.0") != -1, "la ligne doit porter la temperature locale")
	verif.v(ligne.find("60.0") != -1, "la ligne doit porter l'ecart exact (90-30=60)")

# ---- Chemin reel ----

func _catalogue_temperature_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/temperature.json"))

func _donnees_banc_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_temperature.json"))

func _chemin_reel_lobjet_se_rechauffe_pres_du_feu_et_refroidit_en_seloignant() -> void:
	var catalogue := _catalogue_temperature_reel()
	var donnees := _donnees_banc_reelles()
	verif.v(catalogue.has("defaut"), "data/temperature.json doit porter une entree 'defaut'")

	var decl_feu: Dictionary = donnees.get("feu", {})
	var pos_feu: Array = decl_feu.get("position", [0.0, 0.0, 0.0])
	var feu := {
		"position": Vector3(pos_feu[0], pos_feu[1], pos_feu[2]),
		"rayon": decl_feu.get("rayon", 300.0),
		"temperature": decl_feu.get("temperature", 300.0),
		"force": decl_feu.get("force", 1.0),
	}

	var decl_objet: Dictionary = donnees.get("objet_test", {})
	var objet := BancTemperature.fabriquer_objet_test(feu.position, decl_objet.get("temperature_initiale", 20.0), decl_objet.get("conductivite_thermique", 0.4))
	var monde := [objet]
	var ambiante: float = catalogue.defaut.get("ambiante", 20.0)
	var temperature_initiale: float = objet.proprietes.temperature

	# Plusieurs pas au centre exact du feu reel : la temperature doit monter.
	for i in 30:
		Temperature.avancer(monde, [feu], 0.05, catalogue)
	var temperature_pres_du_feu: float = objet.proprietes.temperature
	verif.v(temperature_pres_du_feu > temperature_initiale, "chemin reel : au centre du feu reel, apres plusieurs pas, la temperature doit avoir strictement monte (partie de %f, arrivee a %f)" % [temperature_initiale, temperature_pres_du_feu])

	# L'objet s'eloigne hors de portee de toute source : doit refroidir vers l'ambiante reelle.
	objet.position = feu.position + Vector3(feu.rayon * 10.0, 0.0, 0.0)
	for i in 30:
		Temperature.avancer(monde, [feu], 0.05, catalogue)
	var temperature_eloignee: float = objet.proprietes.temperature
	verif.v(temperature_eloignee < temperature_pres_du_feu, "chemin reel : une fois hors de portee de toute source, la temperature doit redescendre (etait %f, devenue %f)" % [temperature_pres_du_feu, temperature_eloignee])
	verif.v(temperature_eloignee >= ambiante, "chemin reel : le refroidissement ne doit jamais franchir l'ambiante reelle (%f) par le bas, recu %f" % [ambiante, temperature_eloignee])
