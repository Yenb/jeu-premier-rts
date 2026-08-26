extends RefCounted

# LE COUVERT VEGETAL : plusieurs especes qui traversent leurs stades, deposent
# leurs produits, se reproduisent, se font de l'ombre et meurent, sur un terrain
# releve une seule fois.
#
# CE FICHIER N'ECRIT AUCUNE MECANIQUE (CLAUDE.md, « UN GAMEPLAY EST UNE
# COMPOSITION, JAMAIS UNE PIECE »). Il compose cinq mecanismes du coeur DEJA
# FERMES, tous INCHANGES -- scripts/senescence.gd (l'age monte), scripts/stade.gd
# (le stade suit l'age, jamais en arriere), scripts/seuil_etat.gd (la mort au
# seuil de longevite), scripts/gestation.gd (le compteur entre deux pousses,
# point d'entree asexue), scripts/monde.gd via scripts/banc_commun.gd (la requete
# de voisinage) -- plus le pont jeu/plantes/surface_terrain.gd. Aucun fichier de
# scripts/, data/ ni addons/ n'est touche.
#
# AUCUN NOM DE CONTENU N'APPARAIT ICI : ni une espece, ni un stade, ni une cle de
# ressource, ni un chemin de modele. Tous arrivent par la config et par les
# fichiers d'espece.
#
# ---- LES TROIS CONTRAINTES, ET IL FAUT LES TROIS ----
# Elles ne disent pas la meme chose, et en confondre deux ferait disparaitre une
# dynamique entiere :
#   DENSITE       (max_voisins)     -- gate la MERE : trop entouree, elle ne se
#                                      reproduit plus. Borne la population.
#   DOMINANCE     (stature, ombre)  -- gate la CROISSANCE : dominee, une plante se
#                                      fige et attend. Decide qui l'emporte.
#   ETABLISSEMENT (trouee)          -- gate le LIEU : un rejet renonce la ou c'est
#                                      deja trop dense pour SON espece.
#
# LA STATURE, PAS LE NUMERO DE STADE. Entre deux especes un numero ne veut rien
# dire : le stade 3 d'une herbe n'est pas plus grand que le stade 2 d'un arbre.
# Chaque stade declare donc une HAUTEUR, et c'est elle que l'ombre compare. Une
# herbe basse a tous ses stades n'ombrage jamais un arbre et se fige sous
# n'importe lequel -- sous la canopee rien ne pousse, dans les trouees l'herbe
# part. L'ecosysteme sort de la, sans une regle de plus.
#
# LA TROUEE VIENT DE L'ECOLOGIE REELLE : en savane, l'herbe ne tue pas les
# arbres, elle tue leurs SEMIS -- elle n'affecte pas leur vitesse de croissance,
# elle empeche leur installation faute de trouee dans le tapis racinaire. D'ou
# deux gates opposes a deux moments de la vie, et deux gestes opposes pour le
# joueur : arracher l'herbe pour laisser monter les arbres, abattre les arbres
# pour laisser revenir l'herbe.
#
# CE FICHIER NE CONNAIT AUCUN MODELE 3D. Il ecrit un numero de stade et une
# stature ; c'est jeu/plantes/couvert.gd qui traduit en scene affichee. La
# simulation tourne donc entiere sans un seul .glb, ce que le test prouve en
# headless (CLAUDE.md, « La simulation ne depend JAMAIS de l'affichage »).
#
# Entree : un releve de surface, la config partagee, la table des especes
# preparees, une liste de semis ({ id, colonne, type }).
# Sortie : un etat mute en place par avancer(), et un rapport par tick que le
# rendu et les tests relisent sans jamais rien recalculer.
#
# ---- L'ORDRE DU TICK, FIXE ET ASSUME ----
#  1. l'ombre est LUE SUR CHAQUE PLANTE (elle y est stockee), puis senescence.gd
#     et stade.gd -- l'age monte et le stade suit, sauf pour les dominees qui se
#     figent ; la stature est reecrite derriere
#  2. seuil_etat.gd -- l'age depasse la longevite, l'etat de mort tombe
# 2b. la liste des vivantes est REFAITE
#  3. les produits vieillissent, ceux qui ont fait leur temps disparaissent
#  4. la production
#  5. la gestation se pose, sous gate de densite ET de stade
#  6. gestation.gd -- le compteur avance
#  7. les rejets naissent, sous gate de plafond de couche ET de trouee
#  8. le Monde est reconstruit si la composition a change
#  9. l'ombre est relue AUTOUR DES SEULS ENDROITS ou quelque chose a change
#
# 2b N'EST PAS FACULTATIF : la liste est figee en tete de tick, et les mortes que
# le pas 2 vient de declarer y figurent encore. Sans ce rafraichissement une
# plante morte produit au pas 4 et pousse au pas 7 du meme tick, et pire, elle ne
# compte deja plus dans le voisinage du pas 5 -- le gate de densite s'ouvrirait au
# moment precis ou la population s'effondre. Defaut deja recense dans
# scripts/banc_parasites_reproduction.gd, trouve en lancant.
#
# 3 AVANT 4 : un produit qui expire ce tick libere sa place dans le plafond, et la
# plante doit pouvoir en reposer un aussitot.
#
# 5 AVANT 6 : poser apres avoir avance ferait perdre un tick a chaque cycle.
#
# LES PRODUITS SURVIVENT A LEUR PLANTE : deposes au sol, ils finissent leur temps
# meme si la mere meurt -- les retirer avec elle ferait disparaitre sous les yeux
# du joueur ce qu'il allait ramasser. Ils N'ENTRENT PAS DANS LE MONDE (decision de
# cout : rien n'interroge le voisinage d'un produit, et les y verser ferait payer
# leur presence a toute requete dont le rayon les touche -- precedent
# scripts/banc_predation.gd, decision (d)).
#
# Regles tenues : positions en Vector3, jamais Vector2 -- une COLONNE est un
# Vector2i, index de grille et non position. Tout tirage passe par un RNG seede
# porte par l'etat. La simulation ne lit ni noeud ni GridMap. Rien de scripts/,
# data/ ni addons/ n'est ecrit.

