extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_temperature.gd
#
# Verrouille scripts/temperature.gd (chantier "temperature", mecanisme de
# base seul) : la temperature locale comme somme d'ecarts de sources
# attenues par distance (meme patron que vent.gd), la loi de Newton pour
# l'avancement d'un objet (dT = (conductivite / chaleur_specifique) *
# (T_locale - T_objet) * delta -- vite d'abord, puis de plus en plus
# lentement, PROPRIETE DE LA FORMULE), les gardes structurelles -- plus un
# cas hors domaine et un chemin reel sur data/temperature.json.
#
# Verrouille aussi l'INERTIE THERMIQUE (chantier "colonne thermique",
# chaleur_specifique) : absente ou nulle, comportement identique a avant
# (repli sur 1.0) ; a conductivite egale, une chaleur_specifique plus
# haute (pierre, 790.0) ralentit STRICTEMENT le changement de temperature
# par rapport a une plus basse (fer, 450.0) -- plus un chemin reel qui
# fabrique un objet via Objet.fabriquer/data/types.json/data/
# materiaux.json/data/proprietes_immuables_composition.json et verifie que
# conductivite_thermique/chaleur_specifique apparaissent SANS que ce test
# ne les pose a la main.
#
# Verrouille enfin la DILATATION THERMIQUE (chantier "colonne thermique",
# case 5, DERNIERE case du tableau Thermique) : absente ou nulle, aucun
# changement de volume ni de densite (rien invente sur l'objet) ; positive,
# le volume augmente en chauffant et diminue en refroidissant exactement de
# dilatation_thermique*dT (le dT de CE pas, pas un ecart total), la masse ne
# change jamais, la densite reste EXACTEMENT masse/volume a chaque pas ; un
# volume qui tombe a zero ou en dessous (donnee extreme) ne divise jamais
# par zero -- plus un chemin reel qui fabrique un objet et verifie que
# dilatation_thermique apparait SANS etre posee a la main.

const Objet = preload("res://scripts/objet.gd")
const Temperature = preload("res://scripts/temperature.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_locale_est_la_somme_des_sources_a_portee_attenuees_par_distance()
	_hors_du_rayon_dune_source_sa_contribution_est_nulle()
	_deux_sources_qui_se_superposent_sadditionnent_jamais_une_moyenne()
	_source_incomplete_alarme_et_est_ignoree_sans_bloquer_les_autres()
	_catalogue_sans_entree_defaut_alarme_et_rend_un_repli_neutre()
	_source_deplacee_change_ce_que_lit_un_objet_fixe()

	_avancer_rejoint_la_cible_dautant_plus_vite_que_lecart_est_grand()
	_avancer_ralentit_au_fil_des_pas_a_mesure_que_lecart_se_reduit()
	_objet_loin_de_toute_source_retombe_vers_lambiante()
	_avancer_sans_propriete_temperature_alarme_et_ignore_sans_bloquer_les_autres()
	_avancer_sans_conductivite_reste_thermiquement_inerte()

	_chaleur_specifique_absente_se_comporte_comme_avant()
	_chaleur_specifique_nulle_se_comporte_comme_absente_jamais_une_division_par_zero()
	_chaleur_specifique_plus_haute_ralentit_a_conductivite_egale()

	_dilatation_absente_aucun_changement_de_volume_ni_de_densite()
	_dilatation_nulle_aucun_changement_de_volume_ni_de_densite()
	_dilatation_positive_le_volume_augmente_en_chauffant()
	_dilatation_positive_le_volume_diminue_en_refroidissant()
	_dilatation_ne_touche_jamais_la_masse()
	_dilatation_densite_toujours_recalculee_depuis_masse_et_volume()
	_dilatation_volume_non_positif_ne_divise_jamais_par_zero()

	_hors_domaine_le_mecanisme_ignore_le_domaine()
	_chemin_reel_data_temperature_json()
	_chemin_reel_fabrication_fusionne_conductivite_et_chaleur_specifique()
	_chemin_reel_fabrication_fusionne_dilatation_thermique()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: temperature locale = somme des ecarts de sources attenues par " +
		"distance, superposition additive jamais une moyenne, gardes " +
		"structurelles, loi de Newton verifiee (vitesse proportionnelle a " +
		"l'ecart, ralentissement au fil des pas), retombee vers l'ambiante " +
		"hors de toute source, chaleur_specifique ralentit a conductivite " +
		"egale (defaut 1.0 si absente ou nulle, comportement inchange), " +
		"dilatation thermique fait varier volume/densite a masse constante " +
		"(absente ou nulle : comportement inchange), hors domaine, chemin " +
		"reel data/temperature.json et fabrication reelle (data/types.json/" +
		"data/materiaux.json/data/proprietes_immuables_composition.json)")
	quit(0)

