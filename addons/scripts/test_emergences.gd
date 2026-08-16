extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_emergences.gd
#
# Verrouille objet.gd:_evaluer_emergences (chantier "proprietes emergentes --
# capacites conditionnelles a la fabrication"). Catalogue de materiaux, table
# de types ET catalogue d'emergences ENTIEREMENT FICTIFS, construits dans ce
# fichier -- jamais data/materiaux.json ni data/emergences.json, meme
# discipline que test_densite_effective.gd.
#
# Fonction testee via Objet.fabriquer (round-trip complet, pas d'appel direct
# a une fonction prefixee "_") : les deux conditions remplies posent la
# propriete emergente ; une seule condition remplie n'en pose aucune ; aucune
# condition remplie ne change rien ; deux emergences independantes se posent
# toutes les deux sur le meme objet ; un catalogue vide ne change rien ; une
# propriete absente de l'objet fait echouer sa condition (jamais un defaut
# permissif) ; un objet SANS composition traverse quand meme l'evaluation
# (l'emergence ne depend jamais de "composition").

const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

# Deux proprietes hors domaine, jamais rencontrees ailleurs dans le depot.
const MATERIAUX_FICTIFS := {
	"alliage_zorg": { "densite": 1.0, "conductivite_zorg": 900.0, "reactivite_zorg": 0.8 },
	"argile_zorg": { "densite": 1.0, "conductivite_zorg": 10.0, "reactivite_zorg": 0.1 },
}

const PROPRIETES_IMMUABLES_ZORG := ["conductivite_zorg", "reactivite_zorg"]

const TABLE := {
	"objet_haut": { "composition": [ { "materiau": "alliage_zorg", "volume": 1.0 } ] },
	"objet_bas": { "composition": [ { "materiau": "argile_zorg", "volume": 1.0 } ] },
	"objet_sans_composition": { "conductivite_zorg": 900.0, "reactivite_zorg": 0.8 },
}

const CATALOGUE_ETAT_ZORG := [
	{
		"id": "etat_zorg",
		"conditions": [
			{ "propriete": "conductivite_zorg", "operateur": ">=", "seuil": 500.0 },
			{ "propriete": "reactivite_zorg", "operateur": ">=", "seuil": 0.5 },
		],
		"resultat": { "etat_zorg": true },
	},
]

const CATALOGUE_DEUX_EMERGENCES := [
	{
		"id": "chaud_zorg",
		"conditions": [ { "propriete": "conductivite_zorg", "operateur": ">=", "seuil": 500.0 } ],
		"resultat": { "chaud_zorg": true },
	},
	{
		"id": "actif_zorg",
		"conditions": [ { "propriete": "reactivite_zorg", "operateur": ">=", "seuil": 0.5 } ],
		"resultat": { "actif_zorg": true },
	},
]

const CATALOGUE_PROPRIETE_ABSENTE := [
	{
		"id": "fantome_zorg",
		"conditions": [ { "propriete": "propriete_qui_nexiste_pas", "operateur": ">=", "seuil": 0.0 } ],
		"resultat": { "fantome_zorg": true },
	},
]

func _init() -> void:
	var v := Verif.new()
	_deux_conditions_remplies_pose_lemergence(v)
	_une_seule_condition_remplie_ne_pose_rien(v)
	_aucune_condition_remplie_ne_change_rien(v)
	_deux_emergences_independantes_se_posent_toutes_les_deux(v)
	_catalogue_vide_ne_change_rien(v)
	_propriete_absente_fait_echouer_sa_condition(v)
	_sans_composition_lemergence_reste_evaluee(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: emergences -- capacites conditionnelles a la fabrication, " +
			"ET logique sur les conditions, coexistence de plusieurs emergences, " +
			"propriete absente jamais permissive, independant de composition")
		quit(0)

func _deux_conditions_remplies_pose_lemergence(v) -> void:
	var o := Objet.fabriquer("h1", "objet_haut", Vector3.ZERO, TABLE, MATERIAUX_FICTIFS, PROPRIETES_IMMUABLES_ZORG, {}, CATALOGUE_ETAT_ZORG)
	v.v(not o.is_empty(), "un objet valide doit toujours se fabriquer")
	v.v(o.proprietes.get("etat_zorg", false) == true,
		"les deux conditions remplies (conductivite_zorg 900>=500, reactivite_zorg 0.8>=0.5) doivent poser l'emergence")

