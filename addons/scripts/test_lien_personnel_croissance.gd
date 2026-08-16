extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_lien_personnel_croissance.gd
#
# Verrouille scripts/lien_personnel_croissance.gd comme mecanisme GENERIQUE
# de croissance de lien personnel PAR PERCEPTION, avec la convention
# CORRIGEE (montant fixe par pose, cooldown -- voir en-tete du fichier,
# chantier correction "banc invisible") -- pas un code de colon, de couleur
# ni d'arbre. Domaine hors jeu Orion : des fourmis qui percoivent d'autres
# fourmis porteuses d'une piste de pheromone ("odeur_sucre"), jamais vu
# ailleurs dans le depot.
#
# CAS _pose_seulement_apres_intervalle : le cas qui aurait attrape le bug
# audite (montant multiplie par delta, efface a chaque frame par
# lien_personnel.gd:avancer avant meme le premier plancher_suppression) --
# simule des deltas REALISTES (0.1s, pas le DELTA_TICK 1.0 de l'ancienne
# version de ce test, qui masquait exactement ce bug en le faisant
# coincider par accident avec la convention corrigee).
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque (le
# catalogue de croissance et celui de lien_personnel.gd sont des Dictionary
# construits ici, jamais data/lien_personnel_croissance.json ni
# data/liens_personnels.json).

const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const LienPersonnelCroissance = preload("res://scripts/lien_personnel_croissance.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_formation_de_lien_sur_perception_du_trait(v)
	_pas_de_lien_sur_perception_sans_trait(v)
	_plafond_de_croissance_respecte(v)
	_pose_seulement_apres_intervalle(v)
	_reference_absente_alarme(v)
	_propriete_structurelle_absente_alarme(v)
	_resumabilite(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: lien_personnel_croissance.gd pose un montant fixe par intervalle depuis des perceptions " +
			"filtrees par trait, generique a tout domaine invente")
		quit(0)

func _fourmi(id: String, ref: String) -> Dictionary:
	return {
		"id": id,
		"position": Vector3.ZERO,
		"proprietes": {
			"liens_personnels": {},
			"lien_personnel_croissance_ref": ref,
		},
	}

func _percue(id: String, proprietes: Dictionary) -> Dictionary:
	return {"chose": {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}}

func _catalogue_croissance() -> Dictionary:
	return {
		"fourmis_suivent_sucre": {
			"traits_recherches": ["odeur_sucre"],
			"montant_par_pose": 0.1,
			"intervalle_pose": 1.0,
			"plafond": 0.5,
		},
	}

func _catalogue_liens() -> Dictionary:
	return {
		"defaut": {"taux_decroissance": 0.001, "plancher_suppression": 0.01},
	}

func _formation_de_lien_sur_perception_du_trait(v) -> void:
	var fourmi := _fourmi("fourmi_1", "fourmis_suivent_sucre")
	var perceptions := [_percue("fourmi_2", {"odeur_sucre": true})]
	# Trois deltas qui franchissent chacun l'intervalle (1.0s) exactement :
	# trois evenements de pose, un par appel.
	for i in 3:
		LienPersonnelCroissance.avancer(fourmi, perceptions, _catalogue_croissance(), _catalogue_liens(), 1.0)
	var force := LienPersonnel.force(fourmi, "fourmi_2", _catalogue_liens())
	v.v(is_equal_approx(force, 0.3),
		"trois evenements de pose a montant_par_pose 0.1 doivent poser une force de 0.3 (0.1 par pose)")

func _pas_de_lien_sur_perception_sans_trait(v) -> void:
	var fourmi := _fourmi("fourmi_3", "fourmis_suivent_sucre")
	var perceptions := [_percue("fourmi_4", {})]
	for i in 3:
		LienPersonnelCroissance.avancer(fourmi, perceptions, _catalogue_croissance(), _catalogue_liens(), 1.0)
	var force := LienPersonnel.force(fourmi, "fourmi_4", _catalogue_liens())
	v.v(force == 0.0, "une chose percue sans le trait recherche ne doit former aucun lien")

func _plafond_de_croissance_respecte(v) -> void:
	var fourmi := _fourmi("fourmi_5", "fourmis_suivent_sucre")
	var perceptions := [_percue("fourmi_6", {"odeur_sucre": true})]
	# Dix evenements de pose (10.0s au total) : 10 * 0.1 = 1.0, non borne,
	# depasserait le plafond 0.5 -- doit s'arreter exactement a 0.5.
	for i in 10:
		LienPersonnelCroissance.avancer(fourmi, perceptions, _catalogue_croissance(), _catalogue_liens(), 1.0)
	var force := LienPersonnel.force(fourmi, "fourmi_6", _catalogue_liens())
	v.v(is_equal_approx(force, 0.5),
		"dix evenements de pose (potentiel 1.0, non borne) doivent plafonner exactement a 0.5, jamais depasser")

# LE CAS QUI AURAIT ATTRAPE LE BUG AUDITE : deltas REALISTES (0.1s, pas
# 1.0s) -- avant intervalle_pose franchi, aucune pose ; au franchissement,
# EXACTEMENT UNE pose de montant_par_pose, jamais un montant mis a l'echelle
# du delta (l'ancien bug aurait pose 0.1 * 0.1 = 0.01 par appel, efface a
# chaque tick par lien_personnel.gd:avancer avant meme d'atteindre ce test).
func _pose_seulement_apres_intervalle(v) -> void:
	var fourmi := _fourmi("fourmi_7", "fourmis_suivent_sucre")
	var perceptions := [_percue("fourmi_8", {"odeur_sucre": true})]
	var catalogue := _catalogue_croissance()
	var liens := _catalogue_liens()

	# 8 appels de 0.1s = 0.8s ecoules, en-deca de intervalle_pose (1.0s) avec
	# une marge large (evite toute sensibilite a l'arrondi flottant de
	# l'accumulation 0.1+0.1+... -- voir _pose_deuxieme_intervalle ci-dessous
	# pour la meme raison).
	for i in 8:
		LienPersonnelCroissance.avancer(fourmi, perceptions, catalogue, liens, 0.1)
	var force_avant_intervalle := LienPersonnel.force(fourmi, "fourmi_8", liens)
	v.v(force_avant_intervalle == 0.0,
		"avant que le cooldown n'atteigne intervalle_pose (0.8s < 1.0s ecoules), aucune pose ne doit avoir lieu")

	# 3 appels de plus (1.1s cumules) : le premier intervalle est franchi
	# avec une marge large, une seule pose doit avoir eu lieu -- jamais un
	# montant mis a l'echelle du delta (0.1 * 0.1 = 0.01, ce qu'aurait pose
	# l'ancien bug audite).
	for i in 3:
		LienPersonnelCroissance.avancer(fourmi, perceptions, catalogue, liens, 0.1)
	var force_apres_premier_intervalle := LienPersonnel.force(fourmi, "fourmi_8", liens)
	v.v(is_equal_approx(force_apres_premier_intervalle, 0.1),
		"une fois intervalle_pose franchi (1.1s ecoules), EXACTEMENT UNE pose de montant_par_pose (0.1) doit avoir eu lieu")

	# 10 appels de plus (2.1s cumules) : le deuxieme intervalle est franchi
	# avec la meme marge.
	for i in 10:
		LienPersonnelCroissance.avancer(fourmi, perceptions, catalogue, liens, 0.1)
	var force_apres_second_intervalle := LienPersonnel.force(fourmi, "fourmi_8", liens)
	v.v(is_equal_approx(force_apres_second_intervalle, 0.2),
		"une seconde pose doit avoir eu lieu au franchissement du deuxieme intervalle (2.1s ecoules), jamais plus d'une par intervalle")

func _reference_absente_alarme(v) -> void:
	var fourmi := _fourmi("fourmi_9", "reference_inconnue")
	var perceptions := [_percue("fourmi_10", {"odeur_sucre": true})]
	LienPersonnelCroissance.avancer(fourmi, perceptions, _catalogue_croissance(), _catalogue_liens(), 1.0)
	var force := LienPersonnel.force(fourmi, "fourmi_10", _catalogue_liens())
	v.v(force == 0.0,
		"une lien_personnel_croissance_ref absente du catalogue doit alarmer et laisser l'entite ignoree")

func _propriete_structurelle_absente_alarme(v) -> void:
	var fourmi := {"id": "fourmi_11", "position": Vector3.ZERO, "proprietes": {}}
	var perceptions := [_percue("fourmi_12", {"odeur_sucre": true})]
	LienPersonnelCroissance.avancer(fourmi, perceptions, _catalogue_croissance(), _catalogue_liens(), 1.0)
	v.v(not fourmi.proprietes.has("liens_personnels"),
		"proprietes sans 'liens_personnels' ni 'lien_personnel_croissance_ref' ne doit rien ecrire (alarme, pas defaut silencieux)")

	# L'entite VIDE ci-dessus sort sur la PREMIERE garde ; la seconde n'est
	# atteinte que par une entite a qui il manque exactement la reference.
	var sans_ref := {"id": "fourmi_13", "position": Vector3.ZERO, "proprietes": {"liens_personnels": {}}}
	LienPersonnelCroissance.avancer(sans_ref, perceptions, _catalogue_croissance(), _catalogue_liens(), 1.0)
	v.v(sans_ref.proprietes.liens_personnels.is_empty(),
		"'lien_personnel_croissance_ref' absente alors que 'liens_personnels' est la : alarme, aucun lien pose")

func _resumabilite(v) -> void:
	var fourmi := _fourmi("fourmi_13", "fourmis_suivent_sucre")
	var perceptions := [_percue("fourmi_14", {"odeur_sucre": true})]
	LienPersonnelCroissance.avancer(fourmi, perceptions, _catalogue_croissance(), _catalogue_liens(), 1.0)
	var texte := JSON.stringify(fourmi)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	var force_originale: float = fourmi.proprietes.liens_personnels["fourmi_14"]
	var force_relue: float = relu.proprietes.liens_personnels["fourmi_14"]
	v.v(is_equal_approx(force_relue, force_originale),
		"la force posee par croissance doit survivre identique a l'aller-retour JSON")
	var cooldown_original: float = fourmi.proprietes.get("lien_personnel_croissance_cooldown", -1.0)
	var cooldown_relu: float = relu.proprietes.get("lien_personnel_croissance_cooldown", -1.0)
	v.v(is_equal_approx(cooldown_relu, cooldown_original),
		"lien_personnel_croissance_cooldown doit survivre identique a l'aller-retour JSON, comme tout float de proprietes")
