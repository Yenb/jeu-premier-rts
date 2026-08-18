extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_perception.gd
#
# Verrouille perception.gd (PHASE 3.5, dispatcher multi-canal) : un cas
# par geometrie (cone_oriente/propagation_obstacles/sphere_directionnelle/
# contact), une chose captee par deux canaux ne ressort qu'UNE fois avec
# les deux noms dans "canaux", un canal hors domaine invente ("gravitique"
# / "masse") traverse le meme code que les canaux reels, et trois cas
# limites : entite aveugle (canaux sans "vue"), canal a portee 0.0,
# canal cone a angle 360 (degenere en sphere). Plus les deux gardes
# structurelles : "canaux" absent de proprietes, et un nom de canal
# reference par l'entite mais absent du catalogue. Plus l'AUTO-EXCLUSION
# (chantier "colon saillant") : une entite qui percoit, elle-meme
# enregistree dans le monde, ne se retrouve jamais dans ses propres
# perceptions -- un cas via _sphere_brute (sphere/contact/cone a 360),
# un cas dedie au cone a angle < 360 (sa propre boucle, ne passe pas par
# _sphere_brute).
#
# Chantier "vent" (voir scripts/vent.gd) : cablage sur sphere_directionnelle
# SEULE (odorat aujourd'hui) -- sans catalogue_vent (defaut {}), comportement
# RIGOUREUSEMENT identique (verifie au chiffre pres, pas seulement au nombre
# d'entrees) ; une source sous le vent capturee au-dela de sa portee de base ;
# la meme source contre le vent qui redevient non capturee ; un vent qui
# tourne reellement au fil du temps change ce qui est capture, sans hypothese
# sur le sens de la rotation ; une source locale de perturbation qui ne
# modifie la capture que DANS son rayon, jamais au-dela ; un cas hors domaine
# sur le canal invente "gravitique" (meme geometrie sphere_directionnelle),
# pour prouver que le cablage est fait au niveau de la GEOMETRIE, jamais du
# nom du canal.

const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const Vent = preload("res://scripts/vent.gd")
const Verif = preload("res://scripts/verif.gd")

# Catalogues de vent LOCAUX a ce fichier (chantier "vent") -- jamais
# data/vent.json ici, ce test verrouille le CABLAGE (perception.gd), pas les
# valeurs reelles (voir test_vent.gd pour le mecanisme lui-meme, et sa section
# "chemin reel" pour data/vent.json). Vent CONSTANT (sans variation_lente ni
# rafales) : direction (1,0,0), force 10.0 = reference_force -> intensite
# directionnelle PLEINE (1.0) a tout instant, pour rendre les distances de
# capture predictibles au chiffre pres.
const CATALOGUE_VENT_CONSTANT := {
	"defaut": {
		"fond": {"direction": {"x": 1.0, "y": 0.0, "z": 0.0}, "force": 10.0},
		"directionnel": {"reference_force": 10.0, "facteur_max_sous_vent": 2.0, "facteur_min_contre_vent": 0.4},
	}
}

# Catalogue LOCAL a ce fichier (chantier "occlusion") -- "ouie" seule porte
# propriete_obstacle/largeur_obstacle, jamais ajoute a CATALOGUE (partage par
# tous les autres tests de ce fichier) pour ne risquer AUCUNE regression sur
# eux : ils continuent d'utiliser CATALOGUE sans ces deux champs, donc
# _facteur_obstacles y reste court-circuite a 1.0 (propriete_obstacle vide),
# comportement rigoureusement identique a avant ce chantier. largeur_obstacle
# 10.0 : tolerance laterale de demonstration, jamais lue en dehors des tests
# ci-dessous.
const CATALOGUE_OCCLUSION := {
	"ouie": { "geometrie": "propagation_obstacles", "propriete_obstacle": "absorption_sonore", "largeur_obstacle": 10.0 },
}

# Catalogue LOCAL (chantier "propriete_emission configurable par canal") --
# canal fictif "radiation", SANS AUCUN RAPPORT avec le son, qui declare
# propriete_emission: "force_radiation" au lieu du defaut "son_emis". Jamais
# ajoute a CATALOGUE_OCCLUSION (qui ne declare pas propriete_emission,
# reposant donc sur le defaut "son_emis" -- couvert par les cinq tests
# d'occlusion ci-dessus, aucun modifie par ce chantier).
const CATALOGUE_EMISSION_CONFIGURABLE := {
	"radiation": { "geometrie": "propagation_obstacles", "propriete_emission": "force_radiation" },
}

# Vent qui TOURNE reellement (variation_lente active) -- direction (1,0,0) a
# t=0, tourne de +90/-90 deg au fil du temps (periode 40s).
const CATALOGUE_VENT_ROTATIF := {
	"defaut": {
		"fond": {"direction": {"x": 1.0, "y": 0.0, "z": 0.0}, "force": 10.0},
		"variation_lente": {"amplitude_angle": 90.0, "periode_angle": 40.0},
		"directionnel": {"reference_force": 10.0, "facteur_max_sous_vent": 3.0, "facteur_min_contre_vent": 1.0},
	}
}

