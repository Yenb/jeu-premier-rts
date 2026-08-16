extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_bonheur.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « bonheur +
# temperaments » (audit prealable audit_mecaniques_psycho_sociales_prealable.md,
# lignes 5 et 6, toutes deux au verdict CABLABLE -- CONFIRME a l'ecriture :
# AUCUN mecanisme du coeur touche ni cree). Compose DEUX mecanismes deja fermes,
# TOUS DEUX INCHANGES : scripts/seuil_etat.gd (les trois etats poses et retires)
# et scripts/etat_effectif.gd (vitesse et rythme effectifs, composition
# multiplicative).
#
# CE QU'ON DOIT VOIR : quatre colons cote a cote, immobiles, tous exposes AUX
# MEMES cinq sources AUX MEMES niveaux au meme instant. Rien dans le monde ne
# les distingue. Pourtant ils n'ont ni le meme bonheur ni le meme etat -- parce
# que chacun porte SES PROPRES poids. Un clic coupe une source (cycle sur les
# cinq, puis aucune) : le colon qui y mettait tout s'effondre, celui qui n'y
# mettait rien ne bouge pas d'un chiffre.
#
# LE BONHEUR EST UN CHAMP DERIVE, PAS UNE RESERVE. Il ne vit dans aucun
# 'reserves' : depense.gd ne le touche jamais, charge.gd non plus. Le cablage le
# RECALCULE A NEUF chaque tick -- somme des poids_bonheur[source] x
# proprietes[source] -- et l'ECRIT PAR-DESSUS la valeur du tick precedent.
# JAMAIS un '+='. Ce n'est pas un detail de style : c'est la seule chose qui
# empeche un champ derive de DERIVER. Le resultat negatif est deja mesure DEUX
# FOIS dans le depot (data/epigenetique.json:exposition_radioactive puis
# accoutumance_froid) : expression.gd:exprimer, rappele chaque tick, RELIT par
# _lire_chemin la valeur qu'il vient lui-meme d'ecrire et fait diverger sans
# borne la propriete visee. expression.gd n'est donc PAS appele ici --
# contournement INTENTIONNEL et documente, jamais un oubli, meme decision que
# banc_graisse_accoutumance.gd.
#
# UN SEUL ECRIVAIN (audit, constat C). `poser_bonheur` est l'UNIQUE fonction de
# ce fichier qui ecrit 'bonheur' ET son miroir 'manque_bonheur' -- les deux dans
# le MEME geste, depuis le MEME nombre. Deux morceaux de cablage ecrivant l'un
# le champ et l'autre son miroir se seraient desynchronises EN SILENCE : aucun
# test n'aurait rougi, seuil_etat.gd aurait simplement compare deux grandeurs
# qui ne se repondent plus. Meme piege, meme parade que
# banc_faim_thermo.gd:poser_surcout_action.
#
# POURQUOI DEUX PROPRIETES POUR UNE SEULE GRANDEUR. seuil_etat.gd ne compare que
# VERS LE HAUT ('valeur > seuil', jamais >=, jamais <). « Le bonheur monte
# au-dessus de 0.7 » s'ecrit donc directement sur 'bonheur' -- et c'est la SEULE
# entree de data/seuils_etat.json dont la propriete comparee monte quand la
# situation s'AMELIORE. Mais « le bonheur descend sous 0.5 » n'est pas
# exprimable : il s'ecrit « son manque monte au-dessus de 0.5 », d'ou
# 'manque_bonheur' = max(0, capacite - bonheur). Le miroir sert ici UNIQUEMENT a
# retourner le SENS de la comparaison -- pas a atteindre une reserve enfouie
# sous proprietes.reserves.<nom>.reserve, seconde raison habituelle du miroir
# (manque_energie, manque_sommeil, manque_hygiene) : 'bonheur' est deja une cle
# PLATE. Constat B de l'audit.
#
# LES TEMPERAMENTS SONT DES POIDS, JAMAIS DES CATEGORIES (docs/design.md, « Les
# archetypes n'existent pas »). Ce fichier ne connait ni « social », ni
# « guerrier », ni « gourmand » : il lit un Dictionary 'poids_bonheur' sur
# chaque colon et boucle dessus. Les noms des sources n'y sont pas non plus --
# ils viennent de data/banc_bonheur.json. Un cinquieme temperament est une
# entree de donnee, zero ligne de code. Et 'poids_bonheur' est un Dictionary
# SEPARE, au meme rang qu'attaches/forme/poids_verbes -- SURTOUT PAS une entree
# de 'poids_verbes' (audit ligne 6 : son unique lecteur est
# agir.gd:_verbe_par_poids ; y glisser un poids de source de bonheur ferait
# entrer 'nourriture' dans l'arbitrage des VERBES, faux positif silencieux le
# jour ou un verbe porterait le meme nom).
#
# UN POIDS SUR UNE SOURCE QUE LE MONDE N'OFFRE PAS REND EXACTEMENT 0.0, sans
# alarme : `proprietes.get(source, 0.0)`. Ce n'est pas une tolerance, c'est le
# contrat -- un cannibale peut porter un poids sur une source qu'aucune de ces
# scenes ne pose, et sa contribution est simplement nulle. Verrouille par test.
#
# ESCALIER A DEUX ETAGES SUR LE MEME MIROIR. 'malheureux' (manque > 0.5) et
# 'desespere' (manque > 0.8) comparent la MEME propriete continue : franchir le
# second implique d'avoir franchi le premier, les DEUX restent actifs ensemble
# (memoire PAR ENTREE de seuil_etat.gd, aucune n'en retire l'autre) et leurs
# facteurs se composent MULTIPLICATIVEMENT (0.8 x 0.5 = 0.4). En remontant, le
# colon perd 'desespere' d'abord, puis 'malheureux' -- ordre INVERSE. Patron
# deja ecrit pour frisson/hypothermie et faim/famine.
#
# LES COLONS NE SE DEPLACENT PAS et ne decident rien : aucun pipeline
# perception/proximite/dominance/agir ici. Le clic EST le monde qui change.
# Choix assume, meme decoupage que banc_nutrition.gd -- ce chantier observe un
# CHAMP DERIVE, pas un agent. 'vitesse' et 'rythme' EFFECTIFS sont affiches pour
# rendre la modulation visible, jamais pour bouger quoi que ce soit.
#
# LIMITE DITE, PAS MASQUEE : l'etat 'heureux' module 'rythme' par 1.1, et
# banc_commun.gd:agents_rythme lit 'chose.proprietes.rythme' BRUTE (audit,
# constat D -- aucune couche de decision ne passe par etat_effectif.gd). La
# modulation de 'rythme' n'a donc d'effet QUE dans un cablage qui compose
# lui-meme EtatEffectif.valeur, ce que fait ce fichier (`rythme_effectif`) et ce
# qu'aucun autre banc du depot ne fait a ce jour. Rien n'est corrige ici : c'est
# une dette du cablage existant, pas de ce chantier.
#
# COLONS CONSTRUITS A LA MAIN (pas Objet.fabriquer, meme statut que
# banc_faim_thermo.gd/banc_maladie.gd/banc_nutrition.gd) : ni composition ni
# materiau, donc data/types.json n'est pas touche et rien n'est a enregistrer
# dans scripts/test_lint_donnees.gd. Consequence utile, verrouillee POSITIVEMENT
# par test : ne portant ni 'temperature' ni aucune grandeur cumulee, les colons
# sont des chemins morts silencieux pour TOUTES les autres entrees du catalogue
# PARTAGE data/seuils_etat.json -- aucun etat parasite ne peut se poser.
#
# CONTROLE : clic gauche = toggle CYCLIQUE sur (nombre de sources + 1) etats --
# chaque source coupee a son tour, puis AUCUNE coupee. 'AUCUNE' est l'etat de
# DEPART : le banc lance sans un clic montre deja quatre temperaments qui
# divergent. Meme idiome que banc_nutrition.gd:repas_suivant.
#
# RENDU : UN BLOC PAR COLON, UNE LIGNE PAR ROLE. De haut en bas -- nom du colon,
# ligne bonheur + etat (grande, dans la COULEUR de l'etat), les cinq barres de
# source (nom de la source a GAUCHE de sa barre, poids du colon a DROITE), le
# carre du colon (colore par l'etat lui aussi), puis vitesse et rythme SEULS sur
# la derniere ligne. Aucun de ces morceaux ne partage sa zone avec un autre :
# c'est toute la difference avec le rendu precedent, ou un unique label
# multi-lignes empilait sources, poids, vitesse et rythme sous le colon et se
# recouvrait lui-meme. La pile de barres se termine juste AU-DESSUS du carre et
# monte : une sixieme source declaree en donnee repousse le haut du bloc sans
# jamais recouvrir quoi que ce soit.
#
# TOUTE la geometrie vit dans data/banc_bonheur.json (largeurs de colonne,
# espacement entre barres, marges, cinq tailles de police, couleur par source) --
# aucun nombre de position en dur ici, meme discipline que pour les noms de
# propriete. Ces nombres sont lus UNIQUEMENT par _creer_rendu/_rafraichir_tout,
# JAMAIS par une fonction pure : changer le rendu ne peut pas changer un bonheur.
#
# LES CINQ SOURCES ONT CHACUNE SA COULEUR, et la barre d'une source COUPEE passe
# au rouge sombre a longueur nulle sans que son fond disparaisse -- sinon
# « coupee » et « nulle par hasard » seraient indistinguables. Un colon qui ne
# valorise pas une source affiche "-" a droite de sa barre et jamais "x0.00" :
# les deux valent 0.0 dans la somme, mais « je n'y mets rien » et « j'y mets
# zero » ne se disent pas pareil.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les trois JSON, construit les colons et le
#   rendu ; _unhandled_input fait tourner le toggle ; _process enchaine
#   poser_sources -> poser_bonheur -> SeuilEtat.avancer, lit les resultats pour
#   l'affichage et la console.
# - Fonctions statiques (pures, testables headless, voir test_banc_bonheur.gd) :
#   noms_sources/niveaux_sources/construire_colons/poser_sources/
#   calculer_bonheur/poser_bonheur/etat_dominant/compte_par_etat/
#   source_suivante/changements_etats/vitesse_effective/rythme_effectif/
#   seuil_de, plus les textes d'affichage et de log.
#
# AUCUN NOM DE PROPRIETE EN DUR : nom_bonheur/nom_manque_bonheur/
# nom_poids_bonheur/nom_vitesse/nom_rythme et les noms de sources arrivent tous
# de data/banc_bonheur.json -- c'est ce qui permet au test de faire traverser le
# meme code par un domaine entierement invente.

