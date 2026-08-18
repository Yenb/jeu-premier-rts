extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_champ.gd
#
# CHEMIN REEL (meme regime que test_banc_controle.gd -- ce banc fabrique un
# VRAI golem et un VRAI aimant Orion) : tout est lu sur disque
# (data/types.json, data/banc_champ.json, data/champs.json), jamais une
# fixture inventee pour les catalogues. Verrouille la COMPOSITION du pas
# volontaire (BancControle.avancer_controle/donner_ordre, REUTILISES sans
# modification) et de la deviation subie (Champ.avancer, PAR-DESSUS,
# scripts/banc_champ.gd:_process) : loin, le clic gagne ; pres, la traction
# domine SANS aucune branche "if domine" nulle part.

const BancChamp = preload("res://scripts/banc_champ.gd")
const BancControle = preload("res://scripts/banc_controle.gd")
const Champ = preload("res://scripts/champ.gd")
const Verif = preload("res://scripts/verif.gd")

# NOTE : contrairement a test_banc_controle.gd (delta 0.1, sans consequence
# la-bas -- bouger_vers borne son pas par la DISTANCE restante, pas par un
# plafond fixe), "plafond_deplacement" de champ.gd est un plafond FIXE, en
# unites, jamais mis a l'echelle de delta -- un delta trop grand fait
# atteindre ce plafond plus tot, ce qui AFFAIBLIT la traction relative au
# pas volontaire (qui, lui, continue de grandir avec delta). Ce test utilise
# donc un delta proche d'une vraie image (1/60 s), la meme grandeur que la
# calibration de data/banc_champ.json/data/champs.json suppose.
const DELTA_TICK := 1.0 / 60.0

