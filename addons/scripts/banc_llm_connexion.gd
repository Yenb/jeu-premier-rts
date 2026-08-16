extends SceneTree

# Lancement :
# godot --headless --script scripts/banc_llm_connexion.gd
#
# BANC JETABLE, hors moteur. Il ne compose aucun mecanisme du coeur, ne lit
# aucun catalogue de data/, n'est ramasse par aucun lanceur (son nom n'est pas
# test_*.gd) et rien du jeu ne l'appelle. Son seul role : prouver qu'un modele
# local repond a une requete du jeu, et qu'il ne renvoie RIEN d'autre qu'une
# cle d'une liste fermee.
#
# CE QU'IL MONTRE : le tuyau, jamais la decision. Le resume d'etat envoye est
# ecrit en dur ICI (une scene d'observation nommee, exception de CLAUDE.md pour
# un banc) -- il ne vient d'aucun monde simule et n'y retourne pas.
#
# CE QU'IL NE MONTRE PAS : la contrainte de sortie. Rien ici ne FORCE le modele
# a rester dans la liste ; le prompt le demande, le banc ne fait que constater.
# Un modele qui deborde rend ROUGE avec sa reponse brute -- c'est le resultat
# utile, pas un echec du banc.
#
# Entree : aucune. L'hote, le port, le modele et les cles acceptees sont les
# constantes ci-dessous. Sortie : la reponse BRUTE du modele, puis VERT si la
# reponse nettoyee (strip_edges + to_lower) est exactement une des cles, ROUGE
# sinon ou si la requete n'aboutit pas. Code de sortie 0 sur VERT, 1 sur ROUGE.
#
# Regles tenues : aucun etat du monde n'est invente par le modele -- le banc
# LIT sa reponse et la confronte a une liste close, il ne l'interprete jamais
# (docs/design.md, « L'LLM : lecteur ancre, jamais auteur »). Aucun hasard.
# HTTPClient est poll SYNCHRONE, jamais un noeud HTTPRequest : un script
# --headless --script n'a pas d'arbre de scene ou accrocher un noeud.

# L'ADRESSE EST NUMERIQUE, jamais le nom « localhost » : ce nom resout aussi
# vers ::1, le serveur n'ecoute que sur 127.0.0.1, et HTTPClient reste alors
# en STATUS_CONNECTING jusqu'au delai maximum sans jamais rendre d'erreur.
const HOTE := "127.0.0.1"
const PORT := 11434
const CHEMIN := "/api/generate"
# Le nom doit correspondre EXACTEMENT a une entree de GET /api/tags du serveur.
# Un nom absent rend un HTTP 404 nomme, jamais un modele de repli silencieux.
const MODELE := "llama3.2:3b"

# La liste fermee. Toute autre reponse, meme plausible, est ROUGE.
const CLES_VALIDES := ["production", "defense", "assaut"]

const DELAI_MAX_MS := 30000
const PAS_ATTENTE_MS := 20

const RESUME_ETAT := "ÉTAT DE LA COLONIE\n" + \
	"Ressources: bois 1240, pierre 580, nourriture 320\n" + \
	"Menace: attaque récente côté nord, 2 soldats perdus\n" + \
	"Moral: bas\n" + \
	"\n" + \
	"Tu es l'IA de cette colonie. Choisis UNE action parmi : production, defense, assaut\n" + \
	"Réponds UNIQUEMENT par un seul mot parmi ces trois."