# ---- locale() ----

func _locale_est_la_somme_des_sources_a_portee_attenuees_par_distance() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3(10.0, 0.0, 0.0), "rayon": 10.0, "temperature": 100.0, "force": 1.0}

	var au_centre := Temperature.locale(Vector3(10.0, 0.0, 0.0), [source], catalogue)
	verif.v(is_equal_approx(au_centre, 100.0), "au centre de la source (distance 0, attenuation lineaire pleine) : locale attendue exactement 100.0, recu %f" % au_centre)

	var a_mi_rayon := Temperature.locale(Vector3(15.0, 0.0, 0.0), [source], catalogue)
	verif.v(is_equal_approx(a_mi_rayon, 60.0), "a mi-rayon (distance 5 sur rayon 10, attenuation 0.5) : locale attendue 20 + (100-20)*0.5 = 60.0, recu %f" % a_mi_rayon)

	var catalogue_quadratique := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 2.0}}}
	var a_mi_rayon_quadratique := Temperature.locale(Vector3(15.0, 0.0, 0.0), [source], catalogue_quadratique)
	verif.v(is_equal_approx(a_mi_rayon_quadratique, 40.0), "meme mi-rayon avec un exposant 2.0 (forme d'attenuation en donnee) : locale attendue 20 + (100-20)*0.25 = 40.0, recu %f" % a_mi_rayon_quadratique)

func _hors_du_rayon_dune_source_sa_contribution_est_nulle() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 500.0, "force": 1.0}
	var loin := Temperature.locale(Vector3(50.0, 0.0, 0.0), [source], catalogue)
	verif.v(is_equal_approx(loin, 20.0), "hors du rayon de la source, seule l'ambiante doit rester, recu %f" % loin)

func _deux_sources_qui_se_superposent_sadditionnent_jamais_une_moyenne() -> void:
	var catalogue := {"defaut": {"ambiante": 0.0, "attenuation": {"exposant": 1.0}}}
	var source_a := {"position": Vector3.ZERO, "rayon": 20.0, "temperature": 40.0, "force": 1.0}
	var source_b := {"position": Vector3.ZERO, "rayon": 20.0, "temperature": 60.0, "force": 1.0}
	var au_meme_point := Temperature.locale(Vector3.ZERO, [source_a, source_b], catalogue)
	verif.v(is_equal_approx(au_meme_point, 100.0), "deux sources qui se recouvrent exactement doivent ADDITIONNER leurs ecarts (40+60=100), jamais une moyenne (qui rendrait 50), recu %f" % au_meme_point)

func _source_incomplete_alarme_et_est_ignoree_sans_bloquer_les_autres() -> void:
	var catalogue := {"defaut": {"ambiante": 0.0, "attenuation": {"exposant": 1.0}}}
	var incomplete := {"position": Vector3.ZERO, "temperature": 900.0, "force": 1.0}  # "rayon" manquant
	var complete := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 30.0, "force": 1.0}
	var total := Temperature.locale(Vector3.ZERO, [incomplete, complete], catalogue)
	verif.v(is_equal_approx(total, 30.0), "une source incomplete (rayon absent) doit etre ignoree seule, la source complete doit quand meme contribuer, recu %f" % total)

func _catalogue_sans_entree_defaut_alarme_et_rend_un_repli_neutre() -> void:
	var v := Temperature.locale(Vector3.ZERO, [], {})
	verif.v(v == 0.0, "catalogue sans entree 'defaut' : locale() doit alarmer et rendre 0.0")

	var monde := [{"id": "x", "position": Vector3.ZERO, "proprietes": {"temperature": 50.0, "conductivite_thermique": 1.0}}]
	Temperature.avancer(monde, [], 1.0, {})
	verif.v(is_equal_approx(monde[0].proprietes.temperature, 50.0), "catalogue sans entree 'defaut' : avancer() doit alarmer et ne rien muter")

