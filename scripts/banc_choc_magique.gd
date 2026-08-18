extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_choc_magique.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Existe pour VOIR resistance_impact se fracturer par un CHOC
# MAGIQUE, TROISIEME chemin vers l'etat "fracture" apres le choc mecanique
# (scripts/banc_fracture.gd) et le son intense (scripts/banc_fracture_sonore.gd).
# Chantier « resistance_impact pour le choc magique »,
# audit_colonnes_chimique_nucleaire_magie_prealable.md (colonne energie
# magique #5 : « un TROISIEME seuil_propriete: resistance_impact dans
# data/seuils_etat.json apres fracture/fracture_sonore, meme patron deja
# prouve deux fois »).
#
# AUCUN MECANISME DU COEUR TOUCHE : frappe.gd/seuil_etat.gd/etat_effectif.gd/
# produit.gd/objet.gd restent inchanges. Ce fichier COMPOSE trois patrons
# deja fermes, jamais reecrits :
# - Frappe.selectionner/frapper (INCHANGE, voir banc_foudre.gd/banc_fracture.gd)
#   -- QUI est frappe et QUEL degat instantane s'applique. CRITERE DE
#   SELECTION TRANCHE PAR YAEL (question posee avant d'ecrire, voir
#   audit_colonnes_chimique_nucleaire_magie_prealable.md) : sensibilite_magique
#   SEULE (source "materiau"), jamais une pondération par distance dans le
#   score compose -- la distance reste le filtre de portee DEJA EXISTANT de
#   Frappe.selectionner (rayon/Portee.en_portee), jamais une deuxieme source
#   ajoutee a frappe.gd:_score (qui exigerait de toucher le coeur, interdit
#   par ce chantier).
# - frappe.gd NE MONTE AUCUNE PROPRIETE (il ne fait que decrementer une
#   reserve nommee, bornee a zero) -- c'est CE FICHIER, juste apres chaque
#   Frappe.frapper, qui ecrit lui-meme `proprietes.choc_magique_cumule +=
#   degats` sur la cible, meme geste que "degats_impact_cumules" dans
#   banc_fracture.gd.
# - SeuilEtat.avancer (INCHANGE) -- compare choc_magique_cumule a
#   resistance_impact (seuil_propriete, fusionnee a la fabrication) via une
#   TROISIEME entree de data/seuils_etat.json ('choc_magique'), qui pose le
#   MEME etat 'fracture' que les entrees mecanique et sonore -- coexistence
#   documentee dans seuil_etat.gd (memoire PAR ENTREE, voir en-tete de ce
#   fichier). Catalogue PARTAGE data/seuils_etat.json passe TEL QUEL.
# - Produit.transformer (INCHANGE, meme patron que banc_fracture.gd/
#   banc_fracture_sonore.gd) -- appele PAR CE FICHIER, jamais par
#   seuil_etat.gd, UNIQUEMENT si l'objet fraichement fracture porte une
#   fragilite superieure a config.seuil_fragilite_eclats : verre_demo (0.9)
#   se transforme toujours en eclats_verre, bois (0.3) et fer (0.2) restent
#   seuls poses (deformation sans debris, jamais transformes).
#
# SORT TOGGLABLE, BISTABLE CONTINU (TRANCHE PAR YAEL, question posee avant
# d'ecrire) -- meme geste que banc_fracture_sonore.gd:_source_active : un
# clic gauche bascule _sort_actif. PENDANT qu'il est actif, une frappe se
# declenche automatiquement toutes les "intervalle_frappe" secondes -- JAMAIS
# a chaque frame : frappe.gd:frapper applique une quantite degats PONCTUELLE,
# "jamais un taux" (voir frappe.gd, en-tete de frapper()) -- l'appeler a
# chaque tick de _process aurait detourne cette semantique. La CADENCE (pas
# le degat) est donc le seul mecanisme framerate-independant introduit ici :
# un accumulateur de temps ecoule compare a un seuil fixe, meme idiome que
# banc_fracture_sonore.gd:_dernier_rapport/intervalle_print (la, utilise
# seulement pour throttler l'affichage console -- ici, reutilise pour
# declencher la frappe elle-meme).
#
# TROIS CASTERS INDEPENDANTS, un par cible, jamais un seul caster global
# partage entre les trois (voir data/banc_choc_magique.json, en-tete) :
# chaque appel a Frappe.selectionner part de la POSITION DE SA PROPRE CIBLE
# (avancer_frappes ci-dessous), avec un "rayon_frappe" petit devant
# l'espacement des trois objets -- Frappe.selectionner ne voit donc jamais
# qu'UN SEUL candidat frappable par appel. Necessaire pour que les trois
# cibles progressent EN PARALLELE (meme discipline que
# banc_fracture_sonore.gd, ou les trois materiaux recoivent la MEME
# exposition) plutot qu'un seul vainqueur au score (le plus sensible a la
# magie) qui monopoliserait toutes les frappes et laisserait les deux autres
# cibles intactes indefiniment.
#
# LA RESERVE "integrite" (par objet, {reserve, cout_base: 0.0,
# surcout_action: 0.0}) N'EST JAMAIS AVANCEE PAR depense.gd -- exactement
# comme banc_fracture.gd, Frappe.frapper l'ecrit directement a chaque
# frappe ; elle ne decide jamais la fracture (seul choc_magique_cumule vs
# resistance_impact le fait), elle sert seulement a exclure un objet deja
# detruit des cibles futures (objets_frappables, meme fonction que
# banc_fracture.gd, recopiee ICI -- chaque banc porte sa propre copie,
# jamais un import croise entre bancs).
#
# CE QU'ON DOIT VOIR : trois objets fixes -- verre_0 (verre_demo,
# resistance_impact 1.0), bois_0 (4.0), fer_0 (8.0), espaces de 250 unites.
# Un clic gauche ACTIVE le sort (label "sort : actif") : toutes les
# "intervalle_frappe" secondes, chaque cible encaisse un coup magique
# instantane, son label affiche resistance_impact/sensibilite_magique/
# choc_magique_cumule/etat, sa teinte vire progressivement vers le rouge.
# verre_0 fracture des le premier coup et se transforme aussitot en une
# grappe d'eclats (couleur distincte) ; bois_0 fracture apres le troisieme
# coup, deforme sans transformation ; fer_0 apres le sixieme, deforme sans
# transformation -- ordre strict qui reproduit resistance_impact (1.0 < 4.0
# < 8.0). Un second clic COUPE le sort (label "sort : coupe"), plus aucune
# frappe ne se declenche, l'etat reste fige.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees/catalogues partages et
#   fabrique les trois objets (Objet.fabriquer, INCHANGE). _unhandled_input
#   BASCULE le sort au clic gauche (jamais un choc positionne). _process
#   avance l'horloge, declenche une frappe+verif de fracture toutes les
#   intervalle_frappe secondes tant que le sort est actif, redessine.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_choc_magique.gd) : fabriquer_objets/objets_frappables/
#   avancer_frappes/avancer_fracture, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Frappe = preload("res://scripts/frappe.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Produit = preload("res://scripts/produit.gd")

