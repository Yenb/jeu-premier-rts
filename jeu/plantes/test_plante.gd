extends SceneTree

# Test manuel :
# godot --headless --script jeu/plantes/test_plante.gd
#
# Verrouille le couvert vegetal, de bout en bout, SANS UN SEUL NOEUD DE RENDU :
# c'est la preuve que la simulation ne depend pas de l'affichage (CLAUDE.md).
#
# Ce qui est tenu :
# - chaque espece traverse TOUS ses stades, aux instants que ses durees cumulees
#   annoncent, et meurt juste apres le dernier ;
# - LE PLAFOND DE COUCHE EST PAR ESPECE : une colonne trop haute pour l'arbre
#   reste plantable pour l'herbe ;
# - L'OMBRE COMPARE DES STATURES, PAS DES NUMEROS DE STADE : l'herbe n'ombrage
#   jamais l'arbre, l'arbre ombrage toujours l'herbe, deux egales cohabitent, et
#   la dominee repart quand la grande meurt ;
# - LA TROUEE EST PAR ESPECE : un rejet d'arbre renonce la ou le tapis est dense,
#   un rejet d'herbe s'installe au meme endroit ;
# - LA DISPERSION EST PAR ESPECE : la distance mesuree entre une mere et ses
#   rejets tient dans l'anneau de SON espece, et l'arbre porte plus loin que
#   l'herbe -- sans cette derniere comparaison, un anneau redevenu commun
#   passerait sans rougir ;
# - LA DENSITE EST PAR ESPECE : au MEME voisinage, l'arbre renonce a se
#   reproduire et l'herbe continue ;
# - la production sort a partir du stade declare, ralentie au dernier, plafonnee
#   au sol, et le produit se perd apres sa duree de vie ;
# - la reproduction n'a lieu qu'entre les deux bornes de stade ;
# - la densite refuse la pousse au-dela du plafond de voisinage ;
# - L'OMBRE ET LE COMPTE DE VOISINS PORTES PAR CHAQUE PLANTE VALENT LEUR RECALCUL
#   COMPLET, a chaque tick et sur chaque plante -- sans quoi une plante resterait
#   gelee a tort, ou se reproduirait dans une foule, en silence ;
# - la meme graine de RNG rejoue exactement la meme foret ;
# - le prechauffage est du temps vecu : N + M ticks == N+M ticks ;
# - ET UN GROS PAS REND LA MEME SIMULATION QU'UN PETIT : aucun stade saute, aucune
#   population qui derive. Sans ce verrou, accelerer changeait le monde ;
# - la touffe procedurale repose au sol et fait la hauteur demandee ;
# - LE TRONC EST UN FUT, PAS L'ARBRE : un cylindre du rayon declare par l'espece,
#   haut comme la stature du stade donc grandissant avec elle, et ABSENT quand
#   l'espece ne declare aucun rayon -- l'herbe reste traversable ;
# - LES REGLAGES DE L'INSPECTEUR ET LE FICHIER NE PEUVENT PAS DIVERGER.
#
# AUCUNE DUREE, AUCUNE STATURE, AUCUN PLAFOND N'EST ECRIT ICI : tout se relit sur
# les fichiers d'espece. Seuls les deux NOMS d'espece sont nommes, ce qu'un banc
# d'observation s'autorise (CLAUDE.md).
#
# LE TERRAIN EST CONSTRUIT ICI, petit et connu, avec TROIS niveaux : un plateau
# bas ou tout pousse, un replat que seule l'herbe atteint, une butte interdite aux
# deux. Sans ces trois, le plafond par espece ne se prouve pas.
#
# Regles tenues : positions en Vector3, colonnes en Vector2i. Aucun hasard hors du
# RNG seede. Rien de scripts/, data/ ni addons/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const Vegetation = preload("res://jeu/plantes/vegetation.gd")
const Surface = preload("res://jeu/plantes/surface_terrain.gd")
const Couvert = preload("res://jeu/plantes/couvert.gd")
const PlanteScene = preload("res://jeu/plantes/plante.tscn")
const EspeceScript = preload("res://jeu/plantes/espece.gd")

const CHEMIN_BIBLIOTHEQUE := "res://jeu/terrain/bloc.tres"

const ESPECE_HAUTE := "arbre"
const ESPECE_BASSE := "herbe"

const COTE := 40
const COUCHE_PLATEAU := 0
const COUCHE_REPLAT := 4
const COUCHE_BUTTE := 10

const COLONNE_BASSE := Vector2i(8, 8)
const COLONNE_LOIN := Vector2i(24, 24)
const COLONNE_REPLAT := Vector2i(3, 30)
const COLONNE_BUTTE := Vector2i(36, 36)

const PAS := 1.0

var _v
var _config: Dictionary = {}
var _types: Dictionary = {}
var _releve: Dictionary = {}

func _init() -> void:
	_v = Verif.new()

	_config = Vegetation.charger_config()
	_v.v(not _config.is_empty(), "vegetation.json introuvable ou illisible")
	if _config.is_empty():
		_conclure()
		return

	# LES DEUX ESPECES SONT MONTEES COMME DANS LA SCENE : un noeud espece.gd par
	# espece, avec ses champs. Charger autrement que le jeu ne prouverait rien du
	# chemin que le jeu emprunte.
	for reglage in [_espece_haute(), _espece_basse()]:
		var type := Vegetation.preparer_depuis_champs(
			String(reglage.nom), reglage.champs(), _config)
		_v.v(not type.is_empty(), "l'espece '%s' ne prepare aucun stade" % reglage.nom)
		if not type.is_empty():
			_types[String(reglage.nom)] = type
		reglage.free()

	if _types.size() < 2:
		_conclure()
		return

	var grille := _construire_terrain()
	_releve = Surface.relever(grille)
	if not _releve_coherent():
		grille.free()
		_conclure()
		return

	_juger_les_plafonds()
	for nom in _types:
		_juger_le_cycle(String(nom))
	_juger_l_ombre()
	_juger_la_trouee()
	_juger_la_densite()
	_juger_la_dispersion()
	_juger_le_ramassage()
	_juger_la_reproductibilite()
	_juger_l_ombre_par_signal()
	_juger_le_pas_de_temps()
	_juger_le_prechauffage()
	_juger_la_touffe()
	_juger_le_tronc()
	_juger_les_reglages()

	grille.free()
	_conclure()

# ---- Le terrain d'essai ----

func _construire_terrain() -> GridMap:
	var grille := GridMap.new()
	grille.mesh_library = load(CHEMIN_BIBLIOTHEQUE) as MeshLibrary
	for x in range(COTE):
		for z in range(COTE):
			grille.set_cell_item(Vector3i(x, COUCHE_PLATEAU, z), 0)
	for x in range(0, 8):
		for z in range(26, COTE):
			for y in range(COUCHE_PLATEAU + 1, COUCHE_REPLAT + 1):
				grille.set_cell_item(Vector3i(x, y, z), 0)
	for x in range(34, COTE):
		for z in range(34, COTE):
			for y in range(COUCHE_PLATEAU + 1, COUCHE_BUTTE + 1):
				grille.set_cell_item(Vector3i(x, y, z), 0)
	return grille

