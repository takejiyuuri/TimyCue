#if TIMYCUE_DEV_TOOLS
import Observation
import SwiftUI

// H2 の前提作業 1（2026-10-16 Q93・ユーザーの開始の指示）：正式キャラクター 3 モード（亀・人型・うさぎ）の立ち姿を、
// 原画と見比べるための開発用の画面。検証用のビルド（コンパイルの条件 TIMYCUE_DEV_TOOLS を付けたもの）だけに入り、
// App Store の公開版には入らない。Home には出さない（時刻でモードを切り替えるのは H2）。
// 原画そのものはアプリに入れない（spec §88.4：参考資料はアプリの画像素材に使わない）。原画との比べ方は
// docs/design-reference/characters/official-3modes/reproduction/ の比較画像と、この画面の画面写真で行う

/// 3 モードの比べる画面で切り替えるもの
@Observable
final class CharacterModeComparisonStore {
    /// 本体の高さ（pt）。36pt が Home の第一の候補。72・108pt は形を見やすくするための拡大
    static let heights: [CGFloat] = [36, 72, 108]

    var mode: CharacterMode
    var height: CGFloat
    /// 本体の枠と、甲羅・耳を含めた枠を点線で出すか
    var showsArea: Bool

    init(mode: CharacterMode = .human, height: CGFloat = 36, showsArea: Bool = false) {
        self.mode = mode
        self.height = height
        self.showsArea = showsArea
    }

    /// Codemagic の画面写真用：起動引数 `-TimyCueCharacterMode turtle -TimyCueCharacterModeHeight 108 -TimyCueCharacterModeArea YES`
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> CharacterModeComparisonStore {
        let store = CharacterModeComparisonStore()
        if let raw = defaults.string(forKey: "TimyCueCharacterMode"), let mode = CharacterMode(rawValue: raw) {
            store.mode = mode
        }
        let height = CGFloat(defaults.double(forKey: "TimyCueCharacterModeHeight"))
        if heights.contains(height) { store.height = height }
        if defaults.object(forKey: "TimyCueCharacterModeArea") != nil {
            store.showsArea = defaults.bool(forKey: "TimyCueCharacterModeArea")
        }
        return store
    }

    /// 「本体 36pt・甲羅を含めた領域 幅37×高さ39pt（輪郭の線を含む）」の文
    static func areaText(height: CGFloat, mode: CharacterMode) -> String {
        let layout = CharacterLayout(height: height, mode: mode)
        let width = Int(layout.size.width.rounded())
        let whole = Int(layout.size.height.rounded())
        let gearName: String
        switch mode {
        case .turtle: gearName = "甲羅"
        case .human: gearName = "装備なし"
        case .rabbit: gearName = "耳"
        }
        return "本体 \(Int(height))pt・\(gearName)を含めた領域 幅\(width)×高さ\(whole)pt（輪郭の線を含む）"
    }
}

/// 設定 ＞ 開発用：キャラクター 3 モード。上に 3 モードを 36pt で並べ、下に選んだモードを選んだ大きさで出す
struct CharacterModeComparisonView: View {
    @State private var store = CharacterModeComparisonStore.fromLaunchArguments()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("正式原画「キャラクター 3 モード」の立ち姿の再現（確認用）")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
                lineup
                Divider()
                selected
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.homeBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { controls }
        .navigationTitle("キャラクター 3 モード")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 3 モードを Home の第一の候補の大きさ（本体 36pt）で、足元をそろえて並べる
    private var lineup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("3 モード（本体 36pt）")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            HStack(alignment: .bottom, spacing: Theme.Spacing.xl) {
                ForEach(CharacterMode.allCases, id: \.self) { mode in
                    VStack(spacing: Theme.Spacing.xs) {
                        figure(mode: mode, height: 36)
                        Text(mode.title)
                            .font(.caption)
                            .foregroundStyle(mode == store.mode ? Theme.Colors.actionText : Theme.Colors.textSecondary)
                    }
                    .onTapGesture { store.mode = mode }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var selected: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("\(store.mode.title)モード（本体 \(Int(store.height))pt）")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            figure(mode: store.mode, height: store.height)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.s)
            Text(CharacterModeComparisonStore.areaText(height: store.height, mode: store.mode))
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            if store.showsArea {
                Text("点線：オレンジ＝本体の枠（\(Int(store.height))pt の基準）、灰色＝甲羅・耳を含めた枠")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    /// キャラクター。枠を出すときは、本体の枠（オレンジ）と、装備を含めた枠（灰色）を点線で重ねる
    private func figure(mode: CharacterMode, height: CGFloat) -> some View {
        let layout = CharacterLayout(height: height, mode: mode)
        return CharacterFigure(height: height, mode: mode)
            .overlay(alignment: .topLeading) {
                if store.showsArea {
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .strokeBorder(Theme.Colors.textSecondary, style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .frame(width: layout.size.width, height: layout.size.height)
                        Rectangle()
                            .strokeBorder(Theme.Colors.accent, style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .frame(width: layout.bodyFrame.width, height: layout.bodyFrame.height)
                            .offset(x: layout.bodyFrame.minX, y: layout.bodyFrame.minY)
                    }
                    .allowsHitTesting(false)
                }
            }
    }

    private var controls: some View {
        VStack(spacing: Theme.Spacing.s) {
            Picker("モード", selection: $store.mode) {
                ForEach(CharacterMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            HStack(spacing: Theme.Spacing.m) {
                Picker("大きさ", selection: $store.height) {
                    ForEach(CharacterModeComparisonStore.heights, id: \.self) { height in
                        Text("\(Int(height))pt").tag(height)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("枠", isOn: $store.showsArea)
                    .fixedSize()
                    .tint(Theme.Colors.accent)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(.bar)
    }
}
#endif
