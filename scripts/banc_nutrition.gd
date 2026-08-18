extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_nutrition.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « profil de repas +
# malnutrition ». Compose QUATRE mecanismes deja fermes, TOUS INCHANGES :
# scripts/consommer.gd (le repas se vide, la reserve du colon se remplit --
# meme patron que scripts/banc_manger.gd:avancer_repas), scripts/depense.gd
# (les trois reserves redescendent, chacune a SON cout_base),
# scripts/charge.gd (la malnutrition monte sous cause, bascule, et redescend
# seule), scripts/etat_duree.gd + scripts/etat_effectif.gd (l'etat 'malnutri'
# et sa modulation de vitesse). AUCUN MECANISME DU COEUR TOUCHE, AUCUN .gd
# neuf du coeur.
#
# CE QUE CE BANC MONTRE, ET QU'AUCUN AUTRE NE MONTRAIT :
# 1) TROIS RESERVES DE NUTRIMENTS EN PARALLELE, chacune a sa vitesse propre.
#    Rien de neuf n'a ete ecrit pour ca : depense.gd:avancer boucle deja
#    "for nom in reserves" et appelle _avancer_canal sur CHACUNE, sans
#    qu'aucune ne connaisse les autres. Trois cout_base distincts en donnee
#    (data/banc_nutrition.json, ratio 1:3:10) suffisent -- le gras cale
#    longtemps, le sucre redescend vite. Une seule reserve a taux variable
#    aurait au contraire exige que ce cablage recalcule un taux par tick
#    selon le dernier repas : plus de code, moins lisible.
# 2) UNE CAUSE SYNTHETISEE PAR LE CABLAGE. charge.gd ne lit JAMAIS une
#    reserve et ne scanne jamais le monde : "causes" est un Array nu
#    construit par l'appelant. Ce fichier y met { position: colon.position,
#    poids: accumulation } DES QUE la somme des trois reserves passe sous
#    seuil_qualite -- l'etat interne du colon devient ainsi sa propre cause,
#    a distance ZERO (Portee.en_portee compare distance <= portee, 0.0 <= 0.0
#    est vrai, donc portee_charge peut valoir 0.0 sans cas particulier).
#    PREMIERE cause du depot qui ne vient pas d'une AUTRE chose du monde.
#
# LA CHAINE, EN UN SEUL PASSAGE (avancer(), plus bas) :
# 1) MANGER -- si un repas est servi (toggle au clic, voir CONTROLE), taux =
#    taux_base * comestibilite_EFFECTIVE * valeur_nutritive_energie_EFFECTIVE
#    (EtatEffectif.valeur, JAMAIS reimplementee -- meme composition exacte
#    que banc_manger.gd), puis Consommer.transferer du repas vers LA RESERVE
#    NOMMEE PAR SON MATERIAU (type_nutriment, lu sur la fiche
#    data/materiaux.json, jamais un nom en dur ici).
# 2) DEPENSER -- Depense.avancer sur le SEUL colon (les repas ne sont jamais
#    dans le monde passe a depense.gd : leur reserve 'contenu' ne se vide que
#    par consommer.gd). Aucun catalogue de seuils : aucun des trois canaux ne
#    porte 'seuils_ref', ce banc n'a aucun seuil de DEPENSE.
# 3) SYNTHETISER LA CAUSE -- somme des trois reserves face a seuil_qualite.
# 4) CHARGER -- Charge.avancer sur le meme colon. Au franchissement montant,
#    charge.gd pose LUI-MEME un simple marqueur booleen sur proprietes
#    (jamais 'malnutri', qu'il ne connait pas) ; au franchissement
#    descendant, il RETIRE la meme cle -- c'est la quatrieme nature d'effet,
#    le seuil REVERSIBLE, et la raison pour laquelle ce chantier n'utilise
#    NI seuil_etat.gd (qui ne compare que vers le haut, sur une cle plate)
#    NI l'idiome '+= cumulee' de force_traction_cumulee (qui ne redescend
#    jamais).
# 5) RELAYER -- ce cablage lit le marqueur : present -> EtatDuree.poser(
#    "malnutri") a CHAQUE tick (idempotent : poser n'ajoute le nom a
#    etats_actifs que s'il n'y est pas deja) ; absent -> le nom est efface
#    d'etats_actifs. Meme idiome de repose-chaque-tick que 'nausee_radiation'
#    (banc_produit_nucleaire.gd), SANS sa 'duree'.
#
# POURQUOI LE CABLAGE RETIRE L'ETAT LUI-MEME, et pourquoi c'est OBLIGATOIRE
# ici : data/etats.json:malnutri ne porte PAS de 'duree' (decision -- une
# malnutrition ne s'arrete pas apres N secondes, elle s'arrete quand on
# remange). Un etat sans 'duree' n'entre jamais dans etats_intensite, donc
# EtatDuree.avancer ne le retirera JAMAIS. Le seul retrait possible est donc
# celui du cablage, en MIROIR EXACT du marqueur reversible de charge.gd --
# jamais une ligne d'etat_duree.gd ni d'etat_effectif.gd modifiee. Ecriture
# directe du cablage sur etats_actifs : meme geste que banc_maladie.gd
# (porteur) ou banc_succession.gd (stade).
#
# LES REPAS SONT CONSTRUITS A LA MAIN (pas Objet.fabriquer, meme statut que
# banc_maladie.gd/banc_ecoulement.gd) : 'type_nutriment' est une String, et
# la fusion par composition (data/proprietes_immuables_composition.json) est
# une moyenne ponderee par volume -- sans aucun sens sur une String. La fiche
# materiau est donc lue DIRECTEMENT, comme banc_permeabilite.gd lit
# 'permeabilite'.
#
# LE COLON NE SE DEPLACE PAS et ne decide rien : aucun pipeline
# perception/proximite/dominance/agir ici, contrairement a banc_manger.gd. Le
# toggle EST la decision -- « on lui sert ce repas », jamais « il va le
# chercher ». Choix assume : ce chantier observe un CORPS, pas un agent ; la
# 'vitesse' n'est affichee que pour rendre visible la modulation par
# 'malnutri' (etat_effectif.gd), jamais pour bouger quoi que ce soit.
#
# CONTROLE : clic gauche = toggle CYCLIQUE sur quatre etats -- gras,
# proteine, sucre, RIEN. 'RIEN' est le quatrieme etat a part entiere (c'est
# lui qui produit la malnutrition) et l'etat de DEPART : le banc lance sans
# aucun clic montre donc la degradation complete tout seul.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge data/banc_nutrition.json/data/materiaux.json/
#   data/etats.json, construit colon et repas, cree le rendu.
#   _unhandled_input fait tourner le toggle. _process appelle avancer(...)
#   (fonction statique), imprime les traces, redessine.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_nutrition.gd) : fabriquer_colon/fabriquer_repas/noms_reserves/
#   somme_nutriments/causes_de_malnutrition/avancer/repas_suivant/
#   est_malnutri, plus le texte d'affichage et de log.

