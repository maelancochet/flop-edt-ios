import SwiftUI
import Combine

struct HomeView: View {
    // MARK: - State Properties
    
    @State private var currentWeek: [Date.Day] = Date.getWeek(for: .now)
    @State private var selectedDate: Date?
    @State private var weekOffset: Int = 0
    @AppStorage(StorageKeys.showTrayView) var showTrayView: Bool = true
    @Namespace private var namespace
    @State private var cachedToday: Date = Calendar.current.startOfDay(for: .now)
    @State private var referenceMondayDate: Date = Date.getMondayOfWeek(for: .now)
    @State private var allFilteredCourses: [ScheduledCourse] = []
    @State private var isLoadingCourses: Bool = false

    // MARK: - Timers & Publishers
    
    /// Timer to detect midnight transitions for automatic date updates
    private let midnightTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    // MARK: - Filter Settings
    
    @AppStorage(StorageKeys.departement) var departementtodownload: String = ""
    @AppStorage(StorageKeys.trainprog) var trainprog: String = ""
    @AppStorage(StorageKeys.filtreCM) var filtreCM: String = ""
    @AppStorage(StorageKeys.filtreGroupe) var filtreGroupe: String = ""
    @AppStorage(StorageKeys.filtreSousGroupe) var filtreSousGroupe: String = ""

    // MARK: - Tray Snapshot (pour détecter les changements)

    @State private var traySnapshot: [String] = []

    // MARK: - Computed Properties

    /// Generates the week title displayed in the header.
    var weekTitle: String {
        let firstDayOfWeek = currentWeek.first?.date ?? .now
        let weekNumber = Calendar.current.component(.weekOfYear, from: firstDayOfWeek)

        if weekOffset == 0 {
            return "Cette Semaine"
        } else {
            return "Semaine \(weekNumber)"
        }
    }

    // MARK: - Body
    
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

            // Lundi : nouvelle semaine, rafraîchir si on est sur la semaine courante
            if weekday == 2 && weekOffset == 0 {
                resetToCurrentWeek()
                selectedDate = currentWeek.first?.date
                loadCourses()
            }
        }
        .task {
            guard selectedDate == nil else { return }
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: Date.now)
            let isWeekend = (weekday == 1 || weekday == 7)

            if isWeekend {
                // Weekend : avancer à la semaine prochaine et sélectionner lundi
                guard let nextMonday = calendar.date(byAdding: .day, value: weekday == 7 ? 2 : 1, to: Date.now) else { return }
                referenceMondayDate = Date.getMondayOfWeek(for: .now)
                currentWeek = Date.getWeek(for: nextMonday)
                weekOffset = 1
                selectedDate = currentWeek.first?.date
            } else {
                resetToCurrentWeek()
                let today = calendar.startOfDay(for: .now)
                selectedDate = currentWeek.first(where: {
                    calendar.isDate($0.date, inSameDayAs: today)
                })?.date ?? currentWeek.first?.date
            }
            loadCourses()
        }
        .onChange(of: showTrayView) { oldValue, newValue in
            if oldValue == false && newValue == true {
                // Ouverture : sauvegarder l'état actuel des filtres
                traySnapshot = [departementtodownload, trainprog, filtreCM, filtreGroupe, filtreSousGroupe]
            }
            if oldValue == true && newValue == false {
                let currentState = [departementtodownload, trainprog, filtreCM, filtreGroupe, filtreSousGroupe]
                // Recharger uniquement si les filtres ont changé
                if currentState != traySnapshot {
                    Task { await ScheduleDataManager.shared.clearCache() }
                    resetToCurrentWeek()
                    weekOffset = 0
                    let calendar = Calendar.current
                    let today = calendar.startOfDay(for: .now)
                    selectedDate = currentWeek.first(where: {
                        calendar.isDate($0.date, inSameDayAs: today)
                    })?.date ?? currentWeek.first?.date
                    loadCourses()
                }
            }
        }
    }
    
    // MARK: - Data Loading
    
    /// Loads and filters courses from cache for the currently displayed week
    private func loadCourses() {
        isLoadingCourses = true
        Task {
            await loadCoursesAsync()
        }
    }
    
    /// Version async de loadCourses pour éviter les conflits d'animation
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
            
            // Mise à jour sans animation pour éviter les sauts
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
    
    /// Retrieves courses scheduled for a specific date
    /// - Parameter date: The date to filter courses for
    /// - Returns: Array of scheduled courses for that day, sorted by start time
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
        default:
            return []
        }
        
        let coursesForDay = allFilteredCourses.filter { $0.day == dayCode }
            .sorted { $0.startTime < $1.startTime }
        
        return coursesForDay
    }
    
    // MARK: - Helper Methods

    /// Recalcule la semaine courante
    private func resetToCurrentWeek() {
        referenceMondayDate = Date.getMondayOfWeek(for: .now)
        currentWeek = Date.getWeek(for: .now)
    }

    /// Formats a date for debugging purposes
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE dd/MM"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date)
    }

    /// Navigates to a different week relative to the current week
    /// - Parameter offset: Number of weeks to move (positive for future, negative for past)
    private func changeWeek(by offset: Int) {
        isLoadingCourses = true
        weekOffset += offset

        let calendar = Calendar.current

        if let targetMonday = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: referenceMondayDate) {
            withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                currentWeek = Date.getWeek(for: targetMonday)
                // Si on revient sur la semaine courante, sélectionner aujourd'hui
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
            try? await Task.sleep(nanoseconds: 10_000_000)
            await loadCoursesAsync()
        }
    }

    /// Triggers haptic feedback for user interactions
    /// - Parameter style: The intensity style of the haptic feedback
    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    // MARK: - View Components
    
    /// Constructs the header section of the view
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

// MARK: - Supporting Views

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

// MARK: - Date Extensions

extension Date {
    /// A simple wrapper holding a date, used to represent a single day in a week.
    struct Day: Identifiable {
        var id: Date { date }
        let date: Date
    }

    /// Formats the date using the given format string with French locale.
    func string(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: self)
    }

    /// Generates a week array (Monday through Friday) for the week containing the given date
    /// - Parameter date: The reference date
    /// - Returns: Array of 5 weekdays (Monday through Friday)
    static func getWeek(for date: Date) -> [Date.Day] {
        let calendar = Calendar.current
        let monday = getMondayOfWeek(for: date)
        let startOfMonday = calendar.startOfDay(for: monday)
        return (0..<5).compactMap { i in
            calendar.date(byAdding: .day, value: i, to: startOfMonday).map { Date.Day(date: $0) }
        }
    }
    
    /// Returns the Monday of the week containing the given date
    /// - Parameter date: The reference date
    /// - Returns: The Monday of that week at start of day
    static func getMondayOfWeek(for date: Date) -> Date {
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
