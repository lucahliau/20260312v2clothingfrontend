import SwiftUI
import UIKit

/// One photo for `PhotoViewer`: the URL to show plus an optional fallback.
struct PhotoViewerPhoto: Identifiable, Hashable {
    let url: URL
    var fallbackUrl: URL? = nil
    var id: URL { url }
}

/// Which photo a `PhotoViewer` opens on (drives `.fullScreenCover(item:)`).
struct PhotoViewerSelection: Identifiable {
    let photos: [PhotoViewerPhoto]
    let startIndex: Int
    var id: String { "\(startIndex)-\(photos.first?.url.absoluteString ?? "")" }
}

/// Full-screen photo pager with pinch-zoom, pan and double-tap zoom.
struct PhotoViewer: View {
    let photos: [PhotoViewerPhoto]
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss

    init(selection: PhotoViewerSelection) {
        photos = selection.photos
        _index = State(initialValue: min(max(selection.startIndex, 0), max(selection.photos.count - 1, 0)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                    PhotoViewerPage(photo: photo)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            HStack {
                if photos.count > 1 {
                    Text("\(index + 1) / \(photos.count)")
                        .font(.appDisplay(size: 15))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.appPrimaryText)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white))
                        .overlay(Circle().stroke(Color.black, lineWidth: 2.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close photo")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .statusBarHidden()
    }
}

private struct PhotoViewerPage: View {
    let photo: PhotoViewerPhoto

    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let image {
                ZoomableImageView(image: image)
            } else if failed {
                ImageRetryPlaceholder {
                    failed = false
                    attempt += 1
                }
                .frame(width: 160, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: attempt) {
            // Full-size variant (usually already in memory from the detail tile).
            var loaded = await ImageCacheService.shared.loadImage(from: photo.url)
            if loaded == nil, let fallback = photo.fallbackUrl {
                loaded = await ImageCacheService.shared.loadImage(from: fallback)
            }
            image = loaded
            failed = loaded == nil
        }
    }
}

/// UIScrollView-backed zoom: reliable pinch + pan + double-tap, and it plays
/// well inside a paging `TabView` (pans the photo while zoomed, pages at 1x).
private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            scrollView.setZoomScale(1, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
                let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}
