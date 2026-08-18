extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_radiation.gd
#
# Verrouille le cablage de banc_radiation.gd -- chantier « sensibilite_radiation
# -- irradiation et blindage » :
# 1. perceoit_source/monde_pour_objet (fonctions pures de ce banc) decident,
#    via scripts/perception.gd (canal "radiation", INCHANGE), si la source
#    radioactive est visible pour un objet donne -- un mur dense EXACTEMENT
#    sur son segment la bloque, un mur hors segment ne change rien ;
# 2. avancer() (charge.gd -> etat_duree.gd -> depense.gd, tous INCHANGES,
#    patron deja ferme quatre fois) accumule une charge de radiation PAR
#    OBJET CIBLE, ponderee par (force_radiation de la source * sensibilite_
#    radiation EFFECTIVE de l'objet) -- une sensibilite nulle ne produit
#    jamais de cause.
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : perception.gd/charge.gd/
# etat_duree.gd/etat_effectif.gd/depense.gd/objet.gd/monde.gd restent
# exactement ceux deja verrouilles par leurs propres tests -- ce fichier
# verrouille uniquement banc_radiation.gd.

const BancRadiation = preload("res://scripts/banc_radiation.gd")
const Monde = preload("res://scripts/monde.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_perceoit_source_sans_mur_visible()
	_perceoit_source_mur_sur_le_segment_bloque()
	_perceoit_source_mur_hors_segment_ne_bloque_pas()
	_monde_pour_objet_exclut_le_mur_si_inactif()

	_sensibilite_nulle_ne_produit_jamais_de_charge()
	_charge_monte_proportionnellement_a_la_sensibilite()
	_objet_irradie_finit_par_consommer_l_integrite()
	_objet_hors_portee_aucun_effet()

	_fabrication_reelle_fusionne_sensibilite_radiation_depuis_materiaux_json()
	_donnees_reelles_banc_radiation_json()
	_chemin_reel_bois_plus_vite_que_fer_plus_vite_que_pierre()
	_chemin_reel_mur_actif_fer_jamais_irradie()
	_chemin_reel_sans_mur_les_trois_finissent_par_etre_irradies()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: perceoit_source bloque une source occluse par un mur dense sur son segment et " +
		"laisse passer un mur hors segment, avancer() accumule une charge de radiation par objet " +
		"ponderee par sensibilite_radiation effective (une sensibilite nulle n'accumule jamais), " +
		"un objet irradie voit son integrite decroitre, hors portee aucun effet, la fabrication " +
		"reelle fusionne sensibilite_radiation depuis materiaux.json, et data/banc_radiation.json " +
		"charge et se comporte comme attendu chemin reel (bois plus vite que fer, fer plus vite " +
		"que pierre, le mur dense bloque totalement fer_radiation, sans mur les trois finissent " +
		"par s'irradier)")
	quit(0)

# ---- Fixtures ----

const CATALOGUE_CANAUX := {
	"radiation": {
		"geometrie": "propagation_obstacles",
		"propriete_obstacle": "densite",
		"largeur_obstacle": 40.0,
		"propriete_emission": "force_radiation",
	},
}

const CONFIG := {
	"nom_canal_radiation": "radiation",
	"declencheur_expose_radiation": "expose_radiation",
	"canal_radiation_defaut": {
		"charge": 0.0, "seuil": 1.0, "portee_charge": 300.0,
		"taux_decroissance": 0.3, "poser": { "expose_radiation": true },
	},
	"nom_etat_irradie": "irradie",
	"nom_reserve_integrite": "integrite",
	"reserve_integrite_defaut": { "reserve": 10.0, "cout_base": 0.0, "surcout_action": 0.0 },
	"degat_par_s": 1.0,
	"portee_perception_radiation": 300.0,
	"seuil_perception_radiation": 0.01,
}

const ETATS := {
	"irradie": { "duree": 5.0, "effets": [] },
}

func _source(force: float, position: Vector3 = Vector3.ZERO) -> Dictionary:
	return { "id": "source_test", "position": position, "proprietes": { "force_radiation": force } }

func _mur(position: Vector3, densite: float) -> Dictionary:
	return { "id": "mur_test", "position": position, "proprietes": { "densite": densite } }

