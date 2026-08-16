extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_marche_competence.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « prix + specialisation +
# habitude + competence » (audit prealable audit_economie_logistique_prealable.md,
# lignes 9, 10, 11 et 12 -- les QUATRE au verdict CABLABLE, CONFIRME a l'ecriture :
# AUCUN MECANISME DU COEUR TOUCHE NI CREE). Compose HUIT mecanismes deja fermes,
# TOUS APPELES TELS QUELS : somme.gd, comptage.gd, perception.gd, proximite.gd,
# deformation.gd, epigenetique.gd, depense.gd, consommer.gd (+ portee.gd et
# monde.gd).
#
# QUATRE LIGNES, UN SEUL BANC -- parce qu'elles INTERAGISSENT (CLAUDE.md, « UN
# GAMEPLAY EST UNE COMPOSITION, JAMAIS UNE PIECE »). Forger coute de l'energie,
# donc affame, donc fait monter la DEMANDE, donc le PRIX ; forger PRODUIT du
# lingot, donc fait monter l'OFFRE, donc redescendre le prix ; forger accumule la
# COMPETENCE, qui monte la saillance de la forge ; et l'HABITUDE, qui accelere la
# production. Livrees separement, ces quatre lignes ne rendraient que quatre
# mecanismes qui existaient deja.
#
# PREMIER APPELANT REEL DE scripts/somme.gd, ecrit sans appelant par le chantier
# precedent « pour que le cinquieme consommateur n'ecrive pas une cinquieme
# copie ». C'est ce banc, et il n'en a ecrit aucune.
#
# CE QU'ON DOIT VOIR. Un atelier a gauche (la forge et deux tas), un comptoir a
# droite (trois tas). Trois colons : un FORGERON deja competent, un APPRENTI qui
# ne sait rien, un NOVICE poste au comptoir. Les trois lisent le meme monde et
# n'en tirent pas les memes nombres.
#   1. LE PRIX. Le novice voit les cinq tas et trouve le lingot bon marche ; les
#      deux forgerons ne voient que le tas de l'atelier et le trouvent cher. Le
#      meme lingot, au meme instant, a deux prix -- parce que le prix est un
#      champ DERIVE ecrit sur chaque colon, jamais un etat pose sur un marche.
#      Clic gauche : un tas disparait, le prix de qui le voyait monte, celui des
#      autres ne bouge pas d'une decimale.
#   2. LA SPECIALISATION. La forge est ORANGE VIF pour le forgeron et terne pour
#      le novice : sa saillance est multipliee par (1 + biais) POUR LUI SEUL. Le
#      novice n'a AUCUNE deformation -- pas parce qu'un cas particulier l'exclut,
#      mais parce que sa competence effective est nulle et qu'une magnitude nulle
#      ne se pose pas.
#   3. L'HABITUDE. Touche 1/2/3 : un colon se met a forger. Sa barre verte monte
#      en trois secondes, sa vitesse de forge avec elle, et le tas de l'atelier
#      grossit plus vite. Il s'arrete : la barre retombe en six secondes -- il a
#      perdu son rythme.
#   4. LE PLANCHER. Le forgeron arrete de forger. Sa barre orange descend, passe
#      SOUS le trait rouge du plancher, et la marque finit par etre RETIREE par
#      epigenetique.gd (ligne console). Sa competence effective, elle, s'arrete
#      net sur le trait : le veteran rouille reste un forgeron. L'apprenti, lui,
#      a un plancher NUL -- il retombe a zero.
#
# ---------------------------------------------------------------------------
# LES QUATRE CONSTATS DE L'AUDIT QUI DECIDENT CE CABLAGE, relus dans le code
# avant d'ecrire une ligne.
#
# (9) LE PRIX NE VIT PAS DANS UN OBJET-MARCHE (docs/design.md, « Les collectifs
#     n'existent pas »). Il n'y a aucune entite 'marche' ici : chaque colon porte
#     ses propres 'prix_lingot'/'prix_bois', RECALCULES A NEUF chaque tick et
#     ecrits PAR-DESSUS, JAMAIS un '+=' -- c'est la seule chose qui empeche un
#     champ derive de DERIVER (patron banc_bonheur.gd:poser_bonheur, unique
#     ecrivain). Et parce que l'offre est sommee sur ce que CE colon PERCOIT,
#     « deux colons n'estiment pas le meme prix » sort gratuitement de la
#     perception, sans une ligne pour le demander.
#     DEUX QUESTIONS, DEUX FICHIERS, jamais un seul : l'OFFRE est un TOTAL de
#     grandeur (somme.gd:reserves), la DEMANDE est un COMPTE d'entites
#     (comptage.gd:compter). comptage.gd rend un int et ne totalise rien -- c'est
#     exactement pour ca que somme.gd existe.
# (10) poids_verbes NE PESE JAMAIS ENTRE DEUX CIBLES (agir.gd choisit la cible au
#     score, PUIS resout un verbe). Monter poids_verbes.forger a 10 000 ne ferait
#     jamais gagner la forge. La seule voie qui laisse deux entites lire le meme
#     monde differemment est deformation.gd, indexee PAR PERCEVANT.
# (11) L'HABITUDE PASSE PAR LE CABLAGE, jamais par expression.gd (voir plus bas).
# (12) plancher_suppression N'EST PAS UN PLANCHER DE VALEUR -- c'est un seuil de
#     SUPPRESSION : sous lui, epigenetique.gd RETIRE l'entree entiere. Route (a)
#     de l'audit, retenue par Yael : CLAMP A LA LECTURE dans le cablage,
#     competence_effective = max(plancher_competence, modulateur), avec un
#     modulateur de 0.0 quand la marque a ete retiree. Patron litteral
#     banc_graisse_accoutumance.gd:modulateur_accoutumance. CONSEQUENCE ACCEPTEE,
#     dite plutot que masquee : age_marque repart de zero a la prochaine pose --
#     l'anciennete de la competence est PERDUE, seule sa valeur plancher survit.
# ---------------------------------------------------------------------------
#
# LE PLANCHER EST UNE DONNEE PAR COLON, ET C'EST UNE DECISION DE CE CHANTIER, pas
# de la consigne. Ecrit comme une constante du cablage, max(0.3, modulateur)
# donnerait 0.3 au NOVICE aussi (marque absente -> modulateur 0.0), et « la forge
# n'est pas plus attractive pour lui » serait FAUX tous tests verts. Le plancher
# vit donc dans la declaration de chaque colon (data/banc_marche_competence.json:
# colons[].plancher_competence -- 0.3 pour le veteran, 0.0 pour les deux autres),
# patron exact de biais_combat_base dans banc_psycho_social.gd. Ce qu'il dit :
# « ce que mon metier m'a laisse », jamais « ce que tout le monde a ».
#
# UN SEUL ECRIVAIN DE surcout_action (piege recense quatre fois dans le depot,
# patron banc_faim_thermo.gd/banc_psycho_social.gd). depense.gd calcule
# reserve -= (cout_base + surcout_action) * delta : il n'y a QU'UN emplacement par
# canal, deux morceaux de cablage qui y ecrivent s'ecrasent EN SILENCE, aucun test
# ne rougit, la depense est seulement fausse. poser_surcout_action est l'UNIQUE
# ecrivain ici. Ce banc n'a qu'une source de surcout (la forge) -- la discipline
# est tenue quand meme, parce qu'un deuxieme ecrivain ajoute plus tard n'aurait
# aucun endroit ou se declarer.
#
# EXPRESSION.GD N'EST PAS APPELE -- contournement INTENTIONNEL et documente,
# jamais un oubli. RESULTAT NEGATIF MESURE QUATRE FOIS dans le depot
# (data/epigenetique.json: exposition_radioactive, accoutumance_froid,
# experience_combat ; banc_bonheur.gd) : exprimer() relit par _lire_chemin la
# valeur DEJA ECRITE au tick precedent et fait DIVERGER SANS BORNE la propriete
# visee au lieu de refleter la marque courante. Le cablage lit donc lui-meme les
# deux modulateurs et les compose (competence_effective, vitesse_forge_effective).
# Verrouille NEGATIVEMENT par test : test_banc_marche_competence.gd relit CE
# FICHIER sur le disque et exige qu'aucun preload n'y pointe vers ce mecanisme
# dormant. Le test compose le chemin lui-meme, morceau par morceau, pour que la
# phrase que vous lisez ne fasse pas rougir son propre verrou.
#
# LES TROIS PLAFONDS VIVENT AU CABLAGE, ET AUCUN N'EST DECORATIF. epigenetique.gd
# n'a AUCUNE borne haute (poser() ajoute sans plafond) et deformation.gd non plus
# -- avancer() y decroit par SOUSTRACTION FIXE, il n'existe donc AUCUN equilibre
# naturel ni aucune asymptote : tant que le debit de pose depasse le taux, le
# registre monte LINEAIREMENT ET SANS BORNE (resultat negatif deja mesure quatre
# fois, voir data/deformations.json). plafond_habitude borne
# vitesse_forge_effective, plafond_biais_competence et plafond_biais_habitude
# bornent chacun leur source. Les trois sont verrouilles par test.
#
# CADENCE DE POSE : intervalle en SECONDES DE SIMULATION, jamais un appel par
# image -- epigenetique.gd:poser n'a pas de delta, poser a chaque image ferait
# monter les marques a une vitesse dependant de la machine. MAIS l'intervalle
# n'est pas libre : il doit rester sous (modulateur_pose - plancher_suppression) /
# taux_decroissance pour LES DEUX marques, sinon celle qui est en dessous est
# effacee entre deux poses et n'accumule JAMAIS rien, sans que rien ne rougisse
# (resultat negatif mesure par « graisse + accoutumance », voir docs/ETAT.md). La
# borne mordante ici est celle de habitude_forge (0.375 s), pas celle de
# competence_forge (0.4 s). Verrouille par test contre les nombres REELS du disque.
#
# POSER AVANT AVANCER, pour les marques comme pour les deformations : une
# exposition de CE tick doit compter avant la decroissance de CE tick, sinon la
# marque fraiche est rabotee avant d'avoir servi (patron banc_psycho_social.gd).
#
# LE GATE DE PORTEE EST REEL, ET LA SCENE N'EN MONTRE QU'UN COTE. Ni la forge ni
# les deformations ne s'appliquent a un colon hors de portee_forge (Portee.
# en_portee, mecanisme partage). Dans cette scene le forgeron et l'apprenti sont
# a portee, le novice ne l'est PAS -- il ne pourrait donc pas forger meme si on
# le lui demandait, et c'est verrouille par test plutot que laisse a la souris.
#
# LES COLONS NE SE DEPLACENT PAS et ne decident rien : ce banc monte la couche 1
# (perception.gd) et la couche 2 (proximite.gd), NI dominance.gd, NI agir.gd, NI
# ciblage.gd. Choix assume, meme decoupage que banc_temps_anticipation.gd -- ce
# chantier observe des CHAMPS DERIVES (un prix, une saillance, une vitesse), pas
# un agent qui traverse une carte. On voit la forge devenir plus attractive pour
# le forgeron ; qu'il s'y rende demande la chaine complete de decision, et ce
# n'est pas ce chantier.
#
# COLONS, FORGE ET TAS CONSTRUITS A LA MAIN (pas Objet.fabriquer, meme statut que
# banc_faim_thermo.gd/banc_bonheur.gd/banc_temps_anticipation.gd) : ni composition
# ni materiau, donc data/types.json n'est pas touche et rien n'est a enregistrer
# dans scripts/test_lint_donnees.gd.
#
# ECART A LA CONSIGNE, SIGNALE PLUTOT QUE CODE EN SILENCE : la consigne demandait
# « toggle au clic » pour les deux bascules. Trois colons a forger ne tiennent pas
# sur deux boutons de souris. CLIC GAUCHE = retire un tas a tour de role puis
# aucun (patron banc_bonheur.gd:source_suivante) ; TOUCHES 1/2/3 = bascule la
# forge du colon correspondant. Precedent exact : banc_biomes.gd (fleches) et
# banc_psycho_social.gd (touches D et C), meme raison.
#
# Chaque bascule de tas RECONSTRUIT le Monde DU NEANT (monde.gd n'a AUCUNE
# fonction de retrait, dette recensee CARTE.md §6 -- meme idiome que
# banc_psycho_social.gd:_reconstruire_monde) ; colons, forge et tas restants y
# sont RE-AJOUTES PAR REFERENCE, leur etat interne est integralement preserve.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les six fichiers de donnees et construit la
#   scene ; _unhandled_input porte les deux bascules et ne calcule jamais rien ;
#   _process appelle avancer_tick et lit ses resultats pour l'affichage et la
#   console ; _draw dessine tout.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_marche_competence.gd) : avancer_tick et tout ce qu'elle enchaine.
#   LE TICK N'EST JAMAIS RECONSTITUE DANS LE TEST : il appelle avancer_tick, la
#   MEME fonction que _process (regle d'etat de CLAUDE.md).
#
# AUCUN NOM DE PROPRIETE, DE MARQUE NI DE SOURCE EN DUR : nom_reserve_energie/
# nom_reserve_masse/nom_reserve_minerai/nom_manque_energie/nom_plancher_competence/
# nom_marque_competence/nom_marque_habitude/source_deformation_competence/
# source_deformation_habitude/cible_deformation, plus 'propriete'/'nom_prix' par
# marchandise, arrivent tous de data/banc_marche_competence.json -- c'est ce qui
# permet au test de faire traverser le meme code par un domaine entierement
# invente.

