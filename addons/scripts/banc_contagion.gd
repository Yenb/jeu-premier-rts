extends Node2D

# Cablage de banc VISUEL, separe des autres bancs (Scene/banc_contagion.tscn,
# PAS la scene principale -- run/main_scene reste banc_p1). Existe pour VOIR
# la PREMIERE FERMETURE de la boucle lecteur agrege -> decision : un fait
# collectif (« des voisins portent l'attache guerrier ») alimente un canal
# de scripts/charge.gd (deja ferme, deja cable sur banc_charge.gd pour une
# menace spatiale) sur le corps interne d'un colon, franchit un seuil, pose
# une propriete interne -- exactement le patron banc_charge (peur ->
# effraye), applique a une contagion sociale au lieu d'une menace physique.
# JETABLE PAR DEFINITION.
#
# AUCUN MECANISME DU COEUR TOUCHE : charge.gd/comptage.gd/jugement.gd/
# agir.gd restent inchanges. Ce fichier est un CABLAGE seul.
#
# COMPTAGE IMPLICITE, PAS Comptage.compter : charge.gd fait deja lui-meme le
# travail d'agregation -- il boucle sur `causes`, teste la distance de
# chacune a `portee_charge`, et SOMME leur poids. Construire une cause par
# voisin porteur (poids implicite 1.0, defaut de charge.gd) revient a
# compter, sans jamais appeler Comptage.compter : le compte emerge de la
# somme, pas d'un appel explicite. Voir CARTE.md §2 comptage.gd/charge.gd
# pour la distinction.
#
# CE QUE CE BANC MONTRE : trois colons construits A LA MAIN (pas
# Objet.fabriquer, pas data/types.json:colon -- demonstration de cablage,
# pas integration au jeu). Deux ("guerrier_1"/"guerrier_2") portent
# l'attache { propriete: "guerrier", force } des le demarrage -- posee en
# donnee, aucun mecanisme de formation ici (attache_par_trait.gd n'est pas
# cable dans ce banc). Le troisieme ("recepteur") porte un canal
# proprietes.etats.pression_guerrier. A chaque tick, causes_de_attache(...)
# scanne les TROIS colons, exclut le recepteur par id, et retient une cause
# { position } pour chaque colon dont au moins une attache porte
# `propriete_visee` ("guerrier") -- calque sur banc_charge.gd:causes_de,
# filtre different (attache dans un Array, pas une propriete booleenne
# plate). Charge.avancer(...) recoit ces causes : la charge du recepteur
# monte tant que les deux porteurs restent dans sa `portee_charge`, franchit
# son seuil, pose `sous_pression_guerrier: true` sur ses proprietes --
# aucune ligne de charge.gd modifiee.
#
# CE QUE CE BANC NE FAIT PAS : aucun jugement.gd, aucun agir.gd, aucune
# decision. Le banc s'arrete au moment ou la propriete interne est posee --
# la LECTURE de cette propriete par jugement.gd (pression -> saillance ->
# decision) est un chantier ULTERIEUR, non ouvert ici.
#
# PORTEE VOLONTAIREMENT LIMITEE (pas d'interactivite) : les deux porteurs
# gardent leur attache pour toujours dans ce banc -- une fois le seuil
# franchi, la charge continue de monter (aucun plafond dans charge.gd), la
# propriete reste posee. La REVERSIBILITE de charge.gd (redescente, retrait
# de la propriete si les causes disparaissent) est prouvee par
# test_banc_contagion.gd, pas par ce banc en direct (aucun clic, aucune
# donnee ne retire jamais une attache ici).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge data/banc_contagion.json, construit les
#   trois colons A LA MAIN (Dictionary { id, position, proprietes }, sans
#   Objet.fabriquer). _process appelle causes_de_attache(...) puis
#   Charge.avancer(...) sur la liste complete des colons (charge.gd ignore
#   deja, en interne, toute chose sans cle "etats" -- meme geste que
#   banc_charge.gd:_process), met a jour l'affichage.
# - Fonction statique (pure, testable headless, voir
#   test_banc_contagion.gd) : causes_de_attache(objets, propriete_visee,
#   exclure_id) -- calque sur banc_charge.gd:causes_de, filtre par
#   PRESENCE d'un element { propriete: propriete_visee } dans
#   proprietes.attaches (Array), jamais une propriete plate.

