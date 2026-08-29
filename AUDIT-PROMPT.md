# Prompt d'audit — application flop!EDT v2 (iOS)

> À coller dans une nouvelle session Claude Code ouverte sur
> `/Users/ma3lich/Documents/Pro/Projet/flop-edt-ios`.

---

Tu prends la suite d'une session qui a réécrit de bout en bout une application
iOS d'emploi du temps. Ton rôle est **l'audit**, pas la poursuite du
développement : cherche les bugs, les incohérences et les angles morts qu'on a
laissés passer. Sois sceptique — la session précédente a écrit ce code *et* l'a
jugé, et plusieurs bugs sérieux n'ont été trouvés qu'en manipulant l'app.

## 1. Le projet

Application iOS affichant l'emploi du temps de l'IUT de Blagnac, alimentée par
l'API publique de flop!EDT (`https://flopedt.iut-blagnac.fr/fr/api`).

Elle remplace une v1 dont **tous les référentiels étaient codés en dur**
(départements, promos, groupes, durées de cours) et qu'il fallait reprendre à
chaque rentrée. **L'objectif central de la v2 est de supprimer cette maintenance
annuelle** : tout vient de l'API. Garde ce fil rouge en tête — tout `switch` sur
un nom de département, toute liste de groupes en dur, toute durée figée est une
régression de principe, même si le code fonctionne.

Second objectif : **la fraîcheur**. L'intérêt de l'app face aux flux iCal des
enseignants est d'afficher un emploi du temps à jour à la seconde. Un cours peut
être déplacé d'une heure à l'autre.

### Structure

```
flop-edt-ios/
├── API-FLOPEDT.md          ← référence de l'API, vérifiée sur la prod. À LIRE EN PREMIER.
├── FlopEDTKit/             ← paquet Swift, toute la logique hors interface (2 311 lignes)
│   ├── Sources/FlopEDTKit/{Calendar,Models,Networking,Referential,Rooms,Schedule}
│   ├── Sources/FlopEDTKit/Resources/referential-snapshot.json
│   └── Tests/              ← 127 tests (2 246 lignes), dont 6 « live » désactivés par défaut
└── flopEDT/flopEDT/        ← l'app SwiftUI (1 765 lignes, 13 fichiers)
    ├── App/                ← FlopEDTApp, AppModel (@Observable), RootView
    ├── Onboarding/         ← OnboardingView : département → promo → groupe (récursif)
    ├── Schedule/           ← ScheduleScreen, WeekStrip, DayTimeline, ChangeSelectionView
    ├── Rooms/              ← FreeRoomsView
    ├── Settings/           ← SettingsView
    └── Support/            ← DepartmentStyle, DebugOverrides, NavigationSubtitle
```

Cible **iOS 18**, Swift 6, bundle ID `flopEDT.flopEDT` (conservé de la v1 pour
livrer en mise à jour App Store), version 26.09, iPhone + iPad.

Architecture : **MV avec `@Observable`**, pas de MVVM. Un seul `AppModel` injecté
en Environment ; les *stores* (`ReferentialLoader`, `ScheduleStore`, `RoomStore`)
sont des `actor` dans le Kit. C'est délibéré, ne le remets pas en cause.

## 2. Contrainte matérielle importante

**Xcode n'est pas installé sur cette machine.** Il n'y a que les Command Line
Tools, sans SDK iOS. Concrètement :

- `xcodebuild` est inutilisable, l'app ne peut être ni compilée ni lancée ;
- `swift test` échoue : les macros de swift-testing exigent la toolchain Xcode ;
- **ne pars pas à la recherche de Xcode sur le système** — l'utilisateur a été
  explicite là-dessus, il compile et déploie lui-même sur son appareil.

Ce que tu **peux** faire :

