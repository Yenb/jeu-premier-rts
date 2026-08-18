extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_maladie.gd
#
# Verrouille le cablage de banc_maladie.gd : contagion (charge.gd), incubation
# qui expire seule (etat_duree.gd), symptomes (etat_effectif.gd), mort
# (seuil_etat.gd) -- les quatre mecanismes du coeur restent INCHANGES, ce
# fichier ne verrouille que le cablage. Les canaux/etats/seuils reels
# (data/banc_maladie.json, data/etats.json, data/seuils_etat.json) sont lus
# sur disque, comme le fait le banc -- chemin reel, pas une fixture locale
# pour les seuils/durees (meme discipline que test_banc_contagion.gd).
#
# DEUX FAMILLES DE CAS, a ne pas confondre :
# - les cas de mecanique posent leurs propres colons, immobiles, aux
#   distances qu'ils veulent : ils isolent UNE transition et ne disent rien
#   de la jouabilite du banc ;
# - _config_reelle_du_disque_produit_une_epidemie rejoue data/banc_maladie.
#   json EN ENTIER, deplacement seede compris. Sans lui, tout ce fichier
#   restait VERT alors que le banc lance a l'ecran ne contaminait personne.
# Aucun cas de la premiere famille ne remplace le second.

const BancMaladie = preload("res://scripts/banc_maladie.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DELTA_TICK := 0.1

var _config: Dictionary
var _etats: Dictionary
var _seuils_etat: Dictionary

func _init() -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_maladie.json"))
	_etats = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	_seuils_etat = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json"))

	_patient_zero_contamine_un_colon_a_portee()
	_colon_contamine_est_porteur_pendant_incubation_et_vitesse_inchangee()
	_apres_incubation_vitesse_reduite()
	_porteur_en_incubation_contamine_un_troisieme_colon()
	_colon_mort_ne_contamine_plus()
	_colon_hors_portee_jamais_contamine()
	_tous_les_colons_finissent_touches_en_zone_petite()
	_etat_courant_et_compter_etats()
	_deplacement_reste_dans_la_zone_et_colon_mort_ne_bouge_plus()
	_config_reelle_du_disque_produit_une_epidemie()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_maladie.gd -- contagion (charge.gd), incubation qui expire " +
		"seule (etat_duree.gd), symptomes (etat_effectif.gd) et mort " +
		"(seuil_etat.gd) s'enchainent sans qu'aucun mecanisme du coeur ne soit " +
		"touche")
	quit(0)

# Construit une config minimale au MEME FORMAT que data/banc_maladie.json,
# canal_maladie/vitesse_base/seuil_mort REELS (lus sur disque en _init),
# colons fournis par le test -- chemin reel pour les grandeurs qui comptent,
# fixture locale seulement pour les positions/id.
func _config_test(colons: Array, patient_zero_id: String) -> Dictionary:
	return {
		"vitesse_base": _config.vitesse_base,
		"canal_maladie": _config.canal_maladie,
		"patient_zero_id": patient_zero_id,
		"colons": colons,
	}

func _colon_decl(id: String, position: Vector3) -> Dictionary:
	return {"id": id, "position": [position.x, position.y, position.z]}

func _colon_par_id(colons: Array, id: String) -> Dictionary:
	for colon in colons:
		if colon.id == id:
			return colon
	return {}

func _avancer_n_fois(colons: Array, n: int) -> Dictionary:
	var cumul := {"nouveaux_porteurs": [], "nouveaux_malades": [], "gueris": [], "morts": []}
	for i in n:
		var r := BancMaladie.avancer(colons, DELTA_TICK, _etats, _seuils_etat)
		for cle in cumul:
			cumul[cle].append_array(r[cle])
	return cumul

func _patient_zero_contamine_un_colon_a_portee() -> void:
	var colons := [_colon_decl("p0", Vector3.ZERO), _colon_decl("sain", Vector3(10.0, 0.0, 0.0))]
	var c := BancMaladie.fabriquer_colons(_config_test(colons, "p0"), _etats)
	var sain := _colon_par_id(c, "sain")

	verif.v(sain.proprietes.has("etats"), "un colon jamais contamine doit porter un canal 'etats.maladie'")
	verif.v(sain.proprietes.get("porteur", 0.0) == 0.0, "un colon jamais contamine n'est pas porteur")

	var r := _avancer_n_fois(c, 35)
	verif.v(r.nouveaux_porteurs.size() == 1 and r.nouveaux_porteurs[0].id == "sain",
		"le colon a portee du patient zero doit avoir ete contamine en 35 ticks (3.5s, au-dela du seuil du canal reel a poids 1.0)")
	verif.v(r.nouveaux_porteurs[0].infecteur_id == "p0", "la trace doit nommer le patient zero comme infecteur")

