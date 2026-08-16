extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_propagation.gd
#
# Verrouille scripts/propagation.gd : fonction pure, aucune couche,
# aucun noeud, aucun rendu. Le monde porte des objets a proprietes
# { id, position, proprietes } -- s'allumer gagne la propriete-menace
# (menaces.json, "inflammable" -> "brule"), rien d'autre.
#
# _le_modele_ignore_le_domaine() verrouille en plus que propagation.gd ne
# connait aucun nom de domaine : un couple vulnerabilite/menace invente
# ("poreux" -> "corrode", absent de tout le moteur, verifie par grep)
# traverse le meme code que inflammable/brule, sans une ligne ajoutee.

const Propagation = preload("res://scripts/propagation.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const TYPES := {
	"arbre": { "inflammable": true, "portee_propagation": 90.0, "delai_propagation": 1.0 },
	"batisse": { "inflammable": true, "portee_propagation": 90.0, "delai_propagation": 1.5 },
}
const MENACES := { "inflammable": "brule" }

# INTENSITE EFFECTIVE (chantier "feu -- inflammabilite effective") : couple
# vulnerabilite/menace ET propriete d'intensite ENTIEREMENT INVENTES
# ("poreux"/"corrode"/"volatilite_zorg"), absents de tout le reste du
# depot -- si ces tests passent, propagation.gd:delai_ignition ne connait
# ni "inflammabilite" ni "brule" en dur.
const MATERIAUX_INTENSITE := {
	"mat_vif": { "densite": 1.0, "volatilite_zorg": 0.9 },
	"mat_faible": { "densite": 1.0, "volatilite_zorg": 0.15 },
	"mat_inerte": { "densite": 1.0, "volatilite_zorg": 0.02 },
}
const TYPES_INTENSITE := {
	"cible_vive": {
		"poreux": true, "portee_propagation": 90.0, "delai_propagation": 1.0,
		"composition": [{"materiau": "mat_vif", "volume": 1.0}],
	},
	"cible_faible": {
		"poreux": true, "portee_propagation": 90.0, "delai_propagation": 1.0,
		"composition": [{"materiau": "mat_faible", "volume": 1.0}],
	},
	"cible_inerte": {
		"poreux": true, "portee_propagation": 90.0, "delai_propagation": 1.0,
		"composition": [{"materiau": "mat_inerte", "volume": 1.0}],
	},
	"cible_sans_matiere": {
		"poreux": true, "portee_propagation": 90.0, "delai_propagation": 1.0,
	},
}
const MENACES_INTENSITE := {"poreux": "corrode"}
const INTENSITE_ZORG := {"propriete_intensite": "volatilite_zorg", "seuil_ignition": 0.1}
const ETATS_ZORG := {
	"gele_zorg": {"effets": [{"propriete": "volatilite_zorg", "mode": "ecraser", "valeur": 0.0}]},
}

# CHANTIER "emission et seuil" -- hors domaine, meme discipline que
# INTENSITE_ZORG ci-dessus : reutilise "volatilite_zorg"/mat_vif/mat_faible
# comme grandeur de matiere ET comme propriete d'intensite, aucun nom reel
# (feu/bois/inflammable) n'apparait dans ces tests.
# facteur_densite/facteur_porosite a 0.0 -- NEUTRE (chantier "densite et
# porosite sur la vitesse de combustion" ne touche pas a propagation.gd,
# voir son en-tete) : cout_base_effectif == cout_base_reference, preserve
# toutes les assertions deja ecrites sur ce fichier sans les toucher.
const RESERVE_ZORG := {
	"nom_reserve": "zorg_reserve",
	"propriete_materiau": "volatilite_zorg",
	"propriete_porosite": "porosite_zorg",
	"cout_base": 1.0,
	"facteur_densite": 0.0,
	"facteur_porosite": 0.0,
	"surcout_action": 0.0,
	"seuils_ref": "defaut",
}
const EMISSION_ZORG := {
	"portee_emission_base": 0.0,
	"portee_emission_par_capacite": 1000.0,
	"nom_reserve": "zorg_reserve",
	"seuil_base": 9.0,
}
const TYPES_EMISSION := {
	"petit_feu_zorg": {"corrode": true, "composition": [{"materiau": "mat_vif", "volume": 1.0}]},
	"grand_feu_zorg": {"corrode": true, "composition": [{"materiau": "mat_vif", "volume": 8.0}]},
}

