extends Node3D

# LE PORTEUR DU COUVERT VEGETAL : il fait tenir ensemble le terrain, la
# simulation et l'ecran, et c'est tout ce qu'il fait.
#
# CE FICHIER NE DECIDE DE RIEN. La vie des plantes vit dans
# jeu/plantes/vegetation.gd (pur, sans noeud, testable headless) ; la lecture du
# terrain vit dans jeu/plantes/surface_terrain.gd. Ici : relever une fois,
# charger les especes que les semis reclament, prechauffer, appeler le tick,
# echanger le modele quand un stade change, poser et retirer les produits. Le
# rendu RELIT le rapport, il ne le recalcule jamais.
#
# PAS DE @tool, ET C'EST VOULU : ce noeud ne tourne QUE dans le jeu lance. Sous
# @tool, les plantes grandiraient et mourraient pendant que le game designer
# sculpte, et sa mise en place ne survivrait pas a une sauvegarde.
#
# CE NOEUD SE POSE EN ENFANT DIRECT DU GRIDMAP DU TERRAIN, et il le verifie. Tout
# le releve vit dans le repere LOCAL de la grille (voir surface_terrain.gd, ou
# to_global est ecarte parce qu'il rend une matrice vide hors de l'arbre).
#
# LA HAUTEUR DU SOL VIENT DE LA CARTE QUE LE TERRAIN PORTE, et de ses cellules
# seulement a defaut. Un terrain qui ne rend qu'un disque autour du joueur ne
# porte aucune cellule quand ce noeud s'eveille, et n'en portera jamais ailleurs
# que sous le joueur : le releve pris sur ses cellules serait vide, et le couvert
# mort-ne. Quel GridMap porte une carte, quel autre n'en porte pas : voir
# jeu/terrain/terrain_visible.gd et jeu/terrain/carte_terrain.gd.
#
# ---- UNE PLANTE N'EST PAS UN NOEUD DE DESSIN ----
# Les plantes d'une meme espece au meme stade sont le MEME modele a des positions
# differentes : rien ne les distingue. Elles sont donc des LIGNES dans un lot --
# un MultiMesh par maillage, une transform par plante -- et la carte graphique
# dessine le lot d'un seul ordre. Un noeud par plante ferait un ordre par plante,
# plus l'objet de scene qui va avec.
#
# Changer de stade, c'est sortir d'un lot et entrer dans un autre. Voir « LES
# LOTS DE RENDU » plus bas pour ce que le regroupement fait perdre.
#
# ---- ET UN TRONC, QUAND L'ESPECE EN DECLARE UN ----
# Une espece qui pose un `rayon_collision` recoit un CORPS PhysicsServer3D
# pur (RID, aucun noeud d'arbre de scene) : un cylindre de ce rayon, haut
# comme la stature du stade, qu'aucune unite ne traverse. Il est echange
# a chaque changement de stade -- une pousse ne barre pas le passage comme
# un arbre mature. A rayon nul, aucun corps n'est pose : c'est le cas de
# l'herbe, et le defaut.
#
# LE CORPS EST UN RID DE PhysicsServer3D, PAS UN NODE. Mesure d'octobre :
# 5x moins cher qu'un StaticBody3D a 2827 corps actifs simultanes (~3 ms/
# frame de physics vs ~16 ms). Aucun overhead de noeud (pas de signaux, pas
# de notifications, pas de traversee d'arbre par frame).
#
# LA SHAPE (RID) EST PARTAGEE PAR TOUTES LES PLANTES D'UNE ESPECE ET D'UN
# STADE : une shape RID vit dans le serveur physique, decrire une fois suffit
# pour mille arbres. Liberee au NOTIFICATION_PREDELETE du Couvert.
#
# ---- DEUX FACONS D'AVOIR UN CORPS ----
# Une espece qui declare des chemins de modeles recoit ses .glb. Une espece qui
# n'en declare AUCUN recoit une TOUFFE fabriquee ici a l'execution, haute comme
# la stature du stade et de la couleur de l'espece. Grossiere de pres, lisible de
# loin -- assez pour voir tourner un ecosysteme sans attendre qu'un maillage
# existe. Poser des chemins dans le JSON de l'espece la remplace, sans une ligne
# de code.
#
# LES MODELES SONT RECENTRES A L'INSTANCIATION. Un .glb exporte depuis une scene
# ou les modeles sont ranges cote a cote garde le decalage de sa place dans la
# rangee : trois modeles ainsi ranges sont a trois endroits, et une plante qui
# change de stade SAUTE d'autant -- elle parait disparaitre alors qu'elle est
# ailleurs. Defaut trouve EN REGARDANT L'ECRAN, invisible a tout test qui ne
# mesure pas la geometrie. Le recentrage est MESURE sur le modele reel : un
# modele deja centre rend un decalage nul et rien ne s'applique.
#
# LES SEMIS SONT SES PROPRES ENFANTS : chaque jeu/plantes/plante.tscn pose a la
# main sous ce noeud devient une plante de simulation, de l'espece qu'il declare,
# a la colonne ou le game designer l'a laisse. Son noeud est REUTILISE comme
# porteur, et ses enfants d'editeur sont liberes -- ils n'existent que pour se
# voir et se deplacer dans l'editeur.
#
# UN SEMIS HORS COUCHE EST POSE QUAND MEME, et seulement signale en console : le
# mecanisme ne supprime jamais ce que le game designer a place. Un semis d'espece
# INCONNUE, lui, ne peut pas etre pose -- il n'y a aucune table de stades a lui
# donner.
#
# Regles tenues : positions en Vector3. Aucun hasard hors du RNG seede que porte
# l'etat. Les prints sont des traces de mise au point, pas du texte joueur. Rien
# de scripts/, data/ ni addons/ n'est ecrit.

const Vegetation = preload("res://jeu/plantes/vegetation.gd")
const Surface = preload("res://jeu/plantes/surface_terrain.gd")
const PlanteScript = preload("res://jeu/plantes/plante.gd")
const EspeceScript = preload("res://jeu/plantes/espece.gd")
const PeuplementScript = preload("res://jeu/plantes/peuplement.gd")

# Ancien constant `NOM_TRONC` supprime : le tronc n'est plus un noeud
# StaticBody3D nomme, c'est un corps PhysicsServer3D pur (RID). Aucun
# fils de porteur a chercher par nom.
#
# POUR LE FUTUR : si un raycast physique doit un jour identifier QUEL arbre
# il touche (par exemple pour un colon qui abat un arbre choisi visuellement),
# il faudra ajouter un appel PhysicsServer3D.body_attach_object_instance_id
# apres body_create, avec un id qui permette de remonter a l'entree data de
# la plante (etat.plantes). Aujourd'hui aucun raycast n'a ce besoin --
# `interaction_destruction.gd` du banc test_ennemi vise le groupe
# "destructible" et les arbres du couvert n'y sont pas ; la destruction
# externe d'un arbre passe par vegetation.gd:retirer(id) sur un id data,
# jamais via collider.

# ---- LES REGLAGES DE L'INSPECTEUR ----
#
# CE QUI EST ICI EST CE QUI EST PARTAGE PAR TOUTES LES ESPECES. Ce qui varie de
# l'une a l'autre -- stades, statures, plafond de couche, trouee, reproduction,
# production, modeles -- vit dans le JSON de l'espece, parce qu'il y a autant de
# jeux de valeurs que d'especes et que le code ne connait pas leur nombre. Un
# `@export` par espece mettrait un nom de contenu dans un .gd, ce que l'ADN
# interdit (CLAUDE.md). Pour regler une espece sans ouvrir son fichier, voir
# `surcharges_especes` plus bas.
#
# CES VALEURS SURCHARGENT jeu/plantes/vegetation.json : _ready() fusionne les deux
# et ne passe QU'UN Dictionary a la simulation, qui ne sait rien de ce noeud. Le
# fichier reste la seule source pour tout ce qui tourne sans noeud, tests compris,
# et test_plante.gd rougit des que les deux s'ecartent.

@export_group("Peuplement")

# L'ECHELLE A LAQUELLE LE COUVERT REGARDE SON VOISINAGE. Le SEUIL, lui, vit sur
# chaque espece (`max_voisins` sur le noeud Arbre, Herbe...) : une herbe qui fait
# tapis supporte des dizaines de voisines la ou un arbre en refuse six. Le rayon
# reste commun parce qu'il choisit le rayon de rafraichissement de tout le couvert
# (vegetation.gd:rafraichir_autour), qui ne peut pas varier d'une plante a l'autre.
@export var rayon_voisinage_cellules: int = 5

# LA DOMINANCE : dans ce rayon, une voisine de stature strictement superieure fige
# la croissance. Elle ne tue pas -- elle fait attendre.
@export var rayon_ombre_cellules: int = 3