func _colon_contamine_est_porteur_pendant_incubation_et_vitesse_inchangee() -> void:
	var colons := [_colon_decl("p0", Vector3.ZERO), _colon_decl("sain", Vector3(10.0, 0.0, 0.0))]
	var c := BancMaladie.fabriquer_colons(_config_test(colons, "p0"), _etats)
	_avancer_n_fois(c, 35)
	var sain := _colon_par_id(c, "sain")

	verif.v(sain.proprietes.get("porteur", 0.0) == 1.0,
		"un colon fraichement contamine doit etre porteur IMMEDIATEMENT, avant tout symptome")
	verif.v(sain.proprietes.etats_actifs.has("incube_maladie"),
		"un colon fraichement contamine doit porter l'etat 'incube_maladie'")
	verif.v(not sain.proprietes.etats_actifs.has("malade"),
		"un colon en incubation ne doit pas encore porter 'malade'")
	verif.v(not sain.proprietes.has("etats"),
		"un colon contamine doit sortir du pool des receveurs de charge.gd (canal 'etats' retire)")

	var BancCommunTest = preload("res://scripts/etat_effectif.gd")
	var vitesse_eff: float = BancCommunTest.valeur(sain, "vitesse", _etats)
	verif.v(is_equal_approx(vitesse_eff, _config.vitesse_base),
		"pendant l'incubation, la vitesse effective doit rester EXACTEMENT la vitesse de base (aucun symptome)")

func _apres_incubation_vitesse_reduite() -> void:
	var colons := [_colon_decl("p0", Vector3.ZERO), _colon_decl("sain", Vector3(10.0, 0.0, 0.0))]
	var c := BancMaladie.fabriquer_colons(_config_test(colons, "p0"), _etats)
	_avancer_n_fois(c, 35)
	var r := _avancer_n_fois(c, 45)
	var sain := _colon_par_id(c, "sain")

	verif.v(r.nouveaux_malades.has("sain"),
		"apres 45 ticks de plus (4.5s > incubation_s=4.0), l'incubation doit avoir expire et 'malade' doit avoir ete pose")
	verif.v(sain.proprietes.etats_actifs.has("malade"), "le colon doit desormais porter l'etat 'malade'")
	verif.v(not sain.proprietes.etats_actifs.has("incube_maladie"), "'incube_maladie' doit avoir disparu au profit de 'malade'")

	var EtatEffectif = preload("res://scripts/etat_effectif.gd")
	var vitesse_eff: float = EtatEffectif.valeur(sain, "vitesse", _etats)
	verif.v(is_equal_approx(vitesse_eff, _config.vitesse_base * 0.3),
		"une fois malade, la vitesse effective doit etre reduite exactement par le facteur de data/etats.json:malade")

# Positions calees sur portee_charge REELLE, jamais en dur : 'relais' a une
# demi-portee de p0 (donc a portee), 'bout_de_chaine' a une portee PLEINE de
# p0 (donc STRICTEMENT hors de sa portee, en_portee compare a <=) mais a une
# demi-portee de relais. La chaine est ainsi la SEULE explication possible de
# la contamination de bout_de_chaine -- l'ancienne geometrie (0/10/20 face a
# une portee de 60) le laissait a portee directe de p0 et ne prouvait donc
# rien : la trace ne nommait 'relais' que parce qu'il etait le plus proche.
func _porteur_en_incubation_contamine_un_troisieme_colon() -> void:
	var portee: float = _config.canal_maladie.portee_charge
	var colons := [
		_colon_decl("p0", Vector3.ZERO),
		_colon_decl("relais", Vector3(portee * 0.5, 0.0, 0.0)),
		_colon_decl("bout_de_chaine", Vector3(portee * 1.01, 0.0, 0.0)),
	]
	var c := BancMaladie.fabriquer_colons(_config_test(colons, "p0"), _etats)

	# Duree d'incubation reelle, jamais recopiee ici -- ce test s'arrete
	# forcement AVANT que 'relais' ne bascule en 'malade'.
	var incubation_s: float = _etats.incube_maladie.duree
	var ticks := int(incubation_s / DELTA_TICK)
	var r := _avancer_n_fois(c, ticks)
	var relais := _colon_par_id(c, "relais")
	var bout := _colon_par_id(c, "bout_de_chaine")

	verif.v(r.nouveaux_porteurs.size() >= 2, "la chaine p0 -> relais -> bout_de_chaine doit avoir produit deux contaminations avant la fin de l'incubation de relais")
	verif.v(bout.proprietes.get("porteur", 0.0) == 1.0, "bout_de_chaine doit avoir ete contamine par relais -- il est hors de la portee de p0, aucune autre cause n'existe")
	verif.v(BancMaladie.etat_courant(relais) == "incubation",
		"relais doit ENCORE etre en incubation -- il a donc contamine bout_de_chaine AVANT ses propres symptomes")

	var infecteur_bout := ""
	for entree in r.nouveaux_porteurs:
		if entree.id == "bout_de_chaine":
			infecteur_bout = entree.infecteur_id
	verif.v(infecteur_bout == "relais", "la trace doit nommer 'relais' comme infecteur de bout_de_chaine, jamais p0")

