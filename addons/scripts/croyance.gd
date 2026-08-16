extends RefCounted

# Mecanisme du coeur : CROYANCE -- copie partielle, datee et faillible du
# monde, portee par l'entite QUI A PERCU. Chantier « croyance + correction --
# le colon croit au lieu de savoir » (audit prealable
# audit_perception_croyance_memoire_prealable.md, lignes 1 et 2, toutes deux
# au verdict CONCEPT NEUF REQUIS).
#
# CE QUE CE FICHIER EST, ET QU'AUCUN AUTRE N'ETAIT : LE CONTRAT D'ENTREE DE LA
# COUCHE 2, REVU. Jusqu'ici la chaine etait sans intermediaire (audit, constat
# A) -- monde.gd:choses_dans_rayon rend la REFERENCE Dictionary enregistree,
# perception.gd la recopie telle quelle, et attaches.gd/proximite.gd/
# jugement.gd/agir.gd/ciblage.gd lisent tous chose.proprietes, c'est-a-dire
# L'OBJET REEL. Ce fichier S'INTERCALE entre percevoir() et les evaluateurs de
# saillance : il prend le rendu de Perception.percevoir et rend LA MEME FORME,
# avec des proprietes qui sont la copie CRUE du percevant. AUCUN des six
# fichiers de la chaine n'a une ligne a changer -- ils recoivent perceptions EN
# PARAMETRE et ne vont jamais chercher le monde eux-memes.
#
# EVOLUTION DE DOCTRINE, ASSUMEE ET NOMMEE (decision Yael, voir docs/design.md
# « La croyance : une copie partielle, nee de la perception vecue ») :
# design.md posait « un colon ne reconnait rien et ne consulte rien ». Une
# entite porte desormais une copie partielle de ce qu'elle a PERCU, avec une
# certitude par champ. La legitimite est celle, deja tranchee, de
# lien_personnel.gd : le registre nait d'un EVENEMENT VECU, jamais pose en dur
# dans un fichier de donnees -- ce qui aurait recree le « registre consulte »
# ecarte par design.md. Les quatre griefs contre BDI ne mordent pas ici : la
# croyance REMPLACE L'ENTREE de la couche 2, elle ne met aucune deformation
# apres la perception, n'enumere aucun goal, ne pre-ecrit aucun plan et ne
# defend aucune intention contre la distraction.
#
# Modele : proprietes.croyances[chose_id][propriete] = { valeur, certitude }.
# Patron STRUCTUREL : deformation.gd (Dictionary imbrique [source][cible]).
# Patron SEMANTIQUE : lien_personnel.gd (nait d'un evenement vecu, decroit
# seul, disparait sous un plancher). La croyance est les deux a la fois : une
# structure imbriquee dont la semantique est celle du lien.
#
# QUATRE VERBES, jamais un de plus :
# - observer() -- recopier ce qui est perceptible, monter la confiance.
# - filtrer()  -- rendre la copie A LA PLACE de la source.
# - corriger() -- confronter la copie a une valeur verifiee, sous reserve que
#                 la confiance ne soit pas devenue un dogme.
# - avancer()  -- oublier, faute d'y revenir.
#
# AUCUN NOM DE CONTENU. Ce fichier ne connait ni « comestible », ni « fruit »,
# ni « colon » : seulement des cles opaques et un catalogue recu en parametre
# (meme convention que deformation.gd/lien_personnel.gd/extinction.gd/
# depense.gd -- jamais charge par ce fichier). Prouve hors domaine par
# scripts/test_croyance.gd : un enregistreur qui recopie des sondes avec une
# fiabilite par sonde, et rend son registre plutot que les sondes.
#
# entite : Dictionary { id, position, proprietes }, mute en place par
#          observer()/corriger()/avancer(). filtrer() ne mute JAMAIS rien --
#          ni l'entite, ni les perceptions recues, ni les choses reelles
#          qu'elles portent (il construit des choses NEUVES, voir plus bas).
# chose_id / propriete : String, cles opaques.
# catalogue : data/croyances.json --
#   proprietes_observables    Array de String. Les propriretes du MONDE qu'un
#                             canal peut capter. STRUCTURELLE cote observer()
#                             (cle absente -> push_error + retour neutre,
#                             jamais un defaut silencieux) ; valeur vide ([])
#                             legitime : une entite qui n'observe rien.
#   proprietes_conservees     Array de String. Les CHAMPS DE CONFIGURATION
#                             TECHNIQUE qui traversent filtrer() tels quels --
#                             voir « CE QUE FILTRER CONSERVE » plus bas.
#   certitude_initiale        certitude d'une croyance tout juste formee.
#   gain_par_verification     ce qu'une observation de plus ajoute.
#   plafond_certitude         borne haute, jamais depassee.
#   taux_decroissance         oubli passif, par seconde.
#   plancher_suppression      sous quoi la croyance est RETIREE, jamais
#                             laissee a une valeur residuelle.
#   gain_par_echec            certitude d'une croyance qui vient d'etre
#                             corrigee, a credibilite 1.0.
#   resistance_par_certitude  a partir de quelle certitude une correction est
#                             refusee -- LE DOGME.
#   seuil_bornes_transmission JAMAIS LU ICI. Credibilite minimale sous
#                             laquelle un cablage renonce a transmettre --
#                             c'est a l'appelant de le lire et de ne pas
#                             appeler corriger() (voir banc_croyance.gd).
#                             Declare dans ce catalogue parce qu'il qualifie
#                             la meme grandeur que gain_par_echec, jamais
#                             parce que ce fichier s'en sert.
#
# Structurel vs facultatif (docs/design.md, « Propriete structurelle vs
# facultative ») : proprietes.croyances est STRUCTURELLE sur les QUATRE
# fonctions, meme convention que proprietes.liens_personnels/deformation_etat/
# engagement -- sa cle absente dit « ceci n'est pas une entite equipee pour
# croire quoi que ce soit », jamais « aucune croyance ». Sa valeur vide ({})
# est legitime (rien n'a encore ete percu). Une chose, ou une propriete,
# absente de croyances est un point neutre legitime : observer()/corriger() la
# creent, filtrer()/avancer() ne l'inventent JAMAIS.
#
# CE QUE FILTRER CONSERVE, et pourquoi (decision Yael, question posee avant
# d'ecrire) : la copie remplace les PROPRIETES DU MONDE, jamais les CHAMPS DE
# CONFIGURATION TECHNIQUE (docs/design.md, « Propriete du monde vs champ de
# configuration technique »). Un pointeur de catalogue -- profil_saillance,
# transformation, seuils_ref, materiau, composition, canaux -- n'est PAS
# perceptible : aucun canal ne le capte, il ne se manipule jamais comme cause,
# il sert au MOTEUR a retrouver la regle applicable. Il n'est donc objet
# d'aucune croyance. Sans cette conservation, proximite.gd rendrait []
# systematiquement sur une perception filtree (ref == "" -> continue) et
# attaches.gd/jugement.gd deviendraient inertes avec lui : trois des six
# fichiers de la chaine seraient vivants mais muets, ce qui est pire qu'un
# echec (rien ne rougirait). La liste vit EN DONNEE (catalogue.
# proprietes_conservees), jamais en dur ici -- ce fichier ne connait aucun nom
# de champ. Catalogue absent (defaut {}) : remplacement STRICT, aucun champ
# conserve, comportement de la consigne d'origine, conserve comme point neutre
# pour un appelant qui n'a rien a preserver.
#
# CE QUE FILTRER CONSERVE TOUJOURS, sans catalogue et sans condition :
# l'ENTREE de perception elle-meme (type, position, distance, canaux et toute
# cle future que perception.gd ajouterait -- copie superficielle puis
# surcharge de la seule cle « chose »), et sur la chose : SON ID et SA
# POSITION VIVANTE. Le percevant voit bien OU est la chose ; il ne sait pas ce
# qu'elle EST.
#
# PIEGE FERME, nomme par l'audit : les id DOIVENT survivre au filtre. Sans eux,
# agir.gd:_meme_tache/_identifiant (l'inertie), agir.gd:_avec_cible_engagee
# (l'engagement), agir.gd:_appliquer_actes_liants, couplage.gd et
# lien_personnel_attraction.gd cassent TOUS EN SILENCE -- ils comparent des
# identites, jamais des propriretes. Verrouille par test.
#
# CE QUE CE FICHIER NE FAIT PAS, dit plutot que masque :
# - il ne DECIDE pas quand observer ni quand corriger. Le contact, l'usage, la
#   transmission par un tiers sont des faits du CABLAGE ; ce fichier n'a ni
#   portee, ni geometrie, ni notion d'emetteur.
# - il ne connait aucune credibilite : credibilite_source est un nombre DEJA
#   RESOLU par l'appelant (1.0 pour l'experience directe, la force d'un lien
#   personnel pour une transmission -- meme discipline que consommer.gd, dont
#   le « taux » est deja compose par le cablage).
# - il n'oublie jamais une POSITION (aucun champ de position memorisee) : la
#   memoire spatiale est un mecanisme DISTINCT, scripts/memoire_spatiale.gd
#   (audit, ligne 5, livre par une session concurrente du meme audit). Les deux
#   ne se recouvrent pas et ne s'appellent pas : croyance.gd recopie CE QU'UNE
#   CHOSE EST et rend toujours sa position VIVANTE ; memoire_spatiale.gd retient
#   OU elle etait. Un colon qui n'aurait que la croyance suivrait par telepathie
#   une chose qui bougerait.
#
# DECROISSANCE PAR SOUSTRACTION FIXE, comme tout le depot (audit, constat F) :
# max(0.0, certitude - taux * delta). Il n'existe AUCUN equilibre naturel,
# aucune asymptote -- une cadence d'observation superieure au taux fait monter
# la certitude jusqu'au plafond, une cadence inferieure la fait disparaitre.
# Le plafond, lui, est DANS LE CATALOGUE ici (plafond_certitude), pas au
# cablage : une certitude est bornee par nature, contrairement a un biais de
# deformation.
#
# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# proprietes.croyances ne porte que des cles String et, en feuille, une
# certitude float plus une valeur RECOPIEE TELLE QUELLE de la chose percue --
# sa resumabilite est donc exactement celle de proprietes cote monde (bool,
# float, String, Array, Dictionary), jamais un Vector3 ni un Callable, par la
# meme contrainte qui pese deja sur toute propriete d'objet.

