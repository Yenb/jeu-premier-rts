extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_inflammabilite.gd
#
# Verrouille les fonctions statiques testables de banc_inflammabilite.gd
# (diagnostiquer/_teinte_pour_diagnostic/_ratio_exposition/
# _texte_composition/_texte_statut/_evenement/_ligne_log) et, CHEMIN REEL
# (meme regime que test_banc_champ.gd/test_banc_etat_effectif.gd), la
# fabrication effective des quatre objets du banc depuis data/
# banc_inflammabilite.json + data/materiaux.json + data/
# proprietes_immuables_composition.json + data/intensite_propagation.json
# + data/etats.json + data/menaces.json, lus sur disque -- jamais une
# fixture inventee pour ces six catalogues.

const BancInflammabilite = preload("res://scripts/banc_inflammabilite.gd")
const Objet = preload("res://scripts/objet.gd")
const Propagation = preload("res://scripts/propagation.gd")
const Verif = preload("res://scripts/verif.gd")

const MENACES := {"inflammable": "brule"}
const INTENSITE := {"propriete_intensite": "inflammabilite", "seuil_ignition": 0.1}
const ETATS := {
	"mouille": {"effets": [{"propriete": "inflammabilite", "mode": "ecraser", "valeur": 0.0}]},
}

func _init() -> void:
	var v := Verif.new()
	_diagnostiquer_en_feu(v)
	_diagnostiquer_bloque_seuil(v)
	_diagnostiquer_bloque_etat(v)
	_diagnostiquer_intact(v)
	_diagnostiquer_expose(v)
	_teinte_fixe_et_distincte_par_statut_bloque(v)
	_teinte_expose_plus_rouge_avec_le_ratio(v)
	_ratio_exposition_borne_et_nul_si_bloque(v)
	_texte_composition_mono_et_composite_et_etat(v)
	_texte_statut_et_evenement_distinguent_les_deux_blocages(v)
	_texte_label_expose_porte_l_exposition_vive_et_le_delai_chiffre(v)
	_texte_label_bloque_seuil_affiche_jamais(v)
	_texte_label_en_feu_affiche_delai_chiffre_et_temps_mis_jamais_jamais_ni_zero(v)
	_ligne_log_en_feu_porte_le_temps_reellement_mis(v)
	_donnees_reelles_quatre_objets_bon_role(v)
	_donnees_reelles_bois_vif_s_enflamme_plus_vite_que_melange(v)
	_chemin_reel_bois_vif_s_enflamme_et_le_label_dit_la_verite(v)
	_diagnostiquer_tout_ne_confond_jamais_deux_objets(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_inflammabilite.gd -- diagnostic compose EtatEffectif/Propagation.delai_ignition " +
			"sans jamais reimplementer leur loi, teinte/texte distinguent bloque_seuil de bloque_etat, " +
			"chemin reel verifie sur les quatre objets de data/banc_inflammabilite.json")
		quit(0)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _chose(effective_base: float, etats_actifs: Array, brule: bool = false) -> Dictionary:
	return {
		"id": "z",
		"position": Vector3.ZERO,
		"proprietes": {
			"inflammabilite": effective_base, "etats_actifs": etats_actifs, "brule": brule,
			"delai_propagation": 2.0,
		},
	}

func _diagnostiquer_en_feu(v) -> void:
	var chose := _chose(0.9, [], true)
	var diag := BancInflammabilite.diagnostiquer(chose, 0.0, "inflammable", MENACES, INTENSITE, ETATS)
	v.v(diag.statut == "en_feu", "une chose deja 'brule' doit rendre le statut 'en_feu', quelle que soit son exposition")

func _diagnostiquer_bloque_seuil(v) -> void:
	var chose := _chose(0.02, [])
	var diag := BancInflammabilite.diagnostiquer(chose, 0.0, "inflammable", MENACES, INTENSITE, ETATS)
	v.v(diag.statut == "bloque_seuil", "une intensite intrinsequement sous le seuil, sans etat actif, doit rendre 'bloque_seuil'")
	v.v(diag.raison_etat == "", "'bloque_seuil' ne doit jamais porter de nom d'etat -- rien n'ecrase, c'est la base qui est basse")

