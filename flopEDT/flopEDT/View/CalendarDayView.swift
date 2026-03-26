import SwiftUI

/// Vue d'une journée complète avec grille horaire de 0h à 24h
/// Affiche les cours positionnés proportionnellement à leur horaire et durée
struct CalendarDayView: View {
    // MARK: - Properties

    let day: Date
    let courses: [ScheduledCourse]
    let departement: String
    let isToday: Bool
    let isLoadingCourses: Bool
    var onRefresh: (() async -> Void)?

    // MARK: - Constants

    /// Hauteur d'une heure en points (60 minutes = 60 points)
    private let hourHeight: CGFloat = 60

    /// Heure de début de la journée affichée (8h)
    private let startHour = 8

    /// Heure de fin de la journée affichée (20h)
    private let endHour = 20

    /// Nombre total d'heures affichées (8h à 20h = 13 heures)
    private var totalHours: Int {
        endHour - startHour + 1
    }

    // MARK: - Computed Properties

    /// Hauteur totale de la timeline (24 heures)
    private var timelineHeight: CGFloat {
        CGFloat(totalHours) * hourHeight
    }

    /// Heure actuelle en minutes depuis minuit
    private func currentTimeMinutes(for date: Date) -> Int {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return hour * 60 + minute
    }

    /// Position Y du trait rouge (heure actuelle) relatif au début de la timeline (8h)
    private func currentTimePosition(for date: Date) -> CGFloat {
        let minutesSinceStart = currentTimeMinutes(for: date) - (startHour * 60)
        return CGFloat(minutesSinceStart) + 19.5
    }

    /// Indique si l'heure actuelle est dans la plage affichée (8h-20h)
    private func isCurrentTimeInRange(for date: Date) -> Bool {
        let currentHour = currentTimeMinutes(for: date) / 60
        return currentHour >= startHour && currentHour < endHour
    }

    // MARK: - Body

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            // Grille horaire de fond avec ancres pour le scroll
                            TimelineGrid(proxy: proxy)

                            // Cours positionnés sur la timeline
                            if !isLoadingCourses {
                                ForEach(courses, id: \.id) { course in
                                    CourseBlock(
                                        course: course,
                                        departement: departement,
                                        hourHeight: hourHeight,
                                        startHour: startHour
                                    )
                                }
                            }

                            // Indicateur de chargement
                            if isLoadingCourses {
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .scaleEffect(1.5)
                                            .tint(.gray)
                                        Spacer()
                                    }
                                    Spacer()
                                }
                            }

                            // Trait rouge pour l'heure actuelle (uniquement aujourd'hui et si dans la plage 8h-20h)
                            if isToday && isCurrentTimeInRange(for: context.date) {
                                CurrentTimeLine(position: currentTimePosition(for: context.date))
                            }
                        }
                        .frame(height: timelineHeight)
                    }
                    .refreshable {
                        await onRefresh?()
                        // Vibration immédiate dès que les données sont chargées
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        // Scroll après la fin de l'animation du spinner
                        if isToday {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                scrollToCurrentTime(proxy: proxy)
                            }
                        }
                    }
                    .onAppear {
                        // Auto-scroll sur l'heure actuelle si c'est aujourd'hui
                        if isToday {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                scrollToCurrentTime(proxy: proxy)
                            }
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Timeline Grid

    /// Scroll animé vers l'heure actuelle sur la timeline
    private func scrollToCurrentTime(proxy: ScrollViewProxy) {
        let currentHour = currentTimeMinutes(for: Date()) / 60
        let targetHour: Int
        if currentHour < startHour {
            targetHour = startHour
        } else if currentHour >= endHour {
            targetHour = endHour - 1
        } else {
            targetHour = max(startHour, currentHour - 1)
        }
        withAnimation(.easeOut(duration: 0.5)) {
            proxy.scrollTo("hour-\(targetHour)", anchor: .top)
        }
    }

    /// Grille horaire avec lignes et labels d'heures
    @ViewBuilder
    func TimelineGrid(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<totalHours, id: \.self) { index in
                let hour = startHour + index
                HStack(alignment: .top, spacing: 0) {
                    // Label de l'heure
                    Text(String(format: "%02d:00", hour))
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .frame(width: 50, alignment: .trailing)
                        .padding(.trailing, 8)
                        .offset(y: -7)

                    // Ligne horizontale
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: hourHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("hour-\(hour)")
            }
        }
    }
}

