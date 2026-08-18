extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_flux.gd
#
# Verrouille scripts/flux.gd comme MODELE GENERIQUE DE FLUX, pas comme un
# code de lumiere ou d'energie. Une chose portant une propriete SOURCE
# recharge, a son propre taux_flux et dans sa propre portee_flux (posees a
# la fabrication), la reserve <cible> de toute chose a portee portant la
# propriete RECEPTRICE -- meme forme de canal que depense.gd
# (proprietes.reserves.<nom>.reserve).
#
# _le_modele_ignore_le_domaine() verrouille en plus qu'aucun nom de domaine
# (source/receptrice/reserve) n'est cable en dur dans flux.gd : un domaine
# invente, sans aucun rapport avec lumiere/energie/feu ("sonore" -> "auditeur"
# recharge "audition", absents de tout le moteur, verifie par grep), traverse
# le meme code sans une ligne ajoutee. Un taux_flux negatif y decroit la
# reserve au lieu de la recharger, preuve que le script n'est pas "le gain"
# mais un flux neutre.

const Flux = preload("res://scripts/flux.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_le_modele_ignore_le_domaine(v)
	if v.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % v.echecs())
		quit(1)
		return
	print("OK: source recharge la reserve d'une receptrice a portee, a son taux ; " +
		"hors portee ou sans la propriete receptrice, rien n'est gagne ; " +
		"un taux negatif decroit la reserve, meme code")
	quit()

func _source(id: String, pos: Vector3, portee: float, taux: float) -> Dictionary:
	return {
		"id": id,
		"position": pos,
		"proprietes": {"sonore": true, "portee_flux": portee, "taux_flux": taux},
	}

func _table() -> Array:
	return [{"source": "sonore", "receptrice": "auditeur", "cible": "audition"}]

func _le_modele_ignore_le_domaine(v) -> void:
	# Positif : une receptrice a portee gagne la reserve visee, au taux de la source.
	var haut_parleur := _source("haut_parleur", Vector3(0, 0, 0), 50.0, 3.0)
	var auditeur_proche := {
		"id": "auditeur_proche", "position": Vector3(30, 0, 0),
		"proprietes": {"auditeur": true},
	}
	var auditeur_loin := {
		"id": "auditeur_loin", "position": Vector3(500, 0, 0),
		"proprietes": {"auditeur": true},
	}
	var muet := {
		"id": "muet", "position": Vector3(20, 0, 0),
		"proprietes": {},
	}
	var monde := [haut_parleur, auditeur_proche, auditeur_loin, muet]
	var modifiees := Flux.avancer(monde, _table(), 1.0)

	v.v(modifiees.has("auditeur_proche"),
		"une receptrice a portee doit ressortir modifiee")
	v.v(not modifiees.has("auditeur_loin"),
		"une receptrice hors portee ne doit pas ressortir modifiee")
	v.v(not modifiees.has("muet"),
		"une chose sans la propriete receptrice ne doit pas ressortir modifiee")

	v.v(is_equal_approx(auditeur_proche.proprietes.reserves.audition.reserve, 3.0),
		"la reserve visee doit gagner taux_flux * delta")
	v.v(not auditeur_loin.proprietes.has("reserves"),
		"une chose hors portee ne doit gagner aucune reserve")
	v.v(not muet.proprietes.has("reserves"),
		"une chose sans la propriete receptrice ne doit gagner aucune reserve")

	# Negatif : un taux_flux negatif decroit la reserve, meme code -- ce n'est
	# pas "le gain", c'est un flux neutre.
	var absorbeur := _source("absorbeur", Vector3(0, 0, 0), 50.0, -2.0)
	var auditeur_charge := {
		"id": "auditeur_charge", "position": Vector3(10, 0, 0),
		"proprietes": {"auditeur": true, "reserves": {"audition": {"reserve": 10.0}}},
	}
	var monde_negatif := [absorbeur, auditeur_charge]
	var modifiees_neg := Flux.avancer(monde_negatif, _table(), 1.0)

	v.v(modifiees_neg.has("auditeur_charge"),
		"un taux negatif doit aussi faire ressortir la chose comme modifiee")
	v.v(is_equal_approx(auditeur_charge.proprietes.reserves.audition.reserve, 8.0),
		"un taux_flux negatif doit decroitre la reserve, par le meme code")
