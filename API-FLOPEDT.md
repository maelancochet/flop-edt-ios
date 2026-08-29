# API FlOpEDT — référence pour la v2

Instance : `https://flopedt.iut-blagnac.fr/fr/api`
Stack : Django REST Framework + drf-yasg.

Schéma OpenAPI complet (153 endpoints), public et sans authentification :

```bash
curl -s "https://flopedt.iut-blagnac.fr/fr/api/redoc/?format=openapi" | python3 -m json.tool
```

Tout ce qui suit a été vérifié le 31/07/2026 contre l'instance de prod.
La racine `/fr/api/` renvoie une page de login : ce n'est pas un signe que l'API
est fermée, les endpoints ci-dessous répondent en anonyme.

---

## Référentiel — à charger au premier lancement

Ces quatre appels suffisent à supprimer la totalité du hardcode de la v1.

### `GET /fetch/alldepts/`

Aucun paramètre. Remplace la constante `departements`.

```json
[{"id": 103, "abbrev": "INFO"}, {"id": 115, "abbrev": "CS"},
 {"id": 116, "abbrev": "GIM"}, {"id": 117, "abbrev": "RT"},
 {"id": 134, "abbrev": "LPMA"}]
```

⚠️ **Ces identifiants bougent.** LPMA est passé de `119` à `134` entre le
31/07/2026 et le 28/08/2026. Ne jamais en coder un en dur : croiser par
`abbrev`, comme le fait `Referential.timeSettings(forDepartment:)`.

Pas de libellé long ni d'icône : à mapper côté app (`INFO` → « Informatique », `pc`).
Prévoir un libellé de repli pour un département qui apparaîtrait en cours d'année.

### `GET /fetch/idtrainprog/?dept=<abbrev>`

Les promos du département. Remplace la constante `periods`.

```json
[{"id": 189, "abbrev": "BUT1", "name": "BUT Informatique première année"}]
```

À utiliser tel quel dans l'onboarding : `name` est bien plus parlant que « 2e année ».
**Attention** : la promo n'est pas réductible à une année d'étude. RT expose
`BUT1, BUT2, BUT2A, BUT3, BUT3A` — les `*A` sont les parcours par alternance et
ont leur propre EDT. La v1 les écrasait en les rangeant sous « 2e / 3e année ».

### `GET /groups/structural/tree/?dept=<abbrev>`  ← **le plus important**

Renvoie l'arbre des groupes, **exactement au format du struct `GroupNode` de la v1**
(`parent`, `promo`, `promotxt`, `row`, `name`, `buttxt`, `children`). Un tableau
par promo, la racine portant le champ `promo`.

```json
[{"parent": "null", "promo": "BUT1", "promotxt": "BUT1", "row": 0,
  "name": "CE", "buttxt": "BUT1",
  "children": [{"name": "1", "parent": "CE",
                "children": [{"name": "1A", "parent": "1"}]}]}]
```

**La profondeur varie selon le département et la promo** — l'UI doit descendre
récursivement jusqu'à une feuille, sans jamais présumer du nombre de niveaux :

| Département | Profondeur des feuilles | Exemple |
|---|---|---|
| LPMA | 1 | `LPMA → TP1` |
| CS2, CS3 (`3FI`) | 1 | `CS2 → 2G1` |
| INFO BUT1, GIM, RT, CS1 | 2 | `CE → 1 → 1A` |
| INFO BUT2 et BUT3 | 3 | `CE → 12 → 1 → 1A` |

C'est ce qui rendait le `switch dept.code` de `saveSelection()` (v1) ingérable.

### `GET /courses/type/?dept=<abbrev>`

Durées des cours. Remplace les 5 fonctions `endTimeForXXX` de `FilterDataManager`.

```json
[{"name": "CM", "duration": 85}, {"name": "QCM", "duration": 20},
 {"name": "Conf 2h", "duration": 120}]
```

Garder un repli à 90 min pour un type inconnu.

### `GET /base/timesettings/`

Amplitude horaire et jours ouvrés. Remplace `startHour = 8` / `endHour = 20`
et le tableau `["m","tu","w","th","f"]` codés en dur.

```json
{"id": 148, "day_start_time": 480, "day_finish_time": 1125,
 "lunch_break_start_time": 750, "lunch_break_finish_time": 750,
 "days": ["m","tu","w","th","f"], "default_preference_duration": 90,
 "department": 103}
```

