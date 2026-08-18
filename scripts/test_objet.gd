extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_objet.gd
#
# Verrouille objet.gd : la fabrication resout les proprietes depuis la
# table (typeA/typeB memes proprietes -> fabriques pareil, typeC differe) ;
# muter les proprietes d'un objet fabrique ne contamine jamais le gabarit
# partage dans la table (duplicate(true)).
#
# Verrouille aussi la FUSION PAR COMPOSITION DE PAQUETS (PHASE 1, refonte
# session ulterieure) : un type ne recoit les proprietes d'AUCUN paquet
# sauf s'il declare lui-meme "herite": Array de noms de paquet, fusionnes
# DANS L'ORDRE DECLARE puis ecrases par le type -- jamais automatique,
# jamais devine (voir docs/design.md, "Le colon n'est pas un type parent").

const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

const TABLE := {
	"typeA": { "opaque": true, "solide": true },
	"typeB": { "opaque": true, "solide": true },
	"typeC": { "opaque": false, "solide": false },
}

const TABLE_AVEC_ENTITE := {
	"entite": { "engagement": null, "valeur_partagee": 100.0 },
	"agent": { "herite": ["entite"], "valeur_partagee": 1600.0, "vitesse": 150.0 },
	"objet_ordinaire": { "opaque": true },
	"pretend_heriter": { "herite": ["entite"], "vitesse": 42.0 },
}

const TABLE_SANS_ENTITE := {
	"agent_orphelin": { "herite": ["entite"], "vitesse": 1.0 },
}

const TABLE_COMPOSITION := {
	"paquet_a": { "poids": 1.0, "partage": "a" },
	"paquet_b": { "vitesse": 20.0, "partage": "b" },
	"type_compose": { "herite": ["paquet_a", "paquet_b"], "vitesse": 99.0, "propre": true },
	"type_paquet_manquant": { "herite": ["paquet_a", "paquet_fantome"], "propre": true },
}

const TABLE_HERITE_RECURSIF := {
	"paquet_lointain": { "vitesse": 5.0 },
	"paquet_intermediaire": { "herite": ["paquet_lointain"], "poids": 2.0 },
	"type_compose_intermediaire": { "herite": ["paquet_intermediaire"], "propre": true },
}

var verif := Verif.new()

func _init() -> void:
	_fabrication_resout_les_proprietes()
	_memes_proprietes_fabriques_pareil()
	_mutation_ne_contamine_pas_la_table()
	_herite_fusionne_entite_puis_ecrase_avec_le_type()
	_sans_herite_entite_est_ignoree_meme_presente()
	_paquet_absent_de_la_table_alarme_et_replie_sur_le_type()
	_fusion_ne_contamine_pas_le_gabarit_entite()
	_composition_a_deux_paquets_respecte_l_ordre_puis_le_type()
	_composition_paquet_absent_alarme_et_replie_sur_les_paquets_resolus()
	_paquet_intermediaire_avec_sa_propre_herite_alarme_sans_casser()
	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
	else:
		print("OK: PV0-a fabrication")
		quit(0)

func _fabrication_resout_les_proprietes() -> void:
	var o := Objet.fabriquer("obj_1", "typeA", Vector3(10, 0, 0), TABLE)
	verif.v(o.id == "obj_1", "id conserve")
	verif.v(o.position == Vector3(10, 0, 0), "position conservee")
	verif.v(o.proprietes.get("opaque") == true, "opaque resolu depuis la table")
	verif.v(o.proprietes.get("solide") == true, "solide resolu depuis la table")

func _memes_proprietes_fabriques_pareil() -> void:
	var a := Objet.fabriquer("a", "typeA", Vector3(0, 0, 0), TABLE)
	var b := Objet.fabriquer("b", "typeB", Vector3(50, 0, 0), TABLE)
	verif.v(a.proprietes == b.proprietes, "typeA et typeB memes proprietes fabriques pareil")
	var c := Objet.fabriquer("c", "typeC", Vector3(0, 0, 0), TABLE)
	verif.v(a.proprietes != c.proprietes, "typeC proprietes differentes reflete la table")

func _mutation_ne_contamine_pas_la_table() -> void:
	var a := Objet.fabriquer("a", "typeA", Vector3(0, 0, 0), TABLE)
	a.proprietes["opaque"] = false
	var a2 := Objet.fabriquer("a2", "typeA", Vector3(0, 0, 0), TABLE)
	verif.v(a2.proprietes.get("opaque") == true, "muter un objet n'altere pas le gabarit de la table")

func _herite_fusionne_entite_puis_ecrase_avec_le_type() -> void:
	var agent := Objet.fabriquer("a1", "agent", Vector3.ZERO, TABLE_AVEC_ENTITE)
	verif.v(agent.proprietes.has("engagement") and agent.proprietes.engagement == null,
		"herite : la propriete du paquet entite (engagement) doit apparaitre sur l'objet")
	verif.v(agent.proprietes.valeur_partagee == 1600.0,
		"herite : la propriete du type ecrase celle du paquet entite (valeur_partagee)")
	verif.v(agent.proprietes.vitesse == 150.0,
		"herite : une propriete propre au type (absente du paquet) doit rester presente")
	verif.v(not agent.proprietes.has("herite"),
		"la cle herite est une instruction de fabrication, jamais une propriete de l'objet")

