extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_croyance.gd
#
# Verrouille scripts/croyance.gd comme mecanisme GENERIQUE de copie partielle
# et faillible d'un ensemble d'observations -- pas un code de colon, de fruit
# ni de feu.
#
# DOMAINE ENTIEREMENT INVENTE, jamais vu ailleurs dans le depot : un
# CONSIGNEUR ORBITAL qui recopie l'etat de SONDES avec une fiabilite par
# champ, et rend son registre PLUTOT QUE les sondes. Les champs observes
# (flux_tellurique, resonance_ambre) et le champ non observable
# (derive_azimutale) n'existent nulle part dans data/. Si ce test passe, le
# mecanisme ne sait rien du monde d'Orion.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque -- le
# catalogue est un Dictionary construit ici, jamais data/croyances.json.

const Croyance = preload("res://scripts/croyance.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_observer_cree_lentree_avec_la_certitude_initiale(v)
	_observer_a_nouveau_incremente_la_certitude(v)
	_la_certitude_ne_depasse_jamais_le_plafond(v)
	_une_propriete_non_observable_est_ignoree(v)
	_observer_rafraichit_la_valeur_a_chaque_passage(v)
	_filtrer_rend_la_meme_forme_que_perceptions(v)
	_filtrer_rend_la_valeur_crue_pas_la_valeur_reelle(v)
	_une_propriete_inconnue_est_absente_du_filtre(v)
	_les_id_sont_conserves_dans_le_filtre(v)
	_filtrer_ne_mute_jamais_la_chose_reelle(v)
	_les_champs_de_configuration_traversent_le_filtre(v)
	_sans_catalogue_le_filtre_est_un_remplacement_strict(v)
	_un_consigneur_sans_croyance_voit_des_choses_sans_propriete(v)
	_corriger_met_a_jour_si_la_certitude_est_sous_la_resistance(v)
	_corriger_est_ignore_si_la_certitude_atteint_la_resistance(v)
	_la_credibilite_module_le_gain_de_correction(v)
	_corriger_cree_une_croyance_jamais_observee(v)
	_avancer_fait_decroitre_la_certitude(v)
	_une_entree_sous_le_plancher_est_retiree(v)
	_une_chose_devenue_vide_est_retiree_a_son_tour(v)
	_propriete_structurelle_absente_alarme_sur_les_quatre(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % v.echecs())
		quit(1)
		return
	print("OK: croyance.gd recopie partiellement un ensemble d'observations avec " +
		"une certitude par champ, rend cette copie a la place de la source, " +
		"resiste a la correction au-dela d'un seuil de certitude et oublie ce " +
		"qui n'est plus revu -- generique a un domaine entierement invente")
	quit(0)

# ---- Outils de cas (domaine invente) ----

const CHAMP_FLUX := "flux_tellurique"
const CHAMP_RESONANCE := "resonance_ambre"
const CHAMP_NON_OBSERVABLE := "derive_azimutale"
const CHAMP_CONFIG := "profil_sonde"

func _consigneur(id: String, croyances: Dictionary = {}) -> Dictionary:
	return {
		"id": id,
		"position": Vector3.ZERO,
		"proprietes": {"croyances": croyances},
	}

func _sonde(id: String, proprietes: Dictionary, position := Vector3(10.0, 0.0, 0.0)) -> Dictionary:
	return {"id": id, "position": position, "proprietes": proprietes}

# Une entree de perception a la forme exacte que rend perception.gd :
# { chose, type, position, distance, canaux }.
func _perception(sonde: Dictionary) -> Dictionary:
	return {
		"chose": sonde,
		"type": "sonde",
		"position": sonde.position,
		"distance": sonde.position.length(),
		"canaux": ["telemetrie"],
	}

func _catalogue() -> Dictionary:
	return {
		"proprietes_observables": [CHAMP_FLUX, CHAMP_RESONANCE],
		"proprietes_conservees": [CHAMP_CONFIG],
		"certitude_initiale": 0.3,
		"gain_par_verification": 0.1,
		"plafond_certitude": 1.0,
		"taux_decroissance": 0.01,
		"plancher_suppression": 0.05,
		"gain_par_echec": 0.8,
		"resistance_par_certitude": 0.9,
	}

# ---- observer ----

func _observer_cree_lentree_avec_la_certitude_initiale(v) -> void:
	var consigneur := _consigneur("consigneur_1")
	var sonde := _sonde("sonde_alpha", {CHAMP_FLUX: 12.5})
	Croyance.observer(consigneur, [_perception(sonde)], _catalogue())
	var croyances: Dictionary = consigneur.proprietes.croyances
	v.v(croyances.has("sonde_alpha"), "observer doit creer l'entree pour la chose percue")
	v.v(croyances["sonde_alpha"].has(CHAMP_FLUX), "observer doit creer le champ observe")
	v.v(croyances["sonde_alpha"][CHAMP_FLUX].valeur == 12.5,
		"la valeur crue doit etre celle lue sur la chose au moment de l'observation")
	v.v(is_equal_approx(croyances["sonde_alpha"][CHAMP_FLUX].certitude, 0.3),
		"une croyance tout juste formee doit porter certitude_initiale")

func _observer_a_nouveau_incremente_la_certitude(v) -> void:
	var consigneur := _consigneur("consigneur_2")
	var sonde := _sonde("sonde_alpha", {CHAMP_FLUX: 12.5})
	Croyance.observer(consigneur, [_perception(sonde)], _catalogue())
	Croyance.observer(consigneur, [_perception(sonde)], _catalogue())
	Croyance.observer(consigneur, [_perception(sonde)], _catalogue())
	var certitude: float = consigneur.proprietes.croyances["sonde_alpha"][CHAMP_FLUX].certitude
	v.v(is_equal_approx(certitude, 0.5),
		"chaque observation de plus doit ajouter gain_par_verification (0.3 + 0.1 + 0.1)")

func _la_certitude_ne_depasse_jamais_le_plafond(v) -> void:
	var consigneur := _consigneur("consigneur_3")
	var sonde := _sonde("sonde_alpha", {CHAMP_FLUX: 12.5})
	for i in range(50):
		Croyance.observer(consigneur, [_perception(sonde)], _catalogue())
	var certitude: float = consigneur.proprietes.croyances["sonde_alpha"][CHAMP_FLUX].certitude
	v.v(is_equal_approx(certitude, 1.0),
		"cinquante observations doivent buter sur plafond_certitude, jamais le depasser")

func _une_propriete_non_observable_est_ignoree(v) -> void:
	var consigneur := _consigneur("consigneur_4")
	var sonde := _sonde("sonde_alpha", {
		CHAMP_FLUX: 12.5,
		CHAMP_NON_OBSERVABLE: 0.75,
	})
	Croyance.observer(consigneur, [_perception(sonde)], _catalogue())
	var par_chose: Dictionary = consigneur.proprietes.croyances["sonde_alpha"]
	v.v(par_chose.has(CHAMP_FLUX), "un champ du catalogue doit etre recopie")
	v.v(not par_chose.has(CHAMP_NON_OBSERVABLE),
		"un champ ABSENT de proprietes_observables ne doit jamais entrer dans les croyances")

# L'observation RAFRAICHIT la valeur : c'est ce qui distingue observer() de
# corriger() -- regarder a nouveau met a jour ce qu'on voit, sans jamais buter
# sur la resistance au dogme (qui ne protege que contre une correction venue
# d'ailleurs).
func _observer_rafraichit_la_valeur_a_chaque_passage(v) -> void:
	var consigneur := _consigneur("consigneur_5")
	var sonde := _sonde("sonde_alpha", {CHAMP_FLUX: 12.5})
	Croyance.observer(consigneur, [_perception(sonde)], _catalogue())
	sonde.proprietes[CHAMP_FLUX] = 40.0
	Croyance.observer(consigneur, [_perception(sonde)], _catalogue())
	var champ: Dictionary = consigneur.proprietes.croyances["sonde_alpha"][CHAMP_FLUX]
	v.v(champ.valeur == 40.0, "une nouvelle observation doit remplacer la valeur crue")
	v.v(is_equal_approx(champ.certitude, 0.4), "et incrementer la certitude du meme geste")

# ---- filtrer ----

func _filtrer_rend_la_meme_forme_que_perceptions(v) -> void:
	var consigneur := _consigneur("consigneur_6")
	var perceptions: Array = [
		_perception(_sonde("sonde_alpha", {CHAMP_FLUX: 12.5})),
		_perception(_sonde("sonde_beta", {CHAMP_RESONANCE: 3.0}, Vector3(40.0, 0.0, 0.0))),
	]
	Croyance.observer(consigneur, perceptions, _catalogue())
	var filtre := Croyance.filtrer(consigneur, perceptions, _catalogue())
	v.v(filtre.size() == perceptions.size(),
		"filtrer doit rendre autant d'entrees qu'il en recoit -- il n'exclut jamais une chose percue")
	for i in range(filtre.size()):
		v.v(filtre[i].has("chose") and filtre[i].has("type") and filtre[i].has("position")
			and filtre[i].has("distance") and filtre[i].has("canaux"),
			"chaque entree filtree doit porter les memes cles qu'une entree de perception")
		v.v(filtre[i].type == perceptions[i].type, "le type doit traverser le filtre inchange")
		v.v(filtre[i].distance == perceptions[i].distance, "la distance doit traverser le filtre inchangee")
		v.v(filtre[i].canaux == perceptions[i].canaux, "les canaux doivent traverser le filtre inchanges")
		v.v(filtre[i].chose.position == perceptions[i].chose.position,
			"la position de la chose doit traverser le filtre inchangee -- on voit OU elle est")

func _filtrer_rend_la_valeur_crue_pas_la_valeur_reelle(v) -> void:
	var consigneur := _consigneur("consigneur_7")
	var sonde := _sonde("sonde_alpha", {CHAMP_FLUX: 12.5})
	Croyance.observer(consigneur, [_perception(sonde)], _catalogue())
	# Le monde change SANS que le consigneur ne le revoie.
	sonde.proprietes[CHAMP_FLUX] = 999.0
	var filtre := Croyance.filtrer(consigneur, [_perception(sonde)], _catalogue())
	v.v(filtre[0].chose.proprietes[CHAMP_FLUX] == 12.5,
		"filtrer doit rendre la valeur CRUE (perimee), jamais la valeur reelle du monde")

func _une_propriete_inconnue_est_absente_du_filtre(v) -> void:
	var consigneur := _consigneur("consigneur_8")
	var sonde := _sonde("sonde_alpha", {CHAMP_FLUX: 12.5})
	Croyance.observer(consigneur, [_perception(sonde)], _catalogue())
	# Le monde gagne un champ que le consigneur n'a jamais observe.
	sonde.proprietes[CHAMP_RESONANCE] = 7.0
	var filtre := Croyance.filtrer(consigneur, [_perception(sonde)], _catalogue())
	v.v(not filtre[0].chose.proprietes.has(CHAMP_RESONANCE),
		"un champ jamais observe doit etre ABSENT de la copie, jamais present a zero")

func _les_id_sont_conserves_dans_le_filtre(v) -> void:
	var consigneur := _consigneur("consigneur_9")
	var perceptions: Array = [
		_perception(_sonde("sonde_alpha", {CHAMP_FLUX: 12.5})),
		_perception(_sonde("sonde_beta", {CHAMP_RESONANCE: 3.0}, Vector3(40.0, 0.0, 0.0))),
	]
	Croyance.observer(consigneur, perceptions, _catalogue())
	var filtre := Croyance.filtrer(consigneur, perceptions, _catalogue())
	v.v(filtre[0].chose.id == "sonde_alpha" and filtre[1].chose.id == "sonde_beta",
		"les id doivent survivre au filtre -- l'inertie, l'engagement et les liens " +
		"personnels comparent des identites, jamais des proprietes")

func _filtrer_ne_mute_jamais_la_chose_reelle(v) -> void:
	var consigneur := _consigneur("consigneur_10")
	var sonde := _sonde("sonde_alpha", {CHAMP_FLUX: 12.5, CHAMP_NON_OBSERVABLE: 0.75})
	Croyance.observer(consigneur, [_perception(sonde)], _catalogue())
	var filtre := Croyance.filtrer(consigneur, [_perception(sonde)], _catalogue())
	filtre[0].chose.proprietes[CHAMP_FLUX] = -1.0
	v.v(sonde.proprietes[CHAMP_FLUX] == 12.5,
		"la chose rendue par filtrer doit etre un Dictionary NEUF -- muter la chose " +
		"reelle reecrirait le monde pour tous les autres percevants")
	v.v(sonde.proprietes.has(CHAMP_NON_OBSERVABLE),
		"la chose reelle doit garder tous ses champs, filtrer n'en retire jamais aucun")

func _les_champs_de_configuration_traversent_le_filtre(v) -> void:
	var consigneur := _consigneur("consigneur_11")
	var sonde := _sonde("sonde_alpha", {
		CHAMP_FLUX: 12.5,
		CHAMP_CONFIG: "balise_lointaine",
		CHAMP_NON_OBSERVABLE: 0.75,
	})
	Croyance.observer(consigneur, [_perception(sonde)], _catalogue())
	var filtre := Croyance.filtrer(consigneur, [_perception(sonde)], _catalogue())
	var crues: Dictionary = filtre[0].chose.proprietes
	v.v(crues.get(CHAMP_CONFIG, "") == "balise_lointaine",
		"un champ de proprietes_conservees doit traverser le filtre tel quel -- un " +
		"pointeur de catalogue n'est objet d'aucune croyance")
	v.v(not crues.has(CHAMP_NON_OBSERVABLE),
		"un champ ni observable ni conserve doit rester absent du filtre")

func _sans_catalogue_le_filtre_est_un_remplacement_strict(v) -> void:
	var consigneur := _consigneur("consigneur_12")
	var sonde := _sonde("sonde_alpha", {CHAMP_FLUX: 12.5, CHAMP_CONFIG: "balise_lointaine"})
	Croyance.observer(consigneur, [_perception(sonde)], _catalogue())
	var filtre := Croyance.filtrer(consigneur, [_perception(sonde)])
	v.v(filtre[0].chose.proprietes.has(CHAMP_FLUX),
		"sans catalogue, la valeur crue reste rendue")
	v.v(not filtre[0].chose.proprietes.has(CHAMP_CONFIG),
		"sans catalogue, AUCUN champ n'est conserve -- remplacement strict, point neutre")

func _un_consigneur_sans_croyance_voit_des_choses_sans_propriete(v) -> void:
	var consigneur := _consigneur("consigneur_13")
	var perceptions: Array = [
		_perception(_sonde("sonde_alpha", {CHAMP_FLUX: 12.5})),
		_perception(_sonde("sonde_beta", {CHAMP_RESONANCE: 3.0}, Vector3(40.0, 0.0, 0.0))),
	]
	var filtre := Croyance.filtrer(consigneur, perceptions, _catalogue())
	v.v(filtre.size() == 2,
		"une entite sans aucune croyance voit toujours ce que ses canaux captent")
	for entree in filtre:
		v.v(entree.chose.proprietes.is_empty(),
			"sans croyance, chaque chose est rendue SANS AUCUNE propriete : le monde " +
			"est la, il n'est pas interprete")

# ---- corriger ----

func _corriger_met_a_jour_si_la_certitude_est_sous_la_resistance(v) -> void:
	var consigneur := _consigneur("consigneur_14", {
		"sonde_alpha": {CHAMP_FLUX: {"valeur": 12.5, "certitude": 0.5}},
	})
	Croyance.corriger(consigneur, "sonde_alpha", CHAMP_FLUX, 40.0, 1.0, _catalogue())
	var champ: Dictionary = consigneur.proprietes.croyances["sonde_alpha"][CHAMP_FLUX]
	v.v(champ.valeur == 40.0, "sous la resistance, la correction doit ecrire la valeur reelle")
	v.v(is_equal_approx(champ.certitude, 0.8),
		"la certitude doit etre ECRASEE par gain_par_echec x credibilite (0.8 x 1.0)")

func _corriger_est_ignore_si_la_certitude_atteint_la_resistance(v) -> void:
	var consigneur := _consigneur("consigneur_15", {
		"sonde_alpha": {CHAMP_FLUX: {"valeur": 12.5, "certitude": 0.95}},
	})
	Croyance.corriger(consigneur, "sonde_alpha", CHAMP_FLUX, 40.0, 1.0, _catalogue())
	var champ: Dictionary = consigneur.proprietes.croyances["sonde_alpha"][CHAMP_FLUX]
	v.v(champ.valeur == 12.5,
		"au-dela de resistance_par_certitude, la correction doit etre IGNOREE -- le dogme resiste")
	v.v(is_equal_approx(champ.certitude, 0.95),
		"une correction ignoree ne doit toucher NI la valeur NI la certitude")

func _la_credibilite_module_le_gain_de_correction(v) -> void:
	var faible := _consigneur("consigneur_16", {
		"sonde_alpha": {CHAMP_FLUX: {"valeur": 12.5, "certitude": 0.5}},
	})
	var fort := _consigneur("consigneur_17", {
		"sonde_alpha": {CHAMP_FLUX: {"valeur": 12.5, "certitude": 0.5}},
	})
	Croyance.corriger(faible, "sonde_alpha", CHAMP_FLUX, 40.0, 0.25, _catalogue())
	Croyance.corriger(fort, "sonde_alpha", CHAMP_FLUX, 40.0, 1.0, _catalogue())
	var certitude_faible: float = faible.proprietes.croyances["sonde_alpha"][CHAMP_FLUX].certitude
	var certitude_forte: float = fort.proprietes.croyances["sonde_alpha"][CHAMP_FLUX].certitude
	v.v(is_equal_approx(certitude_faible, 0.2), "credibilite 0.25 doit donner 0.8 x 0.25")
	v.v(certitude_forte > certitude_faible,
		"une source credible doit laisser une croyance plus assuree qu'une source douteuse")

func _corriger_cree_une_croyance_jamais_observee(v) -> void:
	var consigneur := _consigneur("consigneur_18")
	Croyance.corriger(consigneur, "sonde_gamma", CHAMP_RESONANCE, 7.0, 1.0, _catalogue())
	var croyances: Dictionary = consigneur.proprietes.croyances
	v.v(croyances.has("sonde_gamma") and croyances["sonde_gamma"].has(CHAMP_RESONANCE),
		"corriger doit CREER la croyance absente -- on apprend d'un tiers ce qu'on n'a jamais vu")
	v.v(croyances["sonde_gamma"][CHAMP_RESONANCE].valeur == 7.0,
		"la croyance creee doit porter la valeur transmise")

# ---- avancer ----

func _avancer_fait_decroitre_la_certitude(v) -> void:
	var consigneur := _consigneur("consigneur_19", {
		"sonde_alpha": {CHAMP_FLUX: {"valeur": 12.5, "certitude": 0.5}},
	})
	Croyance.avancer(consigneur, 10.0, _catalogue())
	var certitude: float = consigneur.proprietes.croyances["sonde_alpha"][CHAMP_FLUX].certitude
	v.v(is_equal_approx(certitude, 0.4),
		"la certitude doit decroitre de taux_decroissance * delta (0.01 * 10.0)")

func _une_entree_sous_le_plancher_est_retiree(v) -> void:
	var consigneur := _consigneur("consigneur_20", {
		"sonde_alpha": {
			CHAMP_FLUX: {"valeur": 12.5, "certitude": 0.06},
			CHAMP_RESONANCE: {"valeur": 3.0, "certitude": 0.9},
		},
	})
	Croyance.avancer(consigneur, 5.0, _catalogue())
	var par_chose: Dictionary = consigneur.proprietes.croyances["sonde_alpha"]
	v.v(not par_chose.has(CHAMP_FLUX),
		"une certitude tombee sous plancher_suppression doit retirer le champ, jamais " +
		"le laisser a une valeur residuelle")
	v.v(par_chose.has(CHAMP_RESONANCE),
		"un champ encore au-dessus du plancher ne doit pas partir avec son voisin")

func _une_chose_devenue_vide_est_retiree_a_son_tour(v) -> void:
	var consigneur := _consigneur("consigneur_21", {
		"sonde_alpha": {CHAMP_FLUX: {"valeur": 12.5, "certitude": 0.06}},
	})
	Croyance.avancer(consigneur, 5.0, _catalogue())
	v.v(not consigneur.proprietes.croyances.has("sonde_alpha"),
		"une chose dont tous les champs sont oublies doit disparaitre du registre, " +
		"jamais rester en coquille vide")

# ---- contrats ----

func _propriete_structurelle_absente_alarme_sur_les_quatre(v) -> void:
	var nu := {"id": "consigneur_22", "position": Vector3.ZERO, "proprietes": {}}
	var sonde := _sonde("sonde_alpha", {CHAMP_FLUX: 12.5})
	Croyance.observer(nu, [_perception(sonde)], _catalogue())
	v.v(not nu.proprietes.has("croyances"),
		"observer sur une entite sans cle structurelle 'croyances' ne doit rien ecrire")
	var filtre := Croyance.filtrer(nu, [_perception(sonde)], _catalogue())
	v.v(filtre.is_empty(), "filtrer sans cle structurelle doit alarmer et rendre []")
	Croyance.corriger(nu, "sonde_alpha", CHAMP_FLUX, 40.0, 1.0, _catalogue())
	v.v(not nu.proprietes.has("croyances"), "corriger sans cle structurelle ne doit rien ecrire")
	Croyance.avancer(nu, 1.0, _catalogue())
	v.v(not nu.proprietes.has("croyances"), "avancer sans cle structurelle ne doit rien ecrire")
	# Catalogue sans proprietes_observables : alarme, aucune ecriture.
	var equipe := _consigneur("consigneur_23")
	Croyance.observer(equipe, [_perception(sonde)], {})
	v.v(equipe.proprietes.croyances.is_empty(),
		"un catalogue sans 'proprietes_observables' doit alarmer et laisser le registre intact")

# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# proprietes.croyances ne doit porter que du JSON pur et redonner exactement
# la meme structure apres un aller-retour stringify/parse_string.
func _resumabilite_json_stricte(v) -> void:
	var consigneur := _consigneur("consigneur_24")
	consigneur.proprietes["position"] = {"x": 1.0, "y": 0.0, "z": 2.0}
	var sonde := _sonde("sonde_alpha", {CHAMP_FLUX: 12.5, CHAMP_RESONANCE: 3.0})
	Croyance.observer(consigneur, [_perception(sonde)], _catalogue())
	Croyance.avancer(consigneur, 1.0, _catalogue())
	Croyance.corriger(consigneur, "sonde_alpha", CHAMP_RESONANCE, 9.0, 1.0, _catalogue())
	var relu: Variant = JSON.parse_string(JSON.stringify(consigneur))
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	var avant: Dictionary = consigneur.proprietes.croyances["sonde_alpha"]
	var apres: Dictionary = relu.proprietes.croyances["sonde_alpha"]
	v.v(is_equal_approx(float(apres[CHAMP_FLUX].certitude), float(avant[CHAMP_FLUX].certitude)),
		"la certitude doit survivre identique a l'aller-retour JSON")
	v.v(float(apres[CHAMP_RESONANCE].valeur) == 9.0,
		"la valeur crue doit survivre identique a l'aller-retour JSON")
	v.v(relu.proprietes.position.x == 1.0 and relu.proprietes.position.z == 2.0,
		"une position deja serialisee en {x,y,z} doit survivre identique, jamais un Vector3")
