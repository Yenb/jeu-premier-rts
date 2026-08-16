extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_inflammabilite.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). PREMIERE demonstration
# reelle du chantier "feu -- inflammabilite effective" : objet.gd
# (proprietes_immuables, fusion generique a la fabrication) et
# propagation.gd (delai_ignition, gating par intensite effective) jouant
# ENSEMBLE sur des objets Orion reels pour la premiere fois. Noms de
# domaine reels (inflammable/brule/inflammabilite/mouille) -- exception
# documentee (CLAUDE.md : "un banc jetable peut nommer une categorie pour
# poser une scene d'observation").
#
# JETABLE PAR DEFINITION : aucune regle de jeu ne doit vivre ici, seulement
# du cablage et de la lecture. Tout calcul de diagnostic est en fonctions
# STATIQUES testables (diagnostiquer/_teinte_pour_diagnostic/
# _ratio_exposition/_texte_composition/_texte_statut/_texte_label/
# _evenement/_ligne_log) -- _process ne fait qu'appeler Propagation.avancer
# (deja le mecanisme reel) puis LIRE son resultat, jamais recalculer une loi
# deja ecrite ailleurs (EtatEffectif.resoudre/valeur, Propagation.
# delai_ignition -- consommes, jamais reimplementes, meme doctrine que le
# chantier etat_effectif).
#
# CE QU'ON DOIT VOIR : un feu central (deja allume, aucun colon ne
# l'eteint jamais) expose en permanence quatre objets alignes, chacun
# affichant SANS INTERACTION : son nom, sa composition (materiau(x) +
# volume(s), et l'etat actif s'il y en a un), son inflammabilite EFFECTIVE
# (EtatEffectif.valeur), son delai requis calcule (Propagation.
# delai_ignition -- "jamais" UNIQUEMENT si la chose ne peut structurellement
# jamais s'enflammer, JAMAIS pour une chose deja en feu, voir DEUX SENS DE
# -1.0 plus bas), son statut (INTACT/EXPOSE/EN FEU/BLOQUE) et une barre dont
# le remplissage suit exposition/delai_requis. La TEINTE du carre encode le
# meme statut sans qu'il faille lire le texte : orange qui vire au rouge a
# mesure que l'exposition approche le delai (bois_vif, vite ; melange,
# lentement -- ecart visible sans console), rouge sature une fois EN FEU,
# BLEU fixe si bloque sous le seuil (fer_inerte), CYAN fixe si bloque par un
# etat qui ecrase (bois_mouille) -- deux couleurs DIFFERENTES pour deux
# raisons differentes de ne jamais s'enflammer, distinguables a l'oeil sans
# lire aucun texte. La console imprime une ligne A CHAQUE CHANGEMENT DE
# STATUT d'un objet (jamais par frame) : objet, inflammabilite effective,
# exposition (voir DEUX SENS ci-dessous), et ce qui a decide (expose/
# ALLUMAGE/seuil non atteint/etat qui ecrase).
#
# DEUX SENS DE -1.0, SEPARES (audit en lecture seule, session precedente --
# corrige ici) : Propagation.delai_ignition rend -1.0 pour dire "ne peut
# JAMAIS s'enflammer" (bloque_seuil/bloque_etat, sens correct et inchange).
# Ce fichier NE REUTILISE PLUS cette meme valeur pour dire "vient de
# s'enflammer" -- diagnostiquer() appelle desormais delai_ignition() SUR LA
# BRANCHE en_feu AUSSI, qui rend le VRAI delai requis (fini, positif),
# jamais -1.0, pour une chose deja "brule". "jamais" a l'ecran ne signifie
# donc plus jamais qu'une seule chose.
#
# EXPOSITION FIGEE A L'ALLUMAGE (meme correction) : propagation.gd:avancer
# remet exposition[id] a 0.0 AU TICK MEME de l'allumage (comportement
# VOULU et teste, jamais touche ici -- voir test_propagation_chantier.gd),
# puis saute la chose tant qu'elle brule : la valeur VIVE de _exposition
# reste donc figee a 0.0 pour toujours apres l'ignition -- l'afficher telle
# quelle a cote de "EN FEU" mentirait ("pris feu instantanement"). _process
# capture, AU TICK OU Propagation.avancer rend l'id dans sa liste
# "nouvellement enflammees", le temps REELLEMENT ecoule (exposition juste
# avant cet appel + delta -- exactement la valeur que avancer() a comparee
# en interne au seuil, jamais recalculee ni devinee) dans
# _temps_ecoule_ignition[id], figee pour toujours ensuite. Le Label et la
# ligne de console d'un objet EN FEU affichent CE nombre ("temps_mis"),
# jamais l'exposition vive remise a zero.
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

