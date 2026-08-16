extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_cratere.gd
#
# Verrouille le CABLAGE de scripts/banc_cratere.gd (grille plate, impact qui
# creuse, trace qui decroit puis efface le cratere, eau qui s'accumule dans
# le creux, absence de cratere sans impact) -- jamais scripts/frappe.gd,
# scripts/depense.gd ni scripts/ecoulement.gd eux-memes, deja verrouilles
# par leurs propres tests.
#
# Le CATALOGUE DE SEUILS est lu SUR LE DISQUE (data/seuils_combustible.json,
# entree "effacement_trace") : l'effacement du cratere est fait par
# depense.gd lui-meme a partir de cette entree, la verifier depuis une
# fixture locale ne prouverait rien du chemin reel.

const BancCratere = preload("res://scripts/banc_cratere.gd")
const Depense = preload("res://scripts/depense.gd")
const Ecoulement = preload("res://scripts/ecoulement.gd")
const Verif = preload("res://scripts/verif.gd")

func _config() -> Dictionary:
	return {
		"grille_lignes": 6,
		"grille_colonnes": 6,
		"altitude_plate": 10.0,
		"rayon_voisinage": 1.5,
		"taux_ecoulement": 5.0,
		"eau_initiale": 12.0,
		"eau_reference_couleur": 4.0,
		"nom_reserve_eau": "niveau_eau",
		"nom_altitude_base": "altitude",
		"nom_altitude_effective": "altitude_effective",
		"nom_reserve_integrite": "integrite_sol",
		"nom_reserve_trace": "trace_age",
		"integrite_sol_max": 10.0,
		"degats_impact": 12.0,
		"degats_reference": 10.0,
		"seuil_creusement": 0.0,
		"profondeur_impact": 2.0,
		"duree_effacement": 8.0,
		"cout_base_trace": 1.0,
		"seuils_ref": "effacement_trace",
	}

func _catalogue() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_combustible.json"))

func _init() -> void:
	var v := Verif.new()
	_la_grille_est_plate_et_sans_cratere(v)
	_un_impact_pose_creusement_et_trace_age(v)
	_trace_age_decroit_a_chaque_tick(v)
	_a_trace_age_zero_le_creusement_revient_a_zero(v)
	_sans_impact_aucun_cratere_n_apparait_jamais(v)
	_l_eau_s_accumule_dans_le_cratere(v)
	_l_eau_repart_quand_le_cratere_s_efface(v)
	_l_altitude_de_base_n_est_jamais_ecrasee(v)
	_une_case_effacee_est_recreusable(v)
	_le_catalogue_du_disque_porte_bien_l_effacement_de_trace(v)
	_le_centre_de_la_grille_est_la_case_frappee(v)
	_couleur_bornee_et_distincte_selon_creusement_et_eau(v)
	_effacements_de_ne_retient_que_les_cases_reellement_creusees(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_cratere.gd creuse un cratere a l'impact (creusement>0, trace_age arme), " +
			"laisse depense.gd effacer le cratere a l'epuisement de trace_age, accumule l'eau " +
			"dans le creux puis la relache a l'effacement, et ne creuse jamais rien sans impact")
		quit(0)

# ---- Outils locaux ----

func _case_par_id(cases: Array, id: String) -> Dictionary:
	for case in cases:
		if case.id == id:
			return case
	return {}

func _creusement(case: Dictionary) -> float:
	return float(case.proprietes.get("creusement", 0.0))

func _reserve(case: Dictionary, nom: String) -> float:
	return float(case.proprietes.reserves.get(nom, {}).get("reserve", 0.0))

# Repand l'eau initiale jusqu'a un etat proche de l'uniforme AVANT de
# creuser : sans ca, la ligne 0 porte toute l'eau et le centre est encore
# sec, l'accumulation dans le cratere ne serait pas mesurable.
func _repandre(cases: Array, config: Dictionary, ticks: int, delta: float) -> void:
	for i in range(ticks):
		BancCratere.rafraichir_altitudes_effectives(cases, config)
		Ecoulement.avancer(cases, config.rayon_voisinage, config.nom_reserve_eau, config.nom_altitude_effective, config.taux_ecoulement, delta)

# ---- Cas ----

