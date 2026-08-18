extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_commun.gd
#
# Verrouille les dix outils de scripts/banc_commun.gd -- jusqu'ici
# dupliques a l'identique entre banc_p1.gd/banc_feu.gd (et banc_animal.gd
# pour bouger_vers), aucun des trois ne les testant tous a la fois (seul
# banc_p1.gd testait fabriquer_colon/bouger_vers/bouger_selon, cote lui).
# Ce fichier ferme ce trou en verrouillant l'unique copie partagee,
# independamment de tout banc. choses_a_fuir/verbe_action (derniere paire
# descendue, chantier "choses_a_fuir/verbe_action") reprennent les memes
# scenarios que testait banc_p1.gd avant la migration -- toujours
# exerces aussi depuis test_banc_p1.gd/test_banc_feu.gd par le chemin reel
# du banc (agir_et_deplacer), jamais retires de la, meme convention que
# bouger_vers/bouger_selon.
#
# _objets_de_aplatit_dans_l_ordre_d_ajout TRANCHE empiriquement un point
# jusqu'ici non verifie : un Dictionary GDScript (monde.choses depuis le
# chantier "Monde en Dictionary") preserve-t-il l'ordre d'insertion sur
# .values() ? Ne se suppose pas, se prouve : deux choses ajoutees a/b,
# l'ordre de sortie doit rester a puis b.
#
# _fabriquer_colon_rend_position_proprietes_et_action utilise le type
# invente "gardien" (jamais "colon") : verrou que la fonction ne code plus
# aucun nom de type en dur, condition pour vivre dans cette boite (voir
# banc_commun.gd, CRITERE D'ENTREE) plutot que dans un banc jetable seul.

const BancCommun = preload("res://scripts/banc_commun.gd")
const Monde = preload("res://scripts/monde.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_objets_de_aplatit_dans_l_ordre_d_ajout()
	_marquer_eteints_pose_couleur_et_log_sur_id_present()
	_marquer_eteints_alarme_sur_id_absent_sans_planter_les_autres()
	_marquer_eteints_ignore_eteints_vide()
	_agents_rythme_derive_du_monde_et_aplatit()
	_resoudre_chantier_pose_les_cles_absentes_du_patron()
	_resoudre_chantier_descend_dans_un_conteneur_sans_effacer_ses_voisines()
	_resoudre_chantier_ne_fusionne_jamais_un_array_ni_ne_partage_de_reference()
	_fabriquer_colon_rend_position_proprietes_et_action()
	_bouger_vers_avance_vers_la_cible_sans_depasser()
	_bouger_selon_avance_selon_une_direction_sans_cible()
	_choses_a_fuir_filtre_par_verbe_resolu_oriente_fuite()
	_verbe_action_resout_portee_depuis_la_transformation_de_la_chose()
	_verbe_action_alarme_sur_portee_travail_absente_sans_defaut_silencieux()
	_monde_depuis_construit_par_groupes_et_resout_le_type_par_chose()
	_monde_depuis_alarme_sur_groupe_sans_choses()
	_aucun_banc_ne_fabrique_un_monde_dans_une_fonction()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: objets_de aplatit dans l'ordre d'ajout avec les memes references, " +
		"marquer_eteints pose couleur/log et alarme sans planter sur id absent, " +
		"agents_rythme aplatit rythme, resoudre_chantier pose les cles absentes du patron " +
		"au grain de la sous-cle sans effacer les voisines ni partager de reference, " +
		"fabriquer_colon rend position/proprietes/action sans nom de type en dur, " +
		"bouger_vers borne le pas a la cible, bouger_selon avance d'un pas plein selon une direction, " +
		"choses_a_fuir filtre par verbe resolu oriente fuite, " +
		"verbe_action resout eteint/va vers depuis la transformation de la chose sans defaut silencieux, " +
		"monde_depuis construit par groupes en re-ajoutant PAR REFERENCE -- et aucun banc ne fabrique plus de Monde dans une fonction")
	quit(0)

