import SwiftUI

struct ItemDetailView: View {
    let item: Item

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                photosSection
                metadataSection
            }
            .padding()
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var photosSection: some View {
        Group {
            if item.imageUrls.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.gray.opacity(0.2))
                    .frame(height: 200)
                    .overlay {
                        Text("No image")
                            .foregroundStyle(.secondary)
                    }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(item.imageUrls, id: \.self) { urlString in
                            if let url = URL(string: urlString) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle()
                                        .fill(.gray.opacity(0.2))
                                }
                                .frame(width: 280, height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let brand = item.brand, !brand.isEmpty {
                metadataRow(label: "Brand", value: brand)
            }
            if let priceDouble = item.priceDouble {
                metadataRow(label: "Price", value: formatPrice(priceDouble))
            }
            if let category = item.category, !category.isEmpty {
                metadataRow(label: "Category", value: category)
            }
            if let description = item.description, !description.isEmpty {
                metadataRow(label: "Description", value: description)
            }
            if let sizes = item.sizes, !sizes.isEmpty {
                metadataRow(label: "Sizes", value: sizes.joined(separator: ", "))
            }
            if let colors = item.colors, !colors.isEmpty {
                metadataRow(label: "Colors", value: colors.joined(separator: ", "))
            }
            if let createdAt = item.createdAt, !createdAt.isEmpty {
                metadataRow(label: "Added", value: createdAt)
            }
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }

    private func formatPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}
