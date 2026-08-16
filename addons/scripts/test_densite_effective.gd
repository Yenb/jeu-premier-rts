extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_densite_effective.gd
#
# Verrouille objet.gd:fabriquer -- DENSITE EFFECTIVE (chantier "la densite
# effective calculee a la fabrication", voir l'en-tete de objet.gd pour la
# doctrine complete). Ne charge AUCUN data/*.json : catalogue de materiaux
# et table de types entierement FICTIFS, construits dans ce fichier -- le
# modele ne doit connaitre aucun nom de materiau reel ("bois"/"pierre"),
# seulement une reference String et un nombre.
#
# Fonction pure testee via Objet.fabriquer (pas de couche, pas de noeud,
# pas de rendu) : mono-materiau egale au materiau seul, composite = moyenne
# ponderee exacte (conversion d'unite comprise), objet sans composition
# inchange, materiau absent refuse toute la fabrication (retour {}),
# composition vide refusee de la meme facon, resumabilite JSON stricte.

const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

# Densites en g/cm3, meme convention que data/materiaux.json -- jamais lu
# sur disque, ces deux entrees n'existent QUE dans ce test. "eclat_zorg"
# (chantier "feu -- inflammabilite effective", generalisation de la fusion
# a une propriete immuable AUTRE que densite) : cristal_lourd le porte
# volontairement PAS -- teste l'absence facultative (contribue 0.0, aucune
# alarme), contrairement a "densite". "combustible_zorg" (chantier "feu --
# la reserve de combustible suit la matiere") : meme absence volontaire
# sur cristal_lourd, cette fois pour la SOMME (extensive) plutot que la
# MOYENNE (intensive).
const MATERIAUX_FICTIFS := {
	"cristal_leger": { "densite": 0.2, "eclat_zorg": 0.9, "combustible_zorg": 0.6 },
	"cristal_lourd": { "densite": 8.0 },
}

const TABLE_MONO := {
	"eclat": { "composition": [ { "materiau": "cristal_leger", "volume": 5.0 } ] },
}

const TABLE_COMPOSITE := {
	"amalgame": {
		"composition": [
			{ "materiau": "cristal_leger", "volume": 2.0 },
			{ "materiau": "cristal_lourd", "volume": 3.0 },
		],
	},
}

const RESERVE_COMBUSTIBLE_CONFIG := {
	"nom_reserve": "combustible", "propriete_materiau": "combustible_zorg",
	"propriete_porosite": "porosite_zorg", "cout_base": 1.0,
	"facteur_densite": 0.0, "facteur_porosite": 0.0,
	"surcout_action": 0.0, "seuils_ref": "epuisement",
}

# Chantier "densite et porosite sur la vitesse de combustion" : facteurs
# NEUTRES (0.0) ci-dessus -- cout_base_effectif == cout_base_reference,
# preserve TOUTES les assertions deja ecrites sur RESERVE_COMBUSTIBLE_CONFIG
# ci-dessous sans les toucher. La modulation reelle (facteurs non nuls) est
# verifiee separement par RESERVE_COMBUSTIBLE_CONFIG_MODULE, plus bas.
const MATERIAUX_DENSITE_POROSITE := {
	"dense_compact_zorg": { "densite": 8.0, "combustible_zorg": 1.0, "porosite_zorg": 0.0 },
	"leger_poreux_zorg": { "densite": 0.1, "combustible_zorg": 1.0, "porosite_zorg": 0.9 },
	"sans_porosite_zorg": { "densite": 1.0, "combustible_zorg": 1.0 },
}

const TABLE_DENSE := {
	"bloc_dense": { "composition": [ { "materiau": "dense_compact_zorg", "volume": 4.0 } ] },
}

const TABLE_POREUSE := {
	"bloc_poreux": { "composition": [ { "materiau": "leger_poreux_zorg", "volume": 4.0 } ] },
}

const TABLE_SANS_POROSITE := {
	"bloc_neutre": { "composition": [ { "materiau": "sans_porosite_zorg", "volume": 4.0 } ] },
}

const RESERVE_COMBUSTIBLE_CONFIG_MODULE := {
	"nom_reserve": "combustible", "propriete_materiau": "combustible_zorg",
	"propriete_porosite": "porosite_zorg", "cout_base": 1.0,
	"facteur_densite": 0.5, "facteur_porosite": 1.3,
	"surcout_action": 0.0, "seuils_ref": "epuisement",
}

const TABLE_SANS_COMPOSITION := {
	"paquet_physique_fictif": { "masse": 1.0, "volume": 0.001, "densite": 1000.0, "temperature": 20.0 },
	"caillou_ordinaire": { "herite": ["paquet_physique_fictif"], "dur": true },
}

