extends SceneTree

# Test manuel :
# godot --headless --script jeu/monde/test_archiviste.gd
#
# Verrouille res://jeu/monde/registre.gd et res://jeu/monde/archiviste.gd, la
# couche qui garde le monde :
# - UN REGISTRE NEUF N'EST PAS SALE, et une donnee RELUE DU DISQUE non plus. Le
#   drapeau decrit une session, pas le monde : l'exporter ferait se reecrire
#   toute carte a chaque ouverture, sans que rien n'ait bouge ;
# - L'ARCHIVISTE N'ECRIT QUE CE QUI EST MARQUE. Ecrire ce qui n'a pas change
#   coute une serialisation complete pour rien, et sur un monde de cent
#   kilometres carres ca se compte en megaoctets ;
# - UN REGISTRE QUI ECHOUE RESTE MARQUE. Se declarer propre apres un echec est
#   la seule facon de perdre du travail sans qu'aucune trace ne le dise ;
# - UNE DONNEE SANS CHEMIN ALARME au lieu d'etre perdue en silence ;
# - LA CARTE SE MARQUE QUAND ON LA SCULPTE, et PAS quand on lui repose ce
#   qu'elle porte deja -- sinon le disque serait reecrit a chaque passage d'un
#   outil qui ne change rien ;
# - AJOUTER UNE SORTE DE DONNEE AU MONDE NE DEMANDE AUCUNE LIGNE D'ECRITURE :
#   le test le prouve en fabriquant un registre qui n'est pas le terrain.
#
# Entree : des registres construits ici, ecrits sous user:// (jamais dans le
# depot). Sortie : une ligne « OK: » et le code 0 si tout tient, « ECHEC: » et
# le code 1 sinon.
#
# Regles tenues : aucun hasard. Les prints sont des traces de mise au point, pas
# du texte joueur. Rien de scripts/, data/ ni documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const Registre = preload("res://jeu/monde/registre.gd")
const Archiviste = preload("res://jeu/monde/archiviste.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")

const CHEMIN := "user://test_registre.tres"
const CHEMIN_CARTE := "user://test_registre_carte.tres"

var _v

# UNE SECTION QUI S'INTERROMPT NE COMPTE AUCUN ECHEC : l'appel plante, les
# jugements suivants ne s'executent pas, et le test conclut OK sur zero echec.
# Chaque section signe donc son passage.
const SECTIONS := 4
var _faites := 0

# La liste TYPEE que l'archiviste accepte. Un Array nu est refuse a l'execution
# sans arreter le test -- l'archiviste garde alors sa liste vide, et tout
# jugement qui attend « rien d'ecrit » passe pour de mauvaises raisons.
static func _liste(choses: Array) -> Array[Resource]:
	var typee: Array[Resource] = []
	for chose in choses:
		typee.append(chose)
	return typee

func _init() -> void:
	_v = Verif.new()
	_tout.call_deferred()

func _tout() -> void:
	var temoin: Resource = Registre.new()
	# UN SCRIPT QUI NE COMPILE PAS ROUGIT, IL NE SE SAUTE PAS.
	if temoin == null:
		_v.v(false, "registre.gd ne s'instancie pas : le script ne compile pas")
		_conclure()
		return
	_drapeau()
	_ecriture()
	_echecs()
	_carte_est_un_registre()
	_conclure()

func _drapeau() -> void:
	var registre: Resource = Registre.new()
	_v.v(not registre.est_sale(), "un registre neuf se croit modifie")
	registre.marquer_sale()
	_v.v(registre.est_sale(), "marquer un registre ne le rend pas sale")
	registre.marquer_propre()
	_v.v(not registre.est_sale(), "un registre ecrit reste marque")

	# SANS CHEMIN, RIEN A ECRIRE.
	_v.v(not registre.peut_etre_ecrit(),
		"un registre sans chemin se croit ecrivable")
	ResourceSaver.save(registre, CHEMIN)
	var relu: Resource = ResourceLoader.load(CHEMIN, "", ResourceLoader.CACHE_MODE_IGNORE)
	_v.v(relu != null and relu.peut_etre_ecrit(), "un registre relu n'a pas de chemin")

	# LE DRAPEAU N'EST PAS UNE DONNEE DU MONDE : une carte relue d'un disque ne
	# se croit pas modifiee, sinon elle se reecrirait a chaque ouverture.
	_v.v(relu != null and not relu.est_sale(),
		"un registre relu du disque se croit modifie : il serait reecrit pour rien")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHEMIN))
	_faites += 1

