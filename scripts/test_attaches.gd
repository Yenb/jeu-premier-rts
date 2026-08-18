extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_attaches.gd
#
# Verrouille scripts/attaches.gd : sur la meme scene (une chose vulnerable
# type_x proche, une chose menacante type_y a distance 50), stresse (rayon
# de liaison large) doit relier la menace et produire UNE entree a
# saillance HAUTE ; placide (rayon de liaison etroit) ne relie rien mais
# produit quand meme UNE entree, a saillance BASSE (familiarite) -- une
# attache intacte vit dans la routine, elle n'est plus absente du resultat
# (voir docs/design.md, "Deux effets pour une seule attache"). Menace par
# proprietes (data/menaces.json), pas par nom.
#
# _hors_domaine() verrouille en plus que le lien d'attache lui-meme se
# fait par PROPRIETE (attache.propriete), jamais par nom de type : un
# type invente pour ce seul test, absent de tout catalogue existant,
# doit etre defendu par la seule presence de la propriete.
#
# _attache_sans_source_de_menace_a_portee() verrouille le cas symetrique :
# l'objet de l'attache est bien percu, mais aucune source de menace n'est
# a portee -- une entree sort quand meme, a saillance BASSE, jamais haute
# (pas seulement quand la menace est hors du rayon de liaison, mais quand
# elle n'existe pas du tout dans la scene).
#
# _attache_intacte_produit_saillance_basse_familiarite() verrouille
# directement la decision de design : une attache intacte (menace nulle)
# produit une saillance strictement positive mais strictement inferieure
# a celle de la meme attache menacee -- la routine n'est jamais un
# silence, ni jamais aussi haute que la crise.
#
# _chose_menacee_par_elle_meme_saillance_haute() verrouille le pansement
# FERME (CARTE.md §6) : une chose qui porte a la fois sa vulnerabilite et
# sa propre propriete-menace (un arbre inflammable qui brule deja) est
# menacee au MAXIMUM (distance a elle-meme = 0), jamais exclue de son
# propre calcul de menace.

