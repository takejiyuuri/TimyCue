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

    /// 既存の予定の編集か
    var isEdit: Bool {
        if case .edit = self { return true }
        return false
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
    case color
    /// 保存先（spec §89.3）。新規・コピーは、連携中で「TimyCue のみ」と使える Apple カレンダーを合わせて 2 種類以上あるとき、
    /// または今の保存先が使えない・まだ決まっていないときに出す（Q97・Q110）。既存の予定では所属のカレンダーをいつも出す（Q113）
    case calendar
    /// 同じ内容で別の日にも登録する。新規・コピーのときだけ、いちばん下に出す。
    /// 開いている間だけ、下のカレンダーをなぞって日を足したり外したりできる（2026-10-14 ユーザー決定）
    case additionalDays

    var label: String {
        switch self {
        case .title: "予定名"
        case .location: "場所"
        case .arrivalTarget: "到着目標"
        case .transport: "移動手段"
        case .route: "ルート"
        case .notifications: "通知"
        case .color: "色"
        case .calendar: "カレンダー"
        case .additionalDays: "同じ内容で追加"
        }
    }

    /// Apple カレンダーの予定そのものの項目か。書き込めないカレンダーの予定ではロックする（追加仕様書 §1.7）
    var isAppleField: Bool {
        switch self {
        case .title, .location, .calendar, .additionalDays: true
        case .arrivalTarget, .transport, .route, .notifications, .color: false
        }
    }
}

/// 保存に足りないもの（仕様 §46：予定名・日付・開始時刻が必須）。
/// 予定の重なりや移動の余裕の少なさは警告だけで、保存は止めない（仕様 §58）。
enum SaveIssue: Equatable {
    case noDaySelected
    case missingStartTime([CalendarDay])
    case missingTitle

    /// 画面に出す知らせ（仕様 §46・Q7 で統一した文言）
    var message: String {
        switch self {
        case .noDaySelected: "日付を選んでください"
        case .missingStartTime: "開始時刻を設定してください"
        case .missingTitle: "予定名を入力してください"
        }
    }
}

enum ScheduleEditorError: Error, Equatable {
    case notReady([SaveIssue])
    case eventNotFound(UUID)
    case copyRequiresEditMode
    /// もう保存が済んでいる（続けて押したなど）。書かない
    case alreadySaved
    /// 一部だけ保存できた・結果を確かめられなかった。知らせ（failure）はもう作ってある
    case partiallySaved
    /// 前回の結果を確かめられなかったので、確かめたかを聞いてから行う
    case needsConfirmation
    /// 新しい予定の保存先がまだ決まっていない（Q111-4）。何も書かず、保存先を選んでもらう
    case needsSaveTargetChoice
}
