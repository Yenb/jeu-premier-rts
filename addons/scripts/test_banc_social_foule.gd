extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_social_foule.gd
#
# Verrouille les fonctions PURES de scripts/banc_social_foule.gd (chantier
# « foule + environnement », audit_social_relations_prealable.md lignes 5, 7, 9
# et 10). Le banc ne fait que CABLER sept mecanismes du coeur deja verrouilles
# separement (comptage.gd, somme.gd, charge.gd, seuil_etat.gd, depense.gd,
# lien_personnel.gd, portee.gd -- TOUS INCHANGES par ce chantier) : aucune de
# leurs lois n'est retestee ici. Ce qui est teste, c'est ce que le CABLAGE
# ajoute -- la fraction et sa fenetre, la somme ponderee recalculee a neuf, le
# stress proportionnel a l'exces de densite, le gate de bruit sur le canal de
# sommeil, et la calibration reelle des vingt colons.
#
# DEUX MOITIES, comme les autres tests de banc :
# - HORS DOMAINE : une config, un catalogue de comptages, un catalogue de seuils
#   ENTIEREMENT INVENTES (suffixe "_qwil" -- "du_troupeau_qwil",
#   "part_furieuse_qwil", "creux_liant_qwil", "vacarme_local_qwil",
#   "tumulte_qwil", "eparpille_qwil", "compresse_qwil", "derange_qwil"), une
#   grille 2x2 et non 4x4, six colons et non vingt, une capacite de cohesion de
#   10.0 et non 1.0, une fraction critique de 0.30 et non 0.15. Si le banc
#   nommait "colere", "cohesion", "bruit_local", "emeute" ou 0.15 en dur, ce
#   bloc rougirait.
# - CHEMIN REEL : data/banc_social_foule.json + data/comptages.json +
#   data/seuils_etat.json + data/etats.json relus SUR LE DISQUE, pour verifier
#   la CALIBRATION (vingt colons, quatre axes hauts, trois colons en colere ne
#   suffisent PAS et quatre suffisent) et l'ACCORD entre les noms que le banc
#   ECRIT et les 'propriete_continue' que les entrees partagees COMPARENT --
#   accord qu'aucun autre test ne verifie et dont la rupture serait SILENCIEUSE
#   (un miroir ecrit sous un nom que plus personne ne compare : aucun etat ne se
#   poserait plus jamais, sans une seule alarme).
#
# CE QUI EST VERROUILLE EN PLUS, ET QUI VIENT D'UN DEFAUT REEL trouve en
# ecrivant (voir data/seuils_etat.json:emeute) : la REVERSIBILITE de l'emeute et
# de la surdensite. charge.gd ERASE ses cles 'poser' au franchissement
# descendant, seuil_etat.gd sort par 'if not proprietes.has(propriete_continue):
# return false' -- branches directement, l'etat serait pose a la montee et
# JAMAIS retire a la descente, en silence. Les deux tests
# _l_emeute_se_defait_quand_la_colere_retombe et
# _la_surdensite_se_defait_quand_on_disperse sont ce qui empeche la
# reintroduction du raccourci.

const Banc = preload("res://scripts/banc_social_foule.gd")
const Verif = preload("res://scripts/verif.gd")

