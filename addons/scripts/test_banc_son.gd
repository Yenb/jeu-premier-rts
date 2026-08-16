extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_son.gd
#
# Verrouille DEUX choses a la fois, chantier « son -- grandeur ambiante par
# sources » :
# 1. le nouveau filtre de scripts/perception.gd:_percevoir_propagation_obstacles
#    (canal ouie, champ "seuil" desormais consomme) -- AUCUN autre fichier
#    de test ne l'exerce (limite stricte du chantier, voir CLAUDE.md), les
#    assertions "mecanisme" ci-dessous appellent donc Perception.percevoir
#    DIRECTEMENT, memes fixtures locales que test_perception.gd sans y
#    toucher ;
# 2. le cablage propre a banc_son.gd (fabriquer_sources/fabriquer_colon_son/
#    filtrer_par_frequence/sons_entendus), verrouille par un chemin REEL sur
#    data/banc_son.json + data/materiaux.json + data/types.json.
#
# AUCUN MECANISME DU COEUR TOUCHE AU-DELA DE LA GARDE DE FILTRE DE
# perception.gd (voir son en-tete) : objet.gd/monde.gd/banc_commun.gd
# restent inchanges, verrouilles par leurs propres tests.

const Perception = preload("res://scripts/perception.gd")
const Monde = preload("res://scripts/monde.gd")
const BancSon = preload("res://scripts/banc_son.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

# Catalogue minimal, meme patron que test_perception.gd:CATALOGUE -- un seul
# canal, la geometrie qui porte le nouveau filtre.
const CATALOGUE := {
	"ouie": { "geometrie": "propagation_obstacles" },
}

func _init() -> void:
	_mecanisme_source_forte_captee_source_faible_sous_seuil_ignoree()
	_mecanisme_hors_de_portee_aucune_source_captee()
	_mecanisme_intensite_attenuee_par_distance_pres_fort_loin_faible()
	_mecanisme_seuil_zero_capte_tout_seuil_un_ne_capte_rien()
	_mecanisme_seuil_par_defaut_zero_ne_change_rien_a_une_chose_sans_son_emis()
	_frequence_ultrason_ignoree_par_humain_captee_par_chien()
	_chemin_reel_donnees_banc_son_json()
	_chemin_reel_fabrication_fusionne_son_emis_et_frequence()
	_chemin_reel_colon_humain_entend_forte_et_moyenne_ignore_faible_et_ultrason()
	_chemin_reel_colon_chien_entend_aussi_l_ultrason()
	_position_source_mobile_oscille_sur_x_seul()
	_chemin_reel_source_mobile_traverse_le_seuil_avec_la_distance()
	_zoom_pour_cadrage_fait_tenir_tous_les_points_dans_l_ecran()
	_zoom_pour_cadrage_reste_borne_sur_une_scene_degeneree()
	_centre_de_cadrage_est_le_centre_de_la_boite_englobante()
	_points_de_cadrage_inclut_les_extremes_de_la_source_mobile()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_son.gd -- le filtre de seuil de perception.gd (canal ouie) retient une source " +
		"forte et ignore une source faible sous seuil, respecte la portee et l'attenuation par la " +
		"distance, seuil 0.0 capte tout / seuil 1.0 ne capte rien ; le filtre de frequence propre a " +
		"ce banc ignore l'ultrason pour un colon humain et le capte pour un colon chien ; chemin reel " +
		"(data/banc_son.json + materiaux.json + types.json) : son_emis/frequence sont fusionnes " +
		"correctement et les deux colons entendent exactement ce qui est attendu")
	quit(0)

# ---- Fixtures locales, mecanisme (Perception.percevoir direct) ----

func _chose_sonore(id: String, position: Vector3, son_emis: float) -> Dictionary:
	return {"id": id, "position": position, "proprietes": {"son_emis": son_emis}}

func _entite_ouie(portee: float, seuil: float) -> Dictionary:
	return {
		"position": Vector3.ZERO,
		"proprietes": {
			"canaux": ["ouie"],
			"canaux_config": {"ouie": {"portee": portee, "seuil": seuil}},
		},
	}

func _ids(perceptions: Array) -> Array:
	var ids: Array = []
	for entree in perceptions:
		ids.append(entree.chose.id)
	return ids

# ---- Mecanisme : seuil (scripts/perception.gd) ----