const TABLE_MATERIAU_ABSENT := {
	"reve": { "composition": [ { "materiau": "cristal_fantome", "volume": 1.0 } ] },
}

const TABLE_COMPOSITION_VIDE := {
	"neant": { "composition": [] },
}

func _init() -> void:
	var v := Verif.new()
	_mono_materiau_egale_le_materiau_seul(v)
	_composite_moyenne_ponderee_exacte(v)
	_sans_composition_traverse_fabriquer_inchange(v)
	_materiau_absent_refuse_toute_la_fabrication(v)
	_composition_vide_refuse_toute_la_fabrication(v)
	_resumabilite_json_stricte(v)
	_propriete_immuable_mono_materiau_egale_le_materiau_seul(v)
	_propriete_immuable_composite_moyenne_ponderee_absence_contribue_zero(v)
	_propriete_immuable_absente_du_parametre_ne_fusionne_rien(v)
	_propriete_immuable_sans_composition_ne_fusionne_rien(v)
	_densite_dans_proprietes_immuables_alarme_et_reste_le_calcul_dedie(v)
	_reserve_combustible_vide_ne_touche_pas_reserves(v)
	_reserve_combustible_mono_materiau_capacite_egale_reserve(v)
	_reserve_combustible_composite_somme_jamais_une_moyenne(v)
	_reserve_combustible_sans_composition_ne_touche_pas_reserves(v)
	_reserve_combustible_champ_manquant_alarme_et_ne_touche_pas_reserves(v)
	_reserve_combustible_fusionne_avec_des_reserves_preexistantes(v)
	_reserve_combustible_densite_haute_ralentit_cout_base(v)
	_reserve_combustible_porosite_haute_accelere_cout_base(v)
	_reserve_combustible_porosite_absente_dune_fiche_contribue_zero(v)
	_reserve_combustible_champs_densite_porosite_manquants_alarment(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: densite effective -- calculee une fois a la fabrication, moyenne ponderee des " +
			"volumes, mono-materiau et composite meme code, objet sans composition inchange, " +
			"materiau inconnu refuse la fabrication (retour {})")
		quit(0)

func _mono_materiau_egale_le_materiau_seul(v) -> void:
	var o := Objet.fabriquer("e1", "eclat", Vector3.ZERO, TABLE_MONO, MATERIAUX_FICTIFS)
	v.v(not o.is_empty(), "un seul materiau resolu doit produire un objet")
	v.v(is_equal_approx(o.proprietes.densite, 200.0),
		"mono-materiau : densite effective doit egaler la densite du seul materiau (0.2 g/cm3 -> 200.0 kg/m3)")
	v.v(is_equal_approx(o.proprietes.volume, 5.0),
		"mono-materiau : volume total doit egaler le volume du seul element de composition")
	v.v(is_equal_approx(o.proprietes.masse, 1000.0),
		"mono-materiau : masse doit egaler densite * volume (200.0 * 5.0)")

func _composite_moyenne_ponderee_exacte(v) -> void:
	var o := Objet.fabriquer("a1", "amalgame", Vector3.ZERO, TABLE_COMPOSITE, MATERIAUX_FICTIFS)
	v.v(not o.is_empty(), "deux materiaux resolus doivent produire un objet")
	# rho_leger = 0.2*1000 = 200.0 ; rho_lourd = 8.0*1000 = 8000.0
	# somme(rho*vol) = 200*2 + 8000*3 = 400 + 24000 = 24400 ; somme(vol) = 5.0
	var densite_attendue := 24400.0 / 5.0
	v.v(is_equal_approx(o.proprietes.densite, densite_attendue),
		"composite : densite doit egaler EXACTEMENT somme(rho_i*volume_i)/somme(volume_i), conversion g/cm3->kg/m3 comprise")
	v.v(o.proprietes.densite > 200.0 and o.proprietes.densite < 8000.0,
		"composite : la densite effective doit tomber strictement entre celles de ses deux materiaux")
	v.v(is_equal_approx(o.proprietes.volume, 5.0), "composite : volume total doit etre la somme des volumes")
	v.v(is_equal_approx(o.proprietes.masse, densite_attendue * 5.0),
		"composite : masse doit egaler densite effective * volume total, meme formule que le mono-materiau")

