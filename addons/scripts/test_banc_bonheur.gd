extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_bonheur.gd
#
# Verrouille les fonctions PURES de scripts/banc_bonheur.gd (chantier « bonheur
# + temperaments », audit_mecaniques_psycho_sociales_prealable.md lignes 5 et
# 6). Le banc ne fait que CABLER deux mecanismes du coeur deja verrouilles
# separement (seuil_etat.gd / etat_effectif.gd, TOUS DEUX INCHANGES par ce
# chantier) : aucune de leurs lois n'est retestee ici. Ce qui est teste, c'est ce
# que le CABLAGE ajoute -- la somme ponderee recalculee a neuf, le miroir ecrit
# dans le meme geste, et la calibration reelle des quatre temperaments.
#
# DEUX MOITIES, comme les autres tests de banc :
# - HORS DOMAINE : une config, un catalogue de seuils et un catalogue d'etats
#   ENTIEREMENT INVENTES (champ "moral_vlok", miroir "creux_moral_vlok", poids
#   "gouts_vlok", sources "brume_vlok"/"silice_vlok"/"echo_vlok", etats
#   "exalte_vlok"/"morne_vlok"/"abattu_vlok", capacite 10 et non 1) traversent le
#   meme code. Si le banc nommait "bonheur", "manque_bonheur", "poids_bonheur",
#   "securite" ou "heureux" en dur, ce bloc rougirait.
# - CHEMIN REEL : data/banc_bonheur.json + data/seuils_etat.json +
#   data/etats.json relus SUR LE DISQUE, pour verifier la CALIBRATION (les
#   quatre temperaments donnent bien quatre bonheurs, et couper la nourriture
#   n'effondre que le gourmand) et l'ACCORD entre les noms de champ/miroir du
#   banc et les 'propriete_continue' des entrees partagees -- accord qu'aucun
#   autre test ne verifie et dont la rupture serait SILENCIEUSE (un miroir ecrit
#   sous un nom que plus personne ne compare : aucun etat ne se poserait plus
#   jamais, sans une seule alarme).

const Banc = preload("res://scripts/banc_bonheur.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Verif = preload("res://scripts/verif.gd")

# Domaine invente de bout en bout. La capacite vaut 10 et les niveaux de source
# depassent 1.0 : rien ici ne suppose un bonheur normalise entre 0 et 1.
const CONFIG_VLOK := {
	"capacite_bonheur": 10.0,
	"nom_bonheur": "moral_vlok",
	"nom_manque_bonheur": "creux_moral_vlok",
	"nom_poids_bonheur": "gouts_vlok",
	"nom_vitesse": "allure_vlok",
	"nom_rythme": "cadence_vlok",
	"vitesse_base": 20.0,
	"rythme_base": 2.0,
	"ref_seuil_haut": "haut_vlok",
	"ref_seuil_bas": "bas_vlok",
	"ref_seuil_critique": "critique_vlok",
	"etat_heureux": "exalte_vlok",
	"etat_malheureux": "morne_vlok",
	"etat_desespere": "abattu_vlok",
	"sources": [
		{ "nom": "brume_vlok",  "niveau": 4.0, "couleur": [1.0, 0.0, 0.0] },
		{ "nom": "silice_vlok", "niveau": 2.0, "couleur": [0.0, 1.0, 0.0] },
		{ "nom": "echo_vlok",   "niveau": 1.0, "couleur": [0.0, 0.0, 1.0] },
	],
	"colons": [
		{ "id": "un_vlok",     "position": [1.0, 2.0, 0.0], "poids_bonheur": { "brume_vlok": 2.0, "echo_vlok": 1.0 } },
		{ "id": "deux_vlok",   "position": [3.0, 2.0, 0.0], "poids_bonheur": { "silice_vlok": 1.0 } },
		{ "id": "trois_vlok",  "position": [5.0, 2.0, 0.0], "poids_bonheur": { "echo_vlok": 1.0 } },
		{ "id": "quatre_vlok", "position": [7.0, 2.0, 0.0], "poids_bonheur": { "absente_vlok": 3.0 } },
	],
	"couleurs_etat": {},
	"couleur_neutre": [0.5, 0.5, 0.5],
	"taille_colon": 2.0,
	"largeur_barre": 10.0,
	"hauteur_barre": 1.0,
	"espacement_barre": 2.0,
	"taille_police_label": 8,
	"taille_police_compteur": 8,
	"periode_trace_s": 1.0,
}

const SEUILS_VLOK := {
	"haut_vlok":     { "propriete_continue": "moral_vlok",       "seuil": 6.0, "etat": "exalte_vlok" },
	"bas_vlok":      { "propriete_continue": "creux_moral_vlok", "seuil": 5.0, "etat": "morne_vlok" },
	"critique_vlok": { "propriete_continue": "creux_moral_vlok", "seuil": 8.0, "etat": "abattu_vlok" },
}

const ETATS_VLOK := {
	"exalte_vlok": { "effets": [
		{ "propriete": "allure_vlok", "mode": "moduler", "facteur": 1.1 },
		{ "propriete": "cadence_vlok", "mode": "moduler", "facteur": 1.1 },
	] },
	"morne_vlok":  { "effets": [ { "propriete": "allure_vlok", "mode": "moduler", "facteur": 0.8 } ] },
	"abattu_vlok": { "effets": [ { "propriete": "allure_vlok", "mode": "moduler", "facteur": 0.5 } ] },
}

func _init() -> void:
	var v := Verif.new()
	# Hors domaine.
	_colons_poses_avec_leurs_poids(v)
	_le_bonheur_est_la_somme_ponderee_des_sources(v)
	_changer_un_poids_change_le_bonheur(v)
	_couper_une_source_fait_baisser_le_bonheur(v)
	_un_poids_sur_une_source_absente_rend_zero(v)
	_le_miroir_est_ecrit_dans_le_meme_geste_et_borne(v)
	_le_champ_derive_ne_derive_pas(v)
	_deux_colons_memes_sources_poids_differents_bonheurs_differents(v)
	_les_trois_etats_sont_poses_a_leurs_seuils(v)
	_escalier_et_reversibilite_dans_l_ordre_inverse(v)
	_etat_dominant_et_compteur(v)
	_vitesse_et_rythme_effectifs(v)
	_le_toggle_cycle_sur_les_sources_puis_aucune(v)
	_changements_etats(v)
	# Chemin reel.
	_chemin_reel_les_noms_sont_ceux_du_catalogue_partage(v)
	_chemin_reel_quatre_temperaments_quatre_bonheurs(v)
	_chemin_reel_couper_la_nourriture_n_effondre_que_le_gourmand(v)
	_chemin_reel_aucun_etat_parasite(v)

	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_bonheur -- bonheur = somme ponderee des sources recalculee a neuf, " +
			"miroir manque_bonheur ecrit dans le meme geste et borne a 0.0, " +
			"changer un poids change le bonheur, couper une source le fait baisser, " +
			"un poids sur une source absente rend exactement 0.0, " +
			"heureux/malheureux/desespere poses a leurs seuils et retires dans l'ordre inverse, " +
			"deux colons aux memes sources mais aux poids differents ont des bonheurs differents, " +
			"vitesse et rythme composes multiplicativement, un domaine invente traverse le meme code, " +
			"et sur le chemin reel les noms correspondent aux entrees partagees, les quatre temperaments " +
			"donnent quatre bonheurs, couper la nourriture n'effondre que le gourmand, aucun etat parasite")
		quit(0)

