import CoreGraphics
import SwiftUI

nonisolated enum AppConstants {
    nonisolated enum UI {
        static let spacing: CGFloat = 16
        static let cornerRadius: CGFloat = 12
        static let controlHeight: CGFloat = 44
        static let poseLineWidth: CGFloat = 3
        static let posePointSize: CGFloat = 6
    }
}

enum Typography {
    static let title = Font.title2
    static let body = Font.body
}

enum AppColors {
    static let background = Color.black
    static let text = Color.white
    static let accent = Color(red: 0.18, green: 0.55, blue: 0.85)
    static let pose = Color.yellow
}
