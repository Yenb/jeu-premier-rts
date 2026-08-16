extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_vent.gd
#
# Verrouille scripts/vent.gd (chantier "vent") : les trois couches (fond,
# variation lente, rafales) additives et independamment desactivables, la
# perturbation locale (agregation additive, confinee au rayon d'une source,
# attenuation configurable), et facteur_directionnel (formule exacte,
# convention de signe, effet nul a vent nul ou a angle perpendiculaire) --
# plus un cas hors domaine et un chemin reel sur data/vent.json.

const Vent = preload("res://scripts/vent.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_fond_seul_rend_direction_et_force_de_depart_sans_variation()
	_variation_lente_fait_reellement_tourner_la_direction_dans_le_temps()
	_variation_lente_module_la_force_selon_la_formule_exacte()
	_rafales_ajoutent_une_variation_rapide_a_la_force_selon_la_formule_exacte()
	_chaque_couche_desactivee_ne_casse_pas_les_deux_autres()
	_source_locale_a_portee_contribue_selon_lattenuation_exacte()
	_source_locale_hors_de_son_rayon_ne_contribue_rien()
	_deux_sources_qui_se_recouvrent_sadditionnent_jamais_un_ecrasement()
	_source_locale_incomplete_alarme_et_est_ignoree_sans_bloquer_les_autres()
	_catalogue_sans_entree_defaut_alarme_et_rend_un_repli_neutre()
	_facteur_directionnel_formule_exacte_dans_les_trois_directions()
	_facteur_directionnel_est_neutre_a_vent_nul_ou_direction_nulle()
	_facteur_directionnel_neutre_sans_reference_force_ou_sans_directionnel()
	_intensite_du_vent_module_lamplitude_de_leffet_directionnel()
	_hors_domaine_le_mecanisme_ignore_le_domaine()
	_chemin_reel_data_vent_json()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: trois couches additives et independamment desactivables, " +
		"perturbation locale additive confinee au rayon avec attenuation " +
		"configurable, facteur_directionnel a formule exacte et convention " +
		"de signe verifiee, neutralite a vent nul, hors domaine, chemin reel " +
		"data/vent.json")
	quit(0)

# ---- Couche FOND ----

func _fond_seul_rend_direction_et_force_de_depart_sans_variation() -> void:
	var catalogue := {"defaut": {"fond": {"direction": {"x": 1.0, "y": 0.0, "z": 0.0}, "force": 5.0}}}
	var v0 := Vent.vecteur(Vector3.ZERO, 0.0, catalogue)
	var v100 := Vent.vecteur(Vector3.ZERO, 100.0, catalogue)
	verif.v(v0.is_equal_approx(Vector3(5.0, 0.0, 0.0)), "fond seul : vecteur attendu (5,0,0) a t=0, recu %s" % v0)
	verif.v(v100.is_equal_approx(Vector3(5.0, 0.0, 0.0)), "fond seul, sans variation_lente/rafales : identique a t=100, recu %s" % v100)

# ---- Couche VARIATION LENTE (direction) ----