# ---- Hors domaine ----

func _colons_poses_avec_leurs_poids(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK)
	v.v(colons.size() == 4, "les quatre colons declares en donnee doivent etre construits")
	var un: Dictionary = colons[0]
	v.v(un.position == Vector3(1.0, 2.0, 0.0), "le colon doit partir de sa position declaree")
	v.v(un.position.z == 0.0, "VERTICALITE : position.z doit rester 0.0 (Vector3 partout, meme a plat)")
	v.v(un.proprietes.has("gouts_vlok"),
		"les poids doivent etre poses sous le nom donne en DONNEE, jamais 'poids_bonheur' en dur")
	v.v(is_equal_approx(float(un.proprietes.gouts_vlok.brume_vlok), 2.0), "les poids declares doivent etre repris tels quels")
	v.v(is_equal_approx(float(un.proprietes.allure_vlok), 20.0) and is_equal_approx(float(un.proprietes.cadence_vlok), 2.0),
		"vitesse et rythme de base doivent etre poses sous les noms donnes en donnee")
	v.v(un.proprietes.get("etats_actifs", null) is Array and un.proprietes.etats_actifs.is_empty(),
		"etats_actifs doit partir vide")
	v.v(not un.proprietes.has("temperature") and not un.proprietes.has("reserves"),
		"le colon ne doit porter NI 'temperature' NI 'reserves' : toutes les autres entrees du catalogue " +
		"PARTAGE de seuils doivent rester des chemins morts pour lui")
	# ALIASING : les poids doivent etre une COPIE, jamais le Dictionary du disque
	# partage entre le catalogue et le colon.
	un.proprietes.gouts_vlok["brume_vlok"] = 99.0
	v.v(is_equal_approx(float(CONFIG_VLOK.colons[0].poids_bonheur.brume_vlok), 2.0),
		"ALIASING : muter les poids d'un colon ne doit JAMAIS toucher la config d'origine")

func _le_bonheur_est_la_somme_ponderee_des_sources(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK)
	var un: Dictionary = colons[0]
	var niveaux: Dictionary = Banc.poser_sources(un, CONFIG_VLOK, "")
	v.v(niveaux.size() == 3 and is_equal_approx(float(niveaux.brume_vlok), 4.0),
		"poser_sources doit poser toutes les sources a leur niveau declare")
	v.v(is_equal_approx(float(un.proprietes.brume_vlok), 4.0),
		"chaque source doit devenir une propriete PLATE sur le colon")
	# 2.0 x 4.0 (brume) + 1.0 x 1.0 (echo) = 9.0. silice n'est pas dans ses gouts :
	# elle ne compte pas, meme si le monde la pose.
	v.v(is_equal_approx(Banc.calculer_bonheur(un, CONFIG_VLOK), 9.0),
		"SOMME PONDEREE : le bonheur doit valoir exactement la somme des poids x niveaux, " +
		"et ignorer les sources que ce colon ne valorise pas")
	var pose: Dictionary = Banc.poser_bonheur(un, CONFIG_VLOK)
	v.v(is_equal_approx(float(un.proprietes.moral_vlok), 9.0),
		"le champ doit etre ecrit sous le nom donne en DONNEE, jamais 'bonheur' en dur")
	v.v(is_equal_approx(float(pose.bonheur), 9.0), "poser_bonheur doit rendre le nombre qu'il vient d'ecrire")

