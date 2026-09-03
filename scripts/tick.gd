extends RefCounted

# FRAMEWORK DE TICK MODULABLE : DECIDE QUAND avancer une entite et AVEC QUEL
# profil, puis delegue le pas a scripts/mouvement_kinematic.gd. Le module
# Mouvement sait avancer UNE entite selon un profil ; il ne sait pas a quelle
# cadence l'appeler ni quel profil donner a telle entite. Cette decision depend
# du TYPE DE JEU construit sur le framework, pas du framework -- donc ce module
# offre PLUSIEURS politiques et laisse l'appelant choisir la sienne.
#
# Patron repris de scripts/boucle.gd : une politique est un Callable DEJA LIE par
# l'appelant, que tick_entite APPELLE et ne recalcule jamais (voir CLAUDE.md,
# Regle d'etat -- "la boucle ne fait que declencher, jamais calculer").
#
# PAS DE class_name (doctrine) : preload("res://scripts/tick.gd").
#
# ====================================================================
# QUELLE POLITIQUE POUR QUEL JEU (a lire AVANT de brancher un manager)
# ====================================================================
#
# MONDE EMERGENT (ecosysteme, saisons, faim, cycle jour/nuit qui affecte tout)
#   -> politique_intrinseque
#   -> Pourquoi : le temps du monde doit etre UNIFORME. Un hiver qui commence a T
#      commence a T partout ; une ville qui simulerait moins vite creerait des
#      decalages temporels visibles quand le joueur y arrive.
#   -> Exemple : Dwarf Fortress, RimWorld, un roguelike survival avec ecosysteme.
#   -> NE PAS utiliser politique_distance ici : le monde deviendrait incoherent
#      (les zones lointaines vivraient en temps ralenti).
#
# ACTION CENTREE (siege, tower defense, arene, boss fight avec vagues)
#   -> politique_distance
#   -> Pourquoi : le gameplay se joue autour d'un POINT CHAUD (chateau, base,
#      arene). Les entites loin arrivent avec le temps ; un leger decalage de leur
#      simulation est invisible et acceptable, l'important est ce qui se passe sous
#      les yeux du joueur.
#   -> Exemple : They Are Billions, Kingdom Rush, tower defense classique.
#   -> NE PAS utiliser pour un monde emergent : les zones lointaines vivraient en
#      temps ralenti.
#
# UTILITAIRE (tests, debug, cinematiques scriptees)
#   -> politique_groupe
#   -> Pour mettre en pause tous les mobs d'une zone pendant une cinematique, ou
#      pour tester un profil precis sur un groupe donne.
#
# REGLE DE COHERENCE : UNE politique par jeu, pas de melange. Soit le temps est
# uniforme partout (intrinseque), soit il varie par observateur (distance).
# Choisir une doctrine et s'y tenir dans TOUT le projet.
#
# ---- CE QU'IL FAIT ----
# Trois fonctions de DECISION pures (politique_intrinseque / politique_distance /
# politique_groupe), chacune rend {"profil", "cadence"} sans rien modifier. Une
# fonction de TICK generique (tick_entite) qui prend une politique en Callable,
# lui demande la decision, tient un compteur de frames par entite, et appelle
# Mouvement.pas au bon rythme avec un delta rattrape (delta_effectif).
#
# ---- CE QU'IL NE FAIT PAS ----
# Il ne choisit PAS la politique a votre place (l'appelant la passe en Callable).
# Il n'ecrit NI la position, NI la velocite, NI le rendu : ca, c'est Mouvement.
# Il ne connait AUCUNE chose du monde (agnostique du type).
#
# ---- COMMENT L'APPELANT PASSE LA POLITIQUE (Callable + bind) ----
# politique_distance et politique_groupe prennent un argument de plus
# (observateur_position, table_groupes) : l'appelant le LIE via .bind(...) pour
# que tick_entite puisse toujours appeler politique.call(entite) a un seul arg.
#   Tick.tick_entite(e, Callable(Tick, "politique_intrinseque"), delta, monde, carte)
#   Tick.tick_entite(e, Callable(Tick, "politique_distance").bind(pos_joueur), delta, monde, carte)
#   Tick.tick_entite(e, Callable(Tick, "politique_groupe").bind(ma_table), delta, monde, carte)
#
# ---- LE RATTRAPAGE DU TEMPS (delta_effectif) ----
# Une entite tickee 1 frame sur `cadence` a saute `cadence` frames de temps reel
# depuis son dernier pas. On lui passe delta_effectif = delta_frame * cadence pour
# qu'elle avance de tout le temps ecoule d'un coup -- sa vitesse moyenne reste
# juste, seule la resolution temporelle baisse avec la distance / le LOD.
#
# ---- CLES LUES / ECRITES (contrat d'entite additionnel) ----
# Lues (fixees a la CREATION de l'entite par le gameplay) :
#   entite.proprietes.profil       : String  ("complet"/"simple"/"minimal" -- politique_intrinseque)
#   entite.proprietes.cadence_tick : int     (frames entre deux ticks -- politique_intrinseque)
#   entite.proprietes.groupe       : String  (nom du groupe -- politique_groupe)
# Ecrites (internes au module) :
#   entite.proprietes.frames_depuis_tick : int
#   entite.proprietes.cadence_lod        : int    (info debug/inspection)
#   entite.proprietes.profil_lod         : String (info debug/inspection)
#
# ---- PRIMITIVES EXTERNES APPELEES ----
#   Mouvement.pas(entite, delta, monde, carte, profil)  (scripts/mouvement_kinematic.gd)
#
# ---- INTERDITS ----
# Aucun Input. Aucun get_tree / get_node / _observateur / Node. Aucun test
# entite.get("type") == "..." (agnostique du type). Aucun preload de scene .tscn.
# Aucune ecriture de entite.position / entite.velocite / entite.noeud, ni d'aucune
# cle de proprietes autre que frames_depuis_tick / cadence_lod / profil_lod.
#
# ECART AVEC LE DEPOT FRAMEWORK : ce fichier est NEUF dans cette copie de
# scripts/ ; le depot orion ne le porte pas encore. Divergence assumee par Yael
# faute d'une couche de cadencement partagee cote framework (voir CLAUDE.md
# § Frontiere ; meme geste que scripts/monde.gd:retirer et
# scripts/mouvement_kinematic.gd).