Minutes depuis minuit. `department` est l'**id** (pas l'abbrev), à croiser avec
`/fetch/alldepts/`. Les amplitudes diffèrent réellement entre départements
(INFO finit à 1125 = 18h45, LPMA à 1140 = 19h00).

⚠️ Ne pas filtrer côté serveur : `?department=INFO` renvoie une erreur de
validation et `?department=103` renvoie **302 vers le login**. Récupérer la liste
complète sans paramètre (200 en anonyme) et filtrer dans l'app.

---

## Emploi du temps

### `GET /fetch/scheduledcourses/`

| Paramètre | Requis | Note |
|---|---|---|
| `week` | ✅ | numéro de semaine **ISO** |
| `year` | ✅ | année **ISO** (`yearForWeekOfYear`, pas `year`) |
| `dept` | | abbrev |
| `train_prog` | | abbrev — **obligatoire dès que `group` est fourni** |
| `group` | | nom du groupe |
| `lineage` | | `true` = inclut les groupes parents (défaut `false`) |
| `work_copy` | | défaut `0` |
| `tutor_name` | | username enseignant |

**`train_prog` + `group` + `lineage=true` remplace tout le filtrage client de la v1.**
Vérifié sur INFO / BUT1 / 1A / S12-2026 : le serveur renvoie 22 cours, jeu d'IDs
strictement identique à celui produit par `CourseFilter.filterCourses` avec
`filtreCM=CE, filtreGroupe=1, filtreSousGroupe=1A`.

Conséquence : `GroupHierarchyManager` (344 lignes), les `@AppStorage` `filtreCM` /
`filtreGroupe` / `filtreSousGroupe` et le `switch` de `saveSelection()` disparaissent.
Il suffit de persister `dept`, `train_prog` et `group`.

Sans `group`, l'endpoint renvoie toute la promo (151 cours pour INFO S12) — c'est
ce qu'il faut pour le calcul des salles libres.

Omettre `group` renvoie `{"detail": "A training programme should be given when a
group name is given"}` si `train_prog` manque.

### `GET /fetch/weekdays/?dept=&week=&year=`

```json
[{"num": 0, "date": "16/03", "ref": "m", "name": "Lun."}]
```

⚠️ **Ne marque ni les fériés ni les vacances.** Renvoie `m,tu,w,th,f` y compris
pour une semaine d'août ou la semaine du 1er mai — c'est juste la projection des
`days` de `timesettings` sur des dates. Utile pour obtenir le mapping
date ↔ code jour, rien de plus.

### `GET /extra/week-infos/?dept=&week=&year=`

```json
{"version": 270, "proposed_pref": -1, "required_pref": -1, "regen": "N, 444"}
```

`version` est un compteur par semaine, qui bouge quand l'EDT de cette semaine est
modifié. Relevé sur INFO 2026 : S2=224, S11=307, S12=270, S20=84.

