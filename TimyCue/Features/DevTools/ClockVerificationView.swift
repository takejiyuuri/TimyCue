#if TIMYCUE_DEV_TOOLS
import SwiftUI

/// 設定 ＞ 開発用：時計の確かめ（H2 の前提作業 2。2026-10-16）。表示の時刻を手で進めて、今の Home の時計
/// （針・弧・色・「いま」・丸のずらし・中央の文字・終わる時刻と知らせ）を確かめる。
/// 時計は今の Home と同じ HomeClockView。時刻はこの画面の中だけのもので、カレンダー・通知・位置情報・経路・Live Activity には影響しない
struct ClockVerificationView: View {
    @State private var store = ClockVerificationStore.fromLaunchArguments()

    var body: some View {
        let model = store.model
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    timeHeader(model)
                    clockArea(model, screenWidth: proxy.size.width)
                    facts(model)
                    presets
                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.Colors.homeBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { controls }
        .navigationTitle("時計の確かめ")
        .navigationBarTitleDisplayMode(.inline)
        // 自動で進める：1 秒ごとに 1 分（この画面の中の時刻だけ）
        .task(id: store.isRunning) {
            guard store.isRunning else { return }
            while !Task.isCancelled && store.isRunning {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled || !store.isRunning { break }
                store.step(1)
            }
        }
    }

    private func timeHeader(_ model: ClockVerificationModel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("検証用の時刻 \(model.nowText)（\(model.offsetText)）")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("見本：\(store.scenario.title)。出発 10:00・開始 \(store.scenario == .withPlace ? "10:30" : "10:00")。実際の予定・通知には影響しません")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    /// 時計と、その下の「9:37 → 10:00 出発予定」、知らせ。時計がないときは「時計なし」
    @ViewBuilder
    private func clockArea(_ model: ClockVerificationModel, screenWidth: CGFloat) -> some View {
        let diameter = screenWidth * store.clockWidth
        VStack(spacing: Theme.Spacing.s) {
            if let face = model.face, let word = model.targetWord {
                // 40％は H2 の第一の候補（中の文字・針を外径に合わせる：Q85）。74％は今の Home のまま
                HomeClockView(face: face, targetWord: word, scalesWithSize: store.clockWidth < 0.7)
                    .frame(width: diameter, height: diameter)
                    .padding(.vertical, HomeMetrics.clockLabelRoom)
                Text("\(HomeClockMath.flowText(now: face.now, target: face.target)) \(word)予定")
                    .font(HomeMetrics.flowFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                Text("時計なし")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(height: diameter + HomeMetrics.clockLabelRoom * 2)
            }
            // 主状態の大きな知らせ（今の Home と同じ文言：出発してください／出発時刻を○分過ぎています／予定時刻になりました）
            Text(model.state.headline ?? " ")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.Colors.accent)
        }
        .frame(maxWidth: .infinity)
    }

    /// 画面の時計と見比べるための、計算の結果
    private func facts(_ model: ClockVerificationModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fact("状態", model.stateTitle)
            if let face = model.face {
                fact("残り", "\(face.remainingMinutes)分（弧は \(face.remainingMinutes * 6)°）")
                fact("弧の色", model.ringColorTitle ?? "")
                fact("「いま」の文字", face.showsNowLabel ? "出す" : "出さない（出発と5分以内）")
                fact("いまの丸", face.markersCoincide ? "内側へずらす（60分前）" : "ずらさない")
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: Theme.Radius.medium).fill(Theme.Colors.surface) }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text(title)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .font(.footnote)
    }

    /// すぐに飛べる時刻
    private var presets: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("中央の文字の 4 種類")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            presetButtons(ClockVerificationPreset.centerTexts)
            Text("確かめる時刻")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.top, Theme.Spacing.s)
            presetButtons(ClockVerificationPreset.all)
        }
    }

    private func presetButtons(_ presets: [ClockVerificationPreset]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(presets) { preset in
                let isCurrent = preset.scenario == store.scenario && preset.offset == store.offsetMinutes
                Button {
                    store.jump(to: preset.offset, scenario: preset.scenario)
                } label: {
                    Text(preset.title)
                        .font(.footnote)
                        .foregroundStyle(isCurrent ? Theme.Colors.onAccent : Theme.Colors.actionText)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, 6)
                        .background {
                            Capsule().fill(isCurrent ? Theme.Colors.accentFill : Theme.Colors.surface)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                stepButton("−5分", -5)
                stepButton("−1分", -1)
                stepButton("＋1分", 1)
                stepButton("＋5分", 5)
                Button(store.isRunning ? "止める" : "自動") {
                    store.isRunning.toggle()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accentFill)
                .foregroundStyle(Theme.Colors.onAccent)
            }
            HStack(spacing: Theme.Spacing.m) {
                Picker("見本", selection: $store.scenario) {
                    ForEach(ClockVerificationScenario.allCases, id: \.self) { scenario in
                        Text(scenario == .withPlace ? "場所あり" : "場所なし").tag(scenario)
                    }
                }
                .pickerStyle(.segmented)
                Picker("時計の大きさ", selection: $store.clockWidth) {
                    ForEach(ClockVerificationStore.clockWidths, id: \.self) { width in
                        Text(width < 0.7 ? "40％" : "74％（今）").tag(width)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(.bar)
    }

    private func stepButton(_ title: String, _ minutes: Int) -> some View {
        Button(title) { store.step(minutes) }
            .buttonStyle(.bordered)
            .tint(Theme.Colors.accent)
            .foregroundStyle(Theme.Colors.actionText)
            .monospacedDigit()
    }
}
#endif
