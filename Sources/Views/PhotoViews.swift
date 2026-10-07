import SwiftUI
import UIKit

/// Drag and pinch a photo inside a circle, then keep what the circle shows as a
/// square image for the cards.
struct PhotoCropView: View {
    let image: UIImage
    let onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private static let circleSide: CGFloat = 300
    private static let outputSide: CGFloat = 720
    private static let maxScale: CGFloat = 5

    init(image: UIImage, onDone: @escaping (UIImage) -> Void) {
        self.image = image
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                cropArea
                VStack {
                    Spacer()
                    Text("Drag to move · Pinch to zoom")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.7))
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("Adjust photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use photo") {
                        onDone(cropped())
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var cropArea: some View {
        let side = PhotoCropView.circleSide
        let size = displaySize
        return Image(uiImage: image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .offset(offset)
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                // Dim everything outside the circle.
                ZStack {
                    Color.black.opacity(0.6)
                    Circle()
                        .frame(width: side, height: side)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .allowsHitTesting(false)
            }
            .overlay {
                Circle()
                    .stroke(Theme.goldLine, lineWidth: 1.5)
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)
            }
            .gesture(SimultaneousGesture(dragGesture, zoomGesture))
    }

    /// At scale 1 the image just covers the circle; zooming grows it from there.
    private var displaySize: CGSize {
        let side = PhotoCropView.circleSide
        let width = max(image.size.width, 1)
        let height = max(image.size.height, 1)
        let fill = max(side / width, side / height)
        return CGSize(width: width * fill * scale, height: height * fill * scale)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clamped(CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                ))
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), PhotoCropView.maxScale)
                offset = clamped(offset)
            }
            .onEnded { _ in
                lastScale = scale
                lastOffset = offset
            }
    }

    /// Keeps the circle covered: the image edge may never move inside it.
    private func clamped(_ proposed: CGSize) -> CGSize {
        let side = PhotoCropView.circleSide
        let size = displaySize
        let maxX = max(0, (size.width - side) / 2)
        let maxY = max(0, (size.height - side) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func cropped() -> UIImage {
        let side = PhotoCropView.circleSide
        let output = PhotoCropView.outputSide
        let factor = output / side
        let size = displaySize
        let origin = CGPoint(
            x: ((side - size.width) / 2 + offset.width) * factor,
            y: ((side - size.height) / 2 + offset.height) * factor
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: output, height: output), format: format).image { _ in
            image.draw(in: CGRect(x: origin.x, y: origin.y, width: size.width * factor, height: size.height * factor))
        }
    }
}

/// A photo filling the screen on black. Pinch to zoom, double tap to reset.
struct PhotoViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    init(image: UIImage) {
        self.image = image
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value.magnification, 1), 4)
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(Theme.spring) {
                        scale = 1
                        lastScale = 1
                    }
                }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .accessibilityLabel("Close")
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }
}

/// Picked photos are kept at most this size so the full-screen view stays sharp
/// without filling the phone.
enum PhotoSizing {
    static let fullMaxSide: CGFloat = 1600

    static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        if longest <= maxSide {
            return image
        }
        let factor = maxSide / longest
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
