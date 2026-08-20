extends Resource

# CE DONT LE MONDE SE SOUVIENT. Toute donnee persistante du jeu herite d'ici :
# le terrain, les objets, la vegetation, les creatures, les rivieres -- tout ce
# qui doit exister au prochain lancement.
#
# Entree : rien. Sortie : un drapeau, `est_sale()`, et un chemin sur disque.
#
# CE FICHIER NE SAIT RIEN ECRIRE, ET C'EST VOULU. Il porte la QUESTION « ai-je
# change ? » ; l'archiviste porte la reponse « alors je t'ecris ». Les deux
# separes, ajouter une sorte de donnee au monde ne demande aucune ligne
# d'ecriture : elle herite, elle se marque, elle est enregistree.
#
# CHAQUE ECRITURE SE MARQUE, ET C'EST LA SEULE DISCIPLINE A TENIR. Un domaine
# qui modifie ses donnees sans appeler `marquer_sale()` ne sera pas enregistre,
# et rien ne le signalera avant le prochain lancement -- ou son travail aura
# disparu. C'est le prix d'un mecanisme qui ne relit pas tout a chaque image
# pour deviner ce qui a bouge : comparer l'etat complet d'un monde de cent
# kilometres carres couterait plus cher que la simulation elle-meme.
#
# ON N'ECRIT QUE CE QUI A CHANGE, jamais le monde entier -- c'est le patron des
# jeux a monde ouvert persistant : stocker les ECARTS au defaut, et ne toucher
# au disque que pour ce qui est marque.
#
# Regles tenues : aucun hasard. Aucun texte visible par le joueur. Aucun nom de
# contenu -- ce fichier ne sait pas ce qu'il garde en memoire. Rien de scripts/,
# data/ ni documents/ n'est lu ni ecrit.

# LE DRAPEAU N'EST PAS EXPORTE : il decrit un etat de session, pas une donnee du
# monde. L'enregistrer voudrait dire qu'une carte relue d'un disque se croit
# modifiee, et se reecrirait sans que rien n'ait bouge.
var _sale := false

# Ce que ce registre a change depuis sa derniere ecriture. L'archiviste ne
# demande rien d'autre.
func est_sale() -> bool:
	return _sale

# A APPELER DANS CHAQUE GESTE QUI MODIFIE. Voir l'en-tete : c'est la seule
# discipline que ce mecanisme demande, et la seule chose qu'il ne peut pas
# deviner a un cout raisonnable.
func marquer_sale() -> void:
	_sale = true

# Appele par l'archiviste apres une ecriture reussie, jamais par un domaine :
# se declarer propre sans avoir ete ecrit perdrait le travail.
func marquer_propre() -> void:
	_sale = false

# Ce registre peut-il etre ecrit ? Une ressource fabriquee a l'execution n'a
# aucun chemin, et ResourceSaver n'a nulle part ou la mettre.
func peut_etre_ecrit() -> bool:
	return not resource_path.is_empty()

# COMMENT L'APPELER DANS UN RAPPORT, jamais un nom de contenu : le chemin sur
# disque, ou le type a defaut. Sert aux traces de l'archiviste.
func nom_lisible() -> String:
	if not resource_path.is_empty():
		return resource_path
	return "registre sans chemin"
