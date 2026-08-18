extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_horloge.gd
#
# Verrouille scripts/horloge.gd comme mecanisme GENERIQUE de temps du monde.
# HORS DOMAINE PAR CONSTRUCTION, sur les DEUX axes que ce fichier expose :
# - aucune saison d'Orion (ni printemps, ni hiver) : le cycle teste est la
#   MUE D'UN CRISTAL GRAVITIQUE, phases inventees "mue_prax"/"mue_velm"/
#   "mue_tuor"/"mue_mibb" (famille de vocabulaire de test_bifurcation.gd,
#   jamais vue ailleurs dans le depot) ;
# - aucune longueur de jour terrestre : les cas nominaux tournent sur des
#   journees de 10 h et de 7 h autant que sur 24 h -- si un "24.0" se
#   glissait dans le mecanisme, ces cas rougiraient.
#
# Fonctions pures : aucune couche, aucun noeud, aucun rendu, aucun disque
# (ce mecanisme ne recoit aucun catalogue, comme senescence.gd/stade.gd).
#
# NON-REGRESSION VOULUE, verrouillee ici : sur toute entree positive, la
# formule doit rendre EXACTEMENT ce que rendent les deux copies locales de
# banc_lumiere.gd:heure_courante et banc_fatigue_circadien.gd:heure_courante
# (recalculee a la main dans _formule_des_bancs, jamais appelee sur eux --
# c'est une contre-epreuve, pas une delegation).

const Horloge = preload("res://scripts/horloge.gd")
const Verif = preload("res://scripts/verif.gd")

const MUES := ["mue_prax", "mue_velm", "mue_tuor", "mue_mibb"]

func _init() -> void:
	var v := Verif.new()

	_heure_reproduit_exactement_la_formule_des_deux_bancs(v)
	_heure_reste_dans_l_intervalle_du_jour(v)
	_heure_cycle_au_dela_d_un_jour(v)
	_heure_respecte_l_heure_de_depart(v)
	_heure_ignore_la_longueur_de_jour_terrestre(v)
	_heure_duree_jour_non_positive_reste_bloquee_sur_le_depart(v)
	_heure_par_jour_non_positif_alarme_et_ne_rend_jamais_nan(v)
	_heure_negative_est_ramenee_dans_l_intervalle(v)

	_saison_rend_le_bon_nom_pour_chaque_index(v)
	_saison_cycle_apres_le_tour_complet(v)
	_saison_a_deux_elements_fonctionne(v)
	_saison_a_un_seul_element_ne_change_jamais(v)
	_saison_vide_est_un_chemin_mort_silencieux(v)
	_saison_jours_par_saison_non_positif_alarme(v)
	_saison_duree_jour_non_positive_rend_la_premiere(v)
	_saison_negative_est_ramenee_dans_la_liste(v)
	_saison_suit_l_ordre_declare_jamais_l_alphabet(v)

	_les_deux_fonctions_sont_pures_et_ne_mutent_rien(v)

	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: horloge.gd rend l'heure du jour et le nom de la saison courante, " +
			"generique a toute longueur de jour et a tout cycle invente")
		quit(0)

# ---------------------------------------------------------------------------
# La formule des deux bancs, RECOPIEE ICI a la main (contre-epreuve) --
# jamais un appel a banc_lumiere.gd ni a banc_fatigue_circadien.gd : un test
# du coeur ne depend jamais d'un banc jetable.
# ---------------------------------------------------------------------------
func _formule_des_bancs(temps_ecoule: float, duree_jour_secondes: float, heures_par_jour: float, heure_depart: float) -> float:
	if duree_jour_secondes <= 0.0:
		return heure_depart
	var heures_ecoulees: float = (temps_ecoule / duree_jour_secondes) * heures_par_jour
	return fmod(heure_depart + heures_ecoulees, heures_par_jour)

# ---------------------------------------------------------------------------
# heure()
# ---------------------------------------------------------------------------

