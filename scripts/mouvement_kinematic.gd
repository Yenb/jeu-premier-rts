extends RefCounted

# MOUVEMENT KINEMATIC EN DONNEE PURE, PARTAGE PAR TOUT MOBILE DU MONDE (joueur,
# cubes errants, producteurs...). UNE seule implementation de la gravite, du
# blocage terrain, du snap au sol et de la collision inter-entites -- au lieu des
# trois reecritures actuelles (manager_proto_2._pas_joueur pour le joueur,
# ennemis.gd:_tick_ia_ennemis pour les cubes, manager_proto._avancer_donnees pour
# les producteurs), qui portent trois bugs differents. Un appelant compose
# l'intention (velocite horizontale voulue, saut demande) dans l'entite, puis
# appelle pas() ; le module avance la donnee et rien d'autre.
#
# AGNOSTIQUE DU TYPE. Le module ne connait AUCUNE chose du monde : ni "joueur",
# ni "cube", ni "mur". Il ne lit que des proprietes (velocite, gravite, formes,
# rayon...). Le profil ("complet" / "simple" / "minimal") choisit la RICHESSE de
# la simulation, jamais l'identite du mobile -- un cube en "complet" et un joueur
# en "complet" suivent exactement le meme chemin. C'est un mecanisme, pas un
# contenu (CLAUDE.md § ADN).
#
# PAS DE class_name (doctrine) : preload("res://scripts/mouvement_kinematic.gd").
#
# ---- CE QU'IL FAIT ----
# static pas(entite, delta, monde, carte, profil) : avance UNE entite d'un pas de
# `delta` seconde, en donnee pure. Dispatch par `profil` vers _pas_complet /
# _pas_simple / _pas_minimal. Profil inconnu : push_error + return, l'entite ne
# bouge pas.
#
# ---- CE QU'IL RECOIT (contrat d'entite, Dictionary) ----
# L'appelant fournit une entite conforme, et POSE l'intention avant l'appel (le
# module ne lit aucun Input). Cles lues/ecrites :
#   entite.position                              : Vector3  (lue ET ecrite : autorite data de la position)
#   entite.proprietes.velocite                   : Vector3  (lue ET ecrite : etat conserve d'un pas a l'autre)
#   entite.proprietes.au_sol                     : bool     (lue ET ecrite : le module tranche le contact)
#   entite.proprietes.formes                     : Array    (contrat collision.gd -- forme de collision de l'entite)
#   entite.proprietes.gravite                    : float    (acceleration vers le bas, par seconde)
#   entite.proprietes.rayon_capsule              : float    (rayon de collision ; joueur : personnage.gd:rayon_effectif())
#   entite.proprietes.hauteur_capsule            : float    (hauteur de collision, pour l'obstacle a hauteur de corps)
#   entite.proprietes.saut_demande               : bool     (POSE par l'appelant -- evenement, pas un Input lu ici)
#   entite.proprietes.vitesse_saut               : float    (impulsion verticale quand saut_demande et au_sol)
#   entite.proprietes.velocite_desiree_horizontale : Vector3 (l'intention horizontale, calculee en amont)
#   entite.proprietes.y_appui_entite             : float    (POSE par _tick_collision AVANT l'appel : dessus de l'entite sous les pieds, -INF si aucune)
#
# ---- CE QU'IL N'ECRIT PAS ----
# entite.noeud, aucun rendu, aucun Node : le rendu suit la donnee, ailleurs.
#
# ---- PRIMITIVES EXTERNES QU'IL UTILISERA (phase 2+, pas encore appelees) ----
#   monde  (scripts/monde.gd)              : requete spatiale + deplacer() apres mouvement
#   collision.gd (jeu/Proto/collision.gd)  : Collision.tick / resoudre (GJK/EPA), collision inter-entites en donnee pure
#   carte.sommet_sous(x, z, y_max)         : surface pleine la plus haute <= y_max (sol sous les pieds, plafonne un surplomb)
#   carte.est_pleine(colonne, couche)      : masque de volume -- obstacle a hauteur de corps (scale avec la taille)
#   carte.sommet(x, z)                     : point le plus haut d'une colonne
#
# ---- CE QU'IL NE FAIT PAS (interdits absolus) ----
# Aucun Input.xxx. Aucun get_tree / get_node / _observateur / Node. Aucun test
# entite.get("type") == "..." (agnostique du type). Aucun preload de scene .tscn.
# Aucune ecriture de entite.noeud.
#
# ---- REGLES TENUES ----
# Positions en Vector3. Aucun hasard non-seede (le module n'introduit aucun alea).
# La simulation ne depend pas de l'affichage. Aucune categorie du monde nommee.
#
# ECART AVEC LE DEPOT FRAMEWORK : ce fichier est NEUF dans cette copie de
# scripts/ ; le depot orion ne le porte pas encore. Divergence assumee par Yael
# faute d'un mecanisme de mouvement partage cote framework (voir CLAUDE.md
# § Frontiere pour la raison d'etre de l'ecart et sa portee ; meme geste que
# scripts/monde.gd:retirer).

