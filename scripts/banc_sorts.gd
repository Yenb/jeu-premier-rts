extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_sorts.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « sorts -- cablage
# de base + banc de demonstration », audit prealable
# audit_sorts_cablage_base_prealable.md. POSE LA TUYAUTERIE des sorts, pas
# les sorts eux-memes : data/sorts.json nomme un effet (mecanisme existant
# du coeur) + une grandeur + une cible + une portee + un cout_mana ; ce
# fichier ne fait que LIRE une entree et DISPATCHER vers le mecanisme
# nomme. Ajouter un cinquieme sort qui reutilise un "effet" deja cable est
# une ligne de data/sorts.json, zero ligne de ce fichier.
#
# AUCUN MECANISME DU COEUR TOUCHE : frappe.gd/flux.gd/charge.gd/
# seuil_etat.gd/etat_duree.gd/etat_effectif.gd/produit.gd/depense.gd/
# perception.gd/portee.gd/agir.gd/objet.gd restent EXACTEMENT ceux deja
# verrouilles par leurs propres tests. Ce fichier COMPOSE quatre patrons
# deja fermes :
# - "frappe" -> Frappe.selectionner (critere lu depuis grandeur.critere,
#   forme EXACTE deja prouvee par banc_choc_magique.gd) + Frappe.frapper.
# - "flux" -> Flux.avancer avec un EMETTEUR SYNTHETIQUE reconstruit a
#   chaque appel (patron banc_conduction.gd/banc_mana_conduction.gd),
#   jamais une propriete SOURCE reelle posee sur le lanceur. Appele avec
#   delta=1.0 (UNE unite, jamais un delta de frame) : un sort est un
#   EVENEMENT PONCTUEL (meme distinction que frappe.gd:frapper -- "un
#   degat instantane n'a pas de delta a lui donner sans detourner sa
#   semantique"), "taux" sert alors directement de quantite appliquee UNE
#   FOIS, jamais recalculee par tick.
# - "etat" -> EtatDuree.poser, INCHANGE. La duree REELLEMENT appliquee
#   vient de data/etats.json:<nom_etat>.duree -- EtatDuree.poser ne
#   recoit jamais de duree en parametre, grandeur.duree dans
#   data/sorts.json documente seulement l'INTENTION, les deux valeurs
#   DOIVENT coincider (verifie a l'ecriture pour "protege").
# - "frappe_zone" -> boucle scripts/portee.gd:en_portee + Frappe.frapper
#   sur CHAQUE objet a portee. PAS Frappe.selectionner (qui ne rend qu'UN
#   SEUL objet, jamais une liste -- nuance de l'audit prealable) : une
#   cible "zone" ne passe donc jamais par la selection, seulement par la
#   meme comparaison de portee que charge.gd/flux.gd/frappe.gd partagent
#   deja.
#
# DISPATCHER = lancer_sort(caster, sort_id, catalogue_sorts, monde,
# catalogue_etats, materiaux) -> { succes, cible, effet } -- UNE fonction
# statique, aucun etat retenu, aucun nom de sort en dur au-dela d'un match
# sur "effet" (jamais sur sort_id). Verifie le mana (proprietes.reserves.
# mana.reserve >= cout_mana, sinon rien ne se passe, succes=false) puis le
# SOUSTRAIT DIRECTEMENT (max(0.0, ...), patron depense.gd -- jamais via
# Depense.avancer, meme raison que Frappe.frapper : ponctuel, pas un taux
# continu). affinite_magique (proprietes.get("affinite_magique", 1.0) du
# LANCEUR, jamais fusionnee par composition -- posee directement sur le
# type du caster dans data/banc_sorts.json) MULTIPLIE toute grandeur
# D'INTENSITE (degats/taux) avant l'appel au mecanisme -- jamais nom_etat/
# duree/nom_reserve, qui ne sont pas des intensites.
#
# VOLATILITE_MAGIQUE : DECISION YAEL (question posee avant d'ecrire, voir
# ci-dessous) -- les valeurs dormantes existantes de data/materiaux.json
# (bois 0.3/pierre 0.1/fer 0.05) sont hors d'echelle avec des degats de
# sort (3.0-10.0 par coup -- un seul coup les depasserait toutes,
# "explose" au premier sort recu, jamais "apres quelques sorts") ET dans
# un ORDRE qui contredirait la demonstration voulue (fer y est la valeur
# la PLUS BASSE des trois, pas la plus haute -- "le fer resiste longtemps"
# serait faux). "volatilite_magique" est donc POSEE A LA MAIN sur les
# quatre cibles FABRIQUEES de ce banc (fabriquer_cibles ci-dessous, meme
# geste que "force_radiation" dans banc_radiation.gd:fabriquer_source --
# jamais fusionnee par composition), a des valeurs propres a CE banc
# (verre_sort 8.0 < bois_sort 20.0 < pierre_sort 35.0 < fer_sort 60.0).
# bois/pierre/fer restent INCHANGES partout ailleurs dans le depot.
#
# CHARGE_MAGIQUE_CUMULEE : chaque objet touche par "frappe"/"frappe_zone"
# recoit grandeur.degats (deja multiplie par affinite_magique) AJOUTE a
# proprietes.charge_magique_cumulee -- meme geste que "degats_impact_
# cumules" dans banc_fracture.gd/"choc_magique_cumule" dans
# banc_choc_magique.gd, jamais un mecanisme du coeur. scripts/seuil_etat.gd
# (INCHANGE, data/seuils_etat.json:explosion_magique, NOUVELLE entree)
# compare cette grandeur a "volatilite_magique" (seuil_propriete) et pose
# "explose" (data/etats.json, NOUVEL etat, marqueur pur -- aucun effet
# module, jamais de duree, IRREVERSIBLE, meme famille que "fracture"/
# "corrode_acide") au franchissement. avancer_explosions (fonction PROPRE
# a ce fichier, ci-dessous) detecte "explose" fraichement pose et
# declenche Frappe.frapper sur tout ce qui est a portee (rayon_explosion_
# volatilite, data/banc_sorts.json) -- UNE SEULE FOIS par objet explose
# (memoire _deja_explose, jamais reappliquee).
#
# MANA AMBIANT : une source hand-built (patron banc_animal.gd -- pas
# Objet.fabriquer, aucune composition physique) porte "source_mana": true/
# taux_flux/portee_flux poses a la fabrication ; le caster porte
# "capte_mana": true (structurelle a ce banc). Flux.avancer (INCHANGE,
# table_flux locale a UNE ligne) recharge proprietes.reserves.mana du
# caster CHAQUE TICK, INDEPENDAMMENT de lancer_sort -- meme separation que
# banc_animal.gd (flux.gd/depense.gd tournent en continu, le cablage ne
# fait que poser les nombres).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et fabrique caster/cibles/
#   source_mana. _unhandled_input lit les touches 1/2/3/4 et appelle
#   lancer_sort. _process fait avancer le mana ambiant (Flux.avancer),
#   l'expiration de "protege" (EtatDuree.avancer), le seuil d'explosion
#   (SeuilEtat.avancer) et la detection de nouvelles explosions
#   (avancer_explosions), puis redessine.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_sorts.gd) : lancer_sort/avancer_explosions/fabriquer_caster/
#   fabriquer_cibles/fabriquer_source_mana, plus le texte d'affichage et
#   de log.

