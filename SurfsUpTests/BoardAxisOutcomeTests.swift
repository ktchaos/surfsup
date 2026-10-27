import Foundation
import Testing
import Vision
@testable import SurfsUp

struct BoardAxisOutcomeTests {
    @Test func noseDirectlyAboveTailIsZero() {
        let direction = BoardAxisDirection.make(tailX: 0.40, tailY: 0.30, noseX: 0.40, noseY: 0.80)

        #expect(direction?.angleDegrees == 0)
    }

    @Test func noseToTheViewersRightIsPositive() {
        let direction = BoardAxisDirection.make(tailX: 0.40, tailY: 0.50, noseX: 0.70, noseY: 0.50)

        #expect(direction?.angleDegrees == 90)
        #expect((direction?.angleDegrees ?? 0) > 0)
    }

    @Test func noseToTheViewersLeftIsNegative() {
        let direction = BoardAxisDirection.make(tailX: 0.60, tailY: 0.50, noseX: 0.20, noseY: 0.50)

        #expect(direction?.angleDegrees == -90)
        #expect((direction?.angleDegrees ?? 0) < 0)
    }

    @Test func angleUsesTheUprightAtan2Convention() {
        let tailX = 0.25
        let tailY = 0.70
        let noseX = 0.55
        let noseY = 0.35
        let direction = BoardAxisDirection.make(tailX: tailX, tailY: tailY, noseX: noseX, noseY: noseY)
        let expected = atan2(noseX - tailX, noseY - tailY) * 180 / .pi

        #expect(direction?.angleDegrees == expected)
        #expect((direction?.angleDegrees ?? -200) > -180)
        #expect((direction?.angleDegrees ?? 200) <= 180)
    }

    @Test func reversalIsADifferentDirection() {
        let forward = BoardAxisDirection.make(tailX: 0.20, tailY: 0.40, noseX: 0.80, noseY: 0.55)
        let reversed = BoardAxisDirection.make(tailX: 0.80, tailY: 0.55, noseX: 0.20, noseY: 0.40)

        #expect(forward?.angleDegrees != reversed?.angleDegrees)
        let delta = abs((forward?.angleDegrees ?? 0) - (reversed?.angleDegrees ?? 0))
        let folded = min(delta, 360 - delta)
        #expect(abs(folded - 180) < 1e-9)
    }

    @Test func noseDirectlyBelowTailStaysInsideTheAtan2Range() {
        let direction = BoardAxisDirection.make(tailX: 0.50, tailY: 0.80, noseX: 0.50, noseY: 0.20)

        #expect(direction?.angleDegrees == 180)
        #expect((direction?.angleDegrees ?? 0) > -180)
        #expect((direction?.angleDegrees ?? 0) <= 180)
    }

    @Test func coincidentPointsAreNotADirection() {
        #expect(BoardAxisDirection.make(tailX: 0.50, tailY: 0.50, noseX: 0.50, noseY: 0.50) == nil)
    }

    @Test func readingTheSamePointsTwiceReturnsTheSameAngle() {
        let first = BoardAxisDirection.make(tailX: 0.15, tailY: 0.25, noseX: 0.45, noseY: 0.65)
        let second = BoardAxisDirection.make(tailX: 0.15, tailY: 0.25, noseX: 0.45, noseY: 0.65)

        #expect(first == second)
        #expect(first?.angleDegrees == second?.angleDegrees)
    }

    @Test func scheduleAcceptsFiveClipsAndAnEmptySamplingNote() throws {
        let schedule = try BoardAxisSchedule.decode(scheduleJSON())

        #expect(schedule.clips.count == 5)
        #expect(schedule.clips.allSatisfy { $0.frames.count == 5 })
        #expect(schedule.clips[0].frames[0].samplingNote == "")
    }

