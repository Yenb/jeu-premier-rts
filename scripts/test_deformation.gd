extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_deformation.gd
#
# Verrouille scripts/deformation.gd comme mecanisme GENERIQUE de biais
# accumule par exposition -- pas un code de peur, de trauma ni
# d'habituation. Source/cible hors domaine (gravitique/masse, jamais vu
# ailleurs dans le depot) : ce test prouve que poser/avancer/biais
# traversent le meme code quel que soit le domaine.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque
# (le catalogue est un Dictionary construit ici, jamais data/deformations.json).
#
# FORME A (chantier "un seul patron de reference de catalogue", session
# ulterieure) : les fixtures de ce fichier portent desormais
# "deformation_sources" (Array de String, structurelle) et
# "deformation_etat" (Dictionary [source][cible] = {rapide, lent},
# structurelle) au lieu de l'ancien champ unique "deformation" (forme B).

const Deformation = preload("res://scripts/deformation.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_poser_cree_la_structure_imbriquee_et_incremente_les_deux_registres(v)
	_poser_accumule_sur_une_structure_deja_posee(v)
	_poser_alarme_sur_source_non_declaree_dans_deformation_sources(v)
	_avancer_decroit_les_deux_registres_differemment(v)
	_avancer_ne_descend_jamais_sous_zero(v)
	_avancer_alarme_sur_source_absente_du_catalogue(v)
	_biais_rend_la_valeur_ponderee_attendue(v)
	_biais_neutre_sans_exposition_posee(v)
	_propriete_structurelle_absente_alarme(v)
	_biais_alarme_sur_source_absente_du_catalogue(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: deformation.gd pose/avance/lit un biais accumule par exposition sur deux " +
			"registres rapide/lent, generique a tout domaine invente")
		quit(0)

func _entite(id: String, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _catalogue() -> Dictionary:
	return {
		"gravitique": {
			"sens": "monte",
			"taux_decroissance_rapide": 0.5,
			"taux_decroissance_lent": 0.02,
			"w_rapide": 0.3,
			"w_lent": 0.7,
		},
	}

func _poser_cree_la_structure_imbriquee_et_incremente_les_deux_registres(v) -> void:
	var caillou := _entite("caillou_1", {"deformation_sources": ["gravitique"], "deformation_etat": {}})
	Deformation.poser(caillou, "gravitique", "masse", 4.0)
	var d: Dictionary = caillou.proprietes.deformation_etat
	v.v(d.has("gravitique"), "poser doit creer la source dans proprietes.deformation_etat")
	v.v(d.gravitique.has("masse"), "poser doit creer la cible sous la source")
	v.v(d.gravitique.masse.rapide == 4.0, "poser doit incrementer le registre rapide de magnitude")
	v.v(d.gravitique.masse.lent == 4.0, "poser doit incrementer le registre lent de magnitude")

func _poser_accumule_sur_une_structure_deja_posee(v) -> void:
	var caillou := _entite("caillou_2", {"deformation_sources": ["gravitique"], "deformation_etat": {}})
	Deformation.poser(caillou, "gravitique", "masse", 4.0)
	Deformation.poser(caillou, "gravitique", "masse", 3.0)
	var canal: Dictionary = caillou.proprietes.deformation_etat.gravitique.masse
	v.v(canal.rapide == 7.0, "poser repete doit accumuler sur le registre rapide deja present")
	v.v(canal.lent == 7.0, "poser repete doit accumuler sur le registre lent deja present")

# CONTRAT NEUF (chantier "un seul patron de reference de catalogue") : une
# source qui n'est pas listee dans deformation_sources n'a pas a recevoir
# d'ecriture -- deformation_sources vide ici (jamais "gravitique" ajoutee),
# poser() doit alarmer et NE RIEN ecrire, meme pas creer la source.
func _poser_alarme_sur_source_non_declaree_dans_deformation_sources(v) -> void:
	var caillou := _entite("caillou_10", {"deformation_sources": [], "deformation_etat": {}})
	Deformation.poser(caillou, "gravitique", "masse", 4.0)
	v.v(not caillou.proprietes.deformation_etat.has("gravitique"),
		"une source absente de deformation_sources ne doit jamais etre ecrite dans deformation_etat")

func _avancer_decroit_les_deux_registres_differemment(v) -> void:
	var caillou := _entite("caillou_3", {
		"deformation_sources": ["gravitique"],
		"deformation_etat": {"gravitique": {"masse": {"rapide": 10.0, "lent": 10.0}}},
	})
	Deformation.avancer(caillou, 2.0, _catalogue())
	var canal: Dictionary = caillou.proprietes.deformation_etat.gravitique.masse
	v.v(is_equal_approx(canal.rapide, 9.0), "rapide doit decroitre de taux_decroissance_rapide * delta (0.5 * 2.0)")
	v.v(is_equal_approx(canal.lent, 9.96), "lent doit decroitre de taux_decroissance_lent * delta (0.02 * 2.0)")
	v.v(canal.rapide < canal.lent, "rapide doit s'effacer plus vite que lent, meme depart, meme delta")

func _avancer_ne_descend_jamais_sous_zero(v) -> void:
	var caillou := _entite("caillou_4", {
		"deformation_sources": ["gravitique"],
		"deformation_etat": {"gravitique": {"masse": {"rapide": 0.2, "lent": 0.01}}},
	})
	Deformation.avancer(caillou, 5.0, _catalogue())
	var canal: Dictionary = caillou.proprietes.deformation_etat.gravitique.masse
	v.v(canal.rapide == 0.0, "rapide ne doit jamais descendre sous 0.0")
	v.v(canal.lent == 0.0, "lent ne doit jamais descendre sous 0.0")

func _avancer_alarme_sur_source_absente_du_catalogue(v) -> void:
	var caillou := _entite("caillou_5", {
		"deformation_sources": ["inconnue"],
		"deformation_etat": {"inconnue": {"masse": {"rapide": 5.0, "lent": 5.0}}},
	})
	Deformation.avancer(caillou, 1.0, _catalogue())
	var canal: Dictionary = caillou.proprietes.deformation_etat.inconnue.masse
	v.v(canal.rapide == 5.0, "une source absente du catalogue doit alarmer et laisser le registre intact")
	v.v(canal.lent == 5.0, "une source absente du catalogue doit alarmer et laisser le registre intact")

func _biais_rend_la_valeur_ponderee_attendue(v) -> void:
	var caillou := _entite("caillou_6", {
		"deformation_sources": ["gravitique"],
		"deformation_etat": {"gravitique": {"masse": {"rapide": 4.0, "lent": 10.0}}},
	})
	var b := Deformation.biais(caillou, "gravitique", "masse", _catalogue())
	v.v(is_equal_approx(b, 0.3 * 4.0 + 0.7 * 10.0),
		"biais doit rendre w_rapide * rapide + w_lent * lent depuis le catalogue")

func _biais_neutre_sans_exposition_posee(v) -> void:
	var caillou := _entite("caillou_7", {"deformation_sources": ["gravitique"], "deformation_etat": {}})
	var b := Deformation.biais(caillou, "gravitique", "masse", _catalogue())
	v.v(b == 0.0, "aucune exposition posee doit rendre un biais neutre, jamais une alarme")

func _propriete_structurelle_absente_alarme(v) -> void:
	var caillou := _entite("caillou_8", {})
	Deformation.poser(caillou, "gravitique", "masse", 4.0)
	v.v(not caillou.proprietes.has("deformation_etat"),
		"proprietes sans les cles structurelles 'deformation_sources'/'deformation_etat' ne doit rien ecrire (alarme, pas defaut silencieux)")
	Deformation.avancer(caillou, 1.0, _catalogue())
	var b := Deformation.biais(caillou, "gravitique", "masse", _catalogue())
	v.v(b == 0.0, "biais sur une entite sans cle 'deformation_etat' doit alarmer et rendre 0.0")

	# L'entite VIDE ci-dessus sort sur la PREMIERE garde : la seconde ne
	# serait jamais atteinte sans une entite a qui il manque exactement une
	# cle. Les deux sont structurelles, chacune doit alarmer pour son compte.
	var sans_etat := _entite("caillou_9", {"deformation_sources": ["gravitique"]})
	Deformation.poser(sans_etat, "gravitique", "masse", 4.0)
	v.v(not sans_etat.proprietes.has("deformation_etat"),
		"'deformation_etat' absente alors que 'deformation_sources' est la : alarme, aucune ecriture")

# La source est absente du CATALOGUE alors que le registre la porte
# reellement -- chemin distinct de la garde d'avancer(), et le seul par
# lequel biais() peut alarmer. Sans registre peuple, biais sort avant.
func _biais_alarme_sur_source_absente_du_catalogue(v) -> void:
	var caillou := _entite("caillou_10", {
		"deformation_sources": ["inconnue"],
		"deformation_etat": {"inconnue": {"masse": {"rapide": 5.0, "lent": 5.0}}},
	})
	v.v(Deformation.biais(caillou, "inconnue", "masse", {}) == 0.0,
		"biais sur une source absente du catalogue doit alarmer et rendre 0.0, jamais une ponderation devinee")

# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# proprietes.deformation_etat/deformation_sources ne doivent porter que du
# JSON pur -- aucun Vector3, aucun Callable -- et redonner exactement la
# meme structure apres un aller-retour JSON.stringify/parse_string.
func _resumabilite_json_stricte(v) -> void:
	var caillou := _entite("caillou_9", {
		"position": {"x": 1.0, "y": 0.0, "z": 2.0},
		"deformation_sources": ["gravitique"],
		"deformation_etat": {},
	})
	Deformation.poser(caillou, "gravitique", "masse", 4.0)
	Deformation.avancer(caillou, 1.0, _catalogue())
	var texte := JSON.stringify(caillou)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	var canal_original: Dictionary = caillou.proprietes.deformation_etat.gravitique.masse
	var canal_relu: Dictionary = relu.proprietes.deformation_etat.gravitique.masse
	v.v(is_equal_approx(canal_relu.rapide, canal_original.rapide),
		"le registre rapide doit survivre identique a l'aller-retour JSON")
	v.v(is_equal_approx(canal_relu.lent, canal_original.lent),
		"le registre lent doit survivre identique a l'aller-retour JSON")
	v.v(relu.proprietes.deformation_sources == ["gravitique"],
		"deformation_sources (Array de String) doit survivre identique a l'aller-retour JSON")
	v.v(relu.proprietes.position.x == 1.0 and relu.proprietes.position.z == 2.0,
		"une position deja serialisee en {x,y,z} doit survivre identique, jamais un Vector3")
