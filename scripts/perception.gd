extends RefCounted

# Couche 1 : perception brute, multi-canal. Aveugle et exhaustive DANS LA
# GEOMETRIE de chaque canal actif -- aucun tri, aucun poids, aucune saillance :
# ca reste le travail de attaches.gd/proximite.gd/jugement.gd (couche 2).
#
# Recoit : entite ({ position: Vector3, proprietes: { canaux, canaux_config,
# orientation, ... }, ... }), monde (tout objet exposant
# choses_dans_rayon(position, rayon) -> Array de { chose, type, position } ;
# aujourd'hui monde.gd), catalogue_canaux (data/canaux.json : nom_canal ->
# { geometrie, proprietes_captees }), catalogue_vent (FACULTATIF, defaut {},
# data/vent.json), temps (FACULTATIF, defaut 0.0, secondes ecoulees -- ignore
# si catalogue_vent est vide), sources_vent (FACULTATIF, defaut [] --
# perturbations locales, voir scripts/vent.gd).
#
# Rend : Array de { chose, type, position, distance, canaux: [nom_canal, ...] }
# -- UNE entree par chose percue (jamais un doublon meme captee par plusieurs
# canaux), la liste "canaux" porte tous ceux qui l'ont captee.
#
# STRUCTUREL VS FACULTATIF
# - "canaux" (Array de String, les NOMS actifs) est STRUCTURELLE : sa cle
#   absente signifie que l'entite recue n'est pas faite pour percevoir --
#   push_error puis retour neutre ([]), jamais un defaut silencieux. Un NOM
#   absent de la liste reste legitime (une entite aveugle porte "canaux" sans
#   "vue" ; "canaux": [] decrit une entite qui ne percoit rien par aucun sens).
#   Un nom present dans la liste mais absent de catalogue_canaux alarme et CE
#   canal est ignore, les autres continuent.
# - "canaux_config" (Dictionary nom_canal -> { portee, angle, sensibilite,
#   seuil }) est FACULTATIVE dans son ensemble ET par canal : absente, le canal
#   est MUET, jamais une alarme. Le catalogue ne porte aucun defaut de repli.
#   Un canal peut donc etre LISTE sans porter de reglages : il vaut alors une
#   portee de 0.0.
# - "orientation" (Vector3 sur proprietes) est FACULTATIVE : son absence dit
#   "direction non precisee", l'entite fait face a l'axe par defaut (0,0,1).
#   Serialisee en Dictionary { x, y, z } dans les donnees JSON (CLAUDE.md,
#   Verticalite), convertie a la lecture.
#
# proprietes_captees (catalogue_canaux) est une METADONNEE DESCRIPTIVE, PAS un
# filtre de detection. ECARTE : un filtre par propriete au niveau du canal
# romprait "la perception est aveugle, la saillance ne l'est pas"
# (docs/design.md) ET ferait fuiter du vocabulaire de banc jetable dans une
# donnee partagee du coeur. Ce champ servira de modulateur de gain a la couche
# saillance, jamais ici.
#
# QUATRE GEOMETRIES, une fonction interne par type, choisie par
# catalogue_canaux[nom].geometrie :
# - cone_oriente (vue) : filtre par angle autour de l'orientation, en plus de
#   la portee. angle >= 360.0 (ou absent) degenere en sphere pure -- aucune
#   direction ne peut alors exclure quoi que ce soit.
# - propagation_obstacles (ouie) : sphere, PUIS trois filtres au-dela, dans cet
#   ordre -- distance, occlusion, seuil. L'intensite lue sur la source est
#   nommee PAR LE CANAL (propriete_emission, defaut "son_emis") ; elle est
#   attenuee LINEAIREMENT par la distance (1.0 - distance/portee), puis par les
#   obstacles, puis comparee au "seuil" de canaux_config.<nom>. Une chose sous
#   ce seuil sort de CETTE geometrie, jamais des trois autres.
# - sphere_directionnelle (odorat) : sphere DONT LA PORTEE EST MODULEE PAR LE
#   VENT quand catalogue_vent est fourni ; sans lui, sphere pure.
# - contact : sphere pure, portee typiquement tres courte (toucher, gout,
#   nociception) -- aucune distinction structurelle avec les deux precedentes,
#   un mecanisme separe pour ne pas coupler leur futur.
#
# Portee/angle/sensibilite/seuil vivent SUR L'ENTITE (canaux_config.<nom>),
# jamais dans catalogue_canaux -- une portee est individuelle (meme convention
# que portee_travail/portee_flux, voir docs/design.md). "sensibilite" (defaut
# 1.0) multiplie la portee effective. "seuil" (defaut 0.0) n'est CONSOMME que
# par propagation_obstacles ; les trois autres geometries le stockent sans
# jamais le lire.
#
# OCCLUSION : la geometrie vit dans scripts/occlusion.gd, partagee avec
# champ_occulte.gd -- _facteur_obstacles ne fait que deleguer. La propriete qui
# attenue est nommee PAR LE CANAL (propriete_obstacle, "absorption_sonore" pour
# ouie), jamais en dur. ECARTE, alors que docs/design.md la placait dans
# monde.gd:choses_dans_rayon : la propriete a lire depend du CANAL -- opacite
# pour une future vue, absorption_sonore pour ouie --, une notion que monde.gd,
# contenant spatial generique, n'a aucune raison de connaitre.
#
# DEUX LOIS D'ATTENUATION COEXISTENT, deliberement : l'attenuation par la
# DISTANCE ecrite ici est LINEAIRE et nulle au bord ;
# occlusion.gd:attenuer_par_distance est une PUISSANCE INVERSE, non bornee par
# une portee, ecrite pour champ_occulte.gd et jamais appelee par ce fichier.
#
# VENT SUR L'ODORAT SEUL (voir scripts/vent.gd). Cablage GEOMETRIQUE, jamais
# nominal : rien ici ne teste nom_canal == "odorat" -- c'est la geometrie
# sphere_directionnelle qui recoit le vent, odorat en est aujourd'hui le seul
# porteur dans data/canaux.json. catalogue_vent VIDE =>
# _percevoir_sphere_directionnelle degenere vers _sphere_brute. Non vide : elle
# boucle PAR CHOSE (meme patron que _percevoir_cone_oriente), la portee modulee
# dependant de la direction vers CHAQUE chose et jamais d'un scalaire partage.
# Le vent module la PORTEE, jamais l'intensite en aval : la `distance` rendue
# reste la vraie distance geometrique (contrat de proximite.gd), seul le seuil
# de comparaison change. POUR BRANCHER UN AUTRE CANAL : voir scripts/vent.gd,
# "REUTILISATION PAR D'AUTRES CANAUX".
#
# AUTO-EXCLUSION : une entite ne se percoit jamais elle-meme, sur aucun canal.
# Filtre UNIQUE ici, jamais dans un appelant -- le jour ou un type devient
# saillant (voir data/profils_saillance.json), il ne doit pas se voir lui-meme
# comme sa propre cible. "id" reste FACULTATIF sur l'entite percevante : son
# absence dit "ceci ne peut structurellement pas se retrouver soi-meme", jamais
# une alarme. LECON : entite.get("id", null), jamais entite.id en acces pointe
# -- un acces pointe sur un Dictionary sans cette cle plante GDScript ("Invalid
# access to property or key"). "chose.id" reste en acces pointe :
# monde.gd:ajouter/par_id le presupposent present pour tout ce qui entre dans
# un Monde. Chaque geometrie qui passe par _sphere_brute est couverte par UNE
# garde ; cone_oriente a angle < 360 et sphere_directionnelle AVEC vent ont
# chacune leur propre boucle, donc chacune leur propre garde.
#
# COUT : O(n) candidats testes par source dans une boucle deja O(n) -- O(n^2)
# par appel dans le pire cas, aucune structure d'acceleration spatiale. NON
# OPTIMISE (limite explicite, voir CLAUDE.md -- signaler, pas corriger) : si un
# appelant reel depasse ~50 candidats par requete, le signaler plutot que
# d'ajouter une structure d'acceleration en silence.

