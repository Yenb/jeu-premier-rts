extends RefCounted

# Mecanisme du vent (chantier "vent"). Repond a UNE question et une seule :
# quelle est la direction et la force du vent, a UNE position, a UN instant.
# Tout le reste du moteur ne fait qu'INTERROGER ce fichier -- aucun canal, aucun
# mecanisme voisin n'est cable ici (voir "REUTILISATION PAR D'AUTRES CANAUX"
# plus bas). Classe RefCounted SANS ETAT (fonctions static, meme discipline que
# tout le reste de scripts/) : le TEMPS est un parametre explicite (`temps`),
# jamais une horloge interne -- meme convention que senescence.gd/gestation.gd,
# qui recoivent delta/temps en parametre plutot que de le compter eux-memes.
#
# Recoit (vecteur(), la fonction d'agregation complete) : `position` (Vector3,
# ou l'on interroge -- necessaire aux sources locales, sans effet sur les trois
# couches de fond), `temps` (float, secondes ecoulees depuis un instant de
# reference arbitraire choisi par l'appelant -- une fonction PURE de `temps`,
# rejouer le meme `temps` rend toujours le meme vent), `catalogue` (data/vent.json,
# entree structurelle "defaut" -- voir REFERENCE_DEFAUT), `sources_locales`
# (Array, FACULTATIF, defaut [] -- voir PERTURBATION LOCALE plus bas).
#
# Rend : Vector3 -- le "vecteur vent" complet, DIRECTION ET FORCE confondues
# dans un seul Vector3 (comme fuite.gd:direction, mais ici NON normalise : sa
# longueur EST la force, `vecteur.normalized()` EST la direction). Un vent nul
# est Vector3.ZERO, jamais un Vector3 de longueur non nulle avec une force a
# part -- un seul objet a lire, jamais deux nombres a synchroniser.
#
# TROIS COUCHES ADDITIVES, TOUTES DANS LA MEME DONNEE (data/vent.json:defaut),
# CHACUNE DESACTIVABLE SANS CASSER LES DEUX AUTRES (chaque amplitude/force a
# 0.0, ou periode/frequence a 0.0, retombe sur "cette couche ne contribue rien",
# jamais une alarme -- ce sont des reglages, pas des references de catalogue) :
#
# 1. FOND -- direction et force de depart, deux nombres fixes (fond.direction,
#    Vector3 serialise {x,y,z} ; fond.force, float).
# 2. VARIATION LENTE -- fait tourner la direction et onduler la force au fil du
#    temps (patron "direction dominante stable, magnitude modulee dans le
#    temps") : la direction du fond est tournee d'un ANGLE qui oscille en sinus
#    (amplitude_angle en degres, periode_angle en secondes pour un cycle
#    complet) AUTOUR DE L'AXE Z (Vector3(0,0,1)) -- choix documente, pas
#    configurable en donnee : coherent avec les positions de banc en
#    Vector3(x,y,0), le plan XY est le plan de jeu observe a l'ecran (voir
#    Scene/*.tscn, Node2D). La force oscille de la meme facon, INDEPENDAMMENT
#    (amplitude_force/periode_force), autour de fond.force. `dephasage_angle`/
#    `dephasage_force` (facultatifs, defaut 0.0, secondes) decalent chaque
#    oscillation dans le temps -- evite que les deux couches ne culminent
#    exactement au meme instant, qui donnerait un vent trop lisiblement
#    "regulier".
# 3. RAFALES -- variation RAPIDE de la force autour de sa valeur courante (donc
#    APRES la variation lente, jamais a la place) : un second sinus, plus court,
#    amplitude et frequence (Hz, cycles par seconde -- pas une periode, cette
#    couche est nommee par sa frequence dans data/vent.json comme demande) en
#    donnee, `dephasage` facultatif.
#
# Chaque couche est un SINUS PUR, fonction du seul `temps` -- aucun etat,
# aucune horloge, aucun hasard (voir CLAUDE.md, "aucun hasard non-seede") :
# rejouer le meme `temps` rend TOUJOURS le meme vent, ce qui rend le mecanisme
# testable sans avancer de vraies secondes.
#
# PERTURBATION LOCALE ("Point Wind", patron Unreal) -- LA PORTE D'ENTREE
# SEULEMENT, aucune source cablee dans ce chantier (ni feu, ni mur, ni relief) :
# `sources_locales` est un Array de Dictionary `{ position: Vector3, rayon:
# float, vecteur: Vector3 }`, construit et possede ENTIEREMENT par l'appelant
# -- ce fichier ne charge, ne fabrique, ne pose jamais aucune source lui-meme,
# il se contente de les AGREGER a chaque appel de vecteur(). N'IMPORTE QUEL
# mecanisme futur peut poser une source (un feu qui cree un appel d'air, un mur
# qui cree un abri) : il lui suffit de construire ce Dictionary et de le passer
# a vecteur() -- aucune reference de catalogue, aucune fabrication, aucun
# enregistrement special n'est requis ici. QUAND DEUX SOURCES SE RECOUVRENT :
# elles S'ADDITIONNENT, jamais un ecrasement ni une moyenne -- chaque source
# contribue independamment son `vecteur` pondere par sa propre attenuation a la
# distance interrogee, la somme des contributions s'ajoute au vent ambiant deja
# calcule (voir ORDRE DE COMPOSITION). Une source dont `position`/`rayon`/
# `vecteur` manque est STRUCTURELLEMENT incomplete (elle n'a pas de sens sans
# les trois) : push_error nommant l'index, cette source SEULE est ignoree, les
# autres continuent -- `sources_locales` dans son ensemble reste FACULTATIVE
# (defaut [], aucune perturbation, point neutre legitime, aucune alarme). Hors
# du rayon d'une source (distance > rayon), sa contribution est NULLE -- pas de
# vent "residuel" au-dela du rayon déclaré.
# ORDRE DE COMPOSITION : le vent AMBIANT (fond + variation lente + rafales, un
# seul Vector3 independant de la position) est calcule D'ABORD ; les
# contributions de TOUTES les sources locales a portee de `position` sont
# ENSUITE additionnees par-dessus, dans l'ordre ou elles apparaissent dans
# `sources_locales` (l'addition vectorielle est commutative : l'ordre ne change
# jamais le resultat, seulement la lisibilite d'un eventuel print de diagnostic
# futur). Aucune source ne peut donc jamais ANNULER le vent ambiant hors de son
# propre rayon, et aucune source ne remplace jamais le vent ambiant a
# l'interieur de son rayon -- elle s'y AJOUTE.
# ATTENUATION D'UNE SOURCE : `1.0 - distance/rayon` (nul au bord, plein au
# centre), eleve a `attenuation_source.exposant` (data/vent.json, PARTAGE par
# toutes les sources d'un appel -- 1.0 = lineaire, plus grand = chute plus
# rapide pres du bord). Forme UNIQUE aujourd'hui, deliberement -- une source ne
# porte pas sa propre forme, voir data/vent.json.
#
# facteur_directionnel(vecteur_vent, direction_cible, catalogue) -> float :
# fonction SEPAREE, PURE, GENERIQUE -- ne mentionne ni odorat, ni canal, ni
# colon. Traduit l'angle entre un vent DEJA CONNU (le Vector3 rendu par
# vecteur() a la position du percepteur) et une direction cible (percepteur ->
# chose, PAS necessairement normalisee) en un FACTEUR MULTIPLICATIF CONTINU,
# destine a etre applique a une PORTEE de perception -- jamais un couperet
# dedans/dehors (voir docs/design.md, la perception reste aveugle/exhaustive
# DANS sa geometrie, seule la geometrie elle-meme change de taille). CONVENTION
# DE SIGNE (a ne pas re-decider ailleurs) : produit scalaire = +1.0 (la cible
# est dans le sens ou souffle le vent, "sous le vent DEPUIS le percepteur") ->
# facteur_max_sous_vent (portee allongee) ; produit scalaire = -1.0 (la cible
# est a l'oppose, "contre le vent") -> facteur_min_contre_vent (portee
# reduite) ; produit scalaire = 0.0 (perpendiculaire) -> TOUJOURS exactement
# 1.0, jamais une valeur de donnee -- interpolation en DEUX MORCEAUX
# (lerp(1.0, facteur_max, dot) si dot >= 0, lerp(1.0, facteur_min, -dot)
# sinon), pas une seule droite entre facteur_min et facteur_max, pour garantir
# ce point milieu quelles que soient les deux valeurs de donnee (qui n'ont
# aucune raison d'etre symetriques). L'AMPLITUDE de cet effet est elle-meme
# proportionnelle a la FORCE du vent courant (`intensite = clamp(force /
# reference_force, 0.0, 1.0)`, `facteur_final = lerp(1.0, facteur_angle,
# intensite)`) -- UN VENT NUL (Vector3.ZERO, force 0.0) REND DONC TOUJOURS
# EXACTEMENT 1.0, quel que soit l'angle : ce n'est pas un cas particulier
# code a part, c'est une PROPRIETE DE LA FORMULE (intensite = 0.0 => lerp
# retombe sur son premier argument). C'est ce qui garantit que "vent absent"
# et "vent nul explicitement fourni" produisent le meme resultat neutre par le
# MEME calcul, jamais deux chemins de code distincts.
# CONSEQUENCE POUR TOUT APPELANT, a lire avant d'ecrire un test d'orientation :
# ce facteur ne descend JAMAIS a zero et n'est jamais negatif -- il vaut 1.0 au
# neutre, plus au vent portant, moins au vent contraire. Tester « ce voisin est
# sous le vent » s'ecrit donc `facteur > 1.0`, JAMAIS `facteur > 0.0`, qui
# serait TOUJOURS vrai et rendrait une diffusion isotrope au lieu de l'effet
# oriente qu'on croyait ecrire -- faux positif silencieux, aucun test ne
# rougirait.
#
# REUTILISATION PAR D'AUTRES CANAUX (son, feu, vue), CE QUI RESTERAIT A FAIRE :
# ce fichier ne connait aucun canal -- perception.gd:_percevoir_sphere_
# directionnelle (odorat, premier et seul appelant a ce jour) en est la preuve :
# aucune chaine "odorat" n'apparait ici. Pour brancher un futur canal, il
# suffirait a l'appelant de : (1) calculer `Vent.vecteur(position_du_percepteur,
# temps, catalogue_vent, sources_vent)` UNE FOIS par appel ; (2) pour chaque
# candidat, appeler `Vent.facteur_directionnel(vecteur_vent, direction_vers_
# candidat, catalogue_vent)` ; (3) multiplier la portee de base de CE canal par
# le facteur rendu, et comparer la distance reelle a cette portee module —
# exactement le geste deja fait dans perception.gd. AUCUNE ligne de ce fichier
# n'aurait a changer ; le seul travail cote appelant est de sortir d'une
# delegation eventuelle a une requete spatiale a rayon UNIQUE (comme
# monde.gd:choses_dans_rayon) vers une boucle PAR CANDIDAT, puisque la portee
# modulee depend de la direction vers CHAQUE candidat, jamais d'un seul
# scalaire partage par toute la requete (voir perception.gd pour l'exemple
# concret sur l'odorat).
#
# STRUCTUREL vs FACULTATIF : `catalogue["defaut"]` (REFERENCE_DEFAUT) est
# STRUCTUREL pour vecteur()/facteur_directionnel() -- son absence signifie que
# l'appelant a oublie de charger data/vent.json, jamais une intention
# legitime : push_error puis repli neutre (Vector3.ZERO / 1.0). `sources_
# locales` est FACULTATIVE dans son ensemble (defaut []) ; CHAQUE source y est
# structurellement complete ou ignoree seule (voir PERTURBATION LOCALE). Toute
# sous-cle des trois couches (amplitude/periode/frequence/dephasage) est
# FACULTATIVE, defaut 0.0 -- une couche absente de la donnee ne contribue
# simplement rien, jamais une alarme : ce sont des reglages continus, pas des
# references qu'un nom pourrait manquer de resoudre.