func _heure_reproduit_exactement_la_formule_des_deux_bancs(v) -> void:
	var cas := [
		[0.0, 20.0, 10.0, 5.0],
		[4.0, 20.0, 10.0, 5.0],
		[12.0, 20.0, 10.0, 5.0],
		[0.0, 24.0, 24.0, 0.0],
		[12.0, 24.0, 24.0, 0.0],
		[24.0, 24.0, 24.0, 0.0],
		[0.0, 24.0, 24.0, 4.0],
		[37.5, 40.0, 24.0, 6.25],
	]
	for c in cas:
		var attendu: float = _formule_des_bancs(c[0], c[1], c[2], c[3])
		var obtenu: float = Horloge.heure(c[0], c[1], c[2], c[3])
		v.v(is_equal_approx(obtenu, attendu),
			"heure(%f, %f, %f, %f) doit valoir exactement ce que rendent les deux bancs (%f), obtenu %f"
				% [c[0], c[1], c[2], c[3], attendu, obtenu])

func _heure_reste_dans_l_intervalle_du_jour(v) -> void:
	var heures_par_jour := 24.0
	for i in range(200):
		var t: float = float(i) * 0.37
		var h: float = Horloge.heure(t, 3.0, heures_par_jour, 0.0)
		v.v(h >= 0.0 and h < heures_par_jour,
			"heure doit toujours rester dans [0, heures_par_jour) -- t=%f a rendu %f" % [t, h])

func _heure_cycle_au_dela_d_un_jour(v) -> void:
	# 25 heures simulees sur un jour de 24 h -> 1 h. `duree_jour_secondes`
	# est pose EGAL a `heures_par_jour` : une heure du monde dure alors une
	# seconde reelle, et temps_ecoule se lit directement en heures.
	v.v(is_equal_approx(Horloge.heure(25.0, 24.0, 24.0, 0.0), 1.0),
		"25 h ecoulees sur une journee de 24 h doivent rendre 1 h")
	v.v(is_equal_approx(Horloge.heure(49.0, 24.0, 24.0, 0.0), 1.0),
		"deux jours plus tard, la meme heure du jour doit revenir a l'identique")
	v.v(is_equal_approx(Horloge.heure(24.0, 24.0, 24.0, 0.0), 0.0),
		"un jour complet exactement doit reboucler sur 0.0, jamais sur 24.0")

func _heure_respecte_l_heure_de_depart(v) -> void:
	v.v(is_equal_approx(Horloge.heure(0.0, 24.0, 24.0, 4.0), 4.0),
		"a t=0 l'heure doit valoir exactement heure_depart")
	v.v(is_equal_approx(Horloge.heure(0.0, 20.0, 10.0, 9.5), 9.5),
		"heure_depart doit etre rendue telle quelle meme sur un jour de 10 h")

func _heure_ignore_la_longueur_de_jour_terrestre(v) -> void:
	# Si 24.0 etait ecrit en dur dans le mecanisme, ces deux cas rougiraient.
	v.v(is_equal_approx(Horloge.heure(11.0, 10.0, 10.0, 0.0), 1.0),
		"sur un monde a 10 h par jour, 11 h ecoulees doivent rendre 1 h")
	v.v(is_equal_approx(Horloge.heure(9.0, 7.0, 7.0, 0.0), 2.0),
		"sur un monde a 7 h par jour, 9 h ecoulees doivent rendre 2 h")
	for hpj in [3.0, 7.0, 10.0, 24.0, 100.0]:
		var h: float = Horloge.heure(1234.5, 2.0, hpj, 0.0)
		v.v(h >= 0.0 and h < hpj,
			"l'heure doit rester sous heures_par_jour=%f, obtenu %f" % [hpj, h])

