extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_lumiere.gd
#
# Verrouille scripts/lumiere.gd (chantier "lumiere ambiante -- scalaire
# ambiant avec temperature de couleur") : la lumiere locale comme
# { intensite, couleur } -- intensite = ambiante + somme des contributions
# ADDITIVES de sources a portee (attenuees par distance, meme forme que
# vent.gd/temperature.gd, jamais leur formule de delta), BORNEE [0.0,
# 1.0] ; couleur = MOYENNE PONDEREE (jamais additive) des couleurs a
# portee, ponderee par la contribution d'intensite de chacune, ambiante
# comme fond pondere par sa propre intensite -- la CONVERGENCE INSTANTANEE
# d'avancer() (intensite_lumiere/couleur_lumiere == locale() apres un seul
# appel, quel que soit delta), le retour Array des ids REELLEMENT changes,
# soleil() (intensite : cosinus de l'angle horaire module par la
# latitude, borne [0.0, 1.0] ; couleur : courbe par morceaux EN DONNEE),
# les gardes structurelles -- plus un cas hors domaine et un chemin reel
# sur data/lumiere.json.

const Lumiere = preload("res://scripts/lumiere.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_locale_est_lambiante_seule_sans_source()
	_source_dans_son_rayon_augmente_lintensite()
	_couleur_locale_est_tiree_vers_la_couleur_de_la_source_dans_son_rayon()
	_hors_du_rayon_dune_source_sa_contribution_est_nulle()
	_deux_sources_qui_se_superposent_sadditionnent_en_intensite_et_se_moyennent_en_couleur()
	_source_incomplete_alarme_et_est_ignoree_sans_bloquer_les_autres()
	_catalogue_sans_entree_defaut_alarme_et_rend_un_repli_neutre()
	_source_deplacee_change_ce_que_lit_un_objet_fixe()
	_sans_source_et_ambiante_nulle_intensite_zero_couleur_ambiante()
	_intensite_jamais_negative_jamais_au_dessus_de_un()

	_avancer_converge_instantanement_vers_la_locale()
	_avancer_delta_naffecte_jamais_le_resultat()
	_avancer_objet_sans_lumiere_prealable_compte_comme_change()
	_avancer_objet_dont_la_valeur_ne_change_pas_nest_pas_dans_le_retour()
	_avancer_objet_dont_la_couleur_seule_change_est_dans_le_retour()
	_avancer_sans_entree_defaut_alarme_et_ne_mute_rien()

	_soleil_intensite_pleine_a_midi_latitude_equateur()
	_soleil_intensite_nulle_a_minuit()
	_soleil_intensite_jamais_negative_jamais_au_dessus_de_un()
	_soleil_intensite_la_latitude_change_la_courbe()
	_soleil_heures_par_jour_non_positif_replie_sur_zero_jamais_division_par_zero()
	_soleil_sans_entree_defaut_alarme_et_rend_zero()
	_soleil_couleur_suit_la_courbe_en_donnee_aube_midi_crepuscule_nuit()
	_soleil_couleur_interpole_entre_deux_points_de_la_courbe()
	_soleil_couleur_courbe_vide_replie_sur_zero_sans_diviser_par_zero()

	_hors_domaine_le_mecanisme_ignore_le_domaine()
	_chemin_reel_data_lumiere_json()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: lumiere locale = {intensite, couleur} -- intensite ambiante " +
		"+ somme des contributions additives de sources attenuees par " +
		"distance (bornee [0.0, 1.0]), couleur moyenne ponderee par la " +
		"contribution d'intensite (jamais additive), gardes structurelles, " +
		"avancer() converge instantanement (delta sans effet) et rend les " +
		"ids reellement changes (intensite OU couleur), soleil() (intensite " +
		"bornee et modulee par la latitude, couleur par courbe en donnee), " +
		"hors domaine, chemin reel data/lumiere.json")
	quit(0)

# ---- locale() : intensite ----

