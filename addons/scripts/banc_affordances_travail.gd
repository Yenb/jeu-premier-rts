extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_affordances_travail.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « travail + coupe + resultat » : lignes 1, 2, 3, 4, 5, 6 et
# 10 du tableau Affordances (audit_affordances_prealable.md), toutes au verdict
# CABLABLE sauf la 10, PARTIELLEMENT COUVERTE -- tenu, et la 10 l'est par la
# voie que l'audit designe (le cablage appelle Produit.transformer lui-meme,
# hors extinction.gd).
#
# AUCUN MECANISME DU COEUR TOUCHE NI CREE. Ce fichier COMPOSE onze mecanismes
# deja fermes, TOUS INCHANGES : extinction.gd, depense.gd, flux.gd,
# seuil_etat.gd, couplage.gd, etat_duree.gd, etat_effectif.gd, bifurcation.gd,
# produit.gd, objet.gd, somme.gd (+ perception.gd/dominance.gd/portee.gd en
# lecture pure, + banc_commun.gd pour le deplacement). Il n'ecrit AUCUNE
# mecanique : tout ce qu'il ajoute est du cablage, des plafonds, des miroirs
# plats et des compositions de valeur effective.
#
# ---------------------------------------------------------------------------
# CE QU'IL DOIT MONTRER -- une ligne de l'audit par point
# ---------------------------------------------------------------------------
# 1. CE QUI COUPE PEUT COUPER. Trois colons, trois outils : fer (ratio de coupe
#    0.90), pierre (0.50), bois (0.20). Sous config.seuil_tranchant (0.30), le
#    porteur d'outil en bois ne coupe PAS -- il n'entre meme pas dans la liste
#    d'agents passee a extinction.gd, sa presence a portee ne fait donc rien
#    avancer du tout. Le ratio lui-meme est degat_coupe(), RECOPIE de
#    scripts/banc_coupe.gd (deux bancs jetables ne se referencent jamais entre
#    eux -- precedent explicite banc_erosion.gd/banc_fatigue_circadien.gd).
#    C'est un REFUS, pas un rendement nul : voir POURQUOI PAS reaction.gd.
# 2. UN TRAVAIL, PAS UN TEMPS. La progression vit sur la CIBLE
#    (arbre.proprietes.travail_restant), consommee par extinction.gd a la somme
#    des `rythme` des agents a portee. Zero ligne a ecrire pour l'obtenir.
# 3. DORMIR JUSQU'A ETRE REPOSE. couplage.gd avec sens_satisfaction
#    "sur_seuil" (data/engagements.json:dormir_reserve, patron animal_reserve,
#    jeton {canal}) -- flux.gd recharge la reserve depuis le lit, et
#    l'engagement se relache TOUT SEUL quand elle repasse au-dessus de
#    seuil_satisfait. seuil_etat.gd n'est PAS l'outil de l'arret : il ne compare
#    que vers le HAUT (son en-tete), il sert ici a l'ENTREE (poser "epuise" sur
#    le miroir plat inverse), jamais a la sortie.
# 4. LE CHANTIER SURVIT A L'OUVRIER. Rien a cabler : extinction.gd resomme les
#    rythmes de TOUS les agents a portee A CHAQUE TICK, il ne memorise aucune
#    identite. Un colon qui part cesse de contribuer, un autre qui arrive
#    contribue immediatement sur le travail_restant laisse.
# 5. UN TRAVAIL INTERROMPU LAISSE UNE BLESSURE. Chantier entame puis abandonne
#    -> le cablage pose "entaille" (etat_duree.gd, REPOSE chaque tick tant que
#    l'abandon dure) ; cet etat GATE le cout_base d'une reserve
#    "fraicheur_entaille" (depense.gd) dont le cout EFFECTIF est compose par le
#    cablage avec l'humidite ; a zero, travail_restant est remis a
#    travail_initial -- l'arbre a cicatrise, tout le travail est perdu. C'est le
#    COUT DE L'ABANDON de la ligne 6, et il n'a demande aucun mecanisme de plus.
# 6. LE CHIRURGIEN FATIGUE N'OUVRE PAS. Avant d'entamer, le cablage compare
#    temps_necessaire * marge_securite a temps_restant et RETIRE l'entree de
#    `resultats` AVANT dominance.gd -- geste dont le seul precedent du depot est
#    banc_economie.gd. Le colon voit l'arbre, et n'y va pas.
# 10. RATER PRODUIT AUTRE CHOSE. bifurcation.gd tranche entre reussite /
#    eclats / debris sur un biais compose PAR COLON (adresse, fatigue, qualite
#    d'outil), puis le cablage appelle produit.gd:transformer sur la SEULE issue
#    gagnante, fabrique un vrai objet et l'ajoute au Monde.
#
# ---------------------------------------------------------------------------
# QUATRE VOIES ECARTEES, ET POURQUOI -- resultats negatifs, interdits a refaire
# ---------------------------------------------------------------------------
# (a) POURQUOI PAS reaction.gd POUR LE GATE DE COUPE (ligne 1). Sa forme est
#     pourtant exactement celle qu'il faut (deux objets a portee, un score
#     compose des deux, un seuil, une transformation) et c'est la SEULE du coeur
#     -- mais deux verrous l'excluent : la paire y est appariee par MATERIAU
#     (_trouver_reaction sur composition[0], donc trois outils x trois cibles =
#     neuf entrees de catalogue), et le nom de la propriete scoree est FIGE a
#     "reactivite" dans _score_reaction, defendu par son propre en-tete
#     (« STRUCTURELLE au mecanisme lui-meme »). Le rendre parametrable
#     TOUCHERAIT LE COEUR. La voie banc_coupe.gd -- deux proprietes plates lues
#     par le cablage, gate ARITHMETIQUE -- est la bonne, et elle ne coute rien.
# (b) POURQUOI PAS seuil_etat.gd POUR L'ARRET DU SOMMEIL (ligne 3). Il ne
#     compare que STRICTEMENT AU-DESSUS (`valeur > seuil`, son en-tete, meme
#     convention que charge.gd) -- c'est pour cela que sept etats du depot
#     reposent sur un MIROIR PLAT INVERSE. Le miroir sert bien ici, mais a
#     l'ENTREE dans le sommeil. Le dire une seconde fois pour la SORTIE
#     creerait deux verites qui divergeraient exactement au bord (piege nomme
#     sur data/etats.json:encombre) : sens_satisfaction "sur_seuil" de
#     couplage.gd dit deja « la reserve est remontee », une seule fois.
# (c) POURQUOI PAS extinction.gd:a_zero.produire POUR L'ISSUE (ligne 10). Il ne
#     lit qu'UN SEUL produit, fige a l'avance en donnee, et REMPLACE les
#     proprietes sur la MEME instance (meme id, meme position) -- il n'y a nulle
#     part ou mettre un second objet, et surtout l'issue n'est connue qu'a
#     l'INSTANT ou le chantier s'acheve, pas quand la donnee est ecrite. La
#     transformation "chantier_coupe_arbre" ne porte donc AUCUN a_zero :
#     extinction.gd retire simplement travail_restant/transformation, et le
#     cablage prend la main sur l'id rendu dans `accomplis` (patron
#     banc_economie.gd:fondre, qui appelle Produit.transformer hors du coeur).
# (d) POURQUOI PAS conditions.gd POUR LA SENSIBILITE A L'HUMIDITE (ligne 5). Il
#     fait N conditions en ET sur des proprietes PLATES d'UN objet et pose un
#     Dictionary -- IL NE MULTIPLIE RIEN. Une sensibilite est une COMPOSITION
#     ARITHMETIQUE, et son precedent est dans le coeur lui-meme :
#     objet.gd:_fabriquer_reserve_combustible module cout_base par la porosite
#     et la densite selon exactement cette forme. conditions.gd resterait utile
#     pour un GATE (« humide ET entaille -> poser infecte »), jamais pour un
#     facteur.
#
# ---------------------------------------------------------------------------
# CINQ PIEGES DU DEPOT, FERMES ICI PLUTOT QUE REPAYES
# ---------------------------------------------------------------------------
# - `rythme` LU BRUT NE PRODUIT RIEN. banc_commun.gd:agents_rythme lit
#   chose.proprietes.rythme TELLE QUELLE ; les etats qui modulent `rythme`
#   (data/etats.json) ne produiraient STRICTEMENT RIEN par eux-memes, aucune
#   couche ne passant par etat_effectif.gd. Ce banc n'appelle donc PAS
#   agents_rythme : il compose lui-meme le rythme effectif
#   (EtatDuree.etats_ponderes -> EtatEffectif.valeur, jamais reimplemente), ce
#   qui lui permet en plus de FILTRER les agents (gate de tranchant, sommeil).
# - UN SEUL ECRIVAIN PAR CANAL. poser_couts est le SEUL endroit du fichier qui
#   ecrit dans reserves.<sommeil>, poser_cout_entaille le seul qui ecrit dans
#   reserves.<fraicheur>. Deux morceaux de cablage qui ecrivent le meme champ se
#   detruisent EN SILENCE, aucun test ne rougit (piege nomme quatre fois dans le
#   depot : banc_infrastructure.gd:poser_encombrement, banc_bonheur.gd).
# - RIEN DANS LE COEUR NE BORNE LE HAUT D'UNE RESERVE. depense.gd borne 0.0 et
#   c'est tout ; flux.gd ne borne rien du tout. Le plafond de sommeil est donc
#   du CABLAGE (plafonner_sommeil), applique apres le pas de flux -- constat
#   deja pose cinq fois dans le depot.
# - UN CHANTIER GELE DEVIENT INVISIBLE A TOUT LE MONDE, occupant compris
#   (banc_p1.gd:mettre_a_jour_occupation, et le correctif
#   agir.gd:_avec_cible_engagee qu'il a fallu ecrire pour ca). Ce banc ne GELE
#   RIEN : un chantier occupe reste parfaitement saillant, c'est la condition
#   meme de la ligne 4 (un second ouvrier doit pouvoir le voir pour le
#   rejoindre).
# - AUCUN HASARD. Le choix d'issue est un argmax deterministe
#   (bifurcation.gd), la position des produits un offset FIXE en donnee. Deux
#   colons dans le meme etat produisent toujours la meme issue.
#
# ---------------------------------------------------------------------------
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les cinq catalogues et construit colons,
#   outils, arbres, lit et rendu ; _unhandled_input porte le seul clic (bascule
#   l'humidite locale) et ne calcule jamais rien ; _process appelle UNIQUEMENT
#   avancer() puis lit son resultat pour l'affichage et la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_affordances_travail.gd) : construire_colons/construire_outils/
#   construire_arbres/construire_lit/degat_coupe/qualite_outil/peut_couper/
#   rythme_effectif/cout_par_seconde/temps_necessaire/temps_restant/
#   resultats_depuis_perceptions/filtrer_marge/choisir_cible/poser_couts/
#   plafonner_sommeil/poser_miroir/table_flux/coupeurs_de/penalite/biais_issue/
#   abattre/gate_entaille/poser_cout_entaille/cicatriser/masse_dans_le_monde/
#   avancer, plus les textes d'affichage et de trace.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Extinction = preload("res://scripts/extinction.gd")
const Depense = preload("res://scripts/depense.gd")
const Flux = preload("res://scripts/flux.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const Couplage = preload("res://scripts/couplage.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Bifurcation = preload("res://scripts/bifurcation.gd")
const Produit = preload("res://scripts/produit.gd")
const Somme = preload("res://scripts/somme.gd")
const Portee = preload("res://scripts/portee.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

var _config: Dictionary = {}
var _catalogues: Dictionary = {}
var _etats: Dictionary = {}
var _engagements: Dictionary = {}

var _colons: Array = []
var _outils: Dictionary = {}
var _arbres: Array = []
var _lit: Dictionary = {}
var _monde
var _compteur_produit := 0
var _masse_perdue := 0.0
var _masse_reference := 0.0
var _compteurs_issue: Dictionary = {}
var _temps := 0.0
var _horloge_trace := 0.0
# MEMOIRE DE TRACE, tenue HORS proprietes -- meme statut que les echeances de
# banc_croyance.gd (`prochaine_observation`) et qu'`action_en_cours` : ce n'est
# pas un fait stable du monde, ca change a chaque tick et aucun mecanisme du
# coeur ne le lit. Sans elle, la console cracherait a CHAQUE FRAME (defaut
# mesure en scene reelle, invisible au test : un refus est un ETAT, pas un
# evenement).
var _refus_tranchant_avant: Dictionary = {}
var _refus_marge_avant: Dictionary = {}

var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres: Dictionary = {}
var _noeuds_outil: Dictionary = {}
var _label_total: Label
var _label_aide: Label

func _ready() -> void:
	_config = _charger_json("res://data/banc_affordances_travail.json")
	_catalogues = {
		"types": _charger_json("res://data/types.json"),
		"materiaux": _charger_json("res://data/materiaux.json"),
		"canaux": _charger_json("res://data/canaux.json"),
		"transformations": _charger_json("res://data/transformations.json").get("transformations", {}),
		"proprietes_immuables": _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", []),
	}
	_etats = _charger_json("res://data/etats.json")
	_engagements = _charger_json("res://data/engagements.json")

	_colons = construire_colons(_config)
	_outils = construire_outils(_config, _catalogues)
	_arbres = construire_arbres(_config, _catalogues)
	_lit = construire_lit(_config, _catalogues)

	_monde = BancCommun.monde_depuis([
		{"choses": _colons, "type": "colon"},
		{"choses": _arbres, "type": "arbre"},
		{"choses": _outils.values(), "type": "outil"},
		{"choses": [_lit], "type": "lit"},
	])

	for sortie in _config.issues.sorties:
		_compteurs_issue[String(sortie)] = 0

	# Reference posee UNE FOIS, jamais recalculee : c'est elle que
	# « monde + perdu » doit egaler a chaque tick pour que le bilan soit une
	# preuve et non un affichage (patron banc_economie.gd:_masse_reference).
	_masse_reference = masse_dans_le_monde(_monde, _config)

	_construire_rendu()
	print(ligne_pose(_config, _colons, _outils, _masse_reference))
	_rafraichir({})

func _unhandled_input(evenement: InputEvent) -> void:
	# Le clic ne fait que declencher : aucune decision, aucun calcul ici (voir
	# CLAUDE.md, Regle d'etat -- ce qui est enferme dans _unhandled_input
	# regresse en silence).
	if not (evenement is InputEventMouseButton) or not evenement.pressed:
		return
	if evenement.button_index == MOUSE_BUTTON_LEFT:
		var humide: float = basculer_humidite(_config)
		_config[String(_config.propriete_humidite)] = humide
		print(ligne_humidite(_temps, humide, cout_entaille_effectif(_config)))
		return
	if evenement.button_index == MOUSE_BUTTON_RIGHT:
		var vise: Variant = colon_le_plus_proche(_colons, get_global_mouse_position(), float(_config.rayon_clic))
		if vise == null:
			return
		if epuiser_de_force(vise, _config, _engagements):
			print(ligne_coucher(_temps, vise, _config))

func _process(delta: float) -> void:
	_temps += delta
	var bilan := avancer(
		_colons, _outils, _arbres, _lit, _monde, _compteur_produit, delta,
		_config, _catalogues, _etats, _engagements)
	_compteur_produit = int(bilan.compteur_produit)
	_masse_perdue += float(bilan.masse_perdue)

	for abattage in bilan.abattages:
		_compteurs_issue[String(abattage.issue)] = int(_compteurs_issue.get(String(abattage.issue), 0)) + 1
		print(ligne_abattage(_temps, abattage))
		_creer_rendu_produit(abattage.produit)
	for id in bilan.entailles_posees:
		print(ligne_entaille(_temps, id, _config))
	for id in bilan.cicatrises:
		print(ligne_cicatrise(_temps, id))
	for evenement in bilan.sommeil:
		print(ligne_sommeil(_temps, evenement))
	for id in nouveaux_refus(bilan.refus_tranchant, _refus_tranchant_avant):
		print(ligne_refus_tranchant(_temps, id, _config))
	for entree in nouveaux_refus_marge(bilan.refus_marge, _refus_marge_avant):
		print(ligne_refus_marge(_temps, entree))

	_horloge_trace += delta
	if _horloge_trace >= float(_config.intervalle_trace_s):
		_horloge_trace = 0.0
		print(ligne_trace(_temps, _colons, _arbres, _monde, _config, _masse_perdue, _masse_reference, _compteurs_issue))

	_rafraichir(bilan)

# ---------------------------------------------------------------------------
# Fonctions PURES, testables headless (voir test_banc_affordances_travail.gd)
# ---------------------------------------------------------------------------

# Colons construits A LA MAIN (pas Objet.fabriquer, meme statut que
# banc_fatigue_circadien.gd/banc_maladie.gd -- un colon de banc n'a pas de
# composition ici, aucun materiau n'intervient). Cles STRUCTURELLES posees
# explicitement : "engagement" (null -- couplage.gd alarme si elle manque),
# "forme" (dominance.gd), "canaux"/"canaux_config" (perception.gd),
# "etats_actifs" (etat_duree.gd/seuil_etat.gd/etat_effectif.gd). Le canal de
# sommeil part SANS seuils_ref : une reserve sans seuils est legitime pour
# depense.gd, elle decroit seulement -- ce banc n'a aucun palier a franchir, le
# franchissement qui l'interesse est celui de seuil_etat.gd sur le miroir plat.
# Les cles hors proprietes (phase, cible_id, refus) suivent action_en_cours :
# ce ne sont pas des faits stables de l'objet, aucun mecanisme du coeur ne les
# lit.
static func construire_colons(config: Dictionary) -> Array:
	var colons: Array = []
	for decl in config.get("colons", []):
		var pos: Array = decl.position
		var proprietes: Dictionary = {
			"engagement": null,
			"etats_actifs": [],
			"forme": {"seuil_ecrasement": float(decl.seuil_ecrasement)},
			"canaux": decl.canaux.duplicate(true),
			"canaux_config": decl.canaux_config.duplicate(true),
			"reserves": {
				String(config.nom_reserve_sommeil): {
					"reserve": float(decl.sommeil_initial),
					"cout_base": 0.0,
					"surcout_action": 0.0,
				},
			},
		}
		proprietes[String(config.nom_rythme)] = float(decl.rythme)
		proprietes[String(config.nom_vitesse)] = float(decl.vitesse)
		proprietes["adresse"] = float(decl.adresse)
		proprietes[String(config.nom_miroir_manque)] = 0.0
		colons.append({
			"id": String(decl.id),
			"position": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			"proprietes": proprietes,
			"cible_id": "",
			"coupe": false,
		})
	return colons

# Un outil par colon, fabrique par Objet.fabriquer sur un catalogue LOCAL a une
# entree par materiau (patron banc_coupe.gd:fabriquer_outil) : "tranchant_max"
# est FUSIONNE a la fabrication depuis data/materiaux.json
# (data/proprietes_immuables_composition.json), jamais recopie en donnee de
# banc ; "tranchant_effectif" en part (un outil neuf coupe a son plein
# potentiel). Rend un Dictionary id_colon -> outil : c'est le CABLAGE qui tient
# ce lien, aucun mecanisme du coeur n'a de notion d'equipement.
static func construire_outils(config: Dictionary, catalogues: Dictionary) -> Dictionary:
	var outils: Dictionary = {}
	for decl in config.get("colons", []):
		var nom_materiau := String(decl.materiau_outil)
		var table: Dictionary = {"outil": {"composition": [{"materiau": nom_materiau, "volume": 0.02}]}}
		var pos: Array = decl.position
		var outil := Objet.fabriquer(
			"outil_%s" % String(decl.id), "outil",
			Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			table, catalogues.materiaux, catalogues.proprietes_immuables)
		if outil.is_empty():
			continue
		outil.proprietes["etats_actifs"] = []
		outil.proprietes["materiau_outil"] = nom_materiau
		outil.proprietes[String(config.propriete_tranchant_effectif)] = \
			float(outil.proprietes.get(String(config.propriete_tranchant_max), 0.0))
		_poser_matiere(outil, config, float(outil.proprietes.masse))
		outils[String(decl.id)] = outil
	return outils

# Les arbres : Objet.fabriquer (composition fusionnee -- "resistance_cisaillement"
# arrive de data/materiaux.json par le meme chemin que tranchant_max sur
# l'outil), puis le CHANTIER pose a la main. travail_restant et travail_initial
# sont poses ENSEMBLE et le second ne bouge JAMAIS : c'est la reference dont
# proximite.gd:_poids_avancement se sert ailleurs, et celle a laquelle une
# cicatrisation ramene ici. "transformation" est une REFERENCE de catalogue
# (String) vers l'entree que resout extinction.gd, jamais un Dictionary
# imbrique -- gain de RESUMABILITE, voir son en-tete. La reserve de fraicheur
# part a cout_base 0.0 : elle ne descend QUE si l'etat d'entaille la degate
# (poser_cout_entaille), exactement le gate de banc_corrosion.gd.
static func construire_arbres(config: Dictionary, catalogues: Dictionary) -> Array:
	var table: Dictionary = {}
	for decl in config.get("arbres", []):
		table[String(decl.id)] = {"composition": [{"materiau": String(decl.materiau), "volume": float(decl.volume)}]}
	var arbres: Array = []
	for decl in config.get("arbres", []):
		var pos: Array = decl.position
		var arbre := Objet.fabriquer(
			String(decl.id), String(decl.id),
			Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
			table, catalogues.materiaux, catalogues.proprietes_immuables)
		if arbre.is_empty():
			continue
		arbre.proprietes["etats_actifs"] = []
		arbre.proprietes["travail_restant"] = float(decl.travail)
		arbre.proprietes["travail_initial"] = float(decl.travail)
		arbre.proprietes["transformation"] = String(config.transformation_chantier)
		arbre.proprietes[String(config.propriete_chantier)] = true
		arbre.proprietes[String(config.propriete_valeur)] = float(decl.valeur)
		_poser_matiere(arbre, config, float(arbre.proprietes.masse))
		var reserves: Dictionary = arbre.proprietes.reserves
		reserves[String(config.nom_reserve_fraicheur)] = {
			"reserve": float(config.fraicheur_entaille),
			"cout_base": 0.0,
			"surcout_action": 0.0,
		}
		arbres.append(arbre)
	return arbres

# Le lit porte DEUX roles sur un seul objet, jamais une structure a part : la
# CIBLE du couplage (couplage.gd:poser exige un objet qui porte un id) et la
# SOURCE flux.gd (propriete source + taux_flux + portee_flux, tous trois poses
# a la fabrication -- flux.gd ne les cherche jamais dans une table, voir son
# en-tete). Meme geste que les "lieux" de banc_economie.gd.
static func construire_lit(config: Dictionary, catalogues: Dictionary) -> Dictionary:
	var decl: Dictionary = config.lit
	var pos: Array = decl.position
	var table: Dictionary = {"lit": {"composition": [{"materiau": String(decl.materiau), "volume": float(decl.volume)}]}}
	var lit := Objet.fabriquer(String(decl.id), "lit", Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
		table, catalogues.materiaux, catalogues.proprietes_immuables)
	if lit.is_empty():
		return {}
	lit.proprietes["etats_actifs"] = []
	lit.proprietes[String(config.propriete_source_repos)] = true
	lit.proprietes["taux_flux"] = float(decl.taux_flux)
	lit.proprietes["portee_flux"] = float(decl.portee_flux)
	_poser_matiere(lit, config, float(lit.proprietes.masse))
	return lit

# La reserve de matiere est le SEUL compteur de matiere du banc, posee ici et
# nulle part ailleurs -- "ou vit la matiere" a une reponse unique. masse reste
# une SORTIE derivee de la composition, jamais reecrite (produit.gd, en-tete).
static func _poser_matiere(objet: Dictionary, config: Dictionary, quantite: float) -> void:
	var reserves: Dictionary = objet.proprietes.get("reserves", {})
	reserves[String(config.nom_reserve_matiere)] = {"reserve": quantite}
	objet.proprietes["reserves"] = reserves

static func _reserve(objet: Dictionary, nom: String) -> float:
	return float(objet.get("proprietes", {}).get("reserves", {}).get(nom, {}).get("reserve", 0.0))

# LIGNE 1 -- RECOPIE de banc_coupe.gd:degat_coupe, jamais importee (deux bancs
# jetables ne se referencent jamais entre eux). tranchant_effectif a zero rend
# 0.0 par la SEULE arithmetique, sans branche separee ; une resistance nulle ou
# negative (donnee incoherente, jamais produite par une fiche materiau reelle)
# rend 0.0 plutot que de diviser par zero -- garde defensive.
static func degat_coupe(tranchant_effectif: float, resistance_cisaillement: float) -> float:
	if resistance_cisaillement <= 0.0:
		return 0.0
	return tranchant_effectif / resistance_cisaillement

# Le ratio de coupe d'un couple (outil, cible), borne a [0, 1] pour servir de
# facteur de qualite dans le biais d'issue. Un outil MEILLEUR que la resistance
# ne rend pas la coupe "plus que parfaite" -- au-dela de 1.0 le surplus ne veut
# plus rien dire, et un facteur non borne ferait exploser le biais de reussite.
static func qualite_outil(outil: Dictionary, cible: Dictionary, config: Dictionary) -> float:
	var tranchant: float = float(outil.get("proprietes", {}).get(String(config.propriete_tranchant_effectif), 0.0))
	var resistance: float = float(cible.get("proprietes", {}).get(String(config.propriete_resistance), 0.0))
	return clamp(degat_coupe(tranchant, resistance), 0.0, 1.0)

# LE GATE DE LA LIGNE 1, et c'est un REFUS, pas un rendement nul : sous le
# seuil, le colon n'entre pas dans la liste d'agents passee a extinction.gd, sa
# presence a portee ne fait donc RIEN avancer. Comparaison STRICTEMENT au-dessus
# (`>`), meme convention que charge.gd/seuil_etat.gd dans tout le depot.
static func peut_couper(outil: Dictionary, cible: Dictionary, config: Dictionary) -> bool:
	return degat_coupe(
		float(outil.get("proprietes", {}).get(String(config.propriete_tranchant_effectif), 0.0)),
		float(cible.get("proprietes", {}).get(String(config.propriete_resistance), 0.0))
	) > float(config.seuil_tranchant)

# Le rythme EFFECTIF, compose par le cablage -- JAMAIS lu brut. Voir en-tete,
# « rythme LU BRUT NE PRODUIT RIEN » : banc_commun.gd:agents_rythme lit la
# valeur telle quelle, et un etat qui pretendrait moduler `rythme` serait vrai
# en donnee et sans effet EN SILENCE. On passe donc par le catalogue PONDERE PAR
# L'INTENSITE (etat_duree.gd:etats_ponderes) puis par etat_effectif.gd -- la loi
# de resolution (ecraser gagne sur moduler, tri alphabetique en cas de conflit)
# n'est jamais reimplementee ici.
static func rythme_effectif(colon: Dictionary, config: Dictionary, etats: Dictionary) -> float:
	var ponderes: Dictionary = EtatDuree.etats_ponderes(colon, etats)
	return EtatEffectif.valeur(colon, String(config.nom_rythme), ponderes)

# Ce que le colon depense par seconde S'IL COUPE -- la grandeur que temps_restant
# divise. Lue depuis la CONFIG et non depuis le canal : au moment ou la marge se
# calcule, le colon ne coupe pas encore, son canal porte donc le cout de la
# VEILLE seule ; c'est bien le cout du chantier A VENIR qu'il faut comparer.
static func cout_par_seconde(config: Dictionary) -> float:
	return float(config.cout_veille_par_s) + float(config.surcout_coupe_par_s)

static func temps_necessaire(cible: Dictionary, rythme: float) -> float:
	if rythme <= 0.0:
		return INF
	return float(cible.get("proprietes", {}).get("travail_restant", 0.0)) / rythme

static func temps_restant(colon: Dictionary, config: Dictionary) -> float:
	var cout := cout_par_seconde(config)
	if cout <= 0.0:
		return INF
	return _reserve(colon, String(config.nom_reserve_sommeil)) / cout

# Construit les entrees de saillance depuis la couche 1 (perception.gd, appelee
# telle quelle) -- MEME FORME que Proximite.evaluer ({ chose, type, position,
# saillance }), plus la distance. Ce banc ne monte PAS proximite.gd et c'est une
# decision : passer par lui forcerait a ajouter des entrees a un catalogue
# PARTAGE (data/profils_saillance.json, verifie par test_lint_donnees.gd contre
# tout champ profil_saillance de data/*.json) pour un banc jetable -- precedents
# banc_economie.gd/banc_grief.gd/banc_charge.gd. Un chantier deja acheve
# (travail_restant absent ou nul) n'est pas une decision a saillance nulle,
# c'est une ABSENCE de decision : il ne rend aucune entree, meme contrat que
# proximite.gd qui n'en rend jamais a saillance nulle.
static func resultats_depuis_perceptions(perceptions: Array, config: Dictionary) -> Array:
	var resultats: Array = []
	for entree in perceptions:
		var proprietes: Dictionary = entree.chose.proprietes
		if not bool(proprietes.get(String(config.propriete_chantier), false)):
			continue
		if float(proprietes.get("travail_restant", 0.0)) <= 0.0:
			continue
		resultats.append({
			"chose": entree.chose,
			"type": entree.type,
			"position": entree.position,
			"distance": float(entree.distance),
			"saillance": float(proprietes.get(String(config.propriete_valeur), 0.0)),
		})
	return resultats

# LIGNE 6 -- LE REFUS PAR RETRAIT D'UNE ENTREE DE `resultats`, AVANT
# dominance.gd. Seul precedent du depot : banc_economie.gd (« LE PREMIER RETRAIT
# D'UNE ENTREE DE resultats »). Pourquoi ce geste et pas dominance.gd : il est
# RELATIF par construction (il garde ce qui est a moins de seuil_ecrasement du
# SOMMET), il ne peut donc porter aucun refus ABSOLU -- un chantier seul dans le
# champ resterait la decision, aussi impossible soit-il a finir.
#
# DEUX MOTIFS DE RETRAIT, distincts et tous deux rendus pour que l'ecran et la
# console les nomment : "tranchant" (l'outil n'entame pas, ligne 1) et "marge"
# (pas le temps de finir avant de tomber de sommeil, ligne 6). Rendre seulement
# la liste gardee ferait ressembler un refus a une scene vide.
static func filtrer_marge(resultats: Array, colon: Dictionary, outil: Dictionary, config: Dictionary, etats: Dictionary) -> Dictionary:
	var marge: float = float(config.marge_securite)
	var rythme := rythme_effectif(colon, config, etats)
	var dispo := temps_restant(colon, config)
	var gardes: Array = []
	var retires: Array = []
	for entree in resultats:
		# Dictionary NEUF, jamais entree.duplicate(true) : une copie profonde
		# dupliquerait la CHOSE elle-meme, et dominance.gd rendrait alors des
		# entrees pointant sur des copies mortes que plus rien du monde ne mute
		# (piege ferme par banc_economie.gd:filtrer_rentables).
		var copie: Dictionary = {
			"chose": entree.chose,
			"type": entree.type,
			"position": entree.position,
			"distance": float(entree.distance),
			"saillance": float(entree.saillance),
			"necessaire": temps_necessaire(entree.chose, rythme),
			"dispo": dispo,
		}
		if not peut_couper(outil, entree.chose, config):
			copie["motif"] = "tranchant"
			retires.append(copie)
			continue
		if copie.necessaire * marge > dispo:
			copie["motif"] = "marge"
			retires.append(copie)
			continue
		gardes.append(copie)
	return {"gardes": gardes, "retires": retires}

# Le maximum de ce qui reste VISIBLE apres dominance.gd. Egalite stricte : la
# premiere declaree l'emporte, jamais un RNG (meme depart que
# agir.gd:_verbe_par_poids, sans son alarme -- ici deux chantiers a saillance
# egale sont interchangeables, pas une donnee mal posee).
static func choisir_cible(visibles: Array):
	var meilleure = null
	for entree in visibles:
		if meilleure == null or float(entree.saillance) > float(meilleure.saillance):
			meilleure = entree
	return meilleure

# LE SEUL ENDROIT DU FICHIER QUI ECRIT DANS LE CANAL DE SOMMEIL (voir en-tete,
# UN SEUL ECRIVAIN PAR CANAL). Trois lois disjointes sur un seul canal :
# - le colon qui dort ne depense RIEN (cout_base et surcout a 0.0) : c'est
#   flux.gd, et lui seul, qui fait remonter la reserve ;
# - le colon qui coupe paye la veille PLUS le surcout de coupe ;
# - le colon eveille qui ne coupe pas paye la veille seule.
# Un cout_base NEGATIF (la voie de banc_fatigue_circadien.gd, qui exploite la
# neutralite de depense.gd) aurait marche aussi -- ecarte ici parce que la ligne
# 3 demande que la recharge vienne d'une SOURCE A PORTEE (le lit), ce que seul
# flux.gd sait faire : un colon qui s'endort loin de son lit ne recupere rien,
# et c'est visible a l'ecran.
static func poser_couts(colons: Array, config: Dictionary, etats: Dictionary) -> void:
	var nom_sommeil := String(config.nom_reserve_sommeil)
	for colon in colons:
		var canal: Dictionary = colon.proprietes.reserves[nom_sommeil]
		if colon.proprietes.get("etats_actifs", []).has(String(config.nom_etat_repose)):
			canal["cout_base"] = 0.0
			canal["surcout_action"] = 0.0
			continue
		canal["cout_base"] = float(config.cout_veille_par_s)
		canal["surcout_action"] = float(config.surcout_coupe_par_s) if bool(colon.get("coupe", false)) else 0.0

# LE SEUL ENDROIT DU FICHIER QUI ECRIT DANS LE CANAL DE FRAICHEUR. Le cout_base
# n'est actif QUE tant que l'etat d'entaille l'est -- gate exact de
# banc_corrosion.gd (INVERSE de banc_p1.gd:geler_combustible_apres_sauvetage,
# qui gele quand l'etat DISPARAIT). La valeur EFFECTIVE est composee ici avec
# l'humidite, jamais lue telle quelle : voir cout_entaille_effectif.
static func poser_cout_entaille(arbres: Array, config: Dictionary) -> void:
	var nom_fraicheur := String(config.nom_reserve_fraicheur)
	var nom_etat := String(config.nom_etat_entaille)
	var cout := cout_entaille_effectif(config)
	for arbre in arbres:
		var reserves: Dictionary = arbre.proprietes.get("reserves", {})
		if not reserves.has(nom_fraicheur):
			continue
		var actif: bool = arbre.proprietes.get("etats_actifs", []).has(nom_etat)
		reserves[nom_fraicheur]["cout_base"] = cout if actif else 0.0

# LA COMPOSITION DE LA LIGNE 5, au cablage et nulle part ailleurs :
# degradation_base * (1 + sensibilite_humidite * humidite). conditions.gd ne
# peut pas la faire (il ne multiplie rien, voir en-tete (d)) ; le precedent est
# dans le coeur lui-meme, objet.gd:_fabriquer_reserve_combustible module
# cout_base par porosite et densite selon exactement cette forme.
static func cout_entaille_effectif(config: Dictionary) -> float:
	return float(config.degradation_entaille_base) \
		* (1.0 + float(config.sensibilite_humidite) * float(config.get(String(config.propriete_humidite), 0.0)))

# ECRETAGE AU PLAFOND -- du CABLAGE, jamais un mecanisme : depense.gd ne borne
# que le BAS (0.0) et flux.gd ne borne rien du tout. Applique APRES le pas de
# flux, sinon le sommeil depasserait sa capacite d'un tick a chaque nuit. Rend
# le total ecrete ce pas (surplus perdu, jamais reverse ailleurs), pour la trace.
static func plafonner_sommeil(colons: Array, config: Dictionary) -> float:
	var plafond: float = float(config.capacite_sommeil)
	var nom := String(config.nom_reserve_sommeil)
	var ecrete := 0.0
	for colon in colons:
		var canal: Dictionary = colon.proprietes.reserves[nom]
		var reserve: float = float(canal.get("reserve", 0.0))
		if reserve > plafond:
			ecrete += reserve - plafond
			canal["reserve"] = plafond
	return ecrete

# MIROIR PLAT INVERSE (patron banc_fatigue_circadien.gd:poser_miroir) : la seule
# forme sous laquelle seuil_etat.gd peut voir une reserve DESCENDRE -- il ne lit
# que des cles PLATES (une reserve vit a proprietes.reserves.<nom>.reserve,
# inatteignable) et ne compare que VERS LE HAUT. « la reserve tombe sous 30 »
# s'ecrit donc « le manque monte au-dessus de 70 ».
static func poser_miroir(colons: Array, config: Dictionary) -> void:
	var capacite: float = float(config.capacite_sommeil)
	var nom_miroir := String(config.nom_miroir_manque)
	for colon in colons:
		colon.proprietes[nom_miroir] = capacite - _reserve(colon, String(config.nom_reserve_sommeil))

# La table de regles de flux.gd : une seule ligne, source -> receptrice ->
# reserve cible. Ni la source, ni la receptrice, ni le nom de reserve ne sont
# nommes en dur dans le mecanisme -- ils arrivent tous de la donnee.
static func table_flux(config: Dictionary) -> Array:
	return [{
		"source": String(config.propriete_source_repos),
		"receptrice": String(config.propriete_recoit_repos),
		"cible": String(config.nom_reserve_sommeil),
	}]

# LES AGENTS D'UN CHANTIER, filtres et composes par le cablage -- jamais
# BancCommun.agents_rythme (qui prend TOUT ce qui porte `rythme` et le lit
# BRUT). Quatre conditions, toutes du cablage : avoir CHOISI ce chantier-ci
# (colon.coupe posee par la decision de ce tick, sur colon.cible_id), etre a
# portee_travail (meme test que extinction.gd, Portee.en_portee), ne pas dormir,
# et passer le gate de tranchant CONTRE CETTE CIBLE-CI (la resistance varie par
# cible, le gate ne peut donc pas se pre-calculer une fois pour toutes).
#
# LA CONDITION DE DECISION N'EST PAS UN CONFORT, elle ferme deux defauts reels
# mesures en test : (a) sans elle, un colon qui a REFUSE le chantier (marge de
# securite, ligne 6) le travaillerait quand meme du seul fait d'etre a portee --
# le refus serait vrai dans `resultats` et faux dans le monde ; (b) un colon en
# route vers un chantier lointain travaillerait AU PASSAGE tout chantier qu'il
# frole. extinction.gd ne peut pas le savoir lui-meme : il ne recoit que des
# positions et des rythmes, aucune notion de cible choisie.
#
# Rend la forme exacte qu'extinction.gd attend ({ position, rythme }) PLUS l'id
# du colon, dont extinction.gd ne fait rien : c'est le cablage qui s'en sert
# ensuite pour retrouver qui a porte le coup final.
static func coupeurs_de(arbre: Dictionary, colons: Array, outils: Dictionary, portee: float, config: Dictionary, etats: Dictionary) -> Array:
	var agents: Array = []
	for colon in colons:
		if not bool(colon.get("coupe", false)) or String(colon.get("cible_id", "")) != String(arbre.id):
			continue
		if colon.proprietes.get("etats_actifs", []).has(String(config.nom_etat_repose)):
			continue
		if not Portee.en_portee(arbre.position, colon.position, portee):
			continue
		var outil: Dictionary = outils.get(String(colon.id), {})
		if outil.is_empty() or not peut_couper(outil, arbre, config):
			continue
		agents.append({
			"position": colon.position,
			"rythme": rythme_effectif(colon, config, etats),
			"id": String(colon.id),
		})
	return agents

# La PENALITE qui compose le biais d'issue : fatigue + (1 - qualite_outil),
# entre 0.0 et 2.0. Un colon frais avec un bon outil est a ~0.0, un colon
# epuise avec un mauvais outil a ~2.0. Une seule grandeur, monotone, dont les
# trois biais se derivent -- plutot que trois formules independantes qui
# pourraient se contredire.
static func penalite(colon: Dictionary, outil: Dictionary, cible: Dictionary, config: Dictionary) -> float:
	var fatigue: float = clamp(
		float(colon.proprietes.get(String(config.nom_miroir_manque), 0.0)) / float(config.capacite_sommeil),
		0.0, 1.0)
	return fatigue + (1.0 - qualite_outil(outil, cible, config))

# LIGNE 10 -- OU VIT REELLEMENT L'ARBITRAGE. bifurcation.gd le dit dans son
# propre en-tete : la `grandeur` est UN SEUL SCALAIRE commun a toutes les
# sorties, tant qu'elle est positive elle multiplie tout par le meme nombre et
# NE CHANGE JAMAIS QUI GAGNE -- elle ne joue qu'un GATE et une echelle. Tout
# l'arbitrage vit donc ICI, dans le biais compose par colon et par tick
# (precedent : banc_predation.gd, biais.territoire x densite d'intrus).
#
# Les trois facteurs sont DISJOINTS par construction : reussite ne survit
# qu'en dessous de penalite 1.0, debris n'apparait qu'au-dessus, eclats couvre
# tout l'intervalle. Sans base_debris nettement superieure aux deux autres
# (1.6 contre 0.9), la troisieme sortie ne gagnerait JAMAIS et serait morte en
# donnee -- verrouille a l'envers par le test.
static func biais_issue(colon: Dictionary, outil: Dictionary, cible: Dictionary, config: Dictionary) -> Dictionary:
	var base: Dictionary = config.issues.base_biais
	var p := penalite(colon, outil, cible, config)
	var adresse: float = float(colon.proprietes.get("adresse", 1.0))
	return {
		"reussite": float(base.reussite) * adresse * max(0.0, 1.0 - p),
		"eclats": float(base.eclats) * min(1.0, p),
		"debris": float(base.debris) * max(0.0, p - 1.0),
	}

# L'ABATTAGE : bifurcation.gd tranche, PUIS le cablage appelle lui-meme
# Produit.transformer sur la SEULE issue gagnante et fabrique un vrai objet
# (patron banc_economie.gd:fondre / banc_elimination_salete.gd:fabriquer_dechet).
# La `grandeur` passee a bifurcation.gd est le ratio de coupe, toujours
# strictement positif des lors que le chantier a pu avancer -- le gate
# arithmetique est donc coherent avec seuil_tranchant sans qu'aucune branche ne
# le repete.
#
# CE QUE DEVIENT L'ARBRE : sa reserve de matiere passe a 0.0 (c'est une SOUCHE,
# elle reste dans le monde) et le produit nait a cote avec masse * rendement. Le
# COMPLEMENT du rendement n'est nulle part -- produit.gd le dit lui-meme -- et
# ce fichier le COMPTE (masse_perdue) plutot que de le laisser disparaitre du
# bilan : « monde + perdu » reste alors exactement constant, et c'est ca que le
# test verrouille. Contrairement a la paire fonte_metal/fonte_scories de
# banc_economie.gd, les trois issues ne somment PAS a 1.0 : rater DETRUIT
# vraiment de la matiere, c'est le sujet meme de la ligne 10.
#
# Rend {} si l'issue ne resout pas (aucune sortie gagnante, transformation
# absente, produit.gd qui refuse) -- jamais un objet a masse zero ajoute au
# Monde.
static func abattre(arbre: Dictionary, colon: Dictionary, outil: Dictionary, monde, compteur: int, config: Dictionary, catalogues: Dictionary) -> Dictionary:
	var biais := biais_issue(colon, outil, arbre, config)
	var resolution := Bifurcation.resoudre(qualite_outil(outil, arbre, config), biais, config.issues.sorties)
	var issue := String(resolution.sortie)
	if issue == "":
		return {}
	var ref := String(config.issues.refs.get(issue, ""))
	if not catalogues.transformations.has(ref):
		push_error("banc_affordances_travail : transformation '%s' (issue '%s') absente du catalogue" % [ref, issue])
		return {}

	var masse_avant: float = _reserve(arbre, String(config.nom_reserve_matiere))
	var produire: Dictionary = catalogues.transformations[ref].get("a_zero", {}).get("produire", {})
	# proprietes_ancien SYNTHETIQUE ({ masse }) : produit.gd ne lit QUE cette
	# cle dessus (son en-tete), et la matiere du chantier vit dans une RESERVE,
	# pas dans la masse derivee de la composition -- qu'il est interdit de
	# reecrire ailleurs qu'a la fabrication.
	var proprietes := Produit.transformer({"masse": masse_avant}, produire, catalogues.types, catalogues.materiaux)
	if proprietes.is_empty():
		return {}

	compteur += 1
	var offset: Array = config.issues.offset_produit
	var produit: Dictionary = {
		"id": "%s_%d" % [String(produire.type_produit), compteur],
		"position": arbre.position + Vector3(float(offset[0]), float(offset[1]), float(offset[2])),
		"proprietes": proprietes,
	}
	_poser_matiere(produit, config, float(proprietes.masse))
	produit.proprietes["issue_coupe"] = issue
	monde.ajouter(produit, "produit", produit.position)

	# La souche : plus de matiere a prendre, plus un chantier (extinction.gd a
	# deja retire travail_restant/transformation -- l'entree resolue ne porte
	# aucun a_zero, voir data/transformations.json:chantier_coupe_arbre).
	_poser_matiere(arbre, config, 0.0)
	arbre.proprietes.erase(String(config.propriete_chantier))

	return {
		"arbre_id": String(arbre.id),
		"colon_id": String(colon.id),
		"issue": issue,
		"scores": resolution.scores,
		"produit": produit,
		"masse_perdue": masse_avant - float(proprietes.masse),
		"compteur_produit": compteur,
	}

# LIGNE 5 -- POSE ET REPOSE DE L'ENTAILLE. Un arbre ENTAME (travail_restant
# strictement entre 0 et travail_initial) et ABANDONNE (aucun coupeur a portee
# ce tick) porte l'etat, REPOSE chaque tick tant que l'abandon dure : idiome
# litteral de `nausee_radiation`/`empoisonne`/`corrode` (etat_duree.gd:poser est
# une remise a 1.0, JAMAIS un cumul, sa propre doctrine). Des qu'un colon
# reprend, plus personne ne repose : l'intensite s'epuise seule et etat_duree.gd
# retire l'etat -- l'entaille se referme sans qu'aucune branche ne le dise.
# Rend les ids FRAICHEMENT entailles (l'etat n'y etait pas au tick precedent),
# jamais tous ceux qui le portent : sans ca la console cracherait a chaque
# frame.
static func gate_entaille(arbres: Array, coupeurs_par_arbre: Dictionary, config: Dictionary, etats: Dictionary) -> Array:
	var nom_etat := String(config.nom_etat_entaille)
	var fraiches: Array = []
	for arbre in arbres:
		var proprietes: Dictionary = arbre.proprietes
		var restant: float = float(proprietes.get("travail_restant", 0.0))
		var initial: float = float(proprietes.get("travail_initial", 0.0))
		if restant <= 0.0 or restant >= initial:
			continue
		if not coupeurs_par_arbre.get(String(arbre.id), []).is_empty():
			continue
		var avant: bool = proprietes.get("etats_actifs", []).has(nom_etat)
		EtatDuree.poser(arbre, nom_etat, etats)
		if not avant:
			fraiches.append(String(arbre.id))
	return fraiches

# LE COUT DE L'ABANDON, une fois la reserve de fraicheur epuisee : le chantier
# est PERDU, travail_restant remonte a travail_initial. Ce n'est pas un
# mecanisme de plus -- c'est une ecriture de cablage sur deux nombres deja la,
# et c'est ce qui donne un prix a l'abandon (ligne 6 de l'audit : « l'etat
# partiel degrade de la ligne 5 EST le cout de l'abandon »). L'etat et la
# reserve sont remis a neuf dans le meme geste, sinon l'arbre cicatriserait en
# boucle a chaque tick suivant.
static func cicatriser(arbres: Array, config: Dictionary) -> Array:
	var nom_fraicheur := String(config.nom_reserve_fraicheur)
	var nom_etat := String(config.nom_etat_entaille)
	var cicatrises: Array = []
	for arbre in arbres:
		var proprietes: Dictionary = arbre.proprietes
		if float(proprietes.get("travail_restant", 0.0)) <= 0.0:
			continue
		var canal: Dictionary = proprietes.get("reserves", {}).get(nom_fraicheur, {})
		if canal.is_empty() or float(canal.get("reserve", 0.0)) > 0.0:
			continue
		proprietes["travail_restant"] = float(proprietes.get("travail_initial", 0.0))
		canal["reserve"] = float(config.fraicheur_entaille)
		canal["cout_base"] = 0.0
		proprietes.get("etats_actifs", []).erase(nom_etat)
		proprietes.get("etats_intensite", {}).erase(nom_etat)
		cicatrises.append(String(arbre.id))
	return cicatrises

# LA MESURE DE CONSERVATION, par somme.gd sur la reserve de matiere de TOUT le
# monde (arbres, souches, outils, lit, produits). Les colons n'en portent pas :
# somme.gd ignore silencieusement une entite sans la reserve demandee (contrat
# de son en-tete), aucune garde a ajouter ici.
static func masse_dans_le_monde(monde, config: Dictionary) -> float:
	return Somme.reserves(BancCommun.objets_de(monde), String(config.nom_reserve_matiere))

# UN REFUS EST UN ETAT, PAS UN EVENEMENT -- il reste vrai tant que rien ne
# change, et le tracer tel quel remplit la console a chaque frame (defaut mesure
# en scene reelle, JAMAIS visible au test : le test lit des listes, pas un
# terminal). Ces deux fonctions rendent la seule BASCULE, exactement le geste de
# banc_fatigue_circadien.gd:evaluer_zone et banc_biomes.gd:evaluer_biomes, et
# pour la meme raison. Elles MUTENT la memoire recue -- l'appelant la tient hors
# de proprietes, comme les echeances de banc_croyance.gd.
static func nouveaux_refus(refus: Array, memoire: Dictionary) -> Array:
	var nouveaux: Array = []
	for id in refus:
		if not bool(memoire.get(String(id), false)):
			nouveaux.append(String(id))
	var frais: Dictionary = {}
	for id in refus:
		frais[String(id)] = true
	memoire.clear()
	memoire.merge(frais, true)
	return nouveaux

static func nouveaux_refus_marge(refus: Array, memoire: Dictionary) -> Array:
	var nouveaux: Array = []
	var frais: Dictionary = {}
	for entree in refus:
		var cle := "%s|%s" % [String(entree.colon_id), String(entree.cible_id)]
		frais[cle] = true
		if not bool(memoire.get(cle, false)):
			nouveaux.append(entree)
	memoire.clear()
	memoire.merge(frais, true)
	return nouveaux

static func basculer_humidite(config: Dictionary) -> float:
	return 0.0 if float(config.get(String(config.propriete_humidite), 0.0)) > 0.0 else float(config.humidite_locale)

# LE SEUL GESTE QUI ARRACHE UN COLON A SON CHANTIER -- et il est ici parce que
# la scene, sans lui, NE MONTRE JAMAIS L'ENTAILLE (mesure en scene reelle, 45 s
# de console lue : zero entaille). Ce n'est pas un defaut du montage, c'est ce
# que la ligne 6 ACHETE : la marge de securite garantit qu'un colon qui entame a
# de quoi finir, et une fois le chantier entame la condition ne peut que
# S'AMELIORER (le travail restant baisse de rythme par seconde, l'autonomie de
# une seconde par seconde). Un abandon spontane est donc STRUCTURELLEMENT
# impossible tant que la marge tient -- l'entaille de la ligne 5 n'existe que
# pour ce que la marge ne couvre pas, et il faut un geste EXTERIEUR pour le
# provoquer.
#
# LE CLIC AGIT SUR UNE GRANDEUR DU MONDE, JAMAIS SUR UNE DECISION : il vide la
# reserve de sommeil sous le seuil de bascule, et TOUT le reste suit par le
# chemin normal, sans un seul cas particulier -- l'engagement se pose au tick
# suivant (couplage.gd), le colon lache son chantier et part au lit, le chantier
# entame et desormais desert recoit son entaille (gate_entaille), puis il dort,
# se reveille et revient.
#
# POSER L'ENGAGEMENT DIRECTEMENT A ETE ESSAYE ET NE MARCHE PAS -- resultat
# negatif, mesure au test, a ne pas repayer : sens_satisfaction "sur_seuil"
# declare l'engagement SATISFAIT des que la reserve depasse seuil_satisfait, ce
# qui est deja vrai pour un colon repose ; couplage.gd le relachait donc au tick
# suivant, avant meme que le colon n'ait bouge. On ne force pas une decision
# contre le mecanisme qui la produit -- on change la grandeur dont elle depend.
#
# Le miroir plat est reecrit dans le meme geste : sans lui, seuil_etat.gd ne
# verrait le manque qu'au tick suivant et 'epuise' arriverait en retard d'une
# image. Rend false si le colon dort deja (rien a epuiser).
static func epuiser_de_force(colon: Dictionary, config: Dictionary, engagements: Dictionary) -> bool:
	if colon.proprietes.get("engagement", null) != null:
		return false
	var seuil_bascule: float = float(engagements.get(String(config.regle_engagement_dormir), {}).get("seuil_bascule", 0.0))
	colon.proprietes.reserves[String(config.nom_reserve_sommeil)]["reserve"] = max(0.0, seuil_bascule - 1.0)
	colon.proprietes[String(config.nom_miroir_manque)] = \
		float(config.capacite_sommeil) - max(0.0, seuil_bascule - 1.0)
	return true

static func colon_le_plus_proche(colons: Array, position_ecran: Vector2, rayon: float) -> Variant:
	var meilleur: Variant = null
	var meilleure_distance := INF
	for colon in colons:
		var distance: float = Vector2(colon.position.x, colon.position.y).distance_to(position_ecran)
		if distance < meilleure_distance and distance <= rayon:
			meilleure_distance = distance
			meilleur = colon
	return meilleur

# UN TICK COMPLET, l'ordre compris. Statique et sans noeud : le test rejoue
# EXACTEMENT ce que la scene execute, jamais une reconstitution parallele qui
# pourrait deriver (patron banc_economie.gd:avancer/banc_fatigue_circadien.gd).
# MUTE colons, arbres et monde en place.
#
# L'ORDRE N'EST PAS LIBRE, huit contraintes le fixent :
#  (1) poser_couts et poser_cout_entaille AVANT Depense.avancer -- sinon la
#      depense de ce tick utiliserait les couts du precedent ;
#  (2) Flux.avancer APRES Depense.avancer -- un dormeur doit recuperer sur une
#      reserve deja ponctionnee, jamais l'inverse (l'ordre inverse rendrait la
#      recharge invisible au plafond) ;
#  (3) plafonner_sommeil APRES flux -- rien dans le coeur ne borne le haut ;
#  (4) poser_miroir sur la reserve FRAICHE, puis SeuilEtat.avancer qui le
#      compare -- l'un sans l'autre ne produit rien ;
#  (5) Couplage.avancer AVANT la decision -- garde/satisfait/arrache doit
#      s'evaluer avant que la decision de ce tick ne lise l'engagement, jamais
#      apres (sinon la decision verrait un etat perime) ; meme ordre exact que
#      banc_p1.gd:agir_et_deplacer ;
#  (6) coupeurs_de calcule AVANT Extinction.avancer et memorise -- apres, le
#      chantier accompli n'a plus ni travail_restant ni transformation, on ne
#      saurait plus qui a porte le coup final ;
#  (7) gate_entaille APRES Extinction.avancer -- un arbre travaille CE tick ne
#      doit pas etre declare abandonne ;
#  (8) cicatriser en DERNIER sur les nombres du tick -- la reserve de fraicheur
#      vient d'etre ponctionnee, c'est sa valeur d'apres qui decide.
static func avancer(
	colons: Array,
	outils: Dictionary,
	arbres: Array,
	lit: Dictionary,
	monde,
	compteur_produit: int,
	delta: float,
	config: Dictionary,
	catalogues: Dictionary,
	etats: Dictionary,
	engagements: Dictionary,
) -> Dictionary:
	var objets: Array = BancCommun.objets_de(monde)

	poser_couts(colons, config, etats)
	poser_cout_entaille(arbres, config)
	Depense.avancer(objets, delta, {})
	Flux.avancer(objets, table_flux(config), delta)
	var ecrete := plafonner_sommeil(colons, config)
	poser_miroir(colons, config)
	var bascules_seuil := SeuilEtat.avancer(colons, config.seuils_locaux)

	var evenements_sommeil: Array = []
	var refus_tranchant: Array = []
	var refus_marge: Array = []
	var portee_travail: float = float(catalogues.transformations
		.get(String(config.transformation_chantier), {}).get("portee_travail", 0.0))

	for colon in colons:
		evenements_sommeil += _avancer_sommeil(colon, lit, delta, config, etats, engagements)
		var outil: Dictionary = outils.get(String(colon.id), {})
		var engage_sommeil: bool = colon.proprietes.get("engagement", null) != null

		colon["coupe"] = false
		if engage_sommeil:
			colon["cible_id"] = ""
			if not colon.proprietes.get("etats_actifs", []).has(String(config.nom_etat_repose)):
				colon.position = BancCommun.bouger_vers(
					colon.position, lit.position,
					float(colon.proprietes.get(String(config.nom_vitesse), 0.0)), delta)
			continue

		var perceptions := Perception.percevoir(colon, monde, catalogues.canaux)
		var filtre := filtrer_marge(resultats_depuis_perceptions(perceptions, config), colon, outil, config, etats)
		for entree in filtre.retires:
			if String(entree.motif) == "tranchant":
				if not refus_tranchant.has(String(colon.id)):
					refus_tranchant.append(String(colon.id))
			else:
				refus_marge.append({"colon_id": String(colon.id), "cible_id": String(entree.chose.id),
					"necessaire": float(entree.necessaire), "dispo": float(entree.dispo)})
		var cible = choisir_cible(Dominance.visibles(filtre.gardes, colon))
		if cible == null:
			colon["cible_id"] = ""
			continue
		colon["cible_id"] = String(cible.chose.id)
		if Portee.en_portee(cible.chose.position, colon.position, portee_travail):
			colon["coupe"] = true
		else:
			colon.position = BancCommun.bouger_vers(
				colon.position, cible.chose.position,
				float(colon.proprietes.get(String(config.nom_vitesse), 0.0)), delta)

	# Un appel a Extinction.avancer PAR ARBRE (patron banc_corrosion.gd, « un
	# appel a Charge.avancer PAR OBJET ») : la liste d'agents depend de la
	# CIBLE, le gate de tranchant comparant la resistance de celle-ci -- une
	# liste globale melangerait les gates de deux cibles differentes.
	var coupeurs_par_arbre: Dictionary = {}
	var accomplis: Array = []
	for arbre in arbres:
		var agents := coupeurs_de(arbre, colons, outils, portee_travail, config, etats)
		coupeurs_par_arbre[String(arbre.id)] = agents
		accomplis += Extinction.avancer([arbre], agents, delta, catalogues.transformations)

	var abattages: Array = []
	var masse_perdue := 0.0
	for id in accomplis:
		var arbre := _par_id(arbres, String(id))
		var agents: Array = coupeurs_par_arbre.get(String(id), [])
		if arbre.is_empty() or agents.is_empty():
			continue
		var colon := _par_id(colons, String(_agent_principal(agents).id))
		if colon.is_empty():
			continue
		var abattage := abattre(arbre, colon, outils.get(String(colon.id), {}), monde, compteur_produit, config, catalogues)
		if abattage.is_empty():
			continue
		compteur_produit = int(abattage.compteur_produit)
		masse_perdue += float(abattage.masse_perdue)
		abattages.append(abattage)

	var entailles := gate_entaille(arbres, coupeurs_par_arbre, config, etats)
	var cicatrises := cicatriser(arbres, config)
	var expirees := EtatDuree.avancer(BancCommun.objets_de(monde), delta, etats)

	return {
		"compteur_produit": compteur_produit,
		"abattages": abattages,
		"masse_perdue": masse_perdue,
		"entailles_posees": entailles,
		"cicatrises": cicatrises,
		"sommeil": evenements_sommeil,
		"refus_tranchant": refus_tranchant,
		"refus_marge": refus_marge,
		"bascules_seuil": bascules_seuil,
		"expirees": expirees,
		"ecrete": ecrete,
		"coupeurs": coupeurs_par_arbre,
	}

# LIGNE 3 -- LE CYCLE DE SOMMEIL, en trois gestes et aucun mecanisme neuf.
# 1. COUPLAGE EN COURS : Couplage.avancer l'evalue contre sa cible REELLE. Il
#    rend "satisfait" quand reserves.sommeil.reserve repasse AU-DESSUS de
#    seuil_satisfait -- c'est sens_satisfaction "sur_seuil"
#    (data/engagements.json:dormir_reserve) qui le dit, jamais un seuil de plus
#    ecrit ici. Au reveil, le cablage retire l'etat marqueur et la propriete
#    receptrice de flux.gd : le colon cesse de recuperer par la seule donnee.
# 2. POSE : sous seuil_bascule (lu sur la regle du catalogue -- couplage.gd le
#    cache sur l'engagement mais ne s'en sert jamais lui-meme, c'est l'appelant
#    qui decide de poser, patron banc_animal.gd), l'engagement se pose sur le
#    LIT. Le colon se met en route ; il ne dort pas encore.
# 3. ENDORMISSEMENT PAR PRESENCE : l'etat "repose" et la propriete receptrice
#    ne sont poses qu'une fois le colon A PORTEE du lit. Un colon qui s'engage
#    a l'autre bout de la carte ne recupere RIEN tant qu'il marche -- flux.gd
#    est un transfert A PORTEE, la geometrie fait le travail sans qu'aucune
#    branche ne la repete.
# Rend les evenements de ce tick pour la trace, jamais l'etat.
static func _avancer_sommeil(colon: Dictionary, lit: Dictionary, delta: float, config: Dictionary, etats: Dictionary, engagements: Dictionary) -> Array:
	var evenements: Array = []
	var nom_repose := String(config.nom_etat_repose)
	var regle := String(config.regle_engagement_dormir)
	var actifs: Array = colon.proprietes.get("etats_actifs", [])

	if colon.proprietes.get("engagement", null) != null:
		var verdict := Couplage.avancer(colon, lit, delta, engagements)
		if verdict == "satisfait" or verdict == "arrache":
			actifs.erase(nom_repose)
			colon.proprietes.erase(String(config.propriete_recoit_repos))
			evenements.append({"colon_id": String(colon.id), "quoi": "reveil", "verdict": verdict,
				"reserve": _reserve(colon, String(config.nom_reserve_sommeil))})
			return evenements

	if colon.proprietes.get("engagement", null) == null:
		var seuil_bascule: float = float(engagements.get(regle, {}).get("seuil_bascule", 0.0))
		if _reserve(colon, String(config.nom_reserve_sommeil)) <= seuil_bascule:
			Couplage.poser(colon, lit, regle, engagements, {"canal": String(config.canal_engagement)})
			evenements.append({"colon_id": String(colon.id), "quoi": "engage",
				"reserve": _reserve(colon, String(config.nom_reserve_sommeil))})
		return evenements

	if not actifs.has(nom_repose) and Portee.en_portee(lit.position, colon.position, float(config.portee_lit)):
		EtatDuree.poser(colon, nom_repose, etats)
		colon.proprietes[String(config.propriete_recoit_repos)] = true
		evenements.append({"colon_id": String(colon.id), "quoi": "endormi",
			"reserve": _reserve(colon, String(config.nom_reserve_sommeil))})
	return evenements

# L'agent au plus fort rythme parmi ceux presents au coup final -- c'est lui
# dont l'adresse et la fatigue composent le biais d'issue. Egalite stricte : le
# PREMIER de la liste l'emporte, ordre DECLARE (celui de config.colons), jamais
# un ordre d'iteration de Dictionary ni un tirage.
static func _agent_principal(agents: Array) -> Dictionary:
	var meilleur: Dictionary = agents[0]
	for agent in agents:
		if float(agent.rythme) > float(meilleur.rythme):
			meilleur = agent
	return meilleur

static func _par_id(objets: Array, id: String) -> Dictionary:
	for objet in objets:
		if String(objet.id) == id:
			return objet
	return {}

# ---- Textes (aucune decision, seulement de la mise en forme) ----

static func texte_colon(colon: Dictionary, outils: Dictionary, config: Dictionary, etats: Dictionary) -> String:
	var outil: Dictionary = outils.get(String(colon.id), {})
	var actifs: Array = colon.proprietes.get("etats_actifs", [])
	var noms: Array = []
	for nom in actifs:
		noms.append(String(nom))
	noms.sort()
	return "%s\ntranchant=%.2f (%s)\nrythme=%.2f  sommeil=%.1f\n%s\n%s" % [
		String(colon.id),
		float(outil.get("proprietes", {}).get(String(config.propriete_tranchant_effectif), 0.0)),
		String(outil.get("proprietes", {}).get("materiau_outil", "?")),
		rythme_effectif(colon, config, etats),
		_reserve(colon, String(config.nom_reserve_sommeil)),
		("cible %s" % String(colon.cible_id)) if String(colon.cible_id) != "" else "cible aucune",
		("etats : " + ", ".join(noms)) if not noms.is_empty() else "etats : aucun",
	]

static func texte_arbre(arbre: Dictionary, config: Dictionary) -> String:
	var proprietes: Dictionary = arbre.proprietes
	var restant: float = float(proprietes.get("travail_restant", 0.0))
	if restant <= 0.0:
		return "%s\nSOUCHE\nmatiere=%.1f" % [String(arbre.id), _reserve(arbre, String(config.nom_reserve_matiere))]
	var entaille: bool = proprietes.get("etats_actifs", []).has(String(config.nom_etat_entaille))
	return "%s\nresistance=%.1f\ntravail %.2f / %.2f\nfraicheur %.2f%s" % [
		String(arbre.id),
		float(proprietes.get(String(config.propriete_resistance), 0.0)),
		restant, float(proprietes.get("travail_initial", 0.0)),
		_reserve(arbre, String(config.nom_reserve_fraicheur)),
		"  ENTAILLE" if entaille else "",
	]

static func texte_total(monde, config: Dictionary, masse_perdue: float, reference: float, compteurs: Dictionary) -> String:
	var dans_le_monde := masse_dans_le_monde(monde, config)
	return "MASSE %.3f = monde %.3f + perdu a la coupe %.3f   (reference %.3f, ecart %.6f)   |   reussites %d  eclats %d  debris %d" % [
		dans_le_monde + masse_perdue, dans_le_monde, masse_perdue, reference,
		absf(dans_le_monde + masse_perdue - reference),
		int(compteurs.get("reussite", 0)), int(compteurs.get("eclats", 0)), int(compteurs.get("debris", 0)),
	]

static func ligne_pose(config: Dictionary, colons: Array, outils: Dictionary, reference: float) -> String:
	var details: Array = []
	for colon in colons:
		var outil: Dictionary = outils.get(String(colon.id), {})
		details.append("%s (%s, tranchant %.1f)" % [
			String(colon.id), String(outil.get("proprietes", {}).get("materiau_outil", "?")),
			float(outil.get("proprietes", {}).get(String(config.propriete_tranchant_effectif), 0.0)),
		])
	return "t=0.0 pose : %s | %d arbres, seuil de tranchant %.2f, marge de securite %.2f -- masse de reference %.3f" % [
		", ".join(details), config.arbres.size(), float(config.seuil_tranchant),
		float(config.marge_securite), reference,
	]

static func ligne_abattage(t: float, abattage: Dictionary) -> String:
	var scores: Array = []
	for sortie in abattage.scores:
		scores.append("%s=%.3f" % [String(sortie), float(abattage.scores[sortie])])
	return "t=%.1f ABATTU : %s par %s -> ISSUE '%s' (%s) -- %s pese %.3f, %.3f perdu" % [
		t, String(abattage.arbre_id), String(abattage.colon_id), String(abattage.issue),
		", ".join(scores), String(abattage.produit.id),
		float(abattage.produit.proprietes.masse), float(abattage.masse_perdue),
	]

static func ligne_entaille(t: float, id: String, config: Dictionary) -> String:
	return "t=%.1f ENTAILLE : %s laisse en chantier, sa fraicheur se degrade a %.3f/s (humidite %.2f)" % [
		t, id, cout_entaille_effectif(config), float(config.get(String(config.propriete_humidite), 0.0)),
	]

static func ligne_cicatrise(t: float, id: String) -> String:
	return "t=%.1f CICATRISE : %s -- l'entaille s'est refermee, TOUT le travail deja fourni est perdu" % [t, id]

static func ligne_sommeil(t: float, evenement: Dictionary) -> String:
	match String(evenement.quoi):
		"engage":
			return "t=%.1f %s : va dormir (sommeil %.1f sous le seuil de bascule)" % [t, String(evenement.colon_id), float(evenement.reserve)]
		"endormi":
			return "t=%.1f %s : s'endort au lit -- flux.gd recharge (sommeil %.1f)" % [t, String(evenement.colon_id), float(evenement.reserve)]
		_:
			return "t=%.1f %s : se reveille, couplage '%s' (sommeil %.1f)" % [t, String(evenement.colon_id), String(evenement.get("verdict", "")), float(evenement.reserve)]

static func ligne_refus_tranchant(t: float, id: String, config: Dictionary) -> String:
	return "t=%.1f REFUS (tranchant) : %s -- son outil est sous le seuil %.2f, il ne coupe rien" % [t, id, float(config.seuil_tranchant)]

static func ligne_refus_marge(t: float, entree: Dictionary) -> String:
	return "t=%.1f REFUS (marge) : %s n'entame pas %s -- %.1f s de travail pour %.1f s d'autonomie" % [
		t, String(entree.colon_id), String(entree.cible_id), float(entree.necessaire), float(entree.dispo),
	]

static func ligne_humidite(t: float, humidite: float, cout: float) -> String:
	return "t=%.1f HUMIDITE : %.2f -- une entaille se degrade desormais a %.3f/s" % [t, humidite, cout]

static func ligne_coucher(t: float, colon: Dictionary, config: Dictionary) -> String:
	return "t=%.1f EPUISE DE FORCE : %s tombe a %.1f de sommeil -- il va lacher son chantier, qui s'entaillera" % [
		t, String(colon.id), _reserve(colon, String(config.nom_reserve_sommeil)),
	]

static func ligne_trace(t: float, colons: Array, arbres: Array, monde, config: Dictionary, masse_perdue: float, reference: float, compteurs: Dictionary) -> String:
	var texte := "t=%.1f | %s" % [t, texte_total(monde, config, masse_perdue, reference, compteurs)]
	for colon in colons:
		texte += "\n   %s sommeil=%.1f cible=%s%s" % [
			String(colon.id), _reserve(colon, String(config.nom_reserve_sommeil)),
			String(colon.cible_id) if String(colon.cible_id) != "" else "-",
			" COUPE" if bool(colon.get("coupe", false)) else "",
		]
	for arbre in arbres:
		texte += "\n   %s travail=%.2f fraicheur=%.2f%s" % [
			String(arbre.id), float(arbre.proprietes.get("travail_restant", 0.0)),
			_reserve(arbre, String(config.nom_reserve_fraicheur)),
			" ENTAILLE" if arbre.proprietes.get("etats_actifs", []).has(String(config.nom_etat_entaille)) else "",
		]
	return texte

# ---------------------------------------------------------------------------
# Rendu (impur, Node) -- aucune decision, seulement des noeuds et une camera.
# ---------------------------------------------------------------------------

func _draw() -> void:
	var fond: Array = _config.couleur_fond
	draw_rect(Rect2(Vector2.ZERO, Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur))),
		Color(float(fond[0]), float(fond[1]), float(fond[2])))