const Perception = preload("res://scripts/perception.gd")
const Proximite = preload("res://scripts/proximite.gd")
const Deformation = preload("res://scripts/deformation.gd")
const Epigenetique = preload("res://scripts/epigenetique.gd")
const Depense = preload("res://scripts/depense.gd")
const Consommer = preload("res://scripts/consommer.gd")
const Comptage = preload("res://scripts/comptage.gd")
const Somme = preload("res://scripts/somme.gd")
const Portee = preload("res://scripts/portee.gd")
const Monde = preload("res://scripts/monde.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

var _config: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _profils_saillance: Dictionary = {}
var _catalogue_deformations: Dictionary = {}
var _catalogue_epigenetique: Dictionary = {}
var _catalogue_comptages: Dictionary = {}

var _colons: Array = []
var _forge: Dictionary = {}
var _tas: Dictionary = {}
var _tas_actifs: Dictionary = {}
var _monde
var _retire: int = -1
var _veut_forger: Dictionary = {}
var _horloges: Dictionary = {}
var _marque_vue: Dictionary = {}

var _temps: float = 0.0
var _horloge_trace: float = 0.0
var _demande: int = 0
# Ce que le dernier tick a produit, PAR COLON -- relu tel quel par l'affichage,
# jamais recalcule (meme discipline que banc_faim_thermo.gd:decomposition).
var _infos: Dictionary = {}

var _labels: Dictionary = {}
var _label_compteur: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_marche_competence.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_profils_saillance = _charger_json("res://data/profils_saillance.json")
	_catalogue_deformations = _charger_json("res://data/deformations.json")
	_catalogue_epigenetique = _charger_json("res://data/epigenetique.json")
	_catalogue_comptages = _charger_json("res://data/comptages.json")

	_forge = construire_forge(_config)
	for decl in _config.get("tas", []):
		var tas: Dictionary = construire_tas(decl, _config)
		_tas[tas.id] = tas
		_tas_actifs[tas.id] = true
	for decl in _config.get("colons", []):
		var colon: Dictionary = construire_colon(decl, _config)
		_colons.append(colon)
		_veut_forger[colon.id] = bool(decl.get("forge_au_depart", false))
		_horloges[colon.id] = 0.0
		_marque_vue[colon.id] = float(decl.get("modulateur_competence_depart", 0.0)) > 0.0
	# AUCUN tas retire au depart (index hors de la liste) : le banc lance sans un
	# clic montre deja trois prix qui divergent.
	_retire = _config.get("tas_retirables", []).size()

	_reconstruire_monde()
	_construire_rendu()
	print(ligne_pose(_config))

func _unhandled_input(evenement: InputEvent) -> void:
	# Le clic et la touche ne font que basculer un drapeau : aucune decision,
	# aucun calcul.
	if evenement is InputEventMouseButton and evenement.pressed \
			and evenement.button_index == MOUSE_BUTTON_LEFT:
		_retire = tas_suivant(_retire, _config.get("tas_retirables", []).size())
		_appliquer_retrait()
		print(ligne_retrait(_temps, _nom_tas_retire()))
	elif evenement is InputEventKey and evenement.pressed and not evenement.echo:
		var rang: int = int(evenement.keycode) - int(KEY_1)
		if rang >= 0 and rang < _colons.size():
			var id = _colons[rang].id
			_veut_forger[id] = not bool(_veut_forger.get(id, false))
			print(ligne_bascule_forge(_temps, String(id), bool(_veut_forger[id])))

func _process(delta: float) -> void:
	_temps += delta

	var resultat: Dictionary = avancer_tick(
		_colons, _monde, _forge, _tas_production(), _veut_forger, _horloges, delta,
		_config, _catalogue_canaux, _profils_saillance, _catalogue_deformations,
		_catalogue_epigenetique, _catalogue_comptages)
	_infos = resultat.infos
	_horloges = resultat.horloges
	_demande = int(resultat.demande)

	# La SUPPRESSION de la marque de competence est l'evenement que la ligne 12
	# existe pour montrer -- sans cette trace, il se produirait en silence.
	for colon in _colons:
		var presente: bool = colon.proprietes.get("marques_epigenetiques", {}).has(
			String(_config.nom_marque_competence))
		if bool(_marque_vue.get(colon.id, false)) and not presente:
			print(ligne_marque_retiree(_temps, String(colon.id), colon, _config))
		_marque_vue[colon.id] = presente

	_horloge_trace += delta
	if _horloge_trace >= float(_config.intervalle_trace_s):
		_horloge_trace = 0.0
		for colon in _colons:
			print(ligne_trace(_temps, colon, _infos.get(colon.id, {}), _config))

	_rafraichir()
	queue_redraw()

func _tas_production():
	var id := String(_config.tas_production)
	if not _tas.has(id) or not bool(_tas_actifs.get(id, false)):
		return null
	return _tas[id]

func _nom_tas_retire() -> String:
	var retirables: Array = _config.get("tas_retirables", [])
	if _retire < 0 or _retire >= retirables.size():
		return ""
	return String(retirables[_retire])

func _appliquer_retrait() -> void:
	var retire := _nom_tas_retire()
	for id in _tas:
		_tas_actifs[id] = String(id) != retire
	_reconstruire_monde()

# monde.gd n'a AUCUNE fonction de retrait (dette recensee CARTE.md §6) : une
# bascule reconstruit donc le Monde DU NEANT. Colons, forge et tas restants y sont
# re-ajoutes PAR REFERENCE -- memes Dictionary, donc reserves, marques et
# deformations sont integralement preservees ; seule la presence des tas change.
func _reconstruire_monde() -> void:
	var tas_actifs: Array = []
	for id in _tas:
		if bool(_tas_actifs.get(id, false)):
			tas_actifs.append(_tas[id])
	_monde = BancCommun.monde_depuis([
		{"choses": _colons, "type": "colon"},
		{"choses": [_forge], "type": "forge"},
		{"choses": tas_actifs, "type": "tas", "type_depuis": "type_banc"},
	])

# ---- Fonctions PURES, testables headless ----

# UN TICK COMPLET, l'ordre compris. Statique et sans noeud : le test rejoue
# EXACTEMENT ce que la scene execute, jamais une reconstitution parallele qui
# pourrait deriver. MUTE colons/forge/tas en place ; rend { infos, horloges,
# demande }.
#
# L'ORDRE N'EST PAS LIBRE, cinq contraintes le fixent :
#   (1) le gate de forge (toggle ET portee) AVANT tout -- il decide du surcout,
#       de la production et de la pose des marques, les trois doivent lire la
#       MEME reponse.
#   (2) poser_surcout_action AVANT Depense.avancer -- sinon la depense de ce tick
#       utiliserait le surcout du precedent.
#   (3) poser_manque_energie APRES Depense.avancer -- la demande doit compter la
#       reserve de CE tick, jamais celle du precedent.
#   (4) la demande AVANT les prix -- les trois colons doivent estimer leur prix
#       depuis LE MEME nombre de demandeurs, sinon « seule la perception les
#       separe » serait faux.
#   (5) poser AVANT avancer, pour les marques comme pour les deformations (voir
#       en-tete) ; et la saillance lue EN DERNIER, apres la deformation de ce
#       tick -- sinon l'ecran montrerait toujours le biais du tick precedent.
static func avancer_tick(
	colons: Array,
	monde,
	forge: Dictionary,
	tas_production,
	veut_forger: Dictionary,
	horloges: Dictionary,
	delta: float,
	config: Dictionary,
	catalogue_canaux: Dictionary,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
	catalogue_epigenetique: Dictionary,
	catalogue_comptages: Dictionary,
) -> Dictionary:
	var infos: Dictionary = {}
	var horloges_apres: Dictionary = {}
	var en_forge: Dictionary = {}

	# (1) Qui forge REELLEMENT ce tick.
	for colon in colons:
		var portee_ok: bool = a_portee_forge(colon, forge, config)
		en_forge[colon.id] = bool(veut_forger.get(colon.id, false)) and portee_ok
		infos[colon.id] = {"a_portee": portee_ok, "en_forge": bool(en_forge[colon.id])}

	# (2) UNIQUE ECRIVAIN de surcout_action, puis la depense -- mecanisme du
	#     coeur, appele tel quel.
	for colon in colons:
		infos[colon.id]["surcout"] = poser_surcout_action(colon, bool(en_forge[colon.id]), config)
	Depense.avancer(colons, delta)

	# (3) Le miroir PLAT, puis (4) la DEMANDE : un COMPTE d'entites (comptage.gd),
	#     jamais un total.
	for colon in colons:
		infos[colon.id]["manque_energie"] = poser_manque_energie(colon, config)
	var demande: int = Comptage.compter(colons, String(config.comptage_ref), catalogue_comptages)

	# L'OFFRE PERCUE, un TOTAL de grandeur (somme.gd), puis le prix -- un champ
	# derive PAR COLON, recalcule a neuf.
	for colon in colons:
		var perceptions: Array = Perception.percevoir(colon, monde, catalogue_canaux)
		infos[colon.id]["perceptions"] = perceptions
		infos[colon.id]["offres"] = offres_percues(perceptions, config)
		infos[colon.id]["prix"] = poser_prix(colon, infos[colon.id].offres, demande, config)

	# La forge produit : transfert DESTRUCTIF minerai -> masse du tas de l'atelier.
	for colon in colons:
		infos[colon.id]["production"] = forger(
			colon, forge, tas_production, bool(en_forge[colon.id]), delta, config)

	# (5) Les deux marques, puis les deux deformations -- poser avant avancer.
	for colon in colons:
		var marques: Dictionary = avancer_marques(
			colon, bool(en_forge[colon.id]), float(horloges.get(colon.id, 0.0)), delta,
			config, catalogue_epigenetique)
		horloges_apres[colon.id] = float(marques.horloge)
		infos[colon.id]["poses"] = int(marques.poses)
	for colon in colons:
		infos[colon.id]["magnitudes"] = poser_deformations(
			colon, forge, delta, config, catalogue_deformations)
		Deformation.avancer(colon, delta, catalogue_deformations)

	# Les lectures, EN DERNIER : elles ne calculent aucun etat, elles le racontent.
	for colon in colons:
		var perceptions: Array = infos[colon.id].perceptions
		infos[colon.id]["competence_modulateur"] = modulateur_competence(colon, config)
		infos[colon.id]["competence_effective"] = competence_effective(colon, config)
		infos[colon.id]["plancher"] = plancher_competence(colon, config)
		infos[colon.id]["habitude_modulateur"] = modulateur_habitude(colon, config)
		infos[colon.id]["habitude_clampee"] = habitude_clampee(colon, config)
		infos[colon.id]["vitesse_forge"] = vitesse_forge_effective(colon, config)
		infos[colon.id]["biais_competence"] = Deformation.biais(
			colon, String(config.source_deformation_competence),
			String(config.cible_deformation), catalogue_deformations)
		infos[colon.id]["biais_habitude"] = Deformation.biais(
			colon, String(config.source_deformation_habitude),
			String(config.cible_deformation), catalogue_deformations)
		infos[colon.id]["saillance_forge"] = saillance_de(
			perceptions, colon, String(forge.id), profils_saillance, catalogue_deformations)
		infos[colon.id]["saillance_nue_forge"] = saillance_de(
			perceptions, lecteur_sans_deformation(), String(forge.id),
			profils_saillance, catalogue_deformations)

	return {"infos": infos, "horloges": horloges_apres, "demande": demande}

# ---- Construction de la scene ----

# Le colon ne porte NI composition NI materiau (voir en-tete). Un seul canal de
# perception, dont la portee est INDIVIDUELLE (c'est elle qui fait diverger les
# prix) ; un seul canal de reserve, dont 'cout_base' est le metabolisme, pose ici
# une fois pour toutes et jamais reecrit -- 'surcout_action' part a 0.0 et n'est
# ecrit que par poser_surcout_action.
# marques_epigenetiques, deformation_sources et deformation_etat sont
# STRUCTURELLES pour epigenetique.gd/deformation.gd (leur absence est une alarme,
# jamais « aucune marque ») : posees ici, comme data/types.json:dynamique le fait
# pour les types reels. deformation_sources est DUPLIQUE depuis la config
# (duplicate(true)) -- jamais partage avec le Dictionary du disque, meme
# precaution d'aliasing que banc_bonheur.gd:construire_colons.
static func construire_colon(decl: Dictionary, config: Dictionary) -> Dictionary:
	var pos: Array = decl.position
	var reserves: Dictionary = {}
	reserves[String(config.nom_reserve_energie)] = {
		"reserve": float(decl.energie_initiale),
		"cout_base": float(config.metabolisme_base_par_s),
		"surcout_action": 0.0,
	}
	var canaux_config: Dictionary = {}
	for nom_canal in config.get("canaux", []):
		canaux_config[String(nom_canal)] = {"portee": float(decl.portee_vue), "angle": 360.0}
	var marques: Dictionary = {}
	var depart: float = float(decl.get("modulateur_competence_depart", 0.0))
	if depart > 0.0:
		marques[String(config.nom_marque_competence)] = {"modulateur": depart, "age_marque": 0.0}
	var proprietes: Dictionary = {
		"reserves": reserves,
		"canaux": config.canaux.duplicate(true),
		"canaux_config": canaux_config,
		"deformation_sources": config.deformation_sources.duplicate(true),
		"deformation_etat": {},
		"marques_epigenetiques": marques,
	}
	# LE PLANCHER EST UNE DONNEE PAR COLON (voir en-tete) : ce qu'un metier a
	# laisse a celui qui l'a exerce, jamais ce que tout le monde porte.
	proprietes[String(config.nom_plancher_competence)] = float(decl.get("plancher_competence", 0.0))
	return {
		"id": String(decl.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": proprietes,
	}

# La forge porte ses proprietes TELLES QUE DECLAREES en donnee (duplique, jamais
# partage) : la propriete de cible de deformation, sa reference de profil de
# saillance, et sa reserve de minerai. Ce fichier ne nomme aucune des trois.
static func construire_forge(config: Dictionary) -> Dictionary:
	var decl: Dictionary = config.forge
	var pos: Array = decl.position
	return {
		"id": String(decl.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": decl.proprietes.duplicate(true),
		"type_banc": "forge",
	}

# Un tas de marchandise : une propriete PLATE qui dit de quelle marchandise il
# est (le nom vient du catalogue de marchandises, jamais de ce fichier) et un
# canal de reserve a cout NUL -- depense.gd n'est jamais appele sur les tas, ils
# ne perdent de la masse que par transfert.
static func construire_tas(decl: Dictionary, config: Dictionary) -> Dictionary:
	var pos: Array = decl.position
	var marchandise: Dictionary = marchandise_par_nom(config, String(decl.marchandise))
	var reserves: Dictionary = {}
	reserves[String(config.nom_reserve_masse)] = {
		"reserve": float(decl.masse), "cout_base": 0.0, "surcout_action": 0.0,
	}
	var proprietes: Dictionary = {"reserves": reserves}
	proprietes[String(marchandise.get("propriete", ""))] = true
	return {
		"id": String(decl.id),
		"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		"proprietes": proprietes,
		"type_banc": "tas",
	}

# Entree absente du catalogue de marchandises : push_error et Dictionary vide --
# jamais une marchandise inventee a la volee (meme contrat qu'une reference de
# catalogue ailleurs dans le depot).
static func marchandise_par_nom(config: Dictionary, nom: String) -> Dictionary:
	for marchandise in config.get("marchandises", []):
		if String(marchandise.nom) == nom:
			return marchandise
	push_error("banc_marche_competence : marchandise '%s' absente du catalogue de banc" % nom)
	return {}

# ---- LIGNE 9 : le prix ----

# Les choses PERCUES qui portent la propriete d'une marchandise. Filtre de
# CABLAGE : somme.gd ne connait aucune propriete de domaine, il recoit une liste
# deja construite (meme contrat que comptage.gd). Une chose qui ne porte pas la
# propriete, ou la porte a false, n'est pas du stock.
static func choses_percues_portant(perceptions: Array, propriete: String) -> Array:
	var choses: Array = []
	for entree in perceptions:
		if entree.chose.get("proprietes", {}).get(propriete, false):
			choses.append(entree.chose)
	return choses

# L'OFFRE, marchandise par marchandise, TELLE QUE CE COLON LA VOIT. C'est le seul
# endroit d'ou vient la divergence des prix : deux colons a portees differentes
# recoivent deux perceptions differentes, donc deux totaux differents.
static func offres_percues(perceptions: Array, config: Dictionary) -> Dictionary:
	var offres: Dictionary = {}
	for marchandise in config.get("marchandises", []):
		offres[String(marchandise.nom)] = Somme.reserves(
			choses_percues_portant(perceptions, String(marchandise.propriete)),
			String(config.nom_reserve_masse))
	return offres

# LECTURE PURE : n'ecrit rien, ne mute rien -- poser_prix est le seul ecrivain
# (patron banc_bonheur.gd:calculer_bonheur/poser_bonheur). Le max(0.1, offre) est
# une garde de DIVISION, pas une regle de jeu : une offre nulle ne donne pas un
# prix infini, elle donne le prix le plus haut que la formule sait produire.
static func calculer_prix(offre: float, demande: int, marchandise: Dictionary) -> float:
	var denominateur: float = max(0.1, offre)
	return float(marchandise.poids_offre_demande) * pow(
		float(demande) / denominateur, float(marchandise.elasticite))

# UNIQUE ECRIVAIN des champs de prix. RECALCULE A NEUF chaque tick et ECRIT
# PAR-DESSUS la valeur du tick precedent, JAMAIS un '+=' : c'est la seule chose
# qui empeche un champ derive de DERIVER (voir en-tete). MUTE le colon en place ;
# rend les prix poses pour que l'affichage relise sans jamais rien recalculer.
static func poser_prix(colon: Dictionary, offres: Dictionary, demande: int, config: Dictionary) -> Dictionary:
	var prix: Dictionary = {}
	for marchandise in config.get("marchandises", []):
		var nom := String(marchandise.nom)
		var valeur: float = calculer_prix(float(offres.get(nom, 0.0)), demande, marchandise)
		colon.proprietes[String(marchandise.nom_prix)] = valeur
		prix[nom] = valeur
	return prix

# Le miroir PLAT que comptage.gd compare pour rendre la demande. Ecrit APRES
# Depense.avancer (voir avancer_tick). Borne a 0.0 par le bas : une reserve
# au-dessus de sa capacite ne donne pas un « manque negatif ».
static func poser_manque_energie(colon: Dictionary, config: Dictionary) -> float:
	var canal: Dictionary = colon.proprietes.get("reserves", {}).get(
		String(config.nom_reserve_energie), {})
	var manque: float = max(0.0, float(config.capacite_energie) - float(canal.get("reserve", 0.0)))
	colon.proprietes[String(config.nom_manque_energie)] = manque
	return manque

# ---- LIGNES 10 et 12 : competence, plancher, specialisation ----

static func a_portee_forge(colon: Dictionary, forge: Dictionary, config: Dictionary) -> bool:
	return Portee.en_portee(colon.position, forge.position, float(config.portee_forge))

# Le modulateur BRUT de la marque. Marque absente -- jamais posee, ou RETIREE par
# epigenetique.gd sous son plancher_suppression -- : 0.0, point neutre legitime,
# jamais une alarme.
static func modulateur_competence(colon: Dictionary, config: Dictionary) -> float:
	var marques: Dictionary = colon.proprietes.get("marques_epigenetiques", {})
	return float(marques.get(String(config.nom_marque_competence), {}).get("modulateur", 0.0))

static func plancher_competence(colon: Dictionary, config: Dictionary) -> float:
	return float(colon.proprietes.get(String(config.nom_plancher_competence), 0.0))

# LE CLAMP A LA LECTURE (route (a) de l'audit, ligne 12). plancher_suppression du
# catalogue SUPPRIME l'entree, il ne borne aucune valeur : le plancher reel est
# ici, et il est PAR COLON. Un veteran rouille garde son metier ; un novice, dont
# le plancher vaut 0.0, ne gagne rien a ce max. Le plafond du meme clamp fait
# symetrie avec habitude_clampee -- il ne fait pas double emploi avec le gate de
# pose (_poser_une_marque) : lui seul protege des valeurs posees a la main, que
# le gate ne voit jamais.
static func competence_effective(colon: Dictionary, config: Dictionary) -> float:
	return clamp(
		max(plancher_competence(colon, config), modulateur_competence(colon, config)),
		0.0, float(config.plafond_competence))

# ---- LIGNE 11 : habitude, rythme de travail ----

static func modulateur_habitude(colon: Dictionary, config: Dictionary) -> float:
	var marques: Dictionary = colon.proprietes.get("marques_epigenetiques", {})
	return float(marques.get(String(config.nom_marque_habitude), {}).get("modulateur", 0.0))

# CLAMP A LA LECTURE, jamais un plafond dans le mecanisme : epigenetique.gd n'a
# AUCUNE borne haute (voir en-tete). Sans lui, vitesse_forge_effective croitrait
# sans fin tant que le colon forge.
static func habitude_clampee(colon: Dictionary, config: Dictionary) -> float:
	return clamp(modulateur_habitude(colon, config), 0.0, float(config.plafond_habitude))

# LE contournement d'expression.gd (voir en-tete) : la composition est faite ICI,
# dans le cablage, jamais par exprimer()/appliquer().
static func vitesse_forge_effective(colon: Dictionary, config: Dictionary) -> float:
	return float(config.vitesse_forge_base) * (1.0 + habitude_clampee(colon, config))

# Les DEUX marques posees d'un meme geste, par INTERVALLE en secondes de
# simulation (voir en-tete, CADENCE DE POSE), et decrues INCONDITIONNELLEMENT --
# c'est la decroissance qui fait perdre le rythme et rouiller la competence,
# jamais un cas particulier. Rend l'horloge suivante et le nombre de poses faites.
static func avancer_marques(
	colon: Dictionary,
	en_forge: bool,
	horloge: float,
	delta: float,
	config: Dictionary,
	catalogue_epigenetique: Dictionary,
) -> Dictionary:
	var suivant: Dictionary = avancer_horloge(
		horloge, delta, float(config.intervalle_pose_marque_s), en_forge)
	var poses := 0
	if bool(suivant.poser):
		if _poser_une_marque(colon, String(config.nom_marque_competence),
				modulateur_competence(colon, config), float(config.plafond_competence),
				catalogue_epigenetique):
			poses += 1
		if _poser_une_marque(colon, String(config.nom_marque_habitude),
				modulateur_habitude(colon, config), float(config.plafond_habitude),
				catalogue_epigenetique):
			poses += 1
	Epigenetique.avancer(colon, delta, catalogue_epigenetique)
	return {"horloge": float(suivant.horloge), "poses": poses}

# LE PLAFOND EST SUR LA POSE, pas seulement sur la lecture -- et ce n'est pas un
# confort, c'est une CONDITION D'OBSERVABILITE trouvee en lancant la scene, pas
# au test. epigenetique.gd n'a aucune borne haute : sans ce gate, apres 45 s de
# forge continue les deux modulateurs valaient 7.6 pour des plafonds de lecture
# de 1.0 et 0.5. Rien n'etait faux -- le clamp a la lecture tenait, la vitesse et
# la saillance restaient bornees -- mais DEUX choses devenaient inobservables :
# la barre de competence saturait au bout de sept secondes, et surtout la
# decroissance qui fait tout le sujet des lignes 11 et 12 mettait 150 s au lieu
# de 20 (le modulateur doit redescendre de 7.6, pas de 1.0). Meme geste exact que
# les plafonds de biais de _poser_une_deformation : le cablage cesse de poser des
# que le plafond est atteint. LE CLAMP A LA LECTURE RESTE, il ne fait pas double
# emploi : lui seul protege des valeurs posees a la main (test, sauvegarde,
# chantier futur) que ce gate ne voit jamais.
static func _poser_une_marque(
	colon: Dictionary,
	nom_marque: String,
	modulateur: float,
	plafond: float,
	catalogue_epigenetique: Dictionary,
) -> bool:
	if modulateur >= plafond:
		return false
	Epigenetique.poser(colon, nom_marque, catalogue_epigenetique)
	return true

# Accumulateur d'intervalle -- TROISIEME copie de cet idiome dans le depot
# (banc_graisse_accoutumance.gd, banc_psycho_social.gd), signalee plutot que
# masquee : elle n'a jamais franchi le seuil d'extraction du depot, et un seul
# geste par chantier. Exposition coupee : l'horloge est REMISE A ZERO plutot que
# gelee -- un residu garde en memoire ferait poser une marque immediatement a la
# reprise.
static func avancer_horloge(horloge: float, delta: float, intervalle: float, actif: bool) -> Dictionary:
	if not actif:
		return {"horloge": 0.0, "poser": false}
	if intervalle <= 0.0:
		return {"horloge": 0.0, "poser": true}
	var suivant: float = horloge + delta
	if suivant < intervalle:
		return {"horloge": suivant, "poser": false}
	return {"horloge": suivant - intervalle, "poser": true}

# LES DEUX DEFORMATIONS, gatees par la PORTEE (voir en-tete) : c'est en etant a
# l'atelier que le metier deforme le regard, pas de l'autre bout de la carte.
# Passent par poser(), jamais par une ecriture directe dans deformation_etat :
# poser() refuse (push_error) toute source non declaree dans deformation_sources,
# garde qu'une ecriture a la main contournerait.
static func poser_deformations(
	colon: Dictionary,
	forge: Dictionary,
	delta: float,
	config: Dictionary,
	catalogue_deformations: Dictionary,
) -> Dictionary:
	var magnitudes: Dictionary = {"competence": 0.0, "habitude": 0.0}
	if not a_portee_forge(colon, forge, config):
		return magnitudes
	var cible := String(config.cible_deformation)
	magnitudes["competence"] = _poser_une_deformation(
		colon, String(config.source_deformation_competence), cible,
		float(config.gain_deformation_competence_par_s) * competence_effective(colon, config) * delta,
		float(config.plafond_biais_competence), catalogue_deformations)
	magnitudes["habitude"] = _poser_une_deformation(
		colon, String(config.source_deformation_habitude), cible,
		float(config.gain_deformation_habitude_par_s) * habitude_clampee(colon, config) * delta,
		float(config.plafond_biais_habitude), catalogue_deformations)
	return magnitudes

# MAGNITUDE NULLE : rien n'est pose du tout, et ce n'est pas une optimisation --
# c'est ce qui garde le deformation_etat d'un novice VIDE. Une entree posee a
# 0.0 ferait quand meme exister le couple [source][cible], et « le novice n'a
# aucune deformation » deviendrait faux tout en restant sans effet visible.
# MULTIPLIEE PAR delta cote appelant : poser() n'a AUCUN parametre de temps.
# PLAFOND AU CABLAGE : deformation.gd n'a aucune borne haute (voir en-tete).
static func _poser_une_deformation(
	colon: Dictionary,
	source: String,
	cible: String,
	magnitude: float,
	plafond: float,
	catalogue_deformations: Dictionary,
) -> float:
	if magnitude <= 0.0:
		return 0.0
	if Deformation.biais(colon, source, cible, catalogue_deformations) >= plafond:
		return 0.0
	Deformation.poser(colon, source, cible, magnitude)
	return magnitude

# ---- Forge : surcout et production ----

# UNIQUE ECRIVAIN de canal.surcout_action -- voir en-tete, « UN SEUL ECRIVAIN ».
# MUTE le colon en place ; rend la DECOMPOSITION pour que l'affichage la relise
# sans jamais rien recalculer. Canal absent (config incoherente) : push_error,
# rien n'est ecrit, total nul -- jamais un canal invente a la volee.
static func poser_surcout_action(colon: Dictionary, en_forge: bool, config: Dictionary) -> Dictionary:
	var cout_forge: float = float(config.cout_forge_par_s) if en_forge else 0.0
	var nom := String(config.nom_reserve_energie)
	var reserves: Dictionary = colon.proprietes.get("reserves", {})
	if not reserves.has(nom):
		push_error("banc_marche_competence : canal de reserve '%s' absent du colon '%s', surcout non pose"
			% [nom, colon.get("id", "?")])
		return {"forge": cout_forge, "total": 0.0}
	reserves[nom]["surcout_action"] = cout_forge
	return {"forge": cout_forge, "total": cout_forge}

# Transfert DESTRUCTIF minerai -> masse (consommer.gd, mecanisme du coeur appele
# tel quel) : ce qui sort de la forge entre EXACTEMENT dans le tas, rien n'est
# cree. Le taux est vitesse_forge_effective, donc l'habitude accelere reellement
# la production -- ce n'est pas un nombre affiche pour rien. Tas de production
# retire de la scene : la forge tourne a vide, aucune matiere n'apparait.
static func forger(
	colon: Dictionary,
	forge: Dictionary,
	tas_production,
	en_forge: bool,
	delta: float,
	config: Dictionary,
) -> float:
	if not en_forge or tas_production == null:
		return 0.0
	return float(Consommer.transferer(
		forge, tas_production,
		String(config.nom_reserve_minerai), String(config.nom_reserve_masse),
		vitesse_forge_effective(colon, config), delta).quantite)

# ---- Lecture de la saillance (couche 2) ----

# La saillance d'UNE chose precise, telle que 'lecteur' la voit. Passe par
# Proximite.evaluer -- jamais une reimplementation de son arithmetique (poids x
# facteur de distance x avancement, puis composition multiplicative des biais) :
# une copie locale deriverait du mecanisme sans que rien ne rougisse.
static func saillance_de(
	perceptions: Array,
	lecteur: Dictionary,
	id_chose: String,
	profils_saillance: Dictionary,
	catalogue_deformations: Dictionary,
) -> float:
	for entree in Proximite.evaluer(perceptions, lecteur, profils_saillance, catalogue_deformations):
		if String(entree.chose.get("id", "")) == id_chose:
			return float(entree.saillance)
	return 0.0

# Le TEMOIN : un lecteur reduit a un deformation_etat vide, pour obtenir la
# saillance NUE de la meme chose, aux memes distances, par le MEME mecanisme.
# proximite.gd ne lit rien d'autre du colon (deformation_etat y est FACULTATIVE) :
# c'est la seule facon de mesurer l'effet de la deformation sans recalculer la
# saillance a la main.
static func lecteur_sans_deformation() -> Dictionary:
	return {"proprietes": {"deformation_etat": {}}}

# ---- Bascules (pures) ----

# Toggle CYCLIQUE sur nb_retirables + 1 etats : le dernier est AUCUN RETRAIT.
# Meme forme exacte que banc_bonheur.gd:source_suivante.
static func tas_suivant(selection: int, nb_retirables: int) -> int:
	return (selection + 1) % (nb_retirables + 1)

# ---- Textes (purs -- aucun nombre n'y est recalcule) ----

static func texte_prix(infos: Dictionary, config: Dictionary) -> String:
	var morceaux: Array = []
	for marchandise in config.get("marchandises", []):
		var nom := String(marchandise.nom)
		morceaux.append("%s %.2f (offre vue %.1f)" % [
			nom,
			float(infos.get("prix", {}).get(nom, 0.0)),
			float(infos.get("offres", {}).get(nom, 0.0)),
		])
	return "   ".join(morceaux)

static func texte_label_colon(colon: Dictionary, infos: Dictionary, config: Dictionary) -> String:
	return "%s%s\nprix : %s\ncompetence modulateur %.3f -> effective %.3f (plancher %.2f)\nhabitude modulateur %.3f -> clamp %.3f -> vitesse forge %.2f/s\nbiais forge %.2f + %.2f -- saillance %.3f (nue %.3f)\nenergie %.1f / %.1f" % [
		String(colon.id),
		"  [FORGE]" if bool(infos.get("en_forge", false)) else ("  [a portee]" if bool(infos.get("a_portee", false)) else "  [hors portee]"),
		texte_prix(infos, config),
		float(infos.get("competence_modulateur", 0.0)),
		float(infos.get("competence_effective", 0.0)),
		float(infos.get("plancher", 0.0)),
		float(infos.get("habitude_modulateur", 0.0)),
		float(infos.get("habitude_clampee", 0.0)),
		float(infos.get("vitesse_forge", 0.0)),
		float(infos.get("biais_competence", 0.0)),
		float(infos.get("biais_habitude", 0.0)),
		float(infos.get("saillance_forge", 0.0)),
		float(infos.get("saillance_nue_forge", 0.0)),
		float(colon.proprietes.get("reserves", {}).get(String(config.nom_reserve_energie), {}).get("reserve", 0.0)),
		float(config.capacite_energie),
	]

static func texte_compteur(temps: float, demande: int, retire: String, minerai: float) -> String:
	return "t=%.1f s -- demande (colons affames) %d -- tas retire : %s -- minerai en forge %.1f" % [
		temps, demande, "aucun" if retire == "" else retire, minerai,
	]

static func texte_aide() -> String:
	return "clic gauche : retire un tas a tour de role, puis aucun -- touches 1/2/3 : le colon correspondant forge / s'arrete"

static func ligne_pose(config: Dictionary) -> String:
	var morceaux: Array = []
	for decl in config.get("colons", []):
		morceaux.append("%s { competence %.2f, plancher %.2f, portee de vue %.0f, forge %s }" % [
			String(decl.id),
			float(decl.get("modulateur_competence_depart", 0.0)),
			float(decl.get("plancher_competence", 0.0)),
			float(decl.portee_vue),
			"ON" if bool(decl.get("forge_au_depart", false)) else "OFF",
		])
	return "t=0.0 %d colons poses -- %s\nplafonds de cablage : habitude %.2f, biais competence %.2f, biais habitude %.2f -- pose des marques toutes les %.2f s" % [
		config.get("colons", []).size(),
		" | ".join(morceaux),
		float(config.plafond_habitude),
		float(config.plafond_biais_competence),
		float(config.plafond_biais_habitude),
		float(config.intervalle_pose_marque_s),
	]

static func ligne_retrait(temps: float, retire: String) -> String:
	return "t=%.1f TAS RETIRE : %s" % [temps, "aucun" if retire == "" else retire]

static func ligne_bascule_forge(temps: float, id: String, actif: bool) -> String:
	return "t=%.1f %s : forge %s" % [temps, id, "ON" if actif else "OFF"]

# L'EVENEMENT de la ligne 12 : epigenetique.gd a retire l'entree sous son
# plancher_suppression. Ce que le colon garde ensuite est le plancher du cablage,
# et rien d'autre.
static func ligne_marque_retiree(temps: float, id: String, colon: Dictionary, config: Dictionary) -> String:
	return "t=%.1f %s MARQUE '%s' RETIREE par epigenetique.gd -- competence effective retombee sur le plancher %.2f" % [
		temps, id, String(config.nom_marque_competence), competence_effective(colon, config),
	]

static func ligne_trace(temps: float, colon: Dictionary, infos: Dictionary, config: Dictionary) -> String:
	return "t=%.1f %s | %s | competence %.3f -> %.3f | habitude %.3f -> %.3f | vitesse forge %.2f | saillance forge %.3f (nue %.3f) | %s" % [
		temps,
		String(colon.id),
		"forge" if bool(infos.get("en_forge", false)) else "arret",
		float(infos.get("competence_modulateur", 0.0)),
		float(infos.get("competence_effective", 0.0)),
		float(infos.get("habitude_modulateur", 0.0)),
		float(infos.get("habitude_clampee", 0.0)),
		float(infos.get("vitesse_forge", 0.0)),
		float(infos.get("saillance_forge", 0.0)),
		float(infos.get("saillance_nue_forge", 0.0)),
		texte_prix(infos, config),
	]

# ---- Rendu (impur, Node) -- aucune decision, seulement des couleurs, des
# rectangles et des longueurs de barre.

func _couleur(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))

func _construire_rendu() -> void:
	for colon in _colons:
		var label := _creer_label(int(_config.taille_police_label))
		label.position = Vector2(colon.position.x, colon.position.y) + Vector2(
			float(_config.taille_colon), float(_config.taille_colon))
		add_child(label)
		_labels[colon.id] = label

	var couche := CanvasLayer.new()
	add_child(couche)
	_label_compteur = _creer_label(int(_config.taille_police_compteur))
	_label_compteur.position = Vector2(10.0, 10.0)
	couche.add_child(_label_compteur)
	_label_aide = _creer_label(int(_config.taille_police_aide))
	_label_aide.position = Vector2(10.0, 34.0)
	_label_aide.text = texte_aide()
	couche.add_child(_label_aide)

	_poser_camera()

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur))),
		_couleur(_config.couleur_fond))

	# Le rayon REEL de la portee de forge, jamais un disque decoratif : c'est lui
	# qui decide qui peut forger et qui se deforme.
	var centre_forge := Vector2(_forge.position.x, _forge.position.y)
	draw_circle(centre_forge, float(_config.portee_forge), _couleur(_config.couleur_portee_forge))

	# Les portees de VUE, dessinees en cercle fin : c'est la seule chose qui
	# separe les trois estimations de prix, elle doit se voir.
	for colon in _colons:
		draw_arc(Vector2(colon.position.x, colon.position.y), _portee_vue(colon), 0.0, TAU, 96,
			_couleur(_config.couleur_portee_vue), 2.0)

	var comptoir: Dictionary = _config.comptoir
	var pc: Array = comptoir.position
	draw_rect(Rect2(
		Vector2(float(pc[0]) - float(comptoir.largeur) / 2.0, float(pc[1]) - float(comptoir.hauteur) / 2.0),
		Vector2(float(comptoir.largeur), float(comptoir.hauteur))), _couleur(comptoir.couleur))

	var taille_forge: float = float(_config.forge.taille)
	draw_rect(Rect2(centre_forge - Vector2(taille_forge, taille_forge) / 2.0,
		Vector2(taille_forge, taille_forge)), _couleur(_config.forge.couleur))

	# Chaque tas a la taille de sa masse REELLE : forger fait grossir celui de
	# l'atelier sous les yeux, sans un chiffre a lire.
	for id in _tas:
		var tas: Dictionary = _tas[id]
		var masse: float = float(tas.proprietes.reserves[String(_config.nom_reserve_masse)].reserve)
		var cote: float = float(_config.taille_tas_min) + masse * float(_config.taille_tas_par_masse)
		var actif: bool = bool(_tas_actifs.get(id, false))
		var couleur := _couleur(_config.couleur_tas_retire)
		if actif:
			couleur = _couleur(_marchandise_du_tas(tas).get("couleur", [1.0, 1.0, 1.0]))
		draw_rect(Rect2(Vector2(tas.position.x, tas.position.y) - Vector2(cote, cote) / 2.0,
			Vector2(cote, cote)), couleur)

	for colon in _colons:
		var centre := Vector2(colon.position.x, colon.position.y)
		var cote: float = float(_config.taille_colon)
		draw_rect(Rect2(centre - Vector2(cote, cote) / 2.0, Vector2(cote, cote)),
			_couleur(_couleur_declaree(String(colon.id))))
		_dessiner_barres(colon, centre)