const Charge = preload("res://scripts/charge.gd")
const Monde = preload("res://scripts/monde.gd")

const TAILLE_CARRE := 24.0
const TAILLE_MARQUEUR := 10.0

var _propriete_visee := ""
var _recepteur_id := ""
var _fenetre_moyenne := 60
var _couleur_porteur := Color.RED
var _couleur_non_porteur := Color.GRAY
var _couleur_marqueur := Color.YELLOW
var _monde := Monde.new()
var _colons: Array = []
var _noeuds: Dictionary = {}
var _marqueur_pression: ColorRect
var _historique_charge: Array = []
var _temps_ecoule := 0.0
var _dernier_sens := "aucun"
var _dernier_temps := 0.0
var _label_pression: Label
var _label_etat: Label
var _label_trace: Label
var _label_moyenne: Label

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_contagion.json")
	_propriete_visee = donnees.get("propriete_visee", "")
	_recepteur_id = donnees.get("recepteur_id", "")
	_fenetre_moyenne = int(donnees.get("fenetre_moyenne", 60))
	var canal_defaut: Dictionary = donnees.get("canal", {})

	var rgb_porteur: Array = donnees.get("couleur_porteur", [0.8, 0.2, 0.2])
	var rgb_non_porteur: Array = donnees.get("couleur_non_porteur", [0.4, 0.5, 0.7])
	var rgb_marqueur: Array = donnees.get("couleur_marqueur_pression", [1.0, 0.85, 0.1])
	_couleur_porteur = Color(rgb_porteur[0], rgb_porteur[1], rgb_porteur[2])
	_couleur_non_porteur = Color(rgb_non_porteur[0], rgb_non_porteur[1], rgb_non_porteur[2])
	_couleur_marqueur = Color(rgb_marqueur[0], rgb_marqueur[1], rgb_marqueur[2])

	var declarations: Array = donnees.get("colons", [])
	for decl in declarations:
		_ajouter_colon(decl, canal_defaut)

	_label_pression = _dessiner_label(Vector2(20.0, 20.0))
	_label_etat = _dessiner_label(Vector2(20.0, 44.0))
	_label_trace = _dessiner_label(Vector2(20.0, 68.0))
	_label_moyenne = _dessiner_label(Vector2(20.0, 92.0))
	_rafraichir_affichage()

func _ajouter_colon(decl: Dictionary, canal_defaut: Dictionary) -> void:
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	var position3 := Vector3(pos[0], pos[1], pos[2])
	var proprietes: Dictionary = {"attaches": decl.get("attaches_initiales", []).duplicate(true)}
	if decl.id == _recepteur_id:
		proprietes["etats"] = {"pression_guerrier": canal_defaut.duplicate(true)}
	var colon := {"id": decl.id, "position": position3, "proprietes": proprietes}
	_monde.ajouter(colon, "colon", position3)
	_colons.append(colon)
	_noeuds[colon.id] = _dessiner_carre(position3, _couleur_de(colon))
	if decl.id == _recepteur_id:
		_marqueur_pression = _dessiner_marqueur(position3)

func _process(delta: float) -> void:
	_temps_ecoule += delta
	var causes := causes_de_attache(_colons, _propriete_visee, _recepteur_id)
	var bascules := Charge.avancer(_colons, causes, delta)
	var recepteur := _colon_par_id(_recepteur_id)
	if bascules.has(recepteur.id):
		_dernier_sens = "UP" if recepteur.proprietes.has("sous_pression_guerrier") else "DOWN"
		_dernier_temps = _temps_ecoule

	var charge_actuelle: float = recepteur.proprietes.get("etats", {}).get("pression_guerrier", {}).get("charge", 0.0)
	_historique_charge.append(charge_actuelle)
	if _historique_charge.size() > _fenetre_moyenne:
		_historique_charge.pop_front()

	_rafraichir_affichage()

