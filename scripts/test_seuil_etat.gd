extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_seuil_etat.gd
#
# Verrouille scripts/seuil_etat.gd comme SEUIL D'ETAT REVERSIBLE GENERIQUE :
# compare une propriete continue deja presente sur l'objet (jamais calculee
# ici) a un seuil -- fixe OU lui-meme lu par objet -- et pose/retire UN
# SEUL nom d'etat au franchissement, dans un sens ou l'autre, symetriquement.
# Chaque entree du catalogue est TOTALEMENT INDEPENDANTE des autres : le
# fichier ne connait aucun nom de propriete ni d'etat, et ne fait jamais
# dependre la bascule d'une entree de ce qu'une autre a pose ou retire (voir
# CHOIX DE CONCEPTION en tete de seuil_etat.gd -- un premier jet a deux
# etats par entree laissait un etat intermediaire survivre a un grand saut
# de temperature en un seul appel, corrige en simplifiant a un etat par
# entree, entierement independante).
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu.

const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_sans_seuil_fourni_aucun_etat_pose(v)
	_catalogue_vide_aucun_etat_pose(v)
	_au_dessus_du_seuil_pose_letat(v)
	_rester_au_dessus_ne_rebascule_pas(v)
	_redescente_sous_le_seuil_retire_letat(v)
	_point_fusion_et_point_ebullition_coexistent_sans_conflit(v)
	_grand_saut_en_un_seul_appel_naisse_aucun_etat_incoherent(v)
	_objet_chaud_a_sa_malleabilite_moduleee(v)
	_objet_sans_point_fusion_ne_fond_jamais(v)
	_propriete_continue_absente_de_lobjet_chemin_mort(v)
	_le_modele_ignore_le_domaine(v)
	_deux_entrees_qui_partagent_le_meme_etat_ne_se_marchent_pas_dessus(v)
	_sublimation_passe_directement_de_solide_a_gaz_sans_liquide(v)
	_entree_sans_propriete_continue_ni_sans_etat_est_ignoree(v)
	_sublimation_redescente_repasse_directement_a_solide(v)
	_objet_sans_seuil_sublimation_nest_pas_affecte(v)
	_sublimation_coexiste_avec_point_fusion_point_ebullition_sans_conflit(v)
	_chemin_reel_glace_carbonique_sublime_sans_jamais_fondre(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: seuil d'etat reversible generique -- compare une propriete deja " +
			"presente a un seuil fixe ou lu par objet, pose/retire un nom d'etat au " +
			"franchissement dans les deux sens, plusieurs entrees independantes " +
			"coexistent sans conflit meme sur un grand saut en un seul appel, objet " +
			"sans seuil ne bascule jamais -- deux entrees qui partagent le meme nom " +
			"d'etat ne se marchent plus dessus (memoire par entree), sublimation " +
			"(seuil_sublimation) saute directement solide -> gaz sans jamais poser " +
			"'liquide', reversible, coexiste avec point_fusion/point_ebullition sur " +
			"un autre objet sans conflit, glace_carbonique (chemin reel, fabrique " +
			"par composition) le prouve")
		quit(0)

func _chose(id: String, valeurs: Dictionary, etats_actifs: Array = []) -> Dictionary:
	var proprietes := {"etats_actifs": etats_actifs.duplicate()}
	for cle in valeurs:
		proprietes[cle] = valeurs[cle]
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _entree(propriete_continue: String, seuil: Variant, etat: String, seuil_est_propriete: bool = false) -> Dictionary:
	var e := {"propriete_continue": propriete_continue, "etat": etat}
	if seuil_est_propriete:
		e["seuil_propriete"] = seuil
	else:
		e["seuil"] = seuil
	return e

func _sans_seuil_fourni_aucun_etat_pose(v) -> void:
	var entree := {"propriete_continue": "temperature", "etat": "chaud"}  # ni seuil ni seuil_propriete
	var monde := [_chose("a", {"temperature": 99999.0})]
	var b := SeuilEtat.avancer(monde, {"chaud": entree})
	v.v(b.is_empty(), "sans 'seuil' ni 'seuil_propriete' dans l'entree, aucune bascule ne doit se produire meme a temperature extreme")
	v.v(not monde[0].proprietes.etats_actifs.has("chaud"), "aucun etat ne doit jamais etre pose sans seuil resoluble")

