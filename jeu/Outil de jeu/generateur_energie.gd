extends RigidBody3D

# BANC "test_ennemi2 Mother box" -- LE GENERATEUR D'ENERGIE, pondu par le
# geniteur (voir gestation_energie.gd, morceau suivant). Petit cube 1 m
# avec 3 vies. Recoit des frappes via Frappe.frapper (framework), affiche
# sa vie en barre 3D via barre_de_vie.gdshader (patron vie_ennemi.gd).
# Meurt a 0 (queue_free).
#
# NE COMPOSE PAS LA GESTATION : ce fichier ne connait pas son producteur.
# Il vit et meurt seul, s'inscrit dans le groupe "generateur_energie" pour
# que le banc de gestation du geniteur puisse compter les vivants sans
# reference explicite. Meme patron que "cube_violet" dans vie_ennemi.gd.
#
# NE REINVENTE PAS LE CALCUL DE DEGATS : Frappe.frapper() (framework)
# soustrait la reserve, bornee a zero -- ce fichier ne fait que fournir
# une reserve "vie" a frapper, lire ce qu'il en reste, rafraichir la
# barre et se detruire.

const Frappe = preload("res://scripts/frappe.gd")
const Perception = preload("res://scripts/perception.gd")

# CATALOGUE LOCAL canaux perceptifs (patron transporteur.gd:47-49, meme
# convention que mother_cube.gd). Vue en cone_oriente, angle absent =>
# sphere pure au rayon portee_vision.
const CATALOGUE_CANAUX := {
	"vue": {"geometrie": "cone_oriente"},
}

@export var vie_max: float = 3.0
# DUREE DE VIE : le generateur meurt automatiquement apres cette duree.
# 300 s = 5 min par defaut. Reglable dans l'inspecteur.
@export var duree_vie_secondes: float = 300.0
# VIE DE CADAVRE : apres _mourir(), la reserve vie est reinitialisee a
# cette valeur. Les frappes suivantes la font descendre ; a 0 -> queue_free.
# Regle Yael : un cadavre encaisse 7 coups avant destruction finale.
@export var vie_cadavre: float = 7.0
# STOCK CADAVRE : matiere puisable par un AUTRE generateur enrole qui
# vient manger le cadavre. Separe de vie_cadavre (celle-ci est la
# resistance aux frappes du joueur). Un generateur enrole preleve
# progressivement ce stock ; a 0 -> le cadavre disparait completement
# (queue_free). Regle Yael 2026-08-22 : valeur separee, cumul possible
# sur plusieurs sources pour atteindre cout_prelevement=10.
@export var stock_cadavre_initial: float = 10.0
# ENROLEMENT (morceau 2) : le generateur naissant marche vers le geniteur,
# preleve 10 stock au contact, attend `secondes_ponte`, pond un carre rouge
# derriere lui, recommence -- jusqu'a mort naturelle 5 min. Instinct
# immediat (voir choix Yael 2026-08-22 : ouvriere SCV, pas d'attente).
@export var vitesse_marche: float = 3.0
@export var distance_contact_geniteur: float = 4.0
@export var cout_prelevement: float = 10.0
@export var secondes_ponte: float = 60.0
# PORTEE VISION : le generateur voit toutes les entites (geniteur ET
# cadavres) dans ce rayon via Perception.percevoir. Choisit la plus
# proche (tri distance). Voir CATALOGUE_CANAUX + percevoir_source_matiere.
@export var portee_vision: float = 30.0
# DISTANCE DE CONTACT CADAVRE : plus courte que celle du geniteur (cadavre
# 1 m vs geniteur 6 m). 1.5 m couvre la marge d'inertie physique.
@export var distance_contact_cadavre: float = 1.5
# INTERVALLE DE PERCEPTION EN ATTENTE : la perception coute (parcours de
# l'index spatial, filtre saillance). En attendant qu'une source apparaisse,
# re-scanner chaque frame gaspille du CPU (bug B6, 2026-08-22 : si le
# geniteur a stock_puisable=0, boucle ATTENTE 60 fps sans production).
# 0.5s : reactif sans etre couteux.
@export var secondes_par_perception: float = 0.5
# OFFSET PONTE : distance a laquelle le carre rouge est pose "derriere"
# le generateur, direction OPPOSEE au geniteur. Le generateur fait 1 m,
# le carre rouge 0.4 m -- 1.0 m suffit pour ne pas s'imbriquer.
@export var offset_carre_rouge: float = 1.0

const CarreRougeScene = preload("res://jeu/Outil de jeu/carre_rouge.tscn")

