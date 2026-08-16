extends RefCounted

# Mecanisme de temperature (chantier "temperature"), mecanisme de base
# SEUL : aucun allumage, aucun seuil de fusion, aucune descente d'etat,
# aucun abri -- ces trois-la sont des chantiers separes, hors perimetre.
# Repond a deux questions : quelle est la temperature locale a une
# position (somme des ecarts de sources a portee, attenues par distance --
# meme patron que vent.gd:vecteur, sources_locales) ; et a quelle vitesse
# un objet rejoint cette temperature locale sur un pas de temps (loi de
# Newton, dT = conductivite * (T_locale - T_objet) * delta -- PAS le
# patron de charge.gd, dont la formule de montee/descente (deux regimes
# disjoints, cible fixe a zero) ne convient pas ici, voir
# audit_temperature_superposition.md §2). Classe RefCounted SANS ETAT
# (fonctions static, meme discipline que tout le reste de scripts/).
#
# Recoit (locale()) : `position` (Vector3, ou l'on interroge), `sources`
# (Array de Dictionary { position: Vector3, rayon: float, temperature:
# float, force: float }, construit et POSSEDE ENTIEREMENT par l'appelant
# -- ce fichier ne fabrique, ne charge, ne pose jamais aucune source
# lui-meme, meme patron que vent.gd:sources_locales), `catalogue`
# (data/temperature.json, entree structurelle "defaut").
# Rend : float -- la temperature locale ABSOLUE (ambiante + somme des
# ecarts ponderes des sources a portee), jamais un ecart seul.
#
# Recoit (avancer()) : `monde` (Array de { id, position, proprietes },
# MUTE EN PLACE -- proprietes.temperature ecrasee par la nouvelle valeur),
# `sources` (meme forme que locale()), `delta` (secondes ecoulees),
# `catalogue` (data/temperature.json).
# Rend : rien (void) -- ce mecanisme ne franchit aucun seuil, ne pose ni
# ne retire aucune cause (contrairement a charge.gd) ; une chose sans
# `conductivite_thermique` (proprietes.conductivite_thermique, FACULTATIVE,
# defaut 0.0 -- objet sans composition, ou materiau sans cette fiche, voir
# data/proprietes_immuables_composition.json) reste thermiquement inerte,
# point neutre legitime, jamais une alarme.
#
# INERTIE THERMIQUE (chantier "colonne thermique", cases 1 et 2 du tableau
# Thermique -- voir docs/orion-matrice-elements.md) : `chaleur_specifique`
# (proprietes.chaleur_specifique, meme statut FACULTATIF que conductivite,
# meme catalogue de fusion) DIVISE la loi de Newton -- une chose a haute
# chaleur_specifique (pierre, 790.0) rejoint sa cible plus LENTEMENT qu'une
# chose a basse chaleur_specifique (fer, 450.0), a conductivite egale :
# c'est la grandeur physique reelle (il faut plus d'energie pour changer la
# temperature d'une matiere qui en emmagasine plus). DEFAUT SI ABSENTE OU
# NULLE : `1.0` -- ce choix, et lui seul, laisse la formule EXACTEMENT
# identique a avant ce chantier (diviser par 1.0 ne change rien), donc
# aucun objet existant qui ne porte pas encore chaleur_specifique (fusion
# via une fiche materiau qui ne la documente pas, ou objet sans
# composition) ne change de comportement. Une valeur nulle ou negative est
# traitee comme absente (repli sur 1.0), jamais une division par zero.
#
# SUPERPOSITION ADDITIVE, comme vent.gd : plusieurs sources a portee d'un
# meme point, leurs ecarts PONDERES s'additionnent, jamais une moyenne.
# Hors du rayon d'une source, sa contribution est NULLE -- pas de residu
# au-dela du rayon declare. Une source dont position/rayon/temperature/
# force manque est STRUCTURELLEMENT incomplete : push_error nommant
# l'index, cette source SEULE est ignoree, les autres continuent --
# `sources` dans son ensemble reste FACULTATIF (defaut [], aucune
# influence, ambiante seule partout).
# ATTENUATION D'UNE SOURCE : `1.0 - distance/rayon` (nul au bord, plein au
# centre), eleve a `catalogue.defaut.attenuation.exposant` -- MEME FORME
# que vent.gd:_contribution_source, recopiee ici (voir
# audit_temperature_superposition.md §1 : le meme calcul applique a un
# ecart scalaire plutot qu'a un Vector3 n'est PAS appelable tel quel en
# GDScript, `Vector3 * float` et `float * float` ne sont pas la meme
# operation -- c'est un COPIER-PATRON, jamais un COPIER-CODE, aucune ligne
# de vent.gd n'est partagee ni modifiee).
#
# LOI DE NEWTON (avancer()) : dT = (conductivite / chaleur_specifique) *
# (T_locale - T_objet) * delta, T_objet_nouveau = T_objet + dT -- UN SEUL
# calcul continu, toujours actif, jamais les deux regimes disjoints de
# charge.gd (monte si une cause est a portee / descend a taux fixe vers
# ZERO). Un objet chaud loin de toute source retombe vers l'ambiante par la
# MEME formule (T_locale degenere en l'ambiante seule, hors de toute
# source) -- pas un cas particulier code a part. Vite d'abord, puis de plus
# en plus lentement : PROPRIETE DE LA FORMULE (l'ecart retrecit a chaque
# pas, jamais une valeur ecrite a la main). Voir INERTIE THERMIQUE
# ci-dessus pour chaleur_specifique et son defaut.
# DIVERGE A GRAND DELTA, et c'est le SEUL mecanisme du depot dans ce cas :
# l'integration est un EULER EXPLICITE. Des que (conductivite /
# chaleur_specifique) * delta depasse 2.0, le pas DEPASSE SA PROPRE CIBLE
# et la temperature oscille en s'eloignant au lieu de converger. Une simulation
# acceleree REPETE un petit pas, elle n'agrandit JAMAIS le delta -- une
# accélération naive casse le resultat en silence, sans alarme.
#
# DILATATION THERMIQUE (chantier "colonne thermique", case 5, DERNIERE case
# du tableau Thermique) : `dilatation_thermique` (proprietes.
# dilatation_thermique, FACULTATIVE, defaut 0.0 -- meme statut que
# conductivite/chaleur_specifique, fusionnee par le meme patron generique)
# fait varier le VOLUME de l'objet a mesure que sa temperature change : sur
# CE pas, dV = dilatation_thermique * dT (le dT calcule par la loi de Newton
# ci-dessus, jamais un ecart total), ajoute a `proprietes.volume`. La MASSE
# ne change jamais ici (aucun mecanisme de ce fichier n'ecrit
# `proprietes.masse`) -- la densite est donc RECALCULEE depuis le nouveau
# volume (`densite = masse / volume`), jamais reposee independamment,
# pour que masse/volume/densite restent cette meme identite partout dans
# le depot (voir objet.gd, DENSITE EFFECTIVE). Un volume qui retombe a zero
# ou en dessous (donnee extreme, pas rencontree avec les valeurs reelles du
# depot) laisse la densite a sa derniere valeur valide plutot que de diviser
# par zero ou par un nombre negatif. Absente ou nulle : AUCUN changement de
# volume ni de densite, comportement rigoureusement identique a avant ce
# chantier.
#
# STRUCTUREL vs FACULTATIF : `catalogue["defaut"]` est STRUCTUREL pour
# locale()/avancer() -- son absence signifie que l'appelant a oublie de
# charger data/temperature.json, jamais une intention legitime :
# push_error puis repli neutre (locale() rend 0.0 -- PAS 20.0 : un repli
# sur l'ambiante par defaut maquillerait une erreur de cablage en lecture
# plausible ; avancer() ne mute rien). `sources` est FACULTATIVE dans son
# ensemble (defaut [], ambiante partout) ; CHAQUE source est
# structurellement complete ou ignoree seule (voir SUPERPOSITION ci-dessus).
# `proprietes.temperature` (paquet objet_physique) est STRUCTURELLE sur
# l'objet avance dans `avancer()` -- son absence dit "ceci n'est pas un
# objet physique", jamais une alarme silencieuse repliee sur 20.0 (une
# chose qui compose reellement objet_physique la porte TOUJOURS, defaut
# 20.0 au paquet). `proprietes.conductivite_thermique` reste FACULTATIVE
# (defaut 0.0, objet thermiquement inerte -- point neutre legitime).

