import SwiftUI
import FlopEDTKit

/// La bande de dates horizontale, façon app Calendrier.
///
/// L'idée et l'animation viennent du composant `HorizontalCalendar` de Balaji
/// Venkatesh, mais la mécanique de défilement a été refaite : l'original gardait
/// trois semaines en mémoire et les faisait glisser à la volée, avec un verrou
/// qui pouvait rester bloqué et figer la bande pour de bon.
///
/// Ici, la liste des semaines est **fixe et ancrée une seule fois**, et la
/// pagination est celle du système. Ce point est essentiel : une propriété
/// ordinaire serait recalculée à chaque `init`, donc à chaque changement de
/// jour, ce qui reconstruirait les pages en permanence. Les vues perdraient leur
/// identité — et une transition ne s'anime pas sur une vue recréée.
///
/// Le bug d'origine sur le jour sélectionné est corrigé au passage : changer de
/// semaine retrouve le jour par son ``Weekday`` et non par une position dans un
/// tableau, ce qui ne dépend plus de la locale de l'appareil.
struct WeekStrip: View {
    @Binding var selection: Date
    /// Les jours porteurs de cours, pour la pastille sous le chiffre.
    var busyDays: (ISOWeek) -> Set<Weekday> = { _ in [] }

    /// Un an dans chaque sens : au-delà, l'emploi du temps n'existe pas côté
    /// serveur. Le style page ne construit que les semaines voisines.
    private static let radius = 52

    /// Fixés à la création et jamais recalculés, pour que l'identité des pages
    /// reste stable d'un rendu à l'autre.
    @State private var weeks: [ISOWeek]
    @State private var visibleWeek: ISOWeek
    /// La bande grandit avec la taille de texte choisie par l'utilisateur.
    ///
    /// 78 pt et non 64 : le contenu mesure environ 71 pt (libellé 16, espace 8,
    /// pastille 35, espace 8, point 4). Trop juste, le `VStack` se comprimait et
    /// le libellé du jour se retrouvait rétréci.
    @ScaledMetric(relativeTo: .body) private var stripHeight: CGFloat = 78

    init(selection: Binding<Date>, busyDays: @escaping (ISOWeek) -> Set<Weekday> = { _ in [] }) {
        self._selection = selection
        self.busyDays = busyDays
        let current = ISOWeek(containing: selection.wrappedValue)
        _weeks = State(initialValue: (-Self.radius...Self.radius).map { current.advanced(by: $0) })
        _visibleWeek = State(initialValue: current)
    }

