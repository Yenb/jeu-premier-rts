extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_emergences.gd
#
# Verrouille le cablage de banc_emergences.gd -- fabrique trois objets via
# Objet.fabriquer (composition + catalogue_emergences, voir objet.gd:
# _evaluer_emergences), formate leur label/trace console. AUCUN MECANISME DU
# COEUR AU-DELA D'OBJET.GD TOUCHE par ce chantier (objet.gd lui-meme EST
# modifie, voir son propre test scripts/test_emergences.gd) -- ce fichier
# verrouille uniquement le cablage propre a banc_emergences.gd.

const BancEmergences = preload("res://scripts/banc_emergences.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

# Domaine invente, jamais "canalise_mana"/"fer"/"cristal" : verifie que le
# cablage ne connait aucun nom de contenu, seulement les champs de la config.
const MATERIAUX_ZORG := {
	"conducteur_zorg": { "densite": 5.0, "flux_zorg": 900.0 },
	"capteur_zorg": { "densite": 2.0, "sensible_zorg": 0.8 },
}

const CATALOGUE_EMERGENCE_ZORG := [
	{
		"id": "resonne_zorg",
		"conditions": [
			{ "propriete": "flux_zorg", "operateur": ">=", "seuil": 100.0 },
			{ "propriete": "sensible_zorg", "operateur": ">=", "seuil": 0.3 },
		],
		"resultat": { "resonne_zorg": true },
	},
]

const PROPRIETES_IMMUABLES_ZORG := ["flux_zorg", "sensible_zorg"]

const DECLARATIONS_ZORG := [
	{ "id": "combine_zorg", "position": [10.0, 20.0, 0.0], "composition": [ { "materiau": "conducteur_zorg", "volume": 1.0 }, { "materiau": "capteur_zorg", "volume": 1.0 } ] },
	{ "id": "seul_zorg", "position": [50.0, 20.0, 0.0], "composition": [ { "materiau": "conducteur_zorg", "volume": 1.0 } ] },
]

func _init() -> void:
	_fabriquer_objets_resout_id_position_composition()
	_objets_bruts_ne_fusionne_rien()
	_basculer_fabrique_inverse_le_booleen()
	_objet_combine_gagne_lemergence_hors_domaine()
	_objet_seul_ne_gagne_rien_hors_domaine()
	_texte_composition_joint_les_materiaux()
	_emergences_actives_ne_rend_que_celles_vraies_dans_lordre_donne()
	_diagnostic_conditions_hors_domaine()
	_texte_label_avant_et_apres_et_ligne_console_hors_domaine()
	_chemin_reel_fer_cristal_balsa_fer_seul()
	_donnees_reelles()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_emergences -- objets_bruts (AVANT) ne fusionne rien, basculer_fabrique inverse, " +
		"fabriquer_objets fusionne composition+emergences (APRES), un domaine invente traverse le meme code, " +
		"texte_composition/emergences_actives/diagnostic_conditions/texte_label_avant/texte_label_apres/" +
		"ligne_console purs, le chemin reel fer+cristal_demo gagne canalise_mana, balsa_demo seul gagne flotte, " +
		"fer seul ne gagne ni l'un ni l'autre, et data/banc_emergences.json + data/emergences.json chargent correctement")
	quit(0)

func _fabriquer_objets_resout_id_position_composition() -> void:
	var objets := BancEmergences.fabriquer_objets(DECLARATIONS_ZORG, MATERIAUX_ZORG, [], [])
	verif.v(objets.size() == 2, "fabriquer_objets doit produire un objet par declaration")
	verif.v(objets[0].id == "combine_zorg", "l'id declare doit etre conserve")
	verif.v(objets[0].position == Vector3(10.0, 20.0, 0.0), "la position declaree doit etre convertie en Vector3")
	verif.v(objets[0].proprietes.composition.size() == 2, "la composition declaree doit etre conservee telle quelle")

func _objets_bruts_ne_fusionne_rien() -> void:
	var objets := BancEmergences.objets_bruts(DECLARATIONS_ZORG)
	verif.v(objets.size() == 2, "objets_bruts doit produire un objet par declaration, comme fabriquer_objets")
	verif.v(objets[0].id == "combine_zorg", "l'id declare doit etre conserve en etat AVANT")
	verif.v(objets[0].position == Vector3(10.0, 20.0, 0.0), "la position declaree doit etre convertie en Vector3 en etat AVANT")
	verif.v(objets[0].proprietes.composition.size() == 2, "la composition declaree doit etre conservee telle quelle en etat AVANT")
	verif.v(objets[0].proprietes.keys() == ["composition"],
		"en etat AVANT, proprietes ne doit porter QUE 'composition' -- aucune fusion, aucune emergence, jamais Objet.fabriquer")

func _basculer_fabrique_inverse_le_booleen() -> void:
	verif.v(BancEmergences.basculer_fabrique(false) == true, "basculer_fabrique(false) doit rendre true")
	verif.v(BancEmergences.basculer_fabrique(true) == false, "basculer_fabrique(true) doit rendre false")

