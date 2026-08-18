extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_lien_personnel.gd
#
# Verrouille le cablage de banc_lien_personnel.gd (PHASE 5 etape 2, chantier
# "L'entite comme agent complet") : deux colons REELS (Objet.fabriquer contre
# data/types.json lu sur disque), identiques a leur naissance -- seule leur
# POSITION differe -- divergent OBSERVABLEMENT sur
# proprietes.liens_personnels["batisse_0"] selon que leur decision resout ou
# non le verbe "eteindre" sur une chose portant "notre_ouvrage", via le
# nouvel effet de bord de agir.gd:choisir (catalogue_actes_liants,
# data/actes_liants.json lu sur disque, poids reels de
# data/liens_personnels.json pour la decroissance).
#
# decider/decider_et_memoriser (banc_lien_personnel.gd) sont exerces sur le
# CHEMIN REEL : data/types.json (colon.liens_personnels: {} herite de
# entite), data/canaux.json, data/profils_saillance.json,
# data/deformations.json, data/actes_liants.json, data/liens_personnels.json,
# tous lus sur disque. "batisse" (brule/notre_ouvrage/chantier) et le
# catalogue_actions local ("brule" -> "eteindre") sont declares ici comme
# dans data/banc_lien_personnel.json -- ce fichier n'invoque ni jugement.gd,
# ni ciblage.gd, ni fuite.gd, ni extinction.gd (le chantier de la batisse
# n'a pas besoin de progresser pour verifier liens_personnels -- seul le
# verbe RESOLU et la propriete de la chose visee comptent, voir
# agir.gd:_appliquer_actes_liants), hors perimetre de cette etape.
#
# PHASE 5 etape 3/4 (lecture par une couche de saillance) :
# _nouveau_feu_pres_batisse_plus_saillant_pour_pompier_que_spectateur
# verrouille _appliquer_bonus_lien_personnel (banc_lien_personnel.gd:decider)
# sur le chemin reel -- apres avoir accumule une force de lien reelle sur la
# batisse (meme boucle que le test precedent), un feu supplementaire
# (type partage "feu", data/types.json) place a 20 unites de la batisse est
# UNIQUEMENT percu par le pompier (10 unites de la batisse, dans
# canaux.vue.portee) -- le spectateur (5000 unites) ne le percoit jamais,
# meme separation que pour la batisse elle-meme. Formule exacte verifiee :
# saillance_nue (Proximite.evaluer, poids reel de data/profils_saillance.json)
# + bonus (LienPersonnelSaillance.bonus, force reelle accumulee, distance
# reelle batisse<->feu, portee_menace reelle de data/liens_personnels.json).

const BancLienPersonnel = preload("res://scripts/banc_lien_personnel.gd")
const LienPersonnel = preload("res://scripts/lien_personnel.gd")
const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const ID_BATISSE := "batisse_0"
const DELTA_TICK := 0.1
const TICKS := 20

func _init() -> void:
	_pompier_reel_developpe_un_lien_spectateur_reste_vide()
	_nouveau_feu_pres_batisse_plus_saillant_pour_pompier_que_spectateur()
	_pompiers_reels_forment_leur_attache_par_trait_a_rythme_differencie()
	_couleur_de_lit_le_type_pose_jamais_le_defaut()
	_etiquette_decision_cas()
	_logger_decision_change_seulement_sur_changement_reel()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: deux colons reels identiques a la naissance divergent sur " +
		"liens_personnels['batisse_0'] selon que leur decision resout ou non " +
		"le verbe 'eteindre' sur une chose notre_ouvrage, via le nouvel effet " +
		"de bord de agir.gd:choisir (catalogue_actes_liants) -- valeur exacte " +
		"verifiee avec les poids reels de data/actes_liants.json/" +
		"data/liens_personnels.json")
	quit(0)

func _types_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))

func _catalogue_canaux_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/canaux.json"))

func _profils_saillance_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/profils_saillance.json"))

func _catalogue_deformations_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/deformations.json"))

func _actes_liants_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/actes_liants.json"))

func _catalogue_liens_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/liens_personnels.json"))

