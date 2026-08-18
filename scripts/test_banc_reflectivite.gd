extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_reflectivite.gd
#
# Verrouille scripts/banc_reflectivite.gd : ses fonctions PURES propres
# (chaleur_absorbee, source_reflechie, source_radiante, position_source_
# mobile, sources_lumiere_ambiantes, lampe_apres_clic) SANS AUCUN nom de
# materiau -- preuve que la formule ne connait ni argent ni bois -- PLUS un
# chemin reel complet -- data/banc_reflectivite.json, data/materiaux.json,
# data/etats.json, data/lumiere.json, data/temperature.json lus sur disque
# -- qui rejoue chacun des points demandes : l'argent reflechit, le bois
# absorbe, la ternissure (et sa cousine patine_verte, utilisee par ce banc)
# reduisent la reflexion, hors lumiere aucun reflet, reflectivite 0.0 ne
# reflechit jamais, un temoin pres de l'argent recoit plus de lumiere
# qu'un temoin pres du bois, l'argent chauffe moins vite que le bois sous
# la meme lampe, la lampe coupee au clic fait redescendre la temperature,
# la source mobile fait varier lumiere_locale dans le temps.

const BancReflectivite = preload("res://scripts/banc_reflectivite.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Lumiere = preload("res://scripts/lumiere.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_chaleur_absorbee_objet_sombre_absorbe_plus_qu_objet_reflechissant()
	_chaleur_absorbee_hors_lumiere_toujours_nulle()
	_chaleur_absorbee_reflectivite_totale_jamais_absorbee()

	_source_reflechie_porte_intensite_egale_lumiere_locale_et_force_egale_reflectivite()
	_source_reflechie_reflectivite_nulle_ne_reflechit_jamais()
	_source_reflechie_hors_lumiere_aucun_reflet()

	_source_radiante_force_egale_chaleur_absorbee()

	_position_source_mobile_immobile_sans_periode()
	_position_source_mobile_fait_un_aller_retour_sinusoidal()

	_sources_lumiere_ambiantes_lampe_active_incluse()
	_sources_lumiere_ambiantes_lampe_coupee_exclue()
	_sources_lumiere_ambiantes_source_mobile_toujours_incluse()

	_lampe_apres_clic_inverse_letat()

	_ternissure_reduit_la_reflectivite_de_largent_chemin_reel()

	_chemin_reel_fabriquer_objets_toutes_les_proprietes_presentes()
	_chemin_reel_largent_reflechit_plus_que_le_bois()
	_chemin_reel_le_bois_absorbe_plus_de_chaleur_que_largent()
	_chemin_reel_patine_verte_reduit_la_reflectivite_effective_du_cuivre()
	_chemin_reel_temoin_pres_de_largent_recoit_plus_de_lumiere_que_pres_du_bois()
	_chemin_reel_largent_chauffe_moins_que_le_bois_sous_la_meme_lampe()
	_chemin_reel_lampe_coupee_la_temperature_redescend()
	_chemin_reel_source_mobile_fait_varier_lumiere_locale_dans_le_temps()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: fonctions propres a banc_reflectivite.gd (chaleur_absorbee, " +
		"source_reflechie, source_radiante, position_source_mobile, " +
		"sources_lumiere_ambiantes, lampe_apres_clic, hors domaine) et " +
		"chemin reel complet sur data/banc_reflectivite.json + " +
		"data/materiaux.json + data/etats.json + data/lumiere.json + " +
		"data/temperature.json -- l'argent reflechit, le bois absorbe, la " +
		"ternissure/patine_verte reduisent la reflexion, hors lumiere aucun " +
		"reflet, reflectivite 0.0 ne reflechit jamais, un temoin pres de " +
		"l'argent recoit plus de lumiere qu'un temoin pres du bois, " +
		"l'argent chauffe moins vite que le bois sous la meme lampe, la " +
		"lampe coupee au clic fait redescendre la temperature, la source " +
		"mobile fait varier lumiere_locale dans le temps")
	quit(0)

# ---- Fonctions PURES, hors domaine (aucun nom de materiau) ----

func _chaleur_absorbee_objet_sombre_absorbe_plus_qu_objet_reflechissant() -> void:
	var sombre := BancReflectivite.chaleur_absorbee(0.6, 0.15, 0.5)
	var reflechissant := BancReflectivite.chaleur_absorbee(0.1, 0.95, 0.5)
	verif.v(sombre > reflechissant, "un objet sombre et peu reflechissant doit absorber strictement plus qu'un objet clair et tres reflechissant a lumiere_locale egale, recu sombre=%f reflechissant=%f" % [sombre, reflechissant])

func _chaleur_absorbee_hors_lumiere_toujours_nulle() -> void:
	var v := BancReflectivite.chaleur_absorbee(0.9, 0.0, 0.0)
	verif.v(is_equal_approx(v, 0.0), "hors de toute lumiere (lumiere_locale=0.0), chaleur_absorbee doit etre exactement 0.0 meme pour un objet tres sombre et pas du tout reflechissant, recu %f" % v)

func _chaleur_absorbee_reflectivite_totale_jamais_absorbee() -> void:
	var v := BancReflectivite.chaleur_absorbee(0.9, 1.0, 0.8)
	verif.v(is_equal_approx(v, 0.0), "un objet a reflectivite totale (1.0) ne doit jamais absorber de chaleur, quelle que soit sa noirceur ou la lumiere recue, recu %f" % v)

func _source_reflechie_porte_intensite_egale_lumiere_locale_et_force_egale_reflectivite() -> void:
	var objet := {"position": Vector3(10.0, 20.0, 0.0), "proprietes": {}}
	var config := {"rayon_reflet": 150.0, "temperature_couleur_reflet": 0.4}
	var source := BancReflectivite.source_reflechie(objet, 0.7, 0.3, config)
	verif.v(source.position == objet.position, "la source reflechie doit etre posee exactement a la position de l'objet")
	verif.v(is_equal_approx(source.intensite, 0.3), "intensite de la source reflechie doit egaler lumiere_locale recue, recu %f" % source.intensite)
	verif.v(is_equal_approx(source.force, 0.7), "force de la source reflechie doit egaler la reflectivite effective, recu %f" % source.force)
	verif.v(is_equal_approx(source.intensite * source.force, 0.3 * 0.7), "le produit intensite*force (ce que lumiere.gd additionne reellement) doit valoir exactement reflectivite x lumiere_locale, recu %f" % (source.intensite * source.force))

func _source_reflechie_reflectivite_nulle_ne_reflechit_jamais() -> void:
	var objet := {"position": Vector3(0.0, 0.0, 0.0), "proprietes": {}}
	var config := {"rayon_reflet": 200.0, "temperature_couleur_reflet": 0.5}
	var source := BancReflectivite.source_reflechie(objet, 0.0, 0.9, config)
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.0, "couleur": 0.5}, "attenuation": {"exposant": 1.0}}}
	var lu := Lumiere.locale(Vector3(50.0, 0.0, 0.0), [source], catalogue)
	verif.v(is_equal_approx(lu.intensite, 0.0), "une source reflechie a reflectivite 0.0 ne doit JAMAIS contribuer a la lumiere ambiante, meme sous une lumiere_locale recue tres forte (0.9), recu %f" % lu.intensite)