enum {
	ETAT_ATTENTE,
	ETAT_VERS_SOURCE,
	ETAT_COLLE,
	ETAT_POND,
}
var _etat: int = ETAT_ATTENTE
# SOURCE : geniteur OU cadavre (autre generateur mort). Choisie a
# ETAT_ATTENTE par perception + saillance sur "stock_puisable > 0", tri
# par distance croissante. is_instance_valid teste avant chaque usage.
var _source: Node3D = null
var _secondes_dans_colle: float = 0.0
var _secondes_depuis_perception: float = 999.0  # premiere frame -> perception immediate
var _cout_paye_pour_ce_cycle: bool = false
# STOCK DEJA CUMULE DANS CE CYCLE : le generateur peut puiser sur
# plusieurs sources jusqu'a atteindre cout_prelevement. Reset a chaque
# nouveau cycle (retour VERS_SOURCE).
var _matiere_cumulee: float = 0.0
# CADAVRE : entite dans le monde + reserve courante.
var _stock_cadavre_courant: float = 0.0
var _entite_cadavre: Dictionary = {}
var _monde_partage: Node = null

var entite: Dictionary
var _barre_vie: MeshInstance3D
var _materiau_vie: ShaderMaterial
# _est_cadavre : passe a true dans _mourir(). Bascule le comportement de
# subir_frappe (a 0 -> queue_free au lieu de _mourir), et rend _mourir()
# idempotent (le Timer 5min peut re-declencher, on skip).
var _est_cadavre: bool = false

# MORT CIVILE : le generateur reste sur place, barre a 0, ne bouge plus,
# devient une RESSOURCE (groupe "ressource", cablage transporteur futur).
# Il quitte le groupe "generateur_energie" pour que le compteur max_vivants
# du geniteur en tienne compte et autorise une nouvelle ponte.
#
# EXCEPTION DOCTRINALE au CLAUDE.md "Freeze/vol/teleportation interdits
# comme reponse a un probleme de mouvement" : ici, freeze n'est PAS un
# contournement de bug -- c'est le CONTRAT gameplay explicitement demande
# par Yael ("le generateur mort ne bouge plus, devient une ressource").
# La regle CLAUDE.md vise les fixes de bugs de steering deguises en
# freeze, pas les changements d'etat gameplay documentes.
#
# DECLAREE AVANT _ready() par prudence : forward reference dans un
# Timer.timeout.connect(_mourir) peut declencher un faux parse error
# selon les versions/cache de Godot (observe le 2026-08-22 chez Yael --
# headless parsait sans probleme, editeur non). Ordre lexical robuste.
func _mourir() -> void:
	if _est_cadavre:
		return  # idempotent : Timer 5 min ne re-reinitialise pas la vie
	_est_cadavre = true
	remove_from_group("generateur_energie")
	add_to_group("ressource")
	freeze = true
	# Cache la barre de vie -- le cadavre n'a plus de "vie" visible.
	var noeud_barre := get_node_or_null("BarreDeVie") as Node3D
	if noeud_barre != null:
		noeud_barre.visible = false
	# Assombrit le cube (bleu terne) : signale visuellement l'etat cadavre.
	# Duplique le materiau pour ne pas teindre les autres generateurs qui
	# partagent la meme sub_resource dans la scene.
	var coeur := get_node_or_null("Coeur") as MeshInstance3D
	if coeur != null and coeur.mesh != null:
		var mat := coeur.mesh.surface_get_material(0)
		if mat != null:
			var mat_terne: StandardMaterial3D = (mat.duplicate() as StandardMaterial3D)
			if mat_terne != null:
				mat_terne.albedo_color = Color(0.12, 0.22, 0.4, 1)
				mat_terne.emission = Color(0.15, 0.3, 0.55, 1)
				mat_terne.emission_energy_multiplier = 0.5
				coeur.set_surface_override_material(0, mat_terne)
	# Reset la reserve vie pour la phase cadavre : les frappes suivantes
	# la font descendre a 0, alors seulement queue_free.
	entite.proprietes.reserves.vie.reserve = vie_cadavre
	entite.proprietes.reserves.vie.capacite = vie_cadavre
	# INSCRIPTION CADAVRE AU MONDE PARTAGE : les autres generateurs enroles
	# le percoivent comme source de matiere (propriete stock_puisable). Sans
	# cette inscription, aucun percepteur ne le trouve. Meme patron
	# carre_rouge.gd:_ready.
	_stock_cadavre_courant = stock_cadavre_initial
	_entite_cadavre = {
		"id": str(get_instance_id()) + "_cadavre",
		"position": global_position,
		"proprietes": {
			"stock_puisable": _stock_cadavre_courant,
		},
		"noeud": self,
	}
	if _monde_partage != null:
		_monde_partage.monde.ajouter(_entite_cadavre, "cadavre_generateur", global_position)
	# EXCEPTION COLLISION AVEC LE GENITEUR : le cadavre est freeze=true,
	# ne bougera plus. S'il tombe sur la route du geniteur, il peut le
	# bloquer physiquement (bug B5, 2026-08-22). L'exception fait passer
	# le geniteur A TRAVERS le cadavre. Les autres corps (generateurs
	# vivants, joueur, mother cube) continuent a collisonner normalement.
	var geniteur_node := get_tree().get_first_node_in_group("geniteur")
	if geniteur_node != null and geniteur_node is CollisionObject3D:
		var g_co: CollisionObject3D = geniteur_node
		g_co.add_collision_exception_with(self)