    @Test func scheduleRejectsTheWrongClipOrFrameCount() {
        #expect(throws: BoardAxisDocumentError.clipCount) {
            try BoardAxisSchedule.decode(scheduleJSON(clipCount: 4))
        }
        #expect(throws: BoardAxisDocumentError.frameCount) {
            try BoardAxisSchedule.decode(scheduleJSON(framesPerClip: 4))
        }
    }

    @Test func scheduleRejectsDuplicateDurationsAndFrameIds() {
        #expect(throws: BoardAxisDocumentError.duplicateClipDuration) {
            try BoardAxisSchedule.decode(scheduleJSON(durations: [10, 10, 30, 40, 50]))
        }
        #expect(throws: BoardAxisDocumentError.duplicateFrameId) {
            try BoardAxisSchedule.decode(scheduleJSON(repeatFrameId: "clip0-frame0"))
        }
    }

    @Test func scheduleRejectsTimestampsOutsideTheHalfOpenRangeOrOutOfOrder() {
        #expect(throws: BoardAxisDocumentError.timestampRange) {
            try BoardAxisSchedule.decode(scheduleJSON(timestampOverride: (clip: 0, frame: 4, timestamp: 10)))
        }
        #expect(throws: BoardAxisDocumentError.timestampOrder) {
            try BoardAxisSchedule.decode(scheduleJSON(timestampOverride: (clip: 0, frame: 2, timestamp: 0.5)))
        }
    }

    @Test func scheduleRejectsDirectionAndOutcomeFields() {
        #expect(throws: BoardAxisDocumentError.forbiddenField) {
            try BoardAxisSchedule.decode(scheduleJSON(extraFrameField: ("tailX", 0.2)))
        }
        #expect(throws: BoardAxisDocumentError.forbiddenField) {
            try BoardAxisSchedule.decode(scheduleJSON(extraFrameField: ("outcome", "match")))
        }
    }

    @Test func labelsMatchTheScheduleAndRejectASignField() throws {
        let schedule = try BoardAxisSchedule.decode(scheduleJSON())
        let labels = try BoardAxisLabelDocument.decode(labelJSON(schedule: schedule), schedule: schedule)

        #expect(labels.labels.count == 25)
        #expect(labels.labels.filter { $0.judgment == .unassessable }.count == 1)
        #expect(throws: BoardAxisDocumentError.forbiddenField) {
            try BoardAxisLabelDocument.decode(
                labelJSON(schedule: schedule, extraField: ("expectedSign", "nose")),
                schedule: schedule
            )
        }
    }

    @Test func directedLabelRejectsAReasonCoincidentPointsAndOutOfRangeCoordinates() throws {
        let schedule = try BoardAxisSchedule.decode(scheduleJSON())
        #expect(throws: BoardAxisDocumentError.unexpectedImageReason) {
            try BoardAxisLabelDocument.decode(
                labelJSON(schedule: schedule, directedImageReason: "visible"),
                schedule: schedule
            )
        }
        #expect(throws: BoardAxisDocumentError.coincidentPoints) {
            try BoardAxisLabelDocument.decode(
                labelJSON(schedule: schedule, noseX: 0.2, noseY: 0.3, tailX: 0.2, tailY: 0.3),
                schedule: schedule
            )
        }
        #expect(throws: BoardAxisDocumentError.coordinateRange) {
            try BoardAxisLabelDocument.decode(
                labelJSON(schedule: schedule, noseX: 1.1),
                schedule: schedule
            )
        }
    }

    @Test func unassessableLabelRequiresAReasonAndForbidsCoordinates() throws {
        let schedule = try BoardAxisSchedule.decode(scheduleJSON())
        #expect(throws: BoardAxisDocumentError.missingImageReason) {
            try BoardAxisLabelDocument.decode(
                labelJSON(schedule: schedule, emptyUnassessableReason: true),
                schedule: schedule
            )
        }
        #expect(throws: BoardAxisDocumentError.unexpectedCoordinates) {
            try BoardAxisLabelDocument.decode(
                labelJSON(schedule: schedule, unassessableCoordinate: true),
                schedule: schedule
            )
        }
    }

    @Test func labelDocumentForbidsDetectorFieldsAndIncompleteCoverage() throws {
        let schedule = try BoardAxisSchedule.decode(scheduleJSON())
        #expect(throws: BoardAxisDocumentError.forbiddenField) {
            try BoardAxisLabelDocument.decode(
                labelJSON(schedule: schedule, extraField: ("angleDegrees", 12)),
                schedule: schedule
            )
        }
        #expect(throws: BoardAxisDocumentError.forbiddenField) {
            try BoardAxisLabelDocument.decode(
                labelJSON(schedule: schedule, extraField: ("outcome", "match")),
                schedule: schedule
            )
        }
        #expect(throws: BoardAxisDocumentError.forbiddenField) {
            try BoardAxisLabelDocument.decode(
                labelJSON(schedule: schedule, extraField: ("cornerTopLeftX", 0.1)),
                schedule: schedule
            )
        }
        #expect(throws: BoardAxisDocumentError.forbiddenField) {
            try BoardAxisLabelDocument.decode(
                labelJSON(schedule: schedule, extraField: ("oppositeLean", false)),
                schedule: schedule
            )
        }
        #expect(throws: BoardAxisDocumentError.labelCoverage) {
            try BoardAxisLabelDocument.decode(labelJSON(schedule: schedule, dropLast: true), schedule: schedule)
        }
    }

    @Test func frozenRectangleRequestUsesThePredeclaredGates() {
        let request = BoardAxisRectangleRequest.make()

        #expect(request.minimumAspectRatio == 0.05)
        #expect(request.maximumAspectRatio == 0.40)
        #expect(request.minimumSize == 0.02)
        #expect(request.quadratureTolerance == 30)
        #expect(request.minimumConfidence == 0)
        #expect(request.maximumObservations == 0)
    }

    @Test func noQuadrilateralIsNoCandidate() {
        let status = BoardAxisCandidateSelection.select(
            quadrilaterals: [],
            ankle: .point(BoardAxisPoint(x: 0.20, y: 0.30))
        )

        #expect(status == .noCandidate(reason: BoardAxisCandidateSelection.noQuadrilateralReason))
    }

    @Test func equalAreaTieIsNoCandidate() {
        let status = BoardAxisCandidateSelection.select(
            quadrilaterals: [horizontalBoard(x0: 0.10, x1: 0.70), horizontalBoard()],
            ankle: .point(BoardAxisPoint(x: 0.20, y: 0.30))
        )

        #expect(status == .noCandidate(reason: BoardAxisCandidateSelection.equalAreaReason))
    }

    @Test func strictlyLargestAreaIsKept() {
        let status = BoardAxisCandidateSelection.select(
            quadrilaterals: [horizontalBoard(x0: 0, x1: 0.30), horizontalBoard()],
            ankle: .point(BoardAxisPoint(x: 0.20, y: 0.30))
        )

        guard case .directed(let tail, let nose, let corners) = status else {
            Issue.record("Expected the larger quadrilateral")
            return
        }
        #expect(tail == BoardAxisPoint(x: 0.20, y: 0.50))
        #expect(nose == BoardAxisPoint(x: 0.80, y: 0.50))
        #expect(corners == horizontalBoard())
    }

    @Test func longAxisJoinsMidpointsOfTheShorterOppositeSides() {
        let horizontal = BoardAxisCandidateSelection.select(
            quadrilaterals: [horizontalBoard()],
            ankle: .point(BoardAxisPoint(x: 0.20, y: 0.30))
        )
        let vertical = BoardAxisCandidateSelection.select(
            quadrilaterals: [verticalBoard()],
            ankle: .point(BoardAxisPoint(x: 0.50, y: 0.22))
        )

        #expect(horizontal == .directed(
            tail: BoardAxisPoint(x: 0.20, y: 0.50),
            nose: BoardAxisPoint(x: 0.80, y: 0.50),
            corners: horizontalBoard()
        ))
        #expect(vertical == .directed(
            tail: BoardAxisPoint(x: 0.50, y: 0.20),
            nose: BoardAxisPoint(x: 0.50, y: 0.80),
            corners: verticalBoard()
        ))
    }

    @Test func candidateFileIsAnArrayOfContractRecords() throws {
        let directed = BoardAxisCandidate(
            frameId: "example-1",
            status: .directed(
                tail: BoardAxisPoint(x: 0.40, y: 0.38),
                nose: BoardAxisPoint(x: 0.63, y: 0.49),
                corners: BoardAxisQuadrilateral(
                    topLeft: BoardAxisPoint(x: 0.42, y: 0.51),
                    topRight: BoardAxisPoint(x: 0.61, y: 0.47),
                    bottomLeft: BoardAxisPoint(x: 0.38, y: 0.40),
                    bottomRight: BoardAxisPoint(x: 0.64, y: 0.36)
                )
            )
        )
        let absent = BoardAxisCandidate(
            frameId: "example-2",
            status: .noCandidate(reason: "No quadrilateral passed the frozen rectangle gates.")
        )

        let data = try BoardAxisCandidateRunner.encode([directed, absent])
        let records = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let directedKeys: Set<String> = [
            "frameId", "status", "tailX", "tailY", "noseX", "noseY",
            "cornerTopLeftX", "cornerTopLeftY", "cornerTopRightX", "cornerTopRightY",
            "cornerBottomLeftX", "cornerBottomLeftY", "cornerBottomRightX", "cornerBottomRightY",
        ]

        #expect(records.count == 2)
        #expect(Set(records[0].keys) == directedKeys)
        #expect(records[0]["frameId"] as? String == "example-1")
        #expect(records[0]["status"] as? String == "directed")
        #expect(records[0]["tailX"] as? Double == 0.40)
        #expect(records[0]["tailY"] as? Double == 0.38)
        #expect(records[0]["noseX"] as? Double == 0.63)
        #expect(records[0]["noseY"] as? Double == 0.49)
        #expect(records[0]["cornerTopLeftX"] as? Double == 0.42)
        #expect(records[0]["cornerTopLeftY"] as? Double == 0.51)
        #expect(records[0]["cornerTopRightX"] as? Double == 0.61)
        #expect(records[0]["cornerTopRightY"] as? Double == 0.47)
        #expect(records[0]["cornerBottomLeftX"] as? Double == 0.38)
        #expect(records[0]["cornerBottomLeftY"] as? Double == 0.40)
        #expect(records[0]["cornerBottomRightX"] as? Double == 0.64)
        #expect(records[0]["cornerBottomRightY"] as? Double == 0.36)
        #expect(Set(records[1].keys) == ["frameId", "status", "reason"])
        #expect(records[1]["frameId"] as? String == "example-2")
        #expect(records[1]["status"] as? String == "noCandidate")
        #expect(records[1]["reason"] as? String == "No quadrilateral passed the frozen rectangle gates.")
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("["))
        for key in ["candidates", "judgment", "imageReason", "expectedSign", "outcome", "angleDegrees", "angleDeltaDegrees"] {
            #expect(!text.contains("\"\(key)\""))
        }
    }

    @Test func equalSidePairLengthIsNoCandidate() {
        let square = BoardAxisQuadrilateral(
            topLeft: BoardAxisPoint(x: 0.20, y: 0.60),
            topRight: BoardAxisPoint(x: 0.60, y: 0.60),
            bottomLeft: BoardAxisPoint(x: 0.20, y: 0.20),
            bottomRight: BoardAxisPoint(x: 0.60, y: 0.20)
        )
        let status = BoardAxisCandidateSelection.select(
            quadrilaterals: [square],
            ankle: .point(BoardAxisPoint(x: 0.30, y: 0.30))
        )

        #expect(status == .noCandidate(reason: BoardAxisCandidateSelection.equalSidePairReason))
    }

    @Test func bothAnklesUseTheirMidpointAndOneAnkleStillEmitsAVector() throws {
        let both = try ankleResolution(leftX: 0.18, rightX: 0.22, timestamp: 0.5)
        let one = try ankleResolution(leftX: 0.20, rightX: nil, timestamp: 0.5)

        #expect(both == .point(BoardAxisPoint(x: 0.20, y: 0.30)))
        #expect(BoardAxisCandidateSelection.select(quadrilaterals: [horizontalBoard()], ankle: both) == .directed(
            tail: BoardAxisPoint(x: 0.20, y: 0.50),
            nose: BoardAxisPoint(x: 0.80, y: 0.50),
            corners: horizontalBoard()
        ))
        #expect(one == .point(BoardAxisPoint(x: 0.20, y: 0.30)))
        #expect(BoardAxisCandidateSelection.select(quadrilaterals: [horizontalBoard()], ankle: one) == .directed(
            tail: BoardAxisPoint(x: 0.20, y: 0.50),
            nose: BoardAxisPoint(x: 0.80, y: 0.50),
            corners: horizontalBoard()
        ))
    }

    @Test func neitherAnkleOrAMissingSampleIsNoCandidate() throws {
        let neither = try ankleResolution(leftX: nil, rightX: nil, timestamp: 0.5)
        let missing = try ankleResolution(leftX: 0.20, rightX: 0.24, timestamp: 2)

        #expect(neither == .noAnkle)
        #expect(BoardAxisCandidateSelection.select(quadrilaterals: [horizontalBoard()], ankle: neither) == .noCandidate(
            reason: BoardAxisCandidateSelection.noAnkleReason
        ))
        #expect(missing == .missingSample)
        #expect(BoardAxisCandidateSelection.select(quadrilaterals: [horizontalBoard()], ankle: missing) == .noCandidate(
            reason: BoardAxisCandidateSelection.missingSampleReason
        ))
    }

    @Test func equalEndpointDistanceIsNoCandidate() {
        let status = BoardAxisCandidateSelection.select(
            quadrilaterals: [horizontalBoard(x0: 0.25, x1: 0.75)],
            ankle: .point(BoardAxisPoint(x: 0.50, y: 0.50))
        )

        #expect(status == .noCandidate(reason: BoardAxisCandidateSelection.equalDistanceReason))
    }

    @Test func candidateCopiedFromAHumanPointIsRejected() throws {
        let copied = BoardAxisCandidateSelection.select(
            quadrilaterals: [horizontalBoard()],
            ankle: .point(BoardAxisPoint(x: 0.20, y: 0.30))
        )

        #expect(throws: BoardAxisCandidateError.copiedFromHumanLabel) {
            try BoardAxisCandidateSelection.rejectEndpointsCopied(
                fromHumanTail: BoardAxisPoint(x: 0.20, y: 0.50),
                humanNose: BoardAxisPoint(x: 0.80, y: 0.50),
                candidate: copied
            )
        }
        try BoardAxisCandidateSelection.rejectEndpointsCopied(
            fromHumanTail: BoardAxisPoint(x: 0.10, y: 0.10),
            humanNose: BoardAxisPoint(x: 0.15, y: 0.15),
            candidate: copied
        )
    }

    @Test func ambiguousEvidenceStopsAndALabelPathFailsBeforeWriting() async throws {
        let duration = 10.0
        let first = try evidenceRecord(duration: duration, ankleX: 0.20)
        let different = try evidenceRecord(duration: duration, ankleX: 0.40)
        #expect(throws: BoardAxisCandidateError.ambiguousEvidence(duration)) {
            try BoardAxisCandidateSelection.timeline(forClipDuration: duration, records: [first, different])
        }
        #expect(throws: BoardAxisCandidateError.missingEvidence(duration)) {
            try BoardAxisCandidateSelection.timeline(forClipDuration: duration, records: [])
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("board-axis-phase-a-\(UUID().uuidString).json")
        let base = BoardAxisCandidateRunner.Input(
            scheduleURL: URL(fileURLWithPath: "/does/not/matter-schedule.json"),
            videoDirectoryURL: URL(fileURLWithPath: "/does/not/matter-videos"),
            evidenceDirectoryURL: URL(fileURLWithPath: "/does/not/matter-evidence"),
            candidatesURL: output,
            labelURL: nil,
            manifestURL: nil
        )
        var withLabel = base
        withLabel.labelURL = URL(fileURLWithPath: "/does/not/matter-labels.json")
        await #expect(throws: BoardAxisCandidateError.forbiddenLabelInput) {
            try await BoardAxisCandidateRunner.run(withLabel)
        }
        var withManifest = base
        withManifest.manifestURL = URL(fileURLWithPath: "/does/not/matter-manifest.json")
        await #expect(throws: BoardAxisCandidateError.forbiddenLabelInput) {
            try await BoardAxisCandidateRunner.run(withManifest)
        }
        #expect(FileManager.default.fileExists(atPath: output.path) == false)
        let emptyInvocation = try BoardAxisCandidateRunner.invocation(from: [:])
        #expect(emptyInvocation == nil)
        #expect(throws: BoardAxisCandidateError.forbiddenLabelInput) {
            try BoardAxisCandidateRunner.invocation(from: ["BOARD_AXIS_LABELS": "/labels.json"])
        }
        #expect(throws: BoardAxisCandidateError.forbiddenLabelInput) {
            try BoardAxisCandidateRunner.invocation(from: ["BOARD_AXIS_MANIFEST": "/manifest.json"])
        }
    }

    @Test func humanUnassessableTakesPrecedenceOverADirectedCandidate() throws {
        let outcome = try BoardAxisOutcome.assign(row(
            id: "frame-unassessable",
            label: unassessableLabel("frame-unassessable"),
            candidate: directedCandidate("frame-unassessable", reversed: false),
            identity: .liesAlongBoard,
            agreement: .agrees
        ))

        #expect(outcome.outcome == .unassessable)
        #expect(!outcome.reason.isEmpty)
        #expect(outcome.angleDeltaDegrees == nil)
    }

    @Test func missingCandidateProducesNoCandidate() throws {
        let outcome = try BoardAxisOutcome.assign(row(
            id: "frame-absent",
            label: directedLabel("frame-absent", reversed: false),
            candidate: BoardAxisCandidate(frameId: "frame-absent", status: .noCandidate(reason: BoardAxisCandidateSelection.noQuadrilateralReason)),
            identity: .liesAlongBoard,
            agreement: .agrees
        ))

        #expect(outcome.outcome == .noCandidate)
        #expect(outcome.reason == BoardAxisCandidateSelection.noQuadrilateralReason)
        #expect(outcome.angleDeltaDegrees == nil)
    }

    @Test func offBoardQuadrilateralCannotMatchOrMismatch() throws {
        let agreed = try BoardAxisOutcome.assign(row(
            id: "frame-off-agree",
            label: directedLabel("frame-off-agree", reversed: false),
            candidate: directedCandidate("frame-off-agree", reversed: false),
            identity: .doesNotLieAlongBoard,
            agreement: .agrees
        ))
        let reversed = try BoardAxisOutcome.assign(row(
            id: "frame-off-reverse",
            label: directedLabel("frame-off-reverse", reversed: false),
            candidate: directedCandidate("frame-off-reverse", reversed: true),
            identity: .doesNotLieAlongBoard,
            agreement: .disagrees
        ))

        #expect(agreed.outcome == .noCandidate)
        #expect(reversed.outcome == .noCandidate)
        #expect(agreed.angleDeltaDegrees == nil)
        #expect(reversed.angleDeltaDegrees == nil)
        #expect(agreed.reason == BoardAxisOutcome.offBoardReason)
    }

    @Test func onBoardAgreementIsMatchAndReversalIsMismatch() throws {
        let match = try BoardAxisOutcome.assign(row(
            id: "frame-match",
            label: directedLabel("frame-match", reversed: false),
            candidate: directedCandidate("frame-match", reversed: false),
            identity: .liesAlongBoard,
            agreement: .agrees
        ))
        let mismatch = try BoardAxisOutcome.assign(row(
            id: "frame-mismatch",
            label: directedLabel("frame-mismatch", reversed: false),
            candidate: directedCandidate("frame-mismatch", reversed: true),
            identity: .liesAlongBoard,
            agreement: .disagrees
        ))

        #expect(match.outcome == .match)
        #expect(mismatch.outcome == .mismatch)
        #expect(abs((match.angleDeltaDegrees ?? 1)) < 1e-9)
        #expect(abs((mismatch.angleDeltaDegrees ?? 0) - 180) < 1e-6)
        #expect(!match.reason.isEmpty)
        #expect(!mismatch.reason.isEmpty)
    }

    @Test func angleDeltaDoesNotAssignTheOutcome() throws {
        let reversedButReviewerAgrees = try BoardAxisOutcome.assign(row(
            id: "frame-delta-ignored",
            label: directedLabel("frame-delta-ignored", reversed: false),
            candidate: directedCandidate("frame-delta-ignored", reversed: true),
            identity: .liesAlongBoard,
            agreement: .agrees
        ))

        #expect(reversedButReviewerAgrees.outcome == .match)
        #expect(abs((reversedButReviewerAgrees.angleDeltaDegrees ?? 0) - 180) < 1e-6)
        #expect(throws: BoardAxisOutcomeError.identityNotReviewed) {
            try BoardAxisOutcome.assign(row(
                id: "frame-unreviewed",
                label: directedLabel("frame-unreviewed", reversed: false),
                candidate: directedCandidate("frame-unreviewed", reversed: false),
                identity: .notReviewed,
                agreement: .agrees
            ))
        }
    }

    @Test func everyFrameStaysInTheOutcomeList() throws {
        let rows = [
            row(id: "frame-1", label: unassessableLabel("frame-1"), candidate: directedCandidate("frame-1", reversed: false), identity: .liesAlongBoard, agreement: .agrees),
            row(id: "frame-2", label: directedLabel("frame-2", reversed: false), candidate: BoardAxisCandidate(frameId: "frame-2", status: .noCandidate(reason: BoardAxisCandidateSelection.noAnkleReason)), identity: .notReviewed, agreement: .notReviewed),
            row(id: "frame-3", label: directedLabel("frame-3", reversed: false), candidate: directedCandidate("frame-3", reversed: false), identity: .doesNotLieAlongBoard, agreement: .agrees),
            row(id: "frame-4", label: directedLabel("frame-4", reversed: false), candidate: directedCandidate("frame-4", reversed: false), identity: .liesAlongBoard, agreement: .agrees),
            row(id: "frame-5", label: directedLabel("frame-5", reversed: false), candidate: directedCandidate("frame-5", reversed: true), identity: .liesAlongBoard, agreement: .disagrees),
        ]

        let outcomes = try BoardAxisOutcome.assignAll(rows)

        #expect(outcomes.map(\.frameId) == rows.map(\.frameId))
        #expect(outcomes.map(\.outcome) == [.unassessable, .noCandidate, .noCandidate, .match, .mismatch])
        #expect(outcomes.filter { $0.outcome == .unassessable || $0.outcome == .noCandidate }.allSatisfy { $0.angleDeltaDegrees == nil })
        #expect(outcomes.filter { $0.outcome == .match || $0.outcome == .mismatch }.allSatisfy { $0.angleDeltaDegrees != nil })
    }

    @Test func presentationTimeIsKeptWhenSampleDurationIsMissing() {
        let samples = [
            BoardAxisDecodedSampleTiming(presentationTime: 2.033333333333333, duration: .nan),
            BoardAxisDecodedSampleTiming(presentationTime: 1.9666666666666666, duration: .nan),
            BoardAxisDecodedSampleTiming(presentationTime: 2.0, duration: .nan),
        ]

        let windows = BoardAxisCandidateRunner.sampleWindows(samples: samples, clipDuration: 31.600907029478456)

        #expect(windows.map(\.start) == [1.9666666666666666, 2.0, 2.033333333333333])
        #expect(windows[1].end == 2.033333333333333)
        #expect(windows[1].start <= 2.0 && 2.0 < windows[1].end)
        #expect(!(windows[0].start <= 2.0 && 2.0 < windows[0].end))
        #expect(windows[2].end == 31.600907029478456)
    }
}

