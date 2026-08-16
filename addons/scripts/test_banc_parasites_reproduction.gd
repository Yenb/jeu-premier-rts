extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_parasites_reproduction.gd
#
# Verrouille le CABLAGE de banc_parasites_reproduction.gd -- jamais un
# mecanisme du coeur, tous inchanges par ce chantier. Les canaux, etats,
# seuils, durees, gabarits d'espece et regles de reproduction REELS sont lus
# sur disque (data/banc_parasites_reproduction.json, data/etats.json,
# data/reproduction.json, data/heredite.json), comme le fait le banc -- chemin
# reel, jamais une fixture locale pour les grandeurs qui decident (meme
# discipline que test_banc_maladie.gd/test_banc_elimination_salete.gd).
#
# DEUX FAMILLES DE CAS, a ne pas confondre :
# - les cas de mecanique posent leurs propres individus, aux positions et aux
#   ages qu'ils veulent : ils isolent UNE transition et ne disent rien de la
#   jouabilite du banc ;
# - _config_reelle_du_disque_produit_un_ecosysteme rejoue
#   data/banc_parasites_reproduction.json EN ENTIER, deplacement seede compris.
#   Sans lui, tout ce fichier resterait VERT alors que le banc lance a l'ecran
#   n'infesterait ni ne ferait naitre personne -- c'est exactement le trou que
#   la calibration d'origine de banc_maladie.gd avait laisse ouvert.
# Aucun cas de la premiere famille ne remplace le second.

const Banc = preload("res://scripts/banc_parasites_reproduction.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const DELTA_TICK := 0.1

var _config: Dictionary
var _etats: Dictionary
var _reproduction: Dictionary
var _heredite: Dictionary

func _init() -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/banc_parasites_reproduction.json"))
	_etats = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	_reproduction = JSON.parse_string(FileAccess.get_file_as_string("res://data/reproduction.json"))
	_heredite = JSON.parse_string(FileAccess.get_file_as_string("res://data/heredite.json"))

	_la_charge_monte_a_portee_du_parasite()
	_l_incubation_est_posee_au_seuil_et_le_canal_reste()
	_l_infestation_reduit_la_vitesse()
	_la_reinfestation_est_possible()
	_pas_de_double_incubation()
	_le_cycle_de_reproduction_va_de_bout_en_bout()
	_le_non_porteur_perd_sa_gestation_a_la_naissance()
	_la_naissance_est_ajoutee_au_monde()
	_le_mort_est_retire_du_monde()
	_population_dense_donne_plus_d_infestations()
	_les_deux_entrees_de_seuil_ne_se_croisent_jamais()
	_le_parasite_pond_sous_gate_de_densite()
	_le_gate_de_vigueur_retient_l_accouplement()
	_config_reelle_du_disque_produit_un_ecosysteme()

	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: banc_parasites_reproduction.gd -- infestation (charge.gd) sans " +
		"retrait du canal, incubation puis symptomes (etat_duree.gd), vitesse " +
		"modulee (etat_effectif.gd), deux morts disjointes (seuil_etat.gd), et " +
		"le cycle de reproduction complet (senescence/stade/accouplement/" +
		"gestation/heredite) jusqu'a une naissance ajoutee au Monde -- sans " +
		"qu'aucun mecanisme du coeur ne soit touche")
	quit(0)

# ---- Outillage ----------------------------------------------------------

# Config au MEME FORMAT que le fichier de banc, avec TOUTES les grandeurs
# reelles lues sur disque (canal, seuils, especes, genes, vigueur, portees) --
# seule la liste des individus est fournie par le cas. Chemin reel pour ce qui
# decide, fixture locale seulement pour les positions/ages/id.
func _config_test(individus: Array) -> Dictionary:
	var config := _config.duplicate(true)
	config["individus"] = individus
	return config

func _decl(id: String, espece: String, position: Vector3, age: float, alleles: Array = []) -> Dictionary:
	var genes: Dictionary = {}
	if not alleles.is_empty():
		genes["endurance_course"] = {"alleles": alleles}
	return {
		"id": id,
		"espece": espece,
		"position": [position.x, position.y, position.z],
		"age": age,
		"genes_etat": genes,
	}

func _hote(id: String, position: Vector3, age: float = 6.0, alleles: Array = [1.0, 1.0]) -> Dictionary:
	return _decl(id, String(_config.espece_hote), position, age, alleles)

