extends RigidBody3D

# BANC "test_ennemi2 Mother box" -- LE GENITEUR. Machine 6x6x6 (3 cases
# GridMap) qui tombe du ciel, extrait la ressource des 9 cases marrons
# sous son emprise, et se DEPLACE au sol vers une nouvelle zone marron
# quand la sienne est epuisee. Meme pattern de deplacement horizontal
# que soldat.gd (avance sur X/Z, la gravite maintient au sol).
#
# COMPORTEMENT :
#  A. Extraction locale : un raycast central trouve la cellule sous le
#     geniteur ; les 9 cellules autour (3x3) sont prelevees a chaque
#     tick, `quantite_par_case` unites chacune.
#  B. Detection : `chercher_cases_marrons()` interroge RessourcesTerrain
#     pour lister les cases marrons dans `rayon_detection`, triees par
#     distance croissante.
#  C. Deplacement : quand le tick d'extraction n'a rien pris (toutes les
#     cases sous lui sont a zero), le geniteur cherche la case marron la
#     plus proche AYANT du stock et se met a `_cible_deplacement`. Dans
#     `_process`, il avance en LIGNE DROITE horizontale a `vitesse_sol`
#     m/s. La gravite du RigidBody3D le maintient au sol pendant le
#     deplacement -- pas de vol, pas de teleportation.
#
# FEEDBACK VISUEL : un decal PlaneMesh 6x6 sous le geniteur (nœud
# ZoneExtraction) montre visuellement les 9 cellules d'emprise. VERT
# quand extraction en cours, ROUGE quand rien a pris (signal "je vais
# bouger"). Materiau `no_depth_test = true` pour s'afficher par-dessus
# la Base opaque.

# DEUX STOCKS SEPARES :
# - PERSO (150) : sert au geniteur pour ses propres gestations
#   (generateur 20, mother cube 100). Rempli par extraction 50 %.
# - ACCESSIBLE (150) : sert aux generateurs enroles qui viennent puiser
#   (cout_prelevement 10 par cycle). Rempli par extraction 50 %. Quand
#   PERSO est plein, l'autre 50 % va integralement dans ACCESSIBLE.
# Total 300 = capacite historique. Les deux barres visibles au-dessus
# du geniteur : violette = privee, bleue = public.
@export var capacite_privee: int = 150
@export var capacite_public: int = 150
@export var intervalle_extraction: float = 3.0
@export var quantite_par_case: int = 1
@export var rayon_detection: float = 30.0
@export var nom_ressource_cible: String = "bloc"
@export var vitesse_sol: float = 3.0