func _variation_lente_fait_reellement_tourner_la_direction_dans_le_temps() -> void:
	var catalogue := {
		"defaut": {
			"fond": {"direction": {"x": 1.0, "y": 0.0, "z": 0.0}, "force": 1.0},
			"variation_lente": {"amplitude_angle": 90.0, "periode_angle": 40.0},
		}
	}
	var base := Vector3(1.0, 0.0, 0.0)
	var d_t0 := Vent.vecteur(Vector3.ZERO, 0.0, catalogue).normalized()
	var d_quart := Vent.vecteur(Vector3.ZERO, 10.0, catalogue).normalized()  # T/4 : offset = 90*sin(pi/2) = 90 deg
	var d_moitie := Vent.vecteur(Vector3.ZERO, 20.0, catalogue).normalized() # T/2 : offset = 90*sin(pi) = 0 deg
	var d_trois_quarts := Vent.vecteur(Vector3.ZERO, 30.0, catalogue).normalized() # 3T/4 : offset = -90 deg

	verif.v(d_t0.is_equal_approx(base), "a t=0, offset nul : la direction doit rester exactement le fond")
	verif.v(not d_quart.is_equal_approx(base), "a T/4, un offset de 90 deg doit reellement faire tourner la direction")
	verif.v(is_equal_approx(base.dot(d_quart), 0.0), "a T/4 (offset 90 deg), la direction tournee doit etre EXACTEMENT perpendiculaire au fond (convention independante du sens de rotation)")
	verif.v(d_moitie.is_equal_approx(base), "a T/2, sin(pi)=0 : la direction doit revenir exactement au fond (verrou de periodicite, pas une derive lineaire)")
	verif.v(is_equal_approx(base.dot(d_trois_quarts), 0.0), "a 3T/4 (offset -90 deg), de nouveau perpendiculaire au fond")
	verif.v(d_quart.dot(d_trois_quarts) < -0.99, "T/4 (+90 deg) et 3T/4 (-90 deg) doivent pointer dans des sens OPPOSES -- preuve d'une vraie oscillation, pas d'une valeur absolue")
	verif.v(is_equal_approx(d_quart.z, 0.0), "la rotation se fait autour de l'axe Z : une direction de fond dans le plan XY doit y rester")

func _variation_lente_module_la_force_selon_la_formule_exacte() -> void:
	var catalogue := {
		"defaut": {
			"fond": {"direction": {"x": 1.0, "y": 0.0, "z": 0.0}, "force": 10.0},
			"variation_lente": {"amplitude_force": 3.0, "periode_force": 20.0},
		}
	}
	var f0 := Vent.vecteur(Vector3.ZERO, 0.0, catalogue).length()
	var f_quart := Vent.vecteur(Vector3.ZERO, 5.0, catalogue).length()   # 10 + 3*sin(pi/2) = 13
	var f_trois_quarts := Vent.vecteur(Vector3.ZERO, 15.0, catalogue).length() # 10 + 3*sin(3pi/2) = 7
	verif.v(is_equal_approx(f0, 10.0), "a t=0, force attendue exactement 10.0, recu %f" % f0)
	verif.v(is_equal_approx(f_quart, 13.0), "a T/4, force attendue exactement 13.0 (formule 10+3*sin(pi/2)), recu %f" % f_quart)
	verif.v(is_equal_approx(f_trois_quarts, 7.0), "a 3T/4, force attendue exactement 7.0 (formule 10+3*sin(3pi/2)), recu %f" % f_trois_quarts)

# ---- Couche RAFALES ----

func _rafales_ajoutent_une_variation_rapide_a_la_force_selon_la_formule_exacte() -> void:
	var catalogue := {
		"defaut": {
			"fond": {"direction": {"x": 1.0, "y": 0.0, "z": 0.0}, "force": 5.0},
			"rafales": {"amplitude": 2.0, "frequence": 0.25},
		}
	}
	var f_t1 := Vent.vecteur(Vector3.ZERO, 1.0, catalogue).length()  # 5 + 2*sin(2*pi*0.25*1) = 5 + 2*sin(pi/2) = 7
	var f_t3 := Vent.vecteur(Vector3.ZERO, 3.0, catalogue).length()  # 5 + 2*sin(2*pi*0.25*3) = 5 + 2*sin(3pi/2) = 3
	verif.v(is_equal_approx(f_t1, 7.0), "rafale a t=1 : force attendue exactement 7.0, recu %f" % f_t1)
	verif.v(is_equal_approx(f_t3, 3.0), "rafale a t=3 : force attendue exactement 3.0, recu %f" % f_t3)

# ---- Independance des trois couches ----

