import SwiftUI

// MARK: - Backdrop

/// Full-screen dimmed scrim; tap invokes optional dismiss.
struct PopArtModalScrim: View {
    var opacity: CGFloat = 0.42
    var onTapOutside: (() -> Void)?

    var body: some View {
        Color.black.opacity(opacity)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                onTapOutside?()
            }
    }
}

// MARK: - Centered shell

/// Scrim + vertically centered content (pop-art card).
struct PopArtCenteredModal<Content: View>: View {
    var onTapOutside: (() -> Void)?
    var horizontalPadding: CGFloat = 24
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            PopArtModalScrim(onTapOutside: onTapOutside)
            VStack {
                Spacer(minLength: 0)
                content()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, horizontalPadding)
        }
    }
}

// MARK: - Card chrome

struct PopArtModalCard<Content: View>: View {
    var maxWidth: CGFloat
    @ViewBuilder var content: () -> Content

    init(maxWidth: CGFloat = 360, @ViewBuilder content: @escaping () -> Content) {
        self.maxWidth = maxWidth
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: maxWidth)
            .padding(20)
            .frame(maxWidth: .infinity)
            .popArtCardContainer()
    }
}

// MARK: - Typography

struct PopArtModalTitle: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.appDisplay(size: 20))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.appPrimaryText)
            .frame(maxWidth: .infinity)
    }
}

struct PopArtModalMessage: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.appDisplay(size: 17))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.appSecondaryText)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Buttons

struct PopArtModalPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.appDisplay(size: 17))
                .foregroundStyle(Color.appAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

/// Full-width primary action with pop-art chrome (stroke + offset shadow).
struct PopArtPrimaryActionButton: View {
    let title: String
    var systemImage: String? = "bag.fill"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                }
                Text(title)
                    .font(.appDisplay(size: 18))
                    .foregroundStyle(Color.appPrimaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .popArtCardContainer()
    }
}

struct PopArtModalSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.appDisplay(size: 17))
                .foregroundStyle(Color.appPrimaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

struct PopArtModalDestructiveButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.appDisplay(size: 17))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preset alerts

/// Single primary “OK” action (accent).
struct PopArtMessageAlert: View {
    let title: String
    let message: String
    var onDismiss: () -> Void

    var body: some View {
        PopArtCenteredModal(onTapOutside: onDismiss) {
            PopArtModalCard {
                VStack(spacing: 18) {
                    PopArtModalTitle(title)
                    PopArtModalMessage(message)
                    PopArtModalPrimaryButton(title: "OK", action: onDismiss)
                }
            }
        }
    }
}

/// Log out style: cancel + destructive.
struct PopArtConfirmDestructiveAlert: View {
    let title: String
    let message: String
    var confirmTitle: String
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        PopArtCenteredModal(onTapOutside: onCancel) {
            PopArtModalCard {
                VStack(spacing: 18) {
                    PopArtModalTitle(title)
                    PopArtModalMessage(message)
                    VStack(spacing: 8) {
                        PopArtModalSecondaryButton(title: "Cancel", action: onCancel)
                        PopArtModalDestructiveButton(title: confirmTitle, action: onConfirm)
                    }
                }
            }
        }
    }
}

// MARK: - Selection row (gender-style lists)

struct PopArtSelectionRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appPrimaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.appAccent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.appAccent.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.appAccent : Color.black.opacity(0.12), lineWidth: isSelected ? 3 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
