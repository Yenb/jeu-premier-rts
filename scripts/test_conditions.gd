extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_conditions.gd
#
# Verrouille scripts/conditions.gd (chantier "biomes -- conditions multiples
# -> type de terrain"). ENTIEREMENT HORS DOMAINE : aucun catalogue reel n'est
# lu (ni data/emergences.json, ni data/biomes.json), aucune propriete de ce
# fichier n'existe ailleurs dans le depot (suffixe "_vlok"), aucun nom de
# biome n'apparait -- si le mecanisme marche ici, il marche sur n'importe quel
# domaine. Meme discipline que test_emergences.gd (suffixe "_zorg").
#
# Couvre : les cinq operateurs ; ET logique (toutes les conditions vraies) ;
# une condition fausse sur deux ne pose rien ; REVERSIBILITE (pose puis
# retrait quand les conditions cessent d'etre remplies) ; DEFAUT NEUTRE (sans
# retirer_si_faux, rien n'est JAMAIS retire -- le contrat d'objet.gd) ; DEUX
# PASSES (une entree fausse ne retire jamais une cle qu'une entree vraie pose,
# quel que soit l'ordre du catalogue) ; catalogue vide ; entrees independantes
# simultanees ; propriete absente jamais permissive ; entree sans "conditions"
# ignoree sans rien poser ni retirer ; contenu de la trace rendue.

const Conditions = preload("res://scripts/conditions.gd")
const Verif = preload("res://scripts/verif.gd")

# Deux entrees INDEPENDANTES : chacune pose SA PROPRE cle, elles ne se
# marchent jamais dessus.
const CATALOGUE_INDEPENDANT := [
	{
		"id": "actif_vlok",
		"conditions": [
			{ "propriete": "flux_vlok", "operateur": ">=", "seuil": 10.0 },
			{ "propriete": "charge_vlok", "operateur": "<=", "seuil": 5.0 },
		],
		"resultat": { "actif_vlok": true },
	},
	{
		"id": "dense_vlok",
		"conditions": [ { "propriete": "charge_vlok", "operateur": "<", "seuil": 100.0 } ],
		"resultat": { "dense_vlok": true },
	},
]

# Deux entrees CONCURRENTES : elles posent LA MEME cle "mode_vlok". C'est le
# cas reel du chantier (quatre biomes posant tous "biome"), et la raison des
# DEUX PASSES de conditions.gd:evaluer.
const CATALOGUE_CONCURRENT := [
	{
		"id": "mode_haut",
		"conditions": [ { "propriete": "flux_vlok", "operateur": ">=", "seuil": 10.0 } ],
		"resultat": { "mode_vlok": "haut" },
	},
	{
		"id": "mode_bas",
		"conditions": [ { "propriete": "flux_vlok", "operateur": "<", "seuil": 10.0 } ],
		"resultat": { "mode_vlok": "bas" },
	},
]

func _init() -> void:
	var v := Verif.new()
	_toutes_conditions_remplies_pose_le_resultat(v)
	_une_condition_non_remplie_ne_pose_rien(v)
	_remplies_puis_non_remplies_retire_le_resultat(v)
	_sans_le_drapeau_rien_n_est_jamais_retire(v)
	_une_entree_fausse_ne_retire_jamais_ce_qu_une_vraie_pose(v)
	_catalogue_vide_ne_change_rien(v)
	_entrees_independantes_se_posent_toutes(v)
	_propriete_absente_fait_echouer_sa_condition(v)
	_entree_sans_conditions_ignoree(v)
	_les_cinq_operateurs(v)
	_condition_incomplete_et_operateur_inconnu_font_echouer_jamais_passer(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: conditions -- evaluateur multi-conditions rejouable, ET logique, " +
			"reversibilite par retirer_si_faux (defaut neutre : aucun retrait), " +
			"deux passes (une entree vraie gagne toujours sur une entree fausse), " +
			"propriete absente jamais permissive, cinq operateurs")
		quit(0)

func _toutes_conditions_remplies_pose_le_resultat(v) -> void:
	var p := { "flux_vlok": 20.0, "charge_vlok": 2.0 }
	var trace := Conditions.evaluer(p, CATALOGUE_INDEPENDANT, true)
	v.v(p.get("actif_vlok", false) == true,
		"les deux conditions remplies (flux 20>=10, charge 2<=5) doivent poser le resultat SUR proprietes")
	v.v(trace.poses.get("actif_vlok", false) == true,
		"la trace rendue doit porter, dans 'poses', ce qui vient d'etre fusionne")
	v.v(trace.retires.is_empty(),
		"aucune entree fausse n'ayant de cle a effacer, 'retires' doit rester vide")

func _une_condition_non_remplie_ne_pose_rien(v) -> void:
	# flux passe (20>=10), charge echoue (50 n'est pas <=5) -- ET logique.
	var p := { "flux_vlok": 20.0, "charge_vlok": 50.0 }
	Conditions.evaluer(p, CATALOGUE_INDEPENDANT, true)
	v.v(not p.has("actif_vlok"),
		"une seule condition vraie sur deux (ET logique) ne doit jamais poser le resultat")
	v.v(p.get("dense_vlok", false) == true,
		"pre-condition du test : l'AUTRE entree, elle, doit bien se poser (50<100)")

