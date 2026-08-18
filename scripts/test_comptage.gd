extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_comptage.gd
#
# Verrouille scripts/comptage.gd comme mecanisme GENERIQUE de comptage --
# premiere brique de la couche LECTEUR (voir docs/design.md, "Les
# collectifs n'existent pas"). Domaine hors colon/faction/ville : une
# nuee de poissons inventee, jamais vue ailleurs dans le depot, prouve
# que compter() ignore tout mot du monde.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque
# (le catalogue est un Dictionary construit ici, jamais data/comptages.json).

const Comptage = preload("res://scripts/comptage.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_le_modele_ignore_le_domaine(v)
	_regle_absente_du_catalogue_alarme(v)
	_mode_inconnu_alarme_et_ne_compte_personne(v)
	_entite_sans_proprietes_ignoree(v)
	_mode_egale_ignore_les_absents(v)
	_mode_superieur_a_alarme_sur_valeur_non_numerique(v)
	_mode_contient_element_avec_champ_compte_correctement(v)
	_mode_contient_element_avec_champ_ignore_les_arrays_absents(v)
	_mode_contient_element_avec_champ_alarme_si_valeur_non_array(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: comptage.gd compte des entites selon une regle en donnee, " +
			"generique a tout domaine invente")
		quit(0)

func _poisson(id: String, proprietes: Dictionary) -> Dictionary:
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _catalogue() -> Dictionary:
	return {
		"poissons_luisants": {"propriete": "luit", "mode": "presente"},
		"poissons_rouges": {"propriete": "couleur", "mode": "egale", "valeur_reference": "rouge"},
		"poissons_lourds": {"propriete": "poids", "mode": "superieur_a", "valeur_reference": 5.0},
		"nuees_avec_oiseau_rouge": {
			"propriete": "oiseaux", "mode": "contient_element_avec_champ",
			"champ_element": "couleur", "valeur_reference": "rouge",
		},
	}

func _le_modele_ignore_le_domaine(v) -> void:
	var poissons := [
		_poisson("poisson_1", {"luit": true, "couleur": "rouge", "poids": 3.0}),
		_poisson("poisson_2", {"luit": false, "couleur": "bleu", "poids": 8.0}),
		_poisson("poisson_3", {"couleur": "rouge", "poids": 6.0}),
	]
	var catalogue := _catalogue()
	v.v(Comptage.compter(poissons, "poissons_luisants", catalogue) == 2,
		"mode presente doit compter toute entite portant la cle, quelle que soit sa valeur (luit: true ET luit: false)")
	v.v(Comptage.compter(poissons, "poissons_rouges", catalogue) == 2,
		"mode egale doit compter les entites dont la valeur egale exactement valeur_reference")
	v.v(Comptage.compter(poissons, "poissons_lourds", catalogue) == 2,
		"mode superieur_a doit compter les entites dont la valeur numerique depasse valeur_reference")

func _regle_absente_du_catalogue_alarme(v) -> void:
	var poissons := [_poisson("poisson_4", {"luit": true})]
	var compte := Comptage.compter(poissons, "regle_inexistante", _catalogue())
	v.v(compte == 0, "une regle absente du catalogue doit alarmer et rendre 0, jamais un compte devine")

# Un mode que le mecanisme ne sait pas jouer est une DONNEE CASSEE : il
# alarme et ne compte PERSONNE. Rendre le compte total serait le pire des
# deux -- un fait collectif faux, indiscernable d'un vrai.
func _mode_inconnu_alarme_et_ne_compte_personne(v) -> void:
	var catalogue := {"regle_zorg": {"propriete": "luit", "mode": "mode_inexistant"}}
	var poissons := [_poisson("poisson_z1", {"luit": true}), _poisson("poisson_z2", {"luit": true})]
	v.v(Comptage.compter(poissons, "regle_zorg", catalogue) == 0,
		"un mode inconnu doit alarmer et rendre 0, jamais compter tout le monde")

func _entite_sans_proprietes_ignoree(v) -> void:
	var poissons := [
		_poisson("poisson_5", {"luit": true}),
		{"id": "poisson_6"},
	]
	var compte := Comptage.compter(poissons, "poissons_luisants", _catalogue())
	v.v(compte == 1, "une entite sans cle 'proprietes' doit etre ignoree silencieusement, jamais faire planter le comptage")

func _mode_egale_ignore_les_absents(v) -> void:
	var poissons := [
		_poisson("poisson_7", {"couleur": "rouge"}),
		_poisson("poisson_8", {}),
	]
	var compte := Comptage.compter(poissons, "poissons_rouges", _catalogue())
	v.v(compte == 1, "mode egale : une entite sans la propriete testee ne doit jamais compter, ni faire planter")

func _mode_superieur_a_alarme_sur_valeur_non_numerique(v) -> void:
	var poissons := [
		_poisson("poisson_9", {"poids": 8.0}),
		_poisson("poisson_lourd_en_texte", {"poids": "beaucoup"}),
	]
	var compte := Comptage.compter(poissons, "poissons_lourds", _catalogue())
	v.v(compte == 1, "mode superieur_a : une valeur non numerique doit alarmer et etre ignoree, jamais planter ni compter")

func _mode_contient_element_avec_champ_compte_correctement(v) -> void:
	var nuees := [
		_poisson("nuee_1", {"oiseaux": [{"couleur": "rouge", "taille": "petit"}, {"couleur": "bleu", "taille": "grand"}]}),
		_poisson("nuee_2", {"oiseaux": [{"couleur": "vert", "taille": "petit"}]}),
		_poisson("nuee_3", {"oiseaux": [{"couleur": "bleu", "taille": "grand"}, {"couleur": "rouge", "taille": "grand"}]}),
	]
	var compte := Comptage.compter(nuees, "nuees_avec_oiseau_rouge", _catalogue())
	v.v(compte == 2,
		"mode contient_element_avec_champ doit compter les entites dont l'Array contient au moins un element au champ egal a valeur_reference")

func _mode_contient_element_avec_champ_ignore_les_arrays_absents(v) -> void:
	var nuees := [
		_poisson("nuee_4", {"oiseaux": [{"couleur": "rouge"}]}),
		_poisson("nuee_5", {}),
	]
	var compte := Comptage.compter(nuees, "nuees_avec_oiseau_rouge", _catalogue())
	v.v(compte == 1, "une entite sans la cle Array testee ne doit jamais compter, ni faire planter")

func _mode_contient_element_avec_champ_alarme_si_valeur_non_array(v) -> void:
	var nuees := [
		_poisson("nuee_6", {"oiseaux": [{"couleur": "rouge"}]}),
		_poisson("nuee_texte", {"oiseaux": {"couleur": "rouge"}}),
	]
	var compte := Comptage.compter(nuees, "nuees_avec_oiseau_rouge", _catalogue())
	v.v(compte == 1, "une valeur non Array doit alarmer et etre ignoree, jamais planter ni compter")

# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# les proprietes lues par compter() ne doivent porter que du JSON pur, et
# le mecanisme doit rendre le meme compte sur des entites reconstruites
# depuis un aller-retour JSON.stringify/parse_string.
func _resumabilite_json_stricte(v) -> void:
	var poissons := [
		_poisson("poisson_10", {"luit": true, "couleur": "rouge", "poids": 9.0}),
		_poisson("poisson_11", {"luit": false, "couleur": "rouge", "poids": 2.0}),
	]
	var texte := JSON.stringify(poissons)
	var relus: Variant = JSON.parse_string(texte)
	v.v(relus != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	var catalogue := _catalogue()
	v.v(Comptage.compter(relus, "poissons_luisants", catalogue) == Comptage.compter(poissons, "poissons_luisants", catalogue),
		"mode presente doit rendre le meme compte apres un aller-retour JSON")
	v.v(Comptage.compter(relus, "poissons_rouges", catalogue) == Comptage.compter(poissons, "poissons_rouges", catalogue),
		"mode egale doit rendre le meme compte apres un aller-retour JSON")
	v.v(Comptage.compter(relus, "poissons_lourds", catalogue) == Comptage.compter(poissons, "poissons_lourds", catalogue),
		"mode superieur_a doit rendre le meme compte apres un aller-retour JSON")