func _objet_combine_gagne_lemergence_hors_domaine() -> void:
	var objets := BancEmergences.fabriquer_objets(DECLARATIONS_ZORG, MATERIAUX_ZORG, PROPRIETES_IMMUABLES_ZORG, CATALOGUE_EMERGENCE_ZORG)
	var combine: Dictionary = objets[0]
	# moyenne ponderee (volumes egaux, conducteur_zorg+capteur_zorg) :
	# flux_zorg (900+0)/2=450 (>=100) ; sensible_zorg (0+0.8)/2=0.4 (>=0.3)
	# -- les deux passent, ni conducteur_zorg ni capteur_zorg seuls n'y
	# suffiraient (conducteur_zorg n'a jamais sensible_zorg, capteur_zorg
	# n'a jamais flux_zorg).
	verif.v(combine.proprietes.get("resonne_zorg", false) == true,
		"un objet combinant les deux materiaux doit gagner l'emergence -- aucun des deux seuls ne porte les deux proprietes requises")

func _objet_seul_ne_gagne_rien_hors_domaine() -> void:
	var objets := BancEmergences.fabriquer_objets(DECLARATIONS_ZORG, MATERIAUX_ZORG, PROPRIETES_IMMUABLES_ZORG, CATALOGUE_EMERGENCE_ZORG)
	var seul: Dictionary = objets[1]
	verif.v(not seul.proprietes.has("resonne_zorg"),
		"conducteur_zorg seul ne porte jamais sensible_zorg (absent de sa fiche) -- l'emergence ne doit jamais se declencher")

func _texte_composition_joint_les_materiaux() -> void:
	var objet := { "proprietes": { "composition": [ { "materiau": "a" }, { "materiau": "b" } ] } }
	verif.v(BancEmergences.texte_composition(objet) == "a+b", "texte_composition doit joindre les noms de materiaux par '+'")

func _emergences_actives_ne_rend_que_celles_vraies_dans_lordre_donne() -> void:
	var objet := { "proprietes": { "x": true, "z": true } }
	var actives := BancEmergences.emergences_actives(objet, ["x", "y", "z"])
	verif.v(actives == ["x", "z"], "emergences_actives doit rendre uniquement les noms a true, dans l'ordre de la liste fournie")
	verif.v(BancEmergences.emergences_actives({ "proprietes": {} }, ["x"]) == [],
		"aucune emergence active sur un objet vide ne doit rendre un Array vide")

func _diagnostic_conditions_hors_domaine() -> void:
	var objet := { "id": "z1", "proprietes": { "composition": [ { "materiau": "conducteur_zorg" }, { "materiau": "capteur_zorg" } ], "flux_zorg": 450.0, "sensible_zorg": 0.4, "resonne_zorg": true } }
	var diag := BancEmergences.diagnostic_conditions(objet, CATALOGUE_EMERGENCE_ZORG)
	verif.v(diag.size() == 1, "diagnostic_conditions doit rendre une entree par emergence du catalogue")
	verif.v(diag[0].id == "resonne_zorg", "l'id de l'emergence doit etre conserve")
	verif.v(diag[0].acquise == true, "'acquise' doit venir de proprietes.get(id, false) -- la VERITE deja posee par objet.gd, jamais recalculee")
	verif.v(diag[0].conditions.size() == 2, "diagnostic_conditions doit detailler chaque condition de l'entree")
	verif.v(diag[0].conditions[0].ok == true and diag[0].conditions[1].ok == true,
		"les deux conditions (flux_zorg>=100 et sensible_zorg>=0.3) doivent etre marquees OK, coherentes avec 'acquise'")

	var objet_rate := { "id": "z2", "proprietes": { "flux_zorg": 900.0, "sensible_zorg": 0.1 } }
	var diag2 := BancEmergences.diagnostic_conditions(objet_rate, CATALOGUE_EMERGENCE_ZORG)
	verif.v(diag2[0].acquise == false, "sans la cle 'resonne_zorg' sur proprietes, 'acquise' doit rester false")
	verif.v(diag2[0].conditions[0].ok == true and diag2[0].conditions[1].ok == false,
		"une seule condition vraie sur deux doit etre reportee EXACTEMENT (flux_zorg OK, sensible_zorg RATE)")