const Attaches = preload("res://scripts/attaches.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	var chemin := "res://data/attaches_exemple.json"
	var texte := FileAccess.get_file_as_string(chemin)
	var donnees: Dictionary = JSON.parse_string(texte)
	# attaches_exemple.json ne porte que attaches/forme (donnee propre a
	# l'instance) -- le colon complet se construit ici, comme
	# _ajouter_colon (banc_p1.gd) construit { proprietes: {...} }.
	var stresse := {"proprietes": donnees.colons.stresse}
	var placide := {"proprietes": donnees.colons.placide}

	var menaces: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/menaces.json"))

	# Table de proprietes locale au test : type_x porte le trait auquel le
	# colon tient ("trait_x", distinct de la vulnerabilite) et la
	# vulnerabilite ("inflammable") ; type_y porte la menace correspondante
	# ("brule"), le couple etant defini par menaces.json.
	var table_proprietes := {
		"type_x": {"trait_x": true, "inflammable": true},
		"type_y": {"brule": true},
	}
	var attache_vue := Objet.fabriquer("attache_vue", "type_x", Vector3(0, 0, 0), table_proprietes)
	var menace_vue := Objet.fabriquer("menace_vue", "type_y", Vector3(50, 0, 0), table_proprietes)

	var perceptions := [
		{
			"chose": attache_vue, "type": "type_x",
			"position": Vector3(0, 0, 0), "distance": 0.0,
		},
		{
			"chose": menace_vue, "type": "type_y",
			"position": Vector3(50, 0, 0), "distance": 50.0,
		},
	]

	var res_stresse = Attaches.evaluer(perceptions, stresse, menaces)
	var res_placide = Attaches.evaluer(perceptions, placide, menaces)

	verif.v(res_stresse.size() == 1, "stresse relie la menace : attendu 1 resultat")
	verif.v(res_placide.size() == 1,
		"placide ne relie rien, mais l'attache intacte produit quand meme une entree")

	if res_stresse.size() == 1 and res_placide.size() == 1:
		var m_stresse: float = res_stresse[0].menace
		var s_stresse: float = res_stresse[0].saillance
		verif.v(m_stresse > 0.0, "stresse doit relier la menace lointaine")

		var m_placide: float = res_placide[0].menace
		var s_placide: float = res_placide[0].saillance
		verif.v(m_placide <= 0.0, "placide : rayon trop etroit, l'attache reste intacte")
		verif.v(s_placide > 0.0, "attache intacte : saillance basse, jamais nulle")
		verif.v(s_placide < s_stresse,
			"la routine (placide, intacte) doit rester sous la crise (stresse, menacee)")

		_hors_domaine()
		_proprietes_structurelles_absentes_alarment_et_rendent_vide()
		_attache_sans_source_de_menace_a_portee()
		_attache_intacte_produit_saillance_basse_familiarite()
		_chose_menacee_par_elle_meme_saillance_haute()

		if verif.echecs() == 0:
			print("OK: stresse=%s/%s (menace/haute), placide=%s/%s (intacte/basse), " % [
				m_stresse, s_stresse, m_placide, s_placide
			] + "attache par propriete hors de tout nom de type connu")

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	quit(0)

# LES DEUX GARDES STRUCTURELLES, exercees ici et nulle part ailleurs
# (doctrine : docs/design.md). Chacune recoit une entite a qui il manque
# EXACTEMENT sa cle -- une entite vide sortirait sur la premiere sans
# jamais atteindre la seconde.
func _proprietes_structurelles_absentes_alarment_et_rendent_vide() -> void:
	var perceptions := [{
		"chose": {"id": "x", "proprietes": {"irremplacable": true}},
		"type": "x", "position": Vector3.ZERO, "distance": 0.0,
	}]
	var menaces := {"irremplacable": "menace_inventee"}

	var sans_attaches := {"proprietes": {"forme": {"rayon_liaison": 100.0}}}
	verif.v(Attaches.evaluer(perceptions, sans_attaches, menaces).is_empty(),
		"'attaches' absente : alarme puis retour neutre, jamais un defaut silencieux")

	var sans_forme := {"proprietes": {"attaches": [{"propriete": "irremplacable", "force": 1.0}]}}
	verif.v(Attaches.evaluer(perceptions, sans_forme, menaces).is_empty(),
		"'forme' absente : alarme puis retour neutre, jamais un defaut silencieux")

	var placide := {"proprietes": {"attaches": [], "forme": {"rayon_liaison": 100.0}}}
	verif.v(Attaches.evaluer(perceptions, placide, menaces).is_empty(),
		"cle PRESENTE et vide reste legitime : le placide ne doit JAMAIS alarmer")

# LA serrure hors domaine : "irremplacable" est le trait auquel un
# fanatique tient (voir docs/design.md, "Les archetypes n'existent pas").
# Un type jamais vu ailleurs dans le projet, portant ce seul trait, doit
# etre relie par attaches.gd sans qu'aucun nom de type n'ait jamais ete
# ecrit ici -- si ce test passe, attaches.gd ne connait aucun nom de type.
func _hors_domaine() -> void:
	var menaces: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/menaces.json"))
	var table := {
		"chose_jamais_vue_ailleurs": {"irremplacable": true, "inflammable": true},
		"autre_chose_jamais_vue_ailleurs": {"brule": true},
	}
	var cible := Objet.fabriquer("cible", "chose_jamais_vue_ailleurs", Vector3(0, 0, 0), table)
	var source := Objet.fabriquer("source", "autre_chose_jamais_vue_ailleurs", Vector3(50, 0, 0), table)
	var perceptions := [
		{"chose": cible, "type": "chose_jamais_vue_ailleurs", "position": Vector3(0, 0, 0), "distance": 0.0},
		{"chose": source, "type": "autre_chose_jamais_vue_ailleurs", "position": Vector3(50, 0, 0), "distance": 50.0},
	]
	var colon := {
		"proprietes": {
			"attaches": [{"propriete": "irremplacable", "force": 4.0}],
			"forme": {"rayon_liaison": 80.0, "gain_haut": 1.0, "plafond_haut": 3.0},
		},
	}
	var res := Attaches.evaluer(perceptions, colon, menaces)
	verif.v(res.size() == 1, "hors domaine : attendu 1 resultat")
	if res.size() == 1:
		verif.v(res[0].menace > 0.0,
			"un type jamais vu, portant irremplacable, doit etre defendu par la seule propriete")

# Cas distinct de "placide ne relie rien" : ici, aucune source de menace
# n'existe DU TOUT dans la scene (pas seulement hors du rayon_liaison) --
# l'objet de l'attache est bien percu, mais rien ne porte la
# propriete-menace correspondante nulle part. Une entree sort quand meme,
# a saillance BASSE : verrouille que la routine ne depend pas d'une portee
# insuffisante ni de la presence d'une menace ailleurs dans la scene, elle
# est le comportement par defaut de toute attache intacte.
func _attache_sans_source_de_menace_a_portee() -> void:
	var menaces: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/menaces.json"))
	var table := {
		"type_x": {"trait_x": true, "inflammable": true},
	}
	var seul_objet := Objet.fabriquer("seul_objet", "type_x", Vector3(0, 0, 0), table)
	var perceptions := [
		{"chose": seul_objet, "type": "type_x", "position": Vector3(0, 0, 0), "distance": 0.0},
	]
	var colon := {
		"proprietes": {
			"attaches": [{"propriete": "trait_x", "force": 2.0}],
			"forme": {"rayon_liaison": 80.0, "gain_haut": 1.0, "plafond_haut": 3.0},
		},
	}
	var res := Attaches.evaluer(perceptions, colon, menaces)
	verif.v(res.size() == 1,
		"objet de l'attache percu, aucune source de menace dans la scene : une entree, routine")
	if res.size() == 1:
		verif.v(res[0].menace <= 0.0, "sans menace, l'attache doit rester intacte")
		verif.v(res[0].saillance > 0.0, "attache intacte : saillance basse, jamais nulle")

# LA serrure de la decision de design : une attache intacte (menace nulle)
# doit produire une saillance strictement positive mais strictement
# inferieure a celle de la MEME attache (meme force, meme forme) menacee.
# Compare deux appels a deformer() directement -- pas via evaluer() -- pour
# isoler la seule chose qui varie : menace 0.0 vs 0.6, rien d'autre.
func _attache_intacte_produit_saillance_basse_familiarite() -> void:
	var attache := {"propriete": "irremplacable", "force": 3.0}
	var forme := {
		"gain_bas": 0.1, "plafond_bas": 0.5,
		"gain_haut": 1.0, "plafond_haut": 5.0,
	}

	var s_intacte := Attaches.deformer(0.0, attache, forme)
	var s_menacee := Attaches.deformer(0.6, attache, forme)

	verif.v(s_intacte > 0.0, "attache intacte : saillance strictement positive (familiarite)")
	verif.v(s_intacte < s_menacee,
		"attache intacte : saillance strictement inferieure a la meme attache menacee")

# FERME (voir CARTE.md §6, pansement menace) : une chose qui porte a la
# fois sa vulnerabilite et sa propre propriete-menace (un arbre inflammable
# qui brule deja) est menacee au MAXIMUM, pas exclue. La distance d'une
# chose a elle-meme est 0 -- poids = 1.0, quel que soit rayon_liaison.
# Avant la fermeture, menace_attache() excluait la chose d'elle-meme via
# is_same(), rendant menace = 0.0 (intacte) alors que l'arbre brule sous
# les yeux du colon qui y tient : ce test aurait echoue sur l'ancien code
# (m_arbre <= 0.0, saillance basse au lieu de haute).
func _chose_menacee_par_elle_meme_saillance_haute() -> void:
	var menaces: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/menaces.json"))
	var table := {
		"arbre_en_feu": {"irremplacable": true, "inflammable": true, "brule": true},
	}
	var arbre := Objet.fabriquer("arbre_1", "arbre_en_feu", Vector3(0, 0, 0), table)
	var perceptions := [
		{"chose": arbre, "type": "arbre_en_feu", "position": Vector3(0, 0, 0), "distance": 0.0},
	]
	var colon := {
		"proprietes": {
			"attaches": [{"propriete": "irremplacable", "force": 3.0}],
			"forme": {"rayon_liaison": 20.0, "gain_haut": 1.0, "plafond_haut": 5.0},
		},
	}
	var res := Attaches.evaluer(perceptions, colon, menaces)
	verif.v(res.size() == 1, "un arbre qui brule lui-meme doit produire une entree")
	if res.size() == 1:
		verif.v(res[0].menace == 1.0,
			"un arbre menace par lui-meme (distance 0) doit etre menace au maximum, jamais exclu")
		verif.v(res[0].saillance > 0.5,
			"un arbre en feu qui menace sa propre attache doit rendre une saillance HAUTE, " +
			"pas la saillance basse (familiarite) d'une attache intacte")
