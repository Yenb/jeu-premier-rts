extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_lumiere.gd
#
# Verrouille scripts/banc_lumiere.gd : ses fonctions statiques propres
# (heure simulee, position de la lanterne, interpolation d'affichage en
# deux morceaux, zone discrete pour le log) PLUS un chemin reel complet --
# data/lumiere.json et data/banc_lumiere.json lus sur disque, torche/
# cristal/lanterne REELS -- qui rejoue chacun des points demandes par le
# chantier "lumiere ambiante -- scalaire ambiant avec temperature de
# couleur" : intensite/couleur ambiantes qui suivent l'heure, une source
# qui augmente l'intensite et tire la couleur dans son rayon, l'absence de
# contribution hors rayon, deux sources qui se superposent en intensite ET
# en couleur, une source deplacee qui change ce que lit un objet fixe,
# l'obscurite nocturne sans source (intensite 0.0, couleur bleue), la
# latitude qui change la courbe jour/nuit, et le bornage strict de
# l'intensite a [0.0, 1.0].

const Lumiere = preload("res://scripts/lumiere.gd")
const BancLumiere = preload("res://scripts/banc_lumiere.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_heure_courante_avance_lineairement_et_boucle()
	_heure_courante_respecte_lheure_de_depart()
	_heure_courante_duree_non_positive_reste_bloquee_sur_le_depart()

	_position_lanterne_immobile_sans_periode()
	_position_lanterne_fait_un_aller_retour_sinusoidal()

	_couleur_affichage_points_nommes_exacts()
	_couleur_affichage_interpolation_en_deux_morceaux_jamais_une_seule_droite()
	_couleur_lecteur_noir_a_intensite_nulle_teinte_pleine_a_intensite_maximale()
	_zone_pour_intensite_trois_paliers()

	_chemin_reel_intensite_ambiante_suit_lheure()
	_chemin_reel_couleur_ambiante_suit_lheure()
	_chemin_reel_source_locale_augmente_lintensite_dans_son_rayon()
	_chemin_reel_couleur_locale_tiree_vers_la_couleur_de_la_source()
	_chemin_reel_hors_rayon_contribution_nulle()
	_chemin_reel_deux_sources_se_superposent_intensite_et_couleur()
	_chemin_reel_source_deplacee_change_ce_que_lit_un_objet_fixe()
	_chemin_reel_sans_source_et_la_nuit_intensite_zero_couleur_bleue()
	_chemin_reel_latitude_change_la_courbe_jour_nuit()
	_chemin_reel_bornage_intensite_jamais_hors_zero_un()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: fonctions propres a banc_lumiere.gd (heure simulee, " +
		"position de la lanterne, interpolation d'affichage en deux " +
		"morceaux, zones discretes) et chemin reel complet sur " +
		"data/lumiere.json + data/banc_lumiere.json -- cycle jour/nuit " +
		"(intensite et couleur), source locale, superposition, source " +
		"deplacee, obscurite nocturne, latitude, bornage")
	quit(0)

# ---- Fonctions propres au banc ----

func _heure_courante_avance_lineairement_et_boucle() -> void:
	var h0 := BancLumiere.heure_courante(0.0, 24.0, 24.0, 0.0)
	var h_mi_cycle := BancLumiere.heure_courante(12.0, 24.0, 24.0, 0.0)
	var h_cycle_complet := BancLumiere.heure_courante(24.0, 24.0, 24.0, 0.0)
	verif.v(is_equal_approx(h0, 0.0), "au depart, heure attendue 0.0, recu %f" % h0)
	verif.v(is_equal_approx(h_mi_cycle, 12.0), "a mi-cycle (12s sur 24s pour 24h), heure attendue 12.0, recu %f" % h_mi_cycle)
	verif.v(is_equal_approx(h_cycle_complet, 0.0), "un cycle complet doit boucler exactement a 0.0 (fmod), recu %f" % h_cycle_complet)

func _heure_courante_respecte_lheure_de_depart() -> void:
	var h := BancLumiere.heure_courante(0.0, 24.0, 24.0, 4.0)
	verif.v(is_equal_approx(h, 4.0), "avec heure_depart=4.0 et aucun temps ecoule, heure attendue 4.0, recu %f" % h)

func _heure_courante_duree_non_positive_reste_bloquee_sur_le_depart() -> void:
	var h := BancLumiere.heure_courante(100.0, 0.0, 24.0, 6.0)
	verif.v(is_equal_approx(h, 6.0), "duree_jour_secondes a 0.0 doit rester bloque sur heure_depart, jamais une division par zero, recu %f" % h)

func _position_lanterne_immobile_sans_periode() -> void:
	var centre := Vector3(100.0, 0.0, 0.0)
	var p := BancLumiere.position_lanterne(centre, 250.0, 0.0, 5.0)
	verif.v(p.is_equal_approx(centre), "periode a 0.0 doit laisser la lanterne immobile au centre, recu %s" % p)

func _position_lanterne_fait_un_aller_retour_sinusoidal() -> void:
	var centre := Vector3(0.0, 0.0, 0.0)
	var p_quart := BancLumiere.position_lanterne(centre, 250.0, 20.0, 5.0)
	verif.v(is_equal_approx(p_quart.x, 250.0), "a un quart de periode, la lanterne doit etre a l'amplitude maximale, recu %f" % p_quart.x)
	var p_moitie := BancLumiere.position_lanterne(centre, 250.0, 20.0, 10.0)
	verif.v(is_equal_approx(p_moitie.x, 0.0), "a une demi-periode, la lanterne doit etre revenue au centre, recu %f" % p_moitie.x)

func _couleur_affichage_points_nommes_exacts() -> void:
	var orange := Color(1.0, 0.5, 0.0)
	var blanc := Color(1.0, 1.0, 1.0)
	var bleu := Color(0.0, 0.0, 1.0)
	verif.v(BancLumiere.couleur_affichage(0.0, orange, blanc, bleu).is_equal_approx(orange), "couleur 0.0 doit rendre exactement 'orange'")
	verif.v(BancLumiere.couleur_affichage(0.5, orange, blanc, bleu).is_equal_approx(blanc), "couleur 0.5 doit rendre exactement le point milieu nomme 'blanc-jaune', jamais un gris-mauve terne")
	verif.v(BancLumiere.couleur_affichage(1.0, orange, blanc, bleu).is_equal_approx(bleu), "couleur 1.0 doit rendre exactement 'bleu'")

func _couleur_affichage_interpolation_en_deux_morceaux_jamais_une_seule_droite() -> void:
	var orange := Color(1.0, 0.0, 0.0)
	var blanc := Color(0.0, 1.0, 0.0)
	var bleu := Color(0.0, 0.0, 1.0)
	var a_un_quart := BancLumiere.couleur_affichage(0.25, orange, blanc, bleu)
	# sur une seule droite orange->bleu, 0.25 rendrait (0.75, 0.0, 0.25) -- jamais ce resultat ici.
	verif.v(not a_un_quart.is_equal_approx(Color(0.75, 0.0, 0.25)), "a 0.25, le resultat NE DOIT PAS correspondre a une seule droite orange->bleu -- l'interpolation doit passer par le point milieu nomme")
	verif.v(is_equal_approx(a_un_quart.g, 0.5), "a 0.25 (mi-chemin du premier morceau), la composante verte doit etre a mi-chemin entre 0.0 (orange) et 1.0 (blanc), recu %f" % a_un_quart.g)

func _couleur_lecteur_noir_a_intensite_nulle_teinte_pleine_a_intensite_maximale() -> void:
	var orange := Color(1.0, 0.5, 0.0)
	var blanc := Color(1.0, 1.0, 1.0)
	var bleu := Color(0.0, 0.0, 1.0)
	var noir := BancLumiere.couleur_lecteur(0.0, 0.0, orange, blanc, bleu)
	verif.v(noir.is_equal_approx(Color.BLACK), "intensite 0.0 doit rendre du noir total quelle que soit la couleur, recu %s" % noir)
	var plein := BancLumiere.couleur_lecteur(1.0, 0.0, orange, blanc, bleu)
	verif.v(plein.is_equal_approx(orange), "intensite 1.0 doit rendre la teinte pleine sans assombrissement, recu %s" % plein)

func _zone_pour_intensite_trois_paliers() -> void:
	verif.v(BancLumiere.zone_pour_intensite(0.9, 0.5, 0.1) == "jour", "intensite 0.9 au-dessus du seuil jour doit rendre 'jour'")
	verif.v(BancLumiere.zone_pour_intensite(0.3, 0.5, 0.1) == "penombre", "intensite 0.3 entre les deux seuils doit rendre 'penombre'")
	verif.v(BancLumiere.zone_pour_intensite(0.05, 0.5, 0.1) == "nuit", "intensite 0.05 sous le seuil penombre doit rendre 'nuit'")

# ---- Chemin reel : data/lumiere.json + data/banc_lumiere.json ----

func _catalogue_lumiere_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/lumiere.json"))

func _donnees_banc_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_lumiere.json"))

func _torche_reelle(donnees: Dictionary) -> Dictionary:
	var decl: Dictionary = donnees.torche
	var pos: Array = decl.position
	return {"position": Vector3(pos[0], pos[1], pos[2]), "rayon": decl.rayon, "intensite": decl.intensite, "temperature_couleur": decl.temperature_couleur, "force": decl.force}

func _cristal_reel(donnees: Dictionary) -> Dictionary:
	var decl: Dictionary = donnees.cristal
	var pos: Array = decl.position
	return {"position": Vector3(pos[0], pos[1], pos[2]), "rayon": decl.rayon, "intensite": decl.intensite, "temperature_couleur": decl.temperature_couleur, "force": decl.force}

func _chemin_reel_intensite_ambiante_suit_lheure() -> void:
	var catalogue := _catalogue_lumiere_reel()
	var heure_midi: float = catalogue.defaut.cycle.get("heure_midi", 12.0)
	var a_midi := Lumiere.soleil(heure_midi, 0.0, catalogue)
	var a_minuit := Lumiere.soleil(0.0, 0.0, catalogue)
	verif.v(is_equal_approx(a_midi.intensite, 1.0), "chemin reel : intensite ambiante a midi (equateur) attendue 1.0, recu %f" % a_midi.intensite)
	verif.v(is_equal_approx(a_minuit.intensite, 0.0), "chemin reel : intensite ambiante a minuit attendue 0.0, recu %f" % a_minuit.intensite)

func _chemin_reel_couleur_ambiante_suit_lheure() -> void:
	var catalogue := _catalogue_lumiere_reel()
	var aube: float = Lumiere.soleil(6.0, 0.0, catalogue).couleur
	var midi: float = Lumiere.soleil(12.0, 0.0, catalogue).couleur
	var nuit: float = Lumiere.soleil(0.0, 0.0, catalogue).couleur
	verif.v(aube < midi, "chemin reel : la couleur de l'aube (orange, bas) doit etre STRICTEMENT plus basse que celle de midi (blanc-jaune), recu aube=%f midi=%f" % [aube, midi])
	verif.v(midi < nuit, "chemin reel : la couleur de midi doit etre STRICTEMENT plus basse que celle de la nuit (bleu, haut), recu midi=%f nuit=%f" % [midi, nuit])
	verif.v(is_equal_approx(aube, 0.2) and is_equal_approx(midi, 0.5) and is_equal_approx(nuit, 0.9), "chemin reel : valeurs exactes de la courbe reelle (aube 0.2, midi 0.5, nuit 0.9), recu aube=%f midi=%f nuit=%f" % [aube, midi, nuit])

func _chemin_reel_source_locale_augmente_lintensite_dans_son_rayon() -> void:
	var catalogue := _catalogue_lumiere_reel()
	catalogue.defaut.ambiante = {"intensite": 0.0, "couleur": 0.5}
	var donnees := _donnees_banc_reelles()
	var torche := _torche_reelle(donnees)
	var au_centre := Lumiere.locale(torche.position, [torche], catalogue)
	verif.v(au_centre.intensite > 0.0, "chemin reel : au centre de la torche reelle (ambiante nulle), l'intensite doit etre strictement positive, recu %f" % au_centre.intensite)
	verif.v(is_equal_approx(au_centre.intensite, torche.intensite), "chemin reel : au centre exact, l'intensite doit egaler celle de la torche (0.7), recu %f" % au_centre.intensite)

func _chemin_reel_couleur_locale_tiree_vers_la_couleur_de_la_source() -> void:
	var catalogue := _catalogue_lumiere_reel()
	catalogue.defaut.ambiante = {"intensite": 0.05, "couleur": 0.9}
	var donnees := _donnees_banc_reelles()
	var torche := _torche_reelle(donnees)
	var au_centre := Lumiere.locale(torche.position, [torche], catalogue)
	verif.v(au_centre.couleur < 0.9, "chemin reel : au centre de la torche reelle (orange, 0.15), la couleur doit etre TIREE en dessous de l'ambiante bleue (0.9), recu %f" % au_centre.couleur)
	verif.v(au_centre.couleur > torche.temperature_couleur, "chemin reel : la couleur ne doit jamais valoir exactement celle de la torche seule tant que l'ambiante contribue un peu, recu %f" % au_centre.couleur)

func _chemin_reel_hors_rayon_contribution_nulle() -> void:
	var catalogue := _catalogue_lumiere_reel()
	catalogue.defaut.ambiante = {"intensite": 0.1, "couleur": 0.6}
	var donnees := _donnees_banc_reelles()
	var torche := _torche_reelle(donnees)
	var loin: Vector3 = torche.position + Vector3(torche.rayon * 10.0, 0.0, 0.0)
	var v := Lumiere.locale(loin, [torche], catalogue)
	verif.v(is_equal_approx(v.intensite, 0.1), "chemin reel : loin de la torche reelle (hors rayon), seule l'ambiante doit rester en intensite, recu %f" % v.intensite)
	verif.v(is_equal_approx(v.couleur, 0.6), "chemin reel : loin de la torche reelle, seule l'ambiante doit rester en couleur, recu %f" % v.couleur)

func _chemin_reel_deux_sources_se_superposent_intensite_et_couleur() -> void:
	var catalogue := _catalogue_lumiere_reel()
	catalogue.defaut.ambiante = {"intensite": 0.0, "couleur": 0.5}
	var donnees := _donnees_banc_reelles()
	var torche := _torche_reelle(donnees)
	var cristal := _cristal_reel(donnees)
	# zone_melange (donnees reelles) est a portee des DEUX sources reelles.
	var decl_zone: Dictionary = {}
	for l in donnees.lecteurs:
		if l.id == "zone_melange":
			decl_zone = l
	var pos_zone: Array = decl_zone.position
	var position_zone := Vector3(pos_zone[0], pos_zone[1], pos_zone[2])
	var au_recouvrement := Lumiere.locale(position_zone, [torche, cristal], catalogue)
	var seule_torche: float = Lumiere.locale(position_zone, [torche], catalogue).intensite
	var seule_cristal: float = Lumiere.locale(position_zone, [cristal], catalogue).intensite
	verif.v(au_recouvrement.intensite > seule_torche and au_recouvrement.intensite > seule_cristal, "chemin reel : dans le recouvrement, l'intensite combinee doit depasser STRICTEMENT celle de chaque source seule, recu combinee=%f torche_seule=%f cristal_seule=%f" % [au_recouvrement.intensite, seule_torche, seule_cristal])
	verif.v(is_equal_approx(au_recouvrement.intensite, seule_torche + seule_cristal), "chemin reel : ambiante nulle ici, l'intensite combinee doit etre la SOMME exacte des deux contributions, recu %f attendu %f" % [au_recouvrement.intensite, seule_torche + seule_cristal])
	verif.v(au_recouvrement.couleur > torche.temperature_couleur and au_recouvrement.couleur < cristal.temperature_couleur, "chemin reel : dans le recouvrement torche(0.15)/cristal(0.85), la couleur doit etre STRICTEMENT ENTRE les deux, jamais ecrasee par l'une, recu %f" % au_recouvrement.couleur)

func _chemin_reel_source_deplacee_change_ce_que_lit_un_objet_fixe() -> void:
	var catalogue := _catalogue_lumiere_reel()
	catalogue.defaut.ambiante = {"intensite": 0.0, "couleur": 0.5}
	var donnees := _donnees_banc_reelles()
	var lanterne_decl: Dictionary = donnees.lanterne
	var centre := Vector3(lanterne_decl.centre[0], lanterne_decl.centre[1], lanterne_decl.centre[2])
	var point_fixe := Vector3(300.0, -80.0, 0.0)  # "passage_lanterne", data/banc_lumiere.json

	var position_t0 := BancLumiere.position_lanterne(centre, lanterne_decl.amplitude, lanterne_decl.periode, 0.0)
	var lanterne_t0 := {"position": position_t0, "rayon": lanterne_decl.rayon, "intensite": lanterne_decl.intensite, "temperature_couleur": lanterne_decl.temperature_couleur, "force": lanterne_decl.force}
	var v_t0 := Lumiere.locale(point_fixe, [lanterne_t0], catalogue)
	verif.v(v_t0.intensite > 0.0, "chemin reel : au depart (t=0), la lanterne reelle doit etre a portee du point de passage fixe, recu %f" % v_t0.intensite)

	var position_t_quart := BancLumiere.position_lanterne(centre, lanterne_decl.amplitude, lanterne_decl.periode, lanterne_decl.periode / 4.0)
	var lanterne_t_quart := {"position": position_t_quart, "rayon": lanterne_decl.rayon, "intensite": lanterne_decl.intensite, "temperature_couleur": lanterne_decl.temperature_couleur, "force": lanterne_decl.force}
	var v_t_quart := Lumiere.locale(point_fixe, [lanterne_t_quart], catalogue)
	verif.v(is_equal_approx(v_t_quart.intensite, 0.0), "chemin reel : un quart de periode plus tard, la lanterne reelle a quitte le rayon du point de passage fixe, recu %f -- la lumiere suit la source deplacee, jamais figee sur sa position d'origine" % v_t_quart.intensite)

func _chemin_reel_sans_source_et_la_nuit_intensite_zero_couleur_bleue() -> void:
	var catalogue := _catalogue_lumiere_reel()
	var ambiante_minuit := Lumiere.soleil(0.0, 0.0, catalogue)
	catalogue.defaut.ambiante = ambiante_minuit
	var v := Lumiere.locale(Vector3(-9999.0, -9999.0, 0.0), [], catalogue)
	verif.v(is_equal_approx(v.intensite, 0.0), "chemin reel : sans aucune source, en pleine nuit reelle, intensite attendue exactement 0.0, recu %f" % v.intensite)
	verif.v(v.couleur > 0.7, "chemin reel : sans aucune source, en pleine nuit reelle, la couleur doit rester nettement bleue (proche de 0.9), recu %f" % v.couleur)

func _chemin_reel_latitude_change_la_courbe_jour_nuit() -> void:
	var catalogue := _catalogue_lumiere_reel()
	var latitude_demo: float = catalogue.defaut.get("latitude_demonstration", 45.0)
	var heure_midi: float = catalogue.defaut.cycle.get("heure_midi", 12.0)
	var a_lequateur: float = Lumiere.soleil(heure_midi, 0.0, catalogue).intensite
	var a_latitude_demo: float = Lumiere.soleil(heure_midi, latitude_demo, catalogue).intensite
	verif.v(a_latitude_demo < a_lequateur, "chemin reel : a midi, la latitude de demonstration reelle (%f) doit rendre une intensite strictement plus faible qu'a l'equateur, recu equateur=%f latitude_demo=%f" % [latitude_demo, a_lequateur, a_latitude_demo])

func _chemin_reel_bornage_intensite_jamais_hors_zero_un() -> void:
	var catalogue := _catalogue_lumiere_reel()
	catalogue.defaut.ambiante = {"intensite": 1.0, "couleur": 0.5}
	var donnees := _donnees_banc_reelles()
	var torche := _torche_reelle(donnees)
	var cristal := _cristal_reel(donnees)
	# plein soleil (ambiante 1.0) plus deux sources reelles au centre de l'une d'elles :
	# la somme brute depasserait 1.0 sans le clamp de locale().
	var v := Lumiere.locale(torche.position, [torche, cristal], catalogue)
	verif.v(v.intensite <= 1.0, "chemin reel : intensite ne doit jamais depasser 1.0 meme cumulee (ambiante pleine + deux sources), recu %f" % v.intensite)
	verif.v(v.intensite >= 0.0, "chemin reel : intensite ne doit jamais etre negative, recu %f" % v.intensite)