func _locale_est_lambiante_seule_sans_source() -> void:
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.4, "couleur": 0.6}, "attenuation": {"exposant": 1.0}}}
	var v := Lumiere.locale(Vector3(10.0, 0.0, 0.0), [], catalogue)
	verif.v(is_equal_approx(v.intensite, 0.4), "sans aucune source, intensite doit exactement egaler l'ambiante, recu %f" % v.intensite)
	verif.v(is_equal_approx(v.couleur, 0.6), "sans aucune source, couleur doit exactement egaler la couleur ambiante, recu %f" % v.couleur)

func _source_dans_son_rayon_augmente_lintensite() -> void:
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.1, "couleur": 0.9}, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3(10.0, 0.0, 0.0), "rayon": 10.0, "intensite": 0.8, "temperature_couleur": 0.15, "force": 1.0}
	var au_centre := Lumiere.locale(Vector3(10.0, 0.0, 0.0), [source], catalogue)
	verif.v(is_equal_approx(au_centre.intensite, 0.9), "au centre de la source (distance 0, attenuation lineaire pleine) : intensite attendue 0.1 + 0.8*1.0 = 0.9, recu %f" % au_centre.intensite)

	var a_mi_rayon := Lumiere.locale(Vector3(15.0, 0.0, 0.0), [source], catalogue)
	verif.v(is_equal_approx(a_mi_rayon.intensite, 0.5), "a mi-rayon (distance 5 sur rayon 10, attenuation 0.5) : intensite attendue 0.1 + 0.8*0.5 = 0.5, recu %f" % a_mi_rayon.intensite)

func _couleur_locale_est_tiree_vers_la_couleur_de_la_source_dans_son_rayon() -> void:
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.05, "couleur": 0.9}, "attenuation": {"exposant": 1.0}}}
	var torche := {"position": Vector3.ZERO, "rayon": 80.0, "intensite": 0.7, "temperature_couleur": 0.15, "force": 1.0}
	var au_centre := Lumiere.locale(Vector3.ZERO, [torche], catalogue)
	verif.v(au_centre.couleur < 0.5, "au centre d'une torche orange (0.15) largement plus forte que l'ambiante (0.05), la couleur doit etre TIREE vers l'orange (couleur basse), recu %f" % au_centre.couleur)
	verif.v(au_centre.couleur > 0.15, "la couleur ne doit jamais valoir EXACTEMENT la couleur de la source seule tant que l'ambiante contribue encore un peu, recu %f" % au_centre.couleur)
	# poids ambiant = 0.05*0.9 = 0.045, poids torche = 0.7 -> couleur = (0.05*0.9 + 0.7*0.15) / (0.05+0.7)
	var attendu: float = (0.05 * 0.9 + 0.7 * 0.15) / (0.05 + 0.7)
	verif.v(is_equal_approx(au_centre.couleur, attendu), "formule exacte de la moyenne ponderee, recu %f attendu %f" % [au_centre.couleur, attendu])

func _hors_du_rayon_dune_source_sa_contribution_est_nulle() -> void:
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.05, "couleur": 0.9}, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "intensite": 1.0, "temperature_couleur": 0.1, "force": 1.0}
	var loin := Lumiere.locale(Vector3(50.0, 0.0, 0.0), [source], catalogue)
	verif.v(is_equal_approx(loin.intensite, 0.05), "hors du rayon de la source, seule l'intensite ambiante doit rester, recu %f" % loin.intensite)
	verif.v(is_equal_approx(loin.couleur, 0.9), "hors du rayon de la source, seule la couleur ambiante doit rester, recu %f" % loin.couleur)

func _deux_sources_qui_se_superposent_sadditionnent_en_intensite_et_se_moyennent_en_couleur() -> void:
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.0, "couleur": 0.5}, "attenuation": {"exposant": 1.0}}}
	var source_a := {"position": Vector3.ZERO, "rayon": 20.0, "intensite": 0.4, "temperature_couleur": 0.1, "force": 1.0}
	var source_b := {"position": Vector3.ZERO, "rayon": 20.0, "intensite": 0.4, "temperature_couleur": 0.9, "force": 1.0}
	var au_meme_point := Lumiere.locale(Vector3.ZERO, [source_a, source_b], catalogue)
	verif.v(is_equal_approx(au_meme_point.intensite, 0.8), "deux sources qui se recouvrent exactement doivent ADDITIONNER leurs intensites (0.4+0.4=0.8), jamais une moyenne, recu %f" % au_meme_point.intensite)
	verif.v(is_equal_approx(au_meme_point.couleur, 0.5), "deux sources de poids egal (0.4/0.4) et de couleurs opposees (0.1/0.9) doivent MOYENNER exactement au milieu (0.5, ambiante nulle), recu %f" % au_meme_point.couleur)