func _chaque_couche_desactivee_ne_casse_pas_les_deux_autres() -> void:
	var base_direction := {"x": 1.0, "y": 0.0, "z": 0.0}
	# amplitude_angle a 0.0 (periode non nulle quand meme fournie) : aucune rotation.
	var sans_lente_direction := {
		"defaut": {
			"fond": {"direction": base_direction, "force": 4.0},
			"variation_lente": {"amplitude_angle": 0.0, "periode_angle": 10.0, "amplitude_force": 1.0, "periode_force": 8.0},
			"rafales": {"amplitude": 0.5, "frequence": 1.0},
		}
	}
	var v := Vent.vecteur(Vector3.ZERO, 3.0, sans_lente_direction).normalized()
	verif.v(v.is_equal_approx(Vector3(1.0, 0.0, 0.0)), "amplitude_angle a 0.0 : la direction ne doit jamais tourner, meme avec periode_angle non nulle et les deux autres couches actives")

	# periode_angle a 0.0 (amplitude non nulle) : aucune rotation, aucun crash (division par zero evitee).
	var periode_nulle := {
		"defaut": {
			"fond": {"direction": base_direction, "force": 4.0},
			"variation_lente": {"amplitude_angle": 60.0, "periode_angle": 0.0},
		}
	}
	var v2 := Vent.vecteur(Vector3.ZERO, 5.0, periode_nulle).normalized()
	verif.v(v2.is_equal_approx(Vector3(1.0, 0.0, 0.0)), "periode_angle a 0.0 : repli sur le fond, jamais un crash ni une rotation devinee")

	# rafales desactivees (amplitude 0.0) : seules fond+lente contribuent.
	var sans_rafale := {
		"defaut": {
			"fond": {"direction": base_direction, "force": 10.0},
			"variation_lente": {"amplitude_force": 2.0, "periode_force": 8.0},
			"rafales": {"amplitude": 0.0, "frequence": 3.0},
		}
	}
	var force_sans_rafale := Vent.vecteur(Vector3.ZERO, 2.0, sans_rafale).length()
	var sans_rafale_ni_lente := {"defaut": {"fond": {"direction": base_direction, "force": 10.0}, "variation_lente": {"amplitude_force": 2.0, "periode_force": 8.0}}}
	var force_reference := Vent.vecteur(Vector3.ZERO, 2.0, sans_rafale_ni_lente).length()
	verif.v(is_equal_approx(force_sans_rafale, force_reference), "amplitude de rafale a 0.0 : la force doit etre identique a la meme configuration sans bloc 'rafales' du tout")

	# les trois couches a zero : repli exact sur le fond seul.
	var trois_a_zero := {
		"defaut": {
			"fond": {"direction": base_direction, "force": 7.0},
			"variation_lente": {"amplitude_angle": 0.0, "amplitude_force": 0.0},
			"rafales": {"amplitude": 0.0},
		}
	}
	var v3 := Vent.vecteur(Vector3.ZERO, 42.0, trois_a_zero)
	verif.v(v3.is_equal_approx(Vector3(7.0, 0.0, 0.0)), "les trois couches a zero doivent rendre EXACTEMENT le fond, quel que soit le temps")

# ---- Perturbation locale ----

func _source_locale_a_portee_contribue_selon_lattenuation_exacte() -> void:
	var catalogue_lineaire := {"defaut": {"fond": {"direction": {"x": 1.0, "y": 0.0, "z": 0.0}, "force": 0.0}, "attenuation_source": {"exposant": 1.0}}}
	var source := {"position": Vector3(10.0, 0.0, 0.0), "rayon": 10.0, "vecteur": Vector3(0.0, 5.0, 0.0)}

	var au_centre := Vent.vecteur(Vector3(10.0, 0.0, 0.0), 0.0, catalogue_lineaire, [source])
	verif.v(au_centre.is_equal_approx(Vector3(0.0, 5.0, 0.0)), "a distance 0 du centre de la source, attenuation lineaire pleine (1.0) : contribution attendue (0,5,0), recu %s" % au_centre)

	var a_mi_rayon := Vent.vecteur(Vector3(15.0, 0.0, 0.0), 0.0, catalogue_lineaire, [source])
	verif.v(a_mi_rayon.is_equal_approx(Vector3(0.0, 2.5, 0.0)), "a mi-rayon (distance 5 sur rayon 10), attenuation lineaire de 0.5 : contribution attendue (0,2.5,0), recu %s" % a_mi_rayon)

	var catalogue_quadratique := {"defaut": {"fond": {"direction": {"x": 1.0, "y": 0.0, "z": 0.0}, "force": 0.0}, "attenuation_source": {"exposant": 2.0}}}
	var a_mi_rayon_quadratique := Vent.vecteur(Vector3(15.0, 0.0, 0.0), 0.0, catalogue_quadratique, [source])
	verif.v(a_mi_rayon_quadratique.is_equal_approx(Vector3(0.0, 1.25, 0.0)), "meme mi-rayon avec un exposant 2.0 (forme d'attenuation en donnee) : contribution attendue (0,1.25,0) (0.5^2 = 0.25), recu %s" % a_mi_rayon_quadratique)

