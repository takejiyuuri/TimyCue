import UIKit

/// 月カレンダーの UIScrollView を、少しの間だけ今の位置にとどめる（2026-10-14 実機の指摘「ピクッと動く」）。
/// カレンダーのタブを押し直すと、iOS が画面をいちばん上（20 年前）へ動かし始める。今日が見えているときは今の位置のままにしたいので、
/// 押した瞬間の位置を覚え、しばらくの間は位置が変わったら画面に描く前に戻す。週の頭へそろえ直すと、そろえた分だけ動いて見えていた
@MainActor
final class ScrollHold {
    /// とどめる長さ（iOS の動きが終わるまで）
    static let duration: Duration = .milliseconds(800)

    /// とどめる UIScrollView。月カレンダーが出たときに ScrollsToTopDisabler が入れる
    weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var releaseTask: Task<Void, Never>?

    /// 今の位置にしばらくとどめる。UIScrollView がまだ見つかっていなければ何もせず false
    @discardableResult
    func hold() -> Bool {
        guard let scrollView else { return false }
        let held = scrollView.contentOffset
        observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                // 指で動かし始めたら、とどめるのをやめる
                if scrollView.isTracking {
                    self?.release()
                } else if scrollView.contentOffset != held {
                    scrollView.setContentOffset(held, animated: false)
                }
            }
        }
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else { return }
            self?.release()
        }
        return true
    }

    /// とどめるのをやめる
    func release() {
        observation?.invalidate()
        observation = nil
        releaseTask?.cancel()
        releaseTask = nil
    }
}