# L'ETABLISSEMENT : dans ce rayon autour du point d'arrivee, un rejet compte les
# vivantes et renonce si elles depassent le seuil de SON espece.
@export var rayon_trouee_cellules: int = 2

@export_group("Prechauffage")

# COMBIEN DE TICKS LA SIMULATION JOUE AVANT LA PREMIERE IMAGE. A zero, le couvert
# demarre tel que le game designer l'a pose. Plus haut, le joueur arrive sur une
# vegetation deja vecue au lieu d'un terrain nu.
#
# LE TEMPS SIMULE EST ticks x delta. Une plante posee a la main qui vit moins que
# ce total sera morte avant la premiere image -- ce n'est pas un defaut, c'est ce
# qu'on a demande.
@export var ticks_prechauffage: int = 0

# Les secondes simulees par tick de prechauffage. AUCUNE VALEUR NE PEUT DEFORMER
# LA SIMULATION : un pas trop grand devant les durees en jeu est decoupe en
# tranches fideles (vegetation.gd:pas_maximal). Le monter fait donc chauffer plus
# longtemps, jamais plus grossierement -- au prix du temps de demarrage.
@export var delta_prechauffage: float = 1.0

@export_group("Rythme")

# LE PAS DE LA SIMULATION, en secondes simulees. Le tick ne suit PLUS la frequence
# d'images : il est joue a intervalle fixe, quel que soit le nombre d'images par
# seconde. Une plante met des dizaines de secondes a changer de stade -- l'evaluer
# soixante fois par seconde etait du gaspillage pur, et c'est ce qui faisait ramer
# le couvert bien avant que le nombre de plantes ne pose probleme.
#
# LA VALEUR VIENT D'UNE MESURE, pas d'une regle inventee. Une plante a l'ombre y
# reste longtemps (76 s en mediane), mais ses ECLAIRCIES sont breves : 9 secondes
# en mediane, 46 au maximum. C'est la duree des eclaircies qui contraint le pas --
# un pas de 10 s raterait la moitie d'entre elles, et comme l'ombre dure huit fois
# plus longtemps que la lumiere, l'echantillonnage tomberait presque toujours
# pendant l'ombre : les plantes en concurrence SOUS-POUSSERAIENT systematiquement.
# A 2 secondes, aucune eclaircie n'est ratee.
@export var pas_simulation: float = 2.0

# Combien de ticks au plus dans une seule image. LE RETARD EST ABANDONNE, jamais
# rattrape : si la simulation ne suit pas, rattraper ferait un tick de plus a
# chaque image, qui prendrait encore plus de retard -- le jeu se fige au lieu de
# ralentir. Perdre du temps simule est le moindre mal, et c'est dit plutot que
# masque.
@export var ticks_max_par_image: int = 4

@export_group("Collision")

# LE RAYON AUTOUR DE L'OBSERVATEUR OU LES TRONCS SOLIDES EXISTENT. Hors de ce
# rayon, l'arbre pousse et vit en donnee sans StaticBody3D -- le rendu MMI
# reste peuple et Godot cull le mesh au-dela de `distance_rendu`. Zero
# collision loin du joueur = zero cout physique pour une foret de milliers
# d'arbres. Le patron MANQUAIT au couvert : le rendu etait deja batche, mais
# chaque adulte fertile portait son StaticBody3D en permanence, partout.
@export var rayon_collision_metres: float = 60.0

# DE COMBIEN L'OBSERVATEUR DOIT S'ECARTER avant qu'on rescanne le voisinage pour
# le rendu et la collision. Entre deux, la liste des arbres proches ne change pas
# (la simulation est figee hors tick, le joueur bouge peu) -- rescanner a chaque
# frame est du gaspillage. Le rescan a lieu aussi a chaque tick joue.
@export var seuil_rescan_metres: float = 4.0

# LE GROUPE OU CHERCHER L'OBSERVATEUR. Meme convention que manager_proto :
# le noeud du joueur (ou de la camera) porte `groups=["observateur"]` dans sa
# tscn. Absent -> aucun tronc n'est pose, tout est en donnee. Autrement dit,
# le culling collision est une OPTION qui s'active par la seule presence de
# l'observateur.
@export var groupe_observateur: StringName = &"observateur"

@export_group("Observation")

# Multiplie le pas de temps de la simulation, jamais celui du moteur. Il est
# DECOUPE comme le prechauffage : accelerer montre la meme simulation plus vite,
# jamais une simulation plus grossiere -- au prix du temps de calcul, qui monte
# avec le facteur.
@export var facteur_temps: float = 1.0

var _config: Dictionary = {}
var _types: Dictionary = {}
var _releve: Dictionary = {}
var _etat: Dictionary = {}
var _rendus: Dictionary = {}
# Ancien `_noeuds: Dictionary` supprime : plus aucun Node3D porteur par
# plante. La collision vit dans PhysicsServer3D via `_corps_actifs`.
# LES LOTS DE RENDU : une cle « espece#stade » -> un paquet de MultiMesh, un par
# maillage du modele. C'est ce qui remplace un noeud de dessin par plante.
var _lots: Dictionary = {}
# id d'une plante -> la cle du lot ou elle est inscrite. Sans lui, la retirer
# demanderait de fouiller tous les lots.
var _lot_de: Dictionary = {}
# id -> sa position. Le rendu la relit a chaque changement de stade, et une
# plante sans tronc n'a plus de noeud pour la porter.
var _poses: Dictionary = {}
# Le plus grand pas fidele, deduit des especes chargees -- voir
# vegetation.gd:pas_maximal. Ni le rendu ni le prechauffage n'appellent avancer()
# directement : les deux passent par les tranches, et aucun ne peut donc choisir
# un pas qui deformerait la simulation.
var _pas_max := 0.0
# Le temps simule en attente d'etre joue. Le tick etant a pas FIXE, ce qui reste
# sous un pas complet est reporte a l'image suivante.
var _accumulateur := 0.0
# LE JOUEUR (ou la camera), trouve par groupe au _ready. Null jusqu'a ce que
# quelqu'un porte le groupe -- auquel cas aucun tronc n'est pose.
var _observateur: Node3D = null
# LES CORPS PHYSIQUES DES TRONCS, portes par PhysicsServer3D (pas par des
# noeuds). id de plante -> {"rid": RID, "numero": int}. Le numero sert a
# detecter un changement de stade (hauteur suit la stature -- nouveau body
# necessaire avec la shape du bon stade).
var _corps_actifs: Dictionary = {}
# FILE D'ATTENTE DES PLANTES DE PEUPLEMENT, consommee par tick dans _process
# a raison de budget_par_frame plantes. Chaque entree :
# {id, colonne, type, age_initial, budget}. Sans cette file, N plantes d'un
# coup au ready donnent un pic de fabrication ingerable (~650 ms a N=1000).
var _file_peuplement: Array = []
# LES SHAPES RID PAR ESPECE ET PAR STADE, fabriquees une fois au ready et
# partagees par tous les corps du meme stade de la meme espece. Structure :
# nom_espece -> Array[RID] indexe par (numero - 1). RID vide (null) pour un
# stade dont la forme est nulle (rayon zero ou stature zero). Liberees au
# NOTIFICATION_PREDELETE.
var _shapes_rid: Dictionary = {}

# L'OCCLUDEUR DES CANOPEES. Un seul OccluderInstance3D pour toutes les canopees
# d'arbres actuellement rendues : ce qui est entierement derriere elles n'est
# plus dessine. Il ne se reconstruit QUE quand la population rendue change
# (naissance, mort, changement de stade, entree/sortie du rayon) -- signalee par
# `_occl_dirty`. Les arbres sont statiques entre deux changements ; aucune
# reconstruction par frame, meme principe que l'occludeur du terrain.
var _occl_arbres: OccluderInstance3D = null
var _occl_dirty := false

# THROTTLE DU SCAN DE BASCULE. `_bascule_rendu` fait une requete spatiale
# (`choses_dans_rayon`) ; la relancer a chaque frame gaspille, car la liste des
# arbres proches ne change qu'au tick (changement de stade) ou quand
# l'observateur se deplace. On retient sa derniere position de scan.
var _derniere_pos_bascule := Vector3.ZERO
var _amorce_bascule := false

# Compteurs d'instrumentation (audit performance), remis a zero par
# prelever_stats(). Passifs : aucune logique de simulation n'en depend.
var _stat_body_create := 0
var _stat_free_rid := 0
var _stat_set_transform := 0
var _stat_realloc := 0
var _stat_ticks := 0
var _stat_temps_tick_us := 0