func _mecanisme_source_forte_captee_source_faible_sous_seuil_ignoree() -> void:
	var monde := Monde.new()
	var forte := _chose_sonore("forte", Vector3(50, 0, 0), 0.5)
	var faible := _chose_sonore("faible", Vector3(50, 0, 0), 0.05)
	monde.ajouter(forte, "chose", forte.position)
	monde.ajouter(faible, "chose", faible.position)

	# portee 100, distance 50 -> ratio d'attenuation 0.5 : forte attenuee
	# 0.25 (>= seuil 0.1, captee), faible attenuee 0.025 (< seuil, ignoree).
	var entite := _entite_ouie(100.0, 0.1)
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)
	var ids := _ids(perceptions)
	verif.v(ids.has("forte"), "une source forte (intensite attenuee au-dessus du seuil) doit etre captee")
	verif.v(not ids.has("faible"), "une source faible (intensite attenuee sous le seuil) doit etre ignoree")

func _mecanisme_hors_de_portee_aucune_source_captee() -> void:
	var monde := Monde.new()
	var loin := _chose_sonore("loin", Vector3(150, 0, 0), 0.5)
	monde.ajouter(loin, "chose", loin.position)

	# distance 150 > portee 100 : hors du rayon geometrique, avant meme le
	# filtre de seuil -- une intensite haute et un seuil nul ne suffisent pas.
	var entite := _entite_ouie(100.0, 0.0)
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)
	verif.v(perceptions.is_empty(), "une source hors de portee ne doit jamais etre captee, quelle que soit son intensite")

func _mecanisme_intensite_attenuee_par_distance_pres_fort_loin_faible() -> void:
	var monde := Monde.new()
	var pres := _chose_sonore("pres", Vector3(20, 0, 0), 0.5)
	var loin := _chose_sonore("loin", Vector3(90, 0, 0), 0.5)
	monde.ajouter(pres, "chose", pres.position)
	monde.ajouter(loin, "chose", loin.position)

	# MEME son_emis (0.5), portee 100, seuil 0.2 : pres (d=20) attenuee
	# 0.5*(1-0.2)=0.4 >= seuil, capte ; loin (d=90) attenuee 0.5*(1-0.9)=0.05
	# < seuil, ignore -- preuve que la distance seule fait basculer le
	# resultat, a intensite de base identique.
	var entite := _entite_ouie(100.0, 0.2)
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)
	var ids := _ids(perceptions)
	verif.v(ids.has("pres"), "une source proche doit rester captee (intensite attenuee peu reduite)")
	verif.v(not ids.has("loin"), "la MEME source, plus loin, doit devenir ignoree (intensite attenuee sous le seuil)")

func _mecanisme_seuil_zero_capte_tout_seuil_un_ne_capte_rien() -> void:
	var monde := Monde.new()
	var faible := _chose_sonore("faible", Vector3(50, 0, 0), 0.01)
	var forte := _chose_sonore("forte", Vector3(50, 0, 0), 0.5)
	monde.ajouter(faible, "chose", faible.position)
	monde.ajouter(forte, "chose", forte.position)

	var entite_permissive := _entite_ouie(100.0, 0.0)
	var tout := _ids(Perception.percevoir(entite_permissive, monde, CATALOGUE))
	verif.v(tout.has("faible") and tout.has("forte"), "seuil 0.0 doit capter toute source d'intensite non negative, meme tres faible")

	var entite_stricte := _entite_ouie(100.0, 1.0)
	var rien := _ids(Perception.percevoir(entite_stricte, monde, CATALOGUE))
	verif.v(rien.is_empty(), "seuil 1.0 ne doit capter aucune source de ce depot (aucune n'atteint une intensite attenuee de 1.0)")

func _mecanisme_seuil_par_defaut_zero_ne_change_rien_a_une_chose_sans_son_emis() -> void:
	# NON-REGRESSION : une chose sans "son_emis" (tout le contenu du depot
	# avant ce chantier) reste captee comme avant -- son_emis par defaut
	# 0.0, seuil par defaut 0.0 (canaux_config.ouie sur tout type existant
	# de data/types.json) : 0.0 < 0.0 est faux, rien n'est jamais retire.
	var monde := Monde.new()
	var muette := {"id": "muette", "position": Vector3(50, 0, 0), "proprietes": {}}
	monde.ajouter(muette, "chose", muette.position)

	var entite := _entite_ouie(100.0, 0.0)
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)
	verif.v(_ids(perceptions).has("muette"), "une chose sans son_emis doit rester captee sous le seuil par defaut (0.0)")

