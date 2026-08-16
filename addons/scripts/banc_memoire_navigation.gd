extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_memoire_navigation.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « memoire spatiale + navigation par memoire », audit prealable
# audit_perception_croyance_memoire_prealable.md lignes 5 et 6.
#
# Compose QUATRE mecanismes deja fermes, TOUS INCHANGES : scripts/perception.gd,
# scripts/lumiere.gd, scripts/monde.gd, scripts/banc_commun.gd -- plus le seul
# mecanisme NEUF du chantier, scripts/memoire_spatiale.gd. AUCUN .gd existant du
# coeur touche : lien_personnel.gd, lien_personnel_attraction.gd, ciblage.gd et
# monde.gd sont rigoureusement inchanges.
#
# ---------------------------------------------------------------------------
# CE QU'IL DOIT MONTRER
# ---------------------------------------------------------------------------
# 1. LE COLON RETIENT OU IL A VU LE PUITS. Tant que le puits est a portee de
#    perception (perception.gd, canal `vue`), memoire_spatiale.gd:memoriser
#    reecrit la position observee et la force du souvenir monte.
# 2. LE PUITS PART HORS DE PORTEE, ET LE COLON CONTINUE DE VISER SON SOUVENIR.
#    C'est le point du chantier, et c'est ce que le depot ne savait PAS faire :
#    lien_personnel_attraction.gd rendait deja une cible hors perception, mais
#    a sa position REELLE, relue vivante (monde.gd : « la position est toujours
#    relue depuis chose.position au moment de la requete ») -- le colon suivait
#    un puits qui bouge PAR TELEPATHIE. Ici le carre BLEU (reel) et le carre
#    ORANGE (memorise) se separent, et le colon marche vers l'ORANGE.
# 3. LA NUIT, IL SE PERD DAVANTAGE. L'heure pose la luminosite via
#    lumiere.gd:soleil, et l'erreur monte de (1 - luminosite) * coef_nuit.
# 4. LE TEMPS QUI PASSE EFFACE. La force du souvenir decroit, l'erreur monte,
#    le point vise derive LE LONG D'UNE DROITE FIXE (la direction du biais vient
#    du hash de l'id du puits, jamais de l'erreur -- le souvenir ne tremble
#    jamais d'un tick a l'autre). Sous le plancher, l'entree est RETIREE : le
#    colon n'a plus rien a viser du tout et s'arrete.
# 5. REPERCEVOIR CORRIGE. Ramener le puits a portee reecrit la position ET
#    remonte la force : l'orange saute sur le bleu, l'erreur retombe.
#
# ---------------------------------------------------------------------------
# TROIS DECISIONS DE CE CABLAGE, dites plutot que masquees
# ---------------------------------------------------------------------------
# (a) AUCUNE HORLOGE N'EST RECOPIEE ICI -- scripts/horloge.gd est APPELE.
#     C'est ce banc, le troisieme demandeur, qui a fait franchir le seuil que
#     banc_fatigue_circadien.gd avait nomme sans le franchir (« si cette horloge
#     doit un jour servir un troisieme banc, elle devient candidate au coeur »).
#     `cycle.duree_jour_secondes` vaut 0.0 en donnee : c'est le point LEGITIME
#     et documente de horloge.gd (« le temps du monde est simplement arrete »,
#     aucune alarme), et heure() rend alors exactement `heure_depart`, que la
#     bascule JOUR/NUIT pose. CE N'EST PAS UN CONTOURNEMENT, c'est le sujet du
#     banc : l'erreur a DEUX causes (memoire faible, obscurite) et le banc
#     existe pour les separer -- une heure qui derive en continu ferait varier
#     la luminosite sous chaque mesure et melangerait les deux. Faire tourner le
#     jour est UN NOMBRE en donnee, zero ligne de code ici.
# (b) LE PLAFOND DE FORCE EST DU CABLAGE, jamais du mecanisme. Le coeur ne borne
#     jamais le HAUT (constat pose par banc_fertilite.gd puis repete cinq fois) :
#     memoriser() est appele CHAQUE TICK tant que le puits est vu -- il faut ca
#     pour que la position reste fraiche -- donc la force monterait sans fin.
#     `plafonner_memoire` l'ecrete, patron litteral de
#     banc_fatigue_circadien.gd:plafonner_reserves. Ecreter la FORCE plutot que
#     de sauter l'appel a memoriser est le seul ordre correct : gater l'appel
#     figerait aussi la POSITION, et un puits qui bouge sous les yeux du colon
#     ne serait plus jamais remis a jour, EN SILENCE.
# (c) SEULE L'HORLOGE DE L'OUBLI ACCELERE. La bascule TEMPS multiplie le `delta`
#     passe a MemoireSpatiale.avancer, jamais celui du deplacement ni de la
#     perception : sinon le colon traverserait l'ecran a chaque appui et on ne
#     verrait plus rien de la derive. Limite assumee, ce n'est pas une
#     acceleration de simulation (celle-la vit dans banc_simulation_acceleree.gd).
#
# LIMITE DITE, PAS MASQUEE : ce banc ne monte AUCUNE couche de saillance --
# ni proximite.gd, ni dominance.gd, ni agir.gd, ni ciblage.gd. La cible est
# declaree en donnee (l'id du puits) et le mouvement est direct. Brancher le
# souvenir sur la couche 2 (rendre un candidat de saillance a position
# MEMORISEE, la ou lien_personnel_attraction.gd en rend un a position REELLE)
# est le chantier SUIVANT, pas celui-ci -- et il touchera le coeur, donc il ne
# se bricole pas ici au passage.
#
# COLON ET PUITS CONSTRUITS A LA MAIN (pas Objet.fabriquer, meme statut que
# banc_maladie.gd/banc_faim_thermo.gd/banc_grief.gd -- ils n'ont pas de
# composition ici, aucun materiau n'intervient). Positions en PIXELS (patron
# banc_lumiere.gd), z = 0.0 TOUJOURS -- VERTICALITE.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et construit le monde et le rendu.
#   _unhandled_input bascule les trois toggles. _process appelle UNIQUEMENT
#   avancer() et lit son resultat pour l'affichage et la console -- aucune
#   decision dans _process.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_memoire_navigation.gd) : construire_colon, construire_puits,
#   heure_du_jour, luminosite_a, position_puits, facteur_temps, cibles_percues,
#   memoriser_percus, plafonner_memoire, force_memorisee, avancer, plus les
#   textes d'affichage et de trace.