func _noeud(couleur: Color) -> ColorRect:
	var n := ColorRect.new()
	n.color = couleur
	return n

# Verrou du point non tranche jusqu'ici (voir en-tete) : .values() sur
# monde.choses (Dictionary id -> { chose, type }) doit rendre les entrees
# dans l'ORDRE D'AJOUT, jamais un ordre arbitraire -- et les MEMES
# references Dictionary que celles enregistrees (pas des copies), sinon
# une mutation via propagation.gd/extinction.gd n'atteindrait plus l'objet
# vu par ailleurs.
func _objets_de_aplatit_dans_l_ordre_d_ajout() -> void:
	var monde := Monde.new()
	var a := Objet.fabriquer("a", "type_a", Vector3(0, 0, 0), {})
	var b := Objet.fabriquer("b", "type_b", Vector3(10, 0, 0), {})
	monde.ajouter(a, "type_a", a.position)
	monde.ajouter(b, "type_b", b.position)

	var objets := BancCommun.objets_de(monde)
	verif.v(objets.size() == 2, "objets_de doit rendre autant d'objets que de choses ajoutees")
	verif.v(objets[0] == a and objets[1] == b,
		"objets_de doit rendre les choses dans l'ordre d'ajout (verdict empirique sur .values())")
	verif.v(is_same(objets[0], a),
		"objets_de doit rendre la MEME reference Dictionary, pas une copie")

# Couleur initiale (blanc) DIFFERENTE de la couleur posee (gris) : si la
# fonction etait videe, le test resterait vert par coincidence sinon (meme
# motif que test_banc_p1.gd:_marquer_eteints_pose_couleur_type_et_ignore_liste_vide).
# monde.par_id("feu_1") doit rendre un wrapper non-null (id enregistre) --
# c'est desormais la SEULE garde, plus de entrees_stub a cote.
func _marquer_eteints_pose_couleur_et_log_sur_id_present() -> void:
	var monde := Monde.new()
	var feu := Objet.fabriquer("feu_1", "feu", Vector3.ZERO, {})
	monde.ajouter(feu, "feu", feu.position)
	var blanc := Color(1, 1, 1)
	var gris_cendre := Color(0.3, 0.3, 0.3)
	var noeuds := {"feu_1": _noeud(blanc)}

	BancCommun.marquer_eteints(["feu_1"], noeuds, monde, gris_cendre, 12.5)

	verif.v(noeuds["feu_1"].color == gris_cendre,
		"la couleur recue en parametre doit etre posee sur le noeud eteint")

# Un id absent de noeuds OU dont monde.par_id() rend null doit alarmer
# (push_error) et continuer sans planter le traitement des autres id de la
# meme liste -- "colon_inconnu" n'est enregistre ni dans noeuds ni dans
# monde (comme un colon reel, jamais alimente dans le monde du chantier
# d'extinction dans les bancs actuels). Note : monde.par_id() alarme deja
# lui-meme sur un id absent (doctrine de monde.gd) -- deux push_error sont
# donc attendus pour "colon_inconnu" (un de monde.par_id, un de
# marquer_eteints), sans que ca n'empeche "feu_1" d'etre traite.
func _marquer_eteints_alarme_sur_id_absent_sans_planter_les_autres() -> void:
	var monde := Monde.new()
	var feu := Objet.fabriquer("feu_1", "feu", Vector3.ZERO, {})
	monde.ajouter(feu, "feu", feu.position)
	var blanc := Color(1, 1, 1)
	var gris_cendre := Color(0.3, 0.3, 0.3)
	var noeuds := {"feu_1": _noeud(blanc)}

	BancCommun.marquer_eteints(["colon_inconnu", "feu_1"], noeuds, monde, gris_cendre, 5.0)

	verif.v(noeuds["feu_1"].color == gris_cendre,
		"l'id valide doit etre traite malgre un id absent dans la meme liste")