const Mouvement = preload("res://scripts/mouvement_kinematic.gd")

# ---- CONSTANTES DE politique_distance (LOD par distance) ----
# Seuils en metres, precalcules AU CARRE pour comparer sans sqrt.
const DIST_COMPLET := 30.0
const DIST_COMPLET_2 := DIST_COMPLET * DIST_COMPLET
const DIST_SIMPLE_60 := 100.0
const DIST_SIMPLE_60_2 := DIST_SIMPLE_60 * DIST_SIMPLE_60
const DIST_SIMPLE_10 := 300.0
const DIST_SIMPLE_10_2 := DIST_SIMPLE_10 * DIST_SIMPLE_10
# Cadences : nombre de frames entre deux ticks.
const CADENCE_60HZ := 1   # tick chaque frame (~60 Hz a 60 fps)
const CADENCE_10HZ := 6   # tick 1 sur 6 (~10 Hz)
const CADENCE_2HZ := 30   # tick 1 sur 30 (~2 Hz)

# POLITIQUE INTRINSEQUE : profil et cadence poses A LA CREATION de l'entite par le
# gameplay, jamais recalcules. La simulation ne depend PAS de l'observateur -- le
# temps du monde est uniforme. Pour tout monde emergent. Ne modifie rien.
static func politique_intrinseque(entite: Dictionary) -> Dictionary:
	var p: Dictionary = entite.proprietes
	return {
		"profil": String(p.get("profil", "simple")),
		"cadence": int(p.get("cadence_tick", 1)),
	}

# POLITIQUE DISTANCE : profil et cadence deduits de la distance a l'observateur.
# Pour l'action centree sur un point chaud. Ne modifie rien.
static func politique_distance(entite: Dictionary, observateur_position: Vector3) -> Dictionary:
	var d2: float = entite.position.distance_squared_to(observateur_position)
	if d2 < DIST_COMPLET_2:
		return {"profil": "complet", "cadence": CADENCE_60HZ}
	if d2 < DIST_SIMPLE_60_2:
		return {"profil": "simple", "cadence": CADENCE_60HZ}
	if d2 < DIST_SIMPLE_10_2:
		return {"profil": "simple", "cadence": CADENCE_10HZ}
	return {"profil": "minimal", "cadence": CADENCE_2HZ}

# POLITIQUE GROUPE : profil et cadence lus dans une table fournie, indexee par le
# nom de groupe de l'entite. Utilitaire (pause de zone, tests). Groupe absent de
# la table -> defaut sur ("simple", 1). Ne modifie rien.
static func politique_groupe(entite: Dictionary, table_groupes: Dictionary) -> Dictionary:
	var groupe: String = String(entite.proprietes.get("groupe", ""))
	var d = table_groupes.get(groupe, null)
	if d is Dictionary:
		return {
			"profil": String(d.get("profil", "simple")),
			"cadence": int(d.get("cadence", 1)),
		}
	return {"profil": "simple", "cadence": 1}

# TICK GENERIQUE D'UNE ENTITE. Demande la decision a `politique` (un Callable a un
# seul argument -- les politiques a parametre supplementaire sont pre-liees par
# l'appelant via .bind(...)), tient un compteur de frames, et appelle Mouvement.pas
# quand la cadence est atteinte, avec un delta rattrape.
static func tick_entite(entite: Dictionary, politique: Callable, delta_frame: float, monde, carte) -> void:
	# T.0 -- Garde.
	if delta_frame <= 0.0:
		return
	# T.1 -- Decision.
	var decision: Dictionary = politique.call(entite)
	var profil: String = String(decision.get("profil", "simple"))
	var cadence: int = int(decision.get("cadence", 1))
	# T.2 -- Compteur (defaut = cadence : la premiere frame declenche un tick).
	var p: Dictionary = entite.proprietes
	var frames: int = int(p.get("frames_depuis_tick", cadence))
	# T.3 -- Decrementation-non-tick.
	if frames + 1 < cadence:
		p["frames_depuis_tick"] = frames + 1
		return
	# T.4 -- Tick. Le delta rattrape le temps saute depuis le dernier pas.
	p["frames_depuis_tick"] = 0
	p["cadence_lod"] = cadence
	p["profil_lod"] = profil
	var delta_effectif: float = delta_frame * float(cadence)
	Mouvement.pas(entite, delta_effectif, monde, carte, profil)
