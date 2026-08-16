extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_conduction.gd
#
# Verrouille le cablage de banc_conduction.gd -- chantier « conduction
# electrique -- courant continu » :
# 1. conducteurs_actifs/propager_tension (fonctions pures de ce banc,
#    PAS flux.gd) determinent qui conduit (seuil sur la conductivite
#    EFFECTIVE, EtatEffectif.valeur, mouille compris) et qui est sous
#    tension (parcours en largeur depuis les generateurs actifs, bloque
#    net a tout objet non conducteur) ;
# 2. flux.gd (INCHANGE) accumule la reserve "courant" de chaque objet
#    energise, un appel PAR OBJET avec un emetteur synthetique dont le
#    taux_flux est proportionnel a SA conductivite effective ;
# 3. charge.gd -> etat_duree.gd -> depense.gd (INCHANGES, patron deja
#    ferme trois fois par pourriture/corrosion/solubilite) appliquent des
#    degats continus a un agent expose a un objet sous tension.
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : flux.gd/charge.gd/
# etat_effectif.gd/etat_duree.gd/depense.gd/objet.gd restent exactement
# ceux deja verrouilles par leurs propres tests -- ce fichier verrouille
# uniquement banc_conduction.gd.

const BancConduction = preload("res://scripts/banc_conduction.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

# Sous-ensemble local de data/etats.json, suffisant pour les tests
# d'isolation (hors chemin reel) -- mouille module conductivite_electrique
# x10.0, electrocute est un marqueur pur (duree, aucun effet).
const ETATS := {
	"mouille": {
		"duree": 6.0,
		"effets": [
			{ "propriete": "conductivite_electrique", "mode": "moduler", "facteur": 10.0 },
		],
	},
	"electrocute": {
		"duree": 1.5,
		"effets": [],
	},
}

const CONFIG := {
	"propriete_cause": "generateur",
	"propriete_sous_tension": "sous_tension",
	"propriete_conducteur": "conducteur_actif",
	"nom_reserve_courant": "courant",
	"seuil_conduction": 1.0,
	"portee_contact": 90.0,
	"facteur_conductivite_base": 0.000001,
	"nom_canal_electrocution": "electrocution",
	"canal_electrocution_defaut": {
		"charge": 0.0, "seuil": 2.0, "portee_charge": 90.0,
		"taux_decroissance": 1.0, "poser": { "expose_electrocution": true },
	},
	"declencheur_expose_electrocution": "expose_electrocution",
	"nom_etat_electrocute": "electrocute",
	"degat_par_s": 3.0,
	"nom_reserve_integrite": "integrite",
	"reserve_integrite_defaut": { "reserve": 10.0, "cout_base": 0.0, "surcout_action": 0.0 },
}

const CONDUCTIVITE_FER := 1.0e7
const CONDUCTIVITE_BOIS := 1.0e-15

func _init() -> void:
	_fer_conduit()
	_bois_isole()
	_conductivite_nulle_ne_conduit_jamais()
	_mouille_conduit_mieux_que_sec_sur_le_seuil()
	_propager_tension_bloque_net_a_un_isolant()
	_propager_tension_traverse_une_chaine_de_conducteurs()
	_sans_generateur_actif_rien_ne_bouge()
	_courant_ne_traverse_pas_le_bois()
	_courant_traverse_si_tout_est_fer()
	_objet_mouille_accumule_le_courant_plus_vite_qu_un_sec()
	_agent_a_portee_d_un_conducteur_sous_tension_prend_des_degats()
	_agent_hors_portee_aucun_effet()
	_causes_de_tension()
	_basculer_generateurs()
	_fabrication_reelle_fusionne_conductivite_electrique_depuis_materiaux_json()
	_donnees_reelles_banc_conduction_json()
	_chemin_reel_banc_conduction_json_bloque_isole_et_electrocute()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: le fer conduit, le bois isole, une conductivite nulle ne conduit jamais, mouille " +
		"conduit mieux que sec sur le seuil, propager_tension bloque net a un isolant et traverse " +
		"une chaine de conducteurs, sans generateur actif rien ne bouge, le courant ne traverse pas " +
		"le bois mais traverse une chaine de fer, un objet mouille accumule le courant plus vite " +
		"qu'un sec, un agent a portee d'un conducteur sous tension prend des degats continus, hors " +
		"portee aucun effet, causes_de_tension/basculer_generateurs purs, la fabrication reelle " +
		"fusionne conductivite_electrique depuis materiaux.json, et data/banc_conduction.json " +
		"charge et se comporte comme attendu chemin reel")
	quit(0)

