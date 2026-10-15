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

/// キャラクターの案の作り方（2026-10-16 H1 の案の比較）
final class CharacterDesignTests: XCTestCase {
    func testCurrentDesignIsTheH1Figure() {
        XCTAssertEqual(CharacterDesign.current.standing, .standing)
        XCTAssertEqual(CharacterDesign.current.sitting, .sitting)
        XCTAssertEqual(CharacterDesign.current.referenceHeight, 100, accuracy: 0.01)
        XCTAssertEqual(CharacterDesign.current.style.cheekOpacity, 0.85)
    }

    func testAdjustmentKeepsTheNeckAndMovesTheFaceWithTheHead() {
        let pose = CharacterPose.standing
        let smaller = pose.adjusted(CharacterPose.Adjustment(headScale: 0.8))
        XCTAssertEqual(smaller.head.center.y + smaller.head.size.height / 2, pose.head.center.y + pose.head.size.height / 2,
                       accuracy: 0.001, "頭のいちばん下（首）は動かさない")
        XCTAssertEqual(smaller.head.size.width, pose.head.size.width * 0.8, accuracy: 0.001)
        let head = CharacterPose.ellipseBounds(smaller.head)
        for part in smaller.eyes + smaller.cheeks {
            XCTAssertTrue(head.contains(CharacterPose.ellipseBounds(part)), "目とほっぺは頭と一緒に動く")
        }
        let lifted = pose.adjusted(CharacterPose.Adjustment(faceLift: 0.05))
        XCTAssertEqual(lifted.eyes[0].center.y, pose.eyes[0].center.y - 0.05 * pose.head.size.height, accuracy: 0.001)
        let merged = pose.adjusted(CharacterPose.Adjustment(armLengthScale: 0.5, armsMergeWithBody: true))
        XCTAssertTrue(merged.arms.allSatisfy(\.mergesWithBody))
        XCTAssertEqual(merged.arms[0].length, pose.arms[0].length * 0.5, accuracy: 0.001)
        XCTAssertEqual(merged.arms[0].joint, pose.arms[0].joint, "腕の付け根は動かさない")
    }

    func testDesignIsSizedByItsOwnStandingHeight() {
        let taller = CharacterDesign.current.adjusted(CharacterPose.Adjustment(legLengthScale: 1.5), style: .current)
        XCTAssertGreaterThan(taller.referenceHeight, 100)
        let layout = CharacterLayout(height: 36, design: taller, posture: .standing)
        XCTAssertEqual(layout.bodySize.height, 36, accuracy: 0.01, "○pt は案ごとの立った姿の全身の高さ")
        let noCheeks = CharacterStyle(outlineRatio: 0.035, cheekOpacity: 0)
        XCTAssertEqual(CharacterLayout(height: 36, pose: .standing, style: noCheeks).outlineWidth, 1.26, accuracy: 0.001)
    }
}

/// 時計を小さくしたときの中の文字・針・目盛り（2026-10-16 Q85）
final class HomeClockStyleTests: XCTestCase {
    func testCurrentHomeClockKeepsItsSizes() {
        let style = HomeClockStyle.standard
        XCTAssertEqual(style.centerNumberSize, 48, "今の Home の時計（外径 74％）の中央の数字は 48pt のまま")
        XCTAssertEqual(style.centerCaptionSize, 13)
        XCTAssertEqual(style.centerUnitSize, 18)
        XCTAssertEqual(style.hourHandWidth, 6)
        XCTAssertEqual(style.minuteHandWidth, 3.5)
        XCTAssertEqual(style.hourTickLength, 7)
    }

