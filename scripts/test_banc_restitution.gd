extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_restitution.gd
#
# Verrouille le cablage de banc_restitution.gd, PREMIERE DEMONSTRATION REELLE
# de "restitution" fusionnee a la fabrication (chantier « restitution --
# rebond apres impact ») : hauteur_apres_rebond/vitesse_pour_hauteur/avancer/
# basculer_chute/fabriquer_objets/diagnostiquer (fonctions statiques, pures)
# plus un CHEMIN REEL combinant Objet.fabriquer avec
# data/banc_restitution.json/data/materiaux.json/
# data/proprietes_immuables_composition.json lus sur disque -- le fer doit
# reellement rebondir plus haut et plus longtemps que le bois, la pierre
# entre les deux, une restitution 0.0 ne doit jamais rebondir, une
# restitution 1.0 doit rebondir indefiniment a la meme hauteur, et un objet
# fini doit s'arreter une fois sous le seuil.

const BancRestitution = preload("res://scripts/banc_restitution.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_hauteur_apres_rebond_restitution_nulle_rend_toujours_zero()
	_hauteur_apres_rebond_restitution_un_rend_la_hauteur_inchangee()
	_hauteur_apres_rebond_restitution_intermediaire_reduit_proportionnellement()

	_vitesse_pour_hauteur_hauteur_nulle_rend_zero()
	_vitesse_pour_hauteur_negative_rend_zero()
	_vitesse_pour_hauteur_positive_suit_la_cinematique()

	_avancer_objet_pas_en_chute_ne_bouge_jamais()
	_avancer_objet_arrete_ne_bouge_jamais()
	_avancer_objet_en_chute_tombe_sous_gravite()
	_avancer_impact_pose_nouvelle_hauteur_et_incremente_rebonds()
	_avancer_restitution_nulle_ne_rebondit_jamais()
	_avancer_restitution_un_rebondit_indefiniment_a_la_meme_hauteur()
	_avancer_hauteur_decroit_a_chaque_rebond()
	_avancer_objet_fini_par_s_arreter_sous_le_seuil()
	_avancer_rend_les_ids_qui_ont_subi_un_impact_ce_tick_seulement()

	_basculer_chute_sur_array_vide_ne_fait_rien()
	_basculer_chute_relache_les_trois_a_la_fois()
	_basculer_chute_second_clic_reinitialise_les_trois_a_la_fois()

	_fabriquer_objets_pose_l_etat_de_depart_au_repos()

	_diagnostiquer_rend_les_cinq_champs_attendus()
	_texte_objet_porte_id_et_les_valeurs()
	_ligne_bascule_distingue_relache_et_reinitialise()
	_ligne_impact_distingue_rebond_et_arret()

	_chemin_reel_fabrication_porte_la_restitution_fusionnee()
	_chemin_reel_fer_rebondit_plus_haut_et_plus_longtemps_que_bois()
	_chemin_reel_pierre_entre_bois_et_fer()
	_chemin_reel_objet_fini_par_s_arreter()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: hauteur_apres_rebond/vitesse_pour_hauteur bornees et exactes, avancer integre " +
		"position/vitesse et declenche un rebond au sol (restitution 0.0 ne rebondit jamais, " +
		"restitution 1.0 rebondit indefiniment a la meme hauteur, la hauteur decroit a chaque " +
		"rebond intermediaire, un objet fini s'arrete sous le seuil), basculer_chute relache/" +
		"reinitialise les objets recus a la fois, chemin reel (data/banc_restitution.json/" +
		"materiaux.json/proprietes_immuables_composition.json) ou restitution est bien fusionnee " +
		"a la fabrication, le fer rebondit plus haut et plus longtemps que le bois, la pierre entre " +
		"les deux")
	quit(0)

# ---- hauteur_apres_rebond ----

func _hauteur_apres_rebond_restitution_nulle_rend_toujours_zero() -> void:
	verif.v(is_equal_approx(BancRestitution.hauteur_apres_rebond(400.0, 0.0), 0.0), "restitution 0.0 : la hauteur du rebond suivant doit toujours etre 0.0")
	verif.v(is_equal_approx(BancRestitution.hauteur_apres_rebond(1.0, 0.0), 0.0), "restitution 0.0 : meme sur une hauteur precedente minuscule, doit rendre 0.0")

