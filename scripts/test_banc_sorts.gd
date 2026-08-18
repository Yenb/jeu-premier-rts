extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_sorts.gd
#
# Verrouille le cablage de banc_sorts.gd -- chantier « sorts -- cablage de
# base + banc de demonstration », audit prealable
# audit_sorts_cablage_base_prealable.md :
# 1. lancer_sort (LE DISPATCHER) resout une entree de catalogue et appelle
#    le mecanisme nomme (frappe.gd/flux.gd/etat_duree.gd) avec les
#    parametres lus, jamais un nom de sort en dur.
# 2. le mana (reserves.mana.reserve) borne le lancement, souscrait
#    directement, jamais via depense.gd.
# 3. affinite_magique multiplie toute grandeur d'intensite avant l'appel
#    au mecanisme.
# 4. charge_magique_cumulee accumule sur chaque cible touchee par
#    "frappe"/"frappe_zone", et scripts/seuil_etat.gd (INCHANGE) la
#    compare a volatilite_magique pour poser "explose".
#
# AUCUN MECANISME DU COEUR TOUCHE par ce chantier : frappe.gd/flux.gd/
# etat_duree.gd/etat_effectif.gd/seuil_etat.gd/produit.gd/depense.gd/
# perception.gd/portee.gd/agir.gd/objet.gd restent exactement ceux deja
# verrouilles par leurs propres tests -- ce fichier verrouille uniquement
# banc_sorts.gd.

const BancSorts = preload("res://scripts/banc_sorts.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_eclair_touche_la_cible_la_plus_conductrice()
	_soin_remonte_la_reserve_sante_du_caster()
	_bouclier_pose_protege_qui_s_estompe_apres_duree()
	_explosion_touche_tous_les_objets_a_portee()
	_mana_insuffisant_empeche_le_sort()
	_affinite_magique_multiplie_les_degats()
	_charge_magique_cumulee_monte_a_chaque_sort_recu()
	_verre_explose_au_seuil_de_volatilite_magique()
	_fer_ne_explose_pas_sur_la_duree_du_test()

	_donnees_reelles_sorts_json()
	_donnees_reelles_banc_sorts_json()
	_chemin_reel_fabrication_et_eclair_choisit_fer()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: lancer_sort dispatche eclair/soin/bouclier/explosion vers frappe.gd/flux.gd/etat_duree.gd " +
		"sans toucher ces mecanismes, verifie le mana avant tout effet et le soustrait directement, " +
		"affinite_magique multiplie degats/taux, charge_magique_cumulee monte a chaque sort recu et " +
		"seuil_etat.gd pose 'explose' au franchissement de volatilite_magique (verre bas explose, fer " +
		"haut resiste), data/sorts.json et data/banc_sorts.json chargent et se comportent comme attendu " +
		"chemin reel (eclair choisit fer_sort, le plus conducteur)")
	quit(0)

# ---- Fixtures ----

const CATALOGUE_SORTS := {
	"eclair": {
		"effet": "frappe", "cible": "objet", "portee": 300.0,
		"grandeur": {"degats": 5.0, "nom_reserve": "integrite", "critere": {"propriete": "conductivite", "poids": 1.0, "source": "materiau"}},
		"cout_mana": 10.0,
	},
	"soin": {
		"effet": "flux", "cible": "soi", "portee": 0.0,
		"grandeur": {"taux": 2.0, "reserve_cible": "sante"},
		"cout_mana": 5.0,
	},
	"bouclier": {
		"effet": "etat", "cible": "soi", "portee": 0.0,
		"grandeur": {"nom_etat": "protege_test", "duree": 2.0},
		"cout_mana": 15.0,
	},
	"explosion": {
		"effet": "frappe_zone", "cible": "zone", "portee": 200.0,
		"grandeur": {"degats": 3.0, "nom_reserve": "integrite"},
		"cout_mana": 20.0,
	},
}

const ETATS_TEST := {
	"protege_test": {"duree": 2.0, "effets": [{"propriete": "resistance_impact", "mode": "moduler", "facteur": 3.0}]},
}

const SEUILS_ETAT_TEST := {
	"explosion_magique_test": {
		"propriete_continue": "charge_magique_cumulee",
		"seuil_propriete": "volatilite_magique",
		"etat": "explose",
	},
}