const COULEUR_ACTIVE := Color(0.2, 0.9, 0.25, 0.35)
const COULEUR_EMISSION_ACTIVE := Color(0.2, 0.9, 0.25, 1.0)
const COULEUR_VIDE := Color(0.9, 0.15, 0.15, 0.4)
const COULEUR_EMISSION_VIDE := Color(0.9, 0.15, 0.15, 1.0)
# DELAI ROUGE AVANT DEPLACEMENT : le decal reste rouge pendant N ticks
# consecutifs sans extraction avant que le geniteur ne se mette en marche.
# Sans ce delai, le rouge apparait 1 frame puis disparait.
const TICKS_ROUGE_AVANT_DEPART := 2
# CONTACT AU SOL : le raycast d'extraction part du centre du geniteur
# (RigidBody3D 6x6x6, collider ShapeGeniteur centre en (0,0,0)). En position
# posee, la face basse du collider est a y_local = -3, donc
# frappe.position.y attendu ~= global_position.y - 3.0. Ecart plus grand =
# geniteur encore en l'air (chute apres spawn, saut physique) : pas
# d'extraction tant qu'il n'est pas pose, sinon il preleve les cases 20 m
# plus bas pendant qu'il tombe du ciel. RESULTAT NEGATIF a ne pas
# reproduire : tester linear_velocity.y (voir commentaire dans
# _tenter_extraction) echoue -- un RigidBody3D pose garde ~-2.7 m/s
# residuel. Le check geometrique n'a pas ce faux positif.
# Seuil = hauteur base (3.0) + tolerance physique (0.5, alignee sur le
# seuil "arrete" de test_collision_terrain.gd:264).
const HAUTEUR_MAX_AU_SOL := 3.5
# DISTANCE MIN CIBLE : quand _choisir_cible pique la plus proche case marron
# avec stock, sans ce filtre elle peut tomber a moins de 1 m -- _avancer_vers_cible
# declare "arrive" immediatement (vers.length() <= 1.0), le geniteur ne
# bouge pas, l'extraction retente sur la meme emprise 3x3 deja videe,
# _ticks_vides remonte, meme case rechoisie : BOUCLE INFINIE SILENCIEUSE.
# Observee le 2026-08-22 apres 4 pontes de generateurs (Yael, decal ROUGE
# fige). Le seuil 4.0 m garantit un deplacement horizontal reel.
const DISTANCE_MIN_CIBLE := 4.0
# PORTEE VERTICALE : ressources_terrain.cellules_par_nom_dans_rayon scan
# TOUTES les cellules avec profil, y compris les couches empilees en Y.
# Sans ce filtre, une case marron 5 m sous le sol est candidate valide,
# le geniteur essaie d'y aller (physique le bloque au sol) et retente en
# boucle. Seuil 5 m : le geniteur est POSE a Y_sol + 3 (hauteur base),
# le centre de la cellule sol est a Y_sol - ~1 (cellule 2 m centree),
# ecart naturel = 4 m. Un seuil 3 m rejetterait TOUT le sol public
# (regression observee le 2026-08-22 : 4229 cases mais 0 valides). 5 m
# tolere le sol immediat et rejette les couches empilees ~7 m plus bas.
const ECART_VERTICAL_MAX_CIBLE := 5.0

var _stock_privee: float = 0.0
var _stock_public: float = 0.0
var _ressources: Node = null
var _timer: Timer
var _ticks_vides: int = 0
# _cible_deplacement : null = immobile, Vector3 = position monde a atteindre.
var _cible_deplacement: Variant = null
# _grille_connue : derniere GridMap detectee sous le geniteur. Memorisee pour
# pouvoir choisir une nouvelle cible meme quand le raycast rate (geniteur
# sorti de la carte, ou passe au-dessus d'un trou) -- sinon les returns
# silencieux de _tenter_extraction laisseraient le geniteur bloque sans
# jamais rappeler _choisir_cible.
var _grille_connue: GridMap = null
# _cellule_centre_courante : Vector3i de la cellule sous le raycast central
# au dernier tick d'extraction reussi. Sert a _choisir_cible pour EXCLURE
# les 9 cases de l'emprise 3x3 actuelle (deja pillees) des candidates
# suivantes. Sans cette exclusion, _choisir_cible pique une case du 3x3
# actuel (elle est la plus proche par definition), _avancer_vers_cible
# declare arrive immediat, geniteur ne bouge pas : boucle silencieuse.
# null tant qu'aucun tick d'extraction n'a reussi.
var _cellule_centre_courante: Variant = null
# ENTITE MONDE : le geniteur est inscrit au monde partage pour etre percu
# comme SOURCE DE MATIERE par les generateurs enroles. Propriete
# "stock_puisable" reflete _stock_public (les gestations paient sur
# privee, mais les enroles puisent uniquement dans l'public). Mise a
# jour a chaque changement (extraction et preleve).
var entite: Dictionary = {}
var _monde_partage: Node = null
@onready var _zone: MeshInstance3D = $ZoneExtraction
var _zone_material: StandardMaterial3D
@onready var _barre_stock: MeshInstance3D = $BarreDeStock/Barre
var _materiau_stock: ShaderMaterial
# Nouvelle barre : stock ACCESSIBLE (violette). Node facultatif ; si le
# noeud n'existe pas dans la scene chargee, on ne l'affiche pas (garde
# compatibilite avec anciennes scenes qui n'ont pas encore ete regenerees).
@onready var _barre_stock_public: MeshInstance3D = $BarreDeStockPublic/Barre if has_node("BarreDeStockPublic/Barre") else null
var _materiau_stock_public: ShaderMaterial

