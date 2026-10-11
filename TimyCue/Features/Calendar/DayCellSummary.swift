import Foundation

/// 月カレンダーのセルに出す予定 1 件分（色点＋名前）
struct EventMark: Equatable {
    let title: String
    let color: EventColor
}

/// 色点だけの表示の 1 枠
enum DotSlot: Equatable {
    case dot(EventColor)
    /// 12 枠目に出す「+N」
    case more(Int)
}

/// 月カレンダーのセルの予定の出し方（仕様 §21）
enum DayCellSummary: Equatable {
    case empty
    /// 1〜4 件：縦に 色点＋予定名（1 行、はみ出す分は省略）
    case titles([EventMark])
    /// 5 件以上：文字を出さず色点だけ。縦 4 × 横 3 の最大 12 枠。13 件以上は 11 件まで色点、12 枠目に +N
    case dots([DotSlot])

    static let maxTitleCount = 4
    static let columns = 3
    static let maxSlots = 12

    init(marks: [EventMark]) {
        switch marks.count {
        case 0:
            self = .empty
        case 1...Self.maxTitleCount:
            self = .titles(marks)
        case ...Self.maxSlots:
            self = .dots(marks.map { .dot($0.color) })
        default:
            let shown = marks.prefix(Self.maxSlots - 1).map { DotSlot.dot($0.color) }
            self = .dots(shown + [.more(marks.count - shown.count)])
        }
    }

    /// 色点を横 3 つずつの行に分けたもの
    var dotRows: [[DotSlot]] {
        guard case .dots(let slots) = self else { return [] }
        return stride(from: 0, to: slots.count, by: Self.columns).map {
            Array(slots[$0..<min($0 + Self.columns, slots.count)])
        }
    }
}
