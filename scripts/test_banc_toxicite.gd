extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_toxicite.gd
#
# Verrouille le cablage de banc_toxicite.gd -- chantier « toxicite --
# empoisonnement par contact » :
# 1. causes_toxicite (fonction pure de ce banc) rend une cause par objet a
#    toxicite EFFECTIVE strictement positive (EtatEffectif.valeur) -- un
#    objet non toxique n'en produit jamais ;
# 2. charge.gd -> etat_duree.gd -> depense.gd (INCHANGES, patron deja ferme
#    quatre fois par pourriture/corrosion/solubilite/conduction) appliquent
#    des degats continus a un agent expose a un objet toxique a portee,
#    proportionnels a la toxicite de cet objet.
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : charge.gd/etat_effectif.gd/
# etat_duree.gd/depense.gd/objet.gd restent exactement ceux deja verrouilles
# par leurs propres tests -- ce fichier verrouille uniquement banc_toxicite.gd.

const BancToxicite = preload("res://scripts/banc_toxicite.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

# Sous-ensemble local de data/etats.json, suffisant pour les tests
# d'isolation (hors chemin reel) -- "empoisonne" est un marqueur pur (duree,
# aucun effet), meme famille que "electrocute".
const ETATS := {
	"empoisonne": {
		"duree": 3.0,
		"effets": [],
	},
}

const CONFIG := {
	"nom_canal_empoisonnement": "empoisonnement",
	"canal_empoisonnement_defaut": {
		"charge": 0.0, "seuil": 1.0, "portee_charge": 60.0,
		"taux_decroissance": 1.0, "poser": { "expose_empoisonnement": true },
	},
	"declencheur_expose_empoisonnement": "expose_empoisonnement",
	"nom_etat_empoisonne": "empoisonne",
	"degat_par_s": 2.0,
	"nom_reserve_sante": "sante",
	"reserve_sante_defaut": { "reserve": 10.0, "cout_base": 0.0, "surcout_action": 0.0 },
}

const TOXICITE_POISON := 0.9
const TOXICITE_FER := 0.1
const TOXICITE_PIERRE := 0.0

func _init() -> void:
	_objet_toxique_produit_une_cause()
	_objet_non_toxique_ne_produit_jamais_de_cause()
	_charge_monte_proportionnellement_a_la_toxicite()
	_agent_a_portee_d_un_objet_toxique_prend_des_degats()
	_agent_pres_de_la_pierre_ne_s_empoisonne_jamais()
	_agent_hors_portee_aucun_effet()
	_deplacer_colon_cycle_circulaire()
	_fabrication_reelle_fusionne_toxicite_depuis_materiaux_json()
	_donnees_reelles_banc_toxicite_json()
	_chemin_reel_banc_toxicite_json_poison_vite_fer_lentement_pierre_jamais()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: un objet toxique produit une cause proportionnelle a sa toxicite, un objet non " +
		"toxique n'en produit jamais, la charge monte proportionnellement a la toxicite, un agent " +
		"a portee d'un objet toxique prend des degats continus, pres de la pierre il ne s'empoisonne " +
		"jamais, hors portee aucun effet, deplacer_colon cycle circulairement, la fabrication reelle " +
		"fusionne toxicite depuis materiaux.json, et data/banc_toxicite.json charge et se comporte " +
		"comme attendu chemin reel (poison rapide, fer lent, pierre jamais)")
	quit(0)

# ---- Fixtures ----

func _objet(id: String, position: Vector3, toxicite: float) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"toxicite": toxicite,
			"etats_actifs": [],
		},
	}

func _agent(position: Vector3) -> Dictionary:
	return BancToxicite.fabriquer_agent({"id": "agent_test"}, CONFIG, position)

# ---- causes_toxicite ----

