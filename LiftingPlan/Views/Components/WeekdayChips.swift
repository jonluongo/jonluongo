import SwiftUI
import LiftingKit

/// A row of tappable day chips for choosing which days to train.
struct WeekdayChips: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(Weekday.displayOrder) { day in
                let isOn = selection.contains(day)
                Button {
                    toggle(day)
                } label: {
                    Text(day.shortName)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isOn ? Color.accentColor : Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.fullName)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private func toggle(_ day: Weekday) {
        if selection.contains(day) {
            selection.remove(day)
        } else {
            selection.insert(day)
        }
    }
}
