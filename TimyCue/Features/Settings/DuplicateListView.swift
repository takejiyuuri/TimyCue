import SwiftUI

/// TimyCue のローカル予定と Apple カレンダーの予定の重複候補の一覧（Q42-8・Q50）。
/// 1 件ずつ「Apple Calendarの予定を使う」か「両方残す」を選ぶ。連携した直後にモーダルを続けて出すことはしない
struct DuplicateListView: View {
    @Environment(CalendarConnection.self) private var connection
    /// 両方に付いた TimyCue の設定がぶつかるとき、どちらを使うか聞いている組
    @State private var conflicting: DuplicateCandidate?

    var body: some View {
        List {
            if connection.duplicateCandidates.isEmpty {
                Text("重複している可能性のある予定はありません")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ForEach(connection.duplicateCandidates) { candidate in
                Section {
                    eventRow(label: "TimyCue の予定", event: candidate.local, calendarName: nil)
                    eventRow(label: "Apple カレンダーの予定", event: candidate.apple,
                             calendarName: connection.calendars.first { $0.id == candidate.apple.calendarID }?.title)
                    Button("Apple Calendarの予定を使う") { useApple(candidate) }
                    Button("両方残す") { connection.keepBoth(candidate) }
                } header: {
                    Text(dateText(candidate.local))
                } footer: {
                    Text("「Apple Calendarの予定を使う」を選ぶと、TimyCue の予定は削除し、到着目標などの設定は Apple の予定に引き継ぎます。")
                }
            }
        }
        .navigationTitle("重複候補")
        // 両方に設定があって中身が違うときは、勝手に上書きせず確かめる（Q50）
        .confirmationDialog("到着目標などの TimyCue の設定が、2 つの予定で違います。どちらを使いますか？",
                            isPresented: Binding(get: { conflicting != nil }, set: { if !$0 { conflicting = nil } }),
                            titleVisibility: .visible,
                            presenting: conflicting) { candidate in
            Button("TimyCue の予定の設定") { try? connection.useApple(candidate, preferLocalSettings: true) }
            Button("Apple カレンダーの予定の設定") { try? connection.useApple(candidate, preferLocalSettings: false) }
            Button("やめる", role: .cancel) {}
        }
    }

    private func useApple(_ candidate: DuplicateCandidate) {
        if connection.settingsConflict(candidate) {
            conflicting = candidate
        } else {
            try? connection.useApple(candidate)
        }
    }

    private func eventRow(label: String, event: CalendarEvent, calendarName: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(calendarName.map { "\(label)（\($0)）" } ?? label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(event.displayTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            if let place = event.locationName, !place.isEmpty {
                Text(place)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private func dateText(_ event: CalendarEvent) -> String {
        "\(event.day.month)月\(event.day.day)日（\(event.day.weekdaySymbol())） \(CalendarStore.timeText(for: event))"
    }
}