var _monde: Array = []
var _objets: Array = []
var _textes_composition: Dictionary = {}
var _dernier_statut: Dictionary = {}
var _exposition: Dictionary = {}
var _temps_ecoule_ignition: Dictionary = {}
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _menaces: Dictionary = {}
var _etats: Dictionary = {}
var _intensite: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_inflammabilite.json")
	_menaces = _charger_json("res://data/menaces.json")
	_etats = _charger_json("res://data/etats.json")
	_intensite = _charger_json("res://data/intensite_propagation.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	var delai_base: float = donnees.get("delai_propagation_base", 1.0)
	var portee: float = donnees.get("portee_propagation", 900.0)

	var decl_feu: Dictionary = donnees.get("feu", {})
	var pos_feu: Array = decl_feu.get("position", [0.0, 0.0, 0.0])
	var feu := {
		"id": "feu_central",
		"position": Vector3(pos_feu[0], pos_feu[1], pos_feu[2]),
		"proprietes": {"brule": true},
	}
	_monde.append(feu)

	var declarations: Array = donnees.get("objets", [])
	var catalogue_types: Dictionary = {}
	for decl in declarations:
		catalogue_types[decl.id] = {
			VULNERABILITE: true,
			"portee_propagation": portee,
			"delai_propagation": delai_base,
			"composition": decl.composition,
		}

	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue_types, materiaux, proprietes_immuables)
		objet.proprietes["etats_actifs"] = decl.get("etats_actifs", []).duplicate()
		_monde.append(objet)
		_objets.append(objet)
		_exposition[decl.id] = 0.0
		_textes_composition[decl.id] = _texte_composition(decl.composition, objet.proprietes.etats_actifs)
		_creer_rendu_objet(objet)

	_creer_rendu_feu(feu)
	_poser_camera()
	_diagnostiquer_tout(0.0, true)

func _process(delta: float) -> void:
	_temps += delta
	var avant_ce_pas: Dictionary = {}
	for objet in _objets:
		avant_ce_pas[objet.id] = _exposition.get(objet.id, 0.0)
	var enflammees: Array = Propagation.avancer(_monde, _menaces, _exposition, delta, {}, _intensite, _etats)
	for id in enflammees:
		_temps_ecoule_ignition[id] = avant_ce_pas.get(id, 0.0) + delta
	_diagnostiquer_tout(_temps, false)

func _diagnostiquer_tout(t: float, forcer_log: bool) -> void:
	var seuil: float = _intensite.get("seuil_ignition", 0.0)
	for objet in _objets:
		var id: String = objet.id
		var exposition_actuelle: float = _exposition.get(id, 0.0)
		var diag: Dictionary = diagnostiquer(objet, exposition_actuelle, VULNERABILITE, _menaces, _intensite, _etats)
		var temps_mis: float = _temps_ecoule_ignition.get(id, 0.0)
		if forcer_log or diag.statut != _dernier_statut.get(id, ""):
			print(_ligne_log(t, id, diag, exposition_actuelle, seuil, temps_mis))
			_dernier_statut[id] = diag.statut
		_noeuds[id].color = _teinte_pour_diagnostic(diag, exposition_actuelle)
		var exposition_pour_barre: float = temps_mis if diag.statut == "en_feu" else exposition_actuelle
		var ratio := _ratio_exposition(exposition_pour_barre, diag.delai_requis)
		var fond: ColorRect = _barres_fond[id]
		_barres_remplies[id].size.x = fond.size.x * ratio
		_labels[id].text = _texte_label(id, _textes_composition[id], diag, exposition_actuelle, seuil, temps_mis)

