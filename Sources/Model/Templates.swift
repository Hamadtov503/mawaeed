import Foundation

/// Ready-made starting points with sensible reminder defaults.
struct Template: Identifiable {
    let id: String
    let name: String
    let icon: String
    let category: Category
    var hasTime = false
    var daysAhead = 30
    var hour = 10
    var repeatUnit: RepeatUnit = .none
    var repeatEvery = 1
    var reminders: [Int] = [1440]
    var warrantyMonths: Int? = nil
    var notes = ""

    func makeItem(now: Date = Date()) -> Item {
        var it = Item()
        it.title = id == "blank" ? "" : name
        it.category = category
        it.icon = id == "blank" ? nil : icon
        it.hasTime = hasTime
        let cal = Fmt.greg
        let day = cal.date(byAdding: .day, value: daysAhead, to: cal.startOfDay(for: now)) ?? now
        it.date = hasTime ? (cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day) : day
        it.repeatUnit = repeatUnit
        it.repeatEvery = repeatEvery
        it.reminders = reminders
        it.notes = notes
        if let m = warrantyMonths {
            it.purchaseDate = cal.startOfDay(for: now)
            it.warrantyMonths = m
            it.date = it.warrantyEnd ?? it.date
        }
        return it
    }
}

struct TemplateGroup: Identifiable {
    let id: String
    let title: String
    let templates: [Template]
}

extension Template {
    static let groups: [TemplateGroup] = [
        TemplateGroup(id: "appts", title: "مواعيد ومهام", templates: [
            Template(id: "appt", name: "موعد", icon: "calendar.badge.clock", category: .appointment,
                     hasTime: true, daysAhead: 1, reminders: [1440, 60]),
            Template(id: "doctor", name: "موعد مستشفى", icon: "stethoscope", category: .appointment,
                     hasTime: true, daysAhead: 1, hour: 9, reminders: [1440, 120],
                     notes: "خذ معك: الهوية، التأمين، التقارير السابقة"),
            Template(id: "task", name: "مهمة", icon: "checklist", category: .task,
                     daysAhead: 0, reminders: [0]),
            Template(id: "visit", name: "مراجعة جهة حكومية", icon: "building.columns.fill", category: .appointment,
                     hasTime: true, daysAhead: 1, hour: 8, reminders: [1440, 60],
                     notes: "جهّز الأوراق المطلوبة"),
        ]),
        TemplateGroup(id: "docs", title: "وثائق وتجديدات", templates: [
            Template(id: "istimara", name: "استمارة السيارة", icon: "car.fill", category: .document,
                     daysAhead: 60, repeatUnit: .year, reminders: [43200, 10080, 1440]),
            Template(id: "license", name: "رخصة القيادة", icon: "person.crop.rectangle", category: .document,
                     daysAhead: 90, reminders: [86400, 43200, 10080]),
            Template(id: "id", name: "الهوية الوطنية", icon: "person.text.rectangle", category: .document,
                     daysAhead: 180, reminders: [86400, 43200, 10080]),
            Template(id: "passport", name: "جواز السفر", icon: "airplane", category: .document,
                     daysAhead: 365, reminders: [259200, 86400, 43200],
                     notes: "كثير من الدول تشترط أن يكون الجواز صالح 6 أشهر على الأقل وقت السفر."),
            Template(id: "insurance", name: "تأمين السيارة", icon: "shield.fill", category: .document,
                     daysAhead: 90, repeatUnit: .year, reminders: [43200, 10080, 1440]),
            Template(id: "fahs", name: "الفحص الدوري", icon: "gauge", category: .document,
                     daysAhead: 90, repeatUnit: .year, reminders: [43200, 10080]),
        ]),
        TemplateGroup(id: "subs", title: "اشتراكات وفواتير", templates: [
            Template(id: "data", name: "باقة النت / الجوال", icon: "wifi", category: .subscription,
                     daysAhead: 30, repeatUnit: .month, reminders: [4320, 1440]),
            Template(id: "sub", name: "اشتراك (تطبيق / منصة)", icon: "play.rectangle.fill", category: .subscription,
                     daysAhead: 30, repeatUnit: .month, reminders: [2880],
                     notes: "لو ما تستخدمه، ألغِه قبل التجديد."),
            Template(id: "bill", name: "فاتورة", icon: "doc.plaintext", category: .bill,
                     daysAhead: 30, repeatUnit: .month, reminders: [4320, 1440]),
            Template(id: "rent", name: "إيجار / قسط", icon: "house.fill", category: .bill,
                     daysAhead: 30, repeatUnit: .month, reminders: [10080, 1440]),
        ]),
        TemplateGroup(id: "care", title: "ضمان وصيانة", templates: [
            Template(id: "warranty", name: "ضمان جهاز", icon: "checkmark.shield.fill", category: .warranty,
                     reminders: [43200, 10080], warrantyMonths: 24,
                     notes: "صوّر الفاتورة وأرفقها هنا."),
            Template(id: "oil", name: "تغيير زيت السيارة", icon: "drop.fill", category: .maintenance,
                     daysAhead: 90, repeatUnit: .month, repeatEvery: 3, reminders: [10080, 1440]),
            Template(id: "ac", name: "صيانة المكيفات", icon: "snowflake", category: .maintenance,
                     daysAhead: 60, repeatUnit: .month, repeatEvery: 6, reminders: [10080]),
            Template(id: "blank", name: "عنصر فارغ", icon: "plus", category: .other,
                     daysAhead: 7, reminders: [1440]),
        ]),
    ]
}