func _sans_herite_entite_est_ignoree_meme_presente() -> void:
	var ordinaire := Objet.fabriquer("o1", "objet_ordinaire", Vector3.ZERO, TABLE_AVEC_ENTITE)
	verif.v(not ordinaire.proprietes.has("engagement"),
		"sans cle herite, un type ne recoit jamais les proprietes d'un paquet, meme si l'entree existe")
	verif.v(ordinaire.proprietes == {"opaque": true},
		"sans cle herite, seules les proprietes propres au type apparaissent")

# push_error non observable depuis ce test (voir verif.gd) : verrouille le
# REPLI (proprietes du type seul, cle herite retiree quand meme), pas
# l'alarme elle-meme -- meme convention que agir.gd/_verbe_par_poids.
func _paquet_absent_de_la_table_alarme_et_replie_sur_le_type() -> void:
	var orphelin := Objet.fabriquer("ag1", "agent_orphelin", Vector3.ZERO, TABLE_SANS_ENTITE)
	verif.v(not orphelin.proprietes.has("engagement"),
		"un paquet nomme absent de la table ne peut faire apparaitre aucune de ses proprietes")
	verif.v(orphelin.proprietes == {"vitesse": 1.0},
		"repli : seules les proprietes propres au type restent, cle herite quand meme retiree")

func _fusion_ne_contamine_pas_le_gabarit_entite() -> void:
	var agent_a := Objet.fabriquer("a2", "agent", Vector3.ZERO, TABLE_AVEC_ENTITE)
	agent_a.proprietes["engagement"] = {"cible_id": "peu_importe"}
	var agent_b := Objet.fabriquer("a3", "agent", Vector3.ZERO, TABLE_AVEC_ENTITE)
	verif.v(agent_b.proprietes.engagement == null,
		"muter la propriete fusionnee (engagement) d'un objet ne contamine ni le gabarit 'entite' " +
		"ni les fabrications suivantes")
	var autre_type := Objet.fabriquer("p1", "pretend_heriter", Vector3.ZERO, TABLE_AVEC_ENTITE)
	verif.v(autre_type.proprietes.engagement == null,
		"un second type qui herite independamment ne partage jamais la meme reference d'engagement")

func _composition_a_deux_paquets_respecte_l_ordre_puis_le_type() -> void:
	var compose := Objet.fabriquer("c1", "type_compose", Vector3.ZERO, TABLE_COMPOSITION)
	verif.v(compose.proprietes.poids == 1.0,
		"composition : une propriete propre au premier paquet (paquet_a) doit rester presente")
	verif.v(compose.proprietes.partage == "b",
		"composition : le second paquet (paquet_b) ecrase la cle commune du premier (ordre A puis B)")
	verif.v(compose.proprietes.vitesse == 99.0,
		"composition : le type ecrase la cle commune des paquets (vitesse), toujours en dernier")
	verif.v(compose.proprietes.propre == true,
		"composition : une propriete propre au type (absente des deux paquets) doit rester presente")
	verif.v(not compose.proprietes.has("herite"),
		"la cle herite est retiree du resultat, meme apres une composition a plusieurs paquets")

# push_error non observable depuis ce test (voir verif.gd) : verrouille le
# REPLI (paquets resolus + type, paquet fantome simplement ignore), pas
# l'alarme elle-meme -- meme convention que le cas a un seul paquet.
func _composition_paquet_absent_alarme_et_replie_sur_les_paquets_resolus() -> void:
	var incomplet := Objet.fabriquer("c2", "type_paquet_manquant", Vector3.ZERO, TABLE_COMPOSITION)
	verif.v(incomplet.proprietes.poids == 1.0,
		"un paquet resolu (paquet_a) continue de fusionner meme si un autre paquet nomme est absent")
	verif.v(incomplet.proprietes.partage == "a",
		"le paquet fantome, absent de la table, ne contribue et n'ecrase rien")
	verif.v(not incomplet.proprietes.has("vitesse"),
		"une propriete du paquet fantome (jamais resolu) ne peut jamais apparaitre")
	verif.v(incomplet.proprietes.propre == true,
		"la propriete propre au type reste presente malgre le paquet manquant")
	verif.v(not incomplet.proprietes.has("herite"),
		"la cle herite est retiree meme quand un paquet nomme n'a pas pu etre resolu")

# push_error non observable depuis ce test (voir verif.gd) : verrouille le
# REPLI (paquet intermediaire fusionne pour ses autres cles, sa propre
# herite ignoree sans etre resolue), pas l'alarme elle-meme -- meme
# convention que les deux cas ci-dessus.
func _paquet_intermediaire_avec_sa_propre_herite_alarme_sans_casser() -> void:
	var compose := Objet.fabriquer("x1", "type_compose_intermediaire", Vector3.ZERO, TABLE_HERITE_RECURSIF)
	verif.v(compose.proprietes.poids == 2.0,
		"le paquet intermediaire (paquet_intermediaire) reste fusionne pour ses AUTRES cles malgre sa propre herite ignoree")
	verif.v(not compose.proprietes.has("vitesse"),
		"le paquet nomme par la herite du paquet intermediaire (paquet_lointain) n'est JAMAIS resolu -- pas de recursion")
	verif.v(not compose.proprietes.has("herite"),
		"la cle herite du paquet intermediaire ne doit jamais survivre sur l'objet fabrique")
	verif.v(compose.proprietes.propre == true,
		"le type continue de fusionner normalement par-dessus le paquet intermediaire")
