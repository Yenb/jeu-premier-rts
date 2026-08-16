extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_fin_chantier.gd
#
# Verrouille le chantier "fin de chantier differenciee" (banc_p1.gd) : deux
# issues pour le meme feu, determinees par la COURSE entre extinction.gd
# (agents a portee, travail_restant) et depense.gd (combustible interne,
# reserves.combustible, sans portee) -- premier arrive a zero gagne.
#
# - Agent gagne (travail_restant touche zero avant le combustible) :
#   a_zero retire "brule"/"profil_saillance", jamais "inflammable" -- la
#   chose est SAUVEE, elle garde inflammable et peut se rallumer.
# - Combustible gagne (personne n'eteint a temps) : le seuil "epuisement"
#   (data/seuils_combustible.json) retire "inflammable", "brule",
#   "profil_saillance", "travail_restant" et "transformation" d'un coup --
#   meme nettoyage que a_zero de extinction.gd (brule/profil_saillance),
#   PLUS inflammable (rallumage impossible) et le chantier (travail_restant/
#   transformation, sinon un chantier fantome resterait mangeable par un
#   agent sur une chose qui ne brule plus). La chose est CONSUMEE : elle
#   cesse de bruler IMMEDIATEMENT (plus de saillance, plus de chantier),
#   et ne peut plus jamais bruler (propagation.gd l'ignore, "inflammable"
#   absente = non vulnerable).
#
# Verrouille aussi banc_p1.gd:geler_combustible_apres_sauvetage : sans elle,
# le combustible d'une chose sauvee continuerait de decroitre en arriere-
# plan (depense.gd ne regarde jamais "brule") et finirait par retirer
# "inflammable" plus tard quand meme, sans lien avec un nouvel incendie --
# decision de Yael. Gele cout_base a 0.0 tant que "brule" est absent,
# garde la reserve restante telle quelle, la restaure (depuis le patron)
# des que "brule" revient -- une reprise repart d'ou elle s'est arretee,
# jamais d'un compte neuf.
#
# Verrouille aussi le bug d'aliasing corrige ce chantier (voir
# banc_commun.gd:resoudre_chantier) : copier une valeur Dictionary du
# patron par simple assignation (`proprietes[cle] = patron[cle]`) partage
# la REFERENCE -- toute chose heritant "reserves" du patron (au clic
# comme par propagation.gd, qui appelle desormais BancCommun.
# resoudre_chantier au lieu de dupliquer le meme geste) partageait le
# meme canal combustible que le patron ET que toute autre chose l'ayant
# herite avant elle. Le "seuils_franchis" pose par la PREMIERE chose a
# s'epuiser bloquait la reapplication du seuil sur toutes les suivantes,
# qui ne se consumaient donc jamais -- exactement le symptome observe sur
# les arbres allumes par propagation. Corrige par `.duplicate(true)` dans
# resoudre_chantier : chaque chose recoit sa PROPRE copie, jamais partagee.
#
# Fonctions pures : aucun noeud, aucun rendu. Catalogues locaux a ce test,
# memes valeurs que data/transformations.json / data/seuils_combustible.json
# au moment de l'ecriture (une derive future entre les deux ne casserait
# que ce fichier, jamais silencieusement) -- sauf les deux tests qui
# verifient explicitement les VRAIES donnees du depot (data/types.json,
# "feu" doit porter sa propre reserve, plus courte que celle heritee du
# patron par un arbre).

