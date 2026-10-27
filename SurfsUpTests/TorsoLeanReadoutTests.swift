import Foundation
import Testing
@testable import SurfsUp

/// Covers the presentation mapper only. Timelines are synthetic `Landmark` points in
/// stored upright coordinates (origin bottom-left, `x` to the viewer's right, `y` up).
/// No video is loaded, no view is rendered, and no `TestStore` is used.
struct TorsoLeanReadoutTests {
    // MARK: - User Story 1: a sampled moment shows the value and the side

    @Test func neckRightOfRootReadsRight() {
        let timeline = singleWindow(neck: (0.75, 0.5), root: (0.25, 0.5))

        let readout = TorsoLeanReadout.make(at: 0.25, in: timeline)

        #expect(readout?.side == .right)
        #expect(readout?.degreesText == "90.0°")
    }

    @Test func neckLeftOfRootReadsLeft() {
        let timeline = singleWindow(neck: (0.25, 0.5), root: (0.75, 0.5))

        let readout = TorsoLeanReadout.make(at: 0.25, in: timeline)

        #expect(readout?.side == .left)
        #expect(readout?.degreesText == "-90.0°")
    }

    @Test func neckDirectlyAboveRootReadsUprightAtZero() {
        let timeline = singleWindow(neck: (0.5, 0.75), root: (0.5, 0.25))

        let readout = TorsoLeanReadout.make(at: 0.25, in: timeline)

        #expect(readout?.side == .upright)
        #expect(readout?.degreesText == "0.0°")
    }

    @Test func neckDirectlyBelowRootReadsStraightDownNotLeftOrRight() {
        let timeline = singleWindow(neck: (0.5, 0.25), root: (0.5, 0.75))
        let sample = ImagePlaneTorsoLean.sample(at: 0.25, in: timeline)

        let readout = TorsoLeanReadout.make(at: 0.25, in: timeline)

        #expect(readout?.side == .straightDown)
        #expect(readout?.side != .left)
        #expect(readout?.side != .right)
        #expect(readout?.degreesText == sample.map { String(format: "%.1f°", $0.angleDegrees) })
        #expect(readout?.degreesText == "180.0°" || readout?.degreesText == "-180.0°")
    }

    @Test func degreeTextIsTheSampleRoundedToOneDecimal() {
        let timeline = singleWindow(neck: (0.7, 0.8), root: (0.4, 0.3))
        let sample = ImagePlaneTorsoLean.sample(at: 0.25, in: timeline)

        let readout = TorsoLeanReadout.make(at: 0.25, in: timeline)

        #expect(sample != nil)
        #expect(readout?.degreesText == sample.map { String(format: "%.1f°", $0.angleDegrees) })
        #expect(readout?.side == .right)
        #expect(TorsoLeanReadout.fractionDigits == 1)
        let text = readout?.degreesText ?? ""
        #expect(text.hasSuffix("°"))
        let fraction = text.dropLast().split(separator: ".", omittingEmptySubsequences: false).last ?? ""
        let fractionIsOneDigit = fraction.count == 1 && fraction.allSatisfy { $0.isNumber }
        #expect(fractionIsOneDigit)
    }

    @Test func nearZeroNegativeSamplePrintsUnsignedZeroAndKeepsSideLeft() {
        let timeline = singleWindow(neck: (0.5 - 1.0 / 4096, 0.75), root: (0.5, 0.25))
        let sample = ImagePlaneTorsoLean.sample(at: 0.25, in: timeline)

        let readout = TorsoLeanReadout.make(at: 0.25, in: timeline)

        #expect((sample?.angleDegrees ?? 0) < 0)
        #expect((sample?.angleDegrees ?? -1) > -0.05)
        #expect(sample?.ordinarySign == .left)
        #expect(readout?.degreesText == "0.0°")
        #expect(readout?.degreesText != "-0.0°")
        #expect(readout?.side == .left)
    }

    @Test func halfOpenBoundaryReadsTheNextWindow() {
        let duration = 1.0
        let leftWindow = frame(start: 0, end: 0.5, duration: duration, neck: (0.25, 0.5), root: (0.75, 0.5))
        let rightWindow = frame(start: 0.5, end: 1, duration: duration, neck: (0.75, 0.5), root: (0.25, 0.5))
        let timeline = PoseTimeline(clipDuration: duration, observations: [leftWindow, rightWindow])!

        #expect(TorsoLeanReadout.make(at: 0.25, in: timeline)?.side == .left)
        #expect(TorsoLeanReadout.make(at: 0.5, in: timeline)?.side == .right)
    }