# ---------------------------------------------------------------------------
# DOMAINE INVENTE DE BOUT EN BOUT
# ---------------------------------------------------------------------------
# Six colons dont un chef. Quatre s'entassent sur la case (0,0) -- confort 2,
# donc exces 2 -- ; le chef est seul sur la case (1,0) et un dernier sur la
# case (1,1). Les deux cases de la colonne 1 sont bruyantes a 0.70 : le chef,
# dormeur leger (seuil 0.30), est derange ; le colon de (1,1), dormeur lourd
# (seuil 0.90), ne l'est pas -- MEME BRUIT, deux issues, c'est le seuil PAR
# COLON qui tranche.
const CONFIG_QWIL := {
	"grille_lignes": 2,
	"grille_colonnes": 2,
	"taille_case": 100.0,
	"portee_appariement": 50.0,

	"nom_membre": "du_troupeau_qwil",
	"nom_colere": "furieux_qwil",
	"nom_chef": "meneur_qwil",
	"nom_fraction_colere": "part_furieuse_qwil",
	"nom_case_locale": "dalle_qwil",
	"nom_densite_locale": "presse_qwil",
	"nom_seuil_confort": "aise_qwil",
	"nom_bruit": "vacarme_qwil",
	"nom_bruit_local": "vacarme_local_qwil",
	"nom_seuil_gene": "seuil_reveil_qwil",
	"nom_cohesion": "liant_qwil",
	"nom_manque_cohesion": "creux_liant_qwil",
	"nom_culture": "us_qwil",
	"nom_culture_partagee": "meme_us_qwil",
	"nom_croyance_partagee": "meme_foi_qwil",
	"nom_cycles_vecus": "lunes_vues_qwil",
	"nom_force_liens_locale": "tenue_qwil",
	"nom_reserve_sommeil": "torpeur_qwil",

	"nom_canal_emeute": "houle_qwil",
	"nom_canal_choc": "deuil_qwil",
	"nom_canal_stress": "presse_montante_qwil",
	"nom_marqueur_emeute": "houle_franchie_qwil",
	"nom_marqueur_choc": "deuil_franchi_qwil",
	"nom_marqueur_stress": "presse_franchie_qwil",
	"nom_miroir_emeute": "houle_soutenue_qwil",
	"nom_miroir_stress": "presse_soutenue_qwil",

	"etat_colere": "furie_qwil",
	"etat_colere_majoritaire": "gronde_qwil",
	"etat_emeute": "tumulte_qwil",
	"etat_disloque": "eparpille_qwil",
	"etat_surdensite": "compresse_qwil",
	"etat_gene_bruit": "derange_qwil",

	"regle_membres": "membres_qwil",
	"regle_colere": "furieux_regle_qwil",
	"regle_croyance_partagee": "foi_qwil",
	"regle_culture_partagee": "us_regle_qwil",
	"regle_vecu_suffisant": "lunes_qwil",

	"croyance_chose": "monolithe_qwil",
	"croyance_propriete": "sacre_qwil",

	"foule": {
		"fraction_critique": 0.30,
		"fenetre_s": 2.0,
		"poids_cause": 1.0,
		"taux_decroissance": 1.0,
		"plafond_charge": 5.0,
	},
	"choc": {
		"poids_cause": 4.0,
		"seuil": 6.0,
		"taux_decroissance": 4.0,
		"plafond_charge": 10.0,
	},
	"densite": {
		"seuil_confort": 2.0,
		"stress_par_point": 1.0,
		"seuil": 3.0,
		"taux_decroissance": 3.0,
		"plafond_charge": 9.0,
	},
	"sommeil": {
		"capacite": 20.0,
		"reserve_initiale": 20.0,
		"recuperation_par_s": 1.0,
		"penalite_par_point_de_bruit": 5.0,
	},
	"cohesion": {
		"capacite": 10.0,
		"poids_liens": 3.0,
		"poids_croyance": 3.0,
		"poids_culture": 2.0,
		"poids_vecu": 2.0,
		"poids_choc": 1.0,
		"reference_liens": 2.0,
	},

	"bruit_par_defaut": 0.0,
	"niveaux_bruit": [0.0, 0.5, 0.9],
	"cases_bruyantes": [
		{ "colonne": 1, "ligne": 0, "bruit": 0.70 },
		{ "colonne": 1, "ligne": 1, "bruit": 0.70 },
	],

	"colons": [
		{ "id": "un_qwil",    "position": [-20.0, -20.0, 0.0], "force_lien": 1.6, "culture": "roche_qwil", "croyance": true,  "cycles_vecus": 4.0, "seuil_gene_sommeil": 0.30 },
		{ "id": "deux_qwil",  "position": [0.0, -20.0, 0.0],   "force_lien": 1.4, "culture": "roche_qwil", "croyance": true,  "cycles_vecus": 5.0, "seuil_gene_sommeil": 0.30 },
		{ "id": "trois_qwil", "position": [20.0, -20.0, 0.0],  "force_lien": 1.2, "culture": "roche_qwil", "croyance": false, "cycles_vecus": 1.0, "seuil_gene_sommeil": 0.30 },
		{ "id": "quatre_qwil","position": [0.0, 20.0, 0.0],    "force_lien": 1.8, "culture": "vent_qwil",  "croyance": true,  "cycles_vecus": 3.0, "seuil_gene_sommeil": 0.30 },
		{ "id": "cinq_qwil",  "position": [100.0, 100.0, 0.0], "force_lien": 1.0, "culture": "roche_qwil", "croyance": true,  "cycles_vecus": 4.0, "seuil_gene_sommeil": 0.90 },
		{ "id": "chef_qwil",  "position": [100.0, 20.0, 0.0],  "force_lien": 2.0, "culture": "roche_qwil", "croyance": true,  "cycles_vecus": 6.0, "seuil_gene_sommeil": 0.30, "chef": true },
	],

	"periode_trace_s": 1.0,
	"rendu": { "rayon_clic": 30.0 },
}

const COMPTAGES_QWIL := {
	"membres_qwil":       { "propriete": "du_troupeau_qwil", "mode": "presente" },
	"furieux_regle_qwil": { "propriete": "furieux_qwil",     "mode": "presente" },
	"foi_qwil":           { "propriete": "meme_foi_qwil",    "mode": "presente" },
	"us_regle_qwil":      { "propriete": "meme_us_qwil",     "mode": "presente" },
	"lunes_qwil":         { "propriete": "lunes_vues_qwil",  "mode": "superieur_a", "valeur_reference": 2.0 },
}

const SEUILS_QWIL := {
	"gronde":    { "propriete_continue": "part_furieuse_qwil",   "seuil": 0.30, "etat": "gronde_qwil" },
	"tumulte":   { "propriete_continue": "houle_soutenue_qwil",  "seuil": 0.5,  "etat": "tumulte_qwil" },
	"eparpille": { "propriete_continue": "creux_liant_qwil",     "seuil": 5.0,  "etat": "eparpille_qwil" },
	"compresse": { "propriete_continue": "presse_soutenue_qwil", "seuil": 0.5,  "etat": "compresse_qwil" },
	"derange":   { "propriete_continue": "vacarme_local_qwil",   "seuil_propriete": "seuil_reveil_qwil", "etat": "derange_qwil" },
}

# lien_personnel.gd:force ne lit jamais le catalogue (seulement poser/avancer
# s'en servent, et avancer n'est PAS cable par ce banc) -- il est passe parce
# que la signature l'exige, avec les memes cles que data/liens_personnels.json.
const LIENS_QWIL := { "defaut": { "taux_decroissance": 0.0, "plancher_suppression": 0.0 } }

const PAS := 0.1