const TAILLE := 70.0
const TAILLE_POLICE_LABEL := 13
const COULEUR_ECLATS := Color(0.75, 0.85, 0.9)

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _proprietes_immuables: Array = []
var _objet_physique: Dictionary = {}
var _catalogue_seuils_etat: Dictionary = {}
var _etats: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _transformations: Dictionary = {}
var _sort_actif: bool = false
var _temps_depuis_frappe: float = 0.0
var _objets: Array = []
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _fracture_avant: Dictionary = {}
var _transforme_avant: Dictionary = {}
var _label_sort: Label
var _camera: Camera2D
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_choc_magique.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_proprietes_immuables = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	_objet_physique = _charger_json("res://data/types.json").get("objet_physique", {})
	_catalogue_seuils_etat = _charger_json("res://data/seuils_etat.json")
	_etats = _charger_json("res://data/etats.json")
	_catalogue_types = _charger_json("res://data/types.json")
	_transformations = _charger_json("res://data/transformations.json").get("transformations", {})

	_objets = fabriquer_objets(_config.get("objets", []), _objet_physique, _materiaux, _proprietes_immuables, _config.nom_reserve_integrite, _config.reserve_integrite_defaut)

	for objet in _objets:
		_fracture_avant[objet.id] = false
		_transforme_avant[objet.id] = false
		_creer_rendu_objet(objet)
	_creer_label_sort()
	_poser_camera()
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_sort_actif = not _sort_actif
		_temps_depuis_frappe = 0.0
		print(_ligne_toggle(_temps, _sort_actif))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta

	if _sort_actif:
		_temps_depuis_frappe += delta
		if _temps_depuis_frappe >= _config.intervalle_frappe:
			_temps_depuis_frappe = 0.0
			var diagnostics := avancer_frappes(_objets, _config.rayon_frappe, _config.criteres, _materiaux, _config.degats, _config.nom_reserve_integrite)
			for diag in diagnostics:
				print(_ligne_frappe(_temps, diag))

			var resultat := avancer_fracture(_objets, _catalogue_seuils_etat, _transformations, _catalogue_types, _materiaux, _config.seuil_fragilite_eclats)
			for id in resultat.bascules:
				if _fracture_avant.get(id, false):
					continue
				_fracture_avant[id] = true
				print(_ligne_fracture(_temps, id, _objet_par_id(id), _etats))
			for id in resultat.transformes:
				_transforme_avant[id] = true
				print(_ligne_transforme(_temps, id, _objet_par_id(id)))

	_rafraichir_tout()