func _releve_coherent() -> bool:
	_v.v(int(_releve.couche_reference) == COUCHE_PLATEAU,
		"le sol le plus bas releve est %d, attendu %d" % [
			int(_releve.couche_reference), COUCHE_PLATEAU])
	_v.v(int(Surface.couche_de(COLONNE_REPLAT, _releve)) == COUCHE_REPLAT,
		"le replat n'est pas a la couche %d" % COUCHE_REPLAT)
	_v.v(int(Surface.couche_de(COLONNE_BUTTE, _releve)) == COUCHE_BUTTE,
		"la butte n'est pas a la couche %d" % COUCHE_BUTTE)
	print("releve : sol le plus bas couche %d, %d colonnes" % [
		int(_releve.couche_reference), (_releve.sommets as Dictionary).size()])
	return _v.echecs() == 0

# ---- Le plafond, par espece ----

func _juger_les_plafonds() -> void:
	var haute: Dictionary = _types[ESPECE_HAUTE]
	var basse: Dictionary = _types[ESPECE_BASSE]
	var plafond_haute := Vegetation.plafond_de(haute, _releve)
	var plafond_basse := Vegetation.plafond_de(basse, _releve)

	# Le jeu de donnees doit vraiment opposer les deux, sinon rien n'est prouve.
	_v.v(plafond_basse > plafond_haute,
		"les deux especes ont le meme plafond (%d et %d) : le plafond par espece ne prouverait rien" % [
			plafond_haute, plafond_basse])

	_v.v(Surface.est_plantable(COLONNE_BASSE, _releve, plafond_haute),
		"le plateau bas n'est pas plantable pour '%s'" % ESPECE_HAUTE)
	_v.v(Surface.est_plantable(COLONNE_BASSE, _releve, plafond_basse),
		"le plateau bas n'est pas plantable pour '%s'" % ESPECE_BASSE)

	# LE COEUR DU MULTI-ESPECE : la MEME colonne, deux verdicts.
	_v.v(not Surface.est_plantable(COLONNE_REPLAT, _releve, plafond_haute),
		"le replat (couche %d) est plantable pour '%s', dont le plafond est %d" % [
			COUCHE_REPLAT, ESPECE_HAUTE, plafond_haute])
	_v.v(Surface.est_plantable(COLONNE_REPLAT, _releve, plafond_basse),
		"le replat (couche %d) n'est pas plantable pour '%s', dont le plafond est %d" % [
			COUCHE_REPLAT, ESPECE_BASSE, plafond_basse])

	_v.v(not Surface.est_plantable(COLONNE_BUTTE, _releve, plafond_basse),
		"la butte est plantable meme pour '%s' : elle ne depasse aucun plafond" % ESPECE_BASSE)

	# ET LE SEMIS HORS COUCHE EST POSE QUAND MEME, seulement signale.
	var etat := Vegetation.etat_initial([
		{"id": "trop_haut", "colonne": COLONNE_BUTTE, "type": ESPECE_HAUTE},
		{"id": "inconnu", "colonne": COLONNE_LOIN, "type": "espece_qui_n_existe_pas"},
	], _releve, _config, _types)
	var raisons: Dictionary = {}
	for refus in etat.refus:
		raisons[String(refus.id)] = String(refus.raison)
	_v.v(raisons.get("trop_haut", "") == "couche_trop_haute",
		"le semis de la butte est refuse pour '%s'" % raisons.get("trop_haut", ""))
	_v.v(raisons.get("inconnu", "") == "type_inconnu",
		"le semis d'espece inconnue est refuse pour '%s'" % raisons.get("inconnu", ""))
	var poses: Array = []
	for plante in etat.plantes:
		poses.append(String(plante.id))
	_v.v(poses.has("trop_haut"),
		"le semis de la butte a disparu : le mecanisme a supprime ce que le game designer a place")
	_v.v(not poses.has("inconnu"),
		"un semis d'espece inconnue a ete pose : avec quelle table de stades ?")
	print("plafonds : '%s' couche %d, '%s' couche %d" % [
		ESPECE_HAUTE, plafond_haute, ESPECE_BASSE, plafond_basse])

# ---- Le cycle d'une espece ----

func _juger_le_cycle(nom: String) -> void:
	var type: Dictionary = _types[nom]
	var stades: Array = type.stades
	var etat := Vegetation.etat_initial(
		[{"id": "sujet", "colonne": COLONNE_BASSE, "type": nom}], _releve, _config, _types)

	var sujet: Dictionary = etat.plantes[0]
	var courant := String(sujet.proprietes.stade)
	var vus: Array = [courant]
	var instants: Dictionary = {courant: 0.0}
	var statures: Dictionary = {courant: float(sujet.proprietes.stature)}
	var produits: Dictionary = {courant: 0}
	var morte_a := -1.0

	var limite := float(type.longevite) + PAS * 4.0
	var temps := 0.0
	while temps < limite:
		var rapport := Vegetation.avancer(etat, _config, _types, _releve, PAS)
		temps = float(rapport.temps)
		for changement in rapport.changements:
			if String(changement.id) != "sujet":
				continue
			courant = String(changement.stade)
			vus.append(courant)
			instants[courant] = temps
			produits[courant] = 0
			var vivant: Variant = _par_id(etat.plantes, "sujet")
			if vivant != null:
				statures[courant] = float(vivant.proprietes.stature)
		for produit in rapport.produits:
			if String(produit.plante_id) == "sujet":
				produits[courant] = int(produits.get(courant, 0)) + 1
		for id in rapport.morts:
			if String(id) == "sujet" and morte_a < 0.0:
				morte_a = temps

	var attendus: Array = []
	for stade in stades:
		attendus.append(String(stade.nom))
	_v.v(vus == attendus, "'%s' traverse %s, attendu %s" % [nom, vus, attendus])

	# CHAQUE STADE COMMENCE A LA SOMME DES DUREES QUI LE PRECEDENT, ET PORTE LA
	# STATURE DECLAREE. Verifier l'ordre seul laisserait passer n'importe quel
	# rythme, et ne dirait rien de la hauteur dont depend toute l'ombre.
	var cumul := 0.0
	for i in range(stades.size()):
		var stade: Dictionary = stades[i]
		var obtenu := float(instants.get(String(stade.nom), -1.0))
		_v.v(obtenu >= cumul and obtenu <= cumul + PAS * 2.0,
			"'%s' entre au stade '%s' a %.1f s, attendu vers %.0f s" % [nom, stade.nom, obtenu, cumul])
		_v.v(is_equal_approx(float(statures.get(String(stade.nom), -1.0)), float(stade.stature)),
			"'%s' au stade '%s' porte la stature %s, attendu %s" % [
				nom, stade.nom, statures.get(String(stade.nom), -1.0), stade.stature])
		cumul += float(stade.duree)

	_v.v(morte_a > float(type.longevite),
		"'%s' meurt a %.1f s, avant la somme de ses stades (%.0f s)" % [nom, morte_a, float(type.longevite)])
	_v.v(morte_a >= 0.0 and morte_a <= float(type.longevite) + PAS * 2.0,
		"'%s' meurt a %.1f s, bien apres la somme de ses stades (%.0f s)" % [nom, morte_a, float(type.longevite)])

	# LA PRODUCTION SUIT LE STADE DECLARE. Une espece dont le stade de production
	# depasse son dernier stade ne produit jamais -- et c'est aussi un resultat.
	var premier := int(type.stade_production_min)
	for i in range(mini(premier - 1, stades.size())):
		_v.v(int(produits.get(String(stades[i].nom), 0)) == 0,
			"'%s' produit au stade '%s', sous son stade de production (%d)" % [
				nom, stades[i].nom, premier])
	print("cycle %s : %s, statures %s, produits %s, mort a %.0f s" % [
		nom, vus, statures, produits, morte_a])

