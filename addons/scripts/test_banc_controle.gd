extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_controle.gd
#
# CHEMIN REEL (meme regime que test_banc_genetique.gd, PAS hors domaine --
# ce banc fabrique un VRAI golem et un VRAI colon Orion) : tout est lu sur
# disque (data/types.json, data/banc_controle.json, data/canaux.json,
# data/menaces.json, data/profils_saillance.json, data/types_choses.json,
# data/orientations.json, data/transformations.json, data/deformations.json),
# jamais une fixture inventee pour les catalogues partages. Verrouille la
# FONDATION du chantier "controle direct du joueur" : un golem OBEIT
# (avancer_controle), un colon DECIDE SEUL (pipeline complet, inchange) --
# AUCUN mecanisme du cœur n'est jamais exerce differemment ici, seul le
# cablage de banc_controle.gd change de branche selon "controlable".

const BancControle = preload("res://scripts/banc_controle.gd")
const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Depense = preload("res://scripts/depense.gd")
const Extinction = preload("res://scripts/extinction.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA_TICK := 0.1

func _init() -> void:
	var v := Verif.new()
	_defauts_neutres_sur_dynamique_colon_ne_surcharge_rien(v)
	_golem_local_surcharge_controlable_et_max_par_joueur(v)
	_fabriquer_golem_transmet_lie_au_joueur_si_present(v)
	_fabriquer_golem_sans_lie_au_joueur_reste_au_defaut_neutre(v)
	_golem_suit_l_ordre_jusqu_a_l_arrivee(v)
	_golem_sans_ordre_reste_immobile(v)
	_ordre_efface_une_fois_arrive(v)
	_controlable_false_ignore_ordre_joueur_meme_si_pose(v)
	_golems_du_joueur_compte_seulement_les_revendiques(v)
	_peut_prendre_controle_bascule_strictement_au_plafond(v)
	_colon_reel_percoit_le_feu_et_l_eteint_pipeline_complet(v)
	_golem_ne_reagit_jamais_au_feu(v)
	_resumabilite_json_stricte(v)
	_couleurs_lisent_le_nom_pose_jamais_le_defaut(v)
	_imprimer_action_colon_change_seulement_sur_changement_reel(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_controle.gd pose la fondation du controle direct du joueur -- " +
			"un golem controlable obeit a un ordre pose en donnee, un colon decide seul " +
			"via le pipeline complet inchange, aucun mecanisme du coeur n'est touche")
		quit(0)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

# Reproduit EXACTEMENT le chargement de banc_controle.gd:_ready -- lu sur
# disque, jamais une fixture locale pour les catalogues partages.
func _catalogues() -> Dictionary:
	var donnees := _charger_json("res://data/banc_controle.json")
	var catalogue_types: Dictionary = donnees.get("types", {}).duplicate(true)
	var types_partages := _charger_json("res://data/types.json")
	catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	catalogue_types["percevant"] = types_partages.get("percevant", {})
	catalogue_types["agent"] = types_partages.get("agent", {})
	catalogue_types["colon"] = types_partages.get("colon", {})
	var donnees_transformations := _charger_json("res://data/transformations.json")
	return {
		"donnees": donnees,
		"types": catalogue_types,
		"types_partages": types_partages,
		"canaux": _charger_json("res://data/canaux.json"),
		"menaces": _charger_json("res://data/menaces.json"),
		"profils_saillance": _charger_json("res://data/profils_saillance.json"),
		"actions": _charger_json("res://data/types_choses.json"),
		"orientations": _charger_json("res://data/orientations.json"),
		"transformations": donnees_transformations.get("transformations", {}),
		"deformations": _charger_json("res://data/deformations.json"),
	}

func _fabriquer_golem(cat: Dictionary) -> Dictionary:
	return BancControle.fabriquer_golem("golem_1", "golem", cat.donnees.get("golem", {}), cat.types)

func _fabriquer_colon(cat: Dictionary) -> Dictionary:
	return BancCommun.fabriquer_colon("colon_1", "colon", cat.donnees.get("colon", {}), cat.types)

# Verrou direct de la decision Yael : "la difference vit en donnee, jamais
# en code moteur" -- un colon fabrique depuis data/types.json:colon SANS
# aucune surcharge de ce chantier reste au defaut neutre de "dynamique"
# (false/{}/""), jamais une alarme, jamais un code special pour "ceci n'est
# pas controlable".
func _defauts_neutres_sur_dynamique_colon_ne_surcharge_rien(v) -> void:
	var cat := _catalogues()
	var colon := _fabriquer_colon(cat)
	v.v(colon.proprietes.controlable == false, "un colon ne surcharge jamais 'controlable' -- reste au defaut neutre false de dynamique")
	v.v(colon.proprietes.ordre_joueur == {}, "un colon ne surcharge jamais 'ordre_joueur' -- reste au defaut neutre {} de dynamique")
	v.v(colon.proprietes.lie_au_joueur == "", "un colon ne surcharge jamais 'lie_au_joueur' -- reste au defaut neutre '' de dynamique")

func _golem_local_surcharge_controlable_et_max_par_joueur(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	v.v(golem.proprietes.controlable == true, "le type local 'golem' (data/banc_controle.json) doit surcharger 'controlable' a true")
	v.v(golem.proprietes.max_par_joueur == 3, "le type local 'golem' doit porter max_par_joueur == 3, en donnee")
	# Doctrine des compartiments (docs/design.md) : le golem porte les CINQ
	# canaux du paquet, plus sa propre energie. Ceux dont il n'a que faire
	# sont ETEINTS -- pleins et sans cout, jamais retires et jamais a zero,
	# une reserve a zero etant lue comme un manque MAXIMAL partout ailleurs.
	v.v(golem.proprietes.reserves.size() == 5,
		"le golem doit porter les cinq compartiments du paquet, jamais un seul")
	for canal in ["faim", "soif", "sommeil", "chaleur"]:
		var c: Dictionary = golem.proprietes.reserves.get(canal, {})
		v.v(c.get("reserve", -1.0) == 100.0, "le compartiment eteint '%s' doit rester PLEIN" % canal)
		v.v(c.get("cout_base", -1.0) == 0.0 and c.get("surcout_action", -1.0) == 0.0,
			"le compartiment eteint '%s' ne doit rien couter, donc jamais descendre" % canal)
	v.v(golem.proprietes.reserves.energie.surcout_action == 2.5,
		"la seule reserve VIVE du golem garde son surcout de controlabilite")

func _fabriquer_golem_transmet_lie_au_joueur_si_present(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	v.v(golem.proprietes.lie_au_joueur == "joueur_1", "fabriquer_golem doit transmettre 'lie_au_joueur' depuis data/banc_controle.json:golem")

func _fabriquer_golem_sans_lie_au_joueur_reste_au_defaut_neutre(v) -> void:
	var cat := _catalogues()
	var golem := BancControle.fabriquer_golem("golem_2", "golem", {"position": [0.0, 0.0, 0.0]}, cat.types)
	v.v(golem.proprietes.lie_au_joueur == "", "sans 'lie_au_joueur' dans decl, le golem doit rester au defaut neutre '' de dynamique, jamais une alarme")

func _golem_suit_l_ordre_jusqu_a_l_arrivee(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	var position_depart: Vector3 = golem.position
	var cible := Vector3(500.0, 300.0, 0.0)
	BancControle.donner_ordre(golem, cible)
	v.v(not golem.proprietes.ordre_joueur.is_empty(), "donner_ordre doit remplir 'ordre_joueur'")
	var arrive := false
	for i in range(500):
		BancControle.avancer_controle(golem, DELTA_TICK)
		if golem.position.distance_to(cible) < 3.0:
			arrive = true
			break
	v.v(arrive, "un golem controlable avec un ordre doit finir par atteindre sa cible")
	v.v(golem.position.distance_to(position_depart) > 100.0, "le golem doit s'etre reellement deplace depuis son point de depart")

func _golem_sans_ordre_reste_immobile(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	var position_depart: Vector3 = golem.position
	v.v(golem.proprietes.ordre_joueur == {}, "un golem fraichement fabrique ne porte aucun ordre")
	for i in range(100):
		BancControle.avancer_controle(golem, DELTA_TICK)
	v.v(golem.position == position_depart, "sans ordre, un golem controlable ne doit JAMAIS bouger -- aucun repli sur une decision autonome")

func _ordre_efface_une_fois_arrive(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	BancControle.donner_ordre(golem, golem.position + Vector3(10.0, 0.0, 0.0))
	for i in range(200):
		BancControle.avancer_controle(golem, DELTA_TICK)
		if golem.proprietes.ordre_joueur.is_empty():
			break
	v.v(golem.proprietes.ordre_joueur == {}, "l'ordre doit s'effacer (retour a {}) une fois la cible atteinte, jamais rester pose indefiniment")

# Verrou direct de la decision Yael : "controlable: false ignore ordre_joueur
# meme si pose" -- un ordre pose A LA MAIN sur un colon (controlable reste a
# son defaut false) ne doit produire AUCUN mouvement par avancer_controle,
# meme apres de nombreux ticks.
func _controlable_false_ignore_ordre_joueur_meme_si_pose(v) -> void:
	var cat := _catalogues()
	var colon := _fabriquer_colon(cat)
	var position_depart: Vector3 = colon.position
	BancControle.donner_ordre(colon, colon.position + Vector3(999.0, 0.0, 0.0))
	v.v(not colon.proprietes.ordre_joueur.is_empty(), "donner_ordre ecrit bien 'ordre_joueur', que l'entite soit controlable ou non")
	for i in range(200):
		BancControle.avancer_controle(colon, DELTA_TICK)
	v.v(colon.position == position_depart, "un colon (controlable: false) doit rester immobile malgre un ordre pose -- avancer_controle ne lit jamais l'ordre d'une entite non controlable")

func _golems_du_joueur_compte_seulement_les_revendiques(v) -> void:
	var objets: Array = [
		{"proprietes": {"lie_au_joueur": "joueur_1"}},
		{"proprietes": {"lie_au_joueur": "joueur_1"}},
		{"proprietes": {"lie_au_joueur": "joueur_2"}},
		{"proprietes": {}},
	]
	v.v(BancControle.golems_du_joueur(objets, "joueur_1") == 2, "seules les entites 'lie_au_joueur' == id_joueur doivent compter")
	v.v(BancControle.golems_du_joueur(objets, "joueur_2") == 1, "un autre id_joueur doit compter separement")
	v.v(BancControle.golems_du_joueur(objets, "joueur_3") == 0, "un id_joueur jamais revendique doit compter 0, jamais une alarme")

func _peut_prendre_controle_bascule_strictement_au_plafond(v) -> void:
	var deux: Array = [
		{"proprietes": {"lie_au_joueur": "joueur_1"}},
		{"proprietes": {"lie_au_joueur": "joueur_1"}},
	]
	var trois: Array = deux + [{"proprietes": {"lie_au_joueur": "joueur_1"}}]
	v.v(BancControle.peut_prendre_controle(deux, "joueur_1", 3), "sous le plafond (2 < 3), le joueur doit pouvoir prendre le controle d'une entite de plus")
	v.v(not BancControle.peut_prendre_controle(trois, "joueur_1", 3), "A EGALITE du plafond (3 == 3), le joueur ne doit plus pouvoir en prendre une de plus")

# Feu en FIXTURE LOCALE au test (position choisie a portee de vue du colon,
# 1600.0, meme discipline que test_banc_genetique.gd:POSITION_FEU_TEST).
func _colon_reel_percoit_le_feu_et_l_eteint_pipeline_complet(v) -> void:
	var cat := _catalogues()
	var colon := _fabriquer_colon(cat)
	var feu := Objet.fabriquer("feu_test", "feu", colon.position + Vector3(400.0, 0.0, 0.0), cat.types)
	var monde := Monde.new()
	monde.ajouter(colon, "colon", colon.position)
	monde.ajouter(feu, "feu", feu.position)

	var perceptions: Array = load("res://scripts/perception.gd").percevoir(colon, monde, cat.canaux)
	v.v(BancControle._percoit_declencheur_statique(perceptions, "brule"), "le colon doit percevoir le feu (400 unites, sous la portee de vue 1600.0)")

	var eteint := false
	for i in range(300):
		BancControle.agir_et_deplacer(colon, monde, cat.canaux, cat.menaces, cat.profils_saillance, cat.deformations, cat.actions, cat.orientations, DELTA_TICK)
		var agents := BancCommun.agents_rythme([colon])
		var eteints: Array = Extinction.avancer([feu], agents, DELTA_TICK, cat.transformations)
		if eteints.has(feu.id):
			eteint = true
			break
	v.v(eteint, "le colon doit finir par decider seul de s'approcher du feu et de l'eteindre -- pipeline complet, aucun ordre joueur implique")
	v.v(not feu.proprietes.has("brule"), "le feu eteint ne doit plus porter 'brule' (a_zero, transformations.json:defaut)")

# CE QU'ON DOIT VOIR, point 3 : "Un feu fait reagir le colon, pas le golem."
# Le golem ne compose que 'dynamique' (herite: ["dynamique"], voir
# data/banc_controle.json) -- pas 'percevant' : il ne porte structurellement
# pas 'canaux', donc aucun mecanisme de perception ne peut jamais le faire
# reagir a quoi que ce soit. Verrouille l'ABSENCE de la cle plutot qu'un
# comportement (rien a simuler : sans "canaux", Perception.percevoir
# alarmerait puis rendrait [] -- ce test verrouille la cause, pas l'effet
# deja verrouille par test_perception.gd).
func _golem_ne_reagit_jamais_au_feu(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	v.v(not golem.proprietes.has("canaux"), "le golem ne doit composer aucun paquet portant 'canaux' -- structurellement incapable de percevoir un feu")
	v.v(not golem.proprietes.has("attaches"), "le golem ne doit composer aucun paquet portant 'attaches' -- structurellement incapable de decider")

func _resumabilite_json_stricte(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	BancControle.donner_ordre(golem, golem.position + Vector3(50.0, 0.0, 0.0))
	BancControle.avancer_controle(golem, DELTA_TICK)
	var colon := _fabriquer_colon(cat)
	Depense.avancer([golem, colon], DELTA_TICK, {})

	var texte_golem := JSON.stringify(golem)
	var relu_golem: Variant = JSON.parse_string(texte_golem)
	v.v(relu_golem != null, "JSON.stringify puis parse_string du golem doit reussir sans erreur")
	v.v(relu_golem.proprietes.ordre_joueur.cible.x == golem.proprietes.ordre_joueur.cible.x,
		"ordre_joueur (Dictionary pur) doit survivre identique a l'aller-retour JSON")
	v.v(is_equal_approx(relu_golem.proprietes.reserves.energie.reserve, golem.proprietes.reserves.energie.reserve),
		"la reserve d'energie du golem doit survivre identique a l'aller-retour JSON")

	var texte_colon := JSON.stringify(colon)
	var relu_colon: Variant = JSON.parse_string(texte_colon)
	v.v(relu_colon != null, "JSON.stringify puis parse_string du colon doit reussir sans erreur")
	v.v(relu_colon.proprietes.controlable == colon.proprietes.controlable,
		"'controlable' (bool pur) doit survivre identique a l'aller-retour JSON")

# Audit couverture 2026-08-06 : _couleur_de/_couleur_reserve/
# _imprimer_action_colon sont des fonctions INSTANCE, aucune appelee par un
# test avant cette session. Meme patron que les autres bancs :
# BancControle.new() nu, jamais ajoute a l'arbre.

func _couleurs_lisent_le_nom_pose_jamais_le_defaut(v) -> void:
	var b := BancControle.new()
	b._couleurs_types = {"golem": [0.6, 0.1, 0.8]}
	b._couleurs_reserves = {"energie": [0.9, 0.6, 0.1]}
	v.v(b._couleur_de("golem") == Color(0.6, 0.1, 0.8), "_couleur_de doit rendre la couleur posee, pas le defaut blanc")
	v.v(b._couleur_de("inconnu") == Color(1.0, 1.0, 1.0), "_couleur_de : nom absent -> blanc par defaut")
	v.v(b._couleur_reserve("energie") == Color(0.9, 0.6, 0.1), "_couleur_reserve doit rendre la couleur posee")
	v.v(b._couleur_reserve("inconnu") == Color(1.0, 1.0, 1.0), "_couleur_reserve : nom absent -> blanc par defaut")

func _imprimer_action_colon_change_seulement_sur_changement_reel(v) -> void:
	var b := BancControle.new()
	b._transformations = {}
	b._colon_action_precedente = "__jamais__"

	var g_rien := {"decision": null, "chose": null, "cible": Vector3.ZERO, "position_avant": Vector3.ZERO}
	b._imprimer_action_colon(g_rien)
	v.v(b._colon_action_precedente == "RIEN", "sans decision, l'etiquette doit etre RIEN")

	var feu := {"id": "feu_1", "position": Vector3(5, 0, 0), "proprietes": {}}
	var g_feu := {"decision": {"type": "brule"}, "chose": feu, "cible": feu.position, "position_avant": Vector3.ZERO}
	b._imprimer_action_colon(g_feu)
	v.v(b._colon_action_precedente.begins_with("feu_1"), "une decision resolue doit nommer la chose visee, pas rester RIEN")

	var precedente: String = b._colon_action_precedente
	b._imprimer_action_colon(g_feu)
	v.v(b._colon_action_precedente == precedente, "meme decision rejouee : l'etiquette ne doit pas changer")