func _source_reflechie_hors_lumiere_aucun_reflet() -> void:
	var objet := {"position": Vector3(0.0, 0.0, 0.0), "proprietes": {}}
	var config := {"rayon_reflet": 200.0, "temperature_couleur_reflet": 0.5}
	var source := BancReflectivite.source_reflechie(objet, 0.95, 0.0, config)
	var catalogue := {"defaut": {"ambiante": {"intensite": 0.0, "couleur": 0.5}, "attenuation": {"exposant": 1.0}}}
	var lu := Lumiere.locale(Vector3(50.0, 0.0, 0.0), [source], catalogue)
	verif.v(is_equal_approx(lu.intensite, 0.0), "hors de toute lumiere (lumiere_locale=0.0), un objet meme tres reflechissant (0.95) ne doit produire AUCUN reflet, recu %f" % lu.intensite)

func _source_radiante_force_egale_chaleur_absorbee() -> void:
	var objet := {"position": Vector3(5.0, 5.0, 0.0), "proprietes": {}}
	var config := {"rayon_radiant": 5.0, "temperature_radiante": 100.0}
	var source := BancReflectivite.source_radiante(objet, 0.234, config)
	verif.v(source.position == objet.position, "la source radiante doit etre posee exactement a la position de l'objet")
	verif.v(is_equal_approx(source.force, 0.234), "force de la source radiante doit egaler chaleur_absorbee, recu %f" % source.force)
	verif.v(is_equal_approx(source.rayon, 5.0), "rayon de la source radiante doit venir de la config (minuscule, couvre uniquement l'objet), recu %f" % source.rayon)