func _source_deplacee_change_ce_que_lit_un_objet_fixe() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3(50.0, 0.0, 0.0), "rayon": 10.0, "temperature": 200.0, "force": 1.0}
	var point_fixe := Vector3.ZERO

	var avant := Temperature.locale(point_fixe, [source], catalogue)
	verif.v(is_equal_approx(avant, 20.0), "source hors de portee du point fixe : locale attendue 20.0 (ambiante seule), recu %f" % avant)

	source.position = Vector3.ZERO  # l'appelant deplace la source lui-meme
	var apres := Temperature.locale(point_fixe, [source], catalogue)
	verif.v(is_equal_approx(apres, 200.0), "meme source deplacee au centre du point fixe : locale attendue 200.0, recu %f -- le mecanisme ne possede ni ne cache jamais une source" % apres)

# ---- avancer() : loi de Newton ----

func _avancer_rejoint_la_cible_dautant_plus_vite_que_lecart_est_grand() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 100.0, "force": 1.0}
	# locale() au centre = 100.0 pour les deux objets, meme conductivite, meme delta -- seul l'ecart initial differe.
	var froid := {"id": "froid", "position": Vector3.ZERO, "proprietes": {"temperature": 20.0, "conductivite_thermique": 0.5}}
	var tiede := {"id": "tiede", "position": Vector3.ZERO, "proprietes": {"temperature": 80.0, "conductivite_thermique": 0.5}}
	var monde := [froid, tiede]
	Temperature.avancer(monde, [source], 1.0, catalogue)
	var dT_froid: float = froid.proprietes.temperature - 20.0
	var dT_tiede: float = tiede.proprietes.temperature - 80.0
	verif.v(dT_froid > 0.0 and dT_tiede > 0.0, "les deux objets doivent se rechauffer vers la cible commune (100.0)")
	verif.v(dT_froid > dT_tiede, "l'objet au plus grand ecart initial (froid, ecart 80) doit avancer STRICTEMENT plus vite que celui au petit ecart (tiede, ecart 20) sur le meme pas, recu dT_froid=%f dT_tiede=%f" % [dT_froid, dT_tiede])
	verif.v(is_equal_approx(froid.proprietes.temperature, 60.0), "formule exacte : 20 + 0.5*(100-20)*1.0 = 60.0, recu %f" % froid.proprietes.temperature)
	verif.v(is_equal_approx(tiede.proprietes.temperature, 90.0), "formule exacte : 80 + 0.5*(100-80)*1.0 = 90.0, recu %f" % tiede.proprietes.temperature)

func _avancer_ralentit_au_fil_des_pas_a_mesure_que_lecart_se_reduit() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 100.0, "force": 1.0}
	var objet := {"id": "x", "position": Vector3.ZERO, "proprietes": {"temperature": 20.0, "conductivite_thermique": 0.5}}
	var monde := [objet]
	var t0: float = objet.proprietes.temperature
	Temperature.avancer(monde, [source], 0.05, catalogue)
	var t1: float = objet.proprietes.temperature
	Temperature.avancer(monde, [source], 0.05, catalogue)
	var t2: float = objet.proprietes.temperature
	Temperature.avancer(monde, [source], 0.05, catalogue)
	var t3: float = objet.proprietes.temperature
	var pas1: float = t1 - t0
	var pas2: float = t2 - t1
	var pas3: float = t3 - t2
	verif.v(pas1 > 0.0 and pas2 > 0.0 and pas3 > 0.0, "chaque pas doit rapprocher l'objet de la cible (temperature strictement croissante)")
	verif.v(pas1 > pas2 and pas2 > pas3, "REFROIDISSEMENT/RECHAUFFEMENT VITE D'ABORD PUIS DE PLUS EN PLUS LENTEMENT -- chaque increment doit etre STRICTEMENT plus petit que le precedent, jamais une valeur ecrite a la main : pas1=%f pas2=%f pas3=%f" % [pas1, pas2, pas3])

