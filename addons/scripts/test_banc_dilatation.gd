extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_dilatation.gd
#
# Verrouille le cablage de banc_dilatation.gd, PREMIERE DEMONSTRATION REELLE
# de la dilatation thermique (chantier "colonne thermique", case 5,
# DERNIERE case du tableau Thermique -- scripts/temperature.gd:avancer) :
# fabriquer_objet/taille_pour_volume/couleur_pour_temperature/texte_objet/
# doit_imprimer/ligne_log (fonctions statiques, pures) plus un CHEMIN REEL
# combinant Temperature.avancer avec data/banc_dilatation.json/
# data/temperature.json lus sur disque -- l'objet "chauffe" doit reellement
# grossir en se rechauffant, l'objet "refroidi" doit reellement retrecir en
# refroidissant, la masse des deux ne doit jamais bouger.

const BancDilatation = preload("res://scripts/banc_dilatation.gd")
const Temperature = preload("res://scripts/temperature.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_fabriquer_objet_porte_toutes_les_cles_et_deduit_la_densite()
	_fabriquer_objet_volume_initial_non_positif_replie_densite_a_zero()

	_taille_pour_volume_egale_taille_base_au_volume_de_reference()
	_taille_pour_volume_suit_la_racine_carree_jamais_lineaire()
	_taille_pour_volume_repli_neutre_si_reference_ou_volume_non_positif()

	_couleur_pour_temperature_bornes_exactes()
	_couleur_pour_temperature_repli_neutre_si_maxi_sous_mini()

	_texte_objet_porte_id_et_les_trois_nombres()
	_ligne_log_porte_le_temps_lid_et_les_trois_nombres()

	_doit_imprimer_sous_le_seuil_faux_au_seuil_ou_au_dela_vrai()
	_doit_imprimer_seuil_non_positif_imprime_toujours()

	_chemin_reel_chauffe_grossit_en_se_rechauffant()
	_chemin_reel_refroidi_retrecit_en_refroidissant()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: fabrication de l'objet (densite deduite masse/volume), " +
		"taille du carre en racine carree du volume, couleur froid->chaud " +
		"bornee, textes HUD/console, seuil de changement significatif, " +
		"chemin reel (data/banc_dilatation.json/data/temperature.json) ou " +
		"'chauffe' grossit en chauffant et 'refroidi' retrecit en " +
		"refroidissant, masse inchangee dans les deux cas")
	quit(0)

# ---- fabriquer_objet ----

func _fabriquer_objet_porte_toutes_les_cles_et_deduit_la_densite() -> void:
	var objet := BancDilatation.fabriquer_objet("x", Vector3(1.0, 2.0, 3.0), 25.0, 0.3, 0.04, 5.0, 20.0)
	verif.v(objet.id == "x", "l'id doit etre celui recu")
	verif.v(objet.position == Vector3(1.0, 2.0, 3.0), "la position doit etre celle recue")
	verif.v(is_equal_approx(objet.proprietes.temperature, 25.0), "la temperature initiale doit etre celle recue")
	verif.v(is_equal_approx(objet.proprietes.conductivite_thermique, 0.3), "la conductivite doit etre celle recue")
	verif.v(is_equal_approx(objet.proprietes.dilatation_thermique, 0.04), "la dilatation thermique doit etre celle recue")
	verif.v(is_equal_approx(objet.proprietes.volume, 5.0), "le volume initial doit etre celui recu")
	verif.v(is_equal_approx(objet.proprietes.masse, 20.0), "la masse doit etre celle recue")
	verif.v(is_equal_approx(objet.proprietes.densite, 4.0), "la densite initiale doit etre EXACTEMENT masse/volume = 20/5 = 4.0, recu %f" % objet.proprietes.densite)

func _fabriquer_objet_volume_initial_non_positif_replie_densite_a_zero() -> void:
	var objet_zero := BancDilatation.fabriquer_objet("zero", Vector3.ZERO, 20.0, 0.1, 0.0, 0.0, 10.0)
	verif.v(is_equal_approx(objet_zero.proprietes.densite, 0.0), "volume initial nul : densite repliee sur 0.0, jamais une division par zero")
	var objet_negatif := BancDilatation.fabriquer_objet("negatif", Vector3.ZERO, 20.0, 0.1, 0.0, -3.0, 10.0)
	verif.v(is_equal_approx(objet_negatif.proprietes.densite, 0.0), "volume initial negatif (donnee incoherente) : densite repliee sur 0.0")

# ---- taille_pour_volume ----