func _position_source_mobile_immobile_sans_periode() -> void:
	var centre := Vector3(100.0, 0.0, 0.0)
	var p := BancReflectivite.position_source_mobile(centre, 250.0, 0.0, 5.0)
	verif.v(p.is_equal_approx(centre), "periode a 0.0 doit laisser la source mobile immobile au centre, recu %s" % p)

func _position_source_mobile_fait_un_aller_retour_sinusoidal() -> void:
	var centre := Vector3(0.0, 0.0, 0.0)
	var p_quart := BancReflectivite.position_source_mobile(centre, 250.0, 20.0, 5.0)
	verif.v(is_equal_approx(p_quart.x, 250.0), "a un quart de periode, la source mobile doit etre a l'amplitude maximale, recu %f" % p_quart.x)
	var p_moitie := BancReflectivite.position_source_mobile(centre, 250.0, 20.0, 10.0)
	verif.v(is_equal_approx(p_moitie.x, 0.0), "a une demi-periode, la source mobile doit etre revenue au centre, recu %f" % p_moitie.x)

func _sources_lumiere_ambiantes_lampe_active_incluse() -> void:
	var lampe := {"position": Vector3(1.0, 0.0, 0.0)}
	var mobile := {"position": Vector3(2.0, 0.0, 0.0)}
	var sources := BancReflectivite.sources_lumiere_ambiantes(lampe, true, mobile)
	verif.v(sources.has(lampe), "lampe active doit figurer dans les sources ambiantes")
	verif.v(sources.size() == 2, "lampe active + source mobile doit rendre exactement deux sources, recu %d" % sources.size())

func _sources_lumiere_ambiantes_lampe_coupee_exclue() -> void:
	var lampe := {"position": Vector3(1.0, 0.0, 0.0)}
	var mobile := {"position": Vector3(2.0, 0.0, 0.0)}
	var sources := BancReflectivite.sources_lumiere_ambiantes(lampe, false, mobile)
	verif.v(not sources.has(lampe), "lampe coupee ne doit JAMAIS figurer dans les sources ambiantes")
	verif.v(sources.size() == 1, "lampe coupee doit laisser exactement une source (la mobile), recu %d" % sources.size())

func _sources_lumiere_ambiantes_source_mobile_toujours_incluse() -> void:
	var lampe := {"position": Vector3(1.0, 0.0, 0.0)}
	var mobile := {"position": Vector3(2.0, 0.0, 0.0)}
	verif.v(BancReflectivite.sources_lumiere_ambiantes(lampe, true, mobile).has(mobile), "la source mobile doit toujours figurer, lampe active")
	verif.v(BancReflectivite.sources_lumiere_ambiantes(lampe, false, mobile).has(mobile), "la source mobile doit toujours figurer, lampe coupee -- elle n'est JAMAIS togglable")

func _lampe_apres_clic_inverse_letat() -> void:
	verif.v(BancReflectivite.lampe_apres_clic(true) == false, "un clic sur une lampe active doit la couper")
	verif.v(BancReflectivite.lampe_apres_clic(false) == true, "un clic sur une lampe coupee doit l'activer")

# ---- Chemin reel : data/etats.json (ternissure, telle quelle demandee) ----

func _catalogue_etats_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))

func _ternissure_reduit_la_reflectivite_de_largent_chemin_reel() -> void:
	var etats := _catalogue_etats_reel()
	var argent_intact := {"proprietes": {"reflectivite": 0.95, "etats_actifs": []}}
	var argent_terni := {"proprietes": {"reflectivite": 0.95, "etats_actifs": ["ternissure"]}}
	var eff_intact: float = EtatEffectif.valeur(argent_intact, "reflectivite", etats)
	var eff_terni: float = EtatEffectif.valeur(argent_terni, "reflectivite", etats)
	verif.v(eff_terni < eff_intact, "chemin reel (data/etats.json) : la ternissure doit reduire STRICTEMENT la reflectivite effective de l'argent, recu intact=%f terni=%f" % [eff_intact, eff_terni])
	verif.v(is_equal_approx(eff_terni, 0.95 * 0.15), "chemin reel : reflectivite ternie attendue 0.95*0.15, recu %f" % eff_terni)