var verif := Verif.new()

# Catalogue local aux tests -- memes geometries que data/canaux.json,
# proprietes_captees omises volontairement (metadonnee non lue par
# perception.gd, voir son en-tete).
const CATALOGUE := {
	"vue":        { "geometrie": "cone_oriente" },
	"ouie":       { "geometrie": "propagation_obstacles" },
	"odorat":     { "geometrie": "sphere_directionnelle" },
	"toucher":    { "geometrie": "contact" },
	"gravitique": { "geometrie": "sphere_directionnelle" },
}

func _chose(id: String, position: Vector3, proprietes: Dictionary = {}) -> Dictionary:
	return { "id": id, "position": position, "proprietes": proprietes }


# "canaux_config" recu ici est le Dictionary nom_canal -> reglages (forme
# des appels existants dans ce fichier, inchangee) -- forme A (chantier
# "un seul patron de reference de catalogue") : la liste "canaux" (les
# NOMS) se derive de ses cles, "canaux_config" (les REGLAGES) reste le
# Dictionary lui-meme, les deux separes sur proprietes comme sur une
# entite reelle (voir data/types.json:percevant).
func _entite(position: Vector3, canaux_config: Dictionary, orientation = null) -> Dictionary:
	var proprietes := { "canaux": canaux_config.keys(), "canaux_config": canaux_config }
	if orientation != null:
		proprietes["orientation"] = orientation
	return { "position": position, "proprietes": proprietes }

func _init() -> void:
	_cone_oriente_filtre_par_angle_et_portee()
	_propagation_obstacles_est_omnidirectionnelle_dans_sa_portee()
	_sphere_directionnelle_est_omnidirectionnelle_dans_sa_portee()
	_contact_ne_capte_qu_a_tres_courte_portee()
	_chose_captee_par_deux_canaux_ne_ressort_qu_une_fois()
	_hors_domaine_canal_gravitique_capte_masse()
	_entite_aveugle_sans_vue_ne_percoit_jamais_par_ce_canal()
	_canal_a_portee_zero_ne_capte_rien()
	_canal_cone_a_angle_360_degenere_en_sphere()
	_canaux_absent_de_proprietes_alarme_et_rend_vide()
	_canal_reference_absent_du_catalogue_alarme_et_ignore_ce_canal_seul()
	_entite_est_exclue_de_ses_propres_perceptions_sphere_brute()
	_entite_est_exclue_de_ses_propres_perceptions_cone_etroit()
	_sans_vent_le_comportement_de_lodorat_est_rigoureusement_identique()
	_source_sous_le_vent_captee_la_ou_elle_ne_letait_pas()
	_meme_source_contre_le_vent_devient_non_captee()
	_le_vent_qui_tourne_change_reellement_ce_qui_est_capte_au_fil_du_temps()
	_source_locale_de_vent_modifie_la_capture_dans_son_rayon_et_pas_au_dela()
	_hors_domaine_vent_sur_canal_invente_gravitique()
	_mur_obstacle_bloque_le_son()
	_mur_retire_la_perception_revient()
	_deux_murs_cumulent_leur_attenuation()
	_mur_transparent_ne_bloque_rien()
	_mur_a_cote_de_la_ligne_ne_bloque_rien()
	_canal_fictif_lit_sa_propre_propriete_emission()
	_geometrie_inconnue_alarme_et_ne_capte_rien_sans_toucher_aux_autres()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: quatre geometries verrouillees, fusion multi-canal sans doublon, " +
		"hors domaine (gravitique/masse), cas limites (aveugle, portee 0, angle 360), " +
		"gardes structurelles (canaux absent, reference de canal absente du catalogue), " +
		"auto-exclusion de l'entite qui percoit (sphere_brute et cone etroit), " +
		"chantier vent : neutralite exacte sans catalogue_vent, portee allongee sous " +
		"le vent, reduite contre le vent, rotation reelle au fil du temps, source " +
		"locale confinee a son rayon, hors domaine (gravitique), " +
		"chantier occlusion : un mur (pierre, absorption_sonore 0.05) sur le segment " +
		"bloque un son qui passait de justesse, retire il repasse, deux murs cumulent " +
		"leur attenuation la ou un seul ne suffit pas, un mur transparent (0.0) ne " +
		"bloque rien, un mur a cote de la ligne (hors largeur_obstacle) ne bloque rien, " +
		"chantier propriete_emission configurable : un canal fictif ('radiation') " +
		"lit sa propre propriete_emission ('force_radiation'), jamais 'son_emis'")
	quit(0)

# ---- Une geometrie par cas ----