private func horizontalBoard(x0: Double = 0.20, x1: Double = 0.80) -> BoardAxisQuadrilateral {
    BoardAxisQuadrilateral(
        topLeft: BoardAxisPoint(x: x0, y: 0.52),
        topRight: BoardAxisPoint(x: x1, y: 0.52),
        bottomLeft: BoardAxisPoint(x: x0, y: 0.48),
        bottomRight: BoardAxisPoint(x: x1, y: 0.48)
    )
}

private func verticalBoard() -> BoardAxisQuadrilateral {
    BoardAxisQuadrilateral(
        topLeft: BoardAxisPoint(x: 0.48, y: 0.80),
        topRight: BoardAxisPoint(x: 0.52, y: 0.80),
        bottomLeft: BoardAxisPoint(x: 0.48, y: 0.20),
        bottomRight: BoardAxisPoint(x: 0.52, y: 0.20)
    )
}

private func ankleResolution(leftX: Double?, rightX: Double?, timestamp: TimeInterval) throws -> BoardAxisAnkleResolution {
    var landmarks: [Landmark] = []
    if let leftX, let left = Landmark(joint: .leftAnkle, x: leftX, y: 0.30, confidence: 1) {
        landmarks.append(left)
    }
    if let rightX, let right = Landmark(joint: .rightAnkle, x: rightX, y: 0.30, confidence: 1) {
        landmarks.append(right)
    }
    let body = landmarks.isEmpty ? nil : BodyObservation(landmarks: landmarks, selectionArea: 0.01)
    let observation = try #require(FrameObservation(start: 0, end: 1, clipDuration: 5, body: body))
    let timeline = try #require(PoseTimeline(clipDuration: 5, observations: [observation]))
    return BoardAxisCandidateSelection.ankleResolution(at: timestamp, in: timeline)
}