func _parasite(id: String, position: Vector3, age: float = 2.0) -> Dictionary:
	return _decl(id, String(_config.espece_parasite), position, age)

func _catalogues() -> Dictionary:
	return {"etats": _etats, "reproduction": _reproduction, "heredite": _heredite}

func _par_id(entites: Array, id: String) -> Dictionary:
	for entite in entites:
		if entite.id == id:
			return entite
	return {}

# Une scene de test complete : les entites, le Monde, les compteurs, la RNG
# seedee. Rendue en Dictionary pour que chaque cas la fasse avancer sans
# reecrire la boucle.
func _scene(individus: Array) -> Dictionary:
	var config := _config_test(individus)
	var entites := Banc.fabriquer_tout(config)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config.seed)
	return {
		"config": config,
		"entites": entites,
		"monde": Banc.monde_des_vivants(entites),
		"compteurs": {"tick": 0, "petits": 0, "parasites_nes": 0, "naissances": 0},
		"rng": rng,
	}

# Fait avancer la scene de n ticks SANS deplacement (les cas de mecanique
# posent des individus immobiles pour isoler une transition ; seul le rejeu de
# la config reelle deplace). Cumule tous les evenements rendus.
func _avancer(scene: Dictionary, n: int) -> Dictionary:
	var cumul := {
		"incubations": [], "declares": [], "gueris": [],
		"morts": [], "gestations": [], "pontes": [], "naissances": [],
	}
	for i in n:
		var r := Banc.avancer(scene.entites, scene.monde, scene.compteurs, DELTA_TICK, scene.config, _catalogues(), scene.rng)
		scene["monde"] = r.monde
		scene["compteurs"] = r.compteurs
		for cle in cumul:
			cumul[cle].append_array(r[cle])
	return cumul

# S'ARRETE AU TICK EXACT DE LA PROCHAINE NAISSANCE. Indispensable pour tout ce
# qui s'observe A LA NAISSANCE et nulle part ailleurs : l'age du nouveau-ne, son
# stade, la vigueur videe des parents, la taille du Monde. Un simple
# _avancer(scene, 400) les manque TOUS -- le petit a vieilli, la vigueur est
# remontee, d'autres portees ont suivi (defaut reel du premier jet de ce
# fichier, quatre assertions rouges pour un code pourtant juste).
func _avancer_jusqu_a_naissance(scene: Dictionary, max_ticks: int) -> Dictionary:
	for i in max_ticks:
		var r := Banc.avancer(scene.entites, scene.monde, scene.compteurs, DELTA_TICK, scene.config, _catalogues(), scene.rng)
		scene["monde"] = r.monde
		scene["compteurs"] = r.compteurs
		if not r.naissances.is_empty():
			return r
	return {"naissances": [], "gestations": [], "morts": [], "incubations": [], "declares": [], "gueris": [], "pontes": []}

# ---- Cas ----------------------------------------------------------------

# Positions calees sur portee_charge REELLE, jamais un nombre en dur : l'hote
# proche est a une demi-portee du parasite, l'hote loin a dix portees.
func _la_charge_monte_a_portee_du_parasite() -> void:
	var portee: float = _config.canal_infestation.portee_charge
	var scene := _scene([
		_parasite("p", Vector3.ZERO),
		_hote("proche", Vector3(portee * 0.5, 0.0, 0.0)),
		_hote("loin", Vector3(portee * 10.0, 0.0, 0.0)),
	])
	_avancer(scene, 10)

	var proche := _par_id(scene.entites, "proche")
	var loin := _par_id(scene.entites, "loin")
	verif.v(Banc.charge_infestation(proche) > 0.0,
		"un hote a portee d'un parasite doit voir sa charge d'infestation monter")
	verif.v(Banc.charge_infestation(loin) == 0.0,
		"un hote hors de portee_charge ne doit JAMAIS accumuler la moindre charge")
	verif.v(not scene.entites[0].proprietes.has("etats"),
		"un parasite ne porte pas de canal receveur -- charge.gd doit le sauter, il n'est que CAUSE")