func _cone_oriente_filtre_par_angle_et_portee() -> void:
	var devant := _chose("devant", Vector3(0, 0, 50))
	var derriere := _chose("derriere", Vector3(0, 0, -50))
	var cote := _chose("cote", Vector3(50, 0, 0))
	var hors_portee := _chose("hors_portee", Vector3(0, 0, 150))

	var monde := Monde.new()
	monde.ajouter(devant, "chose", devant.position)
	monde.ajouter(derriere, "chose", derriere.position)
	monde.ajouter(cote, "chose", cote.position)
	monde.ajouter(hors_portee, "chose", hors_portee.position)

	var entite := _entite(Vector3.ZERO, { "vue": { "portee": 100.0, "angle": 90.0 } }, Vector3(0, 0, 1))
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)

	verif.v(perceptions.size() == 1, "cone_oriente : seul 'devant' doit etre dans le cone ET la portee, recu %d" % perceptions.size())
	if perceptions.size() == 1:
		verif.v(perceptions[0].chose.id == "devant", "cone_oriente : la seule chose percue doit etre 'devant'")
		verif.v(perceptions[0].canaux == ["vue"], "cone_oriente : canaux doit porter exactement ['vue']")

func _propagation_obstacles_est_omnidirectionnelle_dans_sa_portee() -> void:
	var derriere_proche := _chose("derriere_proche", Vector3(0, 0, -30))
	var loin := _chose("loin", Vector3(0, 0, 200))

	var monde := Monde.new()
	monde.ajouter(derriere_proche, "chose", derriere_proche.position)
	monde.ajouter(loin, "chose", loin.position)

	var entite := _entite(Vector3.ZERO, { "ouie": { "portee": 80.0 } }, Vector3(0, 0, 1))
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)

	verif.v(perceptions.size() == 1, "propagation_obstacles : aucun filtre d'angle, mais la portee s'applique")
	if perceptions.size() == 1:
		verif.v(perceptions[0].chose.id == "derriere_proche",
			"propagation_obstacles : une chose DERRIERE l'entite mais a portee doit quand meme etre captee")

func _sphere_directionnelle_est_omnidirectionnelle_dans_sa_portee() -> void:
	var proche := _chose("proche", Vector3(40, 0, 0))
	var loin := _chose("loin", Vector3(400, 0, 0))

	var monde := Monde.new()
	monde.ajouter(proche, "chose", proche.position)
	monde.ajouter(loin, "chose", loin.position)

	var entite := _entite(Vector3.ZERO, { "odorat": { "portee": 100.0 } })
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)

	verif.v(perceptions.size() == 1 and perceptions[0].chose.id == "proche",
		"sphere_directionnelle : seule la chose a portee doit etre captee")

func _contact_ne_capte_qu_a_tres_courte_portee() -> void:
	var au_contact := _chose("au_contact", Vector3(3, 0, 0))
	var trop_loin := _chose("trop_loin", Vector3(10, 0, 0))

	var monde := Monde.new()
	monde.ajouter(au_contact, "chose", au_contact.position)
	monde.ajouter(trop_loin, "chose", trop_loin.position)

	var entite := _entite(Vector3.ZERO, { "toucher": { "portee": 5.0 } })
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)

	verif.v(perceptions.size() == 1 and perceptions[0].chose.id == "au_contact",
		"contact : seule la chose a moins de 5.0 doit etre captee")

# ---- Fusion multi-canal ----

func _chose_captee_par_deux_canaux_ne_ressort_qu_une_fois() -> void:
	var feu := _chose("feu", Vector3(0, 0, 30))

	var monde := Monde.new()
	monde.ajouter(feu, "chose", feu.position)

	var entite := _entite(Vector3.ZERO, {
		"vue": { "portee": 100.0, "angle": 90.0 },
		"ouie": { "portee": 100.0 },
	}, Vector3(0, 0, 1))
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)

	verif.v(perceptions.size() == 1, "une seule chose captee par deux canaux doit rendre UNE seule entree")
	if perceptions.size() == 1:
		verif.v(perceptions[0].canaux.size() == 2 and "vue" in perceptions[0].canaux and "ouie" in perceptions[0].canaux,
			"l'entree doit porter les deux noms de canal qui l'ont captee")

# ---- Hors domaine ----

func _hors_domaine_canal_gravitique_capte_masse() -> void:
	var caillou := _chose("caillou", Vector3(20, 0, 0), { "masse": 42.0 })

	var monde := Monde.new()
	monde.ajouter(caillou, "chose", caillou.position)

	var entite := _entite(Vector3.ZERO, { "gravitique": { "portee": 50.0 } })
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)

	verif.v(perceptions.size() == 1 and perceptions[0].chose.id == "caillou" and perceptions[0].canaux == ["gravitique"],
		"un canal invente (gravitique/masse), sans aucun rapport avec les 6 canaux reels, doit traverser le meme code")

# ---- Cas limites ----

func _entite_aveugle_sans_vue_ne_percoit_jamais_par_ce_canal() -> void:
	var devant := _chose("devant", Vector3(0, 0, 30))

	var monde := Monde.new()
	monde.ajouter(devant, "chose", devant.position)

	# canaux ne porte que "ouie" -- pas de "vue" du tout.
	var entite := _entite(Vector3.ZERO, { "ouie": { "portee": 100.0 } }, Vector3(0, 0, 1))
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)

	verif.v(perceptions.size() == 1, "la chose reste captee par ouie")
	if perceptions.size() == 1:
		verif.v(perceptions[0].canaux == ["ouie"],
			"une entite sans 'vue' dans ses canaux ne doit JAMAIS faire tourner le mecanisme de vue")

