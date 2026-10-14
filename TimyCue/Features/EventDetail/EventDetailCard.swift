import SwiftUI

/// 予定詳細の中身（v1.1「予定詳細画面」・Q27）。別の画面にはせず、各画面の吹き出しの中に出す。
/// ここでは直接編集しない。「編集」を押した時だけ 3 分割の予定編集画面を開く（Q30）。
/// 祝日など見るだけの予定は、何の日か（名前と日時）だけを出し、「編集」は出さない（2026-10-13 ユーザー決定）
struct EventDetailCard: View {
    let event: CalendarEvent
    let metadata: TimyCueEventMetadata?
    var isViewOnly = false
    let onEdit: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        let rows = EventDetailRows(event: event, metadata: metadata)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(EventPalette.color(for: metadata?.color ?? .orange))
                    .frame(width: 10, height: 10)
                Text(event.displayTitle)
                    .font(CalendarMetrics.popoverTitleFont)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if !isViewOnly {
                    Button(action: onEdit) {
                        Text("編集").foregroundStyle(Theme.Colors.onAccent)
                    }
                    .font(CalendarMetrics.popoverSecondaryFont.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(Theme.Colors.accent)
                    .controlSize(.small)
                }
            }
            DetailLine(label: "日時", value: rows.dateTime)
            if !isViewOnly {
                details(rows)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 場所・到着目標など（見るだけの予定では出さない）
    @ViewBuilder
    private func details(_ rows: EventDetailRows) -> some View {
        if let place = rows.place {
            // 暫定：地図のマークを押すと外部の地図（Apple マップ）へ渡す。住所の文字を押しても開かない（2026-10-14 実機の指摘。仮）。
            // 簡易ルートを作ったら、TimyCue 内の簡易ルートを開くに置き換え、外部の地図／ナビを開く役目は「ナビ開始」へ移す
            // （追加仕様書 §28.4・§29.1・Q57。2026-10-13 確認）
            DetailLine(label: "場所", value: place, systemImage: "map") {
                if let url = EventDetailRows.mapsURL(for: place) { openURL(url) }
            }
        } else {
            DetailLine(label: "場所", value: "なし")
        }
        DetailLine(label: "到着目標", value: rows.arrivalTarget)
        DetailLine(label: "移動手段", value: rows.route.map { "\(rows.transport)（\($0)）" } ?? rows.transport)
        DetailLine(label: "通知", value: rows.notifications)
        DetailLine(label: "出発目安", value: rows.departure)
    }
}

/// 予定詳細の 1 行（左に項目名、右に中身）
private struct DetailLine: View {
    let label: String
    let value: String
    var systemImage: String?
    /// マークを押したときの動き（場所の行の「地図で開く」）。あるときは、マークだけが押せる
    var onImageTap: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(CalendarMetrics.popoverSecondaryFont)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(CalendarMetrics.popoverSecondaryFont)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let systemImage, let onImageTap {
                Button(action: onImageTap) {
                    Image(systemName: systemImage)
                        .font(CalendarMetrics.detailActionIconFont)
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(minWidth: CalendarMetrics.detailActionTapSize, minHeight: CalendarMetrics.detailActionTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("地図で開く")
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
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
        arrivalTarget = ScheduleEditorStore.arrivalTargetText(info.arrivalTargetMinutes)
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
