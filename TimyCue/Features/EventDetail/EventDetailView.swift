import SwiftUI

/// 予定詳細（v1.1・Q17）。見るだけの画面で、ここでは直接編集しない。
/// 「編集」を押した時だけ 3 分割の予定編集画面へ移る（3 分割画面は第3段階で作るので、今は押せない）
struct EventDetailView: View {
    let eventID: UUID
    @Environment(CalendarStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let event = store.event(id: eventID) {
                content(for: event, metadata: store.metadata(for: eventID))
            } else {
                Text("予定が見つかりません")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("予定")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // 3 分割の予定編集画面（第3段階）ができたら、ここからつなぐ
                Button("編集") {}
                    .disabled(true)
            }
        }
    }

    private func content(for event: CalendarEvent, metadata: TimyCueEventMetadata?) -> some View {
        let rows = EventDetailRows(event: event, metadata: metadata)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(EventPalette.color(for: metadata?.color ?? .orange))
                        .frame(width: 12, height: 12)
                    Text(event.displayTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .padding(.vertical, Theme.Spacing.l)

                DetailRow(label: "日時", value: rows.dateTime)
                if let place = rows.place {
                    // 場所を押すと外部の地図へ渡す。TimyCue 自身はナビをしない（v1.1「外部地図」）
                    Button {
                        if let url = EventDetailRows.mapsURL(for: place) { openURL(url) }
                    } label: {
                        DetailRow(label: "場所", value: place, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    DetailRow(label: "場所", value: "なし")
                }
                DetailRow(label: "到着目標", value: rows.arrivalTarget)
                DetailRow(label: "移動手段", value: rows.transport)
                if let route = rows.route {
                    DetailRow(label: "ルート", value: route)
                }
                DetailRow(label: "通知", value: rows.notifications)
                DetailRow(label: "出発目安", value: rows.departure)
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
    }
}

/// 予定詳細の 1 行（左に項目名、右に中身）
private struct DetailRow: View {
    let label: String
    let value: String
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "map")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.vertical, Theme.Spacing.m)
        .overlay(alignment: .bottom) {
            Theme.Colors.separator.frame(height: 1)
        }
        .contentShape(Rectangle())
    }
}

/// 予定詳細に出す文字（v1.1「予定詳細画面」の最低限の項目）。画面に依らない決まりだけを置く
struct EventDetailRows: Equatable {
    let dateTime: String
    let place: String?
    let arrivalTarget: String
    let transport: String
    /// 移動手段が車のときだけ（仕様 §52）
    let route: String?
    let notifications: String
    /// 出発目安。移動時間の計算（第5段階）ができるまでは出せない
    let departure: String

    init(event: CalendarEvent, metadata: TimyCueEventMetadata?) {
        let day = event.day
        let date = "\(day.month)月\(day.day)日（\(day.weekdaySymbol())）"
        dateTime = event.isAllDay ? "\(date) 終日" : "\(date) \(CalendarStore.timeText(for: event))"
        place = event.locationName.flatMap { $0.isEmpty ? nil : $0 }
        let info = metadata ?? TimyCueEventMetadata()
        arrivalTarget = info.arrivalTargetMinutes.map { "\($0)分前" } ?? "未設定"
        transport = info.transport.displayName
        route = info.transport == .car ? info.route.displayName : nil
        notifications = info.notifications.summary
        departure = "まだ計算しません"
    }

    /// 外部の地図（Apple マップ）で場所を開く URL
    static func mapsURL(for place: String) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: place)]
        return components?.url
    }
}