func _canal_a_portee_zero_ne_capte_rien() -> void:
	var tout_pres := _chose("tout_pres", Vector3(0, 0, 5))

	var monde := Monde.new()
	monde.ajouter(tout_pres, "chose", tout_pres.position)

	var entite := _entite(Vector3.ZERO, { "vue": { "portee": 0.0, "angle": 90.0 } }, Vector3(0, 0, 1))
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)

	verif.v(perceptions.size() == 0, "un canal a portee 0.0 ne doit jamais capter, meme une chose toute proche")

func _canal_cone_a_angle_360_degenere_en_sphere() -> void:
	var derriere := _chose("derriere", Vector3(0, 0, -50))

	var monde := Monde.new()
	monde.ajouter(derriere, "chose", derriere.position)

	var entite := _entite(Vector3.ZERO, { "vue": { "portee": 100.0, "angle": 360.0 } }, Vector3(0, 0, 1))
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)

	verif.v(perceptions.size() == 1 and perceptions[0].chose.id == "derriere",
		"angle 360 doit degenerer en sphere : meme une chose derriere l'entite doit etre captee")

# ---- Gardes structurelles ----

func _canaux_absent_de_proprietes_alarme_et_rend_vide() -> void:
	var devant := _chose("devant", Vector3(0, 0, 30))
	var monde := Monde.new()
	monde.ajouter(devant, "chose", devant.position)

	var entite := { "position": Vector3.ZERO, "proprietes": {} }
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)

	verif.v(perceptions == [], "'canaux' absent de proprietes doit alarmer et rendre [], jamais un defaut silencieux")

func _canal_reference_absent_du_catalogue_alarme_et_ignore_ce_canal_seul() -> void:
	var devant := _chose("devant", Vector3(0, 0, 30))
	var monde := Monde.new()
	monde.ajouter(devant, "chose", devant.position)

	var entite := _entite(Vector3.ZERO, {
		"vue": { "portee": 100.0, "angle": 90.0 },
		"sixieme_sens": { "portee": 100.0 },
	}, Vector3(0, 0, 1))
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE)

	verif.v(perceptions.size() == 1 and perceptions[0].canaux == ["vue"],
		"un canal reference par l'entite mais absent du catalogue doit alarmer et etre ignore, sans bloquer les autres")

# ---- Auto-exclusion (chantier "colon saillant") ----

# L'entite percevante EST elle-meme une chose du monde (meme id des deux
# cotes) -- couvre propagation_obstacles/sphere_directionnelle/contact ET
# cone_oriente a angle 360 (les quatre passent par _sphere_brute). "moi"
# et "autre" a des positions distinctes : si l'exclusion echouait, "moi"
# ressortirait EN PLUS de "autre", jamais a sa place (distance 0 a
# soi-meme, toujours dans n'importe quelle portee > 0).
func _entite_est_exclue_de_ses_propres_perceptions_sphere_brute() -> void:
	var autre := _chose("autre", Vector3(0, 0, 30))
	var moi := _chose("moi", Vector3(0, 0, 0), {
		"canaux": ["vue", "ouie", "odorat", "toucher"],
		"canaux_config": {
			"vue":     { "portee": 100.0, "angle": 360.0 },
			"ouie":    { "portee": 100.0 },
			"odorat":  { "portee": 100.0 },
			"toucher": { "portee": 100.0 },
		},
	})

	var monde := Monde.new()
	monde.ajouter(autre, "chose", autre.position)
	monde.ajouter(moi, "chose", moi.position)

	var perceptions := Perception.percevoir(moi, monde, CATALOGUE)

	verif.v(perceptions.size() == 1,
		"l'entite ne doit jamais se retrouver dans ses propres perceptions (sphere_brute), recu %d entree(s)" % perceptions.size())
	if perceptions.size() == 1:
		verif.v(perceptions[0].chose.id == "autre",
			"la seule chose percue doit etre 'autre', jamais 'moi' elle-meme")

# cone_oriente a angle < 360 ne passe PAS par _sphere_brute (sa propre
# boucle) -- sans sa propre garde, "moi" (distance 0 a elle-meme, donc
# TOUJOURS dans n'importe quel cone) ressortirait malgre la garde de
# _sphere_brute qui ne la couvre pas ici.
func _entite_est_exclue_de_ses_propres_perceptions_cone_etroit() -> void:
	var devant := _chose("devant", Vector3(0, 0, 30))
	var moi := _chose("moi", Vector3(0, 0, 0), {
		"canaux": ["vue"],
		"canaux_config": { "vue": { "portee": 100.0, "angle": 90.0 } },
		"orientation": { "x": 0.0, "y": 0.0, "z": 1.0 },
	})

	var monde := Monde.new()
	monde.ajouter(devant, "chose", devant.position)
	monde.ajouter(moi, "chose", moi.position)

	var perceptions := Perception.percevoir(moi, monde, CATALOGUE)

	verif.v(perceptions.size() == 1,
		"l'entite ne doit jamais se retrouver dans ses propres perceptions (cone etroit), recu %d entree(s)" % perceptions.size())
	if perceptions.size() == 1:
		verif.v(perceptions[0].chose.id == "devant",
			"la seule chose percue doit etre 'devant', jamais 'moi' elle-meme")

