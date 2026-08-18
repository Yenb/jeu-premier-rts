extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_produit_nucleaire.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). Chantier « Produit
# nucleaire -- contamination, mutation, maladie » (audit prealable
# audit_produit_nucleaire_prealable.md). Compose TROIS effets d'une meme
# source radioactive, en parallele, sur les MEMES mecanismes du coeur que
# scripts/banc_radiation.gd, TOUS INCHANGES : charge.gd, depense.gd,
# seuil_etat.gd, etat_duree.gd, etat_effectif.gd, epigenetique.gd, produit.gd,
# combustible.gd, perception.gd, objet.gd. AUCUN MECANISME DU COEUR TOUCHE.
#
# EFFET 1 -- CONTAMINATION DE ZONE (source qui s'epuise, laisse un residu) :
# la source hand-built (meme patron que banc_radiation.gd:fabriquer_source --
# un point d'emission n'a besoin d'aucune matiere physique) porte en plus une
# reserve nommee "radioactivite" (depense.gd, seuils_ref
# data/seuils_combustible.json:epuisement_radioactivite) ET une "masse" posee
# a la main -- REQUISE pour que scripts/produit.gd:transformer calcule un
# residu de volume non nul (un point d'emission SANS masse produirait un
# residu de volume total 0.0, fabrication refusee, voir objet.gd, ECHEC
# FORT ; constat fait en ecrivant ce fichier, absent de l'audit prealable).
# Chaque tick, force_radiation de la source suit la proportion de sa reserve
# restante (scripts/combustible.gd:restant, meme idiome que
# banc_chaleur_emise.gd). A epuisement, scripts/produit.gd:transformer
# (data/transformations.json:epuisement_source_radiation) remplace la source
# par un residu_radioactif -- produit.gd NE RELAIE AUCUNE propriete immuable
# (constat systemique, audit_produit_nucleaire_prealable.md) : ce fichier
# pose donc A LA MAIN, juste apres l'appel, un nouveau force_radiation (plus
# faible) et une NOUVELLE reserve "radioactivite_residuelle" sur le residu --
# exactement comme banc_radiation.gd pose force_radiation sur sa source
# hand-built. Le residu continue d'irradier en decroissant par le MEME
# mecanisme (Depense.avancer traite indifferemment l'une ou l'autre reserve,
# jamais les deux a la fois -- une seule cle vit sous proprietes.reserves a
# tout instant) ; quand cette seconde reserve atteint zero, force_radiation
# retombe naturellement a 0.0 (proportion nulle), aucun geste special requis.
#
# Les TROIS OBJETS CIBLES (bois/pierre/fer) reprennent, TELS QUELS, le
# mecanisme deja verrouille par banc_radiation.gd -- perception (canal
# "radiation") -> Charge.avancer PAR OBJET pondere par (force_radiation de la
# source * sensibilite_radiation EFFECTIVE de l'objet) -> EtatDuree.poser
# ("irradie") -> Depense.avancer sur une reserve "integrite". Rien de neuf
# ici : la source qui s'epuise et se transforme change seulement la valeur de
# force_radiation qu'ils percoivent, jamais la mecanique elle-meme.
#
# EFFET 2 -- MUTATION GENETIQUE (marque epigenetique sur le colon) : le colon
# porte un DEUXIEME canal charge.gd, "exposition_radioactive" (memes causes
# que le canal "radiation" des objets -- la source visible, si elle l'est).
# Au seuil, charge.gd pose un marqueur (expose_radiation_chronique) ; tant
# qu'il reste vrai, ce fichier appelle Epigenetique.poser(colon,
# "exposition_radioactive", ...) chaque tick (la marque s'accumule, exposition
# chronique) ; Epigenetique.avancer(colon, delta, ...) tourne CHAQUE tick,
# inconditionnellement (decroissance lente une fois l'exposition terminee,
# jamais un retrait instantane). CE FICHIER N'APPELLE JAMAIS expression.gd --
# voir data/epigenetique.json:exposition_radioactive._note pour la raison
# (exprimer()/appliquer() rappeles chaque tick composeraient sur une base deja
# mutee au tick precedent et feraient diverger 'vitesse' sans borne). Le
# modulateur de la marque est affiche brut, jamais applique a 'vitesse' par ce
# chantier.
#
# EFFET 3 -- MALADIE PAR RADIATION (escalier nausee -> syndrome -> mort) :
# TROISIEME canal charge.gd sur le colon, "nausee_radiation" (memes causes).
# Au seuil, pose un marqueur ; tant qu'il reste vrai, EtatDuree.poser(colon,
# "nausee_radiation", ...) chaque tick (reversible, s'estompe si le colon
# s'eloigne -- meme idiome que "irradie"/"empoisonne"). EN PARALLELE, ce
# fichier ecrit "dose_radiation_cumulee" sur le colon a chaque tick TANT QUE
# la source lui est visible (meme geste que "degats_impact_cumules" dans
# banc_fracture.gd -- une grandeur qui ne redescend JAMAIS, ecrite par le
# cablage, jamais par un mecanisme du coeur). scripts/seuil_etat.gd compare
# cette dose a deux seuils UNIVERSELS (data/seuils_etat.json:
# syndrome_radiation/mort_radiation, 50.0 puis 100.0) et pose deux etats
# IRREVERSIBLES distincts -- AUCUNE collision possible avec "nausee_radiation"
# (nom d'etat DIFFERENT, gouverne exclusivement par charge.gd/etat_duree.gd,
# jamais par seuil_etat.gd). EtatEffectif.valeur(colon, "vitesse", etats)
# compose les trois : nausee_radiation/syndrome_radiation MODULENT (se
# multiplient s'ils sont actifs ensemble), mort_radiation ECRASE a 0.0 (un
# ecraseur gagne toujours sur un modulateur, voir etat_effectif.gd, ORDRE DE
# RESOLUTION -- mort rend les deux autres sans effet observable sur vitesse,
# sans qu'aucun des trois etats n'ait besoin de connaitre les deux autres).
#
# GEOMETRIE : source au centre (0,0,0). bois_nucleaire/pierre_nucleaire
# disposes PERPENDICULAIREMENT (jamais sur aucun segment du mur, meme patron
# que banc_radiation.gd) ; fer_nucleaire ET le colon sont alignes sur le MEME
# axe que le mur (0,-100,0), au-dela de lui -- UN SEUL mur togglable bloque
# donc SIMULTANEMENT fer_nucleaire ET le colon, jamais bois/pierre. Reprend
# le patron banc_radiation.gd tel que demande par la tache.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et fabrique source/mur/objets/
#   colon. _unhandled_input bascule le mur au clic gauche. _process appelle
#   UNIQUEMENT avancer() (fonction statique, ci-dessous) puis lit ses
#   resultats pour l'affichage/la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_produit_nucleaire.gd) : perceoit_cible/monde_pour_cible/
#   avancer_source/avancer_objets/avancer_colon/avancer/fabriquer_*/
#   diagnostiquer_*, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const Perception = preload("res://scripts/perception.gd")
const Charge = preload("res://scripts/charge.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Depense = preload("res://scripts/depense.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Epigenetique = preload("res://scripts/epigenetique.gd")
const Produit = preload("res://scripts/produit.gd")
const Combustible = preload("res://scripts/combustible.gd")

const TAILLE := 70.0
const TAILLE_SOURCE := 34.0
const TAILLE_MUR := 40.0
const TAILLE_COLON := 40.0
const HAUTEUR_BARRE := 10.0
const PROPRIETE_SENSIBILITE := "sensibilite_radiation"
const PROPRIETE_FORCE := "force_radiation"
const NOM_CANAL_RADIATION := "radiation"

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _seuils_etat: Dictionary = {}
var _seuils_combustible: Dictionary = {}
var _epigenetique: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _table_types: Dictionary = {}
var _materiaux: Dictionary = {}
var _transformations: Dictionary = {}

var _source: Dictionary = {}
var _mur: Dictionary = {}
var _objets: Array = []
var _colon: Dictionary = {}
var _mur_actif: bool = false
var _source_transformee: bool = false

var _noeuds: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_source: ColorRect
var _label_source: Label
var _noeud_mur: ColorRect
var _label_mur: Label
var _noeud_colon: ColorRect
var _label_colon: Label
var _irradie_avant: Dictionary = {}
var _etat_colon_avant: String = "sain"
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_produit_nucleaire.json")
	_etats = _charger_json("res://data/etats.json")
	_seuils_etat = _charger_json("res://data/seuils_etat.json")
	_seuils_combustible = _charger_json("res://data/seuils_combustible.json")
	_epigenetique = _charger_json("res://data/epigenetique.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_table_types = _charger_json("res://data/types.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_transformations = _charger_json("res://data/transformations.json").get("transformations", {})
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	_source = fabriquer_source(_config.source)
	_mur = fabriquer_mur(_config.mur, _materiaux, proprietes_immuables)
	_objets = fabriquer_objets(_config.objets, _materiaux, proprietes_immuables, _config)
	var pos_colon: Array = _config.colon.position
	_colon = fabriquer_colon(_config.colon.id, Vector3(pos_colon[0], pos_colon[1], pos_colon[2]), _table_types, _config)

	for objet in _objets:
		_irradie_avant[objet.id] = false
		_creer_rendu_objet(objet)
	_creer_rendu_source()
	_creer_rendu_mur()
	_creer_rendu_colon()
	_poser_camera()

	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_mur_actif = not _mur_actif
		print(_ligne_toggle(_temps, _mur_actif))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var resultat := avancer(_source, _mur, _mur_actif, _objets, _colon, delta, _config, _etats, _seuils_etat, _seuils_combustible, _epigenetique, _catalogue_canaux, _table_types, _materiaux, _transformations)

	if resultat.source_transformee and not _source_transformee:
		_source_transformee = true
		print(_ligne_transformation(_temps))

	for objet in _objets:
		var id: String = objet.id
		var irradie: bool = objet.proprietes.get("etats_actifs", []).has(_config.nom_etat_irradie)
		if irradie != _irradie_avant.get(id, false):
			print(_ligne_irradie_objet(_temps, id, irradie))
			_irradie_avant[id] = irradie

	var etat_colon := _etat_courant_colon(_colon)
	if etat_colon != _etat_colon_avant:
		print(_ligne_etat_colon(_temps, etat_colon))
		_etat_colon_avant = etat_colon

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		var irradie: bool = objet.proprietes.get("etats_actifs", []).has(_config.nom_etat_irradie)
		_noeuds[id].color = Color(0.75, 0.2, 0.2) if irradie else Color(0.5, 0.5, 0.55)
		_labels[id].text = _texte_label_objet(objet, _etats)

	_noeud_source.color = Color(0.95, 0.6, 0.1) if not _source_transformee else Color(0.4, 0.7, 0.3)
	_label_source.text = _texte_label_source(_source, _config)

	_noeud_mur.visible = _mur_actif
	_label_mur.visible = _mur_actif
	_label_mur.text = _texte_label_mur(_mur)

	var diag_colon := diagnostiquer_colon(_colon, _etats, _config)
	_noeud_colon.color = _couleur_colon(diag_colon.etat)
	_label_colon.text = _texte_label_colon(diag_colon)

func _charger_json(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _etat_courant_colon(colon: Dictionary) -> String:
	return diagnostiquer_colon(colon, _etats, _config).etat

# ---- Fonctions PURES, testables headless (voir test_banc_produit_nucleaire.gd) ----

# Le mur n'entre dans le Monde du tick QUE si mur_actif est vrai -- meme
# idiome que banc_radiation.gd:monde_pour_objet.
static func monde_pour_cible(source: Dictionary, mur: Dictionary, mur_actif: bool) -> Monde:
	var murs: Array = [mur] if mur_actif else []
	return BancCommun.monde_depuis([
		{"choses": [source], "type": "source_radioactive"},
		{"choses": murs, "type": "mur"},
	])

# La source (ou le residu, meme Dictionary, id/position inchanges) est-elle
# visible pour CETTE cible (objet ou colon) ? Delegue entierement a
# Perception.percevoir -- meme fonction que banc_radiation.gd:perceoit_source,
# recopiee ici (chaque banc porte sa propre copie).
static func perceoit_cible(id_cible: String, position_cible: Vector3, source: Dictionary, mur: Dictionary, mur_actif: bool, portee: float, seuil: float, catalogue_canaux: Dictionary) -> bool:
	var monde := monde_pour_cible(source, mur, mur_actif)
	var entite := {
		"id": id_cible,
		"position": position_cible,
		"proprietes": {
			"canaux": [NOM_CANAL_RADIATION],
			"canaux_config": { NOM_CANAL_RADIATION: { "portee": portee, "seuil": seuil } },
		},
	}
	var perceptions: Array = Perception.percevoir(entite, monde, catalogue_canaux)
	for entree in perceptions:
		if entree.chose.id == source.id and NOM_CANAL_RADIATION in entree.canaux:
			return true
	return false

# force_radiation COURANTE de la source (avant transformation) ou du residu
# (apres) -- lit la SEULE reserve presente sous proprietes.reserves a cet
# instant (jamais les deux a la fois, voir en-tete du fichier) et la
# multiplie par la proportion restante (scripts/combustible.gd:restant).
static func force_radiation_actuelle(source: Dictionary, config: Dictionary) -> float:
	var reserves: Dictionary = source.proprietes.get("reserves", {})
	if reserves.has(config.nom_reserve_source):
		return config.force_radiation_source_base * Combustible.restant(source, config.nom_reserve_source).proportion
	if reserves.has(config.nom_reserve_residu):
		return config.force_radiation_residu_base * Combustible.restant(source, config.nom_reserve_residu).proportion
	return 0.0

# EFFET 1 -- UN PAS sur la source (ou le residu) : (1) Depense.avancer
# decremente la SEULE reserve presente, quelle qu'elle soit -- pose
# "radioactivite_epuisee" sur proprietes au franchissement (data/
# seuils_combustible.json:epuisement_radioactivite). (2) force_radiation est
# recalculee depuis la proportion restante. (3) si le marqueur vient d'etre
# pose ET que la reserve encore presente est celle de la SOURCE (jamais deja
# transformee) : Produit.transformer (INCHANGE) remplace proprietes par celles
# du residu_radioactif, puis ce fichier pose A LA MAIN force_radiation et la
# nouvelle reserve "radioactivite_residuelle" (produit.gd ne relaie aucune
# propriete immuable, voir en-tete du fichier). Rend { franchis,
# transformee: bool }.
static func avancer_source(source: Dictionary, delta: float, config: Dictionary, catalogue_seuils_combustible: Dictionary, table_types: Dictionary, materiaux: Dictionary, transformations: Dictionary) -> Dictionary:
	var franchis := Depense.avancer([source], delta, catalogue_seuils_combustible)
	source.proprietes["force_radiation"] = force_radiation_actuelle(source, config)

	var transformee := false
	var reserves: Dictionary = source.proprietes.get("reserves", {})
	if source.proprietes.get(config.declencheur_radioactivite_epuisee, false) and reserves.has(config.nom_reserve_source):
		var config_produire: Dictionary = transformations.get(config.transformation_source, {}).get("a_zero", {}).get("produire", {})
		var nouvelles_proprietes: Dictionary = Produit.transformer(source.proprietes, config_produire, table_types, materiaux)
		if not nouvelles_proprietes.is_empty():
			source.proprietes.clear()
			source.proprietes.merge(nouvelles_proprietes, true)
			source.proprietes["reserves"] = { config.nom_reserve_residu: config.reserve_residuelle_defaut.duplicate(true) }
			source.proprietes["force_radiation"] = force_radiation_actuelle(source, config)
			transformee = true

	return { "franchis": franchis, "transformee": transformee }

# EFFET 1 (suite) -- UN PAS sur les trois objets cibles, MEME mecanique que
# banc_radiation.gd:avancer (perception -> Charge.avancer PAR OBJET pondere
# par sensibilite_radiation effective -> EtatDuree.poser("irradie") ->
# Depense.avancer sur "integrite"), recopiee ici. Rend { bascules, expirees,
# franchis_integrite }.
static func avancer_objets(objets: Array, source: Dictionary, mur: Dictionary, mur_actif: bool, delta: float, config: Dictionary, etats: Dictionary, catalogue_canaux: Dictionary) -> Dictionary:
	var portee: float = config.portee_perception_radiation
	var seuil_perception: float = config.seuil_perception_radiation
	var bascules: Array = []
	for objet in objets:
		var causes: Array = []
		if perceoit_cible(objet.id, objet.position, source, mur, mur_actif, portee, seuil_perception, catalogue_canaux):
			var sensibilite: float = EtatEffectif.valeur(objet, PROPRIETE_SENSIBILITE, etats)
			if sensibilite > 0.0:
				causes.append({"position": source.position, "poids": source.proprietes.get(PROPRIETE_FORCE, 0.0) * sensibilite})
		var b := Charge.avancer([objet], causes, delta)
		if not b.is_empty():
			bascules.append(objet.id)
		if objet.proprietes.get(config.declencheur_expose_radiation, false):
			EtatDuree.poser(objet, config.nom_etat_irradie, etats)
	var expirees := EtatDuree.avancer(objets, delta, etats)

	for objet in objets:
		var reserves: Dictionary = objet.proprietes.get("reserves", {})
		if not reserves.has(config.nom_reserve_integrite):
			continue
		var actif: bool = objet.proprietes.get("etats_actifs", []).has(config.nom_etat_irradie)
		reserves[config.nom_reserve_integrite]["cout_base"] = config.degat_par_s if actif else 0.0
	var franchis_integrite := Depense.avancer(objets, delta)

	return { "bascules": bascules, "expirees": expirees, "franchis_integrite": franchis_integrite }

# EFFETS 2 + 3 -- UN PAS sur le colon : (1) perception decide si la source
# (ou le residu) est visible ; (2) UN SEUL appel a Charge.avancer met a jour
# les DEUX canaux du colon (etats.exposition_radioactive ET
# etats.nausee_radiation) avec les MEMES causes (charge.gd accepte plusieurs
# canaux nommes sur le meme objet en un seul appel) ; (3) tant que le
# marqueur de mutation reste vrai, Epigenetique.poser accumule la marque ;
# Epigenetique.avancer tourne INCONDITIONNELLEMENT (decroissance) ; (4) tant
# que le marqueur de nausee reste vrai, EtatDuree.poser reconduit
# "nausee_radiation" ; EtatDuree.avancer tourne inconditionnellement
# (estompage) ; (5) dose_radiation_cumulee monte de "dose_par_s" SEULEMENT
# si la source est visible, ne redescend JAMAIS ; (6) SeuilEtat.avancer pose
# syndrome_radiation/mort_radiation au franchissement des deux seuils
# universels sur cette dose. Rend { visible, bascules_charge, expirees_nausee,
# bascules_seuil }.
static func avancer_colon(colon: Dictionary, source: Dictionary, mur: Dictionary, mur_actif: bool, delta: float, config: Dictionary, etats: Dictionary, seuils_etat: Dictionary, catalogue_epigenetique: Dictionary, catalogue_canaux: Dictionary) -> Dictionary:
	var portee: float = config.portee_perception_radiation
	var seuil_perception: float = config.seuil_perception_radiation
	var visible := perceoit_cible(colon.id, colon.position, source, mur, mur_actif, portee, seuil_perception, catalogue_canaux)

	var causes: Array = []
	if visible:
		causes.append({"position": source.position, "poids": source.proprietes.get(PROPRIETE_FORCE, 0.0)})
	var bascules_charge := Charge.avancer([colon], causes, delta)

	if colon.proprietes.get(config.declencheur_mutation, false):
		Epigenetique.poser(colon, config.nom_marque_epigenetique, catalogue_epigenetique)
	Epigenetique.avancer(colon, delta, catalogue_epigenetique)

	if colon.proprietes.get(config.declencheur_nausee, false):
		EtatDuree.poser(colon, config.nom_etat_nausee, etats)
	var expirees_nausee := EtatDuree.avancer([colon], delta, etats)

	if visible:
		colon.proprietes["dose_radiation_cumulee"] = colon.proprietes.get("dose_radiation_cumulee", 0.0) + config.dose_par_s * delta

	var bascules_seuil := SeuilEtat.avancer([colon], seuils_etat)

	return {
		"visible": visible,
		"bascules_charge": bascules_charge,
		"expirees_nausee": expirees_nausee,
		"bascules_seuil": bascules_seuil,
	}

# UN PAS de simulation complet, composant les trois effets. Rend { franchis_source,
# source_transformee, bascules_objets, franchis_integrite_objets, visible_colon,
# bascules_charge_colon, bascules_seuil_colon }.
static func avancer(source: Dictionary, mur: Dictionary, mur_actif: bool, objets: Array, colon: Dictionary, delta: float, config: Dictionary, etats: Dictionary, seuils_etat: Dictionary, seuils_combustible: Dictionary, catalogue_epigenetique: Dictionary, catalogue_canaux: Dictionary, table_types: Dictionary, materiaux: Dictionary, transformations: Dictionary) -> Dictionary:
	var resultat_source := avancer_source(source, delta, config, seuils_combustible, table_types, materiaux, transformations)
	var resultat_objets := avancer_objets(objets, source, mur, mur_actif, delta, config, etats, catalogue_canaux)

	var fige: bool = colon_fige(colon)
	var resultat_colon: Dictionary
	if fige:
		resultat_colon = { "visible": false, "bascules_charge": [], "expirees_nausee": [], "bascules_seuil": [] }
	else:
		resultat_colon = avancer_colon(colon, source, mur, mur_actif, delta, config, etats, seuils_etat, catalogue_epigenetique, catalogue_canaux)

	return {
		"franchis_source": resultat_source.franchis,
		"source_transformee": resultat_source.transformee,
		"bascules_objets": resultat_objets.bascules,
		"franchis_integrite_objets": resultat_objets.franchis_integrite,
		"visible_colon": resultat_colon.visible,
		"bascules_charge_colon": resultat_colon.bascules_charge,
		"bascules_seuil_colon": resultat_colon.bascules_seuil,
		"colon_fige": fige,
	}

# MORT -- decision Yael (option "figer", pas de retrait du monde : monde.gd
# n'a aucune fonction de retrait d'objet, un vrai chantier separe, hors
# perimetre ici). Une fois "mort_radiation" actif dans etats_actifs, plus
# AUCUN mecanisme de ce banc ne met a jour le colon -- avancer_colon n'est
# plus jamais appele dessus par avancer() ci-dessus, il reste visible comme
# un corps, figé EXACTEMENT dans l'etat ou la mort l'a laisse (dose,
# marque epigenetique, etats_actifs, vitesse effective -- tout gele en
# meme temps, puisque plus rien ne les touche). Verifie au DEBUT du pas :
# le tick ou "mort_radiation" vient tout juste d'etre pose (a l'interieur
# de avancer_colon lui-meme, via SeuilEtat.avancer) acheve encore SON
# PROPRE traitement -- c'est le pas SUIVANT qui gele, jamais celui qui
# vient de tuer.
static func colon_fige(colon: Dictionary) -> bool:
	return colon.proprietes.get("etats_actifs", []).has("mort_radiation")

# Hand-built, AUCUNE composition -- un point d'emission n'a besoin d'aucune
# matiere physique (voir banc_radiation.gd:fabriquer_source). "masse" est
# posee a la main, en plus de force_radiation, REQUISE pour que
# Produit.transformer calcule un residu de volume non nul (voir en-tete du
# fichier). "reserves.<nom_reserve_source>" suit le patron generique de
# depense.gd, seuils_ref vers data/seuils_combustible.json:
# epuisement_radioactivite.
static func fabriquer_source(decl: Dictionary) -> Dictionary:
	var pos: Array = decl.position
	return {
		"id": decl.id,
		"position": Vector3(pos[0], pos[1], pos[2]),
		"proprietes": {
			PROPRIETE_FORCE: decl.get("force_radiation", 0.0),
			"masse": decl.get("masse", 0.0),
			"reserves": { decl.nom_reserve_source: decl.reserve_radioactivite.duplicate(true) },
		},
	}

# Fabrique via Objet.fabriquer (composition fusionnee -- "densite" structurelle
# necessaire pour jouer le role de propriete_obstacle du canal "radiation").
static func fabriquer_mur(decl: Dictionary, materiaux: Dictionary, proprietes_immuables: Array) -> Dictionary:
	var catalogue: Dictionary = { decl.id: {"composition": decl.composition} }
	var pos: Array = decl.position
	return Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)

# Construit les trois objets cibles via Objet.fabriquer (composition
# fusionnee -- "sensibilite_radiation" deja dans data/proprietes_immuables_
# composition.json). Chaque objet recoit ENSUITE son propre canal de charge,
# sa propre reserve d'integrite -- meme patron que
# banc_radiation.gd:fabriquer_objets.
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array, config: Dictionary) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet.proprietes["etats"] = {config.nom_canal_radiation: config.canal_radiation_defaut.duplicate(true)}
		objet.proprietes["etats_actifs"] = []
		objet.proprietes["reserves"] = {config.nom_reserve_integrite: config.reserve_integrite_defaut.duplicate(true)}
		objets.append(objet)
	return objets

# Construit le colon via Objet.fabriquer(type "colon"), table_types etant
# data/types.json ENTIER (colon ET ses quatre paquets "herite" y vivent deja
# -- meme table pour Objet.fabriquer ET pour Produit.transformer, voir
# _ready()). Le colon fabrique porte deja "etats"/"etats_actifs"/
# "marques_epigenetiques"/"genes_actifs"/"genes_etat"/"age"/"vitesse" par
# composition du paquet "dynamique" (data/types.json) -- ce fichier AJOUTE
# seulement les deux canaux NEUFS ("exposition_radioactive"/
# "nausee_radiation") a "etats" (Dictionary deja present, fusionne dedans,
# jamais ecrase) et "dose_radiation_cumulee" (0.0, grandeur qui n'existe QUE
# parce que ce fichier l'ecrit lui-meme -- meme statut que
# "degats_impact_cumules"/"choc_magique_cumule").
static func fabriquer_colon(id: String, position: Vector3, table_types: Dictionary, config: Dictionary) -> Dictionary:
	var colon := Objet.fabriquer(id, "colon", position, table_types)
	if colon.is_empty():
		return colon
	var etats: Dictionary = colon.proprietes.get("etats", {})
	etats[config.nom_canal_mutation] = config.canal_mutation_defaut.duplicate(true)
	etats[config.nom_canal_nausee] = config.canal_nausee_defaut.duplicate(true)
	colon.proprietes["etats"] = etats
	colon.proprietes["dose_radiation_cumulee"] = 0.0
	return colon

# Diagnostic d'affichage du colon, PUR. "etat" resume l'escalier -- mort >
# syndrome > nausee > sain, PUR AFFICHAGE (le calcul reel de vitesse effective
# reste EtatEffectif.valeur, jamais reimplemente ici -- ce classement ne sert
# qu'a choisir UN mot/UNE couleur, les etats reels restants tous actifs en
# parallele dans etats_actifs).
static func diagnostiquer_colon(colon: Dictionary, etats: Dictionary, config: Dictionary) -> Dictionary:
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	var etat := "sain"
	if actifs.has("mort_radiation"):
		etat = "mort"
	elif actifs.has("syndrome_radiation"):
		etat = "syndrome"
	elif actifs.has(config.nom_etat_nausee):
		etat = "nausee"
	var marque: Dictionary = colon.proprietes.get("marques_epigenetiques", {}).get(config.nom_marque_epigenetique, {})
	return {
		"etat": etat,
		"dose": colon.proprietes.get("dose_radiation_cumulee", 0.0),
		"vitesse_effective": EtatEffectif.valeur(colon, "vitesse", etats),
		"modulateur_epigenetique": marque.get("modulateur", 0.0),
	}

static func _couleur_colon(etat: String) -> Color:
	match etat:
		"mort":
			return Color(0.15, 0.15, 0.15)
		"syndrome":
			return Color(0.6, 0.3, 0.7)
		"nausee":
			return Color(0.7, 0.6, 0.2)
		_:
			return Color(0.3, 0.55, 0.35)

static func _texte_label_objet(objet: Dictionary, etats: Dictionary) -> String:
	var canal: Dictionary = objet.proprietes.get("etats", {}).get("radiation", {})
	var irradie: bool = objet.proprietes.get("etats_actifs", []).has("irradie")
	var reserves: Dictionary = objet.proprietes.get("reserves", {})
	return "%s\nsensibilite_radiation=%.2f\ncharge=%.2f/%.2f\nirradie=%s\nintegrite=%.2f" % [
		objet.id,
		EtatEffectif.valeur(objet, PROPRIETE_SENSIBILITE, etats),
		canal.get("charge", 0.0), canal.get("seuil", 0.0),
		irradie,
		reserves.get("integrite", {}).get("reserve", 0.0),
	]

static func _texte_label_source(source: Dictionary, config: Dictionary) -> String:
	var reserves: Dictionary = source.proprietes.get("reserves", {})
	var nom_reserve: String = config.nom_reserve_source if reserves.has(config.nom_reserve_source) else config.nom_reserve_residu
	var restant := Combustible.restant(source, nom_reserve)
	return "%s\nforce_radiation=%.3f\nreserve (%s)=%.2f (%.0f%%)" % [
		source.id, source.proprietes.get(PROPRIETE_FORCE, 0.0), nom_reserve, restant.absolu, restant.proportion * 100.0
	]

static func _texte_label_mur(mur: Dictionary) -> String:
	return "mur (fer)\ndensite=%.2f" % mur.proprietes.get("densite", 0.0)

static func _texte_label_colon(diag: Dictionary) -> String:
	return "colon_nucleaire\ndose_radiation_cumulee=%.2f\netat=%s\nvitesse_effective=%.1f\nmarque_epigenetique(modulateur)=%.4f" % [
		diag.dose, diag.etat, diag.vitesse_effective, diag.modulateur_epigenetique
	]

static func _ligne_toggle(t: float, mur_actif: bool) -> String:
	return "t=%.1fs MUR DE BLINDAGE (fer) : %s" % [t, "present" if mur_actif else "absent"]

static func _ligne_transformation(t: float) -> String:
	return "t=%.1fs source_nucleaire : reserve epuisee, transformee en residu_radioactif" % t

static func _ligne_irradie_objet(t: float, id: String, irradie: bool) -> String:
	return "t=%.1fs %s : irradie %s" % [t, id, "POSE" if irradie else "RETIRE"]

static func _ligne_etat_colon(t: float, etat: String) -> String:
	return "t=%.1fs colon_nucleaire : etat -> %s" % [t, etat]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction des
# noeuds et de la camera.

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
	add_child(label)
	_labels[id] = label

func _creer_rendu_source() -> void:
	var centre := Vector2(_source.position.x, _source.position.y)
	_noeud_source = ColorRect.new()
	_noeud_source.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_source.color = Color(0.95, 0.6, 0.1)
	_noeud_source.size = Vector2(TAILLE_SOURCE, TAILLE_SOURCE)
	_noeud_source.position = centre - _noeud_source.size / 2.0
	add_child(_noeud_source)

	_label_source = Label.new()
	_label_source.position = _noeud_source.position - Vector2(20.0, 60.0)
	add_child(_label_source)

func _creer_rendu_mur() -> void:
	var centre := Vector2(_mur.position.x, _mur.position.y)
	_noeud_mur = ColorRect.new()
	_noeud_mur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_mur.color = Color(0.35, 0.35, 0.4)
	_noeud_mur.size = Vector2(TAILLE_MUR, TAILLE_MUR)
	_noeud_mur.position = centre - _noeud_mur.size / 2.0
	add_child(_noeud_mur)

	_label_mur = Label.new()
	_label_mur.position = _noeud_mur.position - Vector2(20.0, 24.0)
	add_child(_label_mur)

func _creer_rendu_colon() -> void:
	var centre := Vector2(_colon.position.x, _colon.position.y)
	_noeud_colon = ColorRect.new()
	_noeud_colon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_colon.size = Vector2(TAILLE_COLON, TAILLE_COLON)
	_noeud_colon.position = centre - _noeud_colon.size / 2.0
	add_child(_noeud_colon)

	_label_colon = Label.new()
	_label_colon.position = _noeud_colon.position - Vector2(20.0, 100.0)
	add_child(_label_colon)

func _poser_camera() -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(_source.position.x, _source.position.y - 100.0)
	camera.zoom = Vector2(0.4, 0.4)
	camera.enabled = true
	add_child(camera)