# Rend les compteurs accumules depuis le dernier appel, puis les remet a zero.
func prelever_stats() -> Dictionary:
	var s := {
		"body_create": _stat_body_create,
		"free_rid": _stat_free_rid,
		"set_transform": _stat_set_transform,
		"realloc": _stat_realloc,
		"ticks": _stat_ticks,
		"temps_tick_us": _stat_temps_tick_us,
	}
	_stat_body_create = 0
	_stat_free_rid = 0
	_stat_set_transform = 0
	_stat_realloc = 0
	_stat_ticks = 0
	_stat_temps_tick_us = 0
	return s

func _ready() -> void:
	var grille := get_parent() as GridMap
	if grille == null:
		push_error("couvert.gd : ce noeud doit etre enfant DIRECT du GridMap du terrain")
		set_process(false)
		return
	if transform != Transform3D.IDENTITY:
		push_error("couvert.gd : ce noeud porte une transform propre -- les colonnes du releve ne coincideront pas avec celles du terrain")

	_config = appliquer_reglages(Vegetation.charger_config(), reglages())
	if _config.is_empty():
		set_process(false)
		return

	# LA CARTE GAGNE SUR LES CELLULES QUAND LE TERRAIN EN PORTE UNE. Un GridMap
	# qui ne rend qu'un disque autour du joueur n'a encore AUCUNE cellule ici --
	# l'ordre des _ready va des enfants vers le parent, et c'est le parent qui
	# les pose. Le releve viendrait vide, et plus rien ne pousserait nulle part.
	# La carte, elle, decrit tout le terrain sans rien rendre.
	var carte_du_terrain = grille.get("carte")
	if carte_du_terrain != null:
		_releve = Surface.relever_depuis_carte(grille, carte_du_terrain)
	else:
		_releve = Surface.relever(grille)
	if not Surface.porte_du_terrain(_releve):
		push_error("couvert.gd : le terrain ne porte aucune colonne -- rien sur quoi planter")
		set_process(false)
		return

	_types = _charger_les_especes()
	_pas_max = Vegetation.pas_maximal(_types, _config)
	if _pas_max > 0.0 and pas_simulation > _pas_max:
		push_error("couvert.gd : un pas de %.1f s depasse le plus grand pas fidele (%.1f s) -- des stades seront sautes" % [
			pas_simulation, _pas_max])
	var semis := _semis()
	if _types.is_empty():
		push_error("couvert.gd : aucune espece chargee -- rien ne peut pousser")
		set_process(false)
		return
	_preparer_les_rendus()

	_etat = Vegetation.etat_initial(semis, _releve, _config, _types)
	for refus in _etat.refus:
		push_warning("couvert.gd : semis '%s' en colonne %s -- %s" % [
			refus.id, refus.colonne, refus.raison])
	for graine in semis:
		if graine.noeud != null:
			for enfant in graine.noeud.get_children():
				enfant.queue_free()

	_prechauffer()

	# LA POSE VIENT APRES, EN UNE SEULE PASSE. Pendant le prechauffage il n'y a
	# rien a l'ecran : poser puis retirer des milliers de noeuds pour montrer une
	# croissance que personne ne regarde coute cher et ne rend rien.
	for plante in _etat.plantes:
		_poser_plante(plante)
	for graine in _etat.graines:
		_poser_graine(String(graine.id))
	_liberer_les_semis_disparus(semis)

	_observateur = get_tree().get_first_node_in_group(groupe_observateur)

	# LE COMPTE EST CELUI DES VIVANTES, jamais la taille de la liste : les mortes y
	# figurent jusqu'a la purge du tick suivant, et une trace qui les compte annonce
	# une foret plus grande que celle qu'on voit.
	print("couvert : %d semis, %d espece(s), %d tick(s) de prechauffage -> %d vivante(s), %d produit(s)" % [
		semis.size(), _types.size(), ticks_prechauffage,
		Vegetation.vivantes(_etat.plantes, _config).size(), (_etat.graines as Array).size()])

func _process(delta: float) -> void:
	if _etat.is_empty():
		return
	# ETALEMENT DES PEUPLEMENTS : chaque tick, on consomme jusqu'au budget
	# de la premiere entree de la file. Le budget vient du noeud Peuplement
	# lui-meme (budget_par_frame @export). Le rebuild du monde et le
	# rafraichir_autour ne se font qu'UNE FOIS a la fin du batch.
	_consommer_file_peuplement()
	_accumulateur += delta * facteur_temps
	var joues := 0
	var t0_tick := Time.get_ticks_usec()
	while _accumulateur >= pas_simulation and joues < ticks_max_par_image:
		_accumulateur -= pas_simulation
		joues += 1
		_appliquer(Vegetation.avancer_par_tranches(
			_etat, _config, _types, _releve, pas_simulation, _pas_max))
	if joues > 0:
		_stat_ticks += joues
		_stat_temps_tick_us += Time.get_ticks_usec() - t0_tick
	if joues >= ticks_max_par_image:
		# Le retard restant est ABANDONNE -- voir ticks_max_par_image.
		_accumulateur = 0.0
	# LE SCAN NE SE RELANCE QU'AU TICK OU AU DEPLACEMENT. Voir _doit_basculer.
	if _doit_basculer(joues):
		_bascule_rendu()

# Le scan spatial de _bascule_rendu ne se justifie qu'a deux moments : un tick a
# ete joue (un stade a pu changer -> `joues > 0`), ou l'observateur s'est ecarte
# de `seuil_rescan_metres` depuis le dernier scan (des arbres entrent ou sortent
# du rayon). Entre les deux, la liste des arbres proches est identique et il n'y
# a rien a refaire. Le tout premier passage scanne toujours (`_amorce_bascule`).
func _doit_basculer(joues: int) -> bool:
	if _observateur == null:
		return false
	if not _amorce_bascule:
		_amorce_bascule = true
		return true
	if joues > 0:
		return true
	return _observateur.global_position.distance_to(_derniere_pos_bascule) >= seuil_rescan_metres

# Consomme jusqu'a `budget` plantes de la file, les fabrique via
# Vegetation.fabriquer_plante (age_initial preserve), les append a
# etat.plantes. Rebuild le monde et rafraichir_autour les nouveaux foyers en
# une seule passe a la fin -- coute O(N_vivantes) une fois par tick au lieu
# de N fois.
func _consommer_file_peuplement() -> void:
	if _file_peuplement.is_empty():
		return
	var budget: int = int(_file_peuplement[0].get("budget", 30))
	var a_ajouter: int = mini(budget, _file_peuplement.size())
	var foyers: Array = []
	var nouvelles: Array = []
	for _n in range(a_ajouter):
		var entree: Dictionary = _file_peuplement.pop_front()
		var type: Dictionary = _types.get(String(entree.type), {})
		if type.is_empty():
			continue
		var plante := Vegetation.fabriquer_plante(
			String(entree.id), entree.colonne, _releve, _config, type,
			_etat.rng, float(entree.age_initial))
		if plante.is_empty():
			continue
		(_etat.plantes as Array).append(plante)
		# AJOUT INCREMENTAL au monde indexe : evite le rebuild O(N) par batch
		# qui rendait l'etalement plus cher que le pic initial. monde.ajouter
		# ne balaie que les niveaux d'index deja ouverts, coute O(niveaux).
		_etat.monde.ajouter(plante, String(plante.proprietes.type_plante), plante.position)
		nouvelles.append(plante)
		foyers.append(plante.position)
	if not nouvelles.is_empty():
		# OMBRE des nouvelles (utilise_ombre). LE RENDU N'EST PAS POSE ICI :
		# c'est _bascule_rendu, et lui seul, qui inscrit une plante dans un lot
		# -- et SEULEMENT si elle est dans le rayon de l'observateur. Poser le
		# rendu ici inscrivait chaque nouvelle plante quelle que soit sa
		# distance ; avec un peuplement disperse sur des kilometres, budget
		# arbres par frame apparaissaient au loin a chaque frame et n'etaient
		# radies qu'au tick suivant -- un scintillement d'arbres lointains
		# pendant tout le peuplement. Meme regle que les naissances de
		# reproduction, qui ne posent deja aucun rendu (voir _appliquer).
		for plante in nouvelles:
			Vegetation.rafraichir_plante(plante, _etat.monde, _config, _releve)
		# COMPTE DE VOISINS : maintenance incrementale du framework, cote
		# NAISSANCE uniquement (aucune mort dans un batch de peuplement). Chaque
		# nouvelle pose son propre compte, chaque existante voisine prend +1.
		# Meme geste que le §7 du tick -- une seule source de verite.
		Vegetation.maj_voisins_naissances(_etat, _config, _releve, nouvelles)

# Le rendu, et rien d'autre : il RELIT le rapport du tick, il ne recalcule jamais
# ce qui vient de se passer. NAISSANCES ET CHANGEMENTS DE STADE NE POSENT
# PLUS DE RENDU ICI : _bascule_rendu s'en charge, seulement pour les plantes
# dans le rayon de l'observateur. Ce que garde _appliquer : purger les mortes
# (qui pouvaient etre visibles) et gerer les produits (rares, non streames).
func _appliquer(rapport: Dictionary) -> void:
	for id in rapport.morts:
		_retirer_plante(String(id))
	for produit in rapport.produits:
		_poser_graine(String(produit.id))
	for id in rapport.perdues:
		retirer_graine(String(id))

