extends RefCounted

# Mecanisme du coeur : HORLOGE DU MONDE -- rend l'HEURE DU JOUR et le NOM DE
# LA SAISON courante a partir d'un temps ecoule. Classe RefCounted SANS ETAT
# (fonctions static PURES), meme gabarit que velocite.gd/portee.gd : ne mute
# rien, ne charge rien du disque, ne recoit aucun catalogue, n'a aucune
# memoire d'un appel a l'autre. Deux nombres entrent, un nombre sort ; trois
# nombres et une liste de noms entrent, un nom sort.
#
# POURQUOI CE FICHIER EXISTE (le seuil que banc_fatigue_circadien.gd avait
# nomme sans le franchir) : le meme calcul d'heure du jour etait RECOPIE dans
# deux bancs jetables -- banc_lumiere.gd:heure_courante et
# banc_fatigue_circadien.gd:heure_courante, formule identique au caractere
# pres. L'en-tete du second disait « si cette horloge doit un jour servir un
# troisieme banc, elle devient candidate au coeur : SIGNALE, jamais decide
# ici ». Le troisieme demandeur est arrive. EXTRACTION ETROITE, meme patron
# que portee.gd/quantite_matiere.gd/occlusion.gd : la formule est reprise
# TELLE QUELLE (voir heure() ci-dessous), aucune loi renegociee, rien
# d'autre unifie autour d'elle.
#
# LES DEUX BANCS EXISTANTS NE SONT PAS TOUCHES : ils gardent leur copie
# locale (deux bancs jetables ne se referencent jamais entre eux, precedent
# banc_erosion.gd). Ce fichier est ecrit POUR LES APPELANTS A VENIR, qui
# liront proprietes.heure_courante au lieu de recalculer -- voir
# senescence.gd:avancer, seul appelant a ce jour.
#
# UNITE, LE POINT QUI COMMANDE TOUT LE RESTE : `temps_ecoule` est en
# SECONDES DE SIMULATION, convention de tout le depot (delta partout,
# ecoulement.gd, depense.gd, charge.gd...) -- JAMAIS en annees. C'est
# `duree_jour_secondes` (combien de secondes reelles dure un jour du monde)
# qui relie cette unite au calendrier, exactement comme `annees_par_seconde`
# relie delta a l'age dans senescence.gd : un FACTEUR D'ECHELLE recu en
# parametre, jamais une constante de ce fichier. Les DEUX fonctions lisent
# `temps_ecoule` dans la MEME unite -- sans quoi l'heure et la saison
# decriraient deux temps differents.
#
# AUCUNE LONGUEUR DE JOUR EN DUR : `heures_par_jour` est un PARAMETRE, jamais
# `24.0` ecrit dans le code. Un monde a dix heures par jour traverse le meme
# code sans une ligne ajoutee -- c'est la discipline que les deux bancs
# tenaient deja explicitement (« jamais 24.0 en dur ici », en-tete de
# banc_lumiere.gd:heure_courante), et la perdre en montant dans le coeur
# figerait la longueur du jour pour tout monde a venir.
#
# NE CONNAIT AUCUN NOM DE SAISON : `saisons` est un Array de String recu EN
# PARAMETRE, declare en donnee par l'appelant. Ni « printemps », ni « hiver »,
# ni aucun cycle nomme n'apparait ici -- meme discipline que stade.gd (qui ne
# connait aucun nom de stade) et que bifurcation.gd (qui ne connait aucun nom
# de sortie). Le NOMBRE de saisons n'est jamais lu non plus : deux, quatre ou
# cinq traversent le meme code.
#
# heure(temps_ecoule, duree_jour_secondes, heures_par_jour, heure_depart)
#   Recoit : `temps_ecoule` (float, secondes de simulation depuis l'origine
#            du monde) ; `duree_jour_secondes` (float, secondes reelles pour
#            un jour complet) ; `heures_par_jour` (float, combien d'heures
#            compte un jour de ce monde) ; `heure_depart` (float, l'heure
#            qu'il etait a temps_ecoule = 0.0).
#   Rend : l'heure du jour, TOUJOURS ramenee dans [0.0, heures_par_jour) --
#          jamais negative, jamais superieure ou egale a la longueur du jour.
#
# saison(temps_ecoule, duree_jour_secondes, jours_par_saison, saisons)
#   Recoit : `temps_ecoule`/`duree_jour_secondes` (MEME unite et meme sens
#            que heure()) ; `jours_par_saison` (float, combien de jours dure
#            une saison) ; `saisons` (Array de String, l'ORDRE compte -- c'est
#            lui qui dit quelle saison suit laquelle, jamais ce fichier).
#   Rend : le nom de la saison courante, un des elements de `saisons` --
#          jamais un nom invente, jamais un index.
#
# STRUCTUREL vs FACULTATIF (voir docs/design.md) -- ce fichier ne lit AUCUNE
# propriete d'objet, la question ne se pose donc que sur ses parametres :
# - `heures_par_jour <= 0.0` : donnee CASSEE, jamais un point legitime du
#   monde (un jour sans heure ne se represente pas) -> push_error + repli
#   neutre 0.0. Garde OBLIGATOIRE et non cosmetique : `fmod(x, 0.0)` rend NaN,
#   qui se propagerait ensuite en silence dans tout ce qui lit l'heure.
# - `jours_par_saison <= 0.0` : meme raison (division par zero) ->
#   push_error + repli "".
# - `duree_jour_secondes <= 0.0` : point LEGITIME, aucune alarme -- le temps
#   du monde est simplement arrete. heure() reste bloquee sur `heure_depart`,
#   saison() rend la premiere saison declaree. Comportement RECOPIE TEL QUEL
#   des deux bancs (« reste bloque sur heure_depart, jamais une division par
#   zero »).
# - `saisons` VIDE : point LEGITIME, aucune alarme -- un monde sans saisons
#   existe. Rend "" (chemin mort silencieux, meme convention que
#   frappe.gd/bifurcation.gd : n'avoir rien a choisir n'est pas une donnee
#   cassee).
#
# SEULE DIFFERENCE ASSUMEE avec la copie des deux bancs : le repli d'un
# resultat NEGATIF dans l'intervalle du jour (`_ramener`). Les deux bancs ne
# recoivent jamais de temps ni d'heure de depart negatifs et n'avaient donc
# pas a s'en proteger ; un mecanisme du coeur, si. Meme geste exact que
# lumiere.gd:_couleur_courbe (« heure_mod < 0.0 -> += heures_par_jour »),
# precedent reel du depot. Sur toute entree positive, le resultat est
# rigoureusement identique a celui des deux bancs.
#
# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) : les
# deux sorties sont un float nu et une String nue -- aucun Vector3, aucun
# Callable, aucun Dictionary.