# ---- L'ombre, par stature ----

func _juger_l_ombre() -> void:
	var haute: Dictionary = _types[ESPECE_HAUTE]
	var basse: Dictionary = _types[ESPECE_BASSE]

	# Le jeu de donnees doit vraiment separer les deux strates.
	var plus_grande_basse := 0.0
	for stade in (basse.stades as Array):
		plus_grande_basse = maxf(plus_grande_basse, float(stade.stature))
	var plus_petite_haute := INF
	for stade in (haute.stades as Array):
		plus_petite_haute = minf(plus_petite_haute, float(stade.stature))
	_v.v(plus_grande_basse < plus_petite_haute,
		"la plus grande stature de '%s' (%.2f) atteint la plus petite de '%s' (%.2f) : les strates se croisent" % [
			ESPECE_BASSE, plus_grande_basse, ESPECE_HAUTE, plus_petite_haute])

	# (1) L'herbe sous l'arbre se fige ; l'arbre a cote ne se fige pas.
	var etat := Vegetation.etat_initial([
		{"id": "arbre", "colonne": COLONNE_BASSE, "type": ESPECE_HAUTE},
		{"id": "herbe", "colonne": COLONNE_BASSE + Vector2i(1, 0), "type": ESPECE_BASSE},
		{"id": "libre", "colonne": COLONNE_BASSE + Vector2i(int(_config.rayon_ombre_cellules) + 3, 0), "type": ESPECE_BASSE},
	], _releve, _config, _types)
	var arbre: Dictionary = etat.plantes[0]
	var herbe: Dictionary = etat.plantes[1]
	var libre: Dictionary = etat.plantes[2]

	for _i in range(20):
		Vegetation.avancer(etat, _config, _types, _releve, PAS)

	_v.v(is_equal_approx(float(herbe.proprietes.age), 0.0),
		"l'herbe sous l'arbre a vieilli de %.1f s : l'ombre ne fige rien" % herbe.proprietes.age)
	_v.v(float(libre.proprietes.age) > 0.0,
		"l'herbe hors de portee est figee aussi : l'ombre ne connait pas son rayon")
	# L'ARBRE N'EST JAMAIS FIGE PAR L'HERBE, et c'est tout l'interet de la stature :
	# avec des numeros de stade, l'herbe au stade 3 aurait fige l'arbre au stade 1.
	_v.v(float(arbre.proprietes.age) > 0.0,
		"l'arbre est fige par l'herbe voisine : l'ombre compare autre chose que la stature")

	# (2) L'arbre est abattu, l'herbe repart. PAR LE VRAI GESTE, jamais en marquant
	# la mort a la main : l'ombre etant portee par chaque plante, retirer une
	# plante sans prevenir son voisinage laisse les dominees gelees pour toujours.
	# Ce test l'a trouve -- il marquait la mort a la main et l'herbe ne repartait
	# plus.
	_v.v(Vegetation.retirer(etat, "arbre", _config, _releve),
		"retirer l'arbre a echoue")
	Vegetation.avancer(etat, _config, _types, _releve, PAS)
	var age_a_la_coupe := float(herbe.proprietes.age)
	for _i in range(10):
		Vegetation.avancer(etat, _config, _types, _releve, PAS)
	_v.v(float(herbe.proprietes.age) > age_a_la_coupe,
		"l'herbe reste figee apres la coupe de l'arbre : couper ne libere pas la strate")
	# ET ON NE COUPE PAS DEUX FOIS LE MEME ARBRE.
	_v.v(not Vegetation.retirer(etat, "arbre", _config, _releve),
		"retirer deux fois la meme plante reussit")

	# (3) LA DOMINEE MEURT QUAND MEME, a l'heure. Sans ca elle serait immortelle :
	# son age gele ne franchirait jamais sa longevite, elle occuperait sa colonne
	# pour toujours, compterait pour toujours dans le plafond de densite, et la
	# foret ne pourrait plus reprendre un sous-bois qui ne se vide jamais. Mesure
	# faite avant la correction : une herbe sous un arbre etait encore vivante dix
	# vies plus tard, age zero.
	var duo := Vegetation.etat_initial([
		{"id": "grand", "colonne": COLONNE_LOIN, "type": ESPECE_HAUTE},
		{"id": "dominee", "colonne": COLONNE_LOIN + Vector2i(1, 0), "type": ESPECE_BASSE},
	], _releve, _config, _types)
	var geant: Dictionary = duo.plantes[0]
	geant.proprietes["age"] = float((haute.stades as Array)[0].duree) + 1.0
	geant.proprietes["stade"] = String((haute.stades as Array)[1].nom)
	var dominee: Dictionary = duo.plantes[1]
	var fin := float((basse as Dictionary).longevite)
	var horloge := 0.0
	while horloge < fin * 3.0:
		horloge = float(Vegetation.avancer(duo, _config, _types, _releve, PAS).temps)
	_v.v(is_equal_approx(float(dominee.proprietes.age), 0.0),
		"la dominee a grandi de %.0f s : l'ombre ne fige plus la croissance" % dominee.proprietes.age)
	_v.v(Vegetation.est_disparue(dominee, _config),
		"la dominee vit encore apres %.0f s pour une longevite de %.0f s : elle est immortelle" % [
			horloge, fin])
	print("mort a l'ombre : dominee morte a l'heure, age de croissance %.0f s apres %.0f s vecues" % [
		float(dominee.proprietes.age), float(dominee.proprietes.age_reel)])

	# (4) Deux egales cohabitent : strictement superieur, jamais « au moins egal ».
	var pair := Vegetation.etat_initial([
		{"id": "une", "colonne": COLONNE_BASSE, "type": ESPECE_BASSE},
		{"id": "deux", "colonne": COLONNE_BASSE + Vector2i(1, 0), "type": ESPECE_BASSE},
	], _releve, _config, _types)
	var une: Dictionary = pair.plantes[0]
	var deux: Dictionary = pair.plantes[1]
	for _i in range(10):
		Vegetation.avancer(pair, _config, _types, _releve, PAS)
	_v.v(float(une.proprietes.age) > 0.0 and float(deux.proprietes.age) > 0.0,
		"deux plantes de meme stature se figent l'une l'autre : la comparaison n'est pas stricte")
	print("ombre : herbe figee a %.1f s puis repartie, arbre libre a %.1f s" % [
		age_a_la_coupe, float(arbre.proprietes.age)])