func _construire_rendu() -> void:
	for arbre in _arbres:
		_creer_carre(String(arbre.id), float(_config.taille_arbre), _couleur(_config.couleur_arbre))
		_creer_barre(String(arbre.id) + "_travail", _couleur(_config.couleur_barre_travail))
	_creer_carre(String(_lit.id), float(_config.taille_lit), _couleur(_config.couleur_lit))
	for colon in _colons:
		_creer_carre(String(colon.id), float(_config.taille_colon), _couleur(_config.couleur_colon))
		_creer_barre(String(colon.id) + "_sommeil", _couleur(_config.couleur_barre_sommeil))
		var outil := ColorRect.new()
		outil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outil.size = Vector2(float(_config.taille_outil), float(_config.taille_outil))
		add_child(outil)
		_noeuds_outil[String(colon.id)] = outil

	var couche := CanvasLayer.new()
	add_child(couche)
	_label_total = _creer_label(17)
	_label_total.position = Vector2(10.0, 8.0)
	couche.add_child(_label_total)
	_label_aide = _creer_label(13)
	_label_aide.position = Vector2(10.0, 34.0)
	_label_aide.text = "clic gauche : basculer l'humidite locale (une entaille se degrade plus vite sous la pluie)   |   clic droit sur un colon : l'epuiser -- il lache son chantier, qui s'entaille"
	couche.add_child(_label_aide)

	var camera := Camera2D.new()
	camera.position = Vector2(float(_config.terrain_largeur), float(_config.terrain_hauteur)) / 2.0
	camera.zoom = Vector2(0.62, 0.62)
	camera.enabled = true
	add_child(camera)

