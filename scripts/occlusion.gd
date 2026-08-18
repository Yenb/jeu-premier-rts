extends RefCounted

# Geometrie d'occlusion PARTAGEE (chantier "ombre pluviometrique -- il pleut
# moins derriere la montagne"). Classe RefCounted SANS ETAT (fonctions static
# pures, meme discipline que tout scripts/) : ne lit aucun catalogue, ne
# connait aucun canal, aucun percepteur, aucun nom de contenu -- rien que de
# la geometrie et deux noms de propriete recus en parametre.
#
# EXTRACTION, PAS INVENTION (patron portee.gd/quantite_matiere.gd : une
# extraction ETROITE qui n'unifie rien d'autre) : facteur() est la geometrie
# de perception.gd:_facteur_obstacles, deplacee ici mot pour mot (projection
# sur le segment, t strictement dans ]0,1[, distance laterale, cumul
# MULTIPLICATIF des attenuations). perception.gd:_facteur_obstacles subsiste
# et ne fait plus que deleguer ici -- une seule geometrie d'occlusion dans le
# depot, plus deux.
#
# attenuer_par_distance(), elle, N'EST PAS UNE EXTRACTION -- constat pose
# avant d'ecrire, contre l'enonce du chantier : perception.gd n'a AUCUNE
# fonction _attenuation_distance, son attenuation est ecrite en ligne dans
# _percevoir_propagation_obstacles et vaut `1.0 - distance / portee`
# (LINEAIRE, BORNEE PAR LA PORTEE, nulle au bord). La loi ecrite ici,
# `force / distance^exposant`, est une loi en PUISSANCE INVERSE, NON bornee
# par une portee, qui ne s'annule jamais completement -- c'est ce que veut un
# champ ambiant (champ_occulte.gd), pas ce que fait perception.gd.
# perception.gd garde sa formule lineaire INCHANGEE : les deux coexistent
# deliberement, aucune n'est la copie de l'autre.
#
# --- facteur(depuis, vers, obstacles, propriete_obstacle, largeur,
#     ids_exclus = []) -> float ---
# Recoit : `depuis`/`vers` (Vector3, les deux bouts du segment -- l'ordre est
# sans effet sur le resultat, la projection est symetrique) ; `obstacles`
# (Array de Dictionary { position: Vector3, proprietes: Dictionary, id
# (FACULTATIF) } -- CONSTRUIT ET POSSEDE ENTIEREMENT PAR L'APPELANT, ce
# fichier ne fabrique, ne charge, ne filtre jamais aucune liste lui-meme,
# meme patron que vent.gd:sources_locales/lumiere.gd:sources) ;
# `propriete_obstacle` (String, nom de la propriete qui attenue --
# "absorption_sonore", "densite", "relief_bloquant" : JAMAIS en dur ici) ;
# `largeur` (float, tolerance laterale au segment, meme unite que les
# positions) ; `ids_exclus` (Array, FACULTATIF, defaut [] -- ids a ne jamais
# compter comme obstacles, typiquement la source elle-meme quand elle figure
# dans la meme liste que les obstacles, cas de perception.gd).
# Rend : un facteur multiplicatif dans [0.0, 1.0] -- 1.0 = aucun obstacle
# retenu (transparent), 0.0 = blocage total.
#
# REGLES (identiques a celles que perception.gd appliquait avant
# l'extraction, aucune renegociee ici) :
# - Un obstacle compte si sa projection sur le segment tombe STRICTEMENT
#   entre les deux bouts (t dans ]0,1[ -- ni un bout, ni l'autre, meme si un
#   objet occupe exactement la position d'un bout : c'est ids_exclus qui
#   exclut nommement, jamais une tolerance de distance) ET si sa distance
#   LATERALE au segment est <= largeur.
# - Chaque obstacle retenu multiplie le facteur par (1.0 - sa valeur,
#   bornee [0.0, 1.0]) : PLUSIEURS obstacles sur le meme segment se
#   CUMULENT MULTIPLICATIVEMENT (deux murs attenuent plus qu'un seul),
#   jamais une somme qui pourrait exceder 1.0 ou devenir negative.
#   CONSEQUENCE PORTANTE DE CE BORNAGE, a savoir avant de cabler : toute
#   grandeur PHYSIQUE BRUTE passee en propriete d'obstacle (une densite en
#   kg/m3, une epaisseur en metres...) clampe a 1.0 des qu'elle depasse
#   1.0, donc BLOCAGE TOTAL, sans aucune gradation. Une valeur qui doit
#   graduer se NORMALISE EN DONNEE avant d'entrer ici -- jamais en
#   assouplissant cette borne, qui est ce qui garantit un facteur dans
#   [0,1].
# - `propriete_obstacle` vide : court-circuit immediat, facteur neutre 1.0,
#   aucune boucle -- gate qui garantit qu'un appelant qui ne declare pas
#   d'occlusion se comporte exactement comme s'il n'y en avait aucune.
# - Segment de longueur quasi nulle (les deux bouts confondus) : aucune
#   ligne significative, facteur neutre 1.0.
# - Un obstacle SANS `position` est STRUCTURELLEMENT incomplet (il n'a aucun
#   sens sans elle) : push_error nommant son index, CET obstacle seul est
#   ignore, les autres continuent -- jamais un repli silencieux sur
#   Vector3.ZERO, qui l'aurait place a l'origine et aurait pu occulter a
#   tort. Un obstacle sans `proprietes`, ou sans la propriete nommee, vaut
#   0.0 (transparent) SANS alarme : c'est un point neutre legitime (dans
#   perception.gd, tout candidat de la sphere sert de candidat obstacle,
#   la plupart ne portant pas la propriete du canal).
#
# COUT : O(n) obstacles testes par appel. L'appelant qui boucle sur n sources
# paie donc O(n^2) -- limite CONNUE et NON OPTIMISEE (aucune structure
# d'acceleration spatiale ici, voir CLAUDE.md : signaler, pas contourner en
# silence). perception.gd portait deja cette note avant l'extraction ; elle
# vaut desormais pour tout appelant, champ_occulte.gd compris.
#
# --- attenuer_par_distance(force, distance, exposant) -> float ---
# Rend `force / distance^exposant`. `exposant` 0.0 rend `force` inchangee
# (aucune attenuation), 1.0 une decroissance en 1/d, 2.0 en 1/d^2. `distance`
# <= 0.0 (le point interroge est EXACTEMENT sur la source) rend `force`
# telle quelle -- jamais une division par zero, jamais INF : contrat
# EXPLICITE, a l'appelant de savoir qu'au point meme d'une source la loi en
# puissance inverse n'a pas de valeur physique.