func _init() -> void:
	var corps := JSON.stringify({
		"model": MODELE,
		"prompt": RESUME_ETAT,
		"stream": false,
		"options": {
			"num_predict": 10,
			"temperature": 0.3,
		},
	})

	print("Requete vers http://%s:%d%s (modele %s, delai max %d s)" % [
		HOTE, PORT, CHEMIN, MODELE, DELAI_MAX_MS / 1000])

	var resultat := _interroger(corps)
	if resultat.has("erreur"):
		_rouge(resultat["erreur"], resultat.get("brut", ""))
		return

	var brut: String = resultat["brut"]
	var nettoye := brut.strip_edges().to_lower()

	print("--- reponse brute du modele ---")
	print(brut)
	print("--- fin de la reponse brute ---")
	print("Reponse nettoyee : \"%s\"" % nettoye)

	if CLES_VALIDES.has(nettoye):
		print("VERT: le modele a rendu la cle \"%s\", membre de la liste fermee %s" % [
			nettoye, str(CLES_VALIDES)])
		quit(0)
		return

	# Le brut est deja affiche ci-dessus : le repasser ici l'imprimerait deux fois.
	_rouge("la reponse nettoyee n'est aucune des cles %s" % str(CLES_VALIDES), "")

func _rouge(raison: String, brut: String) -> void:
	if brut != "":
		print("--- reponse brute du modele ---")
		print(brut)
		print("--- fin de la reponse brute ---")
	print("ROUGE: %s" % raison)
	quit(1)

# Rend { "brut": <champ response du modele> } ou { "erreur": <raison>,
# "brut": <ce qui a pu etre lu> }. Le champ "response" est STRUCTUREL : son
# absence est une erreur nommee, jamais une chaine vide silencieuse.
func _interroger(corps: String) -> Dictionary:
	var client := HTTPClient.new()
	var debut := Time.get_ticks_msec()

	var erreur := client.connect_to_host(HOTE, PORT)
	if erreur != OK:
		return {"erreur": "connect_to_host a rendu l'erreur %d" % erreur}

	var attente := _attendre(client, debut, [
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING])
	if attente != "":
		return {"erreur": attente}
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"erreur": "connexion impossible a %s:%d (statut %d) -- le serveur ecoute-t-il ?" % [
			HOTE, PORT, client.get_status()]}

	erreur = client.request_raw(
		HTTPClient.METHOD_POST,
		CHEMIN,
		PackedStringArray(["Content-Type: application/json"]),
		corps.to_utf8_buffer())
	if erreur != OK:
		return {"erreur": "request_raw a rendu l'erreur %d" % erreur}

	attente = _attendre(client, debut, [HTTPClient.STATUS_REQUESTING])
	if attente != "":
		return {"erreur": attente}

	if not client.has_response():
		return {"erreur": "aucune reponse HTTP (statut %d)" % client.get_status()}

	var code := client.get_response_code()
	var octets := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		if Time.get_ticks_msec() - debut > DELAI_MAX_MS:
			return {"erreur": "delai de %d ms depasse pendant la lecture du corps" % DELAI_MAX_MS}
		client.poll()
		var morceau := client.read_response_body_chunk()
		if morceau.size() == 0:
			OS.delay_msec(PAS_ATTENTE_MS)
		else:
			octets.append_array(morceau)

	var texte := octets.get_string_from_utf8()
	if code != 200:
		return {"erreur": "code HTTP %d" % code, "brut": texte}

	var charge = JSON.parse_string(texte)
	if typeof(charge) != TYPE_DICTIONARY:
		return {"erreur": "corps de reponse illisible en JSON", "brut": texte}
	if not charge.has("response"):
		return {"erreur": "le JSON ne porte aucun champ \"response\"", "brut": texte}

	return {"brut": str(charge["response"])}

# Poll tant que le statut reste dans les etats transitoires donnes. Rend "" si
# la transition a eu lieu, la raison du depassement sinon.
func _attendre(client: HTTPClient, debut: int, transitoires: Array) -> String:
	while transitoires.has(client.get_status()):
		if Time.get_ticks_msec() - debut > DELAI_MAX_MS:
			return "delai de %d ms depasse (statut %d)" % [DELAI_MAX_MS, client.get_status()]
		client.poll()
		OS.delay_msec(PAS_ATTENTE_MS)
	return ""
