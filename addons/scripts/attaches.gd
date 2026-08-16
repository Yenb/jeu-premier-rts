extends RefCounted

# Couche 2 (saillance) : etat de menace des attaches d'un colon.
#
# Entree : perceptions (Array de { chose, type, position, distance }),
# colon ({ proprietes: { attaches, forme }, ... }), menaces (Dictionary
# issu de data/menaces.json, { propriete_vulnerabilite: propriete_menace }).
# attaches et forme sont STRUCTURELLES : leur cle absente de proprietes
# signifie que l'objet recu n'est pas fait pour porter des attaches --
# push_error (log visible, ne bloque jamais le processus) puis retour
# neutre ([]), jamais un defaut silencieux. Une liste d'attaches vide
# ([]) ou une forme vide ({}) restent legitimes : c'est la cle elle-meme
# qui doit exister, pas son contenu qui doit etre plein.
# Sortie : Array de { type, attache, menace, saillance }, une entree PAR
# ATTACHE du colon -- menacee OU intacte, jamais absente. Deux effets pour
# une seule attache (voir docs/design.md, "Le modele : attaches et forme") :
# attache intacte (menace <= 0) -> saillance BASSE, familiarite -- l'attache
# vit dans la routine, pas seulement dans la crise ; attache menacee
# (menace > 0) -> saillance HAUTE. Les deux valeurs different toujours
# (voir deformer) : dominance.gd peut donc s'appuyer sur le nombre seul,
# sans jamais avoir a distinguer une routine d'une absence. Le
# champ "type" du resultat porte attache.propriete (ex. "vegetal") --
# jamais un nom de type. Le nom de cle "type" est impose par agir.gd
# (inertie + catalogue d'actions), volontairement pas touche : il traite
# ce champ comme un jeton opaque, peu importe qu'il porte un nom de trait
# ou un nom de type.
#
# Attache : { "propriete": String, "force": float }. Idee et vecu
# remplissent le meme seau ; le moteur ne sait pas d'ou elle vient.
# Le lien d'attachement se fait par PROPRIETE (proprietes.get(attache.
# propriete), voir menace_attache) : c'est ce a quoi le colon tient, un
# TRAIT, jamais un nom de type. Une chose qu'on n'a pas encore imaginee
# peut porter ce trait et etre defendue sans une ligne de code (voir
# docs/design.md, TRAIT vs IDENTITE).
#
# "forme" (le mot "trait" est reserve en GDScript) ne cree ni ne
# transforme les attaches : elle deforme leur rayon de liaison et
# la hauteur de leur saillance. Immuable, sans contenu.
#
# Le monde n'emet aucun drapeau "menace". Le colon fait le lien
# lui-meme, par PROPRIETE, jamais par nom : l'objet auquel il tient
# porte une propriete de vulnerabilite (ex. inflammable) ; il est
# menace si une chose portant la propriete de menace correspondante
# (ex. brule) est a proximite EN ESPACE (jamais par rapport au colon).
# Les couples vulnerabilite/menace viennent de menaces.json ; le moteur
# ne connait en dur aucun nom de type ni de propriete. Le test "a portee"
# delegue a scripts/portee.gd:en_portee (seule part partagee avec
# propagation.gd/flux.gd/extinction.gd/charge.gd, voir son en-tete et
# docs/design.md "Direction majeure" -- la fusion des cinq mecanismes
# elle-meme est ABANDONNEE, ce fichier garde sa propre boucle).
#
# Une chose peut etre SA PROPRE menace (un arbre inflammable qui porte
# deja brule -- il brule lui-meme) : menace_attache() ne l'exclut plus
# de son propre calcul (FERME, voir CARTE.md §6 -- l'exclusion via
# is_same() etait un pansement, pas une regle) -- la distance d'une
# chose a elle-meme est 0, donc son poids de menace est TOUJOURS maximal
# (1.0), qu'elle soit ou non a portee d'une autre source. Une attache sur
# une chose qui brule deja doit rendre une saillance haute, jamais nulle.
#
# LECTURE DE LA DEFORMATION DU COLON (PHASE 4bis chantier A, patron copie
# depuis scripts/proximite.gd:_appliquer_deformation, voir CARTE.md §2
# proximite.gd -- "PATRON A COPIER"). Difference avec proximite.gd : une
# attache ne connait aucune identite de CHOSE distincte -- ce a quoi le
# colon tient est une PROPRIETE (attache.propriete), jamais un objet percu
# precis. La "cible" de la deformation est donc directement
# attache.propriete : apres le calcul de la saillance NUE (deformer()),
# pour chaque source que porte colon.proprietes.deformation_etat dont la
# cible-map contient attache.propriete,
# Deformation.biais(colon, source, attache.propriete, catalogue_deformations)
# rend un facteur applique MULTIPLICATIVEMENT -- "baisse" (habituation) =>
# saillance *= (1.0 - biais) ; "monte" => saillance *= (1.0 + biais).
# Plusieurs sources se composent EN SEQUENCE, jamais additivement -- meme
# principe que proximite.gd et docs/design.md, "Lecture des calques :
# composition multiplicative".
#
# colon.proprietes.deformation_etat est FACULTATIVE ICI (contrairement a
# deformation.gd, ou la meme cle est STRUCTURELLE) -- meme precedent que
# proximite.gd/agir.gd:_score : son absence dit juste "aucune donnee de
# deformation disponible", saillance rendue inchangee, jamais une alarme.
# catalogue_deformations (data/deformations.json) est FACULTATIF (defaut
# {}), meme convention que "catalogue" dans proximite.gd.