func _catalogue_vide_aucun_etat_pose(v) -> void:
	var monde := [_chose("a", {"temperature": 99999.0})]
	var b := SeuilEtat.avancer(monde, {})
	v.v(b.is_empty(), "un catalogue vide ne doit jamais produire de bascule")
	v.v(monde[0].proprietes.etats_actifs.is_empty(), "un catalogue vide ne doit jamais poser d'etat")

# DEUX CHAMPS SANS LESQUELS UNE ENTREE N'A AUCUN SENS : la grandeur a
# comparer et l'etat a poser. L'un ou l'autre absent, l'entree est ignoree
# APRES alarme -- jamais un etat pose sur une comparaison qui n'a pas eu
# lieu, jamais un etat sans nom.
func _entree_sans_propriete_continue_ni_sans_etat_est_ignoree(v) -> void:
	var sans_propriete := {"zorg": {"seuil": 0.0, "etat": "zorgue"}}
	var monde_a := [_chose("a", {"temperature": 99999.0})]
	v.v(SeuilEtat.avancer(monde_a, sans_propriete).is_empty(),
		"entree sans 'propriete_continue' : alarme puis ignoree, jamais une bascule")
	v.v(monde_a[0].proprietes.etats_actifs.is_empty(),
		"entree sans 'propriete_continue' : aucun etat pose")

	var sans_etat := {"zorg": {"propriete_continue": "temperature", "seuil": 0.0}}
	var monde_b := [_chose("b", {"temperature": 99999.0})]
	v.v(SeuilEtat.avancer(monde_b, sans_etat).is_empty(),
		"entree sans 'etat' : alarme puis ignoree, jamais un etat sans nom")
	v.v(monde_b[0].proprietes.etats_actifs.is_empty(),
		"entree sans 'etat' : aucun etat pose")

func _au_dessus_du_seuil_pose_letat(v) -> void:
	var catalogue := {"chaud": _entree("temperature", 150.0, "chaud")}
	var monde := [_chose("a", {"temperature": 200.0})]
	var b := SeuilEtat.avancer(monde, catalogue)
	v.v(b.has("a"), "franchir le seuil vers le haut doit rendre l'id de la chose")
	v.v(monde[0].proprietes.etats_actifs.has("chaud"), "au-dessus du seuil, l'etat 'chaud' doit etre pose")

func _rester_au_dessus_ne_rebascule_pas(v) -> void:
	var catalogue := {"chaud": _entree("temperature", 150.0, "chaud")}
	var monde := [_chose("a", {"temperature": 200.0}, ["chaud"])]
	var b := SeuilEtat.avancer(monde, catalogue)
	v.v(b.is_empty(), "rester au-dessus du seuil ne doit plus rebasculer")
	v.v(monde[0].proprietes.etats_actifs.has("chaud"), "l'etat deja pose doit rester pose")

func _redescente_sous_le_seuil_retire_letat(v) -> void:
	var catalogue := {"fusion": _entree("temperature", 1000.0, "liquide")}
	var monde := [_chose("a", {"temperature": 500.0}, ["liquide"])]
	var b := SeuilEtat.avancer(monde, catalogue)
	var actifs: Array = monde[0].proprietes.etats_actifs
	v.v(b.has("a"), "franchir le seuil vers le bas doit rendre l'id de la chose")
	v.v(not actifs.has("liquide"), "repasser sous le seuil doit retirer l'etat")

func _point_fusion_et_point_ebullition_coexistent_sans_conflit(v) -> void:
	var catalogue := {
		"point_fusion": _entree("temperature", 1000.0, "liquide"),
		"point_ebullition": _entree("temperature", 2000.0, "gaz"),
	}
	var monde := [_chose("metal", {"temperature": 20.0})]

	# Entre les deux seuils : liquide seul.
	monde[0].proprietes.temperature = 1500.0
	SeuilEtat.avancer(monde, catalogue)
	var actifs: Array = monde[0].proprietes.etats_actifs
	v.v(actifs.has("liquide") and not actifs.has("gaz"), "entre point_fusion et point_ebullition, seul 'liquide' doit etre actif")

	# Au-dela des deux seuils : les deux etats coexistent -- CONSEQUENCE
	# ASSUMEE (voir data/seuils_etat.json), physiquement correct : au-dela
	# du point d'ebullition, on est aussi au-dela du point de fusion.
	monde[0].proprietes.temperature = 3000.0
	var b := SeuilEtat.avancer(monde, catalogue)
	actifs = monde[0].proprietes.etats_actifs
	v.v(b.has("metal"), "franchir point_ebullition doit rendre l'id")
	v.v(actifs.has("liquide") and actifs.has("gaz"), "au-dela des deux seuils, 'liquide' ET 'gaz' doivent etre actifs en meme temps, sans qu'aucune entree ne retire l'etat de l'autre")

	# Redescente sous les deux : plus aucun des deux.
	monde[0].proprietes.temperature = 500.0
	SeuilEtat.avancer(monde, catalogue)
	actifs = monde[0].proprietes.etats_actifs
	v.v(not actifs.has("liquide") and not actifs.has("gaz"), "sous les deux seuils, ni liquide ni gaz ne doivent rester actifs")