func _source_incomplete_alarme_et_est_ignoree_sans_bloquer_les_autres() -> void:
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.0, "couleur": 0.5}, "attenuation": {"exposant": 1.0}}}
	var incomplete := {"position": Vector3.ZERO, "intensite": 0.9, "temperature_couleur": 0.2, "force": 1.0}  # "rayon" manquant
	var complete := {"position": Vector3.ZERO, "rayon": 10.0, "intensite": 0.3, "temperature_couleur": 0.7, "force": 1.0}
	var total := Lumiere.locale(Vector3.ZERO, [incomplete, complete], catalogue)
	verif.v(is_equal_approx(total.intensite, 0.3), "une source incomplete (rayon absent) doit etre ignoree seule, la source complete doit quand meme contribuer, recu %f" % total.intensite)
	verif.v(is_equal_approx(total.couleur, 0.7), "la couleur ne doit refleter que la source complete, jamais l'incomplete, recu %f" % total.couleur)

func _catalogue_sans_entree_defaut_alarme_et_rend_un_repli_neutre() -> void:
	var v := Lumiere.locale(Vector3.ZERO, [], {})
	verif.v(v.intensite == 0.0, "catalogue sans entree 'defaut' : locale() doit alarmer et rendre intensite 0.0")
	verif.v(v.couleur == 0.0, "catalogue sans entree 'defaut' : locale() doit alarmer et rendre couleur 0.0")

func _source_deplacee_change_ce_que_lit_un_objet_fixe() -> void:
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.0, "couleur": 0.9}, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3(50.0, 0.0, 0.0), "rayon": 10.0, "intensite": 0.7, "temperature_couleur": 0.2, "force": 1.0}
	var point_fixe := Vector3.ZERO

	var avant := Lumiere.locale(point_fixe, [source], catalogue)
	verif.v(is_equal_approx(avant.intensite, 0.0), "source hors de portee du point fixe : intensite attendue 0.0, recu %f" % avant.intensite)

	source.position = Vector3.ZERO  # l'appelant deplace la source lui-meme
	var apres := Lumiere.locale(point_fixe, [source], catalogue)
	verif.v(is_equal_approx(apres.intensite, 0.7), "meme source deplacee au centre du point fixe : intensite attendue 0.7, recu %f -- le mecanisme ne possede ni ne cache jamais une source" % apres.intensite)
	verif.v(is_equal_approx(apres.couleur, 0.2), "la couleur doit desormais etre celle de la source, largement dominante sur une ambiante nulle, recu %f" % apres.couleur)

func _sans_source_et_ambiante_nulle_intensite_zero_couleur_ambiante() -> void:
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.0, "couleur": 0.9}, "attenuation": {"exposant": 1.0}}}
	var v := Lumiere.locale(Vector3.ZERO, [], catalogue)
	verif.v(v.intensite == 0.0, "sans source et ambiante nulle (nuit) : intensite doit etre exactement 0.0, recu %f" % v.intensite)
	verif.v(is_equal_approx(v.couleur, 0.9), "sans source et ambiante nulle (nuit) : la couleur doit rester celle de l'ambiante (bleu froid), JAMAIS une valeur neutre inventee par une division par zero evitee au hasard, recu %f" % v.couleur)

func _intensite_jamais_negative_jamais_au_dessus_de_un() -> void:
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.9, "couleur": 0.5}, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "intensite": 0.9, "temperature_couleur": 0.5, "force": 1.0}
	var au_centre := Lumiere.locale(Vector3.ZERO, [source, source, source], catalogue)
	verif.v(au_centre.intensite <= 1.0, "trois sources fortes plus une ambiante forte doivent rester bornees a 1.0, recu %f" % au_centre.intensite)
	verif.v(au_centre.intensite >= 0.0, "intensite ne doit jamais etre negative, recu %f" % au_centre.intensite)

# ---- avancer() ----

