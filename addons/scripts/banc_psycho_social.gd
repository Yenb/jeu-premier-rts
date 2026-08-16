extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_psycho_social.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). AUCUN MECANISME DU COEUR TOUCHE
# NI CREE : les treize mecanismes qu'il compose sont appeles TELS QUELS.
#
# QUATRE LIGNES DANS UN SEUL BANC parce qu'elles INTERAGISSENT -- ce qui fait
# le gameplay est le cablage ENTRE elles (CLAUDE.md, « UN GAMEPLAY EST UNE
# COMPOSITION, JAMAIS UNE PIECE »). Livrees separement, elles ne rendraient
# que quatre mecanismes qui existaient deja.
#
# CE QU'ON DOIT VOIR. Deux colons face a un feu et a un allie blesse poses a
# distance EXACTEMENT egale : ils hesitent, le stress monte, l'hesitation leur
# coute de l'energie. Une nourriture attend au loin, saillance basse, ignoree.
# A mesure que l'energie descend, une sigmoide fait monter une deformation qui
# amplifie la saillance de tout ce qui est comestible POUR CE COLON : passe un
# point, la nourriture ecrase le reste et il va manger quoi qu'on dise, puis
# l'energie remonte, la deformation retombe, il revient a son dilemme. Le
# joueur peut poser une directive « va au feu » : elle AJOUTE une saillance
# concurrente, elle ne regle rien. Enfin un adversaire, au clavier : le VETERAN,
# qui porte deja une marque de combat, bascule en colere des le premier
# echange ; le NOVICE, A BIAIS DE BASE IDENTIQUE, doit d'abord en accumuler --
# et se rouille s'il arrete.
#
# LE CONSTAT QUI DECIDE TROIS DES QUATRE LIGNES : poids_verbes NE PESE JAMAIS
# ENTRE DEUX CIBLES. agir.gd:choisir choisit d'abord la CIBLE par le score
# (saillance + gain_inertie + engagement -- poids_verbes n'y entre pas), PUIS
# resout un verbe parmi ceux que la propriete gagnante propose. Monter
# poids_verbes.manger a 10 000 ne ferait jamais gagner la nourriture contre un
# feu : le colon mourrait de faim devant un repas. Les deux seules voies qui
# pesent, toutes deux utilisees ici :
#   - deformation.gd, qui amplifie une PROPRIETE pour CE colon seul et que les
#     trois couches de saillance lisent ;
#   - une ENTREE DE SAILLANCE SYNTHETIQUE ajoutee a "resultats" avant
#     dominance.gd -- litteralement ce qu'exige docs/design.md sous « Ordre et
#     tension » : un ordre ne supprime jamais une saillance, il en AJOUTE une.
#
# CONFLIT INTERNE. L'ecart se mesure sur "resultats" (att + prox + jugement,
# AVANT dominance) et JAMAIS sur "visibles" : dominance.gd a deja RETIRE toute
# entree dont l'ecart au sommet depasse forme.seuil_ecrasement, un ecart
# superieur n'y serait donc jamais mesurable. Il ne trie pas non plus -- le tri
# est du cablage.
#   DEDUPLICATION PAR CIBLE, decision de ce banc : deux entrees peuvent porter
#   LA MEME chose (la saillance naturelle du feu ET l'entree synthetique de la
#   directive qui le vise). Sans elle, un colon « hesiterait entre le feu et le
#   feu ». Seule la plus haute saillance PAR IDENTITE est gardee.
#   Le stress est un MIROIR PLAT, max(0, seuil_ecart - ecart), RECALCULE A NEUF
#   chaque tick et jamais accumule : c'est ce qui le rend reversible sans une
#   ligne de plus, seuil_etat.gd ne lisant qu'une cle PLATE et ne comparant que
#   vers le HAUT.
#
# COURBE NON LINEAIRE PAR BESOIN. La sigmoide est de l'arithmetique de cablage,
# zero .gd neuf : urgence = 1 / (1 + exp(-raideur * (seuil_critique -
# reserve/capacite))). Elle pilote la MAGNITUDE passee a Deformation.poser.
# MULTIPLIEE PAR delta, et ce n'est pas un detail : poser() n'a AUCUN delta, une
# magnitude fixe par image ferait monter le biais a une vitesse dependant de la
# machine. BORNEE PAR UN PLAFOND DE CABLAGE, et ce n'est pas un confort :
# avancer() decroit par soustraction FIXE, il n'existe donc AUCUN equilibre
# naturel et le biais monterait sans borne.
#   L'ecrasement litteral demande existe deja et n'a coute aucune ligne :
#   forme.seuil_ecrasement ne rend pas les autres options « moins
#   prioritaires », il les RETIRE de la liste.
#
# DIRECTIVES. entree_directive construit { chose, type, position, saillance,
# directive: true } et l'AJOUTE a "resultats" ; la couche 3 arbitre comme
# d'habitude, aucun cas particulier. C'EST UNE SAILLANCE CONCURRENTE, PAS UN
# BONUS ADDITIF -- agir.gd retient le MEILLEUR score, il n'additionne pas : la
# directive doit DEPASSER le sommet naturel pour etre suivie. La cle
# "directive" survit dans la decision, ce qui permet de prouver que le colon a
# obei A L'ORDRE et pas a sa propre saillance ; aucun mecanisme du coeur ne la
# lit.
#   LA DESOBEISSANCE EST PROUVEE PAR DEUX CHEMINS INDEPENDANTS : par le POIDS
#   (l'entree est ajoutee, la faim pese plus) et par un GATE PAR ETAT (quand un
#   etat vital est actif, l'entree n'est meme pas construite).
#
# APPRENTISSAGE. Epigenetique.poser tant que le colon combat, PAR INTERVALLE EN
# SECONDES et jamais a chaque image -- poser() n'a pas de delta. RESULTAT
# NEGATIF, interdit de le repayer : l'intervalle doit rester sous
# (modulateur_pose - plancher_suppression) / taux_decroissance, sinon la marque
# est effacee entre deux poses et n'accumule JAMAIS rien. Le plafond vit au
# CABLAGE, poser() n'en a aucun.
#   EXPRESSION.GD N'EST PAS APPELE, contournement intentionnel : rappele chaque
#   tick, exprimer() relit la valeur qu'il a lui-meme ecrite au tick precedent
#   et fait diverger sans borne la propriete visee. Le cablage lit donc
#   lui-meme le modulateur et le compose.
#   CE N'EST PAS UNE BIFURCATION PONDEREE : « le veteran bascule plus
#   facilement » passe par un SEUIL sur un miroir plat (biais de base +
#   modulateur plafonne), GATE SUR LA DECISION DE COMBAT -- sans ce gate un
#   veteran est furieux en permanence, sans adversaire, et accumule de
#   l'experience pour rien.
#
# UN SEUL ECRIVAIN DE surcout_action : depense.gd n'a QU'UN emplacement par
# canal et TROIS choses veulent y ecrire -- l'effort de marche, la lutte
# thermique, l'hesitation. Trois morceaux de cablage separes se detruiraient EN
# SILENCE, aucun test ne rougirait, la depense serait seulement fausse.
# poser_surcout_action somme puis ecrit UNE FOIS, et rend la DECOMPOSITION que
# l'affichage relit sans jamais rien recalculer. La contribution de stress est
# GATEE PAR L'ETAT, jamais par le miroir : depense.gd ne consulte jamais
# etat_effectif.gd.
#
# DEUX APPELS A SeuilEtat.avancer PAR TICK, sans collision (sa memoire est PAR
# ENTREE) et dans un ordre NON INTERCHANGEABLE : le catalogue LOCAL du banc
# AVANT le surcout, pour que le gate lise l'etat de CE tick ; le catalogue
# PARTAGE APRES la depense, pour que le seuil de faim compare la reserve de CE
# tick. Le colon ne porte AUCUNE propriete "temperature" : les entrees
# thermiques du catalogue partage sont pour lui des chemins morts silencieux.
#
# UN TICK DE RETARD, inherent : la decision d'un tick lit les etats poses au
# tick precedent. L'ordre inverse serait circulaire -- l'etat depend de la
# reserve, qui depend du surcout, qui depend de la decision.
#
# COLONS CONSTRUITS A LA MAIN (ni Objet.fabriquer ni data/types.json:colon) :
# sans composition ni materiau, donc ni masse ni densite a calculer.
# data/types.json n'est pas touche, rien a enregistrer dans
# test_lint_donnees.gd. Les deux proprietes du banc vivent dans un
# catalogue_local fusionne par-dessus data/types_choses.json, qui n'est pas
# touche non plus.
#
# QUATRE TOGGLES NE TIENNENT PAS SUR DEUX BOUTONS DE SOURIS : clic gauche =
# feu, clic droit = nourriture, touche D = directive, touche C = adversaire.
# Chaque bascule RECONSTRUIT le Monde du neant (monde.gd n'a aucune fonction de
# retrait) ; les colons y sont RE-AJOUTES PAR REFERENCE, leur etat interne est
# donc integralement preserve.
#
# NON CABLE, ET DIT : ni sommeil, ni chaleur, ni grief. Cette scene ne porte ni
# lieu de repos ni abri ; aucune entree n'a ete inventee pour un contenu qui
# n'existe pas, aucune barre vide n'a ete dessinee pour faire semblant.
#
# AUCUN NOM DE PROPRIETE EN DUR : les douze noms lus par le cablage arrivent de
# data/banc_psycho_social.json -- c'est ce qui permet au test de faire traverser
# le meme code par un domaine entierement invente.

