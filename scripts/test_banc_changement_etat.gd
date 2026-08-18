extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_changement_etat.gd
#
# Verrouille le cablage de banc_changement_etat.gd, PREMIERE DEMONSTRATION
# REELLE de scripts/seuil_etat.gd : temperature_source/sources_du_tick/
# texte_etat/couleur_pour_etats/texte_label/ligne_log/fluidite_effective
# (fonctions statiques, pures) plus un CHEMIN REEL combinant
# Temperature.avancer/SeuilEtat.avancer/EtatEffectif.valeur sur un fer
# FABRIQUE PAR COMPOSITION (data/materiaux.json/data/proprietes_immuables_
# composition.json/data/seuils_etat.json/data/etats.json lus sur disque) --
# l'objet doit reellement traverser solide -> chaud -> liquide -> gaz en
# chauffant, puis l'inverse en refroidissant, sa malleabilite effective doit
# monter des que "chaud" est actif, et sa fluidite effective (chantier
# "fluidite_liquide") doit rester nulle tant qu'il est solide et n'apparaitre
# qu'une fois liquide.

const Objet = preload("res://scripts/objet.gd")
const Temperature = preload("res://scripts/temperature.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const BancChangementEtat = preload("res://scripts/banc_changement_etat.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_temperature_source_rampe_lineaire_puis_plafonnee()
	_sources_du_tick_disparait_apres_duree_chauffe()

	_texte_etat_vide_rend_aucun()
	_texte_etat_joint_les_noms()

	_couleur_pour_etats_solide_seul()
	_couleur_pour_etats_solide_chaud_est_teinte()
	_couleur_pour_etats_liquide_ignore_le_tint_chaud()
	_couleur_pour_etats_gaz_prioritaire_sur_liquide()

	_texte_label_porte_les_nombres_et_les_etats()
	_ligne_log_porte_les_nombres_et_les_etats()

	_fluidite_effective_solide_rend_zero()
	_fluidite_effective_liquide_rend_la_base()
	_fluidite_effective_sans_donnee_rend_zero()

	_chemin_reel_le_fer_traverse_toutes_les_phases_puis_les_retraverse()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: rampe de temperature de la source plafonnee puis disparue apres " +
		"duree_chauffe, textes/couleurs par etat corrects, chemin reel " +
		"(data/materiaux.json/data/proprietes_immuables_composition.json/" +
		"data/seuils_etat.json/data/etats.json) ou un fer fabrique par " +
		"composition chauffe jusqu'a devenir gazeux puis se resolidifie " +
		"en refroidissant, malleabilite effective moduleee tant que 'chaud' " +
		"est actif, fluidite effective nulle tant que solide et egale a la " +
		"base materiau une fois liquide")
	quit(0)

# ---- temperature_source / sources_du_tick ----

func _temperature_source_rampe_lineaire_puis_plafonnee() -> void:
	var t0 := BancChangementEtat.temperature_source(0.0, 20.0, 40.0, 90.0)
	verif.v(is_equal_approx(t0, 20.0), "a t=0, la source doit etre exactement a l'ambiante, recu %f" % t0)

	var t_milieu := BancChangementEtat.temperature_source(10.0, 20.0, 40.0, 90.0)
	verif.v(is_equal_approx(t_milieu, 420.0), "a t=10 avec une rampe de 40/s, source attendue 20+40*10=420.0, recu %f" % t_milieu)

	var t_plafond := BancChangementEtat.temperature_source(90.0, 20.0, 40.0, 90.0)
	var t_au_dela := BancChangementEtat.temperature_source(500.0, 20.0, 40.0, 90.0)
	verif.v(is_equal_approx(t_plafond, t_au_dela), "au-dela de duree_chauffe, la temperature de la source doit rester PLAFONNEE a sa valeur de duree_chauffe, jamais continuer a grimper, recu %f vs %f" % [t_plafond, t_au_dela])

func _sources_du_tick_disparait_apres_duree_chauffe() -> void:
	var avant := BancChangementEtat.sources_du_tick(50.0, Vector3.ZERO, 100.0, 1.0, 20.0, 40.0, 90.0)
	verif.v(avant.size() == 1, "avant duree_chauffe, une seule source doit exister, recu %d" % avant.size())
	verif.v(is_equal_approx(avant[0].temperature, 20.0 + 40.0 * 50.0), "la source avant coupure doit porter la temperature de rampe exacte")

	var apres := BancChangementEtat.sources_du_tick(200.0, Vector3.ZERO, 100.0, 1.0, 20.0, 40.0, 90.0)
	verif.v(apres.is_empty(), "au-dela de duree_chauffe, la source doit avoir DISPARU (Array vide), jamais rester a une valeur figee")

# ---- texte_etat ----