const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")

var _config: Dictionary = {}
var _catalogue_etats: Dictionary = {}
var _catalogue_seuils: Dictionary = {}

var _colons: Array = []
var _noms_sources: Array = []
var _coupee: int = -1
var _temps: float = 0.0
var _prochaine_trace: float = 0.0

# Un noeud par ROLE, jamais un label fourre-tout : c'est ce qui permet de donner
# a chaque morceau sa taille, sa couleur et sa position propres (voir « RENDU »
# dans l'en-tete). Tous indexes par id de colon.
var _noeuds_colons: Dictionary = {}    # id -> ColorRect, le carre colore par l'etat
var _barres_sources: Dictionary = {}   # id -> { nom_source -> ColorRect }
var _labels_poids: Dictionary = {}     # id -> { nom_source -> Label }
var _labels_bonheur: Dictionary = {}   # id -> Label, recolore par l'etat chaque tick
var _labels_pied: Dictionary = {}      # id -> Label, vitesse et rythme
var _centres_bloc: Dictionary = {}     # id -> float, x du centre du bloc (recentrage)
var _label_compteur: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_bonheur.json")
	_catalogue_etats = _charger_json("res://data/etats.json")
	_catalogue_seuils = _charger_json("res://data/seuils_etat.json")

	_noms_sources = noms_sources(_config)
	_colons = construire_colons(_config)
	# AUCUNE source coupee au depart (index hors des sources) : le banc lance
	# sans un clic montre deja quatre temperaments qui divergent.
	_coupee = _noms_sources.size()

	_creer_rendu()
	_poser_camera()
	print(ligne_pose(_config, _colons, _catalogue_seuils))
	_avancer_un_pas()
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_coupee = source_suivante(_coupee, _noms_sources.size())
		print(ligne_coupure(_temps, _nom_source_coupee()))