const Extinction = preload("res://scripts/extinction.gd")
const Depense = preload("res://scripts/depense.gd")
const Propagation = preload("res://scripts/propagation.gd")
const BancP1 = preload("res://scripts/banc_p1.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

const DELTA := 0.1

const MENACES := { "inflammable": "brule" }

const TRANSFORMATIONS := {
	"defaut_test": {
		"portee_travail": 25.0,
		"a_zero": { "retirer": ["brule", "profil_saillance"] },
	},
}

const SEUILS_COMBUSTIBLE := {
	"epuisement": [
		{ "seuil": 0.0, "retirer": ["inflammable", "brule", "profil_saillance", "travail_restant", "transformation"] },
	],
}

# Meme forme que data/transformations.json au moment de ce chantier : sert
# a la fois de patron de fabrication (tests 1/3) et de reference pour
# geler_combustible_apres_sauvetage (cout_base actif a restaurer).
const PATRON := {
	"travail_restant": 3.0,
	"profil_saillance": "feu",
	"transformation": "defaut_test",
	"reserves": {
		"combustible": {
			"reserve": 5.0,
			"cout_base": 1.0,
			"surcout_action": 0.0,
			"seuils_ref": "epuisement",
		},
	},
}

func _init() -> void:
	var v := Verif.new()
	_arbre_sauve_garde_inflammable_et_peut_se_rallumer(v)
	_arbre_consume_perd_inflammable_et_ne_peut_plus_bruler(v)
	_course_depend_des_nombres_pas_d_un_ordre_code(v)
	_arbre_enflamme_par_propagation_se_consume_seul(v)
	_deux_choses_enflammees_par_propagation_ont_un_combustible_independant(v)
	_feu_lui_meme_se_consume_avec_une_reserve_plus_courte_que_larbre(v)
	_une_chose_qui_porte_deja_des_reserves_recoit_le_combustible_et_se_consume(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: la course entre extinction (agents) et depense (combustible) decide qui gagne, " +
			"jamais un ordre code -- sauve garde inflammable et se rallume, consume perd inflammable " +
			"pour toujours, geler_combustible_apres_sauvetage arrete la decroissance en arriere-plan")
		quit(0)

func _arbre(id: String, pos: Vector3, travail_restant: float, reserve: float, cout_base: float) -> Dictionary:
	return {
		"id": id,
		"position": pos,
		"proprietes": {
			"inflammable": true,
			"brule": true,
			"profil_saillance": "feu",
			"portee_propagation": 90.0,
			"delai_propagation": 1.0,
			"travail_restant": travail_restant,
			"transformation": "defaut_test",
			"reserves": {
				"combustible": {
					"reserve": reserve,
					"cout_base": cout_base,
					"surcout_action": 0.0,
					"seuils_ref": "epuisement",
				},
			},
		},
	}

func _agents(nb: int, pos: Vector3, rythme: float) -> Array:
	var a: Array = []
	for i in nb:
		a.append({"position": pos, "rythme": rythme})
	return a

# Un agent a portee (rythme 1.0) eteint travail_restant (3.0) avant que le
# combustible (5.0, cout_base 1.0) n'ait le temps de s'epuiser -- meme ordre
# d'appel que banc_p1.gd:_process (Extinction -> geler -> Depense).
func _arbre_sauve_garde_inflammable_et_peut_se_rallumer(v: Verif) -> void:
	var arbre := _arbre("arbre_1", Vector3.ZERO, 3.0, 5.0, 1.0)
	var monde: Array = [arbre]
	var agents := _agents(1, Vector3.ZERO, 1.0)
	var sauve := false
	for i in 200:
		var eteints := Extinction.avancer(monde, agents, DELTA, TRANSFORMATIONS)
		BancP1.geler_combustible_apres_sauvetage(monde, PATRON)
		Depense.avancer(monde, DELTA, SEUILS_COMBUSTIBLE)
		if eteints.has("arbre_1"):
			sauve = true
			break
	v.v(sauve, "un agent a portee doit finir par eteindre l'arbre avant que le combustible ne s'epuise")

	var p: Dictionary = arbre.proprietes
	v.v(not p.has("brule"), "l'arbre eteint ne doit plus porter brule")
	v.v(p.get("inflammable", false), "l'arbre sauve doit garder inflammable")
	var reserve_au_sauvetage: float = p.reserves.combustible.reserve
	v.v(reserve_au_sauvetage > 0.0, "le combustible ne doit pas avoir touche zero au moment du sauvetage")

	# Gele : sans agent ni feu, de nombreux ticks supplementaires ne doivent
	# plus bouger le combustible -- c'est la garde que geler_combustible_
	# apres_sauvetage existe pour poser.
	for i in 300:
		BancP1.geler_combustible_apres_sauvetage(monde, PATRON)
		Depense.avancer(monde, DELTA, SEUILS_COMBUSTIBLE)
	v.v(p.reserves.combustible.reserve == reserve_au_sauvetage,
		"gele : le combustible ne doit plus bouger une fois la chose sauvee, meme apres un long moment")
	v.v(p.get("inflammable", false), "toujours inflammable apres le long moment gele")

	# Peut se rallumer : un feu voisin, exposition prolongee, propagation.gd
	# doit reprendre l'arbre puisqu'il porte toujours inflammable.
	var feu_voisin := {"id": "feu_2", "position": Vector3(10, 0, 0), "proprietes": {"brule": true}}
	monde.append(feu_voisin)
	var exposition := {}
	var reprise := false
	for i in 50:
		var enflammees := Propagation.avancer(monde, MENACES, exposition, DELTA, PATRON)
		if enflammees.has("arbre_1"):
			reprise = true
			break
	v.v(reprise, "l'arbre sauve, toujours inflammable, doit pouvoir se rallumer si un feu revient")
	v.v(p.get("brule", false), "l'arbre rallume doit porter brule a nouveau")

	# Une reprise repart d'ou le combustible s'est arrete (reserve_au_sauvetage),
	# jamais d'un compte neuf (5.0) -- resoudre_chantier/propagation.gd ne
	# repose jamais une cle deja presente sur la chose.
	v.v(p.reserves.combustible.reserve == reserve_au_sauvetage,
		"le rallumage ne doit pas remettre le combustible a son plein")
	BancP1.geler_combustible_apres_sauvetage(monde, PATRON)
	v.v(p.reserves.combustible.cout_base == PATRON.reserves.combustible.cout_base,
		"brule etant revenu, cout_base doit etre restaure a sa valeur active, pas rester gele a 0.0")

# Sans aucun agent, le chantier d'extinction n'avance jamais (verrouille
# ailleurs par test_extinction.gd) -- seul le combustible (5.0, cout_base 1.0)
# decroit, jusqu'a toucher le seuil "epuisement" et retirer inflammable.
func _arbre_consume_perd_inflammable_et_ne_peut_plus_bruler(v: Verif) -> void:
	var arbre := _arbre("arbre_2", Vector3.ZERO, 3.0, 5.0, 1.0)
	var monde: Array = [arbre]
	var consume := false
	for i in 200:
		Extinction.avancer(monde, [], DELTA, TRANSFORMATIONS)
		BancP1.geler_combustible_apres_sauvetage(monde, PATRON)
		var consumes := Depense.avancer(monde, DELTA, SEUILS_COMBUSTIBLE)
		if consumes.has("arbre_2"):
			consume = true
			break
	v.v(consume, "sans agent, le combustible doit finir par toucher zero et etre rendu comme franchi")

	var p: Dictionary = arbre.proprietes
	v.v(not p.has("inflammable"), "epuisement doit retirer inflammable")
	v.v(not p.has("brule"), "epuisement doit retirer brule : la chose cesse de bruler immediatement")
	v.v(not p.has("profil_saillance"), "epuisement doit retirer profil_saillance : plus de saillance")
	v.v(not p.has("travail_restant"), "epuisement doit retirer travail_restant : plus de chantier")
	v.v(not p.has("transformation"), "epuisement doit retirer transformation : plus de chantier")

	# Ne peut plus jamais bruler : une chose sans inflammable est hors du
	# domaine de propagation.gd (_vulnerabilite rend "", voir propagation.gd)
	# -- une exposition prolongee a un feu voisin ne doit jamais l'enflammer.
	var cendre := {
		"id": "cendre_1",
		"position": Vector3(50, 0, 0),
		"proprietes": {"portee_propagation": 90.0, "delai_propagation": 1.0},
	}
	var feu_voisin := {"id": "feu_x", "position": Vector3.ZERO, "proprietes": {"brule": true}}
	var monde2: Array = [feu_voisin, cendre]
	var exposition := {}
	for i in 100:
		Propagation.avancer(monde2, MENACES, exposition, DELTA, PATRON)
	v.v(not cendre.proprietes.has("brule"),
		"une chose consumee (sans inflammable) ne doit jamais reprendre feu, meme longtemps exposee")

# LA preuve que le resultat depend des NOMBRES, pas d'un ordre code : le
# meme enchainement Extinction -> geler -> Depense, verifie dans le meme
# ordre a chaque tick que banc_p1.gd:_process, produit une issue differente
# selon les seuls parametres (rythme de l'agent, reserve de combustible).
func _course(rythme_agent: float, reserve: float) -> String:
	var arbre := _arbre("x", Vector3.ZERO, 3.0, reserve, 1.0)
	var monde: Array = [arbre]
	var agents := _agents(1, Vector3.ZERO, rythme_agent)
	for i in 2000:
		var eteints := Extinction.avancer(monde, agents, DELTA, TRANSFORMATIONS)
		BancP1.geler_combustible_apres_sauvetage(monde, PATRON)
		var consumes := Depense.avancer(monde, DELTA, SEUILS_COMBUSTIBLE)
		if eteints.has("x"):
			return "sauve"
		if consumes.has("x"):
			return "consume"
	return "aucun"

func _course_depend_des_nombres_pas_d_un_ordre_code(v: Verif) -> void:
	v.v(_course(5.0, 5.0) == "sauve",
		"agent rapide (rythme 5.0) + combustible normal (5.0) : l'agent doit gagner la course")
	v.v(_course(0.1, 1.0) == "consume",
		"agent lent (rythme 0.1) + combustible court (1.0) : le combustible doit gagner malgre un agent actif")

const TYPES_PROPAGATION := {
	"arbre_prop_test": {"inflammable": true, "portee_propagation": 90.0, "delai_propagation": 1.0},
}

# Une chose allumee par PROPAGATION (pas par clic, pas de proprietes ecrites
# a la main) doit recevoir reserves.combustible du patron exactement comme
# une chose allumee au clic (banc_p1.gd:_unhandled_input appelle
# resoudre_chantier directement) -- propagation.gd appelle desormais le
# meme resoudre_chantier au lieu de dupliquer le geste. Sans agent, elle
# doit se consumer d'elle-meme, comme n'importe quelle autre chose.
func _arbre_enflamme_par_propagation_se_consume_seul(v: Verif) -> void:
	var feu := {"id": "feu_prop", "position": Vector3.ZERO, "proprietes": {"brule": true}}
	var arbre := Objet.fabriquer("arbre_prop", "arbre_prop_test", Vector3(50, 0, 0), TYPES_PROPAGATION)
	var monde: Array = [feu, arbre]
	var exposition := {}
	var enflamme := false
	for i in 50:
		var enflammees := Propagation.avancer(monde, MENACES, exposition, DELTA, PATRON)
		if enflammees.has("arbre_prop"):
			enflamme = true
			break
	v.v(enflamme, "l'arbre doit s'allumer par propagation")
	v.v(arbre.proprietes.has("reserves"),
		"une chose allumee par propagation doit recevoir reserves du patron, exactement comme au clic")
	v.v(arbre.proprietes.reserves.combustible.reserve == PATRON.reserves.combustible.reserve,
		"le combustible recu doit etre intact a l'allumage (copie du patron, pas une reference partagee)")

	var consume := false
	for i in 200:
		Extinction.avancer(monde, [], DELTA, TRANSFORMATIONS)
		var consumes := Depense.avancer(monde, DELTA, SEUILS_COMBUSTIBLE)
		if consumes.has("arbre_prop"):
			consume = true
			break
	v.v(consume, "un arbre allume par propagation, sans agent, doit se consumer de lui-meme")
	v.v(not arbre.proprietes.has("inflammable"), "consume : l'arbre ne peut plus jamais bruler")

# LE verrou direct du bug d'aliasing : deux choses distinctes allumees par
# le MEME appel a Propagation.avancer (donc heritant du MEME patron) ne
# doivent jamais partager le meme canal combustible -- sinon le
# "seuils_franchis" de la premiere a s'epuiser bloque la reapplication du
# seuil sur la seconde, qui ne se consumerait jamais (symptome exact
# observe avant la correction, "les arbres propages ne se consument pas").
func _deux_choses_enflammees_par_propagation_ont_un_combustible_independant(v: Verif) -> void:
	var feu := {"id": "feu_double", "position": Vector3.ZERO, "proprietes": {"brule": true}}
	var arbre_a := Objet.fabriquer("arbre_a_prop", "arbre_prop_test", Vector3(50, 0, 0), TYPES_PROPAGATION)
	var arbre_b := Objet.fabriquer("arbre_b_prop", "arbre_prop_test", Vector3(55, 0, 0), TYPES_PROPAGATION)
	var monde: Array = [feu, arbre_a, arbre_b]
	var exposition := {}
	for i in 50:
		Propagation.avancer(monde, MENACES, exposition, DELTA, PATRON)

	v.v(arbre_a.proprietes.has("reserves") and arbre_b.proprietes.has("reserves"),
		"les deux arbres doivent avoir recu reserves du patron")
	v.v(not is_same(arbre_a.proprietes.reserves.combustible, arbre_b.proprietes.reserves.combustible),
		"chaque chose allumee doit recevoir sa PROPRE copie du canal combustible, jamais le meme objet")
	v.v(not is_same(arbre_a.proprietes.reserves.combustible, PATRON.reserves.combustible),
		"le canal recu ne doit jamais etre le meme objet que celui du patron lui-meme")

	# Meme scenario (memes reserves, allumees au meme tick) : les deux se
	# consument typiquement au MEME tick -- une seule boucle qui accumule les
	# deux drapeaux, jamais deux boucles sequentielles (arbre_b n'aurait plus
	# de franchissement a detecter APRES celui d'arbre_a s'ils arrivent
	# ensemble). Si le bug d'aliasing existait encore, le "seuils_franchis"
	# partage -- deja rempli par le traitement d'arbre_a dans la MEME
	# passe de Depense.avancer -- bloquerait la reapplication du seuil sur
	# arbre_b : ce test echouait avant la correction (arbre_b jamais consume).
	var a_consume := false
	var b_consume := false
	for i in 200:
		var consumes := Depense.avancer(monde, DELTA, SEUILS_COMBUSTIBLE)
		if consumes.has("arbre_a_prop"):
			a_consume = true
		if consumes.has("arbre_b_prop"):
			b_consume = true
		if a_consume and b_consume:
			break
	v.v(a_consume, "arbre_a doit se consumer")
	v.v(b_consume, "arbre_b doit aussi se consumer, independamment -- jamais bloque par un seuils_franchis partage")

# Verifie les VRAIES donnees du depot (pas un catalogue local a ce test,
# voir en-tete) : le type "feu" doit porter sa propre reserve, plus courte
# que celle qu'un arbre herite du patron -- le feu brule vite et meurt,
# l'arbre brule plus longtemps.
func _feu_lui_meme_se_consume_avec_une_reserve_plus_courte_que_larbre(v: Verif) -> void:
	var types_reels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var transformations_reelles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json"))
	var patron_reel: Dictionary = transformations_reelles.get("patron", {})
	var seuils_reels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_combustible.json"))

	v.v(types_reels.feu.has("reserves"), "le type 'feu' (data/types.json) doit porter son propre canal reserves.combustible")
	var reserve_feu: float = types_reels.feu.reserves.combustible.reserve
	var reserve_arbre_heritee: float = patron_reel.reserves.combustible.reserve
	v.v(reserve_feu < reserve_arbre_heritee,
		"le feu doit avoir une reserve de combustible plus courte que celle heritee du patron par un arbre")

	var feu := Objet.fabriquer("feu_reel", "feu", Vector3.ZERO, types_reels)
	# La surcharge de type doit l'emporter sur le patron partage (meme
	# convention que travail_restant sur "arbre_dur", voir
	# test_propagation_chantier.gd) : resoudre_chantier descend dans
	# "reserves" et n'y touche pas, "combustible" y etant deja present.
	BancCommun.resoudre_chantier(feu.proprietes, patron_reel)
	v.v(feu.proprietes.reserves.combustible.reserve == reserve_feu,
		"la surcharge de type doit l'emporter : resoudre_chantier ne doit pas ecraser reserves deja present")

	var monde: Array = [feu]
	var consume := false
	for i in 200:
		var consumes := Depense.avancer(monde, DELTA, seuils_reels)
		if consumes.has("feu_reel"):
			consume = true
			break
	v.v(consume, "le feu doit se consumer de lui-meme, sans agent, par son propre combustible court")

# CHEMIN REEL, catalogues du disque : une chose qui porte deja un
# "reserves" garni d'AUTRES canaux (les cinq physiologiques de
# data/types.json:dynamique) doit recevoir le canal combustible du patron
# ET garder les siens. Comparee a la clef racine, elle deviendrait un
# chantier sans combustible : depense.gd n'aurait rien a ponctionner, le
# seuil "epuisement" ne se declencherait jamais, elle brulerait sans fin
# sans qu'aucune alarme ne sonne. Aucun type inflammable du depot ne
# compose "dynamique" aujourd'hui -- c'est ce qui rend le cas invisible
# partout ailleurs, et pourquoi il est verrouille ici.
func _une_chose_qui_porte_deja_des_reserves_recoit_le_combustible_et_se_consume(v: Verif) -> void:
	var types_reels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var transformations_reelles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json"))
	var seuils_reels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/seuils_combustible.json"))
	var patron_reel: Dictionary = transformations_reelles.get("patron", {})

	var table: Dictionary = types_reels.duplicate(true)
	table["vivant_inflammable_demo"] = {"herite": ["dynamique"], "inflammable": true}
	var vivant := Objet.fabriquer("vivant_1", "vivant_inflammable_demo", Vector3.ZERO, table)

	var canaux_avant: Array = vivant.proprietes.reserves.keys().duplicate()
	v.v(canaux_avant.size() > 0 and not canaux_avant.has("combustible"),
		"le paquet dynamique doit fournir des canaux, et aucun combustible")

	BancCommun.resoudre_chantier(vivant.proprietes, patron_reel)

	for canal in canaux_avant:
		v.v(vivant.proprietes.reserves.has(canal),
			"le canal '%s' herite ne doit JAMAIS disparaitre a l'allumage" % canal)
	v.v(vivant.proprietes.reserves.has("combustible"),
		"une chose qui porte deja d'autres canaux doit quand meme recevoir le combustible du patron")
	v.v(vivant.proprietes.reserves.combustible.reserve == patron_reel.reserves.combustible.reserve,
		"le canal recu doit porter la calibration du patron, telle quelle")
	v.v(vivant.proprietes.get("travail_restant", -1.0) == patron_reel.travail_restant,
		"les cles plates du patron restent posees comme avant")

	var monde: Array = [vivant]
	var consume := false
	for i in 400:
		if Depense.avancer(monde, DELTA, seuils_reels).has("vivant_1"):
			consume = true
			break
	v.v(consume, "la chose doit reellement se consumer : sans le canal, le seuil ne tombe jamais")