# ---- Chantier "vent" ----

# PREUVE CHIFFREE, pas seulement un compte : l'ancien appel a 3 arguments et
# le nouvel appel a 6 arguments avec les trois defauts neutres explicites
# doivent rendre EXACTEMENT les memes distances pour les memes ids -- aucun
# banc existant (tous appellent encore percevoir() a 3 arguments) n'est donc
# affecte par ce chantier.
func _sans_vent_le_comportement_de_lodorat_est_rigoureusement_identique() -> void:
	var proche := _chose("proche", Vector3(60.0, 0.0, 0.0))
	var loin := _chose("loin", Vector3(150.0, 0.0, 0.0))
	var monde := Monde.new()
	monde.ajouter(proche, "chose", proche.position)
	monde.ajouter(loin, "chose", loin.position)

	var entite := _entite(Vector3.ZERO, { "odorat": { "portee": 100.0 } })
	var appel_ancien := Perception.percevoir(entite, monde, CATALOGUE)
	var appel_explicite := Perception.percevoir(entite, monde, CATALOGUE, {}, 0.0, [])

	verif.v(appel_ancien.size() == 1 and appel_explicite.size() == 1,
		"les deux formes d'appel doivent capturer exactement une chose ('proche' seule, 'loin' hors de la portee de base)")
	if appel_ancien.size() == 1 and appel_explicite.size() == 1:
		verif.v(appel_ancien[0].chose.id == "proche" and appel_explicite[0].chose.id == "proche",
			"les deux formes d'appel doivent capturer 'proche', jamais 'loin'")
		verif.v(is_equal_approx(appel_ancien[0].distance, 60.0) and is_equal_approx(appel_explicite[0].distance, 60.0),
			"la distance rapportee doit rester EXACTEMENT 60.0 dans les deux cas, chiffre a l'appui")
		verif.v(is_equal_approx(appel_ancien[0].distance, appel_explicite[0].distance),
			"les deux formes d'appel doivent rendre EXACTEMENT la meme distance, au chiffre pres")

func _source_sous_le_vent_captee_la_ou_elle_ne_letait_pas() -> void:
	var cible := _chose("cible", Vector3(150.0, 0.0, 0.0))  # alignee avec le vent (1,0,0), distance 150
	var monde := Monde.new()
	monde.ajouter(cible, "chose", cible.position)
	var entite := _entite(Vector3.ZERO, { "odorat": { "portee": 100.0 } })

	var sans_vent := Perception.percevoir(entite, monde, CATALOGUE)
	verif.v(sans_vent.size() == 0, "a 150 unites pour une portee de base de 100, la cible ne doit PAS etre captee sans vent")

	var avec_vent := Perception.percevoir(entite, monde, CATALOGUE, CATALOGUE_VENT_CONSTANT, 0.0, [])
	verif.v(avec_vent.size() == 1 and avec_vent[0].chose.id == "cible",
		"sous le vent (facteur_max_sous_vent 2.0 => portee effective 200), la meme cible a 150 unites doit etre captee")
	if avec_vent.size() == 1:
		verif.v(is_equal_approx(avec_vent[0].distance, 150.0),
			"la distance rapportee reste la vraie distance geometrique (150.0), jamais modifiee par le vent -- seule la comparaison au seuil change")

func _meme_source_contre_le_vent_devient_non_captee() -> void:
	var cible := _chose("cible", Vector3(-60.0, 0.0, 0.0))  # opposee au vent (1,0,0), distance 60
	var monde := Monde.new()
	monde.ajouter(cible, "chose", cible.position)
	var entite := _entite(Vector3.ZERO, { "odorat": { "portee": 100.0 } })

	var sans_vent := Perception.percevoir(entite, monde, CATALOGUE)
	verif.v(sans_vent.size() == 1 and sans_vent[0].chose.id == "cible",
		"a 60 unites pour une portee de base de 100, la cible DOIT etre captee sans vent")

	var avec_vent := Perception.percevoir(entite, monde, CATALOGUE, CATALOGUE_VENT_CONSTANT, 0.0, [])
	verif.v(avec_vent.size() == 0,
		"contre le vent (facteur_min_contre_vent 0.4 => portee effective 40), la MEME cible a 60 unites doit devenir NON captee")