# eteints vide ne doit toucher aucune couleur.
func _marquer_eteints_ignore_eteints_vide() -> void:
	var monde := Monde.new()
	var feu := Objet.fabriquer("feu_1", "feu", Vector3.ZERO, {})
	monde.ajouter(feu, "feu", feu.position)
	var blanc := Color(1, 1, 1)
	var noeuds := {"feu_1": _noeud(blanc)}

	BancCommun.marquer_eteints([], noeuds, monde, Color(0.3, 0.3, 0.3), 0.0)

	verif.v(noeuds["feu_1"].color == blanc, "eteints vide ne doit toucher aucune couleur")

# rythme = 3.5, jamais 1.0 (le defaut d'extinction.gd:agent.get("rythme",
# 1.0)) : si le defaut silencieux s'appliquait en douce, ce test le
# verrait, comme test_banc_p1.gd:_agents_rythme_derive_du_monde_et_aplatit.
func _agents_rythme_derive_du_monde_et_aplatit() -> void:
	var table := {
		"avec_rythme": {"rythme": 3.5},
		"sans_rythme": {"dur": true},
	}
	var avec := Objet.fabriquer("avec_rythme_1", "avec_rythme", Vector3(10, 20, 0), table)
	var sans := Objet.fabriquer("sans_rythme_1", "sans_rythme", Vector3(99, 99, 0), table)
	var monde: Array = [avec, sans]

	var agents := BancCommun.agents_rythme(monde)
	verif.v(agents.size() == 1, "seule la chose portant rythme devient agent")
	verif.v(agents[0].get("rythme", -1.0) == 3.5, "rythme doit ressortir a plat et INCHANGE")
	verif.v(agents[0].get("position", null) == Vector3(10, 20, 0), "la position doit aussi ressortir a plat")

# Les cles deja presentes sur proprietes gagnent (travail_restant reste a
# 5.0, pas ecrase par le patron) ; les cles absentes viennent du patron
# (transformation, absente ici, doit apparaitre).
func _resoudre_chantier_pose_les_cles_absentes_du_patron() -> void:
	var proprietes := {"travail_restant": 5.0}
	var patron := {"travail_restant": 100.0, "transformation": "defaut"}

	BancCommun.resoudre_chantier(proprietes, patron)

	verif.v(proprietes.travail_restant == 5.0,
		"une cle deja presente sur proprietes ne doit jamais etre ecrasee par le patron")
	verif.v(proprietes.transformation == "defaut",
		"une cle absente de proprietes doit venir du patron")

# HORS DOMAINE (aucun feu, aucun colon, aucun nom du jeu) : le grain de la
# comparaison est la SOUS-cle. Une chose qui porte deja le CONTENEUR avec
# d'autres sous-cles doit recevoir celle du patron sans perdre les siennes ;
# une chose qui porte deja LA sous-cle du patron doit garder sa valeur. A la
# racine, les deux cas sont indistinguables et le premier perd tout.
func _resoudre_chantier_descend_dans_un_conteneur_sans_effacer_ses_voisines() -> void:
	var patron := {"bacs": {"zorg": {"niveau": 9.0}}}

	var voisines := {"bacs": {"plif": {"niveau": 1.0}, "blop": {"niveau": 2.0}}}
	BancCommun.resoudre_chantier(voisines, patron)
	verif.v(voisines.bacs.has("zorg") and voisines.bacs.zorg.niveau == 9.0,
		"la sous-cle absente du conteneur doit venir du patron")
	verif.v(voisines.bacs.has("plif") and voisines.bacs.has("blop"),
		"les sous-cles deja presentes du conteneur ne doivent JAMAIS disparaitre")
	verif.v(voisines.bacs.plif.niveau == 1.0 and voisines.bacs.blop.niveau == 2.0,
		"les sous-cles deja presentes doivent garder leur valeur")

	var propre := {"bacs": {"zorg": {"niveau": 0.5}}}
	BancCommun.resoudre_chantier(propre, patron)
	verif.v(propre.bacs.zorg.niveau == 0.5,
		"une sous-cle deja presente garde sa calibration, le patron ne l'ecrase pas")

	var scalaire := {"bacs": 3.0}
	BancCommun.resoudre_chantier(scalaire, patron)
	verif.v(scalaire.bacs == 3.0,
		"une valeur presente d'un autre type que celle du patron est laissee telle quelle")