func _avancer_converge_instantanement_vers_la_locale() -> void:
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.2, "couleur": 0.7}, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "intensite": 0.5, "temperature_couleur": 0.2, "force": 1.0}
	var objet := {"id": "x", "position": Vector3.ZERO, "proprietes": {"intensite_lumiere": 0.0, "couleur_lumiere": 0.0}}
	var monde := [objet]
	Lumiere.avancer(monde, [source], 0.016, catalogue)
	var attendu: Dictionary = Lumiere.locale(Vector3.ZERO, [source], catalogue)
	verif.v(is_equal_approx(objet.proprietes.intensite_lumiere, attendu.intensite), "CONVERGENCE INSTANTANEE : apres un seul appel, intensite_lumiere doit exactement egaler locale().intensite, recu %f attendu %f" % [objet.proprietes.intensite_lumiere, attendu.intensite])
	verif.v(is_equal_approx(objet.proprietes.couleur_lumiere, attendu.couleur), "CONVERGENCE INSTANTANEE : apres un seul appel, couleur_lumiere doit exactement egaler locale().couleur, recu %f attendu %f" % [objet.proprietes.couleur_lumiere, attendu.couleur])

func _avancer_delta_naffecte_jamais_le_resultat() -> void:
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.3, "couleur": 0.4}, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "intensite": 0.4, "temperature_couleur": 0.6, "force": 1.0}
	var petit_delta := {"id": "x", "position": Vector3.ZERO, "proprietes": {}}
	var grand_delta := {"id": "x", "position": Vector3.ZERO, "proprietes": {}}
	Lumiere.avancer([petit_delta], [source], 0.001, catalogue)
	Lumiere.avancer([grand_delta], [source], 500.0, catalogue)
	verif.v(is_equal_approx(petit_delta.proprietes.intensite_lumiere, grand_delta.proprietes.intensite_lumiere), "delta ne doit JAMAIS influencer l'intensite -- convergence instantanee, recu %f vs %f" % [petit_delta.proprietes.intensite_lumiere, grand_delta.proprietes.intensite_lumiere])
	verif.v(is_equal_approx(petit_delta.proprietes.couleur_lumiere, grand_delta.proprietes.couleur_lumiere), "delta ne doit JAMAIS influencer la couleur -- convergence instantanee, recu %f vs %f" % [petit_delta.proprietes.couleur_lumiere, grand_delta.proprietes.couleur_lumiere])

func _avancer_objet_sans_lumiere_prealable_compte_comme_change() -> void:
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.0, "couleur": 0.5}, "attenuation": {"exposant": 1.0}}}
	var objet := {"id": "neuf", "position": Vector3.ZERO, "proprietes": {}}
	var changements := Lumiere.avancer([objet], [], 1.0, catalogue)
	verif.v(changements.has("neuf"), "un objet sans 'intensite_lumiere'/'couleur_lumiere' prealables doit apparaitre dans le retour (premiere pose), recu %s" % [changements])
	verif.v(objet.proprietes.has("intensite_lumiere") and objet.proprietes.has("couleur_lumiere"), "l'objet doit desormais porter les deux cles")

func _avancer_objet_dont_la_valeur_ne_change_pas_nest_pas_dans_le_retour() -> void:
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.25, "couleur": 0.6}, "attenuation": {"exposant": 1.0}}}
	var objet := {"id": "stable", "position": Vector3(9999.0, 0.0, 0.0), "proprietes": {"intensite_lumiere": 0.25, "couleur_lumiere": 0.6}}
	var changements := Lumiere.avancer([objet], [], 1.0, catalogue)
	verif.v(not changements.has("stable"), "un objet dont ni l'intensite ni la couleur ne changent (deja a l'ambiante, aucune source) ne doit jamais apparaitre dans le retour, recu %s" % [changements])

