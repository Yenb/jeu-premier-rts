extends RefCounted

# Calcul pur : quelles choses vulnerables gagnent une propriete-menace ce
# pas de temps, et recoivent leur chantier de transformation. Aucun noeud,
# aucun rendu -- testable headless (scripts/test_propagation.gd,
# scripts/test_propagation_chantier.gd).
#
# Precharge scripts/banc_commun.gd pour poser les cles du patron
# (BancCommun.resoudre_chantier) -- EXCEPTION documentee dans l'en-tete de
# banc_commun.gd, seul mecanisme du coeur a precharger cette boite a outils.
# Raison : le geste n'existe qu'a UN endroit, avec son bug d'aliasing sur les
# valeurs imbriquees (Dictionary dans Dictionary, ex. "reserves") ferme une
# seule fois.
#
# monde : Array de Dictionary { "id": String, "position": Vector3,
#         "proprietes": Dictionary }, mute en place -- une chose exposee
#         assez longtemps GAGNE la propriete-menace correspondant a sa
#         vulnerabilite, jamais un champ "type" ni un bool "enflamme".
# menaces : table vulnerabilite -> propriete-menace (data/menaces.json),
#         la meme que lit attaches.gd. Sert a la fois a reconnaitre les
#         sources actuelles (portent deja une propriete-menace) et a
#         poser la propriete gagnee -- aucun nom en dur.
# exposition : Dictionary id -> temps d'exposition continue a une source
#         voisine, mute en place, remis a zero des que la chose sort de
#         portee (source disparue ou hors distance) et au moment ou elle
#         s'allume.
# patron : gabarit pose a l'allumage (data/transformations.json, entree
#         "patron") -- travail_restant, saillance_intrinseque,
#         portee_saillance, et "transformation" (String, reference vers
#         data/transformations.json["transformations"] -- portee_travail et
#         a_zero n'y vivent pas, voir scripts/extinction.gd). FACULTATIF
#         (defaut {}) : un appelant sans chantier traverse sans rien poser.
# intensite : data/intensite_propagation.json ({ propriete_intensite,
#         seuil_ignition, propriete_point_ignition FACULTATIF }).
# etats :  data/etats.json, transmis TEL QUEL a scripts/etat_effectif.gd
#         (consomme, jamais reecrit).
# emission : data/emission_propagation.json.
# temperature_locale : Dictionary id -> float, DEJA RESOLUE par l'appelant
#         via Temperature.locale(), jamais recalculee ici.
#         Les cinq derniers sont FACULTATIFS (defaut {}) et chacun degenere
#         proprement : sans eux, delai_propagation fixe et test binaire de
#         distance (Portee.en_portee), aucune gate.
#
# Frontiere avec attaches.gd : ce fichier POSE la propriete-menace,
# attaches.gd la LIT ailleurs pour en tirer une saillance -- aucun des deux
# n'ecrit dans l'autre, les deux lisent seulement la meme table.
#
# Le test "a portee" delegue a scripts/portee.gd:en_portee -- seule part
# partagee avec attaches.gd/flux.gd/extinction.gd/charge.gd. ECARTE (voir
# docs/design.md, "Direction majeure") : la fusion des cinq mecanismes est
# ABANDONNEE, ce fichier garde sa propre boucle en deux passes.
#
# A l'allumage, chaque cle du patron est posee sur la chose SAUF si le type
# l'a deja posee a la fabrication (Objet.fabriquer copie le type entier dans
# proprietes) -- la valeur du type gagne, les cles absentes viennent du
# patron. Aucun nom de chose en dur : ni le patron ni cette fonction ne
# savent ce qu'est un "feu" ou un "arbre".
#
# Une chose ne perd jamais sa propriete-menace ici : rien dans cette
# fonction ne l'efface.
#
# delai_propagation est STRUCTURELLE, mais seulement une fois la
# vulnerabilite de la chose confirmee (vuln != "") -- voir docs/design.md,
# "Propriete structurelle vs facultative", le cas du couple. Une chose non
# vulnerable n'a pas a la porter (deja filtree plus haut, absence
# legitime) ; une chose vulnerable sans "delai_propagation" contredirait ce
# que sa vulnerabilite vient de declarer (delai borne) par un declenchement
# INSTANTANE -- push_error puis continue, jamais un defaut 0.0 silencieux.
#
# TROIS GATES COEXISTENT, aucun ne remplace l'autre.
#
# (1) INTENSITE EFFECTIVE : le delai requis peut dependre de la valeur
# EFFECTIVE (scripts/etat_effectif.gd) d'une propriete numerique portee par
# la chose -- jamais un nom en dur ici, pilote par intensite.
# propriete_intensite. GATE DOUBLE : ne s'applique QUE si (a) ce nom est non
# vide ET (b) la chose PORTE cette propriete (composition resolue par
# objet.gd:fabriquer). Sinon delai_propagation fixe. Quand il s'applique :
# sous "seuil_ignition" la chose ne s'enflamme JAMAIS, meme exposee
# indefiniment (exposition remise a zero, meme traitement qu'une chose hors
# portee) ; au-dessus, le delai requis devient delai_propagation /
# intensite_effective -- plus intense, plus vite. Un etat qui MODULE au-dela
# de 1.0 raccourcit encore le delai ; un etat qui ECRASE a 0.0 bloque
# l'ignition par le meme seuil, sans aucun code special.
#
# (2) EMISSION ET SEUIL : la portee de propagation n'est PAS un seul nombre
# confondant deux roles. Une EMISSION portee par la SOURCE (fonction de sa
# taille, voir _emission()) DECROIT en 1/distance^2 (voir recu()) ; un SEUIL
# porte par la CIBLE (fonction de sa matiere, voir seuil_exposition())
# decide a partir de quelle valeur recue elle commence a chauffer. Une cible
# est exposee des qu'au moins une source lui delivre au moins son seuil --
# la portee effective en RESULTE (distance ou emission == seuil), elle n'est
# jamais declaree en dur.
#   EMISSION (source) : "portee_emission_base" + "portee_emission_par_
#   capacite" * capacite de la source (proprietes.reserves.<nom_reserve>.
#   capacite, LUE, jamais recalculee -- meme canal que
#   objet.gd:_fabriquer_reserve_combustible / scripts/combustible.gd). Une
#   source sans cette reserve emet a "portee_emission_base" seul, flat --
#   absence legitime, jamais une alarme. C'est la grandeur EXISTANTE qui
#   porte la taille du feu, jamais un nombre libre.
#   SEUIL (cible) : "seuil_base" / intensite EFFECTIVE de la cible --
#   EXACTEMENT le meme appel que delai_ignition(), jamais une propriete
#   separee. CONSEQUENCE ASSUMEE : l'intensite effective joue donc a DEUX
#   ENDROITS -- la DISTANCE a laquelle l'exposition commence ET la VITESSE a
#   laquelle elle aboutit. Une matiere deux fois plus intense est exposee
#   STRICTEMENT plus loin ET s'enflamme STRICTEMENT plus vite : l'ecart
#   entre deux matieres se MULTIPLIE, jamais ne s'additionne. Voulu, pas une
#   redondance a corriger.
#   GATE : ne s'applique QUE si "emission" est non vide ET
#   intensite.propriete_intensite est configuree ET la chose PORTE cette
#   propriete -- sinon avancer() retombe sur le test portee_propagation /
#   Portee.en_portee.
#
# (3) POINT D'IGNITION : la chose ne s'enflamme que si la temperature locale
# a sa position atteint le seuil porte par la propriete NOMMEE PAR LA DONNEE
# ("propriete_point_ignition", String, FACULTATIF, defaut "") -- MEME PATRON
# que "propriete_intensite", le nom vient du catalogue et jamais du code. La
# propriete elle-meme est fusionnee a la fabrication
# (objet.gd:_fusionner_proprietes_immuables, pilotee par
# data/proprietes_immuables_composition.json) -- famille INTENSIVE comme
# "densite"/"inflammabilite", moyenne ponderee par volume, JAMAIS une somme
# comme "pouvoir_calorifique". delai_ignition() recoit un SCALAIRE de
# temperature (defaut INF = "aucune donnee pour cette chose", jamais un bool
# separe). DEUX DESACTIVATIONS PAR LA SEULE ARITHMETIQUE, aucune branche
# "si absent" a ecrire : un nom vide ne matche jamais une propriete, et INF
# n'est jamais strictement inferieur a un seuil fini.
#   RISQUE ACCEPTE, documente et non corrige : un materiau sans cette
#   propriete dans sa fiche retombe a 0.0, et ne bloque donc JAMAIS ce gate
#   (toute temperature >= 0.0) -- seul le proxy d'intensite peut encore le
#   retenir. Aucune composition mixte reelle ne l'exerce aujourd'hui.
const BancCommun = preload("res://scripts/banc_commun.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Portee = preload("res://scripts/portee.gd")

static func avancer(
	monde: Array,
	menaces: Dictionary,
	exposition: Dictionary,
	delta: float,
	patron: Dictionary = {},
	intensite: Dictionary = {},
	etats: Dictionary = {},
	emission: Dictionary = {},
	temperature_locale: Dictionary = {},
) -> Array:
	var feux: Array = []
	for chose in monde:
		if _en_feu(chose, menaces):
			feux.append(chose)
	var nouvellement_enflammees: Array = []
	var propriete_intensite: String = intensite.get("propriete_intensite", "")
	for chose in monde:
		if _en_feu(chose, menaces):
			continue
		var vuln := _vulnerabilite(chose, menaces)
		if vuln == "":
			continue
		var expose := false
		if not emission.is_empty() and propriete_intensite != "" and chose.proprietes.has(propriete_intensite):
			var seuil := seuil_exposition(chose, intensite, etats, emission)
			for feu in feux:
				if recu(chose, feu, emission) >= seuil:
					expose = true
					break
		else:
			var portee: float = chose.proprietes.get("portee_propagation", 0.0)
			for feu in feux:
				if Portee.en_portee(chose.position, feu.position, portee):
					expose = true
					break
		var id: String = chose.id
		if not expose:
			exposition[id] = 0.0
			continue
		if not chose.proprietes.has("delai_propagation"):
			push_error("propagation.gd : chose '%s' vulnerable ('%s') sans 'delai_propagation'" % [id, vuln])
			continue
		var delai_requis: float = delai_ignition(chose, intensite, etats, temperature_locale.get(id, INF))
		if delai_requis < 0.0:
			exposition[id] = 0.0
			continue
		exposition[id] = exposition.get(id, 0.0) + delta
		if exposition[id] >= delai_requis:
			chose.proprietes[menaces[vuln]] = true
			BancCommun.resoudre_chantier(chose.proprietes, patron)
			exposition[id] = 0.0
			nouvellement_enflammees.append(id)
	return nouvellement_enflammees

# Lecture SEULE, publique, MEME calcul interne que avancer() (jamais
# duplique) -- meme doctrine que champ.gd:force_paire, destinee a
# l'observabilite d'un banc. Rend le delai requis (secondes) avant
# ignition pour "chose" si elle etait exposee des maintenant, ou -1.0 si
# elle ne peut JAMAIS s'enflammer -- POUR DEUX RAISONS DISTINCTES,
# DESORMAIS (chantier "point_ignition") : intensite effective sous le
# seuil configure (proxy, inchange), OU temperature locale sous le seuil
# porte par la propriete nommee par "propriete_point_ignition" (nom venu
# de la donnee, voir POINT_IGNITION plus haut) -- jamais une String, jamais un
# cas special que l'appelant devrait deviner ; l'appelant qui a besoin de
# savoir LEQUEL des deux a bloque relit les memes proprietes/parametres
# lui-meme (voir banc_point_ignition.gd:diagnostiquer pour un exemple qui
# n'a besoin que d'UN SEUL gate actif a la fois). Suppose
# "chose.proprietes.delai_propagation" deja
# present (avancer() alarme et s'arrete avant d'appeler cette fonction si
# ce n'est pas le cas ; un appelant d'observabilite qui viole ce contrat
# obtient une erreur GDScript standard, jamais un defaut invente).
static func delai_ignition(chose: Dictionary, intensite: Dictionary, etats: Dictionary, temperature_locale: float = INF) -> float:
	var delai: float = chose.proprietes.delai_propagation
	var propriete_intensite: String = intensite.get("propriete_intensite", "")
	if propriete_intensite != "" and chose.proprietes.has(propriete_intensite):
		var effective: float = EtatEffectif.valeur(chose, propriete_intensite, etats)
		if effective < intensite.get("seuil_ignition", 0.0):
			return -1.0
		delai = delai / effective
	var propriete_point_ignition: String = intensite.get("propriete_point_ignition", "")
	if propriete_point_ignition != "" and chose.proprietes.has(propriete_point_ignition) and temperature_locale < float(chose.proprietes[propriete_point_ignition]):
		return -1.0
	return delai

# Lecture SEULE, publique -- voir EMISSION ET SEUIL en tete de fichier.
# Rend ce qu'une "chose" recoit d'une seule source "feu" a l'instant
# present : emission de la source (_emission(), fonction de sa taille)
# divisee par le carre de la distance qui les separe. La distance est
# planchee a un minimum infime (jamais exactement 0.0) pour rendre un
# nombre fini meme a bout portant -- pas de cas special, pas d'infini
# affiche a l'ecran ni compare a un seuil.
static func recu(chose: Dictionary, feu: Dictionary, emission: Dictionary) -> float:
	var e := _emission(feu, emission)
	var d: float = maxf(chose.position.distance_to(feu.position), 0.0001)
	return e / (d * d)

# Lecture SEULE, publique -- voir EMISSION ET SEUIL en tete de fichier.
# Rend le seuil d'exposition d'une "chose" : "emission.seuil_base" divise
# par son intensite EFFECTIVE (EtatEffectif.valeur, meme lecture que
# delai_ignition -- jamais une propriete separee). Une chose dont
# l'intensite effective resout a 0.0 (propriete absente, propriete_
# intensite non configuree, ou un etat qui l'ECRASE a 0.0) rend INF --
# jamais exposee, quelle que soit la distance, meme traitement que
# "ne peut jamais s'enflammer" ailleurs dans ce fichier.
static func seuil_exposition(chose: Dictionary, intensite: Dictionary, etats: Dictionary, emission: Dictionary) -> float:
	var propriete_intensite: String = intensite.get("propriete_intensite", "")
	var effective: float = EtatEffectif.valeur(chose, propriete_intensite, etats)
	if effective <= 0.0:
		return INF
	return emission.get("seuil_base", 0.0) / effective

# Prive -- voir EMISSION ET SEUIL en tete de fichier. Emission d'une
# source "feu" : une base flat plus un coefficient qui multiplie la
# capacite de sa reserve nommee ("emission.nom_reserve", canal deja
# calcule par objet.gd -- jamais recalcule ici). "nom_reserve" vide, ou
# source sans ce canal : capacite 0.0, l'emission retombe sur la base
# flat seule -- absence legitime, jamais une alarme.
static func _emission(feu: Dictionary, emission: Dictionary) -> float:
	var base: float = emission.get("portee_emission_base", 0.0)
	var coefficient: float = emission.get("portee_emission_par_capacite", 0.0)
	var nom_reserve: String = emission.get("nom_reserve", "")
	var capacite := 0.0
	if nom_reserve != "":
		capacite = feu.proprietes.get("reserves", {}).get(nom_reserve, {}).get("capacite", 0.0)
	return base + coefficient * capacite

static func _vulnerabilite(chose: Dictionary, menaces: Dictionary) -> String:
	for vuln in menaces:
		if chose.proprietes.get(vuln, false):
			return vuln
	return ""

static func _en_feu(chose: Dictionary, menaces: Dictionary) -> bool:
	for vuln in menaces:
		if chose.proprietes.get(menaces[vuln], false):
			return true
	return false