# ---- Chantier "point_ignition" -- gate TROISIEME dans delai_ignition(),
# AJOUTE au proxy d'intensite deja teste plus haut (INTENSITE_ZORG), les
# deux filtres COEXISTENT. Reutilise MENACES/inflammable/brule (deja
# domain-independant, prouve plus haut par _le_modele_ignore_le_domaine) :
# ce bloc ne re-prouve pas l'independance au domaine, seulement le NOUVEAU
# gate lui-meme.
const MATERIAUX_POINT_IGNITION := {
	"mat_avec_seuil": { "densite": 1.0, "point_ignition": 300.0 },
	"mat_sans_seuil": { "densite": 1.0 },
}
const TYPES_POINT_IGNITION := {
	"cible_avec_seuil": {
		"inflammable": true, "portee_propagation": 90.0, "delai_propagation": 1.0,
		"composition": [{"materiau": "mat_avec_seuil", "volume": 1.0}],
	},
	"cible_sans_seuil": {
		"inflammable": true, "portee_propagation": 90.0, "delai_propagation": 1.0,
		"composition": [{"materiau": "mat_sans_seuil", "volume": 1.0}],
	},
}
const PROPRIETES_IMMUABLES_POINT_IGNITION := ["point_ignition"]

# Chantier "correction nom en dur point_ignition" : le nom de la propriete
# gate n'est plus fige dans propagation.gd, il vient de "intensite.
# propriete_point_ignition" (defaut "" -- gate desactive). Les tests
# ci-dessous qui veulent le gate ACTIF doivent desormais le declarer
# explicitement -- meme discipline que INTENSITE_ZORG pour propriete_intensite.
const INTENSITE_POINT_IGNITION := {"propriete_point_ignition": "point_ignition"}
const INTENSITE_ZORG_ET_POINT_IGNITION := {
	"propriete_intensite": "volatilite_zorg", "seuil_ignition": 0.1,
	"propriete_point_ignition": "point_ignition",
}

func _source_en_feu(pos: Vector3) -> Dictionary:
	return {"id": "source_feu", "position": pos, "proprietes": {"brule": true}}

func _delai_ignition_temperature_sans_le_parametre_comportement_inchange(v) -> void:
	var chose := {"proprietes": {"delai_propagation": 4.0, "point_ignition": 300.0}}
	v.v(is_equal_approx(Propagation.delai_ignition(chose, INTENSITE_POINT_IGNITION, {}), 4.0),
		"sans le parametre temperature_locale (defaut INF), le gate ne doit jamais s'appliquer, meme avec point_ignition configure et present")

func _delai_ignition_temperature_sous_le_point_ignition_bloque(v) -> void:
	var chose := {"proprietes": {"delai_propagation": 4.0, "point_ignition": 300.0}}
	v.v(Propagation.delai_ignition(chose, INTENSITE_POINT_IGNITION, {}, 100.0) == -1.0,
		"une temperature (100.0) sous le point_ignition (300.0) doit rendre -1.0 quand 'propriete_point_ignition' est configuree")

func _delai_ignition_temperature_au_dessus_du_point_ignition_allumage_normal(v) -> void:
	var chose := {"proprietes": {"delai_propagation": 4.0, "point_ignition": 300.0}}
	v.v(is_equal_approx(Propagation.delai_ignition(chose, INTENSITE_POINT_IGNITION, {}, 500.0), 4.0),
		"une temperature (500.0) au-dessus du point_ignition (300.0) doit rendre delai_propagation inchange")

func _delai_ignition_sans_point_ignition_le_gate_ne_s_applique_jamais(v) -> void:
	var chose := {"proprietes": {"delai_propagation": 4.0}}
	v.v(is_equal_approx(Propagation.delai_ignition(chose, INTENSITE_POINT_IGNITION, {}, 0.0), 4.0),
		"une chose sans 'point_ignition' sur proprietes ne doit jamais etre bloquee par ce gate, meme configure et a temperature 0.0")

# Chantier "correction nom en dur point_ignition" : NOUVEAU cas -- l'absence
# de 'propriete_point_ignition' dans la donnee (intensite {}) desactive le
# gate PAR DEFAUT, meme si la chose porte reellement un 'point_ignition' et
# qu'une temperature tres en dessous serait normalement bloquante. C'est le
# cas qu'aurait laisse passer l'ancien nom fige en dur -- ce test l'aurait
# attrape.
func _delai_ignition_sans_propriete_point_ignition_configuree_le_gate_ne_bloque_jamais(v) -> void:
	var chose := {"proprietes": {"delai_propagation": 4.0, "point_ignition": 300.0}}
	v.v(is_equal_approx(Propagation.delai_ignition(chose, {}, {}, 100.0), 4.0),
		"sans 'propriete_point_ignition' declaree dans intensite, le gate ne doit jamais bloquer -- meme si la chose porte point_ignition=300.0 et qu'une temperature de 100.0 serait normalement bloquante")

