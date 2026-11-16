import Foundation

/// One payment towards a commitment.
struct Payment: Identifiable, Codable, Equatable {
    var id = UUID()
    var amount: Double
    var date: Date
}

/// A debt or other obligation: the total owed, the payments made so far, and when it is due
/// (open-ended when `due` is nil).
struct Commitment: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var icon: String? = nil
    var total: Double = 0
    var payments: [Payment] = []
    var due: Date? = nil
    var notes = ""
    var createdAt = Date()
    var updatedAt = Date()

    var paid: Double { payments.reduce(0) { $0 + $1.amount } }
    var remaining: Double { max(0, total - paid) }
    /// 0…1, how much of the total has been paid.
    var progress: Double { total > 0 ? min(1, paid / total) : 0 }
    var isSettled: Bool { total > 0 && paid >= total - 0.005 }
    var displayIcon: String { icon ?? "creditcard.fill" }

    func isOverdue(now: Date = Date()) -> Bool {
        guard !isSettled, let d = due else { return false }
        return Fmt.greg.startOfDay(for: d) < Fmt.greg.startOfDay(for: now)
    }

    /// «حتى ١٥ ديسمبر» / «مفتوح».
    var dueText: String {
        guard let d = due else { return L("مفتوح", "Open") }
        return L("حتى \(Fmt.dateText(d, hasTime: false))", "Until \(Fmt.dateText(d, hasTime: false))")
    }

    static let icons = ["creditcard.fill", "banknote.fill", "house.fill", "car.fill", "building.columns.fill",
                        "person.2.fill", "cart.fill", "phone.fill", "graduationcap.fill", "cross.case.fill",
                        "airplane", "gift.fill", "bag.fill", "wrench.and.screwdriver.fill", "bolt.fill"]
}

extension Fmt {
    /// «٣٬٠٠٠ ر.س» / «SAR 3,000» — up to two decimals, only when there are any.
    static func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        let n = f.string(from: NSNumber(value: v)) ?? "\(v)"
        return isArabic ? "\(n) ر.س" : "SAR \(n)"
    }

    /// «٦٠٪» / «60%».
    static func percent(_ p: Double) -> String {
        let n = num(Int((p * 100).rounded()))
        return isArabic ? "\(n)٪" : "\(n)%"
    }

    /// Reads an amount typed with Arabic or Western digits («١٢٥٠٫٥», «1,250.5»).
    static func parseAmount(_ s: String) -> Double? {
        var out = ""
        for ch in s {
            if let v = ch.wholeNumberValue { out.append(String(v)) }
            else if ch == "." || ch == "٫" { out.append(".") }
        }
        return out.isEmpty ? nil : Double(out)
    }

    /// The amount as typed back into a field (no grouping, Western or Arabic digits by language).
    static func amountField(_ v: Double) -> String {
        guard v > 0 else { return "" }
        let f = NumberFormatter()
        f.locale = locale
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? ""
    }
}
