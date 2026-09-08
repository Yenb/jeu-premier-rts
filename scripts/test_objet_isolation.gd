extends SceneTree

# Test headless de scripts/objet.gd -- chantier "partage COW du paquet par
# defaut" (2026-09-08). Verrouille le contrat de PAQUETS PARTAGES : sous
# `paquets_partages=true`, les sous-Dict/Array de premier niveau des paquets
# herites sont partages par reference entre toutes les instances, mais toute
# ecriture TOP-LEVEL sur `proprietes` d'une instance reste ISOLEE des autres.
#
# Utilise scripts/verif.gd -- assert() natif INTERDIT (voir verif.gd:3-9).
# Lancement : godot --headless --script scripts/test_objet_isolation.gd
#
# Cinq cas :
# 1. Le partage EXISTE : deux mobile_test partages pointent vers le meme sous-
#    Dict `reserves` (canonique). Preuve : muter l'un mute l'autre.
# 2. ISOLATION TOP-LEVEL : ecritures p["profil"] / p["_slot"] / p["errance_..."]
#    (ce que fait scripts/peuplement.gd + jeu/bancs/banc_peuplement.gd) sur une
#    instance n'apparaissent PAS sur l'autre. Remplacer entierement une reference
#    de sous-Dict (p["reserves"] = {...}) reste isole aussi.
# 3. Objet.detacher : permet de muter un sous-Dict sans fuite vers l'autre.
# 4. Objet.detacher IDEMPOTENT : appels multiples conservent la mutation ;
#    detacher sur une cle absente reste silencieux.
# 5. Mode NON-PARTAGE (defaut false) : deep-copy historique -- deux fabrications
#    ont chacune leur sous-Dict propre, mutation isolee comme avant ce chantier.

const Verif = preload("res://scripts/verif.gd")
const Objet = preload("res://scripts/objet.gd")

var _v := Verif.new()

func _init() -> void:
	_executer()
	if _v.echecs() == 0:
		print("OK: scripts/objet.gd -- 5 cas passes (partage, isolation top-level, detacher, idempotence, non-partage)")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s) -- voir push_error ci-dessus" % _v.echecs())
		quit(1)