    @Test func readingTheSameMomentTwiceIsEqualAndLeavesTheTimelineUnchanged() {
        let timeline = singleWindow(neck: (0.7, 0.8), root: (0.4, 0.3))
        let before = timeline

        let first = TorsoLeanReadout.make(at: 0.25, in: timeline)
        let second = TorsoLeanReadout.make(at: 0.25, in: timeline)

        #expect(first != nil)
        #expect(first == second)
        #expect(timeline == before)
    }

    // MARK: - User Story 2: a missing sample shows nothing and holds nothing

    @Test func noObservationAtThePlayheadReadsNil() {
        let duration = 1.0
        let window = frame(start: 0, end: 0.5, duration: duration, neck: (0.75, 0.5), root: (0.25, 0.5))
        let timeline = PoseTimeline(clipDuration: duration, observations: [window])!

        #expect(TorsoLeanReadout.make(at: 0.75, in: timeline) == nil)
    }

    @Test func missingBodyReadsNil() {
        let duration = 1.0
        let window = FrameObservation(start: 0, end: 1, clipDuration: duration, body: nil)!
        let timeline = PoseTimeline(clipDuration: duration, observations: [window])!

        #expect(TorsoLeanReadout.make(at: 0.25, in: timeline) == nil)
    }

    @Test func missingNeckReadsNil() {
        let duration = 1.0
        let window = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: body([point(.root, x: 0.4, y: 0.3), point(.nose, x: 0.4, y: 0.9)])
        )!
        let timeline = PoseTimeline(clipDuration: duration, observations: [window])!

        #expect(TorsoLeanReadout.make(at: 0.25, in: timeline) == nil)
    }

    @Test func missingRootReadsNil() {
        let duration = 1.0
        let window = FrameObservation(
            start: 0,
            end: 1,
            clipDuration: duration,
            body: body([point(.neck, x: 0.4, y: 0.8), point(.nose, x: 0.4, y: 0.9)])
        )!
        let timeline = PoseTimeline(clipDuration: duration, observations: [window])!

        #expect(TorsoLeanReadout.make(at: 0.25, in: timeline) == nil)
    }

    @Test func coincidentNeckAndRootReadNil() {
        let timeline = singleWindow(neck: (0.5, 0.5), root: (0.5, 0.5))

        #expect(TorsoLeanReadout.make(at: 0.25, in: timeline) == nil)
    }

    @Test func playheadAtTheLastWindowEndReadsNil() {
        let timeline = singleWindow(neck: (0.75, 0.5), root: (0.25, 0.5))

        #expect(TorsoLeanReadout.make(at: 0.75, in: timeline) != nil)
        #expect(TorsoLeanReadout.make(at: 1.0, in: timeline) == nil)
    }

    @Test func gapBetweenSampledWindowsHoldsNothing() {
        let duration = 3.0
        let leftWindow = frame(start: 0, end: 1, duration: duration, neck: (0.25, 0.5), root: (0.75, 0.5))
        let gap = FrameObservation(start: 1, end: 2, clipDuration: duration, body: nil)!
        let rightWindow = frame(start: 2, end: 3, duration: duration, neck: (0.75, 0.5), root: (0.25, 0.5))
        let timeline = PoseTimeline(clipDuration: duration, observations: [leftWindow, gap, rightWindow])!
        let before = timeline

        let first = TorsoLeanReadout.make(at: 0.5, in: timeline)
        let duringGap = TorsoLeanReadout.make(at: 1.5, in: timeline)
        let last = TorsoLeanReadout.make(at: 2.5, in: timeline)

        #expect(first?.side == .left)
        #expect(duringGap == nil)
        #expect(last?.side == .right)
        #expect(timeline == before)
    }

    // MARK: - Helpers

    private typealias StoredPoint = (x: Double, y: Double)

    private func singleWindow(neck: StoredPoint, root: StoredPoint) -> PoseTimeline {
        let duration = 1.0
        let window = frame(start: 0, end: 1, duration: duration, neck: neck, root: root)
        return PoseTimeline(clipDuration: duration, observations: [window])!
    }

    private func frame(
        start: TimeInterval,
        end: TimeInterval,
        duration: TimeInterval,
        neck: StoredPoint,
        root: StoredPoint
    ) -> FrameObservation {
        FrameObservation(
            start: start,
            end: end,
            clipDuration: duration,
            body: body([point(.neck, x: neck.x, y: neck.y), point(.root, x: root.x, y: root.y)])
        )!
    }

    private func body(_ landmarks: [Landmark]) -> BodyObservation? {
        BodyObservation(landmarks: landmarks, selectionArea: 0.1)
    }

    private func point(_ joint: JointName, x: Double, y: Double) -> Landmark {
        Landmark(joint: joint, x: x, y: y, confidence: 1)!
    }
}