# "brule" -> ["eteindre"] : catalogue_actions LOCAL a ce banc (comme
# data/banc_lien_personnel.json:catalogue_local), jamais le data/
# types_choses.json partage (qui donne "brule" -> "approcher").
func _catalogue_actions_local() -> Dictionary:
	return {"brule": {"verbes": ["eteindre"]}}

# Colon REEL, fabrique directement contre data/types.json -- herite
# liens_personnels: {} sans aucune surcharge de banc, meme geste que
# BancCommun.fabriquer_colon (forme/attaches/poids_verbes poses par-dessus).
func _colon_reel(id: String, position: Vector3, poids_verbes: Dictionary) -> Dictionary:
	var colon := Objet.fabriquer(id, "colon", position, _types_reels())
	colon.proprietes["attaches"] = []
	colon.proprietes["forme"] = {}
	colon.proprietes["poids_verbes"] = poids_verbes
	colon["action_en_cours"] = {}
	colon["action_precedente"] = "__jamais__"
	return colon

# "batisse" local minimal (brule/notre_ouvrage/chantier), meme convention que
# data/banc_lien_personnel.json -- travail_restant tres eleve : le chantier
# ne bouge jamais dans ce test (Extinction.avancer n'est meme pas appele),
# seule la propriete "notre_ouvrage" compte pour agir.gd:_appliquer_actes_liants.
func _monde_avec_batisse(position_batisse: Vector3) -> Monde:
	var monde := Monde.new()
	var table := {
		"batisse": {
			"brule": true, "notre_ouvrage": true, "profil_saillance": "feu",
			"transformation": "defaut", "travail_restant": 500.0, "travail_initial": 500.0,
		},
	}
	var batisse := Objet.fabriquer(ID_BATISSE, "batisse", position_batisse, table)
	monde.ajouter(batisse, "batisse", position_batisse)
	return monde

func _pompier_reel_developpe_un_lien_spectateur_reste_vide() -> void:
	var canaux := _catalogue_canaux_reel()
	var profils := _profils_saillance_reel()
	var deformations := _catalogue_deformations_reel()
	var actes_liants := _actes_liants_reels()
	var liens := _catalogue_liens_reel()
	var catalogue_actions := _catalogue_actions_local()

	var position_batisse := Vector3.ZERO
	# pompier : 10 unites de la batisse, tres largement a portee de vue
	# (1600.0, data/types.json:colon.canaux_config.vue.portee) -- perçoit la batisse
	# et resout "eteindre" a chaque tick. spectateur : 5000 unites, tres
	# largement HORS de cette meme portee -- aucune perception possible,
	# decision toujours null.
	var pompier := _colon_reel("pompier", Vector3(10.0, 0.0, 0.0), {"eteindre": 1.0})
	var spectateur := _colon_reel("spectateur", Vector3(5000.0, 0.0, 0.0), {"eteindre": 1.0})

	verif.v(pompier.proprietes.liens_personnels.is_empty(),
		"un colon reel doit heriter liens_personnels: {} avant toute defense")
	verif.v(spectateur.proprietes.liens_personnels.is_empty(),
		"un colon reel doit heriter liens_personnels: {} avant toute defense")

	var monde_pompier := _monde_avec_batisse(position_batisse)
	monde_pompier.ajouter(pompier, "colon", pompier.position)
	var monde_spectateur := _monde_avec_batisse(position_batisse)
	monde_spectateur.ajouter(spectateur, "colon", spectateur.position)

	for i in TICKS:
		BancLienPersonnel.decider_et_memoriser(
			pompier, monde_pompier, canaux, {}, profils, deformations, catalogue_actions, actes_liants, liens,
		)
		LienPersonnel.avancer(pompier, DELTA_TICK, liens)
		BancLienPersonnel.decider_et_memoriser(
			spectateur, monde_spectateur, canaux, {}, profils, deformations, catalogue_actions, actes_liants, liens,
		)
		LienPersonnel.avancer(spectateur, DELTA_TICK, liens)

	verif.v(not pompier.proprietes.liens_personnels.is_empty(),
		"apres %d cycles a portee de vue d'une batisse notre_ouvrage en feu, le pompier doit porter un lien personnel" % TICKS)
	var force_pompier: float = pompier.proprietes.liens_personnels.get(ID_BATISSE, 0.0)
	verif.v(force_pompier > 0.0,
		"la force du lien du pompier envers la batisse doit etre strictement positive")
	verif.v(spectateur.proprietes.liens_personnels.is_empty(),
		"un colon jamais expose (hors de portee de vue) ne doit jamais former de lien personnel")

	# Valeur exacte : magnitude posee a CHAQUE tick (le pompier resout
	# "eteindre" sur la batisse tout du long, verbe et propriete inchanges)
	# moins la decroissance lineaire (taux_decroissance * delta) appliquee
	# elle aussi a chaque tick -- poids REELS lus sur disque, jamais des
	# constantes recopiees a la main.
	var magnitude: float = actes_liants.defense_ouvrage.magnitude
	var taux_decroissance: float = liens.defaut.taux_decroissance
	var attendu: float = TICKS * magnitude - TICKS * taux_decroissance * DELTA_TICK
	verif.v(is_equal_approx(force_pompier, attendu),
		"la force du lien doit valoir exactement magnitude * TICKS - taux_decroissance * DELTA_TICK * TICKS (%.6f attendu, %.6f obtenu)" % [attendu, force_pompier])

