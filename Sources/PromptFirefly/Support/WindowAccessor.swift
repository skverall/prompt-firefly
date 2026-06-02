import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> AccessorView {
        AccessorView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: AccessorView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveWindow()
    }
}

final class AccessorView: NSView {
    var onResolve: (NSWindow) -> Void

    init(onResolve: @escaping (NSWindow) -> Void) {
        self.onResolve = onResolve
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveWindow()
    }

    func resolveWindow() {
        guard let window else { return }
        DispatchQueue.main.async {
            self.onResolve(window)
        }
    }
}