func _init() -> void:
	var v := Verif.new()
	# Hors domaine.
	_la_scene_se_monte(v)
	_les_liens_sont_un_registre_reel(v)
	_la_fenetre_est_le_seuil_du_canal(v)
	_sous_la_fraction_critique_rien_ne_bascule(v)
	_au_dessus_il_faut_attendre_la_fenetre_entiere(v)
	_l_emeute_se_defait_quand_la_colere_retombe(v)
	_la_cohesion_tient_avec_quatre_axes_hauts(v)
	_le_choc_du_chef_fait_chuter_la_cohesion(v)
	_la_dislocation_est_posee_sous_le_seuil(v)
	_le_choc_se_resorbe_quand_on_rend_le_chef(v)
	_la_cohesion_est_recalculee_a_neuf(v)
	_la_densite_au_dessus_du_confort_accumule_du_stress(v)
	_la_densite_au_confort_n_accumule_rien(v)
	_la_surdensite_se_defait_quand_on_disperse(v)
	_le_bruit_au_dessus_du_seuil_penalise_le_sommeil(v)
	_le_bruit_sous_le_seuil_ne_penalise_pas(v)
	_un_seul_ecrivain_pour_surcout_action(v)
	_le_chef_ne_porte_pas_le_canal_d_emeute(v)
	# Chemin reel.
	_reel_les_noms_ecrits_sont_ceux_que_les_seuils_comparent(v)
	_reel_les_etats_et_les_regles_existent(v)
	_reel_vingt_colons_un_chef_quatre_axes_hauts(v)
	_reel_trois_en_colere_ne_suffisent_pas_quatre_suffisent(v)
	_reel_les_cases_denses_stressent_les_aerees_non(v)
	_reel_la_colonne_bruyante_derange_sauf_le_dormeur_lourd(v)

	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_social_foule -- la fraction sous la critique ne retourne jamais la foule, " +
			"au-dessus il faut la fenetre ENTIERE et l'emeute se defait quand la colere retombe, " +
			"la cohesion est une somme ponderee de quatre axes recalculee a neuf (jamais un +=), " +
			"le choc de la mort du chef la fait chuter puis se resorbe quand on le rend, " +
			"la dislocation est posee sous le seuil, la densite au-dessus du confort accumule un stress " +
			"proportionnel a l'exces et la surdensite se defait quand on disperse, " +
			"le bruit au-dessus du seuil PAR COLON penalise le sommeil et en dessous ne penalise rien, " +
			"surcout_action a un seul ecrivain qui reecrit en entier sans residu, " +
			"un domaine invente traverse le meme code, et sur le chemin reel les noms correspondent aux " +
			"entrees partagees, vingt colons portent quatre axes hauts, trois en colere ne suffisent pas " +
			"et quatre suffisent, les cases denses stressent et les aerees non")
		quit(0)

# ---------------------------------------------------------------------------
# Aides
# ---------------------------------------------------------------------------

func _monde() -> Dictionary:
	var cases: Array = Banc.construire_cases(CONFIG_QWIL)
	var colons: Array = Banc.construire_colons(CONFIG_QWIL)
	Banc.poser_liens(colons, CONFIG_QWIL)
	return {"cases": cases, "colons": colons}

func _tick(monde: Dictionary, delta: float) -> Dictionary:
	return Banc.avancer(monde.cases, monde.colons, CONFIG_QWIL, COMPTAGES_QWIL, SEUILS_QWIL, LIENS_QWIL, delta)

# Avance `secondes` par pas de PAS. Rend le dernier bilan. Un appel a 0.0
# seconde fait quand meme UN pas a delta nul -- c'est ce que fait _ready.
func _avancer(monde: Dictionary, secondes: float) -> Dictionary:
	var bilan := _tick(monde, 0.0)
	var ecoule := 0.0
	while ecoule < secondes - 0.0001:
		var delta: float = min(PAS, secondes - ecoule)
		bilan = _tick(monde, delta)
		ecoule += delta
	return bilan

func _par_id(objets: Array, id: String) -> Dictionary:
	for objet in objets:
		if String(objet.id) == id:
			return objet
	return {}

func _mettre_en_colere(monde: Dictionary, ids: Array) -> void:
	for id in ids:
		var colon := _par_id(monde.colons, String(id))
		colon.proprietes[String(CONFIG_QWIL.nom_colere)] = true

func _canal(objet: Dictionary, nom: String) -> Dictionary:
	return objet.proprietes.get("etats", {}).get(nom, {})

# ---------------------------------------------------------------------------
# Hors domaine
# ---------------------------------------------------------------------------

func _la_scene_se_monte(v) -> void:
	var monde := _monde()
	v.v(monde.cases.size() == 4, "la grille 2x2 doit donner quatre cases, recu %d" % monde.cases.size())
	v.v(monde.colons.size() == 6, "les six colons declares doivent etre construits, recu %d" % monde.colons.size())
	v.v(Banc.membres_de(monde.colons, CONFIG_QWIL).size() == 6, "les six colons doivent etre membres au depart")
	v.v(Banc.chef_vivant(monde.colons, CONFIG_QWIL), "le chef doit etre vivant au depart")
	var porteur := Banc.porteur_choc(monde.colons, CONFIG_QWIL)
	v.v(String(porteur.get("id", "")) == "chef_qwil", "le porteur du canal de choc doit etre le chef declare")
	# L'appariement colon/case, sans lequel rien d'autre ne tient.
	_tick(monde, 0.0)
	var un := _par_id(monde.colons, "un_qwil")
	v.v(String(un.proprietes.get(String(CONFIG_QWIL.nom_case_locale), "")) == "case_0_0",
		"un_qwil doit etre apparie a la case 0,0")
	v.v(String(_par_id(monde.colons, "cinq_qwil").proprietes.get(String(CONFIG_QWIL.nom_case_locale), "")) == "case_1_1",
		"cinq_qwil doit etre apparie a la case 1,1")

# Les liens sont vraiment poses dans le registre par paire de
# lien_personnel.gd, pas un nombre recopie a cote : on relit par
# LienPersonnel.force a travers le miroir plat que le banc ecrit.
func _les_liens_sont_un_registre_reel(v) -> void:
	var monde := _monde()
	_tick(monde, 0.0)
	var un := _par_id(monde.colons, "un_qwil")
	v.v(un.proprietes.liens_personnels.size() == 5,
		"un_qwil doit porter un lien vers chacun des cinq autres, recu %d" % un.proprietes.liens_personnels.size())
	v.v(is_equal_approx(float(un.proprietes.get(String(CONFIG_QWIL.nom_force_liens_locale), 0.0)), 1.6),
		"la moyenne des liens de un_qwil doit valoir sa force declaree 1.6")

