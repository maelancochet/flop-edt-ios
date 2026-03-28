import SwiftUI
import Combine

struct HomeView: View {
    @State private var currentWeek: [Date.Day]
    @State private var selectedDate: Date?
    @State private var weekOffset: Int
    @AppStorage(StorageKeys.showTrayView) var showTrayView: Bool = true
    @Namespace private var namespace
    @State private var cachedToday: Date = Calendar.current.startOfDay(for: .now)
    @State private var referenceMondayDate: Date = Date.getMondayOfWeek(for: .now)
    @State private var allFilteredCourses: [ScheduledCourse] = []
    @State private var isLoadingCourses: Bool = false

    // Calcul synchrone pour éviter un flash au premier rendu le weekend
    init() {
        let calendar = Calendar.current
        let now = Date.now
        let weekday = calendar.component(.weekday, from: now)
        let isWeekend = (weekday == 1 || weekday == 7)

        if isWeekend {
            let daysToMonday = weekday == 7 ? 2 : 1
            let nextMonday = calendar.date(byAdding: .day, value: daysToMonday, to: now) ?? now
            _currentWeek = State(initialValue: Date.getWeek(for: nextMonday))
            _weekOffset = State(initialValue: 1)
            _selectedDate = State(initialValue: Date.getWeek(for: nextMonday).first?.date)
        } else {
            let week = Date.getWeek(for: now)
            let today = calendar.startOfDay(for: now)
            _currentWeek = State(initialValue: week)
            _weekOffset = State(initialValue: 0)
            _selectedDate = State(initialValue: week.first(where: {
                calendar.isDate($0.date, inSameDayAs: today)
            })?.date ?? week.first?.date)
        }
    }

    // Polling toutes les 60s pour détecter le passage à minuit
    private let midnightTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    @AppStorage(StorageKeys.departement) var departementtodownload: String = ""
    @AppStorage(StorageKeys.trainprog) var trainprog: String = ""
    @AppStorage(StorageKeys.filtreCM) var filtreCM: String = ""
    @AppStorage(StorageKeys.filtreGroupe) var filtreGroupe: String = ""
    @AppStorage(StorageKeys.filtreSousGroupe) var filtreSousGroupe: String = ""

    // Snapshot des filtres pris à l'ouverture du TrayView pour ne recharger que si changement
    @State private var traySnapshot: [String] = []

    var weekTitle: String {
        let firstDayOfWeek = currentWeek.first?.date ?? .now
        let weekNumber = Calendar.current.component(.weekOfYear, from: firstDayOfWeek)
        return weekOffset == 0 ? "Cette Semaine" : "Semaine \(weekNumber)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
                .environment(\.colorScheme, .dark)

            GeometryReader { geometry in
                TabView(selection: $selectedDate) {
                    ForEach(currentWeek) { day in
                        CalendarDayView(
                            day: day.date,
                            courses: getCoursesForDay(day.date),
                            departement: departementtodownload,
                            isToday: Calendar.current.isDate(day.date, inSameDayAs: cachedToday),
                            isLoadingCourses: isLoadingCourses,
                            onRefresh: {
                                await ScheduleDataManager.shared.clearCache()
                                await loadCoursesAsync()
                            }
                        )
                        .tag(day.date as Date?)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: selectedDate) { oldValue, newValue in
                    if newValue != nil {
                        triggerHaptic(style: .rigid)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 30,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 30,
                style: .continuous
            ))
            .environment(\.colorScheme, .light)
            .ignoresSafeArea(.all, edges: .bottom)
        }
        .background(.mainBackground)
        .onReceive(midnightTimer) { now in
            let startOfToday = Calendar.current.startOfDay(for: now)
            guard startOfToday != cachedToday else { return }
            cachedToday = startOfToday

            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: now)

            if weekday == 2 && weekOffset == 0 {
                resetToCurrentWeek()
                selectedDate = currentWeek.first?.date
                loadCourses()
            }
        }
        .task {
            loadCourses()
        }
        .onChange(of: showTrayView) { oldValue, newValue in
            if oldValue == false && newValue == true {
                traySnapshot = [departementtodownload, trainprog, filtreCM, filtreGroupe, filtreSousGroupe]
            }
            if oldValue == true && newValue == false {
                let currentState = [departementtodownload, trainprog, filtreCM, filtreGroupe, filtreSousGroupe]
                guard currentState != traySnapshot else { return }
                resetToInitialWeek()
                loadCourses()
            }
        }
    }

    private func loadCourses() {
        isLoadingCourses = true
        Task {
            await loadCoursesAsync()
        }
    }