func _process(delta: float) -> void:
	_temps += delta
	_avancer_un_pas()
	if _temps >= _prochaine_trace:
		_prochaine_trace = _temps + float(_config.periode_trace_s)
		for colon in _colons:
			print(ligne_etat(_temps, colon, _config, _noms_sources, _catalogue_etats))
	_rafraichir_tout()

# UN PAS complet, cote Node parce qu'il imprime : poser les sources -> poser le
# bonheur et son miroir -> laisser seuil_etat.gd poser/retirer les etats -> dire
# ce qui a change. L'instantane d'etats_actifs est pris AVANT l'appel :
# seuil_etat.gd rend les ids ayant bascule, jamais QUELS etats.
func _avancer_un_pas() -> void:
	var avant: Dictionary = {}
	for colon in _colons:
		avant[colon.id] = colon.proprietes.get("etats_actifs", []).duplicate()
		poser_sources(colon, _config, _nom_source_coupee())
		poser_bonheur(colon, _config)
	SeuilEtat.avancer(_colons, _catalogue_seuils)
	for colon in _colons:
		var changements: Dictionary = changements_etats(avant[colon.id], colon.proprietes.get("etats_actifs", []))
		for ligne in lignes_changement(_temps, String(colon.id), changements):
			print(ligne)

func _nom_source_coupee() -> String:
	if _coupee < 0 or _coupee >= _noms_sources.size():
		return ""
	return String(_noms_sources[_coupee])

# ---- Fonctions PURES, testables headless (voir test_banc_bonheur.gd) ----

# Les noms des cinq sources, DANS L'ORDRE DECLARE en donnee (jamais trie : cet
# ordre est celui des barres a l'ecran et celui du cycle du clic -- deux choses
# que le lecteur doit pouvoir rapprocher). PURE.
static func noms_sources(config: Dictionary) -> Array:
	var noms: Array = []
	for source in config.get("sources", []):
		noms.append(String(source.nom))
	return noms

# Le niveau de chaque source A CET INSTANT : celui declare en donnee, sauf pour
# la source coupee qui vaut 0.0. `coupee` vide (aucune coupure) ne fait aucun cas
# particulier -- aucun nom de source ne peut valoir "". PURE.
static func niveaux_sources(config: Dictionary, coupee: String) -> Dictionary:
	var niveaux: Dictionary = {}
	for source in config.get("sources", []):
		var nom := String(source.nom)
		niveaux[nom] = 0.0 if nom == coupee else float(source.niveau)
	return niveaux

