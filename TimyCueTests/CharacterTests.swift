import XCTest
@testable import TimyCue

/// 人型キャラクター（spec §88.4・2026-10-15 H1）
final class CharacterTests: XCTestCase {
    func testStandingPoseRunsFromTheTopOfTheHeadToTheFeet() {
        let bounds = CharacterPose.standing.bounds
        XCTAssertEqual(bounds.minY, 0, accuracy: 0.01, "頭のてっぺんが 0")
        XCTAssertEqual(bounds.maxY, 100, accuracy: 0.01, "足の先が 100（立った姿の全身の高さを 100 とする単位）")
    }

    func testSittingPoseKeepsTheFeetOnTheGroundAndIsLower() {
        let bounds = CharacterPose.sitting.bounds
        XCTAssertEqual(bounds.maxY, 100, accuracy: 0.05, "座っても足の先の高さは同じ")
        XCTAssertLessThan(bounds.height, 90, "座った姿は低くなる")
        XCTAssertGreaterThan(bounds.height, 75)
    }

    func testChosenHeightIsTheStandingFullBodyHeight() {
        for height in [16, 24, 36, 40] as [CGFloat] {
            let standing = CharacterLayout(height: height, pose: .standing)
            XCTAssertEqual(standing.bodySize.height, height, accuracy: 0.01,
                           "○pt は小物を除いた体の全身の高さ（立った姿。2026-10-15 決定 Q79）")
            let sitting = CharacterLayout(height: height, pose: .sitting)
            XCTAssertEqual(sitting.bodySize.height, height * CharacterPose.sitting.bounds.height / 100, accuracy: 0.01,
                           "座った姿も同じ縮尺で描く（大きさを変えずに座る）")
            XCTAssertEqual(standing.size.height, height + standing.outlineWidth * 2, accuracy: 0.01,
                           "輪郭の線がはみ出さないよう、線の太さの分だけ周りをあける")
        }
    }

    func testOutlineStaysVisibleWhenSmallAndQuietWhenLarge() {
        XCTAssertEqual(CharacterMetrics.outlineWidth(forHeight: 16), 1, "小さくても 1pt より細くしない")
        XCTAssertEqual(CharacterMetrics.outlineWidth(forHeight: 40), 1.8, accuracy: 0.001)
        XCTAssertEqual(CharacterMetrics.outlineWidth(forHeight: 200), 2, "大きくても 2pt まで")
    }

    func testHeadIsLargeAndTheFaceSitsInsideIt() {
        for pose in [CharacterPose.standing, .sitting] {
            let head = CharacterPose.ellipseBounds(pose.head)
            XCTAssertGreaterThan(head.height, 60, "大きめの頭（全身の 6 割ほど）")
            for part in pose.eyes + pose.cheeks {
                XCTAssertTrue(head.contains(CharacterPose.ellipseBounds(part)), "目とほっぺは頭の中")
            }
        }
    }

    func testLimbsTurnAroundTheirJoints() {
        let down = CharacterPose.Limb(joint: CGPoint(x: 50, y: 50), length: 20, width: 10, angle: 0)
        XCTAssertEqual(down.center.x, 50, accuracy: 0.001)
        XCTAssertEqual(down.center.y, 60, accuracy: 0.001, "0 度は真下")
        let right = CharacterPose.Limb(joint: CGPoint(x: 50, y: 50), length: 20, width: 10, angle: -90)
        XCTAssertEqual(right.center.x, 60, accuracy: 0.001, "-90 度は右へまっすぐ（付け根のまわりに回る）")
        XCTAssertEqual(right.center.y, 50, accuracy: 0.001)
        let bounds = CharacterPose.roundedRectBounds(right.part, cornerRadius: right.width / 2)
        XCTAssertEqual(bounds.width, 20, accuracy: 0.001, "右へ倒した棒は、横に長さの分だけ")
        XCTAssertEqual(bounds.height, 10, accuracy: 0.001)
    }