const Perception = preload("res://scripts/perception.gd")
const Attaches = preload("res://scripts/attaches.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Jugement = preload("res://scripts/jugement.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Agir = preload("res://scripts/agir.gd")
const Deformation = preload("res://scripts/deformation.gd")
const Epigenetique = preload("res://scripts/epigenetique.gd")
const Depense = preload("res://scripts/depense.gd")
const Consommer = preload("res://scripts/consommer.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Temperature = preload("res://scripts/temperature.gd")
const Velocite = preload("res://scripts/velocite.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

# Cle de cablage POSEE SUR LE COLON, jamais dans data/types.json : l'horloge
# qui espace les appels a Epigenetique.poser (voir LIGNE 12 en tete). Vit sur
# l'entite plutot que dans une variable du Node pour que avancer_experience
# reste une fonction PURE testable sans instancier la scene.
const CLE_HORLOGE_MARQUE := "horloge_marque_combat"

var _config: Dictionary = {}
var _catalogue_etats: Dictionary = {}
var _catalogue_seuils_partages: Dictionary = {}
var _catalogue_deformations: Dictionary = {}
var _catalogue_epigenetique: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_actions: Dictionary = {}
var _profils_saillance: Dictionary = {}
var _menaces: Dictionary = {}
var _jugements: Dictionary = {}
var _catalogue_temperature: Dictionary = {}

var _colons: Array = []
var _choses: Dictionary = {}
var _actives: Dictionary = {}
var _sources_temperature: Array = []
var _monde
var _directive_active := false
var _temps := 0.0
var _cout_combat := 0.0

# Ce que le dernier tick a produit, PAR COLON -- relu tel quel par l'affichage,
# jamais recalcule (meme discipline que banc_faim_thermo.gd:decomposition).
var _infos: Dictionary = {}

var _labels: Dictionary = {}
var _label_entete: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_psycho_social.json")
	_catalogue_etats = _charger_json("res://data/etats.json")
	_catalogue_seuils_partages = _charger_json("res://data/seuils_etat.json")
	_catalogue_deformations = _charger_json("res://data/deformations.json")
	_catalogue_epigenetique = _charger_json("res://data/epigenetique.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_profils_saillance = _charger_json("res://data/profils_saillance.json")
	_menaces = _charger_json("res://data/menaces.json")
	_jugements = _charger_json("res://data/jugements.json")
	_catalogue_temperature = _charger_json("res://data/temperature.json")

	# Catalogue d'actions PARTAGE, complete par le vocabulaire propre au banc
	# (exception banc-jetable, patron banc_charge.gd) -- data/types_choses.json
	# n'est jamais touche sur le disque.
	_catalogue_actions = _charger_json("res://data/types_choses.json")
	var local: Dictionary = _config.get("catalogue_local", {})
	for cle in local:
		_catalogue_actions[cle] = local[cle]

	_sources_temperature = sources_temperature(_config)
	_directive_active = bool(_config.directive.get("active_au_depart", false))

	for decl in _config.get("choses", []):
		var chose: Dictionary = construire_chose(decl)
		_choses[chose.id] = chose
		_actives[chose.id] = bool(decl.get("active_au_depart", true))

	var declarations: Dictionary = _config.get("colons", {})
	for nom in declarations:
		_colons.append(construire_colon(String(nom), declarations[nom], _config))

	_reconstruire_monde()
	_construire_rendu()
	print(ligne_pose(_config))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_basculer_chose("feu")
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_basculer_chose("repas")
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_D:
			_directive_active = not _directive_active
			print("t=%.1f directive '%s' : %s" % [
				_temps, String(_config.directive.cible_id), "POSEE" if _directive_active else "RETIREE",
			])
		elif event.keycode == KEY_C:
			_basculer_chose("adversaire")

func _basculer_chose(id: String) -> void:
	if not _choses.has(id):
		push_error("banc_psycho_social : bascule d'une chose inconnue '%s'" % id)
		return
	_actives[id] = not _actives[id]
	# REMETTRE, c'est remettre une chose NEUVE -- reconstruite depuis sa
	# declaration, jamais celle qu'on vient de retirer : sans cela, rendre
	# l'allie rendrait un allie DEJA GUERI (sante pleine, propriete de blessure
	# absente), et le soin ne serait observable qu'une seule fois par lancement.
	# Vaut pour toutes les choses, aucune n'est nommee ici.
	if _actives[id]:
		for decl in _config.get("choses", []):
			if String(decl.id) == id:
				_choses[id] = construire_chose(decl)
				break
	_reconstruire_monde()
	print("t=%.1f %s : %s" % [_temps, id, "AJOUTE" if _actives[id] else "RETIRE"])

# monde.gd n'a AUCUNE fonction de retrait (dette recensee, CARTE.md §6) : une
# bascule reconstruit donc le Monde DU NEANT. Les colons y sont re-ajoutes PAR
# REFERENCE -- meme Dictionary, donc reserves, marques et etats_actifs sont
# integralement preserves ; seules les choses changent.
func _reconstruire_monde() -> void:
	var choses_actives: Array = []
	for id in _choses:
		if _actives.get(id, false):
			choses_actives.append(_choses[id])
	_monde = BancCommun.monde_depuis([
		{"choses": _colons, "type": "colon"},
		{"choses": choses_actives, "type": "chose", "type_depuis": "type_banc"},
	])

func _process(delta: float) -> void:
	_temps += delta

	var chose_directive = _chose_active(String(_config.directive.cible_id))
	var chose_repas = _chose_active("repas")
	var chose_allie = _chose_active("allie")
	var chose_adversaire = _chose_active("adversaire")

	# 1. La sigmoide, PUIS la deformation. poser() avant avancer() : une
	#    exposition de CE tick doit compter avant la decroissance de CE tick,
	#    sinon la marque fraiche est rabotee avant d'avoir servi.
	for colon in _colons:
		var urgence: float = urgence_faim(colon, _config)
		poser_deformation_faim(colon, urgence, delta, _config, _catalogue_deformations)
		Deformation.avancer(colon, delta, _catalogue_deformations)
		_infos[colon.id] = {"urgence": urgence}

	# 2. Les quatre couches, plus l'entree synthetique de la directive.
	for colon in _colons:
		var g: Dictionary = decider_et_memoriser(
			colon, _monde, _catalogue_canaux, _menaces, _profils_saillance,
			_catalogue_deformations, _jugements, _catalogue_actions,
			chose_directive if _directive_active else null, _config,
		)
		_infos[colon.id]["decision"] = g.decision
		_infos[colon.id]["resultats"] = g.resultats
		_infos[colon.id]["visibles"] = g.visibles
		_infos[colon.id]["cibles"] = saillances_par_cible(g.resultats)
		_infos[colon.id]["stress"] = poser_stress_interne(colon, g.resultats, _config)
		_infos[colon.id]["ardeur"] = poser_ardeur_combat(colon, g.decision, _config)

	# 3. Les seuils LOCAUX (stresse/colere) AVANT le surcout : le gate de stress
	#    doit lire l'etat de CE tick, jamais celui du precedent.
	var etats_avant: Dictionary = {}
	for colon in _colons:
		etats_avant[colon.id] = colon.proprietes.get("etats_actifs", []).duplicate()
	SeuilEtat.avancer(_colons, _config.seuils_locaux)

	# 4. UNE SEULE ecriture de surcout_action par colon (effort + thermo +
	#    stress + combat), plus les deux miroirs thermiques. Voir en-tete.
	var decisions: Dictionary = {}
	for colon in _colons:
		decisions[colon.id] = _infos[colon.id].decision
	for colon in _colons:
		var temp_locale: float = Temperature.locale(colon.position, _sources_temperature, _catalogue_temperature)
		_infos[colon.id]["temperature"] = temp_locale
		var au_contact: bool = combat_au_contact(colon, decisions[colon.id], chose_adversaire, _config)
		_infos[colon.id]["au_contact"] = au_contact
		_infos[colon.id]["surcout"] = poser_surcout_action(colon, temp_locale, au_contact, _config)

	# 4bis. Le cout de la vigueur de l'adversaire, ecrit A NEUF depuis le nombre
	#       de combattants -- unique ecrivain, meme discipline, autre entite.
	_cout_combat = poser_cout_combat(chose_adversaire, _colons, decisions, _config)

	# 5. Les reserves descendent -- mecanisme du coeur, appele tel quel.
	#    L'adversaire y entre comme n'importe quelle entite a reserves : depense.gd
	#    ne connait aucun type, il boucle sur ce qu'on lui donne.
	var entites: Array = _colons.duplicate()
	if chose_adversaire != null:
		entites.append(chose_adversaire)
	Depense.avancer(entites, delta)

	# 6. Le miroir de faim APRES la depense, puis les seuils PARTAGES.
	for colon in _colons:
		poser_manque_energie(colon, _config)
	SeuilEtat.avancer(_colons, _catalogue_seuils_partages)

	for colon in _colons:
		for ligne in lignes_changement(_temps, colon.id, changements_etats(
			etats_avant[colon.id], colon.proprietes.get("etats_actifs", []))):
			print(ligne)

	# 7. Apprentissage, repas, deplacement.
	for colon in _colons:
		var decision = _infos[colon.id].decision
		var en_combat: bool = combat_en_cours(colon, decision, _config)
		_infos[colon.id]["combat"] = en_combat
		_infos[colon.id]["experience"] = avancer_experience(
			colon, en_combat, delta, _config, _catalogue_epigenetique)
		_infos[colon.id]["mange"] = manger_si_possible(colon, decision, chose_repas, delta, _config)
		_infos[colon.id]["soigne"] = soigner_si_possible(colon, decision, chose_allie, delta, _config)
		var vitesse: float = vitesse_effective(colon, _config, _catalogue_etats)
		_infos[colon.id]["vitesse"] = vitesse
		if vitesse > 0.0 and decision != null and decision.has("position"):
			colon.position = BancCommun.bouger_vers(colon.position, decision.position, vitesse, delta)

	# 7bis. La guerison, UNE SEULE FOIS par tick et jamais par colon : deux
	#       soigneurs versent chacun dans la MEME reserve, mais l'etat de
	#       l'allie ne se juge qu'une fois, apres tous les versements.
	var gueri_avant: bool = chose_allie != null and not chose_allie.proprietes.has(String(_config.soin.propriete_blessure))
	var gueri: bool = mettre_a_jour_guerison(chose_allie, _config)
	if chose_allie != null and gueri != gueri_avant:
		print("t=%.1f allie : %s" % [_temps, "GUERI (il sort de la decision, sans sortir du monde)" if gueri else "de nouveau blesse"])

	# 7ter. VAINCU, IL SORT DU MONDE -- et non seulement de la decision, comme
	#       l'allie gueri : decision de Yael, « l'adversaire vaincu disparait, le
	#       clic le remet ». Meme geste exact que la touche C (monde.gd n'a
	#       aucune fonction de retrait, le Monde est reconstruit du neant), et le
	#       remettre reconstruit une chose NEUVE, donc a vigueur pleine.
	if chose_adversaire != null and est_vaincu(chose_adversaire, _config):
		_actives["adversaire"] = false
		_reconstruire_monde()
		print("t=%.1f adversaire : VAINCU (il sort du monde -- touche C pour en remettre un neuf)" % _temps)

	# 8. DERNIER appel du tick, contrat de velocite.gd : apres tout ce qui mute
	#    position, jamais avant.
	Velocite.avancer(_colons, delta)

	_rafraichir()
	queue_redraw()

func _chose_active(id: String):
	if not _choses.has(id) or not _actives.get(id, false):
		return null
	return _choses[id]

# ---- Fonctions PURES, testables headless (voir test_banc_psycho_social.gd) ----

# Le colon ne porte AUCUNE propriete 'temperature' (voir en-tete) et aucune
# composition. Un seul canal de reserve : son 'cout_base' est le metabolisme,
# pose ICI une fois pour toutes et jamais reecrit ; 'surcout_action' part a 0.0
# et n'est ecrit que par poser_surcout_action.
static func construire_colon(nom: String, decl: Dictionary, config: Dictionary) -> Dictionary:
	var pos: Array = decl.position
	var reserves: Dictionary = {}
	reserves[String(config.nom_reserve_energie)] = {
		"reserve": float(config.capacite_energie),
		"cout_base": float(config.metabolisme_base_par_s),
		"surcout_action": 0.0,
	}
	var marques: Dictionary = {}
	var depart: float = float(decl.get("modulateur_combat_depart", 0.0))
	if depart > 0.0:
		marques[String(config.nom_marque_combat)] = {"modulateur": depart, "age_marque": 0.0}
	var proprietes: Dictionary = {
		"reserves": reserves,
		"etats_actifs": [],
		"attaches": [],
		"forme": config.forme_colon.duplicate(true),
		"poids_verbes": config.poids_verbes_colon.duplicate(true),
		"canaux": config.canaux.duplicate(true),
		"canaux_config": config.canaux_config.duplicate(true),
		"deformation_sources": config.deformation_sources.duplicate(true),
		"deformation_etat": {},
		"marques_epigenetiques": marques,
		"biais_combat_base": float(decl.get("biais_combat_base", 0.0)),
	}
	proprietes[String(config.nom_vitesse)] = float(config.vitesse_base)
	return {
		"id": nom,
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": proprietes,
		"action_en_cours": {},
	}

# 'type_banc' est une cle de CABLAGE (le nom affiche et la couleur), jamais
# lue par un mecanisme du coeur -- monde.gd recoit le type en parametre, il ne
# le lit pas sur la chose.
static func construire_chose(decl: Dictionary) -> Dictionary:
	var pos: Array = decl.position
	var chose: Dictionary = {
		"id": String(decl.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": decl.proprietes.duplicate(true),
	}
	chose["type_banc"] = String(decl.get("type", "chose"))
	return chose

# Traduit les zones du banc dans la forme EXACTE que temperature.gd attend --
# la couleur de rendu reste dans la zone et n'entre jamais dans le calcul.
static func sources_temperature(config: Dictionary) -> Array:
	var sources: Array = []
	for zone in config.get("zones_temperature", []):
		var p: Array = zone.position
		sources.append({
			"position": Vector3(float(p[0]), float(p[1]), float(p[2])),
			"rayon": float(zone.rayon),
			"temperature": float(zone.temperature),
			"force": float(zone.force),
		})
	return sources

# LA SIGMOIDE (ligne 10). urgence = 1 / (1 + exp(-raideur * (seuil_critique -
# ratio))), ou ratio = reserve / capacite. Reserve pleine -> quasi 0.0, reserve
# exactement au seuil -> exactement 0.5, reserve vide -> quasi 1.0. Capacite
# nulle ou negative (config incoherente) : 0.0, jamais une division par zero.
static func urgence_faim(colon: Dictionary, config: Dictionary) -> float:
	var capacite: float = float(config.capacite_energie)
	if capacite <= 0.0:
		return 0.0
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	var ratio: float = float(canal.get("reserve", 0.0)) / capacite
	return 1.0 / (1.0 + exp(-float(config.raideur_sigmoide) * (float(config.seuil_critique_ratio) - ratio)))

# MULTIPLIEE PAR delta -- voir LIGNE 10 en tete : sans ce facteur, le biais
# monterait a une vitesse dependant du framerate. Passe par poser(), jamais par
# une ecriture directe dans deformation_etat : poser() refuse (push_error) toute
# source non declaree dans deformation_sources, garde qu'une ecriture a la main
# contournerait. Rend la magnitude reellement posee, pour l'affichage.
#
# LE PLAFOND EST ICI, ET IL EST OBLIGATOIRE -- RESULTAT NEGATIF MESURE PAR CE
# CHANTIER, ecrit pour qu'il ne soit pas repaye : deformation.gd:avancer decroit
# par SOUSTRACTION FIXE, jamais par une fraction du registre courant. Il n'existe
# donc AUCUN equilibre naturel entre la pose et la decroissance -- tant que le
# debit de pose depasse le taux, le registre monte LINEAIREMENT ET SANS BORNE.
# Une premiere calibration de ce banc tablait sur un point fixe « debit = taux » :
# le test l'a demolie, le biais atteignait 58 en vingt secondes et mettait plus
# de deux minutes a redescendre -- le banc ne revenait jamais a son dilemme. Le
# plafond vit donc au CABLAGE, exactement comme plafond_modification pour
# l'epigenetique (poser() n'en a aucun, ni ici ni la-bas). Consequence assumee :
# une fois au plafond, la pose s'arrete, le registre decroit d'un tick, la pose
# reprend -- le biais oscille d'une magnitude de tick autour du plafond, ce qui
# est invisible a l'ecran et sans effet sur l'arbitrage.
static func poser_deformation_faim(
	colon: Dictionary,
	urgence: float,
	delta: float,
	config: Dictionary,
	catalogue_deformations: Dictionary,
) -> float:
	var magnitude: float = float(config.gain_deformation_par_s) * urgence * delta
	if magnitude <= 0.0:
		return 0.0
	var source := String(config.source_deformation)
	var cible := String(config.cible_deformation)
	if Deformation.biais(colon, source, cible, catalogue_deformations) >= float(config.plafond_biais_faim):
		return 0.0
	Deformation.poser(colon, source, cible, magnitude)
	return magnitude

# LE TRI QUE dominance.gd NE FAIT PAS (constat (F)), plus la DEDUPLICATION PAR
# CIBLE (voir LIGNE 9 en tete) : deux entrees de 'resultats' peuvent porter la
# MEME chose -- sa saillance naturelle et l'entree synthetique de la directive
# qui la vise. Sans cela, un colon « hesiterait entre le feu et le feu ».
# L'identite est chose.id quand l'entree en porte une (origine proximite ou
# jugement), le type sinon (origine attache, qui n'a AUCUNE identite de chose --
# voir attaches.gd). Rend un Array de { cible, saillance }, trie par saillance
# DECROISSANTE, jamais mute l'entree d'origine.
static func saillances_par_cible(resultats: Array) -> Array:
	var par_cible: Dictionary = {}
	for entree in resultats:
		var identite := ""
		var chose = entree.get("chose", null)
		if chose is Dictionary and chose.has("id"):
			identite = String(chose.id)
		else:
			identite = "type:%s" % String(entree.get("type", ""))
		var saillance: float = float(entree.get("saillance", 0.0))
		if not par_cible.has(identite) or saillance > float(par_cible[identite]):
			par_cible[identite] = saillance
	var liste: Array = []
	for identite in par_cible:
		liste.append({"cible": identite, "saillance": float(par_cible[identite])})
	liste.sort_custom(func(a, b): return a.saillance > b.saillance)
	return liste

# INF quand il y a moins de DEUX cibles distinctes : un colon qui n'a qu'une
# option n'hesite pas -- un ecart infini, jamais 0.0 (qui se lirait comme le
# conflit maximal, exactement l'inverse).
static func ecart_deux_plus_hautes(resultats: Array) -> float:
	var cibles: Array = saillances_par_cible(resultats)
	if cibles.size() < 2:
		return INF
	return float(cibles[0].saillance) - float(cibles[1].saillance)

# MIROIR PLAT, recalcule a neuf chaque tick et JAMAIS accumule par `+=` : c'est
# ce qui le rend reversible sans une ligne de plus (seuil_etat.gd retire l'etat
# au franchissement descendant). Plus les deux options sont proches, plus le
# stress est haut ; ecart au-dela de seuil_ecart (ou moins de deux options) ->
# exactement 0.0.
static func poser_stress_interne(colon: Dictionary, resultats: Array, config: Dictionary) -> float:
	var ecart: float = ecart_deux_plus_hautes(resultats)
	var stress: float = 0.0
	if ecart != INF:
		stress = max(0.0, float(config.seuil_ecart) - ecart)
	colon.proprietes[String(config.nom_stress_interne)] = stress
	return stress

# LE PLAFOND VIT ICI, jamais dans epigenetique.gd : poser() ajoute sans borne
# haute (voir data/epigenetique.json). Marque absente -> 0.0, point neutre
# legitime (avancer() la retire sous son plancher, elle n'est pas inventee).
static func modulateur_experience(colon: Dictionary, config: Dictionary) -> float:
	var marques: Dictionary = colon.proprietes.get("marques_epigenetiques", {})
	var canal: Dictionary = marques.get(String(config.nom_marque_combat), {})
	return min(float(canal.get("modulateur", 0.0)), float(config.plafond_modification))

# SECOND MIROIR PLAT : biais de base (identique pour tous les colons de ce
# banc) + modulateur plafonne. C'est lui que le catalogue LOCAL compare pour
# poser l'etat de colere -- un SEUIL, jamais une bifurcation ponderee (voir
# LIGNE 12 en tete).
#
# GATE SUR LA DECISION, ET CE N'EST PAS UN RAFFINEMENT MAIS UNE CONDITION DE
# CORRECTION -- DEFAUT REEL TROUVE EN LANCANT LA SCENE, invisible au test :
# ecrit inconditionnellement, ce miroir mettait le VETERAN en colere des
# t=0.1 s, SANS AUCUN ADVERSAIRE dans la scene (son experience de depart suffit
# a franchir le seuil). Pire, combat_en_cours lit cet etat : il accumulait donc
# de l'experience en permanence, montait a son plafond tout seul, et NE SE
# ROUILLAIT JAMAIS -- la ligne 12 devenait inobservable. L'ardeur ne se mesure
# que FACE A QUELQU'UN : hors combat le miroir vaut exactement 0.0, et
# seuil_etat.gd retire la colere de lui-meme au franchissement descendant.
# Precedent exact du miroir GATE : 'manque_graisse' dans
# banc_graisse_accoutumance.gd, ecrit seulement sous l'etat de famine, pour la
# meme raison (un miroir inconditionnel y declarait un colon mort de faim au
# premier tick). LE GATE EST LA DECISION, jamais la seule perception : un
# adversaire visible mais ecrase par dominance.gd n'est pas un combat.
static func poser_ardeur_combat(colon: Dictionary, decision, config: Dictionary) -> float:
	var ardeur := 0.0
	if decision != null and String(decision.get("action", "")) == String(config.verbe_combat):
		ardeur = float(colon.proprietes.get("biais_combat_base", 0.0)) + modulateur_experience(colon, config)
	colon.proprietes[String(config.nom_ardeur_combat)] = ardeur
	return ardeur

# GATE PAR ETAT (patron banc_elimination_salete.gd). ecrase_vital non nul : la
# directive passe outre le besoin vital, l'entree est TOUJOURS ajoutee -- c'est
# ce reglage qui permet de prouver la desobeissance PAR LE POIDS, separement du
# gate.
static func directive_autorisee(colon: Dictionary, config: Dictionary) -> bool:
	var directive: Dictionary = config.directive
	if int(directive.get("ecrase_vital", 0)) != 0:
		return true
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	for etat in directive.get("etats_vitaux", []):
		if actifs.has(String(etat)):
			return false
	return true

# UNE SAILLANCE CONCURRENTE DE PLUS, jamais un reglage du comportement (voir
# LIGNE 11 en tete). Rend null -- et l'appelant n'ajoute alors rien -- quand la
# cible n'existe pas dans la scene ou quand le gate vital est ferme. La cle
# 'directive' survit dans la decision (agir.gd duplique l'entree retenue) : elle
# permet de savoir POURQUOI le colon a choisi cette cible, aucun mecanisme du
# coeur ne la lit.
static func entree_directive(colon: Dictionary, chose_cible, config: Dictionary):
	if chose_cible == null:
		return null
	if not directive_autorisee(colon, config):
		return null
	return {
		"chose": chose_cible,
		"type": String(chose_cible.get("type_banc", "directive")),
		"position": chose_cible.position,
		"saillance": float(config.directive.bonus_score),
		"directive": true,
	}

# Jamais negatif : au-dessus de la cible de confort, il ne fait pas « moins
# froid que zero », il ne fait plus froid du tout.
static func froid_ressenti(temp_locale: float, temp_cible: float) -> float:
	return max(0.0, temp_cible - temp_locale)

static func chaud_ressenti(temp_locale: float, seuil_chaud: float) -> float:
	return max(0.0, temp_locale - seuil_chaud)

# Proportionnel a la velocite REELLE, quel qu'ait ete le mecanisme qui a
# deplace le colon (velocite.gd derive passivement, en fin de tick). Velocite
# absente (tout premier tick) : 0.0, jamais une valeur inventee.
static func surcout_effort(colon: Dictionary, config: Dictionary) -> float:
	var velocite: Vector3 = colon.proprietes.get("velocite", Vector3.ZERO)
	return float(config.coef_effort) * velocite.length()

static func surcout_thermo(froid: float, chaud: float, config: Dictionary) -> float:
	return froid * float(config.cout_par_degre_froid) + chaud * float(config.cout_par_degre_chaud)

# GATE PAR L'ETAT, jamais par le miroir directement : c'est ce qui donne son
# role au marqueur pur data/etats.json:stresse. Un colon dont le stress monte
# mais n'a pas encore franchi le seuil ne paie RIEN -- l'hesitation coute a
# partir du moment ou elle est reconnue comme telle, pas avant.
static func surcout_stress(colon: Dictionary, config: Dictionary) -> float:
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	if not actifs.has(String(config.etat_stresse)):
		return 0.0
	return float(config.coef_stress) * float(colon.proprietes.get(String(config.nom_stress_interne), 0.0))

# LE QUATRIEME TERME, et il n'a DELIBEREMENT PAS son propre point d'ecriture :
# combattre coute de l'energie, mais ce cout passe par poser_surcout_action
# comme les trois autres. Lui donner son propre `surcout_action` aurait ecrase
# les trois premiers EN SILENCE -- c'est exactement le piege que ce banc existe
# pour documenter (audit, constat C). Le combat est GRATUIT pour personne :
# soigner coute (transfert d'energie), combattre coute aussi -- sans quoi il
# serait le seul geste sans prix du banc.
static func surcout_combat(en_combat: bool, config: Dictionary) -> float:
	return float(config.combat.cout_energie_combat_par_s) if en_combat else 0.0

# VRAI seulement si le colon a REELLEMENT resolu le verbe de combat ET qu'il est
# a portee : viser un adversaire de loin n'est pas le combattre. Meme gate exact
# que manger_si_possible / soigner_si_possible, et c'est voulu -- une seule
# notion de « a portee de main » dans ce banc.
static func combat_au_contact(colon: Dictionary, decision, chose_adversaire, config: Dictionary) -> bool:
	if decision == null or chose_adversaire == null:
		return false
	if String(decision.get("action", "")) != String(config.verbe_combat):
		return false
	return colon.position.distance_to(chose_adversaire.position) <= float(config.combat.rayon_combat)

# UNIQUE ECRIVAIN de canal.surcout_action, et des deux miroirs thermiques --
# voir en-tete, « UN SEUL ECRIVAIN ». MUTE le colon en place ; rend la
# DECOMPOSITION ({ effort, thermo, stress, total, froid, chaud }) pour que
# l'affichage la relise sans jamais rien recalculer. Canal absent (config
# incoherente) : push_error, rien n'est ecrit dans le canal, la decomposition
# rendue porte un total nul -- jamais un canal invente a la volee.
static func poser_surcout_action(colon: Dictionary, temp_locale: float, en_combat: bool, config: Dictionary) -> Dictionary:
	var froid: float = froid_ressenti(temp_locale, float(config.temp_cible))
	var chaud: float = chaud_ressenti(temp_locale, float(config.seuil_chaud))
	var effort: float = surcout_effort(colon, config)
	var thermo: float = surcout_thermo(froid, chaud, config)
	var stress: float = surcout_stress(colon, config)
	var combat: float = surcout_combat(en_combat, config)
	var total: float = effort + thermo + stress + combat

	var proprietes: Dictionary = colon.proprietes
	proprietes[String(config.nom_froid_ressenti)] = froid
	proprietes[String(config.nom_chaud_ressenti)] = chaud

	var nom_reserve := String(config.nom_reserve_energie)
	var reserves: Dictionary = proprietes.get("reserves", {})
	if not reserves.has(nom_reserve):
		push_error("banc_psycho_social : canal de reserve '%s' absent du colon, surcout non pose" % nom_reserve)
		return {"effort": effort, "thermo": thermo, "stress": stress, "combat": combat,
			"total": 0.0, "froid": froid, "chaud": chaud}
	reserves[nom_reserve]["surcout_action"] = total
	return {
		"effort": effort, "thermo": thermo, "stress": stress, "combat": combat,
		"total": total, "froid": froid, "chaud": chaud,
	}

# UNIQUE ECRIVAIN du cout_base de la vigueur de l'adversaire, ET IL LE REECRIT A
# NEUF chaque tick depuis le nombre de combattants presents -- jamais un '+='
# accumule : deux colons qui arrivent puis repartent laisseraient sinon un cout
# fantome qui viderait l'adversaire tout seul. Meme discipline que
# poser_surcout_action, sur une autre entite.
# LA VIGUEUR NE VA NULLE PART -- depense.gd et non Consommer.transferer : un
# combat DETRUIT, il ne deplace pas de la matiere d'un corps a l'autre. Le
# transfert aurait credite une reserve du colon (« combattre nourrit le
# vainqueur »), physiquement faux. C'est la difference exacte avec le soin.
# Rend le cout pose (0.0 si personne ne le combat), pour l'affichage.
static func poser_cout_combat(chose_adversaire, colons: Array, decisions: Dictionary, config: Dictionary) -> float:
	if chose_adversaire == null:
		return 0.0
	var nom := String(config.combat.nom_reserve_vigueur)
	var reserves: Dictionary = chose_adversaire.get("proprietes", {}).get("reserves", {})
	if not reserves.has(nom):
		push_error("banc_psycho_social : canal de reserve '%s' absent de l'adversaire, cout non pose" % nom)
		return 0.0
	var combattants := 0
	for colon in colons:
		if combat_au_contact(colon, decisions.get(colon.id, null), chose_adversaire, config):
			combattants += 1
	var cout: float = float(combattants) * float(config.combat.cout_combat_par_s)
	reserves[nom]["cout_base"] = cout
	reserves[nom]["surcout_action"] = 0.0
	return cout

# Vaincu = vigueur epuisee. depense.gd borne deja a 0.0 par le bas, la
# comparaison est donc un simple <= et jamais un seuil invente.
static func est_vaincu(chose_adversaire, config: Dictionary) -> bool:
	if chose_adversaire == null:
		return false
	var canal: Dictionary = chose_adversaire.get("proprietes", {}).get("reserves", {}).get(
		String(config.combat.nom_reserve_vigueur), {})
	return float(canal.get("reserve", 0.0)) <= 0.0

# Le miroir de faim, ecrit APRES Depense.avancer pour que le seuil PARTAGE
# compare la reserve de CE tick. Borne a 0.0 par le bas : une reserve remontee
# au-dessus de sa capacite (le repas la borne deja, mais rien dans le coeur ne
# le garantit) ne donnerait pas un « manque negatif ».
static func poser_manque_energie(colon: Dictionary, config: Dictionary) -> float:
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	var manque: float = max(0.0, float(config.capacite_energie) - float(canal.get("reserve", 0.0)))
	colon.proprietes[String(config.nom_manque_energie)] = manque
	return manque

# GATE DE CABLAGE : reserve vide -> 0.0, sans qu'aucun etat ne soit pose
# (depense.gd ne consulte jamais etat_effectif.gd, et etat_effectif.gd ne pose
# jamais aucun etat). Sinon la vitesse de base modulee par tous les etats
# actifs, composition multiplicative deleguee a etat_effectif.gd.
static func vitesse_effective(colon: Dictionary, config: Dictionary, catalogue_etats: Dictionary) -> float:
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	if float(canal.get("reserve", 0.0)) <= 0.0:
		return 0.0
	return EtatEffectif.valeur(colon, String(config.nom_vitesse), catalogue_etats)

# LES QUATRE COUCHES, plus l'entree synthetique de la directive INSEREE ENTRE
# la couche 2 et la couche 3 -- c'est le seul endroit possible : apres, elle ne
# passerait plus par l'arbitrage de dominance.gd ; avant, il n'y aurait rien a
# quoi l'ajouter. Rend { decision, resultats, visibles, perceptions }, meme
# forme que banc_feu.gd:decider / banc_charge.gd:decider.
# 'resultats' rendu porte DEJA l'entree de directive : c'est bien la liste
# exacte qui part vers dominance.gd que le conflit interne doit mesurer -- un
# ordre concurrent fait partie de ce entre quoi le colon est tiraille.
static func decider(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	jugements: Dictionary,
	catalogue_actions: Dictionary,
	chose_directive,
	config: Dictionary,
) -> Dictionary:
	var perceptions := Perception.percevoir(colon, monde, catalogue_canaux)
	var att := Attaches.evaluer(perceptions, colon, menaces, catalogue_deformations)
	var prox := Proximite.evaluer(perceptions, colon, profils_saillance, catalogue_deformations)
	var jug := Jugement.evaluer(perceptions, colon, att + prox, jugements, catalogue_deformations)
	var resultats: Array = att + prox + jug
	var entree = entree_directive(colon, chose_directive, config)
	if entree != null:
		resultats.append(entree)
	var visibles := Dominance.visibles(resultats, colon)
	var decision = Agir.choisir(visibles, colon, catalogue_actions, monde)
	return {"decision": decision, "resultats": resultats, "visibles": visibles, "perceptions": perceptions}

static func decider_et_memoriser(
	colon: Dictionary,
	monde,
	catalogue_canaux: Dictionary,
	menaces: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	jugements: Dictionary,
	catalogue_actions: Dictionary,
	chose_directive,
	config: Dictionary,
) -> Dictionary:
	var r := decider(colon, monde, catalogue_canaux, menaces, profils_saillance,
		catalogue_deformations, jugements, catalogue_actions, chose_directive, config)
	colon.action_en_cours = Agir.etat_courant(r.decision)
	return r

# Les DEUX conditions de la consigne, sans priorite entre elles : l'etat de
# colere deja actif, OU le verbe resolu ce tick. La premiere fait durer
# l'accumulation au-dela du moment ou l'adversaire cesse d'etre la cible ; la
# seconde l'amorce pour un colon qui n'est pas encore en colere.
static func combat_en_cours(colon: Dictionary, decision, config: Dictionary) -> bool:
	if colon.proprietes.get("etats_actifs", []).has(String(config.etat_colere)):
		return true
	if decision == null:
		return false
	return String(decision.get("action", "")) == String(config.verbe_combat)

# CADENCE EN SECONDES DE SIMULATION, jamais un appel par image : poser() n'a
# pas de delta (voir LIGNE 12 en tete). L'horloge vit sur le colon pour que
# cette fonction reste pure et testable sans la scene. Hors combat elle est
# REMISE A ZERO plutot que gelee -- sinon un colon qui alterne des fractions de
# seconde de combat accumulerait par petits bouts un intervalle qu'il n'a
# jamais tenu. Epigenetique.avancer est appele INCONDITIONNELLEMENT (la
# decroissance ne s'arrete jamais, meme pendant un combat -- c'est la pose qui
# la depasse). Rend { poses, modulateur, horloge }.
static func avancer_experience(
	colon: Dictionary,
	en_combat: bool,
	delta: float,
	config: Dictionary,
	catalogue_epigenetique: Dictionary,
) -> Dictionary:
	var intervalle: float = float(config.intervalle_pose_marque_s)
	var horloge: float = float(colon.proprietes.get(CLE_HORLOGE_MARQUE, 0.0))
	var poses := 0
	if en_combat and intervalle > 0.0:
		horloge += delta
		while horloge >= intervalle:
			horloge -= intervalle
			Epigenetique.poser(colon, String(config.nom_marque_combat), catalogue_epigenetique)
			poses += 1
	else:
		horloge = 0.0
	colon.proprietes[CLE_HORLOGE_MARQUE] = horloge
	Epigenetique.avancer(colon, delta, catalogue_epigenetique)
	return {"poses": poses, "modulateur": modulateur_experience(colon, config), "horloge": horloge}

# TRANSFERT DESTRUCTIF (consommer.gd, appele tel quel) et non un nombre ajoute
# a la main : la nourriture se VIDE de ce que le colon gagne, exactement.
# PRE-BORNAGE DU TAUX plutot qu'ecretage apres coup : rien dans le coeur ne
# borne le HAUT d'une reserve (limite deja mesuree par banc_fertilite.gd), et
# ecreter apres transfert DETRUIRAIT de la matiere que la source a deja perdue.
# Rend la quantite reellement transferee (0.0 sur tout cas neutre).
static func manger_si_possible(colon: Dictionary, decision, chose_repas, delta: float, config: Dictionary) -> float:
	if decision == null or chose_repas == null or delta <= 0.0:
		return 0.0
	if String(decision.get("action", "")) != String(config.repas.verbe_repas):
		return 0.0
	if colon.position.distance_to(chose_repas.position) > float(config.repas.rayon_repas):
		return 0.0
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	var place: float = max(0.0, float(config.capacite_energie) - float(canal.get("reserve", 0.0)))
	var taux: float = min(float(config.repas.taux_repas_par_s), place / delta)
	if taux <= 0.0:
		return 0.0
	var r: Dictionary = Consommer.transferer(
		chose_repas, colon, String(config.nom_reserve_repas), String(config.nom_reserve_energie), taux, delta)
	return float(r.quantite)

# LE MEME GESTE QUE manger_si_possible, DANS L'AUTRE SENS -- le colon est la
# SOURCE et l'allie le receveur : ce que l'allie gagne en sante, le colon le
# perd en energie, EXACTEMENT (Consommer.transferer, appele tel quel). C'est ce
# qui fait que soigner rapproche la faim critique, donc que la ligne 9 et la
# ligne 10 se touchent au lieu de vivre cote a cote.
# LA VOIE 'cout_base NEGATIF sur l'allie' (patron du blesse qui dort dans
# banc_fatigue_circadien.gd:poser_couts) marcherait et a ete ECARTEE PAR
# DECISION DE YAEL : elle fait sortir la sante du neant et ne coute rien au
# soigneur.
# PRE-BORNAGE DU TAUX par la place restante, jamais un ecretage apres coup :
# _crediter ne borne pas le haut, et ecreter apres transfert DETRUIRAIT de
# l'energie que le colon a deja perdue. Rend la quantite reellement transferee
# (0.0 sur tout cas neutre).
static func soigner_si_possible(colon: Dictionary, decision, chose_allie, delta: float, config: Dictionary) -> float:
	if decision == null or chose_allie == null or delta <= 0.0:
		return 0.0
	var soin: Dictionary = config.soin
	if String(decision.get("action", "")) != String(soin.verbe_soin):
		return 0.0
	if colon.position.distance_to(chose_allie.position) > float(soin.rayon_soin):
		return 0.0
	var canal: Dictionary = chose_allie.get("proprietes", {}).get("reserves", {}).get(String(soin.nom_reserve_sante), {})
	var place: float = max(0.0, float(soin.capacite_sante) - float(canal.get("reserve", 0.0)))
	var taux: float = min(float(soin.taux_soin_par_s), place / delta)
	if taux <= 0.0:
		return 0.0
	var r: Dictionary = Consommer.transferer(
		colon, chose_allie, String(config.nom_reserve_energie), String(soin.nom_reserve_sante), taux, delta)
	return float(r.quantite)

# DEUX RETRAITS, ET IL FAUT LES DEUX -- ils visent deux couches DIFFERENTES, et
# n'en faire qu'un laisse un defaut silencieux :
#   - 'blesse_visible' (la propriete de blessure) sort de chose.proprietes,
#     sinon agir.gd:_action la scanne encore contre le catalogue d'actions et
#     resout toujours 'secourir' sur un allie deja gueri ;
#   - 'profil_saillance' est GELE sous 'profil_saillance_gele', sinon
#     proximite.gd continue de le rendre saillant et le colon reste plante sur
#     quelqu'un qu'il ne peut plus aider.
# Retirer le premier seul donne une cible muette qui attire encore ; retirer le
# second seul donne un verbe qui se resout sur une chose invisible.
# LE GEL PLUTOT QUE L'EFFACEMENT, patron EXACT de banc_p1.gd:
# mettre_a_jour_occupation : la chose reste dans le Monde, elle sort seulement
# de la DECISION -- monde.gd n'a de toute facon aucune fonction de retrait
# (dette recensee), et un banc qui detruirait la chose ne pourrait plus jamais
# la rendre. REVERSIBLE PAR CONSTRUCTION : si la sante redescend sous la
# capacite, tout revient. Rien dans cette scene ne la fait redescendre -- c'est
# le clic qui remet un allie neuf --, mais la reversibilite est verrouillee par
# test plutot que supposee. Rend true quand l'allie est gueri.
static func mettre_a_jour_guerison(chose_allie, config: Dictionary) -> bool:
	if chose_allie == null:
		return false
	var soin: Dictionary = config.soin
	var proprietes: Dictionary = chose_allie.proprietes
	var canal: Dictionary = proprietes.get("reserves", {}).get(String(soin.nom_reserve_sante), {})
	var gueri: bool = float(canal.get("reserve", 0.0)) >= float(soin.capacite_sante)
	var propriete_blessure := String(soin.propriete_blessure)
	if gueri:
		proprietes.erase(propriete_blessure)
		if proprietes.has("profil_saillance"):
			proprietes["profil_saillance_gele"] = proprietes["profil_saillance"]
			proprietes.erase("profil_saillance")
	else:
		proprietes[propriete_blessure] = true
		if proprietes.has("profil_saillance_gele"):
			proprietes["profil_saillance"] = proprietes["profil_saillance_gele"]
			proprietes.erase("profil_saillance_gele")
	return gueri

# Compare deux instantanes d'etats_actifs. seuil_etat.gd rend les ids ayant
# bascule, jamais QUELS etats -- d'ou cette comparaison, cote cablage.
static func changements_etats(avant: Array, apres: Array) -> Dictionary:
	var gagnes: Array = []
	var perdus: Array = []
	for etat in apres:
		if not avant.has(etat):
			gagnes.append(String(etat))
	for etat in avant:
		if not apres.has(etat):
			perdus.append(String(etat))
	return {"gagnes": gagnes, "perdus": perdus}

static func lignes_changement(t: float, id: String, changements: Dictionary) -> Array:
	var lignes: Array = []
	for etat in changements.get("gagnes", []):
		lignes.append("t=%.1f %s : etat POSE %s" % [t, id, String(etat)])
	for etat in changements.get("perdus", []):
		lignes.append("t=%.1f %s : etat RETIRE %s" % [t, id, String(etat)])
	return lignes

static func ligne_pose(config: Dictionary) -> String:
	return ("t=0.0 banc pose -- seuil_ecart %.2f (conflit en dessous) / seuil_ecrasement %.2f " +
		"(invisible au-dela) ; sigmoide : seuil %.2f de la capacite, raideur %.1f ; " +
		"directive '%s' bonus %.2f, ecrase_vital %d") % [
		float(config.seuil_ecart),
		float(config.forme_colon.seuil_ecrasement),
		float(config.seuil_critique_ratio),
		float(config.raideur_sigmoide),
		String(config.directive.cible_id),
		float(config.directive.bonus_score),
		int(config.directive.get("ecrase_vital", 0)),
	]

static func texte_label_colon(colon: Dictionary, info: Dictionary, config: Dictionary) -> String:
	var proprietes: Dictionary = colon.proprietes
	var canal: Dictionary = proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {})
	var cibles: Array = info.get("cibles", [])
	var haut := "-"
	var second := "-"
	if cibles.size() >= 1:
		haut = "%s %.2f" % [String(cibles[0].cible), float(cibles[0].saillance)]
	if cibles.size() >= 2:
		second = "%s %.2f" % [String(cibles[1].cible), float(cibles[1].saillance)]
	var ecart: float = ecart_deux_plus_hautes(info.get("resultats", []))
	var noms: Array = []
	for etat in proprietes.get("etats_actifs", []):
		noms.append(String(etat))
	noms.sort()
	var decision = info.get("decision", null)
	var verbe := "-"
	var suffixe := ""
	if decision != null:
		verbe = String(decision.get("action", ""))
		if verbe == "":
			verbe = "(aucun verbe)"
		if bool(decision.get("directive", false)):
			suffixe = "  <- DIRECTIVE"
	var surcout: Dictionary = info.get("surcout", {})
	return ("%s\nenergie %.1f / %.1f   vitesse %.0f\n1re %s\n2e  %s\necart %s (seuil %.2f)   stress %.2f\n" +
		"surcout %.2f = effort %.2f + thermo %.2f + stress %.2f + combat %.2f\n" +
		"experience %.3f   ardeur %.2f   urgence %.2f\netat : %s\nverbe : %s%s") % [
		String(colon.id),
		float(canal.get("reserve", 0.0)), float(config.capacite_energie), float(info.get("vitesse", 0.0)),
		haut, second,
		("inf" if ecart == INF else "%.2f" % ecart), float(config.seuil_ecart),
		float(info.get("stress", 0.0)),
		float(surcout.get("total", 0.0)), float(surcout.get("effort", 0.0)),
		float(surcout.get("thermo", 0.0)), float(surcout.get("stress", 0.0)),
		float(surcout.get("combat", 0.0)),
		modulateur_experience(colon, config), float(info.get("ardeur", 0.0)),
		float(info.get("urgence", 0.0)),
		" + ".join(noms) if not noms.is_empty() else "-",
		verbe, suffixe,
	]

# ---- Rendu (impur, Node) -- aucune decision, seulement des noeuds. ----

func _construire_rendu() -> void:
	var couche := CanvasLayer.new()
	add_child(couche)
	_label_entete = _creer_label(16)
	_label_entete.position = Vector2(12.0, 8.0)
	couche.add_child(_label_entete)
	_label_aide = _creer_label(13)
	_label_aide.position = Vector2(12.0, 32.0)
	_label_aide.text = ("clic GAUCHE : feu on/off   |   clic DROIT : nourriture on/off   |   " +
		"touche D : directive on/off   |   touche C : adversaire on/off")
	couche.add_child(_label_aide)
	for colon in _colons:
		var label := _creer_label(12)
		add_child(label)
		_labels[colon.id] = label
	var camera := Camera2D.new()
	camera.position = Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur)) / 2.0
	camera.zoom = Vector2(0.85, 0.85)
	camera.enabled = true
	add_child(camera)

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	# Contour sombre : le meme label doit rester lisible sur le fond vert comme
	# sur le bleu de la zone froide.
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _rafraichir() -> void:
	var taille: float = float(_config.taille_colon)
	for colon in _colons:
		var label: Label = _labels[colon.id]
		label.position = Vector2(colon.position.x, colon.position.y) + Vector2(taille, taille) * 0.6
		label.text = texte_label_colon(colon, _infos.get(colon.id, {}), _config)
	var allie = _chose_active("allie")
	var texte_allie := "-"
	if allie != null:
		var canal: Dictionary = allie.proprietes.get("reserves", {}).get(String(_config.soin.nom_reserve_sante), {})
		texte_allie = "%.0f / %.0f%s" % [
			float(canal.get("reserve", 0.0)), float(_config.soin.capacite_sante),
			"" if allie.proprietes.has(String(_config.soin.propriete_blessure)) else " GUERI",
		]
	_label_entete.text = "t=%.1f s   directive : %s   feu : %s   nourriture : %s   adversaire : %s   allie : %s" % [
		_temps,
		"POSEE" if _directive_active else "-",
		"la" if _actives.get("feu", false) else "-",
		"la" if _actives.get("repas", false) else "-",
		"la" if _actives.get("adversaire", false) else "-",
		texte_allie,
	]

func _draw() -> void:
	var fond: Array = _config.couleur_fond
	draw_rect(Rect2(Vector2.ZERO, Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur))),
		Color(float(fond[0]), float(fond[1]), float(fond[2])))
	for zone in _config.get("zones_temperature", []):
		var p: Array = zone.position
		var c: Array = zone.couleur
		draw_circle(Vector2(float(p[0]), float(p[1])), float(zone.rayon),
			Color(float(c[0]), float(c[1]), float(c[2]), 0.45))

	var taille_chose: float = float(_config.taille_chose)
	for decl in _config.get("choses", []):
		var id := String(decl.id)
		if not _actives.get(id, false):
			continue
		var chose: Dictionary = _choses[id]
		var c: Array = decl.couleur
		# La couleur de guerison est lue sur la DECLARATION, jamais sur un id en
		# dur : une chose qui n'en declare pas garde la sienne, quoi qu'il lui
		# arrive. Le critere est l'absence de la propriete de blessure -- la
		# MEME que mettre_a_jour_guerison retire, jamais un second test qui
		# pourrait diverger d'elle.
		if decl.has("couleur_gueri") and not chose.proprietes.has(String(_config.soin.propriete_blessure)):
			c = decl.couleur_gueri
		var centre := Vector2(chose.position.x, chose.position.y)
		draw_rect(Rect2(centre - Vector2(taille_chose, taille_chose) / 2.0,
			Vector2(taille_chose, taille_chose)), Color(float(c[0]), float(c[1]), float(c[2])))
		_dessiner_barres_chose(chose, centre + Vector2(-taille_chose / 2.0, taille_chose * 0.7))

	var taille: float = float(_config.taille_colon)
	for colon in _colons:
		var centre := Vector2(colon.position.x, colon.position.y)
		var actifs: Array = colon.proprietes.get("etats_actifs", [])
		var brut: Array = _config.colons[colon.id].couleur
		var couleur := Color(float(brut[0]), float(brut[1]), float(brut[2]))
		if actifs.has(String(_config.etat_colere)):
			var cc: Array = _config.couleur_colon_colere
			couleur = Color(float(cc[0]), float(cc[1]), float(cc[2]))
		elif actifs.has(String(_config.etat_stresse)):
			var cs: Array = _config.couleur_colon_stresse
			couleur = Color(float(cs[0]), float(cs[1]), float(cs[2]))
		draw_rect(Rect2(centre - Vector2(taille, taille) / 2.0, Vector2(taille, taille)), couleur)
		_dessiner_barres(colon, centre + Vector2(-taille, taille * 0.8))
		_dessiner_directive(colon, centre)

	_dessiner_sigmoide()