# Les colons, CONSTRUITS A LA MAIN (voir en-tete). 'poids_bonheur' est DUPLIQUE
# depuis la config (duplicate(true)) -- jamais partage avec le Dictionary du
# disque, meme precaution d'aliasing que banc_nutrition.gd:fabriquer_colon et
# banc_commun.gd:resoudre_chantier. Ni composition, ni materiau, ni
# 'temperature', ni aucune grandeur cumulee : toutes les autres entrees du
# catalogue PARTAGE de seuils sont des chemins morts pour eux.
static func construire_colons(config: Dictionary) -> Array:
	var colons: Array = []
	for decl in config.get("colons", []):
		var pos: Array = decl.position
		var proprietes: Dictionary = {
			"etats_actifs": [],
		}
		proprietes[String(config.nom_poids_bonheur)] = decl.get("poids_bonheur", {}).duplicate(true)
		proprietes[String(config.nom_vitesse)] = float(config.vitesse_base)
		proprietes[String(config.nom_rythme)] = float(config.rythme_base)
		colons.append({
			"id": String(decl.id),
			"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			"proprietes": proprietes,
		})
	return colons

# Le MONDE ecrit sur le colon : chaque source devient une propriete PLATE, au
# MEME niveau pour tous les colons. C'est ce qui rend la demonstration
# opposable -- rien dans le monde ne distingue les quatre. MUTE le colon en
# place, rend les niveaux poses. Les sources sont RECRITES a neuf chaque tick,
# jamais accumulees.
static func poser_sources(colon: Dictionary, config: Dictionary, coupee: String) -> Dictionary:
	var niveaux: Dictionary = niveaux_sources(config, coupee)
	for nom in niveaux:
		colon.proprietes[nom] = float(niveaux[nom])
	return niveaux

# LA SOMME PONDEREE. Lecture PURE : n'ecrit rien, ne mute rien -- `poser_bonheur`
# est le seul ecrivain. Boucle sur les poids DU COLON, jamais sur une liste de
# sources connue de ce fichier : un poids sur une source que le monde n'offre
# pas rend exactement 0.0 (`get(source, 0.0)`), sans alarme, par contrat.
static func calculer_bonheur(colon: Dictionary, config: Dictionary) -> float:
	var proprietes: Dictionary = colon.proprietes
	var poids: Dictionary = proprietes.get(String(config.nom_poids_bonheur), {})
	var bonheur := 0.0
	for source in poids:
		bonheur += float(poids[source]) * float(proprietes.get(String(source), 0.0))
	return bonheur

# UNIQUE ECRIVAIN de 'bonheur' ET de son miroir 'manque_bonheur' -- les deux
# dans le MEME geste, depuis le MEME nombre (voir en-tete, « UN SEUL
# ECRIVAIN »). MIROIR PLAT RECALCULE A NEUF, jamais un '+=' : c'est ce qui
# empeche le champ derive de deriver. Le manque est borne a 0.0 par le bas --
# une somme de poids superieure a la capacite ne donne pas un « manque
# negatif ». MUTE le colon en place ; rend { bonheur, manque } pour que
# l'affichage relise sans jamais rien recalculer.
static func poser_bonheur(colon: Dictionary, config: Dictionary) -> Dictionary:
	var bonheur: float = calculer_bonheur(colon, config)
	var manque: float = max(0.0, float(config.capacite_bonheur) - bonheur)
	colon.proprietes[String(config.nom_bonheur)] = bonheur
	colon.proprietes[String(config.nom_manque_bonheur)] = manque
	return {"bonheur": bonheur, "manque": manque}

# L'etat a AFFICHER quand plusieurs se chevauchent. seuil_etat.gd ne hierarchise
# jamais les etats entre eux (c'est ecrit dans son en-tete) : c'est a l'appelant
# de choisir. Ici le PLUS GRAVE gagne -- 'desespere' implique toujours
# 'malheureux', montrer l'orange plutot que le rouge mentirait sur la gravite.
# Meme geste que banc_changement_etat.gd:couleur_pour_etats (gaz priorise sur
# liquide). Rend "" quand aucun des trois n'est actif : le NEUTRE n'est pas un
# etat, c'est leur absence -- meme convention que 'solide' dans
# data/seuils_etat.json. PURE.
static func etat_dominant(colon: Dictionary, config: Dictionary) -> String:
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	for cle in ["etat_desespere", "etat_malheureux", "etat_heureux"]:
		var nom := String(config.get(cle, ""))
		if nom != "" and actifs.has(nom):
			return nom
	return ""