# Materiaux hors domaine ("conducteur"/"isolant") -- aucun rapport avec
# bois/pierre/fer, prouve que lancer_sort ne connait aucun nom de
# materiau, seulement le nom de propriete lu depuis grandeur.critere.
const MATERIAUX_TEST := {
	"conducteur": {"densite": 1.0, "conductivite": 10.0},
	"isolant": {"densite": 1.0, "conductivite": 0.0},
}

func _caster(mana: float = 30.0, affinite: float = 1.0) -> Dictionary:
	return {
		"id": "caster_test",
		"position": Vector3.ZERO,
		"proprietes": {
			"affinite_magique": affinite,
			"resistance_impact": 2.0,
			"reserves": {"mana": {"reserve": mana}, "sante": {"reserve": 50.0}},
			"etats_actifs": [],
			BancSorts.PROPRIETE_RECEPTRICE_SORT: true,
		},
	}

func _cible(id: String, materiau: String, position: Vector3) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"proprietes": {
			"composition": [{"materiau": materiau, "volume": 1.0}],
			"reserves": {"integrite": {"reserve": 20.0}},
			"charge_magique_cumulee": 0.0,
			"etats_actifs": [],
			"volatilite_magique": 10.0,
		},
	}

# ---- 1. eclair : dégât ponctuel, critère "materiau" ----

func _eclair_touche_la_cible_la_plus_conductrice() -> void:
	var caster := _caster()
	var faible := _cible("faible", "isolant", Vector3(50, 0, 0))
	var forte := _cible("forte", "conducteur", Vector3(60, 0, 0))
	var resultat := BancSorts.lancer_sort(caster, "eclair", CATALOGUE_SORTS, [faible, forte], ETATS_TEST, MATERIAUX_TEST)
	verif.v(resultat.succes, "eclair doit reussir")
	verif.v(resultat.cible.id == "forte", "eclair doit toucher l'objet le plus conducteur (forte), pas le plus proche")

# ---- 2. soin : transfert continu vers soi ----

func _soin_remonte_la_reserve_sante_du_caster() -> void:
	var caster := _caster()
	caster.proprietes.reserves.sante.reserve = 10.0
	var resultat := BancSorts.lancer_sort(caster, "soin", CATALOGUE_SORTS, [], ETATS_TEST, MATERIAUX_TEST)
	verif.v(resultat.succes, "soin doit reussir")
	verif.v(caster.proprietes.reserves.sante.reserve > 10.0, "soin doit augmenter la reserve sante du caster")

# ---- 3. bouclier : état temporaire sur soi ----

func _bouclier_pose_protege_qui_s_estompe_apres_duree() -> void:
	var caster := _caster()
	var resultat := BancSorts.lancer_sort(caster, "bouclier", CATALOGUE_SORTS, [], ETATS_TEST, MATERIAUX_TEST)
	verif.v(resultat.succes, "bouclier doit reussir")
	verif.v(caster.proprietes.etats_actifs.has("protege_test"), "bouclier doit poser l'etat nomme par grandeur.nom_etat")
	EtatDuree.avancer([caster], 3.0, ETATS_TEST)
	verif.v(not caster.proprietes.etats_actifs.has("protege_test"), "protege_test (duree 2.0) doit s'estomper apres un delta de 3.0")

# ---- 4. explosion : dégât de zone ----

func _explosion_touche_tous_les_objets_a_portee() -> void:
	var caster := _caster()
	var proche := _cible("proche", "isolant", Vector3(50, 0, 0))
	var loin := _cible("loin", "isolant", Vector3(500, 0, 0))
	var reserve_proche_avant: float = proche.proprietes.reserves.integrite.reserve
	var reserve_loin_avant: float = loin.proprietes.reserves.integrite.reserve
	var resultat := BancSorts.lancer_sort(caster, "explosion", CATALOGUE_SORTS, [proche, loin], ETATS_TEST, MATERIAUX_TEST)
	verif.v(resultat.succes, "explosion doit reussir")
	verif.v(resultat.cible.size() == 1, "explosion ne doit toucher que les objets a portee (un seul ici)")
	verif.v(proche.proprietes.reserves.integrite.reserve < reserve_proche_avant, "explosion doit toucher un objet a portee")
	verif.v(loin.proprietes.reserves.integrite.reserve == reserve_loin_avant, "explosion ne doit jamais toucher un objet hors de portee")