const MemoireSpatiale = preload("res://scripts/memoire_spatiale.gd")
const Perception = preload("res://scripts/perception.gd")
const Horloge = preload("res://scripts/horloge.gd")
const Lumiere = preload("res://scripts/lumiere.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const TAILLE_COLON := 44.0
const TAILLE_MARQUEUR := 30.0
const EPAISSEUR_LIGNE := 3.0

var _config: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_lumiere: Dictionary = {}
var _catalogue_memoire: Dictionary = {}

var _monde
var _colon: Dictionary = {}
var _puits: Dictionary = {}

var _nuit := false
var _accelere := false
var _reperception := false

var _fond: ColorRect
var _noeud_colon: ColorRect
var _noeud_puits: ColorRect
var _noeud_souvenir: ColorRect
var _ligne: Line2D
var _label: Label
var _label_aide: Label

var _temps := 0.0
var _prochain_print := 0.0
var _souvenir_connu := false

func _ready() -> void:
	_config = _charger_json("res://data/banc_memoire_navigation.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_lumiere = _charger_json("res://data/lumiere.json")
	_catalogue_memoire = _charger_json("res://data/memoire_spatiale.json")

	_colon = construire_colon(_config)
	_puits = construire_puits(_config)
	_monde = BancCommun.monde_depuis([
		{"choses": [_colon], "type": String(_config.colon.type)},
		{"choses": [_puits], "type": String(_config.puits.type)},
	])

	_creer_rendu()
	_rafraichir(bilan_initial())
	print(ligne_pose_initiale(_config))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_nuit = not _nuit
			print(ligne_toggle(_temps, "JOUR/NUIT", "NUIT" if _nuit else "JOUR"))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_accelere = not _accelere
			print(ligne_toggle(_temps, "TEMPS", "ACCELERE x%.0f" % float(_config.facteur_temps_accelere) if _accelere else "NORMAL"))
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_reperception = not _reperception
		print(ligne_toggle(_temps, "REPERCEVOIR", "PUITS RAPPROCHE" if _reperception else "PUITS ELOIGNE"))

func _process(delta: float) -> void:
	_temps += delta
	var bilan := avancer(
		_colon, _puits, _monde, _config,
		_catalogue_canaux, _catalogue_lumiere, _catalogue_memoire,
		_nuit, _accelere, _reperception, _temps, delta)
	_rafraichir(bilan)

	if bool(bilan.souvenir_connu) != _souvenir_connu:
		_souvenir_connu = bool(bilan.souvenir_connu)
		print(ligne_souvenir(_temps, _souvenir_connu))

	if _temps >= _prochain_print:
		_prochain_print = _temps + float(_config.intervalle_print)
		print(ligne_trace(_temps, bilan, _config))

# ---------------------------------------------------------------------------
# Fonctions PURES, testables headless (voir test_banc_memoire_navigation.gd)
# ---------------------------------------------------------------------------

# Le colon porte QUATRE choses et rien d'autre : le canal de perception (lu par
# perception.gd), la memoire spatiale (STRUCTURELLE -- sa cle absente alarme,
# elle est donc posee VIDE ici et jamais oubliee), la forme (dont seule la cle
# `biais` est lue par memoire_spatiale.gd) et sa vitesse.
static func construire_colon(config: Dictionary) -> Dictionary:
	var decl: Dictionary = config.colon
	var pos: Array = decl.position
	return {
		"id": decl.id,
		"position": Vector3(pos[0], pos[1], pos[2]),
		"proprietes": {
			"canaux": [config.nom_canal_vue],
			"canaux_config": {
				config.nom_canal_vue: {"portee": float(decl.portee_vue), "angle": 360.0},
			},
			"memoire_spatiale": {},
			"forme": {"biais": float(decl.biais)},
			config.nom_propriete_vitesse: float(decl.vitesse),
		},
	}

# Le puits ne porte QUE le marqueur qui le rend digne d'etre retenu. Ce
# marqueur est nomme EN DONNEE (config.nom_propriete_repere) : le cablage ne
# teste jamais `type == "puits"`, il teste une PROPRIETE -- meme discipline que
# le coeur, alors meme qu'un banc aurait le droit de nommer une categorie.
static func construire_puits(config: Dictionary) -> Dictionary:
	var decl: Dictionary = config.puits
	var pos: Array = decl.position_initiale
	return {
		"id": decl.id,
		"position": Vector3(pos[0], pos[1], pos[2]),
		"proprietes": {config.nom_propriete_repere: true},
	}

# L'heure passe par horloge.gd, mecanisme du coeur -- jamais un fmod recopie
# ici (voir en-tete, decision (a)). La bascule JOUR/NUIT choisit l'HEURE DE
# DEPART parmi deux heures declarees en donnee ; `duree_jour_secondes` vaut
# 0.0, donc horloge.gd rend cette heure de depart telle quelle. Faire tourner
# le jour ne demande pas une ligne ici, seulement un nombre en donnee.
static func heure_du_jour(nuit: bool, temps: float, config: Dictionary) -> float:
	var cycle: Dictionary = config.cycle
	var depart: float = float(cycle.heure_nuit) if nuit else float(cycle.heure_jour)
	return Horloge.heure(temps, float(cycle.duree_jour_secondes), float(cycle.heures_par_jour), depart)

# La luminosite n'est JAMAIS recalculee ici : elle vient de lumiere.gd:soleil,
# mecanisme du coeur, sur le catalogue partage data/lumiere.json. Une latitude
# de 0.0 est declaree en donnee de banc pour que midi rende exactement 1.0 et
# minuit exactement 0.0 -- sans quoi la part « nuit » de l'erreur ne serait
# jamais nulle en plein jour et le banc melangerait ses deux causes.
static func luminosite_a(heure: float, config: Dictionary, catalogue_lumiere: Dictionary) -> float:
	return float(Lumiere.soleil(heure, float(config.cycle.latitude), catalogue_lumiere).intensite)

# Ou est le puits REELLEMENT. Trois positions declarees en donnee, aucune
# interpolation : au depart il est a portee (le colon le memorise), apres
# `delai_deplacement` il part au loin (le souvenir devient faux), et la bascule
# REPERCEVOIR le ramene A UNE TROISIEME POSITION -- jamais celle de depart,
# sans quoi on ne verrait pas que le souvenir a ete REECRIT et non simplement
# renforce.
static func position_puits(reperception: bool, temps: float, config: Dictionary) -> Vector3:
	var decl: Dictionary = config.puits
	var brut: Array = decl.position_initiale
	if reperception:
		brut = decl.position_proche
	elif temps >= float(config.delai_deplacement):
		brut = decl.position_lointaine
	return Vector3(brut[0], brut[1], brut[2])

# SEULE L'HORLOGE DE L'OUBLI accelere (en-tete, decision (c)).
static func facteur_temps(accelere: bool, config: Dictionary) -> float:
	return float(config.facteur_temps_accelere) if accelere else float(config.facteur_temps_normal)

# Ce que le colon voit ET juge digne d'etre retenu. Filtre sur une PROPRIETE
# nommee en donnee, jamais sur un type. perception.gd rend deja `position` sur
# chaque entree : c'est celle-la qui est memorisee, jamais une position relue
# ailleurs -- si on relisait `chose.position` au moment de memoriser, on
# reintroduirait exactement la telepathie que ce chantier ferme.
static func cibles_percues(perceptions: Array, config: Dictionary) -> Array:
	var cibles: Array = []
	for entree in perceptions:
		if not bool(entree.chose.proprietes.get(config.nom_propriete_repere, false)):
			continue
		cibles.append({"id": entree.chose.id, "position": entree.position})
	return cibles

static func memoriser_percus(colon: Dictionary, cibles: Array, catalogue_memoire: Dictionary) -> Array:
	var ids: Array = []
	for cible in cibles:
		MemoireSpatiale.memoriser(colon, String(cible.id), cible.position, catalogue_memoire)
		ids.append(cible.id)
	return ids

# ECRETAGE AU PLAFOND -- du cablage, jamais un mecanisme (en-tete, decision (b)).
# Rend le total ecrete ce pas, pour la trace.
static func plafonner_memoire(colon: Dictionary, config: Dictionary) -> float:
	var plafond: float = float(config.plafond_force)
	var ecrete := 0.0
	var registre: Dictionary = colon.proprietes.memoire_spatiale
	for chose_id in registre:
		var entree: Dictionary = registre[chose_id]
		var force: float = float(entree.get("force", 0.0))
		if force > plafond:
			ecrete += force - plafond
			entree["force"] = plafond
	return ecrete

# Lecture directe du registre -- legitime : la structure est declaree et
# documentee par memoire_spatiale.gd, et c'est le meme geste que
# banc_fatigue_circadien.gd:reserve_de qui lit proprietes.reserves. Passer par
# position_memorisee() pour n'obtenir qu'une force obligerait a fabriquer une
# heure et une luminosite dont ce diagnostic n'a que faire.
static func force_memorisee(colon: Dictionary, chose_id: String) -> float:
	return float(colon.proprietes.memoire_spatiale.get(chose_id, {}).get("force", 0.0))

# LE PAS COMPLET, seul appele par _process (qui ne calcule jamais rien
# lui-meme). ORDRE FIXE ET VOULU, chaque etape depend de la precedente :
#  1. l'heure vient de la bascule, la luminosite de lumiere.gd:soleil ;
#  2. le puits est pose a sa position REELLE du moment (le Dictionary du puits
#     est celui que Monde tient par reference -- monde.gd relit chose.position
#     a chaque requete, aucune reinscription n'est necessaire) ;
#  3. perception.gd dit ce que le colon voit MAINTENANT ;
#  4. l'OUBLI d'abord (MemoireSpatiale.avancer), l'OBSERVATION ensuite : dans
#     cet ordre, un puits vu ce tick est integralement rafraichi, alors que
#     l'ordre inverse ferait decroitre une observation qui vient d'arriver ;
#  5. ecretage au plafond (le coeur ne borne pas le haut) ;
#  6. lecture du souvenir, deja biaise par l'erreur ;
#  7. le colon marche vers ce souvenir -- et vers RIEN si le souvenir a ete
#     retire sous le plancher (erreur INF) : ne pas savoir n'est pas savoir mal,
#     il s'arrete au lieu de foncer sur Vector3.ZERO.
# Rend un diagnostic de trace, jamais relu comme une source de verite.
static func avancer(
	colon: Dictionary,
	puits: Dictionary,
	monde,
	config: Dictionary,
	catalogue_canaux: Dictionary,
	catalogue_lumiere: Dictionary,
	catalogue_memoire: Dictionary,
	nuit: bool,
	accelere: bool,
	reperception: bool,
	temps: float,
	delta: float,
) -> Dictionary:
	var heure := heure_du_jour(nuit, temps, config)
	var luminosite := luminosite_a(heure, config, catalogue_lumiere)
	puits.position = position_puits(reperception, temps, config)

	var perceptions: Array = Perception.percevoir(colon, monde, catalogue_canaux)
	var cibles := cibles_percues(perceptions, config)
	MemoireSpatiale.avancer(colon, delta * facteur_temps(accelere, config), catalogue_memoire)
	var memorises := memoriser_percus(colon, cibles, catalogue_memoire)
	var ecrete := plafonner_memoire(colon, config)

	var id_cible: String = String(config.puits.id)
	var souvenir: Dictionary = MemoireSpatiale.position_memorisee(
		colon, id_cible, colon.proprietes.forme, heure, luminosite, catalogue_memoire)
	var connu: bool = float(souvenir.erreur) < INF
	if connu:
		colon.position = BancCommun.bouger_vers(
			colon.position, souvenir.position,
			float(colon.proprietes[config.nom_propriete_vitesse]), delta)

	return {
		"heure": heure,
		"luminosite": luminosite,
		"percu": not memorises.is_empty(),
		"souvenir_connu": connu,
		"force": float(souvenir.force),
		"erreur": float(souvenir.erreur),
		"cible": souvenir.position,
		"position_reelle": puits.position,
		"ecart_reel_memorise": (souvenir.position as Vector3).distance_to(puits.position) if connu else INF,
		"ecrete": ecrete,
	}

func bilan_initial() -> Dictionary:
	var heure := heure_du_jour(_nuit, 0.0, _config)
	return {
		"heure": heure,
		"luminosite": luminosite_a(heure, _config, _catalogue_lumiere),
		"percu": false,
		"souvenir_connu": false,
		"force": 0.0,
		"erreur": INF,
		"cible": _colon.position,
		"position_reelle": _puits.position,
		"ecart_reel_memorise": INF,
		"ecrete": 0.0,
	}

# ---------------------------------------------------------------------------
# Textes -- affichage et trace console. Aucun calcul, ils ne font que LIRE le
# bilan rendu par avancer(). (Ce sont des traces de mise au point, pas une
# interface joueur : la regle d'INTERNATIONALISATION de CLAUDE.md ne s'y
# applique pas -- elle vise « les chaines visibles par le joueur ».)
# ---------------------------------------------------------------------------

static func texte_etat(bilan: Dictionary, nuit: bool, accelere: bool, reperception: bool, config: Dictionary) -> String:
	return "heure = %.1f    luminosite = %.2f    [%s]\nforce du souvenir = %s\nerreur = %s\necart reel <-> memorise = %s px\npuits %s%s" % [
		float(bilan.heure), float(bilan.luminosite), "NUIT" if nuit else "JOUR",
		_nombre(float(bilan.force)),
		_nombre(float(bilan.erreur)),
		_nombre(float(bilan.ecart_reel_memorise)),
		"PERCU" if bool(bilan.percu) else "hors de portee",
		"  (rapproche)" if reperception else "",
	] + ("\ntemps de l'oubli : ACCELERE x%.0f" % float(config.facteur_temps_accelere) if accelere else "\ntemps de l'oubli : normal")

static func texte_aide() -> String:
	return "clic gauche : JOUR / NUIT      clic droit : temps de l'oubli accelere      touche R : rapprocher / eloigner le puits"

static func ligne_pose_initiale(config: Dictionary) -> String:
	return "t=0.0 colon '%s' pose, puits '%s' a portee ; il s'eloigne a t=%.1f s" % [
		config.colon.id, config.puits.id, float(config.delai_deplacement),
	]

static func ligne_toggle(t: float, nom: String, valeur: String) -> String:
	return "t=%.1f bascule %s -> %s" % [t, nom, valeur]

static func ligne_souvenir(t: float, connu: bool) -> String:
	return "t=%.1f souvenir du puits : %s" % [
		t, "FORME (le colon a une cible)" if connu else "OUBLIE (plus rien a viser, le colon s'arrete)",
	]

static func ligne_trace(t: float, bilan: Dictionary, config: Dictionary) -> String:
	return "t=%.1f h=%.1f lum=%.2f %s force=%s erreur=%s ecart=%s px cible=(%.0f, %.0f) reel=(%.0f, %.0f)%s" % [
		t, float(bilan.heure), float(bilan.luminosite),
		"VU" if bool(bilan.percu) else "  ",
		_nombre(float(bilan.force)), _nombre(float(bilan.erreur)), _nombre(float(bilan.ecart_reel_memorise)),
		(bilan.cible as Vector3).x, (bilan.cible as Vector3).y,
		(bilan.position_reelle as Vector3).x, (bilan.position_reelle as Vector3).y,
		"" if float(bilan.ecrete) == 0.0 else " ecrete=%.2f" % float(bilan.ecrete),
	]

# Un souvenir absent n'a pas une grande erreur : il n'en a PAS. L'ecrire « inf »
# plutot qu'un nombre enorme est ce qui empeche de lire « il se trompe beaucoup »
# la ou il faut lire « il ne sait rien ».
static func _nombre(valeur: float) -> String:
	return "inf" if valeur == INF else "%.2f" % valeur

# ---------------------------------------------------------------------------
# Rendu (impur, Node) -- aucune decision, seulement des noeuds et une camera.
# ---------------------------------------------------------------------------

func _rafraichir(bilan: Dictionary) -> void:
	_fond.color = _couleur(_config.couleurs.fond_nuit if _nuit else _config.couleurs.fond_jour)

	var pos_colon := Vector2(_colon.position.x, _colon.position.y)
	_noeud_colon.position = pos_colon - _noeud_colon.size / 2.0

	var pos_reelle := Vector2(_puits.position.x, _puits.position.y)
	_noeud_puits.position = pos_reelle - _noeud_puits.size / 2.0

	var connu: bool = bool(bilan.souvenir_connu)
	_noeud_souvenir.visible = connu
	_ligne.visible = connu
	if connu:
		var pos_cible := Vector2((bilan.cible as Vector3).x, (bilan.cible as Vector3).y)
		_noeud_souvenir.position = pos_cible - _noeud_souvenir.size / 2.0
		_ligne.points = PackedVector2Array([pos_colon, pos_cible])

	_label.text = texte_etat(bilan, _nuit, _accelere, _reperception, _config)

func _creer_rendu() -> void:
	_fond = ColorRect.new()
	_fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fond.size = Vector2(4000.0, 3000.0)
	_fond.position = Vector2(-2000.0, -1500.0)
	add_child(_fond)

	_ligne = Line2D.new()
	_ligne.width = EPAISSEUR_LIGNE
	_ligne.default_color = _couleur(_config.couleurs.ligne_visee)
	add_child(_ligne)

	_noeud_puits = _creer_marqueur(TAILLE_MARQUEUR, _config.couleurs.puits_reel)
	_noeud_souvenir = _creer_marqueur(TAILLE_MARQUEUR, _config.couleurs.puits_memorise)
	_noeud_colon = _creer_marqueur(TAILLE_COLON, _config.couleurs.colon)

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_label.position = Vector2(20.0, 14.0)
	couche_ui.add_child(_label)

	_label_aide = Label.new()
	_label_aide.add_theme_font_size_override("font_size", 14)
	_label_aide.position = Vector2(20.0, 150.0)
	_label_aide.text = texte_aide()
	couche_ui.add_child(_label_aide)

	_poser_camera()

func _creer_marqueur(taille: float, rgb: Array) -> ColorRect:
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(taille, taille)
	noeud.color = _couleur(rgb)
	add_child(noeud)
	return noeud

func _poser_camera() -> void:
	var decl: Dictionary = _config.get("camera", {})
	var pos: Array = decl.get("position", [0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(decl.get("zoom", 1.0), decl.get("zoom", 1.0))
	camera.enabled = true
	add_child(camera)

static func _couleur(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
