# FlopEDTKit

Le socle non graphique de la v2 : modèles, calendrier ISO et accès réseau.
Aucun `import SwiftUI` ici — la couche présentation viendra par-dessus.

## Pourquoi un package séparé

Il se compile et se teste en ligne de commande, sans projet Xcode ni simulateur.
Toute la logique sensible (numéro de semaine, hiérarchie des groupes, décodage
des réponses) est donc vérifiable en une seconde, et la frontière avec l'UI est
imposée par le compilateur plutôt que par la discipline.

## Contenu

| Fichier | Rôle |
|---|---|
| `Calendar/FlopCalendar` | Calendrier ISO 8601 figé sur Europe/Paris |
| `Calendar/ISOWeek` | La semaine telle que l'API l'attend |
| `Calendar/FrenchHolidays` | Les 11 fériés, calculés hors ligne depuis Pâques |
| `Models/` | Les réponses du serveur, en types Swift |
| `Networking/Endpoint` | Une requête GET typée par sa réponse |
| `Networking/Lenient` | Un tableau qui écarte l'élément illisible, pas la liste |
| `Networking/FlopEndpoints` | Le catalogue des requêtes de l'app |
| `Networking/FlopAPIClient` | Le client HTTP |
| `Referential/Referential` | Ce que la v1 codait en dur, tel que le serveur l'annonce |
| `Referential/ReferentialLoader` | Disque → instantané embarqué → réseau |
| `Referential/ReferentialStorage` | Persistance et instantané livré dans l'app |
| `Referential/ScheduleSelection` | L'emploi du temps choisi, conservé entre deux lancements |
| `Schedule/WeekSchedule` | Une semaine de cours, et l'issue d'un chargement |
| `Schedule/ScheduleStore` | Cache, réseau, préchargement, détection de changement |
| `Schedule/ScheduleCache` | Un fichier par semaine, élagué à 24 entrées |
| `Rooms/RoomOccupancy` | Le calcul des salles libres |
| `Rooms/RoomStore` | Ce qu'il faut télécharger pour ce calcul |

Les particularités de l'API sont documentées dans `../API-FLOPEDT.md`.

## Décodage tolérant

Deux principes, tirés de pannes réelles.

**Un champ absent ne doit jamais coûter plus que lui-même.** Une valeur par
défaut ne rend pas une clé facultative au décodage : `Referential`,
`DepartmentReferential` et `WeekSchedule` ont donc un `init(from:)` en
`decodeIfPresent`. Sans cela, ajouter un champ dans une nouvelle version rend
illisible tout ce qu'a écrit la précédente — c'est-à-dire le cache hors ligne.

**Un élément illisible ne doit pas emporter la liste.** `JSONDecoder` traite un
tableau comme un tout. Le serveur renvoie `"number": null` sur certains TP
(CS1/1GB2, semaines 36 et 40 de 2026, la rentrée) : un `Int` non optionnel
faisait échouer les douze cours de la semaine, et l'étudiant voyait « Réponse
illisible du serveur » sans recours. Les tableaux de cours passent donc par
`Lenient`, qui écarte l'élément fautif et compte les écarts dans
`WeekSchedule.unreadableCourses` — écarter vaut mieux qu'échouer, mais l'app doit
pouvoir le dire plutôt que de faire disparaître un cours en silence.

## Salles libres

Trois pièges rendent le calcul naïf faux.

**Les salles se chevauchent.** Réserver `B101-B102` occupe B101 *et* B102 ;
`1er Etage + B219` en bloque sept d'un coup ; `Entretien` bloque B010, B115 et
B005. D'où l'expansion par `Room.basicRooms` — sans elle, l'app proposerait des
salles en réalité prises. Seules les salles de base sont proposées : offrir
`B101-B102` alors que B101 est occupé n'aurait pas de sens.

**La durée d'un cours n'est pas dans sa réponse.** Elle dépend du type et vient
de `/courses/type/?dept=` — un barème **par département**. Appliquer celui de
l'utilisateur aux cours des autres décalerait les fins d'occupation.

**Les salles sont partagées entre départements.** C'est le piège le plus coûteux,
parce qu'il produit exactement la faute qu'un tel écran ne peut pas se
permettre : annoncer libre une salle occupée. Un TD de CS en C004 n'apparaît pas
dans l'emploi du temps d'INFO, mais C004 est bien prise. Mesuré sur la semaine 12
de 2026, jeudi 10h00 : sur les 15 salles qu'un calcul limité à INFO annonçait
libres, 4 étaient occupées par CS ou GIM. Sur la semaine entière, 60 créneaux
faux sur 8 des 24 salles de base.