func _changer_un_poids_change_le_bonheur(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK)
	var un: Dictionary = colons[0]
	Banc.poser_sources(un, CONFIG_VLOK, "")
	var avant: float = Banc.calculer_bonheur(un, CONFIG_VLOK)
	# MEME monde, MEMES sources, MEMES niveaux : seul le poids bouge.
	un.proprietes.gouts_vlok["brume_vlok"] = 0.5
	var apres: float = Banc.calculer_bonheur(un, CONFIG_VLOK)
	v.v(is_equal_approx(avant, 9.0) and is_equal_approx(apres, 3.0),
		"CHANGER UN POIDS CHANGE LE BONHEUR : 2.0x4.0+1.0x1.0=9.0 doit devenir 0.5x4.0+1.0x1.0=3.0")
	v.v(apres < avant, "baisser un poids doit baisser le bonheur, le monde etant strictement inchange")
	# Un poids retire disparait de la somme sans qu'aucun cas particulier ne
	# l'exige -- la boucle porte sur les poids, jamais sur une liste de sources.
	un.proprietes.gouts_vlok.erase("brume_vlok")
	v.v(is_equal_approx(Banc.calculer_bonheur(un, CONFIG_VLOK), 1.0),
		"retirer un poids doit retirer sa contribution, sans cas particulier")

func _couper_une_source_fait_baisser_le_bonheur(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK)
	var un: Dictionary = colons[0]
	Banc.poser_sources(un, CONFIG_VLOK, "")
	var plein: float = Banc.calculer_bonheur(un, CONFIG_VLOK)
	Banc.poser_sources(un, CONFIG_VLOK, "brume_vlok")
	var coupe: float = Banc.calculer_bonheur(un, CONFIG_VLOK)
	v.v(is_equal_approx(float(un.proprietes.brume_vlok), 0.0), "une source coupee doit valoir exactement 0.0")
	v.v(is_equal_approx(coupe, 1.0) and coupe < plein,
		"COUPER UNE SOURCE FAIT BAISSER LE BONHEUR : 9.0 doit tomber a 1.0 quand brume est coupee")
	# Couper une source que ce colon ne valorise pas ne doit RIEN changer.
	Banc.poser_sources(un, CONFIG_VLOK, "silice_vlok")
	v.v(is_equal_approx(Banc.calculer_bonheur(un, CONFIG_VLOK), plein),
		"couper une source a laquelle ce colon ne tient pas ne doit rien changer a son bonheur")
	# Reversibilite du monde : la source revient, le bonheur revient.
	Banc.poser_sources(un, CONFIG_VLOK, "")
	v.v(is_equal_approx(Banc.calculer_bonheur(un, CONFIG_VLOK), plein),
		"la source retablie doit rendre exactement le bonheur d'avant la coupure")

func _un_poids_sur_une_source_absente_rend_zero(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK)
	var quatre: Dictionary = colons[3]
	Banc.poser_sources(quatre, CONFIG_VLOK, "")
	v.v(not quatre.proprietes.has("absente_vlok"),
		"le monde ne doit poser QUE les sources declarees -- celle-ci n'existe pas")
	v.v(is_equal_approx(Banc.calculer_bonheur(quatre, CONFIG_VLOK), 0.0),
		"UN POIDS SUR UNE SOURCE QUE LE MONDE N'OFFRE PAS doit rendre exactement 0.0, sans alarme -- " +
		"c'est le contrat (get(source, 0.0)), pas une tolerance")

func _le_miroir_est_ecrit_dans_le_meme_geste_et_borne(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK)
	var un: Dictionary = colons[0]
	Banc.poser_sources(un, CONFIG_VLOK, "")
	var pose: Dictionary = Banc.poser_bonheur(un, CONFIG_VLOK)
	v.v(is_equal_approx(float(un.proprietes.creux_moral_vlok), 1.0),
		"MIROIR : le manque doit valoir exactement capacite - bonheur (10.0 - 9.0), " +
		"sous le nom donne en DONNEE")
	v.v(is_equal_approx(float(pose.manque), 1.0), "poser_bonheur doit rendre le manque qu'il vient d'ecrire")
	v.v(is_equal_approx(float(un.proprietes.creux_moral_vlok),
		float(CONFIG_VLOK.capacite_bonheur) - float(un.proprietes.moral_vlok)),
		"UN SEUL ECRIVAIN : champ et miroir doivent se repondre exactement, ecrits dans le meme geste")
	# Somme de poids superieure a la capacite : le manque plafonne a 0.0, jamais
	# un « manque negatif ».
	un.proprietes.gouts_vlok["brume_vlok"] = 5.0
	Banc.poser_bonheur(un, CONFIG_VLOK)
	v.v(float(un.proprietes.moral_vlok) > float(CONFIG_VLOK.capacite_bonheur),
		"le bonheur n'est PAS ecrete en haut : une somme de poids peut depasser la capacite")
	v.v(is_equal_approx(float(un.proprietes.creux_moral_vlok), 0.0),
		"le miroir doit etre borne a 0.0 par le bas -- jamais un manque negatif")

