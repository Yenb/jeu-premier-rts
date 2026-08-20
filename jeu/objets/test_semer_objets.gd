extends SceneTree

# Test manuel :
# godot --headless --script jeu/objets/test_semer_objets.gd
#
# Verrouille res://jeu/objets/semer_objets.gd, le semis en DONNEES :
# - MEME GRAINE, MEME SEMIS. Sans ca, la carte se repeuple autrement a chaque
#   lancement et un defaut de placement n'est jamais reproductible ;
# - DEUX GRAINES DIFFERENTES NE DONNENT PAS LE MEME SEMIS. Le jugement d'au
#   dessus passerait tout seul sur un tirage qui ne tire rien ;
# - LES IDENTIFIANTS SONT UNIQUES : le Monde range par id, et deux objets qui
#   partagent le leur n'en font qu'un ;
# - LA POSITION EST CELLE QUE LA CARTE ANNONCE, jamais recalculee ici. Deux
#   sources donneraient un objet enfonce ou flottant au moment de la bascule ;
# - UNE CARTE ENTIEREMENT CREUSEE NE RECOIT RIEN, ET LE SEMIS REND LA MAIN.
#   C'est le cas ou un semis qui rejouerait son tirage jusqu'a atteindre son
#   compte tournerait sans fin ;
# - UNE DEMANDE VIDE OU NEGATIVE NE SEME RIEN.
#
# Entree : rien -- tout est construit ici. Sortie : une ligne « OK: » et le code
# 0 si tout tient, « ECHEC: » et le code 1 sinon.
#
# Regles tenues : positions en Vector3, jamais Vector2 -- une COLONNE est un
# Vector2i, un index et pas une position. Aucun hasard non seede. Les prints
# sont des traces de mise au point, pas du texte joueur. Rien de scripts/, data/
# ni documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const Semeur = preload("res://jeu/objets/semer_objets.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")

const CLE := "chose"
const EMPRISE := 20
const COMBIEN := 60

var _v

func _init() -> void:
	_v = Verif.new()
	_tout.call_deferred()

func _tout() -> void:
	var carte := _carte()
	var demande := { CLE: COMBIEN }

	var semis := Semeur.semer(carte, demande, 1)
	_v.v(semis.size() == COMBIEN,
		"%d objets semes sur une carte pleine, %d demandes" % [semis.size(), COMBIEN])
	_v.v(Semeur.demandes(demande) == COMBIEN,
		"le compte demande annonce %d, %d attendus" % [Semeur.demandes(demande), COMBIEN])

	# MEME GRAINE, MEME SEMIS.
	var rejoue := Semeur.semer(carte, demande, 1)
	var identiques := true
	for i in range(mini(semis.size(), rejoue.size())):
		if semis[i]["colonne"] != rejoue[i]["colonne"]:
			identiques = false
	_v.v(identiques and semis.size() == rejoue.size(),
		"la meme graine ne rend pas le meme semis : rien n'est reproductible")

	# ET DEUX GRAINES DIFFERENTES NE DONNENT PAS LE MEME.
	var autre := Semeur.semer(carte, demande, 2)
	var ecart := 0
	for i in range(mini(semis.size(), autre.size())):
		if semis[i]["colonne"] != autre[i]["colonne"]:
			ecart += 1
	_v.v(ecart > 0, "deux graines differentes rendent le meme semis : le tirage ne tire rien")

	var vus := {}
	var hors_emprise := 0
	var mal_posees := 0
	for chose in semis:
		vus[chose["id"]] = true
		var colonne: Vector2i = chose["colonne"]
		if not carte.dans_emprise(colonne):
			hors_emprise += 1
		var sol: Variant = carte.hauteur_du_sol(colonne)
		var pose: Vector3 = chose["position"]
		if sol == null or not is_equal_approx(pose.y, float(sol)):
			mal_posees += 1
	_v.v(vus.size() == semis.size(),
		"%d identifiants pour %d objets : le Monde en perdrait" % [vus.size(), semis.size()])
	_v.v(hors_emprise == 0, "%d objets semes hors de l'emprise" % hors_emprise)
	_v.v(mal_posees == 0,
		"%d objets ne sont pas a la hauteur que la carte annonce" % mal_posees)

	# UNE CARTE ENTIEREMENT CREUSEE.
	var creusee := _carte()
	for x in range(-EMPRISE, EMPRISE):
		for z in range(-EMPRISE, EMPRISE):
			creusee.sculpter(Vector2i(x, z), creusee.couche_base - 1)
	var rien := Semeur.semer(creusee, demande, 1)
	_v.v(rien.is_empty(),
		"%d objets semes sur une carte sans le moindre sol" % rien.size())

	_v.v(Semeur.semer(carte, {}, 1).is_empty(), "une demande vide seme quelque chose")
	_v.v(Semeur.semer(carte, { CLE: -5 }, 1).is_empty(), "une demande negative seme quelque chose")

	print("semis : %d objets sur une emprise de %d colonnes, %d perdus dans le vide sur une carte creusee" % [
		semis.size(), carte.colonnes(), COMBIEN])
	_conclure()

func _carte() -> Resource:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = EMPRISE
	return carte

func _conclure() -> void:
	if _v.echecs() > 0:
		print("ECHEC: le semis en donnees ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: semer_objets -- semis seede et reproductible, pose a la hauteur de la carte, rien sur le vide")
	quit(0)