# PHASE 5 etape 3/4 : voir en-tete du fichier. Deux colons FRAIS (jamais
# ceux du test precedent, pour rester independant) -- meme boucle
# d'accumulation que ci-dessus (batisse SEULE dans le monde, la formule de
# force reste identique), PUIS un feu supplementaire est ajoute au monde
# pour une UNIQUE mesure (pas d'accumulation supplementaire) : compare la
# saillance de ce nouveau feu entre le pompier (lie a la batisse) et le
# spectateur (jamais expose).
func _nouveau_feu_pres_batisse_plus_saillant_pour_pompier_que_spectateur() -> void:
	var canaux := _catalogue_canaux_reel()
	var profils := _profils_saillance_reel()
	var deformations := _catalogue_deformations_reel()
	var actes_liants := _actes_liants_reels()
	var liens := _catalogue_liens_reel()
	var catalogue_actions := _catalogue_actions_local()

	var position_batisse := Vector3.ZERO
	var pompier := _colon_reel("pompier_saillance", Vector3(10.0, 0.0, 0.0), {"eteindre": 1.0})
	var spectateur := _colon_reel("spectateur_saillance", Vector3(5000.0, 0.0, 0.0), {"eteindre": 1.0})

	var monde_pompier := _monde_avec_batisse(position_batisse)
	monde_pompier.ajouter(pompier, "colon", pompier.position)
	var monde_spectateur := _monde_avec_batisse(position_batisse)
	monde_spectateur.ajouter(spectateur, "colon", spectateur.position)

	for i in TICKS:
		BancLienPersonnel.decider_et_memoriser(
			pompier, monde_pompier, canaux, {}, profils, deformations, catalogue_actions, actes_liants, liens,
		)
		LienPersonnel.avancer(pompier, DELTA_TICK, liens)
		BancLienPersonnel.decider_et_memoriser(
			spectateur, monde_spectateur, canaux, {}, profils, deformations, catalogue_actions, actes_liants, liens,
		)
		LienPersonnel.avancer(spectateur, DELTA_TICK, liens)

	var force_pompier: float = pompier.proprietes.liens_personnels.get(ID_BATISSE, 0.0)
	verif.v(force_pompier > 0.0,
		"le pompier doit avoir accumule une force de lien positive avant la mesure de divergence")

	var id_feu_proche := "feu_proche_saillance"
	var position_feu_proche := Vector3(0.0, 20.0, 0.0)
	var feu_proche_pompier := Objet.fabriquer(id_feu_proche, "feu", position_feu_proche, _types_reels())
	monde_pompier.ajouter(feu_proche_pompier, "feu", position_feu_proche)
	var feu_proche_spectateur := Objet.fabriquer(id_feu_proche, "feu", position_feu_proche, _types_reels())
	monde_spectateur.ajouter(feu_proche_spectateur, "feu", position_feu_proche)

	var r_pompier := BancLienPersonnel.decider(
		pompier, monde_pompier, canaux, {}, profils, deformations, catalogue_actions, actes_liants, liens,
	)
	var r_spectateur := BancLienPersonnel.decider(
		spectateur, monde_spectateur, canaux, {}, profils, deformations, catalogue_actions, actes_liants, liens,
	)

	var saillance_pompier := _saillance_pour_id(r_pompier.resultats, id_feu_proche)
	var saillance_spectateur := _saillance_pour_id(r_spectateur.resultats, id_feu_proche)

	verif.v(saillance_pompier > 0.0,
		"le pompier, lie a la batisse, doit percevoir le nouveau feu avec une saillance strictement positive")
	verif.v(saillance_spectateur == 0.0,
		"le spectateur, hors de portee de vue, ne doit meme pas percevoir le nouveau feu (saillance nulle)")
	verif.v(saillance_pompier > saillance_spectateur,
		"le nouveau feu doit etre strictement plus saillant pour le pompier (lien personnel) que pour le spectateur")

	# Formule exacte : saillance_nue (Proximite.evaluer, poids reels de
	# data/profils_saillance.json, deformation nulle chez un colon frais) +
	# bonus de lien personnel (force reellement accumulee, distance reelle
	# batisse<->feu, portee_menace reelle de data/liens_personnels.json).
	var profil_feu: Dictionary = profils.feu
	var distance_pompier_feu: float = pompier.position.distance_to(position_feu_proche)
	var facteur: float = clamp(1.0 - distance_pompier_feu / profil_feu.portee_saillance, 0.0, 1.0)
	var saillance_nue: float = profil_feu.saillance_intrinseque * facteur
	var distance_batisse_feu: float = position_batisse.distance_to(position_feu_proche)
	var portee_menace: float = liens.defaut.portee_menace
	var bonus_attendu: float = force_pompier * (1.0 - distance_batisse_feu / portee_menace)
	var attendu_saillance: float = saillance_nue + bonus_attendu
	verif.v(is_equal_approx(saillance_pompier, attendu_saillance),
		"la saillance du nouveau feu pour le pompier doit valoir exactement saillance_nue + bonus de lien personnel (%.6f attendu, %.6f obtenu)" % [attendu_saillance, saillance_pompier])

