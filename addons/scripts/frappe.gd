extends RefCounted

# Mecanisme du coeur, CINQUIEME nature d'effet (evenement ponctuel par
# selection) -- voir docs/design.md, « Direction majeure » (quatre natures
# deja nommees : lecture pure, ecriture differee irreversible, transfert
# continu, seuil reversible ; aucune ne couvre selectionner UNE cible puis
# appliquer un effet immediat et permanent sans accumulation prealable).
# Audit prealable : audit_foudre_prealable.md.
#
# RefCounted SANS ETAT, fonctions static PURES -- meme gabarit que
# quantite_matiere.gd/combustible.gd (extraction etroite, aucun etat,
# aucun chargement de fichier). N'appartient a AUCUN pipeline de decision
# (perception/saillance/dominance/agir) : un evenement environnemental qui
# frappe n'importe quel objet physique du monde, jamais ce qu'UN colon
# percoit -- contrairement a dominance.gd:visibles (qui suppose
# proprietes.forme sur un colon), ce fichier ne lit ni ne suppose jamais
# de colon.
#
# Porte deux gestes disjoints, jamais composes en une seule fonction :
# QUI est frappe (selectionner, lecture pure) et QUOI la frappe change
# (frapper, une mutation trivale sur une reserve nommee). Aucun des deux
# ne decide QUAND frapper ni QUELLE source de chaleur produire -- ca reste
# au cablage de banc (voir scripts/banc_foudre.gd), meme separation que
# soudure.gd (DETECTION/DECLENCHEMENT hors du mecanisme).
#
# NE FAIT PAS, et ces quatre frontieres sont a connaitre avant de cabler :
# - il ne connait AUCUNE notion de cible « deja detruite » -- l'eligibilite
#   des candidats est filtree par l'APPELANT, avant l'appel ;
# - il ne produit ni chaleur, ni lumiere, ni son : un evenement frappe, ses
#   consequences sensorielles sont posees par le cablage ;
# - il ne MONTE jamais aucune propriete -- un cumul de degats subis s'ecrit
#   au cablage, ce fichier ne fait que soustraire ;
# - DEUX SOURCES DE CRITERE, ET DEUX SEULEMENT (voir selectionner) : une
#   propriete MATERIAU ponderee par volume, ou la hauteur. Une source
#   « propriete plate » (lire directement proprietes.<nom>) N'EXISTE PAS,
#   et l'ajouter serait modifier le coeur, donc un chantier de framework --
#   jamais un ajout au passage dans un cablage qui en aurait besoin.

const Portee = preload("res://scripts/portee.gd")
const QuantiteMatiere = preload("res://scripts/quantite_matiere.gd")

