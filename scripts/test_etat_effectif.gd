extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_etat_effectif.gd
#
# Verrouille scripts/etat_effectif.gd -- calcul PUR, aucune donnee sur
# disque necessaire pour la majorite des cas (voir ETATS_FICTIFS, HORS
# DOMAINE : "conductivite_zorg", "givre", "vernis", "polissage", "brise"
# n'apparaissent nulle part ailleurs dans le depot). Un dernier test
# charge le VRAI data/etats.json pour prouver que l'exemple illustratif
# (mouille/huile sur inflammabilite, voir docs/prototypes.md) parse et se
# comporte comme attendu.

const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Verif = preload("res://scripts/verif.gd")

const ETATS_FICTIFS := {
	"givre": { "effets": [ { "propriete": "conductivite_zorg", "mode": "ecraser", "valeur": 0.0 } ] },
	"brise": { "effets": [ { "propriete": "conductivite_zorg", "mode": "ecraser", "valeur": 9.0 } ] },
	"vernis": { "effets": [ { "propriete": "conductivite_zorg", "mode": "moduler", "facteur": 2.0 } ] },
	"polissage": { "effets": [ { "propriete": "conductivite_zorg", "mode": "moduler", "facteur": 3.0 } ] },
	"poli_couleur": { "effets": [ { "propriete": "couleur_zorg", "mode": "moduler", "facteur": 9.0 } ] },
	"mode_invalide": { "effets": [ { "propriete": "conductivite_zorg", "mode": "transmuter", "valeur": 1.0 } ] },
}

func _chose(base: float, etats_actifs: Variant) -> Dictionary:
	var proprietes: Dictionary = { "conductivite_zorg": base }
	if etats_actifs != null:
		proprietes["etats_actifs"] = etats_actifs
	return { "id": "z1", "position": Vector3.ZERO, "proprietes": proprietes }

func _init() -> void:
	var v := Verif.new()
	_sans_cle_etats_actifs_rend_la_base_inchangee(v)
	_etats_actifs_vide_rend_la_base_inchangee(v)
	_un_seul_modulateur_multiplie_la_base(v)
	_plusieurs_modulateurs_se_composent_multiplicativement_et_dans_l_ordre_du_tri(v)
	_un_ecraseur_impose_sa_valeur_quelle_que_soit_la_base(v)
	_ecraseur_ignore_tout_modulateur_sur_la_meme_propriete(v)
	_conflit_entre_ecraseurs_resolu_par_ordre_alphabetique_du_nom(v)
	_etat_actif_ne_visant_pas_la_propriete_demandee_est_sans_effet(v)
	_reference_absente_du_catalogue_est_ignoree_sans_planter(v)
	_mode_non_reconnu_est_ignore_sans_planter(v)
	_propriete_absente_de_proprietes_vaut_zero_par_defaut(v)
	_ne_mute_jamais_la_chose(v)
	_catalogue_reel_mouille_ecrase_huile_module(v)
	_resoudre_sans_etat_rend_mode_aucun(v)
	_resoudre_un_modulateur_rend_mode_moduler_et_le_gagnant(v)
	_resoudre_plusieurs_modulateurs_rendent_tous_les_gagnants_tries(v)
	_resoudre_ecraseur_seul_rend_mode_ecraser_sans_ignores(v)
	_resoudre_ecraseur_et_modulateur_ignore_le_modulateur(v)
	_resoudre_conflit_ecraseurs_ignore_le_perdant(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: etat_effectif.gd -- ecraser impose une valeur absolue, moduler compose " +
			"multiplicativement, ecraser gagne toujours sur moduler, conflit entre ecraseurs " +
			"tranche par ordre alphabetique du nom (jamais l'ordre du Dictionary/Array), objet " +
			"sans etat inchange, reference et mode inconnus ignores sans planter, resoudre() " +
			"expose gagnants/ignores sans reimplementer la loi")
		quit(0)

func _sans_cle_etats_actifs_rend_la_base_inchangee(v) -> void:
	var chose := _chose(5.0, null)
	v.v(is_equal_approx(EtatEffectif.valeur(chose, "conductivite_zorg", ETATS_FICTIFS), 5.0),
		"sans 'etats_actifs' du tout, la valeur effective doit rester exactement la base")

func _etats_actifs_vide_rend_la_base_inchangee(v) -> void:
	var chose := _chose(5.0, [])
	v.v(is_equal_approx(EtatEffectif.valeur(chose, "conductivite_zorg", ETATS_FICTIFS), 5.0),
		"'etats_actifs' vide doit rendre la base inchangee, comme son absence")

