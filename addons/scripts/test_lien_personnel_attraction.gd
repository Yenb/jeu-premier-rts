extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_lien_personnel_attraction.gd
#
# Verrouille scripts/lien_personnel_attraction.gd comme mecanisme GENERIQUE
# de generation de candidat de saillance par lien personnel -- pas un code
# de colon, de batisse ni de pompier. Domaine invente (sonde_gravitique /
# balise, jamais vus ailleurs dans le depot) pour les cas unitaires ; PUIS un
# chemin REEL (Objet.fabriquer contre data/types.json/data/liens_personnels.json
# lus sur disque, meme patron que test_proximite_deformation.gd/
# test_banc_lien_personnel.gd) qui fait tourner le pipeline complet --
# perception -> attaches + proximite + CE MECANISME -> dominance -> agir ->
# ciblage -> mouvement -- pour prouver qu'une chose aimee sans profil_
# saillance propre devient une cible physiquement atteignable.
#
# Utilise la vraie classe Monde (scripts/monde.gd, deja generique et hors
# domaine par construction) comme fixture -- pas un duck-type maison :
# monde.par_id() est le seul contrat que evaluer() attend.

const LienPersonnelAttraction = preload("res://scripts/lien_personnel_attraction.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")
const Objet = preload("res://scripts/objet.gd")
const Perception = preload("res://scripts/perception.gd")
const Attaches = preload("res://scripts/attaches.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const Ciblage = preload("res://scripts/ciblage.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

func _init() -> void:
	var v := Verif.new()
	_sans_lien_aucune_entree(v)
	_lien_sur_chose_proche_produit_une_entree(v)
	_hors_de_portee_attraction_aucune_entree(v)
	_formule_exacte_verifiee(v)
	_plusieurs_liens_produisent_des_entrees_croissantes_avec_la_force(v)
	_chose_liee_detruite_ignoree_silencieusement(v)
	_propriete_structurelle_absente_alarme(v)
	_catalogue_sans_portee_attraction_alarme(v)
	_ne_mute_jamais_liens_personnels(v)
	_resumabilite_json_stricte(v)
	_chemin_reel_chose_aimee_sans_saillance_propre_devient_cible_atteignable(v)

	if v.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % v.echecs())
		quit(1)
		return
	print("OK: lien_personnel_attraction.gd rend un candidat de saillance " +
		"pour toute chose aimee resolue et a portee, meme sans saillance " +
		"propre, generique a tout domaine invente -- chemin reel verifie : " +
		"un colon rejoint physiquement une chose aimee sans profil_saillance")
	quit(0)