func _delai_ignition_les_deux_gates_coexistent(v) -> void:
	var chose_chaude_faible := {"proprietes": {"delai_propagation": 4.0, "point_ignition": 300.0, "volatilite_zorg": 0.9, "etats_actifs": []}}
	v.v(Propagation.delai_ignition(chose_chaude_faible, INTENSITE_ZORG_ET_POINT_IGNITION, ETATS_ZORG, 100.0) == -1.0,
		"un proxy d'intensite qui passerait seul ne doit pas suffire si la temperature bloque -- les deux gates coexistent")
	var chose_froide_forte := {"proprietes": {"delai_propagation": 4.0, "point_ignition": 300.0, "volatilite_zorg": 0.02, "etats_actifs": []}}
	v.v(Propagation.delai_ignition(chose_froide_forte, INTENSITE_ZORG_ET_POINT_IGNITION, ETATS_ZORG, 500.0) == -1.0,
		"une temperature qui passerait seule ne doit pas suffire si le proxy d'intensite bloque -- les deux gates coexistent")

func _avancer_sans_temperature_locale_comportement_inchange(v) -> void:
	var monde := [
		_source_en_feu(Vector3(0, 0, 0)),
		Objet.fabriquer("cible_0", "cible_avec_seuil", Vector3(50, 0, 0), TYPES_POINT_IGNITION, MATERIAUX_POINT_IGNITION, PROPRIETES_IMMUABLES_POINT_IGNITION),
	]
	var exposition := {}
	var enflammee := false
	for i in 30:
		var e := Propagation.avancer(monde, MENACES, exposition, 0.1)
		if e.has("cible_0"):
			enflammee = true
	v.v(enflammee, "sans le 9e parametre temperature_locale, une chose avec point_ignition doit s'enflammer normalement -- comportement inchange")

func _avancer_temperature_sous_le_point_ignition_ne_s_enflamme_jamais(v) -> void:
	var monde := [
		_source_en_feu(Vector3(0, 0, 0)),
		Objet.fabriquer("cible_0", "cible_avec_seuil", Vector3(50, 0, 0), TYPES_POINT_IGNITION, MATERIAUX_POINT_IGNITION, PROPRIETES_IMMUABLES_POINT_IGNITION),
	]
	var exposition := {}
	var jamais := true
	for i in 500:
		var e := Propagation.avancer(monde, MENACES, exposition, 0.1, {}, INTENSITE_POINT_IGNITION, {}, {}, {"cible_0": 100.0})
		if not e.is_empty():
			jamais = false
	v.v(jamais, "une temperature locale (100.0) sous le point_ignition (300.0) ne doit JAMAIS permettre l'allumage, meme expose tres longtemps")

func _avancer_temperature_au_dessus_du_point_ignition_allumage_normal(v) -> void:
	var monde := [
		_source_en_feu(Vector3(0, 0, 0)),
		Objet.fabriquer("cible_0", "cible_avec_seuil", Vector3(50, 0, 0), TYPES_POINT_IGNITION, MATERIAUX_POINT_IGNITION, PROPRIETES_IMMUABLES_POINT_IGNITION),
	]
	var exposition := {}
	var enflammee := false
	for i in 30:
		var e := Propagation.avancer(monde, MENACES, exposition, 0.1, {}, INTENSITE_POINT_IGNITION, {}, {}, {"cible_0": 500.0})
		if e.has("cible_0"):
			enflammee = true
	v.v(enflammee, "une temperature locale (500.0) au-dessus du point_ignition (300.0) doit permettre l'allumage normal")

func _avancer_materiau_sans_point_ignition_s_enflamme_comme_avant(v) -> void:
	# Temperature (20.0, ambiante realiste) volontairement CHOISIE parce
	# qu'elle bloquerait "cible_avec_seuil" (point_ignition 300.0) -- prouve
	# que le defaut fusionne (0.0, aucune fiche materiau ne le porte) est un
	# SEUIL REEL tres bas, pas un desactivateur du gate (has() reste vrai) :
	# 20.0 >= 0.0 suffit, jamais 20.0 >= 300.0. Une temperature NEGATIVE
	# irait sous ce seuil de 0.0 et bloquerait aussi -- comportement
	# COHERENT, pas un gate desactive, voir data/proprietes_immuables_
	# composition.json pour le risque documente sur ce defaut.
	var monde := [
		_source_en_feu(Vector3(0, 0, 0)),
		Objet.fabriquer("cible_0", "cible_sans_seuil", Vector3(50, 0, 0), TYPES_POINT_IGNITION, MATERIAUX_POINT_IGNITION, PROPRIETES_IMMUABLES_POINT_IGNITION),
	]
	var exposition := {}
	var enflammee := false
	for i in 30:
		var e := Propagation.avancer(monde, MENACES, exposition, 0.1, {}, INTENSITE_POINT_IGNITION, {}, {}, {"cible_0": 20.0})
		if e.has("cible_0"):
			enflammee = true
	v.v(enflammee, "un materiau sans point_ignition (fusionne a 0.0) doit s'enflammer a une temperature (20.0) qui bloquerait un materiau avec un seuil reel (300.0) -- le defaut est un seuil tres bas, pas un gate desactive")

