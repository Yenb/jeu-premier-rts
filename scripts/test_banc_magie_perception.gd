extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_magie_perception.gd
#
# Verrouille DEUX choses a la fois, chantier « sensibilite_magique --
# perception magique » :
# 1. le canal "magie" de data/canaux.json (geometrie propagation_obstacles,
#    propriete_emission "force_magique", propriete_obstacle "opacite") --
#    AUCUNE ligne de scripts/perception.gd modifiee par CE chantier (le
#    mecanisme sous-jacent, propriete_emission configurable, a ete livre par
#    un chantier SEPARE, anterieur -- voir docs/ETAT.md) : les assertions
#    "mecanisme" ci-dessous appellent Perception.percevoir DIRECTEMENT,
#    memes fixtures locales que test_banc_son.gd, pour prouver que le canal
#    "magie" se comporte EXACTEMENT comme "ouie" sur le meme mecanisme ;
# 2. le cablage propre a banc_magie_perception.gd (fabriquer_sources/
#    fabriquer_colon_magie/captures_magie/sources_percues), verrouille par
#    un chemin REEL sur data/banc_magie_perception.json + materiaux.json +
#    types.json.
#
# AUCUN MECANISME DU COEUR TOUCHE PAR CE CHANTIER : perception.gd/
# charge.gd/etat_effectif.gd/objet.gd/monde.gd/banc_commun.gd restent
# inchanges, verrouilles par leurs propres tests.
#
# Chantier « rendu lisible de banc_magie_perception » (session ulterieure) :
# AJOUTE des tests pour les fonctions PURES de disposition d'affichage
# (position_colonne/positions_affichage/decalage_*), qui lisent
# EXCLUSIVEMENT data/banc_magie_perception.json:affichage -- jamais
# "sources"/"colons.*.position" (la position LOGIQUE, verrouillee par les
# tests mecanisme/chemin reel ci-dessus, INCHANGES par ce chantier).

