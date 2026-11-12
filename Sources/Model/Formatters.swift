import Foundation
import SwiftUI

/// The app's language. Arabic uses Arabic-Indic digits and right-to-left; English uses Western digits.
enum AppLanguage: String, CaseIterable, Identifiable {
    case ar, en
    var id: String { rawValue }
    var title: String { self == .ar ? "العربية" : "English" }
}

/// Picks the Arabic or English text for the current app language.
func L(_ ar: String, _ en: String) -> String {
    AppSettings.shared.language == .en ? en : ar
}

/// Dates in the app's language; Gregorian is primary and the Umm al-Qura Hijri date is shown next to it.
enum Fmt {
    static var isArabic: Bool { AppSettings.shared.language == .ar }

    static var locale: Locale {
        Locale(identifier: isArabic ? "ar_SA@calendar=gregorian;numbers=arab" : "en_US@calendar=gregorian")
    }
    static var hijriLocale: Locale {
        Locale(identifier: isArabic ? "ar_SA@calendar=islamic-umalqura;numbers=arab" : "en_US@calendar=islamic-umalqura")
    }

    static let greg: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .autoupdatingCurrent
        c.firstWeekday = 1
        return c
    }()

    static let hijriCalendar: Calendar = {
        var c = Calendar(identifier: .islamicUmmAlQura)
        c.timeZone = .autoupdatingCurrent
        return c
    }()

    private static var cache: [String: DateFormatter] = [:]

    static func formatter(_ format: String, hijri: Bool = false) -> DateFormatter {
        let key = "\(AppSettings.shared.language.rawValue)|\(hijri)|\(format)"
        if let f = cache[key] { return f }
        let f = DateFormatter()
        f.calendar = hijri ? hijriCalendar : greg
        f.locale = hijri ? hijriLocale : locale
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = format
        cache[key] = f
        return f
    }

    static var longDay: DateFormatter { formatter("EEEE d MMMM y") }
    static var shortDay: DateFormatter { formatter("EEE d MMM") }
    static var shortDayYear: DateFormatter { formatter("d MMM y") }
    static var weekday: DateFormatter { formatter("EEEE") }
    static var time: DateFormatter { formatter("h:mm a") }
    static var hijri: DateFormatter { formatter("d MMMM y", hijri: true) }
    static var hijriMonth: DateFormatter { formatter("MMMM", hijri: true) }
    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// A number in the app's digits (١٢٣ in Arabic, 123 in English), without grouping.
    static func num(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func dateText(_ d: Date, hasTime: Bool, long: Bool = false) -> String {
        let sameYear = greg.component(.year, from: d) == greg.component(.year, from: Date())
        let day = long ? longDay.string(from: d) : (sameYear ? shortDay.string(from: d) : shortDayYear.string(from: d))
        return hasTime ? "\(day) • \(time.string(from: d))" : day
    }

    static func hijriText(_ d: Date) -> String { hijri.string(from: d) + L(" هـ", " AH") }
    static func timeText(_ d: Date) -> String { time.string(from: d) }

    /// Today / Tomorrow / Yesterday or the full date — used as day headers.
    static func dayTitle(_ d: Date) -> String {
        if greg.isDateInToday(d) { return L("اليوم", "Today") }
        if greg.isDateInTomorrow(d) { return L("بكرة", "Tomorrow") }
        if greg.isDateInYesterday(d) { return L("أمس", "Yesterday") }
        return longDay.string(from: d)
    }

    // MARK: Counting — Arabic "يوم / يومين / ٣ أيام / ١١ يوم", English "1 day / 2 days"

    static func count(_ n: Int, one: String, two: String, few: String, many: String, en1: String, enN: String) -> String {
        if !isArabic { return n == 1 ? "1 \(en1)" : "\(num(n)) \(enN)" }
        switch n {
        case 1: return one
        case 2: return two
        case 3...10: return "\(num(n)) \(few)"
        default: return "\(num(n)) \(many)"
        }
    }
    static func days(_ n: Int) -> String { count(n, one: "يوم", two: "يومين", few: "أيام", many: "يوم", en1: "day", enN: "days") }
    static func weeks(_ n: Int) -> String { count(n, one: "أسبوع", two: "أسبوعين", few: "أسابيع", many: "أسبوع", en1: "week", enN: "weeks") }
    static func months(_ n: Int) -> String { count(n, one: "شهر", two: "شهرين", few: "أشهر", many: "شهر", en1: "month", enN: "months") }
    static func years(_ n: Int) -> String { count(n, one: "سنة", two: "سنتين", few: "سنوات", many: "سنة", en1: "year", enN: "years") }
    static func hours(_ n: Int) -> String { count(n, one: "ساعة", two: "ساعتين", few: "ساعات", many: "ساعة", en1: "hour", enN: "hours") }
    static func minutes(_ n: Int) -> String { count(n, one: "دقيقة", two: "دقيقتين", few: "دقائق", many: "دقيقة", en1: "minute", enN: "minutes") }
    static func appointments(_ n: Int) -> String { count(n, one: "موعد واحد", two: "موعدين", few: "مواعيد", many: "موعد", en1: "appointment", enN: "appointments") }
    static func tasks(_ n: Int) -> String { count(n, one: "مهمة وحدة", two: "مهمتين", few: "مهام", many: "مهمة", en1: "task", enN: "tasks") }

    /// A human span such as "3 days", "2 months", "1 year and 3 months".
    static func span(from a: Date, to b: Date) -> String {
        let c = greg.dateComponents([.year, .month, .day], from: greg.startOfDay(for: a), to: greg.startOfDay(for: b))
        let y = abs(c.year ?? 0), m = abs(c.month ?? 0)
        if y > 0 { return m > 0 ? L("\(years(y)) و \(months(m))", "\(years(y)) and \(months(m))") : years(y) }
        if m >= 2 { return months(m) }
        let total = abs(greg.dateComponents([.day], from: greg.startOfDay(for: a), to: greg.startOfDay(for: b)).day ?? 0)
        return days(total)
    }

    /// "Now", "in 20 minutes", "Today 4:30 PM", "Tomorrow", "in 3 days", "2 days ago".
    static func countdown(to date: Date, hasTime: Bool, now: Date = Date()) -> String {
        let dayDiff = greg.dateComponents([.day], from: greg.startOfDay(for: now), to: greg.startOfDay(for: date)).day ?? 0
        switch dayDiff {
        case 0:
            if hasTime {
                if date < now { return L("فات \(timeText(date))", "Passed \(timeText(date))") }
                let mins = Int(date.timeIntervalSince(now) / 60)
                if mins < 60 { return mins <= 1 ? L("الحين", "Now") : L("بعد \(minutes(mins))", "in \(minutes(mins))") }
                return L("اليوم \(timeText(date))", "Today \(timeText(date))")
            }
            return L("اليوم", "Today")
        case 1: return hasTime ? L("بكرة \(timeText(date))", "Tomorrow \(timeText(date))") : L("بكرة", "Tomorrow")
        case -1: return L("أمس", "Yesterday")
        case 2...: return L("بعد \(span(from: now, to: date))", "in \(span(from: now, to: date))")
        default: return L("قبل \(span(from: date, to: now))", "\(span(from: date, to: now)) ago")
        }
    }
}

extension Color {
    static let brand = Color("AccentColor")
}