func _objet_loin_de_toute_source_retombe_vers_lambiante() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var objet := {"id": "chaud", "position": Vector3(9999.0, 0.0, 0.0), "proprietes": {"temperature": 200.0, "conductivite_thermique": 0.3}}
	var monde := [objet]
	var precedent: float = 200.0
	for i in 4:
		Temperature.avancer(monde, [], 0.1, catalogue)
		var courant: float = objet.proprietes.temperature
		verif.v(courant < precedent, "sans aucune source, chaque pas doit refroidir l'objet un peu plus vers l'ambiante (pas %d) : precedent=%f courant=%f" % [i, precedent, courant])
		verif.v(courant >= 20.0, "l'objet ne doit jamais franchir l'ambiante par le bas (pas %d), recu %f" % [i, courant])
		precedent = courant
	verif.v(precedent < 200.0 and precedent > 20.0, "apres plusieurs pas sans source, l'objet doit s'etre rapproche de l'ambiante sans encore l'atteindre exactement, recu %f" % precedent)

func _avancer_sans_propriete_temperature_alarme_et_ignore_sans_bloquer_les_autres() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 100.0, "force": 1.0}
	var sans_temperature := {"id": "pas_physique", "position": Vector3.ZERO, "proprietes": {"conductivite_thermique": 1.0}}
	var avec_temperature := {"id": "physique", "position": Vector3.ZERO, "proprietes": {"temperature": 20.0, "conductivite_thermique": 1.0}}
	var monde := [sans_temperature, avec_temperature]
	Temperature.avancer(monde, [source], 1.0, catalogue)
	verif.v(not sans_temperature.proprietes.has("temperature"), "une chose structurellement sans 'temperature' (pas objet_physique) ne doit jamais en recevoir une par ce mecanisme")
	verif.v(is_equal_approx(avec_temperature.proprietes.temperature, 100.0), "l'autre objet, physique, doit quand meme avancer normalement malgre le voisin structurellement invalide, recu %f" % avec_temperature.proprietes.temperature)

func _avancer_sans_conductivite_reste_thermiquement_inerte() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 999.0, "force": 1.0}
	var objet := {"id": "inerte", "position": Vector3.ZERO, "proprietes": {"temperature": 42.0}}  # conductivite_thermique absente
	var monde := [objet]
	Temperature.avancer(monde, [source], 5.0, catalogue)
	verif.v(is_equal_approx(objet.proprietes.temperature, 42.0), "sans 'conductivite_thermique' (defaut 0.0, objet sans composition ou materiau sans cette fiche), la temperature ne doit JAMAIS bouger, meme pres d'une source tres chaude et sur un grand pas de temps, recu %f" % objet.proprietes.temperature)

# ---- Inertie thermique (chaleur_specifique) ----

func _chaleur_specifique_absente_se_comporte_comme_avant() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 100.0, "force": 1.0}
	var sans_cle := {"id": "sans_cle", "position": Vector3.ZERO, "proprietes": {"temperature": 20.0, "conductivite_thermique": 0.5}}
	var avec_un := {"id": "avec_un", "position": Vector3.ZERO, "proprietes": {"temperature": 20.0, "conductivite_thermique": 0.5, "chaleur_specifique": 1.0}}
	var monde := [sans_cle, avec_un]
	Temperature.avancer(monde, [source], 1.0, catalogue)
	verif.v(is_equal_approx(sans_cle.proprietes.temperature, 60.0), "sans 'chaleur_specifique', formule inchangee : 20 + 0.5*(100-20)*1.0 = 60.0, recu %f" % sans_cle.proprietes.temperature)
	verif.v(is_equal_approx(sans_cle.proprietes.temperature, avec_un.proprietes.temperature), "absente ou explicitement 1.0, chaleur_specifique doit produire EXACTEMENT le meme resultat -- le defaut est 1.0, pas un cas particulier")

func _chaleur_specifique_nulle_se_comporte_comme_absente_jamais_une_division_par_zero() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 100.0, "force": 1.0}
	var nulle := {"id": "nulle", "position": Vector3.ZERO, "proprietes": {"temperature": 20.0, "conductivite_thermique": 0.5, "chaleur_specifique": 0.0}}
	var negative := {"id": "negative", "position": Vector3.ZERO, "proprietes": {"temperature": 20.0, "conductivite_thermique": 0.5, "chaleur_specifique": -3.0}}
	var monde := [nulle, negative]
	Temperature.avancer(monde, [source], 1.0, catalogue)
	verif.v(is_equal_approx(nulle.proprietes.temperature, 60.0), "chaleur_specifique a 0.0 doit etre traitee comme absente (repli sur 1.0), jamais une division par zero -- recu %f" % nulle.proprietes.temperature)
	verif.v(is_equal_approx(negative.proprietes.temperature, 60.0), "chaleur_specifique negative (donnee incoherente) doit aussi replier sur 1.0, recu %f" % negative.proprietes.temperature)

