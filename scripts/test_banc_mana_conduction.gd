extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_mana_conduction.gd
#
# Verrouille le cablage de banc_mana_conduction.gd -- chantier « conductivite_
# electrique pour la magie -- canalisation de mana » :
# 1. conducteurs_actifs/propager_mana (fonctions pures de ce banc, PAS
#    flux.gd, RECOPIEES depuis banc_conduction.gd -- aucun appel croise)
#    determinent qui conduit (seuil sur la conductivite EFFECTIVE,
#    EtatEffectif.valeur) et qui est sous_mana (parcours en largeur depuis
#    les sources actives, bloque net a tout objet non conducteur) ;
# 2. flux.gd (INCHANGE) accumule la reserve "mana" de chaque objet canalise,
#    un appel PAR OBJET avec un emetteur synthetique dont le taux_flux est
#    proportionnel a SA conductivite effective.
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : flux.gd/etat_effectif.gd/
# objet.gd restent exactement ceux deja verrouilles par leurs propres tests,
# banc_conduction.gd/scripts/test_banc_conduction.gd restent inchanges -- ce
# fichier verrouille uniquement banc_mana_conduction.gd.

const BancManaConduction = preload("res://scripts/banc_mana_conduction.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const CONFIG := {
	"propriete_cause": "source_active",
	"propriete_sous_mana": "sous_mana",
	"propriete_conducteur": "conducteur_mana_actif",
	"nom_reserve_mana": "mana",
	"seuil_conduction_mana": 10.0,
	"portee_contact": 90.0,
	"facteur_conductivite_base": 0.000001,
}

const ETATS := {}

const CONDUCTIVITE_FER := 1.0e7
const CONDUCTIVITE_BOIS := 1.0e-15

func _init() -> void:
	_fer_conduit()
	_bois_isole()
	_conductivite_nulle_ne_conduit_jamais()
	_seuil_mana_different_du_seuil_electrique()
	_propager_mana_bloque_net_a_un_isolant()
	_propager_mana_traverse_une_chaine_de_conducteurs()
	_sans_source_active_rien_ne_bouge()
	_mana_ne_traverse_pas_le_bois()
	_mana_traverse_si_tout_est_fer()
	_mana_monte_puis_descend_au_basculement_de_la_source()
	_basculer_sources()
	_fabrication_reelle_fusionne_conductivite_electrique_depuis_materiaux_json()
	_donnees_reelles_banc_mana_conduction_json()
	_chemin_reel_banc_mana_conduction_json_bloque_et_traverse()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: le fer conduit le mana, le bois isole, une conductivite nulle ne conduit jamais, le " +
		"seuil de conduction du mana est distinct du seuil electrique, propager_mana bloque net a un " +
		"isolant et traverse une chaine de conducteurs, sans source active rien ne bouge, le mana ne " +
		"traverse pas le bois mais traverse une chaine de fer, le mana monte quand la source est " +
		"active et redescend quand elle est coupee, basculer_sources est pur, la fabrication reelle " +
		"fusionne conductivite_electrique depuis materiaux.json, et data/banc_mana_conduction.json " +
		"charge et se comporte comme attendu chemin reel")
	quit(0)

# ---- Fixtures ----

func _objet(id: String, position: Vector3, conductivite: float) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"conductivite_electrique": conductivite,
			"reserves": { "mana": { "reserve": 0.0 } },
		},
	}

func _source(id: String, position: Vector3, active: bool) -> Dictionary:
	return { "id": id, "position": position, "proprietes": { "source_active": active } }

# ---- conducteurs_actifs / EtatEffectif ----

func _fer_conduit() -> void:
	var actifs := BancManaConduction.conducteurs_actifs([_objet("fer", Vector3.ZERO, CONDUCTIVITE_FER)], ETATS, CONFIG.seuil_conduction_mana)
	verif.v(actifs["fer"], "un objet a conductivite 1e7 (fer) doit canaliser le mana")

func _bois_isole() -> void:
	var actifs := BancManaConduction.conducteurs_actifs([_objet("bois", Vector3.ZERO, CONDUCTIVITE_BOIS)], ETATS, CONFIG.seuil_conduction_mana)
	verif.v(not actifs["bois"], "un objet a conductivite 1e-15 (bois) ne doit jamais canaliser le mana")

func _conductivite_nulle_ne_conduit_jamais() -> void:
	var actifs := BancManaConduction.conducteurs_actifs([_objet("verre", Vector3.ZERO, 0.0)], ETATS, CONFIG.seuil_conduction_mana)
	verif.v(not actifs["verre"], "conductivite_electrique exactement 0.0 ne doit jamais canaliser le mana")

