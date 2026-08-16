extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_animal.gd
#
# Verrouille le cablage pur de banc_animal.gd (cible_besoin, bouger_vers) et
# leur composition avec depense.gd + flux.gd (non modifies, deja prouves
# generiques ailleurs) : sans source a portee, les reserves de l'animal
# chutent (depense) ; a portee de la bonne source, la reserve visee remonte
# pendant que l'autre continue de chuter (flux) ; cible_besoin vise la chose
# la plus proche portant la propriete qui recharge la reserve la plus basse.
#
# Verrouille aussi la correction d'oscillation (dithering), portee depuis
# PHASE 1 par scripts/couplage.gd (mecanisme generique) + cible_besoin (le
# seul cote propre a ce banc, voir banc_animal.gd) : HYSTERESIS
# (engagement.seuil_bascule -- un ecart marginal ne fait pas changer
# d'engagement, verifiee ICI par cible_besoin, pas par couplage.gd) et
# ENGAGEMENT JUSQU'A SATISFACTION (engagement.seuil_satisfait,
# sens_satisfaction "sur_seuil" -- Couplage.avancer libere l'engagement des
# que la reserve visee depasse ce seuil). Un cas a trois reserves prouve
# qu'aucun mecanisme n'est cable a deux.

const BancAnimal = preload("res://scripts/banc_animal.gd")
const Couplage = preload("res://scripts/couplage.gd")
const Depense = preload("res://scripts/depense.gd")
const Flux = preload("res://scripts/flux.gd")
const Verif = preload("res://scripts/verif.gd")

const TABLE_FLUX := [
	{ "source": "lumineux", "receptrice": "phototrophe", "cible": "energie" },
	{ "source": "nourrissant", "receptrice": "brouteur", "cible": "matiere" },
]

# Catalogue LOCAL, invente pour ce test -- jamais data/engagements.json (ce
# fichier ne touche pas au disque). Reprend la forme reelle de la regle
# "animal_reserve" (voir data/engagements.json) avec les seuils historiques
# de ce test (16.0/4.0), inchanges depuis avant PHASE 1.
const CATALOGUE_ENGAGEMENTS := {
	"animal_reserve": {
		"poids": 1.0,
		"seuil_satisfait": 16.0,
		"seuil_bascule": 4.0,
		"sens_satisfaction": "sur_seuil",
		"satisfait_par": "reserves.{canal}.reserve",
	},
}

func _init() -> void:
	var v := Verif.new()
	_sans_source_les_deux_reserves_chutent(v)
	_a_portee_de_la_bonne_source_la_reserve_visee_remonte(v)
	_cible_besoin_libre_vise_la_ressource_la_plus_basse(v)
	_hysteresis_ne_bascule_pas_pour_un_ecart_faible(v)
	_hysteresis_bascule_quand_ecart_depasse_seuil(v)
	_engagement_libere_quand_satisfait_meme_a_trois_reserves(v)
	_couleur_de_lit_le_type_pose_jamais_le_defaut(v)
	if v.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % v.echecs())
		quit(1)
		return
	print("OK: sans source les reserves chutent, a portee la reserve visee remonte, " +
		"cible_besoin vise la ressource la plus basse, hysteresis empeche l'oscillation, " +
		"l'engagement tient jusqu'a satisfaction, generique a 3 reserves")
	quit(0)

func _animal(pos: Vector3, energie: float, matiere: float) -> Dictionary:
	return {
		"id": "animal",
		"position": pos,
		"proprietes": {
			"phototrophe": true,
			"brouteur": true,
			"engagement": null,
			"reserves": {
				"energie": { "reserve": energie, "cout_base": 1.0 },
				"matiere": { "reserve": matiere, "cout_base": 1.0 },
			},
		},
	}

func _lumiere(pos: Vector3) -> Dictionary:
	return {
		"id": "lumiere",
		"position": pos,
		"proprietes": { "lumineux": true, "portee_flux": 260.0, "taux_flux": 6.0 },
	}

func _herbe(pos: Vector3) -> Dictionary:
	return {
		"id": "herbe",
		"position": pos,
		"proprietes": { "nourrissant": true, "portee_flux": 220.0, "taux_flux": 6.0 },
	}

func _sans_source_les_deux_reserves_chutent(v) -> void:
	var animal := _animal(Vector3.ZERO, 20.0, 20.0)
	var monde := [animal]
	for i in 10:
		Depense.avancer(monde, 1.0)
	var reserves: Dictionary = animal.proprietes.reserves
	v.v(reserves.energie.reserve < 20.0, "sans source, energie doit chuter (depense seul)")
	v.v(reserves.matiere.reserve < 20.0, "sans source, matiere doit chuter (depense seul)")