func _hauteur_apres_rebond_restitution_un_rend_la_hauteur_inchangee() -> void:
	verif.v(is_equal_approx(BancRestitution.hauteur_apres_rebond(250.0, 1.0), 250.0), "restitution 1.0 : la hauteur doit rester EXACTEMENT inchangee (conservation parfaite)")

func _hauteur_apres_rebond_restitution_intermediaire_reduit_proportionnellement() -> void:
	verif.v(is_equal_approx(BancRestitution.hauteur_apres_rebond(400.0, 0.65), 260.0), "restitution 0.65 : 400.0*0.65 = 260.0")

# ---- vitesse_pour_hauteur ----

func _vitesse_pour_hauteur_hauteur_nulle_rend_zero() -> void:
	verif.v(is_equal_approx(BancRestitution.vitesse_pour_hauteur(0.0, 900.0), 0.0), "hauteur 0.0 : aucune vitesse necessaire")

func _vitesse_pour_hauteur_negative_rend_zero() -> void:
	verif.v(is_equal_approx(BancRestitution.vitesse_pour_hauteur(-10.0, 900.0), 0.0), "hauteur negative (donnee incoherente) : jamais une vitesse imaginaire, rend 0.0")

func _vitesse_pour_hauteur_positive_suit_la_cinematique() -> void:
	var v := BancRestitution.vitesse_pour_hauteur(200.0, 900.0)
	verif.v(is_equal_approx(v, sqrt(2.0 * 900.0 * 200.0)), "v doit valoir EXACTEMENT racine(2*gravite*hauteur), recu %f" % v)
	verif.v(v > 0.0, "hauteur positive : la vitesse doit etre strictement positive")

# ---- avancer ----

func _objet_test(id: String, restitution: float, hauteur_initiale: float, en_chute: bool = false) -> Dictionary:
	return {
		"id": id,
		"position": Vector3(0.0, 0.0, hauteur_initiale),
		"proprietes": {
			"restitution": restitution,
			"en_chute": en_chute,
			"arrete": false,
			"vitesse_verticale": 0.0,
			"hauteur_pic": hauteur_initiale,
			"nombre_rebonds": 0,
		},
	}

func _avancer_objet_pas_en_chute_ne_bouge_jamais() -> void:
	var objet := _objet_test("tenu", 0.6, 400.0, false)
	var impacts := BancRestitution.avancer([objet], 900.0, 0.1, 4.0)
	verif.v(is_equal_approx(objet.position.z, 400.0), "objet pas en_chute : la hauteur ne doit JAMAIS bouger, recu %f" % objet.position.z)
	verif.v(impacts.is_empty(), "objet pas en_chute : aucun impact ne doit etre rapporte")

func _avancer_objet_arrete_ne_bouge_jamais() -> void:
	var objet := _objet_test("fini", 0.6, 400.0, true)
	objet.proprietes["arrete"] = true
	objet.position.z = 0.0
	var impacts := BancRestitution.avancer([objet], 900.0, 0.1, 4.0)
	verif.v(is_equal_approx(objet.position.z, 0.0), "objet arrete : la hauteur ne doit JAMAIS rebouger, recu %f" % objet.position.z)
	verif.v(impacts.is_empty(), "objet arrete : aucun impact ne doit etre rapporte")

func _avancer_objet_en_chute_tombe_sous_gravite() -> void:
	var objet := _objet_test("tombe", 0.6, 400.0, true)
	BancRestitution.avancer([objet], 900.0, 0.1, 4.0)
	verif.v(objet.position.z < 400.0, "un pas sous gravite doit faire BAISSER la hauteur, recu %f" % objet.position.z)
	verif.v(objet.proprietes.vitesse_verticale < 0.0, "la vitesse verticale doit devenir NEGATIVE (chute) apres un pas")