- `swiftc -parse <fichier>` — contrôle syntaxique, sans typage ;
- `cd FlopEDTKit && swift build --target FlopEDTKit` — compile la bibliothèque
  pour macOS, ce qui **typecheck tout le Kit** (mais aucun fichier de l'app) ;
- `curl` vers l'API de prod, qui est publique et sans authentification ;
- rejouer une logique en Python sur les fixtures pour valider une donnée.

Donc : **l'audit est une revue de code, pas une campagne de tests.** Ton livrable
a d'autant plus de valeur que tu raisonnes juste sans exécuter.

## 3. Ce qui a déjà été vérifié — ne le refais pas

- Les 127 tests du Kit passaient (124 avant les 3 derniers, ajoutés mais **jamais
  exécutés** — vérifie-les par la lecture).
- Recette manuelle au simulateur : passage 2026→2027, jours fériés, les 5
  départements, mode sombre, iPad, tailles de texte d'accessibilité, parcours de
  sélection au doigt, défilement de la bande de dates.
- Le calcul des salles libres a été validé contre une implémentation Python
  indépendante sur données réelles (10 occupées / 14 libres, jeudi 10h, INFO).
- La jointure (promo, nom) qui donne le type d'un groupe : 161 résolutions, 0 échec.

## 4. Bugs déjà trouvés et corrigés — cherche leurs cousins

Ils indiquent où ce code a tendance à se tromper.

1. **Semaine ISO.** La v1 construisait ses requêtes avec `component(.weekOfYear)`
   + `component(.year)`, incohérents à cheval sur janvier : elle demandait la
   semaine 1 de 2025 au lieu de 2026 et affichait une semaine vide chaque année.
   → `ISOWeek` est désormais le seul chemin, et n'expose que `yearForWeekOfYear`.
2. **Index de jour dépendant de la locale.** Le composant d'origine indexait les
   jours avec `component(.weekday) - 1` (numéroté depuis dimanche) dans un tableau
   ordonné depuis `firstWeekday` : décalage d'un jour sur tout iPhone français.
   → `Weekday(date:)` passe par le décalage depuis le lundi ISO.
3. **Emploi du temps périmé après changement de groupe.** SwiftUI mettait
   `ScheduleScreen` à jour en place ; son `@State` survivait et affichait les
   cours de l'ancien groupe. → les semaines sont indexées par
   `ScheduleCacheKey(selection:week:)`, une entrée périmée est illisible.
4. **Feuille modale qui ne se fermait pas.** `@Environment(\.dismiss)` appelé
   depuis une vue *poussée* dans un `NavigationStack` dépile la navigation au
   lieu de fermer la feuille. → fermeture confiée à la racine de la feuille.
5. **Bande de dates figée.** Le verrou anti-scintillement du composant d'origine
   pouvait rester actif faute d'un nouvel événement de défilement.
   → remplacé par un `TabView` paginé sur un tableau de semaines **fixe**.
6. **Identité de vue instable.** Le tableau des semaines était recalculé à chaque
   `init`, ce qui recréait les pages en permanence et empêchait toute animation.
   → `@State` initialisé une seule fois.

7. **Cache invalidé en silence à chaque ajout de champ.** Une valeur par défaut
   ne rend pas un champ facultatif au décodage : le `init(from:)` synthétisé par
   Swift exige la clé. Ajouter un champ à `Referential` rendait donc illisible le
   fichier écrit par la version précédente de l'app — cache abandonné sans le
   moindre signal, données hors ligne perdues, compteur de fraîcheur remis à
   zéro. → `Referential` et `DepartmentReferential` ont un `init(from:)` tolérant
   (`decodeIfPresent`). **`WeekSchedule` a la même fragilité et n'a pas été
   traité** : la conséquence y est bénigne, l'emploi du temps étant de toute
   façon retéléchargé à chaque ouverture. À réévaluer.

## 5. Décisions délibérées — ne les signale pas comme des défauts

- **Le cache ne sert jamais à éviter une requête.** `ScheduleStore.load(_:)` rend
  le cache puis interroge **systématiquement** le serveur. Mesuré : une semaine
  filtrée pèse 9,8 Ko / 0,42 s, un contrôle de version 70 o / 0,30 s — le temps
  part dans l'aller-retour. Vérifier avant de télécharger ferait gagner 0,12 s au
  prix du risque d'afficher du périmé.
- `extra/week-infos` n'est **jamais** l'autorité sur la fraîcheur, seulement un
  sondage à 70 octets pendant que l'app est ouverte.
- L'instantané embarqué est **toujours traité comme périmé** : il porte sa date de
  fabrication, pas celle de l'installation.
- Le calendrier est figé sur **ISO 8601 / Europe-Paris**, jamais `Calendar.current`.
- Les jours fériés sont calculés hors ligne (algorithme de Pâques) : l'API n'expose
  ni fériés ni vacances — vérifié sur les 153 endpoints.
- Les vacances ne sont pas nommées : une semaine sans cours affiche « Aucun cours
  cette semaine ».
- `navigationSubtitle` (iOS 26) est derrière `if #available` à deux endroits ; sur
  iOS 18 le sous-titre est simplement absent. Assumé.
- Les libellés de promos viennent de l'API telle quelle, même quand ils sont
  médiocres (« BUT CS1 », « GIM1 »). On refuse de les corriger en dur.
- Le week-end est affiché dans la bande bien qu'il n'y ait jamais de cours :
  place réservée à de futurs modules personnels.

## 6. Où chercher en priorité

**Concurrence et cycle de vie SwiftUI** — c'est là que sont venus tous les vrais
bugs. Regarde `ScheduleScreen` (`.task(id:)`, `onChange`, `scenePhase`, la boucle
de sondage de 120 s), `WeekStrip` (deux `onChange` qui s'écrivent mutuellement via
`selection` et `visibleWeek` — cherche une boucle ou une course), `AppModel.start()`
et l'ordre entre `activate`, `validate` et `refreshReferential`.

**Actors du Kit** — `ReferentialLoader` et `ScheduleStore` gèrent des tâches en vol
(`inFlight`) avec réentrance. Vérifie que l'annulation, les `defer` et les
réponses tardives ne peuvent pas corrompre l'état ou ressusciter une sélection
abandonnée.

**Décodage** — les modèles sont décodés avec `convertFromSnakeCase`. Cherche un
champ que l'API pourrait renvoyer `null` ou absent et qui ferait échouer tout un
tableau. `supp_tutor` a un type instable (chaîne ou objet), déjà géré.

**Géométrie de `DayTimeline`** — toute la disposition passe par `y(for:)`. Vérifie
les cas limites : cours hors amplitude, chevauchements, durée inconnue, journée
sans cours, changement d'heure d'été.

**`RoomOccupancy`** — l'expansion des salles composites est le cœur du calcul.
Cherche un cas où une salle serait annoncée libre à tort.

**Fuites de logique métier dans l'app** — tout ce qui devrait être dans le Kit et
qui a atterri dans une vue.

## 7. Ce que je veux en retour

Un rapport ordonné par gravité. Pour chaque point :

1. le fichier et la ligne ;
2. **le scénario concret** qui produit le bug — entrées, état, résultat erroné.
   Une inquiétude sans scénario n'est pas un constat ;
3. la correction proposée ;
4. ton **niveau de confiance**, en distinguant ce que tu as pu établir par la
   lecture ou par une requête à l'API de ce qui reste une hypothèse.

Sépare nettement :
- les **bugs** (comportement faux) ;
- les **risques** (ça marche, mais c'est fragile) ;
- les **remarques de qualité** (lisibilité, doublons, code mort).

Ne corrige rien sans me le dire. Si tu hésites entre deux lectures d'une
intention, demande plutôt que de deviner.

## 8. Points ouverts connus

- Le sondage de version n'a jamais pu être observé sur une vraie modification :
  l'année 2026-27 n'est pas encore générée côté serveur.
- L'instantané embarqué (`referential-snapshot.json`) est daté du 2026-08-28, donc à
  jour. Il ne contient **que le référentiel, aucun cours**, et n'est lu qu'à la
  toute première installation si le réseau ne répond pas. Bon réflexe : le
  régénérer peu avant la livraison (procédure dans `FlopEDTKit/README.md`).
- `FLOP_DEBUG_DATE=2026-03-16` et `FLOP_DEBUG_SCREEN=rooms|settings|change`
  permettent d'ouvrir l'app sur une date ou un écran donné en build DEBUG.
