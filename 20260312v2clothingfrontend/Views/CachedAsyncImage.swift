import OSLog
import SwiftUI

private let cachedAsyncImageLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clothing", category: "CachedAsyncImage")

/// Fill used while an image URL is resolving. Geometry-free shimmer (see
/// `ShimmerFill`) so it stays a drop-in fill in flexible layouts while looking
/// consistent with the app's skeletons.
struct GhostImagePlaceholder: View {
    var body: some View {
        ShimmerFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CachedAsyncImage: View {
    let url: URL
    var fallbackUrl: URL? = nil
    /// Optional label for logs (e.g. `"feed"` vs `"avatar"`).
    var logContext: String?
    var placeholder: () -> AnyView
    /// Shown after load completes with no image (HTTP error, decode failure, missing fallback). If `nil`, `placeholder` is used for failure too (e.g. feed ghost tile).
    var failurePlaceholder: (() -> AnyView)?
    /// When non-`nil`, set to `true` after load completes (success with image, success with fallback, or failure).
    var loadFinished: Binding<Bool>?
    /// If `true`, sets `loadFinished` to `false` at the start of each load for `url`.
    var resetsLoadingBinding: Bool
    /// Called on main actor when primary and fallback both fail and the last HTTP status was **404** (feed can drop the item).
    var onUnrecoverableHTTP404: (() -> Void)?
    /// When `true`, the loaded image is cropped to the bounding box of non-transparent pixels (off the main thread, cached per URL).
    /// Use for background-removed PNGs where the garment doesn't fill the canvas (e.g. wardrobe hangers, shoe rack).
    var tightCrop: Bool
    /// How the image fills its frame. Defaults to `.fill` for parity with the legacy callers; wardrobe views pass `.fit`.
    var contentMode: ContentMode

    @State private var image: UIImage?
    @State private var loadCompletedForCurrentURL = false

    init(
        url: URL,
        fallbackUrl: URL? = nil,
        logContext: String? = nil,
        loadFinished: Binding<Bool>? = nil,
        resetsLoadingBinding: Bool = true,
        failurePlaceholder: (() -> AnyView)? = nil,
        onUnrecoverableHTTP404: (() -> Void)? = nil,
        tightCrop: Bool = false,
        contentMode: ContentMode = .fill,
        placeholder: @escaping () -> AnyView = { AnyView(GhostImagePlaceholder()) }
    ) {
        self.url = url
        self.fallbackUrl = fallbackUrl
        self.logContext = logContext
        self.loadFinished = loadFinished
        self.resetsLoadingBinding = resetsLoadingBinding
        self.failurePlaceholder = failurePlaceholder
        self.onUnrecoverableHTTP404 = onUnrecoverableHTTP404
        self.tightCrop = tightCrop
        self.contentMode = contentMode
        self.placeholder = placeholder
        let initial = ImageCacheService.shared.image(for: url)
        if tightCrop, let initial, let cached = TrimmedImageCache.shared.get(url.absoluteString) {
            _image = State(initialValue: cached)
        } else {
            _image = State(initialValue: initial)
        }
    }

    private var logPrefix: String {
        if let logContext, !logContext.isEmpty {
            return "[\(logContext)] "
        }
        return ""
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if loadCompletedForCurrentURL, let failurePlaceholder {
                failurePlaceholder()
            } else {
                placeholder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            if image != nil {
                cachedAsyncImageLog.debug("\(logPrefix)Using memory cache url=\(url.absoluteString, privacy: .public)")
                loadFinished?.wrappedValue = true
            } else {
                cachedAsyncImageLog.debug("\(logPrefix)No memory cache; will load url=\(url.absoluteString, privacy: .public)")
            }
        }
        .task(id: url) {
            await MainActor.run {
                loadCompletedForCurrentURL = false
            }
            if tightCrop, let cached = TrimmedImageCache.shared.get(url.absoluteString) {
                image = cached
            } else {
                image = ImageCacheService.shared.image(for: url)
            }
            if resetsLoadingBinding {
                loadFinished?.wrappedValue = (image != nil)
            }
            if image != nil {
                cachedAsyncImageLog.debug("\(logPrefix)Task start: had memory image url=\(url.absoluteString, privacy: .public)")
            } else {
                cachedAsyncImageLog.debug("\(logPrefix)Task start: fetching url=\(url.absoluteString, privacy: .public)")
            }
            var (loaded, primaryStatus) = await ImageCacheService.shared.loadImageWithStatus(from: url)
            var lastFailureStatus = primaryStatus
            if loaded == nil, let fallback = fallbackUrl {
                cachedAsyncImageLog.debug("\(logPrefix)Primary URL produced no image; trying fallback primary=\(url.absoluteString, privacy: .public) fallback=\(fallback.absoluteString, privacy: .public)")
                let (fbImage, fbStatus) = await ImageCacheService.shared.loadImageWithStatus(from: fallback)
                loaded = fbImage
                if fbStatus != nil {
                    lastFailureStatus = fbStatus
                }
            }
            if loaded == nil {
                let fb = fallbackUrl?.absoluteString ?? "nil"
                cachedAsyncImageLog.error("\(logPrefix)No picture after load (decode failed or HTTP error). primary=\(url.absoluteString, privacy: .public) fallback=\(fb, privacy: .public)")
            } else {
                cachedAsyncImageLog.debug("\(logPrefix)Picture loaded OK url=\(url.absoluteString, privacy: .public)")
            }
            await MainActor.run {
                image = loaded
                loadCompletedForCurrentURL = true
                loadFinished?.wrappedValue = true
                if loaded == nil, lastFailureStatus == 404 {
                    onUnrecoverableHTTP404?()
                }
            }
            if tightCrop, let loaded {
                let key = url.absoluteString
                if let cached = TrimmedImageCache.shared.get(key) {
                    await MainActor.run { image = cached }
                } else {
                    let trimmed = await Task.detached(priority: .userInitiated) {
                        loaded.trimmedToOpaque()
                    }.value
                    TrimmedImageCache.shared.set(trimmed, for: key)
                    await MainActor.run { image = trimmed }
                }
            }
        }
    }
}
