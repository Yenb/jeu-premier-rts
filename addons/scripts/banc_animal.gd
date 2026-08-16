extends Node2D

# Cablage de banc VISUEL, separe de banc_p1 (Scene/banc_animal.tscn). Montre
# flux.gd et depense.gd jouer ENSEMBLE sur un animal photosynthetique
# (docs/design.md, "Exemple travaillé : l'animal photosynthetique", version
# minimale -- pas de paliers, pas de regimes, pas de reproduction : deux
# mecanismes deja prouves, observes cote a cote). JETABLE PAR DEFINITION :
# aucune regle de jeu ne doit vivre ici, seulement du cablage. Ni flux.gd ni
# depense.gd ne sont modifies par ce fichier.
#
# Deux moities, meme decoupage que banc_p1.gd :
# - Node (impur) : _ready charge les donnees (data/banc_animal.json,
#   data/flux.json, data/engagements.json) et fabrique le monde ; _process
#   calcule d'abord la cible et le mouvement du pas (cible_besoin +
#   bouger_vers), pose surcout_action sur chaque reserve selon que l'animal
#   bouge ce pas (comportement.surcout_mouvement, en donnee) ou reste
#   stationnaire (0.0) -- entretien (cout_base) et mouvement (surcout_action)
#   sont deux couts distincts que depense.gd lit deja, le banc ne fait que
#   poser le nombre -- PUIS avance depense.avancer + flux.avancer (flux lit
#   encore la position d'avant ce pas, comme avant), deplace l'animal,
#   redessine deux barres de reserve (largeur = grandeur visuelle, AUCUN
#   nombre affiche). L'etat d'engagement (PHASE 1, voir couplage.gd) est
#   desormais porte PAR L'ANIMAL LUI-MEME (_animal.proprietes.engagement),
#   plus par le Node -- le Node ne garde plus aucun etat de couplage entre
#   deux frames.
# - Fonctions statiques (pures, testables headless, voir test_banc_animal.gd) :
#   cible_besoin(...) -- retrouve OU aller, en posant/faisant avancer/retirant
#     l'engagement generique (scripts/couplage.gd) sur l'entite recue. Sans
#     memoire d'un appel a l'autre, comparer la reserve la plus basse a
#     CHAQUE frame fait osciller l'animal (dithering) : des qu'il approche
#     une source, l'autre reserve redevient la plus basse une frame plus
#     tard, et la cible change avant d'etre atteinte. Deux mecanismes
#     corrigent ca, TOUS DEUX PORTES PAR couplage.gd MAINTENANT (avant
#     PHASE 1 : hysteresis/satisfaction recodees ici meme, voir git log) :
#     HYSTERESIS (engagement.seuil_bascule -- engage sur un canal, on n'en
#     change que si un autre est plus bas d'au moins ce seuil, verifie
#     ICI par cible_besoin, PAS par couplage.gd -- voir plus bas, "Ce que
#     couplage.gd NE FAIT PAS") ; ENGAGEMENT JUSQU'A SATISFACTION
#     (engagement.seuil_satisfait, sens_satisfaction "sur_seuil" --
#     Couplage.avancer libere l'engagement quand la reserve visee a
#     DEPASSE ce seuil, voir couplage.gd section 4). Generique a N
#     reserves : ne lit que ligne.cible/ligne.source dans table_flux,
#     jamais un nom fixe.
#   Ce que couplage.gd NE FAIT PAS ICI : l'ARRACHEMENT PAR HYSTERESIS
#     (une autre reserve devient assez pire pour faire changer d'avis
#     AVANT satisfaction) n'est pas un mecanisme de couplage.gd (voir son
#     en-tete, "L'ARRACHEMENT PAR SAILLANCE... N'EST PAS evalue ici") --
#     c'est cible_besoin qui compare la pire reserve courante au canal
#     engage et appelle Couplage.retirer() lui-meme le cas echeant, exactement
#     comme agir.gd le fait pour l'arrachement par saillance (voir agir.gd).
# - Outils PARTAGES avec les autres bancs (scripts/banc_commun.gd, scripts/
#   couplage.gd, precharges ci-dessous) : bouger_vers (BancCommun) ; poser/
#   avancer/retirer (Couplage, voir plus haut).
#
# Frontiere : ne calcule aucune decroissance ni aucun transfert -- delegue
# entierement a depense.gd et flux.gd. Les noms "animal"/"lumiere"/"herbe"
# n'existent que dans data/banc_animal.json (exception banc jetable, voir
# CLAUDE.md "Tout est objet") ; le coeur ne lit que des proprietes
# (phototrophe, brouteur, lumineux, nourrissant, portee_flux, taux_flux).
# "energie"/"matiere" (noms de reserve) n'apparaissent nulle part dans ce
# fichier ni dans couplage.gd -- seulement dans data/banc_animal.json
# (types.animal.reserves) et data/flux.json (ligne.cible), lus par cle.

