import SwiftUI

/// 設定 ＞ 出発・移動（2026-10-14 決定）：出発の余裕・自宅・最初の予定の出発地点・普段よく使う移動手段。
/// どれもアプリ全体の設定で、予定ごとの細かな設定は増やさない
struct DepartureSettingsView: View {
    @Environment(DepartureStore.self) private var departures
    @State private var registersHome = false

    var body: some View {
        List {
            Section {
                Picker("出発の余裕", selection: Binding(get: { departures.settings.marginLevel },
                                                   set: { departures.setMarginLevel($0) })) {
                    ForEach(DepartureMath.MarginLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("出発の余裕")
            } footer: {
                // 文言は仮
                Text("移動時間に足す余裕の大きさです。到着目標とは別に、推奨出発時刻を早めます。")
            }

            Section {
                if let home = departures.settings.home {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(home.name)
                        if let address = home.address {
                            Text(address)
                                .font(.footnote)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    Button("自宅の場所を変える") { registersHome = true }
                    Button("自宅の登録を消す", role: .destructive) { departures.setHome(nil) }
                } else {
                    Button("自宅を登録") { registersHome = true }
                }
            } header: {
                Text("自宅")
            }

            Section {
                Picker("最初の予定の出発地点", selection: Binding(get: { departures.settings.firstEventOrigin },
                                                        set: { departures.setFirstEventOrigin($0) })) {
                    Text("未選択").tag(FirstEventOrigin?.none)
                    ForEach(FirstEventOrigin.allCases, id: \.self) { origin in
                        Text(origin.displayName).tag(Optional(origin))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("最初の予定の出発地点")
            } footer: {
                // 自宅から出ることが多いのに自宅が未登録なら、登録を案内する（spec Q42-2）
                if departures.settings.firstEventOrigin == .home && departures.settings.home == nil {
                    Text("自宅を登録してください。")
                }
            }

            Section {
                Picker("普段よく使う移動手段", selection: Binding(get: { departures.settings.usualTransport },
                                                        set: { departures.setUsualTransport($0) })) {
                    Text("未選択").tag(TransportMode?.none)
                    ForEach(TransportMode.allCases.filter { $0 != .auto }, id: \.self) { mode in
                        Text(mode.displayName).tag(Optional(mode))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("普段よく使う移動手段")
            } footer: {
                // 2026-10-14 決定の文言
                Text("『自動』の予定で、まだ十分な実績がないときに使用します。TimyCueが移動実績から判断できる場合は、その予測を優先します。")
            }
        }
        .navigationTitle("出発・移動")
        .sheet(isPresented: $registersHome) {
            // 自宅は、名前を初めから「自宅」にして、位置を選ぶだけにする（spec Q42-2）
            PlaceSearchView(title: "自宅を登録", initialQuery: "", near: departures.location.location?.coordinate) { candidate in
                departures.setHome(candidate.savedPlace(named: "自宅"))
            }
        }
    }
}