`RoomOccupancy` prend donc une `Source` par département — ses salles, ses cours,
ses indisponibilités, son barème — et ne propose que les salles de base du
département consulté. Un département injoignable ressort dans
`missingDepartments` : le résultat devient optimiste, et l'écran le signale.

Le résultat est trié par temps de disponibilité décroissant, ce qui répond à la
vraie question — « où puis-je m'installer sans être délogé dans dix minutes ? ».
`RoomStatus` porte aussi le motif de l'occupation, cours ou indisponibilité
déclarée.

`RoomStore` conserve d'un appel sur l'autre ce qui ne bouge pas de l'année — la
table des salles et le barème de durées, pour chaque département — mais
retélécharge toujours cours et indisponibilités : une salle libérée il y a dix
minutes doit apparaître libre.

C'est la seule requête lourde de l'app : 66 Ko **par département** contre 9,8 Ko
pour un emploi du temps de groupe, d'où son cantonnement à cet écran. Les cinq
départements partent en parallèle. Mesuré le 29/08/2026 sur la prod, ouverture
de l'écran de bout en bout :

| | |
|---|---|
| Un seul département (ce que faisait l'app, et c'était faux) | 4,2 s |
| Cinq départements, première ouverture | 8,9 s |
| Cinq départements, ouvertures suivantes | 5,8 s |
| Cinq départements, changement de semaine | 6,1 s |

Le prix de la justesse est donc d'environ un doublement à la première ouverture,
puis une seconde et demie. L'écran affiche un indicateur d'activité pendant ce
temps ; il est ouvert délibérément, et rarement.

## Fraîcheur de l'emploi du temps

La règle tient en une phrase : **le cache sert à ne jamais montrer d'écran vide,
jamais à éviter une requête.** C'est ce qui distingue l'app des flux iCal des
enseignants, qui ne se rafraîchissent qu'une fois par jour alors qu'un cours peut
être déplacé d'une heure à l'autre.

`ScheduleStore.load(_:)` rend donc au plus deux valeurs : ce qu'il a en cache,
puis ce que dit le serveur. En cas de panne, `.failed` transporte quand même les
données périmées, pour qu'une coupure réseau se traduise par un bandeau discret
et non par un écran vide.

Contrôler la version avant de télécharger a été écarté sur mesures : une semaine
filtrée pèse 9,8 Ko pour 0,42 s, un contrôle de version 70 octets pour 0,30 s. Le
temps part dans l'aller-retour, pas dans les octets — on économiserait 0,12 s au
prix du risque d'afficher un emploi du temps périmé en le croyant à jour.

**Une seule exception, `ScheduleStore.recentEnough` : dix secondes.** Une copie
que l'app vient elle-même de télécharger est rendue telle quelle. Le cas visé est
précis : `prefetch` charge la semaine voisine, l'utilisateur y arrive deux
secondes plus tard, et on la redemandait au serveur. Le gain de fraîcheur était
nul — le sondage repasse toutes les 120 s — mais le coût était visible. Fin
août 2026, pendant que l'IUT régénérait l'année entière, les deux requêtes
tombaient de part et d'autre d'une modification : la semaine s'affichait, puis
se remplaçait une demi-seconde plus tard, sans que rien ne l'explique.

Ce n'est pas « le cache évite une requête » au sens écarté plus haut : c'est ne
pas demander deux fois la même chose en dix secondes.

Quand un remplacement a bien lieu — cache périmé puis réponse différente —
l'écran l'annonce désormais avec le même bandeau que le sondage. Remplacer en
silence ce que l'utilisateur vient de lire fait passer une correction légitime
pour un défaut d'affichage.

La version reste utile pour le **sondage pendant que l'app est ouverte**, où elle
devient rentable : `checkForUpdate(_:)` coûte 70 octets et ne retélécharge que si
la version a bougé. Elle est relevée en parallèle des cours, donc sans coût de
temps. Elle n'est jamais l'autorité sur la fraîcheur : si ce champ ment, le pire
cas est de rater une modification pendant quelques minutes, jamais d'afficher du
périmé au lancement.

Si `week-infos` a échoué au chargement de la semaine, la version est inconnue :
`checkForUpdate(_:)` retélécharge alors franchement plutôt que de renvoyer
`.indeterminate`. S'en tenir là condamnait le sondage à ne plus rien faire tant
que l'écran restait ouvert — la promesse de fraîcheur s'éteignait en silence.
Et une version qui bouge sans que les cours changent ne se signale pas : annoncer
« mis à jour » sans rien changer à l'écran laisse l'utilisateur chercher quoi.