func _creer_carre(id: String, taille: float, couleur: Color) -> void:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	carre.color = couleur
	add_child(carre)
	_noeuds[id] = carre
	var label := _creer_label(13)
	add_child(label)
	_labels[id] = label

func _creer_barre(cle: String, couleur: Color) -> void:
	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.size = Vector2(float(_config.largeur_barre), float(_config.hauteur_barre))
	fond.color = _couleur(_config.couleur_barre_fond)
	add_child(fond)
	_barres_fond[cle] = fond
	var rempli := ColorRect.new()
	rempli.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rempli.size = Vector2(0.0, float(_config.hauteur_barre))
	rempli.color = couleur
	add_child(rempli)
	_barres[cle] = rempli

func _creer_rendu_produit(produit: Dictionary) -> void:
	var cle_couleur := "couleur_produit_%s" % String(produit.proprietes.get("issue_coupe", "eclats"))
	_creer_carre(String(produit.id), float(_config.taille_produit), _couleur(_config.get(cle_couleur, _config.couleur_produit_eclats)))

func _creer_label(taille: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", taille)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _couleur(rgb) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))

func _rafraichir(bilan: Dictionary) -> void:
	for arbre in _arbres:
		var id: String = String(arbre.id)
		var restant: float = float(arbre.proprietes.get("travail_restant", 0.0))
		var initial: float = float(arbre.proprietes.get("travail_initial", 1.0))
		var entaille: bool = arbre.proprietes.get("etats_actifs", []).has(String(_config.nom_etat_entaille))
		var teinte: Array = _config.couleur_arbre
		if restant <= 0.0:
			teinte = _config.couleur_arbre_filtre
		elif entaille:
			teinte = _config.couleur_arbre_entaille
		_placer(id, arbre.position, _couleur(teinte), texte_arbre(arbre, _config))
		_regler_barre(id + "_travail", arbre.position, 1.0 - (restant / initial if initial > 0.0 else 0.0), 34.0)

	_placer(String(_lit.id), _lit.position, _couleur(_config.couleur_lit), "lit\n(repos)")

	for colon in _colons:
		var id: String = String(colon.id)
		var actifs: Array = colon.proprietes.get("etats_actifs", [])
		var teinte: Array = _config.couleur_colon
		if actifs.has(String(_config.nom_etat_repose)):
			teinte = _config.couleur_colon_dort
		elif actifs.has(String(_config.nom_etat_epuise)):
			teinte = _config.couleur_colon_epuise
		_placer(id, colon.position, _couleur(teinte), texte_colon(colon, _outils, _config, _etats))
		_regler_barre(id + "_sommeil", colon.position,
			_reserve(colon, String(_config.nom_reserve_sommeil)) / float(_config.capacite_sommeil), 26.0)

		var outil: Dictionary = _outils.get(id, {})
		var noeud: ColorRect = _noeuds_outil[id]
		noeud.position = Vector2(colon.position.x, colon.position.y) + Vector2(float(_config.taille_colon) * 0.6, -float(_config.taille_colon) * 0.6)
		# COULEUR DE L'OUTIL : vert s'il entame CE QU'IL VISE, rouge sinon. Le
		# gate est evalue contre le premier arbre encore debout -- jamais un
		# seuil recopie ici, toujours peut_couper(), la meme fonction que celle
		# qui filtre les agents.
		var reference := _arbre_de_reference()
		noeud.color = _couleur(_config.couleur_outil_coupe) if (not reference.is_empty() and peut_couper(outil, reference, _config)) else _couleur(_config.couleur_outil_emousse)

	for id in _noeuds:
		if _labels.has(id) and not _barres.has(id + "_travail") and not _barres.has(id + "_sommeil"):
			var entree = _monde.choses.get(id)
			if entree != null:
				_placer(id, entree.chose.position, _noeuds[id].color, "%s\n%.1f kg" % [id, _reserve(entree.chose, String(_config.nom_reserve_matiere))])

	_label_total.text = texte_total(_monde, _config, _masse_perdue, _masse_reference, _compteurs_issue)

func _arbre_de_reference() -> Dictionary:
	for arbre in _arbres:
		if float(arbre.proprietes.get("travail_restant", 0.0)) > 0.0:
			return arbre
	return _arbres[0] if not _arbres.is_empty() else {}

func _placer(id: String, position: Vector3, couleur: Color, texte: String) -> void:
	if not _noeuds.has(id):
		return
	var carre: ColorRect = _noeuds[id]
	carre.position = Vector2(position.x, position.y) - carre.size / 2.0
	carre.color = couleur
	var label: Label = _labels[id]
	label.position = carre.position + Vector2(0.0, carre.size.y + 12.0)
	label.text = texte

func _regler_barre(cle: String, position: Vector3, ratio: float, decalage: float) -> void:
	if not _barres.has(cle):
		return
	var origine := Vector2(position.x - float(_config.largeur_barre) / 2.0, position.y + decalage)
	_barres_fond[cle].position = origine
	_barres[cle].position = origine
	_barres[cle].size = Vector2(float(_config.largeur_barre) * clamp(ratio, 0.0, 1.0), float(_config.hauteur_barre))

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