# Ne suppose RIEN sur le sens de rotation (voir test_vent.gd) : place deux
# cibles perpendiculaires au vent de depart, de part et d'autre -- au fil du
# temps, exactement UNE des deux doit devenir capturee (celle que la rotation
# aligne avec le vent), jamais les deux, jamais aucune.
func _le_vent_qui_tourne_change_reellement_ce_qui_est_capte_au_fil_du_temps() -> void:
	var nord := _chose("nord", Vector3(0.0, 150.0, 0.0))
	var sud := _chose("sud", Vector3(0.0, -150.0, 0.0))
	var monde := Monde.new()
	monde.ajouter(nord, "chose", nord.position)
	monde.ajouter(sud, "chose", sud.position)
	var entite := _entite(Vector3.ZERO, { "odorat": { "portee": 100.0 } })

	var a_t0 := Perception.percevoir(entite, monde, CATALOGUE, CATALOGUE_VENT_ROTATIF, 0.0, [])
	verif.v(a_t0.size() == 0,
		"a t=0, le vent pointe (1,0,0) : 'nord' et 'sud' sont tous deux perpendiculaires (facteur neutre 1.0), portee 100 < 150, ni l'un ni l'autre ne doit etre capte")

	var a_t_quart := Perception.percevoir(entite, monde, CATALOGUE, CATALOGUE_VENT_ROTATIF, 10.0, [])  # T/4 : rotation de 90 deg
	verif.v(a_t_quart.size() == 1,
		"apres un quart de periode (rotation de 90 deg), le vent doit s'etre aligne avec exactement une des deux cibles perpendiculaires -- recu %d capture(s)" % a_t_quart.size())
	if a_t_quart.size() == 1:
		verif.v(a_t_quart[0].chose.id == "nord" or a_t_quart[0].chose.id == "sud",
			"la cible capturee doit etre 'nord' ou 'sud' (peu importe laquelle, le sens de rotation n'est pas impose)")

func _source_locale_de_vent_modifie_la_capture_dans_son_rayon_et_pas_au_dela() -> void:
	var catalogue_avec_source_seule := {
		"defaut": {
			"fond": { "direction": { "x": 1.0, "y": 0.0, "z": 0.0 }, "force": 0.0 },  # aucun vent ambiant : seule la source locale parle
			"directionnel": { "reference_force": 15.0, "facteur_max_sous_vent": 2.5, "facteur_min_contre_vent": 0.5 },
		}
	}
	var source := { "position": Vector3(500.0, 0.0, 0.0), "rayon": 50.0, "vecteur": Vector3(20.0, 0.0, 0.0) }

	# Percepteur A DIX unites du centre de la source (largement dans son
	# rayon de 50) : vent local ressenti = (20,0,0) * (1 - 10/50) = (16,0,0),
	# force 16 >= reference_force 15 -> intensite pleine -> facteur_max 2.5.
	var dans_le_rayon := _entite(Vector3(510.0, 0.0, 0.0), { "odorat": { "portee": 100.0 } })
	var cible_dans_le_rayon := _chose("cible_dans_le_rayon", Vector3(660.0, 0.0, 0.0))  # 150 unites, alignee avec le vent local
	var monde_dans_le_rayon := Monde.new()
	monde_dans_le_rayon.ajouter(cible_dans_le_rayon, "chose", cible_dans_le_rayon.position)
	var perceptions_dans_le_rayon := Perception.percevoir(dans_le_rayon, monde_dans_le_rayon, CATALOGUE, catalogue_avec_source_seule, 0.0, [source])
	verif.v(perceptions_dans_le_rayon.size() == 1 and perceptions_dans_le_rayon[0].chose.id == "cible_dans_le_rayon",
		"un percepteur DANS le rayon de la source locale doit voir sa portee allongee par elle (portee effective 250 >= 150)")

	# Percepteur a 500 unites du centre de la source (largement HORS de son
	# rayon de 50) : contribution nulle, vent ambiant nul -> repli exact sur
	# la portee de base, isotrope.
	var hors_du_rayon := _entite(Vector3(1000.0, 0.0, 0.0), { "odorat": { "portee": 100.0 } })
	var cible_hors_du_rayon := _chose("cible_hors_du_rayon", Vector3(1150.0, 0.0, 0.0))  # meme geometrie relative, 150 unites
	var monde_hors_du_rayon := Monde.new()
	monde_hors_du_rayon.ajouter(cible_hors_du_rayon, "chose", cible_hors_du_rayon.position)
	var perceptions_hors_du_rayon := Perception.percevoir(hors_du_rayon, monde_hors_du_rayon, CATALOGUE, catalogue_avec_source_seule, 0.0, [source])
	verif.v(perceptions_hors_du_rayon.size() == 0,
		"un percepteur HORS du rayon de la source locale ne doit recevoir AUCUN effet d'elle -- meme cible a 150 unites, portee de base 100, non captee")

# Le cablage vit au niveau de la GEOMETRIE (sphere_directionnelle), jamais du
# nom du canal -- "gravitique" (canal invente, deja utilise par
# _hors_domaine_canal_gravitique_capte_masse plus haut) doit reagir au vent
# exactement comme "odorat", par le meme code.
func _hors_domaine_vent_sur_canal_invente_gravitique() -> void:
	var caillou := _chose("caillou", Vector3(80.0, 0.0, 0.0), { "masse": 42.0 })  # aligne avec le vent, distance 80
	var monde := Monde.new()
	monde.ajouter(caillou, "chose", caillou.position)
	var entite := _entite(Vector3.ZERO, { "gravitique": { "portee": 50.0 } })

	var sans_vent := Perception.percevoir(entite, monde, CATALOGUE)
	verif.v(sans_vent.size() == 0, "hors domaine : a 80 unites pour une portee de base de 50, non capte sans vent")

	var avec_vent := Perception.percevoir(entite, monde, CATALOGUE, CATALOGUE_VENT_CONSTANT, 0.0, [])
	verif.v(avec_vent.size() == 1 and avec_vent[0].chose.id == "caillou",
		"hors domaine : sous le vent (portee effective 100), le meme canal invente 'gravitique' doit capturer le caillou par le MEME code que l'odorat")