# ---- Chemin reel : data/banc_reflectivite.json + data/materiaux.json ----

func _donnees_banc_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_reflectivite.json"))

func _materiaux_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))

func _proprietes_immuables_reelles() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])

func _lampe_reelle(donnees: Dictionary) -> Dictionary:
	var decl: Dictionary = donnees.lampe
	var pos: Array = decl.position
	return {"position": Vector3(pos[0], pos[1], pos[2]), "rayon": decl.rayon, "intensite": decl.intensite, "temperature_couleur": decl.temperature_couleur, "force": decl.force}

func _objets_reels() -> Dictionary:
	var donnees := _donnees_banc_reelles()
	var objets := BancReflectivite.fabriquer_objets(donnees.objets, _materiaux_reels(), _proprietes_immuables_reelles(), donnees.config)
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	return par_id

func _chemin_reel_fabriquer_objets_toutes_les_proprietes_presentes() -> void:
	var objets := _objets_reels()
	verif.v(objets.size() == 3, "chemin reel : les trois objets (argent_0/bois_0/cuivre_patine_0) doivent tous etre fabriques, recu %d" % objets.size())
	for id in ["argent_0", "bois_0", "cuivre_patine_0"]:
		var objet: Dictionary = objets[id]
		verif.v(objet.proprietes.has("reflectivite"), "chemin reel : %s doit porter 'reflectivite' fusionnee (proprietes_immuables)" % id)
		verif.v(objet.proprietes.has("absorption_sombre"), "chemin reel : %s doit porter 'absorption_sombre' fusionnee (proprietes_immuables)" % id)
		verif.v(objet.proprietes.has("temperature"), "chemin reel : %s doit porter 'temperature' (constante locale posee par fabriquer_objets)" % id)
	verif.v(objets.cuivre_patine_0.proprietes.etats_actifs.has("patine_verte"), "chemin reel : cuivre_patine_0 doit porter 'patine_verte' dans etats_actifs des la fabrication")
	verif.v(objets.argent_0.proprietes.etats_actifs.is_empty(), "chemin reel : argent_0 ne doit porter aucun etat")
	verif.v(objets.bois_0.proprietes.etats_actifs.is_empty(), "chemin reel : bois_0 ne doit porter aucun etat")

func _chemin_reel_largent_reflechit_plus_que_le_bois() -> void:
	var donnees := _donnees_banc_reelles()
	var lampe := _lampe_reelle(donnees)
	var etats := _catalogue_etats_reel()
	var objets := _objets_reels()
	var diag_argent := BancReflectivite.diagnostiquer(objets.argent_0, [lampe], JSON.parse_string(FileAccess.get_file_as_string("res://data/lumiere.json")), etats)
	var diag_bois := BancReflectivite.diagnostiquer(objets.bois_0, [lampe], JSON.parse_string(FileAccess.get_file_as_string("res://data/lumiere.json")), etats)
	verif.v(diag_argent.reflectivite_effective > diag_bois.reflectivite_effective, "chemin reel : l'argent doit avoir une reflectivite effective strictement superieure au bois, recu argent=%f bois=%f" % [diag_argent.reflectivite_effective, diag_bois.reflectivite_effective])
	verif.v(absf(diag_argent.lumiere_locale - diag_bois.lumiere_locale) < 0.001, "chemin reel : argent_0 et bois_0 sont a EGALE distance de la lampe (donnee du banc, positions arrondies a 0.1 unite pres) -- la lumiere_locale recue doit etre quasi identique, isolant la reflectivite comme seule variable, recu argent=%f bois=%f" % [diag_argent.lumiere_locale, diag_bois.lumiere_locale])