# selectionner(objets, position_source, rayon, criteres, materiaux) -> Dictionary
#
# Parcourt "objets" (Array de { id, position, proprietes }) et ne retient
# que ceux A PORTEE de "position_source" (Portee.en_portee -- meme fonction
# partagee que les cinq mecanismes de « Direction majeure », attaches.gd/
# propagation.gd/flux.gd/extinction.gd/charge.gd). Aucun objet a portee :
# rend {} (CHEMIN MORT, meme convention que quantite_matiere.gd sur
# "composition" absente).
#
# Chaque objet a portee recoit un SCORE COMPOSITE, somme ponderee de
# "criteres" (Array de Dictionary { propriete: String, poids: float,
# source: String }) :
# - source "materiau" : QuantiteMatiere.quantite(objet.proprietes,
#   propriete, materiaux) -- quantite de matiere PONDEREE PAR VOLUME, deja
#   extensive (voir quantite_matiere.gd), jamais reimplementee ici.
# - source "position_z" : objet.position.z directement (hauteur -- "propriete"
#   du critere est ignoree pour cette source, il n'y a rien d'autre a lire
#   qu'un scalaire deja present sur l'objet).
# - toute autre valeur de "source" : push_error nommant la source inconnue,
#   ce critere contribue 0.0 au score, les autres criteres continuent
#   (meme severite qu'un materiau absent dans quantite_matiere.gd -- une
#   entree malformee n'invalide jamais le reste du calcul).
#
# Rend l'objet au SCORE LE PLUS HAUT parmi ceux a portee -- idiome
# MAX-REDUCTION de dominance.gd:visibles (sommet = max(sommet, ...)),
# repris ici sur des objets plutot que sur des saillances. EGALITE STRICTE
# au sommet : NON TRANCHE -- garde le PREMIER trouve dans l'ordre
# d'iteration d'"objets", mais ALARME (push_error nommant les ids a
# egalite et le score) -- meme convention que agir.gd:_verbe_par_poids sur
# une egalite stricte au poids maximum : on ne tranche pas, on refuse le
# silence.
static func selectionner(objets: Array, position_source: Vector3, rayon: float, criteres: Array, materiaux: Dictionary) -> Dictionary:
	var candidats: Array = []
	for objet in objets:
		if Portee.en_portee(position_source, objet.position, rayon):
			candidats.append(objet)
	if candidats.is_empty():
		return {}

	var meilleur: Dictionary = candidats[0]
	var meilleur_score := _score(meilleur, criteres, materiaux)
	for i in range(1, candidats.size()):
		var objet: Dictionary = candidats[i]
		var score := _score(objet, criteres, materiaux)
		if score > meilleur_score:
			meilleur_score = score
			meilleur = objet

	var a_egalite: Array = []
	for objet in candidats:
		if is_equal_approx(_score(objet, criteres, materiaux), meilleur_score):
			a_egalite.append(objet.get("id", "?"))
	if a_egalite.size() > 1:
		push_error("frappe.gd : objets a egalite stricte au score maximum (%s) : %s -- '%s' conserve (premier trouve), aucun departage" % [meilleur_score, a_egalite, meilleur.get("id", "?")])
	return meilleur

static func _score(objet: Dictionary, criteres: Array, materiaux: Dictionary) -> float:
	var total := 0.0
	for critere in criteres:
		var source: String = critere.get("source", "")
		var poids: float = critere.get("poids", 0.0)
		var valeur := 0.0
		if source == "materiau":
			valeur = QuantiteMatiere.quantite(objet.proprietes, critere.get("propriete", ""), materiaux)
		elif source == "position_z":
			valeur = objet.position.z
		else:
			push_error("frappe.gd : source de critere inconnue '%s' (attendu 'materiau' ou 'position_z'), critere ignore" % source)
			continue
		total += valeur * poids
	return total

# frapper(cible, degats, nom_reserve) -> Dictionary
#
# Soustrait "degats" (float, jamais un delta -- l'appelant fournit une
# quantite DEJA une fois pour toutes, pas un taux) de proprietes.reserves.
# <nom_reserve>.reserve, BORNEE A ZERO (max(0.0, ...) -- meme doctrine que
# depense.gd, "Dependance : reserve bornee a zero"). ECRITURE DIRECTE,
# jamais via Depense.avancer (structurellement CONTINU, dependant de
# "delta" -- un degat INSTANTANE n'a pas de delta a lui donner sans
# detourner sa semantique, voir audit_foudre_prealable.md §3).
#
# STRUCTUREL : "nom_reserve" absent de proprietes.reserves -- l'objet recu
# n'a jamais eu cette reserve a frapper, ceci n'est pas une intention
# legitime (cible mal cablee, jamais un point neutre) -- push_error
# nommant la reserve et l'id, cible rendue INCHANGEE (meme severite qu'une
# reference structurelle absente ailleurs dans le depot).
#
# Rend "cible" -- MEME REFERENCE, mutee en place (meme convention que
# champ.gd/charge.gd), jamais une copie.
static func frapper(cible: Dictionary, degats: float, nom_reserve: String) -> Dictionary:
	var reserves: Dictionary = cible.proprietes.get("reserves", {})
	if not reserves.has(nom_reserve):
		push_error("frappe.gd : reserve '%s' absente de proprietes.reserves sur '%s' -- rien frappe" % [nom_reserve, str(cible.get("id", "?"))])
		return cible
	var canal: Dictionary = reserves[nom_reserve]
	canal["reserve"] = max(0.0, canal.get("reserve", 0.0) - degats)
	return cible
