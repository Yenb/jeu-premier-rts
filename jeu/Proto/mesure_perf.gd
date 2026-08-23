# MESURE PERF -- log FPS, draw_calls, objects, primitives, TIME_PROCESS
# pendant DUREE_MESURE puis quitte.
#
# Applique METHODE_DIAGNOSTIC_PERF.md etape 4 (mesure programmatique)
# quand l'editeur n'est pas accessible. Chiffres exiges par
# PROTOCOLE_MULTIMESH.md avant toute optimisation.
#
# MODE MOBILE : env var OBSERVATEUR_MOBILE=1 fait deplacer l'observateur
# lineairement pendant la mesure. Utile pour tester si les reconstructions
# de tuiles creent des stutters recurrents.
#
# Consequence si echec : rien -- lecture seule.
# Rollback : supprimer ce fichier et le noeud dans la scene.
extends Node

const DUREE_MESURE: float = 10.0
const INTERVALLE_LOG: float = 1.0

const CHEMIN_LOG_BASE := "user://mesure_perf"
const VITESSE_OBS_MOBILE := 5.0  # m/s (unites Godot), franchit plusieurs tuiles sur 10s

var _t: float = 0.0
var _t_log: float = 0.0
var _echantillons: Array = []
var _fichier: FileAccess = null
var _observateur_mobile := false
var _observateur: Node3D = null
var _pos_depart: Vector3 = Vector3.ZERO

func _ready() -> void:
	var suffixe := OS.get_environment("TAILLE_TUILE")
	if suffixe == "":
		suffixe = "default"
	var mode_mob := OS.get_environment("OBSERVATEUR_MOBILE")
	_observateur_mobile = mode_mob == "1"
	if _observateur_mobile:
		suffixe += "_mobile"
	var chemin := CHEMIN_LOG_BASE + "_" + suffixe + ".log"
	_fichier = FileAccess.open(chemin, FileAccess.WRITE)
	if _fichier == null:
		push_error("[MESURE] impossible d'ouvrir " + chemin)
		return
	_log("[MESURE] demarrage, %.1fs, mobile=%s" % [DUREE_MESURE, str(_observateur_mobile)])
	if _observateur_mobile:
		_observateur = get_tree().get_first_node_in_group(&"observateur")
		if _observateur != null:
			_pos_depart = _observateur.global_position
			_log("[MESURE] observateur pos_depart = %s" % str(_pos_depart))

func _compter_mmi_dans_arbre(n: Node) -> int:
	# Parcours recursif : compte MultiMeshInstance3D ET MeshInstance3D.
	# terrain_visible_multimesh.gd a bascule de MMI vers MI en cours de
	# chantier ; sans les deux, la sonde renvoyait 0. Cout : O(N noeuds),
	# acceptable a 1 Hz (INTERVALLE_LOG).
	var c := 0
	if n is MultiMeshInstance3D or n is MeshInstance3D:
		c += 1
	for enfant in n.get_children():
		c += _compter_mmi_dans_arbre(enfant)
	return c

func _log(ligne: String) -> void:
	print(ligne)
	if _fichier != null:
		_fichier.store_line(ligne)
		_fichier.flush()

func _process(delta: float) -> void:
	_t += delta
	# Deplace l'observateur en ligne droite si mode mobile actif.
	# Impact : force reconstructions de tuiles au franchissement.
	if _observateur_mobile and _observateur != null:
		_observateur.global_position = _pos_depart + Vector3(_t * VITESSE_OBS_MOBILE, 0, 0)
	_t_log += delta
	if _t_log >= INTERVALLE_LOG:
		_t_log = 0.0
		var fps: float = Performance.get_monitor(Performance.TIME_FPS)
		var t_proc: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var t_phys: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var draws: int = RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var objs: int = RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		var prims: int = RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var mmi_total := _compter_mmi_dans_arbre(get_tree().root)
		var ratio := 0.0
		if mmi_total > 0:
			ratio = float(objs) / float(mmi_total)
		_log("[MESURE] t=%.1f fps=%.1f proc=%.2fms phys=%.2fms draws=%d objs=%d prims=%d mmi_total=%d ratio=%.2f" % [
			_t, fps, t_proc, t_phys, draws, objs, prims, mmi_total, ratio])
		_echantillons.append({
			"fps": fps, "proc": t_proc, "draws": draws, "objs": objs, "prims": prims})
	if _t >= DUREE_MESURE:
		_afficher_bilan()
		get_tree().quit()

func _afficher_bilan() -> void:
	if _echantillons.is_empty():
		_log("[MESURE] aucun echantillon")
		return
	var fps_sum := 0.0
	var proc_sum := 0.0
	var draws_sum := 0
	var objs_sum := 0
	var prims_sum: float = 0.0  # float pour eviter overflow int sur ~10x20M
	var proc_max := 0.0
	for e in _echantillons:
		fps_sum += e["fps"]
		proc_sum += e["proc"]
		draws_sum += e["draws"]
		objs_sum += e["objs"]
		prims_sum += float(e["prims"])
		if e["proc"] > proc_max:
			proc_max = e["proc"]
	var n := _echantillons.size()
	_log("[MESURE] BILAN moyennes sur %d echantillons :" % n)
	_log("[MESURE]   fps moyen  = %.1f" % (fps_sum / n))
	_log("[MESURE]   proc moyen = %.2f ms   proc max = %.2f ms" % [proc_sum / n, proc_max])
	_log("[MESURE]   draws moyen = %.1f" % (float(draws_sum) / float(n)))
	_log("[MESURE]   objs moyen  = %.1f" % (float(objs_sum) / float(n)))
	_log("[MESURE]   prims moyen = %.0f" % (prims_sum / float(n)))
	if _fichier != null:
		_fichier.close()