func _colon_mort_ne_contamine_plus() -> void:
	var colon_malade := {
		"id": "mourant", "position": Vector3.ZERO, "destination": Vector3.ZERO,
		"proprietes": {
			"vitesse": _config.vitesse_base, "porteur": 1.0,
			"duree_maladie_cumulee": _config.seuil_mort - 0.05, "etats_actifs": ["malade"],
			"etats_intensite": {"malade": 0.5},
		},
	}
	var seuil_mort: float = _seuils_etat.mort_par_maladie.seuil
	verif.v(seuil_mort == _config.seuil_mort, "le seuil reel de data/seuils_etat.json:mort_par_maladie doit rester coherent avec data/banc_maladie.json:seuil_mort")

	var r := BancMaladie.avancer([colon_malade], DELTA_TICK, _etats, _seuils_etat)
	verif.v(r.morts.has("mourant"), "un colon dont duree_maladie_cumulee franchit le seuil doit mourir ce meme pas")
	verif.v(colon_malade.proprietes.etats_actifs.has("mort_maladie"), "l'etat 'mort_maladie' doit etre pose")
	verif.v(colon_malade.proprietes.get("porteur", 1.0) == 0.0, "un colon mort ne doit plus jamais etre porteur")

	var causes := BancMaladie.causes_de_porteurs([colon_malade])
	verif.v(causes.is_empty(), "un colon mort ne doit plus jamais figurer comme cause de contamination")

func _colon_hors_portee_jamais_contamine() -> void:
	var colons := [_colon_decl("p0", Vector3.ZERO), _colon_decl("loin", Vector3(100000.0, 0.0, 0.0))]
	var c := BancMaladie.fabriquer_colons(_config_test(colons, "p0"), _etats)
	var r := _avancer_n_fois(c, 200)
	var loin := _colon_par_id(c, "loin")

	verif.v(r.nouveaux_porteurs.is_empty(), "un colon hors de portee_charge ne doit jamais etre contamine, meme apres 20s")
	verif.v(loin.proprietes.get("porteur", 0.0) == 0.0, "un colon hors de portee reste porteur=0.0 pour toujours")
	verif.v(loin.proprietes.has("etats"), "un colon jamais contamine garde son canal 'etats.maladie'")

func _tous_les_colons_finissent_touches_en_zone_petite() -> void:
	var colons := [
		_colon_decl("p0", Vector3(0.0, 0.0, 0.0)),
		_colon_decl("c1", Vector3(15.0, 0.0, 0.0)),
		_colon_decl("c2", Vector3(30.0, 0.0, 0.0)),
		_colon_decl("c3", Vector3(0.0, 15.0, 0.0)),
		_colon_decl("c4", Vector3(15.0, 15.0, 0.0)),
	]
	var c := BancMaladie.fabriquer_colons(_config_test(colons, "p0"), _etats)
	_avancer_n_fois(c, 600)

	for colon in c:
		if colon.id == "p0":
			continue
		verif.v(not colon.proprietes.has("etats"),
			"'%s' doit avoir ete contamine au moins une fois en 60s, un cluster serre resserre bien sous portee_charge" % colon.id)