func _le_champ_derive_ne_derive_pas(v) -> void:
	# LE POINT DU CHANTIER. Un champ derive ecrit par '+=' (le defaut mesure deux
	# fois sur expression.gd) grandirait a chaque tick sans que le monde bouge.
	# Rappele cent fois sur un monde IMMOBILE, le champ doit rester STRICTEMENT
	# identique.
	var colons: Array = Banc.construire_colons(CONFIG_VLOK)
	var un: Dictionary = colons[0]
	Banc.poser_sources(un, CONFIG_VLOK, "")
	var premier: float = float(Banc.poser_bonheur(un, CONFIG_VLOK).bonheur)
	for i in range(100):
		Banc.poser_sources(un, CONFIG_VLOK, "")
		Banc.poser_bonheur(un, CONFIG_VLOK)
	v.v(is_equal_approx(float(un.proprietes.moral_vlok), premier),
		"RECALCUL A NEUF : cent passages sur un monde immobile doivent rendre EXACTEMENT le meme nombre -- " +
		"un '+=' aurait fait diverger le champ sans borne")
	v.v(is_equal_approx(float(un.proprietes.creux_moral_vlok), 10.0 - premier),
		"le miroir doit rester d'accord avec le champ apres cent passages")

func _deux_colons_memes_sources_poids_differents_bonheurs_differents(v) -> void:
	# LA DEMONSTRATION DU BANC : rien dans le monde ne distingue les quatre.
	var colons: Array = Banc.construire_colons(CONFIG_VLOK)
	var bonheurs: Array = []
	for colon in colons:
		Banc.poser_sources(colon, CONFIG_VLOK, "")
		bonheurs.append(float(Banc.poser_bonheur(colon, CONFIG_VLOK).bonheur))
	# Memes sources, memes niveaux, meme instant.
	var memes_sources := true
	for colon in colons:
		for source in CONFIG_VLOK.sources:
			if not is_equal_approx(float(colon.proprietes[String(source.nom)]), float(source.niveau)):
				memes_sources = false
	v.v(memes_sources, "les quatre colons doivent voir EXACTEMENT les memes sources aux memes niveaux")
	v.v(is_equal_approx(bonheurs[0], 9.0) and is_equal_approx(bonheurs[1], 2.0)
		and is_equal_approx(bonheurs[2], 1.0) and is_equal_approx(bonheurs[3], 0.0),
		"TEMPERAMENTS : quatre poids differents sur le meme monde doivent donner quatre bonheurs differents")
	v.v(bonheurs[0] != bonheurs[1] and bonheurs[1] != bonheurs[2] and bonheurs[2] != bonheurs[3],
		"aucun des quatre bonheurs ne doit coincider -- seul le POIDS les distingue")

func _les_trois_etats_sont_poses_a_leurs_seuils(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK)
	for colon in colons:
		Banc.poser_sources(colon, CONFIG_VLOK, "")
		Banc.poser_bonheur(colon, CONFIG_VLOK)
	SeuilEtat.avancer(colons, SEUILS_VLOK)

	# un_vlok : bonheur 9.0 > 6.0 -> exalte, manque 1.0 -> rien d'autre.
	v.v(colons[0].proprietes.etats_actifs.has("exalte_vlok"),
		"SEUIL HAUT : au-dela du seuil, l'etat heureux doit etre pose sur le champ LUI-MEME (jamais sur un miroir)")
	v.v(not colons[0].proprietes.etats_actifs.has("morne_vlok"),
		"un colon heureux ne doit jamais porter en meme temps l'etat malheureux")
	# deux_vlok : bonheur 2.0, manque 8.0 -- EXACTEMENT le seuil critique.
	# seuil_etat.gd compare strictement AU-DESSUS : rien ne doit basculer.
	v.v(colons[1].proprietes.etats_actifs.has("morne_vlok"),
		"SEUIL BAS : au-dela du seuil de manque, l'etat malheureux doit etre pose")
	v.v(not colons[1].proprietes.etats_actifs.has("abattu_vlok"),
		"A EGALITE EXACTE avec le seuil critique, l'etat desespere ne doit PAS etre pose " +
		"(comparaison strictement au-dessus, jamais >=)")
	# trois_vlok : manque 9.0 > 8.0 -> les DEUX.
	v.v(colons[2].proprietes.etats_actifs.has("abattu_vlok") and colons[2].proprietes.etats_actifs.has("morne_vlok"),
		"SEUIL CRITIQUE : au-dela du second seuil, les DEUX etats doivent rester actifs ensemble (memoire par entree)")
	v.v(not colons[2].proprietes.etats_actifs.has("exalte_vlok"),
		"un colon desespere ne doit jamais porter l'etat heureux")

