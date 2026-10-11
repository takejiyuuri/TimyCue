import SwiftUI

/// 下部タブ（仕様 §3）：ホーム｜カレンダー｜設定
enum RootTab: String, CaseIterable {
    case home
    case calendar
    case settings

    var title: String {
        switch self {
        case .home: "ホーム"
        case .calendar: "カレンダー"
        case .settings: "設定"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "clock"
        case .calendar: "calendar"
        case .settings: "gearshape"
        }
    }
}

struct RootTabView: View {
    @State private var selection: RootTab = RootTabView.initialTab

    var body: some View {
        TabView(selection: $selection) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                screen(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .tint(Theme.Colors.accent)
    }

    @ViewBuilder
    private func screen(for tab: RootTab) -> some View {
        switch tab {
        case .calendar: CalendarTabView()
        case .home, .settings: PlaceholderScreen(title: tab.title)
        }
    }

    /// Codemagic でシミュレータの画面写真を撮るとき、起動引数 `-TimyCueTab calendar` で最初のタブを選ぶ
    private static var initialTab: RootTab {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "TimyCueTab"), let tab = RootTab(rawValue: raw) {
            return tab
        }
        #endif
        return .home
    }
}

/// 各タブの中身ができるまでの仮の画面
struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}