# ---- Chantier "occlusion" ----
#
# Geometrie commune aux cinq tests : percepteur en (0,0,0), source_son en
# (100,0,0) -- portee ouie 200.0 (attenuation_distance = 1-100/200 = 0.5),
# son_emis 0.5 (meme valeur que le fer reel, data/materiaux.json) -> intensite
# attenuee SANS obstacle = 0.5*0.5 = 0.25, IDENTIQUE dans les cinq tests. Un
# mur eventuel se place en (50,0,0), EXACTEMENT au milieu du segment (t=0.5,
# distance laterale 0.0) sauf le test "a cote de la ligne". absorption_sonore
# 0.05 = valeur REELLE de la pierre (data/materiaux.json) -- un seul mur
# n'attenue donc que de 5% (facteur 0.95, attenuee 0.2375), volontairement
# MARGINAL ("quasi bloque", jamais un mur qui bloquerait n'importe quel
# seuil) : chaque test choisit un seuil juste au-dessus ou au-dessous de la
# valeur attenuee qu'il veut demontrer, jamais un mur artificiellement fort.

func _mur_obstacle_bloque_le_son() -> void:
	var source := _chose("source_son", Vector3(100.0, 0.0, 0.0), { "son_emis": 0.5 })
	var mur := _chose("mur", Vector3(50.0, 0.0, 0.0), { "absorption_sonore": 0.05 })
	var entite := _entite(Vector3.ZERO, { "ouie": { "portee": 200.0, "seuil": 0.24 } })

	var monde := Monde.new()
	monde.ajouter(source, "chose", source.position)
	monde.ajouter(mur, "chose", mur.position)
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE_OCCLUSION)

	verif.v(perceptions.size() == 0,
		"un mur (absorption_sonore 0.05) entre le percepteur et la source doit faire tomber l'intensite attenuee (0.2375) sous le seuil (0.24), recu %d capture(s)" % perceptions.size())

func _mur_retire_la_perception_revient() -> void:
	var source := _chose("source_son", Vector3(100.0, 0.0, 0.0), { "son_emis": 0.5 })
	var entite := _entite(Vector3.ZERO, { "ouie": { "portee": 200.0, "seuil": 0.24 } })

	var monde := Monde.new()
	monde.ajouter(source, "chose", source.position)
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE_OCCLUSION)

	verif.v(perceptions.size() == 1 and perceptions[0].chose.id == "source_son",
		"le MEME seuil (0.24), sans le mur du test precedent, doit laisser passer l'intensite non attenuee (0.25) -- la source redevient percue")

# Un seul mur (facteur 0.95, attenuee 0.2375) laisse encore PASSER un seuil
# de 0.23 ; DEUX murs identiques sur le meme segment (facteur cumule
# 0.95*0.95=0.9025, attenuee 0.225625) tombent SOUS ce meme seuil -- preuve
# que l'attenuation se CUMULE, pas seulement qu'un mur suffit deja a bloquer.
func _deux_murs_cumulent_leur_attenuation() -> void:
	var source := _chose("source_son", Vector3(100.0, 0.0, 0.0), { "son_emis": 0.5 })
	var mur_a := _chose("mur_a", Vector3(30.0, 0.0, 0.0), { "absorption_sonore": 0.05 })
	var mur_b := _chose("mur_b", Vector3(70.0, 0.0, 0.0), { "absorption_sonore": 0.05 })
	var entite := _entite(Vector3.ZERO, { "ouie": { "portee": 200.0, "seuil": 0.23 } })

	var monde_un_mur := Monde.new()
	monde_un_mur.ajouter(source, "chose", source.position)
	monde_un_mur.ajouter(mur_a, "chose", mur_a.position)
	var perceptions_un_mur := Perception.percevoir(entite, monde_un_mur, CATALOGUE_OCCLUSION)
	verif.v(perceptions_un_mur.size() == 1,
		"UN seul mur (facteur 0.95, attenuee 0.2375) doit encore passer le seuil 0.23, recu %d capture(s)" % perceptions_un_mur.size())

	var monde_deux_murs := Monde.new()
	monde_deux_murs.ajouter(source, "chose", source.position)
	monde_deux_murs.ajouter(mur_a, "chose", mur_a.position)
	monde_deux_murs.ajouter(mur_b, "chose", mur_b.position)
	var perceptions_deux_murs := Perception.percevoir(entite, monde_deux_murs, CATALOGUE_OCCLUSION)
	verif.v(perceptions_deux_murs.size() == 0,
		"DEUX murs cumules (facteur 0.9025, attenuee 0.225625) doivent tomber sous le MEME seuil 0.23, recu %d capture(s)" % perceptions_deux_murs.size())