# LE BUG CONSTATE A L'ECRITURE (voir seuil_etat.gd, CHOIX DE CONCEPTION) :
# un design a deux etats par entree laissait un etat intermediaire survivre
# a un grand saut EN UN SEUL APPEL. Verrouille que le design a un seul etat
# par entree, lui, converge TOUJOURS correctement en un seul appel, quelle
# que soit l'ampleur du saut -- monte de 20 a 3000 (au-dela des deux
# seuils) puis retombe direct a 500 (sous les deux) EN DEUX APPELS SEULS,
# jamais besoin d'un pas intermediaire.
func _grand_saut_en_un_seul_appel_naisse_aucun_etat_incoherent(v) -> void:
	var catalogue := {
		"point_fusion": _entree("temperature", 1000.0, "liquide"),
		"point_ebullition": _entree("temperature", 2000.0, "gaz"),
	}
	var monde := [_chose("metal", {"temperature": 20.0})]
	monde[0].proprietes.temperature = 3000.0
	SeuilEtat.avancer(monde, catalogue)
	v.v(monde[0].proprietes.etats_actifs.has("liquide") and monde[0].proprietes.etats_actifs.has("gaz"), "un saut direct de 20 a 3000 (au-dela des deux seuils) doit poser les deux etats en un seul appel")

	# Le saut de retour, direct, en un seul appel : plus aucun etat.
	monde[0].proprietes.temperature = 20.0
	SeuilEtat.avancer(monde, catalogue)
	var actifs: Array = monde[0].proprietes.etats_actifs
	v.v(not actifs.has("liquide") and not actifs.has("gaz"), "un saut direct de 3000 a 20 (sous les deux seuils) doit retirer les deux etats en un seul appel, sans qu'aucun ne survive")

func _objet_chaud_a_sa_malleabilite_moduleee(v) -> void:
	var catalogue_seuils := {"chaud": _entree("temperature", 150.0, "chaud")}
	var etats := {"chaud": {"effets": [{"propriete": "malleabilite", "mode": "moduler", "facteur": 1.3}]}}
	var monde := [_chose("barre", {"temperature": 300.0, "malleabilite": 0.7})]
	SeuilEtat.avancer(monde, catalogue_seuils)
	var effective: float = EtatEffectif.valeur(monde[0], "malleabilite", etats)
	v.v(monde[0].proprietes.etats_actifs.has("chaud"), "l'objet chauffe doit porter l'etat 'chaud'")
	v.v(is_equal_approx(effective, 0.7 * 1.3), "une fois 'chaud', la malleabilite EFFECTIVE doit etre moduleee par le facteur du catalogue, recu %f" % effective)

func _objet_sans_point_fusion_ne_fond_jamais(v) -> void:
	var catalogue := {"point_fusion": _entree("temperature", "point_fusion", "liquide", true)}
	var monde := [_chose("bois", {"temperature": 99999.0})]  # PAS de "point_fusion" sur cet objet
	var b := SeuilEtat.avancer(monde, catalogue)
	v.v(b.is_empty(), "un objet sans 'point_fusion' ne doit jamais basculer, meme a temperature extreme")
	v.v(not monde[0].proprietes.etats_actifs.has("liquide"), "sans 'point_fusion' sur l'objet, 'liquide' ne doit jamais etre pose -- repli sur INF, jamais un seuil devine")

func _propriete_continue_absente_de_lobjet_chemin_mort(v) -> void:
	var catalogue := {"chaud": _entree("temperature", 150.0, "chaud")}
	var monde := [{"id": "sans_temperature", "position": Vector3.ZERO, "proprietes": {}}]
	var b := SeuilEtat.avancer(monde, catalogue)
	v.v(b.is_empty(), "un objet sans la propriete continue nommee doit traverser le mecanisme sans bascule")
	v.v(not monde[0].proprietes.has("etats_actifs"), "aucune cle etats_actifs ne doit apparaitre sur un objet qui n'avait rien a comparer")