func _objet_toxique_produit_une_cause() -> void:
	var causes := BancToxicite.causes_toxicite([_objet("poison", Vector3.ZERO, TOXICITE_POISON)], ETATS)
	verif.v(causes.size() == 1, "un objet a toxicite 0.9 doit produire exactement une cause")
	verif.v(abs(causes[0].poids - TOXICITE_POISON) < 0.0001, "le poids de la cause doit valoir la toxicite effective")

func _objet_non_toxique_ne_produit_jamais_de_cause() -> void:
	var causes := BancToxicite.causes_toxicite([_objet("pierre", Vector3.ZERO, TOXICITE_PIERRE)], ETATS)
	verif.v(causes.is_empty(), "un objet a toxicite 0.0 (pierre) ne doit jamais produire de cause")

func _charge_monte_proportionnellement_a_la_toxicite() -> void:
	# Meme demarche que test_banc_conduction.gd:_objet_mouille_accumule_le_
	# courant_plus_vite_qu_un_sec -- deux agents identiques, exposes a deux
	# objets de toxicite differente, AVANT tout franchissement de seuil (pour
	# lire la charge brute, pas juste le booleen "empoisonne").
	var poison := _objet("poison", Vector3.ZERO, TOXICITE_POISON)
	var fer := _objet("fer", Vector3.ZERO, TOXICITE_FER)
	var agent_poison := _agent(Vector3.ZERO)
	var agent_fer := _agent(Vector3.ZERO)
	for i in 3:
		BancToxicite.avancer([poison], agent_poison, 0.1, CONFIG, ETATS)
		BancToxicite.avancer([fer], agent_fer, 0.1, CONFIG, ETATS)
	var charge_poison: float = agent_poison.proprietes.etats.empoisonnement.charge
	var charge_fer: float = agent_fer.proprietes.etats.empoisonnement.charge
	verif.v(charge_poison > 0.0 and charge_fer > 0.0, "les deux charges doivent avoir monte")
	var ratio := charge_poison / charge_fer
	var ratio_attendu := TOXICITE_POISON / TOXICITE_FER
	verif.v(abs(ratio - ratio_attendu) < 0.01, "le rapport des charges doit egaler le rapport des toxicites (%.2f), obtenu %.2f" % [ratio_attendu, ratio])

# ---- avancer() : charge.gd -> etat_duree.gd -> depense.gd ----

func _agent_a_portee_d_un_objet_toxique_prend_des_degats() -> void:
	var poison := _objet("poison", Vector3.ZERO, TOXICITE_POISON)
	var agent := _agent(Vector3(30, 0, 0))
	var reserve_initiale: float = agent.proprietes.reserves.sante.reserve
	var deja_empoisonne := false
	for i in 30:
		BancToxicite.avancer([poison], agent, 0.1, CONFIG, ETATS)
		if agent.proprietes.etats_actifs.has("empoisonne"):
			deja_empoisonne = true
	verif.v(deja_empoisonne, "expose sans interruption a un objet tres toxique a portee, l'agent doit finir par s'empoisonner")
	verif.v(agent.proprietes.reserves.sante.reserve < reserve_initiale, "empoisonne, la reserve de sante de l'agent doit avoir decru")

func _agent_pres_de_la_pierre_ne_s_empoisonne_jamais() -> void:
	var pierre := _objet("pierre", Vector3.ZERO, TOXICITE_PIERRE)
	var agent := _agent(Vector3(30, 0, 0))
	var reserve_initiale: float = agent.proprietes.reserves.sante.reserve
	for i in 100:
		BancToxicite.avancer([pierre], agent, 0.1, CONFIG, ETATS)
	verif.v(not agent.proprietes.etats_actifs.has("empoisonne"), "pres d'un objet non toxique (pierre), l'agent ne doit jamais s'empoisonner")
	verif.v(agent.proprietes.reserves.sante.reserve == reserve_initiale, "pres de la pierre, la reserve de sante de l'agent ne doit jamais decroitre")

