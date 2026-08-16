extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_social_rupture.gd
#
# Verrouille scripts/banc_social_rupture.gd (chantier « rupture + migration »,
# tableau Social et relations, lignes 8, 12 et 13). Les MECANISMES composes sont
# verrouilles hors domaine par leurs propres tests (test_charge.gd,
# test_seuil_etat.gd, test_bifurcation.gd, test_etat_duree.gd,
# test_etat_effectif.gd, test_conditions.gd, test_consommer.gd,
# test_lien_personnel.gd) -- ce fichier-ci ne teste que le CABLAGE.
#
# Couvre les onze issues demandees : le deuil est pose a la mort du proche ; il
# reduit le rythme effectif ; il accumule du grief ; le grief atteint le
# quatrieme palier et le colon devient traitre ; le traitre detourne la reserve
# commune ; poids_cupidite fait GAGNER la sortie trahison (contre-epreuve a
# cupidite neutre) ; loyaute basse + attractivite haute font migrer ; loyaute
# haute bloque la migration a attractivite IDENTIQUE ; le colon migre change
# reellement de colonie ; scripts/banc_grief.gd n'est pas touche (sa donnee
# porte toujours TROIS sorties, son .gd ignore tout de la quatrieme) ; aucun
# mecanisme du coeur ne porte un nom de ce chantier.
#
# CE QUE CE TEST NE PEUT PAS PROUVER, dit plutot que masque : qu'aucun fichier
# du coeur n'a ete MODIFIE. Un test lit le disque, il ne connait pas l'historique
# -- c'est `git status` qui le dit. Ce qu'il verifie a la place est plus fort
# dans un sens et plus faible dans l'autre : qu'aucun mecanisme du coeur ne
# NOMME une chose de ce chantier (doctrine « le moteur ne connait que des
# verbes », CLAUDE.md).
#
# Plus sept verrous que la consigne ne demandait pas et que le banc exige : la
# bifurcation ne se rejoue PAS tant que l'ensemble des sorties ouvertes ne
# change pas ; elle se rejoue quand il grandit (sans quoi la quatrieme sortie
# serait inatteignable) ; le grief redescend et retire les deux marqueurs quand
# toutes les causes cessent ; une cause encore active bloque cette decrue ; le
# deuil s'estompe SEUL et son integrale reste sous le palier de trahison ; le
# gate de migration est REVERSIBLE en cours de route ; et l'accord entre
# data/banc_social_rupture.json (180 jours x 0.1 s) et data/etats.json:en_deuil
# ('duree' 18.0), que rien d'autre ne tient.
#
# Le dernier cas fait traverser le MEME code par un domaine ENTIEREMENT INVENTE
# (suffixe "_krev", aucun nom du jeu, catalogues d'etats et de seuils inventes
# eux aussi) : c'est ce qui prouve qu'aucun nom de propriete n'est ecrit en dur
# dans le .gd.

const Banc = preload("res://scripts/banc_social_rupture.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA := 0.05

func _init() -> void:
	var v := Verif.new()
	_le_deuil_est_pose_a_la_mort_du_proche(v)
	_le_deuil_reduit_le_rythme_effectif(v)
	_le_deuil_accumule_du_grief(v)
	_le_deuil_s_estompe_seul_et_ne_fait_pas_un_traitre(v)
	_le_quatrieme_palier_fait_un_traitre(v)
	_le_traitre_detourne_la_reserve_commune(v)
	_la_cupidite_fait_gagner_la_trahison(v)
	_la_bifurcation_ne_se_rejoue_que_si_l_ensemble_change(v)
	_le_grief_redescend_quand_les_causes_cessent(v)
	_loyaute_basse_et_attractivite_haute_font_migrer(v)
	_la_loyaute_haute_bloque_la_migration(v)
	_le_gate_de_migration_est_reversible(v)
	_l_accord_avec_les_catalogues_partages(v)
	_banc_grief_n_est_pas_touche(v)
	_aucun_mecanisme_du_coeur_ne_nomme_ce_chantier(v)
	_aucun_nom_de_propriete_en_dur(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_social_rupture -- deuil pose par ABSENCE du proche dans le Monde, " +
			"intensite qui s'estompe seule et penalite de rythme proportionnelle, " +
			"grief accumule par charge.gd sur causes synthetisees a portee 0.0, " +
			"deux paliers lus par objet (rupture puis trahison), bifurcation a quatre " +
			"sorties rejouee EXACTEMENT quand l'ensemble ouvert change, poids_cupidite " +
			"decisif, detournement conservatif par consommer.gd, gate combine reversible " +
			"par conditions.gd, migration effective, banc_grief intact, aucun nom de ce " +
			"chantier dans le coeur, aucun nom de propriete en dur")
		quit(0)

# ---- outils ----

func _config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_social_rupture.json"))

func _etats() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))