# La fenetre n'est pas un nombre pose a cote du seuil : c'est LE seuil du canal.
# Sans ce verrou, changer poids_cause sans changer fenetre_s changerait la
# duree de bascule EN SILENCE.
func _la_fenetre_est_le_seuil_du_canal(v) -> void:
	var monde := _monde()
	var canal := _canal(_par_id(monde.colons, "un_qwil"), String(CONFIG_QWIL.nom_canal_emeute))
	var attendu: float = float(CONFIG_QWIL.foule.fenetre_s) * float(CONFIG_QWIL.foule.poids_cause)
	v.v(is_equal_approx(float(canal.seuil), attendu),
		"le seuil du canal d'emeute doit valoir fenetre_s x poids_cause (%f), recu %f" % [attendu, float(canal.seuil)])

func _sous_la_fraction_critique_rien_ne_bascule(v) -> void:
	var monde := _monde()
	# 1 sur 6 = 0.167, sous la critique 0.30.
	_mettre_en_colere(monde, ["un_qwil"])
	var bilan := _avancer(monde, 6.0)
	v.v(is_equal_approx(float(bilan.fraction_colere), 1.0 / 6.0),
		"la fraction doit valoir 1/6, recu %f" % float(bilan.fraction_colere))
	var un := _par_id(monde.colons, "un_qwil")
	v.v(not Banc.porte_etat(un, String(CONFIG_QWIL.etat_colere_majoritaire)),
		"sous la fraction critique, la colere majoritaire ne doit jamais etre posee")
	v.v(Banc.compter_etat(monde.colons, String(CONFIG_QWIL.etat_emeute)) == 0,
		"sous la fraction critique, aucune emeute ne doit etre posee meme apres trois fois la fenetre")
	v.v(is_equal_approx(float(_canal(un, String(CONFIG_QWIL.nom_canal_emeute)).charge), 0.0),
		"sans colere majoritaire, la charge d'emeute doit rester nulle")

func _au_dessus_il_faut_attendre_la_fenetre_entiere(v) -> void:
	var monde := _monde()
	# 2 sur 6 = 0.333, au-dessus de la critique 0.30.
	_mettre_en_colere(monde, ["un_qwil", "deux_qwil"])
	_avancer(monde, 1.0)
	var trois := _par_id(monde.colons, "trois_qwil")
	v.v(Banc.porte_etat(trois, String(CONFIG_QWIL.etat_colere_majoritaire)),
		"au-dessus de la critique, la colere majoritaire doit etre posee sur TOUS les colons, pas seulement les faches")
	v.v(Banc.compter_etat(monde.colons, String(CONFIG_QWIL.etat_emeute)) == 0,
		"une seconde apres, la fenetre de 2.0 s n'est pas ecoulee : aucune emeute encore")
	_avancer(monde, 2.0)
	v.v(Banc.compter_etat(monde.colons, String(CONFIG_QWIL.etat_emeute)) == 5,
		"la fenetre passee, les cinq porteurs du canal doivent tous etre en emeute, recu %d"
			% Banc.compter_etat(monde.colons, String(CONFIG_QWIL.etat_emeute)))

# LE TEST QUI EMPECHE DE REINTRODUIRE LE RACCOURCI (voir en-tete) : sans le
# miroir plat 0.0/1.0, charge.gd erase sa cle a la descente et seuil_etat.gd ne
# retire JAMAIS l'etat.
func _l_emeute_se_defait_quand_la_colere_retombe(v) -> void:
	var monde := _monde()
	_mettre_en_colere(monde, ["un_qwil", "deux_qwil"])
	_avancer(monde, 4.0)
	v.v(Banc.compter_etat(monde.colons, String(CONFIG_QWIL.etat_emeute)) > 0, "l'emeute doit d'abord etre posee")
	# Un seul colon revient au calme : 1/6 = 0.167, sous la critique.
	Banc.basculer_colere(_par_id(monde.colons, "deux_qwil"), CONFIG_QWIL)
	_avancer(monde, 6.0)
	var un := _par_id(monde.colons, "un_qwil")
	v.v(not un.proprietes.has(String(CONFIG_QWIL.nom_marqueur_emeute)),
		"charge.gd doit avoir efface son marqueur au franchissement descendant")
	v.v(is_equal_approx(float(un.proprietes.get(String(CONFIG_QWIL.nom_miroir_emeute), -1.0)), 0.0),
		"le miroir plat doit exister et valoir 0.0 -- c'est lui, et lui seul, que seuil_etat.gd peut encore comparer")
	v.v(Banc.compter_etat(monde.colons, String(CONFIG_QWIL.etat_emeute)) == 0,
		"l'emeute doit etre RETIREE quand la colere retombe : sans le miroir, elle resterait posee pour toujours")

func _la_cohesion_tient_avec_quatre_axes_hauts(v) -> void:
	var monde := _monde()
	var bilan := _avancer(monde, 1.0)
	var axes: Dictionary = bilan.axes
	# liens : moyenne(1.6+1.4+1.2+1.8+1.0+2.0)/6 = 1.5, sur reference 2.0.
	v.v(is_equal_approx(float(axes.liens), 0.75), "axe des liens attendu 0.75, recu %f" % float(axes.liens))
	v.v(is_equal_approx(float(axes.croyance), 5.0 / 6.0), "axe de croyance attendu 5/6, recu %f" % float(axes.croyance))
	v.v(is_equal_approx(float(axes.culture), 5.0 / 6.0), "axe de culture attendu 5/6, recu %f" % float(axes.culture))
	v.v(is_equal_approx(float(axes.vecu), 5.0 / 6.0), "axe de vecu attendu 5/6, recu %f" % float(axes.vecu))
	var attendue: float = 3.0 * 0.75 + 3.0 * (5.0 / 6.0) + 2.0 * (5.0 / 6.0) + 2.0 * (5.0 / 6.0)
	v.v(is_equal_approx(float(bilan.cohesion.cohesion), attendue),
		"la cohesion doit etre la somme ponderee des quatre axes (%f), recu %f" % [attendue, float(bilan.cohesion.cohesion)])
	v.v(Banc.compter_etat(monde.colons, String(CONFIG_QWIL.etat_disloque)) == 0,
		"avec quatre axes hauts, le groupe ne doit pas etre disloque")
	# La cohesion vit PAR COLON, la meme valeur sur chacun -- jamais un objet-groupe.
	for colon in monde.colons:
		v.v(is_equal_approx(float(colon.proprietes.get(String(CONFIG_QWIL.nom_cohesion), -1.0)), attendue),
			"la cohesion doit etre ecrite sur CHAQUE colon, %s ne la porte pas" % String(colon.id))

