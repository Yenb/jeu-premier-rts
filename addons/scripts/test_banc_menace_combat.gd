extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_menace_combat.gd
#
# Verrouille le cablage de banc_menace_combat.gd : score de menace continu
# (distance x ratio d'effectifs x visibilite), stress accumule par charge.gd
# sous cause synthetisee, bifurcation peur/colere par bifurcation.gd selon le
# biais du colon, et les effets des deux sorties (etat_effectif.gd). Les huit
# mecanismes du coeur composes restent INCHANGES -- ce fichier ne verrouille
# que le cablage.
#
# data/banc_menace_combat.json, data/etats.json, data/deformations.json,
# data/types_choses.json, data/canaux.json, data/orientations.json et
# data/profils_saillance.json sont lus SUR LE DISQUE, jamais recopies ici
# (meme discipline que test_banc_nutrition.gd) : la calibration reste reglable
# par Yael sans toucher a ce fichier.
#
# DEUX FAMILLES DE CAS, a ne pas confondre :
# - les cas de mecanique posent leurs propres positions/ratios pour isoler UNE
#   transition, et ne disent rien de la jouabilite du banc ;
# - _config_reelle_du_disque_fait_bifurquer_les_trois rejoue
#   data/banc_menace_combat.json EN ENTIER, sans un seul chiffre local. Sans
#   lui, tout ce fichier resterait VERT alors que le banc lance a l'ecran ne
#   bifurquerait jamais -- exactement le trou trouve sur banc_maladie.