func _texte_label_avant_et_apres_et_ligne_console_hors_domaine() -> void:
	var objet_avant := { "id": "z1", "proprietes": { "composition": [ { "materiau": "conducteur_zorg" } ] } }
	var label_avant := BancEmergences.texte_label_avant(objet_avant)
	verif.v(label_avant.find("z1") != -1, "le label AVANT doit porter l'id de l'objet")
	verif.v(label_avant.find("composition=conducteur_zorg") != -1, "le label AVANT doit porter la composition")
	verif.v(label_avant.find("clic pour fabriquer") != -1, "le label AVANT doit inviter au clic")
	verif.v(label_avant.find("flux_zorg") == -1, "le label AVANT ne doit jamais afficher une propriete fusionnee -- rien n'est encore fabrique")

	var objet_apres := { "id": "z1", "proprietes": { "composition": [ { "materiau": "conducteur_zorg" } ], "flux_zorg": 900.0, "sensible_zorg": 0.1, "resonne_zorg": false } }
	var label_apres := BancEmergences.texte_label_apres(objet_apres, ["flux_zorg"], CATALOGUE_EMERGENCE_ZORG)
	verif.v(label_apres.find("z1") != -1, "le label APRES doit porter l'id de l'objet")
	verif.v(label_apres.find("flux_zorg=900") != -1, "le label APRES doit porter la propriete demandee et sa valeur")
	verif.v(label_apres.find("resonne_zorg") != -1, "le label APRES doit porter le nom de l'emergence diagnostiquee")
	verif.v(label_apres.find("non") != -1, "le label APRES d'une emergence non acquise doit l'indiquer")

	var objet_console := { "id": "z1", "proprietes": { "composition": [ { "materiau": "conducteur_zorg" } ], "resonne_zorg": true } }
	var ligne := BancEmergences.ligne_console(objet_console, ["resonne_zorg"])
	verif.v(ligne == "z1 : fabrique -- composition=conducteur_zorg emergences=resonne_zorg",
		"ligne_console doit formater id/composition/emergences exactement")

	var objet_sans_emergence := { "id": "z2", "proprietes": { "composition": [ { "materiau": "capteur_zorg" } ] } }
	var ligne2 := BancEmergences.ligne_console(objet_sans_emergence, ["resonne_zorg"])
	verif.v(ligne2 == "z2 : fabrique -- composition=capteur_zorg emergences=aucune",
		"ligne_console sans emergence active doit afficher 'aucune'")

func _chemin_reel_fer_cristal_balsa_fer_seul() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_emergences.json"))
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", []) + ["sensibilite_magique"]
	var catalogue_emergences: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/emergences.json")).get("emergences", [])

	var objets := BancEmergences.fabriquer_objets(donnees.objets, materiaux, proprietes_immuables, catalogue_emergences)
	var par_id: Dictionary = {}
	for objet in objets:
		par_id[objet.id] = objet

	verif.v(par_id.has("fer_cristal") and par_id.has("balsa") and par_id.has("fer_seul"),
		"data/banc_emergences.json doit declarer les trois objets du chantier")

	var fer_cristal: Dictionary = par_id.fer_cristal
	verif.v(fer_cristal.proprietes.get("canalise_mana", false) == true,
		"fer+cristal_demo (volumes egaux) doit gagner 'canalise_mana' -- conductivite_electrique et sensibilite_magique combinees depassent les deux seuils")
	verif.v(not fer_cristal.proprietes.has("flotte"), "fer+cristal_demo est dense (moyenne ponderee bien au-dessus de 500 kg/m3) -- ne doit jamais flotter")

	var balsa: Dictionary = par_id.balsa
	verif.v(balsa.proprietes.get("flotte", false) == true,
		"balsa_demo seul (densite 200 kg/m3, resistance_impact 3.0) doit gagner 'flotte'")
	verif.v(not balsa.proprietes.has("canalise_mana"), "balsa_demo n'a aucune conductivite_electrique -- ne doit jamais canaliser le mana")

	var fer_seul: Dictionary = par_id.fer_seul
	verif.v(not fer_seul.proprietes.has("canalise_mana"),
		"fer seul remplit conductivite_electrique>=1e5 MAIS rate sensibilite_magique>=0.3 (0.2) -- ET logique, aucune emergence")
	verif.v(not fer_seul.proprietes.has("flotte"), "fer seul est bien trop dense (7870 kg/m3) pour flotter")

func _donnees_reelles() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_emergences.json"))
	verif.v(donnees.objets.size() == 3, "data/banc_emergences.json doit declarer trois objets")
	var ids: Array = []
	for objet in donnees.objets:
		ids.append(objet.id)
	verif.v(ids.has("fer_cristal") and ids.has("balsa") and ids.has("fer_seul"),
		"data/banc_emergences.json doit porter les trois id du chantier")

	var emergences: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/emergences.json"))
	verif.v(emergences.emergences.size() == 3, "data/emergences.json doit porter trois entrees (canalise_mana/flotte/incandescent)")
	var noms: Array = []
	for entree in emergences.emergences:
		noms.append(entree.id)
	verif.v(noms.has("canalise_mana") and noms.has("flotte") and noms.has("incandescent"),
		"data/emergences.json doit couvrir les trois emergences du chantier")

	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	verif.v(materiaux.has("cristal_demo") and materiaux.has("balsa_demo"),
		"data/materiaux.json doit porter cristal_demo et balsa_demo")
	verif.v(is_equal_approx(materiaux.cristal_demo.sensibilite_magique, 0.5), "cristal_demo doit porter sensibilite_magique 0.5")
	verif.v(is_equal_approx(materiaux.balsa_demo.densite, 0.2) and is_equal_approx(materiaux.balsa_demo.resistance_impact, 3.0),
		"balsa_demo doit porter densite 0.2 et resistance_impact 3.0")