func _objet_par_id(id: String) -> Dictionary:
	for objet in _objets:
		if objet.id == id:
			return objet
	return {}

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		_noeuds[id].color = _teinte(objet, _transforme_avant.get(id, false), _fracture_avant.get(id, false))
		_labels[id].text = _texte_label(objet)
	_label_sort.text = "sort : %s" % ("actif" if _sort_actif else "coupe")

# ---- Fonctions PURES, testables headless (voir test_banc_choc_magique.gd) ----

# Construit les objets via Objet.fabriquer (composition fusionnee -- meme
# patron que banc_fracture.gd, "objet_physique" fusionne). Ajoute A LA MAIN
# (Objet.fabriquer ne les connait pas) : la reserve "integrite" (patron
# banc_fracture.gd), "choc_magique_cumule" (0.0, la grandeur que
# scripts/seuil_etat.gd va comparer -- SANS elle, proprietes.has() rendrait
# faux et l'entree "choc_magique" ne se declencherait jamais, meme raison
# que "degats_impact_cumules"/"intensite_sonore_cumulee"), "etats_actifs"
# (Array vide, structurelle pour seuil_etat.gd/etat_effectif.gd) et
# "transformation_fracture" (pointeur DATA vers data/transformations.json,
# vide ou nomme selon la declaration -- jamais un nom de materiau en dur ici).
static func fabriquer_objets(declarations: Array, objet_physique: Dictionary, materiaux: Dictionary, proprietes_immuables: Array, nom_reserve_integrite: String, reserve_integrite_defaut: Dictionary) -> Array:
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
		objet.proprietes["choc_magique_cumule"] = 0.0
		objet.proprietes["etats_actifs"] = []
		objet.proprietes["transformation_fracture"] = decl.get("transformation_fracture", "")
		objets.append(objet)
	return objets

# Un objet DEJA DETRUIT (reserve <= 0.0) n'est plus jamais candidat -- meme
# fonction que banc_fracture.gd, recopiee (frappe.gd ne connait aucune
# reserve nommee dans son contrat).
static func objets_frappables(objets: Array, nom_reserve: String) -> Array:
	var vivants: Array = []
	for objet in objets:
		var canal: Dictionary = objet.proprietes.get("reserves", {}).get(nom_reserve, {})
		if canal.get("reserve", 0.0) > 0.0:
			vivants.append(objet)
	return vivants

# TROIS casters independants, un par cible (voir en-tete de ce fichier) :
# pour CHAQUE objet de "objets", un appel a Frappe.selectionner PARTANT DE
# LA POSITION DE CET OBJET, avec "rayon_frappe" (petit devant l'espacement
# reel des cibles) -- ne voit donc jamais qu'UN SEUL candidat frappable
# (lui-meme, s'il est encore frappable). "criteres" reste passe TEL QUEL a
# Frappe.selectionner (sensibilite_magique, source "materiau") -- neutre ici
# (un seul candidat par appel), mais c'est bien lui qui trancherait si un
# jour plusieurs cibles entraient dans le meme rayon. Rend un Array de
# { cible, degats, cumul_apres } -- un element par caster qui a reellement
# touche une cible frappable ce passage (un caster dont la cible est deja
# detruite ne rend rien).
static func avancer_frappes(objets: Array, rayon_frappe: float, criteres: Array, materiaux: Dictionary, degats: float, nom_reserve_integrite: String) -> Array:
	var frappables := objets_frappables(objets, nom_reserve_integrite)
	var diagnostics: Array = []
	for objet in objets:
		var cible := Frappe.selectionner(frappables, objet.position, rayon_frappe, criteres, materiaux)
		if cible.is_empty():
			continue
		Frappe.frapper(cible, degats, nom_reserve_integrite)
		var cumul: float = cible.proprietes.get("choc_magique_cumule", 0.0) + degats
		cible.proprietes["choc_magique_cumule"] = cumul
		diagnostics.append({"cible": cible, "degats": degats, "cumul_apres": cumul})
	return diagnostics