# Un Array ne se fusionne jamais element par element ; et toute feuille posee
# est une COPIE, sinon deux choses partagent le meme sous-dictionnaire et un
# mecanisme qui le mute en place ecrit sur les deux.
func _resoudre_chantier_ne_fusionne_jamais_un_array_ni_ne_partage_de_reference() -> void:
	var patron := {"paliers": ["a", "b"], "bacs": {"zorg": {"niveau": 9.0}}}

	var deja := {"paliers": ["c"]}
	BancCommun.resoudre_chantier(deja, patron)
	verif.v(deja.paliers.size() == 1 and deja.paliers[0] == "c",
		"un Array deja present est laisse tel quel, jamais complete element par element")

	var une := {}
	var autre := {}
	BancCommun.resoudre_chantier(une, patron)
	BancCommun.resoudre_chantier(autre, patron)
	une.bacs.zorg.niveau = 42.0
	une.paliers.append("z")
	verif.v(autre.bacs.zorg.niveau == 9.0,
		"deux choses ne doivent jamais partager le sous-dictionnaire pose par le patron")
	verif.v(autre.paliers.size() == 2,
		"deux choses ne doivent jamais partager l'Array pose par le patron")
	verif.v(patron.bacs.zorg.niveau == 9.0 and patron.paliers.size() == 2,
		"le patron lui-meme ne doit jamais etre mute par une pose")

# Type "gardien", invente, jamais "colon" : verrouille que fabriquer_colon
# ne code plus aucun nom de type en dur (voir CARTE.md §6) -- le type recu
# en parametre traverse jusqu'a Objet.fabriquer, quel qu'il soit.
func _fabriquer_colon_rend_position_proprietes_et_action() -> void:
	var catalogue_types := {
		"gardien": {"vitesse": 150.0, "canaux": ["vue"], "canaux_config": {"vue": {"portee": 1600.0}}, "rythme": 1.0},
	}
	var decl := {
		"position": [10.0, 20.0, 0.0],
		"attaches": [{"propriete": "irremplacable", "force": 4.0}],
		"forme": {"rayon_liaison": 220.0},
		"poids_verbes": {"eteindre": 1.0, "attiser": -1.0},
	}

	var colon := BancCommun.fabriquer_colon("test_colon", "gardien", decl, catalogue_types)

	verif.v(colon.id == "test_colon", "l'id doit etre celui passe en parametre")
	verif.v(colon.position == Vector3(10.0, 20.0, 0.0),
		"la position doit venir de decl, convertie en Vector3")
	verif.v(colon.proprietes.vitesse == 150.0,
		"les proprietes communes au type recu en parametre doivent venir du catalogue_types")
	verif.v(colon.proprietes.attaches == decl.attaches,
		"attaches doit venir de decl, jamais du catalogue_types")
	verif.v(colon.proprietes.forme == decl.forme,
		"forme doit venir de decl, jamais du catalogue_types")
	verif.v(colon.proprietes.poids_verbes == decl.poids_verbes,
		"poids_verbes doit venir de decl, jamais du catalogue_types ni invente")
	verif.v(colon.action_en_cours == {}, "action_en_cours doit etre initialise vide")
	verif.v(colon.action_precedente == "__jamais__",
		"action_precedente doit etre initialisee a la sentinelle")
	verif.v(not colon.has("node"), "fabriquer_colon ne doit rien dessiner")