// MARK: - Course Block

/// Bloc représentant un cours sur la timeline
struct CourseBlock: View {
    let course: ScheduledCourse
    let departement: String
    let hourHeight: CGFloat
    let startHour: Int

    // MARK: - Computed Properties

    /// Position Y du cours (en fonction de startTime)
    private var yPosition: CGFloat {
        // Calcul: startTime en minutes converti en position Y relative à startHour (8h)
        // Formule: (minutes depuis startHour) * (points par minute)
        // Avec hourHeight = 60 points par heure, on a 1 point par minute
        let startHourInMinutes = startHour * 60
        let basePosition = CGFloat(course.startTime - startHourInMinutes) // Position relative à 8h

        // Correction empirique: +23.5 points pour compenser un décalage
        return basePosition + 23.5
        
    }

    /// Hauteur du bloc (en fonction de la durée)
    private var blockHeight: CGFloat {
        let duration = CourseFilter.getCourseDuration(courseType: course.course.type, department: departement)
        // Avec hourHeight = 60 et 1 point par minute, la durée en minutes = hauteur en points
        return CGFloat(duration)
    }

    /// Couleur de fond du cours
    private var backgroundColor: Color {
        Color(hex: course.course.module.display.colorBg) ?? Color.blue
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 12) {
                // Point coloré à gauche (aligné en haut)
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 14, height: 14)
                    .padding(.top, 1.75)

                VStack(alignment: .leading, spacing: 4) {
                    // En-tête : Module + Type + Badge Noté
                    HStack(spacing: 4) {
                        Text(course.course.module.abbrev)
                            .font(.system(size: 15, weight: .bold))
                        Text("-")
                            .font(.system(size: 15, weight: .bold))
                        Text(course.course.type)
                            .font(.system(size: 15, weight: .bold))

                        // Badge "Noté" si le cours est noté
                        if course.course.isGraded {
                            Text("Noté")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 3)
                                .background(backgroundColor)
                                .cornerRadius(6)
                        }
                    }
                    .lineLimit(1)

                    // Horaire + Salle/Tuteur (responsive selon hauteur)
                    if blockHeight > 70 {
                        // Assez d'espace : affichage vertical
                        Text("\(CourseFilter.formatTime(course.startTime)) - \(CourseFilter.formatTime(course.startTime + CourseFilter.getCourseDuration(courseType: course.course.type, department: departement)))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            Text(course.room.name)
                            Text("•")
                            Text(course.tutor ?? "Non assigné")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    } else {
                        // Peu d'espace : affichage horizontal compact
                        HStack(spacing: 4) {
                            Text("\(CourseFilter.formatTime(course.startTime)) - \(CourseFilter.formatTime(course.startTime + CourseFilter.getCourseDuration(courseType: course.course.type, department: departement)))")
                            Text("/")
                            Text(course.room.name)
                            Text("•")
                            Text(course.tutor ?? "N/A")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }

                Spacer()
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: geometry.size.width - 66, height: blockHeight, alignment: .topLeading)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
            )
            .position(
                x: (geometry.size.width - 66) / 2 + 58,
                y: yPosition + blockHeight / 2
            )
        }
    }
}

// MARK: - Current Time Line

/// Trait rouge indiquant l'heure actuelle
struct CurrentTimeLine: View {
    let position: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // Petit cercle à gauche
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .padding(.leading, 46)

            // Ligne rouge qui s'étend jusqu'au bord droit
            Rectangle()
                .fill(.red)
                .frame(height: 2)
                .frame(maxWidth: .infinity)
        }
        .offset(y: position)
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0

        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }

        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

#Preview {
    let sampleCourses: [ScheduledCourse] = [
        // Ces données sont des exemples pour le preview
    ]

    CalendarDayView(
        day: Date(),
        courses: sampleCourses,
        departement: "INFO",
        isToday: true,
        isLoadingCourses: false
    )
}