static func heure(temps_ecoule: float, duree_jour_secondes: float, heures_par_jour: float, heure_depart: float) -> float:
	if heures_par_jour <= 0.0:
		push_error("horloge.gd : heures_par_jour doit etre strictement positif (recu %f)" % heures_par_jour)
		return 0.0
	if duree_jour_secondes <= 0.0:
		return _ramener(heure_depart, heures_par_jour)
	var heures_ecoulees: float = (temps_ecoule / duree_jour_secondes) * heures_par_jour
	return _ramener(heure_depart + heures_ecoulees, heures_par_jour)

static func saison(temps_ecoule: float, duree_jour_secondes: float, jours_par_saison: float, saisons: Array) -> String:
	if saisons.is_empty():
		return ""
	if duree_jour_secondes <= 0.0:
		return String(saisons[0])
	if jours_par_saison <= 0.0:
		push_error("horloge.gd : jours_par_saison doit etre strictement positif (recu %f)" % jours_par_saison)
		return ""
	var jours: float = temps_ecoule / duree_jour_secondes
	var nombre: int = saisons.size()
	var index: int = int(floor(fmod(jours / jours_par_saison, float(nombre))))
	if index < 0:
		index += nombre
	return String(saisons[index])

# Ramene une heure BRUTE (potentiellement au-dela d'un jour, potentiellement
# negative) dans [0.0, heures_par_jour). `fmod` de GDScript garde le SIGNE du
# dividende : un temps ou une heure de depart negatifs rendraient une heure
# negative, qu'aucun lecteur d'heure ne sait interpreter. Meme correction que
# lumiere.gd:_couleur_courbe. `heures_par_jour` est deja garanti strictement
# positif par les appelants ci-dessus -- jamais de division par zero ici.
static func _ramener(heure_brute: float, heures_par_jour: float) -> float:
	var h: float = fmod(heure_brute, heures_par_jour)
	return h + heures_par_jour if h < 0.0 else h
