import EventKit
import Observation
import SwiftUI

/// Apple カレンダーとつなぐ状態（仕様 §68・§79・§80）。
/// 許可は初回に全部求めず、「Apple カレンダーとつなぐ」を押したとき（最初に同期する時）に初めて求める。
/// 許可しなくても、TimyCue で作った予定は端末の中に保存して使える
@MainActor
@Observable
final class CalendarConnection {
    enum State: Equatable {
        /// まだ求めていない
        case notAsked
        /// つないでいる
        case connected
        /// 許可されなかった（設定アプリから許可できる）
        case denied
        /// 端末の制限で使えない
        case restricted
    }

    private(set) var state: State
    /// つなぐときに、端末の中の予定を Apple カレンダーへ移せなかった件数（0 なら全部移せた）
    private(set) var failedMoves = 0

    @ObservationIgnored private let eventStore: EKEventStore
    @ObservationIgnored private let switchable: SwitchableEventRepository
    @ObservationIgnored private let localEvents: FileEventRepository?
    @ObservationIgnored private let metadata: EventMetadataRepository
    @ObservationIgnored private let onChange: @MainActor () -> Void

    /// localEvents が nil のとき（見本の予定で動かしているとき）は、つないでも保存先を切り替えない
    init(eventStore: EKEventStore,
         switchable: SwitchableEventRepository,
         localEvents: FileEventRepository?,
         metadata: EventMetadataRepository,
         onChange: @escaping @MainActor () -> Void) {
        self.eventStore = eventStore
        self.switchable = switchable
        self.localEvents = localEvents
        self.metadata = metadata
        self.onChange = onChange
        state = Self.state(for: EKEventStore.authorizationStatus(for: .event))
        if state == .connected { useEventKit(moveLocalEvents: false) }
    }

    static func state(for status: EKAuthorizationStatus) -> State {
        switch status {
        case .fullAccess, .authorized: .connected
        case .denied, .writeOnly: .denied
        case .restricted: .restricted
        case .notDetermined: .notAsked
        @unknown default: .notAsked
        }
    }

    /// 「Apple カレンダーとつなぐ」：ここで初めてカレンダーの許可を求める（§79）
    func connect() async {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            state = granted ? .connected : .denied
        } catch {
            state = .denied
        }
        if state == .connected { useEventKit(moveLocalEvents: true) }
    }

    /// Apple カレンダー側が変わったとき（§68）。読み直す
    func calendarDidChange() {
        guard state == .connected else { return }
        onChange()
    }

    /// 保存先を Apple カレンダーに切り替える。端末の中に入れていた TimyCue の予定は Apple カレンダーへ移す（仮）
    private func useEventKit(moveLocalEvents: Bool) {
        guard let localEvents else { return }
        let eventKit = EventKitEventRepository(store: eventStore, metadata: metadata)
        if moveLocalEvents {
            let pending = localEvents.allEvents()
            var moved = 0
            for event in pending {
                if (try? eventKit.insert([event])) != nil { moved += 1 }
            }
            failedMoves = pending.count - moved
            if failedMoves == 0 { try? localEvents.removeAll() }
        }
        switchable.use(eventKit)
        onChange()
    }
}

/// カレンダータブの上に出す「Apple カレンダーとつなぐ」（仮の置き場所。設定画面の「カレンダー連携」ができたらそちらへ。§81）
struct CalendarConnectionBanner: View {
    @Environment(CalendarConnection.self) private var connection
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch connection.state {
        case .connected:
            if connection.failedMoves > 0 {
                message("\(connection.failedMoves)件の予定を Apple カレンダーへ移せませんでした。TimyCue の中には残っています。")
            }
        case .notAsked:
            HStack(spacing: Theme.Spacing.s) {
                Text("Apple カレンダーの予定も一緒に見られます")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: 0)
                Button("つなぐ") {
                    Task { await connection.connect() }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
                .controlSize(.small)
            }
            .bannerStyle()
        case .denied:
            // 許可されなくてもアプリは使える。予定は端末の中に保存する（§80）
            HStack(spacing: Theme.Spacing.s) {
                Text("Apple カレンダーにつないでいません。予定は TimyCue の中に保存しています。")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 0)
                Button("設定") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.footnote)
                .controlSize(.small)
            }
            .bannerStyle()
        case .restricted:
            message("この端末では Apple カレンダーを使えません。予定は TimyCue の中に保存しています。")
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .bannerStyle()
    }
}

private extension View {
    func bannerStyle() -> some View {
        padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .background(Theme.Colors.surface)
            .overlay(alignment: .bottom) {
                Theme.Colors.separator.frame(height: 1)
            }
    }
}
