import AppKit

enum ShareHelper {
    static func share(url: URL, from view: NSView) {
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openWithDefaultApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
