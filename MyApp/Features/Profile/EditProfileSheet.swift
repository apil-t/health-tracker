import SwiftUI

struct EditProfileSheet: View {
    @Environment(HealthStore.self) private var store
    @State private var draft: Profile

    init(profile: Profile) {
        _draft = State(initialValue: profile)
    }

    var body: some View {
        let errors = HealthRules.profileErrors(draft)

        FormSheet(title: "Edit profile", canSave: errors.isEmpty && draft != store.profile) {
            store.updateProfile(draft)
        } content: {
            Section {
                TextField("Name", text: $draft.name)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                Picker("Sex", selection: $draft.sex) {
                    ForEach(Profile.Sex.allCases, id: \.self) { Text($0.rawValue) }
                }
                Stepper("Age: \(draft.age)", value: $draft.age, in: HealthRules.ageRange)
            }

            Section {
                NumberRow(title: "Height", unit: "cm", value: $draft.heightCm, format: .number)
                NumberRow(title: "Weight", unit: "kg", value: $draft.weightKg, format: .number.precision(.fractionLength(0...1)))
                NumberRow(title: "Goal weight", unit: "kg", value: $draft.goalWeightKg, format: .number.precision(.fractionLength(0...1)))
            } header: {
                Text("Body")
            } footer: {
                if errors.isEmpty {
                    Text("A new weight is saved as today’s weigh-in.")
                } else {
                    Text(errors.joined(separator: "\n")).foregroundStyle(.red)
                }
            }
        }
    }
}

/// "Height      178 cm" row with an inline number field.
private struct NumberRow<Value, F: ParseableFormatStyle>: View where F.FormatInput == Value, F.FormatOutput == String {
    let title: String
    let unit: String
    @Binding var value: Value
    let format: F

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: $value, format: format)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    EditProfileSheet(profile: HealthStore().profile).environment(HealthStore())
}
