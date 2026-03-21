import SwiftUI

/// Shimmer fill used while an image URL is resolving (matches ghost palette).
struct GhostImagePlaceholder: View {
    var body: some View {
        GeometryReader { geo in
            GhostBlock(height: max(geo.size.height, 1), cornerRadius: 8)
        }
    }
}

struct CachedAsyncImage: View {
    let url: URL
    var fallbackUrl: URL? = nil
    var placeholder: () -> AnyView
    /// When non-`nil`, set to `true` after load completes (success with image, success with fallback, or failure).
    var loadFinished: Binding<Bool>?
    /// If `true`, sets `loadFinished` to `false` at the start of each load for `url`.
    var resetsLoadingBinding: Bool

    @State private var image: UIImage?

    init(
        url: URL,
        fallbackUrl: URL? = nil,
        loadFinished: Binding<Bool>? = nil,
        resetsLoadingBinding: Bool = true,
        placeholder: @escaping () -> AnyView = { AnyView(GhostImagePlaceholder()) }
    ) {
        self.url = url
        self.fallbackUrl = fallbackUrl
        self.loadFinished = loadFinished
        self.resetsLoadingBinding = resetsLoadingBinding
        self.placeholder = placeholder
        _image = State(initialValue: ImageCacheService.shared.image(for: url))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
            }
        }
        .onAppear {
            if image != nil {
                loadFinished?.wrappedValue = true
            }
        }
        .task(id: url) {
            image = ImageCacheService.shared.image(for: url)
            if resetsLoadingBinding {
                loadFinished?.wrappedValue = (image != nil)
            }
            var loaded = await ImageCacheService.shared.loadImage(from: url)
            if loaded == nil, let fallback = fallbackUrl {
                loaded = await ImageCacheService.shared.loadImage(from: fallback)
            }
            await MainActor.run {
                image = loaded
                loadFinished?.wrappedValue = true
            }
        }
    }
}