func _avancer_objet_dont_la_couleur_seule_change_est_dans_le_retour() -> void:
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.0, "couleur": 0.6}, "attenuation": {"exposant": 1.0}}}
	# source d'intensite nulle mais de couleur differente : force 0.0 -> aucune contribution d'intensite,
	# donc la couleur reste celle de l'ambiante (poids_total nul cote source) -- pour changer SEULEMENT la
	# couleur sans toucher l'intensite, on fait varier directement l'ambiante entre deux appels.
	var objet := {"id": "teinte", "position": Vector3.ZERO, "proprietes": {"intensite_lumiere": 0.0, "couleur_lumiere": 0.6}}
	var catalogue_2 := {"defaut": {"ambiante": {"intensite": 0.0, "couleur": 0.9}, "attenuation": {"exposant": 1.0}}}
	var changements := Lumiere.avancer([objet], [], 1.0, catalogue_2)
	verif.v(changements.has("teinte"), "un objet dont seule la couleur change (intensite ambiante nulle des deux cotes) doit apparaitre dans le retour, recu %s" % [changements])
	verif.v(is_equal_approx(objet.proprietes.intensite_lumiere, 0.0), "l'intensite ne doit pas avoir bouge, recu %f" % objet.proprietes.intensite_lumiere)
	verif.v(is_equal_approx(objet.proprietes.couleur_lumiere, 0.9), "la couleur doit avoir suivi le nouveau catalogue, recu %f" % objet.proprietes.couleur_lumiere)

func _avancer_sans_entree_defaut_alarme_et_ne_mute_rien() -> void:
	var objet := {"id": "x", "position": Vector3.ZERO, "proprietes": {"intensite_lumiere": 0.5, "couleur_lumiere": 0.5}}
	var changements := Lumiere.avancer([objet], [], 1.0, {})
	verif.v(changements.is_empty(), "catalogue sans entree 'defaut' : avancer() doit alarmer et rendre un Array vide")
	verif.v(is_equal_approx(objet.proprietes.intensite_lumiere, 0.5), "catalogue sans entree 'defaut' : avancer() ne doit rien muter (intensite)")
	verif.v(is_equal_approx(objet.proprietes.couleur_lumiere, 0.5), "catalogue sans entree 'defaut' : avancer() ne doit rien muter (couleur)")

# ---- soleil() : intensite ----

func _soleil_intensite_pleine_a_midi_latitude_equateur() -> void:
	var catalogue := {"defaut": {"cycle": {"heures_par_jour": 24.0, "heure_midi": 12.0}, "courbe_couleur": []}}
	var v := Lumiere.soleil(12.0, 0.0, catalogue)
	verif.v(is_equal_approx(v.intensite, 1.0), "a midi, a l'equateur (latitude 0), soleil().intensite doit rendre exactement 1.0 (plein soleil), recu %f" % v.intensite)

func _soleil_intensite_nulle_a_minuit() -> void:
	var catalogue := {"defaut": {"cycle": {"heures_par_jour": 24.0, "heure_midi": 12.0}, "courbe_couleur": []}}
	var v := Lumiere.soleil(0.0, 0.0, catalogue)
	verif.v(is_equal_approx(v.intensite, 0.0), "a minuit (heure 0, oppose exact de heure_midi sur un cycle de 24h), soleil().intensite doit rendre exactement 0.0, recu %f" % v.intensite)

func _soleil_intensite_jamais_negative_jamais_au_dessus_de_un() -> void:
	var catalogue := {"defaut": {"cycle": {"heures_par_jour": 24.0, "heure_midi": 12.0}, "courbe_couleur": []}}
	for heure in [1.0, 2.0, 3.0, 12.0, 22.0, 23.0]:
		var v: float = Lumiere.soleil(heure, 0.0, catalogue).intensite
		verif.v(v >= 0.0 and v <= 1.0, "soleil().intensite doit toujours rester dans [0.0, 1.0] (heure=%f), recu %f" % [heure, v])

func _soleil_intensite_la_latitude_change_la_courbe() -> void:
	var catalogue := {"defaut": {"cycle": {"heures_par_jour": 24.0, "heure_midi": 12.0}, "courbe_couleur": []}}
	var a_lequateur: float = Lumiere.soleil(12.0, 0.0, catalogue).intensite
	var a_haute_latitude: float = Lumiere.soleil(12.0, 60.0, catalogue).intensite
	verif.v(a_haute_latitude < a_lequateur, "a la meme heure (midi), une latitude plus haute doit rendre une intensite STRICTEMENT plus faible qu'a l'equateur, recu equateur=%f haute_latitude=%f" % [a_lequateur, a_haute_latitude])
	var au_pole: float = Lumiere.soleil(12.0, 90.0, catalogue).intensite
	verif.v(is_equal_approx(au_pole, 0.0), "a 90 degres de latitude (pole, cos(90)=0), soleil().intensite doit rendre 0.0 quelle que soit l'heure, recu %f" % au_pole)