# bouger_vers borne le pas a vitesse * delta SANS jamais depasser la cible
# (contrairement a bouger_selon) ; sous le seuil de 1.0 il ne bouge pas du
# tout (evite le tremblement au contact).
func _bouger_vers_avance_vers_la_cible_sans_depasser() -> void:
	var position := Vector3(0, 0, 0)
	var avance := BancCommun.bouger_vers(position, Vector3(100, 0, 0), 10.0, 1.0)
	verif.v(avance.is_equal_approx(Vector3(10, 0, 0)),
		"bouger_vers doit avancer d'un pas borne par vitesse * delta")

	var arrivee := BancCommun.bouger_vers(position, Vector3(5, 0, 0), 10.0, 1.0)
	verif.v(arrivee == Vector3(5, 0, 0),
		"bouger_vers ne doit jamais depasser une cible plus proche que vitesse * delta")

	var immobile := BancCommun.bouger_vers(position, Vector3(0.5, 0, 0), 10.0, 1.0)
	verif.v(immobile == position,
		"sous le seuil de 1.0, bouger_vers ne doit pas bouger")

# bouger_selon avance SELON une direction deja donnee, sans jamais recalculer
# vers = cible - position -- aucune cible n'existe, donc aucun overshoot a
# borner (contrairement a bouger_vers) : le pas est toujours vitesse * delta
# plein tant qu'une direction existe. Vector3.ZERO (rien a fuir) laisse la
# position inchangee.
func _bouger_selon_avance_selon_une_direction_sans_cible() -> void:
	var position := Vector3(0, 0, 0)
	var avance := BancCommun.bouger_selon(position, Vector3(1, 0, 0), 10.0, 1.0)
	verif.v(avance.is_equal_approx(Vector3(10, 0, 0)),
		"bouger_selon doit avancer d'un pas plein (vitesse * delta) selon la direction")

	var immobile := BancCommun.bouger_selon(position, Vector3.ZERO, 10.0, 1.0)
	verif.v(immobile == position, "direction ZERO : bouger_selon ne doit pas deplacer le colon")

# Verrouille choses_a_fuir : parmi ce qui reste visible, ne retient que
# les entrees d'origine PROXIMITE (cle "chose") dont le verbe RESOLU
# POUR CETTE SEULE ENTREE (Agir.choisir sur une liste a un element) est
# oriente "fuite" dans orientations -- feu_fuite (propriete "brule",
# poids_verbes["s_eloigner"] positif) est retenu ; eau_calme (propriete
# "eau", verbe "approcher" jamais pese chez ce colon : action vide, donc
# orientation par defaut "declencheur") est ignore ; une entree d'origine
# ATTACHE (pas de "chose") est ignoree meme si presente, faute de
# position a fuir.
func _choses_a_fuir_filtre_par_verbe_resolu_oriente_fuite() -> void:
	var colon := {"proprietes": {"forme": {}, "poids_verbes": {"s_eloigner": 1.0, "approcher": 1.0}}}
	var catalogue_actions := {
		"brule": {"verbes": ["s_eloigner"]},
		"eau": {"verbes": ["approcher"]},
	}
	var orientations := {"s_eloigner": "fuite"}

	var feu_fuite := {"id": "feu_fuite", "position": Vector3(10, 0, 0), "proprietes": {"brule": true}}
	var eau_calme := {"id": "eau_calme", "position": Vector3(20, 0, 0), "proprietes": {"eau": true}}

	var visibles := [
		{"chose": feu_fuite, "type": "feu", "position": Vector3(10, 0, 0), "saillance": 2.0},
		{"chose": eau_calme, "type": "eau", "position": Vector3(20, 0, 0), "saillance": 1.5},
		{"type": "irremplacable", "attache": {"propriete": "irremplacable", "force": 3.0}, "menace": 0.6, "saillance": 5.0},
	]

	var choses := BancCommun.choses_a_fuir(visibles, colon, catalogue_actions, orientations, Monde.new())
	verif.v(choses.size() == 1, "un seul verbe resolu doit etre oriente fuite ici")
	if choses.size() == 1:
		verif.v(choses[0].position == Vector3(10, 0, 0) and choses[0].saillance == 2.0,
			"la chose retenue doit etre feu_fuite (brule -> s_eloigner), pas eau_calme ni l'attache")

