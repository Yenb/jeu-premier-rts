extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_velocite.gd
#
# Verrouille scripts/velocite.gd comme DERIVATION PASSIVE, jamais comme un
# code de deplacement : ce fichier ne mute jamais "position" lui-meme, il
# ne fait qu'observer deux positions successives et en deriver une
# velocite. Objets fictifs, sans aucun rapport avec un phenomene reel --
# meme discipline hors domaine que test_champ.gd.
#
# Fonction pure au sens large (mute "proprietes", jamais "position") :
# aucune couche, aucun noeud, aucun rendu.

const Velocite = preload("res://scripts/velocite.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_objet_deplace_produit_velocite_exacte(v)
	_objet_immobile_velocite_nulle(v)
	_premier_tick_sans_historique_velocite_nulle_sans_crash(v)
	_deux_mutations_meme_tick_produisent_la_velocite_nette(v)
	_delta_quasi_nul_ne_produit_jamais_de_velocite_infinie(v)
	_objet_sans_position_ignore_sans_crash(v)
	_resumabilite_json_stricte(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: velocite.gd derive une velocite passive depuis deux positions " +
			"successives, capture le deplacement net quel que soit le nombre de " +
			"mutations dans le tick, jamais infinie a delta quasi nul, ignore un " +
			"objet sans position")
		quit(0)

func _chose(id: String, position: Vector3) -> Dictionary:
	return {"id": id, "position": position, "proprietes": {}}

func _objet_deplace_produit_velocite_exacte(v) -> void:
	var a := _chose("a", Vector3.ZERO)
	Velocite.avancer([a], 1.0)
	a.position = Vector3(10.0, 0.0, 0.0)
	Velocite.avancer([a], 1.0)
	v.v(a.proprietes.velocite.is_equal_approx(Vector3(10.0, 0.0, 0.0)),
		"un objet deplace de (10,0,0) en 1 seconde doit avoir une velocite de (10,0,0), recu %s" % a.proprietes.velocite)

func _objet_immobile_velocite_nulle(v) -> void:
	var a := _chose("a", Vector3(5.0, 5.0, 0.0))
	Velocite.avancer([a], 1.0)
	Velocite.avancer([a], 1.0)
	v.v(a.proprietes.velocite == Vector3.ZERO,
		"un objet qui ne bouge jamais doit avoir une velocite exactement nulle, recu %s" % a.proprietes.velocite)

func _premier_tick_sans_historique_velocite_nulle_sans_crash(v) -> void:
	var a := _chose("a", Vector3(3.0, 4.0, 0.0))
	var ids := Velocite.avancer([a], 1.0)
	v.v(a.proprietes.velocite == Vector3.ZERO,
		"sans position_precedente prealable, le premier tick doit rendre une velocite nulle, jamais crasher")
	v.v(a.proprietes.get("position_precedente") == Vector3(3.0, 4.0, 0.0),
		"position_precedente doit s'initialiser a la position courante au premier tick")
	v.v(ids.is_empty(),
		"au premier tick, la velocite nulle ne differe pas du defaut absent -- aucun changement a signaler")

func _deux_mutations_meme_tick_produisent_la_velocite_nette(v) -> void:
	var a := _chose("a", Vector3.ZERO)
	Velocite.avancer([a], 1.0)
	# Simule banc_champ.gd : un pas volontaire PUIS une deviation de champ,
	# deux mecanismes qui mutent position dans le MEME tick sans se
	# connaitre, avant que Velocite.avancer ne soit appele UNE SEULE FOIS.
	a.position += Vector3(3.0, 0.0, 0.0)
	a.position += Vector3(2.0, 0.0, 0.0)
	Velocite.avancer([a], 1.0)
	v.v(a.proprietes.velocite.is_equal_approx(Vector3(5.0, 0.0, 0.0)),
		"la velocite doit capturer le deplacement NET des deux mutations (5,0,0), jamais une seule contribution, recu %s" % a.proprietes.velocite)

func _delta_quasi_nul_ne_produit_jamais_de_velocite_infinie(v) -> void:
	var a := _chose("a", Vector3.ZERO)
	Velocite.avancer([a], 1.0)
	a.position = Vector3(1.0, 0.0, 0.0)
	Velocite.avancer([a], 0.0000001)
	var velocite: Vector3 = a.proprietes.velocite
	v.v(not (is_inf(velocite.x) or is_nan(velocite.x)),
		"un delta quasi nul ne doit jamais produire une velocite infinie ou NaN")
	v.v(velocite.length() < 1.0 / Velocite.SEUIL_DELTA_MINIMAL * 2.0,
		"la velocite doit rester bornee par le plancher applique au denominateur, jamais s'envoler")
	var b := _chose("b", Vector3.ZERO)
	Velocite.avancer([b], 1.0)
	b.position = Vector3(1.0, 0.0, 0.0)
	Velocite.avancer([b], 0.0)
	v.v(not (is_inf(b.proprietes.velocite.x) or is_nan(b.proprietes.velocite.x)),
		"un delta EXACTEMENT nul ne doit jamais produire une division par zero")

func _objet_sans_position_ignore_sans_crash(v) -> void:
	var sans_position := {"id": "sans_position", "proprietes": {}}
	var ids := Velocite.avancer([sans_position], 1.0)
	v.v(ids.is_empty(), "un objet sans 'position' ne doit jamais apparaitre dans les ids changes")
	v.v(not sans_position.proprietes.has("velocite"),
		"un objet sans 'position' ne doit jamais recevoir de velocite calculee")

# Verifie sans crash uniquement -- constate empiriquement (Godot 4.7) : un
# Vector3 se serialise en STRING "(x, y, z)" par JSON.stringify, jamais un
# Array ni un Dictionary {x,y,z} -- meme constat que test_deformation.gd:
# _resumabilite_json_stricte, qui evite Vector3 pour cette raison ("JSON pur
# -- aucun Vector3"). Ce fichier ECRIT un Vector3 dans "proprietes" (le
# contrat du chantier l'exige), donc ne peut pas l'eviter comme
# test_deformation.gd -- il constate la conversion en String plutot que de
# supposer une egalite qui ne tiendrait jamais.
func _resumabilite_json_stricte(v) -> void:
	var a := _chose("a", Vector3.ZERO)
	Velocite.avancer([a], 1.0)
	a.position = Vector3(2.0, 0.0, 0.0)
	Velocite.avancer([a], 1.0)
	var texte := JSON.stringify(a)
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "JSON.stringify puis parse_string doit reussir sans erreur")
	v.v(typeof(relu.proprietes.velocite) == TYPE_STRING and relu.proprietes.velocite.begins_with("(2"),
		"velocite (Vector3) se serialise en String par JSON.stringify -- constate, jamais une egalite Vector3 qui ne tiendrait pas")