const REFERENCE_DEFAUT := "defaut"
const _AXE_ROTATION := Vector3(0.0, 0.0, 1.0)

static func vecteur(position: Vector3, temps: float, catalogue: Dictionary, sources_locales: Array = []) -> Vector3:
	if not catalogue.has(REFERENCE_DEFAUT):
		push_error("vent.gd : entree '%s' absente du catalogue de vent" % REFERENCE_DEFAUT)
		return Vector3.ZERO
	var config: Dictionary = catalogue[REFERENCE_DEFAUT]
	var ambiant: Vector3 = _direction_courante(config, temps) * _force_courante(config, temps)
	var total: Vector3 = ambiant
	for i in sources_locales.size():
		total += _contribution_source(position, sources_locales[i], config, i)
	return total

static func facteur_directionnel(vecteur_vent: Vector3, direction_cible: Vector3, catalogue: Dictionary) -> float:
	if vecteur_vent.length() <= 0.0001 or direction_cible.length() <= 0.0001:
		return 1.0
	if not catalogue.has(REFERENCE_DEFAUT):
		push_error("vent.gd : entree '%s' absente du catalogue de vent" % REFERENCE_DEFAUT)
		return 1.0
	var config: Dictionary = catalogue[REFERENCE_DEFAUT]
	if not config.has("directionnel"):
		push_error("vent.gd : 'directionnel' absent de l'entree '%s'" % REFERENCE_DEFAUT)
		return 1.0
	var directionnel: Dictionary = config.directionnel
	var reference_force: float = directionnel.get("reference_force", 0.0)
	if reference_force <= 0.0:
		return 1.0
	var dot: float = vecteur_vent.normalized().dot(direction_cible.normalized())
	var facteur_max: float = directionnel.get("facteur_max_sous_vent", 1.0)
	var facteur_min: float = directionnel.get("facteur_min_contre_vent", 1.0)
	var facteur_angle: float = lerp(1.0, facteur_max, dot) if dot >= 0.0 else lerp(1.0, facteur_min, -dot)
	var intensite: float = clamp(vecteur_vent.length() / reference_force, 0.0, 1.0)
	return lerp(1.0, facteur_angle, intensite)