const Consommer = preload("res://scripts/consommer.gd")
const Depense = preload("res://scripts/depense.gd")
const Charge = preload("res://scripts/charge.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")

const PROPRIETE_COMESTIBILITE := "comestibilite"
const PROPRIETE_VALEUR_NUTRITIVE := "valeur_nutritive_energie"
const PROPRIETE_TYPE_NUTRIMENT := "type_nutriment"
const PROPRIETE_VITESSE := "vitesse"

const TAILLE_COLON := 40.0
const TAILLE_REPAS := 56.0
const LARGEUR_BARRE := 90.0
const HAUTEUR_BARRE := 9.0
const ESPACEMENT_BARRE := 12.0
const TAILLE_POLICE_LABEL := 12
const PERIODE_TRACE_S := 1.0

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _etats: Dictionary = {}
var _colon: Dictionary = {}
var _repas: Array = []
var _noms_reserves: Array = []
var _selection := 0
var _temps := 0.0
var _prochaine_trace := 0.0
var _noeud_colon: ColorRect
var _label_colon: Label
var _noeuds_repas: Dictionary = {}
var _labels_repas: Dictionary = {}
var _fonds_barres: Array = []
var _barres_reserves: Dictionary = {}
var _fond_barre_malnutrition: ColorRect
var _barre_malnutrition: ColorRect