## Démarrage

Le référentiel se résout dans cet ordre : cache disque, puis instantané embarqué,
puis réseau. Les deux premières sources sont immédiates, ce qui permet d'afficher
un écran sans attendre la réponse du serveur — et de faire fonctionner une
première installation même si le serveur de l'IUT est indisponible ce jour-là.

Il est découpé en deux parce que les deux moitiés n'ont pas le même coût : le
socle (départements, horaires) tient en deux petites requêtes, tandis que les
données par département en coûtent quatre chacune, soit environ 3 s pour les cinq.
Un étudiant n'en consulte qu'un : ils sont chargés à la demande.

Le **périmètre du rafraîchissement** compte donc autant que sa fréquence.
`refreshIfNeeded(maxAge:departments:)` prend la liste des départements à
revalider ; l'app passe le seul département suivi. Sans cette précision, on
revalidait « tous ceux déjà chargés » — or l'instantané embarqué en livre cinq,
ce qui faisait partir 23 requêtes à chaque lancement passé 24 h.

`forceRefresh(departments:)` fait la même chose sans condition d'âge : c'est ce
que déclenche le bouton des réglages, qui autrement passait par le garde de 24 h
et ne lançait aucune requête.

L'instantané embarqué est toujours traité comme périmé. Il porte la date de sa
fabrication, pas celle de l'installation, et entre les deux il s'écoule la revue
App Store puis le délai de mise à jour côté utilisateur.

Pour le régénérer, voir `Sources/FlopEDTKit/Resources/referential-snapshot.json` :
c'est un assemblage des réponses brutes de l'API, décodable avec le même codec
que les réponses en direct. Le test « L'instantané embarqué est complet et
décodable » échoue s'il cesse de correspondre.

À ne pas confondre avec la fraîcheur de l'emploi du temps : le référentiel change
une fois par an et se revalide toutes les 24 h, alors que les cours sont
retéléchargés à chaque lancement.

## Les deux bugs que ce socle rend impossibles

**Le nouvel an.** La v1 construisait sa requête avec `component(.weekOfYear)` et
`component(.year)`, deux champs incohérents à cheval sur janvier : le lundi
29/12/2025 appartient à la semaine ISO 1 de *2026*, mais `.year` renvoie 2025.
L'app demandait la semaine 1 de 2025 et affichait une semaine vide. `ISOWeek` est
le seul moyen de construire ces paramètres, et n'expose que l'année ISO.

**Le décalage de jour.** `HorizontalCalendar.swift:168` positionnait le jour
sélectionné avec `component(.weekday) - 1`, numéroté à partir du dimanche, dans un
tableau ordonné à partir de `firstWeekday`. Les deux ne coïncident qu'aux
États-Unis ; sur un iPhone français la sélection glissait d'un jour à chaque
changement de semaine. `Weekday(date:)` passe par le décalage depuis le lundi ISO
et ne dépend plus de la locale.

## Tests

```bash
swift test
```

149 tests hors ligne en moins de trois secondes, plus 8 tests live désactivés par
défaut — dont le balayage de la rentrée, derrière sa propre variable. Les tests de décodage portent sur des réponses réellement capturées sur
`flopedt.iut-blagnac.fr` (dossier `Tests/FlopEDTKitTests/Fixtures`), pas sur du
JSON écrit à la main : un changement de forme du serveur s'y voit.

`AuditRegressionTests` et `AuditNetworkRegressionTests` rejouent chacun des bugs
trouvés à l'audit du 28/08/2026, avec les données réelles qui les produisaient.

Pour interroger le vrai serveur — à faire avant une mise en production, ou quand
on soupçonne un changement d'API :

```bash
FLOP_LIVE_TESTS=1 swift test --filter LiveAPITests
```

Ces tests vérifient notamment que `lineage=true` reste équivalent au filtrage
manuel de la v1 — l'hypothèse qui autorise à supprimer `GroupHierarchyManager`.

Et le balayage complet de la fenêtre de rentrée, cinquante-cinq requêtes
lourdes — c'est le contrôle qui aurait attrapé le `"number": null` :

```bash
FLOP_LIVE_TESTS=1 FLOP_LIVE_SWEEP=1 swift test --filter LiveAPITests
```

⚠️ Le serveur de l'IUT répond en 502 si on le bouscule. La suite live est
`.serialized` et le balayage limité à deux requêtes de front : ne pas relever
ces réglages.
