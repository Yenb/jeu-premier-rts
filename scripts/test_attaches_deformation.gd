extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_attaches_deformation.gd
#
# Verrouille PHASE 4bis chantier A (lecture de la deformation par
# scripts/attaches.gd, patron copie depuis
# scripts/proximite.gd:_appliquer_deformation, voir CARTE.md §2
# attaches.gd/proximite.gd, docs/cadrage_phase4_deformation.md). Ici la
# "cible" de la deformation est directement attache.propriete -- une
# attache ne porte aucune identite de CHOSE distincte, contrairement a
# proximite.gd qui evalue un objet percu precis (voir en-tete
# attaches.gd). Deux colons identiques (meme attache posee sur "brule",
# meme forme), seule la deformation FORCEE sur l'un differe -- doivent
# produire des SAILLANCES differentes pour la MEME attache.
#
# Formule exacte, poids REELS de data/deformations.json:habituation (sens
# "baisse", w_rapide 0.3, w_lent 0.7) -- meme calcul que
# test_proximite_deformation.gd : rapide=0.4/lent=0.6 forces sur l'expose
# donnent biais = 0.3*0.4 + 0.7*0.6 = 0.54. Scene sans aucune source de
# menace (perceptions vides) : l'attache reste intacte, sa saillance nue
# est donc uniquement celle de la branche basse (familiarite,
# force*gain_bas) -- simple a verifier sans arithmetique de menace en plus.

const Attaches = preload("res://scripts/attaches.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_divergence_et_formule_exacte_de_biais()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: attaches.gd applique le biais de deformation du colon a la " +
		"saillance nue de chaque attache selon la formule exacte (sens baisse, " +
		"poids reels de data/deformations.json) -- un colon habitue a brule " +
		"percoit son attache portee sur brule comme moins saillante qu'un " +
		"colon jamais expose")
	quit(0)

func _deformations_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/deformations.json"))

func _menaces_reelles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/menaces.json"))

# Colon avec une attache portee directement sur "brule" -- cible choisie
# pour reutiliser sans nouvelle donnee l'entree reelle
# data/deformations.json:habituation (dont la cible est deja "brule",
# voir data/types.json:colon.deformation_etat.habituation.brule).
# "deformation_etat" demarre vide -- FACULTATIVE ici (voir en-tete
# attaches.gd), chaque test la remplit lui-meme.
func _colon(id: String) -> Dictionary:
	return {
		"id": id,
		"proprietes": {
			"attaches": [{"propriete": "brule", "force": 5.0}],
			"forme": {
				"gain_bas": 0.4, "plafond_bas": 10.0,
				"gain_haut": 1.0, "plafond_haut": 3.0,
				"rayon_liaison": 50.0,
			},
			"deformation_etat": {},
		},
	}

func _divergence_et_formule_exacte_de_biais() -> void:
	var expose := _colon("expose")
	expose.proprietes.deformation_etat["habituation"] = {"brule": {"rapide": 0.4, "lent": 0.6}}
	var isole := _colon("isole")
	# deformation A ZERO -- pas une cle absente, la meme forme que
	# data/types.json:colon.deformation_etat.habituation.brule a la
	# naissance (rapide/lent 0.0) : verrouille que la source existe et est
	# lue sans produire d'effet, pas seulement qu'une cle absente est ignoree.
	isole.proprietes.deformation_etat["habituation"] = {"brule": {"rapide": 0.0, "lent": 0.0}}

	var menaces := _menaces_reelles()
	var deformations := _deformations_reelles()

	# perceptions vides : aucune source de menace dans la scene, l'attache
	# reste intacte (menace 0.0) -- meme scenario que
	# test_attaches.gd:_attache_sans_source_de_menace_a_portee.
	var res_expose := Attaches.evaluer([], expose, menaces, deformations)
	var res_isole := Attaches.evaluer([], isole, menaces, deformations)

	verif.v(res_expose.size() == 1 and res_isole.size() == 1,
		"une attache doit toujours produire une entree, menacee ou non")
	if res_expose.size() != 1 or res_isole.size() != 1:
		return

	var saillance_expose: float = res_expose[0].saillance
	var saillance_isole: float = res_isole[0].saillance

	verif.v(saillance_expose < saillance_isole,
		"l'expose (habitue a brule) doit percevoir son attache comme moins " +
		"saillante que l'isole (sens=baisse)")

	var w_rapide: float = deformations.habituation.w_rapide
	var w_lent: float = deformations.habituation.w_lent
	var biais: float = w_rapide * 0.4 + w_lent * 0.6
	verif.v(is_equal_approx(biais, 0.54),
		"biais attendu = w_rapide*0.4 + w_lent*0.6 = 0.3*0.4 + 0.7*0.6 = 0.54, " +
		"poids REELS de data/deformations.json")

	# saillance nue = force * gain_bas = 5.0 * 0.4 = 2.0 (branche basse,
	# menace <= 0.0, bien sous plafond_bas 10.0 -- aucun clamp actif).
	verif.v(is_equal_approx(saillance_isole, 2.0),
		"sans biais (deformation a zero), la saillance de l'isole doit rester " +
		"la saillance nue exacte : force*gain_bas = 5.0*0.4 = 2.0")
	verif.v(is_equal_approx(saillance_expose, 2.0 * (1.0 - biais)),
		"saillance_expose doit valoir exactement saillance_nue * (1.0 - biais) " +
		"= 2.0 * 0.46 = 0.92")