func _remplies_puis_non_remplies_retire_le_resultat(v) -> void:
	var p := { "flux_vlok": 20.0, "charge_vlok": 2.0 }
	Conditions.evaluer(p, CATALOGUE_INDEPENDANT, true)
	v.v(p.get("actif_vlok", false) == true, "pre-condition du test : le resultat doit d'abord etre pose")
	# Les conditions CESSENT d'etre remplies -- la chose n'est pas refabriquee,
	# c'est le monde autour d'elle qui a change.
	p["charge_vlok"] = 50.0
	var trace := Conditions.evaluer(p, CATALOGUE_INDEPENDANT, true)
	v.v(not p.has("actif_vlok"),
		"REVERSIBILITE : conditions remplies puis non remplies doivent RETIRER la cle de proprietes")
	v.v(trace.retires.has("actif_vlok"),
		"la trace rendue doit nommer, dans 'retires', la cle reellement effacee")
	# Troisieme passage : la cle n'existe plus, l'effacer serait un non-evenement.
	var trace3 := Conditions.evaluer(p, CATALOGUE_INDEPENDANT, true)
	v.v(trace3.retires.is_empty(),
		"une cle DEJA absente ne doit plus jamais reapparaitre dans 'retires' (jamais une trace qui clignote a chaque tick)")

func _sans_le_drapeau_rien_n_est_jamais_retire(v) -> void:
	# Contrat exact de objet.gd:_evaluer_emergences apres extraction : merge
	# seul, aucun retrait, quoi que disent les conditions.
	var p := { "flux_vlok": 20.0, "charge_vlok": 2.0 }
	Conditions.evaluer(p, CATALOGUE_INDEPENDANT)
	p["charge_vlok"] = 50.0
	var trace := Conditions.evaluer(p, CATALOGUE_INDEPENDANT)
	v.v(p.get("actif_vlok", false) == true,
		"DEFAUT NEUTRE : sans retirer_si_faux, une cle deja posee ne doit JAMAIS etre retiree")
	v.v(trace.retires.is_empty(),
		"DEFAUT NEUTRE : 'retires' doit rester vide sans retirer_si_faux")
	# Une cle posee A LA MAIN (patron : une propriete venue du type) que le
	# catalogue nomme sans jamais remplir ses conditions.
	var q := { "flux_vlok": 1.0, "charge_vlok": 500.0, "actif_vlok": true, "dense_vlok": true }
	Conditions.evaluer(q, CATALOGUE_INDEPENDANT)
	v.v(q.get("actif_vlok", false) == true and q.get("dense_vlok", false) == true,
		"DEFAUT NEUTRE : une cle posee ailleurs (type/paquet) ne doit jamais etre effacee par une entree non declenchee")

func _une_entree_fausse_ne_retire_jamais_ce_qu_une_vraie_pose(v) -> void:
	# DEUX PASSES. flux 20 : "mode_haut" est VRAIE (20>=10) et posee EN
	# PREMIER ; "mode_bas" est FAUSSE et vient APRES sur la MEME cle. En une
	# seule passe, elle effacerait ce que la premiere vient de poser.
	var p := { "flux_vlok": 20.0 }
	var trace := Conditions.evaluer(p, CATALOGUE_CONCURRENT, true)
	v.v(p.get("mode_vlok", "") == "haut",
		"une entree FAUSSE placee APRES une entree VRAIE sur la meme cle ne doit jamais effacer ce que la vraie a pose")
	v.v(trace.retires.is_empty(),
		"la cle etant reclamee par une entree vraie, elle ne doit jamais figurer dans 'retires'")
	# Sens inverse : "mode_haut" est FAUSSE et vient EN PREMIER, "mode_bas"
	# est VRAIE et vient APRES -- l'ordre ne doit rien changer.
	var q := { "flux_vlok": 1.0 }
	Conditions.evaluer(q, CATALOGUE_CONCURRENT, true)
	v.v(q.get("mode_vlok", "") == "bas",
		"l'ordre des entrees dans le catalogue ne doit jamais decider qu'une entree fausse l'emporte sur une vraie")
	# Bascule reelle d'une valeur a l'autre, sans jamais passer par l'absence.
	q["flux_vlok"] = 20.0
	Conditions.evaluer(q, CATALOGUE_CONCURRENT, true)
	v.v(q.get("mode_vlok", "") == "haut",
		"une valeur deja posee doit pouvoir etre REMPLACEE par celle d'une autre entree devenue vraie")

func _catalogue_vide_ne_change_rien(v) -> void:
	var p := { "flux_vlok": 20.0, "charge_vlok": 2.0 }
	var avant := p.duplicate(true)
	var trace := Conditions.evaluer(p, [], true)
	v.v(p == avant, "un catalogue vide ne doit RIEN changer sur proprietes")
	v.v(trace.poses.is_empty() and trace.retires.is_empty(),
		"un catalogue vide doit rendre une trace entierement vide")

