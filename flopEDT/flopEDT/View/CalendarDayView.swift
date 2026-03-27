import SwiftUI

struct CalendarDayView: View {
    let day: Date
    let courses: [ScheduledCourse]
    let departement: String
    let isToday: Bool
    let isLoadingCourses: Bool
    var onRefresh: (() async -> Void)?

    private let hourHeight: CGFloat = 60
    private let startHour = 8
    private let endHour = 20

    private var totalHours: Int {
        endHour - startHour + 1
    }

    private var timelineHeight: CGFloat {
        CGFloat(totalHours) * hourHeight
    }

    private func currentTimeMinutes(for date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    private func currentTimePosition(for date: Date) -> CGFloat {
        // +19.5 compense le décalage entre la grille horaire et le positionnement réel
        CGFloat(currentTimeMinutes(for: date) - (startHour * 60)) + 19.5
    }

    private func isCurrentTimeInRange(for date: Date) -> Bool {
        let currentHour = currentTimeMinutes(for: date) / 60
        return currentHour >= startHour && currentHour < endHour
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            TimelineGrid(proxy: proxy)

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

                            if isToday && isCurrentTimeInRange(for: context.date) {
                                CurrentTimeLine(position: currentTimePosition(for: context.date))
                            }
                        }
                        .frame(height: timelineHeight)
                    }
                    .refreshable {
                        await onRefresh?()
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        // Attendre la fin de l'animation du spinner avant de scroller
                        if isToday {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                scrollToCurrentTime(proxy: proxy)
                            }
                        }
                    }
                    .onAppear {
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

    private func scrollToCurrentTime(proxy: ScrollViewProxy) {
        let currentHour = currentTimeMinutes(for: Date()) / 60
        let targetHour: Int
        if currentHour < startHour {
            targetHour = startHour
        } else if currentHour >= endHour {
            targetHour = endHour - 1
        } else {
            // Scroll une heure au-dessus pour donner du contexte visuel
            targetHour = max(startHour, currentHour - 1)
        }
        withAnimation(.easeOut(duration: 0.5)) {
            proxy.scrollTo("hour-\(targetHour)", anchor: .top)
        }
    }

    @ViewBuilder
    func TimelineGrid(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<totalHours, id: \.self) { index in
                let hour = startHour + index
                HStack(alignment: .top, spacing: 0) {
                    Text(String(format: "%02d:00", hour))
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .frame(width: 50, alignment: .trailing)
                        .padding(.trailing, 8)
                        .offset(y: -7)

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

struct CourseBlock: View {
    let course: ScheduledCourse
    let departement: String
    let hourHeight: CGFloat
    let startHour: Int

    private var yPosition: CGFloat {
        // +23.5 compense le décalage entre la grille et le positionnement des blocs
        let startHourInMinutes = startHour * 60
        return CGFloat(course.startTime - startHourInMinutes) + 23.5
    }

    private var blockHeight: CGFloat {
        CGFloat(CourseFilter.getCourseDuration(courseType: course.course.type, department: departement))
    }

    private var backgroundColor: Color {
        Color(hex: course.course.module.display.colorBg) ?? Color.blue
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 14, height: 14)
                    .padding(.top, 1.75)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(course.course.module.abbrev)
                            .font(.system(size: 15, weight: .bold))
                        Text("-")
                            .font(.system(size: 15, weight: .bold))
                        Text(course.course.type)
                            .font(.system(size: 15, weight: .bold))

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

                    // Layout adaptatif : vertical si assez de place, horizontal sinon
                    if blockHeight > 70 {
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

struct CurrentTimeLine: View {
    let position: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .padding(.leading, 46)

            Rectangle()
                .fill(.red)
                .frame(height: 2)
                .frame(maxWidth: .infinity)
        }
        .offset(y: position)
    }
}

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

#Preview {
    let sampleCourses: [ScheduledCourse] = []

    CalendarDayView(
        day: Date(),
        courses: sampleCourses,
        departement: "INFO",
        isToday: true,
        isLoadingCourses: false
    )
}