func _la_grille_est_plate_et_sans_cratere(v) -> void:
	var config := _config()
	var cases := BancCratere.construire_grille(config)
	v.v(cases.size() == 36, "une grille 6x6 doit contenir exactement 36 cases, recu %d" % cases.size())
	for case in cases:
		v.v(is_equal_approx(case.proprietes.altitude, 10.0),
			"le terrain doit etre PLAT : %s doit porter altitude=10.0, recu %.2f" % [case.id, case.proprietes.altitude])
		v.v(is_equal_approx(_creusement(case), 0.0),
			"aucune case ne doit porter de creusement a la construction, %s recu %.2f" % [case.id, _creusement(case)])
		v.v(is_equal_approx(case.position.z, 0.0),
			"position.z doit rester a 0.0 (fait spatial pur, l'altitude vit dans proprietes), %s recu %.2f" % [case.id, case.position.z])
	var eau_ligne0 := 0.0
	var eau_ailleurs := 0.0
	for case in cases:
		if case.position.y == 0.0:
			eau_ligne0 += _reserve(case, "niveau_eau")
		else:
			eau_ailleurs += _reserve(case, "niveau_eau")
	v.v(is_equal_approx(eau_ligne0, 72.0), "les 6 cases de la ligne 0 doivent porter 12.0 chacune (72.0), recu %.2f" % eau_ligne0)
	v.v(is_equal_approx(eau_ailleurs, 0.0), "aucune eau hors de la ligne 0 au depart, recu %.2f" % eau_ailleurs)

func _un_impact_pose_creusement_et_trace_age(v) -> void:
	var config := _config()
	var cases := BancCratere.construire_grille(config)
	var centre: Dictionary = BancCratere.case_centre(cases, config)
	var resultat: Dictionary = BancCratere.impacter(centre, config)

	v.v(resultat.creuse, "un impact de 12.0 sur une integrite de 10.0 doit franchir le seuil et creuser")
	v.v(_creusement(centre) > 0.0, "un impact doit poser un creusement strictement positif, recu %.2f" % _creusement(centre))
	v.v(is_equal_approx(_creusement(centre), 2.0),
		"degats_reels (10.0) / degats_reference (10.0) = 1.0 doit donner exactement profondeur_impact (2.0), recu %.2f" % _creusement(centre))
	v.v(_reserve(centre, "trace_age") > 0.0, "un impact doit armer trace_age, recu %.2f" % _reserve(centre, "trace_age"))
	v.v(is_equal_approx(_reserve(centre, "trace_age"), 8.0),
		"trace_age doit etre arme a duree_effacement (8.0), recu %.2f" % _reserve(centre, "trace_age"))
	v.v(is_equal_approx(_reserve(centre, "integrite_sol"), 10.0),
		"l'integrite doit etre rearmee a integrite_sol_max apres l'impact (la case reste reimpactable), recu %.2f" % _reserve(centre, "integrite_sol"))

	for case in cases:
		if case.id == centre.id:
			continue
		v.v(is_equal_approx(_creusement(case), 0.0),
			"seule la case frappee doit etre creusee, %s recu %.2f" % [case.id, _creusement(case)])

func _trace_age_decroit_a_chaque_tick(v) -> void:
	var config := _config()
	var cases := BancCratere.construire_grille(config)
	var centre: Dictionary = BancCratere.case_centre(cases, config)
	BancCratere.impacter(centre, config)

	var precedent := _reserve(centre, "trace_age")
	for i in range(5):
		Depense.avancer(cases, 0.5, _catalogue())
		var courant := _reserve(centre, "trace_age")
		v.v(courant < precedent,
			"trace_age doit decroitre strictement a chaque tick (pas %d : %.2f -> %.2f)" % [i, precedent, courant])
		v.v(_creusement(centre) > 0.0,
			"le cratere doit rester tant que trace_age n'est pas epuise (pas %d, trace_age=%.2f)" % [i, courant])
		precedent = courant
	v.v(is_equal_approx(precedent, 5.5),
		"cout_base_trace=1.0 doit consommer exactement 1.0 par seconde (8.0 - 2.5 = 5.5), recu %.2f" % precedent)

func _a_trace_age_zero_le_creusement_revient_a_zero(v) -> void:
	var config := _config()
	var cases := BancCratere.construire_grille(config)
	var centre: Dictionary = BancCratere.case_centre(cases, config)
	BancCratere.impacter(centre, config)

	var franchis: Array = []
	for i in range(20):
		franchis = Depense.avancer(cases, 0.5, _catalogue())
		if is_equal_approx(_reserve(centre, "trace_age"), 0.0):
			break
	v.v(is_equal_approx(_reserve(centre, "trace_age"), 0.0),
		"trace_age doit atteindre exactement 0.0 (borne basse de depense.gd), recu %.2f" % _reserve(centre, "trace_age"))
	v.v(is_equal_approx(_creusement(centre), 0.0),
		"a trace_age epuise, le seuil 'effacement_trace' doit reposer creusement a 0.0, recu %.2f" % _creusement(centre))
	v.v(franchis.has(centre.id),
		"depense.gd doit rendre l'id de la case au tick ou son seuil d'effacement s'applique (c'est la SEULE source de la trace console)")
	v.v(BancCratere.compter_crateres(cases) == 0,
		"plus aucun cratere ne doit etre compte apres l'effacement, recu %d" % BancCratere.compter_crateres(cases))