# Le compteur : combien de colons dans chaque etat dominant. La cle "" y compte
# les neutres, sans jamais inventer un nom d'etat pour eux. PURE.
static func compte_par_etat(colons: Array, config: Dictionary) -> Dictionary:
	var compte: Dictionary = {"": 0}
	for cle in ["etat_heureux", "etat_malheureux", "etat_desespere"]:
		compte[String(config.get(cle, ""))] = 0
	for colon in colons:
		var etat := etat_dominant(colon, config)
		compte[etat] = int(compte.get(etat, 0)) + 1
	return compte

# Toggle CYCLIQUE sur nb_sources + 1 etats : le dernier est AUCUNE COUPURE.
# PURE. Meme forme exacte que banc_nutrition.gd:repas_suivant.
static func source_suivante(selection: int, nb_sources: int) -> int:
	return (selection + 1) % (nb_sources + 1)

# Compare deux instantanes d'etats_actifs -- seuil_etat.gd rend les ids ayant
# bascule, jamais QUELS etats, d'ou cette comparaison cote cablage. PURE.
static func changements_etats(avant: Array, apres: Array) -> Dictionary:
	var gagnes: Array = []
	var perdus: Array = []
	for etat in apres:
		if not avant.has(etat):
			gagnes.append(String(etat))
	for etat in avant:
		if not apres.has(etat):
			perdus.append(String(etat))
	return {"gagnes": gagnes, "perdus": perdus}

# La vitesse de base modulee par TOUS les etats actifs -- etat_effectif.gd,
# composition multiplicative, jamais reimplementee ici.
static func vitesse_effective(colon: Dictionary, config: Dictionary, catalogue_etats: Dictionary) -> float:
	return EtatEffectif.valeur(colon, String(config.nom_vitesse), catalogue_etats)

# Meme geste sur 'rythme'. C'est la SEULE lecture composee de 'rythme' du depot :
# banc_commun.gd:agents_rythme, lui, lit la valeur BRUTE (voir en-tete, LIMITE
# DITE). Sans cette fonction, le facteur 1.1 de 'heureux' sur 'rythme' n'aurait
# aucun effet observable nulle part.
static func rythme_effectif(colon: Dictionary, config: Dictionary, catalogue_etats: Dictionary) -> float:
	return EtatEffectif.valeur(colon, String(config.nom_rythme), catalogue_etats)

# Les trois seuils vivent dans le catalogue PARTAGE data/seuils_etat.json,
# jamais recopies en donnee de banc : une seule source de verite, jamais deux
# nombres a garder d'accord (geste de banc_faim_thermo.gd:seuil_faim). Le banc ne
# les relit que pour son affichage -- c'est seuil_etat.gd, et lui seul, qui pose
# les etats. Entree absente : push_error et INF, l'affichage dira « jamais »
# plutot que de mentir.
static func seuil_de(catalogue_seuils: Dictionary, ref: String) -> float:
	if not catalogue_seuils.has(ref) or not catalogue_seuils[ref].has("seuil"):
		push_error("banc_bonheur : entree '%s' sans 'seuil' dans data/seuils_etat.json" % ref)
		return INF
	return float(catalogue_seuils[ref].seuil)

# ---- Textes (purs eux aussi -- aucun nombre n'y est recalcule) ----

static func texte_poids(colon: Dictionary, config: Dictionary) -> String:
	var poids: Dictionary = colon.proprietes.get(String(config.nom_poids_bonheur), {})
	var cles: Array = poids.keys()
	cles.sort()
	var morceaux: Array = []
	for cle in cles:
		morceaux.append("%s %.2f" % [String(cle), float(poids[cle])])
	return "  ".join(morceaux) if not morceaux.is_empty() else "-"

static func texte_sources(colon: Dictionary, noms: Array) -> String:
	var morceaux: Array = []
	for nom in noms:
		morceaux.append("%s %.2f" % [String(nom), float(colon.proprietes.get(String(nom), 0.0))])
	return "  ".join(morceaux)

static func texte_etats(colon: Dictionary) -> String:
	var noms: Array = []
	for etat in colon.proprietes.get("etats_actifs", []):
		noms.append(String(etat))
	noms.sort()
	return " + ".join(noms) if not noms.is_empty() else "neutre"

# La LIGNE DEDIEE, au-dessus des barres, ecrite en GROS et dans la couleur de
# l'etat dominant. Elle porte les DEUX etats quand l'escalier est franchi
# ('desespere + malheureux') alors que la COULEUR, elle, ne peut en montrer qu'un
# -- sans ce texte, le second etage serait invisible a l'ecran. La capacite n'y
# figure PAS : c'est le texte le plus large du banc, et elle est deja dans la
# ligne d'aide (les trois seuils) et dans chaque trace console.
static func texte_bonheur_etat(colon: Dictionary, config: Dictionary) -> String:
	return "bonheur %.3f   %s" % [
		float(colon.proprietes.get(String(config.nom_bonheur), 0.0)),
		texte_etats(colon),
	]