# Deux barres par colon, au-dessus de lui. La barre de competence porte le TRAIT
# DU PLANCHER : sans lui, « le modulateur passe sous le plancher » ne serait
# qu'un nombre dans la console. Le trait vaut 0.0 pour un colon sans plancher --
# il est alors colle au bord gauche, ce qui dit exactement la bonne chose.
func _dessiner_barres(colon: Dictionary, centre: Vector2) -> void:
	var infos: Dictionary = _infos.get(colon.id, {})
	var largeur: float = float(_config.largeur_barre)
	var hauteur: float = float(_config.hauteur_barre)
	var espacement: float = float(_config.espacement_barre)
	var x: float = centre.x - largeur / 2.0
	var y: float = centre.y - float(_config.taille_colon) / 2.0 - float(_config.marge_bloc) - 2.0 * espacement

	# La barre de competence est graduee sur le PLAFOND DE CABLAGE lui-meme,
	# jamais sur un maximum d'affichage recopie a cote : un seul nombre, jamais
	# deux a garder d'accord.
	var max_competence: float = float(_config.plafond_competence)
	_barre(Vector2(x, y), largeur, hauteur, _couleur(_config.couleur_fond_barre), 1.0)
	_barre(Vector2(x, y), largeur, hauteur, _couleur(_config.couleur_barre_competence),
		clamp(float(infos.get("competence_modulateur", 0.0)) / max_competence, 0.0, 1.0) if max_competence > 0.0 else 0.0)
	var ratio_plancher: float = clamp(float(infos.get("plancher", 0.0)) / max_competence, 0.0, 1.0) if max_competence > 0.0 else 0.0
	draw_line(Vector2(x + largeur * ratio_plancher, y - 2.0),
		Vector2(x + largeur * ratio_plancher, y + hauteur + 2.0),
		_couleur(_config.couleur_plancher), 2.0)

	var max_habitude: float = float(_config.plafond_habitude)
	_barre(Vector2(x, y + espacement), largeur, hauteur, _couleur(_config.couleur_fond_barre), 1.0)
	_barre(Vector2(x, y + espacement), largeur, hauteur, _couleur(_config.couleur_barre_habitude),
		clamp(float(infos.get("habitude_modulateur", 0.0)) / max_habitude, 0.0, 1.0) if max_habitude > 0.0 else 0.0)