# Verrouille verbe_action : la portee vient de proprietes.transformation
# de la CHOSE ciblee, resolue dans le catalogue transformations recu en
# parametre -- jamais d'un catalogue de choses par nom, jamais un rayon
# en dur. Portee choisie (42.0) deliberement differente de 0.0 et de 25.0
# (deja utilisee ailleurs dans le depot, data/transformations.json) : si
# un defaut ou une valeur recopiee par erreur s'y substituait, ce test le
# verrait.
func _verbe_action_resout_portee_depuis_la_transformation_de_la_chose() -> void:
	var transformations := {
		"decoration_test": {"portee_travail": 42.0},
	}
	var chose := {
		"id": "chose_test",
		"proprietes": {"travail_restant": 5.0, "transformation": "decoration_test"},
	}
	var colon := {"position": Vector3.ZERO}

	var a_portee := BancCommun.verbe_action(colon, Vector3(40, 0, 0), chose, transformations)
	verif.v(a_portee == "eteint",
		"distance 40 <= portee_travail 42 (resolue depuis la transformation de la chose) : eteint")

	var hors_portee := BancCommun.verbe_action(colon, Vector3(50, 0, 0), chose, transformations)
	verif.v(hors_portee == "va vers",
		"distance 50 > portee_travail 42 : va vers")

# Verrouille le cas qui touche directement le risque de defaut silencieux
# sur portee_travail : transfo.has("portee_travail") == false declenche
# push_error et un retour neutre "va vers", jamais un calcul avec 0.0.
# Distance choisie A ZERO expres : si un defaut 0.0 silencieux s'appliquait
# a portee, 0.0 <= 0.0 serait vrai et rendrait "eteint" -- exactement le
# faux positif qu'un defaut silencieux produirait, meme au pire cas.
func _verbe_action_alarme_sur_portee_travail_absente_sans_defaut_silencieux() -> void:
	var transformations := {
		"sans_portee": {},
	}
	var chose := {
		"id": "chose_sans_portee",
		"proprietes": {"travail_restant": 5.0, "transformation": "sans_portee"},
	}
	var colon := {"position": Vector3.ZERO}

	var resultat := BancCommun.verbe_action(colon, Vector3.ZERO, chose, transformations)
	verif.v(resultat == "va vers",
		"portee_travail absente de l'entree resolue : retour neutre 'va vers', " +
		"jamais 'eteint' par un 0.0 silencieux, meme a distance nulle")