# Le poids de CE colon pour CETTE source, affiche a DROITE de sa barre. Une
# source que le colon ne valorise pas rend "-" et JAMAIS "x0.00" : les deux
# donnent bien 0.0 dans la somme (`get(source, 0.0)`, voir calculer_bonheur),
# mais « je n'y mets rien » et « j'y mets zero » ne se disent pas pareil, et
# c'est exactement ce que le banc existe pour rendre lisible.
static func texte_poids_source(colon: Dictionary, config: Dictionary, nom: String) -> String:
	var poids: Dictionary = colon.proprietes.get(String(config.nom_poids_bonheur), {})
	if not poids.has(nom):
		return "-"
	return "×%.2f" % float(poids[nom])

# La ligne du BAS, seule et sous le carre -- jamais melee aux sources (c'est la
# superposition que ce rendu corrige). Montre la BASE et l'EFFECTIF cote a cote :
# sans les deux, la modulation par l'etat (x1.1 heureux, x0.8 malheureux,
# x0.5 desespere) ne serait pas lisible, seul un nombre changerait sans reference.
static func texte_pied(colon: Dictionary, config: Dictionary, catalogue_etats: Dictionary) -> String:
	var proprietes: Dictionary = colon.proprietes
	return "vitesse %.1f->%.1f   rythme %.2f->%.2f" % [
		float(proprietes.get(String(config.nom_vitesse), 0.0)),
		vitesse_effective(colon, config, catalogue_etats),
		float(proprietes.get(String(config.nom_rythme), 0.0)),
		rythme_effectif(colon, config, catalogue_etats),
	]

static func texte_compteur(colons: Array, config: Dictionary, coupee: String, temps: float) -> String:
	var compte: Dictionary = compte_par_etat(colons, config)
	return "t=%.1f s -- source coupee : %s -- %s %d | neutre %d | %s %d | %s %d" % [
		temps,
		"aucune" if coupee == "" else coupee,
		String(config.etat_heureux), int(compte.get(String(config.etat_heureux), 0)),
		int(compte.get("", 0)),
		String(config.etat_malheureux), int(compte.get(String(config.etat_malheureux), 0)),
		String(config.etat_desespere), int(compte.get(String(config.etat_desespere), 0)),
	]

static func texte_aide(config: Dictionary, catalogue_seuils: Dictionary) -> String:
	return "clic gauche : coupe une source a tour de role, puis aucune -- les memes sources aux memes niveaux pour les quatre colons, seuls les poids different\nseuils partages : %s > %.2f | %s > %.2f | %s > %.2f" % [
		String(config.nom_bonheur), seuil_de(catalogue_seuils, String(config.ref_seuil_haut)),
		String(config.nom_manque_bonheur), seuil_de(catalogue_seuils, String(config.ref_seuil_bas)),
		String(config.nom_manque_bonheur), seuil_de(catalogue_seuils, String(config.ref_seuil_critique)),
	]

static func lignes_changement(t: float, id: String, changements: Dictionary) -> Array:
	var lignes: Array = []
	for etat in changements.get("gagnes", []):
		lignes.append("t=%.1f %s etat POSE : %s" % [t, id, String(etat)])
	for etat in changements.get("perdus", []):
		lignes.append("t=%.1f %s etat RETIRE : %s" % [t, id, String(etat)])
	return lignes

static func ligne_coupure(t: float, coupee: String) -> String:
	return "t=%.1f SOURCE COUPEE : %s" % [t, "aucune" if coupee == "" else coupee]

static func ligne_pose(config: Dictionary, colons: Array, catalogue_seuils: Dictionary) -> String:
	var morceaux: Array = []
	for colon in colons:
		morceaux.append("%s { %s }" % [String(colon.id), texte_poids(colon, config)])
	return "t=0.0 %d colons poses, memes sources pour tous, seuls les poids different -- %s\nseuils : %s > %.2f, %s > %.2f, %s > %.2f" % [
		colons.size(),
		" | ".join(morceaux),
		String(config.nom_bonheur), seuil_de(catalogue_seuils, String(config.ref_seuil_haut)),
		String(config.nom_manque_bonheur), seuil_de(catalogue_seuils, String(config.ref_seuil_bas)),
		String(config.nom_manque_bonheur), seuil_de(catalogue_seuils, String(config.ref_seuil_critique)),
	]

static func ligne_etat(t: float, colon: Dictionary, config: Dictionary, noms: Array, catalogue_etats: Dictionary) -> String:
	var proprietes: Dictionary = colon.proprietes
	return "t=%.1f %s | bonheur=%.3f manque=%.3f | etat=%s | vitesse=%.1f rythme=%.3f | %s" % [
		t,
		String(colon.id),
		float(proprietes.get(String(config.nom_bonheur), 0.0)),
		float(proprietes.get(String(config.nom_manque_bonheur), 0.0)),
		texte_etats(colon),
		vitesse_effective(colon, config, catalogue_etats),
		rythme_effectif(colon, config, catalogue_etats),
		texte_sources(colon, noms),
	]

# ---- Rendu (impur, Node) -- aucune decision, seulement des noeuds, des
# couleurs et des longueurs de barre.

