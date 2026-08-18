extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_extinction.gd
#
# Verrouille scripts/extinction.gd comme MODELE DE TRANSFORMATION generique,
# pas comme un code "feu". Une chose porte une quantite de travail
# (travail_restant, sur l'instance, mutee a chaque pas) et une reference
# "transformation" (String) vers une entree du catalogue TRANSFORMATIONS --
# portee_travail et ce qui change a zero (a_zero, en donnee) vivent DANS
# cette entree, jamais directement sur la chose. Un agent a portee mange la
# quantite a son rythme (defaut 1.0). A zero, a_zero s'applique : proprietes
# retirees et/ou posees, en donnee -- le moteur ne connait ni "feu", ni
# "brule", ni "cendre".
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun registre
# tenu a cote (plus de Dictionary travail). travail_restant vit SUR la
# chose ; portee_travail/a_zero vivent dans TRANSFORMATIONS (catalogue de ce
# test, passe a Extinction.avancer).

const Extinction = preload("res://scripts/extinction.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

# Trois entrees : feu, rocher (_le_modele_ignore_le_mot_feu) -- extinction.gd
# ne lit qu'une cle opaque dans chaque cas, il ne sait pas laquelle est "du
# feu" -- et sans_portee, qui omet deliberement portee_travail pour
# verrouiller la garde contre le defaut silencieux 0.0
# (_portee_travail_absente_de_l_entree_alerte_et_n_accomplit_rien).
const TRANSFORMATIONS := {
	"eteindre_feu": {
		"portee_travail": 25.0,
		"a_zero": { "retirer": ["brule", "saillance_intrinseque", "portee_saillance"] },
	},
	"miner_rocher": {
		"portee_travail": 25.0,
		"a_zero": { "retirer": ["dur"], "poser": { "gravats": true } },
	},
	"sans_portee": {},
}

# Chantier "transformation produit un objet neuf" : catalogues hors domaine
# dedies (jamais bois/charbon/cendre ici, voir le banc reel pour ce
# chemin). "combustion_zorg" ne porte QUE "produire" -- retirer/poser
# n'auraient plus de sens sur un objet qui va disparaitre. Le produit
# (cristal_zorg) enchaine lui-meme un second chantier via patron_produit,
# qui se termine normalement (a_zero.retirer classique, aucun second
# produire) -- verrouille que la chaine peut avoir plus d'un maillon.
const MATERIAUX_PRODUIT := {
	"poudre_zorg": {"densite": 1.0},
}
const TABLE_PRODUIT := {
	"objet_zorg": {"composition": [{"materiau": "poudre_zorg", "volume": 4.0}]},
	"cristal_zorg": {"composition": [{"materiau": "poudre_zorg", "volume": 1.0}]},
}
const TRANSFORMATIONS_PRODUIT := {
	"combustion_zorg": {
		"portee_travail": 25.0,
		"a_zero": {
			"produire": {
				"type_produit": "cristal_zorg",
				"rendement": 0.4,
				"patron_produit": {
					"travail_restant": 1.0,
					"travail_initial": 1.0,
					"transformation": "combustion_cristal_zorg",
					"en_combustion": true,
				},
			},
		},
	},
	"combustion_cristal_zorg": {
		"portee_travail": 25.0,
		"a_zero": {"retirer": ["en_combustion"]},
	},
}

func _init() -> void:
	var v := Verif.new()
	_sans_agent_rien_ne_bouge(v)
	_un_agent_finit_par_accomplir(v)
	_deux_agents_plus_vite(v)
	_hors_portee_ne_travaille_pas(v)
	_a_zero_retire_les_proprietes(v)
	_le_modele_ignore_le_mot_feu(v)
	_portee_travail_absente_de_l_entree_alerte_et_n_accomplit_rien(v)
	_produire_remplace_l_objet_par_un_objet_neuf(v)
	_produire_enchaine_un_second_chantier_via_patron_produit(v)
	_produire_sans_table_se_replie_sur_retirer_poser(v)
	_valeur_posee_par_a_zero_est_une_copie_jamais_une_reference(v)
	_chantier_sans_transformation_resoluble_alarme_et_n_avance_pas(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: une chose porte son travail, un agent a portee le mange, " +
			"a zero a_zero s'applique en donnee, le modele ne connait aucun nom de chose")
		quit(0)

# Un chantier "feu" : les noms brule/saillance ne vivent QUE dans la donnee
# a_zero, jamais dans extinction.gd.
func _feu(id: String, pos: Vector3) -> Dictionary:
	return {
		"id": id,
		"position": pos,
		"proprietes": {
			"brule": true,
			"saillance_intrinseque": 3.0,
			"portee_saillance": 900.0,
			"travail_restant": 3.0,
			"transformation": "eteindre_feu",
		},
	}

func _accompli(monde: Array, agents: Array, delta: float, max_ticks: int, id: String) -> int:
	for i in max_ticks:
		var faits := Extinction.avancer(monde, agents, delta, TRANSFORMATIONS)
		if faits.has(id):
			return i + 1
	return -1

func _agents(nb: int, pos: Vector3) -> Array:
	var a: Array = []
	for i in nb:
		a.append({"position": pos})
	return a

func _sans_agent_rien_ne_bouge(v) -> void:
	var monde := [_feu("feu_1", Vector3.ZERO)]
	var t := _accompli(monde, [], 0.5, 500, "feu_1")
	v.v(t == -1, "sans agent, un chantier ne doit jamais s'accomplir")
	v.v(monde[0].proprietes.get("brule", false), "sans agent, brule doit rester")
	v.v(monde[0].proprietes.get("travail_restant", -1.0) == 3.0,
		"sans agent, travail_restant ne doit pas bouger")

func _un_agent_finit_par_accomplir(v) -> void:
	var monde := [_feu("feu_1", Vector3.ZERO)]
	var t := _accompli(monde, _agents(1, Vector3.ZERO), 0.1, 200, "feu_1")
	v.v(t > 0, "un agent a portee doit finir par accomplir le chantier")

func _deux_agents_plus_vite(v) -> void:
	var monde_un := [_feu("feu_1", Vector3.ZERO)]
	var monde_deux := [_feu("feu_1", Vector3.ZERO)]
	var t_un := _accompli(monde_un, _agents(1, Vector3.ZERO), 0.1, 200, "feu_1")
	var t_deux := _accompli(monde_deux, _agents(2, Vector3.ZERO), 0.1, 200, "feu_1")
	v.v(t_deux < t_un, "deux agents doivent accomplir plus vite qu'un seul")

func _hors_portee_ne_travaille_pas(v) -> void:
	var monde := [_feu("feu_1", Vector3.ZERO)]
	var loin := _agents(1, Vector3(1000.0, 0.0, 0.0))
	var t := _accompli(monde, loin, 0.1, 500, "feu_1")
	v.v(t == -1, "un agent hors de portee_travail ne doit rien accomplir")

# DEUX CHANTIERS INRESOLUBLES, MEME SORTIE : une chose qui porte du travail
# sans dire par quelle transformation il s'acheve, et une reference qui ne
# resout dans aucun catalogue. Les deux alarment et n'avancent RIEN -- un
# travail qui descendrait vers un `a_zero` introuvable atteindrait zero sans
# que rien ne s'applique, et la chose resterait un chantier fantome que les
# agents mangeraient pour toujours.
func _chantier_sans_transformation_resoluble_alarme_et_n_avance_pas(v) -> void:
	var agents := [{"position": Vector3.ZERO, "rythme": 5.0}]

	var sans_reference := [{
		"id": "a", "position": Vector3.ZERO,
		"proprietes": {"travail_restant": 3.0},
	}]
	v.v(Extinction.avancer(sans_reference, agents, 1.0, TRANSFORMATIONS).is_empty(),
		"travail_restant sans 'transformation' : alarme, aucun accomplissement")
	v.v(sans_reference[0].proprietes.travail_restant == 3.0,
		"travail_restant sans 'transformation' : le travail ne descend pas d'un chiffre")

	var reference_morte := [{
		"id": "b", "position": Vector3.ZERO,
		"proprietes": {"travail_restant": 3.0, "transformation": "entree_inexistante"},
	}]
	v.v(Extinction.avancer(reference_morte, agents, 1.0, TRANSFORMATIONS).is_empty(),
		"reference absente du catalogue : alarme, aucun accomplissement")
	v.v(reference_morte[0].proprietes.travail_restant == 3.0,
		"reference absente du catalogue : le travail ne descend pas d'un chiffre")

# HORS DOMAINE. Ce que pose a_zero est une COPIE, jamais la reference du
# catalogue : deux choses qui resolvent la MEME entree de transformation ne
# partagent aucune sous-structure, et le catalogue reste intact.
func _valeur_posee_par_a_zero_est_une_copie_jamais_une_reference(v) -> void:
	var transformations := {
		"zorg": {
			"portee_travail": 10.0,
			"a_zero": {"poser": {"bac": {"niveau": 1.0}, "paliers": ["a"]}},
		},
	}
	var monde := [
		{"id": "a", "position": Vector3.ZERO, "proprietes": {"travail_restant": 1.0, "transformation": "zorg"}},
		{"id": "b", "position": Vector3.ZERO, "proprietes": {"travail_restant": 1.0, "transformation": "zorg"}},
	]
	Extinction.avancer(monde, [{"position": Vector3.ZERO, "rythme": 5.0}], 1.0, transformations)
	var pa: Dictionary = monde[0].proprietes
	var pb: Dictionary = monde[1].proprietes
	v.v(pa.has("bac") and pb.has("bac"), "les deux chantiers doivent s'etre accomplis")
	pa.bac.niveau = 99.0
	pa.paliers.append("z")
	v.v(pb.bac.niveau == 1.0,
		"deux choses ne doivent jamais partager le Dictionary pose par a_zero")
	v.v(pb.paliers.size() == 1,
		"deux choses ne doivent jamais partager l'Array pose par a_zero")
	v.v(transformations.zorg.a_zero.poser.bac.niveau == 1.0,
		"le catalogue ne doit jamais etre mute par une pose")

func _a_zero_retire_les_proprietes(v) -> void:
	var monde := [_feu("feu_1", Vector3.ZERO)]
	_accompli(monde, _agents(1, Vector3.ZERO), 0.1, 200, "feu_1")
	var p: Dictionary = monde[0].proprietes
	v.v(not p.has("brule"), "a_zero doit retirer brule, pas le mettre a false")
	v.v(not p.has("saillance_intrinseque"), "a_zero doit retirer saillance_intrinseque")
	v.v(not p.has("portee_saillance"), "a_zero doit retirer portee_saillance")

# LA serrure generaliste : une chose qui n'a rien d'un feu (un rocher qu'on
# mine) s'accomplit par le MEME code et devient gravats, parce que tout est
# en donnee dans a_zero. Si ce test passe, extinction.gd ne connait aucun
# nom de chose.
func _le_modele_ignore_le_mot_feu(v) -> void:
	var rocher := {
		"id": "rocher_1",
		"position": Vector3.ZERO,
		"proprietes": {
			"dur": true,
			"travail_restant": 2.0,
			"transformation": "miner_rocher",
		},
	}
	var monde := [rocher]
	var t := _accompli(monde, _agents(1, Vector3.ZERO), 0.1, 200, "rocher_1")
	var p: Dictionary = monde[0].proprietes
	v.v(t > 0, "un chantier non-feu doit s'accomplir par le meme code")
	v.v(not p.has("dur"), "a_zero doit retirer dur sur le rocher")
	v.v(p.get("gravats", false), "a_zero doit poser gravats sur le rocher")

# Verrouille la garde sur portee_travail absente de l'entree resolue.
# Agent A DISTANCE NULLE de la chose : si un defaut 0.0 silencieux
# s'appliquait a portee, "0.0 <= 0.0" serait vrai et le chantier
# avancerait quand meme -- exactement le faux positif que la garde doit
# empecher, au pire cas possible (distance minimale).
func _portee_travail_absente_de_l_entree_alerte_et_n_accomplit_rien(v) -> void:
	var chose := {
		"id": "sans_portee_1",
		"position": Vector3.ZERO,
		"proprietes": {
			"travail_restant": 2.0,
			"transformation": "sans_portee",
		},
	}
	var monde := [chose]
	var t := _accompli(monde, _agents(1, Vector3.ZERO), 0.1, 200, "sans_portee_1")
	v.v(t == -1, "portee_travail absente de l'entree resolue : le chantier ne doit jamais avancer")
	v.v(monde[0].proprietes.get("travail_restant", -1.0) == 2.0,
		"travail_restant ne doit pas bouger sans portee_travail resolue")

# Fabrique un "objet_zorg" reel (via Objet.fabriquer, donc avec une masse
# DERIVEE de sa composition, jamais posee a la main) puis y ajoute a la
# main les cles de chantier (travail_restant/transformation) -- ce
# fichier ne connait pas de mecanisme d'allumage, seul extinction.gd est
# sous test ici.
func _objet_zorg_en_chantier(id: String, transformation: String, travail: float) -> Dictionary:
	var fab := Objet.fabriquer(id, "objet_zorg", Vector3.ZERO, TABLE_PRODUIT, MATERIAUX_PRODUIT)
	fab.proprietes["vieux_marqueur"] = true
	fab.proprietes["travail_restant"] = travail
	fab.proprietes["transformation"] = transformation
	return fab

func _produire_remplace_l_objet_par_un_objet_neuf(v) -> void:
	var objet := _objet_zorg_en_chantier("z_1", "combustion_zorg", 3.0)
	var masse_ancien: float = objet.proprietes.masse
	var monde := [objet]
	var agents := _agents(1, Vector3.ZERO)
	for i in 200:
		var faits := Extinction.avancer(monde, agents, 0.1, TRANSFORMATIONS_PRODUIT, TABLE_PRODUIT, MATERIAUX_PRODUIT)
		if faits.has("z_1"):
			break
	var p: Dictionary = monde[0].proprietes
	v.v(monde[0].id == "z_1", "l'id doit rester le meme apres un produit")
	v.v(not p.has("vieux_marqueur"), "les proprietes de l'ancien objet ne doivent pas survivre au produit")
	v.v(is_equal_approx(p.get("masse", -1.0), masse_ancien * 0.4),
		"la masse du produit doit valoir exactement rendement * masse ancienne")
	v.v(p.get("en_combustion", false), "patron_produit doit poser ses cles sur le produit")
	v.v(p.get("transformation", "") == "combustion_cristal_zorg",
		"patron_produit doit pouvoir enchainer un second chantier via 'transformation'")
	v.v(p.get("travail_restant", -1.0) == 1.0, "patron_produit doit poser le travail_restant du second chantier")

func _produire_enchaine_un_second_chantier_via_patron_produit(v) -> void:
	var objet := _objet_zorg_en_chantier("z_2", "combustion_zorg", 3.0)
	var monde := [objet]
	var agents := _agents(1, Vector3.ZERO)
	# Assez de ticks pour traverser LES DEUX chantiers d'affilee.
	for i in 400:
		Extinction.avancer(monde, agents, 0.1, TRANSFORMATIONS_PRODUIT, TABLE_PRODUIT, MATERIAUX_PRODUIT)
	var p: Dictionary = monde[0].proprietes
	v.v(not p.has("en_combustion"), "le second chantier doit s'accomplir et retirer en_combustion")
	v.v(not p.has("travail_restant"), "le second chantier accompli ne doit plus porter de travail_restant")
	v.v(not p.has("transformation"), "le second chantier accompli ne doit plus porter de transformation")
	v.v(p.has("composition"), "le produit final doit rester un objet reel (composition intacte)")

func _produire_sans_table_se_replie_sur_retirer_poser(v) -> void:
	var objet := _objet_zorg_en_chantier("z_3", "combustion_zorg", 3.0)
	var monde := [objet]
	var agents := _agents(1, Vector3.ZERO)
	for i in 200:
		var faits := Extinction.avancer(monde, agents, 0.1, TRANSFORMATIONS_PRODUIT)
		if faits.has("z_3"):
			break
	var p: Dictionary = monde[0].proprietes
	v.v(p.get("vieux_marqueur", false), "sans table, produire doit etre ignore -- l'objet ancien ne doit pas disparaitre")
	v.v(not p.has("travail_restant"), "sans table, le chantier doit quand meme se terminer proprement (travail_restant retire)")
	v.v(not p.has("transformation"), "sans table, transformation doit quand meme etre retiree")