func _sans_composition_traverse_fabriquer_inchange(v) -> void:
	var o := Objet.fabriquer("c1", "caillou_ordinaire", Vector3.ZERO, TABLE_SANS_COMPOSITION, MATERIAUX_FICTIFS)
	v.v(not o.is_empty(), "un objet sans composition doit se fabriquer normalement")
	v.v(not o.proprietes.has("composition"), "sans composition sur le type, aucune cle composition ne doit apparaitre")
	v.v(o.proprietes.masse == 1.0 and o.proprietes.volume == 0.001 and o.proprietes.densite == 1000.0,
		"sans composition, masse/volume/densite doivent rester EXACTEMENT les defauts herites, jamais recalcules")
	v.v(o.proprietes.dur == true, "une propriete propre au type, sans rapport avec la composition, doit rester presente")

func _materiau_absent_refuse_toute_la_fabrication(v) -> void:
	var o := Objet.fabriquer("r1", "reve", Vector3.ZERO, TABLE_MATERIAU_ABSENT, MATERIAUX_FICTIFS)
	v.v(o.is_empty(),
		"un materiau absent du catalogue doit refuser TOUTE la fabrication -- retour {}, jamais une densite mensongere")

func _composition_vide_refuse_toute_la_fabrication(v) -> void:
	var o := Objet.fabriquer("n1", "neant", Vector3.ZERO, TABLE_COMPOSITION_VIDE, MATERIAUX_FICTIFS)
	v.v(o.is_empty(),
		"une composition vide (volume total nul) doit refuser la fabrication, meme severite qu'un materiau absent")

func _resumabilite_json_stricte(v) -> void:
	var o := Objet.fabriquer("a2", "amalgame", Vector3.ZERO, TABLE_COMPOSITE, MATERIAUX_FICTIFS)
	var texte := JSON.stringify(o.proprietes)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu == o.proprietes,
		"les proprietes calculees (composition/volume/densite/masse) doivent survivre un aller-retour JSON strict")

# GENERALISATION DE LA FUSION (chantier "feu -- inflammabilite effective") :
# proprietes_immuables recoit le nom en parametre, jamais en dur dans
# objet.gd -- verifie ici avec "eclat_zorg", un nom hors domaine absent de
# tout le reste du depot.
func _propriete_immuable_mono_materiau_egale_le_materiau_seul(v) -> void:
	var o := Objet.fabriquer("e2", "eclat", Vector3.ZERO, TABLE_MONO, MATERIAUX_FICTIFS, ["eclat_zorg"])
	v.v(not o.is_empty(), "un seul materiau resolu doit toujours produire un objet")
	v.v(is_equal_approx(o.proprietes.eclat_zorg, 0.9),
		"mono-materiau : la propriete immuable fusionnee doit egaler celle du seul materiau (0.9)")

func _propriete_immuable_composite_moyenne_ponderee_absence_contribue_zero(v) -> void:
	var o := Objet.fabriquer("a3", "amalgame", Vector3.ZERO, TABLE_COMPOSITE, MATERIAUX_FICTIFS, ["eclat_zorg"])
	# cristal_leger porte eclat_zorg=0.9 (volume 2.0) ; cristal_lourd ne le
	# porte PAS (volume 3.0, absence facultative -> contribue 0.0).
	var attendu := (0.9 * 2.0 + 0.0 * 3.0) / 5.0
	v.v(is_equal_approx(o.proprietes.eclat_zorg, attendu),
		"composite : une fiche materiau sans la propriete demandee contribue 0.0, aucune alarme, jamais un refus de fabrication")
	v.v(not o.is_empty(), "une propriete immuable absente d'UNE fiche ne doit jamais refuser la fabrication (contrairement a densite)")

func _propriete_immuable_absente_du_parametre_ne_fusionne_rien(v) -> void:
	var o := Objet.fabriquer("e3", "eclat", Vector3.ZERO, TABLE_MONO, MATERIAUX_FICTIFS)
	v.v(not o.proprietes.has("eclat_zorg"),
		"sans proprietes_immuables (defaut []), aucune propriete au-dela de densite/volume/masse ne doit apparaitre")

func _propriete_immuable_sans_composition_ne_fusionne_rien(v) -> void:
	var o := Objet.fabriquer("c2", "caillou_ordinaire", Vector3.ZERO, TABLE_SANS_COMPOSITION, MATERIAUX_FICTIFS, ["eclat_zorg"])
	v.v(not o.proprietes.has("eclat_zorg"),
		"un objet sans 'composition' ne doit jamais recevoir une propriete immuable, meme demandee explicitement -- meme GATE que densite")