# ---- La trouee, par espece ----

# LE GOULOT DEMOGRAPHIQUE : la MEME densite refuse un rejet d'arbre et accepte un
# rejet d'herbe. Sans les deux verdicts sur le meme tapis, ce n'est qu'un second
# plafond de densite -- et ce test ne prouverait rien de l'ecologie.
func _juger_la_trouee() -> void:
	var haute: Dictionary = _types[ESPECE_HAUTE]
	var basse: Dictionary = _types[ESPECE_BASSE]
	_v.v(int(haute.trouee_max_voisins) < int(basse.trouee_max_voisins),
		"'%s' exige %s voisines au plus, '%s' %s : les deux se valent, rien n'est prouve" % [
			ESPECE_HAUTE, haute.trouee_max_voisins, ESPECE_BASSE, basse.trouee_max_voisins])

	var centre := COLONNE_LOIN
	var semis: Array = []
	for i in range(int(basse.trouee_max_voisins)):
		semis.append({
			"id": "tapis_%d" % i,
			"colonne": centre + Vector2i(i % 3 - 1, i / 3 - 1),
			"type": ESPECE_BASSE,
		})
	var etat := Vegetation.etat_initial(semis, _releve, _config, _types)
	var position: Variant = Surface.position_posee(centre, _releve)

	_v.v(not Vegetation.trouee_suffisante(position, etat.monde, _config, haute, _releve),
		"un rejet de '%s' s'installe dans un tapis de %d : la trouee ne retient rien" % [
			ESPECE_HAUTE, semis.size()])
	_v.v(Vegetation.trouee_suffisante(position, etat.monde, _config, basse, _releve),
		"un rejet de '%s' renonce dans son propre tapis de %d : il ne s'etendrait jamais" % [
			ESPECE_BASSE, semis.size()])

	# ET DANS LE VIDE, LES DEUX PASSENT : sans ce temoin, une trouee toujours
	# fausse passerait le premier controle.
	var vide := Vegetation.etat_initial([], _releve, _config, _types)
	_v.v(Vegetation.trouee_suffisante(position, vide.monde, _config, haute, _releve),
		"un rejet de '%s' renonce sur un terrain vide" % ESPECE_HAUTE)
	print("trouee : tapis de %d -- '%s' renonce, '%s' s'installe" % [
		semis.size(), ESPECE_HAUTE, ESPECE_BASSE])

# ---- La dispersion ----

# OU TOMBENT LES REJETS, ET C'EST UN TRAIT D'ESPECE. Le test mesure la distance
# reelle entre une mere et ses rejets, en cellules, et exige qu'elle tienne dans
# l'anneau DE SON ESPECE -- puis que les deux especes ne portent pas a la meme
# distance. Sans cette derniere comparaison, un anneau redevenu commun passerait
# le test sans que rien ne rougisse.
func _juger_la_dispersion() -> void:
	var portees: Dictionary = {}
	for nom in _types:
		var type: Dictionary = _types[nom]
		var mesure := _portee_des_rejets(String(nom))
		if mesure.is_empty():
			_v.v(false, "'%s' n'a produit aucun rejet : la dispersion n'est pas mesuree" % nom)
			continue
		portees[nom] = mesure
		_v.v(float(mesure.min) >= float(type.rayon_dispersion_min) - 0.001,
			"'%s' depose un rejet a %.2f cellules, en deca de son anneau (%d)" % [
				nom, float(mesure.min), int(type.rayon_dispersion_min)])
		_v.v(float(mesure.max) <= float(type.rayon_dispersion_max) + 0.001,
			"'%s' depose un rejet a %.2f cellules, au-dela de son anneau (%d)" % [
				nom, float(mesure.max), int(type.rayon_dispersion_max)])

	if portees.size() == 2:
		var haute: Dictionary = portees[ESPECE_HAUTE]
		var basse: Dictionary = portees[ESPECE_BASSE]
		_v.v(float(haute.max) > float(basse.max),
			"'%s' ne porte pas plus loin que '%s' (%.2f contre %.2f) : l'anneau est reste commun" % [
				ESPECE_HAUTE, ESPECE_BASSE, float(haute.max), float(basse.max)])
		print("dispersion : '%s' de %.2f a %.2f cellules, '%s' de %.2f a %.2f" % [
			ESPECE_HAUTE, float(haute.min), float(haute.max),
			ESPECE_BASSE, float(basse.min), float(basse.max)])

# Une mere seule sur le plateau, jouee jusqu'a ce qu'elle seme. Rend la distance
# minimale et maximale de ses rejets, en cellules -- {} si elle n'a rien seme.
func _portee_des_rejets(espece: String) -> Dictionary:
	var etat := Vegetation.etat_initial(
		[{"id": "mere", "colonne": COLONNE_LOIN, "type": espece}], _releve, _config, _types)
	var pas: float = Vegetation.pas_maximal(_types, _config)
	var plus_pres := INF
	var plus_loin := 0.0
	var combien := 0
	while float(etat.temps) < 4000.0 and combien < 12:
		var rapport := Vegetation.avancer_par_tranches(etat, _config, _types, _releve, pas, pas)
		for naissance in rapport.naissances:
			var ecart: Vector2i = (naissance.colonne as Vector2i) - (naissance.mere_colonne as Vector2i)
			var distance := sqrt(float(ecart.x * ecart.x + ecart.y * ecart.y))
			plus_pres = minf(plus_pres, distance)
			plus_loin = maxf(plus_loin, distance)
			combien += 1
	if combien == 0:
		return {}
	return {"min": plus_pres, "max": plus_loin, "combien": combien}

# ---- La densite ----

# LA DENSITE EST PAR ESPECE, et le test ne vaut que s'il OPPOSE les deux : le
# meme voisinage doit fermer l'une et laisser l'autre pousser. Un test qui ne
# verifierait qu'un plafond passerait a l'identique avec une valeur partagee, et
# ne prouverait donc rien du chantier.
func _juger_la_densite() -> void:
	var plafond_haute := int((_types[ESPECE_HAUTE] as Dictionary).max_voisins)
	var plafond_basse := int((_types[ESPECE_BASSE] as Dictionary).max_voisins)
	_v.v(plafond_basse > plafond_haute,
		"le jeu d'essai n'oppose pas les deux densites (%d et %d) : rien n'est prouve" % [
			plafond_haute, plafond_basse])

	_v.v(_pousse_avec(ESPECE_HAUTE, plafond_haute - 1),
		"'%s' avec %d congeneres a portee ne pousse pas : son plafond refuse trop tot" % [
			ESPECE_HAUTE, plafond_haute - 1])
	_v.v(not _pousse_avec(ESPECE_HAUTE, plafond_haute),
		"'%s' avec %d congeneres a portee pousse encore : son plafond ne retient rien" % [
			ESPECE_HAUTE, plafond_haute])
	_v.v(_pousse_avec(ESPECE_HAUTE, 0), "une plante isolee ne pousse pas")

	# LE MEME VOISINAGE, L'AUTRE ESPECE : la ou l'arbre renonce, l'herbe continue.
	_v.v(_pousse_avec(ESPECE_BASSE, plafond_haute),
		"'%s' s'arrete au plafond de '%s' : la densite n'est pas par espece" % [
			ESPECE_BASSE, ESPECE_HAUTE])
	_v.v(not _pousse_avec(ESPECE_BASSE, plafond_basse),
		"'%s' avec %d congeneres a portee pousse encore : son propre plafond ne retient rien" % [
			ESPECE_BASSE, plafond_basse])
	print("densite : plafond %d pour '%s', %d pour '%s' -- meme voisinage, deux verdicts" % [
		plafond_haute, ESPECE_HAUTE, plafond_basse, ESPECE_BASSE])