# ---- Frequence (scripts/banc_son.gd, propre a ce banc) ----

func _frequence_ultrason_ignoree_par_humain_captee_par_chien() -> void:
	var monde := Monde.new()
	var ultrason := _chose_sonore("ultrason", Vector3(50, 0, 0), 0.5)
	ultrason.proprietes["frequence"] = 30000.0
	monde.ajouter(ultrason, "chose", ultrason.position)

	var entite := _entite_ouie(100.0, 0.1)
	var humain := BancSon.sons_entendus(entite, monde, CATALOGUE, 20.0, 20000.0)
	var chien := BancSon.sons_entendus(entite, monde, CATALOGUE, 20.0, 45000.0)
	verif.v(not humain.has("ultrason"), "un ultrason (30000 Hz) doit etre ignore par une plage humaine (20-20000 Hz)")
	verif.v(chien.has("ultrason"), "le MEME ultrason doit etre capte par une plage chien (20-45000 Hz)")

# ---- Chemin REEL : data/banc_son.json + materiaux.json + types.json ----

func _charger(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _config() -> Dictionary:
	return _charger("res://data/banc_son.json")

func _materiaux() -> Dictionary:
	return _charger("res://data/materiaux.json")

func _proprietes_immuables() -> Array:
	return _charger("res://data/proprietes_immuables_composition.json").get("proprietes", [])

func _catalogue_types() -> Dictionary:
	var config := _config()
	var types_partages: Dictionary = _charger("res://data/types.json")
	var table: Dictionary = config.get("types", {}).duplicate(true)
	table["objet_physique"] = types_partages.get("objet_physique", {})
	table["dynamique"] = types_partages.get("dynamique", {})
	table["percevant"] = types_partages.get("percevant", {})
	table["agent"] = types_partages.get("agent", {})
	table["colon"] = types_partages.get("colon", {})
	return table

func _catalogue_canaux() -> Dictionary:
	return _charger("res://data/canaux.json")

func _par_id(objets: Array, id: String) -> Dictionary:
	for objet in objets:
		if objet.id == id:
			return objet
	return {}

func _monde_reel() -> Dictionary:
	var config := _config()
	var table := _catalogue_types()
	var sources := BancSon.fabriquer_sources(config.sources, table, _materiaux(), _proprietes_immuables())
	var colons := BancSon.fabriquer_colons(config.colons, table)
	var monde := Monde.new()
	for source in sources:
		monde.ajouter(source, "source", source.position)
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)
	return {"monde": monde, "sources": sources, "colons": colons}

func _donnees_reelles_banc_son_json() -> void:
	var config := _config()
	verif.v(config.sources.size() == 9, "data/banc_son.json doit declarer neuf sources (quatre par grappe, plus source_mobile_humain)")
	verif.v(config.colons.size() == 2, "data/banc_son.json doit declarer deux colons (colon_humain, colon_chien)")
	verif.v(config.colons.colon_humain.ouie_surcharge.frequence_max < config.colons.colon_chien.ouie_surcharge.frequence_max,
		"colon_humain doit avoir une frequence_max strictement inferieure a colon_chien")

func _chemin_reel_donnees_banc_son_json() -> void:
	_donnees_reelles_banc_son_json()