func _init() -> void:
	_feu_isole_ne_gagne_rien()
	_propagation_en_chaine()
	_rien_ne_s_eteint_jamais()
	_le_modele_ignore_le_domaine(verif)
	_delai_propagation_absent_alarme_sans_ignition_instantanee()
	_intensite_haute_s_enflamme_avant_intensite_faible(verif)
	_intensite_sous_le_seuil_ne_s_enflamme_jamais(verif)
	_etat_qui_ecrase_l_intensite_bloque_l_ignition(verif)
	_chose_sans_la_propriete_d_intensite_ignore_le_gating(verif)
	_delai_ignition_fonction_pure(verif)
	_recu_croit_avec_la_capacite_de_la_source(verif)
	_recu_decroit_avec_le_carre_de_la_distance(verif)
	_seuil_exposition_derive_de_l_intensite_effective(verif)
	_seuil_exposition_sans_intensite_configuree_rend_infini(verif)
	_grand_feu_expose_a_une_distance_ou_le_petit_n_expose_pas(verif)
	_a_distance_egale_une_matiere_expose_et_l_autre_jamais(verif)
	_sans_emission_configuree_le_comportement_reste_celui_d_avant(verif)
	_delai_ignition_temperature_sans_le_parametre_comportement_inchange(verif)
	_delai_ignition_temperature_sous_le_point_ignition_bloque(verif)
	_delai_ignition_temperature_au_dessus_du_point_ignition_allumage_normal(verif)
	_delai_ignition_sans_point_ignition_le_gate_ne_s_applique_jamais(verif)
	_delai_ignition_sans_propriete_point_ignition_configuree_le_gate_ne_bloque_jamais(verif)
	_delai_ignition_les_deux_gates_coexistent(verif)
	_avancer_sans_temperature_locale_comportement_inchange(verif)
	_avancer_temperature_sous_le_point_ignition_ne_s_enflamme_jamais(verif)
	_avancer_temperature_au_dessus_du_point_ignition_allumage_normal(verif)
	_avancer_materiau_sans_point_ignition_s_enflamme_comme_avant(verif)
	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: feu isole n'a rien gagne, propagation en chaine, rien ne s'eteint, " +
		"domaine invente traverse le meme code sans ligne ajoutee, " +
		"delai_propagation absent alarme au lieu d'enflammer instantanement, " +
		"intensite effective (chantier feu) gate l'ignition sans nom en dur, " +
		"emission (chantier emission et seuil) derive de la capacite de la source et " +
		"decroit en 1/distance^2, seuil derive de l'intensite effective, grand feu " +
		"porte plus loin qu'un petit sans distance ecrite a la main, comportement " +
		"inchange sans emission configuree, gate point_ignition (chantier point_ignition) " +
		"coexiste avec le proxy d'intensite sans le remplacer, defaut INF desactive le " +
		"gate par la seule arithmetique, materiau sans point_ignition inchange, " +
		"propriete_point_ignition vient de la donnee (chantier correction nom en dur), " +
		"sans elle le gate ne bloque jamais")
	quit(0)

func _chose(id: String, type: String, pos: Vector3, allume: bool) -> Dictionary:
	var objet := Objet.fabriquer(id, type, pos, TYPES)
	if allume:
		objet.proprietes["brule"] = true
	return objet

func _en_feu(chose: Dictionary) -> bool:
	return chose.proprietes.get("brule", false)

func _feu_isole_ne_gagne_rien() -> void:
	var monde := [_chose("feu_1", "arbre", Vector3(300, 300, 0), true)]
	var exposition := {}
	for i in 200:
		var enflammees := Propagation.avancer(monde, MENACES, exposition, 0.1)
		verif.v(enflammees.is_empty(), "un feu seul ne doit jamais rien gagner")
	verif.v(_en_feu(monde[0]), "le feu isole doit toujours bruler")

func _propagation_en_chaine() -> void:
	var monde := [
		_chose("arbre_0", "arbre", Vector3(0, 0, 0), true),
		_chose("arbre_1", "arbre", Vector3(80, 0, 0), false),
		_chose("arbre_2", "arbre", Vector3(160, 0, 0), false),
	]
	var exposition := {}
	var tick_arbre_1 := -1
	var tick_arbre_2 := -1
	for i in 60:
		var enflammees := Propagation.avancer(monde, MENACES, exposition, 0.1)
		if enflammees.has("arbre_1") and tick_arbre_1 == -1:
			tick_arbre_1 = i
		if enflammees.has("arbre_2") and tick_arbre_2 == -1:
			tick_arbre_2 = i
	verif.v(tick_arbre_1 != -1, "l'arbre voisin direct doit prendre feu")
	verif.v(tick_arbre_2 != -1, "l'arbre hors de portee du foyer initial doit prendre feu via son voisin")
	if tick_arbre_1 != -1 and tick_arbre_2 != -1:
		verif.v(tick_arbre_2 > tick_arbre_1, "la propagation en chaine doit gagner arbre_1 avant arbre_2")