# Une barre par reserve DECLAREE dans data:barres_choses que la chose porte
# REELLEMENT -- aucune chose n'est nommee ici, et une chose sans reserve n'en
# dessine aucune. Meme discipline que les barres de colon : une FRACTION d'un
# maximum lu en donnee, jamais un nombre brut en pixels.
func _dessiner_barres_chose(chose: Dictionary, origine: Vector2) -> void:
	var reserves: Dictionary = chose.proprietes.get("reserves", {})
	var largeur := float(_config.taille_chose)
	var i := 0
	for barre in _config.get("barres_choses", []):
		var nom := String(barre.reserve)
		if not reserves.has(nom):
			continue
		var f: float = clamp(float(reserves[nom].get("reserve", 0.0)) / max(float(barre.capacite), 0.0001), 0.0, 1.0)
		var c: Array = barre.couleur
		var haut := origine + Vector2(0.0, float(i) * 7.0)
		draw_rect(Rect2(haut, Vector2(largeur, 5.0)), Color(0.0, 0.0, 0.0, 0.5))
		draw_rect(Rect2(haut, Vector2(largeur * f, 5.0)), Color(float(c[0]), float(c[1]), float(c[2])))
		i += 1

# Quatre barres par colon, dans cet ordre : energie, stress, experience, ardeur.
# Chacune est une FRACTION d'un maximum lu en donnee -- jamais un nombre brut
# dessine en pixels, qui mentirait des que la calibration change.
func _dessiner_barres(colon: Dictionary, origine: Vector2) -> void:
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(String(_config.nom_reserve_energie), {})
	var info: Dictionary = _infos.get(colon.id, {})
	var barres := [
		{"f": float(canal.get("reserve", 0.0)) / max(float(_config.capacite_energie), 0.0001), "c": Color(0.4, 0.9, 0.4)},
		{"f": float(info.get("stress", 0.0)) / max(float(_config.seuil_ecart), 0.0001), "c": Color(0.95, 0.6, 0.15)},
		{"f": modulateur_experience(colon, _config) / max(float(_config.plafond_modification), 0.0001), "c": Color(0.55, 0.45, 0.95)},
		{"f": float(info.get("ardeur", 0.0)) / max(float(_config.seuils_locaux.ardeur_combat.seuil) * 2.0, 0.0001), "c": Color(0.9, 0.25, 0.25)},
	]
	var largeur := 70.0
	var hauteur := 5.0
	for i in range(barres.size()):
		var haut := origine + Vector2(0.0, float(i) * (hauteur + 2.0))
		draw_rect(Rect2(haut, Vector2(largeur, hauteur)), Color(0.0, 0.0, 0.0, 0.5))
		var f: float = clamp(float(barres[i].f), 0.0, 1.0)
		draw_rect(Rect2(haut, Vector2(largeur * f, hauteur)), barres[i].c)

