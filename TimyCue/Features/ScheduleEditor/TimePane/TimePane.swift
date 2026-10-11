import SwiftUI

/// 左上：その日の縦タイムライン（仕様 §20）
struct TimePane: View {
    @Environment(ScheduleEditorStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Colors.separator)
            if let day = store.displayedDay {
                DayTimelineScroll(day: day)
            } else {
                Spacer()
            }
        }
        .paneBackground()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(store.displayedDay.map(DayText.withWeekday) ?? "")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            // 終日予定は時間軸に置かず、ここに名前だけ出す（仕様 §9：カレンダーには普通に表示する）
            if let day = store.displayedDay {
                ForEach(store.allDayEvents(on: day)) { event in
                    Text("終日 \(event.content.primaryLabel ?? "予定")")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs + 2)
    }
}

/// 時間軸のスクロール。表示する日が変わったら、その日の最初の予定の少し前へ移る（仕様 §26）
private struct DayTimelineScroll: View {
    @Environment(ScheduleEditorStore.self) private var store
    let day: CalendarDay

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                DayTimeline(day: day,
                            events: store.timedEvents(on: day),
                            drafts: store.draftEvents.filter { $0.day == day })
            }
            .onAppear { scrollToInitialHour(proxy) }
            .onChange(of: day) { scrollToInitialHour(proxy) }
        }
    }

    private func scrollToInitialHour(_ proxy: ScrollViewProxy) {
        // 予定がない日の位置（現在時刻付近／履歴から）は未決の部分があるので、今は現在時刻の少し前にする
        let fallback = Calendar.current.component(.hour, from: Date()) * 60 - 30
        let minute = store.suggestedScrollMinute(for: day) ?? max(0, fallback)
        proxy.scrollTo(DayTimeline.hourID(minute / 60), anchor: .top)
    }
}