func _entite(id: String, position: Vector3, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": position, "proprietes": proprietes}

func _chose(id: String, position: Vector3) -> Dictionary:
	return {"id": id, "position": position, "proprietes": {}}

func _catalogue(portee_attraction: float = 100.0) -> Dictionary:
	return {"defaut": {"portee_attraction": portee_attraction}}

func _monde_avec(choses: Array) -> Monde:
	var monde := Monde.new()
	for c in choses:
		monde.ajouter(c, "balise", c.position)
	return monde

func _sans_lien_aucune_entree(v) -> void:
	var sonde := _entite("sonde_gravitique_1", Vector3.ZERO, {"liens_personnels": {}})
	var monde := _monde_avec([])
	var sortie := LienPersonnelAttraction.evaluer(sonde, monde, _catalogue())
	v.v(sortie.is_empty(), "sans aucun lien personnel, aucune entree ne doit etre produite")

func _lien_sur_chose_proche_produit_une_entree(v) -> void:
	var balise := _chose("balise_1", Vector3(20.0, 0.0, 0.0))
	var sonde := _entite("sonde_gravitique_2", Vector3.ZERO, {"liens_personnels": {"balise_1": 1.0}})
	var monde := _monde_avec([balise])
	var sortie := LienPersonnelAttraction.evaluer(sonde, monde, _catalogue(100.0))
	v.v(sortie.size() == 1, "une chose aimee a portee doit produire exactement une entree")
	if sortie.size() == 1:
		v.v(sortie[0].chose.id == "balise_1", "l'entree doit porter la chose liee elle-meme")
		v.v(sortie[0].saillance > 0.0, "la saillance produite doit etre strictement positive")
		v.v(sortie[0].position == balise.position, "la position rendue doit etre celle, vivante, de la chose liee")

func _hors_de_portee_attraction_aucune_entree(v) -> void:
	var balise := _chose("balise_2", Vector3(500.0, 0.0, 0.0))
	var sonde := _entite("sonde_gravitique_3", Vector3.ZERO, {"liens_personnels": {"balise_2": 1.0}})
	var monde := _monde_avec([balise])
	var sortie := LienPersonnelAttraction.evaluer(sonde, monde, _catalogue(100.0))
	v.v(sortie.is_empty(), "une chose aimee hors de portee_attraction ne doit produire aucune entree")

func _formule_exacte_verifiee(v) -> void:
	var balise := _chose("balise_3", Vector3(30.0, 0.0, 0.0))
	var sonde := _entite("sonde_gravitique_4", Vector3.ZERO, {"liens_personnels": {"balise_3": 2.0}})
	var monde := _monde_avec([balise])
	var sortie := LienPersonnelAttraction.evaluer(sonde, monde, _catalogue(100.0))
	var attendu: float = 2.0 * (1.0 - 30.0 / 100.0)
	v.v(sortie.size() == 1 and is_equal_approx(sortie[0].saillance, attendu),
		"la saillance doit valoir exactement force_du_lien * (1.0 - distance / portee_attraction) (%.6f attendu, %.6f obtenu)" % [attendu, sortie[0].saillance if sortie.size() == 1 else -1.0])

func _plusieurs_liens_produisent_des_entrees_croissantes_avec_la_force(v) -> void:
	var balise_faible := _chose("balise_faible", Vector3(20.0, 0.0, 0.0))
	var balise_forte := _chose("balise_forte", Vector3(20.0, 0.0, 0.0))
	var sonde := _entite("sonde_gravitique_5", Vector3.ZERO, {
		"liens_personnels": {"balise_faible": 1.0, "balise_forte": 4.0},
	})
	var monde := _monde_avec([balise_faible, balise_forte])
	var sortie := LienPersonnelAttraction.evaluer(sonde, monde, _catalogue(100.0))
	v.v(sortie.size() == 2, "deux liens distincts doivent produire deux entrees, jamais une seule retenue")
	var saillance_faible := 0.0
	var saillance_forte := 0.0
	for entree in sortie:
		if entree.chose.id == "balise_faible":
			saillance_faible = entree.saillance
		elif entree.chose.id == "balise_forte":
			saillance_forte = entree.saillance
	v.v(saillance_faible > 0.0 and saillance_forte > 0.0,
		"les deux entrees doivent porter une saillance strictement positive")
	v.v(saillance_forte > saillance_faible,
		"a distance egale, le lien le plus fort doit produire la saillance la plus haute")

func _chose_liee_detruite_ignoree_silencieusement(v) -> void:
	var sonde := _entite("sonde_gravitique_6", Vector3.ZERO, {"liens_personnels": {"balise_disparue": 1.0}})
	var monde := _monde_avec([])
	var sortie := LienPersonnelAttraction.evaluer(sonde, monde, _catalogue(100.0))
	v.v(sortie.is_empty(), "une chose liee absente du monde (detruite) doit etre ignoree, jamais un crash")

func _propriete_structurelle_absente_alarme(v) -> void:
	var sonde := _entite("sonde_gravitique_7", Vector3.ZERO, {})
	var monde := _monde_avec([])
	var sortie := LienPersonnelAttraction.evaluer(sonde, monde, _catalogue(100.0))
	v.v(sortie.is_empty(), "une entite sans cle 'liens_personnels' doit alarmer et rendre [], jamais un defaut invente")

func _catalogue_sans_portee_attraction_alarme(v) -> void:
	var balise := _chose("balise_4", Vector3(10.0, 0.0, 0.0))
	var sonde := _entite("sonde_gravitique_8", Vector3.ZERO, {"liens_personnels": {"balise_4": 1.0}})
	var monde := _monde_avec([balise])
	var sortie := LienPersonnelAttraction.evaluer(sonde, monde, {})
	v.v(sortie.is_empty(), "un catalogue sans 'defaut.portee_attraction' doit alarmer et rendre []")

func _ne_mute_jamais_liens_personnels(v) -> void:
	var liens_avant := {"balise_5": 3.0, "balise_6": 0.5}
	var sonde := _entite("sonde_gravitique_9", Vector3.ZERO, {"liens_personnels": liens_avant.duplicate(true)})
	var balise_5 := _chose("balise_5", Vector3(10.0, 0.0, 0.0))
	var balise_6 := _chose("balise_6", Vector3(90.0, 0.0, 0.0))
	var monde := _monde_avec([balise_5, balise_6])
	LienPersonnelAttraction.evaluer(sonde, monde, _catalogue(100.0))
	v.v(sonde.proprietes.liens_personnels == liens_avant,
		"evaluer() ne doit jamais muter proprietes.liens_personnels -- lecture seule")

# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) --
# evaluer() ne mute jamais rien, mais l'entite lue doit rester JSON pur pour
# que ce mecanisme reste cablable a une entite reelle sans conversion.
func _resumabilite_json_stricte(v) -> void:
	var sonde := _entite("sonde_gravitique_10", Vector3(1.0, 0.0, 2.0), {
		"liens_personnels": {"balise_7": 0.5},
	})
	var texte := JSON.stringify(sonde)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	v.v(relu.proprietes.liens_personnels.balise_7 == 0.5,
		"liens_personnels doit survivre identique a l'aller-retour JSON")

func _types_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))