func _le_choc_du_chef_fait_chuter_la_cohesion(v) -> void:
	var monde := _monde()
	var avant := _avancer(monde, 1.0)
	Banc.basculer_chef(Banc.porteur_choc(monde.colons, CONFIG_QWIL), CONFIG_QWIL)
	var apres := _avancer(monde, 1.0)
	v.v(not bool(apres.chef_vivant), "apres la bascule, le chef ne doit plus etre vivant")
	v.v(Banc.membres_de(monde.colons, CONFIG_QWIL).size() == 5,
		"le chef mort ne compte plus parmi les membres, le denominateur doit tomber a 5")
	v.v(float(apres.charge_choc) > 0.0, "charge.gd doit accumuler le choc tant que la place de chef est vide")
	v.v(float(apres.cohesion.malus) > 0.0, "le choc doit entrer dans la somme comme un terme de signe oppose")
	v.v(float(apres.cohesion.cohesion) < float(avant.cohesion.cohesion),
		"la cohesion doit chuter (avant %f, apres %f)" % [float(avant.cohesion.cohesion), float(apres.cohesion.cohesion)])

func _la_dislocation_est_posee_sous_le_seuil(v) -> void:
	var monde := _monde()
	_avancer(monde, 1.0)
	Banc.basculer_chef(Banc.porteur_choc(monde.colons, CONFIG_QWIL), CONFIG_QWIL)
	var bilan := _avancer(monde, 3.0)
	v.v(float(bilan.cohesion.manque) > 5.0,
		"le manque de cohesion doit depasser le seuil 5.0, recu %f" % float(bilan.cohesion.manque))
	v.v(Banc.compter_etat(monde.colons, String(CONFIG_QWIL.etat_disloque)) == 6,
		"sous le seuil, la dislocation doit etre posee sur les six colons, recu %d"
			% Banc.compter_etat(monde.colons, String(CONFIG_QWIL.etat_disloque)))

func _le_choc_se_resorbe_quand_on_rend_le_chef(v) -> void:
	var monde := _monde()
	_avancer(monde, 1.0)
	var porteur := Banc.porteur_choc(monde.colons, CONFIG_QWIL)
	Banc.basculer_chef(porteur, CONFIG_QWIL)
	_avancer(monde, 3.0)
	v.v(Banc.compter_etat(monde.colons, String(CONFIG_QWIL.etat_disloque)) > 0, "le groupe doit d'abord etre disloque")
	Banc.basculer_chef(porteur, CONFIG_QWIL)
	var bilan := _avancer(monde, 5.0)
	v.v(is_equal_approx(float(bilan.charge_choc), 0.0),
		"la charge de choc doit redescendre a zero d'elle-meme, recu %f" % float(bilan.charge_choc))
	v.v(Banc.compter_etat(monde.colons, String(CONFIG_QWIL.etat_disloque)) == 0,
		"la dislocation doit etre retiree quand la cohesion remonte -- rien ne la retire a la main")

# Le champ derive ne derive pas : a monde inchange, la valeur est la MEME apres
# cent ticks qu'apres un seul. Un '+=' quelque part la ferait grimper sans borne.
func _la_cohesion_est_recalculee_a_neuf(v) -> void:
	var monde := _monde()
	var premier := _avancer(monde, 0.1)
	var centieme := _avancer(monde, 10.0)
	v.v(is_equal_approx(float(premier.cohesion.cohesion), float(centieme.cohesion.cohesion)),
		"a monde inchange la cohesion ne doit pas bouger d'un tick a l'autre (%f puis %f)"
			% [float(premier.cohesion.cohesion), float(centieme.cohesion.cohesion)])

func _la_densite_au_dessus_du_confort_accumule_du_stress(v) -> void:
	var monde := _monde()
	var bilan := _avancer(monde, 1.0)
	var dense := _par_id(monde.cases, "case_0_0")
	v.v(is_equal_approx(float(dense.proprietes.get(String(CONFIG_QWIL.nom_densite_locale), 0.0)), 4.0),
		"la case 0,0 doit porter quatre colons")
	# exces = 4 - 2 = 2, stress_par_point 1.0 -> 2.0/s. Apres 1.0 s : 2.0.
	v.v(is_equal_approx(float(_canal(dense, String(CONFIG_QWIL.nom_canal_stress)).charge), 2.0),
		"le stress doit monter a l'exces x stress_par_point x delta (2.0 attendu), recu %f"
			% float(_canal(dense, String(CONFIG_QWIL.nom_canal_stress)).charge))
	v.v(not Banc.porte_etat(dense, String(CONFIG_QWIL.etat_surdensite)),
		"sous le seuil de stress 3.0, la surdensite ne doit pas encore etre posee")
	_avancer(monde, 1.0)
	v.v(Banc.porte_etat(dense, String(CONFIG_QWIL.etat_surdensite)),
		"le seuil de stress passe, la surdensite doit etre posee sur la CASE")
	v.v(bilan.axes.membres == 6, "le comptage des membres ne doit pas etre affecte par la densite")