func _avancer_impact_pose_nouvelle_hauteur_et_incremente_rebonds() -> void:
	# hauteur_pic tres bas, vitesse deja negative : le prochain pas franchit le sol.
	var objet := _objet_test("proche_sol", 0.5, 400.0, true)
	objet.position.z = 1.0
	objet.proprietes["vitesse_verticale"] = -50.0
	objet.proprietes["hauteur_pic"] = 200.0
	var impacts := BancRestitution.avancer([objet], 900.0, 0.1, 4.0)
	verif.v(impacts == ["proche_sol"], "l'objet doit etre rapporte comme ayant subi un impact ce tick")
	verif.v(is_equal_approx(objet.position.z, 0.0), "au moment de l'impact, la hauteur doit etre remise EXACTEMENT a 0.0")
	verif.v(is_equal_approx(objet.proprietes.hauteur_pic, 100.0), "nouvelle hauteur_pic = 200.0*0.5 = 100.0, recu %f" % objet.proprietes.hauteur_pic)
	verif.v(objet.proprietes.nombre_rebonds == 1, "un rebond au-dessus du seuil doit incrementer nombre_rebonds")
	verif.v(objet.proprietes.vitesse_verticale > 0.0, "apres un rebond, la vitesse doit redevenir ASCENDANTE (positive)")
	verif.v(not objet.proprietes.arrete, "un rebond au-dessus du seuil ne doit pas arreter l'objet")

func _avancer_restitution_nulle_ne_rebondit_jamais() -> void:
	var objet := _objet_test("mou", 0.0, 50.0, true)
	for i in 100:
		BancRestitution.avancer([objet], 900.0, 0.05, 4.0)
		if objet.proprietes.arrete:
			break
	verif.v(objet.proprietes.arrete, "restitution 0.0 : l'objet doit finir par s'arreter au premier contact")
	verif.v(objet.proprietes.nombre_rebonds == 0, "restitution 0.0 : nombre_rebonds doit rester EXACTEMENT 0 -- il ne rebondit jamais, recu %d" % objet.proprietes.nombre_rebonds)

func _avancer_restitution_un_rebondit_indefiniment_a_la_meme_hauteur() -> void:
	var objet := _objet_test("parfait", 1.0, 100.0, true)
	var hauteurs_aux_impacts: Array = []
	for i in 2000:
		var impacts := BancRestitution.avancer([objet], 900.0, 0.01, 4.0)
		if not impacts.is_empty():
			hauteurs_aux_impacts.append(objet.proprietes.hauteur_pic)
		if hauteurs_aux_impacts.size() >= 3:
			break
	verif.v(hauteurs_aux_impacts.size() >= 3, "restitution 1.0 : au moins trois rebonds doivent avoir eu lieu dans la fenetre de simulation, recu %d" % hauteurs_aux_impacts.size())
	for h in hauteurs_aux_impacts:
		verif.v(is_equal_approx(h, 100.0), "restitution 1.0 : CHAQUE rebond doit culminer EXACTEMENT a la hauteur de depart (100.0), recu %f" % h)
	verif.v(not objet.proprietes.arrete, "restitution 1.0 : l'objet ne doit jamais s'arreter")

func _avancer_hauteur_decroit_a_chaque_rebond() -> void:
	var objet := _objet_test("amorti", 0.5, 400.0, true)
	var hauteurs_aux_impacts: Array = []
	for i in 2000:
		var impacts := BancRestitution.avancer([objet], 900.0, 0.01, 4.0)
		if not impacts.is_empty():
			hauteurs_aux_impacts.append(objet.proprietes.hauteur_pic)
		if objet.proprietes.arrete or hauteurs_aux_impacts.size() >= 4:
			break
	verif.v(hauteurs_aux_impacts.size() >= 4, "restitution 0.5 : au moins quatre rebonds attendus avant arret, recu %d" % hauteurs_aux_impacts.size())
	for i in range(1, hauteurs_aux_impacts.size()):
		verif.v(hauteurs_aux_impacts[i] < hauteurs_aux_impacts[i - 1], "la hauteur d'un rebond doit toujours etre STRICTEMENT plus basse que le rebond precedent -- rebond %d=%f, rebond %d=%f" % [i - 1, hauteurs_aux_impacts[i - 1], i, hauteurs_aux_impacts[i]])

func _avancer_objet_fini_par_s_arreter_sous_le_seuil() -> void:
	var objet := _objet_test("court", 0.3, 30.0, true)
	for i in 500:
		BancRestitution.avancer([objet], 900.0, 0.02, 4.0)
		if objet.proprietes.arrete:
			break
	verif.v(objet.proprietes.arrete, "restitution basse, hauteur de depart basse : l'objet doit finir par s'arreter (hauteur sous le seuil)")
	verif.v(is_equal_approx(objet.position.z, 0.0), "une fois arrete, l'objet doit rester au sol EXACTEMENT (z=0.0)")

