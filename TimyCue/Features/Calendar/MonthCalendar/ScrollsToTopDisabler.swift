import SwiftUI
import UIKit

/// 中にある UIScrollView の「いちばん上へ戻る」（タブの押し直し・画面上端のタップ）を止める。
/// 月カレンダーは 20 年前の週から並べているので、いちばん上へ戻ると 20 年前へ飛んでしまう（2026-10-13 実機の不具合）
struct ScrollsToTopDisabler: UIViewRepresentable {
    /// 見つけた UIScrollView を渡す先（タブの押し直しで今の位置にとどめる。2026-10-14）
    var hold: ScrollHold?

    func makeUIView(context: Context) -> Finder {
        let finder = Finder()
        finder.hold = hold
        return finder
    }

    func updateUIView(_ uiView: Finder, context: Context) {
        uiView.hold = hold
    }

    final class Finder: UIView {
        weak var hold: ScrollHold?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                var view = self?.superview
                while let current = view {
                    if let scrollView = current as? UIScrollView {
                        scrollView.scrollsToTop = false
                        self?.hold?.scrollView = scrollView
                        return
                    }
                    view = current.superview
                }
            }
        }
    }
}