func _la_densite_au_confort_n_accumule_rien(v) -> void:
	var monde := _monde()
	_avancer(monde, 5.0)
	var seule := _par_id(monde.cases, "case_1_1")
	v.v(is_equal_approx(float(seule.proprietes.get(String(CONFIG_QWIL.nom_densite_locale), 0.0)), 1.0),
		"la case 1,1 ne porte qu'un colon")
	v.v(is_equal_approx(float(_canal(seule, String(CONFIG_QWIL.nom_canal_stress)).charge), 0.0),
		"sous le confort, aucune cause n'est construite : la charge doit rester nulle")
	v.v(not Banc.porte_etat(seule, String(CONFIG_QWIL.etat_surdensite)),
		"une case au confort ne doit jamais etre en surdensite")

func _la_surdensite_se_defait_quand_on_disperse(v) -> void:
	var monde := _monde()
	_avancer(monde, 3.0)
	var dense := _par_id(monde.cases, "case_0_0")
	v.v(Banc.porte_etat(dense, String(CONFIG_QWIL.etat_surdensite)), "la surdensite doit d'abord etre posee")
	# On disperse a la main : trois des quatre partent hors grille.
	for id in ["un_qwil", "deux_qwil", "trois_qwil"]:
		_par_id(monde.colons, id).position = Vector3(-900.0, -900.0, 0.0)
	_avancer(monde, 5.0)
	v.v(is_equal_approx(float(_canal(dense, String(CONFIG_QWIL.nom_canal_stress)).charge), 0.0),
		"la charge doit redescendre a zero quand la case repasse sous le confort")
	v.v(is_equal_approx(float(dense.proprietes.get(String(CONFIG_QWIL.nom_miroir_stress), -1.0)), 0.0),
		"le miroir plat de stress doit exister et valoir 0.0")
	v.v(not Banc.porte_etat(dense, String(CONFIG_QWIL.etat_surdensite)),
		"la surdensite doit etre RETIREE : sans le miroir, elle resterait posee pour toujours")

func _le_bruit_au_dessus_du_seuil_penalise_le_sommeil(v) -> void:
	var monde := _monde()
	_avancer(monde, 1.0)
	var chef := _par_id(monde.colons, "chef_qwil")
	v.v(is_equal_approx(float(chef.proprietes.get(String(CONFIG_QWIL.nom_bruit_local), 0.0)), 0.70),
		"le bruit de la case doit etre recopie en cle plate sur le colon")
	v.v(Banc.porte_etat(chef, String(CONFIG_QWIL.etat_gene_bruit)),
		"le chef, dormeur leger (seuil 0.30), doit etre gene par un bruit de 0.70")
	var canal: Dictionary = chef.proprietes.reserves[String(CONFIG_QWIL.nom_reserve_sommeil)]
	v.v(is_equal_approx(float(canal.surcout_action), 0.70 * 5.0),
		"le surcout doit valoir bruit x penalite (3.5), recu %f" % float(canal.surcout_action))
	v.v(float(canal.reserve) < float(CONFIG_QWIL.sommeil.reserve_initiale),
		"le sommeil du chef doit reellement descendre : la penalite depasse la recuperation")

func _le_bruit_sous_le_seuil_ne_penalise_pas(v) -> void:
	var monde := _monde()
	_avancer(monde, 1.0)
	var lourd := _par_id(monde.colons, "cinq_qwil")
	v.v(is_equal_approx(float(lourd.proprietes.get(String(CONFIG_QWIL.nom_bruit_local), 0.0)), 0.70),
		"le dormeur lourd subit EXACTEMENT le meme bruit que le chef")
	v.v(not Banc.porte_etat(lourd, String(CONFIG_QWIL.etat_gene_bruit)),
		"avec un seuil de 0.90, un bruit de 0.70 ne doit pas gener -- c'est le seuil PAR COLON qui tranche")
	var canal: Dictionary = lourd.proprietes.reserves[String(CONFIG_QWIL.nom_reserve_sommeil)]
	v.v(is_equal_approx(float(canal.surcout_action), 0.0), "sans gene, le surcout doit valoir exactement 0.0")
	v.v(is_equal_approx(float(canal.reserve), float(CONFIG_QWIL.sommeil.capacite)),
		"sans gene, le sommeil remonte et reste ecrete a sa capacite")

# depense.gd n'a QU'UN emplacement surcout_action par canal : deux morceaux de
# cablage qui y ecriraient chacun le leur se detruiraient EN SILENCE. Le verrou
# porte sur la CONSEQUENCE testable de l'unique ecrivain -- ecriture COMPLETE a
# chaque appel, jamais un '+=', et retour exact a 0.0 sans residu.
func _un_seul_ecrivain_pour_surcout_action(v) -> void:
	var monde := _monde()
	_avancer(monde, 1.0)
	var chef := _par_id(monde.colons, "chef_qwil")
	var canal: Dictionary = chef.proprietes.reserves[String(CONFIG_QWIL.nom_reserve_sommeil)]
	var apres_un_tick: float = float(canal.surcout_action)
	Banc.poser_couts(monde.colons, CONFIG_QWIL)
	Banc.poser_couts(monde.colons, CONFIG_QWIL)
	v.v(is_equal_approx(float(canal.surcout_action), apres_un_tick),
		"deux appels de plus ne doivent rien ajouter : l'ecriture est complete, jamais un '+=' (recu %f contre %f)"
			% [float(canal.surcout_action), apres_un_tick])
	v.v(is_equal_approx(float(canal.cout_base), -float(CONFIG_QWIL.sommeil.recuperation_par_s)),
		"le meme ecrivain pose le cout_base NEGATIF de recuperation, jamais un second morceau de cablage")
	# On rend le silence : le surcout doit retomber exactement a 0.0, sans residu.
	_par_id(monde.cases, "case_1_0").proprietes[String(CONFIG_QWIL.nom_bruit)] = 0.0
	_avancer(monde, 1.0)
	v.v(is_equal_approx(float(canal.surcout_action), 0.0),
		"rendu au silence, le surcout doit retomber a exactement 0.0, recu %f" % float(canal.surcout_action))