# ---- 5. mana insuffisant ----

func _mana_insuffisant_empeche_le_sort() -> void:
	var caster := _caster(2.0)
	var cible := _cible("cible", "conducteur", Vector3(50, 0, 0))
	var reserve_avant: float = cible.proprietes.reserves.integrite.reserve
	var resultat := BancSorts.lancer_sort(caster, "eclair", CATALOGUE_SORTS, [cible], ETATS_TEST, MATERIAUX_TEST)
	verif.v(not resultat.succes, "un mana insuffisant (2.0 < cout_mana 10.0) doit empecher le sort")
	verif.v(caster.proprietes.reserves.mana.reserve == 2.0, "le mana ne doit jamais etre ponctionne si le sort ne se lance pas")
	verif.v(cible.proprietes.reserves.integrite.reserve == reserve_avant, "aucune cible ne doit etre touchee si le sort ne se lance pas")

# ---- 6. affinite_magique multiplicateur ----

func _affinite_magique_multiplie_les_degats() -> void:
	var caster_normal := _caster(30.0, 1.0)
	var caster_fort := _caster(30.0, 2.0)
	var cible_normal := _cible("cible_normal", "conducteur", Vector3(50, 0, 0))
	var cible_fort := _cible("cible_fort", "conducteur", Vector3(50, 0, 0))
	BancSorts.lancer_sort(caster_normal, "eclair", CATALOGUE_SORTS, [cible_normal], ETATS_TEST, MATERIAUX_TEST)
	BancSorts.lancer_sort(caster_fort, "eclair", CATALOGUE_SORTS, [cible_fort], ETATS_TEST, MATERIAUX_TEST)
	var degat_normal: float = 20.0 - cible_normal.proprietes.reserves.integrite.reserve
	var degat_fort: float = 20.0 - cible_fort.proprietes.reserves.integrite.reserve
	verif.v(degat_normal > 0.0, "un caster a affinite 1.0 doit infliger un degat non nul")
	verif.v(abs(degat_fort - degat_normal * 2.0) < 0.001, "affinite 2.0 doit exactement doubler le degat (attendu %.2f, obtenu %.2f)" % [degat_normal * 2.0, degat_fort])

# ---- 7. charge_magique_cumulee ----

func _charge_magique_cumulee_monte_a_chaque_sort_recu() -> void:
	var caster := _caster()
	var cible := _cible("cible", "conducteur", Vector3(50, 0, 0))
	verif.v(cible.proprietes.charge_magique_cumulee == 0.0, "charge_magique_cumulee doit demarrer a 0.0")
	BancSorts.lancer_sort(caster, "eclair", CATALOGUE_SORTS, [cible], ETATS_TEST, MATERIAUX_TEST)
	var apres_un: float = cible.proprietes.charge_magique_cumulee
	verif.v(apres_un > 0.0, "un premier sort recu doit faire monter charge_magique_cumulee")
	caster.proprietes.reserves.mana.reserve = 30.0
	BancSorts.lancer_sort(caster, "eclair", CATALOGUE_SORTS, [cible], ETATS_TEST, MATERIAUX_TEST)
	verif.v(cible.proprietes.charge_magique_cumulee > apres_un, "un deuxieme sort recu doit faire monter charge_magique_cumulee davantage")

# ---- 8/9. volatilite_magique : verre explose, fer résiste ----

func _verre_explose_au_seuil_de_volatilite_magique() -> void:
	var caster := _caster()
	var verre := _cible("verre_test", "conducteur", Vector3(50, 0, 0))
	verre.proprietes.volatilite_magique = 8.0
	for i in 3:
		caster.proprietes.reserves.mana.reserve = 30.0
		BancSorts.lancer_sort(caster, "eclair", CATALOGUE_SORTS, [verre], ETATS_TEST, MATERIAUX_TEST)
		SeuilEtat.avancer([verre], SEUILS_ETAT_TEST)
	verif.v(verre.proprietes.etats_actifs.has("explose"), "un objet a volatilite_magique basse (8.0) doit exploser apres trois 'eclair' (5.0 chacun)")