func _ready() -> void:
	add_to_group("geniteur")
	_ressources = get_tree().get_first_node_in_group("ressources_terrain")
	if _ressources == null:
		push_warning("geniteur.gd : RessourcesTerrain absent, extraction desactivee")
	# DUPLIQUE materiaux (decal + barre) pour ne pas partager entre plusieurs
	# geniteurs -- teindre l'un ne teint pas les autres.
	_zone_material = _zone.mesh.surface_get_material(0).duplicate()
	_zone.set_surface_override_material(0, _zone_material)
	_materiau_stock = _barre_stock.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre_stock.set_surface_override_material(0, _materiau_stock)
	_materiau_stock.set_shader_parameter("fraction", 0.0)
	# BARRE ACCESSIBLE (violette) : optionnelle dans les vieilles scenes.
	if _barre_stock_public != null:
		_materiau_stock_public = _barre_stock_public.mesh.surface_get_material(0).duplicate() as ShaderMaterial
		_barre_stock_public.set_surface_override_material(0, _materiau_stock_public)
		_materiau_stock_public.set_shader_parameter("fraction", 0.0)
	_teindre_zone(true)

	_timer = Timer.new()
	_timer.wait_time = intervalle_extraction
	_timer.one_shot = false
	_timer.autostart = true
	_timer.timeout.connect(_tenter_extraction)
	add_child(_timer)

	# INSCRIPTION AU MONDE PARTAGE : le geniteur devient SOURCE percevable
	# par les generateurs enroles. Propriete "stock_puisable" = ce qu'un
	# generateur peut effectivement puiser (= _stock_public). Sans
	# cette inscription, un generateur ne pourrait pas le trouver via
	# Perception.percevoir (interdit de get_nodes_in_group + distance).
	# Meme patron carre_rouge.gd:_ready.
	entite = {
		"id": str(get_instance_id()),
		"position": global_position,
		"proprietes": {
			"stock_puisable": _stock_public,
		},
		"noeud": self,
	}
	_monde_partage = get_tree().get_first_node_in_group("monde_partage")
	if _monde_partage != null:
		_monde_partage.monde.ajouter(entite, "geniteur", global_position)

# B11 : si le geniteur est un jour queue_free (mecanisme de mort a
# ajouter plus tard), retirer son entree du monde partage sinon les
# generateurs enroles la percoivent comme un fantome perceptible ad
# aeternam. NOTIFICATION_PREDELETE est appelee juste avant la destruction.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _monde_partage != null and not entite.is_empty():
			_monde_partage.monde.retirer(entite.id)

func _process(delta: float) -> void:
	_avancer_vers_cible(delta)
	# SYNCHRO POSITION MONDE : le geniteur bouge, entite.position doit
	# refleter la position vivante pour que les generateurs percoivent la
	# bonne distance. Meme patron transporteur.gd:156.
	# monde.gd:deplacer() est REQUIS : l'indexation spatiale (par case /
	# exposant) doit etre reajustee, sinon la chose reste trouvable a son
	# ANCIENNE case et invisible a la nouvelle (voir monde.gd:148-150).
	# Sans cet appel, les generateurs enroles percoivent le geniteur a
	# son ancienne position et marchent dans le vide.
	if not entite.is_empty():
		entite["position"] = global_position
		if _monde_partage != null:
			_monde_partage.monde.deplacer(entite)

# Deplacement horizontal a vitesse constante vers _cible_deplacement.
# Applique une velocite horizontale au RigidBody, la gravite gere Y.
# Meme pattern que soldat.gd:_faire_vers_joueur.
func _avancer_vers_cible(_delta: float) -> void:
	if _cible_deplacement == null:
		# Immobile : stopper toute derive horizontale residuelle.
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		return
	var vers: Vector3 = _cible_deplacement - global_position
	vers.y = 0.0
	if vers.length() <= 1.0:
		# Arrive.
		_cible_deplacement = null
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		return
	var direction := vers.normalized()
	linear_velocity = Vector3(direction.x * vitesse_sol, linear_velocity.y, direction.z * vitesse_sol)

