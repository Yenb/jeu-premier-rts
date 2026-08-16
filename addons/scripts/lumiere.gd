extends RefCounted

# Mecanisme de lumiere ambiante (chantier "lumiere ambiante -- scalaire
# ambiant avec temperature de couleur"), TROISIEME scalaire/vecteur ambiant
# du depot apres vent.gd (vecteur) et temperature.gd (scalaire simple) --
# PREMIER a porter DEUX composantes couplees (intensite ET couleur).
# Recopie le PATRON de vent.gd/temperature.gd -- sources locales possedees
# et fournies ENTIEREMENT par l'appelant, superposition ADDITIVE des
# contributions ponderees par source, attenuation
# (1-distance/rayon)^exposant -- jamais leur code (COPIER-PATRON, pas
# COPIER-CODE, voir temperature.gd en-tete). Classe RefCounted SANS ETAT
# (fonctions static, meme discipline que tout scripts/).
#
# Repond a deux questions, MEME SIGNATURE que temperature.gd cote
# parametres (position/sources/catalogue, monde/sources/delta/catalogue),
# mais rend un Dictionary { intensite: float, couleur: float } au lieu
# d'un float seul : quelle est la lumiere a une position (locale()) ; a
# quelle vitesse un objet la rejoint (avancer()).
#
# INTENSITE (0.0 noir total, 1.0 plein soleil) : CONTRIBUTION ADDITIVE
# PURE, jamais un ecart -- une source de lumiere AJOUTE (comme
# vent.gd:_contribution_source, `source.vecteur * atten`), elle ne tire
# jamais vers sa propre valeur absolue (contrairement a temperature.gd,
# qui soustrait l'ambiante -- une source thermique transmet vers
# l'equilibre, une source lumineuse eclaire, point). Le total (ambiante +
# sources) est BORNE A [0.0, 1.0] en sortie de locale() -- SEULE
# DIFFERENCE DE BORNAGE avec temperature.gd (dont la locale() reste
# ouverte) : l'intensite lumineuse a un plafond physique (plein jour),
# contrairement a une temperature.
#
# COULEUR (0.0 orange chaud, 1.0 bleu froid -- une temperature de couleur
# SCALAIRE, jamais une teinte RGB : passer de ce scalaire a une couleur
# affichable est un geste d'AFFICHAGE, il vit au cablage et jamais ici) :
# MOYENNE PONDEREE des couleurs a portee, PAS une
# contribution additive -- deux sources qui se recouvrent ne rendent
# jamais une couleur "plus forte", elles rendent une couleur ENTRE les
# deux. Le poids de chaque source est SA PROPRE CONTRIBUTION D'INTENSITE
# a ce point (source.intensite * source.force * attenuation, LA MEME
# valeur que la boucle d'intensite calcule deja -- jamais une pondmoyenne
# recalculee a part) : une source proche et forte pese plus qu'une source
# lointaine et faible, exactement comme on s'y attend a l'oeil. La couleur
# AMBIANTE (soleil) entre dans CETTE MEME moyenne comme un "fond", pondere
# par SA PROPRE intensite ambiante -- en plein jour (ambiante forte), une
# torche proche doit lutter pour teinter la scene ; en pleine nuit
# (ambiante nulle), une seule torche a portee impose entierement sa
# couleur. SANS AUCUNE CONTRIBUTION (ni ambiante ni source, poids total
# nul) : repli EXPLICITE sur la couleur ambiante seule (jamais une
# division par zero, jamais une couleur neutre inventee) -- c'est ce qui
# garantit qu'une nuit totalement sombre reste tout de meme BLEUE (voir
# data/lumiere.json:defaut.ambiante.couleur), jamais une couleur
# indefinie.
#
# LE SOLEIL (soleil()), TROISIEME fonction, INDEPENDANTE de locale()/
# avancer() : fonction PURE de l'heure et de la latitude, PAS une source
# posee dans le monde -- rien de commun avec `sources` (une liste de
# Dictionary POSSEDEE par l'appelant : torche, feu, lanterne portee,
# lune). Rend { intensite, couleur } :
# - intensite : angle horaire (heure rapportee a heure_midi/
#   heures_par_jour, EN DONNEE) mis en cosinus, multiplie par
#   cos(latitude) -- le pic chute vers les poles (0 a l'equateur = pic
#   plein a 1.0, 90 = jamais de jour), SIMPLIFICATION ASSUMEE : aucune
#   declinaison saisonniere, hors perimetre de ce chantier. BORNE
#   EXPLICITEMENT A [0.0, 1.0] (clamp, pas seulement un plancher -- meme
#   si le produit de deux cosinus ne peut deja pas depasser 1.0 par
#   construction, le clamp haut reste ecrit pour rendre le contrat
#   LISIBLE sans avoir a le deduire).
# - couleur : PAS une formule fermee -- une COURBE PAR MORCEAUX, EN
#   DONNEE (data/lumiere.json:defaut.courbe_couleur, Array de { heure,
#   couleur } TRIE PAR HEURE CROISSANTE, premier et dernier point couvrant
#   tout le cycle -- ex. heure 0.0 ET heure heures_par_jour partagent la
#   meme couleur pour que l'interpolation boucle sans code special).
#   Interpolation LINEAIRE entre les deux points qui encadrent l'heure
#   (modulo heures_par_jour -- une heure hors [0, heures_par_jour) est
#   ramenee dans cet intervalle AVANT de chercher les points, jamais une
#   heure negative ou > 24 laissee telle quelle). Heure avant le premier
#   point ou apres le dernier (courbe qui ne couvre pas tout le cycle,
#   donnee incomplete) : repli sur la valeur du point le plus proche,
#   jamais une extrapolation.
#
# L'APPELANT (JAMAIS ce fichier) est responsable d'appeler soleil() puis
# d'ecrire son resultat dans une copie de catalogue.defaut.ambiante AVANT
# d'appeler locale()/avancer() -- exactement comme temperature.gd lit
# catalogue.defaut.ambiante SANS jamais savoir d'ou cette valeur vient
# (pour temperature.gd c'est une constante universelle ; ici l'appelant la
# rafraichit chaque tick depuis soleil()). Ca garde locale()/avancer() a
# la MEME arite que temperature.gd (aucune notion d'heure ni de latitude
# n'y entre jamais), et fait du cycle jour/nuit un TROISIEME appel
# explicite, jamais couple a la boucle sources/attenuation.
#
# Recoit (locale()) : `position` (Vector3, ou l'on interroge), `sources`
# (Array de Dictionary { position: Vector3, rayon: float, intensite:
# float, temperature_couleur: float, force: float }, CONSTRUIT ET POSSEDE
# ENTIEREMENT PAR L'APPELANT -- une torche, un feu, une lanterne portee,
# la lune -- ce fichier ne fabrique, ne charge, ne pose, ne deplace JAMAIS
# aucune source lui-meme, meme patron que vent.gd:sources_locales/
# temperature.gd:sources), `catalogue` (data/lumiere.json, entree
# structurelle "defaut").
# Rend : Dictionary { intensite: float, couleur: float } -- intensite
# BORNEE [0.0, 1.0], couleur JAMAIS bornee ici (une moyenne ponderee de
# valeurs deja dans [0.0, 1.0] y reste par construction, aucun clamp
# supplementaire necessaire).
#
# Recoit (avancer()) : `monde` (Array de { id, position, proprietes },
# MUTE EN PLACE -- proprietes.intensite_lumiere/couleur_lumiere ECRASEES
# par la nouvelle valeur, jamais lues pour un calcul de vitesse :
# CONVERGENCE INSTANTANEE, voir plus haut), `sources` (meme forme que
# locale()), `delta` (secondes ecoulees -- RECU PAR SYMETRIE avec
# temperature.gd/le reste du depot, SANS EFFET sur le resultat : la
# convergence ne depend jamais du temps ecoule, seulement de la position
# courante), `catalogue` (data/lumiere.json).
# Rend : Array des ids dont intensite_lumiere OU couleur_lumiere a
# REELLEMENT change ce tick (avant vs apres, au-dela d'un epsilon
# flottant fixe) -- meme idiome que propagation.gd (ids nouvellement
# enflammes) : l'appelant journalise un changement, jamais chaque frame.
# Un objet qui ne portait pas encore ces deux cles compte toujours comme
# change (premiere pose).
#
# proprietes.intensite_lumiere/couleur_lumiere NE SONT PAS structurelles
# sur objet_physique (contrairement a proprietes.temperature) -- DECISION
# DE PERIMETRE ASSUMEE : ce chantier ne touche pas data/types.json, aucun
# banc reel Orion n'est demande ici. Un objet SANS ces cles prealables les
# recoit simplement a ce tick, sans alarme.
#
# STRUCTUREL vs FACULTATIF : `catalogue["defaut"]` est STRUCTUREL pour
# locale()/avancer()/soleil() -- son absence signifie que l'appelant a
# oublie de charger data/lumiere.json, jamais une intention legitime :
# push_error puis repli neutre (locale() rend { intensite: 0.0, couleur:
# 0.0 }, soleil() de meme, avancer() ne mute rien et rend []). `sources`
# est FACULTATIVE dans son ensemble (defaut [], aucune influence, ambiante
# seule partout) ; CHAQUE source est structurellement complete ou ignoree
# seule (voir _contribution_intensite), meme patron que vent.gd/
# temperature.gd. `courbe_couleur` FACULTATIVE (defaut [], repli sur
# ambiante.couleur si non fournie via config.ambiante, sinon 0.0).