func _diagnostiquer_bloque_etat(v) -> void:
	var chose := _chose(0.9, ["mouille"])
	var diag := BancInflammabilite.diagnostiquer(chose, 0.0, "inflammable", MENACES, INTENSITE, ETATS)
	v.v(diag.statut == "bloque_etat", "une base haute (0.9) ECRASEE par un etat doit rendre 'bloque_etat', jamais 'bloque_seuil'")
	v.v(diag.raison_etat == "mouille", "'bloque_etat' doit nommer l'etat gagnant ('mouille')")

func _diagnostiquer_intact(v) -> void:
	var chose := _chose(0.9, [])
	var diag := BancInflammabilite.diagnostiquer(chose, 0.0, "inflammable", MENACES, INTENSITE, ETATS)
	v.v(diag.statut == "intact", "au-dessus du seuil mais sans exposition accumulee, le statut doit etre 'intact'")

func _diagnostiquer_expose(v) -> void:
	var chose := _chose(0.9, [])
	var diag := BancInflammabilite.diagnostiquer(chose, 0.5, "inflammable", MENACES, INTENSITE, ETATS)
	v.v(diag.statut == "expose", "au-dessus du seuil, avec de l'exposition accumulee, le statut doit etre 'expose'")

func _teinte_fixe_et_distincte_par_statut_bloque(v) -> void:
	var diag_seuil := {"statut": "bloque_seuil", "effective": 0.02, "delai_requis": -1.0, "raison_etat": ""}
	var diag_etat := {"statut": "bloque_etat", "effective": 0.0, "delai_requis": -1.0, "raison_etat": "mouille"}
	var diag_feu := {"statut": "en_feu", "effective": 0.9, "delai_requis": 2.22, "raison_etat": ""}
	var teinte_seuil := BancInflammabilite._teinte_pour_diagnostic(diag_seuil, 0.0)
	var teinte_etat := BancInflammabilite._teinte_pour_diagnostic(diag_etat, 0.0)
	var teinte_feu := BancInflammabilite._teinte_pour_diagnostic(diag_feu, 0.0)
	v.v(teinte_seuil != teinte_etat,
		"'bloque_seuil' et 'bloque_etat' doivent avoir des teintes DIFFERENTES -- deux raisons de ne jamais s'enflammer, distinguables a l'oeil")
	v.v(teinte_seuil != teinte_feu and teinte_etat != teinte_feu,
		"aucun statut bloque ne doit partager sa teinte avec 'en_feu'")

func _teinte_expose_plus_rouge_avec_le_ratio(v) -> void:
	var diag := {"statut": "expose", "effective": 0.9, "delai_requis": 2.0, "raison_etat": ""}
	var teinte_faible := BancInflammabilite._teinte_pour_diagnostic(diag, 0.2)
	var teinte_forte := BancInflammabilite._teinte_pour_diagnostic(diag, 1.8)
	v.v(teinte_forte.r >= teinte_faible.r and teinte_forte.g <= teinte_faible.g,
		"plus l'exposition approche le delai requis, plus la teinte doit virer au rouge (moins de vert)")

func _ratio_exposition_borne_et_nul_si_bloque(v) -> void:
	v.v(is_equal_approx(BancInflammabilite._ratio_exposition(1.0, 2.0), 0.5), "ratio nominal = exposition / delai_requis")
	v.v(is_equal_approx(BancInflammabilite._ratio_exposition(5.0, 2.0), 1.0), "ratio ne doit jamais depasser 1.0, meme exposition superieure au delai")
	v.v(is_equal_approx(BancInflammabilite._ratio_exposition(3.0, -1.0), 0.0), "delai_requis negatif (bloque) doit rendre un ratio nul, jamais une division invalide")

func _texte_composition_mono_et_composite_et_etat(v) -> void:
	var mono := BancInflammabilite._texte_composition([{"materiau": "fer", "volume": 3.0}], [])
	v.v(mono.find("fer") != -1 and mono.find("3.0") != -1, "composition mono-materiau doit nommer le materiau et son volume")
	var composite := BancInflammabilite._texte_composition(
		[{"materiau": "bois", "volume": 1.0}, {"materiau": "pierre", "volume": 4.0}], [])
	v.v(composite.find("bois") != -1 and composite.find("pierre") != -1, "composition composite doit nommer les DEUX materiaux")
	var avec_etat := BancInflammabilite._texte_composition([{"materiau": "bois", "volume": 3.0}], ["mouille"])
	v.v(avec_etat.find("mouille") != -1, "un etat actif doit apparaitre dans le texte de composition")