# ---- Fixtures ----

func _objet(id: String, position: Vector3, conductivite: float, etats_actifs: Array = []) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"conductivite_electrique": conductivite,
			"etats_actifs": etats_actifs.duplicate(true),
			"reserves": { "courant": { "reserve": 0.0 } },
		},
	}

func _source(id: String, position: Vector3, active: bool) -> Dictionary:
	return { "id": id, "position": position, "proprietes": { "generateur": active } }

func _agent(position: Vector3) -> Dictionary:
	return BancConduction.fabriquer_agent({ "id": "agent_test", "position": [position.x, position.y, position.z] }, CONFIG)

# ---- conducteurs_actifs / EtatEffectif (mouille) ----

func _fer_conduit() -> void:
	var actifs := BancConduction.conducteurs_actifs([_objet("fer", Vector3.ZERO, CONDUCTIVITE_FER)], ETATS, CONFIG.seuil_conduction)
	verif.v(actifs["fer"], "un objet a conductivite 1e7 (fer) doit etre conducteur_actif")

func _bois_isole() -> void:
	var actifs := BancConduction.conducteurs_actifs([_objet("bois", Vector3.ZERO, CONDUCTIVITE_BOIS)], ETATS, CONFIG.seuil_conduction)
	verif.v(not actifs["bois"], "un objet a conductivite 1e-15 (bois) ne doit jamais etre conducteur_actif")

func _conductivite_nulle_ne_conduit_jamais() -> void:
	var actifs := BancConduction.conducteurs_actifs([_objet("verre", Vector3.ZERO, 0.0)], ETATS, CONFIG.seuil_conduction)
	verif.v(not actifs["verre"], "conductivite_electrique exactement 0.0 ne doit jamais conduire")

func _mouille_conduit_mieux_que_sec_sur_le_seuil() -> void:
	# Un materiau juste sous le seuil (isolant sec) doit franchir le seuil une
	# fois mouille (x10.0) -- verrou direct sur la fondation dormante du
	# chantier humidite, ici consommee pour la premiere fois par un mecanisme.
	var proche_du_seuil := CONFIG.seuil_conduction / 5.0
	var sec := _objet("presque_isolant_sec", Vector3.ZERO, proche_du_seuil)
	var mouille := _objet("presque_isolant_mouille", Vector3.ZERO, proche_du_seuil, ["mouille"])
	var actifs := BancConduction.conducteurs_actifs([sec, mouille], ETATS, CONFIG.seuil_conduction)
	verif.v(not actifs["presque_isolant_sec"], "sec, sous le seuil, ne doit pas conduire")
	verif.v(actifs["presque_isolant_mouille"], "mouille (x10.0), au-dessus du seuil, doit conduire")

# ---- propager_tension (parcours en largeur) ----

func _propager_tension_bloque_net_a_un_isolant() -> void:
	var fer1 := _objet("fer1", Vector3(90, 0, 0), CONDUCTIVITE_FER)
	var bois := _objet("bois", Vector3(180, 0, 0), CONDUCTIVITE_BOIS)
	var fer2 := _objet("fer2", Vector3(270, 0, 0), CONDUCTIVITE_FER)
	var objets := [fer1, bois, fer2]
	var conducteurs := BancConduction.conducteurs_actifs(objets, ETATS, CONFIG.seuil_conduction)
	var source := _source("s", Vector3(0, 0, 0), true)
	var energises := BancConduction.propager_tension([source], objets, conducteurs, CONFIG.portee_contact, CONFIG.propriete_cause)
	verif.v(energises.has("fer1"), "le premier fer, en contact du generateur actif, doit s'energiser")
	verif.v(not energises.has("bois"), "le bois, isolant, ne doit jamais s'energiser")
	verif.v(not energises.has("fer2"), "le second fer, derriere le bois, ne doit jamais s'energiser -- le courant est bloque")