func _escalier_et_reversibilite_dans_l_ordre_inverse(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK)
	var colon: Dictionary = colons[2]
	var monde: Array = [colon]
	# Le monde s'ecrit a la main ici : ce cas ne teste pas les niveaux du banc,
	# il teste l'ORDRE dans lequel les deux etages se posent et se retirent.
	colon.proprietes["echo_vlok"] = 1.0
	Banc.poser_bonheur(colon, CONFIG_VLOK)
	SeuilEtat.avancer(monde, SEUILS_VLOK)
	v.v(colon.proprietes.etats_actifs.has("morne_vlok") and colon.proprietes.etats_actifs.has("abattu_vlok"),
		"au plus bas, les deux etages doivent etre actifs")
	# Le monde s'ameliore : manque 10 - 3 = 7 -> sous le critique, au-dessus du bas.
	colon.proprietes["echo_vlok"] = 3.0
	Banc.poser_bonheur(colon, CONFIG_VLOK)
	SeuilEtat.avancer(monde, SEUILS_VLOK)
	v.v(not colon.proprietes.etats_actifs.has("abattu_vlok") and colon.proprietes.etats_actifs.has("morne_vlok"),
		"ORDRE INVERSE : en remontant, le colon doit perdre l'etage GRAVE d'abord, en gardant le leger")
	# Il remonte encore : bonheur 5.0, manque 5.0 -- EXACTEMENT le seuil bas et
	# encore sous le seuil haut. Plus aucun etat : ni l'un ni l'autre n'est
	# franchi (comparaison strictement au-dessus des DEUX cotes).
	colon.proprietes["echo_vlok"] = 5.0
	Banc.poser_bonheur(colon, CONFIG_VLOK)
	SeuilEtat.avancer(monde, SEUILS_VLOK)
	v.v(colon.proprietes.etats_actifs.is_empty(),
		"REVERSIBILITE : le champ derive redescend, donc seuil_etat.gd retire les deux etats tout seul -- " +
		"le bonheur n'est PAS une grandeur cumulee")
	# Et il devient heureux : bonheur 9.0 > 6.0.
	colon.proprietes["echo_vlok"] = 9.0
	Banc.poser_bonheur(colon, CONFIG_VLOK)
	SeuilEtat.avancer(monde, SEUILS_VLOK)
	v.v(colon.proprietes.etats_actifs == ["exalte_vlok"],
		"le meme colon doit pouvoir passer du desespoir au bonheur, sans qu'aucun etat ne reste colle")

func _etat_dominant_et_compteur(v) -> void:
	var colons: Array = Banc.construire_colons(CONFIG_VLOK)
	for colon in colons:
		Banc.poser_sources(colon, CONFIG_VLOK, "")
		Banc.poser_bonheur(colon, CONFIG_VLOK)
	SeuilEtat.avancer(colons, SEUILS_VLOK)

	v.v(Banc.etat_dominant(colons[0], CONFIG_VLOK) == "exalte_vlok", "l'etat dominant d'un colon heureux est le sien")
	v.v(Banc.etat_dominant(colons[1], CONFIG_VLOK) == "morne_vlok", "un seul etage actif : c'est lui le dominant")
	v.v(Banc.etat_dominant(colons[2], CONFIG_VLOK) == "abattu_vlok",
		"PRIORITE : les deux etages actifs, c'est le PLUS GRAVE qui doit s'afficher -- " +
		"seuil_etat.gd ne hierarchise jamais, c'est a l'appelant de le faire")

	var neutre: Dictionary = Banc.construire_colons(CONFIG_VLOK)[0]
	neutre.proprietes.etats_actifs = []
	v.v(Banc.etat_dominant(neutre, CONFIG_VLOK) == "",
		"NEUTRE : l'absence des trois etats doit rendre la chaine vide, jamais un nom d'etat invente")

	var compte: Dictionary = Banc.compte_par_etat(colons, CONFIG_VLOK)
	v.v(int(compte.exalte_vlok) == 1 and int(compte.morne_vlok) == 1
		and int(compte.abattu_vlok) == 2 and int(compte[""]) == 0,
		"COMPTEUR : chaque colon doit etre compte UNE FOIS, sous son etat dominant seul")
	var somme := 0
	for cle in compte:
		somme += int(compte[cle])
	v.v(somme == colons.size(), "le compteur doit totaliser exactement le nombre de colons, jamais plus")