# DEPENDANCE DE COUCHE A SIGNALER : ce module (scripts/, framework) preload
# collision.gd qui vit encore dans jeu/Proto/ (prototype destine a Orion, voir
# jeu/Proto/COLLISION.md). C'est une dependance framework -> jeu, a l'envers de la
# couche normale. Elle se resorbe quand collision.gd migrera dans scripts/ cote
# framework ; d'ici la, le chemin reste jeu/Proto/.
const Collision = preload("res://jeu/Proto/collision.gd")

# ---- CONSTANTES DU PROFIL COMPLET ----
# STEP_OFFSET : hauteur max qu'on monte (step-up) ET qu'on colle en descente
#   (step-down snap). Au-dela, en descente, on DECROCHE et on tombe -- c'est la
#   borne qui remplace le snap-teleport de l'ancien _pas_joueur.
const STEP_OFFSET := 0.3
# SAFE_MARGIN : sous ce seuil de penetration, un contact est considere resolu
#   (fin du multipass). SAFE_MARGIN*10 borne la separation appliquee PAR PASSE :
#   une penetration profonde se resout en plusieurs passes, jamais en un teleport.
const SAFE_MARGIN := 0.01
# VITESSE_TERMINALE : plancher de ve.y, chute libre bornee (m/s).
const VITESSE_TERMINALE := 55.0
# cos(45°) : un contact dont la normale de separation (vue par l'entite) pointe
#   vers le haut au-dela de ce seuil est un SOL sous ses pieds (entite POSEE sur
#   l'autre) -- sert a calculer y_appui_entite (dessus du cube porteur).
const COS_SOL_MARCHABLE := 0.707
# Nombre d'iterations tick+separation par pas atomique : resout les empilements
#   et les penetrations profondes en plusieurs passes bornees.
const MULTIPASS_N := 4
# PENTE_MAX : pente maximale franchissable en marche (tan de l'angle). 1.5 = ~56°.
#   Au-dela, l'obstacle devant est traite comme un mur (bloque). En deca, c'est une
#   rampe / marche haute que le joueur monte. Le seuil scale avec le rayon de la
#   capsule via `rayon * PENTE_MAX` -- un gros perso franchit des marches plus
#   hautes qu'un petit.
const PENTE_MAX := 1.5

# AVANCE UNE ENTITE D'UN PAS. Dispatch par profil vers l'implementation de la
# richesse voulue. Le corps des trois _pas_* est VIDE en phase 1 : cette phase
# n'etablit que le squelette et le contrat ; la logique de mouvement (gravite,
# blocage, snap, collision) arrive en phase 2 (_pas_complet) puis phase 3
# (_pas_simple, _pas_minimal).
static func pas(entite: Dictionary, delta: float, monde, carte, profil: String) -> void:
	match profil:
		"complet":
			_pas_complet(entite, delta, monde, carte)
		"simple":
			_pas_simple(entite, delta, monde, carte)
		"minimal":
			_pas_minimal(entite, delta, monde, carte)
		_:
			push_error("Mouvement.pas : profil inconnu : %s" % profil)