    private func loadCoursesAsync(retryCount: Int = 0) async {
        do {
            let allCourses = try await ScheduleDataManager.shared.getCoursesForWeek(
                weekOffset,
                dept: departementtodownload
            )

            var weekCourses: [ScheduledCourse] = []
            let dayMapping = ["m", "tu", "w", "th", "f"]

            for dayCode in dayMapping {
                let dayCourses = CourseFilter.filterCourses(
                    courses: allCourses,
                    trainProg: trainprog,
                    day: dayCode,
                    cmGroup: filtreCM,
                    mainGroup: filtreGroupe,
                    subGroup: filtreSousGroupe
                )
                weekCourses.append(contentsOf: dayCourses)
            }

            await MainActor.run {
                allFilteredCourses = weekCourses
                isLoadingCourses = false
            }

        } catch {
            await MainActor.run {
                isLoadingCourses = false
            }
            guard retryCount < 3 else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await loadCoursesAsync(retryCount: retryCount + 1)
        }
    }

    private func getCoursesForDay(_ date: Date) -> [ScheduledCourse] {
        let calendar = Calendar.current

        guard let mondayOfWeek = currentWeek.first?.date else {
            return []
        }

        let daysSinceMonday = calendar.dateComponents([.day], from: calendar.startOfDay(for: mondayOfWeek), to: calendar.startOfDay(for: date)).day ?? 0

        let dayCode: String
        switch daysSinceMonday {
        case 0: dayCode = "m"
        case 1: dayCode = "tu"
        case 2: dayCode = "w"
        case 3: dayCode = "th"
        case 4: dayCode = "f"
        default: return []
        }

        return allFilteredCourses
            .filter { $0.day == dayCode }
            .sorted { $0.startTime < $1.startTime }
    }

    private func resetToCurrentWeek() {
        referenceMondayDate = Date.getMondayOfWeek(for: .now)
        currentWeek = Date.getWeek(for: .now)
    }

    // Reprend la logique du init() : weekend → semaine prochaine, sinon → aujourd'hui
    private func resetToInitialWeek() {
        let calendar = Calendar.current
        let now = Date.now
        let weekday = calendar.component(.weekday, from: now)
        let isWeekend = (weekday == 1 || weekday == 7)

        referenceMondayDate = Date.getMondayOfWeek(for: now)

        if isWeekend {
            let daysToMonday = weekday == 7 ? 2 : 1
            let nextMonday = calendar.date(byAdding: .day, value: daysToMonday, to: now) ?? now
            currentWeek = Date.getWeek(for: nextMonday)
            weekOffset = 1
            selectedDate = currentWeek.first?.date
        } else {
            currentWeek = Date.getWeek(for: now)
            weekOffset = 0
            let today = calendar.startOfDay(for: now)
            selectedDate = currentWeek.first(where: {
                calendar.isDate($0.date, inSameDayAs: today)
            })?.date ?? currentWeek.first?.date
        }
    }

    private func changeWeek(by offset: Int) {
        isLoadingCourses = true
        weekOffset += offset

        let calendar = Calendar.current

        if let targetMonday = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: referenceMondayDate) {
            withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                currentWeek = Date.getWeek(for: targetMonday)
                if weekOffset == 0 {
                    let today = calendar.startOfDay(for: .now)
                    selectedDate = currentWeek.first(where: {
                        calendar.isDate($0.date, inSameDayAs: today)
                    })?.date ?? currentWeek.first?.date
                } else {
                    selectedDate = currentWeek.first?.date
                }
            }
        }

        Task {
            // Court délai pour laisser l'animation de changement de semaine démarrer
            try? await Task.sleep(nanoseconds: 10_000_000)
            await loadCoursesAsync()
        }
    }

    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    @ViewBuilder
    func HeaderView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderTopBar(
                weekTitle: weekTitle,
                weekOffset: weekOffset,
                showTrayView: $showTrayView,
                onTrayToggle: { triggerHaptic() }
            )

            WeekNavigator(
                currentWeek: currentWeek,
                selectedDate: $selectedDate,
                namespace: namespace,
                cachedToday: cachedToday,
                onWeekChange: { offset in
                    changeWeek(by: offset)
                    triggerHaptic()
                },
                onDateSelect: { triggerHaptic(style: .rigid) }
            )

            MonthYearDisplay(selectedDate: selectedDate)
        }
        .padding([.horizontal, .top], 15)
        .padding(.bottom, 10)
    }
}

struct HeaderTopBar: View {
    let weekTitle: String
    let weekOffset: Int
    @Binding var showTrayView: Bool
    let onTrayToggle: () -> Void