func _vitesse_et_rythme_effectifs(v) -> void:
	var colon: Dictionary = Banc.construire_colons(CONFIG_VLOK)[0]
	v.v(is_equal_approx(Banc.vitesse_effective(colon, CONFIG_VLOK, ETATS_VLOK), 20.0)
		and is_equal_approx(Banc.rythme_effectif(colon, CONFIG_VLOK, ETATS_VLOK), 2.0),
		"sans aucun etat, vitesse et rythme effectifs doivent valoir leurs bases")
	colon.proprietes.etats_actifs = ["exalte_vlok"]
	v.v(is_equal_approx(Banc.vitesse_effective(colon, CONFIG_VLOK, ETATS_VLOK), 22.0),
		"l'etat heureux doit ACCELERER la vitesse (facteur > 1.0, premier du depot)")
	v.v(is_equal_approx(Banc.rythme_effectif(colon, CONFIG_VLOK, ETATS_VLOK), 2.2),
		"l'etat heureux doit aussi moduler le RYTHME -- lecture composee que seul ce banc fait " +
		"(banc_commun.gd:agents_rythme lit la valeur brute)")
	colon.proprietes.etats_actifs = ["morne_vlok", "abattu_vlok"]
	v.v(is_equal_approx(Banc.vitesse_effective(colon, CONFIG_VLOK, ETATS_VLOK), 20.0 * 0.8 * 0.5),
		"les deux etages doivent se composer MULTIPLICATIVEMENT (0.8 x 0.5), aucun des deux ne connaissant l'autre")
	v.v(is_equal_approx(Banc.rythme_effectif(colon, CONFIG_VLOK, ETATS_VLOK), 2.0),
		"aucun des deux etages bas ne vise le rythme : il doit rester a sa base")

func _le_toggle_cycle_sur_les_sources_puis_aucune(v) -> void:
	var nb: int = CONFIG_VLOK.sources.size()
	var vus: Array = []
	var selection := nb
	for i in range(nb + 1):
		selection = Banc.source_suivante(selection, nb)
		vus.append(selection)
	v.v(vus == [0, 1, 2, 3], "le toggle doit parcourir chaque source puis l'etat AUCUNE, dans l'ordre declare")
	v.v(Banc.source_suivante(nb, nb) == 0, "depuis AUCUNE, le clic suivant doit couper la premiere source")
	v.v(Banc.noms_sources(CONFIG_VLOK) == ["brume_vlok", "silice_vlok", "echo_vlok"],
		"les noms de sources doivent rester dans l'ORDRE DECLARE -- c'est celui des barres et celui du cycle")

func _changements_etats(v) -> void:
	var changements: Dictionary = Banc.changements_etats(["a_vlok", "b_vlok"], ["b_vlok", "c_vlok"])
	v.v(changements.gagnes == ["c_vlok"] and changements.perdus == ["a_vlok"],
		"changements_etats doit rendre les etats gagnes ET perdus, jamais ceux qui n'ont pas bouge")
	v.v(Banc.lignes_changement(1.0, "un_vlok", changements).size() == 2,
		"une ligne de console par changement, ni plus ni moins")
	v.v(Banc.changements_etats(["a_vlok"], ["a_vlok"]).gagnes.is_empty(),
		"sans changement, aucune ligne ne doit etre tracee (sinon la console cracherait a chaque frame)")

# ---- Chemin reel : les fichiers du disque ----

