extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_grief.gd
#
# Verrouille scripts/banc_grief.gd (chantier « grief + bifurcation grief »,
# audit_mecaniques_psycho_sociales_prealable.md lignes 7 et 8). Le MECANISME
# de bifurcation, lui, est verrouille hors domaine par test_bifurcation.gd --
# ce fichier-ci ne teste que le CABLAGE.
#
# Couvre les sept issues demandees : le grief monte avec l'injustice ; il
# descend avec l'amelioration ; il ne descend JAMAIS sous zero ; au seuil
# colon_soumis bifurque vers 'soumission', colon_rebelle vers 'contestation',
# colon_nomade vers 'depart' ; l'amelioration depassant l'injustice fait
# redescendre le grief et RETIRE l'etat (reversibilite via seuil_etat.gd).
#
# Plus six verrous que la consigne ne demandait pas et que le banc exige :
# la bifurcation ne se REJOUE jamais tant que le colon reste au-dessus du seuil
# (sans quoi les etats s'empileraient a chaque image) ; le contestataire ne
# recoit PAS l'entree de directive et les deux autres oui ; les effets declares
# dans data/etats.json sont REELLEMENT composes (piege du constat (D) de
# l'audit : etat_effectif.gd ne s'applique que si quelqu'un l'appelle) ; le
# colon en depart se deplace vers le bord PUIS quitte la liste ; le seuil est
# LU PAR OBJET (un colon sans 'seuil_rupture' ne rompt jamais) ; et le REJEU
# COMPLET de data/banc_grief.json franchit vraiment le seuil -- lecon de
# banc_maladie, dont le seuil d'origine ne franchissait jamais rien pendant que
# son test restait VERT.
#
# Le dernier cas fait traverser le MEME code par un domaine ENTIEREMENT
# INVENTE (suffixe "_zbeu", aucun nom du jeu) : c'est ce qui prouve qu'aucun
# nom de propriete n'est ecrit en dur dans le .gd.

const Banc = preload("res://scripts/banc_grief.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA := 0.05

func _init() -> void:
	var v := Verif.new()
	_le_grief_monte_avec_l_injustice(v)
	_le_grief_descend_avec_l_amelioration(v)
	_le_grief_ne_descend_jamais_sous_zero(v)
	_chaque_colon_bifurque_vers_sa_sortie(v)
	_l_amelioration_retire_l_etat(v)
	_la_bifurcation_ne_se_rejoue_pas(v)
	_le_contestataire_ne_recoit_pas_la_directive(v)
	_les_effets_declares_sont_reellement_composes(v)
	_le_partant_va_au_bord_puis_quitte_la_liste(v)
	_un_colon_sans_seuil_ne_rompt_jamais(v)
	_l_accord_avec_le_catalogue_partage(v)
	_rejeu_complet_de_la_donnee_de_banc(v)
	_aucun_nom_de_propriete_en_dur(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_grief -- grief accumule qui REDESCEND (premier du depot), " +
			"borne a zero, seuil lu par objet, bifurcation a trois sorties selon le biais seul " +
			"(soumission/contestation/depart), non rejouee tant que le seuil reste franchi, " +
			"reversible au franchissement descendant, directive gatee par l'etat contestataire, " +
			"effets vitesse/rythme reellement composes, depart vers le bord puis retrait, " +
			"rejeu complet de data/banc_grief.json, aucun nom de propriete en dur")
		quit(0)

# ---- outils ----

func _config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_grief.json"))

func _etats() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))

func _seuils() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json"))

# Monte la scene entiere depuis la donnee, exactement comme _ready le fait.
func _scene(config: Dictionary) -> Dictionary:
	var colons: Array = []
	var ouvrages: Dictionary = {}
	for decl in config.colons:
		var colon := Banc.construire_colon(decl, config)
		colons.append(colon)
		ouvrages[colon.id] = Banc.construire_ouvrage(decl, config)
	var directive := Banc.construire_directive(config)
	var monde = Banc.construire_monde(colons, ouvrages.values(), directive, Monde)
	return {"colons": colons, "ouvrages": ouvrages, "directive": directive, "monde": monde}