const REFERENCE_DEFAUT := "defaut"
const _EPSILON_CHANGEMENT := 0.0001

static func locale(position: Vector3, sources: Array, catalogue: Dictionary) -> Dictionary:
	if not catalogue.has(REFERENCE_DEFAUT):
		push_error("lumiere.gd : entree '%s' absente du catalogue de lumiere" % REFERENCE_DEFAUT)
		return {"intensite": 0.0, "couleur": 0.0}
	var config: Dictionary = catalogue[REFERENCE_DEFAUT]
	var ambiante: Dictionary = config.get("ambiante", {})
	var ambiante_intensite: float = ambiante.get("intensite", 0.0)
	var ambiante_couleur: float = ambiante.get("couleur", 0.0)

	var intensite_brute: float = ambiante_intensite
	var poids_total: float = ambiante_intensite
	var couleur_ponderee: float = ambiante_intensite * ambiante_couleur

	for i in sources.size():
		var contribution: float = _contribution_intensite(position, sources[i], config, i)
		if contribution == 0.0:
			continue
		intensite_brute += contribution
		poids_total += contribution
		couleur_ponderee += contribution * float(sources[i].get("temperature_couleur", 0.0))

	var couleur_finale: float = ambiante_couleur if poids_total <= 0.0 else couleur_ponderee / poids_total
	return {"intensite": clamp(intensite_brute, 0.0, 1.0), "couleur": couleur_finale}