func _a_portee_de_la_bonne_source_la_reserve_visee_remonte(v) -> void:
	var animal := _animal(Vector3.ZERO, 10.0, 10.0)
	var lumiere := _lumiere(Vector3(50, 0, 0))
	var monde := [animal, lumiere]
	for i in 5:
		Depense.avancer(monde, 1.0)
		Flux.avancer(monde, TABLE_FLUX, 1.0)
	var reserves: Dictionary = animal.proprietes.reserves
	v.v(reserves.energie.reserve > 10.0,
		"a portee de la lumiere, energie doit remonter (taux_flux 6.0 > cout_base 1.0)")
	v.v(reserves.matiere.reserve < 10.0,
		"sans herbe a portee, matiere doit continuer de chuter par le meme code")

func _cible_besoin_libre_vise_la_ressource_la_plus_basse(v) -> void:
	var pos_animal := Vector3(0, 0, 0)
	var pos_lumiere := Vector3(100, 0, 0)
	var pos_herbe := Vector3(-100, 0, 0)

	var energie_basse := _animal(pos_animal, 2.0, 15.0)
	var monde_a := [_lumiere(pos_lumiere), _herbe(pos_herbe)]
	var position_a := BancAnimal.cible_besoin(
		energie_basse, monde_a, TABLE_FLUX, pos_animal, 1.0, CATALOGUE_ENGAGEMENTS)
	v.v(position_a.distance_to(pos_lumiere) < 1.0,
		"libre, energie la plus basse : doit viser la lumiere")
	v.v(energie_basse.proprietes.engagement.canal == "energie",
		"libre : l'engagement doit se poser sur energie")

	var matiere_basse := _animal(pos_animal, 15.0, 2.0)
	var monde_b := [_lumiere(pos_lumiere), _herbe(pos_herbe)]
	var position_b := BancAnimal.cible_besoin(
		matiere_basse, monde_b, TABLE_FLUX, pos_animal, 1.0, CATALOGUE_ENGAGEMENTS)
	v.v(position_b.distance_to(pos_herbe) < 1.0,
		"libre, matiere la plus basse : doit viser l'herbe")
	v.v(matiere_basse.proprietes.engagement.canal == "matiere",
		"libre : l'engagement doit se poser sur matiere")

# LA serrure hysteresis : engage sur energie, matiere plus basse mais d'un
# ecart INFERIEUR a seuil_bascule (4.0) -- ne doit PAS faire changer d'avis.
func _hysteresis_ne_bascule_pas_pour_un_ecart_faible(v) -> void:
	var animal := _animal(Vector3.ZERO, 10.0, 8.0)
	var lumiere := _lumiere(Vector3(50, 0, 0))
	var monde := [lumiere]
	Couplage.poser(animal, lumiere, "animal_reserve", CATALOGUE_ENGAGEMENTS, {"canal": "energie"})
	BancAnimal.cible_besoin(animal, monde, TABLE_FLUX, Vector3.ZERO, 1.0, CATALOGUE_ENGAGEMENTS)
	v.v(animal.proprietes.engagement.canal == "energie",
		"ecart de 2.0 < seuil_bascule 4.0 : doit rester engage sur energie")

# LA serrure inverse : le meme engage, mais l'ecart DEPASSE seuil_bascule --
# doit basculer.
func _hysteresis_bascule_quand_ecart_depasse_seuil(v) -> void:
	var animal := _animal(Vector3.ZERO, 10.0, 4.0)
	var lumiere := _lumiere(Vector3(50, 0, 0))
	var herbe := _herbe(Vector3(-50, 0, 0))
	var monde := [lumiere, herbe]
	Couplage.poser(animal, lumiere, "animal_reserve", CATALOGUE_ENGAGEMENTS, {"canal": "energie"})
	BancAnimal.cible_besoin(animal, monde, TABLE_FLUX, Vector3.ZERO, 1.0, CATALOGUE_ENGAGEMENTS)
	v.v(animal.proprietes.engagement.canal == "matiere",
		"ecart de 6.0 > seuil_bascule 4.0 : doit basculer vers matiere")