func _rien_ne_s_eteint_jamais() -> void:
	var monde := [
		_chose("arbre_0", "arbre", Vector3(0, 0, 0), true),
		_chose("arbre_1", "arbre", Vector3(80, 0, 0), false),
		_chose("batisse_0", "batisse", Vector3(30, 60, 0), false),
	]
	var exposition := {}
	for i in 1000:
		Propagation.avancer(monde, MENACES, exposition, 0.1)
	for chose in monde:
		if chose.id == "arbre_0":
			verif.v(_en_feu(chose), "le foyer initial ne doit jamais s'eteindre")
	# Personne n'eteint : une fois enflammee, une chose le reste pour toujours.
	for chose in monde:
		if _en_feu(chose):
			for j in 50:
				Propagation.avancer(monde, MENACES, exposition, 0.1)
				verif.v(_en_feu(chose), "rien ne doit jamais repasser brule=false")

# LA serrure hors domaine : un couple vulnerabilite/menace SANS AUCUN
# rapport avec le feu ("poreux" -> "corrode", absent de tout le moteur)
# doit traverser avancer() par le meme code, avec un patron invente lui
# aussi. Si ce test passe, propagation.gd ne connait aucun nom de domaine.
func _le_modele_ignore_le_domaine(v) -> void:
	var menaces_inventees := { "poreux": "corrode" }
	var patron_invente := { "etat_atteint": "corrosion_avancee" }
	var monde := [
		{
			"id": "source_corrode",
			"position": Vector3(0, 0, 0),
			"proprietes": { "corrode": true },
		},
		{
			"id": "cible_poreuse",
			"position": Vector3(50, 0, 0),
			"proprietes": {
				"poreux": true,
				"portee_propagation": 90.0,
				"delai_propagation": 1.0,
			},
		},
		{
			"id": "cible_hors_portee",
			"position": Vector3(500, 0, 0),
			"proprietes": {
				"poreux": true,
				"portee_propagation": 90.0,
				"delai_propagation": 1.0,
			},
		},
	]
	var exposition := {}
	var gagnee := false
	for i in 30:
		var enflammees := Propagation.avancer(monde, menaces_inventees, exposition, 0.1, patron_invente)
		if enflammees.has("cible_poreuse"):
			gagnee = true

	v.v(gagnee, "une vulnerabilite inventee doit finir par gagner sa menace inventee")

	var p_cible: Dictionary = monde[1].proprietes
	v.v(p_cible.get("corrode", false),
		"la chose exposee doit gagner la propriete-menace inventee (corrode)")
	v.v(p_cible.get("etat_atteint", "") == "corrosion_avancee",
		"la chose exposee doit recevoir les cles du patron invente")

	var p_loin: Dictionary = monde[2].proprietes
	v.v(not p_loin.has("corrode"),
		"une chose vulnerable hors portee de la menace ne doit rien gagner")
	v.v(not p_loin.has("etat_atteint"),
		"une chose hors portee ne doit pas recevoir le patron")

# Verrou du piege recense en CARTE.md §6 : delai_propagation est
# STRUCTURELLE une fois la vulnerabilite confirmee (voir docs/design.md,
# "le cas du couple") -- son absence doit alarmer, jamais retomber sur un
# defaut 0.0 qui enflammerait des le premier tick d'exposition. delta
# choisi (2.0) strictement superieur a tout delai_propagation reel du
# depot (1.0, 1.5) : si un defaut 0.0 silencieux s'appliquait encore,
# exposition[id] >= 0.0 serait vrai des ce premier appel -- exactement le
# pire faux positif que produirait le defaut silencieux.
func _delai_propagation_absent_alarme_sans_ignition_instantanee() -> void:
	var monde := [
		{
			"id": "source_feu",
			"position": Vector3(0, 0, 0),
			"proprietes": {"brule": true},
		},
		{
			"id": "arbre_sans_delai",
			"position": Vector3(50, 0, 0),
			"proprietes": {"inflammable": true, "portee_propagation": 90.0},
		},
	]
	var exposition := {}
	var enflammees := Propagation.avancer(monde, MENACES, exposition, 2.0)
	verif.v(enflammees.is_empty(),
		"delai_propagation absent : aucune ignition, meme avec une exposition qui couvrirait n'importe quel defaut 0.0")
	verif.v(not monde[1].proprietes.get("brule", false),
		"delai_propagation absent : la propriete-menace ne doit jamais etre posee")