# ---- Le prechauffage ----

# DES TICKS JOUES D'AVANCE, ET RIEN D'AUTRE. Aucune mecanique neuve : c'est
# EXACTEMENT la fonction de tick que _process appelle en jeu, appelee en boucle
# avant la premiere image. _process ne l'appelle PAS a chaque image -- il
# accumule le temps ecoule et ne joue un tour que lorsque `pas_simulation` est
# atteint, ce qui, au reglage courant, arrive une fois toutes les quelques
# secondes et jamais soixante fois par seconde. Le rapport de chaque tour est
# ignore VOLONTAIREMENT -- il ne sert qu'a tenir l'ecran a jour, et l'ecran
# n'existe pas encore.
#
# N ticks d'avance plus M ticks normaux doivent rendre le meme etat que N+M ticks
# normaux. Si les deux divergent, c'est que _process fait un travail de simulation
# que avancer() ne fait pas. test_plante.gd le verrouille.
func _prechauffer() -> void:
	if ticks_prechauffage <= 0:
		return
	for _i in range(ticks_prechauffage):
		Vegetation.avancer_par_tranches(
			_etat, _config, _types, _releve, delta_prechauffage, _pas_max)

# UN SEMIS PEUT NE PAS SURVIVRE A SON PROPRE PRECHAUFFAGE : pose a la main, il a
# vecu des minutes avant la premiere image et peut etre mort de vieillesse. Son
# noeud d'editeur, lui, est toujours la -- vide, invisible, jamais reclame. Il est
# libere ici, sans quoi chaque lancement laisserait autant de fantomes que de
# semis trop vieux.
func _liberer_les_semis_disparus(semis: Array) -> void:
	for graine in semis:
		if graine.noeud == null:
			continue
		if _poses.has(String(graine.id)):
			continue
		graine.noeud.queue_free()

# ---- Les reglages ----

func reglages() -> Dictionary:
	return {
		"rayon_voisinage_cellules": rayon_voisinage_cellules,
		"rayon_ombre_cellules": rayon_ombre_cellules,
		"rayon_trouee_cellules": rayon_trouee_cellules,
	}

# La fusion, PURE : rend une config NEUVE, l'originale n'est jamais mutee. Sans la
# copie profonde, deux couverts dans la meme scene se regleraient l'un l'autre par
# le Dictionary que JSON.parse_string leur a rendu.
static func appliquer_reglages(base: Dictionary, valeurs: Dictionary) -> Dictionary:
	if base.is_empty():
		return {}
	var config: Dictionary = base.duplicate(true)
	for cle in valeurs:
		config[cle] = valeurs[cle]
	return config

# ---- Les semis et les especes ----

# Les semis : les enfants qui portent le script de plante, dans l'ordre de la
# scene -- donc DETERMINISTE. Leur position est convertie en colonne par le
# releve, jamais gardee telle quelle : un semis lache entre deux cellules doit
# pousser SUR une cellule, pas a cheval.
func _semis() -> Array:
	var semis: Array = []
	for enfant in get_children():
		if enfant.get_script() == PlanteScript:
			var espece := String(enfant.type)
			if espece == "":
				espece = String(_config.type_par_defaut)
			semis.append({
				"id": String(enfant.name),
				"colonne": Surface.colonne_de(enfant.position, _releve),
				"type": espece,
				"noeud": enfant,
			})
		elif enfant.get_script() == PeuplementScript:
			# UN PEUPLEMENT s'expande en N semis avec age_initial calcule
			# depuis les durees des stades precedents (milieu du stade cible).
			# Les positions sont tirees dans un disque autour du peuplement,
			# RNG seede : deux parties meme graine donnent le meme dessin.
			_expander_peuplement(enfant, semis)
	return semis

# EXPANSE un noeud Peuplement en autant de semis que declare son tableau
# `nombres_par_stade`. Chaque semis recoit un age_initial qui le pose au
# milieu du stade cible, prêt a vivre. Les positions sont tirees dans un
# disque autour du peuplement (uniforme, rayon = sqrt(u) * rayon_max pour
# eviter la concentration au centre).
func _expander_peuplement(noeud: Node3D, _semis_ignores: Array) -> void:
	var espece := String(noeud.get("espece"))
	if espece == "" or not _types.has(espece):
		push_warning("couvert.gd : peuplement '%s' nomme une espece '%s' inconnue" % [noeud.name, espece])
		return
	var type: Dictionary = _types[espece]
	var stades: Array = type.stades
	var nombres: Array = noeud.get("nombres_par_stade")
	var rayon: float = float(noeud.get("rayon_dispersion"))
	var seed_rng: int = int(noeud.get("seed_rng"))
	var duree_dispersion: float = float(noeud.get("duree_dispersion_apparition"))
	var vitesse := float(_config.annees_par_seconde)
	var dispersion_age: float = duree_dispersion * vitesse * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_rng
	var index_semis := 0
	var age_seuils: Array = []
	var cumul := 0.0
	for stade in stades:
		age_seuils.append(cumul)
		cumul += float(stade.duree)
	# LES ENTREES NE VONT PAS DANS `semis` (etat_initial les fabriquerait
	# TOUTES au ready = pic 650 ms a N=1000). Elles vont dans _file_peuplement,
	# consommee par tick dans _process a raison de budget_par_frame plantes.
	var budget: int = int(noeud.get("budget_par_frame"))
	for i in range(mini(nombres.size(), stades.size())):
		var nombre := int(nombres[i])
		if nombre <= 0:
			continue
		var age_cible := float(age_seuils[i]) + float(stades[i].duree) * 0.5
		for _n in range(nombre):
			var angle := rng.randf_range(0.0, TAU)
			var r := sqrt(rng.randf()) * rayon
			var pos_locale := noeud.position + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
			var id := "%s_%d" % [noeud.name, index_semis]
			index_semis += 1
			# ALEA d'age_initial dans une fenetre centree sur l'age cible.
			# Chaque plante atteint son stade cible a un instant different,
			# apparition visuellement dispersee sur duree_dispersion secondes.
			var age_avec_alea := age_cible + rng.randf_range(-dispersion_age, dispersion_age)
			_file_peuplement.append({
				"id": id,
				"colonne": Surface.colonne_de(pos_locale, _releve),
				"type": espece,
				"age_initial": maxf(0.0, age_avec_alea),
				"budget": budget,
			})

# LES ESPECES DECLAREES A L'INSPECTEUR, indexees par leur nom -- celui qu'un semis
# ecrit dans son champ `Type`. Une espece sans nom, sans stade, ou dont le nom est
# deja pris est nommee en console : jamais un couvert a moitie peuple en silence.
# LES ESPECES SONT DES NOEUDS ENFANTS, exactement comme les semis : le game
# designer les voit dans l'arbre de scene, en clique une, et n'a sous les yeux que
# ses reglages. Deux especes ne se melangent jamais dans le meme inspecteur.
#
# Une espece sans nom, sans stade, ou dont le nom est deja pris est nommee en
# console : jamais un couvert a moitie peuple en silence.
func _charger_les_especes() -> Dictionary:
	var types: Dictionary = {}
	for enfant in get_children():
		if enfant.get_script() != EspeceScript:
			continue
		var nom := String(enfant.nom)
		if nom == "":
			push_error("couvert.gd : l'espece '%s' n'a pas de nom -- aucun semis ne peut la reclamer" % enfant.name)
			continue
		if types.has(nom):
			push_error("couvert.gd : deux especes portent le nom '%s' -- la seconde est ignoree" % nom)
			continue
		var prepare := Vegetation.preparer_depuis_champs(nom, enfant.champs(), _config)
		if prepare.is_empty():
			push_error("couvert.gd : l'espece '%s' ne declare aucun stade -- elle ne peut pas vivre" % nom)
			continue
		types[nom] = prepare
	return types

# ---- Les corps ----