static func observer(entite: Dictionary, perceptions: Array, catalogue: Dictionary) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("croyances"):
		push_error("croyance.gd : propriete structurelle 'croyances' absente de proprietes")
		return
	if not catalogue.has("proprietes_observables"):
		push_error("croyance.gd : catalogue sans 'proprietes_observables'")
		return
	var observables: Array = catalogue.proprietes_observables
	var certitude_initiale: float = catalogue.get("certitude_initiale", 0.0)
	var gain: float = catalogue.get("gain_par_verification", 0.0)
	var plafond: float = catalogue.get("plafond_certitude", 1.0)
	var croyances: Dictionary = proprietes.croyances
	for entree in perceptions:
		var chose: Dictionary = entree.chose
		var chose_id = chose.id
		var proprietes_chose: Dictionary = chose.get("proprietes", {})
		for propriete in proprietes_chose:
			if not observables.has(propriete):
				continue
			if not croyances.has(chose_id):
				croyances[chose_id] = {}
			var par_chose: Dictionary = croyances[chose_id]
			if not par_chose.has(propriete):
				par_chose[propriete] = {
					"valeur": proprietes_chose[propriete],
					"certitude": min(certitude_initiale, plafond),
				}
				continue
			var champ: Dictionary = par_chose[propriete]
			champ["valeur"] = proprietes_chose[propriete]
			champ["certitude"] = min(float(champ.get("certitude", 0.0)) + gain, plafond)