# Verifie le franchissement de "fracture" (SeuilEtat.avancer, INCHANGE, via
# data/seuils_etat.json:choc_magique -- compare choc_magique_cumule a
# resistance_impact) sur TOUT le monde, puis, pour chaque id fraichement
# fracture, decide via "fragilite" (lue SEULE par ce fichier, aucun
# mecanisme du coeur ne la connait) si l'objet produit des eclats
# (Produit.transformer, INCHANGE) ou se contente de rester fracture, deforme
# sans transformation. Rend { bascules, transformes } -- memes formes que
# celles deja rendues par SeuilEtat.avancer, jamais recalculees ici. MEME
# FONCTION, RECOPIEE DEPUIS banc_fracture.gd/banc_fracture_sonore.gd (chaque
# banc porte sa propre copie, jamais un import croise entre bancs).
static func avancer_fracture(objets: Array, catalogue_seuils_etat: Dictionary, transformations: Dictionary, table_types: Dictionary, materiaux: Dictionary, seuil_fragilite_eclats: float) -> Dictionary:
	var bascules := SeuilEtat.avancer(objets, catalogue_seuils_etat)
	var transformes: Array = []
	for objet in objets:
		if not bascules.has(objet.id):
			continue
		if not objet.proprietes.get("etats_actifs", []).has("fracture"):
			continue
		var fragilite: float = objet.proprietes.get("fragilite", 0.0)
		if fragilite < seuil_fragilite_eclats:
			continue
		var nom_transformation: String = objet.proprietes.get("transformation_fracture", "")
		if nom_transformation.is_empty():
			continue
		var config_produire: Dictionary = transformations.get(nom_transformation, {}).get("a_zero", {}).get("produire", {})
		var nouvelles_proprietes: Dictionary = Produit.transformer(objet.proprietes, config_produire, table_types, materiaux)
		if nouvelles_proprietes.is_empty():
			continue
		objet.proprietes.clear()
		objet.proprietes.merge(nouvelles_proprietes, true)
		transformes.append(objet.id)
	return {"bascules": bascules, "transformes": transformes}

static func _teinte(objet: Dictionary, transforme: bool, fracture: bool) -> Color:
	if transforme:
		return COULEUR_ECLATS
	if fracture:
		return Color(0.7, 0.2, 0.15)
	var cumul: float = objet.proprietes.get("choc_magique_cumule", 0.0)
	var resistance: float = max(objet.proprietes.get("resistance_impact", 0.0), 0.0001)
	var ratio: float = clamp(cumul / resistance, 0.0, 1.0)
	return Color(0.55, 0.55, 0.6).lerp(Color(0.6, 0.35, 0.85), ratio)

static func _texte_label(objet: Dictionary) -> String:
	var proprietes: Dictionary = objet.proprietes
	if not proprietes.has("resistance_impact"):
		return "%s\n(transforme)\nmasse=%.2f" % [objet.id, proprietes.get("masse", 0.0)]
	var fracture: bool = proprietes.get("etats_actifs", []).has("fracture")
	return "%s\nresistance_impact=%.2f\nsensibilite_magique=%.2f\nchoc_magique_cumule=%.2f\netat=%s" % [
		objet.id,
		proprietes.get("resistance_impact", 0.0),
		proprietes.get("sensibilite_magique", 0.0),
		proprietes.get("choc_magique_cumule", 0.0),
		"fracture" if fracture else "intact",
	]

static func _ligne_toggle(t: float, actif: bool) -> String:
	return "t=%.1fs SORT : %s" % [t, "active" if actif else "coupe"]

static func _ligne_frappe(t: float, diag: Dictionary) -> String:
	return "t=%.1fs CHOC MAGIQUE : %s frappe (degats=%.2f, cumul=%.2f)" % [t, diag.cible.id, diag.degats, diag.cumul_apres]

static func _ligne_fracture(t: float, id: String, objet: Dictionary, etats: Dictionary) -> String:
	var durete_eff := EtatEffectif.valeur(objet, "durete", etats)
	var compression_eff := EtatEffectif.valeur(objet, "resistance_compression", etats)
	return "t=%.1fs %s : FRACTURE PAR CHOC MAGIQUE (durete effective -> %.2f, resistance_compression effective -> %.2f)" % [t, id, durete_eff, compression_eff]

static func _ligne_transforme(t: float, id: String, objet: Dictionary) -> String:
	return "t=%.1fs %s : reduit en eclats (masse=%.2f)" % [t, id, objet.proprietes.get("masse", 0.0)]

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

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 90.0)
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	_labels[id] = label

func _creer_label_sort() -> void:
	_label_sort = Label.new()
	_label_sort.position = Vector2(-100.0, -220.0)
	_label_sort.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL + 4)
	add_child(_label_sort)

func _poser_camera() -> void:
	var decl_camera: Dictionary = _config.get("camera", {})
	var pos: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	_camera = Camera2D.new()
	_camera.position = Vector2(pos[0], pos[1])
	_camera.zoom = Vector2(decl_camera.get("zoom", 0.5), decl_camera.get("zoom", 0.5))
	_camera.enabled = true
	add_child(_camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