# API publique -- utilisee UNIQUEMENT en phase cadavre (avant, le
# generateur ne porte pas de stock puisable). Preleve dans le stock
# cadavre, retourne la quantite REELLEMENT prise (bornee au disponible).
# Quand le stock atteint 0 -> retrait du monde + queue_free (Yael 2026-08-22 :
# "Si le stock, c'est la totalite, ca fait disparaitre le corps").
func preleve_stock_puisable(quantite: float) -> float:
	if not _est_cadavre:
		return 0.0  # generateur vivant : rien a puiser ici
	var pris: float = minf(quantite, _stock_cadavre_courant)
	_stock_cadavre_courant = _stock_cadavre_courant - pris
	if not _entite_cadavre.is_empty():
		_entite_cadavre.proprietes["stock_puisable"] = _stock_cadavre_courant
	if _stock_cadavre_courant <= 0.0:
		# Disparition finale : retrait du monde partage puis queue_free.
		if _monde_partage != null and not _entite_cadavre.is_empty():
			_monde_partage.monde.retirer(_entite_cadavre.id)
		queue_free()
	return pris

func _ready() -> void:
	add_to_group("generateur_energie")
	# TIMER DE MORT NATURELLE : un seul Timer par generateur, cohérent avec
	# le geniteur lui-même (peu d'individus : 4 max par geniteur, ~40
	# total prevus). Le canevas champ scalaire est reserve aux populations
	# de milliers (herbe, lichen) -- ici Timer.one_shot suffit.
	# MORT NATURELLE => _mourir() (comme frappe finale), PAS queue_free
	# direct : un generateur mort reste sur place comme ressource.
	var timer_mort := Timer.new()
	timer_mort.wait_time = duree_vie_secondes
	timer_mort.one_shot = true
	timer_mort.autostart = true
	timer_mort.timeout.connect(_mourir)
	add_child(timer_mort)
	entite = {
		"id": str(get_instance_id()),
		"position": global_position,
		"proprietes": {
			"reserves": {
				"vie": {"reserve": vie_max, "capacite": vie_max},
			},
			# CANAUX PERCEPTIFS : le generateur voit les sources de matiere
			# (geniteur, cadavres) dans son rayon portee_vision. Meme patron
			# que transporteur.gd et mother_cube.gd.
			"canaux": ["vue"],
			"canaux_config": {
				"vue": {"portee": portee_vision, "sensibilite": 1.0, "seuil": 0.0},
			},
		},
		"noeud": self,
	}
	_barre_vie = get_node("BarreDeVie/Barre") as MeshInstance3D
	# DUPLIQUE le materiau pour ne pas partager la fraction entre plusieurs
	# generateurs -- teindre l'un ne teint pas les autres. Meme patron que
	# geniteur.gd:_ready et vie_ennemi.gd:_ready.
	_materiau_vie = _barre_vie.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre_vie.set_surface_override_material(0, _materiau_vie)
	_rafraichir_barre()
	# RESOLUTION MONDE PARTAGE : sans lui, aucune perception ni inscription
	# cadavre. Un generateur qui n'en trouve pas se rabat sur "ne trouve
	# aucune source" (percevoir_source_matiere rend []).
	_monde_partage = get_tree().get_first_node_in_group("monde_partage")

func _process(delta: float) -> void:
	# CADAVRE : ne bouge plus, ne pond plus. Le corps reste comme ressource
	# puisable par les autres generateurs (via preleve_stock_puisable).
	if _est_cadavre:
		return
	# Synchro position monde pour perception (patron transporteur.gd:156).
	entite["position"] = global_position
	_secondes_depuis_perception += delta
	match _etat:
		ETAT_ATTENTE:
			_faire_attente()
		ETAT_VERS_SOURCE:
			_faire_vers_source(delta)
		ETAT_COLLE:
			_faire_colle(delta)
		ETAT_POND:
			_faire_pond()