func _propager_tension_traverse_une_chaine_de_conducteurs() -> void:
	var fer1 := _objet("fer1", Vector3(90, 0, 0), CONDUCTIVITE_FER)
	var fer2 := _objet("fer2", Vector3(180, 0, 0), CONDUCTIVITE_FER)
	var fer3 := _objet("fer3", Vector3(270, 0, 0), CONDUCTIVITE_FER)
	var objets := [fer1, fer2, fer3]
	var conducteurs := BancConduction.conducteurs_actifs(objets, ETATS, CONFIG.seuil_conduction)
	var source := _source("s", Vector3(0, 0, 0), true)
	var energises := BancConduction.propager_tension([source], objets, conducteurs, CONFIG.portee_contact, CONFIG.propriete_cause)
	verif.v(energises.has("fer1") and energises.has("fer2") and energises.has("fer3"), "une chaine de trois conducteurs en contact doit s'energiser entierement")

func _sans_generateur_actif_rien_ne_bouge() -> void:
	var fer1 := _objet("fer1", Vector3(90, 0, 0), CONDUCTIVITE_FER)
	var objets := [fer1]
	var conducteurs := BancConduction.conducteurs_actifs(objets, ETATS, CONFIG.seuil_conduction)
	var source := _source("s", Vector3(0, 0, 0), false)
	var energises := BancConduction.propager_tension([source], objets, conducteurs, CONFIG.portee_contact, CONFIG.propriete_cause)
	verif.v(energises.is_empty(), "generateur inactif : aucun objet ne doit jamais s'energiser, meme un conducteur en contact")

# ---- avancer() : flux.gd cable, la reserve "courant" grandit ----

func _courant_ne_traverse_pas_le_bois() -> void:
	var fer1 := _objet("fer1", Vector3(90, 0, 0), CONDUCTIVITE_FER)
	var bois := _objet("bois", Vector3(180, 0, 0), CONDUCTIVITE_BOIS)
	var fer2 := _objet("fer2", Vector3(270, 0, 0), CONDUCTIVITE_FER)
	var objets := [fer1, bois, fer2]
	var source := _source("s", Vector3(0, 0, 0), true)
	var agent := _agent(Vector3(2000, 0, 0))
	for i in 10:
		BancConduction.avancer([source], objets, agent, 0.1, CONFIG, ETATS)
	verif.v(fer1.proprietes.reserves.courant.reserve > 0.0, "le premier fer doit accumuler du courant")
	verif.v(bois.proprietes.reserves.courant.reserve == 0.0, "le bois ne doit jamais accumuler de courant")
	verif.v(fer2.proprietes.reserves.courant.reserve == 0.0, "le second fer, derriere le bois, ne doit jamais accumuler de courant -- hors tension")
	verif.v(not fer2.proprietes.sous_tension, "le second fer doit rester marque hors tension")

func _courant_traverse_si_tout_est_fer() -> void:
	var fer1 := _objet("fer1", Vector3(90, 0, 0), CONDUCTIVITE_FER)
	var fer2 := _objet("fer2", Vector3(180, 0, 0), CONDUCTIVITE_FER)
	var fer3 := _objet("fer3", Vector3(270, 0, 0), CONDUCTIVITE_FER)
	var objets := [fer1, fer2, fer3]
	var source := _source("s", Vector3(0, 0, 0), true)
	var agent := _agent(Vector3(2000, 0, 0))
	for i in 10:
		BancConduction.avancer([source], objets, agent, 0.1, CONFIG, ETATS)
	verif.v(fer1.proprietes.reserves.courant.reserve > 0.0, "fer1 doit accumuler du courant")
	verif.v(fer2.proprietes.reserves.courant.reserve > 0.0, "fer2 doit accumuler du courant -- meme materiau que fer1, la chaine traverse")
	verif.v(fer3.proprietes.reserves.courant.reserve > 0.0, "fer3 doit accumuler du courant -- remplacer le bois par du fer fait traverser les trois")