# Les trois familles de porteurs sont disjointes -- c'est ce qui empeche les
# causes d'un canal d'alimenter un autre (voir l'en-tete du banc, TROIS
# PORTEURS). Si un jour le chef recevait aussi le canal d'emeute, ce test
# rougirait AVANT que la cohesion ne se mette a monter avec la colere.
func _le_chef_ne_porte_pas_le_canal_d_emeute(v) -> void:
	var monde := _monde()
	var chef := _par_id(monde.colons, "chef_qwil")
	v.v(not _canal(chef, String(CONFIG_QWIL.nom_canal_emeute)).has("charge"),
		"le chef ne doit PAS porter le canal d'emeute")
	v.v(_canal(chef, String(CONFIG_QWIL.nom_canal_choc)).has("charge"),
		"le chef doit porter le canal de choc")
	var porteurs := Banc.porteurs_emeute(monde.colons, CONFIG_QWIL)
	v.v(porteurs.size() == 5, "cinq colons doivent porter le canal d'emeute, recu %d" % porteurs.size())
	for case in monde.cases:
		v.v(_canal(case, String(CONFIG_QWIL.nom_canal_stress)).has("charge"),
			"chaque case doit porter le canal de stress")
		v.v(not _canal(case, String(CONFIG_QWIL.nom_canal_emeute)).has("charge"),
			"aucune case ne doit porter le canal d'emeute")

# ---------------------------------------------------------------------------
# Chemin reel
# ---------------------------------------------------------------------------