const Perception = preload("res://scripts/perception.gd")
const Monde = preload("res://scripts/monde.gd")
const BancMagie = preload("res://scripts/banc_magie_perception.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

# Catalogues minimaux, meme patron que test_banc_son.gd:CATALOGUE.
const CATALOGUE := {
	"magie": { "geometrie": "propagation_obstacles", "propriete_emission": "force_magique" },
}
const CATALOGUE_AVEC_OBSTACLE := {
	"magie": { "geometrie": "propagation_obstacles", "propriete_emission": "force_magique", "propriete_obstacle": "opacite", "largeur_obstacle": 40.0 },
}

func _init() -> void:
	_mecanisme_source_forte_captee_source_faible_sous_seuil_ignoree()
	_mecanisme_hors_de_portee_aucune_source_captee()
	_mecanisme_seuil_zero_capte_meme_une_intensite_nulle()
	_mecanisme_force_magique_absente_jamais_captee_avec_seuil_positif()
	_mecanisme_obstacle_opaque_bloque_totalement_le_champ()
	_chemin_reel_fabrication_fusionne_force_magique()
	_chemin_reel_mage_percoit_les_quatre_sources_de_son_cluster()
	_chemin_reel_guerrier_percoit_seulement_bois_et_demo()
	_chemin_reel_source_neutre_jamais_percue_par_le_mage()
	_chemin_reel_source_lointaine_jamais_percue()
	_zoom_pour_cadrage_fait_tenir_tous_les_points_dans_l_ecran()
	_zoom_pour_cadrage_reste_borne_sur_une_scene_degeneree()
	_centre_de_cadrage_est_le_centre_de_la_boite_englobante()
	_position_colonne_empile_verticalement_centree_et_espacee()
	_position_colonne_vide_ne_rend_rien()
	_positions_affichage_compose_colons_colonnes_et_isolees()
	_positions_affichage_ignore_la_position_logique()
	_decalages_labels_ordonnes_nom_au_dessus_de_valeur_au_dessus_du_carre()
	_decalage_dessous_est_toujours_positif()
	_texte_valeur_colon_formate_le_seuil()
	_chemin_reel_position_affichage_separe_le_mage_et_le_guerrier_de_400_unites_au_moins()
	_chemin_reel_positions_affichage_couvre_toutes_les_sources_et_les_deux_colons()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_magie_perception.gd -- le canal magie (data/canaux.json, propriete_emission " +
		"force_magique, propriete_obstacle opacite) retient une source forte et ignore une source " +
		"faible sous seuil, respecte la portee, seuil 0.0 capte une intensite nulle mais un seuil " +
		"positif ne capte jamais une source sans force_magique, un obstacle opaque bloque " +
		"totalement le champ ; chemin reel (data/banc_magie_perception.json + materiaux.json + " +
		"types.json) : force_magique est fusionnee correctement, le mage (seuil bas) percoit les " +
		"quatre sources de son cluster, le guerrier (seuil haut) n'en percoit que deux, la source " +
		"neutre (verre_demo, sans force_magique) et la source lointaine (hors portee) ne sont " +
		"jamais percues")
	quit(0)

# ---- Fixtures locales, mecanisme (Perception.percevoir direct) ----

func _chose_magique(id: String, position: Vector3, force_magique: float) -> Dictionary:
	return {"id": id, "position": position, "proprietes": {"force_magique": force_magique}}

func _obstacle(id: String, position: Vector3, opacite: float) -> Dictionary:
	return {"id": id, "position": position, "proprietes": {"opacite": opacite}}

func _entite_magie(portee: float, seuil: float) -> Dictionary:
	return {
		"position": Vector3.ZERO,
		"proprietes": {
			"canaux": ["magie"],
			"canaux_config": {"magie": {"portee": portee, "seuil": seuil}},
		},
	}

func _ids(perceptions: Array) -> Array:
	var ids: Array = []
	for entree in perceptions:
		ids.append(entree.chose.id)
	return ids

# ---- Mecanisme : le canal magie suit le meme filtre de seuil que ouie ----

func _mecanisme_source_forte_captee_source_faible_sous_seuil_ignoree() -> void:
	var monde := Monde.new()
	var forte := _chose_magique("forte", Vector3(50, 0, 0), 0.5)
	var faible := _chose_magique("faible", Vector3(50, 0, 0), 0.05)
	monde.ajouter(forte, "chose", forte.position)
	monde.ajouter(faible, "chose", faible.position)

	# portee 100, distance 50 -> ratio d'attenuation 0.5 : forte attenuee
	# 0.25 (>= seuil 0.1, captee), faible attenuee 0.025 (< seuil, ignoree).
	var entite := _entite_magie(100.0, 0.1)
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)
	var ids := _ids(perceptions)
	verif.v(ids.has("forte"), "une source magique forte (intensite attenuee au-dessus du seuil) doit etre captee")
	verif.v(not ids.has("faible"), "une source magique faible (intensite attenuee sous le seuil) doit etre ignoree")

func _mecanisme_hors_de_portee_aucune_source_captee() -> void:
	var monde := Monde.new()
	var loin := _chose_magique("loin", Vector3(150, 0, 0), 0.9)
	monde.ajouter(loin, "chose", loin.position)

	# distance 150 > portee 100 : hors du rayon geometrique, avant meme le
	# filtre de seuil -- une intensite haute et un seuil nul ne suffisent pas.
	var entite := _entite_magie(100.0, 0.0)
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)
	verif.v(perceptions.is_empty(), "une source magique hors de portee ne doit jamais etre captee, quelle que soit son intensite")

func _mecanisme_seuil_zero_capte_meme_une_intensite_nulle() -> void:
	var monde := Monde.new()
	var muette := {"id": "muette", "position": Vector3(50, 0, 0), "proprietes": {}}
	monde.ajouter(muette, "chose", muette.position)

	# NON-REGRESSION, meme patron que test_banc_son.gd : une chose sans
	# force_magique reste captee sous un seuil par defaut de 0.0 (0.0 < 0.0
	# est faux, rien n'est jamais retire).
	var entite := _entite_magie(100.0, 0.0)
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)
	verif.v(_ids(perceptions).has("muette"), "une chose sans force_magique doit rester captee sous le seuil par defaut (0.0)")

