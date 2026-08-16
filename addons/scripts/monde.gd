extends RefCounted

# Le contenant de monde du banc : fournit la requete spatiale
# choses_dans_rayon() dont perception.gd a besoin. _monde (banc_p1.gd) EST
# une instance de cette classe (chantier "_monde porte la requete
# spatiale", CARTE.md §6, FERME) -- ce n'est pas un echafaudage a cote du
# vrai monde, c'est le mecanisme reellement utilise en jeu. Sert aussi de
# fixture legere dans les tests (test_perception.gd, test_monde.gd,
# test_banc_p1.gd) qui n'ont pas besoin du reste du banc.
#
# Regles : test de DISTANCE seul -- aucune occlusion, aucune ligne de vue,
# aucune notion d'opaque. Ce n'est pas un manque : l'occlusion depend du
# CANAL interroge (un mur arrete la vue, pas le son), notion qu'un contenant
# spatial n'a aucune raison de connaitre -- elle vit dans occlusion.gd et
# chez ses appelants.
# COUT LINEAIRE par requete (balayage de toutes les choses) : signale, jamais
# contourne en silence. Un appelant qui interroge n points paie O(n * choses).
#
# AUCUNE FONCTION DE RETRAIT, ET IL N'EN FAUT PAS : ce contenant se construit,
# il ne s'amende pas. Pourquoi, et comment un cablage s'en sert :
# banc_commun.gd:monde_depuis, seul endroit du depot ou un Monde naisse pour
# un banc.
# CE QU'IL RESTE A SAVOIR ICI : rien ne supprime une entree de `choses` en
# place. Une chose laissee dans la liste y reste, `proprietes` eventuellement
# videe -- inoffensif tant que chaque mecanisme lit par .get(cle, defaut),
# DANGEREUX des qu'un mecanisme traite une propriete comme STRUCTURELLE sur
# chaque chose du monde : un fantome non filtre alarme alors INDEFINIMENT, a
# chaque tick.
#
# choses : Dictionary indexe PAR ID (id -> { chose, type }), pas un Array --
# permet l'acces direct par_id() ci-dessous, impossible sur un Array sans
# tenir un index separe a cote. L'ordre d'insertion est preserve (Dictionary
# GDScript), donc un appelant qui n'a besoin que de l'ordre d'ajout le
# retrouve tel quel ; un appelant qui veut les choses nues doit iterer
# `choses.values()` -- hors perimetre de ce fichier,
# recense ailleurs (CARTE.md §6) pour l'etape suivante.
#
# ajouter(chose, type, position) : enregistre `{ chose, type }` sous la cle
# `chose.id`, mute `choses` en place. L'argument `position` n'est PAS stocke
# -- la position est toujours relue depuis `chose.position` au moment de la
# requete (choses_dans_rayon), jamais figee a l'ajout : une chose qui
# bouge apres son ajout (colon.position reassigne a chaque tick, voir
# banc_p1.gd:_faire_agir_colon) reste trouvable a sa position VIVANTE.
# CONSEQUENCE POUR TOUT MECANISME QUI VISE : il vise la chose LA OU ELLE EST
# MAINTENANT, jamais ou elle etait -- viser un SOUVENIR de position exige un
# registre separe (memoire_spatiale.gd), ce contenant ne le fera jamais.
# L'argument existe encore uniquement pour ne pas changer la signature
# (tous les appelants le passent deja, redondant avec chose.position).
# `position` est STRUCTURELLE sur `chose` : absente, push_error et la
# chose n'est PAS enregistree -- jamais un defaut silencieux. Meme
# doctrine sur un id deja present dans `choses` : jamais un ecrasement
# silencieux -- push_error et la chose n'est PAS enregistree.
#
# par_id(id) -> rend le wrapper { chose, type } enregistre sous cet id.
# Id absent : push_error, rend null -- jamais un defaut silencieux.
#
# choses_dans_rayon(position, rayon) -> Array des entrees { chose, type,
# position } a distance <= rayon, `position` relue depuis
# `entree.chose.position` a chaque appel.
#
# Ne fait pas : ne fabrique aucun objet (voir objet.gd), ne connait aucune
# propriete.

var choses: Dictionary = {}

func ajouter(chose, type: String, position: Vector3) -> void:
	if not (chose is Dictionary and chose.has("position")):
		push_error("monde.gd : ajouter() -- 'chose' sans champ 'position' structurel, non enregistree")
		return
	if choses.has(chose.id):
		push_error("monde.gd : ajouter() -- id '%s' deja enregistre, non ecrase" % chose.id)
		return
	choses[chose.id] = {"chose": chose, "type": type}

func par_id(id) -> Variant:
	if not choses.has(id):
		push_error("monde.gd : par_id() -- id '%s' absent" % id)
		return null
	return choses[id]

func choses_dans_rayon(position: Vector3, rayon: float) -> Array:
	var resultat: Array = []
	for entree in choses.values():
		var pos_vivante: Vector3 = entree.chose.position
		if position.distance_to(pos_vivante) <= rayon:
			resultat.append({"chose": entree.chose, "type": entree.type, "position": pos_vivante})
	return resultat