    func testStandingPoseHasNoBackpackOrProps() {
        // リュックは常に背負わせない。小物は動作に要るときだけ別の層で足す（2026-10-15 決定）
        XCTAssertEqual(CharacterPose.standing.arms.count, 2)
        XCTAssertEqual(CharacterPose.standing.legs.count, 2)
        XCTAssertTrue(CharacterPose.standing.legs.allSatisfy(\.mergesWithBody), "立った姿の脚は胴とひと続きの形")
    }
}

#if TIMYCUE_DEV_TOOLS
/// H1 の比べる画面（2026-10-15 決定 Q80）。検証用のビルドだけ
final class CharacterComparisonTests: XCTestCase {
    func testComparisonOffersFourHeightsBothPosturesAndTheClock() {
        XCTAssertEqual(CharacterComparisonStore.heights, [16, 24, 36, 40])
        XCTAssertEqual(CharacterComparisonStore.label(for: 40), "約40pt", "約 40pt は画像からの推定")
        XCTAssertEqual(CharacterComparisonStore.label(for: 24), "24pt")
        let store = CharacterComparisonStore()
        XCTAssertEqual(store.height, 24)
        XCTAssertEqual(store.posture, .standing)
        XCTAssertTrue(store.showsClock)

        store.height = 40
        store.posture = .sitting
        store.showsClock = false
        XCTAssertEqual(store.posture.pose, .sitting)
        XCTAssertEqual(CharacterLayout(height: store.height, pose: store.posture.pose).bodySize.height,
                       40 * CharacterPose.sitting.bounds.height / 100, accuracy: 0.01)
        XCTAssertEqual(CharacterComparisonStore.Posture.standing.pose, .standing)
    }

    func testLaunchArgumentsChooseTheScreenshotState() {
        let defaults = UserDefaults(suiteName: "CharacterComparisonTests")!
        defaults.removePersistentDomain(forName: "CharacterComparisonTests")
        defaults.set("40", forKey: "TimyCueCharacterHeight")
        defaults.set("sitting", forKey: "TimyCueCharacterPosture")
        defaults.set("NO", forKey: "TimyCueCharacterClock")
        let store = CharacterComparisonStore.fromLaunchArguments(defaults)
        XCTAssertEqual(store.height, 40)
        XCTAssertEqual(store.posture, .sitting)
        XCTAssertFalse(store.showsClock)

        defaults.set("30", forKey: "TimyCueCharacterHeight")
        XCTAssertEqual(CharacterComparisonStore.fromLaunchArguments(defaults).height, 24, "比べる 4 つ以外の高さは使わない")
        defaults.removePersistentDomain(forName: "CharacterComparisonTests")
    }

    func testSampleShowsTodayWithDeparturePointsAndTheClockWithoutTouchingRealData() {
        let today = CalendarDay(year: 2026, month: 10, day: 15)
        let sample = CharacterComparisonSample.make(today: today)
        XCTAssertEqual(sample.dateTitle, "10月15日（木）")
        XCTAssertEqual(sample.nowText, "8:52")
        XCTAssertEqual(sample.allDayTitles, ["見本の終日予定（今日）"], "終日の予定は日付の下に（§88.2）")
        XCTAssertEqual(sample.face?.remainingMinutes, 23, "見本の A社打合せ（9:30）の出発 9:15 まで 23 分の時計")
        // 場所ありの予定は、出発の点と開始の点を別々に並べる（Q81）。場所なしは開始だけ
        let kinds = sample.rows.map { row -> String in
            switch row {
            case .departure(_, let minute, let transport): "出発 \(TimeText.hourMinute(minute)) \(transport)"
            case .event(let event, _, let emphasized): "\(TimeText.hourMinute(event.startMinute)) \(event.displayTitle)\(emphasized ? "（強調）" : "")"
            }
        }
        XCTAssertEqual(kinds, [
            "出発 9:15 車", "9:30 A社打合せ（強調）", "10:00 社内レビュー", "10:15 見本さんへ連絡",
            "出発 12:45 徒歩", "13:00 歯医者", "18:00 電話：見本さん",
        ])
    }
}
#endif