# ATTENTE : cherche une source de matiere (geniteur, cadavres). Le plus
# proche gagne. Si rien percu, reste immobile (arret velocite horizontale)
# jusqu'a apparition d'une source.
func _faire_attente() -> void:
	linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)
	# Throttle : ne perceptionne qu'une fois toutes les secondes_par_perception.
	if _secondes_depuis_perception < secondes_par_perception:
		return
	_secondes_depuis_perception = 0.0
	var vus: Array = percevoir_source_matiere()
	if vus.is_empty():
		return
	var noeud = vus[0].chose.get("noeud", null)
	if noeud == null or not is_instance_valid(noeud) or not (noeud is Node3D):
		return
	_source = noeud as Node3D
	_etat = ETAT_VERS_SOURCE
	# NE PAS reset _matiere_cumulee : le generateur qui vient d'epuiser
	# une source (cadavre trop petit) doit CONSERVER sa matiere deja
	# collectee pour l'ajouter a ce qu'il prendra sur la source suivante
	# (Yael 2026-08-22 : "cumul possible sur plusieurs sources"). Le
	# reset se fait a _faire_pond (fin de cycle reussi).
	_cout_paye_pour_ce_cycle = false

# API publique -- rend les percepts qui portent stock_puisable > 0 sur
# leur entite du monde. Tri par distance croissante. La perception reste
# aveugle (rend TOUT dans le cone) ; le filtrage saillance se fait ici
# par propriete NOMMEE (respect CLAUDE.md § ADN : aucun test
# type == "geniteur" ni "cadavre_generateur").
func percevoir_source_matiere() -> Array:
	if _monde_partage == null:
		return []
	var percues := Perception.percevoir(entite, _monde_partage.monde, CATALOGUE_CANAUX)
	var sources: Array = []
	for p in percues:
		var props: Dictionary = p.chose.get("proprietes", {})
		if float(props.get("stock_puisable", 0.0)) > 0.0:
			sources.append(p)
	sources.sort_custom(func(a, b): return a.distance < b.distance)
	return sources

# Marche horizontale vers la source. Distance de contact adaptative :
# le geniteur fait 6 m (distance_contact_geniteur), un cadavre 1 m
# (distance_contact_cadavre). On distingue par presence de la propriete
# "stock_cadavre_initial" sur le noeud (pattern duck-typing).
# Si la source devient invalide (cadavre vide+free, geniteur mort), retour
# ATTENTE pour rechercher.
func _faire_vers_source(_delta: float) -> void:
	if _source == null or not is_instance_valid(_source):
		_source = null
		_etat = ETAT_ATTENTE
		return
	var vers: Vector3 = _source.global_position - global_position
	vers.y = 0.0
	var seuil: float = _distance_contact_pour(_source)
	if vers.length() <= seuil:
		linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)
		_etat = ETAT_COLLE
		_secondes_dans_colle = 0.0
		return
	var direction := vers.normalized()
	linear_velocity = Vector3(direction.x * vitesse_marche, linear_velocity.y, direction.z * vitesse_marche)

# Distance de contact adaptative : cadavre (petit) vs geniteur (grand).
# Duck-typing sur la presence de "preleve_stock_puisable" + presence de
# groupe "ressource" (les cadavres y sont, le geniteur non).
func _distance_contact_pour(source: Node3D) -> float:
	if source.is_in_group("ressource"):
		return distance_contact_cadavre
	return distance_contact_geniteur