func _source_locale_hors_de_son_rayon_ne_contribue_rien() -> void:
	var catalogue := {"defaut": {"fond": {"direction": {"x": 1.0, "y": 0.0, "z": 0.0}, "force": 3.0}}}
	var source := {"position": Vector3(0.0, 0.0, 0.0), "rayon": 10.0, "vecteur": Vector3(0.0, 100.0, 0.0)}
	var loin := Vent.vecteur(Vector3(50.0, 0.0, 0.0), 0.0, catalogue, [source])
	verif.v(loin.is_equal_approx(Vector3(3.0, 0.0, 0.0)), "hors du rayon de la source, seul le vent ambiant doit rester, recu %s" % loin)

func _deux_sources_qui_se_recouvrent_sadditionnent_jamais_un_ecrasement() -> void:
	var catalogue := {"defaut": {"fond": {"direction": {"x": 1.0, "y": 0.0, "z": 0.0}, "force": 0.0}}}
	var source_a := {"position": Vector3(0.0, 0.0, 0.0), "rayon": 20.0, "vecteur": Vector3(4.0, 0.0, 0.0)}
	var source_b := {"position": Vector3(0.0, 0.0, 0.0), "rayon": 20.0, "vecteur": Vector3(0.0, 6.0, 0.0)}
	var au_meme_point := Vent.vecteur(Vector3.ZERO, 0.0, catalogue, [source_a, source_b])
	verif.v(au_meme_point.is_equal_approx(Vector3(4.0, 6.0, 0.0)), "deux sources qui se recouvrent exactement doivent ADDITIONNER leurs contributions, jamais en garder une seule ni faire une moyenne, recu %s" % au_meme_point)

func _source_locale_incomplete_alarme_et_est_ignoree_sans_bloquer_les_autres() -> void:
	var catalogue := {"defaut": {"fond": {"direction": {"x": 1.0, "y": 0.0, "z": 0.0}, "force": 0.0}}}
	var incomplete := {"position": Vector3.ZERO, "vecteur": Vector3(9.0, 9.0, 0.0)}  # "rayon" manquant
	var complete := {"position": Vector3.ZERO, "rayon": 10.0, "vecteur": Vector3(1.0, 2.0, 0.0)}
	var total := Vent.vecteur(Vector3.ZERO, 0.0, catalogue, [incomplete, complete])
	verif.v(total.is_equal_approx(Vector3(1.0, 2.0, 0.0)), "une source incomplete (rayon absent) doit etre ignoree seule, la source complete doit quand meme contribuer, recu %s" % total)

# ---- Garde structurelle ----

func _catalogue_sans_entree_defaut_alarme_et_rend_un_repli_neutre() -> void:
	var v := Vent.vecteur(Vector3.ZERO, 0.0, {})
	verif.v(v == Vector3.ZERO, "catalogue sans entree 'defaut' : vecteur() doit alarmer et rendre Vector3.ZERO")
	var f := Vent.facteur_directionnel(Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), {})
	verif.v(f == 1.0, "catalogue sans entree 'defaut' : facteur_directionnel() doit alarmer et rendre 1.0, jamais un facteur invente")

# ---- facteur_directionnel ----