func _fer_ne_explose_pas_sur_la_duree_du_test() -> void:
	var caster := _caster()
	var fer := _cible("fer_test", "conducteur", Vector3(50, 0, 0))
	fer.proprietes.volatilite_magique = 60.0
	for i in 3:
		caster.proprietes.reserves.mana.reserve = 30.0
		BancSorts.lancer_sort(caster, "eclair", CATALOGUE_SORTS, [fer], ETATS_TEST, MATERIAUX_TEST)
		SeuilEtat.avancer([fer], SEUILS_ETAT_TEST)
	verif.v(not fer.proprietes.etats_actifs.has("explose"), "un objet a volatilite_magique haute (60.0) ne doit pas exploser apres trois 'eclair' (15.0 cumules < 60.0)")

# ---- Chemin REEL : data/sorts.json / data/banc_sorts.json / data/types.json / data/materiaux.json ----

func _donnees_reelles_sorts_json() -> void:
	var sorts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sorts.json"))
	for nom in ["eclair", "soin", "bouclier", "explosion"]:
		verif.v(sorts.has(nom), "data/sorts.json doit porter le sort '%s'" % nom)
	verif.v(sorts.eclair.effet == "frappe", "eclair doit resoudre vers l'effet 'frappe'")
	verif.v(sorts.soin.effet == "flux", "soin doit resoudre vers l'effet 'flux'")
	verif.v(sorts.bouclier.effet == "etat", "bouclier doit resoudre vers l'effet 'etat'")
	verif.v(sorts.explosion.effet == "frappe_zone", "explosion doit resoudre vers l'effet 'frappe_zone'")
	verif.v(sorts.bouclier.grandeur.duree == JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json")).protege.duree, "grandeur.duree de 'bouclier' doit coincider avec data/etats.json:protege.duree")

func _donnees_reelles_banc_sorts_json() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_sorts.json"))
	verif.v(donnees.caster.affinite_magique == 1.5, "data/banc_sorts.json doit declarer affinite_magique=1.5 sur le caster")
	verif.v(donnees.cibles.size() == 4, "data/banc_sorts.json doit declarer quatre cibles")
	var volatilites: Dictionary = {}
	for decl in donnees.cibles:
		volatilites[decl.id] = decl.volatilite_magique
	verif.v(volatilites.verre_sort < volatilites.bois_sort, "verre_sort doit avoir une volatilite_magique plus basse que bois_sort")
	verif.v(volatilites.bois_sort < volatilites.pierre_sort, "bois_sort doit avoir une volatilite_magique plus basse que pierre_sort")
	verif.v(volatilites.pierre_sort < volatilites.fer_sort, "pierre_sort doit avoir une volatilite_magique plus basse que fer_sort (fer resiste le plus longtemps)")

func _chemin_reel_fabrication_et_eclair_choisit_fer() -> void:
	var donnees: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_sorts.json"))
	var sorts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sorts.json"))
	var materiaux: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json"))
	var proprietes_immuables: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", [])
	var catalogue_types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json"))
	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))

	var caster := BancSorts.fabriquer_caster(donnees.caster, catalogue_types, donnees.propriete_capte_mana)
	verif.v(abs(caster.proprietes.affinite_magique - 1.5) < 0.0001, "fabrication reelle : caster doit porter affinite_magique=1.5")
	verif.v(caster.proprietes.reserves.mana.reserve == donnees.caster.reserve_mana_defaut.reserve, "fabrication reelle : caster doit porter la reserve mana declaree")

	var cibles := BancSorts.fabriquer_cibles(donnees.cibles, catalogue_types.objet_physique, materiaux, proprietes_immuables, donnees.reserve_integrite_defaut, donnees.nom_reserve_integrite)
	verif.v(cibles.size() == 4, "fabrication reelle : quatre cibles doivent etre fabriquees")

	var resultat := BancSorts.lancer_sort(caster, "eclair", sorts, cibles, etats, materiaux)
	verif.v(resultat.succes, "chemin reel : eclair doit reussir (mana initial suffisant)")
	verif.v(resultat.cible.id == "fer_sort", "chemin reel : eclair doit choisir fer_sort, seule cible a haute conductivite_electrique (1e7)")