func _un_seul_modulateur_multiplie_la_base(v) -> void:
	var chose := _chose(5.0, ["vernis"])
	v.v(is_equal_approx(EtatEffectif.valeur(chose, "conductivite_zorg", ETATS_FICTIFS), 10.0),
		"un seul modulateur (facteur 2.0) doit multiplier la base (5.0 -> 10.0)")

func _plusieurs_modulateurs_se_composent_multiplicativement_et_dans_l_ordre_du_tri(v) -> void:
	var chose_a := _chose(5.0, ["vernis", "polissage"])
	var chose_b := _chose(5.0, ["polissage", "vernis"])
	v.v(is_equal_approx(EtatEffectif.valeur(chose_a, "conductivite_zorg", ETATS_FICTIFS), 30.0),
		"deux modulateurs (x2 et x3) doivent se composer multiplicativement (5.0 -> 30.0), jamais additivement")
	v.v(is_equal_approx(EtatEffectif.valeur(chose_b, "conductivite_zorg", ETATS_FICTIFS), 30.0),
		"le resultat ne doit JAMAIS dependre de l'ordre des noms dans etats_actifs (meme resultat, ordre inverse)")

func _un_ecraseur_impose_sa_valeur_quelle_que_soit_la_base(v) -> void:
	var chose := _chose(5.0, ["givre"])
	v.v(is_equal_approx(EtatEffectif.valeur(chose, "conductivite_zorg", ETATS_FICTIFS), 0.0),
		"un ecraseur doit imposer sa valeur (0.0), quelle que soit la base (5.0)")

func _ecraseur_ignore_tout_modulateur_sur_la_meme_propriete(v) -> void:
	var chose := _chose(5.0, ["givre", "vernis", "polissage"])
	v.v(is_equal_approx(EtatEffectif.valeur(chose, "conductivite_zorg", ETATS_FICTIFS), 0.0),
		"un ecraseur actif doit rendre tout modulateur sur la meme propriete sans effet (pas 0.0*2.0*3.0)")

func _conflit_entre_ecraseurs_resolu_par_ordre_alphabetique_du_nom(v) -> void:
	var chose_a := _chose(5.0, ["brise", "givre"])
	var chose_b := _chose(5.0, ["givre", "brise"])
	# "brise" < "givre" alphabetiquement -- doit toujours gagner, quel que
	# soit l'ordre de declaration dans etats_actifs.
	v.v(is_equal_approx(EtatEffectif.valeur(chose_a, "conductivite_zorg", ETATS_FICTIFS), 9.0),
		"conflit entre deux ecraseurs : le nom alphabetiquement le plus petit ('brise') doit gagner")
	v.v(is_equal_approx(EtatEffectif.valeur(chose_b, "conductivite_zorg", ETATS_FICTIFS), 9.0),
		"le resultat du conflit ne doit jamais dependre de l'ordre de declaration dans etats_actifs")

func _etat_actif_ne_visant_pas_la_propriete_demandee_est_sans_effet(v) -> void:
	var chose := _chose(5.0, ["poli_couleur"])
	v.v(is_equal_approx(EtatEffectif.valeur(chose, "conductivite_zorg", ETATS_FICTIFS), 5.0),
		"un etat actif qui ne vise pas la propriete demandee (il vise 'couleur_zorg') doit rester sans effet")

func _reference_absente_du_catalogue_est_ignoree_sans_planter(v) -> void:
	var chose := _chose(5.0, ["fantome"])
	v.v(is_equal_approx(EtatEffectif.valeur(chose, "conductivite_zorg", ETATS_FICTIFS), 5.0),
		"un nom d'etat absent du catalogue doit etre ignore (base inchangee), jamais planter")

func _mode_non_reconnu_est_ignore_sans_planter(v) -> void:
	var chose := _chose(5.0, ["mode_invalide"])
	v.v(is_equal_approx(EtatEffectif.valeur(chose, "conductivite_zorg", ETATS_FICTIFS), 5.0),
		"un mode d'effet non reconnu ('transmuter') doit etre ignore, jamais applique ni planter")

func _propriete_absente_de_proprietes_vaut_zero_par_defaut(v) -> void:
	var chose := { "id": "z2", "position": Vector3.ZERO, "proprietes": { "etats_actifs": ["vernis"] } }
	v.v(is_equal_approx(EtatEffectif.valeur(chose, "conductivite_zorg", ETATS_FICTIFS), 0.0),
		"propriete de base absente doit valoir 0.0 (point neutre), un modulateur x2 sur 0.0 reste 0.0")