func _chemin_reel_le_bois_absorbe_plus_de_chaleur_que_largent() -> void:
	var donnees := _donnees_banc_reelles()
	var lampe := _lampe_reelle(donnees)
	var etats := _catalogue_etats_reel()
	var catalogue_lumiere: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/lumiere.json"))
	var objets := _objets_reels()
	var diag_argent := BancReflectivite.diagnostiquer(objets.argent_0, [lampe], catalogue_lumiere, etats)
	var diag_bois := BancReflectivite.diagnostiquer(objets.bois_0, [lampe], catalogue_lumiere, etats)
	verif.v(diag_bois.chaleur_absorbee > diag_argent.chaleur_absorbee, "chemin reel : le bois doit absorber strictement plus de chaleur que l'argent sous la meme lumiere_locale, recu bois=%f argent=%f" % [diag_bois.chaleur_absorbee, diag_argent.chaleur_absorbee])

func _chemin_reel_patine_verte_reduit_la_reflectivite_effective_du_cuivre() -> void:
	var objets := _objets_reels()
	var cuivre: Dictionary = objets.cuivre_patine_0
	var base: float = cuivre.proprietes.reflectivite
	var etats := _catalogue_etats_reel()
	var effective: float = EtatEffectif.valeur(cuivre, "reflectivite", etats)
	verif.v(effective < base, "chemin reel : la patine_verte doit reduire STRICTEMENT la reflectivite effective du cuivre par rapport a sa base, recu base=%f effective=%f" % [base, effective])
	verif.v(is_equal_approx(effective, base * 0.3), "chemin reel : reflectivite effective attendue base*0.3 (facteur de patine_verte, data/etats.json), recu %f" % effective)

func _chemin_reel_temoin_pres_de_largent_recoit_plus_de_lumiere_que_pres_du_bois() -> void:
	var donnees := _donnees_banc_reelles()
	var lampe := _lampe_reelle(donnees)
	var objets := BancReflectivite.fabriquer_objets(donnees.objets, _materiaux_reels(), _proprietes_immuables_reelles(), donnees.config)
	var temoins := BancReflectivite.fabriquer_temoins(donnees.temoins)
	var etats := _catalogue_etats_reel()
	var catalogue_lumiere: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/lumiere.json"))
	var catalogue_temperature: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/temperature.json"))

	BancReflectivite.avancer(objets, temoins, [lampe], 0.1, catalogue_lumiere, catalogue_temperature, etats, donnees.config)

	var par_id: Dictionary = {}
	for temoin in temoins:
		par_id[temoin.id] = temoin
	var intensite_argent: float = par_id.temoin_argent.proprietes.intensite_lumiere
	var intensite_bois: float = par_id.temoin_bois.proprietes.intensite_lumiere
	verif.v(intensite_argent > intensite_bois, "chemin reel : le temoin pres de l'argent doit recevoir strictement plus de lumiere que le temoin pres du bois, recu argent=%f bois=%f" % [intensite_argent, intensite_bois])
	verif.v(intensite_bois > 0.0, "chemin reel : le temoin pres du bois doit tout de meme recevoir un peu de lumiere reflechie (bois n'est pas totalement noir), recu %f" % intensite_bois)

func _chemin_reel_largent_chauffe_moins_que_le_bois_sous_la_meme_lampe() -> void:
	var donnees := _donnees_banc_reelles()
	var lampe := _lampe_reelle(donnees)
	var objets := BancReflectivite.fabriquer_objets(donnees.objets, _materiaux_reels(), _proprietes_immuables_reelles(), donnees.config)
	var temoins := BancReflectivite.fabriquer_temoins(donnees.temoins)
	var etats := _catalogue_etats_reel()
	var catalogue_lumiere: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/lumiere.json"))
	var catalogue_temperature: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/temperature.json"))

	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet
	var temperature_depart: float = par_id.argent_0.proprietes.temperature
	verif.v(is_equal_approx(par_id.bois_0.proprietes.temperature, temperature_depart), "chemin reel : argent et bois doivent partir a la MEME temperature (donnee du banc), recu argent=%f bois=%f" % [temperature_depart, par_id.bois_0.proprietes.temperature])

	for i in range(200):
		BancReflectivite.avancer(objets, temoins, [lampe], 0.1, catalogue_lumiere, catalogue_temperature, etats, donnees.config)

	var temperature_argent: float = par_id.argent_0.proprietes.temperature
	var temperature_bois: float = par_id.bois_0.proprietes.temperature
	verif.v(temperature_bois > temperature_argent, "chemin reel : apres simulation, le bois doit avoir chauffe strictement plus que l'argent sous la meme lampe, recu bois=%f argent=%f" % [temperature_bois, temperature_argent])
	verif.v(temperature_argent < temperature_depart + 1.0, "chemin reel : l'argent, tres reflechissant, doit rester tres proche de sa temperature de depart, recu %f (depart %f)" % [temperature_argent, temperature_depart])