func _mecanisme_force_magique_absente_jamais_captee_avec_seuil_positif() -> void:
	var monde := Monde.new()
	var muette := {"id": "muette", "position": Vector3(10, 0, 0), "proprietes": {}}
	monde.ajouter(muette, "chose", muette.position)

	# A l'inverse du test precedent : des qu'un seuil STRICTEMENT POSITIF
	# est en jeu, une chose sans force_magique (0.0 par defaut generique)
	# n'est plus jamais captee -- meme tres proche, meme portee large.
	var entite := _entite_magie(600.0, 0.01)
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)
	verif.v(perceptions.is_empty(), "une chose sans force_magique ne doit jamais etre captee des qu'un seuil strictement positif est en jeu")

func _mecanisme_obstacle_opaque_bloque_totalement_le_champ() -> void:
	var monde_sans_mur := Monde.new()
	var source := _chose_magique("source", Vector3(0, 100, 0), 0.5)
	monde_sans_mur.ajouter(source, "chose", source.position)

	var entite := _entite_magie(200.0, 0.1)
	var sans_mur := Perception.percevoir(entite, monde_sans_mur, CATALOGUE_AVEC_OBSTACLE)
	verif.v(_ids(sans_mur).has("source"), "sans obstacle, la source magique doit etre captee (intensite attenuee au-dessus du seuil)")

	var monde_avec_mur := Monde.new()
	monde_avec_mur.ajouter(source, "chose", source.position)
	var mur := _obstacle("mur", Vector3(0, 50, 0), 1.0)
	monde_avec_mur.ajouter(mur, "chose", mur.position)
	var avec_mur := Perception.percevoir(entite, monde_avec_mur, CATALOGUE_AVEC_OBSTACLE)
	verif.v(not _ids(avec_mur).has("source"), "un mur opaque (opacite 1.0) positionne sur le segment doit bloquer TOTALEMENT le champ magique (meme mecanisme que ouie/absorption_sonore)")

# ---- Chemin REEL : data/banc_magie_perception.json + materiaux.json + types.json ----

func _charger(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _config() -> Dictionary:
	return _charger("res://data/banc_magie_perception.json")

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
	var sources := BancMagie.fabriquer_sources(config.sources, table, _materiaux(), _proprietes_immuables())
	var colons := BancMagie.fabriquer_colons(config.colons, table)
	var monde := Monde.new()
	for source in sources:
		monde.ajouter(source, "source", source.position)
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)
	return {"monde": monde, "sources": sources, "colons": colons}

func _chemin_reel_fabrication_fusionne_force_magique() -> void:
	var reel := _monde_reel()
	var sources: Array = reel.sources
	var bois := _par_id(sources, "source_bois_mage")
	var pierre := _par_id(sources, "source_pierre_mage")
	var fer := _par_id(sources, "source_fer_mage")
	var demo := _par_id(sources, "source_demo_mage")
	var neutre := _par_id(sources, "source_neutre_mage")

	verif.v(is_equal_approx(bois.proprietes.force_magique, 0.3), "chemin reel : source_bois_mage (bois) doit fusionner force_magique=0.3")
	verif.v(is_equal_approx(pierre.proprietes.force_magique, 0.1), "chemin reel : source_pierre_mage (pierre) doit fusionner force_magique=0.1")
	verif.v(is_equal_approx(fer.proprietes.force_magique, 0.05), "chemin reel : source_fer_mage (fer) doit fusionner force_magique=0.05")
	verif.v(is_equal_approx(demo.proprietes.force_magique, 0.9), "chemin reel : source_demo_mage (source_magique_demo) doit fusionner force_magique=0.9")
	verif.v(is_equal_approx(neutre.proprietes.get("force_magique", 0.0), 0.0), "chemin reel : source_neutre_mage (verre_demo, aucun force_magique declare) doit retomber sur 0.0 par defaut generique")

	var reel_colons: Array = reel.colons
	var mage := _par_id(reel_colons, "mage")
	var guerrier := _par_id(reel_colons, "guerrier")
	verif.v(mage.proprietes.canaux.has("magie"), "chemin reel : le colon mage doit porter 'magie' dans sa liste canaux")
	verif.v(is_equal_approx(mage.proprietes.canaux_config.magie.seuil, 0.02), "chemin reel : le colon mage doit porter le seuil bas (0.02)")
	verif.v(is_equal_approx(guerrier.proprietes.canaux_config.magie.seuil, 0.1), "chemin reel : le colon guerrier doit porter le seuil haut (0.1)")