# PROFIL COMPLET : simulation la plus riche (gravite continue, blocage terrain au
# rayon de la capsule, step-up borne, snap-sol borne sinon chute, collision
# inter-entites). Destine au joueur et aux mobiles qui doivent tenir le contact
# fin avec le monde.
#
# ETAPE A -- SUB-STEPPING. Un pas trop long par rapport a la taille de l'entite
# tunnellerait a travers un mur mince. On decoupe le pas en N sous-pas pour que
# chaque sous-pas avance au plus d'un demi-rayon, puis on avance N fois par le pas
# atomique. La logique gameplay vit DANS _pas_complet_atomique, jamais ici.
static func _pas_complet(entite: Dictionary, delta: float, monde, carte) -> void:
	if delta <= 0.0 or carte == null:
		return
	var ve: Vector3 = entite.proprietes.get("velocite", Vector3.ZERO)
	var v: float = ve.length()
	var rayon: float = float(entite.proprietes.get("rayon_capsule", 0.4))
	var n := 1
	if rayon > 0.0 and v * delta > rayon * 0.5:
		n = int(ceil(v * delta / (rayon * 0.5)))
	var sub_delta: float = delta / float(n)
	for _i in range(n):
		_pas_complet_atomique(entite, sub_delta, monde, carte)

