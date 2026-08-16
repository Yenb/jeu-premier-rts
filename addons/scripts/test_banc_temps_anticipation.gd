extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_temps_anticipation.gd
#
# Verrouille scripts/banc_temps_anticipation.gd -- le CHEMIN REEL du chantier
# « perception du temps + anticipation » (audit_perception_croyance_memoire_
# prealable.md, lignes 7 et 8). A la difference de test_horloge.gd /
# test_memoire_spatiale.gd / test_deformation.gd (hors domaine, mecanisme seul,
# catalogue invente), CE test rejoue les VRAIS fichiers du disque :
# data/banc_temps_anticipation.json, data/textes.json, data/seuils_etat.json,
# data/deformations.json, data/profils_saillance.json, data/memoire_spatiale.json,
# data/canaux.json, data/lumiere.json. Lecon de banc_maladie, deja payee une
# fois : un banc dont le test invente sa propre calibration reste VERT pendant
# que la scene reelle ne franchit jamais rien.
#
# CE QUE CE TEST VERROUILLE, et qu'aucun autre ne verrouillerait :
# 1. 'cycles_vecus' s'incremente A CHAQUE CHANGEMENT DE SAISON, jamais a chaque
#    tick, et jamais deux fois pour le meme changement ;
# 2. 'prevoyant' est pose AU SEUIL, par seuil_etat.gd et le catalogue partage ;
# 3. le vieux ANTICIPE -- biais de deformation actif, saillance du grenier
#    reellement montee pour lui ;
# 4. le jeune N'ANTICIPE PAS tant que son compte est sous le seuil : biais
#    EXACTEMENT nul, saillance INCHANGEE, alors qu'il traverse le meme automne ;
# 5. la perception du temps rend la BONNE CLE selon la force du souvenir, et
#    une CLE, jamais une phrase ;
# 6. data/textes.json porte les traductions des trois cles, et le cablage ne
#    sait produire aucun texte sans lui ;
# 7. 'base_innee' est bien la valeur INITIALE de 'cycles_vecus' du plus jeune ;
# 8. la calibration declaree rend le banc observable, sans quoi les sept points
#    ci-dessus seraient vrais et la scene ne montrerait rien ;
# 9. le pas complet est DETERMINISTE -- aucun RNG, nulle part.