const Banc = preload("res://scripts/banc_menace_combat.gd")
const Monde = preload("res://scripts/monde.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DELTA_TICK := 0.1

var _config: Dictionary
var _etats: Dictionary
var _canaux: Dictionary
var _deformations: Dictionary
var _actions: Dictionary
var _orientations: Dictionary
var _profils: Dictionary

func _init() -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_menace_combat.json"))
	_etats = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	_canaux = JSON.parse_string(FileAccess.get_file_as_string("res://data/canaux.json"))
	_deformations = JSON.parse_string(FileAccess.get_file_as_string("res://data/deformations.json"))
	_actions = JSON.parse_string(FileAccess.get_file_as_string("res://data/types_choses.json"))
	_orientations = JSON.parse_string(FileAccess.get_file_as_string("res://data/orientations.json"))
	_profils = JSON.parse_string(FileAccess.get_file_as_string("res://data/profils_saillance.json"))

	_le_score_monte_quand_les_ennemis_sont_plus_pres()
	_le_score_descend_quand_les_ennemis_s_eloignent()
	_le_score_est_nul_au_dela_de_la_portee_maximale()
	_le_ratio_d_effectifs_module_le_score()
	_l_occlusion_reduit_le_score()
	_sans_ennemi_aucun_stress_aucune_bifurcation()
	_le_lache_bifurque_vers_la_peur()
	_l_agressif_bifurque_vers_la_colere()
	_la_peur_du_lache_retombe_une_fois_qu_il_a_fui()
	_l_equilibre_bascule_avec_le_ratio()
	_en_peur_precision_et_endurance_sont_modulees()
	_en_colere_degats_module_et_prob_fuite_ecrase()
	_le_gate_prob_fuite_empeche_la_fuite_en_colere()
	_une_seule_sortie_active_a_la_fois()
	_poids_verbes_revient_au_repos_quand_la_sortie_retombe()
	_la_meme_propriete_appelle_deux_verbes_opposes()
	_la_deformation_amplifie_la_saillance_de_l_ennemi()
	_la_deformation_redescend_quand_la_sortie_retombe()
	_le_lache_fuit_et_l_agressif_charge()
	_config_reelle_du_disque_fait_bifurquer_les_trois()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_menace_combat.gd -- score de menace continu (distance x ratio " +
		"x visibilite) accumule par charge.gd sous cause synthetisee, bifurcation " +
		"peur/colere par bifurcation.gd selon le seul biais du colon, effets des " +
		"deux sorties lus par etat_effectif.gd (precision/endurance/degats, " +
		"prob_fuite ecrasee et LUE comme gate deterministe), saillance de l'ennemi " +
		"amplifiee par deformation.gd et verbe resolu par poids_verbes -- le lache " +
		"fuit, l'agressif charge, sans qu'aucun mecanisme du coeur ne soit touche " +
		"ni qu'un seul de ne soit tire")
	quit(0)

# ---- Outils de cas ----

# Un colon SEUL, nomme, pose ou l'on veut -- la config reelle du disque fournit
# tout le reste (biais, forme, canaux, canal de stress).
func _colon(nom: String, position: Vector3) -> Dictionary:
	var config := _config.duplicate(true)
	for autre in config.colons.keys():
		if autre != nom:
			config.colons.erase(autre)
	config.colons[nom].position = [position.x, position.y, position.z]
	var colons := Banc.fabriquer_colons(config)
	return colons[0]

func _ennemis_a(positions: Array) -> Array:
	var config := _config.duplicate(true)
	var decls: Array = []
	var i := 0
	for p in positions:
		decls.append({"id": "hostile_test_%d" % i, "position": [p.x, p.y, p.z]})
		i += 1
	config.ennemis = decls
	return Banc.fabriquer_ennemis(config, decls.size())

func _mur_a(position: Vector3, opacite: float) -> Array:
	var config := _config.duplicate(true)
	config.murs = [{"id": "mur_test", "position": [position.x, position.y, position.z], "opacite": opacite}]
	return Banc.fabriquer_murs(config)

# Un monde complet et son Array nu -- meme paire que le banc manipule.
func _scene(colons: Array, ennemis: Array, ouvrages: Array, murs: Array) -> Dictionary:
	var monde := Monde.new()
	var objets: Array = []
	for groupe in [colons, ennemis, ouvrages, murs]:
		for chose in groupe:
			monde.ajouter(chose, "chose", chose.position)
			objets.append(chose)
	return {"monde": monde, "objets": objets}

func _avancer(scene: Dictionary, colons: Array, delta: float) -> Dictionary:
	return Banc.avancer(
		colons, scene.objets, scene.monde, _config, _etats, _canaux,
		_deformations, _profils, _actions, _orientations, delta,
	)

func _avancer_n(scene: Dictionary, colons: Array, ticks: int) -> Dictionary:
	var dernier: Dictionary = {}
	for i in range(ticks):
		dernier = _avancer(scene, colons, DELTA_TICK)
	return dernier

# Avance jusqu'au PREMIER tick ou ce colon porte une sortie, et rend son etat A
# CET INSTANT. Indispensable, et pas un confort : un colon qui bifurque vers la
# peur FUIT, donc s'eloigne, donc voit son score baisser, sa charge repasser
# sous le seuil et sa sortie se retirer -- mesurer l'etat FINAL apres N ticks
# rendrait "" et ne dirait rien de la bifurcation. C'est la boucle du banc
# elle-meme (voir son en-tete, LIMITE DITE), pas un artefact de test.
# Rend {} si aucune bifurcation n'a eu lieu -- les cas l'asserte.
func _avancer_jusqu_a_sortie(scene: Dictionary, colons: Array, id: String, ticks_max: int) -> Dictionary:
	for i in range(ticks_max):
		var etat := _etat_de(_avancer(scene, colons, DELTA_TICK), id)
		if not etat.is_empty() and String(etat.sortie) != "":
			return etat
	return {}

# La PREMIERE sortie de CHAQUE colon sur N ticks -- plusieurs colons ne
# bifurquent pas au meme instant (leur distance aux ennemis differe), et
# certains retombent avant que les autres ne partent.
func _premieres_sorties(scene: Dictionary, colons: Array, ticks: int) -> Dictionary:
	var premieres: Dictionary = {}
	for i in range(ticks):
		for etat in _avancer(scene, colons, DELTA_TICK).colons:
			var id := String(etat.id)
			if not premieres.has(id) and String(etat.sortie) != "":
				premieres[id] = String(etat.sortie)
	return premieres

func _etat_de(resultat: Dictionary, id: String) -> Dictionary:
	for etat_colon in resultat.colons:
		if String(etat_colon.id) == id:
			return etat_colon
	return {}

# ---- LE SCORE ----

func _le_score_monte_quand_les_ennemis_sont_plus_pres() -> void:
	var colon := _colon("colon_equilibre", Vector3.ZERO)
	var loin := _ennemis_a([Vector3(0.0, -600.0, 0.0)])
	var pres := _ennemis_a([Vector3(0.0, -200.0, 0.0)])
	var score_loin := Banc.score_menace(colon, loin, 1.0, [], _config)
	var score_pres := Banc.score_menace(colon, pres, 1.0, [], _config)
	verif.v(score_pres > score_loin,
		"le score doit monter quand l'ennemi est plus pres (%.3f a 200 contre %.3f a 600)" % [score_pres, score_loin])
	# la loi exacte, pas seulement le sens : max(0, 1 - d/portee) * ratio * visibilite
	var attendu: float = 1.0 - 200.0 / float(_config.portee_max_menace)
	verif.v(is_equal_approx(score_pres, attendu),
		"le score d'un ennemi seul a ratio 1 et sans obstacle doit valoir 1 - d/portee (%.4f attendu, %.4f obtenu)" % [attendu, score_pres])

func _le_score_descend_quand_les_ennemis_s_eloignent() -> void:
	var colon := _colon("colon_equilibre", Vector3.ZERO)
	var ennemis := _ennemis_a([Vector3(0.0, -300.0, 0.0)])
	var avant := Banc.score_menace(colon, ennemis, 1.0, [], _config)
	ennemis[0].position = Vector3(0.0, -700.0, 0.0)
	var apres := Banc.score_menace(colon, ennemis, 1.0, [], _config)
	verif.v(apres < avant,
		"le score doit descendre quand le MEME ennemi s'eloigne (%.3f -> %.3f)" % [avant, apres])

func _le_score_est_nul_au_dela_de_la_portee_maximale() -> void:
	var colon := _colon("colon_equilibre", Vector3.ZERO)
	var portee: float = float(_config.portee_max_menace)
	var ennemis := _ennemis_a([Vector3(0.0, -(portee + 500.0), 0.0)])
	var score := Banc.score_menace(colon, ennemis, 1.0, [], _config)
	verif.v(is_equal_approx(score, 0.0),
		"un ennemi au-dela de portee_max_menace doit donner 0.0, JAMAIS un score negatif (%.3f obtenu)" % score)

func _le_ratio_d_effectifs_module_le_score() -> void:
	var colon := _colon("colon_equilibre", Vector3.ZERO)
	var ennemis := _ennemis_a([Vector3(0.0, -300.0, 0.0)])
	var a_un := Banc.score_menace(colon, ennemis, 1.0, [], _config)
	var a_deux := Banc.score_menace(colon, ennemis, 2.0, [], _config)
	verif.v(is_equal_approx(a_deux, a_un * 2.0),
		"doubler le ratio d'effectifs doit doubler le score (%.3f contre %.3f)" % [a_deux, a_un])
	# et le ratio lui-meme sort de comptage.gd, jamais d'un compte a la main
	var colons := [_colon("colon_lache", Vector3(-100.0, 0.0, 0.0)), _colon("colon_agressif", Vector3(100.0, 0.0, 0.0))]
	var quatre := _ennemis_a([
		Vector3(0.0, -300.0, 0.0), Vector3(50.0, -300.0, 0.0),
		Vector3(-50.0, -300.0, 0.0), Vector3(0.0, -350.0, 0.0),
	])
	var scene := _scene(colons, quatre, [], [])
	verif.v(is_equal_approx(Banc.ratio_effectifs(scene.objets, _config), 2.0),
		"quatre ennemis contre deux allies doit donner un ratio de 2.0 (comptage.gd, deux appels et une division)")

func _l_occlusion_reduit_le_score() -> void:
	var colon := _colon("colon_equilibre", Vector3.ZERO)
	var ennemis := _ennemis_a([Vector3(0.0, -400.0, 0.0)])
	var sans_mur := Banc.score_menace(colon, ennemis, 1.0, [], _config)
	var murs := _mur_a(Vector3(0.0, -200.0, 0.0), 0.6)
	var avec_mur := Banc.score_menace(colon, ennemis, 1.0, murs, _config)
	verif.v(avec_mur < sans_mur,
		"un mur pose ENTRE le colon et l'ennemi doit reduire le score (%.3f contre %.3f)" % [avec_mur, sans_mur])
	verif.v(is_equal_approx(avec_mur, sans_mur * 0.4),
		"la reduction doit valoir exactement (1 - opacite), soit 0.4 pour opacite 0.6 (%.4f obtenu)" % avec_mur)
	# un mur DERRIERE l'ennemi n'occulte rien (projection hors du segment)
	var derriere := _mur_a(Vector3(0.0, -600.0, 0.0), 1.0)
	verif.v(is_equal_approx(Banc.score_menace(colon, ennemis, 1.0, derriere, _config), sans_mur),
		"un mur au-DELA de l'ennemi ne doit rien occulter -- la projection tombe hors du segment")

# ---- LE STRESS ET LA BIFURCATION ----

func _sans_ennemi_aucun_stress_aucune_bifurcation() -> void:
	var colon := _colon("colon_equilibre", Vector3.ZERO)
	var ouvrages := Banc.fabriquer_ouvrages(_config)
	var scene := _scene([colon], [], ouvrages, [])
	var resultat := _avancer_n(scene, [colon], 100)
	var etat := _etat_de(resultat, "colon_equilibre")
	verif.v(is_equal_approx(etat.score, 0.0), "aucun ennemi -> score exactement nul (%.3f obtenu)" % etat.score)
	verif.v(is_equal_approx(etat.charge, 0.0), "aucun ennemi -> charge de stress exactement nulle apres 10 s")
	verif.v(String(etat.sortie) == "", "aucun ennemi -> aucune sortie active, jamais une bifurcation a vide")
	verif.v(colon.proprietes.etats_actifs.is_empty(),
		"aucun ennemi -> etats_actifs doit rester VIDE, ni 'peur' ni 'colere' posee")

func _le_lache_bifurque_vers_la_peur() -> void:
	var colon := _colon("colon_lache", Vector3.ZERO)
	var ennemis := _ennemis_a([Vector3(0.0, -300.0, 0.0), Vector3(60.0, -300.0, 0.0)])
	var scene := _scene([colon], ennemis, [], [])
	var etat := _avancer_jusqu_a_sortie(scene, [colon], "colon_lache", 120)
	verif.v(not etat.is_empty(), "le lache doit bifurquer dans les 12 s -- aucune sortie observee")
	verif.v(String(etat.get("sortie", "")) == "peur",
		"le lache (biais peur 0.8) doit bifurquer vers 'peur' (sortie '%s' obtenue)" % String(etat.get("sortie", "")))
	verif.v(colon.proprietes.etats_actifs.has("peur"), "'peur' doit etre posee dans etats_actifs")

func _l_agressif_bifurque_vers_la_colere() -> void:
	var colon := _colon("colon_agressif", Vector3.ZERO)
	var ennemis := _ennemis_a([Vector3(0.0, -300.0, 0.0), Vector3(60.0, -300.0, 0.0)])
	var scene := _scene([colon], ennemis, [], [])
	var etat := _avancer_jusqu_a_sortie(scene, [colon], "colon_agressif", 120)
	verif.v(not etat.is_empty(), "l'agressif doit bifurquer dans les 12 s -- aucune sortie observee")
	verif.v(String(etat.get("sortie", "")) == "colere",
		"l'agressif (biais colere 0.8) doit bifurquer vers 'colere' (sortie '%s' obtenue)" % String(etat.get("sortie", "")))
	verif.v(colon.proprietes.etats_actifs.has("colere"), "'colere' doit etre posee dans etats_actifs")

# LA BOUCLE COMPLETE, verrouillee POSITIVEMENT plutot que subie (voir
# _avancer_jusqu_a_sortie) : le lache a peur, fuit, s'eloigne assez pour que son
# score retombe, et cesse d'avoir peur. C'est la LIMITE nommee dans l'en-tete du
# banc -- aucune hysteresis n'est posee, charge.gd n'en a pas.
func _la_peur_du_lache_retombe_une_fois_qu_il_a_fui() -> void:
	var colon := _colon("colon_lache", Vector3.ZERO)
	var ennemis := _ennemis_a([Vector3(0.0, -300.0, 0.0), Vector3(60.0, -300.0, 0.0)])
	var scene := _scene([colon], ennemis, [], [])
	var etat := _avancer_jusqu_a_sortie(scene, [colon], "colon_lache", 120)
	verif.v(String(etat.get("sortie", "")) == "peur", "prerequis : le lache doit d'abord avoir peur")
	var distance_bifurcation: float = colon.position.distance_to(Vector3(30.0, -300.0, 0.0))
	# on cherche un RETRAIT observe, jamais l'etat a un instant arbitraire : une
	# fois la sortie retiree, poids_verbes repasse au repos et le colon revient
	# vers son ouvrage, donc la peur peut remonter -- c'est l'oscillation dite
	# dans l'en-tete du banc, et mesurer "l'etat apres N ticks" tomberait au
	# hasard sur l'une ou l'autre phase.
	var retire := false
	for i in range(300):
		if String(_etat_de(_avancer(scene, [colon], DELTA_TICK), "colon_lache").sortie) == "":
			retire = true
			break
	verif.v(retire, "apres avoir fui, la sortie doit se RETIRER d'elle-meme -- charge.gd redescend sous son seuil")
	verif.v(colon.position.distance_to(Vector3(30.0, -300.0, 0.0)) > distance_bifurcation,
		"et c'est bien parce qu'il s'est ELOIGNE que sa peur est retombee, jamais par le temps seul")
	verif.v(colon.proprietes.etats_actifs.is_empty(),
		"a l'instant du retrait, etats_actifs doit etre vide -- ni 'peur' ni 'colere' ne portent de 'duree', c'est le cablage qui efface")

# MEME colon, MEMES ennemis, MEME code : seul le nombre d'allies change. C'est
# la demonstration que le ratio d'effectifs entre reellement dans le choix.
func _l_equilibre_bascule_avec_le_ratio() -> void:
	var positions := [Vector3(0.0, -300.0, 0.0), Vector3(60.0, -300.0, 0.0), Vector3(-60.0, -300.0, 0.0)]

	# 3 ennemis contre 1 allie -> ratio 3.0 > 1.0 -> peur
	var seul := _colon("colon_equilibre", Vector3.ZERO)
	var scene_seul := _scene([seul], _ennemis_a(positions), [], [])
	var etat_seul := _avancer_jusqu_a_sortie(scene_seul, [seul], "colon_equilibre", 120)
	verif.v(String(etat_seul.get("sortie", "")) == "peur",
		"l'equilibre (0.5/0.5) en inferiorite numerique doit bifurquer vers 'peur' (sortie '%s')" % String(etat_seul.get("sortie", "")))

	# 3 ennemis contre 6 allies -> ratio 0.5 < 1.0 -> colere
	var entoure := _colon("colon_equilibre", Vector3.ZERO)
	var groupe: Array = [entoure]
	for i in range(5):
		var renfort := _colon("colon_equilibre", Vector3(200.0 + 40.0 * i, 0.0, 0.0))
		renfort.id = "allie_%d" % i
		groupe.append(renfort)
	var scene_groupe := _scene(groupe, _ennemis_a(positions), [], [])
	var etat_groupe := _avancer_jusqu_a_sortie(scene_groupe, groupe, "colon_equilibre", 200)
	verif.v(String(etat_groupe.get("sortie", "")) == "colere",
		"le MEME equilibre, memes ennemis, mais en superiorite numerique doit bifurquer vers 'colere' (sortie '%s')" % String(etat_groupe.get("sortie", "")))

# ---- LES EFFETS ----

func _en_peur_precision_et_endurance_sont_modulees() -> void:
	var colon := _colon("colon_lache", Vector3.ZERO)
	var base_precision: float = colon.proprietes.precision
	var base_endurance: float = colon.proprietes.endurance
	var ennemis := _ennemis_a([Vector3(0.0, -300.0, 0.0), Vector3(60.0, -300.0, 0.0)])
	var scene := _scene([colon], ennemis, [], [])
	var etat := _avancer_jusqu_a_sortie(scene, [colon], "colon_lache", 120)
	verif.v(not etat.is_empty(), "prerequis : le lache doit avoir bifurque")
	var facteur_precision: float = _facteur(_etats, "peur", "precision")
	var facteur_endurance: float = _facteur(_etats, "peur", "endurance")
	verif.v(is_equal_approx(etat.precision, base_precision * facteur_precision),
		"en peur, precision effective = base x facteur du catalogue (%.3f attendu, %.3f obtenu)" % [base_precision * facteur_precision, etat.precision])
	verif.v(is_equal_approx(etat.endurance, base_endurance * facteur_endurance),
		"en peur, endurance effective = base x facteur du catalogue (%.3f attendu, %.3f obtenu)" % [base_endurance * facteur_endurance, etat.endurance])
	verif.v(etat.precision < base_precision and etat.endurance < base_endurance,
		"les deux doivent BAISSER, jamais monter -- la peur affaiblit")

func _en_colere_degats_module_et_prob_fuite_ecrase() -> void:
	var colon := _colon("colon_agressif", Vector3.ZERO)
	var base_degats: float = colon.proprietes.degats
	var ennemis := _ennemis_a([Vector3(0.0, -300.0, 0.0), Vector3(60.0, -300.0, 0.0)])
	var scene := _scene([colon], ennemis, [], [])
	var etat := _avancer_jusqu_a_sortie(scene, [colon], "colon_agressif", 120)
	verif.v(not etat.is_empty(), "prerequis : l'agressif doit avoir bifurque")
	var facteur_degats: float = _facteur(_etats, "colere", "degats")
	verif.v(is_equal_approx(etat.degats, base_degats * facteur_degats),
		"en colere, degats effectifs = base x facteur du catalogue (%.3f attendu, %.3f obtenu)" % [base_degats * facteur_degats, etat.degats])
	verif.v(etat.degats > base_degats, "les degats doivent MONTER en colere")
	verif.v(is_equal_approx(etat.prob_fuite, 0.0),
		"en colere, prob_fuite doit etre ECRASEE a 0.0 quelle que soit la base (%.3f obtenu)" % etat.prob_fuite)
	# l'ecrasement est absolu : la base du colon vaut 1.0, elle n'y peut rien
	verif.v(is_equal_approx(float(colon.proprietes.prob_fuite), 1.0),
		"la BASE prob_fuite du colon ne doit jamais etre reecrite -- l'ecrasement est une LECTURE (etat_effectif.gd)")

func _facteur(etats: Dictionary, nom_etat: String, propriete: String) -> float:
	for effet in etats.get(nom_etat, {}).get("effets", []):
		if String(effet.get("propriete", "")) == propriete and String(effet.get("mode", "")) == "moduler":
			return float(effet.facteur)
	return 1.0

# La garde de agir_et_deplacer, exercee DIRECTEMENT : un colon a qui l'on
# impose le verbe de fuite mais dont prob_fuite est ecrasee a 0.0 ne bouge pas.
# Une garde jamais exercee est une garde qu'on croit avoir.
func _le_gate_prob_fuite_empeche_la_fuite_en_colere() -> void:
	var enrage := _colon("colon_agressif", Vector3.ZERO)
	enrage.proprietes.etats_actifs.append("colere")
	# poids_verbes de PEUR (s_eloigner gagnant) sur un colon en COLERE : le
	# verbe resolu sera 's_eloigner', seul le gate peut encore l'empecher de fuir
	enrage.proprietes.poids_verbes = _config.poids_verbes_par_sortie["peur"].duplicate(true)
	var ennemis := _ennemis_a([Vector3(0.0, -300.0, 0.0)])
	var scene := _scene([enrage], ennemis, [], [])
	var geste := Banc.agir_et_deplacer(
		enrage, scene.monde, _canaux, _profils, _deformations, _actions,
		_orientations, _etats, _config, DELTA_TICK,
	)
	verif.v(geste.fuite, "le verbe resolu doit bien etre oriente 'fuite' -- sinon ce cas ne teste rien")
	verif.v(geste.position_avant == enrage.position,
		"prob_fuite ecrasee a 0.0 -> le colon ne bouge PAS, meme avec un verbe de fuite resolu")

	# contre-epreuve : le MEME colon sans 'colere' fuit reellement
	var libre := _colon("colon_agressif", Vector3.ZERO)
	libre.proprietes.poids_verbes = _config.poids_verbes_par_sortie["peur"].duplicate(true)
	var scene_libre := _scene([libre], _ennemis_a([Vector3(0.0, -300.0, 0.0)]), [], [])
	var geste_libre := Banc.agir_et_deplacer(
		libre, scene_libre.monde, _canaux, _profils, _deformations, _actions,
		_orientations, _etats, _config, DELTA_TICK,
	)
	verif.v(geste_libre.position_avant != libre.position,
		"sans 'colere', prob_fuite vaut 1.0 et le MEME colon fuit -- c'est bien le gate qui decide")

func _une_seule_sortie_active_a_la_fois() -> void:
	var colon := _colon("colon_lache", Vector3.ZERO)
	# on pose LES DEUX a la main, le cablage doit en effacer une au pas suivant
	colon.proprietes.etats_actifs.append("peur")
	colon.proprietes.etats_actifs.append("colere")
	var ennemis := _ennemis_a([Vector3(0.0, -300.0, 0.0), Vector3(60.0, -300.0, 0.0)])
	var scene := _scene([colon], ennemis, [], [])
	# des le PREMIER tick, avant meme tout franchissement de seuil : la sortie
	# perdante est effacee inconditionnellement, jamais seulement au moment de
	# bifurquer
	_avancer(scene, [colon], DELTA_TICK)
	verif.v(colon.proprietes.etats_actifs.size() <= 1,
		"le cablage doit garantir UNE SEULE sortie active au plus (actifs=%s)" % [colon.proprietes.etats_actifs])
	_avancer_jusqu_a_sortie(scene, [colon], "colon_lache", 120)
	verif.v(colon.proprietes.etats_actifs.has("peur") and not colon.proprietes.etats_actifs.has("colere"),
		"apres bifurcation : 'peur' retenue, 'colere' effacee (actifs=%s)" % [colon.proprietes.etats_actifs])

func _poids_verbes_revient_au_repos_quand_la_sortie_retombe() -> void:
	var colon := _colon("colon_lache", Vector3.ZERO)
	var ennemis := _ennemis_a([Vector3(0.0, -300.0, 0.0), Vector3(60.0, -300.0, 0.0)])
	var scene := _scene([colon], ennemis, [], [])
	_avancer_jusqu_a_sortie(scene, [colon], "colon_lache", 120)
	verif.v(colon.proprietes.poids_verbes == _config.poids_verbes_par_sortie["peur"],
		"en peur, poids_verbes doit etre EXACTEMENT la table de la sortie, ecrite en entier")
	# les ennemis disparaissent : le stress redescend, la sortie se retire
	var vide := _scene([colon], [], [], [])
	_avancer_n(vide, [colon], 120)
	verif.v(colon.proprietes.poids_verbes == _config.poids_verbes_repos,
		"sortie retombee -> poids_verbes doit revenir EXACTEMENT a la table de repos, jamais un melange")
	verif.v(colon.proprietes.etats_actifs.is_empty(),
		"sortie retombee -> etats_actifs doit etre vide (le cablage efface, aucune 'duree' ne le ferait)")

# LA PREMIERE PROPRIETE A DEUX VERBES DU DEPOT : le MEME ennemi, percu par le
# MEME colon, resout 'approcher' ou 's_eloigner' selon la seule table
# poids_verbes -- jamais selon sa saillance, jamais selon son etat.
func _la_meme_propriete_appelle_deux_verbes_opposes() -> void:
	var verbes: Array = _actions.get(String(_config.propriete_menace), {}).get("verbes", [])
	verif.v(verbes.size() == 2 and verbes.has("approcher") and verbes.has("s_eloigner"),
		"data/types_choses.json:%s doit proposer DEUX verbes opposes (obtenu %s)" % [String(_config.propriete_menace), verbes])

	var ennemis := _ennemis_a([Vector3(0.0, -300.0, 0.0)])
	var peureux := _colon("colon_lache", Vector3.ZERO)
	peureux.proprietes.poids_verbes = _config.poids_verbes_par_sortie["peur"].duplicate(true)
	var scene_peur := _scene([peureux], ennemis, [], [])
	var d_peur := Banc.decider(peureux, scene_peur.monde, _canaux, _profils, _deformations, _actions)
	verif.v(String(d_peur.decision.action) == "s_eloigner",
		"table de peur -> le verbe resolu sur l'ennemi doit etre 's_eloigner' (obtenu '%s')" % String(d_peur.decision.action))

	var enrage := _colon("colon_agressif", Vector3.ZERO)
	enrage.proprietes.poids_verbes = _config.poids_verbes_par_sortie["colere"].duplicate(true)
	var scene_colere := _scene([enrage], _ennemis_a([Vector3(0.0, -300.0, 0.0)]), [], [])
	var d_colere := Banc.decider(enrage, scene_colere.monde, _canaux, _profils, _deformations, _actions)
	verif.v(String(d_colere.decision.action) == "approcher",
		"table de colere -> le verbe resolu sur le MEME ennemi doit etre 'approcher' (obtenu '%s')" % String(d_colere.decision.action))

# ---- LA DEFORMATION ----

func _la_deformation_amplifie_la_saillance_de_l_ennemi() -> void:
	var colon := _colon("colon_lache", Vector3.ZERO)
	var ennemis := _ennemis_a([Vector3(0.0, -300.0, 0.0)])
	var scene := _scene([colon], ennemis, [], [])
	var nue := _saillance_ennemi(colon, scene)
	_avancer_n(scene, [colon], 200)
	var amplifiee := _saillance_ennemi(colon, scene)
	verif.v(amplifiee > nue,
		"la deformation 'peur' (sens 'monte') doit AMPLIFIER la saillance de l'ennemi (%.3f -> %.3f)" % [nue, amplifiee])
	# et l'ouvrage voisin, lui, n'est jamais amplifie : la cible de la
	# deformation est la propriete de menace, pas une chose nommee
	var ouvrages := Banc.fabriquer_ouvrages(_config)
	var scene_ouvrage := _scene([], [], ouvrages, [])
	var avec_ouvrage := _scene([colon], ennemis, ouvrages, [])
	var saillances := Proximite.evaluer(
		[{"chose": ouvrages[0], "type": "ouvrage", "position": ouvrages[0].position,
		  "distance": colon.position.distance_to(ouvrages[0].position), "canaux": ["vue"]}],
		colon, _profils, _deformations,
	)
	var nue_ouvrage: float = 3.0 * (1.0 - colon.position.distance_to(ouvrages[0].position) / 900.0)
	verif.v(is_equal_approx(saillances[0].saillance, nue_ouvrage),
		"l'ouvrage ne porte PAS la propriete de menace : sa saillance ne doit jamais etre amplifiee (%.3f attendu, %.3f obtenu)" % [nue_ouvrage, saillances[0].saillance])

func _saillance_ennemi(colon: Dictionary, scene: Dictionary) -> float:
	var d := Banc.decider(colon, scene.monde, _canaux, _profils, _deformations, _actions)
	for entree in d.resultats:
		if entree.chose.proprietes.get(String(_config.propriete_menace), false):
			return float(entree.saillance)
	return 0.0

func _la_deformation_redescend_quand_la_sortie_retombe() -> void:
	var colon := _colon("colon_lache", Vector3.ZERO)
	var ennemis := _ennemis_a([Vector3(0.0, -300.0, 0.0)])
	var scene := _scene([colon], ennemis, [], [])
	_avancer_n(scene, [colon], 200)
	var haut := _biais_peur(colon)
	verif.v(haut > 0.0, "le biais de peur doit etre strictement positif apres 20 s d'exposition (%.3f)" % haut)
	var vide := _scene([colon], [], [], [])
	_avancer_n(vide, [colon], 200)
	var bas := _biais_peur(colon)
	verif.v(bas < haut,
		"le biais doit REDESCENDRE quand la menace disparait -- Deformation.avancer est appele a chaque tick, sortie active ou non (%.3f -> %.3f)" % [haut, bas])

func _biais_peur(colon: Dictionary) -> float:
	var canal: Dictionary = colon.proprietes.deformation_etat.get("peur", {}).get(String(_config.propriete_menace), {})
	var regle: Dictionary = _deformations.get("peur", {})
	return float(regle.get("w_rapide", 0.0)) * float(canal.get("rapide", 0.0)) \
		+ float(regle.get("w_lent", 0.0)) * float(canal.get("lent", 0.0))

# ---- LE GESTE COMPLET ----

# Le coeur du banc : memes ennemis, meme ouvrage, meme code -- le lache
# s'ELOIGNE des ennemis, l'agressif s'en RAPPROCHE. Mesure sur la distance,
# jamais sur une intention declaree.
func _le_lache_fuit_et_l_agressif_charge() -> void:
	var positions := [Vector3(0.0, -300.0, 0.0), Vector3(60.0, -300.0, 0.0), Vector3(-60.0, -300.0, 0.0)]
	var barycentre: Vector3 = (positions[0] + positions[1] + positions[2]) / 3.0

	var lache := _colon("colon_lache", Vector3.ZERO)
	var scene_lache := _scene([lache], _ennemis_a(positions), Banc.fabriquer_ouvrages(_config), [])
	var avant_lache: float = lache.position.distance_to(barycentre)
	_avancer_n(scene_lache, [lache], 200)
	var apres_lache: float = lache.position.distance_to(barycentre)
	verif.v(apres_lache > avant_lache,
		"le lache doit s'ELOIGNER du groupe d'ennemis (%.1f -> %.1f)" % [avant_lache, apres_lache])

	var agressif := _colon("colon_agressif", Vector3.ZERO)
	var scene_agressif := _scene([agressif], _ennemis_a(positions), Banc.fabriquer_ouvrages(_config), [])
	var avant_agressif: float = agressif.position.distance_to(barycentre)
	_avancer_n(scene_agressif, [agressif], 200)
	var apres_agressif: float = agressif.position.distance_to(barycentre)
	verif.v(apres_agressif < avant_agressif,
		"l'agressif doit se RAPPROCHER du groupe d'ennemis (%.1f -> %.1f)" % [avant_agressif, apres_agressif])

# ---- LA CONFIG REELLE DU DISQUE ----

# Rejoue data/banc_menace_combat.json EN ENTIER : trois colons, palier de
# depart, ouvrages, mur. Sans ce cas, tout ce fichier resterait VERT alors que
# le banc lance a l'ecran ne bifurquerait jamais.
func _config_reelle_du_disque_fait_bifurquer_les_trois() -> void:
	var colons := Banc.fabriquer_colons(_config)
	var ennemis := Banc.fabriquer_ennemis(_config, Banc.nombre_du_palier(_config, 0))
	var scene := _scene(colons, ennemis, Banc.fabriquer_ouvrages(_config), Banc.fabriquer_murs(_config))
	verif.v(colons.size() == 3 and ennemis.size() == 4,
		"la config du disque doit poser 3 colons et 4 ennemis au palier de depart (obtenu %d/%d)" % [colons.size(), ennemis.size()])

	var ratio_depart := Banc.ratio_effectifs(scene.objets, _config)
	verif.v(is_equal_approx(ratio_depart, 4.0 / 3.0),
		"ratio de depart = 4 ennemis / 3 allies (%.3f obtenu)" % ratio_depart)

	# PREMIERE sortie de chacun : les trois ne bifurquent pas au meme instant
	# (le central est plus pres, l'agressif est derriere le mur) et le lache
	# retombe des qu'il a fui -- voir _avancer_jusqu_a_sortie.
	var premieres := _premieres_sorties(scene, colons, 200)
	verif.v(String(premieres.get("colon_lache", "")) == "peur",
		"config reelle : le lache doit bifurquer vers 'peur' (obtenu '%s')" % String(premieres.get("colon_lache", "")))
	verif.v(String(premieres.get("colon_agressif", "")) == "colere",
		"config reelle : l'agressif doit bifurquer vers 'colere' (obtenu '%s')" % String(premieres.get("colon_agressif", "")))
	verif.v(String(premieres.get("colon_equilibre", "")) == "peur",
		"config reelle : l'equilibre doit bifurquer vers 'peur' au ratio de depart 1.33 > 1.0 (obtenu '%s')" % String(premieres.get("colon_equilibre", "")))

	# le palier suivant du disque renverse le ratio, et l'equilibre SEUL change d'avis
	var colons2 := Banc.fabriquer_colons(_config)
	var ennemis2 := Banc.fabriquer_ennemis(_config, Banc.nombre_du_palier(_config, 1))
	var scene2 := _scene(colons2, ennemis2, Banc.fabriquer_ouvrages(_config), Banc.fabriquer_murs(_config))
	verif.v(Banc.ratio_effectifs(scene2.objets, _config) < 1.0,
		"le deuxieme palier du disque doit passer le ratio SOUS 1.0 (%.3f obtenu)" % Banc.ratio_effectifs(scene2.objets, _config))
	var premieres2 := _premieres_sorties(scene2, colons2, 300)
	verif.v(String(premieres2.get("colon_equilibre", "")) == "colere",
		"au deuxieme palier, l'equilibre doit passer a 'colere' (obtenu '%s')" % String(premieres2.get("colon_equilibre", "")))
	verif.v(String(premieres2.get("colon_lache", "")) == "peur",
		"au deuxieme palier, le lache reste en peur -- son temperament tient a tous les paliers (obtenu '%s')" % String(premieres2.get("colon_lache", "")))
	verif.v(String(premieres2.get("colon_agressif", "")) == "colere",
		"au deuxieme palier, l'agressif reste en colere -- son temperament tient a tous les paliers (obtenu '%s')" % String(premieres2.get("colon_agressif", "")))

	# le mur du disque fait bien de l'ombre a l'agressif
	var agressif: Dictionary = Banc.fabriquer_colons(_config)[2]
	var sans_mur := Banc.score_menace(agressif, ennemis, ratio_depart, [], _config)
	var avec_mur := Banc.score_menace(agressif, ennemis, ratio_depart, Banc.fabriquer_murs(_config), _config)
	verif.v(avec_mur < sans_mur,
		"le mur du disque doit reduire le score de l'agressif (%.3f contre %.3f sans lui)" % [avec_mur, sans_mur])