# UN SOUS-PAS ATOMIQUE DU PROFIL COMPLET, dans l'ordre B.1 -> B.13. Un seul flux :
# gravite TOUJOURS, saut, composition horizontale, blocage au rayon de la capsule
# avec glissement, application, snap-sol BORNE (sinon chute), au_sol conditionnel,
# puis multipass de collision inter-entites (separation clampee par SAFE_MARGIN,
# pas Collision.resoudre) et calcul du dessus du cube porteur (y_appui_entite).
static func _pas_complet_atomique(entite: Dictionary, dt: float, monde, carte) -> void:
	var p: Dictionary = entite.proprietes
	var ve: Vector3 = p.get("velocite", Vector3.ZERO)
	var gravite: float = float(p.get("gravite", 18.0))
	var rayon: float = float(p.get("rayon_capsule", 0.4))

	# B.1 -- Gravite TOUJOURS, hors branche (jamais "si au_sol alors skip").
	ve.y -= gravite * dt
	# B.2 -- Vitesse terminale.
	ve.y = maxf(ve.y, -VITESSE_TERMINALE)
	# B.3 -- Saut : evenement, consomme (pas de repetition au tick suivant).
	if bool(p.get("saut_demande", false)) and bool(p.get("au_sol", false)):
		ve.y = float(p.get("vitesse_saut", 8.5))
		p["au_sol"] = false
	p["saut_demande"] = false
	# B.4 -- Composition horizontale : l'intention ecrase x/z. L'inertie en l'air
	# n'est PAS preservee ici -- l'appelant decide via velocite_desiree_horizontale.
	var vdh: Vector3 = p.get("velocite_desiree_horizontale", Vector3.ZERO)
	ve.x = vdh.x
	ve.z = vdh.z
	# B.5 -- Deplacement candidat.
	var dep: Vector3 = ve * dt

	# B.6 -- Blocage horizontal au rayon de la capsule + glissement (une reprise).
	var dir_h := Vector3(dep.x, 0.0, dep.z)
	if dir_h.length() > 0.0001:
		var normale := _obstacle_hauteur_corps(entite, dir_h.normalized(), carte)
		if normale != Vector3.ZERO:
			var dep_glisse: Vector3 = dep - dep.dot(normale) * normale
			var dir_g := Vector3(dep_glisse.x, 0.0, dep_glisse.z)
			var bloque_encore := false
			if dir_g.length() > 0.0001:
				bloque_encore = _obstacle_hauteur_corps(entite, dir_g.normalized(), carte) != Vector3.ZERO
			if bloque_encore:
				dep = Vector3(0.0, dep.y, 0.0)
				ve.x = 0.0
				ve.z = 0.0
			else:
				dep = dep_glisse

	# B.6bis -- Ralentissement en montee de pente (physique reelle).
	# Sur plat, la vitesse voulue est horizontale ; sur une pente montante, le
	# snap-sol de B.8 ajoute gratuitement la hauteur, donc le joueur avancerait
	# plus vite (longueur physique = sqrt(dh^2 + dv^2) > dh). On reduit dh par
	# dh/sqrt(dh^2 + dv^2) = 1/sqrt(1 + (dv/dh)^2) = cos(angle) sans trigo.
	# UNIQUEMENT quand au sol : en vol/saut, aucun scaling.
	if bool(p.get("au_sol", false)):
		var dh: float = sqrt(dep.x * dep.x + dep.z * dep.z)
		if dh > 0.0001:
			var rayon_b6bis: float = float(p.get("rayon_capsule", 0.4))
			var plafond_pente: float = entite.position.y + rayon_b6bis * PENTE_MAX
			var sol_ici_v = carte.sommet_sous(entite.position.x, entite.position.z, plafond_pente)
			var sol_devant_v = carte.sommet_sous(entite.position.x + dep.x, entite.position.z + dep.z, plafond_pente)
			if sol_ici_v != null and sol_devant_v != null:
				var dv: float = float(sol_devant_v) - float(sol_ici_v)
				if dv > 0.0:
					var facteur: float = dh / sqrt(dh * dh + dv * dv)
					dep.x *= facteur
					dep.z *= facteur

	# B.7 -- Application horizontale.
	entite.position += Vector3(dep.x, 0.0, dep.z)

	# B.8 -- Application verticale + snap-sol BORNE.
	entite.position.y += dep.y
	var pos: Vector3 = entite.position
	var contact_terrain := false
	var contact_entite := false
	# Snap SEULEMENT en descente/stagnation (ve.y <= 0). En montee (saut), snapper
	# remettrait pos.y = sol chaque frame tant que dep.y reste dans la fenetre step
	# -> le saut ne decollerait jamais.
	var sol = carte.sommet_sous(pos.x, pos.z, pos.y + STEP_OFFSET)
	if sol != null and ve.y <= 0.0:
		var solf: float = float(sol)
		if pos.y > solf + STEP_OFFSET:
			pass  # sol trop bas (hors fenetre step) : pas de snap, on tombe.
		else:
			# Dans la fenetre step (descente) ou sous la surface (dans le terrain) :
			# se poser / remonter sur la surface.
			entite.position.y = solf
			contact_terrain = true
	# Dessus de l'ENTITE sous les pieds (cube), pose par la passe de collision
	# precedente : accepte un pas de plus si dans la fenetre step et au-dessus.
	var y_appui: float = float(p.get("y_appui_entite", -INF))
	if y_appui > -1e19 and ve.y <= 0.0 and (y_appui - entite.position.y) <= STEP_OFFSET and y_appui >= entite.position.y:
		entite.position.y = y_appui
		contact_entite = true

	# B.9 -- au_sol conditionnel : un contact vertical ET une vitesse non montante.
	# On n'arrete ve.y QUE si on est effectivement pose (jamais d'ecrasement sinon).
	var au_sol_final: bool = (contact_terrain or contact_entite) and ve.y <= 0.0
	p["au_sol"] = au_sol_final
	if au_sol_final:
		ve.y = 0.0

	# B.10 -- Ecrire l'etat.
	p["velocite"] = ve

	# Sans monde : pas de collision inter-entites (gardes null). On ne fabrique
	# aucun appui et on ne touche pas y_appui_entite (le terrain a deja tranche).
	if monde == null:
		return

	# B.11 -- Deplacer dans l'index spatial (position a jour avant broadphase).
	monde.deplacer(entite)

	# B.12 -- Multipass collision inter-entites. tick fait SA broadphase via
	# monde.choses_dans_rayon -- on ne lui pre-mache aucun voisin. On applique la
	# separation NOUS-MEMES, clampee a SAFE_MARGIN*10 par passe (Collision.resoudre
	# est bypasse : lui teleporterait de la profondeur entiere d'un coup).
	var id_e = entite.get("id")
	var contacts: Array = []
	for _passe in range(MULTIPASS_N):
		contacts = Collision.tick(monde, [entite], dt)
		var max_prof := 0.0
		for c in contacts:
			var est_a: bool = c.a.get("id") == id_e
			var est_b: bool = c.b.get("id") == id_e
			if not (est_a or est_b):
				continue
			var normale_sep: Vector3 = -c.normale if est_a else c.normale
			var prof: float = float(c.profondeur)
			max_prof = maxf(max_prof, prof)
			entite.position += normale_sep * minf(prof, SAFE_MARGIN * 10.0)
		monde.deplacer(entite)
		if max_prof < SAFE_MARGIN:
			break

	# B.13 -- y_appui_entite = TOP du (des) cube(s) porteur(s). Un contact dont la
	# separation vue par l'entite pointe vers le haut (>= COS_SOL_MARCHABLE) est un
	# appui : on prend le dessus de l'AABB de l'autre, le plus haut si plusieurs.
	# Aucun appui vertical -> -INF (le snap terrain reprend la main au tick suivant).
	var y_appui_nouveau := -INF
	for c in contacts:
		var est_a: bool = c.a.get("id") == id_e
		var est_b: bool = c.b.get("id") == id_e
		if not (est_a or est_b):
			continue
		var normale_sep: Vector3 = -c.normale if est_a else c.normale
		if normale_sep.y < COS_SOL_MARCHABLE:
			continue
		var autre: Dictionary = c.b if est_a else c.a
		y_appui_nouveau = maxf(y_appui_nouveau, _top_aabb(autre))
	p["y_appui_entite"] = y_appui_nouveau