const REFERENCE_DEFAUT := "defaut"

static func locale(position: Vector3, sources: Array, catalogue: Dictionary) -> float:
	if not catalogue.has(REFERENCE_DEFAUT):
		push_error("temperature.gd : entree '%s' absente du catalogue de temperature" % REFERENCE_DEFAUT)
		return 0.0
	var config: Dictionary = catalogue[REFERENCE_DEFAUT]
	var ambiante: float = config.get("ambiante", 20.0)
	var total: float = ambiante
	for i in sources.size():
		total += _contribution_source(position, sources[i], config, i, ambiante)
	return total

static func avancer(monde: Array, sources: Array, delta: float, catalogue: Dictionary) -> void:
	if not catalogue.has(REFERENCE_DEFAUT):
		push_error("temperature.gd : entree '%s' absente du catalogue de temperature" % REFERENCE_DEFAUT)
		return
	for chose in monde:
		var proprietes: Dictionary = chose.proprietes
		if not proprietes.has("temperature"):
			push_error("temperature.gd : chose '%s' sans propriete 'temperature' (paquet objet_physique attendu)" % str(chose.get("id", "?")))
			continue
		var conductivite: float = proprietes.get("conductivite_thermique", 0.0)
		var chaleur_specifique: float = proprietes.get("chaleur_specifique", 1.0)
		if chaleur_specifique <= 0.0:
			chaleur_specifique = 1.0
		var t_locale: float = locale(chose.position, sources, catalogue)
		var t_objet: float = proprietes.temperature
		var dt: float = (conductivite / chaleur_specifique) * (t_locale - t_objet) * delta
		proprietes.temperature = t_objet + dt
		var dilatation_thermique: float = proprietes.get("dilatation_thermique", 0.0)
		if dilatation_thermique != 0.0:
			proprietes.volume = proprietes.volume + dilatation_thermique * dt
			if proprietes.volume > 0.0:
				proprietes.densite = proprietes.masse / proprietes.volume

# Une source structurellement incomplete (position/rayon/temperature/force
# manquant) est ignoree SEULE -- push_error nommant son index dans
# `sources`, les autres sources continuent d'etre agregees normalement.
static func _contribution_source(position: Vector3, source: Dictionary, config: Dictionary, index: int, ambiante: float) -> float:
	if not (source.has("position") and source.has("rayon") and source.has("temperature") and source.has("force")):
		push_error("temperature.gd : source locale #%d incomplete (position/rayon/temperature/force requis), ignoree" % index)
		return 0.0
	var rayon: float = source.rayon
	if rayon <= 0.0:
		return 0.0
	var distance: float = position.distance_to(source.position)
	if distance > rayon:
		return 0.0
	var exposant: float = config.get("attenuation", {}).get("exposant", 1.0)
	var ratio: float = clamp(1.0 - distance / rayon, 0.0, 1.0)
	return (source.temperature - ambiante) * source.force * pow(ratio, exposant)
