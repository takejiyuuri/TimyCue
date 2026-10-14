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
            return Self.arrivalTargetText(info.arrivalTargetMinutes)
        case .transport:
            return info.transport.displayName
        case .route:
            return info.route.displayName
        case .notifications:
            return info.notifications.summary
        case .color:
            return info.color.displayName
        case .calendar:
            let id = content.calendarID ?? defaultCalendarID
            return writableCalendars.first { $0.id == id }?.title ?? "既定"
        case .additionalDays:
            return Self.additionalDaysTexts(additionalDays).first ?? "なし"
        }
    }

    /// 行に出す値の候補。長い順に並べ、1 行に入るいちばん長いものを画面が選ぶ（「同じ内容で追加」と通知は候補が複数）
    func valueTexts(for row: InputRow) -> [String] {
        switch row {
        case .additionalDays: Self.additionalDaysTexts(additionalDays)
        case .notifications: content.metadata.notifications.summaryCandidates
        default: [valueText(for: row)]
        }
    }

    /// 「同じ内容で追加」の行に出す、足した日の短い並び（2026-10-14 ユーザー決定）。例：10/2・3・12　11/21・23-26。
    /// 同じ月は「・」でつなぎ、3 日以上続く日は「23-26」、月が変わるところは全角の空き。年は出さない（仮）。
    /// 1 行に入りきらないときのために長い順に候補を返し、後ろを「+3」のように残りの日数にする。何も足していなければ「なし」（仮）
    nonisolated static func additionalDaysTexts(_ days: [CalendarDay]) -> [String] {
        let parts = additionalDayParts(days.sorted())
        guard !parts.isEmpty else { return ["なし"] }
        let total = parts.reduce(0) { $0 + $1.dayCount }
        var texts: [String] = []
        for count in stride(from: parts.count, through: 1, by: -1) {
            let shown = parts.prefix(count)
            let rest = total - shown.reduce(0) { $0 + $1.dayCount }
            let text = shown.map { $0.text }.joined()
            texts.append(rest > 0 ? "\(text) +\(rest)" : text)
        }
        texts.append("\(total)日")
        return texts
    }

    /// 並びのひとつひとつ。前に付ける区切り（月の初めは「10/」や「　11/」、同じ月の中は「・」）も含めた文字と、その中の日数
    private nonisolated static func additionalDayParts(_ days: [CalendarDay]) -> [(text: String, dayCount: Int)] {
        var parts: [(text: String, dayCount: Int)] = []
        var previousMonth: CalendarMonth?
        var index = 0
        while index < days.count {
            let month = CalendarMonth(days[index])
            // 同じ月の中で続いている日をまとめる
            var end = index
            while end + 1 < days.count,
                  CalendarMonth(days[end + 1]) == month,
                  days[end + 1] == days[end].adding(days: 1) {
                end += 1
            }
            var runs: [(text: String, dayCount: Int)] = []
            if end - index + 1 >= 3 {
                runs.append((text: "\(days[index].day)-\(days[end].day)", dayCount: end - index + 1))
            } else {
                for day in days[index...end] { runs.append((text: "\(day.day)", dayCount: 1)) }
            }
            for (offset, run) in runs.enumerated() {
                let separator: String
                if parts.isEmpty {
                    separator = "\(month.month)/"
                } else if offset == 0 && month != previousMonth {
                    separator = "　\(month.month)/"
                } else {
                    separator = "・"
                }
                parts.append((text: separator + run.text, dayCount: run.dayCount))
            }
            previousMonth = month
            index = end + 1
        }
        return parts
    }

    /// 到着目標のドラムロールの値：0〜180 分前を 5 分おき（2026-10-13 実機の指摘）。
    /// 前の版で 5 分おきでない値を保存していたら、その値も並べて、開いただけで変わらないようにする
    nonisolated static func arrivalTargetWheelValues(including current: Int) -> [Int] {
        var values = Array(stride(from: 0, through: 180, by: 5))
        if !values.contains(current) {
            values.append(current)
            values.sort()
        }
        return values
    }

    /// 到着目標の文字。0 分前は予定開始時刻と分かるようにする（文言は仮）
    nonisolated static func arrivalTargetText(_ minutes: Int) -> String {
        if minutes == 0 { return "0分前（予定開始時刻）" }
        // 60 分以上は「1時間30分前」のように時間と分で（2026-10-13 実機の指摘）
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(minutes)分前" }
        return rest == 0 ? "\(hours)時間前" : "\(hours)時間\(rest)分前"
    }

    /// 下カレンダーの日付に出す予定の印（Q23）。予定色のドットを最大 3 個と、残りの件数
    func eventDots(on day: CalendarDay) -> (colors: [EventColor], more: Int) {
        let dayEvents = events
            .filter { $0.day == day }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startMinute) < ($1.isAllDay ? 0 : 1, $1.startMinute) }
        let colors = dayEvents.prefix(Self.maxEventDots).map { metadata(for: $0.id)?.color ?? .orange }
        return (Array(colors), max(dayEvents.count - Self.maxEventDots, 0))
    }

    static let maxEventDots = 3
}