func _objet_radiation(id: String, position: Vector3, sensibilite: float) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"sensibilite_radiation": sensibilite,
			"etats": { CONFIG.nom_canal_radiation: CONFIG.canal_radiation_defaut.duplicate(true) },
			"etats_actifs": [],
			"reserves": { CONFIG.nom_reserve_integrite: CONFIG.reserve_integrite_defaut.duplicate(true) },
		},
	}

# ---- perceoit_source / monde_pour_objet ----

func _perceoit_source_sans_mur_visible() -> void:
	var source := _source(0.2)
	var objet := _objet_radiation("bois", Vector3(200, 0, 0), 0.3)
	var visible := BancRadiation.perceoit_source(objet, source, _mur(Vector3.ZERO, 0.0), false, 300.0, 0.01, CATALOGUE_CANAUX)
	verif.v(visible, "sans mur, la source doit etre percue")

func _perceoit_source_mur_sur_le_segment_bloque() -> void:
	var source := _source(0.2, Vector3.ZERO)
	var objet := _objet_radiation("fer", Vector3(0, -200, 0), 0.2)
	var mur := _mur(Vector3(0, -100, 0), 7.87)
	var visible := BancRadiation.perceoit_source(objet, source, mur, true, 300.0, 0.01, CATALOGUE_CANAUX)
	verif.v(not visible, "un mur tres dense EXACTEMENT sur le segment source->objet doit bloquer totalement la source")

func _perceoit_source_mur_hors_segment_ne_bloque_pas() -> void:
	var source := _source(0.2, Vector3.ZERO)
	var objet := _objet_radiation("bois", Vector3(200, 0, 0), 0.3)
	var mur := _mur(Vector3(0, -100, 0), 7.87)
	var visible := BancRadiation.perceoit_source(objet, source, mur, true, 300.0, 0.01, CATALOGUE_CANAUX)
	verif.v(visible, "un mur actif mais HORS du segment source->objet ne doit jamais bloquer")

func _monde_pour_objet_exclut_le_mur_si_inactif() -> void:
	var source := _source(0.2)
	var mur := _mur(Vector3(50, 0, 0), 7.87)
	var monde := BancRadiation.monde_pour_objet(source, mur, false)
	verif.v(not monde.choses.has("mur_test"), "monde_pour_objet : mur_actif=false ne doit jamais inclure le mur")
	var monde_actif := BancRadiation.monde_pour_objet(source, mur, true)
	verif.v(monde_actif.choses.has("mur_test"), "monde_pour_objet : mur_actif=true doit inclure le mur")

# ---- avancer() : charge.gd -> etat_duree.gd -> depense.gd ----

func _sensibilite_nulle_ne_produit_jamais_de_charge() -> void:
	var source := _source(0.2)
	var mur := _mur(Vector3.ZERO, 0.0)
	var objet := _objet_radiation("neutre", Vector3(100, 0, 0), 0.0)
	for i in 50:
		BancRadiation.avancer([objet], source, mur, false, 0.5, CONFIG, ETATS, CATALOGUE_CANAUX)
	verif.v(objet.proprietes.etats.radiation.charge == 0.0, "sensibilite_radiation 0.0 ne doit jamais produire de charge, meme visible et a portee")
	verif.v(not objet.proprietes.etats_actifs.has("irradie"), "sensibilite_radiation 0.0 ne doit jamais s'irradier")

func _charge_monte_proportionnellement_a_la_sensibilite() -> void:
	var source := _source(0.2)
	var mur := _mur(Vector3.ZERO, 0.0)
	var objet_haut := _objet_radiation("haut", Vector3(100, 0, 0), 0.3)
	var objet_bas := _objet_radiation("bas", Vector3(100, 0, 0), 0.1)
	for i in 3:
		BancRadiation.avancer([objet_haut], source, mur, false, 1.0, CONFIG, ETATS, CATALOGUE_CANAUX)
		BancRadiation.avancer([objet_bas], source, mur, false, 1.0, CONFIG, ETATS, CATALOGUE_CANAUX)
	var charge_haut: float = objet_haut.proprietes.etats.radiation.charge
	var charge_bas: float = objet_bas.proprietes.etats.radiation.charge
	verif.v(charge_haut > 0.0 and charge_bas > 0.0, "les deux charges doivent avoir monte")
	var ratio := charge_haut / charge_bas
	verif.v(abs(ratio - 3.0) < 0.01, "le rapport des charges doit egaler le rapport des sensibilites (0.3/0.1=3.0), obtenu %.2f" % ratio)

