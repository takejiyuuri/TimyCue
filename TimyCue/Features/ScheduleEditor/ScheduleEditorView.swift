import Combine
import UIKit
import SwiftUI

/// カレンダータブ＝予定の閲覧・登録・編集・コピーをする 3 分割画面（仕様 §16。タブと別画面にしない）。
/// 左上：時間画面／右上：入力画面／下：カレンダー。3 つは常に表示し、それぞれ別々にスクロールする。
struct ScheduleEditorView: View {
    @Environment(ScheduleEditorStore.self) private var store
    @State private var isKeyboardVisible = false

    var body: some View {
        GeometryReader { proxy in
            let topHeight = proxy.size.height * (isKeyboardVisible
                ? EditorLayout.topHeightFractionWithKeyboard
                : EditorLayout.topHeightFraction)
            let timeWidth = proxy.size.width * (isKeyboardVisible
                ? EditorLayout.timePaneWidthFractionWithKeyboard
                : EditorLayout.timePaneWidthFraction)

            VStack(spacing: EditorLayout.paneSpacing) {
                HStack(spacing: EditorLayout.paneSpacing) {
                    TimePane()
                        .frame(width: timeWidth)
                    EventInputPane()
                }
                .frame(height: topHeight)

                CalendarPane()
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, EditorLayout.paneSpacing)
            .padding(.top, EditorLayout.paneSpacing)
            .animation(.easeOut(duration: 0.2), value: isKeyboardVisible)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .onAppear {
            if store.displayedDay == nil {
                store.startNew(on: CalendarDay(Date()))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }
}

/// 3 つの領域に共通の見た目（角丸の面）
struct PaneBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.Colors.separator, lineWidth: 1)
            )
    }
}

extension View {
    func paneBackground() -> some View {
        modifier(PaneBackground())
    }
}

#Preview {
    ScheduleEditorView()
        .environment(ScheduleEditorStore(repository: InMemoryEventRepository(events: SampleEvents.make())))
}