func _chemin_reel_lampe_coupee_la_temperature_redescend() -> void:
	var donnees := _donnees_banc_reelles()
	var lampe := _lampe_reelle(donnees)
	var objets := BancReflectivite.fabriquer_objets(donnees.objets, _materiaux_reels(), _proprietes_immuables_reelles(), donnees.config)
	var temoins := BancReflectivite.fabriquer_temoins(donnees.temoins)
	var etats := _catalogue_etats_reel()
	var catalogue_lumiere: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/lumiere.json"))
	var catalogue_temperature: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/temperature.json"))

	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet

	# lampe active seule (source mobile hors de portee de tout objet a
	# cette position -- vecteur nul, jamais utilisee dans ce test) : le
	# bois chauffe.
	var mobile_absente := {"position": Vector3(99999.0, 99999.0, 0.0), "rayon": 1.0, "intensite": 0.0, "temperature_couleur": 0.5, "force": 0.0}
	for i in range(200):
		BancReflectivite.avancer(objets, temoins, [lampe, mobile_absente], 0.1, catalogue_lumiere, catalogue_temperature, etats, donnees.config)
	var temperature_chauffee: float = par_id.bois_0.proprietes.temperature
	verif.v(temperature_chauffee > donnees.config.temperature_depart, "chemin reel : le bois doit avoir chauffe au-dessus de sa temperature de depart, lampe active, recu %f (depart %f)" % [temperature_chauffee, donnees.config.temperature_depart])

	# lampe coupee (retiree du tableau de sources, jamais une intensite a
	# 0.0 laissee trainer) : la temperature doit redescendre vers l'ambiante.
	for i in range(200):
		BancReflectivite.avancer(objets, temoins, [mobile_absente], 0.1, catalogue_lumiere, catalogue_temperature, etats, donnees.config)
	var temperature_refroidie: float = par_id.bois_0.proprietes.temperature
	verif.v(temperature_refroidie < temperature_chauffee, "chemin reel : lampe coupee, la temperature du bois doit redescendre strictement, recu chauffee=%f refroidie=%f" % [temperature_chauffee, temperature_refroidie])

func _chemin_reel_source_mobile_fait_varier_lumiere_locale_dans_le_temps() -> void:
	var donnees := _donnees_banc_reelles()
	var etats := _catalogue_etats_reel()
	var catalogue_lumiere: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/lumiere.json"))
	var objets := _objets_reels()
	var decl_mobile: Dictionary = donnees.source_mobile
	var centre := Vector3(decl_mobile.centre[0], decl_mobile.centre[1], decl_mobile.centre[2])

	var pos_proche := BancReflectivite.position_source_mobile(centre, decl_mobile.amplitude, decl_mobile.periode, 0.0)
	var source_proche := {"position": pos_proche, "rayon": decl_mobile.rayon, "intensite": decl_mobile.intensite, "temperature_couleur": decl_mobile.temperature_couleur, "force": decl_mobile.force}
	var diag_proche := BancReflectivite.diagnostiquer(objets.argent_0, [source_proche], catalogue_lumiere, etats)

	var pos_loin := BancReflectivite.position_source_mobile(centre, decl_mobile.amplitude, decl_mobile.periode, decl_mobile.periode / 4.0)
	var source_loin := {"position": pos_loin, "rayon": decl_mobile.rayon, "intensite": decl_mobile.intensite, "temperature_couleur": decl_mobile.temperature_couleur, "force": decl_mobile.force}
	var diag_loin := BancReflectivite.diagnostiquer(objets.argent_0, [source_loin], catalogue_lumiere, etats)

	verif.v(not is_equal_approx(diag_proche.lumiere_locale, diag_loin.lumiere_locale), "chemin reel : la source mobile reelle doit faire varier lumiere_locale d'un instant a l'autre (t=0 vs demi-periode), recu proche=%f loin=%f" % [diag_proche.lumiere_locale, diag_loin.lumiere_locale])