# UN CORPS PAR STADE ET PAR ESPECE, prepare une fois. Une espece a modeles recoit
# ses scenes ; une espece sans modele recoit des touffes hautes comme ses statures.
# Charger ou fabriquer a chaque changement de stade relirait les memes fichiers des
# centaines de fois.
func _preparer_les_rendus() -> void:
	var largeur := float(_config.largeur_touffe)
	var brins := int(_config.brins_touffe)
	for nom in _types:
		var type: Dictionary = _types[nom]
		var chemins: Array = type.modeles_stades
		var stades: Array = []
		for i in range((type.stades as Array).size()):
			var stature := float((type.stades as Array)[i].get("stature", 1.0))
			if i < chemins.size() and String(chemins[i]) != "":
				stades.append(_corps_depuis_chemin(String(chemins[i])))
			elif float(type.rayon_collision) > 0.0:
				# UNE ESPECE QUI DECLARE UN TRONC recoit une silhouette d'arbre
				# stylise (cylindre + cone). Gate arithmetique, jamais une
				# branche qui nommerait une espece.
				stades.append(_corps_arbre(stature, type.couleur))
			else:
				stades.append(_corps_touffe(stature, largeur, brins, type.couleur))
		var produit := _corps_touffe(largeur, largeur, brins, type.couleur)
		if String(type.modele_produit) != "":
			produit = _corps_depuis_chemin(String(type.modele_produit))
		# UNE FORME PAR STADE, PARTAGEE PAR TOUTES LES PLANTES DE L'ESPECE. Une
		# Shape3D est une ressource : mille arbres au meme stade pointent la meme,
		# et le moteur physique ne la decrit qu'une fois. En fabriquer une par
		# plante multiplierait la memoire par la population sans rien changer a
		# l'ecran. Vide quand l'espece ne declare aucun rayon.
		# LE RAYON EST PROPORTIONNEL A LA STATURE DU STADE. rayon_collision de
		# l'espece est le rayon MAXIMAL, atteint au stade le plus grand. Un
		# enfant a un tronc plus fin qu'un adulte -- sans ca un arbrisseau de
		# 2 m bloquerait le passage sur 3 m de diametre. Gate arithmetique : une
		# espece dont la plus grande stature est 0 rend un rayon 0 partout.
		var stature_max := 0.0
		for stade in (type.stades as Array):
			stature_max = maxf(stature_max, float(stade.get("stature", 0.0)))
		var troncs: Array = []
		var troncs_rid: Array = []
		for i in range((type.stades as Array).size()):
			var stature_stade := float((type.stades as Array)[i].get("stature", 0.0))
			var rayon_stade := 0.0
			if stature_max > 0.0:
				rayon_stade = float(type.rayon_collision) * stature_stade / stature_max
			troncs.append(forme_de_tronc(rayon_stade, stature_stade))
			# SHAPE RID JUMELLE DE LA FORME NODE : meme rayon et meme hauteur.
			# La forme Node reste fabriquee pour que test_plante:_juger_le_tronc
			# continue a interroger forme_de_tronc en static. La shape RID
			# porte la collision reelle du jeu, sans passer par un noeud.
			if rayon_stade > 0.0 and stature_stade > 0.0:
				var shape_rid := PhysicsServer3D.cylinder_shape_create()
				PhysicsServer3D.shape_set_data(shape_rid,
					{"radius": rayon_stade, "height": stature_stade})
				troncs_rid.append(shape_rid)
			else:
				troncs_rid.append(RID())
		_shapes_rid[String(type.nom)] = troncs_rid
		# LA DISTANCE DE RENDU VOYAGE AVEC L'ENTREE, jamais relue au moment de
		# poser : le lot ne connait que l'entree qu'on lui donne, et lui
		# faire retrouver l'espece rouvrirait une table a chaque plante posee.
		var distance := float(type.get("distance_rendu", 0.0))
		for entree in stades:
			if not entree.is_empty():
				entree["distance_rendu"] = distance
				entree["pieces"] = pieces_de(entree)
		if not produit.is_empty():
			produit["distance_rendu"] = distance
			produit["pieces"] = pieces_de(produit)
		_rendus[nom] = {"stades": stades, "produit": produit, "troncs": troncs}

# LE FUT D'UNE PLANTE : un cylindre du rayon declare par l'espece, haut comme la
# stature du stade, POSE SUR LE SOL -- une CylinderShape3D est centree sur son
# origine, il faut donc la remonter d'une demi-hauteur pour que sa base touche
# y = 0, la ou la plante est posee. Sans ce decalage la moitie du tronc serait
# enterree et l'autre flotterait.
#
# Rend null quand le rayon ou la stature est nul : une plante sans fut ne recoit
# aucun corps, ce qui est le cas de l'herbe et de tout stade de stature zero.
static func forme_de_tronc(rayon: float, hauteur: float) -> CylinderShape3D:
	if rayon <= 0.0 or hauteur <= 0.0:
		return null
	var forme := CylinderShape3D.new()
	forme.radius = rayon
	forme.height = hauteur
	return forme

# Un corps charge depuis un .glb ou une scene, avec son recentrage MESURE.
func _corps_depuis_chemin(chemin: String) -> Dictionary:
	if not ResourceLoader.exists(chemin):
		push_error("couvert.gd : modele introuvable '%s' -- ce qui l'utilise restera invisible" % chemin)
		return {}
	var scene := load(chemin) as PackedScene
	if scene == null:
		push_error("couvert.gd : '%s' n'est pas une scene instanciable" % chemin)
		return {}
	var decalage := recentrage(scene)
	if decalage.length() > 0.01:
		print("couvert : '%s' n'est pas centre sur son origine, recentre de %s a l'affichage" % [
			chemin.get_file(), decalage])
	return {"scene": scene, "decalage": decalage}

func _corps_touffe(hauteur: float, largeur: float, brins: int, couleur: Array) -> Dictionary:
	return {"maillage": maillage_touffe(hauteur, largeur, brins, couleur), "decalage": Vector3.ZERO}

func _corps_arbre(hauteur: float, couleur: Array) -> Dictionary:
	return {"maillage": maillage_arbre(hauteur, couleur), "decalage": Vector3.ZERO}

# LA TOUFFE : quelques lames verticales croisees, posees sur y = 0 et hautes comme
# la stature du stade. Elles se croisent en tournant autour de l'axe vertical, ce
# qui donne du volume sous n'importe quel angle sans qu'aucune ne soit orientee
# vers la camera -- une seule lame plate disparaitrait vue de profil.
#
# LES DEUX FACES SONT RENDUES (cull_mode desactive) : une lame vue de derriere
# serait invisible, et la moitie de la touffe manquerait selon l'angle. La normale
# pointe vers le haut plutot que sur le cote, sinon les lames s'assombrissent
# chacune differemment et la touffe scintille en tournant.
#
# AUCUN HASARD : les angles sont repartis regulierement. Deux touffes de meme
# stade sont identiques -- grossier, mais reproductible, et une variation
# aleatoire devrait passer par le RNG seede de l'etat, qui n'a rien a faire dans
# le rendu.
# SILHOUETTE ARBRE STYLISE : un CylinderMesh de Godot pour le tronc, un
# second CylinderMesh a top_radius=0 pour le cone de canopee. Deux surfaces
# dans un seul ArrayMesh, deux materiaux. Les primitives de Godot sont
# fermees et propres -- pas un sommet a fabriquer a la main.
#
# LE COMPTE DE SEGMENTS EST BAS ET C'EST OBLIGATOIRE. Le defaut d'un
# CylinderMesh de Godot est radial_segments=64, rings=4 : ~1000 triangles
# par arbre. Le maillage est PARTAGE par un MultiMesh, donc chaque arbre
# rendu paie ces triangles a l'ecran -- a quelques milliers d'arbres, le
# GPU dessine plusieurs MILLIONS de triangles pour des silhouettes qu'on
# voit de loin. A radial_segments=6, rings=1, un arbre pese ~36 triangles
# et la silhouette tronc + cone reste la meme. Un tronc a 6 cotes suffit :
# monter ce chiffre n'ajoute que du cout, jamais de la lecture a distance.
const SEGMENTS_ARBRE := 6
const ANNEAUX_ARBRE := 1

# TRONC : 30 % de la hauteur, rayon = 6 %. Base au sol (origine du
# CylinderMesh au centre, decale de h/2 vers le haut).
# CANOPEE : 70 % restants, rayon a la base = 23 %, pointe en haut.
static func maillage_arbre(hauteur: float, couleur: Array) -> ArrayMesh:
	var maillage := ArrayMesh.new()
	if hauteur <= 0.0:
		return maillage

	var h_tronc := hauteur * 0.30
	var r_tronc := hauteur * 0.06
	var h_canopee := hauteur * 0.70
	var r_canopee := hauteur * 0.23

	var tronc := CylinderMesh.new()
	tronc.top_radius = r_tronc
	tronc.bottom_radius = r_tronc
	tronc.height = h_tronc
	tronc.radial_segments = SEGMENTS_ARBRE
	tronc.rings = ANNEAUX_ARBRE
	var arrays_tronc := tronc.surface_get_arrays(0)
	_decaler_vertices(arrays_tronc, h_tronc * 0.5)
	var mat_tronc := StandardMaterial3D.new()
	mat_tronc.albedo_color = Color(0.35, 0.22, 0.13)
	maillage.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_tronc)
	maillage.surface_set_material(0, mat_tronc)

	var canopee := CylinderMesh.new()
	canopee.top_radius = 0.0
	canopee.bottom_radius = r_canopee
	canopee.height = h_canopee
	canopee.radial_segments = SEGMENTS_ARBRE
	canopee.rings = ANNEAUX_ARBRE
	var arrays_canopee := canopee.surface_get_arrays(0)
	_decaler_vertices(arrays_canopee, h_tronc + h_canopee * 0.5)
	var mat_canopee := StandardMaterial3D.new()
	mat_canopee.albedo_color = Color(float(couleur[0]), float(couleur[1]), float(couleur[2]))
	maillage.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_canopee)
	maillage.surface_set_material(1, mat_canopee)

	return maillage

