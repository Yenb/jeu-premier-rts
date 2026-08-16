extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_emission.gd
#
# Verrouille les fonctions statiques testables de banc_emission.gd
# (diagnostiquer/_teinte_pour_diagnostic/_texte_composition/_texte_statut/
# _texte_label/_evenement/_ligne_log) et, CHEMIN REEL (meme regime que
# test_banc_inflammabilite.gd/test_banc_combustible.gd), la fabrication
# effective des deux feux et quatre cibles depuis data/banc_emission.json +
# data/materiaux.json + data/reserve_combustible_composition.json +
# data/proprietes_immuables_composition.json + data/menaces.json +
# data/intensite_propagation.json + data/emission_propagation.json, lus
# sur disque -- puis UNE BOUCLE REELLE qui avance Propagation.avancer()
# jusqu'a verifier que SEUL grand_feu+bois_grand s'enflamme, jamais les
# trois autres cibles (chantier "emission et seuil").

const BancEmission = preload("res://scripts/banc_emission.gd")
const Objet = preload("res://scripts/objet.gd")
const Propagation = preload("res://scripts/propagation.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_texte_composition_mono_materiau(v)
	_texte_statut_couvre_les_quatre_statuts(v)
	_teinte_bloque_distincte_de_intact(v)
	_texte_label_porte_recu_et_seuil(v)
	_ligne_log_porte_recu_et_seuil(v)
	_donnees_reelles_six_objets(v)
	_chemin_reel_seul_grand_feu_bois_s_enflamme(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_emission.gd -- diagnostic compose Propagation.recu/seuil_exposition sans " +
			"jamais reimplementer leur loi, chemin reel verifie : seul grand_feu+bois_grand " +
			"s'enflamme, a distance egale des trois autres cibles qui ne s'enflamment jamais")
		quit(0)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _texte_composition_mono_materiau(v) -> void:
	var texte := BancEmission._texte_composition([{"materiau": "bois", "volume": 1.0}])
	v.v(texte.find("bois") != -1 and texte.find("1.0") != -1, "la composition doit nommer le materiau et son volume")

func _texte_statut_couvre_les_quatre_statuts(v) -> void:
	v.v(BancEmission._texte_statut({"statut": "intact"}) == "INTACT", "statut intact")
	v.v(BancEmission._texte_statut({"statut": "expose"}) == "EXPOSE", "statut expose")
	v.v(BancEmission._texte_statut({"statut": "en_feu"}) == "EN FEU", "statut en_feu")
	v.v(BancEmission._texte_statut({"statut": "hors_de_portee"}).find("PORTEE") != -1, "statut hors_de_portee doit nommer la portee")

func _teinte_bloque_distincte_de_intact(v) -> void:
	var bloque := BancEmission._teinte_pour_diagnostic({"statut": "hors_de_portee"}, 0.0)
	var intact := BancEmission._teinte_pour_diagnostic({"statut": "intact"}, 0.0)
	v.v(bloque != intact, "la teinte 'hors de portee' doit etre visuellement distincte de 'intact'")

func _texte_label_porte_recu_et_seuil(v) -> void:
	var diag := {"statut": "expose", "effective": 0.9, "delai_requis": 2.22, "recu": 3.2, "seuil": 1.11}
	var texte := BancEmission._texte_label("bois_grand", "8.0 bois", diag, 0.0)
	v.v(texte.find("bois_grand") != -1 and texte.find("3.20") != -1 and texte.find("1.11") != -1,
		"le label doit porter l'id, ce qui est recu et le seuil")

func _ligne_log_porte_recu_et_seuil(v) -> void:
	var diag := {"statut": "hors_de_portee", "effective": 0.9, "delai_requis": 2.22, "recu": 0.4, "seuil": 1.11}
	var ligne := BancEmission._ligne_log(1.0, "bois_petit", diag, 0.0, 0.0)
	v.v(ligne.find("bois_petit") != -1 and ligne.find("0.40") != -1 and ligne.find("1.11") != -1,
		"la ligne de log doit porter l'objet, ce qui est recu et le seuil")

func _donnees_reelles_six_objets(v) -> void:
	var donnees := _charger_json("res://data/banc_emission.json")
	v.v(donnees.feux.size() == 2, "le banc doit declarer exactement deux feux")
	v.v(donnees.cibles.size() == 4, "le banc doit declarer exactement quatre cibles")
	var materiaux := _charger_json("res://data/materiaux.json")
	var reserve_combustible := _charger_json("res://data/reserve_combustible_composition.json")
	var catalogue_feux: Dictionary = {}
	for decl in donnees.feux:
		catalogue_feux[decl.id] = {"composition": decl.composition}
	var petit := Objet.fabriquer("petit_feu", "petit_feu", Vector3.ZERO, catalogue_feux, materiaux, [], reserve_combustible)
	var grand := Objet.fabriquer("grand_feu", "grand_feu", Vector3.ZERO, catalogue_feux, materiaux, [], reserve_combustible)
	v.v(is_equal_approx(grand.proprietes.reserves.combustible.capacite, 8.0 * petit.proprietes.reserves.combustible.capacite),
		"grand_feu (volume 8x) doit avoir une capacite EXACTEMENT 8x celle de petit_feu")

func _chemin_reel_seul_grand_feu_bois_s_enflamme(v) -> void:
	var donnees := _charger_json("res://data/banc_emission.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var reserve_combustible := _charger_json("res://data/reserve_combustible_composition.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var menaces := _charger_json("res://data/menaces.json")
	var intensite := _charger_json("res://data/intensite_propagation.json")
	var emission := _charger_json("res://data/emission_propagation.json")
	var delai_base: float = donnees.get("delai_propagation_base", 1.0)

	var catalogue_feux: Dictionary = {}
	for decl in donnees.feux:
		catalogue_feux[decl.id] = {"composition": decl.composition}
	var catalogue_cibles: Dictionary = {}
	for decl in donnees.cibles:
		catalogue_cibles[decl.id] = {"inflammable": true, "delai_propagation": delai_base, "composition": decl.composition}

	var monde: Array = []
	for decl in donnees.feux:
		var pos: Array = decl.position
		var feu := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue_feux, materiaux, [], reserve_combustible)
		feu.proprietes["brule"] = true
		monde.append(feu)
	for decl in donnees.cibles:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue_cibles, materiaux, proprietes_immuables)
		monde.append(objet)

	var exposition := {}
	var enflammees_vues: Array = []
	for i in 2000:
		var enflammees: Array = Propagation.avancer(monde, menaces, exposition, 0.05, {}, intensite, {}, emission)
		for id in enflammees:
			if not enflammees_vues.has(id):
				enflammees_vues.append(id)

	v.v(enflammees_vues == ["bois_grand"],
		"seul bois_grand doit s'enflammer -- bois_petit (meme matiere, meme distance, feu plus petit) et fer_petit/fer_grand (meme feu, matiere quasi inerte) ne doivent JAMAIS s'enflammer. Enflammees obtenues : %s" % str(enflammees_vues))
