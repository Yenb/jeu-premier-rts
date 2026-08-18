extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_resonance.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « resonance -- un materiau resonnant amplifie le son » :
# un objet qui recoit du son le REEMET comme source sonore secondaire,
# force proportionnelle a son_recu * resonance (materiau, data/
# materiaux.json, fusionnee a la fabrication via data/
# proprietes_immuables_composition.json, meme patron que son_emis avant
# elle). Un colon a portee percoit alors la source originale ET les
# sources secondaires : le son total percu monte quand un objet resonnant
# (fer 0.6, bois 0.7) est present, reste quasi inchange avec un objet a
# faible resonance (pierre 0.2).
#
# AUCUN MECANISME DU COEUR TOUCHE : perception.gd/etat_effectif.gd/
# charge.gd/lumiere.gd/temperature.gd/frappe.gd/seuil_etat.gd restent
# inchanges, banc_son.gd n'est pas touche non plus. Ce fichier COMPOSE :
# - Objet.fabriquer (INCHANGE) -- trois objets resonnants REELS (fer/bois/
#   pierre, data/materiaux.json), composant "objet_physique" et fusionnant
#   "resonance" comme n'importe quelle autre propriete immuable (meme
#   patron que banc_fracture_sonore.gd:fabriquer_objets pour "son_emis").
#   Leur propre "son_emis" fusionne (baseline d'emission intrinseque,
#   deja demontree par banc_son.gd) N'EST JAMAIS LU ICI -- sans rapport
#   avec la resonance, qui ne concerne QUE le son RECU puis REEMIS.
# - BancCommun.fabriquer_colon (INCHANGE) -- un colon "colon" (data/
#   types.json), canaux_config.ouie au defaut du type (portee 600.0,
#   seuil 0.0), aucune surcharge necessaire pour ce banc.
# - Portee.en_portee (INCHANGE) -- gate de son_recu, meme usage que
#   banc_fracture_sonore.gd:intensite_recue.
# - Monde/Perception.percevoir (INCHANGES) -- un Monde JETABLE, RECONSTRUIT
#   CHAQUE TICK (jamais le meme objet d'un tick a l'autre, aucune memoire),
#   qui ne contient QUE les sources actives CE TICK (source originale +
#   sources secondaires syntheticques construites par sources_resonantes) --
#   les trois objets resonnants eux-memes n'y entrent JAMAIS : ce sont des
#   recepteurs/reemetteurs, pas des choses que le colon percoit
#   directement par ce canal. Perception.percevoir isole ensuite ce que le
#   colon capte par le canal "ouie" precisement (captures_ouie, meme patron
#   que banc_son.gd -- fonction RECOPIEE ici, jamais un import croise entre
#   bancs, meme discipline que banc_fracture_sonore.gd le documente pour
#   avancer_fracture).
#
# SON_RECU (fonction PURE, coeur du chantier, RECOPIEE de
# banc_fracture_sonore.gd:intensite_recue -- MEME FORMULE que
# perception.gd:_percevoir_propagation_obstacles, jamais une seconde
# formule inventee) : intensite qu'un objet PASSIF (sans canal perceptif)
# recoit d'UNE source, attenuee lineairement par la distance, nulle hors
# du rayon d'emission physique de la source (Portee.en_portee) -- ce rayon
# est une propriete de la SOURCE (rayon_emission), jamais celle d'un
# quelconque auditeur (contrairement a canaux_config.ouie.portee, propre a
# une entite percevante).
#
# SOURCES_RESONANTES (fonction PURE, PROPRE A CE CHANTIER, meme idiome que
# banc_chaleur_emise.gd:sources_chaleur -- "une source PAR OBJET,
# RECONSTRUITE DU NEANT a chaque appel, jamais une memoire propre a la
# fonction") : pour chaque objet resonnant, calcule son_recu depuis la
# source originale PUIS son_reemis = son_recu * resonance (proprietes.
# resonance, FACULTATIVE, defaut 0.0 -- un materiau sans cette propriete,
# ou un objet qui ne recoit rien, point neutre legitime, jamais une
# alarme). Un objet dont le son reemis n'est pas strictement positif
# (source coupee, hors de rayon_emission, ou resonance 0.0) NE PRODUIT
# JAMAIS de source secondaire -- meme discipline que sources_chaleur pour
# un objet qui ne brule pas : la source disparait/n'existe pas, elle n'est
# jamais posee a force nulle.
#
# Toggle au clic gauche (_unhandled_input) coupe/active la source
# originale -- meme geste que banc_fracture_sonore.gd. Source coupee :
# sources_actives rend [] (CHEMIN MORT STRICT), donc aucune source
# secondaire ne peut exister non plus (son_recu de chaque objet resonnant
# retombe a 0.0 des que source_active est faux) -- "pas de son a
# amplifier" est une consequence directe de la gate, jamais un cas
# special ecrit a part.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge donnees/catalogues, fabrique la source,
#   les trois objets resonnants et le colon, cree le rendu.
#   _unhandled_input bascule la source. _process reconstruit les sources
#   actives et le Monde du tick, fait percevoir le colon, calcule le son
#   total, logue au CHANGEMENT seulement (jamais chaque frame, meme idiome
#   que banc_son.gd), redessine les labels.
# - Fonctions statiques (pures, testables headless, voir
#   scripts/test_banc_resonance.gd) : fabriquer_objets_resonnants/
#   son_recu/diagnostic_objet/sources_resonantes/sources_actives/
#   captures_ouie/ids_de/intensite_attenuee/son_total_percu, plus le texte
#   d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const Portee = preload("res://scripts/portee.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const TAILLE := 60.0
const TAILLE_SOURCE := 26.0
const TAILLE_POLICE_LABEL := 13