func _executer() -> void:
	var table: Dictionary = _charger_types()
	_v.v(table.has("mobile_test"), "prealable : data/types.json sans entree 'mobile_test'")
	_v.v(table.has("dynamique"), "prealable : data/types.json sans paquet 'dynamique'")

	# ---- CAS 1 : partage effectif ----
	Objet.vider_cache_paquets_partages()
	var a: Dictionary = Objet.fabriquer("a", "mobile_test", Vector3.ZERO, table, {}, [], {}, [], true)
	var b: Dictionary = Objet.fabriquer("b", "mobile_test", Vector3.ZERO, table, {}, [], {}, [], true)
	_v.v(not a.is_empty() and not b.is_empty(), "cas 1 : Objet.fabriquer a rendu {}")
	var pa: Dictionary = a.proprietes
	var pb: Dictionary = b.proprietes
	_v.v(pa.has("reserves") and pb.has("reserves"), "cas 1 : reserves absente d'une instance (herite de dynamique)")
	var faim_canonique: float = float(pa.reserves.faim.reserve)
	pa.reserves.faim.reserve = faim_canonique - 42.0
	_v.v(is_equal_approx(pb.reserves.faim.reserve, faim_canonique - 42.0),
		"cas 1 : mutation d'un sous-Dict sur A pas vue par B -- le partage n'existe pas")

	# ---- CAS 2 : isolation des ecritures TOP-LEVEL ----
	# Ce que fait le peuplement (banc_peuplement._fabriquer_lot) : p["profil"],
	# p["_slot"], p["errance_direction"], p["reserves"] = {...}. Aucun de ces
	# gestes ne mute un sous-Dict partage : ils creent/remplacent des cles au
	# top-level du Dict propre a chaque instance.
	Objet.vider_cache_paquets_partages()
	var c: Dictionary = Objet.fabriquer("c", "mobile_test", Vector3.ZERO, table, {}, [], {}, [], true)
	var d: Dictionary = Objet.fabriquer("d", "mobile_test", Vector3.ZERO, table, {}, [], {}, [], true)
	var pc: Dictionary = c.proprietes
	var pd: Dictionary = d.proprietes
	pc["profil"] = "simple_c"
	pc["_slot"] = 42
	pc["errance_direction"] = Vector3(1.0, 0.0, 0.0)
	_v.v(not pd.has("profil"), "cas 2 : ecriture top-level pc['profil'] a fuite vers pd")
	_v.v(not pd.has("_slot"), "cas 2 : ecriture top-level pc['_slot'] a fuite vers pd")
	_v.v(not pd.has("errance_direction"), "cas 2 : ecriture top-level pc['errance_direction'] a fuite vers pd")
	# Remplacement complet de la reference d'un sous-Dict : pd.reserves doit
	# rester le partage canonique et garder ses canaux par defaut.
	pc["reserves"] = {"nouveau_canal": {"reserve": 5.0}}
	_v.v(pd.reserves.has("faim") and not pd.reserves.has("nouveau_canal"),
		"cas 2 : remplacement de pc['reserves'] a fuite vers pd (mutation au lieu d'un remplacement de reference)")

	# ---- CAS 3 : detacher permet de muter un sous-Dict sans fuite ----
	Objet.vider_cache_paquets_partages()
	var e: Dictionary = Objet.fabriquer("e", "mobile_test", Vector3.ZERO, table, {}, [], {}, [], true)
	var f: Dictionary = Objet.fabriquer("f", "mobile_test", Vector3.ZERO, table, {}, [], {}, [], true)
	var pe: Dictionary = e.proprietes
	var pf: Dictionary = f.proprietes
	var faim_avant_detache: float = float(pf.reserves.faim.reserve)
	Objet.detacher(pe, "reserves")
	pe.reserves.faim.reserve = 12.34
	_v.v(is_equal_approx(pf.reserves.faim.reserve, faim_avant_detache),
		"cas 3 : mutation apres detacher a fuite vers pf -- detacher n'a pas isole la reference")
	_v.v(is_equal_approx(pe.reserves.faim.reserve, 12.34),
		"cas 3 : la valeur mutee apres detacher n'est pas conservee sur pe")

	# ---- CAS 4 : detacher idempotent + silencieux sur cle absente ----
	Objet.detacher(pe, "reserves")
	_v.v(is_equal_approx(pe.reserves.faim.reserve, 12.34),
		"cas 4 : detacher idempotent -- second appel a perdu la mutation")
	Objet.detacher(pe, "cle_qui_n_existe_pas")
	_v.v(not pe.has("cle_qui_n_existe_pas"), "cas 4 : detacher a cree une cle absente au lieu d'etre silencieux")

	# ---- CAS 5 : mode non-partage (defaut) reste isolant historique ----
	Objet.vider_cache_paquets_partages()
	var g: Dictionary = Objet.fabriquer("g", "mobile_test", Vector3.ZERO, table, {}, [], {}, [], false)
	var h: Dictionary = Objet.fabriquer("h", "mobile_test", Vector3.ZERO, table, {}, [], {}, [], false)
	var pg: Dictionary = g.proprietes
	var ph: Dictionary = h.proprietes
	var faim_defaut: float = float(ph.reserves.faim.reserve)
	pg.reserves.faim.reserve = 3.14
	_v.v(is_equal_approx(ph.reserves.faim.reserve, faim_defaut),
		"cas 5 : sous mode non-partage, mutation d'un sous-Dict sur g a fuite vers h -- regression de l'isolation historique")

func _charger_types() -> Dictionary:
	if not FileAccess.file_exists("res://data/types.json"):
		push_error("test_objet_isolation : data/types.json introuvable")
		return {}
	var texte := FileAccess.get_file_as_string("res://data/types.json")
	var donnees = JSON.parse_string(texte)
	if donnees is Dictionary:
		return donnees
	push_error("test_objet_isolation : data/types.json invalide")
	return {}
