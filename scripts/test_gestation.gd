extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_gestation.gd
#
# Verrouille scripts/gestation.gd comme mecanisme GENERIQUE de troisieme
# phase du cycle de reproduction : un compteur qui avance depuis une
# gestation deja posee (par accouplement.gd ou par poser() ci-dessous)
# jusqu'a un seuil qui pose naissance_prete -- pas un code de colon.
# Domaine invente (cristal_gravitique_*, meme famille que
# test_accouplement.gd/test_stade.gd/test_senescence.gd) : ce test prouve
# que avancer()/poser() traversent le meme code quel que soit le domaine.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque (le
# catalogue de reproduction est un Dictionary construit ici, jamais
# data/reproduction.json).

const Gestation = preload("res://scripts/gestation.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_sans_gestation_avancer_ne_fait_rien(v)
	_avancer_incremente_le_compteur_depuis_zero(v)
	_flag_pose_exactement_au_seuil_franchi(v)
	_pas_de_double_flag_apres_franchissement(v)
	_avancer_alarme_si_duree_gestation_absente_du_catalogue(v)
	_avancer_alarme_si_reference_absente_du_catalogue(v)
	_avancer_alarme_si_reproduction_ref_absente(v)
	_poser_asexuee_copie_ses_propres_genes(v)
	_poser_parthenogenese_dictionnaire_partiel(v)
	_poser_ignore_une_entite_deja_en_gestation(v)
	_poser_alarme_si_reproduction_ref_absente(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: gestation.gd fait avancer un compteur depuis une gestation posee " +
			"et pose naissance_prete au seuil, generique a tout domaine invente")
		quit(0)

func _cristal(id: String, ref: String = "gravitique_fusion", genes: Dictionary = {}, marques: Dictionary = {}) -> Dictionary:
	return {
		"id": id,
		"position": Vector3.ZERO,
		"proprietes": {
			"reproduction_ref": ref,
			"genes_etat": genes,
			"marques_epigenetiques": marques,
		},
	}

func _catalogue(duree: float = 10.0, seuil: float = 1.0, taux: float = 0.5) -> Dictionary:
	return {"gravitique_fusion": {"seuil_accouplement": seuil, "taux_montee": taux, "duree_gestation": duree}}

func _sans_gestation_avancer_ne_fait_rien(v) -> void:
	var e := _cristal("cristal_1")
	Gestation.avancer(e, _catalogue(), 1.0)
	v.v(not e.proprietes.has("gestation"), "une entite sans gestation ne doit jamais en recevoir une par avancer()")

func _avancer_incremente_le_compteur_depuis_zero(v) -> void:
	var e := _cristal("cristal_2")
	e.proprietes["gestation"] = {"partenaire_id": "cristal_3", "partenaire_genes_etat": {}, "partenaire_marques_epigenetiques": {}, "accouplement_tick": 5}
	Gestation.avancer(e, _catalogue(10.0), 2.5)
	v.v(is_equal_approx(e.proprietes.gestation.duree_gestation_ecoulee, 2.5),
		"le premier avancer doit initialiser duree_gestation_ecoulee a 0.0 puis l'incrementer exactement de delta")
	Gestation.avancer(e, _catalogue(10.0), 1.5)
	v.v(is_equal_approx(e.proprietes.gestation.duree_gestation_ecoulee, 4.0),
		"un second avancer doit accumuler, jamais repartir de zero")
	v.v(not e.proprietes.gestation.has("naissance_prete"),
		"sous le seuil, naissance_prete ne doit jamais etre pose")

func _flag_pose_exactement_au_seuil_franchi(v) -> void:
	var e := _cristal("cristal_4")
	e.proprietes["gestation"] = {"partenaire_id": "cristal_5", "partenaire_genes_etat": {}, "partenaire_marques_epigenetiques": {}, "accouplement_tick": 0}
	Gestation.avancer(e, _catalogue(5.0), 4.0)
	v.v(not e.proprietes.gestation.get("naissance_prete", false), "sous le seuil (4.0 < 5.0), aucun flag")
	Gestation.avancer(e, _catalogue(5.0), 1.0)
	v.v(e.proprietes.gestation.get("naissance_prete", false) == true,
		"au franchissement exact du seuil (5.0 >= 5.0), naissance_prete doit passer a true")
	v.v(not e.proprietes.has("id_enfant") and e.proprietes.has("gestation"),
		"gestation.gd ne doit jamais retirer gestation ni creer quoi que ce soit d'autre")

func _pas_de_double_flag_apres_franchissement(v) -> void:
	var e := _cristal("cristal_6")
	e.proprietes["gestation"] = {"partenaire_id": "cristal_7", "partenaire_genes_etat": {}, "partenaire_marques_epigenetiques": {}, "accouplement_tick": 0, "duree_gestation_ecoulee": 9.0, "naissance_prete": true}
	Gestation.avancer(e, _catalogue(5.0), 100.0)
	v.v(is_equal_approx(e.proprietes.gestation.duree_gestation_ecoulee, 9.0),
		"une fois naissance_prete deja pose, avancer ne doit plus rien incrementer -- idempotent")
	v.v(e.proprietes.gestation.naissance_prete == true, "le flag doit rester true, jamais retire par ce fichier")

func _avancer_alarme_si_duree_gestation_absente_du_catalogue(v) -> void:
	var e := _cristal("cristal_8")
	e.proprietes["gestation"] = {"partenaire_id": "cristal_9", "partenaire_genes_etat": {}, "partenaire_marques_epigenetiques": {}, "accouplement_tick": 0}
	var catalogue := {"gravitique_fusion": {"seuil_accouplement": 1.0, "taux_montee": 0.5}}
	Gestation.avancer(e, catalogue, 1.0)
	v.v(not e.proprietes.gestation.has("duree_gestation_ecoulee"),
		"une entree de catalogue sans 'duree_gestation' doit alarmer et ne rien incrementer, jamais un defaut 0.0 silencieux")

func _avancer_alarme_si_reference_absente_du_catalogue(v) -> void:
	var e := _cristal("cristal_10", "reference_inconnue")
	e.proprietes["gestation"] = {"partenaire_id": "cristal_11", "partenaire_genes_etat": {}, "partenaire_marques_epigenetiques": {}, "accouplement_tick": 0}
	Gestation.avancer(e, _catalogue(), 1.0)
	v.v(not e.proprietes.gestation.has("duree_gestation_ecoulee"),
		"une reproduction_ref absente du catalogue doit alarmer sans rien ecrire")

func _avancer_alarme_si_reproduction_ref_absente(v) -> void:
	var e := {"id": "cristal_12", "position": Vector3.ZERO, "proprietes": {"gestation": {"partenaire_id": "cristal_13", "partenaire_genes_etat": {}, "partenaire_marques_epigenetiques": {}, "accouplement_tick": 0}}}
	Gestation.avancer(e, _catalogue(), 1.0)
	v.v(not e.proprietes.gestation.has("duree_gestation_ecoulee"),
		"propriete structurelle 'reproduction_ref' absente doit alarmer sans rien ecrire, meme avec une gestation en cours")

func _poser_asexuee_copie_ses_propres_genes(v) -> void:
	var e := _cristal("cristal_14", "gravitique_fusion", {"resonance_gravitique": {"alleles": [0.3, 0.7]}}, {"exposition_gravitique": {"modulateur": 0.2, "age_marque": 1.0}})
	Gestation.poser(e, null, _catalogue())
	v.v(e.proprietes.has("gestation"), "poser doit poser gestation en mode asexuee (partenaire_data null)")
	v.v(e.proprietes.gestation.partenaire_id == "cristal_14",
		"en mode asexuee, partenaire_id doit nommer l'entite elle-meme -- elle est sa propre source")
	v.v(e.proprietes.gestation.partenaire_genes_etat.resonance_gravitique.alleles == [0.3, 0.7],
		"en mode asexuee, partenaire_genes_etat doit etre une copie des genes DE L'ENTITE elle-meme")
	e.proprietes.genes_etat.resonance_gravitique.alleles[0] = 999.0
	v.v(e.proprietes.gestation.partenaire_genes_etat.resonance_gravitique.alleles[0] == 0.3,
		"la copie posee par poser() doit etre PROFONDE (duplicate(true)), jamais une reference qui suit l'etat vivant")

func _poser_parthenogenese_dictionnaire_partiel(v) -> void:
	var e := _cristal("cristal_15", "gravitique_fusion", {"resonance_gravitique": {"alleles": [0.1, 0.9]}})
	Gestation.poser(e, {"id": "parthenogenese"}, _catalogue())
	v.v(e.proprietes.gestation.partenaire_id == "parthenogenese",
		"un Dictionary partiel doit pouvoir surcharger l'id seul (cle 'id', a plat, meme vocabulaire que 'chose' cote accouplement.gd)")
	v.v(e.proprietes.gestation.partenaire_genes_etat.resonance_gravitique.alleles == [0.1, 0.9],
		"une cle absente du Dictionary partiel (genes_etat) doit retomber sur les propres genes de l'entite")

func _poser_ignore_une_entite_deja_en_gestation(v) -> void:
	var e := _cristal("cristal_16")
	e.proprietes["gestation"] = {"partenaire_id": "quelqu_un_dautre", "partenaire_genes_etat": {}, "partenaire_marques_epigenetiques": {}, "accouplement_tick": 0}
	Gestation.poser(e, null, _catalogue())
	v.v(e.proprietes.gestation.partenaire_id == "quelqu_un_dautre",
		"une entite deja en gestation ne doit jamais voir sa gestation ecrasee par poser()")

func _poser_alarme_si_reproduction_ref_absente(v) -> void:
	var e := {"id": "cristal_17", "position": Vector3.ZERO, "proprietes": {"genes_etat": {}, "marques_epigenetiques": {}}}
	Gestation.poser(e, null, _catalogue())
	v.v(not e.proprietes.has("gestation"),
		"proprietes sans la cle structurelle 'reproduction_ref' ne doit rien ecrire (alarme, pas defaut silencieux)")

	# Cle PRESENTE mais qui ne resout nulle part : poser() a sa propre garde,
	# distincte de celle d'avancer(). Sans elle, une gestation naitrait sans
	# duree et l'entite accoucherait au premier appel.
	var ref_morte := {"id": "cristal_18", "position": Vector3.ZERO,
		"proprietes": {"genes_etat": {}, "marques_epigenetiques": {}, "reproduction_ref": "entree_inexistante"}}
	Gestation.poser(ref_morte, null, _catalogue())
	v.v(not ref_morte.proprietes.has("gestation"),
		"reproduction_ref absente du catalogue doit alarmer et ne poser aucune gestation")

func _resumabilite_json_stricte(v) -> void:
	var e := {
		"id": "cristal_18",
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"proprietes": {"reproduction_ref": "gravitique_fusion", "genes_etat": {}, "marques_epigenetiques": {}},
	}
	Gestation.poser(e, null, _catalogue())
	Gestation.avancer(e, _catalogue(5.0), 6.0)
	var texte := JSON.stringify(e)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	v.v(relu.proprietes.gestation.naissance_prete == true,
		"naissance_prete doit survivre identique a l'aller-retour JSON")
	v.v(is_equal_approx(relu.proprietes.gestation.duree_gestation_ecoulee, 6.0),
		"duree_gestation_ecoulee doit survivre identique a l'aller-retour JSON")