# A CONDUCTIVITE EGALE, seule variable la chaleur_specifique -- valeurs
# reelles de data/materiaux.json (pierre 790.0, fer 450.0), verifie le
# COMPORTEMENT demande par le chantier "colonne thermique" : une matiere
# qui emmagasine plus d'energie par degre change de temperature plus
# LENTEMENT sur le meme pas, la meme cible, le meme ecart initial.
func _chaleur_specifique_plus_haute_ralentit_a_conductivite_egale() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 220.0, "force": 1.0}
	var pierre := {"id": "pierre", "position": Vector3.ZERO, "proprietes": {"temperature": 20.0, "conductivite_thermique": 1.0, "chaleur_specifique": 790.0}}
	var fer := {"id": "fer", "position": Vector3.ZERO, "proprietes": {"temperature": 20.0, "conductivite_thermique": 1.0, "chaleur_specifique": 450.0}}
	var monde := [pierre, fer]
	Temperature.avancer(monde, [source], 1.0, catalogue)
	var dT_pierre: float = pierre.proprietes.temperature - 20.0
	var dT_fer: float = fer.proprietes.temperature - 20.0
	verif.v(dT_pierre > 0.0 and dT_fer > 0.0, "les deux doivent se rechauffer vers la meme cible (220.0)")
	verif.v(dT_fer > dT_pierre, "a conductivite egale, la chaleur_specifique plus BASSE (fer, 450) doit changer de temperature STRICTEMENT plus vite que la plus HAUTE (pierre, 790), recu dT_pierre=%f dT_fer=%f" % [dT_pierre, dT_fer])
	verif.v(is_equal_approx(pierre.proprietes.temperature, 20.0 + (1.0 / 790.0) * 200.0), "formule exacte pour pierre : 20 + (1.0/790.0)*(220-20)*1.0, recu %f" % pierre.proprietes.temperature)
	verif.v(is_equal_approx(fer.proprietes.temperature, 20.0 + (1.0 / 450.0) * 200.0), "formule exacte pour fer : 20 + (1.0/450.0)*(220-20)*1.0, recu %f" % fer.proprietes.temperature)

# ---- Dilatation thermique (colonne thermique, case 5, DERNIERE case) ----

func _dilatation_absente_aucun_changement_de_volume_ni_de_densite() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 100.0, "force": 1.0}
	var objet := {"id": "sans_dilatation", "position": Vector3.ZERO, "proprietes": {"temperature": 20.0, "conductivite_thermique": 0.5}}
	var monde := [objet]
	Temperature.avancer(monde, [source], 1.0, catalogue)
	verif.v(is_equal_approx(objet.proprietes.temperature, 60.0), "la temperature doit quand meme avancer normalement, recu %f" % objet.proprietes.temperature)
	verif.v(not objet.proprietes.has("volume"), "sans 'dilatation_thermique' (defaut 0.0), 'volume' ne doit JAMAIS etre invente sur l'objet")
	verif.v(not objet.proprietes.has("densite"), "sans 'dilatation_thermique', 'densite' ne doit JAMAIS etre invente sur l'objet")

func _dilatation_nulle_aucun_changement_de_volume_ni_de_densite() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 100.0, "force": 1.0}
	var objet := {"id": "dilatation_nulle", "position": Vector3.ZERO, "proprietes": {"temperature": 20.0, "conductivite_thermique": 0.5, "dilatation_thermique": 0.0, "volume": 10.0, "masse": 5000.0, "densite": 500.0}}
	var monde := [objet]
	Temperature.avancer(monde, [source], 1.0, catalogue)
	verif.v(is_equal_approx(objet.proprietes.volume, 10.0), "dilatation_thermique explicitement 0.0 : volume inchange, recu %f" % objet.proprietes.volume)
	verif.v(is_equal_approx(objet.proprietes.densite, 500.0), "dilatation_thermique explicitement 0.0 : densite inchangee, recu %f" % objet.proprietes.densite)

