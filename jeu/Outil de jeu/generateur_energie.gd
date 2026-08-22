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

@export var vie_max: float = 3.0
# DUREE DE VIE : le generateur meurt automatiquement apres cette duree.
# 300 s = 5 min par defaut. Reglable dans l'inspecteur.
@export var duree_vie_secondes: float = 300.0
# VIE DE CADAVRE : apres _mourir(), la reserve vie est reinitialisee a
# cette valeur. Les frappes suivantes la font descendre ; a 0 -> queue_free.
# Regle Yael : un cadavre encaisse 7 coups avant destruction finale.
@export var vie_cadavre: float = 7.0
# ENROLEMENT (morceau 2) : le generateur naissant marche vers le geniteur,
# preleve 10 stock au contact, attend `secondes_ponte`, pond un carre rouge
# derriere lui, recommence -- jusqu'a mort naturelle 5 min. Instinct
# immediat (voir choix Yael 2026-08-22 : ouvriere SCV, pas d'attente).
@export var vitesse_marche: float = 3.0
@export var distance_contact_geniteur: float = 4.0
@export var cout_prelevement: float = 10.0
@export var secondes_ponte: float = 60.0
# OFFSET PONTE : distance a laquelle le carre rouge est pose "derriere"
# le generateur, direction OPPOSEE au geniteur. Le generateur fait 1 m,
# le carre rouge 0.4 m -- 1.0 m suffit pour ne pas s'imbriquer.
@export var offset_carre_rouge: float = 1.0

const CarreRougeScene = preload("res://jeu/Outil de jeu/carre_rouge.tscn")

enum {
	ETAT_VERS_GENITEUR,
	ETAT_COLLE,
	ETAT_POND,
}
var _etat: int = ETAT_VERS_GENITEUR
var _geniteur: Node3D = null
var _secondes_dans_colle: float = 0.0
var _cout_paye_pour_ce_cycle: bool = false

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
	# RESOLUTION GENITEUR : un seul geniteur dans le banc, resolu par groupe
	# (patron transporteur.gd pour la mere). is_instance_valid teste avant
	# chaque action de mouvement -- garde-fou valide par Yael.
	_geniteur = get_tree().get_first_node_in_group("geniteur") as Node3D

func _process(delta: float) -> void:
	# CADAVRE : ne bouge plus, ne pond plus. Le corps reste comme ressource.
	if _est_cadavre or _geniteur == null or not is_instance_valid(_geniteur):
		return
	match _etat:
		ETAT_VERS_GENITEUR:
			_faire_vers_geniteur(delta)
		ETAT_COLLE:
			_faire_colle(delta)
		ETAT_POND:
			_faire_pond()

# Marche horizontale vers le geniteur. Meme pattern que soldat.gd et
# geniteur.gd:_avancer_vers_cible : linear_velocity horizontal, gravite
# gere Y. Au contact (distance <= distance_contact_geniteur), transition
# ETAT_COLLE et reset des compteurs de cycle.
func _faire_vers_geniteur(_delta: float) -> void:
	var vers: Vector3 = _geniteur.global_position - global_position
	vers.y = 0.0
	if vers.length() <= distance_contact_geniteur:
		# Au contact : arret horizontal, entree en ETAT_COLLE.
		linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)
		_etat = ETAT_COLLE
		_secondes_dans_colle = 0.0
		_cout_paye_pour_ce_cycle = false
		return
	var direction := vers.normalized()
	linear_velocity = Vector3(direction.x * vitesse_marche, linear_velocity.y, direction.z * vitesse_marche)

# Colle au geniteur : paie le cout de prelevement UNE FOIS (a l'entree),
# puis attend secondes_ponte avant de pondre. Le geniteur ne bouge pas
# tres vite (vitesse_sol=3), s'il se deplace en cours de gestation, le
# generateur reste sur place -- c'est un choix simple, s'il traine trop
# loin le generateur devra remarcher au tick suivant (mais ce cycle a
# deja depense les 10 stock, budget perdu si le geniteur meurt).
func _faire_colle(delta: float) -> void:
	# Stopper toute velocite horizontale (patron geniteur.gd:_avancer_vers_cible
	# ligne 105 : eviter la derive residuelle).
	linear_velocity = Vector3(0.0, linear_velocity.y, 0.0)
	# PAIEMENT AU STOCK ACCESSIBLE (violet), pas au stock perso. preleve_
	# rend ce qui a ete effectivement pris (borne au disponible). Si le
	# stock accessible est vide/insuffisant, ATTENDRE au contact que le
	# geniteur remplisse -- pas de timer, pas de production tant qu'on
	# n'a pas paye integralement le cout. Le morceau cadavre-mange
	# ajoutera plus tard un "repart chercher un cadavre" quand cette
	# attente devient improductive.
	if not _cout_paye_pour_ce_cycle:
		if _geniteur.has_method("preleve_stock_accessible"):
			var pris: float = float(_geniteur.preleve_stock_accessible(cout_prelevement))
			if pris >= cout_prelevement:
				_cout_paye_pour_ce_cycle = true
		else:
			# Fallback pour mocks / anciens geniteurs sans preleve_stock_accessible :
			# essayer retirer_stock (comportement historique).
			if _geniteur.has_method("retirer_stock"):
				_geniteur.retirer_stock(cout_prelevement)
			_cout_paye_pour_ce_cycle = true
	# Le timer de ponte n'avance que si le paiement est fait.
	if _cout_paye_pour_ce_cycle:
		_secondes_dans_colle += delta
		if _secondes_dans_colle >= secondes_ponte:
			_etat = ETAT_POND

# Pose un carre rouge du cote OPPOSE au geniteur (Yael : "derriere lui").
# Puis retour ETAT_VERS_GENITEUR pour recommencer le cycle. La ponte est
# instantanee -- le vrai timer est dans ETAT_COLLE.
func _faire_pond() -> void:
	var vers_geniteur: Vector3 = _geniteur.global_position - global_position
	vers_geniteur.y = 0.0
	var direction_derriere: Vector3
	if vers_geniteur.length() > 0.001:
		direction_derriere = -vers_geniteur.normalized()
	else:
		# Colle sur le geniteur : direction arbitraire pour ne pas superposer.
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
	# Retour au debut du cycle : va rechercher le geniteur pour paie
	# suivante. Meme comportement infini jusqu'a mort naturelle 5 min.
	_etat = ETAT_VERS_GENITEUR

# API publique -- appelee par ce qui frappe (arme, projectile, etc.).
# Le degat 1 = une vie perdue (patron 3 vies = 3 unites de reserve).
# Phase VIVANT : a 0 -> _mourir() (etat cadavre).
# Phase CADAVRE : a 0 -> queue_free (destruction finale, apres vie_cadavre
# coups). Barre non rafraichie (elle est cachee).
func subir_frappe(degats: float) -> void:
	Frappe.frapper(entite, degats, "vie")
	if _est_cadavre:
		if entite.proprietes.reserves.vie.reserve <= 0.0:
			queue_free()
		return
	_rafraichir_barre()
	if entite.proprietes.reserves.vie.reserve <= 0.0:
		_mourir()

func _rafraichir_barre() -> void:
	var f := clampf(entite.proprietes.reserves.vie.reserve / vie_max, 0.0, 1.0)
	_materiau_vie.set_shader_parameter("fraction", f)