func _densite_dans_proprietes_immuables_alarme_et_reste_le_calcul_dedie(v) -> void:
	var o := Objet.fabriquer("a4", "amalgame", Vector3.ZERO, TABLE_COMPOSITE, MATERIAUX_FICTIFS, ["densite", "eclat_zorg"])
	v.v(not o.is_empty(), "'densite' dans proprietes_immuables ne doit jamais faire echouer la fabrication -- alarme et entree ignoree")
	var densite_attendue := (200.0 * 2.0 + 8000.0 * 3.0) / 5.0
	v.v(is_equal_approx(o.proprietes.densite, densite_attendue),
		"'densite' demandee via proprietes_immuables doit rester EXACTEMENT le resultat du calcul dedie, jamais recalculee par le chemin generique")
	v.v(is_equal_approx(o.proprietes.eclat_zorg, (0.9 * 2.0 + 0.0 * 3.0) / 5.0),
		"les AUTRES proprietes de la liste continuent de se fusionner normalement malgre l'entree 'densite' fautive")

# RESERVE DE COMBUSTIBLE (chantier "feu -- la reserve de combustible suit
# la matiere") : reserve_combustible recoit sa config en parametre, jamais
# en dur dans objet.gd -- verifie ici avec "combustible_zorg" (SOMME,
# jamais une moyenne comme "eclat_zorg" ci-dessus).
func _reserve_combustible_vide_ne_touche_pas_reserves(v) -> void:
	var o := Objet.fabriquer("e4", "eclat", Vector3.ZERO, TABLE_MONO, MATERIAUX_FICTIFS)
	v.v(not o.proprietes.has("reserves"),
		"sans reserve_combustible (defaut {}), 'reserves' ne doit jamais apparaitre")

func _reserve_combustible_mono_materiau_capacite_egale_reserve(v) -> void:
	var o := Objet.fabriquer("e5", "eclat", Vector3.ZERO, TABLE_MONO, MATERIAUX_FICTIFS, [], RESERVE_COMBUSTIBLE_CONFIG)
	v.v(not o.is_empty(), "reserve_combustible ne doit jamais faire echouer une fabrication par ailleurs valide")
	var canal: Dictionary = o.proprietes.reserves.combustible
	# 0.6 * 5.0 = 3.0
	v.v(is_equal_approx(canal.capacite, 3.0), "mono-materiau : capacite doit egaler valeur_fiche * volume (0.6 * 5.0 = 3.0)")
	v.v(is_equal_approx(canal.reserve, canal.capacite), "a la fabrication, 'reserve' doit demarrer EXACTEMENT egale a 'capacite'")
	v.v(canal.cout_base == 1.0 and canal.surcout_action == 0.0 and canal.seuils_ref == "epuisement",
		"le canal doit porter cout_base/surcout_action/seuils_ref tels que declares dans la config, inchanges")

func _reserve_combustible_composite_somme_jamais_une_moyenne(v) -> void:
	var o := Objet.fabriquer("a5", "amalgame", Vector3.ZERO, TABLE_COMPOSITE, MATERIAUX_FICTIFS, [], RESERVE_COMBUSTIBLE_CONFIG)
	# cristal_leger (combustible_zorg=0.6, volume 2.0) + cristal_lourd (absent -> 0.0, volume 3.0)
	# somme = 0.6*2.0 + 0.0*3.0 = 1.2 -- PAS une moyenne (qui donnerait 0.24)
	v.v(is_equal_approx(o.proprietes.reserves.combustible.capacite, 1.2),
		"composite : capacite doit etre la SOMME ponderee (1.2), jamais une moyenne -- extensive, meme geste que champ.gd")

func _reserve_combustible_sans_composition_ne_touche_pas_reserves(v) -> void:
	var o := Objet.fabriquer("c3", "caillou_ordinaire", Vector3.ZERO, TABLE_SANS_COMPOSITION, MATERIAUX_FICTIFS, [], RESERVE_COMBUSTIBLE_CONFIG)
	v.v(not o.proprietes.has("reserves"),
		"un objet sans 'composition' ne doit JAMAIS recevoir de canal calcule, meme config fournie -- garde son forfait actuel ailleurs")

func _reserve_combustible_champ_manquant_alarme_et_ne_touche_pas_reserves(v) -> void:
	var config_incomplete := {"nom_reserve": "combustible", "propriete_materiau": "combustible_zorg", "cout_base": 1.0}
	var o := Objet.fabriquer("e6", "eclat", Vector3.ZERO, TABLE_MONO, MATERIAUX_FICTIFS, [], config_incomplete)
	v.v(not o.proprietes.has("reserves"),
		"une config incomplete (surcout_action/seuils_ref absents) doit alarmer et ne RIEN ecrire, jamais un canal partiel")