func _taille_pour_volume_egale_taille_base_au_volume_de_reference() -> void:
	var taille := BancDilatation.taille_pour_volume(6.0, 6.0, 50.0)
	verif.v(is_equal_approx(taille, 50.0), "au volume de reference, la taille doit etre EXACTEMENT taille_base, recu %f" % taille)

func _taille_pour_volume_suit_la_racine_carree_jamais_lineaire() -> void:
	var taille_double := BancDilatation.taille_pour_volume(12.0, 6.0, 50.0)
	verif.v(is_equal_approx(taille_double, 50.0 * sqrt(2.0)), "un volume DOUBLE doit donner une taille en sqrt(2), jamais un doublement lineaire de la taille, recu %f" % taille_double)
	verif.v(taille_double < 100.0, "verrou direct contre une echelle lineaire : sqrt(2)*50 doit rester strictement sous 100.0, recu %f" % taille_double)

func _taille_pour_volume_repli_neutre_si_reference_ou_volume_non_positif() -> void:
	verif.v(is_equal_approx(BancDilatation.taille_pour_volume(6.0, 0.0, 50.0), 0.0), "volume_reference a 0.0 : repli sur 0.0, jamais une division par zero")
	verif.v(is_equal_approx(BancDilatation.taille_pour_volume(0.0, 6.0, 50.0), 0.0), "volume a 0.0 : repli sur 0.0 (carre invisible plutot qu'une racine de zero surprenante)")
	verif.v(is_equal_approx(BancDilatation.taille_pour_volume(-2.0, 6.0, 50.0), 0.0), "volume negatif (donnee extreme) : repli sur 0.0, jamais une racine d'un nombre negatif")

# ---- couleur_pour_temperature ----

func _couleur_pour_temperature_bornes_exactes() -> void:
	var froid := Color(0.0, 0.0, 1.0)
	var chaud := Color(1.0, 0.0, 0.0)
	verif.v(BancDilatation.couleur_pour_temperature(20.0, 20.0, 90.0, froid, chaud) == froid, "a la borne minimale, couleur attendue exactement froid")
	verif.v(BancDilatation.couleur_pour_temperature(90.0, 20.0, 90.0, froid, chaud) == chaud, "a la borne maximale, couleur attendue exactement chaud")
	verif.v(BancDilatation.couleur_pour_temperature(9999.0, 20.0, 90.0, froid, chaud) == chaud, "tres au dessus du maximum : borne a chaud, jamais une extrapolation")

func _couleur_pour_temperature_repli_neutre_si_maxi_sous_mini() -> void:
	var froid := Color(0.0, 0.0, 1.0)
	var chaud := Color(1.0, 0.0, 0.0)
	verif.v(BancDilatation.couleur_pour_temperature(50.0, 80.0, 80.0, froid, chaud) == froid, "maxi <= mini : repli neutre sur froid, jamais une division par zero")

# ---- textes ----

func _texte_objet_porte_id_et_les_trois_nombres() -> void:
	var texte := BancDilatation.texte_objet("chauffe", 55.5, 8.25, 1.333)
	verif.v(texte.find("chauffe") != -1, "le texte doit porter l'id de l'objet")
	verif.v(texte.find("55.5") != -1, "le texte doit porter la temperature")
	verif.v(texte.find("8.25") != -1, "le texte doit porter le volume")
	verif.v(texte.find("1.333") != -1, "le texte doit porter la densite")

func _ligne_log_porte_le_temps_lid_et_les_trois_nombres() -> void:
	var ligne := BancDilatation.ligne_log(12.5, "refroidi", 33.0, 4.5, 2.667)
	verif.v(ligne.find("t=12.5") != -1, "la ligne doit porter le temps")
	verif.v(ligne.find("refroidi") != -1, "la ligne doit porter l'id de l'objet")
	verif.v(ligne.find("33.0") != -1, "la ligne doit porter la temperature")
	verif.v(ligne.find("4.50") != -1, "la ligne doit porter le volume")
	verif.v(ligne.find("2.667") != -1, "la ligne doit porter la densite")

# ---- doit_imprimer ----

func _doit_imprimer_sous_le_seuil_faux_au_seuil_ou_au_dela_vrai() -> void:
	verif.v(not BancDilatation.doit_imprimer(6.1, 6.0, 0.25), "variation de 0.1, sous le seuil de 0.25 : ne doit PAS imprimer")
	verif.v(BancDilatation.doit_imprimer(6.25, 6.0, 0.25), "variation EXACTEMENT au seuil (0.25, exact en binaire) : doit imprimer")
	verif.v(BancDilatation.doit_imprimer(5.5, 6.0, 0.25), "variation negative au dela du seuil (baisse de 0.5) : doit imprimer, le sens ne compte pas")