    var body: some View {
        HStack {
            Text(weekTitle)
                .font(.title.bold())
                .animation(.snappy(duration: 0.3, extraBounce: 0), value: weekOffset)

            Spacer(minLength: 0)

            Button {
                showTrayView.toggle()
                onTrayToggle()
            } label: {
                Text("Changer d'EDT")
                Image(systemName: "chevron.down")
            }
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color(.systemGray2))
            .cornerRadius(12)
        }
        .sheet(isPresented: $showTrayView) {
            DynamicSheet(animation: .snappy(duration: 0.3, extraBounce: 0)) {
                TrayView(animation: .snappy(duration: 0.3, extraBounce: 0))
            }
        }
    }
}

struct WeekNavigator: View {
    let currentWeek: [Date.Day]
    @Binding var selectedDate: Date?
    let namespace: Namespace.ID
    let cachedToday: Date
    let onWeekChange: (Int) -> Void
    let onDateSelect: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            NavigationButton(systemName: "chevron.left", enabled: true, action: { onWeekChange(-1) })
            ForEach(currentWeek) { day in
                DayButton(
                    day: day,
                    selectedDate: selectedDate,
                    cachedToday: cachedToday,
                    namespace: namespace,
                    onSelect: {
                        selectedDate = day.date
                        onDateSelect()
                    }
                )
            }
            NavigationButton(systemName: "chevron.right", enabled: true, action: { onWeekChange(1) })
        }
        .frame(height: 80)
        .padding(.vertical, 5)
        .offset(y: 5)
        .gesture(
            DragGesture()
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if value.translation.width > threshold {
                        onWeekChange(-1)
                    } else if value.translation.width < -threshold {
                        onWeekChange(1)
                    }
                }
        )
    }
}

struct NavigationButton: View {
    let systemName: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .foregroundStyle(enabled ? .white : .gray.opacity(0.3))
        .font(.title3.bold())
        .frame(width: 40, height: 60)
        .disabled(!enabled)
    }
}

struct DayButton: View {
    let day: Date.Day
    let selectedDate: Date?
    let cachedToday: Date
    let namespace: Namespace.ID
    let onSelect: () -> Void

    private var isSameDate: Bool {
        guard let selectedDate = selectedDate else { return false }
        return Calendar.current.isDate(day.date, inSameDayAs: selectedDate)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(day.date.string("EEE"))
                .font(.caption)
                .foregroundStyle(.white)
                .animation(.smooth(duration: 0.3), value: isSameDate)

            Text(day.date.string("dd"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(isSameDate ? .black : .white)
                .frame(width: 38, height: 38)
                .background {
                    if isSameDate {
                        Circle()
                            .fill(.white)
                            .matchedGeometryEffect(id: "ACTIVEDATE", in: namespace)
                    }
                }
                .animation(.smooth(duration: 0.3), value: isSameDate)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture {
            onSelect()
        }
    }
}

struct MonthYearDisplay: View {
    @AppStorage(StorageKeys.departement) var departementtodownload: String = ""
    @AppStorage(StorageKeys.yearhome) var yearhome: String = ""
    @AppStorage(StorageKeys.filtreSousGroupe) var filtreSousGroupe: String = ""

    let selectedDate: Date?

    var body: some View {
        HStack {
            Text(selectedDate?.string("MMM") ?? "")
            Text(selectedDate?.string("YYYY") ?? "")

            Spacer()

            Text(departementtodownload)
            Text(yearhome)
            Text(filtreSousGroupe)
        }
        .font(.caption2)
    }
}

extension Date {
    struct Day: Identifiable {
        var id: Date { date }
        let date: Date
    }

    func string(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: self)
    }

    static func getWeek(for date: Date) -> [Date.Day] {
        let calendar = Calendar.current
        let monday = getMondayOfWeek(for: date)
        let startOfMonday = calendar.startOfDay(for: monday)
        return (0..<5).compactMap { i in
            calendar.date(byAdding: .day, value: i, to: startOfMonday).map { Date.Day(date: $0) }
        }
    }

    // weekday Apple : 1=dimanche, 2=lundi, ..., 7=samedi
    // nonisolated pour être appelable depuis n'importe quel actor (pur calcul, pas de UI)
    nonisolated static func getMondayOfWeek(for date: Date) -> Date {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)

        let daysToSubtract: Int
        switch weekday {
        case 2: daysToSubtract = 0
        case 3: daysToSubtract = 1
        case 4: daysToSubtract = 2
        case 5: daysToSubtract = 3
        case 6: daysToSubtract = 4
        case 7: daysToSubtract = 5
        case 1: daysToSubtract = 6
        default: daysToSubtract = 0
        }

        guard let monday = calendar.date(byAdding: .day, value: -daysToSubtract, to: date) else {
            return date
        }

        return calendar.startOfDay(for: monday)
    }
}

#Preview {
    HomeView()
}