func _soleil_heures_par_jour_non_positif_replie_sur_zero_jamais_division_par_zero() -> void:
	var catalogue := {"defaut": {"cycle": {"heures_par_jour": 0.0, "heure_midi": 12.0}, "courbe_couleur": []}}
	var v := Lumiere.soleil(12.0, 0.0, catalogue)
	verif.v(v.intensite == 0.0, "heures_par_jour a 0.0 doit replier l'intensite sur 0.0 sans diviser par zero, recu %f" % v.intensite)
	verif.v(not is_nan(v.intensite) and not is_inf(v.intensite), "soleil().intensite ne doit jamais rendre NaN ni infini")
	verif.v(not is_nan(v.couleur) and not is_inf(v.couleur), "soleil().couleur ne doit jamais rendre NaN ni infini meme si heures_par_jour est invalide")

func _soleil_sans_entree_defaut_alarme_et_rend_zero() -> void:
	var v := Lumiere.soleil(12.0, 0.0, {})
	verif.v(v.intensite == 0.0, "catalogue sans entree 'defaut' : soleil() doit alarmer et rendre intensite 0.0")
	verif.v(v.couleur == 0.0, "catalogue sans entree 'defaut' : soleil() doit alarmer et rendre couleur 0.0")

# ---- soleil() : couleur ----

func _soleil_couleur_suit_la_courbe_en_donnee_aube_midi_crepuscule_nuit() -> void:
	var courbe := [
		{"heure": 0.0, "couleur": 0.9},
		{"heure": 6.0, "couleur": 0.2},
		{"heure": 12.0, "couleur": 0.5},
		{"heure": 18.0, "couleur": 0.2},
		{"heure": 24.0, "couleur": 0.9},
	]
	var catalogue := {"defaut": {"cycle": {"heures_par_jour": 24.0, "heure_midi": 12.0}, "courbe_couleur": courbe}}
	verif.v(is_equal_approx(Lumiere.soleil(0.0, 0.0, catalogue).couleur, 0.9), "minuit : couleur attendue exactement le point de la courbe (0.9, bleu froid), recu %f" % Lumiere.soleil(0.0, 0.0, catalogue).couleur)
	verif.v(is_equal_approx(Lumiere.soleil(6.0, 0.0, catalogue).couleur, 0.2), "aube : couleur attendue exactement le point de la courbe (0.2, orange), recu %f" % Lumiere.soleil(6.0, 0.0, catalogue).couleur)
	verif.v(is_equal_approx(Lumiere.soleil(12.0, 0.0, catalogue).couleur, 0.5), "midi : couleur attendue exactement le point de la courbe (0.5, blanc-jaune), recu %f" % Lumiere.soleil(12.0, 0.0, catalogue).couleur)
	verif.v(is_equal_approx(Lumiere.soleil(18.0, 0.0, catalogue).couleur, 0.2), "crepuscule : couleur attendue exactement le point de la courbe (0.2, orange), recu %f" % Lumiere.soleil(18.0, 0.0, catalogue).couleur)

func _soleil_couleur_interpole_entre_deux_points_de_la_courbe() -> void:
	var courbe := [
		{"heure": 0.0, "couleur": 0.0},
		{"heure": 10.0, "couleur": 1.0},
	]
	var catalogue := {"defaut": {"cycle": {"heures_par_jour": 24.0, "heure_midi": 12.0}, "courbe_couleur": courbe}}
	var v: float = Lumiere.soleil(5.0, 0.0, catalogue).couleur
	verif.v(is_equal_approx(v, 0.5), "a mi-chemin entre deux points (heure 5 entre 0 et 10), la couleur doit etre interpolee LINEAIREMENT (0.5), recu %f" % v)