func _pousse_avec(espece: String, voisines: int) -> bool:
	var centre := COLONNE_LOIN
	var semis: Array = [{"id": "sujet", "colonne": centre, "type": espece}]
	var decalages := _couronne(voisines)
	for i in range(decalages.size()):
		semis.append({
			"id": "voisine_%d" % i,
			"colonne": centre + (decalages[i] as Vector2i),
			"type": ESPECE_BASSE,
		})
	var etat := Vegetation.etat_initial(semis, _releve, _config, _types)
	return Vegetation.peut_pousser(etat.plantes[0], _types[espece])

func _couronne(nombre: int) -> Array:
	var decalages: Array = []
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			if dx == 0 and dz == 0:
				continue
			decalages.append(Vector2i(dx, dz))
	decalages.sort_custom(func(a, b): return (a.x * a.x + a.y * a.y) < (b.x * b.x + b.y * b.y))
	return decalages.slice(0, nombre)

# ---- Le ramassage ----

func _juger_le_ramassage() -> void:
	var type: Dictionary = _types[ESPECE_HAUTE]
	var etat := Vegetation.etat_initial(
		[{"id": "sujet", "colonne": COLONNE_BASSE, "type": ESPECE_HAUTE}], _releve, _config, _types)

	var temps := 0.0
	var produit_id := ""
	while temps < float(type.longevite) and produit_id == "":
		var rapport := Vegetation.avancer(etat, _config, _types, _releve, PAS)
		temps = float(rapport.temps)
		if not rapport.produits.is_empty():
			produit_id = String(rapport.produits[0].id)

	_v.v(produit_id != "", "aucun produit en une vie : rien a ramasser")
	if produit_id == "":
		return

	var avant := (etat.graines as Array).size()
	var rendu := Vegetation.ramasser(etat, produit_id, _config)
	_v.v(String(rendu.get("ressource", "")) == String(type.ressource),
		"le ramassage rend '%s', attendu '%s'" % [rendu.get("ressource", ""), type.ressource])
	_v.v((etat.graines as Array).size() == avant - 1, "le produit ramasse est encore la")
	_v.v(_par_id(etat.plantes, "sujet") != null, "la plante a disparu quand on a ramasse son produit")
	_v.v(Vegetation.ramasser(etat, produit_id, _config).is_empty(),
		"ramasser deux fois rend quelque chose : la ressource se cree a partir de rien")
	print("ramassage : '%s' rendu, la plante tient toujours" % type.ressource)

# ---- La reproductibilite ----

func _juger_la_reproductibilite() -> void:
	var premiere := _signature_de_partie()
	var seconde := _signature_de_partie()
	_v.v(premiere == seconde,
		"deux parties de meme graine divergent :\n  %s\n  %s" % [
			premiere.substr(0, 250), seconde.substr(0, 250)])
	_v.v(premiere != "", "la signature de partie est vide")

func _signature_de_partie() -> String:
	var etat := _partie_des_deux_especes()
	var morceaux: PackedStringArray = []
	var temps := 0.0
	while temps < 400.0:
		var rapport := Vegetation.avancer(etat, _config, _types, _releve, PAS)
		temps = float(rapport.temps)
		for n in rapport.naissances:
			morceaux.append("%.0f:n:%s:%s" % [temps, n.id, n.type])
		for p in rapport.produits:
			morceaux.append("%.0f:p:%s" % [temps, p.id])
		for id in rapport.morts:
			morceaux.append("%.0f:m:%s" % [temps, id])
	return "|".join(morceaux)

func _partie_des_deux_especes() -> Dictionary:
	return Vegetation.etat_initial([
		{"id": "souche_haute", "colonne": COLONNE_BASSE, "type": ESPECE_HAUTE},
		{"id": "souche_basse", "colonne": COLONNE_LOIN, "type": ESPECE_BASSE},
	], _releve, _config, _types)

# ---- L'OMBRE PAR SIGNAL ----

# L'OMBRE STOCKEE DOIT VALOIR L'OMBRE RECALCULEE, A CHAQUE TICK ET SUR CHAQUE
# PLANTE. C'est le seul verrou qui rend le stockage sur.
#
# Une valeur gardee en memoire qui rate une mise a jour laisse une plante gelee a
# tort -- ou poussant a tort -- ET RIEN NE LE SIGNALE : la foret reste plausible,
# les comptes restent ronds, le defaut dort. Aucun raisonnement ne protege de ca,
# seule une comparaison le fait.
#
# LA COMPARAISON EST TOTALE, jamais un echantillon : chaque plante, chaque tick.
# C'est cher, et c'est pour ca qu'elle vit dans le test et nulle part ailleurs --
# le jeu, lui, ne recalcule jamais tout.
func _juger_l_ombre_par_signal() -> void:
	var etat := Vegetation.etat_initial([
		{"id": "a1", "colonne": COLONNE_BASSE, "type": ESPECE_HAUTE},
		{"id": "a2", "colonne": COLONNE_BASSE + Vector2i(4, 0), "type": ESPECE_HAUTE},
		{"id": "h1", "colonne": COLONNE_BASSE + Vector2i(1, 1), "type": ESPECE_BASSE},
		{"id": "h2", "colonne": COLONNE_LOIN, "type": ESPECE_BASSE},
	], _releve, _config, _types)

	var divergences := 0
	var premiere := ""
	var ticks := 0
	var jamais_ombragee := true
	var relues := 0
	var temps := 0.0
	while temps < 400.0:
		var rapport := Vegetation.avancer(etat, _config, _types, _releve, 2.0)
		temps = float(rapport.temps)
		ticks += 1
		relues += int(rapport.ombres_relues)

		var vivantes := Vegetation.vivantes(etat.plantes, _config)
		var verite := Vegetation.ombres(vivantes, etat.monde, _config, _releve)
		var rayon := Surface.metres_par_cellules(float(_config.rayon_voisinage_cellules), _releve)
		for plante in vivantes:
			var vraie: bool = verite[String(plante.id)]
			if vraie:
				jamais_ombragee = false
			if bool(plante.proprietes.get("ombragee", false)) != vraie:
				divergences += 1
				if premiere == "":
					premiere = "t=%.0f s, '%s' porte l'ombre %s alors que le calcul dit %s" % [
						temps, plante.id, plante.proprietes.get("ombragee", false), vraie]
			# LE COMPTE DE VOISINS EST PORTE COMME L'OMBRE, et se verifie pareil :
			# un compte perime laisse une plante se reproduire dans une foule, ou
			# refuser de pousser dans le vide -- sans que rien ne le signale.
			var compte := Vegetation.voisinage(plante.position, etat.monde, rayon)
			if int(plante.proprietes.get("voisins", -1)) != compte:
				divergences += 1
				if premiere == "":
					premiere = "t=%.0f s, '%s' porte %s voisins alors que le calcul en trouve %d" % [
						temps, plante.id, plante.proprietes.get("voisins", -1), compte]

	_v.v(divergences == 0,
		"%d divergence(s) entre ce que les plantes portent et le calcul complet -- premiere : %s" % [
			divergences, premiere])

	# UNE PARTIE OU PERSONNE N'EST JAMAIS A L'OMBRE ne prouverait rien : les deux
	# calculs seraient d'accord sur « false » partout.
	_v.v(not jamais_ombragee,
		"aucune plante n'a jamais ete a l'ombre : la comparaison ne prouve rien")

	# ET LE GAIN EST REEL : on relit une poignee d'ombres par tick, pas toute la
	# carte. Sans ce controle, un rafraichissement qui relirait tout passerait le
	# test d'exactitude sans rien economiser.
	var par_tick := float(relues) / float(maxi(ticks, 1))
	var population := Vegetation.vivantes(etat.plantes, _config).size()
	_v.v(par_tick < float(population) * 0.5,
		"%.1f ombres relues par tick pour %d plantes : le signal relit presque tout" % [
			par_tick, population])
	print("ombre par signal : %d divergence(s) sur %d ticks, %.1f ombre(s) relue(s) par tick pour %d plantes" % [
		divergences, ticks, par_tick, population])