# Calque sur banc_charge.gd:causes_de -- meme geste (scanner un Array brut,
# filtrer, rendre des causes { position }, poids implicite 1.0 laisse a la
# charge de charge.gd), filtre DIFFERENT : une propriete plate
# (proprietes.get(cle, false)) ne peut pas tester une attache, qui vit dans
# un Array (proprietes.attaches, { propriete, force }) -- meme famille que
# le mode "contient_element_avec_champ" de comptage.gd, mais aucun appel a
# Comptage.compter ici : charge.gd fait deja la somme lui-meme, ce filtre
# ne fait que SELECTIONNER, jamais compter.
# `exclure_id` retire le colon interrogateur AVANT que la liste n'atteigne
# charge.gd -- l'auto-exclusion vit dans CE cablage, jamais dans charge.gd
# (qui ne sait pas qui pose la question), meme decision que le precedent
# banc_charge.gd:decider (source_pression, voir CARTE.md §6).
static func causes_de_attache(objets: Array, propriete_visee: String, exclure_id: String) -> Array:
	var causes: Array = []
	for chose in objets:
		if chose.id == exclure_id:
			continue
		for attache in chose.proprietes.get("attaches", []):
			if attache.get("propriete", "") == propriete_visee:
				causes.append({"position": chose.position})
				break
	return causes

func _colon_par_id(id: String) -> Dictionary:
	for colon in _colons:
		if colon.id == id:
			return colon
	return {}

func _porte_attache(colon: Dictionary) -> bool:
	for attache in colon.proprietes.get("attaches", []):
		if attache.get("propriete", "") == _propriete_visee:
			return true
	return false

func _couleur_de(colon: Dictionary) -> Color:
	return _couleur_porteur if _porte_attache(colon) else _couleur_non_porteur

func _dessiner_carre(position3: Vector3, couleur: Color) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(TAILLE_CARRE, TAILLE_CARRE)
	carre.color = couleur
	carre.position = Vector2(position3.x, position3.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _dessiner_marqueur(position3: Vector3) -> ColorRect:
	var marqueur := ColorRect.new()
	marqueur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marqueur.color = _couleur_marqueur
	marqueur.size = Vector2(TAILLE_MARQUEUR, TAILLE_MARQUEUR)
	marqueur.position = Vector2(position3.x, position3.y) - Vector2(TAILLE_MARQUEUR / 2.0, TAILLE_CARRE / 2.0 + TAILLE_MARQUEUR + 2.0)
	marqueur.visible = false
	add_child(marqueur)
	return marqueur

func _dessiner_label(position2: Vector2) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = position2
	add_child(label)
	return label

# Moyenne arithmetique d'un Array de comptes/charges. 0.0 sur un historique
# vide. Duplique depuis banc_comptage.gd/banc_convergence_attache.gd (meme
# fonction pure) -- troisieme copie de ce chantier, candidate a une
# promotion dans banc_commun.gd le jour ou un quatrieme banc en aurait
# besoin, non fait ici (hors perimetre).
static func _moyenne_glissante(historique: Array) -> float:
	if historique.is_empty():
		return 0.0
	var somme := 0.0
	for valeur in historique:
		somme += valeur
	return somme / historique.size()

func _rafraichir_affichage() -> void:
	var recepteur := _colon_par_id(_recepteur_id)
	for colon in _colons:
		var carre: ColorRect = _noeuds[colon.id]
		carre.color = _couleur_de(colon)

	var canal: Dictionary = recepteur.proprietes.get("etats", {}).get("pression_guerrier", {})
	var charge_actuelle: float = canal.get("charge", 0.0)
	var seuil: float = canal.get("seuil", 0.0)
	var pose: bool = recepteur.proprietes.has("sous_pression_guerrier")

	_marqueur_pression.visible = pose
	_label_pression.text = "pression_guerrier = %.2f / seuil = %.2f" % [charge_actuelle, seuil]
	_label_etat.text = "sous_pression_guerrier %s" % ("POSEE" if pose else "ABSENTE")
	_label_trace.text = "dernier franchissement : %s (t=%.1f)" % [_dernier_sens, _dernier_temps]
	_label_moyenne.text = "charge moyenne sur les %d derniers ticks : %.2f" % [_fenetre_moyenne, _moyenne_glissante(_historique_charge)]

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