func _ready() -> void:
	_config = _charger_json("res://data/banc_nutrition.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_etats = _charger_json("res://data/etats.json")

	_noms_reserves = noms_reserves(_config)
	_colon = fabriquer_colon(_config)
	_repas = fabriquer_repas(_config, _materiaux)
	# L'etat de depart est RIEN (index == nombre de repas), pas le premier
	# repas : sans clic, le banc doit montrer la degradation.
	_selection = _repas.size()

	_creer_rendu()
	_poser_camera()
	_rafraichir_tout()
	print(_ligne_service(0.0, _nom_repas_servi()))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_selection = repas_suivant(_selection, _repas.size())
		print(_ligne_service(_temps, _nom_repas_servi()))

func _process(delta: float) -> void:
	_temps += delta
	var resultat := avancer(_colon, _repas_servi(), _config, _etats, delta)

	if resultat.pose:
		print(_ligne_pose(_temps, resultat.charge, resultat.somme))
	if resultat.retire:
		print(_ligne_retire(_temps, resultat.charge, resultat.somme))
	if _temps >= _prochaine_trace:
		_prochaine_trace = _temps + PERIODE_TRACE_S
		print(_ligne_etat(_temps, _colon, _noms_reserves, _config, _etats, _nom_repas_servi()))

	_rafraichir_tout()

func _repas_servi() -> Variant:
	if _selection < 0 or _selection >= _repas.size():
		return null
	return _repas[_selection]

func _nom_repas_servi() -> String:
	var servi: Variant = _repas_servi()
	return "rien" if servi == null else String(servi.id)

# ---- Fonctions PURES, testables headless (voir test_banc_nutrition.gd) ----

# Noms des trois reserves de nutriment, LUS EN DONNEE (jamais "gras"/
# "proteine"/"sucre" en dur dans ce fichier) -- ils servent a la fois a la
# somme, a l'affichage et a la verification que le type_nutriment d'un
# materiau designe bien une reserve que le colon porte.
static func noms_reserves(config: Dictionary) -> Array:
	var noms: Array = []
	for nom in config.get("reserves", {}):
		noms.append(String(nom))
	noms.sort()
	return noms

# Le colon, CONSTRUIT A LA MAIN (voir en-tete). Les trois canaux de reserve
# et le canal de charge sont DUPLIQUES depuis la config (duplicate(true)) --
# jamais partages avec le Dictionary du disque, meme precaution d'aliasing
# que banc_maladie.gd:fabriquer_colons.
static func fabriquer_colon(config: Dictionary) -> Dictionary:
	var pos: Array = config.colon.position
	var reserves: Dictionary = {}
	for nom in config.get("reserves", {}):
		reserves[String(nom)] = config.reserves[nom].duplicate(true)
	return {
		"id": String(config.colon.id),
		"position": Vector3(pos[0], pos[1], pos[2]),
		"proprietes": {
			"vitesse": float(config.colon.vitesse),
			"reserves": reserves,
			"etats": {String(config.nom_canal_malnutrition): config.canal_malnutrition.duplicate(true)},
			"etats_actifs": [],
		},
	}

# Les trois repas, CONSTRUITS A LA MAIN. comestibilite/valeur_nutritive_
# energie sont RECOPIEES depuis la fiche materiau sur proprietes -- c'est ce
# qui rend EtatEffectif.valeur utile (un futur etat 'pourri' ecraserait
# comestibilite a 0.0 et le taux tomberait a 0.0 sans un cas particulier).
# type_nutriment reste une String, JAMAIS un nombre : elle designe une
# reserve, elle n'est jamais modulee par un etat. Un materiau sans
# type_nutriment est une reference cassee -- push_error, ce repas est saute
# (jamais un nom de reserve invente).
static func fabriquer_repas(config: Dictionary, materiaux: Dictionary) -> Array:
	var repas: Array = []
	for decl in config.get("repas", []):
		var nom_materiau: String = String(decl.materiau)
		var fiche: Dictionary = materiaux.get(nom_materiau, {})
		if not fiche.has(PROPRIETE_TYPE_NUTRIMENT):
			push_error("banc_nutrition.gd : materiau '%s' sans '%s'" % [nom_materiau, PROPRIETE_TYPE_NUTRIMENT])
			continue
		var pos: Array = decl.position
		repas.append({
			"id": String(decl.id),
			"position": Vector3(pos[0], pos[1], pos[2]),
			"materiau": nom_materiau,
			"proprietes": {
				PROPRIETE_COMESTIBILITE: float(fiche.get(PROPRIETE_COMESTIBILITE, 0.0)),
				PROPRIETE_VALEUR_NUTRITIVE: float(fiche.get(PROPRIETE_VALEUR_NUTRITIVE, 0.0)),
				PROPRIETE_TYPE_NUTRIMENT: String(fiche[PROPRIETE_TYPE_NUTRIMENT]),
				"etats_actifs": [],
				"reserves": {String(config.nom_reserve_contenu): {"reserve": float(decl.contenu)}},
			},
		})
	return repas

# Somme des trois reserves de nutriment -- LA grandeur que le cablage compare
# a seuil_qualite pour synthetiser la cause. PURE.
static func somme_nutriments(colon: Dictionary, noms: Array) -> float:
	var reserves: Dictionary = colon.proprietes.get("reserves", {})
	var somme := 0.0
	for nom in noms:
		somme += float(reserves.get(nom, {}).get("reserve", 0.0))
	return somme

# LA CAUSE SYNTHETISEE (voir en-tete, point 2). Rend un Array vide -- et
# c'est ce vide, pas une valeur negative, qui declenche la redescente
# autonome de charge.gd (taux_decroissance n'est applique que lorsque la
# somme des causes a portee est nulle ce pas). PURE.
static func causes_de_malnutrition(colon: Dictionary, somme: float, config: Dictionary) -> Array:
	if somme >= float(config.seuil_qualite):
		return []
	return [{"position": colon.position, "poids": float(config.accumulation_malnutrition_par_s)}]

static func est_malnutri(colon: Dictionary, config: Dictionary) -> bool:
	return colon.proprietes.get("etats_actifs", []).has(String(config.etat_malnutri))

# Toggle CYCLIQUE sur nb_repas + 1 etats : le dernier est RIEN. PURE.
static func repas_suivant(selection: int, nb_repas: int) -> int:
	return (selection + 1) % (nb_repas + 1)

# UN PAS complet : manger -> depenser -> synthetiser la cause -> charger ->
# relayer vers l'etat. MUTE le colon et le repas servi EN PLACE. L'ordre
# manger-AVANT-depenser est fixe et assume : un repas servi ce tick remplit
# la reserve avant qu'elle ne soit ponctionnee du meme delta, jamais
# l'inverse -- a l'echelle d'un tick l'ecart est de cout_base * delta, mais
# l'ordre doit etre DIT plutot que subi.
#
# Rend { mange, quantite, somme, charge, malnutri, pose, retire } -- 'pose'/
# 'retire' sont les DEUX transitions de ce pas, lues avant/apres sur le
# colon et jamais deduites de la valeur de la charge (le seuil appartient a
# charge.gd, ce fichier ne le recompare jamais).
static func avancer(
	colon: Dictionary,
	repas_servi: Variant,
	config: Dictionary,
	etats: Dictionary,
	delta: float,
) -> Dictionary:
	var noms := noms_reserves(config)
	var malnutri_avant := est_malnutri(colon, config)

	var quantite := 0.0
	if repas_servi != null:
		quantite = _servir(colon, repas_servi, config, etats, noms, delta)

	Depense.avancer([colon], delta)

	var somme := somme_nutriments(colon, noms)
	var causes := causes_de_malnutrition(colon, somme, config)
	Charge.avancer([colon], causes, delta)

	_relayer_marqueur(colon, config, etats)

	var malnutri_apres := est_malnutri(colon, config)
	return {
		"mange": quantite > 0.0,
		"quantite": quantite,
		"somme": somme,
		"charge": charge_malnutrition(colon, config),
		"malnutri": malnutri_apres,
		"pose": malnutri_apres and not malnutri_avant,
		"retire": malnutri_avant and not malnutri_apres,
	}

# Le geste de banc_manger.gd:avancer_repas, adapte : la reserve RECEPTRICE
# n'est pas fixe, elle est NOMMEE PAR LE MATERIAU du repas. Un type_nutriment
# qui ne designe aucune reserve du colon est une anomalie STRUCTURELLE
# (push_error, rien n'est transfere) -- laisser faire aurait fait creer
# silencieusement par consommer.gd:_crediter une quatrieme reserve sans
# cout_base, qui ne redescendrait jamais.
static func _servir(
	colon: Dictionary,
	repas: Dictionary,
	config: Dictionary,
	etats: Dictionary,
	noms: Array,
	delta: float,
) -> float:
	var cible: String = String(repas.proprietes.get(PROPRIETE_TYPE_NUTRIMENT, ""))
	if not noms.has(cible):
		push_error("banc_nutrition.gd : '%s' vise la reserve '%s', absente du colon" % [repas.id, cible])
		return 0.0
	var comestibilite_eff: float = EtatEffectif.valeur(repas, PROPRIETE_COMESTIBILITE, etats)
	var valeur_eff: float = EtatEffectif.valeur(repas, PROPRIETE_VALEUR_NUTRITIVE, etats)
	var taux: float = float(config.taux_base) * comestibilite_eff * valeur_eff
	var resultat := Consommer.transferer(repas, colon, String(config.nom_reserve_contenu), cible, taux, delta)
	return float(resultat.quantite)

# MIROIR EXACT du marqueur reversible de charge.gd (voir en-tete). Aucune
# comparaison de seuil ici : ce fichier ne fait que suivre la presence de la
# cle que charge.gd pose et retire lui-meme.
static func _relayer_marqueur(colon: Dictionary, config: Dictionary, etats: Dictionary) -> void:
	var nom_etat: String = String(config.etat_malnutri)
	if colon.proprietes.get(String(config.nom_marqueur_malnutrition), false):
		EtatDuree.poser(colon, nom_etat, etats)
		return
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	actifs.erase(nom_etat)

static func charge_malnutrition(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get("etats", {})
		.get(String(config.nom_canal_malnutrition), {}).get("charge", 0.0))

static func _texte_colon(colon: Dictionary, noms: Array, config: Dictionary, etats: Dictionary, servi: String) -> String:
	var reserves: Dictionary = colon.proprietes.get("reserves", {})
	var lignes: Array = []
	for nom in noms:
		lignes.append("%s=%.1f" % [nom, float(reserves.get(nom, {}).get("reserve", 0.0))])
	return "%s\n%s\nsomme=%.1f (seuil_qualite=%.1f)\nmalnutrition=%.2f (seuil=%.1f)\netat=%s\nvitesse=%.1f\nsert=%s" % [
		colon.id,
		"  ".join(lignes),
		somme_nutriments(colon, noms),
		float(config.seuil_qualite),
		charge_malnutrition(colon, config),
		float(config.canal_malnutrition.seuil),
		String(config.etat_malnutri) if est_malnutri(colon, config) else "nourri",
		EtatEffectif.valeur(colon, PROPRIETE_VITESSE, etats),
		servi,
	]

static func _texte_repas(repas: Dictionary, config: Dictionary, servi: bool) -> String:
	var contenu: float = float(repas.proprietes.reserves[String(config.nom_reserve_contenu)].reserve)
	return "%s\n%s -> %s\ncontenu=%.0f%s" % [
		repas.id,
		repas.materiau,
		String(repas.proprietes[PROPRIETE_TYPE_NUTRIMENT]),
		contenu,
		"\nSERVI" if servi else "",
	]

static func _ligne_service(t: float, servi: String) -> String:
	return "t=%.1fs SERT : %s" % [t, servi]

static func _ligne_pose(t: float, charge: float, somme: float) -> String:
	return "t=%.1fs MALNUTRI pose (charge=%.2f, somme des nutriments=%.1f)" % [t, charge, somme]

static func _ligne_retire(t: float, charge: float, somme: float) -> String:
	return "t=%.1fs malnutri retire (charge=%.2f, somme des nutriments=%.1f)" % [t, charge, somme]

static func _ligne_etat(t: float, colon: Dictionary, noms: Array, config: Dictionary, etats: Dictionary, servi: String) -> String:
	var reserves: Dictionary = colon.proprietes.get("reserves", {})
	var morceaux: Array = []
	for nom in noms:
		morceaux.append("%s=%.1f" % [nom, float(reserves.get(nom, {}).get("reserve", 0.0))])
	return "t=%.1fs sert=%s | %s | somme=%.1f | malnutrition=%.2f | etat=%s | vitesse=%.1f" % [
		t, servi, "  ".join(morceaux),
		somme_nutriments(colon, noms),
		charge_malnutrition(colon, config),
		String(config.etat_malnutri) if est_malnutri(colon, config) else "nourri",
		EtatEffectif.valeur(colon, PROPRIETE_VITESSE, etats),
	]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction des
# noeuds, les couleurs et la longueur des barres.

func _couleur(cle: String, defaut: Array) -> Color:
	var rgb: Array = _config.get("couleurs", {}).get(cle, defaut)
	return Color(rgb[0], rgb[1], rgb[2])

func _creer_rendu() -> void:
	_noeud_colon = ColorRect.new()
	_noeud_colon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_colon.size = Vector2(TAILLE_COLON, TAILLE_COLON)
	_noeud_colon.position = Vector2(_colon.position.x, _colon.position.y) - _noeud_colon.size / 2.0
	add_child(_noeud_colon)

	# Trois barres de reserve + une barre de malnutrition, empilees AU-DESSUS
	# du colon. Chaque barre a un fond fixe (la longueur max) et une barre de
	# remplissage, seule a changer de taille -- meme patron que
	# banc_animal.gd:_positionner_barre.
	var origine := Vector2(_colon.position.x, _colon.position.y) - Vector2(LARGEUR_BARRE / 2.0, TAILLE_COLON)
	var rang := 0
	for nom in _noms_reserves:
		var y: float = origine.y - float(rang + 1) * ESPACEMENT_BARRE
		_fonds_barres.append(_creer_barre(_couleur("fond_barre", [0.15, 0.15, 0.15]),
			Vector2(origine.x, y), LARGEUR_BARRE))
		var rgb: Array = _config.get("couleurs_reserves", {}).get(nom, [1.0, 1.0, 1.0])
		_barres_reserves[nom] = _creer_barre(Color(rgb[0], rgb[1], rgb[2]), Vector2(origine.x, y), 0.0)
		rang += 1
	var y_malnutrition: float = origine.y - float(rang + 2) * ESPACEMENT_BARRE
	_fond_barre_malnutrition = _creer_barre(_couleur("fond_barre", [0.15, 0.15, 0.15]),
		Vector2(origine.x, y_malnutrition), LARGEUR_BARRE)
	_barre_malnutrition = _creer_barre(_couleur("malnutrition", [0.9, 0.15, 0.15]),
		Vector2(origine.x, y_malnutrition), 0.0)

	_label_colon = Label.new()
	_label_colon.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	_label_colon.position = Vector2(_colon.position.x - LARGEUR_BARRE / 2.0, _colon.position.y + TAILLE_COLON)
	add_child(_label_colon)

	for repas in _repas:
		var carre := ColorRect.new()
		carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
		carre.size = Vector2(TAILLE_REPAS, TAILLE_REPAS)
		carre.position = Vector2(repas.position.x, repas.position.y) - carre.size / 2.0
		add_child(carre)
		_noeuds_repas[repas.id] = carre

		var label := Label.new()
		label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
		label.position = carre.position + Vector2(0.0, TAILLE_REPAS + 4.0)
		add_child(label)
		_labels_repas[repas.id] = label

func _creer_barre(couleur: Color, origine: Vector2, largeur: float) -> ColorRect:
	var barre := ColorRect.new()
	barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barre.color = couleur
	barre.position = origine
	barre.size = Vector2(largeur, HAUTEUR_BARRE)
	add_child(barre)
	return barre

func _rafraichir_tout() -> void:
	var malnutri := est_malnutri(_colon, _config)
	_noeud_colon.color = _couleur("colon_malnutri", [0.55, 0.5, 0.35]) if malnutri \
		else _couleur("colon", [0.3, 0.55, 0.85])

	var reserves: Dictionary = _colon.proprietes.get("reserves", {})
	for nom in _noms_reserves:
		var valeur: float = float(reserves.get(nom, {}).get("reserve", 0.0))
		var maxi: float = float(_config.get("reserves_max", {}).get(nom, 1.0))
		_barres_reserves[nom].size = Vector2(LARGEUR_BARRE * clamp(valeur / maxi, 0.0, 1.0), HAUTEUR_BARRE)
	var charge := charge_malnutrition(_colon, _config)
	var charge_max: float = float(_config.charge_max_affichee)
	_barre_malnutrition.size = Vector2(LARGEUR_BARRE * clamp(charge / charge_max, 0.0, 1.0), HAUTEUR_BARRE)

	_label_colon.text = _texte_colon(_colon, _noms_reserves, _config, _etats, _nom_repas_servi())

	var servi: Variant = _repas_servi()
	for repas in _repas:
		var est_servi: bool = servi != null and servi.id == repas.id
		_noeuds_repas[repas.id].color = _couleur(repas.id, [1.0, 1.0, 1.0]) if est_servi \
			else _couleur("repas_non_servi", [0.35, 0.35, 0.35])
		_labels_repas[repas.id].text = _texte_repas(repas, _config, est_servi)

func _poser_camera() -> void:
	var decl: Dictionary = _config.get("camera", {})
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(decl.get("zoom", 1.0), decl.get("zoom", 1.0))
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