func _mur_transparent_ne_bloque_rien() -> void:
	var source := _chose("source_son", Vector3(100.0, 0.0, 0.0), { "son_emis": 0.5 })
	var mur := _chose("mur_transparent", Vector3(50.0, 0.0, 0.0), { "absorption_sonore": 0.0 })
	var entite := _entite(Vector3.ZERO, { "ouie": { "portee": 200.0, "seuil": 0.24 } })

	var monde := Monde.new()
	monde.ajouter(source, "chose", source.position)
	monde.ajouter(mur, "chose", mur.position)
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE_OCCLUSION)

	verif.v(perceptions.size() == 1 and perceptions[0].chose.id == "source_son",
		"un mur avec absorption_sonore 0.0 (transparent) ne doit rien attenuer -- meme resultat que sans mur du tout")

# Meme mur "fort" (absorption_sonore 1.0, bloquerait TOTALEMENT s'il etait
# sur le segment) mais positionne LATERALEMENT a (50,100,0) -- distance
# laterale au segment = 100.0, tres au-dela de largeur_obstacle (10.0) :
# jamais teste comme obstacle, la source reste percue a intensite pleine.
func _mur_a_cote_de_la_ligne_ne_bloque_rien() -> void:
	var source := _chose("source_son", Vector3(100.0, 0.0, 0.0), { "son_emis": 0.5 })
	var mur := _chose("mur_a_cote", Vector3(50.0, 100.0, 0.0), { "absorption_sonore": 1.0 })
	var entite := _entite(Vector3.ZERO, { "ouie": { "portee": 200.0, "seuil": 0.24 } })

	var monde := Monde.new()
	monde.ajouter(source, "chose", source.position)
	monde.ajouter(mur, "chose", mur.position)
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE_OCCLUSION)

	verif.v(perceptions.size() == 1 and perceptions[0].chose.id == "source_son",
		"un mur hors de la largeur_obstacle (distance laterale 100.0 > 10.0), meme absorbant a 100%, ne doit jamais etre teste comme obstacle")

# ---- Chantier "propriete_emission configurable par canal" ----

# La source porte les DEUX proprietes -- son_emis a 0.0 (bruyamment FAUX si
# le canal lisait encore le defaut en dur) et force_radiation a 0.5 (la
# valeur que "radiation" doit reellement lire, declaree via
# CATALOGUE_EMISSION_CONFIGURABLE). Portee 200.0, seuil 0.24 : intensite
# attenuee sur force_radiation = 0.5*(1-100/200) = 0.25 >= seuil -> captee ;
# sur son_emis = 0.0*... = 0.0 < seuil -> jamais captee. Le resultat ne peut
# donc etre positif QUE si le canal a bien lu force_radiation.
# Une geometrie que le mecanisme ne sait pas jouer est une DONNEE CASSEE,
# jamais un canal muet : elle alarme, ce canal seul ne capte rien, et les
# autres canaux de la meme entite continuent de capter normalement. Sans ce
# cas, un nom de geometrie mal ecrit dans le catalogue rendrait un percevant
# partiellement aveugle en silence.
func _geometrie_inconnue_alarme_et_ne_capte_rien_sans_toucher_aux_autres() -> void:
	var catalogue := {
		"zorg": { "geometrie": "spirale_inexistante" },
		"ouie": { "geometrie": "propagation_obstacles" },
	}
	var source := _chose("source", Vector3(0.0, 0.0, 30.0), { "son_emis": 1.0 })
	var entite := _entite(Vector3.ZERO, {
		"zorg": { "portee": 200.0 },
		"ouie": { "portee": 200.0, "seuil": 0.0 },
	})

	var monde := Monde.new()
	monde.ajouter(source, "chose", source.position)
	var perceptions := Perception.percevoir(entite, monde, catalogue)

	verif.v(perceptions.size() == 1,
		"le canal a geometrie inconnue ne capte rien, l'autre capte quand meme -- recu %d" % perceptions.size())
	verif.v(perceptions.size() == 1 and not perceptions[0].canaux.has("zorg"),
		"le canal a geometrie inconnue ne doit apparaitre dans aucune capture")

func _canal_fictif_lit_sa_propre_propriete_emission() -> void:
	var source := _chose("source_radiation", Vector3(100.0, 0.0, 0.0), { "force_radiation": 0.5, "son_emis": 0.0 })
	var entite := _entite(Vector3.ZERO, { "radiation": { "portee": 200.0, "seuil": 0.24 } })

	var monde := Monde.new()
	monde.ajouter(source, "chose", source.position)
	var perceptions := Perception.percevoir(entite, monde, CATALOGUE_EMISSION_CONFIGURABLE)

	verif.v(perceptions.size() == 1 and perceptions[0].chose.id == "source_radiation",
		"un canal fictif declarant propriete_emission: 'force_radiation' doit lire force_radiation (0.5, intensite attenuee 0.25 >= seuil 0.24) sur la source, jamais son_emis (0.0), recu %d capture(s)" % perceptions.size())