func _tenter_extraction() -> void:
	if _ressources == null:
		return
	# EN MOUVEMENT VOLONTAIRE vers une cible : pas d'extraction. Pas de
	# check de linear_velocity : un RigidBody3D pose garde une velocite
	# residuelle (~-2.7 m/s en Y) due au contact continu avec le sol qui
	# annule la gravite. Tester la velocity bloquait definitivement
	# l'extraction (mesure : _ticks_vides restait a 0 apres vidage).
	if _cible_deplacement != null:
		return
	var espace := get_world_3d().direct_space_state
	if espace == null:
		return
	# UN SEUL raycast central pour trouver la cellule sous le geniteur,
	# puis extraction des 9 cellules autour dans la grille. Independant
	# de l'alignement du geniteur sur la grille (voir memoire :
	# alignement objet, pas grille).
	var pt := global_position
	var arrivee := pt + Vector3(0, -100.0, 0)
	var requete := PhysicsRayQueryParameters3D.create(pt, arrivee)
	requete.exclude = [get_rid()]
	var frappe: Dictionary = espace.intersect_ray(requete)
	if frappe.is_empty():
		# Rien sous le geniteur (bord de carte, trou) : compter comme tick
		# vide pour qu'apres N ticks _choisir_cible relance la marche vers
		# une case marron connue. Sans ce comptage, le geniteur qui sort de
		# la GridMap reste bloque sans jamais reappeler _choisir_cible.
		_marquer_tick_vide_sans_grille()
		return
	if not (frappe.collider is GridMap):
		# Frappe autre chose qu'une GridMap (mesh de decor, corps physique
		# etranger) : meme traitement -- tick vide, relance eventuelle vers
		# une case marron connue.
		_marquer_tick_vide_sans_grille()
		return
	var grille: GridMap = frappe.collider
	_grille_connue = grille  # memorise pour les returns silencieux futurs
	# ETAPE A' : verifier que le geniteur est POSE sur la GridMap avant de
	# prelever. Sans ce test le raycast trouve la grille 20 m plus bas
	# pendant la chute et l'extraction commence en l'air, ce qui n'a pas de
	# sens physique. Voir constante HAUTEUR_MAX_AU_SOL en haut du fichier
	# pour la mesure et le resultat negatif ecarte (linear_velocity).
	if global_position.y - float((frappe.position as Vector3).y) > HAUTEUR_MAX_AU_SOL:
		# En l'air : ne rien prendre, ne rien teindre (le decal garde sa
		# derniere couleur -- pas de reset volontaire pour ne pas clignoter
		# pendant la chute). Ne compte PAS comme un tick vide non plus :
		# _ticks_vides ne bouge pas, le geniteur ne partira pas chercher une
		# nouvelle case simplement parce qu'il n'est pas encore arrive au sol.
		return
	var point := (frappe.position as Vector3) - (frappe.normal as Vector3) * 0.01
	var cellule_centre := grille.local_to_map(grille.to_local(point))
	_cellule_centre_courante = cellule_centre  # memoire pour _choisir_cible

	# EXTRACTION ARRETEE SI LES DEUX STOCKS PLEINS : Yael a valide que
	# le geniteur cesse de prendre plutot que de gaspiller.
	if _stock_privee >= float(capacite_privee) and _stock_public >= float(capacite_public):
		return
	var capacite_totale: float = float(capacite_privee + capacite_public)
	var pris_total := 0.0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cellule := cellule_centre + Vector3i(dx, 0, dz)
			var pris := float(_ressources.preleve(cellule, float(quantite_par_case)))
			pris_total += pris
			if _stock_privee + _stock_public + pris_total >= capacite_totale:
				break
		if _stock_privee + _stock_public + pris_total >= capacite_totale:
			break
	# REPARTITION 50/50 avec debordement contro le : la moitie va au privee
	# TANT QU'IL N'EST PAS PLEIN ; ce que le privee refuse va integralement
	# dans public. Meme regle inverse : si public plein, tout dans
	# privee. Total conserve, aucune matiere perdue.
	var part_privee: float = 0.0
	var part_public: float = 0.0
	if _stock_privee >= float(capacite_privee):
		# PERSO plein -> tout dans public.
		part_public = minf(pris_total, float(capacite_public) - _stock_public)
	elif _stock_public >= float(capacite_public):
		# ACCESSIBLE plein -> tout dans privee.
		part_privee = minf(pris_total, float(capacite_privee) - _stock_privee)
	else:
		# CAS NOMINAL : moitie / moitie, avec debordement contro le.
		var moitie: float = pris_total * 0.5
		part_privee = minf(moitie, float(capacite_privee) - _stock_privee)
		part_public = minf(pris_total - part_privee, float(capacite_public) - _stock_public)
		# Si privee a capte moins que sa moitie (dej a presque plein),
		# le debordement va dans public ; la ligne ci-dessus le fait deja.
	_stock_privee = _stock_privee + part_privee
	_stock_public = _stock_public + part_public
	_materiau_stock.set_shader_parameter("fraction", _stock_privee / float(capacite_privee))
	if _materiau_stock_public != null:
		_materiau_stock_public.set_shader_parameter("fraction", _stock_public / float(capacite_public))
	# Sync entite pour perception : le stock_puisable actuel (= public).
	if not entite.is_empty():
		entite.proprietes["stock_puisable"] = _stock_public
	_teindre_zone(pris_total > 0.0)

	# ETAPE C : si RIEN pris ET AU MOINS UN stock non plein, on compte les
	# ticks vides. Si les deux sont pleins, l'immobilite est voulue (rien a
	# aller chercher).
	if pris_total > 0.0:
		_ticks_vides = 0
	elif _stock_privee < float(capacite_privee) or _stock_public < float(capacite_public):
		_ticks_vides += 1
		if _ticks_vides >= TICKS_ROUGE_AVANT_DEPART:
			_ticks_vides = 0
			_choisir_cible(grille)