func _attaches_par_trait_reel() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/attaches_par_trait.json"))

# PHASE 5 etape 4/4 piece 2/3 (L'ELARGISSEMENT, scripts/attache_par_trait.gd) :
# verrouille le CABLAGE REEL de AttacheParTrait.avancer via le DEUXIEME
# effet de bord de agir.gd:choisir (catalogue_attaches_par_trait, chemin
# decider_et_memoriser reel). Trois colons, memes sensibilite_generalisation
# que data/banc_lien_personnel.json:colons (pompier_rapide/pompier_moyen/
# pompier_lent), defendent des "batisses" notre_ouvrage DISTINCTES, une a la
# fois. Verifie qu'aucune attache ne se forme avant la Nieme defense
# distincte, et qu'elle se forme exactement a la Nieme -- poids REELS de
# data/attaches_par_trait.json:generalisation_ouvrage pour pompier_moyen
# (aucune surcharge).
func _pompiers_reels_forment_leur_attache_par_trait_a_rythme_differencie() -> void:
	var canaux := _catalogue_canaux_reel()
	var profils := _profils_saillance_reel()
	var deformations := _catalogue_deformations_reel()
	var actes_liants := _actes_liants_reels()
	var liens := _catalogue_liens_reel()
	var catalogue_actions := _catalogue_actions_local()
	var attaches_par_trait := _attaches_par_trait_reel()

	_verifie_rythme_generalisation(
		"pompier_rapide_reel", {"notre_ouvrage": {"seuil_nombre": 2}}, 2,
		canaux, profils, deformations, actes_liants, liens, catalogue_actions, attaches_par_trait,
	)
	_verifie_rythme_generalisation(
		"pompier_moyen_reel", {}, 3,
		canaux, profils, deformations, actes_liants, liens, catalogue_actions, attaches_par_trait,
	)
	_verifie_rythme_generalisation(
		"pompier_lent_reel", {"notre_ouvrage": {"seuil_nombre": 5, "seuil_force": 0.5}}, 5,
		canaux, profils, deformations, actes_liants, liens, catalogue_actions, attaches_par_trait,
	)

