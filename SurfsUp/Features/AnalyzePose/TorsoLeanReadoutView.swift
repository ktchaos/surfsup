import SwiftUI

/// Shows the frozen image-plane torso lean at the current playhead.
///
/// The caption is always shown. The value and the side appear only when
/// `TorsoLeanReadout.make` returns a readout for this playhead. A missing sample
/// shows nothing in their place: no zero, no dash, no held value, no animation.
struct TorsoLeanReadoutView: View {
    var timeline: PoseTimeline
    var playhead: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.AnalyzePose.readoutSpacing) {
            if let readout = TorsoLeanReadout.make(at: playhead, in: timeline) {
                HStack(spacing: UIConstants.AnalyzePose.readoutSpacing) {
                    Text(readout.degreesText)
                        .font(Typography.body)
                        .monospacedDigit()
                    sideText(readout.side)
                        .font(Typography.body)
                }
            }
            Text("torsoLeanCaption")
                .font(Typography.caption)
                .multilineTextAlignment(.leading)
                .opacity(UIConstants.AnalyzePose.readoutCaptionOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(AppColors.text)
    }

    private func sideText(_ side: TorsoLeanReadout.Side) -> Text {
        switch side {
        case .left: Text("torsoLeanLeft")
        case .right: Text("torsoLeanRight")
        case .upright: Text("torsoLeanUpright")
        case .straightDown: Text("torsoLeanStraightDown")
        }
    }
}