func _objet_mouille_accumule_le_courant_plus_vite_qu_un_sec() -> void:
	var sec := _objet("sec", Vector3(90, 0, 0), CONDUCTIVITE_FER)
	var mouille := _objet("mouille", Vector3(90, 200, 0), CONDUCTIVITE_FER, ["mouille"])
	var source_sec := _source("source_sec", Vector3(0, 0, 0), true)
	var source_mouille := _source("source_mouille", Vector3(0, 200, 0), true)
	var agent := _agent(Vector3(2000, 0, 0))
	for i in 10:
		BancConduction.avancer([source_sec, source_mouille], [sec, mouille], agent, 0.1, CONFIG, ETATS)
	var reserve_sec: float = sec.proprietes.reserves.courant.reserve
	var reserve_mouille: float = mouille.proprietes.reserves.courant.reserve
	verif.v(reserve_sec > 0.0, "le fer sec doit accumuler du courant")
	verif.v(reserve_mouille > reserve_sec, "le fer mouille doit accumuler du courant plus vite que le sec")
	var ratio := reserve_mouille / reserve_sec
	verif.v(ratio > 9.0 and ratio < 11.0, "le rapport doit etre proche de 10.0 (mouille module conductivite_electrique x10.0), obtenu %.2f" % ratio)

# ---- avancer() : charge.gd -> etat_duree.gd -> depense.gd, degats a l'agent ----

func _agent_a_portee_d_un_conducteur_sous_tension_prend_des_degats() -> void:
	var fer := _objet("fer", Vector3(90, 0, 0), CONDUCTIVITE_FER)
	var source := _source("s", Vector3(0, 0, 0), true)
	var agent := _agent(Vector3(90, 40, 0))
	var reserve_initiale: float = agent.proprietes.reserves.integrite.reserve
	var deja_electrocute := false
	for i in 15:
		BancConduction.avancer([source], [fer], agent, 0.1, CONFIG, ETATS)
		if agent.proprietes.etats_actifs.has("electrocute"):
			deja_electrocute = true
	verif.v(deja_electrocute, "expose sans interruption a un fer sous tension a portee, l'agent doit finir par etre electrocute")
	verif.v(agent.proprietes.reserves.integrite.reserve < reserve_initiale, "electrocute, la reserve d'integrite de l'agent doit avoir decru")

func _agent_hors_portee_aucun_effet() -> void:
	var fer := _objet("fer", Vector3(90, 0, 0), CONDUCTIVITE_FER)
	var source := _source("s", Vector3(0, 0, 0), true)
	var agent := _agent(Vector3(90, 5000, 0))
	var reserve_initiale: float = agent.proprietes.reserves.integrite.reserve
	for i in 30:
		BancConduction.avancer([source], [fer], agent, 0.1, CONFIG, ETATS)
	verif.v(not agent.proprietes.etats_actifs.has("electrocute"), "hors de portee_charge, l'agent ne doit jamais etre electrocute")
	verif.v(agent.proprietes.reserves.integrite.reserve == reserve_initiale, "hors de portee_charge, la reserve d'integrite de l'agent ne doit jamais decroitre")

# ---- Fonctions pures isolees ----

func _causes_de_tension() -> void:
	var objets := [
		{"id": "a", "position": Vector3.ZERO, "proprietes": {"sous_tension": true, "conductivite_electrique": CONDUCTIVITE_FER, "etats_actifs": []}},
		{"id": "b", "position": Vector3(5, 0, 0), "proprietes": {"sous_tension": false, "conductivite_electrique": CONDUCTIVITE_FER, "etats_actifs": []}},
	]
	var causes := BancConduction.causes_de_tension(objets, "sous_tension", ETATS, CONFIG.facteur_conductivite_base)
	verif.v(causes.size() == 1 and causes[0].position == Vector3.ZERO, "causes_de_tension doit retenir uniquement les objets sous tension")
	verif.v(abs(causes[0].poids - CONDUCTIVITE_FER * CONFIG.facteur_conductivite_base) < 0.0001, "le poids doit valoir conductivite effective * facteur_conductivite_base")