# Seuil et poids REELS : le nombre de ticks est DERIVE de la donnee, jamais
# recopie -- si Yael recalibre le canal, ce cas suit sans etre reecrit.
func _l_incubation_est_posee_au_seuil_et_le_canal_reste() -> void:
	var scene := _scene([_parasite("p", Vector3.ZERO), _hote("h", Vector3(10.0, 0.0, 0.0))])
	var seuil: float = _config.canal_infestation.seuil
	var poids: float = _config.poids_parasite
	var ticks := int(seuil / poids / DELTA_TICK) + 4
	var r := _avancer(scene, ticks)
	var hote := _par_id(scene.entites, "h")

	verif.v(r.incubations.has("h"), "l'hote a portee doit franchir le seuil du canal et entrer en incubation")
	verif.v(hote.proprietes.etats_actifs.has("incube_parasite"), "l'etat 'incube_parasite' doit etre pose")
	verif.v(hote.proprietes.get("porteur_parasite", 0.0) == 1.0,
		"un hote fraichement infeste doit etre contagieux IMMEDIATEMENT, avant tout symptome")
	verif.v(not hote.proprietes.etats_actifs.has("infeste"), "pendant l'incubation, 'infeste' ne doit pas encore etre pose")
	verif.v(hote.proprietes.has("etats"),
		"LE CANAL NE DOIT JAMAIS ETRE RETIRE (difference voulue avec banc_maladie.gd) -- c'est ce qui rend la reinfestation possible")

	var vitesse_base: float = _config.especes[String(_config.espece_hote)].vitesse
	var vitesse_gene := vitesse_base + 2.0 * float(_config.catalogue_genes.endurance_course.cibles[0].poids)
	verif.v(is_equal_approx(EtatEffectif.valeur(hote, "vitesse", _etats), vitesse_gene),
		"pendant l'incubation, la vitesse effective doit rester EXACTEMENT celle du gene (aucun symptome)")

func _l_infestation_reduit_la_vitesse() -> void:
	var scene := _scene([_parasite("p", Vector3.ZERO), _hote("h", Vector3(10.0, 0.0, 0.0))])
	var seuil: float = _config.canal_infestation.seuil
	var incubation_s: float = _etats.incube_parasite.duree
	var ticks := int((seuil / float(_config.poids_parasite) + incubation_s) / DELTA_TICK) + 8
	var r := _avancer(scene, ticks)
	var hote := _par_id(scene.entites, "h")

	verif.v(r.declares.has("h"), "l'incubation doit expirer d'elle-meme (etat_duree.gd) et le cablage doit poser 'infeste'")
	verif.v(hote.proprietes.etats_actifs.has("infeste"), "l'etat 'infeste' doit etre actif")
	verif.v(not hote.proprietes.etats_actifs.has("incube_parasite"), "'incube_parasite' doit avoir cede la place a 'infeste'")

	var vitesse_base: float = _config.especes[String(_config.espece_hote)].vitesse
	var vitesse_gene := vitesse_base + 2.0 * float(_config.catalogue_genes.endurance_course.cibles[0].poids)
	var facteur: float = _etats.infeste.effets[0].facteur
	verif.v(is_equal_approx(EtatEffectif.valeur(hote, "vitesse", _etats), vitesse_gene * facteur),
		"une fois infeste, la vitesse effective doit etre reduite EXACTEMENT par le facteur de data/etats.json:infeste")