func _barre(origine: Vector2, largeur: float, hauteur: float, couleur: Color, ratio: float) -> void:
	draw_rect(Rect2(origine, Vector2(largeur * ratio, hauteur)), couleur)

# La portee du PREMIER canal declare -- ce banc n'en a qu'un, et son cercle a
# l'ecran doit etre celui que perception.gd utilise reellement, jamais un nombre
# recopie a cote.
func _portee_vue(colon: Dictionary) -> float:
	var canaux_config: Dictionary = colon.proprietes.get("canaux_config", {})
	for nom_canal in canaux_config:
		return float(canaux_config[nom_canal].get("portee", 0.0))
	return 0.0

func _couleur_declaree(id: String) -> Array:
	for decl in _config.get("colons", []):
		if String(decl.id) == id:
			return decl.get("couleur", [1.0, 1.0, 1.0])
	return [1.0, 1.0, 1.0]

func _marchandise_du_tas(tas: Dictionary) -> Dictionary:
	for marchandise in _config.get("marchandises", []):
		if tas.proprietes.get(String(marchandise.propriete), false):
			return marchandise
	return {}

func _rafraichir() -> void:
	for colon in _colons:
		_labels[colon.id].text = texte_label_colon(colon, _infos.get(colon.id, {}), _config)
	_label_compteur.text = texte_compteur(_temps, _demande, _nom_tas_retire(),
		float(_forge.proprietes.reserves[String(_config.nom_reserve_minerai)].reserve))

func _poser_camera() -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur)) / 2.0
	camera.zoom = Vector2(0.95, 0.95)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
