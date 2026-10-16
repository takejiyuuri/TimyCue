import XCTest
@testable import TimyCue

/// 正式キャラクター 3 モード（spec §88.4・Q89・Q90・Q93。2026-10-16 H2 の前提作業 1）
final class CharacterModeTests: XCTestCase {
    func testEachModeWearsOnlyItsOwnGear() {
        XCTAssertEqual(CharacterMode.turtle.gear, [.shell], "亀モードは甲羅だけ")
        XCTAssertEqual(CharacterMode.human.gear, [], "人型モードは装備なし")
        XCTAssertEqual(CharacterMode.rabbit.gear, [.rabbitHood], "うさぎモードは耳の被り物（耳は必ず付ける）")
    }

    func testAllModesShareTheSameBody() {
        // 同じ人型の本体に、装備だけを着け外しする（本体の形はモードで変えない）
        let layouts = CharacterMode.allCases.map { CharacterLayout(height: 36, mode: $0) }
        for layout in layouts {
            XCTAssertEqual(layout.pose, CharacterPose.officialStanding)
            XCTAssertEqual(layout.bodySize.height, 36, accuracy: 0.01, "36pt は本体の高さ（甲羅・耳を含めない）")
            XCTAssertEqual(layout.bodySize, layouts[0].bodySize)
            XCTAssertEqual(layout.outlineWidth, layouts[0].outlineWidth)
        }
    }

    func testGearAreaIsAddedAroundTheBody() {
        let human = CharacterLayout(height: 36, mode: .human)
        let turtle = CharacterLayout(height: 36, mode: .turtle)
        let rabbit = CharacterLayout(height: 36, mode: .rabbit)
        XCTAssertEqual(human.size.height, 36 + human.outlineWidth * 2, accuracy: 0.01, "装備なしは本体と輪郭の線の分だけ")
        XCTAssertEqual(human.bodyFrame.minX, human.outlineWidth, accuracy: 0.01)
        XCTAssertGreaterThan(turtle.size.width, human.size.width, "甲羅の分だけ右へ広げる")
        XCTAssertEqual(turtle.size.height, human.size.height, accuracy: 0.01, "甲羅は本体の高さの中に収まる")
        XCTAssertEqual(turtle.bodyFrame.minX, human.bodyFrame.minX, accuracy: 0.01, "甲羅は右側なので、本体の位置は左のまま")
        XCTAssertGreaterThan(rabbit.size.height, human.size.height + 5, "耳の分だけ上へ広げる")
        XCTAssertGreaterThan(rabbit.bodyFrame.minY, human.bodyFrame.minY, "本体は耳の下")
        // 足元は枠の下の端（並べたとき足元がそろう）
        for layout in [human, turtle, rabbit] {
            XCTAssertEqual(layout.bodyFrame.maxY + layout.outlineWidth, layout.size.height, accuracy: 0.01)
        }
    }

    func testOutlineMatchesTheArtwork() {
        // 原画の輪郭は本体の高さの約 3.85％。36pt で約 1.4pt（1〜2pt に収まる）
        XCTAssertEqual(CharacterLayout(height: 36, mode: .human).outlineWidth, 1.386, accuracy: 0.01)
    }

    func testBodyHasMovableArmsAndLegsAndNoProps() {
        let pose = CharacterPose.officialStanding
        XCTAssertEqual(pose.arms.count, 2, "腕は付け根のまわりに動かせる部品（H3 の動作のため）")
        XCTAssertEqual(pose.legs.count, 2)
        XCTAssertTrue(pose.headMergesWithBody, "頭と胴はひと続き（あごの線なし）")
        XCTAssertTrue(pose.cheeks.isEmpty, "ほっぺなし")
        XCTAssertTrue(pose.frontGroups.isEmpty, "小物（カップ・スマホ・バッグ）は描かない（H3 で正式な素材を決めてから）")
        let head = CharacterPose.ellipseBounds(pose.head)
        for eye in pose.eyes {
            XCTAssertTrue(head.contains(CharacterPose.ellipseBounds(eye)), "目は頭の中")
        }
        XCTAssertEqual(pose.legs[0].angle, 0, "立った姿の脚はまっすぐ")
        XCTAssertEqual(pose.legs[0].joint.x + pose.legs[1].joint.x, pose.head.center.x * 2, accuracy: 0.01, "左右対称")
        XCTAssertEqual(pose.arms[0].angle, -pose.arms[1].angle, accuracy: 0.001)
    }

    func testShellSitsBehindTheRightSideOfTheBody() {
        let pose = CharacterPose.officialStanding
        let shell = OfficialCharacter.gear.shell
        let shellBounds = CharacterPose.ellipseBounds(shell.shape)
        XCTAssertGreaterThan(shell.shape.center.x, pose.head.center.x, "甲羅は右側（原画の亀「立つ」）")
        XCTAssertGreaterThan(shellBounds.minY, pose.bounds.minY, "甲羅は頭のてっぺんより下")
        XCTAssertLessThanOrEqual(shellBounds.maxY, pose.bounds.maxY, "甲羅は足元より下へ出ない")
        // 模様の線は甲羅の中（甲羅の外へは描かない。描くときも甲羅の形で切る）
        let slack: CGFloat = 0.5
        for line in shell.patternLines() {
            for point in line {
                XCTAssertTrue(shellBounds.insetBy(dx: -slack, dy: -slack).contains(point))
            }
        }
    }

    func testRabbitHoodEarsStandAboveTheHead() {
        let pose = CharacterPose.officialStanding
        let hood = OfficialCharacter.gear.rabbitHood
        XCTAssertEqual(hood.ears.count, 2)
        XCTAssertEqual(hood.earInners.count, 2)
        let headTop = pose.head.center.y - pose.head.size.height / 2
        for (ear, inner) in zip(hood.ears, hood.earInners) {
            XCTAssertLessThan(CharacterPose.ellipseBounds(ear).minY, headTop - 10, "耳は頭の上に立つ")
            XCTAssertGreaterThan(CharacterPose.ellipseBounds(ear).maxY, headTop, "耳の根元は頭に隠れる")
            XCTAssertTrue(CharacterPose.ellipseBounds(ear).contains(inner.center), "ピンクは耳の内側")
            XCTAssertGreaterThan(CharacterPose.ellipseBounds(inner).minY, CharacterPose.ellipseBounds(ear).minY,
                                 "ピンクは耳の先まで届かない")
        }
        XCTAssertLessThan(hood.ears[0].rotation, 0, "左の耳は上が左へ開く")
        XCTAssertGreaterThan(hood.ears[1].rotation, 0, "右の耳は上が右へ開く")
        // 顔まわりの線は頭の中（左の端から額を通って右の端まで）
        let line = hood.faceLine()
        let head = CharacterPose.ellipseBounds(pose.head)
        XCTAssertTrue(line.allSatisfy { head.contains($0) })
        XCTAssertLessThan(line[0].x, line[line.count - 1].x)
        XCTAssertLessThan(line[line.count / 2].y, line[0].y, "真ん中（額）がいちばん上")
    }

    func testOldDesignsAreUnchanged() {
        // H1 の案（履歴）は前の色・線のまま
        XCTAssertEqual(CharacterDesign.simple2.style.palette, .h1)
        XCTAssertEqual(CharacterStyle.current.palette, .h1)
        XCTAssertEqual(OfficialCharacter.style.palette, .official)
    }
}