func _liens_personnels_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/liens_personnels.json"))

# CHEMIN REEL -- preuve du trou comble (voir en-tete du fichier teste) :
# "batisse" (data/types.json) ne porte NI profil_saillance NI "brule" -- une
# batisse intacte n'est saillante ni par proximite.gd (aucune reference a
# resoudre) ni par attaches.gd (le colon n'a aucune attache). SANS ce
# mecanisme, resultats reste vide et Agir.choisir rend null : le colon ne
# bouge jamais vers ce qu'il aime. AVEC : la chose aimee devient l'unique
# candidat, Agir.choisir la retient, Ciblage.viser la resout comme cible
# (branche par defaut, decision.has("chose")), et BancCommun.bouger_vers
# rapproche reellement le colon -- pipeline complet, aucune ligne du cœur
# modifiee en aval de ce fichier (ciblage.gd/agir.gd/dominance.gd/le
# mouvement sont deja generiques et suffisants).
func _chemin_reel_chose_aimee_sans_saillance_propre_devient_cible_atteignable(v) -> void:
	var types := _types_reels()
	var liens_catalogue := _liens_personnels_reels()

	var batisse := Objet.fabriquer("batisse_aimee", "batisse", Vector3(60.0, 0.0, 0.0), types)
	v.v(not batisse.proprietes.has("profil_saillance") and not batisse.proprietes.get("brule", false),
		"pre-condition du test : une batisse fraiche ne doit porter ni profil_saillance ni brule")

	var colon := Objet.fabriquer("colon_attache", "colon", Vector3.ZERO, types)
	colon.proprietes["forme"] = {}
	colon.proprietes["poids_verbes"] = {}
	colon["action_en_cours"] = {}
	# Lien personnel deja forme -- comment il s'est forme (acte liant, vecu
	# inter-colon) est hors du perimetre de ce fichier, voir agir.gd/
	# lien_personnel_croissance.gd : ce test verifie la LECTURE, pas
	# l'ECRITURE, meme separation que test_lien_personnel_saillance.gd.
	colon.proprietes["liens_personnels"] = {"batisse_aimee": 5.0}

	var monde := Monde.new()
	monde.ajouter(batisse, "batisse", batisse.position)
	monde.ajouter(colon, "colon", colon.position)

	var canaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/canaux.json"))
	var perceptions := Perception.percevoir(colon, monde, canaux)

	var att := Attaches.evaluer(perceptions, colon, {})
	var prox := Proximite.evaluer(perceptions, colon, {}, {})
	v.v((att + prox).is_empty(),
		"SANS lien_personnel_attraction.gd, une batisse intacte sans attache ne doit produire aucun candidat")

	var attraction := LienPersonnelAttraction.evaluer(colon, monde, liens_catalogue)
	v.v(attraction.size() == 1 and attraction[0].chose.id == "batisse_aimee",
		"AVEC lien_personnel_attraction.gd, la batisse aimee doit devenir l'unique candidat")

	var resultats: Array = att + prox + attraction
	var vus := Dominance.visibles(resultats, colon)
	v.v(vus.size() == 1, "la batisse aimee, seule candidate, doit rester seule visible")

	var decision = Agir.choisir(vus, colon, {}, monde)
	v.v(decision != null, "le colon doit decider d'agir vers la chose aimee")
	if decision == null:
		return
	v.v(decision.chose.id == "batisse_aimee", "la decision doit porter sur la batisse aimee")

	var chose = Ciblage.viser(decision, perceptions, {}, {}, {})
	v.v(chose != null and chose.id == "batisse_aimee",
		"ciblage.gd doit resoudre la batisse aimee comme cible, sans aucune ligne de ciblage.gd modifiee")

	var distance_avant: float = colon.position.distance_to(batisse.position)
	var nouvelle_position: Vector3 = BancCommun.bouger_vers(colon.position, chose.position, 150.0, 1.0)
	var distance_apres: float = nouvelle_position.distance_to(batisse.position)
	v.v(distance_apres < distance_avant,
		"le colon doit physiquement se rapprocher de la chose aimee (%.2f avant, %.2f apres)" % [distance_avant, distance_apres])