# Tick vide sans grille sous les pieds (bord de carte, trou, collider
# etranger). Meme logique que le comptage classique dans _tenter_extraction,
# mais adapte au cas ou on n'a pas de grille en argument : on reutilise
# _grille_connue (memorisee au dernier tick reussi) pour _choisir_cible.
# Si aucune grille n'a jamais ete vue (spawn dans le vide), on ne fait rien
# ce tick-ci -- le geniteur tombera jusqu'a en trouver une.
func _marquer_tick_vide_sans_grille() -> void:
	# Idem : ne bouge pas si les deux stocks sont pleins.
	if _stock_privee >= float(capacite_privee) and _stock_public >= float(capacite_public):
		return
	_ticks_vides += 1
	if _ticks_vides >= TICKS_ROUGE_AVANT_DEPART:
		_ticks_vides = 0
		if _grille_connue != null:
			_choisir_cible(_grille_connue)

func _choisir_cible(grille: GridMap) -> void:
	var cases := chercher_cases_marrons()
	var pos_geniteur := global_position
	for c in cases:
		if _ressources.quantite_a(c) <= 0:
			continue
		# EXCLURE L'EMPRISE 3x3 ACTUELLE : sans ca, la case sous les pieds
		# (deja pillee mais tri par distance = 0) est cible instantanee,
		# _avancer_vers_cible declare arrive immediat, boucle silencieuse.
		if _cellule_centre_courante != null:
			var d := c - (_cellule_centre_courante as Vector3i)
			if absi(d.x) <= 1 and absi(d.z) <= 1:
				continue
		var pos_c := grille.to_global(grille.map_to_local(c))
		# PORTEE VERTICALE : ignorer les couches empilees en Y hors de
		# portee (case souterraine, plafond de mur). Le geniteur ne peut
		# monter ou descendre : cibler une case a 5 m sous lui = figeage.
		if absf(pos_c.y - pos_geniteur.y) > ECART_VERTICAL_MAX_CIBLE:
			continue
		# DISTANCE MINIMUM HORIZONTALE : garantit un vrai deplacement.
		# Sans ce filtre, une case adjacente a l'emprise (a ~4 m mais
		# < 1 m selon geometrie) peut declencher "arrive" immediat.
		var dx := pos_c.x - pos_geniteur.x
		var dz := pos_c.z - pos_geniteur.z
		if sqrt(dx * dx + dz * dz) < DISTANCE_MIN_CIBLE:
			continue
		_cible_deplacement = pos_c
		return