func _texte_etat_vide_rend_aucun() -> void:
	verif.v(BancChangementEtat.texte_etat([]) == "(aucun)", "aucun etat actif doit rendre le texte '(aucun)'")

func _texte_etat_joint_les_noms() -> void:
	var texte := BancChangementEtat.texte_etat(["liquide", "chaud"])
	verif.v(texte.find("liquide") != -1 and texte.find("chaud") != -1, "le texte doit porter tous les noms d'etat actifs, recu '%s'" % texte)

# ---- couleur_pour_etats ----

func _couleur_pour_etats_solide_seul() -> void:
	var solide := Color(0.5, 0.5, 0.5)
	var tint := Color(1.0, 0.0, 0.0)
	var liquide := Color(0.0, 1.0, 0.0)
	var gaz := Color(0.0, 0.0, 1.0)
	var c := BancChangementEtat.couleur_pour_etats([], solide, tint, liquide, gaz)
	verif.v(c == solide, "sans aucun etat actif, la couleur doit etre exactement 'solide', recu %s" % c)

func _couleur_pour_etats_solide_chaud_est_teinte() -> void:
	var solide := Color(0.5, 0.5, 0.5)
	var tint := Color(1.0, 0.0, 0.0)
	var liquide := Color(0.0, 1.0, 0.0)
	var gaz := Color(0.0, 0.0, 1.0)
	var c := BancChangementEtat.couleur_pour_etats(["chaud"], solide, tint, liquide, gaz)
	verif.v(c != solide, "solide + chaud doit produire une couleur DIFFERENTE de solide pur (lisere plus chaud)")
	verif.v(c != tint, "solide + chaud ne doit pas etre le tint PUR non plus -- un melange (lerp), pas un remplacement")

func _couleur_pour_etats_liquide_ignore_le_tint_chaud() -> void:
	var solide := Color(0.5, 0.5, 0.5)
	var tint := Color(1.0, 0.0, 0.0)
	var liquide := Color(0.0, 1.0, 0.0)
	var gaz := Color(0.0, 0.0, 1.0)
	var c := BancChangementEtat.couleur_pour_etats(["liquide", "chaud"], solide, tint, liquide, gaz)
	verif.v(c == liquide, "une fois liquide, la couleur de phase doit dominer, meme si 'chaud' est aussi actif, recu %s" % c)

func _couleur_pour_etats_gaz_prioritaire_sur_liquide() -> void:
	var solide := Color(0.5, 0.5, 0.5)
	var tint := Color(1.0, 0.0, 0.0)
	var liquide := Color(0.0, 1.0, 0.0)
	var gaz := Color(0.0, 0.0, 1.0)
	# etats mutuellement exclusifs en pratique (seuil_etat.gd), mais la
	# fonction de couleur doit rester deterministe si jamais les deux
	# etaient presents en meme temps -- gaz l'emporte.
	var c := BancChangementEtat.couleur_pour_etats(["liquide", "gaz"], solide, tint, liquide, gaz)
	verif.v(c == gaz, "gaz doit toujours dominer liquide si les deux sont presents, recu %s" % c)

# ---- textes ----

func _texte_label_porte_les_nombres_et_les_etats() -> void:
	var texte := BancChangementEtat.texte_label(1600.0, 1650.0, ["liquide", "chaud"], 0.91, 0.6)
	verif.v(texte.find("1600.0") != -1, "le texte doit porter la temperature de l'objet")
	verif.v(texte.find("1650.0") != -1, "le texte doit porter la temperature locale")
	verif.v(texte.find("liquide") != -1 and texte.find("chaud") != -1, "le texte doit porter les etats actifs")
	verif.v(texte.find("0.910") != -1, "le texte doit porter la malleabilite effective")
	verif.v(texte.find("0.600") != -1, "le texte doit porter la fluidite effective")

func _ligne_log_porte_les_nombres_et_les_etats() -> void:
	var ligne := BancChangementEtat.ligne_log(45.0, "fer_test", 1538.5, ["liquide", "chaud"], 0.91, 0.6)
	verif.v(ligne.find("t=45.0") != -1, "la ligne doit porter le temps")
	verif.v(ligne.find("fer_test") != -1, "la ligne doit porter l'id")
	verif.v(ligne.find("1538.5") != -1, "la ligne doit porter la temperature")
	verif.v(ligne.find("liquide") != -1 and ligne.find("chaud") != -1, "la ligne doit porter les etats actifs")
	verif.v(ligne.find("fluidite_effective=0.600") != -1, "la ligne doit porter la fluidite effective")

# ---- fluidite_effective ----