func _entrees_independantes_se_posent_toutes(v) -> void:
	var p := { "flux_vlok": 20.0, "charge_vlok": 2.0 }
	Conditions.evaluer(p, CATALOGUE_INDEPENDANT, true)
	v.v(p.get("actif_vlok", false) == true and p.get("dense_vlok", false) == true,
		"deux entrees independantes remplies en meme temps doivent poser TOUTES LES DEUX leur resultat")

func _propriete_absente_fait_echouer_sa_condition(v) -> void:
	var catalogue := [
		{
			"id": "fantome_vlok",
			"conditions": [ { "propriete": "propriete_vlok_absente", "operateur": "<=", "seuil": 999.0 } ],
			"resultat": { "fantome_vlok": true },
		},
	]
	var p := { "flux_vlok": 20.0 }
	Conditions.evaluer(p, catalogue, true)
	v.v(not p.has("fantome_vlok"),
		"une condition sur une propriete absente doit echouer (repli false), jamais reussir par un defaut 0.0 permissif")
	v.v(not Conditions.remplies(p, catalogue[0].conditions),
		"remplies() doit rendre false sur une propriete absente, meme appelee directement")

func _entree_sans_conditions_ignoree(v) -> void:
	# Une entree cassee ne doit ni poser (verite par vacuite sur une liste
	# vide) ni compter comme fausse (elle effacerait alors du contenu).
	var catalogue := [ { "id": "cassee_vlok", "resultat": { "actif_vlok": true } } ]
	var p := { "actif_vlok": true }
	var trace := Conditions.evaluer(p, catalogue, true)
	v.v(p.get("actif_vlok", false) == true,
		"une entree sans 'conditions' doit etre ignoree, jamais comptee comme fausse -- elle ne retire rien")
	v.v(trace.poses.is_empty() and trace.retires.is_empty(),
		"une entree sans 'conditions' ne doit rien inscrire dans la trace")

# DEUX DONNEES CASSEES, MEME SORTIE : une condition a laquelle il manque un
# champ, et un operateur que le mecanisme ne sait pas jouer. Toutes deux
# alarment et font ECHOUER la condition -- jamais passer. Le sens compte :
# une condition cassee qui passerait poserait un resultat que rien ne
# justifie, et l'erreur de donnee se lirait comme un comportement du monde.
func _condition_incomplete_et_operateur_inconnu_font_echouer_jamais_passer(v) -> void:
	var p := { "flux_vlok": 10.0 }
	v.v(not Conditions.remplies(p, [ { "propriete": "flux_vlok", "operateur": ">=" } ]),
		"condition sans 'seuil' : alarme et echoue, jamais un seuil devine")
	v.v(not Conditions.remplies(p, [ { "operateur": ">=", "seuil": 1.0 } ]),
		"condition sans 'propriete' : alarme et echoue")
	v.v(not Conditions.remplies(p, [ { "propriete": "flux_vlok", "operateur": "~~", "seuil": 1.0 } ]),
		"operateur inconnu : alarme et echoue, jamais une comparaison devinee")

	var catalogue := [ { "conditions": [ { "propriete": "flux_vlok", "operateur": "~~", "seuil": 1.0 } ], "resultat": { "zorg": true } } ]
	var proprietes := p.duplicate()
	Conditions.evaluer(proprietes, catalogue)
	v.v(not proprietes.has("zorg"),
		"une entree a operateur inconnu ne pose RIEN sur les proprietes")

func _les_cinq_operateurs(v) -> void:
	var p := { "flux_vlok": 10.0 }
	v.v(Conditions.remplies(p, [ { "propriete": "flux_vlok", "operateur": ">=", "seuil": 10.0 } ]), "operateur >= : 10>=10 doit passer")
	v.v(Conditions.remplies(p, [ { "propriete": "flux_vlok", "operateur": "<=", "seuil": 10.0 } ]), "operateur <= : 10<=10 doit passer")
	v.v(not Conditions.remplies(p, [ { "propriete": "flux_vlok", "operateur": ">", "seuil": 10.0 } ]), "operateur > : 10>10 doit echouer")
	v.v(not Conditions.remplies(p, [ { "propriete": "flux_vlok", "operateur": "<", "seuil": 10.0 } ]), "operateur < : 10<10 doit echouer")
	v.v(Conditions.remplies(p, [ { "propriete": "flux_vlok", "operateur": "==", "seuil": 10.0 } ]), "operateur == : 10==10 doit passer")
	v.v(not Conditions.remplies(p, [ { "propriete": "flux_vlok", "operateur": "==", "seuil": 11.0 } ]), "operateur == : 10==11 doit echouer")
	v.v(Conditions.remplies(p, []), "une liste de conditions vide est vraie par vacuite (contrat assume, jamais atteint via evaluer)")