# Un CylinderMesh de Godot a son origine au CENTRE. Pour poser une piece a
# une hauteur y donnee, on decale tous ses sommets. Modifie le tableau
# arrays en place.
static func _decaler_vertices(arrays: Array, dy: float) -> void:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(v.size()):
		v[i] += Vector3(0.0, dy, 0.0)
	arrays[Mesh.ARRAY_VERTEX] = v

static func maillage_touffe(hauteur: float, largeur: float, brins: int, couleur: Array) -> ArrayMesh:
	var sommets := PackedVector3Array()
	var normales := PackedVector3Array()
	var indices := PackedInt32Array()
	var combien := maxi(brins, 1)
	for i in range(combien):
		var angle := PI * float(i) / float(combien)
		var cote := Vector3(cos(angle), 0.0, sin(angle)) * largeur * 0.5
		# La lame se retrecit vers le haut : un rectangle plein fait un panneau,
		# un trapeze fait une feuille.
		var haut := cote * 0.3
		var base := sommets.size()
		sommets.append_array(PackedVector3Array([
			-cote, cote, haut + Vector3(0.0, hauteur, 0.0), -haut + Vector3(0.0, hauteur, 0.0)]))
		for _n in range(4):
			normales.append(Vector3.UP)
		indices.append_array(PackedInt32Array([
			base, base + 1, base + 2, base, base + 2, base + 3]))

	var tableaux := []
	tableaux.resize(Mesh.ARRAY_MAX)
	tableaux[Mesh.ARRAY_VERTEX] = sommets
	tableaux[Mesh.ARRAY_NORMAL] = normales
	tableaux[Mesh.ARRAY_INDEX] = indices

	var materiau := StandardMaterial3D.new()
	materiau.albedo_color = Color(float(couleur[0]), float(couleur[1]), float(couleur[2]))
	materiau.cull_mode = BaseMaterial3D.CULL_DISABLED

	var maillage := ArrayMesh.new()
	maillage.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tableaux)
	maillage.surface_set_material(0, materiau)
	return maillage

# CE QU'IL FAUT AJOUTER A UN MODELE POUR QU'IL TOMBE OU ON LE POSE : de quoi
# ramener son empreinte au sol sur l'origine et sa base sur y = 0. Rend
# Vector3.ZERO pour un modele sans maillage -- inventer un decalage serait pire
# que de n'en poser aucun.
static func recentrage(scene: PackedScene) -> Vector3:
	var noeud := scene.instantiate() as Node3D
	if noeud == null:
		return Vector3.ZERO
	var boite: Variant = englobante(noeud, Transform3D.IDENTITY)
	noeud.free()
	if boite == null:
		return Vector3.ZERO
	var b: AABB = boite
	return Vector3(
		-(b.position.x + b.size.x * 0.5),
		-b.position.y,
		-(b.position.z + b.size.z * 0.5))

# L'encombrement reel d'un arbre de noeuds, transforms enchainees. Rend null quand
# il ne porte aucun maillage -- jamais une boite vide, qu'un appelant prendrait
# pour un objet a l'origine.
static func englobante(noeud: Node, parent: Transform3D) -> Variant:
	var local := parent
	if noeud is Node3D:
		local = parent * (noeud as Node3D).transform
	var boite: Variant = null
	if noeud is MeshInstance3D and (noeud as MeshInstance3D).mesh != null:
		boite = local * (noeud as MeshInstance3D).mesh.get_aabb()
	for enfant in noeud.get_children():
		var celle: Variant = englobante(enfant, local)
		if celle == null:
			continue
		boite = celle if boite == null else (boite as AABB).merge(celle)
	return boite

# LES PIECES D'UN MODELE : ses maillages, chacun avec la transform qu'il porte
# DANS le modele, decalage de recentrage compris. Un lot de rendu ne sait poser
# qu'un maillage a la fois ; un `.glb` en porte souvent plusieurs.
#
# LE MODELE EST INSTANCIE UNE FOIS, ICI, PUIS LIBERE : ce qu'on garde est une
# liste de ressources et de transforms, jamais un arbre de noeuds. C'est ce qui
# permet a mille plantes de ne rien instancier du tout.
#
# LE MATERIAU SUIT LA PIECE quand il est pose sur le noeud plutot que sur le
# maillage : un `.glb` peut faire l'un ou l'autre, et le perdre rendrait la
# plante grise sans qu'aucune erreur ne sorte.
static func pieces_de(entree: Dictionary) -> Array:
	if entree.is_empty():
		return []
	var decalage: Vector3 = entree.get("decalage", Vector3.ZERO)
	if entree.has("maillage"):
		return [{
			"maillage": entree.maillage,
			"pose": Transform3D(Basis(), decalage),
			"materiau": null,
		}]
	if not entree.has("scene"):
		return []
	var corps := (entree.scene as PackedScene).instantiate() as Node3D
	if corps == null:
		return []
	var pieces: Array = []
	ramasser_pieces(corps, Transform3D(corps.transform.basis, decalage), pieces)
	corps.free()
	return pieces

static func ramasser_pieces(noeud: Node, pose: Transform3D, pieces: Array) -> void:
	if noeud is MeshInstance3D and (noeud as MeshInstance3D).mesh != null:
		var vue := noeud as MeshInstance3D
		var materiau: Material = vue.material_override
		if materiau == null and vue.get_surface_override_material_count() > 0:
			materiau = vue.get_surface_override_material(0)
		pieces.append({"maillage": vue.mesh, "pose": pose, "materiau": materiau})
	for enfant in noeud.get_children():
		var locale := pose
		if enfant is Node3D:
			locale = pose * (enfant as Node3D).transform
		ramasser_pieces(enfant, locale, pieces)

# ---- Le rendu ----

func _plante_par_id(id: String) -> Variant:
	for plante in _etat.plantes:
		if String(plante.id) == id:
			return plante
	return null

func _poser_plante(plante: Dictionary) -> void:
	var id := String(plante.id)
	_poses[id] = plante.position
	var type := Vegetation.type_de(plante, _types)
	if type.is_empty():
		return
	_poser_modele(id, String(type.nom), Vegetation.numero_de_stade(plante, type))

# L'ECHANGE DE CORPS, et c'est tout ce qu'un changement de stade fait a l'ecran :
# la plante sort du lot de son ancien stade et entre dans celui du nouveau. Son
# tronc suit par le meme geste -- une pousse ne barre pas le passage comme un
# arbre mature.
func _poser_modele(id: String, espece: String, numero: int) -> void:
	_radier(id)
	# LE CORPS PHYSIQUE N'EST PLUS POSE ICI. Il vit dans _bascule_rendu, qui
	# decide selon la distance a l'observateur. On invalide juste l'etat
	# courant pour que le prochain tick reevalue.
	if _corps_actifs.has(id):
		_liberer_corps(id)
	if not _rendus.has(espece):
		return
	var rendu: Dictionary = _rendus[espece]
	var stades: Array = rendu.stades
	if numero < 1 or numero > stades.size():
		return
	_inscrire(_cle_de_lot(espece, str(numero)), stades[numero - 1], id)