Utile pour le **polling en session** (70 octets contre 9,8 Ko pour l'EDT complet).
**Ne jamais s'en servir comme autorité de fraîcheur au lancement** : il n'est pas
prouvé qu'il s'incrémente à *chaque* déplacement de cours, et l'app doit rester
juste même si ce champ ment. Voir la stratégie de rafraîchissement plus bas.

`regen == "I"` et `version == 0` marquent une semaine jamais générée (S1, S17, S18
en 2026 = nouvel an et vacances de printemps). Signal **incomplet** : S10 et S26
sont vides avec `version > 0`. Ne pas en faire un détecteur de vacances fiable.

### `GET /fetch/bknews/?dept=&week=&year=`

Bandeaux d'info publiés par le département (vide la plupart du temps).

---

## Salles disponibles

### `GET /rooms/room/?dept=<abbrev>`  ← la clé du calcul

```json
{"id": 18, "name": "Amphi1", "subroom_of": [196],
 "departments": [103, 115, 116, 117, 119], "is_basic": true,
 "basic_rooms": [{"id": 18, "name": "Amphi1"}]}
```

**`basic_rooms` est indispensable** : les salles se chevauchent. Réserver
`B101-B102` occupe B101 *et* B102 ; `1er Etage + B219` en bloque 7 d'un coup ;
`Entretien` bloque B010, B115 et B005. Sans cette table, le calcul des salles
libres est faux.

### `GET /fetch/unavailableroom/?dept=&week=&year=`

Indisponibilités hors cours (ménage, maintenance, réunions).

```json
[{"room": "Amphi1", "day": "m", "start_time": 780, "duration": 75, "value": 0}]
```

### ⚠️ Les salles sont partagées entre départements

C'est le piège qui coûte le plus cher, parce qu'il produit exactement la faute
qu'un tel écran ne peut pas se permettre : **annoncer libre une salle occupée**.

La table d'INFO déclare 36 salles appartenant aussi à d'autres départements. Un
TD de CS en C004 n'apparaît pas dans `/fetch/scheduledcourses/?dept=INFO`, mais
C004 est bien prise. Mesuré sur la semaine 12 de 2026, jeudi 10h00, pour un
étudiant d'INFO :

| | occupées | libres |
|---|---|---|
| En ne lisant que INFO | 9 | **15** |
| En lisant les cinq départements | 13 | 11 |

Les quatre salles annoncées libres à tort : B006 (CS, MACC2 TD), B113 (GIM,
MATH2 TD90), C004 (CS, QUAL4 TD), C006 (CS, ANG4 TD). Sur la semaine entière :
60 créneaux faux, sur 8 des 24 salles de base d'INFO.

Il faut donc interroger **tous** les départements. Les requêtes partent en
parallèle : mesuré, on passe d'environ 1,9 s à 2,1 s.

Attention aussi au barème de durées : `/courses/type/?dept=` est **propre à
chaque département**, et un « TD » ne dure pas forcément la même chose partout.
Appliquer celui de l'utilisateur aux cours des autres décale les fins
d'occupation.

### Algorithme validé

1. Charger une fois `rooms/room/` pour **chaque** département → table
   `nom → [salles de base]`, prise en union : une salle composite peut n'être
   déclarée que chez GIM tout en bloquant une salle de base d'INFO.
2. Pour l'instant T visé, parcourir les cours de la semaine **de tous les
   départements**, chacun avec son propre barème de durées : si
   `start_time <= T < start_time + durée`, marquer occupées toutes les
   `basic_rooms` de `course.room.name`.
3. Idem avec `unavailableroom`, département par département.
4. Les salles de base **du département consulté** qui restent sont libres.

Implémenté dans `FlopEDTKit/Sources/FlopEDTKit/Rooms/RoomOccupancy.swift`, et
vérifié contre ce même résultat sur les données réelles de la semaine 12.

Deux détails relevés en le codant :
- `is_basic == true` sélectionne exactement les 24 salles de base d'INFO, et
  chaque salle de base se contient elle-même. Filtrer sur ce drapeau ou prendre
  l'union des `basic_rooms` donne le même ensemble.
- `value == 0` signifie indisponible. Toutes les entrées observées valent 0, mais
  une valeur non nulle exprimerait une préférence et non un blocage : la traiter
  comme une occupation masquerait des salles utilisables.

Endpoints d'appoint : `/rooms/all/?dept=` (salles groupées par type),
`/rooms/names/?dept=`, `/rooms/types/?dept=`.

---

## Coûts mesurés — dimensionnement du rafraîchissement

Le serveur **ne compresse pas** (`Accept-Encoding: gzip` renvoie la même taille).

| Requête | Taille | 31/07/2026 | 29/08/2026 |
|---|---|---|---|
| Semaine filtrée sur un groupe (22 cours) | 9,8 Ko | 0,42 s | **2,8 – 3,5 s** |
| Semaine complète d'un département (151 cours) | 66 Ko | 1,89 s | **4 – 19 s** |
| `week-infos` (contrôle de version) | 70 o | 0,30 s | 0,3 s |
| Arbre des groupes | 1,4 Ko | 0,23 s | 0,2 s |
| Liste des départements | 131 o | 0,22 s | 0,2 s |

⚠️ **Les temps de juillet ne sont plus représentatifs.** Les petites requêtes
n'ont pas bougé, mais tout ce qui touche `scheduledcourses` a été relevé entre 7
et 10 fois plus lent le 29/08/2026, avec une forte variance d'un appel à
l'autre — la semaine complète d'un département est passée sous les 4 s serveur
chaud et au-delà de 19 s à froid.

Conséquence directe : le délai d'expiration de 15 s de `FlopAPIClient` était
**plus court que la latence réelle du serveur**, ce qui transforme une réponse
lente en échec certain, que les tentatives suivantes ne font qu'allonger. Porté
à 30 s par requête et 60 s par ressource.

À remesurer avant la livraison : si la lenteur persiste à la rentrée, c'est
l'écran des salles libres qu'il faudra revoir, pas les délais.

**Conclusion : le temps est dominé par l'aller-retour, pas par la charge utile.**
Contrôler la version avant de télécharger fait gagner 0,12 s — donc au lancement,
télécharger directement l'EDT frais, sans contrôle préalable. Le `version` ne
devient rentable que pour du polling répété en session (70 o contre 9,8 Ko).

## Pas de fériés ni de vacances dans l'API

Aucun endpoint ne les expose — vérifié en cherchant `holiday`, `vacation`,
`ferie`, `break`, `closed` dans les 153 endpoints et toutes les définitions.

`/courses/module-full/?dept=` donne seulement les bornes de semestre
(`period: {starting_week: 35, ending_week: 6, name: "S1"}`), donc l'amplitude de
l'année scolaire, pas les coupures.

À traiter côté app :
- **Fériés** → calcul local. Les 11 fériés français se déduisent de la date de
  Pâques (algorithme de Meeus/Jones/Butcher) : Lundi de Pâques = P+1,
  Ascension = P+39, Lundi de Pentecôte = P+50, plus 8 dates fixes. Aucun réseau,
  aucune maintenance, valable pour n'importe quelle année.
- **Vacances** → ne pas chercher à les nommer. Une semaine sans aucun cours pour
  le groupe de l'utilisateur s'affiche « Aucun cours cette semaine », à partir de
  données déjà téléchargées. Nommer « Vacances de la Toussaint » imposerait la
  base open-data `data.education.gouv.fr` (calendrier par académie) pour un
  bénéfice purement cosmétique.

## Pièges

**Semaines ISO.** L'API attend des semaines ISO. La v1 utilisait
`Calendar.current` + `component(.year)`, ce qui casse au nouvel an :

| Date | v1 demande | Correct |
|---|---|---|
| 2025-12-29 | W01/**2025** | W01/**2026** |
| 2026-01-01 | W01/**2025** | W01/**2026** |

→ `Calendar(identifier: .iso8601)` et `component(.yearForWeekOfYear, from:)`.
Le calendrier ISO fixe aussi `firstWeekday` et `minimalDaysInFirstWeek`,
supprimant la dépendance à la locale de l'appareil.

**Le référentiel bouge.** Les données codées en dur dans la v1 sont déjà fausses :
INFO BUT3 y a un arbre vide alors que l'API en renvoie un complet, et CS2 est
passé de `2FA` / `2FI→2GA/2GB` à `2G1` / `2G2`. D'où la v2.

**Prévoir un repli hors-ligne.** Si l'API est indisponible au tout premier
lancement, l'app n'a aucun référentiel et devient inutilisable. Embarquer un
snapshot JSON dans le bundle, revalidé en tâche de fond.

**`supp_tutor` a un type instable** — la forme réellement observée en août 2026
est `{"username": …}`, jamais `{"name": …}`. La v1 gérait `String` et
`{"name": …}` et retombait donc silencieusement sur la chaîne vide. `SupplementaryTutor`
accepte désormais les trois formes.

**Des champs scalaires peuvent être `null`.** Relevé sur 2 622 cours (5 départements
× 8 semaines de 2026) : `pay_module`, `id_visio`, `tutor` — et **`number`**, qui
ne l'était pas dans le modèle. Un seul `null` sur un champ non optionnel fait
échouer le décodage de **tout le tableau** :

```
GET /fetch/scheduledcourses/?dept=CS&week=36&year=2026&train_prog=CS1&group=1GB2&lineage=true
→ cours 616313, "number": null
→ DecodingError.valueNotFound sur [2].number, les 12 cours sont perdus
```

S36 et S40 de 2026, c'est-à-dire la rentrée. D'où deux garde-fous :
`ScheduledCourse` décode en `decodeIfPresent` tout ce qui n'est pas indispensable
au placement du créneau, et les tableaux de cours passent par `Lenient`, qui
écarte l'élément fautif au lieu de la liste entière.
