import Foundation

/// 3 分割画面のモード（仕様 §29）
enum EditorMode: Equatable {
    case new
    case edit(eventID: UUID)
    case copy(sourceID: UUID)

    /// 右上の固定ヘッダーに出す表示（仕様 §35）
    var headerLabel: String {
        switch self {
        case .new: "新規"
        case .edit: "編集中"
        case .copy: "コピー中"
        }
    }

    /// 複数日を選べるか（仕様 §17・§31）
    var allowsMultipleDays: Bool {
        switch self {
        case .new, .copy: true
        case .edit: false
        }
    }
}

/// 保存できる状態か。過去日・重複などの検証は未決（報告 Q12）なので、今は「日付がない」「時刻がない」だけを見る。
enum DateValidationState: Equatable {
    case ready
    case noDaySelected
    case missingStartTime([CalendarDay])
}

/// 「予測で一括」の状態（仕様 §19）
enum PredictionState: Equatable {
    case idle
    /// 候補を入れた日。保存はしていない
    case applied([CalendarDay])
    /// 候補を出せなかった
    case noSuggestion
}

enum ScheduleEditorError: Error, Equatable {
    case notReady(DateValidationState)
    case eventNotFound(UUID)
    case copyRequiresEditMode
}