# NORMALE D'UN MUR BLOQUANT DEVANT L'ENTITE, Vector3.ZERO si rien. Echantillonne
# la FACE AVANT du corps (segment de longueur 2*rayon, tangent a dir, centre sur
# pos + dir*rayon), avec un pas <= cote pour qu'aucune colonne de voxel dans la
# largeur du corps ne puisse etre survolee. Chaque sonde lit la hauteur REELLE du
# sol via sommet_sous (profil de rampe compris, plafonne a la tete pour ignorer
# un bloc suspendu au-dessus) et la compare a rayon * PENTE_MAX :
#   null (bord de carte / trou)              -> mur (on ne franchit pas un vide)
#   sol_devant > pos.y + rayon * PENTE_MAX   -> mur / marche trop haute -> bloque
#   sol_devant <= pos.y + rayon * PENTE_MAX  -> rampe / marche basse / plat -> passe
# est_pleine est ECARTE pour le test de sol (il rendrait vrai pour une rampe) mais
# CONSERVE pour le test de plafond (colonne de voxels devant, entre pieds et tete).
#
# ECART FRAMEWORK (local a ce depot) : la version d'origine sondait uniquement
# pos + dir*rayon (une sonde unique au bord). Insuffisant des que rayon > cote --
# la sonde atterrit au-dela du mur, dans le vide, et un grand personnage traverse
# les murs voxel. Reference : voxel-aabb-sweep (Fenomas) -- balayer la face avant
# de l'AABB, pas juste le coin. Le sub-stepping temporel reste porte par
# _pas_complet_atomique.
static func _obstacle_hauteur_corps(entite: Dictionary, dir: Vector3, carte) -> Vector3:
	var p: Dictionary = entite.proprietes
	var rayon: float = float(p.get("rayon_capsule", 0.4))
	var hauteur: float = float(p.get("hauteur_capsule", 1.8))
	var pos: Vector3 = entite.position
	var cote: float = 2.0
	if "cote" in carte:
		cote = float(carte.cote)
	var tangent := Vector3(-dir.z, 0.0, dir.x)
	var n_lateral: int = max(1, int(ceil(2.0 * rayon / cote)))
	for i in range(n_lateral + 1):
		var t: float = -rayon + (float(i) / float(n_lateral)) * 2.0 * rayon
		var x_sonde: float = pos.x + dir.x * rayon + tangent.x * t
		var z_sonde: float = pos.z + dir.z * rayon + tangent.z * t
		var sol_devant = carte.sommet_sous(x_sonde, z_sonde, pos.y + hauteur)
		if sol_devant == null:
			return -dir
		var solf: float = float(sol_devant)
		if solf > pos.y + rayon * PENTE_MAX:
			return -dir
		# Test espace vertical devant : un plafond trop bas arrete l'AVANCEE.
		# Couches PIEDS (juste au-dessus du sol) a TETE. Epsilon pour ne pas
		# retomber dans la couche du sol sur une frontiere de voxel, et pour ne pas
		# viser la couche au-dessus de la tete quand elle tombe pile dessus --
		# sinon range peut etre vide et rater le bloc traversant le corps.
		var epsilon := 0.001
		var colonne := Vector2i(int(floor(x_sonde / cote)), int(floor(z_sonde / cote)))
		var couche_pieds: int = int(floor((solf + epsilon) / cote))
		var couche_tete: int = int(floor((solf + hauteur - epsilon) / cote))
		for couche in range(couche_pieds, couche_tete + 1):
			if carte.est_pleine(colonne, couche):
				return -dir
	return Vector3.ZERO