func _seuils() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json"))

# Monte la scene entiere depuis la donnee, exactement comme _ready le fait.
func _scene(config: Dictionary) -> Dictionary:
	var colons: Array = []
	for decl in config.colons:
		colons.append(Banc.construire_colon(decl, config))
	var depots: Dictionary = {}
	for nom_colonie in config.colonies:
		depots[String(nom_colonie)] = Banc.construire_depot(String(nom_colonie), config)
	var compagnon := Banc.construire_compagnon(config)
	return {
		"colons": colons,
		"depots": depots,
		"compagnon": compagnon,
		"monde": Banc.construire_monde(colons, depots.values(), compagnon, Monde),
		"resumes": Banc.resumes_initiaux(config),
	}

# LA MORT : le compagnon quitte le Monde, rien d'autre. monde.gd n'a aucune
# fonction de retrait -- le Monde est reconstruit du neant, colons et depots
# re-ajoutes PAR REFERENCE (leur etat interne est integralement preserve).
func _tuer_compagnon(scene: Dictionary) -> void:
	scene["monde"] = Banc.construire_monde(scene.colons, scene.depots.values(), null, Monde)

func _tourner(scene: Dictionary, injustice: bool, secondes: float,
		config: Dictionary, etats: Dictionary, seuils: Dictionary) -> Dictionary:
	var bascules: Array = []
	var deuils: Array = []
	var migrations: Array = []
	var restant := secondes
	while restant > 0.0:
		var bilan := Banc.avancer(scene.colons, scene.depots, scene.monde, scene.resumes,
			injustice, config, etats, seuils, DELTA)
		bascules.append_array(bilan.bascules)
		deuils.append_array(bilan.deuils)
		migrations.append_array(bilan.migrations)
		scene["dernier"] = bilan
		restant -= DELTA
	return {"bascules": bascules, "deuils": deuils, "migrations": migrations}

func _colon(scene: Dictionary, id: String):
	for colon in scene.colons:
		if String(colon.id) == id:
			return colon
	return null

func _grief(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get(String(config.nom_grief), 0.0))

# ---- les onze issues demandees ----