func _source_corrode(pos: Vector3) -> Dictionary:
	return {"id": "source_corrode", "position": pos, "proprietes": {"corrode": true}}

func _intensite_haute_s_enflamme_avant_intensite_faible(v) -> void:
	var monde := [
		_source_corrode(Vector3(0, 0, 0)),
		Objet.fabriquer("vive_0", "cible_vive", Vector3(50, 0, 0), TYPES_INTENSITE, MATERIAUX_INTENSITE, ["volatilite_zorg"]),
		Objet.fabriquer("faible_0", "cible_faible", Vector3(50, 20, 0), TYPES_INTENSITE, MATERIAUX_INTENSITE, ["volatilite_zorg"]),
	]
	var exposition := {}
	var tick_vive := -1
	var tick_faible := -1
	for i in 200:
		var enflammees := Propagation.avancer(monde, MENACES_INTENSITE, exposition, 0.1, {}, INTENSITE_ZORG, ETATS_ZORG)
		if enflammees.has("vive_0") and tick_vive == -1:
			tick_vive = i
		if enflammees.has("faible_0") and tick_faible == -1:
			tick_faible = i
	v.v(tick_vive != -1 and tick_faible != -1, "les deux cibles, au-dessus du seuil, doivent finir par s'enflammer")
	if tick_vive != -1 and tick_faible != -1:
		v.v(tick_vive < tick_faible,
			"une intensite effective plus haute (0.9) doit s'enflammer STRICTEMENT plus vite qu'une plus basse (0.15), meme exposition")

func _intensite_sous_le_seuil_ne_s_enflamme_jamais(v) -> void:
	var monde := [
		_source_corrode(Vector3(0, 0, 0)),
		Objet.fabriquer("inerte_0", "cible_inerte", Vector3(50, 0, 0), TYPES_INTENSITE, MATERIAUX_INTENSITE, ["volatilite_zorg"]),
	]
	var exposition := {}
	var jamais := true
	for i in 500:
		var enflammees := Propagation.avancer(monde, MENACES_INTENSITE, exposition, 0.1, {}, INTENSITE_ZORG, ETATS_ZORG)
		if not enflammees.is_empty():
			jamais = false
	v.v(jamais, "une intensite effective (0.02) sous le seuil (0.1) ne doit JAMAIS s'enflammer, meme exposee tres longtemps")

func _etat_qui_ecrase_l_intensite_bloque_l_ignition(v) -> void:
	var cible := Objet.fabriquer("vive_gelee_0", "cible_vive", Vector3(50, 0, 0), TYPES_INTENSITE, MATERIAUX_INTENSITE, ["volatilite_zorg"])
	cible.proprietes["etats_actifs"] = ["gele_zorg"]
	var monde := [_source_corrode(Vector3(0, 0, 0)), cible]
	var exposition := {}
	var jamais := true
	for i in 500:
		var enflammees := Propagation.avancer(monde, MENACES_INTENSITE, exposition, 0.1, {}, INTENSITE_ZORG, ETATS_ZORG)
		if not enflammees.is_empty():
			jamais = false
	v.v(jamais,
		"un etat qui ECRASE l'intensite a 0.0 doit bloquer l'ignition exactement comme une intensite nativement basse -- meme base (0.9) que 'vive_0', qui elle s'enflamme")

func _chose_sans_la_propriete_d_intensite_ignore_le_gating(v) -> void:
	var monde := [
		_source_corrode(Vector3(0, 0, 0)),
		Objet.fabriquer("sans_matiere_0", "cible_sans_matiere", Vector3(50, 0, 0), TYPES_INTENSITE, MATERIAUX_INTENSITE),
	]
	var exposition := {}
	var enflammee := false
	for i in 30:
		var enflammees := Propagation.avancer(monde, MENACES_INTENSITE, exposition, 0.1, {}, INTENSITE_ZORG, ETATS_ZORG)
		if enflammees.has("sans_matiere_0"):
			enflammee = true
	v.v(enflammee,
		"une chose SANS la propriete d'intensite (pas de composition) doit s'enflammer normalement au delai fixe, meme quand le gating est configure -- comportement inchange")