# DESSUS (Y MAX) DE L'AABB MONDE D'UNE ENTITE, le plus haut de ses formes. Sert a
# poser y_appui_entite : ou se tient une entite posee sur celle-ci. -INF si l'entite
# n'a aucune forme.
static func _top_aabb(autre: Dictionary) -> float:
	var props: Dictionary = autre.get("proprietes", {})
	var formes: Array = props.get("formes", [])
	if formes.is_empty():
		return -INF
	var orient: Basis = props.get("orientation", Basis.IDENTITY)
	var top := -INF
	for f in formes:
		var tf: Transform3D = Transform3D(orient, autre.position) * f.get("transform_locale", Transform3D.IDENTITY)
		var aabb: AABB = Collision.aabb_forme(f, tf)
		top = maxf(top, aabb.position.y + aabb.size.y)
	return top

# REDIMENSIONNE UNE ENTITE : met a jour les endroits qui portent la taille de la
# capsule -- proprietes.hauteur_capsule / rayon_capsule, la forme de collision GJK
# (son transform_locale decale de +hauteur/2, origine aux pieds, et ses parametres
# rayon/hauteur) et le aabb_cache. A appeler au _ready du gameplay ET a chaque
# changement runtime de la taille : c'est LA source unique de verite, apres cet
# appel la collision suit le reglage. La premiere forme est la capsule principale.
static func redimensionner_entite(entite: Dictionary, nouvelle_hauteur: float, nouveau_rayon: float) -> void:
	if entite.is_empty():
		return
	var p: Dictionary = entite.proprietes
	p["hauteur_capsule"] = nouvelle_hauteur
	p["rayon_capsule"] = nouveau_rayon
	var formes: Array = p.get("formes", [])
	if formes.is_empty():
		return
	var forme: Dictionary = formes[0]
	forme["transform_locale"] = Transform3D(Basis.IDENTITY, Vector3(0.0, nouvelle_hauteur * 0.5, 0.0))
	var params: Dictionary = forme.get("parametres", {})
	params["rayon"] = nouveau_rayon
	params["hauteur"] = nouvelle_hauteur
	forme["parametres"] = params
	p["aabb_cache"] = Collision.aabb_forme(
		forme,
		Transform3D(Basis.IDENTITY, entite.position))