# Rend un Array de MEME FORME (et de MEME LONGUEUR) que perceptions -- une
# entree par chose percue, jamais un filtre de presence : le percevant VOIT
# tout ce que ses canaux captent, il ne SAIT pas ce que c'est. Une entite sans
# aucune croyance rend donc autant d'entrees qu'elle en a recues, chacune
# portant une chose aux proprietes VIDES (plus les champs de configuration
# conserves) -- le monde est la, il n'est pas interprete.
#
# Ne mute rien : chaque « chose » rendue est un Dictionary NEUF. Muter la
# chose reelle pour y ecrire la croyance d'un percevant la reecrirait pour
# TOUS les autres (monde.gd ne rend que des references, audit constat A).
static func filtrer(entite: Dictionary, perceptions: Array, catalogue: Dictionary = {}) -> Array:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("croyances"):
		push_error("croyance.gd : propriete structurelle 'croyances' absente de proprietes")
		return []
	var croyances: Dictionary = proprietes.croyances
	var conservees: Array = catalogue.get("proprietes_conservees", [])
	var sortie: Array = []
	for entree in perceptions:
		var chose: Dictionary = entree.chose
		var chose_id = chose.id
		var proprietes_chose: Dictionary = chose.get("proprietes", {})
		var crues: Dictionary = {}
		for propriete in croyances.get(chose_id, {}):
			crues[propriete] = croyances[chose_id][propriete].valeur
		for propriete in conservees:
			if proprietes_chose.has(propriete):
				crues[propriete] = proprietes_chose[propriete]
		var copie: Dictionary = entree.duplicate()
		copie["chose"] = {
			"id": chose_id,
			"position": chose.position,
			"proprietes": crues,
		}
		sortie.append(copie)
	return sortie