# HORS DOMAINE (aucun colon, aucun feu -- des "zorgs" et des "flurbs") : le
# type peut etre FIXE pour tout un groupe, ou lu SUR CHAQUE CHOSE. La
# lecture par chose cherche d'abord dans proprietes, sinon a la racine --
# les deux emplacements sont exerces ici, sur la meme cle, pour que l'ordre
# soit verrouille et pas seulement documente.
func _monde_depuis_construit_par_groupes_et_resout_le_type_par_chose() -> void:
	var fixe_a := {"id": "zorg_1", "position": Vector3(0, 0, 0), "proprietes": {}}
	var fixe_b := {"id": "zorg_2", "position": Vector3(10, 0, 0), "proprietes": {}}
	var par_proprietes := {"id": "flurb_1", "position": Vector3(20, 0, 0), "proprietes": {"famille": "flurb_bleu"}}
	var par_racine := {"id": "flurb_2", "position": Vector3(30, 0, 0), "famille": "flurb_rouge", "proprietes": {}}

	var monde = BancCommun.monde_depuis([
		{"choses": [fixe_a, fixe_b], "type": "zorg"},
		{"choses": [par_proprietes, par_racine], "type_depuis": "famille"},
	])

	verif.v(monde.choses.size() == 4, "monde_depuis doit enregistrer toutes les choses de tous les groupes")
	verif.v(monde.par_id("zorg_1").type == "zorg" and monde.par_id("zorg_2").type == "zorg",
		"un groupe a type FIXE doit poser ce type sur chacune de ses choses")
	verif.v(monde.par_id("flurb_1").type == "flurb_bleu",
		"type_depuis doit lire la cle dans proprietes en priorite")
	verif.v(monde.par_id("flurb_2").type == "flurb_rouge",
		"type_depuis doit se rabattre sur la racine de la chose quand proprietes ne porte pas la cle")

	# RE-AJOUT PAR REFERENCE, jamais une copie : c'est ce qui fait qu'un monde
	# reconstruit garde positions, reserves et etats. Muter apres coup doit se
	# voir depuis le monde.
	fixe_a.proprietes["marque"] = 1.0
	verif.v(monde.par_id("zorg_1").chose.proprietes.has("marque"),
		"les choses doivent etre enregistrees PAR REFERENCE -- une copie ferait perdre l'etat a chaque reconstruction")

	# Absent de la liste d'appel, absent du resultat -- aucun retrait n'est
	# jamais demande a personne.
	var sans_b = BancCommun.monde_depuis([{"choses": [fixe_a], "type": "zorg"}])
	verif.v(sans_b.choses.size() == 1 and sans_b.par_id("zorg_1") != null,
		"une chose absente de la liste est absente du monde, sans qu'aucun retrait n'existe")

func _monde_depuis_alarme_sur_groupe_sans_choses() -> void:
	var bon := {"id": "zorg_3", "position": Vector3.ZERO, "proprietes": {}}
	var monde = BancCommun.monde_depuis([
		{"type": "zorg"},
		{"choses": [bon], "type": "zorg"},
	])
	verif.v(monde.choses.size() == 1,
		"un groupe sans 'choses' doit alarmer et etre saute, jamais rendre un monde silencieusement incomplet")

# VERROU NEGATIF, porte sur la FORME DU CODE et non sur un mot ecrit. Une ligne
# INDENTEE qui instancie Monde est du code de reconstruction ecrit a la main
# -- exactement ce que monde_depuis remplace. Une ligne a la COLONNE ZERO est
# une declaration de champ : elle construit le contenant une seule fois, elle
# ne le refait jamais, elle reste donc permise. banc_commun.gd est exclu :
# l'outil doit bien instancier quelque part.
func _aucun_banc_ne_fabrique_un_monde_dans_une_fonction() -> void:
	var dossier := DirAccess.open("res://scripts")
	if dossier == null:
		verif.v(false, "impossible d'ouvrir res://scripts pour le verrou negatif")
		return
	var fautifs: Array = []
	dossier.list_dir_begin()
	var nom := dossier.get_next()
	while nom != "":
		if not dossier.current_is_dir() and nom.begins_with("banc_") and nom.ends_with(".gd") and nom != "banc_commun.gd":
			var lignes := FileAccess.get_file_as_string("res://scripts/%s" % nom).split("\n")
			for i in lignes.size():
				var ligne: String = lignes[i]
				if ligne.find("Monde.new()") == -1:
					continue
				if not ligne.begins_with("\t") and not ligne.begins_with(" "):
					continue
				fautifs.append("%s:%d" % [nom, i + 1])
		nom = dossier.get_next()
	dossier.list_dir_end()
	fautifs.sort()
	verif.v(fautifs.is_empty(),
		"un banc ne fabrique jamais un Monde dans une fonction -- passer par BancCommun.monde_depuis. Fautifs : %s" % str(fautifs))