func _avancer_rend_les_ids_qui_ont_subi_un_impact_ce_tick_seulement() -> void:
	var a := _objet_test("a", 0.6, 5.0, true)
	var b := _objet_test("b", 0.6, 400.0, true)
	var impacts := BancRestitution.avancer([a, b], 900.0, 0.5, 4.0)
	verif.v(impacts.has("a") or a.proprietes.arrete, "'a' (hauteur basse) doit avoir subi un evenement des le premier pas long")
	verif.v(not impacts.has("b"), "'b' (hauteur haute) ne doit PAS encore avoir touche le sol apres un seul pas")

# ---- basculer_chute ----

func _basculer_chute_sur_array_vide_ne_fait_rien() -> void:
	verif.v(BancRestitution.basculer_chute([], 400.0) == false, "basculer_chute sur un Array vide ne doit jamais planter, doit rendre false")

func _basculer_chute_relache_les_trois_a_la_fois() -> void:
	var a := _objet_test("a", 0.5, 400.0, false)
	var b := _objet_test("b", 0.6, 400.0, false)
	var c := _objet_test("c", 0.65, 400.0, false)
	var relache := BancRestitution.basculer_chute([a, b, c], 400.0)
	verif.v(relache, "premier clic : basculer_chute doit rendre true (relachement)")
	verif.v(a.proprietes.en_chute and b.proprietes.en_chute and c.proprietes.en_chute, "premier clic : les TROIS objets doivent porter en_chute=true a la fois")

func _basculer_chute_second_clic_reinitialise_les_trois_a_la_fois() -> void:
	var a := _objet_test("a", 0.5, 400.0, true)
	a.position.z = 12.0
	a.proprietes["vitesse_verticale"] = -30.0
	a.proprietes["hauteur_pic"] = 80.0
	a.proprietes["nombre_rebonds"] = 3
	var b := _objet_test("b", 0.6, 400.0, true)
	b.proprietes["arrete"] = true
	var relache := BancRestitution.basculer_chute([a, b], 400.0)
	verif.v(not relache, "second clic : basculer_chute doit rendre false (reinitialisation)")
	for objet in [a, b]:
		verif.v(not objet.proprietes.en_chute, "reinitialisation : en_chute doit redevenir false")
		verif.v(not objet.proprietes.arrete, "reinitialisation : arrete doit redevenir false")
		verif.v(is_equal_approx(objet.proprietes.vitesse_verticale, 0.0), "reinitialisation : vitesse_verticale doit redevenir 0.0")
		verif.v(is_equal_approx(objet.proprietes.hauteur_pic, 400.0), "reinitialisation : hauteur_pic doit redevenir hauteur_initiale")
		verif.v(objet.proprietes.nombre_rebonds == 0, "reinitialisation : nombre_rebonds doit redevenir 0")
		verif.v(is_equal_approx(objet.position.z, 400.0), "reinitialisation : la hauteur doit redevenir hauteur_initiale")

# ---- fabriquer_objets ----

func _fabriquer_objets_pose_l_etat_de_depart_au_repos() -> void:
	var materiaux := {"bois": {"densite": 0.5, "restitution": 0.5}}
	var declarations := [{"id": "test_bois", "position": [0.0, 0.0, 0.0], "composition": [{"materiau": "bois", "volume": 1.0}]}]
	var objets := BancRestitution.fabriquer_objets(declarations, materiaux, ["restitution"], 300.0)
	verif.v(objets.size() == 1, "un objet declare doit produire un objet fabrique")
	var objet: Dictionary = objets[0]
	verif.v(not objet.proprietes.en_chute, "un objet fraichement fabrique doit etre au repos (en_chute=false)")
	verif.v(not objet.proprietes.arrete, "un objet fraichement fabrique ne doit jamais etre deja arrete")
	verif.v(is_equal_approx(objet.proprietes.vitesse_verticale, 0.0), "vitesse_verticale initiale doit etre 0.0")
	verif.v(is_equal_approx(objet.proprietes.hauteur_pic, 300.0), "hauteur_pic initiale doit etre hauteur_initiale")
	verif.v(objet.proprietes.nombre_rebonds == 0, "nombre_rebonds initial doit etre 0")
	verif.v(is_equal_approx(objet.position.z, 300.0), "la hauteur initiale doit etre hauteur_initiale")
	verif.v(is_equal_approx(objet.proprietes.get("restitution", -1.0), 0.5), "restitution doit etre FUSIONNEE depuis materiaux, recu %f" % objet.proprietes.get("restitution", -1.0))