func _delai_ignition_fonction_pure(v) -> void:
	var chose_sans_composition := {"proprietes": {"delai_propagation": 4.0}}
	v.v(is_equal_approx(Propagation.delai_ignition(chose_sans_composition, INTENSITE_ZORG, ETATS_ZORG), 4.0),
		"sans la propriete d'intensite sur la chose, delai_ignition doit rendre delai_propagation inchange")
	v.v(is_equal_approx(Propagation.delai_ignition(chose_sans_composition, {}, ETATS_ZORG), 4.0),
		"sans propriete_intensite configuree (intensite {}), delai_ignition doit rendre delai_propagation inchange")

	var chose_haute := {"proprietes": {"delai_propagation": 4.0, "volatilite_zorg": 0.8, "etats_actifs": []}}
	v.v(is_equal_approx(Propagation.delai_ignition(chose_haute, INTENSITE_ZORG, ETATS_ZORG), 4.0 / 0.8),
		"au-dessus du seuil, delai_ignition doit rendre delai_propagation / intensite_effective")

	var chose_basse := {"proprietes": {"delai_propagation": 4.0, "volatilite_zorg": 0.05, "etats_actifs": []}}
	v.v(Propagation.delai_ignition(chose_basse, INTENSITE_ZORG, ETATS_ZORG) == -1.0,
		"sous le seuil, delai_ignition doit rendre -1.0 -- jamais un delai fini, jamais un crash")

# ---- Chantier "emission et seuil" -- hors domaine (RESERVE_ZORG/
# EMISSION_ZORG/TYPES_EMISSION ci-dessus, memes noms invente que
# INTENSITE_ZORG plus haut).

func _recu_croit_avec_la_capacite_de_la_source(v) -> void:
	var petit := Objet.fabriquer("petit", "petit_feu_zorg", Vector3.ZERO, TYPES_EMISSION, MATERIAUX_INTENSITE, [], RESERVE_ZORG)
	var grand := Objet.fabriquer("grand", "grand_feu_zorg", Vector3.ZERO, TYPES_EMISSION, MATERIAUX_INTENSITE, [], RESERVE_ZORG)
	v.v(is_equal_approx(grand.proprietes.reserves.zorg_reserve.capacite, 8.0 * petit.proprietes.reserves.zorg_reserve.capacite),
		"grand_feu_zorg (volume 8x) doit avoir une capacite EXACTEMENT 8x celle de petit_feu_zorg (meme materiau)")
	var cible := {"id": "c", "position": Vector3(20, 0, 0), "proprietes": {}}
	var recu_petit := Propagation.recu(cible, petit, EMISSION_ZORG)
	var recu_grand := Propagation.recu(cible, grand, EMISSION_ZORG)
	v.v(is_equal_approx(recu_grand, 8.0 * recu_petit),
		"a distance egale, ce qu'une cible recoit doit croitre EXACTEMENT comme la capacite de la source -- emission lineaire en capacite, jamais un nombre libre")

func _recu_decroit_avec_le_carre_de_la_distance(v) -> void:
	var feu := Objet.fabriquer("f", "grand_feu_zorg", Vector3.ZERO, TYPES_EMISSION, MATERIAUX_INTENSITE, [], RESERVE_ZORG)
	var proche := {"id": "p", "position": Vector3(10, 0, 0), "proprietes": {}}
	var loin := {"id": "l", "position": Vector3(20, 0, 0), "proprietes": {}}
	var recu_proche := Propagation.recu(proche, feu, EMISSION_ZORG)
	var recu_loin := Propagation.recu(loin, feu, EMISSION_ZORG)
	v.v(is_equal_approx(recu_proche, 4.0 * recu_loin),
		"doubler la distance doit diviser par 4 ce que la cible recoit -- decroissance en 1/distance^2, jamais lineaire")

func _seuil_exposition_derive_de_l_intensite_effective(v) -> void:
	var vive := Objet.fabriquer("v", "cible_vive", Vector3.ZERO, TYPES_INTENSITE, MATERIAUX_INTENSITE, ["volatilite_zorg"])
	var faible := Objet.fabriquer("fa", "cible_faible", Vector3.ZERO, TYPES_INTENSITE, MATERIAUX_INTENSITE, ["volatilite_zorg"])
	var seuil_vive := Propagation.seuil_exposition(vive, INTENSITE_ZORG, ETATS_ZORG, EMISSION_ZORG)
	var seuil_faible := Propagation.seuil_exposition(faible, INTENSITE_ZORG, ETATS_ZORG, EMISSION_ZORG)
	v.v(is_equal_approx(seuil_vive, EMISSION_ZORG.seuil_base / 0.9),
		"le seuil doit valoir EXACTEMENT seuil_base / intensite effective, jamais recalcule autrement")
	v.v(seuil_vive < seuil_faible,
		"une matiere plus intense (0.9) doit avoir un seuil d'exposition PLUS BAS qu'une matiere moins intense (0.15) -- plus facile a exposer, meme direction que delai_ignition")

func _seuil_exposition_sans_intensite_configuree_rend_infini(v) -> void:
	var chose := {"proprietes": {}}
	v.v(Propagation.seuil_exposition(chose, {}, {}, EMISSION_ZORG) == INF,
		"sans intensite.propriete_intensite configuree, l'effective resout a 0.0 -- seuil infini, jamais expose, jamais un crash")