# Defend rythme_attendu "batisses" distinctes, UNE A LA FOIS (TICKS ticks
# chacune, meme rythme d'accumulation que le premier test de ce fichier).
# Chaque nouvelle batisse nait a la MEME position proche (50, 0, 0) : la
# precedente est RELOCALISEE hors de canaux.vue.portee juste apres sa phase
# (monde.par_id(...).chose.position reste vivant pour AttacheParTrait, voir
# monde.gd -- seule la PERCEPTION en est affectee) -- sans ca, le BONUS DE
# LIEN PERSONNEL (LienPersonnelSaillance.bonus, deja accumule sur la
# batisse precedente) la rend de plus en plus saillante a chaque tick et
# verrouille le colon dessus pour toujours : aucune nouvelle batisse, meme
# strictement plus proche, ne peut jamais la detroner (verifie
# empiriquement, script de diagnostic jetable, jamais commite). Relocaliser
# la precedente hors de vue avant d'introduire la suivante evite ce
# verrouillage et garantit un handoff deterministe.
# Verifie qu'aucune attache ne se forme avant la derniere, et qu'elle se
# forme exactement a celle-la.
func _verifie_rythme_generalisation(
	id: String,
	surcharge: Dictionary,
	rythme_attendu: int,
	canaux: Dictionary, profils: Dictionary, deformations: Dictionary,
	actes_liants: Dictionary, liens: Dictionary, catalogue_actions: Dictionary,
	attaches_par_trait: Dictionary,
) -> void:
	var colon := _colon_reel(id, Vector3.ZERO, {"eteindre": 1.0})
	if not surcharge.is_empty():
		colon.proprietes["sensibilite_generalisation"] = surcharge
	var monde := Monde.new()
	monde.ajouter(colon, "colon", colon.position)

	var pos := Vector3(50.0, 0.0, 0.0)
	var loin := Vector3(100000.0, 0.0, 0.0)
	for i in rythme_attendu:
		var id_batisse := "%s_batisse_%d" % [id, i]
		var table := {
			"batisse": {
				"brule": true, "notre_ouvrage": true, "profil_saillance": "feu",
				"transformation": "defaut", "travail_restant": 500.0, "travail_initial": 500.0,
			},
		}
		var batisse := Objet.fabriquer(id_batisse, "batisse", pos, table)
		monde.ajouter(batisse, "batisse", pos)

		for t in TICKS:
			BancLienPersonnel.decider_et_memoriser(
				colon, monde, canaux, {}, profils, deformations, catalogue_actions, actes_liants, liens, attaches_par_trait,
			)
			LienPersonnel.avancer(colon, DELTA_TICK, liens)

		monde.par_id(id_batisse).chose.position = loin

		var forme_maintenant: bool = not colon.proprietes.attaches.is_empty()
		if i < rythme_attendu - 1:
			verif.v(not forme_maintenant,
				"%s ne doit pas former l'attache avant sa %de defense distincte (actuellement %d)" % [id, rythme_attendu, i + 1])
		else:
			verif.v(forme_maintenant,
				"%s doit former l'attache par trait exactement a sa %de defense distincte" % [id, rythme_attendu])
			if forme_maintenant:
				verif.v(colon.proprietes.attaches[0].propriete == "notre_ouvrage",
					"l'attache formee par %s doit porter la propriete 'notre_ouvrage'" % id)

func _saillance_pour_id(resultats: Array, id: String) -> float:
	for entree in resultats:
		if entree.has("chose") and entree.chose.id == id:
			return entree.saillance
	return 0.0

# Audit couverture 2026-08-06 : _couleur_de/_etiquette_decision/
# _logger_decision sont des fonctions INSTANCE, aucune appelee par un test
# avant cette session. Meme patron que les autres bancs :
# BancLienPersonnel.new() nu, jamais ajoute a l'arbre.

