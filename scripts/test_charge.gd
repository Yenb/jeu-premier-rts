extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_charge.gd
#
# Verrouille scripts/charge.gd comme MODELE GENERIQUE DE CHARGE A
# SEUIL, pas comme un code de peur ou de colere. Une charge nommee MONTE tant
# qu'une cause est percue a portee (somme des contributions, meme geste de
# detection qu'extinction.gd sur ses agents), FRANCHIT un seuil vers le HAUT
# qui pose une cause en donnee, puis REDESCEND d'elle-meme en son absence et
# RETIRE la meme cause en repassant sous le seuil -- reversible, pas un
# evenement unique. Le script ne lit aucun nom d'action, de contenu ni de
# canal.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu.

const Charge = preload("res://scripts/charge.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_sans_etats_rien_ne_bouge(v)
	_presence_fait_monter_la_charge_sans_franchir(v)
	_presence_franchit_le_seuil_et_pose_la_cause(v)
	_rester_au_dessus_ne_rebascule_pas(v)
	_absence_fait_redescendre_et_retire_la_cause(v)
	_plancher_a_zero_jamais_negatif(v)
	_hors_portee_ne_contribue_pas(v)
	_le_modele_ignore_le_domaine(v)
	_valeur_posee_est_une_copie_jamais_une_reference(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: une charge nommee monte sous cause a portee, franchit un seuil vers le haut " +
			"qui pose une cause en donnee, redescend et la retire en l'absence de toute cause, " +
			"plancher a 0.0 jamais negatif")
		quit(0)

func _canal(charge: float, seuil: float, portee: float, taux_decroissance: float, poser: Dictionary) -> Dictionary:
	return {
		"charge": charge,
		"seuil": seuil,
		"portee_charge": portee,
		"taux_decroissance": taux_decroissance,
		"poser": poser,
	}

func _chose(id: String, canaux: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var proprietes := {"etats": canaux}
	for cle in extra:
		proprietes[cle] = extra[cle]
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _cause(poids: float, position: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"position": position, "poids": poids}

func _sans_etats_rien_ne_bouge(v) -> void:
	var monde := [{"id": "x", "position": Vector3.ZERO, "proprietes": {}}]
	var b := Charge.avancer(monde, [_cause(5.0)], 1.0)
	v.v(b.is_empty(), "sans etats, rien ne doit etre rendu comme bascule")
	v.v(not monde[0].proprietes.has("etats"), "sans etats, aucune cle ne doit apparaitre")

func _presence_fait_monter_la_charge_sans_franchir(v) -> void:
	var monde := [_chose("a", {"jauge": _canal(0.0, 10.0, 50.0, 1.0, {"alerte": true})})]
	var b := Charge.avancer(monde, [_cause(2.0)], 1.0)
	v.v(monde[0].proprietes.etats.jauge.charge == 2.0,
		"une cause a portee doit faire monter la charge de poids * delta")
	v.v(b.is_empty(), "monter sans franchir le seuil ne doit rendre aucune bascule")
	v.v(not monde[0].proprietes.has("alerte"), "sous le seuil, la cause ne doit jamais etre posee")

func _presence_franchit_le_seuil_et_pose_la_cause(v) -> void:
	var monde := [_chose("a", {"jauge": _canal(8.0, 10.0, 50.0, 1.0, {"alerte": true})})]
	var b := Charge.avancer(monde, [_cause(5.0)], 1.0)
	var p: Dictionary = monde[0].proprietes
	v.v(b.has("a"), "franchir le seuil vers le haut doit rendre l'id de la chose")
	v.v(p.etats.jauge.charge == 13.0, "la charge doit avoir monte de poids * delta avant bascule")
	v.v(p.get("alerte", false), "franchir le seuil vers le haut doit poser la cause sur proprietes")

# HORS DOMAINE. Ce que pose un canal est une COPIE, jamais la reference du
# catalogue : deux choses qui portent le MEME `poser` (cas nominal d'un canal
# declare une fois en donnee) ne partagent aucune sous-structure une fois le
# seuil franchi, et le catalogue reste intact.
func _valeur_posee_est_une_copie_jamais_une_reference(v) -> void:
	var poser := {"bac": {"niveau": 1.0}, "paliers": ["a"]}
	var monde := [
		_chose("a", {"jauge": _canal(8.0, 10.0, 50.0, 1.0, poser)}),
		_chose("b", {"jauge": _canal(8.0, 10.0, 50.0, 1.0, poser)}),
	]
	Charge.avancer(monde, [_cause(5.0)], 1.0)
	var pa: Dictionary = monde[0].proprietes
	var pb: Dictionary = monde[1].proprietes
	v.v(pa.has("bac") and pb.has("bac"), "les deux choses doivent avoir franchi le seuil")
	pa.bac.niveau = 99.0
	pa.paliers.append("z")
	v.v(pb.bac.niveau == 1.0,
		"deux choses ne doivent jamais partager le Dictionary pose par un canal")
	v.v(pb.paliers.size() == 1,
		"deux choses ne doivent jamais partager l'Array pose par un canal")
	v.v(poser.bac.niveau == 1.0 and poser.paliers.size() == 1,
		"le catalogue ne doit jamais etre mute par une pose")

func _rester_au_dessus_ne_rebascule_pas(v) -> void:
	var monde := [_chose("a", {"jauge": _canal(13.0, 10.0, 50.0, 1.0, {"alerte": true})}, {"alerte": true})]
	var b := Charge.avancer(monde, [_cause(5.0)], 1.0)
	var p: Dictionary = monde[0].proprietes
	v.v(not b.has("a"), "rester au-dessus du seuil ne doit plus rebasculer")
	v.v(p.get("alerte", false), "la cause deja posee doit rester posee tant que la charge reste au-dessus")
	v.v(p.etats.jauge.charge == 18.0, "la charge continue de monter meme sans nouvelle bascule")

func _absence_fait_redescendre_et_retire_la_cause(v) -> void:
	var monde := [_chose("a", {"jauge": _canal(18.0, 10.0, 50.0, 4.0, {"alerte": true})}, {"alerte": true})]
	var b := Charge.avancer(monde, [], 3.0)
	var p: Dictionary = monde[0].proprietes
	v.v(b.has("a"), "franchir le seuil vers le bas doit rendre l'id de la chose")
	v.v(p.etats.jauge.charge == 6.0, "sans cause, la charge doit decroitre de taux_decroissance * delta")
	v.v(not p.has("alerte"), "repasser sous le seuil doit retirer la meme cause qui avait ete posee")

func _plancher_a_zero_jamais_negatif(v) -> void:
	var monde := [_chose("a", {"jauge": _canal(2.0, 10.0, 50.0, 5.0, {})})]
	var b := Charge.avancer(monde, [], 10.0)
	v.v(monde[0].proprietes.etats.jauge.charge == 0.0,
		"la charge ne doit jamais descendre sous 0.0, meme quand la decroissance la depasserait")
	v.v(b.is_empty(), "rester sous un seuil jamais atteint ne doit rendre aucune bascule")

func _hors_portee_ne_contribue_pas(v) -> void:
	var monde := [_chose("a", {"jauge": _canal(5.0, 100.0, 10.0, 0.0, {})})]
	var loin := _cause(3.0, Vector3(50.0, 0.0, 0.0))
	var b := Charge.avancer(monde, [loin], 1.0)
	v.v(monde[0].proprietes.etats.jauge.charge == 5.0,
		"une cause hors de portee_charge ne doit jamais contribuer a la charge")
	v.v(b.is_empty(), "aucune contribution hors portee ne doit produire de bascule")

# LA serrure generaliste : deux canaux sans rapport avec la peur ou la colere,
# sur le meme objet, traversent le meme code -- l'un franchit son seuil, pas
# l'autre, sans qu'aucun nom de canal ne soit lu par charge.gd.
func _le_modele_ignore_le_domaine(v) -> void:
	var canaux := {
		"vibration": _canal(0.0, 5.0, 100.0, 0.0, {"resonance": true}),
		"corrosion": _canal(0.0, 50.0, 100.0, 0.0, {"rouille_visible": true}),
	}
	var monde := [_chose("poteau_1", canaux)]
	var b := Charge.avancer(monde, [_cause(6.0)], 1.0)
	var p: Dictionary = monde[0].proprietes
	v.v(b.has("poteau_1"), "un objet hors de tout domaine connu doit franchir un seuil par le meme code")
	v.v(p.get("resonance", false), "le canal dont le seuil est franchi doit poser sa cause")
	v.v(not p.has("rouille_visible"), "le canal dont le seuil n'est pas franchi ne doit rien poser")
	v.v(p.etats.corrosion.charge == 6.0,
		"corrosion accumule independamment de vibration, sur le meme objet, sans jamais franchir son seuil ici")