# ---- diagnostiquer / textes ----

func _diagnostiquer_rend_les_cinq_champs_attendus() -> void:
	var objet := _objet_test("x", 0.6, 400.0, true)
	objet.position.z = 123.0
	objet.proprietes["nombre_rebonds"] = 4
	var diag := BancRestitution.diagnostiquer(objet)
	verif.v(is_equal_approx(diag.restitution, 0.6), "diag.restitution doit refleter proprietes.restitution")
	verif.v(is_equal_approx(diag.hauteur, 123.0), "diag.hauteur doit refleter position.z")
	verif.v(diag.nombre_rebonds == 4, "diag.nombre_rebonds doit refleter proprietes.nombre_rebonds")
	verif.v(not diag.arrete, "diag.arrete doit refleter proprietes.arrete")
	verif.v(diag.en_chute, "diag.en_chute doit refleter proprietes.en_chute")

func _texte_objet_porte_id_et_les_valeurs() -> void:
	var texte := BancRestitution.texte_objet("fer_restitution", {"restitution": 0.65, "hauteur": 123.4, "nombre_rebonds": 3, "arrete": false})
	verif.v(texte.find("fer_restitution") != -1, "le texte doit porter l'id de l'objet")
	verif.v(texte.find("0.65") != -1, "le texte doit porter la restitution")
	verif.v(texte.find("123.4") != -1, "le texte doit porter la hauteur")
	verif.v(texte.find("3") != -1, "le texte doit porter le nombre de rebonds")

func _ligne_bascule_distingue_relache_et_reinitialise() -> void:
	verif.v(BancRestitution.ligne_bascule(1.0, true).find("RELACHE") != -1, "un relachement doit s'imprimer distinctement")
	verif.v(BancRestitution.ligne_bascule(1.0, false).find("REINITIALISE") != -1, "une reinitialisation doit s'imprimer distinctement")

func _ligne_impact_distingue_rebond_et_arret() -> void:
	var rebond := _objet_test("r", 0.6, 400.0, true)
	rebond.proprietes["nombre_rebonds"] = 2
	rebond.proprietes["hauteur_pic"] = 150.0
	verif.v(BancRestitution.ligne_impact(1.0, rebond).find("rebond #2") != -1, "un impact qui rebondit doit mentionner le numero du rebond")

	var arret := _objet_test("s", 0.6, 400.0, true)
	arret.proprietes["arrete"] = true
	arret.proprietes["nombre_rebonds"] = 5
	verif.v(BancRestitution.ligne_impact(1.0, arret).find("arrete") != -1, "un impact final doit mentionner l'arret")

# ---- Chemin reel ----