func _dilatation_positive_le_volume_augmente_en_chauffant() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 100.0, "force": 1.0}
	var objet := {"id": "chauffe", "position": Vector3.ZERO, "proprietes": {"temperature": 20.0, "conductivite_thermique": 0.5, "dilatation_thermique": 2.0, "volume": 500.0, "masse": 5000.0}}
	var monde := [objet]
	Temperature.avancer(monde, [source], 1.0, catalogue)
	# dT = 0.5*(100-20)*1.0 = 40.0 -> dV = 2.0*40.0 = 80.0 -> volume 580.0
	verif.v(is_equal_approx(objet.proprietes.temperature, 60.0), "temperature attendue 60.0, recu %f" % objet.proprietes.temperature)
	verif.v(is_equal_approx(objet.proprietes.volume, 580.0), "en chauffant (dT=40.0), le volume doit AUGMENTER exactement de dilatation_thermique*dT=80.0 -> 580.0, recu %f" % objet.proprietes.volume)
	verif.v(is_equal_approx(objet.proprietes.densite, 5000.0 / 580.0), "densite recalculee EXACTEMENT masse/volume, recu %f" % objet.proprietes.densite)

func _dilatation_positive_le_volume_diminue_en_refroidissant() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 150.0, "force": 1.0}
	var objet := {"id": "refroidi", "position": Vector3.ZERO, "proprietes": {"temperature": 200.0, "conductivite_thermique": 0.5, "dilatation_thermique": 2.0, "volume": 500.0, "masse": 5000.0}}
	var monde := [objet]
	Temperature.avancer(monde, [source], 1.0, catalogue)
	# dT = 0.5*(150-200)*1.0 = -25.0 -> dV = 2.0*-25.0 = -50.0 -> volume 450.0
	verif.v(is_equal_approx(objet.proprietes.temperature, 175.0), "temperature attendue 175.0, recu %f" % objet.proprietes.temperature)
	verif.v(is_equal_approx(objet.proprietes.volume, 450.0), "en refroidissant (dT=-25.0), le volume doit DIMINUER exactement de |dilatation_thermique*dT|=50.0 -> 450.0, recu %f" % objet.proprietes.volume)
	verif.v(objet.proprietes.densite > 10.0, "un volume plus petit a masse constante doit rendre une densite STRICTEMENT plus haute que la densite d'origine (10.0), recu %f" % objet.proprietes.densite)

func _dilatation_ne_touche_jamais_la_masse() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 500.0, "force": 1.0}
	var objet := {"id": "masse_fixe", "position": Vector3.ZERO, "proprietes": {"temperature": 20.0, "conductivite_thermique": 0.8, "dilatation_thermique": 5.0, "volume": 10.0, "masse": 1000.0}}
	var monde := [objet]
	for i in 5:
		Temperature.avancer(monde, [source], 0.2, catalogue)
	verif.v(is_equal_approx(objet.proprietes.masse, 1000.0), "la masse ne doit JAMAIS changer sous l'effet de la dilatation thermique, meme apres plusieurs pas, recu %f" % objet.proprietes.masse)

func _dilatation_densite_toujours_recalculee_depuis_masse_et_volume() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var source := {"position": Vector3.ZERO, "rayon": 10.0, "temperature": 300.0, "force": 1.0}
	var objet := {"id": "coherent", "position": Vector3.ZERO, "proprietes": {"temperature": 20.0, "conductivite_thermique": 0.3, "dilatation_thermique": 1.5, "volume": 20.0, "masse": 400.0}}
	var monde := [objet]
	for i in 3:
		Temperature.avancer(monde, [source], 0.3, catalogue)
		verif.v(is_equal_approx(objet.proprietes.densite, objet.proprietes.masse / objet.proprietes.volume), "a chaque pas, densite doit rester EXACTEMENT masse/volume, jamais reposee independamment (pas %d)" % i)