const Vent = preload("res://scripts/vent.gd")
const Occlusion = preload("res://scripts/occlusion.gd")

static func percevoir(entite: Dictionary, monde, catalogue_canaux: Dictionary, catalogue_vent: Dictionary = {}, temps: float = 0.0, sources_vent: Array = []) -> Array:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("canaux"):
		push_error("perception.gd : propriete structurelle 'canaux' absente de proprietes")
		return []
	var captures: Dictionary = {}
	for nom_canal in proprietes.canaux:
		if not catalogue_canaux.has(nom_canal):
			push_error("perception.gd : canal '%s' reference par l'entite est absent de catalogue_canaux" % nom_canal)
			continue
		var declaration: Dictionary = catalogue_canaux[nom_canal]
		var params: Dictionary = proprietes.get("canaux_config", {}).get(nom_canal, {})
		var geometrie: String = declaration.get("geometrie", "")
		var detectees: Array
		match geometrie:
			"cone_oriente":
				detectees = _percevoir_cone_oriente(entite, monde, params)
			"propagation_obstacles":
				var params_avec_obstacle: Dictionary = params.duplicate()
				params_avec_obstacle["propriete_obstacle"] = declaration.get("propriete_obstacle", "")
				params_avec_obstacle["largeur_obstacle"] = declaration.get("largeur_obstacle", 0.0)
				params_avec_obstacle["propriete_emission"] = declaration.get("propriete_emission", "son_emis")
				detectees = _percevoir_propagation_obstacles(entite, monde, params_avec_obstacle)
			"sphere_directionnelle":
				detectees = _percevoir_sphere_directionnelle(entite, monde, params, catalogue_vent, temps, sources_vent)
			"contact":
				detectees = _percevoir_contact(entite, monde, params)
			_:
				push_error("perception.gd : geometrie inconnue '%s' pour le canal '%s'" % [geometrie, nom_canal])
				detectees = []
		for entree in detectees:
			var id = entree.chose.id
			if not captures.has(id):
				captures[id] = {
					"chose": entree.chose,
					"type": entree.type,
					"position": entree.position,
					"distance": entree.distance,
					"canaux": [],
				}
			captures[id].canaux.append(nom_canal)
	return captures.values()

