extends RefCounted

# Mecanisme du coeur : ATTENTE SUR SEUIL LU A LA POSITION. Tient un
# registre d'entrees LATENTES, chacune portant au moins une position
# (Vector3) et des donnees libres que ce fichier ne lit jamais. A
# chaque appel a avancer(), pour chaque entree, un moyen de lecture
# fourni par l'appelant (un Callable qui recoit la position et rend un
# float) donne la valeur observee a cette position ; cette valeur est
# comparee a un seuil selon un sens (au-dessus/en-dessous, strict).
# Rend les entrees dont la comparaison est vraie ce passage --
# DECLAREES REALISABLES, jamais FABRIQUEES : ce fichier ne fait
# naitre rien, ne mute aucune de ses entrees, ne les retire pas
# automatiquement. Meme discipline que gestation.gd : pose un signal
# (ici : la selection dans le retour), laisse l'appelant consommer
# (retirer l'entree, produire l'objet du monde).
#
# GENERIQUE : ce fichier ne connait ni "graine", ni "arbre", ni
# "foret", ni "densite", ni aucun nom de contenu. Un test hors
# domaine (scripts/test_attente_seuil.gd) exerce le mecanisme sur
# des nombres nus, sans le moindre concept du monde, pour prouver
# qu'aucun contenu ne s'y est glisse.
#
# STATEFUL, PAS STATIC : contrairement a gestation.gd/seuil_etat.gd/
# charge.gd/conditions.gd (tous static), ce fichier TIENT une
# collection -- une instance par registre. new() est le point
# d'entree, chaque instance vit tant que son appelant la reference.
#
# API :
#   ajouter(entree: Dictionary) -> int
#     Enregistre une entree. Exige au moins la cle "position"
#     (Vector3). Toute autre cle est libre et OPAQUE : ce fichier
#     ne la lit ni ne la mute jamais -- elle voyage telle quelle,
#     rendue a l'appelant dans avancer(). Rend l'INDEX interne de
#     l'entree (utilisable ensuite par retirer()). Une entree sans
#     "position" ou dont "position" n'est pas un Vector3 : push_error,
#     rien enregistre, rend -1.
#
#   avancer(lire_valeur: Callable, seuil: float, sens: String) -> Array
#     Pour chaque entree du registre, appelle lire_valeur.call(entree.
#     position) qui doit rendre un float. Compare a seuil selon sens :
#       "au_dessus" -> valeur > seuil (strict, meme convention que
#                      charge.gd et seuil_etat.gd)
#       "en_dessous" -> valeur < seuil (strict, symetrique)
#     Rend un Array de Dictionary { "index": int, "entree": Dictionary,
#     "valeur": float } pour chaque entree dont la comparaison est
#     vraie -- une COPIE PROFONDE du dict entree, pour que la mutation
#     eventuelle par l'appelant n'affecte pas le registre. NE RETIRE
#     RIEN, ne mute rien : la meme entree peut redevenir realisable a
#     un appel ulterieur, ou etre volontairement gardee latente par
#     l'appelant.
#     "sens" different de "au_dessus" ou "en_dessous" : push_error,
#     rend [] (jamais un defaut permissif).
#
#   retirer(index: int) -> void
#     Retire l'entree d'index donne. Meme geste que l'appelant fait
#     sur gestation apres consommation. Index hors bornes : push_error,
#     rien mute.
#
#   prospects() -> Array
#     Rend l'Array interne des entrees encore latentes (lecture, non
#     duplique -- consommateur ne doit pas muter la structure).
#
#   nombre() -> int
#     Rend le nombre d'entrees latentes.
#
# LATENCE PROPREMENT DITE : la SELECTION dans le retour d'avancer()
# ne retire pas l'entree du registre. C'est l'appelant qui decide --
# il peut retirer immediatement (usage typique : realisation
# ponctuelle, meme geste que gestation) ou laisser latent (usage
# typique : un candidat qui redevient realisable a chaque cycle
# tant qu'aucune ressource n'est libre pour le materialiser). Ce
# fichier ne prend jamais cette decision.
#
# ORDRE DE RETRAIT PAR INDEX : retirer(index) utilise remove_at,
# qui decale les indices des entrees suivantes. Un appelant qui
# consomme plusieurs realisables en un passage doit donc les
# retirer PAR INDEX DECROISSANT (ou dupliquer la liste et retirer
# a la volee) -- convention Godot standard, laissee a l'appelant
# comme dans monde.gd:retirer.
#
# VERTICALITE : position en Vector3 strict, jamais Vector2 (regle
# du depot -- meme si Z reste a zero pour un usage donne, la
# signature ne se replie pas).
#
# AUCUN HASARD : ce fichier ne tire jamais rien. Les choix (seuil,
# sens, moyen de lecture) sont fournis par l'appelant.
#
# TOURNE SANS RENDU : aucune reference a un noeud, a un materiau,
# a une scene. Testable headless.
#
# ECART AVEC LE DEPOT FRAMEWORK : ce mecanisme n'existe pas dans le
# depot framework (Orion) et est cree dans cette copie parce qu'il
# manquait au jeu et bloquait un chantier gameplay -- exception
# actee par Yael, meme geste doctrinal que scripts/monde.gd:retirer
# (premier precedent d'un ecart trace dans le fichier lui-meme). La
# fiche CARTE.md correspondante est un ajout a faire cote depot
# framework, pas ici (documents/ est lecture seule).


var _prospects: Array = []


func ajouter(entree: Dictionary) -> int:
	if not entree.has("position"):
		push_error("attente_seuil.gd : ajouter() -- entree sans 'position'")
		return -1
	if not (entree.position is Vector3):
		push_error("attente_seuil.gd : ajouter() -- 'position' n'est pas un Vector3")
		return -1
	_prospects.append(entree)
	return _prospects.size() - 1


func avancer(lire_valeur: Callable, seuil: float, sens: String) -> Array:
	if sens != "au_dessus" and sens != "en_dessous":
		push_error("attente_seuil.gd : avancer() -- sens inconnu '%s' (attendu 'au_dessus' ou 'en_dessous')" % sens)
		return []
	var realisables: Array = []
	for index in range(_prospects.size()):
		var entree: Dictionary = _prospects[index]
		var valeur: float = float(lire_valeur.call(entree.position))
		var vrai := false
		if sens == "au_dessus":
			vrai = valeur > seuil
		else:
			vrai = valeur < seuil
		if vrai:
			realisables.append({
				"index": index,
				"entree": entree.duplicate(true),
				"valeur": valeur,
			})
	return realisables


func retirer(index: int) -> void:
	if index < 0 or index >= _prospects.size():
		push_error("attente_seuil.gd : retirer() -- index %d hors bornes (taille %d)" % [index, _prospects.size()])
		return
	_prospects.remove_at(index)


func prospects() -> Array:
	return _prospects


func nombre() -> int:
	return _prospects.size()