# Direction du fond, rendue A PLAT (1,0,0) si non declaree (aucune direction
# ne peut etre devinee ni valoir Vector3.ZERO : une direction nulle rendrait
# toute rotation ulterieure sans effet, un repli explicite et documente vaut
# mieux qu'un vent qui ne pointe jamais nulle part).
static func _direction_courante(config: Dictionary, temps: float) -> Vector3:
	var base: Vector3 = _vecteur_depuis_dict(config.get("fond", {}).get("direction", {}))
	if base.length() <= 0.0001:
		base = Vector3(1.0, 0.0, 0.0)
	base = base.normalized()
	var lente: Dictionary = config.get("variation_lente", {})
	var amplitude: float = lente.get("amplitude_angle", 0.0)
	var periode: float = lente.get("periode_angle", 0.0)
	if amplitude == 0.0 or periode <= 0.0:
		return base
	var dephasage: float = lente.get("dephasage_angle", 0.0)
	var angle_deg: float = amplitude * sin(TAU * (temps + dephasage) / periode)
	return base.rotated(_AXE_ROTATION, deg_to_rad(angle_deg))

static func _force_courante(config: Dictionary, temps: float) -> float:
	var force: float = config.get("fond", {}).get("force", 0.0)
	var lente: Dictionary = config.get("variation_lente", {})
	var amplitude_lente: float = lente.get("amplitude_force", 0.0)
	var periode_lente: float = lente.get("periode_force", 0.0)
	if amplitude_lente != 0.0 and periode_lente > 0.0:
		var dephasage_lente: float = lente.get("dephasage_force", 0.0)
		force += amplitude_lente * sin(TAU * (temps + dephasage_lente) / periode_lente)
	var rafales: Dictionary = config.get("rafales", {})
	var amplitude_rafale: float = rafales.get("amplitude", 0.0)
	var frequence_rafale: float = rafales.get("frequence", 0.0)
	if amplitude_rafale != 0.0 and frequence_rafale > 0.0:
		var dephasage_rafale: float = rafales.get("dephasage", 0.0)
		force += amplitude_rafale * sin(TAU * frequence_rafale * (temps + dephasage_rafale))
	return max(force, 0.0)

static func _vecteur_depuis_dict(d: Dictionary) -> Vector3:
	return Vector3(d.get("x", 0.0), d.get("y", 0.0), d.get("z", 0.0))

# Une source structurellement incomplete (position/rayon/vecteur manquant) est
# ignoree SEULE -- push_error nommant son index dans sources_locales, les
# autres sources continuent d'etre agregees normalement.
static func _contribution_source(position: Vector3, source: Dictionary, config: Dictionary, index: int) -> Vector3:
	if not (source.has("position") and source.has("rayon") and source.has("vecteur")):
		push_error("vent.gd : source locale #%d incomplete (position/rayon/vecteur requis), ignoree" % index)
		return Vector3.ZERO
	var rayon: float = source.rayon
	if rayon <= 0.0:
		return Vector3.ZERO
	var distance: float = position.distance_to(source.position)
	if distance > rayon:
		return Vector3.ZERO
	var exposant: float = config.get("attenuation_source", {}).get("exposant", 1.0)
	var ratio: float = clamp(1.0 - distance / rayon, 0.0, 1.0)
	return source.vecteur * pow(ratio, exposant)