# LE SUJET DU BANC. Le canal n'etant jamais retire, un hote gueri redevient
# susceptible : sa charge redescend (taux_decroissance), puis remonte, et une
# SECONDE incubation se pose. Le parasite est ecarte pendant la guerison pour
# que la charge ait le temps de retomber sous le seuil -- exactement ce qu'un
# hote qui s'eloigne fait a l'ecran.
func _la_reinfestation_est_possible() -> void:
	var scene := _scene([_parasite("p", Vector3.ZERO), _hote("h", Vector3(10.0, 0.0, 0.0))])
	var seuil: float = _config.canal_infestation.seuil
	var incubation_s: float = _etats.incube_parasite.duree
	var infeste_s: float = _etats.infeste.duree
	var parasite := _par_id(scene.entites, "p")
	var hote := _par_id(scene.entites, "h")

	var r1 := _avancer(scene, int((seuil / float(_config.poids_parasite) + incubation_s) / DELTA_TICK) + 8)
	verif.v(r1.incubations.size() == 1, "une seule incubation avant la guerison")

	# Le parasite s'ecarte : la charge redescend pendant que l'infestation
	# s'epuise. Le Monde n'a pas a etre reconstruit -- il n'est lu que par
	# l'accouplement et la ponte, jamais par charge.gd.
	parasite.position = Vector3(100000.0, 0.0, 0.0)
	var r2 := _avancer(scene, int(infeste_s / DELTA_TICK) + 8)
	verif.v(r2.gueris.has("h"), "l'infestation doit expirer d'elle-meme et l'hote guerir")
	verif.v(not hote.proprietes.etats_actifs.has("infeste"), "'infeste' doit avoir ete retire")
	verif.v(hote.proprietes.get("porteur_parasite", 1.0) == 0.0, "un hote gueri ne doit plus etre contagieux")
	verif.v(Banc.charge_infestation(hote) == 0.0,
		"loin de toute cause, la charge doit REDESCENDRE a zero -- taux_decroissance non nul, contrairement au cliquet de banc_maladie.gd")
	verif.v(Banc.peut_incuber(hote), "un hote gueri doit redevenir susceptible")

	# UN PARASITE NEUF, jamais celui de la phase 1 ramene sur place : entre
	# temps il a vieilli de tout le temps d'incubation ET d'infestation, et sa
	# 'seuil_longevite' le rattrape avant que la charge ait le temps de
	# remonter -- le cas mesurait alors la longevite, pas la reinfestation
	# (defaut reel du premier jet). Ajoute directement a la liste : charge.gd
	# lit les entites, jamais le Monde.
	scene.entites.append(Banc.fabriquer_individu(_parasite("p_neuf", Vector3(10.0, 0.0, 0.0), 0.0), scene.config))
	var r3 := _avancer(scene, int(seuil / float(_config.poids_parasite) / DELTA_TICK) + 8)
	verif.v(r3.incubations.has("h"),
		"REINFESTATION : le canal n'ayant jamais ete retire, le meme hote doit pouvoir etre infeste une SECONDE fois")

# La garde est un GATE DE CABLAGE, jamais le retrait du canal : la charge
# continue de monter au-dessus du seuil, et pourtant aucune incubation neuve
# n'est posee tant que l'hote en porte deja une.
func _pas_de_double_incubation() -> void:
	var scene := _scene([_parasite("p", Vector3.ZERO), _hote("h", Vector3(10.0, 0.0, 0.0))])
	var seuil: float = _config.canal_infestation.seuil
	var incubation_s: float = _etats.incube_parasite.duree
	var hote := _par_id(scene.entites, "h")

	var r := _avancer(scene, int((seuil / float(_config.poids_parasite) + incubation_s * 0.5) / DELTA_TICK))
	verif.v(r.incubations.size() == 1, "une seule incubation, jamais deux, alors que la charge reste au-dessus du seuil")
	verif.v(not Banc.peut_incuber(hote), "peut_incuber doit refuser un hote deja en incubation")

	var r2 := _avancer(scene, int(incubation_s * 4.0 / DELTA_TICK))
	verif.v(r2.declares.size() == 1, "l'incubation ne doit se declarer qu'une fois, jamais reposee par le marqueur qui reste vrai")
	verif.v(not Banc.peut_incuber(hote), "peut_incuber doit refuser un hote deja infeste")

	var mort := {"proprietes": {"etats_actifs": ["mort_parasite"]}}
	verif.v(not Banc.peut_incuber(mort), "peut_incuber doit refuser un mort")

# Le cycle entier sans aucun parasite : vieillissement (senescence.gd), stade
# (stade.gd), vigueur (depense.gd), rencontre (accouplement.gd), gestation
# (gestation.gd), kit genetique (heredite.gd), naissance (cablage).
func _le_cycle_de_reproduction_va_de_bout_en_bout() -> void:
	var scene := _scene([
		_hote("a", Vector3.ZERO, 6.0, [1.0, 1.0]),
		_hote("b", Vector3(30.0, 0.0, 0.0), 6.0, [-1.0, -1.0]),
	])
	var a := _par_id(scene.entites, "a")
	verif.v(a.proprietes.stade == "adulte", "un hote de 6 annees doit deja etre adulte (stade.gd, stades_config du gabarit)")

	var r := _avancer_jusqu_a_naissance(scene, 400)
	verif.v(not r.naissances.is_empty(), "la gestation doit aller jusqu'a une naissance reelle")
	if r.naissances.is_empty():
		return

	var naissance: Dictionary = r.naissances[0]
	verif.v(String(naissance.partenaire_id) != String(naissance.parent_id),
		"en mode sexuee, le petit doit avoir DEUX parents distincts -- preuve qu'accouplement.gd a bien pose la gestation, jamais gestation.gd:poser")
	var petit := _par_id(scene.entites, String(naissance.id))
	verif.v(not petit.is_empty(), "le petit doit avoir rejoint la liste des entites")
	verif.v(petit.proprietes.age < 1.0, "un nouveau-ne repart a age 0.0, aucun chemin special")
	verif.v(petit.proprietes.stade != "adulte", "un nouveau-ne ne doit pas naitre fertile")
	verif.v(petit.proprietes.has("etats"), "un petit d'hote doit porter le canal receveur des sa naissance")

	# Parents homozygotes opposes : l'enfant tire un allele de chaque, sa somme
	# est TOUJOURS 0.0 avant mutation -- il nait exactement a la vitesse de base.
	var vitesse_base: float = _config.especes[String(_config.espece_hote)].vitesse
	verif.v(abs(float(petit.proprietes.vitesse) - vitesse_base) < 5.0,
		"le petit de deux homozygotes opposes doit naitre a la vitesse de BASE, entre ses deux parents (heredite.gd + expression.gd)")