func _ne_mute_jamais_la_chose(v) -> void:
	var chose := _chose(5.0, ["vernis"])
	var avant := JSON.stringify(chose.proprietes)
	EtatEffectif.valeur(chose, "conductivite_zorg", ETATS_FICTIFS)
	var apres := JSON.stringify(chose.proprietes)
	v.v(avant == apres, "valeur() ne doit jamais muter 'proprietes' -- fonction PURE, calcul seul")

func _catalogue_reel_mouille_ecrase_huile_module(v) -> void:
	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	var chose_mouille := { "id": "b1", "position": Vector3.ZERO, "proprietes": { "inflammabilite": 0.9, "etats_actifs": ["mouille"] } }
	var chose_huile := { "id": "b2", "position": Vector3.ZERO, "proprietes": { "inflammabilite": 0.9, "etats_actifs": ["huile"] } }
	v.v(is_equal_approx(EtatEffectif.valeur(chose_mouille, "inflammabilite", etats), 0.0),
		"data/etats.json:mouille doit ecraser 'inflammabilite' a 0.0 (exemple illustratif reel)")
	v.v(is_equal_approx(EtatEffectif.valeur(chose_huile, "inflammabilite", etats), 1.8),
		"data/etats.json:huile doit moduler 'inflammabilite' par 2.0 (0.9 -> 1.8, exemple illustratif reel)")

func _resoudre_sans_etat_rend_mode_aucun(v) -> void:
	var chose := _chose(5.0, null)
	var r: Dictionary = EtatEffectif.resoudre(chose, "conductivite_zorg", ETATS_FICTIFS)
	v.v(r.mode == "aucun" and r.gagnants.is_empty() and r.ignores.is_empty() and is_equal_approx(r.valeur, 5.0),
		"resoudre() sans etat doit rendre mode 'aucun', gagnants/ignores vides, valeur = base")

func _resoudre_un_modulateur_rend_mode_moduler_et_le_gagnant(v) -> void:
	var chose := _chose(5.0, ["vernis"])
	var r: Dictionary = EtatEffectif.resoudre(chose, "conductivite_zorg", ETATS_FICTIFS)
	v.v(r.mode == "moduler" and r.gagnants == ["vernis"] and r.ignores.is_empty(),
		"resoudre() avec un seul modulateur doit rendre mode 'moduler', gagnants = ['vernis'], aucun ignore")

func _resoudre_plusieurs_modulateurs_rendent_tous_les_gagnants_tries(v) -> void:
	var chose := _chose(5.0, ["polissage", "vernis"])
	var r: Dictionary = EtatEffectif.resoudre(chose, "conductivite_zorg", ETATS_FICTIFS)
	v.v(r.gagnants == ["polissage", "vernis"],
		"resoudre() avec plusieurs modulateurs doit lister tous les gagnants, tries alphabetiquement, quel que soit l'ordre de declaration")

func _resoudre_ecraseur_seul_rend_mode_ecraser_sans_ignores(v) -> void:
	var chose := _chose(5.0, ["givre"])
	var r: Dictionary = EtatEffectif.resoudre(chose, "conductivite_zorg", ETATS_FICTIFS)
	v.v(r.mode == "ecraser" and r.gagnants == ["givre"] and r.ignores.is_empty(),
		"resoudre() avec un seul ecraseur doit rendre mode 'ecraser', gagnants = ['givre'], aucun ignore")

func _resoudre_ecraseur_et_modulateur_ignore_le_modulateur(v) -> void:
	var chose := _chose(5.0, ["givre", "vernis"])
	var r: Dictionary = EtatEffectif.resoudre(chose, "conductivite_zorg", ETATS_FICTIFS)
	v.v(r.mode == "ecraser" and r.gagnants == ["givre"] and r.ignores == ["vernis"],
		"resoudre() doit signaler le modulateur ecarte par un ecraseur actif dans 'ignores', pour qu'un appelant puisse expliquer pourquoi il n'a pas compte")

func _resoudre_conflit_ecraseurs_ignore_le_perdant(v) -> void:
	var chose := _chose(5.0, ["givre", "brise"])
	var r: Dictionary = EtatEffectif.resoudre(chose, "conductivite_zorg", ETATS_FICTIFS)
	v.v(r.mode == "ecraser" and r.gagnants == ["brise"] and r.ignores == ["givre"],
		"resoudre() doit nommer l'ecraseur perdant ('givre') dans 'ignores' quand deux ecraseurs entrent en conflit")
