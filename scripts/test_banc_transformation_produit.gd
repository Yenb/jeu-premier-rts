extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_transformation_produit.gd
#
# Cablage de banc_transformation_produit.gd, PREMIERE demonstration
# reelle du chantier "transformation produit un objet neuf"
# (scripts/produit.gd, scripts/extinction.gd:a_zero.produire) sur les
# vraies donnees (data/types.json, data/materiaux.json, data/
# transformations.json, data/banc_transformation_produit.json lus sur
# disque -- PAS hors domaine, ce test verrouille la chaine reelle
# bois -> charbon -> cendre).
#
# Meme patron que les autres bancs : BancTransformationProduit.new() nu,
# jamais ajoute a l'arbre -- _noeud/_label sont des instances de Control
# non attachees (legal, aucun rendu requis pour muter .color/.text).

const BancTransformationProduit = preload("res://scripts/banc_transformation_produit.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_materiau_actuel_lit_le_premier_element_de_composition(v)
	_materiau_actuel_vide_sans_composition(v)
	_rendements_par_produit_chemin_reel(v)
	_texte_rendement_distingue_origine_et_pourcentage(v)
	_texte_label_format_exact(v)
	_ligne_pose_et_transition_format_exact(v)
	_couleur_pour_materiau_replie_sur_blanc_si_absent(v)
	_chemin_reel_chaine_bois_charbon_cendre(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_transformation_produit cable la chaine reelle bois -> charbon -> cendre, masse exacte a chaque etape")
		quit(0)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

# ---- Fonctions pures ------------------------------------------------

func _materiau_actuel_lit_le_premier_element_de_composition(v) -> void:
	var proprietes := {"composition": [{"materiau": "charbon", "volume": 1.0}]}
	v.v(BancTransformationProduit._materiau_actuel(proprietes) == "charbon",
		"_materiau_actuel doit lire le premier element de composition")

func _materiau_actuel_vide_sans_composition(v) -> void:
	v.v(BancTransformationProduit._materiau_actuel({}) == "", "sans composition, materiau actuel vide")
	v.v(BancTransformationProduit._materiau_actuel({"composition": []}) == "", "composition vide, materiau actuel vide")

func _rendements_par_produit_chemin_reel(v) -> void:
	var transformations: Dictionary = _charger_json("res://data/transformations.json").transformations
	var rendements := BancTransformationProduit._rendements_par_produit(transformations)
	v.v(is_equal_approx(rendements.get("charbon", -1.0), 0.30), "combustion_bois doit produire charbon a rendement 0.30")
	v.v(is_equal_approx(rendements.get("cendre", -1.0), 0.05), "combustion_charbon doit produire cendre a rendement 0.05")
	v.v(not rendements.has("bois"), "rien ne produit 'bois' -- il ne doit jamais apparaitre dans la table des rendements")

func _texte_rendement_distingue_origine_et_pourcentage(v) -> void:
	v.v(BancTransformationProduit._texte_rendement(null) == "origine", "sans rendement (origine de la chaine), texte 'origine'")
	v.v(BancTransformationProduit._texte_rendement(0.3) == "30%", "rendement 0.3 doit s'afficher '30%'")
	v.v(BancTransformationProduit._texte_rendement(0.05) == "5%", "rendement 0.05 doit s'afficher '5%'")

func _texte_label_format_exact(v) -> void:
	var texte := BancTransformationProduit._texte_label("charbon", 540.0, 0.3)
	v.v(texte.find("charbon") != -1, "le label doit nommer le materiau actuel")
	v.v(texte.find("540.00") != -1, "le label doit afficher la masse exacte")
	v.v(texte.find("30%") != -1, "le label doit afficher le rendement applique")

func _ligne_pose_et_transition_format_exact(v) -> void:
	var pose := BancTransformationProduit._ligne_pose(0.0, "bois", 1800.0)
	v.v(pose == "t=0.0s : bois en combustion, masse=1800.00", "la ligne de pose doit avoir le format exact")
	var transition := BancTransformationProduit._ligne_transition(3.0, "bois", "charbon", 0.3, 1800.0, 540.0)
	v.v(transition == "t=3.0s : bois -> charbon (rendement 30%, masse 1800.00 -> 540.00)",
		"la ligne de transition doit avoir le format exact")

func _couleur_pour_materiau_replie_sur_blanc_si_absent(v) -> void:
	var couleurs := {"bois": [0.5, 0.3, 0.1]}
	v.v(BancTransformationProduit._couleur_pour_materiau("bois", couleurs) == Color(0.5, 0.3, 0.1),
		"une couleur declaree doit se lire telle quelle")
	v.v(BancTransformationProduit._couleur_pour_materiau("fantome", couleurs) == Color(1.0, 1.0, 1.0),
		"un materiau sans couleur declaree doit se replier sur blanc")

# ---- Chemin reel, de bout en bout ------------------------------------

# Reproduit EXACTEMENT le geste de fabrication de _ready() (sans add_child,
# voir en-tete) puis fait avancer _process() jusqu'a ce que la chaine soit
# entierement consommee (cendre, plus de chantier). Verifie la masse EXACTE
# a chaque etape contre les rendements REELS de data/transformations.json.
func _chemin_reel_chaine_bois_charbon_cendre(v) -> void:
	var catalogue_types := _charger_json("res://data/types.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var transformations: Dictionary = _charger_json("res://data/transformations.json").transformations
	var donnees := _charger_json("res://data/banc_transformation_produit.json")

	var decl: Dictionary = donnees.objet
	var pos_arr: Array = decl.position
	var pos := Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
	catalogue_types[decl.id] = {"composition": decl.composition}

	var objet := Objet.fabriquer(decl.id, decl.id, pos, catalogue_types, materiaux)
	var masse_initiale: float = objet.proprietes.masse
	objet.proprietes["brule"] = true
	objet.proprietes["travail_restant"] = donnees.travail_restant_initial
	objet.proprietes["travail_initial"] = donnees.travail_initial_initial
	objet.proprietes["transformation"] = donnees.transformation_initiale

	var b := BancTransformationProduit.new()
	b._noeud = ColorRect.new()
	b._label = Label.new()
	b._monde = [objet]
	b._agents = [{"position": pos, "rythme": donnees.rythme_combustion}]
	b._transformations = transformations
	b._catalogue_types = catalogue_types
	b._materiaux = materiaux
	b._couleurs = donnees.couleurs
	b._rendements = BancTransformationProduit._rendements_par_produit(transformations)
	b._dernier_materiau = BancTransformationProduit._materiau_actuel(objet.proprietes)
	b._derniere_masse = masse_initiale

	var vu_charbon := false
	var masse_a_charbon := -1.0
	for i in 600:
		b._process(0.1)
		var materiau := BancTransformationProduit._materiau_actuel(b._monde[0].proprietes)
		if materiau == "charbon" and not vu_charbon:
			vu_charbon = true
			masse_a_charbon = b._monde[0].proprietes.masse
		if not b._monde[0].proprietes.has("travail_restant") and not b._monde[0].proprietes.has("transformation"):
			break

	v.v(vu_charbon, "la chaine doit passer par le charbon avant la cendre")
	v.v(is_equal_approx(masse_a_charbon, masse_initiale * 0.30),
		"la masse de charbon doit valoir exactement 30%% de la masse initiale de bois (%.4f vu, %.4f attendu)" %
			[masse_a_charbon, masse_initiale * 0.30])

	var p_finale: Dictionary = b._monde[0].proprietes
	v.v(BancTransformationProduit._materiau_actuel(p_finale) == "cendre",
		"la chaine doit se terminer en cendre")
	v.v(is_equal_approx(p_finale.masse, masse_a_charbon * 0.05),
		"la masse de cendre doit valoir exactement 5%% de la masse de charbon (%.4f vu, %.4f attendu)" %
			[p_finale.masse, masse_a_charbon * 0.05])
	v.v(not p_finale.has("travail_restant") and not p_finale.has("transformation"),
		"la cendre ne doit plus porter de chantier -- fin de chaine")
