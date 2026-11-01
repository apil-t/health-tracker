import SwiftUI

// Design tokens from the Figma file. The brand green (#167C68) is the AccentColor asset.
extension Color {
    static let heart = Color(red: 0.820, green: 0.412, blue: 0.447)    // #D16972
    static let sleep = Color(red: 0.396, green: 0.596, blue: 0.773)    // #6598C5
    static let lavender = Color(red: 0.608, green: 0.518, blue: 0.737) // #9B84BC
    static let carbs = Color(red: 0.784, green: 0.569, blue: 0.333)    // #C89155
    static let card = Color(.secondarySystemGroupedBackground)
}

extension View {
    /// Rounded card from the design. Pass a tint for the soft coloured variant.
    func card(_ tint: Color? = nil, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint?.opacity(0.12) ?? .card, in: .rect(cornerRadius: 22))
    }
}

// Model → icon/colour mapping kept here so the models stay UI-free.

extension Workout.Kind {
    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .mobility: "figure.flexibility"
        case .other: "figure.mixed.cardio"
        }
    }

    var color: Color {
        switch self {
        case .run: .accentColor
        case .walk: .sleep
        case .mobility: .lavender
        case .other: .carbs
        }
    }
}

extension Meal.Kind {
    var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .snack: "carrot"
        case .dinner: "moon"
        }
    }
}

extension Nutrient {
    var color: Color {
        switch kind {
        case .carbs: .carbs
        case .fat: .lavender
        default: .accentColor
        }
    }
}
