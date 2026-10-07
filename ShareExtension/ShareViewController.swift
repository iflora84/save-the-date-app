import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// "Share > Save the Date". Saves the first image, else the text, else the link
/// into the App Group inbox and says so. Finding the date happens in the app,
/// which has the room for text recognition and Apple Intelligence.
/// A share extension's principal class has to be a view controller; it only
/// hosts the SwiftUI view.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let model: ShareModel = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model, onDone: { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        Task { await model.receive(providers) }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum State: Equatable {
        case working, saved, nothing, failed
    }

    @Published private(set) var state: State = .working

    func receive(_ providers: [NSItemProvider]) async {
        guard let directory = SharedInbox.directory else {
            state = .failed
            return
        }
        guard let item = await firstItem(providers) else {
            state = .nothing
            return
        }
        state = SharedInbox.save(item, in: directory) ? .saved : .failed
    }

    private func firstItem(_ providers: [NSItemProvider]) async -> SharedInbox.Item? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let data = imageData(await load(provider, UTType.image)) {
                return .image(data)
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = text(await load(provider, UTType.plainText)), !text.isEmpty {
                return .text(text)
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await load(provider, UTType.url) as? URL {
                return .text(url.absoluteString)
            }
        }
        return nil
    }

    private func load(_ provider: NSItemProvider, _ type: UTType) async -> NSSecureCoding? {
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    private func imageData(_ item: NSSecureCoding?) -> Data? {
        if let url = item as? URL {
            return try? Data(contentsOf: url)
        }
        if let image = item as? UIImage {
            return image.jpegData(compressionQuality: 0.9)
        }
        return item as? Data
    }

    private func text(_ item: NSSecureCoding?) -> String? {
        if let string = item as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let attributed = item as? NSAttributedString {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

private struct ShareView: View {
    @ObservedObject var model: ShareModel
    let onDone: () -> Void

    /// The app's champagne gold; the extension can't see the app's Theme.
    private let gold: Color = Color(red: 0.839, green: 0.745, blue: 0.549)

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            symbol
            Text(title)
                .font(.system(size: 26, weight: .regular, design: .serif))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                onDone()
            } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(gold, in: Capsule())
                    .foregroundStyle(Color(red: 0.10, green: 0.08, blue: 0.03))
            }
            .disabled(model.state == .working)
        }
        .padding(28)
    }

    @ViewBuilder private var symbol: some View {
        if model.state == .working {
            ProgressView()
                .controlSize(.large)
        } else {
            Image(systemName: model.state == .saved ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 54))
                .foregroundStyle(gold)
        }
    }

    private var title: String {
        switch model.state {
        case .working:
            return "Saving…"
        case .saved:
            return "Saved to Save the Date"
        case .nothing:
            return "Nothing to save"
        case .failed:
            return "Couldn't save"
        }
    }

    private var message: String {
        switch model.state {
        case .working:
            return ""
        case .saved:
            return "Open Save the Date to check the date and add it. Nothing was uploaded."
        case .nothing:
            return "Share some text, a link or a screenshot."
        case .failed:
            return "Save the Date couldn't reach its shared folder. Update the app and try again."
        }
    }
}