func _chemin_reel_mage_percoit_les_quatre_sources_de_son_cluster() -> void:
	var reel := _monde_reel()
	var mage := _par_id(reel.colons, "mage")
	var percu := BancMagie.sources_percues(mage, reel.monde, _catalogue_canaux())

	verif.v(percu.has("source_bois_mage"), "le mage doit percevoir source_bois_mage")
	verif.v(percu.has("source_pierre_mage"), "le mage (seuil bas) doit percevoir source_pierre_mage")
	verif.v(percu.has("source_fer_mage"), "le mage (seuil bas) doit percevoir source_fer_mage, la plus faible du cluster")
	verif.v(percu.has("source_demo_mage"), "le mage doit percevoir source_demo_mage, la plus forte du cluster")

func _chemin_reel_guerrier_percoit_seulement_bois_et_demo() -> void:
	var reel := _monde_reel()
	var guerrier := _par_id(reel.colons, "guerrier")
	var percu := BancMagie.sources_percues(guerrier, reel.monde, _catalogue_canaux())

	verif.v(percu.has("source_bois_guerrier"), "le guerrier (seuil haut) doit percevoir source_bois_guerrier (forte)")
	verif.v(percu.has("source_demo_guerrier"), "le guerrier (seuil haut) doit percevoir source_demo_guerrier (tres forte)")
	verif.v(not percu.has("source_pierre_guerrier"), "le guerrier (seuil haut) ne doit PAS percevoir source_pierre_guerrier (intensite attenuee sous son seuil)")
	verif.v(not percu.has("source_fer_guerrier"), "le guerrier (seuil haut) ne doit PAS percevoir source_fer_guerrier, la plus faible")

func _chemin_reel_source_neutre_jamais_percue_par_le_mage() -> void:
	var reel := _monde_reel()
	var mage := _par_id(reel.colons, "mage")
	var percu := BancMagie.sources_percues(mage, reel.monde, _catalogue_canaux())
	verif.v(not percu.has("source_neutre_mage"), "source_neutre_mage (verre_demo, force_magique 0.0) ne doit jamais etre percue, meme par le colon au seuil le plus bas")

func _chemin_reel_source_lointaine_jamais_percue() -> void:
	var reel := _monde_reel()
	var mage := _par_id(reel.colons, "mage")
	var percu := BancMagie.sources_percues(mage, reel.monde, _catalogue_canaux())
	verif.v(not percu.has("source_lointaine_mage"), "source_lointaine_mage (hors de la portee 600.0) ne doit jamais etre percue, quelle que soit son intensite")

# ---- Cadrage camera (banc_magie_perception.gd:zoom_pour_cadrage/centre_de_cadrage, PURES) ----

func _zoom_pour_cadrage_fait_tenir_tous_les_points_dans_l_ecran() -> void:
	var points: Array = [Vector3(-1000.0, 0.0, 0.0), Vector3(1000.0, 0.0, 0.0), Vector3(0.0, 200.0, 0.0), Vector3(0.0, -200.0, 0.0)]
	var ecran := Vector2(1000.0, 1000.0)
	var zoom := BancMagie.zoom_pour_cadrage(points, 100.0, ecran)
	# etendue X = 2000 + 2*100 = 2200, etendue Y = 400 + 2*100 = 600 ->
	# zoom limite par X : 1000.0/2200.0.
	verif.v(is_equal_approx(zoom, 1000.0 / 2200.0), "le zoom doit etre limite par la dimension la plus large (ici X), pour que TOUT tienne a l'ecran")

func _zoom_pour_cadrage_reste_borne_sur_une_scene_degeneree() -> void:
	var un_seul_point: Array = [Vector3(50.0, 50.0, 0.0)]
	verif.v(BancMagie.zoom_pour_cadrage(un_seul_point, 100.0, Vector2(1000.0, 1000.0)) > 0.0, "un seul point (etendue nulle) ne doit jamais produire un zoom nul ou negatif")

	var points_confondus: Array = [Vector3(9999999.0, 0.0, 0.0), Vector3(-9999999.0, 0.0, 0.0)]
	var zoom_extreme := BancMagie.zoom_pour_cadrage(points_confondus, 100.0, Vector2(1000.0, 1000.0))
	verif.v(zoom_extreme >= 0.05 and zoom_extreme <= 2.0, "le zoom doit toujours rester dans [ZOOM_MIN, ZOOM_MAX], meme sur une etendue demesuree")

