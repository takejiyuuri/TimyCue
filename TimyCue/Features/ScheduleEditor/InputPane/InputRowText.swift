import Foundation

extension ScheduleEditorStore {
    /// 右上の 1 行に出す今の値（仕様 §44 の例：「到着目標 10分前」「通知 30分・出発」「終了 未設定」）
    func valueText(for row: InputRow) -> String {
        let info = content.metadata
        switch row {
        case .title:
            return content.title.isEmpty ? "未入力" : content.title
        case .location:
            return content.locationName.flatMap { $0.isEmpty ? nil : $0 } ?? "なし"
        case .arrivalTarget:
            return info.arrivalTargetMinutes.map { "\($0)分前" } ?? "未設定"
        case .transport:
            return info.transport.displayName
        case .route:
            return info.route.displayName
        case .notifications:
            return info.notifications.summary
        case .repeatRule:
            return content.repeatRule.displayName
        case .color:
            return info.color.displayName
        case .end:
            guard let day = displayedDay, let end = endMinute(on: day) else { return "未設定" }
            return TimeText.hourMinute(end)
        }
    }

    /// 到着目標の候補（仕様 §49。カスタムは入力の段階で足す）
    static let arrivalTargetChoices = [5, 10, 15, 20, 30]

    /// 終了の行で選べる所要時間（仮。仮予定の下端のハンドルで決める操作は時間画面の段階で作る。仕様 §41）
    static let durationChoices = [30, 60, 90, 120]

    /// 表示中の日の所要時間を、分で入れる。開始時刻がない日は何もしない
    func setDuration(_ minutes: Int?) {
        guard let day = displayedDay, let start = startMinutes[day] else { return }
        setEndMinute(minutes.map { start + $0 }, on: day)
    }
}