    func testSmallerClockScalesTextAndLinesButKeepsThemReadable() {
        let diameter: CGFloat = 393 * 0.45
        let style = HomeClockStyle.scaled(diameter: diameter)
        XCTAssertEqual(style.centerNumberSize, 30, accuracy: 0.5, "45％のとき数字は約 30pt（仮の基準）")
        XCTAssertEqual(style.centerCaptionSize, 11, "「出発まで」は 11pt 未満にしない")
        XCTAssertGreaterThanOrEqual(style.centerUnitSize, 11)
        XCTAssertLessThan(style.hourHandWidth, HomeClockStyle.standard.hourHandWidth, "針は時計に合わせて細く")
        XCTAssertGreaterThanOrEqual(style.hourHandWidth, HomeMetrics.minimumHourHandWidth)
        XCTAssertGreaterThanOrEqual(style.minuteHandWidth, HomeMetrics.minimumMinuteHandWidth)
        for width in [0.40, 0.45, 0.50] as [CGFloat] {
            let scaled = HomeClockStyle.scaled(diameter: 393 * width)
            XCTAssertGreaterThanOrEqual(scaled.centerCaptionSize, HomeMetrics.minimumClockText)
            XCTAssertLessThan(scaled.centerNumberSize, HomeClockStyle.standard.centerNumberSize)
        }
        XCTAssertEqual(HomeClockStyle.scaled(diameter: 1000).centerNumberSize, 48, "大きな時計でも今より大きくはしない")
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
        XCTAssertEqual(store.height, 36, "初めは第一の候補の 36pt（2026-10-16）")
        XCTAssertEqual(store.posture, .standing)
        XCTAssertTrue(store.showsClock)

        XCTAssertEqual(CharacterComparisonStore.clockWidths, [0.40, 0.45, 0.50], "時計は画面の幅の 40・45・50％を比べる（2026-10-16）")
        XCTAssertEqual(store.clockWidth, 0.45, "45％が第一の候補")
        XCTAssertEqual(CharacterComparisonStore.clockLabel(for: 0.45), "45％")

        store.height = 40
        store.posture = .sitting
        store.showsClock = false
        store.clockWidth = 0.50
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
        defaults.set("50", forKey: "TimyCueClockWidth")
        let store = CharacterComparisonStore.fromLaunchArguments(defaults)
        XCTAssertEqual(store.height, 40)
        XCTAssertEqual(store.posture, .sitting)
        XCTAssertFalse(store.showsClock)
        XCTAssertEqual(store.clockWidth, 0.50)

        defaults.set("30", forKey: "TimyCueCharacterHeight")
        defaults.set("74", forKey: "TimyCueClockWidth")
        let other = CharacterComparisonStore.fromLaunchArguments(defaults)
        XCTAssertEqual(other.height, 36, "比べる 4 つ以外の高さは使わない")
        XCTAssertEqual(other.clockWidth, 0.45, "比べる 3 つ以外の時計の大きさは使わない")
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
        let all = sample.timeline(showingEvents: 5)
        XCTAssertEqual(Self.kinds(all.rows), [
            "出発 9:15 車", "9:30 A社打合せ（強調）", "10:00 社内レビュー", "10:15 見本さんへ連絡",
            "出発 12:45 徒歩", "13:00 歯医者", "18:00 電話：見本さん",
        ])
        XCTAssertEqual(all.hiddenEvents, 0)
    }

    func testTimelineThatDoesNotFitFoldsTheRestIntoACount() {
        // Home は縦にスクロールしない。入りきらない予定は「ほか○件」（件数は予定の数で、出発の点は数えない。2026-10-16 Q84）
        let sample = CharacterComparisonSample.make(today: CalendarDay(year: 2026, month: 10, day: 15))
        let three = sample.timeline(showingEvents: 3)
        XCTAssertEqual(Self.kinds(three.rows), ["出発 9:15 車", "9:30 A社打合せ（強調）", "10:00 社内レビュー", "10:15 見本さんへ連絡"])
        XCTAssertEqual(three.hiddenEvents, 2, "歯医者（と、その出発の点）と電話。出発の点は数えない")
        let one = sample.timeline(showingEvents: 1)
        XCTAssertEqual(Self.kinds(one.rows), ["出発 9:15 車", "9:30 A社打合せ（強調）"], "主状態の予定とその出発の点はいつも出す")
        XCTAssertEqual(one.hiddenEvents, 4)
        XCTAssertEqual(Self.kinds(sample.timeline(showingEvents: 0).rows), Self.kinds(one.rows), "0 件にはしない")
    }