# LA CERTITUDE EST ECRASEE, jamais incrementee (decision Yael, question posee
# avant d'ecrire) : certitude := min(gain_par_echec * credibilite_source,
# plafond_certitude). Consequence voulue -- avec gain_par_echec 0.8 et
# resistance_par_certitude 0.9, une verification DIRECTE (credibilite 1.0)
# laisse toujours la croyance corrigible. Incrementer aurait fait du dogme le
# produit de la verification elle-meme : deux corrections directes portent la
# certitude au plafond, qui depasse la resistance, et plus aucun contact ne
# passe. Le dogme ne peut donc naitre QUE de l'accumulation d'observations
# (observer(), gain_par_verification repete), jamais d'une correction.
#
# Une croyance ABSENTE est un point neutre legitime, pas une erreur : sa
# certitude vaut 0.0, elle est donc sous toute resistance positive, et
# corriger() la CREE -- c'est ainsi qu'un percevant apprend d'un tiers une
# chose qu'il n'avait jamais observee lui-meme.
#
# Une credibilite nulle ou negative rend une certitude nulle : la valeur est
# ecrite mais avancer() retirera l'entree au premier pas (0.0 <
# plancher_suppression). Point neutre, jamais une alarme -- « on m'a dit, je
# n'y crois pas, j'ai deja oublie ».
static func corriger(
	entite: Dictionary,
	chose_id: String,
	propriete: String,
	valeur_reelle: Variant,
	credibilite_source: float,
	catalogue: Dictionary,
) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("croyances"):
		push_error("croyance.gd : propriete structurelle 'croyances' absente de proprietes")
		return
	var croyances: Dictionary = proprietes.croyances
	var par_chose: Dictionary = croyances.get(chose_id, {})
	var champ: Dictionary = par_chose.get(propriete, {})
	var certitude_actuelle: float = champ.get("certitude", 0.0)
	var resistance: float = catalogue.get("resistance_par_certitude", INF)
	if certitude_actuelle >= resistance:
		return
	var plafond: float = catalogue.get("plafond_certitude", 1.0)
	var gain: float = catalogue.get("gain_par_echec", 0.0) * credibilite_source
	if not croyances.has(chose_id):
		croyances[chose_id] = {}
	croyances[chose_id][propriete] = {
		"valeur": valeur_reelle,
		"certitude": max(0.0, min(gain, plafond)),
	}

# L'OUBLI PASSIF. Retire la propriete tombee sous le plancher, puis la chose
# devenue vide -- sans ces deux retraits le Dictionary grossirait
# indefiniment de croyances residuelles quasi nulles, puis de coquilles vides
# (meme raison exacte que lien_personnel.gd:avancer, un cran plus profond
# parce que la structure est imbriquee).
static func avancer(entite: Dictionary, delta: float, catalogue: Dictionary) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("croyances"):
		push_error("croyance.gd : propriete structurelle 'croyances' absente de proprietes")
		return
	var taux: float = catalogue.get("taux_decroissance", 0.0)
	var plancher: float = catalogue.get("plancher_suppression", 0.0)
	var croyances: Dictionary = proprietes.croyances
	var choses_a_retirer: Array = []
	for chose_id in croyances:
		var par_chose: Dictionary = croyances[chose_id]
		var proprietes_a_retirer: Array = []
		for propriete in par_chose:
			var champ: Dictionary = par_chose[propriete]
			var restante: float = max(0.0, float(champ.get("certitude", 0.0)) - taux * delta)
			champ["certitude"] = restante
			if restante < plancher:
				proprietes_a_retirer.append(propriete)
		for propriete in proprietes_a_retirer:
			par_chose.erase(propriete)
		if par_chose.is_empty():
			choses_a_retirer.append(chose_id)
	for chose_id in choses_a_retirer:
		croyances.erase(chose_id)