# Portee effective commune aux quatre geometries : portee declaree *
# sensibilite (toutes deux facultatives, defaut 0.0/1.0 -- une portee
# absente ou nulle rend le canal muet, point neutre legitime, jamais une
# alarme : un canal desactive se declare par son ABSENCE de la liste
# "canaux", pas par une portee a 0.0, mais les deux doivent produire le
# meme resultat neutre).
static func _portee_effective(params: Dictionary) -> float:
	return params.get("portee", 0.0) * params.get("sensibilite", 1.0)

# Balayage brut par sphere, partage par les trois geometries qui n'ont
# pas encore de raffinement geometrique au-dela de la portee (V1).
static func _sphere_brute(entite: Dictionary, monde, portee: float) -> Array:
	if portee <= 0.0:
		return []
	var id_percepteur = entite.get("id", null)
	var resultat: Array = []
	for entree in monde.choses_dans_rayon(entite.position, portee):
		if id_percepteur != null and entree.chose.id == id_percepteur:
			continue
		resultat.append({
			"chose": entree.chose,
			"type": entree.type,
			"position": entree.position,
			"distance": entite.position.distance_to(entree.position),
		})
	return resultat

static func _orientation(proprietes: Dictionary) -> Vector3:
	var brute = proprietes.get("orientation")
	if brute == null:
		return Vector3(0.0, 0.0, 1.0)
	if brute is Vector3:
		return brute
	return Vector3(brute.get("x", 0.0), brute.get("y", 0.0), brute.get("z", 0.0))

static func _percevoir_cone_oriente(entite: Dictionary, monde, params: Dictionary) -> Array:
	var portee: float = _portee_effective(params)
	if portee <= 0.0:
		return []
	var angle: float = params.get("angle", 360.0)
	if angle >= 360.0:
		return _sphere_brute(entite, monde, portee)
	var orientation: Vector3 = _orientation(entite.get("proprietes", {})).normalized()
	var cos_limite: float = cos(deg_to_rad(angle / 2.0))
	var id_percepteur = entite.get("id", null)
	var resultat: Array = []
	for entree in monde.choses_dans_rayon(entite.position, portee):
		if id_percepteur != null and entree.chose.id == id_percepteur:
			continue
		var vers_chose: Vector3 = entree.position - entite.position
		var d: float = vers_chose.length()
		var dans_cone: bool = true
		if d > 0.0001:
			dans_cone = orientation.dot(vers_chose / d) >= cos_limite
		if dans_cone:
			resultat.append({
				"chose": entree.chose,
				"type": entree.type,
				"position": entree.position,
				"distance": d,
			})
	return resultat