# Catalogue minimal, meme forme que data/etats.json:liquide (une entree
# reelle, sans effet sur "fluidite_liquide") -- un catalogue {} ferait
# hurler etat_effectif.gd ("etat 'liquide' absent de data/etats.json") des
# que "liquide" figure dans etats_actifs, meme si fluidite_effective ne
# l'atteint jamais pour le cas solide (garde avant l'appel).
const _CATALOGUE_ETATS_MINIMAL := {"liquide": {"effets": [{"propriete": "rigidite", "mode": "ecraser", "valeur": 0.0}]}}

func _fluidite_effective_solide_rend_zero() -> void:
	var chose := {"proprietes": {"fluidite_liquide": 0.6, "etats_actifs": ["chaud"]}}
	var f := BancChangementEtat.fluidite_effective(chose, _CATALOGUE_ETATS_MINIMAL)
	verif.v(is_equal_approx(f, 0.0), "un objet solide (meme 'chaud', sans 'liquide') ne doit porter AUCUNE fluidite effective, recu %f" % f)

func _fluidite_effective_liquide_rend_la_base() -> void:
	var chose := {"proprietes": {"fluidite_liquide": 0.6, "etats_actifs": ["liquide"]}}
	var f := BancChangementEtat.fluidite_effective(chose, _CATALOGUE_ETATS_MINIMAL)
	verif.v(is_equal_approx(f, 0.6), "un objet liquide doit porter sa fluidite de base (aucun etat ne la module dans data/etats.json), recu %f" % f)

func _fluidite_effective_sans_donnee_rend_zero() -> void:
	var chose := {"proprietes": {"etats_actifs": ["liquide"]}}
	var f := BancChangementEtat.fluidite_effective(chose, _CATALOGUE_ETATS_MINIMAL)
	verif.v(is_equal_approx(f, 0.0), "un objet liquide sans 'fluidite_liquide' en donnee doit rendre 0.0 (defaut d'etat_effectif.gd), pas une erreur, recu %f" % f)

# ---- Chemin reel ----

func _catalogues_reels() -> Dictionary:
	return {
		"temperature": JSON.parse_string(FileAccess.get_file_as_string("res://data/temperature.json")),
		"seuils": JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json")),
		"etats": JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json")),
		"materiaux": JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json")),
		"proprietes_immuables": JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", []),
	}