# LA LIGNE POINTILLEE N'EST PAS DECORATIVE : elle n'est tracee que si l'entree
# synthetique est REELLEMENT construite pour CE colon (directive posee, cible
# presente, gate vital ouvert) -- elle rend donc visible, sans un nombre, le
# moment exact ou un besoin critique fait taire l'ordre du joueur.
func _dessiner_directive(colon: Dictionary, centre: Vector2) -> void:
	if not _directive_active:
		return
	var cible = _chose_active(String(_config.directive.cible_id))
	if entree_directive(colon, cible, _config) == null:
		return
	var c: Array = _config.couleur_directive
	draw_dashed_line(centre, Vector2(cible.position.x, cible.position.y),
		Color(float(c[0]), float(c[1]), float(c[2])), 2.0, 10.0)

# LA COURBE, dessinee depuis la MEME fonction que le banc utilise (urgence_faim
# sur un colon fictif) -- jamais une seconde formule recopiee, qui pourrait
# diverger de celle qui decide reellement. Un point par colon, a sa reserve
# courante : on voit le colon glisser le long de la courbe.
func _dessiner_sigmoide() -> void:
	var s: Dictionary = _config.sigmoide
	var o: Array = s.origine
	var origine := Vector2(float(o[0]), float(o[1]))
	var largeur: float = float(s.largeur)
	var hauteur: float = float(s.hauteur)
	var ca: Array = s.couleur_axes
	var couleur_axes := Color(float(ca[0]), float(ca[1]), float(ca[2]))
	draw_rect(Rect2(origine, Vector2(largeur, hauteur)), Color(0.0, 0.0, 0.0, 0.45))
	draw_line(origine + Vector2(0.0, hauteur), origine + Vector2(largeur, hauteur), couleur_axes, 1.0)
	draw_line(origine, origine + Vector2(0.0, hauteur), couleur_axes, 1.0)
	# Le seuil critique, en vertical : c'est lui que la reserve franchit.
	var x_seuil: float = origine.x + largeur * float(_config.seuil_critique_ratio)
	draw_line(Vector2(x_seuil, origine.y), Vector2(x_seuil, origine.y + hauteur), couleur_axes, 1.0)

	var cc: Array = s.couleur_courbe
	var couleur_courbe := Color(float(cc[0]), float(cc[1]), float(cc[2]))
	var n: int = int(s.echantillons)
	var fictif: Dictionary = {"proprietes": {"reserves": {String(_config.nom_reserve_energie): {"reserve": 0.0}}}}
	var precedent := Vector2.ZERO
	for i in range(n + 1):
		var ratio: float = float(i) / float(n)
		fictif.proprietes.reserves[String(_config.nom_reserve_energie)]["reserve"] = ratio * float(_config.capacite_energie)
		var u: float = urgence_faim(fictif, _config)
		var point := Vector2(origine.x + largeur * ratio, origine.y + hauteur * (1.0 - u))
		if i > 0:
			draw_line(precedent, point, couleur_courbe, 2.0)
		precedent = point

	for colon in _colons:
		var canal: Dictionary = colon.proprietes.get("reserves", {}).get(String(_config.nom_reserve_energie), {})
		var r: float = clamp(float(canal.get("reserve", 0.0)) / max(float(_config.capacite_energie), 0.0001), 0.0, 1.0)
		var u2: float = float(_infos.get(colon.id, {}).get("urgence", 0.0))
		var brut: Array = _config.colons[colon.id].couleur
		draw_circle(Vector2(origine.x + largeur * r, origine.y + hauteur * (1.0 - u2)), 4.0,
			Color(float(brut[0]), float(brut[1]), float(brut[2])))

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