private func evidenceRecord(duration: TimeInterval, ankleX: Double) throws -> EvidenceRecord {
    let landmark = try #require(Landmark(joint: .leftAnkle, x: ankleX, y: 0.20, confidence: 1))
    let body = try #require(BodyObservation(landmarks: [landmark], selectionArea: 0.01))
    let observation = try #require(FrameObservation(start: 0, end: duration, clipDuration: duration, body: body))
    let timeline = try #require(PoseTimeline(clipDuration: duration, observations: [observation]))
    return try #require(EvidenceRecord(timeline: timeline, elapsedSeconds: 1, decodedFrameCount: 1, attemptedFrameCount: 1))
}

private func directedLabel(_ frameId: String, reversed: Bool) -> BoardAxisLabel {
    BoardAxisLabel(
        frameId: frameId,
        judgment: .directed,
        tailX: reversed ? 0.80 : 0.20,
        tailY: 0.50,
        noseX: reversed ? 0.20 : 0.80,
        noseY: 0.50,
        imageReason: nil
    )
}

private func unassessableLabel(_ frameId: String) -> BoardAxisLabel {
    BoardAxisLabel(
        frameId: frameId,
        judgment: .unassessable,
        imageReason: "The two ends cannot be distinguished."
    )
}

private func directedCandidate(_ frameId: String, reversed: Bool) -> BoardAxisCandidate {
    BoardAxisCandidate(
        frameId: frameId,
        status: .directed(
            tail: BoardAxisPoint(x: reversed ? 0.80 : 0.20, y: 0.50),
            nose: BoardAxisPoint(x: reversed ? 0.20 : 0.80, y: 0.50),
            corners: horizontalBoard()
        )
    )
}

