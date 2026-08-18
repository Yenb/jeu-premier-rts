extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_emission.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). PREMIERE demonstration
# reelle du chantier "emission et seuil" : scripts/propagation.gd:recu/
# seuil_exposition (emission portee par la source en feu, decroissante
# avec la distance en 1/distance^2 ; seuil porte par la cible, derive de
# son intensite EFFECTIVE) jouant ENSEMBLE sur des objets Orion reels pour
# la premiere fois. Noms de domaine reels (bois/fer/inflammable/brule) --
# exception documentee (CLAUDE.md : "un banc jetable peut nommer une
# categorie pour poser une scene d'observation").
#
# JETABLE PAR DEFINITION : aucune regle de jeu ne doit vivre ici, seulement
# du cablage et de la lecture. Tout calcul de diagnostic est en fonctions
# STATIQUES testables (diagnostiquer/_teinte_pour_diagnostic/
# _texte_composition/_texte_statut/_texte_label/_evenement/_ligne_log) --
# _process ne fait qu'appeler Propagation.avancer (deja le mecanisme reel)
# puis LIRE ses resultats publics (recu/seuil_exposition/delai_ignition),
# jamais recalculer une loi deja ecrite ailleurs.
#
# CE QU'ON DOIT VOIR : deux feux DEJA allumes (aucun colon, jamais eteints)
# de meme materiau mais de volumes tres differents -- petit_feu (1.0) et
# grand_feu (8.0), memes volumes que banc_combustible.json:bois_petit/
# bois_moyen, meme capacite de reserve (0.8 vs 6.4). Devant chacun, deux
# cibles a la MEME distance (500.0) : une en bois (inflammable), une en
# fer (quasi inerte). Chaque cible affiche EN PERMANENCE ce qu'elle recoit
# (Propagation.recu, maximum sur les deux feux) et son seuil
# (Propagation.seuil_exposition) -- le statut se lit au nombre ET a la
# teinte. Seul grand_feu+bois_grand finit par s'enflammer : bois_petit
# prouve que la PORTEE manque (meme matiere, meme distance que bois_grand,
# mais petit_feu ne porte pas jusque-la) ; fer_petit/fer_grand prouvent que
# la MATIERE bloque (aucun des deux feux, meme le grand, ne les expose
# jamais). Aucune distance n'est ecrite en dur : voir data/
# banc_emission.json pour le detail des grandeurs choisies.
#
# LIMITE STRICTE (rappel explicite du chantier) : ce fichier cable
# UNIQUEMENT ce banc -- aucun mecanisme neuf, aucune extension du coeur.
# objet.gd/propagation.gd/etat_effectif.gd sont deja ecrits et verts ; ce
# fichier ne fait que les appeler et lire leurs resultats publics.

const Objet = preload("res://scripts/objet.gd")
const Propagation = preload("res://scripts/propagation.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")

const VULNERABILITE := "inflammable"
const TAILLE := 70.0
const HAUTEUR_BARRE := 10.0
const TAILLE_FEU := 90.0

var _monde: Array = []
var _feux: Array = []
var _cibles: Array = []
var _textes_composition: Dictionary = {}
var _dernier_statut: Dictionary = {}
var _exposition: Dictionary = {}
var _temps_ecoule_ignition: Dictionary = {}
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _menaces: Dictionary = {}
var _intensite: Dictionary = {}
var _emission: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_emission.json")
	_menaces = _charger_json("res://data/menaces.json")
	_intensite = _charger_json("res://data/intensite_propagation.json")
	_emission = _charger_json("res://data/emission_propagation.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var reserve_combustible := _charger_json("res://data/reserve_combustible_composition.json")

	var delai_base: float = donnees.get("delai_propagation_base", 1.0)

	var declarations_feux: Array = donnees.get("feux", [])
	var catalogue_feux: Dictionary = {}
	for decl in declarations_feux:
		catalogue_feux[decl.id] = {"composition": decl.composition}
	for decl in declarations_feux:
		var pos: Array = decl.position
		var feu := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue_feux, materiaux, [], reserve_combustible)
		if feu.is_empty():
			push_error("banc_emission.gd : fabrication refusee pour la source '%s'" % decl.id)
			continue
		feu.proprietes["brule"] = true
		_monde.append(feu)
		_feux.append(feu)
		_creer_rendu_feu(feu)

	var declarations_cibles: Array = donnees.get("cibles", [])
	var catalogue_cibles: Dictionary = {}
	for decl in declarations_cibles:
		catalogue_cibles[decl.id] = {
			VULNERABILITE: true,
			"delai_propagation": delai_base,
			"composition": decl.composition,
		}
	for decl in declarations_cibles:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue_cibles, materiaux, proprietes_immuables)
		if objet.is_empty():
			push_error("banc_emission.gd : fabrication refusee pour la cible '%s'" % decl.id)
			continue
		_monde.append(objet)
		_cibles.append(objet)
		_exposition[decl.id] = 0.0
		_textes_composition[decl.id] = _texte_composition(decl.composition)
		_creer_rendu_cible(objet)

	_poser_camera()
	_diagnostiquer_tout(0.0, true)