func _init() -> void:
	var v := Verif.new()
	_golem_porte_composition_masse_et_magnetisme_resolvables(v)
	_aimant_porte_une_masse_enorme_face_au_golem(v)
	_loin_le_pas_volontaire_l_emporte_meme_contre_le_champ(v)
	_pres_la_traction_domine_le_pas_volontaire_sans_branche(v)
	_aimant_quasi_immobile_meme_pres_du_golem(v)
	_hors_portee_aucune_traction_le_clic_est_seul_maitre(v)
	_resumabilite_json_stricte(v)
	_mettre_a_jour_observabilite_ecrit_distance_et_force_dans_le_label(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_champ.gd compose le pas volontaire du golem controlable (reutilise, " +
			"inchange) avec la deviation de champ.gd -- loin le clic gagne, pres la traction " +
			"domine, sans aucune branche 'if domine'")
		quit(0)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _catalogues() -> Dictionary:
	var donnees := _charger_json("res://data/banc_champ.json")
	var catalogue_types: Dictionary = donnees.get("types", {}).duplicate(true)
	var types_partages := _charger_json("res://data/types.json")
	catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	return {
		"donnees": donnees,
		"types": catalogue_types,
		"materiaux": _charger_json("res://data/materiaux.json"),
		"champs": _charger_json("res://data/champs.json"),
	}

func _fabriquer_golem(cat: Dictionary) -> Dictionary:
	return BancChamp.fabriquer_golem_magnetique("golem_1", "golem_magnetique", cat.donnees.get("golem", {}), cat.types, cat.materiaux)

func _fabriquer_aimant(cat: Dictionary, position: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"id": "aimant_1", "position": position, "proprietes": BancChamp._fabriquer_aimant("aimant_1", "aimant", cat.donnees.get("aimant", {}), cat.types, cat.materiaux).proprietes}

func _golem_porte_composition_masse_et_magnetisme_resolvables(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	v.v(not golem.is_empty(), "le golem magnetique doit se fabriquer sans etre refuse (materiau resolvable)")
	v.v(golem.proprietes.has("composition"), "le golem doit porter 'composition' (propriete source lue a la demande)")
	v.v(golem.proprietes.masse > 0.0, "la masse doit etre calculee a la fabrication (densite effective)")
	v.v(golem.proprietes.controlable == true, "le golem magnetique reste controlable, meme type de cle que banc_controle.gd")

func _aimant_porte_une_masse_enorme_face_au_golem(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	var aimant := BancChamp._fabriquer_aimant("aimant_1", "aimant", cat.donnees.get("aimant", {}), cat.types, cat.materiaux)
	v.v(not aimant.is_empty(), "l'aimant doit se fabriquer sans etre refuse")
	v.v(aimant.proprietes.masse > golem.proprietes.masse * 100.0,
		"l'aimant doit etre bien plus massif que le golem -- l'immobilite doit emerger du rapport de masse, aucune propriete 'fixe'")
	v.v(not aimant.proprietes.has("controlable"), "l'aimant ne compose pas 'dynamique' -- aucune notion de controle")

# Loin dans la portee (200 unites, portee 240) : le clic vers l'oppose de
# l'aimant doit rester net GAGNANT malgre la traction.
func _loin_le_pas_volontaire_l_emporte_meme_contre_le_champ(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	var aimant := _fabriquer_aimant(cat, Vector3.ZERO)
	golem.position = Vector3(200.0, 0.0, 0.0)
	var distance_avant: float = golem.position.distance_to(aimant.position)
	BancControle.donner_ordre(golem, Vector3(2000.0, 0.0, 0.0))
	BancControle.avancer_controle(golem, DELTA_TICK)
	Champ.avancer([golem, aimant], DELTA_TICK, cat.champs, cat.materiaux)
	var distance_apres: float = golem.position.distance_to(aimant.position)
	v.v(distance_apres > distance_avant, "loin (200 unites), le clic vers l'oppose doit l'emporter net sur la traction")

# Pres du point de bascule (80 unites, ~2m) : meme en cliquant vers
# l'oppose de l'aimant, la traction doit l'emporter NET -- aucune branche
# "if domine" n'existe, la domination emerge de la somme des deux pas.
func _pres_la_traction_domine_le_pas_volontaire_sans_branche(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	var aimant := _fabriquer_aimant(cat, Vector3.ZERO)
	golem.position = Vector3(80.0, 0.0, 0.0)
	var distance_avant: float = golem.position.distance_to(aimant.position)
	BancControle.donner_ordre(golem, Vector3(2000.0, 0.0, 0.0))
	BancControle.avancer_controle(golem, DELTA_TICK)
	Champ.avancer([golem, aimant], DELTA_TICK, cat.champs, cat.materiaux)
	var distance_apres: float = golem.position.distance_to(aimant.position)
	v.v(distance_apres < distance_avant,
		"pres du point de bascule (80 unites), la traction doit l'emporter NET sur un clic vers l'oppose")

func _aimant_quasi_immobile_meme_pres_du_golem(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	var aimant := _fabriquer_aimant(cat, Vector3.ZERO)
	golem.position = Vector3(60.0, 0.0, 0.0)
	var position_aimant_avant: Vector3 = aimant.position
	for i in range(20):
		Champ.avancer([golem, aimant], DELTA_TICK, cat.champs, cat.materiaux)
	v.v(aimant.position.distance_to(position_aimant_avant) < 1.0,
		"l'aimant (masse enorme) doit rester quasi immobile meme apres plusieurs ticks pres du golem")

func _hors_portee_aucune_traction_le_clic_est_seul_maitre(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	var aimant := _fabriquer_aimant(cat, Vector3.ZERO)
	golem.position = Vector3(1000.0, 0.0, 0.0)
	BancControle.donner_ordre(golem, Vector3(500.0, 0.0, 0.0))
	var deplaces := Champ.avancer([golem, aimant], DELTA_TICK, cat.champs, cat.materiaux)
	v.v(deplaces.is_empty(), "hors de 'portee' (1000 unites), champ.gd ne doit rien deplacer")

func _resumabilite_json_stricte(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	var aimant := _fabriquer_aimant(cat, Vector3.ZERO)
	golem.position = Vector3(60.0, 0.0, 0.0)
	Champ.avancer([golem, aimant], DELTA_TICK, cat.champs, cat.materiaux)
	var texte := JSON.stringify(golem)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string du golem doit reussir sans erreur")
	v.v(is_equal_approx(relu.proprietes.masse, golem.proprietes.masse),
		"masse doit survivre identique a l'aller-retour JSON")

# Audit couverture 2026-08-06 : _mettre_a_jour_observabilite (fonction
# INSTANCE, jamais appelee par un test avant cette session) ecrit le TEXTE
# affiche a l'ecran -- meme classe de risque que le defaut trouve par
# l'audit dans banc_inflammabilite.gd (_texte_label). Verifie que le label
# porte exactement la distance et la force REELLES, calculees
# independamment ici, jamais une valeur figee ou un ancien tick.
func _mettre_a_jour_observabilite_ecrit_distance_et_force_dans_le_label(v) -> void:
	var cat := _catalogues()
	var golem := _fabriquer_golem(cat)
	golem.position = Vector3(60.0, 0.0, 0.0)
	var aimant := _fabriquer_aimant(cat, Vector3.ZERO)

	var b := BancChamp.new()
	b._golem = golem
	b._aimant = aimant
	b._catalogue_champs = cat.champs
	b._materiaux = cat.materiaux
	b._label = Label.new()

	b._mettre_a_jour_observabilite()

	var distance: float = golem.position.distance_to(aimant.position)
	var force: float = Champ.force_paire(golem, aimant, cat.champs.get("magnetisme", {}), cat.materiaux)
	var attendu := "distance golem-aimant : %.1f u (~%.2f m) | force de traction : %.4f" % [distance, distance / 40.0, force]
	v.v(b._label.text == attendu,
		"le label doit afficher exactement la distance et la force reelles, jamais une valeur figee ou un ancien tick")