func _texte_statut_et_evenement_distinguent_les_deux_blocages(v) -> void:
	var diag_seuil := {"statut": "bloque_seuil", "effective": 0.02, "delai_requis": -1.0, "raison_etat": ""}
	var diag_etat := {"statut": "bloque_etat", "effective": 0.0, "delai_requis": -1.0, "raison_etat": "mouille"}
	var texte_seuil := BancInflammabilite._texte_statut(diag_seuil, 0.1)
	var texte_etat := BancInflammabilite._texte_statut(diag_etat, 0.1)
	v.v(texte_seuil.find("seuil") != -1, "le texte de statut 'bloque_seuil' doit mentionner le seuil")
	v.v(texte_etat.find("mouille") != -1, "le texte de statut 'bloque_etat' doit nommer l'etat")
	var evt_seuil := BancInflammabilite._evenement(diag_seuil, 0.1)
	var evt_etat := BancInflammabilite._evenement(diag_etat, 0.1)
	v.v(evt_seuil != evt_etat, "les evenements console des deux blocages doivent etre des phrases differentes")

func _texte_label_expose_porte_l_exposition_vive_et_le_delai_chiffre(v) -> void:
	var diag := {"statut": "expose", "effective": 0.9, "delai_requis": 2.22, "raison_etat": ""}
	var texte := BancInflammabilite._texte_label("bois_vif", "3.0 bois", diag, 1.10, 0.1, 0.0)
	v.v(texte.find("exposition=1.10s") != -1, "hors allumage, le label doit porter l'exposition VIVE telle quelle")
	v.v(texte.find("delai_requis=2.22s") != -1, "le label doit porter le delai requis chiffre")
	v.v(texte.find("temps_mis") == -1, "hors allumage, le champ 'temps_mis' ne doit jamais apparaitre -- seul 'exposition' a un sens")

func _texte_label_bloque_seuil_affiche_jamais(v) -> void:
	var diag := {"statut": "bloque_seuil", "effective": 0.02, "delai_requis": -1.0, "raison_etat": ""}
	var texte := BancInflammabilite._texte_label("fer_inerte", "3.0 fer", diag, 0.0, 0.1, 0.0)
	v.v(texte.find("delai_requis=jamais") != -1,
		"un objet structurellement bloque doit toujours afficher 'jamais' -- CE sens-la de -1.0 reste correct, inchange")

func _texte_label_en_feu_affiche_delai_chiffre_et_temps_mis_jamais_jamais_ni_zero(v) -> void:
	var diag := {"statut": "en_feu", "effective": 0.9, "delai_requis": 2.22, "raison_etat": ""}
	var texte := BancInflammabilite._texte_label("bois_vif", "3.0 bois", diag, 0.0, 0.1, 2.30)
	v.v(texte.find("jamais") == -1, "un objet EN FEU ne doit PLUS JAMAIS afficher 'jamais' comme delai_requis -- il s'est enflamme, la preuve qu'un delai fini existait")
	v.v(texte.find("delai_requis=2.22s") != -1, "le label doit porter le VRAI delai requis chiffre, meme une fois en feu")
	v.v(texte.find("temps_mis=2.30s") != -1, "le label doit porter le temps REELLEMENT mis, distinct du delai requis theorique")
	v.v(texte.find("exposition=") == -1,
		"un objet EN FEU ne doit plus afficher le champ 'exposition' -- il vaudrait toujours 0.00s (remis a zero par propagation.gd), un mensonge visuel")

func _ligne_log_en_feu_porte_le_temps_reellement_mis(v) -> void:
	var diag := {"statut": "en_feu", "effective": 0.9, "delai_requis": 2.22, "raison_etat": ""}
	var ligne := BancInflammabilite._ligne_log(4.2, "bois_vif", diag, 0.0, 0.1, 2.30)
	v.v(ligne.find("bois_vif") != -1 and ligne.find("0.90") != -1 and ligne.find("2.30") != -1 and ligne.find("ALLUMAGE") != -1,
		"la ligne ALLUMAGE doit porter l'objet, l'inflammabilite effective, le temps REELLEMENT mis et l'evenement")
	v.v(ligne.find("0.00") == -1,
		"la ligne ALLUMAGE ne doit plus jamais afficher 0.00s -- ce serait l'exposition vive, deja remise a zero par propagation.gd au meme tick")