# LA serrure generaliste : une propriete et un seuil sans aucun rapport
# avec la temperature ou la matiere traversent le meme code -- le fichier
# ne lit jamais le nom "temperature", "point_fusion" ni "chaud".
func _le_modele_ignore_le_domaine(v) -> void:
	var catalogue := {"seuil_pression": _entree("pression_atmospherique", 1050.0, "depression")}
	var monde := [_chose("station_meteo", {"pression_atmospherique": 1080.0}, ["accalmie"])]
	var b := SeuilEtat.avancer(monde, catalogue)
	var actifs: Array = monde[0].proprietes.etats_actifs
	v.v(b.has("station_meteo"), "hors domaine (pression atmospherique, rien a voir avec la chaleur) : le meme code doit basculer")
	v.v(actifs.has("depression"), "hors domaine : l'etat du dessus doit etre pose, exactement comme point_fusion/chaud")
	v.v(actifs.has("accalmie"), "hors domaine : un etat sans rapport avec cette entree (deja pose ailleurs) ne doit jamais etre touche -- chaque entree est INDEPENDANTE")

# ---- Memoire par entree (chantier "transitions directes solide<->gaz") :
# bug constate a l'ecriture -- deux entrees visant le MEME nom d'etat, l'une
# reellement applicable, l'autre non (repli INF), sur le MEME objet. Avec
# l'ancienne memoire LUE depuis etats_actifs partage, l'entree non
# applicable relisait "actif" (pose par l'AUTRE entree) et l'EFFACAIT au
# meme appel. Verrouille que ce n'arrive plus jamais : une entree qui ne
# franchit JAMAIS son propre seuil ne doit RIEN faire, quel que soit ce
# qu'une autre entree pose sous le meme nom, sur PLUSIEURS appels
# consecutifs (pas seulement le premier). ----
func _deux_entrees_qui_partagent_le_meme_etat_ne_se_marchent_pas_dessus(v) -> void:
	var catalogue := {
		"applicable": _entree("temperature", 2000.0, "gaz"),
		"jamais_applicable": _entree("temperature", "seuil_absent", "gaz", true),  # PAS sur l'objet -- repli INF
	}
	var monde := [_chose("metal", {"temperature": 20.0})]

	monde[0].proprietes.temperature = 3000.0
	var b := SeuilEtat.avancer(monde, catalogue)
	v.v(b.has("metal"), "franchir le seuil applicable doit rendre l'id")
	v.v(monde[0].proprietes.etats_actifs.has("gaz"), "l'entree applicable doit poser 'gaz' -- l'entree jamais applicable (INF) ne doit pas l'empecher")

	# Un DEUXIEME appel, sans rien changer -- l'entree non applicable relit
	# desormais SA PROPRE memoire (deja ecrite au premier appel), plus
	# jamais 'etats_actifs' -- elle ne doit RIEN faire, meme si 'gaz' y est
	# toujours present depuis l'AUTRE entree.
	var b2 := SeuilEtat.avancer(monde, catalogue)
	v.v(b2.is_empty(), "rien n'a change -- aucune bascule ne doit se produire au deuxieme appel")
	v.v(monde[0].proprietes.etats_actifs.has("gaz"), "'gaz' doit rester actif -- l'entree jamais applicable ne doit JAMAIS l'effacer, meme un appel plus tard")

	# Redescente : seule l'entree applicable doit retirer 'gaz'.
	monde[0].proprietes.temperature = 20.0
	SeuilEtat.avancer(monde, catalogue)
	v.v(not monde[0].proprietes.etats_actifs.has("gaz"), "sous le seuil applicable, 'gaz' doit etre retire par l'entree qui l'avait pose")

# ---- Sublimation (chantier "transitions directes solide<->gaz",
# data/seuils_etat.json:sublimation) : AUCUN champ neuf dans seuil_etat.gd
# -- une entree de plus, seuil_propriete different (seuil_sublimation),
# MEME nom d'etat que point_ebullition ("gaz"), rendu SUR par la memoire
# par entree ci-dessus. Le saut direct solide -> gaz vient du fait qu'un
# materiau qui sublime (glace_carbonique) porte un point_fusion/
# point_ebullition fusionnes a 0.0 (absents de sa fiche) -- jamais franchis
# aux temperatures de demonstration (toutes negatives, voir
# data/materiaux.json:glace_carbonique). ----