    var body: some View {
        TabView(selection: $visibleWeek) {
            ForEach(weeks, id: \.self) { week in
                // Une seule fois par page : appelé depuis la cellule, il
                // reconstruisait l'ensemble des jours occupés sept fois, en
                // reparcourant tous les cours de la semaine à chaque rendu.
                let busy = busyDays(week)
                HStack(spacing: 0) {
                    ForEach(week.days, id: \.self) { date in
                        DayCell(
                            date: date,
                            selection: $selection,
                            hasCourses: busy.contains(Weekday(date: date)),
                            holiday: FrenchHolidays.name(on: date)
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .tag(week)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: stripHeight)
        // Sept colonnes sur une largeur d'iPhone : au-delà de cette taille, les
        // numéros de jour se tronquent en « … » et la bande devient illisible.
        // Le reste de l'app suit les tailles d'accessibilité sans limite.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .onChange(of: visibleWeek) { _, week in
            moveSelection(to: week)
        }
        .onChange(of: selection) { _, date in
            // Sélection venue d'ailleurs (bouton « Aujourd'hui ») : on amène la
            // bande sur la bonne semaine.
            let week = ISOWeek(containing: date)
            guard visibleWeek != week, weeks.contains(week) else { return }
            withAnimation(.snappy) { visibleWeek = week }
        }
    }

    /// Conserve le jour de la semaine en changeant de semaine.
    ///
    /// C'est ici que vivait le bug d'origine, qui indexait le tableau des jours
    /// avec `component(.weekday) - 1` — numéroté à partir du dimanche, alors que
    /// le tableau commence à `firstWeekday`. Les deux ne coïncident qu'aux
    /// États-Unis ; sur un iPhone français la sélection glissait d'un jour à
    /// chaque changement de semaine.
    private func moveSelection(to week: ISOWeek) {
        guard !week.contains(selection) else { return }
        if let date = week.date(of: Weekday(date: selection)) {
            selection = date
        }
    }
}

private struct DayCell: View {
    let date: Date
    /// La liaison, et non une copie.
    ///
    /// Calqué sur `CalendarLabel` : le tap est **à l'intérieur** de la vue qui
    /// porte le `.animation(value:)`, et il écrit dans la même valeur que celle
    /// observée. C'était la dernière différence de structure avec l'original.
    @Binding var selection: Date
    let hasCourses: Bool
    let holiday: String?

    @Environment(\.colorScheme) private var colorScheme
    /// La pastille suit la taille de texte, sinon le chiffre en déborde.
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 35

    var body: some View {
        let isSelected = FlopCalendar.iso.isDate(date, inSameDayAs: selection)
        let isToday = FlopCalendar.iso.isDateInToday(date)
        let isWeekend = Weekday(date: date) == .saturday || Weekday(date: date) == .sunday

        VStack(spacing: 8) {
            Text(Weekday(date: date).shortLabel)
                .font(.caption)
                .lineLimit(1)
                // Juste de quoi éviter une troncature en « sa… » aux grandes
                // tailles, sans permettre au libellé de rapetisser visiblement.
                .minimumScaleFactor(0.8)
                .foregroundStyle(isWeekend || holiday != nil ? .tertiary : .secondary)

            let foreground = colorScheme == .dark ? Color.black : Color.white
            Text("\(FlopCalendar.iso.component(.day, from: date))")
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(
                    isSelected
                    ? (isToday ? Color.white : foreground)
                    : (isToday ? Color.red : (holiday != nil || isWeekend ? Color.secondary : Color.primary))
                )
                .frame(width: badgeSize, height: badgeSize)
                .background {
                    // Le rond est rendu en permanence et c'est son échelle et son
                    // opacité qui varient, plutôt qu'une `.transition` sur une vue
                    // insérée puis retirée.
                    //
                    // Une transition ne joue que si SwiftUI voit bien une
                    // insertion dans une transaction animée, ce qui dépend de la
                    // stabilité de l'identité de la vue — et donc du conteneur.
                    // Ici la bande est un `TabView` paginé, adossé à un
                    // `UIPageViewController` qui recrée le contenu de ses pages.
                    // Une animation de propriété, elle, ne peut pas être
                    // escamotée : le rendu est le même, le déclenchement est sûr.
                    Circle()
                        // Aujourd'hui en rouge, comme l'app Calendrier.
                        .fill(isToday ? Color.red : Color.primary)
                        .scaleEffect(isSelected ? 1 : 0.5)
                        .opacity(isSelected ? 1 : 0)
                }
                .contentShape(.rect)
                .onTapGesture { selection = date }

            // Pas d'`AnyShapeStyle` ici : non équatable, il forçait SwiftUI à
            // considérer le remplissage comme modifié à chaque rendu.
            Circle()
                .fill(.tint)
                .opacity(hasCourses ? 1 : 0)
                .frame(width: 4, height: 4)
        }
        .animation(.smooth(duration: 0.3, extraBounce: 0), value: selection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(isToday: isToday))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func accessibilityLabel(isToday: Bool) -> String {
        var parts = [DateFormatter.frenchDay.string(from: date)]
        if isToday { parts.append("aujourd'hui") }
        if let holiday { parts.append(holiday) }
        if hasCourses { parts.append("cours prévus") }
        return parts.joined(separator: ", ")
    }
}