# LA CORRECTION DE L'AUDIT (ligne 11, point 3) : sans ce retrait, le
# non-porteur resterait indisponible POUR TOUJOURS.
func _le_non_porteur_perd_sa_gestation_a_la_naissance() -> void:
	var scene := _scene([
		_hote("a", Vector3.ZERO),
		_hote("b", Vector3(30.0, 0.0, 0.0), 6.0, [-1.0, -1.0]),
	])
	var r := _avancer_jusqu_a_naissance(scene, 400)
	verif.v(not r.naissances.is_empty(), "prealable : une naissance doit avoir eu lieu")
	if r.naissances.is_empty():
		return

	var a := _par_id(scene.entites, "a")
	var b := _par_id(scene.entites, "b")
	verif.v(not a.proprietes.has("gestation"), "le PORTEUR doit avoir perdu sa gestation a la naissance")
	verif.v(not b.proprietes.has("gestation"),
		"le NON-PORTEUR doit lui aussi avoir perdu sa gestation -- sinon la garde d'accouplement.gd le rend indisponible pour toujours")
	verif.v(not a.proprietes.has("accouplement_accumulateur") and not b.proprietes.has("accouplement_accumulateur"),
		"l'accumulateur des deux parents doit etre vide -- il ne redescend JAMAIS tout seul, une gestation serait reposee au tick suivant")
	verif.v(Banc.vigueur(a) < float(_config.seuil_vigueur_accouplement)
		and Banc.vigueur(b) < float(_config.seuil_vigueur_accouplement),
		"la vigueur des deux parents doit etre videe -- c'est elle qui tient le rythme des portees")

	# CONTRE-EPREUVE, et c'est elle qui donne son sens a tout le cas : le couple
	# doit pouvoir refaire un petit. Sans le triple retrait, la seconde portee
	# n'arrive JAMAIS (le non-porteur reste indisponible pour toujours).
	var r2 := _avancer_jusqu_a_naissance(scene, 400)
	verif.v(not r2.naissances.is_empty(),
		"le MEME couple doit pouvoir se reproduire une SECONDE fois -- c'est tout l'objet de la correction")

func _la_naissance_est_ajoutee_au_monde() -> void:
	var scene := _scene([
		_hote("a", Vector3.ZERO),
		_hote("b", Vector3(30.0, 0.0, 0.0), 6.0, [-1.0, -1.0]),
	])
	var r := _avancer_jusqu_a_naissance(scene, 400)
	verif.v(not r.naissances.is_empty(), "prealable : une naissance doit avoir eu lieu")
	if r.naissances.is_empty():
		return
	var id_petit := String(r.naissances[0].id)
	verif.v(scene.monde.choses.has(id_petit),
		"le petit doit avoir ete AJOUTE au Monde (reconstruit du neant au tick de sa naissance)")
	verif.v(scene.monde.choses.size() == 3, "le Monde doit compter les deux parents et le petit")