var _config: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _position_source: Vector3 = Vector3.ZERO
var _son_emis_source: float = 0.0
var _rayon_emission: float = 0.0
var _id_source: String = ""
var _source_active: bool = true
var _objets: Array = []
var _colon: Dictionary = {}
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_source: ColorRect
var _label_source: Label
var _camera: Camera2D
var _temps: float = 0.0
var _prochain_print := 0.0
var _entendus_avant: Array = []

func _ready() -> void:
	_config = _charger_json("res://data/banc_resonance.json")
	var materiaux: Dictionary = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var objet_physique: Dictionary = _charger_json("res://data/types.json").get("objet_physique", {})
	var catalogue_types: Dictionary = _charger_json("res://data/types.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")

	var decl_source: Dictionary = _config.source
	var pos_source: Array = decl_source.position
	_position_source = Vector3(pos_source[0], pos_source[1], pos_source[2])
	_son_emis_source = decl_source.son_emis
	_rayon_emission = decl_source.rayon_emission
	_id_source = decl_source.id

	_objets = fabriquer_objets_resonnants(_config.get("objets", []), objet_physique, materiaux, proprietes_immuables)
	_colon = BancCommun.fabriquer_colon("colon", "colon", _config.colon, catalogue_types)

	for objet in _objets:
		_creer_rendu(objet.id, objet.position, _couleur_de(objet.id))
	_creer_rendu("colon", _colon.position, _couleur_de("colon"))
	_creer_rendu_source()
	_poser_camera()

	_prochain_print = _config.get("intervalle_print", 2.0)
	print(_ligne_toggle(0.0, _source_active))
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_source_active = not _source_active
		print(_ligne_toggle(_temps, _source_active))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta

	if _temps >= _prochain_print:
		_prochain_print += _config.get("intervalle_print", 2.0)
		for objet in _objets:
			print(_ligne_rapport(_temps, objet, _diag(objet)))

	_rafraichir_tout()

func _diag(objet: Dictionary) -> Dictionary:
	return diagnostic_objet(objet, _source_active, _position_source, _son_emis_source, _rayon_emission)

# Recalcule TOUT depuis l'etat courant (source active/coupee, positions
# figees) et redessine -- appelee a chaque tick ET au toggle, jamais deux
# calculs paralleles qui pourraient diverger.
func _rafraichir_tout() -> void:
	for objet in _objets:
		_labels[objet.id].text = _texte_label_objet(objet, _diag(objet))

	var sources := sources_actives(_source_active, _id_source, _position_source, _son_emis_source, _rayon_emission, _objets)
	var monde_tick = BancCommun.monde_depuis([{"choses": sources, "type": "source_sonore"}])
	var entendus := captures_ouie(_colon, monde_tick, _catalogue_canaux)
	var ids_entendus := ids_de(entendus)
	ids_entendus.sort()
	if ids_entendus != _entendus_avant:
		_entendus_avant = ids_entendus
		print(_ligne_log(_temps, ids_entendus))

	var total := son_total_percu(_colon, sources, ids_entendus)
	_labels["colon"].text = _texte_label_colon(ids_entendus, total)

	var cle_couleur: String = "couleur_source_active" if _source_active else "couleur_source_inactive"
	var defaut: Array = [0.95, 0.85, 0.2] if _source_active else [0.35, 0.35, 0.35]
	var rgb: Array = _config.get(cle_couleur, defaut)
	_noeud_source.color = Color(rgb[0], rgb[1], rgb[2])
	_label_source.text = "source : %s" % ("active" if _source_active else "coupee")

