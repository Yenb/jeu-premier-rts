extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_quantite_matiere.gd
#
# Verrouille scripts/quantite_matiere.gd -- calcul PUR, hors domaine par
# construction (materiaux/propriete FICTIFS, jamais lus sur disque). Ce
# fichier extrait le geste deja present (prive) dans champ.gd:
# _quantite_matiere -- ces tests prouvent que la version PARTAGEE se
# comporte EXACTEMENT comme l'original documente (somme, pas moyenne).

const QuantiteMatiere = preload("res://scripts/quantite_matiere.gd")
const Verif = preload("res://scripts/verif.gd")

const MATERIAUX_FICTIFS := {
	"alliage_zorg": {"densite": 1.0, "combustible_zorg": 0.8},
	"gel_zorg": {"densite": 1.0, "combustible_zorg": 0.1},
	"inerte_zorg": {"densite": 1.0},
}

func _init() -> void:
	var v := Verif.new()
	_sans_composition_rend_zero(v)
	_mono_materiau_egale_valeur_fois_volume(v)
	_composite_somme_jamais_une_moyenne(v)
	_propriete_absente_de_la_fiche_contribue_zero_sans_alarme(v)
	_materiau_absent_du_catalogue_contribue_zero_et_alarme(v)
	_ne_mute_jamais_proprietes(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: quantite_matiere.gd -- somme ponderee par volume sur une composition, jamais une " +
			"moyenne, propriete absente d'une fiche contribue 0.0 sans alarme, materiau absent alarme " +
			"et contribue 0.0 sans bloquer les autres elements, chemin mort sans composition")
		quit(0)

func _chose(composition: Variant) -> Dictionary:
	var proprietes: Dictionary = {}
	if composition != null:
		proprietes["composition"] = composition
	return {"id": "z", "position": Vector3.ZERO, "proprietes": proprietes}

func _sans_composition_rend_zero(v) -> void:
	var chose := _chose(null)
	v.v(is_equal_approx(QuantiteMatiere.quantite(chose.proprietes, "combustible_zorg", MATERIAUX_FICTIFS), 0.0),
		"une chose sans 'composition' doit rendre 0.0, chemin mort")

func _mono_materiau_egale_valeur_fois_volume(v) -> void:
	var chose := _chose([{"materiau": "alliage_zorg", "volume": 5.0}])
	v.v(is_equal_approx(QuantiteMatiere.quantite(chose.proprietes, "combustible_zorg", MATERIAUX_FICTIFS), 4.0),
		"mono-materiau : quantite doit egaler valeur_fiche * volume (0.8 * 5.0 = 4.0)")

func _composite_somme_jamais_une_moyenne(v) -> void:
	var chose := _chose([
		{"materiau": "alliage_zorg", "volume": 5.0},
		{"materiau": "gel_zorg", "volume": 5.0},
	])
	# somme = 0.8*5.0 + 0.1*5.0 = 4.5 -- PAS une moyenne (qui donnerait 0.45)
	v.v(is_equal_approx(QuantiteMatiere.quantite(chose.proprietes, "combustible_zorg", MATERIAUX_FICTIFS), 4.5),
		"composite : quantite doit etre la SOMME ponderee (4.5), jamais une moyenne (0.45) -- extensive, pas intensive")

func _propriete_absente_de_la_fiche_contribue_zero_sans_alarme(v) -> void:
	var chose := _chose([
		{"materiau": "alliage_zorg", "volume": 2.0},
		{"materiau": "inerte_zorg", "volume": 10.0},
	])
	# inerte_zorg ne porte pas combustible_zorg -> contribue 0.0, ne dilue pas alliage_zorg
	v.v(is_equal_approx(QuantiteMatiere.quantite(chose.proprietes, "combustible_zorg", MATERIAUX_FICTIFS), 1.6),
		"une fiche sans la propriete demandee doit contribuer 0.0 sans jamais diluer la contribution des autres elements (0.8*2.0 = 1.6)")

func _materiau_absent_du_catalogue_contribue_zero_et_alarme(v) -> void:
	var chose := _chose([
		{"materiau": "fantome_zorg", "volume": 100.0},
		{"materiau": "alliage_zorg", "volume": 1.0},
	])
	v.v(is_equal_approx(QuantiteMatiere.quantite(chose.proprietes, "combustible_zorg", MATERIAUX_FICTIFS), 0.8),
		"un materiau absent du catalogue doit contribuer 0.0 (alarme) sans empecher les AUTRES elements de contribuer")

func _ne_mute_jamais_proprietes(v) -> void:
	var chose := _chose([{"materiau": "alliage_zorg", "volume": 5.0}])
	var avant := JSON.stringify(chose.proprietes)
	QuantiteMatiere.quantite(chose.proprietes, "combustible_zorg", MATERIAUX_FICTIFS)
	var apres := JSON.stringify(chose.proprietes)
	v.v(avant == apres, "quantite() ne doit jamais muter 'proprietes' -- fonction PURE, calcul seul")