func _sans_impact_aucun_cratere_n_apparait_jamais(v) -> void:
	var config := _config()
	var cases := BancCratere.construire_grille(config)
	for i in range(60):
		Depense.avancer(cases, 0.1, _catalogue())
		BancCratere.rafraichir_altitudes_effectives(cases, config)
		Ecoulement.avancer(cases, config.rayon_voisinage, config.nom_reserve_eau, config.nom_altitude_effective, config.taux_ecoulement, 0.1)
	v.v(BancCratere.compter_crateres(cases) == 0,
		"sans aucun impact, aucun cratere ne doit jamais apparaitre, recu %d" % BancCratere.compter_crateres(cases))
	for case in cases:
		v.v(is_equal_approx(case.proprietes.altitude_effective, 10.0),
			"sans cratere, l'altitude effective doit rester egale a l'altitude de base sur %s, recu %.2f" % [case.id, case.proprietes.altitude_effective])

func _l_eau_s_accumule_dans_le_cratere(v) -> void:
	var config := _config()
	var cases := BancCratere.construire_grille(config)
	_repandre(cases, config, 400, 0.05)

	var centre: Dictionary = BancCratere.case_centre(cases, config)
	var eau_avant := _reserve(centre, "niveau_eau")
	BancCratere.impacter(centre, config)
	_repandre(cases, config, 400, 0.05)

	var eau_centre := _reserve(centre, "niveau_eau")
	v.v(eau_centre > eau_avant,
		"l'eau doit s'accumuler dans le cratere (avant %.3f, apres %.3f)" % [eau_avant, eau_centre])
	for voisin_id in ["case_2_3", "case_4_3", "case_3_2", "case_3_4"]:
		var voisin := _case_par_id(cases, voisin_id)
		v.v(eau_centre > _reserve(voisin, "niveau_eau"),
			"la case cratere doit porter strictement plus d'eau que son voisin %s (%.3f contre %.3f)" % [voisin_id, eau_centre, _reserve(voisin, "niveau_eau")])

func _l_eau_repart_quand_le_cratere_s_efface(v) -> void:
	var config := _config()
	var cases := BancCratere.construire_grille(config)
	_repandre(cases, config, 400, 0.05)
	var centre: Dictionary = BancCratere.case_centre(cases, config)
	BancCratere.impacter(centre, config)
	_repandre(cases, config, 400, 0.05)
	var eau_pleine := _reserve(centre, "niveau_eau")

	# Effacement, puis meme duree d'ecoulement qu'avant.
	for i in range(20):
		Depense.avancer(cases, 0.5, _catalogue())
	v.v(is_equal_approx(_creusement(centre), 0.0), "le cratere doit etre efface avant de mesurer le retrait de l'eau")
	_repandre(cases, config, 400, 0.05)

	var eau_apres := _reserve(centre, "niveau_eau")
	v.v(eau_apres < eau_pleine,
		"une fois le cratere efface, l'eau accumulee doit repartir vers les voisines (%.3f -> %.3f)" % [eau_pleine, eau_apres])
	var voisin := _case_par_id(cases, "case_2_3")
	v.v(abs(eau_apres - _reserve(voisin, "niveau_eau")) < 0.05,
		"sur un terrain redevenu plat, la case et sa voisine doivent revenir a un niveau quasi egal (%.3f contre %.3f)" % [eau_apres, _reserve(voisin, "niveau_eau")])

func _l_altitude_de_base_n_est_jamais_ecrasee(v) -> void:
	var config := _config()
	var cases := BancCratere.construire_grille(config)
	var centre: Dictionary = BancCratere.case_centre(cases, config)
	BancCratere.impacter(centre, config)
	BancCratere.rafraichir_altitudes_effectives(cases, config)

	v.v(is_equal_approx(centre.proprietes.altitude, 10.0),
		"l'altitude de BASE ne doit jamais etre reecrite par un impact, recu %.2f" % centre.proprietes.altitude)
	v.v(is_equal_approx(centre.proprietes.altitude_effective, 8.0),
		"l'altitude EFFECTIVE doit valoir altitude - creusement (10.0 - 2.0 = 8.0), recu %.2f" % centre.proprietes.altitude_effective)

	for i in range(20):
		Depense.avancer(cases, 0.5, _catalogue())
	BancCratere.rafraichir_altitudes_effectives(cases, config)
	v.v(is_equal_approx(centre.proprietes.altitude_effective, 10.0),
		"apres effacement, l'altitude effective doit revenir exactement a l'altitude de base, recu %.2f" % centre.proprietes.altitude_effective)