func _heure_duree_jour_non_positive_reste_bloquee_sur_le_depart(v) -> void:
	v.v(is_equal_approx(Horloge.heure(100.0, 0.0, 24.0, 6.0), 6.0),
		"duree_jour_secondes nulle doit bloquer l'heure sur heure_depart, jamais diviser par zero")
	v.v(is_equal_approx(Horloge.heure(1e9, -5.0, 10.0, 3.0), 3.0),
		"duree_jour_secondes negative doit se comporter comme nulle, sans alarme")

func _heure_par_jour_non_positif_alarme_et_ne_rend_jamais_nan(v) -> void:
	var h_nul: float = Horloge.heure(10.0, 1.0, 0.0, 0.0)
	v.v(h_nul == 0.0 and not is_nan(h_nul),
		"heures_par_jour nul doit alarmer et rendre 0.0, jamais NaN (fmod par zero)")
	var h_negatif: float = Horloge.heure(10.0, 1.0, -4.0, 2.0)
	v.v(h_negatif == 0.0 and not is_nan(h_negatif),
		"heures_par_jour negatif doit alarmer et rendre 0.0")

func _heure_negative_est_ramenee_dans_l_intervalle(v) -> void:
	# Seule difference assumee avec la copie des deux bancs : un temps ou une
	# heure de depart negatifs y rendaient une heure negative.
	v.v(is_equal_approx(Horloge.heure(-1.0, 24.0, 24.0, 0.0), 23.0),
		"une heure avant l'origine du monde doit rendre 23 h, jamais -1 h")
	v.v(is_equal_approx(Horloge.heure(0.0, 24.0, 24.0, -2.0), 22.0),
		"un heure_depart negatif doit etre ramene dans [0, heures_par_jour)")
	for i in range(50):
		var t: float = -float(i) * 1.7
		var h: float = Horloge.heure(t, 2.0, 10.0, -3.0)
		v.v(h >= 0.0 and h < 10.0,
			"meme sur un temps negatif, l'heure doit rester dans [0, 10) -- t=%f a rendu %f" % [t, h])

# ---------------------------------------------------------------------------
# saison()
# ---------------------------------------------------------------------------

func _saison_rend_le_bon_nom_pour_chaque_index(v) -> void:
	# Journee d'une seconde reelle, 5 jours par saison : temps_ecoule se lit
	# directement en jours.
	for index in range(MUES.size()):
		var t: float = float(index) * 5.0 + 2.0  # au milieu de la saison
		var obtenu: String = Horloge.saison(t, 1.0, 5.0, MUES)
		v.v(obtenu == MUES[index],
			"a t=%f jours, la saison doit etre '%s', obtenu '%s'" % [t, MUES[index], obtenu])

func _saison_cycle_apres_le_tour_complet(v) -> void:
	var tour: float = 5.0 * float(MUES.size())
	v.v(Horloge.saison(tour, 1.0, 5.0, MUES) == MUES[0],
		"apres un tour complet du cycle, la premiere saison doit revenir")
	v.v(Horloge.saison(tour + 2.0, 1.0, 5.0, MUES) == MUES[0],
		"le deuxieme tour doit se derouler exactement comme le premier")
	v.v(Horloge.saison(tour * 3.0 + 12.0, 1.0, 5.0, MUES) == MUES[2],
		"au quatrieme tour, le cycle doit toujours tomber sur la meme saison qu'au premier")
	v.v(Horloge.saison(4.99, 1.0, 5.0, MUES) == MUES[0]
			and Horloge.saison(5.01, 1.0, 5.0, MUES) == MUES[1],
		"la bascule doit se faire exactement au jour jours_par_saison, jamais avant ni apres")

func _saison_a_deux_elements_fonctionne(v) -> void:
	var deux := ["mue_prax", "mue_velm"]
	v.v(Horloge.saison(0.0, 1.0, 3.0, deux) == "mue_prax",
		"un cycle a deux elements doit commencer par le premier")
	v.v(Horloge.saison(3.0, 1.0, 3.0, deux) == "mue_velm",
		"un cycle a deux elements doit basculer sur le second")
	v.v(Horloge.saison(6.0, 1.0, 3.0, deux) == "mue_prax",
		"un cycle a deux elements doit reboucler sur le premier")
	v.v(Horloge.saison(9.0, 1.0, 3.0, deux) == "mue_velm",
		"le rebouclage d'un cycle a deux elements doit se repeter sans derive")