func _teindre_zone(active: bool) -> void:
	if _zone_material == null:
		return
	if active:
		_zone_material.albedo_color = COULEUR_ACTIVE
		_zone_material.emission = COULEUR_EMISSION_ACTIVE
	else:
		_zone_material.albedo_color = COULEUR_VIDE
		_zone_material.emission = COULEUR_EMISSION_VIDE

# API publique -- STOCK PERSO du geniteur. Utilise par gestation_energie
# et gestation_mother_cube pour tester le seuil de ponte. Le stock
# public aux generateurs enroles est distinct (voir preleve_stock_public).
func stock_courant() -> float:
	return _stock_privee

# API publique -- retirer du stock PERSO. Utilise par gestation_energie.gd
# (cout 20) et gestation_mother_cube.gd (cout 100) pour payer les
# gestations. Borne a zero. Rafraichit la barre bleue.
func retirer_stock(quantite: float) -> void:
	_stock_privee = maxf(0.0, _stock_privee - quantite)
	if _materiau_stock != null:
		_materiau_stock.set_shader_parameter("fraction", _stock_privee / float(capacite_privee))

# API publique -- LECTURE du stock ACCESSIBLE (violet). Utilise par
# gestation_generateur_public.gd pour la gate de ponte (v2 : les
# generateurs se produisent sur ce stock, plus sur le privee).
func stock_public_courant() -> float:
	return _stock_public

# API publique -- prelever au stock ACCESSIBLE (violet). Utilise par les
# generateurs enroles quand ils viennent puiser au geniteur. Rend la
# quantite REELLEMENT prise (bornee par le stock disponible), jamais
# celle demandee -- meme convention que ressources_terrain.gd:preleve.
# Un generateur qui recoit moins que cout_prelevement peut choisir de
# repartir chercher un cadavre (comportement a cabler morceau suivant).
func preleve_stock_public(quantite: float) -> float:
	var pris: float = minf(quantite, _stock_public)
	_stock_public = _stock_public - pris
	if _materiau_stock_public != null:
		_materiau_stock_public.set_shader_parameter("fraction", _stock_public / float(capacite_public))
	# Sync entite pour perception -- les generateurs qui percoivent doivent
	# voir la valeur qui vient de changer, pas l'ancienne.
	if not entite.is_empty():
		entite.proprietes["stock_puisable"] = _stock_public
	return pris

# API PUBLIQUE UNIFORME -- utilisee par les generateurs enroles. Alias de
# preleve_stock_public cote geniteur ; le cadavre (generateur_energie.gd
# apres _mourir) expose la MEME signature avec sa propre reserve. Le
# generateur enrole appelle preleve_stock_puisable indifferemment sur
# n'importe quelle source (respect CLAUDE.md § ADN : aucune connaissance
# du type de la source dans le code appelant).
func preleve_stock_puisable(quantite: float) -> float:
	return preleve_stock_public(quantite)

# API publique -- force le geniteur a chercher une nouvelle case marron
# vers laquelle se deplacer. Utilise par gestation_energie.gd quand aucune
# place n'est libre autour pour poser un generateur : bouger cree de
# nouvelles positions autour, la ponte reussira apres le trajet. Silent
# si aucune grille n'a jamais ete vue (spawn dans le vide).
func chercher_nouvelle_cible() -> void:
	if _grille_connue != null:
		_choisir_cible(_grille_connue)

# API publique -- rend les cellules de type `nom_ressource_cible` dans
# le rayon de detection, triees par distance croissante.
func chercher_cases_marrons() -> Array[Vector3i]:
	if _ressources == null:
		return []
	return _ressources.cellules_par_nom_dans_rayon(
		global_position, rayon_detection, nom_ressource_cible)