func _une_case_effacee_est_recreusable(v) -> void:
	var config := _config()
	var cases := BancCratere.construire_grille(config)
	var centre: Dictionary = BancCratere.case_centre(cases, config)
	BancCratere.impacter(centre, config)
	for i in range(20):
		Depense.avancer(cases, 0.5, _catalogue())
	v.v(is_equal_approx(_creusement(centre), 0.0), "le premier cratere doit etre efface avant le second impact")

	var second: Dictionary = BancCratere.impacter(centre, config)
	v.v(second.creuse, "une case dont la trace est effacee doit pouvoir etre recreusee (integrite rearmee)")
	v.v(is_equal_approx(_creusement(centre), 2.0), "le second cratere doit avoir la meme profondeur que le premier, recu %.2f" % _creusement(centre))
	v.v(centre.proprietes.reserves.trace_age.seuils_franchis.is_empty(),
		"l'impact doit VIDER seuils_franchis, sinon depense.gd n'effacerait jamais le second cratere")

	for i in range(20):
		Depense.avancer(cases, 0.5, _catalogue())
	v.v(is_equal_approx(_creusement(centre), 0.0),
		"le SECOND cratere doit s'effacer comme le premier, recu %.2f" % _creusement(centre))

func _le_catalogue_du_disque_porte_bien_l_effacement_de_trace(v) -> void:
	var catalogue := _catalogue()
	v.v(catalogue.has("effacement_trace"),
		"data/seuils_combustible.json doit porter l'entree 'effacement_trace' (referencee par data/banc_cratere.json:seuils_ref)")
	var entree: Array = catalogue.get("effacement_trace", [])
	v.v(entree.size() == 1, "'effacement_trace' doit porter exactement un seuil, recu %d" % entree.size())
	v.v(entree.size() > 0 and is_equal_approx(float(entree[0].get("seuil", -1.0)), 0.0),
		"le seuil d'effacement doit se declencher a reserve 0.0")
	v.v(entree.size() > 0 and entree[0].get("poser", {}).has("creusement"),
		"le seuil d'effacement doit POSER creusement (et non retirer une cle) -- c'est lui qui efface le cratere")

func _le_centre_de_la_grille_est_la_case_frappee(v) -> void:
	var config := _config()
	var cases := BancCratere.construire_grille(config)
	var centre: Variant = BancCratere.case_centre(cases, config)
	v.v(centre != null and centre.id == "case_3_3",
		"le centre d'une grille 6x6 doit etre case_3_3, recu %s" % (centre.id if centre != null else "null"))
	v.v(BancCratere.case_centre([], config) == null, "une grille vide doit rendre null, jamais planter")

func _couleur_bornee_et_distincte_selon_creusement_et_eau(v) -> void:
	var sec := BancCratere.couleur_case(0.0, 0.0, 2.0, 4.0)
	var creuse := BancCratere.couleur_case(2.0, 0.0, 2.0, 4.0)
	var noye := BancCratere.couleur_case(0.0, 4.0, 2.0, 4.0)
	v.v(not sec.is_equal_approx(creuse), "une case creusee a sec doit etre visiblement plus sombre qu'une case intacte a sec")
	v.v(not sec.is_equal_approx(noye), "une case pleine d'eau doit etre visiblement differente d'une case seche")
	v.v(creuse.is_equal_approx(BancCratere.couleur_case(50.0, 0.0, 2.0, 4.0)),
		"un creusement au-dela de la reference doit rendre exactement la meme couleur, jamais divergente")
	v.v(noye.is_equal_approx(BancCratere.couleur_case(0.0, 500.0, 2.0, 4.0)),
		"un niveau d'eau au-dela de la reference doit rendre exactement la meme couleur, jamais divergente")
	v.v(BancCratere.couleur_case(1.0, 1.0, 0.0, 0.0).is_equal_approx(sec),
		"des references nulles doivent rendre la couleur de base, jamais une division par zero")

func _effacements_de_ne_retient_que_les_cases_reellement_creusees(v) -> void:
	var effaces: Array = BancCratere.effacements_de(["a", "b", "c"], ["b"])
	v.v(effaces.size() == 1 and effaces[0] == "b",
		"effacements_de ne doit garder que les ids qui etaient creuses AVANT l'appel a depense.gd, recu %s" % str(effaces))
	v.v(BancCratere.effacements_de(["a", "b"], []).is_empty(),
		"aucun cratere avant l'appel : aucun effacement a tracer, jamais un faux positif")