func _etat_courant_et_compter_etats() -> void:
	var sain := {"proprietes": {"etats_actifs": []}}
	var incubation := {"proprietes": {"etats_actifs": ["incube_maladie"]}}
	var malade := {"proprietes": {"etats_actifs": ["malade"]}}
	var mort := {"proprietes": {"etats_actifs": ["malade", "mort_maladie"]}}

	verif.v(BancMaladie.etat_courant(sain) == "sain", "un colon sans etat actif est 'sain'")
	verif.v(BancMaladie.etat_courant(incubation) == "incubation", "'incube_maladie' actif -> 'incubation'")
	verif.v(BancMaladie.etat_courant(malade) == "malade", "'malade' seul actif -> 'malade'")
	verif.v(BancMaladie.etat_courant(mort) == "mort", "'mort_maladie' actif (avec 'malade' encore actif) -> 'mort', priorite a la mort")

	var compte := BancMaladie.compter_etats([sain, incubation, malade, mort, sain])
	verif.v(compte.sain == 2 and compte.incubation == 1 and compte.malade == 1 and compte.mort == 1,
		"compter_etats doit repartir chaque colon dans exactement une categorie")

func _deplacement_reste_dans_la_zone_et_colon_mort_ne_bouge_plus() -> void:
	var zone := {"min": [0.0, 0.0, 0.0], "max": [100.0, 100.0, 0.0]}
	var vivant := {"id": "vivant", "position": Vector3(50.0, 50.0, 0.0), "destination": Vector3(50.0, 50.0, 0.0),
		"proprietes": {"vitesse": 200.0, "etats_actifs": []}}
	var mort := {"id": "mort", "position": Vector3(10.0, 10.0, 0.0), "destination": Vector3(10.0, 10.0, 0.0),
		"proprietes": {"vitesse": 200.0, "etats_actifs": ["mort_maladie"]}}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	for i in 50:
		BancMaladie.deplacer_colons([vivant, mort], zone, 200.0, _etats, rng, DELTA_TICK)

	verif.v(mort.position == Vector3(10.0, 10.0, 0.0), "un colon mort (vitesse effective ecrasee a 0.0) ne doit jamais bouger")
	verif.v(vivant.position.x >= zone.min[0] and vivant.position.x <= zone.max[0]
		and vivant.position.y >= zone.min[1] and vivant.position.y <= zone.max[1],
		"un colon vivant doit toujours rester a l'interieur des bornes de la zone")

# LE SEUL CAS QUI REJOUE data/banc_maladie.json EN ENTIER -- neuf colons a
# leurs positions reelles, deplacement aleatoire seede reel, canal/seuils/
# durees reels. Tous les autres cas de ce fichier posent leurs propres
# colons immobiles a portee : ils etaient VERTS alors que le banc lance a
# l'ecran ne contaminait PERSONNE (calibration d'origine, seuil 3.0 jamais
# atteint -- mesure, voir le _note de data/banc_maladie.json). C'est ce trou
# que ce cas ferme.
#
# Deux assertions seulement, les plus larges qui gardent le contrat : une
# calibration reste libre de bouger tant que l'epidemie DEMARRE et VA AU
# BOUT. Ne jamais y coder un compte de morts ni un instant precis -- ce
# serait reverrouiller la calibration elle-meme, que Yael doit pouvoir
# regler sans casser ce fichier.
func _config_reelle_du_disque_produit_une_epidemie() -> void:
	var colons := BancMaladie.fabriquer_colons(_config, _etats)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_config.seed)

	var patient_zero_id: String = _config.patient_zero_id
	var contamines_avant_mort_du_patient_zero := 0
	var patient_zero_mort := false
	var morts_hors_patient_zero := 0

	for i in 600:
		var r := BancMaladie.avancer(colons, DELTA_TICK, _etats, _seuils_etat)
		BancMaladie.deplacer_colons(colons, _config.zone, _config.vitesse_base, _etats, rng, DELTA_TICK)
		if not patient_zero_mort:
			contamines_avant_mort_du_patient_zero += r.nouveaux_porteurs.size()
		for id in r.morts:
			if id == patient_zero_id:
				patient_zero_mort = true
			else:
				morts_hors_patient_zero += 1

	verif.v(contamines_avant_mort_du_patient_zero > 0,
		"la config reelle du disque doit contaminer au moins un colon AVANT la mort du patient zero -- passe ce moment il n'existe plus aucune cause et l'epidemie ne peut plus jamais demarrer")
	verif.v(morts_hors_patient_zero > 0,
		"la config reelle du disque doit mener au moins un colon contamine jusqu'a la mort en 60s -- sinon la chaine contagion/incubation/symptomes/mort n'est pas observable a l'ecran")