# ---- LE PAS DE TEMPS ----

# UN GROS PAS DOIT RENDRE LA MEME SIMULATION QU'UN PETIT, et c'est le verrou qui
# manquait. Le precedent comparait N + M ticks a N+M ticks -- les trois avec le
# MEME pas. Il prouvait une tautologie : accelerer n'etait jamais teste.
#
# CE QU'IL CACHAIT, mesure ensuite : tous les seuils sont franchis EN RETARD D'UN
# PAS. Une herbe qui vit 100 s mourait a 120 avec un pas de 30 -- 20 % de vie en
# plus, a chaque generation, et ca compose. Sur 600 s simulees, un pas de 30
# rendait TROIS FOIS plus d'herbe qu'un pas de 1, et sautait entierement son
# premier stade. Le prechauffage ne montrait donc pas la simulation lente jouee
# vite : il en montrait une autre.
func _juger_le_pas_de_temps() -> void:
	var pas_max := Vegetation.pas_maximal(_types, _config)
	_v.v(pas_max > 0.0, "aucun pas maximal deduit des especes : le decoupage ne protege rien")

	# La plus courte duree en jeu doit vraiment borner le pas, sinon ce jugement
	# ne verifie rien.
	var plus_courte := INF
	for nom in _types:
		for stade in ((_types[nom] as Dictionary).stades as Array):
			plus_courte = minf(plus_courte, float(stade.duree))
	_v.v(pas_max < plus_courte,
		"le pas maximal (%.2f) atteint la plus courte duree en jeu (%.2f)" % [pas_max, plus_courte])

	# (1) AUCUN STADE SAUTE, meme avec un pas plus grand qu'un stade entier. Verif
	# deterministe : une plante seule, suivie stade par stade.
	var enorme := plus_courte * 2.0
	var type: Dictionary = _types[ESPECE_BASSE]
	var etat := Vegetation.etat_initial(
		[{"id": "sujet", "colonne": COLONNE_BASSE, "type": ESPECE_BASSE}], _releve, _config, _types)
	var vus: Array = [String((etat.plantes[0] as Dictionary).proprietes.stade)]
	var temps := 0.0
	while temps < float(type.longevite):
		var rapport := Vegetation.avancer_par_tranches(
			etat, _config, _types, _releve, enorme, pas_max)
		temps = float(rapport.temps)
		for changement in rapport.changements:
			if String(changement.id) == "sujet":
				vus.append(String(changement.stade))
	var attendus: Array = []
	for stade in (type.stades as Array):
		attendus.append(String(stade.nom))
	_v.v(vus == attendus,
		"avec un pas de %.0f s, '%s' traverse %s au lieu de %s : un stade est saute" % [
			enorme, ESPECE_BASSE, vus, attendus])

	# (2) LES POPULATIONS RESTENT COMPARABLES. Bornes larges a dessein : deux pas
	# differents consomment le tirage dans un autre ordre, la dispersion est
	# normale. Ce qui ne l'est pas, c'est un facteur trois.
	var fine := _population_apres(1.0, pas_max)
	var grosse := _population_apres(enorme, pas_max)
	_v.v(fine > 0 and grosse > 0,
		"une des deux parties ne laisse personne : la comparaison ne prouverait rien")
	if fine > 0 and grosse > 0:
		var ecart := float(grosse) / float(fine)
		_v.v(ecart > 0.5 and ecart < 2.0,
			"a pas fin %d vivantes, a pas de %.0f s %d vivantes (facteur %.2f) : les deux pas ne jouent pas la meme simulation" % [
				fine, enorme, grosse, ecart])
		print("pas de temps : %d vivantes a pas fin, %d a pas de %.0f s (facteur %.2f), pas maximal %.2f s" % [
			fine, grosse, enorme, ecart, pas_max])

func _population_apres(pas: float, pas_max: float) -> int:
	var etat := Vegetation.etat_initial([
		{"id": "a", "colonne": COLONNE_BASSE, "type": ESPECE_HAUTE},
		{"id": "h", "colonne": COLONNE_LOIN, "type": ESPECE_BASSE},
	], _releve, _config, _types)
	var temps := 0.0
	while temps < 400.0:
		var rapport := Vegetation.avancer_par_tranches(etat, _config, _types, _releve, pas, pas_max)
		temps = float(rapport.temps)
	return Vegetation.vivantes(etat.plantes, _config).size()

# ---- Le prechauffage ----

