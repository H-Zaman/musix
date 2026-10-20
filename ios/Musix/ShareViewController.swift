import UIKit
import UniformTypeIdentifiers

/// Receives a link shared from YouTube, leaves it for the main app in the
/// shared App Group, then opens the app so it can start the download.
/// The app reads `pendingYouTubeURL` (see lib/services/shared_link_inbox.dart).
final class ShareViewController: UIViewController {
    private let appGroup = "group.com.shuvro.musix.shared"
    private let pendingKey = "pendingYouTubeURL"
    private let hostScheme = "musix-sharing://share"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        loadSharedText { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let text, !text.isEmpty else { return self.finish() }
                self.store(text)
                self.openHostApp()
            }
        }
    }

    /// A web URL if there is one, otherwise plain text that may contain a link.
    private func loadSharedText(completion: @escaping (String?) -> Void) {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                completion((item as? URL)?.absoluteString ?? (item as? String))
            }
        } else if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                completion(item as? String)
            }
        } else {
            completion(nil)
        }
    }

    private func store(_ text: String) {
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set(text, forKey: pendingKey)
        defaults?.synchronize()
    }

    /// Share extensions have no public API to open the host app; on iOS 18+
    /// going through the responder chain's UIApplication is what works.
    private func openHostApp() {
        guard let url = URL(string: hostScheme) else { return finish() }
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:]) { [weak self] _ in self?.finish() }
                return
            }
            responder = current.next
        }
        finish()
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
