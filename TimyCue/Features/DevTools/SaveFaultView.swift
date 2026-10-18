#if TIMYCUE_DEV_TOOLS
import SwiftUI

// 保存の途中の失敗を再現する開発用の画面（spec §89.9・2026-10-18 S1b 指示 10）。検証用のビルド（TIMYCUE_DEV_TOOLS）だけに入り、
// 公開版には入らない。印を付けた場所で、次の 1 回だけ失敗する（1 回失敗すると印は外れる）

/// 「設定 ＞ 開発用：保存の失敗の再現」
struct SaveFaultView: View {
    @State private var armed = SaveFaults.armedFaults

    var body: some View {
        List {
            Section {
                ForEach(SaveFault.allCases) { fault in
                    Toggle(isOn: Binding(get: { armed.contains(fault) }, set: { on in
                        if on { SaveFaults.arm(fault) } else { SaveFaults.disarm(fault) }
                        armed = SaveFaults.armedFaults
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.title(of: fault))
                            Text(Self.detail(of: fault))
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    .tint(Theme.Colors.accent)
                }
            } footer: {
                Text("印を付けた場所で、次の 1 回だけ失敗します。実際の Apple カレンダーで試すときは、予定名に「TimyCue テスト」と入れた予定だけを使ってください。")
            }
        }
        .navigationTitle("開発用：保存の失敗の再現")
        .onAppear { armed = SaveFaults.armedFaults }
    }

    static func title(of fault: SaveFault) -> String {
        switch fault {
        case .appleBeforeWrite: "Apple に書く前"
        case .appleAfterWrite: "Apple に書けた直後"
        case .terminateAfterAppleWrite: "Apple に書けた直後にアプリを終える"
        case .appleLinksWrite: "結び付けの保存"
        case .multiDaySecondDay: "複数日の 2 日目"
        case .moveAfterAppleWrite: "Apple Calendarに保存の途中"
        case .localEventsWrite: "端末の中の予定の保存"
        case .metadataWrite: "到着目標などの設定の保存"
        case .settingsWrite: "カレンダー連携の設定の保存"
        case .appleLinksAfterDelete: "Apple の予定を消したあとの結び付けの保存"
        case .unknownResult: "Apple に書いた結果を確かめられない"
        }
    }

    static func detail(of fault: SaveFault) -> String {
        switch fault {
        case .appleBeforeWrite: "何も書かずに失敗する"
        case .appleAfterWrite: "書けたのに、その場では失敗が届く"
        case .terminateAfterAppleWrite: "次に開いたときの復旧を確かめる"
        case .appleLinksWrite: "予定は書けたが、結び付けのファイルに書けない"
        case .multiDaySecondDay: "1 日目は書け、2 日目が書けない"
        case .moveAfterAppleWrite: "Apple には作れたが、元の予定を消す前に失敗する"
        case .localEventsWrite: "連携していないときの予定の保存・変更・削除"
        case .metadataWrite: "予定は書けたが、TimyCue の設定を保存できない"
        case .settingsWrite: "保存先・表示などの設定を変えたとき"
        case .appleLinksAfterDelete: "予定は消えたが、結び付けのファイルに書けない"
        case .unknownResult: "書けたかどうか確かめられない結果にする"
        }
    }

    /// 起動引数 `-TimyCueSaveFault multiDaySecondDay,metadataWrite` で、起動したときに印を付ける（画面写真・実機の確かめ用）
    static func armFromLaunchArguments() {
        guard let raw = UserDefaults.standard.string(forKey: "TimyCueSaveFault") else { return }
        raw.split(separator: ",")
            .compactMap { SaveFault(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
            .forEach(SaveFaults.arm)
    }
}
#endif
