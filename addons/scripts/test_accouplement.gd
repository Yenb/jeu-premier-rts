extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_accouplement.gd
#
# Verrouille scripts/accouplement.gd comme mecanisme GENERIQUE d'accumulation
# d'exposition entre deux individus matures et compatibles, jusqu'a un seuil
# qui pose un etat de gestation IRREVERSIBLE sur les seuls individus que leur
# role_gestation autorise a porter -- pas un code de
# colon. Domaine invente (cristal_gravitique_*, jamais vu ailleurs dans le
# depot, meme famille que test_stade.gd/test_senescence.gd) : ce test prouve
# que avancer() traverse le meme code quel que soit le domaine.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque (le
# catalogue de reproduction est un Dictionary construit ici, jamais
# data/reproduction.json).

const Accouplement = preload("res://scripts/accouplement.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_immatures_ne_produisent_rien(v)
	_incompatibles_ne_produisent_rien(v)
	_mode_reproduction_non_sexuee_ne_produit_rien(v)
	_exposition_sous_seuil_ne_produit_rien(v)
	_seuil_franchi_pose_gestation_sur_les_porteurs_avec_genes_copies(v)
	_seul_le_role_de_gestation_decide_qui_porte(v)
	_deja_en_gestation_ignore(v)
	_proprietes_structurelles_absentes_alarme(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: accouplement.gd accumule une exposition entre deux individus matures et compatibles " +
			"et pose un etat de gestation irreversible au seuil sur les seuls porteurs declares en donnee, generique a tout domaine invente")
		quit(0)

func _cristal(id: String, stade: String, espece: String = "gravitique", ref: String = "gravitique_fusion", genes: Dictionary = {}, role: String = "les_deux") -> Dictionary:
	return {
		"id": id,
		"position": Vector3.ZERO,
		"proprietes": {
			"mode_reproduction": "sexuee",
			"espece_reproduction": espece,
			"stades_fertiles": ["mature"],
			"stade": stade,
			"reproduction_ref": ref,
			"role_gestation": role,
			"genes_etat": genes,
			"marques_epigenetiques": {},
		},
	}

func _percue(chose: Dictionary) -> Dictionary:
	return {"chose": chose}

func _catalogue(seuil: float = 1.0, taux: float = 0.5) -> Dictionary:
	return {"gravitique_fusion": {"seuil_accouplement": seuil, "taux_montee": taux}}

func _immatures_ne_produisent_rien(v) -> void:
	var a := _cristal("cristal_1", "jeune")
	var b := _cristal("cristal_2", "jeune")
	for i in 10:
		Accouplement.avancer(a, [_percue(b)], _catalogue(), 1.0, 1)
	v.v(not a.proprietes.has("gestation"), "deux cristaux immatures ne doivent jamais entrer en gestation")

func _incompatibles_ne_produisent_rien(v) -> void:
	var a := _cristal("cristal_3", "mature", "gravitique")
	var b := _cristal("cristal_4", "mature", "electrique")
	for i in 10:
		Accouplement.avancer(a, [_percue(b)], _catalogue(), 1.0, 1)
	v.v(not a.proprietes.has("gestation"), "deux especes de reproduction differentes ne doivent jamais entrer en gestation, meme matures")

func _mode_reproduction_non_sexuee_ne_produit_rien(v) -> void:
	var a := _cristal("cristal_5", "mature")
	a.proprietes.mode_reproduction = "asexuee"
	var b := _cristal("cristal_6", "mature")
	for i in 10:
		Accouplement.avancer(a, [_percue(b)], _catalogue(), 1.0, 1)
	v.v(not a.proprietes.has("gestation") and not a.proprietes.has("accouplement_accumulateur"),
		"mode_reproduction different de 'sexuee' doit sauter la phase entierement, aucune accumulation")

func _exposition_sous_seuil_ne_produit_rien(v) -> void:
	var a := _cristal("cristal_7", "mature")
	var b := _cristal("cristal_8", "mature")
	# seuil 1.0, taux 0.1 : 3 appels de 1.0s = 0.3, largement sous le seuil.
	for i in 3:
		Accouplement.avancer(a, [_percue(b)], _catalogue(1.0, 0.1), 1.0, 1)
	v.v(not a.proprietes.has("gestation"), "une exposition qui n'atteint pas le seuil ne doit jamais poser de gestation")
	v.v(is_equal_approx(a.proprietes.accouplement_accumulateur.get("cristal_8", 0.0), 0.3),
		"l'accumulateur doit refleter exactement taux_montee * delta cumule")

func _seuil_franchi_pose_gestation_sur_les_porteurs_avec_genes_copies(v) -> void:
	var genes_a := {"resonance_gravitique": {"alleles": [0.5, 0.5]}}
	var genes_b := {"resonance_gravitique": {"alleles": [0.1, 0.9]}}
	var a := _cristal("cristal_9", "mature", "gravitique", "gravitique_fusion", genes_a)
	var b := _cristal("cristal_10", "mature", "gravitique", "gravitique_fusion", genes_b)
	# seuil 1.0, taux 0.5 : 3 appels de 1.0s franchissent au deuxieme (1.0).
	for i in 3:
		Accouplement.avancer(a, [_percue(b)], _catalogue(1.0, 0.5), 1.0, 42)

	# Les deux portent ici "les_deux" (hermaphrodites) : les deux gestent, et
	# ce sont bien deux pontes, jamais un doublon. Le cas d'un seul porteur
	# est verrouille plus bas.
	v.v(a.proprietes.has("gestation"), "le franchissement du seuil doit poser gestation sur l'entite avancee")
	v.v(b.proprietes.has("gestation"), "le partenaire percu porteur doit gester aussi (meme reference que le monde)")
	v.v(a.proprietes.gestation.partenaire_id == "cristal_10", "gestation.partenaire_id doit nommer le partenaire")
	v.v(b.proprietes.gestation.partenaire_id == "cristal_9", "gestation.partenaire_id du partenaire doit nommer l'entite avancee en retour")
	v.v(a.proprietes.gestation.accouplement_tick == 42, "accouplement_tick doit porter la valeur recue de l'appelant, jamais une horloge interne")
	v.v(a.proprietes.gestation.partenaire_genes_etat.resonance_gravitique.alleles == [0.1, 0.9],
		"gestation.partenaire_genes_etat doit porter une copie des genes DU PARTENAIRE, pas des siens")
	v.v(b.proprietes.gestation.partenaire_genes_etat.resonance_gravitique.alleles == [0.5, 0.5],
		"gestation.partenaire_genes_etat du partenaire doit porter une copie des genes de l'entite avancee")

	# Copie PROFONDE, jamais une reference partagee : muter les genes vivants
	# de b apres coup ne doit jamais affecter la copie deja figee dans a.
	b.proprietes.genes_etat.resonance_gravitique.alleles[0] = 999.0
	v.v(a.proprietes.gestation.partenaire_genes_etat.resonance_gravitique.alleles[0] == 0.1,
		"la copie de genes dans gestation doit etre PROFONDE (duplicate(true)), jamais une reference qui suit l'etat vivant du partenaire")

# HORS DOMAINE. La fecondation est symetrique, la gestation ne l'est pas :
# c'est la DONNEE de chaque entite qui dit si elle porte, jamais une
# convention de l'appelant ni un departage entre les deux. Sans cette regle,
# un couple a sexes separes rend DEUX gestations donc deux enfants d'un seul
# accouplement, et chaque banc doit designer un porteur a la main, hors du
# mecanisme.
func _seul_le_role_de_gestation_decide_qui_porte(v) -> void:
	var porteur := _cristal("cristal_20", "mature", "gravitique", "gravitique_fusion", {}, "porteur")
	var autre := _cristal("cristal_21", "mature", "gravitique", "gravitique_fusion", {}, "non_porteur")
	for i in 3:
		Accouplement.avancer(porteur, [_percue(autre)], _catalogue(1.0, 0.5), 1.0, 7)
	v.v(porteur.proprietes.has("gestation"), "le 'porteur' doit gester")
	v.v(not autre.proprietes.has("gestation"), "le 'non_porteur' ne doit JAMAIS gester, meme feconde")

	# Symetrique : que l'entite avancee soit celle qui porte ou non ne change
	# rien -- la decision est locale a chacun, pas relative a qui appelle.
	var porteur_b := _cristal("cristal_22", "mature", "gravitique", "gravitique_fusion", {}, "porteur")
	var autre_b := _cristal("cristal_23", "mature", "gravitique", "gravitique_fusion", {}, "non_porteur")
	for i in 3:
		Accouplement.avancer(autre_b, [_percue(porteur_b)], _catalogue(1.0, 0.5), 1.0, 7)
	v.v(porteur_b.proprietes.has("gestation"), "le porteur PERCU doit gester, meme si c'est l'autre qu'on avance")
	v.v(not autre_b.proprietes.has("gestation"), "l'entite avancee non porteuse ne geste pas davantage")

	var sans_role := _cristal("cristal_24", "mature", "gravitique", "gravitique_fusion", {}, "")
	var sans_role_2 := _cristal("cristal_25", "mature", "gravitique", "gravitique_fusion", {}, "")
	for i in 3:
		Accouplement.avancer(sans_role, [_percue(sans_role_2)], _catalogue(1.0, 0.5), 1.0, 7)
	v.v(not sans_role.proprietes.has("gestation") and not sans_role_2.proprietes.has("gestation"),
		"role absent : personne ne geste -- le defaut ne fabrique jamais une naissance")

func _deja_en_gestation_ignore(v) -> void:
	var a := _cristal("cristal_11", "mature")
	a.proprietes["gestation"] = {"partenaire_id": "quelqu_un_dautre", "partenaire_genes_etat": {}, "partenaire_marques_epigenetiques": {}, "accouplement_tick": 0}
	var b := _cristal("cristal_12", "mature")
	Accouplement.avancer(a, [_percue(b)], _catalogue(0.0, 999.0), 1.0, 5)
	v.v(a.proprietes.gestation.partenaire_id == "quelqu_un_dautre",
		"une entite deja en gestation ne doit jamais accumuler ni ecraser sa gestation existante, meme avec un seuil deja franchissable")
	v.v(not b.proprietes.has("gestation"),
		"une entite deja en gestation ne doit jamais faire entrer un partenaire percu en gestation a sa place")

func _proprietes_structurelles_absentes_alarme(v) -> void:
	var b := _cristal("cristal_13", "mature")

	var sans_ref := _cristal("cristal_14", "mature")
	sans_ref.proprietes.erase("reproduction_ref")
	Accouplement.avancer(sans_ref, [_percue(b)], _catalogue(), 1.0, 1)
	v.v(not sans_ref.proprietes.has("gestation") and not sans_ref.proprietes.has("accouplement_accumulateur"),
		"reproduction_ref absente (mode_reproduction sexuee) doit alarmer et ne rien ecrire")

	var sans_espece := _cristal("cristal_15", "mature")
	sans_espece.proprietes.erase("espece_reproduction")
	Accouplement.avancer(sans_espece, [_percue(b)], _catalogue(), 1.0, 1)
	v.v(not sans_espece.proprietes.has("gestation") and not sans_espece.proprietes.has("accouplement_accumulateur"),
		"espece_reproduction absente (mode_reproduction sexuee) doit alarmer et ne rien ecrire")

	var sans_stades := _cristal("cristal_16", "mature")
	sans_stades.proprietes.erase("stades_fertiles")
	Accouplement.avancer(sans_stades, [_percue(b)], _catalogue(), 1.0, 1)
	v.v(not sans_stades.proprietes.has("gestation") and not sans_stades.proprietes.has("accouplement_accumulateur"),
		"stades_fertiles absente (mode_reproduction sexuee) doit alarmer et ne rien ecrire")

	# Clé PRESENTE mais qui ne resout nulle part : chemin distinct des trois
	# ci-dessus, et le seul qui laisse le mecanisme croire qu'il a sa regle.
	var ref_morte := _cristal("cristal_17", "mature")
	ref_morte.proprietes["reproduction_ref"] = "entree_inexistante"
	Accouplement.avancer(ref_morte, [_percue(b)], _catalogue(), 1.0, 1)
	v.v(not ref_morte.proprietes.has("gestation") and not ref_morte.proprietes.has("accouplement_accumulateur"),
		"reproduction_ref absente du catalogue doit alarmer et ne rien ecrire, jamais un seuil devine")

func _resumabilite_json_stricte(v) -> void:
	var a := _cristal("cristal_17", "mature", "gravitique", "gravitique_fusion", {"resonance_gravitique": {"alleles": [0.2, 0.4]}})
	var b := _cristal("cristal_18", "mature")
	for i in 3:
		Accouplement.avancer(a, [_percue(b)], _catalogue(1.0, 0.5), 1.0, 7)
	var texte := JSON.stringify(a)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	v.v(relu.proprietes.gestation.partenaire_id == "cristal_18",
		"gestation doit survivre identique a l'aller-retour JSON")
	v.v(relu.proprietes.gestation.accouplement_tick == 7,
		"accouplement_tick doit survivre identique a l'aller-retour JSON")