func _centre_de_cadrage_est_le_centre_de_la_boite_englobante() -> void:
	var points: Array = [Vector3(-200.0, -100.0, 0.0), Vector3(600.0, 300.0, 0.0)]
	var centre := BancMagie.centre_de_cadrage(points)
	verif.v(is_equal_approx(centre.x, 200.0) and is_equal_approx(centre.y, 100.0), "le centre doit etre le milieu exact de la boite englobante, pas un barycentre des points")

# ---- Disposition d'affichage (banc_magie_perception.gd:position_colonne/positions_affichage, PURES) ----
# Chantier « rendu lisible de banc_magie_perception » -- la position
# d'affichage est une donnee SEPAREE de la position logique (voir
# fixtures/tests ci-dessus, jamais touches par ce chantier).

func _position_colonne_empile_verticalement_centree_et_espacee() -> void:
	var ids: Array = ["a", "b", "c", "d", "e"]
	var resultat := BancMagie.position_colonne(Vector2(-250.0, 0.0), -260.0, ids, 100.0)
	verif.v(resultat.size() == 5, "position_colonne doit rendre une entree par id")
	for id in ids:
		verif.v(is_equal_approx(resultat[id].x, -510.0), "chaque source de la colonne doit partager le MEME x (centre.x + decalage_x), id '%s'" % id)
	# n=5 impair : l'element central (index 2, "c") reste EXACTEMENT sur
	# centre.y -- les quatre autres s'espacent de 100.0 de part et d'autre.
	verif.v(is_equal_approx(resultat.c.y, 0.0), "l'element central d'une colonne impaire doit rester exactement sur centre.y")
	verif.v(is_equal_approx(resultat.a.y, -200.0), "le premier element doit etre a 2*espacement au-dessus du centre")
	verif.v(is_equal_approx(resultat.b.y, -100.0), "le deuxieme element doit etre a 1*espacement au-dessus du centre")
	verif.v(is_equal_approx(resultat.d.y, 100.0), "le quatrieme element doit etre a 1*espacement en dessous du centre")
	verif.v(is_equal_approx(resultat.e.y, 200.0), "le dernier element doit etre a 2*espacement en dessous du centre")
	# Deux elements CONSECUTIFS de la colonne sont toujours espaces
	# EXACTEMENT de "espacement" (100.0 ici, dans la fourchette 80-100
	# demandee) -- jamais moins, jamais plus.
	verif.v(is_equal_approx(resultat.b.y - resultat.a.y, 100.0), "l'espacement entre deux sources consecutives doit etre exactement celui demande")
	verif.v(is_equal_approx(resultat.c.y - resultat.b.y, 100.0), "l'espacement entre deux sources consecutives doit etre exactement celui demande")

func _position_colonne_vide_ne_rend_rien() -> void:
	var resultat := BancMagie.position_colonne(Vector2(500.0, 0.0), 260.0, [], 100.0)
	verif.v(resultat.is_empty(), "une colonne sans id ne doit rendre aucune entree")