func _soleil_couleur_courbe_vide_replie_sur_zero_sans_diviser_par_zero() -> void:
	var catalogue := {"defaut": {"cycle": {"heures_par_jour": 24.0, "heure_midi": 12.0}, "courbe_couleur": []}}
	var v: float = Lumiere.soleil(12.0, 0.0, catalogue).couleur
	verif.v(v == 0.0, "courbe_couleur vide (donnee absente) doit replier sur 0.0, jamais un plantage, recu %f" % v)

# ---- Hors domaine ----

# Aucune chaine "lumiere"/"soleil"/"feu"/"colon" n'apparait dans le
# RAISONNEMENT de scripts/lumiere.gd -- seul le nom des cles est fixe par
# le contrat (position/rayon/intensite/temperature_couleur/force), le
# mecanisme lui-meme ne sait pas que "intensite"/"couleur" designent de la
# lumiere : ce cas fait porter les memes cles un scalaire de nature
# totalement differente (une concentration chimique locale et son pH) et
# verifie que le meme code produit le meme calcul.
func _hors_domaine_le_mecanisme_ignore_le_domaine() -> void:
	var catalogue_chimie := {"defaut": {"ambiante": {"intensite": 0.1, "couleur": 7.0}, "attenuation": {"exposant": 1.0}}}
	var fuite := {"position": Vector3.ZERO, "rayon": 100.0, "intensite": 0.6, "temperature_couleur": 3.0, "force": 1.0}
	var au_centre := Lumiere.locale(Vector3.ZERO, [fuite], catalogue_chimie)
	verif.v(is_equal_approx(au_centre.intensite, 0.7), "hors domaine (concentration chimique, rien a voir avec la lumiere) : au centre d'une fuite, l'intensite doit sommer ambiante + contribution comme n'importe quel autre scalaire, recu %f" % au_centre.intensite)

	var capteur := {"id": "capteur_chimique", "position": Vector3.ZERO, "proprietes": {}}
	var monde := [capteur]
	Lumiere.avancer(monde, [fuite], 1.0, catalogue_chimie)
	verif.v(is_equal_approx(capteur.proprietes.intensite_lumiere, 0.7), "hors domaine : avancer() doit ecrire la meme valeur sous la meme cle generique, quel que soit ce qu'elle represente, recu %f" % capteur.proprietes.intensite_lumiere)

# ---- Chemin reel ----

func _catalogue_lumiere_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/lumiere.json"))

func _chemin_reel_data_lumiere_json() -> void:
	var catalogue := _catalogue_lumiere_reel()
	verif.v(catalogue.has("defaut"), "data/lumiere.json doit porter une entree 'defaut'")
	verif.v(catalogue.defaut.has("cycle"), "data/lumiere.json:defaut doit porter 'cycle'")
	verif.v(catalogue.defaut.has("courbe_couleur"), "data/lumiere.json:defaut doit porter 'courbe_couleur'")

	var latitude_demo: float = catalogue.defaut.get("latitude_demonstration", -9999.0)
	verif.v(latitude_demo != -9999.0, "data/lumiere.json:defaut doit porter 'latitude_demonstration'")

	var midi_reel := Lumiere.soleil(catalogue.defaut.cycle.get("heure_midi", 12.0), 0.0, catalogue)
	verif.v(is_equal_approx(midi_reel.intensite, 1.0), "chemin reel : a l'heure_midi reelle et a l'equateur, soleil().intensite doit rendre 1.0, recu %f" % midi_reel.intensite)

	var minuit_reel := Lumiere.soleil(0.0, 0.0, catalogue)
	verif.v(minuit_reel.couleur > midi_reel.couleur, "chemin reel : la couleur reelle de minuit doit etre STRICTEMENT plus bleue (valeur plus haute) que celle de midi, recu minuit=%f midi=%f" % [minuit_reel.couleur, midi_reel.couleur])

	var source_reelle := {"position": Vector3.ZERO, "rayon": 50.0, "intensite": 0.9, "temperature_couleur": 0.15, "force": 1.0}
	var pres := Lumiere.locale(Vector3.ZERO, [source_reelle], catalogue)
	verif.v(pres.intensite > catalogue.defaut.ambiante.get("intensite", 0.0), "chemin reel : au centre d'une source reelle, l'intensite locale doit depasser l'ambiante seule")
