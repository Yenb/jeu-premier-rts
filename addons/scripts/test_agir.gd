extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_agir.gd
#
# Verrouille agir.gd : inertie -- a saillance egale, la tache en cours
# (action_en_cours) reste. Comparee par ID quand action_en_cours en porte
# un (saillance de proximite, une chose precise), par TYPE sinon
# (saillance d'attache, sans identite). Un ecart de saillance strictement
# superieur au bonus d'inertie fait ceder, dans les deux cas. Un seul
# visible s'impose sans comparaison ; rien de visible ne rend rien.
# Verrouille aussi _action : une entree de catalogue non vide sans cle
# "verbes" (catalogue malforme) rend une action vide comme une entree
# absente, distinction que seul push_error (non observable ici) separe --
# voir CARTE.md §2, agir.gd.
# Verrouille la resolution de la collision E (CARTE.md §6) : un arbre
# irremplacable qui brule (scenario reel) ne resout plus qu'un seul verbe
# candidat ("approcher" via "brule") depuis que data/types_attaches.json
# ne porte plus les cles irremplacable/notre_ouvrage (verbe mort "defendre"
# retire) -- catalogue AVANT/APRES construits explicitement ici pour
# montrer la difference, l'alarme push_error de la fixture n'etant pas
# observable depuis ce test.

const Agir = preload("res://scripts/agir.gd")
const Verif = preload("res://scripts/verif.gd")
const Monde = preload("res://scripts/monde.gd")

var verif := Verif.new()
var monde_vide := Monde.new()