func _reserve_combustible_fusionne_avec_des_reserves_preexistantes(v) -> void:
	var table_avec_reserves := {
		"paquet_vivant": {"reserves": {"energie": {"reserve": 100.0}}},
		"creature_combustible": {"herite": ["paquet_vivant"], "composition": [{"materiau": "cristal_leger", "volume": 5.0}]},
	}
	var o := Objet.fabriquer("v1", "creature_combustible", Vector3.ZERO, table_avec_reserves, MATERIAUX_FICTIFS, [], RESERVE_COMBUSTIBLE_CONFIG)
	v.v(is_equal_approx(o.proprietes.reserves.energie.reserve, 100.0),
		"un canal de reserve deja present (herite d'un paquet) ne doit jamais etre efface par l'ajout du canal combustible")
	v.v(is_equal_approx(o.proprietes.reserves.combustible.capacite, 3.0),
		"le canal combustible doit s'ajouter AUX COTES des reserves preexistantes, jamais les remplacer")

# VITESSE DE COMBUSTION SELON LA MATIERE (chantier "densite et porosite sur
# la vitesse de combustion") : cout_base ecrit sur le canal n'est plus la
# constante de config -- il est module par la densite (ralentit) et la
# porosite (accelere) de la composition. Formule verifiee EXACTEMENT,
# noms de materiaux et de proprietes hors domaine.
func _reserve_combustible_densite_haute_ralentit_cout_base(v) -> void:
	var o := Objet.fabriquer("d1", "bloc_dense", Vector3.ZERO, TABLE_DENSE, MATERIAUX_DENSITE_POROSITE, [], RESERVE_COMBUSTIBLE_CONFIG_MODULE)
	v.v(not o.is_empty(), "un materiau dense doit produire un objet normalement")
	# densite 8.0 g/cm3, porosite 0.0 : 1.0 * (1+1.3*0.0) / (1+0.5*8.0) = 1.0/5.0 = 0.2
	v.v(is_equal_approx(o.proprietes.reserves.combustible.cout_base, 0.2),
		"un materiau dense et non poreux doit voir son cout_base EFFECTIF nettement REDUIT (combustion ralentie) -- attendu 0.2, reference 1.0")

func _reserve_combustible_porosite_haute_accelere_cout_base(v) -> void:
	var o := Objet.fabriquer("p1", "bloc_poreux", Vector3.ZERO, TABLE_POREUSE, MATERIAUX_DENSITE_POROSITE, [], RESERVE_COMBUSTIBLE_CONFIG_MODULE)
	v.v(not o.is_empty(), "un materiau poreux doit produire un objet normalement")
	# densite 0.1 g/cm3, porosite 0.9 : 1.0 * (1+1.3*0.9) / (1+0.5*0.1) = 2.17/1.05
	var attendu := 2.17 / 1.05
	v.v(is_equal_approx(o.proprietes.reserves.combustible.cout_base, attendu),
		"un materiau leger et poreux doit voir son cout_base EFFECTIF nettement AUGMENTE (combustion acceleree), attendu %.6f" % attendu)

func _reserve_combustible_porosite_absente_dune_fiche_contribue_zero(v) -> void:
	var o := Objet.fabriquer("n1", "bloc_neutre", Vector3.ZERO, TABLE_SANS_POROSITE, MATERIAUX_DENSITE_POROSITE, [], RESERVE_COMBUSTIBLE_CONFIG_MODULE)
	v.v(not o.is_empty(), "une fiche sans la propriete de porosite ne doit jamais refuser la fabrication -- absence facultative, comme pour les proprietes immuables")
	# densite 1.0, porosite absente -> 0.0 : 1.0 * (1+1.3*0.0) / (1+0.5*1.0) = 1.0/1.5
	var attendu := 1.0 / 1.5
	v.v(is_equal_approx(o.proprietes.reserves.combustible.cout_base, attendu),
		"une fiche materiau sans 'porosite_zorg' doit contribuer 0.0 a la porosite effective, sans alarme -- attendu %.6f" % attendu)

func _reserve_combustible_champs_densite_porosite_manquants_alarment(v) -> void:
	var config_sans_facteurs := {
		"nom_reserve": "combustible", "propriete_materiau": "combustible_zorg",
		"cout_base": 1.0, "surcout_action": 0.0, "seuils_ref": "epuisement",
	}
	var o := Objet.fabriquer("d2", "bloc_dense", Vector3.ZERO, TABLE_DENSE, MATERIAUX_DENSITE_POROSITE, [], config_sans_facteurs)
	v.v(not o.proprietes.has("reserves"),
		"une config sans 'propriete_porosite'/'facteur_densite'/'facteur_porosite' doit alarmer et ne RIEN ecrire, meme severite que les cinq champs deja requis")