func _seuil_mana_different_du_seuil_electrique() -> void:
	# Le seuil de conduction du mana (10.0) est distinct du seuil electrique
	# de banc_conduction.gd (1.0) -- une conductivite entre les deux doit
	# conduire l'electricite mais pas le mana, preuve que les deux seuils
	# sont bien independants (donnee locale a CHAQUE banc, jamais partagee).
	var entre_deux := 5.0
	var actifs_mana := BancManaConduction.conducteurs_actifs([_objet("intermediaire", Vector3.ZERO, entre_deux)], ETATS, CONFIG.seuil_conduction_mana)
	verif.v(not actifs_mana["intermediaire"], "une conductivite de 5.0 doit rester sous le seuil de conduction du mana (10.0)")
	verif.v(entre_deux > 1.0, "verrou de coherence : 5.0 doit rester au-dessus du seuil electrique de banc_conduction.gd (1.0), la meme conductivite conduirait donc l'electricite sans conduire le mana")

# ---- propager_mana (parcours en largeur) ----

func _propager_mana_bloque_net_a_un_isolant() -> void:
	var fer1 := _objet("fer1", Vector3(90, 0, 0), CONDUCTIVITE_FER)
	var bois := _objet("bois", Vector3(180, 0, 0), CONDUCTIVITE_BOIS)
	var fer2 := _objet("fer2", Vector3(270, 0, 0), CONDUCTIVITE_FER)
	var objets := [fer1, bois, fer2]
	var conducteurs := BancManaConduction.conducteurs_actifs(objets, ETATS, CONFIG.seuil_conduction_mana)
	var source := _source("s", Vector3(0, 0, 0), true)
	var canalises := BancManaConduction.propager_mana([source], objets, conducteurs, CONFIG.portee_contact, CONFIG.propriete_cause)
	verif.v(canalises.has("fer1"), "le premier fer, en contact de la source active, doit se canaliser")
	verif.v(not canalises.has("bois"), "le bois, isolant, ne doit jamais se canaliser")
	verif.v(not canalises.has("fer2"), "le second fer, derriere le bois, ne doit jamais se canaliser -- le mana est bloque")

func _propager_mana_traverse_une_chaine_de_conducteurs() -> void:
	var fer1 := _objet("fer1", Vector3(90, 0, 0), CONDUCTIVITE_FER)
	var fer2 := _objet("fer2", Vector3(180, 0, 0), CONDUCTIVITE_FER)
	var fer3 := _objet("fer3", Vector3(270, 0, 0), CONDUCTIVITE_FER)
	var objets := [fer1, fer2, fer3]
	var conducteurs := BancManaConduction.conducteurs_actifs(objets, ETATS, CONFIG.seuil_conduction_mana)
	var source := _source("s", Vector3(0, 0, 0), true)
	var canalises := BancManaConduction.propager_mana([source], objets, conducteurs, CONFIG.portee_contact, CONFIG.propriete_cause)
	verif.v(canalises.has("fer1") and canalises.has("fer2") and canalises.has("fer3"), "une chaine de trois conducteurs en contact doit se canaliser entierement")

func _sans_source_active_rien_ne_bouge() -> void:
	var fer1 := _objet("fer1", Vector3(90, 0, 0), CONDUCTIVITE_FER)
	var objets := [fer1]
	var conducteurs := BancManaConduction.conducteurs_actifs(objets, ETATS, CONFIG.seuil_conduction_mana)
	var source := _source("s", Vector3(0, 0, 0), false)
	var canalises := BancManaConduction.propager_mana([source], objets, conducteurs, CONFIG.portee_contact, CONFIG.propriete_cause)
	verif.v(canalises.is_empty(), "source inactive : aucun objet ne doit jamais se canaliser, meme un conducteur en contact")

# ---- avancer() : flux.gd cable, la reserve "mana" grandit ----

func _mana_ne_traverse_pas_le_bois() -> void:
	var fer1 := _objet("fer1", Vector3(90, 0, 0), CONDUCTIVITE_FER)
	var bois := _objet("bois", Vector3(180, 0, 0), CONDUCTIVITE_BOIS)
	var fer2 := _objet("fer2", Vector3(270, 0, 0), CONDUCTIVITE_FER)
	var objets := [fer1, bois, fer2]
	var source := _source("s", Vector3(0, 0, 0), true)
	for i in 10:
		BancManaConduction.avancer([source], objets, 0.1, CONFIG, ETATS)
	verif.v(fer1.proprietes.reserves.mana.reserve > 0.0, "le premier fer doit accumuler du mana")
	verif.v(bois.proprietes.reserves.mana.reserve == 0.0, "le bois ne doit jamais accumuler de mana")
	verif.v(fer2.proprietes.reserves.mana.reserve == 0.0, "le second fer, derriere le bois, ne doit jamais accumuler de mana -- hors canalisation")
	verif.v(not fer2.proprietes.sous_mana, "le second fer doit rester marque hors canalisation")