    func testDesignCandidatesDifferInTheIntendedWays() {
        // 1 現行・2 シンプル寄り・3 かわいさ控えめ・4 中間（2026-10-16 H1 の続き）
        XCTAssertEqual(CharacterDesignComparisonStore.Candidate.allCases.map(\.title), ["現行", "シンプル", "控えめ", "中間"])
        let current = CharacterDesign.current
        let simple = CharacterDesign.simple
        let calm = CharacterDesign.calm
        let middle = CharacterDesign.middle
        XCTAssertEqual(simple.style.cheekOpacity, 0, "シンプル寄りはほっぺなし")
        XCTAssertTrue(simple.standing.arms.allSatisfy(\.mergesWithBody), "シンプル寄りは腕を胴とひと続きにして線を減らす")
        XCTAssertLessThan(simple.standing.eyes[0].size.height, current.standing.eyes[0].size.height)
        XCTAssertLessThan(calm.standing.head.size.height / calm.referenceHeight,
                          current.standing.head.size.height / current.referenceHeight, "かわいさ控えめは頭が小さめ（全身に対して）")
        XCTAssertLessThan(calm.standing.eyes[0].center.y - calm.standing.head.center.y,
                          current.standing.eyes[0].center.y - current.standing.head.center.y, "目が少し上")
        // 中間案は、目の大きさ・ほっぺの濃さ・輪郭の太さが現行案とシンプル寄りの間
        XCTAssertTrue((simple.standing.eyes[0].size.height...current.standing.eyes[0].size.height)
            .contains(middle.standing.eyes[0].size.height))
        XCTAssertTrue((simple.style.cheekOpacity...current.style.cheekOpacity).contains(middle.style.cheekOpacity))
        XCTAssertTrue((simple.style.outlineRatio...current.style.outlineRatio).contains(middle.style.outlineRatio))
        for candidate in CharacterDesignComparisonStore.Candidate.allCases {
            let design = candidate.design
            let standing = CharacterLayout(height: 36, design: design, posture: .standing)
            XCTAssertEqual(standing.bodySize.height, 36, accuracy: 0.01, "\(candidate.title)：36pt は立った姿の全身の高さ")
            XCTAssertLessThan(CharacterLayout(height: 36, design: design, posture: .sitting).bodySize.height, 36, "座ると低くなる")
            XCTAssertTrue((1...2).contains(standing.outlineWidth), "輪郭は 1〜2pt")
            for posture in CharacterPosture.allCases {
                let pose = design.pose(posture)
                let head = CharacterPose.ellipseBounds(pose.head)
                XCTAssertTrue((pose.eyes + pose.cheeks).allSatisfy { head.contains(CharacterPose.ellipseBounds($0)) },
                              "\(candidate.title)：目とほっぺは頭の中")
            }
        }
    }

    func testDesignComparisonUsesTheFirstCandidateSizesAndLaunchArguments() {
        XCTAssertEqual(CharacterDesignComparisonStore.height, 36, "人型 36pt に固定（2026-10-16 の第一の候補）")
        XCTAssertEqual(CharacterDesignComparisonStore.clockWidth, 0.45, "時計 45％に固定")
        let store = CharacterDesignComparisonStore()
        XCTAssertEqual(store.candidate, .current)
        XCTAssertEqual(store.posture, .standing)
        XCTAssertTrue(store.showsClock)
        let defaults = UserDefaults(suiteName: "CharacterDesignComparisonTests")!
        defaults.removePersistentDomain(forName: "CharacterDesignComparisonTests")
        defaults.set("calm", forKey: "TimyCueCharacterDesign")
        defaults.set("sitting", forKey: "TimyCueCharacterPosture")
        defaults.set("NO", forKey: "TimyCueCharacterClock")
        let launched = CharacterDesignComparisonStore.fromLaunchArguments(defaults)
        XCTAssertEqual(launched.candidate, .calm)
        XCTAssertEqual(launched.posture, .sitting)
        XCTAssertFalse(launched.showsClock)
        defaults.removePersistentDomain(forName: "CharacterDesignComparisonTests")
    }

    private static func kinds(_ rows: [CharacterComparisonSample.Row]) -> [String] {
        rows.map { row -> String in
            switch row {
            case .departure(_, let minute, let transport): "出発 \(TimeText.hourMinute(minute)) \(transport)"
            case .event(let event, _, let emphasized): "\(TimeText.hourMinute(event.startMinute)) \(event.displayTitle)\(emphasized ? "（強調）" : "")"
            }
        }
    }
}
#endif