func _agent_hors_portee_aucun_effet() -> void:
	var poison := _objet("poison", Vector3.ZERO, TOXICITE_POISON)
	var agent := _agent(Vector3(5000, 0, 0))
	var reserve_initiale: float = agent.proprietes.reserves.sante.reserve
	for i in 30:
		BancToxicite.avancer([poison], agent, 0.1, CONFIG, ETATS)
	verif.v(not agent.proprietes.etats_actifs.has("empoisonne"), "hors de portee_charge, l'agent ne doit jamais s'empoisonner")
	verif.v(agent.proprietes.reserves.sante.reserve == reserve_initiale, "hors de portee_charge, la reserve de sante de l'agent ne doit jamais decroitre")

# ---- deplacer_colon ----

func _deplacer_colon_cycle_circulaire() -> void:
	var positions := [[0.0, 0.0, 0.0], [300.0, 0.0, 0.0], [600.0, 0.0, 0.0]]
	var agent := _agent(Vector3.ZERO)
	var index := 0
	index = BancToxicite.deplacer_colon(agent, positions, index)
	verif.v(index == 1 and agent.position == Vector3(300, 0, 0), "un premier deplacement doit mener a l'index 1")
	index = BancToxicite.deplacer_colon(agent, positions, index)
	verif.v(index == 2 and agent.position == Vector3(600, 0, 0), "un second deplacement doit mener a l'index 2")
	index = BancToxicite.deplacer_colon(agent, positions, index)
	verif.v(index == 0 and agent.position == Vector3(0, 0, 0), "un troisieme deplacement doit boucler a l'index 0")

# ---- Chemin REEL : materiaux.json/proprietes_immuables_composition.json ----

func _fabrication_reelle_fusionne_toxicite_depuis_materiaux_json() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(proprietes_immuables.has("toxicite"), "data/proprietes_immuables_composition.json doit lister toxicite")

	var declarations := [
		{"id": "poison_reel", "position": [0.0, 0.0, 0.0], "composition": [ {"materiau": "poison_demo", "volume": 1.0} ]},
		{"id": "fer_reel", "position": [10.0, 0.0, 0.0], "composition": [ {"materiau": "fer", "volume": 1.0} ]},
		{"id": "pierre_reel", "position": [20.0, 0.0, 0.0], "composition": [ {"materiau": "pierre", "volume": 1.0} ]},
	]
	var objets := BancToxicite.fabriquer_objets(declarations, materiaux, proprietes_immuables)
	var poison: Dictionary = objets[0]
	var fer: Dictionary = objets[1]
	var pierre: Dictionary = objets[2]
	verif.v(abs(poison.proprietes.toxicite - 0.9) < 0.0001, "poison_demo reel doit fusionner toxicite=0.9 depuis materiaux.json")
	verif.v(abs(fer.proprietes.toxicite - 0.1) < 0.0001, "fer reel doit fusionner toxicite=0.1 depuis materiaux.json")
	verif.v(abs(pierre.proprietes.toxicite - 0.0) < 0.0001, "pierre reelle doit fusionner toxicite=0.0 depuis materiaux.json")

	var etats_reels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	verif.v(etats_reels.has("empoisonne"), "data/etats.json (catalogue PARTAGE) doit porter l'entree 'empoisonne'")
	verif.v(etats_reels.empoisonne.get("effets", []).is_empty(), "'empoisonne' ne doit moduler aucune propriete -- marqueur de gate seul")

# ---- Chemin REEL : data/banc_toxicite.json ----