func _chemin_reel_le_fer_traverse_toutes_les_phases_puis_les_retraverse() -> void:
	var cat := _catalogues_reels()
	var catalogue_types := {"fer_test": {"composition": [{"materiau": "fer", "volume": 1.0}]}}
	var objet := Objet.fabriquer("fer_test", "fer_test", Vector3.ZERO, catalogue_types, cat.materiaux, cat.proprietes_immuables)
	verif.v(not objet.is_empty(), "chemin reel : le fer doit se fabriquer normalement")
	objet.proprietes["temperature"] = 20.0
	objet.proprietes["etats_actifs"] = []
	verif.v(is_equal_approx(float(objet.proprietes.point_fusion), 1538.0), "chemin reel : point_fusion doit venir de la fusion generique (fer, 1538.0), sans etre pose a la main, recu %f" % objet.proprietes.point_fusion)
	verif.v(is_equal_approx(float(objet.proprietes.point_ebullition), 2862.0), "chemin reel : point_ebullition doit venir de la fusion generique (fer, 2862.0), sans etre pose a la main, recu %f" % objet.proprietes.point_ebullition)
	verif.v(is_equal_approx(float(objet.proprietes.fluidite_liquide), 0.6), "chemin reel : fluidite_liquide doit venir de la fusion generique (fer, 0.6), sans etre posee a la main, recu %f" % objet.proprietes.fluidite_liquide)
	verif.v(is_equal_approx(BancChangementEtat.fluidite_effective(objet, cat.etats), 0.0), "chemin reel : a froid, solide, la fluidite effective doit etre nulle malgre une fluidite_liquide de base non nulle, recu %f" % BancChangementEtat.fluidite_effective(objet, cat.etats))

	var monde := [objet]
	var position := Vector3.ZERO
	var rayon := 100.0
	var force := 1.0
	var ambiante: float = cat.temperature.defaut.ambiante
	var ramp_rate := 40.0
	var duree_chauffe := 90.0
	var delta := 0.5

	var vu_chaud := false
	var vu_liquide := false
	var vu_gaz := false
	var vu_fluidite := false
	var fluidite_vue_pendant_solide_seul := false
	var t := 0.0

	# Phase de chauffe -- STRICTEMENT jusqu'a duree_chauffe (jamais au-dela :
	# la source disparait pile a cette frontiere, voir sources_du_tick --
	# depasser cette borne ferait deja commencer le refroidissement avant
	# d'avoir lu l'etat au pic).
	var actifs_au_pic: Array = []
	while t < duree_chauffe:
		var sources := BancChangementEtat.sources_du_tick(t, position, rayon, force, ambiante, ramp_rate, duree_chauffe)
		Temperature.avancer(monde, sources, delta, cat.temperature)
		SeuilEtat.avancer(monde, cat.seuils)
		var actifs: Array = objet.proprietes.etats_actifs
		if actifs.has("chaud"):
			vu_chaud = true
		if actifs.has("liquide"):
			vu_liquide = true
		if actifs.has("gaz"):
			vu_gaz = true
		var f: float = BancChangementEtat.fluidite_effective(objet, cat.etats)
		if f > 0.0:
			vu_fluidite = true
		if not actifs.has("liquide") and not actifs.has("gaz") and f > 0.0:
			fluidite_vue_pendant_solide_seul = true
		actifs_au_pic = actifs
		t += delta

	verif.v(vu_chaud, "chemin reel : le fer doit avoir traverse l'etat 'chaud' pendant la chauffe")
	verif.v(vu_liquide, "chemin reel : le fer doit avoir traverse l'etat 'liquide' (point_fusion franchi) pendant la chauffe")
	verif.v(vu_gaz, "chemin reel : le fer doit avoir traverse l'etat 'gaz' (point_ebullition franchi) pendant la chauffe -- 'Du fer qui fond' ET 'devient gazeux'")

	verif.v(actifs_au_pic.has("gaz"), "chemin reel : au pic de chauffe (juste avant la coupure de la source), le fer doit etre gazeux, recu %s" % str(actifs_au_pic))

	verif.v(vu_fluidite, "chemin reel : le fer doit avoir porte une fluidite effective non nulle une fois liquide")
	verif.v(not fluidite_vue_pendant_solide_seul, "chemin reel : la fluidite effective ne doit JAMAIS etre non nulle tant que le fer est encore solide (ni 'liquide' ni 'gaz' actifs)")
	verif.v(is_equal_approx(BancChangementEtat.fluidite_effective(objet, cat.etats), float(cat.materiaux.fer.fluidite_liquide)), "chemin reel : au pic (gazeux, donc encore 'liquide' actif -- voir CONSEQUENCE ASSUMEE de seuil_etat.gd), la fluidite effective doit valoir exactement la base materiau (0.6), recu %f" % BancChangementEtat.fluidite_effective(objet, cat.etats))

	var effective_chaud: float = EtatEffectif.valeur(objet, "malleabilite", cat.etats)
	var malleabilite_base: float = float(cat.materiaux.fer.malleabilite)
	verif.v(effective_chaud > malleabilite_base, "chemin reel : 'chaud' actif doit moduler la malleabilite EFFECTIVE au-dessus de la base (%f), recu %f" % [malleabilite_base, effective_chaud])
	verif.v(is_equal_approx(effective_chaud, malleabilite_base * 1.3), "chemin reel : le facteur doit etre exactement celui de data/etats.json:chaud (1.3), attendu %f, recu %f" % [malleabilite_base * 1.3, effective_chaud])

	# Phase de refroidissement -- la source a disparu (t > duree_chauffe),
	# assez de temps simule pour redescendre entierement sous "chaud".
	while t < duree_chauffe + 400.0:
		var sources := BancChangementEtat.sources_du_tick(t, position, rayon, force, ambiante, ramp_rate, duree_chauffe)
		Temperature.avancer(monde, sources, delta, cat.temperature)
		SeuilEtat.avancer(monde, cat.seuils)
		t += delta

	var actifs_final: Array = objet.proprietes.etats_actifs
	verif.v(not actifs_final.has("gaz"), "chemin reel : apres refroidissement prolonge, le fer ne doit plus etre gazeux")
	verif.v(not actifs_final.has("liquide"), "chemin reel : apres refroidissement prolonge, le fer ne doit plus etre liquide -- il doit s'etre RESOLIDIFIE")
	verif.v(not actifs_final.has("chaud"), "chemin reel : apres refroidissement prolonge sous le seuil 'chaud', l'etat doit avoir ete retire")
	verif.v(objet.proprietes.temperature < ambiante + 5.0, "chemin reel : la temperature doit etre redescendue tres pres de l'ambiante reelle (%f), recu %f" % [ambiante, objet.proprietes.temperature])

	var effective_froid: float = EtatEffectif.valeur(objet, "malleabilite", cat.etats)
	verif.v(is_equal_approx(effective_froid, malleabilite_base), "chemin reel : une fois refroidi, la malleabilite effective doit etre revenue EXACTEMENT a la base (%f), recu %f -- plus aucun etat ne la module" % [malleabilite_base, effective_froid])

	var fluidite_froid: float = BancChangementEtat.fluidite_effective(objet, cat.etats)
	verif.v(is_equal_approx(fluidite_froid, 0.0), "chemin reel : une fois RESOLIDIFIE, la fluidite effective doit etre retombee a 0.0 (garde 'liquide' retire), pas rester a la base materiau, recu %f" % fluidite_froid)