static func facteur(depuis: Vector3, vers: Vector3, obstacles: Array, propriete_obstacle: String, largeur: float, ids_exclus: Array = []) -> float:
	if propriete_obstacle.is_empty():
		return 1.0
	var vecteur: Vector3 = vers - depuis
	var longueur_carre: float = vecteur.length_squared()
	if longueur_carre <= 0.0001:
		return 1.0
	var resultat := 1.0
	for i in obstacles.size():
		var obstacle: Dictionary = obstacles[i]
		if not obstacle.has("position"):
			push_error("occlusion.gd : obstacle #%d sans 'position', ignore" % i)
			continue
		if not ids_exclus.is_empty() and ids_exclus.has(obstacle.get("id", null)):
			continue
		var position: Vector3 = obstacle.position
		var t: float = (position - depuis).dot(vecteur) / longueur_carre
		if t <= 0.0 or t >= 1.0:
			continue
		var point_sur_segment: Vector3 = depuis + vecteur * t
		var distance_laterale: float = position.distance_to(point_sur_segment)
		if distance_laterale > largeur:
			continue
		var valeur: float = clamp(obstacle.get("proprietes", {}).get(propriete_obstacle, 0.0), 0.0, 1.0)
		resultat *= (1.0 - valeur)
	return resultat

static func attenuer_par_distance(force: float, distance: float, exposant: float) -> float:
	if distance <= 0.0:
		return force
	return force / pow(distance, exposant)