func _grand_feu_expose_a_une_distance_ou_le_petit_n_expose_pas(v) -> void:
	var petit := Objet.fabriquer("petit", "petit_feu_zorg", Vector3(0, 0, 0), TYPES_EMISSION, MATERIAUX_INTENSITE, [], RESERVE_ZORG)
	var grand := Objet.fabriquer("grand", "grand_feu_zorg", Vector3(0, 0, 0), TYPES_EMISSION, MATERIAUX_INTENSITE, [], RESERVE_ZORG)
	var cible_petit := Objet.fabriquer("cible_petit", "cible_vive", Vector3(20, 0, 0), TYPES_INTENSITE, MATERIAUX_INTENSITE, ["volatilite_zorg"])
	var cible_grand := Objet.fabriquer("cible_grand", "cible_vive", Vector3(20, 0, 0), TYPES_INTENSITE, MATERIAUX_INTENSITE, ["volatilite_zorg"])
	var monde_petit := [petit, cible_petit]
	var monde_grand := [grand, cible_grand]
	var exposition_petit := {}
	var exposition_grand := {}
	var jamais_petit := true
	var enflammee_grand := false
	for i in 500:
		var e1 := Propagation.avancer(monde_petit, MENACES_INTENSITE, exposition_petit, 0.1, {}, INTENSITE_ZORG, ETATS_ZORG, EMISSION_ZORG)
		if not e1.is_empty():
			jamais_petit = false
		var e2 := Propagation.avancer(monde_grand, MENACES_INTENSITE, exposition_grand, 0.1, {}, INTENSITE_ZORG, ETATS_ZORG, EMISSION_ZORG)
		if e2.has("cible_grand"):
			enflammee_grand = true
	v.v(jamais_petit, "a distance 20, le petit feu ne doit JAMAIS exposer une cible que le grand feu, lui, expose -- aucune distance ecrite a la main, seule la capacite differe")
	v.v(enflammee_grand, "le grand feu doit finir par enflammer la meme cible, a la meme distance, la ou le petit ne le fait jamais")

func _a_distance_egale_une_matiere_expose_et_l_autre_jamais(v) -> void:
	var feu_vive := Objet.fabriquer("f1", "grand_feu_zorg", Vector3(0, 0, 0), TYPES_EMISSION, MATERIAUX_INTENSITE, [], RESERVE_ZORG)
	var feu_faible := Objet.fabriquer("f2", "grand_feu_zorg", Vector3(0, 0, 0), TYPES_EMISSION, MATERIAUX_INTENSITE, [], RESERVE_ZORG)
	var vive := Objet.fabriquer("vive", "cible_vive", Vector3(20, 0, 0), TYPES_INTENSITE, MATERIAUX_INTENSITE, ["volatilite_zorg"])
	var faible := Objet.fabriquer("faible", "cible_faible", Vector3(20, 0, 0), TYPES_INTENSITE, MATERIAUX_INTENSITE, ["volatilite_zorg"])
	var monde_vive := [feu_vive, vive]
	var monde_faible := [feu_faible, faible]
	var exposition_vive := {}
	var exposition_faible := {}
	var enflammee_vive := false
	var jamais_faible := true
	for i in 500:
		var ev := Propagation.avancer(monde_vive, MENACES_INTENSITE, exposition_vive, 0.1, {}, INTENSITE_ZORG, ETATS_ZORG, EMISSION_ZORG)
		if ev.has("vive"):
			enflammee_vive = true
		var ef := Propagation.avancer(monde_faible, MENACES_INTENSITE, exposition_faible, 0.1, {}, INTENSITE_ZORG, ETATS_ZORG, EMISSION_ZORG)
		if not ef.is_empty():
			jamais_faible = false
	v.v(enflammee_vive, "a distance egale, la matiere la plus intense (0.9) doit finir par s'enflammer")
	v.v(jamais_faible, "a la MEME distance, la meme source, la matiere la moins intense (0.15) ne doit JAMAIS s'enflammer -- seul le seuil differe")

func _sans_emission_configuree_le_comportement_reste_celui_d_avant(v) -> void:
	var monde := [
		_source_corrode(Vector3(0, 0, 0)),
		Objet.fabriquer("vive_0", "cible_vive", Vector3(50, 0, 0), TYPES_INTENSITE, MATERIAUX_INTENSITE, ["volatilite_zorg"]),
	]
	var exposition := {}
	var enflammee := false
	for i in 200:
		var enflammees := Propagation.avancer(monde, MENACES_INTENSITE, exposition, 0.1, {}, INTENSITE_ZORG, ETATS_ZORG)
		if enflammees.has("vive_0"):
			enflammee = true
	v.v(enflammee, "sans le 8e parametre 'emission' (absent de cet appel), avancer() doit retomber EXACTEMENT sur le chemin portee_propagation/en_portee d'avant ce chantier -- inchange")