const Senescence = preload("res://scripts/senescence.gd")
const Stade = preload("res://scripts/stade.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Gestation = preload("res://scripts/gestation.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")
const Surface = preload("res://jeu/plantes/surface_terrain.gd")

const CHEMIN_CONFIG := "res://jeu/plantes/vegetation.json"

# ---- Chargement ----

static func _lire_json(chemin: String) -> Dictionary:
	var brut := FileAccess.get_file_as_string(chemin)
	if brut == "":
		push_error("vegetation.gd : %s introuvable ou vide" % chemin)
		return {}
	var lu: Variant = JSON.parse_string(brut)
	if not (lu is Dictionary):
		push_error("vegetation.gd : %s n'est pas un objet JSON" % chemin)
		return {}
	return lu

static func charger_config(chemin: String = CHEMIN_CONFIG) -> Dictionary:
	return _lire_json(chemin)

# UNE ESPECE, PREPAREE UNE FOIS POUR TOUTES. Elle arrive en champs plats -- ce que
# le game designer regle sur un noeud jeu/plantes/espece.gd -- et repart en
# Dictionary, la forme que le tick manipule. Trois calculs, parce que les
# mecanismes du coeur veulent une autre forme que le game designer :
#
# (1) stade.gd attend des SEUILS ABSOLUS d'age, l'espece declare des DUREES. Le
#     cumul se fait ici, jamais a chaque tick.
# (2) LA LONGEVITE EST LA SOMME DES DUREES, jamais un champ separe -- un champ
#     pourrait contredire la table et tuer la plante avant son dernier stade.
# (3) CHAQUE ESPECE RECOIT SON PROPRE CATALOGUE DE REPRODUCTION. gestation.gd
#     resout son entree par proprietes.reproduction_ref, identique pour tout le
#     monde : deux especes de rythmes differents ne peuvent donc PAS partager un
#     catalogue. Chacune emporte le sien, une copie ou seule duree_gestation
#     change.
#
# Rend {} pour une espece sans stade : l'appelant decide quoi faire d'une espece
# qui ne peut pas vivre, ce fichier n'en fabrique jamais une a moitie.
static func preparer_depuis_champs(nom: String, champs: Dictionary, config: Dictionary) -> Dictionary:
	var stades: Array = []
	var modeles: Array = []
	var stades_config: Array = []
	var cumul := 0.0
	var noms: Array = champs.noms_stades
	var durees: Array = champs.durees_stades
	var statures: Array = champs.statures_stades
	var chemins: Array = champs.modeles_stades
	for i in range(noms.size()):
		var duree: float = float(durees[i]) if i < durees.size() else 0.0
		stades.append({
			"nom": String(noms[i]),
			"duree": duree,
			"stature": float(statures[i]) if i < statures.size() else 1.0,
		})
		modeles.append(String(chemins[i]) if i < chemins.size() else "")
		stades_config.append({"nom": String(noms[i]), "age_seuil": cumul})
		cumul += duree
	if stades.is_empty():
		return {}

	var reproduction: Dictionary = (config.reproduction_locale as Dictionary).duplicate(true)
	var ref := String(config.reproduction_ref)
	if reproduction.has(ref):
		reproduction[ref]["duree_gestation"] = float(champs.intervalle_reproduction)
	else:
		push_error("vegetation.gd : reproduction_ref '%s' absente du catalogue partage" % ref)

	var teinte: Color = champs.couleur
	return {
		"nom": nom,
		"stades": stades,
		"stades_config": stades_config,
		"longevite": cumul,
		"dispersion_duree": maxf(0.0, float(champs.get("dispersion_duree", 0.0))),
		"utilise_ombre": bool(champs.get("utilise_ombre", false)),
		"reproduction_locale": reproduction,
		"marge_couches": int(champs.marge_couches),
		"trouee_max_voisins": int(champs.trouee_max_voisins),
		"rayon_dispersion_min": int(champs.rayon_dispersion_min),
		"rayon_dispersion_max": int(champs.rayon_dispersion_max),
		"max_voisins": int(champs.max_voisins),
		"stade_reproduction_min": int(champs.stade_reproduction_min),
		"stade_reproduction_max": int(champs.stade_reproduction_max),
		"stade_production_min": int(champs.stade_production_min),
		"intervalle_production": float(champs.intervalle_production),
		"max_produits_par_plante": int(champs.max_produits_par_plante),
		"ralentissement_dernier_stade": float(champs.ralentissement_dernier_stade),
		"duree_vie_produit": float(champs.duree_vie_produit),
		"ressource": String(champs.ressource),
		"rayon_collision": float(champs.rayon_collision),
		"distance_rendu": float(champs.get("distance_rendu", 0.0)),
		"couleur": [teinte.r, teinte.g, teinte.b],
		"modeles_stades": modeles,
		"modele_produit": String(champs.modele_produit),
	}

# ---- Construction ----

# Une plante, CONSTRUITE A LA MAIN -- jamais Objet.fabriquer, qui exigerait une
# entree dans data/types.json (lecture seule pour le jeu).
# Patron : scripts/banc_parasites_reproduction.gd:fabriquer_individu.
#
# CHAQUE CLE EST STRUCTURELLE POUR UN MECANISME PRECIS : 'age' pour
# senescence.gd, 'stades_config' pour stade.gd, 'seuil_longevite' pour l'entree
# de seuil, 'reproduction_ref' pour gestation.gd, 'etats_actifs' pour
# seuil_etat.gd. S'y ajoutent 'type_plante', 'compteur_production' et 'stature'.
#
# LA STATURE EST POSEE SUR LA PLANTE, pas relue depuis son espece a chaque
# comparaison. L'ombre est une boucle en n carre : y refaire deux recherches de
# table par voisine couterait tout le tick. Elle est REECRITE a chaque tick,
# jamais perimee.
# LE FACTEUR DE VIE D'UN INDIVIDU. Tire UNE FOIS a la naissance, applique a tous
# ses seuils : la plante vit plus vite ou plus lentement que son espece, jamais
# par a-coups. Rend exactement 1.0 quand l'espece ne declare aucune dispersion,
# ET NE TIRE ALORS RIEN -- une scene qui ne s'en sert pas garde la meme suite de
# tirages, donc exactement la meme partie qu'avant.
static func facteur_de_vie(type: Dictionary, rng) -> float:
	var dispersion := float(type.get("dispersion_duree", 0.0))
	if dispersion <= 0.0 or rng == null:
		return 1.0
	# Borne a 0.05 : un facteur nul ou negatif ferait franchir tous les seuils au
	# premier tick, ce que stade.gd traduirait par une plante nee epuisee.
	return maxf(0.05, 1.0 + rng.randf_range(-dispersion, dispersion))

static func fabriquer_plante(id: String, colonne: Vector2i, releve: Dictionary, config: Dictionary, type: Dictionary, rng = null, age_initial: float = 0.0) -> Dictionary:
	var position: Variant = Surface.position_posee(colonne, releve)
	if position == null:
		return {}
	# LES SEUILS SONT COPIES PAR PLANTE DEPUIS TOUJOURS (duplicate) : il ne
	# manquait qu'une raison de les rendre differents. La voici.
	var facteur := facteur_de_vie(type, rng)
	var seuils_etales: Array = (type.stades_config as Array).duplicate(true)
	# TOUTE L'HORLOGE DE L'INDIVIDU, JAMAIS LA MOITIE. Mettre les seuils de stade
	# a l'echelle sans toucher a la reproduction raccourcit la FENETRE FERTILE
	# sans raccourcir l'intervalle entre deux pousses : la plante rapide seme
	# moins, parfois plus du tout, et la population s'effondre. Mesure : 1603
	# vivantes a dispersion nulle, 441 avec la seule mise a l'echelle des stades.
	# Piege deja recense -- SUIVI.md, « FENETRE FERTILE PLUS COURTE QUE
	# L'INTERVALLE ». Ce qui change ici est la PHASE d'un individu, jamais sa
	# fecondite.
	var reproduction: Dictionary = (type.reproduction_locale as Dictionary)
	if not is_equal_approx(facteur, 1.0):
		for entree in seuils_etales:
			entree["age_seuil"] = float(entree.age_seuil) * facteur
		reproduction = reproduction.duplicate(true)
		# UN CATALOGUE PORTE AUSSI DES NOTES : toute entree qui n'est pas un
		# Dictionary est sautee, jamais supposee etre une regle.
		for ref in reproduction:
			if not (reproduction[ref] is Dictionary):
				continue
			var regle: Dictionary = reproduction[ref]
			if regle.has("duree_gestation"):
				regle["duree_gestation"] = float(regle.duree_gestation) * facteur

	var plante := {
		"id": id,
		"position": position,
		"colonne": colonne,
		"proprietes": {
			"type_plante": String(type.nom),
			# DEUX HORLOGES, ET C'EST TOUT LE SUJET DE LA SUCCESSION.
			# 'age' n'avance qu'a la lumiere : c'est lui que stade.gd lit, donc
			# c'est lui qui commande la CROISSANCE. Une plante dominee cesse de
			# grandir.
			# 'age_reel' avance TOUJOURS : c'est lui que l'entree de seuil lit,
			# donc c'est lui qui commande la MORT. Une plante dominee meurt quand
			# meme, a l'heure.
			# LES CONFONDRE REND LES DOMINEES IMMORTELLES -- mesure faite, une
			# herbe sous un arbre etait encore vivante dix vies plus tard, age
			# zero. Elle occupait sa colonne pour toujours, comptait pour toujours
			# dans le plafond de densite, et ne liberait jamais rien : la foret ne
			# pouvait plus reprendre le terrain. La mort ne doit pas connaitre
			# l'ombre.
			# AGE INITIAL : par defaut 0 (plante fraiche). Un peuplement pose
			# ses individus DEJA VIEUX de X secondes : Stade.avancer les met
			# au bon stade juste apres. `age` et `age_reel` sont alignes --
			# une plante nee vieille n'est pas plus dominee qu'une autre.
			"age": age_initial,
			"age_reel": age_initial,
			"seuil_longevite": float(type.longevite) * facteur,
			"reproduction_ref": String(config.reproduction_ref),
			"etats_actifs": [],
			"stade": "",
			"stades_config": seuils_etales,
			# Le catalogue de gestation de CETTE plante. Identique a celui de son
			# espece quand elle ne porte aucune dispersion -- meme objet, aucune
			# copie inutile.
			"reproduction_locale": reproduction,
			"facteur_vie": facteur,
			"compteur_production": 0.0,
			"stature": 0.0,
			"ombragee": false,
			# Court-circuit d'ombre : porte par la plante pour que
			# rafraichir_plante n'ait pas a rouvrir la table types.
			"utilise_ombre": bool(type.get("utilise_ombre", false)),
		},
	}
	# LE STADE EST RESOLU TOUT DE SUITE, jamais laisse vide jusqu'au tick suivant :
	# une chaine vide ne correspond a aucun stade, si bien qu'une plante neuve
	# n'aurait ni modele ni stature pendant un tick entier. Defaut deja recense
	# dans scripts/banc_predation.gd:fabriquer_enfant.
	Stade.avancer(plante)
	plante.proprietes["stature"] = stature_de(plante, type)
	return plante

# `semis` : Array de { id, colonne, type }. Un semis dont la colonne n'est pas
# plantable POUR SON ESPECE est pose quand meme et son refus rendu dans `refus`
# -- le game designer decide, le mecanisme ne supprime jamais ce qu'il a place.
# Un type inconnu, lui, ne PEUT pas etre pose : il n'y a aucune table de stades a
# lui donner.
static func etat_initial(semis: Array, releve: Dictionary, config: Dictionary, types: Dictionary) -> Dictionary:
	var plantes: Array = []
	var refus: Array = []
	# CREE AVANT LA BOUCLE, et non plus apres : les semis tirent desormais leur
	# facteur de vie, et ils doivent le tirer sur LE meme RNG seede que la suite
	# de la partie -- sinon la reproductibilite s'arrete au premier semis.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config.get("seed", 0))
	for graine in semis:
		var colonne: Vector2i = graine.colonne
		var nom_type := String(graine.get("type", ""))
		if nom_type == "":
			nom_type = String(config.type_par_defaut)
		if not types.has(nom_type):
			refus.append({"id": String(graine.id), "colonne": colonne, "raison": "type_inconnu"})
			continue
		var type: Dictionary = types[nom_type]
		var raison := Surface.raison_de_refus(colonne, releve, plafond_de(type, releve))
		if raison != "":
			refus.append({"id": String(graine.id), "colonne": colonne, "raison": raison})
		var age_initial := float(graine.get("age_initial", 0.0))
		var plante := fabriquer_plante(String(graine.id), colonne, releve, config, type, rng, age_initial)
		if plante.is_empty():
			continue
		plantes.append(plante)

	var etat := {
		"plantes": plantes,
		"graines": [],
		"monde": null,
		"rng": rng,
		"temps": 0.0,
		"tick": 0,
		"rejets": 0,
		"produits": 0,
		"naissances": 0,
		"morts": 0,
		"refus": refus,
	}
	etat["monde"] = monde_des_vivantes(plantes, config)
	rafraichir_toutes(plantes, etat.monde, config, releve)
	return etat

# ---- Lectures pures ----

static func est_disparue(plante: Dictionary, config: Dictionary) -> bool:
	return plante.proprietes.get("etats_actifs", []).has(String(config.etat_morte))

static func vivantes(plantes: Array, config: Dictionary) -> Array:
	var resultat: Array = []
	for plante in plantes:
		if not est_disparue(plante, config):
			resultat.append(plante)
	return resultat

static func type_de(plante: Dictionary, types: Dictionary) -> Dictionary:
	return types.get(String(plante.proprietes.get("type_plante", "")), {})

static func plafond_de(type: Dictionary, releve: Dictionary) -> int:
	return Surface.plafond_pour(releve, int(type.marge_couches))

# LE NUMERO DU STADE, COMPTE A PARTIR DE 1 comme le game designer le nomme --
# zero quand la plante n'a pas encore de stade.
static func numero_de_stade(plante: Dictionary, type: Dictionary) -> int:
	var courant := String(plante.proprietes.get("stade", ""))
	if courant == "":
		return 0
	var stades: Array = type.get("stades", [])
	for i in range(stades.size()):
		if String(stades[i].nom) == courant:
			return i + 1
	return 0

static func dernier_stade(type: Dictionary) -> int:
	return (type.get("stades", []) as Array).size()

static func stature_de(plante: Dictionary, type: Dictionary) -> float:
	var i := numero_de_stade(plante, type)
	if i <= 0:
		return 0.0
	return float((type.stades as Array)[i - 1].get("stature", 0.0))

# DEUX BORNES, PAS UNE : un minimum seul laisserait une plante epuisee semer
# encore, son numero etant au-dessus du minimum. La borne haute est ce qui rend
# « uniquement au stade mature » exprimable -- et l'herbe, elle, sement jusqu'a
# son dernier stade, ce qui la rend envahissante.
static func stade_fertile(plante: Dictionary, type: Dictionary) -> bool:
	var numero := numero_de_stade(plante, type)
	if numero <= 0:
		return false
	return numero >= int(type.stade_reproduction_min) and numero <= int(type.stade_reproduction_max)

# Rend INF sous le stade de production -- gate desactive par la SEULE
# ARITHMETIQUE, jamais par une branche : meme idiome qu'« un objet sans
# point_fusion ne fond jamais » (scripts/seuil_etat.gd). Une espece qui declare un
# stade de production au-dela de son dernier ne produit donc JAMAIS, sans qu'une
# ligne de code ne le sache.
# LA MEME HORLOGE QUE LE RESTE DE LA PLANTE : un individu qui vit vite produit
# vite. Sans ce facteur, il traverserait ses stades plus tot tout en gardant la
# cadence de son espece -- une incoherence qui se verrait sur le sol.
static func intervalle_de_production(plante: Dictionary, type: Dictionary) -> float:
	var numero := numero_de_stade(plante, type)
	if numero <= 0 or numero < int(type.stade_production_min):
		return INF
	var intervalle := float(type.intervalle_production)
	if numero == dernier_stade(type):
		intervalle *= float(type.ralentissement_dernier_stade)
	return intervalle * float(plante.proprietes.get("facteur_vie", 1.0))

static func produits_au_sol(etat: Dictionary, id: String) -> int:
	var combien := 0
	for graine in etat.graines:
		if String(graine.plante_id) == id:
			combien += 1
	return combien

static func colonnes_prises(etat: Dictionary, config: Dictionary) -> Dictionary:
	var prises: Dictionary = {}
	for plante in vivantes(etat.plantes, config):
		prises[plante.colonne] = String(plante.id)
	for graine in etat.graines:
		prises[graine.colonne] = String(graine.id)
	return prises

# Combien de plantes vivantes autour d'un point, TOUTES ESPECES CONFONDUES.
static func voisinage(position: Vector3, monde, rayon: float) -> int:
	return monde.choses_dans_rayon(position, rayon).size()

# LA DENSITE, PAR ESPECE. Le gate est un refus d'appeler gestation.gd, qui ne lit
# aucun voisinage et n'en lira jamais. La plante se compte elle-meme (distance
# zero de son propre rayon) : le plafond de l'espece en tient compte.
#
# LE SEUIL EST A L'ESPECE, LE RAYON RESTE COMMUN : une herbe qui fait tapis
# supporte des dizaines de voisines la ou un arbre en refuse six, mais les deux se
# comptent a la meme echelle. Melanger les deux ferait varier le rayon de
# rafraichissement d'une plante a l'autre, alors qu'il est choisi une fois pour
# tout le couvert (voir rafraichir_autour).
#
# LE COMPTE EST CALCULE A LA DEMANDE, JAMAIS TENU. peut_pousser est le SEUL
# lecteur du nombre de voisins, et le tick ne l'appelle que pour une plante
# FERTILE (gate stade_fertile en amont). Il compte donc lui-meme, ici, a
# l'instant ou il en a besoin : un scan par plante fertile qui tente de
# pousser, jamais un compte maintenu pour toute la population. Poser une plante
# ne compte plus rien -- ni un vieux qui ne poussera jamais, ni un jeune tant
# qu'il n'est pas fertile. Le compte n'existe qu'a l'instant de la reproduction.
static func peut_pousser(plante: Dictionary, type: Dictionary, monde, config: Dictionary, releve: Dictionary) -> bool:
	var rayon := Surface.metres_par_cellules(float(config.rayon_voisinage_cellules), releve)
	return voisinage(plante.position, monde, rayon) <= int(type.max_voisins)

# L'ETABLISSEMENT : un rejet renonce la ou c'est deja trop dense POUR SON ESPECE.
# Compte AU POINT D'ARRIVEE, jamais autour de la mere -- c'est l'endroit ou l'on
# s'installe qui decide, pas celui d'ou l'on vient. Les morts sont ecartes ici
# aussi, pour la meme raison qu'ailleurs : le Monde en garde un tick.
# LES REJETS D'UN MEME TICK DOIVENT SE VOIR LES UNS LES AUTRES. `monde` n'est
# reconstruit qu'au pas 8 : sans `nouvelles`, une cohorte entiere teste la MEME
# trouee et s'y engouffre en bloc, chacune aveugle aux autres. Le gate ne mord
# alors jamais pendant une rafale -- exactement quand il devrait mordre.
#
# MESURE QUI L'A ETABLI : a especes et graine identiques, une population
# synchronisee atteignait 1603 vivantes la ou la meme population etalee dans le
# temps se stabilisait vers 500. L'ecart n'etait pas une ecologie differente,
# c'etait le gate contourne par la synchronisation.
#
# `nouvelles` est indexe par COLONNE, jamais par position : les rejets de ce tick
# sont deja ranges ainsi par le pas 7, et compter des cles coute moins qu'une
# seconde requete spatiale.
static func trouee_suffisante(position: Vector3, monde, config: Dictionary, type: Dictionary, releve: Dictionary, nouvelles: Dictionary = {}) -> bool:
	var rayon_cellules := float(config.rayon_trouee_cellules)
	var rayon := Surface.metres_par_cellules(rayon_cellules, releve)
	var combien := 0
	for entree in monde.choses_dans_rayon(position, rayon):
		if est_disparue(entree.chose, config):
			continue
		combien += 1
	if not nouvelles.is_empty():
		combien += voisines_nees_ce_tick(
			Surface.colonne_de(position, releve), nouvelles, rayon_cellules)
	return combien <= int(type.trouee_max_voisins)

# Combien de rejets DE CE TICK sont deja tombes dans le rayon d'une colonne. Le
# balayage est borne par le rayon de trouee, qui vaut quelques cellules -- il ne
# depend jamais de la population.
static func voisines_nees_ce_tick(colonne: Vector2i, nouvelles: Dictionary, rayon_cellules: float) -> int:
	var portee := int(ceil(rayon_cellules))
	var combien := 0
	for dx in range(-portee, portee + 1):
		for dz in range(-portee, portee + 1):
			if sqrt(float(dx * dx + dz * dz)) > rayon_cellules:
				continue
			if nouvelles.has(Vector2i(colonne.x + dx, colonne.y + dz)):
				combien += 1
	return combien

# LA DOMINANCE : une voisine de STATURE strictement superieure fige la plante.
# Strictement, jamais « au moins egale » : deux grands cohabitent, seuls les
# petits attendent -- sans quoi une foret adulte se bloquerait elle-meme.
#
# LES MORTES SONT FILTREES DEUX FOIS : elles quittent le Monde a la
# reconstruction, et ce test les ecarte quand meme. Le Monde n'est refait qu'aux
# ticks ou la composition change ; un cadavre qui ombrage empecherait la strate de
# repartir apres une coupe, exactement le contraire du but. Meme garde que
# scripts/banc_parasites_reproduction.gd:perceptions_a_portee.
static func ombragee(plante: Dictionary, monde, config: Dictionary, releve: Dictionary) -> bool:
	var mienne := float(plante.proprietes.get("stature", 0.0))
	var rayon := Surface.metres_par_cellules(float(config.rayon_ombre_cellules), releve)
	for entree in monde.choses_dans_rayon(plante.position, rayon):
		if String(entree.chose.id) == String(plante.id):
			continue
		if est_disparue(entree.chose, config):
			continue
		if float(entree.chose.proprietes.get("stature", 0.0)) > mienne:
			return true
	return false

# QUI EST A L'OMBRE, POUR TOUT LE MONDE EN MEME TEMPS : la carte est lue AVANT
# que le moindre age ne bouge. Calculer l'ombre plante par plante en vieillissant
# au fil de la boucle rendrait le resultat dependant de l'ORDRE de la liste -- une
# plante traitee tot pourrait grandir et ombrager une voisine dans le meme tick,
# quand une plante traitee tard ne le ferait qu'au suivant. Aucun test ne
# rattraperait ca : les deux ordres rendent des forets egalement plausibles.
static func ombres(plantes: Array, monde, config: Dictionary, releve: Dictionary) -> Dictionary:
	var table: Dictionary = {}
	for plante in plantes:
		table[String(plante.id)] = ombragee(plante, monde, config, releve)
	return table

# ---- L'OMBRE EST UN SIGNAL, PAS UNE QUESTION ----
#
# Chaque plante PORTE son etat d'ombre au lieu de le redemander a chaque tick.
# C'est le renversement qui rend ce couvert tenable : mesure faite, 99,6 % des
# balayages de voisinage decouvraient qu'il ne s'etait rien passe.
#
# L'OMBRE D'UNE PLANTE NE PEUT CHANGER QUE SI UNE VOISINE CHANGE, et une voisine
# ne change qu'a TROIS instants : elle meurt, elle change de stade (donc de
# stature), elle nait. Ces trois-la sont deja connus du tick. Entre eux, l'etat
# d'ombre est rigoureusement le meme -- le recalculer serait le retrouver.
#
# CE QUI REND LE STOCKAGE SUR ICI ET NULLE PART AILLEURS : une plante ne bouge
# JAMAIS. Toute la difficulte d'un etat spatial garde en memoire vient du
# mouvement, et il n'y en a aucun. Le jour ou une chose mobile entre dans ce
# monde, ce raisonnement tombe.
#
# LE RISQUE, DIT PLUTOT QUE MASQUE : un evenement oublie laisse une plante gelee a
# tort, ou poussant a tort, ET RIEN NE LE SIGNALE. C'est un defaut qui dort. La
# parade n'est pas ce raisonnement mais le test : test_plante.gd compare, tick
# apres tick, l'ombre tenue par signaux a l'ombre recalculee entierement, et
# rougit sur une seule plante qui diverge.

# Relit L'OMBRE d'UNE plante, et la lui pose. NE TOUCHE PLUS AU COMPTE DE
# VOISINS : celui-ci est maintenu INCREMENTALEMENT (+1 a la naissance, -1 a
# la mort, voir _maj_voisins_incremental et retirer), jamais rescanne ici.
# L'ombre, elle, DOIT rester un scan sur changement de stade -- une voisine
# qui grandit peut t'ombrager -- donc ce rafraichissement tourne toujours
# autour des foyers (dont les changements de stade), mais pour l'ombre seule.
static func rafraichir_plante(plante: Dictionary, monde, config: Dictionary, releve: Dictionary) -> void:
	# COURT-CIRCUIT D'OMBRE : une espece qui ne declare pas utilise_ombre
	# reste toujours non-ombragee, sans aucune requete.
	if bool(plante.proprietes.get("utilise_ombre", false)):
		plante.proprietes["ombragee"] = ombragee(plante, monde, config, releve)
	else:
		plante.proprietes["ombragee"] = false


# Le calcul COMPLET, pour une seule chose : la pose initiale. Apres quoi plus
# personne ne balaie tout le monde -- sauf le test, pour verifier.
static func rafraichir_toutes(plantes: Array, monde, config: Dictionary, releve: Dictionary) -> void:
	for plante in plantes:
		rafraichir_plante(plante, monde, config, releve)

# LE SIGNAL. Autour de chaque endroit ou quelque chose a change, on relit l'ombre
# ET le compte de voisins de ce qui s'y trouve -- et de rien d'autre.
#
# LE RAYON EST CELUI DE L'OMBRE, ET C'EST EXACT, pas une marge de securite : une
# plante est affectee par un changement si et seulement si ce changement tombe
# dans SON rayon d'ombre. Chercher a la meme distance depuis le point du
# changement trouve donc exactement les plantes concernees, ni plus ni moins.
static func rafraichir_autour(etat: Dictionary, config: Dictionary, releve: Dictionary, foyers: Array) -> int:
	if foyers.is_empty():
		return 0
	# LE PLUS GRAND DES DEUX RAYONS : l'ombre porte a trois cellules, la densite a
	# cinq. Chercher au plus grand couvre les deux d'un seul balayage -- relire
	# l'ombre de quelques plantes qui n'en avaient pas besoin ne coute rien et ne
	# peut pas se tromper, alors que deux balayages de rayons differents
	# doubleraient le travail pour rien.
	var rayon: float = maxf(
		Surface.metres_par_cellules(float(config.rayon_ombre_cellules), releve),
		Surface.metres_par_cellules(float(config.rayon_voisinage_cellules), releve))
	var relues: Dictionary = {}
	for foyer in foyers:
		for entree in etat.monde.choses_dans_rayon(foyer, rayon):
			var chose: Dictionary = entree.chose
			if relues.has(chose.id) or est_disparue(chose, config):
				continue
			relues[chose.id] = true
			rafraichir_plante(chose, etat.monde, config, releve)
	return relues.size()

# L'ANNEAU DISCRET des decalages de colonne, CONSTRUIT plutot que tire puis
# corrige : tirer un angle et une distance puis arrondir produit des decalages
# hors bornes, qu'il faudrait rejeter en boucle -- et une boucle de rejet consomme
# un nombre variable de tirages, ce qui rend la suite du RNG dependante du terrain
# et casse la reproductibilite qui est la raison meme de le seeder.
static func anneau(rayon_min: int, rayon_max: int) -> Array:
	var decalages: Array = []
	for dx in range(-rayon_max, rayon_max + 1):
		for dz in range(-rayon_max, rayon_max + 1):
			var distance := sqrt(float(dx * dx + dz * dz))
			if distance >= float(rayon_min) and distance <= float(rayon_max):
				decalages.append(Vector2i(dx, dz))
	return decalages

static func colonne_de_rejet(plante: Dictionary, decalages: Array, rng: RandomNumberGenerator) -> Vector2i:
	if decalages.is_empty():
		return plante.colonne
	return (plante.colonne as Vector2i) + (decalages[rng.randi_range(0, decalages.size() - 1)] as Vector2i)

# UN SEUL TIRAGE, PUIS UN BALAYAGE : tirer jusqu'a tomber sur une place libre
# consommerait un nombre variable de tirages selon l'encombrement, et deux parties
# de meme graine divergeraient des la premiere colonie serree.
static func colonne_libre_autour(plante: Dictionary, decalages: Array, prises: Dictionary, releve: Dictionary, plafond: int, rng: RandomNumberGenerator) -> Variant:
	if decalages.is_empty():
		return null
	var depart := rng.randi_range(0, decalages.size() - 1)
	for k in range(decalages.size()):
		var colonne: Vector2i = (plante.colonne as Vector2i) + (decalages[(depart + k) % decalages.size()] as Vector2i)
		if prises.has(colonne):
			continue
		if not Surface.est_plantable(colonne, releve, plafond):
			continue
		return colonne
	return null

# Le Monde RECONSTRUIT DU NEANT, les vivantes ré-ajoutées PAR REFERENCE : leurs
# positions, stades et statures traversent la reconstruction intacts. monde.gd
# n'a aucune fonction de retrait et n'en a pas besoin -- ce qui doit disparaitre
# n'est simplement plus dans la liste au moment ou le Monde est construit.
static func monde_des_vivantes(plantes: Array, config: Dictionary, deja_propre: bool = false) -> Variant:
	# `deja_propre` : l'appelant garantit que `plantes` ne contient aucune
	# morte (ex : il vient d'appeler vivantes() dessus). On evite alors un
	# second scan O(N) inutile -- voir §8 du tick, ou survivantes est deja
	# filtre juste avant.
	return BancCommun.monde_depuis([{
		"choses": plantes if deja_propre else vivantes(plantes, config),
		"type_depuis": "type_plante",
	}])

static func _par_id(choses: Array, id: String) -> Variant:
	for chose in choses:
		if String(chose.id) == id:
			return chose
	return null

# ---- LE TICK COMPLET ----

# ORDRE FIXE ET ASSUME -- voir l'en-tete pour les huit pas et les inversions qui
# seraient fausses. MUTE `etat` en place, etat.monde compris. Rend le rapport que
# le rendu et les tests relisent, jamais recalcule ailleurs.
static func avancer(etat: Dictionary, config: Dictionary, types: Dictionary, releve: Dictionary, delta: float) -> Dictionary:
	etat["temps"] = float(etat.temps) + delta
	etat["tick"] = int(etat.tick) + 1
	var plantes: Array = etat.plantes
	var monde = etat.monde
	var naissances: Array = []
	var morts: Array = []
	var produits: Array = []
	var perdues: Array = []
	var changements: Array = []

	# ETAT.PLANTES EST LE CACHE DES VIVANTES : il ne contient AUCUNE morte a
	# l'entree du tick (purge immediate en §2b, ajout des rejets apres §7,
	# aucune reconstruction paresseuse). `encore` l'ALIAS directement -- plus
	# de scan ni de copie O(N) ici, ce qui etait le seul cout toujours-paye du
	# tick. L'invariant "plantes propre a l'entree" est verrouille par
	# jeu/plantes/test_cache_vivantes.gd.
	var encore: Array = plantes

	# 1. l'ombre d'abord, pour tout le monde ; puis l'age, le stade, la stature.
	# L'ombre n'est PAS redemandee : chaque plante porte celle que le dernier
	# evenement de son voisinage lui a posee -- voir « L'OMBRE EST UN SIGNAL ».
	# Elle date de la fin du tick precedent, exactement comme avant.
	var stades_avant: Dictionary = {}
	var ombragees := 0
	# Les endroits ou quelque chose change ce tick. C'est autour d'eux, et
	# seulement autour d'eux, que l'ombre sera relue en fin de tick.
	var foyers: Array = []
	for plante in encore:
		stades_avant[plante.id] = String(plante.proprietes.get("stade", ""))
		if plante.proprietes.get("ombragee", false):
			ombragees += 1

	# VIEILLISSEMENT CONDITIONNEL, SANS UNE LIGNE DE MECANISME : senescence.gd
	# recoit son facteur EN PARAMETRE, et un facteur nul fige l'age. Le stade
	# suivant l'age, il se fige avec lui. La dominee n'est ni malade ni marquee :
	# elle ATTEND, et repart quand la grande disparait. Patron exact :
	# scripts/banc_succession.gd.
	var vitesse := float(config.annees_par_seconde)
	for plante in encore:
		var type_courant := type_de(plante, types)
		# L'HORLOGE DE MORT AVANCE TOUJOURS, sans regarder la lumiere. Accumulee
		# par ce cablage et par lui seul -- senescence.gd n'ecrit que 'age', et
		# c'est tres bien : les deux horloges ne doivent pas partager d'ecrivain.
		plante.proprietes["age_reel"] = float(plante.proprietes.get("age_reel", 0.0)) + delta * vitesse
		# L'HORLOGE DE CROISSANCE, elle, se fige a l'ombre.
		var facteur := 0.0 if plante.proprietes.get("ombragee", false) else vitesse
		Senescence.avancer(plante, delta, facteur)
		Stade.avancer(plante)
		if not type_courant.is_empty():
			plante.proprietes["stature"] = stature_de(plante, type_courant)
		var apres := String(plante.proprietes.get("stade", ""))
		if apres != String(stades_avant.get(plante.id, "")):
			# LA STATURE A CHANGE : ce qui l'entoure doit relire son ombre.
			foyers.append(plante.position)
			changements.append({
				"id": String(plante.id),
				"type": String(plante.proprietes.type_plante),
				"stade": apres,
				"numero": numero_de_stade(plante, type_courant),
			})

	# 2. la mort de vieillesse -- catalogue LOCAL, format exact du partage. Le
	# seuil est lu PAR PLANTE : deux longevites tres differentes traversent la
	# meme entree sans une branche.
	for id in SeuilEtat.avancer(encore, config.seuils_locaux):
		var morte: Variant = _par_id(encore, String(id))
		if morte == null or not est_disparue(morte, config):
			continue
		foyers.append(morte.position)
		morts.append(String(id))

	# 2b. PURGE IMMEDIATE des mortes de ce tick, EN PLACE dans etat.plantes.
	# `assign` reecrit le contenu du MEME objet tableau -- `encore` (qui
	# l'alias) reste valide et sans-morte pour §3-§7. C'est ce qui remplace
	# l'ancienne reconstruction paresseuse de §8 : etat.plantes est desormais
	# toujours propre, pas seulement aux frontieres de tick.
	if not morts.is_empty():
		plantes.assign(vivantes(plantes, config))

	# 3. les produits vieillissent. ILS SURVIVENT A LEUR PLANTE : un produit au sol
	# n'appartient plus a personne, il finit son temps meme si sa mere est morte.
	var restants: Array = []
	for graine in etat.graines:
		graine["age"] = float(graine.age) + delta
		if float(graine.age) > float(graine.duree_vie):
			perdues.append(String(graine.id))
			continue
		restants.append(graine)
	etat["graines"] = restants

	# LA CARTE DES COLONNES OCCUPEES, CONSTRUITE UNE FOIS PAR TICK et tenue a jour
	# au fil des poses. Elle etait refaite a chaque rejet et a chaque production --
	# un balayage complet par evenement, ce qui rendait le tick proportionnel au
	# produit du nombre de plantes par le nombre de naissances. Mesure : premier
	# poste de cout une fois l'ombre passee en signal.
	var prises := colonnes_prises(etat, config)

	# 4. la production. Le compteur est plafonne a un intervalle : sans ce plafond,
	# une plante longtemps bloquee par son plafond de produits en relacherait
	# plusieurs d'affilee des qu'une place se libere.
	# LES FERTILES ET LES GESTANTS DE CE TICK, ramasses pendant cette passe --
	# deja post-purge des mortes (§2b), deja en ordre. §5 n'itere que les
	# fertiles, §6 et §7 que les gestants : un stade ni fertile ni en gestation
	# ne coute plus un continue par boucle de reproduction.
	var fertiles: Array = []
	var gestants: Array = []
	var decalages_depot := anneau(1, int(config.rayon_depot_cellules))
	for plante in encore:
		var type_prod := type_de(plante, types)
		if type_prod.is_empty():
			continue
		if plante.proprietes.has("gestation"):
			gestants.append(plante)
		elif stade_fertile(plante, type_prod):
			fertiles.append(plante)
		var intervalle := intervalle_de_production(plante, type_prod)
		var compteur := float(plante.proprietes.get("compteur_production", 0.0)) + delta
		if intervalle == INF:
			plante.proprietes["compteur_production"] = 0.0
			continue
		if compteur < intervalle:
			plante.proprietes["compteur_production"] = compteur
			continue
		plante.proprietes["compteur_production"] = intervalle
		if produits_au_sol(etat, String(plante.id)) >= int(type_prod.max_produits_par_plante):
			continue
		var place: Variant = colonne_libre_autour(
			plante, decalages_depot, prises, releve, plafond_de(type_prod, releve), etat.rng)
		if place == null:
			continue
		var pose: Variant = Surface.position_posee(place, releve)
		if pose == null:
			continue
		plante.proprietes["compteur_production"] = 0.0
		etat["produits"] = int(etat.produits) + 1
		var graine := {
			"id": "graine_%d" % int(etat.produits),
			"colonne": place,
			"position": pose,
			"age": 0.0,
			"duree_vie": float(type_prod.duree_vie_produit),
			"ressource": String(type_prod.ressource),
			"type_plante": String(type_prod.nom),
			"plante_id": String(plante.id),
		}
		etat.graines.append(graine)
		prises[place] = String(graine.id)
		produits.append({"id": String(graine.id), "plante_id": String(plante.id), "colonne": place})

	# 5. la gestation se pose, sous DEUX gates : la densite (partagee) et le stade
	# (par espece). gestation.gd ne lit ni l'un ni l'autre -- c'est le refus de
	# l'appeler qui EST le gate. Chaque espece passe SON catalogue : elles n'ont
	# pas le meme rythme et gestation.gd resout la meme reference pour toutes.
	for plante in fertiles:
		var type_pousse := type_de(plante, types)
		if type_pousse.is_empty():
			continue
		if not peut_pousser(plante, type_pousse, monde, config, releve):
			continue
		Gestation.poser(plante, null,
			plante.proprietes.get("reproduction_locale", type_pousse.reproduction_locale))
		gestants.append(plante)

	# 6. le compteur avance.
	for plante in gestants:
		var type_gest := type_de(plante, types)
		if type_gest.is_empty():
			continue
		Gestation.avancer(plante,
			plante.proprietes.get("reproduction_locale", type_gest.reproduction_locale), delta)

	# 7. les rejets. La mere perd sa gestation dans TOUS les cas, y compris quand
	# aucun rejet n'a pris : sans ce retrait elle resterait prete pour toujours et
	# retenterait a chaque tick au lieu d'attendre le cycle suivant.
	# UN ANNEAU PAR ESPECE, construit au plus une fois par tick et par espece : la
	# capacite de dispersion est un trait d'espece, et l'anneau se deduit d'elle.
	# Le cache evite de le reconstruire a chaque mere.
	var anneaux: Dictionary = {}
	# LES REJETS DEJA TOMBES CE TICK, par colonne. C'est ce qui permet au gate de
	# trouee de se refermer PENDANT une rafale au lieu de la laisser passer.
	var nes_ce_tick: Dictionary = {}
	# LES REJETS S'ACCUMULENT ICI, JAMAIS DANS `plantes` PENDANT LA BOUCLE :
	# `encore` alias `plantes`, appendre en cours d'iteration ferait iterer
	# les rejets (ils se reproduiraient le meme tick) et muterait la liste
	# parcourue. Ils sont integres a `plantes` APRES la boucle.
	var nouveaux: Array = []
	for plante in gestants:
		var gestation: Dictionary = plante.proprietes.get("gestation", {})
		if gestation.is_empty() or not gestation.get("naissance_prete", false):
			continue
		var type_mere := type_de(plante, types)
		if type_mere.is_empty():
			plante.proprietes.erase("gestation")
			continue
		var plafond := plafond_de(type_mere, releve)
		var nom_mere := String(type_mere.nom)
		if not anneaux.has(nom_mere):
			anneaux[nom_mere] = anneau(
				int(type_mere.rayon_dispersion_min), int(type_mere.rayon_dispersion_max))
		var decalages: Array = anneaux[nom_mere]
		var combien: int = etat.rng.randi_range(int(config.rejets_min), int(config.rejets_max))
		for _i in range(combien):
			var colonne := colonne_de_rejet(plante, decalages, etat.rng)
			if prises.has(colonne) or not Surface.est_plantable(colonne, releve, plafond):
				continue
			var arrivee: Variant = Surface.position_posee(colonne, releve)
			if arrivee == null:
				continue
			# LA TROUEE, et c'est ici seulement qu'elle se joue : le rejet regarde
			# ou il tombe, pas d'ou il vient.
			if not trouee_suffisante(arrivee, monde, config, type_mere, releve, nes_ce_tick):
				continue
			etat["rejets"] = int(etat.rejets) + 1
			var rejet := fabriquer_plante("rejet_%d" % int(etat.rejets), colonne, releve, config, type_mere, etat.rng)
			if rejet.is_empty():
				continue
			nouveaux.append(rejet)
			prises[colonne] = String(rejet.id)
			nes_ce_tick[colonne] = true
			foyers.append(rejet.position)
			naissances.append({
				"id": String(rejet.id),
				"mere_id": String(plante.id),
				"mere_colonne": plante.colonne,
				"type": String(type_mere.nom),
				"colonne": colonne,
			})
			etat["naissances"] = int(etat.naissances) + 1
		plante.proprietes.erase("gestation")

	# LES REJETS DU TICK sont integres a `plantes` (= etat.plantes) MAINTENANT,
	# hors de la boucle §7 : ils rejoignent le cache des vivantes sans avoir
	# ete iteres ni s'etre reproduits ce tick.
	if not nouveaux.is_empty():
		plantes.append_array(nouveaux)

	# 8. le Monde ne se reconstruit qu'aux ticks ou sa composition change.
	# etat.plantes est DEJA a jour : les mortes ont ete purgees en §2b, les
	# rejets ajoutes juste au-dessus. Plus de purge paresseuse ici -- juste la
	# reconstruction du Monde, a partir d'une liste deja propre (deja_propre).
	etat["morts"] = int(etat.morts) + morts.size()
	if not morts.is_empty() or not naissances.is_empty():
		etat["monde"] = monde_des_vivantes(plantes, config, true)

	# APRES la reconstruction du Monde, jamais avant : relire l'OMBRE (pas le
	# compte de voisins -- il est deja a jour) sur un Monde qui contient encore
	# les mortes du tick les laisserait ombrager depuis leur tombe.
	var relues := rafraichir_autour(etat, config, releve, foyers)

	return {
		"tick": int(etat.tick),
		"temps": float(etat.temps),
		# etat.plantes est PROPRE ici : §8 vient de le purger si la composition
		# a change, sinon aucune morte n'y figure (invariant de fin de tick).
		# Un scan vivantes() de plus juste pour compter serait O(N) gaspille.
		"vivantes": (etat.plantes as Array).size(),
		"ombragees": ombragees,
		"ombres_relues": relues,
		"graines": (etat.graines as Array).size(),
		"changements": changements,
		"produits": produits,
		"perdues": perdues,
		"naissances": naissances,
		"morts": morts,
		"total_naissances": int(etat.naissances),
		"total_morts": int(etat.morts),
		"total_produits": int(etat.produits),
	}

# ---- LE PAS DE TEMPS, ET POURQUOI IL EST DECOUPE ----

# LE PLUS GRAND PAS FIDELE, deduit des donnees et jamais reglé a la main.
#
# Tous les seuils de ce couvert sont franchis EN RETARD D'UN PAS : une plante
# meurt au premier tick ou son age depasse sa longevite, pas a l'instant exact.
# Tant que le pas est petit devant les durees en jeu, le retard est du bruit. Des
# qu'il les approche, il devient une DEFORMATION -- une herbe qui vit 100 s meurt
# a 120 avec un pas de 30, soit 20 % de vie en plus, a chaque generation, et ca
# compose. MESURE : a 600 s simulees, un pas de 30 rend trois fois plus d'herbe
# qu'un pas de 1. Et un pas plus grand qu'un stade le saute purement.
#
# LE QUART DE LA PLUS COURTE DUREE : un seuil ne peut alors etre depasse que d'un
# quart de la duree qui le porte. Le facteur est arbitraire, la GRANDEUR ne l'est
# pas -- elle sort des donnees, donc une espece plus rapide resserre le pas d'elle
# meme, sans que personne y pense.
static func pas_maximal(types: Dictionary, config: Dictionary) -> float:
	var plus_court := INF
	for nom in types:
		var type: Dictionary = types[nom]
		for stade in (type.stades as Array):
			plus_court = minf(plus_court, float(stade.duree))
		plus_court = minf(plus_court, float(type.reproduction_locale[String(config.reproduction_ref)].duree_gestation))
		if float(type.intervalle_production) > 0.0 and int(type.stade_production_min) <= dernier_stade(type):
			plus_court = minf(plus_court, float(type.intervalle_production))
		if float(type.duree_vie_produit) > 0.0:
			plus_court = minf(plus_court, float(type.duree_vie_produit))
	if plus_court == INF or plus_court <= 0.0:
		return 0.0
	return plus_court * 0.25

# LE MEME TEMPS, DECOUPE EN TRANCHES FIDELES. C'est le SEUL point d'entree du
# tick pour un appelant : ni le rendu ni le prechauffage n'appellent avancer()
# directement, justement pour qu'aucun des deux ne puisse choisir un pas trop
# grand.
#
# UN PRECHAUFFAGE EST DONC EXACTEMENT LA MEME SIMULATION, jouee plus tot -- pas
# une approximation plus rapide. Un pas de 30 secondes demande a la simulation
# d'avancer de 30 secondes ; il ne l'autorise pas a le faire d'un bond.
#
# Rend le rapport de la DERNIERE tranche, plus les evenements de toutes : un
# appelant qui pose des noeuds doit voir chaque naissance, pas seulement celles du
# dernier morceau.
static func avancer_par_tranches(etat: Dictionary, config: Dictionary, types: Dictionary, releve: Dictionary, delta: float, pas_max: float) -> Dictionary:
	if pas_max <= 0.0 or delta <= pas_max:
		return avancer(etat, config, types, releve, delta)

	var cumul := {"changements": [], "produits": [], "perdues": [], "naissances": [], "morts": []}
	var rapport: Dictionary = {}
	var reste := delta
	while reste > 0.0:
		var tranche: float = minf(pas_max, reste)
		reste -= tranche
		rapport = avancer(etat, config, types, releve, tranche)
		for cle in cumul:
			(cumul[cle] as Array).append_array(rapport[cle])
	for cle in cumul:
		rapport[cle] = cumul[cle]
	return rapport

# ---- Retirer une plante du dehors ----

# LE SEUL GESTE QUI OTE UNE PLANTE SANS ATTENDRE SA MORT. C'est ce qu'un colon
# qui abat un arbre appellera -- le mecanisme de coupe n'existe pas encore, le
# point d'entree si.
#
# IL NE SUFFIT PAS DE LA MARQUER MORTE. L'ombre etant desormais portee par chaque
# plante et mise a jour PAR SIGNAL, retirer une plante sans prevenir son voisinage
# laisserait les dominees gelees pour toujours -- l'arbre serait coupe et la
# strate ne repartirait jamais. Ce piege est REEL : il a ete trouve en lancant le
# test, qui marquait la mort a la main.
#
# Le Monde est reconstruit ET l'ombre relue autour du trou, dans cet ordre : relire
# l'ombre sur un Monde qui contient encore la plante retiree la laisserait
# ombrager depuis sa tombe.
#
# Rend false si l'id est inconnu ou la plante deja partie -- jamais une seconde
# coupe sur le meme arbre.
static func retirer(etat: Dictionary, id: String, config: Dictionary, releve: Dictionary) -> bool:
	var plante: Variant = _par_id(etat.plantes, id)
	if plante == null or est_disparue(plante, config):
		return false
	var actifs: Array = plante.proprietes.get("etats_actifs", [])
	actifs.append(String(config.etat_morte))
	plante.proprietes["etats_actifs"] = actifs
	var position: Vector3 = plante.position
	etat["plantes"] = vivantes(etat.plantes, config)
	etat["monde"] = monde_des_vivantes(etat.plantes, config)
	# rafraichir_autour relit l'OMBRE autour du trou.
	rafraichir_autour(etat, config, releve, [position])
	return true

# ---- Le ramassage ----

# LE COLON RAMASSE LE PRODUIT, PAS LA PLANTE. Elle n'est jamais touchee : elle
# continue de vivre et de produire, et la place liberee au sol lui rouvre son
# plafond. C'est ce qui distingue ce couvert d'une ressource qui s'epuise.
#
# La cle de ressource vient de l'espece, jamais du code : c'est une CLE, pas un
# texte joueur (CLAUDE.md, INTERNATIONALISATION).
static func ramasser(etat: Dictionary, id: String, _config: Dictionary) -> Dictionary:
	var au_sol: Array = etat.graines
	for i in range(au_sol.size()):
		if String(au_sol[i].id) != id:
			continue
		var ressource := String(au_sol[i].ressource)
		au_sol.remove_at(i)
		return {"ressource": ressource, "quantite": 1.0}
	return {}