# Sphere, PUIS trois filtres au-dela, dans cet ordre : distance, occlusion,
# seuil. Voir l'en-tete du fichier pour la vue d'ensemble ; ici le detail des
# defauts et des gates.
#
# INTENSITE ET SEUIL : l'intensite lue sur la source
# (chose.proprietes.<propriete_emission>) est FACULTATIVE, defaut 0.0 -- une
# chose qui n'emet rien est un point neutre legitime, jamais une alarme. Elle
# est attenuee LINEAIREMENT par la distance (1.0 - distance/portee), MEME
# forme que _portee_effective/_sphere_brute, jamais une seconde formule, puis
# comparee a "seuil" (params, facultatif, defaut 0.0). A seuil 0.0 le filtre
# est inerte : toute intensite attenuee non negative reste >= 0.0.
#
# TROIS CLES FUSIONNEES PAR L'APPELANT UNIQUE, percevoir(), depuis
# catalogue_canaux[nom] -- canaux_config.<nom> ne les porte jamais lui-meme :
# "propriete_emission" (String, defaut "son_emis"), "propriete_obstacle"
# (String, nom de la propriete materiau qui attenue -- "absorption_sonore"
# pour ouie) et "largeur_obstacle" (float, tolerance laterale au segment). Un
# canal qui n'en declare aucune garde le comportement d'une sphere pure :
# propriete_obstacle vide court-circuite _facteur_obstacles a 1.0.
#
# AUCUNE DEUXIEME REQUETE SPATIALE, et c'est une propriete geometrique, pas
# une optimisation : tout obstacle ENTRE l'entite et une source deja captee
# par la sphere de rayon "portee" est necessairement dans cette meme sphere
# (le segment entite->source, de longueur <= portee, ne peut en sortir).
# "brut" sert donc a la fois de source de candidats PERCUS et de candidats
# OBSTACLES, jamais deux listes separees.
static func _percevoir_propagation_obstacles(entite: Dictionary, monde, params: Dictionary) -> Array:
	var portee: float = _portee_effective(params)
	var brut: Array = _sphere_brute(entite, monde, portee)
	var seuil: float = params.get("seuil", 0.0)
	var propriete_obstacle: String = params.get("propriete_obstacle", "")
	var largeur_obstacle: float = params.get("largeur_obstacle", 0.0)
	var propriete_emission: String = params.get("propriete_emission", "son_emis")
	# Normalisation des candidats vers la forme attendue par occlusion.gd
	# ({ id, position, proprietes }), faite UNE SEULE FOIS pour tout l'appel
	# et non par source : la liste des candidats-obstacles est la MEME pour
	# les n sources (c'est "brut", voir plus haut), seule la source exclue
	# change. Court-circuitee quand le canal ne declare aucune occlusion --
	# aucun cout ajoute a un canal qui n'en veut pas.
	var obstacles: Array = [] if propriete_obstacle.is_empty() else _obstacles_depuis_candidats(brut)
	var resultat: Array = []
	for entree in brut:
		var force_emission: float = entree.chose.get("proprietes", {}).get(propriete_emission, 0.0)
		var attenuation_distance: float = 1.0 - entree.distance / portee
		var facteur_obstacles: float = _facteur_obstacles(entite.position, entree, obstacles, propriete_obstacle, largeur_obstacle)
		var attenuee: float = force_emission * attenuation_distance * facteur_obstacles
		if attenuee < seuil:
			continue
		resultat.append(entree)
	return resultat

