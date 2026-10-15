import Foundation
import Observation

/// 3 分割画面の下カレンダーの位置と、左右のバーでの動き（2026-10-13 ユーザー決定）。
/// なぞっている間は指と同じだけ動き、指を離したら iPhone のふつうのスクロールと同じように滑って止まる。
/// 左右どちらのバーでも同じ位置を動かす（滑っている途中でどちらかのバーに触れたら止める）
@MainActor
@Observable
final class EditorCalendarScroller {
    /// いちばん上に見えている所（日付の行の高さを 1 とした位置）
    private(set) var offset: Double = 0
    /// バーをなぞっている間（バーの色を変える）
    private(set) var isDragging = false

    @ObservationIgnored private var dragStart: Double?
    @ObservationIgnored private var inertia: Task<Void, Never>?

    /// バーをなぞっている間。translation はなぞり始めからの縦の移動（ポイント）
    func drag(translation: Double, rowHeight: Double, axis: EditorCalendarAxis) {
        if dragStart == nil {
            stopInertia()
            dragStart = offset
            isDragging = true
        }
        guard let start = dragStart else { return }
        offset = axis.clamp(EditorCalendarAxis.offset(afterDragging: translation, from: start, rowHeight: rowHeight))
    }

    /// 指を離したとき。velocity は指の縦の速さ（ポイント／秒）。そこから滑らせる
    func endDrag(velocity: Double, rowHeight: Double, axis: EditorCalendarAxis) {
        dragStart = nil
        isDragging = false
        let initial = EditorCalendarAxis.velocity(fromDragVelocity: velocity, rowHeight: rowHeight)
        guard abs(initial) > EditorCalendarAxis.inertiaStopVelocity else { return }
        inertia = Task { @MainActor [weak self] in
            var speed = initial
            var last = Date()
            while !Task.isCancelled, abs(speed) > EditorCalendarAxis.inertiaStopVelocity {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, !Task.isCancelled else { return }
                let now = Date()
                let step = EditorCalendarAxis.inertiaStep(velocity: speed, seconds: now.timeIntervalSince(last))
                last = now
                speed = step.velocity
                self.offset = axis.clamp(self.offset + step.moved)
            }
        }
    }

    func stopInertia() {
        inertia?.cancel()
        inertia = nil
    }
}