func _charger(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _reel() -> Dictionary:
	return {
		"config": _charger("res://data/banc_social_foule.json"),
		"comptages": _charger("res://data/comptages.json"),
		"seuils": _charger("res://data/seuils_etat.json"),
		"etats": _charger("res://data/etats.json"),
		"liens": _charger("res://data/liens_personnels.json"),
	}

func _monde_reel(reel: Dictionary) -> Dictionary:
	var cases: Array = Banc.construire_cases(reel.config)
	var colons: Array = Banc.construire_colons(reel.config)
	Banc.poser_liens(colons, reel.config)
	return {"cases": cases, "colons": colons}

func _avancer_reel(reel: Dictionary, monde: Dictionary, secondes: float) -> Dictionary:
	var bilan: Dictionary = Banc.avancer(monde.cases, monde.colons, reel.config, reel.comptages, reel.seuils, reel.liens, 0.0)
	var ecoule := 0.0
	while ecoule < secondes - 0.0001:
		var delta: float = min(PAS, secondes - ecoule)
		bilan = Banc.avancer(monde.cases, monde.colons, reel.config, reel.comptages, reel.seuils, reel.liens, delta)
		ecoule += delta
	return bilan

# CE QU'AUCUN AUTRE TEST NE VERIFIE : que le nom que le banc ECRIT est bien
# celui que l'entree partagee COMPARE. Leur divergence serait SILENCIEUSE -- un
# miroir ecrit sous un nom que plus personne ne compare, aucun etat pose, aucune
# alarme.
func _reel_les_noms_ecrits_sont_ceux_que_les_seuils_comparent(v) -> void:
	var reel := _reel()
	var config: Dictionary = reel.config
	var seuils: Dictionary = reel.seuils
	var paires := [
		["foule_colere", String(config.nom_fraction_colere), String(config.etat_colere_majoritaire)],
		["emeute", String(config.nom_miroir_emeute), String(config.etat_emeute)],
		["cohesion_disloquee", String(config.nom_manque_cohesion), String(config.etat_disloque)],
		["surdensite", String(config.nom_miroir_stress), String(config.etat_surdensite)],
		["gene_bruit", String(config.nom_bruit_local), String(config.etat_gene_bruit)],
	]
	for paire in paires:
		var ref: String = paire[0]
		v.v(seuils.has(ref), "l'entree de seuil '%s' doit exister dans data/seuils_etat.json" % ref)
		if not seuils.has(ref):
			continue
		v.v(String(seuils[ref].propriete_continue) == String(paire[1]),
			"l'entree '%s' doit comparer '%s', elle compare '%s'" % [ref, String(paire[1]), String(seuils[ref].propriete_continue)])
		v.v(String(seuils[ref].etat) == String(paire[2]),
			"l'entree '%s' doit poser '%s', elle pose '%s'" % [ref, String(paire[2]), String(seuils[ref].etat)])
	v.v(String(seuils.gene_bruit.get("seuil_propriete", "")) == String(config.nom_seuil_gene),
		"l'entree 'gene_bruit' doit lire son seuil PAR COLON sous le nom que le banc pose")
	v.v(is_equal_approx(float(seuils.foule_colere.seuil), float(config.foule.fraction_critique)),
		"le seuil partage et la fraction critique du banc doivent etre le MEME nombre")

func _reel_les_etats_et_les_regles_existent(v) -> void:
	var reel := _reel()
	var config: Dictionary = reel.config
	for cle in ["etat_colere", "etat_colere_majoritaire", "etat_emeute", "etat_disloque", "etat_surdensite", "etat_gene_bruit"]:
		var nom := String(config[cle])
		v.v(reel.etats.has(nom), "l'etat '%s' (config.%s) doit exister dans data/etats.json" % [nom, cle])
	for cle in ["regle_membres", "regle_colere", "regle_croyance_partagee", "regle_culture_partagee", "regle_vecu_suffisant"]:
		var nom := String(config[cle])
		v.v(reel.comptages.has(nom), "la regle '%s' (config.%s) doit exister dans data/comptages.json" % [nom, cle])

func _reel_vingt_colons_un_chef_quatre_axes_hauts(v) -> void:
	var reel := _reel()
	var monde := _monde_reel(reel)
	v.v(monde.colons.size() == 20, "vingt colons doivent etre declares, recu %d" % monde.colons.size())
	v.v(monde.cases.size() == 16, "la grille 4x4 doit donner seize cases, recu %d" % monde.cases.size())
	v.v(Banc.porteurs_emeute(monde.colons, reel.config).size() == 19,
		"dix-neuf colons portent le canal d'emeute (le chef ne bascule pas avec la foule)")
	var bilan := _avancer_reel(reel, monde, 1.0)
	var axes: Dictionary = bilan.axes
	v.v(is_equal_approx(float(axes.liens), 0.74), "axe des liens attendu 0.74, recu %f" % float(axes.liens))
	v.v(is_equal_approx(float(axes.croyance), 0.85), "axe de croyance attendu 0.85 (17/20), recu %f" % float(axes.croyance))
	v.v(is_equal_approx(float(axes.culture), 0.80), "axe de culture attendu 0.80 (16/20), recu %f" % float(axes.culture))
	v.v(is_equal_approx(float(axes.vecu), 0.75), "axe de vecu attendu 0.75 (15/20), recu %f" % float(axes.vecu))
	v.v(is_equal_approx(float(bilan.cohesion.cohesion), 0.7845),
		"la cohesion de depart attendue 0.7845, recu %f" % float(bilan.cohesion.cohesion))
	v.v(float(bilan.cohesion.manque) < float(reel.seuils.cohesion_disloquee.seuil),
		"avec quatre axes hauts, le manque doit rester sous le seuil de dislocation")
	v.v(Banc.compter_etat(monde.colons, String(reel.config.etat_disloque)) == 0,
		"aucun colon ne doit etre disloque au repos")

# LA CALIBRATION LA PLUS FRAGILE DU BANC, et la consequence directe du '>'
# strict de seuil_etat.gd : sur vingt colons, trois font EXACTEMENT 0.15 et ne
# suffisent PAS ; il en faut quatre.
func _reel_trois_en_colere_ne_suffisent_pas_quatre_suffisent(v) -> void:
	var reel := _reel()
	var monde := _monde_reel(reel)
	var cle := String(reel.config.nom_colere)
	# Deux sont deja en colere en donnee -- on monte a trois.
	monde.colons[1].proprietes[cle] = true
	var bilan := _avancer_reel(reel, monde, 6.0)
	v.v(is_equal_approx(float(bilan.fraction_colere), 0.15),
		"trois sur vingt doivent faire exactement 0.15, recu %f" % float(bilan.fraction_colere))
	v.v(Banc.compter_etat(monde.colons, String(reel.config.etat_emeute)) == 0,
		"0.15 n'est pas > 0.15 : aucune emeute, meme apres deux fois la fenetre")
	monde.colons[2].proprietes[cle] = true
	var apres := _avancer_reel(reel, monde, 6.0)
	v.v(is_equal_approx(float(apres.fraction_colere), 0.20),
		"quatre sur vingt doivent faire 0.20, recu %f" % float(apres.fraction_colere))
	v.v(Banc.compter_etat(monde.colons, String(reel.config.etat_emeute)) == 19,
		"au-dessus de la critique et la fenetre passee, les dix-neuf porteurs doivent etre en emeute, recu %d"
			% Banc.compter_etat(monde.colons, String(reel.config.etat_emeute)))

func _reel_les_cases_denses_stressent_les_aerees_non(v) -> void:
	var reel := _reel()
	var monde := _monde_reel(reel)
	_avancer_reel(reel, monde, 5.0)
	for id in ["case_0_0", "case_1_0", "case_0_1", "case_1_1"]:
		var dense := _par_id(monde.cases, id)
		v.v(is_equal_approx(float(dense.proprietes.get(String(reel.config.nom_densite_locale), 0.0)), 3.0),
			"la case dense %s doit porter trois colons" % id)
		v.v(Banc.porte_etat(dense, String(reel.config.etat_surdensite)),
			"la case dense %s doit etre en surdensite apres cinq secondes" % id)
	for id in ["case_2_2", "case_3_2", "case_2_3", "case_3_3"]:
		var aeree := _par_id(monde.cases, id)
		v.v(is_equal_approx(float(aeree.proprietes.get(String(reel.config.nom_densite_locale), 0.0)), 2.0),
			"la case aeree %s doit porter deux colons" % id)
		v.v(not Banc.porte_etat(aeree, String(reel.config.etat_surdensite)),
			"la case aeree %s, exactement au confort, ne doit jamais stresser" % id)

func _reel_la_colonne_bruyante_derange_sauf_le_dormeur_lourd(v) -> void:
	var reel := _reel()
	var monde := _monde_reel(reel)
	_avancer_reel(reel, monde, 2.0)
	var etat_gene := String(reel.config.etat_gene_bruit)
	for id in ["aere_c", "aere_g", "chef"]:
		var gene := _par_id(monde.colons, id)
		v.v(Banc.porte_etat(gene, etat_gene), "%s dort sur la colonne bruyante et doit etre gene" % id)
		v.v(float(Banc.sommeil_de(gene, reel.config)) < float(reel.config.sommeil.capacite),
			"%s doit reellement perdre du sommeil" % id)
	var lourd := _par_id(monde.colons, "aere_d")
	v.v(is_equal_approx(float(lourd.proprietes.get(String(reel.config.nom_bruit_local), 0.0)), 0.8),
		"aere_d subit le meme bruit de 0.8 que ses voisins")
	v.v(not Banc.porte_etat(lourd, etat_gene),
		"aere_d, dormeur lourd (seuil 0.9), ne doit pas etre gene par un bruit de 0.8")
	v.v(is_equal_approx(float(Banc.sommeil_de(lourd, reel.config)), float(reel.config.sommeil.capacite)),
		"aere_d doit garder son sommeil plein")
	# Les colons du silence : personne d'autre n'est gene.
	v.v(Banc.compter_etat(monde.colons, etat_gene) == 3,
		"exactement trois colons doivent etre genes, recu %d" % Banc.compter_etat(monde.colons, etat_gene))