func _mana_traverse_si_tout_est_fer() -> void:
	var fer1 := _objet("fer1", Vector3(90, 0, 0), CONDUCTIVITE_FER)
	var fer2 := _objet("fer2", Vector3(180, 0, 0), CONDUCTIVITE_FER)
	var fer3 := _objet("fer3", Vector3(270, 0, 0), CONDUCTIVITE_FER)
	var objets := [fer1, fer2, fer3]
	var source := _source("s", Vector3(0, 0, 0), true)
	for i in 10:
		BancManaConduction.avancer([source], objets, 0.1, CONFIG, ETATS)
	verif.v(fer1.proprietes.reserves.mana.reserve > 0.0, "fer1 doit accumuler du mana")
	verif.v(fer2.proprietes.reserves.mana.reserve > 0.0, "fer2 doit accumuler du mana -- meme materiau que fer1, la chaine traverse")
	verif.v(fer3.proprietes.reserves.mana.reserve > 0.0, "fer3 doit accumuler du mana -- remplacer le bois par du fer fait traverser les trois")

func _mana_monte_puis_descend_au_basculement_de_la_source() -> void:
	var fer := _objet("fer", Vector3(90, 0, 0), CONDUCTIVITE_FER)
	var objets := [fer]
	var source := _source("s", Vector3(0, 0, 0), true)
	var sources := [source]

	for i in 10:
		BancManaConduction.avancer(sources, objets, 0.1, CONFIG, ETATS)
	var apres_montee: float = fer.proprietes.reserves.mana.reserve
	verif.v(apres_montee > 0.0, "source active, le fer doit accumuler du mana")

	BancManaConduction.basculer_sources(sources, CONFIG.propriete_cause)
	for i in 5:
		BancManaConduction.avancer(sources, objets, 0.1, CONFIG, ETATS)
	var apres_coupure: float = fer.proprietes.reserves.mana.reserve
	verif.v(apres_coupure < apres_montee, "source coupee, la reserve de mana doit decroitre")
	verif.v(not fer.proprietes.sous_mana, "source coupee, le fer ne doit plus etre marque sous_mana")

	BancManaConduction.basculer_sources(sources, CONFIG.propriete_cause)
	for i in 10:
		BancManaConduction.avancer(sources, objets, 0.1, CONFIG, ETATS)
	var apres_relance: float = fer.proprietes.reserves.mana.reserve
	verif.v(apres_relance > apres_coupure, "source reactivee, la reserve de mana doit remonter")

# ---- Fonctions pures isolees ----

func _basculer_sources() -> void:
	var sources := [_source("a", Vector3.ZERO, false), _source("b", Vector3(10, 0, 0), false)]
	BancManaConduction.basculer_sources(sources, "source_active")
	verif.v(sources[0].proprietes.source_active and sources[1].proprietes.source_active, "basculer_sources doit activer toutes les sources a la fois quand aucune n'est active")
	BancManaConduction.basculer_sources(sources, "source_active")
	verif.v(not sources[0].proprietes.source_active and not sources[1].proprietes.source_active, "basculer_sources doit desactiver toutes les sources a la fois")

# ---- Chemin REEL : materiaux.json/proprietes_immuables_composition.json ----

func _fabrication_reelle_fusionne_conductivite_electrique_depuis_materiaux_json() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(proprietes_immuables.has("conductivite_electrique"), "data/proprietes_immuables_composition.json doit lister conductivite_electrique")

	var declarations := [
		{"id": "fer_reel", "position": [0.0, 0.0, 0.0], "composition": [ {"materiau": "fer", "volume": 1.0} ]},
		{"id": "bois_reel", "position": [10.0, 0.0, 0.0], "composition": [ {"materiau": "bois", "volume": 1.0} ]},
	]
	var objets := BancManaConduction.fabriquer_objets(declarations, materiaux, proprietes_immuables)
	var fer: Dictionary = objets[0]
	var bois: Dictionary = objets[1]
	verif.v(abs(fer.proprietes.conductivite_electrique - 1.0e7) / 1.0e7 < 0.0001, "fer reel doit fusionner conductivite_electrique=1e7 depuis materiaux.json")
	verif.v(abs(bois.proprietes.conductivite_electrique - 1.0e-15) < 1.0e-14, "bois reel doit fusionner conductivite_electrique=1e-15 depuis materiaux.json")
	verif.v(fer.proprietes.has("reserves") and fer.proprietes.reserves.has("mana"), "fabriquer_objets doit initialiser une reserve 'mana' a 0.0")
	verif.v(fer.proprietes.reserves.mana.reserve == 0.0, "la reserve 'mana' initiale doit valoir 0.0")

	var etats_reels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	var actifs := BancManaConduction.conducteurs_actifs(objets, etats_reels, CONFIG.seuil_conduction_mana)
	verif.v(actifs["fer_reel"], "chemin reel : le fer fabrique par composition doit canaliser le mana")
	verif.v(not actifs["bois_reel"], "chemin reel : le bois fabrique par composition ne doit jamais canaliser le mana")