func _positions_affichage_compose_colons_colonnes_et_isolees() -> void:
	var affichage := {
		"colons": {
			"mage": {"position": [-250.0, 0.0], "decalage_colonne_x": -260.0, "sources": ["s1", "s2"]},
			"guerrier": {"position": [250.0, 0.0], "decalage_colonne_x": 260.0, "sources": ["s3"]},
		},
		"isolees": {"lointaine": [0.0, 300.0]},
	}
	var resultat := BancMagie.positions_affichage(affichage, 100.0)
	verif.v(resultat.has("mage") and resultat.has("guerrier"), "chaque colon doit avoir sa propre position d'affichage")
	verif.v(resultat.has("s1") and resultat.has("s2") and resultat.has("s3"), "chaque source listee dans une colonne doit avoir une position d'affichage")
	verif.v(resultat.has("lointaine"), "chaque source isolee doit avoir une position d'affichage")
	verif.v(is_equal_approx(resultat.mage.x, -250.0) and is_equal_approx(resultat.mage.y, 0.0), "la position du colon doit venir telle quelle de affichage.colons.<nom>.position")
	verif.v(is_equal_approx(resultat.lointaine.x, 0.0) and is_equal_approx(resultat.lointaine.y, 300.0), "la position d'une source isolee doit venir telle quelle de affichage.isolees")
	# Ecart HORIZONTAL entre les deux colons -- la tache exige au moins 400
	# unites.
	verif.v(absf(resultat.guerrier.x - resultat.mage.x) >= 400.0, "l'ecart horizontal entre mage et guerrier doit etre d'au moins 400 unites")

func _positions_affichage_ignore_la_position_logique() -> void:
	# Preuve structurelle que positions_affichage ne lit JAMAIS
	# "sources"/"colons.*.position" (la position LOGIQUE) -- seule la cle
	# "affichage" compte, meme si elle contredit totalement une position
	# logique par ailleurs. Un Dictionary sans aucune trace de position
	# logique produit exactement le meme resultat.
	var affichage := {"colons": {"mage": {"position": [-250.0, 0.0], "sources": []}}}
	var resultat := BancMagie.positions_affichage(affichage, 100.0)
	verif.v(is_equal_approx(resultat.mage.x, -250.0), "positions_affichage doit ignorer toute donnee autre que la cle 'affichage'")

func _decalages_labels_ordonnes_nom_au_dessus_de_valeur_au_dessus_du_carre() -> void:
	var zoom := 1.0
	var valeur := BancMagie.decalage_valeur_au_dessus(zoom)
	var nom := BancMagie.decalage_nom_au_dessus(zoom)
	# Tous deux NEGATIFS (au-dessus du carre, l'axe Y ecran croit vers le
	# bas) ; le nom, plus loin du carre, a un decalage PLUS NEGATIF (plus
	# haut a l'ecran) que la valeur, elle-meme collee au-dessus du carre.
	verif.v(valeur < 0.0, "le label de valeur au-dessus doit avoir un decalage negatif (au-dessus du carre)")
	verif.v(nom < valeur, "le label de nom doit etre PLUS HAUT que le label de valeur (decalage plus negatif)")

func _decalage_dessous_est_toujours_positif() -> void:
	verif.v(BancMagie.decalage_dessous(1.0) > 0.0, "le decalage d'un label EN DESSOUS du carre doit toujours etre positif")
	verif.v(BancMagie.decalage_dessous(0.5) > 0.0, "le decalage en dessous doit rester positif a tout zoom raisonnable")

func _texte_valeur_colon_formate_le_seuil() -> void:
	verif.v(BancMagie.texte_valeur_colon(0.02) == "seuil=0.02", "texte_valeur_colon doit formater le seuil a deux decimales")
	verif.v(BancMagie.texte_valeur_colon(0.1) == "seuil=0.10", "texte_valeur_colon doit formater le seuil a deux decimales, y compris un zero final")

# ---- Chemin REEL : data/banc_magie_perception.json:affichage ----

func _chemin_reel_position_affichage_separe_le_mage_et_le_guerrier_de_400_unites_au_moins() -> void:
	var affichage: Dictionary = _config().get("affichage", {})
	var positions := BancMagie.positions_affichage(affichage, 100.0)
	verif.v(absf(positions.guerrier.x - positions.mage.x) >= 400.0, "chemin reel : l'ecart horizontal entre le mage et le guerrier doit etre d'au moins 400 unites, comme demande")

func _chemin_reel_positions_affichage_couvre_toutes_les_sources_et_les_deux_colons() -> void:
	var config := _config()
	var affichage: Dictionary = config.get("affichage", {})
	var positions := BancMagie.positions_affichage(affichage, 100.0)
	for decl in config.sources:
		verif.v(positions.has(decl.id), "chemin reel : la source '%s' doit avoir une position d'affichage" % decl.id)
	verif.v(positions.has("mage") and positions.has("guerrier"), "chemin reel : les deux colons doivent avoir une position d'affichage")