func _facteur_directionnel_formule_exacte_dans_les_trois_directions() -> void:
	var catalogue := {"defaut": {"directionnel": {"reference_force": 10.0, "facteur_max_sous_vent": 2.0, "facteur_min_contre_vent": 0.5}}}
	var vent_vecteur := Vector3(1.0, 0.0, 0.0) * 10.0  # force = reference_force : intensite pleine (1.0)

	var f_aligne := Vent.facteur_directionnel(vent_vecteur, Vector3(1.0, 0.0, 0.0), catalogue)
	verif.v(is_equal_approx(f_aligne, 2.0), "cible exactement dans le sens du vent (dot=1) : facteur attendu exactement facteur_max_sous_vent (2.0), recu %f" % f_aligne)

	var f_oppose := Vent.facteur_directionnel(vent_vecteur, Vector3(-1.0, 0.0, 0.0), catalogue)
	verif.v(is_equal_approx(f_oppose, 0.5), "cible exactement a l'oppose du vent (dot=-1) : facteur attendu exactement facteur_min_contre_vent (0.5), recu %f" % f_oppose)

	var f_perp := Vent.facteur_directionnel(vent_vecteur, Vector3(0.0, 1.0, 0.0), catalogue)
	verif.v(is_equal_approx(f_perp, 1.0), "cible perpendiculaire au vent (dot=0) : facteur attendu EXACTEMENT 1.0, quelles que soient facteur_max/facteur_min, recu %f" % f_perp)

	# meme test avec des facteurs tres asymetriques : le perpendiculaire doit rester 1.0.
	var catalogue_asymetrique := {"defaut": {"directionnel": {"reference_force": 10.0, "facteur_max_sous_vent": 5.0, "facteur_min_contre_vent": 0.1}}}
	var f_perp_asymetrique := Vent.facteur_directionnel(vent_vecteur, Vector3(0.0, -1.0, 0.0), catalogue_asymetrique)
	verif.v(is_equal_approx(f_perp_asymetrique, 1.0), "perpendiculaire reste 1.0 meme avec des facteurs tres asymetriques (5.0 / 0.1), recu %f" % f_perp_asymetrique)

func _facteur_directionnel_est_neutre_a_vent_nul_ou_direction_nulle() -> void:
	var catalogue := {"defaut": {"directionnel": {"reference_force": 10.0, "facteur_max_sous_vent": 3.0, "facteur_min_contre_vent": 0.2}}}
	var f_vent_nul := Vent.facteur_directionnel(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), catalogue)
	verif.v(f_vent_nul == 1.0, "vent nul (Vector3.ZERO) : facteur doit rester exactement 1.0 quel que soit l'angle")
	var f_direction_nulle := Vent.facteur_directionnel(Vector3(5.0, 0.0, 0.0), Vector3.ZERO, catalogue)
	verif.v(f_direction_nulle == 1.0, "direction cible nulle (distance 0 a la chose) : facteur neutre, jamais une division degeneree")

func _facteur_directionnel_neutre_sans_reference_force_ou_sans_directionnel() -> void:
	var sans_directionnel := {"defaut": {}}
	var f1 := Vent.facteur_directionnel(Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), sans_directionnel)
	verif.v(f1 == 1.0, "'directionnel' absent de l'entree 'defaut' : alarme et repli neutre 1.0")

	var reference_nulle := {"defaut": {"directionnel": {"reference_force": 0.0, "facteur_max_sous_vent": 5.0, "facteur_min_contre_vent": 0.1}}}
	var f2 := Vent.facteur_directionnel(Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), reference_nulle)
	verif.v(f2 == 1.0, "reference_force a 0.0 : aucun effet directionnel possible, repli neutre 1.0 (jamais une division par zero)")

