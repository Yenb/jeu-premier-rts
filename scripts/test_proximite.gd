extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_proximite.gd
#
# Le fanatique abandonne le feu proche pour le feu lointain qui menace
# sa foret : la saillance d'attache (menace) ecrase la saillance de
# proximite. Le placide, sans attache, va au feu le plus proche : seule
# la saillance de proximite existe pour lui.
#
# _le_modele_ignore_le_domaine() verrouille en plus que proximite.gd ne
# connait aucun nom de domaine : une chose saillante inventee (un cristal
# luisant, absent de tout le moteur, verifie par grep) traverse le meme
# code que le feu, sans une ligne ajoutee.

const Proximite = preload("res://scripts/proximite.gd")
const Attaches = preload("res://scripts/attaches.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	var chemin := "res://data/proximite_exemple.json"
	var texte := FileAccess.get_file_as_string(chemin)
	var donnees: Dictionary = JSON.parse_string(texte)
	# Catalogue des profils de saillance (data/profils_saillance.json en
	# vrai) : la chose ne porte plus saillance_intrinseque/portee_saillance
	# en valeur, seulement une reference "profil_saillance" resolue ici.
	var profils_saillance: Dictionary = donnees.profils_saillance
	# proximite_exemple.json ne porte que attaches/forme -- le colon
	# complet se construit ici, comme _ajouter_colon (banc_p1.gd).
	var fanatique := {"proprietes": donnees.colons.fanatique}
	var placide := {"proprietes": donnees.colons.placide}

	# Table de menaces par propriete (data/menaces.json) : la menace n'est
	# plus detectee par type nominal (menace_par), remplace catalogue_attaches.
	var menaces := { "inflammable": "brule" }

	var perceptions := [
		{
			"chose": { "id": "feu_proche", "position": Vector3(10, 0, 0), "proprietes": { "profil_saillance": "feu", "brule": true } },
			"type": "feu",
			"position": Vector3(10, 0, 0), "distance": 10.0,
		},
		{
			"chose": { "id": "feu_lointain", "position": Vector3(200, 0, 0), "proprietes": { "profil_saillance": "feu", "brule": true } },
			"type": "feu",
			"position": Vector3(200, 0, 0), "distance": 200.0,
		},
		{
			"chose": { "id": "foret_lointaine", "position": Vector3(205, 0, 0), "proprietes": { "inflammable": true, "irremplacable": true } },
			"type": "foret",
			"position": Vector3(205, 0, 0), "distance": 205.0,
		},
	]

	# fanatique/placide : ni l'un ni l'autre ne porte de deformation ici --
	# le colon passe pour cette saillance PARTAGEE (reutilisee pour les deux
	# ensuite) n'a donc aucun effet sur le resultat, quel qu'il soit (voir
	# PHASE 4 piece 3, scripts/proximite.gd:_appliquer_deformation).
	var prox := Proximite.evaluer(perceptions, fanatique, profils_saillance, {})
	verif.v(prox.size() == 1, "seul le feu proche reste dans sa portee de saillance")
	if prox.size() == 1:
		verif.v(prox[0].chose.id == "feu_proche", "le feu lointain est hors portee de saillance")

	var att_fanatique := Attaches.evaluer(perceptions, fanatique, menaces)
	var att_placide := Attaches.evaluer(perceptions, placide, menaces)

	# Meme liste, deux sources : dominance.gd n'y verra que des nombres.
	var resultats_fanatique: Array = att_fanatique + prox
	var resultats_placide: Array = att_placide + prox

	var forme_ecrasement := { "proprietes": { "forme": { "seuil_ecrasement": 1.0 } } }
	var vus_fanatique := Dominance.visibles(resultats_fanatique, forme_ecrasement)
	var vus_placide := Dominance.visibles(resultats_placide, forme_ecrasement)

	verif.v(vus_fanatique.size() == 1, "le fanatique doit ecraser sur un seul choix")
	if vus_fanatique.size() == 1:
		verif.v(vus_fanatique[0].has("attache"), "le fanatique choisit la menace sur sa foret")

	verif.v(vus_placide.size() == 1, "le placide doit ecraser sur un seul choix")
	if vus_placide.size() == 1:
		verif.v(vus_placide[0].chose.id == "feu_proche", "le placide va au feu le plus proche")

	_le_modele_ignore_le_domaine(verif)
	_portee_saillance_est_structurelle_si_saillance_declaree(verif)
	_reference_profil_saillance_absente_du_catalogue_alarme(verif)
	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return

	print("OK: fanatique -> foret (menace=%.2f saillance=%.2f) | placide -> %s (saillance=%.2f), " % [
		vus_fanatique[0].menace, vus_fanatique[0].saillance,
		vus_placide[0].chose.id, vus_placide[0].saillance,
	] + "domaine invente traverse le meme code sans ligne ajoutee")
	quit(0)

# LA serrure hors domaine : une chose saillante SANS AUCUN rapport avec le
# feu (un cristal qui attire par sa lueur, absent de tout le moteur) doit
# ressortir saillante par le meme code, tant qu'elle reference une entree
# de catalogue portant saillance_intrinseque/portee_saillance. Si ce test
# passe, proximite.gd ne connait aucun nom de domaine.
func _le_modele_ignore_le_domaine(v) -> void:
	var catalogue := {
		"cristal": { "saillance_intrinseque": 5.0, "portee_saillance": 50.0 },
	}
	var perceptions := [
		{
			"chose": {
				"id": "cristal_luisant",
				"position": Vector3(20, 0, 0),
				"proprietes": { "profil_saillance": "cristal" },
			},
			"type": "cristal",
			"position": Vector3(20, 0, 0), "distance": 20.0,
		},
		{
			"chose": {
				"id": "chose_neutre",
				"position": Vector3(10, 0, 0),
				"proprietes": {},
			},
			"type": "neutre",
			"position": Vector3(10, 0, 0), "distance": 10.0,
		},
		{
			"chose": {
				"id": "cristal_lointain",
				"position": Vector3(999, 0, 0),
				"proprietes": { "profil_saillance": "cristal" },
			},
			"type": "cristal",
			"position": Vector3(999, 0, 0), "distance": 999.0,
		},
	]

	var colon := {"proprietes": {}}
	var resultats := Proximite.evaluer(perceptions, colon, catalogue, {})

	v.v(resultats.size() == 1, "seul le cristal a portee doit ressortir saillant")
	v.v(resultats[0].chose.id == "cristal_luisant" if resultats.size() > 0 else false,
		"le cristal luisant a portee doit ressortir saillant par le meme code")
	v.v(resultats[0].saillance > 0.0 if resultats.size() > 0 else false,
		"le cristal saillant doit recevoir une saillance strictement positive")

	var ids: Array = []
	for r in resultats:
		ids.append(r.chose.id)
	v.v(not ids.has("chose_neutre"),
		"une chose sans profil_saillance ne doit jamais ressortir saillante")
	v.v(not ids.has("cristal_lointain"),
		"une chose hors de sa portee_saillance ne doit jamais ressortir saillante")

# Piege du couple : saillance_intrinseque > 0 declare "je suis saillant",
# portee_saillance le borne -- desormais au niveau de l'ENTREE DE CATALOGUE
# resolue, pas de l'instance. Cle ABSENTE (has == false) est un oubli
# structurel -- alarme, entree exclue, jamais une saillance maximale a
# toute distance. Cle PRESENTE a 0.0 est une intention explicite -- exclue
# aussi, mais sans alarme. Les deux convergent sur "jamais saillante", pour
# des raisons distinctes.
func _portee_saillance_est_structurelle_si_saillance_declaree(v) -> void:
	var catalogue := {
		"sans_portee": { "saillance_intrinseque": 5.0 },
		"portee_zero_explicite": { "saillance_intrinseque": 5.0, "portee_saillance": 0.0 },
	}
	var perceptions := [
		{
			"chose": {
				"id": "sans_portee",
				"position": Vector3(999, 0, 0),
				"proprietes": { "profil_saillance": "sans_portee" },
			},
			"type": "sans_portee",
			"position": Vector3(999, 0, 0), "distance": 999.0,
		},
		{
			"chose": {
				"id": "portee_zero_explicite",
				"position": Vector3(999, 0, 0),
				"proprietes": { "profil_saillance": "portee_zero_explicite" },
			},
			"type": "portee_zero_explicite",
			"position": Vector3(999, 0, 0), "distance": 999.0,
		},
	]

	var colon := {"proprietes": {}}
	var resultats := Proximite.evaluer(perceptions, colon, catalogue, {})
	var ids: Array = []
	for r in resultats:
		ids.append(r.chose.id)

	v.v(not ids.has("sans_portee"),
		"saillance_intrinseque sans portee_saillance ne doit jamais ressortir saillante (cas du couple, structurel)")
	v.v(not ids.has("portee_zero_explicite"),
		"portee_saillance explicitement a 0.0 ne doit jamais ressortir saillante (intention explicite, pas une alarme)")

# STRUCTUREL, meme forme que "transformation" dans extinction.gd et
# "seuils_ref" dans depense.gd : une chose qui reference un profil_saillance
# absent du catalogue alarme et n'est jamais saillante, jamais un silence.
func _reference_profil_saillance_absente_du_catalogue_alarme(v) -> void:
	var perceptions := [
		{
			"chose": {
				"id": "reference_inconnue",
				"position": Vector3(10, 0, 0),
				"proprietes": { "profil_saillance": "jamais_declare" },
			},
			"type": "inconnu",
			"position": Vector3(10, 0, 0), "distance": 10.0,
		},
	]
	var colon := {"proprietes": {}}
	var resultats := Proximite.evaluer(perceptions, colon, {}, {})
	v.v(resultats.is_empty(), "une reference de profil_saillance absente du catalogue ne doit jamais ressortir saillante")
