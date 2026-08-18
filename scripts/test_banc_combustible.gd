extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_combustible.gd
#
# Verrouille les fonctions statiques testables de banc_combustible.gd
# (_texte_composition/_teinte_pour_proportion/_texte_label/_ligne_pose/
# _ligne_rapport/_ligne_extinction) et, CHEMIN REEL (meme regime que
# test_banc_inflammabilite.gd), la fabrication effective des cinq objets
# du banc depuis data/banc_combustible.json + data/materiaux.json +
# data/reserve_combustible_composition.json + data/seuils_combustible.json,
# lus sur disque -- puis UNE BOUCLE REELLE qui avance Depense.avancer()
# tick par tick sur les cinq objets ENSEMBLE jusqu'a leurs extinctions
# reelles, verifiant l'ORDRE (fer_meme_volume et paille_vive en premier,
# puis bois_petit/bois_moyen/bois_grand dans cet ordre). Verrouille aussi
# la CORRECTION du chantier : la capacite vient desormais de
# "pouvoir_calorifique" (materiaux.json), une propriete DEDIEE et
# INDEPENDANTE d'"inflammabilite" -- paille_vive le prouve : plus
# inflammable que le bois, mais avec beaucoup moins a bruler.

const BancCombustible = preload("res://scripts/banc_combustible.gd")
const Objet = preload("res://scripts/objet.gd")
const Combustible = preload("res://scripts/combustible.gd")
const Depense = preload("res://scripts/depense.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_texte_composition_mono_materiau(v)
	_teinte_plus_sombre_a_proportion_faible(v)
	_texte_label_porte_id_capacite_et_reste(v)
	_ligne_pose_porte_objet_et_capacite(v)
	_ligne_rapport_porte_absolu_et_proportion(v)
	_ligne_extinction_porte_objet_et_reste(v)
	_donnees_reelles_cinq_objets_capacites_attendues(v)
	_donnees_reelles_pouvoir_calorifique_independant_d_inflammabilite(v)
	_chemin_reel_ordre_d_extinction(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_combustible.gd -- capacite/reste suivent Combustible.restant sans jamais " +
			"reimplementer sa loi, capacite vient de 'pouvoir_calorifique' (independant " +
			"d'inflammabilite), cout_base effectif vient de densite/porosite, chemin reel verifie " +
			"jusqu'aux sept extinctions reelles dans l'ordre attendu (matiere, volume ET vitesse)")
		quit(0)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _texte_composition_mono_materiau(v) -> void:
	var texte := BancCombustible._texte_composition([{"materiau": "bois", "volume": 8.0}])
	v.v(texte.find("bois") != -1 and texte.find("8.0") != -1, "la composition doit nommer le materiau et son volume")

func _teinte_plus_sombre_a_proportion_faible(v) -> void:
	var pleine := BancCombustible._teinte_pour_proportion(1.0)
	var faible := BancCombustible._teinte_pour_proportion(0.1)
	var vide := BancCombustible._teinte_pour_proportion(0.0)
	v.v(pleine.r > faible.r and faible.r > vide.r, "la teinte doit s'assombrir a mesure que la proportion baisse")

func _texte_label_porte_id_capacite_et_reste(v) -> void:
	var texte := BancCombustible._texte_label("bois_moyen", 7.2, {"absolu": 3.6, "proportion": 0.5})
	v.v(texte.find("bois_moyen") != -1 and texte.find("7.20") != -1 and texte.find("3.60") != -1 and texte.find("50%") != -1,
		"le label doit porter l'id, la capacite et le reste (absolu et pourcentage)")

func _ligne_pose_porte_objet_et_capacite(v) -> void:
	var ligne := BancCombustible._ligne_pose(0.0, "bois_grand", 13.5)
	v.v(ligne.find("bois_grand") != -1 and ligne.find("13.50") != -1, "la ligne de pose doit porter l'objet et sa capacite/reserve initiale")

func _ligne_rapport_porte_absolu_et_proportion(v) -> void:
	var ligne := BancCombustible._ligne_rapport(4.0, "bois_moyen", 3.2, 0.44)
	v.v(ligne.find("bois_moyen") != -1 and ligne.find("3.20") != -1 and ligne.find("44%") != -1,
		"la ligne de rapport doit porter l'objet, le reste absolu et le pourcentage")

func _ligne_extinction_porte_objet_et_reste(v) -> void:
	var ligne := BancCombustible._ligne_extinction(2.7, "bois_petit", -0.03)
	v.v(ligne.find("bois_petit") != -1 and ligne.find("eteint") != -1,
		"la ligne d'extinction doit porter l'objet et le mot 'eteint'")

func _donnees_reelles_cinq_objets_capacites_attendues(v) -> void:
	var donnees := _charger_json("res://data/banc_combustible.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var reserve_combustible := _charger_json("res://data/reserve_combustible_composition.json")
	v.v(donnees.objets.size() == 7, "le banc doit declarer exactement sept objets (cinq d'origine + la paire dense/poreux)")
	v.v(reserve_combustible.propriete_materiau == "pouvoir_calorifique",
		"la config reelle doit desormais pointer vers 'pouvoir_calorifique', jamais 'inflammabilite'")

	var catalogue_types: Dictionary = {}
	for decl in donnees.objets:
		catalogue_types[decl.id] = {"composition": decl.composition}

	var petit := Objet.fabriquer("bois_petit", "bois_petit", Vector3.ZERO, catalogue_types, materiaux, [], reserve_combustible)
	var moyen := Objet.fabriquer("bois_moyen", "bois_moyen", Vector3.ZERO, catalogue_types, materiaux, [], reserve_combustible)
	var grand := Objet.fabriquer("bois_grand", "bois_grand", Vector3.ZERO, catalogue_types, materiaux, [], reserve_combustible)
	var fer := Objet.fabriquer("fer_meme_volume", "fer_meme_volume", Vector3.ZERO, catalogue_types, materiaux, [], reserve_combustible)
	var paille := Objet.fabriquer("paille_vive", "paille_vive", Vector3.ZERO, catalogue_types, materiaux, [], reserve_combustible)
	var dense := Objet.fabriquer("dense_vs_poreux_dense", "dense_vs_poreux_dense", Vector3.ZERO, catalogue_types, materiaux, [], reserve_combustible)
	var poreux := Objet.fabriquer("dense_vs_poreux_poreux", "dense_vs_poreux_poreux", Vector3.ZERO, catalogue_types, materiaux, [], reserve_combustible)

	# bois.pouvoir_calorifique = 0.8, fer.pouvoir_calorifique = 0.03, paille.pouvoir_calorifique = 0.15 (catalogue reel)
	v.v(is_equal_approx(petit.proprietes.reserves.combustible.capacite, 2.4), "bois_petit (volume 3.0) doit avoir une capacite de 2.4")
	v.v(is_equal_approx(moyen.proprietes.reserves.combustible.capacite, 6.4), "bois_moyen (volume 8.0) doit avoir une capacite de 6.4")
	v.v(is_equal_approx(grand.proprietes.reserves.combustible.capacite, 12.0), "bois_grand (volume 15.0) doit avoir une capacite de 12.0")
	v.v(is_equal_approx(fer.proprietes.reserves.combustible.capacite, 0.24), "fer_meme_volume (volume 8.0, meme volume que bois_moyen) doit avoir une capacite de 0.24 -- tres inferieure malgre le meme volume")
	v.v(is_equal_approx(paille.proprietes.reserves.combustible.capacite, 0.75), "paille_vive (volume 5.0) doit avoir une capacite de 0.75 -- faible malgre une inflammabilite superieure a celle du bois")
	# pouvoir_calorifique 0.5 * volume 6.0 = 3.0, IDENTIQUE pour les deux -- seule la vitesse (cout_base) doit differer
	v.v(is_equal_approx(dense.proprietes.reserves.combustible.capacite, 3.0), "dense_vs_poreux_dense (volume 6.0) doit avoir une capacite de 3.0")
	v.v(is_equal_approx(poreux.proprietes.reserves.combustible.capacite, 3.0), "dense_vs_poreux_poreux (volume 6.0) doit avoir la MEME capacite que son pendant dense (3.0) -- seule densite/porosite varie entre les deux")
	v.v(dense.proprietes.reserves.combustible.cout_base < poreux.proprietes.reserves.combustible.cout_base,
		"a capacite egale, le materiau dense/peu poreux doit avoir un cout_base EFFECTIF plus bas (combustion plus lente) que le materiau leger/poreux")

func _donnees_reelles_pouvoir_calorifique_independant_d_inflammabilite(v) -> void:
	var materiaux := _charger_json("res://data/materiaux.json")
	v.v(materiaux.paille.inflammabilite > materiaux.bois.inflammabilite,
		"la paille doit etre PLUS inflammable que le bois dans le catalogue reel")
	v.v(materiaux.paille.pouvoir_calorifique < materiaux.bois.pouvoir_calorifique,
		"la paille doit avoir un pouvoir_calorifique NETTEMENT plus bas que le bois, malgre une inflammabilite plus haute -- preuve que les deux grandeurs sont independantes, jamais deduites l'une de l'autre")
	v.v(not is_equal_approx(materiaux.fer.inflammabilite / materiaux.bois.inflammabilite, materiaux.fer.pouvoir_calorifique / materiaux.bois.pouvoir_calorifique),
		"le ratio fer/bois ne doit PAS etre le meme pour inflammabilite et pour pouvoir_calorifique -- si les deux se suivaient exactement, pouvoir_calorifique ne serait qu'une copie mise a l'echelle")

func _chemin_reel_ordre_d_extinction(v) -> void:
	var donnees := _charger_json("res://data/banc_combustible.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var reserve_combustible := _charger_json("res://data/reserve_combustible_composition.json")
	var seuils_combustible := _charger_json("res://data/seuils_combustible.json")

	var catalogue_types: Dictionary = {}
	for decl in donnees.objets:
		catalogue_types[decl.id] = {"composition": decl.composition}

	var monde: Array = []
	for decl in donnees.objets:
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3.ZERO, catalogue_types, materiaux, [], reserve_combustible)
		objet.proprietes["brule"] = true
		monde.append(objet)

	var ordre_extinction: Array = []
	var pas := 0.02
	for i in 2000:
		var franchis: Array = Depense.avancer(monde, pas, seuils_combustible)
		for id in franchis:
			if not ordre_extinction.has(id):
				ordre_extinction.append(id)
		if ordre_extinction.size() == monde.size():
			break

	# ORDRE CHANGE par le chantier "densite et porosite sur la vitesse de
	# combustion" : paille_vive passe DEVANT fer_meme_volume -- sa forte
	# porosite (0.9) accelere son cout_base effectif (2.07) bien au-dela du
	# forfait de reference (1.0), pendant que la densite du fer (7.87) fait
	# l'inverse (cout_base effectif 0.21) -- l'ecart de capacite (fer 0.24
	# contre paille 0.75) ne suffit plus a compenser l'ecart de vitesse.
	# Verifie par script jetable cette session (jamais commite) avant
	# d'ecrire cette assertion, jamais devine.
	v.v(ordre_extinction == ["paille_vive", "fer_meme_volume", "dense_vs_poreux_poreux", "bois_petit", "bois_moyen", "bois_grand", "dense_vs_poreux_dense"],
		"l'ordre d'extinction reel doit etre EXACTEMENT paille_vive, fer_meme_volume, dense_vs_poreux_poreux, bois_petit, bois_moyen, bois_grand, dense_vs_poreux_dense -- capacite ET vitesse (densite/porosite) combinees, jamais ecrit a la main. Ordre obtenu : %s" % str(ordre_extinction))

	for chose in monde:
		v.v(not chose.proprietes.get("brule", false), "%s doit avoir 'brule' retire une fois epuise" % chose.id)
		var restant := Combustible.restant(chose, "combustible")
		# BORNE BASSE (bug ferme 2026-08-07, depense.gd) : une reserve epuisee
		# est EXACTEMENT 0.0, plus jamais negative -- assertion resserree
		# depuis "<= 0.0" (qui tolerait encore le defaut avant ce bug).
		v.v(restant.absolu == 0.0, "%s doit avoir une reserve residuelle EXACTEMENT nulle une fois epuise, jamais negative" % chose.id)
		v.v(restant.proportion == 0.0, "%s doit avoir une proportion residuelle EXACTEMENT nulle une fois epuise" % chose.id)