func _donnees_reelles_banc_toxicite_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_toxicite.json"))
	verif.v(donnees.nom_etat_empoisonne == "empoisonne", "data/banc_toxicite.json doit declarer nom_etat_empoisonne")
	verif.v(donnees.objets.size() == 3, "data/banc_toxicite.json doit declarer trois objets")
	verif.v(donnees.positions_colon.size() == 3, "data/banc_toxicite.json doit declarer trois positions de colon")

	var par_id: Dictionary = {}
	for objet in donnees.objets:
		par_id[objet.id] = objet
	verif.v(par_id.has("poison_demo") and par_id.has("fer_toxicite") and par_id.has("pierre_toxicite"), "data/banc_toxicite.json doit porter poison_demo/fer_toxicite/pierre_toxicite")
	verif.v(par_id.poison_demo.composition[0].materiau == "poison_demo", "l'objet poison_demo doit etre compose de poison_demo")

# Chemin REEL complet : data/banc_toxicite.json + data/materiaux.json +
# data/etats.json + data/proprietes_immuables_composition.json lus sur
# disque, comme banc_toxicite.gd les charge lui-meme a _ready() -- exerce
# exactement la scene decrite par le chantier (colon pres du poison, puis du
# fer, puis de la pierre).
func _chemin_reel_banc_toxicite_json_poison_vite_fer_lentement_pierre_jamais() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_toxicite.json"))
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])

	var objets := BancToxicite.fabriquer_objets(donnees.objets, materiaux, proprietes_immuables)

	# Pres de poison_demo (index 0, position de depart reelle) : doit
	# s'empoisonner vite (seuil 1.0 atteint en ~1.1s a poids 0.9/s).
	var pos0: Array = donnees.positions_colon[0]
	var agent := BancToxicite.fabriquer_agent(donnees.agent, donnees, Vector3(pos0[0], pos0[1], pos0[2]))
	for i in 30:
		BancToxicite.avancer(objets, agent, 0.1, donnees, etats)
	verif.v(agent.proprietes.etats_actifs.has("empoisonne"), "chemin reel : pres de poison_demo, l'agent doit s'empoisonner en moins de 3s")
	verif.v(agent.proprietes.reserves.sante.reserve < donnees.reserve_sante_defaut.reserve, "chemin reel : la reserve de sante doit avoir decru pres de poison_demo")
	var sante_apres_poison: float = agent.proprietes.reserves.sante.reserve

	# Deplacement vers fer_toxicite (index 1) : la charge redescend (fer,
	# a distance, ne contribue plus tant que le colon reste loin -- mais ici
	# on le deplace directement au contact du fer), l'empoisonnement finit par
	# s'estomper (etat_duree.gd) le temps qu'un nouveau seuil, plus lent, soit
	# franchi a son tour.
	var index := 0
	index = BancToxicite.deplacer_colon(agent, donnees.positions_colon, index)
	verif.v(index == 1, "deplacer_colon doit mener a l'index 1 (fer_toxicite)")
	for i in 200:
		BancToxicite.avancer(objets, agent, 0.1, donnees, etats)
	verif.v(agent.proprietes.reserves.sante.reserve < sante_apres_poison, "chemin reel : pres du fer, la reserve de sante doit continuer a decroitre (plus lentement)")

	# Deplacement vers pierre_toxicite (index 2) : plus aucune cause, la
	# charge redescend a 0.0, "empoisonne" finit par expirer et la reserve de
	# sante se fige.
	index = BancToxicite.deplacer_colon(agent, donnees.positions_colon, index)
	verif.v(index == 2, "deplacer_colon doit mener a l'index 2 (pierre_toxicite)")
	for i in 400:
		BancToxicite.avancer(objets, agent, 0.1, donnees, etats)
	verif.v(not agent.proprietes.etats_actifs.has("empoisonne"), "chemin reel : assez longtemps pres de la pierre, 'empoisonne' doit finir par etre retire par etat_duree.gd")
	var sante_figee: float = agent.proprietes.reserves.sante.reserve
	for i in 10:
		BancToxicite.avancer(objets, agent, 0.1, donnees, etats)
	verif.v(agent.proprietes.reserves.sante.reserve == sante_figee, "chemin reel : 'empoisonne' retire et pres de la pierre, la reserve de sante doit rester figee")