func _dilatation_volume_non_positif_ne_divise_jamais_par_zero() -> void:
	var catalogue := {"defaut": {"ambiante": 20.0, "attenuation": {"exposant": 1.0}}}
	var objet := {"id": "extreme", "position": Vector3(9999.0, 0.0, 0.0), "proprietes": {"temperature": 1000.0, "conductivite_thermique": 1.0, "dilatation_thermique": 50.0, "volume": 1.0, "masse": 1000.0, "densite": 1000.0}}
	var monde := [objet]
	# Sans source, locale = ambiante 20.0 -> dT = 1.0*(20-1000)*1.0 = -980.0 -> dV = 50.0*-980.0 = -49000.0, volume devient negatif.
	Temperature.avancer(monde, [], 1.0, catalogue)
	verif.v(objet.proprietes.volume <= 0.0, "constat du scenario : le volume doit bien etre devenu non positif avec ces valeurs extremes, recu %f" % objet.proprietes.volume)
	verif.v(is_equal_approx(objet.proprietes.densite, 1000.0), "volume non positif : la densite ne doit JAMAIS etre recalculee (division par zero ou negatif), elle garde sa derniere valeur valide, recu %f" % objet.proprietes.densite)
	verif.v(not is_nan(objet.proprietes.densite) and not is_inf(objet.proprietes.densite), "la densite ne doit jamais devenir NaN ni infinie")

# ---- Hors domaine ----

# Aucune chaine "temperature"/"feu"/"chaleur"/"colon" n'apparait dans le
# RAISONNEMENT de scripts/temperature.gd -- seul le nom des cles est fixe
# par le contrat (position/rayon/temperature/force), le mecanisme lui-meme
# ne sait pas que "temperature" designe une chaleur : ce cas fait porter la
# meme cle un scalaire de nature totalement differente (une pression
# atmospherique locale) et verifie que le meme code produit le meme calcul.
func _hors_domaine_le_mecanisme_ignore_le_domaine() -> void:
	var catalogue_pression := {"defaut": {"ambiante": 1013.0, "attenuation": {"exposant": 1.0}}}
	var depression := {"position": Vector3.ZERO, "rayon": 100.0, "temperature": 950.0, "force": 1.0}
	var au_centre := Temperature.locale(Vector3.ZERO, [depression], catalogue_pression)
	verif.v(is_equal_approx(au_centre, 950.0), "hors domaine (pression atmospherique, rien a voir avec la chaleur) : au centre d'une depression, locale doit exactement egaler sa valeur propre, recu %f" % au_centre)

	var station := {"id": "station_meteo", "position": Vector3.ZERO, "proprietes": {"temperature": 1013.0, "conductivite_thermique": 0.2}}
	var monde := [station]
	Temperature.avancer(monde, [depression], 1.0, catalogue_pression)
	verif.v(station.proprietes.temperature < 1013.0, "hors domaine : la meme loi de Newton doit faire baisser la 'temperature' (ici une pression) vers la depression, recu %f" % station.proprietes.temperature)

# ---- Chemin reel ----

func _catalogue_temperature_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/temperature.json"))

func _chemin_reel_data_temperature_json() -> void:
	var catalogue := _catalogue_temperature_reel()
	verif.v(catalogue.has("defaut"), "data/temperature.json doit porter une entree 'defaut'")
	var ambiante_reelle: float = catalogue.defaut.get("ambiante", -9999.0)
	verif.v(is_equal_approx(ambiante_reelle, 20.0), "l'ambiante reelle doit correspondre au defaut du paquet objet_physique (20.0), recu %f" % ambiante_reelle)

	var sans_source := Temperature.locale(Vector3.ZERO, [], catalogue)
	verif.v(is_equal_approx(sans_source, ambiante_reelle), "sans aucune source, la locale reelle doit exactement egaler l'ambiante reelle")

	var source_reelle := {"position": Vector3.ZERO, "rayon": 50.0, "temperature": 400.0, "force": 1.0}
	var pres := Temperature.locale(Vector3.ZERO, [source_reelle], catalogue)
	verif.v(pres > ambiante_reelle, "chemin reel : au centre d'une source chaude reelle, la locale doit depasser l'ambiante")