func _process(delta: float) -> void:
	_temps += delta
	var avant_ce_pas: Dictionary = {}
	for cible in _cibles:
		avant_ce_pas[cible.id] = _exposition.get(cible.id, 0.0)
	var enflammees: Array = Propagation.avancer(_monde, _menaces, _exposition, delta, {}, _intensite, {}, _emission)
	for id in enflammees:
		_temps_ecoule_ignition[id] = avant_ce_pas.get(id, 0.0) + delta
	_diagnostiquer_tout(_temps, false)

func _diagnostiquer_tout(t: float, forcer_log: bool) -> void:
	for cible in _cibles:
		var id: String = cible.id
		var exposition_actuelle: float = _exposition.get(id, 0.0)
		var diag: Dictionary = diagnostiquer(cible, _feux, exposition_actuelle, VULNERABILITE, _menaces, _intensite, {}, _emission)
		var temps_mis: float = _temps_ecoule_ignition.get(id, 0.0)
		if forcer_log or diag.statut != _dernier_statut.get(id, ""):
			print(_ligne_log(t, id, diag, exposition_actuelle, temps_mis))
			_dernier_statut[id] = diag.statut
		_noeuds[id].color = _teinte_pour_diagnostic(diag, exposition_actuelle)
		var exposition_pour_barre: float = temps_mis if diag.statut == "en_feu" else exposition_actuelle
		var ratio := _ratio_exposition(exposition_pour_barre, diag.delai_requis)
		var fond: ColorRect = _barres_fond[id]
		_barres_remplies[id].size.x = fond.size.x * ratio
		_labels[id].text = _texte_label(id, _textes_composition[id], diag, temps_mis)

# ---- Diagnostic, PUR : compose Propagation.recu/seuil_exposition/
# delai_ignition et EtatEffectif.valeur (deja publics, deja testes) -- ne
# reimplemente JAMAIS leur loi, seulement leur lecture. "recu" est le
# MAXIMUM sur toutes les sources en feu -- meme logique "au moins une
# source suffit" que propagation.gd:avancer (OU, jamais une somme). Rend
# { statut: "hors_de_portee" | "intact" | "expose" | "en_feu", effective:
# float, delai_requis: float, recu: float, seuil: float }.
static func diagnostiquer(
	chose: Dictionary,
	feux: Array,
	exposition_actuelle: float,
	vulnerabilite: String,
	menaces: Dictionary,
	intensite: Dictionary,
	etats: Dictionary,
	emission: Dictionary,
) -> Dictionary:
	var menace: String = menaces.get(vulnerabilite, "")
	var propriete_intensite: String = intensite.get("propriete_intensite", "")
	var effective: float = EtatEffectif.valeur(chose, propriete_intensite, etats)
	var seuil: float = Propagation.seuil_exposition(chose, intensite, etats, emission)
	var recu_max := 0.0
	for feu in feux:
		var r: float = Propagation.recu(chose, feu, emission)
		if r > recu_max:
			recu_max = r
	var delai_requis: float = Propagation.delai_ignition(chose, intensite, etats)
	if chose.proprietes.get(menace, false):
		return {"statut": "en_feu", "effective": effective, "delai_requis": delai_requis, "recu": recu_max, "seuil": seuil}
	if recu_max < seuil:
		return {"statut": "hors_de_portee", "effective": effective, "delai_requis": delai_requis, "recu": recu_max, "seuil": seuil}
	if exposition_actuelle <= 0.0:
		return {"statut": "intact", "effective": effective, "delai_requis": delai_requis, "recu": recu_max, "seuil": seuil}
	return {"statut": "expose", "effective": effective, "delai_requis": delai_requis, "recu": recu_max, "seuil": seuil}

# ---- Affichage et console, PURS -- lisent un diagnostic deja calcule,
# ne recalculent jamais une valeur de Propagation/EtatEffectif.