func _saison_a_un_seul_element_ne_change_jamais(v) -> void:
	var un := ["mue_tuor"]
	for i in range(20):
		v.v(Horloge.saison(float(i) * 3.3, 1.0, 2.0, un) == "mue_tuor",
			"un cycle a un seul element doit toujours rendre ce seul element")

func _saison_vide_est_un_chemin_mort_silencieux(v) -> void:
	v.v(Horloge.saison(100.0, 1.0, 5.0, []) == "",
		"un monde sans saison declaree doit rendre '' sans alarme, jamais un nom invente")

func _saison_jours_par_saison_non_positif_alarme(v) -> void:
	v.v(Horloge.saison(10.0, 1.0, 0.0, MUES) == "",
		"jours_par_saison nul doit alarmer et rendre '', jamais diviser par zero")
	v.v(Horloge.saison(10.0, 1.0, -2.0, MUES) == "",
		"jours_par_saison negatif doit alarmer et rendre ''")

func _saison_duree_jour_non_positive_rend_la_premiere(v) -> void:
	v.v(Horloge.saison(1e9, 0.0, 5.0, MUES) == MUES[0],
		"duree_jour_secondes nulle arrete le temps : la premiere saison declaree, jamais une alarme")

func _saison_negative_est_ramenee_dans_la_liste(v) -> void:
	v.v(Horloge.saison(-1.0, 1.0, 5.0, MUES) == MUES[MUES.size() - 1],
		"un jour avant l'origine du monde doit rendre la DERNIERE saison, jamais un index negatif")
	for i in range(40):
		var t: float = -float(i) * 2.3
		var s: String = Horloge.saison(t, 1.0, 5.0, MUES)
		v.v(MUES.has(s),
			"meme sur un temps negatif, la saison rendue doit appartenir a la liste -- t=%f a rendu '%s'" % [t, s])

func _saison_suit_l_ordre_declare_jamais_l_alphabet(v) -> void:
	# Meme ensemble de noms, ordre inverse : la sequence doit s'inverser.
	var inverse := [MUES[3], MUES[2], MUES[1], MUES[0]]
	for index in range(inverse.size()):
		var t: float = float(index) * 5.0 + 2.0
		v.v(Horloge.saison(t, 1.0, 5.0, inverse) == inverse[index],
			"c'est l'ORDRE de l'Array qui dit quelle saison suit laquelle, jamais un tri interne")
	v.v(Horloge.saison(2.0, 1.0, 5.0, MUES) != Horloge.saison(2.0, 1.0, 5.0, inverse),
		"inverser l'ordre declare doit changer la saison rendue au meme instant")

# ---------------------------------------------------------------------------
# Puretes
# ---------------------------------------------------------------------------

func _les_deux_fonctions_sont_pures_et_ne_mutent_rien(v) -> void:
	var saisons := MUES.duplicate()
	var avant := saisons.duplicate()
	var h1: float = Horloge.heure(123.4, 7.0, 10.0, 2.0)
	var h2: float = Horloge.heure(123.4, 7.0, 10.0, 2.0)
	var s1: String = Horloge.saison(123.4, 7.0, 5.0, saisons)
	var s2: String = Horloge.saison(123.4, 7.0, 5.0, saisons)
	v.v(h1 == h2, "heure doit rendre exactement la meme valeur sur deux appels identiques (fonction pure)")
	v.v(s1 == s2, "saison doit rendre exactement le meme nom sur deux appels identiques (fonction pure)")
	v.v(saisons == avant, "saison ne doit JAMAIS muter l'Array de saisons qu'elle recoit")