func _init() -> void:
	var catalogue := {
		"type_a": {"verbes": ["action_a"]},
		"type_b": {"verbes": ["action_b"]},
		"feu": {"verbes": ["eteindre"]},
	}

	# --- Sans id (saillance d'attache) : comparaison par type ---

	var colon_sans_id := {
		"proprietes": {
			"forme": {"gain_inertie": 1.0},
			"poids_verbes": {"action_a": 1.0, "action_b": 1.0},
		},
		"action_en_cours": {"type": "type_a"},
	}

	# Saillance egale, aucun id des deux cotes : la tache en cours (par type) reste.
	# type_a (action_en_cours) est pose EN SECOND expres : la comparaison de
	# choisir() est stricte (score > meilleur_score), donc le premier element
	# du tableau gagne toute egalite par defaut, inertie ou pas. Si type_a
	# etait premier, ce scenario passerait meme a gain_inertie=0.0 (verifie :
	# il passait). Le poser second force le bonus d'inertie a faire le travail
	# pour que ce test cede a l'ecart -- sinon il ne verrouille que l'ordre.
	var visibles_egales := [
		{"type": "type_b", "attache": {"type": "type_b"}, "menace": 0.5, "saillance": 1.5},
		{"type": "type_a", "attache": {"type": "type_a"}, "menace": 0.5, "saillance": 1.5},
	]
	var retenu_egal = Agir.choisir(visibles_egales, colon_sans_id, catalogue, monde_vide)
	verif.v(retenu_egal.action == "action_a", "sans id, saillance egale : reste sur le type en cours")

	# Ecart de saillance superieur au bonus : ca cede, meme sans id.
	var visibles_ecart := [
		{"type": "type_a", "attache": {"type": "type_a"}, "menace": 0.5, "saillance": 1.5},
		{"type": "type_b", "attache": {"type": "type_b"}, "menace": 0.9, "saillance": 3.0},
	]
	var retenu_ecart = Agir.choisir(visibles_ecart, colon_sans_id, catalogue, monde_vide)
	verif.v(retenu_ecart.action == "action_b", "sans id, ecart de saillance : ca cede")

	# --- Avec id (saillance de proximite) : comparaison par id, jamais par type ---

	var colon_avec_id := {
		"proprietes": {"forme": {"gain_inertie": 1.0}},
		"action_en_cours": {"id": "feu_2", "position": Vector3.ZERO, "type": "feu"},
	}

	# Deux visibles du MEME type, ids differents, saillances egales : celui dont
	# l'id est dans action_en_cours doit gagner -- le type seul ne distingue pas
	# deux feux. Ce cas echoue avec l'ancienne comparaison par type seul.
	var visibles_deux_feux := [
		{"chose": {"id": "feu_1", "proprietes": {}}, "type": "feu", "position": Vector3.ZERO, "saillance": 2.0},
		{"chose": {"id": "feu_2", "proprietes": {}}, "type": "feu", "position": Vector3.ZERO, "saillance": 2.0},
	]
	var retenu_id = Agir.choisir(visibles_deux_feux, colon_avec_id, catalogue, monde_vide)
	verif.v(retenu_id.chose.id == "feu_2", "avec id, saillance egale : reste sur la chose visee, pas sur le type")

	# Ecart de saillance superieur au bonus : ca cede aussi avec id.
	var visibles_ecart_id := [
		{"chose": {"id": "feu_2", "proprietes": {}}, "type": "feu", "position": Vector3.ZERO, "saillance": 2.0},
		{"chose": {"id": "feu_3", "proprietes": {}}, "type": "feu", "position": Vector3.ZERO, "saillance": 4.0},
	]
	var retenu_ecart_id = Agir.choisir(visibles_ecart_id, colon_avec_id, catalogue, monde_vide)
	verif.v(retenu_ecart_id.chose.id == "feu_3", "avec id, ecart de saillance : ca cede")

	# --- Entree de catalogue malformee : presente mais sans "verbes" ---
	# Distinct de decl == {} (aucune entree, chose ordinaire, legitime,
	# silencieux) : ici l'entree existe mais est mal formee -- push_error
	# (non observable depuis ce test, voir verif.gd), puis meme retour
	# neutre "" que le cas legitime. Non exerce ailleurs dans le depot.
	var catalogue_malforme := {
		"type_a": {"cout": 5},
	}
	var visible_malforme := [
		{"type": "type_a", "attache": {"type": "type_a"}, "menace": 0.0, "saillance": 0.4},
	]
	var retenu_malforme = Agir.choisir(visible_malforme, colon_sans_id, catalogue_malforme, monde_vide)
	verif.v(retenu_malforme.action == "", "entree de catalogue non vide sans verbes : action vide (alarme push_error), pas un defaut silencieux")

	# --- Collision E (CARTE.md §6, resolue par retrait du verbe mort "defendre") ---
	# Scenario reel : un arbre irremplacable qui brule porte SIMULTANEMENT
	# irremplacable:true et brule:true (propagation.gd pose "brule" sans
	# jamais retirer "irremplacable"). _action (branche PROXIMITE) scanne
	# les CLES du catalogue dans l'ordre d'insertion et s'arrete au premier
	# match (break) -- si "irremplacable"/"notre_ouvrage" restent des cles
	# du catalogue fusionne (meme videes de leur "verbes"), le scan s'y
	# arrete AVANT d'atteindre "brule", quel que soit le contenu de l'entree.
	#
	# AVANT (etat historique, data/types_attaches.json portait encore
	# "irremplacable"/"notre_ouvrage" -> verbes:["defendre"]) : demontre ici
	# en construisant EXPLICITEMENT ce catalogue -- aucun colon reel ne pese
	# "defendre" (verbe mort, voir CARTE.md §6), donc l'action resolue est
	# vide meme si l'arbre brule et que ce colon valorise "approcher".
	var arbre_en_feu := {"id": "arbre_defendu", "proprietes": {"irremplacable": true, "brule": true}}
	var visible_arbre := {"chose": arbre_en_feu, "type": "arbre", "position": Vector3.ZERO, "saillance": 3.0}
	var fanatique_reel := {"proprietes": {"forme": {}, "poids_verbes": {"approcher": 1.0}}}
	var placide_reel := {"proprietes": {"forme": {}, "poids_verbes": {}}}

	var catalogue_avant := {
		"irremplacable": {"verbes": ["defendre"]},
		"notre_ouvrage": {"verbes": ["defendre"]},
		"brule": {"verbes": ["approcher"]},
	}
	var avant_e = Agir.choisir([visible_arbre], fanatique_reel, catalogue_avant, monde_vide)
	verif.v(avant_e.action == "",
		"AVANT (etat historique) : le scan s'arrete sur 'irremplacable' avant 'brule' -- " +
		"'defendre' n'est jamais pese -> action vide, l'arbre en feu n'est pas rejoint")

	# APRES : data/types_attaches.json ne porte plus DU TOUT les cles
	# irremplacable/notre_ouvrage (verbe mort retire, pas seulement sa liste
	# "verbes" videe -- voir constat CARTE.md §6). Le catalogue fusionne reel
	# ne contient donc plus que "brule" : le scan l'atteint directement, plus
	# de collision a deux proprietes actionnables sur la meme chose.
	var catalogue_apres := {"brule": {"verbes": ["approcher"]}}
	var apres_e_fanatique = Agir.choisir([visible_arbre], fanatique_reel, catalogue_apres, monde_vide)
	verif.v(apres_e_fanatique.action == "approcher",
		"APRES : plus qu'une propriete actionnable (brule) -- le fanatique approche l'arbre en feu")

	var apres_e_placide = Agir.choisir([visible_arbre], placide_reel, catalogue_apres, monde_vide)
	verif.v(apres_e_placide.action == "",
		"APRES : le placide (poids_verbes vide) n'a toujours d'avis sur rien -- pas de regression")

	# --- F (CARTE.md §6) : egalite stricte au poids maximum entre deux verbes ---
	# _verbe_par_poids alarme (push_error) quand deux verbes du MEME decl.verbes
	# atteignent le meme poids maximum strictement positif, PUIS conserve le
	# comportement actuel (premier verbe declare l'emporte) -- on ne tranche
	# pas, on refuse le silence. push_error n'est pas observable depuis ce
	# test (voir verif.gd) : ce test verrouille le RETOUR (inchange, premier
	# declare), l'emission de l'alarme se verifie par lecture de code
	# (agir.gd:_verbe_par_poids).
	var catalogue_egalite := {
		"type_e": {"verbes": ["v1", "v2"]},
	}
	var colon_egalite := {
		"proprietes": {"forme": {}, "poids_verbes": {"v1": 2.0, "v2": 2.0}},
	}
	var visible_egalite := [
		{"type": "type_e", "attache": {"type": "type_e"}, "menace": 0.0, "saillance": 0.5},
	]
	var retenu_egalite = Agir.choisir(visible_egalite, colon_egalite, catalogue_egalite, monde_vide)
	verif.v(retenu_egalite.action == "v1",
		"F : deux verbes a egalite stricte au poids max -- alarme (non observable ici), premier declare conserve")

	# --- etat_courant : ce que decider_et_memoriser (banc_p1.gd/banc_feu.gd)
	# ecrit sur action_en_cours pour le tick suivant. Deux lecteurs, pas un :
	# l'inertie ci-dessus (type, id) ET le LLM lecteur-de-scene (voir
	# docs/design.md, "action_en_cours vit hors de proprietes"), qui a besoin
	# de position pour ancrer sa description -- retirer position parce que
	# l'inertie l'ignore casserait ce second lecteur (piege deja tombe une
	# fois, ce verrou empeche la recidive).

	var decision_avec_position := {
		"chose": {"id": "feu_5", "proprietes": {}},
		"type": "feu",
		"position": Vector3(10, 20, 0),
		"saillance": 2.0,
	}
	var etat_avec_position := Agir.etat_courant(decision_avec_position)
	verif.v(etat_avec_position.get("position") == Vector3(10, 20, 0),
		"etat_courant doit porter position quand la decision en porte une -- l'LLM lecteur-de-scene en a besoin, meme si l'inertie l'ignore")

	var decision_sans_position := {
		"type": "irremplacable",
		"attache": {"type": "irremplacable", "force": 3.0},
		"menace": 0.6,
		"saillance": 5.0,
	}
	var etat_sans_position := Agir.etat_courant(decision_sans_position)
	verif.v(not etat_sans_position.has("position"),
		"etat_courant ne doit pas inventer une position pour une origine attache, qui n'en porte jamais")

	verif.v(Agir.etat_courant(null) == {}, "etat_courant(null) : rien de visible, rien a memoriser")

	# --- Cas deja verrouilles : un seul visible, rien de visible ---

	var visible_seul := [
		{"type": "type_c", "attache": {"type": "type_c"}, "menace": 0.0, "saillance": 0.4},
	]
	var retenu_seul = Agir.choisir(visible_seul, colon_sans_id, catalogue, monde_vide)
	verif.v(retenu_seul.type == "type_c", "un seul visible : il y va")

	var retenu_vide = Agir.choisir([], colon_sans_id, catalogue, monde_vide)
	verif.v(retenu_vide == null, "rien de visible : rien retenu")

	# --- Engagement (couplage.gd, PHASE 1) : bonus additif + reinjection ---
	# gain_inertie reste a 0.0 ici expres : ces cas verrouillent l'engagement
	# seul, sans que l'inertie de personnalite ne puisse expliquer le resultat.

	# Bonus additif : la cible engagee est deja visible (pas de reinjection
	# necessaire), son poids d'engagement la fait gagner malgre une saillance
	# de depart plus basse que l'alternative.
	var colon_engage := {
		"proprietes": {
			"forme": {},
			"poids_verbes": {"eteindre": 1.0},
			"engagement": {"cible_id": "bloc_1", "poids": 5.0},
		},
	}
	var visibles_avec_engagee := [
		{"chose": {"id": "bloc_1", "proprietes": {}}, "type": "bloc", "position": Vector3.ZERO, "saillance": 1.0},
		{"chose": {"id": "feu_9", "proprietes": {}}, "type": "feu", "position": Vector3.ZERO, "saillance": 3.0},
	]
	var retenu_engage = Agir.choisir(visibles_avec_engagee, colon_engage, catalogue, monde_vide)
	verif.v(retenu_engage.chose.id == "bloc_1",
		"engagement : 1.0 + poids 5.0 (6.0) bat 3.0 -- la cible engagee gagne malgre une saillance de depart plus basse")

	# Reinjection : la cible engagee est GELEE (absente de visibles, comme un
	# chantier occupe dont proximite.gd n'a rendu aucune entree). Sans
	# reinjection, son id n'apparaitrait jamais et l'engagement ne pourrait
	# jamais peser -- c'est exactement le bug d'oscillation ferme ici.
	var monde_reinjection := Monde.new()
	var bloc_gele := {"id": "bloc_gele", "position": Vector3.ZERO, "proprietes": {"cassable": true}}
	monde_reinjection.ajouter(bloc_gele, "bloc", Vector3.ZERO)
	var colon_engage_gele := {
		"proprietes": {
			"forme": {},
			"poids_verbes": {"casser": 1.0},
			"engagement": {"cible_id": "bloc_gele", "poids": 5.0},
		},
	}
	var catalogue_bloc := {"cassable": {"verbes": ["casser"]}}
	var visibles_sans_la_cible_gelee := [
		{"chose": {"id": "feu_10", "proprietes": {}}, "type": "feu", "position": Vector3.ZERO, "saillance": 3.0},
	]
	var retenu_reinjecte = Agir.choisir(
		visibles_sans_la_cible_gelee, colon_engage_gele, catalogue_bloc, monde_reinjection)
	verif.v(retenu_reinjecte.chose.id == "bloc_gele",
		"reinjection : la cible engagee, absente de visibles, doit etre retrouvee via monde.par_id " +
		"et gagner (poids 5.0 seul contre saillance 3.0 du feu)")

	# Arrachement par saillance NON empeche : une alternative bien plus forte
	# que le poids d'engagement gagne quand meme -- couplage.gd (avancer)
	# n'evalue pas ce cas, agir.gd non plus : la comparaison de score reste
	# ouverte, c'est au cablage de banc de detecter le changement de cible.
	var visibles_alternative_ecrasante := [
		{"chose": {"id": "bloc_1", "proprietes": {}}, "type": "bloc", "position": Vector3.ZERO, "saillance": 1.0},
		{"chose": {"id": "feu_11", "proprietes": {}}, "type": "feu", "position": Vector3.ZERO, "saillance": 50.0},
	]
	var retenu_arrache = Agir.choisir(visibles_alternative_ecrasante, colon_engage, catalogue, monde_vide)
	verif.v(retenu_arrache.chose.id == "feu_11",
		"une alternative ecrasante (50.0) gagne quand meme malgre l'engagement -- agir.gd ne l'empeche pas")

	_proprietes_structurelles_absentes_alarment_et_rendent_neutre(catalogue)

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: inertie compare par id quand il y en a un, par type sinon, cede a l'ecart dans les deux cas, " +
		"et les deux cles structurelles absentes alarment sans jamais decider a l'aveugle")
	quit(0)

# LES DEUX GARDES STRUCTURELLES d'agir.gd, exercees ici et nulle part
# ailleurs (doctrine : docs/design.md). Decider sans inertie, ou retenir un
# verbe sans poids, serait une decision prise a l'aveugle que rien ne
# distinguerait d'une decision juste. Chacune recoit une entite a qui il
# manque EXACTEMENT sa cle.
func _proprietes_structurelles_absentes_alarment_et_rendent_neutre(catalogue: Dictionary) -> void:
	var visibles := [{"type": "type_a", "attache": {"type": "type_a"}, "menace": 0.5, "saillance": 1.0}]

	var sans_forme := {"proprietes": {"poids_verbes": {"action_a": 1.0}}}
	verif.v(Agir.choisir(visibles, sans_forme, catalogue, monde_vide) == null,
		"'forme' absente : alarme puis null, jamais une decision sans inertie")

	var sans_poids := {"proprietes": {"forme": {"gain_inertie": 0.0}}}
	var retenu = Agir.choisir(visibles, sans_poids, catalogue, monde_vide)
	verif.v(retenu != null and retenu.get("action", "") == "",
		"'poids_verbes' absente : alarme puis action vide, jamais un verbe retenu au hasard")