func _couleur(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))

# UN BLOC PAR COLON, de haut en bas : nom -> ligne bonheur/etat -> les cinq
# barres (nom a GAUCHE, barre, poids a DROITE) -> le carre -> vitesse/rythme.
# Chaque morceau a sa ligne ; rien ne partage une zone avec rien.
#
# Les largeurs de colonne (largeur_legende / largeur_barre / largeur_poids) et
# l'espacement vertical entre barres viennent tous de data/banc_bonheur.json :
# aucun nombre de geometrie n'est en dur ici. La pile de barres se termine juste
# AU-DESSUS du carre et monte, si bien qu'ajouter une sixieme source en donnee
# repousse le haut du bloc sans jamais recouvrir quoi que ce soit.
func _creer_rendu() -> void:
	var taille: float = float(_config.taille_colon)
	var largeur: float = float(_config.largeur_barre)
	var hauteur: float = float(_config.hauteur_barre)
	var espacement: float = float(_config.espacement_barre)
	var largeur_legende: float = float(_config.largeur_legende)
	var largeur_poids: float = float(_config.largeur_poids)
	var marge: float = float(_config.marge_legende)
	var marge_bloc: float = float(_config.marge_bloc)
	var sources: Array = _config.get("sources", [])

	for colon in _colons:
		var centre := Vector2(colon.position.x, colon.position.y)
		var x_barre: float = centre.x - largeur / 2.0
		var x_bloc: float = x_barre - marge - largeur_legende
		var largeur_bloc: float = largeur_legende + marge + largeur + marge + largeur_poids
		# Le centre du BLOC, pas celui de la barre : le bloc est asymetrique
		# (legende large a gauche, poids etroit a droite), et centrer le nom sur
		# la barre le ferait pencher.
		var centre_bloc: float = x_bloc + largeur_bloc / 2.0
		_centres_bloc[colon.id] = centre_bloc

		var carre := ColorRect.new()
		carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
		carre.size = Vector2(taille, taille)
		carre.position = centre - carre.size / 2.0
		add_child(carre)
		_noeuds_colons[colon.id] = carre

		# Les barres de source, empilees AU-DESSUS du carre, dans l'ordre declare
		# en donnee (le meme que celui du cycle du clic). Chaque barre a un fond
		# fixe (la longueur max) et une barre de remplissage, seule a changer de
		# taille -- meme patron que banc_nutrition.gd:_creer_barre.
		var y_barres: float = centre.y - taille / 2.0 - marge_bloc - float(sources.size()) * espacement
		var barres: Dictionary = {}
		var poids: Dictionary = {}
		var rang := 0
		for source in sources:
			var nom := String(source.nom)
			var y: float = y_barres + float(rang) * espacement
			_creer_barre(_couleur(_config.couleur_fond_barre), Vector2(x_barre, y), largeur, hauteur)
			barres[nom] = _creer_barre(_couleur(source.couleur), Vector2(x_barre, y), 0.0, hauteur)
			# Le nom de la source a GAUCHE, cale a DROITE contre sa barre ; le
			# poids a DROITE, cale a GAUCHE contre elle. Les deux sont centres
			# verticalement sur la barre, jamais poses en dessous.
			_creer_label(int(_config.taille_police_legende), Vector2(x_bloc, y), largeur_legende,
				HORIZONTAL_ALIGNMENT_RIGHT, hauteur).text = nom
			poids[nom] = _creer_label(int(_config.taille_police_poids),
				Vector2(x_barre + largeur + marge, y), largeur_poids, HORIZONTAL_ALIGNMENT_LEFT, hauteur)
			rang += 1
		_barres_sources[colon.id] = barres
		_labels_poids[colon.id] = poids

		# Ligne bonheur/etat, puis le nom encore au-dessus. Les deux sont recentres
		# a la main (voir _centrer) : leur texte change de longueur, et une boite
		# de largeur fixe laisserait Godot rendre la largeur au minimum du texte,
		# ce qui decalerait le centrage au lieu de le tenir.
		var y_bonheur: float = y_barres - marge_bloc - _hauteur_ligne(int(_config.taille_police_bonheur))
		_labels_bonheur[colon.id] = _creer_label(int(_config.taille_police_bonheur),
			Vector2(x_bloc, y_bonheur), largeur_bloc, HORIZONTAL_ALIGNMENT_LEFT,
			_hauteur_ligne(int(_config.taille_police_bonheur)))

		var y_nom: float = y_bonheur - marge_bloc / 2.0 - _hauteur_ligne(int(_config.taille_police_nom))
		var label_nom := _creer_label(int(_config.taille_police_nom), Vector2(x_bloc, y_nom),
			largeur_bloc, HORIZONTAL_ALIGNMENT_LEFT, _hauteur_ligne(int(_config.taille_police_nom)))
		label_nom.text = String(colon.id)
		_centrer(label_nom, centre_bloc)

		# Vitesse et rythme, SOUS le carre et seuls sur leur ligne.
		var y_pied: float = centre.y + taille / 2.0 + marge_bloc
		_labels_pied[colon.id] = _creer_label(int(_config.taille_police_pied),
			Vector2(x_bloc, y_pied), largeur_bloc, HORIZONTAL_ALIGNMENT_LEFT,
			_hauteur_ligne(int(_config.taille_police_pied)))

	var couche := CanvasLayer.new()
	add_child(couche)
	_label_compteur = _creer_label_fixe(int(_config.taille_police_compteur), Vector2(10.0, 10.0))
	couche.add_child(_label_compteur)
	_label_aide = _creer_label_fixe(int(_config.taille_police_label), Vector2(10.0, 40.0))
	couche.add_child(_label_aide)
	_label_aide.text = texte_aide(_config, _catalogue_seuils)