# Un hote au cumul juste sous le seuil : un seul tick d'infestation le fait
# basculer. Le seuil vient du catalogue LOCAL du banc, jamais recopie ici.
func _le_mort_est_retire_du_monde() -> void:
	var scene := _scene([_hote("a", Vector3.ZERO), _hote("b", Vector3(600.0, 0.0, 0.0))])
	var a := _par_id(scene.entites, "a")
	var seuil: float = _config.seuils_locaux.mort_parasitose.seuil
	a.proprietes["charge_parasitaire_cumulee"] = seuil - DELTA_TICK * 0.5
	a.proprietes.etats_actifs.append("infeste")

	verif.v(scene.monde.choses.has("a"), "prealable : l'hote vivant est dans le Monde")
	var r := _avancer(scene, 2)

	verif.v(r.morts.size() == 1 and r.morts[0].id == "a", "l'hote dont le cumul franchit le seuil doit mourir")
	verif.v(r.morts[0].cause == "mort_parasite", "la cause tracee doit etre la parasitose")
	verif.v(a.proprietes.etats_actifs.has("mort_parasite"), "l'etat 'mort_parasite' doit etre pose")
	verif.v(a.proprietes.get("porteur_parasite", 1.0) == 0.0, "un mort ne doit plus etre contagieux")
	verif.v(EtatEffectif.valeur(a, "vitesse", _etats) == 0.0, "'mort_parasite' doit ECRASER la vitesse a 0.0")
	verif.v(not scene.monde.choses.has("a"),
		"le mort doit avoir QUITTE le Monde (reconstruit du neant sans lui) -- plus percu, plus partenaire, plus une cause")
	verif.v(scene.monde.choses.has("b"), "les vivants sont ré-ajoutes PAR REFERENCE, leur etat interne traverse la reconstruction")
	verif.v(_par_id(scene.entites, "a") != {}, "le mort reste dans la liste animee (il doit rester visible et compte a l'ecran)")
	verif.v(Banc.causes_infestation(scene.entites, scene.config).is_empty(),
		"un mort ne doit plus jamais figurer comme cause d'infestation")

# LE COUPLAGE. Meme parasite, meme duree, meme nombre d'hotes : seule la
# DENSITE change. Les deux scenes sont immobiles, la geometrie est donc la
# seule variable.
func _population_dense_donne_plus_d_infestations() -> void:
	var portee: float = _config.canal_infestation.portee_charge
	var dense: Array = [_parasite("p", Vector3.ZERO)]
	var disperse: Array = [_parasite("p", Vector3.ZERO)]
	for i in 5:
		dense.append(_hote("d%d" % i, Vector3(portee * 0.2 * float(i), 0.0, 0.0)))
		disperse.append(_hote("s%d" % i, Vector3(portee * 3.0 * float(i + 1), 0.0, 0.0)))

	var scene_dense := _scene(dense)
	var scene_disperse := _scene(disperse)
	var ticks := int(_config.canal_infestation.seuil / float(_config.poids_parasite) / DELTA_TICK) + 10
	var r_dense := _avancer(scene_dense, ticks)
	var r_disperse := _avancer(scene_disperse, ticks)

	verif.v(r_dense.incubations.size() > r_disperse.incubations.size(),
		"une population DENSE doit produire strictement plus d'infestations qu'une population dispersee, a duree et parasite egaux")
	verif.v(r_disperse.incubations.is_empty(),
		"aucun hote disperse (au-dela de portee_charge) ne doit etre infeste")

# Les deux entrees du catalogue local visent des proprietes que l'autre espece
# ne porte pas : chacune est un chemin mort silencieux pour l'autre, par la
# SEULE ARITHMETIQUE (seuil_etat.gd rend false avant meme d'ecrire sa memoire
# quand propriete_continue est absente, et replie sur INF quand
# seuil_propriete l'est).
func _les_deux_entrees_de_seuil_ne_se_croisent_jamais() -> void:
	var scene := _scene([_hote("h", Vector3.ZERO, 500.0), _parasite("p", Vector3(600.0, 0.0, 0.0), 0.0)])
	var hote := _par_id(scene.entites, "h")
	var parasite := _par_id(scene.entites, "p")

	verif.v(not hote.proprietes.has("seuil_longevite"),
		"un hote ne porte pas 'seuil_longevite' -- l'entree 'fin_vie' replie sur INF pour lui")
	verif.v(not parasite.proprietes.has("charge_parasitaire_cumulee"),
		"un parasite ne porte pas 'charge_parasitaire_cumulee' -- l'entree 'mort_parasitose' est pour lui un chemin mort")

	var r := _avancer(scene, 300)
	verif.v(not Banc.est_mort(hote),
		"un hote de 500 annees ne doit JAMAIS mourir de vieillesse -- il vieillit seulement pour ses stades")
	verif.v(Banc.est_mort(parasite), "un parasite doit mourir quand son age depasse son 'seuil_longevite'")
	var mort_parasite: Dictionary = {}
	for entree in r.morts:
		if entree.id == "p":
			mort_parasite = entree
	verif.v(mort_parasite.get("cause", "") == "mort_vieillesse", "la cause tracee doit etre la fin de vie, jamais la parasitose")