func _basculer_generateurs() -> void:
	var sources := [_source("a", Vector3.ZERO, false), _source("b", Vector3(10, 0, 0), false)]
	BancConduction.basculer_generateurs(sources, "generateur")
	verif.v(sources[0].proprietes.generateur and sources[1].proprietes.generateur, "basculer_generateurs doit activer toutes les sources a la fois quand aucune n'est active")
	BancConduction.basculer_generateurs(sources, "generateur")
	verif.v(not sources[0].proprietes.generateur and not sources[1].proprietes.generateur, "basculer_generateurs doit desactiver toutes les sources a la fois")

# ---- Chemin REEL : materiaux.json/proprietes_immuables_composition.json ----

func _fabrication_reelle_fusionne_conductivite_electrique_depuis_materiaux_json() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(proprietes_immuables.has("conductivite_electrique"), "data/proprietes_immuables_composition.json doit lister conductivite_electrique")

	var declarations := [
		{"id": "fer_reel", "position": [0.0, 0.0, 0.0], "composition": [ {"materiau": "fer", "volume": 1.0} ]},
		{"id": "bois_reel", "position": [10.0, 0.0, 0.0], "composition": [ {"materiau": "bois", "volume": 1.0} ]},
	]
	var objets := BancConduction.fabriquer_objets(declarations, materiaux, proprietes_immuables)
	var fer: Dictionary = objets[0]
	var bois: Dictionary = objets[1]
	verif.v(abs(fer.proprietes.conductivite_electrique - 1.0e7) / 1.0e7 < 0.0001, "fer reel doit fusionner conductivite_electrique=1e7 depuis materiaux.json")
	verif.v(abs(bois.proprietes.conductivite_electrique - 1.0e-15) < 1.0e-14, "bois reel doit fusionner conductivite_electrique=1e-15 depuis materiaux.json")
	verif.v(fer.proprietes.has("reserves") and fer.proprietes.reserves.has("courant"), "fabriquer_objets doit initialiser une reserve 'courant' a 0.0")
	verif.v(fer.proprietes.reserves.courant.reserve == 0.0, "la reserve 'courant' initiale doit valoir 0.0")

	var etats_reels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	var actifs := BancConduction.conducteurs_actifs(objets, etats_reels, CONFIG.seuil_conduction)
	verif.v(actifs["fer_reel"], "chemin reel : le fer fabrique par composition doit etre conducteur_actif")
	verif.v(not actifs["bois_reel"], "chemin reel : le bois fabrique par composition ne doit jamais etre conducteur_actif")

# ---- Chemin REEL : data/banc_conduction.json ----

func _donnees_reelles_banc_conduction_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_conduction.json"))
	verif.v(donnees.propriete_cause == "generateur", "data/banc_conduction.json doit declarer propriete_cause")
	verif.v(donnees.nom_etat_electrocute == "electrocute", "data/banc_conduction.json doit declarer nom_etat_electrocute")
	verif.v(donnees.sources.size() == 4, "data/banc_conduction.json doit declarer quatre generateurs")
	verif.v(donnees.objets.size() == 8, "data/banc_conduction.json doit declarer huit objets")

	var par_id: Dictionary = {}
	for objet in donnees.objets:
		par_id[objet.id] = objet
	verif.v(par_id.has("fer_bloque_1") and par_id.has("bois_bloque") and par_id.has("fer_bloque_2"), "data/banc_conduction.json doit porter la rangee fer-bois-fer")
	verif.v(par_id.has("fer_traverse_1") and par_id.has("fer_traverse_2") and par_id.has("fer_traverse_3"), "data/banc_conduction.json doit porter la rangee fer-fer-fer")
	verif.v(par_id.fer_mouille.get("etats_actifs", []).has("mouille"), "fer_mouille doit declarer etats_actifs=['mouille']")
	verif.v(not par_id.fer_sec.has("etats_actifs") or par_id.fer_sec.get("etats_actifs", []).is_empty(), "fer_sec ne doit porter aucun etat")

	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	verif.v(etats.has("electrocute"), "data/etats.json (catalogue PARTAGE) doit porter l'entree 'electrocute'")
	verif.v(etats.electrocute.get("effets", []).is_empty(), "'electrocute' ne doit moduler aucune propriete -- marqueur de gate seul")