func _une_seule_condition_remplie_ne_pose_rien(v) -> void:
	# Catalogue a seuil de reactivite volontairement hors de portee : sur
	# objet_haut, conductivite_zorg (900) passe le premier seuil (500) mais
	# reactivite_zorg (0.8) ne peut jamais passer le second (999) -- isole
	# le cas UNE SEULE condition vraie sur deux (ET logique).
	var catalogue_une_seule_vraie := [
		{
			"id": "etat_impossible",
			"conditions": [
				{ "propriete": "conductivite_zorg", "operateur": ">=", "seuil": 500.0 },
				{ "propriete": "reactivite_zorg", "operateur": ">=", "seuil": 999.0 },
			],
			"resultat": { "etat_impossible": true },
		},
	]
	var o2 := Objet.fabriquer("h2", "objet_haut", Vector3.ZERO, TABLE, MATERIAUX_FICTIFS, PROPRIETES_IMMUABLES_ZORG, {}, catalogue_une_seule_vraie)
	v.v(o2.proprietes.get("conductivite_zorg", 0.0) >= 500.0, "pre-condition du test : la premiere condition doit passer seule")
	v.v(not o2.proprietes.has("etat_impossible"),
		"une seule condition vraie sur deux (ET logique) ne doit jamais poser l'emergence")

func _aucune_condition_remplie_ne_change_rien(v) -> void:
	var avant := Objet.fabriquer("b2", "objet_bas", Vector3.ZERO, TABLE, MATERIAUX_FICTIFS, PROPRIETES_IMMUABLES_ZORG)
	var apres := Objet.fabriquer("b3", "objet_bas", Vector3.ZERO, TABLE, MATERIAUX_FICTIFS, PROPRIETES_IMMUABLES_ZORG, {}, CATALOGUE_ETAT_ZORG)
	v.v(avant.proprietes == apres.proprietes,
		"aucune condition remplie : les proprietes fusionnees doivent rester EXACTEMENT identiques, rien ajoute")

func _deux_emergences_independantes_se_posent_toutes_les_deux(v) -> void:
	var o := Objet.fabriquer("h3", "objet_haut", Vector3.ZERO, TABLE, MATERIAUX_FICTIFS, PROPRIETES_IMMUABLES_ZORG, {}, CATALOGUE_DEUX_EMERGENCES)
	v.v(o.proprietes.get("chaud_zorg", false) == true, "premiere emergence independante doit se poser")
	v.v(o.proprietes.get("actif_zorg", false) == true, "seconde emergence independante doit AUSSI se poser sur le meme objet")

func _catalogue_vide_ne_change_rien(v) -> void:
	var avec_defaut := Objet.fabriquer("h4", "objet_haut", Vector3.ZERO, TABLE, MATERIAUX_FICTIFS)
	var avec_vide := Objet.fabriquer("h5", "objet_haut", Vector3.ZERO, TABLE, MATERIAUX_FICTIFS, [], {}, [])
	v.v(avec_defaut.proprietes == avec_vide.proprietes,
		"catalogue_emergences par defaut ([]) et catalogue_emergences explicitement vide doivent produire les memes proprietes")
	v.v(not avec_vide.proprietes.has("etat_zorg") and not avec_vide.proprietes.has("chaud_zorg"),
		"un catalogue vide ne doit jamais poser une propriete emergente, quelle que soit la table de proprietes")

func _propriete_absente_fait_echouer_sa_condition(v) -> void:
	var o := Objet.fabriquer("h6", "objet_haut", Vector3.ZERO, TABLE, MATERIAUX_FICTIFS, [], {}, CATALOGUE_PROPRIETE_ABSENTE)
	v.v(not o.proprietes.has("propriete_qui_nexiste_pas"), "pre-condition du test : la propriete visee ne doit jamais exister sur l'objet")
	v.v(not o.proprietes.has("fantome_zorg"),
		"une condition sur une propriete absente de l'objet doit echouer (repli false), jamais reussir par defaut 0.0")

func _sans_composition_lemergence_reste_evaluee(v) -> void:
	var o := Objet.fabriquer("s1", "objet_sans_composition", Vector3.ZERO, TABLE, MATERIAUX_FICTIFS, [], {}, CATALOGUE_ETAT_ZORG)
	v.v(not o.proprietes.has("composition"), "pre-condition du test : ce type ne doit jamais porter 'composition'")
	v.v(o.proprietes.get("etat_zorg", false) == true,
		"l'evaluation des emergences ne doit JAMAIS dependre de 'composition' -- un objet sans composition qui remplit les conditions gagne l'emergence comme n'importe quel autre")
