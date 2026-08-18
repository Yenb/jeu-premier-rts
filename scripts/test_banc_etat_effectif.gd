extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_etat_effectif.gd
#
# CHEMIN REEL (meme regime que test_banc_champ.gd) : charge
# data/banc_etat_effectif.json et data/etats.json depuis le disque, jamais
# une fixture inventee pour ces deux catalogues. Verrouille les fonctions
# statiques testables de banc_etat_effectif.gd (_est_actif/
# _teinte_pour_valeur/_texte_label/_explication/_ligne_log) et la
# composition reelle avec EtatEffectif.valeur/resoudre sur les quatre
# objets du banc (sans_etat/ecrase/module/ecrase_et_module).

const BancEtatEffectif = preload("res://scripts/banc_etat_effectif.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_est_actif_alterne_sur_la_periode(v)
	_est_actif_periode_nulle_reste_toujours_actif(v)
	_teinte_grise_a_valeur_nulle_ou_negative(v)
	_teinte_orange_croissante_avec_la_valeur(v)
	_texte_label_porte_id_base_etats_et_effective(v)
	_explication_mode_aucun(v)
	_explication_mode_ecraser_sans_ignore(v)
	_explication_mode_ecraser_avec_ignore(v)
	_explication_mode_moduler(v)
	_ligne_log_pose_porte_objet_action_et_valeurs(v)
	_ligne_log_retire_quand_les_etats_diminuent(v)
	_donnees_reelles_quatre_objets_avec_les_bons_roles(v)
	_donnees_reelles_ecrase_et_module_rend_identique_a_ecrase_seul(v)
	_donnees_reelles_sans_etat_rend_toujours_la_base(v)
	_appliquer_roles_pose_et_retire_les_etats_selon_actif(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_etat_effectif.gd -- quatre objets cote a cote (sans_etat/ecrase/module/" +
			"ecrase_et_module), minuterie pose et retire leurs etats en boucle, la teinte et le " +
			"Label suivent EtatEffectif.valeur sans jamais reimplementer la loi, la console " +
			"explique le gagnant via EtatEffectif.resoudre, chemin reel verifie sur " +
			"data/banc_etat_effectif.json/data/etats.json")
		quit(0)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _est_actif_alterne_sur_la_periode(v) -> void:
	v.v(BancEtatEffectif._est_actif(0.0, 4.0) == true, "au demarrage (t=0), le cycle doit etre ACTIF")
	v.v(BancEtatEffectif._est_actif(1.9, 4.0) == true, "juste avant la moitie de la periode, toujours ACTIF")
	v.v(BancEtatEffectif._est_actif(2.1, 4.0) == false, "juste apres la moitie de la periode, INACTIF")
	v.v(BancEtatEffectif._est_actif(3.9, 4.0) == false, "juste avant la fin de la periode, toujours INACTIF")
	v.v(BancEtatEffectif._est_actif(4.1, 4.0) == true, "un cycle complet plus tard, de nouveau ACTIF")

func _est_actif_periode_nulle_reste_toujours_actif(v) -> void:
	v.v(BancEtatEffectif._est_actif(123.0, 0.0) == true, "une periode nulle ou negative est une garde degeneree : toujours actif, jamais planter")

func _teinte_grise_a_valeur_nulle_ou_negative(v) -> void:
	v.v(BancEtatEffectif._teinte_pour_valeur(0.0) == Color(0.4, 0.4, 0.4),
		"valeur effective nulle doit rendre le gris neutre")
	v.v(BancEtatEffectif._teinte_pour_valeur(-1.0) == Color(0.4, 0.4, 0.4),
		"valeur effective negative doit aussi rendre le gris neutre, jamais une teinte inventee")

func _teinte_orange_croissante_avec_la_valeur(v) -> void:
	var teinte_faible := BancEtatEffectif._teinte_pour_valeur(0.3)
	var teinte_forte := BancEtatEffectif._teinte_pour_valeur(0.9)
	v.v(teinte_faible.r > 0.0 and teinte_forte.r > teinte_faible.r,
		"la composante rouge doit croitre avec la valeur effective (plus orange = plus inflammable)")
	v.v(BancEtatEffectif._teinte_pour_valeur(1.8) == BancEtatEffectif._teinte_pour_valeur(1.0),
		"la teinte doit se saturer a 1.0 (au-dela, meme teinte pleine) -- seul le texte porte la vraie valeur")

func _texte_label_porte_id_base_etats_et_effective(v) -> void:
	var texte := BancEtatEffectif._texte_label("ecrase_et_module", 0.9, ["huile", "mouille"], 0.0)
	v.v(texte.find("ecrase_et_module") != -1 and texte.find("0.90") != -1 and texte.find("mouille") != -1 and texte.find("0.00") != -1,
		"le texte du Label doit porter l'identifiant de l'objet, la base, les etats actifs et la valeur effective, lisibles")

func _explication_mode_aucun(v) -> void:
	var texte := BancEtatEffectif._explication({"valeur": 0.9, "mode": "aucun", "gagnants": [], "ignores": []})
	v.v(texte == "aucun etat actif sur cette propriete", "mode 'aucun' doit expliquer qu'aucun etat n'agit")

func _explication_mode_ecraser_sans_ignore(v) -> void:
	var texte := BancEtatEffectif._explication({"valeur": 0.0, "mode": "ecraser", "gagnants": ["mouille"], "ignores": []})
	v.v(texte == "'mouille' ecrase", "mode 'ecraser' sans conflit doit nommer l'unique gagnant, sans parenthese d'ignores")

func _explication_mode_ecraser_avec_ignore(v) -> void:
	var texte := BancEtatEffectif._explication({"valeur": 0.0, "mode": "ecraser", "gagnants": ["mouille"], "ignores": ["huile"]})
	v.v(texte.find("'mouille' ecrase") != -1 and texte.find("huile") != -1,
		"mode 'ecraser' avec un modulateur ecarte doit nommer le gagnant ET l'etat ignore -- c'est ce qui rend visible que l'ecraseur gagne")

func _explication_mode_moduler(v) -> void:
	var texte := BancEtatEffectif._explication({"valeur": 1.8, "mode": "moduler", "gagnants": ["huile"], "ignores": []})
	v.v(texte.find("huile") != -1, "mode 'moduler' doit nommer le ou les etats qui ont compose la valeur")

func _ligne_log_pose_porte_objet_action_et_valeurs(v) -> void:
	var resolution := {"valeur": 0.0, "mode": "ecraser", "gagnants": ["mouille"], "ignores": []}
	var ligne := BancEtatEffectif._ligne_log("ecrase", 4.0, [], ["mouille"], 0.9, resolution)
	v.v(ligne.find("ecrase") != -1 and ligne.find("pose") != -1 and ligne.find("0.90") != -1 and ligne.find("0.00") != -1 and ligne.find("mouille") != -1,
		"la ligne de pose doit porter l'objet, le mot 'pose', la valeur avant, la valeur apres, et l'etat gagnant")

func _ligne_log_retire_quand_les_etats_diminuent(v) -> void:
	var resolution := {"valeur": 0.9, "mode": "aucun", "gagnants": [], "ignores": []}
	var ligne := BancEtatEffectif._ligne_log("ecrase", 6.0, ["mouille"], [], 0.0, resolution)
	v.v(ligne.find("retire") != -1, "quand les etats diminuent (retrait), la ligne doit porter le mot 'retire', jamais 'pose'")

func _donnees_reelles_quatre_objets_avec_les_bons_roles(v) -> void:
	var donnees := _charger_json("res://data/banc_etat_effectif.json")
	var objets: Array = donnees.get("objets", [])
	v.v(objets.size() == 4, "le banc doit declarer exactement quatre objets cote a cote")
	var ids: Array = []
	for o in objets:
		ids.append(o.id)
	v.v(ids.has("sans_etat") and ids.has("ecrase") and ids.has("module") and ids.has("ecrase_et_module"),
		"les quatre roles attendus (sans_etat/ecrase/module/ecrase_et_module) doivent tous etre presents")

func _donnees_reelles_ecrase_et_module_rend_identique_a_ecrase_seul(v) -> void:
	var donnees := _charger_json("res://data/banc_etat_effectif.json")
	var etats := _charger_json("res://data/etats.json")
	var base: float = donnees.inflammabilite_base
	var chose_ecrase := {"id": "ecrase", "position": Vector3.ZERO, "proprietes": {"inflammabilite": base, "etats_actifs": ["mouille"]}}
	var chose_les_deux := {"id": "ecrase_et_module", "position": Vector3.ZERO, "proprietes": {"inflammabilite": base, "etats_actifs": ["mouille", "huile"]}}
	var valeur_ecrase := EtatEffectif.valeur(chose_ecrase, "inflammabilite", etats)
	var valeur_les_deux := EtatEffectif.valeur(chose_les_deux, "inflammabilite", etats)
	v.v(is_equal_approx(valeur_ecrase, valeur_les_deux) and is_equal_approx(valeur_les_deux, 0.0),
		"l'objet portant les DEUX etats doit rendre exactement la meme valeur que l'objet ecrase seul (0.0) -- preuve visuelle que l'ecraseur gagne toujours sur le modulateur")

func _donnees_reelles_sans_etat_rend_toujours_la_base(v) -> void:
	var donnees := _charger_json("res://data/banc_etat_effectif.json")
	var etats := _charger_json("res://data/etats.json")
	var base: float = donnees.inflammabilite_base
	var chose := {"id": "sans_etat", "position": Vector3.ZERO, "proprietes": {"inflammabilite": base, "etats_actifs": []}}
	v.v(is_equal_approx(EtatEffectif.valeur(chose, "inflammabilite", etats), base),
		"l'objet temoin (sans_etat) doit toujours rendre exactement la base, jamais touche par la minuterie")

# Audit couverture 2026-08-06 : _appliquer_roles est une fonction INSTANCE,
# aucune appelee par un test avant cette session -- pourtant c'est ELLE qui
# pose/retire les etats sur les objets a chaque bascule de la minuterie.
# Meme patron que les autres bancs : BancEtatEffectif.new() nu, jamais
# ajoute a l'arbre.
func _appliquer_roles_pose_et_retire_les_etats_selon_actif(v) -> void:
	var etats := _charger_json("res://data/etats.json")
	var b := BancEtatEffectif.new()
	b._etats = etats
	var ecrase := {"id": "ecrase", "proprietes": {"inflammabilite": 0.9, "etats_actifs": []}, "etats_role": ["mouille"]}
	var temoin := {"id": "sans_etat", "proprietes": {"inflammabilite": 0.9, "etats_actifs": []}, "etats_role": []}
	b._objets = [ecrase, temoin]

	b._appliquer_roles(true, 0.0)
	v.v(ecrase.proprietes.etats_actifs == ["mouille"], "actif=true doit poser les etats_role de l'objet")
	v.v(temoin.proprietes.etats_actifs == [], "un objet sans etats_role ne doit jamais rien recevoir, meme actif")

	b._appliquer_roles(false, 4.0)
	v.v(ecrase.proprietes.etats_actifs == [], "actif=false doit retirer les etats poses")

	b._appliquer_roles(false, 8.0)
	v.v(ecrase.proprietes.etats_actifs == [], "rejouer le meme actif=false (apres == avant) doit laisser l'etat inchange, sans planter")