# Facteur multiplicatif [0.0, 1.0] d'attenuation par obstacles, pour UNE
# source (entree_source, deja captee par la sphere) percue depuis
# position_percepteur -- parmi les MEMES candidats que la sphere brute
# (deja normalises par _obstacles_depuis_candidats, jamais une deuxieme
# requete spatiale, voir plus haut).
#
# NE CALCULE RIEN LUI-MEME, il delegue : toute la geometrie (projection sur le
# segment, t dans ]0,1[, distance laterale, cumul multiplicatif, gate sur
# propriete_obstacle vide, segment degenere) vit dans
# scripts/occlusion.gd:facteur, PARTAGEE avec champ_occulte.gd. La source
# elle-meme est exclue PAR SON ID, via ids_exclus -- jamais par une distance.
#
# COUT (voir occlusion.gd) : O(n) candidats testes par source, dans une boucle
# deja O(n) sur les sources -- O(n^2) par appel dans le pire cas, aucune
# structure d'acceleration spatiale. NON OPTIMISE (limite explicite, voir
# CLAUDE.md -- signaler, pas corriger) : si un appelant reel depasse ~50
# candidats par requete, le signaler a Yael plutot que d'ajouter une structure
# d'acceleration en silence.
static func _facteur_obstacles(position_percepteur: Vector3, entree_source: Dictionary, obstacles: Array, propriete_obstacle: String, largeur_obstacle: float) -> float:
	return Occlusion.facteur(position_percepteur, entree_source.position, obstacles, propriete_obstacle, largeur_obstacle, [entree_source.chose.id])

# Traduit les entrees de la sphere brute ({ chose, type, position, distance })
# vers la forme d'obstacle attendue par occlusion.gd ({ id, position,
# proprietes }) -- pure mise en forme, AUCUN filtre : tout candidat de la
# sphere reste candidat obstacle, y compris ceux qui ne portent pas la
# propriete du canal (ils valent alors 0.0, transparent, voir occlusion.gd).
static func _obstacles_depuis_candidats(candidats: Array) -> Array:
	var obstacles: Array = []
	for entree in candidats:
		obstacles.append({
			"id": entree.chose.id,
			"position": entree.position,
			"proprietes": entree.chose.get("proprietes", {}),
		})
	return obstacles

static func _percevoir_sphere_directionnelle(entite: Dictionary, monde, params: Dictionary, catalogue_vent: Dictionary, temps: float, sources_vent: Array) -> Array:
	var portee: float = _portee_effective(params)
	if portee <= 0.0:
		return []
	if catalogue_vent.is_empty():
		# Sans catalogue de vent, cette geometrie EST une sphere pure. Voir
		# l'en-tete du fichier, "VENT SUR L'ODORAT SEUL".
		return _sphere_brute(entite, monde, portee)
	var vecteur_vent: Vector3 = Vent.vecteur(entite.position, temps, catalogue_vent, sources_vent)
	if vecteur_vent.length() <= 0.0001:
		# Vent fourni mais nul a cette position/cet instant : le facteur
		# directionnel serait 1.0 pour toute chose (voir vent.gd), donc le
		# resultat serait de toute facon identique a _sphere_brute -- court-
		# circuit de clarte, pas une necessite mathematique.
		return _sphere_brute(entite, monde, portee)
	# Portee modulee : depend de la direction vers CHAQUE chose, jamais d'un
	# seul scalaire -- sort de la delegation a _sphere_brute (meme patron que
	# _percevoir_cone_oriente). La requete spatiale se fait avec la portee la
	# PLUS FAVORABLE actuellement possible (le vent aligne avec lui-meme rend
	# le facteur le plus haut atteignable a cet instant), chaque candidat est
	# ensuite filtre par SA PROPRE portee effective.
	var facteur_le_plus_favorable: float = Vent.facteur_directionnel(vecteur_vent, vecteur_vent, catalogue_vent)
	var portee_requete: float = portee * max(facteur_le_plus_favorable, 1.0)
	var id_percepteur = entite.get("id", null)
	var resultat: Array = []
	for entree in monde.choses_dans_rayon(entite.position, portee_requete):
		if id_percepteur != null and entree.chose.id == id_percepteur:
			continue
		var vers_chose: Vector3 = entree.position - entite.position
		var d: float = vers_chose.length()
		var facteur: float = Vent.facteur_directionnel(vecteur_vent, vers_chose, catalogue_vent)
		if d <= portee * facteur:
			resultat.append({
				"chose": entree.chose,
				"type": entree.type,
				"position": entree.position,
				"distance": d,
			})
	return resultat

static func _percevoir_contact(entite: Dictionary, monde, params: Dictionary) -> Array:
	return _sphere_brute(entite, monde, _portee_effective(params))