# ---- Chemin REEL : data/banc_mana_conduction.json ----

func _donnees_reelles_banc_mana_conduction_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_mana_conduction.json"))
	verif.v(donnees.propriete_cause == "source_active", "data/banc_mana_conduction.json doit declarer propriete_cause")
	verif.v(donnees.seuil_conduction_mana == 10.0, "data/banc_mana_conduction.json doit declarer seuil_conduction_mana=10.0")
	verif.v(donnees.sources.size() == 2, "data/banc_mana_conduction.json doit declarer deux sources")
	verif.v(donnees.objets.size() == 6, "data/banc_mana_conduction.json doit declarer six objets")

	var par_id: Dictionary = {}
	for objet in donnees.objets:
		par_id[objet.id] = objet
	verif.v(par_id.has("fer_bloque_1") and par_id.has("bois_bloque") and par_id.has("fer_bloque_2"), "data/banc_mana_conduction.json doit porter la rangee fer-bois-fer")
	verif.v(par_id.has("fer_traverse_1") and par_id.has("fer_traverse_2") and par_id.has("fer_traverse_3"), "data/banc_mana_conduction.json doit porter la rangee fer-fer-fer")

# Chemin REEL complet : data/banc_mana_conduction.json + data/materiaux.json +
# data/etats.json + data/proprietes_immuables_composition.json lus sur
# disque, comme banc_mana_conduction.gd les charge lui-meme a _ready() --
# exerce exactement la scene decrite par le chantier (fer-bois-fer bloque,
# fer-fer-fer traverse).
func _chemin_reel_banc_mana_conduction_json_bloque_et_traverse() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_mana_conduction.json"))
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])

	var sources := BancManaConduction.fabriquer_sources(donnees.sources)
	var objets := BancManaConduction.fabriquer_objets(donnees.objets, materiaux, proprietes_immuables)
	BancManaConduction.basculer_sources(sources, donnees.propriete_cause)

	var par_id: Dictionary = {}
	for i in 10:
		BancManaConduction.avancer(sources, objets, 0.1, donnees, etats)
	for objet in objets:
		par_id[objet.id] = objet

	verif.v(par_id.fer_bloque_1.proprietes.reserves.mana.reserve > 0.0, "chemin reel : fer_bloque_1 doit canaliser (en contact direct d'une source active)")
	verif.v(par_id.bois_bloque.proprietes.reserves.mana.reserve == 0.0, "chemin reel : bois_bloque ne doit jamais canaliser")
	verif.v(par_id.fer_bloque_2.proprietes.reserves.mana.reserve == 0.0, "chemin reel : fer_bloque_2, derriere le bois, doit rester hors canalisation")

	verif.v(par_id.fer_traverse_1.proprietes.reserves.mana.reserve > 0.0, "chemin reel : fer_traverse_1 doit canaliser")
	verif.v(par_id.fer_traverse_2.proprietes.reserves.mana.reserve > 0.0, "chemin reel : fer_traverse_2 doit canaliser -- la chaine tout-fer traverse")
	verif.v(par_id.fer_traverse_3.proprietes.reserves.mana.reserve > 0.0, "chemin reel : fer_traverse_3 doit canaliser -- remplacer le bois par du fer fait traverser les trois")

	# Couper les sources doit arreter la canalisation -- la reserve cesse de
	# monter et decroit vers zero.
	var avant_coupure: float = par_id.fer_traverse_1.proprietes.reserves.mana.reserve
	BancManaConduction.basculer_sources(sources, donnees.propriete_cause)
	for i in 5:
		BancManaConduction.avancer(sources, objets, 0.1, donnees, etats)
	verif.v(par_id.fer_traverse_1.proprietes.reserves.mana.reserve < avant_coupure, "chemin reel : sources coupees, la reserve de mana doit decroitre")