private func row(
    id: String,
    label: BoardAxisLabel,
    candidate: BoardAxisCandidate,
    identity: BoardAxisBoardIdentity,
    agreement: BoardAxisDirectionAgreement
) -> BoardAxisOutcomeRow {
    BoardAxisOutcomeRow(
        frameId: id,
        label: label,
        candidate: candidate,
        identity: identity,
        directionAgreement: agreement
    )
}

private let scheduleHash = String(repeating: "ab", count: 32)

private func scheduleJSON(
    clipCount: Int = 5,
    framesPerClip: Int = 5,
    durations: [Double]? = nil,
    repeatFrameId: String? = nil,
    timestampOverride: (clip: Int, frame: Int, timestamp: Double)? = nil,
    extraFrameField: (String, Any)? = nil
) -> Data {
    let resolvedDurations = durations ?? (0..<clipCount).map { Double(($0 + 1) * 10) }
    let clips: [[String: Any]] = (0..<clipCount).map { clip in
        let frames: [[String: Any]] = (0..<framesPerClip).map { frame in
            var object: [String: Any] = [
                "frameId": clip == 1 && frame == 0 ? (repeatFrameId ?? "clip\(clip)-frame\(frame)") : "clip\(clip)-frame\(frame)",
                "timestamp": Double(frame) + 0.5,
                "samplingNote": frame == 0 ? "" : "distant",
            ]
            if let timestampOverride, timestampOverride.clip == clip, timestampOverride.frame == frame {
                object["timestamp"] = timestampOverride.timestamp
            }
            if clip == 0, frame == 0, let extraFrameField {
                object[extraFrameField.0] = extraFrameField.1
            }
            return object
        }
        return [
            "sourceFilename": "clip\(clip).mp4",
            "sourceSha256": scheduleHash,
            "clipDuration": resolvedDurations[clip],
            "frames": frames,
        ]
    }
    return try! JSONSerialization.data(withJSONObject: ["clips": clips])
}

