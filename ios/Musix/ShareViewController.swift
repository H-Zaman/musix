import UIKit
import Social
import MobileCoreServices

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedURL()
    }

    private func handleSharedURL() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachment = extensionItem.attachments?.first else {
            self.exit()
            return
        }

        if attachment.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
            attachment.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil) { (url, error) in
                if let sharedURL = url as? URL {
                    self.saveToAppGroup(url: sharedURL)
                    self.redirectToMainApp()
                } else {
                    self.exit()
                }
            }
        } else {
            self.exit()
        }
    }

    private func saveToAppGroup(url: URL) {
        // Use the App Group ID defined in Signing & Capabilities
        if let userDefaults = UserDefaults(suiteName: "group.com.shuvro.musix.shared") {
            userDefaults.set(url.absoluteString, forKey: "pendingYouTubeURL")
            userDefaults.synchronize()
        }
    }

    private func redirectToMainApp() {
        // Custom URL scheme to trigger app open
        let urlScheme = URL(string: "musix-sharing://")!

        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(urlScheme, options: [:], completionHandler: { _ in
                    self.exit()
                })
                return
            }
            responder = responder?.next
        }

        // Fallback
        self.exit()
    }

    private func exit() {
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
