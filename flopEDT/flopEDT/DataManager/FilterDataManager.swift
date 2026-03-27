import Foundation

struct ScheduledCourse: Codable {
    let id: Int
    let room: ScheduleRoom
    let startTime: Int
    let day: String
    let course: ScheduleCourse
    let tutor: String?
    let idVisio: String?
    let number: Int

    enum CodingKeys: String, CodingKey {
        case id, room, day, course, tutor, number
        case startTime = "start_time"
        case idVisio = "id_visio"
    }
}

struct ScheduleRoom: Codable {
    let id: Int
    let name: String
}

struct ScheduleCourse: Codable {
    let id: Int
    let type: String
    let roomType: String
    let week: Int
    let year: Int
    let groups: [ScheduleGroup]
    let suppTutor: [SuppTutor]
    let module: ScheduleModule
    let payModule: ScheduleModule?
    let isGraded: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, week, year, groups, module
        case roomType = "room_type"
        case suppTutor = "supp_tutor"
        case payModule = "pay_module"
        case isGraded = "is_graded"
    }
}

/// L'API renvoie les tuteurs tantôt comme String, tantôt comme objet {name: String}
struct SuppTutor: Codable {
    let name: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let stringValue = try? container.decode(String.self) {
            self.name = stringValue
        } else if let dict = try? container.decode([String: String].self),
                  let nameValue = dict["name"] {
            self.name = nameValue
        } else {
            self.name = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

struct ScheduleGroup: Codable {
    let id: Int
    let trainProg: String
    let name: String
    let isStructural: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case trainProg = "train_prog"
        case isStructural = "is_structural"
    }
}

struct ScheduleModule: Codable {
    let name: String
    let abbrev: String
    let display: ScheduleDisplay
}

struct ScheduleDisplay: Codable {
    let colorBg: String
    let colorTxt: String

    enum CodingKeys: String, CodingKey {
        case colorBg = "color_bg"
        case colorTxt = "color_txt"
    }
}

class CourseFilter {
    static func filterCourses(
        courses: [ScheduledCourse],
        trainProg: String = "",
        day: String = "",
        cmGroup: String = "",
        mainGroup: String = "",
        subGroup: String = ""
    ) -> [ScheduledCourse] {

        let outputBase = courses.filter { course in
            course.course.groups.contains { $0.trainProg == trainProg } && course.day == day
        }

        let filtered = outputBase.filter { course in
            let groupNames = course.course.groups.map { $0.name }
            let hasCM = !cmGroup.isEmpty && groupNames.contains(cmGroup)
            let hasMainGroup = !mainGroup.isEmpty && groupNames.contains(mainGroup)
            let hasSubGroup = !subGroup.isEmpty && groupNames.contains(subGroup)
            return hasCM || hasMainGroup || hasSubGroup
        }

        return Dictionary(grouping: filtered, by: { $0.id })
            .compactMap { $0.value.first }
            .sorted { $0.startTime < $1.startTime }
    }

    static func formatTime(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func getCourseDuration(courseType: String, department: String) -> Int {
        switch department {
        case "INFO": return endTimeForInfo(type: courseType)
        case "CS": return endTimeForCS(type: courseType)
        case "GIM": return endTimeForGIM(type: courseType)
        case "RT": return endTimeForRT(type: courseType)
        case "LPMA": return endTimeForLPMA(type: courseType)
        default: return 90
        }
    }

    private static func endTimeForInfo(type: String) -> Int {
        switch type {
        case "CM", "TD", "TP", "DS", "Projet": return 85
        case "QCM": return 20
        case "Conf 45": return 45
        case "Conf": return 90
        case "Conf 2h": return 120
        default: return 90
        }
    }

    private static func endTimeForCS(type: String) -> Int {
        switch type {
        case "CM", "TD", "TP", "Accueil": return 90
        case "Conférence": return 60
        default: return 90
        }
    }

    private static func endTimeForGIM(type: String) -> Int {
        switch type {
        case "CM30": return 30
        case "CM60", "CTRL60": return 60
        case "CM90", "TD90", "TP90", "CTRL90": return 90
        case "CM180", "TD180", "TP180": return 180
        case "CM270", "TD270", "TP270": return 270
        default: return 90
        }
    }

    private static func endTimeForRT(type: String) -> Int {
        switch type {
        case "CM30", "TP60", "TD60", "CM60": return type.contains("30") ? 30 : 60
        case "CM", "TD", "CMHi5", "TP90", "Examen": return 90
        case "CM120", "ExamTP120", "TD120", "TP120": return 120
        case "TP150": return 150
        case "CM180", "TD180", "TP180": return 180
        case "CM240", "TD240", "TP240", "ExamTP240": return 240
        case "Exam45": return 45
        default: return 90
        }
    }

    private static func endTimeForLPMA(type: String) -> Int {
        switch type {
        case "CM30", "TP30": return 30
        case "CM60", "TD60", "TP60": return 60
        case "CM90", "TD90", "TP90": return 90
        case "CM120", "TD120", "TP120": return 120
        case "CM180", "TD180", "TP180": return 180
        case "CM240", "TD240", "TP240": return 240
        default: return 90
        }
    }
}