# Chantier "colonne thermique" : fabrique "bloc" (data/types.json, composition
# pierre) via Objet.fabriquer, catalogue de fusion REEL (data/
# proprietes_immuables_composition.json), materiaux REELS (data/
# materiaux.json) -- PERSONNE ne pose conductivite_thermique/
# chaleur_specifique a la main dans ce test, c'est la fabrication normale
# qui doit les faire apparaitre. Verifie ensuite que Temperature.avancer
# les lit reellement sur cet objet fabrique (pas seulement sur un
# Dictionary construit a la main comme les tests ci-dessus).
func _chemin_reel_fabrication_fusionne_conductivite_et_chaleur_specifique() -> void:
	var types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(proprietes_immuables.has("conductivite_thermique"), "data/proprietes_immuables_composition.json doit lister conductivite_thermique")
	verif.v(proprietes_immuables.has("chaleur_specifique"), "data/proprietes_immuables_composition.json doit lister chaleur_specifique")

	var bloc := Objet.fabriquer("bloc_reel", "bloc", Vector3.ZERO, types, materiaux, proprietes_immuables)
	verif.v(not bloc.is_empty(), "chemin reel : 'bloc' (composition pierre) doit se fabriquer normalement")
	verif.v(is_equal_approx(bloc.proprietes.get("conductivite_thermique", -1.0), materiaux.pierre.conductivite_thermique), "chemin reel : conductivite_thermique doit apparaitre sur l'objet fabrique, EGALE a la fiche pierre (%f), sans que ce test ne la pose a la main" % materiaux.pierre.conductivite_thermique)
	verif.v(is_equal_approx(bloc.proprietes.get("chaleur_specifique", -1.0), materiaux.pierre.chaleur_specifique), "chemin reel : chaleur_specifique doit apparaitre sur l'objet fabrique, EGALE a la fiche pierre (%f), sans que ce test ne la pose a la main" % materiaux.pierre.chaleur_specifique)

	var catalogue := _catalogue_temperature_reel()
	var source_chaude := {"position": Vector3.ZERO, "rayon": 100.0, "temperature": 500.0, "force": 1.0}
	var monde := [bloc]
	var temperature_initiale: float = bloc.proprietes.temperature
	Temperature.avancer(monde, [source_chaude], 1.0, catalogue)
	verif.v(bloc.proprietes.temperature > temperature_initiale, "chemin reel : l'objet fabrique doit reellement se rechauffer -- Temperature.avancer lit bien la conductivite/chaleur_specifique FUSIONNEES, jamais posees a la main")

# Chantier "colonne thermique", case 5 (DERNIERE case) : meme discipline que
# le test ci-dessus, mais pour dilatation_thermique -- fabrique "bloc"
# (composition pierre) et verifie que dilatation_thermique apparait sur
# l'objet fabrique SANS etre posee a la main, puis que Temperature.avancer
# fait reellement varier volume/densite (masse inchangee) sur cet objet.
func _chemin_reel_fabrication_fusionne_dilatation_thermique() -> void:
	var types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(proprietes_immuables.has("dilatation_thermique"), "data/proprietes_immuables_composition.json doit lister dilatation_thermique")

	var bloc := Objet.fabriquer("bloc_dilatation", "bloc", Vector3.ZERO, types, materiaux, proprietes_immuables)
	verif.v(not bloc.is_empty(), "chemin reel : 'bloc' (composition pierre) doit se fabriquer normalement")
	verif.v(is_equal_approx(bloc.proprietes.get("dilatation_thermique", -1.0), materiaux.pierre.dilatation_thermique), "chemin reel : dilatation_thermique doit apparaitre sur l'objet fabrique, EGALE a la fiche pierre (%f), sans que ce test ne la pose a la main" % materiaux.pierre.dilatation_thermique)

	var catalogue := _catalogue_temperature_reel()
	var source_chaude := {"position": Vector3.ZERO, "rayon": 100.0, "temperature": 500.0, "force": 1.0}
	var monde := [bloc]
	var volume_initial: float = bloc.proprietes.volume
	var masse_initiale: float = bloc.proprietes.masse
	Temperature.avancer(monde, [source_chaude], 1.0, catalogue)
	verif.v(bloc.proprietes.volume > volume_initial, "chemin reel : l'objet fabrique se rechauffant doit voir son volume AUGMENTER -- dilatation_thermique lue reellement, jamais posee a la main")
	verif.v(is_equal_approx(bloc.proprietes.masse, masse_initiale), "chemin reel : la masse de l'objet fabrique ne doit jamais changer sous l'effet de la dilatation")
	verif.v(is_equal_approx(bloc.proprietes.densite, bloc.proprietes.masse / bloc.proprietes.volume), "chemin reel : densite recalculee EXACTEMENT masse/volume sur l'objet fabrique")