# ACCORD ENTRE LE BANC ET LES CATALOGUES PARTAGES. Si 'nom_bonheur' ou
# 'nom_manque_bonheur' cessait de correspondre au 'propriete_continue' d'une
# entree de data/seuils_etat.json, le banc ecrirait sagement deux nombres que
# plus personne ne comparerait : aucun etat ne se poserait plus jamais, et
# AUCUNE alarme ne le dirait (seuil_etat.gd traite une propriete absente comme un
# chemin mort legitime). Ce cas ferme ce trou.
func _chemin_reel_les_noms_sont_ceux_du_catalogue_partage(v) -> void:
	var config: Dictionary = _charger("res://data/banc_bonheur.json")
	var seuils: Dictionary = _charger("res://data/seuils_etat.json")
	var etats: Dictionary = _charger("res://data/etats.json")
	v.v(not config.is_empty() and not seuils.is_empty() and not etats.is_empty(),
		"les trois fichiers du chemin reel doivent charger")

	var attendus := {
		String(config.ref_seuil_haut):     [String(config.nom_bonheur), String(config.etat_heureux)],
		String(config.ref_seuil_bas):      [String(config.nom_manque_bonheur), String(config.etat_malheureux)],
		String(config.ref_seuil_critique): [String(config.nom_manque_bonheur), String(config.etat_desespere)],
	}
	for ref in attendus:
		v.v(seuils.has(ref), "data/seuils_etat.json doit porter l'entree '%s'" % ref)
		if not seuils.has(ref):
			continue
		v.v(String(seuils[ref].propriete_continue) == String(attendus[ref][0]),
			"l'entree '%s' doit comparer la propriete que le banc ecrit reellement (%s)" % [ref, attendus[ref][0]])
		var nom_etat := String(seuils[ref].etat)
		v.v(nom_etat == String(attendus[ref][1]), "l'entree '%s' doit poser l'etat '%s'" % [ref, attendus[ref][1]])
		v.v(etats.has(nom_etat), "l'etat '%s' doit exister dans data/etats.json" % nom_etat)
		if etats.has(nom_etat):
			v.v(not etats[nom_etat].has("duree"),
				"l'etat '%s' ne doit porter AUCUNE duree : il est retire par le franchissement descendant, " % nom_etat +
				"jamais par le temps -- le temps ne rend personne heureux")
			var vise_vitesse := false
			for effet in etats[nom_etat].get("effets", []):
				if String(effet.get("propriete", "")) == String(config.nom_vitesse):
					vise_vitesse = true
			v.v(vise_vitesse, "l'etat '%s' doit moduler la vitesse -- sinon rien ne serait observable" % nom_etat)

	# L'etat heureux est le SEUL a viser aussi le rythme, et le seul du depot dont
	# un facteur depasse 1.0.
	var heureux: Dictionary = etats.get(String(config.etat_heureux), {})
	var vise_rythme := false
	var accelere := false
	for effet in heureux.get("effets", []):
		if String(effet.get("propriete", "")) == String(config.nom_rythme):
			vise_rythme = true
		if float(effet.get("facteur", 1.0)) > 1.0:
			accelere = true
	v.v(vise_rythme, "l'etat heureux doit moduler le RYTHME en plus de la vitesse")
	v.v(accelere, "l'etat heureux doit ACCELERER (facteur > 1.0) : un colon heureux fait tout un peu plus vite")

	v.v(float(seuils[String(config.ref_seuil_critique)].seuil) > float(seuils[String(config.ref_seuil_bas)].seuil),
		"ESCALIER : le seuil critique doit rester strictement au-dessus du seuil bas")
	# heureux et malheureux ne peuvent JAMAIS coexister : bonheur > seuil_haut
	# implique manque < capacite - seuil_haut, qui doit rester sous le seuil bas.
	v.v(float(config.capacite_bonheur) - float(seuils[String(config.ref_seuil_haut)].seuil)
		<= float(seuils[String(config.ref_seuil_bas)].seuil),
		"CALIBRATION : les seuils doivent interdire qu'un colon soit heureux ET malheureux en meme temps")
	v.v(is_equal_approx(float(config.capacite_bonheur), 1.0),
		"les trois seuils partages sont calibres contre capacite_bonheur = 1.0 -- tout cablage qui la change " +
		"doit rouvrir data/seuils_etat.json (meme limite assumee que 'famine'/'epuisement')")

# CALIBRATION REELLE : les quatre temperaments sur le monde reel. Sans ce cas,
# un reglage mal choisi laisserait un banc qui ne montre rien tout en restant
# VERT (le defaut exact rencontre par banc_maladie, voir docs/ETAT.md).
func _chemin_reel_quatre_temperaments_quatre_bonheurs(v) -> void:
	var config: Dictionary = _charger("res://data/banc_bonheur.json")
	var seuils: Dictionary = _charger("res://data/seuils_etat.json")
	var colons: Array = Banc.construire_colons(config)
	v.v(colons.size() == 4, "le banc reel doit porter exactement quatre colons")
	v.v(Banc.noms_sources(config).size() == 5, "le banc reel doit porter exactement cinq sources")

	var bonheurs: Dictionary = {}
	for colon in colons:
		Banc.poser_sources(colon, config, "")
		bonheurs[String(colon.id)] = float(Banc.poser_bonheur(colon, config).bonheur)
	SeuilEtat.avancer(colons, seuils)

	# Aucun des quatre ne doit avoir le meme bonheur : c'est toute la
	# demonstration, et elle ne tient qu'a la calibration.
	var vus: Array = []
	var tous_distincts := true
	for id in bonheurs:
		for deja in vus:
			if is_equal_approx(float(bonheurs[id]), float(deja)):
				tous_distincts = false
		vus.append(bonheurs[id])
	v.v(tous_distincts,
		"CALIBRATION : les quatre temperaments doivent donner quatre bonheurs DISTINCTS sur le meme monde")

	var etats_par_id: Dictionary = {}
	for colon in colons:
		etats_par_id[String(colon.id)] = Banc.etat_dominant(colon, config)
	# Trois etats differents presents au demarrage : sans un seul clic, le banc
	# montre deja que le temperament seul suffit a diverger.
	var distincts: Dictionary = {}
	for id in etats_par_id:
		distincts[etats_par_id[id]] = true
	v.v(distincts.size() >= 2,
		"CALIBRATION : au demarrage, sans aucun clic, les quatre colons ne doivent PAS etre tous dans le meme etat")
	var au_moins_un_heureux := false
	var au_moins_un_neutre := false
	for id in etats_par_id:
		if etats_par_id[id] == String(config.etat_heureux):
			au_moins_un_heureux = true
		if etats_par_id[id] == "":
			au_moins_un_neutre = true
	v.v(au_moins_un_heureux, "CALIBRATION : au moins un colon doit demarrer heureux")
	v.v(au_moins_un_neutre,
		"CALIBRATION : au moins un colon doit demarrer NEUTRE -- sans lui, la couleur grise ne serait jamais visible")