func _sublimation_passe_directement_de_solide_a_gaz_sans_liquide(v) -> void:
	var catalogue := {
		"point_fusion": _entree("temperature", "point_fusion", "liquide", true),
		"point_ebullition": _entree("temperature", "point_ebullition", "gaz", true),
		"sublimation": _entree("temperature", "seuil_sublimation", "gaz", true),
	}
	# PAS de "point_fusion"/"point_ebullition" sur cet objet -- seul
	# "seuil_sublimation" est present, meme convention que glace_carbonique.
	var monde := [_chose("glace_seche", {"temperature": -100.0, "seuil_sublimation": -78.5})]
	monde[0].proprietes.temperature = 20.0
	var b := SeuilEtat.avancer(monde, catalogue)
	var actifs: Array = monde[0].proprietes.etats_actifs
	v.v(b.has("glace_seche"), "franchir seuil_sublimation vers le haut doit rendre l'id")
	v.v(actifs.has("gaz"), "au-dessus de seuil_sublimation, l'objet doit devenir gazeux")
	v.v(not actifs.has("liquide"), "un objet qui sublime ne doit JAMAIS passer par 'liquide' -- point_fusion absent de l'objet replie sur INF, jamais franchi")

func _sublimation_redescente_repasse_directement_a_solide(v) -> void:
	var catalogue := {"sublimation": _entree("temperature", "seuil_sublimation", "gaz", true)}
	var monde := [_chose("glace_seche", {"temperature": 20.0, "seuil_sublimation": -78.5}, ["gaz"])]
	monde[0].proprietes.temperature = -100.0
	var b := SeuilEtat.avancer(monde, catalogue)
	var actifs: Array = monde[0].proprietes.etats_actifs
	v.v(b.has("glace_seche"), "franchir seuil_sublimation vers le bas doit rendre l'id")
	v.v(not actifs.has("gaz"), "sous seuil_sublimation, 'gaz' doit etre retire -- l'objet redevient solide par ABSENCE de liquide/gaz, jamais un etat 'solide' pose")
	v.v(not actifs.has("liquide"), "la condensation solide ne doit jamais avoir pose 'liquide' -- aucune entree de ce catalogue ne le fait pour cet objet")

func _objet_sans_seuil_sublimation_nest_pas_affecte(v) -> void:
	var catalogue := {"sublimation": _entree("temperature", "seuil_sublimation", "gaz", true)}
	var monde := [_chose("fer", {"temperature": 99999.0})]  # PAS de "seuil_sublimation" sur cet objet
	var b := SeuilEtat.avancer(monde, catalogue)
	v.v(b.is_empty(), "un objet sans 'seuil_sublimation' ne doit jamais basculer par cette entree, meme a temperature extreme")
	v.v(not monde[0].proprietes.etats_actifs.has("gaz"), "sans 'seuil_sublimation' sur l'objet, 'gaz' ne doit jamais etre pose par cette entree -- repli sur INF, jamais un seuil devine")

func _sublimation_coexiste_avec_point_fusion_point_ebullition_sans_conflit(v) -> void:
	var catalogue := {
		"point_fusion": _entree("temperature", "point_fusion", "liquide", true),
		"point_ebullition": _entree("temperature", "point_ebullition", "gaz", true),
		"sublimation": _entree("temperature", "seuil_sublimation", "gaz", true),
	}
	# Deux objets DANS LE MEME monde, meme catalogue PARTAGE -- un metal qui
	# fond/bout normalement, une glace seche qui sublime -- aucune entree ne
	# doit lire ni modifier les proprietes de l'AUTRE objet.
	var metal := _chose("metal", {"temperature": 3000.0, "point_fusion": 1000.0, "point_ebullition": 2000.0})
	var glace_seche := _chose("glace_seche", {"temperature": -100.0, "seuil_sublimation": -78.5})
	var monde := [metal, glace_seche]
	SeuilEtat.avancer(monde, catalogue)
	v.v(metal.proprietes.etats_actifs.has("liquide") and metal.proprietes.etats_actifs.has("gaz"), "le metal doit fondre et bouillir normalement, aucune interference de l'entree sublimation (il n'a pas 'seuil_sublimation')")
	v.v(not glace_seche.proprietes.etats_actifs.has("gaz"), "a -100 deg C, sous son seuil de sublimation (-78.5), la glace seche ne doit pas etre gazeuse")
	v.v(not glace_seche.proprietes.etats_actifs.has("liquide"), "la glace seche ne doit jamais porter 'liquide', quel que soit l'etat du metal voisin dans le meme monde")

	glace_seche.proprietes.temperature = -50.0
	SeuilEtat.avancer(monde, catalogue)
	v.v(glace_seche.proprietes.etats_actifs.has("gaz"), "la glace seche doit sublimer une fois au-dessus de son propre seuil, independamment du metal")
	v.v(not glace_seche.proprietes.etats_actifs.has("liquide"), "meme gazeuse, la glace seche ne doit jamais avoir porte 'liquide'")
	v.v(metal.proprietes.etats_actifs.has("liquide") and metal.proprietes.etats_actifs.has("gaz"), "le metal doit rester INCHANGE -- la bascule de la glace seche ne doit rien lui faire")