static func _teinte_pour_diagnostic(diag: Dictionary, exposition_actuelle: float) -> Color:
	match diag.statut:
		"en_feu":
			return Color(0.75, 0.1, 0.05)
		"hors_de_portee":
			return Color(0.25, 0.35, 0.55)
		"expose":
			var ratio: float = _ratio_exposition(exposition_actuelle, diag.delai_requis)
			return Color(0.6 + 0.3 * ratio, 0.35 * (1.0 - ratio), 0.05)
		_:
			return Color(0.5, 0.5, 0.5)

static func _ratio_exposition(exposition: float, delai_requis: float) -> float:
	if delai_requis <= 0.0:
		return 0.0
	return clamp(exposition / delai_requis, 0.0, 1.0)

static func _texte_composition(composition: Array) -> String:
	var morceaux: Array = []
	for element in composition:
		morceaux.append("%.1f %s" % [float(element.get("volume", 0.0)), String(element.get("materiau", "?"))])
	return " + ".join(morceaux)

static func _texte_statut(diag: Dictionary) -> String:
	match diag.statut:
		"intact":
			return "INTACT"
		"expose":
			return "EXPOSE"
		"en_feu":
			return "EN FEU"
		"hors_de_portee":
			return "HORS DE PORTEE"
		_:
			return "?"

# temps_ecoule_ignition : capture par l'appelant AU TICK de l'allumage,
# meme patron que banc_inflammabilite.gd -- jamais recalcule ici. Ignore
# sur toute branche autre que "en_feu".
static func _texte_label(id: String, composition_texte: String, diag: Dictionary, temps_ecoule_ignition: float) -> String:
	var delai_texte: String = "%.2fs" % diag.delai_requis
	var derniere_ligne: String = ("temps_mis=%.2fs" % temps_ecoule_ignition) if diag.statut == "en_feu" else ""
	return "%s\n%s\nrecu=%.2f / seuil=%.2f\ninflammabilite_effective=%.2f\ndelai_requis=%s\n%s\n%s" % [
		id, composition_texte, diag.recu, diag.seuil, diag.effective, delai_texte, _texte_statut(diag), derniere_ligne
	]

static func _evenement(diag: Dictionary) -> String:
	match diag.statut:
		"intact":
			return "intact, pas encore expose"
		"expose":
			return "expose, en accumulation vers %.2fs" % diag.delai_requis
		"en_feu":
			return "ALLUMAGE"
		"hors_de_portee":
			return "hors de portee (recu %.2f < seuil %.2f)" % [diag.recu, diag.seuil]
		_:
			return "?"

static func _ligne_log(t: float, id: String, diag: Dictionary, exposition_actuelle: float, temps_ecoule_ignition: float) -> String:
	var exposition_affichee: float = temps_ecoule_ignition if diag.statut == "en_feu" else exposition_actuelle
	return "t=%.1fs %s : recu=%.2f seuil=%.2f exposition=%.2fs -> %s" % [
		t, id, diag.recu, diag.seuil, exposition_affichee, _evenement(diag)
	]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_cible(objet: Dictionary) -> void:
	var id: String = objet.id
	var centre := Vector2(objet.position.x, objet.position.y)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.color = Color(0.2, 0.2, 0.2)
	fond.size = Vector2(TAILLE, HAUTEUR_BARRE)
	fond.position = centre + Vector2(-TAILLE / 2.0, TAILLE / 2.0 + 6.0)
	add_child(fond)
	_barres_fond[id] = fond

	var rempli := ColorRect.new()
	rempli.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rempli.color = Color(0.9, 0.7, 0.1)
	rempli.size = Vector2(0.0, HAUTEUR_BARRE)
	rempli.position = fond.position
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0 + 20.0, TAILLE / 2.0 + 130.0)
	add_child(label)
	_labels[id] = label

func _creer_rendu_feu(feu: Dictionary) -> void:
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.color = Color(0.95, 0.45, 0.05)
	noeud.size = Vector2(TAILLE_FEU, TAILLE_FEU)
	noeud.position = Vector2(feu.position.x, feu.position.y) - noeud.size / 2.0
	add_child(noeud)

	var label := Label.new()
	label.position = noeud.position - Vector2(0.0, 24.0)
	label.text = feu.id
	add_child(label)

func _poser_camera() -> void:
	var min_x := INF
	var max_x := -INF
	for objet in _monde:
		min_x = minf(min_x, objet.position.x)
		max_x = maxf(max_x, objet.position.x)
	var centre_x := (min_x + max_x) / 2.0 if _monde.size() > 0 else 0.0
	var camera := Camera2D.new()
	camera.position = Vector2(centre_x, 450.0)
	camera.zoom = Vector2(0.4, 0.4)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