func _tourner(scene: Dictionary, mode: String, secondes: float, config: Dictionary, etats: Dictionary, seuils: Dictionary) -> Array:
	var bascules: Array = []
	var restant := secondes
	while restant > 0.0:
		var bilan := Banc.avancer(scene.colons, scene.ouvrages, scene.directive, mode,
			config, etats, seuils, scene.monde, DELTA)
		bascules.append_array(bilan.bascules)
		restant -= DELTA
	return bascules

func _colon(scene: Dictionary, id: String):
	for colon in scene.colons:
		if colon.id == id:
			return colon
	return null

func _grief(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get(String(config.nom_grief), 0.0))

# ---- les sept issues demandees ----

func _le_grief_monte_avec_l_injustice(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var colon = _colon(scene, "colon_soumis")
	var avant := _grief(colon, config)
	_tourner(scene, Banc.MODE_INJUSTICE, 1.0, config, _etats(), _seuils())
	var apres := _grief(colon, config)
	v.v(apres > avant, "en mode injustice, le grief doit MONTER")
	# Le net exact, jamais un « ca monte » approximatif : gain - perte.
	var net: float = float(config.gain_injustice_par_s) - float(config.perte_base_par_s)
	v.v(abs((apres - avant) - net * 1.0) < 0.05,
		"la montee doit valoir exactement (gain_injustice - perte_base) x duree, soit %.1f/s" % net)

func _le_grief_descend_avec_l_amelioration(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()
	var scene := _scene(config)
	var colon = _colon(scene, "colon_soumis")
	_tourner(scene, Banc.MODE_INJUSTICE, 3.0, config, etats, seuils)
	var haut := _grief(colon, config)
	v.v(haut > 0.0, "pre-condition : le grief doit d'abord etre monte")
	_tourner(scene, Banc.MODE_AMELIORATION, 1.0, config, etats, seuils)
	var bas := _grief(colon, config)
	v.v(bas < haut, "en mode amelioration, le grief doit DESCENDRE")
	var net: float = float(config.perte_amelioration_par_s) - float(config.gain_base_par_s)
	v.v(abs((haut - bas) - net * 1.0) < 0.05,
		"la descente doit valoir exactement (perte_amelioration - gain_base) x duree, soit %.1f/s" % net)

func _le_grief_ne_descend_jamais_sous_zero(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var colon = _colon(scene, "colon_soumis")
	# Amelioration longue en partant de zero : sans la borne, le grief plongerait
	# a -90 et il faudrait ensuite 10 s d'injustice avant que la moindre
	# rancune ne recommence a compter.
	_tourner(scene, Banc.MODE_AMELIORATION, 10.0, config, _etats(), _seuils())
	v.v(_grief(colon, config) == 0.0,
		"le grief doit etre borne a 0.0 par le bas, jamais negatif")

func _chaque_colon_bifurque_vers_sa_sortie(v) -> void:
	var config := _config()
	var scene := _scene(config)
	# Assez longtemps pour franchir le seuil (50 / 7 = 7.15 s), avec de la marge.
	var bascules := _tourner(scene, Banc.MODE_INJUSTICE, 9.0, config, _etats(), _seuils())
	var attendu := {
		"colon_soumis": "soumission",
		"colon_rebelle": "contestation",
		"colon_nomade": "depart",
	}
	for id in attendu:
		var colon = _colon(scene, String(id))
		# colon_nomade a pu quitter la liste : sa bascule reste dans la trace.
		var sortie := ""
		if colon != null:
			sortie = Banc.sortie_active(colon, config)
		for bascule in bascules:
			if String(bascule.id) == String(id) and String(bascule.sens) == "pose":
				sortie = String(bascule.sortie)
		v.v(sortie == String(attendu[id]),
			"au seuil, %s doit bifurquer vers '%s' (obtenu '%s') -- seul biais_grief les distingue" % [id, attendu[id], sortie])
	# LA demonstration : memes conditions, meme seuil, trois destins.
	v.v(bascules.size() >= 3, "les trois colons doivent avoir bifurque")

func _l_amelioration_retire_l_etat(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()
	var scene := _scene(config)
	var colon = _colon(scene, "colon_soumis")
	_tourner(scene, Banc.MODE_INJUSTICE, 9.0, config, etats, seuils)
	v.v(Banc.sortie_active(colon, config) == "soumission",
		"pre-condition : l'etat doit d'abord etre pose")
	v.v(colon.proprietes.etats_actifs.has(String(config.etat_rupture)),
		"pre-condition : le marqueur de rupture doit etre actif")
	# REVERSIBILITE : c'est seuil_etat.gd qui retire le marqueur au
	# franchissement descendant, sans une ligne de cablage ; bifurquer() ne fait
	# qu'en tirer la consequence sur l'etat de sortie.
	_tourner(scene, Banc.MODE_AMELIORATION, 5.0, config, etats, seuils)
	v.v(_grief(colon, config) < float(config.seuil_rupture),
		"le grief doit etre redescendu sous le seuil")
	v.v(not colon.proprietes.etats_actifs.has(String(config.etat_rupture)),
		"seuil_etat.gd doit RETIRER le marqueur au franchissement descendant")
	v.v(Banc.sortie_active(colon, config) == "",
		"l'etat de sortie doit etre retire quand le grief redescend (reversibilite)")
	v.v(not colon.proprietes.etats_actifs.has("soumis"),
		"'soumis' ne doit plus figurer dans etats_actifs apres le retour sous le seuil")

# ---- verrous que le banc exige, non demandes par la consigne ----

func _la_bifurcation_ne_se_rejoue_pas(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var colon = _colon(scene, "colon_soumis")
	var bascules := _tourner(scene, Banc.MODE_INJUSTICE, 15.0, config, _etats(), _seuils())
	var poses := 0
	for bascule in bascules:
		if String(bascule.id) == "colon_soumis" and String(bascule.sens) == "pose":
			poses += 1
	v.v(poses == 1,
		"la bifurcation ne doit se produire QU'UNE FOIS tant que le colon reste au-dessus du seuil (obtenu %d)" % poses)
	var compte := 0
	for etat in colon.proprietes.etats_actifs:
		if String(etat) == "soumis":
			compte += 1
	v.v(compte == 1, "l'etat de sortie ne doit JAMAIS s'empiler dans etats_actifs")

func _le_contestataire_ne_recoit_pas_la_directive(v) -> void:
	var config := _config()
	var scene := _scene(config)
	var neutre = _colon(scene, "colon_rebelle")
	v.v(Banc.entree_directive(neutre, scene.directive, config) != null,
		"pre-condition : un colon sans etat vital doit recevoir l'entree de directive")
	_tourner(scene, Banc.MODE_INJUSTICE, 9.0, config, _etats(), _seuils())
	v.v(Banc.sortie_active(neutre, config) == "contestation",
		"pre-condition : le rebelle doit etre devenu contestataire")
	v.v(Banc.entree_directive(neutre, scene.directive, config) == null,
		"un colon contestataire ne doit PAS recevoir l'entree de directive -- le joueur perd le controle")
	v.v(not Banc.directive_autorisee(neutre, config),
		"directive_autorisee doit rendre false sur un contestataire")
	# Les autres, eux, la recoivent encore : le gate vise l'etat, jamais le banc.
	var soumis = _colon(scene, "colon_soumis")
	v.v(Banc.entree_directive(soumis, scene.directive, config) != null,
		"un colon soumis doit continuer de recevoir la directive -- il obeit, il traine seulement")

func _les_effets_declares_sont_reellement_composes(v) -> void:
	# PIEGE DU CONSTAT (D) : declarer un effet dans data/etats.json ne suffit
	# jamais, il faut que le cablage lise EtatEffectif. Ce cas verrouille les
	# DEUX lectures du banc.
	var config := _config()
	var etats := _etats()
	var scene := _scene(config)
	var colon = _colon(scene, "colon_soumis")
	var vitesse_nue := Banc.vitesse_effective(colon, config, etats)
	var rythme_nu := Banc.rythme_effectif(colon, config, etats)
	v.v(abs(vitesse_nue - float(config.vitesse_base)) < 0.001,
		"sans etat, la vitesse effective doit valoir la base")
	v.v(abs(rythme_nu - float(config.rythme_base)) < 0.001,
		"sans etat, le rythme effectif doit valoir la base")

	colon.proprietes.etats_actifs.append("soumis")
	v.v(abs(Banc.vitesse_effective(colon, config, etats) - vitesse_nue * 0.7) < 0.001,
		"'soumis' doit MODULER la vitesse par 0.7")
	v.v(abs(Banc.rythme_effectif(colon, config, etats) - rythme_nu * 0.7) < 0.001,
		"'soumis' doit MODULER le rythme par 0.7 -- sans cette lecture l'effet serait mort en silence")

	# L'ecraseur gagne toujours sur le modulateur, les deux etats coexistant.
	colon.proprietes.etats_actifs.append("en_depart")
	v.v(Banc.vitesse_effective(colon, config, etats) == 0.0,
		"'en_depart' doit ECRASER la vitesse a 0.0, quel que soit le modulateur present")

func _le_partant_va_au_bord_puis_quitte_la_liste(v) -> void:
	var config := _config()
	var etats := _etats()
	var seuils := _seuils()
	var scene := _scene(config)
	var nomade = _colon(scene, "colon_nomade")
	_tourner(scene, Banc.MODE_INJUSTICE, 8.0, config, etats, seuils)
	v.v(Banc.sortie_active(nomade, config) == "depart",
		"pre-condition : le nomade doit etre en depart")
	# LEQUEL des quatre bords, c'est bord_le_plus_proche qui le dit -- le test ne
	# le presume jamais (premiere version de ce cas : elle supposait le bord
	# GAUCHE pour un colon a (220,480) sur un terrain 1100x640, alors que le bord
	# BAS est a 160 et le gauche a 220. Le code avait raison, le test avait tort).
	var cible_bord := Banc.bord_le_plus_proche(nomade.position, config)
	var avant: float = nomade.position.distance_to(cible_bord)
	_tourner(scene, Banc.MODE_INJUSTICE, 1.0, config, etats, seuils)
	v.v(nomade.position.distance_to(cible_bord) < avant,
		"le partant doit se rapprocher du bord le plus proche, quel qu'il soit")
	# 'en_depart' ecrase 'vitesse' a 0.0 : s'il bougeait par 'vitesse', il serait
	# cloue au sol. C'est 'vitesse_sortie' qui le pousse.
	v.v(Banc.vitesse_effective(nomade, config, etats) == 0.0,
		"le partant doit bouger MALGRE une vitesse effective nulle (mouvement de sortie, pas du travail)")
	var bascules := _tourner(scene, Banc.MODE_INJUSTICE, 6.0, config, etats, seuils)
	var ids: Array = []
	for colon in scene.colons:
		ids.append(String(colon.id))
	v.v(not ids.has("colon_nomade"),
		"une fois le bord franchi, le partant doit avoir quitte la liste des colons")
	v.v(scene.colons.size() == 2, "les deux autres colons doivent rester")
	v.v(bascules != null, "pre-condition de forme : avancer doit toujours rendre un bilan")

func _un_colon_sans_seuil_ne_rompt_jamais(v) -> void:
	# seuil_etat.gd replie sur INF quand 'seuil_propriete' est absente de
	# l'objet : chemin mort silencieux, jamais une alarme, jamais un seuil
	# invente.
	var config := _config()
	var scene := _scene(config)
	var colon = _colon(scene, "colon_soumis")
	colon.proprietes.erase(String(config.nom_seuil_rupture))
	_tourner(scene, Banc.MODE_INJUSTICE, 20.0, config, _etats(), _seuils())
	v.v(_grief(colon, config) > float(config.seuil_rupture),
		"pre-condition : le grief doit avoir depasse ce qu'aurait ete le seuil")
	v.v(Banc.sortie_active(colon, config) == "",
		"un colon sans 'seuil_rupture' ne doit JAMAIS rompre (repli INF de seuil_etat.gd)")

func _rejeu_complet_de_la_donnee_de_banc(v) -> void:
	# LECON DE banc_maladie : un seuil mal calibre ne franchit jamais rien
	# pendant que le test reste VERT parce qu'il n'a teste que des cas montes
	# a la main. Ici la scene REELLE est rejouee entiere, sur la donnee reelle.
	var config := _config()
	var scene := _scene(config)
	var bascules := _tourner(scene, Banc.MODE_INJUSTICE, 12.0, config, _etats(), _seuils())
	var sorties: Dictionary = {}
	for bascule in bascules:
		if String(bascule.sens) == "pose":
			sorties[String(bascule.sortie)] = true
	v.v(sorties.size() == 3,
		"la donnee reelle doit produire LES TROIS sorties distinctes, jamais deux fois la meme")
	for sortie in config.sorties:
		v.v(sorties.has(String(sortie)),
			"la sortie '%s' doit etre reellement atteinte par la scene reelle" % sortie)
	var comptes := Banc.compter_par_etat(scene.colons, config)
	v.v(int(comptes.neutre) == 0,
		"apres 12 s d'injustice, plus aucun colon ne doit etre neutre")

# LE COUPLAGE QUE LE CAS SUIVANT A REVELE, verrouille ici plutot que
# contourne. Le banc nomme sa grandeur et son seuil en donnee
# (nom_grief/nom_seuil_rupture), mais c'est data/seuils_etat.json qui dit
# QUELLE propriete seuil_etat.gd compare : les deux doivent rester d'accord.
# Renommer l'un sans l'autre ne casse RIEN visiblement -- l'entree devient un
# chemin mort silencieux et plus aucun colon ne rompt jamais, sans une seule
# alarme. Meme accord, et meme verrou, que les trois miroirs de
# banc_faim_thermo.
func _l_accord_avec_le_catalogue_partage(v) -> void:
	var config := _config()
	var entree: Dictionary = _seuils().get(String(config.etat_rupture), {})
	v.v(not entree.is_empty(),
		"data/seuils_etat.json doit porter une entree nommee '%s'" % config.etat_rupture)
	v.v(String(entree.get("propriete_continue", "")) == String(config.nom_grief),
		"l'entree de seuil doit comparer exactement la propriete que le banc ecrit ('%s')" % config.nom_grief)
	v.v(String(entree.get("seuil_propriete", "")) == String(config.nom_seuil_rupture),
		"le seuil doit etre lu PAR OBJET sur exactement la propriete que le banc pose ('%s')" % config.nom_seuil_rupture)
	v.v(String(entree.get("etat", "")) == String(config.etat_rupture),
		"l'etat pose par le seuil doit etre le marqueur que bifurquer() attend")
	# Les trois etats de sortie ET le marqueur de rupture doivent exister dans le
	# catalogue partage : tous les quatre vivent dans etats_actifs, et
	# etat_effectif.gd alarme sur tout nom actif absent de son catalogue -- a
	# chaque lecture de vitesse, donc a chaque image.
	var etats := _etats()
	v.v(etats.has(String(config.etat_rupture)),
		"le marqueur '%s' doit exister dans data/etats.json" % config.etat_rupture)
	for sortie in config.sorties:
		var nom := String(config.etats_par_sortie[String(sortie)])
		v.v(etats.has(nom),
			"l'etat '%s' (sortie '%s') doit exister dans data/etats.json" % [nom, sortie])

func _aucun_nom_de_propriete_en_dur(v) -> void:
	# DOMAINE ENTIEREMENT INVENTE : si le meme code marche ici, c'est qu'aucun
	# nom du jeu n'est ecrit dedans. Meme discipline que test_banc_faim_thermo.
	# Les catalogues d'etats ET de seuils sont eux aussi INVENTES et passes en
	# parametre -- c'est ce que la premiere version de ce cas avait manque : elle
	# renommait les proprietes du banc en gardant le catalogue PARTAGE, dont
	# l'entree compare 'grief' ; plus rien ne rompait, et c'etait CORRECT.
	var config := {
		"nom_grief": "rancoeur_zbeu",
		"nom_seuil_rupture": "point_bascule_zbeu",
		"nom_vitesse": "allure_zbeu",
		"nom_rythme": "cadence_zbeu",
		"nom_travail": "reste_zbeu",
		"etat_rupture": "casse_zbeu",
		"terrain_largeur": 500.0,
		"terrain_hauteur": 500.0,
		"seuil_rupture": 10.0,
		"grief_initial": 0.0,
		"gain_injustice_par_s": 20.0,
		"perte_amelioration_par_s": 20.0,
		"gain_base_par_s": 0.0,
		"perte_base_par_s": 0.0,
		"vitesse_base": 50.0,
		"vitesse_sortie": 50.0,
		"rythme_base": 1.0,
		"travail_initial": 10.0,
		"rayon_arrivee": 10.0,
		"marge_bord": 10.0,
		"sorties": ["flim_zbeu", "glop_zbeu"],
		"etats_par_sortie": {"flim_zbeu": "plie_zbeu", "glop_zbeu": "brave_zbeu"},
		"directive": {"id": "d_zbeu", "position": [400.0, 250.0, 0.0], "bonus_score": 5.0, "etats_vitaux": ["brave_zbeu"]},
		"saillance_ouvrage": 2.0,
		"catalogue_local": {"ouvrage": {"verbes": ["travailler"]}, "point_rassemblement": {"verbes": ["rejoindre"]}},
		"poids_verbes_colon": {"travailler": 1.0, "rejoindre": 1.0},
		"forme_colon": {"seuil_ecrasement": 1.2, "gain_inertie": 0.1, "rayon_liaison": 0.0,
			"gain_bas": 0.1, "plafond_bas": 0.5, "gain_haut": 1.0, "plafond_haut": 1.0},
		"colons": [
			{"id": "zorb_zbeu", "position": [100.0, 250.0, 0.0],
				"biais_grief": {"flim_zbeu": 0.9, "glop_zbeu": 0.1}, "ouvrage": [250.0, 250.0, 0.0]},
		],
	}
	# Catalogues INVENTES eux aussi -- aucun fichier reel du depot n'est lu ici.
	# Le MARQUEUR de rupture doit y figurer lui aussi, au meme titre que les
	# sorties : il vit dans etats_actifs, et etat_effectif.gd alarme sur tout nom
	# actif absent de son catalogue -- a chaque lecture, donc a chaque image.
	var etats_zbeu := {
		"casse_zbeu": {"effets": []},
		"plie_zbeu": {"effets": [{"propriete": "allure_zbeu", "mode": "moduler", "facteur": 0.5}]},
		"brave_zbeu": {"effets": []},
	}
	var seuils_zbeu := {
		"casse_zbeu": {
			"propriete_continue": "rancoeur_zbeu",
			"seuil_propriete": "point_bascule_zbeu",
			"etat": "casse_zbeu",
		},
	}
	var scene := _scene(config)
	var colon = _colon(scene, "zorb_zbeu")
	v.v(colon.proprietes.has("rancoeur_zbeu") and colon.proprietes.has("point_bascule_zbeu"),
		"les noms de proprietes doivent venir de la donnee, jamais du code")
	_tourner(scene, Banc.MODE_INJUSTICE, 1.0, config, etats_zbeu, seuils_zbeu)
	v.v(Banc.sortie_active(colon, config) == "flim_zbeu",
		"un domaine entierement invente doit bifurquer par la meme loi, sans une ligne de code specifique")
	v.v(colon.proprietes.etats_actifs.has("plie_zbeu"),
		"l'etat pose doit venir de etats_par_sortie, jamais d'un nom ecrit dans le .gd")
	v.v(abs(Banc.vitesse_effective(colon, config, etats_zbeu) - float(config.vitesse_base) * 0.5) < 0.001,
		"l'effet d'un etat invente doit se composer par la meme loi, sur un catalogue invente")
	# A DEUX sorties (l'audit ligne 2) comme a trois : la loi ne les compte pas.
	v.v(config.sorties.size() == 2, "pre-condition : ce domaine n'a que DEUX sorties")