func _chemin_reel_fabrication_fusionne_son_emis_et_frequence() -> void:
	var reel := _monde_reel()
	var sources: Array = reel.sources
	var forte := _par_id(sources, "source_forte_humain")
	var moyenne := _par_id(sources, "source_moyenne_humain")
	var faible := _par_id(sources, "source_faible_humain")
	var ultrason := _par_id(sources, "source_ultrason_humain")

	verif.v(is_equal_approx(forte.proprietes.son_emis, 0.5), "chemin reel : source_forte (fer) doit fusionner son_emis=0.5")
	verif.v(is_equal_approx(moyenne.proprietes.son_emis, 0.1), "chemin reel : source_moyenne (bois) doit fusionner son_emis=0.1")
	verif.v(is_equal_approx(faible.proprietes.son_emis, 0.05), "chemin reel : source_faible (pierre) doit fusionner son_emis=0.05")
	verif.v(is_equal_approx(ultrason.proprietes.son_emis, forte.proprietes.son_emis),
		"chemin reel : source_ultrason et source_forte partagent le MEME son_emis (fer) -- seule la frequence les distingue")
	verif.v(is_equal_approx(ultrason.proprietes.frequence, 30000.0), "chemin reel : source_ultrason doit porter frequence=30000.0")
	verif.v(is_equal_approx(forte.proprietes.frequence, 200.0), "chemin reel : source_forte doit porter frequence=200.0")

	var reel_colons: Array = reel.colons
	var colon_humain := _par_id(reel_colons, "colon_humain")
	verif.v(is_equal_approx(colon_humain.proprietes.canaux_config.ouie.seuil, 0.04), "chemin reel : colon_humain doit porter le seuil surcharge (0.04)")
	verif.v(is_equal_approx(colon_humain.proprietes.canaux_config.ouie.portee, 600.0), "chemin reel : colon_humain doit garder la portee ouie par defaut du type colon (600.0), jamais surchargee")

func _chemin_reel_colon_humain_entend_forte_et_moyenne_ignore_faible_et_ultrason() -> void:
	var reel := _monde_reel()
	var colon_humain := _par_id(reel.colons, "colon_humain")
	var ouie: Dictionary = colon_humain.proprietes.canaux_config.ouie
	var entendu := BancSon.sons_entendus(colon_humain, reel.monde, _catalogue_canaux(), ouie.frequence_min, ouie.frequence_max)

	verif.v(entendu.has("source_forte_humain"), "colon_humain doit entendre source_forte_humain")
	verif.v(entendu.has("source_moyenne_humain"), "colon_humain doit entendre source_moyenne_humain")
	verif.v(not entendu.has("source_faible_humain"), "colon_humain ne doit PAS entendre source_faible_humain (intensite attenuee sous son seuil)")
	verif.v(not entendu.has("source_ultrason_humain"), "colon_humain ne doit PAS entendre source_ultrason_humain (frequence hors de sa plage)")

func _chemin_reel_colon_chien_entend_aussi_l_ultrason() -> void:
	var reel := _monde_reel()
	var colon_chien := _par_id(reel.colons, "colon_chien")
	var ouie: Dictionary = colon_chien.proprietes.canaux_config.ouie
	var entendu := BancSon.sons_entendus(colon_chien, reel.monde, _catalogue_canaux(), ouie.frequence_min, ouie.frequence_max)

	verif.v(entendu.has("source_forte_chien"), "colon_chien doit entendre source_forte_chien")
	verif.v(entendu.has("source_moyenne_chien"), "colon_chien doit entendre source_moyenne_chien")
	verif.v(not entendu.has("source_faible_chien"), "colon_chien ne doit PAS entendre source_faible_chien (intensite attenuee sous son seuil, MEME seuil que colon_humain)")
	verif.v(entendu.has("source_ultrason_chien"), "colon_chien DOIT entendre source_ultrason_chien (frequence dans sa plage, contrairement a colon_humain)")

# ---- Source mobile (banc_son.gd:position_source_mobile, PURE) ----

func _position_source_mobile_oscille_sur_x_seul() -> void:
	var a_zero := BancSon.position_source_mobile(0.0, 400.0, 200.0, 6.0)
	verif.v(is_equal_approx(a_zero.x, 0.0), "a t=0, x doit valoir 0.0 (sin(0)=0)")
	verif.v(is_equal_approx(a_zero.y, 200.0), "y doit rester fixe a y_fixe, quel que soit t")

	var au_quart := BancSon.position_source_mobile(1.5, 400.0, 200.0, 6.0)
	verif.v(is_equal_approx(au_quart.x, 400.0), "a t=periode/4 (1.5s sur 6.0s), x doit atteindre l'amplitude maximale (sin(pi/2)=1)")
	verif.v(is_equal_approx(au_quart.z, 0.0), "z doit toujours rester a 0.0 (pas de verticalite dans ce banc)")

# ---- Chemin REEL : source_mobile_humain traverse le seuil avec la distance ----