# LA serrure generaliste : trois reserves, pour prouver que rien n'est cable
# a deux. R1 engage et deja au-dessus de seuil_satisfait (16.0) -> libere et
# rechoisit la pire (R2) ; puis, engage sur R1 NON satisfait avec un ecart
# insuffisant vers R2 -> reste engage ; puis avec un ecart suffisant ->
# bascule. Meme fonction, memes seuils, un canal de plus, zero ligne
# ajoutee au moteur de decision.
func _engagement_libere_quand_satisfait_meme_a_trois_reserves(v) -> void:
	var table_trois := [
		{ "source": "src_r1", "receptrice": "recu_r1", "cible": "r1" },
		{ "source": "src_r2", "receptrice": "recu_r2", "cible": "r2" },
		{ "source": "src_r3", "receptrice": "recu_r3", "cible": "r3" },
	]
	var proprietes := func(r1: float, r2: float, r3: float) -> Dictionary:
		return {
			"engagement": null,
			"reserves": {
				"r1": { "reserve": r1, "cout_base": 1.0 },
				"r2": { "reserve": r2, "cout_base": 1.0 },
				"r3": { "reserve": r3, "cout_base": 1.0 },
			},
		}
	var source := func(id: String, propriete: String) -> Dictionary:
		return {"id": id, "position": Vector3.ZERO, "proprietes": {propriete: true}}

	var monde_trois := [
		source.call("source_r1", "src_r1"),
		source.call("source_r2", "src_r2"),
		source.call("source_r3", "src_r3"),
	]

	# R1 engage, satisfait (17.0 > 16.0) -> libere, rechoisit la pire (r2).
	var animal_satisfait := {"id": "a1", "position": Vector3.ZERO, "proprietes": proprietes.call(17.0, 5.0, 10.0)}
	Couplage.poser(animal_satisfait, monde_trois[0], "animal_reserve", CATALOGUE_ENGAGEMENTS, {"canal": "r1"})
	BancAnimal.cible_besoin(animal_satisfait, monde_trois, table_trois, Vector3.ZERO, 1.0, CATALOGUE_ENGAGEMENTS)
	v.v(animal_satisfait.proprietes.engagement.canal == "r2",
		"r1 satisfait (17.0 > seuil_satisfait) doit liberer et rechoisir la pire (r2)")

	# R1 engage, non satisfait (10.0), r2 plus bas mais d'un ecart insuffisant.
	var animal_ecart_faible := {"id": "a2", "position": Vector3.ZERO, "proprietes": proprietes.call(10.0, 7.0, 20.0)}
	Couplage.poser(animal_ecart_faible, monde_trois[0], "animal_reserve", CATALOGUE_ENGAGEMENTS, {"canal": "r1"})
	BancAnimal.cible_besoin(animal_ecart_faible, monde_trois, table_trois, Vector3.ZERO, 1.0, CATALOGUE_ENGAGEMENTS)
	v.v(animal_ecart_faible.proprietes.engagement.canal == "r1",
		"r1 non satisfait, ecart vers r2 insuffisant : doit rester engage sur r1")

	# Meme etat de depart, mais r2 assez bas pour depasser seuil_bascule.
	var animal_ecart_fort := {"id": "a3", "position": Vector3.ZERO, "proprietes": proprietes.call(10.0, 3.0, 20.0)}
	Couplage.poser(animal_ecart_fort, monde_trois[0], "animal_reserve", CATALOGUE_ENGAGEMENTS, {"canal": "r1"})
	BancAnimal.cible_besoin(animal_ecart_fort, monde_trois, table_trois, Vector3.ZERO, 1.0, CATALOGUE_ENGAGEMENTS)
	v.v(animal_ecart_fort.proprietes.engagement.canal == "r2",
		"r1 non satisfait, ecart vers r2 suffisant : doit basculer vers r2")

# Audit couverture 2026-08-06 : _couleur_de est une fonction INSTANCE,
# aucune appelee par un test avant cette session. Meme patron que les
# autres bancs : BancAnimal.new() nu, jamais ajoute a l'arbre.
func _couleur_de_lit_le_type_pose_jamais_le_defaut(v) -> void:
	var b := BancAnimal.new()
	b._couleurs_types = {"animal": [0.9, 0.2, 0.1], "lumiere": [0.1, 0.6, 0.9]}
	v.v(b._couleur_de("animal") == Color(0.9, 0.2, 0.1), "doit rendre la couleur posee pour 'animal', pas le defaut blanc")
	v.v(b._couleur_de("lumiere") == Color(0.1, 0.6, 0.9), "doit distinguer deux types poses")
	v.v(b._couleur_de("inconnu") == Color(1.0, 1.0, 1.0), "un type absent doit rendre le blanc par defaut, jamais alarmer")