const Deformation = preload("res://scripts/deformation.gd")
const Portee = preload("res://scripts/portee.gd")

static func evaluer(
	perceptions: Array,
	colon: Dictionary,
	menaces: Dictionary,
	catalogue_deformations: Dictionary = {},
) -> Array:
	var proprietes: Dictionary = colon.get("proprietes", {})
	if not proprietes.has("attaches"):
		push_error("attaches.gd : propriete structurelle 'attaches' absente de proprietes")
		return []
	if not proprietes.has("forme"):
		push_error("attaches.gd : propriete structurelle 'forme' absente de proprietes")
		return []
	var forme: Dictionary = proprietes.forme
	var resultats: Array = []
	for attache in proprietes.attaches:
		var menace := menace_attache(attache, menaces, perceptions, forme)
		var saillance := deformer(menace, attache, forme)
		saillance = _appliquer_deformation(colon, attache.propriete, saillance, catalogue_deformations)
		resultats.append({
			"type": attache.propriete,
			"attache": attache,
			"menace": menace,
			"saillance": saillance,
		})
	return resultats

# Applique le biais de deformation du COLON a la saillance NUE d'une
# attache -- voir en-tete. Ne mute rien (Deformation.biais est pure), rend
# juste le nombre module. "propriete_attache" tient lieu de "cible" : c'est
# la seule identite que porte une attache, contrairement a une chose
# percue par proximite.gd.
static func _appliquer_deformation(
	colon: Dictionary,
	propriete_attache: String,
	saillance: float,
	catalogue_deformations: Dictionary,
) -> float:
	var deformation: Dictionary = colon.get("proprietes", {}).get("deformation_etat", {})
	for source in deformation:
		if not deformation[source].has(propriete_attache):
			continue
		var biais: float = Deformation.biais(colon, source, propriete_attache, catalogue_deformations)
		var sens: String = catalogue_deformations.get(source, {}).get("sens", "")
		if sens == "baisse":
			saillance *= (1.0 - biais)
		elif sens == "monte":
			saillance *= (1.0 + biais)
	return saillance

static func menace_attache(
	attache: Dictionary,
	menaces: Dictionary,
	perceptions: Array,
	forme: Dictionary,
) -> float:
	var rayon: float = forme.get("rayon_liaison", 0.0)
	var menace := 0.0
	for instance in perceptions:
		var proprietes: Dictionary = instance.chose.proprietes
		if not proprietes.get(attache.propriete, false):
			continue
		for vuln in menaces:
			if not proprietes.get(vuln, false):
				continue
			var prop_menace = menaces[vuln]
			for autre in perceptions:
				if not autre.chose.proprietes.get(prop_menace, false):
					continue
				if not Portee.en_portee(instance.position, autre.position, rayon):
					continue
				var d: float = instance.position.distance_to(autre.position)
				var poids := (1.0 - d / rayon) if rayon > 0.0 else 1.0
				menace = max(menace, poids)
	return clamp(menace, 0.0, 1.0)

# Deux branches, symetriques, lues sur la meme "forme" -- voir
# docs/design.md, "Le modele : attaches et forme", "Deux effets pour une
# seule attache". menace <= 0.0 (attache intacte, routine) : saillance
# BASSE, "gain_bas"/"plafond_bas" (retablis ici -- avaient ete retires
# quand evaluer() filtrait les attaches intactes avant tout appel a
# deformer ; evaluer() n'exclut plus rien, voir plus haut). menace > 0.0
# (attache menacee, crise) : saillance HAUTE, "gain_haut"/"plafond_haut",
# inchangee. Le plancher "+1.0" de la branche haute garantit que toute
# menace strictement positive rend une saillance strictement superieure
# a "plafond_bas" par defaut (0.5 < 1.0) -- les deux branches ne se
# chevauchent jamais sans que la donnee ne le decide explicitement.
static func deformer(
	menace: float,
	attache: Dictionary,
	forme: Dictionary,
) -> float:
	if menace <= 0.0:
		var gain_bas: float = forme.get("gain_bas", 0.1)
		var plafond_bas: float = max(forme.get("plafond_bas", 0.5), 0.0)
		var brut_bas: float = attache.force * gain_bas
		return clamp(brut_bas, 0.0, plafond_bas)
	var gain: float = forme.get("gain_haut", 1.0)
	var plafond: float = max(forme.get("plafond_haut", 1.0), 1.0)
	var brut: float = 1.0 + attache.force * menace * gain
	return clamp(brut, 1.0, plafond)