const Banc = preload("res://scripts/banc_temps_anticipation.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

var _config: Dictionary = {}
var _textes: Dictionary = {}
var _canaux: Dictionary = {}
var _lumiere: Dictionary = {}
var _memoire: Dictionary = {}
var _profils: Dictionary = {}
var _deformations: Dictionary = {}
var _seuils_etat: Dictionary = {}

func _init() -> void:
	_config = _charger("res://data/banc_temps_anticipation.json")
	_textes = _charger("res://data/textes.json")
	_canaux = _charger("res://data/canaux.json")
	_lumiere = _charger("res://data/lumiere.json")
	_memoire = _charger("res://data/memoire_spatiale.json")
	_profils = _charger("res://data/profils_saillance.json")
	_deformations = _charger("res://data/deformations.json")
	_seuils_etat = _charger("res://data/seuils_etat.json")

	var v := Verif.new()
	_calibration_declaree_rend_le_banc_observable(v)
	_les_catalogues_partages_portent_les_entrees_du_chantier(v)
	_horloge_rend_les_saisons_dans_lordre_declare(v)
	_cycles_vecus_sincremente_a_chaque_changement_de_saison(v)
	_prevoyant_est_pose_au_seuil(v)
	_le_vieux_anticipe(v)
	_le_jeune_nanticipe_pas(v)
	_lanticipation_retombe_hors_de_la_saison(v)
	_la_perception_du_temps_rend_la_bonne_cle(v)
	_les_reperes_traversent_les_trois_cles(v)
	_textes_json_porte_les_traductions(v)
	_base_innee_est_la_valeur_initiale_du_compteur(v)
	_le_pas_complet_est_deterministe(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_temps_anticipation.gd -- le colon lit le temps dans la force de ses souvenirs " +
			"(cles i18n, jamais une phrase), compte les saisons vecues, devient prevoyant au seuil, " +
			"et seul un prevoyant fait monter la saillance du grenier avant l'hiver")
		quit(0)

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _scene() -> Dictionary:
	var monde = Monde.new()
	var colons: Array = []
	for decl in _config.colons:
		var colon := Banc.construire_colon(decl, _config)
		colons.append(colon)
		monde.ajouter(colon, String(decl.type), colon.position)
	var grenier := Banc.construire_grenier(_config)
	monde.ajouter(grenier, String(_config.grenier.type), grenier.position)
	var reperes: Array = []
	for decl in _config.reperes:
		var repere := Banc.construire_repere(decl)
		reperes.append(repere)
		monde.ajouter(repere, String(decl.type), repere.position)
	return {"colons": colons, "grenier": grenier, "reperes": reperes, "monde": monde}

func _pas(scene: Dictionary, temps: float, delta: float) -> Dictionary:
	return Banc.avancer(
		scene.colons, scene.grenier, scene.reperes, scene.monde, _config,
		_canaux, _lumiere, _memoire, _profils, _deformations, _seuils_etat,
		temps, delta)

func _boucle(scene: Dictionary, depart: float, pas: int, delta: float) -> Dictionary:
	var bilan: Dictionary = {}
	for i in range(pas):
		bilan = _pas(scene, depart + float(i) * delta, delta)
	return bilan

# Rend l'etat d'un colon dans un bilan, par son nom declare en donnee.
func _etat(bilan: Dictionary, nom: String) -> Dictionary:
	for etat in bilan.colons:
		if String(etat.nom) == nom:
			return etat
	return {}

func _vec(brut: Array) -> Vector3:
	return Vector3(brut[0], brut[1], brut[2])

func _duree_saison() -> float:
	return float(_config.cycle.duree_jour_secondes) * float(_config.cycle.jours_par_saison)

# La calibration DECLAREE doit rendre le banc observable. Sans ce cas, une
# retouche de data/banc_temps_anticipation.json (une portee, un seuil, une
# position) laisserait tous les autres cas VERTS pendant que la scene ne
# montrerait plus rien : le grenier jamais vu, le repere jamais perdu de vue,
# ou les trois colons du meme cote du seuil.
func _calibration_declaree_rend_le_banc_observable(v) -> void:
	var portee: float = float(_config.portee_vue)
	var grenier := _vec(_config.grenier.position)
	var seuil: float = float(_config.seuil_prevoyance)

	for decl in _config.colons:
		var pos := _vec(decl.position)
		v.v(pos.distance_to(grenier) < portee,
			"chaque colon doit VOIR le grenier, sans quoi sa saillance n'est jamais evaluee")

	var jeune: float = float(_config.colons[0].cycles_vecus)
	var adulte: float = float(_config.colons[1].cycles_vecus)
	var vieux: float = float(_config.colons[2].cycles_vecus)
	v.v(jeune < adulte and adulte < vieux, "les trois colons doivent porter trois comptes distincts et croissants")
	v.v(vieux > seuil, "le vieux doit etre prevoyant DES LE DEPART, sans quoi le banc n'a rien a montrer au debut")
	v.v(jeune < seuil, "le jeune ne doit PAS etre prevoyant au depart -- c'est le temoin du banc")
	v.v(adulte <= seuil, "l'adulte doit DEVENIR prevoyant en cours de route, jamais l'etre des le premier pas")

	var reference := _vec(_config.colons[1].position)
	var proche: Dictionary = _config.reperes[0]
	var lointain: Dictionary = _config.reperes[1]
	v.v(not bool(proche.s_eloigne), "le premier repere doit RESTER : c'est le temoin 'souvenir recent'")
	v.v(bool(lointain.s_eloigne), "le second repere doit s'eloigner, sans quoi aucune cle ne change jamais")
	v.v(reference.distance_to(_vec(proche.position_initiale)) < portee,
		"le repere temoin doit rester a portee de vue")
	v.v(reference.distance_to(_vec(lointain.position_initiale)) < portee,
		"le repere qui s'eloigne doit d'abord etre VU, sans quoi aucun souvenir ne se forme")
	for decl in _config.colons:
		v.v(_vec(decl.position).distance_to(_vec(lointain.position_lointaine)) > portee,
			"une fois parti, le repere doit sortir de la portee de vue de TOUS les colons")

	v.v(float(_config.seuil_souvenir_recent) > float(_config.seuil_souvenir_ancien),
		"le seuil 'recent' doit etre au-dessus du seuil 'ancien'")
	v.v(float(_config.seuil_souvenir_recent) < float(_config.plafond_force),
		"un souvenir sature doit tomber dans 'recent', sinon aucune chose vue a l'instant n'y tombe jamais")
	v.v(_duree_saison() > 0.0, "une saison doit durer un temps strictement positif")
	v.v(_config.cycle.saisons.has(String(_config.saison_avant_hiver)),
		"la saison d'anticipation doit exister dans la liste des saisons declarees")

# Les trois entrees ajoutees aux catalogues PARTAGES doivent y etre, et decrire
# ce que ce banc suppose. Sans ce cas, un chantier concurrent qui les
# renommerait laisserait le banc silencieusement inerte : seuil_etat.gd ne
# poserait plus rien, proximite.gd ne trouverait plus de profil, et aucun test
# de mecanisme ne rougirait.
func _les_catalogues_partages_portent_les_entrees_du_chantier(v) -> void:
	var seuil: Dictionary = _seuils_etat.get("prevoyance", {})
	v.v(String(seuil.get("propriete_continue", "")) == "cycles_vecus",
		"data/seuils_etat.json:prevoyance doit comparer 'cycles_vecus'")
	v.v(String(seuil.get("seuil_propriete", "")) == "seuil_prevoyance",
		"le seuil doit etre lu PAR OBJET (patron rupture_grief/seuil_rupture), jamais universel")
	v.v(String(seuil.get("etat", "")) == String(_config.etat_prevoyant),
		"l'etat pose doit etre celui que le cablage lit comme gate")

	var source: Dictionary = _deformations.get(String(_config.source_deformation), {})
	v.v(String(source.get("sens", "")) == "monte",
		"la deformation d'anticipation doit MONTER la saillance -- 'baisse' la ferait descendre, en silence")
	v.v(float(source.get("taux_decroissance_rapide", 0.0)) > 0.0 and float(source.get("taux_decroissance_lent", 0.0)) > 0.0,
		"les deux taux doivent etre non nuls, sans quoi le biais ne retomberait JAMAIS apres l'automne")
	v.v(float(source.get("w_rapide", 0.0)) + float(source.get("w_lent", 0.0)) > 0.0,
		"au moins un des deux poids doit etre non nul, sinon biais() rend toujours 0.0")

	v.v(_profils.has(String(_config.grenier.profil_saillance)),
		"le profil de saillance du grenier doit exister dans le catalogue partage")
	v.v(_textes.has(String(_config.langue)), "data/textes.json doit porter la langue declaree en donnee de banc")

func _horloge_rend_les_saisons_dans_lordre_declare(v) -> void:
	var saisons: Array = _config.cycle.saisons
	var duree := _duree_saison()
	for i in range(saisons.size()):
		v.v(Banc.saison_courante(duree * float(i) + duree * 0.5, _config) == String(saisons[i]),
			"la saison au milieu du %d-ieme intervalle doit etre celle declaree a cet index" % i)
	v.v(Banc.saison_courante(duree * float(saisons.size()) + duree * 0.5, _config) == String(saisons[0]),
		"le cycle doit BOUCLER -- une saison est cyclique, c'est pourquoi stade.gd ne pouvait pas la porter")

# LE COMPTEUR. Trois choses a la fois, et chacune casse seule : le premier appel
# n'invente pas un changement, un tick sans changement n'incremente rien, et un
# changement n'est compte QU'UNE FOIS meme s'il est suivi de cent ticks.
func _cycles_vecus_sincremente_a_chaque_changement_de_saison(v) -> void:
	var scene := _scene()
	var colon: Dictionary = scene.colons[0]
	var depart: float = float(colon.proprietes.cycles_vecus)

	Banc.compter_cycles(scene.colons, "printemps")
	v.v(is_equal_approx(float(colon.proprietes.cycles_vecus), depart),
		"le PREMIER appel ne doit rien incrementer -- il n'y a pas eu de changement, seulement un debut")
	Banc.compter_cycles(scene.colons, "printemps")
	v.v(is_equal_approx(float(colon.proprietes.cycles_vecus), depart),
		"une saison inchangee ne doit rien incrementer")
	var comptes: Array = Banc.compter_cycles(scene.colons, "ete")
	v.v(is_equal_approx(float(colon.proprietes.cycles_vecus), depart + 1.0),
		"un changement de saison doit incrementer de 1.0 exactement")
	v.v(comptes.size() == scene.colons.size(), "TOUS les colons doivent compter le meme changement")
	Banc.compter_cycles(scene.colons, "ete")
	v.v(is_equal_approx(float(colon.proprietes.cycles_vecus), depart + 1.0),
		"le meme changement ne doit jamais etre compte deux fois")

	# Et sur le chemin reel, en rejouant le temps : une saison ecoulee, un cycle.
	var reelle := _scene()
	var duree := _duree_saison()
	var bilan := _boucle(reelle, 0.0, int(duree / 0.1) + 4, 0.1)
	v.v(is_equal_approx(float(_etat(bilan, "jeune").cycles_vecus), float(_config.base_innee) + 1.0),
		"apres une saison ecoulee en temps reel, chaque colon doit avoir compte exactement un cycle")

# 'prevoyant' n'est pas pose par le cablage : il l'est par seuil_etat.gd, depuis
# le catalogue partage. Ce cas verrouille les DEUX cotes du seuil sur le meme
# pas de temps -- le vieux au-dessus des le premier tick (bootstrap de
# seuil_etat.gd), l'adulte encore en dessous.
func _prevoyant_est_pose_au_seuil(v) -> void:
	var scene := _scene()
	var bilan := _pas(scene, 0.0, 0.1)
	v.v(bool(_etat(bilan, "vieux").prevoyant),
		"un colon deja au-dessus du seuil doit devenir prevoyant DES LE PREMIER PAS")
	v.v(not bool(_etat(bilan, "adulte").prevoyant), "l'adulte ne doit pas encore etre prevoyant")
	v.v(not bool(_etat(bilan, "jeune").prevoyant), "le jeune ne doit pas etre prevoyant")

	# Deux saisons plus tard, l'adulte a compte deux cycles et franchit.
	var duree := _duree_saison()
	var apres := _boucle(scene, 0.1, int(duree * 2.0 / 0.1) + 4, 0.1)
	var adulte := _etat(apres, "adulte")
	v.v(float(adulte.cycles_vecus) > float(_config.seuil_prevoyance),
		"apres deux changements de saison, le compte de l'adulte doit avoir depasse son seuil")
	v.v(bool(adulte.prevoyant), "l'adulte doit alors etre devenu prevoyant")
	v.v(not bool(_etat(apres, "jeune").prevoyant),
		"le jeune, parti de bien plus bas, ne doit toujours pas l'etre")

# LE POINT DU CHANTIER, cote anticipation. Le grenier n'a pas change ; le vieux
# n'a pas bouge ; c'est sa LECTURE du meme monde qui a change, et elle a change
# parce qu'il a vecu des hivers.
func _le_vieux_anticipe(v) -> void:
	var scene := _scene()
	var duree := _duree_saison()
	var index_saison: int = _config.cycle.saisons.find(String(_config.saison_avant_hiver))

	# Hors saison d'anticipation : rien ne doit etre pose, biais nul.
	var avant := _boucle(scene, 0.0, 60, 0.1)
	var vieux_avant := _etat(avant, "vieux")
	v.v(bool(vieux_avant.prevoyant), "precondition : le vieux est prevoyant")
	v.v(is_equal_approx(float(vieux_avant.biais), 0.0),
		"hors de la saison declaree, meme un prevoyant ne doit RIEN poser")
	var saillance_nue: float = float(vieux_avant.saillance_grenier)
	v.v(saillance_nue > 0.0, "precondition : le grenier doit deja etre saillant, sans aucun biais")

	# Dans la saison d'anticipation.
	var debut_saison := duree * float(index_saison)
	var pendant := _boucle(scene, debut_saison, 80, 0.1)
	var vieux := _etat(pendant, "vieux")
	v.v(String(pendant.saison) == String(_config.saison_avant_hiver),
		"precondition : on doit bien etre dans la saison declaree avant l'hiver")
	v.v(float(vieux.biais) > 0.0, "le vieux doit avoir accumule un biais d'anticipation")
	v.v(float(vieux.saillance_grenier) > saillance_nue,
		"la saillance du grenier doit avoir REELLEMENT monte pour lui -- un biais qui ne se lit " +
		"nulle part serait vrai dans le registre et sans effet dans le jeu, en silence")
	v.v(is_equal_approx(float(vieux.saillance_grenier), saillance_nue * (1.0 + float(vieux.biais))),
		"la montee doit etre exactement celle de proximite.gd (saillance *= 1 + biais), jamais recalculee ici")

	# Le plafond tient : le coeur ne borne jamais le haut.
	var longtemps := _boucle(scene, debut_saison + 8.0, 100, 0.1)
	v.v(float(_etat(longtemps, "vieux").biais) <= float(_config.plafond_biais_anticipation) + 0.0001,
		"le biais ne doit JAMAIS depasser le plafond du cablage -- sans ce gate il monterait sans borne")

	# Et un vieux monte plus vite qu'un adulte, a saison egale : c'est le debit
	# qui differe (base + gain * cycles_vecus), jamais le catalogue.
	var duo := _scene()
	_boucle(duo, 0.0, int(debut_saison / 0.1), 0.1)
	var court := _boucle(duo, debut_saison, 12, 0.1)
	var b_vieux: float = float(_etat(court, "vieux").biais)
	var b_adulte: float = float(_etat(court, "adulte").biais)
	v.v(bool(_etat(court, "adulte").prevoyant), "precondition : l'adulte est devenu prevoyant lui aussi")
	v.v(b_vieux > b_adulte,
		"a saison egale et depuis le meme instant, le vieux doit anticiper PLUS FORT que l'adulte")

func _le_jeune_nanticipe_pas(v) -> void:
	var scene := _scene()
	var duree := _duree_saison()
	var index_saison: int = _config.cycle.saisons.find(String(_config.saison_avant_hiver))
	var debut_saison := duree * float(index_saison)

	var avant := _boucle(scene, 0.0, 60, 0.1)
	var saillance_nue: float = float(_etat(avant, "jeune").saillance_grenier)

	_boucle(scene, 6.0, int((debut_saison - 6.0) / 0.1), 0.1)
	var pendant := _boucle(scene, debut_saison, 120, 0.1)
	var jeune := _etat(pendant, "jeune")
	v.v(String(pendant.saison) == String(_config.saison_avant_hiver),
		"precondition : le jeune traverse bien la MEME saison que le vieux")
	v.v(float(jeune.cycles_vecus) < float(_config.seuil_prevoyance),
		"precondition : son compte est reste sous son seuil")
	v.v(not bool(jeune.prevoyant), "il ne doit pas etre prevoyant")
	v.v(is_equal_approx(float(jeune.biais), 0.0),
		"son biais doit etre EXACTEMENT nul -- pas petit, nul : le gate ferme n'appelle jamais poser()")
	v.v(is_equal_approx(float(jeune.saillance_grenier), saillance_nue),
		"le grenier ne doit pas avoir monte d'un poil pour lui, alors qu'il monte pour le vieux au " +
		"MEME instant et dans le MEME monde")

# Un biais qui ne retomberait pas laisserait le colon colle au grenier toute
# l'annee : le banc ne montrerait plus qu'un etat permanent, jamais une
# anticipation. C'est deformation.gd:avancer qui le fait, sans une ligne ici.
func _lanticipation_retombe_hors_de_la_saison(v) -> void:
	var scene := _scene()
	var duree := _duree_saison()
	var index_saison: int = _config.cycle.saisons.find(String(_config.saison_avant_hiver))
	var debut_saison := duree * float(index_saison)

	_boucle(scene, 0.0, int(debut_saison / 0.1), 0.1)
	var charge := _boucle(scene, debut_saison, 100, 0.1)
	var haut: float = float(_etat(charge, "vieux").biais)
	v.v(haut > 0.0, "precondition : le biais est charge")

	var apres := _boucle(scene, debut_saison + duree, 200, 0.1)
	v.v(String(apres.saison) != String(_config.saison_avant_hiver), "precondition : la saison a change")
	v.v(float(_etat(apres, "vieux").biais) < haut, "le biais doit RETOMBER une fois la saison passee")

# LA LIGNE 7 DE L'AUDIT, dans sa forme la plus nue : une fonction pure
# force -> CLE. Aucun texte, aucune concatenation, aucune horloge.
func _la_perception_du_temps_rend_la_bonne_cle(v) -> void:
	var recent: float = float(_config.seuil_souvenir_recent)
	var ancien: float = float(_config.seuil_souvenir_ancien)
	v.v(Banc.cle_perception_temps(float(_config.plafond_force), _config) == "souvenir.recent",
		"un souvenir sature doit etre 'recent'")
	v.v(Banc.cle_perception_temps(recent, _config) == "souvenir.recent",
		"le seuil 'recent' est inclusif -- la borne appartient au cas du haut")
	v.v(Banc.cle_perception_temps(recent - 0.001, _config) == "souvenir.ancien",
		"juste sous le seuil 'recent', le souvenir devient 'ancien'")
	v.v(Banc.cle_perception_temps(ancien, _config) == "souvenir.ancien", "le seuil 'ancien' est inclusif")
	v.v(Banc.cle_perception_temps(ancien - 0.001, _config) == "souvenir.tres_ancien",
		"sous le seuil 'ancien', le souvenir devient 'tres ancien'")
	v.v(Banc.cle_perception_temps(0.0, _config) == "souvenir.tres_ancien", "une force nulle est 'tres ancien'")

	# Une chose JAMAIS memorisee ne rend AUCUNE cle -- ne pas savoir n'est pas
	# savoir vaguement. Sans ce cas, le label afficherait « Il y a longtemps »
	# a propos d'une chose que le colon n'a jamais vue.
	var scene := _scene()
	v.v(Banc.cle_souvenir(scene.colons[0], "chose_jamais_vue", _config) == "",
		"une chose jamais memorisee ne doit rendre aucune cle")
	v.v(Banc.texte("", _config, _textes) == "", "aucune cle, aucun texte")

# Le chemin REEL : la cle change parce que la FORCE decroit, et pour aucune
# autre raison. Le repere temoin, lui, reste vu et reste donc 'recent' -- ce qui
# prouve que ce n'est pas le TEMPS ECOULE qui est lu (il passe pour les deux),
# mais bien l'etat du souvenir.
func _les_reperes_traversent_les_trois_cles(v) -> void:
	var scene := _scene()
	var proche := String(_config.reperes[0].id)
	var lointain := String(_config.reperes[1].id)

	var tot := _boucle(scene, 0.0, 60, 0.1)
	var jeune := _etat(tot, "jeune")
	v.v(String(jeune.souvenirs[proche].cle) == "souvenir.recent", "le repere temoin doit etre 'recent'")
	v.v(String(jeune.souvenirs[lointain].cle) == "souvenir.recent",
		"le repere qui vient de partir doit encore etre 'recent'")

	var taux: float = float(_memoire.defaut.taux_decroissance)
	var plafond: float = float(_config.plafond_force)
	var vers_ancien: float = (plafond - float(_config.seuil_souvenir_ancien)) / taux
	var moyen := _boucle(scene, 6.0, int(vers_ancien * 0.5 / 0.1), 0.1)
	var au_milieu := _etat(moyen, "jeune")
	v.v(String(au_milieu.souvenirs[lointain].cle) == "souvenir.ancien",
		"a mi-chemin de l'oubli, le repere parti doit etre devenu 'ancien'")
	v.v(String(au_milieu.souvenirs[proche].cle) == "souvenir.recent",
		"le repere TOUJOURS VU doit rester 'recent' au meme instant -- ce n'est pas le temps ecoule " +
		"qui est lu, c'est la force du souvenir")

	var vieux_souvenir := _boucle(scene, 6.0 + vers_ancien * 0.5, int(vers_ancien * 0.6 / 0.1), 0.1)
	var au_bout := _etat(vieux_souvenir, "jeune")
	v.v(String(au_bout.souvenirs[lointain].cle) == "souvenir.tres_ancien",
		"plus tard encore, le repere parti doit etre 'tres ancien'")
	v.v(float(au_bout.souvenirs[lointain].force) < float(au_milieu.souvenirs[lointain].force),
		"sa force doit avoir strictement decru entre les deux mesures")
	v.v(String(au_bout.souvenirs[proche].cle) == "souvenir.recent",
		"et le temoin, lui, doit toujours etre 'recent'")

# CLAUDE.md, regle non negociable : « le code manipule des CLES, les textes
# vivent en donnees ». Ce cas verrouille les deux bouts -- le catalogue porte
# bien les trois traductions, et rien dans le cablage ne sait produire un texte
# sans lui (une cle absente ressort telle quelle, visible donc corrigee, jamais
# un repli ecrit en dur).
func _textes_json_porte_les_traductions(v) -> void:
	var langue := String(_config.langue)
	var table: Dictionary = _textes.get(langue, {})
	for cle in ["souvenir.recent", "souvenir.ancien", "souvenir.tres_ancien"]:
		v.v(table.has(cle), "data/textes.json > %s doit porter la cle '%s'" % [langue, cle])
		v.v(String(table.get(cle, "")) != "", "la traduction de '%s' ne doit pas etre vide" % cle)
		v.v(Banc.texte(cle, _config, _textes) == String(table[cle]),
			"le cablage doit rendre la traduction du catalogue, jamais un texte a lui")
	v.v(String(table.get("souvenir.recent", "")) != String(table.get("souvenir.tres_ancien", "")),
		"les trois cles doivent porter trois textes distincts, sinon le label ne montre rien")
	v.v(Banc.texte("cle.qui.nexiste.pas", _config, _textes) == "cle.qui.nexiste.pas",
		"une cle absente doit ressortir TELLE QUELLE -- visible a l'ecran, donc corrigee")

	# Ajouter une langue = une cle dans data/textes.json, ZERO ligne de code.
	var enrichis: Dictionary = _textes.duplicate(true)
	enrichis["xx"] = {"souvenir.recent": "TEMOIN"}
	var config_xx: Dictionary = _config.duplicate(true)
	config_xx["langue"] = "xx"
	v.v(Banc.texte("souvenir.recent", config_xx, enrichis) == "TEMOIN",
		"une langue ajoutee en donnee doit etre lue sans une ligne de code de plus")

# 'base_innee' n'est ni un poids de verbe ni un biais : c'est le POINT DE DEPART
# du compteur du plus jeune. Ce cas verrouille les trois choses qui en
# decoulent, et la troisieme est celle qui distingue cette lecture de l'autre :
# tant que le gate est ferme, le biais du jeune est nul -- sa base innee ne lui
# donne pas un petit biais, elle le place plus haut sur la MEME echelle que le
# vieux, donc plus pres du seuil qu'un colon qui naitrait a 0.0.
func _base_innee_est_la_valeur_initiale_du_compteur(v) -> void:
	var base: float = float(_config.base_innee)
	v.v(is_equal_approx(float(_config.colons[0].cycles_vecus), base),
		"le plus jeune doit etre pose EXACTEMENT a 'base_innee'")
	v.v(base > 0.0, "la base innee doit etre non nulle -- un jeune n'est pas d'une autre espece qu'un vieux")
	v.v(base < float(_config.seuil_prevoyance), "elle doit rester sous le seuil, sinon tout le monde anticipe")

	var scene := _scene()
	var jeune: Dictionary = scene.colons[0]
	var vieux: Dictionary = scene.colons[2]
	v.v(is_equal_approx(float(jeune.proprietes.cycles_vecus), base),
		"le colon construit doit porter cette valeur initiale, jamais 0.0")
	v.v(Banc.magnitude_anticipation(jeune, _config) > 0.0,
		"son debit d'anticipation POTENTIEL est non nul : il est sur la meme echelle que le vieux")
	v.v(Banc.magnitude_anticipation(jeune, _config) < Banc.magnitude_anticipation(vieux, _config) * 0.5,
		"mais bien plus petit que celui du vieux -- « un vieux anticipe beaucoup plus » vit dans ce debit")

	# Et le nombre de saisons qui le separe du seuil est plus court d'autant.
	var sans_base: Dictionary = (_config.colons[0] as Dictionary).duplicate(true)
	sans_base["cycles_vecus"] = 0.0
	var nu := Banc.construire_colon(sans_base, _config)
	v.v(float(jeune.proprietes.cycles_vecus) > float(nu.proprietes.cycles_vecus),
		"un colon a base innee doit partir strictement plus haut qu'un colon parti de zero")

# CLAUDE.md, regle non negociable : « aucun hasard non-seede » -- et le depot
# n'a AUCUN RNG. Deux scenes identiques avancees a l'identique doivent finir
# exactement au meme etat, au bit pres.
func _le_pas_complet_est_deterministe(v) -> void:
	var a := _scene()
	var b := _scene()
	var bilan_a := _boucle(a, 0.0, 400, 0.1)
	var bilan_b := _boucle(b, 0.0, 400, 0.1)
	for i in range(bilan_a.colons.size()):
		var ea: Dictionary = bilan_a.colons[i]
		var eb: Dictionary = bilan_b.colons[i]
		v.v(ea.cycles_vecus == eb.cycles_vecus, "meme compte de cycles a l'identique")
		v.v(ea.biais == eb.biais, "meme biais a l'identique")
		v.v(ea.saillance_grenier == eb.saillance_grenier, "meme saillance a l'identique")
		v.v(String(ea.souvenirs[String(_config.reperes[1].id)].cle) ==
			String(eb.souvenirs[String(_config.reperes[1].id)].cle),
			"meme cle de perception du temps a l'identique")
	v.v(bilan_a.saison == bilan_b.saison, "meme saison a l'identique")