func _intensite_du_vent_module_lamplitude_de_leffet_directionnel() -> void:
	var catalogue := {"defaut": {"directionnel": {"reference_force": 10.0, "facteur_max_sous_vent": 2.0, "facteur_min_contre_vent": 0.5}}}
	var vent_faible := Vector3(1.0, 0.0, 0.0) * 5.0  # moitie de reference_force : intensite 0.5
	var f := Vent.facteur_directionnel(vent_faible, Vector3(1.0, 0.0, 0.0), catalogue)
	# facteur_angle plein = 2.0, intensite 0.5 => lerp(1.0, 2.0, 0.5) = 1.5
	verif.v(is_equal_approx(f, 1.5), "un vent a moitie de reference_force ne doit produire que la MOITIE de l'effet directionnel plein (1.5, pas 2.0), recu %f" % f)

	var vent_fort := Vector3(1.0, 0.0, 0.0) * 100.0  # tres au-dela de reference_force : intensite plafonnee a 1.0
	var f_fort := Vent.facteur_directionnel(vent_fort, Vector3(1.0, 0.0, 0.0), catalogue)
	verif.v(is_equal_approx(f_fort, 2.0), "un vent tres au-dela de reference_force reste plafonne au facteur plein (2.0), jamais une extrapolation sans borne, recu %f" % f_fort)

# ---- Hors domaine ----

# Aucune chaine "vent"/"odeur"/"colon" n'apparait dans scripts/vent.gd -- ce
# cas verifie que le meme code agrege n'importe quel Vector3 continu, sans
# rapport avec un phenomene meteorologique : un capteur immobile lit un
# "flux" ambiant plus une source ponctuelle, exactement le meme geste que les
# tests ci-dessus, avec un vocabulaire qui n'a rien a voir.
func _hors_domaine_le_mecanisme_ignore_le_domaine() -> void:
	var catalogue_flux := {
		"defaut": {
			"fond": {"direction": {"x": 0.0, "y": 1.0, "z": 0.0}, "force": 2.0},
			"directionnel": {"reference_force": 4.0, "facteur_max_sous_vent": 3.0, "facteur_min_contre_vent": 0.3},
		}
	}
	var emetteur := {"position": Vector3(100.0, 100.0, 0.0), "rayon": 5.0, "vecteur": Vector3(1.0, 1.0, 0.0)}
	var loin_de_lemetteur := Vent.vecteur(Vector3.ZERO, 0.0, catalogue_flux, [emetteur])
	verif.v(loin_de_lemetteur.is_equal_approx(Vector3(0.0, 2.0, 0.0)), "hors domaine : loin de l'emetteur ponctuel, seul le flux de fond doit rester")
	var f := Vent.facteur_directionnel(loin_de_lemetteur, Vector3(0.0, 1.0, 0.0), catalogue_flux)
	verif.v(f > 1.0, "hors domaine : une cible alignee avec le flux doit recevoir un facteur > 1.0, meme mecanisme que le vent")

# ---- Chemin reel ----

func _catalogue_vent_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/vent.json"))

func _chemin_reel_data_vent_json() -> void:
	var catalogue := _catalogue_vent_reel()
	verif.v(catalogue.has("defaut"), "data/vent.json doit porter une entree 'defaut'")
	var v := Vent.vecteur(Vector3.ZERO, 0.0, catalogue)
	verif.v(v.length() > 0.0, "le vent reel a t=0 doit avoir une force strictement positive avec les valeurs de depart du depot")
	var v_ailleurs := Vent.vecteur(Vector3.ZERO, 12.3, catalogue)
	verif.v(not v.is_equal_approx(v_ailleurs), "le vent reel doit varier entre deux instants distincts (variation lente et/ou rafales actives par defaut)")

	var direction_vent := v.normalized()
	var f_aval := Vent.facteur_directionnel(v, direction_vent, catalogue)
	var f_amont := Vent.facteur_directionnel(v, -direction_vent, catalogue)
	verif.v(f_aval > 1.0, "avec les valeurs reelles, une cible exactement dans le sens du vent doit recevoir un facteur de portee strictement superieur a 1.0")
	verif.v(f_amont < 1.0, "avec les valeurs reelles, une cible exactement a l'oppose du vent doit recevoir un facteur de portee strictement inferieur a 1.0")