func _chemin_reel_source_mobile_traverse_le_seuil_avec_la_distance() -> void:
	var reel := _monde_reel()
	var colon_humain := _par_id(reel.colons, "colon_humain")
	var mobile := _par_id(reel.sources, "source_mobile_humain")
	var mouv: Dictionary = _config().mouvement_source_mobile
	var ouie: Dictionary = colon_humain.proprietes.canaux_config.ouie

	mobile.position = BancSon.position_source_mobile(0.0, mouv.amplitude_x, mouv.y_fixe, mouv.periode)
	var pres := BancSon.sons_entendus(colon_humain, reel.monde, _catalogue_canaux(), ouie.frequence_min, ouie.frequence_max)
	verif.v(pres.has("source_mobile_humain"), "chemin reel : source_mobile_humain proche (t=0, distance 200) doit etre entendue")

	mobile.position = BancSon.position_source_mobile(mouv.periode / 4.0, mouv.amplitude_x, mouv.y_fixe, mouv.periode)
	var loin := BancSon.sons_entendus(colon_humain, reel.monde, _catalogue_canaux(), ouie.frequence_min, ouie.frequence_max)
	verif.v(not loin.has("source_mobile_humain"), "chemin reel : la MEME source_mobile_humain, eloignee (t=periode/4, distance ~447), ne doit plus etre entendue")

# ---- Cadrage camera (banc_son.gd:zoom_pour_cadrage/centre_de_cadrage/points_de_cadrage, PURES) ----
# Bug visuel corrige (retour Yael) : la camera doit desormais cadrer TOUT
# le banc a partir des positions REELLES, jamais d'un zoom/position fige
# lus depuis la donnee.

func _zoom_pour_cadrage_fait_tenir_tous_les_points_dans_l_ecran() -> void:
	var points: Array = [Vector3(-1000.0, 0.0, 0.0), Vector3(1000.0, 0.0, 0.0), Vector3(0.0, 200.0, 0.0), Vector3(0.0, -200.0, 0.0)]
	var ecran := Vector2(1000.0, 1000.0)
	var zoom := BancSon.zoom_pour_cadrage(points, 100.0, ecran)
	# etendue X = 2000 + 2*100 = 2200, etendue Y = 400 + 2*100 = 600 ->
	# zoom limite par X : 1000.0/2200.0.
	verif.v(is_equal_approx(zoom, 1000.0 / 2200.0), "le zoom doit etre limite par la dimension la plus large (ici X), pour que TOUT tienne a l'ecran")

func _zoom_pour_cadrage_reste_borne_sur_une_scene_degeneree() -> void:
	var un_seul_point: Array = [Vector3(50.0, 50.0, 0.0)]
	verif.v(BancSon.zoom_pour_cadrage(un_seul_point, 100.0, Vector2(1000.0, 1000.0)) > 0.0, "un seul point (etendue nulle) ne doit jamais produire un zoom nul ou negatif")

	var points_confondus: Array = [Vector3(9999999.0, 0.0, 0.0), Vector3(-9999999.0, 0.0, 0.0)]
	var zoom_extreme := BancSon.zoom_pour_cadrage(points_confondus, 100.0, Vector2(1000.0, 1000.0))
	verif.v(zoom_extreme >= 0.05 and zoom_extreme <= 2.0, "le zoom doit toujours rester dans [ZOOM_MIN, ZOOM_MAX], meme sur une etendue demesuree")

func _centre_de_cadrage_est_le_centre_de_la_boite_englobante() -> void:
	var points: Array = [Vector3(-200.0, -100.0, 0.0), Vector3(600.0, 300.0, 0.0)]
	var centre := BancSon.centre_de_cadrage(points)
	verif.v(is_equal_approx(centre.x, 200.0) and is_equal_approx(centre.y, 100.0), "le centre doit etre le milieu exact de la boite englobante, pas un barycentre des points")

func _points_de_cadrage_inclut_les_extremes_de_la_source_mobile() -> void:
	var mouvement := {"id": "source_mobile_humain", "amplitude_x": 400.0, "y_fixe": 200.0, "periode": 6.0}
	var points := BancSon.points_de_cadrage([], [], mouvement)
	var a_x_positif := false
	var a_x_negatif := false
	for p in points:
		if is_equal_approx(p.x, 400.0) and is_equal_approx(p.y, 200.0):
			a_x_positif = true
		if is_equal_approx(p.x, -400.0) and is_equal_approx(p.y, 200.0):
			a_x_negatif = true
	verif.v(a_x_positif and a_x_negatif, "les deux extremes de l'oscillation de source_mobile_humain doivent etre cadres, pas seulement sa position de depart")