func _doit_imprimer_seuil_non_positif_imprime_toujours() -> void:
	verif.v(BancDilatation.doit_imprimer(6.0, 6.0, 0.0), "seuil a 0.0 (garde degeneree) : doit toujours imprimer, meme a variation nulle")

# ---- Chemin reel ----

func _catalogue_temperature_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/temperature.json"))

func _donnees_banc_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_dilatation.json"))

func _objet_reel(donnees: Dictionary, cle: String) -> Dictionary:
	var decl: Dictionary = donnees.get(cle, {})
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	return BancDilatation.fabriquer_objet(
		cle,
		Vector3(pos[0], pos[1], pos[2]),
		decl.get("temperature_initiale", 20.0),
		decl.get("conductivite_thermique", 0.25),
		decl.get("dilatation_thermique", 0.0),
		decl.get("volume_initial", 6.0),
		decl.get("masse", 12.0),
	)

func _source_reelle(donnees: Dictionary) -> Dictionary:
	var decl: Dictionary = donnees.get("source_chaude", {})
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	return {
		"position": Vector3(pos[0], pos[1], pos[2]),
		"rayon": decl.get("rayon", 400.0),
		"temperature": decl.get("temperature", 90.0),
		"force": decl.get("force", 1.0),
	}

func _chemin_reel_chauffe_grossit_en_se_rechauffant() -> void:
	var catalogue := _catalogue_temperature_reel()
	var donnees := _donnees_banc_reelles()
	var chauffe := _objet_reel(donnees, "chauffe")
	var source := _source_reelle(donnees)
	var monde := [chauffe]

	var temperature_initiale: float = chauffe.proprietes.temperature
	var volume_initial: float = chauffe.proprietes.volume
	var masse_initiale: float = chauffe.proprietes.masse

	for i in 60:
		Temperature.avancer(monde, [source], 0.2, catalogue)

	verif.v(chauffe.proprietes.temperature > temperature_initiale, "chemin reel : 'chauffe' pres de la source reelle doit reellement se rechauffer (parti de %f, arrive a %f)" % [temperature_initiale, chauffe.proprietes.temperature])
	verif.v(chauffe.proprietes.volume > volume_initial, "chemin reel : en se rechauffant, 'chauffe' doit voir son volume AUGMENTER (parti de %f, arrive a %f)" % [volume_initial, chauffe.proprietes.volume])
	verif.v(is_equal_approx(chauffe.proprietes.masse, masse_initiale), "chemin reel : la masse de 'chauffe' ne doit jamais changer sous l'effet de la dilatation")
	verif.v(is_equal_approx(chauffe.proprietes.densite, chauffe.proprietes.masse / chauffe.proprietes.volume), "chemin reel : la densite de 'chauffe' doit rester EXACTEMENT masse/volume")

func _chemin_reel_refroidi_retrecit_en_refroidissant() -> void:
	var catalogue := _catalogue_temperature_reel()
	var donnees := _donnees_banc_reelles()
	var refroidi := _objet_reel(donnees, "refroidi")
	var monde := [refroidi]

	var temperature_initiale: float = refroidi.proprietes.temperature
	var volume_initial: float = refroidi.proprietes.volume
	var masse_initiale: float = refroidi.proprietes.masse

	# Meme geometrie que le banc reel : 'refroidi' est hors de portee de
	# l'unique source (distance 800 > rayon 400) -- simuler cette absence de
	# source directement, comme test_banc_temperature.gd le fait pour son
	# objet eloigne.
	for i in 60:
		Temperature.avancer(monde, [], 0.2, catalogue)

	verif.v(refroidi.proprietes.temperature < temperature_initiale, "chemin reel : 'refroidi', hors de portee de toute source, doit reellement refroidir vers l'ambiante (parti de %f, arrive a %f)" % [temperature_initiale, refroidi.proprietes.temperature])
	verif.v(refroidi.proprietes.volume < volume_initial, "chemin reel : en refroidissant, 'refroidi' doit voir son volume DIMINUER (parti de %f, arrive a %f)" % [volume_initial, refroidi.proprietes.volume])
	verif.v(refroidi.proprietes.volume > 0.0, "chemin reel : le volume de 'refroidi' doit rester STRICTEMENT positif sur la plage modeste de ce banc, jamais s'effondrer a zero ou en dessous")
	verif.v(is_equal_approx(refroidi.proprietes.masse, masse_initiale), "chemin reel : la masse de 'refroidi' ne doit jamais changer sous l'effet de la dilatation")
	verif.v(is_equal_approx(refroidi.proprietes.densite, refroidi.proprietes.masse / refroidi.proprietes.volume), "chemin reel : la densite de 'refroidi' doit rester EXACTEMENT masse/volume")