static func avancer(monde: Array, sources: Array, delta: float, catalogue: Dictionary) -> Array:
	if not catalogue.has(REFERENCE_DEFAUT):
		push_error("lumiere.gd : entree '%s' absente du catalogue de lumiere" % REFERENCE_DEFAUT)
		return []
	var changements: Array = []
	for chose in monde:
		var proprietes: Dictionary = chose.proprietes
		var avant_intensite: Variant = proprietes.get("intensite_lumiere", null)
		var avant_couleur: Variant = proprietes.get("couleur_lumiere", null)
		var resultat: Dictionary = locale(chose.position, sources, catalogue)
		proprietes.intensite_lumiere = resultat.intensite
		proprietes.couleur_lumiere = resultat.couleur
		var change := avant_intensite == null or avant_couleur == null \
			or absf(float(avant_intensite) - resultat.intensite) > _EPSILON_CHANGEMENT \
			or absf(float(avant_couleur) - resultat.couleur) > _EPSILON_CHANGEMENT
		if change:
			changements.append(chose.id)
	return changements

# heure/latitude vivent EN PARAMETRE (jamais en dur, jamais relues depuis
# une horloge interne -- meme convention que vent.gd) ; heure_midi/
# heures_par_jour/courbe_couleur vivent EN DONNEE (data/lumiere.json:
# defaut.cycle / defaut.courbe_couleur).
static func soleil(heure: float, latitude: float, catalogue: Dictionary) -> Dictionary:
	if not catalogue.has(REFERENCE_DEFAUT):
		push_error("lumiere.gd : entree '%s' absente du catalogue de lumiere" % REFERENCE_DEFAUT)
		return {"intensite": 0.0, "couleur": 0.0}
	var config: Dictionary = catalogue[REFERENCE_DEFAUT]
	var cycle: Dictionary = config.get("cycle", {})
	var heures_par_jour: float = cycle.get("heures_par_jour", 24.0)
	if heures_par_jour <= 0.0:
		return {"intensite": 0.0, "couleur": _couleur_courbe(0.0, [], 24.0)}
	var heure_midi: float = cycle.get("heure_midi", 12.0)
	var angle_horaire: float = TAU * (heure - heure_midi) / heures_par_jour
	var facteur_latitude: float = cos(deg_to_rad(latitude))
	var intensite: float = clamp(facteur_latitude * cos(angle_horaire), 0.0, 1.0)

	var courbe: Array = config.get("courbe_couleur", [])
	var couleur: float = _couleur_courbe(heure, courbe, heures_par_jour)
	return {"intensite": intensite, "couleur": couleur}