# La hauteur d'une ligne de texte pour une police donnee. Un seul facteur, ici,
# plutot qu'une hauteur de ligne de plus a tenir d'accord en donnee pour chaque
# police : les cinq tailles de ce banc suivent toutes la meme regle.
func _hauteur_ligne(taille_police: int) -> float:
	return float(taille_police) * 1.5

# Un label de bloc (dans le monde, il suit donc la camera -- a la difference de
# _creer_label_fixe, qui vit sur le CanvasLayer et ne bouge jamais).
func _creer_label(taille_police: int, origine: Vector2, largeur: float,
		alignement: int, hauteur: float) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille_police)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = alignement
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = origine
	add_child(label)
	label.size = Vector2(largeur, hauteur)
	return label

# Recentre un label sur x APRES que son texte a change. Godot ramene la largeur
# d'un Control libre a sa taille minimale des que le texte la depasse : une boite
# large + HORIZONTAL_ALIGNMENT_CENTER ne tient donc PAS le centrage pour un texte
# de longueur variable (« bonheur 0.000   desespere + malheureux » est deux fois
# plus long que « bonheur 0.880   heureux »). On mesure et on pose.
func _centrer(label: Label, centre_x: float) -> void:
	var largeur: float = label.get_minimum_size().x
	label.size.x = largeur
	label.position.x = centre_x - largeur / 2.0

func _creer_label_fixe(taille: int, position_ecran: Vector2) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	label.position = position_ecran
	return label

func _creer_barre(couleur: Color, origine: Vector2, largeur: float, hauteur: float) -> ColorRect:
	var barre := ColorRect.new()
	barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barre.color = couleur
	barre.position = origine
	barre.size = Vector2(largeur, hauteur)
	add_child(barre)
	return barre

func _rafraichir_tout() -> void:
	var largeur: float = float(_config.largeur_barre)
	var hauteur: float = float(_config.hauteur_barre)
	var coupee := _nom_source_coupee()

	for colon in _colons:
		var etat := etat_dominant(colon, _config)
		var rgb: Array = _config.couleurs_etat.get(etat, _config.couleur_neutre) if etat != "" \
			else _config.couleur_neutre
		var couleur_etat := _couleur(rgb)
		_noeuds_colons[colon.id].color = couleur_etat

		# La ligne bonheur porte la MEME couleur que le carre : deux lectures du
		# meme etat, jamais deux sources de verite -- couleur_etat est calculee
		# une fois et posee aux deux endroits.
		var label_bonheur: Label = _labels_bonheur[colon.id]
		label_bonheur.text = texte_bonheur_etat(colon, _config)
		label_bonheur.add_theme_color_override("font_color", couleur_etat)
		_centrer(label_bonheur, float(_centres_bloc[colon.id]))

		var barres: Dictionary = _barres_sources[colon.id]
		var poids: Dictionary = _labels_poids[colon.id]
		for source in _config.get("sources", []):
			var nom := String(source.nom)
			var niveau: float = float(colon.proprietes.get(nom, 0.0))
			var barre: ColorRect = barres[nom]
			barre.size = Vector2(largeur * clamp(niveau, 0.0, 1.0), hauteur)
			# Une source coupee ne disparait pas : sa barre passe au rouge sombre
			# a longueur nulle, et le fond reste. Sans ca, « coupee » et « nulle
			# par hasard » seraient indistinguables a l'ecran.
			barre.color = _couleur(_config.couleur_source_coupee) if nom == coupee else _couleur(source.couleur)
			poids[nom].text = texte_poids_source(colon, _config, nom)

		var label_pied: Label = _labels_pied[colon.id]
		label_pied.text = texte_pied(colon, _config, _catalogue_etats)
		_centrer(label_pied, float(_centres_bloc[colon.id]))

	_label_compteur.text = texte_compteur(_colons, _config, coupee, _temps)

func _poser_camera() -> void:
	var decl: Dictionary = _config.get("camera", {})
	var pos: Array = decl.get("position", [0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(float(pos[0]), float(pos[1]))
	camera.zoom = Vector2(float(decl.get("zoom", 1.0)), float(decl.get("zoom", 1.0)))
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
