extends RefCounted

# Champ scalaire OCCULTE par les obstacles (chantier "ombre pluviometrique --
# il pleut moins derriere la montagne"). Repond a UNE question et une seule :
# quelle est l'INTENSITE d'un champ ambiant, a UNE position, compte tenu des
# sources qui l'alimentent ET de ce qui se dresse entre elles et ce point.
# Classe RefCounted SANS ETAT (fonctions static pures, meme discipline que
# tout scripts/).
#
# CE QU'IL EST, EXACTEMENT : le patron lumiere.gd:locale (superposition
# ADDITIVE de contributions ponderees par source, attenuees par la distance)
# PLUS l'occlusion de perception.gd (occlusion.gd:facteur, extraite par ce
# meme chantier). Les deux moities existaient separement et aucune ne parlait
# a l'autre -- lumiere.gd/temperature.gd ignorent totalement les obstacles,
# perception.gd connait les obstacles mais rend une LISTE FILTREE, jamais
# l'intensite attenuee qu'il calcule pourtant en interne (constat de
# audit_terrain_et_monde_prealable.md §7, points (a) a (d)). Ce fichier ferme
# ce trou, et rien d'autre.
#
# CE QU'IL N'EST PAS, DELIBEREMENT :
# - PAS un filtre binaire : il rend un NOMBRE, jamais "percu / non percu".
#   Derriere un obstacle l'intensite est REDUITE, jamais coupee -- c'est
#   toute la difference entre une ombre et une frontiere.
# - PAS une perception : aucun percepteur, aucune entite, aucun canal,
#   aucun catalogue. Il ne lit ni proprietes.canaux ni canaux_config, et
#   n'appelle jamais perception.gd.
# - PAS un consommateur de monde.gd : `sources` et `obstacles` sont deux
#   Array PLATS recus de l'appelant, jamais un objet exposant
#   choses_dans_rayon -- meme decision que ecoulement.gd, et pour la meme
#   raison (une requete spatiale O(n) par case, sur un terrain de n cases,
#   coute O(n^2) pour un voisinage que l'appelant connait deja).
# - PAS un ecrivain : il ne mute aucun objet, ne pose aucune propriete, ne
#   fabrique rien. C'est au CABLAGE d'ecrire l'intensite rendue la ou il
#   veut (proprietes.humidite pour banc_ombre_pluvio.gd) -- meme discipline
#   que consommer.gd/frappe.gd, qui ne transforment jamais eux-memes.
#
# --- intensite_locale(position, sources, obstacles, propriete_obstacle,
#     largeur_obstacle, propriete_emission, exposant_distance) -> float ---
#
# Recoit :
# - `position` (Vector3) : ou l'on interroge le champ.
# - `sources` (Array de Dictionary { position: Vector3, proprietes:
#   Dictionary }) : CONSTRUIT ET POSSEDE ENTIEREMENT PAR L'APPELANT (la mer,
#   un feu, un marais) -- ce fichier ne fabrique, ne charge, ne deplace
#   jamais aucune source, meme patron que vent.gd:sources_locales/
#   lumiere.gd:sources. Une source dont `position` manque est
#   STRUCTURELLEMENT incomplete : push_error nommant son index, CETTE source
#   seule est ignoree, les autres continuent.
# - `obstacles` (Array de Dictionary { position: Vector3, proprietes:
#   Dictionary }) : de meme, possede par l'appelant. Passe tel quel a
#   occlusion.gd:facteur -- voir ce fichier pour la geometrie exacte.
# - `propriete_obstacle` (String) : nom de la propriete qui attenue, portee
#   par les obstacles ("relief_bloquant"). VIDE : aucune occlusion testee,
#   le champ redevient un pur lumiere.gd:locale.
# - `largeur_obstacle` (float) : tolerance laterale au segment source->point
#   (occlusion.gd). PARAMETRE OBLIGATOIRE, sans defaut : un defaut 0.0
#   n'aurait retenu aucun obstacle et aurait rendu "aucune ombre" en
#   silence -- exactement le genre de neutre trompeur a ne pas offrir.
# - `propriete_emission` (String) : nom de la propriete que porte la SOURCE
#   pour sa force ("humidite_emission"). MEME CONVENTION que
#   data/canaux.json:propriete_emission (perception.gd) : jamais un nom en
#   dur ici. Une source qui ne la porte pas vaut 0.0 -- point neutre
#   legitime, jamais une alarme.
# - `exposant_distance` (float) : exposant de la loi en puissance inverse
#   (occlusion.gd:attenuer_par_distance). 0.0 = aucune attenuation, 1.0 =
#   1/d, 2.0 = 1/d^2.
#
# Rend : un float, la SOMME des contributions de toutes les sources --
# chacune valant (force attenuee par la distance) * (facteur d'occlusion sur
# le segment source->position). JAMAIS borne en haut (contrairement a
# lumiere.gd:locale, qui plafonne a 1.0 parce qu'une intensite lumineuse a
# un plafond physique) : une humidite atmospherique n'a pas de plafond
# universel, c'est au cablage de choisir son echelle de reference. Jamais
# negatif non plus : chaque terme est un produit de grandeurs positives ou
# nulles.
#
# ADDITIF, JAMAIS UN ECART : deux sources qui se recouvrent S'ADDITIONNENT
# (meme choix que lumiere.gd:locale et vent.gd, jamais celui de
# temperature.gd qui tire vers une valeur d'equilibre). Une source occluse ne
# retire rien aux autres : son propre terme est simplement plus petit.
#
# COUT : O(sources * obstacles) par appel. Un cablage qui interroge n points
# paie donc O(n * sources * obstacles) par tick -- limite CONNUE, NON
# OPTIMISEE (aucune structure d'acceleration spatiale, voir occlusion.gd et
# CLAUDE.md : signaler, pas contourner en silence).

const Occlusion = preload("res://scripts/occlusion.gd")

static func intensite_locale(position: Vector3, sources: Array, obstacles: Array, propriete_obstacle: String, largeur_obstacle: float, propriete_emission: String, exposant_distance: float) -> float:
	var total := 0.0
	for i in sources.size():
		var source: Dictionary = sources[i]
		if not source.has("position"):
			push_error("champ_occulte.gd : source #%d sans 'position', ignoree" % i)
			continue
		var force: float = float(source.get("proprietes", {}).get(propriete_emission, 0.0))
		if force == 0.0:
			continue
		var distance: float = position.distance_to(source.position)
		var attenuation: float = Occlusion.attenuer_par_distance(force, distance, exposant_distance)
		if attenuation == 0.0:
			continue
		var facteur: float = Occlusion.facteur(source.position, position, obstacles, propriete_obstacle, largeur_obstacle)
		total += attenuation * facteur
	return total