# Interpolation LINEAIRE par morceaux sur une courbe { heure, couleur }
# triee par heure croissante -- voir en-tete, section COULEUR du soleil.
# `heure` est d'abord ramenee dans [0, heures_par_jour) (fmod, gere aussi
# les heures negatives). Courbe vide : repli neutre 0.0 (jamais de
# division ni d'index hors bornes). Heure avant le premier point ou apres
# le dernier : repli sur le point le plus proche, jamais une
# extrapolation.
static func _couleur_courbe(heure: float, courbe: Array, heures_par_jour: float) -> float:
	if courbe.is_empty():
		return 0.0
	if courbe.size() == 1:
		return float(courbe[0].get("couleur", 0.0))

	var heure_mod: float = fmod(heure, heures_par_jour)
	if heure_mod < 0.0:
		heure_mod += heures_par_jour

	if heure_mod <= float(courbe[0].get("heure", 0.0)):
		return float(courbe[0].get("couleur", 0.0))
	var dernier: Dictionary = courbe[courbe.size() - 1]
	if heure_mod >= float(dernier.get("heure", heures_par_jour)):
		return float(dernier.get("couleur", 0.0))

	for i in range(courbe.size() - 1):
		var point_a: Dictionary = courbe[i]
		var point_b: Dictionary = courbe[i + 1]
		var heure_a: float = point_a.get("heure", 0.0)
		var heure_b: float = point_b.get("heure", 0.0)
		if heure_mod >= heure_a and heure_mod <= heure_b:
			if heure_b <= heure_a:
				return float(point_a.get("couleur", 0.0))
			var ratio: float = (heure_mod - heure_a) / (heure_b - heure_a)
			return lerp(float(point_a.get("couleur", 0.0)), float(point_b.get("couleur", 0.0)), ratio)
	return float(dernier.get("couleur", 0.0))

# Une source structurellement incomplete (position/rayon/intensite/force
# manquant -- temperature_couleur EXCLUE de cette liste, voir plus bas)
# est ignoree SEULE -- push_error nommant son index dans `sources`, les
# autres sources continuent d'etre agregees normalement. CONTRIBUTION
# ADDITIVE PURE (jamais un ecart a l'ambiante, voir en-tete) : intensite *
# force, attenue par distance -- meme forme d'attenuation que vent.gd/
# temperature.gd, jamais leur formule de delta. `temperature_couleur`
# n'est PAS verifiee ici : cette fonction ne rend que la contribution
# d'INTENSITE (le poids), locale() lit temperature_couleur separement
# UNIQUEMENT si cette contribution est non nulle (source a portee) --
# une source sans temperature_couleur declaree module donc l'intensite
# normalement mais pese sur la couleur avec un defaut 0.0, jamais une
# alarme redondante.
static func _contribution_intensite(position: Vector3, source: Dictionary, config: Dictionary, index: int) -> float:
	if not (source.has("position") and source.has("rayon") and source.has("intensite") and source.has("force")):
		push_error("lumiere.gd : source locale #%d incomplete (position/rayon/intensite/force requis), ignoree" % index)
		return 0.0
	var rayon: float = source.rayon
	if rayon <= 0.0:
		return 0.0
	var distance: float = position.distance_to(source.position)
	if distance > rayon:
		return 0.0
	var exposant: float = config.get("attenuation", {}).get("exposant", 1.0)
	var ratio: float = clamp(1.0 - distance / rayon, 0.0, 1.0)
	return source.intensite * source.force * pow(ratio, exposant)