func _charger(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _config() -> Dictionary:
	return _charger("res://data/banc_restitution.json")

func _materiaux() -> Dictionary:
	return _charger("res://data/materiaux.json")

func _proprietes_immuables() -> Array:
	return _charger("res://data/proprietes_immuables_composition.json").get("proprietes", [])

func _objets_reels() -> Array:
	var donnees := _config()
	return BancRestitution.fabriquer_objets(donnees.get("objets", []), _materiaux(), _proprietes_immuables(), donnees.get("hauteur_initiale", 400.0))

func _chemin_reel_fabrication_porte_la_restitution_fusionnee() -> void:
	var objets := _objets_reels()
	verif.v(objets.size() == 3, "data/banc_restitution.json doit declarer exactement trois objets, recu %d" % objets.size())
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	verif.v(is_equal_approx(par_id.bois_restitution.proprietes.get("restitution", -1.0), 0.5), "chemin reel : bois_restitution doit porter restitution FUSIONNEE 0.5, recu %f" % par_id.bois_restitution.proprietes.get("restitution", -1.0))
	verif.v(is_equal_approx(par_id.pierre_restitution.proprietes.get("restitution", -1.0), 0.6), "chemin reel : pierre_restitution doit porter restitution FUSIONNEE 0.6, recu %f" % par_id.pierre_restitution.proprietes.get("restitution", -1.0))
	verif.v(is_equal_approx(par_id.fer_restitution.proprietes.get("restitution", -1.0), 0.65), "chemin reel : fer_restitution doit porter restitution FUSIONNEE 0.65, recu %f" % par_id.fer_restitution.proprietes.get("restitution", -1.0))

func _simuler_jusqu_a_arret(objet: Dictionary, gravite: float, delta: float, seuil: float, max_pas: int) -> void:
	BancRestitution.basculer_chute([objet], objet.position.z)
	for i in max_pas:
		BancRestitution.avancer([objet], gravite, delta, seuil)
		if objet.proprietes.arrete:
			break

func _chemin_reel_fer_rebondit_plus_haut_et_plus_longtemps_que_bois() -> void:
	var objets := _objets_reels()
	var donnees := _config()
	var gravite: float = donnees.get("gravite", 900.0)
	var seuil: float = donnees.get("seuil_arret", 4.0)
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	_simuler_jusqu_a_arret(par_id.bois_restitution, gravite, 0.02, seuil, 5000)
	_simuler_jusqu_a_arret(par_id.fer_restitution, gravite, 0.02, seuil, 5000)
	verif.v(par_id.bois_restitution.proprietes.arrete, "chemin reel : le bois doit avoir fini par s'arreter dans la fenetre de simulation")
	verif.v(par_id.fer_restitution.proprietes.arrete, "chemin reel : le fer doit avoir fini par s'arreter dans la fenetre de simulation")
	var rebonds_bois: int = par_id.bois_restitution.proprietes.nombre_rebonds
	var rebonds_fer: int = par_id.fer_restitution.proprietes.nombre_rebonds
	verif.v(rebonds_fer > rebonds_bois, "chemin reel : le fer (restitution 0.65) doit rebondir STRICTEMENT plus de fois que le bois (0.5) -- fer=%d bois=%d" % [rebonds_fer, rebonds_bois])

func _chemin_reel_pierre_entre_bois_et_fer() -> void:
	var objets := _objets_reels()
	var donnees := _config()
	var gravite: float = donnees.get("gravite", 900.0)
	var seuil: float = donnees.get("seuil_arret", 4.0)
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	_simuler_jusqu_a_arret(par_id.bois_restitution, gravite, 0.02, seuil, 5000)
	_simuler_jusqu_a_arret(par_id.pierre_restitution, gravite, 0.02, seuil, 5000)
	_simuler_jusqu_a_arret(par_id.fer_restitution, gravite, 0.02, seuil, 5000)
	var rebonds_bois: int = par_id.bois_restitution.proprietes.nombre_rebonds
	var rebonds_pierre: int = par_id.pierre_restitution.proprietes.nombre_rebonds
	var rebonds_fer: int = par_id.fer_restitution.proprietes.nombre_rebonds
	verif.v(rebonds_bois < rebonds_pierre, "chemin reel : la pierre (0.6) doit rebondir plus que le bois (0.5) -- bois=%d pierre=%d" % [rebonds_bois, rebonds_pierre])
	verif.v(rebonds_pierre < rebonds_fer, "chemin reel : le fer (0.65) doit rebondir plus que la pierre (0.6) -- pierre=%d fer=%d" % [rebonds_pierre, rebonds_fer])

func _chemin_reel_objet_fini_par_s_arreter() -> void:
	var objets := _objets_reels()
	var donnees := _config()
	var gravite: float = donnees.get("gravite", 900.0)
	var seuil: float = donnees.get("seuil_arret", 4.0)
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	_simuler_jusqu_a_arret(par_id.bois_restitution, gravite, 0.02, seuil, 5000)
	verif.v(par_id.bois_restitution.proprietes.arrete, "chemin reel : le bois doit finir par s'arreter (hauteur sous le seuil)")
	verif.v(is_equal_approx(par_id.bois_restitution.position.z, 0.0), "chemin reel : une fois arrete, la hauteur doit rester a 0.0")