# POSE UN CORPS PHYSIQUE STATIQUE POUR LE TRONC via PhysicsServer3D pur.
# Aucun noeud n'est cree -- le corps existe uniquement dans le serveur
# physique. Il bloque le personnage comme un StaticBody3D le ferait, mais
# sans le cout d'un noeud dans l'arbre de scene (mesure ~5x moins cher
# qu'un StaticBody3D a 2827 corps actifs).
#
# LE BODY EST POSITIONNE A `position + (0, stature/2, 0)` : la shape
# CylinderShape3D est centree sur son origine, il faut la remonter d'une
# demi-hauteur pour que sa base repose au sol (`position` est au pied de
# l'arbre).
#
# BODY_MODE_STATIC obligatoire : le defaut de body_create est BODY_MODE_RIGID,
# qui pousserait le tronc a la moindre collision.
# body_set_space obligatoire : sans ca le body existe mais n'est dans aucune
# simulation, silencieusement.
func _poser_corps(id: String, espece: String, numero: int, position: Vector3) -> void:
	if not _shapes_rid.has(espece):
		return
	var shapes: Array = _shapes_rid[espece]
	if numero < 1 or numero > shapes.size():
		return
	var shape_rid: RID = shapes[numero - 1]
	if not shape_rid.is_valid():
		return
	var stades: Array = _types[espece].stades
	var stature := float(stades[numero - 1].get("stature", 0.0))
	var body_rid := PhysicsServer3D.body_create()
	_stat_body_create += 1
	PhysicsServer3D.body_set_mode(body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body_rid, get_world_3d().space)
	PhysicsServer3D.body_add_shape(body_rid, shape_rid)
	# LAYER ET MASK POSES EXPLICITEMENT a 1. La doc dit que body_create()
	# initialise deja layer=1, mask=1 -- mais rien de devine : les lignes
	# sont ecrites pour que le contrat de collision (couche 1, comme les
	# StaticBody3D par defaut du reste du projet) soit lisible ici sans
	# supposer un defaut de moteur.
	PhysicsServer3D.body_set_collision_layer(body_rid, 1)
	PhysicsServer3D.body_set_collision_mask(body_rid, 1)
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM,
		Transform3D(Basis(), position + Vector3(0.0, stature * 0.5, 0.0)))
	_corps_actifs[id] = {"rid": body_rid, "numero": numero}

# LIBERE LE BODY RID (immediat, pas de queue). L'appelant peut immediatement
# recreer un body au meme id sans risque de sur-population transitoire.
func _liberer_corps(id: String) -> void:
	if not _corps_actifs.has(id):
		return
	var body_rid: RID = _corps_actifs[id].rid
	if body_rid.is_valid():
		PhysicsServer3D.free_rid(body_rid)
		_stat_free_rid += 1
	_corps_actifs.erase(id)

# NETTOYAGE FINAL : libere tous les RID (bodies + shapes) a la destruction
# du Couvert. Sans ca, chaque RID cree fuite jusqu'a la fermeture du jeu --
# invisible tant que la scene n'est pas rechargee.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for entree in _corps_actifs.values():
			var rid: RID = entree.rid
			if rid.is_valid():
				PhysicsServer3D.free_rid(rid)
		_corps_actifs.clear()
		for shapes in _shapes_rid.values():
			for shape_rid in shapes:
				if (shape_rid as RID).is_valid():
					PhysicsServer3D.free_rid(shape_rid)
		_shapes_rid.clear()

# ---- LES LOTS DE RENDU ----
#
# UNE PLANTE N'EST PLUS UN OBJET A DESSINER, C'EST UNE LIGNE DANS UN LOT. Toutes
# les plantes d'une meme espece au meme stade sont le MEME modele a des positions
# differentes -- rien ne les distingue, ni couleur, ni echelle, ni rotation. Un
# MultiMesh porte donc le maillage UNE fois et la liste des positions, et la carte
# graphique dessine le lot entier d'un seul ordre au lieu d'un ordre par plante.
# Ce qu'on abandonne en echange : une ligne de lot n'est pas un noeud, elle ne
# porte ni script, ni enfant, ni reglage propre.
#
# UN MULTIMESH PAR MAILLAGE : un `.glb` est un arbre de noeuds qui peut en porter
# plusieurs, et un MultiMesh n'en connait qu'un. Chaque piece garde la transform
# qu'elle avait dans le modele, composee avec la position de la plante.
#
# LA DISTANCE DE RENDU DEVIENT CELLE DU LOT, et non plus celle de la plante : un
# lot se cache ou se dessine en bloc. C'est le prix du regroupement, et c'est
# pourquoi un lot reste une espece a un stade -- regrouper toute la carte ferait
# disparaitre une foret d'un coup.
#
# LE RETRAIT NE DECALE RIEN : la derniere ligne prend la place de celle qui part.
# Recompacter la liste ferait payer la population a chaque mort.
func _cle_de_lot(espece: String, stade: String) -> String:
	return "%s#%s" % [espece, stade]

# Le lot d'une cle, cree au premier besoin. Rend un Dictionary VIDE quand l'entree
# ne porte aucune piece -- un modele manquant a deja ete signale au chargement, et
# la plante reste alors simplement invisible.
func _lot(cle: String, entree: Dictionary) -> Dictionary:
	if _lots.has(cle):
		return _lots[cle]
	var pieces: Array = entree.get("pieces", [])
	if pieces.is_empty():
		return {}
	var instances: Array = []
	for i in range(pieces.size()):
		var piece: Dictionary = pieces[i]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = piece.maillage
		multi.instance_count = 0
		var noeud := MultiMeshInstance3D.new()
		# Nomme par son RANG, jamais par l'espece : le nom d'un noeud de scene n'a
		# pas a porter un nom de contenu.
		noeud.name = "lot_%d_%d" % [_lots.size(), i]
		noeud.multimesh = multi
		# INTERPOLATION PHYSIQUE COUPEE sur les MMI : set_instance_transform
		# est appele depuis _process (le tick du couvert), jamais depuis
		# _physics_process. Sans ce coupe-circuit, Godot rale "MultiMesh
		# interpolation is being triggered from outside physics process" a
		# chaque tick. Les transforms des plantes ne bougent QUE aux naissances,
		# morts et changements de stade -- rien qui doive s'interpoler entre
		# deux frames physiques.
		noeud.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		if piece.get("materiau") != null:
			noeud.material_override = piece.materiau
		poser_distance_rendu(noeud, float(entree.get("distance_rendu", 0.0)))
		add_child(noeud)
		instances.append({"noeud": noeud, "pose": piece.pose})
	var lot := {"instances": instances, "ids": [], "poses": [], "index": {}, "capacite": 0}
	_lots[cle] = lot
	return lot

func _inscrire(cle: String, entree: Dictionary, id: String) -> void:
	var lot := _lot(cle, entree)
	if lot.is_empty():
		return
	var rang: int = (lot.ids as Array).size()
	(lot.ids as Array).append(id)
	(lot.poses as Array).append(_poses.get(id, Vector3.ZERO))
	(lot.index as Dictionary)[id] = rang
	_lot_de[id] = cle
	_ecrire_lot(lot, rang)
	_occl_dirty = true

func _radier(id: String) -> void:
	if not _lot_de.has(id):
		return
	var lot: Dictionary = _lots[_lot_de[id]]
	_lot_de.erase(id)
	var rang: int = int((lot.index as Dictionary)[id])
	(lot.index as Dictionary).erase(id)
	var dernier: int = (lot.ids as Array).size() - 1
	if rang != dernier:
		var deplace := String((lot.ids as Array)[dernier])
		(lot.ids as Array)[rang] = deplace
		(lot.poses as Array)[rang] = (lot.poses as Array)[dernier]
		(lot.index as Dictionary)[deplace] = rang
	(lot.ids as Array).resize(dernier)
	(lot.poses as Array).resize(dernier)
	_ecrire_lot(lot, rang if rang != dernier else -1)
	_occl_dirty = true

# Ecrit le lot dans ses MultiMesh. `rang` designe la seule ligne qui a bouge, -1
# n'en redresse aucune.
#
# LA CAPACITE DOUBLE, ELLE NE SUIT PAS LE COMPTE : agrandir un MultiMesh
# reconstruit son tampon, et le faire a chaque plante couterait plus cher que ce
# que le regroupement fait gagner. Un agrandissement reecrit tout le lot, parce
# que le contenu du tampon neuf n'est garanti nulle part.
func _ecrire_lot(lot: Dictionary, rang: int) -> void:
	var combien: int = (lot.ids as Array).size()
	var tout := false
	if combien > int(lot.capacite):
		var capacite: int = maxi(int(lot.capacite), 32)
		while combien > capacite:
			capacite *= 2
		lot.capacite = capacite
		tout = true
	for instance in lot.instances:
		var multi: MultiMesh = (instance.noeud as MultiMeshInstance3D).multimesh
		if tout:
			multi.instance_count = int(lot.capacite)
			_stat_realloc += 1
			for i in range(combien):
				multi.set_instance_transform(i, pose_de_ligne(
					(lot.poses as Array)[i], instance.pose))
				_stat_set_transform += 1
		elif rang >= 0 and rang < combien:
			multi.set_instance_transform(rang, pose_de_ligne(
				(lot.poses as Array)[rang], instance.pose))
			_stat_set_transform += 1
		multi.visible_instance_count = combien

# La transform d'une ligne : la position de la plante, portant la piece la ou elle
# etait dans le modele.
@warning_ignore("shadowed_variable_base_class")
static func pose_de_ligne(position: Vector3, piece: Transform3D) -> Transform3D:
	return Transform3D(Basis(), position) * piece

# Combien de lignes un lot porte, et quels lots existent. Pour les tests et les
# traces : rien du rendu n'en depend.
func lignes_du_lot(cle: String) -> int:
	if not _lots.has(cle):
		return 0
	return ((_lots[cle] as Dictionary).ids as Array).size()