# PROFIL SIMPLE : mobs courants (errance des cubes, unites RTS standard). Ils
# avancent, tombent, et un mur/marche-trop-haute/bord-de-carte les arrete -- mais
# ils acceptent d'inter-penetrer un peu leurs voisins (personne ne mesure au
# millimetre a cette echelle). Reprend la regle de blocage de ennemis.gd
# (comparaison de sommets), portee dans le module partage.
# UN seul pas, UNE seule passe. PAS de sub-stepping, PAS de GJK/multipass, PAS de
# saut, PAS de y_appui_entite (le profil simple ne monte pas sur les autres).
static func _pas_simple(entite: Dictionary, delta: float, monde, carte) -> void:
	# S.0 -- Gardes.
	if delta <= 0.0 or carte == null:
		return
	var p: Dictionary = entite.proprietes
	# S.1 -- Lecture.
	var ve: Vector3 = p.get("velocite", Vector3.ZERO)
	var gravite: float = float(p.get("gravite", 18.0))
	# S.2 -- Gravite toujours.
	ve.y -= gravite * delta
	# S.3 -- Vitesse terminale.
	ve.y = maxf(ve.y, -VITESSE_TERMINALE)
	# S.4 -- Composition horizontale.
	var vdh: Vector3 = p.get("velocite_desiree_horizontale", Vector3.ZERO)
	ve.x = vdh.x
	ve.z = vdh.z
	# S.5 -- Deplacement candidat.
	var dep: Vector3 = ve * delta
	# S.6 -- Blocage terrain simple (regle ennemis.gd) : bord de carte ou marche
	# trop haute a la destination -> l'horizontale est annulee.
	var cote: float = 2.0
	if "cote" in carte:
		cote = float(carte.cote)
	var pos: Vector3 = entite.position
	var sol_ici = carte.sommet_sous(pos.x, pos.z, pos.y + cote)
	var sol_devant = carte.sommet_sous(pos.x + dep.x, pos.z + dep.z, pos.y + cote)
	if sol_ici == null or sol_devant == null:
		dep.x = 0.0
		dep.z = 0.0
		ve.x = 0.0
		ve.z = 0.0
	elif float(sol_devant) - float(sol_ici) > cote:
		dep.x = 0.0
		dep.z = 0.0
		ve.x = 0.0
		ve.z = 0.0
	# S.7 -- Application.
	entite.position += Vector3(dep.x, 0.0, dep.z)
	entite.position.y += dep.y
	# S.8 -- Snap sol simple (position atteinte).
	pos = entite.position
	var sol = carte.sommet_sous(pos.x, pos.z, pos.y + cote)
	var contact := false
	if sol != null and pos.y <= float(sol):
		entite.position.y = float(sol)
		contact = true
	# S.9 -- au_sol conditionnel.
	var au_sol_final: bool = contact and ve.y <= 0.0
	p["au_sol"] = au_sol_final
	if au_sol_final:
		ve.y = 0.0
	# S.10 -- Ecriture.
	p["velocite"] = ve
	# S.11 -- Deplacer index spatial.
	if monde != null:
		monde.deplacer(entite)

# PROFIL MINIMAL : mobs tres lointains ou occlus (LOD, tick 1/30). Ils avancent et
# ne traversent pas le terrain VISUELLEMENT -- rien de plus. Pas de gravite
# balistique : on colle directement au sol le plus haut. Pas de blocage, pas de
# collision (personne ne regarde de pres, un mob qui rase un mur ne derange
# personne). PAS de saut.
static func _pas_minimal(entite: Dictionary, delta: float, monde, carte) -> void:
	# M.0 -- Gardes.
	if delta <= 0.0 or carte == null:
		return
	var p: Dictionary = entite.proprietes
	# M.1 -- Lecture.
	var ve: Vector3 = p.get("velocite", Vector3.ZERO)
	var vdh: Vector3 = p.get("velocite_desiree_horizontale", Vector3.ZERO)
	# M.2 -- Composition horizontale (pas de gravite balistique en minimal).
	ve.x = vdh.x
	ve.z = vdh.z
	ve.y = 0.0
	# M.3 -- Application horizontale.
	entite.position.x += ve.x * delta
	entite.position.z += ve.z * delta
	# M.4 -- Snap sol strict : colle au sommet ; bord de carte -> pas de snap.
	var pos: Vector3 = entite.position
	var sol = carte.sommet(pos.x, pos.z)
	if sol != null:
		entite.position.y = float(sol)
	# M.5 -- Etat.
	p["au_sol"] = sol != null
	p["velocite"] = ve
	# M.6 -- Deplacer index spatial.
	if monde != null:
		monde.deplacer(entite)