# ---- Fonctions statiques, pures, testables ----

# Meme patron que banc_fracture_sonore.gd:fabriquer_objets -- trois objets
# resonnants REELS (composition fusionnee via Objet.fabriquer).
static func fabriquer_objets_resonnants(declarations: Array, objet_physique: Dictionary, materiaux: Dictionary, proprietes_immuables: Array) -> Array:
	var table: Dictionary = {"objet_physique": objet_physique}
	for decl in declarations:
		table[decl.id] = {"herite": ["objet_physique"], "composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), table, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objets.append(objet)
	return objets

# RECOPIEE de banc_fracture_sonore.gd:intensite_recue -- MEME FORMULE que
# perception.gd:_percevoir_propagation_obstacles (son_emis * (1.0 -
# distance/portee)), jamais une seconde formule. Hors du rayon d'emission
# de la source : 0.0, chemin mort -- un objet hors de portee ne recoit
# jamais rien, quelle que soit son_emis_source.
static func son_recu(position_objet: Vector3, position_source: Vector3, son_emis_source: float, rayon_emission: float) -> float:
	if not Portee.en_portee(position_source, position_objet, rayon_emission):
		return 0.0
	if rayon_emission <= 0.0:
		return 0.0
	var distance: float = position_source.distance_to(position_objet)
	return son_emis_source * (1.0 - distance / rayon_emission)

# Diagnostic complet d'UN objet resonnant, pour affichage ET pour
# sources_resonantes (meme calcul, jamais duplique). "resonance" facultative
# (defaut 0.0, materiau sans cette propriete -- point neutre legitime).
# source_active=false : son_recu/son_reemis retombent a 0.0 sans jamais
# appeler son_recu -- "pas de son a amplifier" quand la source est coupee.
static func diagnostic_objet(objet: Dictionary, source_active: bool, position_source: Vector3, son_emis_source: float, rayon_emission: float) -> Dictionary:
	var resonance: float = objet.proprietes.get("resonance", 0.0)
	var recu: float = son_recu(objet.position, position_source, son_emis_source, rayon_emission) if source_active else 0.0
	return {"resonance": resonance, "son_recu": recu, "son_reemis": recu * resonance}

# Coeur du chantier, meme idiome que banc_chaleur_emise.gd:sources_chaleur
# -- une source secondaire PAR OBJET dont le son reemis est strictement
# positif, RECONSTRUITE DU NEANT a chaque appel (aucune memoire propre a
# cette fonction). Un objet a resonance 0.0, ou hors de portee de la
# source, ou source coupee : AUCUNE source secondaire produite pour lui --
# jamais une source posee a force nulle.
static func sources_resonantes(objets_resonnants: Array, source_active: bool, position_source: Vector3, son_emis_source: float, rayon_emission: float) -> Array:
	var sources: Array = []
	for objet in objets_resonnants:
		var diag := diagnostic_objet(objet, source_active, position_source, son_emis_source, rayon_emission)
		if diag.son_reemis <= 0.0:
			continue
		sources.append({
			"id": "%s_reso" % objet.id,
			"position": objet.position,
			"proprietes": {"son_emis": diag.son_reemis},
		})
	return sources

# Point d'entree unique : la source originale (si active, meme id que la
# declaration) PUIS les sources secondaires -- source coupee, rend []
# (CHEMIN MORT STRICT), aucune source de quelque nature ne peut exister ce
# tick.
static func sources_actives(source_active: bool, id_source: String, position_source: Vector3, son_emis_source: float, rayon_emission: float, objets_resonnants: Array) -> Array:
	if not source_active:
		return []
	var sources: Array = [{"id": id_source, "position": position_source, "proprietes": {"son_emis": son_emis_source}}]
	sources.append_array(sources_resonantes(objets_resonnants, true, position_source, son_emis_source, rayon_emission))
	return sources

# RECOPIEE de banc_son.gd:captures_ouie -- parmi tout ce que
# Perception.percevoir rend, ne retient que les entrees captees par le
# canal "ouie" precisement.
static func captures_ouie(colon: Dictionary, monde, catalogue_canaux: Dictionary) -> Array:
	var perceptions: Array = Perception.percevoir(colon, monde, catalogue_canaux)
	var resultat: Array = []
	for entree in perceptions:
		if "ouie" in entree.canaux:
			resultat.append(entree)
	return resultat

# RECOPIEE de banc_son.gd:ids_de.
static func ids_de(perceptions: Array) -> Array:
	var ids: Array = []
	for entree in perceptions:
		ids.append(entree.chose.id)
	return ids

# RECOPIEE de banc_son.gd:intensite_attenuee -- MEME FORMULE que
# perception.gd:_percevoir_propagation_obstacles, jamais consultee par
# captures_ouie ci-dessus (qui passe toujours par Perception.percevoir, le
# vrai chemin) : ici uniquement pour reconstruire, POUR L'AFFICHAGE, le
# son total percu par le colon.
static func intensite_attenuee(son_emis: float, distance: float, portee: float) -> float:
	if portee <= 0.0:
		return 0.0
	return son_emis * (1.0 - distance / portee)

# Somme, sur les seules sources EFFECTIVEMENT entendues (ids_entendus,
# rendu par captures_ouie/ids_de -- le vrai filtre de seuil), de
# l'intensite attenuee de chacune a la position du colon -- portee/
# sensibilite lues sur colon.proprietes.canaux_config.ouie, meme convention
# que perception.gd:_portee_effective (jamais une seconde portee inventee).
# C'est CE total qui monte quand un objet resonnant ajoute une source
# secondaire au-dela de la source originale.
static func son_total_percu(colon: Dictionary, sources: Array, ids_entendus: Array) -> float:
	var ouie: Dictionary = colon.proprietes.canaux_config.ouie
	var portee: float = ouie.get("portee", 0.0) * ouie.get("sensibilite", 1.0)
	var total := 0.0
	for source in sources:
		if not ids_entendus.has(source.id):
			continue
		var distance: float = colon.position.distance_to(source.position)
		total += intensite_attenuee(source.proprietes.get("son_emis", 0.0), distance, portee)
	return total

static func _texte_label_objet(objet: Dictionary, diag: Dictionary) -> String:
	return "%s\nresonance=%.2f\nson_recu=%.3f\nson_reemis=%.3f" % [objet.id, diag.resonance, diag.son_recu, diag.son_reemis]

static func _texte_label_colon(ids_entendus: Array, total: float) -> String:
	var entendu: String = ", ".join(ids_entendus) if not ids_entendus.is_empty() else "(rien)"
	return "colon\nsources percues : %s\nson total=%.3f" % [entendu, total]

static func _ligne_toggle(t: float, actif: bool) -> String:
	return "t=%.1fs SOURCE : %s" % [t, "activee" if actif else "coupee"]

static func _ligne_log(t: float, ids_entendus: Array) -> String:
	var entendu: String = ", ".join(ids_entendus) if not ids_entendus.is_empty() else "(rien)"
	return "t=%.1f colon entend : %s" % [t, entendu]

static func _ligne_rapport(t: float, objet: Dictionary, diag: Dictionary) -> String:
	return "t=%.1fs %s : resonance=%.2f son_recu=%.3f son_reemis=%.3f" % [t, objet.id, diag.resonance, diag.son_recu, diag.son_reemis]

# ---- Rendu (impur, Node) -- aucune decision, seulement construction des
# noeuds et de la camera.

func _couleur_de(id: String) -> Color:
	var rgb: Array = _config.get("couleurs_types", {}).get(id, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _creer_rendu(id: String, position: Vector3, couleur: Color) -> void:
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.color = couleur
	noeud.position = Vector2(position.x, position.y) - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var label := Label.new()
	label.position = Vector2(position.x, position.y) - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 70.0)
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	_labels[id] = label

func _creer_rendu_source() -> void:
	var centre := Vector2(_position_source.x, _position_source.y)

	_noeud_source = ColorRect.new()
	_noeud_source.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_source.size = Vector2(TAILLE_SOURCE, TAILLE_SOURCE)
	_noeud_source.position = centre - _noeud_source.size / 2.0
	add_child(_noeud_source)

	_label_source = Label.new()
	_label_source.position = centre - Vector2(TAILLE_SOURCE / 2.0, TAILLE_SOURCE / 2.0 + 24.0)
	_label_source.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(_label_source)

func _poser_camera() -> void:
	var decl_camera: Dictionary = _config.get("camera", {})
	var pos: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	_camera = Camera2D.new()
	_camera.position = Vector2(pos[0], pos[1])
	_camera.zoom = Vector2(decl_camera.get("zoom", 0.5), decl_camera.get("zoom", 0.5))
	_camera.enabled = true
	add_child(_camera)

func _charger_json(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
