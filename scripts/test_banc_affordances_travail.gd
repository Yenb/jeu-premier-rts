extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_affordances_travail.gd
#
# Verrouille le cablage de banc_affordances_travail.gd -- chantier
# « travail + coupe + resultat », lignes 1/2/3/4/5/6/10 du tableau Affordances
# (audit_affordances_prealable.md). Les onze mecanismes du coeur qu'il compose
# restent INCHANGES : ce fichier ne verrouille que du cablage.
#
# TROIS FAMILLES DE CAS, a ne pas confondre :
# - MECANIQUE : une fonction pure isolee sur des nombres choisis (gate de
#   tranchant, penalite, biais d'issue, marge) ;
# - CHEMIN REEL : data/banc_affordances_travail.json rejoue EN ENTIER, avec les
#   vrais catalogues du disque -- sans eux, tout ce fichier resterait VERT
#   alors que le banc lance a l'ecran ne montrerait rien (c'est exactement le
#   trou qui avait laisse passer la calibration morte de banc_maladie, voir
#   docs/ETAT.md) ;
# - HORS DOMAINE integral : des tailleurs de cristal sur une planete sans
#   arbres, catalogues et NOMS DE PROPRIETE entierement inventes ici. C'est lui
#   qui prouve que le cablage ne connait ni arbre, ni bucheron, ni sommeil.
#
# CE QUI EST VERROUILLE A L'ENVERS, et c'est le plus important : chaque refus
# est verrouille DANS LES DEUX SENS (sous le seuil il refuse, au-dessus il
# accepte) et chaque issue de bifurcation est verrouillee comme ATTEIGNABLE --
# une sortie declaree qui ne gagnerait jamais serait morte en donnee sans
# qu'aucun test ne rougisse.