# LE GATE DE PONTE EST UN RATIO, jamais un nombre absolu (voir
# banc_parasites_reproduction.gd:peut_pondre, RESULTAT NEGATIF -- un gate
# absolu ne freine rien et fait exploser la population). Trois epreuves : assez
# d'hotes PAR parasite -> il pond ; trop peu d'hotes -> jamais ; assez d'hotes
# mais trop de parasites -> jamais non plus. C'est la troisieme, et elle seule,
# qui verrouille le ratio contre un retour au nombre absolu.
func _le_parasite_pond_sous_gate_de_densite() -> void:
	var minimum := int(_config.min_hotes_par_parasite)
	var portee: float = _config.portee_ponte

	# GEOMETRIE VOULUE : les hotes sont poses DE PART ET D'AUTRE du parasite, a
	# une demi-portee_ponte chacun -- donc tous a portee de SA ponte, mais
	# separes de portee_ponte entiere, largement au-dela de portee_rencontre.
	# Ils ne s'accouplent donc jamais entre eux, et le nombre d'hotes reste
	# FIXE pendant tout le cas : sans cette precaution, leurs propres naissances
	# rouvriraient le gate du parasite en cours de route et le cas mesurerait
	# autre chose que ce qu'il annonce (defaut reel du premier jet).
	var assez: Array = [_parasite("p", Vector3.ZERO)]
	for i in minimum:
		assez.append(_hote("h%d" % i, Vector3(portee * 0.5 * (1.0 if i % 2 == 0 else -1.0), 0.0, 0.0)))
	var scene_assez := _scene(assez)
	verif.v(Banc.peut_pondre(scene_assez.entites[0], scene_assez.monde, scene_assez.config),
		"prealable : un parasite seul avec 'min_hotes_par_parasite' hotes a portee doit pouvoir pondre")
	var r_assez := _avancer(scene_assez, int(float(_reproduction.parasite.duree_gestation) / DELTA_TICK) + 20)
	verif.v(not r_assez.pontes.is_empty(), "un parasite adulte avec assez d'hotes par parasite doit pondre")
	verif.v(not r_assez.naissances.is_empty(), "la ponte asexuee doit aller jusqu'a une naissance reelle (gestation.gd:poser -> avancer)")
	verif.v(String(r_assez.naissances[0].espece) == String(_config.espece_parasite),
		"le petit d'un parasite est un parasite -- l'espece vient du parent, jamais d'un nom en dur")
	verif.v(r_assez.pontes.size() == 1,
		"UNE SEULE ponte : le parasite ne, comptant a son tour, referme le gate -- c'est la capacite de charge qui borne la population")

	var trop_peu: Array = [_parasite("p", Vector3.ZERO), _hote("h0", Vector3(portee * 0.5, 0.0, 0.0))]
	var scene_peu := _scene(trop_peu)
	var r_peu := _avancer(scene_peu, 200)
	verif.v(r_peu.pontes.is_empty(),
		"un parasite avec trop peu d'hotes a portee ne doit JAMAIS pondre -- c'est le bras montant du couplage")

	var trop_de_parasites: Array = [_parasite("p0", Vector3.ZERO), _parasite("p1", Vector3(4.0, 0.0, 0.0))]
	for i in minimum:
		trop_de_parasites.append(_hote("h%d" % i, Vector3(portee * 0.5 * (1.0 if i % 2 == 0 else -1.0), 0.0, 0.0)))
	var scene_pleine := _scene(trop_de_parasites)
	var r_pleine := _avancer(scene_pleine, 200)
	verif.v(r_pleine.pontes.is_empty(),
		"MEME nombre d'hotes, DEUX parasites : le ratio doit refermer le gate -- un gate sur le nombre absolu laisserait pondre les deux")

# accouplement.gd ne lit AUCUNE reserve : c'est le refus de l'appeler qui EST
# le gate. Contre-epreuve directe -- vigueur videe a chaque tick, aucune
# gestation ne se pose jamais alors que les deux adultes sont a portee.
func _le_gate_de_vigueur_retient_l_accouplement() -> void:
	var scene := _scene([_hote("a", Vector3.ZERO), _hote("b", Vector3(30.0, 0.0, 0.0), 6.0, [-1.0, -1.0])])
	var a := _par_id(scene.entites, "a")
	var b := _par_id(scene.entites, "b")
	var gestations := 0
	for i in 400:
		Banc.vider_vigueur(a)
		Banc.vider_vigueur(b)
		var r := Banc.avancer(scene.entites, scene.monde, scene.compteurs, DELTA_TICK, scene.config, _catalogues(), scene.rng)
		scene["monde"] = r.monde
		scene["compteurs"] = r.compteurs
		gestations += r.gestations.size()
	verif.v(gestations == 0,
		"sous le seuil de vigueur, deux adultes a portee ne doivent JAMAIS s'accoupler")
	verif.v(not a.proprietes.has("gestation"), "aucune gestation ne doit avoir ete posee")

