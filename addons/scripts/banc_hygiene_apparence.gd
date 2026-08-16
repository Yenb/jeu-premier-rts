extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_hygiene_apparence.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). Chantier « hygiene +
# apparence -- perception sociale », audit_mecaniques_corps_prealable.md,
# lignes 9 (HYGIENE -> RELATIONS) et 13 (DES GENS QUI FINISSENT PAR SE VOIR)
# livrees ENSEMBLE -- l'audit le disait deja : « meme machinerie exacte que
# la ligne 9 : les deux se livrent ensemble ou pas du tout ».
#
# AUCUN MECANISME DU COEUR TOUCHE NI CREE PAR CE CHANTIER. perception.gd/
# agir.gd/fuite.gd/depense.gd/seuil_etat.gd/proximite.gd/dominance.gd/
# banc_commun.gd/objet.gd/monde.gd sont appeles TELS QUELS, aucune ligne
# modifiee. Tout ce qui est neuf est de la DONNEE (deux canaux dans
# data/canaux.json, deux etats dans data/etats.json, une entree dans
# data/seuils_etat.json, une dans data/types_choses.json,
# data/banc_hygiene_apparence.json) plus ce cablage et son test.
#
# CE QUE CE BANC MONTRE, en une phrase : l'hygiene descend toute seule ; sous
# un seuil le colon devient « sale », se met a SENTIR, et les autres le
# fuient des qu'ils le percoivent ; en parallele un colon blesse est
# VISUELLEMENT reperable, de loin par un colon attentif, seulement de pres
# par un colon distrait -- et le meme colon blesse n'est jamais fui, parce
# qu'aucun verbe ne se resout sur « blesse ».
#
# LA CHAINE, cinq maillons, chacun un mecanisme deja ferme :
#  1. Depense.avancer      -- la reserve "hygiene" descend (cout_base).
#  2. ecrire_manque        -- MIROIR PLAT INVERSE, ecrit par CE cablage :
#     manque_hygiene = capacite - reserve. Obligatoire : seuil_etat.gd ne
#     sait ni descendre dans proprietes.reserves.<nom>.reserve (il ne lit
#     qu'une cle PLATE), ni comparer vers le BAS (sa comparaison est
#     strictement `valeur > seuil`). Precedent exact et documente :
#     data/seuils_etat.json:activation_neutronique / dose_radiation_objet.
#  3. SeuilEtat.avancer    -- pose/retire "sale" dans proprietes.etats_actifs
#     (data/seuils_etat.json:hygiene). REVERSIBLE par construction : c'est
#     tout le sujet, et c'est pourquoi les seuils propres de depense.gd
#     (seuils_franchis ne fait que grandir, jamais reapplique -- banc_cratere
#     a du le vider a la main) sont le MAUVAIS outil ici.
#  4. appliquer_marqueurs  -- ce cablage ecrit, depuis etats_actifs :
#     (a) odeur_emise (propriete_emission du canal "odeur_corporelle"),
#     (b) visibilite_etat (propriete_emission du canal "apparence"), SOMME
#         des marqueurs actifs,
#     (c) LE MIROIR PLAT DES ETATS -- proprietes.<nom_etat> = true tant que
#         l'etat est actif, cle EFFACEE sinon.
#     Le point (c) n'est pas un confort : agir.gd:_action scanne les cles de
#     data/types_choses.json contre chose.proprietes, une cle PLATE, JAMAIS
#     contre etats_actifs. Sans ce miroir, "sale" ne resoudrait aucun verbe
#     et personne ne fuirait jamais. Meme geste de traduction que
#     banc_maladie.gd (marqueur charge.gd -> porteur/EtatDuree.poser).
#     Les points (a)/(b) sont le patron banc_activation_neutronique.gd : un
#     objet se voit poser a la main une propriete d'emission et DEVIENT
#     source secondaire d'un canal de perception.gd.
#  5. perception -> proximite -> dominance -> BancCommun.choses_a_fuir
#     (qui resout le verbe par Agir.choisir, entree par entree) ->
#     Fuite.direction -> BancCommun.bouger_selon.
#
# DEUX CANAUX SEULEMENT SUR LES COLONS (data/banc_hygiene_apparence.json:
# canaux_du_banc), jamais les six de data/types.json:percevant -- la liste
# "canaux" est REMPLACEE apres fabrication, pas completee. Meme famille de
# geste que banc_magie_perception.gd:fabriquer_colon_magie (qui, lui,
# AJOUTE), pousse d'un cran, et pour une raison mesurable : "vue" a une
# portee de 1600 et AUCUN filtre d'intensite (geometrie cone_oriente, qui ne
# lit ni propriete_emission ni seuil) -- laissee en place, elle ferait capter
# tout colon par tout colon a toute distance, et ni l'odeur ni le seuil
# d'apparence ne prouveraient plus quoi que ce soit. RESERVES REMPLACEES de
# meme (un seul canal, "hygiene", au lieu des cinq canaux physiologiques
# herites de "dynamique") : les cinq autres n'ont aucun lecteur ici et
# descendraient en silence.
#
# CE QUE data/canaux.json GAGNE, et pourquoi deux canaux NEUFS plutot que
# des canaux existants :
# - "odeur_corporelle" n'est PAS "odorat". "odorat" a la geometrie
#   sphere_directionnelle, la SEULE qui porte la modulation par le vent, et
#   qui ne lit NI propriete_emission NI seuil (perception.gd, en-tete) :
#   basculer sa geometrie retirerait le vent a l'odorat en silence, dans un
#   catalogue PARTAGE. Ecarte par l'audit (ligne 9, voie (b)), ecarte ici.
#   propriete_obstacle VIDE : une odeur contourne un mur.
# - "apparence" porte propriete_obstacle "opacite" -- un mur cache un colon.
#   opacite vaut 1.0 sur bois/pierre/fer (data/materiaux.json, fusionnee par
#   composition) : le blocage est donc TOTAL, jamais partiel. Consequence
#   assumee, exactement celle deja documentee pour le canal "magie".
#
# LE SEUIL EST INDIVIDUEL, ET C'EST LE SUJET DE LA LIGNE 13 :
# canaux_config.apparence.seuil vit sur CHAQUE colon (perception.gd lit
# "params"), pas dans le catalogue. colon_attentif 0.05, colon_distrait 0.40,
# colon_blesse 0.20 -- meme mecanique exacte que mage/guerrier sur "magie",
# appliquee cette fois a l'etat d'un autre colon. Aucune ligne de code, un
# nombre par colon.
#
# CONSTAT MESURE, PAS UN REGLAGE -- CE QUI BORNE REELLEMENT LA FUITE : une
# entree ne peut etre fuie que si elle survit a Proximite.evaluer, qui
# l'exclut des que sa saillance tombe a zero. data/profils_saillance.json:
# colon borne la saillance inter-colon a portee_saillance 350.0. Donc :
# colon_attentif PERCOIT le colon sale jusqu'a 600 unites (apparence) mais ne
# le FUIT qu'a partir de 350 -- c'est la portee de saillance qui borne, pas
# sa perception ; colon_blesse et colon_distrait ne le percoivent QUE par
# l'odeur (285 unites, sous 350), pour eux c'est bien l'odeur qui borne.
# Trouve en calibrant, verrouille par test, dit plutot que masque.
#
# LE COLON BLESSE N'EST JAMAIS FUI : "blesse" n'a aucune entree dans
# data/types_choses.json, donc agir.gd ne resout aucun verbe dessus et
# BancCommun.choses_a_fuir ne le retient jamais. Il reste parfaitement
# PERCU (lignes de perception, label). La difference entre « remarque » et
# « fui » tient donc entierement a UNE ligne de donnee.
#
# LAVAGE AU CLIC -- LECTURE SIGNALEE A YAEL, NON TRANCHEE PAR LUI : la
# consigne disait « toggle au clic », mais sa propre parenthese decrit un
# evenement ponctuel (« hygiene remise a capacite ») -- une remise a la
# capacite n'a rien vers quoi rebasculer. Implemente en CLIC PONCTUEL,
# repetable (le colon se resalit et peut etre relave), meme lecture et meme
# reserve que banc_succession.gd. Le clic ne fait que remettre chaque reserve
# a sa capacite : il ne touche NI etats_actifs, NI le miroir plat, NI
# l'odeur -- c'est SeuilEtat.avancer qui retire "sale" au tick suivant, par
# franchissement descendant, et appliquer_marqueurs qui eteint l'odeur en
# consequence. Aucun cas particulier, aucune ligne « si lave alors ».
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les catalogues, fabrique le mur et les
#   quatre colons, cree le rendu. _unhandled_input lave au clic gauche.
#   _process enchaine les cinq maillons ci-dessus puis met a jour le rendu.
# - Fonctions statiques (pures, testables headless -- voir
#   scripts/test_banc_hygiene_apparence.gd) : fabriquer_colon_hygiene/
#   fabriquer_colons/ecrire_manque/somme_emission/appliquer_marqueurs/laver/
#   perceptions_de/visibles_de/fuite_de/ids_de/avancer_errance/borner/
#   compter_etat/compter_fuyants/couleur_de_colon/texte_colon/
#   texte_compteurs/ligne_log.
#
# NON OPTIMISE, dit et non contourne : perception.gd est en O(n^2) par appel
# des qu'un canal declare une occlusion (voir son en-tete). Quatre colons +
# un mur : sans objet.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Fuite = preload("res://scripts/fuite.gd")
const Depense = preload("res://scripts/depense.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const TAILLE := 26.0
const TAILLE_MUR := Vector2(34.0, 150.0)
const TAILLE_POLICE := 12
const TAILLE_POLICE_COMPTEUR := 16
const LARGEUR_LABEL := 320.0
const DECALAGE_LABEL := 20.0
const LARGEUR_LIGNE_FUITE := 3.0
const SEGMENTS_NUAGE := 40
const ALPHA_NUAGE := 0.16

var _config: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_actions: Dictionary = {}
var _orientations: Dictionary = {}
var _profils_saillance: Dictionary = {}
var _seuils_etat: Dictionary = {}
var _monde := Monde.new()
var _colons: Array = []
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _nuages: Dictionary = {}
var _lignes: Dictionary = {}
var _errance: Dictionary = {}
var _fuites_precedentes: Dictionary = {}
var _sales_precedents: Dictionary = {}
var _label_compteurs: Label
var _rng := RandomNumberGenerator.new()
var _temps := 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_hygiene_apparence.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_actions = _charger_json("res://data/types_choses.json")
	_orientations = _charger_json("res://data/orientations.json")
	_profils_saillance = _charger_json("res://data/profils_saillance.json")
	_seuils_etat = _charger_json("res://data/seuils_etat.json")
	var materiaux: Dictionary = _charger_json("res://data/materiaux.json")
	var immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var types_partages: Dictionary = _charger_json("res://data/types.json")

	var catalogue_types: Dictionary = _config.get("types", {}).duplicate(true)
	for nom_paquet in ["objet_physique", "dynamique", "percevant", "agent", "colon"]:
		catalogue_types[nom_paquet] = types_partages.get(nom_paquet, {})

	_rng.seed = int(_config.get("graine", 0))

	# Le mur : un objet ORDINAIRE fabrique par composition (pierre), qui ne
	# porte ni profil_saillance ni propriete d'emission -- il n'est donc
	# jamais percu (intensite 0.0 sous tout seuil strictement positif) ni
	# saillant, seulement OBSTACLE sur le canal "apparence" par son
	# "opacite" fusionnee. Il ne bloque aucun deplacement (aucune collision
	# dans ce depot) : un colon le traverse, dit plutot que masque.
	for decl in _config.get("obstacles", []):
		var pos: Array = decl.position
		var position3 := Vector3(pos[0], pos[1], pos[2])
		var obstacle := Objet.fabriquer(decl.id, decl.type, position3, catalogue_types, materiaux, immuables)
		if obstacle.is_empty():
			continue
		_monde.ajouter(obstacle, decl.type, position3)
		_dessiner_mur(decl.id, position3)

	_colons = fabriquer_colons(_config.get("colons", {}), catalogue_types, _config)
	for colon in _colons:
		_monde.ajouter(colon, "colon", colon.position)
		_errance[colon.id] = {}
		_fuites_precedentes[colon.id] = []
		_sales_precedents[colon.id] = false
		_lignes[colon.id] = {}
		_nuages[colon.id] = _creer_nuage()
		_noeuds[colon.id] = _creer_carre(colon.position, _couleur("normal"))
		_labels[colon.id] = _creer_label(colon.position)

	_label_compteurs = Label.new()
	_label_compteurs.add_theme_font_size_override("font_size", TAILLE_POLICE_COMPTEUR)
	_label_compteurs.position = Vector2(20.0, 20.0)
	add_child(_label_compteurs)

# ---- Boucle (impure) ----

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var nom_reserve: String = _config.get("nom_reserve_hygiene", "")
		for colon in _colons:
			laver(colon, nom_reserve)
		print("t=%.1f LAVAGE : les %d colons voient leur reserve '%s' remise a sa capacite" % [_temps, _colons.size(), nom_reserve])

func _process(delta: float) -> void:
	_temps += delta

	# 1. la reserve descend, 2. le miroir plat, 3. le seuil, 4. les marqueurs.
	Depense.avancer(_colons, delta)
	ecrire_manque(_colons, _config.get("nom_reserve_hygiene", ""), _config.get("propriete_manque", ""))
	SeuilEtat.avancer(_colons, _seuils_etat)
	appliquer_marqueurs(
		_colons,
		_config.get("emission_odeur", {}),
		_config.get("emission_apparence", {}),
		_config.get("propriete_odeur", ""),
		_config.get("propriete_apparence", ""),
	)

	var etat_compte: String = _config.get("etat_compte", "")
	for colon in _colons:
		var sale_maintenant: bool = colon.proprietes.get("etats_actifs", []).has(etat_compte)
		if sale_maintenant != _sales_precedents[colon.id]:
			_sales_precedents[colon.id] = sale_maintenant
			print("t=%.1f %s : '%s' %s (hygiene %.1f)" % [
				_temps, colon.id, etat_compte, "POSÉ" if sale_maintenant else "RETIRÉ",
				colon.proprietes.reserves.get(_config.get("nom_reserve_hygiene", ""), {}).get("reserve", 0.0),
			])

	# 5. percevoir, fuir, se deplacer.
	var nb_fuyants := 0
	for colon in _colons:
		var perceptions := perceptions_de(colon, _monde, _catalogue_canaux)
		var visibles := visibles_de(perceptions, colon, _profils_saillance)
		var f := fuite_de(visibles, colon, _catalogue_actions, _orientations, _monde)
		if not f.ids.is_empty():
			nb_fuyants += 1
		var direction: Vector3 = f.direction
		if direction == Vector3.ZERO:
			direction = avancer_errance(_errance[colon.id], delta, _rng, _config.get("duree_errance", 2.0))
		colon.position = borner(
			BancCommun.bouger_selon(colon.position, direction, colon.proprietes.vitesse, delta),
			_config.get("bornes", {}),
		)

		var ids_percus := ids_de(perceptions)
		if f.ids != _fuites_precedentes[colon.id]:
			_fuites_precedentes[colon.id] = f.ids.duplicate()
			print(ligne_log(_temps, colon.id, f.ids, ids_percus))
		_mettre_a_jour_rendu(colon, ids_percus, f.ids)

	_label_compteurs.text = texte_compteurs(compter_etat(_colons, etat_compte), nb_fuyants)

# ---- Fonctions statiques, pures, testables ----

# Fabrique un colon PARTAGE (BancCommun.fabriquer_colon, INCHANGE -- il pose
# position/attaches/forme/poids_verbes/action_en_cours) puis REMPLACE, en
# local a ce banc, trois blocs herites de data/types.json :
#  - "canaux"      : la liste du banc (deux canaux), jamais les six de
#                    "percevant" -- voir en-tete, "DEUX CANAUX SEULEMENT".
#  - "canaux_config" : les reglages du banc EN ENTIER (le merge d'objet.gd
#                    est superficiel, un canaux_config partiel effacerait
#                    tout ce qui est herite -- piege deja documente sur
#                    data/types.json:colon).
#  - "reserves"    : un seul canal, celui de l'hygiene.
# Pose enfin etats_actifs (etats de depart, ex. "blesse") et les trois
# proprietes PLATES que les mecanismes vont lire des le premier tick
# (manque/odeur/apparence, a 0.0 -- jamais absentes, pour que seuil_etat.gd
# et perception.gd trouvent toujours une cle a lire).
# AUCUN nom de canal, d'etat, de reserve ou de propriete ecrit ici : tout
# vient de "config" (data/banc_hygiene_apparence.json).
static func fabriquer_colon_hygiene(nom: String, decl: Dictionary, catalogue_types: Dictionary, config: Dictionary) -> Dictionary:
	var colon := BancCommun.fabriquer_colon(nom, "colon", decl, catalogue_types)
	colon.proprietes["canaux"] = config.get("canaux_du_banc", []).duplicate()
	colon.proprietes["canaux_config"] = decl.get("canaux_config", {}).duplicate(true)
	colon.proprietes["reserves"] = { config.get("nom_reserve_hygiene", ""): decl.get("hygiene", {}).duplicate(true) }
	colon.proprietes["etats_actifs"] = decl.get("etats_actifs", []).duplicate()
	colon.proprietes[config.get("propriete_manque", "")] = 0.0
	colon.proprietes[config.get("propriete_odeur", "")] = 0.0
	colon.proprietes[config.get("propriete_apparence", "")] = 0.0
	return colon

static func fabriquer_colons(declarations: Dictionary, catalogue_types: Dictionary, config: Dictionary) -> Array:
	var colons: Array = []
	for nom in declarations:
		colons.append(fabriquer_colon_hygiene(nom, declarations[nom], catalogue_types, config))
	return colons

# MIROIR PLAT INVERSE (voir en-tete, maillon 2) : une grandeur qui MONTE
# quand la reserve DESCEND, posee en propriete plate pour que seuil_etat.gd
# puisse la comparer. Une chose sans ce canal est ignoree en silence (point
# neutre legitime, jamais une alarme -- rien n'oblige un objet a porter une
# hygiene). "capacite" absente vaut 0.0 : le manque est alors toujours
# negatif ou nul, donc jamais au-dessus d'un seuil positif -- un canal mal
# declare rend l'etat INATTEIGNABLE plutot que permanent.
static func ecrire_manque(colons: Array, nom_reserve: String, propriete_manque: String) -> void:
	for colon in colons:
		var canal: Dictionary = colon.proprietes.get("reserves", {}).get(nom_reserve, {})
		if canal.is_empty():
			continue
		colon.proprietes[propriete_manque] = float(canal.get("capacite", 0.0)) - float(canal.get("reserve", 0.0))

# Somme des valeurs de "table" pour les etats REELLEMENT actifs. Un etat
# actif absent de la table contribue 0.0 sans alarme (tous les etats ne sont
# pas visibles ni odorants) ; une entree de table jamais active ne contribue
# rien non plus. Pure, aucun nom en dur.
static func somme_emission(etats_actifs: Array, table: Dictionary) -> float:
	var somme := 0.0
	for nom in table:
		if etats_actifs.has(nom):
			somme += float(table[nom])
	return somme

# Ecrit les deux proprietes d'EMISSION (odeur/apparence) ET le MIROIR PLAT
# des etats -- voir en-tete, maillon 4. Le miroir couvre l'UNION des cles
# des deux tables : c'est le seul ensemble de noms d'etat que ce banc
# connait, et il vient entierement de la donnee. Un etat sorti de
# etats_actifs voit sa cle plate EFFACEE (jamais laissee a false : agir.gd
# teste `proprietes.get(propriete, false)`, une cle a false serait
# equivalente, mais l'effacer garde l'objet lisible pour un resumeur LLM --
# voir docs/design.md, « L'LLM : lecteur ancre »).
static func appliquer_marqueurs(
	colons: Array,
	table_odeur: Dictionary,
	table_apparence: Dictionary,
	propriete_odeur: String,
	propriete_apparence: String,
) -> void:
	var noms: Array = []
	for nom in table_odeur:
		if not noms.has(nom):
			noms.append(nom)
	for nom in table_apparence:
		if not noms.has(nom):
			noms.append(nom)
	for colon in colons:
		var actifs: Array = colon.proprietes.get("etats_actifs", [])
		colon.proprietes[propriete_odeur] = somme_emission(actifs, table_odeur)
		colon.proprietes[propriete_apparence] = somme_emission(actifs, table_apparence)
		for nom in noms:
			if actifs.has(nom):
				colon.proprietes[nom] = true
			else:
				colon.proprietes.erase(nom)

# Remet la reserve a sa capacite. NE TOUCHE NI etats_actifs NI le miroir
# plat NI l'odeur : c'est SeuilEtat.avancer qui retirera l'etat au tick
# suivant, par franchissement descendant du miroir. Une chose sans ce canal
# est ignoree (point neutre, jamais une alarme).
static func laver(colon: Dictionary, nom_reserve: String) -> void:
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(nom_reserve, {})
	if canal.is_empty():
		return
	canal["reserve"] = float(canal.get("capacite", 0.0))

static func perceptions_de(colon: Dictionary, monde, catalogue_canaux: Dictionary) -> Array:
	return Perception.percevoir(colon, monde, catalogue_canaux)

# Couche 2 puis 3, sans attaches ni jugement (rien de ce banc n'en pose) :
# Proximite.evaluer resout profil_saillance ("colon", data/profils_saillance
# .json) et EXCLUT toute entree dont la saillance tombe a zero -- c'est elle
# qui borne reellement la fuite a portee_saillance, voir en-tete.
static func visibles_de(perceptions: Array, colon: Dictionary, profils_saillance: Dictionary) -> Array:
	return Dominance.visibles(Proximite.evaluer(perceptions, colon, profils_saillance, {}), colon)

# Resout, entree par entree, ce qui est A FUIR -- en DELEGUANT a
# BancCommun.choses_a_fuir (qui appelle lui-meme Agir.choisir pour resoudre
# le verbe puis data/orientations.json pour son orientation). Jamais une
# reimplementation du pesage poids_verbes ni du scan de types_choses.json :
# ce fichier ne sait meme pas que le verbe s'appelle "s_eloigner". Une
# entree sans "chose" est ecartee par choses_a_fuir lui-meme, jamais ici.
# Boucle par entree UNIQUEMENT pour recuperer les IDS (choses_a_fuir rend
# { position, saillance }, sans identite -- necessaire pour tracer les
# lignes et la console) ; la liste passee a Fuite.direction est la
# concatenation exacte de ce que choses_a_fuir a rendu, jamais reconstruite.
# Rend { choses, ids, direction }.
static func fuite_de(
	visibles: Array,
	colon: Dictionary,
	catalogue_actions: Dictionary,
	orientations: Dictionary,
	monde,
) -> Dictionary:
	var choses: Array = []
	var ids: Array = []
	for entree in visibles:
		var retenues: Array = BancCommun.choses_a_fuir([entree], colon, catalogue_actions, orientations, monde)
		if retenues.is_empty():
			continue
		choses.append_array(retenues)
		ids.append(entree.chose.id)
	return { "choses": choses, "ids": ids, "direction": Fuite.direction(colon.position, choses) }

static func ids_de(perceptions: Array) -> Array:
	var ids: Array = []
	for entree in perceptions:
		ids.append(entree.chose.id)
	ids.sort()
	return ids

# Errance seedee : une direction tiree au sort, gardee "duree" secondes.
# "etat" est un Dictionary MUTE EN PLACE, propre a un colon (aucun hasard
# non seede -- CLAUDE.md). Pure au sens du depot : tout arrive en parametre,
# rien n'est lu hors de "etat".
static func avancer_errance(etat: Dictionary, delta: float, rng: RandomNumberGenerator, duree: float) -> Vector3:
	etat["reste"] = float(etat.get("reste", 0.0)) - delta
	if etat.reste <= 0.0 or not etat.has("direction"):
		var angle: float = rng.randf() * TAU
		etat["direction"] = Vector3(cos(angle), sin(angle), 0.0)
		etat["reste"] = duree
	return etat.direction

# Garde le colon dans le cadre observable. Bornes absentes : position rendue
# telle quelle (point neutre, jamais une alarme). z reste toujours 0.0 --
# les positions sont des Vector3 par doctrine (CLAUDE.md, VERTICALITE),
# jamais des Vector2, meme quand la scene est plate.
static func borner(position: Vector3, bornes: Dictionary) -> Vector3:
	if bornes.is_empty():
		return position
	return Vector3(
		clamp(position.x, float(bornes.get("x_min", -INF)), float(bornes.get("x_max", INF))),
		clamp(position.y, float(bornes.get("y_min", -INF)), float(bornes.get("y_max", INF))),
		0.0,
	)

static func compter_etat(colons: Array, nom_etat: String) -> int:
	var n := 0
	for colon in colons:
		if colon.proprietes.get("etats_actifs", []).has(nom_etat):
			n += 1
	return n

# Premier etat de "priorite" present dans etats_actifs, sinon "". Une seule
# couleur par carre alors que plusieurs etats peuvent coexister : c'est a
# l'APPELANT de hierarchiser (seuil_etat.gd ne le fait jamais), meme geste
# que banc_changement_etat.gd:couleur_pour_etats qui priorise gaz sur
# liquide. L'ordre vient de la donnee, jamais du code.
static func etat_dominant(colon: Dictionary, priorite: Array) -> String:
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	for nom in priorite:
		if actifs.has(nom):
			return String(nom)
	return ""

static func texte_colon(
	colon: Dictionary,
	nom_reserve: String,
	propriete_odeur: String,
	propriete_apparence: String,
	ids_percus: Array,
) -> String:
	var reserve: float = colon.proprietes.get("reserves", {}).get(nom_reserve, {}).get("reserve", 0.0)
	var percu: String = ", ".join(ids_percus) if not ids_percus.is_empty() else "(rien)"
	return "%s\nhygiene %.0f | odeur %.2f | apparence %.2f\nperçoit : %s" % [
		colon.id, reserve,
		colon.proprietes.get(propriete_odeur, 0.0),
		colon.proprietes.get(propriete_apparence, 0.0),
		percu,
	]

static func texte_compteurs(nb_sales: int, nb_fuyants: int) -> String:
	return "colons sales : %d    colons qui fuient : %d" % [nb_sales, nb_fuyants]

static func ligne_log(t: float, colon_id: String, ids_fuis: Array, ids_percus: Array) -> String:
	var fuis: String = ", ".join(ids_fuis) if not ids_fuis.is_empty() else "(personne)"
	var percus: String = ", ".join(ids_percus) if not ids_percus.is_empty() else "(rien)"
	return "t=%.1f %s : fuit %s | perçoit %s" % [t, colon_id, fuis, percus]

# ---- Rendu (impur, Node) -- aucune decision, seulement des noeuds ----

func _mettre_a_jour_rendu(colon: Dictionary, ids_percus: Array, ids_fuis: Array) -> void:
	var ecran := Vector2(colon.position.x, colon.position.y)
	var carre: ColorRect = _noeuds[colon.id]
	var dominant: String = etat_dominant(colon, _config.get("priorite_couleur", []))
	carre.color = _couleur(dominant if dominant != "" else "normal")
	carre.position = ecran - carre.size / 2.0

	var label: Label = _labels[colon.id]
	label.position = ecran + Vector2(-LARGEUR_LABEL / 2.0, DECALAGE_LABEL)
	label.text = texte_colon(
		colon,
		_config.get("nom_reserve_hygiene", ""),
		_config.get("propriete_odeur", ""),
		_config.get("propriete_apparence", ""),
		ids_percus,
	)

	var nuage: Polygon2D = _nuages[colon.id]
	nuage.position = ecran
	nuage.visible = colon.proprietes.get(_config.get("propriete_odeur", ""), 0.0) > 0.0

	_mettre_a_jour_lignes(colon, ids_fuis)

# Une ligne (couleur "fuite") entre le colon et CHAQUE chose qu'il fuit ce
# tick -- jamais vers une chose seulement percue. Patron
# banc_magie_perception.gd:_mettre_a_jour_lignes, aux positions VIVANTES
# (les deux bouts bougent), donc repositionnee a chaque tick.
func _mettre_a_jour_lignes(colon: Dictionary, ids_fuis: Array) -> void:
	var actuelles: Dictionary = _lignes[colon.id]
	for id in ids_fuis:
		if not actuelles.has(id):
			var ligne := Line2D.new()
			ligne.width = LARGEUR_LIGNE_FUITE
			ligne.default_color = _couleur("fuite")
			add_child(ligne)
			actuelles[id] = ligne
		var autre = _monde.par_id(id)
		if autre == null:
			continue
		actuelles[id].points = PackedVector2Array([
			Vector2(colon.position.x, colon.position.y),
			Vector2(autre.chose.position.x, autre.chose.position.y),
		])
	var a_retirer: Array = []
	for id in actuelles:
		if not (id in ids_fuis):
			actuelles[id].queue_free()
			a_retirer.append(id)
	for id in a_retirer:
		actuelles.erase(id)

func _creer_carre(position: Vector3, couleur: Color) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(TAILLE, TAILLE)
	carre.color = couleur
	carre.position = Vector2(position.x, position.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _dessiner_mur(id: String, position: Vector3) -> void:
	var mur := ColorRect.new()
	mur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mur.size = TAILLE_MUR
	mur.color = _couleur("mur")
	mur.position = Vector2(position.x, position.y) - mur.size / 2.0
	add_child(mur)
	_noeuds[id] = mur

# Nuage d'odeur : un disque semi-transparent, rayon lu en donnee
# (rayon_nuage_odeur = la distance a laquelle l'odeur tombe sous le seuil
# commun des colons, calculee a la main dans data/banc_hygiene_apparence
# .json:_note -- un RENDU, jamais relu par un mecanisme). Cree une fois par
# colon, rendu invisible tant qu'il n'emet rien.
func _creer_nuage() -> Polygon2D:
	var rayon: float = _config.get("rayon_nuage_odeur", 0.0)
	var points := PackedVector2Array()
	for i in range(SEGMENTS_NUAGE):
		var a: float = TAU * float(i) / float(SEGMENTS_NUAGE)
		points.append(Vector2(cos(a), sin(a)) * rayon)
	var nuage := Polygon2D.new()
	nuage.polygon = points
	var c: Color = _couleur("odeur")
	nuage.color = Color(c.r, c.g, c.b, ALPHA_NUAGE)
	nuage.visible = false
	add_child(nuage)
	return nuage

func _creer_label(position: Vector3) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(LARGEUR_LABEL, 0.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", TAILLE_POLICE)
	label.position = Vector2(position.x, position.y) + Vector2(-LARGEUR_LABEL / 2.0, DECALAGE_LABEL)
	add_child(label)
	return label

func _couleur(nom: String) -> Color:
	var rgb: Array = _config.get("couleurs", {}).get(nom, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