func _couleur_de_lit_le_type_pose_jamais_le_defaut() -> void:
	var b := BancLienPersonnel.new()
	b._couleurs_types = {"batisse": [0.9, 0.2, 0.1], "bois": [0.1, 0.6, 0.9]}
	verif.v(b._couleur_de("batisse") == Color(0.9, 0.2, 0.1), "doit rendre la couleur posee pour 'batisse', pas le defaut blanc")
	verif.v(b._couleur_de("bois") == Color(0.1, 0.6, 0.9), "doit distinguer deux types poses")
	verif.v(b._couleur_de("inconnu") == Color(1.0, 1.0, 1.0), "un type absent doit rendre le blanc par defaut, jamais alarmer")

# Cette version (comme banc_p1.gd, DIFFERENT de banc_charge.gd/banc_feu.gd,
# verrouilles cette meme session) porte la branche "chose != null mais pas
# Dictionary -> rendre la chose telle quelle". Verrouille CE fichier
# precisement -- les trois versions de _etiquette_decision ont divergees,
# aucune supposition de coherence entre bancs.
func _etiquette_decision_cas() -> void:
	var b := BancLienPersonnel.new()
	verif.v(b._etiquette_decision({"type": "brule", "chose": {"id": "feu_1"}}) == "feu_1",
		"chose Dictionary avec id : doit rendre l'id de la chose")
	verif.v(b._etiquette_decision({"type": "brule", "chose": {}}) == "brule",
		"chose Dictionary sans id : doit retomber sur decision.type")
	verif.v(b._etiquette_decision({"type": "brule", "chose": "feu_2"}) == "feu_2",
		"chose non-Dictionary : doit rendre la chose telle quelle (comme banc_p1.gd)")
	verif.v(b._etiquette_decision({"type": "brule", "chose": null}) == "brule",
		"chose absente (null) : doit retomber sur decision.type")

# Le point de _logger_decision (CLAUDE.md, log par decision, jamais par
# tick) : n'imprime/ne met a jour action_precedente que sur un CHANGEMENT
# reel. Verrouille les trois cas -- RIEN -> cible, meme cible rejouee
# (aucun changement), cible A -> cible B (doit suivre, jamais rester
# bloque sur l'ancienne).
func _logger_decision_change_seulement_sur_changement_reel() -> void:
	var b := BancLienPersonnel.new()
	b._transformations = {}
	var colon := {"id": "colon_test", "action_precedente": ""}

	var g_rien := {"decision": null, "resultats": [], "cible": Vector3.ZERO, "chose": null, "position_avant": Vector3.ZERO}
	b._logger_decision(colon, g_rien)
	verif.v(colon.action_precedente == "RIEN", "sans decision, l'etiquette doit etre RIEN")

	var chose_a := {"id": "feu_a", "position": Vector3(10, 0, 0), "proprietes": {}}
	var g_a := {"decision": {"type": "brule", "chose": chose_a}, "resultats": [1], "cible": Vector3(10, 0, 0), "chose": chose_a, "position_avant": Vector3.ZERO}
	b._logger_decision(colon, g_a)
	verif.v(colon.action_precedente.begins_with("feu_a"), "une decision resolue doit nommer la chose visee, pas rester RIEN")

	var precedente: String = colon.action_precedente
	b._logger_decision(colon, g_a)
	verif.v(colon.action_precedente == precedente, "meme decision rejouee : l'etiquette ne doit pas changer (pas de re-log)")

	var chose_b := {"id": "feu_b", "position": Vector3(20, 0, 0), "proprietes": {}}
	var g_b := {"decision": {"type": "brule", "chose": chose_b}, "resultats": [1], "cible": Vector3(20, 0, 0), "chose": chose_b, "position_avant": Vector3.ZERO}
	b._logger_decision(colon, g_b)
	verif.v(colon.action_precedente.begins_with("feu_b") and colon.action_precedente != precedente,
		"une nouvelle cible doit mettre a jour l'etiquette, jamais rester bloquee sur l'ancienne")