const Objet = preload("res://scripts/objet.gd")
const Depense = preload("res://scripts/depense.gd")
const Flux = preload("res://scripts/flux.gd")
const Couplage = preload("res://scripts/couplage.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

var _couleurs_types: Dictionary = {}
var _reserves_max: Dictionary = {}
var _table_flux: Array = []
var _engagements: Dictionary = {}
var _surcout_mouvement: float = 0.0
var _monde: Array = []
var _animal: Dictionary = {}
var _vitesse: float = 90.0
var _noeuds: Dictionary = {}
var _barre_energie: ColorRect
var _barre_matiere: ColorRect

const LARGEUR_BARRE := 40.0
const HAUTEUR_BARRE := 5.0

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_animal.json")
	_couleurs_types = donnees.get("couleurs_types", {})
	_reserves_max = donnees.get("reserves_max", {})
	_table_flux = _charger_json_array("res://data/flux.json")
	_engagements = _charger_json("res://data/engagements.json")
	_surcout_mouvement = donnees.get("comportement", {}).get("surcout_mouvement", 0.0)
	var types: Dictionary = donnees.get("types", {})

	var i := 0
	for instance in donnees.get("instances", []):
		var pos: Array = instance["position"]
		var position3 := Vector3(pos[0], pos[1], pos[2])
		var id := "%s_%d" % [instance["type"], i]
		i += 1
		var objet := Objet.fabriquer(id, instance["type"], position3, types)
		_monde.append(objet)
		_noeuds[id] = _dessiner_carre(instance["type"], position3)

	var decl: Dictionary = donnees.get("animal", {})
	var pos_animal: Array = decl.get("position", [0.0, 0.0, 0.0])
	var position_animal := Vector3(pos_animal[0], pos_animal[1], pos_animal[2])
	_vitesse = decl.get("vitesse", 90.0)
	_animal = Objet.fabriquer("animal", "animal", position_animal, types)
	_monde.append(_animal)
	_noeuds["animal"] = _dessiner_carre("animal", position_animal)

	_barre_energie = _dessiner_barre(Color(1.0, 0.85, 0.2))
	_barre_matiere = _dessiner_barre(Color(0.3, 0.8, 0.3))

func _process(delta: float) -> void:
	var position_avant: Vector3 = _animal.position
	var position_cible := cible_besoin(_animal, _monde, _table_flux, position_avant, delta, _engagements)
	var position_apres := BancCommun.bouger_vers(position_avant, position_cible, _vitesse, delta)
	var a_bouge := position_apres != position_avant

	_poser_surcout_mouvement(a_bouge)
	Depense.avancer(_monde, delta)
	Flux.avancer(_monde, _table_flux, delta)

	_animal.position = position_apres
	_noeuds["animal"].position = Vector2(_animal.position.x, _animal.position.y) - _noeuds["animal"].size / 2.0

	_redessiner_barres()

# Entretien (cout_base) vs mouvement (surcout_action) : depense.gd lit deja
# les deux, le banc ne fait que poser le nombre -- aucun calcul de depense
# ici. Generique a N reserves : boucle sur proprietes.reserves, aucun nom
# de canal en dur.
func _poser_surcout_mouvement(a_bouge: bool) -> void:
	var reserves: Dictionary = _animal.proprietes.get("reserves", {})
	var surcout: float = _surcout_mouvement if a_bouge else 0.0
	for nom in reserves:
		reserves[nom]["surcout_action"] = surcout

# Retrouve OU aller pour l'entite recue, en gerant son engagement generique
# (scripts/couplage.gd) au passage -- fonction pure, ne stocke rien en
# dehors de entite.proprietes.engagement (que Couplage mute en place).
#
# entite : { id, position, proprietes: { reserves, engagement } }, engagement
# STRUCTURELLE (voir couplage.gd) -- doit etre pose par la fabrication
# (data/banc_animal.json, types.animal.engagement: null).
# monde : Array d'objets bruts (sources ET l'entite elle-meme).
# table_flux : data/flux.json, generique a N lignes -- aucun nom de reserve
# en dur ici, seulement ligne.cible/ligne.source.
# catalogue_engagements : data/engagements.json, cle "animal_reserve" --
# seuils/sens_satisfaction lus par Couplage, jamais par cette fonction.
#
# Ordre des etapes, un engagement generique a la fois :
# 1) engagement en cours -> Couplage.avancer contre sa cible reelle
#    (retrouvee par id dans monde). "satisfait"/"arrache" videntt
#    l'engagement (Couplage l'a deja remis a null) ; "garde" le laisse
#    intact.
# 2) HYSTERESIS (pas un mecanisme de couplage.gd, voir en-tete du fichier) :
#    si toujours engage sur un canal, et qu'une AUTRE reserve est pire d'au
#    moins engagement.seuil_bascule, Couplage.retirer() l'engagement en
#    cours -- il sera rechoisi a l'etape suivante.
# 3) libre (jamais engage, ou vient d'etre libere) -> engage sur la pire
#    reserve, vers sa source la plus proche (Couplage.poser, contexte
#    { canal: <nom de la reserve> } pour parametrer le chemin
#    "reserves.{canal}.reserve" de la regle "animal_reserve").
# 4) rend la position de la cible engagee, ou defaut si aucun engagement
#    n'a pu se poser (aucune reserve en carence, ou aucune source trouvee).
static func cible_besoin(
	entite: Dictionary,
	monde: Array,
	table_flux: Array,
	defaut: Vector3,
	delta: float,
	catalogue_engagements: Dictionary,
) -> Vector3:
	var proprietes: Dictionary = entite.proprietes
	var reserves: Dictionary = proprietes.get("reserves", {})
	var engagement: Variant = proprietes.get("engagement", null)

	if engagement != null:
		var cible_actuelle: Variant = _par_id(monde, engagement.cible_id)
		Couplage.avancer(entite, cible_actuelle, delta, catalogue_engagements)
		engagement = proprietes.get("engagement", null)

	var pire := _pire_reserve(reserves, table_flux)
	if engagement != null:
		var canal_actuel: String = engagement.get("canal", "")
		if pire != "" and pire != canal_actuel:
			var seuil_bascule: float = engagement.get("seuil_bascule", 0.0)
			var valeur_engagee := _valeur_reserve(reserves, canal_actuel)
			var valeur_candidate := _valeur_reserve(reserves, pire)
			if valeur_candidate < valeur_engagee - seuil_bascule:
				Couplage.retirer(entite, "hysteresis : autre reserve plus pire d'au moins seuil_bascule")
				engagement = null

	if engagement == null and pire != "":
		var ligne: Variant = _ligne_pour_cible(table_flux, pire)
		if ligne != null:
			var source: Variant = _source_la_plus_proche(monde, ligne.source, entite.position)
			if source != null:
				Couplage.poser(entite, source, "animal_reserve", catalogue_engagements, {"canal": pire})
				engagement = proprietes.get("engagement", null)

	if engagement == null:
		return defaut
	var cible: Variant = _par_id(monde, engagement.cible_id)
	if cible == null:
		return defaut
	return cible.position

static func _valeur_reserve(reserves: Dictionary, nom: String) -> float:
	var canal: Dictionary = reserves.get(nom, {})
	return canal.get("reserve", 0.0)

static func _pire_reserve(reserves: Dictionary, table_flux: Array) -> String:
	var pire := ""
	var pire_valeur := INF
	for ligne in table_flux:
		var valeur: float = _valeur_reserve(reserves, ligne.cible)
		if valeur < pire_valeur:
			pire_valeur = valeur
			pire = ligne.cible
	return pire

static func _ligne_pour_cible(table_flux: Array, cible: String) -> Variant:
	for ligne in table_flux:
		if ligne.cible == cible:
			return ligne
	return null

static func _par_id(monde: Array, id: Variant) -> Variant:
	for chose in monde:
		if chose.id == id:
			return chose
	return null

static func _source_la_plus_proche(monde: Array, propriete_source: String, position_animal: Vector3) -> Variant:
	var meilleure: Variant = null
	var meilleure_d := INF
	for chose in monde:
		if not chose.proprietes.get(propriete_source, false):
			continue
		var d: float = position_animal.distance_to(chose.position)
		if d < meilleure_d:
			meilleure_d = d
			meilleure = chose
	return meilleure

func _redessiner_barres() -> void:
	var reserves: Dictionary = _animal.proprietes.get("reserves", {})
	var pos_animal := Vector2(_animal.position.x, _animal.position.y)
	_positionner_barre(_barre_energie, reserves.get("energie", {}).get("reserve", 0.0),
		_reserves_max.get("energie", 1.0), pos_animal + Vector2(-LARGEUR_BARRE / 2.0, -24.0))
	_positionner_barre(_barre_matiere, reserves.get("matiere", {}).get("reserve", 0.0),
		_reserves_max.get("matiere", 1.0), pos_animal + Vector2(-LARGEUR_BARRE / 2.0, -16.0))

func _positionner_barre(barre: ColorRect, valeur: float, max_valeur: float, origine: Vector2) -> void:
	var fraction: float = clamp(valeur / max_valeur, 0.0, 1.0) if max_valeur > 0.0 else 0.0
	barre.position = origine
	barre.size = Vector2(LARGEUR_BARRE * fraction, HAUTEUR_BARRE)

func _dessiner_carre(type: String, pos: Vector3) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(24.0, 24.0)
	carre.color = _couleur_de(type)
	carre.position = Vector2(pos.x, pos.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _dessiner_barre(couleur: Color) -> ColorRect:
	var barre := ColorRect.new()
	barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barre.color = couleur
	add_child(barre)
	return barre

func _couleur_de(type: String) -> Color:
	var rgb: Array = _couleurs_types.get(type, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _charger_json_array(chemin: String) -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