# Chemin REEL complet : data/banc_conduction.json + data/materiaux.json +
# data/etats.json + data/proprietes_immuables_composition.json lus sur
# disque, comme banc_conduction.gd les charge lui-meme a _ready() -- exerce
# exactement la scene decrite par le chantier (fer-bois-fer bloque,
# fer-fer-fer traverse, sec/mouille, agent electrocute).
func _chemin_reel_banc_conduction_json_bloque_isole_et_electrocute() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_conduction.json"))
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])

	var sources := BancConduction.fabriquer_generateurs(donnees.sources)
	var objets := BancConduction.fabriquer_objets(donnees.objets, materiaux, proprietes_immuables)
	var agent := BancConduction.fabriquer_agent(donnees.agent, donnees)
	BancConduction.basculer_generateurs(sources, donnees.propriete_cause)

	var par_id: Dictionary = {}
	for i in 10:
		BancConduction.avancer(sources, objets, agent, 0.1, donnees, etats)
	for objet in objets:
		par_id[objet.id] = objet

	verif.v(par_id.fer_bloque_1.proprietes.reserves.courant.reserve > 0.0, "chemin reel : fer_bloque_1 doit conduire (en contact direct d'un generateur actif)")
	verif.v(par_id.bois_bloque.proprietes.reserves.courant.reserve == 0.0, "chemin reel : bois_bloque ne doit jamais conduire")
	verif.v(par_id.fer_bloque_2.proprietes.reserves.courant.reserve == 0.0, "chemin reel : fer_bloque_2, derriere le bois, doit rester hors tension")

	verif.v(par_id.fer_traverse_1.proprietes.reserves.courant.reserve > 0.0, "chemin reel : fer_traverse_1 doit conduire")
	verif.v(par_id.fer_traverse_2.proprietes.reserves.courant.reserve > 0.0, "chemin reel : fer_traverse_2 doit conduire -- la chaine tout-fer traverse")
	verif.v(par_id.fer_traverse_3.proprietes.reserves.courant.reserve > 0.0, "chemin reel : fer_traverse_3 doit conduire -- remplacer le bois par du fer fait traverser les trois")

	verif.v(par_id.fer_mouille.proprietes.reserves.courant.reserve > par_id.fer_sec.proprietes.reserves.courant.reserve, "chemin reel : fer_mouille doit conduire mieux que fer_sec")

	verif.v(agent.proprietes.etats_actifs.has("electrocute"), "chemin reel : l'agent pose pres du fer central de la rangee qui traverse doit finir electrocute")
	verif.v(agent.proprietes.reserves.integrite.reserve < donnees.reserve_integrite_defaut.reserve, "chemin reel : la reserve d'integrite de l'agent doit avoir decru")

	# Couper les generateurs doit arreter les degats -- la reserve cesse de
	# decroitre une fois "electrocute" retire par etat_duree.gd (guerison
	# progressive, jamais instantanee).
	BancConduction.basculer_generateurs(sources, donnees.propriete_cause)
	for i in 40:
		BancConduction.avancer(sources, objets, agent, 0.1, donnees, etats)
	verif.v(not agent.proprietes.etats_actifs.has("electrocute"), "chemin reel : generateurs coupes assez longtemps, 'electrocute' doit finir par etre retire par etat_duree.gd")
	var reserve_apres_guerison: float = agent.proprietes.reserves.integrite.reserve
	for i in 10:
		BancConduction.avancer(sources, objets, agent, 0.1, donnees, etats)
	verif.v(agent.proprietes.reserves.integrite.reserve == reserve_apres_guerison, "chemin reel : 'electrocute' retire et generateurs coupes, la reserve d'integrite doit rester figee")
