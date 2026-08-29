import SwiftUI
import FlopEDTKit

/// La journée en grille horaire.
///
/// Toute la géométrie passe par ``y(for:)``. La v1 compensait des désalignements
/// avec deux constantes différentes — `+19.5` pour la ligne d'heure courante,
/// `+23.5` pour les blocs de cours — parce que la grille était un empilement de
/// lignes de hauteur fixe dont l'origine ne coïncidait pas avec celle des blocs.
/// Ici, traits horaires, cours et ligne d'heure courante lisent la même fonction :
/// il n'y a plus rien à compenser.
///
/// L'amplitude vient de `/base/timesettings/`, et non des 8h–20h codés en dur de
/// la v1 : les départements diffèrent réellement, et un cours placé en dehors
/// élargit la plage plutôt que d'être tronqué.
struct DayTimeline: View {
    let date: Date
    let courses: [ScheduledCourse]
    let durations: [String: Int]
    let settings: TimeSettings
    let isToday: Bool

    private let hourHeight: CGFloat = 64
    private let gutter: CGFloat = 52

    /// Début de la grille, à l'heure pleine précédant le premier événement.
    private var startMinute: Int {
        let earliest = min(settings.dayStartTime, courses.map(\.startTime).min() ?? .max)
        return (earliest / 60) * 60
    }

    /// Fin de la grille, à l'heure pleine suivant le dernier événement.
    private var endMinute: Int {
        let latest = max(
            settings.dayFinishTime,
            courses.map { $0.endTime(using: durations) }.max() ?? .min
        )
        return Int((Double(latest) / 60).rounded(.up)) * 60
    }

    private var hours: [Int] {
        stride(from: startMinute, through: endMinute, by: 60).map { $0 }
    }

    /// L'unique conversion minute → position verticale.
    private func y(for minute: Int) -> CGFloat {
        CGFloat(minute - startMinute) / 60 * hourHeight
    }