const Banc = preload("res://scripts/banc_affordances_travail.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const Dominance = preload("res://scripts/dominance.gd")
const Somme = preload("res://scripts/somme.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DELTA := 0.1
# Tolerance de comparaison de masses : la chaine passe par une division
# (volume = masse/densite) puis une multiplication (masse = densite*volume)
# dans objet.gd -- l'egalite BINAIRE n'est pas garantie, l'egalite a 1e-6 pres
# l'est largement sur les ordres de grandeur de ce banc (~900 kg).
const EPS := 1e-6

var _config: Dictionary
var _catalogues: Dictionary
var _etats: Dictionary
var _engagements: Dictionary

func _init() -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_affordances_travail.json"))
	_catalogues = {
		"types": JSON.parse_string(FileAccess.get_file_as_string("res://data/types.json")),
		"materiaux": JSON.parse_string(FileAccess.get_file_as_string("res://data/materiaux.json")),
		"canaux": JSON.parse_string(FileAccess.get_file_as_string("res://data/canaux.json")),
		"transformations": JSON.parse_string(FileAccess.get_file_as_string("res://data/transformations.json")).get("transformations", {}),
		"proprietes_immuables": JSON.parse_string(FileAccess.get_file_as_string("res://data/proprietes_immuables_composition.json")).get("proprietes", []),
	}
	_etats = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	_engagements = JSON.parse_string(FileAccess.get_file_as_string("res://data/engagements.json"))

	_sous_le_seuil_de_tranchant_aucune_coupe()
	_au_dessus_du_seuil_la_coupe_a_bien_lieu()
	_le_travail_descend_proportionnellement_au_rythme()
	_un_second_colon_reprend_sans_reinitialiser()
	_le_colon_dort_quand_la_reserve_passe_sous_le_seuil()
	_le_colon_se_reveille_quand_la_reserve_remonte()
	_l_entaille_est_posee_a_l_abandon()
	_l_entaille_se_degrade_et_le_travail_est_perdu()
	_l_entaille_se_referme_quand_le_travail_reprend()
	_coucher_de_force_arrache_le_colon_a_son_chantier()
	_la_marge_de_securite_refuse_quand_le_temps_manque()
	_la_marge_laisse_passer_quand_le_temps_suffit()
	_la_bifurcation_tranche_entre_les_trois_issues()
	_les_trois_produits_existent_dans_le_monde()
	_le_bilan_de_masse_est_constant_sur_le_cycle_reel()
	_hors_domaine_des_tailleurs_de_cristal()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_affordances_travail.gd -- gate de tranchant qui REFUSE (jamais " +
		"un rendement nul), travail porte par la cible et consomme au rythme des " +
		"agents, reprise par un second colon sans reinitialisation, sommeil ferme " +
		"par couplage.gd (sens_satisfaction 'sur_seuil') et recharge par flux.gd, " +
		"entaille posee a l'abandon puis degradee par depense.gd jusqu'a la perte " +
		"du chantier, marge de securite qui RETIRE une entree de resultats avant " +
		"dominance.gd, et bifurcation.gd qui tranche les TROIS issues, chacune " +
		"atteignable et produisant son objet -- sans qu'aucun mecanisme du coeur " +
		"ne soit touche")
	quit(0)

# ---- Fixtures ---------------------------------------------------------------

# Monte la scene REELLE du disque : colons, outils, arbres et lit de
# data/banc_affordances_travail.json, dans un vrai Monde.
func _scene_reelle() -> Dictionary:
	return _scene_depuis(_config, _catalogues)

func _scene_depuis(config: Dictionary, catalogues: Dictionary) -> Dictionary:
	var colons := Banc.construire_colons(config)
	var outils := Banc.construire_outils(config, catalogues)
	var arbres := Banc.construire_arbres(config, catalogues)
	var lit := Banc.construire_lit(config, catalogues)
	var monde = Monde.new()
	for colon in colons:
		monde.ajouter(colon, "colon", colon.position)
	for arbre in arbres:
		monde.ajouter(arbre, "arbre", arbre.position)
	for id in outils:
		monde.ajouter(outils[id], "outil", outils[id].position)
	monde.ajouter(lit, "lit", lit.position)
	return {"colons": colons, "outils": outils, "arbres": arbres, "lit": lit, "monde": monde}

func _par_id(objets: Array, id: String) -> Dictionary:
	for objet in objets:
		if String(objet.id) == id:
			return objet
	return {}

func _reserve(objet: Dictionary, nom: String) -> float:
	return float(objet.proprietes.get("reserves", {}).get(nom, {}).get("reserve", 0.0))

func _sommeil(colon: Dictionary, config: Dictionary) -> float:
	return _reserve(colon, String(config.nom_reserve_sommeil))

func _regler_sommeil(colon: Dictionary, config: Dictionary, valeur: float) -> void:
	colon.proprietes.reserves[String(config.nom_reserve_sommeil)]["reserve"] = valeur
	colon.proprietes[String(config.nom_miroir_manque)] = float(config.capacite_sommeil) - valeur

# Colle un colon sur son chantier pour que la portee_travail soit satisfaite
# sans avoir a le faire marcher pendant des dizaines de ticks.
func _poser_sur(colon: Dictionary, cible: Dictionary) -> void:
	colon.position = cible.position

func _avancer_n(scene: Dictionary, n: int, config: Dictionary, catalogues: Dictionary) -> Dictionary:
	var compteur := 0
	var perdue := 0.0
	var abattages: Array = []
	var entailles: Array = []
	var cicatrises: Array = []
	var sommeil: Array = []
	for i in range(n):
		var bilan := Banc.avancer(scene.colons, scene.outils, scene.arbres, scene.lit, scene.monde,
			compteur, DELTA, config, catalogues, _etats, _engagements)
		compteur = int(bilan.compteur_produit)
		perdue += float(bilan.masse_perdue)
		for a in bilan.abattages:
			abattages.append(a)
		for id in bilan.entailles_posees:
			entailles.append(id)
		for id in bilan.cicatrises:
			cicatrises.append(id)
		for e in bilan.sommeil:
			sommeil.append(e)
	return {"compteur": compteur, "masse_perdue": perdue, "abattages": abattages,
		"entailles": entailles, "cicatrises": cicatrises, "sommeil": sommeil}

func _portee_travail(config: Dictionary, catalogues: Dictionary) -> float:
	return float(catalogues.transformations.get(String(config.transformation_chantier), {}).get("portee_travail", 0.0))

# ---- LIGNE 1 : ce qui coupe peut couper -------------------------------------

# LE GATE EST UN REFUS, PAS UN RENDEMENT NUL : le porteur d'outil en bois n'est
# meme pas dans la liste d'agents, donc le travail ne bouge PAS D'UN CHIFFRE --
# ce qu'un rendement nul ne prouverait pas (un agent a rythme 0.0 laisserait
# aussi le travail intact, mais serait quand meme compte comme present).
func _sous_le_seuil_de_tranchant_aucune_coupe() -> void:
	var scene := _scene_reelle()
	var manoeuvre := _par_id(scene.colons, "manoeuvre")
	var arbre: Dictionary = scene.arbres[0]
	var outil: Dictionary = scene.outils["manoeuvre"]

	var ratio := Banc.degat_coupe(
		float(outil.proprietes[String(_config.propriete_tranchant_effectif)]),
		float(arbre.proprietes[String(_config.propriete_resistance)]))
	verif.v(ratio < float(_config.seuil_tranchant),
		"l'outil du manoeuvre doit etre SOUS le seuil (%.3f vs %.3f) -- sinon ce cas ne prouve rien" % [ratio, float(_config.seuil_tranchant)])
	verif.v(not Banc.peut_couper(outil, arbre, _config), "sous le seuil, peut_couper doit rendre faux")

	# Le colon est pose sur l'arbre ET declare le couper : seul le TRANCHANT peut
	# encore l'exclure. Sans ces deux lignes, la liste serait vide pour la
	# mauvaise raison (aucune decision prise) et ce cas ne prouverait rien.
	_poser_sur(manoeuvre, arbre)
	manoeuvre["coupe"] = true
	manoeuvre["cible_id"] = String(arbre.id)
	var agents := Banc.coupeurs_de(arbre, [manoeuvre], scene.outils, _portee_travail(_config, _catalogues), _config, _etats)
	verif.v(agents.is_empty(), "un colon qui ne peut pas couper n'entre PAS dans la liste d'agents")

	# Contre-epreuve immediate : le meme colon, au meme endroit, avec l'outil du
	# bucheron, entre bien dans la liste -- c'est l'OUTIL qui excluait.
	var prete: Dictionary = {"manoeuvre": scene.outils["bucheron"]}
	verif.v(Banc.coupeurs_de(arbre, [manoeuvre], prete, _portee_travail(_config, _catalogues), _config, _etats).size() == 1,
		"avec un outil au-dessus du seuil, le meme colon au meme endroit compte comme agent")

	var avant: float = float(arbre.proprietes.travail_restant)
	for i in range(50):
		Banc.avancer([manoeuvre], scene.outils, scene.arbres, scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	verif.v(float(arbre.proprietes.travail_restant) == avant,
		"colle sur l'arbre pendant 5 s avec un outil sous le seuil, le travail ne bouge pas d'un chiffre (%.6f)" % float(arbre.proprietes.travail_restant))

# VERROUILLAGE DANS L'AUTRE SENS : ce qui exclut le manoeuvre est bien le SEUIL,
# et rien d'autre. Meme colon, meme arbre, meme code -- seul l'outil change.
func _au_dessus_du_seuil_la_coupe_a_bien_lieu() -> void:
	var scene := _scene_reelle()
	var bucheron := _par_id(scene.colons, "bucheron")
	var arbre: Dictionary = scene.arbres[0]
	verif.v(Banc.peut_couper(scene.outils["bucheron"], arbre, _config), "l'outil en fer passe le seuil")

	_poser_sur(bucheron, arbre)
	var avant: float = float(arbre.proprietes.travail_restant)
	for i in range(10):
		Banc.avancer([bucheron], scene.outils, scene.arbres, scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	verif.v(float(arbre.proprietes.travail_restant) < avant, "au-dessus du seuil, le travail descend")

	# Et un seuil abaisse fait repasser le manoeuvre, sans qu'aucune autre
	# donnee ne bouge (patron banc_economie.gd:_le_seuil_abaisse_fait_repasser).
	var permissif := _config.duplicate(true)
	permissif["seuil_tranchant"] = 0.0
	verif.v(Banc.peut_couper(scene.outils["manoeuvre"], arbre, permissif),
		"seuil a 0.0 : le meme outil en bois passe -- c'est le SEUIL qui excluait, rien d'autre")

# ---- LIGNE 2 : un travail, pas un temps -------------------------------------

# Le travail vit sur la CIBLE et descend a la somme des rythmes des agents a
# portee : deux colons de rythmes differents ne consomment pas la meme quantite
# dans le meme temps, et le rapport est EXACTEMENT celui des rythmes.
func _le_travail_descend_proportionnellement_au_rythme() -> void:
	var lent := _scene_reelle()
	var rapide := _scene_reelle()
	var arbre_lent: Dictionary = lent.arbres[0]
	var arbre_rapide: Dictionary = rapide.arbres[0]
	var apprenti := _par_id(lent.colons, "apprenti")
	var bucheron := _par_id(rapide.colons, "bucheron")
	_regler_sommeil(apprenti, _config, float(_config.capacite_sommeil))
	_poser_sur(apprenti, arbre_lent)
	_poser_sur(bucheron, arbre_rapide)

	var depart: float = float(arbre_lent.proprietes.travail_restant)
	for i in range(10):
		Banc.avancer([apprenti], lent.outils, lent.arbres, lent.lit, lent.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
		Banc.avancer([bucheron], rapide.outils, rapide.arbres, rapide.lit, rapide.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)

	var consomme_lent: float = depart - float(arbre_lent.proprietes.travail_restant)
	var consomme_rapide: float = depart - float(arbre_rapide.proprietes.travail_restant)
	var rythme_lent := Banc.rythme_effectif(apprenti, _config, _etats)
	var rythme_rapide := Banc.rythme_effectif(bucheron, _config, _etats)
	verif.v(consomme_lent > 0.0 and consomme_rapide > 0.0, "les deux doivent avoir consomme quelque chose")
	verif.v(absf(consomme_rapide / consomme_lent - rythme_rapide / rythme_lent) < 1e-4,
		"le travail consomme suit EXACTEMENT le rapport des rythmes (%.4f vs %.4f)" % [consomme_rapide / consomme_lent, rythme_rapide / rythme_lent])

	# Et travail_initial ne bouge JAMAIS -- c'est la reference.
	verif.v(float(arbre_lent.proprietes.travail_initial) == depart, "travail_initial ne bouge jamais")

# ---- LIGNE 4 : le chantier survit a l'ouvrier -------------------------------

# Le premier colon travaille puis PART ; un second arrive et reprend sur le
# travail_restant LAISSE, jamais sur un compte neuf. Aucune identite d'agent
# n'est memorisee nulle part -- c'est le seul modele possible, pas un drapeau.
func _un_second_colon_reprend_sans_reinitialiser() -> void:
	var scene := _scene_reelle()
	var arbre: Dictionary = scene.arbres[0]
	var bucheron := _par_id(scene.colons, "bucheron")
	var apprenti := _par_id(scene.colons, "apprenti")
	_regler_sommeil(apprenti, _config, float(_config.capacite_sommeil))
	var loin := Vector3(-5000.0, -5000.0, 0.0)
	apprenti.position = loin
	_poser_sur(bucheron, arbre)

	for i in range(10):
		Banc.avancer(scene.colons, scene.outils, scene.arbres, scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	var apres_premier: float = float(arbre.proprietes.travail_restant)
	verif.v(apres_premier < float(arbre.proprietes.travail_initial), "le premier colon doit avoir entame le chantier")

	# Le premier part, personne ne travaille : le travail ne remonte pas.
	bucheron.position = loin
	Banc.avancer(scene.colons, scene.outils, scene.arbres, scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	verif.v(float(arbre.proprietes.travail_restant) == apres_premier,
		"l'ouvrier parti, le travail deja fourni reste EXACTEMENT la (%.4f)" % float(arbre.proprietes.travail_restant))

	# Le second arrive et reprend d'ou l'autre s'est arrete.
	_poser_sur(apprenti, arbre)
	Banc.avancer(scene.colons, scene.outils, scene.arbres, scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	var apres_second: float = float(arbre.proprietes.travail_restant)
	verif.v(apres_second < apres_premier, "le second colon reprend le chantier (%.4f -> %.4f)" % [apres_premier, apres_second])
	verif.v(apres_second < float(arbre.proprietes.travail_initial),
		"et il reprend SUR LE RESTANT, jamais sur un chantier reinitialise")

	# Deux ensemble consomment la SOMME des deux rythmes -- c'est litteralement
	# ce qu'extinction.gd fait, et il n'y a rien a cabler pour l'obtenir.
	var avant_duo: float = apres_second
	_poser_sur(bucheron, arbre)
	Banc.avancer(scene.colons, scene.outils, scene.arbres, scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	var consomme_duo: float = avant_duo - float(arbre.proprietes.travail_restant)
	var somme_rythmes := Banc.rythme_effectif(bucheron, _config, _etats) + Banc.rythme_effectif(apprenti, _config, _etats)
	verif.v(absf(consomme_duo - somme_rythmes * DELTA) < 1e-5,
		"a deux, le chantier avance de la SOMME des rythmes (%.5f vs %.5f)" % [consomme_duo, somme_rythmes * DELTA])

# ---- LIGNE 3 : dormir jusqu'a etre repose -----------------------------------

func _le_colon_dort_quand_la_reserve_passe_sous_le_seuil() -> void:
	var scene := _scene_reelle()
	var colon := _par_id(scene.colons, "bucheron")
	var seuil_bascule: float = float(_engagements[String(_config.regle_engagement_dormir)].seuil_bascule)

	# AU-DESSUS du seuil : aucun engagement, verrouille dans ce sens d'abord.
	_regler_sommeil(colon, _config, seuil_bascule + 10.0)
	Banc.avancer([colon], scene.outils, scene.arbres, scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	verif.v(colon.proprietes.engagement == null, "au-dessus du seuil de bascule, aucun engagement de sommeil")

	# SOUS le seuil : l'engagement se pose sur le LIT, avec le jeton de canal.
	_regler_sommeil(colon, _config, seuil_bascule - 1.0)
	Banc.avancer([colon], scene.outils, scene.arbres, scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	var engagement = colon.proprietes.engagement
	verif.v(engagement != null, "sous le seuil de bascule, l'engagement de sommeil est pose")
	if engagement == null:
		return
	verif.v(String(engagement.cible_id) == String(scene.lit.id), "l'engagement vise le LIT, jamais un chantier")
	verif.v(String(engagement.get("canal", "")) == String(_config.canal_engagement),
		"le jeton de contexte est bien pose -- c'est lui qui resout 'reserves.{canal}.reserve'")
	verif.v(String(engagement.sens_satisfaction) == "sur_seuil",
		"sens_satisfaction 'sur_seuil' : la satisfaction vient d'une reserve qui MONTE, jamais d'un seuil_etat.gd")

	# Il se met en route vers le lit, et ne dort qu'une fois ARRIVE : flux.gd
	# est un transfert A PORTEE, la geometrie fait le travail.
	var distance_avant: float = colon.position.distance_to(scene.lit.position)
	Banc.avancer([colon], scene.outils, scene.arbres, scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	verif.v(colon.position.distance_to(scene.lit.position) < distance_avant, "le colon engage marche VERS le lit")
	verif.v(not colon.proprietes.get("etats_actifs", []).has(String(_config.nom_etat_repose)),
		"loin du lit, il n'est pas encore 'repose' -- et ne recupere donc rien")

	var reserve_loin := _sommeil(colon, _config)
	Banc.avancer([colon], scene.outils, scene.arbres, scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	verif.v(_sommeil(colon, _config) < reserve_loin, "en marchant vers le lit, il continue de fatiguer")

func _le_colon_se_reveille_quand_la_reserve_remonte() -> void:
	var scene := _scene_reelle()
	var colon := _par_id(scene.colons, "bucheron")
	var seuil_bascule: float = float(_engagements[String(_config.regle_engagement_dormir)].seuil_bascule)
	var seuil_satisfait: float = float(_engagements[String(_config.regle_engagement_dormir)].seuil_satisfait)

	_regler_sommeil(colon, _config, seuil_bascule - 1.0)
	colon.position = scene.lit.position
	var suite := _avancer_n({"colons": [colon], "outils": scene.outils, "arbres": scene.arbres,
		"lit": scene.lit, "monde": scene.monde}, 3, _config, _catalogues)
	verif.v(colon.proprietes.get("etats_actifs", []).has(String(_config.nom_etat_repose)),
		"pose au lit et engage, il s'endort")
	verif.v(bool(colon.proprietes.get(String(_config.propriete_recoit_repos), false)),
		"la propriete RECEPTRICE de flux.gd est posee -- c'est elle, et rien d'autre, qui le fait recuperer")

	var bas := _sommeil(colon, _config)
	_avancer_n({"colons": [colon], "outils": scene.outils, "arbres": scene.arbres,
		"lit": scene.lit, "monde": scene.monde}, 5, _config, _catalogues)
	verif.v(_sommeil(colon, _config) > bas, "au lit, flux.gd fait REMONTER la reserve (%.2f -> %.2f)" % [bas, _sommeil(colon, _config)])

	# ... jusqu'au reveil, decide par couplage.gd et par lui seul. La reserve est
	# capturee A L'INSTANT du relachement, jamais apres N ticks fixes : une fois
	# reveille, le colon repart travailler et refatigue -- lire plus tard
	# mesurerait sa journee, pas son reveil.
	var reserve_au_reveil := -1.0
	for i in range(400):
		var bilan := Banc.avancer([colon], scene.outils, scene.arbres, scene.lit, scene.monde,
			0, DELTA, _config, _catalogues, _etats, _engagements)
		for evenement in bilan.sommeil:
			if String(evenement.quoi) == "reveil":
				reserve_au_reveil = float(evenement.reserve)
		if reserve_au_reveil >= 0.0:
			break
	verif.v(reserve_au_reveil >= 0.0, "le colon doit finir par se reveiller")
	verif.v(colon.proprietes.engagement == null, "la reserve remontee, couplage.gd relache l'engagement")
	verif.v(not colon.proprietes.get("etats_actifs", []).has(String(_config.nom_etat_repose)),
		"et le cablage retire l'etat 'repose' au meme geste")
	verif.v(not colon.proprietes.get(String(_config.propriete_recoit_repos), false),
		"la propriete receptrice de flux.gd est retiree : il cesse de recuperer par la seule donnee")
	verif.v(reserve_au_reveil >= seuil_satisfait,
		"il ne se reveille qu'AU-DESSUS de seuil_satisfait (%.1f >= %.1f)" % [reserve_au_reveil, seuil_satisfait])
	verif.v(reserve_au_reveil <= float(_config.capacite_sommeil) + EPS,
		"et jamais au-dessus de la capacite -- le plafond est du cablage, rien dans le coeur ne borne le haut")

# ---- LIGNE 5 : un travail interrompu laisse une blessure --------------------

func _l_entaille_est_posee_a_l_abandon() -> void:
	var scene := _scene_reelle()
	var arbre: Dictionary = scene.arbres[0]
	var colon := _par_id(scene.colons, "bucheron")
	_poser_sur(colon, arbre)

	for i in range(10):
		Banc.avancer([colon], scene.outils, [arbre], scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	verif.v(not arbre.proprietes.get("etats_actifs", []).has(String(_config.nom_etat_entaille)),
		"tant qu'on y travaille, AUCUNE entaille -- un chantier en cours n'est pas un chantier abandonne")

	colon.position = Vector3(-5000.0, -5000.0, 0.0)
	var bilan := Banc.avancer([colon], scene.outils, [arbre], scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	verif.v(bilan.entailles_posees.has(String(arbre.id)), "l'ouvrier parti, l'entaille est posee")
	verif.v(arbre.proprietes.get("etats_actifs", []).has(String(_config.nom_etat_entaille)),
		"et l'etat est bien actif sur l'arbre")
	verif.v(float(arbre.proprietes.get("etats_intensite", {}).get(String(_config.nom_etat_entaille), 0.0)) > 0.0,
		"avec une intensite suivie par etat_duree.gd -- c'est elle qui la fera se refermer")

	# Un arbre INTACT n'a jamais d'entaille : c'est bien l'abandon EN COURS DE
	# ROUTE qui la pose, pas la seule absence d'ouvrier.
	var intact: Dictionary = scene.arbres[1]
	verif.v(not intact.proprietes.get("etats_actifs", []).has(String(_config.nom_etat_entaille)),
		"un arbre jamais entame ne porte aucune entaille")

func _l_entaille_se_degrade_et_le_travail_est_perdu() -> void:
	var scene := _scene_reelle()
	var arbre: Dictionary = scene.arbres[0]
	var colon := _par_id(scene.colons, "bucheron")
	_poser_sur(colon, arbre)
	for i in range(10):
		Banc.avancer([colon], scene.outils, [arbre], scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	var entame: float = float(arbre.proprietes.travail_restant)
	colon.position = Vector3(-5000.0, -5000.0, 0.0)

	# La reserve ne descend QUE parce que l'etat la degate (patron
	# banc_corrosion.gd) : verrouille en mesurant le cout_base pose.
	var fraicheur_pleine := _reserve(arbre, String(_config.nom_reserve_fraicheur))
	Banc.avancer([colon], scene.outils, [arbre], scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	Banc.avancer([colon], scene.outils, [arbre], scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	verif.v(_reserve(arbre, String(_config.nom_reserve_fraicheur)) < fraicheur_pleine,
		"une fois l'entaille active, depense.gd degrade la fraicheur")
	verif.v(absf(float(arbre.proprietes.reserves[String(_config.nom_reserve_fraicheur)].cout_base) - Banc.cout_entaille_effectif(_config)) < EPS,
		"le cout_base pose est EXACTEMENT degradation_base * (1 + sensibilite * humidite)")

	# L'humidite module bien ce cout -- verrouille dans les deux sens.
	var sec := _config.duplicate(true)
	sec[String(_config.propriete_humidite)] = 0.0
	verif.v(Banc.cout_entaille_effectif(sec) < Banc.cout_entaille_effectif(_config),
		"a sec, une entaille se degrade moins vite (%.4f vs %.4f)" % [Banc.cout_entaille_effectif(sec), Banc.cout_entaille_effectif(_config)])
	verif.v(absf(Banc.cout_entaille_effectif(sec) - float(_config.degradation_entaille_base)) < EPS,
		"a humidite nulle, le cout retombe EXACTEMENT sur la degradation de base")

	# Puis le chantier est PERDU : travail_restant remonte a travail_initial.
	var suite := _avancer_n({"colons": [colon], "outils": scene.outils, "arbres": [arbre],
		"lit": scene.lit, "monde": scene.monde}, 400, _config, _catalogues)
	verif.v(suite.cicatrises.has(String(arbre.id)), "la fraicheur epuisee, l'arbre cicatrise")
	verif.v(float(arbre.proprietes.travail_restant) == float(arbre.proprietes.travail_initial),
		"et TOUT le travail deja fourni est perdu (%.2f, entame a %.2f)" % [float(arbre.proprietes.travail_restant), entame])
	verif.v(not arbre.proprietes.get("etats_actifs", []).has(String(_config.nom_etat_entaille)),
		"l'entaille est retiree au meme geste, sinon l'arbre cicatriserait en boucle")
	verif.v(suite.cicatrises.size() == 1, "et il ne cicatrise QU'UNE FOIS (%d)" % suite.cicatrises.size())

func _l_entaille_se_referme_quand_le_travail_reprend() -> void:
	var scene := _scene_reelle()
	var arbre: Dictionary = scene.arbres[0]
	var colon := _par_id(scene.colons, "bucheron")
	_poser_sur(colon, arbre)
	for i in range(10):
		Banc.avancer([colon], scene.outils, [arbre], scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	colon.position = Vector3(-5000.0, -5000.0, 0.0)
	for i in range(10):
		Banc.avancer([colon], scene.outils, [arbre], scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	verif.v(arbre.proprietes.get("etats_actifs", []).has(String(_config.nom_etat_entaille)), "l'entaille est bien la")

	# Le colon revient : plus personne ne repose l'etat, son intensite s'epuise
	# seule et etat_duree.gd le retire -- aucune branche « refermer l'entaille ».
	_poser_sur(colon, arbre)
	var duree: float = float(_etats[String(_config.nom_etat_entaille)].duree)
	for i in range(int(duree / DELTA) + 5):
		Banc.avancer([colon], scene.outils, [arbre], scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	verif.v(not arbre.proprietes.get("etats_actifs", []).has(String(_config.nom_etat_entaille)),
		"le travail repris, l'entaille se referme d'elle-meme (etat_duree.gd, aucune branche de cablage)")

# LE SEUL GESTE QUI ARRACHE UN COLON A SON CHANTIER, et la raison pour laquelle
# il existe : la marge de securite rend l'abandon spontane STRUCTURELLEMENT
# impossible -- une fois le chantier entame, le travail restant baisse de
# `rythme` par seconde tandis que l'autonomie ne baisse que d'une seconde par
# seconde, la condition ne peut donc que s'ameliorer. C'est verrouille ici comme
# une PROPRIETE (et non constate comme un manque) : sans le clic, la scene ne
# montrerait JAMAIS l'entaille de la ligne 5.
func _coucher_de_force_arrache_le_colon_a_son_chantier() -> void:
	var scene := _scene_reelle()
	var arbre: Dictionary = scene.arbres[0]
	var colon := _par_id(scene.colons, "bucheron")
	_poser_sur(colon, arbre)

	# La marge ne se degrade JAMAIS une fois le chantier entame -- mesure sur le
	# chemin reel, c'est ce qui rend le geste exterieur necessaire.
	var pire_ecart := -INF
	for i in range(20):
		Banc.avancer([colon], scene.outils, [arbre], scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
		var rythme := Banc.rythme_effectif(colon, _config, _etats)
		pire_ecart = max(pire_ecart, Banc.temps_necessaire(arbre, rythme) * float(_config.marge_securite) - Banc.temps_restant(colon, _config))
	verif.v(pire_ecart < 0.0,
		"la marge ne se degrade jamais en cours de chantier (pire ecart %.3f) -- l'abandon spontane est impossible" % pire_ecart)
	verif.v(bool(colon.get("coupe", false)), "et le colon coupe toujours")

	# Le geste exterieur agit sur la GRANDEUR, jamais sur la decision -- et tout
	# le reste suit par le chemin NORMAL, sans un cas particulier. Poser
	# l'engagement directement a ete essaye et NE MARCHE PAS (resultat negatif
	# ecrit dans epuiser_de_force) : sens_satisfaction 'sur_seuil' declare
	# satisfait un colon deja repose, couplage.gd relachait au tick suivant.
	var seuil_bascule: float = float(_engagements[String(_config.regle_engagement_dormir)].seuil_bascule)
	verif.v(Banc.epuiser_de_force(colon, _config, _engagements), "l'epuisement force doit prendre")
	verif.v(_sommeil(colon, _config) < seuil_bascule, "la reserve tombe sous le seuil de bascule")
	verif.v(colon.proprietes.engagement == null, "aucun engagement n'est pose A LA MAIN : c'est le tick qui le fera")

	var bilan := Banc.avancer([colon], scene.outils, [arbre], scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	verif.v(colon.proprietes.engagement != null, "au tick suivant, couplage.gd pose l'engagement de sommeil")
	verif.v(not bool(colon.get("coupe", false)), "et le colon a lache son chantier")
	verif.v(bilan.entailles_posees.has(String(arbre.id)), "le chantier lache s'entaille au meme tick")
	verif.v(not Banc.epuiser_de_force(colon, _config, _engagements),
		"un colon deja engage ne se re-epuise pas -- rien a forcer")

	# Et il repart bien dormir, puis revient : le cycle entier tient sur le seul
	# changement de grandeur.
	var suite := _avancer_n({"colons": [colon], "outils": scene.outils, "arbres": [arbre],
		"lit": scene.lit, "monde": scene.monde}, 300, _config, _catalogues)
	var quoi: Array = []
	for evenement in suite.sommeil:
		quoi.append(String(evenement.quoi))
	verif.v(quoi.has("endormi") and quoi.has("reveil"),
		"le colon epuise s'endort puis se reveille par le cycle normal (%s)" % str(quoi))

# ---- LIGNE 6 : le chirurgien fatigue n'ouvre pas ----------------------------

func _la_marge_de_securite_refuse_quand_le_temps_manque() -> void:
	var scene := _scene_reelle()
	var colon := _par_id(scene.colons, "bucheron")
	var arbre: Dictionary = scene.arbres[0]
	var outil: Dictionary = scene.outils["bucheron"]
	_poser_sur(colon, arbre)

	# Juste assez de sommeil pour tenir, pas assez pour la marge.
	var rythme := Banc.rythme_effectif(colon, _config, _etats)
	var necessaire := Banc.temps_necessaire(arbre, rythme)
	var cout := Banc.cout_par_seconde(_config)
	_regler_sommeil(colon, _config, necessaire * cout * 1.05)
	verif.v(Banc.temps_restant(colon, _config) > necessaire,
		"il a de quoi finir SANS marge -- c'est bien la marge, et rien d'autre, qui va refuser")

	var perceptions := Perception.percevoir(colon, scene.monde, _catalogues.canaux)
	var bruts := Banc.resultats_depuis_perceptions(perceptions, _config)
	verif.v(bruts.size() > 0, "les chantiers doivent etre PERCUS : le filtre retire ce qui est vu, pas ce qui est invisible")

	var filtre := Banc.filtrer_marge(bruts, colon, outil, _config, _etats)
	verif.v(filtre.gardes.is_empty(), "sous la marge, TOUTES les entrees sont retirees de resultats")
	for entree in filtre.retires:
		verif.v(String(entree.motif) == "marge", "et le motif est bien la marge, pas le tranchant")
		verif.v(float(entree.necessaire) * float(_config.marge_securite) > float(entree.dispo),
			"la condition de refus est exactement temps_necessaire * marge > temps_restant")

	# Le retrait a lieu AVANT dominance.gd : le colon ne decide RIEN, meme seul
	# au monde avec un chantier sous les yeux -- ce qu'un seuil relatif
	# (dominance.gd) ne pourrait jamais produire.
	verif.v(Banc.choisir_cible(Dominance.visibles(filtre.gardes, colon)) == null,
		"aucune cible : le colon voit l'arbre et n'y va pas")

	var avant: float = float(arbre.proprietes.travail_restant)
	Banc.avancer([colon], scene.outils, [arbre], scene.lit, scene.monde, 0, DELTA, _config, _catalogues, _etats, _engagements)
	verif.v(float(arbre.proprietes.travail_restant) == avant, "et il n'entame rien du tout")
	# LE REFUS DOIT ALLER JUSQU'AUX AGENTS, sinon il serait vrai dans `resultats`
	# et faux dans le monde : un colon a portee travaillerait quand meme, du seul
	# fait d'etre la. Defaut REEL, mesure en test avant d'etre ferme.
	verif.v(not bool(colon.get("coupe", false)), "un colon qui a refuse ne se declare pas coupeur")
	verif.v(Banc.coupeurs_de(arbre, [colon], scene.outils, _portee_travail(_config, _catalogues), _config, _etats).is_empty(),
		"et n'entre donc PAS dans la liste d'agents passee a extinction.gd, malgre sa presence a portee")

func _la_marge_laisse_passer_quand_le_temps_suffit() -> void:
	var scene := _scene_reelle()
	var colon := _par_id(scene.colons, "bucheron")
	var arbre: Dictionary = scene.arbres[0]
	_regler_sommeil(colon, _config, float(_config.capacite_sommeil))
	var filtre := Banc.filtrer_marge(
		Banc.resultats_depuis_perceptions(Perception.percevoir(colon, scene.monde, _catalogues.canaux), _config),
		colon, scene.outils["bucheron"], _config, _etats)
	verif.v(not filtre.gardes.is_empty(), "a pleine reserve, les chantiers passent la marge")

	# Et la marge abaissee fait repasser un colon fatigue : c'est bien elle le
	# seul arbitre (patron banc_economie.gd:_le_seuil_abaisse_fait_repasser).
	var rythme := Banc.rythme_effectif(colon, _config, _etats)
	_regler_sommeil(colon, _config, Banc.temps_necessaire(arbre, rythme) * Banc.cout_par_seconde(_config) * 1.05)
	var permissive := _config.duplicate(true)
	permissive["marge_securite"] = 1.0
	var filtre_permissif := Banc.filtrer_marge(
		Banc.resultats_depuis_perceptions(Perception.percevoir(colon, scene.monde, _config_canaux_ok()), _config),
		colon, scene.outils["bucheron"], permissive, _etats)
	verif.v(not filtre_permissif.gardes.is_empty(),
		"marge a 1.0 : le meme colon dans le meme etat entame -- rien d'autre n'a bouge")

func _config_canaux_ok() -> Dictionary:
	return _catalogues.canaux

# ---- LIGNE 10 : rater produit autre chose -----------------------------------

# LES TROIS SORTIES SONT ATTEIGNABLES -- verrouillage indispensable : une sortie
# declaree qui ne gagnerait JAMAIS serait morte en donnee sans qu'aucun test ne
# rougisse (c'est le cas que base_debris 1.6 existe pour eviter, voir
# data/banc_affordances_travail.json:_note_issues).
func _la_bifurcation_tranche_entre_les_trois_issues() -> void:
	var scene := _scene_reelle()
	var arbre: Dictionary = scene.arbres[0]

	var trois := {
		"reussite": {"colon": "bucheron", "sommeil": 100.0},
		"eclats": {"colon": "apprenti", "sommeil": 50.0},
		"debris": {"colon": "apprenti", "sommeil": 0.0},
	}
	var vues: Array = []
	for attendu in trois:
		var cas: Dictionary = trois[attendu]
		var colon := _par_id(scene.colons, String(cas.colon))
		_regler_sommeil(colon, _config, float(cas.sommeil))
		var biais := Banc.biais_issue(colon, scene.outils[String(cas.colon)], arbre, _config)
		var gagnante := _argmax(biais)
		verif.v(gagnante == String(attendu),
			"issue attendue '%s' pour %s a sommeil %.0f, obtenue '%s' (biais %s)" % [String(attendu), String(cas.colon), float(cas.sommeil), gagnante, str(biais)])
		if not vues.has(gagnante):
			vues.append(gagnante)
	verif.v(vues.size() == 3, "les TROIS sorties doivent etre atteignables, %d vue(s)" % vues.size())

	# La penalite est monotone : plus fatigue, plus penalise -- c'est elle, et
	# elle seule, qui compose les trois biais.
	var colon := _par_id(scene.colons, "bucheron")
	_regler_sommeil(colon, _config, 100.0)
	var frais := Banc.penalite(colon, scene.outils["bucheron"], arbre, _config)
	_regler_sommeil(colon, _config, 10.0)
	var use := Banc.penalite(colon, scene.outils["bucheron"], arbre, _config)
	verif.v(use > frais, "la penalite monte avec la fatigue (%.3f -> %.3f)" % [frais, use])

	# LA GRANDEUR NE CHANGE JAMAIS QUI GAGNE (limite ecrite dans l'en-tete de
	# bifurcation.gd) -- verrouille positivement, pour qu'un futur cablage ne
	# croie jamais l'inverse.
	_regler_sommeil(colon, _config, 100.0)
	var biais := Banc.biais_issue(colon, scene.outils["bucheron"], arbre, _config)
	var Bifurcation = load("res://scripts/bifurcation.gd")
	verif.v(Bifurcation.selectionner(0.01, biais, _config.issues.sorties) == Bifurcation.selectionner(1000.0, biais, _config.issues.sorties),
		"la grandeur est une echelle et un gate, jamais un arbitre : meme gagnant a 0.01 et a 1000.0")
	verif.v(Bifurcation.selectionner(0.0, biais, _config.issues.sorties) == "",
		"a grandeur nulle, RIEN ne bifurque -- le gate est arithmetique, jamais une branche")

func _argmax(biais: Dictionary) -> String:
	var meilleur := ""
	var score := 0.0
	for cle in biais:
		if float(biais[cle]) > score:
			score = float(biais[cle])
			meilleur = String(cle)
	return meilleur

# LES TROIS PRODUITS EXISTENT DANS LE MONDE : chaque issue fabrique un VRAI
# objet (Objet.fabriquer via Produit.transformer, puis Monde.ajouter), jamais
# une propriete posee sur l'arbre. Et le bilan de masse reste exact a chaque
# abattage -- ce que produit.gd perd, le cablage le COMPTE.
func _les_trois_produits_existent_dans_le_monde() -> void:
	var scene := _scene_reelle()
	var cas := [
		{"arbre": 0, "colon": "bucheron", "sommeil": 100.0, "issue": "reussite"},
		{"arbre": 1, "colon": "apprenti", "sommeil": 50.0, "issue": "eclats"},
		{"arbre": 2, "colon": "apprenti", "sommeil": 0.0, "issue": "debris"},
	]
	var reference := Banc.masse_dans_le_monde(scene.monde, _config)
	var perdue := 0.0
	var compteur := 0
	var issues_vues: Array = []

	for c in cas:
		var arbre: Dictionary = scene.arbres[int(c.arbre)]
		var colon := _par_id(scene.colons, String(c.colon))
		_regler_sommeil(colon, _config, float(c.sommeil))
		var masse_avant := _reserve(arbre, String(_config.nom_reserve_matiere))
		var abattage := Banc.abattre(arbre, colon, scene.outils[String(c.colon)], scene.monde, compteur, _config, _catalogues)
		verif.v(not abattage.is_empty(), "l'abattage de %s doit produire quelque chose" % String(arbre.id))
		if abattage.is_empty():
			continue
		compteur = int(abattage.compteur_produit)
		perdue += float(abattage.masse_perdue)
		issues_vues.append(String(abattage.issue))
		verif.v(String(abattage.issue) == String(c.issue),
			"issue attendue '%s' sur %s, obtenue '%s'" % [String(c.issue), String(arbre.id), String(abattage.issue)])

		var produit: Dictionary = abattage.produit
		verif.v(scene.monde.choses.has(String(produit.id)), "le produit '%s' doit EXISTER dans le Monde" % String(produit.id))
		verif.v(float(produit.proprietes.masse) > 0.0, "et porter une masse reelle, derivee par objet.gd")
		var rendement: float = float(_catalogues.transformations[String(_config.issues.refs[String(c.issue)])].a_zero.produire.rendement)
		verif.v(absf(float(produit.proprietes.masse) - masse_avant * rendement) < EPS,
			"le produit pese EXACTEMENT rendement x masse de l'arbre (%.6f)" % float(produit.proprietes.masse))
		verif.v(_reserve(arbre, String(_config.nom_reserve_matiere)) == 0.0,
			"et l'arbre devient une souche vide, sinon la matiere serait comptee deux fois")

		# LE BILAN, a chaque abattage : monde + perdu == reference.
		verif.v(absf(Banc.masse_dans_le_monde(scene.monde, _config) + perdue - reference) < EPS,
			"monde + perdu doit egaler la reference apres %s (ecart %.9f)" % [String(arbre.id), absf(Banc.masse_dans_le_monde(scene.monde, _config) + perdue - reference)])

	verif.v(issues_vues.size() == 3, "les trois abattages doivent avoir eu lieu")
	verif.v(perdue > 0.0, "et de la matiere doit REELLEMENT avoir ete perdue -- rater detruit, c'est le sujet de la ligne 10")

	# Les trois produits sont de types DIFFERENTS : trois issues, trois choses.
	var types_produits: Array = []
	for entree in scene.monde.choses.values():
		if String(entree.type) != "produit":
			continue
		var issue := String(entree.chose.proprietes.get("issue_coupe", ""))
		if not types_produits.has(issue):
			types_produits.append(issue)
	verif.v(types_produits.size() == 3, "trois produits distincts dans le monde, %d trouve(s)" % types_produits.size())

# ---- Le chemin REEL, de bout en bout ----------------------------------------

# Sans ce cas, tout ce fichier resterait VERT alors que la scene lancee a
# l'ecran ne montrerait rien. Il rejoue data/banc_affordances_travail.json EN
# ENTIER sur 120 s simulees, et verrouille l'invariant a CHAQUE tick.
func _le_bilan_de_masse_est_constant_sur_le_cycle_reel() -> void:
	var scene := _scene_reelle()
	var reference := Banc.masse_dans_le_monde(scene.monde, _config)
	verif.v(reference > 0.0, "la scene reelle doit porter de la matiere au depart")

	var compteur := 0
	var perdue := 0.0
	var pire_ecart := 0.0
	var abattages: Array = []
	var dodos: Array = []
	for i in range(1200):
		var bilan := Banc.avancer(scene.colons, scene.outils, scene.arbres, scene.lit, scene.monde,
			compteur, DELTA, _config, _catalogues, _etats, _engagements)
		compteur = int(bilan.compteur_produit)
		perdue += float(bilan.masse_perdue)
		for a in bilan.abattages:
			abattages.append(a)
		for e in bilan.sommeil:
			dodos.append(e)
		pire_ecart = max(pire_ecart, absf(Banc.masse_dans_le_monde(scene.monde, _config) + perdue - reference))

	verif.v(pire_ecart < EPS, "monde + perdu reste constant a CHAQUE tick du cycle reel (pire ecart %.9f)" % pire_ecart)
	verif.v(not abattages.is_empty(), "le cycle reel doit abattre au moins un arbre en 120 s, sinon ce cas ne prouve rien")
	verif.v(not dodos.is_empty(), "et au moins un colon doit avoir eu a dormir")

	# Le manoeuvre (outil en bois) n'abat JAMAIS rien, sur le chemin reel.
	for abattage in abattages:
		verif.v(String(abattage.colon_id) != "manoeuvre",
			"le porteur d'outil sous le seuil n'abat jamais rien, meme sur 120 s")

# ---- HORS DOMAINE -----------------------------------------------------------

# Des tailleurs de cristal sur une planete sans arbres : catalogue de materiaux,
# table de types, transformations, canal perceptif, etats, engagements ET TOUS
# les noms de propriete sont fabriques ici, aucun n'existe ailleurs dans le
# depot. Pas un arbre, pas un bucheron, pas une seconde de sommeil -- et le meme
# code traverse la chaine entiere : gate d'entame, chantier consomme au rythme,
# repos par couplage, veine entamee qui se degrade, bifurcation a trois issues.
func _hors_domaine_des_tailleurs_de_cristal() -> void:
	var materiaux := {
		"quartz_zorg": {"densite": 2.6, "tenacite_zorg": 12.0, "mordant_zorg": 8.0},
		"eclat_zorg": {"densite": 2.6},
		"poudre_zorg": {"densite": 1.1},
		"gangue_zorg": {"densite": 0.9},
		"mousse_zorg": {"densite": 0.2},
	}
	var types := {
		"prisme_zorg": {"composition": [{"materiau": "quartz_zorg", "volume": 1.0}]},
		"brisure_zorg": {"composition": [{"materiau": "eclat_zorg", "volume": 1.0}]},
		"poussiere_zorg": {"composition": [{"materiau": "poudre_zorg", "volume": 1.0}]},
	}
	var transformations := {
		"taille_zorg": {"portee_travail": 50.0},
		"taille_pure": {"a_zero": {"produire": {"type_produit": "prisme_zorg", "rendement": 0.8}}},
		"taille_brisee": {"a_zero": {"produire": {"type_produit": "brisure_zorg", "rendement": 0.4}}},
		"taille_pulverisee": {"a_zero": {"produire": {"type_produit": "poussiere_zorg", "rendement": 0.1}}},
	}
	var canaux := {"palpe_zorg": {"geometrie": "cone_oriente", "proprietes_captees": []}}
	var etats := {
		"fissure_zorg": {"duree": 6.0, "effets": []},
		"blotti_zorg": {"effets": []},
		"lourd_zorg": {"effets": [{"propriete": "cadence_zorg", "mode": "moduler", "facteur": 0.5}]},
	}
	var engagements := {
		"blottir_zorg": {
			"poids": 4.0, "seuil_satisfait": 40.0, "seuil_bascule": 12.0,
			"sens_satisfaction": "sur_seuil", "satisfait_par": "reserves.{canal}.reserve",
		},
	}
	var catalogues := {"types": types, "materiaux": materiaux, "canaux": canaux,
		"transformations": transformations, "proprietes_immuables": ["tenacite_zorg", "mordant_zorg"]}

	var config := {
		"nom_reserve_matiere": "substance_zorg",
		"nom_reserve_sommeil": "torpeur",
		"nom_reserve_fraicheur": "nettete_fissure",
		"propriete_tranchant_max": "mordant_zorg",
		"propriete_tranchant_effectif": "mordant_use",
		"propriete_resistance": "tenacite_zorg",
		"propriete_chantier": "taillable",
		"propriete_valeur": "eclat_percu",
		"propriete_source_repos": "emet_torpeur",
		"propriete_recoit_repos": "recoit_torpeur",
		"propriete_humidite": "brume_zorg",
		"nom_miroir_manque": "manque_torpeur",
		"nom_vitesse": "glisse",
		"nom_rythme": "cadence_zorg",
		"nom_etat_epuise": "lourd_zorg",
		"nom_etat_entaille": "fissure_zorg",
		"nom_etat_repose": "blotti_zorg",
		"regle_engagement_dormir": "blottir_zorg",
		"canal_engagement": "torpeur",
		"transformation_chantier": "taille_zorg",
		"seuil_tranchant": 0.30,
		"marge_securite": 1.5,
		"capacite_sommeil": 50.0,
		"cout_veille_par_s": 0.8,
		"surcout_coupe_par_s": 1.2,
		"fraicheur_entaille": 8.0,
		"degradation_entaille_base": 0.5,
		"sensibilite_humidite": 0.6,
		"humidite_locale": 0.4,
		"brume_zorg": 0.4,
		"portee_lit": 60.0,
		"seuils_locaux": {"torpeur_zorg": {"propriete_continue": "manque_torpeur", "seuil": 38.0, "etat": "lourd_zorg"}},
		"issues": {
			"sorties": ["reussite", "eclats", "debris"],
			"base_biais": {"reussite": 1.0, "eclats": 0.9, "debris": 1.6},
			"refs": {"reussite": "taille_pure", "eclats": "taille_brisee", "debris": "taille_pulverisee"},
			"offset_produit": [0.0, 60.0, 0.0],
		},
		"colons": [
			{"id": "tailleur", "position": [200.0, 200.0, 0.0], "rythme": 1.4, "vitesse": 120.0,
				"adresse": 1.2, "materiau_outil": "quartz_zorg", "sommeil_initial": 50.0, "seuil_ecrasement": 0.6,
				"canaux": ["palpe_zorg"],
				"canaux_config": {"palpe_zorg": {"portee": 900.0, "angle": 360.0, "sensibilite": 1.0, "seuil": 0.0}}},
			{"id": "novice", "position": [260.0, 200.0, 0.0], "rythme": 0.9, "vitesse": 110.0,
				"adresse": 0.5, "materiau_outil": "mousse_zorg", "sommeil_initial": 50.0, "seuil_ecrasement": 0.6,
				"canaux": ["palpe_zorg"],
				"canaux_config": {"palpe_zorg": {"portee": 900.0, "angle": 360.0, "sensibilite": 1.0, "seuil": 0.0}}},
		],
		"arbres": [
			{"id": "veine_1", "position": [400.0, 200.0, 0.0], "materiau": "quartz_zorg", "volume": 0.3, "travail": 9.0, "valeur": 5.0},
			{"id": "veine_2", "position": [560.0, 200.0, 0.0], "materiau": "quartz_zorg", "volume": 0.3, "travail": 9.0, "valeur": 4.0},
		],
		"lit": {"id": "alcove", "position": [120.0, 200.0, 0.0], "materiau": "gangue_zorg",
			"volume": 0.1, "taux_flux": 9.0, "portee_flux": 70.0},
	}

	var scene := _scene_depuis(config, catalogues)
	verif.v(scene.arbres.size() == 2, "les deux veines doivent se fabriquer sur un catalogue entierement invente")
	verif.v(scene.outils.size() == 2, "les deux outils aussi")

	# Le gate d'entame trie sur les memes regles, avec d'autres noms.
	var tailleur := _par_id(scene.colons, "tailleur")
	var novice := _par_id(scene.colons, "novice")
	verif.v(Banc.peut_couper(scene.outils["tailleur"], scene.arbres[0], config), "le mordant du quartz entame la veine")
	verif.v(not Banc.peut_couper(scene.outils["novice"], scene.arbres[0], config),
		"celui de la mousse (mordant absent de sa fiche, repli 0.0) n'entame rien -- le gate est arithmetique")

	var reference := Banc.masse_dans_le_monde(scene.monde, config)
	var compteur := 0
	var perdue := 0.0
	var pire_ecart := 0.0
	var abattages: Array = []
	var entailles: Array = []
	var dodos: Array = []
	for i in range(900):
		var bilan := Banc.avancer(scene.colons, scene.outils, scene.arbres, scene.lit, scene.monde,
			compteur, DELTA, config, catalogues, etats, engagements)
		compteur = int(bilan.compteur_produit)
		perdue += float(bilan.masse_perdue)
		for a in bilan.abattages:
			abattages.append(a)
		for id in bilan.entailles_posees:
			entailles.append(id)
		for e in bilan.sommeil:
			dodos.append(e)
		pire_ecart = max(pire_ecart, absf(Banc.masse_dans_le_monde(scene.monde, config) + perdue - reference))

	verif.v(pire_ecart < EPS, "la conservation tient sur un domaine entierement invente (pire ecart %.9f)" % pire_ecart)
	verif.v(not abattages.is_empty(), "les veines doivent finir taillees, sans un seul nom du depot")
	verif.v(not dodos.is_empty(), "et le tailleur doit avoir eu a se blottir")
	for abattage in abattages:
		verif.v(String(abattage.colon_id) != "novice", "le novice n'entame rien, donc n'acheve jamais rien")

	# L'etat 'lourd_zorg' MODULE la cadence -- et le cablage le lit vraiment,
	# via etat_effectif.gd : c'est le piege « rythme lu brut » ferme, verrouille
	# sur un nom d'etat qui n'existe nulle part ailleurs.
	var brut: float = float(tailleur.proprietes[String(config.nom_rythme)])
	tailleur.proprietes["etats_actifs"] = ["lourd_zorg"]
	var module := Banc.rythme_effectif(tailleur, config, etats)
	verif.v(absf(module - brut * 0.5) < EPS,
		"un etat qui module la cadence est REELLEMENT lu par le cablage (%.4f vs %.4f)" % [module, brut * 0.5])
