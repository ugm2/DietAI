import SwiftUI

// MARK: - Product Not Found View

struct ProductNotFoundView: View {
    let message: String
    let onTryAgain: () -> Void
    let onEnterManually: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            // Title
            Text("Product Not Found")
                .font(.title2)
                .fontWeight(.semibold)

            // Message
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Suggestions
            VStack(alignment: .leading, spacing: 12) {
                suggestionRow(icon: "arrow.clockwise", text: "Try scanning the barcode again")
                suggestionRow(icon: "character.cursor.ibeam", text: "Enter the product details manually")
                suggestionRow(icon: "barcode", text: "Make sure the barcode is clear and well-lit")
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
            .padding(.horizontal)

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                Button {
                    onTryAgain()
                } label: {
                    HStack {
                        Image(systemName: "barcode.viewfinder")
                        Text("Try Again")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
                }

                Button {
                    onEnterManually()
                } label: {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Enter Manually")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .cornerRadius(14)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func suggestionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    ProductNotFoundView(
        message: "This product isn't in our database yet.",
        onTryAgain: {},
        onEnterManually: {}
    )
}