const Objet = preload("res://scripts/objet.gd")
const Frappe = preload("res://scripts/frappe.gd")
const Flux = preload("res://scripts/flux.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Portee = preload("res://scripts/portee.gd")

const PROPRIETE_RECEPTRICE_SORT := "receptrice_sort"
const PROPRIETE_CHARGE_MAGIQUE := "charge_magique_cumulee"
const TAILLE := 70.0
const TAILLE_CASTER := 50.0
const TAILLE_POLICE_LABEL := 13

var _config: Dictionary = {}
var _sorts: Dictionary = {}
var _etats: Dictionary = {}
var _seuils_etat: Dictionary = {}
var _materiaux: Dictionary = {}
var _proprietes_immuables: Array = []
var _catalogue_types: Dictionary = {}
var _caster: Dictionary = {}
var _cibles: Array = []
var _source_mana: Dictionary = {}
var _table_flux_mana: Array = []
var _deja_explose: Dictionary = {}
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_caster: ColorRect
var _label_caster: Label
var _camera: Camera2D
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_sorts.json")
	_sorts = _charger_json("res://data/sorts.json")
	_etats = _charger_json("res://data/etats.json")
	_seuils_etat = _charger_json("res://data/seuils_etat.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_proprietes_immuables = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	_catalogue_types = _charger_json("res://data/types.json")

	_caster = fabriquer_caster(_config.caster, _catalogue_types, _config.propriete_capte_mana)
	_cibles = fabriquer_cibles(_config.cibles, _catalogue_types.objet_physique, _materiaux, _proprietes_immuables, _config.reserve_integrite_defaut, _config.nom_reserve_integrite)
	_source_mana = fabriquer_source_mana(_config.source_mana, _config.propriete_source_mana)
	_table_flux_mana = [{"source": _config.propriete_source_mana, "receptrice": _config.propriete_capte_mana, "cible": _config.nom_reserve_mana}]

	for cible in _cibles:
		_deja_explose[cible.id] = false
		_creer_rendu_cible(cible)
	_creer_rendu_caster()
	_creer_rendu_source_mana()
	_poser_camera()
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var sort_id := ""
	match event.keycode:
		KEY_1: sort_id = "eclair"
		KEY_2: sort_id = "soin"
		KEY_3: sort_id = "bouclier"
		KEY_4: sort_id = "explosion"
	if sort_id == "":
		return
	var resultat := lancer_sort(_caster, sort_id, _sorts, _cibles, _etats, _materiaux)
	_tracer_sort(sort_id, resultat)
	_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta

	Flux.avancer([_source_mana, _caster], _table_flux_mana, delta)
	EtatDuree.avancer([_caster], delta, _etats)
	SeuilEtat.avancer(_cibles, _seuils_etat)

	var nouvelles := avancer_explosions(_cibles, _config.rayon_explosion_volatilite, _config.degats_explosion_volatilite, _config.nom_reserve_integrite, _deja_explose)
	for id in nouvelles:
		print(_ligne_explosion(_temps, id))

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for cible in _cibles:
		var id: String = cible.id
		var diag := diagnostiquer_cible(cible, _config)
		_noeuds[id].color = Color(0.85, 0.3, 0.1) if diag.explose else Color(0.55, 0.55, 0.6)
		_labels[id].text = _texte_label_cible(id, diag)
	_label_caster.text = _texte_label_caster(_caster, _etats)

# ---- Fonctions PURES, testables headless (voir test_banc_sorts.gd) ----

# LE DISPATCHER. Voir en-tete du fichier pour le detail par "effet".
# Rend { succes: bool, cible: Variant, effet: String } -- cible est un
# Dictionary d'objet pour "frappe"/"flux"/"etat", un Array de Dictionary
# pour "frappe_zone" (plusieurs cibles touchees), null si le sort ne s'est
# pas lance (catalogue/mana insuffisant) ou n'a touche personne
# ("frappe" hors de portee de tout objet).
static func lancer_sort(caster: Dictionary, sort_id: String, catalogue_sorts: Dictionary, monde: Array, catalogue_etats: Dictionary, materiaux: Dictionary) -> Dictionary:
	if not catalogue_sorts.has(sort_id):
		push_error("banc_sorts.gd : sort '%s' absent du catalogue" % sort_id)
		return {"succes": false, "cible": null, "effet": ""}

	var entree: Dictionary = catalogue_sorts[sort_id]
	var effet: String = entree.get("effet", "")
	var cout_mana: float = entree.get("cout_mana", 0.0)
	var reserves: Dictionary = caster.proprietes.get("reserves", {})
	var canal_mana: Dictionary = reserves.get("mana", {})
	if canal_mana.get("reserve", 0.0) < cout_mana:
		return {"succes": false, "cible": null, "effet": effet}
	canal_mana["reserve"] = max(0.0, canal_mana.get("reserve", 0.0) - cout_mana)

	var affinite: float = caster.proprietes.get("affinite_magique", 1.0)
	var grandeur: Dictionary = entree.get("grandeur", {})
	var portee: float = entree.get("portee", 0.0)

	match effet:
		"frappe":
			var criteres: Array = [grandeur.get("critere", {})]
			var cible: Dictionary = Frappe.selectionner(monde, caster.position, portee, criteres, materiaux)
			if cible.is_empty():
				return {"succes": false, "cible": null, "effet": effet}
			var degats_effectifs: float = float(grandeur.get("degats", 0.0)) * affinite
			Frappe.frapper(cible, degats_effectifs, grandeur.get("nom_reserve", ""))
			_accumuler_charge_magique(cible, degats_effectifs)
			return {"succes": true, "cible": cible, "effet": effet}

		"flux":
			var taux: float = float(grandeur.get("taux", 0.0)) * affinite
			var emetteur := {
				"id": "%s_emetteur_%s" % [caster.get("id", "?"), sort_id],
				"position": caster.position,
				"proprietes": {"__sort_source__": true, "taux_flux": taux, "portee_flux": portee},
			}
			var table_flux := [{"source": "__sort_source__", "receptrice": PROPRIETE_RECEPTRICE_SORT, "cible": grandeur.get("reserve_cible", "")}]
			Flux.avancer([emetteur, caster], table_flux, 1.0)
			return {"succes": true, "cible": caster, "effet": effet}

		"etat":
			EtatDuree.poser(caster, grandeur.get("nom_etat", ""), catalogue_etats)
			return {"succes": true, "cible": caster, "effet": effet}

		"frappe_zone":
			var degats_zone: float = float(grandeur.get("degats", 0.0)) * affinite
			var nom_reserve_zone: String = grandeur.get("nom_reserve", "")
			var touches: Array = []
			for objet in monde:
				if Portee.en_portee(caster.position, objet.position, portee):
					Frappe.frapper(objet, degats_zone, nom_reserve_zone)
					_accumuler_charge_magique(objet, degats_zone)
					touches.append(objet)
			return {"succes": true, "cible": touches, "effet": effet}

		_:
			push_error("banc_sorts.gd : effet '%s' inconnu (sort '%s')" % [effet, sort_id])
			return {"succes": false, "cible": null, "effet": effet}

static func _accumuler_charge_magique(objet: Dictionary, degats: float) -> void:
	var cumul: float = objet.proprietes.get(PROPRIETE_CHARGE_MAGIQUE, 0.0)
	objet.proprietes[PROPRIETE_CHARGE_MAGIQUE] = cumul + degats

# Detecte, PARMI "objets", ceux qui portent "explose" dans etats_actifs
# (pose par SeuilEtat.avancer, appele par l'appelant AVANT cette fonction,
# jamais ici) et n'ont pas encore explose CETTE PARTIE (deja_explose,
# Dictionary id -> bool, MUTE EN PLACE -- meme convention que canal.charge
# dans charge.gd). Pour chacun, une SEULE fois, applique Frappe.frapper a
# "degats_explosion" sur CHAQUE AUTRE objet a "rayon_explosion" (Portee.
# en_portee, jamais Frappe.selectionner -- une explosion touche TOUT ce
# qui est a portee, pas un seul objet). Rend l'Array des ids qui viennent
# d'exploser CE passage.
static func avancer_explosions(objets: Array, rayon_explosion: float, degats_explosion: float, nom_reserve: String, deja_explose: Dictionary) -> Array:
	var nouvelles: Array = []
	for objet in objets:
		if not objet.proprietes.get("etats_actifs", []).has("explose"):
			continue
		if deja_explose.get(objet.id, false):
			continue
		deja_explose[objet.id] = true
		nouvelles.append(objet.id)
		for cible in objets:
			if cible.id == objet.id:
				continue
			if Portee.en_portee(objet.position, cible.position, rayon_explosion):
				Frappe.frapper(cible, degats_explosion, nom_reserve)
	return nouvelles

# Colon fabrique via Objet.fabriquer (catalogue_types PORTE deja colon +
# ses quatre paquets herites -- table PASSEE TELLE QUELLE, jamais
# retaillee ici). affinite_magique/resistance_impact/reserves.mana/
# reserves.sante/capte_mana/receptrice_sort/sort_en_cours sont poses A LA
# MAIN apres fabrication (aucun des sept n'existe sur le paquet colon) --
# meme geste que banc_radiation.gd:fabriquer_source pour force_radiation.
# resistance_impact (base, PAS fusionnee -- un colon n'a jamais de
# "composition") existe UNIQUEMENT pour que "protege" (module
# resistance_impact x3.0, data/etats.json) ait une base non nulle a
# moduler sur le caster -- meme raison que malleabilite pour "chaud" dans
# data/proprietes_immuables_composition.json, transposee a un colon.
static func fabriquer_caster(decl: Dictionary, catalogue_types: Dictionary, propriete_capte_mana: String) -> Dictionary:
	var pos: Array = decl.position
	var caster := Objet.fabriquer(decl.id, "colon", Vector3(pos[0], pos[1], pos[2]), catalogue_types)
	caster.proprietes["affinite_magique"] = decl.get("affinite_magique", 1.0)
	caster.proprietes["resistance_impact"] = decl.get("resistance_impact_base", 0.0)
	caster.proprietes["reserves"]["mana"] = decl.reserve_mana_defaut.duplicate(true)
	caster.proprietes["reserves"]["sante"] = decl.reserve_sante_defaut.duplicate(true)
	caster.proprietes[propriete_capte_mana] = true
	caster.proprietes[PROPRIETE_RECEPTRICE_SORT] = true
	caster.proprietes["sort_en_cours"] = ""
	return caster

# Cibles fabriquees via Objet.fabriquer (composition fusionnee, meme
# patron que banc_choc_magique.gd:fabriquer_objets). reserves.<integrite>/
# charge_magique_cumulee/etats_actifs/volatilite_magique sont poses A LA
# MAIN (aucun n'existe sur objet_physique) -- volatilite_magique EN
# PARTICULIER n'est PAS lue depuis materiaux.json/proprietes_immuables
# (voir en-tete du fichier, DECISION YAEL) : chaque declaration porte SA
# PROPRE valeur, propre a ce banc.
static func fabriquer_cibles(declarations: Array, objet_physique: Dictionary, materiaux: Dictionary, proprietes_immuables: Array, reserve_integrite_defaut: Dictionary, nom_reserve_integrite: String) -> Array:
	var table: Dictionary = {"objet_physique": objet_physique}
	for decl in declarations:
		table[decl.id] = {"herite": ["objet_physique"], "composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), table, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet.proprietes["reserves"] = {nom_reserve_integrite: reserve_integrite_defaut.duplicate(true)}
		objet.proprietes[PROPRIETE_CHARGE_MAGIQUE] = 0.0
		objet.proprietes["etats_actifs"] = []
		objet.proprietes["volatilite_magique"] = decl.get("volatilite_magique", 0.0)
		objets.append(objet)
	return objets

# Hand-built, AUCUNE composition -- un point d'emission de mana n'a besoin
# d'aucune matiere physique, meme raison que banc_radiation.gd:
# fabriquer_source/banc_animal.gd (sources ambiantes).
static func fabriquer_source_mana(decl: Dictionary, propriete_source: String) -> Dictionary:
	var pos: Array = decl.position
	return {
		"id": decl.id,
		"position": Vector3(pos[0], pos[1], pos[2]),
		"proprietes": {propriete_source: true, "taux_flux": decl.taux_flux, "portee_flux": decl.portee_flux},
	}

static func diagnostiquer_cible(cible: Dictionary, config: Dictionary) -> Dictionary:
	var reserves: Dictionary = cible.proprietes.get("reserves", {})
	return {
		"integrite": reserves.get(config.nom_reserve_integrite, {}).get("reserve", 0.0),
		"charge_magique_cumulee": cible.proprietes.get(PROPRIETE_CHARGE_MAGIQUE, 0.0),
		"volatilite_magique": cible.proprietes.get("volatilite_magique", 0.0),
		"explose": cible.proprietes.get("etats_actifs", []).has("explose"),
	}

static func _texte_label_cible(id: String, diag: Dictionary) -> String:
	return "%s\nintegrite=%.2f\ncharge_magique=%.2f/%.2f\netat=%s" % [
		id, diag.integrite, diag.charge_magique_cumulee, diag.volatilite_magique, "EXPLOSE" if diag.explose else "intact"
	]

static func _texte_label_caster(caster: Dictionary, etats: Dictionary) -> String:
	var mana: float = caster.proprietes.get("reserves", {}).get("mana", {}).get("reserve", 0.0)
	var sante: float = caster.proprietes.get("reserves", {}).get("sante", {}).get("reserve", 0.0)
	var protege: bool = caster.proprietes.get("etats_actifs", []).has("protege")
	var resistance_effective: float = EtatEffectif.valeur(caster, "resistance_impact", etats)
	return "caster\nmana=%.2f\nsante=%.2f\naffinite_magique=%.2f\nprotege=%s (resistance_impact=%.2f)\nsort_en_cours=%s" % [
		mana, sante, caster.proprietes.get("affinite_magique", 1.0), protege, resistance_effective, caster.proprietes.get("sort_en_cours", "")
	]

static func _ligne_sort(t: float, sort_id: String, resultat: Dictionary, mana_restant: float) -> String:
	return "t=%.1fs SORT '%s' : succes (effet=%s, mana restant=%.2f)" % [t, sort_id, resultat.effet, mana_restant]

static func _ligne_sort_echec(t: float, sort_id: String, mana_restant: float) -> String:
	return "t=%.1fs SORT '%s' : ECHEC (mana insuffisant ou aucune cible, mana restant=%.2f)" % [t, sort_id, mana_restant]

static func _ligne_explosion(t: float, id: String) -> String:
	return "t=%.1fs %s : EXPLOSE (charge_magique_cumulee au-dela de volatilite_magique)" % [t, id]

func _tracer_sort(sort_id: String, resultat: Dictionary) -> void:
	_caster.proprietes["sort_en_cours"] = sort_id
	var mana_restant: float = _caster.proprietes.get("reserves", {}).get("mana", {}).get("reserve", 0.0)
	if resultat.succes:
		print(_ligne_sort(_temps, sort_id, resultat, mana_restant))
	else:
		print(_ligne_sort_echec(_temps, sort_id, mana_restant))

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_cible(cible: Dictionary) -> void:
	var id: String = cible.id
	var centre := Vector2(cible.position.x, cible.position.y)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 90.0)
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	_labels[id] = label

func _creer_rendu_caster() -> void:
	var centre := Vector2(_caster.position.x, _caster.position.y)
	_noeud_caster = ColorRect.new()
	_noeud_caster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_caster.color = Color(0.3, 0.5, 0.9)
	_noeud_caster.size = Vector2(TAILLE_CASTER, TAILLE_CASTER)
	_noeud_caster.position = centre - _noeud_caster.size / 2.0
	add_child(_noeud_caster)

	_label_caster = Label.new()
	_label_caster.position = _noeud_caster.position - Vector2(20.0, 110.0)
	_label_caster.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(_label_caster)

func _creer_rendu_source_mana() -> void:
	var centre := Vector2(_source_mana.position.x, _source_mana.position.y)
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.color = Color(0.6, 0.3, 0.9)
	noeud.size = Vector2(24.0, 24.0)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)

func _poser_camera() -> void:
	var decl_camera: Dictionary = _config.get("camera", {})
	var pos: Array = decl_camera.get("position", [0.0, 0.0])
	_camera = Camera2D.new()
	_camera.position = Vector2(pos[0], pos[1])
	_camera.zoom = Vector2(decl_camera.get("zoom", 0.5), decl_camera.get("zoom", 0.5))
	_camera.enabled = true
	add_child(_camera)