# N TICKS D'AVANCE PLUS M NORMAUX DOIVENT RENDRE LE MEME ETAT QUE N+M NORMAUX.
# Ce que ce jugement prouve vraiment : que _process ne fait AUCUN travail de
# simulation. Comparer avancer() a lui-meme ne prouverait rien -- ce test monte
# donc un VRAI noeud Couvert et le laisse faire son _ready.
func _juger_le_prechauffage() -> void:
	var avance := 200
	var apres := 100

	var grille := _construire_terrain()
	var couvert = Couvert.new()
	_v.v(couvert != null, "couvert.gd n'a pas pu etre instancie : le prechauffage n'est pas verifie")
	if couvert == null:
		grille.free()
		return
	couvert.name = "Couvert"
	couvert.ticks_prechauffage = avance
	couvert.delta_prechauffage = PAS
	# LES ESPECES SE DECLARENT SUR LE NOEUD, comme dans l'editeur : sans elles le
	# couvert ne charge rien, et c'est deliberement une alarme.
	couvert.add_child(_espece_haute())
	couvert.add_child(_espece_basse())
	grille.add_child(couvert)

	var colonnes: Array = [COLONNE_BASSE, COLONNE_LOIN]
	var especes: Array = [ESPECE_HAUTE, ESPECE_BASSE]
	for i in range(colonnes.size()):
		var noeud := PlanteScene.instantiate() as Node3D
		noeud.name = "semis_%d" % i
		noeud.type = especes[i]
		noeud.position = Surface.position_posee(colonnes[i], _releve)
		couvert.add_child(noeud)

	# _ready EST APPELE A LA MAIN : ce test tourne dans _init, ou la racine du
	# SceneTree n'est pas encore demarree -- un noeud qu'on y attache n'entre pas
	# dans l'arbre et son _ready ne part jamais. La fonction appelee est la VRAIE ;
	# seule l'appartenance a l'arbre manque, et _ready ne s'en sert pas.
	couvert._ready()

	var config: Dictionary = couvert.get("_config")
	var types: Dictionary = couvert.get("_types")
	var releve: Dictionary = couvert.get("_releve")
	var etat_chauffe: Dictionary = couvert.get("_etat")
	_v.v(not etat_chauffe.is_empty(), "le couvert n'a pas d'etat apres son _ready")
	if etat_chauffe.is_empty():
		grille.free()
		return

	for _i in range(apres):
		Vegetation.avancer(etat_chauffe, config, types, releve, PAS)

	var semis: Array = []
	for i in range(colonnes.size()):
		semis.append({"id": "semis_%d" % i, "colonne": colonnes[i], "type": especes[i]})
	var etat_droit := Vegetation.etat_initial(semis, releve, config, types)
	for _i in range(avance + apres):
		Vegetation.avancer(etat_droit, config, types, releve, PAS)

	_v.v(Vegetation.vivantes(etat_droit.plantes, config).size() > 1,
		"la partie de reference ne laisse qu'une plante : la comparaison ne prouverait rien")
	_v.v(_signature_etat(etat_chauffe, config, types) == _signature_etat(etat_droit, config, types),
		"%d ticks d'avance puis %d normaux divergent de %d ticks joues d'un trait" % [
			avance, apres, avance + apres])
	print("prechauffage : %d + %d ticks == %d ticks, %d vivante(s)" % [
		avance, apres, avance + apres, Vegetation.vivantes(etat_chauffe.plantes, config).size()])
	grille.free()

func _signature_etat(etat: Dictionary, config: Dictionary, types: Dictionary) -> String:
	var morceaux: PackedStringArray = []
	for plante in Vegetation.vivantes(etat.plantes, config):
		morceaux.append("p:%s@%d,%d:%d" % [
			plante.id, (plante.colonne as Vector2i).x, (plante.colonne as Vector2i).y,
			Vegetation.numero_de_stade(plante, Vegetation.type_de(plante, types))])
	for graine in etat.graines:
		morceaux.append("g:%s@%d,%d" % [
			graine.id, (graine.colonne as Vector2i).x, (graine.colonne as Vector2i).y])
	morceaux.sort()
	return "|".join(morceaux)

# ---- La touffe procedurale ----

# UNE ESPECE SANS MODELE RECOIT UNE TOUFFE, et elle doit reposer au sol a la
# hauteur demandee -- sinon l'herbe flotte ou s'enfonce, ce qu'aucun test de
# simulation ne verrait.
func _juger_la_touffe() -> void:
	var basse: Dictionary = _types[ESPECE_BASSE]
	# AUCUN CHEMIN DECLARE, chaine vide comprise : c'est le vide qui declenche la
	# touffe. Une ressource rend toujours autant d'entrees que de stades, remplies
	# de chaines vides -- verifier la taille du tableau ne dirait rien.
	var declare := false
	for chemin in (basse.modeles_stades as Array):
		if String(chemin) != "":
			declare = true
	_v.v(not declare,
		"'%s' declare un modele : la touffe procedurale n'est plus exercee" % ESPECE_BASSE)

	var hauteur := float((basse.stades as Array)[0].stature)
	var largeur := float(_config.largeur_touffe)
	var maillage := Couvert.maillage_touffe(hauteur, largeur, int(_config.brins_touffe), basse.couleur)
	_v.v(maillage != null, "la touffe n'a pas ete fabriquee")
	if maillage == null:
		return

	var b := maillage.get_aabb()
	_v.v(absf(b.position.y) < 0.01,
		"la touffe a sa base a y = %.3f : elle flotte ou s'enfonce" % b.position.y)
	_v.v(is_equal_approx(b.size.y, hauteur),
		"la touffe fait %.3f de haut, attendu %.3f" % [b.size.y, hauteur])
	_v.v(b.size.x <= largeur + 0.01 and b.size.z <= largeur + 0.01,
		"la touffe fait %s de large, attendu au plus %.2f" % [b.size, largeur])

	var materiau := maillage.surface_get_material(0) as StandardMaterial3D
	_v.v(materiau != null, "la touffe n'a aucun materiau : elle sera blanche")
	if materiau != null:
		_v.v(materiau.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"la touffe n'est pas rendue des deux cotes : la moitie des brins disparaitra selon l'angle")

	# ET L'ARBRE, LUI, A DE VRAIS MODELES QUI SE CHARGENT.
	var haute: Dictionary = _types[ESPECE_HAUTE]
	for chemin in (haute.modeles_stades as Array):
		_v.v(ResourceLoader.exists(String(chemin)),
			"le modele '%s' n'existe pas : ce qui l'utilise restera invisible" % chemin)
	print("touffe : %.2f de haut, %d brins, deux faces ; '%s' garde ses %d modele(s)" % [
		b.size.y, int(_config.brins_touffe), ESPECE_HAUTE, (haute.modeles_stades as Array).size()])

# ---- Le verrou contre la divergence ----

# ---- Le tronc ----

# LE CORPS SOLIDE SUIT LE STADE ET N'EXISTE QUE SI L'ESPECE LE DECLARE. Le test
# porte sur la fabrique statique (jeu/plantes/couvert.gd:forme_de_tronc), donc
# sans arbre de scene ni moteur physique : c'est une geometrie, elle se mesure.
func _juger_le_tronc() -> void:
	var haute: Dictionary = _types[ESPECE_HAUTE]
	var stades: Array = haute.stades

	# A RAYON NUL, RIEN. C'est le defaut, et c'est ce qui laisse l'herbe
	# traversable sans qu'une ligne de code ne nomme l'herbe.
	_v.v(Couvert.forme_de_tronc(0.0, 7.5) == null,
		"un rayon nul fabrique quand meme un tronc : l'herbe barrerait le passage")
	_v.v(Couvert.forme_de_tronc(0.4, 0.0) == null,
		"une stature nulle fabrique quand meme un tronc")

	# LA HAUTEUR EST CELLE DU STADE, donc elle CHANGE avec lui : une pousse ne
	# barre pas le passage comme un arbre mature. Un tronc de hauteur fixe
	# passerait tous les autres jugements sans que rien ne rougisse.
	var hauteurs: Array = []
	for stade in stades:
		var forme: CylinderShape3D = Couvert.forme_de_tronc(0.4, float(stade.stature))
		_v.v(forme != null, "le stade '%s' n'a pas de tronc alors que son rayon est pose" % stade.nom)
		if forme == null:
			continue
		_v.v(is_equal_approx(forme.radius, 0.4),
			"le tronc du stade '%s' a un rayon de %.2f au lieu de 0.40" % [stade.nom, forme.radius])
		_v.v(is_equal_approx(forme.height, float(stade.stature)),
			"le tronc du stade '%s' est haut de %.2f pour une stature de %.2f" % [
				stade.nom, forme.height, float(stade.stature)])
		hauteurs.append(forme.height)

	_v.v(hauteurs.size() >= 2 and hauteurs.max() > hauteurs.min(),
		"tous les stades ont un tronc de la meme hauteur : il ne suit pas la croissance")
	print("tronc : rayon 0.40, hauteurs %s -- une par stade, l'herbe n'en a aucun" % [hauteurs])

