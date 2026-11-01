import Foundation
import SwiftUI

/// Dates are always shown in Arabic with Western digits; the Gregorian calendar is primary
/// and the Umm al-Qura Hijri date is shown next to it.
enum Fmt {
    static let locale = Locale(identifier: "ar_SA@calendar=gregorian;numbers=latn")
    static let hijriLocale = Locale(identifier: "ar_SA@calendar=islamic-umalqura;numbers=latn")

    static let greg: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = locale
        c.timeZone = .autoupdatingCurrent
        c.firstWeekday = 1
        return c
    }()

    static let hijriCalendar: Calendar = {
        var c = Calendar(identifier: .islamicUmmAlQura)
        c.locale = hijriLocale
        c.timeZone = .autoupdatingCurrent
        return c
    }()

    private static func formatter(_ format: String, hijri: Bool = false) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = hijri ? hijriCalendar : greg
        f.locale = hijri ? hijriLocale : locale
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = format
        return f
    }

    static let longDay = formatter("EEEE d MMMM y")
    static let shortDay = formatter("EEE d MMM")
    static let shortDayYear = formatter("d MMM y")
    static let time = formatter("h:mm a")
    static let hijri = formatter("d MMMM y", hijri: true)
    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dateText(_ d: Date, hasTime: Bool, long: Bool = false) -> String {
        let sameYear = greg.component(.year, from: d) == greg.component(.year, from: Date())
        let day = long ? longDay.string(from: d) : (sameYear ? shortDay.string(from: d) : shortDayYear.string(from: d))
        return hasTime ? "\(day) • \(time.string(from: d))" : day
    }

    static func hijriText(_ d: Date) -> String { hijri.string(from: d) + " هـ" }

    static func timeText(_ d: Date) -> String { time.string(from: d) }

    static func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.maximumFractionDigits = v.rounded() == v ? 0 : 2
        return (f.string(from: NSNumber(value: v)) ?? "\(v)") + " ر.س"
    }

    /// Accepts Arabic-Indic digits and Arabic separators ("١٢٣٫٥").
    static func parseNumber(_ s: String) -> Double? {
        let arabic = Array("٠١٢٣٤٥٦٧٨٩"), persian = Array("۰۱۲۳۴۵۶۷۸۹")
        var out = ""
        for ch in s.trimmingCharacters(in: .whitespaces) {
            if let i = arabic.firstIndex(of: ch) { out.append(String(i)) }
            else if let i = persian.firstIndex(of: ch) { out.append(String(i)) }
            else if ch == "٫" || ch == "," { out.append(".") }
            else if ch == "٬" { continue }
            else { out.append(ch) }
        }
        return Double(out)
    }

    // MARK: Arabic counting ("يوم / يومين / 3 أيام / 11 يوم")

    static func count(_ n: Int, one: String, two: String, few: String, many: String) -> String {
        switch n {
        case 1: return one
        case 2: return two
        case 3...10: return "\(n) \(few)"
        default: return "\(n) \(many)"
        }
    }
    static func days(_ n: Int) -> String { count(n, one: "يوم", two: "يومين", few: "أيام", many: "يوم") }
    static func weeks(_ n: Int) -> String { count(n, one: "أسبوع", two: "أسبوعين", few: "أسابيع", many: "أسبوع") }
    static func months(_ n: Int) -> String { count(n, one: "شهر", two: "شهرين", few: "أشهر", many: "شهر") }
    static func years(_ n: Int) -> String { count(n, one: "سنة", two: "سنتين", few: "سنوات", many: "سنة") }
    static func hours(_ n: Int) -> String { count(n, one: "ساعة", two: "ساعتين", few: "ساعات", many: "ساعة") }
    static func minutes(_ n: Int) -> String { count(n, one: "دقيقة", two: "دقيقتين", few: "دقائق", many: "دقيقة") }

    /// A human span such as "3 أيام", "شهرين و 5 أيام", "سنة و 3 أشهر".
    static func span(from a: Date, to b: Date) -> String {
        let c = greg.dateComponents([.year, .month, .day], from: greg.startOfDay(for: a), to: greg.startOfDay(for: b))
        let y = abs(c.year ?? 0), m = abs(c.month ?? 0), d = abs(c.day ?? 0)
        if y > 0 { return m > 0 ? "\(years(y)) و \(months(m))" : years(y) }
        if m >= 2 || (m == 1 && d == 0) { return d > 0 && m < 3 ? "\(months(m)) و \(days(d))" : months(m) }
        let total = abs(greg.dateComponents([.day], from: greg.startOfDay(for: a), to: greg.startOfDay(for: b)).day ?? 0)
        return days(total)
    }

    /// "اليوم", "بكرة", "بعد 3 أيام", "متأخر يومين", "اليوم 4:30 م"…
    static func countdown(to date: Date, hasTime: Bool, now: Date = Date()) -> String {
        let dayDiff = greg.dateComponents([.day], from: greg.startOfDay(for: now), to: greg.startOfDay(for: date)).day ?? 0
        switch dayDiff {
        case 0:
            if hasTime {
                if date < now { return "فات اليوم \(timeText(date))" }
                let mins = Int(date.timeIntervalSince(now) / 60)
                if mins < 60 { return mins <= 1 ? "الحين" : "بعد \(minutes(mins))" }
                return "اليوم \(timeText(date))"
            }
            return "اليوم"
        case 1: return hasTime ? "بكرة \(timeText(date))" : "بكرة"
        case -1: return "متأخر من أمس"
        case 2...: return "بعد \(span(from: now, to: date))"
        default: return "متأخر \(span(from: date, to: now))"
        }
    }
}

extension Color {
    static let brand = Color("AccentColor")
}