func _objet_irradie_finit_par_consommer_l_integrite() -> void:
	var source := _source(0.2)
	var mur := _mur(Vector3.ZERO, 0.0)
	var objet := _objet_radiation("cible", Vector3(50, 0, 0), 0.3)
	var reserve_initiale: float = objet.proprietes.reserves.integrite.reserve
	var deja_irradie := false
	for i in 60:
		BancRadiation.avancer([objet], source, mur, false, 0.5, CONFIG, ETATS, CATALOGUE_CANAUX)
		if objet.proprietes.etats_actifs.has("irradie"):
			deja_irradie = true
	verif.v(deja_irradie, "expose sans interruption a une source visible et sensible, l'objet doit finir par s'irradier")
	verif.v(objet.proprietes.reserves.integrite.reserve < reserve_initiale, "irradie, la reserve d'integrite de l'objet doit avoir decru")

func _objet_hors_portee_aucun_effet() -> void:
	var source := _source(0.2, Vector3(9000, 0, 0))
	var mur := _mur(Vector3.ZERO, 0.0)
	var objet := _objet_radiation("loin", Vector3.ZERO, 0.3)
	var reserve_initiale: float = objet.proprietes.reserves.integrite.reserve
	for i in 30:
		BancRadiation.avancer([objet], source, mur, false, 0.5, CONFIG, ETATS, CATALOGUE_CANAUX)
	verif.v(not objet.proprietes.etats_actifs.has("irradie"), "hors de portee, l'objet ne doit jamais s'irradier")
	verif.v(objet.proprietes.reserves.integrite.reserve == reserve_initiale, "hors de portee, la reserve d'integrite ne doit jamais decroitre")

# ---- Chemin REEL : materiaux.json/proprietes_immuables_composition.json/etats.json/canaux.json ----

func _fabrication_reelle_fusionne_sensibilite_radiation_depuis_materiaux_json() -> void:
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	verif.v(proprietes_immuables.has("sensibilite_radiation"), "data/proprietes_immuables_composition.json doit lister sensibilite_radiation")

	var declarations := [
		{ "id": "bois_reel", "position": [0.0, 0.0, 0.0], "composition": [ {"materiau": "bois", "volume": 1.0} ] },
		{ "id": "pierre_reel", "position": [10.0, 0.0, 0.0], "composition": [ {"materiau": "pierre", "volume": 1.0} ] },
		{ "id": "fer_reel", "position": [20.0, 0.0, 0.0], "composition": [ {"materiau": "fer", "volume": 1.0} ] },
	]
	var objets := BancRadiation.fabriquer_objets(declarations, materiaux, proprietes_immuables, CONFIG)
	verif.v(abs(objets[0].proprietes.sensibilite_radiation - 0.3) < 0.0001, "bois reel doit fusionner sensibilite_radiation=0.3 depuis materiaux.json")
	verif.v(abs(objets[1].proprietes.sensibilite_radiation - 0.1) < 0.0001, "pierre reelle doit fusionner sensibilite_radiation=0.1 depuis materiaux.json")
	verif.v(abs(objets[2].proprietes.sensibilite_radiation - 0.2) < 0.0001, "fer reel doit fusionner sensibilite_radiation=0.2 depuis materiaux.json")

	var etats_reels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	verif.v(etats_reels.has("irradie"), "data/etats.json (catalogue PARTAGE) doit porter l'entree 'irradie'")
	verif.v(etats_reels.irradie.get("effets", []).is_empty(), "'irradie' ne doit moduler aucune propriete -- marqueur de gate seul")

	var canaux_reels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/canaux.json"))
	verif.v(canaux_reels.has("radiation"), "data/canaux.json doit porter le canal 'radiation'")
	verif.v(canaux_reels.radiation.propriete_obstacle == "densite", "le canal 'radiation' doit viser 'densite' comme propriete_obstacle")
	verif.v(canaux_reels.radiation.propriete_emission == "force_radiation", "le canal 'radiation' doit viser 'force_radiation' comme propriete_emission")