func _juger_les_reglages() -> void:
	var noeud = Couvert.new()
	_v.v(noeud != null, "couvert.gd n'a pas pu etre instancie : les reglages ne sont pas verifies")
	if noeud == null:
		return
	var defauts: Dictionary = noeud.reglages()

	for cle in defauts:
		_v.v(_meme_valeur(defauts[cle], _config.get(cle)),
			"'%s' vaut %s a l'inspecteur et %s dans le fichier" % [cle, defauts[cle], _config.get(cle)])

	var autres: Dictionary = defauts.duplicate(true)
	autres["rayon_voisinage_cellules"] = 13
	autres["rayon_trouee_cellules"] = 9
	var surchargee: Dictionary = Couvert.appliquer_reglages(_config, autres)
	_v.v(int(surchargee.rayon_voisinage_cellules) == 13, "la surcharge du rayon de voisinage ne prend pas")
	_v.v(int(surchargee.rayon_trouee_cellules) == 9, "la surcharge du rayon de trouee ne prend pas")
	_v.v(int(_config.rayon_voisinage_cellules) != 13,
		"appliquer_reglages a mute la config d'origine")

	# CE QUI EST DESCENDU A L'ESPECE NE DOIT PAS DIVERGER DE SON DEFAUT DE FICHIER.
	# Meme doctrine que pour le noeud Couvert juste au-dessus : le fichier reste la
	# source pour tout ce qui tourne sans noeud, un noeud d'espece neuf doit le
	# rejouer a l'identique.
	var neuve = EspeceScript.new()
	for paire in [
		["rayon_dispersion_min", "rayon_min_cellules"],
		["rayon_dispersion_max", "rayon_max_cellules"],
		["max_voisins", "max_voisins"],
	]:
		_v.v(int(neuve.get(String(paire[0]))) == int(_config.get(String(paire[1]))),
			"'%s' vaut %s sur une espece neuve et %s dans le fichier ('%s')" % [
				paire[0], neuve.get(String(paire[0])), _config.get(String(paire[1])), paire[1]])
	neuve.free()

	# LA LONGEVITE SUIT LA TABLE, jamais un champ pose a cote : elle doit valoir la
	# somme des durees declarees, et rien d'autre.
	for nom in _types:
		var type: Dictionary = _types[nom]
		var somme := 0.0
		for stade in (type.stades as Array):
			somme += float(stade.duree)
		_v.v(is_equal_approx(float(type.longevite), somme),
			"'%s' vit %s alors que ses stades somment a %s" % [nom, type.longevite, somme])
	noeud.free()

# EGALITE DE VALEUR, JAMAIS DE TEXTE : JSON ne connait qu'un type de nombre, un
# entier ecrit 2 revient en 2.0. Les comparer en texte ferait rougir ce verrou sur
# des valeurs pourtant identiques -- et un verrou qui crie a tort n'est plus lu.
func _meme_valeur(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b)

# LES DEUX ESPECES D'ESSAI, montees a la main. Les valeurs sont ecrites ICI et
# nulle part ailleurs : ce test ne lit pas la scene du jeu, dont le contenu change
# au gre du game designer. Ce qu'il verrouille est le MECANISME -- qu'une stature
# basse se fasse ombrager, qu'une trouee exigeante refuse un tapis -- jamais la
# calibration du jour.
func _espece_haute() -> Node:
	var espece := EspeceScript.new()
	espece.nom = ESPECE_HAUTE
	espece.nom_stade_1 = "pousse"; espece.duree_stade_1 = 180.0; espece.stature_stade_1 = 2.0
	espece.nom_stade_2 = "mature"; espece.duree_stade_2 = 240.0; espece.stature_stade_2 = 7.5
	espece.nom_stade_3 = "epuise"; espece.duree_stade_3 = 180.0; espece.stature_stade_3 = 5.0
	espece.modele_stade_1 = "res://jeu/plantes/jeune pousse.glb"
	espece.modele_stade_2 = "res://jeu/plantes/mature.glb"
	espece.modele_stade_3 = "res://jeu/plantes/epuisé.glb"
	espece.modele_produit = "res://jeu/plantes/seve.glb"
	espece.marge_couches = 2
	espece.trouee_max_voisins = 1
	espece.rayon_dispersion_min = 3; espece.rayon_dispersion_max = 5
	espece.max_voisins = 6
	espece.stade_reproduction_min = 2; espece.stade_reproduction_max = 2
	espece.intervalle_reproduction = 240.0
	espece.stade_production_min = 2; espece.intervalle_production = 120.0
	espece.max_produits_par_plante = 3; espece.ralentissement_dernier_stade = 2.0
	espece.duree_vie_produit = 300.0; espece.ressource = "graine"
	return espece

func _espece_basse() -> Node:
	var espece := EspeceScript.new()
	espece.nom = ESPECE_BASSE
	espece.nom_stade_1 = "brin"; espece.duree_stade_1 = 25.0; espece.stature_stade_1 = 0.4
	espece.nom_stade_2 = "touffe"; espece.duree_stade_2 = 35.0; espece.stature_stade_2 = 0.8
	espece.nom_stade_3 = "montee"; espece.duree_stade_3 = 40.0; espece.stature_stade_3 = 1.0
	espece.marge_couches = 6
	espece.trouee_max_voisins = 8
	espece.rayon_dispersion_min = 1; espece.rayon_dispersion_max = 2
	espece.max_voisins = 14
	espece.stade_reproduction_min = 2; espece.stade_reproduction_max = 3
	espece.intervalle_reproduction = 30.0
	espece.stade_production_min = 99
	espece.max_produits_par_plante = 0; espece.ralentissement_dernier_stade = 1.0
	espece.duree_vie_produit = 60.0; espece.ressource = "herbe"
	return espece

func _par_id(choses: Array, id: String) -> Variant:
	for chose in choses:
		if String(chose.id) == id:
			return chose
	return null

func _conclure() -> void:
	if _v.echecs() > 0:
		print("ECHEC: le couvert vegetal ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: plantes -- deux especes, stades et statures declarees, plafond de couche par espece, ombre par stature qui fige les dominees et les libere a la coupe, trouee qui refuse le semis d'arbre dans le tapis d'herbe, densite bornee, production et ramassage, prechauffage equivalent au temps vecu, tirage seede reproductible, touffe procedurale posee au sol, inspecteur et fichier d'accord")
	quit(0)