func _le_deuil_est_pose_a_la_mort_du_proche(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()
	var scene := _scene(config)
	var endeuille = _colon(scene, "colon_endeuille")
	var chef = _colon(scene, "chef_nord")
	_tourner(scene, false, 0.5, config, etats, seuils)
	v.v(not endeuille.proprietes.etats_actifs.has(String(config.etat_deuil)),
		"pre-condition : tant que le compagnon est dans le Monde, personne n'est en deuil")

	_tuer_compagnon(scene)
	var trace := _tourner(scene, false, 0.2, config, etats, seuils)
	v.v(endeuille.proprietes.etats_actifs.has(String(config.etat_deuil)),
		"le colon qui portait un lien fort vers le compagnon doit entrer en deuil des son ABSENCE du Monde")
	v.v(trace.deuils.size() == 1,
		"un seul deuil doit etre pose, et une seule fois -- jamais repose a chaque tick (obtenu %d)" % trace.deuils.size())
	# LE SEUIL DE PROCHE EST UNE FORCE DE LIEN, jamais une appartenance : le chef
	# est de la meme colonie et connaissait le compagnon (lien 0.2), il ne porte
	# pas son deuil.
	v.v(not chef.proprietes.etats_actifs.has(String(config.etat_deuil)),
		"un lien sous 'seuil_proche' ne doit poser aucun deuil -- c'est la force du lien qui decide, pas la colonie")

func _le_deuil_reduit_le_rythme_effectif(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()
	var scene := _scene(config)
	var endeuille = _colon(scene, "colon_endeuille")
	var nu := Banc.rythme_effectif(endeuille, config, etats)
	v.v(abs(nu - float(config.rythme_base)) < 0.001,
		"sans etat, le rythme effectif doit valoir exactement la base")

	_tuer_compagnon(scene)
	_tourner(scene, false, 0.2, config, etats, seuils)
	var apres := Banc.rythme_effectif(endeuille, config, etats)
	# 0.7 = 1 - penalite_efficacite 0.3, a intensite pleine. Quelques ticks se
	# sont ecoules : l'intensite a deja un peu baisse, donc le rythme est
	# legerement AU-DESSUS de base x 0.7 -- c'est exactement ce que
	# EtatDuree.etats_ponderes produit, et c'est le sujet du cas suivant.
	v.v(apres < nu, "le deuil doit REDUIRE le rythme effectif")
	v.v(abs(apres - nu * 0.7) < 0.02,
		"la penalite doit valoir base x (1 - 0.3) a intensite pleine (obtenu %.4f pour %.4f attendu)" % [apres, nu * 0.7])
	# PIEGE DU CONSTAT (D) : sans la composition explicite du cablage, l'effet
	# declare dans data/etats.json ne produirait RIEN. La valeur BRUTE, elle, n'a
	# pas bouge d'un chiffre.
	v.v(abs(float(endeuille.proprietes[String(config.nom_rythme)]) - float(config.rythme_base)) < 0.001,
		"la valeur BRUTE de 'rythme' ne doit jamais etre ecrite par un etat -- seule la lecture composee change")

func _le_deuil_accumule_du_grief(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()
	var scene := _scene(config)
	var endeuille = _colon(scene, "colon_endeuille")
	# INJUSTICE LEVEE : la SEULE cause possible est le deuil. Sans cette
	# precaution, « le deuil accumule du grief » serait vrai a cause de
	# l'injustice, et le cas ne prouverait rien.
	_tourner(scene, false, 1.0, config, etats, seuils)
	v.v(_grief(endeuille, config) == 0.0,
		"pre-condition : sans aucune cause, le grief doit rester a zero")
	_tuer_compagnon(scene)
	_tourner(scene, false, 1.0, config, etats, seuils)
	var apres := _grief(endeuille, config)
	v.v(apres > 0.0, "le deuil doit faire MONTER le grief")
	# Le poids declare, module par l'intensite qui a deja commence a descendre :
	# la montee est donc un peu SOUS le poids nominal, jamais au-dessus.
	var poids := _poids_cause(config, "deuil")
	v.v(apres <= poids * 1.0 + 0.001 and apres > poids * 0.9,
		"la montee doit valoir le poids de la cause 'deuil' (%.1f/s) module par l'intensite (obtenu %.2f)" % [poids, apres])

func _le_deuil_s_estompe_seul_et_ne_fait_pas_un_traitre(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()
	var scene := _scene(config)
	var endeuille = _colon(scene, "colon_endeuille")
	_tuer_compagnon(scene)
	var duree: float = float(etats[String(config.etat_deuil)].duree)
	_tourner(scene, false, duree / 2.0, config, etats, seuils)
	var pendant := Banc.rythme_effectif(endeuille, config, etats)
	_tourner(scene, false, duree / 2.0 + 1.0, config, etats, seuils)
	v.v(not endeuille.proprietes.etats_actifs.has(String(config.etat_deuil)),
		"le deuil doit s'estomper SEUL au bout de sa duree -- aucun cablage ne le retire")
	v.v(not endeuille.proprietes.get("etats_intensite", {}).has(String(config.etat_deuil)),
		"etat_duree.gd doit aussi retirer son intensite -- sans quoi il alarmerait a chaque tick suivant")
	v.v(Banc.rythme_effectif(endeuille, config, etats) > pendant,
		"le rythme effectif doit REMONTER quand le deuil s'eteint")
	v.v(Banc.deuil_restant(endeuille, config, etats) == 0.0,
		"il ne doit plus rester une seconde de deuil")
	# CE QUE LE DEUIL LAISSE DERRIERE LUI, constate a l'ecriture et garde comme
	# verrou plutot que contourne : son grief a franchi le PREMIER palier au
	# passage, donc une sortie est posee et module encore le rythme. Le rythme ne
	# revient DONC PAS a la base -- il revient a ce que la sortie en fait. C'est
	# le chainage des trois lignes du chantier, pas un defaut.
	v.v(Banc.sortie_active(endeuille, config) != "",
		"le grief accumule par le seul deuil doit avoir franchi le premier palier")
	# L'integrale d'une cause qui decroit lineairement de p a 0 sur d secondes
	# vaut p x d / 2 = 45.0, SOUS le palier de trahison (60.0) : un deuil seul ne
	# fait jamais un traitre, quel que soit le temps qu'on attend.
	v.v(not endeuille.proprietes.etats_actifs.has(String(config.etat_tentation)),
		"un deuil SEUL ne doit jamais suffire a franchir le palier de trahison")

func _le_quatrieme_palier_fait_un_traitre(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()
	var scene := _scene(config)
	var cupide = _colon(scene, "colon_cupide")
	var trace := _tourner(scene, true, 12.0, config, etats, seuils)
	v.v(cupide.proprietes.etats_actifs.has(String(config.etat_rupture)),
		"pre-condition : le premier palier doit etre franchi")
	v.v(cupide.proprietes.etats_actifs.has(String(config.etat_tentation)),
		"le second palier doit etre franchi -- les DEUX marqueurs restent actifs ensemble")
	v.v(Banc.sortie_active(cupide, config) == String(config.sortie_detournement),
		"au quatrieme palier, le colon le plus cupide doit devenir traitre (obtenu '%s')" % Banc.sortie_active(cupide, config))
	# L'ESCALADE EN DEUX TEMPS est le sujet de la ligne 12 : il conteste d'abord,
	# il ne trahit qu'apres le second palier.
	var sorties: Array = []
	for bascule in trace.bascules:
		if String(bascule.id) == "colon_cupide" and String(bascule.sens) == "pose":
			sorties.append(String(bascule.sortie))
	v.v(sorties.size() == 2 and sorties[1] == String(config.sortie_detournement),
		"le cupide doit passer par une PREMIERE sortie avant la trahison (obtenu %s)" % [sorties])

func _le_traitre_detourne_la_reserve_commune(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()
	var scene := _scene(config)
	var cupide = _colon(scene, "colon_cupide")
	_tourner(scene, true, 8.0, config, etats, seuils)
	v.v(Banc.sortie_active(cupide, config) == String(config.sortie_detournement),
		"pre-condition : le cupide doit avoir trahi")
	var commun_avant := Banc.reserve_commune(scene.depots, "nord", config)
	var butin_avant := Banc.butin(cupide, config)
	var sud_avant := Banc.reserve_commune(scene.depots, "sud", config)
	_tourner(scene, true, 2.0, config, etats, seuils)
	var butin_apres := Banc.butin(cupide, config)
	v.v(butin_apres > butin_avant, "le traitre doit remplir sa propre reserve")
	# L'AUTRE COLONIE NE PERD RIEN : sa reserve monte de SA SEULE production, au
	# centime pres -- on ne vole que chez soi. Comparer a « n'a pas bouge » serait
	# faux : ses deux colons travaillent pendant ce temps.
	v.v(abs((Banc.reserve_commune(scene.depots, "sud", config) - sud_avant)
			- _production(scene, config, "sud", 2.0)) < 0.5,
		"la reserve de l'AUTRE colonie ne doit varier que de sa propre production -- on ne vole que chez soi")
	# CONSERVATIF PAR CONSTRUCTION (consommer.gd) : la production des deux autres
	# colons monte pendant ce temps, mais ce qui a QUITTE la reserve commune est
	# exactement ce qui est ENTRE dans la poche du traitre.
	var commun_apres := Banc.reserve_commune(scene.depots, "nord", config)
	var production := _production(scene, config, "nord", 2.0)
	v.v(abs((commun_apres - commun_avant) - (production - (butin_apres - butin_avant))) < 0.5,
		"ce qui quitte la reserve commune doit valoir exactement ce qui entre dans la poche du traitre, production deduite")

func _la_cupidite_fait_gagner_la_trahison(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()

	# CONTRE-EPREUVE : le MEME colon, la MEME scene, le MEME grief -- seule la
	# cupidite change. C'est litteralement « Les archetypes n'existent pas ».
	var scene_neutre := _scene(config)
	var neutre = _colon(scene_neutre, "colon_cupide")
	neutre.proprietes[String(config.nom_cupidite)] = 1.0
	_tourner(scene_neutre, true, 12.0, config, etats, seuils)
	v.v(neutre.proprietes.etats_actifs.has(String(config.etat_tentation)),
		"pre-condition : a cupidite neutre, le second palier doit etre franchi quand meme")
	v.v(Banc.sortie_active(neutre, config) != String(config.sortie_detournement),
		"a cupidite 1.0, la trahison ne doit PAS gagner (obtenu '%s')" % Banc.sortie_active(neutre, config))

	var scene := _scene(config)
	var cupide = _colon(scene, "colon_cupide")
	_tourner(scene, true, 12.0, config, etats, seuils)
	v.v(Banc.sortie_active(cupide, config) == String(config.sortie_detournement),
		"a la cupidite declaree, la trahison doit gagner -- le multiplicateur est DECISIF")

	# Le biais compose est un Dictionary NEUF : le biais du colon n'est jamais mute.
	var biais: Dictionary = Banc.biais_effectif(cupide, config)
	var brut: Dictionary = cupide.proprietes.biais_grief
	v.v(abs(float(biais[String(config.sortie_detournement)])
			- float(brut[String(config.sortie_detournement)]) * float(cupide.proprietes[String(config.nom_cupidite)])) < 0.0001,
		"le biais de trahison doit valoir biais x poids_cupidite")
	v.v(float(brut[String(config.sortie_detournement)]) == 0.15,
		"le biais BRUT du colon ne doit jamais avoir ete mute par la composition")

func _la_bifurcation_ne_se_rejoue_que_si_l_ensemble_change(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()
	var scene := _scene(config)
	var chef = _colon(scene, "chef_nord")
	var trace := _tourner(scene, true, 20.0, config, etats, seuils)
	var poses := 0
	for bascule in trace.bascules:
		if String(bascule.id) == "chef_nord" and String(bascule.sens) == "pose":
			poses += 1
	# Le chef franchit LES DEUX paliers, donc l'ensemble ouvert change une fois --
	# mais son biais donne la MEME sortie avant et apres : rien ne doit etre
	# repose, et surtout rien ne doit s'empiler dans etats_actifs.
	v.v(poses == 1,
		"une sortie inchangee ne doit jamais etre reposee, meme quand l'ensemble ouvert grandit (obtenu %d)" % poses)
	var compte := 0
	for etat in chef.proprietes.etats_actifs:
		if String(etat) == String(config.etats_par_sortie[Banc.sortie_active(chef, config)]):
			compte += 1
	v.v(compte == 1, "l'etat de sortie ne doit JAMAIS s'empiler dans etats_actifs")
	v.v(Banc.sorties_ouvertes(chef, config).size() == config.sorties.size(),
		"les deux paliers franchis doivent ouvrir LES QUATRE sorties")

func _le_grief_redescend_quand_les_causes_cessent(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()
	var scene := _scene(config)
	var chef = _colon(scene, "chef_nord")
	var cupide = _colon(scene, "colon_cupide")
	_tourner(scene, true, 8.0, config, etats, seuils)
	v.v(Banc.sortie_active(chef, config) != "", "pre-condition : le chef doit avoir rompu")
	var haut := _grief(chef, config)
	# Une seconde de marge au-dela du strict necessaire (48.0 de grief a 8.0/s) :
	# la borne a zero de charge.gd est un max(0.0, ...), pas une egalite exacte a
	# la seconde pres -- un test cale au pixel dependrait de l'arrondi flottant.
	_tourner(scene, false, 7.0, config, etats, seuils)
	v.v(_grief(chef, config) < haut, "l'injustice levee, le grief doit REDESCENDRE")
	v.v(_grief(chef, config) == 0.0, "et il doit etre borne a zero par charge.gd")
	v.v(not chef.proprietes.etats_actifs.has(String(config.etat_rupture)),
		"seuil_etat.gd doit RETIRER le marqueur au franchissement descendant")
	v.v(Banc.sortie_active(chef, config) == "",
		"la sortie doit etre retiree quand le grief redescend (reversibilite)")
	# CONSTAT G DE charge.gd, assume : une cause encore active bloque TOUTE
	# decrue. Le cupide subit une agression permanente, l'amelioration ne le
	# sauve pas.
	v.v(_grief(cupide, config) > float(config.seuil_trahison),
		"un colon qui garde une cause active ne doit JAMAIS voir son grief redescendre")

func _loyaute_basse_et_attractivite_haute_font_migrer(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()
	var scene := _scene(config)
	var endeuille = _colon(scene, "colon_endeuille")
	var depart: Vector3 = endeuille.position
	var trace := _tourner(scene, false, 15.0, config, etats, seuils)
	v.v(float(endeuille.proprietes[String(config.nom_loyaute)]) < 0.45,
		"pre-condition : sa loyaute doit etre sous le seuil du gate")
	v.v(float(endeuille.proprietes[String(config.nom_attractivite)]) > 0.50
		or String(endeuille.proprietes[String(config.nom_colonie)]) != "nord",
		"pre-condition : l'attractivite de l'autre colonie doit avoir depasse le seuil")
	v.v(endeuille.position != depart, "un colon qui migre doit se DEPLACER")
	v.v(trace.migrations.size() == 1,
		"la migration doit se produire une fois, a l'arrivee (obtenu %d)" % trace.migrations.size())
	v.v(String(endeuille.proprietes[String(config.nom_colonie)]) == "sud",
		"le colon migre doit CHANGER de colonie")
	v.v(float(endeuille.proprietes[String(config.nom_vecu_cumule)]) < 1.0,
		"le vecu doit repartir de zero a l'arrivee -- ce qu'on a vecu ailleurs ne compte pas ici")
	# Une fois arrive, il produit pour SA nouvelle colonie et plus pour l'ancienne.
	var avant := Banc.reserve_commune(scene.depots, "sud", config)
	_tourner(scene, false, 1.0, config, etats, seuils)
	v.v(Banc.reserve_commune(scene.depots, "sud", config) > avant,
		"le colon migre doit desormais produire pour sa nouvelle colonie")

func _la_loyaute_haute_bloque_la_migration(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()
	var scene := _scene(config)
	var cupide = _colon(scene, "colon_cupide")
	var endeuille = _colon(scene, "colon_endeuille")
	var depart: Vector3 = cupide.position
	_tourner(scene, false, 3.0, config, etats, seuils)
	# LA DEMONSTRATION : les deux colons portent la MEME ouverture, lisent donc
	# EXACTEMENT le meme resume, et l'un part quand l'autre reste. Seule la
	# loyaute les separe.
	v.v(abs(float(cupide.proprietes[String(config.nom_attractivite)])
			- float(endeuille.proprietes[String(config.nom_attractivite)])) < 0.0001,
		"pre-condition : les deux colons doivent lire la MEME attractivite")
	v.v(float(cupide.proprietes[String(config.nom_attractivite)]) > 0.50,
		"pre-condition : cette attractivite doit etre au-dessus du seuil du gate")
	v.v(float(cupide.proprietes[String(config.nom_loyaute)]) >= 0.45,
		"pre-condition : la loyaute du cupide doit etre au-dessus du seuil")
	v.v(float(cupide.proprietes.get(String(config.nom_veut_migrer), 0.0)) == 0.0,
		"une loyaute haute doit BLOQUER la migration, meme a attractivite haute")
	v.v(cupide.position == depart, "un colon qui ne migre pas ne doit pas bouger d'un pixel")

func _le_gate_de_migration_est_reversible(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()
	var scene := _scene(config)
	var endeuille = _colon(scene, "colon_endeuille")
	_tourner(scene, false, 3.0, config, etats, seuils)
	v.v(float(endeuille.proprietes.get(String(config.nom_veut_migrer), 0.0)) > 0.0,
		"pre-condition : il doit etre en route")
	var en_route: Vector3 = endeuille.position
	# L'attractivite du sud retombe SOUS le seuil : conditions.gd retire le
	# drapeau (retirer_si_faux), et le colon s'arrete EN COURS DE ROUTE.
	scene.resumes["sud"] = 0.30
	_tourner(scene, false, 2.0, config, etats, seuils)
	v.v(float(endeuille.proprietes.get(String(config.nom_veut_migrer), 0.0)) == 0.0,
		"le gate doit se DEFAIRE quand l'attractivite retombe -- conditions.gd, retirer_si_faux")
	v.v(endeuille.position == en_route, "un colon dont le gate s'est referme doit s'arreter net")
	v.v(String(endeuille.proprietes[String(config.nom_colonie)]) == "nord",
		"il ne doit pas avoir change de colonie en route")

func _l_accord_avec_les_catalogues_partages(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()

	# LE COUPLAGE QUE RIEN D'AUTRE NE TIENT : le banc nomme sa grandeur et ses
	# deux paliers en donnee, mais c'est data/seuils_etat.json qui dit QUELLE
	# propriete seuil_etat.gd compare. Renommer l'un sans l'autre ne casse RIEN
	# visiblement -- l'entree devient un chemin mort et plus personne ne rompt.
	for couple in [[String(config.etat_rupture), String(config.nom_seuil_rupture)],
			[String(config.etat_tentation), String(config.nom_seuil_trahison)]]:
		var entree: Dictionary = seuils.get(couple[0], {})
		v.v(not entree.is_empty(),
			"data/seuils_etat.json doit porter une entree nommee '%s'" % couple[0])
		v.v(String(entree.get("propriete_continue", "")) == String(config.nom_grief),
			"l'entree '%s' doit comparer exactement la propriete que le banc ecrit" % couple[0])
		v.v(String(entree.get("seuil_propriete", "")) == couple[1],
			"l'entree '%s' doit lire son seuil PAR OBJET sur '%s'" % [couple[0], couple[1]])
		v.v(String(entree.get("etat", "")) == couple[0],
			"l'etat pose par l'entree '%s' doit etre le marqueur que le cablage attend" % couple[0])
	v.v(float(config.seuil_trahison) > float(config.seuil_rupture),
		"le palier de trahison doit etre STRICTEMENT au-dessus du palier de rupture")

	# LES 180 JOURS ET LES 18 SECONDES : le depot n'a aucune horloge de jour, le
	# produit vit donc en donnee de banc et la duree en catalogue partage. Rien
	# d'autre que ce verrou n'empeche les deux de diverger.
	v.v(abs(float(config.duree_deuil_j) * float(config.secondes_par_jour)
			- float(etats[String(config.etat_deuil)].duree)) < 0.0001,
		"duree_deuil_j x secondes_par_jour doit valoir exactement data/etats.json:%s.duree" % config.etat_deuil)

	# Les quatre etats de sortie, les deux marqueurs et le deuil vivent tous dans
	# etats_actifs : etat_effectif.gd alarme sur tout nom actif absent de son
	# catalogue, a chaque lecture de rythme, donc a chaque image.
	for nom in [String(config.etat_rupture), String(config.etat_tentation), String(config.etat_deuil)]:
		v.v(etats.has(nom), "l'etat '%s' doit exister dans data/etats.json" % nom)
	for sortie in config.sorties:
		v.v(etats.has(String(config.etats_par_sortie[String(sortie)])),
			"l'etat de la sortie '%s' doit exister dans data/etats.json" % sortie)
		v.v(config.marqueur_par_sortie.has(String(sortie)),
			"la sortie '%s' doit declarer le marqueur qui l'ouvre" % sortie)

func _banc_grief_n_est_pas_touche(v) -> void:
	# LA QUATRIEME SORTIE VIT DANS UNE DONNEE, PAS DANS UN .gd. Le banc precedent
	# garde ses TROIS sorties et son .gd ignore tout de la quatrieme : la preuve
	# se lit sur le disque, pas dans un souvenir de session.
	var grief: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_grief.json"))
	v.v(grief.sorties.size() == 3,
		"data/banc_grief.json doit garder ses TROIS sorties (obtenu %d)" % grief.sorties.size())
	var source: String = FileAccess.get_file_as_string("res://scripts/banc_grief.gd")
	var config := _config()
	for mot in [String(config.sortie_detournement), String(config.etats_par_sortie[String(config.sortie_detournement)]),
			String(config.etat_tentation), String(config.etat_deuil)]:
		v.v(not source.contains(mot),
			"scripts/banc_grief.gd ne doit contenir aucune trace de '%s'" % mot)

func _aucun_mecanisme_du_coeur_ne_nomme_ce_chantier(v) -> void:
	# Ce que ce cas prouve, et ce qu'il ne prouve pas : voir l'en-tete. Il ne lit
	# pas l'historique -- il verifie la DOCTRINE (« le moteur ne connait que des
	# verbes ») sur les huit mecanismes que ce banc compose.
	var config := _config()
	var mots: Array = [
		String(config.sortie_detournement),
		String(config.etats_par_sortie[String(config.sortie_detournement)]),
		String(config.etat_tentation),
		String(config.etat_deuil),
		String(config.nom_loyaute),
		String(config.nom_colonie),
		String(config.nom_cupidite),
	]
	for fichier in ["charge", "bifurcation", "seuil_etat", "etat_duree", "etat_effectif",
			"depense", "lien_personnel", "conditions", "consommer", "dominance", "agir",
			"deformation", "perception"]:
		var source: String = FileAccess.get_file_as_string("res://scripts/%s.gd" % fichier)
		v.v(source != "", "scripts/%s.gd doit exister et etre lisible" % fichier)
		for mot in mots:
			v.v(not source.contains(mot),
				"scripts/%s.gd ne doit nommer aucune chose de ce chantier ('%s')" % [fichier, mot])

# Ce qu'une colonie a produit pendant `secondes`, extrapole depuis le DERNIER
# tick joue -- exact tant qu'aucun etat n'a change de rythme dans l'intervalle,
# ce que les cas appelants garantissent en choisissant leur fenetre.
func _production(scene: Dictionary, config: Dictionary, colonie: String, secondes: float) -> float:
	var total := 0.0
	for colon in scene.colons:
		if String(colon.proprietes[String(config.nom_colonie)]) != colonie:
			continue
		total += float(scene.dernier.infos[colon.id].produit) / DELTA * secondes
	return total

func _poids_cause(config: Dictionary, nom: String) -> float:
	for cause in config.causes_grief:
		if String(cause.nom) == nom:
			return float(cause.poids)
	return 0.0

func _aucun_nom_de_propriete_en_dur(v) -> void:
	# DOMAINE ENTIEREMENT INVENTE : si le meme code marche ici, c'est qu'aucun nom
	# du jeu n'est ecrit dedans. Les catalogues d'etats ET de seuils sont eux
	# aussi INVENTES et passes en parametre -- sans quoi le catalogue PARTAGE,
	# dont l'entree compare 'grief', ferait passer le test pour de mauvaises
	# raisons (lecon de test_banc_grief.gd).
	var config := {
		"nom_grief": "rancune_krev",
		"canal_grief": "rancune_krev",
		"nom_seuil_rupture": "pallier_un_krev",
		"nom_seuil_trahison": "pallier_deux_krev",
		"etat_rupture": "bascule_krev",
		"etat_tentation": "bascule_haute_krev",
		"etat_deuil": "manque_krev",
		"nom_rythme": "cadence_krev",
		"nom_loyaute": "attache_krev",
		"nom_poids_loyaute": "poids_attache_krev",
		"nom_attractivite": "ailleurs_krev",
		"nom_ouverture": "gout_ailleurs_krev",
		"nom_colonie": "clan_krev",
		"nom_chef": "meneur_krev",
		"nom_cupidite": "avidite_krev",
		"nom_veut_migrer": "s_en_va_krev",
		"nom_vecu_cumule": "anciennete_krev",
		"source_lien_colonie": "proches_krev",
		"source_adhesions_partagees": "accord_krev",
		"source_vecu": "racines_krev",
		"nom_adhesions": "credos_krev",
		"nom_injustice": "brimade_krev",
		"nom_deuil_ressenti": "peine_krev",
		"nom_deuils_faits": "pleures_krev",
		"nom_sorties_ouvertes": "portes_krev",
		"nom_reserve_commune": "tas_krev",
		"nom_reserve_butin": "poche_krev",
		"colonie_principale": "flim_krev",
		"seuil_rupture": 10.0,
		"seuil_trahison": 20.0,
		"taux_decroissance_grief": 40.0,
		"rythme_base": 2.0,
		"causes_grief": [
			{"nom": "brimade", "propriete": "brimade_krev", "poids": 20.0},
			{"nom": "peine", "propriete": "peine_krev", "poids": 10.0},
		],
		"sorties": ["plie_krev", "vole_krev"],
		"etats_par_sortie": {"plie_krev": "courbe_krev", "vole_krev": "larron_krev"},
		"marqueur_par_sortie": {"plie_krev": "bascule_krev", "vole_krev": "bascule_haute_krev"},
		"sortie_detournement": "vole_krev",
		"sortie_sans_production": "plie_krev",
		"taux_detournement_par_s": 5.0,
		"plafond_lien": 1.0,
		"plafond_vecu": 1.0,
		"vecu_par_s": 0.0,
		"seuil_proche": 0.5,
		"gate_migration": [{
			"id": "fuite_krev",
			"conditions": [
				{"propriete": "attache_krev", "operateur": "<", "seuil": 0.4},
				{"propriete": "ailleurs_krev", "operateur": ">", "seuil": 0.5},
			],
			"resultat": {"s_en_va_krev": 1.0},
		}],
		"vitesse_migration": 200.0,
		"rayon_arrivee": 20.0,
		"colonies": {
			"flim_krev": {"position": [0.0, 0.0, 0.0], "resume_attractivite": 0.0,
				"depot": {"id": "tas_flim_krev", "position": [0.0, 50.0, 0.0], "reserve": 100.0}},
			"glop_krev": {"position": [300.0, 0.0, 0.0], "resume_attractivite": 1.0,
				"depot": {"id": "tas_glop_krev", "position": [300.0, 50.0, 0.0], "reserve": 100.0}},
		},
		"compagnon": {"id": "ombre_krev", "position": [100.0, 0.0, 0.0]},
		"colons": [
			{"id": "zorb_krev", "colonie": "flim_krev", "chef": true, "position": [0.0, 10.0, 0.0],
				"biais_grief": {"plie_krev": 0.8, "vole_krev": 0.1}, "poids_cupidite": 20.0,
				"poids_loyaute": {"proches_krev": 1.0}, "ouverture_ailleurs": 0.1,
				"causes_propres": {}, "liens": {"ombre_krev": 1.0},
				"adhesions": {"sel_krev": true}},
		],
	}
	var etats_krev := {
		"bascule_krev": {"effets": []},
		"bascule_haute_krev": {"effets": []},
		"courbe_krev": {"effets": []},
		"larron_krev": {"effets": []},
		"manque_krev": {"duree": 4.0, "effets": [
			{"propriete": "cadence_krev", "mode": "moduler", "facteur": 0.5}]},
	}
	var seuils_krev := {
		"bascule_krev": {"propriete_continue": "rancune_krev",
			"seuil_propriete": "pallier_un_krev", "etat": "bascule_krev"},
		"bascule_haute_krev": {"propriete_continue": "rancune_krev",
			"seuil_propriete": "pallier_deux_krev", "etat": "bascule_haute_krev"},
	}
	var scene := _scene(config)
	var zorb = _colon(scene, "zorb_krev")
	v.v(zorb.proprietes.has("rancune_krev") and zorb.proprietes.has("pallier_deux_krev"),
		"les noms de proprietes doivent venir de la donnee, jamais du code")

	# Le deuil d'un domaine invente, par la meme absence.
	_tuer_compagnon(scene)
	_tourner(scene, false, 0.2, config, etats_krev, seuils_krev)
	v.v(zorb.proprietes.etats_actifs.has("manque_krev"),
		"un deuil d'un domaine invente doit se poser par la meme loi")
	# 2.0 x 0.5 a intensite pleine ; quelques ticks ont deja passe, donc la valeur
	# est legerement AU-DESSUS -- la tolerance couvre cette decroissance, pas une
	# approximation de la loi.
	v.v(abs(Banc.rythme_effectif(zorb, config, etats_krev) - 2.0 * 0.5) < 0.1,
		"l'effet d'un etat invente doit se composer par la meme loi, sur un catalogue invente")

	# Les deux paliers, puis la quatrieme sortie -- ici la DEUXIEME.
	_tourner(scene, true, 3.0, config, etats_krev, seuils_krev)
	v.v(zorb.proprietes.etats_actifs.has("bascule_haute_krev"),
		"le second palier d'un domaine invente doit se franchir par la meme loi")
	v.v(Banc.sortie_active(zorb, config) == "vole_krev",
		"la sortie du second palier doit gagner par la cupidite inventee (obtenu '%s')" % Banc.sortie_active(zorb, config))
	v.v(Banc.butin(zorb, config) > 0.0,
		"le detournement doit fonctionner sur des noms de reserve entierement inventes")
	# A DEUX sorties (une par palier) comme a quatre : la loi ne les compte pas.
	v.v(config.sorties.size() == 2, "pre-condition : ce domaine n'a que DEUX sorties")
