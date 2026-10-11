import Foundation

/// 3 分割画面のモード（仕様 §59）
enum EditorMode: Equatable {
    case new
    case edit(eventID: UUID)
    case copy(sourceID: UUID)

    /// ヘッダーに出す表示（仕様 §59）
    var headerLabel: String {
        switch self {
        case .new: "新規"
        case .edit: "編集中"
        case .copy: "コピー中"
        }
    }

    /// 複数日を選べるか（仕様 §34・§60〜§62：新規・コピーは複数日、編集は 1 件）
    var allowsMultipleDays: Bool {
        switch self {
        case .new, .copy: true
        case .edit: false
        }
    }
}

/// 右上の入力の行（仕様 §44 の並び）
enum InputRow: CaseIterable, Equatable {
    case title
    case location
    case arrivalTarget
    case transport
    case route
    case notifications
    case repeatRule
    case color
    case end

    var label: String {
        switch self {
        case .title: "予定名"
        case .location: "場所"
        case .arrivalTarget: "到着目標"
        case .transport: "移動手段"
        case .route: "ルート"
        case .notifications: "通知"
        case .repeatRule: "繰り返し"
        case .color: "色"
        case .end: "終了"
        }
    }
}

/// 保存に足りないもの（仕様 §46：予定名・日付・開始時刻が必須）。
/// 予定の重なりや移動の余裕の少なさは警告だけで、保存は止めない（仕様 §58）。
enum SaveIssue: Equatable {
    case noDaySelected
    case missingStartTime([CalendarDay])
    case missingTitle

    /// 画面に出す知らせ。予定名は仕様 §46 の例どおり。日付・開始時刻の文言は仮
    var message: String {
        switch self {
        case .noDaySelected: "日付を選んでください"
        case .missingStartTime: "開始時刻を入れてください"
        case .missingTitle: "予定名を入力してください"
        }
    }
}

/// 「予測で一括」の状態（仕様 §36）
enum PredictionState: Equatable {
    case idle
    /// 候補を入れた日。保存はしていない
    case applied([CalendarDay])
    /// 候補を出せなかった
    case noSuggestion
}

enum ScheduleEditorError: Error, Equatable {
    case notReady([SaveIssue])
    case eventNotFound(UUID)
    case copyRequiresEditMode
}