    private var totalHeight: CGFloat { y(for: endMinute) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    scrollAnchors
                    grid
                    courseBlocks
                    if isToday { currentTimeLine }
                }
                .frame(height: totalHeight + hourHeight / 2, alignment: .top)
                .padding(.horizontal, 16)
                // De quoi loger le premier libellé horaire, centré sur son
                // trait et donc à cheval sur le haut de la zone.
                .padding(.top, 12)
            }
            // `onAppear` ne se déclenchait qu'une fois : la vue garde son
            // identité quand seule `date` change, donc passer d'une journée qui
            // commence à 8h à une autre qui commence à 14h laissait la grille
            // là où elle était.
            .onChange(of: date, initial: true) { _, _ in
                scrollToRelevantHour(proxy)
            }
        }
    }

    // MARK: Grille

    /// Les cibles de défilement, invisibles mais **réellement disposées**.
    ///
    /// Les traits horaires ne peuvent pas servir d'ancres : ils sont positionnés
    /// par `.offset`, qui déplace le rendu sans déplacer la vue pour la mise en
    /// page. Aux yeux de `ScrollViewProxy`, les douze traits occupent donc tous
    /// le même point, en haut de la grille — `scrollTo` n'avait aucun moyen de
    /// distinguer 9h de 17h. Cette colonne, elle, empile de vraies lignes d'une
    /// heure : le haut de la n-ième coïncide exactement avec `y(for:)`.
    private var scrollAnchors: some View {
        VStack(spacing: 0) {
            ForEach(hours, id: \.self) { minute in
                Color.clear
                    .frame(height: hourHeight)
                    .id("hour-\(minute)")
            }
        }
        .frame(height: totalHeight, alignment: .top)
        .allowsHitTesting(false)
    }

    private var grid: some View {
        ForEach(hours, id: \.self) { minute in
            HStack(alignment: .center, spacing: 8) {
                Text(minute.asClockTime)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: gutter - 8, alignment: .trailing)

                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 0.5)
            }
            // Centré sur le trait : le libellé est à la même hauteur que sa ligne.
            .offset(y: y(for: minute))
            .frame(height: 0, alignment: .center)
        }
    }

    // MARK: Cours

    private var courseBlocks: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - gutter
            ForEach(layout(), id: \.course.id) { placement in
                let columnWidth = (width - CGFloat(placement.columns - 1) * 4) / CGFloat(placement.columns)
                CourseCard(
                    course: placement.course,
                    duration: placement.course.duration(using: durations),
                    height: max(28, y(for: placement.course.endTime(using: durations)) - y(for: placement.course.startTime))
                )
                .frame(width: columnWidth, alignment: .topLeading)
                .offset(
                    x: gutter + CGFloat(placement.column) * (columnWidth + 4),
                    y: y(for: placement.course.startTime)
                )
            }
        }
    }

    /// Répartit les cours qui se chevauchent en colonnes.
    ///
    /// Deux cours au même créneau existent : un CM de promo et un TD de groupe
    /// peuvent entrer en conflit dans un emploi du temps en cours de retouche.
    /// La v1 les superposait, rendant l'un des deux invisible.
    private struct Placement {
        let course: ScheduledCourse
        let column: Int
        let columns: Int
    }

    private func layout() -> [Placement] {
        let sorted = courses.sorted { $0.startTime < $1.startTime }
        var lanes: [Int] = []          // fin du dernier cours de chaque colonne
        var assignment: [(ScheduledCourse, Int)] = []

        for course in sorted {
            let end = course.endTime(using: durations)
            if let free = lanes.firstIndex(where: { $0 <= course.startTime }) {
                lanes[free] = end
                assignment.append((course, free))
            } else {
                lanes.append(end)
                assignment.append((course, lanes.count - 1))
            }
        }

        // Le nombre de colonnes est celui du groupe de chevauchement le plus
        // large ; on l'applique à tous pour garder des largeurs cohérentes.
        let columns = max(1, assignment.map(\.1).max().map { $0 + 1 } ?? 1)
        return assignment.map { Placement(course: $0.0, column: $0.1, columns: columns) }
    }

    // MARK: Heure courante

    private var currentTimeLine: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let minute = FlopCalendar.minutesSinceMidnight(of: context.date)
            if minute >= startMinute && minute <= endMinute {
                HStack(spacing: 0) {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .offset(x: gutter - 3.5)
                    Rectangle()
                        .fill(.red)
                        .frame(height: 1.5)
                        .offset(x: gutter - 3.5)
                }
                .offset(y: y(for: minute))
                .frame(height: 0, alignment: .center)
            }
        }
    }

    private func scrollToRelevantHour(_ proxy: ScrollViewProxy) {
        // Aujourd'hui : l'heure courante. Un autre jour : le premier cours.
        let target: Int
        if isToday {
            target = FlopCalendar.minutesSinceMidnight(of: .now)
        } else if let first = courses.map(\.startTime).min() {
            target = first
        } else {
            return
        }
        // Une heure de contexte au-dessus. Si la cible est déjà la première
        // heure de la grille, on ne défile pas : ancrer en haut rognerait le
        // libellé, qui est centré sur son trait et déborde donc vers le haut.
        let hour = ((target / 60) * 60) - 60
        guard hour > startMinute else { return }
        proxy.scrollTo("hour-\(hour)", anchor: .top)
    }
}

// MARK: - Carte de cours

private struct CourseCard: View {
    let course: ScheduledCourse
    let duration: Int
    let height: CGFloat

    private var accent: Color {
        Color(hex: course.course.module.display.colorBg) ?? .accentColor
    }

    /// En dessous d'environ une heure, il n'y a plus la place pour trois lignes.
    private var isCompact: Bool { height < 60 }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(course.course.module.abbrev)
                        .font(.footnote.weight(.semibold))
                    Text(course.course.type)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    if course.course.isGraded {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                    }
                }
                .lineLimit(1)

                if isCompact {
                    Text("\(course.startTime.asClockTime) • \(course.room.name)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("\(course.startTime.asClockTime) – \((course.startTime + duration).asClockTime)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text(course.room.name)
                        if let tutor = course.tutor, !tutor.isEmpty {
                            Text("•")
                            Text(tutor)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height, alignment: .topLeading)
        // Fond opaque : sinon les traits horaires se voient au travers et
        // barrent le texte de la carte.
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .overlay { RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.14)) }
        }
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