private func labelJSON(
    schedule: BoardAxisSchedule,
    extraField: (String, Any)? = nil,
    directedImageReason: String? = nil,
    noseX: Double = 0.7,
    noseY: Double = 0.6,
    tailX: Double = 0.2,
    tailY: Double = 0.3,
    emptyUnassessableReason: Bool = false,
    unassessableCoordinate: Bool = false,
    dropLast: Bool = false
) -> Data {
    var frameIds = schedule.frameIds
    if dropLast { frameIds.removeLast() }
    let labels: [[String: Any]] = frameIds.enumerated().map { index, frameId in
        if index == 0 {
            var object: [String: Any] = [
                "frameId": frameId,
                "judgment": "unassessable",
                "imageReason": emptyUnassessableReason ? "" : "The two ends cannot be distinguished.",
            ]
            if unassessableCoordinate {
                object["tailX"] = 0.2
            }
            return object
        }
        var object: [String: Any] = [
            "frameId": frameId,
            "judgment": "directed",
            "tailX": tailX,
            "tailY": tailY,
            "noseX": noseX,
            "noseY": noseY,
        ]
        if index == 1, let directedImageReason {
            object["imageReason"] = directedImageReason
        }
        if index == 1, let extraField {
            object[extraField.0] = extraField.1
        }
        return object
    }
    return try! JSONSerialization.data(withJSONObject: ["labels": labels])
}
