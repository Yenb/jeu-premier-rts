extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_proximite_deformation.gd
#
# Verrouille PHASE 4 piece 3/3 (chantier "L'entite comme agent complet",
# voir docs/cadrage_phase4_deformation.md) : scripts/proximite.gd:evaluer
# applique desormais le biais de deformation du COLON (Deformation.biais,
# deja ferme piece 1) a la saillance NUE d'une chose, APRES le calcul
# habituel (profil_saillance/portee_saillance/avancement). Ferme la boucle
# du chantier sur son premier lecteur : deux colons REELS (Objet.fabriquer
# contre data/types.json), identiques a la naissance -- seule la
# deformation FORCEE sur l'un differe, meme geste que le forcage direct
# deja verrouille par test_deformation.gd/test_banc_deformation.gd --
# divergent desormais dans la SAILLANCE qu'ils accordent a la meme chose,
# pas seulement dans leur valeur de deformation (PHASE 4 piece 2).
#
# Formule exacte verrouillee, avec les VRAIES valeurs de
# data/deformations.json:habituation (sens "baisse", w_rapide 0.3,
# w_lent 0.7, jamais une fixture locale pour les poids) :
#   biais = w_rapide * rapide + w_lent * lent
#   saillance = saillance_nue * (1.0 - biais)
# Rapide=0.4/lent=0.6 forces sur l'expose donnent biais = 0.3*0.4 + 0.7*0.6
# = 0.54, donc saillance_expose = saillance_nue * 0.46.

const Proximite = preload("res://scripts/proximite.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_divergence_et_formule_exacte_de_biais()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: proximite.gd applique le biais de deformation du colon a la " +
		"saillance nue selon la formule exacte (sens baisse, poids reels de " +
		"data/deformations.json) -- un colon habitue percoit la meme chose " +
		"comme moins saillante qu'un colon jamais expose")
	quit(0)

func _types_reels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))

func _deformations_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/deformations.json"))

# Colon REEL, fabrique directement contre data/types.json -- herite
# deformation_etat.habituation.brule = { rapide: 0.0, lent: 0.0 } (PHASE 4
# piece 1/2, forme A depuis le chantier "un seul patron de reference de
# catalogue"), sans aucun cablage de banc (ni forme ni poids_verbes
# n'entrent en jeu ici, proximite.gd ne les lit jamais).
func _colon_reel(id: String) -> Dictionary:
	return Objet.fabriquer(id, "colon", Vector3.ZERO, _types_reels())

# Une chose portant "brule" (declencheur de l'habituation, PHASE 4 piece 2)
# et un profil_saillance fixe -- distance nulle, facteur de portee exact a
# 1.0, pour que la saillance nue soit exactement saillance_intrinseque,
# sans arithmetique supplementaire a verifier.
func _perception_feu() -> Dictionary:
	var chose := {
		"id": "feu_test",
		"position": Vector3.ZERO,
		"proprietes": {"profil_saillance": "feu_test", "brule": true},
	}
	return {"chose": chose, "type": "feu_test", "position": Vector3.ZERO, "distance": 0.0}

func _catalogue_saillance() -> Dictionary:
	return {"feu_test": {"saillance_intrinseque": 10.0, "portee_saillance": 100.0}}

func _divergence_et_formule_exacte_de_biais() -> void:
	var expose := _colon_reel("expose")
	expose.proprietes.deformation_etat.habituation.brule.rapide = 0.4
	expose.proprietes.deformation_etat.habituation.brule.lent = 0.6
	var isole := _colon_reel("isole")

	var catalogue := _catalogue_saillance()
	var deformations := _deformations_reelles()

	var resultats_expose := Proximite.evaluer([_perception_feu()], expose, catalogue, deformations)
	var resultats_isole := Proximite.evaluer([_perception_feu()], isole, catalogue, deformations)

	verif.v(resultats_expose.size() == 1 and resultats_isole.size() == 1,
		"le feu doit rester saillant pour les deux colons -- le biais reduit la saillance, il n'exclut jamais")
	if resultats_expose.size() != 1 or resultats_isole.size() != 1:
		return

	var saillance_expose: float = resultats_expose[0].saillance
	var saillance_isole: float = resultats_isole[0].saillance

	verif.v(saillance_expose < saillance_isole,
		"l'expose (habitue a brule) doit percevoir le feu comme moins saillant que l'isole (sens=baisse)")

	var w_rapide: float = deformations.habituation.w_rapide
	var w_lent: float = deformations.habituation.w_lent
	var biais: float = w_rapide * 0.4 + w_lent * 0.6
	verif.v(is_equal_approx(biais, 0.54),
		"biais attendu = w_rapide*0.4 + w_lent*0.6 = 0.3*0.4 + 0.7*0.6 = 0.54, poids REELS de data/deformations.json")
	verif.v(is_equal_approx(saillance_expose, 10.0 * (1.0 - biais)),
		"saillance_expose doit valoir exactement saillance_nue * (1.0 - biais) = 10.0 * 0.46 = 4.6")
	verif.v(is_equal_approx(saillance_isole, 10.0),
		"sans deformation posee (biais=0.0), la saillance de l'isole doit rester la saillance nue, inchangee")