# LE SEUL CAS QUI REJOUE data/banc_parasites_reproduction.json EN ENTIER --
# neuf individus a leurs positions reelles, deplacement aleatoire seede reel,
# canal/seuils/durees/regles de reproduction reels. Tous les autres cas posent
# leurs propres individus immobiles a portee : ils resteraient VERTS alors que
# le banc lance a l'ecran n'infesterait ni ne ferait naitre personne (defaut
# reellement survenu sur la calibration d'origine de banc_maladie.gd).
#
# Trois assertions seulement, les plus larges qui gardent le contrat : une
# calibration reste libre de bouger tant que les trois phenomenes se
# produisent. Ne JAMAIS y coder un compte de morts ni un instant precis -- ce
# serait reverrouiller la calibration elle-meme, que Yael doit pouvoir regler
# sans casser ce fichier.
func _config_reelle_du_disque_produit_un_ecosysteme() -> void:
	var entites := Banc.fabriquer_tout(_config)
	var monde = Banc.monde_des_vivants(entites)
	var compteurs := {"tick": 0, "petits": 0, "parasites_nes": 0, "naissances": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_config.seed)

	var infestations := 0
	var naissances_hote := 0
	var naissances_parasite := 0
	var morts_parasitose := 0
	var reinfestations := 0
	var deja_infeste: Dictionary = {}
	for i in 600:
		var r := Banc.avancer(entites, monde, compteurs, DELTA_TICK, _config, _catalogues(), rng)
		monde = r.monde
		compteurs = r.compteurs
		Banc.deplacer(entites, _config.zone, _etats, rng, DELTA_TICK)
		infestations += r.incubations.size()
		for id in r.incubations:
			if deja_infeste.has(id):
				reinfestations += 1
			deja_infeste[id] = true
		for entree in r.naissances:
			if String(entree.espece) == String(_config.espece_parasite):
				naissances_parasite += 1
			else:
				naissances_hote += 1
		for entree in r.morts:
			if String(entree.cause) == "mort_parasite":
				morts_parasitose += 1

	verif.v(infestations > 0,
		"la config reelle du disque doit infester au moins un hote en 60s -- sinon rien de la chaine parasitaire n'est observable a l'ecran")
	verif.v(reinfestations > 0,
		"la config reelle du disque doit REINFESTER au moins un hote deja gueri en 60s -- c'est le sujet du banc, et il ne se voit que sur le chemin reel")
	verif.v(naissances_hote > 0,
		"la config reelle du disque doit produire au moins une naissance d'HOTE en 60s -- sinon le cycle sexue complet n'est observable qu'au test")
	verif.v(naissances_parasite > 0,
		"la config reelle du disque doit produire au moins une naissance de PARASITE en 60s -- c'est le bras montant du couplage")
	# ASSERTION LA PLUS EXIGEANTE DU FICHIER, et la seule qui prouve que le banc
	# montre ce qu'il annonce. Une version plus faible (« au moins une mort »)
	# etait VERTE alors que les seules morts observees en scene reelle etaient
	# des parasites de VIEILLESSE : aucun hote ne mourait, la couleur « rouge »
	# du cahier des charges n'apparaissait jamais, et le bras descendant du
	# couplage n'existait pas. Elle exige en plus une REINFESTATION en amont :
	# 'infeste' durant 12.0s pour un seuil de mort a 14.0 de cumul, une seule
	# infestation ne peut PAS tuer -- il faut la seconde.
	verif.v(morts_parasitose > 0,
		"la config reelle du disque doit tuer au moins un hote PAR PARASITOSE en 60s -- une mort de vieillesse de parasite ne prouve rien du bras descendant")
	verif.v(entites.size() < 60,
		"la population totale doit rester BORNEE -- contre-epreuve de la capacite de charge : sans elle les deux especes croissent exponentiellement et la suite de tests PEND (mesure)")