func lots() -> Dictionary:
	return _lots

# LA DISTANCE DE RENDU, POSEE SUR CHAQUE PIECE QUI SE DESSINE. `visibility_range_
# end` appartient a GeometryInstance3D, pas a Node3D : un `.glb` est un Node3D qui
# en porte plusieurs, la poser sur sa racine ne toucherait rien. On descend donc
# l'arbre entier.
#
# A ZERO, RIEN N'EST ECRIT : la propriete garde son defaut, tout se dessine, et une
# espece qui ne declare pas de distance se comporte exactement comme avant.
#
# LA CAMERA EN DECIDE SEULE. Aucun appelant n'a besoin de savoir ou est le joueur,
# et c'est ce qui rend le geste valable pour mille types d'objets sans un champ a
# remplir sur chacun.
static func poser_distance_rendu(corps: Node, distance: float) -> int:
	if distance <= 0.0 or corps == null:
		return 0
	var poses := 0
	var a_visiter: Array = [corps]
	while not a_visiter.is_empty():
		var noeud: Node = a_visiter.pop_back()
		if noeud is GeometryInstance3D:
			(noeud as GeometryInstance3D).visibility_range_end = distance
			poses += 1
		for enfant in noeud.get_children():
			a_visiter.append(enfant)
	return poses

func _retirer_plante(id: String) -> void:
	_radier(id)
	_poses.erase(id)
	_liberer_corps(id)

func _poser_graine(id: String) -> void:
	if _lot_de.has(id):
		return
	for graine in _etat.graines:
		if String(graine.id) != id:
			continue
		var espece := String(graine.type_plante)
		if not _rendus.has(espece):
			return
		_poses[id] = graine.position
		_inscrire(_cle_de_lot(espece, "produit"), _rendus[espece].produit, id)
		return

# Retire le corps d'un produit perdu OU ramasse. Le ramassage par les unites
# n'existe pas encore -- Vegetation.ramasser attend son appelant -- mais le geste
# est le meme des deux cotes, et il est pose ici pour que ce futur cablage n'ait
# pas a fouiller le rendu.
func retirer_graine(id: String) -> void:
	_radier(id)
	_poses.erase(id)

# ---- Culling COMPLET par distance a l'observateur ----
#
# HORS DU RAYON `rayon_collision_metres`, la plante N'EST NI DESSINEE NI
# SOLIDE : aucune ligne dans un lot MultiMesh, aucun StaticBody3D, aucun
# Node3D porteur. La simulation continue en donnee -- ombre, croissance,
# reproduction, mort -- exactement comme avec un joueur present. Ce que ce
# cycle fait, c'est basculer le rendu et la collision selon la distance,
# comme manager_proto le fait pour ses producteurs et ses carres.
#
# APPELE PAR TICK (au bout de _process). L'index de scripts/monde.gd:
# choses_dans_rayon range par case : le cout suit le RAYON, pas la population
# totale. Voir MESURES_COUVERT.md §4.
#
# TROIS ETATS PAR PLANTE :
#  - hors rayon : rien pose. La plante n'existe que dans etat.plantes.
#  - dans rayon, stade non-fertile : ligne dans un lot MMI. Aucun corps.
#  - dans rayon, stade fertile a rayon_collision > 0 : ligne MMI + corps
#    PhysicsServer3D. Aucun Node3D par plante.
#
# LE STADE EST STOCKE dans _lot_de (implicite via _lot_de[id] = cle_du_lot)
# et dans _corps_actifs.numero (pour detecter les changements de hauteur de
# corps quand la stature change). Un changement de stade dans le rayon =
# radier l'ancien lot, inscrire dans le nouveau, reposer le corps.
func _bascule_rendu() -> void:
	if _observateur == null:
		return
	if _etat.is_empty():
		return
	var pos_obs: Vector3 = _observateur.global_position
	_derniere_pos_bascule = pos_obs
	var doit: Dictionary = {}
	for entree in _etat.monde.choses_dans_rayon(pos_obs, rayon_collision_metres):
		var plante: Dictionary = entree.chose
		if Vegetation.est_disparue(plante, _config):
			continue
		var type: Dictionary = Vegetation.type_de(plante, _types)
		if type.is_empty():
			continue
		var espece := String(type.nom)
		if not _rendus.has(espece):
			continue
		var numero := Vegetation.numero_de_stade(plante, type)
		if numero < 1:
			continue
		var stades: Array = _rendus[espece].stades
		if numero > stades.size():
			continue
		var id := String(plante.id)
		doit[id] = true
		# RENDU : inscrit dans le bon lot si absent ou dans un autre lot
		# (changement de stade -> changement de lot).
		var cle_lot := _cle_de_lot(espece, str(numero))
		if String(_lot_de.get(id, "")) != cle_lot:
			_radier(id)
			_poses[id] = plante.position
			_inscrire(cle_lot, stades[numero - 1], id)
		# COLLISION : pose le corps si l'espece declare une forme non nulle
		# pour ce stade. Repose si le stade a change (hauteur suit stature,
		# nouveau body avec la shape du bon stade).
		var shapes: Array = _shapes_rid.get(espece, [])
		var a_une_shape := numero <= shapes.size() and (shapes[numero - 1] as RID).is_valid()
		if a_une_shape:
			var actuel: int = int(_corps_actifs.get(id, {}).get("numero", -1))
			if actuel != numero:
				_liberer_corps(id)
				_poser_corps(id, espece, numero, plante.position)
		elif _corps_actifs.has(id):
			# Passe d'un stade a corps vers un stade sans corps.
			_liberer_corps(id)
	# LES SORTIES : plantes actuellement inscrites qui ne sont plus dans le
	# rayon. Radier du lot, liberer le corps PhysicsServer.
	var inscrits := _lot_de.keys().duplicate()
	for id in inscrits:
		if not doit.has(id):
			_radier(id)
			_liberer_corps(id)
			_poses.erase(id)
	# L'OCCLUDEUR NE SE REFAIT QUE SI LA POPULATION RENDUE A CHANGE ce tour
	# (inscription, radiation, changement de stade l'ont marque). Immobile en
	# foret etablie, rien ne change et rien ne se reconstruit.
	if _occl_dirty:
		_reconstruire_occludeur_arbres()
		_occl_dirty = false

# REFAIT L'OCCLUDEUR DES CANOPEES a partir des lots actuellement rendus. Une boite
# par canopee d'arbre (espece a tronc) ; l'herbe, sans canopee opaque, n'occulte
# rien et n'y entre pas. Sommets en coordonnees monde : ce noeud vit dans le
# repere local du GridMap, a l'identite (verifie au _ready), donc local = monde.
func _reconstruire_occludeur_arbres() -> void:
	if _occl_arbres != null and is_instance_valid(_occl_arbres):
		_occl_arbres.queue_free()
		_occl_arbres = null
	var sommets := PackedVector3Array()
	var indices := PackedInt32Array()
	var faces := PackedInt32Array([
		0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4,
		1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7])
	var base := 0
	for cle in _lots:
		var parts := String(cle).split("#")
		if parts.size() != 2:
			continue
		var espece := String(parts[0])
		if not _types.has(espece):
			continue
		var type: Dictionary = _types[espece]
		if float(type.get("rayon_collision", 0.0)) <= 0.0:
			continue
		var numero := int(parts[1])
		var stades: Array = type.stades
		if numero < 1 or numero > stades.size():
			continue
		var h := float((stades[numero - 1] as Dictionary).get("stature", 0.0))
		if h <= 0.0:
			continue
		# La canopee de maillage_arbre va de y=h*0.3 a y=h, rayon ~h*0.23 : la
		# boite s'y cale, centre a h*0.65.
		var dx := h * 0.23
		var dy := h * 0.35
		var cy := h * 0.65
		var lot: Dictionary = _lots[cle]
		for p in (lot.poses as Array):
			var c := (p as Vector3) + Vector3(0.0, cy, 0.0)
			sommets.append(c + Vector3(-dx, -dy, -dx))
			sommets.append(c + Vector3(dx, -dy, -dx))
			sommets.append(c + Vector3(dx, -dy, dx))
			sommets.append(c + Vector3(-dx, -dy, dx))
			sommets.append(c + Vector3(-dx, dy, -dx))
			sommets.append(c + Vector3(dx, dy, -dx))
			sommets.append(c + Vector3(dx, dy, dx))
			sommets.append(c + Vector3(-dx, dy, dx))
			for idx in faces:
				indices.append(base + idx)
			base += 8
	if sommets.is_empty():
		return
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(sommets, indices)
	var inst := OccluderInstance3D.new()
	inst.occluder = occ
	add_child(inst)
	_occl_arbres = inst