# LE CAS QUE LA CONSIGNE DEMANDE DE RENDRE VISIBLE : couper la nourriture
# effondre le gourmand et laisse les autres a peu pres ou ils etaient.
func _chemin_reel_couper_la_nourriture_n_effondre_que_le_gourmand(v) -> void:
	var config: Dictionary = _charger("res://data/banc_bonheur.json")
	var seuils: Dictionary = _charger("res://data/seuils_etat.json")
	var colons: Array = Banc.construire_colons(config)

	# La source coupee et le colon le plus expose sont TROUVES en donnee, jamais
	# nommes en dur : c'est celui dont le poids sur cette source est le plus haut.
	var source := "nourriture"
	v.v(Banc.noms_sources(config).has(source), "le banc reel doit porter la source '%s'" % source)

	var avant: Dictionary = {}
	for colon in colons:
		Banc.poser_sources(colon, config, "")
		avant[String(colon.id)] = float(Banc.poser_bonheur(colon, config).bonheur)
	SeuilEtat.avancer(colons, seuils)

	var apres: Dictionary = {}
	for colon in colons:
		Banc.poser_sources(colon, config, source)
		apres[String(colon.id)] = float(Banc.poser_bonheur(colon, config).bonheur)
	SeuilEtat.avancer(colons, seuils)

	var le_plus_expose := ""
	var poids_max := -1.0
	var chute_max := -1.0
	for colon in colons:
		var id := String(colon.id)
		var poids: float = float(colon.proprietes.get(String(config.nom_poids_bonheur), {}).get(source, 0.0))
		if poids > poids_max:
			poids_max = poids
			le_plus_expose = id
		chute_max = max(chute_max, float(avant[id]) - float(apres[id]))
		v.v(float(apres[id]) <= float(avant[id]),
			"couper une source ne doit JAMAIS faire monter le bonheur de qui que ce soit (%s)" % id)
		if is_equal_approx(poids, 0.0):
			v.v(is_equal_approx(float(apres[id]), float(avant[id])),
				"%s ne met aucun poids sur '%s' : son bonheur doit rester STRICTEMENT inchange" % [id, source])

	v.v(is_equal_approx(float(avant[le_plus_expose]) - float(apres[le_plus_expose]), chute_max),
		"c'est le colon qui met le plus de poids sur la source coupee qui doit chuter le plus")

	var etats_apres: Dictionary = {}
	for colon in colons:
		etats_apres[String(colon.id)] = colons_etats(colon)
	v.v(etats_apres[le_plus_expose].has(String(config.etat_malheureux))
		and etats_apres[le_plus_expose].has(String(config.etat_desespere)),
		"CALIBRATION : nourriture coupee, le colon qui n'a qu'elle doit devenir malheureux ET desespere -- " +
		"les deux etages a la fois, c'est ce que le banc existe pour montrer")
	var au_moins_un_epargne := false
	for id in etats_apres:
		if id != le_plus_expose and not etats_apres[id].has(String(config.etat_malheureux)):
			au_moins_un_epargne = true
	v.v(au_moins_un_epargne,
		"CALIBRATION : au moins un autre colon doit rester non malheureux -- sinon la coupure ne prouve rien " +
		"sur les temperaments, seulement que tout le monde souffre pareil")

	# Et le monde revient : la source retablie, tout le monde retrouve exactement
	# son bonheur d'avant.
	for colon in colons:
		Banc.poser_sources(colon, config, "")
		Banc.poser_bonheur(colon, config)
	SeuilEtat.avancer(colons, seuils)
	for colon in colons:
		v.v(is_equal_approx(float(colon.proprietes[String(config.nom_bonheur)]), float(avant[String(colon.id)])),
			"REVERSIBILITE : la source retablie, %s doit retrouver EXACTEMENT son bonheur d'avant" % colon.id)

# Aucun etat du catalogue PARTAGE autre que les trois de ce chantier ne doit
# pouvoir se poser sur ces colons -- ils ne portent ni 'temperature', ni reserve,
# ni aucune grandeur cumulee. Verrouille POSITIVEMENT, comme banc_faim_thermo.
func _chemin_reel_aucun_etat_parasite(v) -> void:
	var config: Dictionary = _charger("res://data/banc_bonheur.json")
	var seuils: Dictionary = _charger("res://data/seuils_etat.json")
	var colons: Array = Banc.construire_colons(config)
	var autorises := [String(config.etat_heureux), String(config.etat_malheureux), String(config.etat_desespere)]

	for coupee in ([""] + Banc.noms_sources(config)):
		for colon in colons:
			Banc.poser_sources(colon, config, String(coupee))
			Banc.poser_bonheur(colon, config)
		SeuilEtat.avancer(colons, seuils)
		for colon in colons:
			for etat in colon.proprietes.get("etats_actifs", []):
				v.v(autorises.has(String(etat)),
					"AUCUN PARASITE : '%s' s'est pose sur %s -- les colons de ce banc ne portent " % [String(etat), colon.id] +
					"ni temperature ni grandeur cumulee, toutes les autres entrees du catalogue partage " +
					"doivent rester des chemins morts pour eux")

func colons_etats(colon: Dictionary) -> Array:
	var noms: Array = []
	for etat in colon.proprietes.get("etats_actifs", []):
		noms.append(String(etat))
	return noms

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