# ---- Diagnostic, PUR : compose EtatEffectif.valeur/resoudre et
# Propagation.delai_ignition (deja publics, deja testes) -- ne reimplemente
# JAMAIS leur loi, seulement leur lecture. Rend { statut: "intact" |
# "expose" | "en_feu" | "bloque_seuil" | "bloque_etat", effective: float,
# delai_requis: float, raison_etat: String (nom de l'etat ecraseur, vide
# sauf statut "bloque_etat") }.
#
# delai_requis vaut -1.0 UNIQUEMENT sur "bloque_seuil"/"bloque_etat" (ne
# peut JAMAIS s'enflammer). Sur "en_feu", delai_ignition() est appelee
# EXACTEMENT comme sur les autres branches -- elle ne regarde jamais
# "brule", seulement composition/etat courants -- et rend le VRAI delai
# que la chose a requis, jamais -1.0 : les deux sens de la sentinelle
# (bloque pour toujours / deja enflamme) ne partagent plus la meme valeur.
static func diagnostiquer(
	chose: Dictionary,
	exposition_actuelle: float,
	vulnerabilite: String,
	menaces: Dictionary,
	intensite: Dictionary,
	etats: Dictionary,
) -> Dictionary:
	var propriete_intensite: String = intensite.get("propriete_intensite", "")
	var menace: String = menaces.get(vulnerabilite, "")
	var effective: float = EtatEffectif.valeur(chose, propriete_intensite, etats)
	var delai_requis: float = Propagation.delai_ignition(chose, intensite, etats)
	if chose.proprietes.get(menace, false):
		return {"statut": "en_feu", "effective": effective, "delai_requis": delai_requis, "raison_etat": ""}
	if delai_requis < 0.0:
		var resolution: Dictionary = EtatEffectif.resoudre(chose, propriete_intensite, etats)
		if resolution.mode == "ecraser":
			return {"statut": "bloque_etat", "effective": effective, "delai_requis": delai_requis, "raison_etat": resolution.gagnants[0]}
		return {"statut": "bloque_seuil", "effective": effective, "delai_requis": delai_requis, "raison_etat": ""}
	if exposition_actuelle <= 0.0:
		return {"statut": "intact", "effective": effective, "delai_requis": delai_requis, "raison_etat": ""}
	return {"statut": "expose", "effective": effective, "delai_requis": delai_requis, "raison_etat": ""}

# ---- Affichage et console, PURS -- lisent un diagnostic deja calcule,
# ne recalculent jamais une valeur d'EtatEffectif/Propagation.

static func _teinte_pour_diagnostic(diag: Dictionary, exposition_actuelle: float) -> Color:
	match diag.statut:
		"en_feu":
			return Color(0.75, 0.1, 0.05)
		"bloque_seuil":
			return Color(0.25, 0.35, 0.55)
		"bloque_etat":
			return Color(0.1, 0.55, 0.6)
		"expose":
			var ratio: float = _ratio_exposition(exposition_actuelle, diag.delai_requis)
			return Color(0.6 + 0.3 * ratio, 0.35 * (1.0 - ratio), 0.05)
		_:
			return Color(0.5, 0.5, 0.5)

static func _ratio_exposition(exposition: float, delai_requis: float) -> float:
	if delai_requis <= 0.0:
		return 0.0
	return clamp(exposition / delai_requis, 0.0, 1.0)