# ---- Chemin REEL : data/banc_radiation.json ----

func _donnees_reelles_banc_radiation_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_radiation.json"))
	verif.v(donnees.nom_etat_irradie == "irradie", "data/banc_radiation.json doit declarer nom_etat_irradie")
	verif.v(donnees.objets.size() == 3, "data/banc_radiation.json doit declarer trois objets")
	var par_id: Dictionary = {}
	for objet in donnees.objets:
		par_id[objet.id] = objet
	verif.v(par_id.has("bois_radiation") and par_id.has("pierre_radiation") and par_id.has("fer_radiation"), "data/banc_radiation.json doit porter bois_radiation/pierre_radiation/fer_radiation")
	verif.v(donnees.mur.composition[0].materiau == "fer", "le mur doit etre en fer")

# Chemin REEL complet : data/banc_radiation.json + data/materiaux.json +
# data/etats.json + data/proprietes_immuables_composition.json +
# data/canaux.json lus sur disque, comme banc_radiation.gd les charge
# lui-meme a _ready().

func _fabriquer_tout_reel() -> Dictionary:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_radiation.json"))
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	var canaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/canaux.json"))

	var source := BancRadiation.fabriquer_source(donnees.source)
	var mur := BancRadiation.fabriquer_mur(donnees.mur, materiaux, proprietes_immuables)
	var objets := BancRadiation.fabriquer_objets(donnees.objets, materiaux, proprietes_immuables, donnees)
	return { "donnees": donnees, "etats": etats, "canaux": canaux, "source": source, "mur": mur, "objets": objets }

func _par_id(objets: Array, id: String) -> Dictionary:
	for objet in objets:
		if objet.id == id:
			return objet
	return {}

func _chemin_reel_bois_plus_vite_que_fer_plus_vite_que_pierre() -> void:
	var ctx := _fabriquer_tout_reel()
	for i in 20:
		BancRadiation.avancer(ctx.objets, ctx.source, ctx.mur, false, 1.0, ctx.donnees, ctx.etats, ctx.canaux)
	var bois := _par_id(ctx.objets, "bois_radiation")
	var pierre := _par_id(ctx.objets, "pierre_radiation")
	var fer := _par_id(ctx.objets, "fer_radiation")
	var charge_bois: float = bois.proprietes.etats.radiation.charge
	var charge_pierre: float = pierre.proprietes.etats.radiation.charge
	var charge_fer: float = fer.proprietes.etats.radiation.charge
	verif.v(charge_bois > charge_fer, "chemin reel, sans mur : le bois (sensibilite 0.3) doit accumuler plus vite que le fer (0.2)")
	verif.v(charge_fer > charge_pierre, "chemin reel, sans mur : le fer (sensibilite 0.2) doit accumuler plus vite que la pierre (0.1)")

func _chemin_reel_mur_actif_fer_jamais_irradie() -> void:
	var ctx := _fabriquer_tout_reel()
	for i in 200:
		BancRadiation.avancer(ctx.objets, ctx.source, ctx.mur, true, 1.0, ctx.donnees, ctx.etats, ctx.canaux)
	var fer := _par_id(ctx.objets, "fer_radiation")
	var bois := _par_id(ctx.objets, "bois_radiation")
	verif.v(fer.proprietes.etats.radiation.charge == 0.0, "chemin reel, mur actif : fer_radiation (derriere le mur) ne doit jamais accumuler de charge")
	verif.v(not fer.proprietes.etats_actifs.has("irradie"), "chemin reel, mur actif : fer_radiation ne doit jamais s'irradier")
	verif.v(bois.proprietes.etats_actifs.has("irradie"), "chemin reel, mur actif : bois_radiation (jamais sur le segment du mur) doit s'irradier normalement")

func _chemin_reel_sans_mur_les_trois_finissent_par_etre_irradies() -> void:
	var ctx := _fabriquer_tout_reel()
	for i in 400:
		BancRadiation.avancer(ctx.objets, ctx.source, ctx.mur, false, 1.0, ctx.donnees, ctx.etats, ctx.canaux)
	for objet in ctx.objets:
		verif.v(objet.proprietes.etats_actifs.has("irradie"), "chemin reel, sans mur, assez longtemps : %s doit finir par s'irradier" % objet.id)
