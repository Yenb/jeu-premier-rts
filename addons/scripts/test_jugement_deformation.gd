extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_jugement_deformation.gd
#
# Verrouille PHASE 4bis chantier B (chantier "L'entite comme agent
# complet", lecture par jugement.gd -- voir docs/cadrage_phase4_deformation.md) :
# scripts/jugement.gd:evaluer applique desormais le biais de deformation du
# COLON (Deformation.biais, deja ferme PHASE 4) a la PRESSION DEJA SOMMEE
# par entree de jugements.json, APRES le calcul habituel (somme des
# saillances des choses percues portant le declencheur), AVANT la
# multiplication par gain_jugement. Meme geste que
# test_proximite_deformation.gd (chemin reel, Objet.fabriquer contre
# data/types.json, poids REELS de data/deformations.json, jamais une
# fixture locale pour les poids) -- deux colons reels, identiques a la
# naissance, seule la deformation FORCEE sur l'un differe.
#
# Scene : cinq feux percus, deja saillants en couche 2 (resultats, 3.0
# chacun -- meme ordre de grandeur que banc_feu.gd a sa plage de bascule
# reelle, ou 5 feux x 3.0 x gain_jugement fait basculer le colon "mesure").
# Pression brute = 15.0 avant deformation, sur l'entree reelle
# "abrite": "brule" de data/jugements.json.
#
# Formule exacte verrouillee, avec les VRAIES valeurs de
# data/deformations.json:habituation (sens "baisse", w_rapide 0.3,
# w_lent 0.7) :
#   biais = w_rapide * rapide + w_lent * lent
#   saillance = clamp(pression_sommee * (1.0 - biais) * gain_jugement, 0.0, plafond)
# Rapide=0.4/lent=0.6 forces sur l'expose donnent biais = 0.3*0.4 + 0.7*0.6
# = 0.54, donc pression_expose = 15.0 * 0.46 = 6.9.

const Jugement = preload("res://scripts/jugement.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_divergence_et_formule_exacte_sur_pression_sommee()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: jugement.gd applique le biais de deformation du colon a la " +
		"PRESSION DEJA SOMMEE par entree de jugements.json (poids reels de " +
		"data/deformations.json) -- un colon habitue a brule juge l'abri " +
		"moins saillant qu'un colon jamais expose, jamais une attenuation " +
		"appliquee saillance par saillance avant sommation")
	quit(0)

func _types_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))

func _jugements_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/jugements.json"))

func _deformations_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/deformations.json"))

# Colon REEL, fabrique directement contre data/types.json -- herite
# deformation_etat.habituation.brule = { rapide: 0.0, lent: 0.0 } (PHASE 4
# piece 1/2, forme A depuis le chantier "un seul patron de reference de
# catalogue"). "forme" est structurelle pour jugement.gd : gain/plafond
# poses explicitement ici, jamais lus depuis un catalogue de banc (aucun
# cablage de banc n'entre en jeu dans ce test, comme
# test_proximite_deformation.gd).
func _colon_reel(id: String) -> Dictionary:
	var colon := Objet.fabriquer(id, "colon", Vector3.ZERO, _types_reels())
	colon.proprietes.forme = {"gain_jugement": 1.0, "plafond_jugement": 100.0}
	return colon

# Cinq feux percus (comme banc_feu.gd a sa plage de bascule reelle, cinq
# clics de feu), chacun deja saillant en couche 2 (resultats) a 3.0 -- meme
# ordre de grandeur que data/profils_saillance.json:feu. La distance
# n'entre dans aucun calcul de jugement.gd, elle n'est portee ici que pour
# respecter la forme attendue de "perceptions".
func _perceptions_et_resultats_cinq_feux() -> Dictionary:
	var perceptions: Array = []
	var resultats: Array = []
	for i in range(5):
		var feu := {
			"id": "feu_%d" % i,
			"position": Vector3(i, 0, 0),
			"proprietes": {"brule": true},
		}
		perceptions.append({"chose": feu, "type": "feu", "position": feu.position, "distance": float(i)})
		resultats.append({"chose": feu, "type": "feu", "position": feu.position, "saillance": 3.0})
	return {"perceptions": perceptions, "resultats": resultats}

func _divergence_et_formule_exacte_sur_pression_sommee() -> void:
	var expose := _colon_reel("expose")
	expose.proprietes.deformation_etat.habituation.brule.rapide = 0.4
	expose.proprietes.deformation_etat.habituation.brule.lent = 0.6
	var isole := _colon_reel("isole")

	var scene := _perceptions_et_resultats_cinq_feux()
	var jugements := _jugements_reels()
	var deformations := _deformations_reelles()

	# Une chose "abrite" pour recevoir la saillance jugee -- sans elle,
	# aucune entree ne sort meme avec une pression positive (meme contrat
	# que proximite.gd/attaches.gd : perception jugee necessaire).
	var abri := {"id": "abri", "position": Vector3(10, 0, 0), "proprietes": {"abrite": true}}
	var perceptions: Array = scene.perceptions.duplicate()
	perceptions.append({"chose": abri, "type": "abri", "position": abri.position, "distance": 10.0})

	var res_expose := Jugement.evaluer(perceptions, expose, scene.resultats, jugements, deformations)
	var res_isole := Jugement.evaluer(perceptions, isole, scene.resultats, jugements, deformations)

	verif.v(res_expose.size() == 1 and res_isole.size() == 1,
		"l'abri doit rester juge saillant pour les deux colons -- le biais reduit la pression, il n'exclut jamais l'entree")
	if res_expose.size() != 1 or res_isole.size() != 1:
		return

	verif.v(res_expose[0].chose.id == "abri" and res_isole[0].chose.id == "abri",
		"l'entree doit designer l'abri, pas un feu")

	var saillance_expose: float = res_expose[0].saillance
	var saillance_isole: float = res_isole[0].saillance

	var w_rapide: float = deformations.habituation.w_rapide
	var w_lent: float = deformations.habituation.w_lent
	var biais: float = w_rapide * 0.4 + w_lent * 0.6
	verif.v(is_equal_approx(biais, 0.54),
		"biais attendu = w_rapide*0.4 + w_lent*0.6 = 0.3*0.4 + 0.7*0.6 = 0.54, poids REELS de data/deformations.json")

	var pression_nue := 15.0 # 5 feux x 3.0 de saillance chacun
	var gain: float = expose.proprietes.forme.gain_jugement
	var plafond: float = expose.proprietes.forme.plafond_jugement
	var attendu_expose: float = clamp(pression_nue * (1.0 - biais) * gain, 0.0, plafond)
	var attendu_isole: float = clamp(pression_nue * gain, 0.0, plafond)

	verif.v(is_equal_approx(saillance_expose, attendu_expose),
		"saillance_expose doit valoir exactement pression_sommee * (1.0 - biais) * gain_jugement = 15.0 * 0.46 = 6.9")
	verif.v(is_equal_approx(saillance_isole, attendu_isole),
		"sans deformation posee (biais=0.0), la saillance de l'isole doit rester celle de la pression nue (15.0)")
	verif.v(saillance_expose < saillance_isole,
		"l'expose (habitue a brule) doit juger l'abri moins saillant que l'isole (sens=baisse)")