static func _texte_composition(composition: Array, etats_actifs: Array) -> String:
	var morceaux: Array = []
	for element in composition:
		morceaux.append("%.1f %s" % [float(element.get("volume", 0.0)), String(element.get("materiau", "?"))])
	var texte: String = " + ".join(morceaux)
	if not etats_actifs.is_empty():
		texte += " (%s)" % ", ".join(etats_actifs)
	return texte

static func _texte_statut(diag: Dictionary, seuil: float) -> String:
	match diag.statut:
		"intact":
			return "INTACT"
		"expose":
			return "EXPOSE"
		"en_feu":
			return "EN FEU"
		"bloque_seuil":
			return "BLOQUE (sous le seuil %.2f)" % seuil
		"bloque_etat":
			return "BLOQUE (etat '%s' ecrase)" % diag.raison_etat
		_:
			return "?"

# temps_ecoule_ignition : capture par l'appelant AU TICK de l'allumage
# (voir _process/DEUX SENS DE -1.0 en tete de fichier), jamais recalcule
# ici. Ignore sur toute branche autre que "en_feu" -- affiche l'exposition
# VIVE dans ce cas, seule valeur qui a un sens avant l'allumage.
static func _texte_label(id: String, composition_texte: String, diag: Dictionary, exposition_actuelle: float, seuil: float, temps_ecoule_ignition: float) -> String:
	var delai_texte: String = ("%.2fs" % diag.delai_requis) if diag.delai_requis >= 0.0 else "jamais"
	var derniere_ligne: String
	if diag.statut == "en_feu":
		derniere_ligne = "temps_mis=%.2fs" % temps_ecoule_ignition
	else:
		derniere_ligne = "exposition=%.2fs" % exposition_actuelle
	return "%s\n%s\ninflammabilite_effective=%.2f\ndelai_requis=%s\n%s\n%s" % [
		id, composition_texte, diag.effective, delai_texte, _texte_statut(diag, seuil), derniere_ligne
	]

static func _evenement(diag: Dictionary, seuil: float) -> String:
	match diag.statut:
		"intact":
			return "intact, pas encore expose"
		"expose":
			return "expose, en accumulation vers %.2fs" % diag.delai_requis
		"en_feu":
			return "ALLUMAGE"
		"bloque_seuil":
			return "seuil non atteint (effectif %.2f < seuil %.2f)" % [diag.effective, seuil]
		"bloque_etat":
			return "etat '%s' ecrase (effectif %.2f)" % [diag.raison_etat, diag.effective]
		_:
			return "?"

# temps_ecoule_ignition : voir _texte_label -- meme substitution, la ligne
# "en_feu" (ALLUMAGE) porte le temps REELLEMENT mis, jamais l'exposition
# vive remise a zero par propagation.gd au meme tick.
static func _ligne_log(t: float, id: String, diag: Dictionary, exposition_actuelle: float, seuil: float, temps_ecoule_ignition: float) -> String:
	var exposition_affichee: float = temps_ecoule_ignition if diag.statut == "en_feu" else exposition_actuelle
	return "t=%.1fs %s : effective=%.2f exposition=%.2fs -> %s" % [
		t, id, diag.effective, exposition_affichee, _evenement(diag, seuil)
	]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_objet(objet: Dictionary) -> void:
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
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 140.0)
	add_child(label)
	_labels[id] = label

func _creer_rendu_feu(feu: Dictionary) -> void:
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.color = Color(0.95, 0.45, 0.05)
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.position = Vector2(feu.position.x, feu.position.y) - noeud.size / 2.0
	add_child(noeud)

	var label := Label.new()
	label.position = noeud.position - Vector2(0.0, 24.0)
	label.text = "feu_central"
	add_child(label)

func _poser_camera() -> void:
	var centre_x := 0.0
	for objet in _objets:
		centre_x += objet.position.x
	if not _objets.is_empty():
		centre_x /= _objets.size()
	var camera := Camera2D.new()
	camera.position = Vector2(centre_x, 320.0)
	camera.zoom = Vector2(0.75, 0.75)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