# ---- Chemin reel : glace_carbonique (data/materiaux.json), fabriquee PAR
# COMPOSITION (jamais un seuil_sublimation pose a la main), catalogue reel
# data/seuils_etat.json lu sur disque -- meme discipline que
# test_banc_changement_etat.gd:_chemin_reel_le_fer_traverse_toutes_les_phases.
func _chemin_reel_glace_carbonique_sublime_sans_jamais_fondre(v) -> void:
	var seuils: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_etat.json"))
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])

	var catalogue_types := {"glace_test": {"composition": [{"materiau": "glace_carbonique", "volume": 1.0}]}}
	var objet := Objet.fabriquer("glace_test", "glace_test", Vector3.ZERO, catalogue_types, materiaux, proprietes_immuables)
	v.v(not objet.is_empty(), "chemin reel : la glace carbonique doit se fabriquer normalement")
	v.v(is_equal_approx(float(objet.proprietes.seuil_sublimation), -78.5), "chemin reel : seuil_sublimation doit venir de la fusion generique (glace_carbonique, -78.5), sans etre pose a la main, recu %f" % objet.proprietes.seuil_sublimation)
	v.v(is_equal_approx(float(objet.proprietes.point_fusion), 0.0), "chemin reel : glace_carbonique ne declare aucun point_fusion sur sa fiche -- la moyenne ponderee generique doit contribuer 0.0, jamais un seuil devine, recu %f" % objet.proprietes.point_fusion)

	# Chemin reel BOIS/PIERRE/FER, meme catalogue partage : leur
	# seuil_sublimation EXPLICITE (9999.0, voir data/materiaux.json) doit
	# venir de leur propre fiche, jamais du defaut 0.0 generique -- sinon
	# ils "subliment" a temperature ambiante, regression que ce chemin reel
	# verrouille en plus de glace_carbonique.
	var fer := Objet.fabriquer("fer_test", "fer_test", Vector3.ZERO, {"fer_test": {"composition": [{"materiau": "fer", "volume": 1.0}]}}, materiaux, proprietes_immuables)
	v.v(is_equal_approx(float(fer.proprietes.seuil_sublimation), 9999.0), "chemin reel : le fer doit fusionner son seuil_sublimation explicite (9999.0), jamais le defaut 0.0 generique, recu %f" % fer.proprietes.seuil_sublimation)
	fer.proprietes["temperature"] = 20.0
	fer.proprietes["etats_actifs"] = []
	var monde_fer := [fer]
	SeuilEtat.avancer(monde_fer, seuils)
	v.v(not fer.proprietes.etats_actifs.has("gaz"), "chemin reel : le fer a temperature ambiante (20 deg C) ne doit JAMAIS etre gazeux -- son seuil_sublimation explicite (9999.0) est loin au-dessus")

	objet.proprietes["temperature"] = -100.0
	objet.proprietes["etats_actifs"] = []
	var monde := [objet]

	objet.proprietes.temperature = -20.0
	var b := SeuilEtat.avancer(monde, seuils)
	v.v(b.has("glace_test"), "chemin reel : franchir -78.5 vers le haut doit rendre l'id")
	v.v(objet.proprietes.etats_actifs.has("gaz"), "chemin reel : au-dessus de -78.5, la glace carbonique reelle doit devenir gazeuse")
	v.v(not objet.proprietes.etats_actifs.has("liquide"), "chemin reel : la glace carbonique ne doit JAMAIS porter 'liquide' -- point_fusion fusionne a 0.0, jamais franchi a -20 deg C")

	objet.proprietes.temperature = -100.0
	SeuilEtat.avancer(monde, seuils)
	v.v(not objet.proprietes.etats_actifs.has("gaz"), "chemin reel : sous -78.5, la glace carbonique doit redevenir solide (retrait de 'gaz')")
	v.v(not objet.proprietes.etats_actifs.has("liquide"), "chemin reel : la condensation solide ne doit jamais avoir pose 'liquide'")