func _ecriture() -> void:
	var archiviste: Node = Archiviste.new()
	archiviste.journal = false
	get_root().add_child(archiviste)

	# UN REGISTRE QUI N'EST PAS LE TERRAIN : ajouter une sorte de donnee au
	# monde ne demande aucune ligne d'ecriture.
	var quelconque: Resource = Registre.new()
	ResourceSaver.save(quelconque, CHEMIN)
	quelconque = load(CHEMIN)
	archiviste.registres = _liste([quelconque])

	# RIEN DE MARQUE, RIEN D'ECRIT.
	_v.v(archiviste.en_attente() == 0, "un registre neuf est compte en attente")
	_v.v(archiviste.ecrire_les_sales() == 0,
		"l'archiviste ecrit un registre que personne n'a modifie")

	quelconque.marquer_sale()
	_v.v(archiviste.en_attente() == 1, "un registre marque n'est pas compte en attente")
	_v.v(archiviste.ecrire_les_sales() == 1, "l'archiviste n'ecrit pas ce qui est marque")
	_v.v(not quelconque.est_sale(), "un registre ecrit reste marque : il serait reecrit sans fin")
	_v.v(archiviste.ecrire_les_sales() == 0, "l'archiviste reecrit ce qu'il vient d'ecrire")

	archiviste.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHEMIN))
	_faites += 1

func _echecs() -> void:
	var archiviste: Node = Archiviste.new()
	archiviste.journal = false
	get_root().add_child(archiviste)

	# SANS CHEMIN : on alarme, on n'ecrit pas, et le registre RESTE marque.
	var sans_chemin: Resource = Registre.new()
	sans_chemin.marquer_sale()
	archiviste.registres = _liste([sans_chemin])
	_v.v(archiviste.ecrire_les_sales() == 0, "l'archiviste a cru ecrire un registre sans chemin")
	_v.v(sans_chemin.est_sale(),
		"un registre qu'on n'a pas pu ecrire se croit propre : son travail serait perdu")

	# UN REGISTRE NUL DANS LA LISTE ne fait pas tomber le reste.
	var bon: Resource = Registre.new()
	ResourceSaver.save(bon, CHEMIN)
	bon = load(CHEMIN)
	bon.marquer_sale()
	archiviste.registres = _liste([null, sans_chemin, bon])
	_v.v(archiviste.ecrire_les_sales() == 1,
		"un registre nul ou sans chemin empeche d'ecrire les autres")
	_v.v(not bon.est_sale(), "le registre valide n'a pas ete ecrit")

	archiviste.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHEMIN))
	_faites += 1

func _carte_est_un_registre() -> void:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 100
	_v.v(carte.has_method("est_sale"),
		"la carte n'est pas un registre : rien ne l'enregistrera")
	_v.v(not carte.est_sale(), "une carte neuve se croit modifiee")

	# SCULPTER MARQUE.
	var colonne := Vector2i(3, 3)
	carte.sculpter(colonne, carte.sommet_de_base() + 2)
	_v.v(carte.est_sale(), "sculpter ne marque pas la carte : le relief ne serait jamais ecrit")

	# REPOSER CE QU'ELLE PORTE DEJA NE MARQUE PAS : sinon le disque serait
	# reecrit a chaque passage d'un outil qui ne change rien.
	carte.marquer_propre()
	carte.poser_masque(colonne, carte.masque(colonne))
	_v.v(not carte.est_sale(),
		"reposer un masque identique marque la carte : elle serait reecrite pour rien")

	# ET UN VRAI CHANGEMENT MARQUE DE NOUVEAU.
	carte.poser_masque(colonne, carte.masque_de_base())
	_v.v(carte.est_sale(), "revenir au defaut ne marque pas la carte")

	# L'ARCHIVISTE L'ECRIT COMME N'IMPORTE QUEL REGISTRE, sans rien connaitre
	# du terrain.
	ResourceSaver.save(carte, CHEMIN_CARTE)
	var sur_disque: Resource = load(CHEMIN_CARTE)
	sur_disque.sculpter(Vector2i(1, 1), sur_disque.sommet_de_base() + 1)
	var archiviste: Node = Archiviste.new()
	archiviste.journal = false
	archiviste.registres = _liste([sur_disque])
	get_root().add_child(archiviste)
	_v.v(archiviste.ecrire_les_sales() == 1, "l'archiviste n'a pas ecrit la carte")

	var relue: Resource = ResourceLoader.load(
		CHEMIN_CARTE, "", ResourceLoader.CACHE_MODE_IGNORE)
	_v.v(relue != null and relue.sommet_max_colonne(Vector2i(1, 1)) == relue.sommet_de_base() + 1,
		"le relief n'est pas sur le disque apres l'ecriture de l'archiviste")

	archiviste.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHEMIN_CARTE))
	_faites += 1

func _conclure() -> void:
	_v.v(_faites == SECTIONS,
		"%d sections sur %d sont allees jusqu'au bout : une s'est interrompue" % [
			_faites, SECTIONS])
	if _v.echecs() > 0:
		print("ECHEC: la couche de persistance ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: archiviste -- seul ce qui est marque est ecrit, un echec laisse le registre marque, "
		+ "une donnee relue ne se croit pas modifiee, la carte se marque en sculptant et pas en se "
		+ "reposant, et une sorte de donnee neuve s'enregistre sans une ligne d'ecriture")
	quit(0)