# Colle au geniteur : paie le cout de prelevement UNE FOIS (a l'entree),
# puis attend secondes_ponte avant de pondre. Le geniteur ne bouge pas
# tres vite (vitesse_sol=3), s'il se deplace en cours de gestation, le
# generateur reste sur place -- c'est un choix simple, s'il traine trop
# loin le generateur devra remarcher au tick suivant (mais ce cycle a
# deja depense les 10 stock, budget perdu si le geniteur meurt).
func _faire_colle(delta: float) -> void:
	if _source == null or not is_instance_valid(_source):
		_source = null
		_etat = ETAT_ATTENTE
		return
	linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)
	# PAIEMENT UNIFORME via preleve_stock_puisable. La source rend la
	# quantite REELLEMENT prise (bornee par son stock). Cumul dans
	# _matiere_cumulee sur PLUSIEURS puises si necessaire. Une fois le
	# cout atteint, le timer de ponte demarre.
	# Si la source ne suffit pas a completer le cycle (cadavre trop
	# petit), le generateur repart chercher une autre source (retour
	# ATTENTE) avec la matiere deja cumulee gardee.
	if not _cout_paye_pour_ce_cycle:
		var reste: float = cout_prelevement - _matiere_cumulee
		if _source.has_method("preleve_stock_puisable"):
			var pris: float = float(_source.preleve_stock_puisable(reste))
			_matiere_cumulee += pris
			if pris <= 0.0:
				# Source epuisee ce tick (le cadavre queue_free apres retour).
				# Retour ATTENTE pour rechercher une autre source. Le cumul
				# est PRESERVE (le generateur porte deja la matiere prise).
				_source = null
				_etat = ETAT_ATTENTE
				return
			if _matiere_cumulee >= cout_prelevement:
				_cout_paye_pour_ce_cycle = true
		elif _source.has_method("retirer_stock"):
			# Fallback pour mocks sans preleve_stock_puisable.
			_source.retirer_stock(cout_prelevement)
			_matiere_cumulee = cout_prelevement
			_cout_paye_pour_ce_cycle = true
		else:
			# Aucune API disponible : la source est invalide comme source
			# de matiere (bug B7 corrige 2026-08-22 -- avant, le generateur
			# restait bloque en COLLE, timer arrete). Retour ATTENTE pour
			# oublier cette source, la prochaine perception l'ignorera
			# (elle n'a pas de stock_puisable > 0 declare).
			_source = null
			_etat = ETAT_ATTENTE
			return
	if _cout_paye_pour_ce_cycle:
		_secondes_dans_colle += delta
		if _secondes_dans_colle >= secondes_ponte:
			_etat = ETAT_POND

# Pose un carre rouge du cote OPPOSE a la source (patron puceron : produit
# le miellat de son cote, pas colle a la plante hote). Puis retour ATTENTE
# pour choisir la prochaine source (peut avoir change entre-temps :
# cadavre plus proche, geniteur epuise, ...). La ponte est instantanee.
func _faire_pond() -> void:
	var vers_source: Vector3 = Vector3.ZERO
	if _source != null and is_instance_valid(_source):
		vers_source = _source.global_position - global_position
		vers_source.y = 0.0
	var direction_derriere: Vector3
	if vers_source.length() > 0.001:
		direction_derriere = -vers_source.normalized()
	else:
		# Colle sur la source ou source invalide : direction arbitraire.
		direction_derriere = Vector3.RIGHT
	var pose: Vector3 = global_position + direction_derriere * offset_carre_rouge
	# POSITION AVANT add_child : sinon _ready du carre lit global_position
	# Vector3.ZERO et inscrit tout a l'origine du monde partage (piege deja
	# rencontre au test_mother_cube 2026-08-22).
	var cr := CarreRougeScene.instantiate() as Node3D
	cr.position = pose
	# ADD_CHILD SUR LE PARENT DU GENERATEUR : universel (marche en test
	# SceneTree ou en scene chargee). get_tree().current_scene est null en
	# test headless SceneTree, piege rencontre le 2026-08-22.
	var accueil := get_parent()
	if accueil != null:
		accueil.add_child(cr)
	# Retour ATTENTE : nouveau cycle, choisit la meilleure source dispo.
	_source = null
	_matiere_cumulee = 0.0
	_cout_paye_pour_ce_cycle = false
	_etat = ETAT_ATTENTE

# API publique -- appelee par ce qui frappe (arme, projectile, etc.).
# Le degat 1 = une vie perdue (patron 3 vies = 3 unites de reserve).
# Phase VIVANT : a 0 -> _mourir() (etat cadavre).
# Phase CADAVRE : a 0 -> queue_free (destruction finale, apres vie_cadavre
# coups). Barre non rafraichie (elle est cachee).
func subir_frappe(degats: float) -> void:
	Frappe.frapper(entite, degats, "vie")
	if _est_cadavre:
		if entite.proprietes.reserves.vie.reserve <= 0.0:
			# Destruction par frappe AVANT que le stock soit consomme :
			# retirer du monde partage pour eviter un fantome perceptible.
			if _monde_partage != null and not _entite_cadavre.is_empty():
				_monde_partage.monde.retirer(_entite_cadavre.id)
			queue_free()
		return
	_rafraichir_barre()
	if entite.proprietes.reserves.vie.reserve <= 0.0:
		_mourir()

func _rafraichir_barre() -> void:
	var f := clampf(entite.proprietes.reserves.vie.reserve / vie_max, 0.0, 1.0)
	_materiau_vie.set_shader_parameter("fraction", f)