func _donnees_reelles_quatre_objets_bon_role(v) -> void:
	var donnees := _charger_json("res://data/banc_inflammabilite.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var intensite := _charger_json("res://data/intensite_propagation.json")
	var etats := _charger_json("res://data/etats.json")
	var delai_base: float = donnees.delai_propagation_base

	var catalogue_types: Dictionary = {}
	for decl in donnees.objets:
		catalogue_types[decl.id] = {
			"inflammable": true, "portee_propagation": donnees.portee_propagation,
			"delai_propagation": delai_base, "composition": decl.composition,
		}

	var choses: Dictionary = {}
	for decl in donnees.objets:
		var o := Objet.fabriquer(decl.id, decl.id, Vector3.ZERO, catalogue_types, materiaux, proprietes_immuables)
		o.proprietes["etats_actifs"] = decl.get("etats_actifs", [])
		choses[decl.id] = o

	var diag_vif := BancInflammabilite.diagnostiquer(choses.bois_vif, 0.0, "inflammable", MENACES, intensite, etats)
	var diag_melange := BancInflammabilite.diagnostiquer(choses.melange, 0.0, "inflammable", MENACES, intensite, etats)
	var diag_fer := BancInflammabilite.diagnostiquer(choses.fer_inerte, 0.0, "inflammable", MENACES, intensite, etats)
	var diag_mouille := BancInflammabilite.diagnostiquer(choses.bois_mouille, 0.0, "inflammable", MENACES, intensite, etats)

	v.v(diag_vif.statut == "intact" and diag_melange.statut == "intact",
		"bois_vif et melange, au-dessus du seuil reel, doivent tous deux demarrer 'intact' (aucune exposition encore)")
	v.v(diag_fer.statut == "bloque_seuil", "fer_inerte (materiau reel fer, inflammabilite ~0.02) doit etre 'bloque_seuil' contre le seuil reel (0.1)")
	v.v(diag_mouille.statut == "bloque_etat" and diag_mouille.raison_etat == "mouille",
		"bois_mouille (composition identique a bois_vif) doit etre 'bloque_etat' via l'etat reel 'mouille', jamais 'bloque_seuil'")
	v.v(is_equal_approx(diag_vif.effective, 0.9), "bois_vif doit avoir une inflammabilite effective de 0.9 (bois pur, catalogue reel)")
	v.v(is_equal_approx(diag_mouille.effective, 0.0), "bois_mouille doit avoir une inflammabilite effective de 0.0 (ecrasee par 'mouille' reel)")

func _donnees_reelles_bois_vif_s_enflamme_plus_vite_que_melange(v) -> void:
	var donnees := _charger_json("res://data/banc_inflammabilite.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var intensite := _charger_json("res://data/intensite_propagation.json")
	var etats := _charger_json("res://data/etats.json")
	var delai_base: float = donnees.delai_propagation_base

	var catalogue_types: Dictionary = {}
	for decl in donnees.objets:
		catalogue_types[decl.id] = {
			"inflammable": true, "portee_propagation": donnees.portee_propagation,
			"delai_propagation": delai_base, "composition": decl.composition,
		}

	var bois_vif := Objet.fabriquer("bois_vif", "bois_vif", Vector3.ZERO, catalogue_types, materiaux, proprietes_immuables)
	bois_vif.proprietes["etats_actifs"] = []
	var melange := Objet.fabriquer("melange", "melange", Vector3.ZERO, catalogue_types, materiaux, proprietes_immuables)
	melange.proprietes["etats_actifs"] = []

	var delai_vif: float = Propagation.delai_ignition(bois_vif, intensite, etats)
	var delai_melange: float = Propagation.delai_ignition(melange, intensite, etats)
	v.v(delai_vif > 0.0 and delai_melange > 0.0, "les deux delais reels doivent etre finis (au-dessus du seuil)")
	v.v(delai_vif < delai_melange,
		"bois_vif (inflammabilite reelle plus haute) doit exiger un delai STRICTEMENT plus court que melange -- l'ecart que le banc doit rendre visible")

# CHEMIN REEL, BOUCLE REELLE (correction post-audit) : avance
# Propagation.avancer() tick par tick, exactement comme _process(), jusqu'a
# un allumage reel de bois_vif -- capture le temps ecoule EXACTEMENT comme
# banc_inflammabilite.gd:_process le fait (exposition juste avant l'appel +
# delta, jamais devine), puis relit diagnostiquer() ET _texte_label() APRES
# l'ignition. Verifier le seul statut ne suffisait pas (voir l'audit en
# lecture seule qui a motive cette correction) : ce test verifie ce qui
# s'AFFICHE.
func _chemin_reel_bois_vif_s_enflamme_et_le_label_dit_la_verite(v) -> void:
	var donnees := _charger_json("res://data/banc_inflammabilite.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var intensite := _charger_json("res://data/intensite_propagation.json")
	var etats := _charger_json("res://data/etats.json")
	var menaces := _charger_json("res://data/menaces.json")
	var delai_base: float = donnees.delai_propagation_base

	var catalogue_types: Dictionary = {}
	for decl in donnees.objets:
		catalogue_types[decl.id] = {
			"inflammable": true, "portee_propagation": donnees.portee_propagation,
			"delai_propagation": delai_base, "composition": decl.composition,
		}

	var bois_vif := Objet.fabriquer("bois_vif", "bois_vif", Vector3(50, 0, 0), catalogue_types, materiaux, proprietes_immuables)
	bois_vif.proprietes["etats_actifs"] = []
	var feu := {"id": "feu_central", "position": Vector3(0, 0, 0), "proprietes": {"brule": true}}
	var monde := [feu, bois_vif]
	var exposition := {}

	var pas := 0.1
	var temps_mis := -1.0
	for i in 200:
		var avant: float = exposition.get("bois_vif", 0.0)
		var enflammees: Array = Propagation.avancer(monde, menaces, exposition, pas, {}, intensite, etats)
		if enflammees.has("bois_vif"):
			temps_mis = avant + pas
			break
	v.v(temps_mis > 0.0, "bois_vif doit s'enflammer reellement dans la fenetre du test (200 pas de 0.1s)")
	v.v(is_equal_approx(exposition.get("bois_vif", -1.0), 0.0),
		"apres l'ignition, l'exposition VIVE doit bien etre retombee a 0.0 (propagation.gd, comportement voulu, non touche par cette correction)")

	var diag := BancInflammabilite.diagnostiquer(bois_vif, exposition.get("bois_vif", 0.0), "inflammable", menaces, intensite, etats)
	v.v(diag.statut == "en_feu", "une fois 'brule' pose par propagation.gd, diagnostiquer() doit rendre 'en_feu'")
	v.v(diag.delai_requis > 0.0,
		"une fois en feu, delai_requis ne doit JAMAIS valoir -1.0 -- Propagation.delai_ignition doit etre appelee meme sur cette branche")
	v.v(is_equal_approx(diag.delai_requis, delai_base / diag.effective),
		"delai_requis pour un objet en feu doit rester EXACTEMENT delai_propagation / inflammabilite_effective, jamais invente ni recalcule autrement")

	var texte := BancInflammabilite._texte_label("bois_vif", "3.0 bois", diag, exposition.get("bois_vif", 0.0), intensite.seuil_ignition, temps_mis)
	v.v(texte.find("jamais") == -1,
		"le label reel d'un objet EN FEU ne doit plus jamais afficher 'jamais' comme delai_requis")
	v.v(texte.find("0.00s") == -1,
		"le label reel d'un objet EN FEU ne doit plus jamais afficher un temps a 0.00s")
	v.v(texte.find("%.2f" % diag.delai_requis) != -1, "le label reel doit porter le VRAI delai requis chiffre")
	v.v(texte.find("%.2f" % temps_mis) != -1, "le label reel doit porter le temps reellement mis, capture avant la remise a zero")

# Audit couverture 2026-08-06 : _diagnostiquer_tout (fonction INSTANCE,
# jamais appelee par un test avant cette session) est EXACTEMENT le
# niveau ou le defaut original a ete trouve (_texte_label affichait "EN
# FEU" et "delai=jamais" en meme temps) -- ce n'est pas diagnostiquer()
# seule qui composait mal, c'est l'aggregation par objet. Deux objets
# REELS (chemin identique a _chemin_reel_bois_vif_s_enflamme_et_le_label_
# dit_la_verite) : bois_vif s'enflamme reellement, fer_inerte reste
# bloque_seuil pour toujours -- verrouille que chaque noeud/label/barre
# reflete SON PROPRE statut, jamais celui de l'autre objet.
func _diagnostiquer_tout_ne_confond_jamais_deux_objets(v) -> void:
	var donnees := _charger_json("res://data/banc_inflammabilite.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var intensite := _charger_json("res://data/intensite_propagation.json")
	var etats := _charger_json("res://data/etats.json")
	var menaces := _charger_json("res://data/menaces.json")
	var delai_base: float = donnees.delai_propagation_base

	var catalogue_types: Dictionary = {}
	for decl in donnees.objets:
		catalogue_types[decl.id] = {
			"inflammable": true, "portee_propagation": donnees.portee_propagation,
			"delai_propagation": delai_base, "composition": decl.composition,
		}

	var bois_vif := Objet.fabriquer("bois_vif", "bois_vif", Vector3(50, 0, 0), catalogue_types, materiaux, proprietes_immuables)
	bois_vif.proprietes["etats_actifs"] = []
	var fer_inerte := Objet.fabriquer("fer_inerte", "fer_inerte", Vector3(50, 0, 0), catalogue_types, materiaux, proprietes_immuables)
	fer_inerte.proprietes["etats_actifs"] = []
	var feu := {"id": "feu_central", "position": Vector3(0, 0, 0), "proprietes": {"brule": true}}
	var monde := [feu, bois_vif, fer_inerte]
	var exposition := {}

	for i in 200:
		if Propagation.avancer(monde, menaces, exposition, 0.1, {}, intensite, etats).has("bois_vif"):
			break
	v.v(bois_vif.proprietes.get("brule", false), "verrou intermediaire : bois_vif doit s'etre reellement enflamme")
	v.v(not fer_inerte.proprietes.get("brule", false), "verrou intermediaire : fer_inerte ne doit jamais s'enflammer (bloque_seuil)")

	var b := BancInflammabilite.new()
	b._objets = [bois_vif, fer_inerte]
	b._exposition = exposition
	b._menaces = menaces
	b._intensite = intensite
	b._etats = etats
	b._textes_composition = {"bois_vif": "3.0 bois", "fer_inerte": "3.0 fer"}
	for id in ["bois_vif", "fer_inerte"]:
		b._noeuds[id] = ColorRect.new()
		b._labels[id] = Label.new()
		var fond := ColorRect.new()
		fond.size = Vector2(100.0, 4.0)
		b._barres_fond[id] = fond
		b._barres_remplies[id] = ColorRect.new()

	b._diagnostiquer_tout(0.0, true)

	v.v(b._dernier_statut.bois_vif == "en_feu", "bois_vif doit etre diagnostique 'en_feu'")
	v.v(b._dernier_statut.fer_inerte == "bloque_seuil", "fer_inerte doit rester diagnostique 'bloque_seuil'")
	v.v(b._noeuds.bois_vif.color != b._noeuds.fer_inerte.color,
		"deux objets a des statuts differents ne doivent jamais partager la meme teinte")
	v.v(b._labels.bois_vif.text.find("bois_vif") != -1 and b._labels.bois_vif.text.find("fer_inerte") == -1,
		"le label de bois_vif ne doit jamais porter l'id ou le statut de fer_inerte")
	v.v(b._labels.fer_inerte.text.find("fer_inerte") != -1 and b._labels.fer_inerte.text.find("bois_vif") == -1,
		"le label de fer_inerte ne doit jamais porter l'id ou le statut de bois_vif")
	v.v(b._labels.bois_vif.text.find("jamais") == -1,
		"bois_vif est en_feu : son label ne doit plus jamais afficher 'jamais' comme delai")
	v.v(b._labels.fer_inerte.text.find("jamais") != -1,
		"fer_inerte est bloque_seuil : son label doit afficher 'jamais' (ne s'enflammera jamais)")
